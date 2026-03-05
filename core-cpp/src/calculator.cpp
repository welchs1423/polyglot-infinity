#include <iostream>

// 핵심 포인트: extern "C"
// C++ 컴파일러가 함수 이름을 마음대로 바꾸는 것(Name Mangling)을 방지
// 그래야 나중에 Go, Python, Rust에서 이 정확한 이름으로 함수를 찾아 호출 가능
extern "C"
{
    // 상태 확인용 간단한 출력 함수
    void print_cpp_status()
    {
        std::cout << "[C++ Core] System is ready for extreme calculations." << std::endl;
    }

    // 부동소수점 연산 시뮬레이션
    double extreme_computation(int iterations)
    {
        double result = 0.0;
        for (int i = 0; i < iterations; ++i)
        {
            result += 3.14159265359 * i / (i + 1.0);
        }
        return result;
    }
}