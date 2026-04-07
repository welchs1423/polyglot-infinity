<script>
    /** @type {any | null} */
    let dartData = $state(null);
    /** @type {boolean} */
    let dartLoading = $state(false);
    /** @type {any[] | null} */
    let scenarios = $state(null);
    let scenarioLoading = $state(false);
    let bondYears = $state(10);
    let bondCoupon = $state(0.05);

    async function runDart() {
        dartLoading = true;
        dartData = null;
        try {
            const [bondRes, ycRes] = await Promise.all([
                fetch(
                    "http://localhost:9005/api/dart/bond?face=1000&coupon=0.05&ytm=0.06&years=10",
                ),
                fetch("http://localhost:9005/api/dart/yieldcurve"),
            ]);
            if (bondRes.ok && ycRes.ok) {
                const bond = await bondRes.json();
                const yc = await ycRes.json();
                dartData = {
                    ...bond,
                    spread_10y_2y: yc.spread_10y_2y,
                    curve_shape: yc.curve_shape,
                    y2y: yc.yields[3],
                    y10y: yc.yields[7],
                };
            } else {
                dartData = { error: "Dart 엔진 오프라인" };
            }
        } catch {
            dartData = { error: "Dart 서버 접속 불가 (:9005)" };
        } finally {
            dartLoading = false;
        }
    }

    async function runScenarios() {
        scenarioLoading = true;
        scenarios = null;
        try {
            const ytmList = [0.03, 0.06, 0.1];
            const labels = ["Bull (YTM 3%)", "Base (YTM 6%)", "Bear (YTM 10%)"];
            const results = await Promise.all(
                ytmList.map((ytm) =>
                    fetch(
                        `http://localhost:9005/api/dart/bond?face=1000&coupon=${bondCoupon}&ytm=${ytm}&years=${bondYears}`,
                    ).then((r) => r.json()),
                ),
            );
            scenarios = results.map((r, i) => ({ ...r, label: labels[i] }));
        } catch {
            scenarios = [{ error: "Dart 서버 접속 불가 (:9005)" }];
        } finally {
            scenarioLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🎯 Dart (Yield Curve Engine)</h2>
            <p class="subtitle">
                Dart 3.11 · dart:io HttpServer · 채권 가격 · Nelson-Siegel
                수익률 곡선 (:9005)
            </p>
        </div>
        <button class="dart-btn" onclick={runDart} disabled={dartLoading}>
            {dartLoading ? "계산 중..." : "수익률 곡선"}
        </button>
    </div>
    {#if dartData}
        {#if dartData.error}
            <div class="empty-box">
                <p style="color:#f87171">{dartData.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card dart-card">
                    <span class="jlabel">Bond Price</span><span class="jval"
                        >{dartData.price?.toFixed(2)}</span
                    >
                </div>
                <div class="julia-card dart-card">
                    <span class="jlabel">Mod. Duration</span><span class="jval"
                        >{dartData.modified_duration?.toFixed(3)}</span
                    >
                </div>
                <div class="julia-card dart-card">
                    <span class="jlabel">Convexity</span><span class="jval"
                        >{dartData.convexity?.toFixed(3)}</span
                    >
                </div>
                <div class="julia-card dart-card">
                    <span class="jlabel">DV01</span><span class="jval"
                        >{dartData.dv01?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card dart-card">
                    <span class="jlabel">10Y-2Y Spread</span><span class="jval"
                        >{((dartData.spread_10y_2y ?? 0) * 100).toFixed(0)}bp ({dartData.curve_shape})</span
                    >
                </div>
                <div class="julia-card dart-card">
                    <span class="jlabel">2Y / 10Y Yield</span><span class="jval"
                        >{((dartData.y2y ?? 0) * 100).toFixed(2)}% / {(
                            (dartData.y10y ?? 0) * 100
                        ).toFixed(2)}%</span
                    >
                </div>
            </div>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Dart 채권 가격·듀레이션·볼록도와 Nelson-Siegel
                수익률 곡선 분석을 실행하세요. (Dart 서버 :9005 필요)
            </p>
        </div>
    {/if}

    <div class="scenario-section">
        <p class="scenario-label">YTM 시나리오 비교 (Bull / Base / Bear)</p>
        <div class="scenario-params">
            <label class="sc-field">
                <span>만기 (년)</span>
                <input
                    class="sc-input"
                    type="number"
                    bind:value={bondYears}
                    min="1"
                    max="30"
                />
            </label>
            <label class="sc-field">
                <span>쿠폰 (원 리틬)</span>
                <input
                    class="sc-input"
                    type="number"
                    bind:value={bondCoupon}
                    min="0.001"
                    max="0.20"
                    step="0.005"
                />
            </label>
            <button
                class="dart-btn sc-btn"
                onclick={runScenarios}
                disabled={scenarioLoading}
            >
                {scenarioLoading ? "분석 중..." : "시나리오 실행"}
            </button>
        </div>
        {#if scenarios}
            {#if scenarios[0]?.error}
                <p style="color:#f87171">{scenarios[0].error}</p>
            {:else}
                <div class="scenario-table">
                    <div class="sc-row sc-header">
                        <span>시나리오</span>
                        <span>가격</span>
                        <span>수정듀레이션</span>
                        <span>DV01</span>
                        <span>볼록도</span>
                    </div>
                    {#each scenarios as sc}
                        <div class="sc-row">
                            <span class="sc-name">{sc.label}</span>
                            <span
                                class="sc-price"
                                style="color:{sc.price >= 1000
                                    ? '#34d399'
                                    : '#f87171'}"
                            >
                                {sc.price?.toFixed(2)}
                            </span>
                            <span>{sc.modified_duration?.toFixed(3)}</span>
                            <span>{sc.dv01?.toFixed(4)}</span>
                            <span>{sc.convexity?.toFixed(2)}</span>
                        </div>
                    {/each}
                </div>
            {/if}
        {/if}
    </div>
</section>

<style>
    .dart-btn {
        background: linear-gradient(135deg, #0284c7, #075985);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .dart-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #0369a1, #0c4a6e);
    }
    .dart-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .dart-card {
        border-color: #0284c7 !important;
    }
    .scenario-section {
        margin-top: 1.5rem;
        border-top: 1px solid rgba(2, 132, 199, 0.25);
        padding-top: 1rem;
    }
    .scenario-label {
        font-size: 0.75rem;
        color: #0284c7;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        font-weight: 600;
        margin-bottom: 0.6rem;
    }
    .scenario-params {
        display: flex;
        gap: 0.75rem;
        flex-wrap: wrap;
        align-items: flex-end;
    }
    .sc-field {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        font-size: 0.75rem;
        color: #94a3b8;
        flex: 1;
        min-width: 100px;
    }
    .sc-input {
        background: rgba(2, 132, 199, 0.07);
        border: 1px solid rgba(2, 132, 199, 0.35);
        border-radius: 6px;
        color: #e2e8f0;
        font-size: 0.85rem;
        padding: 0.4rem 0.5rem;
        width: 100%;
        box-sizing: border-box;
    }
    .sc-input:focus {
        outline: none;
        border-color: #0284c7;
    }
    .sc-btn {
        padding: 0.5rem 1.1rem;
        font-size: 0.82rem;
    }
    .scenario-table {
        width: 100%;
        margin-top: 0.5rem;
        font-size: 0.82rem;
    }
    .sc-row {
        display: grid;
        grid-template-columns: 1.8fr 1fr 1.2fr 0.9fr 1fr;
        padding: 0.35rem 0.6rem;
        border-bottom: 1px solid rgba(2, 132, 199, 0.12);
    }
    .sc-row:last-child {
        border-bottom: none;
    }
    .sc-header {
        color: #0284c7;
        font-weight: 600;
        font-size: 0.72rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        background: rgba(2, 132, 199, 0.08);
        border-radius: 4px 4px 0 0;
    }
    .sc-name {
        color: #e2e8f0;
        font-weight: 600;
    }
    .sc-price {
        font-weight: 700;
    }
</style>
