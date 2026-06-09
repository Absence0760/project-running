<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchGymWorkouts,
		fetchGymSetHistory,
		type GymWorkout,
		type GymSetWithDate,
	} from '$lib/core/data';
	import { workoutPrs, type GymSetLike } from '$lib/gym/gym_prs';
	import { formatDate } from '$lib/format/time';
	import { formatWeight } from '$lib/format/units.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import GymEditor from '$lib/components/GymEditor.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	let workouts = $state<GymWorkout[]>([]);
	let history = $state<GymSetWithDate[]>([]);
	let loading = $state(true);
	let showCreate = $state(false);

	async function load() {
		[workouts, history] = await Promise.all([fetchGymWorkouts(100), fetchGymSetHistory()]);
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		await load();
	});

	// Sets grouped by workout id.
	const setsByWorkout = $derived.by(() => {
		const map = new Map<string, GymSetWithDate[]>();
		for (const s of history) {
			const arr = map.get(s.workout_id) ?? [];
			arr.push(s);
			map.set(s.workout_id, arr);
		}
		return map;
	});

	// Total working volume (Σ reps·weight) per workout, for the row stat.
	function volumeOf(id: string): number {
		let v = 0;
		for (const s of setsByWorkout.get(id) ?? []) {
			if (s.reps != null && s.weight_kg != null) v += s.reps * s.weight_kg;
		}
		return Math.round(v);
	}
	function exerciseCountOf(id: string): number {
		const names = new Set<string>();
		for (const s of setsByWorkout.get(id) ?? []) names.add(s.exercise_name.trim().toLowerCase());
		return names.size;
	}
	function setCountOf(id: string): number {
		return (setsByWorkout.get(id) ?? []).length;
	}

	// Which workouts set at least one PR. Walk oldest→newest accumulating
	// prior sets so each workout is judged against everything before it.
	const prWorkoutIds = $derived.by(() => {
		const ids = new Set<string>();
		const ordered = [...workouts].sort((a, b) => a.started_at.localeCompare(b.started_at));
		const prior: GymSetLike[] = [];
		for (const w of ordered) {
			const mine = (setsByWorkout.get(w.id) ?? []).map(
				(s): GymSetLike => ({ exercise_name: s.exercise_name, reps: s.reps, weight_kg: s.weight_kg }),
			);
			if (workoutPrs(prior, mine).length > 0) ids.add(w.id);
			prior.push(...mine);
		}
		return ids;
	});

	// Whether any logged set carries a positive weight — gates the Records
	// link, since /gym/records only surfaces weighted exercises.
	const hasWeightedRecords = $derived(
		history.some((s) => s.weight_kg != null && s.weight_kg > 0),
	);

	// Distinct exercise names from history, most-used first — the composer
	// autocomplete source.
	const suggestions = $derived.by(() => {
		const counts = new Map<string, number>();
		for (const s of history) {
			const name = s.exercise_name.trim();
			if (name === '') continue;
			counts.set(name, (counts.get(name) ?? 0) + 1);
		}
		return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([n]) => n);
	});

	function onCreated() {
		showCreate = false;
		void load();
	}
</script>

<svelte:head><title>{t('gym.title')} — Threkir</title></svelte:head>

