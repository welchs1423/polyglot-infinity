<script>
    /** @type {any} */
    let statusData = $state(null);
    /** @type {any} */
    let inferData = $state(null);
    /** @type {any} */
    let portfolioData = $state(null);
    /** @type {any} */
    let explainData = $state(null);
    let loading = $state(false);
    let explainLoading = $state(false);
    let portfolioType = $state("balanced");
    let riskMax = $state(12);
    let debtRatio = $state(0.45);
    let volatility = $state(0.22);
    let defaults = $state(1);

    async function runAll() {
        loading = true;
        try {
            const [status, infer, portfolio, explain] = await Promise.all([
                fetch("http://localhost:8011/api/prolog/status").then((x) =>
                    x.json(),
                ),
                fetch(
                    `http://localhost:8011/api/prolog/infer?debt=${debtRatio}&vol=${volatility}&defaults=${defaults}`,
                ).then((x) => x.json()),
                fetch(
                    `http://localhost:8011/api/prolog/portfolio?type=${portfolioType}&risk_max=${riskMax}`,
                ).then((x) => x.json()),
                fetch(
                    `http://localhost:8011/api/prolog/explain?debt=${debtRatio}&vol=${volatility}&defaults=${defaults}`,
                ).then((x) => x.json()),
            ]);
            statusData = status;
            inferData = infer;
            portfolioData = portfolio;
            explainData = explain;
        } catch {
            inferData = { error: "Prolog 서버 접속 불가 (:8011)" };
        } finally {
            loading = false;
        }
    }

    async function runPortfolio() {
        loading = true;
        try {
            portfolioData = await fetch(
                `http://localhost:8011/api/prolog/portfolio?type=${portfolioType}&risk_max=${riskMax}`,
            ).then((x) => x.json());
        } catch {
            portfolioData = { error: "포트폴리오 탐색 실패" };
        } finally {
            loading = false;
        }
    }

    async function fetchExplain() {
        explainLoading = true;
        explainData = null;
        try {
            explainData = await fetch(
                `http://localhost:8011/api/prolog/explain?debt=${debtRatio}&vol=${volatility}&defaults=${defaults}`,
            ).then((x) => x.json());
        } catch {
            explainData = { error: "Prolog 서버 접속 불가 (:8011)" };
        } finally {
            explainLoading = false;
        }
    }

    const gradeColor = /** @param {string} g */ (g) => {
        if (!g) return "#94a3b8";
        /** @type {Record<string, string>} */
        const m = {
            low: "#22c55e",
            medium: "#f59e0b",
            high: "#f97316",
            critical: "#ef4444",
        };
        return m[g.toLowerCase()] ?? "#94a3b8";
    };

    /** @type {Record<string, string>} */
    const typeColors = {
        aggressive: "#ef4444",
        balanced: "#3b82f6",
        conservative: "#22c55e",
    };
</script>

