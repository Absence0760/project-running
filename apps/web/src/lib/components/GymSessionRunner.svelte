<script lang="ts">
	import type { RoutineStep } from '$lib/gym/gym_routine';
	import type { GymRoutineSummary } from '$lib/core/data';
	import { createGymWorkout, type GymSetInput } from '$lib/core/data';
	import {
		computeRoutineAdherence,
		type PlannedSetRef,
		type ActualSetRef,
	} from '$lib/gym/gym_adherence';
	import GymExecutionBand from './GymExecutionBand.svelte';
	import type { EnteredSet } from '$lib/gym/gym_session_types';
	import RestTimer from './RestTimer.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	interface Props {
		routine: GymRoutineSummary;
		steps: RoutineStep[];
		onfinish: (workoutId: string) => void;
		oncancel: () => void;
	}

	let { routine, steps, onfinish, oncancel }: Props = $props();

	type StepOutcome =
		| { kind: 'logged'; entered: EnteredSet }
		| { kind: 'skipped' };

	let currentIndex = $state(0);
	// Sparse per-step record of what the runner entered (or skipped). Indexed by
	// step position so a rewind can re-surface a prior edit.
	let outcomes = $state<(StepOutcome | undefined)[]>(steps.map(() => undefined));
	let resting = $state(false);
	let restSeconds = $state(0);
	let confirmingDiscard = $state(false);
	let saving = $state(false);
	let saveFailed = $state(false);

	const startedAt = new Date().toISOString();

	const currentStep = $derived(steps[currentIndex] as RoutineStep | undefined);
	const finished = $derived(currentIndex >= steps.length);

	function enteredFor(i: number): EnteredSet {
		const o = outcomes[i];
		if (o && o.kind === 'logged') return o.entered;
		return { reps: null, weightKg: null, rpe: null, durationS: null };
	}

	function advance() {
		const step = steps[currentIndex];
		if (step && step.restS != null && step.restS > 0 && currentIndex + 1 < steps.length) {
			restSeconds = step.restS;
			resting = true;
			return;
		}
		currentIndex += 1;
	}

	function onComplete(e: EnteredSet) {
		outcomes[currentIndex] = { kind: 'logged', entered: e };
		advance();
	}

	function onSkip() {
		outcomes[currentIndex] = { kind: 'skipped' };
		// A skipped set isn't performed, so its trailing rest doesn't apply —
		// go straight to the next step rather than through advance()'s rest timer.
		currentIndex += 1;
	}

	function onRewind() {
		if (currentIndex > 0) currentIndex -= 1;
	}

	function onRestDone() {
		resting = false;
		currentIndex += 1;
	}

	function onRestSkip() {
		resting = false;
		currentIndex += 1;
	}

	// Build the logged sets + the metadata trio, then persist. Adherence is by
	// (exerciseKey, setIndex) — never name spelling. Weights stay canonical kg.
	function buildSets(): GymSetInput[] {
		const out: GymSetInput[] = [];
		steps.forEach((step, i) => {
			const o = outcomes[i];
			if (!o || o.kind !== 'logged') return;
			const e = o.entered;
			if (e.reps == null && e.weightKg == null && e.durationS == null) return;
			out.push({
				exercise_name: step.exerciseName,
				reps: e.reps,
				weight_kg: e.weightKg,
				rpe: e.rpe,
				duration_s: e.durationS,
			});
		});
		return out;
	}

	function buildMetadata() {
		const planned: PlannedSetRef[] = steps.map((step) => ({
			exerciseKey: step.exerciseKey,
			setIndex: step.setIndex,
			setType: step.setType,
			targetRepsMin: step.targetRepsMin,
			targetRepsMax: step.targetRepsMax,
			targetWeightKg: step.targetWeightKg,
			targetDurationS: step.targetDurationS,
		}));
		const actual: ActualSetRef[] = [];
		steps.forEach((step, i) => {
			const o = outcomes[i];
			if (!o || o.kind !== 'logged') return;
			const e = o.entered;
			actual.push({
				exerciseKey: step.exerciseKey,
				setIndex: step.setIndex,
				reps: e.reps,
				weightKg: e.weightKg,
				durationS: e.durationS,
			});
		});
		const adherence = computeRoutineAdherence(planned, actual);
		const actualByKey = new Map(actual.map((a) => [`${a.exerciseKey} ${a.setIndex}`, a]));
		const plannedByKey = new Map(planned.map((p) => [`${p.exerciseKey} ${p.setIndex}`, p]));
		const stepResults = adherence.sets.map((s) => {
			const key = `${s.exerciseKey} ${s.setIndex}`;
			const p = plannedByKey.get(key);
			const a = actualByKey.get(key);
			return {
				exercise_key: s.exerciseKey,
				set_index: s.setIndex,
				status: s.status,
				reps_delta: s.repsDelta,
				weight_delta_kg: s.weightDeltaKg,
				target_reps_min: p?.targetRepsMin ?? null,
				target_reps_max: p?.targetRepsMax ?? null,
				target_weight_kg: p?.targetWeightKg ?? null,
				target_duration_s: p?.targetDurationS ?? null,
				actual_reps: a?.reps ?? null,
				actual_weight_kg: a?.weightKg ?? null,
				actual_duration_s: a?.durationS ?? null,
			};
		});
		return {
			routine_id: routine.id,
			gym_step_results: stepResults,
			gym_adherence: adherence.verdict,
		};
	}

	async function finish() {
		saving = true;
		saveFailed = false;
		try {
			const durationS = Math.max(1, Math.round((Date.now() - new Date(startedAt).getTime()) / 1000));
			const workout = await createGymWorkout({
				title: routine.title,
				started_at: startedAt,
				duration_s: durationS,
				sets: buildSets(),
				metadata: buildMetadata(),
			});
			onfinish(workout.id);
		} catch (e) {
			console.error('save guided session failed', e);
			saveFailed = true;
		} finally {
			saving = false;
		}
	}
