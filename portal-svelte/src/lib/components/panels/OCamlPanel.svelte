<script>
    /** @type {any | null} */
    let ocamlRisk = $state(null);
    /** @type {boolean} */
    let ocamlLoading = $state(false);
    /** @type {any | null} */
    let scoreData = $state(null);
    let scoreLoading = $state(false);
    let income = $state(5000000);
    let debt = $state(2000000);
    let historyYears = $state(3);
    let missedPayments = $state(1);

    async function runOcamlRisk() {
        ocamlLoading = true;
        ocamlRisk = null;
        try {
            const [riskRes, scoreRes] = await Promise.all([
                fetch(
                    "http://localhost:8004/api/ocaml/risk?debt_ratio=0.75&volatility=0.28&leverage=3.5&credit_score=650",
                ),
                fetch(
                    "http://localhost:8004/api/ocaml/score?income=5000000&debt=2000000&history_years=3&missed_payments=1",
                ),
            ]);
            if (riskRes.ok && scoreRes.ok) {
                const risk = await riskRes.json();
                const score = await scoreRes.json();
                ocamlRisk = {
                    ...risk,
                    credit_grade: score.grade,
                    credit_score_model: score.score,
                    prob_good: score.prob_good,
                };
            } else {
                ocamlRisk = { error: "OCaml 리스크 엔진 오프라인" };
            }
        } catch {
            ocamlRisk = { error: "OCaml 엔진 접속 불가 (:8004)" };
        } finally {
            ocamlLoading = false;
        }
    }

    async function fetchScore() {
        scoreLoading = true;
        scoreData = null;
        try {
            const url = `http://localhost:8004/api/ocaml/score?income=${income}&debt=${debt}&history_years=${historyYears}&missed_payments=${missedPayments}`;
            const res = await fetch(url);
            if (res.ok) scoreData = await res.json();
            else scoreData = { error: "OCaml 스코어 오프라인" };
        } catch {
            scoreData = { error: "OCaml 엔진 접속 불가 (:8004)" };
        } finally {
            scoreLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🐪 OCaml (Risk Rule Engine)</h2>
            <p class="subtitle">
                OCaml 4.13 · 규칙 기반 리스크 판정 · 신용 스코어링 (:8004)
            </p>
        </div>
        <button
            class="ocaml-btn"
            onclick={runOcamlRisk}
            disabled={ocamlLoading}
        >
            {ocamlLoading ? "분석 중..." : "리스크 분석"}
        </button>
    </div>
    {#if ocamlRisk}
        {#if ocamlRisk.error}
            <div class="empty-box">
                <p style="color:#f87171">{ocamlRisk.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card ocaml-card">
                    <span class="jlabel">Risk Level</span><span
                        class="jval risk-{ocamlRisk.level?.toLowerCase()}"
                        >{ocamlRisk.level}</span
                    >
                </div>
                <div class="julia-card ocaml-card">
                    <span class="jlabel">Risk Score</span><span class="jval"
                        >{ocamlRisk.risk_score} / 100</span
                    >
                </div>
                <div class="julia-card ocaml-card">
                    <span class="jlabel">Credit Score</span><span class="jval"
                        >{ocamlRisk.credit_score_model}</span
                    >
                </div>
                <div class="julia-card ocaml-card">
                    <span class="jlabel">Credit Grade</span><span class="jval"
                        >{ocamlRisk.credit_grade}</span
                    >
                </div>
                <div class="julia-card ocaml-card">
                    <span class="jlabel">Debt Ratio</span><span class="jval"
                        >{(ocamlRisk.debt_ratio * 100).toFixed(1)}%</span
                    >
                </div>
                <div class="julia-card ocaml-card">
                    <span class="jlabel">Volatility</span><span class="jval"
                        >{(ocamlRisk.volatility * 100).toFixed(1)}%</span
                    >
                </div>
            </div>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 OCaml 규칙 기반 리스크 판정 · 신용 스코어링을
                실행하세요. (OCaml 서버 :8004 필요)
            </p>
        </div>
    {/if}

    <div class="score-section">
        <p class="score-label">신용 스코어 실시간 산정</p>
        <div class="score-form">
            <label class="sf-field">
                <span>연소득 (원)</span>
                <input class="sf-input" type="number" bind:value={income} min="100000" step="100000" />
            </label>
            <label class="sf-field">
                <span>부체 (원)</span>
                <input class="sf-input" type="number" bind:value={debt} min="0" step="100000" />
            </label>
            <label class="sf-field">
                <span>신용이력 (년)</span>
                <input class="sf-input" type="number" bind:value={historyYears} min="0" max="30" />
            </label>
            <label class="sf-field">
                <span>연체 횟수</span>
                <input class="sf-input" type="number" bind:value={missedPayments} min="0" max="20" />
            </label>
            <button class="ocaml-btn score-btn" onclick={fetchScore} disabled={scoreLoading}>
                {scoreLoading ? "산정 중..." : "스코어 산정"}
            </button>
        </div>
        {#if scoreData}
            {#if scoreData.error}
                <p style="color:#f87171">{scoreData.error}</p>
            {:else}
                <div class="julia-grid" style="margin-top:0.5rem">
                    <div class="julia-card ocaml-card" style="border-color:#60a5fa">
                        <span class="jlabel">Credit Score</span>
                        <span class="jval" style="color:#60a5fa">{scoreData.score}</span>
                    </div>
                    <div class="julia-card ocaml-card" style="border-color:#60a5fa">
                        <span class="jlabel">Grade</span>
                        <span class="jval" style="color:#60a5fa">{scoreData.grade}</span>
                    </div>
                    <div class="julia-card ocaml-card">
                        <span class="jlabel">제거 확률</span>
                        <span class="jval">{((scoreData.prob_good ?? 0) * 100).toFixed(1)}%</span>
                    </div>
                    <div class="julia-card ocaml-card">
                        <span class="jlabel">DTI</span>
                        <span class="jval">{((scoreData.dti ?? 0) * 100).toFixed(1)}%</span>
                    </div>
                </div>
            {/if}
        {/if}
    </div>
</section>

<style>
    .ocaml-btn {
        background: linear-gradient(135deg, #f97316, #c2410c);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .ocaml-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #ea580c, #9a3412);
    }
    .ocaml-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .ocaml-card {
        border-color: #f97316 !important;
    }
    :global(.risk-low) {
        color: #4ade80 !important;
    }
    :global(.risk-medium) {
        color: #facc15 !important;
    }
    :global(.risk-high) {
        color: #fb923c !important;
    }
    :global(.risk-critical) {
        color: #f87171 !important;
    }
    .score-section {
        margin-top: 1.5rem;
        border-top: 1px solid rgba(249, 115, 22, 0.25);
        padding-top: 1rem;
    }
    .score-label {
        font-size: 0.75rem;
        color: #f97316;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        font-weight: 600;
        margin-bottom: 0.6rem;
    }
    .score-form {
        display: flex;
        gap: 0.75rem;
        flex-wrap: wrap;
        align-items: flex-end;
    }
    .sf-field {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        font-size: 0.75rem;
        color: #94a3b8;
        flex: 1;
        min-width: 110px;
    }
    .sf-input {
        background: rgba(249, 115, 22, 0.07);
        border: 1px solid rgba(249, 115, 22, 0.35);
        border-radius: 6px;
        color: #e2e8f0;
        font-size: 0.85rem;
        padding: 0.4rem 0.5rem;
        width: 100%;
        box-sizing: border-box;
    }
    .sf-input:focus {
        outline: none;
        border-color: #f97316;
    }
    .score-btn {
        padding: 0.5rem 1.1rem;
        font-size: 0.82rem;
    }
</style>
