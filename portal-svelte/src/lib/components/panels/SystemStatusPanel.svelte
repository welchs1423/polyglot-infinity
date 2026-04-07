<script>
    import { onDestroy } from "svelte";

    /** @type {{ onSync?: () => void }} */
    let { onSync } = $props();

    /** @type {any} */
    let systemData = $state(null);
    /** @type {string | null} */
    let errorMsg = $state(null);
    /** @type {boolean} */
    let autoSync = $state(false);
    /** @type {number | null} */
    let autoSyncInterval = $state(null);
    /** @type {any | null} */
    let aggregateData = $state(null);
    let aggregateLoading = $state(false);

    async function syncSystem() {
        try {
            const res = await fetch("http://localhost:8080/api/status");
            if (!res.ok) throw new Error("System Offline");
            systemData = await res.json();
            errorMsg = null;
            onSync?.();
        } catch (err) {
            errorMsg = err instanceof Error ? err.message : "Unknown Error";
            systemData = null;
        }
    }

    async function runAggregate() {
        aggregateLoading = true;
        aggregateData = null;
        try {
            const res = await fetch("http://localhost:8080/api/aggregate");
            if (res.ok) aggregateData = await res.json();
            else aggregateData = { error: "Go 허브 오프라인" };
        } catch {
            aggregateData = { error: "Go 허브 접속 불가 (:8080)" };
        } finally {
            aggregateLoading = false;
        }
    }

    function toggleAutoSync() {
        autoSync = !autoSync;
        if (autoSync) {
            syncSystem();
            autoSyncInterval = setInterval(syncSystem, 10000);
        } else {
            if (autoSyncInterval !== null) clearInterval(autoSyncInterval);
            autoSyncInterval = null;
        }
    }

    onDestroy(() => {
        if (autoSyncInterval !== null) clearInterval(autoSyncInterval);
    });
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>System Status</h2>
            <p class="subtitle">Svelte 5 ↔ Go ↔ Python ↔ Rust ↔ DB</p>
        </div>
        <div class="btn-group">
            <button
                class="auto-btn {autoSync ? 'active' : ''}"
                onclick={toggleAutoSync}
            >
                {autoSync ? "⏸ Auto-Sync ON" : "▶ Auto-Sync"}
            </button>
            <button class="sync-btn" onclick={syncSystem}>Sync System</button>
            <button
                class="agg-btn"
                onclick={runAggregate}
                disabled={aggregateLoading}
            >
                {aggregateLoading ? "스캔 중..." : "전체 헬스체크"}
            </button>
        </div>
    </div>

    {#if errorMsg}
        <div class="error-box">
            <p>⚠️ {errorMsg}</p>
        </div>
    {:else if systemData}
        <div class="card-grid">
            <div class="status-card">
                <h3>🏹 Go (Backend)</h3>
                <p class="status online">● {systemData.status}</p>
                <span class="version">{systemData.system}</span>
            </div>

            <div class="status-card">
                <h3>🗄️ PostgreSQL / Redis</h3>
                <p
                    class="status {systemData.database === 'connected'
                        ? 'online'
                        : 'error'}"
                >
                    ● {systemData.database}
                </p>
                <span class="version">Data & Cache Layer</span>
            </div>

            <div class="status-card">
                <h3>🐍 Python (Engine)</h3>
                {#if systemData.engine_analysis.version}
                    <p class="status online">● online</p>
                    <span class="version"
                        >{systemData.engine_analysis.version}</span
                    >
                    <div class="badge">{systemData.engine_analysis.source}</div>
                    <div class="financial-data">
                        <p class="rate">
                            💸 {systemData.engine_analysis.recommendation}
                        </p>
                        {#if systemData.engine_analysis.rates}
                            <div class="currency-grid">
                                {#each Object.entries(systemData.engine_analysis.rates) as [currency, value]}
                                    <span class="currency-chip"
                                        >{currency}: {typeof value === "number"
                                            ? value.toFixed(2)
                                            : value}</span
                                    >
                                {/each}
                            </div>
                        {/if}
                        <p class="risk">
                            ⚠️ Risk Score: {systemData.engine_analysis
                                .computation_result}
                        </p>
                    </div>
                {:else}
                    <p class="status error">● Offline</p>
                {/if}
            </div>

            <div class="status-card">
                <h3>⚡ Zig (Core)</h3>
                {#if systemData.engine_analysis?.zig_analysis?.engine}
                    <p class="status online">● online</p>
                    <span class="version"
                        >{systemData.engine_analysis.zig_analysis.engine}</span
                    >
                    <div class="financial-data">
                        <p class="rate">
                            σ {systemData.engine_analysis.zig_analysis
                                .volatility}
                        </p>
                        <p class="risk">
                            VaR 95%: ₩{systemData.engine_analysis.zig_analysis.var_95?.toLocaleString()}
                        </p>
                    </div>
                {:else}
                    <p class="status error">● Offline</p>
                {/if}
            </div>

            <div class="status-card">
                <h3>🦀 Rust (Pipeline)</h3>
                {#if systemData.pipeline_node.status === "online"}
                    <p class="status online">
                        ● {systemData.pipeline_node.status}
                    </p>
                    <span class="version"
                        >{systemData.pipeline_node.module}</span
                    >
                    {#if systemData.pipeline_node.total_risk_logs !== undefined}
                        <span class="version"
                            >DB records: {systemData.pipeline_node.total_risk_logs.toLocaleString()}</span
                        >
                    {/if}
                {:else}
                    <p class="status error">● Offline</p>
                {/if}
            </div>
        </div>
    {:else}
        <div class="empty-box">
            <p>우측 상단의 Sync System 버튼을 눌러 전체 시스템을 스캔하세요.</p>
        </div>
    {/if}

    <!-- 전체 헬스체크 집계 -->
    {#if aggregateData}
        {#if aggregateData.error}
            <div class="empty-box" style="margin-top:0.75rem">
                <p style="color:#f87171">{aggregateData.error}</p>
            </div>
        {:else}
            <div class="agg-header">
                <span
                    >🔍 전체 백엔드 헬스체크 — <strong style="color:#34d399"
                        >{aggregateData.online}</strong
                    >
                    / {aggregateData.total} online</span
                >
                <span class="agg-engine">{aggregateData.engine}</span>
            </div>
            <div class="agg-grid">
                {#each aggregateData.services ?? [] as svc}
                    <div
                        class="agg-item {svc.status === 'online'
                            ? 'agg-on'
                            : 'agg-off'}"
                    >
                        <span class="agg-dot"
                            >{svc.status === "online" ? "●" : "○"}</span
                        >
                        <span class="agg-name">{svc.name}</span>
                        <span class="agg-port">:{svc.port}</span>
                        <span class="agg-ms">{svc.latency_ms}ms</span>
                    </div>
                {/each}
            </div>
        {/if}
    {/if}
</section>

<style>
    .agg-btn {
        background: #1e293b;
        color: #38bdf8;
        border: 1px solid #38bdf8;
        padding: 0.6rem 1.1rem;
        border-radius: 8px;
        font-weight: 700;
        cursor: pointer;
        font-size: 0.85rem;
        transition: background 0.2s;
    }
    .agg-btn:hover:not(:disabled) {
        background: #0f2a3f;
    }
    .agg-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .agg-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        font-size: 0.82rem;
        color: #94a3b8;
        margin: 0.75rem 0 0.4rem;
        padding: 0.4rem 0;
        border-top: 1px solid #1e293b;
    }
    .agg-engine {
        color: #475569;
        font-style: italic;
    }
    .agg-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
        gap: 0.3rem;
    }
    .agg-item {
        display: flex;
        align-items: center;
        gap: 0.4rem;
        padding: 0.3rem 0.5rem;
        border-radius: 6px;
        font-size: 0.78rem;
        font-family: monospace;
        background: #0f172a;
        border: 1px solid #1e293b;
    }
    .agg-on .agg-dot {
        color: #34d399;
    }
    .agg-off .agg-dot {
        color: #475569;
    }
    .agg-on .agg-name {
        color: #e2e8f0;
    }
    .agg-off .agg-name {
        color: #475569;
    }
    .agg-port {
        color: #64748b;
    }
    .agg-ms {
        color: #475569;
        margin-left: auto;
        font-size: 0.72rem;
    }
    .agg-on .agg-ms {
        color: #38bdf8;
    }
</style>
