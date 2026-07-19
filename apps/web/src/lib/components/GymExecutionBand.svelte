<script lang="ts">
	import type { RoutineStep } from '$lib/gym/gym_routine';
	import type { EnteredSet } from '$lib/gym/gym_session_types';
	import {
		idleStopwatch,
		isRunning,
		elapsedSeconds,
		startStopwatch,
		stopStopwatch,
		parseDurationInput,
		type StopwatchState,
	} from '$lib/gym/gym_stopwatch';
	import { weightInputValue, parseWeight, weightUnitLabel } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	interface Props {
		step: RoutineStep;
		index: number;
		total: number;
		entered: EnteredSet;
		onComplete: (e: EnteredSet) => void;
		onSkip: () => void;
		onRewind: () => void;
		onAbandon: () => void;
	}

	let { step, index, total, entered, onComplete, onSkip, onRewind, onAbandon }: Props = $props();

	let repsStr = $state('');
	let weightStr = $state('');
	let rpeStr = $state('');
	let distanceStr = $state('');
	// The ACTUAL held time for a time-modality set, in seconds. Never prefilled
	// from the target — an untracked hold must log null, not a fake full hit.
	let durationStr = $state('');
	let stopwatch = $state<StopwatchState>(idleStopwatch());
	let nowMs = $state(0);

	const isTimed = $derived(step.targetDurationS != null);
	const stopwatchRunning = $derived(isRunning(stopwatch));

	// Re-seed the inputs whenever we move to a different set (the band is reused
	// across steps). `entered` carries a prior in-progress edit if the user
	// rewound to this set; otherwise it prefills from the step's targets.
	$effect(() => {
		void index;
		repsStr = entered.reps != null ? String(entered.reps) : targetRepsValue();
		weightStr =
			entered.weightKg != null
				? weightInputValue(entered.weightKg)
				: step.targetWeightKg != null
					? weightInputValue(step.targetWeightKg)
					: '';
		rpeStr = entered.rpe != null ? String(entered.rpe) : step.targetRpe != null ? String(step.targetRpe) : '';
		distanceStr =
			entered.distanceM != null
				? String(entered.distanceM)
				: step.targetDistanceM != null
					? String(step.targetDistanceM)
					: '';
		durationStr = entered.durationS != null ? String(entered.durationS) : '';
		stopwatch = idleStopwatch();
	});

	// Live display tick while the stopwatch runs. The value is recomputed from the
	// wall-clock anchor each tick (not accumulated per tick), so a throttled or
	// backgrounded tab reports the true elapsed once it resumes.
	$effect(() => {
		if (!stopwatchRunning) return;
		const id = setInterval(() => {
			nowMs = Date.now();
			durationStr = String(elapsedSeconds(stopwatch, nowMs));
		}, 250);
		return () => clearInterval(id);
	});

	function toggleStopwatch() {
		const now = Date.now();
		if (stopwatchRunning) {
			stopwatch = stopStopwatch(stopwatch, now);
			durationStr = String(elapsedSeconds(stopwatch, now));
		} else {
			stopwatch = startStopwatch(stopwatch, now);
			nowMs = now;
		}
	}

	function targetRepsValue(): string {
		if (step.targetRepsMin == null) return '';
		return String(step.targetRepsMin);
	}

	const hasTarget = $derived(
		step.targetRepsMin != null ||
			step.targetWeightKg != null ||
			step.targetDurationS != null ||
			step.targetDistanceM != null,
	);

	function targetLabel(): string {
		if (!hasTarget) return t('gym.session.noTarget');
		const parts: string[] = [];
		if (step.targetRepsMin != null) {
			parts.push(
				step.targetRepsMax != null && step.targetRepsMax !== step.targetRepsMin
					? `${step.targetRepsMin}–${step.targetRepsMax}`
					: String(step.targetRepsMin),
			);
		}
		if (step.targetWeightKg != null) {
			parts.push(formatTargetWeight(step.targetWeightKg));
		}
		const repWeight = parts.join(' × ');
		const extras: string[] = [];
		if (step.targetDurationS != null) {
			extras.push(t('gym.durationValue', { seconds: step.targetDurationS }));
		}
		if (step.targetDistanceM != null) {
			extras.push(t('gym.distanceValue', { metres: step.targetDistanceM }));
		}
		const tail = extras.join(' · ');
		if (!tail) return repWeight;
		return repWeight ? `${repWeight} · ${tail}` : tail;
	}

	function formatTargetWeight(kg: number): string {
		return `${weightInputValue(kg)} ${weightUnitLabel()}`;
	}

	function currentEntered(): EnteredSet {
		// A `<input type="number" bind:value>` coerces its bound value to a
		// `number` the moment the user edits it, even though these fields are
		// declared as strings — so guard before any string op or `.trim()` throws
		// uncaught and Complete-set silently does nothing (the weight field already
		// routes through `parseWeight`, which coerces; reps + rpe must too).
		const repsRaw = typeof repsStr === 'number' ? String(repsStr) : repsStr;
		const rpeRaw = typeof rpeStr === 'number' ? String(rpeStr) : rpeStr;
		const distanceRaw = typeof distanceStr === 'number' ? String(distanceStr) : distanceStr;
		const reps = repsRaw.trim() === '' ? null : parseInt(repsRaw, 10);
		const weightKg = parseWeight(weightStr);
		const rpe = rpeRaw.trim() === '' ? null : parseFloat(rpeRaw);
		const distanceM =
			step.targetDistanceM == null || distanceRaw.trim() === '' ? null : parseFloat(distanceRaw);
		// If the stopwatch is still running when Complete is tapped, capture the
		// live elapsed rather than the last committed tick.
		const durationS = isTimed
			? stopwatchRunning
				? elapsedSeconds(stopwatch, Date.now())
				: parseDurationInput(durationStr)
			: null;
		return {
			reps: reps != null && Number.isFinite(reps) ? reps : null,
			weightKg,
			rpe: rpe != null && Number.isFinite(rpe) ? rpe : null,
			durationS,
			distanceM: distanceM != null && Number.isFinite(distanceM) ? distanceM : null,
		};
	}

	// reps/load pip: green when the entered reps + (if a weight target) the
	// entered weight reach their targets; amber when logged but under; grey when
	// nothing entered yet. Glyph + colour, never colour alone.
	const pip = $derived.by((): { state: 'hit' | 'under' | 'pending'; icon: string } => {
		const e = currentEntered();
		const loggedReps = e.reps != null;
		const loggedWeight = e.weightKg != null;
		const loggedDuration = step.targetDurationS != null && e.durationS != null;
		const loggedDistance = step.targetDistanceM != null && e.distanceM != null;
		if (!loggedReps && !loggedWeight && !loggedDuration && !loggedDistance) {
			return { state: 'pending', icon: 'radio_button_unchecked' };
		}
		const repsOk = step.targetRepsMin == null || (e.reps != null && e.reps >= step.targetRepsMin);
		const weightOk =
			step.targetWeightKg == null || (e.weightKg != null && e.weightKg >= step.targetWeightKg);
		const durationOk =
			step.targetDurationS == null || (e.durationS != null && e.durationS >= step.targetDurationS);
		const distanceOk =
			step.targetDistanceM == null || (e.distanceM != null && e.distanceM >= step.targetDistanceM);
		return repsOk && weightOk && durationOk && distanceOk
			? { state: 'hit', icon: 'check_circle' }
			: { state: 'under', icon: 'error' };
	});
