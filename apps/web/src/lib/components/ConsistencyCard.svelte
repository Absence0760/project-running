<script lang="ts">
	import { computeConsistency, type WeekStart } from '$lib/training/consistency';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	interface Props {
		activities: Run[];
		weekStart: WeekStart;
		/// Overridable for deterministic tests; defaults to the real clock.
		now?: Date;
	}
	let { activities, weekStart, now }: Props = $props();

	let stats = $derived(
		computeConsistency(
			activities.map((r) => ({ started_at: r.started_at, distance_m: r.distance_m })),
			weekStart,
			12,
			now ?? new Date(),
		),
	);

	// Tallest active week normalises the strip bars; a floor keeps a single
	// tiny week from rendering as an invisible sliver.
	let maxWeek = $derived(stats ? Math.max(1, ...stats.weeklyDistanceM) : 1);
</script>

{#if stats}
	<section class="card-elevated consistency-card" data-testid="consistency-card">
		<div class="card-head">
			<h2>{m('dashConsistency.title')}</h2>
			{#if stats.steadiness}
				<span class="steadiness-chip chip-{stats.steadiness}">
					{stats.steadiness === 'steady'
						? m('dashConsistency.steady')
						: m('dashConsistency.variable')}
				</span>
			{/if}
		</div>

		<div class="headline">
			<span class="big" data-testid="consistency-active">{stats.weeksActive}/{stats.windowWeeks}</span>
			<span class="headline-sub">{m('dashConsistency.weeksTrained', { pct: stats.activePct })}</span>
		</div>

		<div class="consistency-strip" aria-hidden="true">
			{#each stats.weeklyDistanceM as distance, i (i)}
				<span
					class="week-cell"
					class:active={distance > 0}
					class:current={i === stats.windowWeeks - 1}
					style="--h: {distance > 0 ? Math.max(12, (distance / maxWeek) * 100) : 6}%"
				></span>
			{/each}
		</div>

		<div class="consistency-stats">
			<div class="stat">
				<span class="stat-value" data-testid="consistency-current-streak">{stats.currentStreak}</span>
				<span class="stat-label">{m('dashConsistency.currentStreakLabel')}</span>
			</div>
			<div class="stat">
				<span class="stat-value">{stats.longestStreak}</span>
				<span class="stat-label">{m('dashConsistency.bestStreakLabel')}</span>
			</div>
		</div>

		<p class="footnote">{m('dashConsistency.footnote', { total: stats.windowWeeks })}</p>
	</section>
{/if}

<style>
	.consistency-card {
		padding: var(--space-xl);
	}
	.card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.card-head h2 {
		margin: 0;
	}
	.steadiness-chip {
		padding: 0.1rem 0.55rem;
		border-radius: 999px;
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}
	.chip-steady {
		background: #d1fae5;
		color: #047857;
	}
	.chip-variable {
		background: #fef3c7;
		color: #b45309;
	}
	.headline {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.big {
		font-size: 2rem;
		font-weight: 800;
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.headline-sub {
		font-size: 0.9rem;
		color: var(--text-muted, #6b7280);
	}
	.consistency-strip {
		display: flex;
		align-items: flex-end;
		gap: 3px;
		height: 44px;
		margin-bottom: var(--space-md);
	}
	.week-cell {
		flex: 1 1 0;
		height: var(--h, 6%);
		min-height: 3px;
		border-radius: 2px;
		background: var(--border, #e5e7eb);
	}
	.week-cell.active {
		background: var(--color-primary, #2563eb);
	}
	.week-cell.current {
		outline: 2px solid var(--color-primary, #2563eb);
		outline-offset: 1px;
	}
	.consistency-stats {
		display: flex;
		gap: var(--space-xl);
	}
	.stat {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.stat-value {
		font-size: 1.4rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.stat-label {
		font-size: 0.78rem;
		color: var(--text-muted, #6b7280);
	}
	.footnote {
		margin: var(--space-md) 0 0;
		font-size: 0.78rem;
		color: var(--text-muted, #6b7280);
	}
</style>
