<script lang="ts">
	import { updatePlanWorkout } from '$lib/data';
	import {
		WORKOUT_KIND_LABEL,
		type WorkoutKind
	} from '$lib/training';
	import { fmtKm, fmtPace } from '$lib/units.svelte';
	import type { PlanWorkout } from '$lib/types';

	interface Props {
		workout: PlanWorkout;
		onClose: () => void;
		onSaved: () => void;
	}
	let { workout, onClose, onSaved }: Props = $props();

	// Local form state. Initialised from the workout row and only pushed to
	// the server when the user hits Save, so cancelling restores cleanly.
	let kind = $state<WorkoutKind>(workout.kind as WorkoutKind);
	let distanceKm = $state<number | null>(
		workout.target_distance_m != null ? +(workout.target_distance_m / 1000).toFixed(2) : null
	);
	let paceMin = $state<number | null>(
		workout.target_pace_sec_per_km != null ? Math.floor(workout.target_pace_sec_per_km / 60) : null
	);
	let paceSec = $state<number | null>(
		workout.target_pace_sec_per_km != null ? workout.target_pace_sec_per_km % 60 : null
	);
	let paceEndMin = $state<number | null>(
		workout.target_pace_end_sec_per_km != null
			? Math.floor(workout.target_pace_end_sec_per_km / 60)
			: null
	);
	let paceEndSec = $state<number | null>(
		workout.target_pace_end_sec_per_km != null
			? workout.target_pace_end_sec_per_km % 60
			: null
	);
	let toleranceSec = $state<number | null>(workout.target_pace_tolerance_sec);
	let zone = $state<string>(workout.pace_zone ?? '');
	let notes = $state<string>(workout.notes ?? '');
	let busy = $state(false);
	let error = $state<string | null>(null);

	const kindOptions: WorkoutKind[] = [
		'easy', 'long', 'recovery', 'tempo', 'interval', 'marathon_pace', 'race', 'rest'
	];

	async function save() {
		busy = true;
		error = null;
		try {
			const paceStart =
				paceMin != null ? paceMin * 60 + (paceSec ?? 0) : null;
			const paceEnd =
				paceEndMin != null ? paceEndMin * 60 + (paceEndSec ?? 0) : null;
			const isRest = kind === 'rest';
			const unstructuredKinds = ['easy', 'long', 'recovery', 'rest'] as const;
			const isUnstructured = (unstructuredKinds as readonly string[]).includes(kind);
			await updatePlanWorkout(workout.id, {
				kind,
				target_distance_m: isRest ? null : distanceKm != null ? distanceKm * 1000 : null,
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

<div class="backdrop" role="presentation" onclick={onClose}>
	<div
		class="drawer"
		role="dialog"
		aria-modal="true"
		aria-label="Edit workout"
		onclick={(e) => e.stopPropagation()}
	>
		<header>
			<span class="date">{workout.scheduled_date}</span>
			<button class="close" onclick={onClose} aria-label="Close">
				<span class="material-symbols">close</span>
			</button>
		</header>

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
				<span>Distance <span class="hint">km</span></span>
				<input type="number" min="0" step="0.1" bind:value={distanceKm} />
			</label>

			<fieldset>
				<legend>Target pace <span class="hint">per km</span></legend>
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
			<button class="btn-secondary" onclick={onClose} disabled={busy}>Cancel</button>
			<button class="btn-primary" onclick={save} disabled={busy}>
				{busy ? 'Saving…' : 'Save'}
			</button>
		</div>
	</div>
</div>

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.45);
		display: flex;
		justify-content: flex-end;
		z-index: 100;
	}
	.drawer {
		background: var(--color-bg);
		width: 24rem;
		max-width: 100vw;
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		overflow-y: auto;
	}
	header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-sm);
	}
	.date {
		font-size: 0.78rem;
		letter-spacing: 0.08em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	.close {
		background: none;
		border: none;
		cursor: pointer;
		color: var(--color-text-secondary);
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