<div class="page">
	<header class="page-header">
		<div class="head-text">
			<h1>{t('gym.title')}</h1>
			{#if !loading && workouts.length > 0}
				<p class="head-sub">
					{workouts.length === 1
						? t('gym.workoutsOne')
						: t('gym.workoutsMany', { count: workouts.length })}
				</p>
			{/if}
		</div>
		<div class="head-actions">
			{#if !loading && hasWeightedRecords}
				<a class="btn btn-secondary" href="/gym/records" data-testid="gym-records-link">
					<span class="material-symbols" aria-hidden="true">trophy</span>
					{t('gym.records.link')}
				</a>
			{/if}
			<button class="btn btn-primary" onclick={() => (showCreate = true)} data-testid="gym-log">
				<span class="material-symbols" aria-hidden="true">add</span>
				{t('gym.log')}
			</button>
		</div>
	</header>

	{#if loading}
		<ul class="workout-list" aria-hidden="true">
			{#each Array(5) as _, i (i)}
				<li class="card-elevated skel-row">
					<span class="skel skel-line skel-w-40"></span>
					<span class="skel skel-pill"></span>
				</li>
			{/each}
		</ul>
		<p class="sr-only" role="status">{t('shell.loading')}</p>
	{:else if workouts.length === 0}
		<div class="card-elevated empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">fitness_center</span>
			<p class="empty-title empty-text">{t('gym.empty.title')}</p>
			<p class="empty-text empty-body">{t('gym.empty.body')}</p>
			<button class="btn btn-primary" onclick={() => (showCreate = true)}>
				<span class="material-symbols" aria-hidden="true">add</span>
				{t('gym.log')}
			</button>
		</div>
	{:else}
		<ul class="workout-list">
			{#each workouts as w (w.id)}
				<li>
					<a class="card-elevated workout-row" href="/gym/{w.id}">
						<div class="row-main">
							<span class="row-title">{w.title || t('gym.untitled')}</span>
							<span class="row-date">{formatDate(w.started_at)}</span>
						</div>
						<div class="row-stats">
							{#if prWorkoutIds.has(w.id)}
								<span class="pr-badge" aria-label={t('gym.pr.title')}>
									<span class="material-symbols" aria-hidden="true">trophy</span>
									{t('gym.pr.badge')}
								</span>
							{/if}
							<span class="stat">
								<span class="stat-value">{exerciseCountOf(w.id)}</span>
								<span class="stat-label section-label">{t('gym.exercisesLabel')}</span>
							</span>
							<span class="stat">
								<span class="stat-value">{setCountOf(w.id)}</span>
								<span class="stat-label section-label">{t('gym.setsLabel')}</span>
							</span>
							{#if volumeOf(w.id) > 0}
								<span class="stat stat-volume">
									<span class="stat-value">{formatWeight(volumeOf(w.id))}</span>
									<span class="stat-label section-label">{t('gym.volumeLabel')}</span>
								</span>
							{/if}
							<span class="material-symbols chevron" aria-hidden="true">chevron_right</span>
						</div>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<Modal open={showCreate} title={t('gym.editor.newTitle')} onclose={() => (showCreate = false)}>
	<GymEditor {suggestions} oncreated={onCreated} oncancel={() => (showCreate = false)} />
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.page-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: var(--space-xl);
		gap: var(--space-md);
	}
	.head-text {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.page-header h1 {
		margin: 0;
	}
	.head-sub {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.head-actions {
		display: flex;
		gap: var(--space-sm);
		flex-shrink: 0;
	}
	.page-header .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		flex-shrink: 0;
		text-decoration: none;
	}
	.page-header .material-symbols {
		font-size: 1.1rem;
	}

	/* Empty-state card — same shape as /routes, /history, /dashboard. */
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		text-align: center;
	}
	.empty-title {
		margin: 0;
		padding: 0;
		font-size: 1.05rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-body {
		max-width: 32rem;
		margin: 0;
		padding: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.empty-card .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		margin-top: var(--space-sm);
	}
	.empty-card .material-symbols {
		font-size: 1.1rem;
	}

	.workout-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.workout-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-lg);
		padding: var(--space-md) var(--space-lg);
		text-decoration: none;
		color: inherit;
		transition:
			border-color var(--transition-fast),
			box-shadow var(--transition-base);
	}
	.workout-row:hover {
		border-color: var(--color-primary);
	}
	.workout-row:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.row-main {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.row-title {
		font-weight: 600;
		font-size: 1rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.row-date {
		font-size: 0.82rem;
		color: var(--color-text-secondary);
	}
	.row-stats {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
		flex-shrink: 0;
	}
	.stat {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-2xs);
		white-space: nowrap;
	}
	.stat-value {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.stat-label {
		color: var(--color-text-tertiary);
	}
	.pr-badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		color: var(--color-primary);
		background: var(--color-primary-light);
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
		align-self: center;
	}
	.pr-badge .material-symbols {
		font-size: 0.85rem;
	}
	.chevron {
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}

	/* Skeleton — same shimmer language as /routes + /history. */
	.skel-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-lg);
		padding: var(--space-md) var(--space-lg);
	}
	.skel {
		display: block;
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
	.skel-line {
		height: 0.95rem;
	}
	.skel-w-40 {
		width: 40%;
		max-width: 16rem;
	}
	.skel-pill {
		width: 9rem;
		height: 1.6rem;
		border-radius: var(--radius-md);
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

	/* On a phone the per-stat stack would crowd the title; drop the
	   Sets stat label group to keep the row scannable. */
	@media (max-width: 30rem) {
		.row-stats {
			gap: var(--space-md);
		}
		.stat-volume {
			display: none;
		}
	}
</style>
