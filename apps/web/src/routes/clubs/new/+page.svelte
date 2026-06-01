<script lang="ts">
	import { goto, afterNavigate } from '$app/navigation';
	import ClubEditor from '$lib/components/ClubEditor.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let cameFromClubs = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromClubs || !from) return;
		const p = from.url.pathname;
		if (p === '/clubs' || p.startsWith('/clubs?') || p === '/social') {
			cameFromClubs = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromClubs) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (cameFromClubs) history.back();
		else goto('/social?tab=clubs');
	}
</script>

<svelte:head>
	<title>{m('clubsNewPage.documentTitle')}</title>
</svelte:head>

<div class="page">
	<a href="/social?tab=clubs" class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		{m('clubsNewPage.backToClubs')}
	</a>

	<header class="page-header">
		<p class="kicker">{m('clubsNewPage.kicker')}</p>
		<h1>{m('clubsNewPage.heading')}</h1>
		<p class="tagline">
			{m('clubsNewPage.tagline')}
		</p>
	</header>

	<ClubEditor
		oncreated={(club) => goto(`/clubs/${club.slug}`)}
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
