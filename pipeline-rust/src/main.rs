use axum::{
    routing::{get, post},
    Router,
    response::IntoResponse,
    Json,
    extract::State,
};
use sqlx::postgres::PgPoolOptions;
use std::time::Instant;
use serde_json::json;

#[tokio::main]
async fn main() {

    let db_url = "postgres://postgres:postgres@localhost:5433/postgres";
    
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(db_url)
        .await
        .expect("Failed to connect to PostgreSQL");

    // 2. 리스크 데이터 적재용 테이블 자동 생성
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS risk_logs (
            id SERIAL PRIMARY KEY,
            user_id INT NOT NULL,
            risk_score FLOAT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )"
    )
    .execute(&pool)
    .await
    .unwrap();

    // 3. Axum 라우터 구성 및 상태(커넥션 풀) 공유
    let app = Router::new()
        .route("/api/rust/status", get(status_handler))
        .route("/api/bulk-insert", post(bulk_insert))
        .with_state(pool);

    println!("[Rust Pipeline] Server is running on http://0.0.0.0:8081");
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8081").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

// 상태 확인 핸들러
async fn status_handler(State(pool): State<sqlx::PgPool>) -> impl IntoResponse {
    let row_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM risk_logs")
        .fetch_one(&pool)
        .await
        .unwrap_or(0);

    Json(json!({
        "status": "online",
        "module": "Rust-Pipeline-v1",
        "total_risk_logs": row_count
    }))
}

// 대규모 데이터 적재 핸들러
async fn bulk_insert(State(pool): State<sqlx::PgPool>) -> impl IntoResponse {
    let start_time = Instant::now();
    let record_count = 10000;

    // 4. 트랜잭션 시작 (벌크 인서트의 핵심: 하나씩 넣지 않고 모아서 한 번에 커밋)
    let mut tx = pool.begin().await.expect("Failed to begin transaction");

    for i in 0..record_count {
        // 복잡한 연산 결과를 시뮬레이션한 리스크 점수
        let risk_score = (i as f64) * 0.12345;
        
        sqlx::query("INSERT INTO risk_logs (user_id, risk_score) VALUES ($1, $2)")
            .bind(i)
            .bind(risk_score)
            .execute(&mut *tx)
            .await
            .expect("Failed to insert record");
    }

    // 5. 트랜잭션 커밋 (이때 실제 DB에 일괄 기록됨)
    tx.commit().await.expect("Failed to commit transaction");

    let elapsed = start_time.elapsed();
    println!("Inserted {} records in {:?}", record_count, elapsed);

    // 결과를 JSON으로 반환
    Json(json!({
        "status": "success",
        "inserted_rows": record_count,
        "elapsed_time_ms": elapsed.as_millis()
    }))
}