<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { supabase } from '$lib/supabase';
	import { PUBLIC_SUPABASE_URL } from '$env/static/public';

	let loading = $state<string | null>(null);

	let hasDonated = $state(false);

	const donateAmounts = [
		{ id: 'donate_5', amount: '$5', label: 'Buy me a gel' },
		{ id: 'donate_10', amount: '$10', label: 'Buy me a race entry' },
		{ id: 'donate_25', amount: '$25', label: 'Buy me new shoes', popular: true },
		{ id: 'donate_50', amount: '$50', label: 'Sponsor a month of servers' },
	];

	const features = [
		'GPS recording (phone, Wear OS, Apple Watch)',
		'Unlimited run history + sync',
		'Route builder + GPX/KML/GeoJSON import/export',
		'Public route discovery, tags, reviews',
		'Training plans with VDOT paces',
		'AI Coach (personalised advice from Claude)',
		'Clubs, events, live race mode',
		'Race leaderboards + results',
		'Full backup & restore',
		'Strava ZIP + parkrun + Health Connect import',
		'Cross-device settings sync',
		'Personal bests, weekly goals, splits',
		'Background sync',
	];

	async function handleDonate(donateId: string) {
		// TODO: Replace with Stripe Checkout or Ko-fi / Buy Me a Coffee
		// redirect. For now, show a thank-you message.
		loading = donateId;
		try {
			// Placeholder — in production this redirects to a payment
			// link. The actual donation flow is external (Stripe, Ko-fi,
			// GitHub Sponsors, etc.) and doesn't change subscription_tier.
			showToast('Thank you! Payment integration coming soon.', 'info');
			hasDonated = true;
		} finally {
			loading = null;
		}
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Support Better Runner</h1>
		<p class="subtitle">
			Every feature is free. If the app has helped your running, a donation
			keeps the servers on and development going.
		</p>
	</header>

	{#if hasDonated}
		<section class="thank-you">
			<span class="heart">&#10084;</span>
			<strong>Thank you for your support!</strong>
		</section>
	{/if}

	<div class="plans">
		{#each donateAmounts as d (d.id)}
			<div class="plan-card" class:popular={d.popular}>
				{#if d.popular}
					<div class="popular-tag">Most popular</div>
				{/if}
				<div class="price">
					<span class="amount">{d.amount}</span>
				</div>
				<p class="plan-desc">{d.label}</p>
				<button
					class="btn-plan"
					class:primary={d.popular}
					onclick={() => handleDonate(d.id)}
					disabled={loading !== null}
				>
					{loading === d.id ? 'Processing...' : 'Donate'}
				</button>
			</div>
		{/each}
	</div>

	<section class="comparison">
		<h2>Everything is free</h2>
		<table>
			<thead>
				<tr>
					<th>Feature</th>
					<th>Included</th>
				</tr>
			</thead>
			<tbody>
				{#each features as f}
					<tr>
						<td>{f}</td>
						<td class="check">✓</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</section>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 52rem;
	}
	.page-header { margin-bottom: var(--space-xl); text-align: center; }
	h1 { font-size: 1.75rem; font-weight: 800; margin-bottom: var(--space-xs); }
	.subtitle { color: var(--color-text-secondary); font-size: 0.95rem; }

	.thank-you {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 1rem 1.25rem;
		background: rgba(46, 125, 50, 0.08);
		border: 1.5px solid #2e7d32;
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-xl);
		font-size: 0.95rem;
	}
	.heart { font-size: 1.5rem; color: #e53935; }

	.current-plan {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 1rem 1.25rem;
		background: var(--color-primary-light);
		border: 1.5px solid var(--color-primary);
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-xl);
	}
	.pro-badge {
		background: var(--color-primary);
		color: white;
		font-size: 0.7rem;
		font-weight: 800;
		letter-spacing: 0.08em;
		padding: 0.3rem 0.8rem;
		border-radius: 9999px;
	}
	.plan-note { font-size: 0.82rem; color: var(--color-text-secondary); margin: 0.2rem 0 0; }
	.link-btn {
		background: none;
		border: none;
		color: var(--color-primary);
		cursor: pointer;
		font-size: 0.82rem;
		padding: 0;
		text-decoration: underline;
	}

	.plans {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-lg);
		margin-bottom: var(--space-2xl);
	}
	@media (max-width: 48rem) {
		.plans { grid-template-columns: 1fr; }
	}
	.plan-card {
		background: var(--color-surface);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
		display: flex;
		flex-direction: column;
		position: relative;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}
	.plan-card:hover { border-color: var(--color-primary); }
	.plan-card.popular {
		border-color: var(--color-primary);
		box-shadow: 0 4px 20px rgba(79, 70, 229, 0.15);
	}
	.plan-card.active {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.popular-tag {
		position: absolute;
		top: -0.7rem;
		left: 50%;
		transform: translateX(-50%);
		background: var(--color-primary);
		color: white;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.2rem 0.8rem;
		border-radius: 9999px;
		letter-spacing: 0.04em;
	}
	.plan-card h3 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0 0 0.75rem;
	}
	.price { margin-bottom: 0.5rem; }
	.amount { font-size: 2rem; font-weight: 800; }
	.period { font-size: 0.85rem; color: var(--color-text-secondary); margin-left: 0.2rem; }
	.plan-desc {
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		flex: 1;
		margin-bottom: 1rem;
	}
	.btn-plan {
		width: 100%;
		padding: 0.6rem;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
		font-weight: 600;
		cursor: pointer;
		border: 1.5px solid var(--color-border);
		background: var(--color-bg);
		color: var(--color-text);
		transition: all var(--transition-fast);
	}
	.btn-plan:hover { border-color: var(--color-primary); color: var(--color-primary); }
	.btn-plan.primary {
		background: var(--color-primary);
		color: white;
		border-color: var(--color-primary);
	}
	.btn-plan.primary:hover { background: var(--color-primary-hover); }
	.btn-plan.current { opacity: 0.6; cursor: default; }
	.btn-plan:disabled { opacity: 0.5; cursor: not-allowed; }

	h2 {
		font-size: 1.1rem;
		font-weight: 700;
		margin-bottom: var(--space-lg);
		text-align: center;
	}
	.comparison {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
	}
	table { width: 100%; border-collapse: collapse; }
	th {
		text-align: left;
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-secondary);
		padding: 0.5rem 0;
		border-bottom: 1px solid var(--color-border);
	}
	th:not(:first-child) { text-align: center; width: 4rem; }
	td {
		padding: 0.5rem 0;
		font-size: 0.85rem;
		border-bottom: 1px solid var(--color-border);
	}
	td.check { text-align: center; font-size: 1rem; }
	td.pro-check { color: var(--color-primary); font-weight: 700; }
	tr:last-child td { border-bottom: none; }
</style>
