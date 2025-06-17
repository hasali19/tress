use std::iter;

use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{any, get};
use axum::{Json, Router};
use serde::Serialize;
use serde_json::json;
use tokio::signal;
use tower_http::services::{ServeDir, ServeFile};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

#[tokio::main]
async fn main() -> eyre::Result<()> {
    color_eyre::install()?;

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                format!(
                    "{}=debug,tower_http=debug,axum=trace",
                    env!("CARGO_CRATE_NAME")
                )
                .into()
            }),
        )
        .with(tracing_subscriber::fmt::layer().without_time())
        .init();

    let api = Router::new().route("/posts", get(get_posts)).fallback(any((
        StatusCode::NOT_FOUND,
        Json(json!({"message": "not found"})),
    )));

    let app = Router::new()
        .nest("/api", api)
        .fallback_service(ServeDir::new("ui/dist").fallback(ServeFile::new("ui/dist/index.html")));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();

    tracing::info!("server listening on {}", listener.local_addr()?);

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    Ok(())
}

async fn get_posts() -> impl IntoResponse {
    #[derive(Clone, Serialize)]
    struct Post {
        feed: String,
        title: String,
        date: String,
        thumbnail: String,
        description: String,
        url: String,
    }

    let post = Post {
        date: "2025-06-05T19:00:01Z".to_owned(),
        title: "Introducing facet: Reflection for Rust".to_owned(),
        feed: "fasterthanli.me".to_owned(),
        // "icon": "https://cdn.fasterthanli.me/content/img/logo-square-2~fd5dd5c3a1490c10.w900.png",
        thumbnail: "https://cdn.fasterthanli.me/content/articles/introducing-facet-reflection-for-rust/_thumb~23945b507327fd24.png".to_owned(),
        description: "I have long been at war against Rust compile times.\n\
    Part of the solution for me was to buy my way into Apple Silicon dreamland, where builds are, like… faster. I remember every time I SSH into an x...".to_owned(),
        url: "https://fasterthanli.me/articles/introducing-facet-reflection-for-rust".to_owned(),
    };

    Json(json!(iter::repeat_n(post, 10).collect::<Vec<_>>()))
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
