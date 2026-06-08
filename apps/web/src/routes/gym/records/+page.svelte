<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchGymSetHistory } from '$lib/core/data';
	import { exerciseRecords, type ExerciseRecord } from '$lib/gym/exercise_records';
	import { formatDate } from '$lib/format/time';
	import { formatWeight } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	let records = $state<ExerciseRecord[]>([]);
	let loading = $state(true);

	async function load() {
		records = exerciseRecords(await fetchGymSetHistory());
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) {
			loading = false;
			return;
		}
		await load();
	});

	function heaviestLine(r: ExerciseRecord): string {
		const w = formatWeight(r.heaviestWeightKg);
		return r.heaviestWeightReps != null ? `${w} × ${r.heaviestWeightReps}` : w;
	}
	function sessionsLine(r: ExerciseRecord): string {
		return r.sessionCount === 1
			? t('gym.records.sessionsOne')
			: t('gym.records.sessionsMany', { count: r.sessionCount });
	}
</script>

<svelte:head><title>{t('gym.records.title')} — Threkir</title></svelte:head>

<div class="page">
	<a class="back" href="/gym">
		<span class="material-symbols">arrow_back</span>{t('gym.back')}
	</a>

	<header class="page-header">
		<h1>{t('gym.records.title')}</h1>
		<p class="head-sub">{t('gym.records.subtitle')}</p>
	</header>

	{#if loading}
		<ul class="record-grid" aria-hidden="true">
			{#each Array(6) as _, i (i)}
				<li class="skel-card">
					<span class="skel skel-line skel-w-50"></span>
					<span class="skel skel-line skel-w-70"></span>
					<span class="skel skel-line skel-w-40"></span>
				</li>
			{/each}
		</ul>
		<p class="sr-only" role="status">{t('shell.loading')}</p>
	{:else if records.length === 0}
		<div class="empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">trophy</span>
			<p class="empty-text">{t('gym.records.empty')}</p>
			<a href="/gym" class="btn btn-outline">{t('gym.back')}</a>
		</div>
	{:else}
		<ul class="record-grid">
			{#each records as r (r.exerciseName)}
				<li>
					<a class="record-card" href="/gym/exercise?name={encodeURIComponent(r.exerciseName)}">
					<h2 class="ex-name">{r.exerciseName}</h2>
					<dl class="metrics">
						{#if r.bestEst1RmKg != null}
							<div class="metric metric-primary">
								<dt class="section-label">{t('gym.pr.e1rm')}</dt>
								<dd>{formatWeight(r.bestEst1RmKg)}</dd>
							</div>
						{/if}
						<div class="metric">
							<dt class="section-label">{t('gym.pr.weight')}</dt>
							<dd>{heaviestLine(r)}</dd>
						</div>
						{#if r.bestVolumeKg != null}
							<div class="metric">
								<dt class="section-label">{t('gym.pr.volume')}</dt>
								<dd>{formatWeight(r.bestVolumeKg)}</dd>
							</div>
						{/if}
					</dl>
					<p class="meta">
						{#if r.lastPerformedAt}
							<span>{t('gym.records.lastDone', { date: formatDate(r.lastPerformedAt) })}</span>
							<span aria-hidden="true">·</span>
						{/if}
						<span>{sessionsLine(r)}</span>
					</p>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-secondary);
		text-decoration: none;
		margin-bottom: var(--space-lg);
		font-size: 0.9rem;
	}
	.back:hover {
		color: var(--color-primary);
	}
	.back:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
		border-radius: var(--radius-sm);
	}
	.page-header {
		margin-bottom: var(--space-xl);
	}
	.page-header h1 {
		margin: 0;
	}
	.head-sub {
		margin: 0.15rem 0 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}

	.record-grid {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr));
		gap: var(--space-md);
	}
	.record-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-lg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		text-decoration: none;
		color: inherit;
		height: 100%;
		transition:
			border-color var(--transition-fast),
			box-shadow var(--transition-fast);
	}
	.record-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}
	.record-card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.ex-name {
		margin: 0;
		font-size: 1.05rem;
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.metrics {
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.metric {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-md);
	}
	.metric dt {
		margin: 0;
	}
	.metric dd {
		margin: 0;
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.metric-primary dd {
		font-size: 1.25rem;
		color: var(--color-primary);
	}
	.meta {
		margin: 0;
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}

	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-text {
		max-width: 32rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.empty-card .btn {
		margin-top: var(--space-xs);
	}

	/* Skeleton — same shimmer language as the gym list. */
	.skel-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-lg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
	}
	.skel {
		display: block;
		height: 0.95rem;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-w-40 {
		width: 40%;
	}
	.skel-w-50 {
		width: 50%;
	}
	.skel-w-70 {
		width: 70%;
	}
	@keyframes skel-shimmer {
		0% {
			background-position: 200% 0;
		}
		100% {
			background-position: -200% 0;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.skel {
			animation: none;
		}
	}

	.sr-only {
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
