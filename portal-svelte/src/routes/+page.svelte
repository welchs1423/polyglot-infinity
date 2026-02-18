<script lang="ts">
  let status: any = $state(null);
  let logs: any[] = $state([]); // 로그 데이터를 담을 변수
  let loading = $state(false);

  // 1. 시스템 상태 점검 및 로그 갱신 함수
  async function checkSystem() {
    loading = true;
    try {
      // (1) Go Backend 상태 체크 요청
      const res = await fetch('http://localhost:8080/api/status');
      status = await res.json();
      
      // (2) 로그 데이터 갱신 요청 (연쇄 호출)
      await fetchLogs();
    } catch (e) {
      console.error(e);
      status = { error: "System Offline" };
    } finally {
      loading = false;
    }
  }

  // 2. 로그 데이터 가져오기 함수
  async function fetchLogs() {
    try {
        const res = await fetch('http://localhost:8080/api/history');
        logs = await res.json();
    } catch (e) {
        console.error("로그 조회 실패:", e);
    }
  }
</script>

<div class="min-h-screen bg-gray-900 text-white flex flex-col items-center justify-center p-4">
  <h1 class="text-5xl font-bold mb-8 bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
    Polyglot Infinity Portal
  </h1>

  <div class="bg-gray-800 p-8 rounded-xl shadow-2xl border border-gray-700 w-full max-w-2xl mb-8">
    <div class="flex justify-between items-center mb-6">
      <div>
        <h2 class="text-xl font-semibold text-gray-300">System Status</h2>
        <p class="text-gray-400 text-sm">Svelte 5 ↔ Go ↔ Python ↔ DB</p>
      </div>
      <button 
        onclick={checkSystem}
        class="px-6 py-3 bg-blue-600 hover:bg-blue-500 rounded-lg font-bold transition-all transform active:scale-95 shadow-lg disabled:opacity-50 disabled:cursor-not-allowed"
        disabled={loading}
      >
        {loading ? 'Processing...' : 'Sync System'}
      </button>
    </div>

    {#if status}
      <div class="bg-black/50 p-4 rounded-lg font-mono text-sm border border-gray-600">
        <pre class="whitespace-pre-wrap">{JSON.stringify(status, null, 2)}</pre>
      </div>
    {:else}
      <div class="text-center text-gray-500 py-4">
        시스템 동기화를 시작해주세요.
      </div>
    {/if}
  </div>

  <div class="bg-gray-800 p-8 rounded-xl shadow-2xl border border-gray-700 w-full max-w-2xl">
    <h2 class="text-xl font-semibold text-gray-300 mb-4 border-b border-gray-700 pb-2">
        System Memory (Latest Logs)
    </h2>
    
    {#if logs.length > 0}
        <div class="overflow-x-auto">
            <table class="w-full text-left text-sm text-gray-400">
                <thead class="bg-gray-700 text-gray-200">
                    <tr>
                        <th class="p-3 rounded-tl-lg">ID</th>
                        <th class="p-3">Source</th>
                        <th class="p-3">Message</th>
                        <th class="p-3 rounded-tr-lg">Time</th>
                    </tr>
                </thead>
                <tbody>
                    {#each logs as log}
                        <tr class="border-b border-gray-700 hover:bg-gray-700/50 transition-colors">
                            <td class="p-3 text-blue-400 font-mono">#{log.id}</td>
                            <td class="p-3 font-semibold text-white">{log.source}</td>
                            <td class="p-3">{log.message}</td>
                            <td class="p-3 text-xs text-gray-500">{new Date(log.created_at).toLocaleString()}</td>
                        </tr>
                    {/each}
                </tbody>
            </table>
        </div>
    {:else}
        <p class="text-center text-gray-500 py-4">저장된 기록이 없습니다.</p>
    {/if}
  </div>

</div>