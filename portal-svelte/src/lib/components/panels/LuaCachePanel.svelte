<script>
    import { API_BASE } from '$lib/api';
    /** @type {any | null} */
    let cacheStats = $state(null);

    async function fetchCacheStats() {
        try {
            const res = await fetch(`${API_BASE}/api/cache/stats`);
            if (res.ok) cacheStats = await res.json();
        } catch {
            cacheStats = null;
        }
    }
</script>

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
                🔄 Cache Misses<br /><strong>{cacheStats.cache_misses}</strong>
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

<style>
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
</style>
