# 🌈 Polyglot Infinity

A **real-time multi-currency micro-loan risk analysis platform** built with 28 languages/runtimes and 2 databases (PostgreSQL · Redis).

---

## Service Map

| # | Language | Port | Key Feature |
|:-:|:---|:---:|:---|
| 1 | **Svelte 5** (SvelteKit + Bun) | 5173 | Real-time dashboard UI |
| 2 | **Go** `net/http` | 8080 | API Hub · Redis caching · SSE stream · Circuit breaker |
| 3 | **Python** FastAPI | 8000 | FX rate collection · C++/Zig FFI · Julia HTTP |
| 4 | **Rust** Axum + sqlx | 8081 | High-performance bulk insert pipeline |
| 5 | **C++** | — | `libcore.so` — Python FFI compute acceleration |
| 6 | **Zig 0.13** | — | `libzigcore.so` — Volatility estimation · VaR (C ABI) |
| 7 | **WebAssembly** (Zig → WASM32) | Browser | Black-Scholes Greeks · VaR · DCF · MC — runs in browser, no server round-trip |
| 8 | **Lua 5.4** | — / 8007 | Redis EVAL atomic cache counter · coroutine 6-feed scheduler |
| 9 | **Kotlin 2.0** | 9000 | Coroutine 60s risk report scheduler |
| 10 | **Elixir/Phoenix** | 4000 | OTP Supervisor · GenServer · WebSocket Channel |
| 11 | **Julia 1.10** | 8002 | `Threads.@threads` GBM Monte Carlo · VaR/CVaR |
| 12 | **R 4.1** | 8003 | MLE distribution fitting · GARCH · ARIMA · Sharpe |
| 13 | **F# (.NET 8)** | 9001 | Black-Scholes Greeks · Implied Volatility · DCF |
| 14 | **OCaml 4.13** | 8004 | Rule-based risk judgment · logistic credit scoring |
| 15 | **Crystal 1.19** | 9002 | `spawn`/`Channel` fibers — parallel FX collection from 4 sources (~1.8x) |
| 16 | **Nim 2.2.8** | 8005 | `static:` compile-time EMA/RSI tables · zero runtime divisions |
| 17 | **Scala 3** | 9003 | `enum` ADT + `LazyList.unfold` infinite stream + `given` typeclass |
| 18 | **Haskell GHC** | 8006 | Pure functional Black-Scholes Greeks · GBM Monte Carlo |
| 19 | **Ruby 3.0** | 9004 | `instance_eval` runtime DSL — dynamic rule loading without restart |
| 20 | **Dart 3.11** | 9005 | Bond pricing · Duration · Nelson-Siegel yield curve |
| 21 | **Gleam 1.15** | 4001 | `ServiceMessage` ADT · exhaustive pattern match enforced at compile time |
| 22 | **V 0.5.1** | 4002 | `--gc none` Zero-GC MA crossover strategy backtester |
| 23 | **Erlang/OTP 24** | 4003 | `code:load_file/1` hot code swap · 0ms downtime |
| 24 | **Swift 6.1** | 8008 | `actor` — compile-time data race prevention |
| 25 | **Clojure 1.10** | 8009 | `ref`+`dosync` STM — lock-free atomic transfers |
| 26 | **Java 21** Project Loom | 8010 | `Thread.ofVirtual()` 50k virtual threads (~6x vs platform threads) |
| 27 | **SWI-Prolog 8.4** | 8011 | Declarative constraint rules → backtracking portfolio search |
| — | **PostgreSQL** | 5432/5433 | System logs · risk data |
| — | **Redis** | 6379 | Analytics result caching (Lua EVAL atomic ops) |

---

## Architecture

```
[Svelte 5 :5173]
      │ fetch / SSE
      ▼
[Go Hub :8080] ── Redis :6379 (Lua EVAL cache)
      │
      ├─ [Python :8000] ── C++ libcore.so
      │                 ── Zig libzigcore.so
      │                 ── Julia :8002
      │
      ├─ [Rust :8081] ── PostgreSQL :5433
      │
      └─ Workflow orchestration (Python→Rust→Kotlin pipeline)
           └─ Circuit breaker (closed/open/half-open)

Standalone services: Kotlin · Elixir · R · F# · OCaml · Crystal · Nim · Scala · Haskell
                     Ruby · Dart · Gleam · V · Erlang · Lua · Swift · Clojure · Java · Prolog

[WebAssembly] — runs directly in browser (no server round-trip)
```

---

## Key APIs (Go Hub :8080)

| Method | Endpoint | Description |
|:---|:---|:---|
| GET | `/api/status` | Overall system status |
| GET | `/api/aggregate` | Parallel health check aggregation across 28 backends |
| GET | `/api/aggregate/stream` | **SSE** — real-time service status stream |
| GET | `/api/report` | Consolidated risk report (includes DB stats) |
| GET | `/api/workflow/risk-full` | Python→Rust→Kotlin end-to-end pipeline |
| GET | `/api/workflow/option-compare` | F# · Haskell · Python 3-engine BS price comparison |
| GET | `/api/circuit/status` | Circuit breaker status |
| GET | `/api/cache/stats` | Redis Lua EVAL cache hit/miss stats |

---

## DB Schema

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

## Changelog

| Date | Changes |
|:---|:---|
| 2026-04-08 | SSE health stream · WASM Theta/Vega/Rho Greeks · Python multi-stage Dockerfile · Rust SQLX_OFFLINE · GitHub Actions CI · Rust base image 1.78 → 1.88 (edition2024 / MSRV) · add openssl-libs-static (fix musl static link) · add portal-svelte package-lock.json (fix npm ci) |
| 2026-04-07 | Docker Compose 28 services · Go workflow orchestration · circuit breaker · R GARCH/ARIMA · Nim AR(p) · OCaml multi-asset VaR · WASM MC/portfolio · Elixir Redis Pub/Sub · Svelte tabs/notifications/charts/dependency-map panels |
| 2026-04-06 | SWI-Prolog added (28th) · Lua coroutines · Swift Actor · Clojure STM · Java Loom · Erlang hot-swap · V Zero-GC · Ruby DSL · Gleam ADT · Scala 3 · Nim · Crystal · OCaml · Dart · Haskell · R · F# · WebAssembly |
| 2026-03-18 | Rust pipeline · Docker PostgreSQL integration |
| 2026-02-14 | Project init (SvelteKit · Go · Python · Rust · C++) |
