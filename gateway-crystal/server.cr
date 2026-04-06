# Polyglot Infinity — Crystal API Gateway (:9002)
# Ruby 문법 + 네이티브 컴파일 · 타입 안전 · 멀티스레드 HTTP
# 역할: 포트폴리오 성과 분석 + 환율 가중평균 계산
#
# 엔드포인트:
#   GET /api/crystal/portfolio  — 포트폴리오 수익률 · 샤프 지수 · MDD
#   GET /api/crystal/fx         — 다중 통화 가중평균 환율
#   GET /health

require "http/server"
require "json"
require "math"

# ── 통계 헬퍼 ──────────────────────────────────────────────

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
    # 기본 환율 (KRW 기준)
    rates = [
      FxRate.new("USD", get_float(params, "usd", 1380.0), get_float(params, "w_usd", 0.50)),
      FxRate.new("EUR", get_float(params, "eur", 1510.0), get_float(params, "w_eur", 0.25)),
      FxRate.new("JPY", get_float(params, "jpy",    9.2), get_float(params, "w_jpy", 0.15)),
      FxRate.new("CNY", get_float(params, "cny",  191.0), get_float(params, "w_cny", 0.10)),
    ]
    weighted = weighted_fx(rates)
    ctx.response.print build_fx_json(rates, weighted)

  else
    ctx.response.status = HTTP::Status::NOT_FOUND
    ctx.response.print %({"error":"not found"})
  end
end

port = 9002
puts "Crystal API Gateway listening on :#{port}"
server.listen("0.0.0.0", port)
