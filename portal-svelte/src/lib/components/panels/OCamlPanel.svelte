<script>
    /** @type {any | null} */
    let ocamlRisk = $state(null);
    /** @type {boolean} */
    let ocamlLoading = $state(false);

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
</style>
