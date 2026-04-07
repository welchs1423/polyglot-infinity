// ============================================================
// Gleam 1.15 Functional Pipeline Engine
// Port: 4001  (HTTP served by wisp + mist)
// Endpoints:
//   GET /health
//   GET /api/gleam/pipeline
//   GET /api/gleam/risk
//   GET /api/gleam/validate
//   GET /api/gleam/contract
// ============================================================

import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import mist
import wisp.{type Request, type Response}
import wisp/wisp_mist

// ---------- Math ----------

fn float_sqrt(x: Float) -> Float {
  float.square_root(x) |> result.unwrap(0.0)
}

fn float_pow_int(base: Float, n: Int) -> Float {
  case n {
    0 -> 1.0
    k -> base *. float_pow_int(base, k - 1)
  }
}

fn factorial(n: Int) -> Int {
  case n {
    0 -> 1
    1 -> 1
    _ -> n * factorial(n - 1)
  }
}

fn float_log(x: Float) -> Float {
  case x >. 0.0 {
    False -> -999.0
    True -> {
      let z = { x -. 1.0 } /. { x +. 1.0 }
      let terms = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
      let sum =
        list.fold(terms, 0.0, fn(acc, n) {
          acc +. float_pow_int(z, n) /. int.to_float(n)
        })
      2.0 *. sum
    }
  }
}

fn float_cos(x: Float) -> Float {
  let terms = [0, 2, 4, 6, 8, 10, 12]
  list.index_fold(terms, 0.0, fn(acc, n, i) {
    let sign = case i % 2 == 0 {
      True -> 1.0
      False -> -1.0
    }
    acc +. sign *. float_pow_int(x, n) /. int.to_float(factorial(n))
  })
}

// ---------- LCG pseudo-random + Box-Muller ----------

fn lcg_next(seed: Int) -> Int {
  { 1_664_525 * seed + 1_013_904_223 }
  |> int.modulo(2_147_483_648)
  |> result.unwrap(0)
}

fn lcg_seq_loop(seed: Int, remaining: Int, acc: List(Float)) -> List(Float) {
  case remaining {
    0 -> list.reverse(acc)
    _ -> {
      let next = lcg_next(seed)
      let val = int.to_float(next) /. 2_147_483_648.0
      lcg_seq_loop(next, remaining - 1, [val, ..acc])
    }
  }
}

fn box_muller_loop(us: List(Float), acc: List(Float)) -> List(Float) {
  case us {
    [u1, u2, ..rest] -> {
      let safe = case u1 <. 1.0e-10 { True -> 1.0e-10 False -> u1 }
      let r = float_sqrt(-2.0 *. float_log(safe))
      let z = r *. float_cos(2.0 *. 3.141592653589793 *. u2)
      box_muller_loop(rest, [z, ..acc])
    }
    _ -> list.reverse(acc)
  }
}

fn gbm_returns(n: Int, mu: Float, sigma: Float, seed: Int) -> List(Float) {
  let dt = 1.0 /. 252.0
  let drift = { mu -. 0.5 *. sigma *. sigma } *. dt
  let diffusion = sigma *. float_sqrt(dt)
  let randoms =
    lcg_seq_loop(seed, n * 2, [])
    |> box_muller_loop([])
    |> list.take(n)
  list.map(randoms, fn(z) { drift +. diffusion *. z })
}

// ---------- Statistics ----------

fn list_mean(xs: List(Float)) -> Float {
  case xs {
    [] -> 0.0
    _ ->
      list.fold(xs, 0.0, fn(a, x) { a +. x }) /. int.to_float(list.length(xs))
  }
}

fn list_std(xs: List(Float)) -> Float {
  let m = list_mean(xs)
  let v =
    list.fold(xs, 0.0, fn(a, x) { a +. { x -. m } *. { x -. m } })
    /. int.to_float(list.length(xs))
  float_sqrt(v)
}

fn list_min(xs: List(Float)) -> Float {
  case xs {
    [] -> 0.0
    [h, ..t] -> list.fold(t, h, fn(m, x) { case x <. m { True -> x False -> m } })
  }
}

