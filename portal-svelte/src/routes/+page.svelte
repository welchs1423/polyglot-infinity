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
	import ChartsPanel from "$lib/components/panels/ChartsPanel.svelte";
	import DependencyMapPanel from "$lib/components/panels/DependencyMapPanel.svelte";
	import LogsPanel from "$lib/components/panels/LogsPanel.svelte";

	// ── 탭 정의 ──────────────────────────────────────────────
	const TABS = [
		{ id: "all", label: "전체", emoji: "🌈" },
		{ id: "infra", label: "인프라", emoji: "⚙️" },
		{ id: "finance", label: "금융분석", emoji: "📈" },
		{ id: "concurrency", label: "동시성", emoji: "⚡" },
		{ id: "functional", label: "함수형", emoji: "λ" },
		{ id: "paradigm", label: "패러다임", emoji: "🧠" },
		{ id: "monitor", label: "모니터링", emoji: "📊" },
	];

	// 패널 → 탭 매핑
	const PANEL_TABS = /** @type {Record<string, string[]>} */ ({
		SystemStatus: ["all", "infra", "monitor"],
		RustPipeline: ["all", "infra"],
		PythonBrain: ["all", "infra"],
		LuaCache: ["all", "infra"],
		Julia: ["all", "finance"],
		Kotlin: ["all", "concurrency"],
		Elixir: ["all", "concurrency", "functional"],
		R: ["all", "finance"],
		FSharp: ["all", "finance", "functional"],
		Wasm: ["all", "finance"],
		OCaml: ["all", "finance", "functional"],
		Crystal: ["all", "concurrency"],
		Nim: ["all", "finance", "paradigm"],
		Scala: ["all", "finance", "functional", "concurrency"],
		Haskell: ["all", "finance", "functional"],
		Ruby: ["all", "paradigm"],
		Dart: ["all", "finance"],
		Gleam: ["all", "functional"],
		V: ["all", "finance", "paradigm"],
		Erlang: ["all", "concurrency", "paradigm"],
		LuaStream: ["all", "concurrency"],
		SwiftActor: ["all", "concurrency"],
		ClojureSTM: ["all", "concurrency"],
		JavaLoom: ["all", "concurrency"],
		Prolog: ["all", "paradigm"],
		Charts: ["all", "finance", "monitor"],
		DependencyMap: ["all", "monitor"],
		Logs: ["all", "monitor"],
	});

	/** @param {string} panel */
	function show(panel) {
		return PANEL_TABS[panel]?.includes(activeTab) ?? true;
	}

	// ── 상태 ─────────────────────────────────────────────────
	let activeTab = $state("all");
	/** @type {any[]} */
	let logs = $state([]);

	// 상태바: SSE로 실시간 서비스 온라인 수 추적
	let onlineCount = $state(0);
	let totalCount = $state(22);
	let sseConnected = $state(false);
	/** @type {EventSource | null} */
	let sse = null;

	// auto-refresh: 상태바 폴백 폴링 주기 (SSE 연결 실패 시)
	const REFRESH_OPTIONS = [
		{ label: "수동", value: 0 },
		{ label: "10s", value: 10 },
		{ label: "30s", value: 30 },
		{ label: "60s", value: 60 },
	];
	let refreshInterval = $state(30); // 기본 30초
	/** @type {ReturnType<typeof setInterval> | null} */
	let refreshTimer = null;

	function startSSE() {
		if (sse) sse.close();
		sse = new EventSource("http://localhost:8080/api/aggregate/stream");
		sse.onmessage = (e) => {
			try {
				const d = JSON.parse(e.data);
				onlineCount = d.online ?? 0;
				totalCount = d.total ?? 22;
				sseConnected = true;
			} catch {
				/* ignore */
			}
		};
		sse.onerror = () => {
			sseConnected = false;
		};
	}

	async function pollAggregate() {
		try {
			const res = await fetch("http://localhost:8080/api/aggregate");
			if (res.ok) {
				const d = await res.json();
				onlineCount = d.online ?? 0;
				totalCount = d.total ?? 22;
			}
		} catch {
			/* offline */
		}
	}

	function applyRefreshTimer() {
		if (refreshTimer) {
			clearInterval(refreshTimer);
			refreshTimer = null;
		}
		if (refreshInterval > 0 && !sseConnected) {
			refreshTimer = setInterval(pollAggregate, refreshInterval * 1000);
		}
	}

	$effect(() => {
		// sseConnected 또는 refreshInterval 변경 시 폴링 타이머 재설정
		applyRefreshTimer();
	});

	async function fetchLogs() {
		try {
			const res = await fetch("http://localhost:8080/api/history");
			if (res.ok) logs = await res.json();
		} catch {
			/* ignore */
		}
	}

	onMount(() => {
		fetchLogs();
		startSSE();
		pollAggregate(); // 즉시 한 번 폴링 (SSE 연결 전 초기값)
	});

	onDestroy(() => {
		sse?.close();
		if (refreshTimer) clearInterval(refreshTimer);
	});

	// 탭별 패널 개수 (뱃지용)
	/** @param {string} tabId */
	function tabCount(tabId) {
		return Object.values(PANEL_TABS).filter((tabs) => tabs.includes(tabId))
			.length;
	}
</script>

