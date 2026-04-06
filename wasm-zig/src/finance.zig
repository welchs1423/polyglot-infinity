// WebAssembly 금융 수학 모듈
// Zig 0.13 → wasm32-freestanding → 브라우저 직접 실행
// 서버 왕복 없이 클라이언트에서 Black-Scholes · VaR · DCF 계산

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
// s=현재가, k=행사가, r=무위험금리, sigma=변동성, t=만기(년)
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
// 95% VaR: quantile = -1.6449
// 99% VaR: quantile = -2.3263
export fn varNormal(mu: f64, sigma: f64, confidence: f64) f64 {
    // 근사 역정규분포 (Beasley-Springer-Moro)
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

// ── DCF 내재가치 (단순 고정성장 모델) ─────────────────────────────────────────
// fcf: 현재 FCF, growth: 성장률, terminal: 영구성장률, wacc: 할인율, years: 예측기간
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
