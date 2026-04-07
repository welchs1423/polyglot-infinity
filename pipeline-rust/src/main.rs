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

// ── 결정론적 VaR(95%) 계산 ─────────────────────────────────────────
//
// rand crate 없이 Xorshift64 PRNG로 사용자별 포지션·변동성을 생성한 뒤
// 일별 VaR(95%) = position * (annual_vol / √252) * z_{0.95} 를 계산한다.
//
// z_{0.95} = 1.6448536

/// Xorshift64: 시드에서 (0,1) uniform 값 두 개를 뽑아 반환
fn xorshift_pair(seed: u64) -> (f64, f64) {
    let mut x = seed ^ 0x9e37_79b9_7f4a_7c15;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    let u1 = (x & 0x001F_FFFF_FFFF_FFFF) as f64 / (1u64 << 53) as f64;

    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    let u2 = (x & 0x001F_FFFF_FFFF_FFFF) as f64 / (1u64 << 53) as f64;

    (u1, u2)
}

/// 사용자 i에 대한 일별 VaR(95%) 추정값 (단위: 원)
///
/// - position_krw : U(5_000_000, 100_000_000)  — 5백만~1억원 포지션
/// - annual_vol   : U(0.08, 0.55)              — 8%~55% 연간 변동성
/// - daily_VaR    = position × (vol / √252) × 1.6448536
fn daily_var_95(user_id: i32) -> f64 {
    let (u1, u2) = xorshift_pair(user_id as u64 ^ 0xDEAD_BEEF_CAFE_F00D);
    let position = 5_000_000.0 + 95_000_000.0 * u1;
    let annual_vol = 0.08 + 0.47 * u2;
    let daily_vol = annual_vol / 252_f64.sqrt();
    position * daily_vol * 1.644_853_6
}

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
        .route("/health", get(health_handler))
        .with_state(pool);

    println!("[Rust Pipeline] Server is running on http://0.0.0.0:8081");
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8081").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

// 헬스체크 핸들러
async fn health_handler() -> impl IntoResponse {
    Json(json!({
        "status": "ok",
        "engine": "Rust-Pipeline-v2",
        "port": 8081
    }))
}

// 상태 확인 핸들러
async fn status_handler(State(pool): State<sqlx::PgPool>) -> impl IntoResponse {
    let row_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM risk_logs")
        .fetch_one(&pool)
        .await
        .unwrap_or(0);

    Json(json!({
        "status": "online",
        "module": "Rust-Pipeline-v2",
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
        // 사용자별 일별 VaR(95%): Xorshift64 기반 포지션·변동성 샘플링 후
        // daily_VaR = position × (annual_vol / √252) × z_{0.95}
        let risk_score = daily_var_95(i);

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
    println!("[Rust Pipeline] Inserted {} VaR records in {:?}", record_count, elapsed);

    // 통계 샘플 (첫 행·마지막 행 VaR 참고값)
    let var_first = daily_var_95(0);
    let var_last  = daily_var_95(record_count - 1);

    Json(json!({
        "status": "success",
        "inserted_rows": record_count,
        "elapsed_time_ms": elapsed.as_millis(),
        "model": "daily_VaR_95",
        "formula": "position × (annual_vol / √252) × z_{0.95}",
        "sample_var_first_krw": (var_first * 100.0).round() / 100.0,
        "sample_var_last_krw":  (var_last  * 100.0).round() / 100.0
    }))
}