<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import { createTrainingPlan, fetchActivePlanOverview } from '$lib/core/data';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import {
		GOAL_DISTANCES_M,
		defaultPlanWeeks,
		walkRunDefaultWeeks,
		generatePlan,
		formatISO,
	} from '$lib/training/training';
	import { workoutKindLabel, planPhaseLabel } from '$lib/training/workout_labels';
	import type {
		GoalEvent,
		GeneratedPlan,
		WorkoutKind,
		TrainingGender,
	} from '$lib/training/training';
	import { isSundayIso, nextSundayIso } from '$lib/training/plan_start';
	import { parsePlanMarkdown, parsePlanJson } from '$lib/training/plan_serialize';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { fmtKm, fmtPace, getUnit } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	// Persona-hunt Round 3 finding Woman #3. Pull the runner's gender
	// off user_profiles so generatePlan can apply the gender-aware
	// pace calibration when available. We don't ask in the wizard
	// (the runner already set it in Settings → Preferences alongside
	// the segments-leaderboard demographics). null → unmodified
	// (male-curve) paces, matching pre-fix behaviour.
	let viewerGender = $state<TrainingGender>(null);
	// Persona-hunt finding Older #30. Age (from date_of_birth) drives the
	// masters recovery calibration in generatePlan — wider hard-day
	// spacing + a 3-week build/recover cycle for 50+. Like gender, it's
	// read off the profile rather than asked in the wizard. null → the
	// standard (younger-physiology) schedule.
	let viewerAge = $state<number | null>(null);
	onMount(async () => {
		if (!auth.user) return;
		// Self-read via get_my_profile(): gender / date_of_birth are
		// deny-by-default for direct authenticated SELECTs (column lockdown,
		// 20260707_001).
		const { data } = await supabase.rpc('get_my_profile');
		const g = (data as { gender?: string | null } | null)?.gender;
		if (g === 'male' || g === 'female' || g === 'nonbinary') viewerGender = g;
		const dob = (data as { date_of_birth?: string | null } | null)?.date_of_birth;
		if (dob) {
			const born = new Date(dob);
			if (!Number.isNaN(born.getTime())) {
				const now = new Date();
				let age = now.getFullYear() - born.getFullYear();
				const m = now.getMonth() - born.getMonth();
				if (m < 0 || (m === 0 && now.getDate() < born.getDate())) age--;
				if (age >= 0 && age < 120) viewerAge = age;
			}
		}
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
	// Beginner / return-to-run: generate a C25K-style walk-run plan (persona #22).
	let beginnerWalkRun = $state(false);

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

	// Paste-import state. When `importedMode` is on, the auto-generate
	// effect stands down so a pasted plan isn't clobbered; changing any
	// core form input exits import mode and hands control back to the
	// generator. `importedGoalDistanceM` carries the parsed goal distance
	// (the generator's `goalDistance` derived is wrong for a custom event).
	let showImport = $state(false);
	let importText = $state('');
	let importError = $state<string | null>(null);
	let importedMode = $state(false);
	let importedGoalDistanceM = $state<number | null>(null);

	function loadFromText() {
		importError = null;
		const text = importText.trim();
		if (!text) return;
		try {
			const parsed = text.startsWith('{') ? parsePlanJson(text) : parsePlanMarkdown(text);
			name = parsed.name;
			goalEvent = parsed.goalEvent;
			startDate = parsed.startDate;
			importedGoalDistanceM = parsed.goalDistanceM;
			if (parsed.goalTimeSec != null && parsed.goalTimeSec > 0) {
				targetHours = Math.floor(parsed.goalTimeSec / 3600);
				targetMin = Math.floor((parsed.goalTimeSec % 3600) / 60);
				targetSec = parsed.goalTimeSec % 60;
			}
			importedMode = true;
			plan = parsed.generated;
			expandedWeek = null;
			showImport = false;
		} catch (e) {
			importError = describeError(e);
		}
	}

	/// Changing a core input means the runner wants the generator back —
	/// drop import mode so the reactive effect regenerates from the form.
	function exitImportMode() {
		if (importedMode) {
			importedMode = false;
			importedGoalDistanceM = null;
		}
	}

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
		return t('planEditor.errorCreateFailed');
	}

	// A brand-new runner ticking the walk-run box is not training for a half
	// (the default goal) — point them at 5K, the appropriate first-timer
	// target. One-shot on enable only, and only when the current goal is
	// longer than 5K, so it never clobbers a deliberate 5K choice and never
	// stops them re-picking 10K afterwards.
	function onBeginnerToggle(e: Event) {
		beginnerWalkRun = (e.currentTarget as HTMLInputElement).checked;
		if (beginnerWalkRun && goalDistance > GOAL_DISTANCES_M.distance_5k) {
			goalEvent = 'distance_5k';
		}
	}

	function defaultStart(): string {
		const d = new Date();
		d.setDate(d.getDate() + 7);
		d.setDate(d.getDate() + ((7 - d.getDay()) % 7));
		return formatISO(d);
	}

	// The generator hard-anchors day 0 of the start week to the Sunday long
	// run (rest=Mon, quality=Tue/Thu). A non-Sunday start silently shifts
	// every day-role, so the long run lands on a weekday. The <input
	// type="date"> can't restrict to Sundays, so snap the chosen date
	// forward to the upcoming Sunday on change — the reactive preview then
	// regenerates from the aligned date, keeping what the user sees in sync
	// with what's saved. (Persona round-5 intermediate.)
	let startSnapped = $state(false);
	function alignStartToSunday() {
		if (!startDate) return;
		if (isSundayIso(startDate)) {
			startSnapped = false;
			return;
		}
		startDate = nextSundayIso(startDate);
		startSnapped = true;
	}

	let goalDistance = $derived(
		goalEvent === 'custom' ? 10_000 : GOAL_DISTANCES_M[goalEvent]
	);
	// A beginner walk-run plan needs the full C25K progression length (9
	// weeks), not the 5k continuous-run default (8) — otherwise the final
	// graduation week is dropped. Persona round-5 runner-new. An explicit
	// override still wins.
	let weeks = $derived(
		weekOverride ?? (beginnerWalkRun ? walkRunDefaultWeeks() : defaultPlanWeeks(goalEvent))
	);

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
		void [goalEvent, goalDistance, goalTimeSec, recent5kApplied, startDate, daysPerWeek, weeks, viewerGender, beginnerWalkRun, importedMode];
		// A pasted plan owns `plan` until the runner edits a core input
		// (which flips importedMode off and re-runs this effect).
		if (importedMode) return;
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
				age: viewerAge,
				beginnerWalkRun,
			});
			expandedWeek = null;
		} catch (_) {
			plan = null;
		}
	});

	const eventOptions: { value: GoalEvent; label: string }[] = $derived([
		{ value: 'distance_5k', label: '5K' },
		{ value: 'distance_10k', label: '10K' },
		{ value: 'distance_half', label: t('planEditor.halfMarathon') },
		{ value: 'distance_full', label: t('planEditor.marathon') }
	]);

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
		if (!importedMode && startDate && startDate < todayIso()) {
			error = t('planEditor.errorStartInPast');
			return;
		}
		// Defensive backstop: onchange snaps the date to a Sunday, but if a
		// non-Sunday slipped through (keyboard entry that didn't fire
		// onchange), snap now and re-show the preview rather than persisting
		// a misaligned plan. The reactive preview regenerates from the
		// aligned date, so ask the user to submit once more.
		if (!importedMode && startDate && !isSundayIso(startDate)) {
			alignStartToSunday();
			error = t('planEditor.errorStartMovedToSunday');
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
		return formatISO(d);
	}

	async function proceedWithCreate() {
		busy = true;
		error = null;
		try {
			const created = await createTrainingPlan({
				name: name.trim(),
				goalEvent,
				// A pasted plan's distance comes from the parse (the derived
				// `goalDistance` is wrong for a custom-event import).
				goalDistanceM: importedMode && importedGoalDistanceM ? importedGoalDistanceM : goalDistance,
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
			<details class="import-box" bind:open={showImport}>
				<summary>{t('planEditor.importTitle')}</summary>
				<p class="hint">{t('planEditor.importHint')}</p>
				<textarea
					class="import-text"
					bind:value={importText}
					rows="6"
					placeholder={t('planEditor.importPlaceholder')}
				></textarea>
				{#if importError}
					<p class="error">{importError}</p>
				{/if}
				<button type="button" class="btn btn-secondary" onclick={loadFromText}>
					{t('planEditor.importLoad')}
				</button>
			</details>
			{#if importedMode}
				<p class="imported-note" role="status">{t('planEditor.importedNote')}</p>
			{/if}

			<label>
				<span>{t('planEditor.planName')}</span>
				<input
					type="text"
					bind:value={name}
					placeholder={t('planEditor.planNamePlaceholder')}
					required
					maxlength="80"
				/>
			</label>

			<label>
				<span>{t('planEditor.goalRace')}</span>
				<select bind:value={goalEvent} onchange={exitImportMode}>
					{#each eventOptions as opt}
						<option value={opt.value}>{opt.label}</option>
					{/each}
				</select>
			</label>

			<label>
				<span>{t('planEditor.startDate')} <span class="optional">{t('planEditor.firstWeekBeginsSunday')}</span></span>
				<input
					type="date"
					bind:value={startDate}
					min={todayIso()}
					onchange={() => { exitImportMode(); alignStartToSunday(); }}
					required
				/>
				{#if startSnapped}
					<span class="field-note">{t('planEditor.movedToNextSunday')}</span>
				{/if}
			</label>

			<label>
				<span>{t('planEditor.daysPerWeek')}</span>
				<select bind:value={daysPerWeek} onchange={exitImportMode}>
					{#each [3, 4, 5, 6, 7] as n}
						<option value={n}>{t('planEditor.nDays', { n })}</option>
					{/each}
				</select>
			</label>

			<fieldset>
				<legend>{t('planEditor.goalTime')} <span class="optional">{t('planEditor.optional')}</span></legend>
				<p class="hint">{t('planEditor.goalTimeHint')}</p>
				<div class="time-row">
					<input type="number" min="0" max="9" bind:value={targetHours} placeholder={t('planEditor.placeholderHours')} />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetMin} placeholder={t('planEditor.placeholderMinutes')} />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetSec} placeholder={t('planEditor.placeholderSeconds')} />
				</div>
			</fieldset>

			<label class="beginner-toggle">
				<input type="checkbox" checked={beginnerWalkRun} onchange={onBeginnerToggle} />
				<span>
					<span class="beginner-title">{t('planEditor.beginnerTitle')}</span>
					<span class="hint">
						{t('planEditor.beginnerHint')}
					</span>
				</span>
			</label>

			<fieldset>
				<legend>{t('planEditor.recent5kTime')} <span class="optional">{t('planEditor.optional')}</span></legend>
				<p class="hint">{t('planEditor.recent5kHint')}</p>
				<div class="time-row">
					<input type="number" min="0" max="59" bind:value={recent5kMin} placeholder={t('planEditor.placeholderMinutes')} />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={recent5kSec} placeholder={t('planEditor.placeholderSeconds')} />
				</div>
				{#if recent5kTotal != null}
					<label class="confirm-recent">
						<input type="checkbox" bind:checked={recent5kConfirmed} />
						<span>{t('planEditor.recent5kConfirm')}</span>
					</label>
				{/if}
				{#if recent5kNeedsConfirm}
					<p class="hint warn" role="status">
						{t('planEditor.recent5kWarn')}
					</p>
				{/if}
			</fieldset>

			<label>
				<span>{t('planEditor.overrideTotalWeeks')} <span class="optional">{t('planEditor.optional')}</span></span>
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
					<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>{t('planEditor.cancel')}</button>
				{/if}
				<button type="submit" class="btn btn-primary" disabled={!name.trim() || !plan || busy}>
					{busy ? t('planEditor.creating') : t('planEditor.createPlan')}
				</button>
			</div>
		</section>

		<aside class="preview">
			<h2>{t('planEditor.previewAndEdit')}</h2>
			{#if plan}
				<div class="paces">
					<div class="pace-row"><span>{t('planEditor.paceEasy')}</span><strong>{fmtPace(plan.paces.easy)}</strong></div>
					<div class="pace-row"><span>{t('planEditor.paceMarathon')}</span><strong>{fmtPace(plan.paces.marathon)}</strong></div>
					<div class="pace-row"><span>{t('planEditor.paceTempo')}</span><strong>{fmtPace(plan.paces.tempo)}</strong></div>
					<div class="pace-row"><span>{t('planEditor.paceInterval')}</span><strong>{fmtPace(plan.paces.interval)}</strong></div>
					<div class="pace-row"><span>{t('planEditor.paceRepetition')}</span><strong>{fmtPace(plan.paces.repetition)}</strong></div>
				</div>

				{#if plan.pacesAreFallback}
					<p class="paces-estimated" role="status">
						{t('planEditor.pacesEstimated')}
					</p>
				{/if}

				{#if plan.vdot}
					<p class="vdot">{t('planEditor.danielsVdot')} <strong>{plan.vdot.toFixed(1)}</strong></p>
				{/if}

				<h3>{t('planEditor.weekOutline')}</h3>
				<p class="outline-hint">
					{t('planEditor.outlineHint')}
				</p>
				<ul class="weeks">
					{#each plan.weeks as w, weekIdx (w.week_index)}
						{@const sessionCount = w.workouts.filter((x) => x.kind !== 'rest').length}
						<li class="week-item" class:expanded={expandedWeek === weekIdx}>
							<button
								type="button"
								class="week-row"
								onclick={() => (expandedWeek = expandedWeek === weekIdx ? null : weekIdx)}
							>
								<span class="week-num">#{w.week_index + 1}</span>
								<span class="week-phase">{planPhaseLabel(w.phase)}</span>
								<span class="week-km">{fmtKm(w.target_volume_m, 0)}</span>
								<span class="week-workouts">
									{t(sessionCount === 1 ? 'planEditor.nSessionsOne' : 'planEditor.nSessionsMany', { n: sessionCount })}
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
												{new Date(wo.scheduled_date).toLocaleDateString(activeFormatLocale(), {
													weekday: 'short',
													month: 'short',
													day: 'numeric',
												})}
											</div>
											<label class="wo-field">
												<span>{t('planEditor.runType')}</span>
												<select bind:value={w.workouts[woIdx].kind}>
													{#each KIND_OPTIONS as k}
														<option value={k}>{workoutKindLabel(k)}</option>
													{/each}
												</select>
											</label>
											<label class="wo-field">
												<span>{t('planEditor.distance', { unit: distanceUnit })}</span>
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
												<span>{t('planEditor.paceMmSs')}</span>
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
												<span>{t('planEditor.notes')}</span>
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
				<p class="muted">{t('planEditor.fillFormForPreview')}</p>
			{/if}
		</aside>
	</div>
</form>

<ConfirmDialog
	open={showReplaceConfirm}
	title={t('planEditor.replaceActivePlanTitle')}
	message={existingActiveName
		? t('planEditor.replaceActivePlanNamed', { name: existingActiveName })
		: t('planEditor.replaceActivePlanUnnamed')}
	confirmLabel={t('planEditor.replacePlan')}
	cancelLabel={t('planEditor.keepCurrent')}
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
	.field-note {
		display: block;
		margin-top: var(--space-2xs);
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		font-weight: 400;
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
	.beginner-toggle {
		display: flex;
		align-items: flex-start;
		gap: 0.6rem;
	}
	.beginner-toggle input { margin-top: 0.2rem; }
	.beginner-title { display: block; font-weight: 600; }
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
	.import-box {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		padding: 0.4rem 0.7rem;
	}
	.import-box summary {
		cursor: pointer;
		font-weight: 600;
		font-size: 0.9rem;
		padding: 0.25rem 0;
	}
	.import-box[open] summary {
		margin-bottom: 0.4rem;
	}
	.import-text {
		width: 100%;
		box-sizing: border-box;
		font-family: var(--font-mono, monospace);
		font-size: 0.8rem;
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 0.5rem;
		color: var(--color-text);
		resize: vertical;
		margin-bottom: 0.5rem;
	}
	.imported-note {
		font-size: 0.82rem;
		font-weight: 500;
		color: var(--color-primary);
		margin: 0;
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
	/* Full-contrast body text (not --color-warning, which fails AA as body
	   text on the surface); weight carries the "this is a caveat" emphasis. */
	.paces-estimated {
		color: var(--color-text);
		font-weight: 500;
		font-size: 0.82rem;
		margin: 0;
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
		text-align: start;
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
		text-align: end;
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
