<script>
    import { API_BASE } from '$lib/api';
    /** @type {any | null} */
    let riskResult = $state(null);
    /** @type {any | null} */
    let circuitResult = $state(null);
    let riskLoading = $state(false);
    let circuitLoading = $state(false);

    async function runRiskFull() {
        riskLoading = true;
        riskResult = null;
        try {
            const res = await fetch(
                `${API_BASE}/api/workflow/risk-full`,
            );
            if (res.ok) riskResult = await res.json();
            else riskResult = { error: "Go 워크플로 오프라인" };
        } catch {
            riskResult = { error: "Go 게이트웨이 접속 불가 (:8080)" };
        } finally {
            riskLoading = false;
        }
    }

    async function fetchCircuit() {
        circuitLoading = true;
        circuitResult = null;
        try {
            const res = await fetch(`${API_BASE}/api/circuit/status`);
            if (res.ok) circuitResult = await res.json();
            else circuitResult = { error: "서킷 브레이커 조회 실패" };
        } catch {
            circuitResult = { error: "Go 게이트웨이 접속 불가 (:8080)" };
        } finally {
            circuitLoading = false;
        }
    }

    /** @param {string} state @returns {string} */
    function cbClass(state) {
        if (state === "closed") return "cb-closed";
        if (state === "open") return "cb-open";
        return "cb-half";
    }

    /** @param {string} state @returns {string} */
    function cbLabel(state) {
        if (state === "closed") return "✓ 정상";
        if (state === "open") return "✕ 차단";
        return "~ 복구중";
    }

    /** @param {any} step @returns {string} */
    function stepClass(step) {
        return step?.status === "ok" ? "step-ok" : "step-err";
    }

    /** @param {any} step @returns {string} */
    function stepIcon(step) {
        return step?.status === "ok" ? "✓" : "✕";
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🔀 워크플로 파이프라인 (Go 오케스트레이션)</h2>
            <p class="subtitle">
                Python → Rust → Kotlin → Nim 엔드-투-엔드 리스크 파이프라인 ·
                서킷 브레이커 모니터링 · Redis Pub/Sub 이벤트 (:8080) · 5단계
            </p>
        </div>
        <div class="btn-group">
            <button
                class="run-btn"
                onclick={runRiskFull}
                disabled={riskLoading}
            >
                {riskLoading ? "실행 중..." : "▶ 파이프라인 실행"}
            </button>
            <button
                class="circuit-btn"
                onclick={fetchCircuit}
                disabled={circuitLoading}
            >
                {circuitLoading ? "조회 중..." : "🛡 서킷 브레이커"}
            </button>
        </div>
    </div>

    <!-- ── 리스크 파이프라인 ──────────────────────────────── -->
    {#if riskResult?.error}
        <p class="error-msg">{riskResult.error}</p>
    {:else if riskResult}
        <div class="pipeline-meta">
            <span class="meta-item">
                상태: <strong
                    class={riskResult.status === "ok" ? "ok-text" : "warn-text"}
                >
                    {riskResult.status}
                </strong>
            </span>
            <span class="meta-item"
                >소요: <strong>{riskResult.elapsed_ms}ms</strong></span
            >
            <span class="meta-item meta-engine">{riskResult.engine}</span>
        </div>

        <div class="steps-timeline">
            {#each riskResult.steps ?? [] as step}
                <div class="step-item {stepClass(step)}">
                    <div class="step-header">
                        <span class="step-icon">{stepIcon(step)}</span>
                        <span class="step-num">Step {step.step}</span>
                        <span class="step-service">{step.service}</span>
                        <span class="step-action">— {step.action}</span>
                    </div>
                    {#if step.status === "error"}
                        <p class="step-err-msg">{step.error}</p>
                    {:else if step.data}
                        <p class="step-data">
                            {#if step.data.engine}
                                {step.data.engine}
                                {#if step.data.risk_score !== undefined}
                                    · VaR95={step.data.risk_score}
                                {/if}
                            {:else if step.data.rows_inserted !== undefined}
                                {step.data.rows_inserted}건 삽입
                            {:else if step.data.persistence !== undefined}
                                α+β={step.data.persistence?.toFixed(4)} · 반감기={step.data.half_life_days?.toFixed(
                                    1,
                                )}일 · 현재σ={step.data.current_vol_ann != null
                                    ? (step.data.current_vol_ann * 100).toFixed(
                                          2,
                                      ) + "%"
                                    : "N/A"}
                            {:else if step.data.var_95 !== undefined}
                                VaR95={step.data.var_95}
                                {#if step.data.count !== undefined}
                                    ({step.data.count}건)
                                {/if}
                            {:else if step.data.total_currencies !== undefined}
                                {step.data.total_currencies}통화 리포트 생성
                            {:else}
                                완료
                            {/if}
                        </p>
                    {/if}
                </div>
            {/each}
        </div>
    {/if}

    <!-- ── 서킷 브레이커 상태 ────────────────────────────── -->
    {#if circuitResult?.error}
        <p class="error-msg">{circuitResult.error}</p>
    {:else if circuitResult}
        <div class="section-divider">🛡 서킷 브레이커 현황</div>
        <div class="cb-grid">
            {#each Object.entries(circuitResult.circuit_breakers ?? {}) as [name, cb]}
                <div class="cb-card {cbClass(cb.state)}">
                    <div class="cb-name">{name}</div>
                    <div class="cb-state-label">{cbLabel(cb.state)}</div>
                    <div class="cb-stats">
                        실패 {cb.failures} · 성공 {cb.successes}
                    </div>
                </div>
            {/each}
        </div>
    {/if}
</section>

<style>
    .panel {
        background: #1e293b;
        border: 1px solid #334155;
        border-radius: 12px;
        padding: 1.25rem 1.5rem;
        margin-bottom: 1.25rem;
    }
    .panel-header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 1rem;
        margin-bottom: 1rem;
    }
    h2 {
        margin: 0 0 0.25rem;
        font-size: 1.05rem;
        color: #e2e8f0;
    }
    .subtitle {
        margin: 0;
        font-size: 0.78rem;
        color: #64748b;
    }
    .btn-group {
        display: flex;
        gap: 0.5rem;
        flex-shrink: 0;
        flex-wrap: wrap;
    }
    .run-btn {
        background: #1e3a5f;
        color: #60a5fa;
        border: 1px solid #1d4ed8;
        border-radius: 6px;
        padding: 0.45rem 1rem;
        cursor: pointer;
        font-size: 0.82rem;
        white-space: nowrap;
    }
    .run-btn:hover:not(:disabled) {
        background: #1d4ed8;
    }
    .run-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }
    .circuit-btn {
        background: #1a2e1a;
        color: #4ade80;
        border: 1px solid #166534;
        border-radius: 6px;
        padding: 0.45rem 1rem;
        cursor: pointer;
        font-size: 0.82rem;
        white-space: nowrap;
    }
    .circuit-btn:hover:not(:disabled) {
        background: #166534;
    }
    .circuit-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    /* ── 파이프라인 결과 ── */
    .pipeline-meta {
        display: flex;
        gap: 1.5rem;
        font-size: 0.8rem;
        color: #94a3b8;
        margin-bottom: 0.85rem;
        flex-wrap: wrap;
    }
    .meta-item strong {
        color: #e2e8f0;
    }
    .ok-text {
        color: #22c55e;
    }
    .warn-text {
        color: #f59e0b;
    }
    .meta-engine {
        color: #475569;
        font-family: monospace;
        margin-left: auto;
    }

    .steps-timeline {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        margin-bottom: 1rem;
    }
    .step-item {
        border-left: 3px solid #334155;
        padding: 0.5rem 0.75rem;
        border-radius: 0 6px 6px 0;
        background: #0f172a;
    }
    .step-ok {
        border-left-color: #22c55e;
    }
    .step-err {
        border-left-color: #ef4444;
    }
    .step-header {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.83rem;
    }
    .step-icon {
        font-size: 0.85rem;
    }
    .step-ok .step-icon {
        color: #22c55e;
    }
    .step-err .step-icon {
        color: #ef4444;
    }
    .step-num {
        color: #64748b;
        font-family: monospace;
    }
    .step-service {
        color: #e2e8f0;
        font-weight: 600;
    }
    .step-action {
        color: #64748b;
    }
    .step-data {
        margin: 0.3rem 0 0 1.3rem;
        font-size: 0.78rem;
        color: #94a3b8;
        font-family: monospace;
    }
    .step-err-msg {
        margin: 0.3rem 0 0 1.3rem;
        font-size: 0.78rem;
        color: #ef4444;
    }

    /* ── 서킷 브레이커 ── */
    .section-divider {
        font-size: 0.8rem;
        color: #64748b;
        border-bottom: 1px solid #334155;
        padding-bottom: 0.4rem;
        margin: 1rem 0 0.75rem;
    }
    .cb-grid {
        display: flex;
        flex-wrap: wrap;
        gap: 0.6rem;
    }
    .cb-card {
        background: #0f172a;
        border: 1px solid #334155;
        border-radius: 8px;
        padding: 0.6rem 0.85rem;
        min-width: 140px;
    }
    .cb-closed {
        border-color: #166534;
    }
    .cb-open {
        border-color: #991b1b;
    }
    .cb-half {
        border-color: #92400e;
    }
    .cb-name {
        font-size: 0.82rem;
        color: #94a3b8;
        margin-bottom: 0.2rem;
    }
    .cb-state-label {
        font-size: 0.88rem;
        font-weight: 600;
    }
    .cb-closed .cb-state-label {
        color: #4ade80;
    }
    .cb-open .cb-state-label {
        color: #f87171;
    }
    .cb-half .cb-state-label {
        color: #fbbf24;
    }
    .cb-stats {
        font-size: 0.72rem;
        color: #475569;
        font-family: monospace;
        margin-top: 0.25rem;
    }
    .error-msg {
        color: #ef4444;
        font-size: 0.85rem;
        margin-top: 0.5rem;
    }
</style>
