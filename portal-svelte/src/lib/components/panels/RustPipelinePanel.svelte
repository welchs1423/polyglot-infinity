<script>
    import { onMount } from "svelte";

    /** @type {{ onTrigger?: () => void }} */
    let { onTrigger } = $props();

    /** @type {{ status: string, inserted_rows?: number, elapsed_time_ms?: number, message?: string } | null} */
    let pipelineResult = $state(null);
    /** @type {any | null} */
    let riskSummary = $state(null);
    /** @type {any | null} */
    let rustStatus = $state(null);
    /** @type {boolean} */
    let pipelineLoading = $state(false);
    /** @type {boolean} */
    let summaryLoading = $state(false);

    async function fetchRustStatus() {
        try {
            const res = await fetch("http://localhost:8081/api/rust/status");
            if (res.ok) rustStatus = await res.json();
        } catch {
            rustStatus = null;
        }
    }

    onMount(() => { fetchRustStatus(); });

    async function triggerPipeline() {
        pipelineLoading = true;
        pipelineResult = null;
        try {
            const res = await fetch(
                "http://localhost:8080/api/pipeline/trigger",
                { method: "POST" },
            );
            pipelineResult = await res.json();
            onTrigger?.();
            await fetchRustStatus();
        } catch {
            pipelineResult = {
                status: "error",
                message: "Rust Pipeline unreachable",
            };
        } finally {
            pipelineLoading = false;
        }
    }

    async function fetchRiskSummary() {
        summaryLoading = true;
        riskSummary = null;
        try {
            const res = await fetch("http://localhost:8081/api/risk/summary");
            if (res.ok) riskSummary = await res.json();
            else riskSummary = { error: "Rust 서버 오프라인" };
        } catch {
            riskSummary = { error: "Rust 서버 접속 불가 (:8081)" };
        } finally {
            summaryLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🦀 Rust Pipeline</h2>
            <p class="subtitle">
                10,000건 리스크 DB 적재 · VaR(95%) 통계 (:8081)
            </p>
            {#if rustStatus}
                <p class="db-badge">
                    <span class="db-dot"></span>
                    DB {rustStatus.total_risk_logs?.toLocaleString() ?? 0}행 · {rustStatus.module ?? rustStatus.status}
                </p>
            {/if}
        </div>
        <div class="btn-group">
            <button
                class="trigger-btn"
                onclick={triggerPipeline}
                disabled={pipelineLoading}
            >
                {pipelineLoading ? "⏳ Running..." : "🚀 Bulk Insert"}
            </button>
            <button
                class="summary-btn"
                onclick={fetchRiskSummary}
                disabled={summaryLoading}
            >
                {summaryLoading ? "조회 중..." : "VaR 통계"}
            </button>
        </div>
    </div>

    {#if pipelineResult}
        {#if pipelineResult.status === "success"}
            <div class="pipeline-result success">
                <span class="result-icon">✅</span>
                <span
                    ><strong
                        >{pipelineResult.inserted_rows?.toLocaleString()}</strong
                    >건 적재 완료</span
                >
                <span class="result-time"
                    >⏱ {pipelineResult.elapsed_time_ms}ms</span
                >
            </div>
        {:else}
            <div class="pipeline-result error-result">
                <span class="result-icon">❌</span>
                <span>{pipelineResult.message ?? "Unknown error"}</span>
            </div>
        {/if}
    {:else if !riskSummary}
        <div class="empty-box">
            <p>Bulk Insert로 데이터를 적재하거나 VaR 통계를 조회하세요.</p>
        </div>
    {/if}

    {#if riskSummary}
        {#if riskSummary.error}
            <div class="pipeline-result error-result">
                <span class="result-icon">❌</span>
                <span>{riskSummary.error}</span>
            </div>
        {:else}
            <div class="julia-grid" style="margin-top:0.75rem">
                <div class="julia-card rust-card">
                    <span class="jlabel">총 레코드</span><span class="jval"
                        >{Number(riskSummary.count).toLocaleString()}</span
                    >
                </div>
                <div class="julia-card rust-card">
                    <span class="jlabel">VaR 평균</span><span class="jval"
                        >{riskSummary.avg_var?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card rust-card">
                    <span class="jlabel">VaR 최소</span><span class="jval"
                        >{riskSummary.min_var?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card rust-card">
                    <span class="jlabel">VaR 최대</span><span class="jval"
                        >{riskSummary.max_var?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card rust-card" style="border-color:#f59e0b">
                    <span class="jlabel">VaR P95</span><span
                        class="jval"
                        style="color:#f59e0b"
                        >{riskSummary.p95_var?.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card rust-card" style="border-color:#34d399">
                    <span class="jlabel">엔진</span><span
                        class="jval"
                        style="color:#34d399;font-size:0.7rem"
                        >{riskSummary.engine}</span
                    >
                </div>
            </div>
        {/if}
    {/if}
</section>

<style>
    .btn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
    }
    .trigger-btn {
        background: linear-gradient(135deg, #f97316, #c2410c);
        color: white;
        border: none;
        padding: 0.75rem 1.25rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: filter 0.2s;
    }
    .trigger-btn:hover:not(:disabled) {
        filter: brightness(1.15);
    }
    .trigger-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .summary-btn {
        background: #1e293b;
        color: #f97316;
        border: 1px solid #f97316;
        padding: 0.75rem 1.25rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .summary-btn:hover:not(:disabled) {
        background: #2d3748;
    }
    .summary-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .db-badge {
        display: flex;
        align-items: center;
        gap: 0.35rem;
        margin: 0.25rem 0 0;
        font-size: 0.75rem;
        color: #94a3b8;
    }
    .db-dot {
        display: inline-block;
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: #f97316;
    }
    .pipeline-result {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.75rem 1rem;
        border-radius: 8px;
        margin-top: 0.5rem;
    }
    .success {
        background: #052e16;
        border: 1px solid #16a34a;
    }
    .error-result {
        background: #2d1515;
        border: 1px solid #ef4444;
    }
    .result-icon {
        font-size: 1.2rem;
    }
    .result-time {
        color: #94a3b8;
        font-size: 0.85rem;
        margin-left: auto;
    }
    .rust-card {
        border-color: #f97316 !important;
    }
</style>
