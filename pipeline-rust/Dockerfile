FROM rust:1.88-alpine AS builder
RUN apk add --no-cache musl-dev openssl-dev openssl-libs-static pkgconfig g++
WORKDIR /app
ENV SQLX_OFFLINE=true
COPY pipeline-rust/Cargo.toml pipeline-rust/Cargo.lock pipeline-rust/build.rs ./
COPY core-cpp/src /core-cpp/src
RUN mkdir src && echo "fn main(){}" > src/main.rs && cargo build --release 2>/dev/null || true
COPY pipeline-rust/src ./src
RUN touch src/main.rs && cargo build --release

FROM alpine:3.19
RUN apk add --no-cache libgcc openssl
WORKDIR /app
COPY --from=builder /app/target/release/pipeline-rust ./server
EXPOSE 8081
CMD ["./server"]
