<script lang="ts">
	import { onMount } from 'svelte';
	import { createTrainingPlan, fetchActivePlanOverview } from '$lib/data';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import {
		GOAL_DISTANCES_M,
		defaultPlanWeeks,
		generatePlan,
		PHASE_LABEL,
		WORKOUT_KIND_LABEL,
	} from '$lib/training';
	import type {
		GoalEvent,
		GeneratedPlan,
		WorkoutKind,
		TrainingGender,
	} from '$lib/training';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';
	import { fmtKm, fmtPace, getUnit } from '$lib/units.svelte';

	// Persona-hunt Round 3 finding Woman #3. Pull the runner's gender
	// off user_profiles so generatePlan can apply the gender-aware
	// pace calibration when available. We don't ask in the wizard
	// (the runner already set it in Settings → Preferences alongside
	// the segments-leaderboard demographics). null → unmodified
	// (male-curve) paces, matching pre-fix behaviour.
	let viewerGender = $state<TrainingGender>(null);
	onMount(async () => {
		if (!auth.user) return;
		const { data } = await supabase
			.from('user_profiles')
			.select('gender')
			.eq('id', auth.user.id)
			.maybeSingle();
		const g = (data as { gender?: string | null } | null)?.gender;
		if (g === 'male' || g === 'female' || g === 'nonbinary') viewerGender = g;
	});

	const METRES_PER_MILE = 1609.344;
	let distanceUnit = $derived(getUnit());
	let distancePerUnit = $derived(distanceUnit === 'mi' ? METRES_PER_MILE : 1000);
	let distanceStep = $derived(distanceUnit === 'mi' ? '0.1' : '0.5');

	function metresToDistanceInput(metres: number | null | undefined): string {
		if (metres == null) return '';
		return String(Math.round((metres / distancePerUnit) * 10) / 10);
	}
	function distanceInputToMetres(raw: string): number | null {
		if (raw === '') return null;
		const num = parseFloat(raw);
		if (Number.isNaN(num)) return null;
		return Math.max(0, num * distancePerUnit);
	}

	interface Props {
		oncreated?: (plan: { id: string }) => void;
		oncancel?: () => void;
	}
	let { oncreated, oncancel }: Props = $props();

	let name = $state('');
	let goalEvent = $state<GoalEvent>('distance_half');
	let startDate = $state(defaultStart());
	let daysPerWeek = $state(4);

	let targetHours = $state<number | null>(null);
	let targetMin = $state<number | null>(null);
	let targetSec = $state<number | null>(null);

	let recent5kMin = $state<number | null>(null);
	let recent5kSec = $state<number | null>(null);
	// Returning runners type an old PR; the engine would treat it as current
	// fitness and prescribe paces that are too fast (injury risk — comeback
	// persona #24). The time only anchors paces once the runner confirms it
	// reflects current fitness; otherwise we fall back to goal-based paces.
	let recent5kConfirmed = $state(false);

	let weekOverride = $state<number | null>(null);
	let busy = $state(false);
	let error = $state<string | null>(null);

	// Editable plan state. The auto-generator produces a candidate
	// outline whenever core form inputs change; the user can then
	// tweak individual workouts before clicking Create plan. Touching
	// any non-week input regenerates and discards user edits — matches
	// the "if you change the goal, the schedule changes" expectation.
	let plan = $state<GeneratedPlan | null>(null);
	let expandedWeek = $state<number | null>(null);

	const KIND_OPTIONS: WorkoutKind[] = [
		'easy',
		'long',
		'recovery',
		'tempo',
		'interval',
		'marathon_pace',
		'race',
		'rest',
	];

	function paceToInput(secPerKm: number | null): string {
		if (secPerKm == null || secPerKm <= 0) return '';
		const m = Math.floor(secPerKm / 60);
		const s = Math.round(secPerKm % 60);
		return `${m}:${String(s).padStart(2, '0')}`;
	}

	function inputToPace(raw: string): number | null {
		const trimmed = raw.trim();
		if (!trimmed) return null;
		const m = trimmed.match(/^(\d{1,2}):(\d{2})$/);
		if (!m) return null;
		return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
	}

	function paceInputHandler(weekIdx: number, woIdx: number) {
		return (e: Event) => {
			if (!plan) return;
			const value = (e.currentTarget as HTMLInputElement).value;
			const sec = inputToPace(value);
			plan.weeks[weekIdx].workouts[woIdx].target_pace_sec_per_km = sec;
		};
	}

	function describeError(e: unknown): string {
		if (e instanceof Error) return e.message;
		if (e && typeof e === 'object') {
			const obj = e as { message?: unknown; code?: unknown; details?: unknown };
			const parts: string[] = [];
			if (typeof obj.message === 'string') parts.push(obj.message);
			if (typeof obj.code === 'string') parts.push(`(${obj.code})`);
			if (typeof obj.details === 'string') parts.push(obj.details);
			if (parts.length) return parts.join(' ');
		}
		return 'Failed to create plan. Check the browser console for details.';
	}

	function defaultStart(): string {
		const d = new Date();
		d.setDate(d.getDate() + 7);
		d.setDate(d.getDate() + ((7 - d.getDay()) % 7));
		const pad = (n: number) => String(n).padStart(2, '0');
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	}

	let goalDistance = $derived(
		goalEvent === 'custom' ? 10_000 : GOAL_DISTANCES_M[goalEvent]
	);
	let weeks = $derived(weekOverride ?? defaultPlanWeeks(goalEvent));

	let goalTimeSec = $derived(
		targetHours != null || targetMin != null || targetSec != null
			? (targetHours ?? 0) * 3600 + (targetMin ?? 0) * 60 + (targetSec ?? 0)
			: null
	);
	let recent5kTotal = $derived(
		recent5kMin != null || recent5kSec != null
			? (recent5kMin ?? 0) * 60 + (recent5kSec ?? 0)
			: null
	);
	// Only anchor paces on the entered time once the runner confirms it's
	// current. An entered-but-unconfirmed time is treated as absent so paces
	// stay on the conservative goal-based fallback.
	let recent5kApplied = $derived(recent5kConfirmed ? recent5kTotal : null);
	let recent5kNeedsConfirm = $derived(recent5kTotal != null && !recent5kConfirmed);

	// Re-generate the editable plan whenever any input that drives
	// generation changes. Replaces the previous $derived preview so we
	// can mutate workouts in-place; the user's edits live on `plan`
	// until they touch a top-level input again.
	$effect(() => {
		// Read every input we care about so the effect tracks them.
		void [goalEvent, goalDistance, goalTimeSec, recent5kApplied, startDate, daysPerWeek, weeks, viewerGender];
		if (!startDate) {
			plan = null;
			return;
		}
		try {
			plan = generatePlan({
				goalEvent,
				goalDistanceM: goalDistance,
				goalTimeSec,
				recent5kSec: recent5kApplied,
				startDate,
				daysPerWeek,
				weeks,
				gender: viewerGender,
			});
			expandedWeek = null;
		} catch (_) {
			plan = null;
		}
	});

	const eventOptions: { value: GoalEvent; label: string }[] = [
		{ value: 'distance_5k', label: '5K' },
		{ value: 'distance_10k', label: '10K' },
		{ value: 'distance_half', label: 'Half marathon' },
		{ value: 'distance_full', label: 'Marathon' }
	];

	/// The schema enforces one active plan per user via a partial unique
	/// index, and `createTrainingPlan` enforces it by auto-completing
	/// any existing active plan inside the same transaction. That used
	/// to happen silently — clicking "Create plan" on the wizard would
	/// transparently flip the user's current plan to `completed` with
	/// no warning. This dialog gates the create on an explicit
	/// confirmation when a previous active plan exists; the user gets
	/// to see what they're about to retire and can cancel.
	let showReplaceConfirm = $state(false);
	let existingActiveName = $state<string | null>(null);

	async function submit(e: Event) {
		e.preventDefault();
		if (!name.trim() || !plan || busy) return;
		// Persona-hunt Intermediate #3: a startDate in the past
		// generates a plan anchored to elapsed weeks — the today-card +
		// progress ring report "you're already two workouts behind" the
		// moment the plan is created. The wizard's input has min=today
		// (set on the markup below) but a user that opened the modal
		// yesterday could submit a stale value before the page reloads,
		// and a future refactor that drops the markup-level min loses
		// the only guardrail. Validate at submit-time too.
		if (startDate && startDate < todayIso()) {
			error =
				'Plan start date is in the past. Pick today or a future date so the plan starts at week 1, not week 0.';
			return;
		}
		busy = true;
		error = null;
		try {
			const active = await fetchActivePlanOverview();
			if (active?.plan) {
				existingActiveName = active.plan.name;
				showReplaceConfirm = true;
				busy = false;
				return;
			}
			await proceedWithCreate();
		} catch (e: unknown) {
			error = describeError(e);
			console.error('Plan create failed', e);
			busy = false;
		}
	}

	function todayIso(): string {
		const d = new Date();
		const pad = (n: number) => String(n).padStart(2, '0');
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	}

	async function proceedWithCreate() {
		busy = true;
		error = null;
		try {
			const created = await createTrainingPlan({
				name: name.trim(),
				goalEvent,
				goalDistanceM: goalDistance,
				goalTimeSec,
				recent5kSec: recent5kApplied,
				startDate,
				daysPerWeek,
				generated: plan!,
			});
			oncreated?.(created);
		} catch (e: unknown) {
			error = describeError(e);
			console.error('Plan create failed', e);
		} finally {
			busy = false;
			showReplaceConfirm = false;
			existingActiveName = null;
		}
	}

	function cancelReplace() {
		showReplaceConfirm = false;
		existingActiveName = null;
	}
