<script>
	import { onMount, onDestroy } from "svelte";
	import SystemStatusPanel from "$lib/components/panels/SystemStatusPanel.svelte";
	import RustPipelinePanel from "$lib/components/panels/RustPipelinePanel.svelte";
	import PythonBrainPanel from "$lib/components/panels/PythonBrainPanel.svelte";
	import LuaCachePanel from "$lib/components/panels/LuaCachePanel.svelte";
	import JuliaPanel from "$lib/components/panels/JuliaPanel.svelte";
	import KotlinPanel from "$lib/components/panels/KotlinPanel.svelte";
	import ElixirPanel from "$lib/components/panels/ElixirPanel.svelte";
	import RPanel from "$lib/components/panels/RPanel.svelte";
	import FSharpPanel from "$lib/components/panels/FSharpPanel.svelte";
	import WasmPanel from "$lib/components/panels/WasmPanel.svelte";
	import OCamlPanel from "$lib/components/panels/OCamlPanel.svelte";
	import CrystalPanel from "$lib/components/panels/CrystalPanel.svelte";
	import NimPanel from "$lib/components/panels/NimPanel.svelte";
	import ScalaPanel from "$lib/components/panels/ScalaPanel.svelte";
	import HaskellPanel from "$lib/components/panels/HaskellPanel.svelte";
	import RubyPanel from "$lib/components/panels/RubyPanel.svelte";
	import DartPanel from "$lib/components/panels/DartPanel.svelte";
	import GleamPanel from "$lib/components/panels/GleamPanel.svelte";
	import VPanel from "$lib/components/panels/VPanel.svelte";
	import ErlangPanel from "$lib/components/panels/ErlangPanel.svelte";
	import LuaStreamPanel from "$lib/components/panels/LuaStreamPanel.svelte";
	import SwiftActorPanel from "$lib/components/panels/SwiftActorPanel.svelte";
	import ClojureSTMPanel from "$lib/components/panels/ClojureSTMPanel.svelte";
	import JavaLoomPanel from "$lib/components/panels/JavaLoomPanel.svelte";
	import PrologPanel from "$lib/components/panels/PrologPanel.svelte";
	import BSComparePanel from "$lib/components/panels/BSComparePanel.svelte";
	import WorkflowPanel from "$lib/components/panels/WorkflowPanel.svelte";
	import ChartsPanel from "$lib/components/panels/ChartsPanel.svelte";
	import DependencyMapPanel from "$lib/components/panels/DependencyMapPanel.svelte";
	import LogsPanel from "$lib/components/panels/LogsPanel.svelte";

	// Go gateway base URL. Points to the central reverse proxy server.
	const GO_HUB = "http://localhost:8080";

	// Tab definitions. Each tab filters the visible panel set.
	const TABS = [
		{ id: "all",         label: "전체",    emoji: "all" },
		{ id: "infra",       label: "인프라",   emoji: "infra" },
		{ id: "finance",     label: "금융분석", emoji: "finance" },
		{ id: "concurrency", label: "동시성",   emoji: "concurrency" },
		{ id: "functional",  label: "함수형",   emoji: "functional" },
		{ id: "paradigm",    label: "패러다임", emoji: "paradigm" },
		{ id: "monitor",     label: "모니터링", emoji: "monitor" },
	];

	// Maps each panel key to the tabs under which it is visible.
	const PANEL_TABS = /** @type {Record<string, string[]>} */ ({
		SystemStatus: ["all", "infra", "monitor"],
		RustPipeline: ["all", "infra"],
		PythonBrain:  ["all", "infra"],
		LuaCache:     ["all", "infra"],
		Julia:        ["all", "finance"],
		Kotlin:       ["all", "concurrency"],
		Elixir:       ["all", "concurrency", "functional"],
		R:            ["all", "finance"],
		FSharp:       ["all", "finance", "functional"],
		Wasm:         ["all", "finance"],
		OCaml:        ["all", "finance", "functional"],
		Crystal:      ["all", "concurrency"],
		Nim:          ["all", "finance", "paradigm"],
		Scala:        ["all", "finance", "functional", "concurrency"],
		Haskell:      ["all", "finance", "functional"],
		Ruby:         ["all", "paradigm"],
		Dart:         ["all", "finance"],
		Gleam:        ["all", "functional"],
		V:            ["all", "finance", "paradigm"],
		Erlang:       ["all", "concurrency", "paradigm"],
		LuaStream:    ["all", "concurrency"],
		SwiftActor:   ["all", "concurrency"],
		ClojureSTM:   ["all", "concurrency"],
		JavaLoom:     ["all", "concurrency"],
		Prolog:       ["all", "paradigm"],
		BSCompare:    ["all", "finance"],
		Workflow:     ["all", "infra", "monitor"],
		Charts:       ["all", "finance", "monitor"],
		DependencyMap:["all", "monitor"],
		Logs:         ["all", "monitor"],
	});

	/**
	 * Returns true when the given panel key is included in the active tab.
	 * @param {string} panel
	 */
	function show(panel) {
		return PANEL_TABS[panel]?.includes(activeTab) ?? true;
	}

	// Active tab key. Drives conditional rendering of all panel components.
	let activeTab = $state("all");

	// DB system-log rows fetched from GET /api/history.
	/** @type {any[]} */
	let logs = $state([]);

	// Counts derived from SSE aggregate stream (GET /api/aggregate/stream).
	let onlineCount = $state(0);
	let totalCount  = $state(22);
	let sseConnected = $state(false);

	/** @type {EventSource | null} */
	let sse = null;

	// Transient notification banners displayed at the top of the page.
	/** @type {{ id: number, type: string, msg: string }[]} */
	let notifications = $state([]);
	let notifId = 0;

	/**
	 * Pushes a notification banner and auto-dismisses it after 4 seconds.
	 * @param {"info"|"ok"|"error"} type - Controls the banner colour class.
	 * @param {string} msg
	 */
	function addNotif(type, msg) {
		const id = ++notifId;
		notifications = [...notifications, { id, type, msg }];
		setTimeout(() => {
			notifications = notifications.filter((n) => n.id !== id);
		}, 4000);
	}

	/**
	 * Fetches the 10 most recent system-log rows from the Go gateway and
	 * stores them in the logs reactive variable for the LogsPanel.
	 */
	async function fetchLogs() {
		try {
			const res = await fetch(`${GO_HUB}/api/history`);
			if (res.ok) logs = await res.json();
		} catch {
			// History fetch failure is non-critical; leave existing rows visible.
		}
	}

	/**
	 * Opens a persistent EventSource connection to GET /api/aggregate/stream.
	 * The Go server pushes a full service-health snapshot every 10 seconds.
	 * Each message updates onlineCount, totalCount, and sseConnected.
	 */
	function connectSSE() {
		if (sse) return;
		sse = new EventSource(`${GO_HUB}/api/aggregate/stream`);
		sseConnected = true;

		sse.onmessage = (event) => {
			try {
				const data = JSON.parse(event.data);
				// data.online and data.total are set by buildAggregate in Go.
				onlineCount  = data.online  ?? onlineCount;
				totalCount   = data.total   ?? totalCount;
				sseConnected = true;
			} catch {
				// Malformed SSE frame; ignore and wait for next tick.
			}
		};

		sse.onerror = () => {
			sseConnected = false;
			sse?.close();
			sse = null;
			// Reconnect after 5 seconds if the connection drops.
			setTimeout(connectSSE, 5000);
		};
	}

	/**
	 * Called by SystemStatusPanel when a manual sync completes.
	 * Refreshes the log panel to reflect any new DB entries.
	 */
	function handleSync() {
		fetchLogs();
		addNotif("ok", "Go 게이트웨이 동기화 완료");
	}

	// Initial data load and SSE connection start on component mount.
	onMount(() => {
		fetchLogs();
		connectSSE();
	});

	// Close the SSE connection when the component is removed from the DOM.
	onDestroy(() => {
		sse?.close();
		sse = null;
	});
