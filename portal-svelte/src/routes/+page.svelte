<script lang="ts">
    let engineStatus = "연결 시도 중...";
    let power = 0;

    async function checkSystem(){
        try {
            const response = await fetch(`http://localhost:8080/api/status`);
            const data = await response.json();

            engineStatus = `${data.engine} (${data.status})`;
            power = data.power;
        } catch (err) {
            engineStatus = "서버 연결 실패 (Go 서버를 켰는지 확인하세요)";
        }
    }
</script>

<div class="min-h-screen bg-gray-900 text-white flex flex-col items-center justify-center text-center">
    <h1 class="text-5xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-orange-400 to-red mb-8 pb-2">
        Polygot Infinity Portal    
    </h1>

    <div class="p-8 bg-gray-800 rounded-2xl shadow-2xl border border-gray-700 w-96">
        <div class="mb-6">
            <p class="text-gray-400 text-sm uppercase tracking-widest mb-1">System Status</p>
            <p class="text-xl font-mono text-green-400">{engineStatus}</p> 
        </div>

        <button
            on:click={checkSystem}
            class="w-full py-4 bg-orange-600 hover:bg-orange-500 active:scale-95 transition-all rounded-xl font-bold text-lg shadow-lg">
            시스템 동기화 (Go 호출)
        </button>
    </div>
</div>