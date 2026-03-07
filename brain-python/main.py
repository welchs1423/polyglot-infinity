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

@app.get("/api/analyze")
def analyze_data():
    """
    외부 금융 API에서 실시간 환율을 가져와 C++ 엔진으로 리스크를 계산합니다.
    """
    start_time = time.time()
    
    api_url = "https://open.er-api.com/v6/latest/USD"
    try:
        req = urllib.request.urlopen(api_url, timeout=3)
        data = json.loads(req.read())
        exchange_rate = data['rates']['KRW'] # 현재 환율 추출
        api_status = "Success"
    except Exception as e:
        exchange_rate = 1350.00 # API 통신 실패 시 방어용 기본값
        api_status = f"Fallback Mode ({e})"

    # 환율 데이터를 바탕으로 한 복잡한 대출 리스크 가중치 연산이라고 가정합니다.
    iterations = int(exchange_rate * 3000) # 환율에 따라 약 400만 번 전후의 극한 연산 수행
    
    # C++ FFI 호출
    risk_score = cpp_core.extreme_computation(iterations)
    
    end_time = time.time()
    elapsed_ms = round((end_time - start_time) * 1000, 2)
    
    return {
        "version": "Python-Brain-v3 (API + C++ Core)",
        "source": f"Python + C++ FFI ({elapsed_ms}ms)",
        "intelligence_score": 99,
        "recommendation": f"Current USD/KRW Rate: ₩{exchange_rate:,.2f}. Risk assessment complete.",
        "api_status": api_status,
        "computation_result": risk_score
    }