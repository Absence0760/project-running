<script lang="ts">
	import RunShareView from '$lib/components/RunShareView.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Run — Run Onward</title>
	<meta property="og:type" content="website" />
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Run Onward</a>
	</header>

	<div class="content">
		<RunShareView runId={data.id} />
	</div>
</div>

<style>
	.share-page {
		min-height: 100vh;
		background: var(--color-bg);
	}

	.share-header {
		padding: var(--space-md) var(--space-xl);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.share-logo {
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-primary);
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.content {
		max-width: 56rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
	}
</style>
