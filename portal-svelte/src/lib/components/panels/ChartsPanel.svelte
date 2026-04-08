<script>
    import { onMount } from "svelte";
    import { API_BASE } from "$lib/api";

    /** @type {HTMLCanvasElement} */
    let mcCanvas;
    /** @type {HTMLCanvasElement} */
    let smileCanvas;
    /** @type {HTMLCanvasElement} */
    let varCanvas;

    let loading = $state(false);
    /** @type {any} */
    let mcData = $state(null);
    /** @type {any} */
    let smileData = $state(null);
    /** @type {any} */
    let varData = $state(null);

    async function fetchAll() {
        loading = true;
        try {
            const [mc, smile, bulk] = await Promise.all([
                fetch(
                    `${API_BASE}/api/julia/simulate?paths=200&days=252&vol=0.20&mu=0.05`,
                )
                    .then((x) => x.json())
                    .catch(() => null),
                fetch(
                    `${API_BASE}/api/fsharp/smile?s=100&r=0.05&t=1.0&k_min=80&k_max=120&steps=9&atm_vol=0.20&skew=-0.05&curvature=0.10&type=call`,
                )
                    .then((x) => x.json())
                    .catch(() => null),
                fetch(`${API_BASE}/api/risk/summary`)
                    .then((x) => x.json())
                    .catch(() => null),
            ]);
            mcData = mc;
            smileData = smile;
            varData = bulk;
        } finally {
            loading = false;
        }
    }

    // ── Monte Carlo 경로 차트 ──────────────────────────────────
    /** @param {any} data */
    function drawMC(data) {
        if (!mcCanvas || !data?.paths) return;
        const ctx = mcCanvas.getContext("2d");
        if (!ctx) return;
        const W = mcCanvas.width,
            H = mcCanvas.height;
        ctx.clearRect(0, 0, W, H);

        const paths = data.paths; // [[s0,s1,...,sN], ...]
        const allVals = paths.flat();
        const minV = Math.min(...allVals);
        const maxV = Math.max(...allVals);
        const days = paths[0].length;

        // 배경 그리드
        ctx.strokeStyle = "#1e293b";
        ctx.lineWidth = 1;
        for (let i = 0; i <= 4; i++) {
            const y = (H * i) / 4;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(W, y);
            ctx.stroke();
            const val = maxV - ((maxV - minV) * i) / 4;
            ctx.fillStyle = "#475569";
            ctx.font = "10px monospace";
            ctx.fillText(val.toFixed(0), 4, y - 2);
        }

        // 경로 그리기
        const nPaths = Math.min(paths.length, 80);
        for (let p = 0; p < nPaths; p++) {
            const path = paths[p];
            const alpha = 0.15 + (p === 0 ? 0.7 : 0);
            ctx.strokeStyle = p === 0 ? "#60a5fa" : `rgba(99,102,241,${alpha})`;
            ctx.lineWidth = p === 0 ? 1.5 : 0.6;
            ctx.beginPath();
            for (let d = 0; d < days; d++) {
                const x = (d / (days - 1)) * W;
                const y = H - ((path[d] - minV) / (maxV - minV)) * H;
                d === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
            }
            ctx.stroke();
        }

        // VaR 95% 수평선
        if (data.var_95) {
            const yVar = H - ((data.var_95 + 100 - minV) / (maxV - minV)) * H;
            ctx.strokeStyle = "#ef4444";
            ctx.lineWidth = 1.5;
            ctx.setLineDash([4, 3]);
            ctx.beginPath();
            ctx.moveTo(0, yVar);
            ctx.lineTo(W, yVar);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.fillStyle = "#ef4444";
            ctx.font = "10px monospace";
            ctx.fillText(`VaR95% ${data.var_95?.toFixed(2)}`, 4, yVar - 3);
        }
    }

    // ── Vol Smile 차트 ────────────────────────────────────────
    /** @param {any} data */
    function drawSmile(data) {
        if (!smileCanvas || !data?.smile) return;
        const ctx = smileCanvas.getContext("2d");
        if (!ctx) return;
        const W = smileCanvas.width,
            H = smileCanvas.height;
        ctx.clearRect(0, 0, W, H);

        const pts =
            /** @type {Array<{strike:number,iv:number,price:number}>} */ (
                data.smile
            );
        const strikes = pts.map((p) => p.strike);
        const ivs = pts.map((p) => p.iv);
        const minK = Math.min(...strikes),
            maxK = Math.max(...strikes);
        const minIV = Math.min(...ivs) * 0.9,
            maxIV = Math.max(...ivs) * 1.05;

        // 그리드
        ctx.strokeStyle = "#1e293b";
        ctx.lineWidth = 1;
        for (let i = 0; i <= 4; i++) {
            const y = (H * i) / 4;
            ctx.beginPath();
            ctx.moveTo(40, y);
            ctx.lineTo(W, y);
            ctx.stroke();
            const val = maxIV - ((maxIV - minIV) * i) / 4;
            ctx.fillStyle = "#475569";
            ctx.font = "10px monospace";
            ctx.fillText((val * 100).toFixed(1) + "%", 2, y + 3);
        }

        // ATM 수직선
        const atm = 100;
        const xAtm = 40 + ((atm - minK) / (maxK - minK)) * (W - 44);
        ctx.strokeStyle = "#374151";
        ctx.lineWidth = 1;
        ctx.setLineDash([3, 3]);
        ctx.beginPath();
        ctx.moveTo(xAtm, 0);
        ctx.lineTo(xAtm, H);
        ctx.stroke();
        ctx.setLineDash([]);

        // Smile 곡선
        ctx.strokeStyle = "#a78bfa";
        ctx.lineWidth = 2;
        ctx.beginPath();
        pts.forEach((p, i) => {
            const x = 40 + ((p.strike - minK) / (maxK - minK)) * (W - 44);
            const y = H - ((p.iv - minIV) / (maxIV - minIV)) * H;
            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        });
        ctx.stroke();

        // 데이터 점
        pts.forEach((p) => {
            const x = 40 + ((p.strike - minK) / (maxK - minK)) * (W - 44);
            const y = H - ((p.iv - minIV) / (maxIV - minIV)) * H;
            ctx.fillStyle = "#c4b5fd";
            ctx.beginPath();
            ctx.arc(x, y, 3, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = "#94a3b8";
            ctx.font = "9px monospace";
            ctx.fillText(String(p.strike), x - 8, H - 2);
        });
    }

    // ── VaR 히스토그램 ────────────────────────────────────────
    /** @param {any} data */
    function drawVaR(data) {
        if (!varCanvas || !data) return;
        const ctx = varCanvas.getContext("2d");
        if (!ctx) return;
        const W = varCanvas.width,
            H = varCanvas.height;
        ctx.clearRect(0, 0, W, H);

        // risk_logs 통계로 정규분포 근사 히스토그램 생성
        const avg = data.avg_var ?? data.avg ?? 0;
        const minV = data.min_var ?? data.min ?? avg * 0.5;
        const maxV = data.max_var ?? data.max ?? avg * 1.5;
        const p95 = data.p95_var ?? data.p95 ?? avg * 1.3;
        const std = (maxV - minV) / 6;

        // 30 bins 히스토그램 (정규 근사)
        const BINS = 30;
        const binW = (maxV - minV) / BINS;
        /** @type {number[]} */
        const bins = [];
        for (let i = 0; i < BINS; i++) {
            const x = minV + (i + 0.5) * binW;
            const z = (x - avg) / std;
            bins.push(Math.exp(-0.5 * z * z));
        }
        const maxBin = Math.max(...bins);

        const pad = 40;
        const bw = (W - pad * 2) / BINS;

        // 그리드
        ctx.strokeStyle = "#1e293b";
        ctx.lineWidth = 1;
        for (let i = 0; i <= 4; i++) {
            const y = pad + ((H - pad * 2) * i) / 4;
            ctx.beginPath();
            ctx.moveTo(pad, y);
            ctx.lineTo(W - 10, y);
            ctx.stroke();
        }

        // 막대
        bins.forEach((v, i) => {
            const barH = ((H - pad * 2) * v) / maxBin;
            const x = pad + i * bw;
            const y = H - pad - barH;
            const binCenter = minV + (i + 0.5) * binW;
            ctx.fillStyle = binCenter >= p95 ? "#ef4444" : "#6366f1";
            ctx.fillRect(x, y, bw - 1, barH);
        });

        // P95 수직선
        const xP95 = pad + ((p95 - minV) / (maxV - minV)) * (W - pad * 2);
        ctx.strokeStyle = "#ef4444";
        ctx.lineWidth = 2;
        ctx.setLineDash([4, 3]);
        ctx.beginPath();
        ctx.moveTo(xP95, pad);
        ctx.lineTo(xP95, H - pad);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.fillStyle = "#ef4444";
        ctx.font = "10px monospace";
        ctx.fillText(`p95: ${p95?.toFixed(4)}`, xP95 + 3, pad + 12);

        // avg 수직선
        const xAvg = pad + ((avg - minV) / (maxV - minV)) * (W - pad * 2);
        ctx.strokeStyle = "#22c55e";
        ctx.lineWidth = 1.5;
        ctx.setLineDash([3, 3]);
        ctx.beginPath();
        ctx.moveTo(xAvg, pad);
        ctx.lineTo(xAvg, H - pad);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.fillStyle = "#22c55e";
        ctx.font = "10px monospace";
        ctx.fillText(`avg: ${avg?.toFixed(4)}`, xAvg + 3, pad + 24);

        // x축 레이블
        ctx.fillStyle = "#475569";
        ctx.font = "9px monospace";
        ctx.fillText(minV.toFixed(3), pad, H - 4);
        ctx.fillText(maxV.toFixed(3), W - pad - 10, H - 4);
    }

    $effect(() => {
        if (mcData) drawMC(mcData);
    });
    $effect(() => {
        if (smileData) drawSmile(smileData);
    });
    $effect(() => {
        if (varData) drawVaR(varData);
    });
</script>

<section class="panel charts-panel">
    <div class="panel-header">
        <div>
            <h2>📊 금융 시각화 차트</h2>
            <p class="subtitle">
                Monte Carlo 경로 (Julia) · Volatility Smile (F#) · VaR 분포
                (Rust)
            </p>
        </div>
        <button class="chart-btn" onclick={fetchAll} disabled={loading}>
            {loading ? "로딩 중..." : "차트 갱신"}
        </button>
    </div>

    <div class="charts-grid">
        <!-- Monte Carlo -->
        <div class="chart-box">
            <div class="chart-label">
                <span class="chart-title"
                    >Monte Carlo GBM — 200경로 (Julia :8002)</span
                >
                {#if mcData && !mcData.error}
                    <span class="chart-meta">
                        μ={mcData.mu?.toFixed(2)} σ={mcData.vol?.toFixed(2)}
                        VaR={mcData.var_95?.toFixed(2)}
                    </span>
                {:else if mcData?.error}
                    <span class="chart-err">Julia 오프라인</span>
                {/if}
            </div>
            <canvas
                bind:this={mcCanvas}
                width="820"
                height="200"
                class="chart-canvas"
            ></canvas>
        </div>

        <!-- Vol Smile -->
        <div class="chart-box">
            <div class="chart-label">
                <span class="chart-title"
                    >Volatility Smile — IV곡선 (F# :9001)</span
                >
                {#if smileData && !smileData.error}
                    <span class="chart-meta">
                        ATM=100 · skew=-5% · {smileData.smile?.length}개 strike
                    </span>
                {:else if smileData?.error}
                    <span class="chart-err">F# 오프라인</span>
                {/if}
            </div>
            <canvas
                bind:this={smileCanvas}
                width="820"
                height="200"
                class="chart-canvas"
            ></canvas>
        </div>

        <!-- VaR Distribution -->
        <div class="chart-box">
            <div class="chart-label">
                <span class="chart-title"
                    >VaR 분포 히스토그램 (Rust :8081 risk_logs)</span
                >
                {#if varData && !varData.error}
                    <span class="chart-meta">
                        count={varData.count} avg={varData.avg_var?.toFixed(4)} p95={varData.p95_var?.toFixed(
                            4,
                        )}
                    </span>
                {:else if varData?.error}
                    <span class="chart-err">Rust 오프라인</span>
                {/if}
            </div>
            <canvas
                bind:this={varCanvas}
                width="820"
                height="200"
                class="chart-canvas"
            ></canvas>
        </div>
    </div>

    {#if !mcData && !smileData && !varData}
        <div class="placeholder">
            <span
                >「차트 갱신」을 눌러 Julia · F# · Rust 데이터를 가져옵니다</span
            >
        </div>
    {/if}
</section>

<style>
    .charts-panel {
        background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
        border: 1px solid #334155;
    }

    .chart-btn {
        background: #0ea5e9;
        color: white;
        border: none;
        padding: 0.6rem 1.4rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        white-space: nowrap;
        transition: opacity 0.2s;
    }
    .chart-btn:hover:not(:disabled) {
        opacity: 0.85;
    }
    .chart-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .charts-grid {
        display: flex;
        flex-direction: column;
        gap: 1rem;
    }

    .chart-box {
        background: #0f172a;
        border: 1px solid #1e293b;
        border-radius: 8px;
        padding: 0.75rem;
    }

    .chart-label {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 0.5rem;
    }

    .chart-title {
        font-size: 0.82rem;
        color: #94a3b8;
        font-weight: bold;
    }

    .chart-meta {
        font-size: 0.75rem;
        color: #64748b;
        font-family: monospace;
    }

    .chart-err {
        font-size: 0.75rem;
        color: #f87171;
    }

    .chart-canvas {
        display: block;
        width: 100%;
        height: auto;
        border-radius: 4px;
    }

    .placeholder {
        text-align: center;
        padding: 2rem;
        color: #475569;
        font-size: 0.9rem;
    }
</style>
