<script>
    /** @type {any | null} */
    let statusData = $state(null);
    /** @type {any | null} */
    let concurrentRes = $state(null);
    /** @type {boolean} */
    let statusLoading = $state(false);
    /** @type {boolean} */
    let concurrentLoading = $state(false);

    // ── API 호출 ─────────────────────────────────────────────────

    async function checkStatus() {
        statusLoading = true;
        statusData = null;
        try {
            const res = await fetch("http://localhost:8008/api/swift/status");
            statusData = res.ok
                ? await res.json()
                : { error: "Swift server offline" };
        } catch {
            statusData = { error: "Swift server unreachable (:8008)" };
        } finally {
            statusLoading = false;
        }
    }

    async function runConcurrentTest() {
        concurrentLoading = true;
        concurrentRes = null;
        try {
            // 100개 Task 동시 실행 — actor 직렬화 검증
            const res = await fetch(
                "http://localhost:8008/api/swift/concurrent?n=100",
            );
            concurrentRes = res.ok
                ? await res.json()
                : { error: "Swift server offline" };
        } catch {
            concurrentRes = { error: "Swift server unreachable (:8008)" };
        } finally {
            concurrentLoading = false;
        }
    }

    async function sendTrade() {
        // 데모 트레이드: NVDA 10주 @ $875
        try {
            await fetch(
                "http://localhost:8008/api/swift/trade?sym=NVDA&qty=10&price=875",
            );
            // 트레이드 후 상태 갱신
            await checkStatus();
        } catch {
            /* offline */
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🦅 Swift Actor</h2>
            <p class="subtitle">
                Swift 6.1 actor — 컴파일타임 data race 차단 · PortfolioLedger
                동시성 보증 (:8008)
            </p>
        </div>
        <div class="btn-group">
            <button
                class="swift-btn"
                onclick={checkStatus}
                disabled={statusLoading}
            >
                {statusLoading ? "조회 중..." : "포트폴리오 상태"}
            </button>
            <button
                class="swift-btn secondary"
                onclick={sendTrade}
                disabled={statusLoading}
            >
                NVDA 트레이드
            </button>
            <button
                class="swift-btn stress"
                onclick={runConcurrentTest}
                disabled={concurrentLoading}
            >
                {concurrentLoading ? "검증 중..." : "동시성 100개 테스트"}
            </button>
        </div>
    </div>

    <!-- 포트폴리오 상태 -->
    {#if statusData && !statusData.error}
        <div class="swift-grid">
            <div class="swift-card">
                <span class="slabel">총 트레이드</span>
                <span class="sval">{statusData.total_trades}</span>
            </div>
            <div class="swift-card">
                <span class="slabel">총 명목금액</span>
                <span class="sval"
                    >${Number(statusData.total_notional).toLocaleString()}</span
                >
            </div>
            <div class="swift-card wide">
                <span class="slabel">포지션</span>
                <span class="sval">
                    {statusData.positions?.length
                        ? statusData.positions
                              .map(
                                  (/** @type {any} */ p) =>
                                      `${p.sym}: ${p.qty}주`,
                              )
                              .join(" · ")
                        : "없음 (트레이드 버튼으로 추가)"}
                </span>
            </div>
        </div>
    {:else if statusData?.error}
        <div class="error-box">
            <p>
                ⚠️ {statusData.error} — <code>./actor-swift/run.sh</code> 으로 실행하세요.
            </p>
        </div>
    {/if}

    <!-- 동시성 테스트 결과 -->
    {#if concurrentRes && !concurrentRes.error}
        <div
            class="concurrent-result"
            class:race={concurrentRes.data_race_detected}
        >
            <div class="race-header">
                {#if concurrentRes.data_race_detected}
                    ❌ Data Race 감지됨! (예상 불가—actor 보호 실패)
                {:else}
                    ✅ Data Race 없음 — actor 직렬화 보증
                {/if}
            </div>
            <div class="concurrent-grid">
                <div class="swift-card">
                    <span class="slabel">동시 Task 수</span>
                    <span class="sval">{concurrentRes.concurrent_tasks}</span>
                </div>
                <div class="swift-card">
                    <span class="slabel">실제 트레이드</span>
                    <span class="sval">{concurrentRes.actual_trades}</span>
                </div>
                <div class="swift-card">
                    <span class="slabel">총 명목금액</span>
                    <span class="sval"
                        >${Number(
                            concurrentRes.total_notional,
                        ).toLocaleString()}</span
                    >
                </div>
                <div class="swift-card wide">
                    <span class="slabel">보증</span>
                    <span class="sval guarantee">{concurrentRes.guarantee}</span
                    >
                </div>
            </div>
        </div>
    {:else if concurrentRes?.error}
        <div class="error-box">
            <p>⚠️ {concurrentRes.error}</p>
        </div>
    {:else if !statusData}
        <div class="empty-box">
            <p>
                Swift 6.1 actor 키워드: 외부 Task가 <code>await</code> 없이
                포트폴리오 프로퍼티에 접근하면 <strong>컴파일 에러</strong>가
                발생합니다. Java synchronized, Go Mutex와 달리 런타임이 아닌
                컴파일 타임 보증입니다.
            </p>
        </div>
    {/if}
</section>

<style>
    .btn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
        justify-content: flex-end;
    }
    .swift-btn {
        background: #f05138;
        color: white;
        border: none;
        padding: 0.6rem 1.1rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        font-size: 0.85rem;
        transition: background 0.2s;
    }
    .swift-btn.secondary {
        background: #c0392b;
    }
    .swift-btn.stress {
        background: #e67e22;
    }
    .swift-btn:hover:not(:disabled) {
        filter: brightness(1.15);
    }
    .swift-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }

    .swift-grid,
    .concurrent-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
        gap: 0.75rem;
        margin-top: 1rem;
    }
    .swift-card {
        background: rgba(240, 81, 56, 0.08);
        border: 1px solid rgba(240, 81, 56, 0.3);
        border-radius: 8px;
        padding: 0.75rem 1rem;
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
    }
    .swift-card.wide {
        grid-column: 1 / -1;
    }
    .slabel {
        font-size: 0.75rem;
        color: #999;
    }
    .sval {
        font-weight: bold;
        color: #f05138;
        font-size: 0.95rem;
        word-break: break-word;
    }
    .sval.guarantee {
        font-size: 0.78rem;
        color: #ccc;
        font-weight: normal;
    }

    .concurrent-result {
        margin-top: 1rem;
        border: 2px solid #2ecc71;
        border-radius: 10px;
        padding: 0.75rem 1rem;
    }
    .concurrent-result.race {
        border-color: #e74c3c;
    }
    .race-header {
        font-weight: bold;
        font-size: 0.95rem;
        margin-bottom: 0.5rem;
        color: #2ecc71;
    }
    .concurrent-result.race .race-header {
        color: #e74c3c;
    }
</style>
