<script>
    /** @type {any} */
    let vData = $state(null);
    let vLoading = $state(false);

    async function runV() {
        vLoading = true;
        try {
            const [bt, st] = await Promise.all([
                fetch(
                    "http://localhost:4002/api/v/backtest?ticks=100000&fast=20&slow=50&seed=42",
                ).then((x) => x.json()),
                fetch(
                    "http://localhost:4002/api/v/stress?ticks=150000&seed=42",
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
</style>
