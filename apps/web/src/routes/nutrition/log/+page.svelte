<script lang="ts">
	import { goto } from '$app/navigation';
	import FoodLogEditor from '$lib/components/FoodLogEditor.svelte';
	import { m } from '$lib/i18n/store.svelte';
</script>

<svelte:head><title>{m('nutrition.logHeading')} — Threkir</title></svelte:head>

<div class="page">
	<header class="page-head">
		<a class="back-link" href="/nutrition">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('nutrition.heading')}
		</a>
		<h1>{m('nutrition.logHeading')}</h1>
	</header>

	<FoodLogEditor oncreated={() => goto('/nutrition')} />
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 44rem;
	}
	.page-head { display: flex; flex-direction: column; gap: var(--space-xs); }
	.page-head h1 { margin: 0; }
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-weight: 500;
		text-decoration: none;
		align-self: flex-start;
	}
	.back-link:hover { color: var(--color-primary); }
	.back-link .material-symbols { font-size: 1.05rem; }
</style>
