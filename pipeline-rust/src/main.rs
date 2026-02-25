use axum::{
    routing::{get, post},
    Router,
    Json,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

#[derive(Serialize)]
struct StatusResponse {
    module: String,
    status: String,
    message: String,
}

#[derive(Deserialize)]
struct ComputeRequest {
    data_size: usize,
}

#[derive(Serialize)]
struct ComputeResponse {
    processed_count: usize,
    elapsed_ms: u128,
}

#[tokio::main]
async fn main(){
    let app = Router::new()
    .route("/api/rust/status",get(status_handler))
    .route("/api/rust/compute", post(compute_handler));

    let addr = SocketAddr::from(([0, 0, 0, 0], 8081));
    println!("Rust Pipeline Server running on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn status_handler() -> Json<StatusResponse> {
    Json(StatusResponse {
        module: "Rust-Pipeline-v1".to_string(),
        status: "online".to_string(),
        message: "Ready for high-performance processing".to_string(),
    })
}

async fn compute_handler(Json(payload): Json<ComputeRequest>) -> Json<ComputeResponse> {
    let start = std::time::Instant::now();

    let mut sum: u64 = 0;
    for i in 0..payload.data_size {
        sum = sum.wrapping_add(i as u64);
    }

    let duration = start.elapsed();

    Json(ComputeResponse {
        processed_count: payload.data_size,
        elapsed_ms: duration.as_millis(),
    })
}