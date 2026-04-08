<script>
    import { API_BASE } from '$lib/api';
    /** @type {any[] | null} */
    let reports = $state(null);
    let generating = $state(false);
    /** @type {string | null} */
    let genMsg = $state(null);
    /** @type {any | null} */
    let expanded = $state(null);

    async function fetchReports() {
        try {
            const res = await fetch(`${API_BASE}/api/reports/latest`);
            if (res.ok) reports = await res.json();
            else reports = [];
        } catch {
            reports = null;
        }
    }

    async function generateNow() {
        generating = true;
        genMsg = null;
        try {
            const res = await fetch(`${API_BASE}/api/reports/now`);
            if (res.ok) {
                genMsg = "리포트 즉시 생성 완료";
                await fetchReports();
            } else {
                genMsg = "생성 실패";
            }
        } catch {
            genMsg = "Kotlin 서버 접속 불가 (:9000)";
        } finally {
            generating = false;
        }
    }

    /**
     * @param {number} value
     * @param {number} min
     * @param {number} max
     */
    function pct(value, min, max) {
        if (max === min) return 50;
        return Math.round(((value - min) / (max - min)) * 100);
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>☕ Kotlin 코루틴 스케줄러 (:9000)</h2>
            <p class="subtitle">코루틴 스케줄러 · DB 리스크 리포트 자동 생성</p>
        </div>
        <div class="kbtn-group">
            <button class="kotlin-btn" onclick={fetchReports}
                >최신 리포트</button
            >
            <button
                class="kotlin-btn gen-btn"
                onclick={generateNow}
                disabled={generating}
            >
                {generating ? "생성 중..." : "즉시 생성"}
            </button>
        </div>
    </div>

    {#if genMsg}
        <div class="gen-msg {genMsg.includes('완료') ? 'ok' : 'err'}">
            {genMsg}
        </div>
    {/if}
    {#if reports && reports.length > 0}
        <p class="report-count">
            {reports.length}개 리포트 · 가장 최근: {new Date(
                reports[0]?.generatedAt,
            ).toLocaleString("ko-KR")}
        </p>
        <div class="report-list">
            {#each reports as r}
                <div
                    class="report-row"
                    onclick={() => (expanded = expanded === r.id ? null : r.id)}
                    style="cursor:pointer"
                >
                    <div class="report-row-main">
                        <span class="rid">#{r.id}</span>
                        <span class="rtime"
                            >{new Date(r.generatedAt).toLocaleString("ko-KR", {
                                month: "2-digit",
                                day: "2-digit",
                                hour: "2-digit",
                                minute: "2-digit",
                            })}</span
                        >
                        <span class="ravg" style="color:#f59e0b"
                            >{r.avgRiskScore?.toFixed(4)}</span
                        >
                        <div class="risk-bar-wrap">
                            <div class="risk-bar-track">
                                <div
                                    class="risk-bar-min"
                                    style="left:{pct(
                                        r.minRiskScore,
                                        r.minRiskScore,
                                        r.maxRiskScore,
                                    )}%"
                                ></div>
                                <div
                                    class="risk-bar-fill"
                                    style="left:{pct(
                                        r.minRiskScore,
                                        r.minRiskScore,
                                        r.maxRiskScore,
                                    )}%;
                                            width:{pct(
                                        r.maxRiskScore,
                                        r.minRiskScore,
                                        r.maxRiskScore,
                                    ) -
                                        pct(
                                            r.minRiskScore,
                                            r.minRiskScore,
                                            r.maxRiskScore,
                                        )}%"
                                ></div>
                                <div
                                    class="risk-bar-avg"
                                    style="left:{pct(
                                        r.avgRiskScore,
                                        r.minRiskScore,
                                        r.maxRiskScore,
                                    )}%"
                                ></div>
                            </div>
                        </div>
                        <span class="expand-icon"
                            >{expanded === r.id ? "▲" : "▼"}</span
                        >
                    </div>
                    {#if expanded === r.id}
                        <div class="report-detail">
                            <div class="rd-item">
                                <span>총 기록</span><strong
                                    >{r.totalRecords?.toLocaleString()}</strong
                                >
                            </div>
                            <div class="rd-item">
                                <span>평균 VaR</span><strong
                                    style="color:#f59e0b"
                                    >{r.avgRiskScore?.toFixed(6)}</strong
                                >
                            </div>
                            <div class="rd-item">
                                <span>최대 VaR</span><strong
                                    style="color:#f87171"
                                    >{r.maxRiskScore?.toFixed(6)}</strong
                                >
                            </div>
                            <div class="rd-item">
                                <span>최소 VaR</span><strong
                                    style="color:#34d399"
                                    >{r.minRiskScore?.toFixed(6)}</strong
                                >
                            </div>
                            <div class="rd-item">
                                <span>범위</span><strong
                                    >{(r.maxRiskScore - r.minRiskScore).toFixed(
                                        6,
                                    )}</strong
                                >
                            </div>
                        </div>
                    {/if}
                </div>
            {/each}
        </div>
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Kotlin 스케줄러 리포트를 불러오세요. (Kotlin 서버
                :9000 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .kotlin-btn {
        background: linear-gradient(135deg, #e8590c, #c2410c);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: filter 0.2s;
    }
    .kotlin-btn:hover {
        filter: brightness(1.15);
    }
    .kbtn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
    }
    .gen-btn {
        background: linear-gradient(135deg, #7c3aed, #5b21b6);
    }
    .gen-msg {
        font-size: 0.8rem;
        padding: 0.3rem 0.75rem;
        border-radius: 6px;
        margin-bottom: 0.4rem;
        font-weight: 600;
    }
    .gen-msg.ok {
        background: #052e16;
        color: #34d399;
        border: 1px solid #166534;
    }
    .gen-msg.err {
        background: #2d1515;
        color: #f87171;
        border: 1px solid #b91c1c;
    }
    .report-count {
        font-size: 0.75rem;
        color: #64748b;
        margin-bottom: 0.5rem;
    }
    .report-list {
        display: flex;
        flex-direction: column;
        gap: 0.3rem;
    }
    .report-row {
        background: #0f172a;
        border: 1px solid #1e293b;
        border-radius: 6px;
        padding: 0.5rem 0.75rem;
        transition: border-color 0.15s;
    }
    .report-row:hover {
        border-color: #e8590c;
    }
    .report-row-main {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        font-size: 0.82rem;
    }
    .rid {
        color: #64748b;
        min-width: 2rem;
        font-family: monospace;
    }
    .rtime {
        color: #94a3b8;
        min-width: 7rem;
        font-size: 0.75rem;
    }
    .ravg {
        font-weight: 700;
        min-width: 4rem;
        font-family: monospace;
    }
    .risk-bar-wrap {
        flex: 1;
    }
    .risk-bar-track {
        position: relative;
        height: 6px;
        background: #1e293b;
        border-radius: 3px;
    }
    .risk-bar-fill {
        position: absolute;
        top: 0;
        height: 100%;
        background: rgba(232, 89, 12, 0.4);
        border-radius: 3px;
    }
    .risk-bar-avg {
        position: absolute;
        top: -3px;
        width: 3px;
        height: 12px;
        background: #f59e0b;
        border-radius: 1px;
        transform: translateX(-50%);
    }
    .risk-bar-min {
        position: absolute;
        top: -2px;
        width: 2px;
        height: 10px;
        background: #34d399;
        border-radius: 1px;
        transform: translateX(-50%);
    }
    .expand-icon {
        color: #475569;
        font-size: 0.65rem;
    }
    .report-detail {
        display: flex;
        gap: 0.75rem;
        flex-wrap: wrap;
        margin-top: 0.5rem;
        padding-top: 0.4rem;
        border-top: 1px solid #1e293b;
        font-size: 0.78rem;
    }
    .rd-item {
        display: flex;
        flex-direction: column;
        gap: 0.1rem;
    }
    .rd-item span {
        color: #64748b;
        font-size: 0.7rem;
    }
</style>
