<script>
	import { onMount } from "svelte";
	import ServiceCard from "$lib/components/ServiceCard.svelte";

	// Base URL of the Go gateway. All API calls are routed through it.
	const API_BASE = "http://localhost:8080";
	const WS_URL = "ws://localhost:8080/ws";

	// ── WebSocket order feed ──────────────────────────────────────────────────
	// wsStatus: current connection state displayed in the feed header.
	// orderEvents: ring buffer of the last 50 received events (newest first).
	// wsConn: raw WebSocket instance kept outside $state to avoid Svelte
	//         wrapping a native object that is not serialisable.
	/** @type {'connecting'|'connected'|'disconnected'|'error'} */
	let wsStatus = $state("disconnected");
	/** @type {Array<{order_id:string, type:string, event:string, prev_status:string, new_status:string, timestamp:number}>} */
	let orderEvents = $state([]);
	/** @type {WebSocket|null} */
	let wsConn = null;

	function connectOrderFeed() {
		wsStatus = "connecting";
		const ws = new WebSocket(WS_URL);
		wsConn = ws;

		ws.onopen = () => {
			wsStatus = "connected";
		};

		ws.onmessage = (evt) => {
			try {
				const data = JSON.parse(evt.data);
				orderEvents = [data, ...orderEvents].slice(0, 50);
			} catch {
				// ignore non-JSON frames
			}
		};

		ws.onclose = () => {
			wsStatus = "disconnected";
			wsConn = null;
			setTimeout(connectOrderFeed, 3000);
		};

		ws.onerror = () => {
			wsStatus = "error";
		};
	}

	// Static service registry. Defines every language microservice in this platform.
	// aggregateName: the exact 'name' value returned by GET /api/aggregate, or null for
	// services not covered by that endpoint (the gateway itself and artifact servers).
	const SERVICES = [
		{
			key: "go",
			name: "Go-Hub",
			aggregateName: null,
			lang: "Go",
			port: 8080,
			role: "Gateway / Orchestrator",
		},
		{
			key: "python",
			name: "Python-Brain",
			aggregateName: "Python-Brain",
			lang: "Python",
			port: 8000,
			role: "ML Engine / Redis Cache",
		},
		{
			key: "rust",
			name: "Rust-Pipeline",
			aggregateName: "Rust-Pipeline",
			lang: "Rust",
			port: 8081,
			role: "VaR Risk Pipeline",
		},
		{
			key: "julia",
			name: "Julia-Engine",
			aggregateName: "Julia-Engine",
			lang: "Julia",
			port: 8002,
			role: "Monte Carlo Engine",
		},
		{
			key: "r",
			name: "R-Stats",
			aggregateName: "R-Stats",
			lang: "R",
			port: 8003,
			role: "Statistical Analysis",
		},
		{
			key: "fsharp",
			name: "FSharp-Pricer",
			aggregateName: "FSharp-Pricer",
			lang: "F#",
			port: 9001,
			role: "Implied Volatility (NR)",
		},
		{
			key: "ocaml",
			name: "OCaml-Risk",
			aggregateName: "OCaml-Risk",
			lang: "OCaml",
			port: 8004,
			role: "Risk Engine",
		},
		{
			key: "crystal",
			name: "Crystal-GW",
			aggregateName: "Crystal-Gateway",
			lang: "Crystal",
			port: 9002,
			role: "High-Perf Gateway",
		},
		{
			key: "nim",
			name: "Nim-Analytics",
			aggregateName: "Nim-Analytics",
			lang: "Nim",
			port: 8005,
			role: "GARCH Volatility",
		},
		{
			key: "scala",
			name: "Scala-Streamer",
			aggregateName: "Scala-Streamer",
			lang: "Scala",
			port: 9003,
			role: "Akka Streams",
		},
		{
			key: "haskell",
			name: "Haskell-Pricer",
			aggregateName: "Haskell-Pricer",
			lang: "Haskell",
			port: 8006,
			role: "Black-Scholes Pricer",
		},
		{
			key: "ruby",
			name: "Ruby-Scorer",
			aggregateName: "Ruby-Scorer",
			lang: "Ruby",
			port: 9004,
			role: "Credit Scorer",
		},
		{
			key: "dart",
			name: "Dart-Engine",
			aggregateName: "Dart-Engine",
			lang: "Dart",
			port: 9005,
			role: "Async HTTP Engine",
		},
		{
			key: "gleam",
			name: "Gleam-Hub",
			aggregateName: "Gleam-Hub",
			lang: "Gleam",
			port: 4001,
			role: "Type-Safe Hub",
		},
		{
			key: "v",
			name: "V-Quant",
			aggregateName: "V-Quant",
			lang: "V",
			port: 4002,
			role: "Quant Finance",
		},
		{
			key: "erlang",
			name: "Erlang-Hot",
			aggregateName: "Erlang-Hot",
			lang: "Erlang",
			port: 4003,
			role: "Hot Code Reload",
		},
		{
			key: "elixir",
			name: "Elixir-Hub",
			aggregateName: "Elixir-Hub",
			lang: "Elixir",
			port: 4000,
			role: "Phoenix PubSub",
		},
		{
			key: "clojure",
			name: "Clojure-STM",
			aggregateName: "Clojure-STM",
			lang: "Clojure",
			port: 8009,
			role: "STM Ledger",
		},
		{
			key: "java",
			name: "Java-Loom",
			aggregateName: "Java-Loom",
			lang: "Java",
			port: 8010,
			role: "Virtual Threads",
		},
		{
			key: "prolog",
			name: "Prolog-Solver",
			aggregateName: "Prolog-Solver",
			lang: "Prolog",
			port: 8011,
			role: "Logic Solver",
		},
		{
			key: "lua",
			name: "Lua-Stream",
			aggregateName: "Lua-Stream",
			lang: "Lua",
			port: 8007,
			role: "Coroutine Mux",
		},
		{
			key: "swift",
			name: "Swift-Actor",
			aggregateName: "Swift-Actor",
			lang: "Swift",
			port: 8008,
			role: "Actor Concurrency",
		},
		{
			key: "kotlin",
			name: "Kotlin-Sched",
			aggregateName: "Kotlin-Scheduler",
			lang: "Kotlin",
			port: 9000,
			role: "Coroutine Scheduler",
		},
		{
			key: "cpp",
			name: "C++-Core",
			aggregateName: null,
			lang: "C++",
			port: 8012,
			role: "Compute Library (FFI)",
		},
		{
			key: "zig",
			name: "Zig-Core",
			aggregateName: null,
			lang: "Zig",
			port: 8013,
			role: "Systems Core (FFI)",
		},
		{
			key: "wasm",
			name: "Wasm-Finance",
			aggregateName: null,
			lang: "WASM",
			port: 8014,
			role: "WebAssembly Module",
		},
	];

	// Dynamic status for each service, keyed by SERVICES[i].key.
	// status:    "loading" | "online" | "offline"
	// latencyMs: round-trip milliseconds measured client-side, or null
	// result:    short summary string for display in the card, or null
	/** @type {Record<string, { status: string, latencyMs: number | null, result: string | null }>} */
	let statuses = $state(
		Object.fromEntries(
			SERVICES.map((s) => [
				s.key,
				{ status: "loading", latencyMs: null, result: null },
			]),
		),
	);

	// Derived count of services currently reporting "online".
	let onlineCount = $derived(
		Object.values(statuses).filter((s) => s.status === "online").length,
	);

	// True while the initial (or manual) fetch cycle is in-flight.
	let loading = $state(true);

	// Non-null when the aggregate fetch fails and the gateway is unreachable.
	/** @type {string | null} */
	let fetchError = $state(null);

	// Resets all service statuses to "loading" and re-fetches from all sources concurrently.
	async function fetchStatus() {
		loading = true;
		fetchError = null;

		for (const svc of SERVICES) {
			statuses[svc.key] = {
				status: "loading",
				latencyMs: null,
				result: null,
			};
		}

		await Promise.allSettled([
			fetchAggregate(),
			fetchGoHub(),
			fetchArtifactServer("cpp", 8012),
			fetchArtifactServer("zig", 8013),
			fetchArtifactServer("wasm", 8014),
		]);

		loading = false;
	}

	// Calls GET /api/aggregate and maps each returned service entry onto statuses.
	// The aggregate endpoint covers all 22 language services managed by the Go gateway.
	async function fetchAggregate() {
		try {
			const res = await fetch(`${API_BASE}/api/aggregate`);
			if (!res.ok) throw new Error(`HTTP ${res.status}`);

			/** @type {{ services?: Array<{ name: string, port: number, status: string, latency_ms: number }> }} */
			const data = await res.json();

			// Index remote results by name for O(1) lookup.
			/** @type {Map<string, { name: string, port: number, status: string, latency_ms: number }>} */
			const byName = new Map(
				(data.services ?? []).map((s) => [s.name, s]),
			);

			for (const svc of SERVICES) {
				if (!svc.aggregateName) continue;
				const remote = byName.get(svc.aggregateName);
				if (!remote) continue;
				statuses[svc.key] = {
					status: remote.status,
					latencyMs: remote.latency_ms,
					result:
						remote.status === "online"
							? `${remote.latency_ms}ms`
							: null,
				};
			}
		} catch {
			fetchError = "Gateway unreachable";
			for (const svc of SERVICES) {
				if (!svc.aggregateName) continue;
				statuses[svc.key] = {
					status: "offline",
					latencyMs: null,
					result: null,
				};
			}
		}
	}

	// Health-checks the Go gateway itself via GET /api/status.
	// Confirms the gateway is operational and surfaces the DB connection state.
	async function fetchGoHub() {
		const t0 = performance.now();
		try {
			const res = await fetch(`${API_BASE}/api/status`);
			const latencyMs = Math.round(performance.now() - t0);
			if (res.ok) {
				/** @type {{ database?: string }} */
				const data = await res.json();
				statuses["go"] = {
					status: "online",
					latencyMs,
					result: data.database
						? `db: ${data.database}`
						: `${latencyMs}ms`,
				};
			} else {
				statuses["go"] = { status: "offline", latencyMs, result: null };
			}
		} catch {
			statuses["go"] = {
				status: "offline",
				latencyMs: null,
				result: null,
			};
		}
	}

	// Health-checks an artifact HTTP server by issuing a HEAD request to its root.
	// These containers serve static binary files via python http.server or nginx;
	// they have no JSON API. A 200 or 405 response confirms the server is reachable.
	/** @param {string} key @param {number} port */
	async function fetchArtifactServer(key, port) {
		const t0 = performance.now();
		try {
			const res = await fetch(`http://localhost:${port}/`, {
				method: "HEAD",
			});
			const latencyMs = Math.round(performance.now() - t0);
			const up = res.ok || res.status === 405;
			statuses[key] = {
				status: up ? "online" : "offline",
				latencyMs: up ? latencyMs : null,
				result: up ? `${latencyMs}ms` : null,
			};
		} catch {
			statuses[key] = {
				status: "offline",
				latencyMs: null,
				result: null,
			};
		}
	}

	onMount(() => {
		fetchStatus();
		connectOrderFeed();
		return () => {
			if (wsConn) wsConn.close();
		};
	});
