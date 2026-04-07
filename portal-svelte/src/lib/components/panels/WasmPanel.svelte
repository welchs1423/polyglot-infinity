<script>
    /** @type {any} */
    let wasmExports = null;
    /** @type {boolean} */
    let wasmLoaded = $state(false);
    /** @type {any | null} */
    let wasmBsResult = $state(null);
    /** @type {boolean} */
    let wasmLoading = $state(false);

    async function runWasm() {
        wasmLoading = true;
        try {
            if (!wasmExports) {
                const res = await fetch("/finance.wasm");
                const bytes = await res.arrayBuffer();
                const { instance } = await WebAssembly.instantiate(bytes, {});
                wasmExports = instance.exports;
                wasmLoaded = true;
            }
            const exp = wasmExports;
            wasmBsResult = {
                call: exp.bsCall(100, 100, 0.05, 0.2, 1.0),
                put: exp.bsPut(100, 100, 0.05, 0.2, 1.0),
                delta: exp.bsDelta(100, 100, 0.05, 0.2, 1.0),
                gamma: exp.bsGamma(100, 100, 0.05, 0.2, 1.0),
                var95: exp.varNormal(0.0005, 0.018, 0.95),
                dcf: exp.dcfValue(1_000_000, 0.1, 0.03, 0.08, 5),
            };
        } catch (e) {
            wasmBsResult = { error: String(e) };
        } finally {
            wasmLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🕸️ WebAssembly (Client-side)</h2>
            <p class="subtitle">
                Zig → WASM32 · 브라우저 직접 실행 · 서버 왕복 없음
            </p>
        </div>
        <button class="wasm-btn" onclick={runWasm} disabled={wasmLoading}>
            {#if wasmLoading}계산 중...{:else if wasmLoaded}재계산{:else}WASM
                로드 & 실행{/if}
        </button>
    </div>
    {#if wasmBsResult}
        {#if wasmBsResult.error}
            <div class="empty-box">
                <p style="color:#f87171">{wasmBsResult.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card wasm-card">
                    <span class="jlabel">Call Price</span><span class="jval"
                        >${wasmBsResult.call.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Put Price</span><span class="jval"
                        >${wasmBsResult.put.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Delta</span><span class="jval"
                        >{wasmBsResult.delta.toFixed(4)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">Gamma</span><span class="jval"
                        >{wasmBsResult.gamma.toFixed(6)}</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">VaR 95%</span><span class="jval"
                        >{(wasmBsResult.var95 * 100).toFixed(3)}%</span
                    >
                </div>
                <div class="julia-card wasm-card">
                    <span class="jlabel">DCF Value</span><span class="jval"
                        >₩{Math.round(wasmBsResult.dcf).toLocaleString()}</span
                    >
                </div>
            </div>
            <p class="wasm-hint">
                ✓ 서버 없이 브라우저에서 직접 계산됨 (S=100 K=100 r=5% σ=20%
                T=1y)
            </p>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                Zig로 컴파일된 WASM을 브라우저에서 직접 실행합니다. 서버 없이
                Black-Scholes · VaR · DCF 계산.
            </p>
        </div>
    {/if}
</section>

<style>
    .wasm-btn {
        background: linear-gradient(135deg, #06b6d4, #0e7490);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .wasm-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #0891b2, #065f6e);
    }
    .wasm-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .wasm-card {
        border-color: #06b6d4 !important;
    }
    .wasm-hint {
        margin-top: 0.75rem;
        font-size: 0.8rem;
        color: #67e8f9;
        text-align: center;
    }
</style>
