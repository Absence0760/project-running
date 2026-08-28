<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import GoalThermometer from './GoalThermometer.svelte';
	import type { Fundraiser, FundraiserTotals } from '$lib/types';

	let {
		fundraiser,
		totals,
		totalsFailed = false,
		compact = false
	}: {
		fundraiser: Fundraiser;
		totals: FundraiserTotals | null;
		/// The totals read FAILED, as distinct from `totals === null` meaning
		/// nothing has been donated yet. A thermometer at zero is a claim about
		/// someone else's campaign, so the failure gets said out loud instead.
		totalsFailed?: boolean;
		compact?: boolean;
	} = $props();

	const raised = $derived(totals?.raised_cents ?? 0);
	const goal = $derived(totals?.goal_cents ?? fundraiser.goal_cents);
	const donorCount = $derived(totals?.donor_count ?? 0);
	const closed = $derived(fundraiser.status === 'closed');

	function donate() {
		// The compact card hands off to the full fundraiser page, which hosts the
		// amount picker. A bare "Donate" here just routes there.
		window.location.href = `/fundraisers/${fundraiser.id}`;
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

	{#if totalsFailed}
		<p class="totals-error" role="alert" data-testid="fundraiser-card-totals-error">
			{m('fundraiser.totalsFailed')}
		</p>
	{:else}
		<GoalThermometer raisedCents={raised} goalCents={goal} {donorCount} currency={fundraiser.currency} />
	{/if}

	{#if closed}
		<p class="closed">{m('fundraiser.closed')}</p>
	{:else}
		<button type="button" class="btn btn-primary" onclick={donate}>
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
		color: var(--color-text-secondary);
	}
	.closed {
		color: var(--color-text-secondary);
		font-weight: 600;
	}
	.totals-error {
		margin: 0;
		color: var(--color-text-secondary);
	}
	.fundraiser-card.compact header h3 {
		font-size: 1rem;
	}
</style>
