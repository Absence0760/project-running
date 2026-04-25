<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import { fetchMyPlans, deletePlan, updatePlanStatus } from '$lib/data';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import PlanEditor from '$lib/components/PlanEditor.svelte';
	import type { TrainingPlan } from '$lib/types';

	let plans = $state<TrainingPlan[]>([]);
	let loading = $state(true);
	let confirmTarget = $state<TrainingPlan | null>(null);
	let confirmAction = $state<'abandon' | 'delete' | null>(null);

	async function load() {
		loading = true;
		plans = await fetchMyPlans();
		loading = false;
	}

	onMount(async () => {
		await load();
		// Deep-link from the dashboard's "Pick a goal race" CTA: opening
		// `/plans?new=1` lands here with the create-plan modal already
		// open. Strip the query so a refresh doesn't re-open the modal.
		if ($page.url.searchParams.get('new') === '1') {
			showPlanModal = true;
			goto('/plans', { replaceState: true, noScroll: true });
		}
	});

	const eventLabels: Record<string, string> = {
		distance_5k: '5K',
		distance_10k: '10K',
		distance_half: 'Half marathon',
		distance_full: 'Marathon',
		custom: 'Custom'
	};

	const statusIcon: Record<string, string> = {
		active: 'play_circle',
		completed: 'check_circle',
		abandoned: 'cancel'
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

	function abandon(p: TrainingPlan) {
		confirmTarget = p;
		confirmAction = 'abandon';
	}

	function remove(p: TrainingPlan) {
		confirmTarget = p;
		confirmAction = 'delete';
	}

	async function handleConfirmAction() {
		if (!confirmTarget || !confirmAction) return;
		if (confirmAction === 'abandon') {
			await updatePlanStatus(confirmTarget.id, 'abandoned');
		} else {
			await deletePlan(confirmTarget.id);
		}
		confirmTarget = null;
		confirmAction = null;
		await load();
	}

	function cancelConfirm() {
		confirmTarget = null;
		confirmAction = null;
	}

	let showPlanModal = $state(false);

	function handlePlanCreated(plan: { id: string }) {
		showPlanModal = false;
		// Plan creation is heavyweight — drop straight into the new plan
		// detail page so the user can review weeks, edit workouts, etc.
		goto(`/plans/${plan.id}`);
	}
</script>

<div class="page">
	<header class="page-header">
		<div class="title-row">
			<button class="btn-primary" type="button" onclick={() => (showPlanModal = true)}>
				<span class="material-symbols">add</span>
				New plan
			</button>
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
			<button class="btn-primary" type="button" onclick={() => (showPlanModal = true)}>
				<span class="material-symbols">add</span>
				Create your first plan
			</button>
		</div>
	{:else}
		<div class="grid">
			{#each plans as p (p.id)}
				<a class="card" href="/plans/{p.id}">
					<div class="card-head">
						<h3>{p.name}</h3>
						<span class="badge status-{p.status}">
						<span class="material-symbols">{statusIcon[p.status] ?? 'help'}</span>
						{p.status}
					</span>
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

<ConfirmDialog
	open={confirmTarget !== null}
	title={confirmAction === 'abandon' ? 'Abandon plan' : 'Delete plan'}
	message={confirmAction === 'abandon'
		? `Abandon "${confirmTarget?.name}"? You can create a new plan after.`
		: `Delete "${confirmTarget?.name}"? All weeks and workouts will be removed.`}
	confirmLabel={confirmAction === 'abandon' ? 'Abandon' : 'Delete'}
	onconfirm={handleConfirmAction}
	oncancel={cancelConfirm}
	danger
/>

{#if showPlanModal}
	<div class="modal-backdrop" role="presentation" onclick={() => (showPlanModal = false)}></div>
	<div class="modal modal-wide" role="dialog" aria-modal="true" aria-label="New plan">
		<header class="modal-header">
			<h2>New plan</h2>
			<button
				class="modal-close"
				type="button"
				aria-label="Close"
				onclick={() => (showPlanModal = false)}
			>
				<span class="material-symbols">close</span>
			</button>
		</header>
		<div class="modal-body">
			<PlanEditor oncreated={handlePlanCreated} oncancel={() => (showPlanModal = false)} />
		</div>
	</div>
{/if}

<style>
	.page {
		max-width: 72rem;
		padding: var(--space-xl) var(--space-2xl);
	}
	.page-header {
		margin-bottom: var(--space-lg);
	}
	.title-row {
		display: flex;
		align-items: center;
		justify-content: flex-end;
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
	.btn-ghost {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
		font-weight: 600;
		cursor: pointer;
		font-size: 0.8rem;
		padding: 0.35rem 0.8rem;
		border-radius: var(--radius-md);
		transition:
			background var(--transition-fast),
			border-color var(--transition-fast),
			color var(--transition-fast);
	}
	.btn-ghost:hover,
	.btn-ghost.danger:hover {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
		color: var(--color-primary);
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
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: 0.2rem 0.55rem;
		border-radius: var(--radius-sm);
	}
	.badge .material-symbols {
		font-size: 0.95rem;
	}
	.status-active {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.status-completed {
		background: var(--color-success-light);
		color: var(--color-success);
	}
	.status-abandoned {
		background: var(--color-danger-light);
		color: var(--color-danger);
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

	/* .modal-* classes live in app.css. */
</style>
