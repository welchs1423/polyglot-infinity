<script>
    import { API_BASE } from '$lib/api';
    /** @type {any} */
    let vData = $state(null);
    let vLoading = $state(false);
    let ticks = $state(100000);
    let fastPeriod = $state(20);
    let slowPeriod = $state(50);
    let seed = $state(42);

    async function runV() {
        vLoading = true;
        try {
            const [bt, st] = await Promise.all([
                fetch(
                    `${API_BASE}/api/v/backtest?ticks=${ticks}&fast=${fastPeriod}&slow=${slowPeriod}&seed=${seed}`,
                ).then((x) => x.json()),
                fetch(
                    `${API_BASE}/api/v/stress?ticks=${Math.round(ticks * 1.5)}&seed=${seed}`,
                ).then((x) => x.json()),
            ]);
            vData = { ...bt, stress: st };
        } catch {
            vData = { error: "V 서버 접속 불가 (:4002)" };
        } finally {
            vLoading = false;
        }
    }
</script>

<section class="panel v-panel">
    <h2>V 0.5.1 · Zero-GC 전략 백테스터 (:4002)</h2>
    <p class="subtitle">
        v -gc none 컴파일 → GC 일시정지 물리적 불가 → 결정론적 레이턴시
    </p>
    <button class="v-btn" onclick={runV} disabled={vLoading}>
        {vLoading ? "백테스트 중..." : "전략 백테스트"}
    </button>

    <div class="param-grid">
        <div class="param-row">
            <label for="v-ticks">Ticks</label>
            <input
                id="v-ticks"
                type="range"
                min="10000"
                max="500000"
                step="10000"
                bind:value={ticks}
            />
            <span class="param-val">{(ticks / 1000).toFixed(0)}k</span>
        </div>
        <div class="param-row">
            <label for="v-fast-ma">Fast MA</label>
            <input
                id="v-fast-ma"
                type="range"
                min="3"
                max="50"
                step="1"
                bind:value={fastPeriod}
            />
            <span class="param-val">{fastPeriod}</span>
        </div>
        <div class="param-row">
            <label for="v-slow-ma">Slow MA</label>
            <input
                id="v-slow-ma"
                type="range"
                min="10"
                max="200"
                step="5"
                bind:value={slowPeriod}
            />
            <span class="param-val">{slowPeriod}</span>
        </div>
        <div class="param-row">
            <label for="v-seed">Seed</label>
            <input
                id="v-seed"
                type="range"
                min="1"
                max="99"
                step="1"
                bind:value={seed}
            />
            <span class="param-val">{seed}</span>
        </div>
    </div>

    {#if vData}
        {#if vData.error}
            <div class="error-box">
                <p style="color:#f87171">{vData.error}</p>
            </div>
        {:else}
            <div class="julia-card v-card">
                <span class="label">전략</span>
                <span class="value">{vData.strategy}</span>
            </div>
            <div class="julia-card v-card">
                <span class="label">틱 수</span>
                <span class="value">{vData.ticks?.toLocaleString()}</span>
            </div>
            <div class="julia-card v-card">
                <span class="label">승률</span>
                <span class="value"
                    >{((vData.win_rate ?? 0) * 100).toFixed(1)}%</span
                >
            </div>
            <div class="julia-card v-card">
                <span class="label">총수익률</span>
                <span class="value"
                    >{((vData.total_return ?? 0) * 100).toFixed(2)}%</span
                >
            </div>
            <div class="julia-card v-card">
                <span class="label">Sharpe</span>
                <span class="value">{(vData.sharpe_ratio ?? 0).toFixed(3)}</span
                >
            </div>
            <div class="julia-card v-card" style="border-color:#22d3ee">
                <span class="label">GC 일시정지</span>
                <span class="value" style="color:#22d3ee"
                    >{vData.gc_pauses_ms}ms</span
                >
            </div>
            {#if vData.stress}
                <div class="julia-card v-card">
                    <span class="label"
                        >스트레스 ({vData.stress.total_ticks?.toLocaleString()} 틱)</span
                    >
                    <span class="value">{vData.stress.elapsed_ms}ms</span>
                </div>
            {/if}
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                MA 크로스오버 전략 백테스트를 실행하세요. (V 서버 :4002 필요, v
                -gc none 컴파일)
            </p>
        </div>
    {/if}
</section>

<style>
    .v-btn {
        background: linear-gradient(135deg, #5d8dee 0%, #1d4ed8 100%);
        color: #fff;
        border: none;
        padding: 0.6rem 1.4rem;
        border-radius: 8px;
        cursor: pointer;
        font-weight: 700;
        margin-bottom: 1rem;
    }
    .v-btn:hover:not(:disabled) {
        filter: brightness(1.15);
    }
    .v-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .v-card {
        border-color: #3b82f6 !important;
    }
    .param-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
        gap: 0.4rem 1rem;
        margin-bottom: 0.75rem;
    }
    .param-row {
        display: flex;
        align-items: center;
        gap: 0.4rem;
        font-size: 0.8rem;
        color: #94a3b8;
    }
    .param-row label {
        min-width: 60px;
        flex-shrink: 0;
    }
    .param-row input[type="range"] {
        flex: 1;
        accent-color: #3b82f6;
    }
    .param-val {
        min-width: 38px;
        text-align: right;
        color: #e2e8f0;
        font-family: monospace;
        font-size: 0.78rem;
    }
</style>
