# OIDC Auth Implementation Plan

## Overview

The tress API already validates OIDC tokens on the backend (via `OIDC_ISSUER_URL` env var). The UI currently has no auth and calls the API directly. We need to:

1. **Backend**: Add a public config endpoint that exposes the OIDC issuer URL and client ID so the UI can discover them without a token.
2. **Frontend**: Implement the OIDC authorization code flow (with PKCE) and pass the resulting `id_token` as a Bearer token on all API requests.

---

## Backend Changes

### Problem: `/api/config` is behind auth middleware

Currently all `/api` routes are wrapped in the auth middleware (see `main.rs:124–144`). This means a client with no token cannot call `/api/config` to discover whether auth is even required. The config endpoint must be moved outside the auth middleware.

### Step 1 — Add `OIDC_CLIENT_ID` to config (`src/config.rs`)

Add a `client_id` field to `OidcConfig`, read from the `OIDC_CLIENT_ID` environment variable. This lets the backend tell the UI which client ID to use when initiating the OIDC flow.

```rust
pub struct OidcConfig {
    pub issuer_url: String,
    pub client_id: String,      // new — OIDC_CLIENT_ID env var
    pub audience: Option<String>,
}
```

### Step 2 — Expose OIDC config in `App` struct (`src/main.rs`)

Add optional OIDC fields to the `App` state so the `get_config` handler can include them in the response:

```rust
struct App {
    db: DatabaseConnection,
    sync_sender: mpsc::UnboundedSender<SyncRequest>,
    http_client: Client,
    vapid_key: Arc<ES256KeyPair>,
    oidc_issuer_url: Option<String>,   // new
    oidc_client_id: Option<String>,    // new
}
```

Populate from `config.oidc` before it is moved into `JwksClient::new`.

### Step 3 — Restructure router to make `/config` public (`src/main.rs`)

Split the API router into a public part and a protected part:

```rust
// Protected routes — auth middleware applied here only
let protected_api = Router::new()
    .route("/push_subscriptions", post(create_push_subscription))
    .route("/feeds", get(get_feeds).post(add_feed))
    .route("/feeds/{id}", get(get_feed))
    .route("/posts", get(get_posts))
    .route("/posts/{id}", get(get_post))
    .fallback(...)
    .layer(axum::middleware::from_fn_with_state(
        jwks_client,
        auth_middleware::auth_middleware,
    ));

// Public routes — no auth required
let api = Router::new()
    .route("/config", get(get_config))   // always accessible
    .merge(protected_api)
    .with_state(App { ... });
```

### Step 4 — Update `get_config` handler to include OIDC info (`src/main.rs`)

Extend the JSON response to include an optional `oidc` field:

```json
{
  "vapid": { "public_key": "..." },
  "oidc": {
    "issuer_url": "https://auth.example.com",
    "client_id": "tress"
  }
}
```

If OIDC is not configured, `oidc` is `null`. The UI uses this to decide whether to trigger the auth flow.

---

## Frontend Changes

### Packages to add (`ui/pubspec.yaml`)

- **`flutter_appauth`** — OIDC/OAuth2 authorization code flow with PKCE, using the system browser. Handles the browser redirect, code exchange, and returns tokens.
- **`flutter_secure_storage`** — Stores the id_token (and refresh token if available) securely in the platform keystore.

### Step 5 — Configure Android redirect URI (`ui/android/app/src/main/AndroidManifest.xml`)

`flutter_appauth` uses a custom URI scheme for the redirect. Add an intent filter so Android routes the callback back to the app:

```xml
<activity android:name="com.linusu.flutter_web_auth_2.CallbackActivity" ...>
  <intent-filter android:label="flutter_web_auth_2">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="dev.hasali.tress" android:host="auth" />
  </intent-filter>
</activity>
```

The redirect URI used in the OIDC flow will be `dev.hasali.tress://auth/callback`.

### Step 6 — Create `AuthService` (`ui/lib/auth_service.dart`)

Encapsulates the OIDC flow and token storage:

```dart
class AuthService {
  // Stores id_token (and refresh_token) via flutter_secure_storage
  // Exposes:
  //   Future<void> login(issuerUrl, clientId)  — triggers browser auth flow
  //   Future<String?> getIdToken()              — returns current token or null
  //   Future<String?> refreshIfNeeded()         — refresh using refresh_token
  //   Future<void> logout()                     — clears stored tokens
}
```

Key implementation details:
- Uses `FlutterAppAuth.authorizeAndExchangeCode()` with PKCE
- Requests scopes: `['openid', 'profile']`
- Redirect URI: `dev.hasali.tress://auth/callback`
- Stores `id_token` and `refresh_token` in secure storage
- On token expiry, attempts silent refresh using the refresh token

### Step 7 — Update `ApiClient` to attach Bearer token (`ui/lib/api_client.dart`)

Add a Dio interceptor that retrieves the current `id_token` from `AuthService` and attaches it to every request:

```dart
_dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) async {
    final token = await authService.getIdToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  },
  onError: (error, handler) async {
    if (error.response?.statusCode == 401) {
      // Token may have expired — attempt refresh then retry once
      final newToken = await authService.refreshIfNeeded();
      if (newToken != null) {
        // retry original request with new token
        ...
      }
    }
    handler.next(error);
  },
));
```

`ApiClient` receives `AuthService` via constructor injection (registered in GetIt).

### Step 8 — Update `main.dart` to gate startup on auth

Change the startup sequence:

1. Fetch `/api/config` (now public — no token needed).
2. Check if `config['oidc']` is non-null.
3. If OIDC is required:
   a. Check if a valid stored token exists (`authService.getIdToken()`).
   b. If not, call `authService.login(issuerUrl, clientId)` — opens browser.
   c. Wait for login to complete.
4. Continue with app startup (register push subscription, etc.).

The app should show a loading/login screen while auth is in progress rather than trying to render the main UI with a missing token.

---

## Data Flow Summary

```
App starts
  → GET /api/config (no auth)
  ← { oidc: { issuer_url, client_id }, vapid: { ... } }

If oidc is non-null:
  → Open system browser to {issuer_url}/authorize?client_id=...&code_challenge=...
  ← Browser redirects to dev.hasali.tress://auth/callback?code=...
  → POST {issuer_url}/token (exchange code for tokens)
  ← { id_token, refresh_token, ... }
  → Store id_token + refresh_token in secure storage

All subsequent API calls:
  → GET/POST /api/... with Authorization: Bearer {id_token}
  ← 200 OK (or 401 if token expired → refresh and retry)
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/config.rs` | Add `client_id` to `OidcConfig` |
| `src/main.rs` | Add OIDC fields to `App`, restructure router, update `get_config` |
| `ui/pubspec.yaml` | Add `flutter_appauth`, `flutter_secure_storage` |
| `ui/android/app/src/main/AndroidManifest.xml` | Add redirect URI intent filter |
| `ui/lib/auth_service.dart` | New file — OIDC flow + token storage |
| `ui/lib/api_client.dart` | Add Dio interceptor for Bearer token |
| `ui/lib/main.dart` | Gate startup on auth when OIDC is configured |
