<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchGymRoutinesWithError, type GymRoutineSummary } from '$lib/core/data';
	import { formatDate } from '$lib/format/time';
	import ActivityLoader from '$lib/components/ActivityLoader.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	let routines = $state<GymRoutineSummary[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	async function load() {
		loading = true;
		loadError = null;
		const result = await fetchGymRoutinesWithError(100);
		routines = result.routines;
		loadError = result.error;
		loading = false;
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) return;
		await load();
	});
</script>

<svelte:head><title>{t('gym.routine.title')} — Threkir</title></svelte:head>

<div class="page">
	<header class="page-header">
		<div class="head-text">
			<a class="back-link" href="/gym">
				<span class="material-symbols" aria-hidden="true">arrow_back</span>
				{t('gym.back')}
			</a>
			<h1>{t('gym.routine.title')}</h1>
			{#if !loading && routines.length > 0}
				<p class="head-sub">{t('gym.routine.subtitle', { count: routines.length })}</p>
			{/if}
		</div>
		<div class="head-actions">
			<a class="btn btn-outline" href="/gym/routines/library" data-testid="routine-library">
				<span class="material-symbols" aria-hidden="true">public</span>
				{t('gymLibrary.link')}
			</a>
			<a class="btn btn-primary" href="/gym/routines/new" data-testid="routine-new">
				<span class="material-symbols" aria-hidden="true">add</span>
				{t('gym.routine.new')}
			</a>
		</div>
	</header>

	{#if loading}
		<div class="act-load"><ActivityLoader kind="train" size={76} label={t('shell.loading')} /></div>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{t('gym.routine.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" onclick={load}>{t('gym.routine.retry')}</button>
		</div>
	{:else if routines.length === 0}
		<div class="card-elevated empty-card" data-testid="routine-empty">
			<span class="material-symbols empty-icon" aria-hidden="true">list_alt</span>
			<p class="empty-title empty-text">{t('gym.routine.empty.title')}</p>
			<p class="empty-text empty-body">{t('gym.routine.empty.body')}</p>
		</div>
	{:else}
		<ul class="routine-list" data-testid="routine-list">
			{#each routines as r (r.id)}
				<li>
					<a class="card-elevated routine-row" href="/gym/routines/{r.id}">
						<div class="row-main">
							<span class="row-title">{r.title}</span>
							<span class="row-date">{formatDate(r.last_modified_at)}</span>
						</div>
						<div class="row-stats">
							<span class="stat">
								<span class="stat-value">{r.exercise_count}</span>
								<span class="stat-label section-label"
									>{t('gym.exercisesLabel')}</span
								>
							</span>
							<span class="material-symbols chevron" aria-hidden="true">chevron_right</span>
						</div>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.act-load {
		display: flex;
		justify-content: center;
		padding: var(--space-2xl) 0;
	}
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.page-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin-bottom: var(--space-lg);
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.head-sub {
		color: var(--color-text-tertiary);
		margin: var(--space-2xs) 0 0;
	}
	.routine-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.routine-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md);
		text-decoration: none;
		color: inherit;
	}
	.row-main {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.row-title {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.row-date {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}
	.row-stats {
		display: flex;
		align-items: center;
		gap: var(--space-md);
	}
	.stat {
		display: flex;
		flex-direction: column;
		align-items: center;
	}
	.stat-value {
		font-weight: 600;
	}
	.chevron {
		color: var(--color-text-tertiary);
	}
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2xs);
		padding: var(--space-2xl);
		text-align: center;
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
	}
	.empty-title {
		font-weight: 600;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.4rem;
	}
</style>
