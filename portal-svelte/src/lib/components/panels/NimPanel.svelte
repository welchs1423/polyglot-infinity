<script>
    /** @type {any | null} */
    let nimData = $state(null);
    /** @type {boolean} */
    let nimLoading = $state(false);

    async function runNim() {
        nimLoading = true;
        nimData = null;
        try {
            const [tsRes, momRes, indRes] = await Promise.all([
                fetch(
                    "http://localhost:8005/api/nim/timeseries?mu=0.10&sigma=0.20&n=252",
                ),
                fetch(
                    "http://localhost:8005/api/nim/momentum?mu=0.10&sigma=0.20&n=252",
                ),
                fetch("http://localhost:8005/api/nim/indicators"),
            ]);
            if (tsRes.ok && momRes.ok && indRes.ok) {
                const ts = await tsRes.json();
                const mom = await momRes.json();
                const ind = await indRes.json();
                nimData = {
                    ...ts,
                    rsi_14: mom.rsi_14,
                    macd: mom.macd,
                    bb_width: mom.bb_width,
                    bb_position: mom.bb_position,
                    precomputed_alpha_periods: ind.precomputed_ema_periods,
                    runtime_divisions: ind.runtime_divisions,
                };
            } else {
                nimData = { error: "Nim 엔진 오프라인" };
            }
        } catch {
            nimData = { error: "Nim 서버 접속 불가 (:8005)" };
        } finally {
            nimLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>💎 Nim (Time-series Analytics)</h2>
            <p class="subtitle">
                Nim 2.2.8 · Python 문법 + C 속도 · 시계열 기술통계 + 모멘텀 지표
                (:8005)
            </p>
        </div>
        <button class="nim-btn" onclick={runNim} disabled={nimLoading}>
            {nimLoading ? "분석 중..." : "시계열 분석"}
        </button>
    </div>
    {#if nimData}
        {#if nimData.error}
            <div class="empty-box">
                <p style="color:#f87171">{nimData.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card nim-card">
                    <span class="jlabel">Ann. Return</span>
                    <span class="jval"
                        >{(nimData.annualized_return * 100).toFixed(2)}%</span
                    >
                </div>
                <div class="julia-card nim-card">
                    <span class="jlabel">Skewness / Kurtosis</span>
                    <span class="jval"
                        >{nimData.skewness?.toFixed(3)} / {nimData.excess_kurtosis?.toFixed(
                            3,
                        )}</span
                    >
                </div>
                <div class="julia-card nim-card">
                    <span class="jlabel">RSI (14)</span>
                    <span class="jval">{nimData.rsi_14?.toFixed(2)}</span>
                </div>
                <div class="julia-card nim-card">
                    <span class="jlabel">MACD</span>
                    <span class="jval">{nimData.macd?.toFixed(4)}</span>
                </div>
                <div class="julia-card nim-card" style="border-color:#22d3ee">
                    <span class="jlabel">사전계산 α 계수</span>
                    <span class="jval" style="color:#22d3ee"
                        >{nimData.precomputed_alpha_periods ?? 199}개</span
                    >
                </div>
                <div class="julia-card nim-card" style="border-color:#22d3ee">
                    <span class="jlabel">런타임 나눗셈</span>
                    <span class="jval" style="color:#22d3ee"
                        >{nimData.runtime_divisions ?? 0}회</span
                    >
                </div>
            </div>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Nim 기술통계 + 컴파일타임 EMA 계수 테이블 정보를
                확인하세요. (Nim 서버 :8005 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .nim-btn {
        background: linear-gradient(135deg, #10b981, #047857);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .nim-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #059669, #065f46);
    }
    .nim-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .nim-card {
        border-color: #10b981 !important;
    }
</style>
