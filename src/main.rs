mod entities;

use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{any, get, post};
use axum::{Json, Router};
use backon::{ExponentialBuilder, Retryable};
use base64ct::{Base64UrlUnpadded, Encoding};
use eyre::eyre;
use itertools::Itertools;
use migration::{Migrator, MigratorTrait, OnConflict};
use reqwest::{Client, Request};
use scraper::{Html, Selector};
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
use web_push_native::jwt_simple::prelude::{ECDSAP256KeyPairLike, ES256KeyPair};
use web_push_native::p256::PublicKey;
use web_push_native::{Auth, WebPushBuilder};

use crate::entities::prelude::*;
use crate::entities::{feeds, posts, push_subscriptions};

#[derive(Clone)]
struct App {
    db: DatabaseConnection,
    sync_sender: mpsc::UnboundedSender<SyncRequest>,
    http_client: Client,
    vapid_key: Arc<ES256KeyPair>,
}

#[tokio::main]
async fn main() -> eyre::Result<()> {
    color_eyre::install()?;

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| format!("info,{}=debug", env!("CARGO_CRATE_NAME")).into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let db = init_db().await?;

    let key_path = Path::new("data/private_key.pem");
    let vapid_key = Arc::new(if let Ok(key) = std::fs::read_to_string(key_path) {
        ES256KeyPair::from_pem(&key).map_err(|e| eyre!(e))?
    } else {
        let key = ES256KeyPair::generate();
        let pem = key.to_pem().map_err(|e| eyre!(e))?;
        std::fs::write(key_path, pem)?;
        key
    });

    let (sync_sender, sync_receiver) = mpsc::unbounded_channel();

    tokio::spawn({
        let sync_sender = sync_sender.clone();
        async move {
            sync_sender
                .send(SyncRequest {
                    scope: SyncScope::All,
                    notify: true,
                })
                .unwrap();
            tokio::time::sleep(Duration::from_secs(60 * 60)).await;
        }
    });

    let http_client = Client::new();
    let push_client = PushClient {
        http_client: http_client.clone(),
        vapid_key: vapid_key.clone(),
    };

    tokio::spawn(run_sync_worker(
        sync_receiver,
        http_client.clone(),
        db.clone(),
        push_client,
    ));

    let api = Router::new()
        .route("/config", get(get_config))
        .route("/push_subscriptions", post(create_push_subscription))
        .route("/feeds", get(get_feeds).post(add_feed))
        .route("/posts", get(get_posts))
        .fallback(any((
            StatusCode::NOT_FOUND,
            Json(json!({"message": "not found"})),
        )))
        .with_state(App {
            db: db.clone(),
            sync_sender,
            http_client,
            vapid_key,
        });

    let app = Router::new()
        .nest("/api", api)
        .fallback_service(ServeDir::new("ui/dist").fallback(ServeFile::new("ui/dist/index.html")));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();

    tracing::info!("server listening at http://{}", listener.local_addr()?);

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    db.close().await?;

    Ok(())
}

#[derive(Clone)]
struct PushClient {
    http_client: Client,
    vapid_key: Arc<ES256KeyPair>,
}

impl PushClient {
    async fn send_message(
        &self,
        subscription: &push_subscriptions::Model,
        message: &impl serde::Serialize,
    ) -> eyre::Result<()> {
        let req = WebPushBuilder::new(
            subscription.endpoint.parse()?,
            PublicKey::from_sec1_bytes(&Base64UrlUnpadded::decode_vec(&subscription.p256dh_key)?)?,
            Auth::clone_from_slice(&Base64UrlUnpadded::decode_vec(&subscription.auth_key)?),
        )
        .with_vapid(&self.vapid_key, "mailto:hasan@hasali.dev")
        .build(serde_json::to_vec(message)?)?;

        self.http_client
            .execute(Request::try_from(req)?)
            .await?
            .error_for_status()?;

        Ok(())
    }
}

async fn init_db() -> eyre::Result<DatabaseConnection> {
    // TODO: DB url should be configurable
    let mut options = ConnectOptions::new("sqlite://data/tress.db?mode=rwc");
    options
        .max_connections(1)
        .sqlx_logging_level(log::LevelFilter::Debug);
    let db = Database::connect(options).await?;
    Migrator::up(&db, None).await?;
    Ok(db)
}

#[derive(Debug, Deserialize)]
struct PushSubscriptionReq {
    subscription: PushSubscriptionData,
}

#[derive(Debug, Deserialize)]
struct PushSubscriptionData {
    endpoint: String,
    keys: PushSubscriptionKeys,
}

#[derive(Debug, Deserialize)]
struct PushSubscriptionKeys {
    auth: String,
    p256dh: String,
}

async fn create_push_subscription(State(app): State<App>, Json(body): Json<PushSubscriptionReq>) {
    let subscription = push_subscriptions::ActiveModel {
        id: ActiveValue::NotSet,
        endpoint: ActiveValue::Set(body.subscription.endpoint),
        auth_key: ActiveValue::Set(body.subscription.keys.auth),
        p256dh_key: ActiveValue::Set(body.subscription.keys.p256dh),
    };

    PushSubscriptions::insert(subscription)
        .on_conflict(
            OnConflict::column("endpoint")
                .update_columns(["auth_key", "p256dh_key"])
                .to_owned(),
        )
        .exec(&app.db)
        .await
        .unwrap();
}

