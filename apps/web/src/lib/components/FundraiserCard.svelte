<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import GoalThermometer from './GoalThermometer.svelte';
	import { startDonationCheckout } from '$lib/core/data';
	import type { Fundraiser, FundraiserTotals } from '$lib/types';

	let {
		fundraiser,
		totals,
		compact = false
	}: {
		fundraiser: Fundraiser;
		totals: FundraiserTotals | null;
		compact?: boolean;
	} = $props();

	let donating = $state(false);

	const raised = $derived(totals?.raised_cents ?? 0);
	const goal = $derived(totals?.goal_cents ?? fundraiser.goal_cents);
	const donorCount = $derived(totals?.donor_count ?? 0);
	const closed = $derived(fundraiser.status === 'closed');

	async function donate() {
		// The compact card hands off to the full fundraiser page, which hosts the
		// amount picker. A bare "Donate" here just routes there.
		window.location.href = `/fundraisers/${fundraiser.id}`;
	}

	export async function donateAmount(
		amountCents: number,
		opts: { displayName?: string | null; message?: string | null; isAnonymous?: boolean }
	) {
		if (donating || closed) return;
		donating = true;
		try {
			const { url } = await startDonationCheckout(fundraiser.id, amountCents, opts);
			window.location.href = url;
		} catch (e) {
			showToast(m('fundraiser.donateFailed'), 'error');
			console.error('donation checkout failed', e);
			donating = false;
		}
	}
</script>

<section class="fundraiser-card" class:compact>
	<header>
		<h3>{fundraiser.title}</h3>
		<p class="charity">
			{#if fundraiser.charity_url}
				<a href={fundraiser.charity_url} target="_blank" rel="noopener noreferrer nofollow">{fundraiser.charity_name}</a>
			{:else}
				{fundraiser.charity_name}
			{/if}
		</p>
	</header>

	<GoalThermometer raisedCents={raised} goalCents={goal} {donorCount} currency={fundraiser.currency} />

	{#if closed}
		<p class="closed">{m('fundraiser.closed')}</p>
	{:else}
		<button type="button" class="btn btn-primary" onclick={donate} disabled={donating}>
			{m('fundraiser.donate')}
		</button>
	{/if}
</section>

<style>
	.fundraiser-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	header h3 {
		margin: 0;
	}
	.charity {
		margin: var(--space-2xs) 0 0;
		color: var(--color-text-muted, #6b7280);
	}
	.closed {
		color: var(--color-text-muted, #6b7280);
		font-weight: 600;
	}
	.fundraiser-card.compact header h3 {
		font-size: 1rem;
	}
</style>
