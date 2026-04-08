<script>
    import { API_BASE } from '$lib/api';
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
                    `${API_BASE}/api/nim/timeseries?mu=0.10&sigma=0.20&n=252`,
                ),
                fetch(
                    `${API_BASE}/api/nim/momentum?mu=0.10&sigma=0.20&n=252`,
                ),
                fetch(`${API_BASE}/api/nim/indicators`),
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

    /** @type {any | null} */
    let nimGarch = $state(null);
    let nimGarchLoading = $state(false);
    /** @type {any | null} */
    let nimForecast = $state(null);
    let nimForecastLoading = $state(false);

    async function runNimGarch() {
        nimGarchLoading = true;
        nimGarch = null;
        try {
            const res = await fetch(
                `${API_BASE}/api/nim/garch?omega=0.00001&alpha=0.1&beta=0.85&n=500`,
            );
            if (res.ok) nimGarch = await res.json();
            else nimGarch = { error: "Nim GARCH offline" };
        } catch {
            nimGarch = { error: "Nim 서버 접속 불가 (:8005)" };
        } finally {
            nimGarchLoading = false;
        }
    }

    async function runNimForecast() {
        nimForecastLoading = true;
        nimForecast = null;
        try {
            const res = await fetch(
                `${API_BASE}/api/nim/forecast?mu=0.10&sigma=0.20&n=100&p=2`,
            );
            if (res.ok) nimForecast = await res.json();
            else nimForecast = { error: "Nim forecast offline" };
        } catch {
            nimForecast = { error: "Nim 서버 접속 불가 (:8005)" };
        } finally {
            nimForecastLoading = false;
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
        <div class="nim-btn-group">
            <button class="nim-btn" onclick={runNim} disabled={nimLoading}>
                {nimLoading ? "분석 중..." : "시계열 분석"}
            </button>
            <button
                class="nim-btn nim-garch-btn"
                onclick={runNimGarch}
                disabled={nimGarchLoading}
            >
                {nimGarchLoading ? "추정 중..." : "GARCH 시뮬"}
            </button>
            <button
                class="nim-btn nim-forecast-btn"
                onclick={runNimForecast}
                disabled={nimForecastLoading}
            >
                {nimForecastLoading ? "예측 중..." : "AR 예측"}
            </button>
        </div>
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

{#if nimGarch || nimGarchLoading}
    <section class="panel nim-extra-section">
        <h3 class="section-title">📈 Nim GARCH(1,1) 변동성 시뮬레이션</h3>
        {#if nimGarchLoading}
            <div class="empty-box"><p>GARCH 추정 중…</p></div>
        {:else if nimGarch?.error}
            <div class="error-box"><p>⚠️ {nimGarch.error}</p></div>
        {:else if nimGarch}
            <div class="julia-grid">
                <div class="julia-card nim-card">
                    <span class="jlabel">지속성 (α+β)</span><span class="jval"
                        >{nimGarch.persistence?.toFixed(4) ?? "N/A"}</span
                    >
                </div>
                <div class="julia-card nim-card">
                    <span class="jlabel">반감기 (일)</span><span class="jval"
                        >{nimGarch.half_life_days?.toFixed(1) ?? "N/A"}</span
                    >
                </div>
                <div class="julia-card nim-card">
                    <span class="jlabel">현재 연율 변동성</span><span
                        class="jval"
                        >{nimGarch.current_vol_ann != null
                            ? (nimGarch.current_vol_ann * 100).toFixed(2) + "%"
                            : "N/A"}</span
                    >
                </div>
            </div>
            {#if nimGarch.last_10_vols?.length}
                <div class="vol-strip">
                    <span class="vstrip-label">최근 10일 변동성:</span>
                    {#each nimGarch.last_10_vols as v}
                        <span class="vstrip-cell">{(v * 100).toFixed(2)}%</span>
                    {/each}
                </div>
            {/if}
        {/if}
    </section>
{/if}

{#if nimForecast || nimForecastLoading}
    <section class="panel nim-extra-section">
        <h3 class="section-title">
            📊 Nim AR({nimForecast?.order ?? 2}) 3-Step 예측
        </h3>
        {#if nimForecastLoading}
            <div class="empty-box"><p>AR 예측 중…</p></div>
        {:else if nimForecast?.error}
            <div class="error-box"><p>⚠️ {nimForecast.error}</p></div>
        {:else if nimForecast}
            <div class="julia-grid">
                {#each nimForecast.forecasts ?? [] as fc, i}
                    <div class="julia-card nim-card">
                        <span class="jlabel">예측 t+{i + 1}</span>
                        <span class="jval">{(fc * 100).toFixed(4)}%</span>
                    </div>
                {/each}
                {#if nimForecast.coefficients}
                    <div
                        class="julia-card nim-card"
                        style="border-color:#22d3ee"
                    >
                        <span class="jlabel">AR 계수 (φ₁)</span>
                        <span class="jval" style="color:#22d3ee"
                            >{nimForecast.coefficients[0]?.toFixed(4) ??
                                "N/A"}</span
                        >
                    </div>
                {/if}
            </div>
        {/if}
    </section>
{/if}

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
    .nim-btn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
    }
    .nim-garch-btn {
        background: linear-gradient(135deg, #7c3aed, #5b21b6);
    }
    .nim-garch-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #6d28d9, #4c1d95);
    }
    .nim-forecast-btn {
        background: linear-gradient(135deg, #b45309, #92400e);
    }
    .nim-forecast-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #92400e, #78350f);
    }
    .nim-extra-section {
        margin-top: 0.75rem;
    }
    .vol-strip {
        display: flex;
        flex-wrap: wrap;
        gap: 0.3rem;
        margin-top: 0.5rem;
        align-items: center;
    }
    .vstrip-label {
        font-size: 0.75rem;
        color: #64748b;
        margin-right: 0.3rem;
    }
    .vstrip-cell {
        font-family: monospace;
        font-size: 0.75rem;
        background: #1e293b;
        padding: 0.2rem 0.4rem;
        border-radius: 4px;
        color: #a78bfa;
    }
</style>