</script>

<div class="page">
	<header class="page-header">
		<div class="header-left">
			<h1 class="page-title">Polyglot Infinity</h1>
			<span class="page-subtitle"
				>Multi-Language Microservices Dashboard</span
			>
		</div>

		<div class="header-right">
			{#if fetchError}
				<span class="error-banner">{fetchError}</span>
			{/if}

			<div class="counter-badge">
				<span class="count-online">{onlineCount}</span>
				<span class="count-sep">/</span>
				<span class="count-total">{SERVICES.length}</span>
				<span class="count-label">online</span>
			</div>

			<button
				class="btn-refresh"
				onclick={fetchStatus}
				disabled={loading}
			>
				{loading ? "Loading…" : "Refresh"}
			</button>
		</div>
	</header>

	<div class="grid">
		{#each SERVICES as svc (svc.key)}
			<ServiceCard
				name={svc.name}
				lang={svc.lang}
				port={svc.port}
				role={svc.role}
				status={statuses[svc.key].status}
				latencyMs={statuses[svc.key].latencyMs}
				result={statuses[svc.key].result}
			/>
		{/each}
	</div>

	<section class="order-feed">
		<div class="feed-header">
			<h2 class="feed-title">Order Event Feed</h2>
			<span class="feed-source">Java Loom &rarr; Redis &rarr; Go WS</span>
			<span class="ws-badge ws-badge--{wsStatus}">{wsStatus}</span>
		</div>

		{#if orderEvents.length === 0}
			<p class="feed-empty">Waiting for order events&hellip;</p>
		{:else}
			<div class="feed-table-wrap">
				<table class="feed-table">
					<thead>
						<tr>
							<th>Order ID</th>
							<th>Type</th>
							<th>Event</th>
							<th>Prev Status</th>
							<th>New Status</th>
							<th>Time</th>
						</tr>
					</thead>
					<tbody>
						{#each orderEvents as evt (evt.timestamp + evt.order_id + evt.event)}
							<tr class="feed-row">
								<td class="mono">{evt.order_id}</td>
								<td
									><span
										class="tag tag--{evt.type?.toLowerCase()}"
										>{evt.type}</span
									></td
								>
								<td>{evt.event}</td>
								<td class="status-cell"
									>{evt.prev_status || "—"}</td
								>
								<td class="status-cell status-cell--new"
									>{evt.new_status}</td
								>
								<td class="mono ts"
									>{new Date(
										evt.timestamp,
									).toLocaleTimeString()}</td
								>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</section>
</div>

<style>
	.page {
		max-width: 1600px;
		margin: 0 auto;
	}

	.page-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		flex-wrap: wrap;
		gap: 1rem;
		margin-bottom: 2rem;
		padding-bottom: 1.5rem;
		border-bottom: 1px solid #1e293b;
	}

	.header-left {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	/* Override the global .title gradient with a flat page-specific style. */
	.page-title {
		margin: 0;
		font-size: 1.8rem;
		font-weight: 700;
		letter-spacing: -0.025em;
		color: #f1f5f9;
		background: none;
		-webkit-background-clip: unset;
		background-clip: unset;
		-webkit-text-fill-color: unset;
	}

	.page-subtitle {
		font-size: 0.75rem;
		color: #64748b;
		letter-spacing: 0.07em;
		text-transform: uppercase;
	}

	.header-right {
		display: flex;
		align-items: center;
		gap: 0.875rem;
		flex-wrap: wrap;
	}

	.error-banner {
		font-size: 0.75rem;
		color: #fca5a5;
		background: #450a0a2a;
		border: 1px solid #ef444430;
		border-radius: 6px;
		padding: 0.3rem 0.8rem;
	}

	.counter-badge {
		display: flex;
		align-items: baseline;
		gap: 0.28rem;
		background: #1e293b;
		border: 1px solid #334155;
		border-radius: 8px;
		padding: 0.5rem 1rem;
	}

	.count-online {
		font-size: 1.4rem;
		font-weight: 700;
		color: #22c55e;
		line-height: 1;
	}

	.count-sep {
		color: #475569;
	}

	.count-total {
		font-size: 1rem;
		color: #94a3b8;
	}

	.count-label {
		font-size: 0.68rem;
		color: #64748b;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		margin-left: 0.15rem;
	}

	.btn-refresh {
		background: #1e293b;
		border: 1px solid #334155;
		border-radius: 8px;
		color: #94a3b8;
		font-size: 0.8rem;
		padding: 0.5rem 1.1rem;
		cursor: pointer;
		transition:
			background 0.15s ease,
			color 0.15s ease;
	}

	.btn-refresh:hover:not(:disabled) {
		background: #334155;
		color: #e2e8f0;
	}

	.btn-refresh:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}

	/* Responsive grid: minimum card width 210px, fills all available columns. */
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
		gap: 1rem;
	}

	/* ── Order Event Feed ─────────────────────────────────────────────────── */
	.order-feed {
		margin-top: 2.5rem;
		background: #0f172a;
		border: 1px solid #1e293b;
		border-radius: 12px;
		overflow: hidden;
	}

	.feed-header {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 1rem 1.25rem;
		border-bottom: 1px solid #1e293b;
		flex-wrap: wrap;
	}

	.feed-title {
		margin: 0;
		font-size: 0.95rem;
		font-weight: 600;
		color: #e2e8f0;
	}

	.feed-source {
		font-size: 0.72rem;
		color: #475569;
		flex: 1;
	}

	.ws-badge {
		font-size: 0.68rem;
		font-weight: 600;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		padding: 0.25rem 0.65rem;
		border-radius: 100px;
	}

	.ws-badge--connected {
		background: #14532d40;
		color: #4ade80;
		border: 1px solid #16a34a50;
	}
	.ws-badge--connecting {
		background: #1e3a5f40;
		color: #60a5fa;
		border: 1px solid #2563eb50;
	}
	.ws-badge--disconnected {
		background: #1e293b;
		color: #64748b;
		border: 1px solid #33415550;
	}
	.ws-badge--error {
		background: #450a0a40;
		color: #f87171;
		border: 1px solid #ef444450;
	}

	.feed-empty {
		padding: 2rem 1.25rem;
		color: #475569;
		font-size: 0.85rem;
		text-align: center;
	}

	.feed-table-wrap {
		overflow-x: auto;
	}

	.feed-table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.8rem;
	}

	.feed-table th {
		padding: 0.6rem 1rem;
		text-align: left;
		font-size: 0.68rem;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: #475569;
		background: #0f172a;
		border-bottom: 1px solid #1e293b;
	}

	.feed-row td {
		padding: 0.55rem 1rem;
		border-bottom: 1px solid #1e293b20;
		color: #94a3b8;
		white-space: nowrap;
	}

	.feed-row:first-child td {
		color: #e2e8f0;
		background: #1e293b30;
	}

	.mono {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.75rem;
	}

	.ts {
		color: #475569;
	}

	.tag {
		display: inline-block;
		padding: 0.15rem 0.5rem;
		border-radius: 4px;
		font-size: 0.7rem;
		font-weight: 600;
	}

	.tag--buy {
		background: #14532d40;
		color: #4ade80;
	}
	.tag--sell {
		background: #450a0a40;
		color: #f87171;
	}

	.status-cell {
		color: #64748b;
	}
	.status-cell--new {
		color: #38bdf8;
		font-weight: 600;
	}
</style>
