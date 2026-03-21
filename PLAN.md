# Plan: OIDC/OAuth Authentication (Resource Server)

## Overview

Add Bearer token authentication to the Tress API so it can be protected behind an OIDC provider like Authelia. The **mobile app** handles the OAuth flow itself (Authorization Code + PKCE via system browser), obtains an access token from the provider, and sends it on every API request as a standard `Authorization: Bearer <token>` header.

The server acts purely as an **OAuth 2.0 Resource Server**: it validates tokens locally using the provider's JWKS endpoint — no redirects, no sessions, no cookies.

Auth is **opt-in**: if no OIDC config is provided the server runs as today with no auth.

---

## Configuration (env vars)

| Variable | Required | Description |
|---|---|---|
| `OIDC_ISSUER_URL` | Yes | Provider base URL, e.g. `https://auth.example.com`. Used for OIDC discovery (`/.well-known/openid-configuration`) to obtain the JWKS URI and issuer claim. |
| `OIDC_AUDIENCE` | No | Expected `aud` claim in the token. If omitted, audience validation is skipped. Some providers (e.g. Authelia) set `aud` to the client ID. |

No client secret is needed on the server — the mobile app holds the client credentials and performs the token exchange. The server only needs the public JWKS to verify signatures.

---

## New Dependencies (Cargo.toml)

- **`jsonwebtoken`** — JWT decoding and signature verification (RS256/ES256)
- **`reqwest`** — already present; used to fetch the discovery document and JWKS
- **`serde_json`** — already present; parse discovery/JWKS responses
- **`tokio::sync::RwLock`** — cache the JWKS in memory with periodic refresh

---

## Backend Changes

### 1. Configuration (`src/config.rs`) — new file

```rust
pub struct Config {
    pub database_url: String,
    pub oidc: Option<OidcConfig>,
}

pub struct OidcConfig {
    pub issuer_url: String,   // e.g. "https://auth.example.com"
    pub audience: Option<String>,
}
```

Populated from env vars at startup; errors out clearly if `OIDC_ISSUER_URL` is set but malformed.

### 2. JWKS client (`src/jwks.rs`) — new file

Responsibilities:
- At startup, fetch `{issuer_url}/.well-known/openid-configuration` to discover the `jwks_uri` and canonical `issuer` value
- Fetch and parse the JWKS; cache the key set in an `Arc<RwLock<JwkSet>>`
- Spawn a background task that refreshes the JWKS every 12 hours (handles key rotation)
- Expose a `validate_token(token: &str) -> Result<Claims, AuthError>` function that:
  1. Decodes the JWT header to find the `kid` (key ID)
  2. Looks up the matching key in the cached JWKS
  3. Verifies signature, `iss`, `exp`, and optionally `aud` using `jsonwebtoken`
  4. Returns the validated claims or an error

```rust
pub struct Claims {
    pub sub: String,
    pub exp: usize,
    // … other standard claims
}
```

### 3. Auth middleware (`src/middleware/auth.rs`) — new file

An Axum middleware that:
1. If `oidc_config` is `None` → pass through (auth disabled)
2. Extract the `Authorization` header; if missing → `401` with `WWW-Authenticate: Bearer`
3. Strip `Bearer ` prefix; if malformed → `401`
4. Call `jwks_client.validate_token(token)`:
   - Ok → pass through (optionally inject `sub` into request extensions for logging)
   - Err → `401` with `WWW-Authenticate: Bearer error="invalid_token"`

Applied to all `/api/*` routes. Static file serving and the SPA do not need protection (mobile-only API).

### 4. App state & router (`src/main.rs`) — modified

Add to `App`:
```rust
pub jwks_client: Option<Arc<JwksClient>>,
```

Startup sequence when `OIDC_ISSUER_URL` is set:
1. Fetch discovery document → extract `issuer` and `jwks_uri`
2. Fetch initial JWKS
3. Spawn background refresh task
4. Add `JwksClient` to app state
5. Apply auth middleware to `/api` routes

### 5. `/api/config` response — modified

Add `auth_enabled: bool` so the mobile app knows whether to initiate an auth flow before making API calls.

---

## Mobile App Responsibilities (out of scope for server)

For completeness, the mobile client (Flutter) needs to:
1. Read `auth_enabled` from `GET /api/config` on first launch
2. If true, initiate Authorization Code + PKCE flow using the system browser (`flutter_appauth` or similar)
3. Store the access token and refresh token securely (flutter_secure_storage)
4. Attach `Authorization: Bearer <access_token>` to every API request
5. On `401` response, attempt token refresh; if refresh fails, re-initiate login

---

## Token Validation Flow

```
Mobile App                   Tress API                  Authelia
    |                            |                          |
    |-- POST /api/feeds          |                          |
    |   Authorization: Bearer <token>                       |
    |                            |                          |
    |                            | decode JWT header → kid  |
    |                            | lookup kid in JWKS cache |
    |                            | verify signature + exp   |
    |                            |                          |
    |<-- 200 OK                  |                          |
    |                            |                          |
    |-- POST /api/feeds (expired token)                     |
    |                            |                          |
    |                            | exp check fails          |
    |<-- 401 Unauthorized        |                          |
    |   WWW-Authenticate: Bearer error="invalid_token"      |
    |                            |                          |
    |-- token refresh ---------->|  (direct to Authelia)   |
    |<-- new access token -------|--------------------------|
    |-- retry with new token --> |                          |
    |<-- 200 OK                  |                          |
```

---

## Security Considerations

- **No client secret on the server** — the server never sees client credentials; it only verifies signatures with public JWKS keys
- **JWKS caching** with periodic refresh handles key rotation without downtime
- **`kid` lookup** before verification avoids trying all keys (important when the provider has multiple keys)
- **Strict claim validation**: `iss` must exactly match the discovered issuer; `exp` is always checked; `aud` checked if configured
- **Unknown `kid`** triggers an immediate JWKS refresh before failing, to handle newly rotated keys
- Auth is fully **opt-in** — no behaviour change when `OIDC_ISSUER_URL` is absent

---

## File Summary

```
src/
  config.rs           ← NEW: env var parsing
  jwks.rs             ← NEW: JWKS fetch, cache, token validation
  middleware/
    auth.rs           ← NEW: Bearer token extraction + validation middleware
  main.rs             ← MODIFIED: wire config, JwksClient, middleware
  api/
    config.rs         ← MODIFIED: add auth_enabled to response

Cargo.toml            ← MODIFIED: add jsonwebtoken
```

---

## Implementation Order

1. **`Cargo.toml`** — add `jsonwebtoken`
2. **`src/config.rs`** — env var parsing
3. **`src/jwks.rs`** — discovery, JWKS fetch/cache, `validate_token`
4. **`src/middleware/auth.rs`** — Bearer extraction + middleware
5. **`src/main.rs`** — wire it all together
6. **`/api/config`** — add `auth_enabled` field
