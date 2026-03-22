use std::sync::Arc;
use std::time::Duration;

use jsonwebtoken::jwk::{Jwk, JwkSet};
use jsonwebtoken::{Algorithm, DecodingKey, Validation};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use parking_lot::RwLock;

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("token validation failed: {0}")]
    InvalidToken(String),
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub exp: usize,
    pub iss: String,
}

#[derive(Deserialize)]
struct OidcDiscovery {
    issuer: String,
    jwks_uri: String,
}

pub struct JwksClient {
    issuer: String,
    audience: Option<String>,
    jwks_uri: String,
    http_client: Client,
    key_set: RwLock<JwkSet>,
}

impl JwksClient {
    pub async fn new(
        http_client: Client,
        issuer_url: &str,
        audience: Option<String>,
    ) -> eyre::Result<Arc<Self>> {
        let discovery_url = format!(
            "{}/.well-known/openid-configuration",
            issuer_url.trim_end_matches('/')
        );

        let discovery: OidcDiscovery = http_client
            .get(&discovery_url)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;

        tracing::info!("OIDC issuer: {}", discovery.issuer);

        let key_set: JwkSet = http_client
            .get(&discovery.jwks_uri)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;

        tracing::info!("Loaded {} JWKS key(s)", key_set.keys.len());

        let client = Arc::new(JwksClient {
            issuer: discovery.issuer,
            audience,
            jwks_uri: discovery.jwks_uri,
            http_client,
            key_set: RwLock::new(key_set),
        });

        tokio::spawn({
            let client = client.clone();
            async move {
                loop {
                    tokio::time::sleep(Duration::from_secs(12 * 60 * 60)).await;
                    if let Err(e) = client.refresh_keys().await {
                        tracing::warn!("Failed to refresh JWKS: {e}");
                    }
                }
            }
        });

        Ok(client)
    }

    async fn refresh_keys(&self) -> eyre::Result<()> {
        let key_set: JwkSet = self
            .http_client
            .get(&self.jwks_uri)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        *self.key_set.write() = key_set;
        tracing::debug!("JWKS refreshed");
        Ok(())
    }

    pub async fn validate_token(&self, token: &str) -> Result<Claims, AuthError> {
        let header = jsonwebtoken::decode_header(token)
            .map_err(|e| AuthError::InvalidToken(e.to_string()))?;

        match &header.kid {
            Some(kid) => {
                // Try with cached keys first
                {
                    let key_set = self.key_set.read();
                    if let Some(jwk) = key_set.find(kid) {
                        return self.decode_with_jwk(token, header.alg, jwk);
                    }
                }
                // Unknown kid — refresh JWKS and retry once (handles key rotation)
                if let Err(e) = self.refresh_keys().await {
                    tracing::warn!("JWKS refresh failed: {e}");
                }
                let key_set = self.key_set.read();
                let jwk = key_set
                    .find(kid)
                    .ok_or_else(|| AuthError::InvalidToken("unknown key id".to_string()))?;
                self.decode_with_jwk(token, header.alg, jwk)
            }
            None => {
                // No kid in token — try all cached keys
                let key_set = self.key_set.read();
                for jwk in &key_set.keys {
                    if let Ok(claims) = self.decode_with_jwk(token, header.alg, jwk) {
                        return Ok(claims);
                    }
                }
                Err(AuthError::InvalidToken(
                    "token validation failed".to_string(),
                ))
            }
        }
    }

    fn decode_with_jwk(&self, token: &str, alg: Algorithm, jwk: &Jwk) -> Result<Claims, AuthError> {
        let decoding_key =
            DecodingKey::from_jwk(jwk).map_err(|e| AuthError::InvalidToken(e.to_string()))?;

        let mut validation = Validation::new(alg);
        validation.set_issuer(&[&self.issuer]);
        if let Some(aud) = &self.audience {
            validation.set_audience(&[aud]);
        } else {
            validation.validate_aud = false;
        }

        jsonwebtoken::decode::<Claims>(token, &decoding_key, &validation)
            .map(|data| data.claims)
            .map_err(|e| AuthError::InvalidToken(e.to_string()))
    }
}
