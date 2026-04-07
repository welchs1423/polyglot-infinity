<script>
    /** @type {any | null} */
    let crystalData = $state(null);
    /** @type {boolean} */
    let crystalLoading = $state(false);

    async function runCrystal() {
        crystalLoading = true;
        crystalData = null;
        try {
            const [pfRes, fxRes, concRes] = await Promise.all([
                fetch(
                    "http://localhost:9002/api/crystal/portfolio?mu=0.12&sigma=0.18&days=252",
                ),
                fetch("http://localhost:9002/api/crystal/fx"),
                fetch("http://localhost:9002/api/crystal/concurrent"),
            ]);
            if (pfRes.ok && fxRes.ok) {
                const pf = await pfRes.json();
                const fx = await fxRes.json();
                const conc = concRes.ok ? await concRes.json() : null;
                crystalData = { ...pf, fx, conc };
            } else {
                crystalData = { error: "Crystal 게이트웨이 오프라인" };
            }
        } catch {
            crystalData = { error: "Crystal 서버 접속 불가 (:9002)" };
        } finally {
            crystalLoading = false;
        }
    }

    /** @type {any | null} */
    let crystalStats = $state(null);
    let statsLoading = $state(false);

    async function runCrystalStats() {
        statsLoading = true;
        crystalStats = null;
        try {
            const res = await fetch("http://localhost:9002/api/crystal/stats");
            if (res.ok) crystalStats = await res.json();
            else crystalStats = { error: "Crystal stats offline" };
        } catch {
            crystalStats = { error: "Crystal 서버 접속 불가 (:9002)" };
        } finally {
            statsLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🔮 Crystal (Portfolio Gateway)</h2>
            <p class="subtitle">
                Crystal 1.19 · Ruby 문법 + 네이티브 컴파일 · 포트폴리오 성과 +
                FX (:9002)
            </p>
        </div>
        <div class="crystal-btn-group">
            <button
                class="crystal-btn"
                onclick={runCrystal}
                disabled={crystalLoading}
            >
                {crystalLoading ? "분석 중..." : "포트폴리오 분석"}
            </button>
            <button
                class="crystal-btn crystal-stats-btn"
                onclick={runCrystalStats}
                disabled={statsLoading}
            >
                {statsLoading ? "복수 중..." : "FX 통계"}
            </button>
        </div>
    </div>
    {#if crystalData}
        {#if crystalData.error}
            <div class="empty-box">
                <p style="color:#f87171">{crystalData.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card crystal-card">
                    <span class="jlabel">Total Return</span>
                    <span class="jval"
                        >{(crystalData.total_return * 100).toFixed(2)}%</span
                    >
                </div>
                <div class="julia-card crystal-card">
                    <span class="jlabel">Sharpe Ratio</span>
                    <span class="jval"
                        >{crystalData.sharpe_ratio?.toFixed(4)}</span
                    >
                </div>
                {#if crystalData.fx}
                    <div
                        class="julia-card crystal-card"
                        style="border-color:#34d399"
                    >
                        <span class="jlabel">파이버 수집 시간</span>
                        <span class="jval" style="color:#34d399"
                            >{crystalData.fx.concurrent_total_ms}ms</span
                        >
                    </div>
                    <div
                        class="julia-card crystal-card"
                        style="border-color:#34d399"
                    >
                        <span class="jlabel">순차 시 예상</span>
                        <span class="jval"
                            >{crystalData.fx.sequential_would_be_ms}ms</span
                        >
                    </div>
                    <div
                        class="julia-card crystal-card"
                        style="border-color:#34d399"
                    >
                        <span class="jlabel">병렬 가속 배율</span>
                        <span class="jval" style="color:#34d399"
                            >{crystalData.fx.speedup_factor}x</span
                        >
                    </div>
                    <div
                        class="julia-card crystal-card"
                        style="border-color:#34d399"
                    >
                        <span class="jlabel">가중 평균 환율</span>
                        <span class="jval"
                            >₩{crystalData.fx.weighted_krw?.toLocaleString()}</span
                        >
                    </div>
                {/if}
            </div>

            <!-- /concurrent fiber sources -->
            {#if crystalData.conc?.sources?.length}
                <div class="fiber-header">
                    ⚡ {crystalData.conc.fiber_model} — {crystalData.conc
                        .sources.length}개 소스 병렬 수집
                </div>
                <div class="fiber-list">
                    {#each crystalData.conc.sources as src}
                        <div class="fiber-item">
                            <span class="fiber-name">{src.source}</span>
                            <span class="fiber-rate"
                                >₩{src.rate?.toLocaleString(undefined, {
                                    minimumFractionDigits: 2,
                                    maximumFractionDigits: 2,
                                })}</span
                            >
                            <span class="fiber-ms">{src.elapsed_ms}ms</span>
                        </div>
                    {/each}
                </div>
            {/if}
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Crystal spawn/Channel 파이버 병렬 FX 수집을
                확인하세요. (Crystal 서버 :9002 필요)
            </p>
        </div>
    {/if}
</section>

{#if crystalStats || statsLoading}
    <section class="panel crystal-stats-section">
        <h3 class="section-title">📊 Crystal FX 실시간 통계</h3>
        {#if statsLoading}
            <div class="empty-box"><p>FX 통계 복수 중…</p></div>
        {:else if crystalStats?.error}
            <div class="error-box"><p>⚠️ {crystalStats.error}</p></div>
        {:else if crystalStats}
            <div class="julia-grid">
                <div class="julia-card crystal-card">
                    <span class="jlabel">평균 (mean)</span>
                    <span class="jval"
                        >₩{crystalStats.mean?.toLocaleString(undefined, {
                            minimumFractionDigits: 2,
                            maximumFractionDigits: 2,
                        }) ?? "N/A"}</span
                    >
                </div>
                <div class="julia-card crystal-card">
                    <span class="jlabel">표준편차 (σ)</span>
                    <span class="jval"
                        >{crystalStats.std_dev?.toFixed(4) ?? "N/A"}</span
                    >
                </div>
                <div class="julia-card crystal-card">
                    <span class="jlabel">최소</span>
                    <span class="jval"
                        >₩{crystalStats.min?.toLocaleString(undefined, {
                            minimumFractionDigits: 2,
                            maximumFractionDigits: 2,
                        }) ?? "N/A"}</span
                    >
                </div>
                <div class="julia-card crystal-card">
                    <span class="jlabel">최대</span>
                    <span class="jval"
                        >₩{crystalStats.max?.toLocaleString(undefined, {
                            minimumFractionDigits: 2,
                            maximumFractionDigits: 2,
                        }) ?? "N/A"}</span
                    >
                </div>
                <div
                    class="julia-card crystal-card"
                    style="border-color:#f59e0b"
                >
                    <span class="jlabel">스프레드 (bps)</span>
                    <span class="jval" style="color:#f59e0b"
                        >{crystalStats.spread_bps?.toFixed(1) ?? "N/A"} bps</span
                    >
                </div>
                <div
                    class="julia-card crystal-card"
                    style="border-color:#34d399"
                >
                    <span class="jlabel">가중평균율</span>
                    <span class="jval" style="color:#34d399"
                        >₩{crystalStats.weighted_avg?.toLocaleString(
                            undefined,
                            {
                                minimumFractionDigits: 2,
                                maximumFractionDigits: 2,
                            },
                        ) ?? "N/A"}</span
                    >
                </div>
            </div>
        {/if}
    </section>
{/if}

<style>
    .crystal-btn {
        background: linear-gradient(135deg, #a855f7, #7c3aed);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .crystal-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #9333ea, #6d28d9);
    }
    .crystal-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .crystal-card {
        border-color: #a855f7 !important;
    }
    .fiber-header {
        font-size: 0.78rem;
        color: #94a3b8;
        margin: 0.6rem 0 0.3rem;
        font-weight: 600;
    }
    .fiber-list {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
    }
    .fiber-item {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        font-size: 0.8rem;
        font-family: monospace;
        padding: 0.25rem 0.5rem;
        background: #0f172a;
        border: 1px solid #1e293b;
        border-radius: 5px;
    }
    .fiber-name {
        color: #a855f7;
        min-width: 80px;
    }
    .fiber-rate {
        color: #e2e8f0;
        flex: 1;
    }
    .fiber-ms {
        color: #38bdf8;
    }
    .crystal-btn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
    }
    .crystal-stats-btn {
        background: linear-gradient(135deg, #f59e0b, #d97706);
    }
    .crystal-stats-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #d97706, #b45309);
    }
    .crystal-stats-section {
        margin-top: 0.75rem;
    }
</style>
