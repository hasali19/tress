pub struct Config {
    pub database_url: String,
    pub oidc: Option<OidcConfig>,
}

impl Config {
    pub fn from_env() -> Self {
        Config {
            database_url: std::env::var("DATABASE_URL")
                .unwrap_or_else(|_| "sqlite://data/tress.db?mode=rwc".to_owned()),
            oidc: OidcConfig::from_env(),
        }
    }
}

pub struct OidcConfig {
    pub issuer_url: String,
    pub audience: Option<String>,
}

impl OidcConfig {
    pub fn from_env() -> Option<Self> {
        let issuer_url = std::env::var("OIDC_ISSUER_URL").ok()?;
        Some(OidcConfig {
            issuer_url,
            audience: std::env::var("OIDC_AUDIENCE").ok(),
        })
    }
}
