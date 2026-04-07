<script>
    /** @type {any | null} */
    let rubyData = $state(null);
    /** @type {boolean} */
    let rubyLoading = $state(false);
    /** @type {any | null} */
    let rulesResult = $state(null);
    /** @type {boolean} */
    let rulesLoading = $state(false);
    let customRule = $state(
        `rule(:low_income_penalty) do\n  condition { annual_income_k < 50 }\n  action     { score - 40 }\nend`,
    );
    let debtRatio = $state(0.75);
    let ltv = $state(0.88);
    let numDefaults = $state(1);
    let annualIncomeK = $state(60);

    async function runRuby() {
        rubyLoading = true;
        rubyData = null;
        try {
            const q = `debt_ratio=${debtRatio}&ltv=${ltv}&num_defaults=${numDefaults}&annual_income_k=${annualIncomeK}`;
            const [scoreRes, rulesetRes, evalRes] = await Promise.all([
                fetch(`http://localhost:9004/api/ruby/score?${q}`),
                fetch("http://localhost:9004/api/ruby/ruleset"),
                fetch(`http://localhost:9004/api/ruby/evaluate?${q}`),
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

    async function loadCustomRule() {
        rulesLoading = true;
        rulesResult = null;
        try {
            const res = await fetch("http://localhost:9004/api/ruby/rules", {
                method: "POST",
                headers: { "Content-Type": "text/plain" },
                body: customRule,
            });
            rulesResult = await res.json();
            if (rulesResult?.loaded) {
                await runRuby();
            }
        } catch {
            rulesResult = {
                loaded: false,
                error: "Ruby 서버 접속 불가 (:9004)",
            };
        } finally {
            rulesLoading = false;
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

    <div class="param-grid">
        <div class="param-row">
            <label>부채비율</label>
            <input
                type="range"
                min="0.1"
                max="1.0"
                step="0.05"
                bind:value={debtRatio}
            />
            <span class="param-val">{debtRatio.toFixed(2)}</span>
        </div>
        <div class="param-row">
            <label>LTV</label>
            <input
                type="range"
                min="0.1"
                max="1.5"
                step="0.05"
                bind:value={ltv}
            />
            <span class="param-val">{ltv.toFixed(2)}</span>
        </div>
        <div class="param-row">
            <label>연체 횟수</label>
            <input
                type="range"
                min="0"
                max="5"
                step="1"
                bind:value={numDefaults}
            />
            <span class="param-val">{numDefaults}회</span>
        </div>
        <div class="param-row">
            <label>연소득 (만$)</label>
            <input
                type="range"
                min="20"
                max="300"
                step="10"
                bind:value={annualIncomeK}
            />
            <span class="param-val">{annualIncomeK}k</span>
        </div>
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

    <div class="dsl-section">
        <p class="dsl-label">커스텀 DSL 룰 동적 로드</p>
        <textarea
            class="dsl-input"
            rows="5"
            bind:value={customRule}
            placeholder="rule(:name) do ... end"
        ></textarea>
        <div class="dsl-row">
            <button
                class="ruby-btn dsl-btn"
                onclick={loadCustomRule}
                disabled={rulesLoading}
            >
                {rulesLoading ? "로딩 중..." : "룰 로드"}
            </button>
            {#if rulesResult}
                {#if rulesResult.loaded}
                    <span class="dsl-result ok">
                        ✅ 로드 완료 · {rulesResult.rules_before}개 →
                        {rulesResult.rules_after}개
                    </span>
                {:else}
                    <span class="dsl-result err">
                        ❌ {rulesResult.error ?? "로드 실패"}
                    </span>
                {/if}
            {/if}
        </div>
    </div>
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
    .dsl-section {
        margin-top: 1.5rem;
        border-top: 1px solid rgba(220, 38, 38, 0.25);
        padding-top: 1rem;
    }
    .dsl-label {
        font-size: 0.75rem;
        color: #dc2626;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        font-weight: 600;
        margin-bottom: 0.5rem;
    }
    .dsl-input {
        width: 100%;
        background: rgba(220, 38, 38, 0.06);
        border: 1px solid rgba(220, 38, 38, 0.35);
        border-radius: 6px;
        color: #e2e8f0;
        font-family: monospace;
        font-size: 0.82rem;
        padding: 0.5rem 0.7rem;
        resize: vertical;
        box-sizing: border-box;
    }
    .dsl-input:focus {
        outline: none;
        border-color: #dc2626;
    }
    .dsl-row {
        display: flex;
        align-items: center;
        gap: 1rem;
        margin-top: 0.5rem;
    }
    .dsl-btn {
        padding: 0.5rem 1.2rem;
        font-size: 0.85rem;
    }
    .dsl-result {
        font-size: 0.85rem;
        font-weight: 600;
    }
    .dsl-result.ok {
        color: #34d399;
    }
    .dsl-result.err {
        color: #f87171;
    }
    .param-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
        gap: 0.4rem 1rem;
        margin-bottom: 0.75rem;
    }
    .param-row {
        display: flex;
        align-items: center;
        gap: 0.4rem;
        font-size: 0.8rem;
        color: #94a3b8;
    }
    .param-row label {
        min-width: 80px;
        flex-shrink: 0;
    }
    .param-row input[type="range"] {
        flex: 1;
        accent-color: #dc2626;
    }
    .param-val {
        min-width: 40px;
        text-align: right;
        color: #e2e8f0;
        font-family: monospace;
        font-size: 0.78rem;
    }
</style>
