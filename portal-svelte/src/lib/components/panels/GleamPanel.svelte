<script>
    /** @type {any} */
    let gleamData = $state(null);
    let gleamLoading = $state(false);

    async function runGleam() {
        gleamLoading = true;
        try {
            const [valid_ok, valid_err, contract] = await Promise.all([
                fetch(
                    "http://localhost:4001/api/gleam/validate?service=risk&score=750&grade=A",
                ).then((x) => x.json()),
                fetch(
                    "http://localhost:4001/api/gleam/validate?service=risk&score=1500&grade=X",
                ).then((x) => x.json()),
                fetch("http://localhost:4001/api/gleam/contract").then((x) =>
                    x.json(),
                ),
            ]);
            gleamData = { valid_ok, valid_err, contract };
        } catch {
            gleamData = { error: "Gleam 서버 접속 불가 (:4001)" };
        } finally {
            gleamLoading = false;
        }
    }
</script>

<section class="panel gleam-panel">
    <h2>Gleam 1.15 · BEAM/Erlang · 서비스 계약 검증 레이어 (:4001)</h2>
    <p class="subtitle">
        ServiceMessage 모든 variant — exhaustive case 컴파일 강제
    </p>
    <button class="gleam-btn" onclick={runGleam} disabled={gleamLoading}>
        {gleamLoading ? "검증 중..." : "계약 검증 실행"}
    </button>
    {#if gleamData}
        {#if gleamData.error}
            <div class="error-box">
                <p style="color:#f87171">{gleamData.error}</p>
            </div>
        {:else}
            <div class="julia-card gleam-card">
                <span class="label">✅ 정상 검증 (score=750)</span>
                <span class="value" style="color:#34d399"
                    >{gleamData.valid_ok?.ok ? "OK" : "FAIL"}</span
                >
            </div>
            <div class="julia-card gleam-card">
                <span class="label">❌ 오류 검증 (score=1500)</span>
                <span class="value" style="color:#f87171"
                    >{gleamData.valid_err?.error ?? "?"}</span
                >
            </div>
            <div class="julia-card gleam-card">
                <span class="label">메시지 타입 수</span>
                <span class="value"
                    >{gleamData.contract?.message_types?.length ?? 0}개</span
                >
            </div>
            <div class="julia-card gleam-card">
                <span class="label">보장</span>
                <span class="value">{gleamData.contract?.guarantee ?? "?"}</span
                >
            </div>
        {/if}
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 Gleam 서비스 계약 검증을 실행하세요. (Gleam 서버
                :4001 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .gleam-btn {
        background: linear-gradient(135deg, #ffaff3 0%, #a855f7 100%);
        color: #1a0030;
        border: none;
        padding: 0.6rem 1.4rem;
        border-radius: 8px;
        cursor: pointer;
        font-weight: 700;
        margin-bottom: 1rem;
    }
    .gleam-btn:hover:not(:disabled) {
        filter: brightness(1.1);
    }
    .gleam-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .gleam-card {
        border-color: #a855f7 !important;
    }
    .gleam-panel {
        /* inherits .panel from global */
    }
</style>
