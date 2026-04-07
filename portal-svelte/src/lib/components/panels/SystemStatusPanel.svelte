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
    /** @type {EventSource | null} */
    let sseSource = $state(null);
    let sseConnected = $state(false);
    /** @type {any | null} */
    let reportData = $state(null);
    let reportLoading = $state(false);

    async function runReport() {
        reportLoading = true;
        try {
            const res = await fetch("http://localhost:8080/api/report");
            if (res.ok) reportData = await res.json();
            else reportData = { error: "리포트 생성 실패" };
        } catch {
            reportData = { error: "Go 허브 접속 불가 (:8080)" };
        } finally {
            reportLoading = false;
        }
    }

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

    function toggleSSE() {
        if (sseConnected) {
            sseSource?.close();
            sseSource = null;
            sseConnected = false;
        } else {
            sseSource = new EventSource("http://localhost:8080/api/aggregate/stream");
            sseConnected = true;
            sseSource.onmessage = (e) => {
                try { aggregateData = JSON.parse(e.data); } catch { /* ignore */ }
            };
            sseSource.onerror = () => {
                sseConnected = false;
                sseSource?.close();
                sseSource = null;
            };
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
        sseSource?.close();
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
                class="agg-btn {sseConnected ? 'sse-active' : ''}"
                onclick={toggleSSE}
            >
                {sseConnected ? "🟢 Live 스트림 중지" : "전체 헬스체크 (SSE)"}
            </button>
            <button
                class="report-btn"
                onclick={runReport}
                disabled={reportLoading}
            >
                {reportLoading ? "리포트 생성 중..." : "통합 리포트"}
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

    <!-- 통합 리스크 리포트 -->
    {#if reportData}
        <div class="report-section">
            <div class="report-header">
                📋 통합 리스크 리포트
                <span class="report-time"
                    >{reportData.generated_at
                        ?.slice(0, 19)
                        .replace("T", " ")}</span
                >
            </div>
            {#if reportData.error}
                <p style="color:#f87171;font-size:0.85rem">
                    {reportData.error}
                </p>
            {:else}
                <div class="report-grid">
                    <!-- Rust Risk -->
                    {#if reportData.rust_risk && !reportData.rust_risk.status}
                        <div class="report-card">
                            <span class="rc-label">🦀 Rust Risk</span>
                            <span class="rc-val"
                                >{reportData.rust_risk.count ?? "—"} logs</span
                            >
                            <span class="rc-sub"
                                >avg VaR {reportData.rust_risk.avg_var?.toFixed(
                                    4,
                                ) ?? "—"}</span
                            >
                        </div>
                    {:else}
                        <div class="report-card offline">
                            <span class="rc-label">🦀 Rust Risk</span><span
                                class="rc-val">offline</span
                            >
                        </div>
                    {/if}
                    <!-- Python -->
                    {#if reportData.python_analysis?.version}
                        <div class="report-card">
                            <span class="rc-label">🐍 Python</span>
                            <span class="rc-val"
                                >{reportData.python_analysis.recommendation ??
                                    "online"}</span
                            >
                            <span class="rc-sub"
                                >{reportData.python_analysis.source ?? ""}</span
                            >
                        </div>
                    {:else}
                        <div class="report-card offline">
                            <span class="rc-label">🐍 Python</span><span
                                class="rc-val">offline</span
                            >
                        </div>
                    {/if}
                    <!-- Julia MC -->
                    {#if reportData.julia_mc?.var_95 !== undefined}
                        <div class="report-card">
                            <span class="rc-label">🟣 Julia MC</span>
                            <span class="rc-val"
                                >VaR {reportData.julia_mc.var_95?.toFixed(
                                    3,
                                )}</span
                            >
                            <span class="rc-sub"
                                >CVaR {reportData.julia_mc.cvar_95?.toFixed(
                                    3,
                                ) ?? "—"}</span
                            >
                        </div>
                    {:else}
                        <div class="report-card offline">
                            <span class="rc-label">🟣 Julia MC</span><span
                                class="rc-val">offline</span
                            >
                        </div>
                    {/if}
                    <!-- R Stats -->
                    {#if reportData.r_stats?.mean !== undefined}
                        <div class="report-card">
                            <span class="rc-label">📊 R Stats</span>
                            <span class="rc-val"
                                >μ={reportData.r_stats.mean?.toFixed(4)}</span
                            >
                            <span class="rc-sub"
                                >VaR {reportData.r_stats.var_95?.toFixed(4) ??
                                    "—"}</span
                            >
                        </div>
                    {:else}
                        <div class="report-card offline">
                            <span class="rc-label">📊 R Stats</span><span
                                class="rc-val">offline</span
                            >
                        </div>
                    {/if}
                    <!-- OCaml -->
                    {#if reportData.ocaml_risk?.score !== undefined || reportData.ocaml_risk?.risk_level}
                        <div class="report-card">
                            <span class="rc-label">🐪 OCaml</span>
                            <span class="rc-val"
                                >{reportData.ocaml_risk.risk_level ?? "—"}</span
                            >
                            <span class="rc-sub"
                                >score {reportData.ocaml_risk.score?.toFixed(
                                    3,
                                ) ?? "—"}</span
                            >
                        </div>
                    {:else}
                        <div class="report-card offline">
                            <span class="rc-label">🐪 OCaml</span><span
                                class="rc-val">offline</span
                            >
                        </div>
                    {/if}
                    <!-- Haskell -->
                    {#if reportData.haskell_mc?.var_95 !== undefined}
                        <div class="report-card">
                            <span class="rc-label">λ Haskell</span>
                            <span class="rc-val"
                                >VaR {reportData.haskell_mc.var_95?.toFixed(
                                    3,
                                )}</span
                            >
                            <span class="rc-sub"
                                >CVaR {reportData.haskell_mc.cvar_95?.toFixed(
                                    3,
                                ) ?? "—"}</span
                            >
                        </div>
                    {:else}
                        <div class="report-card offline">
                            <span class="rc-label">λ Haskell</span><span
                                class="rc-val">offline</span
                            >
                        </div>
                    {/if}
                </div>
            {/if}
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
                    >{sseConnected ? "🟢 실시간 스트림" : "🔍 전체 백엔드 헬스체크"} — <strong style="color:#34d399"
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
    .agg-btn.sse-active {
        background: #052e16;
        color: #34d399;
        border-color: #34d399;
    }
    .agg-btn.sse-active:hover {
        background: #064e3b;
    }
    .report-btn {
        background: #1e293b;
        color: #a78bfa;
        border: 1px solid #7c3aed;
        padding: 0.6rem 1.1rem;
        border-radius: 8px;
        font-weight: 700;
        cursor: pointer;
        font-size: 0.85rem;
        transition: background 0.2s;
    }
    .report-btn:hover:not(:disabled) {
        background: #2e1065;
    }
    .report-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .report-section {
        margin-top: 0.75rem;
        border: 1px solid #4c1d95;
        border-radius: 8px;
        padding: 0.75rem 1rem;
        background: #0f0f1e;
    }
    .report-header {
        font-size: 0.82rem;
        color: #a78bfa;
        font-weight: bold;
        margin-bottom: 0.6rem;
        display: flex;
        justify-content: space-between;
        align-items: center;
    }
    .report-time {
        color: #64748b;
        font-family: monospace;
        font-size: 0.75rem;
        font-weight: normal;
    }
    .report-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
        gap: 0.4rem;
    }
    .report-card {
        background: #1e293b;
        border: 1px solid #312e81;
        border-radius: 6px;
        padding: 0.5rem 0.6rem;
        display: flex;
        flex-direction: column;
        gap: 0.15rem;
    }
    .report-card.offline {
        opacity: 0.4;
        border-color: #1e293b;
    }
    .rc-label {
        font-size: 0.72rem;
        color: #94a3b8;
    }
    .rc-val {
        font-size: 0.9rem;
        color: #e2e8f0;
        font-weight: 700;
    }
    .rc-sub {
        font-size: 0.7rem;
        color: #64748b;
        font-family: monospace;
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
