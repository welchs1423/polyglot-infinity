<script>
	import { onMount } from "svelte";
	import SystemStatusPanel from "$lib/components/panels/SystemStatusPanel.svelte";
	import RustPipelinePanel from "$lib/components/panels/RustPipelinePanel.svelte";
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
	import SwiftPanel from "$lib/components/panels/SwiftPanel.svelte";
	import LuaStreamPanel from "$lib/components/panels/LuaStreamPanel.svelte";
	import SwiftActorPanel from "$lib/components/panels/SwiftActorPanel.svelte";
	import ClojureSTMPanel from "$lib/components/panels/ClojureSTMPanel.svelte";
	import JavaLoomPanel from "$lib/components/panels/JavaLoomPanel.svelte";
	import LogsPanel from "$lib/components/panels/LogsPanel.svelte";

	/** @type {any[]} */
	let logs = $state([]);

	async function fetchLogs() {
		try {
			const res = await fetch("http://localhost:8080/api/history");
			if (res.ok) logs = await res.json();
		} catch {
			console.error("Failed to fetch logs");
		}
	}

	onMount(() => {
		fetchLogs();
	});
</script>

<main class="container">
	<h1 class="title">Polyglot Infinity Portal</h1>

	<SystemStatusPanel onSync={fetchLogs} />
	<RustPipelinePanel onTrigger={fetchLogs} />
	<LuaCachePanel />
	<JuliaPanel />
	<KotlinPanel />
	<ElixirPanel />
	<RPanel />
	<FSharpPanel />
	<WasmPanel />
	<OCamlPanel />
	<CrystalPanel />
	<NimPanel />
	<ScalaPanel />
	<HaskellPanel />
	<RubyPanel />
	<DartPanel />
	<GleamPanel />
	<VPanel />
	<ErlangPanel />
	<SwiftPanel />
	<LuaStreamPanel />
	<SwiftActorPanel />
	<ClojureSTMPanel />
	<JavaLoomPanel />
	<LogsPanel {logs} />
</main>
