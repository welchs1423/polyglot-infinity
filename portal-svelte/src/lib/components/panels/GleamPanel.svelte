<script>
    /** @type {any} */
    let gleamData = $state(null);
    let gleamLoading = $state(false);
    /** @type {any} */
    let pipelineData = $state(null);
    let pipelineLoading = $state(false);
    /** @type {any} */
    let riskData = $state(null);
    let riskLoading = $state(false);

    async function runGleam() {
        gleamLoading = true;
        try {
            const [valid_ok, valid_err, contract] = await Promise.all([
                fetch(
                    "http://localhost:4001/api/gleam/validate?service=risk&score=750&grade=A",
                ).then((x) => x.json()),
                fetch(
                    "http://localhost:4001/api/gleam/validate?service=risk&score=1500&grade=X",
                ).then((x) => x.json()),
                fetch("http://localhost:4001/api/gleam/contract").then((x) =>
                    x.json(),
                ),
            ]);
            gleamData = { valid_ok, valid_err, contract };
        } catch {
            gleamData = { error: "Gleam 서버 접속 불가 (:4001)" };
        } finally {
            gleamLoading = false;
        }
    }

    async function runGleamPipeline() {
        pipelineLoading = true;
        try {
            pipelineData = await fetch(
                "http://localhost:4001/api/gleam/pipeline?n=252&mu=0.05&sigma=0.18",
            ).then((x) => x.json());
        } catch {
            pipelineData = { error: "Gleam 서버 접속 불가 (:4001)" };
        } finally {
            pipelineLoading = false;
        }
    }

    async function runGleamRisk() {
        riskLoading = true;
        try {
            riskData = await fetch(
                "http://localhost:4001/api/gleam/risk?n=252&mu=0.05&sigma=0.18",
            ).then((x) => x.json());
        } catch {
            riskData = { error: "Gleam 서버 접속 불가 (:4001)" };
        } finally {
            riskLoading = false;
        }
    }
</script>

