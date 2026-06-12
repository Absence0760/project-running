<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchGymWorkoutWithSets,
		fetchExerciseSetHistory,
		deleteGymWorkout,
		type GymWorkoutWithSets,
		type GymSet,
		type GymSetWithDate,
	} from '$lib/core/data';
	import { workoutPrs, normaliseExerciseName, type GymSetLike, type PrKind } from '$lib/gym/gym_prs';
	import { previousExerciseSession, type ExerciseSession } from '$lib/gym/exercise_history';
	import {
		routineFromWorkout,
		prefillFromRoutine,
		type PrefillExercise,
	} from '$lib/gym/gym_routine';
	import { formatDate } from '$lib/format/time';
	import { formatWeight, weightUnitLabel } from '$lib/format/units.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import GymEditor from '$lib/components/GymEditor.svelte';
	import RoutineEditor from '$lib/components/RoutineEditor.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import GymWorkoutReview from '$lib/components/GymWorkoutReview.svelte';
	import type { GymStepResult } from '$lib/gym/gym_session_types';
	import type { RoutineAdherence, RoutineVerdict, SetAdherence } from '$lib/gym/gym_adherence';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	const id = $derived($page.params.id ?? '');

	let data = $state<GymWorkoutWithSets | null>(null);
	let history = $state<GymSetWithDate[]>([]);
	let loading = $state(true);
	let notFound = $state(false);
	let editing = $state(false);
	let confirmingDelete = $state(false);
	let savingAsRoutine = $state(false);
	let repeating = $state(false);
	let routineSeed = $state<PrefillExercise[] | null>(null);
	let routineSeedTitle = $state('');
	let repeatSeed = $state<GymWorkoutWithSets | null>(null);

	// "Save as routine": promote this logged session's grouped sets into a
	// routine draft (gym_routine.ts), then prefill the RoutineEditor with it.
	function openSaveAsRoutine() {
		if (!data) return;
		const draft = routineFromWorkout(
			data.workout.title,
			data.sets.map((s) => ({
				exercise_name: s.exercise_name,
				reps: s.reps,
				weight_kg: s.weight_kg,
				rpe: s.rpe,
			})),
		);
		routineSeed = prefillFromRoutine({
			title: draft.title,
			exercises: draft.exercises.map((e) => ({
				exerciseName: e.exerciseName,
				position: e.position,
				sets: e.sets.map((st) => ({
					setIndex: st.setIndex,
					targetRepsMin: st.targetRepsMin,
					targetRepsMax: st.targetRepsMax,
					targetWeightKg: st.targetWeightKg,
					targetRpe: st.targetRpe,
				})),
			})),
		});
		routineSeedTitle = draft.title;
		savingAsRoutine = true;
	}

	// "Repeat last": instantiate this session's sets into a fresh GymEditor log
	// (no saved routine required). The GymEditor groups by exercise_name on init.
	function openRepeat() {
		if (!data) return;
		repeatSeed = {
			workout: { ...data.workout, id: '', title: data.workout.title },
			sets: data.sets.map((s, i) => ({ ...s, id: '', workout_id: '', set_index: i })),
		};
		repeating = true;
	}

	function onRepeated() {
		repeating = false;
		repeatSeed = null;
		goto('/gym');
	}

	function onRoutineSaved() {
		savingAsRoutine = false;
		routineSeed = null;
	}

	const isOwner = $derived(!!data && data.workout.user_id === auth.user?.id);

	async function load() {
		loading = true;
		const w = await fetchGymWorkoutWithSets(id);
		data = w;
		notFound = w == null;
		// The PR badges + "vs last time" only judge THIS workout's exercises
		// against their own earlier sessions, so fetch just those exercises'
		// history (one bounded RPC each) instead of the user's entire gym_sets
		// log. Dedup by the normalised key so a differently-cased pair isn't
		// fetched twice (the RPC already matches normalised names).
		// perf-hunt 2026-06-10.
		if (w) {
			const byKey = new Map<string, string>();
			for (const s of w.sets) {
				const key = normaliseExerciseName(s.exercise_name);
				if (key && !byKey.has(key)) byKey.set(key, s.exercise_name);
			}
			const histories = await Promise.all(
				[...byKey.values()].map((nm) => fetchExerciseSetHistory(nm)),
			);
			history = histories.flat();
		} else {
			history = [];
		}
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
	});

	// Group this workout's sets into exercise blocks (set_index order).
	const blocks = $derived.by(() => {
		const out: { name: string; sets: GymSet[] }[] = [];
		for (const s of data?.sets ?? []) {
			const last = out[out.length - 1];
			if (last && last.name === s.exercise_name) last.sets.push(s);
			else out.push({ name: s.exercise_name, sets: [s] });
		}
		return out;
	});

	// PR kinds this workout achieved, per exercise, judged against all of
	// the user's OTHER (earlier) sets.
	const prByExercise = $derived.by(() => {
		const out = new Map<string, PrKind[]>();
		if (!data || !isOwner) return out;
		const startedAt = data.workout.started_at;
		const prior: GymSetLike[] = history
			.filter((s) => s.workout_id !== data!.workout.id && s.started_at < startedAt)
			.map((s) => ({ exercise_name: s.exercise_name, reps: s.reps, weight_kg: s.weight_kg }));
		const mine: GymSetLike[] = data.sets.map((s) => ({
			exercise_name: s.exercise_name,
			reps: s.reps,
			weight_kg: s.weight_kg,
		}));
		for (const r of workoutPrs(prior, mine)) {
			out.set(r.exerciseName.trim().toLowerCase(), r.kinds);
		}
		return out;
	});

	// "vs last time" per exercise: the previous weighted session of this
	// exercise (before this workout) + how this session's heaviest set compares
	// to it. The progressive-overload cue the all-time PR chips can't give.
	const prevByExercise = $derived.by(() => {
		const out = new Map<string, { prev: ExerciseSession; deltaKg: number | null }>();
		if (!data || !isOwner) return out;
		const startedAt = data.workout.started_at;
		for (const b of blocks) {
			const key = b.name.trim().toLowerCase();
			if (out.has(key)) continue;
			const prev = previousExerciseSession(history, b.name, startedAt);
			if (!prev) continue;
			let thisTop: number | null = null;
			for (const st of b.sets) {
				if (st.weight_kg != null && st.weight_kg > 0 && (thisTop == null || st.weight_kg > thisTop)) {
					thisTop = st.weight_kg;
				}
			}
			const deltaKg = thisTop != null ? Math.round((thisTop - prev.topWeightKg) * 10) / 10 : null;
			out.set(key, { prev, deltaKg });
		}
		return out;
	});

	function prevSetLine(prev: ExerciseSession): string {
		const w = formatWeight(prev.topWeightKg);
		return prev.topWeightReps != null ? `${w} × ${prev.topWeightReps}` : w;
	}
	function deltaText(deltaKg: number): string {
		return `${deltaKg > 0 ? '+' : '−'}${formatWeight(Math.abs(deltaKg))}`;
	}

	function prLabel(kind: PrKind): string {
		return kind === 'weight'
			? t('gym.pr.weight')
			: kind === 'volume'
				? t('gym.pr.volume')
				: t('gym.pr.e1rm');
	}
	function setSummary(s: GymSet): string {
		const parts: string[] = [];
		if (s.reps != null) parts.push(`${s.reps}`);
		if (s.weight_kg != null) parts.push(formatWeight(s.weight_kg));
		const repWeight = parts.join(' × ');
		if (s.duration_s != null) {
			const dur = t('gym.durationValue', { seconds: s.duration_s });
			return repWeight ? `${repWeight} · ${dur}` : dur;
		}
		return repWeight;
	}

	// Header summary stats — total exercises / sets / working volume.
	const summary = $derived.by(() => {
		const sets = data?.sets ?? [];
		const names = new Set<string>();
		let volume = 0;
		for (const s of sets) {
			names.add(s.exercise_name.trim().toLowerCase());
			if (s.reps != null && s.weight_kg != null) volume += s.reps * s.weight_kg;
		}
		return { exercises: names.size, sets: sets.length, volume: Math.round(volume) };
	});

	// Planned-vs-actual review, reconstructed from the gym_workouts.metadata trio
	// written by the guided session (routine_id / gym_step_results /
	// gym_adherence — metadata.md). Self-hides when the keys are absent.
	const review = $derived.by((): { adherence: RoutineAdherence; stepResults: GymStepResult[] } | null => {
		const meta = (data?.workout as { metadata?: Record<string, unknown> | null } | undefined)?.metadata;
		if (!meta || typeof meta !== 'object') return null;
		const verdict = meta['gym_adherence'];
		const raw = meta['gym_step_results'];
		if (typeof verdict !== 'string' || !Array.isArray(raw) || raw.length === 0) return null;
		const stepResults = raw as GymStepResult[];
		const sets: SetAdherence[] = stepResults.map((s) => ({
			exerciseKey: s.exercise_key,
			setIndex: s.set_index,
			status: s.status,
			repsDelta: null,
			weightDeltaKg: null,
		}));
		const planned = stepResults.filter((s) => s.status !== 'extra');
		const completedCount = planned.filter((s) => s.status === 'hit').length;
		const plannedCount = planned.length;
		const adherence: RoutineAdherence = {
			sets,
			plannedCount,
			completedCount,
			adherencePct: plannedCount === 0 ? 0 : completedCount / plannedCount,
			verdict: verdict as RoutineVerdict,
		};
		return { adherence, stepResults };
	});

	function onUpdated() {
		editing = false;
		void load();
	}

	async function doDelete() {
		confirmingDelete = false;
		try {
			await deleteGymWorkout(id);
			showToast(t('gym.deleted'));
			goto('/gym');
		} catch (e) {
			console.error('delete gym workout failed', e);
			showToast(t('gym.saveFailed'));
		}
	}