</script>

<div class="band" data-testid="gym-exec-band">
	<header class="band-head">
		<div class="band-title">
			<h2>{step.exerciseName}</h2>
			<p class="set-count">{t('gym.session.step', { exercise: step.exerciseName, set: index + 1, total })}</p>
		</div>
		<div class="target">
			<span class="target-label section-label">{t('gym.session.target')}</span>
			<span class="target-value" class:no-target={!hasTarget}>{targetLabel()}</span>
		</div>
		<span
			class="pip pip-{pip.state}"
			data-testid="gym-pip"
			data-pip-state={pip.state}
			aria-label={t(
				pip.state === 'hit'
					? 'gym.review.status.hit'
					: pip.state === 'under'
						? 'gym.review.status.partial'
						: 'gym.session.noTarget',
			)}
		>
			<span class="material-symbols" aria-hidden="true">{pip.icon}</span>
		</span>
	</header>

	{#if isTimed}
		<div class="timed" data-testid="gym-set-timed">
			<label class="field">
				<span class="field-label section-label">{t('gym.session.holdSeconds')}</span>
				<input
					type="number"
					inputmode="numeric"
					min="0"
					bind:value={durationStr}
					readonly={stopwatchRunning}
					data-testid="gym-set-duration"
				/>
			</label>
			<button
				type="button"
				class="btn btn-secondary btn-sm stopwatch"
				class:running={stopwatchRunning}
				onclick={toggleStopwatch}
				data-testid="gym-set-stopwatch"
				aria-pressed={stopwatchRunning}
			>
				<span class="material-symbols" aria-hidden="true">{stopwatchRunning ? 'stop' : 'timer'}</span>
				{stopwatchRunning ? t('gym.session.stopHold') : t('gym.session.startHold')}
			</button>
		</div>
	{/if}

	<div class="inputs" class:has-distance={step.targetDistanceM != null}>

		<label class="field">
			<span class="field-label section-label">{t('gym.reps')}</span>
			<input
				type="number"
				inputmode="numeric"
				min="0"
				bind:value={repsStr}
				data-testid="gym-set-reps"
			/>
		</label>
		<label class="field">
			<span class="field-label section-label">{t('gym.weightUnit', { unit: weightUnitLabel() })}</span>
			<input
				type="number"
				inputmode="decimal"
				min="0"
				step="0.5"
				bind:value={weightStr}
				data-testid="gym-set-weight"
			/>
		</label>
		<label class="field">
			<span class="field-label section-label">{t('gym.rpe')}</span>
			<input
				type="number"
				inputmode="decimal"
				min="0"
				max="10"
				step="0.5"
				bind:value={rpeStr}
				data-testid="gym-set-rpe"
			/>
		</label>
		{#if step.targetDistanceM != null}
			<label class="field">
				<span class="field-label section-label">{t('gym.distanceUnit')}</span>
				<input
					type="number"
					inputmode="decimal"
					min="0"
					step="1"
					bind:value={distanceStr}
					data-testid="gym-set-distance"
				/>
			</label>
		{/if}
	</div>

	<div class="actions">
		<button
			type="button"
			class="btn btn-secondary btn-sm"
			onclick={onRewind}
			disabled={index === 0}
			data-testid="gym-rewind"
		>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{t('gym.session.rewind')}
		</button>
		<button type="button" class="btn btn-secondary btn-sm" onclick={onSkip} data-testid="gym-step-skip">
			{t('gym.session.skipSet')}
		</button>
		<button type="button" class="btn btn-danger btn-sm" onclick={onAbandon} data-testid="gym-session-discard">
			{t('gym.session.abandon')}
		</button>
		<button
			type="button"
			class="btn btn-primary btn-sm complete"
			onclick={() => onComplete(currentEntered())}
			data-testid="gym-step-complete"
		>
			<span class="material-symbols" aria-hidden="true">check</span>
			{t('gym.session.complete')}
		</button>
	</div>
</div>

<style>
	.band {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.band-head {
		display: flex;
		align-items: flex-start;
		gap: var(--space-md);
	}
	.band-title {
		min-width: 0;
		flex: 1 1 auto;
	}
	.band-title h2 {
		margin: 0;
		font-size: 1.3rem;
		font-weight: 700;
	}
	.set-count {
		margin: var(--space-2xs) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.target {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-2xs);
		text-align: end;
	}
	.target-label {
		color: var(--color-text-tertiary);
	}
	.target-value {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.target-value.no-target {
		color: var(--color-text-tertiary);
		font-weight: 400;
		font-style: italic;
	}
	.pip {
		flex-shrink: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
	}
	.pip .material-symbols {
		font-size: 1.6rem;
	}
	.pip-hit {
		color: var(--color-success);
	}
	.pip-under {
		color: var(--color-warning-text);
	}
	.pip-pending {
		color: var(--color-text-tertiary);
	}

	.timed {
		display: flex;
		align-items: flex-end;
		gap: var(--space-md);
	}
	.timed .field {
		flex: 1 1 auto;
	}
	.timed .stopwatch {
		flex: 0 0 auto;
	}
	.timed .stopwatch.running {
		color: var(--color-danger);
		border-color: var(--color-danger);
	}
	.inputs {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-md);
	}
	.inputs.has-distance {
		grid-template-columns: repeat(4, 1fr);
	}
	@media (max-width: 30rem) {
		.inputs.has-distance {
			grid-template-columns: repeat(2, 1fr);
		}
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.field-label {
		color: var(--color-text-tertiary);
	}
	.field input {
		padding: var(--space-sm);
		font-size: 1.1rem;
		text-align: center;
		font-variant-numeric: tabular-nums;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		align-items: center;
	}
	.actions .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.actions .material-symbols {
		font-size: 1.05rem;
	}
	.complete {
		margin-inline-start: auto;
	}

	@media (max-width: 30rem) {
		.complete {
			margin-inline-start: 0;
			width: 100%;
			justify-content: center;
		}
	}
</style>
