<script>
    /** @type {any | null} */
    let javaData = $state(null);
    let javaLoading = $state(false);

    async function runJava() {
        javaLoading = true;
        javaData = null;
        try {
            const [vthreads, compare] = await Promise.all([
                fetch("http://localhost:8010/api/java/vthreads?n=50000").then(
                    (r) => r.json(),
                ),
                fetch("http://localhost:8010/api/java/compare?n=500").then(
                    (r) => r.json(),
                ),
            ]);
            javaData = { vthreads, compare };
        } catch {
            javaData = { error: "Java 서버 접속 불가 (:8010)" };
        } finally {
            javaLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>☕ Java 21 Virtual Threads</h2>
            <p class="subtitle">
                Project Loom · Thread.ofVirtual() — 5만 개 경량 스레드 · OS
                스레드 수 무관 (:8010)
            </p>
        </div>
        <button class="java-btn" onclick={runJava} disabled={javaLoading}>
            {javaLoading ? "실행 중..." : "Loom 실행"}
        </button>
    </div>

    {#if javaData}
        {#if javaData.error}
            <div class="empty-box">
                <p style="color:#f87171">{javaData.error}</p>
            </div>
        {:else}
            {@const v = javaData.vthreads}
            {@const c = javaData.compare}
            <div class="julia-grid">
                <div class="julia-card java-card">
                    <span class="jlabel">Virtual Threads</span>
                    <span class="jval"
                        >{Number(v?.virtual_threads).toLocaleString()}</span
                    >
                </div>
                <div class="julia-card java-card">
                    <span class="jlabel">처리량</span>
                    <span class="jval"
                        >{Number(v?.throughput_per_s).toLocaleString()}/s</span
                    >
                </div>
                <div class="julia-card java-card">
                    <span class="jlabel">소요 시간</span>
                    <span class="jval">{v?.elapsed_ms}ms</span>
                </div>
                <div class="julia-card java-card">
                    <span class="jlabel">메모리 증가</span>
                    <span class="jval"
                        >{Number(v?.mem_delta_kb).toLocaleString()} KB</span
                    >
                </div>
                <div class="julia-card java-card" style="border-color:#f59e0b">
                    <span class="jlabel">Platform {c?.tasks}개</span>
                    <span class="jval" style="color:#94a3b8"
                        >{c?.platform_thread_ms}ms</span
                    >
                </div>
                <div class="julia-card java-card" style="border-color:#34d399">
                    <span class="jlabel">Virtual {c?.tasks}개</span>
                    <span class="jval" style="color:#34d399"
                        >{c?.virtual_thread_ms}ms</span
                    >
                </div>
                <div
                    class="julia-card java-card"
                    style="border-color:#34d399; grid-column: span 2"
                >
                    <span class="jlabel">Virtual Thread 우위</span>
                    <span class="jval" style="color:#34d399"
                        >{c?.speedup} 빠름</span
                    >
                </div>
            </div>
            <p class="java-note">{v?.note}</p>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Java 21 Virtual Thread 벤치마크를 실행하세요. (Java
                서버 :8010 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .java-btn {
        background: #b45309;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .java-btn:hover:not(:disabled) {
        background: #92400e;
    }
    .java-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }

    .java-card {
        border-color: #b45309;
    }

    .java-note {
        font-size: 0.75rem;
        color: #64748b;
        margin-top: 0.75rem;
        font-style: italic;
        border-top: 1px solid #1e293b;
        padding-top: 0.5rem;
    }
</style>
