<script>
    import { API_BASE } from '$lib/api';
    /** @type {any | null} */
    let scalaData = $state(null);
    /** @type {boolean} */
    let scalaLoading = $state(false);

    async function runScala() {
        scalaLoading = true;
        scalaData = null;
        try {
            const [aggRes, smRes, streamRes] = await Promise.all([
                fetch(
                    `${API_BASE}/api/scala/aggregate?mu=0.08&sigma=0.15&n=252`,
                ),
                fetch(
                    `${API_BASE}/api/scala/smooth?mu=0.08&sigma=0.15&n=252&alpha=0.3&beta=0.1`,
                ),
                fetch(
                    `${API_BASE}/api/scala/stream?mu=0.08&sigma=0.22&n=300&seed=7`,
                ),
            ]);
            if (aggRes.ok && smRes.ok && streamRes.ok) {
                const agg = await aggRes.json();
                const sm = await smRes.json();
                const stream = await streamRes.json();
                scalaData = {
                    ...agg,
                    forecast_next: sm.forecast_next,
                    alpha: sm.alpha,
                    beta: sm.beta,
                    stream,
                };
            } else {
                scalaData = { error: "Scala 스트리머 오프라인" };
            }
        } catch {
            scalaData = { error: "Scala 서버 접속 불가 (:9003)" };
        } finally {
            scalaLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>☢️ Scala (Streaming Aggregator)</h2>
            <p class="subtitle">
                Scala 3.8.3 + JVM · 함수형 스트림 집계 · Holt 이중지수평활
                (:9003)
            </p>
        </div>
        <button class="scala-btn" onclick={runScala} disabled={scalaLoading}>
            {scalaLoading ? "분석 중..." : "스트림 집계"}
        </button>
    </div>
    {#if scalaData}
        {#if scalaData.error}
            <div class="empty-box">
                <p style="color:#f87171">{scalaData.error}</p>
            </div>
        {:else}
            <div class="julia-grid">
                <div class="julia-card scala-card">
                    <span class="jlabel">Ann. Return</span>
                    <span class="jval"
                        >{(scalaData.annualized_return * 100).toFixed(2)}%</span
                    >
                </div>
                <div class="julia-card scala-card">
                    <span class="jlabel">Holt Forecast</span>
                    <span class="jval"
                        >{(scalaData.forecast_next * 100).toFixed(4)}%</span
                    >
                </div>
                {#if scalaData.stream}
                    <div
                        class="julia-card scala-card"
                        style="border-color:#a78bfa"
                    >
                        <span class="jlabel">ADT Tick 이벤트</span>
                        <span class="jval" style="color:#a78bfa"
                            >{scalaData.stream.n_ticks}</span
                        >
                    </div>
                    <div
                        class="julia-card scala-card"
                        style="border-color:#a78bfa"
                    >
                        <span class="jlabel">ADT Alert 이벤트</span>
                        <span class="jval" style="color:#f87171"
                            >{scalaData.stream.n_alerts}</span
                        >
                    </div>
                    <div
                        class="julia-card scala-card"
                        style="border-color:#a78bfa"
                    >
                        <span class="jlabel">최대 심각도</span>
                        <span class="jval"
                            >{scalaData.stream.max_severity_score}</span
                        >
                    </div>
                    <div
                        class="julia-card scala-card"
                        style="border-color:#a78bfa"
                    >
                        <span class="jlabel">LazyList 스트림</span>
                        <span class="jval" style="color:#a78bfa"
                            >{scalaData.stream.lazy_stream
                                ? "∞ unfold"
                                : "N/A"}</span
                        >
                    </div>
                {/if}
            </div>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Scala 3 enum ADT 이벤트 스트림 (LazyList.unfold +
                given/using) 을 실행하세요. (Scala 서버 :9003 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .scala-btn {
        background: linear-gradient(135deg, #dc2626, #991b1b);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .scala-btn:hover:not(:disabled) {
        background: linear-gradient(135deg, #b91c1c, #7f1d1d);
    }
    .scala-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .scala-card {
        border-color: #dc2626 !important;
    }
</style>
