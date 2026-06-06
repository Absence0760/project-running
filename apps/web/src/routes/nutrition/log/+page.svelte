<script lang="ts">
	import { goto } from '$app/navigation';
	import NutritionLogEditor from '$lib/components/NutritionLogEditor.svelte';
	import { m } from '$lib/i18n/store.svelte';

	// Standalone wrapper around NutritionLogEditor, kept so deep links and
	// browser back resolve (the create-flow modal pattern — apps/web/CLAUDE.md).
	// The canonical entry point is the modal on /nutrition; both exits return
	// to the day view.
	function back() {
		void goto('/nutrition');
	}
</script>

<svelte:head><title>{m('nutrition.logHeading')}</title></svelte:head>

<div class="page">
	<header class="page-header">
		<a class="back-link" href="/nutrition">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('nutrition.heading')}
		</a>
		<h1>{m('nutrition.logHeading')}</h1>
	</header>

	<NutritionLogEditor oncreated={back} oncancel={back} />
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 44rem;
	}
	.page-header { display: flex; flex-direction: column; gap: var(--space-xs); }
	.page-header h1 { margin: 0; }
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
