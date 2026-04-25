<script lang="ts">
	import { goto } from '$app/navigation';
	import PlanEditor from '$lib/components/PlanEditor.svelte';
</script>

<div class="page">
	<a class="back" href="/plans">
		<span class="material-symbols">arrow_back</span>
		Back to plans
	</a>
	<h1>New plan</h1>
	<p class="sub">
		Pick a goal race and we'll schedule the phases, long runs, and quality sessions for you.
		The preview on the right updates as you type.
	</p>

	<PlanEditor
		oncreated={(plan) => goto(`/plans/${plan.id}`)}
		oncancel={() => history.back()}
	/>
</div>

<style>
	.page {
		max-width: 72rem;
		padding: var(--space-xl) var(--space-2xl);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 700;
	}
	.sub {
		color: var(--color-text-secondary);
		margin: 0.3rem 0 var(--space-lg) 0;
		max-width: 44rem;
	}
</style>
