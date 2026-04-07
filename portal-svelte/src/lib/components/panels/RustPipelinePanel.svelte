<script>
    /** @type {{ onTrigger?: () => void }} */
    let { onTrigger } = $props();

    /** @type {{ status: string, inserted_rows?: number, elapsed_time_ms?: number, message?: string } | null} */
    let pipelineResult = $state(null);
    /** @type {boolean} */
    let pipelineLoading = $state(false);

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
        } catch {
            pipelineResult = {
                status: "error",
                message: "Rust Pipeline unreachable",
            };
        } finally {
            pipelineLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🦀 Rust Pipeline</h2>
            <p class="subtitle">10,000건 리스크 데이터 DB 일괄 적재</p>
        </div>
        <button
            class="trigger-btn"
            onclick={triggerPipeline}
            disabled={pipelineLoading}
        >
            {pipelineLoading ? "⏳ Running..." : "🚀 Trigger Bulk Insert"}
        </button>
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
    {:else}
        <div class="empty-box">
            <p>버튼을 눌러 Rust 파이프라인을 가동하세요.</p>
        </div>
    {/if}
</section>
