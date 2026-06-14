<script lang="ts">
	import { untrack } from 'svelte';
	import { markWorkoutCompleted, markWorkoutSkipped, updatePlanWorkout } from '$lib/core/data';
	import {
		isWorkoutCompleted,
		isWorkoutSkipped,
		type WorkoutKind,
		type WorkoutStructure
	} from '$lib/training/training';
	import { workoutKindLabel } from '$lib/training/workout_labels';
	import { getUnit } from '$lib/format/units.svelte';
	import { paceParts } from '$lib/format/pace_format';
	import { m as t } from '$lib/i18n/store.svelte';
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
			? paceParts(paceFromCanonical(workout.target_pace_sec_per_km)).minutes
			: null
	));
	let paceSec = $state<number | null>(untrack(() =>
		workout.target_pace_sec_per_km != null
			? paceParts(paceFromCanonical(workout.target_pace_sec_per_km)).seconds
			: null
	));
	let paceEndMin = $state<number | null>(untrack(() =>
		workout.target_pace_end_sec_per_km != null
			? paceParts(paceFromCanonical(workout.target_pace_end_sec_per_km)).minutes
			: null
	));
	let paceEndSec = $state<number | null>(untrack(() =>
		workout.target_pace_end_sec_per_km != null
			? paceParts(paceFromCanonical(workout.target_pace_end_sec_per_km)).seconds
			: null
	));
	let toleranceSec = $state<number | null>(
		untrack(() => workout.target_pace_tolerance_sec)
	);
	let zone = $state<string>(untrack(() => workout.pace_zone ?? ''));
	let notes = $state<string>(untrack(() => workout.notes ?? ''));

	const initialStructure = untrack(
		() => (workout.structure as WorkoutStructure | null) ?? null
	);

	function metresToUnit(m: number): number {
		return +(m / distanceDivisor).toFixed(2);
	}
	function unitToMetres(v: number): number {
		return v * distanceDivisor;
	}

	let mode = $state<'repeats' | 'steady'>(
		untrack(() => {
			if (initialStructure?.repeats) return 'repeats';
			if (initialStructure?.steady) return 'steady';
			return workout.kind === 'interval' ? 'repeats' : 'steady';
		})
	);
	let warmupDistance = $state<number | null>(
		untrack(() =>
			initialStructure?.warmup ? metresToUnit(initialStructure.warmup.distance_m ?? 0) : 2
		)
	);
	let cooldownDistance = $state<number | null>(
		untrack(() =>
			initialStructure?.cooldown
				? metresToUnit(initialStructure.cooldown.distance_m ?? 0)
				: 2
		)
	);
	let repeatsCount = $state<number | null>(
		untrack(() => initialStructure?.repeats?.count ?? 5)
	);
	let repeatsDistance = $state<number | null>(
		untrack(() =>
			initialStructure?.repeats
				? metresToUnit(initialStructure.repeats.distance_m ?? 0)
				: 1
		)
	);
	let repeatsPaceMin = $state<number | null>(
		untrack(() =>
			initialStructure?.repeats
				? paceParts(paceFromCanonical(initialStructure.repeats.pace_sec_per_km)).minutes
				: null
		)
	);
	let repeatsPaceSec = $state<number | null>(
		untrack(() =>
			initialStructure?.repeats
				? paceParts(paceFromCanonical(initialStructure.repeats.pace_sec_per_km)).seconds
				: null
		)
	);
	let recoveryDistance = $state<number | null>(
		untrack(() =>
			initialStructure?.repeats
				? metresToUnit(initialStructure.repeats.recovery_distance_m ?? 0)
				: 0.4
		)
	);
	let recoveryPace = $state<'easy' | 'jog' | 'walk'>(
		untrack(() => initialStructure?.repeats?.recovery_pace ?? 'jog')
	);
	let steadyDistance = $state<number | null>(
		untrack(() =>
			initialStructure?.steady
				? metresToUnit(initialStructure.steady.distance_m ?? 0)
				: null
		)
	);
	let steadyPaceMin = $state<number | null>(
		untrack(() =>
			initialStructure?.steady
				? paceParts(paceFromCanonical(initialStructure.steady.pace_sec_per_km)).minutes
				: null
		)
	);
	let steadyPaceSec = $state<number | null>(
		untrack(() =>
			initialStructure?.steady
				? paceParts(paceFromCanonical(initialStructure.steady.pace_sec_per_km)).seconds
				: null
		)
	);

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
	const wasSkipped = $derived(isWorkoutSkipped(workout));
	const hasLinkedRun = $derived(workout.completed_run_id != null);
	const showStructure = $derived(
		!(['easy', 'long', 'recovery', 'rest'] as const).includes(
			kind as 'easy' | 'long' | 'recovery' | 'rest'
		)
	);

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
			error = e instanceof Error ? e.message : t('workoutEditor.updateFailed');
		} finally {
			busy = false;
		}
	}

	async function toggleSkipped() {
		busy = true;
		error = null;
		try {
			// Skipping clears any manual completion server-side; un-skipping
			// just drops the flag and leaves the workout as a plain to-do.
			await markWorkoutSkipped(workout.id, !wasSkipped);
			onSaved();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : t('workoutEditor.updateFailed');
		} finally {
			busy = false;
		}
	}

	function buildStructure(): WorkoutStructure | null {
		const next: WorkoutStructure = {};
		if (warmupDistance != null && warmupDistance > 0) {
			next.warmup = { distance_m: unitToMetres(warmupDistance), pace: 'easy' };
		}
		if (mode === 'repeats') {
			const repPaceUnit =
				repeatsPaceMin != null ? repeatsPaceMin * 60 + (repeatsPaceSec ?? 0) : null;
			if (
				repeatsCount != null &&
				repeatsCount > 0 &&
				repeatsDistance != null &&
				repeatsDistance > 0 &&
				repPaceUnit != null &&
				repPaceUnit > 0
			) {
				next.repeats = {
					count: Math.round(repeatsCount),
					distance_m: unitToMetres(repeatsDistance),
					pace_sec_per_km: repPaceUnit / paceFactor,
					recovery_distance_m:
						recoveryDistance != null ? unitToMetres(recoveryDistance) : 0,
					recovery_pace: recoveryPace
				};
			}
		} else {
			const steadyPaceUnit =
				steadyPaceMin != null ? steadyPaceMin * 60 + (steadyPaceSec ?? 0) : null;
			if (steadyDistance != null && steadyDistance > 0 && steadyPaceUnit != null) {
				next.steady = {
					distance_m: unitToMetres(steadyDistance),
					pace_sec_per_km: steadyPaceUnit / paceFactor
				};
			}
		}
		if (cooldownDistance != null && cooldownDistance > 0) {
			next.cooldown = { distance_m: unitToMetres(cooldownDistance), pace: 'easy' };
		}
		const hasAny = next.warmup || next.repeats || next.steady || next.cooldown;
		return hasAny ? next : null;
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
			const nextStructure = isUnstructured ? null : buildStructure();
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
				structure: isUnstructured
					? null
					: (nextStructure as unknown as Record<string, unknown> | null),
			});
			onSaved();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : t('workoutEditor.saveFailed');
		} finally {
			busy = false;
		}
	}
