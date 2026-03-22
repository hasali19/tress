use std::sync::Arc;

use axum::extract::{Request, State};
use axum::http::header::WWW_AUTHENTICATE;
use axum::http::{HeaderValue, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum_extra::TypedHeader;
use axum_extra::headers::Authorization;
use axum_extra::headers::authorization::Bearer;

use crate::jwks::JwksClient;

pub async fn auth_middleware(
    State(jwks_client): State<Option<Arc<JwksClient>>>,
    auth: Option<TypedHeader<Authorization<Bearer>>>,
    request: Request,
    next: Next,
) -> Response {
    let Some(client) = jwks_client else {
        return next.run(request).await;
    };

    let Some(TypedHeader(auth)) = auth else {
        let mut res = StatusCode::UNAUTHORIZED.into_response();
        res.headers_mut()
            .insert(WWW_AUTHENTICATE, HeaderValue::from_static("Bearer"));
        return res;
    };

    match client.validate_token(auth.token()).await {
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
