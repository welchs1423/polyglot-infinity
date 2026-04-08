"""
main.py

FastAPI application for the brain-python microservice.

Responsibilities:
  - Load the C++ shared library via CoreBridge (ctypes FFI wrapper)
  - Optionally load the Zig shared library for VaR / volatility primitives
  - Expose HTTP endpoints for financial analytics and matrix operations
  - Delegate heavy numeric work to C++ / Zig; Python handles routing and I/O

Endpoints:
  GET  /health                  - liveness probe
  GET  /api/analyze             - multi-currency risk analysis (C++ + Zig + Julia)
  POST /api/matrix/multiply     - matrix multiplication (C++)
  POST /api/matrix/covariance   - sample covariance matrix (C++)
  POST /api/matrix/cholesky     - Cholesky decomposition (C++)
  POST /api/portfolio/variance  - portfolio variance (C++)
"""

import ctypes
import json
import math
import os
import time
import urllib.request
from typing import List

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, field_validator

from core_bridge import CoreBridge, CoreBridgeError

app = FastAPI(title="Python-Brain", version="v7")

# ------------------------------------------------------------------
# C++ core engine (calculator + matrix operations)
# ------------------------------------------------------------------
_cpp_lib_path = os.path.join(os.path.dirname(__file__), "libcore.so")
_cpp: CoreBridge | None = None
try:
    _cpp = CoreBridge(_cpp_lib_path)
except OSError as _e:
    print(f"[C++ Core] Load failed (continuing without): {_e}")

# ------------------------------------------------------------------
# Zig core engine (VaR and volatility estimation)
# ------------------------------------------------------------------
_zig_lib_path = os.path.realpath(
    os.path.join(os.path.dirname(__file__), "..", "core-zig", "zig-out", "lib", "libzigcore.so")
)
zig_core = None
try:
    zig_core = ctypes.CDLL(_zig_lib_path)
    zig_core.volatility_estimate.argtypes = [ctypes.c_uint64, ctypes.c_int]
    zig_core.volatility_estimate.restype = ctypes.c_double
    zig_core.value_at_risk.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double]
    zig_core.value_at_risk.restype = ctypes.c_double
except Exception as _e:
    print(f"[Zig Core] Load failed (continuing without): {_e}")

FALLBACK_RATES = {"KRW": 1350.00, "JPY": 149.50, "EUR": 0.92, "CNY": 7.23}
CURRENCY_WEIGHTS = {"KRW": 0.45, "JPY": 0.25, "EUR": 0.20, "CNY": 0.10}
POSITION_SIZE = 100_000_000  # 100 million KRW notional position


# ------------------------------------------------------------------
# Request / response models for matrix and portfolio endpoints
# ------------------------------------------------------------------

