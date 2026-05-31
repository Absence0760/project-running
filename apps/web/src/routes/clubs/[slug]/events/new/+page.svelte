<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { afterNavigate, goto } from '$app/navigation';
	import { fetchClubBySlug } from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import EventEditor from '$lib/components/EventEditor.svelte';
	import type { ClubWithMeta } from '$lib/types';

	let slug = $derived($page.params.slug as string);
	let club = $state<ClubWithMeta | null>(null);
	let loading = $state(true);

	let cameFromClub = $state(false);
	afterNavigate(({ from }) => {
		if (!cameFromClub && from?.url.pathname === `/clubs/${slug}`) {
			cameFromClub = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromClub) {
			e.preventDefault();
			history.back();
		}
	}

	onMount(async () => {
		// Wait for auth.user before resolving the club — fetchClubBySlug
		// derives `viewer_role` against the caller's identity. Without
		// this guard a fast page-load can hit the fetch while auth is
		// still hydrating, viewer_role comes back null even for the
		// real owner, and the admin-gate goto kicks them back to the
		// club page.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		club = await fetchClubBySlug(slug);
		// owner / admin / event_organiser may create events — the latter is a
		// delegated role the DB RLS (is_event_organiser) already permits. Gating
		// it out here was the sole blocker on the deep-linkable create route.
		const role = club?.viewer_role;
		if (role !== 'owner' && role !== 'admin' && role !== 'event_organiser') {
			goto(`/clubs/${slug}`);
			return;
		}
		loading = false;
	});
</script>

{#if loading}
	<div class="page" aria-busy="true" aria-label="Loading">
		<span class="back-skel" aria-hidden="true">
			<span class="material-symbols">arrow_back</span>
			Back to club
		</span>
		<div class="header-skel">
			<span class="skel skel-line skel-w-20"></span>
			<span class="skel skel-line skel-w-40"></span>
			<span class="skel skel-line skel-w-60"></span>
		</div>
		<div class="form-skel">
			<span class="skel skel-block"></span>
			<span class="skel skel-block tall"></span>
			<span class="skel skel-block"></span>
		</div>
	</div>
	<p class="sr-only" role="status">Loading…</p>
{:else if !club}
	<div class="page">
		<div class="empty-card">
			<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
			<h3>Club not found</h3>
			<p class="empty-text">
				This club may be private, or it may have been deleted.
			</p>
			<div class="empty-actions">
				<a href="/clubs" class="btn btn-primary">Back to clubs</a>
			</div>
		</div>
	</div>
{:else}
	<div class="page">
		<a class="back" href="/clubs/{slug}" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			Back to {club.name}
		</a>

		<header class="page-header">
			<span class="kicker">{club.name}</span>
			<h1>New event</h1>
			<p class="tagline">
				Every active member can RSVP to this event the moment you publish.
			</p>
		</header>

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
		text-decoration: none;
	}
	.back:hover { color: var(--color-primary); }
	.back .material-symbols { font-size: 1.05rem; }

	.page-header {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		margin-bottom: var(--space-lg);
	}
	.kicker {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 700;
		line-height: 1.15;
		margin: 0;
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		max-width: 44rem;
		margin: var(--space-2xs) 0 0 0;
	}

	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
	}
	.empty-card h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
	}
	.empty-mark {
		display: block;
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-sm);
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.empty-actions {
		display: flex;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}

	.back-skel {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		opacity: 0.5;
	}
	.header-skel {
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
		margin-bottom: var(--space-lg);
	}
	.form-skel {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line { height: 0.85rem; }
	.skel-block { height: 2.4rem; border-radius: var(--radius-md); }
	.skel-block.tall { height: 5.5rem; }
	.skel-w-20 { width: 20%; }
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
