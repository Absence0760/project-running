<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import CalendarHeatmap from '$lib/components/CalendarHeatmap.svelte';
	import {
		formatDuration,
		formatPace,
		formatDistance,
		formatDate,
		formatDateShort,
		sourceLabel,
		sourceColor,
	} from '$lib/mock-data';
	import {
		fetchRuns,
		fetchWeeklyMileage,
		fetchPersonalRecords,
		fetchActivePlanOverview,
		fetchNextRsvpedEvent,
		fetchFitnessSnapshots,
		insertFitnessSnapshot,
		type FitnessSnapshotRow,
	} from '$lib/data';
	import { computeSnapshot, recoveryAdvice } from '$lib/fitness';
	import { computeRunStreaks } from '$lib/streaks';
	import { computeReadiness } from '$lib/readiness';
	import { computeTrainingLoadSeries, hasTrimpSignal } from '$lib/training_load';
	import TrainingLoadChart from '$lib/components/TrainingLoadChart.svelte';
	import { WORKOUT_KIND_LABEL } from '$lib/training';
	import WorkoutEditor from '$lib/components/WorkoutEditor.svelte';
	import PeriodSummary from '$lib/components/PeriodSummary.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import type { PlanWorkout } from '$lib/types';
	import { loadSettings, effective } from '$lib/settings';
	import { fmtKm, fmtPace, setUnit } from '$lib/units.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		loadGoals,
		saveGoals,
		evaluateGoal,
		newGoalId,
		periodLabel,
		type RunGoal,
	} from '$lib/goals';
	import type { Run, RunSource, ActivePlanOverview } from '$lib/types';

	let runs = $state<Run[]>([]);
	let weeklyMileage = $state<{ week: string; distance_m: number }[]>([]);
	let personalRecords = $state<{ distance: string; time_s: number; date: string }[]>([]);
	let planOverview = $state<ActivePlanOverview | null>(null);
	let loading = $state(true);
	let mileageView = $state<'weekly' | 'monthly' | 'yearly'>('weekly');
	let sourceFilter = $state<RunSource | 'all'>('all');
	/// User's weekly mileage goal in metres, from the universal settings
	/// bag (`weekly_mileage_goal_m` — shared with Android + mobile iOS).
	/// Null until loaded; null-stays-null if the user hasn't set one yet,
	/// in which case the progress card hides itself.
	let weeklyGoalMetres = $state<number | null>(null);
	let preferredUnit = $state<'km' | 'mi'>('km');
	let weekStartDay = $state<'monday' | 'sunday'>('monday');
	let upcomingEvent = $state<Awaited<ReturnType<typeof fetchNextRsvpedEvent>>>(null);
	let fitnessHistory = $state<FitnessSnapshotRow[]>([]);
	let liveSnap = $derived(computeSnapshot(runs));

	// HR prefs feed both the TRIMP-eligible flag and the stress score.
	let trimpPrefs = $state<{ resting_hr_bpm?: number | null; max_hr_bpm?: number | null }>({});
	let trainingLoadSeries = $derived(computeTrainingLoadSeries(runs, trimpPrefs, 90));
	let trainingLoadHasHr = $derived(hasTrimpSignal(runs, trimpPrefs));

	/// Normalised VO2 max sparkline points for the trend chart. Kept
	/// in the script (not as `{@const}` under `<svg>`, which Svelte 5
	/// rejects — const-tags must be immediate children of block tags
	/// like `#if` / `#each`, not HTML elements).
	let trendPath = $derived.by(() => {
		const vals = fitnessHistory.map((s) => s.vo2_max ?? 0).filter((v) => v > 0);
		if (vals.length < 2) return '';
		const lo = Math.min(...vals);
		const hi = Math.max(...vals);
		const range = Math.max(0.5, hi - lo);
		const stepX = 200 / (vals.length - 1);
		return vals
			.map((v, i) => {
				const x = i * stepX;
				const y = 36 - ((v - lo) / range) * 32;
				return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`;
			})
			.join(' ');
	});

	// Multi-metric goals — local-only today, per browser. Load on
	// mount; every edit writes back synchronously. See `lib/goals.ts`.
	let goals = $state<RunGoal[]>([]);
	let showGoalEditor = $state(false);
	let editingGoal = $state<RunGoal | null>(null);

	/// The legacy `weekly_mileage_goal_m` setting (shared with Android
	/// via Settings → Preferences) is folded into the same Goals
	/// section so the dashboard only has ONE goal surface. We surface
	/// it as a read-only synthetic goal — clicking it routes to
	/// /settings/preferences instead of opening the multi-metric
	/// editor — and skip rendering it if the user already has a
	/// week-period distance goal of their own.
	const SYNTHETIC_WEEKLY_GOAL_ID = '__weekly_mileage_pref__';
	let displayGoals = $derived.by<RunGoal[]>(() => {
		const userHasWeeklyDistance = goals.some(
			(g) => g.period === 'week' && (g.distanceMetres ?? 0) > 0,
		);
		if (!weeklyGoalMetres || weeklyGoalMetres <= 0 || userHasWeeklyDistance) {
			return goals;
		}
		const synthetic: RunGoal = {
			id: SYNTHETIC_WEEKLY_GOAL_ID,
			period: 'week',
			distanceMetres: weeklyGoalMetres,
		};
		return [synthetic, ...goals];
	});

	/// Today's-workout modal — opened by clicking the today card. Hosted
	/// on the dashboard directly so we don't need to round-trip through
	/// /plans/[id] with a `?edit=` query.
	let editingWorkout = $state<PlanWorkout | null>(null);

	/// Period-summary modal state. The stat cards (This Week / This Month)
	/// open the same `<PeriodSummary>` component that the standalone
	/// /dashboard/period/... page uses, so deep-linking still works.
	let periodModal = $state<{ type: 'week' | 'month'; date: Date } | null>(null);

	function openNewGoal() {
		editingGoal = {
			id: newGoalId(),
			period: 'week',
			distanceMetres: undefined,
			timeSeconds: undefined,
			paceSecPerKm: undefined,
			runCount: undefined,
		};
		showGoalEditor = true;
	}

	function openEditGoal(g: RunGoal) {
		editingGoal = { ...g };
		showGoalEditor = true;
	}

	function commitGoal(g: RunGoal) {
		const hasAny =
			(g.distanceMetres ?? 0) > 0 ||
			(g.timeSeconds ?? 0) > 0 ||
			(g.paceSecPerKm ?? 0) > 0 ||
			(g.runCount ?? 0) > 0;
		if (!hasAny) {
			// "Save" on an empty goal is effectively delete.
			goals = goals.filter((x) => x.id !== g.id);
		} else {
			const idx = goals.findIndex((x) => x.id === g.id);
			if (idx >= 0) goals = goals.map((x, i) => (i === idx ? g : x));
			else goals = [...goals, g];
		}
		saveGoals(auth.user?.id, goals);
		showGoalEditor = false;
		editingGoal = null;
	}

	function deleteGoal(id: string) {
		goals = goals.filter((g) => g.id !== id);
		saveGoals(auth.user?.id, goals);
		showGoalEditor = false;
		editingGoal = null;
	}

	const sources: { value: RunSource | 'all'; label: string }[] = [
		{ value: 'all', label: 'All' },
		{ value: 'app', label: 'Recorded' },
		{ value: 'strava', label: 'Strava' },
		{ value: 'parkrun', label: 'parkrun' },
		{ value: 'healthkit', label: 'HealthKit' },
	];

	onMount(async () => {
		// Wait for the auth store to hydrate before reading user-scoped
		// goals out of localStorage — otherwise auth.user.id is null on
		// first paint and `loadGoals` returns []. The /coach route uses
		// the same pattern.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		goals = loadGoals(auth.user?.id);
		[runs, weeklyMileage, personalRecords, planOverview, upcomingEvent, fitnessHistory] = await Promise.all([
			fetchRuns(),
			fetchWeeklyMileage(),
			fetchPersonalRecords(),
			fetchActivePlanOverview(),
			fetchNextRsvpedEvent(48),
			fetchFitnessSnapshots(60),
		]);
		// Compute a fresh snapshot from today's runs and persist it so
		// the trend chart accumulates history over time. Best-effort —
		// an RLS blip just leaves the chart with yesterday's data.
		const snap = computeSnapshot(runs);
		try {
			await insertFitnessSnapshot(snap);
		} catch (_) {
			/* silent */
		}
		// Best-effort load of the user's weekly-mileage goal from the
		// settings bag. A missing bag (new user, or RLS blip) just
		// leaves `weeklyGoalMetres = null` and the goal card stays hidden.
		try {
			const uid = auth.user?.id;
			if (uid) {
				const settings = await loadSettings(uid);
				weeklyGoalMetres = effective<number>(settings, 'weekly_mileage_goal_m') ?? null;
				const unit = effective<string>(settings, 'preferred_unit');
				if (unit === 'mi' || unit === 'km') {
					preferredUnit = unit;
					setUnit(unit);
				}
				const wsd = effective<string>(settings, 'week_start_day');
				if (wsd === 'sunday' || wsd === 'monday') weekStartDay = wsd;
				trimpPrefs = {
					resting_hr_bpm: effective<number>(settings, 'resting_hr_bpm') ?? null,
					max_hr_bpm: effective<number>(settings, 'max_hr_bpm') ?? null,
				};
			}
		} catch (_) {
			// silent — goal card is additive, not load-blocking
		}
		loading = false;
	});

	const now = new Date();
	const weekStart = new Date(now);
	const dowMon = (now.getDay() + 6) % 7; // 0 = Mon, matching runs/+page.svelte and Android
	weekStart.setDate(now.getDate() - dowMon);
	weekStart.setHours(0, 0, 0, 0);

	let filteredRuns = $derived(
		sourceFilter === 'all' ? runs : runs.filter((r) => r.source === sourceFilter)
	);
	let thisWeekRuns = $derived(filteredRuns.filter((r) => new Date(r.started_at) >= weekStart));
	let thisWeekRunDistance = $derived(thisWeekRuns.reduce((sum, r) => sum + r.distance_m, 0));

	/// Plan workouts the user marked as done this week without
	/// recording a run. Their target distance is folded into the
	/// "This Week" card so the dashboard reflects the user's stated
	/// progress, matching the mark-as-done UX expectation. Workouts
	/// linked to an actual run (`completed_run_id != null`) are
	/// excluded since the run already counts via `thisWeekRuns`.
	let thisWeekManualWorkouts = $derived.by(() => {
		const overview = planOverview;
		if (!overview) return [];
		return overview.workouts.filter((w) => {
			if (!(w.manually_completed === true && w.completed_run_id == null)) return false;
			if (!w.scheduled_date) return false;
			const d = new Date(w.scheduled_date + 'T00:00:00');
			return d >= weekStart && d <= now;
		});
	});
	let thisWeekManualDistance = $derived(
		thisWeekManualWorkouts.reduce((sum, w) => sum + (w.target_distance_m ?? 0), 0)
	);

	/// Combined distance + activity count for the "This Week" card.
	/// Distance includes manually-completed workouts' target distance;
	/// the count includes them too so "X runs / workouts" reflects
	/// actions taken this week.
	let thisWeekDistance = $derived(thisWeekRunDistance + thisWeekManualDistance);
	let thisWeekActivityCount = $derived(thisWeekRuns.length + thisWeekManualWorkouts.length);
	let totalRuns = $derived(filteredRuns.length);
	let longestRun = $derived(filteredRuns.length > 0 ? Math.max(...filteredRuns.map((r) => r.distance_m)) : 0);

	/// Current + best run streak. Daily granularity; Strava's grace
	/// rule means a missing today doesn't break the streak if
	/// yesterday is intact. Filtered runs feed in so the user's
	/// activity-type filter on the dashboard scopes the streak too —
	/// "run streak" view shows running-only, "walk" shows walks, etc.
	let runStreaks = $derived.by(() => {
		const starts = filteredRuns.map((r) => new Date(r.started_at));
		return computeRunStreaks(starts, now);
	});

	/// Readiness-to-run score (0–100) derived from the live fitness
	/// snapshot. Sleep + resting-HR inputs aren't piped yet (Health
	/// Connect / HealthKit reads ship separately); the helper handles
	/// null gracefully so the card shows a TSB-only score for now.
	let readiness = $derived.by(() =>
		computeReadiness({ tsb: liveSnap.trainingStressBal ?? null }),
	);

	// Mileage chart data based on view mode
	let mileageData = $derived.by(() => {
		if (mileageView === 'weekly') return weeklyMileage;

		// Group runs by month or year. Distance stays in metres so the
		// render-time formatter can honor the user's preferred unit.
		const groups = new Map<string, number>();
		for (const run of filteredRuns) {
			const d = new Date(run.started_at);
			const key = mileageView === 'monthly'
				? d.toLocaleDateString('en-GB', { month: 'short', year: '2-digit' })
				: String(d.getFullYear());
			groups.set(key, (groups.get(key) ?? 0) + run.distance_m);
		}
		return Array.from(groups.entries()).map(([week, distance_m]) => ({
			week,
			distance_m: Math.round(distance_m),
		}));
	});

	let maxBar = $derived(
		mileageData.length > 0 ? Math.max(...mileageData.map((w) => w.distance_m)) : 1
	);
</script>

<svelte:head>
	<title>Dashboard — Run Onward</title>
</svelte:head>

<div class="page">
	{#if loading}
		<div class="skeleton-hero"></div>
		<div class="skeleton-filter"></div>
		<div class="stat-grid">
			<div class="stat-card skeleton-card"></div>
			<div class="stat-card skeleton-card"></div>
			<div class="stat-card skeleton-card"></div>
			<div class="stat-card skeleton-card"></div>
			<div class="stat-card skeleton-card"></div>
		</div>
		<div class="skeleton-block skeleton-block-tall"></div>
		<div class="skeleton-block"></div>
	{:else}
		{#if planOverview?.todayWorkout}
			{@const t = planOverview.todayWorkout}
			<button
				class="today-card"
				class:done={t.manually_completed === true || t.completed_run_id != null}
				type="button"
				onclick={() => (editingWorkout = t)}
			>
				<div class="today-left">
					<span class="today-label">TODAY'S WORKOUT</span>
					<h2>
						{WORKOUT_KIND_LABEL[t.kind as keyof typeof WORKOUT_KIND_LABEL] ?? t.kind}
					</h2>
					<div class="today-meta">
						{#if t.target_distance_m != null}
							<span>{fmtKm(t.target_distance_m)}</span>
						{/if}
						{#if t.target_pace_sec_per_km}
							<span>@ {fmtPace(t.target_pace_sec_per_km)}</span>
						{/if}
					</div>
				</div>
				<div class="today-right">
					{#if t.manually_completed === true || t.completed_run_id != null}
						<span class="material-symbols done-icon">check_circle</span>
					{:else}
						<span class="material-symbols">chevron_right</span>
					{/if}
					<span class="plan-name">{planOverview.plan.name}</span>
					<span class="plan-progress">{planOverview.completionPct}% done</span>
				</div>
			</button>
		{:else if !planOverview}
			<a class="plan-promo" href="/plans?new=1">
				<div>
					<span class="today-label">TRAINING PLANS</span>
					<h3>Pick a goal race and we'll schedule the weeks</h3>
					<p>5K, 10K, half or full — VDOT-anchored paces, phases, step-back weeks.</p>
				</div>
				<span class="material-symbols">chevron_right</span>
			</a>
		{/if}

		{#if planOverview}
			<div class="plan-secondary">
				<a class="plan-secondary-link" href="/plans/{planOverview.plan.id}">
					Full plan
					<span class="material-symbols">chevron_right</span>
				</a>
				<a class="plan-secondary-link plan-secondary-quiet" href="/plans">
					Manage plans
				</a>
			</div>
		{/if}

		<!-- Upcoming RSVP'd event within 48h — promotes to the top of
		     the dashboard so runners remember to show up. Mirrors
		     Android's upcoming_event_card. Hides when nothing matches. -->
		{#if upcomingEvent}
			{@const when = new Date(upcomingEvent.instance_start)}
			{@const whenLabel = when.toLocaleString(undefined, {
				weekday: 'short',
				month: 'short',
				day: 'numeric',
				hour: 'numeric',
				minute: '2-digit',
			})}
			<a
				href="/clubs/{upcomingEvent.club_slug}/events/{upcomingEvent.event_id}"
				class="event-card"
			>
				<div class="event-icon">
					<span class="material-symbols">event</span>
				</div>
				<div class="event-body">
					<span class="event-label">UPCOMING EVENT</span>
					<strong class="event-title">{upcomingEvent.title}</strong>
					<span class="event-when">
						{whenLabel}{#if upcomingEvent.meet_label} &middot; {upcomingEvent.meet_label}{/if}
					</span>
				</div>
				<span class="material-symbols event-arrow">chevron_right</span>
			</a>
		{/if}

		<!-- Source filter — applies to every metric below the today
		     card / upcoming event. Sits up here so the user understands
		     which slice of their data drives the analytics that follow. -->
		<div class="filter-row">
			{#each sources as src}
				<button
					class="filter-btn"
					class:active={sourceFilter === src.value}
					onclick={() => (sourceFilter = src.value)}
				>
					{src.label}
				</button>
			{/each}
		</div>

		<!-- Stat cards -->
		<div class="recap-strip">
			<a href="/recap/{new Date().getFullYear()}" class="recap-link">
				<span class="material-symbols">auto_awesome</span>
				View {new Date().getFullYear()} recap →
			</a>
		</div>
		<div class="stat-grid">
			<button
				type="button"
				class="stat-card stat-card-button"
				onclick={() => (periodModal = { type: 'week', date: new Date() })}
			>
				<span class="stat-label">This Week</span>
				<span class="stat-value">{formatDistance(thisWeekDistance)}</span>
				<span class="stat-sub">
					{thisWeekActivityCount}
					{thisWeekActivityCount === 1 ? 'activity' : 'activities'}
					{#if thisWeekManualWorkouts.length > 0}
						<span class="manual-hint">
							incl. {thisWeekManualWorkouts.length} marked done
						</span>
					{/if}
				</span>
			</button>
			<div class="stat-card">
				<span class="stat-label">Total Runs</span>
				<span class="stat-value">{totalRuns}</span>
				<span class="stat-sub">all sources</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Longest Run</span>
				<span class="stat-value">{formatDistance(longestRun)}</span>
				<span class="stat-sub">all time</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">This Week Pace</span>
				<span class="stat-value">
					{thisWeekRuns.length > 0
						? formatPace(
								thisWeekRuns.reduce((s, r) => s + r.duration_s, 0),
								thisWeekDistance,
							)
						: '--'}
				</span>
				<span class="stat-sub">average</span>
			</div>
			<div class="stat-card" class:streak-active={runStreaks.current > 0}>
				<span class="stat-label">Streak</span>
				<span class="stat-value">
					{runStreaks.current}
					<span class="stat-unit">{runStreaks.current === 1 ? 'day' : 'days'}</span>
				</span>
				<span class="stat-sub">
					{#if runStreaks.best > runStreaks.current}
						best {runStreaks.best} {runStreaks.best === 1 ? 'day' : 'days'}
					{:else if runStreaks.current > 0}
						all-time best
					{:else}
						no active streak
					{/if}
				</span>
			</div>
		</div>

		<!-- Fitness snapshot — VO2 max + training-load (ATL / CTL / TSB)
		     + a rule-based recovery advice line. Computed client-side
		     from recent runs via `lib/fitness.ts`; persisted to
		     `fitness_snapshots` on every dashboard open so the trend
		     chart has history. Hides when the user has no qualifying
		     runs yet (short / non-recording sources only). -->
		<!-- Readiness-to-run — single 0-100 number with band-aware
		     accent. Inputs today are TSB-only; sleep + resting-HR pipe
		     through the `readiness.ts` helper unchanged once Health
		     Connect / HealthKit reads land. Hide entirely when there's
		     nothing to score (no TSB, no qualifying runs). -->
		{#if liveSnap.trainingStressBal != null}
			<section class="readiness-card readiness-{readiness.band}">
				<div class="readiness-head">
					<span class="readiness-label">Readiness</span>
					<span class="readiness-band">{readiness.band}</span>
				</div>
				<div class="readiness-score">{readiness.score}</div>
				<p class="readiness-advice">{readiness.advice}</p>
				{#if readiness.contributors.length > 0}
					<ul class="readiness-contribs">
						{#each readiness.contributors as c (c.name)}
							<li>
								<span class="contrib-name">{c.name}</span>
								<span class="contrib-delta" class:positive={c.delta > 0} class:negative={c.delta < 0}>
									{c.delta > 0 ? '+' : ''}{c.delta}
								</span>
							</li>
						{/each}
					</ul>
				{/if}
			</section>
		{/if}

		{#if liveSnap.vo2Max != null || liveSnap.chronicLoad != null}
			<section class="fitness-card">
				<div class="fitness-row">
					<div class="fitness-metric">
						<span class="fitness-label">VO₂ max</span>
						<span class="fitness-value">
							{liveSnap.vo2Max != null ? liveSnap.vo2Max.toFixed(1) : '—'}
						</span>
						<span class="fitness-unit">ml/kg/min</span>
					</div>
					{#if liveSnap.chronicLoad != null}
						<div class="fitness-metric">
							<span class="fitness-label">CTL (fitness)</span>
							<span class="fitness-value">{liveSnap.chronicLoad.toFixed(0)}</span>
							<span class="fitness-unit">42-day avg TSS</span>
						</div>
						<div class="fitness-metric">
							<span class="fitness-label">ATL (fatigue)</span>
							<span class="fitness-value">
								{liveSnap.acuteLoad != null ? liveSnap.acuteLoad.toFixed(0) : '—'}
							</span>
							<span class="fitness-unit">7-day avg TSS</span>
						</div>
						<div class="fitness-metric">
							<span class="fitness-label">TSB (form)</span>
							<span
								class="fitness-value"
								class:tsb-neg={(liveSnap.trainingStressBal ?? 0) < -10}
								class:tsb-pos={(liveSnap.trainingStressBal ?? 0) > 10}
							>
								{liveSnap.trainingStressBal != null
									? (liveSnap.trainingStressBal > 0 ? '+' : '') + liveSnap.trainingStressBal.toFixed(0)
									: '—'}
							</span>
							<span class="fitness-unit">CTL − ATL</span>
						</div>
					{/if}
				</div>
				<p class="fitness-advice">
					{recoveryAdvice(liveSnap.trainingStressBal, liveSnap.chronicLoad)}
				</p>
				{#if trendPath}
					<!-- Trend sparkline: VO2 max over the persisted
					     snapshot history. Rendered as an inline SVG path
					     — no chart lib needed for a shape this simple. -->
					<svg class="trend" viewBox="0 0 200 40" preserveAspectRatio="none" aria-hidden="true">
						<path d={trendPath} stroke="currentColor" stroke-width="1.5" fill="none" />
					</svg>
				{/if}
			</section>
		{/if}

		<!-- Training-load curves over the last 90 days (decisions §34).
		     Uses TRIMP when avg_bpm + HR prefs are available, distance
		     fallback otherwise. Hides when there's nothing to plot. -->
		{#if runs.length > 0}
			<section class="fitness-card">
				<TrainingLoadChart points={trainingLoadSeries} hasHr={trainingLoadHasHr} />
			</section>
		{/if}

		<!-- Mileage chart -->
		<section class="card">
			<div class="chart-header">
				<h2>Mileage</h2>
				<div class="view-toggle">
					<button class:active={mileageView === 'weekly'} onclick={() => (mileageView = 'weekly')}>Week</button>
					<button class:active={mileageView === 'monthly'} onclick={() => (mileageView = 'monthly')}>Month</button>
					<button class:active={mileageView === 'yearly'} onclick={() => (mileageView = 'yearly')}>Year</button>
				</div>
			</div>
			<div class="chart">
				{#each mileageData as week}
					<div class="bar-col">
						<div class="bar-tooltip">{formatDistance(week.distance_m)}</div>
						<div
							class="bar"
							style="height: {(week.distance_m / maxBar) * 100}%"
						></div>
						<span class="bar-label">{week.week.split(' ')[0]}</span>
					</div>
				{/each}
			</div>
		</section>

		<!-- Calendar heatmap -->
		<section class="card">
			<h2>Activity</h2>
			<CalendarHeatmap runs={filteredRuns} />
		</section>

		<div class="two-col">
			<!-- Personal records -->
			<section class="card">
				<h2>Personal Records</h2>
				{#if personalRecords.length > 0}
					<table class="pr-table">
						<thead>
							<tr>
								<th>Distance</th>
								<th>Time</th>
								<th>Date</th>
							</tr>
						</thead>
						<tbody>
							{#each personalRecords as pr}
								<tr>
									<td class="pr-distance">{pr.distance}</td>
									<td class="pr-time">{formatDuration(pr.time_s)}</td>
									<td class="pr-date">{formatDate(pr.date)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				{:else}
					<p class="empty-text">Complete qualifying runs to see PRs</p>
				{/if}
			</section>

			<!-- Recent runs -->
			<section class="card">
				<h2>Recent Runs</h2>
				{#if filteredRuns.length > 0}
					<div class="run-list">
						{#each filteredRuns.slice(0, 7) as run}
							<a href="/runs/{run.id}" class="run-row">
								<div class="run-info">
									<span class="run-date">{formatDateShort(run.started_at)}</span>
									<span class="run-distance">{formatDistance(run.distance_m)}</span>
								</div>
								<div class="run-meta">
									<span class="run-pace">{formatPace(run.duration_s, run.distance_m)}</span>
									<span class="source-badge" style="background: {sourceColor(run.source)}">{sourceLabel(run.source)}</span>
								</div>
							</a>
						{/each}
					</div>
				{:else}
					<p class="empty-text">
						{sourceFilter === 'all'
							? 'Record your first run or import from Strava / Garmin to get started.'
							: `No ${sources.find((s) => s.value === sourceFilter)?.label ?? sourceFilter} runs yet.`}
					</p>
				{/if}
			</section>
		</div>

		<!-- Multi-metric goals — local-only. Shows a card per goal with
		     a progress row per target. Empty by default; header button
		     opens the editor. The legacy `weekly_mileage_goal_m` setting
		     (still shared with Android via Settings → Preferences) is
		     surfaced as a synthetic weekly distance goal so it shows up
		     here without needing a separate card. -->
		<section class="goals-section">
			<header class="goals-header">
				<h2>Goals</h2>
				<button type="button" class="link-btn" onclick={openNewGoal}>
					+ Add goal
				</button>
			</header>
			{#if displayGoals.length === 0}
				<p class="goals-empty">
					No goals yet. Set a weekly or monthly target for distance, time,
					avg pace, or number of runs.
				</p>
			{:else}
				<div class="goal-grid">
					{#each displayGoals as g (g.id)}
						{@const p = evaluateGoal(g, runs, new Date(), weekStartDay)}
						{@const isSynthetic = g.id === SYNTHETIC_WEEKLY_GOAL_ID}
						<button
							class="goal-card"
							type="button"
							onclick={() =>
								isSynthetic ? goto('/settings/preferences') : openEditGoal(g)}
						>
							<header class="goal-card-top">
								<span class="goal-period">{periodLabel(g.period)}</span>
								<span class="goal-overall">
									{Math.round(p.overallPercent * 100)}%
								</span>
							</header>
							<ul class="goal-targets">
								{#each p.targets as t}
									<li>
										<div class="goal-target-top">
											<span>{t.label}</span>
											<span class="goal-target-value">
												{t.currentLabel} / {t.targetLabel}
											</span>
										</div>
										<div class="goal-target-bar">
											<div
												class="goal-target-fill"
												class:complete={t.complete}
												style="width: {Math.round(t.percent * 100)}%"
											></div>
										</div>
									</li>
								{/each}
							</ul>
							{#if isSynthetic}
								<p class="goal-card-footer">From Settings · Edit there</p>
							{/if}
						</button>
					{/each}
				</div>
			{/if}
		</section>

		<a class="coach-promo" href="/coach">
			<div class="coach-icon">
				<span class="material-symbols">sports</span>
			</div>
			<div class="coach-body">
				<span class="today-label">ASK THE COACH</span>
				<strong>Should I run today? How's my pace?</strong>
				<span class="coach-sub">
					{#if planOverview}
						Grounded in your plan and recent runs.
					{:else}
						Grounded in your recent runs.
					{/if}
				</span>
			</div>
			<span class="material-symbols coach-arrow">chevron_right</span>
		</a>
	{/if}
</div>

{#if editingWorkout}
	<WorkoutEditor
		workout={editingWorkout}
		onClose={() => (editingWorkout = null)}
		onSaved={async () => {
			editingWorkout = null;
			// Re-fetch the active plan overview so the today card picks up
			// any changes (e.g. new target distance / pace) without a refresh.
			planOverview = await fetchActivePlanOverview();
		}}
	/>
{/if}

<Modal
	open={periodModal != null}
	title="Period summary"
	wide
	onclose={() => (periodModal = null)}
>
	{#if periodModal}
		<PeriodSummary
			runs={filteredRuns}
			initialType={periodModal.type}
			initialDate={periodModal.date}
		/>
	{/if}
</Modal>

<Modal
	open={showGoalEditor && editingGoal != null}
	title="Edit goal"
	onclose={() => (showGoalEditor = false)}
	bodyClass="goal-editor-body"
>
	{#if editingGoal}
		{@const eg = editingGoal}
		<label class="field">
			<span class="field-label">Period</span>
			<div class="toggle-row">
				<button
					class="toggle-btn"
					class:active={eg.period === 'week'}
					type="button"
					onclick={() => (editingGoal = { ...eg, period: 'week' })}
				>Week</button>
				<button
					class="toggle-btn"
					class:active={eg.period === 'month'}
					type="button"
					onclick={() => (editingGoal = { ...eg, period: 'month' })}
				>Month</button>
			</div>
		</label>
		<label class="field">
			<span class="field-label">Distance ({preferredUnit})</span>
			<input
				type="number"
				min="0"
				step="0.5"
				value={eg.distanceMetres != null
					? (preferredUnit === 'mi' ? eg.distanceMetres / 1609.344 : eg.distanceMetres / 1000)
					: ''}
				placeholder="—"
				oninput={(e) => {
					const v = (e.currentTarget as HTMLInputElement).value;
					const perUnit = preferredUnit === 'mi' ? 1609.344 : 1000;
					editingGoal = {
						...eg,
						distanceMetres: v === '' ? undefined : Math.max(0, parseFloat(v) * perUnit),
					};
				}}
				class="input"
			/>
		</label>
		<label class="field">
			<span class="field-label">Time (minutes)</span>
			<input
				type="number"
				min="0"
				step="5"
				value={eg.timeSeconds != null ? Math.round(eg.timeSeconds / 60) : ''}
				placeholder="—"
				oninput={(e) => {
					const v = (e.currentTarget as HTMLInputElement).value;
					editingGoal = {
						...eg,
						timeSeconds: v === '' ? undefined : Math.max(0, parseFloat(v) * 60),
					};
				}}
				class="input"
			/>
		</label>
		<label class="field">
			<span class="field-label">
				Avg pace (mm:ss / {preferredUnit === 'mi' ? 'mi' : 'km'})
			</span>
			<input
				type="text"
				inputmode="numeric"
				pattern={'[0-9]{1,2}:[0-9]{2}'}
				placeholder={preferredUnit === 'mi' ? '8:00' : '5:00'}
				value={eg.paceSecPerKm != null
					? (() => {
						const perDisplay = preferredUnit === 'mi' ? eg.paceSecPerKm * 1.609344 : eg.paceSecPerKm;
						const m = Math.floor(perDisplay / 60);
						const s = Math.round(perDisplay % 60);
						return `${m}:${s.toString().padStart(2, '0')}`;
					})()
					: ''}
				oninput={(e) => {
					const raw = (e.currentTarget as HTMLInputElement).value.trim();
					if (raw === '') {
						editingGoal = { ...eg, paceSecPerKm: undefined };
						return;
					}
					const m = raw.match(/^(\d{1,2}):(\d{2})$/);
					if (!m) return; // wait for a complete mm:ss
					const perDisplay = parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
					if (perDisplay <= 0) return;
					const perKm = preferredUnit === 'mi' ? perDisplay / 1.609344 : perDisplay;
					editingGoal = { ...eg, paceSecPerKm: perKm };
				}}
				class="input"
			/>
		</label>
		<label class="field">
			<span class="field-label">Run count</span>
			<input
				type="number"
				min="0"
				step="1"
				value={eg.runCount ?? ''}
				placeholder="—"
				oninput={(e) => {
					const v = (e.currentTarget as HTMLInputElement).value;
					editingGoal = {
						...eg,
						runCount: v === '' ? undefined : Math.max(0, parseInt(v, 10)),
					};
				}}
				class="input"
			/>
		</label>
		<p class="goal-editor-hint">
			Fill any subset. Blank = no target for that metric. Saving with
			nothing filled deletes the goal.
		</p>
		<div class="goal-editor-actions">
			{#if goals.some((x) => x.id === eg.id)}
				<button type="button" class="btn btn-danger" onclick={() => deleteGoal(eg.id)}>
					Delete
				</button>
			{/if}
			<button type="button" class="btn btn-secondary" onclick={() => (showGoalEditor = false)}>
				Cancel
			</button>
			<button type="button" class="btn btn-primary" onclick={() => commitGoal(eg)}>
				Save
			</button>
		</div>
	{/if}
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}

	h2 {
		font-size: var(--font-size-section-title);
		font-weight: 700;
		margin: 0 0 var(--space-md);
		color: var(--color-text);
		letter-spacing: -0.005em;
	}

	/* Why: groups a section heading + its body without trapping the
	   heading inside card chrome. The old pattern put h2 inside `.card`
	   which made every section title visually indistinguishable from
	   table headers below it. */
	.section { display: flex; flex-direction: column; gap: var(--space-sm); }
	.section-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-md);
	}
	.section-head h2 { margin: 0; }
	.section-desc {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0;
	}

	.empty-text {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}

	/* Skeleton loader — replaces the silent &nbsp; with structured
	   placeholders so the page rhythm is visible before data lands. */
	.skeleton-hero,
	.skeleton-filter,
	.skeleton-block,
	.skeleton-card {
		background: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-lg);
		animation: skeleton-shimmer 1.6s ease-in-out infinite;
	}
	.skeleton-hero { height: 5rem; }
	.skeleton-filter { height: 2rem; width: 22rem; max-width: 100%; }
	.skeleton-block { height: 12rem; }
	.skeleton-block-tall { height: 18rem; }
	.skeleton-card { height: 6.5rem; }
	@keyframes skeleton-shimmer {
		0% { background-position: 100% 0; }
		100% { background-position: -100% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skeleton-hero,
		.skeleton-filter,
		.skeleton-block,
		.skeleton-card { animation: none; }
	}

	.filter-row {
		display: flex;
		gap: var(--space-xs);
		flex-wrap: wrap;
	}
	.filter-btn {
		padding: var(--space-xs) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
		cursor: pointer;
	}
	.filter-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.filter-btn.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: var(--color-surface);
		box-shadow: var(--shadow-sm);
	}

	.chart-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-md);
	}
	.chart-header h2 { margin-bottom: 0; }

	.view-toggle {
		display: inline-flex;
		gap: 0.15rem;
		background: var(--color-bg-tertiary);
		padding: 0.2rem;
		border-radius: var(--radius-md);
	}
	.view-toggle button {
		padding: 0.3rem 0.85rem;
		border: none;
		background: transparent;
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		cursor: pointer;
		border-radius: var(--radius-sm);
		transition: all var(--transition-fast);
	}
	.view-toggle button:hover { color: var(--color-text); }
	.view-toggle button.active {
		background: var(--color-surface);
		color: var(--color-primary);
		box-shadow: var(--shadow-sm);
	}

	/* Hero: today's-workout card. Promoted to the loudest surface on
	   the page — gradient + larger type + a primary-tinted accent. */
	.today-card {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-lg) var(--space-xl);
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 14%, var(--color-surface)) 0%,
			var(--color-surface) 70%
		);
		border: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
		border-radius: var(--radius-xl);
		color: inherit;
		font: inherit;
		text-align: left;
		width: 100%;
		cursor: pointer;
		box-shadow: var(--shadow-sm);
		transition:
			transform var(--transition-base),
			box-shadow var(--transition-base),
			border-color var(--transition-base);
	}
	.today-card:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-md);
		border-color: var(--color-primary);
	}
	.today-card.done { opacity: 0.78; }
	.today-label {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	.today-card h2 {
		margin: var(--space-xs) 0;
		font-size: 1.4rem;
		font-weight: 700;
		color: var(--color-text);
	}
	.today-meta {
		display: flex;
		gap: var(--space-md);
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		font-variant-numeric: tabular-nums;
	}
	.today-right {
		text-align: right;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-2xs);
		color: var(--color-text-secondary);
	}
	.plan-name {
		font-weight: 600;
		color: var(--color-text);
		font-size: 0.9rem;
	}
	.plan-progress { font-size: 0.8rem; }
	.done-icon {
		color: var(--color-success);
		font-size: 1.75rem;
	}
	.plan-promo {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-lg) var(--space-xl);
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-accent-orange) 12%, var(--color-surface)) 0%,
			var(--color-surface) 70%
		);
		border: 1px dashed color-mix(in srgb, var(--color-primary) 35%, var(--color-border));
		border-radius: var(--radius-xl);
		color: inherit;
		text-decoration: none;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}
	.plan-promo:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-sm);
	}
	.plan-promo h3 {
		font-size: 1.15rem;
		font-weight: 700;
		margin: var(--space-xs) 0 var(--space-2xs);
		color: var(--color-text);
	}
	.plan-promo p {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0;
	}
	.plan-promo > :global(.material-symbols) {
		color: var(--color-primary);
		font-size: 1.5rem;
		flex-shrink: 0;
	}

	.plan-secondary {
		display: flex;
		gap: var(--space-md);
		margin-top: calc(var(--space-md) * -1 + 0.1rem);
		padding: 0 var(--space-md);
	}
	.plan-secondary-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.82rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
		padding: var(--space-2xs) 0;
		transition: color var(--transition-fast);
	}
	.plan-secondary-link :global(.material-symbols) {
		font-size: 1.1rem;
	}
	.plan-secondary-link:hover {
		color: var(--color-primary-dark, var(--color-primary));
		text-decoration: underline;
	}
	.plan-secondary-quiet {
		color: var(--color-text-tertiary);
	}
	.plan-secondary-quiet:hover {
		color: var(--color-text);
	}

	.stat-grid {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-md);
	}

	.event-card {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid color-mix(in srgb, var(--color-primary) 40%, var(--color-border));
		border-left: 3px solid var(--color-primary);
		border-radius: var(--radius-lg);
		text-decoration: none;
		color: inherit;
		transition: background var(--transition-fast), box-shadow var(--transition-fast);
	}
	.event-card:hover {
		background: color-mix(in srgb, var(--color-primary) 5%, var(--color-surface));
		box-shadow: var(--shadow-sm);
	}
	.event-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 50%;
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		color: var(--color-primary);
		flex-shrink: 0;
	}
	.event-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.event-label {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-primary);
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}
	.event-title {
		font-size: 1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.event-when {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.event-arrow { color: var(--color-text-tertiary); }

	.coach-promo {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-decoration: none;
		color: inherit;
		transition:
			background var(--transition-fast),
			border-color var(--transition-fast),
			box-shadow var(--transition-fast);
	}
	.coach-promo:hover {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 4%, var(--color-surface));
		box-shadow: var(--shadow-sm);
	}
	.coach-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 50%;
		background: color-mix(in srgb, var(--color-accent-cyan) 22%, transparent);
		color: var(--color-primary);
		flex-shrink: 0;
	}
	.coach-icon :global(.material-symbols) { font-size: 1.4rem; }
	.coach-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.coach-body strong {
		font-size: 1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.coach-sub {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.coach-arrow { color: var(--color-text-tertiary); }

	.fitness-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		box-shadow: var(--shadow-sm);
	}
	.fitness-row {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr));
		gap: var(--space-md);
		margin-bottom: var(--space-sm);
	}
	.fitness-metric { display: flex; flex-direction: column; }
	.fitness-label {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: var(--section-label-tracking);
	}
	.fitness-value {
		font-size: 1.5rem;
		font-weight: 800;
		margin-top: var(--space-2xs);
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.fitness-value.tsb-neg { color: var(--color-danger); }
	.fitness-value.tsb-pos { color: var(--color-success); }

	.recap-strip {
		display: flex;
		justify-content: flex-end;
	}
	.recap-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-xs) var(--space-md);
		background: color-mix(in srgb, var(--color-secondary) 14%, transparent);
		color: var(--color-secondary);
		border-radius: 9999px;
		font-weight: 600;
		font-size: 0.85rem;
		text-decoration: none;
		transition: background var(--transition-fast);
	}
	.recap-link:hover {
		background: color-mix(in srgb, var(--color-secondary) 22%, transparent);
	}

	.readiness-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		box-shadow: var(--shadow-sm);
	}
	.readiness-card.readiness-high { border-left: 4px solid var(--color-success); }
	.readiness-card.readiness-moderate { border-left: 4px solid var(--color-warning); }
	.readiness-card.readiness-low { border-left: 4px solid var(--color-danger); }
	.readiness-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-secondary);
	}
	.readiness-band {
		padding: var(--space-2xs) var(--space-sm);
		border-radius: 999px;
		background: var(--color-bg-secondary);
	}
	.readiness-card.readiness-high .readiness-band {
		background: color-mix(in srgb, var(--color-success) 14%, transparent);
		color: var(--color-success);
	}
	.readiness-card.readiness-moderate .readiness-band {
		background: color-mix(in srgb, var(--color-warning) 22%, transparent);
		color: var(--color-warning);
	}
	.readiness-card.readiness-low .readiness-band {
		background: color-mix(in srgb, var(--color-danger) 16%, transparent);
		color: var(--color-danger);
	}
	.readiness-score {
		font-size: 2.75rem;
		font-weight: 800;
		line-height: 1;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.readiness-advice {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
	}
	.readiness-contribs {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.readiness-contribs li {
		display: inline-flex;
		gap: var(--space-xs);
		align-items: baseline;
	}
	.contrib-delta { font-variant-numeric: tabular-nums; font-weight: 700; }
	.contrib-delta.positive { color: var(--color-success); }
	.contrib-delta.negative { color: var(--color-danger); }
	.fitness-unit {
		font-size: var(--font-size-section-label);
		color: var(--color-text-tertiary);
		margin-top: var(--space-2xs);
	}
	.fitness-advice {
		margin: var(--space-xs) 0 0;
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.trend {
		width: 100%;
		height: 40px;
		margin-top: var(--space-sm);
		display: block;
		color: var(--color-primary);
	}

	.goals-section { display: flex; flex-direction: column; gap: var(--space-sm); }
	.goals-header {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
	}
	.goals-header h2 {
		font-size: var(--font-size-section-title);
		font-weight: 700;
		margin: 0;
	}
	.link-btn {
		background: transparent;
		border: none;
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		padding: var(--space-xs) var(--space-sm);
		border-radius: var(--radius-sm);
		transition: background var(--transition-fast);
	}
	.link-btn:hover { background: var(--color-primary-light); }
	.goals-empty {
		color: var(--color-text-tertiary);
		font-size: 0.88rem;
		margin: 0;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-lg);
	}
	.goal-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(24rem, 1fr));
		gap: var(--space-lg);
	}
	.goal-card {
		display: block;
		text-align: left;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		cursor: pointer;
		font: inherit;
		color: inherit;
		box-shadow: var(--shadow-sm);
		transition:
			border-color var(--transition-fast),
			box-shadow var(--transition-fast),
			transform var(--transition-fast);
	}
	.goal-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
		transform: translateY(-1px);
	}
	.goal-card-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-md);
	}
	.goal-period {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}
	.goal-overall {
		font-size: 1.65rem;
		font-weight: 800;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
		line-height: 1;
	}
	.goal-targets {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: var(--space-md);
	}
	.goal-target-top {
		display: flex;
		justify-content: space-between;
		font-size: 0.95rem;
		font-weight: 500;
		margin-bottom: var(--space-xs);
	}
	.goal-target-value {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.goal-target-bar {
		height: 0.55rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		overflow: hidden;
	}
	.goal-target-fill {
		height: 100%;
		background: var(--color-primary);
		transition: width 0.4s ease;
	}
	.goal-target-fill.complete { background: var(--color-success); }
	.goal-card-footer {
		margin: var(--space-sm) 0 0;
		font-size: var(--font-size-section-label);
		color: var(--color-text-tertiary);
	}

	/* Goal editor reuses the canonical .modal-* classes from app.css.
	   Only field-level styling stays local. */
	.goal-editor-body { display: grid; gap: var(--space-md); }
	.field { display: grid; gap: var(--space-xs); }
	.field-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.input {
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.9rem;
		font-family: inherit;
	}
	.input:focus {
		outline: 2px solid color-mix(in srgb, var(--color-primary) 40%, transparent);
		outline-offset: 1px;
		border-color: var(--color-primary);
	}
	.toggle-row { display: flex; gap: var(--space-xs); }
	.toggle-btn {
		padding: var(--space-sm) var(--space-md);
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
	}
	.toggle-btn.active {
		background: var(--color-primary);
		color: var(--color-surface);
		border-color: var(--color-primary);
	}
	.goal-editor-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		margin: 0;
	}
	.goal-editor-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-xs);
	}
	.goal-editor-actions .btn-danger { margin-right: auto; }

	/* Stat cards: quiet family. The old per-card rainbow `::before` is
	   gone; cards share the same surface treatment so the eye reads the
	   data, not the decoration. The interactive "This Week" tile lifts
	   on hover; the rest are static. */
	.stat-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		box-shadow: var(--shadow-sm);
		transition:
			box-shadow var(--transition-base),
			border-color var(--transition-base),
			transform var(--transition-base);
	}
	.stat-card:hover {
		box-shadow: var(--shadow-md);
		border-color: color-mix(in srgb, var(--color-primary) 30%, var(--color-border));
	}
	.stat-card-button {
		font: inherit;
		text-align: left;
		cursor: pointer;
		color: inherit;
	}
	.stat-card-button:hover { transform: translateY(-1px); }
	.stat-label {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		margin-bottom: var(--space-xs);
	}
	.stat-value {
		font-size: 1.6rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}
	.stat-unit {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		margin-left: var(--space-2xs);
	}
	.streak-active .stat-value { color: var(--color-warning); }
	.stat-sub {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-xs);
	}
	.manual-hint {
		display: block;
		font-size: 0.72rem;
		color: var(--color-primary);
		margin-top: var(--space-2xs);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		box-shadow: var(--shadow-sm);
		transition: box-shadow var(--transition-base);
	}
	.card:hover { box-shadow: var(--shadow-md); }

	.chart {
		display: flex;
		align-items: flex-end;
		gap: var(--space-sm);
		height: 12rem;
		padding-top: var(--space-md);
	}
	.bar-col {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		height: 100%;
		justify-content: flex-end;
		position: relative;
	}
	.bar-col:hover .bar-tooltip { opacity: 1; }
	.bar-tooltip {
		position: absolute;
		top: -1.5rem;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		opacity: 0;
		transition: opacity var(--transition-fast);
		white-space: nowrap;
		font-variant-numeric: tabular-nums;
	}
	.bar {
		width: 100%;
		max-width: 2.5rem;
		background: linear-gradient(
			180deg,
			var(--color-primary) 0%,
			color-mix(in srgb, var(--color-secondary) 75%, var(--color-primary)) 100%
		);
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
		min-height: 4px;
		transition: height var(--transition-base), background var(--transition-fast);
	}
	.bar-col:hover .bar {
		background: linear-gradient(
			180deg,
			var(--color-primary-hover) 0%,
			var(--color-secondary) 100%
		);
	}
	.bar-label {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-xs);
	}

	.two-col {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-lg);
	}

	.pr-table { width: 100%; border-collapse: collapse; }
	.pr-table th {
		text-align: left;
		font-size: 0.72rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
	}
	.pr-table td {
		padding: var(--space-md) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
	}
	.pr-table tbody tr:last-child td { border-bottom: none; }
	.pr-distance { font-weight: 600; }
	.pr-time {
		font-family: 'SF Mono', 'Menlo', monospace;
		font-weight: 600;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
	}
	.pr-date {
		color: var(--color-text-secondary);
		font-size: 0.875rem;
	}

	.run-list { display: flex; flex-direction: column; }
	.run-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
		transition: background var(--transition-fast);
		text-decoration: none;
		color: inherit;
	}
	.run-row:last-child { border-bottom: none; }
	.run-row:hover {
		background: var(--color-bg-secondary);
		margin: 0 calc(-1 * var(--space-sm));
		padding: var(--space-sm);
		border-radius: var(--radius-sm);
	}
	.run-info { display: flex; gap: var(--space-md); align-items: baseline; }
	.run-date {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		min-width: 4rem;
	}
	.run-distance {
		font-weight: 600;
		font-size: 0.9rem;
		font-variant-numeric: tabular-nums;
	}
	.run-meta {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.run-pace {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		font-family: 'SF Mono', 'Menlo', monospace;
		font-variant-numeric: tabular-nums;
	}
	.source-badge {
		font-size: 0.65rem;
		font-weight: 600;
		color: var(--color-surface);
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}

	/* Why: hero rows reflow before the 4-up stat grid does — keep the
	   reading order intact. 768px tablet first, then 480px phone. */
	@media (max-width: 768px) {
		.stat-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
		.two-col { grid-template-columns: 1fr; }
		.today-card,
		.plan-promo {
			padding: var(--space-md) var(--space-lg);
		}
		.today-card h2 { font-size: 1.2rem; }
	}
	@media (max-width: 480px) {
		.page {
			padding: var(--space-lg) var(--space-md);
			gap: var(--space-md);
		}
		.stat-grid { gap: var(--space-sm); }
		.stat-card { padding: var(--space-md); }
		.stat-value { font-size: 1.35rem; }
		.today-card,
		.plan-promo {
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-sm);
		}
		.today-right { align-items: flex-start; text-align: left; }
		.fitness-card,
		.card,
		.readiness-card,
		.goal-card {
			padding: var(--space-md);
		}
		.chart { height: 9rem; gap: var(--space-xs); }
		.bar-label { font-size: 0.6rem; }
	}
</style>
