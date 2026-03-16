# Plan: Multi-User Accounts

## Overview

Scope all data (feeds, posts, push subscriptions) to individual users.
Auth is simple: every request must include `Authorization: <user_id>` (a UUID).
If the header is missing, malformed, or doesn't match any known user, return `401 Unauthorized`.
Users are created explicitly via a new endpoint — no auto-provisioning.

> **Entity generation rule:** Never edit `src/entities/` directly.
> After writing migrations, run `just gen-entities` to regenerate them.

---

## 1. Database Migrations

Two new migration files, written in Rust using the `sea-orm-migration` library, following the same pattern as the existing migrations.

### Migration A: Create `users` table

Use `SchemaManager::create_table` to create:

```
users
  id   UUID  PK
  name TEXT  NOT NULL UNIQUE
```

`down` drops the table.

### Migration B: Seed default user + add `user_id` to existing tables

This migration handles the transition for existing data. All steps run inside a single `up` function:

1. **Generate a UUID** at runtime: `let default_user_id = Uuid::new_v4();`
   - Add `uuid` to `migration/Cargo.toml` (it's already in the main workspace with the `v4` feature).

2. **Insert the default user** using `manager.get_connection()` and a `Query::insert` statement:
   ```rust
   Query::insert()
       .into_table("users")
       .columns(["id", "name"])
       .values_panic([default_user_id.to_string().into(), "default".into()])
   ```

3. **Recreate `feeds` table** with `user_id`:
   - Because SQLite doesn't support `ADD COLUMN NOT NULL` without a default or `DROP/MODIFY CONSTRAINT`, the standard approach is to recreate the table:
     - Create `feeds_new` with the same columns plus `user_id UUID NOT NULL` and a foreign key to `users(id)`, and with the unique constraint changed from `UNIQUE(url)` to `UNIQUE(url, user_id)`.
     - `INSERT INTO feeds_new SELECT *, '<generated_uuid>' FROM feeds`
     - Drop `feeds`, rename `feeds_new` → `feeds`.

4. **Recreate `push_subscriptions` table** with `user_id` similarly:
   - Create `push_subscriptions_new` with `user_id UUID NOT NULL` referencing `users(id)`.
   - Copy existing rows with the generated UUID.
   - Drop and rename.

`down` is not strictly required (existing migrations don't always implement it), but if provided: drop the `user_id` column from both tables (via table recreation) and delete the default user.

---

## 2. Regenerate Entities

After writing both migrations, run:

```sh
just gen-entities
```

This regenerates `src/entities/users.rs`, `src/entities/feeds.rs`, and `src/entities/push_subscriptions.rs`. Do not edit these files manually.

---

## 3. Auth Extractor (Axum)

Add a custom Axum extractor `AuthUser` in `src/main.rs` (or a new `src/auth.rs`):

```rust
struct AuthUser {
    user_id: Uuid,
}
```

Implementation:
1. Read the `Authorization` header value.
2. Parse it as a UUID — return `401` if missing or not a valid UUID.
3. Query `SELECT id FROM users WHERE id = ?` — return `401` if no row found.
4. Return `AuthUser { user_id }`.

The extractor implements `FromRequestParts` using `axum::extract::FromRef` to access `State<AppState>` and the DB connection.

---

## 4. New Endpoint: `POST /api/users`

**No auth required.**

Request body:
```json
{ "name": "alice" }
```

Handler:
1. Validate that `name` is non-empty.
2. Generate a new `Uuid::new_v4()` for the user ID.
3. Insert into `users`; return `409 Conflict` if the name is already taken (unique constraint violation).
4. Return `201 Created` with:
   ```json
   { "id": "<uuid>", "name": "alice" }
   ```

---

## 5. Update Existing API Handlers

Add `AuthUser` as an extractor argument to every handler that reads or writes user-scoped data.

| Endpoint | Change |
|---|---|
| `GET /api/feeds` | Filter `WHERE user_id = ?` |
| `POST /api/feeds` | Insert with `user_id`; unique conflict is now `(url, user_id)` |
| `GET /api/feeds/{id}` | Add `AND user_id = ?`; return `404` if not found or owned by another user |
| `GET /api/posts` | Join posts → feeds, filter `feeds.user_id = ?` |
| `GET /api/posts/{id}` | Join posts → feeds, filter `feeds.user_id = ?`; return `404` if inaccessible |
| `POST /api/push_subscriptions` | Insert with `user_id` |

---

## 6. Sync Worker Adjustments

Feed rows are per-user, but the actual fetched content (posts) is deduplicated by URL across all users. The sync logic stays the same, but push notifications must be scoped:

- After inserting new posts for a feed, send push notifications only to subscriptions where `push_subscriptions.user_id = feeds.user_id`.

---

## 7. File Checklist

| File | Change |
|---|---|
| `migration/Cargo.toml` | Add `uuid = { version = "1", features = ["v4"] }` |
| `migration/src/<ts>_create_users.rs` | New migration: create `users` table |
| `migration/src/<ts>_add_user_id.rs` | New migration: seed default user, add `user_id` to `feeds` + `push_subscriptions` via table recreation |
| `migration/src/lib.rs` | Register both new migrations |
| `src/entities/` | Regenerated via `just gen-entities` — do not edit manually |
| `src/main.rs` | Add `AuthUser` extractor; add `POST /api/users` handler; update all scoped handlers; update sync worker push dispatch |

---

## 8. Out of Scope

- No changes to the React UI or Flutter app
- No password hashing, JWT, or OAuth
- No admin endpoints
- No user deletion or update endpoints
