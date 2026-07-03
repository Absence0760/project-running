<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { formatPrice } from '$lib/format/format_price';
	import { m } from '$lib/i18n/store.svelte';
	import {
		proCheckoutUrl,
		managementUrl,
		isRevenueCatConfigured,
	} from '$lib/billing/revenuecat';
	import { coachEnabled } from '$lib/coach/coach_flag';

	// Every Pro perk is a Coach feature, so when the Coach is off (rock-bottom
	// deploy, ANTHROPIC_API_KEY unset) Pro delivers nothing. Don't sell it:
	// show a "coming soon" teaser and lead with donations. paywall.md.
	const coachOn = coachEnabled();

	// External donation link. One-off donations are intentionally routed
	// through an external provider so the app doesn't have to own a payment
	// integration just for chip-ins. Swap for Stripe / Ko-fi / GitHub
	// Sponsors as appropriate.
	const DONATE_URL = 'https://github.com/sponsors';

	const PRO_PRICE_MONTHLY_USD = 9.99;
	const priceLabel = $derived(formatPrice(PRO_PRICE_MONTHLY_USD));

	let purchasing = $state(false);

	const isPro = $derived(auth.isPro);

	function handleGetPro() {
		const userId = auth.user?.id;
		if (!userId) {
			showToast(m('upgrade.signInToUpgrade'), 'error');
			return;
		}
		const url = proCheckoutUrl(userId, window.location.href);
		if (!url) {
			// Dev / preview builds without a RevenueCat checkout link fall
			// back to the original placeholder so the page stays usable
			// end-to-end without a real billing account.
			showToast(m('upgrade.checkoutNotConfigured'), 'info');
			return;
		}
		// Full-page redirect to the hosted checkout. On success RevenueCat
		// redirects back to `redirect_url` (this page); the webhook flips
		// the tier server-side and the reloaded page refetches the profile.
		purchasing = true;
		window.location.href = url;
	}

	function handleDonate() {
		window.open(DONATE_URL, '_blank', 'noopener,noreferrer');
	}

	/// Opens the billing portal where the Pro subscription was started.
	/// Mobile purchases route through the App Store / Play Store — those
	/// users need to cancel on-device. For web purchases RevenueCat's
	/// no-code customer portal authenticates the user by email, so we open
	/// the hosted portal link directly (no per-user SDK call).
	function handleManageSubscription() {
		if (!isRevenueCatConfigured()) {
			showToast(m('upgrade.manageWhereStarted'), 'info');
			return;
		}
		const url = managementUrl();
		if (url) {
			window.open(url, '_blank', 'noopener,noreferrer');
		} else {
			showToast(m('upgrade.noActiveWebSub'), 'info');
		}
	}
</script>

