<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';

	/// Persistent top-of-app banner that surfaces a recent
	/// `BILLING_ISSUE` event from RevenueCat — a renewal payment failed
	/// but the user still has Pro access during the store's grace
	/// period (~16 days App Store, up to 30 days Play). Cleared
	/// automatically when RC fires `RENEWAL` (payment recovered) or
	/// `EXPIRATION` / `CANCELLATION` (access ended).
	///
	/// Mounted on the root layout so it's visible on every authed
	/// page until resolved. Suppressed for free users who happen to
	/// have a stale flag (defence in depth — the EF clears the flag
	/// on EXPIRATION but a missed delivery shouldn't strand it).

	const since = $derived(auth.user?.billing_issue_at ?? null);
	const isProTier = $derived(auth.isPro);
	const visible = $derived(!!since && isProTier);

	function relativeDays(iso: string): string {
		const diffMs = Date.now() - new Date(iso).getTime();
		const days = Math.max(0, Math.floor(diffMs / 86400000));
		if (days === 0) return 'today';
		if (days === 1) return 'yesterday';
		return `${days} days ago`;
	}
</script>

{#if visible && since}
	<div class="banner" role="alert" data-testid="billing-issue-banner">
		<span class="material-symbols">credit_card_off</span>
		<div class="msg">
			<strong>Your Pro renewal payment failed {relativeDays(since)}.</strong>
			<span class="sub">
				Update your card before your grace period ends or you'll be
				downgraded to Free.
			</span>
		</div>
		<button class="cta" onclick={() => goto('/settings/upgrade')}>
			Manage subscription
		</button>
	</div>
{/if}

<style>
	.banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-xl);
		background: rgba(229, 57, 53, 0.08);
		border-bottom: 1px solid rgba(229, 57, 53, 0.25);
		color: var(--color-danger, #c1413f);
	}
	.material-symbols {
		font-size: 1.5rem;
		flex-shrink: 0;
	}
	.msg {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-width: 0;
		font-size: 0.95rem;
	}
	.msg .sub {
		color: var(--color-text-muted);
		font-size: 0.85rem;
	}
	.cta {
		flex-shrink: 0;
		padding: var(--space-xs) var(--space-md);
		background: var(--color-danger, #c1413f);
		color: white;
		border: none;
		border-radius: var(--radius-sm);
		font-size: 0.9rem;
		font-weight: 500;
		cursor: pointer;
	}
	.cta:hover {
		background: rgba(193, 65, 63, 0.85);
	}
</style>
