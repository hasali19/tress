pub struct Config {
    pub database_url: String,
    pub oidc: Option<OidcConfig>,
}

impl Config {
    pub fn from_env() -> eyre::Result<Self> {
        Ok(Config {
            database_url: std::env::var("DATABASE_URL")
                .unwrap_or_else(|_| "sqlite://data/tress.db?mode=rwc".to_owned()),
            oidc: OidcConfig::from_env()?,
        })
    }
}

#[derive(Clone)]
pub struct OidcConfig {
    pub issuer_url: String,
    pub client_id: String,
}

impl OidcConfig {
    pub fn from_env() -> eyre::Result<Option<Self>> {
        let Ok(issuer_url) = std::env::var("OIDC_ISSUER_URL") else {
            return Ok(None);
        };
        let client_id = std::env::var("OIDC_CLIENT_ID")
            .map_err(|_| eyre::eyre!("OIDC_CLIENT_ID must be set when OIDC_ISSUER_URL is set"))?;
        Ok(Some(OidcConfig {
            issuer_url,
            client_id,
        }))
    }
}
