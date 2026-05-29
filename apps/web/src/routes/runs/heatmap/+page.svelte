<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import PersonalHeatmap from '$lib/components/PersonalHeatmap.svelte';

	let ready = $state(false);
	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		ready = true;
	});
</script>

<svelte:head>
	<title>Your run heatmap — Threkir</title>
</svelte:head>

<div class="page">
	<header class="page-head">
		<div>
			<h1>Your heatmap</h1>
			<p class="sub">Everywhere you've run, mapped from your own GPS tracks.</p>
		</div>
		<a class="btn btn-outline" href="/runs">Back to runs</a>
	</header>

	{#if !ready}
		<p class="muted">Loading…</p>
	{:else if !auth.user}
		<p class="muted">Sign in to see your run heatmap.</p>
	{:else}
		<div class="map-host">
			<PersonalHeatmap />
		</div>
	{/if}
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		padding: var(--space-xl) var(--space-2xl);
		gap: var(--space-lg);
		height: calc(100vh - var(--app-header-h, 0px));
		min-height: 32rem;
	}
	.page-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-md);
		flex: 0 0 auto;
	}
	.page-head h1 {
		margin: 0;
	}
	.sub {
		margin: 0.2rem 0 0;
		color: var(--color-text-secondary);
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.map-host {
		flex: 1 1 auto;
		min-height: 0;
	}
</style>
