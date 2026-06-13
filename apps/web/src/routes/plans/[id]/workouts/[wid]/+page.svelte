<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { afterNavigate } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchWorkout,
		markWorkoutCompleted,
		fetchRelinkCandidateRuns,
		type RelinkCandidateRun
	} from '$lib/core/data';
	import { fmtHms, isWorkoutCompleted } from '$lib/training/training';
	import { workoutKindLabel } from '$lib/training/workout_labels';
	import { fmtKm, fmtPace } from '$lib/format/units.svelte';
	import { formatDateShort } from '$lib/format/time';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import type { PlanWorkout } from '$lib/types';
	import type { WorkoutStructure } from '$lib/training/training';

	let planId = $derived($page.params.id as string);
	let wid = $derived($page.params.wid as string);
	let workout = $state<PlanWorkout | null>(null);
	let loading = $state(true);
	let showUnlinkConfirm = $state(false);

	let showRelink = $state(false);
	let relinkLoading = $state(false);
	let relinkError = $state(false);
	let relinkCandidates = $state<RelinkCandidateRun[]>([]);
	let relinkSaving = $state(false);

	let cameFromPlan = $state(false);
	afterNavigate(({ from }) => {
		if (!cameFromPlan && from?.url.pathname === `/plans/${planId}`) {
			cameFromPlan = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromPlan) {
			e.preventDefault();
			history.back();
		}
	}

	async function load() {
		loading = true;
		workout = await fetchWorkout(wid);
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
	});

	let structure = $derived(
		(workout?.structure as unknown as WorkoutStructure | null) ?? null
	);

	function unlink() {
		if (!workout || !isWorkoutCompleted(workout)) return;
		showUnlinkConfirm = true;
	}

	let unlinking = $state(false);
	async function confirmUnlink() {
		if (!workout || unlinking) return;
		unlinking = true;
		try {
			await markWorkoutCompleted(workout.id, null);
			showUnlinkConfirm = false;
			await load();
		} catch (e) {
			console.error('markWorkoutCompleted(unlink) failed', e);
			showToast(t('workoutDetail.unlinkFailed'), 'error');
		} finally {
			unlinking = false;
		}
	}

	async function openRelink() {
		if (!workout) return;
		showRelink = true;
		relinkError = false;
		relinkLoading = true;
		relinkCandidates = [];
		try {
			relinkCandidates = await fetchRelinkCandidateRuns(workout);
		} catch (e) {
			console.error('fetchRelinkCandidateRuns failed', e);
			relinkError = true;
		} finally {
			relinkLoading = false;
		}
	}

	async function pickRelink(runId: string) {
		if (!workout || relinkSaving) return;
		relinkSaving = true;
		try {
			await markWorkoutCompleted(workout.id, runId);
			showRelink = false;
			await load();
		} catch (e) {
			console.error('re-link failed', e);
			relinkError = true;
		} finally {
			relinkSaving = false;
		}
	}

	// A step's "magnitude" for the proportional bar: distance when present,
	// else duration (walk-run sessions are fully time-based — see training.md).
	function mag(b: { distance_m?: number; duration_s?: number } | undefined): number {
		if (!b) return 0;
		return b.distance_m ?? b.duration_s ?? 0;
	}
	function repMag(r: WorkoutStructure['repeats']): number {
		return r?.distance_m ?? r?.duration_s ?? 0;
	}
	function recMag(r: WorkoutStructure['repeats']): number {
		return r?.recovery_distance_m ?? r?.recovery_duration_s ?? 0;
	}

	function intervalTotal(s: WorkoutStructure): number {
		return (
			mag(s.warmup) +
			(s.repeats ? s.repeats.count * (repMag(s.repeats) + recMag(s.repeats)) : 0) +
			mag(s.steady) +
			mag(s.cooldown)
		);
	}

	type SegmentVisual = {
		role: 'warmup' | 'work' | 'recovery' | 'steady' | 'cooldown';
		fraction: number;
	};

	function segmentVisuals(s: WorkoutStructure): SegmentVisual[] {
		const total = intervalTotal(s);
		if (total <= 0) return [];
		const out: SegmentVisual[] = [];
		if (s.warmup) out.push({ role: 'warmup', fraction: mag(s.warmup) / total });
		if (s.repeats) {
			for (let i = 0; i < s.repeats.count; i++) {
				out.push({ role: 'work', fraction: repMag(s.repeats) / total });
				if (i < s.repeats.count - 1) {
					out.push({ role: 'recovery', fraction: recMag(s.repeats) / total });
				}
			}
			out.push({ role: 'recovery', fraction: recMag(s.repeats) / total });
		}
		if (s.steady) out.push({ role: 'steady', fraction: mag(s.steady) / total });
		if (s.cooldown) out.push({ role: 'cooldown', fraction: mag(s.cooldown) / total });
		return out;
	}

	function fmtIsoDate(iso: string): string {
		const [y, m, d] = iso.split('-').map(Number);
		const dt = new Date(y, (m ?? 1) - 1, d ?? 1);
		return dt.toLocaleDateString(activeFormatLocale(), {
			weekday: 'long',
			day: 'numeric',
			month: 'long',
			year: 'numeric'
		});
	}

	let kindForChrome = $derived(workout?.kind ?? 'easy');
