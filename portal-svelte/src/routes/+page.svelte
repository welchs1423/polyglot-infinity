<script>
	import { onMount, onDestroy } from "svelte";

	/** @type {any} */
	let systemData = $state(null);

	/** @type {string | null} */
	let errorMsg = $state(null);

	/** @type {any[]} */
	let logs = $state([]);

	/** @type {{ status: string, inserted_rows?: number, elapsed_time_ms?: number, message?: string } | null} */
	let pipelineResult = $state(null);

	/** @type {boolean} */
	let pipelineLoading = $state(false);

	/** @type {boolean} */
	let autoSync = $state(false);

	/** @type {number | null} */
	let autoSyncInterval = $state(null);

	/** @type {any[] | null} */
	let reports = $state(null);

	/** @type {any | null} */
	let juliaResult = $state(null);

	/** @type {boolean} */
	let juliaLoading = $state(false);

	/** @type {any | null} */
	let cacheStats = $state(null);

	/** @type {any | null} */
	let elixirStatus = $state(null);

	/** @type {any | null} */
	let rFit = $state(null);

	/** @type {boolean} */
	let rLoading = $state(false);

	/** @type {any | null} */
	let fsharpOption = $state(null);

	/** @type {boolean} */
	let fsharpLoading = $state(false);

	/** @type {any} */
	let wasmExports = null;
	/** @type {boolean} */
	let wasmLoaded = $state(false);
	/** @type {any | null} */
	let wasmBsResult = $state(null);
	/** @type {boolean} */
	let wasmLoading = $state(false);

	async function syncSystem() {
		try {
			const res = await fetch("http://localhost:8080/api/status");
			if (!res.ok) throw new Error("System Offline");
			systemData = await res.json();
			errorMsg = null;
			fetchLogs();
		} catch (err) {
			errorMsg = err instanceof Error ? err.message : "Unknown Error";
			systemData = null;
		}
	}

	async function fetchLogs() {
		try {
			const res = await fetch("http://localhost:8080/api/history");
			if (res.ok) logs = await res.json();
		} catch (err) {
			console.error("Failed to fetch logs");
		}
	}

	async function triggerPipeline() {
		pipelineLoading = true;
		pipelineResult = null;
		try {
			const res = await fetch(
				"http://localhost:8080/api/pipeline/trigger",
				{ method: "POST" },
			);
			pipelineResult = await res.json();
			fetchLogs();
		} catch (err) {
			pipelineResult = {
				status: "error",
				message: "Rust Pipeline unreachable",
			};
		} finally {
			pipelineLoading = false;
		}
	}

	function toggleAutoSync() {
		autoSync = !autoSync;
		if (autoSync) {
			syncSystem();
			autoSyncInterval = setInterval(syncSystem, 10000);
		} else {
			if (autoSyncInterval !== null) clearInterval(autoSyncInterval);
			autoSyncInterval = null;
		}
	}

	onDestroy(() => {
		if (autoSyncInterval !== null) clearInterval(autoSyncInterval);
	});

	async function fetchReports() {
		try {
			const res = await fetch("http://localhost:9000/api/reports/latest");
			if (res.ok) reports = await res.json();
		} catch {
			reports = null;
		}
	}

	async function runJulia() {
		juliaLoading = true;
		juliaResult = null;
		try {
			const res = await fetch(
				"http://localhost:8002/api/julia/simulate?paths=10000&days=252&vol=0.20&mu=0.05",
			);
			if (res.ok) juliaResult = await res.json();
			else juliaResult = { error: "Julia engine offline" };
		} catch {
			juliaResult = { error: "Julia engine unreachable" };
		} finally {
			juliaLoading = false;
		}
	}

	async function fetchCacheStats() {
		try {
			const res = await fetch("http://localhost:8080/api/cache/stats");
			if (res.ok) cacheStats = await res.json();
		} catch {
			cacheStats = null;
		}
	}

	async function checkElixir() {
		try {
			const res = await fetch("http://localhost:4000/health");
			if (res.ok) elixirStatus = await res.json();
			else elixirStatus = { status: "offline" };
		} catch {
			elixirStatus = { status: "offline" };
		}
	}

	async function runRFit() {
		rLoading = true;
		rFit = null;
		try {
			const res = await fetch("http://localhost:8003/api/r/fit?n=1000");
			if (res.ok) rFit = await res.json();
			else rFit = { error: "R engine offline" };
		} catch {
			rFit = { error: "R engine unreachable" };
		} finally {
			rLoading = false;
		}
	}

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

	async function runWasm() {
		wasmLoading = true;
		try {
			if (!wasmExports) {
				const res = await fetch("/finance.wasm");
				const bytes = await res.arrayBuffer();
				const { instance } = await WebAssembly.instantiate(bytes, {});
				wasmExports = instance.exports;
				wasmLoaded = true;
			}
			const exp = wasmExports;
			wasmBsResult = {
				call: exp.bsCall(100, 100, 0.05, 0.2, 1.0),
				put: exp.bsPut(100, 100, 0.05, 0.2, 1.0),
				delta: exp.bsDelta(100, 100, 0.05, 0.2, 1.0),
				gamma: exp.bsGamma(100, 100, 0.05, 0.2, 1.0),
				var95: exp.varNormal(0.0005, 0.018, 0.95),
				dcf: exp.dcfValue(1_000_000, 0.1, 0.03, 0.08, 5),
			};
		} catch (e) {
			wasmBsResult = { error: String(e) };
		} finally {
			wasmLoading = false;
		}
	}

	/** @type {any | null} */
	let ocamlRisk = $state(null);
	/** @type {boolean} */
	let ocamlLoading = $state(false);

	async function runOcamlRisk() {
		ocamlLoading = true;
		ocamlRisk = null;
		try {
			const [riskRes, scoreRes] = await Promise.all([
				fetch(
					"http://localhost:8004/api/ocaml/risk?debt_ratio=0.75&volatility=0.28&leverage=3.5&credit_score=650",
				),
				fetch(
					"http://localhost:8004/api/ocaml/score?income=5000000&debt=2000000&history_years=3&missed_payments=1",
				),
			]);
			if (riskRes.ok && scoreRes.ok) {
				const risk = await riskRes.json();
				const score = await scoreRes.json();
				ocamlRisk = {
					...risk,
					credit_grade: score.grade,
					credit_score_model: score.score,
					prob_good: score.prob_good,
				};
			} else {
				ocamlRisk = { error: "OCaml 리스크 엔진 오프라인" };
			}
		} catch {
			ocamlRisk = { error: "OCaml 엔진 접속 불가 (:8004)" };
		} finally {
			ocamlLoading = false;
		}
	}

	/** @type {any | null} */
	let crystalData = $state(null);
	/** @type {boolean} */
	let crystalLoading = $state(false);

	async function runCrystal() {
		crystalLoading = true;
		crystalData = null;
		try {
			const [pfRes, fxRes] = await Promise.all([
				fetch('http://localhost:9002/api/crystal/portfolio?mu=0.12&sigma=0.18&days=252'),
				fetch('http://localhost:9002/api/crystal/fx'),
			]);
			if (pfRes.ok && fxRes.ok) {
				const pf = await pfRes.json();
				const fx = await fxRes.json();
				crystalData = { ...pf, weighted_krw: fx.weighted_krw, rates: fx.rates };
			} else {
				crystalData = { error: 'Crystal 게이트웨이 오프라인' };
			}
		} catch {
			crystalData = { error: 'Crystal 서버 접속 불가 (:9002)' };
		} finally {
			crystalLoading = false;
		}
	}