fn list_max(xs: List(Float)) -> Float {
  case xs {
    [] -> 0.0
    [h, ..t] -> list.fold(t, h, fn(m, x) { case x >. m { True -> x False -> m } })
  }
}

fn percentile_p(xs: List(Float), p: Float) -> Float {
  case xs {
    [] -> 0.0
    _ -> {
      let sorted = list.sort(xs, float.compare)
      let n = list.length(sorted)
      let raw_idx = float.round(p /. 100.0 *. int.to_float(n))
      let idx = case raw_idx < 0 { True -> 0 False -> case raw_idx >= n { True -> n - 1 False -> raw_idx } }
      sorted |> list.drop(idx) |> list.first |> result.unwrap(0.0)
    }
  }
}

fn sharpe(returns: List(Float)) -> Float {
  let ann_ret = list_mean(returns) *. 252.0
  let ann_vol = list_std(returns) *. float_sqrt(252.0)
  case ann_vol == 0.0 { True -> 0.0 False -> ann_ret /. ann_vol }
}

fn max_drawdown(xs: List(Float)) -> Float {
  let #(_, mdd) =
    list.fold(xs, #(0.0, 0.0), fn(s, cr) {
      let #(pk, md) = s
      let new_pk = case cr >. pk { True -> cr False -> pk }
      let dd = new_pk -. cr
      #(new_pk, case dd >. md { True -> dd False -> md })
    })
  mdd
}

fn cumsum(xs: List(Float)) -> List(Float) {
  list.scan(xs, 0.0, fn(acc, x) { acc +. x })
}

// ---------- JSON helpers ----------

fn fmt_f(x: Float) -> String {
  let r = float.round(x *. 1_000_000.0)
  let ip = r / 1_000_000
  let fp = int.absolute_value(r % 1_000_000)
  int.to_string(ip) <> "." <> string.pad_start(int.to_string(fp), 6, "0")
}

// ---------- Pipeline step helpers ----------

fn pipeline_step_json(
  name: String,
  xs: List(Float),
) -> String {
  "{"
  <> "\"name\":\"" <> name <> "\","
  <> "\"count\":" <> int.to_string(list.length(xs)) <> ","
  <> "\"mean\":" <> fmt_f(list_mean(xs)) <> ","
  <> "\"std\":" <> fmt_f(list_std(xs)) <> ","
  <> "\"min\":" <> fmt_f(list_min(xs)) <> ","
  <> "\"max\":" <> fmt_f(list_max(xs))
  <> "}"
}

// ---------- Public API (called from Erlang) ----------

pub fn pipeline_json(n: Int, mu: Float, sigma: Float) -> String {
  let returns = gbm_returns(n, mu, sigma, 42)
  let sigma2 = list_std(returns)
  let filtered = list.filter(returns, fn(r) { float.absolute_value(r) <. 2.0 *. sigma2 })
  let scaled = list.map(filtered, fn(r) { r *. 252.0 })
  let positive = list.filter(filtered, fn(r) { r >. 0.0 })
  let ann_ret = list_mean(returns) *. 252.0
  let ann_vol = list_std(returns) *. float_sqrt(252.0)
  "{"
  <> "\"n\":" <> int.to_string(n) <> ","
  <> "\"annualized_return\":" <> fmt_f(ann_ret) <> ","
  <> "\"annualized_vol\":" <> fmt_f(ann_vol) <> ","
  <> "\"pipeline_steps\":["
  <> pipeline_step_json("raw_returns", returns) <> ","
  <> pipeline_step_json("filtered_2sigma", filtered) <> ","
  <> pipeline_step_json("annualized", scaled) <> ","
  <> pipeline_step_json("positive_only", positive)
  <> "],\"engine\":\"Gleam 1.15 (BEAM/Erlang)\"}"
}

