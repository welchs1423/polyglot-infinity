<script>
    /** @type {any | null} */
    let dartData = $state(null);
    /** @type {boolean} */
    let dartLoading = $state(false);

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
</style>
