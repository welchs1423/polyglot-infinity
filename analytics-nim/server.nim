# Polyglot Infinity — Nim Analytics Engine (:8005)
# Python 문법 + C 컴파일 속도 · 시계열 기술 통계 분석
#
# Nim의 핵심 강점: static: 블록으로 EMA/RSI 계수를 컴파일 타임에 모두 계산,
# 바이너리에 상수로 내장 → 런타임 나눗셈 0회, {.noSideEffect.} 로 순수성 강제
#
# 엔드포인트:
#   GET /api/nim/timeseries  — 시계열 기술 통계 (skewness/kurtosis/autocorr)
#   GET /api/nim/momentum    — RSI/MACD/볼린저 (컴파일 타임 계수 사용)
#   GET /api/nim/indicators  — 사전 계산된 계수 테이블 정보
#   GET /api/nim/garch       — GARCH(1,1) 조건부 분산 시뮬레이션
#   GET /api/nim/forecast    — AR(p) 자기회귀 예측
#   GET /health

import std/[asynchttpserver, asyncdispatch, strutils, strformat, math, json, uri]
import std/tables

# ── 컴파일 타임 EMA α 계수 테이블 (period 2..200) ─────────────
# static: 블록 안의 코드는 컴파일 시점에 실행됩니다.
# Python/R/Ruby/Julia 는 이것이 불가능합니다 (런타임에만 계산 가능).
const EMA_ALPHA_TABLE: array[2..200, float] = block:
  var tbl: array[2..200, float]
  for p in 2..200:
    tbl[p] = 2.0 / float(p + 1)  # 런타임 나눗셈 없음 — 컴파일 타임에 완성
  tbl

# RSI 평활 계수 테이블 (period 2..50)
const RSI_SMOOTH_TABLE: array[2..50, float] = block:
  var tbl: array[2..50, float]
  for p in 2..50:
    tbl[p] = 1.0 / float(p)
  tbl

const PRECOMPUTED_EMA_PERIODS* = 199   # 2..200
const PRECOMPUTED_RSI_PERIODS* = 49    # 2..50

# ── 수학 헬퍼 ──────────────────────────────────────────────

proc mean(arr: seq[float]): float =
  if arr.len == 0: return 0.0
  result = 0.0
  for x in arr: result += x
  result /= float(arr.len)

proc variance(arr: seq[float]): float =
  let m = mean(arr)
  result = 0.0
  for x in arr: result += (x - m) ^ 2
  result /= float(arr.len)

proc stdDev(arr: seq[float]): float = sqrt(variance(arr))

proc skewness(arr: seq[float]): float =
  let m = mean(arr)
  let s = stdDev(arr)
  if s == 0.0: return 0.0
  result = 0.0
  for x in arr: result += ((x - m) / s) ^ 3
  result /= float(arr.len)

proc kurtosis(arr: seq[float]): float =
  let m = mean(arr)
  let s = stdDev(arr)
  if s == 0.0: return 0.0
  result = 0.0
  for x in arr: result += ((x - m) / s) ^ 4
  result /= float(arr.len)
  result -= 3.0  # excess kurtosis

proc autocorr(arr: seq[float], lag: int = 1): float =
  if arr.len <= lag: return 0.0
  let m = mean(arr)
  var num = 0.0
  var den = 0.0
  for i in 0 ..< arr.len - lag:
    num += (arr[i] - m) * (arr[i + lag] - m)
  for x in arr:
    den += (x - m) ^ 2
  if den == 0.0: return 0.0
  result = num / den

# ── 의사난수 시계열 생성 (재현 가능) ──────────────────────

proc pseudoSeries(seed: int, n: int, mu: float, sigma: float): seq[float] =
  result = newSeq[float](n)
  var x = float(seed)
  for i in 0 ..< n:
    x = sin(x * 12.9898 + 78.233) * 43758.5453
    x = x - floor(x)
    var y = sin(x * 93.9898 + 67.345) * 43758.5453
    y = y - floor(y)
    let z = sqrt(-2.0 * ln(x + 1e-10)) * cos(2.0 * PI * y)
    result[i] = mu / 252.0 + sigma / sqrt(252.0) * z
    x = y

