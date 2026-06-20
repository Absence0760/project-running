<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { getCtaTarget } from '$lib/learn/categories';

	let { feature }: { feature?: string } = $props();

	const target = $derived(feature ? getCtaTarget(feature) : undefined);
</script>

<section class="learn-cta" aria-labelledby="learn-cta-heading">
	<h2 id="learn-cta-heading">{m('learn.articleCtaHeading')}</h2>
	<div class="learn-cta-actions">
		{#if target}
			<a class="btn btn-primary" href={target.route}>{m(target.labelKey)}</a>
		{/if}
		<a class="btn btn-outline" href="/login?signup=1">{m('learn.articleCtaSignup')}</a>
	</div>
</section>

<style>
	.learn-cta {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		padding: var(--space-lg);
		margin-top: var(--space-xl);
		text-align: center;
	}

	.learn-cta h2 {
		font-size: 1.2rem;
		font-weight: 700;
		margin: 0 0 var(--space-md);
		color: var(--color-text);
	}

	.learn-cta-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
</style>
