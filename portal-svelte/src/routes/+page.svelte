<script>
	/** @type {any} */
	let systemData = $state(null);

	/** @type {string | null} */
	let errorMsg = $state(null);

	/** @type {any[]} */
	let logs = $state([]);

	async function syncSystem() {
		try {
			const res = await fetch("http://localhost:8080/api/status");
			if (!res.ok) throw new Error("System Offline");
			systemData = await res.json();
			errorMsg = null;
			fetchLogs();
		} catch (err) {
			// 에러 객체에서 안전하게 메시지 추출
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
</script>

<main class="container">
	<h1 class="title">Polyglot Infinity Portal</h1>

	<section class="panel">
		<div class="panel-header">
			<div>
				<h2>System Status</h2>
				<p class="subtitle">Svelte 5 ↔ Go ↔ Python ↔ Rust ↔ DB</p>
			</div>
			<button class="sync-btn" onclick={syncSystem}>Sync System</button>
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
					<h3>🦀 Rust (Pipeline)</h3>
					{#if systemData.pipeline_node.status === "online"}
						<p class="status online">
							● {systemData.pipeline_node.status}
						</p>
						<span class="version"
							>{systemData.pipeline_node.module}</span
						>
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
</style>
