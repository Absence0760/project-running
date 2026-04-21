<script lang="ts">
	import { onMount } from 'svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { supabase } from '$lib/supabase';

	// Monthly cost breakdown — update these when infrastructure changes.
	const costs = [
		{ name: 'Supabase Pro (DB, Auth, Storage)', amount: 25 },
		{ name: 'Claude API (AI Coach)', amount: 30 },
		{ name: 'MapTiler (map tiles)', amount: 20 },
		{ name: 'Domain + DNS', amount: 2 },
		{ name: 'Misc (monitoring, email)', amount: 3 },
	];
	const serverCostTotal = costs.reduce((s, c) => s + c.amount, 0);
	const devCost = 3000;
	const monthlyTarget = serverCostTotal + devCost;

	let amountReceived = $state(0);
	let donorCount = $state(0);
	let loading = $state(false);

	let serverPct = $derived(Math.min(100, Math.round((amountReceived / serverCostTotal) * 100)));
	let totalPct = $derived(Math.min(100, Math.round((amountReceived / monthlyTarget) * 100)));
	let serverCovered = $derived(amountReceived >= serverCostTotal);

	onMount(async () => {
		const firstOfMonth = new Date();
		firstOfMonth.setDate(1);
		firstOfMonth.setHours(0, 0, 0, 0);
		const monthStr = firstOfMonth.toISOString().slice(0, 10);
		const { data } = await supabase
			.from('monthly_funding')
			.select('amount_received, donor_count')
			.eq('month', monthStr)
			.maybeSingle();
		if (data) {
			amountReceived = Number(data.amount_received);
			donorCount = data.donor_count;
		}
	});

	const donateOptions = [
		{ id: 'donate_5', amount: 5, label: 'Buy me a gel', icon: '🧴', color: '#89D0B8' },
		{ id: 'donate_15', amount: 15, label: 'Cover a day of servers', icon: '🖥', color: '#B9A7E8' },
		{ id: 'donate_50', amount: 50, label: 'Cover a week of servers', icon: '🚀', color: '#F2A07B' },
		{ id: 'donate_80', amount: 80, label: 'Cover a full month of servers', icon: '💛', color: '#E6A96B' },
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

	async function handleDonate(amount: number) {
		// TODO: Replace with Stripe Checkout / Ko-fi / GitHub Sponsors
		// redirect. The webhook or return URL updates monthly_funding.
		loading = true;
		try {
			showToast('Thank you! Payment integration coming soon.', 'info');
		} finally {
			loading = false;
		}
	}

	function fmtCurrency(n: number): string {
		return `$${n.toLocaleString()}`;
	}

	const monthName = new Date().toLocaleString(undefined, { month: 'long', year: 'numeric' });
</script>

<div class="page">
	<header class="page-header">
		<h1>Fund Better Runner</h1>
		<p class="subtitle">
			Every feature is free, forever. Your donations keep the servers running
			and development moving.
		</p>
	</header>

	<!-- Progress bars -->
	<section class="card funding-card">
		<h2>Monthly funding — {monthName}</h2>

		<div class="progress-section">
			<div class="progress-header">
				<span class="progress-label">Server costs</span>
				<span class="progress-value">
					{fmtCurrency(Math.min(amountReceived, serverCostTotal))} / {fmtCurrency(serverCostTotal)}
					{#if serverCovered}<span class="covered-badge">Covered</span>{/if}
				</span>
			</div>
			<div class="progress-bar">
				<div
					class="progress-fill server"
					style="width: {serverPct}%"
				></div>
			</div>
		</div>

		<div class="progress-section">
			<div class="progress-header">
				<span class="progress-label">Server + 1 dedicated developer</span>
				<span class="progress-value">
					{fmtCurrency(amountReceived)} / {fmtCurrency(monthlyTarget)}
				</span>
			</div>
			<div class="progress-bar">
				<div
					class="progress-fill total"
					style="width: {totalPct}%"
				></div>
			</div>
			<p class="progress-sub">
				{donorCount} donor{donorCount === 1 ? '' : 's'} this month
			</p>
		</div>
	</section>

	<!-- Cost breakdown -->
	<section class="card">
		<h2>Where your money goes</h2>
		<div class="cost-grid">
			<div class="cost-group">
				<h3>Server costs <span class="cost-total">{fmtCurrency(serverCostTotal)}/mo</span></h3>
				{#each costs as c}
					<div class="cost-row">
						<span>{c.name}</span>
						<span class="cost-amount">{fmtCurrency(c.amount)}</span>
					</div>
				{/each}
			</div>
			<div class="cost-group">
				<h3>Development <span class="cost-total">{fmtCurrency(devCost)}/mo</span></h3>
				<div class="cost-row">
					<span>1 dedicated developer</span>
					<span class="cost-amount">{fmtCurrency(devCost)}</span>
				</div>
				<p class="cost-note">
					Full-time development: new features, bug fixes, platform
					updates, and keeping 5 app targets in sync.
				</p>
			</div>
		</div>
	</section>

	<!-- Donate buttons -->
	<section class="card">
		<h2>Contribute</h2>
		<div class="donate-grid">
			{#each donateOptions as d (d.id)}
				<button
					class="donate-btn"
					style="--accent: {d.color}"
					onclick={() => handleDonate(d.amount)}
					disabled={loading}
				>
					<span class="donate-icon">{d.icon}</span>
					<span class="donate-amount">{fmtCurrency(d.amount)}</span>
					<span class="donate-label">{d.label}</span>
				</button>
			{/each}
		</div>
		<p class="donate-note">
			Donations are one-time. No subscription, no recurring charge.
			<!-- TODO: Add links when payment is wired -->
			<!-- Also available on <a href="#">GitHub Sponsors</a> and <a href="#">Ko-fi</a>. -->
		</p>
	</section>

	<!-- All features free -->
	<section class="card">
		<h2>Everything is free</h2>
		<div class="feature-list">
			{#each features as f}
				<div class="feature-row">
					<span class="feature-check">✓</span>
					<span>{f}</span>
				</div>
			{/each}
		</div>
	</section>
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 48rem; }
	.page-header { margin-bottom: var(--space-xl); text-align: center; }
	h1 { font-size: 1.75rem; font-weight: 800; margin-bottom: var(--space-xs); }
	.subtitle { color: var(--color-text-secondary); font-size: 0.95rem; max-width: 36rem; margin: 0 auto; }
	h2 { font-size: 0.9rem; font-weight: 600; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: var(--space-lg); }
	h3 { font-size: 0.95rem; font-weight: 700; margin: 0 0 0.75rem; display: flex; align-items: center; gap: 0.5rem; }

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
		margin-bottom: var(--space-xl);
	}

	.funding-card { border-color: var(--color-primary); border-width: 1.5px; }

	.progress-section { margin-bottom: 1.25rem; }
	.progress-section:last-child { margin-bottom: 0; }
	.progress-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 0.4rem;
	}
	.progress-label { font-size: 0.88rem; font-weight: 600; }
	.progress-value { font-size: 0.82rem; color: var(--color-text-secondary); }
	.covered-badge {
		background: #2e7d32;
		color: white;
		font-size: 0.65rem;
		font-weight: 700;
		padding: 0.1rem 0.5rem;
		border-radius: 9999px;
		margin-left: 0.4rem;
		letter-spacing: 0.04em;
	}
	.progress-bar {
		height: 0.6rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		overflow: hidden;
	}
	.progress-fill {
		height: 100%;
		border-radius: 9999px;
		transition: width 0.5s ease;
	}
	.progress-fill.server { background: #2e7d32; }
	.progress-fill.total { background: var(--color-primary); }
	.progress-sub {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		margin-top: 0.3rem;
	}

	.cost-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }
	@media (max-width: 40rem) { .cost-grid { grid-template-columns: 1fr; } }
	.cost-group { }
	.cost-total { font-weight: 400; font-size: 0.82rem; color: var(--color-text-secondary); }
	.cost-row {
		display: flex;
		justify-content: space-between;
		padding: 0.35rem 0;
		font-size: 0.85rem;
		border-bottom: 1px solid var(--color-border);
	}
	.cost-row:last-of-type { border-bottom: none; }
	.cost-amount { font-weight: 600; font-variant-numeric: tabular-nums; }
	.cost-note { font-size: 0.78rem; color: var(--color-text-tertiary); margin-top: 0.5rem; line-height: 1.5; }

	.donate-grid {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 0.75rem;
		margin-bottom: 1rem;
	}
	@media (max-width: 40rem) { .donate-grid { grid-template-columns: repeat(2, 1fr); } }
	.donate-btn {
		--accent: var(--color-primary);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.4rem;
		padding: 1.25rem 0.75rem;
		border: 1.5px solid color-mix(in srgb, var(--accent) 35%, transparent);
		border-radius: var(--radius-lg);
		background: color-mix(in srgb, var(--accent) 8%, var(--color-surface));
		cursor: pointer;
		transition: all 0.2s ease;
	}
	.donate-btn:hover {
		border-color: var(--accent);
		background: color-mix(in srgb, var(--accent) 16%, var(--color-surface));
		box-shadow: 0 6px 24px color-mix(in srgb, var(--accent) 25%, transparent);
		transform: translateY(-2px);
	}
	.donate-btn:active {
		transform: translateY(0);
	}
	.donate-btn:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }
	.donate-icon { font-size: 1.5rem; }
	.donate-amount {
		font-size: 1.75rem;
		font-weight: 800;
		color: var(--accent);
	}
	.donate-label {
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		text-align: center;
		line-height: 1.4;
	}
	.donate-note { font-size: 0.78rem; color: var(--color-text-tertiary); }

	.feature-list { display: grid; grid-template-columns: 1fr 1fr; gap: 0.3rem 1.5rem; }
	@media (max-width: 40rem) { .feature-list { grid-template-columns: 1fr; } }
	.feature-row {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.35rem 0;
		font-size: 0.85rem;
	}
	.feature-check { color: #2e7d32; font-weight: 700; }
</style>
