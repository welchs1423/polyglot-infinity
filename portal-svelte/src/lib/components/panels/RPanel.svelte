<script>
    /** @type {any | null} */
    let rFit = $state(null);
    /** @type {any | null} */
    let rCorr = $state(null);
    /** @type {boolean} */
    let rLoading = $state(false);
    /** @type {boolean} */
    let corrLoading = $state(false);

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

    async function runRCorr() {
        corrLoading = true;
        rCorr = null;
        try {
            const res = await fetch("http://localhost:8003/api/r/correlation");
            if (res.ok) rCorr = await res.json();
            else rCorr = { error: "R engine offline" };
        } catch {
            rCorr = { error: "R engine unreachable" };
        } finally {
            corrLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>📊 R Stats Engine (:8003)</h2>
            <p class="subtitle">
                MLE 정규분포 피팅 · VaR/CVaR · 4-asset 상관분석 (Plumber)
            </p>
        </div>
        <div class="rbtn-group">
            <button class="r-btn" onclick={runRFit} disabled={rLoading}>
                {rLoading ? "분석 중..." : "분포 피팅"}
            </button>
            <button class="r-btn corr-btn" onclick={runRCorr} disabled={corrLoading}>
                {corrLoading ? "분석 중..." : "상관 분석"}
            </button>
        </div>
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
    {:else if !rCorr}
        <div class="empty-box">
            <p>분포 피팅 또는 상관 분석 버튼을 눌러주세요. (R Plumber :8003)</p>
        </div>
    {/if}

    <!-- 상관분석 결과 -->
    {#if rCorr}
        {#if rCorr.error}
            <div class="error-box"><p>⚠️ {rCorr.error}</p></div>
        {:else}
            <div class="corr-header">
                🔗 4-Asset 상관행렬 — 등가중 포트폴리오 연율 변동성: <strong style="color:#1d6fa5">{(rCorr.portfolio_vol_ann * 100).toFixed(4)}%</strong>
            </div>
            <div class="corr-table">
                <div class="corr-row header">
                    <span></span>
                    {#each rCorr.assets ?? [] as asset}
                        <span class="corr-asset">{asset}</span>
                    {/each}
                </div>
                {#each rCorr.assets ?? [] as rowAsset, ri}
                    <div class="corr-row">
                        <span class="corr-asset">{rowAsset}</span>
                        {#each rCorr.assets ?? [] as colAsset, ci}
                            {@const val = rCorr.correlation?.[rowAsset]?.[colAsset] ?? 0}
                            {@const abs = Math.abs(val)}
                            <span
                                class="corr-cell"
                                style="background:rgba(29,111,165,{ri===ci?0:abs*0.5});color:{ri===ci?'#94a3b8':val>0.5?'#34d399':val<-0.3?'#f87171':'#e2e8f0'}">
                                {ri === ci ? "1.000" : val.toFixed(3)}
                            </span>
                        {/each}
                    </div>
                {/each}
            </div>
        {/if}
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
    .rbtn-group { display: flex; gap: 0.5rem; flex-wrap: wrap; }
    .corr-btn { background: #0e7490; }
    .corr-btn:hover:not(:disabled) { background: #155e75; }
    .corr-header {
        font-size: 0.8rem;
        color: #94a3b8;
        margin: 0.6rem 0 0.4rem;
        border-top: 1px solid #1e293b;
        padding-top: 0.5rem;
    }
    .corr-table {
        display: flex;
        flex-direction: column;
        gap: 2px;
    }
    .corr-row {
        display: grid;
        grid-template-columns: 60px repeat(4, 1fr);
        gap: 2px;
    }
    .corr-row.header .corr-asset { color: #64748b; text-align: center; }
    .corr-asset {
        font-size: 0.75rem;
        font-weight: 700;
        color: #1d6fa5;
        display: flex;
        align-items: center;
    }
    .corr-cell {
        font-family: monospace;
        font-size: 0.78rem;
        text-align: center;
        padding: 0.3rem 0;
        border-radius: 4px;
    }
</style>
