<script>
    /** @type {any | null} */
    let rFit = $state(null);
    /** @type {boolean} */
    let rLoading = $state(false);

    async function runRFit() {
        rLoading = true;
        rFit = null;
        try {
            const res = await fetch("http://localhost:8003/api/r/fit?n=1000");
            if (res.ok) rFit = await res.json();
            else rFit = { error: "R engine offline" };
        } catch {
            rFit = { error: "R engine unreachable" };
        } finally {
            rLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>📊 R Distribution Fit</h2>
            <p class="subtitle">
                MLE 정규분포 피팅 · VaR/CVaR · Sharpe (Plumber :8003)
            </p>
        </div>
        <button class="r-btn" onclick={runRFit} disabled={rLoading}>
            {rLoading ? "분석 중..." : "분포 피팅"}
        </button>
    </div>
    {#if rFit && !rFit.error}
        <div class="julia-grid">
            <div class="julia-card r-card">
                <span class="jlabel">정규 평균 μ</span><span class="jval"
                    >{(rFit.fit_normal.mean * 100).toFixed(4)}%</span
                >
            </div>
            <div class="julia-card r-card">
                <span class="jlabel">정규 표준편차 σ</span><span class="jval"
                    >{(rFit.fit_normal.sd * 100).toFixed(4)}%</span
                >
            </div>
            <div class="julia-card r-card">
                <span class="jlabel">t분포 자유도</span><span class="jval"
                    >{rFit.fit_t_df ?? "N/A"}</span
                >
            </div>
            <div class="julia-card r-card">
                <span class="jlabel">VaR 95%</span><span class="jval"
                    >{(rFit.var_95 * 100).toFixed(3)}%</span
                >
            </div>
            <div class="julia-card r-card">
                <span class="jlabel">CVaR 95%</span><span class="jval"
                    >{(rFit.cvar_95 * 100).toFixed(3)}%</span
                >
            </div>
            <div class="julia-card r-card">
                <span class="jlabel">Sharpe (연율)</span><span class="jval"
                    >{rFit.sharpe_ratio}</span
                >
            </div>
        </div>
    {:else if rFit?.error}
        <div class="error-box">
            <p>⚠️ {rFit.error} — Rscript engine-r/run.R 으로 실행하세요.</p>
        </div>
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 R MLE 분포 피팅을 실행하세요. (R Plumber 서버 :8003
                필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .r-btn {
        background: #1d6fa5;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .r-btn:hover:not(:disabled) {
        background: #155881;
    }
    .r-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .r-card {
        border-color: #1d6fa5 !important;
    }
</style>
