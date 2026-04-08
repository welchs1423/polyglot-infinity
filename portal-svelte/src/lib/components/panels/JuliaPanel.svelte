<script>
    import { API_BASE } from '$lib/api';
    /** @type {any | null} */
    let juliaResult = $state(null);
    /** @type {any | null} */
    let stressResult = $state(null);
    /** @type {boolean} */
    let juliaLoading = $state(false);
    /** @type {boolean} */
    let stressLoading = $state(false);

    async function runJulia() {
        juliaLoading = true;
        juliaResult = null;
        try {
            const res = await fetch(
                `${API_BASE}/api/julia/simulate?paths=10000&days=252&vol=0.20&mu=0.05`,
            );
            if (res.ok) juliaResult = await res.json();
            else juliaResult = { error: "Julia engine offline" };
        } catch {
            juliaResult = { error: "Julia engine unreachable" };
        } finally {
            juliaLoading = false;
        }
    }

    async function runStress() {
        stressLoading = true;
        stressResult = null;
        try {
            const res = await fetch(
                `${API_BASE}/api/julia/stress?paths=5000&days=252`,
            );
            if (res.ok) stressResult = await res.json();
            else stressResult = { error: "Julia engine offline" };
        } catch {
            stressResult = { error: "Julia engine unreachable" };
        } finally {
            stressLoading = false;
        }
    }

    /** @type {Record<string, string>} */
    const SCENARIO_COLORS = {
        "Bull Market": "#34d399",
        "Bear Market": "#f87171",
        Crash: "#ef4444",
        "Flat/Low Vol": "#94a3b8",
    };
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🔬 Julia Engine (:8002)</h2>
            <p class="subtitle">
                GBM 몬테카를로 · 시나리오 스트레스 테스트 · Threads.@spawn 병렬
            </p>
        </div>
        <div class="jbtn-group">
            <button
                class="julia-btn"
                onclick={runJulia}
                disabled={juliaLoading}
            >
                {juliaLoading ? "분석 중..." : "시뮬레이션"}
            </button>
            <button
                class="julia-btn stress-btn"
                onclick={runStress}
                disabled={stressLoading}
            >
                {stressLoading ? "스트레스 중..." : "시나리오 스트레스"}
            </button>
        </div>
    </div>
    {#if juliaResult}
        <div class="julia-grid">
            <div class="julia-card">
                <span class="jlabel">VaR 95%</span><span class="jval"
                    >{(juliaResult.var_95 * 100).toFixed(2)}%</span
                >
            </div>
            <div class="julia-card">
                <span class="jlabel">CVaR 95%</span><span class="jval"
                    >{(juliaResult.cvar_95 * 100).toFixed(2)}%</span
                >
            </div>
            <div class="julia-card">
                <span class="jlabel">평균 수익</span><span class="jval"
                    >{(juliaResult.mean_return * 100).toFixed(2)}%</span
                >
            </div>
            <div class="julia-card">
                <span class="jlabel">변동성</span><span class="jval"
                    >{(juliaResult.std_return * 100).toFixed(2)}%</span
                >
            </div>
            <div class="julia-card">
                <span class="jlabel">샤프 비율</span><span class="jval"
                    >{juliaResult.sharpe.toFixed(3)}</span
                >
            </div>
            <div class="julia-card">
                <span class="jlabel">시뮬레이션 경로</span><span class="jval"
                    >{juliaResult.paths?.toLocaleString()}</span
                >
            </div>
        </div>
    {:else if !stressResult}
        <div class="empty-box">
            <p>
                버튼을 눌러 Julia GBM 몬테카를로 또는 시나리오 스트레스 테스트를
                실행하세요. (:8002)
            </p>
        </div>
    {/if}

    <!-- 스트레스 테스트 결과 -->
    {#if stressResult}
        {#if stressResult.error}
            <div class="empty-box" style="margin-top:0.5rem">
                <p style="color:#f87171">{stressResult.error}</p>
            </div>
        {:else}
            <div class="stress-header">
                📊 {stressResult.engine} — {stressResult.paths?.toLocaleString()}
                paths × {stressResult.days}일 · {stressResult.elapsed_ms}ms
            </div>
            <div class="stress-grid">
                {#each stressResult.scenarios ?? [] as sc}
                    {@const c = SCENARIO_COLORS[sc.scenario] ?? "#94a3b8"}
                    <div class="stress-card" style="border-color:{c}">
                        <div class="sc-name" style="color:{c}">
                            {sc.scenario}
                        </div>
                        <div class="sc-row">
                            <span>VaR 95%</span><span style="color:{c}"
                                >{(sc.var_95 * 100).toFixed(2)}%</span
                            >
                        </div>
                        <div class="sc-row">
                            <span>CVaR 95%</span><span
                                >{(sc.cvar_95 * 100).toFixed(2)}%</span
                            >
                        </div>
                        <div class="sc-row">
                            <span>최대 손실</span><span style="color:#f87171"
                                >{(sc.max_loss * 100).toFixed(2)}%</span
                            >
                        </div>
                        <div class="sc-row">
                            <span>Sharpe</span><span>{sc.sharpe}</span>
                        </div>
                    </div>
                {/each}
            </div>
        {/if}
    {/if}
</section>

<style>
    .julia-btn {
        background: #0d9488;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .julia-btn:hover:not(:disabled) {
        background: #0f766e;
    }
    .julia-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .stress-btn {
        background: #0891b2;
    }
    .stress-btn:hover:not(:disabled) {
        background: #0e7490;
    }
    .jbtn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
    }
    .stress-header {
        font-size: 0.78rem;
        color: #64748b;
        margin: 0.6rem 0 0.4rem;
        border-top: 1px solid #1e293b;
        padding-top: 0.5rem;
    }
    .stress-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
        gap: 0.5rem;
    }
    .stress-card {
        border: 1px solid #334155;
        border-left-width: 3px;
        border-radius: 8px;
        padding: 0.6rem 0.75rem;
        background: #0f172a;
    }
    .sc-name {
        font-weight: 700;
        font-size: 0.82rem;
        margin-bottom: 0.4rem;
    }
    .sc-row {
        display: flex;
        justify-content: space-between;
        font-size: 0.78rem;
        color: #94a3b8;
        margin-top: 0.15rem;
    }
    .sc-row > span:last-child {
        color: #e2e8f0;
        font-family: monospace;
    }
</style>
