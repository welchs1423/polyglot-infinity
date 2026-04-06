"""
Polyglot Infinity — Julia Monte Carlo Risk Engine
포트 8002에서 실행. Python Brain(:8000)의 보조 수치 연산 엔진.

엔드포인트:
  GET  /api/julia/simulate?paths=10000&days=252&vol=0.2&mu=0.05
  GET  /health
"""

using HTTP
using JSON3
using Statistics
using Random

# ── 핵심 수치 연산 ─────────────────────────────────────────────────

"""
GBM(기하 브라운 운동) 기반 몬테카를로 시뮬레이션

- paths: 시뮬레이션 경로 수 (기본 10,000)
- days:  예측 일수 (기본 252 거래일 = 1년)
- mu:    연간 기대 수익률 (기본 0.05 = 5%)
- vol:   연간 변동성 (기본 0.20 = 20%)
"""
function monte_carlo_gbm(;paths::Int=10_000, days::Int=252, mu::Float64=0.05, vol::Float64=0.20)
    dt = 1.0 / days
    sqrt_dt = sqrt(dt)

    # 각 경로의 최종 수익률 저장
    final_returns = Vector{Float64}(undef, paths)

    Threads.@threads for i in 1:paths
        rng = MersenneTwister(i)  # 재현 가능한 per-thread 시드
        log_return = 0.0
        for _ in 1:days
            z = randn(rng)
            log_return += (mu - 0.5 * vol^2) * dt + vol * sqrt_dt * z
        end
        final_returns[i] = exp(log_return) - 1.0  # 총수익률
    end

    return final_returns
end

"""
VaR(Value at Risk) 및 CVaR(Conditional VaR, Expected Shortfall) 계산
"""
function compute_risk_metrics(returns::Vector{Float64}, confidence::Float64=0.95)
    sorted = sort(returns)
    n = length(sorted)
    var_idx = Int(floor((1 - confidence) * n))
    var_idx = max(var_idx, 1)

    var_val  = sorted[var_idx]          # VaR: 하위 5% 분위수
    cvar_val = mean(sorted[1:var_idx])  # CVaR: VaR 이하 평균 손실

    return (
        var_95  = var_val,
        cvar_95 = cvar_val,
        mean    = mean(returns),
        std     = std(returns),
        min_r   = minimum(returns),
        max_r   = maximum(returns),
        sharpe  = (mean(returns) - 0.0) / std(returns),  # 무위험이율 0 가정
    )
end

# ── HTTP 핸들러 ────────────────────────────────────────────────────
function simulate_handler(req::HTTP.Request)
    # 쿼리 파라미터 파싱
    uri    = HTTP.URIs.URI(req.target)
    params = HTTP.URIs.queryparams(uri)

    paths = parse(Int,     get(params, "paths", "10000"))
    days  = parse(Int,     get(params, "days",  "252"))
    vol   = parse(Float64, get(params, "vol",   "0.20"))
    mu    = parse(Float64, get(params, "mu",    "0.05"))

    # 범위 제한 (DoS 방지)
    paths = clamp(paths, 100, 100_000)
    days  = clamp(days,   5,  504)
    vol   = clamp(vol,  0.01, 2.0)

    t_start = time_ns()
    returns = monte_carlo_gbm(paths=paths, days=days, mu=mu, vol=vol)
    metrics = compute_risk_metrics(returns)
    elapsed_ms = round((time_ns() - t_start) / 1e6, digits=2)

    body = JSON3.write(Dict(
        "engine"       => "Julia-MonteCarlo-v1",
        "params"       => Dict("paths"=>paths, "days"=>days, "vol"=>vol, "mu"=>mu),
        "elapsed_ms"   => elapsed_ms,
        "threads"      => Threads.nthreads(),
        "var_95"       => round(metrics.var_95,  digits=6),
        "cvar_95"      => round(metrics.cvar_95, digits=6),
        "mean_return"  => round(metrics.mean,    digits=6),
        "std_return"   => round(metrics.std,     digits=6),
        "min_return"   => round(metrics.min_r,   digits=6),
        "max_return"   => round(metrics.max_r,   digits=6),
        "sharpe_ratio" => round(metrics.sharpe,  digits=4),
    ))

    return HTTP.Response(200, ["Content-Type" => "application/json",
                               "Access-Control-Allow-Origin" => "*"], body)
end

function health_handler(_req)
    HTTP.Response(200, ["Content-Type" => "application/json"],
        JSON3.write(Dict("status" => "online", "module" => "Julia-Engine-v1",
                         "threads" => Threads.nthreads())))
end

function router(req::HTTP.Request)
    path = HTTP.URIs.URI(req.target).path
    if startswith(path, "/api/julia/simulate")
        return simulate_handler(req)
    elseif path == "/health"
        return health_handler(req)
    else
        return HTTP.Response(404, [], "Not Found")
    end
end

# ── 서버 시작 ──────────────────────────────────────────────────────
const PORT = 8002
println("[Julia Engine] 🔬 Starting on http://0.0.0.0:$PORT (threads=$(Threads.nthreads()))")
HTTP.serve(router, "0.0.0.0", PORT)
