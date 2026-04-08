<script>
    import { API_BASE } from "$lib/api";
    import { onDestroy } from "svelte";

    /** @type {any | null} */
    let elixirStatus = $state(null);
    /** @type {any | null} */
    let liveSnapshot = $state(null);
    /** @type {boolean} */
    let wsConnected = $state(false);
    /** @type {string} */
    let wsLog = $state("");
    /** @type {number} */
    let snapshotCount = $state(0);
    /** @type {boolean} */
    let autoReconnect = $state(false);

    // Phoenix channel wire 포맷: [join_ref, ref, topic, event, payload]
    /** @type {WebSocket | null} */
    let ws = null;
    /** @type {any} */
    let heartbeatTimer = 0;
    /** @type {any} */
    let reconnectTimer = 0;
    let reconnectDelay = 3000; // ms, exponential backoff
    let refCounter = 1;
    let intentionalClose = false;

    async function checkElixir() {
        try {
            const res = await fetch(`${API_BASE}/api/hub/status`);
            if (res.ok) elixirStatus = await res.json();
            else elixirStatus = { status: "offline" };
        } catch {
            elixirStatus = { status: "offline" };
        }
    }

    function scheduleReconnect() {
        if (!autoReconnect || intentionalClose) return;
        wsLog = `${reconnectDelay / 1000}s 후 재연결 시도...`;
        reconnectTimer = setTimeout(() => {
            if (autoReconnect && !intentionalClose) {
                reconnectDelay = Math.min(reconnectDelay * 2, 30000);
                connectWS();
            }
        }, reconnectDelay);
    }

    function connectWS() {
        clearTimeout(reconnectTimer);
        intentionalClose = false;
        if (ws) {
            ws.close();
            ws = null;
        }

        const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0";
        ws = new WebSocket(url);
        wsLog = "연결 시도 중...";

        ws.onopen = () => {
            wsConnected = true;
            reconnectDelay = 3000; // 성공 시 백오프 초기화
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
                    snapshotCount++;
                    wsLog = `마지막 수신: ${new Date().toLocaleTimeString()} (총 ${snapshotCount}회)`;
                }
            } catch {
                /* ignore */
            }
        };

        ws.onclose = () => {
            wsConnected = false;
            clearInterval(heartbeatTimer);
            if (!intentionalClose) {
                wsLog = "연결 끊김 — 재연결 대기...";
                scheduleReconnect();
            } else {
                wsLog = "연결 해제됨";
            }
        };

        ws.onerror = () => {
            wsLog = "연결 실패 — Elixir 서버(:4000)를 먼저 실행하세요";
        };
    }

    function toggleAutoReconnect() {
        autoReconnect = !autoReconnect;
        if (autoReconnect) {
            reconnectDelay = 3000;
            connectWS();
        } else {
            intentionalClose = true;
            clearTimeout(reconnectTimer);
            ws?.close();
            ws = null;
            wsConnected = false;
            wsLog = "자동 재연결 OFF — 수동 연결 사용하세요";
        }
    }

    function disconnectWS() {
        intentionalClose = true;
        clearTimeout(reconnectTimer);
        ws?.close();
        ws = null;
        wsConnected = false;
        clearInterval(heartbeatTimer);
        wsLog = "연결 해제됨";
    }

    onDestroy(() => {
        intentionalClose = true;
        clearTimeout(reconnectTimer);
        clearInterval(heartbeatTimer);
        ws?.close();
    });
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
            <button
                class="elixir-btn auto {autoReconnect ? 'active' : ''}"
                onclick={toggleAutoReconnect}
            >
                {autoReconnect ? "⏸ 자동 재연결 ON" : "🔄 자동 재연결"}
            </button>
            {#if wsConnected}
                <button class="elixir-btn disconnect" onclick={disconnectWS}
                    >WS 해제</button
                >
            {:else if !autoReconnect}
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
                📡 실시간 스냅숏 (Elixir GenServer 10s 주기 브로드캐스트 · 총 {snapshotCount}회
                수신)
            </div>
            <div class="stats-row">
                <div class="stat-box hit">
                    Elixir Hub<br /><strong
                        >{liveSnapshot.elixir_hub ?? "online"}</strong
                    >
                </div>
                <div class="stat-box engine">
                    Go Status<br /><strong
                        >{liveSnapshot.status ??
                            liveSnapshot.go_status ??
                            "N/A"}</strong
                    >
                </div>
                <div class="stat-box miss">
                    DB Layer<br /><strong
                        >{liveSnapshot.database ?? "N/A"}</strong
                    >
                </div>
                <div class="stat-box hit">
                    Polled At<br /><strong
                        >{liveSnapshot.polled_at?.slice(11, 19) ??
                            "N/A"}</strong
                    >
                </div>
            </div>
            {#if liveSnapshot.engine_analysis?.version}
                <div class="engine-row">
                    <span class="eng-label">🐍 Python Engine:</span>
                    <span class="eng-val"
                        >{liveSnapshot.engine_analysis.version}</span
                    >
                    <span class="eng-sub"
                        >{liveSnapshot.engine_analysis.recommendation ??
                            ""}</span
                    >
                </div>
            {/if}
            {#if liveSnapshot.pipeline_node?.status === "online"}
                <div class="engine-row">
                    <span class="eng-label">🦀 Rust Pipeline:</span>
                    <span class="eng-val"
                        >{liveSnapshot.pipeline_node.module ?? "online"}</span
                    >
                    {#if liveSnapshot.pipeline_node.total_risk_logs !== undefined}
                        <span class="eng-sub"
                            >logs: {liveSnapshot.pipeline_node.total_risk_logs.toLocaleString()}</span
                        >
                    {/if}
                </div>
            {/if}
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
    .elixir-btn.auto {
        background: #1e293b;
        border: 1px solid #7c3aed;
        color: #a78bfa;
    }
    .elixir-btn.auto.active {
        background: #4c1d95;
        color: #fff;
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
    .engine-row {
        display: flex;
        align-items: baseline;
        gap: 0.5rem;
        margin-top: 0.4rem;
        font-size: 0.82rem;
    }
    .eng-label {
        color: #94a3b8;
        font-size: 0.78rem;
    }
    .eng-val {
        color: #e2e8f0;
        font-weight: 700;
    }
    .eng-sub {
        color: #64748b;
        font-family: monospace;
        font-size: 0.75rem;
    }
</style>
