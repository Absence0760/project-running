<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchMyPlans, deletePlan, updatePlanStatus } from '$lib/data';
	import { fmtPace } from '$lib/training';
	import type { TrainingPlan } from '$lib/types';

	let plans = $state<TrainingPlan[]>([]);
	let loading = $state(true);

	async function load() {
		loading = true;
		plans = await fetchMyPlans();
		loading = false;
	}

	onMount(load);

	const eventLabels: Record<string, string> = {
		distance_5k: '5K',
		distance_10k: '10K',
		distance_half: 'Half marathon',
		distance_full: 'Marathon',
		custom: 'Custom'
	};

	function goalTime(p: TrainingPlan): string {
		if (!p.goal_time_seconds) return 'Finish';
		const h = Math.floor(p.goal_time_seconds / 3600);
		const m = Math.floor((p.goal_time_seconds % 3600) / 60);
		const s = p.goal_time_seconds % 60;
		return h > 0
			? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
			: `${m}:${String(s).padStart(2, '0')}`;
	}

	async function abandon(p: TrainingPlan) {
		if (!confirm(`Abandon "${p.name}"? You can create a new plan after.`)) return;
		await updatePlanStatus(p.id, 'abandoned');
		await load();
	}

	async function remove(p: TrainingPlan) {
		if (!confirm(`Delete "${p.name}"? All weeks and workouts will be removed.`)) return;
		await deletePlan(p.id);
		await load();
	}
</script>

<div class="page">
	<header class="page-header">
		<div class="title-row">
			<h1>Training plans</h1>
			<a href="/plans/new" class="btn-primary">
				<span class="material-symbols">add</span>
				New plan
			</a>
		</div>
		<p class="sub">
			Goal-race plans, 8–16 weeks, with easy / long / tempo / interval /
			marathon-pace sessions built around a Daniels-style pace engine. Your
			active plan drives the "today's workout" card on the dashboard.
		</p>
	</header>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else if plans.length === 0}
		<div class="empty">
			<h2>No plans yet.</h2>
			<p>Pick a goal race and we'll schedule the weeks for you.</p>
			<a href="/plans/new" class="btn-primary">
				<span class="material-symbols">add</span>
				Create your first plan
			</a>
		</div>
	{:else}
		<div class="grid">
			{#each plans as p (p.id)}
				<a class="card" href="/plans/{p.id}">
					<div class="card-head">
						<h3>{p.name}</h3>
						<span class="badge status-{p.status}">{p.status}</span>
					</div>
					<div class="meta">
						<span>
							<span class="material-symbols">flag</span>
							{eventLabels[p.goal_event] ?? p.goal_event}
						</span>
						<span>
							<span class="material-symbols">timer</span>
							{goalTime(p)}
						</span>
						{#if p.vdot}
							<span>
								<span class="material-symbols">trending_up</span>
								VDOT {Number(p.vdot).toFixed(1)}
							</span>
						{/if}
					</div>
					<div class="dates">
						{p.start_date} → {p.end_date}
						<span class="per-week">· {p.days_per_week} days/week</span>
					</div>
					{#if p.status === 'active'}
						<div class="card-actions">
							<button
								class="btn-ghost"
								onclick={(e) => {
									e.preventDefault();
									abandon(p);
								}}>Abandon</button
							>
						</div>
					{:else}
						<div class="card-actions">
							<button
								class="btn-ghost danger"
								onclick={(e) => {
									e.preventDefault();
									remove(p);
								}}>Delete</button
							>
						</div>
					{/if}
				</a>
			{/each}
		</div>
	{/if}
</div>

<style>
	.page {
		max-width: 64rem;
		margin: 0 auto;
		padding: var(--space-xl);
	}
	.page-header {
		margin-bottom: var(--space-lg);
	}
	.title-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 700;
	}
	.sub {
		color: var(--color-text-secondary);
		margin-top: 0.3rem;
		max-width: 44rem;
	}
	.btn-primary {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		background: var(--color-primary);
		color: var(--color-bg);
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.9rem;
	}
	.btn-primary:hover {
		background: var(--color-primary-hover);
	}
	.btn-ghost {
		background: transparent;
		border: none;
		color: var(--color-text-secondary);
		font-weight: 600;
		cursor: pointer;
		font-size: 0.85rem;
	}
	.btn-ghost.danger:hover {
		color: var(--color-danger);
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(20rem, 1fr));
		gap: var(--space-md);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		color: inherit;
		transition:
			transform var(--transition-base),
			box-shadow var(--transition-base);
	}
	.card:hover {
		transform: translateY(-2px);
		box-shadow: var(--shadow-md);
	}
	.card-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	.card-head h3 {
		font-size: 1.05rem;
		font-weight: 700;
	}
	.badge {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: 0.15rem 0.5rem;
		border-radius: var(--radius-sm);
	}
	.status-active {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.status-completed {
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
	}
	.status-abandoned {
		background: var(--color-bg-tertiary);
		color: var(--color-text-tertiary);
	}
	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: 0.9rem;
		color: var(--color-text-secondary);
		font-size: 0.88rem;
	}
	.meta span {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}
	.meta .material-symbols {
		font-size: 1rem;
	}
	.dates {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.per-week {
		color: var(--color-text-tertiary);
	}
	.card-actions {
		display: flex;
		justify-content: flex-end;
		margin-top: 0.3rem;
	}
	.empty {
		padding: var(--space-2xl);
		text-align: center;
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-lg);
	}
	.empty h2 {
		font-size: 1.25rem;
		margin-bottom: 0.4rem;
	}
	.empty p {
		color: var(--color-text-secondary);
		margin-bottom: 1rem;
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
