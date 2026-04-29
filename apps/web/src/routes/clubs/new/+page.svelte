<script lang="ts">
	import { goto } from '$app/navigation';
	import ClubEditor from '$lib/components/ClubEditor.svelte';
</script>

<div class="page">
	<a class="back" href="/clubs">
		<span class="material-symbols">arrow_back</span>
		Back to clubs
	</a>
	<h1>Create a club</h1>
	<p class="sub">Set up a group for weekly long runs, a local chapter, or a training crew.</p>

	<ClubEditor
		oncreated={(club) => goto(`/clubs/${club.slug}`)}
		oncancel={() => history.back()}
	/>
</div>

<style>
	.page {
		max-width: 40rem;
		padding: var(--space-xl) var(--space-2xl);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
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
		margin: 0.35rem 0 var(--space-lg) 0;
	}
</style>
