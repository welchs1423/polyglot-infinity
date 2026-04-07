<script>
    /** @type {any | null} */
    let brainData = $state(null);
    let brainLoading = $state(false);

    async function runBrain() {
        brainLoading = true;
        brainData = null;
        try {
            const res = await fetch("http://localhost:8000/api/analyze");
            if (res.ok) brainData = await res.json();
            else brainData = { error: "Python Brain 오프라인" };
        } catch {
            brainData = { error: "Python Brain 접속 불가 (:8000)" };
        } finally {
            brainLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🐍 Python Brain (:8000)</h2>
            <p class="subtitle">
                실시간 외환 수집 · C++ FFI 리스크 계산 · Zig FFI VaR · Julia
                몬테카를로
            </p>
        </div>
        <button class="py-btn" onclick={runBrain} disabled={brainLoading}>
            {brainLoading ? "분석 중..." : "멀티 엔진 분석"}
        </button>
    </div>

    {#if brainData}
        {#if brainData.error}
            <div class="empty-box">
                <p style="color:#f87171">{brainData.error}</p>
            </div>
        {:else}
            <!-- API + C++ 결과 -->
            <div class="julia-grid">
                <div class="julia-card py-card">
                    <span class="jlabel">API 상태</span>
                    <span
                        class="jval"
                        class:online={brainData.api_status === "Success"}
                        >{brainData.api_status}</span
                    >
                </div>
                <div class="julia-card py-card">
                    <span class="jlabel">C++ 리스크 점수</span>
                    <span class="jval"
                        >{brainData.computation_result?.toLocaleString()}</span
                    >
                </div>
                {#if brainData.rates}
                    {#each Object.entries(brainData.rates) as [cur, val]}
                        <div class="julia-card py-card">
                            <span class="jlabel">USD/{cur}</span>
                            <span class="jval"
                                >{typeof val === "number"
                                    ? val.toFixed(2)
                                    : val}</span
                            >
                        </div>
                    {/each}
                {/if}
            </div>

            <!-- Zig VaR -->
            {#if brainData.zig_analysis?.engine}
                <div class="section-label">
                    ⚡ Zig FFI — {brainData.zig_analysis.engine}
                </div>
                <div class="julia-grid">
                    <div
                        class="julia-card py-card"
                        style="border-color:#22d3ee"
                    >
                        <span class="jlabel">Volatility σ</span>
                        <span class="jval" style="color:#22d3ee"
                            >{brainData.zig_analysis.volatility}</span
                        >
                    </div>
                    <div
                        class="julia-card py-card"
                        style="border-color:#22d3ee"
                    >
                        <span class="jlabel">VaR 95%</span>
                        <span class="jval" style="color:#22d3ee"
                            >₩{brainData.zig_analysis.var_95?.toLocaleString()}</span
                        >
                    </div>
                    <div
                        class="julia-card py-card"
                        style="border-color:#22d3ee"
                    >
                        <span class="jlabel">포지션 사이즈</span>
                        <span class="jval"
                            >₩{Number(
                                brainData.zig_analysis.position_size,
                            ).toLocaleString()}</span
                        >
                    </div>
                </div>
            {/if}

            <!-- Julia 시뮬레이션 -->
            {#if brainData.julia_simulation?.engine}
                {@const j = brainData.julia_simulation}
                <div class="section-label">🔬 Julia — {j.engine}</div>
                <div class="julia-grid">
                    <div
                        class="julia-card py-card"
                        style="border-color:#9333ea"
                    >
                        <span class="jlabel">시뮬 경로</span>
                        <span class="jval" style="color:#9333ea"
                            >{Number(j.paths).toLocaleString()}</span
                        >
                    </div>
                    <div
                        class="julia-card py-card"
                        style="border-color:#9333ea"
                    >
                        <span class="jlabel">최종가 평균</span>
                        <span class="jval"
                            >{j.mean_final_price?.toFixed(2)}</span
                        >
                    </div>
                    <div
                        class="julia-card py-card"
                        style="border-color:#9333ea"
                    >
                        <span class="jlabel">VaR (Monte)</span>
                        <span class="jval">{j.var_95?.toFixed(4)}</span>
                    </div>
                    <div
                        class="julia-card py-card"
                        style="border-color:#9333ea"
                    >
                        <span class="jlabel">소요 시간</span>
                        <span class="jval">{j.elapsed_ms}ms</span>
                    </div>
                </div>
            {/if}

            <p class="py-note">{brainData.version} · {brainData.source}</p>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Python + C++ + Zig + Julia 멀티 엔진 분석을
                실행하세요. (:8000)
            </p>
        </div>
    {/if}
</section>

<style>
    .py-btn {
        background: linear-gradient(135deg, #3b82f6, #1d4ed8);
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: filter 0.2s;
    }
    .py-btn:hover:not(:disabled) {
        filter: brightness(1.15);
    }
    .py-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .py-card {
        border-color: #3b82f6 !important;
    }
    .online {
        color: #34d399 !important;
    }
    .section-label {
        font-size: 0.78rem;
        color: #64748b;
        margin: 0.6rem 0 0.3rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.04em;
    }
    .py-note {
        font-size: 0.72rem;
        color: #475569;
        margin-top: 0.75rem;
        font-style: italic;
        border-top: 1px solid #1e293b;
        padding-top: 0.5rem;
    }
</style>
