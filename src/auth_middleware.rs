use std::sync::Arc;

use axum::extract::{Request, State};
use axum::http::header::WWW_AUTHENTICATE;
use axum::http::{HeaderValue, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};

use crate::jwks::JwksClient;

pub async fn auth_middleware(
    State(jwks_client): State<Option<Arc<JwksClient>>>,
    request: Request,
    next: Next,
) -> Response {
    let Some(client) = jwks_client else {
        return next.run(request).await;
    };

    let Some(token) = extract_bearer_token(&request) else {
        let mut res = StatusCode::UNAUTHORIZED.into_response();
        res.headers_mut()
            .insert(WWW_AUTHENTICATE, HeaderValue::from_static("Bearer"));
        return res;
    };

    match client.validate_token(&token).await {
        Ok(_) => next.run(request).await,
        Err(e) => {
            tracing::debug!("Auth rejected: {e}");
            let mut res = StatusCode::UNAUTHORIZED.into_response();
            res.headers_mut().insert(
                WWW_AUTHENTICATE,
                HeaderValue::from_static(r#"Bearer error="invalid_token""#),
            );
            res
        }
    }
}

fn extract_bearer_token(request: &Request) -> Option<String> {
    let value = request.headers().get("Authorization")?.to_str().ok()?;
    value.strip_prefix("Bearer ").map(str::to_owned)
}
