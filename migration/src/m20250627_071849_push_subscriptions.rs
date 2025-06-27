use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table("push_subscriptions")
                    .col(pk_auto("id"))
                    .col(string_uniq("endpoint"))
                    .col(string("auth_key"))
                    .col(string("p256dh_key"))
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table("push_subscriptions").to_owned())
            .await
    }
}
