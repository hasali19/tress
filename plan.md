# Plan: Multi-User Accounts

## Overview

Scope all data (feeds, posts, push subscriptions) to individual users.
Auth is simple: every request must include `Authorization: <user_id>` (a UUID).
If the header is missing or malformed, return `401 Unauthorized`.
No user registration endpoint — users are created on first use (auto-provision).

---

## 1. Database Migrations

### Migration 1: Create `users` table

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY
);
```

Simple table — no passwords, just a stable identifier.

### Migration 2: Add `user_id` to `feeds` and `push_subscriptions`

- Add `user_id UUID NOT NULL REFERENCES users(id)` to `feeds`
- Add `user_id UUID NOT NULL REFERENCES users(id)` to `push_subscriptions`
- Drop the existing `UNIQUE` constraint on `feeds.url`; replace it with `UNIQUE(url, user_id)` so different users can subscribe to the same feed independently

Posts are linked to feeds (via `feed_id`) so they are implicitly scoped to a user already. No change needed to the posts table.

---

## 2. New Entity: `users`

Create `src/entities/users.rs` with a SeaORM model mirroring the table above.

Update `src/entities/mod.rs` to expose the new module and `prelude`.

---

## 3. Auth Extractor (Axum)

Add a custom Axum extractor `AuthUser` in `src/main.rs` (or a new `src/auth.rs`):

```rust
struct AuthUser {
    user_id: Uuid,
}
```

Implementation steps:
1. Read the `Authorization` header value.
2. Parse it as a UUID.
3. Return `401` if missing or invalid.
4. Upsert a row in `users` (insert-or-ignore) so users are auto-provisioned on first request.
5. Return `AuthUser { user_id }`.

The extractor needs access to the DB, so it will implement `FromRequestParts<Arc<App>>` (or use `State` injection via `axum::extract::FromRef`).

---

## 4. Update API Handlers

Pass `AuthUser` as an extractor argument to every handler that reads or writes user-scoped data.

### GET `/api/feeds`
- Filter: `WHERE user_id = ?`

### POST `/api/feeds`
- Insert feed with `user_id = auth.user_id`
- Unique conflict is now `(url, user_id)` — OK to insert if another user already has the same feed URL (each user gets their own row)
- Trigger sync only for this user's new feed

### GET `/api/feeds/{id}`
- Add `WHERE user_id = ?` to the lookup; return `404` if not found or belongs to another user

### GET `/api/posts`
- Join posts → feeds, filter `feeds.user_id = ?`

### GET `/api/posts/{id}`
- Join posts → feeds, filter `feeds.user_id = ?`; return `404` if inaccessible

### POST `/api/push_subscriptions`
- Insert with `user_id = auth.user_id`

---

## 5. Sync Worker Adjustments

The sync worker currently processes all feeds globally. It must be updated to:
- Query `SELECT DISTINCT user_id FROM feeds` (or just process all feeds, since feed data itself is not user-specific — only the association is)
- Continue to process all feeds regardless of user; only the push notifications need to be scoped: send only to subscriptions where `user_id` matches the feed's `user_id`

Concretely:
- After inserting new posts for a feed, look up push subscriptions where `user_id = feed.user_id` and notify only those.

---

## 6. `SyncRequest` Update

The `SyncRequest` enum / message currently carries a feed ID. No structural change needed — the user scoping is handled by the DB query inside the sync handler.

---

## 7. File Checklist

| File | Change |
|---|---|
| `migration/src/` | Add two new migration files |
| `src/entities/users.rs` | New SeaORM entity |
| `src/entities/mod.rs` | Expose `users` module |
| `src/main.rs` | Add `AuthUser` extractor; update all handlers; update sync worker push dispatch |

---

## 8. Out of Scope

- No changes to the React UI or Flutter app (they would need to send the `Authorization` header, but that's a separate concern)
- No password hashing, JWT, or OAuth
- No admin endpoints
- No user deletion
