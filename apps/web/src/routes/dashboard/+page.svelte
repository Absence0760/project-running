<script lang="ts">
	import { onMount } from 'svelte';
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
	import { fetchRuns, fetchWeeklyMileage, fetchPersonalRecords, fetchActivePlanOverview, fetchNextRsvpedEvent } from '$lib/data';
	import { fmtPace, fmtKm, WORKOUT_KIND_LABEL } from '$lib/training';
	import { loadSettings, effective } from '$lib/settings';
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
	let weeklyMileage = $state<{ week: string; distance_km: number }[]>([]);
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
	let upcomingEvent = $state<Awaited<ReturnType<typeof fetchNextRsvpedEvent>>>(null);

	// Multi-metric goals — local-only today, per browser. Load on
	// mount; every edit writes back synchronously. See `lib/goals.ts`.
	let goals = $state<RunGoal[]>([]);
	let showGoalEditor = $state(false);
	let editingGoal = $state<RunGoal | null>(null);

	function openNewGoal() {
		editingGoal = {
			id: newGoalId(),
			period: 'week',
			distanceMetres: undefined,
			timeSeconds: undefined,
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
			(g.runCount ?? 0) > 0;
		if (!hasAny) {
			// "Save" on an empty goal is effectively delete.
			goals = goals.filter((x) => x.id !== g.id);
		} else {
			const idx = goals.findIndex((x) => x.id === g.id);
			if (idx >= 0) goals = goals.map((x, i) => (i === idx ? g : x));
			else goals = [...goals, g];
		}
		saveGoals(goals);
		showGoalEditor = false;
		editingGoal = null;
	}

	function deleteGoal(id: string) {
		goals = goals.filter((g) => g.id !== id);
		saveGoals(goals);
		showGoalEditor = false;
		editingGoal = null;
	}

	/// ISO date (YYYY-MM-DD) of the current week's Monday, for deep-
	/// linking the This-Week stat card into `/dashboard/period/...`.
	let weekStartIso = $derived.by(() => {
		const d = new Date();
		d.setHours(0, 0, 0, 0);
		d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
		return d.toISOString().slice(0, 10);
	});

	const sources: { value: RunSource | 'all'; label: string }[] = [
		{ value: 'all', label: 'All' },
		{ value: 'app', label: 'Recorded' },
		{ value: 'strava', label: 'Strava' },
		{ value: 'parkrun', label: 'parkrun' },
		{ value: 'healthkit', label: 'HealthKit' },
	];

	onMount(async () => {
		goals = loadGoals();
		[runs, weeklyMileage, personalRecords, planOverview, upcomingEvent] = await Promise.all([
			fetchRuns(),
			fetchWeeklyMileage(),
			fetchPersonalRecords(),
			fetchActivePlanOverview(),
			fetchNextRsvpedEvent(48),
		]);
		// Best-effort load of the user's weekly-mileage goal from the
		// settings bag. A missing bag (new user, or RLS blip) just
		// leaves `weeklyGoalMetres = null` and the goal card stays hidden.
		try {
			const uid = auth.user?.id;
			if (uid) {
				const settings = await loadSettings(uid);
				weeklyGoalMetres = effective<number>(settings, 'weekly_mileage_goal_m') ?? null;
				const unit = effective<string>(settings, 'preferred_unit');
				if (unit === 'mi') preferredUnit = 'mi';
			}
		} catch (_) {
			// silent — goal card is additive, not load-blocking
		}
		loading = false;
	});

	const now = new Date();
	const weekStart = new Date(now);
	weekStart.setDate(now.getDate() - now.getDay());
	weekStart.setHours(0, 0, 0, 0);

	let filteredRuns = $derived(
		sourceFilter === 'all' ? runs : runs.filter((r) => r.source === sourceFilter)
	);
	let thisWeekRuns = $derived(filteredRuns.filter((r) => new Date(r.started_at) >= weekStart));
	let thisWeekDistance = $derived(thisWeekRuns.reduce((sum, r) => sum + r.distance_m, 0));
	let totalRuns = $derived(filteredRuns.length);
	let longestRun = $derived(filteredRuns.length > 0 ? Math.max(...filteredRuns.map((r) => r.distance_m)) : 0);

	// Mileage chart data based on view mode
	let mileageData = $derived.by(() => {
		if (mileageView === 'weekly') return weeklyMileage;

		// Group runs by month or year
		const groups = new Map<string, number>();
		for (const run of filteredRuns) {
			const d = new Date(run.started_at);
			const key = mileageView === 'monthly'
				? d.toLocaleDateString('en-GB', { month: 'short', year: '2-digit' })
				: String(d.getFullYear());
			groups.set(key, (groups.get(key) ?? 0) + run.distance_m / 1000);
		}
		return Array.from(groups.entries()).map(([week, distance_km]) => ({
			week,
			distance_km: Math.round(distance_km * 10) / 10
		}));
	});

	let maxBar = $derived(
		mileageData.length > 0 ? Math.max(...mileageData.map((w) => w.distance_km)) : 1
	);
</script>

<div class="page">
	<header class="page-header">
		<h1>Dashboard</h1>
	</header>

	{#if loading}
		<p class="loading-text">&nbsp;</p>
	{:else}
		{#if planOverview?.todayWorkout}
			{@const t = planOverview.todayWorkout}
			<a
				class="today-card"
				class:done={!!t.completed_run_id}
				href="/plans/{planOverview.plan.id}/workouts/{t.id}"
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
					{#if t.completed_run_id}
						<span class="material-symbols done-icon">check_circle</span>
					{:else}
						<span class="material-symbols">chevron_right</span>
					{/if}
					<span class="plan-name">{planOverview.plan.name}</span>
					<span class="plan-progress">{planOverview.completionPct}% done</span>
				</div>
			</a>
		{:else if !planOverview}
			<a class="plan-promo" href="/plans/new">
				<div>
					<span class="today-label">TRAINING PLANS</span>
					<h3>Pick a goal race and we'll schedule the weeks</h3>
					<p>5K, 10K, half or full — VDOT-anchored paces, phases, step-back weeks.</p>
				</div>
				<span class="material-symbols">chevron_right</span>
			</a>
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

		<!-- Weekly goal progress — hides when the user hasn't set one.
		     Configure via Settings → Preferences (writes the same
		     `weekly_mileage_goal_m` value Android's dashboard reads). -->
		{#if weeklyGoalMetres != null && weeklyGoalMetres > 0}
			{@const pct = Math.min(100, Math.round((thisWeekDistance / weeklyGoalMetres) * 100))}
			{@const goalDisplay = preferredUnit === 'mi'
				? `${(weeklyGoalMetres / 1609.344).toFixed(1)} mi`
				: `${(weeklyGoalMetres / 1000).toFixed(1)} km`}
			<div class="goal-card">
				<header class="goal-header">
					<div>
						<span class="goal-title">Weekly goal</span>
						<span class="goal-sub">
							{formatDistance(thisWeekDistance)} of {goalDisplay}
						</span>
					</div>
					<span class="goal-pct">{pct}%</span>
				</header>
				<div class="goal-bar">
					<div class="goal-fill" style="width: {pct}%"></div>
				</div>
				<p class="goal-edit-hint">
					<a href="/settings/preferences">Edit goal</a>
				</p>
			</div>
		{/if}

		<!-- Multi-metric goals — local-only. Shows a card per goal with
		     a progress row per target. Empty by default; header button
		     opens the editor. -->
		<section class="goals-section">
			<header class="goals-header">
				<h2>Goals</h2>
				<button type="button" class="link-btn" onclick={openNewGoal}>
					+ Add goal
				</button>
			</header>
			{#if goals.length === 0}
				<p class="goals-empty">
					No goals yet. Set a weekly or monthly target for distance, time,
					or number of runs.
				</p>
			{:else}
				<div class="goal-grid">
					{#each goals as g (g.id)}
						{@const p = evaluateGoal(g, runs, new Date())}
						<button class="goal-card" type="button" onclick={() => openEditGoal(g)}>
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
						</button>
					{/each}
				</div>
			{/if}
		</section>

		<!-- Stat cards -->
		<div class="stat-grid">
			<a href="/dashboard/period/week/{weekStartIso}" class="stat-card">
				<span class="stat-label">This Week</span>
				<span class="stat-value">{formatDistance(thisWeekDistance)}</span>
				<span class="stat-sub">{thisWeekRuns.length} run{thisWeekRuns.length !== 1 ? 's' : ''}</span>
			</a>
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
							) + ' /km'
						: '--'}
				</span>
				<span class="stat-sub">average</span>
			</div>
		</div>

		<!-- Source filter -->
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
						<div class="bar-tooltip">{week.distance_km.toFixed(1)} km</div>
						<div
							class="bar"
							style="height: {(week.distance_km / maxBar) * 100}%"
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
				<div class="run-list">
					{#each filteredRuns.slice(0, 7) as run}
						<a href="/runs/{run.id}" class="run-row">
							<div class="run-info">
								<span class="run-date">{formatDateShort(run.started_at)}</span>
								<span class="run-distance">{formatDistance(run.distance_m)}</span>
							</div>
							<div class="run-meta">
								<span class="run-pace">{formatPace(run.duration_s, run.distance_m)} /km</span>
								<span class="source-badge" style="background: {sourceColor(run.source)}">{sourceLabel(run.source)}</span>
							</div>
						</a>
					{/each}
				</div>
			</section>
		</div>
	{/if}
</div>

{#if showGoalEditor && editingGoal}
	{@const eg = editingGoal}
	<div class="backdrop" onclick={() => (showGoalEditor = false)} role="presentation"></div>
	<div class="goal-editor" role="dialog" aria-label="Edit goal">
		<h3>Edit goal</h3>
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
			<span class="field-label">Distance (km)</span>
			<input
				type="number"
				min="0"
				step="0.5"
				value={eg.distanceMetres != null ? eg.distanceMetres / 1000 : ''}
				placeholder="—"
				oninput={(e) => {
					const v = (e.currentTarget as HTMLInputElement).value;
					editingGoal = {
						...eg,
						distanceMetres: v === '' ? undefined : Math.max(0, parseFloat(v) * 1000),
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
				<button type="button" class="btn-danger" onclick={() => deleteGoal(eg.id)}>
					Delete
				</button>
			{/if}
			<button type="button" class="btn-secondary" onclick={() => (showGoalEditor = false)}>
				Cancel
			</button>
			<button type="button" class="btn-primary" onclick={() => commitGoal(eg)}>
				Save
			</button>
		</div>
	</div>
{/if}

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 72rem;
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}

	h2 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: var(--space-lg);
		color: var(--color-text);
	}

	.loading-text {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.empty-text {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}

	.filter-row {
		display: flex;
		gap: var(--space-xs);
		margin-bottom: var(--space-xl);
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
		color: white;
		box-shadow: 0 2px 8px rgba(79, 70, 229, 0.25);
	}

	.chart-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}

	.chart-header h2 {
		margin-bottom: 0;
	}

	.view-toggle {
		display: flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		overflow: hidden;
	}

	.view-toggle button {
		padding: var(--space-xs) var(--space-md);
		border: none;
		background: var(--color-surface);
		font-size: 0.75rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.view-toggle button:not(:last-child) {
		border-right: 1px solid var(--color-border);
	}

	.view-toggle button.active {
		background: var(--color-primary);
		color: white;
		box-shadow: 0 1px 4px rgba(79, 70, 229, 0.3);
	}

	.today-card {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 1rem;
		padding: 1rem 1.2rem;
		margin-bottom: var(--space-md);
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 15%, var(--color-surface)),
			var(--color-surface)
		);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		color: inherit;
		transition: transform var(--transition-base), box-shadow var(--transition-base);
	}
	.today-card:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-md);
	}
	.today-card.done {
		opacity: 0.85;
	}
	.today-label {
		font-size: 0.72rem;
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
	}
	.today-card h2 {
		margin: 0.35rem 0 0.25rem 0;
		font-size: 1.3rem;
	}
	.today-meta {
		display: flex;
		gap: 0.8rem;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
	}
	.today-right {
		text-align: right;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 0.2rem;
		color: var(--color-text-secondary);
	}
	.plan-name {
		font-weight: 600;
		color: var(--color-text);
		font-size: 0.9rem;
	}
	.plan-progress {
		font-size: 0.8rem;
	}
	.done-icon {
		color: var(--color-primary);
		font-size: 1.6rem;
	}
	.plan-promo {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 0.9rem 1.2rem;
		margin-bottom: var(--space-md);
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-lg);
		color: inherit;
	}
	.plan-promo h3 {
		font-size: 1.05rem;
		margin: 0.3rem 0 0.2rem 0;
	}
	.plan-promo p {
		color: var(--color-text-secondary);
		font-size: 0.88rem;
	}

	.stat-grid {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}

	.goal-card {
		background: var(--color-surface);
		border: 1px solid var(--color-primary);
		border-radius: var(--radius-lg);
		padding: 1rem 1.25rem;
		margin-bottom: var(--space-lg);
	}
	.goal-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: 0.6rem;
	}
	.goal-title {
		display: block;
		font-size: 0.8rem;
		font-weight: 700;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.goal-sub {
		display: block;
		font-size: 1rem;
		font-weight: 600;
		margin-top: 0.2rem;
	}
	.goal-pct {
		font-size: 1.4rem;
		font-weight: 800;
		color: var(--color-primary);
	}
	.goal-bar {
		height: 0.55rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		overflow: hidden;
	}
	.goal-fill {
		height: 100%;
		background: var(--color-primary);
		border-radius: 9999px;
		transition: width 0.4s ease;
	}
	.goal-edit-hint {
		margin: 0.5rem 0 0;
		font-size: 0.78rem;
		text-align: right;
	}
	.goal-edit-hint a {
		color: var(--color-text-tertiary);
		text-decoration: none;
	}
	.goal-edit-hint a:hover { text-decoration: underline; }

	.event-card {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 1rem 1.25rem;
		margin-bottom: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-primary);
		border-radius: var(--radius-lg);
		text-decoration: none;
		color: inherit;
		transition: background 0.15s ease;
	}
	.event-card:hover {
		background: color-mix(in srgb, var(--color-primary) 6%, var(--color-surface));
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
	}
	.event-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
	}
	.event-label {
		font-size: 0.72rem;
		font-weight: 700;
		color: var(--color-primary);
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}
	.event-title {
		font-size: 1rem;
	}
	.event-when {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.event-arrow {
		color: var(--color-text-tertiary);
	}

	.goals-section {
		margin-bottom: var(--space-xl);
	}
	.goals-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-sm);
	}
	.goals-header h2 {
		font-size: 1rem;
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
		padding: 0.3rem 0.5rem;
	}
	.goals-empty {
		color: var(--color-text-tertiary);
		font-size: 0.88rem;
		margin: 0;
	}
	.goal-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
		gap: var(--space-md);
	}
	.goal-card {
		display: block;
		text-align: left;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1rem 1.25rem;
		cursor: pointer;
		font: inherit;
		color: inherit;
	}
	.goal-card:hover { border-color: var(--color-primary); }
	.goal-card-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 0.6rem;
	}
	.goal-period {
		font-size: 0.72rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}
	.goal-overall {
		font-size: 1.1rem;
		font-weight: 800;
		color: var(--color-primary);
	}
	.goal-targets {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 0.5rem;
	}
	.goal-target-top {
		display: flex;
		justify-content: space-between;
		font-size: 0.85rem;
		margin-bottom: 0.2rem;
	}
	.goal-target-value { color: var(--color-text-secondary); }
	.goal-target-bar {
		height: 0.4rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		overflow: hidden;
	}
	.goal-target-fill {
		height: 100%;
		background: var(--color-primary);
		transition: width 0.4s ease;
	}
	.goal-target-fill.complete {
		background: #2e7d32;
	}

	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		z-index: 100;
	}
	.goal-editor {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
		width: min(92vw, 22rem);
		z-index: 101;
		display: grid;
		gap: 0.9rem;
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4);
	}
	.goal-editor h3 {
		margin: 0;
		font-size: 1rem;
		font-weight: 700;
	}
	.field { display: grid; gap: 0.3rem; }
	.field-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.input {
		padding: 0.5rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.9rem;
		font-family: inherit;
	}
	.toggle-row { display: flex; gap: 0.3rem; }
	.toggle-btn {
		padding: 0.4rem 0.9rem;
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
	}
	.toggle-btn.active {
		background: var(--color-primary);
		color: white;
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
		gap: 0.4rem;
	}
	.btn-primary,
	.btn-secondary,
	.btn-danger {
		padding: 0.5rem 1rem;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
		font-weight: 600;
		cursor: pointer;
		border: 1px solid transparent;
	}
	.btn-primary { background: var(--color-primary); color: white; }
	.btn-secondary {
		background: transparent;
		color: var(--color-text-secondary);
		border-color: var(--color-border);
	}
	.btn-danger {
		background: transparent;
		color: var(--color-danger);
		border-color: var(--color-danger);
		margin-right: auto;
	}

	.stat-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		position: relative;
		overflow: hidden;
		transition: all var(--transition-base);
	}

	.stat-card::before {
		content: '';
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		height: 3px;
		border-radius: var(--radius-lg) var(--radius-lg) 0 0;
	}

	.stat-card:nth-child(1)::before { background: linear-gradient(90deg, #4F46E5, #7C3AED); }
	.stat-card:nth-child(2)::before { background: linear-gradient(90deg, #10B981, #06B6D4); }
	.stat-card:nth-child(3)::before { background: linear-gradient(90deg, #F97316, #F59E0B); }
	.stat-card:nth-child(4)::before { background: linear-gradient(90deg, #EC4899, #EF4444); }

	.stat-card:hover {
		box-shadow: var(--shadow-md);
		border-color: transparent;
	}

	.stat-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		margin-bottom: var(--space-xs);
	}

	.stat-value {
		font-size: 1.5rem;
		font-weight: 700;
		color: var(--color-text);
	}

	.stat-sub {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-xs);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
		transition: all var(--transition-base);
	}

	.card:hover {
		box-shadow: var(--shadow-md);
	}

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

	.bar-col:hover .bar-tooltip {
		opacity: 1;
	}

	.bar-tooltip {
		position: absolute;
		top: -1.5rem;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		opacity: 0;
		transition: opacity var(--transition-fast);
		white-space: nowrap;
	}

	.bar {
		width: 100%;
		max-width: 2.5rem;
		background: linear-gradient(180deg, #4F46E5, #7C3AED);
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
		min-height: 4px;
		transition: height var(--transition-base);
	}

	.bar-col:hover .bar {
		background: linear-gradient(180deg, #6366F1, #A78BFA);
	}

	.bar-label {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-xs);
	}

	.two-col {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-xl);
	}

	.pr-table {
		width: 100%;
		border-collapse: collapse;
	}

	.pr-table th {
		text-align: left;
		font-size: 0.75rem;
		font-weight: 500;
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

	.pr-distance {
		font-weight: 600;
	}

	.pr-time {
		font-family: 'SF Mono', 'Menlo', monospace;
		font-weight: 600;
		color: var(--color-primary);
	}

	.pr-date {
		color: var(--color-text-secondary);
		font-size: 0.875rem;
	}

	.run-list {
		display: flex;
		flex-direction: column;
	}

	.run-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
		transition: background var(--transition-fast);
	}

	.run-row:last-child {
		border-bottom: none;
	}

	.run-row:hover {
		background: var(--color-bg-secondary);
		margin: 0 calc(-1 * var(--space-sm));
		padding: var(--space-sm);
		border-radius: var(--radius-sm);
	}

	.run-info {
		display: flex;
		gap: var(--space-md);
		align-items: baseline;
	}

	.run-date {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		min-width: 4rem;
	}

	.run-distance {
		font-weight: 600;
		font-size: 0.9rem;
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
	}

	.source-badge {
		font-size: 0.65rem;
		font-weight: 600;
		color: white;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}

	@media (max-width: 768px) {
		.stat-grid { grid-template-columns: repeat(2, 1fr); }
		.two-col { grid-template-columns: 1fr; }
	}
</style>