</script>

{#if loading}
	<div class="page" aria-busy="true" aria-label={t('workoutDetail.loadingWorkout')}>
		<span class="back-skel" aria-hidden="true">
			<span class="material-symbols">arrow_back</span>
			{t('workoutDetail.backToPlan')}
		</span>
		<div class="hero skel-hero" aria-hidden="true">
			<div class="skel-hero-text">
				<span class="skel skel-line skel-w-20"></span>
				<span class="skel skel-line skel-w-40"></span>
				<span class="skel skel-line skel-w-60"></span>
			</div>
		</div>
		<div class="skel-card" aria-hidden="true">
			<span class="skel skel-line skel-w-20"></span>
			<span class="skel skel-line skel-w-80"></span>
			<span class="skel skel-line skel-w-60"></span>
		</div>
	</div>
	<p class="sr-only" role="status">{t('workoutDetail.loadingWorkoutEllipsis')}</p>
{:else if !workout}
	<div class="page">
		<a class="back" href="/plans/{planId}">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{t('workoutDetail.backToPlan')}
		</a>
		<div class="empty-card">
			<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
			<h2>{t('workoutDetail.notFoundTitle')}</h2>
			<p class="empty-text">
				{t('workoutDetail.notFoundText')}
			</p>
			<div class="empty-actions">
				<a class="btn btn-primary" href="/plans/{planId}">{t('workoutDetail.returnToPlan')}</a>
			</div>
		</div>
	</div>
{:else}
	<div class="page" data-kind={kindForChrome}>
		<a class="back" href="/plans/{planId}" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{t('workoutDetail.backToPlan')}
		</a>

		<header class="hero">
			<div class="hero-body">
				<span class="kicker">{fmtIsoDate(workout.scheduled_date)}</span>
				<h1>{workoutKindLabel(workout.kind)}</h1>
				<p class="tagline">
					{#if structure}
						{t('workoutDetail.taglineStructured')}
					{:else if workout.kind === 'easy' || workout.kind === 'recovery'}
						{t('workoutDetail.taglineEasy')}
					{:else if workout.kind === 'long'}
						{t('workoutDetail.taglineLong')}
					{:else if workout.kind === 'rest'}
						{t('workoutDetail.taglineRest')}
					{:else if workout.kind === 'race'}
						{t('workoutDetail.taglineRace')}
					{:else}
						{t('workoutDetail.taglineFreeForm')}
					{/if}
				</p>
				<div class="meta">
					{#if workout.target_distance_m != null}
						<div class="metric">
							<span class="m-label">{t('workoutDetail.distance')}</span>
							<strong>{fmtKm(workout.target_distance_m, 2)}</strong>
						</div>
					{/if}
					{#if workout.target_duration_seconds}
						<div class="metric">
							<span class="m-label">{t('workoutDetail.duration')}</span>
							<strong>{fmtHms(workout.target_duration_seconds)}</strong>
						</div>
					{/if}
					{#if workout.target_pace_sec_per_km}
						<div class="metric pace-metric">
							<span class="m-label">{t('workoutDetail.targetPace')}</span>
							<strong>
								{fmtPace(workout.target_pace_sec_per_km)}
								{#if workout.target_pace_end_sec_per_km && workout.target_pace_end_sec_per_km !== workout.target_pace_sec_per_km}
									<span class="arrow">→</span>
									{fmtPace(workout.target_pace_end_sec_per_km)}
								{/if}
							</strong>
							<span class="pace-extras">
								{#if workout.target_pace_tolerance_sec}
									<span class="tol">±{workout.target_pace_tolerance_sec}s</span>
								{/if}
								{#if workout.pace_zone}
									<span class="zone">{workout.pace_zone}</span>
								{/if}
							</span>
						</div>
					{/if}
				</div>
			</div>
			{#if isWorkoutCompleted(workout)}
				<div class="completed-card">
					<span class="material-symbols" aria-hidden="true">check_circle</span>
					<span class="completed-label">{t('workoutDetail.completed')}</span>
					<div class="completed-actions">
						{#if workout.completed_run_id}
							<button class="btn-ghost" onclick={openRelink}>
								{t('workoutDetail.relink')}
							</button>
						{/if}
						<button class="btn-ghost" onclick={unlink}>
							{workout.completed_run_id ? t('workoutDetail.unlink') : t('workoutDetail.markNotDone')}
						</button>
					</div>
				</div>
			{/if}
		</header>

		{#if workout.notes}
			<section class="card">
				<h3>{t('workoutDetail.notes')}</h3>
				<p>{workout.notes}</p>
			</section>
		{/if}

		{#if structure}
			<section class="card structure-card">
				<h3>{t('workoutDetail.structure')}</h3>
				<div class="timeline" role="img" aria-label={t('workoutDetail.segmentTimeline')}>
					{#each segmentVisuals(structure) as seg, i (i)}
						<span
							class="tl-seg tl-{seg.role}"
							style="flex: {Math.max(seg.fraction, 0.01)};"
							title={seg.role}
						></span>
					{/each}
				</div>
				<ol class="steps">
					{#if structure.warmup}
						<li class="step step-warmup">
							<span class="step-kind">{t('workoutDetail.warmup')}</span>
							<span class="step-body">
								<span class="step-main">{fmtKm(structure.warmup.distance_m, 1)}</span>
								<span class="step-pace">{t('workoutDetail.atEasy')}</span>
							</span>
						</li>
					{/if}
					{#if structure.repeats}
						<li class="step step-work">
							<span class="step-kind">{t('workoutDetail.repeats')}</span>
							<span class="step-body">
								<span class="step-main">
									{t('workoutDetail.repeatsDetail', {
										count: structure.repeats.count,
										distance: fmtKm(structure.repeats.distance_m, 2),
										pace: fmtPace(structure.repeats.pace_sec_per_km),
										recoveryDistance: fmtKm(structure.repeats.recovery_distance_m, 2),
										recoveryPace: structure.repeats.recovery_pace ?? ''
									})}
								</span>
							</span>
						</li>
					{/if}
					{#if structure.steady}
						<li class="step step-steady">
							<span class="step-kind">{t('workoutDetail.steady')}</span>
							<span class="step-body">
								<span class="step-main">{fmtKm(structure.steady.distance_m, 1)}</span>
								<span class="step-pace">{t('workoutDetail.atPace', { pace: fmtPace(structure.steady.pace_sec_per_km) })}</span>
							</span>
						</li>
					{/if}
					{#if structure.cooldown}
						<li class="step step-cooldown">
							<span class="step-kind">{t('workoutDetail.cooldown')}</span>
							<span class="step-body">
								<span class="step-main">{fmtKm(structure.cooldown.distance_m, 1)}</span>
								<span class="step-pace">{t('workoutDetail.atEasy')}</span>
							</span>
						</li>
					{/if}
				</ol>
				<p class="total">{t('workoutDetail.total', { value: fmtKm(intervalTotal(structure), 2) })}</p>
			</section>
		{:else if workout.kind !== 'rest'}
			<section class="card structure-empty">
				<h3>{t('workoutDetail.planIt')}</h3>
				<div class="structure-empty-body">
					<span class="material-symbols" aria-hidden="true">timeline</span>
					<div>
						<strong>{t('workoutDetail.freeFormRun')}</strong>
						<span class="muted">
							{t('workoutDetail.freeFormRunHint')}
						</span>
					</div>
				</div>
			</section>
		{/if}

		<section class="card advice">
			<h3>{t('workoutDetail.howToRunIt')}</h3>
			{#if workout.kind === 'easy' || workout.kind === 'recovery'}
				<p>{t('workoutDetail.adviceEasy')}</p>
			{:else if workout.kind === 'long'}
				<p>
					{t('workoutDetail.adviceLong')}
				</p>
			{:else if workout.kind === 'tempo'}
				<p>
					{t('workoutDetail.adviceTempo')}
				</p>
			{:else if workout.kind === 'interval'}
				<p>
					{t('workoutDetail.adviceInterval')}
				</p>
			{:else if workout.kind === 'marathon_pace'}
				<p>
					{t('workoutDetail.adviceMarathonPace')}
				</p>
			{:else if workout.kind === 'race'}
				<p>{t('workoutDetail.adviceRace')}</p>
			{:else}
				<p>{t('workoutDetail.adviceRest')}</p>
			{/if}
		</section>
	</div>

<ConfirmDialog
	open={showUnlinkConfirm}
	title={t('workoutDetail.unlinkRunTitle')}
	message={t('workoutDetail.unlinkRunMessage')}
	confirmLabel={t('workoutDetail.unlink')}
	onconfirm={confirmUnlink}
	oncancel={() => showUnlinkConfirm = false}
	danger
/>

<Modal
	open={showRelink}
	onclose={() => (showRelink = false)}
	title={t('workoutDetail.relinkTitle')}
	narrow
	data-testid="relink-modal"
>
	<p class="relink-hint">{t('workoutDetail.relinkHint')}</p>
	{#if relinkLoading}
		<p class="relink-status" role="status">{t('workoutDetail.relinkLoading')}</p>
	{:else if relinkError}
		<p class="relink-status relink-error" role="alert">{t('workoutDetail.relinkError')}</p>
	{:else if relinkCandidates.length === 0}
		<p class="relink-status">{t('workoutDetail.relinkEmpty')}</p>
	{:else}
		<ul class="relink-list">
			{#each relinkCandidates as run (run.id)}
				<li>
					<button
						class="relink-run"
						class:current={run.id === workout?.completed_run_id}
						data-run-id={run.id}
						disabled={relinkSaving}
						onclick={() => pickRelink(run.id)}
					>
						<span class="relink-run-date">{formatDateShort(run.started_at)}</span>
						<span class="relink-run-stats">
							{fmtKm(run.distance_m, 2)} · {fmtHms(run.duration_s)}
						</span>
						{#if run.id === workout?.completed_run_id}
							<span class="relink-current-tag">{t('workoutDetail.relinkCurrent')}</span>
						{/if}
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</Modal>
{/if}

<style>
	.page {
		max-width: 56rem;
		padding: var(--space-xl) var(--space-2xl);

		/* Per-kind tint applied to hero accent, step bars, and timeline.
		   Defaults to the primary palette; specific kinds remap below. */
		--kind-tint: var(--color-primary);
	}
	.page[data-kind="tempo"]      { --kind-tint: #C98ECF; }
	.page[data-kind="interval"]   { --kind-tint: #D97A54; }
	.page[data-kind="marathon_pace"] { --kind-tint: #E6A96B; }
	.page[data-kind="long"]       { --kind-tint: var(--color-primary); }
	.page[data-kind="easy"]       { --kind-tint: var(--color-text-secondary); }
	.page[data-kind="recovery"]   { --kind-tint: var(--color-text-tertiary); }
	.page[data-kind="race"]       { --kind-tint: var(--color-primary); }
	.page[data-kind="rest"]       { --kind-tint: var(--color-text-tertiary); }

	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		text-decoration: none;
	}
	.back:hover { color: var(--color-primary); }
	.back .material-symbols { font-size: 1.05rem; }

	.hero {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		gap: var(--space-lg);
		align-items: start;
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--kind-tint) 14%, var(--color-surface)) 0%,
			var(--color-surface) 70%
		);
		border: 1px solid color-mix(in srgb, var(--kind-tint) 30%, var(--color-border));
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-sm);
		padding: var(--space-lg) var(--space-xl);
		margin-bottom: var(--space-md);
	}
	.hero-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.hero h1 {
		font-size: 1.65rem;
		font-weight: 700;
		margin: 0;
		line-height: 1.15;
	}
	.kicker {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--kind-tint);
		font-weight: 700;
		text-transform: uppercase;
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		max-width: 44rem;
		margin: var(--space-2xs) 0 var(--space-xs) 0;
	}
	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: 2rem;
		margin-top: var(--space-2xs);
	}
	.metric {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.m-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		font-weight: 600;
	}
	.metric strong {
		font-size: 1.15rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.pace-extras {
		display: inline-flex;
		gap: 0.4rem;
		align-items: center;
		margin-top: 0.15rem;
	}
	.tol {
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
		font-variant-numeric: tabular-nums;
	}
	.arrow {
		color: var(--color-text-tertiary);
		margin: 0 0.25rem;
		font-weight: 400;
	}
	.zone {
		display: inline-block;
		padding: 0.1rem 0.5rem;
		border-radius: var(--radius-sm);
		background: color-mix(in srgb, var(--kind-tint) 18%, transparent);
		color: var(--kind-tint);
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.05em;
		white-space: nowrap;
	}
	.completed-card {
		background: color-mix(in srgb, var(--color-success) 14%, transparent);
		color: var(--color-success);
		padding: 0.55rem 0.85rem;
		border: 1px solid color-mix(in srgb, var(--color-success) 35%, transparent);
		border-radius: var(--radius-md);
		display: inline-flex;
		align-items: center;
		gap: 0.45rem;
		font-weight: 700;
		flex-shrink: 0;
	}
	.completed-card .material-symbols { font-size: 1.15rem; }
	.completed-card .completed-label { font-size: 0.92rem; }
	.completed-actions {
		display: inline-flex;
		gap: 0.65rem;
		align-items: center;
	}
	.btn-ghost {
		background: none;
		border: none;
		color: var(--color-success);
		font-weight: 600;
		text-decoration: underline;
		cursor: pointer;
		font-size: 0.85rem;
	}

	.relink-hint {
		margin: 0 0 var(--space-sm) 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.5;
	}
	.relink-status {
		margin: var(--space-sm) 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.relink-error { color: var(--color-danger); }
	.relink-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.relink-run {
		width: 100%;
		display: flex;
		align-items: baseline;
		gap: 0.6rem;
		padding: 0.6rem 0.8rem;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		cursor: pointer;
		text-align: start;
		font: inherit;
		color: var(--color-text);
	}
	.relink-run:hover:not(:disabled) {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 8%, var(--color-bg-secondary));
	}
	.relink-run:disabled { opacity: 0.6; cursor: default; }
	.relink-run.current { border-color: var(--color-success); }
	.relink-run-date {
		font-weight: 700;
		font-size: 0.92rem;
	}
	.relink-run-stats {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
		font-size: 0.9rem;
	}
	.relink-current-tag {
		margin-inline-start: auto;
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-success);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-md);
	}
	.card h3 {
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm) 0;
	}
	.card p { line-height: 1.55; margin: 0; }

	.timeline {
		display: flex;
		height: 0.55rem;
		gap: 2px;
		margin-bottom: var(--space-sm);
		border-radius: 9999px;
		overflow: hidden;
		background: var(--color-bg-secondary);
	}
	.tl-seg { display: block; min-width: 0.15rem; }
	.tl-warmup   { background: color-mix(in srgb, var(--color-text-secondary) 55%, transparent); }
	.tl-work     { background: var(--kind-tint); }
	.tl-recovery { background: color-mix(in srgb, var(--kind-tint) 25%, var(--color-bg-tertiary)); }
	.tl-steady   { background: var(--kind-tint); }
	.tl-cooldown { background: color-mix(in srgb, var(--color-text-secondary) 35%, transparent); }

	.steps {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.step {
		display: grid;
		grid-template-columns: 6rem 1fr;
		gap: 0.8rem;
		align-items: baseline;
		padding: 0.6rem 0.85rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		border-inline-start: 3px solid var(--seg-color, var(--color-text-tertiary));
	}
	.step-warmup   { --seg-color: color-mix(in srgb, var(--color-text-secondary) 55%, transparent); }
	.step-work     { --seg-color: var(--kind-tint); }
	.step-steady   { --seg-color: var(--kind-tint); }
	.step-cooldown { --seg-color: color-mix(in srgb, var(--color-text-secondary) 35%, transparent); }
	.step-kind {
		font-weight: 700;
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--seg-color, var(--color-primary));
	}
	.step-body {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0.4rem;
		min-width: 0;
	}
	.step-main {
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.step-pace {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
		font-size: 0.92rem;
	}
	.total {
		margin: var(--space-sm) 0 0 0;
		color: var(--color-text-secondary);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.structure-empty .structure-empty-body {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) 0;
	}
	.structure-empty .material-symbols {
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.structure-empty div {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.structure-empty strong {
		color: var(--color-text);
		font-size: 0.95rem;
	}
	.muted { color: var(--color-text-tertiary); font-size: 0.88rem; }

	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
	}
	.empty-card h2 {
		margin: 0;
		font-size: 1.2rem;
		font-weight: 700;
	}
	.empty-mark {
		display: block;
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-sm);
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.empty-actions {
		display: flex;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}

	.back-skel {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		opacity: 0.5;
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
	}
	.skel-line { height: 0.75rem; }
	.skel-w-20 { width: 20%; }
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	.skel-w-80 { width: 80%; }
	.skel-hero {
		grid-template-columns: 1fr;
	}
	.skel-hero-text {
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
		min-width: 0;
	}
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
		margin-bottom: var(--space-md);
	}
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
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

	@media (max-width: 50rem) {
		.hero {
			grid-template-columns: 1fr;
		}
		.completed-card { align-self: stretch; justify-content: center; }
		.step {
			grid-template-columns: 1fr;
			gap: 0.25rem;
		}
	}
</style>
