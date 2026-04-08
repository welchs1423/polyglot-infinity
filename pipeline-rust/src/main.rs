mod ffi;

use axum::{
    routing::{get, post},
    Router,
    response::IntoResponse,
    Json,
    extract::State,
};
use serde::Deserialize;
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

/// Request body for matrix multiplication: C = A * B.
/// A is [m x k] row-major, B is [k x n] row-major.
#[derive(Deserialize)]
struct MultiplyRequest {
    a: Vec<f64>,
    m: i32,
    k: i32,
    b: Vec<f64>,
    n: i32,
}

/// Request body for sample covariance matrix computation.
/// returns is [assets x periods] row-major.
#[derive(Deserialize)]
struct CovarianceRequest {
    returns: Vec<f64>,
    assets: i32,
    periods: i32,
}

/// Request body for Cholesky decomposition (A = L * L^T).
/// matrix is [n x n] row-major, symmetric positive-definite.
#[derive(Deserialize)]
struct CholeskyRequest {
    matrix: Vec<f64>,
    n: i32,
}

/// Request body for Frobenius norm computation.
/// matrix is [m x n] row-major.
#[derive(Deserialize)]
struct FrobeniusRequest {
    matrix: Vec<f64>,
    m: i32,
    n: i32,
}

/// Request body for portfolio variance: v = w^T * cov * w.
#[derive(Deserialize)]
struct PortfolioVarRequest {
    cov: Vec<f64>,
    weights: Vec<f64>,
    assets: i32,
}

#[tokio::main]
async fn main() {

    let db_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:5433/postgres".to_string());
    
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&db_url)
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
        .route("/api/risk/summary", get(risk_summary))
        .route("/health", get(health_handler))
        /* Matrix FFI endpoints */
        .route("/api/matrix/multiply",   post(matrix_multiply_handler))
        .route("/api/matrix/covariance",  post(matrix_covariance_handler))
        .route("/api/matrix/cholesky",   post(matrix_cholesky_handler))
        .route("/api/matrix/frobenius",  post(matrix_frobenius_handler))
        .route("/api/portfolio/variance", post(portfolio_variance_handler))
        .with_state(pool);

    println!("[Rust Pipeline] Server is running on http://0.0.0.0:8081");
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8081").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

// VaR 통계 요약 핸들러 — risk_logs 전체에서 min/max/avg/p95 조회
async fn risk_summary(State(pool): State<sqlx::PgPool>) -> impl IntoResponse {
    // query! 매크로는 DATABASE_URL이 필요하므로 query()로 직접 파싱
    let row: Result<(Option<i64>, Option<f64>, Option<f64>, Option<f64>, Option<f64>), _> =
        sqlx::query_as(
            r#"SELECT
                COUNT(*)::BIGINT,
                MIN(risk_score),
                MAX(risk_score),
                AVG(risk_score),
                PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY risk_score)
               FROM risk_logs"#,
        )
        .fetch_one(&pool)
        .await;

    match row {
        Ok((count, min_v, max_v, avg_v, p95_v)) => {
            let round2 = |v: Option<f64>| v.map(|x| (x * 100.0).round() / 100.0);
            Json(json!({
                "engine":  "Rust-Pipeline-v2",
                "model":   "daily_VaR_95 (position × annual_vol/√252 × z₀.₉₅)",
                "count":   count,
                "min_var": round2(min_v),
                "max_var": round2(max_v),
                "avg_var": round2(avg_v),
                "p95_var": round2(p95_v),
            }))
        }
        Err(_) => Json(json!({
            "error": "risk_logs 테이블이 비어있거나 /api/bulk-insert 를 먼저 실행하세요"
        })),
    }
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
    let record_count: i32 = 10000;

    // 테이블이 없을 경우 자동 생성 후 재시도할 수 있도록 먼저 ensure
    let ensure = sqlx::query(
        "CREATE TABLE IF NOT EXISTS risk_logs (
            id SERIAL PRIMARY KEY,
            user_id INT NOT NULL,
            risk_score FLOAT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )",
    )
    .execute(&pool)
    .await;

    if let Err(e) = ensure {
        eprintln!("[Rust Pipeline] bulk_insert: table ensure failed: {e}");
        return Json(json!({
            "status":  "error",
            "message": format!("DB schema ensure failed: {e}"),
            "inserted_rows": 0
        }));
    }

    // 트랜잭션 시작
    let tx_result = pool.begin().await;
    let mut tx = match tx_result {
        Ok(tx) => tx,
        Err(e) => {
            eprintln!("[Rust Pipeline] bulk_insert: begin tx failed: {e}");
            return Json(json!({
                "status":  "error",
                "message": format!("Failed to begin transaction: {e}"),
                "inserted_rows": 0
            }));
        }
    };

    for i in 0..record_count {
        let risk_score = daily_var_95(i);
        let insert_result =
            sqlx::query("INSERT INTO risk_logs (user_id, risk_score) VALUES ($1, $2)")
                .bind(i)
                .bind(risk_score)
                .execute(&mut *tx)
                .await;

        if let Err(e) = insert_result {
            eprintln!("[Rust Pipeline] bulk_insert: insert row {i} failed: {e}");
            let _ = tx.rollback().await;
            return Json(json!({
                "status":  "error",
                "message": format!("Insert failed at row {i}: {e}"),
                "inserted_rows": i
            }));
        }
    }

    // 트랜잭션 커밋
    if let Err(e) = tx.commit().await {
        eprintln!("[Rust Pipeline] bulk_insert: commit failed: {e}");
        return Json(json!({
            "status":  "error",
            "message": format!("Failed to commit transaction: {e}"),
            "inserted_rows": 0
        }));
    }

    let elapsed = start_time.elapsed();
    println!("[Rust Pipeline] Inserted {} VaR records in {:?}", record_count, elapsed);

    let var_first = daily_var_95(0);
    let var_last  = daily_var_95(record_count - 1);

    Json(json!({
        "status": "success",
        "inserted_rows": record_count,
        "elapsed_time_ms": elapsed.as_millis(),
        "model": "daily_VaR_95",
        "formula": "position x (annual_vol / sqrt(252)) x z_0.95",
        "sample_var_first_krw": (var_first * 100.0).round() / 100.0,
        "sample_var_last_krw":  (var_last  * 100.0).round() / 100.0
    }))
}

