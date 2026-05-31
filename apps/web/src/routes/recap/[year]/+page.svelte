<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchRuns } from '$lib/data';
	import { buildYearInRunningRecap, type YearInRunningRecap } from '$lib/recap';
	import { buildRecapShareSvg } from '$lib/recap_share_image';
	import { fmtKm, getUnit, fmtPace } from '$lib/units.svelte';
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


	function fmtWeekStart(iso: string): string {
		const d = new Date(iso + 'T00:00:00');
		return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
	}

	function maxMonthlyDistance(monthly: YearInRunningRecap['monthly']): number {
		return Math.max(1, ...monthly.map((m) => m.distanceM));
	}

	function activeMonths(monthly: YearInRunningRecap['monthly']): number {
		return monthly.filter((m) => m.runCount > 0).length;
	}

	const MONTH_LABELS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

	/// Rasterise an SVG string to a PNG blob via an offscreen canvas.
	/// The recap is personal data with no public URL, so the card is
	/// rendered client-side rather than served as an og:image.
	async function svgToPngBlob(svg: string, size: number): Promise<Blob> {
		const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
		try {
			const img = new Image(size, size);
			await new Promise<void>((resolve, reject) => {
				img.onload = () => resolve();
				img.onerror = () => reject(new Error('recap card svg failed to load'));
				img.src = url;
			});
			const canvas = document.createElement('canvas');
			canvas.width = size;
			canvas.height = size;
			const ctx = canvas.getContext('2d');
			if (!ctx) throw new Error('no 2d canvas context');
			ctx.drawImage(img, 0, 0, size, size);
			return await new Promise<Blob>((resolve, reject) => {
				canvas.toBlob(
					(b) => (b ? resolve(b) : reject(new Error('canvas.toBlob returned null'))),
					'image/png',
				);
			});
		} finally {
			URL.revokeObjectURL(url);
		}
	}

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

		// Primary path: share / download the rendered card image. Any
		// failure (no canvas, blocked toBlob, share rejected) falls
		// through to the text share below — the card is additive, never
		// the only way out.
		try {
			const svg = buildRecapShareSvg(recap, getUnit());
			const blob = await svgToPngBlob(svg, 1080);
			const file = new File([blob], `threkir-${recap.year}.png`, { type: 'image/png' });
			if (navigator.canShare?.({ files: [file] })) {
				await navigator.share({ files: [file], title: `My ${recap.year} in running`, text });
				return;
			}
			const dl = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = dl;
			a.download = `threkir-${recap.year}.png`;
			a.click();
			URL.revokeObjectURL(dl);
			return;
		} catch (err) {
			console.warn('recap card share failed, falling back to text', err);
		}

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
	<title>My {year} in running — Threkir</title>
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
			<p class="kicker">{year}</p>
			<h1>No runs in {year} yet</h1>
			<p class="empty-sub">
				Get out there — your wrap card is waiting. Every run you log this year shows up
				here.
			</p>
		</header>
	{:else}
		<header class="hero">
			<p class="kicker">My {recap.year} in running</p>
			<h1 class="bignum">{fmtKm(recap.totalDistanceM)}</h1>
			<p class="subhead">
				across {recap.runCount} {recap.runCount === 1 ? 'run' : 'runs'}
			</p>
			<div class="hero-meta">
				<span class="hero-meta-item">
					<span class="material-symbols">timer</span>
					{fmtTime(recap.totalDurationS)} on foot
				</span>
				<span class="hero-meta-divider" aria-hidden="true"></span>
				<span class="hero-meta-item">
					<span class="material-symbols">terrain</span>
					{Math.round(recap.totalElevationM).toLocaleString()} m climbed
				</span>
				<span class="hero-meta-divider" aria-hidden="true"></span>
				<span class="hero-meta-item">
					<span class="material-symbols">calendar_month</span>
					active in {activeMonths(recap.monthly)} {activeMonths(recap.monthly) === 1 ? 'month' : 'months'}
				</span>
			</div>
			<button type="button" class="btn share-btn" onclick={shareRecap}>
				<span class="material-symbols">ios_share</span>
				Share recap
			</button>
		</header>

		<section class="cards">
			<div class="card">
				<span class="card-label">Longest run</span>
				<span class="card-value">{fmtKm(recap.longestRunM)}</span>
				<span class="card-sub">single outing</span>
			</div>
			<div class="card">
				<span class="card-label">Fastest pace</span>
				<span class="card-value">{fmtPace(recap.fastestPaceSecPerKm)}</span>
				<span class="card-sub">on runs over 500&nbsp;m</span>
			</div>
			<div class="card">
				<span class="card-label">Best streak</span>
				<span class="card-value">{recap.bestStreakDays} <small>days</small></span>
				<span class="card-sub">consecutive run days</span>
			</div>
			<div class="card">
				<span class="card-label">Top week</span>
				<span class="card-value">{fmtKm(recap.topWeek?.distanceM ?? 0)}</span>
				<span class="card-sub">
					{#if recap.topWeek}
						week of {fmtWeekStart(recap.topWeek.weekStart)}
					{:else}
						no weekly data
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
			<header class="month-chart-head">
				<h2>Distance by month</h2>
				<span class="month-chart-meta">
					Peak {fmtKm(maxMonthlyDistance(recap.monthly))}
				</span>
			</header>
			<div class="bars">
				{#each recap.monthly as m (m.month)}
					{@const max = maxMonthlyDistance(recap.monthly)}
					{@const pct = (m.distanceM / max) * 100}
					<div class="bar-col" title={`${fmtKm(m.distanceM)} (${m.runCount} runs)`}>
						<span class="bar-track">
							<span class="bar" class:bar-empty={m.runCount === 0} style="height: {pct}%"></span>
						</span>
						<span class="bar-label">{MONTH_LABELS[m.month - 1]}</span>
					</div>
				{/each}
			</div>
		</section>

		<section class="closing">
			<h2>Wrap it up</h2>
			<p>
				That's {fmtKm(recap.totalDistanceM)} of effort. Share the card, then come back next
				year and beat it.
			</p>
			<button type="button" class="btn btn-primary" onclick={shareRecap}>
				<span class="material-symbols">ios_share</span>
				Share my {recap.year}
			</button>
		</section>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 72rem;
		margin: 0 auto;
	}
	.muted {
		color: var(--color-text-secondary);
	}

	.hero {
		position: relative;
		padding: var(--space-2xl) var(--space-xl);
		text-align: center;
		background:
			radial-gradient(circle at 80% 20%, color-mix(in srgb, var(--color-accent-orange) 30%, transparent), transparent 55%),
			radial-gradient(circle at 15% 90%, color-mix(in srgb, var(--color-secondary) 28%, transparent), transparent 55%),
			linear-gradient(135deg, var(--color-primary) 0%, color-mix(in srgb, var(--color-primary) 70%, #000) 100%);
		color: var(--color-bg);
		border-radius: var(--radius-xl);
		margin-bottom: var(--space-xl);
		overflow: hidden;
	}
	.hero-empty {
		background: var(--color-bg-secondary);
		color: var(--color-text);
		border: 1px solid var(--color-border);
	}
	.hero-empty .kicker {
		color: var(--color-text-tertiary);
	}
	.hero-empty h1 {
		font-size: 2rem;
	}
	.empty-sub {
		max-width: 32rem;
		margin: 0 auto;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.12em;
		font-size: 0.78rem;
		font-weight: 700;
		opacity: 0.85;
		margin: 0 0 var(--space-md);
	}
	.bignum {
		font-size: clamp(3.5rem, 9vw, 6rem);
		font-weight: 900;
		margin: 0;
		line-height: 0.95;
		letter-spacing: -0.02em;
	}
	.subhead {
		font-size: 1.05rem;
		opacity: 0.92;
		margin: var(--space-sm) 0 var(--space-lg);
	}
	.hero-meta {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: center;
		gap: var(--space-sm) var(--space-md);
		padding: var(--space-sm) var(--space-lg);
		background: rgba(255, 255, 255, 0.12);
		border-radius: 999px;
		margin-bottom: var(--space-lg);
	}
	.hero-meta-item {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.9rem;
		font-weight: 600;
	}
	.hero-meta-item .material-symbols {
		font-size: 1.1rem;
	}
	.hero-meta-divider {
		width: 1px;
		height: 1rem;
		background: rgba(255, 255, 255, 0.25);
	}
	.share-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: var(--color-bg);
		color: var(--color-primary);
		font-weight: 700;
		border-color: transparent;
		box-shadow: var(--shadow-md);
	}
	.share-btn:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-lg);
	}
	.share-btn .material-symbols {
		font-size: 1.1rem;
	}

	.cards {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
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
		transition: transform 0.15s ease, border-color 0.15s ease;
	}
	.card:hover {
		transform: translateY(-2px);
		border-color: color-mix(in srgb, var(--color-primary) 35%, var(--color-border));
	}
	.card-label {
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-tertiary);
	}
	.card-value {
		font-size: 1.85rem;
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		letter-spacing: -0.01em;
	}
	.card-value small {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.card-sub {
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-2xs);
	}

	.month-chart {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}
	.month-chart-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.month-chart h2 {
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.month-chart-meta {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.bars {
		display: grid;
		grid-template-columns: repeat(12, 1fr);
		gap: 0.4rem;
		align-items: end;
		height: 13rem;
	}
	.bar-col {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: end;
		height: 100%;
		gap: 0.4rem;
	}
	.bar-track {
		width: 100%;
		height: 100%;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-sm);
		display: flex;
		align-items: flex-end;
		overflow: hidden;
	}
	.bar {
		width: 100%;
		min-height: 2px;
		background: linear-gradient(180deg, var(--color-secondary), var(--color-primary));
		border-radius: var(--radius-sm);
	}
	.bar-empty {
		background: transparent;
		min-height: 0;
	}
	.bar-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}

	.closing {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		text-align: center;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
	}
	.closing h2 {
		margin: 0;
		font-size: 1.4rem;
		font-weight: 800;
	}
	.closing p {
		margin: 0 0 var(--space-sm);
		color: var(--color-text-secondary);
		max-width: 36rem;
		line-height: 1.5;
	}
	.closing .material-symbols {
		font-size: 1.1rem;
	}
	.closing .btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
</style>