async fn get_config(State(app): State<App>) -> impl IntoResponse {
    let public_key_bytes = app
        .vapid_key
        .key_pair()
        .public_key()
        .to_bytes_uncompressed();

    Json(json!({
        "vapid": {
            "public_key": Base64UrlUnpadded::encode_string(&public_key_bytes),
        }
    }))
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
    let feed = fetch_feed(&app.http_client, &req.url).await.unwrap();

    let title = match feed {
        Feed::Atom(feed) => feed.title.value,
        Feed::Rss(channel) => channel.title,
    };

    let feed = feeds::ActiveModel {
        id: ActiveValue::Set(Uuid::new_v4()),
        title: ActiveValue::Set(title),
        url: ActiveValue::Set(req.url),
        ..Default::default()
    };

    let feed = match feed.insert(&app.db).await {
        Ok(feed) => feed,
        Err(e) => {
            tracing::error!("{e}");
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }
    };

    tracing::info!("added feed: {feed:?}");

    let _ = app.sync_sender.send(SyncRequest {
        scope: SyncScope::Feed(feed.id),
        notify: false,
    });

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

struct SyncRequest {
    scope: SyncScope,
    notify: bool,
}

enum SyncScope {
    All,
    Feed(Uuid),
}

async fn run_sync_worker(
    mut receiver: mpsc::UnboundedReceiver<SyncRequest>,
    http_client: Client,
    db: DatabaseConnection,
    push_client: PushClient,
) {
    while let Some(req) = receiver.recv().await {
        let feeds = match req.scope {
            SyncScope::All => Feeds::find().all(&db).await.unwrap(),
            SyncScope::Feed(id) => Feeds::find_by_id(id)
                .one(&db)
                .await
                .unwrap()
                .into_iter()
                .collect_vec(),
        };

        for feed_model in feeds {
            tracing::info!("syncing posts from {}", feed_model.url);

            let feed = fetch_feed(&http_client, &feed_model.url).await.unwrap();

            match feed {
                Feed::Atom(feed) => {
                    for entry in feed.entries {
                        let description =
                            entry.summary().map(|v| v.value.as_str()).map(|summary| {
                                let html = Html::parse_fragment(summary);
                                html.root_element().text().join("")
                            });

                        let post_id = Uuid::new_v4();
                        let post = posts::ActiveModel {
                            id: ActiveValue::Set(post_id),
                            feed_id: ActiveValue::Set(feed_model.id),
                            url: ActiveValue::Set(entry.id),
                            title: ActiveValue::Set(entry.title.value),
                            description: ActiveValue::Set(description),
                            content: ActiveValue::Set(
                                entry.content.and_then(|content| content.value),
                            ),
                            publish_time: ActiveValue::Set(entry.updated.to_rfc3339()),
                            thumbnail: ActiveValue::Set(None),
                        };

                        tracing::debug!(?post.title, ?post.url, "inserting post");

                        let post = match post.insert(&db).await {
                            Ok(post) => post,
                            Err(e) => {
                                if let Some(SqlErr::UniqueConstraintViolation(_)) = e.sql_err() {
                                    tracing::debug!("skipping post as it already exists");
                                } else {
                                    tracing::error!("{e}");
                                }
                                continue;
                            }
                        };

                        let content = (|| fetch_page_content(&http_client, &post.url))
                            .retry(ExponentialBuilder::default())
                            .sleep(tokio::time::sleep)
                            .notify(|err, duration| {
                                tracing::warn!("retrying {err:?} after {duration:?}");
                            })
                            .await
                            .unwrap();

                        let image = {
                            Html::parse_document(&content)
                                .select(&Selector::parse("meta[property=\"og:image\"]").unwrap())
                                .next()
                                .and_then(|el| el.attr("content"))
                                .map(ToOwned::to_owned)
                        };

                        posts::ActiveModel {
                            id: ActiveValue::Unchanged(post_id),
                            thumbnail: ActiveValue::Set(image),
                            ..Default::default()
                        }
                        .update(&db)
                        .await
                        .unwrap();

                        if req.notify {
                            for subscription in PushSubscriptions::find().all(&db).await.unwrap() {
                                if let Err(e) = push_client
                                    .send_message(
                                        &subscription,
                                        &json!({
                                            "id": post.id.to_string(),
                                            "title": post.title,
                                        }),
                                    )
                                    .await
                                {
                                    tracing::error!(
                                        subscription.id,
                                        subscription.endpoint,
                                        "Failed to send push message: {e}",
                                    );
                                }
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

async fn fetch_page_content(client: &Client, url: &str) -> eyre::Result<String> {
    let text = client.get(url).send().await?.text().await?;
    Ok(text)
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

async fn fetch_feed(client: &Client, url: &str) -> eyre::Result<Feed> {
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