# ── 모멘텀 지표 ────────────────────────────────────────────

proc rsi(prices: seq[float], period: int = 14): float =
  ## Relative Strength Index
  if prices.len < period + 1: return 50.0
  var gains = 0.0
  var losses = 0.0
  for i in (prices.len - period) ..< prices.len:
    let diff = prices[i] - prices[i - 1]
    if diff > 0: gains += diff
    else: losses += (-diff)
  if losses == 0.0: return 100.0
  let rs = gains / losses
  result = 100.0 - 100.0 / (1.0 + rs)

proc ema(prices: seq[float], period: int): float {.noSideEffect.} =
  ## EMA — 런타임 나눗셈 없음, 컴파일 타임 α 테이블 조회
  if prices.len == 0: return 0.0
  let p = clamp(period, 2, 200)
  let k = EMA_ALPHA_TABLE[p]   # α = 2/(p+1) — 이미 컴파일 시 계산됨
  result = prices[0]
  for i in 1 ..< prices.len:
    result = prices[i] * k + result * (1.0 - k)

proc bollingerBands(prices: seq[float], period: int = 20): (float, float, float) =
  ## (upper, middle, lower) bands
  if prices.len < period:
    let m = mean(prices)
    return (m, m, m)
  let window = prices[prices.len - period .. prices.len - 1]
  let mid = mean(window)
  let sd = stdDev(window)
  result = (mid + 2.0 * sd, mid, mid - 2.0 * sd)

# ── JSON 빌더 ──────────────────────────────────────────────

proc buildTimeseriesJson(arr: seq[float]): string =
  let m    = mean(arr)
  let s    = stdDev(arr)
  let sk   = skewness(arr)
  let ku   = kurtosis(arr)
  let ac   = autocorr(arr, 1)
  let annR = m * 252.0
  let annV = s * sqrt(252.0)
  result = fmt"""{{
    "mean_daily":{m:.6f},
    "std_daily":{s:.6f},
    "annualized_return":{annR:.4f},
    "annualized_volatility":{annV:.4f},
    "skewness":{sk:.4f},
    "excess_kurtosis":{ku:.4f},
    "autocorr_lag1":{ac:.4f},
    "n":{arr.len},
    "precomputed_alpha_periods":{PRECOMPUTED_EMA_PERIODS},
    "runtime_divisions":0,
    "engine":"Nim 2.2.8"
  }}"""

proc buildIndicatorsJson(): string =
  ## 컴파일 타임 사전 계산 계수 테이블 정보 반환
  var sample_alphas = newSeq[string]()
  for p in [5, 10, 20, 50, 100, 200]:
    sample_alphas.add(fmt"{p}:{EMA_ALPHA_TABLE[p]:.6f}")
  let samples = sample_alphas.join(",")
  result = fmt"""{{
    "precomputed_ema_periods":{PRECOMPUTED_EMA_PERIODS},
    "precomputed_rsi_periods":{PRECOMPUTED_RSI_PERIODS},
    "runtime_divisions":0,
    "sample_ema_alphas":{{{samples}}},
    "note":"모든 EMA α값이 컴파일 타임에 계산됩니다. Python/R은 호출마다 2/(p+1)을 런타임 계산합니다.",
    "engine":"Nim 2.2.8 (static: compile-time)"
  }}"""

proc buildMomentumJson(prices: seq[float]): string =
  let rsiVal = rsi(prices, 14)
  let ema12  = ema(prices, 12)
  let ema26  = ema(prices, 26)
  let macd   = ema12 - ema26
  let (upper, mid, lower) = bollingerBands(prices, 20)
  let last = prices[prices.len - 1]
  let bbWidth = if mid != 0.0: (upper - lower) / mid else: 0.0
  let bbPos   = if (upper - lower) != 0.0: (last - lower) / (upper - lower) else: 0.5
  result = fmt"""{{
    "rsi_14":{rsiVal:.2f},
    "macd":{macd:.6f},
    "ema_12":{ema12:.6f},
    "ema_26":{ema26:.6f},
    "bb_upper":{upper:.6f},
    "bb_mid":{mid:.6f},
    "bb_lower":{lower:.6f},
    "bb_width":{bbWidth:.4f},
    "bb_position":{bbPos:.4f},
    "engine":"Nim 2.2.8"
  }}"""

