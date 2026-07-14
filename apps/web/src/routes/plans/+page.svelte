<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDuration } from '$lib/format/time';
	import { formatDateShort } from '$lib/format/time';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import { fetchMyPlansWithError, deletePlan, updatePlanStatus } from '$lib/core/data';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	import RunSurfaceTabs from '$lib/components/RunSurfaceTabs.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import PlanEditor from '$lib/components/PlanEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import type { TrainingPlan, PlanStatus } from '$lib/types';
	import type { Snapshot } from './$types';

	let plans = $state<TrainingPlan[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let confirmTarget = $state<TrainingPlan | null>(null);
	let confirmAction = $state<'abandon' | 'delete' | null>(null);
	let showPlanModal = $state(false);

	type StatusFilter = 'all' | PlanStatus;
	let statusFilter = $state<StatusFilter>('all');

	async function load() {
		loading = true;
		loadError = null;
		const result = await fetchMyPlansWithError();
		plans = result.plans;
		loadError = result.error;
		loading = false;
	}

	onMount(async () => {
		// Snapshot restore (below) repopulates `plans` synchronously
		// when navigating back, so skip the fetch — otherwise a flash
		// of "loading" replaces the restored list and breaks scroll.
		if (!(plans.length > 0 && !loading)) await load();
		// Deep-link from the dashboard's "Pick a goal race" CTA: opening
		// `/plans?new=1` lands here with the create-plan modal already
		// open. Strip the query so a refresh doesn't re-open the modal.
		if ($page.url.searchParams.get('new') === '1') {
			showPlanModal = true;
			goto('/plans', { replaceState: true, noScroll: true });
		}
	});

	export const snapshot: Snapshot<{ plans: TrainingPlan[]; statusFilter: StatusFilter }> = {
		capture: () => ({ plans, statusFilter }),
		restore: (s) => {
			plans = s.plans;
			statusFilter = s.statusFilter;
			loading = false;
		}
	};

	const eventLabels: Record<string, () => string> = {
		distance_5k: () => '5K',
		distance_10k: () => '10K',
		distance_half: () => m('plansPage.eventHalf'),
		distance_full: () => m('plansPage.eventFull'),
		custom: () => m('plansPage.eventCustom')
	};

	const statusIcon: Record<PlanStatus, string> = {
		active: 'play_circle',
		paused: 'pause_circle',
		completed: 'check_circle',
		abandoned: 'cancel'
	};

	function statusLabel(s: PlanStatus): string {
		if (s === 'active') return m('plansPage.statusActive');
		if (s === 'paused') return m('plansPage.statusPaused');
		if (s === 'completed') return m('plansPage.statusCompleted');
		return m('plansPage.statusAbandoned');
	}

	const statusFilters: { value: StatusFilter; label: () => string; icon: string }[] = [
		{ value: 'all', label: () => m('plansPage.filterAll'), icon: 'apps' },
		{ value: 'active', label: () => m('plansPage.filterActive'), icon: 'play_circle' },
		{ value: 'paused', label: () => m('plansPage.filterPaused'), icon: 'pause_circle' },
		{ value: 'completed', label: () => m('plansPage.filterCompleted'), icon: 'check_circle' },
		{ value: 'abandoned', label: () => m('plansPage.filterAbandoned'), icon: 'cancel' }
	];

	function goalTime(p: TrainingPlan): string {
		return p.goal_time_seconds ? formatDuration(p.goal_time_seconds) : m('plansPage.goalFinish');
	}

	/// Local-tz midnight, mirrors how `fetchActivePlanOverview` computes
	/// `today` on the detail side. Avoids a UTC drift on or near midnight.
	function todayMidnight(): Date {
		const d = new Date();
		d.setHours(0, 0, 0, 0);
		return d;
	}

	function planMidnight(iso: string): Date {
		const d = new Date(iso + 'T00:00:00');
		d.setHours(0, 0, 0, 0);
		return d;
	}

	/// Total weeks the plan spans, rounded up. Inclusive of both endpoints.
	function totalWeeks(p: TrainingPlan): number {
		const ms = planMidnight(p.end_date).getTime() - planMidnight(p.start_date).getTime();
		const days = Math.max(1, Math.round(ms / 86_400_000) + 1);
		return Math.max(1, Math.ceil(days / 7));
	}

	/// Calendar-week index within the plan, 1-based. Capped to [1, total].
	/// Used only as a coarse position indicator on the card — the plan
	/// detail page has the authoritative "completed workouts" progress.
	function currentWeek(p: TrainingPlan): number {
		const today = todayMidnight();
		const start = planMidnight(p.start_date);
		const total = totalWeeks(p);
		if (today < start) return 1;
		const week = Math.floor((today.getTime() - start.getTime()) / (7 * 86_400_000)) + 1;
		return Math.min(Math.max(1, week), total);
	}

	/// Calendar progress (0–100) for the timeline bar on active cards.
	/// Calendar-based, not workout-based — cheap to compute without a
	/// per-plan workouts fetch and roughly correct for the "where am I in
	/// the plan" answer the list page needs to give.
	function calendarPct(p: TrainingPlan): number {
		const today = todayMidnight().getTime();
		const start = planMidnight(p.start_date).getTime();
		const end = planMidnight(p.end_date).getTime();
		if (today <= start) return 0;
		if (today >= end) return 100;
		return Math.round(((today - start) / (end - start)) * 100);
	}

	/// Human framing for an active plan's relationship to today. "Starts
	/// in 5 days" / "12 days to go" / "Race day" / "Ended". Surfaces the
	/// time-sensitive context that the raw start→end dates can't.
	function timeRelation(p: TrainingPlan): string {
		const today = todayMidnight();
		const start = planMidnight(p.start_date);
		const end = planMidnight(p.end_date);
		const dayMs = 86_400_000;
		if (today < start) {
			const d = Math.round((start.getTime() - today.getTime()) / dayMs);
			return d === 1 ? m('plansPage.startsTomorrow') : m('plansPage.startsInDays', { d });
		}
		if (today.getTime() === end.getTime()) return m('plansPage.raceDay');
		if (today > end) return m('plansPage.ended');
		const d = Math.round((end.getTime() - today.getTime()) / dayMs);
		if (d === 0) return m('plansPage.raceDay');
		if (d === 1) return m('plansPage.oneDayToGo');
		return m('plansPage.daysToGo', { d });
	}

	let filteredPlans = $derived.by(() => {
		const out =
			statusFilter === 'all' ? [...plans] : plans.filter((p) => p.status === statusFilter);
		// Active first, then paused, then completed, then abandoned. Newest within each.
		const rank: Record<PlanStatus, number> = { active: 0, paused: 1, completed: 2, abandoned: 3 };
		out.sort((a, b) => {
			const r = rank[a.status] - rank[b.status];
			if (r !== 0) return r;
			return b.start_date.localeCompare(a.start_date);
		});
		return out;
	});

	let counts = $derived.by(() => {
		const c = { all: plans.length, active: 0, paused: 0, completed: 0, abandoned: 0 } as Record<
			StatusFilter,
			number
		>;
		for (const p of plans) c[p.status] = (c[p.status] ?? 0) + 1;
		return c;
	});

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
		const target = confirmTarget;
		const action = confirmAction;
		try {
			if (action === 'abandon') {
				await updatePlanStatus(target.id, 'abandoned');
			} else {
				await deletePlan(target.id);
			}
		} catch (e) {
			// Keep the dialog open so the user can retry or cancel — the
			// plan still exists, so silently closing would be a lie.
			showToast(
				m('plansPage.actionFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
			return;
		}
		confirmTarget = null;
		confirmAction = null;
		await load();
	}

	function cancelConfirm() {
		confirmTarget = null;
		confirmAction = null;
	}

	function handlePlanCreated(plan: { id: string }) {
		showPlanModal = false;
		// Plan creation is heavyweight — drop straight into the new plan
		// detail page so the user can review weeks, edit workouts, etc.
		goto(`/plans/${plan.id}`);
	}
</script>

<svelte:head>
	<title>{m('plansPage.headTitle')}</title>
</svelte:head>

<div class="page">
	<RunSurfaceTabs active="plans" />
	<header class="page-header">
		<div class="toolbar">
			<div class="activity-group" role="group" aria-label={m('plansPage.filterGroupLabel')}>
				{#each statusFilters as f}
					<button
						class="activity-btn"
						class:active={statusFilter === f.value}
						onclick={() => (statusFilter = f.value)}
						aria-label={f.label()}
						aria-pressed={statusFilter === f.value}
						type="button"
					>
						<span class="material-symbols">{f.icon}</span>
						<span class="activity-label">{f.label()}</span>
						{#if counts[f.value] > 0}
							<span class="count-pill">{counts[f.value]}</span>
						{/if}
					</button>
				{/each}
			</div>

			<div class="toolbar-actions">
				<a class="add-btn add-btn-outline" href="/plans/library">
					<span class="material-symbols">public</span>
					{m('plansPage.browseLibrary')}
				</a>
				<button class="add-btn" type="button" onclick={() => (showPlanModal = true)}>
					<span class="material-symbols">add</span>
					{m('plansPage.newPlan')}
				</button>
			</div>
		</div>
	</header>

	{#if loading}
		<div class="grid grid-skel" aria-hidden="true" aria-busy="true">
			{#each Array(4) as _, i (i)}
				<div class="skel-card">
					<div class="skel-card-top">
						<span class="skel skel-line skel-w-50"></span>
						<span class="skel skel-pill"></span>
					</div>
					<div class="skel-card-meta">
						<span class="skel skel-line skel-w-30"></span>
						<span class="skel skel-line skel-w-30"></span>
						<span class="skel skel-line skel-w-30"></span>
					</div>
					<span class="skel skel-bar"></span>
					<span class="skel skel-line skel-w-60"></span>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{m('plansPage.loadingPlans')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('plansPage.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" onclick={load}>{m('plansPage.retry')}</button>
		</div>
	{:else if plans.length === 0}
		<section class="empty">
			<span class="material-symbols empty-icon" aria-hidden="true">calendar_month</span>
			<h2>{m('plansPage.emptyTitle')}</h2>
			<p class="empty-lead">
				{m('plansPage.emptyLead')}
			</p>
			<button class="btn-primary" type="button" onclick={() => (showPlanModal = true)}>
				<span class="material-symbols">add</span>
				{m('plansPage.createFirst')}
			</button>
		</section>
	{:else}
		<div class="grid">
			{#each filteredPlans as p (p.id)}
				{@const total = totalWeeks(p)}
				{@const isActive = p.status === 'active'}
				{@const week = isActive ? currentWeek(p) : null}
				{@const pct = isActive ? calendarPct(p) : null}
				<a class="card" class:card-active={isActive} href="/plans/{p.id}">
					<div class="card-head">
						<h3>{p.name}</h3>
						<span class="badge status-{p.status}">
							<span class="material-symbols">{statusIcon[p.status] ?? 'help'}</span>
							{statusLabel(p.status)}
						</span>
					</div>

					<div class="hero">
						<div class="hero-metric">
							<span class="section-label">{m('plansPage.heroGoal')}</span>
							<span class="hero-value">{eventLabels[p.goal_event]?.() ?? p.goal_event}</span>
						</div>
						<div class="hero-metric">
							<span class="section-label">{m('plansPage.heroTarget')}</span>
							<span class="hero-value">{goalTime(p)}</span>
						</div>
						{#if p.vdot}
							<div class="hero-metric">
								<span class="section-label">VDOT</span>
								<span class="hero-value">{Number(p.vdot).toFixed(1)}</span>
							</div>
						{/if}
					</div>

					<div class="meta">
						<span class="meta-item">
							<span class="material-symbols">date_range</span>
							{formatDateShort(p.start_date)} → {formatDateShort(p.end_date)}
						</span>
						<span class="meta-item">
							<span class="material-symbols">view_week</span>
							{total === 1
								? m('plansPage.metaWeeksSingular', { days: p.days_per_week })
								: m('plansPage.metaWeeksPlural', { total, days: p.days_per_week })}
						</span>
					</div>

					{#if isActive && week != null && pct != null}
						<div class="progress" aria-label={m('plansPage.progressLabel')}>
							<div class="progress-head">
								<span class="progress-week">{m('plansPage.weekOf', { week, total })}</span>
								<span class="progress-when">{timeRelation(p)}</span>
							</div>
							<div
								class="progress-track"
								role="progressbar"
								aria-valuemin="0"
								aria-valuemax="100"
								aria-valuenow={pct}
							>
								<div class="progress-fill" style="width: {pct}%"></div>
							</div>
						</div>
					{/if}

					<div class="card-actions">
						{#if isActive}
							<button
								class="card-action-btn"
								type="button"
								onclick={(e) => {
									e.preventDefault();
									abandon(p);
								}}>{m('plansPage.abandon')}</button
							>
						{:else}
							<button
								class="card-action-btn danger"
								type="button"
								onclick={(e) => {
									e.preventDefault();
									remove(p);
								}}>{m('plansPage.delete')}</button
							>
						{/if}
					</div>
				</a>
			{/each}
		</div>

		{#if filteredPlans.length === 0}
			<div class="filter-empty">
				<span class="material-symbols empty-icon" aria-hidden="true">filter_alt_off</span>
				<p class="empty-text">{m('plansPage.noFilteredPlans', { status: statusFilter })}</p>
				<button class="link-btn" type="button" onclick={() => (statusFilter = 'all')}>
					{m('plansPage.showAllPlans')}
				</button>
			</div>
		{/if}
	{/if}
</div>

<ConfirmDialog
	open={confirmTarget !== null}
	title={confirmAction === 'abandon' ? m('plansPage.abandonTitle') : m('plansPage.deleteTitle')}
	message={confirmAction === 'abandon'
		? m('plansPage.abandonMessage', { name: confirmTarget?.name ?? '' })
		: m('plansPage.deleteMessage', { name: confirmTarget?.name ?? '' })}
	confirmLabel={confirmAction === 'abandon' ? m('plansPage.abandon') : m('plansPage.delete')}
	onconfirm={handleConfirmAction}
	oncancel={cancelConfirm}
	danger
/>

<Modal open={showPlanModal} title={m('plansPage.newPlan')} wide onclose={() => (showPlanModal = false)}>
	<PlanEditor oncreated={handlePlanCreated} oncancel={() => (showPlanModal = false)} />
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	.toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
	}

	.activity-group {
		display: inline-flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		padding: var(--space-2xs);
		gap: var(--space-2xs);
	}

	.activity-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-xs) var(--space-sm);
		border: none;
		border-radius: var(--radius-sm);
		background: transparent;
		font: inherit;
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition:
			background var(--transition-fast),
			color var(--transition-fast);
	}
	.activity-btn .material-symbols {
		font-size: 1.05rem;
	}
	.activity-btn:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.activity-btn.active {
		background: var(--color-primary);
		color: var(--color-surface);
	}
	.activity-btn.active:hover {
		background: var(--color-primary-hover);
	}
	.count-pill {
		font-size: 0.7rem;
		font-weight: 600;
		padding: 0 var(--space-xs);
		border-radius: 9999px;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		min-width: 1.25rem;
		text-align: center;
		font-variant-numeric: tabular-nums;
	}
	.activity-btn.active .count-pill {
		background: rgba(255, 255, 255, 0.22);
		color: var(--color-surface);
	}

	.toolbar-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		margin-inline-start: auto;
	}

	.add-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-lg);
		background: var(--color-primary);
		color: var(--color-surface);
		border-radius: var(--radius-md);
		font-size: 0.875rem;
		font-weight: 600;
		text-decoration: none;
		border: none;
		cursor: pointer;
		transition: background var(--transition-fast);
	}
	.add-btn:hover {
		background: var(--color-primary-hover);
	}
	.add-btn-outline {
		background: transparent;
		color: var(--color-primary);
		border: 1.5px solid var(--color-primary);
	}
	.add-btn-outline:hover {
		background: var(--color-primary);
		color: var(--color-surface);
	}
	.add-btn .material-symbols {
		font-size: 1.1rem;
	}

	@media (max-width: 50rem) {
		.activity-label {
			display: none;
		}
		.toolbar-actions {
			margin-inline-start: 0;
			width: 100%;
			justify-content: flex-end;
		}
	}
	@media (max-width: 30rem) {
		.toolbar {
			gap: var(--space-sm);
		}
		.activity-group {
			width: 100%;
			justify-content: space-between;
		}
		.activity-btn {
			flex: 1 1 0;
			justify-content: center;
		}
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-md);
	}

	.card {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		color: inherit;
		text-decoration: none;
		transition:
			border-color var(--transition-fast),
			box-shadow var(--transition-fast),
			transform var(--transition-fast);
	}
	.card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
		transform: translateY(-2px);
	}
	.card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.card-active {
		border-color: var(--color-primary-light);
	}

	.card-head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	.card-head h3 {
		font-size: 1.1rem;
		font-weight: 700;
		line-height: 1.25;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.7rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: 9999px;
		white-space: nowrap;
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
		background: var(--color-bg-tertiary);
		color: var(--color-text-tertiary);
	}

	.hero {
		display: flex;
		gap: var(--space-lg);
		flex-wrap: wrap;
	}
	.hero-metric {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.hero-value {
		font-size: 1.3rem;
		font-weight: 700;
		line-height: 1.1;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.hero-metric:first-child .hero-value {
		color: var(--color-primary);
	}

	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.meta-item {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-width: 0;
	}
	.meta-item .material-symbols {
		font-size: 1rem;
		color: var(--color-text-tertiary);
	}

	.progress {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.progress-head {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-sm);
		font-size: 0.8rem;
	}
	.progress-week {
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.progress-when {
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.progress-track {
		height: 0.4rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		overflow: hidden;
	}
	.progress-fill {
		height: 100%;
		background: var(--color-primary);
		border-radius: 9999px;
		transition: width var(--transition-base);
	}

	.card-actions {
		display: flex;
		justify-content: flex-end;
		margin-top: auto;
	}
	.card-action-btn {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
		font: inherit;
		font-weight: 600;
		font-size: 0.8rem;
		cursor: pointer;
		padding: var(--space-xs) var(--space-md);
		border-radius: var(--radius-md);
		transition:
			background var(--transition-fast),
			border-color var(--transition-fast),
			color var(--transition-fast);
	}
	.card-action-btn:hover {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.card-action-btn.danger:hover {
		background: var(--color-danger-light);
		border-color: var(--color-danger);
		color: var(--color-danger);
	}

	.empty {
		max-width: 38rem;
		margin: var(--space-2xl) 0;
		padding: var(--space-2xl);
		text-align: center;
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-lg);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.7;
	}
	.empty h2 {
		font-size: 1.25rem;
		font-weight: 700;
	}
	.empty-lead {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.55;
		max-width: 32rem;
	}

	.filter-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-md);
		color: var(--color-text-tertiary);
	}
	.filter-empty .empty-icon {
		font-size: 2.25rem;
	}
	.filter-empty .empty-text {
		font-size: 0.95rem;
		color: var(--color-text);
		padding: 0;
	}
	.link-btn {
		background: transparent;
		border: none;
		color: var(--color-primary);
		font: inherit;
		font-size: 0.875rem;
		font-weight: 600;
		cursor: pointer;
		padding: var(--space-xs);
	}
	.link-btn:hover {
		color: var(--color-primary-hover);
	}

	/* Skeleton placeholders for the initial load. Layout matches the
	   real card so the page lands at its true height immediately. */
	.skel-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		min-height: 11rem;
		pointer-events: none;
	}
	.skel-card-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-sm);
	}
	.skel-card-meta {
		display: flex;
		gap: var(--space-md);
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line {
		height: 0.75rem;
	}
	.skel-pill {
		width: 4rem;
		height: 1rem;
		border-radius: 9999px;
	}
	.skel-bar {
		height: 0.4rem;
		border-radius: 9999px;
	}
	.skel-w-30 {
		width: 30%;
	}
	.skel-w-50 {
		width: 50%;
	}
	.skel-w-60 {
		width: 60%;
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
		.card:hover {
			transform: none;
		}
		.progress-fill {
			transition: none;
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

	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.4rem;
	}
</style>
