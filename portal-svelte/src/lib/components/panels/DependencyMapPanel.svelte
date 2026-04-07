<script>
    import { onMount } from "svelte";

    // 노드 정의: [id, label, port, color, x%, y%]
    /** @type {Array<{id:string, label:string, port:string, color:string, x:number, y:number}>} */
    const NODES = [
        // 프론트엔드
        {
            id: "svelte",
            label: "Svelte 5",
            port: ":5173",
            color: "#ff3e00",
            x: 50,
            y: 5,
        },
        // 메인 허브
        {
            id: "go",
            label: "Go Hub",
            port: ":8080",
            color: "#00acd7",
            x: 50,
            y: 20,
        },
        // 데이터 레이어
        {
            id: "redis",
            label: "Redis",
            port: ":6379",
            color: "#dc382c",
            x: 15,
            y: 35,
        },
        {
            id: "pg8080",
            label: "PostgreSQL",
            port: ":5432",
            color: "#336791",
            x: 32,
            y: 35,
        },
        // 핵심 분석
        {
            id: "python",
            label: "Python",
            port: ":8000",
            color: "#3572a5",
            x: 70,
            y: 35,
        },
        {
            id: "rust",
            label: "Rust Axum",
            port: ":8081",
            color: "#dea584",
            x: 85,
            y: 35,
        },
        // Python FFI
        {
            id: "cpp",
            label: "C++ FFI",
            port: "lib",
            color: "#555555",
            x: 60,
            y: 50,
        },
        {
            id: "zig",
            label: "Zig FFI",
            port: "lib",
            color: "#f7a41d",
            x: 75,
            y: 50,
        },
        {
            id: "julia",
            label: "Julia",
            port: ":8002",
            color: "#9558b2",
            x: 88,
            y: 50,
        },
        // Rust DB
        {
            id: "pg8081",
            label: "PostgreSQL",
            port: ":5433",
            color: "#336791",
            x: 95,
            y: 35,
        },
        // 독립 서비스들 (좌측 열)
        {
            id: "kotlin",
            label: "Kotlin",
            port: ":9000",
            color: "#f18e33",
            x: 5,
            y: 55,
        },
        {
            id: "elixir",
            label: "Elixir",
            port: ":4000",
            color: "#6e4a7e",
            x: 5,
            y: 65,
        },
        { id: "r", label: "R", port: ":8003", color: "#276dc3", x: 5, y: 75 },
        {
            id: "fsharp",
            label: "F#",
            port: ":9001",
            color: "#378bba",
            x: 18,
            y: 55,
        },
        {
            id: "ocaml",
            label: "OCaml",
            port: ":8004",
            color: "#ee7832",
            x: 18,
            y: 65,
        },
        {
            id: "crystal",
            label: "Crystal",
            port: ":9002",
            color: "#000000",
            x: 18,
            y: 75,
        },
        // 중간 열
        {
            id: "nim",
            label: "Nim",
            port: ":8005",
            color: "#ffe953",
            x: 32,
            y: 55,
        },
        {
            id: "scala",
            label: "Scala",
            port: ":9003",
            color: "#dc322f",
            x: 32,
            y: 65,
        },
        {
            id: "haskell",
            label: "Haskell",
            port: ":8006",
            color: "#5e5086",
            x: 32,
            y: 75,
        },
        {
            id: "ruby",
            label: "Ruby",
            port: ":9004",
            color: "#cc342d",
            x: 45,
            y: 55,
        },
        {
            id: "dart",
            label: "Dart",
            port: ":9005",
            color: "#00b4ab",
            x: 45,
            y: 65,
        },
        {
            id: "gleam",
            label: "Gleam",
            port: ":4001",
            color: "#ffaff3",
            x: 45,
            y: 75,
        },
        // 우측 열
        { id: "v", label: "V", port: ":4002", color: "#5d87bf", x: 60, y: 65 },
        {
            id: "erlang",
            label: "Erlang",
            port: ":4003",
            color: "#b83998",
            x: 60,
            y: 75,
        },
        {
            id: "lua",
            label: "Lua Coroutine",
            port: ":8007",
            color: "#000080",
            x: 72,
            y: 65,
        },
        {
            id: "swift",
            label: "Swift Actor",
            port: ":8008",
            color: "#f05138",
            x: 72,
            y: 75,
        },
        {
            id: "clojure",
            label: "Clojure STM",
            port: ":8009",
            color: "#5881d8",
            x: 82,
            y: 65,
        },
        {
            id: "java",
            label: "Java Loom",
            port: ":8010",
            color: "#007396",
            x: 82,
            y: 75,
        },
        {
            id: "prolog",
            label: "Prolog",
            port: ":8011",
            color: "#8b0000",
            x: 92,
            y: 65,
        },
        // 브라우저 특별
        {
            id: "wasm",
            label: "WASM",
            port: "browser",
            color: "#654ff0",
            x: 92,
            y: 75,
        },
    ];

    // 엣지: [from, to, label?]
    /** @type {Array<{from:string, to:string, label?:string, style?:string}>} */
    const EDGES = [
        { from: "svelte", to: "go", label: "fetch" },
        { from: "svelte", to: "wasm", label: "WASM", style: "dashed" },
        { from: "go", to: "redis", label: "Lua EVAL" },
        { from: "go", to: "pg8080", label: "SQL" },
        { from: "go", to: "python", label: "proxy" },
        { from: "go", to: "rust", label: "proxy" },
        { from: "go", to: "kotlin", label: "proxy" },
        { from: "go", to: "elixir", label: "proxy" },
        { from: "go", to: "r", label: "proxy" },
        { from: "go", to: "fsharp", label: "proxy" },
        { from: "go", to: "ocaml", label: "proxy" },
        { from: "go", to: "crystal", label: "proxy" },
        { from: "go", to: "nim", label: "proxy" },
        { from: "go", to: "scala", label: "proxy" },
        { from: "go", to: "haskell", label: "proxy" },
        { from: "go", to: "ruby", label: "proxy" },
        { from: "go", to: "dart", label: "proxy" },
        { from: "go", to: "gleam", label: "proxy" },
        { from: "go", to: "v", label: "proxy" },
        { from: "go", to: "erlang", label: "proxy" },
        { from: "go", to: "lua", label: "proxy" },
        { from: "go", to: "swift", label: "proxy" },
        { from: "go", to: "clojure", label: "proxy" },
        { from: "go", to: "java", label: "proxy" },
        { from: "go", to: "prolog", label: "proxy" },
        { from: "python", to: "cpp", label: "ctypes" },
        { from: "python", to: "zig", label: "ctypes" },
        { from: "python", to: "julia", label: "HTTP" },
        { from: "rust", to: "pg8081", label: "sqlx" },
    ];

    const W = 900,
        H = 540;

    /** @param {typeof NODES[0]} n */
    function nx(n) {
        return (n.x / 100) * W;
    }
    /** @param {typeof NODES[0]} n */
    function ny(n) {
        return (n.y / 100) * H;
    }

    const nodeMap = Object.fromEntries(NODES.map((n) => [n.id, n]));

    // tooltip
    let hoverId = $state("");
