# Plan: OIDC/OAuth Authentication

## Overview

Add OIDC/OAuth authentication to Tress so that the server can be protected behind an identity provider like Authelia, Authentik, or any standards-compliant OIDC provider. When auth is configured, all API and UI routes are protected; unauthenticated requests are redirected to the provider's login page.

Since Tress is a single-user self-hosted app, we need only verify _that_ a user authenticated successfully — we do not need multi-tenancy or per-user data isolation.

---

## Configuration

Authentication is **opt-in**: if no OIDC config is provided the server runs as today (no auth). Configuration is provided via environment variables (consistent with the existing `DATABASE_URL` pattern):

| Variable | Required | Description |
|---|---|---|
| `OIDC_ISSUER_URL` | Yes | Base URL of the OIDC provider, e.g. `https://auth.example.com` |
| `OIDC_CLIENT_ID` | Yes | Client ID registered with the provider |
| `OIDC_CLIENT_SECRET` | Yes | Client secret |
| `OIDC_REDIRECT_URL` | No | Full callback URL (defaults to `http://localhost:3000/auth/callback`) |
| `SESSION_SECRET` | Recommended | 64-byte hex secret for signing session cookies (auto-generated and logged as a warning if absent) |

---

## New Dependencies (Cargo.toml)

- **`openidconnect`** — Standards-compliant OIDC client; handles discovery, PKCE, token validation
- **`tower-sessions`** + **`tower-sessions-sqlx-store`** (or `tower-sessions-moka-store`) — Cookie-based session middleware backed by SQLite or in-memory store
- **`axum-extra`** (already may be present) — For typed cookies / cookie jar
- **`rand`** (likely already present via transitive deps) — PKCE verifier / state generation

---

## Backend Changes

### 1. Configuration struct (`src/config.rs`)

Create a `Config` struct that is populated from environment variables at startup:

```rust
pub struct Config {
    pub database_url: String,
    pub oidc: Option<OidcConfig>,
    pub session_secret: [u8; 64],
}

pub struct OidcConfig {
    pub issuer_url: IssuerUrl,
    pub client_id: ClientId,
    pub client_secret: ClientSecret,
    pub redirect_url: RedirectUrl,
}
```

### 2. App state (`src/main.rs`)

Add to the shared `App` state:
- `Option<Arc<CoreClient>>` — the configured OIDC client (None = auth disabled)
- `SessionManagerLayer` — added to the router when auth is enabled

### 3. Auth routes (`src/auth.rs`)

Three new Axum handlers:

**`GET /auth/login`**
1. Generate a PKCE challenge pair and a random CSRF `state` value
2. Store `(state, pkce_verifier)` in the session
3. Build the authorization URL using `openidconnect` discovery
4. Redirect the browser to the provider

**`GET /auth/callback?code=...&state=...`**
1. Retrieve `(state, pkce_verifier)` from session; reject if missing or state mismatch (CSRF protection)
2. Exchange the authorization code for tokens using PKCE verifier
3. Validate the ID token (signature, nonce, audience, expiry) — `openidconnect` does this automatically
4. Store `authenticated = true` (and optionally the subject `sub` claim) in the session
5. Redirect to `/` (or a pre-auth URL stored in the session)

**`GET /auth/logout`**
1. Destroy the session
2. Redirect to `/` (which will redirect to login since session is gone)

**`GET /auth/status`** (new API endpoint, unauthenticated)
Returns:
```json
{ "auth_enabled": true }   // or false
```
The frontend uses this to decide whether to show a login flow.

### 4. Auth middleware (`src/middleware/auth.rs`)

An Axum middleware layer that:
1. If `oidc_client` is `None` → pass through (auth disabled)
2. Check the session for `authenticated = true`
3. If present → pass through
4. If the request is for `/auth/*` or is a static asset → pass through
5. Otherwise:
   - For `Accept: application/json` requests → return `401 Unauthorized`
   - For browser requests → redirect to `/auth/login` (storing the original URL in the session for post-login redirect)

