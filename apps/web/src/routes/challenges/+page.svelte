<script lang="ts">
	import { fetchChallenges, browsePublicChallenges } from '$lib/core/data';
	import type { ChallengeWithMeta } from '$lib/types';
	import ChallengeEditor from '$lib/components/ChallengeEditor.svelte';
	import ChallengeProgressBar from '$lib/components/ChallengeProgressBar.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { goto } from '$app/navigation';
	import { smartBack } from '$lib/util/smart_back';

	const back = smartBack();
	const BROWSE_PAGE = 24;

	// My challenges = the ones I've joined. Browse = the ranked, server-paginated
	// public feed of ones I haven't (popularity-ordered in browse_public_challenges).
	let mine = $state<ChallengeWithMeta[] | null>(null);
	let browse = $state<ChallengeWithMeta[] | null>(null);
	let creating = $state(false);
	let search = $state('');
	let browseOffset = $state(0);
	let browseDone = $state(false);
	let browseLoading = $state(false);
	let activeSearch = $state('');

	async function loadMine() {
		try {
			mine = await fetchChallenges({ mine: true });
		} catch {
			mine = [];
		}
	}

	async function loadBrowse(reset: boolean, term: string) {
		if (browseLoading) return;
		browseLoading = true;
		const offset = reset ? 0 : browseOffset;
		try {
			const rows = await browsePublicChallenges({ search: term, limit: BROWSE_PAGE, offset });
			browse = reset ? rows : [...(browse ?? []), ...rows];
			browseOffset = offset + rows.length;
			browseDone = rows.length < BROWSE_PAGE;
			activeSearch = term;
		} catch {
			if (reset) browse = [];
			browseDone = true;
		} finally {
			browseLoading = false;
		}
	}

	$effect(() => {
		loadMine();
	});

	// Debounced search → reset Browse. Tracks `search`, so it also runs once on
	// mount with the empty term to load the first page.
	$effect(() => {
		const term = search.trim();
		const t = setTimeout(() => loadBrowse(true, term), 200);
		return () => clearTimeout(t);
	});

	function metricLabel(metricKey: ChallengeWithMeta['metric']): string {
		switch (metricKey) {
			case 'distance':
				return m('challenges.metricDistance');
			case 'duration':
				return m('challenges.metricDuration');
			case 'vert':
				return m('challenges.metricVert');
			case 'activity_count':
				return m('challenges.metricActivityCount');
			case 'streak_days':
				return m('challenges.metricStreak');
		}
	}

	const METRIC_ICON: Record<ChallengeWithMeta['metric'], string> = {
		distance: 'straighten',
		duration: 'timer',
		vert: 'terrain',
		activity_count: 'format_list_numbered',
		streak_days: 'local_fire_department'
	};
</script>

<svelte:head>
	<title>{m('challenges.title')}</title>
</svelte:head>

