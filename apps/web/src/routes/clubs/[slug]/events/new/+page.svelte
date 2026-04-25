<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { fetchClubBySlug } from '$lib/data';
	import EventEditor from '$lib/components/EventEditor.svelte';
	import type { ClubWithMeta } from '$lib/types';

	let slug = $derived($page.params.slug as string);
	let club = $state<ClubWithMeta | null>(null);
	let loading = $state(true);

	onMount(async () => {
		club = await fetchClubBySlug(slug);
		if (club?.viewer_role !== 'owner' && club?.viewer_role !== 'admin') {
			goto(`/clubs/${slug}`);
			return;
		}
		loading = false;
	});
</script>

{#if loading}
	<p class="centered muted">Loading…</p>
{:else if !club}
	<p class="centered muted">Club not found.</p>
{:else}
	<div class="page">
		<a class="back" href="/clubs/{slug}">
			<span class="material-symbols">arrow_back</span>
			Back to {club.name}
		</a>
		<h1>New event</h1>

		<EventEditor
			clubId={club.id}
			clubName={club.name}
			oncreated={(event) => goto(`/clubs/${slug}/events/${event.id}`)}
			oncancel={() => history.back()}
		/>
	</div>
{/if}

<style>
	.page {
		max-width: 64rem;
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
		margin-bottom: var(--space-md);
	}
	.centered {
		text-align: center;
		padding: var(--space-2xl);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
