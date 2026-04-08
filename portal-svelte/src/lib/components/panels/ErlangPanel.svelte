<script>
    import { API_BASE } from '$lib/api';
    /** @type {any} */
    let erlangData = $state(null);
    let erlangLoading = $state(false);
    let riskDebt = $state(0.65);
    let riskVol = $state(0.28);
    /** @type {any | null} */
    let riskData = $state(null);
    let riskLoading = $state(false);

    async function runErlang() {
        erlangLoading = true;
        try {
            const [status, swap, riskV1] = await Promise.all([
                fetch(`${API_BASE}/api/erlang/status`).then((x) =>
                    x.json(),
                ),
                fetch(`${API_BASE}/api/erlang/hotswap`).then((x) =>
                    x.json(),
                ),
                fetch(
                    `${API_BASE}/api/erlang/risk?debt=0.65&vol=0.28`,
                ).then((x) => x.json()),
            ]);
            const riskV2 = await fetch(
                `${API_BASE}/api/erlang/risk?debt=0.65&vol=0.28`,
            ).then((x) => x.json());
            erlangData = {
                ...status,
                swap,
                riskBefore: riskV1,
                riskAfter: riskV2,
            };
        } catch {
            erlangData = { error: "Erlang 서버 접속 불가 (:4003)" };
        } finally {
            erlangLoading = false;
        }
    }

    async function fetchRisk() {
        riskLoading = true;
        riskData = null;
        try {
            riskData = await fetch(
                `${API_BASE}/api/erlang/risk?debt=${riskDebt.toFixed(2)}&vol=${riskVol.toFixed(2)}`,
            ).then((x) => x.json());
        } catch {
            riskData = { error: "Erlang 서버 접속 불가 (:4003)" };
        } finally {
            riskLoading = false;
        }
    }

    /** @param {number} score */
    function gradeColor(score) {
        if (score < 0.2) return "#34d399";
        if (score < 0.35) return "#86efac";
        if (score < 0.5) return "#fbbf24";
        if (score < 0.65) return "#f97316";
        return "#f87171";
    }
</script>

