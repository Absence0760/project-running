<script lang="ts">
	import RunShareView from '$lib/components/RunShareView.svelte';
	import { buildRunShareDescription, buildRunShareTitle } from '$lib/share_meta';

	let { data } = $props();

	// `data.run` + `data.displayName` are thin projections from
	// `public_runs` and `public_profiles` (migration 20260824_001
	// added the latter so the anon prerender can see display names).
	// Both bake into the prerendered HTML so chat-app unfurls (Slack,
	// Discord, FB, LinkedIn) get per-run, per-runner copy instead
	// of the SPA-shell fallback.
	let title = $derived(buildRunShareTitle(data.run, data.displayName));
	let description = $derived(buildRunShareDescription(data.run, data.displayName));
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<!-- Open Graph + Twitter — per-run title + description bake into
	     the prerendered HTML. og:image is still the static favicon;
	     a per-run track-preview PNG renderer is the remaining follow-up
	     under docs/followups.md § #15. -->
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:site_name" content="Run Onward" />
	<meta property="og:image" content="/og/run/{data.id}.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og/run/{data.id}.png" />
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
