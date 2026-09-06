<script lang="ts">
	import { onMount } from 'svelte';
	import { afterNavigate } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import PersonalHeatmap from '$lib/components/PersonalHeatmap.svelte';
	import ActivityLoader from '$lib/components/ActivityLoader.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let ready = $state(false);
	onMount(async () => {
		await auth.ready();
		ready = true;
	});

	/// The only entry point to this page is the /runs toolbar, and the button
	/// pointed at /history — the cross-modal timeline, not the run list the
	/// runner came from. Going BACK rather than forward is what restores
	/// /runs's snapshot (filters + scroll); a soft-nav forward drops it. Stays
	/// a real link so a deep hit, a middle-click and the keyboard all work.
	/// Same shape as /clubs/[slug] → /clubs and /runs/[id] → /runs.
	let cameFromRuns = $state(false);
	afterNavigate(({ from }) => {
		if (from?.url.pathname === '/runs' && !cameFromRuns) {
			cameFromRuns = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromRuns) {
			e.preventDefault();
			history.back();
		}
	}
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
		<a class="btn btn-outline" href="/runs" onclick={handleBack}
			>{m('runsHeatmap.backToRuns')}</a
		>
	</header>

	{#if !ready}
		<div class="act-load"><ActivityLoader kind="run" size={76} label={m('shell.loading')} /></div>
	{:else if !auth.user}
		<p class="muted">{m('runsHeatmap.signInPrompt')}</p>
	{:else}
		<div class="map-host">
			<PersonalHeatmap />
		</div>
	{/if}
</div>

<style>
	.act-load {
		display: flex;
		justify-content: center;
		padding: var(--space-2xl) 0;
	}
	.page {
		display: flex;
		flex-direction: column;
		padding: var(--page-padding-y) var(--page-padding-x);
		gap: var(--space-lg);
		height: 100vh;
		min-height: 32rem;
	}
	.page-head {
		display: flex;
		flex-wrap: wrap;
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
