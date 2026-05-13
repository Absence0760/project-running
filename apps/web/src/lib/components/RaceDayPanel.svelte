<script lang="ts">
	import {
		daysUntilRace,
		evenSplitPacing,
		negativeSplitPacing,
		raceChecklist,
		fmtSplitTime,
	} from '$lib/race_day';
	import { riegelPredict } from '$lib/training';
	import { fmtKm } from '$lib/units.svelte';
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
	// qualifying recent effort (>1 km, in the last 90 days).
	let predictedSec = $derived.by(() => {
		if (goalTimeSec != null) return goalTimeSec;
		let bestSec: number | null = null;
		const cutoff = Date.now() - 90 * 24 * 60 * 60 * 1000;
		for (const r of recentRuns) {
			if (r.distance_m < 1000) continue;
			const t = new Date(r.started_at).getTime();
			if (t < cutoff) continue;
			const proj = riegelPredict(r.distance_m, r.duration_s, distanceM);
			if (bestSec == null || proj < bestSec) bestSec = proj;
		}
		return bestSec;
	});

	let strategy = $state<'even' | 'negative'>('even');
	let pacing = $derived.by(() => {
		if (predictedSec == null) return null;
		return strategy === 'even'
			? evenSplitPacing(distanceM, predictedSec)
			: negativeSplitPacing(distanceM, predictedSec, 2);
	});

	let checklist = $derived(raceChecklist(distanceM));

	let countdownLabel = $derived.by(() => {
		if (daysOut < 0) return null;
		if (daysOut === 0) return 'Race day';
		if (daysOut === 1) return '1 day to go';
		return `${daysOut} days to go`;
	});
</script>

{#if daysOut >= 0}
	<section class="race-day-panel">
		<header>
			<span class="kicker">Race day</span>
			<h2>{countdownLabel}</h2>
			{#if predictedSec != null}
				<p class="prediction">
					Predicted finish at <strong>{fmtSplitTime(predictedSec)}</strong>
					for {fmtKm(distanceM, 1)}
				</p>
			{/if}
		</header>

		{#if pacing}
			<div class="pacing-section">
				<div class="strategy-toggle" role="group" aria-label="Pacing strategy">
					<button
						type="button"
						class="toggle-btn"
						class:active={strategy === 'even'}
						onclick={() => (strategy = 'even')}
					>Even splits</button>
					<button
						type="button"
						class="toggle-btn"
						class:active={strategy === 'negative'}
						onclick={() => (strategy = 'negative')}
					>Negative splits (-2%)</button>
				</div>

				<ol class="splits">
					{#each pacing.splitsSec as sp, i (i)}
						<li>
							<span class="split-km">km {i + 1}</span>
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