<section class="panel prolog-panel">
    <h2>🟣 SWI-Prolog 8.4 · 논리 추론 + 제약 백트래킹 (:8011)</h2>
    <p class="subtitle">
        선언적 규칙 → 자동 백트래킹 탐색 · 제약 충족 포트폴리오 · 신용 리스크
        논리 추론 체인
    </p>

    <!-- 파라미터 입력 -->
    <div class="prolog-params">
        <div class="param-group">
            <label>부채비율</label>
            <input
                type="range"
                min="0.1"
                max="0.9"
                step="0.05"
                bind:value={debtRatio}
            />
            <span>{debtRatio.toFixed(2)}</span>
        </div>
        <div class="param-group">
            <label>변동성</label>
            <input
                type="range"
                min="0.05"
                max="0.5"
                step="0.05"
                bind:value={volatility}
            />
            <span>{volatility.toFixed(2)}</span>
        </div>
        <div class="param-group">
            <label>연체 횟수</label>
            <input
                type="range"
                min="0"
                max="5"
                step="1"
                bind:value={defaults}
            />
            <span>{defaults}</span>
        </div>
    </div>

    <div class="prolog-params">
        <div class="param-group">
            <label>포트폴리오 타입</label>
            <select bind:value={portfolioType}>
                <option value="aggressive">Aggressive (공격형)</option>
                <option value="balanced">Balanced (균형형)</option>
                <option value="conservative">Conservative (안정형)</option>
            </select>
        </div>
        <div class="param-group">
            <label>최대 리스크</label>
            <input
                type="range"
                min="6"
                max="20"
                step="1"
                bind:value={riskMax}
            />
            <span>{riskMax}</span>
        </div>
    </div>

    <button class="prolog-btn" onclick={runAll} disabled={loading}>
        {loading ? "추론 중..." : "논리 추론 실행"}
    </button>
    <button
        class="explain-btn"
        onclick={fetchExplain}
        disabled={explainLoading}
    >
        {explainLoading ? "분석 중..." : "회? (Why?) 역추적 설명"}
    </button>

    {#if inferData}
        {#if inferData.error}
            <div class="error-box">
                <p style="color:#f87171">{inferData.error}</p>
            </div>
        {:else}
            <!-- 엔진 정보 -->
            {#if statusData}
                <div class="prolog-info-bar">
                    <span class="prolog-badge"
                        >SWI-Prolog {statusData.version?.replace(
                            "SWI-Prolog ",
                            "",
                        ) ?? ""}</span
                    >
                    <span class="prolog-badge" style="background:#4b5563"
                        >{statusData.paradigm}</span
                    >
                </div>
            {/if}

            <!-- 신용 추론 결과 -->
            <h3 class="section-title">🔍 신용 리스크 논리 추론</h3>
            <div
                class="prolog-result-box"
                style="border-color: {gradeColor(inferData.grade)}"
            >
                <div
                    class="prolog-grade"
                    style="color: {gradeColor(inferData.grade)}"
                >
                    {(inferData.grade ?? "").toUpperCase()}
                </div>
                <div class="prolog-reason">{inferData.reason}</div>
                <div class="prolog-method">{inferData.method}</div>
            </div>

            <div class="card-grid" style="margin-top:0.75rem">
                <div class="julia-card" style="border-color:#6366f1">
                    <span class="label">부채비율</span>
                    <span class="value"
                        >{(inferData.debt_ratio * 100).toFixed(0)}%</span
                    >
                </div>
                <div class="julia-card" style="border-color:#6366f1">
                    <span class="label">변동성</span>
                    <span class="value"
                        >{(inferData.volatility * 100).toFixed(0)}%</span
                    >
                </div>
                <div class="julia-card" style="border-color:#6366f1">
                    <span class="label">연체 횟수</span>
                    <span class="value">{inferData.defaults}회</span>
                </div>
                <div class="julia-card" style="border-color:#6366f1">
                    <span class="label">매칭 규칙 수</span>
                    <span class="value">{inferData.rules_matched}개</span>
                </div>
            </div>

            {#if inferData.flags_fired?.length > 0}
                <div class="flags-box">
                    <span class="flags-label">발화된 플래그:</span>
                    {#each inferData.flags_fired as flag}
                        <span class="flag-chip">{flag}</span>
                    {/each}
                </div>
            {/if}

            <!-- Why? 역추적 설명 -->
            {#if explainData && !explainData.error}
                <h3 class="section-title" style="margin-top:1rem">
                    🔎 Why? 역추적 추론 체인
                </h3>
                <div class="explain-box">
                    <div class="explain-method">{explainData.method}</div>
                    <ul class="evidence-list">
                        {#each explainData.evidence ?? [] as ev}
                            <li class="evidence-item">{ev}</li>
                        {/each}
                    </ul>
                    {#if explainData.rules_matched?.length > 0}
                        <div class="explain-section">
                            <span class="explain-label">매칭된 규칙:</span>
                            {#each explainData.rules_matched as rule}
                                <span class="rule-chip">{rule}</span>
                            {/each}
                        </div>
                    {/if}
                    <div
                        class="explain-conclusion"
                        style="color: {gradeColor(explainData.final_grade)}"
                    >
                        {explainData.conclusion}
                    </div>
                </div>
            {/if}
        {/if}
    {/if}

    <!-- 역추적 설명 -->
    {#if explainData}
        <h3 class="section-title" style="margin-top:1.2rem">
            🔎 왜? (Why?) 역추적 설명
        </h3>
        {#if explainData.error}
            <p style="color:#f87171">{explainData.error}</p>
        {:else}
            <div class="explain-chain">
                {#each explainData.evidence ?? [] as ev, i}
                    <div class="explain-step">
                        <span class="step-num">①②③④⑤⑥⑦⑧⑨⑩"[i] ?? (i + 1)</span>
                        <span>{ev}</span>
                    </div>
                {/each}
            </div>
            {#if (explainData.flags_fired ?? []).length > 0}
                <div class="flags-box" style="margin-top:0.5rem">
                    <span class="flags-label">발화된 플래그:</span>
                    {#each explainData.flags_fired as flag}
                        <span class="flag-chip">{flag}</span>
                    {/each}
                </div>
            {:else}
                <div class="flags-box" style="margin-top:0.5rem">
                    <span class="flags-label">발화된 플래그: 없음</span>
                </div>
            {/if}
            <div
                class="explain-conclusion"
                style="color:{gradeColor(explainData.final_grade)}"
            >
                {explainData.conclusion}
            </div>
            <p class="prolog-method" style="margin-top:0.4rem">
                {explainData.method}
            </p>
        {/if}
    {/if}

    <!-- 포트폴리오 탐색 -->
    {#if portfolioData}
        <h3 class="section-title" style="margin-top:1.2rem">
            📦 제약 충족 포트폴리오 (백트래킹 탐색)
        </h3>
        {#if portfolioData.error}
            <p style="color:#f87171">{portfolioData.error}</p>
        {:else if portfolioData.found}
            <div
                class="prolog-portfolio-box"
                style="border-color: {typeColors[
                    portfolioData.portfolio_type
                ] ?? '#6366f1'}"
            >
                <div
                    class="portfolio-type-badge"
                    style="background: {typeColors[
                        portfolioData.portfolio_type
                    ] ?? '#6366f1'}"
                >
                    {portfolioData.portfolio_type?.toUpperCase()}
                </div>
                <div class="portfolio-alloc">
                    <div class="alloc-bar-wrap">
                        <span class="alloc-label">주식 (Equity)</span>
                        <div class="alloc-bar">
                            <div
                                class="alloc-fill equity"
                                style="width:{portfolioData.equity_pct}%"
                            ></div>
                        </div>
                        <span class="alloc-pct"
                            >{portfolioData.equity_pct}%</span
                        >
                    </div>
                    <div class="alloc-bar-wrap">
                        <span class="alloc-label">채권 (Bond)</span>
                        <div class="alloc-bar">
                            <div
                                class="alloc-fill bond"
                                style="width:{portfolioData.bond_pct}%"
                            ></div>
                        </div>
                        <span class="alloc-pct">{portfolioData.bond_pct}%</span>
                    </div>
                    <div class="alloc-bar-wrap">
                        <span class="alloc-label">대안 (Alternative)</span>
                        <div class="alloc-bar">
                            <div
                                class="alloc-fill alt"
                                style="width:{portfolioData.alternative_pct}%"
                            ></div>
                        </div>
                        <span class="alloc-pct"
                            >{portfolioData.alternative_pct}%</span
                        >
                    </div>
                    <div class="alloc-bar-wrap">
                        <span class="alloc-label">현금 (Cash)</span>
                        <div class="alloc-bar">
                            <div
                                class="alloc-fill cash"
                                style="width:{portfolioData.cash_pct}%"
                            ></div>
                        </div>
                        <span class="alloc-pct">{portfolioData.cash_pct}%</span>
                    </div>
                </div>
                <div class="card-grid" style="margin-top:0.75rem">
                    <div class="julia-card" style="border-color:#8b5cf6">
                        <span class="label">기대수익률</span>
                        <span class="value" style="color:#a78bfa"
                            >{portfolioData.expected_return?.toFixed(2)}%</span
                        >
                    </div>
                    <div class="julia-card" style="border-color:#8b5cf6">
                        <span class="label">포트폴리오 리스크</span>
                        <span class="value" style="color:#f59e0b"
                            >{portfolioData.portfolio_risk?.toFixed(2)}</span
                        >
                    </div>
                </div>
                <div class="prolog-method" style="margin-top:0.5rem">
                    {portfolioData.method}
                </div>
            </div>
        {:else}
            <p style="color:#f87171">
                해당 제약을 만족하는 포트폴리오를 찾을 수 없습니다.
            </p>
        {/if}
    {/if}
</section>

<style>
    .prolog-panel {
        background: linear-gradient(135deg, #1e1b4b 0%, #1e293b 100%);
        border: 1px solid #4c1d95;
    }

    .prolog-btn {
        background: linear-gradient(90deg, #7c3aed, #6d28d9);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: opacity 0.2s;
        width: 100%;
        margin-bottom: 1rem;
    }

    .prolog-btn:hover:not(:disabled) {
        opacity: 0.85;
    }
    .prolog-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .prolog-params {
        display: flex;
        gap: 1rem;
        flex-wrap: wrap;
        margin-bottom: 0.75rem;
    }

    .param-group {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.85rem;
        color: #94a3b8;
        flex: 1;
        min-width: 160px;
    }

    .param-group label {
        white-space: nowrap;
        color: #cbd5e1;
    }
    .param-group input[type="range"] {
        flex: 1;
        accent-color: #7c3aed;
    }
    .param-group select {
        flex: 1;
        background: #1e293b;
        color: #e2e8f0;
        border: 1px solid #4b5563;
        border-radius: 6px;
        padding: 0.2rem 0.4rem;
        font-size: 0.82rem;
    }
    .param-group span {
        min-width: 2.5rem;
        text-align: right;
        color: #a78bfa;
        font-weight: bold;
    }

    .prolog-info-bar {
        display: flex;
        gap: 0.5rem;
        margin-bottom: 0.75rem;
    }

    .prolog-badge {
        font-size: 0.75rem;
        background: #4c1d95;
        color: #c4b5fd;
        padding: 0.2rem 0.6rem;
        border-radius: 4px;
    }

    .section-title {
        color: #c4b5fd;
        font-size: 0.95rem;
        margin: 0 0 0.5rem 0;
    }

    .prolog-result-box {
        background: #0f172a;
        border: 1px solid;
        border-radius: 8px;
        padding: 1rem;
    }

    .prolog-grade {
        font-size: 1.4rem;
        font-weight: bold;
        margin-bottom: 0.25rem;
    }

    .prolog-reason {
        color: #e2e8f0;
        font-size: 0.9rem;
        margin-bottom: 0.4rem;
    }

    .prolog-method {
        color: #64748b;
        font-size: 0.78rem;
        font-style: italic;
    }

    .flags-box {
        margin-top: 0.5rem;
        display: flex;
        flex-wrap: wrap;
        gap: 0.4rem;
        align-items: center;
    }

    .flags-label {
        font-size: 0.8rem;
        color: #94a3b8;
    }

    .flag-chip {
        background: #7f1d1d;
        color: #fca5a5;
        font-size: 0.75rem;
        padding: 0.15rem 0.5rem;
        border-radius: 4px;
    }

    .prolog-portfolio-box {
        background: #0f172a;
        border: 1px solid;
        border-radius: 8px;
        padding: 1rem;
    }

    .portfolio-type-badge {
        display: inline-block;
        color: white;
        font-size: 0.75rem;
        font-weight: bold;
        padding: 0.25rem 0.75rem;
        border-radius: 4px;
        margin-bottom: 0.75rem;
    }

    .portfolio-alloc {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
    }

    .alloc-bar-wrap {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.82rem;
    }

    .alloc-label {
        width: 110px;
        color: #94a3b8;
        flex-shrink: 0;
    }

    .alloc-bar {
        flex: 1;
        background: #1e293b;
        border-radius: 4px;
        height: 12px;
        overflow: hidden;
    }

    .alloc-fill {
        height: 100%;
        border-radius: 4px;
        transition: width 0.4s;
    }
    .alloc-fill.equity {
        background: #ef4444;
    }
    .alloc-fill.bond {
        background: #3b82f6;
    }
    .alloc-fill.alt {
        background: #f59e0b;
    }
    .alloc-fill.cash {
        background: #22c55e;
    }

    .alloc-pct {
        width: 2.5rem;
        text-align: right;
        color: #e2e8f0;
        font-weight: bold;
        font-size: 0.82rem;
    }

    .error-box {
        margin-top: 0.5rem;
    }

    .julia-card {
        background: #0f172a;
        border: 1px solid #334155;
        border-radius: 8px;
        padding: 1rem;
        display: flex;
        flex-direction: column;
        gap: 0.3rem;
    }

    .label {
        font-size: 0.8rem;
        color: #94a3b8;
    }
    .value {
        font-size: 1.1rem;
        font-weight: bold;
        color: #f8fafc;
    }
    .explain-btn {
        background: transparent;
        color: #a78bfa;
        border: 1px solid #7c3aed;
        padding: 0.55rem 1.2rem;
        border-radius: 8px;
        font-weight: 600;
        cursor: pointer;
        font-size: 0.85rem;
        width: 100%;
        margin-bottom: 1rem;
        transition: background 0.2s;
    }
    .explain-btn:hover:not(:disabled) {
        background: rgba(124, 58, 237, 0.12);
    }
    .explain-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }
    .explain-chain {
        display: flex;
        flex-direction: column;
        gap: 0.35rem;
        margin-top: 0.5rem;
    }
    .explain-step {
        display: flex;
        gap: 0.6rem;
        align-items: flex-start;
        font-size: 0.82rem;
        color: #cbd5e1;
        background: rgba(99, 102, 241, 0.07);
        border-left: 3px solid #6366f1;
        padding: 0.4rem 0.7rem;
        border-radius: 0 4px 4px 0;
    }
    .step-num {
        color: #818cf8;
        font-weight: 700;
        flex-shrink: 0;
    }
    .explain-conclusion {
        margin-top: 0.75rem;
        font-size: 0.95rem;
        font-weight: 700;
        padding: 0.5rem 0.75rem;
        background: rgba(99, 102, 241, 0.1);
        border-radius: 6px;
    }
</style>
