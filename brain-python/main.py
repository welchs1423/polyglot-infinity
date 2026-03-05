from fastapi import FastAPI
import ctypes
import os
import time

app = FastAPI()

# 1. C++ 코어 엔진 로드 (서버가 켜질 떄 한번만 장착)
lib_path = os.path.join(os.path.dirname(__file__), 'libcore.so')
cpp_core = ctypes.CDLL(lib_path)
cpp_core.extreme_computation.argtypes = [ctypes.c_int]
cpp_core.extreme_computation.restype = ctypes.c_double

@app.get("/api/analyze")
def analyze_data():
    """
    Go 백엔드에서 호출하는 데이터 분석 API
    (C++ 엔진을 이용해 초고속 연산을 수행함)
    """
    iterations = 5000000    # 500만 번의 연산 (API 응답 속도를 위해 조절)

    # C++ FFI 호출 및 시간 측정
    start_time = time.time()
    result = cpp_core.extreme_computation(iterations)
    end_time = time.time()

    elapse_ms = round((end_time - start_time) * 1000, 2)

    return {
        "version" : "Python-Brain-v2 (with C++ Core)",
        "source" : f"Python + C++ FFI ({elapse_ms}ms)", 
        "intelligence_score" : 99,
        "recommendation" : "System integration is optimal. C++ Engine active",
        "computation_result" : result
    }