<section class="panel gleam-panel">
    <div class="panel-header">
        <div>
            <h2>Gleam 1.15 · BEAM/Erlang · 서비스 계약 검증 레이어 (:4001)</h2>
            <p class="subtitle">
                ServiceMessage 모든 variant — exhaustive case 컴파일 강제
            </p>
        </div>
        <div class="gleam-btn-group">
            <button
                class="gleam-btn"
                onclick={runGleam}
                disabled={gleamLoading}
            >
                {gleamLoading ? "검증 중..." : "계약 검증"}
            </button>
            <button
                class="gleam-btn"
                onclick={runGleamPipeline}
                disabled={pipelineLoading}
            >
                {pipelineLoading ? "실행 중..." : "파이프라인"}
            </button>
            <button
                class="gleam-btn"
                onclick={runGleamRisk}
                disabled={riskLoading}
            >
                {riskLoading ? "계산 중..." : "리스크 지표"}
            </button>
        </div>
    </div>

    {#if gleamData}
        {#if gleamData.error}
            <div class="empty-box">
                <p style="color:#f87171">{gleamData.error}</p>
            </div>
        {:else}
            <p class="section-label">계약 검증</p>
            <div class="julia-grid">
                <div class="julia-card gleam-card">
                    <span class="jlabel">✅ 정상 검증 (score=750)</span>
                    <span class="jval" style="color:#34d399"
                        >{gleamData.valid_ok?.ok ? "OK" : "FAIL"}</span
                    >
                </div>
                <div class="julia-card gleam-card">
                    <span class="jlabel">❌ 오류 검증 (score=1500)</span>
                    <span class="jval" style="color:#f87171"
                        >{gleamData.valid_err?.error ?? "?"}</span
                    >
                </div>
                <div class="julia-card gleam-card">
                    <span class="jlabel">메시지 타입 수</span>
                    <span class="jval"
                        >{gleamData.contract?.message_types?.length ??
                            0}개</span
                    >
                </div>
                <div class="julia-card gleam-card">
                    <span class="jlabel">보장</span>
                    <span class="jval"
                        >{gleamData.contract?.guarantee ?? "?"}</span
                    >
                </div>
            </div>
        {/if}
    {/if}

    {#if pipelineData}
        {#if pipelineData.error}
            <div class="empty-box">
                <p style="color:#f87171">{pipelineData.error}</p>
            </div>
        {:else}
            <p class="section-label">데이터 파이프라인 (n={pipelineData.n})</p>
            <div class="julia-grid">
                <div class="julia-card gleam-card">
                    <span class="jlabel">연간 수익률</span>
                    <span class="jval" style="color:#34d399">
                        {((pipelineData.annualized_return ?? 0) * 100).toFixed(
                            2,
                        )}%
                    </span>
                </div>
                <div class="julia-card gleam-card">
                    <span class="jlabel">연간 변동성</span>
                    <span class="jval" style="color:#f59e0b">
                        {((pipelineData.annualized_vol ?? 0) * 100).toFixed(2)}%
                    </span>
                </div>
            </div>
            <div class="pipeline-table">
                <div class="pipeline-row pipeline-header">
                    <span>단계</span><span>건수</span><span>평균</span><span
                        >표준편차</span
                    >
                </div>
                {#each pipelineData.pipeline_steps ?? [] as step}
                    <div class="pipeline-row">
                        <span class="step-name">{step.name}</span>
                        <span>{step.count}</span>
                        <span>{(step.mean ?? 0).toFixed(4)}</span>
                        <span>{(step.std ?? 0).toFixed(4)}</span>
                    </div>
                {/each}
            </div>
        {/if}
    {/if}

    {#if riskData}
        {#if riskData.error}
            <div class="empty-box">
                <p style="color:#f87171">{riskData.error}</p>
            </div>
        {:else}
            <p class="section-label">리스크 지표 (n={riskData.n})</p>
            <div class="julia-grid">
                <div class="julia-card gleam-card">
                    <span class="jlabel">연간 수익률</span>
                    <span class="jval" style="color:#34d399">
                        {((riskData.annualized_return ?? 0) * 100).toFixed(2)}%
                    </span>
                </div>
                <div class="julia-card gleam-card">
                    <span class="jlabel">연간 변동성</span>
                    <span class="jval" style="color:#f59e0b">
                        {((riskData.annualized_vol ?? 0) * 100).toFixed(2)}%
                    </span>
                </div>
                <div class="julia-card gleam-card" style="border-color:#f87171">
                    <span class="jlabel">VaR 95%</span>
                    <span class="jval" style="color:#f87171">
                        {((riskData.var_95 ?? 0) * 100).toFixed(2)}%
                    </span>
                </div>
                <div class="julia-card gleam-card" style="border-color:#f87171">
                    <span class="jlabel">CVaR 95%</span>
                    <span class="jval" style="color:#f87171">
                        {((riskData.cvar_95 ?? 0) * 100).toFixed(2)}%
                    </span>
                </div>
                <div class="julia-card gleam-card" style="border-color:#60a5fa">
                    <span class="jlabel">Sharpe Ratio</span>
                    <span class="jval" style="color:#60a5fa">
                        {(riskData.sharpe_ratio ?? 0).toFixed(3)}
                    </span>
                </div>
                <div class="julia-card gleam-card" style="border-color:#fb923c">
                    <span class="jlabel">Max Drawdown</span>
                    <span class="jval" style="color:#fb923c">
                        {((riskData.max_drawdown ?? 0) * 100).toFixed(2)}%
                    </span>
                </div>
            </div>
        {/if}
    {/if}

    {#if !gleamData && !pipelineData && !riskData}
        <div class="empty-box">
            <p>
                버튼을 눌러 Gleam 계약 검증 / 파이프라인 / 리스크 지표를
                실행하세요. (Gleam 서버 :4001 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .gleam-btn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
    }
    .gleam-btn {
        background: linear-gradient(135deg, #ffaff3 0%, #a855f7 100%);
        color: #1a0030;
        border: none;
        padding: 0.6rem 1.2rem;
        border-radius: 8px;
        cursor: pointer;
        font-weight: 700;
    }
    .gleam-btn:hover:not(:disabled) {
        filter: brightness(1.1);
    }
    .gleam-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .gleam-card {
        border-color: #a855f7 !important;
    }
    .section-label {
        font-size: 0.75rem;
        color: #a855f7;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        margin: 1rem 0 0.4rem;
        font-weight: 600;
    }
    .pipeline-table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 0.5rem;
        font-size: 0.82rem;
    }
    .pipeline-row {
        display: grid;
        grid-template-columns: 2fr 1fr 1fr 1fr;
        padding: 0.35rem 0.6rem;
        border-bottom: 1px solid rgba(168, 85, 247, 0.15);
    }
    .pipeline-row:last-child {
        border-bottom: none;
    }
    .pipeline-header {
        color: #a855f7;
        font-weight: 600;
        font-size: 0.75rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        background: rgba(168, 85, 247, 0.08);
        border-radius: 4px 4px 0 0;
    }
    .step-name {
        color: #e2e8f0;
        font-family: monospace;
    }
    .gleam-panel {
        /* inherits .panel from global */
    }
</style>
