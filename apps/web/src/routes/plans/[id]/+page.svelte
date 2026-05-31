<script lang="ts">
	import { onMount } from 'svelte';
	import { afterNavigate } from '$app/navigation';
	import { page } from '$app/stores';
	import { fetchPlan, fetchMyClubs, fetchRuns, publishPlanAsTemplate } from '$lib/core/data';
	import WorkoutEditor from '$lib/components/WorkoutEditor.svelte';
	import PlanMetaEditor from '$lib/components/PlanMetaEditor.svelte';
	import PlanCalendar from '$lib/components/PlanCalendar.svelte';
	import RaceDayPanel from '$lib/components/RaceDayPanel.svelte';
	import { daysUntilRace } from '$lib/runs/race_day';
	import type { Run } from '$lib/types';
	import { showToast } from '$lib/stores/toast.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fmtHms,
		isWorkoutCompleted,
		PHASE_LABEL,
		WORKOUT_KIND_LABEL,
		parseISO,
		todayISO
	} from '$lib/training/training';
	import { fmtKm, fmtPace } from '$lib/format/units.svelte';
	import type { TrainingPlan, PlanWeek, PlanWorkout, ClubWithMeta } from '$lib/types';

	let id = $derived($page.params.id as string);
	let plan = $state<TrainingPlan | null>(null);
	let weeks = $state<PlanWeek[]>([]);
	let workouts = $state<PlanWorkout[]>([]);
	let loading = $state(true);
	let editing = $state<PlanWorkout | null>(null);

	let adminClubs = $state<ClubWithMeta[]>([]);
	let publishingTo = $state('');
	let editingPlanMeta = $state(false);
	let recentRuns = $state<Run[]>([]);

	let isOwner = $derived(plan != null && plan.user_id === auth.user?.id);

	let showRaceDay = $derived.by(() => {
		if (!plan) return false;
		const days = daysUntilRace(plan.end_date, new Date());
		// Show within 21 days of race day (Strava's "race week" surface
		// is +/-14; we widen it slightly to cover a proper taper).
		return days >= 0 && days <= 21;
	});

	/// The user usually arrives here from /dashboard's plan-hero CTA or
	/// /plans. Honour the back-snapshot pattern so the parent's scroll +
	/// filter state survives a round trip. Captured on first afterNavigate
	/// so SvelteKit's own forward navigations inside this page don't
	/// overwrite the source.
	let backHref = $state('/plans');
	let backLabel = $state('All plans');
	let cameFromKnownParent = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromKnownParent || !from) return;
		if (from.url.pathname === '/dashboard') {
			backHref = '/dashboard';
			backLabel = 'Dashboard';
			cameFromKnownParent = true;
		} else if (from.url.pathname === '/plans') {
			backHref = '/plans';
			backLabel = 'All plans';
			cameFromKnownParent = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromKnownParent) {
			e.preventDefault();
			history.back();
		}
	}

	async function load() {
		loading = true;
		const res = await fetchPlan(id);
		plan = res.plan;
		weeks = res.weeks;
		workouts = res.workouts;
		loading = false;
		if (plan != null) {
			const days = daysUntilRace(plan.end_date, new Date());
			if (days >= 0 && days <= 21) {
				// Lazy-load the runner's recent runs so the Race Day panel
				// can predict a finish time from a Riegel projection.
				recentRuns = await fetchRuns({ limit: 50 });
			}
		}
	}

	onMount(async () => {
		// Same poll-for-auth shape as /runs/[id], /routes/[id], etc.
		// auth-store flips loading=false before fetchUser resolves, so
		// the publish-as-template gate below must wait for `auth.user`
		// to actually be set or the admin-clubs fetch silently no-ops
		// for the plan owner.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
		// Only owners-of-this-plan see the publish-as-template control,
		// and only when they have at least one club they admin.
		if (auth.user?.id && plan?.user_id === auth.user.id) {
			const clubs = await fetchMyClubs();
			adminClubs = clubs.filter(
				(c) => c.viewer_role === 'owner' || c.viewer_role === 'admin'
			);
		}
	});

	async function publishAsTemplate() {
		if (!plan || !publishingTo) return;
		try {
			await publishPlanAsTemplate(plan.id, publishingTo);
			showToast('Plan published as a club template. Your personal plan is unchanged.');
			publishingTo = '';
			// No reload needed — the source plan stayed put. The new
			// template lives on the club's Templates tab.
		} catch (e) {
			showToast(`Failed to publish: ${e}`, 'error');
		}
	}

	let workoutsByWeek = $derived.by(() => {
		const m = new Map<string, PlanWorkout[]>();
		for (const w of workouts) {
			const list = m.get(w.week_id) ?? [];
			list.push(w);
			m.set(w.week_id, list);
		}
		return m;
	});

	let today = $derived(todayISO());

	let todayWorkout = $derived(
		workouts.find((w) => w.scheduled_date === today) ?? null
	);

	/// When today is between plans (rest day or pre-start), fall back to
	/// the next scheduled non-rest workout so the primary card always
	/// answers "what's next?" instead of silently vanishing.
	let nextWorkout = $derived.by(() => {
		if (todayWorkout) return null;
		return workouts.find((w) => w.scheduled_date > today && w.kind !== 'rest') ?? null;
	});

	let currentWeekIndex = $derived.by(() => {
		if (!plan) return null;
		const dayIndex = Math.floor(
			(parseISO(today).getTime() - parseISO(plan.start_date).getTime()) /
				(1000 * 60 * 60 * 24)
		);
		if (dayIndex < 0) return 0;
		return Math.min(weeks.length - 1, Math.floor(dayIndex / 7));
	});

	/// Race-date relation derived from start/end in the plan's local-date
	/// frame. Mirrors the dashboard plan-hero so the two surfaces agree.
	let planPosition = $derived.by(() => {
		if (!plan) return null;
		const start = parseISO(plan.start_date);
		const end = parseISO(plan.end_date);
		const t = parseISO(today);
		const dayMs = 86_400_000;
		const totalWeeks = weeks.length > 0 ? weeks.length : 1;
		const weekIndex = (currentWeekIndex ?? 0) + 1;
		const totalDays = Math.max(1, Math.round((end.getTime() - start.getTime()) / dayMs) + 1);
		let calendarPct: number;
		if (t <= start) calendarPct = 0;
		else if (t >= end) calendarPct = 100;
		else calendarPct = Math.round(((t.getTime() - start.getTime()) / (end.getTime() - start.getTime())) * 100);
		let relation: string;
		let raceState: 'upcoming' | 'today' | 'past';
		if (t < start) {
			const d = Math.round((start.getTime() - t.getTime()) / dayMs);
			relation = d === 1 ? 'Starts tomorrow' : `Starts in ${d} days`;
			raceState = 'upcoming';
		} else if (t > end) {
			relation = 'Race day past';
			raceState = 'past';
		} else {
			const d = Math.round((end.getTime() - t.getTime()) / dayMs);
			if (d === 0) {
				relation = 'Race day';
				raceState = 'today';
			} else if (d === 1) {
				relation = 'Race tomorrow';
				raceState = 'upcoming';
			} else {
				relation = `Race in ${d} days`;
				raceState = 'upcoming';
			}
		}
		return { weekIndex, totalWeeks, totalDays, calendarPct, relation, raceState };
	});

	let completed = $derived(workouts.filter(isWorkoutCompleted).length);
	let totalActive = $derived(workouts.filter((w) => w.kind !== 'rest').length);
	let pct = $derived(totalActive === 0 ? 0 : Math.round((completed / totalActive) * 100));

	/// Pre-compute the conic-gradient stop so the progress ring renders
	/// as a real fill, not a static border. The static `5px` border was
	/// indistinguishable from a chrome flourish.
	let progressGradient = $derived(
		`conic-gradient(var(--color-primary) ${pct * 3.6}deg, color-mix(in srgb, var(--color-primary) 14%, var(--color-border)) 0deg)`
	);

	const kindColor: Record<string, string> = {
		easy: 'var(--color-text-secondary)',
		long: 'var(--color-primary)',
		recovery: 'var(--color-text-tertiary)',
		tempo: '#C98ECF',
		interval: '#D97A54',
		marathon_pace: '#E6A96B',
		race: 'var(--color-primary)',
		rest: 'var(--color-border)'
	};

	function dayOfWeek(iso: string): string {
		const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
		return names[parseISO(iso).getDay()];
	}

	function fmtRaceDate(iso: string): string {
		const [y, m, d] = iso.split('-').map(Number);
		const dt = new Date(y, (m ?? 1) - 1, d ?? 1);
		return dt.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
	}

	function workoutAriaLabel(wo: PlanWorkout): string {
		const dow = dayOfWeek(wo.scheduled_date);
		const kind = WORKOUT_KIND_LABEL[wo.kind as keyof typeof WORKOUT_KIND_LABEL] ?? wo.kind;
		const dist = wo.target_distance_m != null ? `, ${fmtKm(wo.target_distance_m)}` : '';
		const done = isWorkoutCompleted(wo) ? ', completed' : '';
		return `${dow}: ${kind}${dist}${done}`;
	}
