<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchRuns, fetchRecapExtras } from '$lib/core/data';
	import { buildYearInRunningRecap, type YearInRunningRecap } from '$lib/runs/recap';
	import { buildRecapShareSvg } from '$lib/share/recap_share_image';
	import { fmtKm, getUnit, fmtPace } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	let runs = $state<Run[]>([]);
	let extras = $state<{ photoCount: number; personalRecordCount: number }>({
		photoCount: 0,
		personalRecordCount: 0
	});
	let loading = $state(true);
	let recap = $state<YearInRunningRecap | null>(null);

	let year = $derived(parseInt($page.params.year ?? '0', 10));
	let valid = $derived(!Number.isNaN(year) && year >= 2010 && year <= 2100);

	onMount(async () => {
		await auth.ready();
		if (!auth.user) {
			loading = false;
			return;
		}
		const yr = year;
		[runs, extras] = await Promise.all([
			fetchRuns(),
			valid ? fetchRecapExtras(yr) : Promise.resolve({ photoCount: 0, personalRecordCount: 0 })
		]);
		loading = false;
	});

	$effect(() => {
		if (!valid) return;
		recap = buildYearInRunningRecap(runs, year, extras);
	});

	function fmtTime(seconds: number): string {
		const h = Math.floor(seconds / 3600);
		const m = Math.floor((seconds % 3600) / 60);
		if (h > 0) return `${h}h ${m}m`;
		return `${m}m`;
	}


	function fmtWeekStart(iso: string): string {
		const d = new Date(iso + 'T00:00:00');
		return d.toLocaleDateString(activeFormatLocale(), { day: 'numeric', month: 'short' });
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
			t('recap.shareTitle', { year: recap.year }),
			'',
			t('recap.shareDistance', { distance: fmtKm(recap.totalDistanceM), n: recap.runCount }),
			t('recap.shareLongest', { distance: fmtKm(recap.longestRunM) }),
			t('recap.shareStreak', { n: recap.bestStreakDays }),
			t('recap.shareTopWeek', { distance: fmtKm(recap.topWeek?.distanceM ?? 0) }),
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
				await navigator.share({ files: [file], title: t('recap.shareTitle', { year: recap.year }), text });
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
				await navigator.share({ title: t('recap.shareTitle', { year: recap.year }), text });
				return;
			} catch (_) {
				// fall through to clipboard
			}
		}
		await navigator.clipboard.writeText(text);
		alert(t('recap.copiedToClipboard'));
	}
</script>

<svelte:head>
	<title>{t('recap.pageTitle', { year })}</title>
</svelte:head>

