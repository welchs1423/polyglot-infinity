<script>
    /** @type {"option" | "iv" | "smile" | "dcf"} */
    let activeTab = $state("option");

    /** @type {any | null} */
    let fsharpOption = $state(null);
    /** @type {any | null} */
    let fsharpIV = $state(null);
    /** @type {any | null} */
    let fsharpSmile = $state(null);
    /** @type {any | null} */
    let fsharpDCF = $state(null);
    /** @type {boolean} */
    let fsharpLoading = $state(false);

    async function runFsharpOption() {
        fsharpLoading = true;
        fsharpOption = null;
        try {
            const res = await fetch(
                "http://localhost:9001/api/fsharp/option?s=100&k=100&r=0.05&sigma=0.20&t=1.0",
            );
            if (res.ok) fsharpOption = await res.json();
            else fsharpOption = { error: "F# pricer offline" };
        } catch {
            fsharpOption = { error: "F# pricer unreachable" };
        } finally {
            fsharpLoading = false;
        }
    }

    async function runFsharpIV() {
        fsharpLoading = true;
        fsharpIV = null;
        try {
            // market_price ≈ BS Call at σ=0.20 (≈10.45)
            const res = await fetch(
                "http://localhost:9001/api/fsharp/iv?market_price=10.45&s=100&k=100&r=0.05&t=1.0&type=call",
            );
            if (res.ok) fsharpIV = await res.json();
            else fsharpIV = { error: "F# pricer offline" };
        } catch {
            fsharpIV = { error: "F# pricer unreachable" };
        } finally {
            fsharpLoading = false;
        }
    }

    async function runFsharpSmile() {
        fsharpLoading = true;
        fsharpSmile = null;
        try {
            const res = await fetch(
                "http://localhost:9001/api/fsharp/smile?s=100&r=0.05&t=1.0&k_min=80&k_max=120&steps=9&atm_vol=0.20&skew=-0.05&curvature=0.10&type=call",
            );
            if (res.ok) fsharpSmile = await res.json();
            else fsharpSmile = { error: "F# pricer offline" };
        } catch {
            fsharpSmile = { error: "F# pricer unreachable" };
        } finally {
            fsharpLoading = false;
        }
    }

    async function runFsharpDCF() {
        fsharpLoading = true;
        fsharpDCF = null;
        try {
            const res = await fetch("http://localhost:9001/api/fsharp/dcf");
            if (res.ok) fsharpDCF = await res.json();
            else fsharpDCF = { error: "F# pricer offline" };
        } catch {
            fsharpDCF = { error: "F# pricer unreachable" };
        } finally {
            fsharpLoading = false;
        }
    }

    const TABS = [
        { id: "option", label: "Greeks", run: () => runFsharpOption() },
        { id: "iv", label: "내재변동성", run: () => runFsharpIV() },
        { id: "smile", label: "Vol Smile", run: () => runFsharpSmile() },
        { id: "dcf", label: "DCF", run: () => runFsharpDCF() },
    ];

    function switchTab(/** @type {"option"|"iv"|"smile"|"dcf"} */ id) {
        activeTab = id;
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🤖 F# Pricer (.NET 8 · :9001)</h2>
            <p class="subtitle">
                Black-Scholes · 내재변동성(Newton-Raphson) · Vol Smile · DCF
            </p>
        </div>
        <button
            class="fsharp-btn"
            onclick={TABS.find((t) => t.id === activeTab)?.run}
            disabled={fsharpLoading}
        >
            {fsharpLoading
                ? "계산 중..."
                : TABS.find((t) => t.id === activeTab)?.label + " 실행"}
        </button>
    </div>

    <!-- 탭 -->
    <div class="tab-bar">
        {#each TABS as tab}
            <button
                class="tab-btn {activeTab === tab.id ? 'active' : ''}"
                onclick={() => switchTab(/** @type {any} */ (tab.id))}
                >{tab.label}</button
            >
        {/each}
    </div>

    <!-- Greeks 탭 -->
    {#if activeTab === "option"}
        {#if fsharpOption && !fsharpOption.error}
            <div class="julia-grid">
                <div class="julia-card fsharp-card">
                    <span class="jlabel">Call Price</span><span class="jval"
                        >${fsharpOption.call_price}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">Put Price</span><span class="jval"
                        >${fsharpOption.put_price}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">Δ Delta</span><span class="jval"
                        >{fsharpOption.delta_call}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">Γ Gamma</span><span class="jval"
                        >{fsharpOption.gamma}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">ν Vega</span><span class="jval"
                        >{fsharpOption.vega}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">Θ Theta/day</span><span class="jval"
                        >{fsharpOption.theta_call}</span
                    >
                </div>
            </div>
        {:else if fsharpOption?.error}
            <div class="error-box">
                <p>
                    ⚠️ {fsharpOption.error} —
                    <code>dotnet run --project pricer-fsharp</code>
                </p>
            </div>
        {:else}
            <div class="empty-box">
                <p>Greeks 실행 버튼을 눌러 ATM 옵션 Greeks를 계산하세요.</p>
            </div>
        {/if}
    {/if}

    <!-- 내재변동성 탭 -->
    {#if activeTab === "iv"}
        {#if fsharpIV && !fsharpIV.error}
            <div class="julia-grid">
                <div class="julia-card fsharp-card">
                    <span class="jlabel">내재변동성 (IV)</span><span
                        class="jval"
                        >{(fsharpIV.implied_vol * 100).toFixed(4)}%</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">시장가 입력</span><span class="jval"
                        >${fsharpIV.market_price}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">BS 재현가</span><span class="jval"
                        >${fsharpIV.bs_price?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">수렴 반복</span><span class="jval"
                        >{fsharpIV.iterations}회</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">잔차</span><span class="jval"
                        >{fsharpIV.residual?.toExponential(2)}</span
                    >
                </div>
                <div
                    class="julia-card fsharp-card"
                    style="border-color:#34d399"
                >
                    <span class="jlabel">엔진</span><span
                        class="jval"
                        style="color:#34d399">{fsharpIV.engine}</span
                    >
                </div>
            </div>
        {:else if fsharpIV?.error}
            <div class="error-box"><p>⚠️ {fsharpIV.error}</p></div>
        {:else}
            <div class="empty-box">
                <p>
                    내재변동성 실행 버튼을 눌러 Newton-Raphson IV를 계산하세요.
                </p>
            </div>
        {/if}
    {/if}

    <!-- Vol Smile 탭 -->
    {#if activeTab === "smile"}
        {#if fsharpSmile && !fsharpSmile.error}
            {@const points = fsharpSmile.smile ?? []}
            <div class="smile-table">
                <div class="smile-header">
                    <span>Strike</span><span>σ 모형</span><span>BS Call</span
                    ><span>IV 역산</span>
                </div>
                {#each points as pt}
                    <div class="smile-row">
                        <span>{pt.strike}</span>
                        <span>{(pt.model_vol * 100).toFixed(2)}%</span>
                        <span>${pt.bs_price?.toFixed(3)}</span>
                        <span class:iv-atm={Math.abs(pt.strike - 100) < 1}
                            >{(pt.implied_vol * 100).toFixed(2)}%</span
                        >
                    </div>
                {/each}
            </div>
            <p class="clj-note">
                skew={fsharpSmile.skew} · curvature={fsharpSmile.curvature} · {fsharpSmile.engine}
            </p>
        {:else if fsharpSmile?.error}
            <div class="error-box"><p>⚠️ {fsharpSmile.error}</p></div>
        {:else}
            <div class="empty-box">
                <p>
                    Vol Smile 실행 버튼을 눌러 변동성 스마일 곡선을 계산하세요.
                </p>
            </div>
        {/if}
    {/if}

    <!-- DCF 탭 -->
    {#if activeTab === "dcf"}
        {#if fsharpDCF && !fsharpDCF.error}
            <div class="julia-grid">
                <div class="julia-card fsharp-card">
                    <span class="jlabel">내재가치 (DCF)</span><span class="jval"
                        >${Number(
                            fsharpDCF.intrinsic_value,
                        ).toLocaleString()}</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">할인율</span><span class="jval"
                        >{(fsharpDCF.discount_rate * 100).toFixed(1)}%</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">현금흐름 기간</span><span class="jval"
                        >{fsharpDCF.periods}년</span
                    >
                </div>
                <div class="julia-card fsharp-card">
                    <span class="jlabel">터미널 밸류</span><span class="jval"
                        >${Number(
                            fsharpDCF.terminal_value,
                        ).toLocaleString()}</span
                    >
                </div>
                {#if fsharpDCF.pv_cashflows}
                    <div class="julia-card fsharp-card">
                        <span class="jlabel">PV(FCF 합계)</span><span
                            class="jval"
                            >${Number(
                                fsharpDCF.pv_cashflows,
                            ).toLocaleString()}</span
                        >
                    </div>
                {/if}
                <div
                    class="julia-card fsharp-card"
                    style="border-color:#34d399"
                >
                    <span class="jlabel">엔진</span><span
                        class="jval"
                        style="color:#34d399">{fsharpDCF.engine}</span
                    >
                </div>
            </div>
        {:else if fsharpDCF?.error}
            <div class="error-box"><p>⚠️ {fsharpDCF.error}</p></div>
        {:else}
            <div class="empty-box">
                <p>DCF 실행 버튼을 눌러 현금흐름 할인 기업가치를 계산하세요.</p>
            </div>
        {/if}
    {/if}
</section>

<style>
    .fsharp-btn {
        background: #512bd4;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .fsharp-btn:hover:not(:disabled) {
        background: #3d1fa0;
    }
    .fsharp-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .fsharp-card {
        border-color: #512bd4 !important;
    }

    .tab-bar {
        display: flex;
        gap: 0.4rem;
        margin-bottom: 0.75rem;
        flex-wrap: wrap;
    }
    .tab-btn {
        background: #1e293b;
        color: #94a3b8;
        border: 1px solid #334155;
        border-radius: 6px;
        padding: 0.3rem 0.9rem;
        font-size: 0.82rem;
        cursor: pointer;
        transition: all 0.15s;
    }
    .tab-btn:hover {
        color: #e2e8f0;
        border-color: #512bd4;
    }
    .tab-btn.active {
        background: #512bd4;
        color: white;
        border-color: #512bd4;
    }

    .smile-table {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 0;
        border: 1px solid #1e293b;
        border-radius: 8px;
        overflow: hidden;
        font-size: 0.8rem;
        font-family: monospace;
        margin-bottom: 0.5rem;
    }
    .smile-header {
        display: contents;
    }
    .smile-header > span {
        background: #1e293b;
        color: #94a3b8;
        padding: 0.35rem 0.6rem;
        font-weight: 700;
    }
    .smile-row {
        display: contents;
    }
    .smile-row > span {
        padding: 0.3rem 0.6rem;
        color: #e2e8f0;
        border-top: 1px solid #1e293b;
    }
    .smile-row > span.iv-atm {
        color: #a78bfa;
        font-weight: 700;
    }
    .clj-note {
        font-size: 0.75rem;
        color: #64748b;
        font-style: italic;
    }
</style>
