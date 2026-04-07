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
</section>