<div class="page">
	<header class="hero">
		<p class="kicker">{m('shell.settings')}</p>
		<h1>{m('upgrade.heroTitle')}</h1>
		<p class="tagline">
			{m('upgrade.heroTagline')}
		</p>
	</header>

	<section class="tier-grid">
		<article class="tier tier-free" aria-labelledby="tier-free-h">
			<header class="tier-head">
				<h2 id="tier-free-h">{m('upgrade.tierFree')}</h2>
				<p class="tier-price">
					<span class="price-amount">{formatPrice(0)}</span>
					<span class="price-period">{m('upgrade.forever')}</span>
				</p>
			</header>
			<p class="tier-blurb">{m('upgrade.freeBlurb')}</p>
			<ul class="tier-features">
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>{m('upgrade.freeFeatRecording')}</span>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>{m('upgrade.freeFeatRoutes')}</span>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>{m('upgrade.freeFeatSync')}</span>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>{m('upgrade.freeFeatCoach')}</span>
				</li>
			</ul>
			{#if !isPro}
				<p class="tier-note">{m('upgrade.youreOnFree')}</p>
			{/if}
		</article>

		<article class="tier tier-pro" class:active={isPro} aria-labelledby="tier-pro-h">
			<span class="tier-flag">{coachOn ? m('upgrade.mostPopular') : m('upgrade.comingSoonFlag')}</span>
			<header class="tier-head">
				<h2 id="tier-pro-h">Pro</h2>
				{#if isPro}<span class="pro-badge">{m('upgrade.active')}</span>{/if}
				<p class="tier-price">
					<span class="price-amount">{priceLabel}</span>
					<span class="price-period">{m('upgrade.perMonth')}</span>
				</p>
				<!-- Honesty notes (audit-findings 2026-05-30 Medium [regional]):
				     the amount is billed in USD (we don't FX-convert), and
				     the payment processor can't serve every country. -->
				<p class="tier-price-note">
					{m('upgrade.priceNote')}
				</p>
			</header>
			<p class="tier-blurb">{m('upgrade.proBlurb')}</p>
			<ul class="tier-features">
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>{m('upgrade.proFeatCoachTitle')}</strong>
						<span class="feat-sub">{m('upgrade.proFeatCoachSub')}</span>
					</div>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>{m('upgrade.proFeatMapMatchTitle')}</strong>
						<span class="feat-sub">{m('upgrade.proFeatMapMatchSub')}</span>
					</div>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>{m('upgrade.proFeatExportsTitle')}</strong>
						<span class="feat-sub">{m('upgrade.proFeatExportsSub')}</span>
					</div>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>{m('upgrade.proFeatEverythingTitle')}</strong>
						<span class="feat-sub">{m('upgrade.proFeatEverythingSub')}</span>
					</div>
				</li>
			</ul>
			{#if isPro}
				<p class="pro-note">
					{m('upgrade.proThanks')}
				</p>
				<button class="btn btn-outline" onclick={handleManageSubscription}>
					{m('upgrade.manageSubscription')}
				</button>
			{:else if coachOn}
				<button class="btn btn-primary tier-cta" onclick={handleGetPro} disabled={purchasing}>
					{purchasing ? m('upgrade.redirecting') : m('upgrade.getPro', { price: priceLabel })}
				</button>
				<p class="tier-fine">{m('upgrade.cancelAnytime')}</p>
			{:else}
				<p class="coming-soon-note">{m('upgrade.proComingSoon')}</p>
			{/if}
		</article>
	</section>

	<section class="donate-card">
		<div class="donate-text">
			<h2>{m('upgrade.donateTitle')}</h2>
			<p>
				{m('upgrade.donateBody')}
			</p>
		</div>
		<button class="btn" class:btn-primary={!coachOn} class:btn-outline={coachOn} onclick={handleDonate}>
			<span class="material-symbols" aria-hidden="true">favorite</span>
			{m('upgrade.donate')}
		</button>
	</section>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 64rem;
	}
	.hero {
		margin-bottom: var(--space-2xl);
		max-width: 44rem;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	.hero h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.15;
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 1rem;
		line-height: 1.55;
		margin: 0;
	}

	.tier-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(20rem, 1fr));
		gap: var(--space-lg);
		margin-bottom: var(--space-2xl);
	}
	.tier {
		position: relative;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.tier-pro {
		border-color: var(--color-primary);
		border-width: 1.5px;
		box-shadow: var(--shadow-md);
	}
	.tier-pro.active {
		background: color-mix(in srgb, var(--color-primary) 6%, var(--color-surface));
	}
	.tier-flag {
		position: absolute;
		top: -0.6rem;
		inset-inline-end: var(--space-lg);
		background: var(--color-primary);
		color: white;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.2rem 0.7rem;
		border-radius: 9999px;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}
	.tier-head {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.tier-head h2 {
		font-size: 1.3rem;
		font-weight: 700;
		margin: 0;
	}
	.tier-price {
		margin: 0 0 0 auto;
		display: flex;
		align-items: baseline;
		gap: 0.25rem;
	}
	.tier-price-note {
		margin: var(--space-2xs) 0 0;
		font-size: 0.72rem;
		line-height: 1.4;
		color: var(--color-text-tertiary);
	}
	.price-amount {
		font-size: 1.5rem;
		font-weight: 800;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
	}
	.tier-free .price-amount { color: var(--color-text); }
	.price-period {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.pro-badge {
		/* WCAG AA: white on --color-success was 3.28/2.22:1; -strong is 5.13:1. */
		background: var(--color-success-strong);
		color: white;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.2rem 0.6rem;
		border-radius: 9999px;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}
	.tier-blurb {
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.tier-features {
		list-style: none;
		padding: 0;
		margin: var(--space-sm) 0 auto;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.tier-features li {
		display: flex;
		gap: 0.6rem;
		align-items: flex-start;
		font-size: 0.9rem;
		line-height: 1.45;
	}
	.tier-features strong {
		display: block;
		font-weight: 600;
		font-size: 0.92rem;
	}
	.feat-sub {
		display: block;
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		margin-top: 0.15rem;
		line-height: 1.4;
	}
	.check {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
		color: var(--color-success);
		flex-shrink: 0;
		line-height: 1.3;
	}
	.tier-cta {
		width: 100%;
		justify-content: center;
		font-size: 0.95rem;
		padding: 0.85rem 1rem;
		margin-top: var(--space-sm);
	}
	.tier-note {
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}
	.tier-fine {
		margin: var(--space-xs) 0 0;
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		text-align: center;
		line-height: 1.4;
	}
	.coming-soon-note {
		margin: var(--space-sm) 0 0;
		padding: 0.75rem 1rem;
		background: var(--color-bg-secondary);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		text-align: center;
		line-height: 1.45;
	}
	.pro-note {
		margin: var(--space-sm) 0;
		padding: 0.75rem 1rem;
		background: var(--color-success-light);
		border-inline-start: 3px solid var(--color-success);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}

	.donate-card {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		flex-wrap: wrap;
	}
	.donate-text { flex: 1; min-width: 16rem; }
	.donate-text h2 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0 0 var(--space-xs);
	}
	.donate-text p {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.5;
	}
	.donate-card .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}
</style>
