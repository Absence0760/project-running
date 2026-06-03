<script lang="ts">
	import {
		daysUntilRace,
		evenSplitPacing,
		MILE_METRES,
		negativeSplitPacing,
		raceChecklist,
		fmtSplitTime,
	} from '$lib/runs/race_day';
	import { riegelPredict, predictionConfidence } from '$lib/training/training';
	import { fmtKm, getUnit } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	interface Props {
		raceDate: string;
		distanceM: number;
		goalTimeSec: number | null;
		recentRuns: Run[];
	}
	let { raceDate, distanceM, goalTimeSec, recentRuns }: Props = $props();

	let today = $state(new Date());

	let daysOut = $derived(daysUntilRace(raceDate, today));

	// Predict the finish from the goal time if the user set one,
	// otherwise pick a Riegel projection off the runner's best
	// qualifying recent effort (>1 km, in the last 90 days). When the
	// prediction is data-derived we also capture the anchoring effort so
	// we can grade its confidence (distance gap / recency / sample size).
	let prediction = $derived.by(() => {
		if (goalTimeSec != null) {
			return { sec: goalTimeSec, fromGoal: true, anchor: null, qualifyingCount: 0 };
		}
		const now = Date.now();
		const cutoff = now - 90 * 24 * 60 * 60 * 1000;
		let bestSec: number | null = null;
		let anchor: { distanceM: number; daysSinceBest: number } | null = null;
		let qualifyingCount = 0;
		for (const r of recentRuns) {
			if (r.distance_m < 1000) continue;
			const t = new Date(r.started_at).getTime();
			if (t < cutoff) continue;
			qualifyingCount++;
			const proj = riegelPredict(r.distance_m, r.duration_s, distanceM);
			if (bestSec == null || proj < bestSec) {
				bestSec = proj;
				anchor = {
					distanceM: r.distance_m,
					daysSinceBest: Math.max(0, Math.round((now - t) / (24 * 60 * 60 * 1000))),
				};
			}
		}
		return { sec: bestSec, fromGoal: false, anchor, qualifyingCount };
	});

	let predictedSec = $derived(prediction.sec);

	// Confidence chip — only for data-derived predictions (a user-set
	// goal time isn't a prediction, so no data-quality grade applies).
	let confidence = $derived.by(() => {
		if (prediction.fromGoal || prediction.anchor == null) return null;
		return predictionConfidence({
			knownDistanceM: prediction.anchor.distanceM,
			targetDistanceM: distanceM,
			daysSinceBest: prediction.anchor.daysSinceBest,
			qualifyingRunCount: prediction.qualifyingCount,
		});
	});

	let confidenceLabel = $derived(
		confidence == null ? null : m(`raceDayPanel.confidence_${confidence.confidence}`),
	);
	let confidenceReason = $derived(
		confidence == null ? null : m(`raceDayPanel.confReason_${confidence.reason}`),
	);

	let strategy = $state<'even' | 'negative'>('even');
	// Pacing splits honour the user's distance pref — mi-mode users
	// see per-mile splits + "mi N" labels, km-mode users see per-km.
	// Reading getUnit() inside $derived re-runs when the pref flips.
	let splitUnitMetres = $derived(getUnit() === 'mi' ? MILE_METRES : 1000);
	let splitUnitLabel = $derived(getUnit() === 'mi' ? 'mi' : 'km');
	let pacing = $derived.by(() => {
		if (predictedSec == null) return null;
		return strategy === 'even'
			? evenSplitPacing(distanceM, predictedSec, splitUnitMetres)
			: negativeSplitPacing(distanceM, predictedSec, 2, splitUnitMetres);
	});

	let checklist = $derived(raceChecklist(distanceM));

	let countdownLabel = $derived.by(() => {
		if (daysOut < 0) return null;
		if (daysOut === 0) return m('raceDayPanel.raceDay');
		if (daysOut === 1) return m('raceDayPanel.daysToGoOne');
		return m('raceDayPanel.daysToGoMany', { n: daysOut });
	});
</script>

