<script lang="ts">
        let count = 0;
        const increment = () => {
                count += 1;
        };
</script>

<h1>일류 개발자의 Svelte 입성기</h1>
<p>현재 클릭 횟수: {count}</p>
<button on:click={increment}>숫자 올리기</button>

<style>
        h1 { color: #ff3e00; } 
        button { padding: 10px 20px; font-size: 1.2rem; cursor: pointer; }
</style>