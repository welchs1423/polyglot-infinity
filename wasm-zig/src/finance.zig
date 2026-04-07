// WebAssembly 금융 수학 모듈
// Zig 0.13 → wasm32-freestanding → 브라우저 직접 실행
// 서버 왕복 없이 클라이언트에서 Black-Scholes · VaR · DCF · Monte Carlo · 포트폴리오 최적화 계산

const std = @import("std");
const math = std.math;

// ── 정규분포 CDF (Abramowitz & Stegun 근사) ──────────────────────────────────
export fn normCdf(x: f64) f64 {
    const ax = @abs(x);
    const t = 1.0 / (1.0 + 0.2316419 * ax);
    const poly = t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
    const pdf = math.exp(-x * x / 2.0) / math.sqrt(2.0 * math.pi);
    const result = 1.0 - pdf * poly;
    return if (x >= 0.0) result else 1.0 - result;
}

// ── Black-Scholes Call 가격 ────────────────────────────────────────────────
export fn bsCall(s: f64, k: f64, r: f64, sigma: f64, t: f64) f64 {
    if (t <= 0.0) return @max(s - k, 0.0);
    const d1 = (math.log(f64, math.e, s / k) + (r + sigma * sigma / 2.0) * t) / (sigma * math.sqrt(t));
    const d2 = d1 - sigma * math.sqrt(t);
    return s * normCdf(d1) - k * math.exp(-r * t) * normCdf(d2);
}

// ── Black-Scholes Put 가격 ─────────────────────────────────────────────────
export fn bsPut(s: f64, k: f64, r: f64, sigma: f64, t: f64) f64 {
    if (t <= 0.0) return @max(k - s, 0.0);
    const d1 = (math.log(f64, math.e, s / k) + (r + sigma * sigma / 2.0) * t) / (sigma * math.sqrt(t));
    const d2 = d1 - sigma * math.sqrt(t);
    return k * math.exp(-r * t) * normCdf(-d2) - s * normCdf(-d1);
}

// ── Delta (콜) ────────────────────────────────────────────────────────────
export fn bsDelta(s: f64, k: f64, r: f64, sigma: f64, t: f64) f64 {
    if (t <= 0.0) return if (s > k) 1.0 else 0.0;
    const d1 = (math.log(f64, math.e, s / k) + (r + sigma * sigma / 2.0) * t) / (sigma * math.sqrt(t));
    return normCdf(d1);
}

// ── Gamma ─────────────────────────────────────────────────────────────────
export fn bsGamma(s: f64, k: f64, r: f64, sigma: f64, t: f64) f64 {
    if (t <= 0.0) return 0.0;
    const d1 = (math.log(f64, math.e, s / k) + (r + sigma * sigma / 2.0) * t) / (sigma * math.sqrt(t));
    const pdf = math.exp(-d1 * d1 / 2.0) / math.sqrt(2.0 * math.pi);
    return pdf / (s * sigma * math.sqrt(t));
}

// ── VaR (정규분포 가정, 단측 신뢰구간) ───────────────────────────────────────
export fn varNormal(mu: f64, sigma: f64, confidence: f64) f64 {
    const p = 1.0 - confidence;
    const t = math.sqrt(-2.0 * math.log(f64, math.e, @min(p, 1.0 - p)));
    const c0 = 2.515517;
    const c1 = 0.802853;
    const c2 = 0.010328;
    const d1 = 1.432788;
    const d2 = 0.189269;
    const d3 = 0.001308;
    const z_approx = t - (c0 + c1 * t + c2 * t * t) / (1.0 + d1 * t + d2 * t * t + d3 * t * t * t);
    const z = if (p < 0.5) -z_approx else z_approx;
    return -(mu + z * sigma);
}

// ── DCF 내재가치 ────────────────────────────────────────────────────────────
export fn dcfValue(fcf: f64, growth: f64, terminal: f64, wacc: f64, years: f64) f64 {
    var pv: f64 = 0.0;
    var y: f64 = 1.0;
    var cf: f64 = fcf;
    while (y <= years) : (y += 1.0) {
        cf *= (1.0 + growth);
        pv += cf / math.pow(f64, 1.0 + wacc, y);
    }
    const last_cf = fcf * math.pow(f64, 1.0 + growth, years);
    const tv = last_cf * (1.0 + terminal) / (wacc - terminal);
    pv += tv / math.pow(f64, 1.0 + wacc, years);
    return pv;
}