{#if daysOut >= 0}
	<section class="race-day-panel">
		<header>
			<span class="kicker">{m('raceDayPanel.raceDay')}</span>
			<h2>{countdownLabel}</h2>
			{#if predictedSec != null}
				<p class="prediction">
					{m('raceDayPanel.predictedFinishPrefix')} <strong>{fmtSplitTime(predictedSec)}</strong>
					{m('raceDayPanel.predictedFinishFor')} {fmtKm(distanceM, 1)}
				</p>
				{#if confidenceLabel != null}
					<span
						class="confidence-chip conf-{confidence?.confidence}"
						title={confidenceReason}
					>{confidenceLabel}</span>
				{/if}
			{/if}
		</header>

		{#if pacing}
			<div class="pacing-section">
				<div class="strategy-toggle" role="group" aria-label={m('raceDayPanel.pacingStrategy')}>
					<button
						type="button"
						class="toggle-btn"
						class:active={strategy === 'even'}
						onclick={() => (strategy = 'even')}
					>{m('raceDayPanel.evenSplits')}</button>
					<button
						type="button"
						class="toggle-btn"
						class:active={strategy === 'negative'}
						onclick={() => (strategy = 'negative')}
					>{m('raceDayPanel.negativeSplits')}</button>
				</div>

				<ol class="splits">
					{#each pacing.splitsSec as sp, i (i)}
						<li>
							<span class="split-km">{splitUnitLabel} {i + 1}</span>
							<span class="split-time">{fmtSplitTime(sp)}</span>
						</li>
					{/each}
				</ol>
			</div>
		{/if}

		<div class="checklist-grid">
			{#each checklist as section (section.title)}
				<div class="checklist-section">
					<h3>{section.title}</h3>
					<ul>
						{#each section.items as item (item.name)}
							<li>
								<span class="check-name">{item.name}</span>
								{#if item.detail}
									<span class="check-detail">{item.detail}</span>
								{/if}
							</li>
						{/each}
					</ul>
				</div>
			{/each}
		</div>
	</section>
{/if}

<style>
	.race-day-panel {
		background: linear-gradient(135deg, #F97316 0%, #EF4444 100%);
		color: white;
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		margin-bottom: var(--space-xl);
	}
	header { margin-bottom: var(--space-lg); }
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: 0.78rem;
		opacity: 0.9;
	}
	h2 {
		font-size: 2.2rem;
		font-weight: 800;
		margin: 0.2rem 0 0.5rem;
	}
	.prediction { margin: 0; font-size: 1rem; opacity: 0.95; }
	.prediction strong { font-weight: 800; }

	.confidence-chip {
		display: inline-block;
		margin-top: 0.4rem;
		padding: 0.15rem 0.6rem;
		border-radius: 999px;
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		background: rgba(255, 255, 255, 0.18);
		border: 1px solid rgba(255, 255, 255, 0.35);
		cursor: help;
	}
	.confidence-chip.conf-high { background: rgba(255, 255, 255, 0.92); color: #047857; }
	.confidence-chip.conf-moderate { background: rgba(255, 255, 255, 0.82); color: #B45309; }
	.confidence-chip.conf-low { background: rgba(255, 255, 255, 0.7); color: #B91C1C; }

	.pacing-section {
		background: rgba(255, 255, 255, 0.12);
		border-radius: var(--radius-md);
		padding: var(--space-md);
		margin-bottom: var(--space-lg);
	}
	.strategy-toggle {
		display: flex;
		gap: 0.5rem;
		margin-bottom: var(--space-md);
	}
	.toggle-btn {
		padding: 0.3rem 0.8rem;
		border: 1px solid rgba(255, 255, 255, 0.4);
		background: transparent;
		color: white;
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
	}
	.toggle-btn.active { background: white; color: #EF4444; }
	.splits {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(8rem, 1fr));
		gap: 0.4rem;
	}
	.splits li {
		display: flex;
		justify-content: space-between;
		padding: 0.3rem 0.6rem;
		background: rgba(255, 255, 255, 0.1);
		border-radius: 6px;
		font-size: 0.9rem;
	}
	.split-time { font-variant-numeric: tabular-nums; font-weight: 700; }

	.checklist-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
		gap: var(--space-md);
	}
	.checklist-section {
		background: rgba(255, 255, 255, 0.1);
		border-radius: var(--radius-md);
		padding: var(--space-md);
	}
	.checklist-section h3 {
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		margin: 0 0 var(--space-sm);
		opacity: 0.95;
	}
	.checklist-section ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.checklist-section li {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		font-size: 0.88rem;
	}
	.check-name { font-weight: 600; }
	.check-detail { opacity: 0.85; font-size: 0.8rem; }
</style>
