import ctypes
import os
import time

# 1. C++ 공유 라이브러리(.so) 로드
# 현재 스크립트와 같은 경로에 있는 libcore.so를 불러옴
lib_path = os.path.join(os.path.dirname(__file__), 'libcore.so')
cpp_core = ctypes.CDLL(lib_path)

# 2. C++ 함수의 입출력 타입 정의
# double extreme_computation(int iterations);
cpp_core.extreme_computation.argtypes = [ctypes.c_int] # 입력: int
cpp_core.extreme_computation.restype = ctypes.c_double # 출력: double

def test_cpp_performance(iterations: int = 100000000):
    """
    파이썬과 C++의 연산 속도를 비교하는 테스트 함수
    """
    print(f"\n [성능 테스트] {iterations:,}번의 극한 연산 시작...")

    # --- 1. Python 순수 연산 ---
    start_py = time.time()
    py_result = 0.0
    for i in range(iterations):
        py_py = 3.14159265359 * i / (i + 1.0)
        py_result += py_py
    end_py = time.time()
    py_time = end_py - start_py
    print(f"Python 소요 시간: {py_time:4f}초 (결과: {py_result})")

    # --- 2. C++ 연산 (FFI 호출) ---
    # C++의 print_cpp_status() 함수 호출
    cpp_core.print_cpp_status()

    start_cpp = time.time()
    # 단 한줄로 C++ 엔진에 연산을 위임
    cpp_result = cpp_core.extreme_computation(iterations)
    end_cpp = time.time()
    cpp_time = end_cpp - start_cpp
    print(f" C++ (FFI) 소요 시간: {cpp_time:4f}초 (결과: {cpp_result})")

    # --- 3. 성능 비교 ---
    if cpp_time > 0:
        speedup = py_time / cpp_time
        print(f"결과: C++ 모듈이 Python보다 약 {speedup:.1f}배 빠릅니다!\n")

# 이 파일을 직접 실행할 때만 테스트가 돌아가도록 설정
if __name__ == "__main__":
    test_cpp_performance()