</script>

<!-- Notification banners rendered above all content. -->
<div class="notif-container">
	{#each notifications as n (n.id)}
		<div class="notif notif-{n.type}">{n.msg}</div>
	{/each}
</div>

<div class="container">
	<!-- Page header: title and live service counter. -->
	<header class="page-header">
		<h1 class="title">Polyglot Infinity</h1>
		<div class="service-counter">
			<span class="counter-label">Services</span>
			<span class="counter-online">{onlineCount}</span>
			<span class="counter-sep">/</span>
			<span class="counter-total">{totalCount}</span>
			<span class="sse-dot" class:sse-dot-live={sseConnected} title={sseConnected ? "SSE connected" : "SSE disconnected"}></span>
		</div>
	</header>

	<!-- Tab bar: filters the visible panel set. -->
	<nav class="tab-bar" role="tablist">
		{#each TABS as tab}
			<button
				role="tab"
				aria-selected={activeTab === tab.id}
				class="tab-btn"
				class:tab-active={activeTab === tab.id}
				onclick={() => (activeTab = tab.id)}
			>
				{tab.label}
			</button>
		{/each}
	</nav>

	<!-- Panel grid: each panel is self-contained and manages its own API calls. -->
	<!-- Panels are hidden via display:none rather than destroyed to preserve state across tab switches. -->

	{#if show("SystemStatus")}
		<SystemStatusPanel onSync={handleSync} />
	{/if}

	{#if show("RustPipeline")}
		<RustPipelinePanel />
	{/if}

	{#if show("PythonBrain")}
		<PythonBrainPanel />
	{/if}

	{#if show("LuaCache")}
		<LuaCachePanel />
	{/if}

	{#if show("Julia")}
		<JuliaPanel />
	{/if}

	{#if show("Kotlin")}
		<KotlinPanel />
	{/if}

	{#if show("Elixir")}
		<ElixirPanel />
	{/if}

	{#if show("R")}
		<RPanel />
	{/if}

	{#if show("FSharp")}
		<FSharpPanel />
	{/if}

	{#if show("Wasm")}
		<WasmPanel />
	{/if}

	{#if show("OCaml")}
		<OCamlPanel />
	{/if}

	{#if show("Crystal")}
		<CrystalPanel />
	{/if}

	{#if show("Nim")}
		<NimPanel />
	{/if}

	{#if show("Scala")}
		<ScalaPanel />
	{/if}

	{#if show("Haskell")}
		<HaskellPanel />
	{/if}

	{#if show("Ruby")}
		<RubyPanel />
	{/if}

	{#if show("Dart")}
		<DartPanel />
	{/if}

	{#if show("Gleam")}
		<GleamPanel />
	{/if}

	{#if show("V")}
		<VPanel />
	{/if}

	{#if show("Erlang")}
		<ErlangPanel />
	{/if}

	{#if show("LuaStream")}
		<LuaStreamPanel />
	{/if}

	{#if show("SwiftActor")}
		<SwiftActorPanel />
	{/if}

	{#if show("ClojureSTM")}
		<ClojureSTMPanel />
	{/if}

	{#if show("JavaLoom")}
		<JavaLoomPanel />
	{/if}

	{#if show("Prolog")}
		<PrologPanel />
	{/if}

	{#if show("BSCompare")}
		<BSComparePanel />
	{/if}

	{#if show("Workflow")}
		<WorkflowPanel />
	{/if}

	{#if show("Charts")}
		<ChartsPanel />
	{/if}

	{#if show("DependencyMap")}
		<DependencyMapPanel />
	{/if}

	{#if show("Logs")}
		<!-- LogsPanel receives log rows as a prop; rows are owned by +page.svelte. -->
		<LogsPanel {logs} />
	{/if}
</div>

<style>
	/* Page-level header: title on the left, service counter on the right. */
	.page-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 1.5rem;
		flex-wrap: wrap;
		gap: 0.75rem;
	}

	/* Service counter badge displayed next to the page title. */
	.service-counter {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		background: #1e293b;
		border: 1px solid #334155;
		border-radius: 8px;
		padding: 0.5rem 1rem;
		font-size: 0.9rem;
	}

	.counter-label {
		color: #64748b;
		font-size: 0.8rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.counter-online {
		font-weight: bold;
		color: #22c55e;
		font-size: 1.2rem;
	}

	.counter-sep {
		color: #475569;
	}

	.counter-total {
		color: #94a3b8;
		font-size: 1rem;
	}

	/* SSE connection status indicator dot. */
	.sse-dot {
		display: inline-block;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: #475569;
		margin-left: 0.3rem;
		transition: background 0.4s;
	}

	.sse-dot-live {
		background: #22c55e;
		/* Pulse animation signals that the SSE stream is actively receiving data. */
		animation: pulse 2s infinite;
	}

	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50%       { opacity: 0.4; }
	}

	/* Tab navigation bar. */
	.tab-bar {
		display: flex;
		gap: 0.4rem;
		flex-wrap: wrap;
		margin-bottom: 1.5rem;
	}

	.tab-btn {
		background: #1e293b;
		color: #94a3b8;
		border: 1px solid #334155;
		padding: 0.45rem 1rem;
		border-radius: 6px;
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		transition: background 0.15s, color 0.15s, border-color 0.15s;
	}

	.tab-btn:hover {
		background: #334155;
		color: #e2e8f0;
	}

	.tab-active {
		background: #2563eb;
		color: #fff;
		border-color: #2563eb;
	}

	/* Notification banner container anchored to the top of the viewport. */
	.notif-container {
		position: fixed;
		top: 1rem;
		right: 1rem;
		z-index: 1000;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		pointer-events: none;
	}

	.notif {
		padding: 0.7rem 1.2rem;
		border-radius: 8px;
		font-size: 0.85rem;
		font-weight: 600;
		max-width: 320px;
		animation: slidein 0.2s ease-out;
	}

	@keyframes slidein {
		from { opacity: 0; transform: translateX(20px); }
		to   { opacity: 1; transform: translateX(0); }
	}

	.notif-ok {
		background: #052e16;
		border: 1px solid #16a34a;
		color: #86efac;
	}

	.notif-error {
		background: #450a0a;
		border: 1px solid #dc2626;
		color: #fca5a5;
	}

	.notif-info {
		background: #1e1b4b;
		border: 1px solid #6366f1;
		color: #a5b4fc;
	}
</style>
