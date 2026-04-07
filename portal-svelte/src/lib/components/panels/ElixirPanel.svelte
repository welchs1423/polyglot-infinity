<script>
    /** @type {any | null} */
    let elixirStatus = $state(null);
    /** @type {any | null} */
    let liveSnapshot = $state(null);
    /** @type {boolean} */
    let wsConnected = $state(false);
    /** @type {string} */
    let wsLog = $state("");

    // Phoenix channel wire 포맷: [join_ref, ref, topic, event, payload]
    // phoenix.js 없이 네이티브 WebSocket으로 구현
    /** @type {WebSocket | null} */
    let ws = null;
    let heartbeatTimer = 0;
    let refCounter = 1;

    async function checkElixir() {
        try {
            const res = await fetch("http://localhost:4000/api/hub/status");
            if (res.ok) elixirStatus = await res.json();
            else elixirStatus = { status: "offline" };
        } catch {
            elixirStatus = { status: "offline" };
        }
    }

    function connectWS() {
        if (ws) {
            ws.close();
            ws = null;
        }

        const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0";
        ws = new WebSocket(url);
        wsLog = "연결 시도 중...";

        ws.onopen = () => {
            wsConnected = true;
            wsLog = "WebSocket 연결됨 ✅";
            // system:lobby 채널 조인
            const joinMsg = JSON.stringify([
                null,
                String(refCounter++),
                "system:lobby",
                "phx_join",
                {},
            ]);
            ws?.send(joinMsg);

            // 30초 heartbeat (Phoenix 기본 타임아웃 60s)
            heartbeatTimer = setInterval(() => {
                ws?.send(
                    JSON.stringify([
                        null,
                        String(refCounter++),
                        "phoenix",
                        "heartbeat",
                        {},
                    ]),
                );
            }, 30_000);
        };

        ws.onmessage = (e) => {
            try {
                const [, , , event, payload] = JSON.parse(e.data);
                if (event === "snapshot") {
                    liveSnapshot = payload;
                    wsLog = `마지막 수신: ${new Date().toLocaleTimeString()}`;
                }
            } catch {
                /* ignore */
            }
        };

        ws.onclose = () => {
            wsConnected = false;
            clearInterval(heartbeatTimer);
            wsLog = "연결 끊김";
        };

        ws.onerror = () => {
            wsLog = "연결 실패 — Elixir 서버(:4000)를 먼저 실행하세요";
        };
    }

    function disconnectWS() {
        ws?.close();
        ws = null;
        wsConnected = false;
        clearInterval(heartbeatTimer);
        wsLog = "연결 해제됨";
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
        <div class="btn-group">
            <button class="elixir-btn" onclick={checkElixir}>HTTP 상태</button>
            {#if wsConnected}
                <button class="elixir-btn disconnect" onclick={disconnectWS}
                    >WS 해제</button
                >
            {:else}
                <button class="elixir-btn ws" onclick={connectWS}
                    >WS 실시간 연결</button
                >
            {/if}
        </div>
    </div>

    <!-- HTTP 상태 -->
    {#if elixirStatus}
        <div class="stats-row">
            <div class="stat-box hit">
                🟢 Status<br /><strong
                    >{elixirStatus.elixir_hub ?? elixirStatus.status}</strong
                >
            </div>
            <div class="stat-box engine">
                🕐 Polled At<br /><strong
                    >{elixirStatus.polled_at ?? "N/A"}</strong
                >
            </div>
            <div class="stat-box miss">
                🔗 Go Status<br /><strong
                    >{elixirStatus.go_status ??
                        elixirStatus.status ??
                        "N/A"}</strong
                >
            </div>
        </div>
    {/if}

    <!-- WebSocket 실시간 스냅숏 -->
    <div class="ws-status" class:connected={wsConnected}>
        {wsConnected ? "🔴 LIVE" : "⚫ OFFLINE"} &nbsp;{wsLog}
    </div>

    {#if liveSnapshot}
        <div class="live-box">
            <div class="live-header">
                📡 실시간 스냅숏 (Elixir GenServer 10s 주기 브로드캐스트)
            </div>
            <div class="stats-row">
                <div class="stat-box hit">
                    Elixir Hub<br /><strong>{liveSnapshot.elixir_hub}</strong>
                </div>
                <div class="stat-box engine">
                    Go Status<br /><strong
                        >{liveSnapshot.status ??
                            liveSnapshot.go_status ??
                            "N/A"}</strong
                    >
                </div>
                <div class="stat-box miss">
                    Polled At<br /><strong
                        >{liveSnapshot.polled_at?.slice(11, 19) ??
                            "N/A"}</strong
                    >
                </div>
            </div>
        </div>
    {:else if !elixirStatus}
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
    .btn-group {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
        justify-content: flex-end;
    }
    .elixir-btn {
        background: #7c3aed;
        color: white;
        border: none;
        padding: 0.6rem 1.1rem;
        border-radius: 8px;
        font-weight: bold;
        cursor: pointer;
        font-size: 0.85rem;
        transition: background 0.2s;
    }
    .elixir-btn.ws {
        background: #059669;
    }
    .elixir-btn.disconnect {
        background: #dc2626;
    }
    .elixir-btn:hover {
        filter: brightness(1.15);
    }

    .ws-status {
        margin-top: 0.75rem;
        font-size: 0.82rem;
        color: #888;
        padding: 0.4rem 0.8rem;
        background: rgba(255, 255, 255, 0.04);
        border-radius: 6px;
        border: 1px solid #333;
    }
    .ws-status.connected {
        color: #2ecc71;
        border-color: #2ecc71;
        background: rgba(46, 204, 113, 0.06);
    }

    .live-box {
        margin-top: 0.75rem;
        border: 1px solid #7c3aed;
        border-radius: 8px;
        padding: 0.75rem 1rem;
    }
    .live-header {
        font-size: 0.8rem;
        color: #a78bfa;
        margin-bottom: 0.5rem;
        font-weight: bold;
    }
</style>
