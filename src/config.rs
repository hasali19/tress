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
