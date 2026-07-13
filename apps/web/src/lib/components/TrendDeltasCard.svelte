<script lang="ts">
	import {
		computeTrendDeltas,
		type MetricDelta,
		type WeekStartDay,
	} from '$lib/training/trend_deltas';
	import { fmtKm } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	interface Props {
		runs: Run[];
		weekStart: WeekStartDay;
		/// Overridable for deterministic tests; defaults to the real clock.
		now?: Date;
	}
	let { runs, weekStart, now }: Props = $props();

	let trend = $derived(
		computeTrendDeltas(
			runs.map((r) => ({
				started_at: r.started_at,
				distance_m: r.distance_m,
				duration_s: r.duration_s,
			})),
			weekStart,
			now ?? new Date(),
		),
	);

	// Nothing to trend when every current and prior window is empty — the card
	// self-hides, matching the other analytics cards' data-presence rule.
	let hasData = $derived.by(() => {
		const cells = [trend.week, trend.month];
		return cells.some(
			(p) =>
				p.distanceM.current > 0 ||
				p.distanceM.prior > 0 ||
				p.runs.current > 0 ||
				p.runs.prior > 0,
		);
	});

	function compactDuration(seconds: number): string {
		if (seconds < 60) return '0m';
		const h = Math.floor(seconds / 3600);
		const mm = Math.floor((seconds % 3600) / 60);
		if (h > 0) return mm > 0 ? `${h}h ${mm}m` : `${h}h`;
		return `${mm}m`;
	}

	function arrow(d: MetricDelta): string {
		return d.direction === 'up' ? 'arrow_upward' : d.direction === 'down' ? 'arrow_downward' : 'remove';
	}
	// A signed percentage when the prior window supports one; otherwise a
	// no-change / new-activity word so the direction is always legible and we
	// never divide by a zero prior.
	function deltaText(d: MetricDelta): string {
		if (d.pct != null) {
			const sign = d.pct > 0 ? '+' : '';
			return `${sign}${d.pct}%`;
		}
		if (d.delta === 0) return m('trends.noChange');
		return m('trends.new');
	}
</script>

{#if hasData}
	<section class="card-elevated trend-deltas" data-testid="trend-deltas">
		<div class="card-head">
			<h2>{m('trends.title')}</h2>
		</div>
		<table class="trend-table">
			<thead>
				<tr>
					<th scope="col" class="metric-col"><span class="visually-hidden">{m('trends.metricCol')}</span></th>
					<th scope="col">{m('trends.weekCol')}</th>
					<th scope="col">{m('trends.monthCol')}</th>
				</tr>
			</thead>
			<tbody>
				<tr>
					<th scope="row">{m('trends.distanceRow')}</th>
					<td>
						<span class="cur">{fmtKm(trend.week.distanceM.current)}</span>
						<span class="delta delta-{trend.week.distanceM.direction}" data-testid="trend-week-distance">
							<span class="material-symbols" aria-hidden="true">{arrow(trend.week.distanceM)}</span>
							{deltaText(trend.week.distanceM)}
						</span>
					</td>
					<td>
						<span class="cur">{fmtKm(trend.month.distanceM.current)}</span>
						<span class="delta delta-{trend.month.distanceM.direction}" data-testid="trend-month-distance">
							<span class="material-symbols" aria-hidden="true">{arrow(trend.month.distanceM)}</span>
							{deltaText(trend.month.distanceM)}
						</span>
					</td>
				</tr>
				<tr>
					<th scope="row">{m('trends.timeRow')}</th>
					<td>
						<span class="cur">{compactDuration(trend.week.durationS.current)}</span>
						<span class="delta delta-{trend.week.durationS.direction}">
							<span class="material-symbols" aria-hidden="true">{arrow(trend.week.durationS)}</span>
							{deltaText(trend.week.durationS)}
						</span>
					</td>
					<td>
						<span class="cur">{compactDuration(trend.month.durationS.current)}</span>
						<span class="delta delta-{trend.month.durationS.direction}">
							<span class="material-symbols" aria-hidden="true">{arrow(trend.month.durationS)}</span>
							{deltaText(trend.month.durationS)}
						</span>
					</td>
				</tr>
				<tr>
					<th scope="row">{m('trends.runsRow')}</th>
					<td>
						<span class="cur">{trend.week.runs.current}</span>
						<span class="delta delta-{trend.week.runs.direction}" data-testid="trend-week-runs">
							<span class="material-symbols" aria-hidden="true">{arrow(trend.week.runs)}</span>
							{deltaText(trend.week.runs)}
						</span>
					</td>
					<td>
						<span class="cur">{trend.month.runs.current}</span>
						<span class="delta delta-{trend.month.runs.direction}">
							<span class="material-symbols" aria-hidden="true">{arrow(trend.month.runs)}</span>
							{deltaText(trend.month.runs)}
						</span>
					</td>
				</tr>
			</tbody>
		</table>
		<p class="footnote">{m('trends.footnote')}</p>
	</section>
{/if}

<style>
	.trend-deltas {
		padding: var(--space-xl);
	}
	.card-head {
		margin-bottom: var(--space-md);
	}
	.card-head h2 {
		margin: 0;
	}
	.trend-table {
		width: 100%;
		border-collapse: collapse;
	}
	.trend-table th[scope='col'] {
		text-align: start;
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--text-muted, #6b7280);
		padding-bottom: var(--space-sm);
	}
	.trend-table th[scope='row'] {
		text-align: start;
		font-weight: 600;
		font-size: 0.9rem;
		padding: var(--space-sm) var(--space-md) var(--space-sm) 0;
		white-space: nowrap;
	}
	.trend-table td {
		padding: var(--space-sm) var(--space-md) var(--space-sm) 0;
	}
	.cur {
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		margin-inline-end: 0.4rem;
	}
	.delta {
		display: inline-flex;
		align-items: center;
		gap: 0.1rem;
		font-size: 0.8rem;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.delta .material-symbols {
		font-size: 0.95rem;
	}
	.delta-up {
		color: #047857;
	}
	.delta-down {
		color: #b45309;
	}
	.delta-flat {
		color: var(--text-muted, #6b7280);
	}
	.footnote {
		margin: var(--space-md) 0 0;
		font-size: 0.78rem;
		color: var(--text-muted, #6b7280);
	}
</style>
