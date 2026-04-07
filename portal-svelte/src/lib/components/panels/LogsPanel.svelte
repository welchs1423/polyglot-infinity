<script>
    /** @type {{ logs?: any[] }} */
    let { logs = [] } = $props();
</script>

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
