<script>
    /** @type {any | null} */
    let juliaResult = $state(null);
    /** @type {boolean} */
    let juliaLoading = $state(false);

    async function runJulia() {
        juliaLoading = true;
        juliaResult = null;
        try {
            const res = await fetch(
                "http://localhost:8002/api/julia/simulate?paths=10000&days=252&vol=0.20&mu=0.05",
            );
            if (res.ok) juliaResult = await res.json();
            else juliaResult = { error: "Julia engine offline" };
        } catch {
            juliaResult = { error: "Julia engine unreachable" };
        } finally {
            juliaLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🔬 Julia Monte Carlo</h2>
            <p class="subtitle">GBM 기반 병렬 시뮬레이션 · VaR/CVaR 95%</p>
        </div>
        <button class="julia-btn" onclick={runJulia} disabled={juliaLoading}>
            {juliaLoading ? "분석 중..." : "시뮬레이션"}
        </button>
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
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Julia GBM 몬테카를로 분석을 실행하세요. (Julia 서버
                :8002 필요)
            </p>
        </div>
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
</style>