// ── GBM Monte Carlo VaR (브라우저에서 직접 실행) ───────────────────────────
// seed: 재현 가능한 의사난수 시드
// s0: 초기 가격, mu: 드리프트(연), sigma: 변동성(연)
// days: 시뮬레이션 기간, paths: 경로 수
// 반환: 95% VaR (손실률, 양수)
export fn mcVaR95(seed: u64, s0: f64, mu: f64, sigma: f64, days: u32, paths: u32) f64 {
    const dt: f64 = 1.0 / 252.0;
    const sqrt_dt = math.sqrt(dt);
    const drift = (mu - 0.5 * sigma * sigma) * dt;

    // 버퍼 없이 직접 순위 추정 (정렬 불가한 WASM 환경)
    // 손실 5% 분위: paths * 0.05 번째로 작은 최종 가격을 추적
    // 간소화: 모든 최종 수익률을 저장하지 않고 손실 카운트로 VaR 근사
    // 실용적 접근: 1000 경로 이하에서 배열 사용

    const MAX_PATHS = 2000;
    var finals: [MAX_PATHS]f64 = undefined;
    const actual_paths = @min(paths, MAX_PATHS);

    var rng: u64 = seed;
    var i: u32 = 0;
    while (i < actual_paths) : (i += 1) {
        var s: f64 = s0;
        var d: u32 = 0;
        while (d < days) : (d += 1) {
            // xorshift64 PRNG
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            const rv1 = @as(f64, @floatFromInt(rng & 0xFFFFFF)) / 16777216.0;
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            const rv2 = @as(f64, @floatFromInt(rng & 0xFFFFFF)) / 16777216.0;
            const z = math.sqrt(-2.0 * math.log(f64, math.e, rv1 + 1e-10)) * @cos(2.0 * math.pi * rv2);
            s *= math.exp(drift + sigma * sqrt_dt * z);
        }
        finals[i] = (s - s0) / s0; // 수익률
    }

    // 부분 선택 정렬로 5% 분위 찾기
    const k = @max(1, actual_paths / 20); // 5%
    var j: u32 = 0;
    while (j < k) : (j += 1) {
        var min_idx: u32 = j;
        var m: u32 = j + 1;
        while (m < actual_paths) : (m += 1) {
            if (finals[m] < finals[min_idx]) min_idx = m;
        }
        const tmp = finals[j];
        finals[j] = finals[min_idx];
        finals[min_idx] = tmp;
    }
    return -finals[k - 1]; // VaR (양수 손실률)
}

// ── 2-자산 최소분산 포트폴리오 가중치 ────────────────────────────────────────
// 반환: 자산1 최적 비중 w* (자산2 = 1 - w*)
// vol1, vol2: 개별 변동성, corr: 상관계수
export fn minVarWeight(vol1: f64, vol2: f64, corr: f64) f64 {
    const v1sq = vol1 * vol1;
    const v2sq = vol2 * vol2;
    const cov12 = corr * vol1 * vol2;
    const denom = v1sq + v2sq - 2.0 * cov12;
    if (@abs(denom) < 1e-12) return 0.5;
    const w = (v2sq - cov12) / denom;
    return @max(0.0, @min(1.0, w));
}

// ── 포트폴리오 샤프 비율 ──────────────────────────────────────────────────────
// w: 자산1 비중, mu1/mu2: 기대 수익률(연), vol1/vol2: 변동성, corr: 상관, rf: 무위험금리
export fn portfolioSharpe(w: f64, mu1: f64, mu2: f64, vol1: f64, vol2: f64, corr: f64, rf: f64) f64 {
    const port_mu = w * mu1 + (1.0 - w) * mu2;
    const port_var = w * w * vol1 * vol1
        + (1.0 - w) * (1.0 - w) * vol2 * vol2
        + 2.0 * w * (1.0 - w) * corr * vol1 * vol2;
    const port_vol = math.sqrt(port_var);
    if (port_vol < 1e-12) return 0.0;
    return (port_mu - rf) / port_vol;
}

