<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	// External donation link. One-off donations are intentionally routed
	// through an external provider so the app doesn't have to own a payment
	// integration just for chip-ins. Swap for Stripe / Ko-fi / GitHub
	// Sponsors as appropriate.
	const DONATE_URL = 'https://github.com/sponsors';

	const PRO_PRICE_MONTHLY = 9.99;

	let purchasing = $state(false);

	const isPro = $derived(auth.isPro);

	async function handleGetPro() {
		// RevenueCat web SDK is not wired yet — see docs/paywall.md.
		purchasing = true;
		try {
			showToast('Pro checkout is coming soon — thanks for your patience.', 'info');
		} finally {
			purchasing = false;
		}
	}

	function handleDonate() {
		window.open(DONATE_URL, '_blank', 'noopener,noreferrer');
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Pro &amp; support</h1>
		<p class="subtitle">
			Upgrade for unlimited coach chat and priority processing, or chip in
			one-off to help cover server costs.
		</p>
	</header>

	<section class="card pro-card" class:active={isPro}>
		<header class="pro-header">
			<div>
				<h2>Pro</h2>
				<p class="pro-price">
					<span class="price-amount">${PRO_PRICE_MONTHLY}</span>
					<span class="price-period">/ month</span>
				</p>
			</div>
			{#if isPro}<span class="pro-badge">Active</span>{/if}
		</header>
		<ul class="pro-features">
			<li>
				<span class="check">✓</span>
				<div>
					<strong>Unlimited AI Coach</strong>
					<span class="feat-sub">No 10 / day cap on coach chat.</span>
				</div>
			</li>
			<li>
				<span class="check">✓</span>
				<div>
					<strong>Priority processing</strong>
					<span class="feat-sub">Faster responses when the service is under heavy load.</span>
				</div>
			</li>
			<li>
				<span class="check">✓</span>
				<div>
					<strong>Everything in Free</strong>
					<span class="feat-sub">Recording, routes, plans, clubs, sync, imports — all of it.</span>
				</div>
			</li>
		</ul>
		{#if isPro}
			<p class="pro-note">
				Thanks for supporting Better Runner. Manage your subscription from
				the App Store, Play Store, or billing portal where you started it.
			</p>
		{:else}
			<button class="btn-primary" onclick={handleGetPro} disabled={purchasing}>
				{purchasing ? 'Redirecting…' : `Get Pro — $${PRO_PRICE_MONTHLY}/mo`}
			</button>
		{/if}
	</section>

	<section class="card donate-card">
		<h2>Support the project</h2>
		<p>
			If a subscription isn't for you, a one-off donation helps keep the
			app running.
		</p>
		<button class="btn-secondary" onclick={handleDonate}>Donate</button>
	</section>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 40rem;
	}
	.page-header {
		margin-bottom: var(--space-xl);
		text-align: center;
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		margin-bottom: var(--space-xs);
	}
	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		max-width: 32rem;
		margin: 0 auto;
		line-height: 1.5;
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.75rem;
		margin-bottom: var(--space-xl);
	}
	.card h2 {
		font-size: 1.15rem;
		font-weight: 700;
		margin: 0 0 0.5rem;
	}
	.card p {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.5;
		margin: 0 0 1rem;
	}

	.pro-card {
		border-color: var(--color-primary);
		border-width: 1.5px;
	}
	.pro-card.active {
		background: color-mix(in srgb, var(--color-primary) 6%, var(--color-surface));
	}
	.pro-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: 1.25rem;
	}
	.pro-price {
		margin: 0;
		display: flex;
		align-items: baseline;
		gap: 0.25rem;
	}
	.price-amount {
		font-size: 1.6rem;
		font-weight: 800;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
	}
	.price-period {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.pro-badge {
		background: #2e7d32;
		color: white;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.2rem 0.6rem;
		border-radius: 9999px;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}
	.pro-features {
		list-style: none;
		padding: 0;
		margin: 0 0 1.5rem;
		display: grid;
		gap: 0.85rem;
	}
	.pro-features li {
		display: flex;
		gap: 0.75rem;
		align-items: flex-start;
	}
	.pro-features strong {
		display: block;
		font-weight: 600;
		font-size: 0.95rem;
	}
	.feat-sub {
		display: block;
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		margin-top: 0.15rem;
		line-height: 1.4;
	}
	.check {
		color: #2e7d32;
		font-weight: 700;
		flex-shrink: 0;
		margin-top: 0.1rem;
	}
	.pro-note {
		margin: 0;
		padding: 0.75rem 1rem;
		background: color-mix(in srgb, #2e7d32 8%, transparent);
		border-left: 3px solid #2e7d32;
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.btn-primary {
		width: 100%;
		padding: 0.85rem 1rem;
		background: var(--color-primary);
		color: white;
		border: none;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.95rem;
		cursor: pointer;
		transition: filter 0.15s ease, transform 0.15s ease;
	}
	.btn-primary:hover {
		filter: brightness(1.08);
	}
	.btn-primary:active {
		transform: translateY(1px);
	}
	.btn-primary:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}

	.btn-secondary {
		padding: 0.7rem 1.5rem;
		background: transparent;
		color: var(--color-primary);
		border: 1.5px solid var(--color-primary);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.9rem;
		cursor: pointer;
		transition: background 0.15s ease;
	}
	.btn-secondary:hover {
		background: color-mix(in srgb, var(--color-primary) 10%, transparent);
	}
</style>
