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

Three new migrations, in order:

### Migration A: Create `users` table

```sql
CREATE TABLE users (
    id   UUID PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);
```

### Migration B: Seed a default user and add `user_id` to existing tables

This migration handles the transition for existing data:

1. Insert a default user with a fixed, well-known UUID (e.g. `00000000-0000-0000-0000-000000000001`) and name `"default"`.
2. Add `user_id UUID NOT NULL DEFAULT '<default-uuid>' REFERENCES users(id)` to `feeds`.
3. Add `user_id UUID NOT NULL DEFAULT '<default-uuid>' REFERENCES users(id)` to `push_subscriptions`.
4. All existing rows automatically receive the default user's ID via the column default.
5. Drop the column defaults afterward (they shouldn't be implicit going forward).
6. Drop the existing `UNIQUE` constraint on `feeds.url`; add `UNIQUE(url, user_id)` so different users can subscribe to the same feed independently.

> SQLite doesn't support `ALTER COLUMN DROP DEFAULT` or `DROP CONSTRAINT` directly,
> so step 5 and 6 require recreating the affected tables (standard SQLite migration pattern).

---

## 2. Regenerate Entities

After writing the migrations above, run:

```sh
just gen-entities
```

This regenerates `src/entities/users.rs`, `src/entities/feeds.rs`, and `src/entities/push_subscriptions.rs` with the correct SeaORM models and relations.

---

## 3. Auth Extractor (Axum)

Add a custom Axum extractor `AuthUser` (in `src/main.rs` or a new `src/auth.rs`):

```rust
struct AuthUser {
    user_id: Uuid,
}
```

Implementation:
1. Read the `Authorization` header value.
2. Parse it as a UUID — return `401` if missing or not a valid UUID.
3. Query `SELECT id FROM users WHERE id = ?` — return `401` if not found.
4. Return `AuthUser { user_id }`.

The extractor needs DB access, so it implements `FromRequestParts` using `axum::extract::FromRef` to pull `State<AppState>`.

---

## 4. New Endpoint: `POST /api/users`

**No auth required** (this is how you get a user in the first place).

Request body:
```json
{ "name": "alice" }
```

Handler:
1. Validate that `name` is non-empty.
2. Generate a new UUID v4 for the user ID.
3. Insert into `users`; return `409 Conflict` if the name is already taken.
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

Feed rows are per-user (each user has their own feed row), but the actual fetched content (posts) is shared/deduplicated by URL. The sync logic stays the same, but push notifications must be scoped:

- After inserting new posts for a feed, send push notifications only to subscriptions where `push_subscriptions.user_id = feeds.user_id`.

---

## 7. File Checklist

| File | Change |
|---|---|
| `migration/src/<timestamp>_create_users.rs` | New migration: create `users` table |
| `migration/src/<timestamp>_add_user_id.rs` | New migration: seed default user, add `user_id` to `feeds` + `push_subscriptions`, fix unique constraint |
| `migration/src/lib.rs` | Register both new migrations |
| `src/entities/` | Regenerated via `just gen-entities` — do not edit manually |
| `src/main.rs` | Add `AuthUser` extractor; add `POST /api/users` handler; update all scoped handlers; update sync worker push dispatch |

---

## 8. Out of Scope

- No changes to the React UI or Flutter app (they would need to send the `Authorization` header, but that's a separate task)
- No password hashing, JWT, or OAuth
- No admin endpoints
- No user deletion or update endpoints
