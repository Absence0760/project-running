<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchPublicGymRoutineLibrary, type PublicGymRoutineEntry } from '$lib/core/data';
	import { m as t } from '$lib/i18n/store.svelte';

	let routines = $state<PublicGymRoutineEntry[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let query = $state('');

	let searchTimer: ReturnType<typeof setTimeout> | undefined;
	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(load, 250);
	}

	async function load() {
		loading = true;
		loadError = null;
		const res = await fetchPublicGymRoutineLibrary(query);
		routines = res.routines;
		loadError = res.error;
		loading = false;
	}

	onMount(load);
</script>

<svelte:head>
	<title>{t('gymLibrary.headTitle')}</title>
</svelte:head>

<div class="library">
	<header class="library-head">
		<a class="back" href="/gym/routines">{t('gymLibrary.backToRoutines')}</a>
		<h1>{t('gymLibrary.heading')}</h1>
		<p class="sub">{t('gymLibrary.subheading')}</p>
	</header>

	<label class="search">
		<span class="visually-hidden">{t('gymLibrary.searchAria')}</span>
		<input
			type="search"
			bind:value={query}
			oninput={onSearchInput}
			placeholder={t('gymLibrary.searchPlaceholder')}
			aria-label={t('gymLibrary.searchAria')}
		/>
	</label>

	{#if loading}
		<p class="state" role="status">{t('gymLibrary.loading')}</p>
	{:else if loadError}
		<div class="state error" role="alert">
			<p>{t('gymLibrary.loadError')}</p>
			<button class="btn btn-outline" type="button" onclick={load}>{t('gymLibrary.retry')}</button>
		</div>
	{:else if routines.length === 0}
		<p class="state" data-testid="gym-library-empty">
			{query.trim() ? t('gymLibrary.emptySearch', { query }) : t('gymLibrary.empty')}
		</p>
	{:else}
		<ul class="routine-grid" data-testid="gym-library-list">
			{#each routines as r (r.id)}
				<li>
					<a class="routine-card" href="/gym/routines/library/{r.id}">
						<span class="routine-name">{r.title}</span>
						<span class="routine-author">
							{t('gymLibrary.byAuthor', {
								author: r.author_handle ?? t('gymLibrary.anonymousAuthor'),
							})}
						</span>
						<span class="routine-meta">
							<span class="chip">{t('gymLibrary.exercisesLabel', { count: r.exercise_count })}</span>
						</span>
						<span class="routine-cta">{t('gymLibrary.preview')}</span>
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
	.routine-grid {
		list-style: none;
		padding: 0;
		margin: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
		gap: 0.75rem;
	}
	.routine-card {
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
	.routine-card:hover {
		border-color: var(--accent, #3b6ef5);
	}
	.routine-name {
		font-weight: 600;
		font-size: 1.05rem;
	}
	.routine-author {
		font-size: 0.85rem;
		color: var(--text-muted, #667);
	}
	.routine-meta {
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
	.routine-cta {
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
