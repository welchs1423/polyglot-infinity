from fastapi import FastAPI
import ctypes
import os
import time
import urllib.request
import json

app = FastAPI(title="Python-Brain", version="v6")

# 1. C++ 코어 엔진 로드
lib_path = os.path.join(os.path.dirname(__file__), 'libcore.so')
cpp_core = ctypes.CDLL(lib_path)
cpp_core.extreme_computation.argtypes = [ctypes.c_int]
cpp_core.extreme_computation.restype = ctypes.c_double

# 2. Zig 코어 엔진 로드 (VaR · 변동성 추정)
zig_lib_path = os.path.join(os.path.dirname(__file__), '..', 'core-zig', 'zig-out', 'lib', 'libzigcore.so')
zig_core = None
try:
    zig_core = ctypes.CDLL(os.path.realpath(zig_lib_path))
    zig_core.volatility_estimate.argtypes = [ctypes.c_uint64, ctypes.c_int]
    zig_core.volatility_estimate.restype  = ctypes.c_double
    zig_core.value_at_risk.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double]
    zig_core.value_at_risk.restype  = ctypes.c_double
except Exception as e:
    print(f"[Zig Core] 로드 실패 (무시): {e}")

FALLBACK_RATES = {"KRW": 1350.00, "JPY": 149.50, "EUR": 0.92, "CNY": 7.23}
CURRENCY_WEIGHTS = {"KRW": 0.45, "JPY": 0.25, "EUR": 0.20, "CNY": 0.10}
POSITION_SIZE = 100_000_000  # 1억 원 포지션 가정


@app.get("/health")
def health():
    """Liveness probe: 서버가 당장 열릴 수 있는지 확인"""
    return {
        "status": "ok",
        "engine": "Python-Brain-v6",
        "port": 8000,
        "ffi_cpp": True,
        "ffi_zig": zig_core is not None,
    }


@app.get("/api/analyze")
def analyze_data():
    """
    외부 금융 API에서 실시간 다중 환율을 가져와 C++ 엔진으로 복합 리스크를 계산합니다.
    """
    start_time = time.time()

    api_url = "https://open.er-api.com/v6/latest/USD"
    rates = {}
    api_status = "Success"
    try:
        req = urllib.request.urlopen(api_url, timeout=3)
        data = json.loads(req.read())
        for currency in FALLBACK_RATES:
            rates[currency] = data['rates'].get(currency, FALLBACK_RATES[currency])
    except Exception as e:
        rates = FALLBACK_RATES.copy()
        api_status = f"Fallback Mode ({e})"

    # 다중 통화 가중합으로 복합 리스크 이터레이션 계산
    weighted_rate = sum(rates[c] * CURRENCY_WEIGHTS[c] for c in rates)
    iterations = int(weighted_rate * 3000)

    # C++ FFI 호출 — 누적 리스크 점수
    risk_score = cpp_core.extreme_computation(iterations)

    # Zig FFI 호출 — 변동성 추정 + VaR 계산
    zig_result = {}
    if zig_core:
        seed = int(time.time())
        volatility = zig_core.volatility_estimate(seed, 100000)
        mean_return = (weighted_rate - 1350.0) / 1350.0 * 0.01
        var_95 = zig_core.value_at_risk(mean_return, volatility, float(POSITION_SIZE))
        zig_result = {
            "engine": "Zig-Core-v1",
            "volatility": round(volatility, 6),
            "var_95": round(var_95, 2),
            "position_size": POSITION_SIZE,
        }

    # Julia 몬테카를로 시뮬레이션 호출 (옵션 — 오프라인이면 무시)
    julia_result = {}
    try:
        vol_param = zig_result.get("volatility", 0.20) if zig_result else 0.20
        julia_url = f"http://localhost:8002/api/julia/simulate?paths=5000&days=252&vol={vol_param:.4f}&mu=0.05"
        julia_req = urllib.request.urlopen(julia_url, timeout=5)
        julia_result = json.loads(julia_req.read())
    except Exception:
        pass  # Julia 오프라인 시 결과 생략

    end_time = time.time()
    elapsed_ms = round((end_time - start_time) * 1000, 2)

    rate_summary = " | ".join(f"{c}: {v:,.2f}" for c, v in rates.items())

    return {
        "version": "Python-Brain-v6 (Multi-Currency + C++ + Zig + Julia)",
        "source": f"Python + C++ + Zig + Julia ({elapsed_ms}ms)",
        "intelligence_score": 99,
        "recommendation": f"USD/KRW ₩{rates['KRW']:,.0f} · JPY ¥{rates['JPY']:,.1f} · EUR €{rates['EUR']:.4f} · CNY ¥{rates['CNY']:.4f}",
        "api_status": api_status,
        "computation_result": risk_score,
        "rates": rates,
        "rate_summary": rate_summary,
        "zig_analysis": zig_result,
        "julia_simulation": julia_result,
    }