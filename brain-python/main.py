from fastapi import FastAPI
import ctypes
import os
import time
import urllib.request
import json

app = FastAPI()

# 1. C++ 코어 엔진 로드
lib_path = os.path.join(os.path.dirname(__file__), 'libcore.so')
cpp_core = ctypes.CDLL(lib_path)
cpp_core.extreme_computation.argtypes = [ctypes.c_int]
cpp_core.extreme_computation.restype = ctypes.c_double

FALLBACK_RATES = {"KRW": 1350.00, "JPY": 149.50, "EUR": 0.92, "CNY": 7.23}
CURRENCY_WEIGHTS = {"KRW": 0.45, "JPY": 0.25, "EUR": 0.20, "CNY": 0.10}

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

    # C++ FFI 호출
    risk_score = cpp_core.extreme_computation(iterations)

    end_time = time.time()
    elapsed_ms = round((end_time - start_time) * 1000, 2)

    rate_summary = " | ".join(f"{c}: {v:,.2f}" for c, v in rates.items())

    return {
        "version": "Python-Brain-v4 (Multi-Currency + C++ Core)",
        "source": f"Python + C++ FFI ({elapsed_ms}ms)",
        "intelligence_score": 99,
        "recommendation": f"USD/KRW ₩{rates['KRW']:,.0f} · JPY ¥{rates['JPY']:,.1f} · EUR €{rates['EUR']:.4f} · CNY ¥{rates['CNY']:.4f}",
        "api_status": api_status,
        "computation_result": risk_score,
        "rates": rates,
        "rate_summary": rate_summary,
    }