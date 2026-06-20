<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { englishBadge, type AchievementTier } from '$lib/social/badges';
	import { formatDateStable } from '$lib/share/share_meta';

	let { data } = $props();

	let resolved = $derived(
		data.badge ? englishBadge(data.badge.badge_key, data.badge.tier as AchievementTier) : null
	);
	let hasBadge = $derived(!!data.badge && !!resolved);
	let label = $derived(resolved?.label ?? '');
	let title = $derived(
		hasBadge ? m('badges.shareTitle', { badge: label }) : m('badges.section.title')
	);
	let description = $derived(resolved?.desc ?? m('badges.notFound'));
	let tier = $derived((data.badge?.tier ?? 'bronze') as AchievementTier);
	let earned = $derived(formatDateStable(data.badge?.earned_at ?? null));
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og/badge/{data.id}.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
</svelte:head>

<main class="share-badge">
	{#if hasBadge}
		<div class="badge-card tier-{tier}">
			<span class="badge-icon material-symbols" aria-hidden="true">{resolved?.icon}</span>
			<h1 class="badge-label">{label}</h1>
			<p class="badge-desc">{resolved?.desc}</p>
			<span class="badge-tier">{tier.toUpperCase()}</span>
			{#if data.displayName}
				<p class="badge-by">{data.displayName}</p>
			{/if}
			{#if earned}
				<p class="badge-date">{m('badges.earnedOn', { date: earned })}</p>
			{/if}
		</div>
	{:else}
		<div class="badge-card not-found">
			<span class="badge-icon material-symbols" aria-hidden="true">military_tech</span>
			<h1 class="badge-label">{m('badges.section.title')}</h1>
			<p class="badge-desc">{m('badges.notFound')}</p>
		</div>
	{/if}
	<a class="cta" href={auth.loggedIn ? '/dashboard' : '/'}>{m('badges.shareCta')}</a>
</main>

<style>
	.share-badge {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-lg);
		padding: var(--space-2xl);
		text-align: center;
	}
	.badge-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-xs);
		max-width: 28rem;
		padding: var(--space-2xl);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-top: 4px solid var(--tier-color, var(--color-border));
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
		font-size: 4rem;
		color: var(--tier-color, var(--color-text-secondary));
	}
	.badge-label {
		margin: 0;
		font-size: 1.75rem;
	}
	.badge-desc {
		margin: 0;
		color: var(--color-text-secondary);
	}
	.badge-tier {
		font-size: 0.75rem;
		letter-spacing: 0.06em;
		font-weight: 700;
		color: var(--tier-color, var(--color-text-secondary));
	}
	.badge-by {
		margin: var(--space-xs) 0 0;
		font-weight: 600;
	}
	.badge-date {
		margin: 0;
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}
	.cta {
		color: var(--color-primary);
		font-weight: 600;
	}
</style>
