<script lang="ts" module>
	import type { DmRouteCard } from '$lib/social/dm_attachment';

	// Same bounded-LRU shape as RunTrackPreview / RouteTrackPreview. Keyed by
	// viewer as well as route: what `fetchRouteById` hands back IS the viewer's
	// own clipped view of the line, so a cache shared across a sign-out would
	// serve one reader another reader's clip.
	const CACHE_MAX = 100;
	const CACHE = new Map<string, DmRouteCard | null>();
	function cacheSet(key: string, value: DmRouteCard | null) {
		if (CACHE.size >= CACHE_MAX && !CACHE.has(key)) {
			const oldest = CACHE.keys().next().value;
			if (oldest !== undefined) CACHE.delete(oldest);
		}
		CACHE.set(key, value);
	}
</script>

<script lang="ts">
	import { onMount } from 'svelte';
	import TrackPreview from './TrackPreview.svelte';
	import { m as tr } from '$lib/i18n/store.svelte';
	import { formatDistance } from '$lib/format/units.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchRouteById } from '$lib/core/data';
	import {
		dmAttachmentView,
		dmRouteCardFrom,
		dmRouteCardHasTrace,
		type DmAttachmentResolution
	} from '$lib/social/dm_attachment';

	let { routeId }: { routeId: string } = $props();

	let resolution = $state<DmAttachmentResolution>({ status: 'pending' });

	const view = $derived(dmAttachmentView(routeId, resolution));

	onMount(() => {
		const key = `${auth.user?.id ?? 'anon'}:${routeId}`;
		if (CACHE.has(key)) {
			resolution = { status: 'resolved', route: CACHE.get(key) ?? null };
			return;
		}
		void (async () => {
			let route: DmRouteCard | null = null;
			try {
				// The one read path. fetchRouteById is owner-aware: the bare
				// `routes` table under RLS for the owner and active club members,
				// the `public_routes` view plus clip_route_for_viewer for everyone
				// else — so the polyline a non-owner recipient gets has already had
				// the sender's privacy zones removed server-side. Reading `routes`
				// directly here would hand the recipient the unclipped line.
				const row = await fetchRouteById(routeId);
				route = row ? dmRouteCardFrom(row) : null;
			} catch {
				// Fail closed to "unavailable" rather than to a bare body: a route
				// we could not resolve and a route the reader may not see are the
				// same answer as far as what may be claimed about it.
				route = null;
			}
			cacheSet(key, route);
			resolution = { status: 'resolved', route };
		})();
	});
</script>

{#if view.kind === 'pending'}
	<div class="attachment pending" aria-busy="true" data-testid="dm-route-attachment-pending">
		<span class="visually-hidden">{tr('shell.loading')}</span>
	</div>
{:else if view.kind === 'unavailable'}
	<p class="attachment unavailable" data-testid="dm-route-attachment-unavailable">
		{tr('messages.attachment.routeUnavailable')}
	</p>
{:else if view.kind === 'card'}
	{@const card = view.route}
	<a
		class="attachment card"
		href={`/routes/${card.id}`}
		data-testid="dm-route-attachment"
		data-route-id={card.id}
	>
		<span class="thumb">
			{#if dmRouteCardHasTrace(card)}
				<TrackPreview points={card.waypoints} aspect={1.6} />
			{:else}
				<span class="material-symbols placeholder" aria-hidden="true">map</span>
			{/if}
		</span>
		<span class="meta">
			<span class="eyebrow">{tr('messages.attachment.routeEyebrow')}</span>
			<strong class="name">{card.name ?? tr('messages.attachment.routeUntitled')}</strong>
			{#if card.distanceM !== null}
				<span class="distance">{formatDistance(card.distanceM)}</span>
			{/if}
		</span>
	</a>
{/if}

<style>
	.attachment {
		display: block;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		min-inline-size: 14rem;
	}
	.pending {
		block-size: 4.5rem;
		background: var(--color-bg-secondary);
	}
	.unavailable {
		margin: 0;
		padding: var(--space-sm);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.card {
		display: flex;
		align-items: stretch;
		gap: var(--space-sm);
		padding: var(--space-xs);
		color: inherit;
		text-decoration: none;
		overflow: hidden;
	}
	.card:hover {
		border-color: var(--color-primary);
	}
	.card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.thumb {
		inline-size: 5.5rem;
		block-size: 3.5rem;
		flex: 0 0 auto;
		border-radius: var(--radius-sm);
		background: var(--color-bg-secondary);
		display: grid;
		place-items: center;
		overflow: hidden;
	}
	.placeholder {
		font-family: 'Material Symbols Outlined';
		font-size: 1.25rem;
		color: var(--color-text-tertiary);
	}
	.meta {
		display: flex;
		flex-direction: column;
		justify-content: center;
		min-inline-size: 0;
		padding-inline-end: var(--space-xs);
	}
	.eyebrow {
		font-size: var(--font-size-section-label);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-secondary);
	}
	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.distance {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
</style>
