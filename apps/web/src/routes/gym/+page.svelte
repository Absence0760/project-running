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

<svelte:head><title>{t('gym.title')} · Threkir</title></svelte:head>

<div class="gym-page">
	<header class="page-head">
		<h1>{t('gym.title')}</h1>
		<button class="btn btn-primary" onclick={() => (showCreate = true)} data-testid="gym-log">
			{t('gym.log')}
		</button>
	</header>

	{#if loading}
		<p class="muted">{t('shell.loading')}</p>
	{:else if workouts.length === 0}
		<div class="empty">
			<h2>{t('gym.empty.title')}</h2>
			<p class="muted">{t('gym.empty.body')}</p>
			<button class="btn btn-primary" onclick={() => (showCreate = true)}>{t('gym.log')}</button>
		</div>
	{:else}
		<ul class="workout-list">
			{#each workouts as w (w.id)}
				<li>
					<a class="workout-row" href="/gym/{w.id}">
						<div class="row-main">
							<span class="row-title">{w.title || t('gym.untitled')}</span>
							<span class="row-date">{formatDate(w.started_at)}</span>
						</div>
						<div class="row-stats">
							{#if prWorkoutIds.has(w.id)}
								<span class="pr-badge" title={t('gym.pr.badge')}>{t('gym.pr.badge')}</span>
							{/if}
							<span class="stat">{t('gym.exercisesShort', { count: exerciseCountOf(w.id) })}</span>
							{#if volumeOf(w.id) > 0}
								<span class="stat">{t('gym.volumeShort', { volume: formatWeight(volumeOf(w.id)) })}</span>
							{/if}
							<span class="material-symbols-outlined chevron">chevron_right</span>
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
	.gym-page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.page-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-xl);
		gap: var(--space-md);
	}
	.page-head h1 {
		margin: 0;
	}
	.muted {
		color: var(--text-secondary);
	}
	.empty {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
		max-width: 32rem;
	}
	.empty h2 {
		margin: 0;
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
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		border: 1px solid var(--border);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
		background: var(--surface);
	}
	.workout-row:hover {
		border-color: var(--accent, #d97a54);
	}
	.row-main {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.row-title {
		font-weight: 600;
	}
	.row-date {
		font-size: 0.85rem;
		color: var(--text-secondary);
	}
	.row-stats {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-shrink: 0;
	}
	.stat {
		font-size: 0.85rem;
		color: var(--text-secondary);
		white-space: nowrap;
	}
	.pr-badge {
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		color: #fff;
		background: var(--accent, #d97a54);
		padding: 2px 6px;
		border-radius: var(--radius-sm);
	}
	.chevron {
		color: var(--text-secondary);
	}
</style>
