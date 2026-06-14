<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		fetchPublicPlanLibrary,
		type PublicPlanLibraryEntry,
	} from '$lib/core/data';
	import { formatDistance } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let plans = $state<PublicPlanLibraryEntry[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let query = $state('');

	const eventLabels: Record<string, () => string> = {
		distance_5k: () => '5K',
		distance_10k: () => '10K',
		distance_half: () => m('plansPage.eventHalf'),
		distance_full: () => m('plansPage.eventFull'),
		custom: () => m('plansPage.eventCustom'),
	};

	function goalLabel(p: PublicPlanLibraryEntry): string {
		const named = eventLabels[p.goal_event];
		if (named) return named();
		return formatDistance(p.goal_distance_m);
	}

	function weeksOf(p: PublicPlanLibraryEntry): number {
		const start = new Date(p.start_date).getTime();
		const end = new Date(p.end_date).getTime();
		const days = Math.round((end - start) / 86_400_000) + 1;
		return Math.max(1, Math.ceil(days / 7));
	}

	let searchTimer: ReturnType<typeof setTimeout> | undefined;
	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(load, 250);
	}

	async function load() {
		loading = true;
		loadError = null;
		const res = await fetchPublicPlanLibrary(query);
		plans = res.plans;
		loadError = res.error;
		loading = false;
	}

	onMount(load);
</script>

<svelte:head>
	<title>{m('planLibrary.headTitle')}</title>
</svelte:head>

<div class="library">
	<header class="library-head">
		<a class="back" href="/plans">{m('planLibrary.backToLibrary')}</a>
		<h1>{m('planLibrary.heading')}</h1>
		<p class="sub">{m('planLibrary.subheading')}</p>
	</header>

	<label class="search">
		<span class="visually-hidden">{m('planLibrary.searchAria')}</span>
		<input
			type="search"
			bind:value={query}
			oninput={onSearchInput}
			placeholder={m('planLibrary.searchPlaceholder')}
			aria-label={m('planLibrary.searchAria')}
		/>
	</label>

	{#if loading}
		<p class="state">{m('planLibrary.loading')}</p>
	{:else if loadError}
		<div class="state error">
			<p>{m('planLibrary.loadError')}</p>
			<button class="btn btn-outline" type="button" onclick={load}>
				{m('planLibrary.retry')}
			</button>
		</div>
	{:else if plans.length === 0}
		<p class="state">
			{query.trim() ? m('planLibrary.emptySearch', { query }) : m('planLibrary.empty')}
		</p>
	{:else}
		<ul class="plan-grid">
			{#each plans as p (p.id)}
				<li>
					<a class="plan-card" href="/plans/library/{p.id}">
						<span class="plan-name">{p.name}</span>
						<span class="plan-author">
							{m('planLibrary.byAuthor', {
								author: p.author_handle ?? m('planLibrary.anonymousAuthor'),
							})}
						</span>
						<span class="plan-meta">
							<span class="chip">{goalLabel(p)}</span>
							<span class="chip">{m('planLibrary.weeksLabel', { weeks: weeksOf(p) })}</span>
							<span class="chip">{m('planLibrary.daysPerWeek', { days: p.days_per_week })}</span>
						</span>
						<span class="plan-cta">{m('planLibrary.preview')}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.library {
		max-width: 880px;
		margin: 0 auto;
		padding: 1rem;
	}
	.library-head {
		margin-bottom: 1rem;
	}
	.back {
		font-size: 0.85rem;
		color: var(--text-muted, #667);
		text-decoration: none;
	}
	.library-head h1 {
		margin: 0.25rem 0 0.25rem;
		font-size: 1.4rem;
	}
	.sub {
		margin: 0;
		color: var(--text-muted, #667);
	}
	.search {
		display: block;
		margin-bottom: 1rem;
	}
	.search input {
		width: 100%;
		padding: 0.6rem 0.75rem;
		border: 1px solid var(--border, #ccd);
		border-radius: 0.5rem;
		font-size: 1rem;
	}
	.state {
		text-align: center;
		color: var(--text-muted, #667);
		padding: 2rem 0;
	}
	.state.error {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		align-items: center;
	}
	.plan-grid {
		list-style: none;
		padding: 0;
		margin: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
		gap: 0.75rem;
	}
	.plan-card {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		padding: 1rem;
		border: 1px solid var(--border, #ccd);
		border-radius: 0.75rem;
		text-decoration: none;
		color: inherit;
		background: var(--surface, #fff);
		transition: border-color 0.15s ease;
	}
	.plan-card:hover {
		border-color: var(--accent, #3b6ef5);
	}
	.plan-name {
		font-weight: 600;
		font-size: 1.05rem;
	}
	.plan-author {
		font-size: 0.85rem;
		color: var(--text-muted, #667);
	}
	.plan-meta {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		margin-top: 0.2rem;
	}
	.chip {
		font-size: 0.75rem;
		padding: 0.15rem 0.5rem;
		border-radius: 1rem;
		background: var(--chip-bg, #eef);
		color: var(--chip-fg, #335);
	}
	.plan-cta {
		margin-top: 0.4rem;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--accent, #3b6ef5);
	}
	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
