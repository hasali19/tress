use sea_orm_migration::{prelude::*, schema::*};
use uuid::Uuid;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // 1. Create users table
        manager
            .create_table(
                Table::create()
                    .table(Users::Table)
                    .col(pk_uuid(Users::Id))
                    .col(string_uniq(Users::Name))
                    .to_owned(),
            )
            .await?;

        // 2. Insert a default user to own all existing data
        let default_user_id = Uuid::new_v4();
        let db = manager.get_connection();
        db.execute(
            db.get_database_backend().build(
                Query::insert()
                    .into_table(Users::Table)
                    .columns([Users::Id, Users::Name])
                    .values_panic([default_user_id.to_string().into(), "default".into()]),
            ),
        )
        .await?;

        // 3. Recreate feeds with user_id and updated unique constraint
        manager
            .create_table(
                Table::create()
                    .table(FeedsNew::Table)
                    .col(pk_uuid(FeedsNew::Id))
                    .col(uuid(FeedsNew::UserId))
                    .col(string(FeedsNew::Url))
                    .col(string(FeedsNew::Title))
                    .col(string_null(FeedsNew::Icon))
                    .col(string_null(FeedsNew::Thumbnail))
                    .foreign_key(
                        ForeignKey::create()
                            .from_col(FeedsNew::UserId)
                            .to_tbl(Users::Table)
                            .to_col(Users::Id),
                    )
                    .index(
                        Index::create()
                            .unique()
                            .col(FeedsNew::Url)
                            .col(FeedsNew::UserId),
                    )
                    .to_owned(),
            )
            .await?;

        db.execute(
            db.get_database_backend().build(
                Query::insert()
                    .into_table(FeedsNew::Table)
                    .columns([
                        FeedsNew::Id,
                        FeedsNew::UserId,
                        FeedsNew::Url,
                        FeedsNew::Title,
                        FeedsNew::Icon,
                        FeedsNew::Thumbnail,
                    ])
                    .select_from(
                        SelectStatement::new()
                            .column(Feeds::Id)
                            .expr(Expr::val(default_user_id.to_string()))
                            .column(Feeds::Url)
                            .column(Feeds::Title)
                            .column(Feeds::Icon)
                            .column(Feeds::Thumbnail)
                            .from(Feeds::Table)
                            .to_owned(),
                    )
                    .map_err(|e| DbErr::Custom(e.to_string()))?,
            ),
        )
        .await?;

        manager
            .drop_table(Table::drop().table(Feeds::Table).to_owned())
            .await?;

        manager
            .rename_table(
                Table::rename()
                    .table(FeedsNew::Table, Feeds::Table)
                    .to_owned(),
            )
            .await?;

        // 4. Recreate push_subscriptions with user_id
        manager
            .create_table(
                Table::create()
                    .table(PushSubscriptionsNew::Table)
                    .col(pk_auto(PushSubscriptionsNew::Id))
                    .col(uuid(PushSubscriptionsNew::UserId))
                    .col(string_uniq(PushSubscriptionsNew::Endpoint))
                    .col(string(PushSubscriptionsNew::AuthKey))
                    .col(string(PushSubscriptionsNew::P256dhKey))
                    .foreign_key(
                        ForeignKey::create()
                            .from_col(PushSubscriptionsNew::UserId)
                            .to_tbl(Users::Table)
                            .to_col(Users::Id),
                    )
                    .to_owned(),
            )
            .await?;

        db.execute(
            db.get_database_backend().build(
                Query::insert()
                    .into_table(PushSubscriptionsNew::Table)
                    .columns([
                        PushSubscriptionsNew::UserId,
                        PushSubscriptionsNew::Endpoint,
                        PushSubscriptionsNew::AuthKey,
                        PushSubscriptionsNew::P256dhKey,
                    ])
                    .select_from(
                        SelectStatement::new()
                            .expr(Expr::val(default_user_id.to_string()))
                            .column(PushSubscriptions::Endpoint)
                            .column(PushSubscriptions::AuthKey)
                            .column(PushSubscriptions::P256dhKey)
                            .from(PushSubscriptions::Table)
                            .to_owned(),
                    )
                    .map_err(|e| DbErr::Custom(e.to_string()))?,
            ),
        )
        .await?;

        manager
            .drop_table(Table::drop().table(PushSubscriptions::Table).to_owned())
            .await?;

        manager
            .rename_table(
                Table::rename()
                    .table(PushSubscriptionsNew::Table, PushSubscriptions::Table)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Recreate feeds without user_id, with UNIQUE(url)
        manager
            .create_table(
                Table::create()
                    .table(FeedsNew::Table)
                    .col(pk_uuid(FeedsNew::Id))
                    .col(string_uniq(FeedsNew::Url))
                    .col(string(FeedsNew::Title))
                    .col(string_null(FeedsNew::Icon))
                    .col(string_null(FeedsNew::Thumbnail))
                    .to_owned(),
            )
            .await?;

        let db = manager.get_connection();
        db.execute(
            db.get_database_backend().build(
                Query::insert()
                    .into_table(FeedsNew::Table)
                    .columns([
                        FeedsNew::Id,
                        FeedsNew::Url,
                        FeedsNew::Title,
                        FeedsNew::Icon,
                        FeedsNew::Thumbnail,
                    ])
                    .select_from(
                        SelectStatement::new()
                            .column(Feeds::Id)
                            .column(Feeds::Url)
                            .column(Feeds::Title)
                            .column(Feeds::Icon)
                            .column(Feeds::Thumbnail)
                            .from(Feeds::Table)
                            .to_owned(),
                    )
                    .map_err(|e| DbErr::Custom(e.to_string()))?,
            ),
        )
        .await?;

        manager
            .drop_table(Table::drop().table(Feeds::Table).to_owned())
            .await?;

        manager
            .rename_table(
                Table::rename()
                    .table(FeedsNew::Table, Feeds::Table)
                    .to_owned(),
            )
            .await?;

        // Recreate push_subscriptions without user_id
        manager
            .create_table(
                Table::create()
                    .table(PushSubscriptionsNew::Table)
                    .col(pk_auto(PushSubscriptionsNew::Id))
                    .col(string_uniq(PushSubscriptionsNew::Endpoint))
                    .col(string(PushSubscriptionsNew::AuthKey))
                    .col(string(PushSubscriptionsNew::P256dhKey))
                    .to_owned(),
            )
            .await?;

        db.execute(
            db.get_database_backend().build(
                Query::insert()
                    .into_table(PushSubscriptionsNew::Table)
                    .columns([
                        PushSubscriptionsNew::Endpoint,
                        PushSubscriptionsNew::AuthKey,
                        PushSubscriptionsNew::P256dhKey,
                    ])
                    .select_from(
                        SelectStatement::new()
                            .column(PushSubscriptions::Endpoint)
                            .column(PushSubscriptions::AuthKey)
                            .column(PushSubscriptions::P256dhKey)
                            .from(PushSubscriptions::Table)
                            .to_owned(),
                    )
                    .map_err(|e| DbErr::Custom(e.to_string()))?,
            ),
        )
        .await?;

        manager
            .drop_table(Table::drop().table(PushSubscriptions::Table).to_owned())
            .await?;

        manager
            .rename_table(
                Table::rename()
                    .table(PushSubscriptionsNew::Table, PushSubscriptions::Table)
                    .to_owned(),
            )
            .await?;

        manager
            .drop_table(Table::drop().table(Users::Table).to_owned())
            .await?;

        Ok(())
    }
}

#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
    Name,
}

#[derive(DeriveIden)]
#[sea_orm(table_name = "feeds")]
enum Feeds {
    Table,
    Id,
    Url,
    Title,
    Icon,
    Thumbnail,
}

#[derive(DeriveIden)]
#[sea_orm(table_name = "feeds_new")]
enum FeedsNew {
    Table,
    Id,
    UserId,
    Url,
    Title,
    Icon,
    Thumbnail,
}

#[derive(DeriveIden)]
#[sea_orm(table_name = "push_subscriptions")]
enum PushSubscriptions {
    Table,
    Endpoint,
    AuthKey,
    P256dhKey,
}

#[derive(DeriveIden)]
#[sea_orm(table_name = "push_subscriptions_new")]
enum PushSubscriptionsNew {
    Table,
    Id,
    UserId,
    Endpoint,
    AuthKey,
    P256dhKey,
}
