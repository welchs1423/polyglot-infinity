<script>
    /** @type {any | null} */
    let result = $state(null);
    let loading = $state(false);

    let bsS = $state(100);
    let bsK = $state(100);
    let bsSigma = $state(0.2);
    let bsT = $state(1.0);
    let bsR = $state(0.05);

    async function runCompare() {
        loading = true;
        result = null;
        try {
            const res = await fetch(
                `http://localhost:8080/api/workflow/option-compare?s=${bsS}&k=${bsK}&sigma=${bsSigma}&t=${bsT}&r=${bsR}`,
            );
            if (res.ok) result = await res.json();
            else result = { error: "Go 워크플로 오프라인" };
        } catch {
            result = { error: "Go 게이트웨이 접속 불가 (:8080)" };
        } finally {
            loading = false;
        }
    }

    /** @param {any} eng */
    function callVal(eng) {
        const d = eng?.data;
        if (!d) return "—";
        return d.call ?? d.call_price ?? d.risk_score ?? "—";
    }
    /** @param {any} eng */
    function putVal(eng) {
        const d = eng?.data;
        if (!d) return "—";
        return d.put ?? d.put_price ?? "—";
    }
    /** @param {any} eng */
    function deltaVal(eng) {
        const d = eng?.data;
        if (!d) return "—";
        return d.delta ?? d.call_delta ?? "—";
    }
    /** @param {any} eng */
    function gammaVal(eng) {
        const d = eng?.data;
        if (!d) return "—";
        return d.gamma ?? "—";
    }

    /** @param {any} eng @returns {string} */
    function statusClass(eng) {
        if (!eng) return "status-unknown";
        return eng.status === "ok" ? "status-ok" : "status-err";
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>⚖️ BS 비교 워크플로 (F# · Haskell · Python)</h2>
            <p class="subtitle">
                Go 오케스트레이션 · 3개 엔진 병렬 Black-Scholes 비교 · 서킷
                브레이커 보호 (:8080 → :9001/:8006/:8000)
            </p>
        </div>
        <button class="run-btn" onclick={runCompare} disabled={loading}>
            {loading ? "비교 중..." : "엔진 비교"}
        </button>
    </div>

    <div class="param-grid">
        <div class="param-row">
            <label for="bs-s">Spot (S)</label>
            <input
                id="bs-s"
                type="range"
                min="50"
                max="200"
                step="5"
                bind:value={bsS}
            />
            <span class="param-val">{bsS}</span>
        </div>
        <div class="param-row">
            <label for="bs-k">Strike (K)</label>
            <input
                id="bs-k"
                type="range"
                min="50"
                max="200"
                step="5"
                bind:value={bsK}
            />
            <span class="param-val">{bsK}</span>
        </div>
        <div class="param-row">
            <label for="bs-sigma">Volatility σ</label>
            <input
                id="bs-sigma"
                type="range"
                min="0.05"
                max="0.80"
                step="0.01"
                bind:value={bsSigma}
            />
            <span class="param-val">{bsSigma.toFixed(2)}</span>
        </div>
        <div class="param-row">
            <label for="bs-t">Maturity T (년)</label>
            <input
                id="bs-t"
                type="range"
                min="0.1"
                max="3.0"
                step="0.1"
                bind:value={bsT}
            />
            <span class="param-val">{bsT.toFixed(1)}</span>
        </div>
        <div class="param-row">
            <label for="bs-r">Risk-free r</label>
            <input
                id="bs-r"
                type="range"
                min="0.00"
                max="0.15"
                step="0.005"
                bind:value={bsR}
            />
            <span class="param-val">{bsR.toFixed(3)}</span>
        </div>
    </div>

    {#if result?.error}
        <p class="error-msg">{result.error}</p>
    {:else if result}
        <p class="meta">
            파라미터: S={result.params?.s} K={result.params?.k} σ={result.params
                ?.sigma}
            T={result.params?.t} r={result.params?.r}
        </p>

        <div class="compare-grid">
            {#each Object.entries(result.engines ?? {}) as [name, eng]}
                <div class="engine-card">
                    <div class="engine-header">
                        <span class="engine-name">{name}</span>
                        <span class="engine-status {statusClass(eng)}">
                            {eng.status === "ok" ? "✓" : "✕"}
                        </span>
                        <span class="engine-latency">{eng.latency_ms}ms</span>
                    </div>
                    {#if eng.status === "ok"}
                        <table class="result-table">
                            <tbody>
                                <tr
                                    ><td class="k">Call</td><td class="v"
                                        >{callVal(eng)}</td
                                    ></tr
                                >
                                <tr
                                    ><td class="k">Put</td><td class="v"
                                        >{putVal(eng)}</td
                                    ></tr
                                >
                                <tr
                                    ><td class="k">Delta</td><td class="v"
                                        >{deltaVal(eng)}</td
                                    ></tr
                                >
                                <tr
                                    ><td class="k">Gamma</td><td class="v"
                                        >{gammaVal(eng)}</td
                                    ></tr
                                >
                            </tbody>
                        </table>
                    {:else}
                        <p class="engine-err">{eng.error ?? "오류"}</p>
                    {/if}
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
    .run-btn {
        background: #1e3a5f;
        color: #60a5fa;
        border: 1px solid #1d4ed8;
        border-radius: 6px;
        padding: 0.45rem 1.1rem;
        cursor: pointer;
        font-size: 0.85rem;
        white-space: nowrap;
        flex-shrink: 0;
    }
    .run-btn:hover:not(:disabled) {
        background: #1d4ed8;
    }
    .run-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .param-grid {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
        margin-bottom: 1rem;
    }
    .param-row {
        display: grid;
        grid-template-columns: 120px 1fr 56px;
        align-items: center;
        gap: 0.6rem;
        font-size: 0.82rem;
        color: #94a3b8;
    }
    .param-val {
        text-align: right;
        font-family: monospace;
        color: #e2e8f0;
        font-size: 0.85rem;
    }

    .meta {
        font-size: 0.78rem;
        color: #64748b;
        margin-bottom: 0.75rem;
        font-family: monospace;
    }

    .compare-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 1rem;
    }
    .engine-card {
        background: #0f172a;
        border: 1px solid #334155;
        border-radius: 8px;
        padding: 0.85rem 1rem;
    }
    .engine-header {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin-bottom: 0.65rem;
    }
    .engine-name {
        font-size: 0.9rem;
        font-weight: 600;
        color: #e2e8f0;
        flex: 1;
    }
    .engine-status {
        font-size: 0.85rem;
        font-weight: 700;
    }
    .status-ok {
        color: #22c55e;
    }
    .status-err {
        color: #ef4444;
    }
    .status-unknown {
        color: #64748b;
    }
    .engine-latency {
        font-family: monospace;
        font-size: 0.75rem;
        color: #64748b;
    }
    .result-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 0.82rem;
    }
    .result-table tr + tr td {
        border-top: 1px solid #1e293b;
    }
    .result-table td {
        padding: 0.3rem 0;
    }
    .result-table td.k {
        color: #94a3b8;
        width: 52px;
    }
    .result-table td.v {
        color: #e2e8f0;
        font-family: monospace;
        text-align: right;
    }
    .engine-err {
        font-size: 0.78rem;
        color: #ef4444;
        margin: 0;
    }
    .error-msg {
        color: #ef4444;
        font-size: 0.85rem;
        margin-top: 0.5rem;
    }
</style>