<main class="container">
	<h1 class="title">Polyglot Infinity Portal</h1>

	<!-- ── 상태바 ───────────────────────────────────────────── -->
	<div class="status-bar">
		<div class="status-left">
			<span class="status-dot" class:online={sseConnected}></span>
			<span class="status-label">
				{sseConnected ? "실시간 연결됨" : "폴링 모드"}
			</span>
			<span class="status-count">
				<span class="count-online">{onlineCount}</span>
				<span class="count-sep">/</span>
				<span class="count-total">{totalCount}</span>
				<span class="count-label">온라인</span>
			</span>
			<div class="online-bar">
				<div
					class="online-fill"
					style="width:{totalCount > 0
						? (onlineCount / totalCount) * 100
						: 0}%"
				></div>
			</div>
		</div>
		<div class="status-right">
			<label class="refresh-label">자동갱신</label>
			<select
				class="refresh-select"
				bind:value={refreshInterval}
				onchange={applyRefreshTimer}
			>
				{#each REFRESH_OPTIONS as opt}
					<option value={opt.value}>{opt.label}</option>
				{/each}
			</select>
			<button
				class="refresh-btn"
				onclick={pollAggregate}
				title="지금 새로고침">↺</button
			>
		</div>
	</div>

	<!-- ── 탭 네비게이션 ────────────────────────────────────── -->
	<nav class="tab-nav">
		{#each TABS as tab}
			<button
				class="tab-btn"
				class:active={activeTab === tab.id}
				onclick={() => (activeTab = tab.id)}
			>
				<span class="tab-emoji">{tab.emoji}</span>
				{tab.label}
				<span class="tab-badge">{tabCount(tab.id)}</span>
			</button>
		{/each}
	</nav>

	<!-- ── 패널 ─────────────────────────────────────────────── -->
	{#if show("SystemStatus")}
		<SystemStatusPanel onSync={fetchLogs} />
	{/if}
	{#if show("RustPipeline")}
		<RustPipelinePanel onTrigger={fetchLogs} />
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
	{#if show("Charts")}
		<ChartsPanel />
	{/if}
	{#if show("DependencyMap")}
		<DependencyMapPanel />
	{/if}
	{#if show("Logs")}
		<LogsPanel {logs} />
	{/if}
</main>

<style>
	/* ── 상태바 ─────────────────────────────────────────────── */
	.status-bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		background: #1e293b;
		border: 1px solid #334155;
		border-radius: 10px;
		padding: 0.6rem 1rem;
		margin-bottom: 1rem;
		gap: 1rem;
		flex-wrap: wrap;
	}
	.status-left {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}
	.status-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: #475569;
		flex-shrink: 0;
	}
	.status-dot.online {
		background: #22c55e;
		box-shadow: 0 0 6px #22c55e;
		animation: pulse 2s infinite;
	}
	@keyframes pulse {
		0%,
		100% {
			opacity: 1;
		}
		50% {
			opacity: 0.5;
		}
	}
	.status-label {
		font-size: 0.78rem;
		color: #64748b;
		white-space: nowrap;
	}
	.status-count {
		display: flex;
		align-items: baseline;
		gap: 0.2rem;
		font-family: monospace;
	}
	.count-online {
		color: #22c55e;
		font-size: 1.15rem;
		font-weight: 700;
	}
	.count-sep {
		color: #475569;
		font-size: 1rem;
	}
	.count-total {
		color: #94a3b8;
		font-size: 1rem;
	}
	.count-label {
		color: #64748b;
		font-size: 0.78rem;
		margin-left: 0.2rem;
	}
	.online-bar {
		width: 80px;
		height: 6px;
		background: #1e3a2a;
		border-radius: 3px;
		overflow: hidden;
	}
	.online-fill {
		height: 100%;
		background: #22c55e;
		border-radius: 3px;
		transition: width 0.5s ease;
	}
	.status-right {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.refresh-label {
		font-size: 0.78rem;
		color: #64748b;
	}
	.refresh-select {
		background: #0f172a;
		color: #94a3b8;
		border: 1px solid #334155;
		border-radius: 4px;
		padding: 0.2rem 0.4rem;
		font-size: 0.78rem;
		cursor: pointer;
	}
	.refresh-btn {
		background: #1e3a5f;
		color: #60a5fa;
		border: 1px solid #1d4ed8;
		border-radius: 4px;
		padding: 0.2rem 0.5rem;
		cursor: pointer;
		font-size: 0.85rem;
	}
	.refresh-btn:hover {
		background: #1d4ed8;
	}

	/* ── 탭 네비게이션 ──────────────────────────────────────── */
	.tab-nav {
		display: flex;
		gap: 0.4rem;
		flex-wrap: wrap;
		margin-bottom: 1.5rem;
		padding: 0.5rem;
		background: #1e293b;
		border-radius: 10px;
		border: 1px solid #334155;
	}
	.tab-btn {
		display: flex;
		align-items: center;
		gap: 0.3rem;
		background: transparent;
		color: #64748b;
		border: 1px solid transparent;
		border-radius: 6px;
		padding: 0.35rem 0.75rem;
		font-size: 0.82rem;
		cursor: pointer;
		transition: all 0.15s;
		white-space: nowrap;
	}
	.tab-btn:hover {
		background: #0f172a;
		color: #94a3b8;
	}
	.tab-btn.active {
		background: #0f172a;
		color: #e2e8f0;
		border-color: #3b82f6;
	}
	.tab-emoji {
		font-size: 0.9rem;
	}
	.tab-badge {
		background: #0f172a;
		color: #475569;
		border-radius: 10px;
		padding: 0 0.4rem;
		font-size: 0.7rem;
		font-family: monospace;
	}
	.tab-btn.active .tab-badge {
		background: #1e3a5f;
		color: #60a5fa;
	}
</style>
