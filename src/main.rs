mod entities;

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{any, get};
use axum::{Json, Router};
use itertools::Itertools;
use migration::{Migrator, MigratorTrait};
use sea_orm::prelude::Uuid;
use sea_orm::{
    ActiveModelTrait, ActiveValue, ConnectOptions, Database, DatabaseConnection, EntityTrait,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::signal;
use tower_http::services::{ServeDir, ServeFile};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

use crate::entities::feeds;
use crate::entities::prelude::*;

#[derive(Clone)]
struct App {
    db: DatabaseConnection,
}

#[tokio::main]
async fn main() -> eyre::Result<()> {
    color_eyre::install()?;

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                format!(
                    "info,{}=debug,tower_http=debug,axum=trace",
                    env!("CARGO_CRATE_NAME")
                )
                .into()
            }),
        )
        .with(tracing_subscriber::fmt::layer().without_time())
        .init();

    let db = init_db().await?;

    let api = Router::new()
        .route("/feeds", get(get_feeds).post(add_feed))
        .route("/posts", get(get_posts))
        .fallback(any((
            StatusCode::NOT_FOUND,
            Json(json!({"message": "not found"})),
        )))
        .with_state(App { db });

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

async fn init_db() -> eyre::Result<DatabaseConnection> {
    // TODO: DB url should be configurable
    let mut options = ConnectOptions::new("sqlite://tress.db?mode=rwc");
    options.max_connections(1);
    let db = Database::connect(options).await?;
    Migrator::up(&db, None).await?;
    Ok(db)
}

async fn get_feeds(State(app): State<App>) -> Result<impl IntoResponse, StatusCode> {
    let feeds = match Feeds::find().all(&app.db).await {
        Ok(posts) => posts,
        Err(e) => {
            tracing::error!("{e}");
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    #[derive(Clone, Serialize)]
    struct Feed {
        id: String,
        url: String,
    }

    Ok(Json(
        feeds
            .into_iter()
            .map(|feed| Feed {
                id: feed.id.to_string(),
                url: feed.url,
            })
            .collect_vec(),
    ))
}

#[derive(Deserialize)]
struct CreateFeedReq {
    url: String,
}

async fn add_feed(
    State(app): State<App>,
    Json(req): Json<CreateFeedReq>,
) -> Result<impl IntoResponse, StatusCode> {
    let feed = feeds::ActiveModel {
        id: ActiveValue::Set(Uuid::new_v4()),
        url: ActiveValue::Set(req.url),
    };

    if let Err(e) = feed.insert(&app.db).await {
        tracing::error!("{e}");
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    Ok(())
}

async fn get_posts(State(app): State<App>) -> Result<impl IntoResponse, StatusCode> {
    let posts = match Posts::find().all(&app.db).await {
        Ok(posts) => posts,
        Err(e) => {
            tracing::error!("{e}");
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    #[derive(Clone, Serialize)]
    struct Post {
        id: String,
        feed_id: String,
        title: String,
        post_time: String,
        thumbnail: String,
        description: String,
        url: String,
    }

    Ok(Json(
        posts
            .into_iter()
            .map(|post| Post {
                id: post.id.to_string(),
                feed_id: post.feed_id.to_string(),
                title: post.title,
                post_time: post.post_time,
                thumbnail: post.thumbnail,
                description: post.description,
                url: post.url,
            })
            .collect_vec(),
    ))
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