/* ── Matrix FFI handlers ──────────────────────────────────────────────── */

/*
 * POST /api/matrix/multiply
 *
 * Computes C = A * B using the C++ cache-tiled implementation.
 * The output buffer is allocated by Rust (zero-copy into C++).
 *
 * Request  : { "a": [f64...], "m": int, "k": int, "b": [f64...], "n": int }
 * Response : { "result": [f64...], "rows": int, "cols": int, "elapsed_us": u128 }
 */
async fn matrix_multiply_handler(
    Json(req): Json<MultiplyRequest>,
) -> impl IntoResponse {
    let expected_a = (req.m as usize).saturating_mul(req.k as usize);
    let expected_b = (req.k as usize).saturating_mul(req.n as usize);

    if req.m <= 0 || req.k <= 0 || req.n <= 0
        || req.a.len() != expected_a
        || req.b.len() != expected_b
    {
        return Json(json!({ "error": "invalid dimensions or mismatched input lengths" }));
    }

    let (m, k, n) = (req.m, req.k, req.n);
    let a = req.a;
    let b = req.b;

    /*
     * CPU-bound work is offloaded to the blocking thread pool so the async
     * executor is not stalled.  The owned Vec<f64> values are moved into the
     * closure; no additional allocation is required.
     */
    let result = tokio::task::spawn_blocking(move || {
        let t0 = Instant::now();
        let out = ffi::multiply_zero_copy(&a, m, k, &b, n);
        (out, t0.elapsed())
    })
    .await
    .expect("blocking task panicked");

    Json(json!({
        "result":     result.0,
        "rows":       m,
        "cols":       n,
        "elapsed_us": result.1.as_micros(),
    }))
}

/*
 * POST /api/matrix/covariance
 *
 * Computes the sample covariance matrix of a returns matrix.
 * The output buffer is allocated by Rust (zero-copy into C++).
 *
 * Request  : { "returns": [f64...], "assets": int, "periods": int }
 * Response : { "covariance": [f64...], "assets": int, "elapsed_us": u128 }
 */
