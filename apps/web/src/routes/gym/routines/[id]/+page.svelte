<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchGymRoutineDetail,
		deleteGymRoutine,
		fetchGymExerciseNames,
		type GymRoutineDetail,
		type GymSetInput,
	} from '$lib/core/data';
	import { prefillFromRoutine, type PlannedRoutine } from '$lib/gym/gym_routine';
	import { formatWeight, weightUnitLabel, parseWeight } from '$lib/format/units.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import GymEditor from '$lib/components/GymEditor.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import type { GymWorkoutWithSets } from '$lib/core/data';

	let detail = $state<GymRoutineDetail | null>(null);
	let loading = $state(true);
	let confirmingDelete = $state(false);
	let showStart = $state(false);
	let suggestions = $state<string[]>([]);
	let startSeed = $state<GymWorkoutWithSets | null>(null);

	const routineId = $derived($page.params.id ?? '');

	async function load() {
		detail = await fetchGymRoutineDetail(routineId);
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		[, suggestions] = await Promise.all([load(), fetchGymExerciseNames()]);
	});

	async function doDelete() {
		try {
			await deleteGymRoutine(routineId);
			showToast(t('gym.routine.deleted'));
			goto('/gym/routines');
		} catch (e) {
			console.error('routine delete failed', e);
			showToast(t('gym.routine.saveFailed'));
		}
	}

	// "Start routine" (P1: prefill-only — no execution loop). Expand the saved
	// plan into editable GymEditor blocks via prefillFromRoutine, then seed a
	// fresh GymEditor (logging a new session) with those targets as actuals.
	function startRoutine() {
		if (!detail) return;
		const planned: PlannedRoutine = {
			title: detail.routine.title,
			exercises: detail.exercises.map((e) => ({
				exerciseName: e.exercise_name,
				position: e.position,
				sets: e.sets.map((s) => ({
					setIndex: s.set_index,
					targetRepsMin: s.target_reps_min,
					targetRepsMax: s.target_reps_max,
					targetWeightKg: s.target_weight_kg,
					targetRpe: s.target_rpe,
				})),
			})),
		};
		const blocks = prefillFromRoutine(planned);
		// Re-shape the prefill into a GymWorkoutWithSets so GymEditor's
		// initExercises rebuilds the same blocks (it groups by consecutive
		// exercise_name). Weight is canonical kg.
		const sets: GymSetInput[] = [];
		let order = 0;
		for (const b of blocks) {
			if (b.name.trim() === '') continue;
			for (const s of b.sets) {
				sets.push({
					exercise_name: b.name,
					reps: s.reps === '' ? null : parseInt(s.reps, 10),
					weight_kg: s.weightKg ?? null,
					rpe: s.rpe === '' ? null : parseFloat(s.rpe),
				});
				order++;
			}
		}
		startSeed = {
			workout: {
				id: '',
				user_id: auth.user?.id ?? '',
				title: detail.routine.title,
				started_at: new Date().toISOString(),
				duration_s: null,
				notes: null,
				is_public: false,
				external_id: null,
				last_modified_at: new Date().toISOString(),
				created_at: new Date().toISOString(),
			},
			sets: sets.map((s, i) => ({
				id: '',
				workout_id: '',
				set_index: i,
				exercise_name: s.exercise_name,
				reps: s.reps ?? null,
				weight_kg: s.weight_kg ?? null,
				rpe: s.rpe ?? null,
			})),
		};
		void order;
		showStart = true;
	}

	function onLogged() {
		showStart = false;
		startSeed = null;
		goto('/gym');
	}

	function repLabel(s: { target_reps_min: number | null; target_reps_max: number | null }): string {
		if (s.target_reps_min == null) return '—';
		if (s.target_reps_max != null && s.target_reps_max !== s.target_reps_min) {
			return `${s.target_reps_min}–${s.target_reps_max}`;
		}
		return String(s.target_reps_min);
	}
</script>

<svelte:head><title>{detail?.routine.title ?? t('gym.routine.title')} — Threkir</title></svelte:head>

<div class="page">
	<a class="back-link" href="/gym/routines">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{t('gym.routine.back')}
	</a>

	{#if loading}
		<p class="sr-only" role="status">{t('shell.loading')}</p>
	{:else if !detail}
		<p class="not-found">{t('gym.routine.notFound')}</p>
	{:else}
		<header class="detail-header">
			<div>
				<h1>{detail.routine.title}</h1>
				<p class="head-sub">
					{t('gym.routine.exerciseCount', { count: detail.routine.exercise_count })}
				</p>
				{#if detail.routine.notes}
					<p class="notes">{detail.routine.notes}</p>
				{/if}
			</div>
			<div class="head-actions">
				<button
					class="btn btn-primary"
					onclick={startRoutine}
					data-testid="routine-start"
				>
					<span class="material-symbols" aria-hidden="true">play_arrow</span>
					{t('gym.routine.start')}
				</button>
				<button
					class="btn btn-danger"
					onclick={() => (confirmingDelete = true)}
					data-testid="routine-delete"
				>
					{t('gym.routine.delete')}
				</button>
			</div>
		</header>

		<ul class="exercise-list" data-testid="routine-exercises">
			{#each detail.exercises as ex (ex.id)}
				<li class="card-elevated exercise-card">
					<span class="exercise-name">{ex.exercise_name}</span>
					<table class="set-table">
						<thead>
							<tr>
								<th class="section-label">{t('gym.routine.targetReps')}</th>
								<th class="section-label"
									>{t('gym.routine.targetWeight', { unit: weightUnitLabel() })}</th
								>
							</tr>
						</thead>
						<tbody>
							{#each ex.sets as s (s.set_index)}
								<tr>
									<td>{repLabel(s)}</td>
									<td>{s.target_weight_kg == null ? '—' : formatWeight(s.target_weight_kg)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<Modal open={showStart} title={detail?.routine.title ?? ''} onclose={() => (showStart = false)}>
	<GymEditor
		seed={startSeed}
		{suggestions}
		oncreated={onLogged}
		oncancel={() => (showStart = false)}
	/>
</Modal>

<ConfirmDialog
	open={confirmingDelete}
	title={t('gym.routine.deleteConfirm.title')}
	message={t('gym.routine.deleteConfirm.body')}
	confirmLabel={t('gym.routine.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmingDelete = false)}
/>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--text-muted);
		font-size: 0.9rem;
	}
	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin: var(--space-sm) 0 var(--space-lg);
	}
	.head-sub {
		color: var(--text-muted);
		margin: var(--space-2xs) 0 0;
	}
	.notes {
		margin: var(--space-2xs) 0 0;
	}
	.head-actions {
		display: flex;
		gap: var(--space-sm);
	}
	.exercise-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.exercise-card {
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.exercise-name {
		font-weight: 600;
	}
	.set-table {
		border-collapse: collapse;
		width: 100%;
		max-width: 20rem;
	}
	.set-table th {
		text-align: left;
		padding-right: var(--space-md);
	}
	.set-table td {
		padding-right: var(--space-md);
	}
	.not-found {
		color: var(--text-muted);
	}
</style>