</script>

<form onsubmit={submit} class="plan-editor">
	<div class="grid">
		<section class="form">
			<label>
				<span>Plan name</span>
				<input
					type="text"
					bind:value={name}
					placeholder="Autumn half marathon"
					required
					maxlength="80"
				/>
			</label>

			<label>
				<span>Goal race</span>
				<select bind:value={goalEvent}>
					{#each eventOptions as opt}
						<option value={opt.value}>{opt.label}</option>
					{/each}
				</select>
			</label>

			<label>
				<span>Start date <span class="optional">first week begins Sunday</span></span>
				<input
					type="date"
					bind:value={startDate}
					min={todayIso()}
					required
				/>
			</label>

			<label>
				<span>Days per week</span>
				<select bind:value={daysPerWeek}>
					{#each [3, 4, 5, 6, 7] as n}
						<option value={n}>{n} days</option>
					{/each}
				</select>
			</label>

			<fieldset>
				<legend>Goal time <span class="optional">optional</span></legend>
				<p class="hint">Drives the pace targets. Leave blank for a volume-only plan.</p>
				<div class="time-row">
					<input type="number" min="0" max="9" bind:value={targetHours} placeholder="h" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetMin} placeholder="m" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetSec} placeholder="s" />
				</div>
			</fieldset>

			<fieldset>
				<legend>Recent 5K time <span class="optional">optional</span></legend>
				<p class="hint">Anchor paces on a real result via Riegel equivalence.</p>
				<div class="time-row">
					<input type="number" min="0" max="59" bind:value={recent5kMin} placeholder="m" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={recent5kSec} placeholder="s" />
				</div>
				{#if recent5kTotal != null}
					<label class="confirm-recent">
						<input type="checkbox" bind:checked={recent5kConfirmed} />
						<span>This is a time I could run today — it reflects my current fitness.</span>
					</label>
				{/if}
				{#if recent5kNeedsConfirm}
					<p class="hint warn" role="status">
						Until you confirm, paces stay on the conservative goal-based estimate.
						Anchoring on an old result can prescribe paces that are too fast for a
						returning runner.
					</p>
				{/if}
			</fieldset>

			<label>
				<span>Override total weeks <span class="optional">optional</span></span>
				<input
					type="number"
					min="4"
					max="24"
					bind:value={weekOverride}
					placeholder={String(defaultPlanWeeks(goalEvent))}
				/>
			</label>

			{#if error}
				<p class="error">{error}</p>
			{/if}

			<div class="actions">
				{#if oncancel}
					<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>Cancel</button>
				{/if}
				<button type="submit" class="btn btn-primary" disabled={!name.trim() || !plan || busy}>
					{busy ? 'Creating…' : 'Create plan'}
				</button>
			</div>
		</section>

		<aside class="preview">
			<h2>Preview &amp; edit</h2>
			{#if plan}
				<div class="paces">
					<div class="pace-row"><span>Easy</span><strong>{fmtPace(plan.paces.easy)}</strong></div>
					<div class="pace-row"><span>Marathon</span><strong>{fmtPace(plan.paces.marathon)}</strong></div>
					<div class="pace-row"><span>Tempo</span><strong>{fmtPace(plan.paces.tempo)}</strong></div>
					<div class="pace-row"><span>Interval</span><strong>{fmtPace(plan.paces.interval)}</strong></div>
					<div class="pace-row"><span>Repetition</span><strong>{fmtPace(plan.paces.repetition)}</strong></div>
				</div>

				{#if plan.vdot}
					<p class="vdot">Daniels VDOT: <strong>{plan.vdot.toFixed(1)}</strong></p>
				{/if}

				<h3>Week outline</h3>
				<p class="outline-hint">
					Click a week to expand the day-by-day editor. Changes are kept until you tweak
					a top-level input above (which regenerates the whole plan).
				</p>
				<ul class="weeks">
					{#each plan.weeks as w, weekIdx (w.week_index)}
						<li class="week-item" class:expanded={expandedWeek === weekIdx}>
							<button
								type="button"
								class="week-row"
								onclick={() => (expandedWeek = expandedWeek === weekIdx ? null : weekIdx)}
							>
								<span class="week-num">#{w.week_index + 1}</span>
								<span class="week-phase">{PHASE_LABEL[w.phase]}</span>
								<span class="week-km">{fmtKm(w.target_volume_m, 0)}</span>
								<span class="week-workouts">
									{w.workouts.filter((x) => x.kind !== 'rest').length} sessions
								</span>
								<span class="caret material-symbols">
									{expandedWeek === weekIdx ? 'expand_less' : 'expand_more'}
								</span>
							</button>

							{#if expandedWeek === weekIdx}
								<div class="week-editor">
									{#each w.workouts as wo, woIdx (woIdx)}
										<div class="wo-row">
											<div class="wo-date">
												{new Date(wo.scheduled_date).toLocaleDateString(undefined, {
													weekday: 'short',
													month: 'short',
													day: 'numeric',
												})}
											</div>
											<label class="wo-field">
												<span>Run type</span>
												<select bind:value={w.workouts[woIdx].kind}>
													{#each KIND_OPTIONS as k}
														<option value={k}>{WORKOUT_KIND_LABEL[k]}</option>
													{/each}
												</select>
											</label>
											<label class="wo-field">
												<span>Distance ({distanceUnit})</span>
												<input
													type="number"
													min="0"
													step={distanceStep}
													value={metresToDistanceInput(wo.target_distance_m)}
													oninput={(e) => {
														w.workouts[woIdx].target_distance_m = distanceInputToMetres(
															(e.currentTarget as HTMLInputElement).value,
														);
													}}
													disabled={wo.kind === 'rest'}
												/>
											</label>
											<label class="wo-field">
												<span>Pace (mm:ss)</span>
												<input
													type="text"
													inputmode="numeric"
													pattern={'[0-9]{1,2}:[0-9]{2}'}
													placeholder="—"
													value={paceToInput(wo.target_pace_sec_per_km)}
													oninput={paceInputHandler(weekIdx, woIdx)}
													disabled={wo.kind === 'rest'}
												/>
											</label>
											<label class="wo-field wo-notes">
												<span>Notes</span>
												<input
													type="text"
													bind:value={w.workouts[woIdx].notes}
													placeholder="—"
													maxlength="200"
												/>
											</label>
										</div>
									{/each}
								</div>
							{/if}
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">Fill in the form to see a preview.</p>
			{/if}
		</aside>
	</div>
</form>

<ConfirmDialog
	open={showReplaceConfirm}
	title="Replace your active plan?"
	message={existingActiveName
		? `You already have an active plan: "${existingActiveName}". Creating a new plan will mark the current one as completed (you can still find it under Manage plans). Continue?`
		: 'You already have an active plan. Creating a new plan will mark the current one as completed. Continue?'}
	confirmLabel="Replace plan"
	cancelLabel="Keep current"
	danger={true}
	onconfirm={proceedWithCreate}
	oncancel={cancelReplace}
/>

<style>
	.plan-editor {
		display: block;
	}
	.grid {
		display: grid;
		grid-template-columns: minmax(0, 22rem) minmax(0, 1fr);
		gap: var(--space-lg);
	}
	@media (max-width: 60rem) {
		.grid {
			grid-template-columns: 1fr;
		}
	}
	.form,
	.preview {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	label,
	fieldset {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 0.9rem;
		font-weight: 600;
	}
	.optional {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}
	input[type='text'],
	input[type='date'],
	input[type='number'],
	select {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.55rem 0.75rem;
		font: inherit;
		color: inherit;
	}
	fieldset {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.8rem 1rem;
		background: var(--color-surface);
	}
	legend {
		font-weight: 600;
		padding: 0 0.4rem;
	}
	.hint {
		font-weight: 400;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin-bottom: 0.4rem;
	}
	/* Full-contrast text (not --color-warning, which is a light accent that
	   fails AA as body text on the cream surface); emphasis carries "warning". */
	.hint.warn {
		color: var(--color-text);
		font-weight: 500;
	}
	.confirm-recent {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		margin-top: 0.5rem;
		font-size: 0.85rem;
		font-weight: 400;
	}
	.confirm-recent input {
		margin-top: 0.15rem;
	}
	.time-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	.time-row input {
		width: 4rem;
		text-align: center;
	}
	.time-row span {
		font-weight: 700;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
	}
	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}
	.preview h2 {
		font-size: 1.1rem;
	}
	.preview h3 {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		margin-top: var(--space-md);
	}
	.paces {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.4rem 0.8rem;
	}
	.pace-row {
		display: flex;
		justify-content: space-between;
		padding: 0.3rem 0.55rem;
		background: var(--color-surface);
		border-radius: var(--radius-md);
		font-size: 0.88rem;
	}
	.vdot {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-top: -0.2rem;
	}
	.outline-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		margin: 0 0 0.4rem 0;
	}
	.weeks {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.week-item {
		background: var(--color-surface);
		border-radius: var(--radius-md);
		border: 1px solid var(--color-border);
		min-width: 0;
		overflow: hidden;
	}
	.week-item.expanded {
		border-color: var(--color-primary);
	}
	.week-row {
		display: grid;
		grid-template-columns: 2rem minmax(0, 1fr) auto auto auto;
		gap: 0.5rem;
		align-items: center;
		font-size: 0.85rem;
		padding: 0.45rem 0.6rem;
		background: transparent;
		border: none;
		cursor: pointer;
		text-align: left;
		width: 100%;
		color: inherit;
		font: inherit;
	}
	.week-row:hover {
		background: var(--color-bg-secondary);
	}
	.week-num {
		font-weight: 700;
		color: var(--color-primary);
	}
	.week-phase {
		color: var(--color-text-secondary);
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.week-km {
		color: var(--color-text);
		text-align: right;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.week-workouts {
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
		white-space: nowrap;
	}
	.caret {
		color: var(--color-text-tertiary);
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}
	.week-editor {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		padding: 0.5rem 0.75rem 0.75rem;
		background: var(--color-bg-secondary);
		border-top: 1px solid var(--color-border);
	}
	.wo-row {
		/* Date + run type + distance + pace on one row; notes always
		   wraps to its own line so the four primary fields aren't
		   squeezed against each other and the run-type dropdown has
		   room to display its longer labels (e.g. "Marathon Pace"). */
		display: grid;
		grid-template-columns: minmax(5.5rem, auto) minmax(8rem, 1.3fr) minmax(6rem, 1fr) minmax(6rem, 1fr);
		gap: 0.5rem;
		align-items: end;
		padding: 0.55rem 0.6rem;
		background: var(--color-surface);
		border-radius: var(--radius-sm);
	}
	.wo-notes {
		grid-column: 1 / -1;
	}
	@media (max-width: 50rem) {
		.wo-row {
			grid-template-columns: repeat(2, 1fr);
		}
	}
	.wo-date {
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		white-space: nowrap;
	}
	.wo-field {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		min-width: 0;
	}
	.wo-field input,
	.wo-field select {
		padding: 0.35rem 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.85rem;
		text-transform: none;
		letter-spacing: 0;
		font-weight: 400;
		min-width: 0;
	}
	.wo-field input:disabled,
	.wo-field select:disabled {
		opacity: 0.5;
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
