<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { fetchWorkout, markWorkoutCompleted } from '$lib/data';
	import { fmtPace, fmtKm, fmtHms, WORKOUT_KIND_LABEL } from '$lib/training';
	import type { PlanWorkout } from '$lib/types';
	import type { WorkoutStructure } from '$lib/training';

	let planId = $derived($page.params.id as string);
	let wid = $derived($page.params.wid as string);
	let workout = $state<PlanWorkout | null>(null);
	let loading = $state(true);

	async function load() {
		loading = true;
		workout = await fetchWorkout(wid);
		loading = false;
	}

	onMount(load);

	let structure = $derived(
		(workout?.structure as unknown as WorkoutStructure | null) ?? null
	);

	async function unlink() {
		if (!workout?.completed_run_id) return;
		if (!confirm('Unlink the matched run? The workout will show as not yet done.')) return;
		await markWorkoutCompleted(workout.id, null);
		await load();
	}

	function intervalTotal(s: WorkoutStructure): number {
		return (
			(s.warmup?.distance_m ?? 0) +
			(s.repeats
				? s.repeats.count * (s.repeats.distance_m + s.repeats.recovery_distance_m)
				: 0) +
			(s.steady?.distance_m ?? 0) +
			(s.cooldown?.distance_m ?? 0)
		);
	}
</script>

{#if loading}
	<p class="centered muted">Loading…</p>
{:else if !workout}
	<div class="centered">
		<h2>Workout not found</h2>
		<a class="btn-secondary" href="/plans/{planId}">Back to plan</a>
	</div>
{:else}
	<div class="page">
		<a class="back" href="/plans/{planId}">
			<span class="material-symbols">arrow_back</span>
			Back to plan
		</a>

		<header class="hero">
			<div>
				<span class="label">{workout.scheduled_date}</span>
				<h1>
					{WORKOUT_KIND_LABEL[workout.kind as keyof typeof WORKOUT_KIND_LABEL] ?? workout.kind}
				</h1>
				<div class="meta">
					{#if workout.target_distance_m != null}
						<div class="metric">
							<span class="m-label">Distance</span>
							<strong>{fmtKm(workout.target_distance_m, 2)}</strong>
						</div>
					{/if}
					{#if workout.target_duration_seconds}
						<div class="metric">
							<span class="m-label">Duration</span>
							<strong>{fmtHms(workout.target_duration_seconds)}</strong>
						</div>
					{/if}
					{#if workout.target_pace_sec_per_km}
						<div class="metric">
							<span class="m-label">Target pace</span>
							<strong>{fmtPace(workout.target_pace_sec_per_km)}</strong>
							{#if workout.target_pace_tolerance_sec}
								<span class="tol">±{workout.target_pace_tolerance_sec}s</span>
							{/if}
						</div>
					{/if}
				</div>
			</div>
			{#if workout.completed_run_id}
				<div class="completed-card">
					<span class="material-symbols">check_circle</span>
					<span>Completed</span>
					<button class="btn-ghost" onclick={unlink}>Unlink</button>
				</div>
			{/if}
		</header>

		{#if workout.notes}
			<section class="card">
				<h3>Notes</h3>
				<p>{workout.notes}</p>
			</section>
		{/if}

		{#if structure}
			<section class="card">
				<h3>Structure</h3>
				<ol class="steps">
					{#if structure.warmup}
						<li>
							<span class="step-kind">Warmup</span>
							<span>{fmtKm(structure.warmup.distance_m, 1)} @ easy</span>
						</li>
					{/if}
					{#if structure.repeats}
						<li>
							<span class="step-kind">Repeats</span>
							<span>
								{structure.repeats.count}× {fmtKm(structure.repeats.distance_m, 2)}
								@ {fmtPace(structure.repeats.pace_sec_per_km)} with
								{fmtKm(structure.repeats.recovery_distance_m, 2)} {structure.repeats.recovery_pace}
							</span>
						</li>
					{/if}
					{#if structure.steady}
						<li>
							<span class="step-kind">Steady</span>
							<span>
								{fmtKm(structure.steady.distance_m, 1)} @ {fmtPace(structure.steady.pace_sec_per_km)}
							</span>
						</li>
					{/if}
					{#if structure.cooldown}
						<li>
							<span class="step-kind">Cooldown</span>
							<span>{fmtKm(structure.cooldown.distance_m, 1)} @ easy</span>
						</li>
					{/if}
				</ol>
				<p class="total">Total: {fmtKm(intervalTotal(structure), 2)}</p>
			</section>
		{/if}

		<section class="card advice">
			<h3>How to run it</h3>
			{#if workout.kind === 'easy' || workout.kind === 'recovery'}
				<p>Conversational pace. If you can't hold a conversation, you're running it too fast.</p>
			{:else if workout.kind === 'long'}
				<p>
					Stay relaxed — aim for steady breathing. If the weather is rough or you're
					sore, drop 10% of the distance rather than skip.
				</p>
			{:else if workout.kind === 'tempo'}
				<p>
					"Comfortably hard". You should feel like you could hold the pace for about an
					hour at peak effort, but no longer.
				</p>
			{:else if workout.kind === 'interval'}
				<p>
					Run the reps hard enough that the last one feels like the first. Don't pick
					a pace you can only hold for two or three reps.
				</p>
			{:else if workout.kind === 'marathon_pace'}
				<p>
					Lock into goal marathon pace exactly. This is a rehearsal session — no
					faster, no slower.
				</p>
			{:else if workout.kind === 'race'}
				<p>Trust the plan. Don't chase a PB in the first mile.</p>
			{:else}
				<p>Rest day — if you need to move, walk or stretch.</p>
			{/if}
		</section>
	</div>
{/if}

<style>
	.page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl);
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
		align-items: flex-start;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-md);
	}
	.hero h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin: 0.3rem 0 0.6rem 0;
	}
	.label {
		font-size: 0.78rem;
		letter-spacing: 0.08em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: 1.4rem;
	}
	.metric {
		display: flex;
		flex-direction: column;
	}
	.m-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
	}
	.tol {
		color: var(--color-text-tertiary);
		margin-left: 0.25rem;
		font-size: 0.78rem;
	}
	.completed-card {
		background: var(--color-primary-light);
		color: var(--color-primary);
		padding: 0.55rem 0.85rem;
		border-radius: var(--radius-md);
		display: flex;
		align-items: center;
		gap: 0.35rem;
		font-weight: 700;
	}
	.completed-card .material-symbols {
		font-size: 1.15rem;
	}
	.btn-ghost {
		background: none;
		border: none;
		color: var(--color-primary);
		font-weight: 600;
		text-decoration: underline;
		cursor: pointer;
		font-size: 0.85rem;
		margin-left: 0.45rem;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.card h3 {
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-tertiary);
		margin-bottom: 0.4rem;
	}
	.card p {
		line-height: 1.55;
	}
	.steps {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.steps li {
		display: flex;
		gap: 0.8rem;
		padding: 0.5rem 0.7rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}
	.step-kind {
		font-weight: 700;
		color: var(--color-primary);
		min-width: 5.5rem;
	}
	.total {
		margin-top: 0.6rem;
		color: var(--color-text-secondary);
		font-weight: 600;
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
