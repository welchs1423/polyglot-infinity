.libPaths(c("~/R/library", .libPaths()))
library(plumber)
library(jsonlite)
library(MASS)  # fitdistr, built-in

# ── 정규분포 피팅 (Maximum Likelihood Estimation) ──────────────────────────────
#' @get /api/r/fit
#' @serializer json
function(n = "500", seed = "42") {
  n    <- as.integer(n)
  seed <- as.integer(seed)
  set.seed(seed)

  # 일별 로그 수익률 시뮬레이션 (GBM 기반 샘플)
  returns <- rnorm(n, mean = 0.0005, sd = 0.018)

  # 정규분포 MLE 피팅
  fit_normal <- fitdistr(returns, "normal")

  # t분포 피팅 (두꺼운 꼬리 적합)
  fit_t <- tryCatch(
    fitdistr(returns, "t"),
    error = function(e) list(estimate = list(m = NA, s = NA, df = NA))
  )

  # 기술 통계
  q <- quantile(returns, probs = c(0.01, 0.05, 0.25, 0.50, 0.75, 0.95, 0.99))

  # VaR / CVaR (정규 가정)
  mu  <- fit_normal$estimate[["mean"]]
  sig <- fit_normal$estimate[["sd"]]
  var_95  <- -(mu + qnorm(0.05) * sig)
  cvar_95 <- -(mu - sig * dnorm(qnorm(0.05)) / 0.05)

  # Sharpe Ratio (연율화, 무위험 금리 0%)
  sharpe <- (mean(returns) / sd(returns)) * sqrt(252)

  list(
    engine       = "R-Stats-v1",
    n_samples    = n,
    fit_normal   = list(
      mean = round(mu, 6),
      sd   = round(sig, 6)
    ),
    fit_t_df     = round(unname(fit_t$estimate[["df"]]), 3),
    var_95       = round(var_95, 6),
    cvar_95      = round(cvar_95, 6),
    sharpe_ratio = round(sharpe, 4),
    quantiles    = lapply(q, function(x) round(x, 6))
  )
}

# ── 포트폴리오 상관 분석 ────────────────────────────────────────────────────────
#' @get /api/r/correlation
#' @serializer json
function(seed = "42") {
  set.seed(as.integer(seed))
  assets <- c("KRW", "JPY", "EUR", "CNY")

  # 4-asset 일별 수익률 시뮬레이션
  returns_mat <- matrix(
    rnorm(252 * 4, mean = c(0.0002, 0.0001, 0.0003, 0.0001),
          sd = c(0.012, 0.008, 0.007, 0.005)),
    ncol = 4, byrow = TRUE
  )
  colnames(returns_mat) <- assets

  cor_mat  <- cor(returns_mat)
  cov_mat  <- cov(returns_mat)

  # 등가중 포트폴리오 변동성
  w    <- rep(0.25, 4)
  port_var <- as.numeric(t(w) %*% cov_mat %*% w)
  port_vol <- sqrt(port_var) * sqrt(252)

  list(
    engine            = "R-Stats-v1",
    assets            = assets,
    correlation       = apply(round(cor_mat, 4), 1, as.list),
    portfolio_vol_ann = round(port_vol, 6)
  )
}

# ── 헬스체크 ──────────────────────────────────────────────────────────────────
#' @get /health
#' @serializer json
function() {
  list(status = "ok", engine = "R-Stats-v2", port = 8003L)
}

# ── GARCH(1,1) 변동성 예측 ────────────────────────────────────────────────────
#' @get /api/r/garch
#' @serializer json
function(n = "500", seed = "42", omega = "0.000001", alpha = "0.08", beta_g = "0.90") {
  n      <- as.integer(n)
  seed   <- as.integer(seed)
  omega  <- as.numeric(omega)   # 장기 분산 가중치
  alpha1 <- as.numeric(alpha)   # ARCH 항 (직전 충격 가중치)
  beta1  <- as.numeric(beta_g)  # GARCH 항 (직전 분산 가중치)
  set.seed(seed)

  # GARCH(1,1) 시뮬레이션: h_t = omega + alpha1*eps_{t-1}^2 + beta1*h_{t-1}
  h    <- numeric(n)   # 조건부 분산
  eps  <- numeric(n)   # 충격 (수익률)
  h[1] <- omega / (1 - alpha1 - beta1 + 1e-10)  # 무조건 분산

  for (i in 2:n) {
    h[i]   <- omega + alpha1 * eps[i-1]^2 + beta1 * h[i-1]
    eps[i] <- rnorm(1, 0, sqrt(h[i]))
  }

  # 추정량
  ann_vol_avg  <- sqrt(mean(h)) * sqrt(252)
  persistence  <- alpha1 + beta1           # 1에 가까울수록 변동성 지속
  half_life    <- -log(2) / log(persistence + 1e-10)  # 변동성 충격 반감기(일)
  var_95_garch <- qnorm(0.05, 0, sqrt(h[n]))  # 현재 조건부 VaR
  last_vol_ann <- sqrt(h[n]) * sqrt(252)

  list(
    engine           = "R-GARCH-v1",
    model            = "GARCH(1,1)",
    n                = n,
    omega            = omega,
    alpha            = alpha1,
    beta             = beta1,
    persistence      = round(persistence, 4),
    half_life_days   = round(half_life, 2),
    ann_vol_avg      = round(ann_vol_avg, 6),
    current_vol_ann  = round(last_vol_ann, 6),
    var_95_today     = round(var_95_garch, 6),
    last_10_vols     = round(sqrt(tail(h, 10)) * sqrt(252), 6)
  )
}

# ── ARIMA 시계열 예측 ──────────────────────────────────────────────────────────
#' @get /api/r/arima
#' @serializer json
function(n = "120", seed = "42", steps = "10", p = "1", d_ = "1", q_ = "1") {
  n     <- as.integer(n)
  seed  <- as.integer(seed)
  steps <- as.integer(steps)
  p_    <- as.integer(p)
  d_i   <- as.integer(d_)
  q_i   <- as.integer(q_)
  set.seed(seed)

  # 의사 주가 시계열 (랜덤 워크 + 드리프트)
  returns <- rnorm(n, 0.0003, 0.015)
  prices  <- 100 * cumprod(1 + returns)

  # ARIMA(p,d,q) 피팅
  fit <- tryCatch(
    arima(prices, order = c(p_, d_i, q_i)),
    error = function(e) arima(prices, order = c(1, 1, 1))
  )

  # steps 기간 예측
  pred <- predict(fit, n.ahead = steps)
  forecast_vals <- as.numeric(pred$pred)
  se_vals       <- as.numeric(pred$se)

  list(
    engine       = "R-ARIMA-v1",
    model        = paste0("ARIMA(", p_, ",", d_i, ",", q_i, ")"),
    n_history    = n,
    n_forecast   = steps,
    aic          = round(AIC(fit), 2),
    last_price   = round(tail(prices, 1), 4),
    forecast     = round(forecast_vals, 4),
    forecast_se  = round(se_vals, 6),
    ci_upper_95  = round(forecast_vals + 1.96 * se_vals, 4),
    ci_lower_95  = round(forecast_vals - 1.96 * se_vals, 4)
  )
}


