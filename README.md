# 🌈 Polyglot Infinity

A **real-time multi-currency micro-loan risk analysis platform** built with 28 languages/runtimes and 2 databases (PostgreSQL · Redis), featuring 2 independent frontend micro-apps (Svelte 5 dashboard · Elm order terminal).

---

## Service Map

| # | Language | Port | Key Feature |
|:-:|:---|:---:|:---|
| 1 | **Svelte 5** (SvelteKit + Bun) | 5173 | Real-time dashboard UI |
| 28 | **Elm 0.19.1** (TEA) | 5174 | Order entry terminal · live Greeks (F#) · VaR (Rust) · no runtime exceptions |
| 2 | **Go** `net/http` | 8080 | API Hub · Reverse proxy gateway (27 backends) · Redis caching · SSE stream · Circuit breaker |
| 3 | **Python** FastAPI | 8000 | FX rate collection · C++/Zig FFI · Julia HTTP |
| 4 | **Rust** Axum + sqlx | 8081 | High-performance bulk insert pipeline |
| 5 | **C++** | 8012 | `libcore.so` — Python FFI compute acceleration · HTTP artifact server |
| 6 | **Zig 0.13** | 8013 | `libzigcore.so` — Volatility estimation · VaR (C ABI) · HTTP artifact server |
| 7 | **WebAssembly** (Zig → WASM32) | 8014 | Black-Scholes Greeks · VaR · DCF · MC — nginx static server, browser-side execution |
| 8 | **Lua 5.4** | — / 8007 | Redis EVAL atomic cache counter · coroutine 6-feed scheduler |
| 9 | **Kotlin 2.0** | 9000 | Coroutine 60s risk report scheduler |
| 10 | **Elixir/Phoenix** | 4000 / 4001 | OTP Supervisor · GenServer · Phoenix Channel (port 4000) · Cowboy WebSocket raw server (port 4001) · Registry broadcast · Redis Pub/Sub → multi-client fan-out |
| 11 | **Julia 1.10** | 8002 | `Threads.@threads` GBM Monte Carlo · VaR/CVaR |
| 12 | **R 4.1** | 8003 | MLE distribution fitting · GARCH · ARIMA · Sharpe |
| 13 | **F# (.NET 8)** | 9001 | Black-Scholes Greeks · Implied Volatility · DCF |
| 14 | **OCaml 4.13** | 8004 | Rule-based risk judgment · logistic credit scoring · pattern-match loan approval · margin call escalation |
| 15 | **Crystal 1.19** | 9002 | `spawn`/`Channel` fibers — parallel FX collection from 4 sources (~1.8x) |
| 16 | **Nim 2.2.8** | 8005 | `static:` compile-time EMA/RSI tables · zero runtime divisions |
| 17 | **Scala 3** | 9003 | `enum` ADT + `LazyList.unfold` infinite stream + `given` typeclass |
| 18 | **Haskell GHC** | 8006 | Servant HTTP API · `/price` Black-Scholes Greeks (pure functional) · GBM Monte Carlo · lazy infinite stream |
| 19 | **Ruby 3.0** | 9004 | `instance_eval` runtime DSL — dynamic rule loading without restart |
| 20 | **Dart 3.11** | 9005 | Bond pricing · Duration · Nelson-Siegel yield curve |
| 21 | **Gleam 1.15** | 4001 | `wisp` + `mist` HTTP server · `ServiceMessage` ADT · exhaustive pattern match enforced at compile time |
| 22 | **V 0.5.1** | 4002 | `--gc none` Zero-GC MA crossover strategy backtester |
| 23 | **Erlang/OTP 24** | 4003 | `code:load_file/1` hot code swap · 0ms downtime |
| 24 | **Swift 6.1** | 8008 | `actor` — compile-time data race prevention |
| 25 | **Clojure 1.10** | 8009 | `ref`+`dosync` STM — lock-free atomic transfers |
| 26 | **Java 21** Project Loom | 8010 | `Executors.newVirtualThreadPerTaskExecutor()` · Order/Payment state machine (`ORDERED→PAID→PROCESSING→SHIPPED→DELIVERED`, `CANCELED→REFUNDED`) · `ReentrantLock` prevents Virtual Thread pinning · Async event queue (16 virtual thread workers) · **HikariCP JDBC persistence** (PostgreSQL `INSERT ON CONFLICT DO NOTHING` + `UPDATE`, `autoCommit=true`, pool 20) · `DbStore` inner class — `initSchema` / `insertOrder` / `updateOrder` via pure JDBC · DB write inside Virtual Thread (blocking JDBC acceptable; OS thread yielded) · **Redis Pub/Sub** (`order-events` channel via Jedis 5 JedisPool) · Virtual vs Platform Thread benchmark |
| 27 | **SWI-Prolog 8.4** | 8011 | Declarative constraint rules → backtracking portfolio search |
| — | **PostgreSQL** | 5432 | System logs · risk data (shared) |
| — | **PostgreSQL** (`db-postgres`) | 5432 | `loom-java` order persistence (isolated) |
| — | **Redis** | 6379 | Analytics result caching (Lua EVAL atomic ops) |

---

## Architecture

```
[Svelte 5 :5173]
      │ fetch / SSE
      ▼
[Go Hub :8080] ── Redis :6379 (Lua EVAL cache)
      │
      ├─ [Python :8000] ── C++ cpp-core :8012 (libcore.so)
      │                 ── Zig  zig-core :8013 (libzigcore.so)
      │                 ── Julia :8002
      │
      ├─ [Rust :8081] ── PostgreSQL :5433
      │
      └─ Workflow orchestration (Python→Rust→Kotlin pipeline)
           └─ Circuit breaker (closed/open/half-open)

Standalone services: Kotlin · Elixir · R · F# · OCaml · Crystal · Nim · Scala · Haskell
                     Ruby · Dart · Gleam · V · Erlang · Lua · Swift · Clojure · Java · Prolog

[Wasm-Zig :8014] — nginx serves finance.wasm; browser fetches and instantiates (no server round-trip)

[Elm Terminal :5174] — pure TEA micro-frontend; consumes go-hub :8080, fsharp-pricer :9001, rust-pipeline :8081;
  compiled to elm.js (no runtime), served by nginx; no Node.js in the final image

All 30 containers share the "polyglot" bridge network.
Inter-service DNS: http://<service-name>:<port>/ (e.g. http://risk-ocaml:8004)

Reverse proxy routes registered on Go Hub (:8080):
  Canonical (language prefix)     Role alias (service name)
  /api/python/   -> :8000         /api/risk/       -> ocaml-risk  :8004
  /api/rust/     -> :8081         /api/pricer/     -> fsharp-pricer:9001
  /api/julia/    -> :8002         /api/analytics/  -> nim-analytics:8005
  /api/r/        -> :8003         /api/ledger/     -> clojure-stm :8009
  /api/fsharp/   -> :9001         /api/scheduler/  -> kotlin-sched:9000
  /api/ocaml/    -> :8004
  /api/crystal/  -> :9002
  /api/nim/      -> :8005
  /api/scala/    -> :9003
  /api/haskell/  -> :8006
  /api/ruby/     -> :9004
  /api/dart/     -> :9005
  /api/gleam/    -> :4001
  /api/v/        -> :4002
  /api/erlang/   -> :4003
  /api/elixir/   -> :4000
  /api/clojure/  -> :8009
  /api/java/     -> :8010
  /api/prolog/   -> :8011
  /api/lua/      -> :8007
  /api/swift/    -> :8008
  /api/kotlin/   -> :9000
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
| ANY | `/api/<lang>/*` | **Reverse proxy** — 22 canonical language routes forwarded to backend container |
| ANY | `/api/risk/*` | Role alias → `ocaml-risk:8004` |
| ANY | `/api/pricer/*` | Role alias → `fsharp-pricer:9001` |
| ANY | `/api/analytics/*` | Role alias → `nim-analytics:8005` |
| ANY | `/api/ledger/*` | Role alias → `clojure-stm:8009` |
| ANY | `/api/scheduler/*` | Role alias → `kotlin-scheduler:9000` |
| POST | `/api/java/order?id=<id>` | Create order (status: ORDERED) |
| PUT | `/api/java/order?id=<id>&event=<evt>` | Order state transition — `PAY`, `PROCESS`, `SHIP`, `DELIVER`, `CANCEL`, `REFUND` (via async event queue) |
| GET | `/api/java/order?id=<id>` | Get order by ID (includes state history) |
| GET | `/api/java/orders` | Get all orders |
| GET | `/api/java/benchmark?n=<N>&mode=virtual\|platform\|both` | Virtual Thread vs Platform Thread throughput benchmark |

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

-- orders (Java Loom · db-postgres :5432/loom_db, auto-created on startup via initSchema())
CREATE TABLE IF NOT EXISTS orders (
    id         VARCHAR(255) PRIMARY KEY,
    status     VARCHAR(32)  NOT NULL,
    created_at BIGINT       NOT NULL,
    updated_at BIGINT       NOT NULL
);
```

---

## CI/CD

### GitHub Actions — `.github/workflows/main.yml`

Triggered on every push to the `main` branch. The pipeline consists of two jobs.

**Job 1: `build-verify`** (required)

| Step | Action |
|:---|:---|
| Disk cleanup | Removes `/usr/share/dotnet`, Android SDK, GHC, CodeQL to reclaim several GB on the runner |
| `docker compose config` | Validates YAML schema before any image pull |
| BuildKit layer cache | `actions/cache@v4` persists `/tmp/.buildx-cache` across runs |
| `docker compose build --parallel` | Parallel build of the 6 Dockerfile-based services: `go-hub`, `python-brain`, `rust-pipeline`, `cpp-core`, `zig-core`, `terminal-elm` |
| `docker compose pull --ignore-buildable` | Pulls registry images for the remaining 22 application + 2 infrastructure services |
| `docker compose up --no-start` | Creates all containers without starting them; fails immediately if any image cannot be resolved |
| Container count check | Counts lines from `docker compose ps -a --quiet`; exits with code 1 if count is below 28 |

**Job 2: `load-test`** (optional, `needs: build-verify`)

Starts only the three core backends (postgres, redis, go-hub, python-brain, rust-pipeline) to stay within runner memory limits.

| Step | Action |
|:---|:---|
| Health wait loop | `pg_isready`, `redis-cli ping`, and `curl /health` loops with `timeout 120` each |
| k6 installation | Official Grafana APT repository |
| Smoke test script | 10 VUs for 30 seconds, round-robin across`:8080/health`, `:8000/health`, `:8081/health` |
| Background execution | `k6 run ... &` — container logs streamed in parallel; `wait $K6_PID` collects exit code |
| Thresholds | `http_req_failed < 5%`, `p(95) < 2000 ms` |
| Artifact upload | `k6-results-run-N.json` uploaded via `actions/upload-artifact@v4` (`if: always()`) |

---

## Changelog

### 2026-04-08 (latest)

**Java Loom — dedicated PostgreSQL instance** (`loom-java` / `docker-compose.yml`)

- `docker-compose.yml` — Added `db-postgres` service (`postgres:16-alpine`, DB `loom_db`) isolated from the shared `postgres` instance (`polyglot_db`); prevents order-workload I/O from impacting other services
  - Healthcheck: `pg_isready -U dev -d loom_db` (interval 5s, retries 10)
  - Named volume: `db_postgres_data` — separate persistence from `postgres_data`
  - Network: `polyglot` bridge (same as all other containers)
- `java-loom` service — `DB_URL` updated to `jdbc:postgresql://db-postgres:5432/loom_db`; `depends_on` updated from `postgres` to `db-postgres: { condition: service_healthy }`

---

### 2026-04-08

**GitHub Actions CI/CD pipeline** (`.github/workflows/main.yml`)

- Trigger: push to `main` branch
- Job `build-verify`: validates compose config, builds 6 Dockerfile services in parallel, pulls 22 remaining images, instantiates all containers (`--no-start`), and asserts container count >= 28
- Job `load-test` (optional, `needs: build-verify`): starts core 3 backends, runs k6 smoke test (10 VU / 30 s, thresholds `http_req_failed < 5%` and `p(95) < 2000 ms`), uploads raw JSON results as a workflow artifact

**Java Loom — HikariCP JDBC persistence** (`loom-java`)

- `VirtualServer.java` — Added `DbStore` inner class (pure JDBC, no ORM)
  - `HikariDataSource` pool: `maximumPoolSize=20`, `minimumIdle=2`, `connectionTimeout=3s`, `autoCommit=true`
  - `initSchema()`: `CREATE TABLE IF NOT EXISTS orders (id VARCHAR(255) PRIMARY KEY, status VARCHAR(32) NOT NULL, created_at BIGINT NOT NULL, updated_at BIGINT NOT NULL)` — called once at startup
  - `insertOrder(id, status, createdAt)`: `INSERT ... ON CONFLICT (id) DO NOTHING` — idempotent, called in `POST /api/java/order` handler inside Virtual Thread
  - `updateOrder(id, status, updatedAt)`: `UPDATE orders SET status, updated_at WHERE id` — called in event worker after every successful state transition inside Virtual Thread
  - Blocking JDBC is used directly inside Virtual Thread; JVM scheduler yields the carrier OS thread during socket I/O wait, so throughput is not degraded
  - DB unavailability (no `DB_URL` env var, or connection failure) causes graceful fallback to in-memory-only mode; state management continues normally
  - `isRunning()` / `close()` guarded by null check on every call path
- `main()` — initialized `DbStore` from env vars `DB_URL` / `DB_USER` / `DB_PASSWORD` before JedisPool init; JVM shutdown hook calls `dbStore.close()`
- `GET /api/java/status` — added `db_connected` (bool) and `db_url` (string) fields
- `docker-compose.yml` — `java-loom`: added `DB_URL`, `DB_USER`, `DB_PASSWORD`, `REDIS_HOST`, `REDIS_PORT` env vars; added `depends_on: postgres (service_healthy), redis (service_healthy)`; volume changed from `:ro` to writable (run.sh writes `.classpath`)

**Elm Order Terminal — micro-frontend** (`terminal-elm`)

- Selected Elm 0.19.1 over HTMX and ClojureScript as the additive micro-frontend paradigm
  - HTMX rejected: all 26 backends emit JSON; HTMX value requires HTML-fragment servers
  - ClojureScript rejected: Lisp paradigm already represented by `ledger-clojure` (:8009)
  - Elm chosen: TEA (unidirectional state machine + managed effects) is absent from the polyglot stack; compiler-enforced exhaustive pattern matching eliminates runtime exceptions at the type level
- `terminal-elm/elm.json` — Elm 0.19.1 package manifest; direct deps: `elm/browser`, `elm/core`, `elm/html`, `elm/http`, `elm/json`, `elm/time`
- `terminal-elm/src/Main.elm` — full TEA implementation
  - `RemoteData e a` custom type (`NotAsked | Loading | Failure | Success`) used for every remote call; all branches handled exhaustively or the build fails
  - `Model`: order form state, risk snapshot, Greeks, submission status, live UTC clock
  - `Msg`: 10 variants covering form input, order type selection, submit, HTTP responses, 1s tick
  - `update`: pure function; no in-place mutation
  - HTTP: `fetchRisk` → `rust-pipeline :8081/api/risk`; `fetchGreeks` → `fsharp-pricer :9001/api/fsharp/iv`; `submitOrder` → `go-hub :8080/api/orders`
  - `subscriptions`: `Time.every 1000 Tick` drives live UTC clock in header
  - `view`: renders order form, risk metrics, Greeks panel, paradigm guarantees card
- `terminal-elm/index.html` — static shell; dark monospace CSS (CSS custom properties, no external dep); `Elm.Main.init` entry point
- `terminal-elm/build.sh` — `elm make src/Main.elm --output=elm.js --optimize`
- `docker-compose.yml` — `terminal-elm` service added (port `5174:80`); multi-stage build: `node:22-alpine` compiles Elm, `nginx:1.27-alpine` serves static assets; no Node.js or JVM in runtime image


**Svelte Portal — Health-check Dashboard Grid** (`portal-svelte`)

- `src/routes/+page.svelte` — Full rewrite as a self-contained 26-service health dashboard
  - `SERVICES` static registry (26 entries: key, name, aggregateName, lang, port, role)
  - `statuses` — `$state` record keyed by service key; each holds `{ status, latencyMs, result }`
  - `onlineCount` — `$derived` count of `"online"` entries, displayed live in the header
  - `fetchStatus()` — resets all cards to `"loading"`, then fires three parallel tracks via `Promise.allSettled`:
    - `fetchAggregate()` → `GET /api/aggregate` — maps 22 gateway-managed language services by name
    - `fetchGoHub()` → `GET /api/status` — confirms gateway liveness; surfaces `db: connected` in result field
    - `fetchArtifactServer(key, port)` × 3 — `HEAD /` for C++ (:8012), Zig (:8013), Wasm (:8014) artifact containers
  - `onMount` triggers `fetchStatus()` on page load; manual Refresh button triggers re-fetch
  - Responsive `auto-fill` CSS grid (`minmax(210px, 1fr)`) — no external CSS library
  - Dark-theme header: service counter badge, error banner, Refresh button (disabled while loading)
  - Removed all old panel component imports and tab/SSE/notification logic

- `src/lib/components/ServiceCard.svelte` — Rewritten to match new prop contract
  - Props: `name`, `lang`, `port`, `status`, `latencyMs`, `result`, `role`
  - Card border / opacity driven by `.card-online` / `.card-offline` / `.card-loading` class variants
  - Status dot: green pulse when online, amber blink when loading, red when offline
  - Result line: monospace, single-line, ellipsis overflow; shows `"checking…"` / `"—"` placeholders
  - Single scoped `<style>` block (dark theme, no external dependencies)

**Rust Pipeline Docker build fix** (`pipeline-rust`)
- `pipeline-rust/Dockerfile` — Added `g++` to builder `apk` installs; switched all `COPY` paths to repo-root-relative (`pipeline-rust/...`, `core-cpp/src`) so `build.rs` can compile `matrix.cpp` into `libcppmatrix.a` during the image build
- `docker-compose.yml` — Changed `rust-pipeline` build context from `./pipeline-rust` to `.` (repo root) with `dockerfile: pipeline-rust/Dockerfile`
- `.github/workflows/ci.yml` — Same `context: .` + `file: pipeline-rust/Dockerfile` fix for the `Build Rust Pipeline` step

**Elixir WebSocket Extension** (`hub-elixir`)
- `lib/hub_elixir/websocket/registry.ex` — Tracks all Cowboy WS handler processes using Elixir's built-in `Registry` in `:duplicate` mode; auto-cleaned on process exit
- `lib/hub_elixir/websocket/handler.ex` — Cowboy 2.14 `:cowboy_websocket` behavior; independent BEAM process per client (`init` → `websocket_init` → `websocket_handle` → `websocket_info` → `terminate`); pushes latest snapshot on connect; handles bidirectional `ping`/`pong` JSON frames
- `lib/hub_elixir/websocket/broadcaster.ex` — JSON-encodes and fans out to all clients via `Registry.dispatch`
- `lib/hub_elixir/redis_subscriber.ex` — Subscribes to `polyglot:events` via dedicated `Redix.PubSub` connection; broadcasts received events to both Phoenix PubSub (port 4000) and `Broadcaster` (port 4001) simultaneously; exponential backoff reconnect (5s base → 30s max)
- `lib/hub_elixir/poller.ex` — 10s periodic snapshot broadcast propagated to both channels as well
- `lib/hub_elixir/application.ex` — Starts Cowboy WS listener (port 4001) via `:cowboy.start_clear/3` after Supervisor boot; `Registry` registered as first child
- `mix.exs` — Removed `optional: true` from `plug_cowboy`

**Rust × C++ FFI pipeline** (`core-cpp` / `pipeline-rust`)
- `core-cpp/src/matrix.cpp` — 4 new functions: `cholesky_decompose` (Cholesky-Banachiewicz O(n³/3), returns -1 on non-PD), `mat_vec_mul` (y=A·x zero-copy), `portfolio_variance` (v=wᵀΣw, internal tmp malloc/free), `mat_frobenius_norm` (‖A‖_F single-pass)
- `core-cpp/src/matrix.h` — C extern declarations for all 4
- `pipeline-rust/src/ffi.rs` — new `unsafe extern "C"` bindings + safe wrappers (`cholesky`, `mat_vec_multiply`, `portfolio_var`, `frobenius_norm`) + `#![allow(dead_code)]`
- `pipeline-rust/Cargo.toml` — `[build-dependencies] cc = "1"`
- `pipeline-rust/src/main.rs` — 5 new Axum handlers (`POST /api/matrix/multiply`, `/api/matrix/covariance`, `/api/matrix/cholesky`, `/api/matrix/frobenius`, `/api/portfolio/variance`) all offloaded via `spawn_blocking`

**Haskell** (`pricer-haskell`)
- `server.hs` full rewrite — raw socket → Servant + Warp HTTP framework
- `DataKinds`/`TypeOperators` type-level API definition
- `/price` — Black-Scholes call/put/delta/gamma/vega/theta pure functions
- `/montecarlo` — GBM MC (LCG + Box-Muller)
- `/stream` — infinite lazy GBM stream (`iterate`/`scanl`/`zipWith`)
- `BSResult`/`MCResult`/`StreamResult` Generic-based ToJSON
- `pricer-haskell.cabal` — aeson/servant-server/warp dependencies

**OCaml** (`risk-ocaml`)
- `server.ml` — `applicant` record type · `loan_decision` ADT (Approved, ConditionalApproval of string, Rejected of string) · `margin_status` ADT (Safe, MarginWarning, MarginCall, ForcedLiquidation)
- `evaluate_loan` — pattern matching + when guard 6-stage assessment
- `evaluate_margin` — pattern matching Basel III 4-stage escalation
- `/api/ocaml/loan` · `/api/ocaml/margincall` HTTP endpoints added
- `dune`/`dune-project` — Dune 3.0 build config added

**Java 21 Loom** (`loom-java`)
- `VirtualServer.java` — Added `DbStore` inner class: HikariCP 5.1 connection pool init (`maximumPoolSize=20`, `connectionTimeout=3s`, `autoCommit=true`); supports env vars `DB_URL` / `DB_USER` / `DB_PASSWORD` (default: PostgreSQL `localhost:5432/orders`)
- PostgreSQL: `INSERT INTO orders ... ON CONFLICT (id) DO UPDATE SET status, updated_at` (single statement, row-level lock)
- Oracle: `MERGE INTO orders USING DUAL` (single statement, row-level lock); auto table creation ignoring `ORA-00955`
- DB writes performed as a snapshot after releasing `ReentrantLock` — minimizes lock hold time
- On DB unavailability, server falls back to in-memory-only mode and continues normal operation
- `GET /api/java/status` — Added `db_connected`, `db_url`, `redis_connected` fields
- `build.sh` — Downloads `HikariCP-5.1.0.jar`, `slf4j-api-2.0.12.jar`, `slf4j-nop-2.0.12.jar`, `postgresql-42.7.3.jar` from Maven Central; generates `.classpath` file after compilation
- `run.sh` — Reads `.classpath` file to construct runtime classpath

**Go reverse proxy** (`server-go`)
- `main.go` — 22 canonical language routes + 5 role aliases (27 total) registered as `httputil.ReverseProxy`
- `resolveBackend` env-override + localhost fallback
- `withCORS` preflight handling
- Shared `proxyTransport` (30s header timeout)

**Gleam** (`hub_gleam`)
- Replaced gen_tcp-based Erlang server with pure Gleam HTTP server using `wisp` 2.2.2 + `mist` 6.0.2
- `/health` "Gleam Hub OK" · `handle_request` wisp router
- `gleam.toml` dependencies added

**docker-compose**
- Added cpp-core(:8012) · zig-core(:8013) · wasm-zig(:8014) containers
- Unified all services on polyglot bridge network
- nginx WASM MIME config · SSE health stream · WASM Theta/Vega/Rho Greeks
- Python multi-stage Dockerfile · Rust SQLX_OFFLINE · GitHub Actions CI
- Rust base image 1.78→1.88 (edition2024/MSRV)
- Added openssl-libs-static (fix musl static link) · portal-svelte package-lock.json (fix npm ci)

**Misc**
- `.gitignore` — added `tree.txt` · `server-go/server` (Go compiled binary)

---

### 2026-04-07
Docker Compose 28 services · Go workflow orchestration · circuit breaker · R GARCH/ARIMA · Nim AR(p) · OCaml multi-asset VaR · WASM MC/portfolio · Elixir Redis Pub/Sub · Svelte tabs/notifications/charts/dependency-map panels

### 2026-04-06
SWI-Prolog added (28th) · Lua coroutines · Swift Actor · Clojure STM · Java Loom · Erlang hot-swap · V Zero-GC · Ruby DSL · Gleam ADT · Scala 3 · Nim · Crystal · OCaml · Dart · Haskell · R · F# · WebAssembly

### 2026-03-18
Rust pipeline · Docker PostgreSQL integration

### 2026-02-14
Project init (SvelteKit · Go · Python · Rust · C++)
