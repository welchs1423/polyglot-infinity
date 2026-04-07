<script>
    /** @type {any[] | null} */
    let reports = $state(null);

    async function fetchReports() {
        try {
            const res = await fetch("http://localhost:9000/api/reports/latest");
            if (res.ok) reports = await res.json();
        } catch {
            reports = null;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>☕ Kotlin Reports</h2>
            <p class="subtitle">코루틴 스케줄러 · 리스크 리포트 생성 (:9000)</p>
        </div>
        <button class="kotlin-btn" onclick={fetchReports}>최신 리포트</button>
    </div>
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
</style>
