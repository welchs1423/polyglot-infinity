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
  list(status = "ok", engine = "R-Stats-v1", port = 8003L)
}


