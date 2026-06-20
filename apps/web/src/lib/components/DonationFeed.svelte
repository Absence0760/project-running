<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatPrice } from '$lib/format/format_price';
	import { formatRelativeTime } from '$lib/format/time';
	import type { FundraiserFeedEntry } from '$lib/types';

	let { entries }: { entries: FundraiserFeedEntry[] } = $props();

	function donorName(e: FundraiserFeedEntry): string {
		if (e.is_anonymous || !e.display_name) return m('fundraiser.anonymous');
		return e.display_name;
	}
</script>

<div class="donation-feed">
	{#if entries.length === 0}
		<p class="empty">{m('fundraiser.feedEmpty')}</p>
	{:else}
		<ul>
			{#each entries as e, i (i)}
				<li>
					<div class="row">
						<span class="name">{donorName(e)}</span>
						<span class="amount">{formatPrice(e.amount_cents / 100, { currency: e.currency.toUpperCase() })}</span>
					</div>
					{#if e.message}
						<p class="message">{e.message}</p>
					{/if}
					{#if e.paid_at}
						<time datetime={e.paid_at}>{formatRelativeTime(e.paid_at)}</time>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.donation-feed ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	li {
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border, #e5e7eb);
	}
	.row {
		display: flex;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.name {
		font-weight: 600;
	}
	.amount {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
	.message {
		margin: var(--space-2xs) 0 0;
		color: var(--color-text-muted, #6b7280);
	}
	time {
		font-size: 0.8rem;
		color: var(--color-text-muted, #6b7280);
	}
	.empty {
		color: var(--color-text-muted, #6b7280);
	}
</style>