<div class="page">
	<a class="back" href="/social?tab=challenges" onclick={back.handle}>
		<span class="material-symbols" aria-hidden="true">arrow_back</span>{m('challenges.back')}
	</a>
	<header class="page-head">
		<div class="head-row">
			<h1>{m('challenges.title')}</h1>
			<button type="button" class="btn btn-primary" onclick={() => (creating = true)}>
				{m('challenges.create')}
			</button>
		</div>
		<p class="tagline">{m('challenges.tagline')}</p>
	</header>

	<section>
		<h2>{m('challenges.myChallenges')}</h2>
		{#if mine === null}
			<p class="muted">…</p>
		{:else if mine.length === 0}
			<div class="empty-state">
				<span class="material-symbols" aria-hidden="true">trophy</span>
				<p>{m('challenges.empty')}</p>
			</div>
		{:else}
			<ul class="list">
				{#each mine as c (c.id)}
					<li class="card-elevated">
						<a href={`/challenges/${c.id}`}>
							<div class="row-top">
								<span class="title">{c.title}</span>
								<span class="badge">
									<span class="material-symbols" aria-hidden="true">{METRIC_ICON[c.metric]}</span>
									{metricLabel(c.metric)}
								</span>
							</div>
							<ChallengeProgressBar metric={c.metric} value={c.my_value ?? 0} goal={c.goal_value} />
							<span class="meta">
								<span class="material-symbols" aria-hidden="true">group</span>
								{m('challenges.participants', { n: c.participant_count })}
							</span>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section>
		<div class="browse-head">
			<h2>{m('challenges.browse')}</h2>
			<div class="search">
				<span class="material-symbols" aria-hidden="true">search</span>
				<input
					type="search"
					bind:value={search}
					placeholder={m('challenges.searchPlaceholder')}
					aria-label={m('challenges.searchPlaceholder')}
				/>
			</div>
		</div>
		{#if browse === null}
			<p class="muted">…</p>
		{:else if browse.length === 0}
			<div class="empty-state">
				<span class="material-symbols" aria-hidden="true">search</span>
				<p>{m('challenges.browseEmpty')}</p>
			</div>
		{:else}
			<ul class="list">
				{#each browse as c (c.id)}
					<li class="card-elevated">
						<a href={`/challenges/${c.id}`}>
							<div class="row-top">
								<span class="title">{c.title}</span>
								<span class="badge">
									<span class="material-symbols" aria-hidden="true">{METRIC_ICON[c.metric]}</span>
									{metricLabel(c.metric)}
								</span>
							</div>
							<span class="meta">
								<span class="material-symbols" aria-hidden="true">group</span>
								{m('challenges.participants', { n: c.participant_count })}
							</span>
						</a>
					</li>
				{/each}
			</ul>
			{#if !browseDone}
				<div class="load-more">
					<button
						type="button"
						class="btn btn-secondary"
						disabled={browseLoading}
						onclick={() => loadBrowse(false, activeSearch)}
					>
						{m('challenges.loadMore')}
					</button>
				</div>
			{/if}
		{/if}
	</section>
</div>

<Modal open={creating} onclose={() => (creating = false)} title={m('challenges.create')}>
	<ChallengeEditor
		oncreated={(ch) => {
			creating = false;
			goto(`/challenges/${ch.id}`);
		}}
		oncancel={() => (creating = false)}
	/>
</Modal>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.1rem;
		margin-bottom: var(--space-md);
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
	}
	.back .material-symbols {
		font-size: 1.1rem;
	}
	.back:hover {
		text-decoration: underline;
	}
	.head-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
	}
	section {
		margin-top: var(--space-xl);
	}
	h2 {
		font-size: 1.1rem;
		margin: 0 0 var(--space-md);
	}
	.browse-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		flex-wrap: wrap;
		margin-bottom: var(--space-md);
	}
	.browse-head h2 {
		margin: 0;
	}
	.search {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		padding: 0.3rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		background: var(--color-surface);
		min-width: 14rem;
	}
	.search:focus-within {
		border-color: var(--color-primary);
	}
	.search .material-symbols {
		font-size: 1.1rem;
		color: var(--color-text-tertiary);
	}
	.search input {
		border: none;
		background: transparent;
		outline: none;
		font: inherit;
		color: inherit;
		width: 100%;
	}
	.load-more {
		display: flex;
		justify-content: center;
		margin-top: var(--space-lg);
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
		gap: var(--space-md);
	}
	.list li {
		transition:
			transform 0.15s ease,
			box-shadow 0.15s ease;
	}
	.list li:hover {
		transform: translateY(-2px);
	}
	.list li a {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
	}
	.row-top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.title {
		font-weight: 600;
		line-height: 1.3;
	}
	.badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		flex-shrink: 0;
		font-size: 0.75rem;
		font-weight: 600;
		padding: 0.15rem 0.55rem;
		border-radius: 999px;
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.badge .material-symbols {
		font-size: 0.95rem;
		width: 0.95rem;
		height: 0.95rem;
	}
	.meta {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.meta .material-symbols {
		font-size: 1rem;
		width: 1rem;
		height: 1rem;
		color: var(--color-text-tertiary);
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-lg);
		color: var(--color-text-secondary);
		text-align: center;
	}
	.empty-state .material-symbols {
		font-size: 2rem;
		width: 2rem;
		height: 2rem;
		color: var(--color-text-tertiary);
	}
	.empty-state p {
		margin: 0;
	}
</style>
