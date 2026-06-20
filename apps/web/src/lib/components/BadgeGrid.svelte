<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatDate } from '$lib/format/time';
	import { tierFor, type AchievementTier } from '$lib/social/badges';
	import type { Achievement } from '$lib/types';

	interface Props {
		badges: Achievement[];
		/** Owner view shows private badges + the visibility toggle + share. */
		isOwner?: boolean;
		onToggleVisibility?: (badge: Achievement) => void;
		onShare?: (badge: Achievement) => void;
	}

	let { badges, isOwner = false, onToggleVisibility, onShare }: Props = $props();

	const TIER_LABEL: Record<AchievementTier, () => string> = {
		bronze: () => m('badges.tier.bronze'),
		silver: () => m('badges.tier.silver'),
		gold: () => m('badges.tier.gold'),
		platinum: () => m('badges.tier.platinum')
	};

	function resolved(b: Achievement) {
		return tierFor(b.badge_key, b.tier as AchievementTier);
	}
</script>

{#if badges.length === 0}
	<p class="badges-empty">{isOwner ? m('badges.empty') : m('badges.emptyOther')}</p>
{:else}
	<ul class="badge-grid">
		{#each badges as b (b.id)}
			{@const r = resolved(b)}
			<li class="badge-tile tier-{b.tier}" class:is-private={!b.is_public}>
				<span class="badge-icon material-symbols" aria-hidden="true">{r?.icon ?? 'military_tech'}</span>
				<span class="badge-label">{r ? m(r.labelKey) : b.badge_key}</span>
				{#if r}
					<span class="badge-desc">{m(r.descKey)}</span>
				{/if}
				<span class="badge-tier">{TIER_LABEL[b.tier as AchievementTier]?.() ?? b.tier}</span>
				<span class="badge-date">{m('badges.earnedOn', { date: formatDate(b.earned_at) })}</span>
				{#if isOwner}
					<div class="badge-actions">
						<button
							type="button"
							class="badge-action"
							onclick={() => onToggleVisibility?.(b)}
						>
							{b.is_public ? m('badges.makePrivate') : m('badges.makePublic')}
						</button>
						{#if b.is_public}
							<button type="button" class="badge-action" onclick={() => onShare?.(b)}>
								{m('badges.share')}
							</button>
						{/if}
					</div>
					{#if !b.is_public}
						<span class="badge-private-flag">{m('badges.private')}</span>
					{/if}
				{/if}
			</li>
		{/each}
	</ul>
{/if}

<style>
	.badges-empty {
		color: var(--color-text-secondary);
		margin: var(--space-md) 0;
	}
	.badge-grid {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
		gap: var(--space-md);
	}
	.badge-tile {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: var(--space-2xs);
		padding: var(--space-lg) var(--space-md);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-top: 3px solid var(--tier-color, var(--color-border));
	}
	.badge-tile.is-private {
		opacity: 0.72;
	}
	.tier-bronze {
		--tier-color: #b08d57;
	}
	.tier-silver {
		--tier-color: #9aa3ad;
	}
	.tier-gold {
		--tier-color: #d4af37;
	}
	.tier-platinum {
		--tier-color: #7fd3e0;
	}
	.badge-icon {
		font-size: 2.5rem;
		color: var(--tier-color);
	}
	.badge-label {
		font-weight: 600;
	}
	.badge-desc {
		font-size: 0.8125rem;
		color: var(--color-text-secondary);
	}
	.badge-tier {
		font-size: 0.6875rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		font-weight: 700;
		color: var(--tier-color);
	}
	.badge-date {
		font-size: 0.75rem;
		color: var(--color-text-secondary);
	}
	.badge-actions {
		display: flex;
		gap: var(--space-xs);
		margin-top: var(--space-2xs);
		flex-wrap: wrap;
		justify-content: center;
	}
	.badge-action {
		background: none;
		border: none;
		padding: 0;
		font: inherit;
		font-size: 0.75rem;
		color: var(--color-primary);
		cursor: pointer;
		text-decoration: underline;
	}
	.badge-private-flag {
		position: absolute;
		top: var(--space-xs);
		right: var(--space-xs);
		font-size: 0.625rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-secondary);
	}
</style>
