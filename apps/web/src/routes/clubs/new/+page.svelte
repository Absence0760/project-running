<script lang="ts">
	import { goto, afterNavigate } from '$app/navigation';
	import ClubEditor from '$lib/components/ClubEditor.svelte';

	let cameFromClubs = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromClubs || !from) return;
		if (from.url.pathname === '/clubs' || from.url.pathname.startsWith('/clubs?')) {
			cameFromClubs = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromClubs) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (cameFromClubs) history.back();
		else goto('/clubs');
	}
</script>

<svelte:head>
	<title>Create a club — Run Onward</title>
</svelte:head>

<div class="page">
	<a href="/clubs" class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		Back to clubs
	</a>

	<header class="page-header">
		<p class="kicker">New club</p>
		<h1>Create a club</h1>
		<p class="tagline">
			Set up a group for weekly long runs, a local chapter, or a training crew. Pick a visibility
			and join policy — you can change either later from the club's admin settings.
		</p>
	</header>

	<ClubEditor
		oncreated={(club) => goto(`/clubs/${club.slug}`)}
		oncancel={handleCancel}
	/>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 44rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
	.page-header {
		margin-bottom: var(--space-xl);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-2xs);
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		line-height: 1.2;
		margin: 0 0 var(--space-xs);
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 38rem;
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
