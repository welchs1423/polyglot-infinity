<script>
    /** @type {any} */
    let wasmExports = null;
    /** @type {boolean} */
    let wasmLoaded = $state(false);
    /** @type {any | null} */
    let wasmBsResult = $state(null);
    /** @type {any | null} */
    let wasmMcResult = $state(null);
    /** @type {any | null} */
    let wasmPortResult = $state(null);
    /** @type {boolean} */
    let wasmLoading = $state(false);

    // MC 파라미터
    let mcS0 = $state(100);
    let mcMu = $state(0.08);
    let mcSigma = $state(0.2);
    let mcDays = $state(252);
    let mcPaths = $state(500);

    // 포트폴리오 파라미터
    let portVol1 = $state(0.2);
    let portVol2 = $state(0.15);
    let portCorr = $state(0.3);
    let portMu1 = $state(0.1);
    let portMu2 = $state(0.07);

    // DCF 파라미터
    let dcfFcf = $state(1_000_000);
    let dcfGrowth = $state(0.1);
    let dcfTerminal = $state(0.03);
    let dcfWacc = $state(0.08);
    let dcfYears = $state(5);
    /** @type {any | null} */
    let wasmDcfResult = $state(null);

    async function loadWasm() {
        if (!wasmExports) {
            const res = await fetch("/finance.wasm");
            const bytes = await res.arrayBuffer();
            const { instance } = await WebAssembly.instantiate(bytes, {});
            wasmExports = instance.exports;
            wasmLoaded = true;
        }
        return wasmExports;
    }

    async function runWasm() {
        wasmLoading = true;
        try {
            const exp = await loadWasm();
            wasmBsResult = {
                call: exp.bsCall(100, 100, 0.05, 0.2, 1.0),
                put: exp.bsPut(100, 100, 0.05, 0.2, 1.0),
                delta: exp.bsDelta(100, 100, 0.05, 0.2, 1.0),
                gamma: exp.bsGamma(100, 100, 0.05, 0.2, 1.0),
                theta: exp.bsTheta(100, 100, 0.05, 0.2, 1.0),
                vega: exp.bsVega(100, 100, 0.05, 0.2, 1.0),
                rho: exp.bsRho(100, 100, 0.05, 0.2, 1.0),
                var95: exp.varNormal(0.0005, 0.018, 0.95),
                dcf: exp.dcfValue(1_000_000, 0.1, 0.03, 0.08, 5),
            };
        } catch (e) {
            wasmBsResult = { error: String(e) };
        } finally {
            wasmLoading = false;
        }
    }

    async function runMcVaR() {
        wasmLoading = true;
        try {
            const exp = await loadWasm();
            const seed = BigInt(Math.floor(Math.random() * 0xffffffff) + 1);
            const var95 = exp.mcVaR95(
                seed,
                mcS0,
                mcMu,
                mcSigma,
                mcDays,
                mcPaths,
            );
            wasmMcResult = {
                var95_pct: (var95 * 100).toFixed(3),
                var95_abs: (var95 * mcS0).toFixed(2),
                s0: mcS0,
                mu: mcMu,
                sigma: mcSigma,
                days: mcDays,
                paths: mcPaths,
            };
        } catch (e) {
            wasmMcResult = { error: String(e) };
        } finally {
            wasmLoading = false;
        }
    }

    async function runPortfolio() {
        wasmLoading = true;
        try {
            const exp = await loadWasm();
            const wStar = exp.minVarWeight(portVol1, portVol2, portCorr);
            const sharpeStar = exp.portfolioSharpe(
                wStar,
                portMu1,
                portMu2,
                portVol1,
                portVol2,
                portCorr,
                0.03,
            );
            const sharpeEq = exp.portfolioSharpe(
                0.5,
                portMu1,
                portMu2,
                portVol1,
                portVol2,
                portCorr,
                0.03,
            );
            const portVarMV =
                wStar * wStar * portVol1 ** 2 +
                (1 - wStar) ** 2 * portVol2 ** 2 +
                2 * wStar * (1 - wStar) * portCorr * portVol1 * portVol2;
            wasmPortResult = {
                min_var_w1: (wStar * 100).toFixed(1),
                min_var_w2: ((1 - wStar) * 100).toFixed(1),
                min_var_vol: (
                    Math.sqrt(portVarMV) *
                    Math.sqrt(252) *
                    100
                ).toFixed(2),
                sharpe_mv: sharpeStar.toFixed(3),
                sharpe_eq: sharpeEq.toFixed(3),
            };
        } catch (e) {
            wasmPortResult = { error: String(e) };
        } finally {
            wasmLoading = false;
        }
    }

    async function runDcf() {
        wasmLoading = true;
        try {
            const exp = await loadWasm();
            const value = exp.dcfValue(
                dcfFcf,
                dcfGrowth,
                dcfTerminal,
                dcfWacc,
                dcfYears,
            );
            // 1단계별 PV 수동 계산 (시각화용)
            const steps = [];
            let cf = dcfFcf;
            let cumPv = 0;
            for (let y = 1; y <= dcfYears; y++) {
                cf *= 1 + dcfGrowth;
                const pv = cf / Math.pow(1 + dcfWacc, y);
                cumPv += pv;
                steps.push({ year: y, cf: Math.round(cf), pv: Math.round(pv) });
            }
            const lastCf = dcfFcf * Math.pow(1 + dcfGrowth, dcfYears);
            const tv = (lastCf * (1 + dcfTerminal)) / (dcfWacc - dcfTerminal);
            const tvPv = tv / Math.pow(1 + dcfWacc, dcfYears);
            wasmDcfResult = {
                intrinsic_value: Math.round(value),
                terminal_value_pv: Math.round(tvPv),
                operating_pv: Math.round(cumPv),
                steps,
                tv_pct: ((tvPv / value) * 100).toFixed(1),
            };
        } catch (e) {
            wasmDcfResult = { error: String(e) };
        } finally {
            wasmLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🕸️ WebAssembly (Client-side)</h2>
            <p class="subtitle">
                Zig → WASM32 · 브라우저 직접 실행 · 서버 왕복 없음
            </p>
        </div>
        <button class="wasm-btn" onclick={runWasm} disabled={wasmLoading}>
            {#if wasmLoading}계산 중...{:else if wasmLoaded}재계산{:else}WASM
                로드 & 실행{/if}
        </button>
    </div>

    {#if wasmBsResult}
        {#if wasmBsResult.error}
            <div class="empty-box">
                <p style="color:#f87171">{wasmBsResult.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card wasm-card">
                    <span class="jlabel">Call Price</span><span class="jval"
                        >${wasmBsResult.call.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Put Price</span><span class="jval"
                        >${wasmBsResult.put.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Delta</span><span class="jval"
                        >{wasmBsResult.delta.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Gamma</span><span class="jval"
                        >{wasmBsResult.gamma.toFixed(6)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Theta /day</span><span class="jval"
                        >{wasmBsResult.theta.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Vega /1%σ</span><span class="jval"
                        >{wasmBsResult.vega.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Rho /1%r</span><span class="jval"
                        >{wasmBsResult.rho.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">VaR 95%</span><span class="jval"
                        >{(wasmBsResult.var95 * 100).toFixed(3)}%</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">DCF Value</span><span class="jval"
                        >₩{Math.round(wasmBsResult.dcf).toLocaleString()}</span
                    >
                </div>
            </div>
            <p class="wasm-hint">
                ✓ 서버 없이 브라우저에서 직접 계산됨 (S=100 K=100 r=5% σ=20%
                T=1y)
            </p>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                Zig로 컴파일된 WASM을 브라우저에서 직접 실행합니다. 서버 없이
                Black-Scholes · VaR · DCF 계산.
            </p>
        </div>
    {/if}

    <!-- Monte Carlo VaR -->
    <div class="section-divider">📊 GBM Monte Carlo VaR (WASM)</div>
    <div class="param-grid">
        <div class="param-row">
            <label for="wasm-s0">S₀</label>
            <input
                id="wasm-s0"
                type="range"
                min="50"
                max="500"
                step="10"
                bind:value={mcS0}
            />
            <span class="param-val">{mcS0}</span>
        </div>
        <div class="param-row">
            <label for="wasm-mu">μ (연)</label>
            <input
                id="wasm-mu"
                type="range"
                min="0.01"
                max="0.30"
                step="0.01"
                bind:value={mcMu}
            />
            <span class="param-val">{(mcMu * 100).toFixed(0)}%</span>
        </div>
        <div class="param-row">
            <label for="wasm-sigma">σ (연)</label>
            <input
                id="wasm-sigma"
                type="range"
                min="0.05"
                max="0.60"
                step="0.01"
                bind:value={mcSigma}
            />
            <span class="param-val">{(mcSigma * 100).toFixed(0)}%</span>
        </div>
        <div class="param-row">
            <label for="wasm-paths">경로 수</label>
            <input
                id="wasm-paths"
                type="range"
                min="100"
                max="2000"
                step="100"
                bind:value={mcPaths}
            />
            <span class="param-val">{mcPaths}</span>
        </div>
    </div>
    <button
        class="wasm-btn"
        onclick={runMcVaR}
        disabled={wasmLoading}
        style="margin-top:0.5rem"
    >
        Monte Carlo 실행
    </button>
    {#if wasmMcResult}
        {#if wasmMcResult.error}
            <p style="color:#f87171">{wasmMcResult.error}</p>
        {:else}
            <div class="julia-grid" style="margin-top:0.75rem">
                <div class="julia-card wasm-card">
                    <span class="jlabel">VaR 95% (손실률)</span>
                    <span class="jval" style="color:#f87171"
                        >{wasmMcResult.var95_pct}%</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">VaR 95% (절대값)</span>
                    <span class="jval" style="color:#f87171"
                        >{wasmMcResult.var95_abs}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">경로 수</span>
                    <span class="jval">{wasmMcResult.paths}</span>
                </div>
            </div>
            <p class="wasm-hint">
                ✓ xorshift64 PRNG · 부분 선택정렬 5% 분위 · 순수 WASM
            </p>
        {/if}
    {/if}

    <!-- 포트폴리오 최적화 -->
    <div class="section-divider">⚖️ 최소분산 포트폴리오 (WASM)</div>
    <div class="param-grid">
        <div class="param-row">
            <label for="wasm-vol1">σ₁ (자산1)</label>
            <input
                id="wasm-vol1"
                type="range"
                min="0.05"
                max="0.60"
                step="0.01"
                bind:value={portVol1}
            />
            <span class="param-val">{(portVol1 * 100).toFixed(0)}%</span>
        </div>
        <div class="param-row">
            <label for="wasm-vol2">σ₂ (자산2)</label>
            <input
                id="wasm-vol2"
                type="range"
                min="0.05"
                max="0.60"
                step="0.01"
                bind:value={portVol2}
            />
            <span class="param-val">{(portVol2 * 100).toFixed(0)}%</span>
        </div>
        <div class="param-row">
            <label for="wasm-corr">상관계수 ρ</label>
            <input
                id="wasm-corr"
                type="range"
                min="-0.90"
                max="0.90"
                step="0.05"
                bind:value={portCorr}
            />
            <span class="param-val">{portCorr.toFixed(2)}</span>
        </div>
    </div>
    <button
        class="wasm-btn"
        onclick={runPortfolio}
        disabled={wasmLoading}
        style="margin-top:0.5rem"
    >
        포트폴리오 최적화
    </button>
    {#if wasmPortResult}
        {#if wasmPortResult.error}
            <p style="color:#f87171">{wasmPortResult.error}</p>
        {:else}
            <div class="julia-grid" style="margin-top:0.75rem">
                <div class="julia-card wasm-card">
                    <span class="jlabel">최적 비중 (자산1)</span>
                    <span class="jval">{wasmPortResult.min_var_w1}%</span>
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">최적 비중 (자산2)</span>
                    <span class="jval">{wasmPortResult.min_var_w2}%</span>
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">최소분산 연변동성</span>
                    <span class="jval" style="color:#34d399"
                        >{wasmPortResult.min_var_vol}%</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Sharpe (MV)</span>
                    <span class="jval">{wasmPortResult.sharpe_mv}</span>
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Sharpe (등가중)</span>
                    <span class="jval">{wasmPortResult.sharpe_eq}</span>
                </div>
            </div>
            <p class="wasm-hint">✓ 해석적 최솟값 공식 · 서버 왕복 없음</p>
        {/if}
    {/if}
    <!-- DCF 내재가치 계산기 -->
    <div class="section-divider">🏢 DCF 내재가치 (WASM)</div>
    <div class="param-grid">
        <div class="param-row">
            <label for="wasm-fcf">FCF (연간)</label>
            <input
                id="wasm-fcf"
                type="range"
                min="100000"
                max="10000000"
                step="100000"
                bind:value={dcfFcf}
            />
            <span class="param-val">₩{dcfFcf.toLocaleString()}</span>
        </div>
        <div class="param-row">
            <label for="wasm-growth">성장률 g</label>
            <input
                id="wasm-growth"
                type="range"
                min="0.00"
                max="0.30"
                step="0.01"
                bind:value={dcfGrowth}
            />
            <span class="param-val">{(dcfGrowth * 100).toFixed(0)}%</span>
        </div>
        <div class="param-row">
            <label for="wasm-terminal">잡리성장 g∞</label>
            <input
                id="wasm-terminal"
                type="range"
                min="0.01"
                max="0.05"
                step="0.005"
                bind:value={dcfTerminal}
            />
            <span class="param-val">{(dcfTerminal * 100).toFixed(1)}%</span>
        </div>
        <div class="param-row">
            <label for="wasm-wacc">WACC</label>
            <input
                id="wasm-wacc"
                type="range"
                min="0.03"
                max="0.20"
                step="0.005"
                bind:value={dcfWacc}
            />
            <span class="param-val">{(dcfWacc * 100).toFixed(1)}%</span>
        </div>
        <div class="param-row">
            <label for="wasm-years">예측기간</label>
            <input
                id="wasm-years"
                type="range"
                min="3"
                max="15"
                step="1"
                bind:value={dcfYears}
            />
            <span class="param-val">{dcfYears}년</span>
        </div>
    </div>
    <button
        class="wasm-btn"
        onclick={runDcf}
        disabled={wasmLoading}
        style="margin-top:0.5rem"
    >
        DCF 계산
    </button>
    {#if wasmDcfResult}
        {#if wasmDcfResult.error}
            <p style="color:#f87171">{wasmDcfResult.error}</p>
        {:else}
            <div class="julia-grid" style="margin-top:0.75rem">
                <div class="julia-card wasm-card" style="border-color:#f59e0b">
                    <span class="jlabel">내재가치 (DCF)</span>
                    <span class="jval" style="color:#f59e0b"
                        >₩{wasmDcfResult.intrinsic_value?.toLocaleString()}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">영업현금흐름 PV</span>
                    <span class="jval"
                        >₩{wasmDcfResult.operating_pv?.toLocaleString()}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">쟑리치 PV</span>
                    <span class="jval"
                        >₩{wasmDcfResult.terminal_value_pv?.toLocaleString()}</span
                    >
                </div>
                <div class="julia-card wasm-card" style="border-color:#a78bfa">
                    <span class="jlabel">쟑리치 비중</span>
                    <span class="jval" style="color:#a78bfa"
                        >{wasmDcfResult.tv_pct}%</span
                    >
                </div>
            </div>
            <div class="dcf-table">
                <div class="dcf-row dcf-head">
                    <span>연도</span><span>FCF</span><span>PV</span>
                </div>
                {#each wasmDcfResult.steps ?? [] as s}
                    <div class="dcf-row">
                        <span class="dcf-yr">Y{s.year}</span>
                        <span>₩{s.cf.toLocaleString()}</span>
                        <span style="color:#67e8f9"
                            >₩{s.pv.toLocaleString()}</span
                        >
                    </div>
                {/each}
            </div>
            <p class="wasm-hint">✓ 연도별 FCF 할인 · 쟑리수식 · 순수 WASM</p>
        {/if}
    {/if}
</section>

<style>
    .wasm-btn {
        background: linear-gradient(135deg, #06b6d4, #0e7490);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .wasm-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #0891b2, #065f6e);
    }
    .wasm-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .wasm-card {
        border-color: #06b6d4 !important;
    }
    .wasm-hint {
        margin-top: 0.75rem;
        font-size: 0.8rem;
        color: #67e8f9;
        text-align: center;
    }
    .section-divider {
        margin: 1.25rem 0 0.75rem;
        font-size: 0.85rem;
        font-weight: 600;
        color: #67e8f9;
        border-bottom: 1px solid rgba(6, 182, 212, 0.2);
        padding-bottom: 0.4rem;
    }
    .param-grid {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
    }
    .param-row {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.82rem;
    }
    .param-row label {
        width: 80px;
        color: #94a3b8;
        flex-shrink: 0;
    }
    .param-row input[type="range"] {
        flex: 1;
        accent-color: #06b6d4;
    }
    .param-val {
        width: 50px;
        text-align: right;
        color: #e2e8f0;
        font-size: 0.82rem;
    }
    .dcf-table {
        margin-top: 0.6rem;
        display: flex;
        flex-direction: column;
        gap: 2px;
        font-size: 0.78rem;
        font-family: monospace;
    }
    .dcf-row {
        display: grid;
        grid-template-columns: 36px 1fr 1fr;
        gap: 0.5rem;
        padding: 0.2rem 0.4rem;
        background: #0f172a;
        border-radius: 4px;
    }
    .dcf-head {
        color: #64748b;
        font-weight: 600;
        background: transparent;
    }
    .dcf-yr {
        color: #06b6d4;
    }
</style>
