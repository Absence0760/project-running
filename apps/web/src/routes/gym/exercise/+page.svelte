<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchGymSetHistory } from '$lib/core/data';
	import { exerciseProgress, type ExerciseProgress, type ExerciseSession } from '$lib/gym/exercise_history';
	import { formatDate } from '$lib/format/time';
	import { formatWeight } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	const name = $derived($page.url.searchParams.get('name') ?? '');

	let progress = $state<ExerciseProgress | null>(null);
	let loading = $state(true);

	async function load() {
		loading = true;
		progress = name ? exerciseProgress(await fetchGymSetHistory(), name) : null;
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

	// Re-load when the ?name= changes (navigating between exercises). Seed
	// lastName to the mount-time name so this only fires on a *subsequent*
	// change — onMount owns the first load, so the effect must not double it.
	let lastName = $state(untrack(() => name));
	$effect(() => {
		if (name !== lastName) {
			lastName = name;
			if (auth.user) void load();
		}
	});

	// Most-recent-first for the list (sessions come oldest-first).
	const reversed = $derived([...(progress?.sessions ?? [])].reverse());

	// Bar width: each session's e1rm relative to the best, so the visual climbs
	// toward 100% at the PR session. Sessions with no e1rm get no bar.
	function barPct(s: ExerciseSession): number {
		const best = progress?.bestEst1RmKg;
		if (!best || s.bestEst1RmKg == null) return 0;
		return Math.max(4, Math.round((s.bestEst1RmKg / best) * 100));
	}
	function topSetLine(s: ExerciseSession): string {
		const w = formatWeight(s.topWeightKg);
		return s.topWeightReps != null ? `${w} × ${s.topWeightReps}` : w;
	}
	function deltaText(p: ExerciseProgress): string {
		const d = p.est1RmDeltaKg;
		if (d == null || d === 0) return t('gym.exercise.sinceFirstFlat');
		const mag = formatWeight(Math.abs(d));
		return d > 0
			? t('gym.exercise.sinceFirstUp', { delta: mag })
			: t('gym.exercise.sinceFirstDown', { delta: mag });
	}
	function deltaDir(p: ExerciseProgress): 'up' | 'down' | 'flat' {
		const d = p.est1RmDeltaKg;
		if (d == null || d === 0) return 'flat';
		return d > 0 ? 'up' : 'down';
	}
	function sessionsText(n: number): string {
		return n === 1
			? t('gym.records.sessionsOne')
			: t('gym.records.sessionsMany', { count: n });
	}
</script>

<svelte:head><title>{progress?.exerciseName || name || t('gym.title')} — Threkir</title></svelte:head>

<div class="page">
	<a class="back" href="/gym/records">
		<span class="material-symbols">arrow_back</span>{t('gym.exercise.back')}
	</a>

	{#if loading}
		<div class="skel-head" aria-hidden="true">
			<span class="skel skel-line skel-w-50"></span>
			<span class="skel skel-line skel-w-30"></span>
		</div>
		<ul class="session-list" aria-hidden="true">
			{#each Array(4) as _, i (i)}
				<li class="skel-row"><span class="skel skel-line"></span></li>
			{/each}
		</ul>
		<p class="sr-only" role="status">{t('shell.loading')}</p>
	{:else if !progress}
		<div class="empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">monitoring</span>
			<p class="empty-text">{t('gym.exercise.empty')}</p>
			<a href="/gym/records" class="btn btn-outline">{t('gym.exercise.back')}</a>
		</div>
	{:else}
		<header class="head">
			<h1>{progress.exerciseName}</h1>
			<div class="headline">
				{#if progress.latestEst1RmKg != null}
					<span class="big-1rm">{formatWeight(progress.latestEst1RmKg)}</span>
					<span class="section-label">{t('gym.pr.e1rm')}</span>
				{/if}
				{#if progress.est1RmDeltaKg != null}
					<span class="delta delta-{deltaDir(progress)}">
						<span class="material-symbols" aria-hidden="true">
							{deltaDir(progress) === 'up'
								? 'trending_up'
								: deltaDir(progress) === 'down'
									? 'trending_down'
									: 'trending_flat'}
						</span>
						{deltaText(progress)}
					</span>
				{/if}
			</div>
			<p class="sub">{sessionsText(progress.sessions.length)}</p>
		</header>

		<ul class="session-list">
			{#each reversed as s (s.workoutId)}
				<li class="session-row">
					<a class="row-link" href="/gym/{s.workoutId}">
						<div class="row-top">
							<span class="row-date">{formatDate(s.startedAt)}</span>
							{#if s.isEst1RmPr}
								<span class="pr-badge">
									<span class="material-symbols" aria-hidden="true">trophy</span>
									{t('gym.pr.badge')}
								</span>
							{/if}
							<span class="row-top-set">{topSetLine(s)}</span>
						</div>
						{#if s.bestEst1RmKg != null}
							<div class="bar-track" aria-hidden="true">
								<div class="bar-fill" style="width: {barPct(s)}%"></div>
							</div>
							<div class="row-metrics">
								<span>{formatWeight(s.bestEst1RmKg)} <span class="section-label">{t('gym.pr.e1rm')}</span></span>
								{#if s.volumeKg > 0}
									<span>{formatWeight(s.volumeKg)} <span class="section-label">{t('gym.volumeLabel')}</span></span>
								{/if}
							</div>
						{/if}
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
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

	.head {
		margin-bottom: var(--space-xl);
	}
	.head h1 {
		margin: 0 0 var(--space-2xs);
		font-size: 1.6rem;
	}
	.headline {
		display: flex;
		align-items: baseline;
		flex-wrap: wrap;
		gap: var(--space-2xs) var(--space-md);
	}
	.big-1rm {
		font-size: 2rem;
		font-weight: 700;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}
	.delta {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		font-size: 0.85rem;
		font-weight: 600;
	}
	.delta .material-symbols {
		font-size: 1rem;
	}
	.delta-up {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.delta-down,
	.delta-flat {
		color: var(--color-text-secondary);
	}
	.sub {
		margin: var(--space-2xs) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}

	.session-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.row-link {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding: var(--space-md) var(--space-lg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		text-decoration: none;
		color: inherit;
		transition:
			border-color var(--transition-fast),
			box-shadow var(--transition-fast);
	}
	.row-link:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}
	.row-link:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.row-top {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.row-date {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.row-top-set {
		margin-inline-start: auto;
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.pr-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		font-size: 0.65rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		color: #fff;
		background: var(--color-primary);
		padding: 0.1rem 0.4rem;
		border-radius: var(--radius-sm);
	}
	.pr-badge .material-symbols {
		font-size: 0.8rem;
	}
	.bar-track {
		height: 0.4rem;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-pill, 999px);
		overflow: hidden;
	}
	.bar-fill {
		height: 100%;
		background: var(--color-primary);
		border-radius: inherit;
	}
	.row-metrics {
		display: flex;
		gap: var(--space-lg);
		font-size: 0.85rem;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
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
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.empty-card .btn {
		margin-top: var(--space-xs);
	}

	.skel-head {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-bottom: var(--space-xl);
	}
	.skel-row {
		padding: var(--space-md) var(--space-lg);
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
	.skel-w-30 {
		width: 30%;
	}
	.skel-w-50 {
		width: 50%;
		height: 1.4rem;
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
