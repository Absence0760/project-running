<script lang="ts">
	import { goto, afterNavigate } from '$app/navigation';
	import RunEditor from '$lib/components/RunEditor.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let cameFromRuns = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromRuns || !from) return;
		if (from.url.pathname === '/runs' || from.url.pathname.startsWith('/runs?')) {
			cameFromRuns = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromRuns) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (cameFromRuns) history.back();
		else goto('/runs');
	}
</script>

<svelte:head>
	<title>{m('runsNewPage.title')} — Threkir</title>
</svelte:head>

<div class="page">
	<a href="/runs" class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		{m('runsNewPage.backToRuns')}
	</a>

	<header class="page-header">
		<p class="kicker">{m('runsNewPage.kicker')}</p>
		<h1>{m('runsNewPage.title')}</h1>
		<p class="tagline">
			{m('runsNewPage.tagline')}
		</p>
	</header>

	<RunEditor
		oncreated={(run) => goto(`/runs/${run.id}`)}
		oncancel={handleCancel}
	/>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 44rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
	.page-header {
		margin-bottom: var(--space-xl);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-2xs);
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		line-height: 1.2;
		margin: 0 0 var(--space-xs);
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 38rem;
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
