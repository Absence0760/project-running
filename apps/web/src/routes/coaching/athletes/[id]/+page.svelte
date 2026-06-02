<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import Avatar from '$lib/components/Avatar.svelte';
	import {
		fetchMyAthletes,
		fetchAthleteRuns,
		fetchAthletePlanOverview,
		type CoachAthleteLink,
		type AthleteRunSummary
	} from '$lib/core/data';
	import type { ActivePlanOverview, PlanWorkout } from '$lib/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { formatDistance, formatPace } from '$lib/format/units.svelte';
	import { formatDuration, formatDate } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';

	const athleteId = $derived($page.params.id);

	let loading = $state(true);
	let link = $state<CoachAthleteLink | null>(null);
	let notOnRoster = $state(false);
	let runs = $state<AthleteRunSummary[]>([]);
	let overview = $state<ActivePlanOverview | null>(null);

	async function load() {
		loading = true;
		const id = athleteId;
		if (!id) {
			notOnRoster = true;
			loading = false;
			return;
		}
		// Same auth-hydration poll the /coaching landing uses — the
		// fetchers bail to []/null when auth.user is null, and onMount can
		// fire before fetchUser resolves on a hard load.
		for (let i = 0; i < 40 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		// Confirm the coaching relationship (and get the display name) from
		// the roster. RLS already gates the run/plan reads, but resolving
		// the link gives us the header + a clean "not on your roster" state.
		const roster = await fetchMyAthletes();
		link = roster.find((a) => a.user_id === id) ?? null;
		if (!link) {
			notOnRoster = true;
			loading = false;
			return;
		}
		[runs, overview] = await Promise.all([
			fetchAthleteRuns(id, 20),
			fetchAthletePlanOverview(id)
		]);
		loading = false;
	}

	onMount(load);

	function activityLabel(r: AthleteRunSummary): string {
		const a = (r.metadata?.activity_type as string | undefined) ?? 'run';
		return a.charAt(0).toUpperCase() + a.slice(1);
	}

	function paceLabel(r: AthleteRunSummary): string {
		if (!(r.distance_m > 0) || !(r.duration_s > 0)) return '—';
		return formatPace(r.duration_s, r.distance_m);
	}

	function workoutStatus(w: PlanWorkout): 'done' | 'missed' | 'upcoming' | 'rest' {
		if (w.kind === 'rest') return 'rest';
		if (w.manually_completed === true || w.completed_run_id != null) return 'done';
		// Local-tz today vs the scheduled date string (YYYY-MM-DD).
		const today = new Date();
		const todayISO = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
		return w.scheduled_date < todayISO ? 'missed' : 'upcoming';
	}

	function workoutLabel(w: PlanWorkout): string {
		const k = (w.kind ?? 'run').replace(/_/g, ' ');
		return k.charAt(0).toUpperCase() + k.slice(1);
	}

	// Compliance counts over the whole plan (rest days excluded).
	const compliance = $derived.by(() => {
		if (!overview) return null;
		const real = overview.workouts.filter((w) => w.kind !== 'rest');
		const done = real.filter(
			(w) => w.manually_completed === true || w.completed_run_id != null
		).length;
		const today = new Date();
		const todayISO = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
		const missed = real.filter(
			(w) =>
				!(w.manually_completed === true || w.completed_run_id != null) &&
				w.scheduled_date < todayISO
		).length;
		return { total: real.length, done, missed, pct: overview.completionPct };
	});

	// The workouts worth surfacing: a window around today (recent misses +
	// what's coming up) rather than the whole plan, newest-relevant first.
	const focusWorkouts = $derived.by(() => {
		if (!overview) return [] as PlanWorkout[];
		const sorted = [...overview.workouts]
			.filter((w) => w.kind !== 'rest')
			.sort((a, b) => a.scheduled_date.localeCompare(b.scheduled_date));
		const today = new Date();
		const todayISO = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
		const idx = sorted.findIndex((w) => w.scheduled_date >= todayISO);
		const pivot = idx === -1 ? sorted.length : idx;
		return sorted.slice(Math.max(0, pivot - 4), pivot + 6);
	});
</script>

<svelte:head><title>{link?.display_name ?? m('coachingAthlete.athleteFallback')} · Coaching · Threkir</title></svelte:head>

<div class="page">
	<a class="back" href="/coaching">← {m('shell.coaching')}</a>

	{#if loading}
		<p class="muted">{m('shell.loading')}</p>
	{:else if notOnRoster}
		<div class="card">
			<h1>{m('coachingAthlete.notOnRosterTitle')}</h1>
			<p class="muted">
				{m('coachingAthlete.notOnRosterPrefix')}<a href="/coaching">{m('shell.coaching')}</a>{m('coachingAthlete.notOnRosterSuffix')}
			</p>
		</div>
	{:else}
		<header class="athlete-head">
			<Avatar name={link?.display_name} size="3rem" font="1.1rem" />
			<div>
				<h1>{link?.display_name ?? m('coachingAthlete.runnerFallback')}</h1>
				<p class="muted">
					{m('coachingAthlete.coachingSince', { date: link?.accepted_at ? formatDate(link.accepted_at) : '—' })} ·
					<a href="/u/{athleteId}">{m('coachingAthlete.publicProfile')}</a>
				</p>
			</div>
		</header>

		<section class="card">
			<h2>{m('coachingAthlete.planCompliance')}</h2>
			{#if !overview}
				<p class="empty">{m('coachingAthlete.noActivePlan')}</p>
			{:else}
				<div class="plan-summary">
					<a class="plan-name" href="/plans/{overview.plan.id}">{overview.plan.name}</a>
					{#if compliance}
						<div class="compliance-bar" role="img"
							aria-label={m('coachingAthlete.complianceBarLabel', { pct: compliance.pct })}>
							<div class="compliance-fill" style="width:{compliance.pct}%"></div>
						</div>
						<p class="compliance-stats">
							<strong>{compliance.pct}%</strong> {m('coachingAthlete.complete')} ·
							{m('coachingAthlete.doneCount', { done: compliance.done, total: compliance.total })}
							{#if compliance.missed > 0}
								· <span class="missed-count">{m('coachingAthlete.missedCount', { n: compliance.missed })}</span>
							{/if}
						</p>
					{/if}
				</div>
				<ul class="workout-list">
					{#each focusWorkouts as w (w.id)}
						{@const status = workoutStatus(w)}
						<li class="workout-row status-{status}">
							<span class="w-date">{formatDate(w.scheduled_date)}</span>
							<span class="w-kind">{workoutLabel(w)}</span>
							<span class="w-target">
								{#if w.target_distance_m}{formatDistance(w.target_distance_m)}{/if}
								{#if w.target_pace_sec_per_km}
									· {formatPace(w.target_pace_sec_per_km, 1000)}
								{/if}
							</span>
							<span class="w-status status-pill status-{status}">
								{status === 'done'
									? m('coachingAthlete.statusDone')
									: status === 'missed'
										? m('coachingAthlete.statusMissed')
										: m('coachingAthlete.statusUpcoming')}
							</span>
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<section class="card">
			<h2>{m('coachingAthlete.recentRuns')}</h2>
			{#if runs.length === 0}
				<p class="empty">{m('coachingAthlete.noRunsYet')}</p>
			{:else}
				<ul class="run-list">
					{#each runs as r (r.id)}
						<li class="run-row">
							<span class="r-date">{formatDate(r.started_at)}</span>
							<span class="r-activity">{activityLabel(r)}</span>
							<span class="r-distance">{formatDistance(r.distance_m)}</span>
							<span class="r-duration">{formatDuration(r.duration_s)}</span>
							<span class="r-pace">{paceLabel(r)}</span>
							{#if !r.is_public}
								<span class="r-private" title={m('coachingAthlete.privateRunTooltip')}>{m('coachingAthlete.private')}</span>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 64rem;
	}
	.back {
		display: inline-block;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-decoration: none;
		font-size: 0.9rem;
	}
	.back:hover {
		text-decoration: underline;
	}
	.athlete-head {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}
	h1 {
		margin: 0 0 var(--space-2xs);
		font-size: 1.7rem;
		font-weight: 800;
		letter-spacing: -0.01em;
	}
	h2 {
		margin: 0 0 var(--space-md);
		font-size: 1.15rem;
		font-weight: 700;
	}
	.muted {
		color: var(--color-text-secondary);
		font-size: 0.88rem;
		margin: 0;
	}
	.muted a {
		color: var(--color-text-secondary);
	}
	.empty {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		margin: 0;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-lg);
	}
	.plan-summary {
		margin-bottom: var(--space-md);
	}
	.plan-name {
		font-weight: 700;
		color: var(--color-text);
		text-decoration: none;
	}
	.plan-name:hover {
		text-decoration: underline;
	}
	.compliance-bar {
		height: 8px;
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		overflow: hidden;
		margin: var(--space-xs) 0;
	}
	.compliance-fill {
		height: 100%;
		background: var(--color-primary, #4f46e5);
		border-radius: 9999px;
	}
	.compliance-stats {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.missed-count {
		color: var(--color-danger, #dc2626);
	}
	.workout-list,
	.run-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.workout-row,
	.run-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		font-size: 0.88rem;
	}
	.w-date,
	.r-date {
		flex: 0 0 6.5rem;
		color: var(--color-text-secondary);
	}
	.w-kind {
		flex: 0 0 7rem;
		font-weight: 600;
	}
	.w-target {
		flex: 1;
		color: var(--color-text-secondary);
		min-width: 0;
	}
	.r-activity {
		flex: 0 0 5rem;
		font-weight: 600;
	}
	.r-distance,
	.r-duration,
	.r-pace {
		flex: 0 0 5rem;
	}
	.r-private {
		margin-inline-start: auto;
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		padding: 1px 8px;
	}
	.status-pill {
		margin-inline-start: auto;
		flex-shrink: 0;
		font-size: 0.72rem;
		font-weight: 600;
		border-radius: 9999px;
		padding: 1px 10px;
	}
	.status-pill.status-done {
		background: color-mix(in srgb, var(--color-primary, #4f46e5) 18%, transparent);
		color: var(--color-primary, #4f46e5);
	}
	.status-pill.status-missed {
		background: color-mix(in srgb, var(--color-danger, #dc2626) 16%, transparent);
		color: var(--color-danger, #dc2626);
	}
	.status-pill.status-upcoming {
		background: var(--color-surface);
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
	}
</style>
