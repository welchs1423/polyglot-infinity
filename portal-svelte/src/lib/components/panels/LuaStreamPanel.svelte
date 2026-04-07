<script>
    /** @type {any | null} */
    let luaData = $state(null);
    let luaLoading = $state(false);

    async function runLua() {
        luaLoading = true;
        luaData = null;
        try {
            const [status, stream] = await Promise.all([
                fetch("http://localhost:8007/api/lua/status").then((r) =>
                    r.json(),
                ),
                fetch(
                    "http://localhost:8007/api/lua/stream?feeds=6&steps=300",
                ).then((r) => r.json()),
            ]);
            luaData = { ...status, ...stream };
        } catch {
            luaData = { error: "Lua 서버 접속 불가 (:8007)" };
        } finally {
            luaLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🌙 Lua 5.4 Coroutine Stream</h2>
            <p class="subtitle">
                단일 OS 스레드 · coroutine.yield/resume으로 6개 가격 피드를
                협력적 멀티플렉싱 (:8007)
            </p>
        </div>
        <button class="lua2-btn" onclick={runLua} disabled={luaLoading}>
            {luaLoading ? "스트리밍..." : "코루틴 실행"}
        </button>
    </div>

    {#if luaData}
        {#if luaData.error}
            <div class="empty-box">
                <p style="color:#f87171">{luaData.error}</p>
            </div>
        {:else}
            <div class="lua2-meta">
                <span class="lua2-tag">스레드 없음</span>
                <span class="lua2-tag">락 없음</span>
                <span class="lua2-tag">콜백 없음</span>
                <span class="lua2-tag orange"
                    >총 resume: {luaData.total_resumes?.toLocaleString()}</span
                >
                <span class="lua2-tag green"
                    >{luaData.elapsed_ms?.toFixed(1)}ms</span
                >
            </div>
            <div class="julia-grid">
                {#each luaData.feeds ?? [] as feed}
                    <div class="julia-card lua2-card">
                        <span class="jlabel">{feed.symbol}</span>
                        <span class="jval">${feed.end_price?.toFixed(2)}</span>
                        <span class="lua2-sub"
                            >수익 {feed.return_pct?.toFixed(1)}% · 변동성 {feed.ann_vol_pct?.toFixed(
                                1,
                            )}%</span
                        >
                        <span class="lua2-status {feed.coroutine_status}"
                            >{feed.coroutine_status}</span
                        >
                    </div>
                {/each}
            </div>
            <p class="lua2-note">
                {luaData.scheduler}
            </p>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Lua 코루틴 스케줄러를 실행하세요. (Lua 서버 :8007
                필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .lua2-btn {
        background: #7c3aed;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .lua2-btn:hover:not(:disabled) {
        background: #6d28d9;
    }
    .lua2-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }

    .lua2-meta {
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem;
        margin-bottom: 1rem;
    }
    .lua2-tag {
        background: #1e1b4b;
        color: #a5b4fc;
        border: 1px solid #3730a3;
        padding: 0.2rem 0.6rem;
        border-radius: 4px;
        font-size: 0.78rem;
        font-weight: 600;
    }
    .lua2-tag.orange {
        background: #1c1007;
        color: #fb923c;
        border-color: #c2410c;
    }
    .lua2-tag.green {
        background: #052e16;
        color: #4ade80;
        border-color: #166534;
    }

    .lua2-card {
        border-color: #7c3aed;
        display: flex;
        flex-direction: column;
        gap: 0.15rem;
    }
    .lua2-sub {
        font-size: 0.7rem;
        color: #94a3b8;
    }
    .lua2-status {
        font-size: 0.68rem;
        font-weight: 700;
        letter-spacing: 0.05em;
        text-transform: uppercase;
    }
    .lua2-status.suspended {
        color: #a78bfa;
    }
    .lua2-status.dead {
        color: #f87171;
    }
    .lua2-status.running {
        color: #4ade80;
    }

    .lua2-note {
        font-size: 0.75rem;
        color: #64748b;
        margin-top: 0.75rem;
        font-style: italic;
        border-top: 1px solid #1e293b;
        padding-top: 0.5rem;
    }
</style>
