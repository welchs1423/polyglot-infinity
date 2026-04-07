<script>
    /** @type {any | null} */
    let clojureData = $state(null);
    let clojureLoading = $state(false);

    async function runClojure() {
        clojureLoading = true;
        clojureData = null;
        try {
            const [status, stress] = await Promise.all([
                fetch("http://localhost:8009/api/clojure/status").then((r) =>
                    r.json(),
                ),
                fetch("http://localhost:8009/api/clojure/stress?n=300").then(
                    (r) => r.json(),
                ),
            ]);
            clojureData = { ...status, stress };
        } catch {
            clojureData = { error: "Clojure 서버 접속 불가 (:8009)" };
        } finally {
            clojureLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🟣 Clojure 1.10 STM</h2>
            <p class="subtitle">
                ref + dosync — 소프트웨어 트랜잭션 메모리 · 잠금 없는 원자적
                이체 (:8009)
            </p>
        </div>
        <button class="clj-btn" onclick={runClojure} disabled={clojureLoading}>
            {clojureLoading ? "트랜잭션 중..." : "STM 검증"}
        </button>
    </div>

    {#if clojureData}
        {#if clojureData.error}
            <div class="empty-box">
                <p style="color:#f87171">{clojureData.error}</p>
            </div>
        {:else}
            {@const s = clojureData.stress}
            <div class="julia-grid">
                <div
                    class="julia-card clj-card"
                    style="border-color:{s?.['invariant-preserved']
                        ? '#34d399'
                        : '#ef4444'}"
                >
                    <span class="jlabel">잔액 합계 불변성</span>
                    <span
                        class="jval"
                        style="color:{s?.['invariant-preserved']
                            ? '#34d399'
                            : '#f87171'}"
                    >
                        {s?.["invariant-preserved"] ? "✅ 보존됨" : "❌ 깨짐"}
                    </span>
                </div>
                <div class="julia-card clj-card">
                    <span class="jlabel">시도 / 커밋</span>
                    <span class="jval"
                        >{s?.["transfers-attempted"]} / {s?.[
                            "transfers-committed"
                        ]}</span
                    >
                </div>
                <div class="julia-card clj-card">
                    <span class="jlabel">최종 합계</span>
                    <span class="jval"
                        >${Number(
                            s?.["final-total-balance"],
                        ).toLocaleString()}</span
                    >
                </div>
                <div class="julia-card clj-card">
                    <span class="jlabel">기댓값</span>
                    <span class="jval"
                        >${Number(s?.["expected-total"]).toLocaleString()}</span
                    >
                </div>
            </div>

            <div class="clj-accounts">
                {#each Object.entries(clojureData.accounts ?? {}) as [id, acc]}
                    <div class="clj-acc">
                        <span class="clj-id">{id}</span>
                        <span class="clj-name">{acc.name}</span>
                        <span class="clj-bal"
                            >${Number(acc.balance).toLocaleString(undefined, {
                                minimumFractionDigits: 2,
                                maximumFractionDigits: 2,
                            })}</span
                        >
                    </div>
                {/each}
            </div>

            <p class="clj-note">{s?.["stm-note"]}</p>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Clojure STM 트랜잭션 불변성을 검증하세요. (Clojure
                서버 :8009 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .clj-btn {
        background: #8b5cf6;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .clj-btn:hover:not(:disabled) {
        background: #7c3aed;
    }
    .clj-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }

    .clj-card {
        border-color: #8b5cf6;
    }

    .clj-accounts {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
        margin-top: 0.75rem;
        border: 1px solid #1e293b;
        border-radius: 8px;
        padding: 0.75rem;
    }
    .clj-acc {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        font-size: 0.82rem;
    }
    .clj-id {
        color: #a78bfa;
        font-family: monospace;
        font-weight: 700;
        min-width: 70px;
    }
    .clj-name {
        color: #94a3b8;
        flex: 1;
    }
    .clj-bal {
        color: #e2e8f0;
        font-weight: 700;
        font-family: monospace;
    }

    .clj-note {
        font-size: 0.75rem;
        color: #64748b;
        margin-top: 0.75rem;
        font-style: italic;
        border-top: 1px solid #1e293b;
        padding-top: 0.5rem;
    }
</style>
