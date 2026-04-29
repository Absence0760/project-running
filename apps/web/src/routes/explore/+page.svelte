<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	onMount(() => {
		goto('/routes?tab=explore', { replaceState: true });
	});
</script>

<svelte:head>
	<title>Redirecting…</title>
	<meta http-equiv="refresh" content="0;url=/routes?tab=explore" />
</svelte:head>
