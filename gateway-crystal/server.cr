# Polyglot Infinity — Crystal API Gateway (:9002)
# Crystal의 핵심 강점: spawn + Channel 으로 Go의 goroutine 모델을
# Ruby 문법으로 사용 — OS 스레드가 아닌 경량 Fiber, GC 없는 C 속도
#
# 엔드포인트:
#   GET /api/crystal/portfolio     — 포트폴리오 성과 분석
#   GET /api/crystal/fx            — 파이버 병렬 FX 수집 (4개 소스 동시)
#   GET /api/crystal/concurrent    — 파이버 동시성 명시적 데모
#   GET /health

require "http/server"
require "json"
require "math"

# ── FX 소스 정의 (각각 다른 지연시간 시뮬레이션) ────────────────

struct FxSource
  property name : String
  property latency_ms : Int32   # 시뮬레이션된 네트워크 지연
  property rate : Float64        # KRW 기준 환율
  property weight : Float64

  def initialize(@name, @latency_ms, @rate, @weight); end
end

struct FxResult
  property source : String
  property rate : Float64
  property elapsed_ms : Int32
  property ok : Bool

  def initialize(@source, @rate, @elapsed_ms, @ok); end
end

FX_SOURCES = [
  FxSource.new("Bloomberg-Sim",   12, 1385.50_f64, 0.40_f64),
  FxSource.new("Reuters-Sim",     28, 1384.20_f64, 0.30_f64),
  FxSource.new("ExchangeRate-API", 8, 1386.00_f64, 0.20_f64),
  FxSource.new("FallbackCache",    2, 1383.00_f64, 0.10_f64),
]

# spawn + Channel: 4개 파이버가 동시에 FX 소스를 조회
# OS 스레드가 아닌 Fiber — Ruby의 Thread/Mutex 불필요
def fetch_fx_concurrent(sources : Array(FxSource)) : Array(FxResult)
  channel = Channel(FxResult).new(sources.size)

  sources.each do |src|
    spawn do
      t0 = Time.monotonic
      # sleep은 Crystal의 fiber scheduler를 통해 실행 — 다른 파이버 차단 없음
      sleep(src.latency_ms.milliseconds)
      elapsed = ((Time.monotonic - t0).total_milliseconds).to_i32
      channel.send(FxResult.new(src.name, src.rate, elapsed, true))
    end
  end

  # 4개 파이버 결과 수집 (순서는 완료 순)
  sources.size.times.map { channel.receive }.to_a
end