async fn matrix_covariance_handler(
    Json(req): Json<CovarianceRequest>,
) -> impl IntoResponse {
    let expected = (req.assets as usize).saturating_mul(req.periods as usize);

    if req.assets <= 0 || req.periods < 2 || req.returns.len() != expected {
        return Json(json!({ "error": "assets > 0, periods >= 2, and returns length must equal assets*periods" }));
    }

    let (assets, periods) = (req.assets, req.periods);
    let returns = req.returns;

    let result = tokio::task::spawn_blocking(move || {
        let t0 = Instant::now();
        let cov = ffi::covariance(&returns, assets, periods);
        (cov, t0.elapsed())
    })
    .await
    .expect("blocking task panicked");

    Json(json!({
        "covariance": result.0,
        "assets":     assets,
        "elapsed_us": result.1.as_micros(),
    }))
}

/*
 * POST /api/matrix/cholesky
 *
 * Computes the Cholesky factor L such that A = L * L^T.
 * A must be a symmetric positive-definite matrix.
 * The output buffer is allocated by Rust (zero-copy into C++).
 *
 * Request  : { "matrix": [f64...], "n": int }
 * Response : { "l": [f64...], "n": int, "elapsed_us": u128 }
 *          | { "error": "..." }
 */
async fn matrix_cholesky_handler(
    Json(req): Json<CholeskyRequest>,
) -> impl IntoResponse {
    let expected = (req.n as usize).saturating_mul(req.n as usize);

    if req.n <= 0 || req.matrix.len() != expected {
        return Json(json!({ "error": "n must be positive and matrix length must equal n*n" }));
    }

    let n = req.n;
    let matrix = req.matrix;

    let result = tokio::task::spawn_blocking(move || {
        let t0 = Instant::now();
        let l = ffi::cholesky(&matrix, n);
        (l, t0.elapsed())
    })
    .await
    .expect("blocking task panicked");

    match result.0 {
        Some(l) => Json(json!({
            "l":          l,
            "n":          n,
            "elapsed_us": result.1.as_micros(),
        })),
        None => Json(json!({
            "error": "matrix is not symmetric positive-definite"
        })),
    }
}

/*
 * POST /api/portfolio/variance
 *
 * Computes the scalar portfolio variance v = w^T * cov * w.
 * An internal temporary buffer is allocated and freed inside the C++ function.
 *
 * Request  : { "cov": [f64...], "weights": [f64...], "assets": int }
 * Response : { "variance": f64, "std_dev": f64, "elapsed_us": u128 }
 */
async fn portfolio_variance_handler(
    Json(req): Json<PortfolioVarRequest>,
) -> impl IntoResponse {
    let expected_cov = (req.assets as usize).saturating_mul(req.assets as usize);

    if req.assets <= 0
        || req.cov.len() != expected_cov
        || req.weights.len() != req.assets as usize
    {
        return Json(json!({ "error": "assets must be positive; cov length must equal assets^2; weights length must equal assets" }));
    }

    let assets = req.assets;
    let cov = req.cov;
    let weights = req.weights;

    let result = tokio::task::spawn_blocking(move || {
        let t0 = Instant::now();
        let var = ffi::portfolio_var(&cov, &weights, assets);
        (var, t0.elapsed())
    })
    .await
    .expect("blocking task panicked");

    let variance = result.0;
    Json(json!({
        "variance":   variance,
        "std_dev":    variance.sqrt(),
        "assets":     assets,
        "elapsed_us": result.1.as_micros(),
    }))
}

/*
 * POST /api/matrix/frobenius
 *
 * Computes the Frobenius norm: sqrt( sum_{i,j} A[i,j]^2 ).
 * Read-only over the input; no allocation in C++.
 *
 * Request  : { "matrix": [f64...], "m": int, "n": int }
 * Response : { "norm": f64, "rows": int, "cols": int, "elapsed_us": u128 }
 */
async fn matrix_frobenius_handler(
    Json(req): Json<FrobeniusRequest>,
) -> impl IntoResponse {
    let expected = (req.m as usize).saturating_mul(req.n as usize);

    if req.m <= 0 || req.n <= 0 || req.matrix.len() != expected {
        return Json(json!({ "error": "m and n must be positive and matrix length must equal m*n" }));
    }

    let (m, n) = (req.m, req.n);
    let matrix = req.matrix;

    let result = tokio::task::spawn_blocking(move || {
        let t0 = Instant::now();
        let norm = ffi::frobenius_norm(&matrix, m, n);
        (norm, t0.elapsed())
    })
    .await
    .expect("blocking task panicked");

    Json(json!({
        "norm":       result.0,
        "rows":       m,
        "cols":       n,
        "elapsed_us": result.1.as_micros(),
    }))
}