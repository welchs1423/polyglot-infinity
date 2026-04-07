<script>
    /** @type {any | null} */
    let swiftData = $state(null);
    let swiftLoading = $state(false);

    async function runSwift() {
        swiftLoading = true;
        swiftData = null;
        try {
            const [status, concurrent] = await Promise.all([
                fetch("http://localhost:8008/api/swift/status").then((r) =>
                    r.json(),
                ),
                fetch("http://localhost:8008/api/swift/concurrent?n=200").then(
                    (r) => r.json(),
                ),
            ]);
            swiftData = { ...status, ...concurrent };
        } catch {
            swiftData = { error: "Swift 서버 접속 불가 (:8008)" };
        } finally {
            swiftLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🦅 Swift 6.1 Actor</h2>
            <p class="subtitle">
                actor 키워드 — 컴파일 타임 data race 차단 · 200개 Task 동시 접근
                (:8008)
            </p>
        </div>
        <button class="swift-btn" onclick={runSwift} disabled={swiftLoading}>
            {swiftLoading ? "검증 중..." : "Actor 검증"}
        </button>
    </div>

    {#if swiftData}
        {#if swiftData.error}
            <div class="empty-box">
                <p style="color:#f87171">{swiftData.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div
                    class="julia-card swift-card"
                    style="border-color: {swiftData.data_race_detected
                        ? '#ef4444'
                        : '#34d399'}"
                >
                    <span class="jlabel">Data Race</span>
                    <span
                        class="jval"
                        style="color:{swiftData.data_race_detected
                            ? '#f87171'
                            : '#34d399'}"
                    >
                        {swiftData.data_race_detected ? "⚠️ 감지됨" : "✅ 없음"}
                    </span>
                </div>
                <div class="julia-card swift-card">
                    <span class="jlabel">동시 Task</span>
                    <span class="jval"
                        >{swiftData.concurrent_tasks?.toLocaleString()}</span
                    >
                </div>
                <div class="julia-card swift-card">
                    <span class="jlabel">예상 / 실제 trade</span>
                    <span class="jval"
                        >{swiftData.expected_trades} / {swiftData.actual_trades}</span
                    >
                </div>
                <div class="julia-card swift-card">
                    <span class="jlabel">총 Notional</span>
                    <span class="jval"
                        >${Number(swiftData.total_notional).toLocaleString(
                            undefined,
                            { maximumFractionDigits: 0 },
                        )}</span
                    >
                </div>
                {#each swiftData.positions ?? [] as pos}
                    <div
                        class="julia-card swift-card"
                        style="border-color:#f59e0b"
                    >
                        <span class="jlabel">{pos.sym}</span>
                        <span class="jval" style="color:#fbbf24"
                            >{pos.qty}주</span
                        >
                    </div>
                {/each}
            </div>
            <p class="swift-note">{swiftData.guarantee}</p>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Swift actor 동시성 검증을 실행하세요. (Swift 서버
                :8008 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .swift-btn {
        background: #f97316;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .swift-btn:hover:not(:disabled) {
        background: #ea580c;
    }
    .swift-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }

    .swift-card {
        border-color: #f97316;
    }

    .swift-note {
        font-size: 0.75rem;
        color: #64748b;
        margin-top: 0.75rem;
        font-style: italic;
        border-top: 1px solid #1e293b;
        padding-top: 0.5rem;
    }
</style>