</script>

<Modal
	open={true}
	title={t('workoutEditor.title', { date: workout.scheduled_date ?? '' })}
	onclose={onClose}
>
	<div class="editor-form">
		<label>
			<span>{t('workoutEditor.kind')}</span>
			<select bind:value={kind}>
				{#each kindOptions as k}
					<option value={k}>{workoutKindLabel(k)}</option>
				{/each}
			</select>
		</label>

		{#if kind !== 'rest'}
			<label>
				<span>{t('workoutEditor.distance')} <span class="hint">{unit}</span></span>
				<input type="number" min="0" step="0.1" bind:value={distance} />
			</label>

			<fieldset>
				<legend>{t('workoutEditor.targetPace')} <span class="hint">{t('workoutEditor.perUnit', { unit })}</span></legend>
				<div class="pace-row">
					<input type="number" min="0" max="59" bind:value={paceMin} placeholder={t('workoutEditor.min')} />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={paceSec} placeholder={t('workoutEditor.sec')} />
					<span class="arrow">→</span>
					<input
						type="number"
						min="0"
						max="59"
						bind:value={paceEndMin}
						placeholder={t('workoutEditor.min')}
					/>
					<span>:</span>
					<input
						type="number"
						min="0"
						max="59"
						bind:value={paceEndSec}
						placeholder={t('workoutEditor.sec')}
					/>
				</div>
				<p class="hint">
					{t('workoutEditor.paceEndHint')}
				</p>
			</fieldset>

			<label>
				<span>{t('workoutEditor.paceTolerance')} <span class="hint">{t('workoutEditor.plusMinusSeconds')}</span></span>
				<input type="number" min="0" max="60" bind:value={toleranceSec} />
			</label>

			<label>
				<span>{t('workoutEditor.zoneLabel')} <span class="hint">{t('workoutEditor.zoneHint')}</span></span>
				<input type="text" bind:value={zone} maxlength="16" />
			</label>
		{/if}

		{#if showStructure}
			<fieldset class="structure">
				<legend>{t('workoutEditor.structure')}</legend>

				<label class="warmup">
					<span>{t('workoutEditor.warmup')} <span class="hint">{unit}</span></span>
					<input
						type="number"
						min="0"
						step="0.1"
						bind:value={warmupDistance}
					/>
				</label>

				<div class="mode-toggle" role="radiogroup" aria-label={t('workoutEditor.bodyOfWorkout')}>
					<label class="mode-opt">
						<input
							type="radio"
							name="structure-mode"
							value="repeats"
							checked={mode === 'repeats'}
							onchange={() => (mode = 'repeats')}
						/>
						<span>{t('workoutEditor.repeats')}</span>
					</label>
					<label class="mode-opt">
						<input
							type="radio"
							name="structure-mode"
							value="steady"
							checked={mode === 'steady'}
							onchange={() => (mode = 'steady')}
						/>
						<span>{t('workoutEditor.steady')}</span>
					</label>
				</div>

				{#if mode === 'repeats'}
					<fieldset class="repeats">
						<legend>{t('workoutEditor.repeats')}</legend>
						<label>
							<span>{t('workoutEditor.count')}</span>
							<input
								type="number"
								min="1"
								max="40"
								step="1"
								bind:value={repeatsCount}
							/>
						</label>
						<label>
							<span>{t('workoutEditor.repDistance')} <span class="hint">{unit}</span></span>
							<input
								type="number"
								min="0"
								step="0.1"
								bind:value={repeatsDistance}
							/>
						</label>
						<fieldset>
							<legend>{t('workoutEditor.repPace')} <span class="hint">{t('workoutEditor.perUnit', { unit })}</span></legend>
							<div class="pace-row">
								<input
									type="number"
									min="0"
									max="59"
									bind:value={repeatsPaceMin}
									placeholder={t('workoutEditor.min')}
								/>
								<span>:</span>
								<input
									type="number"
									min="0"
									max="59"
									bind:value={repeatsPaceSec}
									placeholder={t('workoutEditor.sec')}
								/>
							</div>
						</fieldset>
						<label class="recovery">
							<span>{t('workoutEditor.recovery')} <span class="hint">{unit}</span></span>
							<input
								type="number"
								min="0"
								step="0.05"
								bind:value={recoveryDistance}
							/>
						</label>
						<label>
							<span>{t('workoutEditor.recoveryPace')}</span>
							<select bind:value={recoveryPace}>
								<option value="jog">{t('workoutEditor.jog')}</option>
								<option value="easy">{t('workoutEditor.easy')}</option>
							</select>
						</label>
					</fieldset>
				{:else}
					<fieldset class="steady">
						<legend>{t('workoutEditor.steady')}</legend>
						<label>
							<span>{t('workoutEditor.distance')} <span class="hint">{unit}</span></span>
							<input
								type="number"
								min="0"
								step="0.1"
								bind:value={steadyDistance}
							/>
						</label>
						<fieldset>
							<legend>{t('workoutEditor.pace')} <span class="hint">{t('workoutEditor.perUnit', { unit })}</span></legend>
							<div class="pace-row">
								<input
									type="number"
									min="0"
									max="59"
									bind:value={steadyPaceMin}
									placeholder={t('workoutEditor.min')}
								/>
								<span>:</span>
								<input
									type="number"
									min="0"
									max="59"
									bind:value={steadyPaceSec}
									placeholder={t('workoutEditor.sec')}
								/>
							</div>
						</fieldset>
					</fieldset>
				{/if}

				<label class="cooldown">
					<span>{t('workoutEditor.cooldown')} <span class="hint">{unit}</span></span>
					<input
						type="number"
						min="0"
						step="0.1"
						bind:value={cooldownDistance}
					/>
				</label>
			</fieldset>
		{/if}

		<label>
			<span>{t('workoutEditor.notes')}</span>
			<textarea rows="3" bind:value={notes} maxlength="500"></textarea>
		</label>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		<div class="actions">
			<button class="btn btn-secondary" onclick={onClose} disabled={busy}>{t('workoutEditor.cancel')}</button>
			<button
				class="btn btn-outline"
				onclick={toggleCompleted}
				disabled={busy || hasLinkedRun}
				title={hasLinkedRun
					? t('workoutEditor.linkedRunTitle')
					: wasCompleted
						? t('workoutEditor.clearManualTitle')
						: t('workoutEditor.markDoneTitle')}
			>
				{wasCompleted ? t('workoutEditor.markNotDone') : t('workoutEditor.markAsDone')}
			</button>
			<button
				class="btn btn-outline"
				onclick={toggleSkipped}
				disabled={busy || hasLinkedRun}
				title={hasLinkedRun
					? t('workoutEditor.skipLinkedRunTitle')
					: wasSkipped
						? t('workoutEditor.unskipTitle')
						: t('workoutEditor.skipTitle')}
			>
				{wasSkipped ? t('workoutEditor.unskip') : t('workoutEditor.skip')}
			</button>
			<button class="btn btn-primary" onclick={save} disabled={busy}>
				{busy ? t('workoutEditor.saving') : t('workoutEditor.save')}
			</button>
		</div>
	</div>
</Modal>

<style>
	/* The shared .editor-form layer (app.css) supplies the field chrome,
	   label / legend text, fieldset card, focus ring, actions row and error
	   banner. The layer styles fieldsets as cards but not as flex columns,
	   so the column layout for the bare fieldsets stays here. */
	.editor-form fieldset {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
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
	fieldset.structure {
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
	}
	fieldset.repeats,
	fieldset.steady {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.55rem 0.85rem;
	}
	fieldset.repeats > fieldset,
	fieldset.steady > fieldset {
		grid-column: 1 / -1;
	}
	.mode-toggle {
		display: flex;
		gap: 0.55rem;
	}
	.mode-opt {
		display: inline-flex;
		flex-direction: row;
		align-items: center;
		gap: 0.3rem;
		font-weight: 500;
		font-size: 0.88rem;
	}
</style>
