// Polyglot Infinity — Zig Core Engine
// C ABI 호환 공유 라이브러리: Python ctypes에서 직접 호출 가능
// 빌드: zig build-lib src/core.zig -dynamic -O ReleaseFast -femit-bin=libzigcore.so

const std = @import("std");

/// C++ extreme_computation과 동일한 시그니처 — Python FFI 드롭인 대체 가능
/// iterations 횟수만큼 누적 제곱근 합산 후 반환
export fn extreme_computation(iterations: c_int) f64 {
    var result: f64 = 0.0;
    var i: c_int = 1;
    while (i <= iterations) : (i += 1) {
        result += @sqrt(@as(f64, @floatFromInt(i)));
    }
    return result;
}

/// 몬테카를로 방식으로 리스크 변동성(표준편차) 추정
/// seed: 재현 가능한 난수 시드, samples: 시뮬레이션 횟수
export fn volatility_estimate(seed: u64, samples: c_int) f64 {
    var prng = std.rand.DefaultPrng.init(seed);
    const rng = prng.random();

    var sum: f64 = 0.0;
    var sum_sq: f64 = 0.0;
    const n: f64 = @floatFromInt(samples);

    var i: c_int = 0;
    while (i < samples) : (i += 1) {
        // [-1, 1] 범위 균등 난수 → 리스크 수익률 시뮬레이션
        const r = (rng.float(f64) * 2.0) - 1.0;
        sum += r;
        sum_sq += r * r;
    }

    const mean = sum / n;
    const variance = (sum_sq / n) - (mean * mean);
    return @sqrt(variance);
}

/// VaR(Value at Risk) 95% 근사: 정규분포 가정, z=1.645
export fn value_at_risk(mean_return: f64, volatility: f64, position_size: f64) f64 {
    const z_95: f64 = 1.645;
    return position_size * (mean_return - z_95 * volatility);
}
