<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '$lib/i18n/store.svelte';
	import { fetchEventClubSlug } from '$lib/core/data';

	let { data } = $props();
	let resolving = $state(true);

	// Stable-id event URL. The canonical event page is nested under its club's
	// slug, but the notification worker's row projection carries only event_id
	// (no join), so /events/{id} is the address every email + push CTA can
	// build — and it survives a club rename, which the nested URL does not.
	// Emails and push payloads already sent carry this shape too, so the route
	// has to keep resolving indefinitely.
	onMount(async () => {
		const slug = await fetchEventClubSlug(data.id);
		if (slug) {
			await goto(`/clubs/${slug}/events/${data.id}`, { replaceState: true });
			return;
		}
		resolving = false;
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
</svelte:head>

<div class="page">
	{#if resolving}
		<p class="muted">{m('shell.loading')}</p>
	{:else}
		<div class="empty-card">
			<img src="/logo-mark.svg" alt="" width="56" height="56" class="empty-mark" />
			<h3>{m('clubEvent.notFoundTitle')}</h3>
			<p class="muted">{m('clubEvent.notFoundBody')}</p>
			<a href="/clubs" class="btn btn-primary">{m('clubJoin.browseClubs')}</a>
		</div>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		text-align: center;
		padding: var(--space-2xl);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		max-width: 32rem;
		margin-inline: auto;
	}
	.empty-mark {
		opacity: 0.5;
	}
</style>
