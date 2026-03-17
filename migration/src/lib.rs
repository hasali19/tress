pub use sea_orm_migration::prelude::*;

mod m20220101_000001_create_table;
mod m20250627_071849_push_subscriptions;
mod m20260317_062834_add_users;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(m20220101_000001_create_table::Migration),
            Box::new(m20250627_071849_push_subscriptions::Migration),
            Box::new(m20260317_062834_add_users::Migration),
        ]
    }
}
