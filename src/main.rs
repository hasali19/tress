mod entities;

use std::time::Duration;

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{any, get};
use axum::{Json, Router};
use eyre::eyre;
use itertools::Itertools;
use migration::{Migrator, MigratorTrait};
use reqwest::Client;
use scraper::Html;
use sea_orm::prelude::Uuid;
use sea_orm::{
    ActiveModelTrait, ActiveValue, ConnectOptions, Database, DatabaseConnection, EntityTrait,
    QueryOrder, SqlErr,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use thiserror::Error;
use tokio::signal;
use tokio::sync::mpsc;
use tower_http::services::{ServeDir, ServeFile};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

use crate::entities::prelude::*;
use crate::entities::{feeds, posts};

#[derive(Clone)]
struct App {
    db: DatabaseConnection,
    sync_sender: mpsc::UnboundedSender<SyncRequest>,
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
        .with(tracing_subscriber::fmt::layer())
        .init();

    let db = init_db().await?;

    let (sync_sender, sync_receiver) = mpsc::unbounded_channel();

    tokio::spawn({
        let sync_sender = sync_sender.clone();
        async move {
            sync_sender.send(SyncRequest::All).unwrap();
            tokio::time::sleep(Duration::from_secs(60 * 60)).await;
        }
    });

    tokio::spawn(run_sync_worker(sync_receiver, db.clone()));

    let api = Router::new()
        .route("/feeds", get(get_feeds).post(add_feed))
        .route("/posts", get(get_posts))
        .fallback(any((
            StatusCode::NOT_FOUND,
            Json(json!({"message": "not found"})),
        )))
        .with_state(App {
            db: db.clone(),
            sync_sender,
        });

    let app = Router::new()
        .nest("/api", api)
        .fallback_service(ServeDir::new("ui/dist").fallback(ServeFile::new("ui/dist/index.html")));

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .unwrap();

    tracing::info!("server listening at http://{}", listener.local_addr()?);

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    db.close().await?;

    Ok(())
}

async fn init_db() -> eyre::Result<DatabaseConnection> {
    // TODO: DB url should be configurable
    let mut options = ConnectOptions::new("sqlite://tress.db?mode=rwc");
    options
        .max_connections(1)
        .sqlx_logging_level(log::LevelFilter::Debug);
    let db = Database::connect(options).await?;
    Migrator::up(&db, None).await?;
    Ok(db)
}

#[derive(Clone, Serialize)]
struct FeedResponse {
    id: String,
    title: String,
    url: String,
}

async fn get_feeds(State(app): State<App>) -> Result<impl IntoResponse, StatusCode> {
    let feeds = match Feeds::find().all(&app.db).await {
        Ok(posts) => posts,
        Err(e) => {
            tracing::error!("{e}");
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    Ok(Json(
        feeds
            .into_iter()
            .map(|feed| FeedResponse {
                id: feed.id.to_string(),
                title: feed.title,
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
    let feed = fetch_feed(&req.url).await.unwrap();

    let title = match feed {
        Feed::Atom(feed) => feed.title.value,
        Feed::Rss(channel) => channel.title,
    };

    let feed = feeds::ActiveModel {
        id: ActiveValue::Set(Uuid::new_v4()),
        title: ActiveValue::Set(title),
        url: ActiveValue::Set(req.url),
    };

    let feed = match feed.insert(&app.db).await {
        Ok(feed) => feed,
        Err(e) => {
            tracing::error!("{e}");
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    tracing::info!("added feed: {feed:?}");

    let _ = app.sync_sender.send(SyncRequest::Feed(feed.id));

    Ok(Json(FeedResponse {
        id: feed.id.to_string(),
        title: feed.title,
        url: feed.url,
    }))
}

async fn get_posts(State(app): State<App>) -> Result<impl IntoResponse, StatusCode> {
    let posts = match Posts::find()
        .order_by_desc(posts::Column::PublishTime)
        .all(&app.db)
        .await
    {
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
        thumbnail: Option<String>,
        description: Option<String>,
        url: String,
    }

    Ok(Json(
        posts
            .into_iter()
            .map(|post| Post {
                id: post.id.to_string(),
                feed_id: post.feed_id.to_string(),
                title: post.title,
                post_time: post.publish_time,
                thumbnail: post.thumbnail,
                description: post.description,
                url: post.url,
            })
            .collect_vec(),
    ))
}

enum SyncRequest {
    All,
    Feed(Uuid),
}

async fn run_sync_worker(
    mut receiver: mpsc::UnboundedReceiver<SyncRequest>,
    db: DatabaseConnection,
) {
    while let Some(req) = receiver.recv().await {
        let feeds = match req {
            SyncRequest::All => Feeds::find().all(&db).await.unwrap(),
            SyncRequest::Feed(id) => Feeds::find_by_id(id)
                .one(&db)
                .await
                .unwrap()
                .into_iter()
                .collect_vec(),
        };

        for feed_model in feeds {
            tracing::info!("syncing posts from {}", feed_model.url);

            let feed = fetch_feed(&feed_model.url).await.unwrap();

            match feed {
                Feed::Atom(feed) => {
                    for entry in feed.entries {
                        let description =
                            entry.summary().map(|v| v.value.as_str()).map(|summary| {
                                let html = Html::parse_fragment(summary);
                                html.root_element().text().join("")
                            });

                        let post = posts::ActiveModel {
                            id: ActiveValue::Set(Uuid::new_v4()),
                            feed_id: ActiveValue::Set(feed_model.id),
                            url: ActiveValue::Set(entry.id),
                            title: ActiveValue::Set(entry.title.value),
                            description: ActiveValue::Set(description),
                            publish_time: ActiveValue::Set(entry.updated.to_rfc3339()),
                            thumbnail: ActiveValue::Set(None),
                        };

                        tracing::debug!(?post.title, ?post.url, "inserting post");

                        if let Err(e) = post.insert(&db).await {
                            if let Some(SqlErr::UniqueConstraintViolation(_)) = e.sql_err() {
                                tracing::debug!("skipping post as it already exists");
                            } else {
                                tracing::error!("{e}");
                            }
                        }
                    }
                }
                Feed::Rss(_channel) => {
                    // TODO: RSS support
                    tracing::warn!("rss not yet implemented");
                }
            }
        }
    }
}

#[derive(Debug)]
enum Feed {
    Atom(Box<atom_syndication::Feed>),
    Rss(Box<rss::Channel>),
}

#[derive(Error, Debug)]
#[error("Failed to parse feed")]
struct FeedParseError {
    atom: atom_syndication::Error,
    rss: rss::Error,
}

async fn fetch_feed(url: &str) -> eyre::Result<Feed> {
    let client = Client::new();
    let content = client.get(url).send().await?.bytes().await?;
    match atom_syndication::Feed::read_from(&content[..]) {
        Ok(feed) => Ok(Feed::Atom(Box::new(feed))),
        Err(atom_error) => match rss::Channel::read_from(&content[..]) {
            Ok(channel) => Ok(Feed::Rss(Box::new(channel))),
            Err(rss_error) => Err(eyre!(FeedParseError {
                atom: atom_error,
                rss: rss_error,
            })),
        },
    }
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
