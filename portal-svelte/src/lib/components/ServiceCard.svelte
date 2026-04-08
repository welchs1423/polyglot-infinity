<script>
    // Props:
    //   name       - Service display name (e.g. "Go-Hub")
    //   lang       - Programming language label shown in the badge (e.g. "Go")
    //   port       - Port number the service listens on
    //   status     - "online" | "offline" | "loading"
    //   latencyMs  - Round-trip latency in milliseconds, or null when unknown
    //   result     - Short summary string for the core computation result, or null
    //   role       - Single-line role description (e.g. "VaR Risk Pipeline")

    /** @type {{ name: string, lang: string, port: number, status: string, latencyMs: number | null, result: string | null, role: string }} */
    let { name, lang, port, status, latencyMs, result, role } = $props();
</script>

<article
    class="card"
    class:card-online={status === "online"}
    class:card-offline={status === "offline"}
    class:card-loading={status === "loading"}
>
    <header class="card-header">
        <div class="name-row">
            <span class="lang-badge">{lang}</span>
            <span class="card-name">{name}</span>
        </div>
        <div class="status-row">
            <span class="status-dot" aria-hidden="true"></span>
            <span class="status-text">{status}</span>
            {#if latencyMs !== null && status === "online"}
                <span class="latency">{latencyMs}ms</span>
            {/if}
        </div>
    </header>

    <div class="card-body">
        <p class="role">{role}</p>
        <p class="port">:{port}</p>
        {#if result}
            <p class="result" title={result}>{result}</p>
        {:else if status === "loading"}
            <p class="result result-dim">checking…</p>
        {:else}
            <p class="result result-dim">—</p>
        {/if}
    </div>
</article>

<style>
    .card {
        background: #1e293b;
        border: 1px solid #334155;
        border-radius: 10px;
        padding: 1rem 1.2rem;
        display: flex;
        flex-direction: column;
        gap: 0.65rem;
        transition:
            border-color 0.2s ease,
            box-shadow 0.2s ease;
        min-height: 140px;
    }

    .card-online {
        border-color: #22c55e44;
        box-shadow: 0 0 0 1px #22c55e18;
    }

    .card-offline {
        border-color: #ef444433;
        opacity: 0.72;
    }

    .card-loading {
        border-color: #f59e0b33;
    }

    .card-header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 0.5rem;
    }

    .name-row {
        display: flex;
        align-items: center;
        gap: 0.45rem;
        flex-wrap: wrap;
    }

    .lang-badge {
        background: #0f172a;
        border: 1px solid #475569;
        border-radius: 4px;
        font-size: 0.62rem;
        font-weight: 700;
        letter-spacing: 0.05em;
        padding: 0.1rem 0.45rem;
        color: #94a3b8;
        text-transform: uppercase;
        white-space: nowrap;
    }

    .card-name {
        font-size: 0.84rem;
        font-weight: 600;
        color: #e2e8f0;
        white-space: nowrap;
    }

    .status-row {
        display: flex;
        align-items: center;
        gap: 0.32rem;
        flex-shrink: 0;
    }

    .status-dot {
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: #64748b;
        flex-shrink: 0;
    }

    .card-online .status-dot {
        background: #22c55e;
        box-shadow: 0 0 5px #22c55e88;
        animation: pulse 2.2s ease-in-out infinite;
    }

    .card-offline .status-dot {
        background: #ef4444;
    }

    .card-loading .status-dot {
        background: #f59e0b;
        animation: blink 1s step-start infinite;
    }

    @keyframes pulse {
        0%,
        100% {
            opacity: 1;
        }
        50% {
            opacity: 0.4;
        }
    }

    @keyframes blink {
        0%,
        100% {
            opacity: 1;
        }
        50% {
            opacity: 0;
        }
    }

    .status-text {
        font-size: 0.68rem;
        font-weight: 600;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        color: #64748b;
    }

    .card-online .status-text {
        color: #86efac;
    }
    .card-offline .status-text {
        color: #fca5a5;
    }
    .card-loading .status-text {
        color: #fde68a;
    }

    .latency {
        font-size: 0.62rem;
        color: #475569;
        margin-left: 0.1rem;
    }

    .card-body {
        display: flex;
        flex-direction: column;
        gap: 0.2rem;
    }

    .role {
        margin: 0;
        font-size: 0.7rem;
        color: #64748b;
        text-transform: uppercase;
        letter-spacing: 0.07em;
        font-weight: 500;
    }

    .port {
        margin: 0;
        font-size: 0.73rem;
        color: #475569;
        font-family: "Consolas", "Fira Code", monospace;
    }

    .result {
        margin: 0.2rem 0 0;
        font-size: 0.8rem;
        color: #cbd5e1;
        font-family: "Consolas", "Fira Code", monospace;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }

    .result-dim {
        color: #475569;
    }
</style>
