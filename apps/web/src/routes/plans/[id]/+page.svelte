<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { fetchPlan } from '$lib/data';
	import WorkoutEditor from '$lib/components/WorkoutEditor.svelte';
	import CoachChat from '$lib/components/CoachChat.svelte';
	import PlanCalendar from '$lib/components/PlanCalendar.svelte';
	import {
		fmtHms,
		PHASE_LABEL,
		WORKOUT_KIND_LABEL,
		parseISO,
		todayISO
	} from '$lib/training';
	import { fmtKm, fmtPace } from '$lib/units.svelte';
	import type { TrainingPlan, PlanWeek, PlanWorkout } from '$lib/types';

	let id = $derived($page.params.id as string);
	let plan = $state<TrainingPlan | null>(null);
	let weeks = $state<PlanWeek[]>([]);
	let workouts = $state<PlanWorkout[]>([]);
	let loading = $state(true);
	let editing = $state<PlanWorkout | null>(null);

	async function load() {
		loading = true;
		const res = await fetchPlan(id);
		plan = res.plan;
		weeks = res.weeks;
		workouts = res.workouts;
		loading = false;
	}

	onMount(load);

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

	let currentWeek = $derived.by(() => {
		if (!plan) return null;
		const dayIndex = Math.floor(
			(parseISO(today).getTime() - parseISO(plan.start_date).getTime()) /
				(1000 * 60 * 60 * 24)
		);
		if (dayIndex < 0) return 0;
		return Math.min(weeks.length - 1, Math.floor(dayIndex / 7));
	});

	let completed = $derived(workouts.filter((w) => w.completed_run_id).length);
	let totalActive = $derived(workouts.filter((w) => w.kind !== 'rest').length);
	let pct = $derived(totalActive === 0 ? 0 : Math.round((completed / totalActive) * 100));

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
</script>

