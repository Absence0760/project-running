<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { beforeNavigate, goto } from '$app/navigation';
	import type { RoutineStep } from '$lib/gym/gym_routine';
	import type { GymRoutineSummary, GymWorkout } from '$lib/core/data';
	import {
		createGymWorkout,
		deleteGymWorkout,
		updateGymWorkout,
		type GymSetInput,
	} from '$lib/core/data';
	import {
		computeRoutineAdherence,
		refKey,
		type PlannedSetRef,
		type ActualSetRef,
	} from '$lib/gym/gym_adherence';
	import GymExecutionBand from './GymExecutionBand.svelte';
	import type { EnteredSet, StepOutcome } from '$lib/gym/gym_session_types';
	import { draftMetadata, restoreSessionDraft, resumedStartedAt } from '$lib/gym/gym_session_draft';
	import RestTimer from './RestTimer.svelte';
	import Modal from './Modal.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	interface Props {
		routine: GymRoutineSummary;
		steps: RoutineStep[];
		/// An in-flight draft row for this routine, if one exists — the runner
		/// replays its snapshot instead of starting fresh, and every later
		/// durable save lands on that same row rather than forking a second one.
		draft?: GymWorkout | null;
		onfinish: (workoutId: string) => void;
		oncancel: () => void;
	}

	let { routine, steps, draft = null, onfinish, oncancel }: Props = $props();

	const restored = untrack(() =>
		draft ? restoreSessionDraft(draft.metadata, steps.length) : null,
	);

	let currentIndex = $state(restored?.currentIndex ?? 0);
	// Sparse per-step record of what the runner entered (or skipped). Indexed by
	// step position so a rewind can re-surface a prior edit.
	let outcomes = $state<(StepOutcome | undefined)[]>(
		untrack(() => restored?.outcomes ?? steps.map(() => undefined)),
	);
	let resting = $state(false);
	let restSeconds = $state(0);
	let leavePrompt = $state(false);
	let saving = $state(false);
	let saveFailed = $state(false);
	let draftId: string | null = untrack(() => draft?.id ?? null);
	let leaveTarget: string | null = null;
	let abandoned = false;
	let departing = false;

	// Resuming continues from the last durable save rather than billing the time
	// the tab was gone, matching resumeSession's elapsed semantics on the run side.
	let startedAt = untrack(() =>
		draft ? resumedStartedAt(draft.duration_s, Date.now()) : new Date().toISOString(),
	);

	const currentStep = $derived(steps[currentIndex] as RoutineStep | undefined);
	const finished = $derived(currentIndex >= steps.length);

	function enteredFor(i: number): EnteredSet {
		const o = outcomes[i];
		if (o && o.kind === 'logged') return o.entered;
		return { reps: null, weightKg: null, rpe: null, durationS: null, distanceM: null };
	}

	function enteredSomething(e: EnteredSet): boolean {
		return e.reps != null || e.weightKg != null || e.durationS != null || e.distanceM != null;
	}

	// Count every set the runner actually logged a value for, including a
	// distance-only set (which carries no gym_sets column, so buildSets — the
	// gym_sets writer — legitimately drops it, but it is still a completed set).
	const loggedCount = $derived(
		outcomes.filter((o) => o?.kind === 'logged' && enteredSomething(o.entered)).length,
	);

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
			// distance has no gym_sets column — a distance-only set is graded via
			// the metadata step-results below, not persisted as a flat set row.
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
		const planned: PlannedSetRef[] = steps.map((step, i) => ({
			exerciseKey: step.exerciseKey,
			stepIndex: i,
			setIndex: step.setIndex,
			setType: step.setType,
			targetRepsMin: step.targetRepsMin,
			targetRepsMax: step.targetRepsMax,
			targetWeightKg: step.targetWeightKg,
			targetDurationS: step.targetDurationS,
			targetDistanceM: step.targetDistanceM,
		}));
		const actual: ActualSetRef[] = [];
		steps.forEach((step, i) => {
			const o = outcomes[i];
			if (!o || o.kind !== 'logged') return;
			const e = o.entered;
			actual.push({
				exerciseKey: step.exerciseKey,
				stepIndex: i,
				setIndex: step.setIndex,
				reps: e.reps,
				weightKg: e.weightKg,
				durationS: e.durationS,
				distanceM: e.distanceM,
			});
		});
		const adherence = computeRoutineAdherence(planned, actual);
		const actualByKey = new Map(actual.map((a) => [refKey(a.exerciseKey, a.stepIndex), a]));
		const plannedByKey = new Map(planned.map((p) => [refKey(p.exerciseKey, p.stepIndex), p]));
		const stepResults = adherence.sets.map((s) => {
			const key = refKey(s.exerciseKey, s.stepIndex);
			const p = plannedByKey.get(key);
			const a = actualByKey.get(key);
			return {
				exercise_key: s.exerciseKey,
				step_index: s.stepIndex,
				set_index: s.setIndex,
				status: s.status,
				reps_delta: s.repsDelta,
				weight_delta_kg: s.weightDeltaKg,
				target_reps_min: p?.targetRepsMin ?? null,
				target_reps_max: p?.targetRepsMax ?? null,
				target_weight_kg: p?.targetWeightKg ?? null,
				target_duration_s: p?.targetDurationS ?? null,
				target_distance_m: p?.targetDistanceM ?? null,
				actual_reps: a?.reps ?? null,
				actual_weight_kg: a?.weightKg ?? null,
				actual_duration_s: a?.durationS ?? null,
				actual_distance_m: a?.distanceM ?? null,
			};
		});
		return {
			routine_id: routine.id,
			gym_step_results: stepResults,
			gym_adherence: adherence.verdict,
		};
	}

	function durationS(): number {
		return Math.max(1, Math.round((Date.now() - new Date(startedAt).getTime()) / 1000));
	}

	// Persist the session so far onto one draft row. Best-effort (L4): a failed
	// write leaves the in-memory state intact for the next tick, never
	// interrupts the runner. The snapshot rides the row's metadata rather than
	// a second store, so a force-kill is as resumable as a graceful leave.
	async function durableSave(): Promise<void> {
		if (abandoned || saving) return;
		const sets = buildSets();
		if (sets.length === 0 && draftId === null) return;
		const metadata = draftMetadata(routine.id, outcomes, currentIndex, new Date().toISOString());
		try {
			if (draftId === null) {
				const created = await createGymWorkout({
					title: routine.title,
					started_at: startedAt,
					duration_s: durationS(),
					sets,
					metadata,
				});
				draftId = created.id;
			} else {
				await updateGymWorkout(draftId, { duration_s: durationS(), metadata }, sets);
			}
		} catch (e) {
			console.error('gym session durable save failed', e);
		}
	}

	onMount(() => {
		const timer = setInterval(() => void durableSave(), 10_000);
		return () => clearInterval(timer);
	});

	// The session's leave outcome is ternary and non-destructive, so it takes
	// its own three-way prompt rather than the binary UnsavedChangesGuard —
	// the same split decisions.md § 483 made on mobile against DiscardGuard.
	beforeNavigate((nav) => {
		if (abandoned || departing || saving || leaveTarget !== null) return;
		if (buildSets().length === 0 && draftId === null) return;
		nav.cancel();
		// A 'leave' navigation is the browser's own beforeunload; the tab may go
		// anyway, so persist first and let the native prompt carry the choice.
		if (nav.type === 'leave') {
			void durableSave();
			return;
		}
		leaveTarget = nav.to?.url.href ?? null;
		leavePrompt = true;
	});

	function dismissLeave() {
		leavePrompt = false;
		leaveTarget = null;
	}

	async function departTo(href: string | null): Promise<void> {
		leavePrompt = false;
		const target = href;
		leaveTarget = null;
		// The departure is itself a navigation, so the guard has to stand down
		// or it would re-prompt against the choice just made.
		departing = true;
		if (target) await goto(target);
		else oncancel();
	}

	async function leaveKeepingDraft() {
		const target = leaveTarget;
		await durableSave();
		await departTo(target);
	}

	async function discardSession() {
		const target = leaveTarget;
		abandoned = true;
		const id = draftId;
		draftId = null;
		if (id) {
			try {
				await deleteGymWorkout(id);
			} catch (e) {
				console.error('gym session draft discard failed', e);
			}
		}
		await departTo(target);
	}

	async function finish() {
		saving = true;
		saveFailed = false;
		try {
			// Finish replaces the whole bag with the execution trio, which is what
			// clears the draft marker — the row stops being resumable because it
			// is no longer in flight.
			const metadata = buildMetadata();
			const sets = buildSets();
			let id = draftId;
			if (id === null) {
				const workout = await createGymWorkout({
					title: routine.title,
					started_at: startedAt,
					duration_s: durationS(),
					sets,
					metadata,
				});
				id = workout.id;
				draftId = id;
			} else {
				await updateGymWorkout(id, { duration_s: durationS(), metadata }, sets);
			}
			abandoned = true;
			onfinish(id);
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
			onAbandon={() => (leavePrompt = true)}
		/>
	{:else}
		<div class="finish" data-testid="gym-session-finish">
			<span class="material-symbols finish-icon" aria-hidden="true">flag</span>
			<p class="finish-text">{t('gym.session.setProgress', { done: loggedCount, total: steps.length })}</p>
			{#if saveFailed}
				<p class="save-failed" role="alert" data-testid="gym-session-save-failed">
					{t('gym.session.saveFailed')}
				</p>
			{/if}
			<div class="finish-actions">
				<button
					type="button"
					class="btn btn-secondary"
					onclick={() => (leavePrompt = true)}
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

<Modal
	open={leavePrompt}
	narrow
	data-testid="gym-leave-dialog"
	title={t('gym.session.leaveTitle')}
	onclose={dismissLeave}
	bodyClass="leave-body"
>
	<p class="leave-message">{t('gym.session.leaveBody')}</p>
	<div class="leave-actions">
		<button type="button" class="btn btn-primary" onclick={dismissLeave}>
			{t('gym.session.leaveKeepGoing')}
		</button>
		<button
			type="button"
			class="btn btn-secondary"
			onclick={leaveKeepingDraft}
			data-testid="gym-leave-keep-draft"
		>
			{t('gym.session.leaveKeepDraft')}
		</button>
		<button
			type="button"
			class="btn btn-danger"
			onclick={discardSession}
			data-testid="gym-leave-discard"
		>
			{t('gym.session.discardConfirm')}
		</button>
	</div>
</Modal>

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
	.leave-message {
		margin: 0 0 var(--space-md);
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.leave-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
</style>