</script>

<svelte:head><title>{data?.workout.title || t('gym.title')} — Threkir</title></svelte:head>

<div class="page">
	<a class="back-link" href="/gym">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>{t('gym.back')}
	</a>

	{#if loading}
		<div class="skel-head" aria-hidden="true">
			<span class="skel skel-line skel-w-50"></span>
			<span class="skel skel-line skel-w-30"></span>
		</div>
		{#each Array(2) as _, i (i)}
			<div class="card-elevated skel-block" aria-hidden="true">
				<span class="skel skel-line skel-w-40"></span>
				<span class="skel skel-line"></span>
				<span class="skel skel-line"></span>
			</div>
		{/each}
		<p class="sr-only" role="status">{t('shell.loading')}</p>
	{:else if notFound}
		<div class="card-elevated empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">search_off</span>
			<p class="empty-text">{t('gym.notFound')}</p>
			<a href="/gym" class="btn btn-outline">{t('gym.back')}</a>
		</div>
	{:else if data}
		<header class="page-header">
			<div class="head-text">
				<h1>{data.workout.title || t('gym.untitled')}</h1>
				<p class="head-date">{formatDate(data.workout.started_at)}</p>
			</div>
			{#if isOwner}
				<div class="head-actions">
					<button
						class="btn btn-secondary btn-sm"
						onclick={openRepeat}
						data-testid="gym-repeat-last"
					>
						<span class="material-symbols" aria-hidden="true">replay</span>
						{t('gym.routine.repeatLast')}
					</button>
					<button
						class="btn btn-secondary btn-sm"
						onclick={openSaveAsRoutine}
						data-testid="gym-save-as-routine"
					>
						<span class="material-symbols" aria-hidden="true">list_alt</span>
						{t('gym.routine.saveAsRoutine')}
					</button>
					<button class="btn btn-secondary btn-sm" onclick={() => (editing = true)}>
						<span class="material-symbols" aria-hidden="true">edit</span>
						{t('gym.edit')}
					</button>
					<button class="btn btn-danger btn-sm" onclick={() => (confirmingDelete = true)}>
						<span class="material-symbols" aria-hidden="true">delete</span>
						{t('gym.delete')}
					</button>
				</div>
			{/if}
		</header>

		<div class="summary-grid">
			<div class="card-elevated summary-stat">
				<span class="summary-value">{summary.exercises}</span>
				<span class="summary-label section-label">{t('gym.exercisesLabel')}</span>
			</div>
			<div class="card-elevated summary-stat">
				<span class="summary-value">{summary.sets}</span>
				<span class="summary-label section-label">{t('gym.setsLabel')}</span>
			</div>
			{#if summary.volume > 0}
				<div class="card-elevated summary-stat">
					<span class="summary-value">{formatWeight(summary.volume)}</span>
					<span class="summary-label section-label">{t('gym.volumeLabel')}</span>
				</div>
			{/if}
		</div>

		{#if review}
			<GymWorkoutReview adherence={review.adherence} stepResults={review.stepResults} />
		{/if}

		{#each blocks as block (block.name)}
			{@const lt = prevByExercise.get(block.name.trim().toLowerCase())}
			<section class="card-elevated exercise-block">
				<div class="block-head">
					<h2>{block.name}</h2>
					{#each prByExercise.get(block.name.trim().toLowerCase()) ?? [] as kind (kind)}
						<span class="pr-chip">
							<span class="material-symbols" aria-hidden="true">trophy</span>
							{prLabel(kind)}
						</span>
					{/each}
				</div>
				{#if lt}
					<a class="last-time" href="/gym/exercise?name={encodeURIComponent(block.name)}">
						<span class="lt-text">
							{t('gym.detail.lastTime', { date: formatDate(lt.prev.startedAt) })}: {prevSetLine(lt.prev)}
						</span>
						{#if lt.deltaKg != null && lt.deltaKg !== 0}
							<span class="lt-delta lt-{lt.deltaKg > 0 ? 'up' : 'down'}">
								<span class="material-symbols" aria-hidden="true">
									{lt.deltaKg > 0 ? 'trending_up' : 'trending_down'}
								</span>
								{deltaText(lt.deltaKg)}
							</span>
						{/if}
						<span class="material-symbols lt-chevron" aria-hidden="true">chevron_right</span>
					</a>
				{/if}
				<ol class="sets">
					<li class="sets-head" aria-hidden="true">
						<span class="set-n"></span>
						<span class="set-val section-label">{t('gym.reps')} × {t('gym.weightUnit', { unit: weightUnitLabel() })}</span>
						<span class="rpe section-label">{t('gym.rpe')}</span>
					</li>
					{#each block.sets as s (s.id)}
						<li>
							<span class="set-n">{t('gym.setN', { n: s.set_index + 1 })}</span>
							<span class="set-val">{setSummary(s) || '—'}</span>
							<span class="rpe">{s.rpe != null ? s.rpe : '—'}</span>
						</li>
					{/each}
				</ol>
			</section>
		{/each}

		{#if data.workout.notes}
			<section class="card-elevated exercise-block notes">
				<div class="block-head"><h2>{t('gym.notes')}</h2></div>
				<p>{data.workout.notes}</p>
			</section>
		{/if}
	{/if}
</div>

{#if data}
	<Modal open={editing} title={t('gym.editor.editTitle')} onclose={() => (editing = false)}>
		<GymEditor existing={data} onupdated={onUpdated} oncancel={() => (editing = false)} />
	</Modal>
{/if}

<Modal
	open={savingAsRoutine}
	title={t('gym.routine.editor.newTitle')}
	onclose={() => (savingAsRoutine = false)}
>
	<RoutineEditor
		seedExercises={routineSeed}
		seedTitle={routineSeedTitle}
		oncreated={onRoutineSaved}
		oncancel={() => (savingAsRoutine = false)}
	/>
</Modal>

<Modal open={repeating} title={t('gym.routine.repeatLast')} onclose={() => (repeating = false)}>
	<GymEditor seed={repeatSeed} oncreated={onRepeated} oncancel={() => (repeating = false)} />
</Modal>

<ConfirmDialog
	open={confirmingDelete}
	title={t('gym.deleteConfirm.title')}
	message={t('gym.deleteConfirm.body')}
	confirmLabel={t('gym.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmingDelete = false)}
/>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		color: var(--color-text-secondary);
		text-decoration: none;
		margin-bottom: var(--space-lg);
		font-size: 0.8rem;
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
		border-radius: var(--radius-sm);
	}

	.page-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin-bottom: var(--space-lg);
	}
	.head-text {
		min-width: 0;
	}
	.page-header h1 {
		margin: 0 0 var(--space-2xs);
	}
	.head-date {
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.head-actions {
		display: flex;
		gap: var(--space-sm);
		flex-shrink: 0;
	}
	.head-actions .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.head-actions .material-symbols {
		font-size: 1.05rem;
	}

	/* Summary stat strip — composes the shared .card-elevated; only the
	   stacked layout lives here. */
	.summary-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr));
		gap: var(--space-sm);
		margin-bottom: var(--space-lg);
	}
	.summary-stat {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		padding: var(--space-md) var(--space-lg);
	}
	.summary-value {
		font-size: 1.35rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}
	.summary-label {
		color: var(--color-text-tertiary);
	}

	.exercise-block {
		margin-bottom: var(--space-md);
	}
	.block-head {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
		flex-wrap: wrap;
	}
	.block-head h2 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
	}
	.pr-chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		color: var(--color-primary);
		background: var(--color-primary-light);
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
	}
	.pr-chip .material-symbols {
		font-size: 0.85rem;
	}

	/* "vs last time" hint — links to the exercise's full progression. */
	.last-time {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		margin: calc(-1 * var(--space-2xs)) 0 var(--space-md);
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		text-decoration: none;
		transition: background var(--transition-fast);
	}
	.last-time:hover {
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}
	.last-time:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.lt-text {
		font-variant-numeric: tabular-nums;
	}
	.lt-delta {
		display: inline-flex;
		align-items: center;
		gap: 0.1rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.lt-delta .material-symbols {
		font-size: 0.95rem;
	}
	.lt-up {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.lt-down {
		color: var(--color-text-secondary);
	}
	.lt-chevron {
		margin-inline-start: auto;
		font-size: 1.05rem;
		color: var(--color-text-tertiary);
	}

	.sets {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	.sets li {
		display: grid;
		grid-template-columns: 4rem 1fr 4rem;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-xs) 0;
	}
	.sets li + li:not(.sets-head) {
		border-top: 1px solid var(--color-border);
	}
	.sets-head {
		padding-bottom: var(--space-2xs);
	}
	.sets-head .set-val,
	.sets-head .rpe {
		color: var(--color-text-tertiary);
	}
	.set-n {
		font-size: 0.82rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		white-space: nowrap;
	}
	.set-val {
		font-variant-numeric: tabular-nums;
		font-weight: 500;
		color: var(--color-text);
	}
	.rpe {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		text-align: end;
		font-variant-numeric: tabular-nums;
	}

	.notes p {
		margin: 0;
		white-space: pre-wrap;
		color: var(--color-text);
		line-height: 1.6;
	}

	/* Empty / not-found card — composes .card-elevated; only the centered
	   layout lives here. */
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		text-align: center;
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-text {
		margin: 0;
		padding: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.empty-card .btn {
		margin-top: var(--space-xs);
	}

	/* Skeletons mirror the head + exercise-card heights. */
	.skel-head {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-bottom: var(--space-lg);
	}
	.skel-block {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
		height: 0.9rem;
	}
	.skel-line {
		width: 100%;
	}
	.skel-w-30 {
		width: 30%;
	}
	.skel-w-40 {
		width: 40%;
	}
	.skel-w-50 {
		width: 50%;
		height: 1.4rem;
	}
	@keyframes skel-shimmer {
		0% {
			background-position: 200% 0;
		}
		100% {
			background-position: -200% 0;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.skel {
			animation: none;
		}
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 40rem) {
		.page-header {
			flex-direction: column;
			gap: var(--space-sm);
		}
		.head-actions {
			width: 100%;
		}
		.head-actions .btn {
			flex: 1 1 0;
			justify-content: center;
		}
	}
</style>
