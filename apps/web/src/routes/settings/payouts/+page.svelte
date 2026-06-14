<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { fetchPayoutAccount, startConnectOnboarding, type PayoutAccountStatus } from '$lib/core/data';
	import { m } from '$lib/i18n/store.svelte';

	let account = $state<PayoutAccountStatus | null>(null);
	let loaded = $state(false);
	let redirecting = $state(false);

	// Onboarding started but not yet charges-enabled — Stripe still needs
	// more info. Restricted = onboarding submitted but charges disabled.
	let status = $derived.by<'none' | 'ready' | 'incomplete' | 'restricted'>(() => {
		if (!account) return 'none';
		if (account.charges_enabled) return 'ready';
		if (account.details_submitted) return 'restricted';
		return 'incomplete';
	});

	onMount(async () => {
		if (auth.user) {
			account = await fetchPayoutAccount();
		}
		loaded = true;
	});

	async function startSetup() {
		if (redirecting) return;
		redirecting = true;
		try {
			const { url } = await startConnectOnboarding();
			window.location.href = url;
		} catch (err) {
			// A build without Stripe Connect keys returns a 503
			// (events-connect-onboard fails closed). Treat that like the
			// upgrade page's not-configured fallback: an info toast, no
			// red error, page stays usable.
			const msg = err instanceof Error ? err.message : String(err);
			if (/not[_ ]configured|503/i.test(msg)) {
				showToast(m('payouts.notConfigured'), 'info');
			} else {
				showToast(m('payouts.setupFailed', { error: msg }), 'error');
			}
			redirecting = false;
		}
	}
</script>

<svelte:head>
	<title>{m('payouts.pageTitle')}</title>
</svelte:head>

<div class="page">
	<header class="hero">
		<p class="kicker">{m('shell.settings')}</p>
		<h1>{m('payouts.heroTitle')}</h1>
		<p class="tagline">{m('payouts.heroTagline')}</p>
	</header>

	<section class="card" aria-busy={!loaded}>
		{#if !loaded}
			<p class="muted">{m('payouts.redirecting')}</p>
		{:else if status === 'ready'}
			<div class="status status-ready" role="status">
				<span class="material-symbols" aria-hidden="true">check_circle</span>
				<span>{m('payouts.statusReady')}</span>
			</div>
			<p class="merchant-note">{m('payouts.merchantNote')}</p>
			<button class="btn btn-outline" onclick={startSetup} disabled={redirecting}>
				{redirecting ? m('payouts.redirecting') : m('payouts.manageDashboard')}
			</button>
		{:else if status === 'incomplete' || status === 'restricted'}
			<div class="status status-warn" role="status">
				<span class="material-symbols" aria-hidden="true">error</span>
				<span>
					{status === 'restricted'
						? m('payouts.statusRestricted')
						: m('payouts.statusIncomplete')}
				</span>
			</div>
			<button class="btn btn-primary" onclick={startSetup} disabled={redirecting}>
				{redirecting ? m('payouts.redirecting') : m('payouts.continueSetup')}
			</button>
		{:else}
			<p class="merchant-note">{m('payouts.merchantNote')}</p>
			<button class="btn btn-primary" onclick={startSetup} disabled={redirecting}>
				{redirecting ? m('payouts.redirecting') : m('payouts.setupCta')}
			</button>
		{/if}
	</section>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 48rem;
	}
	.hero {
		margin-bottom: var(--space-xl);
		max-width: 40rem;
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
		font-size: 1.7rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.15;
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.55;
		margin: 0;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		align-items: flex-start;
	}
	.status {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		font-weight: 600;
		font-size: 0.95rem;
	}
	.status .material-symbols {
		font-family: 'Material Symbols Outlined';
	}
	.status-ready {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.status-warn {
		color: var(--color-warning, var(--color-danger));
	}
	.merchant-note {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.muted {
		color: var(--color-text-tertiary);
		margin: 0;
	}
</style>