</script>

{#if loading}
	<div class="page" aria-busy="true" aria-label="Loading plan">
		<div class="back-skel skeleton-shimmer"></div>
		<div class="hero-skel skeleton-shimmer"></div>
		<div class="today-skel skeleton-shimmer"></div>
		<div class="week-skel skeleton-shimmer"></div>
		<div class="week-skel skeleton-shimmer"></div>
		<div class="week-skel skeleton-shimmer"></div>
	</div>
{:else if !plan}
	<div class="page">
		<a class="back" href={backHref} onclick={handleBack}>
			<span class="material-symbols">arrow_back</span>
			{backLabel}
		</a>
		<div class="empty">
			<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
			<h3>Plan not found</h3>
			<p>This plan may have been deleted, or you may not have access to it.</p>
			<a href="/plans" class="btn btn-primary">Back to your plans</a>
		</div>
	</div>
{:else}
	<div class="page">
		<a class="back" href={backHref} onclick={handleBack}>
			<span class="material-symbols">arrow_back</span>
			{backLabel}
		</a>

		<header class="hero" class:race-today={planPosition?.raceState === 'today'}>
			<div class="hero-body">
				<span class="hero-eyebrow">Training plan</span>
				<div class="hero-title-row">
					<h1>{plan.name}</h1>
					{#if isOwner && !plan.is_template}
						<button
							type="button"
							class="btn btn-outline btn-sm hero-edit"
							aria-label="Edit plan name, goal time, and rules"
							onclick={() => (editingPlanMeta = true)}
						>
							<span class="material-symbols">edit</span>
							Edit plan
						</button>
					{/if}
				</div>
				<div class="hero-chips">
					{#if plan.parent_template_id}
						<a class="chip chip-link" href="/plans/{plan.parent_template_id}">
							<span class="material-symbols">link</span>
							Cloned from a template
						</a>
					{/if}
					{#if plan.is_template && plan.club_id}
						<span class="chip">
							<span class="material-symbols">groups</span>
							Club template
						</span>
					{/if}
				</div>
				<div class="meta">
					<span>
						<span class="material-symbols">flag</span>
						{fmtKm(plan.goal_distance_m, 1)}
					</span>
					{#if plan.goal_time_seconds}
						<span>
							<span class="material-symbols">timer</span>
							{fmtHms(plan.goal_time_seconds)}
						</span>
					{/if}
					{#if plan.vdot}
						<span>
							<span class="material-symbols">trending_up</span>
							VDOT {Number(plan.vdot).toFixed(1)}
						</span>
					{/if}
					{#if planPosition}
						<span>
							<span class="material-symbols">event</span>
							{fmtRaceDate(plan.end_date)}
						</span>
					{/if}
				</div>
			</div>
			<div class="hero-position">
				{#if planPosition}
					<span class="week-pill">
						Week {planPosition.weekIndex} <em>of {planPosition.totalWeeks}</em>
					</span>
					<span
						class="relation-pill"
						class:race-today={planPosition.raceState === 'today'}
						class:race-past={planPosition.raceState === 'past'}
					>
						{planPosition.relation}
					</span>
				{/if}
				<div
					class="progress-ring"
					style="background: {progressGradient}"
					role="progressbar"
					aria-label="Workout completion"
					aria-valuemin="0"
					aria-valuemax="100"
					aria-valuenow={pct}
				>
					<div class="progress-inner">
						<span class="pct">{pct}%</span>
						<span class="done">{completed} / {totalActive}</span>
					</div>
				</div>
			</div>
		</header>

		{#if planPosition}
			<div class="calendar-bar" aria-hidden="true">
				<span
					class="calendar-fill"
					style="width: {planPosition.calendarPct}%"
				></span>
			</div>
		{/if}

		{#if Array.isArray(plan.rules) && plan.rules.length > 0}
			<aside class="rules-card">
				<h3>Rules</h3>
				<ul>
					{#each plan.rules as r}
						<li>{r}</li>
					{/each}
				</ul>
			</aside>
		{/if}

		{#if showRaceDay && plan != null}
			<RaceDayPanel
				raceDate={plan.end_date}
				distanceM={plan.goal_distance_m}
				goalTimeSec={plan.goal_time_seconds}
				{recentRuns}
			/>
		{/if}

		{#if todayWorkout}
			<section class="today">
				<button
					class="today-link"
					type="button"
					aria-label="Edit today's workout: {WORKOUT_KIND_LABEL[todayWorkout.kind as keyof typeof WORKOUT_KIND_LABEL] ?? todayWorkout.kind}"
					onclick={() => (editing = todayWorkout)}
				>
					<div class="today-icon" class:done={isWorkoutCompleted(todayWorkout)}>
						{#if isWorkoutCompleted(todayWorkout)}
							<span class="material-symbols">check_circle</span>
						{:else if todayWorkout.kind === 'rest'}
							<span class="material-symbols">self_improvement</span>
						{:else}
							<span class="material-symbols">directions_run</span>
						{/if}
					</div>
					<div class="today-body">
						<span class="today-label">Today</span>
						<span class="today-kind">
							{WORKOUT_KIND_LABEL[todayWorkout.kind as keyof typeof WORKOUT_KIND_LABEL] ?? todayWorkout.kind}
						</span>
						<div class="today-meta">
							{#if todayWorkout.target_distance_m != null}
								<span>{fmtKm(todayWorkout.target_distance_m)}</span>
							{/if}
							{#if todayWorkout.target_pace_sec_per_km}
								<span>@ {fmtPace(todayWorkout.target_pace_sec_per_km)}</span>
							{/if}
							{#if isWorkoutCompleted(todayWorkout)}
								<span class="today-done">Completed</span>
							{/if}
						</div>
						{#if todayWorkout.notes}
							<p class="today-notes">{todayWorkout.notes}</p>
						{/if}
					</div>
					<span class="material-symbols today-arrow">chevron_right</span>
				</button>
			</section>
		{:else if nextWorkout}
			<section class="today">
				<button
					class="today-link"
					type="button"
					aria-label="Edit next workout"
					onclick={() => (editing = nextWorkout)}
				>
					<div class="today-icon">
						<span class="material-symbols">event_upcoming</span>
					</div>
					<div class="today-body">
						<span class="today-label">Next up</span>
						<span class="today-kind">
							{WORKOUT_KIND_LABEL[nextWorkout.kind as keyof typeof WORKOUT_KIND_LABEL] ?? nextWorkout.kind}
						</span>
						<div class="today-meta">
							<span>{dayOfWeek(nextWorkout.scheduled_date)} · {nextWorkout.scheduled_date}</span>
							{#if nextWorkout.target_distance_m != null}
								<span>{fmtKm(nextWorkout.target_distance_m)}</span>
							{/if}
							{#if nextWorkout.target_pace_sec_per_km}
								<span>@ {fmtPace(nextWorkout.target_pace_sec_per_km)}</span>
							{/if}
						</div>
					</div>
					<span class="material-symbols today-arrow">chevron_right</span>
				</button>
			</section>
		{:else if planPosition?.raceState === 'today'}
			<section class="today">
				<div class="today-link today-static">
					<div class="today-icon">
						<span class="material-symbols">emoji_events</span>
					</div>
					<div class="today-body">
						<span class="today-label">Race day</span>
						<span class="today-kind">Go and run it.</span>
					</div>
				</div>
			</section>
		{:else}
			<section class="today">
				<div class="today-link today-static">
					<div class="today-icon">
						<span class="material-symbols">self_improvement</span>
					</div>
					<div class="today-body">
						<span class="today-label">Today</span>
						<span class="today-kind">Rest day</span>
						<div class="today-meta">
							<span>No workout scheduled — recover and roll into tomorrow.</span>
						</div>
					</div>
				</div>
			</section>
		{/if}

		{#if !plan.is_template && adminClubs.length > 0 && plan.user_id === auth.user?.id}
			<section class="publish-row">
				<span class="publish-label">Publish as a club template:</span>
				<select bind:value={publishingTo} aria-label="Club to publish to">
					<option value="">— pick a club —</option>
					{#each adminClubs as c (c.id)}
						<option value={c.id}>{c.name}</option>
					{/each}
				</select>
				<button
					class="btn btn-outline"
					type="button"
					disabled={!publishingTo}
					onclick={publishAsTemplate}
				>
					Publish
				</button>
			</section>
		{/if}

		<section class="calendar-section">
			<h2 class="section-title">Calendar</h2>
			<PlanCalendar
				startDate={plan.start_date}
				endDate={plan.end_date}
				{workouts}
				planId={plan.id}
				onSelect={(wo) => (editing = wo)}
			/>
		</section>

		<section class="weeks">
			<h2 class="section-title">Week by week</h2>
			{#each weeks as w (w.id)}
				{@const weekWorkouts = workoutsByWeek.get(w.id) ?? []}
				{@const weekActive = weekWorkouts.filter((x) => x.kind !== 'rest')}
				{@const weekDone = weekWorkouts.filter(isWorkoutCompleted).length}
				{@const isPast = w.week_index < (currentWeekIndex ?? -1)}
				{@const isFuture = w.week_index > (currentWeekIndex ?? -1)}
				<article
					class="week"
					class:current={w.week_index === currentWeekIndex}
					class:past={isPast}
					class:future={isFuture}
				>
					<header class="week-header">
						<div class="week-ident">
							<span class="week-num">Week {w.week_index + 1}</span>
							<span class="week-phase">
								{PHASE_LABEL[w.phase as keyof typeof PHASE_LABEL] ?? w.phase}
							</span>
						</div>
						<div class="week-stats">
							<span class="week-progress">
								{weekDone}<em> / {weekActive.length}</em> done
							</span>
							<span class="week-volume">{fmtKm(w.target_volume_m, 0)}</span>
						</div>
					</header>
					{#if w.notes}
						<p class="week-note">{w.notes}</p>
					{/if}
					<div class="day-grid">
						{#each weekWorkouts as wo (wo.id)}
							<div
								class="day"
								class:today={wo.scheduled_date === today}
								class:completed={isWorkoutCompleted(wo)}
								class:rest={wo.kind === 'rest'}
								class:past={wo.scheduled_date < today}
								style="--kind-color: {kindColor[wo.kind] ?? 'var(--color-text-secondary)'}"
							>
								<button
									class="day-link"
									type="button"
									aria-label={workoutAriaLabel(wo)}
									onclick={() => (editing = wo)}
								>
									<span class="dow">{dayOfWeek(wo.scheduled_date)}</span>
									<span class="kind">
										{WORKOUT_KIND_LABEL[wo.kind as keyof typeof WORKOUT_KIND_LABEL] ?? wo.kind}
									</span>
									{#if wo.target_distance_m != null && wo.kind !== 'rest'}
										<span class="dist">{fmtKm(wo.target_distance_m, 1)}</span>
									{/if}
									{#if isWorkoutCompleted(wo)}
										<span class="material-symbols check" aria-hidden="true">check_circle</span>
									{/if}
								</button>
							</div>
						{/each}
					</div>
				</article>
			{/each}
		</section>

		<a class="coach-link" href="/coach?plan={plan.id}">
			<span class="material-symbols">sports</span>
			<div class="coach-link-body">
				<strong>Ask the coach about this plan</strong>
				<span>Should I run today? Am I on track? Why this week's long run?</span>
			</div>
			<span class="material-symbols arrow">chevron_right</span>
		</a>
	</div>
{/if}

{#if editing}
	<WorkoutEditor
		workout={editing}
		onClose={() => (editing = null)}
		onSaved={async () => {
			editing = null;
			await load();
		}}
	/>
{/if}

{#if editingPlanMeta && plan}
	<PlanMetaEditor
		{plan}
		onClose={() => (editingPlanMeta = false)}
		onSaved={async () => {
			editingPlanMeta = false;
			await load();
		}}
	/>
{/if}

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
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
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-lg);
		padding: var(--space-lg) var(--space-xl);
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 14%, var(--color-surface)) 0%,
			var(--color-surface) 70%
		);
		border: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-sm);
		flex-wrap: wrap;
	}
	.hero.race-today {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}
	.hero-body {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.hero-eyebrow {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	h1 {
		font-size: 1.65rem;
		font-weight: 700;
		margin: 0;
		line-height: 1.15;
	}
	.hero-title-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.hero-edit {
		flex-shrink: 0;
	}
	.hero-edit .material-symbols {
		font-size: 1rem;
		vertical-align: -2px;
		margin-right: 0.2rem;
	}
	.hero-chips {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2xs);
	}
	.chip,
	.chip-link {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.15rem 0.55rem;
		border-radius: 9999px;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		text-decoration: none;
	}
	.chip-link:hover { color: var(--color-primary); }
	.chip .material-symbols,
	.chip-link .material-symbols { font-size: 0.95rem; }

	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md);
		margin-top: var(--space-xs);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-variant-numeric: tabular-nums;
	}
	.meta span {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}
	.meta .material-symbols {
		font-size: 1.05rem;
		color: var(--color-text-tertiary);
	}

	.hero-position {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-sm);
		flex-shrink: 0;
		min-width: 9rem;
	}
	.week-pill {
		font-size: 1.05rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.week-pill em {
		font-style: normal;
		font-weight: 500;
		color: var(--color-text-tertiary);
	}
	.relation-pill {
		display: inline-flex;
		align-items: center;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: 9999px;
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		color: var(--color-primary);
		font-size: 0.8rem;
		font-weight: 600;
		white-space: nowrap;
	}
	.relation-pill.race-today {
		background: var(--color-primary);
		color: var(--color-surface);
	}
	.relation-pill.race-past {
		background: color-mix(in srgb, var(--color-text-tertiary) 18%, transparent);
		color: var(--color-text-tertiary);
	}
	.progress-ring {
		width: 5rem;
		height: 5rem;
		border-radius: 50%;
		padding: 5px;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.progress-inner {
		width: 100%;
		height: 100%;
		background: var(--color-surface);
		border-radius: 50%;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
	}
	.pct {
		font-size: 1.2rem;
		font-weight: 700;
		line-height: 1;
	}
	.done {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		margin-top: 0.15rem;
	}

	.calendar-bar {
		height: 0.4rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		overflow: hidden;
		margin: var(--space-sm) 0 var(--space-md);
	}
	.calendar-fill {
		display: block;
		height: 100%;
		background: linear-gradient(
			90deg,
			var(--color-primary),
			color-mix(in srgb, var(--color-primary) 70%, var(--color-accent-orange, var(--color-primary)))
		);
		transition: width var(--transition-base);
	}

	.publish-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
		padding: var(--space-md) var(--space-lg);
		margin: var(--space-md) 0;
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md);
	}
	.publish-label {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
	}
	.publish-row select {
		padding: 0.4rem 0.7rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.9rem;
	}

	.today {
		margin-bottom: var(--space-md);
	}
	.today-link {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		width: 100%;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
		transition: transform var(--transition-base), box-shadow var(--transition-base), border-color var(--transition-base);
	}
	button.today-link:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-sm);
		border-color: var(--color-primary);
	}
	.today-static {
		cursor: default;
		background: color-mix(in srgb, var(--color-text-tertiary) 4%, var(--color-surface));
	}
	.today-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.75rem;
		height: 2.75rem;
		border-radius: 50%;
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
		color: var(--color-primary);
		flex-shrink: 0;
	}
	.today-icon.done {
		background: color-mix(in srgb, var(--color-success) 18%, transparent);
		color: var(--color-success);
	}
	.today-icon .material-symbols { font-size: 1.5rem; }
	.today-static .today-icon {
		background: color-mix(in srgb, var(--color-text-tertiary) 14%, transparent);
		color: var(--color-text-tertiary);
	}
	.today-body {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.today-label {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.08em;
		text-transform: uppercase;
		font-weight: 700;
		color: var(--color-text-tertiary);
	}
	.today-kind {
		font-size: 1.15rem;
		font-weight: 700;
		color: var(--color-text);
		line-height: 1.2;
	}
	.today-meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-variant-numeric: tabular-nums;
	}
	.today-done {
		color: var(--color-success);
		font-weight: 600;
	}
	.today-notes {
		color: var(--color-text-secondary);
		margin: 0.3rem 0 0;
		font-size: 0.9rem;
	}
	.today-arrow {
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}

	.week {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-sm);
		transition: opacity var(--transition-base);
	}
	.week.past { opacity: 0.62; }
	.week.future { opacity: 0.85; }
	.week.current {
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--color-primary) 35%, transparent);
		opacity: 1;
	}
	.week-header {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-md);
		margin-bottom: 0.5rem;
		flex-wrap: wrap;
	}
	.week-ident {
		display: inline-flex;
		align-items: baseline;
		gap: var(--space-sm);
		min-width: 0;
	}
	.week-num {
		font-weight: 700;
		font-size: 1rem;
	}
	.week-phase {
		font-size: 0.78rem;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-primary);
	}
	.week-stats {
		display: inline-flex;
		align-items: baseline;
		gap: var(--space-md);
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.week-progress {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}
	.week-progress em {
		font-style: normal;
		color: var(--color-text-tertiary);
	}
	.week-volume {
		font-weight: 600;
	}
	.week-note {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin-bottom: 0.6rem;
	}
	.day-grid {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		gap: 0.4rem;
	}
	/* On narrow viewports stay one column wide per day so the
	   day-of-week order remains scannable top-to-bottom. Two columns
	   broke the weekly progression; the previous code paired Sun+Mon,
	   Tue+Wed which reads like a random grid. */
	@media (max-width: 40rem) {
		.day-grid {
			grid-template-columns: 1fr;
		}
	}
	.day {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		padding: 0.5rem 0.55rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		border: 1px solid var(--color-border);
		color: inherit;
		font-size: 0.8rem;
		border-top: 3px solid var(--kind-color, var(--color-border));
		position: relative;
		min-height: 4.5rem;
	}
	.day:hover {
		border-color: var(--color-primary);
	}
	.day-link {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		color: inherit;
		width: 100%;
		min-height: 2.75rem;
		text-align: left;
		background: transparent;
		border: none;
		padding: 0;
		font: inherit;
		cursor: pointer;
	}
	.day.rest {
		opacity: 0.55;
	}
	.day.past {
		opacity: 0.7;
	}
	.day.past.completed,
	.day.today {
		opacity: 1;
	}
	.day.today {
		background: color-mix(in srgb, var(--color-primary) 14%, var(--color-surface));
		border-color: var(--color-primary);
		box-shadow: 0 0 0 1px color-mix(in srgb, var(--color-primary) 30%, transparent);
	}
	.day.completed {
		background: color-mix(in srgb, var(--color-success) 12%, var(--color-surface));
	}
	.day .dow {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		letter-spacing: 0.05em;
		text-transform: uppercase;
	}
	.day .kind {
		font-weight: 700;
		color: var(--kind-color, var(--color-text));
	}
	.day .dist {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.day .check {
		position: absolute;
		top: 0.3rem;
		right: 0.3rem;
		color: var(--color-success);
		font-size: 1rem;
	}
	.coach-link {
		display: flex;
		align-items: center;
		gap: 1rem;
		margin-top: var(--space-xl);
		padding: 0.9rem 1.25rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		color: inherit;
		text-decoration: none;
		transition: border-color 0.15s ease, background 0.15s ease;
	}
	.coach-link:hover {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 4%, var(--color-surface));
	}
	.coach-link > .material-symbols {
		color: var(--color-primary);
		font-size: 1.5rem;
	}
	.coach-link-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
	}
	.coach-link-body span {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.coach-link .arrow {
		color: var(--color-text-tertiary);
	}
	.calendar-section {
		margin: var(--space-md) 0;
	}
	.section-title {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm) 0;
	}
	.weeks .section-title {
		margin-top: var(--space-lg);
	}
	.rules-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.rules-card h3 {
		font-size: 0.78rem;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
		margin-bottom: 0.4rem;
	}
	.rules-card ul {
		margin: 0;
		padding-left: 1.1rem;
	}
	.rules-card li {
		margin-bottom: 0.2rem;
		font-size: 0.92rem;
	}

	/* Skeleton placeholders replace the silent "Loading..." paragraph
	   so the page rhythm is visible before data lands. */
	.back-skel,
	.hero-skel,
	.today-skel,
	.week-skel {
		background: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-lg);
		animation: plan-skeleton-shimmer 1.6s ease-in-out infinite;
	}
	.back-skel {
		height: 1rem;
		width: 8rem;
		margin-bottom: var(--space-md);
		border-radius: var(--radius-sm);
	}
	.hero-skel { height: 9rem; margin-bottom: var(--space-md); }
	.today-skel { height: 5.5rem; margin-bottom: var(--space-md); }
	.week-skel { height: 6rem; margin-bottom: var(--space-sm); }
	@keyframes plan-skeleton-shimmer {
		0% { background-position: 100% 0; }
		100% { background-position: -100% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.back-skel,
		.hero-skel,
		.today-skel,
		.week-skel { animation: none; }
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		text-align: center;
		max-width: 28rem;
		margin: 0 auto;
	}
	.empty-mark {
		opacity: 0.85;
		border-radius: var(--radius-md);
	}
	.empty h3 {
		font-size: 1.15rem;
		font-weight: 700;
		margin: 0;
	}
	.empty p {
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
		font-size: 0.95rem;
	}

	@media (max-width: 48rem) {
		.page {
			padding: var(--space-lg) var(--space-md);
		}
		.hero {
			padding: var(--space-md);
			gap: var(--space-md);
		}
		.hero-position {
			flex-direction: row;
			align-items: center;
			align-self: stretch;
			justify-content: space-between;
			min-width: 0;
		}
		h1 {
			font-size: 1.35rem;
		}
		.today-link {
			padding: var(--space-md);
		}
	}
</style>
