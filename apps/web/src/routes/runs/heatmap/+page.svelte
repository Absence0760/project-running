<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import PersonalHeatmap from '$lib/components/PersonalHeatmap.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let ready = $state(false);
	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		ready = true;
	});
</script>

<svelte:head>
	<title>{m('runsHeatmap.pageTitle')}</title>
</svelte:head>

<div class="page">
	<header class="page-head">
		<div>
			<h1>{m('runsHeatmap.heading')}</h1>
			<p class="sub">{m('runsHeatmap.subtitle')}</p>
		</div>
		<a class="btn btn-outline" href="/history">{m('runsHeatmap.backToRuns')}</a>
	</header>

	{#if !ready}
		<p class="muted">{m('shell.loading')}</p>
	{:else if !auth.user}
		<p class="muted">{m('runsHeatmap.signInPrompt')}</p>
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
