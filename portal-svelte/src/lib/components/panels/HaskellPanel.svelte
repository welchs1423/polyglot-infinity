<script>
    /** @type {any | null} */
    let haskellData = $state(null);
    /** @type {boolean} */
    let haskellLoading = $state(false);

    async function runHaskell() {
        haskellLoading = true;
        haskellData = null;
        try {
            const [bsRes, mcRes, streamRes] = await Promise.all([
                fetch(
                    "http://localhost:8006/api/haskell/blackscholes?s=100&k=100&r=0.05&sigma=0.2&t=1",
                ),
                fetch(
                    "http://localhost:8006/api/haskell/montecarlo?s=100&vol=0.2&mu=0.08&n=500&days=252",
                ),
                fetch(
                    "http://localhost:8006/api/haskell/stream?s=100&mu=0.08&sigma=0.2&n=60&seed=42",
                ),
            ]);
            if (bsRes.ok && mcRes.ok && streamRes.ok) {
                const bs = await bsRes.json();
                const mc = await mcRes.json();
                const stream = await streamRes.json();
                haskellData = {
                    ...bs,
                    mc_annualized_return: mc.annualized_return,
                    mc_annualized_vol: mc.annualized_vol,
                    mc_var95: mc.var_95,
                    mc_cvar95: mc.cvar_95,
                    mc_avg_final: mc.avg_final_price,
                    stream_prices: stream.prices,
                    stream_ewma_vol: stream.ewma_vol,
                    stream_drawdowns: stream.drawdowns,
                    stream_final: stream.final_price,
                    stream_sharpe: stream.sharpe_ratio,
                    stream_mdd: stream.max_drawdown,
                    stream_n: stream.n,
                };
            } else {
                haskellData = { error: "Haskell 프라이서 오프라인" };
            }
        } catch {
            haskellData = { error: "Haskell 서버 접속 불가 (:8006)" };
        } finally {
            haskellLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>λ Haskell (Option Pricer)</h2>
            <p class="subtitle">
                GHC 8.8.4 · 순수 함수형 · Black-Scholes Greeks · GBM Monte Carlo
                · 무한 레이지 스트림 (:8006)
            </p>
        </div>
        <button
            class="haskell-btn"
            onclick={runHaskell}
            disabled={haskellLoading}
        >
            {haskellLoading ? "계산 중..." : "파생상품 계산"}
        </button>
    </div>
    {#if haskellData}
        {#if haskellData.error}
            <div class="empty-box">
                <p style="color:#f87171">{haskellData.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card haskell-card">
                    <span class="jlabel">Call Price</span><span class="jval"
                        >{haskellData.call_price?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card haskell-card">
                    <span class="jlabel">Put Price</span><span class="jval"
                        >{haskellData.put_price?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card haskell-card">
                    <span class="jlabel">Delta / Gamma</span><span class="jval"
                        >{haskellData.delta?.toFixed(4)} / {haskellData.gamma?.toFixed(
                            4,
                        )}</span
                    >
                </div>
                <div class="julia-card haskell-card">
                    <span class="jlabel">Vega / Theta</span><span class="jval"
                        >{haskellData.vega?.toFixed(4)} / {haskellData.theta_daily?.toFixed(
                            4,
                        )}</span
                    >
                </div>
                <div class="julia-card haskell-card">
                    <span class="jlabel">MC Ann. Return</span><span class="jval"
                        >{(
                            (haskellData.mc_annualized_return ?? 0) * 100
                        ).toFixed(2)}%</span
                    >
                </div>
                <div class="julia-card haskell-card">
                    <span class="jlabel">MC VaR 95%</span><span class="jval"
                        >{((haskellData.mc_var95 ?? 0) * 100).toFixed(2)}%</span
                    >
                </div>
            </div>
            {#if haskellData.stream_prices}
                <div class="stream-box">
                    <p class="stream-label">
                        ∞ 무한 레이지 GBM 스트림 — <code
                            >iterate/scanl/zipWith</code
                        >
                        — {haskellData.stream_n}틱 구체화
                    </p>
                    <div class="julia-grid">
                        <div class="julia-card haskell-card">
                            <span class="jlabel">Final Price</span><span
                                class="jval"
                                >{haskellData.stream_final?.toFixed(2)}</span
                            >
                        </div>
                        <div class="julia-card haskell-card">
                            <span class="jlabel">Sharpe (stream)</span><span
                                class="jval"
                                >{haskellData.stream_sharpe?.toFixed(3)}</span
                            >
                        </div>
                        <div class="julia-card haskell-card">
                            <span class="jlabel">Max Drawdown</span><span
                                class="jval"
                                >{((haskellData.stream_mdd ?? 0) * 100).toFixed(
                                    2,
                                )}%</span
                            >
                        </div>
                        <div class="julia-card haskell-card">
                            <span class="jlabel">EWMA Vol (last)</span><span
                                class="jval"
                                >{(
                                    (haskellData.stream_ewma_vol?.at(-1) ?? 0) *
                                    100
                                ).toFixed(3)}%</span
                            >
                        </div>
                    </div>
                    <p class="stream-prices">
                        {haskellData.stream_prices
                            ?.slice(0, 8)
                            .map((/** @type {number} */ p) => p.toFixed(2))
                            .join(" → ")} …
                    </p>
                </div>
            {/if}
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Haskell 순수 함수형 Black-Scholes Greeks와 GBM Monte
                Carlo 시뮬레이션을 실행하세요. (Haskell 서버 :8006 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .haskell-btn {
        background: linear-gradient(135deg, #7c3aed, #4c1d95);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .haskell-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #6d28d9, #3b0764);
    }
    .haskell-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .haskell-card {
        border-color: #7c3aed !important;
    }
    .stream-box {
        margin-top: 1rem;
        padding: 0.75rem 1rem;
        background: rgba(124, 58, 237, 0.07);
        border: 1px dashed #7c3aed;
        border-radius: 8px;
    }
    .stream-label {
        font-size: 0.8rem;
        color: #a78bfa;
        margin-bottom: 0.5rem;
    }
    .stream-label code {
        background: rgba(124, 58, 237, 0.15);
        padding: 0.1rem 0.3rem;
        border-radius: 3px;
        font-size: 0.78rem;
    }
    .stream-prices {
        margin-top: 0.5rem;
        font-size: 0.78rem;
        color: #c4b5fd;
        font-family: monospace;
        word-break: break-all;
    }
</style>