<div class="page">
	{#if !valid}
		<p class="muted">{t('recap.invalidYear')}</p>
	{:else if loading}
		<p class="muted">{t('recap.loadingYear')}</p>
	{:else if !auth.user}
		<p class="muted">{t('recap.signInPrompt')}</p>
	{:else if recap == null || recap.runCount === 0}
		<header class="hero hero-empty">
			<p class="kicker">{year}</p>
			<h1>{t('recap.noRunsYet', { year })}</h1>
			<p class="empty-sub">
				{t('recap.emptySub')}
			</p>
		</header>
	{:else}
		<header class="hero">
			<p class="kicker">{t('recap.heroKicker', { year: recap.year })}</p>
			<h1 class="bignum">{fmtKm(recap.totalDistanceM)}</h1>
			<p class="subhead">
				{t(recap.runCount === 1 ? 'recap.acrossRunsOne' : 'recap.acrossRunsMany', { n: recap.runCount })}
			</p>
			<div class="hero-meta">
				<span class="hero-meta-item">
					<span class="material-symbols">timer</span>
					{t('recap.onFoot', { time: fmtTime(recap.totalDurationS) })}
				</span>
				<span class="hero-meta-divider" aria-hidden="true"></span>
				<span class="hero-meta-item">
					<span class="material-symbols">terrain</span>
					{t('recap.climbed', { meters: Math.round(recap.totalElevationM).toLocaleString() })}
				</span>
				<span class="hero-meta-divider" aria-hidden="true"></span>
				<span class="hero-meta-item">
					<span class="material-symbols">calendar_month</span>
					{t(activeMonths(recap.monthly) === 1 ? 'recap.activeInMonthsOne' : 'recap.activeInMonthsMany', { n: activeMonths(recap.monthly) })}
				</span>
			</div>
			<button type="button" class="btn share-btn" onclick={shareRecap}>
				<span class="material-symbols">ios_share</span>
				{t('recap.shareRecap')}
			</button>
		</header>

		<section class="cards">
			<div class="card">
				<span class="card-label">{t('recap.longestRun')}</span>
				<span class="card-value">{fmtKm(recap.longestRunM)}</span>
				<span class="card-sub">{t('recap.singleOuting')}</span>
			</div>
			<div class="card">
				<span class="card-label">{t('recap.fastestPace')}</span>
				<span class="card-value">{fmtPace(recap.fastestPaceSecPerKm)}</span>
				<span class="card-sub">{t('recap.fastestPaceSub')}</span>
			</div>
			<div class="card">
				<span class="card-label">{t('recap.bestStreak')}</span>
				<span class="card-value">{recap.bestStreakDays} <small>{t('recap.days')}</small></span>
				<span class="card-sub">{t('recap.consecutiveRunDays')}</span>
			</div>
			<div class="card">
				<span class="card-label">{t('recap.topWeek')}</span>
				<span class="card-value">{fmtKm(recap.topWeek?.distanceM ?? 0)}</span>
				<span class="card-sub">
					{#if recap.topWeek}
						{t('recap.weekOf', { date: fmtWeekStart(recap.topWeek.weekStart) })}
					{:else}
						{t('recap.noWeeklyData')}
					{/if}
				</span>
			</div>
			<div class="card">
				<span class="card-label">{t('recap.routesRun')}</span>
				<span class="card-value">{recap.uniqueRouteCount}</span>
				<span class="card-sub">{t('recap.distinctSavedRoutes')}</span>
			</div>
			<div class="card">
				<span class="card-label">{t('recap.earliestStart')}</span>
				<span class="card-value">{recap.earliestStartLocal ?? '—'}</span>
				<span class="card-sub">{t('recap.localTime')}</span>
			</div>
			<div class="card">
				<span class="card-label">{t('recap.personalRecords')}</span>
				<span class="card-value">{recap.personalRecordCount}</span>
				<span class="card-sub">{t('recap.setThisYear')}</span>
			</div>
			<div class="card">
				<span class="card-label">{t('recap.photos')}</span>
				<span class="card-value">{recap.photoCount}</span>
				<span class="card-sub">{t('recap.momentsCaptured')}</span>
			</div>
		</section>

		{#if recap.badges.length > 0}
			<section class="badges">
				<header class="badges-head">
					<h2>{t('recap.trophies')}</h2>
					<span class="badges-meta">
						{t('recap.earnedInYear', { n: recap.badges.length, year: recap.year })}
					</span>
				</header>
				<div class="badge-grid">
					{#each recap.badges as b (b.id)}
						<div class="badge">
							<span class="badge-icon material-symbols" aria-hidden="true">{b.icon}</span>
							<span class="badge-label">{b.label}</span>
							<span class="badge-detail">{b.detail}</span>
						</div>
					{/each}
				</div>
			</section>
		{/if}

		<section class="month-chart">
			<header class="month-chart-head">
				<h2>{t('recap.distanceByMonth')}</h2>
				<span class="month-chart-meta">
					{t('recap.peak', { distance: fmtKm(maxMonthlyDistance(recap.monthly)) })}
				</span>
			</header>
			<div class="bars">
				{#each recap.monthly as m (m.month)}
					{@const max = maxMonthlyDistance(recap.monthly)}
					{@const pct = (m.distanceM / max) * 100}
					<div class="bar-col" title={t(m.runCount === 1 ? 'recap.barTitleOne' : 'recap.barTitleMany', { distance: fmtKm(m.distanceM), n: m.runCount })}>
						<span class="bar-track">
							<span class="bar" class:bar-empty={m.runCount === 0} style="height: {pct}%"></span>
						</span>
						<span class="bar-label">{MONTH_LABELS[m.month - 1]}</span>
					</div>
				{/each}
			</div>
		</section>

		<section class="closing">
			<h2>{t('recap.wrapItUp')}</h2>
			<p>
				{t('recap.closingBody', { distance: fmtKm(recap.totalDistanceM) })}
			</p>
			<button type="button" class="btn btn-primary" onclick={shareRecap}>
				<span class="material-symbols">ios_share</span>
				{t('recap.shareMyYear', { year: recap.year })}
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

	.badges {
		margin-bottom: var(--space-xl);
	}
	.badges-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.badges h2 {
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.badges-meta {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.badge-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
		gap: var(--space-md);
	}
	.badge {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 0.3rem;
		transition: transform 0.15s ease, border-color 0.15s ease;
	}
	.badge:hover {
		transform: translateY(-2px);
		border-color: color-mix(in srgb, var(--color-accent-orange) 45%, var(--color-border));
	}
	.badge-icon {
		font-size: 2rem;
		color: var(--color-accent-orange);
		background: color-mix(in srgb, var(--color-accent-orange) 14%, transparent);
		width: 3.25rem;
		height: 3.25rem;
		display: grid;
		place-items: center;
		border-radius: 999px;
		margin-bottom: var(--space-2xs);
	}
	.badge-label {
		font-weight: 800;
		font-size: 0.98rem;
	}
	.badge-detail {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		line-height: 1.35;
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
