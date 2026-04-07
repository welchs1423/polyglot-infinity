<script>
    /** @type {any | null} */
    let fsharpOption = $state(null);
    /** @type {boolean} */
    let fsharpLoading = $state(false);

    async function runFsharpOption() {
        fsharpLoading = true;
        fsharpOption = null;
        try {
            const res = await fetch(
                "http://localhost:9001/api/fsharp/option?s=100&k=100&r=0.05&sigma=0.20&t=1.0",
            );
            if (res.ok) fsharpOption = await res.json();
            else fsharpOption = { error: "F# pricer offline" };
        } catch {
            fsharpOption = { error: "F# pricer unreachable" };
        } finally {
            fsharpLoading = false;
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>🤖 F# Black-Scholes</h2>
            <p class="subtitle">
                At-the-money 옵션 Greeks 미분 · Call/Put 프라이스 (.NET 8 ·
                :9001)
            </p>
        </div>
        <button
            class="fsharp-btn"
            onclick={runFsharpOption}
            disabled={fsharpLoading}
        >
            {fsharpLoading ? "계산 중..." : "옵션 프라이스"}
        </button>
    </div>
    {#if fsharpOption && !fsharpOption.error}
        <div class="julia-grid">
            <div class="julia-card fsharp-card">
                <span class="jlabel">Call Price</span><span class="jval"
                    >${fsharpOption.call_price}</span
                >
            </div>
            <div class="julia-card fsharp-card">
                <span class="jlabel">Put Price</span><span class="jval"
                    >${fsharpOption.put_price}</span
                >
            </div>
            <div class="julia-card fsharp-card">
                <span class="jlabel">Δ Delta</span><span class="jval"
                    >{fsharpOption.delta_call}</span
                >
            </div>
            <div class="julia-card fsharp-card">
                <span class="jlabel">Γ Gamma</span><span class="jval"
                    >{fsharpOption.gamma}</span
                >
            </div>
            <div class="julia-card fsharp-card">
                <span class="jlabel">ν Vega</span><span class="jval"
                    >{fsharpOption.vega}</span
                >
            </div>
            <div class="julia-card fsharp-card">
                <span class="jlabel">Θ Theta/day</span><span class="jval"
                    >{fsharpOption.theta_call}</span
                >
            </div>
        </div>
    {:else if fsharpOption?.error}
        <div class="error-box">
            <p>
                ⚠️ {fsharpOption.error} —
                <code>dotnet run --project pricer-fsharp</code> 으로 실행하세요.
            </p>
        </div>
    {:else}
        <div class="empty-box">
            <p>
                버튼을 눌러 F# Black-Scholes 옵션 Greeks를 계산하세요. (F# 서버
                :9001 필요)
            </p>
        </div>
    {/if}
</section>

<style>
    .fsharp-btn {
        background: #512bd4;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .fsharp-btn:hover:not(:disabled) {
        background: #3d1fa0;
    }
    .fsharp-btn:disabled {
        opacity: 0.6;
        cursor: not-allowed;
    }
    .fsharp-card {
        border-color: #512bd4 !important;
    }
</style>