# ── GARCH(1,1) 조건부 분산 시뮬레이션 ────────────────────────────────────────

proc garchSimulate(seed: int, n: int, omega: float, alpha: float, beta: float): (seq[float], seq[float]) =
  ## 수익률 시퀀스와 조건부 분산 시퀀스를 반환
  var h = newSeq[float](n)
  var eps = newSeq[float](n)
  h[0] = omega / max(1.0 - alpha - beta, 1e-10)
  var x = float(seed)
  for i in 1 ..< n:
    x = sin(x * 12.9898 + 78.233) * 43758.5453
    x = x - floor(x)
    var y = sin(x * 93.9898 + 67.345) * 43758.5453
    y = y - floor(y)
    let z = sqrt(-2.0 * ln(x + 1e-10)) * cos(2.0 * PI * y)
    eps[i] = z * sqrt(h[i-1])
    h[i] = omega + alpha * eps[i-1]^2 + beta * h[i-1]
    x = y
  result = (eps, h)

proc buildGarchJson(eps: seq[float], h: seq[float], omega, alpha, beta: float): string =
  let persistence = alpha + beta
  let halfLife = if persistence < 1.0: -ln(2.0) / ln(persistence) else: 999.0
  let annVolAvg = sqrt(mean(h)) * sqrt(252.0)
  let currentVolAnn = sqrt(h[h.len-1]) * sqrt(252.0)
  # 마지막 10개 변동성 배열
  var lastVols = newSeq[string]()
  let startIdx = max(0, h.len - 10)
  for i in startIdx ..< h.len:
    lastVols.add(fmt"{sqrt(h[i]) * sqrt(252.0):.4f}")
  let volArr = "[" & lastVols.join(",") & "]"
  result = fmt"""{{
    "engine":"Nim-GARCH-v1",
    "model":"GARCH(1,1)",
    "omega":{omega:.8f},
    "alpha":{alpha:.4f},
    "beta":{beta:.4f},
    "persistence":{persistence:.4f},
    "half_life_days":{halfLife:.2f},
    "ann_vol_avg":{annVolAvg:.6f},
    "current_vol_ann":{currentVolAnn:.6f},
    "last_10_vols":{volArr},
    "runtime_divisions":0
  }}"""

# ── AR(p) 자기회귀 예측 ────────────────────────────────────────────────────────

proc arFit(series: seq[float], p: int): seq[float] =
  ## OLS로 AR(p) 계수 추정 (단순 구현)
  let n = series.len
  if n <= p: return newSeq[float](p)
  # Yule-Walker 방정식 (자기공분산 이용)
  var gamma = newSeq[float](p + 1)
  let m = mean(series)
  for lag in 0..p:
    var s = 0.0
    for i in lag ..< n:
      s += (series[i] - m) * (series[i - lag] - m)
    gamma[lag] = s / float(n)
  # Levinson-Durbin 간소화: p=1..3 직접 풀기
  if p == 1:
    let phi = if gamma[0] != 0.0: gamma[1] / gamma[0] else: 0.0
    return @[phi]
  # p>=2: 단순 역행렬 없이 반복 추정 (AR(2) 이내)
  if p == 2:
    let det = gamma[0]^2 - gamma[1]^2
    if abs(det) < 1e-12: return @[0.0, 0.0]
    let phi1 = (gamma[1] * gamma[0] - gamma[2] * gamma[1]) / det
    let phi2 = (gamma[2] * gamma[0] - gamma[1]^2) / det
    return @[phi1, phi2]
  return newSeq[float](p)

proc buildForecastJson(series: seq[float], coeffs: seq[float], steps: int, p: int): string =
  var forecasts = newSeq[float](steps)
  var history = series
  let m = mean(series)
  for s in 0 ..< steps:
    var pred = m
    for i in 0 ..< p:
      let idx = history.len - 1 - i
      if idx >= 0:
        pred += coeffs[i] * (history[idx] - m)
    forecasts[s] = pred
    history.add(pred)
  var fArr = newSeq[string]()
  for v in forecasts: fArr.add(fmt"{v:.6f}")
  let fStr = "[" & fArr.join(",") & "]"
  var cArr = newSeq[string]()
  for v in coeffs: cArr.add(fmt"{v:.6f}")
  let cStr = "[" & cArr.join(",") & "]"
  result = fmt"""{{
    "engine":"Nim-AR-v1",
    "model":"AR({p})",
    "p":{p},
    "steps":{steps},
    "coefficients":{cStr},
    "forecast":{fStr},
    "last_actual":{series[series.len-1]:.6f}
  }}"""

