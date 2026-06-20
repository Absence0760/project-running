<script lang="ts">
	import RecapView from '$lib/components/RecapView.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import type { YearInRunningRecap } from '$lib/runs/recap';

	let { data } = $props();

	// The frozen snapshot is a YearInRunningRecap-shaped aggregate. Tolerate a
	// snapshot from an older/newer build by defaulting the optional surfaces so
	// RecapView can't crash on a missing field.
	let recap = $derived.by<YearInRunningRecap | null>(() => {
		if (!data.recap) return null;
		const s = data.recap.snapshot as Partial<YearInRunningRecap>;
		return {
			year: s.year ?? 0,
			month: s.month,
			runCount: s.runCount ?? 0,
			totalDistanceM: s.totalDistanceM ?? 0,
			totalDurationS: s.totalDurationS ?? 0,
			totalElevationM: s.totalElevationM ?? 0,
			longestRunM: s.longestRunM ?? 0,
			fastestPaceSecPerKm: s.fastestPaceSecPerKm ?? null,
			bestStreakDays: s.bestStreakDays ?? 0,
			currentStreakDays: s.currentStreakDays ?? 0,
			earliestStartLocal: s.earliestStartLocal ?? null,
			latestStartLocal: s.latestStartLocal ?? null,
			monthly:
				s.monthly ??
				Array.from({ length: 12 }, (_, i) => ({
					month: i + 1,
					distanceM: 0,
					durationS: 0,
					runCount: 0
				})),
			topWeek: s.topWeek ?? null,
			uniqueRouteCount: s.uniqueRouteCount ?? 0,
			mostUsedActivity: s.mostUsedActivity ?? null,
			photoCount: s.photoCount ?? 0,
			personalRecordCount: s.personalRecordCount ?? 0,
			badges: s.badges ?? []
		};
	});

	let periodLabel = $derived(data.periodLabel ?? (recap ? String(recap.year) : ''));
	let title = $derived(
		recap
			? t('recap.sharePageTitle', { period: periodLabel, name: data.recap?.displayName ?? '' })
			: t('recap.shareNotFoundTitle')
	);
	let description = $derived(
		recap ? t('recap.shareMetaDescription', { period: periodLabel }) : t('recap.shareNotFoundSub')
	);

	// Read-only on the public page: a viewer (often anon) can't publish or
	// re-share someone else's recap — the share + publish actions belong to the
	// owner on /recap/[year]. So no onshare/onpublish passed to RecapView.
	function noop() {}
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og/recap/{data.id}.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og/recap/{data.id}.png" />
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Threkir</a>
	</header>

	{#if recap}
		<main class="content">
			<p class="attribution">
				{#if data.recap?.displayName}
					{t('recap.shareAttribution', { name: data.recap.displayName, period: periodLabel })}
				{:else}
					{t('recap.shareAttributionAnon', { period: periodLabel })}
				{/if}
			</p>
			<RecapView
				{recap}
				kicker={t('recap.shareKicker', { period: periodLabel })}
				shareLabel={t('recap.shareGoMakeYours')}
				onshare={noop}
			/>
		</main>
	{:else}
		<main class="content">
			<div class="notfound-card">
				<p class="kicker">{t('recap.shareNotFoundKicker')}</p>
				<h1>{t('recap.shareNotFoundTitle')}</h1>
				<p class="notfound-sub">{t('recap.shareNotFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{t('shareRun.signIn')}</a>
					<a class="btn btn-outline" href="/">{t('shareRun.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && recap}
		<section class="signup-cta">
			<p class="kicker">{t('recap.shareCtaKicker')}</p>
			<h2>{t('recap.shareCtaHeading')}</h2>
			<p class="signup-sub">{t('recap.shareCtaSub')}</p>
			<a class="btn btn-primary" href="/login?signup=1">{t('recap.shareCtaButton')}</a>
		</section>
	{/if}

	<footer class="share-footer">
		<a href="/">{t('shareRun.footerHome')}</a>
		<span class="dot">&middot;</span>
		<a href="/login">{t('shareRun.signIn')}</a>
	</footer>
</div>

<style>
	.share-page {
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}
	.share-header {
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}
	.share-logo {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-primary);
		text-decoration: none;
	}
	.content {
		max-width: 72rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-lg) var(--space-md);
	}
	.attribution {
		text-align: center;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		margin: 0 0 var(--space-md);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
	}
	.notfound-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl) var(--space-lg);
		margin-top: var(--space-xl);
		text-align: center;
	}
	.notfound-card h1 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.notfound-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 28rem;
		margin: 0 auto var(--space-lg);
		line-height: 1.5;
	}
	.notfound-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
	.signup-cta {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-lg) var(--space-md) var(--space-xl);
		text-align: center;
	}
	.signup-cta h2 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.signup-cta .signup-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin: 0 auto var(--space-md);
		line-height: 1.5;
	}
	.dot {
		color: var(--color-text-tertiary);
		margin: 0 0.3rem;
	}
	.share-footer {
		margin-top: auto;
		padding: var(--space-lg) var(--space-md);
		border-top: 1px solid var(--color-border);
		text-align: center;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		background: var(--color-surface);
	}
	.share-footer a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}
	.share-footer a:hover {
		color: var(--color-primary);
	}
</style>
