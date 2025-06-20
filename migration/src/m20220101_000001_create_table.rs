use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table("feeds")
                    .col(pk_uuid("id"))
                    .col(string_uniq("url"))
                    .col(string("title"))
                    .col(string_null("icon"))
                    .col(string_null("thumbnail"))
                    .to_owned(),
            )
            .await?;

        manager
            .create_table(
                Table::create()
                    .table("posts")
                    .col(pk_uuid("id"))
                    .col(uuid("feed_id"))
                    .col(string_uniq("url"))
                    .col(string("title"))
                    .col(string("publish_time"))
                    .col(string_null("description"))
                    .col(string_null("content"))
                    .col(string_null("thumbnail"))
                    .foreign_key(
                        ForeignKey::create()
                            .from_col("feed_id")
                            .to_tbl("feeds")
                            .to_col("id"),
                    )
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table("posts").to_owned())
            .await?;

        manager
            .drop_table(Table::drop().table("feeds").to_owned())
            .await?;

        Ok(())
    }
}