pub fn risk_json(n: Int, mu: Float, sigma: Float) -> String {
  let returns = gbm_returns(n, mu, sigma, 42)
  let cum = cumsum(returns)
  let var95 = percentile_p(returns, 5.0)
  let cvar95 = list.filter(returns, fn(r) { r <=. var95 }) |> list_mean
  let ann_ret = list_mean(returns) *. 252.0
  let ann_vol = list_std(returns) *. float_sqrt(252.0)
  let sr = sharpe(returns)
  let mdd = max_drawdown(cum)
  "{"
  <> "\"annualized_return\":" <> fmt_f(ann_ret) <> ","
  <> "\"annualized_vol\":" <> fmt_f(ann_vol) <> ","
  <> "\"var_95\":" <> fmt_f(var95) <> ","
  <> "\"cvar_95\":" <> fmt_f(cvar95) <> ","
  <> "\"sharpe_ratio\":" <> fmt_f(sr) <> ","
  <> "\"max_drawdown\":" <> fmt_f(mdd) <> ","
  <> "\"n\":" <> int.to_string(n) <> ","
  <> "\"engine\":\"Gleam 1.15 (BEAM/Erlang)\"}"
}

// ---------- Query parameter helpers ----------

fn query_str(
  params: List(#(String, String)),
  key: String,
  default: String,
) -> String {
  list.find(params, fn(p) { p.0 == key })
  |> result.map(fn(p) { p.1 })
  |> result.unwrap(default)
}

fn query_int(
  params: List(#(String, String)),
  key: String,
  default: Int,
) -> Int {
  query_str(params, key, "")
  |> int.parse
  |> result.unwrap(default)
}

fn query_float(
  params: List(#(String, String)),
  key: String,
  default: Float,
) -> Float {
  query_str(params, key, "")
  |> float.parse
  |> result.unwrap(default)
}

// ---------- HTTP router ----------

fn json_resp(body: String) -> Response {
  wisp.ok()
  |> wisp.json_body(body)
}

pub fn handle_request(req: Request) -> Response {
  use req <- wisp.handle_head(req)
  let params = wisp.get_query(req)
  case wisp.path_segments(req) {
    ["health"] ->
      wisp.ok()
      |> wisp.string_body("Gleam Hub OK")
    ["api", "gleam", "pipeline"] -> {
      let n = query_int(params, "n", 252)
      let mu = query_float(params, "mu", 0.08)
      let sigma = query_float(params, "sigma", 0.20)
      json_resp(pipeline_json(n, mu, sigma))
    }
    ["api", "gleam", "risk"] -> {
      let n = query_int(params, "n", 252)
      let mu = query_float(params, "mu", 0.08)
      let sigma = query_float(params, "sigma", 0.20)
      json_resp(risk_json(n, mu, sigma))
    }
    ["api", "gleam", "validate"] -> {
      let score = query_float(params, "score", 500.0)
      let grade = query_str(params, "grade", "B")
      json_resp(validate_risk_json(score, grade))
    }
    ["api", "gleam", "validate", "option"] -> {
      let call = query_float(params, "call", 10.0)
      let delta = query_float(params, "delta", 0.5)
      json_resp(validate_option_json(call, delta))
    }
    ["api", "gleam", "contract"] ->
      json_resp(contract_json())
    _ ->
      wisp.not_found()
  }
}

// ---------- Entry point ----------

pub fn main() {
  let secret_key_base = wisp.random_string(64)
  let assert Ok(_) =
    handle_request
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(4001)
    |> mist.bind("0.0.0.0")
    |> mist.start
  process.sleep_forever()
}

// ============================================================
// 서비스 계약 검증 레이어 — Gleam의 존재 이유
// ============================================================
// ServiceMessage 의 모든 variant를 case 표현식에서 반드시 처리해야 합니다.
// 새 variant를 추가하고 case를 수정하지 않으면 gleam build 가 실패합니다.
// Elixir(같은 BEAM)는 이 보장을 컴파일 타임에 제공하지 않습니다.

pub type ServiceMessage {
  RiskScore(score: Float, grade: String, user_id: Int)
  OptionPrice(call: Float, put: Float, delta: Float)
  VolatilityData(vol: Float, var_95: Float, cvar_95: Float)
  StreamBatch(count: Int, window: Int)
  Unknown(raw: String)
}

pub type ValidationError {
  ScoreOutOfRange(score: Float)
  NegativePremium(got: Float)
  DeltaOutOfRange(delta: Float)
  NegativeVolatility(vol: Float)
  EmptyBatch
  UnknownService(name: String)
}

// validate_message: ServiceMessage의 모든 variant를 처리해야 컴파일 성공
// Unknown 케이스를 제거하면 → "Non-exhaustive patterns" 컴파일 에러
fn validate_message(msg: ServiceMessage) -> Result(String, ValidationError) {
  case msg {
    RiskScore(score, grade, _) ->
      case score >=. 0.0 && score <=. 1000.0 {
        True  -> Ok("valid: score=" <> fmt_f(score) <> " grade=" <> grade)
        False -> Error(ScoreOutOfRange(score))
      }
    OptionPrice(call, _, delta) ->
      case call >=. 0.0 {
        False -> Error(NegativePremium(call))
        True  ->
          case delta >=. 0.0 && delta <=. 1.0 {
            True  -> Ok("valid: call=" <> fmt_f(call) <> " delta=" <> fmt_f(delta))
            False -> Error(DeltaOutOfRange(delta))
          }
      }
    VolatilityData(vol, var_95, _) ->
      case vol >=. 0.0 && var_95 <=. 0.0 {
        True  -> Ok("valid: vol=" <> fmt_f(vol))
        False -> Error(NegativeVolatility(vol))
      }
    StreamBatch(count, _) ->
      case count > 0 {
        False -> Error(EmptyBatch)
        True  -> Ok("valid: batch count=" <> int.to_string(count))
      }
    Unknown(raw) -> Error(UnknownService(raw))
    // 새 ServiceMessage variant 추가 시 여기에 케이스 추가 필수
    // 누락 시: "Non-exhaustive patterns in case expression" 컴파일 에러
  }
}

fn error_to_string(e: ValidationError) -> String {
  case e {
    ScoreOutOfRange(s)    -> "score_out_of_range:" <> fmt_f(s) <> " (valid:0-1000)"
    NegativePremium(v)    -> "negative_premium:" <> fmt_f(v)
    DeltaOutOfRange(d)    -> "delta_out_of_range:" <> fmt_f(d) <> " (valid:0-1)"
    NegativeVolatility(v) -> "negative_volatility:" <> fmt_f(v)
    EmptyBatch            -> "empty_batch"
    UnknownService(n)     -> "unknown_service:" <> n
  }
}

// Erlang에서 호출되는 공개 함수: 리스크 스코어 검증
pub fn validate_risk_json(score: Float, grade: String) -> String {
  let msg = RiskScore(score: score, grade: grade, user_id: 0)
  case validate_message(msg) {
    Ok(ok_msg) ->
      "{\"ok\":true,\"message\":\"" <> ok_msg
      <> "\",\"service\":\"risk\",\"exhaustive\":true,\"engine\":\"Gleam 1.15\"}"
    Error(e) ->
      "{\"ok\":false,\"error\":\"" <> error_to_string(e)
      <> "\",\"service\":\"risk\",\"exhaustive\":true,\"engine\":\"Gleam 1.15\"}"
  }
}

// 옵션 가격 검증
pub fn validate_option_json(call: Float, delta: Float) -> String {
  let msg = OptionPrice(call: call, put: 0.0, delta: delta)
  case validate_message(msg) {
    Ok(ok_msg) ->
      "{\"ok\":true,\"message\":\"" <> ok_msg
      <> "\",\"service\":\"option\",\"exhaustive\":true,\"engine\":\"Gleam 1.15\"}"
    Error(e) ->
      "{\"ok\":false,\"error\":\"" <> error_to_string(e)
      <> "\",\"service\":\"option\",\"exhaustive\":true,\"engine\":\"Gleam 1.15\"}"
  }
}

// 서비스 계약 목록 반환
pub fn contract_json() -> String {
  "{\"services\":[\"risk\",\"option\",\"volatility\",\"stream\"],"
  <> "\"message_types\":[\"RiskScore\",\"OptionPrice\",\"VolatilityData\",\"StreamBatch\",\"Unknown\"],"
  <> "\"guarantee\":\"exhaustive_pattern_match\","
  <> "\"note\":\"모든 ServiceMessage variant가 case에서 강제 처리됩니다. 누락 시 컴파일 에러.\","
  <> "\"engine\":\"Gleam 1.15 (BEAM/Erlang)\"}"
}
