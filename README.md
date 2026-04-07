# 🌈 Polyglot Infinity

28개 언어/런타임과 2개 DB(PostgreSQL · Redis)로 구성된 **실시간 다중 통화 마이크로 대출 리스크 분석 플랫폼**

---

## 서비스 맵

| # | 언어 | 포트 | 핵심 특징 |
|:-:|:---|:---:|:---|
| 1 | **Svelte 5** (SvelteKit + Bun) | 5173 | 실시간 대시보드 UI |
| 2 | **Go** `net/http` | 8080 | API Hub · Redis 캐싱 · SSE 스트림 · 서킷 브레이커 |
| 3 | **Python** FastAPI | 8000 | 환율 수집 · C++/Zig FFI · Julia HTTP |
| 4 | **Rust** Axum + sqlx | 8081 | 고성능 벌크 인서트 파이프라인 |
| 5 | **C++** | — | `libcore.so` — Python FFI 연산 가속 |
| 6 | **Zig 0.13** | — | `libzigcore.so` — 변동성 추정 · VaR (C ABI) |
| 7 | **WebAssembly** (Zig → WASM32) | Browser | 서버 없이 브라우저에서 Black-Scholes Greeks · VaR · DCF · MC |
| 8 | **Lua 5.4** | — / 8007 | Redis EVAL 원자적 캐시 카운터 · 코루틴 6-피드 스케줄러 |
| 9 | **Kotlin 2.0** | 9000 | 코루틴 60초 주기 리스크 리포트 스케줄러 |
| 10 | **Elixir/Phoenix** | 4000 | OTP Supervisor · GenServer · WebSocket Channel |
| 11 | **Julia 1.10** | 8002 | `Threads.@threads` GBM Monte Carlo · VaR/CVaR |
| 12 | **R 4.1** | 8003 | MLE 분포 피팅 · GARCH · ARIMA · Sharpe |
| 13 | **F# (.NET 8)** | 9001 | Black-Scholes Greeks · Implied Volatility · DCF |
| 14 | **OCaml 4.13** | 8004 | 규칙 기반 리스크 판정 · 로지스틱 신용 스코어링 |
| 15 | **Crystal 1.19** | 9002 | `spawn`/`Channel` 파이버 — 4소스 병렬 FX 수집 (~1.8x) |
| 16 | **Nim 2.2.8** | 8005 | `static:` 컴파일타임 EMA/RSI 테이블 · 런타임 나눗셈 0회 |
| 17 | **Scala 3** | 9003 | `enum` ADT + `LazyList.unfold` 무한 스트림 + `given` 타입클래스 |
| 18 | **Haskell GHC** | 8006 | 순수 함수형 Black-Scholes Greeks · GBM Monte Carlo |
| 19 | **Ruby 3.0** | 9004 | `instance_eval` 런타임 DSL — 재시작 없이 규칙 동적 적재 |
| 20 | **Dart 3.11** | 9005 | 채권 가격 · Duration · Nelson-Siegel 수익률 곡선 |
| 21 | **Gleam 1.15** | 4001 | `ServiceMessage` ADT · exhaustive pattern match 컴파일 강제 |
| 22 | **V 0.5.1** | 4002 | `--gc none` Zero-GC MA 크로스오버 전략 백테스터 |
| 23 | **Erlang/OTP 24** | 4003 | `code:load_file/1` 핫 코드 스왑 · 0ms 다운타임 |
| 24 | **Swift 6.1** | 8008 | `actor` — 컴파일 타임 data race 차단 |
| 25 | **Clojure 1.10** | 8009 | `ref`+`dosync` STM — 잠금 없는 원자적 이체 |
| 26 | **Java 21** Project Loom | 8010 | `Thread.ofVirtual()` 5만 가상 스레드 (~6x vs platform) |
| 27 | **SWI-Prolog 8.4** | 8011 | 선언적 제약 규칙 → 백트래킹 포트폴리오 탐색 |
| — | **PostgreSQL** | 5432/5433 | 시스템 로그 · 리스크 데이터 |
| — | **Redis** | 6379 | 분석 결과 캐싱 (Lua EVAL 원자적 연산) |

---

## 아키텍처

```
[Svelte 5 :5173]
      │ fetch / SSE
      ▼
[Go Hub :8080] ── Redis :6379 (Lua EVAL 캐시)
      │
      ├─ [Python :8000] ── C++ libcore.so
      │                 ── Zig libzigcore.so
      │                 ── Julia :8002
      │
      ├─ [Rust :8081] ── PostgreSQL :5433
      │
      └─ 워크플로 오케스트레이션 (Python→Rust→Kotlin 파이프라인)
           └─ 서킷 브레이커 (closed/open/half-open)

독립 서비스: Kotlin·Elixir·R·F#·OCaml·Crystal·Nim·Scala·Haskell
            Ruby·Dart·Gleam·V·Erlang·Lua·Swift·Clojure·Java·Prolog

[WebAssembly] — 브라우저에서 직접 실행 (서버 왕복 없음)
```

---

## 주요 API (Go Hub :8080)

| Method | Endpoint | 설명 |
|:---|:---|:---|
| GET | `/api/status` | 전체 시스템 상태 |
| GET | `/api/aggregate` | 28개 백엔드 헬스체크 병렬 집계 |
| GET | `/api/aggregate/stream` | **SSE** — 서비스 상태 실시간 스트림 |
| GET | `/api/report` | 통합 리스크 리포트 (DB 통계 포함) |
| GET | `/api/workflow/risk-full` | Python→Rust→Kotlin 엔드-투-엔드 파이프라인 |
| GET | `/api/workflow/option-compare` | F# · Haskell · Python 3-엔진 BS 가격 비교 |
| GET | `/api/circuit/status` | 서킷 브레이커 상태 |
| GET | `/api/cache/stats` | Redis Lua EVAL 캐시 히트/미스 |

---

## DB 스키마

```sql
-- system_logs (Go · polyglot_db)
CREATE TABLE system_logs (
    id SERIAL PRIMARY KEY, source TEXT, message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- risk_logs (Rust · postgres :5433)
CREATE TABLE risk_logs (
    id SERIAL PRIMARY KEY, user_id INT, risk_score FLOAT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- risk_reports (Kotlin · postgres :5433)
CREATE TABLE risk_reports (
    id SERIAL PRIMARY KEY, generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    avg_risk_score FLOAT, total_records INT, max_risk_score FLOAT, min_risk_score FLOAT
);
```

---

## 변경 이력

| 날짜 | 내용 |
|:---|:---|
| 2026-04-08 | SSE 헬스 스트림 · WASM Theta/Vega/Rho Greeks · Python 멀티스테이지 Dockerfile · Rust SQLX_OFFLINE · GitHub Actions CI |
| 2026-04-07 | Docker Compose 28 서비스 · Go 워크플로 오케스트레이션 · 서킷 브레이커 · R GARCH/ARIMA · Nim AR(p) · OCaml 멀티에셋 VaR · WASM MC/포트폴리오 · Elixir Redis Pub/Sub · Svelte 탭/알림/차트/의존성맵 패널 |
| 2026-04-06 | SWI-Prolog 추가 (28번째) · Lua 코루틴 · Swift Actor · Clojure STM · Java Loom · Erlang 핫스왑 · V Zero-GC · Ruby DSL · Gleam ADT · Scala 3 · Nim · Crystal · OCaml · Dart · Haskell · R · F# · WebAssembly |
| 2026-03-18 | Rust 파이프라인 · Docker PostgreSQL 연동 |
| 2026-02-14 | 프로젝트 초기화 (SvelteKit · Go · Python · Rust · C++) |
