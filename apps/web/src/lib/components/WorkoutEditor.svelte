<script lang="ts">
	import { untrack } from 'svelte';
	import { markWorkoutCompleted, updatePlanWorkout } from '$lib/data';
	import {
		isWorkoutCompleted,
		WORKOUT_KIND_LABEL,
		type WorkoutKind
	} from '$lib/training';
	import { getUnit } from '$lib/units.svelte';
	import type { PlanWorkout } from '$lib/types';
	import Modal from './Modal.svelte';

	interface Props {
		workout: PlanWorkout;
		onClose: () => void;
		onSaved: () => void;
	}
	let { workout, onClose, onSaved }: Props = $props();

	// All inputs are rendered + stored in the user's preferred unit so
	// the form matches the rest of the app. Conversion to the canonical
	// metric storage shape (metres + sec/km) happens at save time only.
	const METRES_PER_MILE = 1609.344;
	const unit = getUnit();
	const distanceDivisor = unit === 'mi' ? METRES_PER_MILE : 1000;
	const paceFactor = unit === 'mi' ? METRES_PER_MILE / 1000 : 1;

	function paceFromCanonical(sec: number): number {
		return sec * paceFactor;
	}

	// Local form state. Initialised from the workout row and only pushed to
	// the server when the user hits Save, so cancelling restores cleanly.
	// Each initialiser runs inside `untrack` because we want a one-time
	// snapshot of the prop — without it, Svelte 5 (correctly) warns that
	// reading the reactive `workout` prop here captures only its initial
	// value and won't track later changes. That's the intended behaviour:
	// the form holds its own state until Save / Cancel.
	let kind = $state<WorkoutKind>(untrack(() => workout.kind as WorkoutKind));
	let distance = $state<number | null>(untrack(() =>
		workout.target_distance_m != null
			? +(workout.target_distance_m / distanceDivisor).toFixed(2)
			: null
	));
	let paceMin = $state<number | null>(untrack(() =>
		workout.target_pace_sec_per_km != null
			? Math.floor(paceFromCanonical(workout.target_pace_sec_per_km) / 60)
			: null
	));
	let paceSec = $state<number | null>(untrack(() =>
		workout.target_pace_sec_per_km != null
			? Math.round(paceFromCanonical(workout.target_pace_sec_per_km) % 60)
			: null
	));
	let paceEndMin = $state<number | null>(untrack(() =>
		workout.target_pace_end_sec_per_km != null
			? Math.floor(paceFromCanonical(workout.target_pace_end_sec_per_km) / 60)
			: null
	));
	let paceEndSec = $state<number | null>(untrack(() =>
		workout.target_pace_end_sec_per_km != null
			? Math.round(paceFromCanonical(workout.target_pace_end_sec_per_km) % 60)
			: null
	));
	let toleranceSec = $state<number | null>(
		untrack(() => workout.target_pace_tolerance_sec)
	);
	let zone = $state<string>(untrack(() => workout.pace_zone ?? ''));
	let notes = $state<string>(untrack(() => workout.notes ?? ''));
	let busy = $state(false);
	let error = $state<string | null>(null);

	// Workouts can be completed two ways: (1) auto-matched from a tracked
	// run via /runs (sets completed_run_id), or (2) the user taps
	// "Mark as done" here when they ran without recording — sets the
	// manually_completed flag instead. The two are mutually compatible:
	// linking a real run later overrides the manual flag without losing
	// the timestamp. These are read-only views of `workout`, so they
	// derive (re-evaluate when the prop changes) rather than capture once.
	const wasCompleted = $derived(isWorkoutCompleted(workout));
	const hasLinkedRun = $derived(workout.completed_run_id != null);

	const kindOptions: WorkoutKind[] = [
		'easy', 'long', 'recovery', 'tempo', 'interval', 'marathon_pace', 'race', 'rest'
	];

	async function toggleCompleted() {
		busy = true;
		error = null;
		try {
			if (wasCompleted) {
				// Both paths clear via runId=null. The unlink confirm flow on
				// the workout-detail page handles linked-run unlinking with
				// a dialog; here we keep it one-tap because the user is in
				// an editor context.
				await markWorkoutCompleted(workout.id, null);
			} else {
				await markWorkoutCompleted(workout.id, null, { manual: true });
			}
			onSaved();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Update failed';
		} finally {
			busy = false;
		}
	}

	async function save() {
		busy = true;
		error = null;
		try {
			const paceStartUnit =
				paceMin != null ? paceMin * 60 + (paceSec ?? 0) : null;
			const paceEndUnit =
				paceEndMin != null ? paceEndMin * 60 + (paceEndSec ?? 0) : null;
			const paceStart =
				paceStartUnit != null ? paceStartUnit / paceFactor : null;
			const paceEnd =
				paceEndUnit != null ? paceEndUnit / paceFactor : null;
			const isRest = kind === 'rest';
			const unstructuredKinds = ['easy', 'long', 'recovery', 'rest'] as const;
			const isUnstructured = (unstructuredKinds as readonly string[]).includes(kind);
			await updatePlanWorkout(workout.id, {
				kind,
				target_distance_m: isRest
					? null
					: distance != null
						? distance * distanceDivisor
						: null,
				target_pace_sec_per_km: isRest ? null : paceStart,
				target_pace_end_sec_per_km: isRest ? null : paceEnd,
				target_pace_tolerance_sec: isRest ? null : toleranceSec,
				pace_zone: isRest ? null : zone.trim() || null,
				notes: notes.trim() || null,
				structure: isUnstructured ? null : undefined,
			});
			onSaved();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Save failed';
		} finally {
			busy = false;
		}
	}
