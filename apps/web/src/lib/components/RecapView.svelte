<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { fmtKm, fmtPace } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import type { YearInRunningRecap } from '$lib/runs/recap';

	interface Props {
		recap: YearInRunningRecap;
		/** Uppercase eyebrow over the hero (e.g. "My 2026 in running"). */
		kicker: string;
		/** Closing-section CTA label (e.g. "Share my 2026"). */
		shareLabel: string;
		onshare: () => void;
		/** Optional "publish a public link" action shown alongside the image share. */
		onpublish?: (() => void) | null;
		publishing?: boolean;
	}

	let { recap, kicker, shareLabel, onshare, onpublish = null, publishing = false }: Props =
		$props();

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
</script>

<header class="hero">
	<p class="kicker">{kicker}</p>
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
		{#if recap.month == null}
			<span class="hero-meta-divider" aria-hidden="true"></span>
			<span class="hero-meta-item">
				<span class="material-symbols">calendar_month</span>
				{t(
					activeMonths(recap.monthly) === 1
						? 'recap.activeInMonthsOne'
						: 'recap.activeInMonthsMany',
					{ n: activeMonths(recap.monthly) }
				)}
			</span>
		{/if}
	</div>
	<div class="hero-actions">
		<button type="button" class="btn share-btn" onclick={onshare}>
			<span class="material-symbols">ios_share</span>
			{t('recap.shareRecap')}
		</button>
		{#if onpublish}
			<button
				type="button"
				class="btn publish-btn"
				onclick={onpublish}
				disabled={publishing}
			>
				<span class="material-symbols">link</span>
				{publishing ? t('recap.publishing') : t('recap.publishAndShare')}
			</button>
		{/if}
	</div>
	{#if onpublish}
		<p class="publish-note">{t('recap.makePublicExplain')}</p>
	{/if}
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

{#if recap.month == null}
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
				<div
					class="bar-col"
					title={t(m.runCount === 1 ? 'recap.barTitleOne' : 'recap.barTitleMany', {
						distance: fmtKm(m.distanceM),
						n: m.runCount
					})}
				>
					<span class="bar-track">
						<span class="bar" class:bar-empty={m.runCount === 0} style="height: {pct}%"></span>
					</span>
					<span class="bar-label">{MONTH_LABELS[m.month - 1]}</span>
				</div>
			{/each}
		</div>
	</section>
{/if}

<section class="closing">
	<h2>{t('recap.wrapItUp')}</h2>
	<p>
		{t('recap.closingBody', { distance: fmtKm(recap.totalDistanceM) })}
	</p>
	<button type="button" class="btn btn-primary" onclick={onshare}>
		<span class="material-symbols">ios_share</span>
		{shareLabel}
	</button>
</section>

<style>
	.hero {
		position: relative;
		padding: var(--space-2xl) var(--space-xl);
		text-align: center;
		background:
			radial-gradient(
				circle at 80% 20%,
				color-mix(in srgb, var(--color-accent-orange) 30%, transparent),
				transparent 55%
			),
			radial-gradient(
				circle at 15% 90%,
				color-mix(in srgb, var(--color-secondary) 28%, transparent),
				transparent 55%
			),
			linear-gradient(
				135deg,
				var(--color-primary) 0%,
				color-mix(in srgb, var(--color-primary) 70%, #000) 100%
			);
		color: var(--color-bg);
		border-radius: var(--radius-xl);
		margin-bottom: var(--space-xl);
		overflow: hidden;
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
	.hero-actions {
		display: inline-flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		justify-content: center;
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
	.share-btn .material-symbols,
	.publish-btn .material-symbols {
		font-size: 1.1rem;
	}
	.publish-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: rgba(255, 255, 255, 0.16);
		color: var(--color-bg);
		font-weight: 700;
		border-color: rgba(255, 255, 255, 0.4);
	}
	.publish-btn:hover:not(:disabled) {
		background: rgba(255, 255, 255, 0.24);
	}
	.publish-note {
		margin: var(--space-sm) auto 0;
		max-width: 30rem;
		font-size: 0.8rem;
		opacity: 0.85;
		line-height: 1.4;
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
		transition:
			transform 0.15s ease,
			border-color 0.15s ease;
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
		transition:
			transform 0.15s ease,
			border-color 0.15s ease;
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