def build_concurrent_json(results : Array(FxResult), total_ms : Int32) : String
  individual_ms = results.sum(&.elapsed_ms)
  weighted_rate = begin
    total_w = FX_SOURCES.sum(&.weight)
    results.sum { |r|
      src = FX_SOURCES.find { |s| s.name == r.source }
      (src ? src.weight : 0.0_f64) * r.rate
    } / total_w
  end

  String.build do |s|
    s << %[{"concurrent_total_ms":#{total_ms},]
    s << %["sequential_would_be_ms":#{individual_ms},]
    s << %["speedup_factor":#{(individual_ms.to_f / total_ms.to_f).round(2)},]
    s << %["weighted_krw":#{weighted_rate.round(2)},]
    s << %["fiber_model":"spawn/Channel (OS thread 불필요)",]
    s << %["sources":[]}
    results.each_with_index do |r, i|
      s << "," if i > 0
      s << %[{"source":"#{r.source}","rate":#{r.rate},"elapsed_ms":#{r.elapsed_ms}}]
    end
    s << %[],"engine":"Crystal 1.19"}]
  end
end

# ── 기존 코드 유지 ─────────────────────────────────────────

def mean(arr : Array(Float64)) : Float64
  arr.sum / arr.size
end

def std_dev(arr : Array(Float64)) : Float64
  m = mean(arr)
  variance = arr.sum { |x| (x - m) ** 2 } / arr.size
  Math.sqrt(variance)
end

# 최대 낙폭 (Maximum Drawdown)
def max_drawdown(returns : Array(Float64)) : Float64
  peak = 1.0
  nav = 1.0
  mdd = 0.0
  returns.each do |r|
    nav *= (1.0 + r)
    peak = nav if nav > peak
    dd = (peak - nav) / peak
    mdd = dd if dd > mdd
  end
  mdd
end

# 샤프 비율 (연환산, 무위험 이자율 3%)
def sharpe_ratio(returns : Array(Float64), rf : Float64 = 0.03) : Float64
  daily_rf = rf / 252.0
  excess = returns.map { |r| r - daily_rf }
  m = mean(excess)
  s = std_dev(excess)
  return 0.0 if s == 0.0
  m / s * Math.sqrt(252.0)
end

# Sortino 비율 (하방 편차만)
def sortino_ratio(returns : Array(Float64), rf : Float64 = 0.03) : Float64
  daily_rf = rf / 252.0
  excess = returns.map { |r| r - daily_rf }
  m = mean(excess)
  downside = excess.select { |r| r < 0 }
  return 0.0 if downside.empty?
  ds = Math.sqrt(downside.sum { |r| r ** 2 } / downside.size) * Math.sqrt(252.0)
  return 0.0 if ds == 0.0
  m * 252.0 / ds
end

# ── 포트폴리오 시뮬레이션 ──────────────────────────────────

# 시드 기반 간단 난수 (외부 의존 없이 재현성 확보)
def pseudo_returns(seed : Int32, n : Int32, mu : Float64, sigma : Float64) : Array(Float64)
  returns = [] of Float64
  x = seed.to_f64
  n.times do
    x = Math.sin(x * 12.9898 + 78.233) * 43758.5453
    x -= x.floor
    # Box-Muller 변환
    y = Math.sin(x * 93.9898 + 67.345) * 43758.5453
    y -= y.floor
    z = Math.sqrt(-2.0 * Math.log(x + 1e-10)) * Math.cos(2.0 * Math::PI * y)
    returns << mu / 252.0 + sigma / Math.sqrt(252.0) * z
    x = y
  end
  returns
end

# ── FX 가중평균 계산 ────────────────────────────────────────

struct FxRate
  property currency : String
  property rate : Float64      # vs KRW
  property weight : Float64

  def initialize(@currency, @rate, @weight); end
end

def weighted_fx(rates : Array(FxRate)) : Float64
  total_weight = rates.sum(&.weight)
  rates.sum { |r| r.rate * r.weight } / total_weight
end

# ── JSON 빌더 헬퍼 ──────────────────────────────────────────

def build_portfolio_json(
  total_return : Float64,
  ann_return : Float64,
  volatility : Float64,
  sharpe : Float64,
  sortino : Float64,
  mdd : Float64,
  days : Int32
) : String
  String.build do |s|
    s << %[{"total_return":#{total_return.round(4)},]
    s << %["annualized_return":#{ann_return.round(4)},]
    s << %["volatility":#{volatility.round(4)},]
    s << %["sharpe_ratio":#{sharpe.round(4)},]
    s << %["sortino_ratio":#{sortino.round(4)},]
    s << %["max_drawdown":#{mdd.round(4)},]
    s << %["days":#{days},]
    s << %["engine":"Crystal 1.19"]
    s << "}"
  end
end

def build_fx_json(rates : Array(FxRate), weighted : Float64) : String
  String.build do |s|
    s << %[{"weighted_krw":#{weighted.round(2)},]
    s << %["rates":{]
    rates.each_with_index do |r, i|
      s << %["#{r.currency}":{"rate":#{r.rate},"weight":#{r.weight}}]
      s << "," unless i == rates.size - 1
    end
    s << %[},"engine":"Crystal 1.19"}]
  end
end

# ── 쿼리 파싱 ──────────────────────────────────────────────

def parse_params(query : String?) : Hash(String, String)
  result = {} of String => String
  return result if query.nil? || query.empty?
  query.split("&").each do |pair|
    parts = pair.split("=", 2)
    result[parts[0]] = parts[1] if parts.size == 2
  end
  result
end

def get_float(params : Hash(String, String), key : String, default : Float64) : Float64
  params[key]?.try(&.to_f64?) || default
end

def get_int(params : Hash(String, String), key : String, default : Int32) : Int32
  params[key]?.try(&.to_i32?) || default
end

# ── HTTP 서버 ──────────────────────────────────────────────

server = HTTP::Server.new do |ctx|
  path   = ctx.request.path
  params = parse_params(ctx.request.query)

  ctx.response.headers["Access-Control-Allow-Origin"] = "*"
  ctx.response.content_type = "application/json"

  case path
  when "/health"
    ctx.response.print %({"status":"ok","service":"crystal-gateway"})

  when "/api/crystal/portfolio"
    mu      = get_float(params, "mu",      0.12)   # 연 기대 수익률
    sigma   = get_float(params, "sigma",   0.18)   # 연 변동성
    days    = get_int(params,   "days",    252)
    seed    = get_int(params,   "seed",    42)

    rets      = pseudo_returns(seed, days, mu, sigma)
    total_ret = rets.reduce(1.0) { |acc, r| acc * (1.0 + r) } - 1.0
    ann_ret   = (1.0 + total_ret) ** (252.0 / days) - 1.0
    vol       = std_dev(rets) * Math.sqrt(252.0)
    sharpe    = sharpe_ratio(rets)
    sortino   = sortino_ratio(rets)
    mdd       = max_drawdown(rets)

    ctx.response.print build_portfolio_json(total_ret, ann_ret, vol, sharpe, sortino, mdd, days)

  when "/api/crystal/fx"
    # 4개 파이버 동시 수집 — total ≈ max(latencies), not sum
    t0 = Time.monotonic
    results = fetch_fx_concurrent(FX_SOURCES.dup)
    total_ms = ((Time.monotonic - t0).total_milliseconds).to_i32
    ctx.response.print build_concurrent_json(results, total_ms)

  when "/api/crystal/concurrent"
    # 파이버 동시성 명시적 데모
    t0 = Time.monotonic
    results = fetch_fx_concurrent(FX_SOURCES.dup)
    total_ms = ((Time.monotonic - t0).total_milliseconds).to_i32
    ctx.response.print build_concurrent_json(results, total_ms)

  else
    ctx.response.status = HTTP::Status::NOT_FOUND
    ctx.response.print %({"error":"not found"})
  end
end

port = 9002
puts "Crystal API Gateway listening on :#{port}"
server.listen("0.0.0.0", port)
