<script lang="ts">
	import RunShareView from '$lib/components/RunShareView.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Run — Run Onward</title>
	<meta
		name="description"
		content="View a public run on Run Onward — map, splits, elevation, kudos."
	/>
	<!-- Open Graph + Twitter scaffold. Title / description stay generic
	     here because the per-run data fetch lives inside RunShareView and
	     refactoring that out for a per-run unfurl would touch the feed
	     modal too. A future slice can lift the run fetch into +page.ts
	     (load function) so og:title can include the runner's name. -->
	<meta property="og:title" content="Run — Run Onward" />
	<meta
		property="og:description"
		content="View a public run on Run Onward — map, splits, elevation, kudos."
	/>
	<meta property="og:type" content="website" />
	<meta property="og:site_name" content="Run Onward" />
	<meta property="og:image" content="/apple-touch-icon.png" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content="Run — Run Onward" />
	<meta
		name="twitter:description"
		content="View a public run on Run Onward — map, splits, elevation, kudos."
	/>
	<meta name="twitter:image" content="/apple-touch-icon.png" />
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
