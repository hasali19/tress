FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

FROM chef AS planner-rust
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder-rust
COPY --from=planner-rust /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json
# Build application
COPY . .
RUN cargo build --release --bin tress

# We do not need the Rust toolchain to run the binary!
FROM debian:bookworm-slim AS runtime
WORKDIR /app
COPY --from=builder-rust /app/target/release/tress /usr/local/bin
ENTRYPOINT ["/usr/local/bin/tress"]