<section class="panel erlang-panel">
    <div class="panel-header">
        <div>
            <h2>🔴 Erlang/OTP 24 · Hot Code Swap (:4003)</h2>
            <p class="subtitle">
                code:load_file/1 — 서버 무중단 로직 교체 · 진행 중 연결은
                구버전으로 완료 (BEAM 2-version protocol)
            </p>
        </div>
        <button class="erlang-btn" onclick={runErlang} disabled={erlangLoading}>
            {erlangLoading ? "핯 스왓 중..." : "핯 스왓 실행"}
        </button>
    </div>
    {#if erlangData}
        {#if erlangData.error}
            <div class="error-box">
                <p style="color:#f87171">{erlangData.error}</p>
            </div>
        {:else}
            <div class="julia-card erlang-card" style="border-color:#ef4444">
                <span class="label">다운타임</span>
                <span class="value" style="color:#34d399"
                    >{erlangData.swap?.downtime_ms}ms</span
                >
            </div>
            <div class="julia-card erlang-card">
                <span class="label">스왑 횟수</span>
                <span class="value">{erlangData.swap?.swap_count}회</span>
            </div>
            <div class="julia-card erlang-card">
                <span class="label"
                    >{erlangData.swap?.old_logic} → {erlangData.swap
                        ?.new_logic}</span
                >
                <span class="value">교체 완료</span>
            </div>
            <div class="julia-card erlang-card">
                <span class="label">리스크 (스왑 전)</span>
                <span class="value"
                    >{((erlangData.riskBefore?.risk_score ?? 0) * 100).toFixed(
                        2,
                    )}% {erlangData.riskBefore?.grade}</span
                >
            </div>
            <div class="julia-card erlang-card" style="border-color:#f59e0b">
                <span class="label">리스크 (스왑 후)</span>
                <span class="value" style="color:#f59e0b"
                    >{((erlangData.riskAfter?.risk_score ?? 0) * 100).toFixed(
                        2,
                    )}% {erlangData.riskAfter?.grade}</span
                >
            </div>
            <div class="julia-card erlang-card">
                <span class="label">BEAM 프로세스 수</span>
                <span class="value">{erlangData.beam_processes}</span>
            </div>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 리스크 로직을 핫 스왑하세요. (Erlang 서버 :4003
                필요)
            </p>
        </div>
    {/if}
    <div class="risk-section">
        <p class="risk-label">리스크 직접 계산 (v1 로직 적용)</p>
        <div class="risk-params">
            <label class="risk-field">
                <span>부체비율</span>
                <input
                    type="range"
                    min="0.1"
                    max="0.99"
                    step="0.01"
                    bind:value={riskDebt}
                />
                <span class="pval">{(riskDebt * 100).toFixed(0)}%</span>
            </label>
            <label class="risk-field">
                <span>변동성</span>
                <input
                    type="range"
                    min="0.05"
                    max="0.80"
                    step="0.01"
                    bind:value={riskVol}
                />
                <span class="pval">{(riskVol * 100).toFixed(0)}%</span>
            </label>
            <button
                class="erlang-btn risk-btn"
                onclick={fetchRisk}
                disabled={riskLoading}
            >
                {riskLoading ? "계산 중..." : "산정"}
            </button>
        </div>
        {#if riskData}
            {#if riskData.error}
                <p style="color:#f87171">{riskData.error}</p>
            {:else}
                <div class="julia-grid" style="margin-top:0.5rem">
                    <div
                        class="julia-card erlang-card"
                        style="border-color:{gradeColor(
                            riskData.risk_score ?? 0,
                        )}"
                    >
                        <span class="jlabel">Risk Score</span>
                        <span
                            class="jval"
                            style="color:{gradeColor(riskData.risk_score ?? 0)}"
                        >
                            {((riskData.risk_score ?? 0) * 100).toFixed(2)}%
                        </span>
                    </div>
                    <div class="julia-card erlang-card">
                        <span class="jlabel">Grade</span>
                        <span
                            class="jval"
                            style="color:{gradeColor(riskData.risk_score ?? 0)}"
                        >
                            {riskData.grade}
                        </span>
                    </div>
                    <div class="julia-card erlang-card">
                        <span class="jlabel">Logic Ver</span>
                        <span class="jval">{riskData.version}</span>
                    </div>
                    <div class="julia-card erlang-card">
                        <span class="jlabel">로직</span>
                        <span class="jval" style="font-size:0.7rem"
                            >{riskData.logic}</span
                        >
                    </div>
                </div>
            {/if}
        {/if}
    </div>
</section>

<style>
    .erlang-btn {
        background: linear-gradient(135deg, #ef4444 0%, #7f1d1d 100%);
        color: #fff;
        border: none;
        padding: 0.6rem 1.4rem;
        border-radius: 8px;
        cursor: pointer;
        font-weight: 700;
        margin-bottom: 1rem;
    }
    .erlang-btn:hover:not(:disabled) {
        filter: brightness(1.15);
    }
    .erlang-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .erlang-card {
        border-color: #ef4444 !important;
    }
    .erlang-panel {
        border-top: 3px solid #ef4444;
    }
    .risk-section {
        margin-top: 1.5rem;
        border-top: 1px solid rgba(239, 68, 68, 0.25);
        padding-top: 1rem;
    }
    .risk-label {
        font-size: 0.75rem;
        color: #ef4444;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        font-weight: 600;
        margin-bottom: 0.6rem;
    }
    .risk-params {
        display: flex;
        gap: 0.75rem;
        align-items: flex-end;
        flex-wrap: wrap;
    }
    .risk-field {
        display: flex;
        align-items: center;
        gap: 0.4rem;
        font-size: 0.78rem;
        color: #94a3b8;
        flex: 1;
        min-width: 180px;
    }
    .risk-field input[type="range"] {
        flex: 1;
        accent-color: #ef4444;
    }
    .pval {
        min-width: 2.8rem;
        text-align: right;
        color: #fca5a5;
        font-weight: 700;
    }
    .risk-btn {
        padding: 0.45rem 1rem;
        font-size: 0.82rem;
        margin-bottom: 0;
    }
</style>
