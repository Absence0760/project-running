<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchRuns } from '$lib/data';
	import { buildYearInRunningRecap, type YearInRunningRecap } from '$lib/recap';
	import { fmtKm, getUnit } from '$lib/units.svelte';
	import type { Run } from '$lib/types';

	let runs = $state<Run[]>([]);
	let loading = $state(true);
	let recap = $state<YearInRunningRecap | null>(null);

	let year = $derived(parseInt($page.params.year ?? '0', 10));
	let valid = $derived(!Number.isNaN(year) && year >= 2010 && year <= 2100);

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) {
			loading = false;
			return;
		}
		runs = await fetchRuns();
		loading = false;
	});

	$effect(() => {
		if (!valid) return;
		recap = buildYearInRunningRecap(runs, year);
	});

	function fmtTime(seconds: number): string {
		const h = Math.floor(seconds / 3600);
		const m = Math.floor((seconds % 3600) / 60);
		if (h > 0) return `${h}h ${m}m`;
		return `${m}m`;
	}

	function fmtPace(secPerKm: number | null): string {
		if (secPerKm == null) return '—';
		const unit = getUnit();
		// Convert to s/mi if the user prefers miles.
		const secPerUnit = unit === 'mi' ? secPerKm * 1.609344 : secPerKm;
		const m = Math.floor(secPerUnit / 60);
		const s = Math.round(secPerUnit % 60);
		return `${m}:${String(s).padStart(2, '0')} /${unit}`;
	}

	function maxMonthlyDistance(monthly: YearInRunningRecap['monthly']): number {
		return Math.max(1, ...monthly.map((m) => m.distanceM));
	}

	const MONTH_LABELS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

	async function shareRecap() {
		if (!recap) return;
		const lines = [
			`My ${recap.year} in running`,
			'',
			`${fmtKm(recap.totalDistanceM)} across ${recap.runCount} runs`,
			`Longest run: ${fmtKm(recap.longestRunM)}`,
			`Best streak: ${recap.bestStreakDays} days`,
			`Top week: ${fmtKm(recap.topWeek?.distanceM ?? 0)}`,
		];
		const text = lines.join('\n');
		if (navigator.share) {
			try {
				await navigator.share({ title: `My ${recap.year} in running`, text });
				return;
			} catch (_) {
				// fall through to clipboard
			}
		}
		await navigator.clipboard.writeText(text);
		alert('Recap copied to clipboard.');
	}
</script>

<svelte:head>
	<title>My {year} in running — Run Onward</title>
</svelte:head>

<div class="page">
	{#if !valid}
		<p class="muted">Pick a year between 2010 and 2100.</p>
	{:else if loading}
		<p class="muted">Loading your year…</p>
	{:else if !auth.user}
		<p class="muted">Sign in to see your year in running.</p>
	{:else if recap == null || recap.runCount === 0}
		<header class="hero hero-empty">
			<h1>{year}</h1>
			<p>No runs in {year} yet. Get out there — your wrap card is waiting.</p>
		</header>
	{:else}
		<header class="hero">
			<p class="kicker">My {recap.year} in running</p>
			<h1 class="bignum">{fmtKm(recap.totalDistanceM)}</h1>
			<p class="subhead">
				across {recap.runCount} {recap.runCount === 1 ? 'run' : 'runs'}
				· {fmtTime(recap.totalDurationS)} on foot
				· {Math.round(recap.totalElevationM)} m climbed
			</p>
			<button type="button" class="btn btn-primary share-btn" onclick={shareRecap}>
				Share recap
			</button>
		</header>

		<section class="cards">
			<div class="card">
				<span class="card-label">Longest run</span>
				<span class="card-value">{fmtKm(recap.longestRunM)}</span>
			</div>
			<div class="card">
				<span class="card-label">Fastest pace</span>
				<span class="card-value">{fmtPace(recap.fastestPaceSecPerKm)}</span>
				<span class="card-sub">on runs over 500&nbsp;m</span>
			</div>
			<div class="card">
				<span class="card-label">Best streak</span>
				<span class="card-value">{recap.bestStreakDays} <small>days</small></span>
			</div>
			<div class="card">
				<span class="card-label">Top week</span>
				<span class="card-value">{fmtKm(recap.topWeek?.distanceM ?? 0)}</span>
				<span class="card-sub">
					{#if recap.topWeek}
						week of {recap.topWeek.weekStart}
					{/if}
				</span>
			</div>
			<div class="card">
				<span class="card-label">Routes run</span>
				<span class="card-value">{recap.uniqueRouteCount}</span>
				<span class="card-sub">distinct saved routes</span>
			</div>
			<div class="card">
				<span class="card-label">Earliest start</span>
				<span class="card-value">{recap.earliestStartLocal ?? '—'}</span>
				<span class="card-sub">local time</span>
			</div>
		</section>

		<section class="month-chart">
			<h2>Distance by month</h2>
			<div class="bars">
				{#each recap.monthly as m (m.month)}
					{@const max = maxMonthlyDistance(recap.monthly)}
					<div class="bar-col" title={`${fmtKm(m.distanceM)} (${m.runCount} runs)`}>
						<div class="bar" style="height: {(m.distanceM / max) * 100}%"></div>
						<span class="bar-label">{MONTH_LABELS[m.month - 1]}</span>
					</div>
				{/each}
			</div>
		</section>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.muted { color: var(--color-text-secondary); }
	.hero {
		padding: var(--space-2xl) var(--space-xl);
		text-align: center;
		background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%);
		color: white;
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-xl);
	}
	.hero-empty {
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.8rem;
		opacity: 0.8;
		margin: 0 0 var(--space-sm);
	}
	.bignum {
		font-size: 5rem;
		font-weight: 900;
		margin: 0 0 var(--space-sm);
		line-height: 1;
	}
	.subhead {
		font-size: 1.05rem;
		opacity: 0.95;
		margin: 0 0 var(--space-lg);
	}
	.share-btn {
		background: white;
		color: #4F46E5;
	}
	.cards {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr));
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.card-label {
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-secondary);
	}
	.card-value {
		font-size: 1.75rem;
		font-weight: 800;
	}
	.card-value small {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.card-sub {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}
	.month-chart {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
	}
	.month-chart h2 {
		font-size: 0.85rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-md);
	}
	.bars {
		display: grid;
		grid-template-columns: repeat(12, 1fr);
		gap: 0.4rem;
		align-items: end;
		height: 12rem;
	}
	.bar-col {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: end;
		height: 100%;
		gap: 0.3rem;
	}
	.bar {
		width: 100%;
		min-height: 2px;
		background: linear-gradient(180deg, #7C3AED, #4F46E5);
		border-radius: 4px 4px 0 0;
	}
	.bar-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
</style>
