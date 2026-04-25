<script lang="ts">
	import { goto } from '$app/navigation';
	import RunEditor from '$lib/components/RunEditor.svelte';
</script>

<div class="page">
	<header class="page-header">
		<h1>Add a run</h1>
		<p class="subtitle">
			Manually enter a run you did without the app — a treadmill session,
			a race result from a chip timer, a trail run where GPS failed.
		</p>
	</header>

	<div class="card">
		<RunEditor
			oncreated={(run) => goto(`/runs/${run.id}`)}
			oncancel={() => goto('/runs')}
		/>
	</div>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 40rem;
	}
	h1 {
		font-size: 1.5rem;
		font-weight: 800;
		margin: 0 0 var(--space-xs);
	}
	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0 0 var(--space-xl);
		line-height: 1.5;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
	}
</style>
