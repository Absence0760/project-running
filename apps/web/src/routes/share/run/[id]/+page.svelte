<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDuration, formatPace, formatDistance, formatDate, sourceLabel, sourceColor } from '$lib/mock-data';
	import { fetchPublicRun } from '$lib/data';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import type { Run } from '$lib/types';

	let { data } = $props();

	let run = $state<Run | null>(null);
	let loading = $state(true);
	let notFound = $state(false);

	onMount(async () => {
		const r = await fetchPublicRun(data.id);
		if (r) run = r;
		else notFound = true;
		loading = false;
	});

	let track = $derived(run?.track ?? []);
	let elevations = $derived(track.map((p) => p.ele ?? 0));
	let pageTitle = $derived(run ? `${formatDistance(run.distance_m)} Run — Better Runner` : 'Run — Better Runner');
	let pageDesc = $derived(run ? `${formatDistance(run.distance_m)} in ${formatDuration(run.duration_s)} — ${formatPace(run.duration_s, run.distance_m)}` : '');
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={pageDesc} />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={pageDesc} />
	<meta property="og:type" content="website" />
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">
			<span class="logo-icon">&#9654;</span> Run
		</a>
	</header>

	{#if loading}
		<div class="content"><p class="status">Loading...</p></div>
	{:else if notFound}
		<div class="content">
			<p class="status">Run not found.</p>
			<a href="/" class="home-link">Go to home page</a>
		</div>
	{:else if run}
		<div class="content">
			<h1>{formatDate(run.started_at)}</h1>
			<div class="run-meta">
				<span>{formatDistance(run.distance_m)}</span>
				<span class="meta-sep">&middot;</span>
				<span>{formatDuration(run.duration_s)}</span>
				<span class="meta-sep">&middot;</span>
				<span>{formatPace(run.duration_s, run.distance_m)}</span>
				<span class="meta-sep">&middot;</span>
				<span class="source-badge" style="background: {sourceColor(run.source)}">{sourceLabel(run.source)}</span>
			</div>

			{#if track.length > 0}
				<div class="map-container">
					<RunMap {track} />
				</div>
			{/if}

			{#if elevations.some((e) => e > 0)}
				<section class="card">
					<h2>Elevation Profile</h2>
					<ElevationProfile {elevations} totalDistance={run.distance_m} />
				</section>
			{/if}

			<div class="cta">
				<p>Track your own runs</p>
				<a href="/login" class="btn btn-primary">Sign up free</a>
			</div>
		</div>
	{/if}
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

	.status {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.home-link {
		display: block;
		text-align: center;
		color: var(--color-primary);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.run-meta {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xl);
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.source-badge {
		font-size: 0.65rem;
		font-weight: 600;
		color: white;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		text-transform: uppercase;
	}

	.map-container {
		height: 24rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
		margin-bottom: var(--space-xl);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}

	.cta {
		text-align: center;
		padding: var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}

	.cta p {
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
	}

	.btn-primary {
		display: inline-block;
		padding: var(--space-sm) var(--space-xl);
		background: var(--color-primary);
		color: white;
		border-radius: var(--radius-md);
		font-weight: 600;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
	}
</style>