class MatMultiplyRequest(BaseModel):
    """
    Request body for POST /api/matrix/multiply.
    Matrices are provided as row-major flat lists.
    """
    a: List[float]   # row-major flat list for matrix A (m x k)
    m: int           # rows of A
    k: int           # shared inner dimension
    b: List[float]   # row-major flat list for matrix B (k x n)
    n: int           # cols of B

    @field_validator("m", "k", "n")
    @classmethod
    def positive_dim(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("matrix dimensions must be positive integers")
        return v


class CovarianceRequest(BaseModel):
    """
    Request body for POST /api/matrix/covariance.
    Returns the (assets x assets) sample covariance matrix.
    """
    returns: List[float]  # row-major flat list (assets x periods)
    assets: int           # number of assets
    periods: int          # number of return observations per asset (>= 2)

    @field_validator("assets", "periods")
    @classmethod
    def positive_dim(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("assets and periods must be positive integers")
        return v


class CholeskyRequest(BaseModel):
    """
    Request body for POST /api/matrix/cholesky.
    a must be a symmetric positive-definite matrix.
    """
    a: List[float]  # row-major flat list (n x n)
    n: int          # matrix dimension

    @field_validator("n")
    @classmethod
    def positive_dim(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("n must be a positive integer")
        return v


class PortfolioVarianceRequest(BaseModel):
    """
    Request body for POST /api/portfolio/variance.
    Computes the scalar portfolio variance v = w^T * cov * w.
    """
    cov: List[float]      # row-major covariance matrix (assets x assets)
    weights: List[float]  # portfolio weights (length = assets)
    assets: int           # number of assets

    @field_validator("assets")
    @classmethod
    def positive_dim(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("assets must be a positive integer")
        return v


# ------------------------------------------------------------------
# Helper: ensure C++ core is available
# ------------------------------------------------------------------

def _require_cpp() -> CoreBridge:
    if _cpp is None:
        raise HTTPException(
            status_code=503,
            detail="C++ core library is not loaded (libcore.so not found)"
        )
    return _cpp


# ------------------------------------------------------------------
# Endpoints
# ------------------------------------------------------------------

@app.get("/health")
def health():
    """Liveness probe: confirms the server is running and reports FFI status."""
    return {
        "status": "ok",
        "engine": "Python-Brain-v7",
        "port": 8000,
        "ffi_cpp": _cpp is not None,
        "ffi_zig": zig_core is not None,
    }


@app.get("/api/analyze")
def analyze_data():
    """
    Fetch live multi-currency FX rates, compute a weighted risk score via the
    C++ engine, estimate volatility and VaR via the Zig engine, and optionally
    call the Julia Monte-Carlo service.
    """
    bridge = _require_cpp()
    start_time = time.time()

    # Fetch live FX rates; fall back to constants if the external API is down.
    api_url = "https://open.er-api.com/v6/latest/USD"
    rates: dict[str, float] = {}
    api_status = "Success"
    try:
        req = urllib.request.urlopen(api_url, timeout=3)
        data = json.loads(req.read())
        for currency in FALLBACK_RATES:
            rates[currency] = float(data["rates"].get(currency, FALLBACK_RATES[currency]))
    except Exception as exc:
        rates = FALLBACK_RATES.copy()
        api_status = f"Fallback ({exc})"

    # Derive an iteration count from the currency-weighted composite rate.
    weighted_rate = sum(rates[c] * CURRENCY_WEIGHTS[c] for c in rates)
    iterations = int(weighted_rate * 3000)

    # C++ FFI: cumulative floating-point risk score.
    risk_score = bridge.extreme_computation(iterations)

    # Zig FFI: stochastic volatility and 95% VaR.
    zig_result: dict = {}
    if zig_core:
        seed = int(time.time())
        volatility = float(zig_core.volatility_estimate(ctypes.c_uint64(seed), ctypes.c_int(100_000)))
        mean_return = (weighted_rate - 1350.0) / 1350.0 * 0.01
        var_95 = float(zig_core.value_at_risk(
            ctypes.c_double(mean_return),
            ctypes.c_double(volatility),
            ctypes.c_double(float(POSITION_SIZE)),
        ))
        zig_result = {
            "engine": "Zig-Core-v1",
            "volatility": round(volatility, 6),
            "var_95": round(var_95, 2),
            "position_size": POSITION_SIZE,
        }

    # Julia Monte-Carlo service (optional; silently omitted when offline).
    julia_result: dict = {}
    try:
        vol_param = zig_result.get("volatility", 0.20) if zig_result else 0.20
        julia_url = (
            f"http://localhost:8002/api/julia/simulate"
            f"?paths=5000&days=252&vol={vol_param:.4f}&mu=0.05"
        )
        julia_req = urllib.request.urlopen(julia_url, timeout=5)
        julia_result = json.loads(julia_req.read())
    except Exception:
        pass

    elapsed_ms = round((time.time() - start_time) * 1000, 2)
    rate_summary = " | ".join(f"{c}: {v:,.2f}" for c, v in rates.items())

    return {
        "version": "Python-Brain-v7 (Multi-Currency + C++ + Zig + Julia)",
        "source": f"Python + C++ + Zig + Julia ({elapsed_ms}ms)",
        "intelligence_score": 99,
        "recommendation": (
            f"USD/KRW {rates['KRW']:,.0f} | "
            f"JPY {rates['JPY']:,.1f} | "
            f"EUR {rates['EUR']:.4f} | "
            f"CNY {rates['CNY']:.4f}"
        ),
        "api_status": api_status,
        "computation_result": risk_score,
        "rates": rates,
        "rate_summary": rate_summary,
        "zig_analysis": zig_result,
        "julia_simulation": julia_result,
    }


@app.post("/api/matrix/multiply")
def matrix_multiply(req: MatMultiplyRequest):
    """
    Multiply two matrices using the cache-tiled C++ implementation.

    Body (JSON):
      a   : row-major flat array for A  (length = m * k)
      m   : rows of A
      k   : shared inner dimension
      b   : row-major flat array for B  (length = k * n)
      n   : cols of B

    Response:
      c        : row-major flat array for C = A * B  (length = m * n)
      shape    : [m, n]
      frobenius: Frobenius norm of C
    """
    bridge = _require_cpp()
    try:
        c = bridge.mat_multiply(req.a, req.m, req.k, req.b, req.n)
    except (ValueError, CoreBridgeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    frobenius = bridge.mat_frobenius_norm(c, req.m, req.n)

    return {
        "c": c,
        "shape": [req.m, req.n],
        "frobenius_norm": round(frobenius, 6),
        "engine": "C++-mat_multiply",
    }


@app.post("/api/matrix/covariance")
def matrix_covariance(req: CovarianceRequest):
    """
    Compute the unbiased sample covariance matrix from a returns matrix.

    Body (JSON):
      returns : row-major flat array, shape (assets x periods).
                Row i is the time-series of asset i's returns.
      assets  : number of assets
      periods : number of return observations (>= 2)

    Response:
      cov     : row-major flat array for the (assets x assets) covariance matrix
      shape   : [assets, assets]
      port_vol: annualised portfolio volatility for equal-weight portfolio (approx)
    """
    bridge = _require_cpp()
    try:
        cov = bridge.covariance_matrix(req.returns, req.assets, req.periods)
    except (ValueError, CoreBridgeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    # Equal-weight portfolio variance as a derived metric.
    equal_weights = [1.0 / req.assets] * req.assets
    port_var = bridge.portfolio_variance(cov, equal_weights, req.assets)
    port_vol_annual = math.sqrt(max(port_var, 0.0) * 252)

    return {
        "cov": cov,
        "shape": [req.assets, req.assets],
        "equal_weight_portfolio_variance": round(port_var, 8),
        "equal_weight_portfolio_vol_annual": round(port_vol_annual, 6),
        "engine": "C++-covariance_matrix",
    }


@app.post("/api/matrix/cholesky")
def matrix_cholesky(req: CholeskyRequest):
    """
    Compute the lower-triangular Cholesky factor L such that A = L * L^T.

    Body (JSON):
      a : row-major flat array for a symmetric positive-definite matrix (n x n)
      n : matrix dimension

    Response:
      l     : row-major flat array for L (lower triangle; upper is zero)
      shape : [n, n]
    """
    bridge = _require_cpp()
    try:
        l = bridge.cholesky_decompose(req.a, req.n)
    except (ValueError, CoreBridgeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    return {
        "l": l,
        "shape": [req.n, req.n],
        "engine": "C++-cholesky_decompose",
    }


@app.post("/api/portfolio/variance")
def portfolio_variance(req: PortfolioVarianceRequest):
    """
    Compute the scalar portfolio variance v = w^T * cov * w.

    Body (JSON):
      cov     : row-major flat array for the covariance matrix (assets x assets)
      weights : portfolio weight vector (length = assets)
      assets  : number of assets

    Response:
      variance       : portfolio variance
      volatility     : portfolio volatility (sqrt of variance)
      volatility_ann : annualised volatility assuming 252 trading days
    """
    bridge = _require_cpp()
    try:
        variance = bridge.portfolio_variance(req.cov, req.weights, req.assets)
    except (ValueError, CoreBridgeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    volatility = math.sqrt(max(variance, 0.0))
    volatility_ann = volatility * math.sqrt(252)

    return {
        "variance": round(variance, 8),
        "volatility": round(volatility, 8),
        "volatility_annual": round(volatility_ann, 6),
        "engine": "C++-portfolio_variance",
    }