</script>

<section class="panel depmap-panel">
    <div class="panel-header">
        <div>
            <h2>🗺️ 서비스 의존성 맵</h2>
            <p class="subtitle">27개 언어/런타임 · 2개 DB · 호출 관계 시각화</p>
        </div>
        <span class="node-count">{NODES.length} 노드 · {EDGES.length} 엣지</span
        >
    </div>

    <div class="map-scroll">
        <svg viewBox="0 0 {W} {H}" width="100%" class="dep-svg">
            <!-- 엣지 -->
            {#each EDGES as e}
                {@const a = nodeMap[e.from]}
                {@const b = nodeMap[e.to]}
                {#if a && b}
                    <line
                        x1={nx(a)}
                        y1={ny(a)}
                        x2={nx(b)}
                        y2={ny(b)}
                        stroke={e.style === "dashed" ? "#f59e0b" : "#334155"}
                        stroke-width={e.style === "dashed" ? 1.5 : 0.8}
                        stroke-dasharray={e.style === "dashed" ? "4 3" : "none"}
                        opacity="0.6"
                    />
                {/if}
            {/each}

            <!-- 노드 -->
            {#each NODES as n}
                {@const isHovered = hoverId === n.id}
                <g
                    role="button"
                    tabindex="0"
                    transform="translate({nx(n)},{ny(n)})"
                    onmouseenter={() => (hoverId = n.id)}
                    onmouseleave={() => (hoverId = "")}
                    style="cursor:pointer"
                >
                    <circle
                        r={isHovered ? 14 : 10}
                        fill={n.color || "#6366f1"}
                        stroke={isHovered ? "#fff" : "#1e293b"}
                        stroke-width={isHovered ? 2 : 1}
                        opacity={n.port === "browser" ? 0.7 : 1}
                    />
                    <text
                        dy={-14}
                        text-anchor="middle"
                        fill={isHovered ? "#fff" : "#cbd5e1"}
                        font-size={isHovered ? 11 : 9}
                        font-family="monospace"
                        font-weight={isHovered ? "bold" : "normal"}
                        >{n.label}</text
                    >
                    <text
                        dy={22}
                        text-anchor="middle"
                        fill="#64748b"
                        font-size="8"
                        font-family="monospace">{n.port}</text
                    >
                </g>
            {/each}
        </svg>
    </div>

    <!-- 범례 -->
    <div class="legend">
        <div class="legend-item">
            <svg width="24" height="8"
                ><line
                    x1="0"
                    y1="4"
                    x2="24"
                    y2="4"
                    stroke="#334155"
                    stroke-width="1.5"
                /></svg
            >
            <span>HTTP 프록시 / 직접 호출</span>
        </div>
        <div class="legend-item">
            <svg width="24" height="8"
                ><line
                    x1="0"
                    y1="4"
                    x2="24"
                    y2="4"
                    stroke="#f59e0b"
                    stroke-width="1.5"
                    stroke-dasharray="4 3"
                /></svg
            >
            <span>브라우저 직접 (WASM)</span>
        </div>
        <div class="legend-item">
            <circle
                cx="6"
                cy="6"
                r="6"
                fill="#dc382c"
                style="display:inline-block;width:12px;height:12px;border-radius:50%;vertical-align:middle;margin-right:4px"
            ></circle>
            <span>DB / 인프라</span>
        </div>
    </div>
</section>

<style>
    .depmap-panel {
        background: #0f172a;
        border: 1px solid #1e3a5f;
    }

    .node-count {
        font-size: 0.8rem;
        color: #475569;
        white-space: nowrap;
    }

    .map-scroll {
        overflow-x: auto;
        border: 1px solid #1e293b;
        border-radius: 8px;
        background: #050d1a;
    }

    .dep-svg {
        display: block;
        min-width: 600px;
    }

    .legend {
        display: flex;
        gap: 1.5rem;
        flex-wrap: wrap;
        margin-top: 0.75rem;
        padding-top: 0.75rem;
        border-top: 1px solid #1e293b;
    }

    .legend-item {
        display: flex;
        align-items: center;
        gap: 0.4rem;
        font-size: 0.78rem;
        color: #64748b;
    }
</style>
