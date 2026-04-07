<script>
    /** @type {any | null} */
    let elixirStatus = $state(null);

    async function checkElixir() {
        try {
            const res = await fetch("http://localhost:4000/health");
            if (res.ok) elixirStatus = await res.json();
            else elixirStatus = { status: "offline" };
        } catch {
            elixirStatus = { status: "offline" };
        }
    }
</script>

<section class="panel">
    <div class="panel-header">
        <div>
            <h2>💜 Elixir Hub</h2>
            <p class="subtitle">
                Phoenix WebSocket · GenServer 폴링 · OTP 슈퍼바이저 (:4000)
            </p>
        </div>
        <button class="elixir-btn" onclick={checkElixir}>상태 확인</button>
    </div>
    {#if elixirStatus}
        <div class="stats-row">
            <div class="stat-box hit">
                🟢 Status<br /><strong>{elixirStatus.status}</strong>
            </div>
            <div class="stat-box engine">
                🔧 Services<br /><strong
                    >{elixirStatus.services?.join(", ") ?? "N/A"}</strong
                >
            </div>
            <div class="stat-box miss">
                🕐 Uptime<br /><strong>{elixirStatus.uptime ?? "N/A"}</strong>
            </div>
        </div>
    {:else}
        <div class="empty-box">
            <p>
                Elixir/Erlang 설치 후 <code
                    >mix deps.get &amp;&amp; mix run</code
                > 으로 실행하세요.
            </p>
        </div>
    {/if}
</section>

<style>
    .elixir-btn {
        background: #7c3aed;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        transition: background 0.2s;
    }
    .elixir-btn:hover {
        background: #6d28d9;
    }
</style>