</script>

<div class="runner" data-testid="gym-session-runner">
	{#if resting}
		<RestTimer seconds={restSeconds} ondone={onRestDone} onskip={onRestSkip} />
	{:else if !finished && currentStep}
		<GymExecutionBand
			step={currentStep}
			index={currentIndex}
			total={steps.length}
			entered={enteredFor(currentIndex)}
			{onComplete}
			{onSkip}
			{onRewind}
			onAbandon={() => (confirmingDiscard = true)}
		/>
	{:else}
		<div class="finish" data-testid="gym-session-finish">
			<span class="material-symbols finish-icon" aria-hidden="true">flag</span>
			<p class="finish-text">{t('gym.session.setProgress', { done: buildSets().length, total: steps.length })}</p>
			{#if saveFailed}
				<p class="save-failed" role="alert" data-testid="gym-session-save-failed">
					{t('gym.session.saveFailed')}
				</p>
			{/if}
			<div class="finish-actions">
				<button
					type="button"
					class="btn btn-secondary"
					onclick={() => (confirmingDiscard = true)}
					disabled={saving}
				>
					{t('gym.session.abandon')}
				</button>
				<button
					type="button"
					class="btn btn-primary"
					onclick={finish}
					disabled={saving}
					data-testid="gym-session-finish-save"
				>
					{t('gym.session.finish')}
				</button>
			</div>
		</div>
	{/if}
</div>

<ConfirmDialog
	open={confirmingDiscard}
	data-testid="gym-discard-dialog"
	title={t('gym.session.discardTitle')}
	message={t('gym.session.discardBody')}
	confirmLabel={t('gym.session.discardConfirm')}
	danger
	onconfirm={() => {
		confirmingDiscard = false;
		oncancel();
	}}
	oncancel={() => (confirmingDiscard = false)}
/>

<style>
	.runner {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.finish {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-xl) var(--space-lg);
		text-align: center;
	}
	.finish-icon {
		font-size: 2.5rem;
		color: var(--color-primary);
	}
	.finish-text {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.save-failed {
		margin: 0;
		color: var(--color-danger);
		font-size: 0.9rem;
	}
	.finish-actions {
		display: flex;
		gap: var(--space-sm);
	}
</style>
