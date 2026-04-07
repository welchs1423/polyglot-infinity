<script>
    /** @type {any[] | null} */
    let reports = $state(null);
    let generating = $state(false);
    /** @type {string | null} */
    let genMsg = $state(null);

    async function fetchReports() {
        try {
            const res = await fetch("http://localhost:9000/api/reports/latest");
            if (res.ok) reports = await res.json();
        } catch {
            reports = null;
        }
    }

    async function generateNow() {
        generating = true;
        genMsg = null;
        try {
            const res = await fetch("http://localhost:9000/api/reports/now");
            if (res.ok) {
                genMsg = "리포트 즉시 생성 완료";
                await fetchReports(); // 목록 갱신
            } else {
                genMsg = "생성 실패";
            }
        } catch {
            genMsg = "Kotlin 서버 접속 불가 (:9000)";
        } finally {
            generating = false;
        }
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
        <table class="log-table">
            <thead>
                <tr>
                    <th>ID</th><th>생성 시각</th><th>평균 리스크</th><th
                        >총 기록</th
                    ><th>최대</th><th>최소</th>
                </tr>
            </thead>
            <tbody>
                {#each reports as r}
                    <tr>
                        <td class="log-id">#{r.id}</td>
                        <td class="log-time"
                            >{new Date(r.generatedAt).toLocaleString(
                                "ko-KR",
                            )}</td
                        >
                        <td><strong>{r.avgRiskScore?.toFixed(4)}</strong></td>
                        <td>{r.totalRecords}</td>
                        <td style="color:#f87171"
                            >{r.maxRiskScore?.toFixed(4)}</td
                        >
                        <td style="color:#34d399"
                            >{r.minRiskScore?.toFixed(4)}</td
                        >
                    </tr>
                {/each}
            </tbody>
        </table>
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
</style>
