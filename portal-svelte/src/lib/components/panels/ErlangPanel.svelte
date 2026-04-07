<script>
    /** @type {any} */
    let erlangData = $state(null);
    let erlangLoading = $state(false);

    async function runErlang() {
        erlangLoading = true;
        try {
            const [status, swap, riskV1] = await Promise.all([
                fetch("http://localhost:4003/api/erlang/status").then((x) =>
                    x.json(),
                ),
                fetch("http://localhost:4003/api/erlang/hotswap").then((x) =>
                    x.json(),
                ),
                fetch(
                    "http://localhost:4003/api/erlang/risk?debt=0.65&vol=0.28",
                ).then((x) => x.json()),
            ]);
            const riskV2 = await fetch(
                "http://localhost:4003/api/erlang/risk?debt=0.65&vol=0.28",
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
</script>

<section class="panel erlang-panel">
    <h2>🔴 Erlang/OTP 24 · Hot Code Swap (:4003)</h2>
    <p class="subtitle">
        code:load_file/1 — 서버 무중단 로직 교체 · 진행 중 연결은 구버전으로
        완료 (BEAM 2-version protocol)
    </p>
    <button class="erlang-btn" onclick={runErlang} disabled={erlangLoading}>
        {erlangLoading ? "핫 스왑 중..." : "핫 스왑 실행"}
    </button>
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
</style>
