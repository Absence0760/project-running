<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '$lib/i18n/store.svelte';

	onMount(() => {
		goto('/routes?tab=explore', { replaceState: true });
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
	<meta http-equiv="refresh" content="0;url=/routes?tab=explore" />
</svelte:head>
