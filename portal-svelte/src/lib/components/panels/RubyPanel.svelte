<script>
    /** @type {any | null} */
    let rubyData = $state(null);
    /** @type {boolean} */
    let rubyLoading = $state(false);

    async function runRuby() {
        rubyLoading = true;
        rubyData = null;
        try {
            const [scoreRes, rulesetRes, evalRes] = await Promise.all([
                fetch(
                    "http://localhost:9004/api/ruby/score?debt_ratio=0.75&ltv=0.88&num_defaults=1&annual_income_k=60",
                ),
                fetch("http://localhost:9004/api/ruby/ruleset"),
                fetch(
                    "http://localhost:9004/api/ruby/evaluate?debt_ratio=0.75&ltv=0.88&num_defaults=1&annual_income_k=60",
                ),
            ]);
            if (scoreRes.ok && rulesetRes.ok && evalRes.ok) {
                const score = await scoreRes.json();
                const ruleset = await rulesetRes.json();
                const evalResult = await evalRes.json();
                rubyData = { ...score, ruleset, evalResult };
            } else {
                rubyData = { error: "Ruby DSL 엔진 오프라인" };
            }
        } catch {
            rubyData = { error: "Ruby 서버 접속 불가 (:9004)" };
        } finally {
            rubyLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>💎 Ruby (Runtime DSL Engine)</h2>
            <p class="subtitle">
                Ruby 3.0 · instance_eval 런타임 규칙 동적 적재 · 서버 재시작
                없음 (:9004)
            </p>
        </div>
        <button class="ruby-btn" onclick={runRuby} disabled={rubyLoading}>
            {rubyLoading ? "계산 중..." : "DSL 규칙 평가"}
        </button>
    </div>
    {#if rubyData}
        {#if rubyData.error}
            <div class="empty-box">
                <p style="color:#f87171">{rubyData.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card ruby-card">
                    <span class="jlabel">Credit Score</span>
                    <span class="jval">{rubyData.score}</span>
                </div>
                <div class="julia-card ruby-card">
                    <span class="jlabel">Grade / PD</span>
                    <span class="jval"
                        >{rubyData.grade} / {((rubyData.pd ?? 0) * 100).toFixed(
                            1,
                        )}%</span
                    >
                </div>
                <div class="julia-card ruby-card" style="border-color:#f59e0b">
                    <span class="jlabel">발화 규칙 수</span>
                    <span class="jval" style="color:#f59e0b"
                        >{rubyData.evalResult?.fired_count ?? 0} / {rubyData
                            .evalResult?.total_rules ?? 0}</span
                    >
                </div>
                <div class="julia-card ruby-card" style="border-color:#f59e0b">
                    <span class="jlabel">발화된 규칙</span>
                    <span class="jval"
                        >{(rubyData.evalResult?.fired_rules ?? []).join(", ") ||
                            "없음"}</span
                    >
                </div>
                <div class="julia-card ruby-card">
                    <span class="jlabel">등록 규칙 수</span>
                    <span class="jval"
                        >{rubyData.ruleset?.total_rules ?? 0}개</span
                    >
                </div>
                <div class="julia-card ruby-card">
                    <span class="jlabel">인터프리터</span>
                    <span class="jval">instance_eval</span>
                </div>
            </div>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Ruby instance_eval DSL 동적 규칙 평가를 실행하세요.
                (Ruby 서버 :9004 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .ruby-btn {
        background: linear-gradient(135deg, #dc2626, #c2410c);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .ruby-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #b91c1c, #9a3412);
    }
    .ruby-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .ruby-card {
        border-color: #dc2626 !important;
    }
</style>