</script>

<main class="container">
	<h1 class="title">Polyglot Infinity Portal</h1>

	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>System Status</h2>
				<p class="subtitle">Svelte 5 ↔ Go ↔ Python ↔ Rust ↔ DB</p>
			</div>
			<div class="btn-group">
				<button
					class="auto-btn {autoSync ? 'active' : ''}"
					onclick={toggleAutoSync}
				>
					{autoSync ? "⏸ Auto-Sync ON" : "▶ Auto-Sync"}
				</button>
				<button class="sync-btn" onclick={syncSystem}
					>Sync System</button
				>
			</div>
		</div>

		{#if errorMsg}
			<div class="error-box">
				<p>⚠️ {errorMsg}</p>
			</div>
		{:else if systemData}
			<div class="card-grid">
				<div class="status-card">
					<h3>🏹 Go (Backend)</h3>
					<p class="status online">● {systemData.status}</p>
					<span class="version">{systemData.system}</span>
				</div>

				<div class="status-card">
					<h3>🗄️ PostgreSQL / Redis</h3>
					<p
						class="status {systemData.database === 'connected'
							? 'online'
							: 'error'}"
					>
						● {systemData.database}
					</p>
					<span class="version">Data & Cache Layer</span>
				</div>

				<div class="status-card">
					<h3>🐍 Python (Engine)</h3>
					{#if systemData.engine_analysis.version}
						<p class="status online">● online</p>
						<span class="version"
							>{systemData.engine_analysis.version}</span
						>
						<div class="badge">
							{systemData.engine_analysis.source}
						</div>

						<div class="financial-data">
							<p class="rate">
								💸 {systemData.engine_analysis.recommendation}
							</p>
							{#if systemData.engine_analysis.rates}
								<div class="currency-grid">
									{#each Object.entries(systemData.engine_analysis.rates) as [currency, value]}
										<span class="currency-chip"
											>{currency}: {typeof value ===
											"number"
												? value.toFixed(2)
												: value}</span
										>
									{/each}
								</div>
							{/if}
							<p class="risk">
								⚠️ Risk Score: {systemData.engine_analysis
									.computation_result}
							</p>
						</div>
					{:else}
						<p class="status error">● Offline</p>
					{/if}
				</div>

				<div class="status-card">
					<h3>⚡ Zig (Core)</h3>
					{#if systemData.engine_analysis?.zig_analysis?.engine}
						<p class="status online">● online</p>
						<span class="version"
							>{systemData.engine_analysis.zig_analysis
								.engine}</span
						>
						<div class="financial-data">
							<p class="rate">
								σ {systemData.engine_analysis.zig_analysis
									.volatility}
							</p>
							<p class="risk">
								VaR 95%: ₩{systemData.engine_analysis.zig_analysis.var_95?.toLocaleString()}
							</p>
						</div>
					{:else}
						<p class="status error">● Offline</p>
					{/if}
				</div>

				<div class="status-card">
					<h3>🦀 Rust (Pipeline)</h3>
					{#if systemData.pipeline_node.status === "online"}
						<p class="status online">
							● {systemData.pipeline_node.status}
						</p>
						<span class="version"
							>{systemData.pipeline_node.module}</span
						>
						{#if systemData.pipeline_node.total_risk_logs !== undefined}
							<span class="version"
								>DB records: {systemData.pipeline_node.total_risk_logs.toLocaleString()}</span
							>
						{/if}
					{:else}
						<p class="status error">● Offline</p>
					{/if}
				</div>
			</div>
		{:else}
			<div class="empty-box">
				<p>
					우측 상단의 Sync System 버튼을 눌러 전체 시스템을
					스캔하세요.
				</p>
			</div>
		{/if}
	</section>

	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>🦀 Rust Pipeline</h2>
				<p class="subtitle">10,000건 리스크 데이터 DB 일괄 적재</p>
			</div>
			<button
				class="trigger-btn"
				onclick={triggerPipeline}
				disabled={pipelineLoading}
			>
				{pipelineLoading ? "⏳ Running..." : "🚀 Trigger Bulk Insert"}
			</button>
		</div>

		{#if pipelineResult}
			{#if pipelineResult.status === "success"}
				<div class="pipeline-result success">
					<span class="result-icon">✅</span>
					<span
						><strong
							>{pipelineResult.inserted_rows?.toLocaleString()}</strong
						>건 적재 완료</span
					>
					<span class="result-time"
						>⏱ {pipelineResult.elapsed_time_ms}ms</span
					>
				</div>
			{:else}
				<div class="pipeline-result error-result">
					<span class="result-icon">❌</span>
					<span>{pipelineResult.message ?? "Unknown error"}</span>
				</div>
			{/if}
		{:else}
			<div class="empty-box">
				<p>버튼을 눌러 Rust 파이프라인을 가동하세요.</p>
			</div>
		{/if}
	</section>

	<!-- Lua Cache Stats Panel -->
	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>🌙 Lua Cache Stats</h2>
				<p class="subtitle">Redis EVAL 원자적 캐시 히트/미스 카운터</p>
			</div>
			<button class="lua-btn" onclick={fetchCacheStats}>조회</button>
		</div>
		{#if cacheStats}
			<div class="stats-row">
				<div class="stat-box hit">
					✅ Cache Hits<br /><strong>{cacheStats.cache_hits}</strong>
				</div>
				<div class="stat-box miss">
					🔄 Cache Misses<br /><strong
						>{cacheStats.cache_misses}</strong
					>
				</div>
				<div class="stat-box engine">
					⚙️ Engine<br /><strong>{cacheStats.engine}</strong>
				</div>
			</div>
		{:else}
			<div class="empty-box">
				<p>조회 버튼을 눌러 Lua 스크립트 통계를 확인하세요.</p>
			</div>
		{/if}
	</section>

	<!-- Julia Monte Carlo Panel -->
	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>🔬 Julia Monte Carlo</h2>
				<p class="subtitle">GBM 기반 병렬 시뮬레이션 · VaR/CVaR 95%</p>
			</div>
			<button
				class="julia-btn"
				onclick={runJulia}
				disabled={juliaLoading}
			>
				{juliaLoading ? "분석 중..." : "시뮬레이션"}
			</button>
		</div>
		{#if juliaResult}
			<div class="julia-grid">
				<div class="julia-card">
					<span class="jlabel">VaR 95%</span><span class="jval"
						>{(juliaResult.var_95 * 100).toFixed(2)}%</span
					>
				</div>
				<div class="julia-card">
					<span class="jlabel">CVaR 95%</span><span class="jval"
						>{(juliaResult.cvar_95 * 100).toFixed(2)}%</span
					>
				</div>
				<div class="julia-card">
					<span class="jlabel">평균 수익</span><span class="jval"
						>{(juliaResult.mean_return * 100).toFixed(2)}%</span
					>
				</div>
				<div class="julia-card">
					<span class="jlabel">변동성</span><span class="jval"
						>{(juliaResult.std_return * 100).toFixed(2)}%</span
					>
				</div>
				<div class="julia-card">
					<span class="jlabel">샤프 비율</span><span class="jval"
						>{juliaResult.sharpe.toFixed(3)}</span
					>
				</div>
				<div class="julia-card">
					<span class="jlabel">시뮬레이션 경로</span><span
						class="jval">{juliaResult.paths?.toLocaleString()}</span
					>
				</div>
			</div>
		{:else}
			<div class="empty-box">
				<p>
					버튼을 눌러 Julia GBM 몬테카를로 분석을 실행하세요. (Julia
					서버 :8002 필요)
				</p>
			</div>
		{/if}
	</section>

	<!-- Kotlin Reports Panel -->
	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>☕ Kotlin Reports</h2>
				<p class="subtitle">
					코루틴 스케줄러 · 리스크 리포트 생성 (:9000)
				</p>
			</div>
			<button class="kotlin-btn" onclick={fetchReports}
				>최신 리포트</button
			>
		</div>
		{#if reports && reports.length > 0}
			<table class="log-table">
				<thead
					><tr
						><th>ID</th><th>생성 시각</th><th>평균 리스크</th><th
							>총 기록</th
						><th>최대</th><th>최소</th></tr
					></thead
				>
				<tbody>
					{#each reports as r}
						<tr>
							<td class="log-id">#{r.id}</td>
							<td class="log-time"
								>{new Date(r.generatedAt).toLocaleString(
									"ko-KR",
								)}</td
							>
							<td
								><strong>{r.avgRiskScore?.toFixed(4)}</strong
								></td
							>
							<td>{r.totalRecords}</td>
							<td style="color:#f87171"
								>{r.maxRiskScore?.toFixed(4)}</td
							>
							<td style="color:#34d399"
								>{r.minRiskScore?.toFixed(4)}</td
							>
						</tr>
					{/each}
				</tbody>
			</table>
		{:else}
			<div class="empty-box">
				<p>
					버튼을 눌러 Kotlin 스케줄러 리포트를 불러오세요. (Kotlin
					서버 :9000 필요)
				</p>
			</div>
		{/if}
	</section>

	<!-- Elixir Hub Panel -->
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
					🕐 Uptime<br /><strong
						>{elixirStatus.uptime ?? "N/A"}</strong
					>
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

	<!-- R Stats Panel -->
	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>📊 R Distribution Fit</h2>
				<p class="subtitle">
					MLE 정규분포 피팅 · VaR/CVaR · Sharpe (Plumber :8003)
				</p>
			</div>
			<button class="r-btn" onclick={runRFit} disabled={rLoading}>
				{rLoading ? "분석 중..." : "분포 피팅"}
			</button>
		</div>
		{#if rFit && !rFit.error}
			<div class="julia-grid">
				<div class="julia-card r-card">
					<span class="jlabel">정규 평균 μ</span><span class="jval"
						>{(rFit.fit_normal.mean * 100).toFixed(4)}%</span
					>
				</div>
				<div class="julia-card r-card">
					<span class="jlabel">정규 표준편차 σ</span><span
						class="jval"
						>{(rFit.fit_normal.sd * 100).toFixed(4)}%</span
					>
				</div>
				<div class="julia-card r-card">
					<span class="jlabel">t분포 자유도</span><span class="jval"
						>{rFit.fit_t_df ?? "N/A"}</span
					>
				</div>
				<div class="julia-card r-card">
					<span class="jlabel">VaR 95%</span><span class="jval"
						>{(rFit.var_95 * 100).toFixed(3)}%</span
					>
				</div>
				<div class="julia-card r-card">
					<span class="jlabel">CVaR 95%</span><span class="jval"
						>{(rFit.cvar_95 * 100).toFixed(3)}%</span
					>
				</div>
				<div class="julia-card r-card">
					<span class="jlabel">Sharpe (연율)</span><span class="jval"
						>{rFit.sharpe_ratio}</span
					>
				</div>
			</div>
		{:else if rFit?.error}
			<div class="error-box">
				<p>⚠️ {rFit.error} — Rscript engine-r/run.R 으로 실행하세요.</p>
			</div>
		{:else}
			<div class="empty-box">
				<p>
					버튼을 눌러 R MLE 분포 피팅을 실행하세요. (R Plumber 서버
					:8003 필요)
				</p>
			</div>
		{/if}
	</section>

	<!-- F# Black-Scholes Panel -->
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
					버튼을 눌러 F# Black-Scholes 옵션 Greeks를 계산하세요. (F#
					서버 :9001 필요)
				</p>
			</div>
		{/if}
	</section>

	<!-- WebAssembly Panel -->
	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>🕸️ WebAssembly (Client-side)</h2>
				<p class="subtitle">
					Zig → WASM32 · 브라우저 직접 실행 · 서버 왕복 없음
				</p>
			</div>
			<button class="wasm-btn" onclick={runWasm} disabled={wasmLoading}>
				{#if wasmLoading}계산 중...{:else if wasmLoaded}재계산{:else}WASM
					로드 & 실행{/if}
			</button>
		</div>
		{#if wasmBsResult}
			{#if wasmBsResult.error}
				<div class="empty-box">
					<p style="color:#f87171">{wasmBsResult.error}</p>
				</div>
			{:else}
				<div class="julia-grid">
					<div class="julia-card wasm-card">
						<span class="jlabel">Call Price</span><span class="jval"
							>${wasmBsResult.call.toFixed(4)}</span
						>
					</div>
					<div class="julia-card wasm-card">
						<span class="jlabel">Put Price</span><span class="jval"
							>${wasmBsResult.put.toFixed(4)}</span
						>
					</div>
					<div class="julia-card wasm-card">
						<span class="jlabel">Delta</span><span class="jval"
							>{wasmBsResult.delta.toFixed(4)}</span
						>
					</div>
					<div class="julia-card wasm-card">
						<span class="jlabel">Gamma</span><span class="jval"
							>{wasmBsResult.gamma.toFixed(6)}</span
						>
					</div>
					<div class="julia-card wasm-card">
						<span class="jlabel">VaR 95%</span><span class="jval"
							>{(wasmBsResult.var95 * 100).toFixed(3)}%</span
						>
					</div>
					<div class="julia-card wasm-card">
						<span class="jlabel">DCF Value</span><span class="jval"
							>₩{Math.round(
								wasmBsResult.dcf,
							).toLocaleString()}</span
						>
					</div>
				</div>
				<p class="wasm-hint">
					✓ 서버 없이 브라우저에서 직접 계산됨 (S=100 K=100 r=5% σ=20%
					T=1y)
				</p>
			{/if}
		{:else}
			<div class="empty-box">
				<p>
					Zig로 컴파일된 WASM을 브라우저에서 직접 실행합니다. 서버
					없이 Black-Scholes · VaR · DCF 계산.
				</p>
			</div>
		{/if}
	</section>

	<!-- OCaml Panel -->
	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>🐪 OCaml (Risk Rule Engine)</h2>
				<p class="subtitle">
					OCaml 4.13 · 규칙 기반 리스크 판정 · 신용 스코어링 (:8004)
				</p>
			</div>
			<button
				class="ocaml-btn"
				onclick={runOcamlRisk}
				disabled={ocamlLoading}
			>
				{ocamlLoading ? "분석 중..." : "리스크 분석"}
			</button>
		</div>
		{#if ocamlRisk}
			{#if ocamlRisk.error}
				<div class="empty-box">
					<p style="color:#f87171">{ocamlRisk.error}</p>
				</div>
			{:else}
				<div class="julia-grid">
					<div class="julia-card ocaml-card">
						<span class="jlabel">Risk Level</span><span
							class="jval risk-{ocamlRisk.level?.toLowerCase()}"
							>{ocamlRisk.level}</span
						>
					</div>
					<div class="julia-card ocaml-card">
						<span class="jlabel">Risk Score</span><span class="jval"
							>{ocamlRisk.risk_score} / 100</span
						>
					</div>
					<div class="julia-card ocaml-card">
						<span class="jlabel">Credit Score</span><span
							class="jval">{ocamlRisk.credit_score_model}</span
						>
					</div>
					<div class="julia-card ocaml-card">
						<span class="jlabel">Credit Grade</span><span
							class="jval">{ocamlRisk.credit_grade}</span
						>
					</div>
					<div class="julia-card ocaml-card">
						<span class="jlabel">Debt Ratio</span><span class="jval"
							>{(ocamlRisk.debt_ratio * 100).toFixed(1)}%</span
						>
					</div>
					<div class="julia-card ocaml-card">
						<span class="jlabel">Volatility</span><span class="jval"
							>{(ocamlRisk.volatility * 100).toFixed(1)}%</span
						>
					</div>
				</div>
			{/if}
		{:else}
			<div class="empty-box">
				<p>
					버튼을 눌러 OCaml 규칙 기반 리스크 판정 · 신용 스코어링을
					실행하세요. (OCaml 서버 :8004 필요)
				</p>
			</div>
		{/if}
	</section>

	<!-- Crystal Panel -->
	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>🔮 Crystal (Portfolio Gateway)</h2>
				<p class="subtitle">Crystal 1.19 · Ruby 문법 + 네이티브 컴파일 · 포트폴리오 성과 + FX (:9002)</p>
			</div>
			<button class="crystal-btn" onclick={runCrystal} disabled={crystalLoading}>
				{crystalLoading ? '분석 중...' : '포트폴리오 분석'}
			</button>
		</div>
		{#if crystalData}
			{#if crystalData.error}
				<div class="empty-box"><p style="color:#f87171">{crystalData.error}</p></div>
			{:else}
				<div class="julia-grid">
					<div class="julia-card crystal-card"><span class="jlabel">Total Return</span><span class="jval">{(crystalData.total_return * 100).toFixed(2)}%</span></div>
					<div class="julia-card crystal-card"><span class="jlabel">Ann. Volatility</span><span class="jval">{(crystalData.volatility * 100).toFixed(2)}%</span></div>
					<div class="julia-card crystal-card"><span class="jlabel">Sharpe Ratio</span><span class="jval">{crystalData.sharpe_ratio.toFixed(4)}</span></div>
					<div class="julia-card crystal-card"><span class="jlabel">Sortino Ratio</span><span class="jval">{crystalData.sortino_ratio.toFixed(4)}</span></div>
					<div class="julia-card crystal-card"><span class="jlabel">Max Drawdown</span><span class="jval">{(crystalData.max_drawdown * 100).toFixed(2)}%</span></div>
					<div class="julia-card crystal-card"><span class="jlabel">Weighted KRW</span><span class="jval">₩{crystalData.weighted_krw.toLocaleString()}</span></div>
				</div>
			{/if}
		{:else}
			<div class="empty-box">
				<p>버튼을 눌러 Crystal 포트폴리오 수익률 · 샤프 · MDD · FX 가중평균 환율을 분석하세요. (Crystal 서버 :9002 필요)</p>
			</div>
		{/if}
	</section>

	<section class="panel">
		<h2>System Memory (Latest Logs)</h2>
		{#if logs.length > 0}
			<table class="log-table">
				<thead>
					<tr>
						<th>ID</th>
						<th>Source</th>
						<th>Message</th>
						<th>Time</th>
					</tr>
				</thead>
				<tbody>
					{#each logs as log}
						<tr>
							<td class="log-id">#{log.id}</td>
							<td class="log-source">{log.source}</td>
							<td>{log.message}</td>
							<td class="log-time"
								>{new Date(log.created_at).toLocaleString()}</td
							>
						</tr>
					{/each}
				</tbody>
			</table>
		{:else}
			<p class="empty-text">저장된 기록이 없습니다.</p>
		{/if}
	</section>
</main>

<style>
	:global(body) {
		background-color: #0f172a;
		color: #e2e8f0;
		font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
		margin: 0;
		padding: 2rem;
	}
	.container {
		max-width: 900px;
		margin: 0 auto;
	}
	.title {
		text-align: center;
		background: linear-gradient(90deg, #3b82f6, #8b5cf6, #ec4899);
		-webkit-background-clip: text;
		background-clip: text; /* ✨ 이 표준 속성을 추가해 주세요! */
		-webkit-text-fill-color: transparent;
		font-size: 2.5rem;
		margin-bottom: 2rem;
	}
	.panel {
		background: #1e293b;
		border-radius: 12px;
		padding: 1.5rem;
		margin-bottom: 1.5rem;
		box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
	}
	.panel-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 1.5rem;
	}
	.panel-header h2 {
		margin: 0;
	}
	.subtitle {
		margin: 0;
		color: #94a3b8;
		font-size: 0.9rem;
	}
	.sync-btn {
		background: #2563eb;
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.sync-btn:hover {
		background: #1d4ed8;
	}

	/* 카드 그리드 스타일 */
	.card-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: 1rem;
	}
	.status-card {
		background: #0f172a;
		border: 1px solid #334155;
		border-radius: 8px;
		padding: 1.2rem;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.status-card h3 {
		margin: 0;
		font-size: 1.1rem;
		color: #f8fafc;
	}
	.status {
		font-weight: bold;
		margin: 0;
	}
	.online {
		color: #22c55e;
	}
	.error {
		color: #ef4444;
	}
	.version {
		font-size: 0.85rem;
		color: #64748b;
	}
	.badge {
		display: inline-block;
		background: #3b82f6;
		color: white;
		font-size: 0.7rem;
		padding: 0.2rem 0.5rem;
		border-radius: 4px;
		align-self: flex-start;
		margin-top: 0.5rem;
	}

	.error-box,
	.empty-box {
		background: #0f172a;
		padding: 1.5rem;
		border-radius: 8px;
		text-align: center;
		color: #94a3b8;
	}
	.error-box {
		border: 1px solid #7f1d1d;
		color: #fca5a5;
	}

	.log-table {
		width: 100%;
		border-collapse: collapse;
		margin-top: 1rem;
	}
	.log-table th,
	.log-table td {
		padding: 0.75rem;
		text-align: left;
		border-bottom: 1px solid #334155;
	}
	.log-table th {
		color: #cbd5e1;
		font-weight: 600;
	}
	.log-id {
		color: #3b82f6;
		font-weight: bold;
	}
	.log-source {
		font-weight: 600;
	}
	.log-time {
		color: #64748b;
		font-size: 0.9rem;
	}
	.empty-text {
		color: #64748b;
		text-align: center;
		padding: 2rem 0;
	}
	.financial-data {
		margin-top: 0.8rem;
		padding-top: 0.8rem;
		border-top: 1px dashed #334155;
		font-size: 0.85rem;
		background: rgba(15, 23, 42, 0.5);
		border-radius: 4px;
		padding: 0.5rem;
	}
	.rate {
		color: #fcd34d;
		margin: 0 0 4px 0;
		font-weight: bold;
	}
	.risk {
		color: #f87171;
		margin: 0;
		word-break: break-all;
	}
	.btn-group {
		display: flex;
		gap: 0.5rem;
		align-items: center;
	}
	.auto-btn {
		background: #374151;
		color: #94a3b8;
		border: 1px solid #4b5563;
		padding: 0.75rem 1.25rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: all 0.2s;
	}
	.auto-btn.active {
		background: #065f46;
		color: #6ee7b7;
		border-color: #059669;
	}
	.auto-btn:hover {
		background: #4b5563;
	}
	.currency-grid {
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
		margin: 0.4rem 0;
	}
	.currency-chip {
		background: #1e3a5f;
		color: #93c5fd;
		font-size: 0.72rem;
		padding: 0.15rem 0.4rem;
		border-radius: 4px;
		font-weight: 600;
	}
	.trigger-btn {
		background: #7c3aed;
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.trigger-btn:hover:not(:disabled) {
		background: #6d28d9;
	}
	.trigger-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}
	.pipeline-result {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 1rem 1.5rem;
		border-radius: 8px;
		font-size: 1rem;
	}
	.pipeline-result.success {
		background: #052e16;
		border: 1px solid #16a34a;
		color: #86efac;
	}
	.pipeline-result.error-result {
		background: #450a0a;
		border: 1px solid #dc2626;
		color: #fca5a5;
	}
	.result-icon {
		font-size: 1.3rem;
	}
	.result-time {
		margin-left: auto;
		color: #64748b;
		font-size: 0.9rem;
	}

	/* Lua, Julia, Kotlin, Elixir 버튼 */
	.lua-btn {
		background: #b45309;
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.lua-btn:hover {
		background: #92400e;
	}

	.julia-btn {
		background: #0d9488;
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.julia-btn:hover:not(:disabled) {
		background: #0f766e;
	}
	.julia-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.kotlin-btn {
		background: linear-gradient(135deg, #e8590c, #c2410c);
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: filter 0.2s;
	}
	.kotlin-btn:hover {
		filter: brightness(1.15);
	}

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

	.r-btn {
		background: #1d6fa5;
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.r-btn:hover:not(:disabled) {
		background: #155881;
	}
	.r-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.r-card {
		border-color: #1d6fa5 !important;
	}

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

	/* Cache stats row */
	.stats-row {
		display: flex;
		gap: 1rem;
		flex-wrap: wrap;
	}
	.stat-box {
		flex: 1;
		min-width: 120px;
		padding: 1rem;
		border-radius: 8px;
		text-align: center;
		font-size: 0.9rem;
		line-height: 1.8;
	}
	.stat-box.hit {
		background: #052e16;
		border: 1px solid #16a34a;
		color: #86efac;
	}
	.stat-box.miss {
		background: #1e1b4b;
		border: 1px solid #6366f1;
		color: #a5b4fc;
	}
	.stat-box.engine {
		background: #0f172a;
		border: 1px solid #334155;
		color: #94a3b8;
	}

	/* Julia metrics grid */
	.julia-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
		gap: 0.75rem;
		margin-top: 0.5rem;
	}
	.julia-card {
		background: #0f172a;
		border: 1px solid #0d9488;
		border-radius: 8px;
		padding: 0.9rem;
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		text-align: center;
	}
	.jlabel {
		font-size: 0.75rem;
		color: #5eead4;
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.jval {
		font-size: 1.15rem;
		font-weight: bold;
		color: #f0fdfa;
	}

	.wasm-btn {
		background: linear-gradient(135deg, #06b6d4, #0e7490);
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.wasm-btn:hover:not(:disabled) {
		background: linear-gradient(135deg, #0891b2, #065f6e);
	}
	.wasm-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.wasm-card {
		border-color: #06b6d4 !important;
	}

	.wasm-hint {
		margin-top: 0.75rem;
		font-size: 0.8rem;
		color: #67e8f9;
		text-align: center;
	}

	.ocaml-btn {
		background: linear-gradient(135deg, #f97316, #c2410c);
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.ocaml-btn:hover:not(:disabled) {
		background: linear-gradient(135deg, #ea580c, #9a3412);
	}
	.ocaml-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.ocaml-card {
		border-color: #f97316 !important;
	}

	.risk-low {
		color: #4ade80 !important;
	}
	.risk-medium {
		color: #facc15 !important;
	}
	.risk-high {
		color: #fb923c !important;
	}
	.risk-critical {
		color: #f87171 !important;
	}

	.crystal-btn {
		background: linear-gradient(135deg, #a855f7, #7c3aed);
		color: white;
		border: none;
		padding: 0.75rem 1.5rem;
		border-radius: 8px;
		font-weight: bold;
		cursor: pointer;
		transition: background 0.2s;
	}
	.crystal-btn:hover:not(:disabled) {
		background: linear-gradient(135deg, #9333ea, #6d28d9);
	}
	.crystal-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.crystal-card {
		border-color: #a855f7 !important;
	}
</style>
