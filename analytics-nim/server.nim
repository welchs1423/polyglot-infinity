# Polyglot Infinity — Nim Analytics Engine (:8005)
# Python 문법 + C 컴파일 속도 · 시계열 기술 통계 분석
#
# 엔드포인트:
#   GET /api/nim/timeseries  — 시계열 기술 통계 (mean, std, skew, kurtosis, autocorr)
#   GET /api/nim/momentum    — 모멘텀 팩터 분석 (RSI, MACD, 볼린저 밴드)
#   GET /health

import std/[asynchttpserver, asyncdispatch, strutils, strformat, math, json, uri]
import std/tables

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

proc ema(prices: seq[float], period: int): float =
  ## Exponential Moving Average (last value)
  if prices.len == 0: return 0.0
  let k = 2.0 / float(period + 1)
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
    "engine":"Nim 2.2.8"
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

  else:
    await req.respond(Http404, """{"error":"not found"}""", headers)

# ── 진입점 ────────────────────────────────────────────────

proc main() {.async.} =
  let server = newAsyncHttpServer()
  echo "Nim Analytics Engine listening on :8005"
  await server.serve(Port(8005), handler)

waitFor main()
