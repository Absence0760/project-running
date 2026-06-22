<script lang="ts">
	import { predictRaceLadder, type EffortForPrediction } from '$lib/training/race_predictor';
	import { qualifyingRuns } from '$lib/training/fitness';
	import { fmtSplitTime } from '$lib/runs/race_day';
	import { fmtKm, fmtPace } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	interface Props {
		runs: Run[];
	}
	let { runs }: Props = $props();

	// Use the same qualifying-run gate the Fitness card uses (recording /
	// reliable import, >= 1.5 km, sane duration, no treadmill) so the
	// predictor never anchors to a belt-estimate distance. Then map each run
	// down to the minimal effort shape, computing age in whole days.
	let prediction = $derived.by(() => {
		const now = Date.now();
		const efforts: EffortForPrediction[] = qualifyingRuns(runs).map((r) => ({
			distanceM: r.distance_m,
			durationS: r.duration_s,
			ageDays: Math.max(0, (now - new Date(r.started_at).getTime()) / 86_400_000),
		}));
		return predictRaceLadder(efforts);
	});

	function labelFor(confidence: 'high' | 'moderate' | 'low'): string {
		return m(`racePredictor.confidence_${confidence}`);
	}
	function reasonFor(reason: 'similar' | 'extrapolated' | 'stale' | 'limited'): string {
		return m(`racePredictor.confReason_${reason}`);
	}
</script>

{#if prediction}
	<section class="card-elevated race-predictor" data-testid="race-predictor">
		<div class="card-head">
			<h2>{m('racePredictor.title')}</h2>
		</div>
		<p class="anchor-line">
			{m('racePredictor.anchoredOn', {
				distance: fmtKm(prediction.anchor.distanceM, 1),
				time: fmtSplitTime(prediction.anchor.durationS),
			})}
		</p>
		<table class="ladder">
			<thead>
				<tr>
					<th scope="col">{m('racePredictor.colDistance')}</th>
					<th scope="col">{m('racePredictor.colTime')}</th>
					<th scope="col">{m('racePredictor.colPace')}</th>
					<th scope="col">{m('racePredictor.colConfidence')}</th>
				</tr>
			</thead>
			<tbody>
				{#each prediction.rungs as rung (rung.distanceM)}
					<tr>
						<td class="dist">{fmtKm(rung.distanceM, 1)}</td>
						<td class="time">{fmtSplitTime(rung.predictedSec)}</td>
						<td class="pace">{fmtPace(rung.paceSecPerKm)}</td>
						<td class="conf">
							<span
								class="confidence-chip conf-{rung.quality.confidence}"
								title={reasonFor(rung.quality.reason)}
							>{labelFor(rung.quality.confidence)}</span>
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
		<p class="footnote">{m('racePredictor.footnote')}</p>
	</section>
{/if}

<style>
	.race-predictor { padding: var(--space-xl); }
	.card-head { margin-bottom: var(--space-sm); }
	.card-head h2 { margin: 0; }
	.anchor-line {
		margin: 0 0 var(--space-md);
		font-size: 0.88rem;
		color: var(--text-muted, #6b7280);
	}
	.ladder {
		width: 100%;
		border-collapse: collapse;
		font-variant-numeric: tabular-nums;
	}
	.ladder th {
		text-align: start;
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--text-muted, #6b7280);
		padding: 0.3rem 0.6rem 0.4rem 0;
	}
	.ladder td {
		padding: 0.45rem 0.6rem 0.45rem 0;
		border-top: 1px solid var(--border, #e5e7eb);
		font-size: 0.95rem;
	}
	.ladder .time { font-weight: 700; }
	.ladder .dist { font-weight: 600; }
	.confidence-chip {
		display: inline-block;
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		cursor: help;
	}
	.confidence-chip.conf-high { background: #d1fae5; color: #047857; }
	.confidence-chip.conf-moderate { background: #fef3c7; color: #b45309; }
	.confidence-chip.conf-low { background: #fee2e2; color: #b91c1c; }
	.footnote {
		margin: var(--space-md) 0 0;
		font-size: 0.78rem;
		color: var(--text-muted, #6b7280);
	}
</style>