</script>

<Modal
	open={true}
	title="Edit workout · {workout.scheduled_date}"
	onclose={onClose}
>
		<label>
			<span>Kind</span>
			<select bind:value={kind}>
				{#each kindOptions as k}
					<option value={k}>{WORKOUT_KIND_LABEL[k]}</option>
				{/each}
			</select>
		</label>

		{#if kind !== 'rest'}
			<label>
				<span>Distance <span class="hint">{unit}</span></span>
				<input type="number" min="0" step="0.1" bind:value={distance} />
			</label>

			<fieldset>
				<legend>Target pace <span class="hint">per {unit}</span></legend>
				<div class="pace-row">
					<input type="number" min="0" max="59" bind:value={paceMin} placeholder="min" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={paceSec} placeholder="sec" />
					<span class="arrow">→</span>
					<input
						type="number"
						min="0"
						max="59"
						bind:value={paceEndMin}
						placeholder="min"
					/>
					<span>:</span>
					<input
						type="number"
						min="0"
						max="59"
						bind:value={paceEndSec}
						placeholder="sec"
					/>
				</div>
				<p class="hint">
					Right side is optional — use when the pace progresses across a phase (e.g. MP 7:15 → 6:41).
				</p>
			</fieldset>

			<label>
				<span>Pace tolerance <span class="hint">± seconds</span></span>
				<input type="number" min="0" max="60" bind:value={toleranceSec} />
			</label>

			<label>
				<span>Zone label <span class="hint">optional — E, T, I, MP…</span></span>
				<input type="text" bind:value={zone} maxlength="16" />
			</label>
		{/if}

		<label>
			<span>Notes</span>
			<textarea rows="3" bind:value={notes} maxlength="500"></textarea>
		</label>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		<div class="actions">
			<button class="btn btn-secondary" onclick={onClose} disabled={busy}>Cancel</button>
			<button
				class="btn btn-outline"
				onclick={toggleCompleted}
				disabled={busy || hasLinkedRun}
				title={hasLinkedRun
					? 'A run is linked — unlink it from the workout detail page first.'
					: wasCompleted
						? 'Clear the manual completion flag.'
						: 'Mark this workout as done without a tracked run.'}
			>
				{wasCompleted ? 'Mark not done' : 'Mark as done'}
			</button>
			<button class="btn btn-primary" onclick={save} disabled={busy}>
				{busy ? 'Saving…' : 'Save'}
			</button>
		</div>
</Modal>

<style>
	/* Canonical .modal-backdrop / .modal / .modal-header / .modal-close /
	   .modal-body live in app.css; only field-level styling stays
	   here. */
	.modal-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.date {
		color: var(--color-primary);
		font-weight: 700;
	}
	label,
	fieldset {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 0.88rem;
		font-weight: 600;
		border: none;
		padding: 0;
	}
	fieldset {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.7rem 0.85rem;
		background: var(--color-surface);
	}
	legend {
		padding: 0 0.4rem;
	}
	.hint {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}
	input,
	select,
	textarea {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.45rem 0.65rem;
		color: inherit;
		font: inherit;
	}
	.pace-row {
		display: flex;
		align-items: center;
		gap: 0.3rem;
	}
	.pace-row input {
		width: 3.5rem;
	}
	.pace-row .arrow {
		color: var(--color-text-tertiary);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
		margin-top: var(--space-sm);
	}
	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
	}
</style>
