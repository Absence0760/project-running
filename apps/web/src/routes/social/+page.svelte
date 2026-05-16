<script lang="ts">
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import SocialFeed from '$lib/components/SocialFeed.svelte';
	import SocialPeople from '$lib/components/SocialPeople.svelte';
	import SocialClubs from '$lib/components/SocialClubs.svelte';

	type Tab = 'feed' | 'people' | 'clubs';
	const TABS: { id: Tab; label: string; icon: string }[] = [
		{ id: 'feed', label: 'Feed', icon: 'dynamic_feed' },
		{ id: 'people', label: 'People', icon: 'person_search' },
		{ id: 'clubs', label: 'Clubs', icon: 'groups' },
	];

	let tab = $state<Tab>('feed');

	$effect(() => {
		const t = $page.url.searchParams.get('tab');
		if (t === 'people' || t === 'clubs' || t === 'feed') tab = t;
		else tab = 'feed';
	});

	function setTab(next: Tab) {
		if (next === tab) return;
		const url = new URL($page.url);
		if (next === 'feed') url.searchParams.delete('tab');
		else url.searchParams.set('tab', next);
		// Clear the Clubs subtab when leaving Clubs so a back-nav doesn't
		// re-deep-link into Browse.
		if (next !== 'clubs') url.searchParams.delete('clubs-sub');
		goto(url, { replaceState: false, noScroll: true, keepFocus: true });
		tab = next;
	}
</script>

<svelte:head>
	<title>Social — Run Onward</title>
</svelte:head>

<div class="page">
	<header class="page-head">
		<p class="kicker">SOCIAL</p>
		<h1>Social</h1>
		<p class="tagline">Your feed, people to follow, and clubs to join.</p>
	</header>

	<div class="tabs" role="tablist" aria-label="Social sections">
		{#each TABS as t}
			<button
				type="button"
				role="tab"
				class="tab"
				class:active={tab === t.id}
				aria-selected={tab === t.id}
				aria-controls="social-panel-{t.id}"
				onclick={() => setTab(t.id)}
			>
				<span class="material-symbols" aria-hidden="true">{t.icon}</span>
				<span>{t.label}</span>
			</button>
		{/each}
	</div>

	<div
		id="social-panel-{tab}"
		role="tabpanel"
		tabindex="0"
		aria-label="{TABS.find((t) => t.id === tab)?.label} panel"
	>
		{#if tab === 'feed'}
			<SocialFeed />
		{:else if tab === 'people'}
			<SocialPeople />
		{:else}
			<SocialClubs />
		{/if}
	</div>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.page-head {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		margin: 0;
	}
	h1 {
		margin: 0;
		font-size: 1.75rem;
		font-weight: 800;
	}
	.tagline {
		margin: 0;
		color: var(--color-text-secondary);
		max-width: 48rem;
	}
	.tabs {
		display: flex;
		gap: 0.4rem;
		border-bottom: 1px solid var(--color-border);
		overflow-x: auto;
	}
	.tab {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: none;
		border: none;
		padding: 0.7rem 0.25rem;
		margin-right: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 600;
		white-space: nowrap;
	}
	.tab:hover { color: var(--color-text); }
	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}
	.tab .material-symbols { font-size: 1.1rem; }
	.material-symbols { font-family: 'Material Symbols Outlined'; }
</style>
