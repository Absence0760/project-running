<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { formatPrice } from '$lib/format/format_price';
	import {
		startProCheckout,
		managementUrl,
		isRevenueCatConfigured,
	} from '$lib/billing/revenuecat';

	// External donation link. One-off donations are intentionally routed
	// through an external provider so the app doesn't have to own a payment
	// integration just for chip-ins. Swap for Stripe / Ko-fi / GitHub
	// Sponsors as appropriate.
	const DONATE_URL = 'https://github.com/sponsors';

	const PRO_PRICE_MONTHLY_USD = 9.99;
	const priceLabel = $derived(formatPrice(PRO_PRICE_MONTHLY_USD));

	let purchasing = $state(false);

	const isPro = $derived(auth.isPro);

	async function handleGetPro() {
		const userId = auth.user?.id;
		if (!userId) {
			showToast('Sign in to upgrade to Pro.', 'error');
			return;
		}
		if (!isRevenueCatConfigured()) {
			// Dev / preview builds without a RevenueCat key fall back to
			// the original placeholder so the page stays usable end-to-
			// end without a real billing account.
			showToast('Pro checkout is not configured on this build.', 'info');
			return;
		}
		purchasing = true;
		try {
			const { purchased } = await startProCheckout(userId);
			if (purchased) {
				showToast('Welcome to Pro! Refreshing your subscription…', 'success');
				// The revenuecat-webhook Edge Function flips the tier
				// server-side; refetch the profile so the UI picks up the
				// change without a full reload.
				await auth.fetchUser();
			}
		} catch (err) {
			showToast(
				`Checkout failed: ${err instanceof Error ? err.message : String(err)}`,
				'error',
			);
		} finally {
			purchasing = false;
		}
	}

	function handleDonate() {
		window.open(DONATE_URL, '_blank', 'noopener,noreferrer');
	}

	/// Opens the billing portal where the Pro subscription was started.
	/// Mobile purchases route through the App Store / Play Store — those
	/// users need to cancel on-device. For web purchases the RevenueCat
	/// SDK exposes a `managementURL` on CustomerInfo; we redirect there.
	async function handleManageSubscription() {
		const userId = auth.user?.id;
		if (!userId) return;
		if (!isRevenueCatConfigured()) {
			showToast(
				'Manage your subscription where you started it — App Store / Play Store / billing portal.',
				'info',
			);
			return;
		}
		try {
			const url = await managementUrl(userId);
			if (url) {
				window.open(url, '_blank', 'noopener,noreferrer');
			} else {
				showToast(
					'No active web subscription found — manage in the App Store / Play Store instead.',
					'info',
				);
			}
		} catch (err) {
			showToast(
				`Could not open billing portal: ${err instanceof Error ? err.message : String(err)}`,
				'error',
			);
		}
	}
</script>

<div class="page">
	<header class="hero">
		<p class="kicker">Settings</p>
		<h1>Pro &amp; support</h1>
		<p class="tagline">
			Threkir is free for the parts that matter — recording, routes, plans,
			clubs, imports. Pro raises the daily Coach cap (2 → 10 messages) and
			pushes your map-matching to the front of the queue. Or chip in one-off
			to help keep the lights on.
		</p>
	</header>

	<section class="tier-grid">
		<article class="tier tier-free" aria-labelledby="tier-free-h">
			<header class="tier-head">
				<h2 id="tier-free-h">Free</h2>
				<p class="tier-price">
					<span class="price-amount">{formatPrice(0)}</span>
					<span class="price-period">forever</span>
				</p>
			</header>
			<p class="tier-blurb">Everything you need to record, plan, and share.</p>
			<ul class="tier-features">
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>Unlimited recording on phone &amp; watch</span>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>Routes, plans, clubs, social feed</span>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>Strava, parkrun, Garmin sync &amp; imports</span>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<span>AI Coach — 2 chats per day</span>
				</li>
			</ul>
			{#if !isPro}
				<p class="tier-note">You're on Free.</p>
			{/if}
		</article>

		<article class="tier tier-pro" class:active={isPro} aria-labelledby="tier-pro-h">
			<span class="tier-flag">Most popular</span>
			<header class="tier-head">
				<h2 id="tier-pro-h">Pro</h2>
				{#if isPro}<span class="pro-badge">Active</span>{/if}
				<p class="tier-price">
					<span class="price-amount">{priceLabel}</span>
					<span class="price-period">/ month</span>
				</p>
				<!-- Honesty notes (audit-findings 2026-05-30 Medium [regional]):
				     the amount is billed in USD (we don't FX-convert), and
				     the payment processor can't serve every country. -->
				<p class="tier-price-note">
					Billed in US dollars. Availability depends on your country and payment
					method — some regions can't be served by our payment processor.
				</p>
			</header>
			<p class="tier-blurb">For runners who live in the app.</p>
			<ul class="tier-features">
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>AI Coach — 10/day</strong>
						<span class="feat-sub">5× the Free cap on Coach chat (2/day → 10/day).</span>
					</div>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>Priority map-matching</strong>
						<span class="feat-sub">Your GPS tracks snap to roads in seconds, not minutes.</span>
					</div>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>Priority cloud exports</strong>
						<span class="feat-sub">8 GPX bundle exports per hour vs. 2 on Free.</span>
					</div>
				</li>
				<li>
					<span class="check material-symbols" aria-hidden="true">check_circle</span>
					<div>
						<strong>Everything in Free</strong>
						<span class="feat-sub">Recording, routes, plans, clubs, sync, imports.</span>
					</div>
				</li>
			</ul>
			{#if isPro}
				<p class="pro-note">
					Thanks for supporting Threkir. Manage your subscription where
					you started it — App Store, Play Store, or the web billing portal.
				</p>
				<button class="btn btn-outline" onclick={handleManageSubscription}>
					Manage subscription
				</button>
			{:else}
				<button class="btn btn-primary tier-cta" onclick={handleGetPro} disabled={purchasing}>
					{purchasing ? 'Redirecting…' : `Get Pro — ${priceLabel}/mo`}
				</button>
				<p class="tier-fine">Cancel anytime from the App Store, Play Store, or billing portal.</p>
			{/if}
		</article>
	</section>

	<section class="donate-card">
		<div class="donate-text">
			<h2>Not ready for a subscription?</h2>
			<p>
				A one-off donation helps cover map tiles, push notifications, and the
				occasional server invoice. Every chip-in lands directly with the project.
			</p>
		</div>
		<button class="btn btn-outline" onclick={handleDonate}>
			<span class="material-symbols" aria-hidden="true">favorite</span>
			Donate
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
