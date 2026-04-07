<script>
    import { onMount } from "svelte";

    /** @type {any | null} */
    let javaData = $state(null);
    let javaLoading = $state(false);
    /** @type {any | null} */
    let pipelineData = $state(null);
    let pipelineLoading = $state(false);
    /** @type {any | null} */
    let javaStatus = $state(null);

    onMount(async () => {
        try {
            const res = await fetch("http://localhost:8010/api/java/status");
            if (res.ok) javaStatus = await res.json();
        } catch { /* offline */ }
    });

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

    async function runPipeline() {
        pipelineLoading = true;
        pipelineData = null;
        try {
            pipelineData = await fetch(
                "http://localhost:8010/api/java/pipeline?n=1000&delay=10",
            ).then((r) => r.json());
        } catch {
            pipelineData = { error: "Java 서버 접속 불가 (:8010)" };
        } finally {
            pipelineLoading = false;
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
            {#if javaStatus}
                <p class="java-info-strip">
                    <span>Java {javaStatus.version}</span>
                    <span class="dot">·</span>
                    <span>{javaStatus.jvm}</span>
                    <span class="dot">·</span>
                    <span>CPU {javaStatus.cpu_cores}코어</span>
                </p>
            {/if}
        </div>
        <button class="java-btn" onclick={runJava} disabled={javaLoading}>
            {javaLoading ? "실행 중..." : "Loom 실행"}
        </button>
        <button
            class="pipeline-btn"
            onclick={runPipeline}
            disabled={pipelineLoading}
        >
            {pipelineLoading ? "측정 중..." : "Blocking I/O 시뮬레이션"}
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

    {#if pipelineData}
        <div class="pipeline-section">
            <h3 class="pipeline-title">
                ⏱ Blocking I/O 시뮬레이션 — Thread.sleep() × {pipelineData.tasks}개
            </h3>
            {#if pipelineData.error}
                <p style="color:#f87171">{pipelineData.error}</p>
            {:else}
                <p class="pipeline-desc">
                    작업마다 {pipelineData.delay_ms_per_task}ms sleep(blocking)
                    포함. Platform pool({pipelineData.platform_pool_size}개)는
                    순차 처리 → Virtual은 {pipelineData.tasks}개 동시 sleep.
                </p>
                <div class="julia-grid">
                    <div class="julia-card platform-card">
                        <span class="jlabel">Platform Thread</span>
                        <span class="jval" style="color:#f87171"
                            >{pipelineData.platform_total_ms}ms</span
                        >
                        <span class="pipeline-sub"
                            >pool 상한 {pipelineData.platform_pool_size}개 ·
                            이론값 {pipelineData.theoretical_platform_ms}ms</span
                        >
                    </div>
                    <div class="julia-card virtual-card">
                        <span class="jlabel">Virtual Thread</span>
                        <span class="jval" style="color:#34d399"
                            >{pipelineData.virtual_total_ms}ms</span
                        >
                        <span class="pipeline-sub"
                            >sleep 중 OS 스레드 반환 · {pipelineData.tasks}개
                            동시 실행</span
                        >
                    </div>
                    <div
                        class="julia-card"
                        style="border-color:#f59e0b; grid-column: span 2"
                    >
                        <span class="jlabel">가속 배율</span>
                        <span
                            class="jval"
                            style="color:#f59e0b; font-size:1.4rem"
                            >{pipelineData.speedup}</span
                        >
                    </div>
                </div>
                <p class="java-note">{pipelineData.note}</p>
            {/if}
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

    .pipeline-btn {
        background: #065f46;
        color: #6ee7b7;
        border: 1px solid #059669;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
        margin-left: 0.5rem;
    }
    .pipeline-btn:hover:not(:disabled) {
        background: #047857;
    }
    .pipeline-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }

    .pipeline-section {
        margin-top: 1rem;
        padding-top: 1rem;
        border-top: 1px solid #1e293b;
    }

    .pipeline-title {
        font-size: 0.95rem;
        color: #6ee7b7;
        margin: 0 0 0.5rem 0;
    }

    .pipeline-desc {
        font-size: 0.82rem;
        color: #94a3b8;
        margin: 0 0 0.75rem 0;
    }

    .pipeline-sub {
        font-size: 0.72rem;
        color: #64748b;
    }

    .platform-card {
        border-color: #ef4444;
    }
    .virtual-card {
        border-color: #34d399;
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
    .java-info-strip {
        display: flex;
        gap: 0.4rem;
        align-items: center;
        font-size: 0.72rem;
        color: #64748b;
        margin: 0.2rem 0 0;
        flex-wrap: wrap;
    }
    .java-info-strip .dot {
        color: #334155;
    }
</style>