Apply this middleware to the top-level router so it covers both API routes and the SPA fallback.

### 5. Router changes (`src/main.rs`)

```
Router
  ├── /auth/login      → auth::login
  ├── /auth/callback   → auth::callback
  ├── /auth/logout     → auth::logout
  ├── /api/config      → existing (expose auth_enabled flag here instead of separate endpoint)
  ├── /api/**          → existing handlers (now protected by middleware)
  └── /**              → static files + SPA fallback (protected by middleware)
```

The session layer and auth middleware are added conditionally when OIDC config is present.

---

## Database / Session Storage

Use **in-memory session store** (`MemoryStore` from `tower-sessions`) to keep things simple — sessions are lost on restart, which just means users need to log in again. This avoids a new database migration.

If persistence is needed in the future, a SQLite-backed store can be swapped in without API changes.

---

## Frontend Changes

### 1. Auth status check (`src/api.ts` or similar)

On app startup, call `GET /api/config` (already exists) — extend it to include `auth_enabled: boolean`. No new endpoint needed.

### 2. 401 handling

In the existing `fetch` wrappers, intercept `401` responses and redirect `window.location` to `/auth/login`. This handles token expiry or session loss after initial load.

### 3. Logout button

Add a logout button to the UI (e.g., in the header/settings area) that calls `GET /auth/logout`.

---

## File Structure (new/modified files)

```
src/
  config.rs          ← NEW: parse env vars into Config struct
  auth.rs            ← NEW: login / callback / logout handlers
  middleware/
    auth.rs          ← NEW: session-checking middleware
  main.rs            ← MODIFIED: wire up config, auth routes, session layer, middleware
  api/
    config.rs        ← MODIFIED: include auth_enabled in response

ui/web/src/
  api.ts (or lib/api.ts)   ← MODIFIED: handle 401 → redirect to /auth/login
  App.tsx                  ← MODIFIED: add logout button

Cargo.toml           ← MODIFIED: add openidconnect, tower-sessions, rand
```

---

## Sequence Diagram

```
Browser                 Tress                    Authelia
  |                       |                          |
  |-- GET /               |                          |
  |                       | (no session)             |
  |<-- 302 /auth/login    |                          |
  |                       |                          |
  |-- GET /auth/login     |                          |
  |                       | generate state+PKCE      |
  |                       | store in session         |
  |<-- 302 https://auth.example.com/oauth2/authorize?... |
  |                       |                          |
  |------- authorize request ----------------------->|
  |<------ 302 /auth/callback?code=...&state=... ----|
  |                       |                          |
  |-- GET /auth/callback  |                          |
  |                       | validate state           |
  |                       |-- token exchange ------->|
  |                       |<-- tokens ---------------|
  |                       | validate ID token        |
  |                       | mark session authenticated|
  |<-- 302 /             |                          |
  |                       |                          |
  |-- GET /api/feeds      |                          |
  |                       | session OK → serve       |
  |<-- 200 [feeds]        |                          |
```

---

## Security Considerations

- **PKCE** (S256 method) is used for all flows, mitigating authorization code interception
- **State parameter** provides CSRF protection on the callback
- **Session cookies** are `HttpOnly`, `SameSite=Lax`, `Secure` (configurable; default Secure=false for localhost dev)
- **ID token validation**: signature (from JWKS), issuer, audience, expiry all verified by the `openidconnect` crate
- Auth is completely **opt-in** — no behaviour change when env vars are absent

---

## Implementation Order

1. **`Cargo.toml`** — add dependencies
2. **`src/config.rs`** — environment variable parsing
3. **`src/auth.rs`** — OIDC handlers (login, callback, logout)
4. **`src/middleware/auth.rs`** — session auth check middleware
5. **`src/main.rs`** — wire everything together; extend `/api/config` response
6. **Frontend** — 401 handling + logout button

Each step is independently testable: config parsing and routing can be unit-tested; the OIDC flow can be integration-tested against a local provider like Authelia or Dex.
