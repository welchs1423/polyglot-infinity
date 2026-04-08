/**
 * k6 integration load test for the polyglot-infinity Go gateway.
 *
 * Target  : http://localhost:8080
 * Scale   : 500 VUs, 3 minutes
 * Thresholds:
 *   - http_req_duration p(95) < 200ms
 *   - http_req_failed   rate  < 0.01  (1%)
 *
 * Run:
 *   k6 run tests/load-test.js
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";
import { randomIntBetween } from "https://jslib.k6.io/k6-utils/1.4.0/index.js";

// ── Custom metrics ────────────────────────────────────────────────────────────
const errorRate = new Rate("custom_error_rate");
const orderLatency = new Trend("order_latency_ms", true);
const workflowLatency = new Trend("workflow_latency_ms", true);
const aggregateLatency = new Trend("aggregate_latency_ms", true);
const scenarioCounter = new Counter("scenario_hits");

// ── Test configuration ────────────────────────────────────────────────────────
export const options = {
    // Ramp-up → sustained 500 VUs → ramp-down
    stages: [
        { duration: "30s", target: 100 }, // ramp-up: 0 → 100
        { duration: "30s", target: 500 }, // ramp-up: 100 → 500
        { duration: "120s", target: 500 }, // sustained: 500 VUs for 2 min
        { duration: "20s", target: 0 }, // ramp-down: 500 → 0
    ],

    thresholds: {
        // 95th-percentile response time must stay under 200ms
        http_req_duration: ["p(95)<200"],
        // HTTP error rate (non-2xx/3xx) must stay below 1%
        http_req_failed: ["rate<0.01"],
        // Custom: aggregated error rate (includes app-level errors) < 1%
        custom_error_rate: ["rate<0.01"],
        // Order submission 95th percentile < 300ms (heavier write path)
        order_latency_ms: ["p(95)<300"],
        // Multi-step workflow 95th percentile < 2s (sequential fan-out)
        workflow_latency_ms: ["p(95)<2000"],
        // Cross-service aggregate 95th percentile < 500ms
        aggregate_latency_ms: ["p(95)<500"],
    },
};

// ── Base URL ──────────────────────────────────────────────────────────────────
const BASE = "http://localhost:8080";

// ── Common headers ────────────────────────────────────────────────────────────
const JSON_HEADERS = { "Content-Type": "application/json" };

// ── Scenario weight table ─────────────────────────────────────────────────────
// Each entry: [cumulative weight, scenario function reference]
// Total weight = 100. Higher weight → more traffic share.
// Distribution rationale:
//   - Status / aggregate are the most frequent dashboard calls (10% each).
//   - Order submission is the primary write path (10%).
//   - All 31 language backends covered to expose per-service bottlenecks.
//   - Heavyweight compute endpoints (workflow, V backtest) kept ≤ 2% share.
const SCENARIOS = [
    [10, scenarioStatus],           //  0- 9 : GET  /api/status              (10%)
    [20, scenarioAggregate],        // 10-19 : GET  /api/aggregate            (10%)
    [30, scenarioOrderSubmit],      // 20-29 : POST /api/java/order           (10%)
    [36, scenarioCacheStats],       // 30-35 : GET  /api/cache/stats           (6%)
    [41, scenarioHistory],          // 36-40 : GET  /api/history               (5%)
    [46, scenarioReport],           // 41-45 : GET  /api/report                (5%)
    [50, scenarioRustRisk],         // 46-49 : GET  /api/rust/status           (4%)
    [54, scenarioPythonAnalyze],    // 50-53 : GET  /api/python/analyze        (4%)
    [57, scenarioFSharpIV],         // 54-56 : GET  /api/fsharp/iv             (3%)
    [60, scenarioOCamlRisk],        // 57-59 : GET  /api/ocaml/risk            (3%)
    [62, scenarioNimGarch],         // 60-61 : GET  /api/nim/garch             (2%)
    [64, scenarioJuliaSimulate],    // 62-63 : GET  /api/julia/simulate        (2%)
    [66, scenarioHaskellMC],        // 64-65 : GET  /api/haskell/montecarlo    (2%)
    [68, scenarioKotlinReport],     // 66-67 : GET  /api/kotlin/reports/now    (2%)
    [70, scenarioElixirStatus],     // 68-69 : GET  /api/elixir/status         (2%)
    [72, scenarioClojureTransfer],  // 70-71 : POST /api/clojure/transfer      (2%)
    [73, scenarioLuaStream],        // 72    : GET  /api/lua/stream             (1%)
    [75, scenarioSwiftOrder],       // 73-74 : POST /api/swift/order           (2%)
    [76, scenarioErlangStatus],     // 75    : GET  /api/erlang/status          (1%)
    [77, scenarioPipelineTrigger],  // 76    : POST /api/pipeline/trigger       (1%)
    [79, scenarioWorkflowRisk],     // 77-78 : GET  /api/workflow/risk-full     (2%)
    [81, scenarioWorkflowOption],   // 79-80 : GET  /api/workflow/option-compare(2%)
    [83, scenarioRStats],           // 81-82 : GET  /api/r/fit                  (2%)
    [85, scenarioCrystalPortfolio], // 83-84 : GET  /api/crystal/portfolio      (2%)
    [87, scenarioScalaAggregate],   // 85-86 : GET  /api/scala/aggregate        (2%)
    [89, scenarioRubyScore],        // 87-88 : GET  /api/ruby/score             (2%)
    [91, scenarioDartBond],         // 89-90 : GET  /api/dart/bond              (2%)
    [93, scenarioGleamPipeline],    // 91-92 : GET  /api/gleam/pipeline         (2%)
    [95, scenarioVBacktest],        // 93-94 : GET  /api/v/backtest             (2%)
    [96, scenarioPrologPortfolio],  // 95    : GET  /api/prolog/portfolio        (1%)
    [100, scenarioCircuitStatus],    // 96-99 : GET  /api/circuit/status          (4%)
];

// ── Main VU loop ──────────────────────────────────────────────────────────────
export default function () {
    const roll = randomIntBetween(0, 99);

    for (const [ceiling, fn] of SCENARIOS) {
        if (roll < ceiling) {
            fn();
            scenarioCounter.add(1);
            break;
        }
    }

    // Think-time: 100–500ms uniform to avoid thundering-herd artefacts
    sleep(randomIntBetween(100, 500) / 1000);
}

// ── Scenario implementations ──────────────────────────────────────────────────

function scenarioStatus() {
    const res = http.get(`${BASE}/api/status`);
    check(res, {
        "status 200": (r) => r.status === 200,
        "has system field": (r) => r.status === 200 && r.json("system") !== undefined,
    });
    errorRate.add(res.status >= 400);
}

function scenarioAggregate() {
    const start = Date.now();
    const res = http.get(`${BASE}/api/aggregate`);
    aggregateLatency.add(Date.now() - start);
    check(res, {
        "aggregate 200": (r) => r.status === 200,
        "has services array": (r) => r.status === 200 && Array.isArray(r.json("services")),
    });
    errorRate.add(res.status >= 400);
}

// Primary write path: submit a virtual order through the Java Loom backend.
function scenarioOrderSubmit() {
    const orderTypes = ["MARKET", "LIMIT", "STOP"];
    const symbols = ["AAPL", "TSLA", "MSFT", "NVDA", "GOOG"];
    const sides = ["BUY", "SELL"];

    const payload = JSON.stringify({
        symbol: symbols[randomIntBetween(0, symbols.length - 1)],
        quantity: randomIntBetween(1, 1000),
        price: parseFloat((randomIntBetween(10000, 50000) / 100).toFixed(2)),
        order_type: orderTypes[randomIntBetween(0, orderTypes.length - 1)],
        side: sides[randomIntBetween(0, sides.length - 1)],
    });

    const start = Date.now();
    const res = http.post(`${BASE}/api/java/order`, payload, {
        headers: JSON_HEADERS,
    });
    orderLatency.add(Date.now() - start);

    check(res, {
        "order accepted": (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(res.status >= 400);
}

function scenarioCacheStats() {
    const res = http.get(`${BASE}/api/cache/stats`);
    check(res, {
        "cache stats 200": (r) => r.status === 200,
        "has cache_hits": (r) => r.status === 200 && r.json("cache_hits") !== undefined,
    });
    errorRate.add(res.status >= 400);
}

function scenarioHistory() {
    const res = http.get(`${BASE}/api/history`);
    check(res, {
        "history 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioReport() {
    const res = http.get(`${BASE}/api/report`, { timeout: "10s" });
    check(res, {
        "report 200": (r) => r.status === 200,
        "has generated_at": (r) => r.status === 200 && r.json("generated_at") !== undefined,
    });
    errorRate.add(res.status >= 400);
}

function scenarioRustRisk() {
    const res = http.get(`${BASE}/api/rust/status`);
    check(res, {
        "rust 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioPythonAnalyze() {
    const res = http.get(`${BASE}/api/python/analyze`);
    check(res, {
        "python 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioFSharpIV() {
    // Implied volatility: Black-Scholes Newton-Raphson solve
    const s = randomIntBetween(90, 110);
    const k = randomIntBetween(95, 115);
    const res = http.get(
        `${BASE}/api/fsharp/iv?s=${s}&k=${k}&r=0.05&t=0.25&market_price=5.0`
    );
    check(res, {
        "fsharp iv 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioOCamlRisk() {
    const res = http.get(`${BASE}/api/ocaml/risk`);
    check(res, {
        "ocaml risk 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioNimGarch() {
    const omega = (randomIntBetween(1, 10) / 1000000).toFixed(7);
    const alpha = (randomIntBetween(5, 20) / 100).toFixed(2);
    const beta = (randomIntBetween(75, 90) / 100).toFixed(2);
    const res = http.get(
        `${BASE}/api/nim/garch?omega=${omega}&alpha=${alpha}&beta=${beta}&n=252`
    );
    check(res, {
        "nim garch 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioJuliaSimulate() {
    const vol = (randomIntBetween(10, 40) / 100).toFixed(2);
    const paths = randomIntBetween(10, 100);
    const res = http.get(
        `${BASE}/api/julia/simulate?paths=${paths}&days=252&vol=${vol}&mu=0.07`
    );
    check(res, {
        "julia simulate 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioHaskellMC() {
    const s = randomIntBetween(80, 120);
    const n = randomIntBetween(100, 500);
    const res = http.get(
        `${BASE}/api/haskell/montecarlo?s=${s}&vol=0.2&mu=0.05&n=${n}&days=252`
    );
    check(res, {
        "haskell mc 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioKotlinReport() {
    const res = http.get(`${BASE}/api/kotlin/reports/now`);
    check(res, {
        "kotlin report 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

function scenarioElixirStatus() {
    const res = http.get(`${BASE}/api/elixir/status`);
    check(res, {
        "elixir status 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Clojure STM: atomic double-entry transfer between two accounts
function scenarioClojureTransfer() {
    const accounts = ["ACC-001", "ACC-002", "ACC-003", "ACC-004", "ACC-005"];
    const from = accounts[randomIntBetween(0, accounts.length - 1)];
    let to = from;
    while (to === from) {
        to = accounts[randomIntBetween(0, accounts.length - 1)];
    }

    const payload = JSON.stringify({
        from_account: from,
        to_account: to,
        amount: parseFloat((randomIntBetween(100, 10000) / 100).toFixed(2)),
    });

    const res = http.post(`${BASE}/api/clojure/transfer`, payload, {
        headers: JSON_HEADERS,
    });
    check(res, {
        "clojure transfer accepted": (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(res.status >= 400);
}

function scenarioLuaStream() {
    const res = http.get(`${BASE}/api/lua/stream`);
    check(res, {
        "lua stream 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Swift actor: concurrent-safe order submission
function scenarioSwiftOrder() {
    const payload = JSON.stringify({
        symbol: "BTC-USD",
        quantity: randomIntBetween(1, 10),
        price: parseFloat((randomIntBetween(2000000, 7000000) / 100).toFixed(2)),
        side: randomIntBetween(0, 1) === 0 ? "BUY" : "SELL",
    });

    const res = http.post(`${BASE}/api/swift/order`, payload, {
        headers: JSON_HEADERS,
    });
    check(res, {
        "swift order accepted": (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(res.status >= 400);
}

function scenarioErlangStatus() {
    const res = http.get(`${BASE}/api/erlang/status`);
    check(res, {
        "erlang status 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Rust pipeline bulk insert trigger (heavyweight write, low frequency)
function scenarioPipelineTrigger() {
    const res = http.post(`${BASE}/api/pipeline/trigger`, null, {
        headers: JSON_HEADERS,
        timeout: "10s",
    });
    check(res, {
        "pipeline trigger 2xx": (r) => r.status >= 200 && r.status < 300,
    });
    errorRate.add(res.status >= 400);
}

// Sequential 5-step workflow: Python → Rust × 2 → Kotlin → Nim
function scenarioWorkflowRisk() {
    const start = Date.now();
    const res = http.get(`${BASE}/api/workflow/risk-full`, { timeout: "15s" });
    workflowLatency.add(Date.now() - start);
    check(res, {
        "workflow risk 200": (r) => r.status === 200,
        "has steps": (r) => r.status === 200 && Array.isArray(r.json("steps")),
    });
    errorRate.add(res.status >= 400);
}

// Sequential option-compare workflow: F# BS vs Haskell BS
function scenarioWorkflowOption() {
    const s = randomIntBetween(90, 110);
    const k = randomIntBetween(95, 115);
    const start = Date.now();
    const res = http.get(
        `${BASE}/api/workflow/option-compare?s=${s}&k=${k}&r=0.05&t=0.25&vol=0.2`,
        { timeout: "15s" }
    );
    workflowLatency.add(Date.now() - start);
    check(res, {
        "workflow option 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// ── Missing-backend scenarios (R, Crystal, Scala, Ruby, Dart, Gleam, V, Prolog, circuit) ──

// R (plumber): normal MLE fit + VaR over synthetic return series
function scenarioRStats() {
    const n = randomIntBetween(100, 1000);
    const seed = randomIntBetween(1, 9999);
    const res = http.get(`${BASE}/api/r/fit?n=${n}&seed=${seed}`, { timeout: "15s" });
    check(res, {
        "r fit 200": (r) => r.status === 200,
        "has sharpe_ratio": (r) => r.status === 200 && r.json("sharpe_ratio") !== undefined,
    });
    errorRate.add(res.status >= 400);
}

// Crystal (fibers): simulated portfolio Sharpe + Sortino analysis
function scenarioCrystalPortfolio() {
    const mu = (randomIntBetween(5, 25) / 100).toFixed(2);
    const sigma = (randomIntBetween(10, 35) / 100).toFixed(2);
    const seed = randomIntBetween(1, 9999);
    const res = http.get(
        `${BASE}/api/crystal/portfolio?mu=${mu}&sigma=${sigma}&days=252&seed=${seed}`
    );
    check(res, {
        "crystal portfolio 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Scala 3 (ADT streams): time-series aggregate over simulated price events
function scenarioScalaAggregate() {
    const n = randomIntBetween(50, 500);
    const mu = (randomIntBetween(3, 15) / 100).toFixed(2);
    const sigma = (randomIntBetween(10, 30) / 100).toFixed(2);
    const res = http.get(
        `${BASE}/api/scala/aggregate?n=${n}&mu=${mu}&sigma=${sigma}&seed=${randomIntBetween(1, 9999)}`
    );
    check(res, {
        "scala aggregate 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Ruby (instance_eval DSL): credit scoring with dynamic risk rules
function scenarioRubyScore() {
    const dr = (randomIntBetween(10, 80) / 100).toFixed(2);
    const ltv = (randomIntBetween(30, 95) / 100).toFixed(2);
    const nd = randomIntBetween(0, 5);
    const inc = randomIntBetween(30, 500);
    const res = http.get(
        `${BASE}/api/ruby/score?debt_ratio=${dr}&ltv=${ltv}&num_defaults=${nd}&annual_income_k=${inc}`
    );
    check(res, {
        "ruby score 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Dart (isolates): fixed-income bond pricing (price + duration + convexity)
function scenarioDartBond() {
    const coupon = (randomIntBetween(2, 10) / 100).toFixed(3);
    const rate = (randomIntBetween(1, 12) / 100).toFixed(3);
    const n = randomIntBetween(3, 30);
    const face = randomIntBetween(100, 10000) * 10;
    const res = http.get(
        `${BASE}/api/dart/bond?coupon=${coupon}&face=${face}&rate=${rate}&n=${n}`
    );
    check(res, {
        "dart bond 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Gleam (BEAM typed): multi-service pipeline orchestration
function scenarioGleamPipeline() {
    const res = http.get(`${BASE}/api/gleam/pipeline`);
    check(res, {
        "gleam pipeline 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// V (low-memory): dual-SMA crossover backtest (kept small to avoid timeout)
function scenarioVBacktest() {
    const ticks = randomIntBetween(500, 5000);
    const fast = randomIntBetween(5, 20);
    const slow = randomIntBetween(30, 80);
    const seed = randomIntBetween(1, 9999);
    const res = http.get(
        `${BASE}/api/v/backtest?ticks=${ticks}&fast=${fast}&slow=${slow}&seed=${seed}`,
        { timeout: "15s" }
    );
    check(res, {
        "v backtest 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Prolog (constraint solving): portfolio allocation satisfying weight constraints
function scenarioPrologPortfolio() {
    const res = http.get(`${BASE}/api/prolog/portfolio`, { timeout: "10s" });
    check(res, {
        "prolog portfolio 200": (r) => r.status === 200,
    });
    errorRate.add(res.status >= 400);
}

// Go gateway: circuit breaker state snapshot for all downstream services
function scenarioCircuitStatus() {
    const res = http.get(`${BASE}/api/circuit/status`);
    check(res, {
        "circuit status 200": (r) => r.status === 200,
        "is object": (r) => r.status === 200 && typeof r.json() === "object",
    });
    errorRate.add(res.status >= 400);
}

// ── Summary hook ──────────────────────────────────────────────────────────────
// Printed by k6 after the test run. No code needed here; k6 renders the
// thresholds table and the custom metric histograms automatically in the
// end-of-test summary.