{#if loading}
	<p class="centered muted">Loading…</p>
{:else if !plan}
	<div class="centered">
		<h2>Plan not found</h2>
		<a href="/plans" class="btn-secondary">Back to plans</a>
	</div>
{:else}
	<div class="page">
		<a class="back" href="/plans">
			<span class="material-symbols">arrow_back</span>
			All plans
		</a>

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

		<header class="hero">
			<div>
				<h1>{plan.name}</h1>
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
					<span>
						<span class="material-symbols">calendar_today</span>
						{plan.start_date} → {plan.end_date}
					</span>
				</div>
			</div>
			<div class="progress">
				<div class="progress-circle">
					<span class="pct">{pct}%</span>
					<span class="done">
						{completed} / {totalActive}
					</span>
				</div>
			</div>
		</header>

		{#if todayWorkout}
			<section class="today">
				<span class="label">TODAY</span>
				<a class="today-link" href="/plans/{plan.id}/workouts/{todayWorkout.id}">
					<h2>
						{WORKOUT_KIND_LABEL[todayWorkout.kind as keyof typeof WORKOUT_KIND_LABEL] ?? todayWorkout.kind}
					</h2>
					<div class="today-meta">
						{#if todayWorkout.target_distance_m != null}
							<span>{fmtKm(todayWorkout.target_distance_m)}</span>
						{/if}
						{#if todayWorkout.target_pace_sec_per_km}
							<span>@ {fmtPace(todayWorkout.target_pace_sec_per_km)}</span>
						{/if}
						{#if todayWorkout.completed_run_id}
							<span class="done-chip">
								<span class="material-symbols">check_circle</span>
								Completed
							</span>
						{/if}
					</div>
					{#if todayWorkout.notes}
						<p class="today-notes">{todayWorkout.notes}</p>
					{/if}
				</a>
			</section>
		{/if}

		<section class="calendar-section">
			<h2 class="section-title">Calendar</h2>
			<PlanCalendar
				startDate={plan.start_date}
				endDate={plan.end_date}
				{workouts}
				planId={plan.id}
			/>
		</section>

		<section class="weeks">
			{#each weeks as w (w.id)}
				<article
					class="week"
					class:current={w.week_index === currentWeek}
					class:future={w.week_index > (currentWeek ?? -1)}
				>
					<header class="week-header">
						<div>
							<span class="week-num">Week {w.week_index + 1}</span>
							<span class="week-phase">{PHASE_LABEL[w.phase as keyof typeof PHASE_LABEL] ?? w.phase}</span>
						</div>
						<span class="week-volume">{fmtKm(w.target_volume_m, 0)}</span>
					</header>
					{#if w.notes}
						<p class="week-note">{w.notes}</p>
					{/if}
					<div class="day-grid">
						{#each workoutsByWeek.get(w.id) ?? [] as wo (wo.id)}
							<div
								class="day"
								class:today={wo.scheduled_date === today}
								class:completed={!!wo.completed_run_id}
								class:rest={wo.kind === 'rest'}
								style="--kind-color: {kindColor[wo.kind] ?? 'var(--color-text-secondary)'}"
							>
								<a class="day-link" href="/plans/{plan.id}/workouts/{wo.id}">
									<span class="dow">{dayOfWeek(wo.scheduled_date)}</span>
									<span class="kind">
										{WORKOUT_KIND_LABEL[wo.kind as keyof typeof WORKOUT_KIND_LABEL] ??
											wo.kind}
									</span>
									{#if wo.target_distance_m != null && wo.kind !== 'rest'}
										<span class="dist">{fmtKm(wo.target_distance_m, 1)}</span>
									{/if}
									{#if wo.completed_run_id}
										<span class="material-symbols check">check_circle</span>
									{/if}
								</a>
								<button
									class="edit"
									aria-label="Edit workout"
									onclick={() => (editing = wo)}
								>
									<span class="material-symbols">edit</span>
								</button>
							</div>
						{/each}
					</div>
				</article>
			{/each}
		</section>

		<section class="coach-section">
			<h2 class="section-title">Coach</h2>
			<CoachChat planId={plan.id} />
		</section>
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

<style>
	.page {
		max-width: 60rem;
		padding: var(--space-xl) var(--space-2xl);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
	}
	.hero {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-md);
	}
	h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}
	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: 1rem;
		margin-top: 0.4rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.meta span {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}
	.meta .material-symbols {
		font-size: 1rem;
	}
	.progress-circle {
		width: 5rem;
		height: 5rem;
		border-radius: 50%;
		border: 5px solid var(--color-primary);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
	}
	.pct {
		font-size: 1.2rem;
		font-weight: 700;
	}
	.done {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
	}
	.today {
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 14%, var(--color-surface)),
			var(--color-surface)
		);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.today .label {
		font-size: 0.75rem;
		letter-spacing: 0.08em;
		color: var(--color-primary);
		font-weight: 700;
	}
	.today-link {
		color: inherit;
		display: block;
	}
	.today-link h2 {
		font-size: 1.25rem;
		margin: 0.35rem 0;
		font-weight: 700;
	}
	.today-meta {
		display: flex;
		gap: 0.8rem;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
	}
	.today-notes {
		color: var(--color-text-secondary);
		margin-top: 0.4rem;
		font-size: 0.9rem;
	}
	.done-chip {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-primary);
		font-weight: 600;
	}
	.done-chip .material-symbols {
		font-size: 1rem;
	}
	.week {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-sm);
		transition: opacity var(--transition-base);
	}
	.week.future {
		opacity: 0.8;
	}
	.week.current {
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--color-primary) 35%, transparent);
	}
	.week-header {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		margin-bottom: 0.5rem;
	}
	.week-num {
		font-weight: 700;
		font-size: 1rem;
	}
	.week-phase {
		margin-left: 0.6rem;
		font-size: 0.78rem;
		letter-spacing: 0.07em;
		text-transform: uppercase;
		color: var(--color-primary);
	}
	.week-volume {
		color: var(--color-text-secondary);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
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
	@media (max-width: 40rem) {
		.day-grid {
			grid-template-columns: repeat(2, 1fr);
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
	}
	.day:hover {
		border-color: var(--color-primary);
	}
	.day-link {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		color: inherit;
	}
	.edit {
		position: absolute;
		right: 0.2rem;
		bottom: 0.2rem;
		background: transparent;
		border: none;
		cursor: pointer;
		color: var(--color-text-tertiary);
		padding: 0.1rem;
		opacity: 0;
		transition: opacity 0.15s ease;
	}
	.day:hover .edit {
		opacity: 1;
	}
	.edit:hover {
		color: var(--color-primary);
	}
	.edit .material-symbols {
		font-size: 0.95rem;
	}
	.day.rest {
		opacity: 0.5;
	}
	.day.today {
		background: color-mix(in srgb, var(--color-primary) 10%, var(--color-surface));
	}
	.day.completed {
		background: color-mix(in srgb, var(--color-primary) 16%, var(--color-surface));
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
		color: var(--color-primary);
		font-size: 1rem;
	}
	.coach-section {
		margin-top: var(--space-xl);
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
	.centered {
		text-align: center;
		padding: var(--space-2xl);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
	.btn-secondary {
		background: transparent;
		color: var(--color-text);
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		border: 1px solid var(--color-border);
		font-weight: 600;
	}
</style>