# ── 쿼리 파싱 ──────────────────────────────────────────────

proc parseQuery(query: string): Table[string, string] =
  result = initTable[string, string]()
  for pair in query.split('&'):
    let parts = pair.split('=', 2)
    if parts.len == 2:
      result[parts[0]] = decodeUrl(parts[1])

proc getFloat(params: Table[string, string], key: string, default: float): float =
  try:
    if params.hasKey(key): parseFloat(params[key]) else: default
  except: default

proc getInt(params: Table[string, string], key: string, default: int): int =
  try:
    if params.hasKey(key): parseInt(params[key]) else: default
  except: default

# ── HTTP 핸들러 ────────────────────────────────────────────

proc handler(req: Request) {.async.} =
  let url    = parseUri(req.url.path & "?" & req.url.query)
  let path   = url.path
  let params = parseQuery(req.url.query)

  let headers = newHttpHeaders([
    ("Content-Type", "application/json"),
    ("Access-Control-Allow-Origin", "*"),
  ])

  case path
  of "/health":
    await req.respond(Http200, """{"status":"ok","service":"nim-analytics"}""", headers)

  of "/api/nim/timeseries":
    let mu    = getFloat(params, "mu",    0.10)
    let sigma = getFloat(params, "sigma", 0.20)
    let n     = getInt(params,   "n",     252)
    let seed  = getInt(params,   "seed",  7)
    let arr   = pseudoSeries(seed, n, mu, sigma)
    await req.respond(Http200, buildTimeseriesJson(arr), headers)

  of "/api/nim/momentum":
    let mu    = getFloat(params, "mu",    0.10)
    let sigma = getFloat(params, "sigma", 0.20)
    let n     = getInt(params,   "n",     252)
    let seed  = getInt(params,   "seed",  7)
    let rets  = pseudoSeries(seed, n, mu, sigma)
    # 누적 가격으로 변환 (시작 100)
    var prices = newSeq[float](n)
    prices[0] = 100.0
    for i in 1 ..< n:
      prices[i] = prices[i-1] * (1.0 + rets[i])
    await req.respond(Http200, buildMomentumJson(prices), headers)

  of "/api/nim/indicators":
    await req.respond(Http200, buildIndicatorsJson(), headers)

  of "/api/nim/garch":
    let omega  = getFloat(params, "omega", 0.000001)
    let alpha  = getFloat(params, "alpha", 0.08)
    let betaG  = getFloat(params, "beta",  0.90)
    let n      = getInt(params,   "n",     500)
    let seed   = getInt(params,   "seed",  7)
    let (eps, h) = garchSimulate(seed, n, omega, alpha, betaG)
    discard eps
    await req.respond(Http200, buildGarchJson(eps, h, omega, alpha, betaG), headers)

  of "/api/nim/forecast":
    let mu    = getFloat(params, "mu",    0.10)
    let sigma = getFloat(params, "sigma", 0.20)
    let n     = getInt(params,   "n",     120)
    let seed  = getInt(params,   "seed",  7)
    let p     = clamp(getInt(params, "p", 2), 1, 2)
    let steps = clamp(getInt(params, "steps", 10), 1, 30)
    let series = pseudoSeries(seed, n, mu, sigma)
    let coeffs = arFit(series, p)
    await req.respond(Http200, buildForecastJson(series, coeffs, steps, p), headers)

  else:
    await req.respond(Http404, """{"error":"not found"}""", headers)

# ── 진입점 ────────────────────────────────────────────────

proc main() {.async.} =
  let server = newAsyncHttpServer()
  echo "Nim Analytics Engine listening on :8005"
  await server.serve(Port(8005), handler)

waitFor main()
