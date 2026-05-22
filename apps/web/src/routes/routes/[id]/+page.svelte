<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { toGpx, toKml, downloadFile } from '$lib/gpx';
	import { fetchRouteById, getRouteReviews, upsertRouteReview, updateRouteTags, setRoutePublic, setRouteStar } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import SplitPane from '$lib/components/SplitPane.svelte';
	import SegmentsPanel from '$lib/components/SegmentsPanel.svelte';
	import ReportDialog from '$lib/components/ReportDialog.svelte';
	import RoutePreviewScrubber from '$lib/components/RoutePreviewScrubber.svelte';
	import { interpolateAlongRoute } from '$lib/route_geometry';
	import type { Route } from '$lib/types';

	let { data } = $props();

	let route = $state<Route | null>(null);
	// `fetchRouteById` returns owner-clipped waypoints for owners and
	// server-clipped waypoints for non-owners (via the public_routes
	// view + clip_route_for_viewer). The wire-leak is closed there;
	// the renderer just consumes what it gets.
	let displayWaypoints = $state<{ lat: number; lng: number; ele?: number }[]>([]);
	let loading = $state(true);
	let reviews = $state<any[]>([]);
	let showReviewForm = $state(false);
	let reviewRating = $state(4);
	let reviewComment = $state('');

	let avgRating = $derived(
		reviews.length > 0
			? (reviews.reduce((a: number, r: any) => a + r.rating, 0) / reviews.length).toFixed(1)
			: null,
	);

	onMount(async () => {
		// Wait for auth to resolve before fetching the row. Without
		// this, `isOwner` (a $derived from auth.user) starts false and
		// owner-only affordances (toggleStar, togglePublic, tag editor)
		// silently no-op on early clicks. Same poll-for-auth shape as
		// /runs/[id]; auth-store flips loading=false before fetchUser
		// resolves, so we have to wait for both. The 1s budget falls
		// through to the fetch regardless so anon visitors aren't
		// stalled when they hit a public route.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		route = await fetchRouteById(data.id);
		loading = false;
		if (route) {
			displayWaypoints = (route.waypoints ?? []) as typeof displayWaypoints;
			try {
				reviews = await getRouteReviews(route.id);
			} catch (_) {}
		}
	});

	async function submitReview() {
		if (!route) return;
		try {
			await upsertRouteReview({
				route_id: route.id,
				rating: reviewRating,
				comment: reviewComment.trim() || null,
			});
			reviews = await getRouteReviews(route.id);
			showReviewForm = false;
			reviewComment = '';
		} catch (e) {
			showToast(`Failed to submit review: ${e}`, 'error');
		}
	}

	let shareLink = $state('');
	let shareCopied = $state(false);
	let tagDraft = $state('');
	let tagsSaving = $state(false);

	let isOwner = $derived(route !== null && auth.user?.id === route.user_id);
	let showReportDialog = $state(false);

	async function addTag() {
		if (!route) return;
		const next = tagDraft.trim().toLowerCase();
		if (!next) return;
		if ((route.tags ?? []).includes(next)) {
			tagDraft = '';
			return;
		}
		const updated = [...(route.tags ?? []), next];
		tagsSaving = true;
		try {
			await updateRouteTags(route.id, updated);
			route.tags = updated;
			tagDraft = '';
		} catch (e) {
			showToast(`Could not save tag: ${e}`, 'error');
		} finally {
			tagsSaving = false;
		}
	}

	async function removeTag(tag: string) {
		if (!route) return;
		const updated = (route.tags ?? []).filter((t) => t !== tag);
		tagsSaving = true;
		try {
			await updateRouteTags(route.id, updated);
			route.tags = updated;
		} catch (e) {
			showToast(`Could not remove tag: ${e}`, 'error');
		} finally {
			tagsSaving = false;
		}
	}

	async function toggleStar() {
		if (!route || !isOwner) return;
		const next = !route.is_starred;
		// Optimistic — feels instant. Revert + toast on failure.
		route.is_starred = next;
		try {
			await setRouteStar(route.id, next);
		} catch (e) {
			route.is_starred = !next;
			showToast(`Could not ${next ? 'star' : 'unstar'} route: ${e}`, 'error');
		}
	}

	function handleExportGpx() {
		if (!route || !displayWaypoints.length) return;
		// Use displayWaypoints (clipped for non-owners) so a non-owner
		// download doesn't leak what the renderer hides.
		const coords: [number, number][] = displayWaypoints.map((w) => [w.lng, w.lat]);
		const eles = displayWaypoints.map((w) => w.ele ?? 0);
		const gpx = toGpx(route.name, coords, eles);
		const filename = route.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.gpx';
		downloadFile(gpx, filename, 'application/gpx+xml');
	}

	function handleExportKml() {
		if (!route || !displayWaypoints.length) return;
		const coords: [number, number][] = displayWaypoints.map((w) => [w.lng, w.lat]);
		const eles = displayWaypoints.map((w) => w.ele ?? 0);
		const kml = toKml(route.name, coords, eles);
		const filename = route.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.kml';
		downloadFile(kml, filename, 'application/vnd.google-earth.kml+xml');
	}

	async function handleShare() {
		if (!route) return;
		// Share requires the route to be publicly reachable. If the
		// owner hasn't flipped the visibility yet, flip it for them and
		// tell them what happened. Mirrors the one-tap Share-on-Android
		// flow, but we no longer silently conflate the two — a separate
		// public/private toggle below lets the owner revert.
		if (!route.is_public) {
			try {
				await setRoutePublic(route.id, true);
				route = { ...route, is_public: true };
				showToast('Route is now public so the link works.', 'info');
			} catch (e) {
				showToast(`Couldn't make public: ${e}`, 'error');
				return;
			}
		}
		shareLink = `${window.location.origin}/share/route/${route.id}`;
		shareCopied = false;
	}

	/// Bidirectional public/private toggle. Owner-only. Optimistic
	/// update with rollback on error — keeps the click snappy on a
	/// slow network while still being honest when the RLS write fails.
	async function togglePublic() {
		if (!route) return;
		const next = !route.is_public;
		// Optimistic flip so the icon changes immediately.
		route = { ...route, is_public: next };
		try {
			await setRoutePublic(route.id, next);
			showToast(next ? 'Route is now public.' : 'Route is private again.', 'success');
			// If we just made it private, clearing any prior share link
			// below the button avoids surfacing a dead URL.
			if (!next) {
				shareLink = '';
				shareCopied = false;
			}
		} catch (e) {
			// Roll back on failure so the UI matches reality.
			route = { ...route, is_public: !next };
			showToast(`Couldn't update visibility: ${e}`, 'error');
		}
	}


	async function copyShareLink() {
		await navigator.clipboard.writeText(shareLink);
		shareCopied = true;
		setTimeout(() => (shareCopied = false), 2000);
	}

	// Derive elevations from displayWaypoints (not route.waypoints
	// directly) so the chart's idx-space lines up with what the map
	// is actually drawing. Non-owners get a clipped polyline; their
	// chart idx → map marker must hit the same point on the clipped
	// trace, not the original.
	let elevations = $derived(displayWaypoints.map((w) => w.ele ?? 0));
	// Hide the elevation profile when waypoints have no real elevation
	// data (community routes imported without per-waypoint ele still
	// have a stored total gain in route.elevation_m). Without this guard
	// the chart renders as a flat line at zero, which looks broken next
	// to the non-zero "X m elevation gain" label.
	let hasElevationData = $derived(elevations.length > 1 && Math.max(...elevations) > Math.min(...elevations));

	/// Linked-cursor index — same shape as /runs/[id]. ElevationProfile
	/// onhover sets it; RunMap reads it.
	let chartHoverIdx = $state<number | null>(null);
	// Route-direction scrubber state. `scrubFraction` advances 0..1
	// as the user drags the slider; `scrubbing` toggles while the
	// thumb is under the finger so the preview marker only renders
	// during an active drag (fades back to the static polyline
	// view on release). Twin of the Flutter route-detail screen's
	// `_scrubFraction` + `_scrubbing` fields.
	let scrubFraction = $state(0);
	let scrubbing = $state(false);
	const previewLngLat = $derived.by<[number, number] | null>(() => {
		if (!scrubbing) return null;
		const interp = interpolateAlongRoute(
			displayWaypoints.map((w) => ({ lat: w.lat, lng: w.lng })),
			scrubFraction,
		);
		return interp ? [interp.lng, interp.lat] : null;
	});

	/// Per-waypoint elevation rollup. Walks once: total gain (sum of
	/// positive deltas), total loss (sum of negative deltas), and the
	/// min / max altitude. Used by the elevation summary tile above
	/// the chart.
	let elevationStats = $derived.by(() => {
		const eles = elevations;
		if (eles.length < 2 || !hasElevationData) {
			return { gain: 0, loss: 0, min: 0, max: 0 };
		}
		let gain = 0;
		let loss = 0;
		let min = eles[0];
		let max = eles[0];
		for (let i = 1; i < eles.length; i++) {
			const d = eles[i] - eles[i - 1];
			if (d > 0) gain += d;
			else loss += -d;
			if (eles[i] < min) min = eles[i];
			if (eles[i] > max) max = eles[i];
		}
		return {
			gain: Math.round(gain),
			loss: Math.round(loss),
			min: Math.round(min),
			max: Math.round(max),
		};
	});

	// Send the back link wherever the user came from. Defaults to /routes
	// (the owner's list); switches to the Explore tab when arriving from
	// community discovery so the trip back is one click, not two. Prefer
	// the explicit ?from=explore query param (set by RouteExplorer)
	// because document.referrer is unreliable across browsers and gets
	// stripped by some Referrer-Policy configurations.
	let backHref = $state('/routes');
	let backLabel = $state('Routes');
	onMount(() => {
		const fromParam = new URLSearchParams(window.location.search).get('from');
		const ref = typeof document !== 'undefined' ? document.referrer : '';
		const fromExplore =
			fromParam === 'explore' ||
			(ref && new URL(ref, window.location.origin).pathname.startsWith('/explore')) ||
			(ref && new URL(ref, window.location.origin).search.includes('tab=explore'));
		if (fromExplore) {
			backHref = '/routes?tab=explore';
			backLabel = 'Explore';
		}
	});
</script>

{#if loading}
	<div class="route-detail"><p class="loading">&nbsp;</p></div>
{:else if !route}
	<div class="route-detail">
		<a href="/routes" class="back-link page-back">
			<span class="material-symbols">arrow_back</span> Routes
		</a>
		<div class="not-found">
			<h1>Route not found</h1>
			<p>This route may have been deleted, or you may not have access to it.</p>
			<a href="/routes" class="btn btn-primary">Back to your routes</a>
		</div>
	</div>
{:else}
<div class="route-detail">
	<div class="route-detail-body">
	<!-- Panels-on-left convention (May 2026 UX pass): info pane on the
		 left, map dominant on the right. The fraction is the LEFT
		 pane width, so 0.35 is "info ≈ 35% of viewport, map ≈ 65%". -->
	<SplitPane storageKey="route-detail-split" min={300} initialFraction={0.35}>
		{#snippet left()}
		{#if route}
		<aside class="stats-panel">
			<a href={backHref} class="back-link panel-back">
				<span class="material-symbols">arrow_back</span>
				{backLabel}
			</a>
			<header class="detail-header">
				<div>
					<div class="title-row">
						<h1>{route.name}</h1>
						{#if isOwner}
							<button
								type="button"
								class="star-btn"
								class:starred={route.is_starred}
								title={route.is_starred ? 'Unstar route' : 'Star route — shows on watch'}
								aria-label={route.is_starred ? 'Unstar route' : 'Star route'}
								onclick={toggleStar}
							>
								<span class="material-symbols">star</span>
							</button>
						{/if}
					</div>
					<div class="route-meta">
						<span>{formatDistance(route.distance_m)}</span>
						{#if route.elevation_m}
							<span class="meta-sep">&middot;</span>
							<span>{route.elevation_m} m elevation gain</span>
						{/if}
						<span class="meta-sep">&middot;</span>
						<span class="surface-tag">{route.surface}</span>
						{#if route.run_count > 0}
							<span class="meta-sep">&middot;</span>
							<span>run {route.run_count} {route.run_count === 1 ? 'time' : 'times'}</span>
						{/if}
						{#if route.featured}
							<span class="featured-pill">★ Featured</span>
						{/if}
					</div>
					{#if route.description}
						<p class="route-description">{route.description}</p>
					{/if}
					{#if (route.tags && route.tags.length > 0) || isOwner}
						<div class="tags-row">
							{#each route.tags ?? [] as t (t)}
								<span class="tag-chip">
									{t}
									{#if isOwner}
										<button type="button" class="tag-x" aria-label="Remove tag {t}" onclick={() => removeTag(t)}>×</button>
									{/if}
								</span>
							{/each}
							{#if isOwner}
								<form class="tag-add" onsubmit={(e) => { e.preventDefault(); addTag(); }}>
									<input
										type="text"
										bind:value={tagDraft}
										placeholder="add tag"
										maxlength="24"
										disabled={tagsSaving}
									/>
								</form>
							{/if}
						</div>
					{/if}
				</div>
				<div class="actions">
					<button class="btn btn-outline btn-sm" onclick={handleExportGpx}>GPX</button>
					<button class="btn btn-outline btn-sm" onclick={handleExportKml}>KML</button>
					{#if isOwner}
						<button
							class="btn btn-outline btn-sm"
							onclick={togglePublic}
							title={route.is_public
								? 'Public — tap to make private'
								: 'Private — tap to make public'}
						>
							<span class="material-symbols">
								{route.is_public ? 'public' : 'public_off'}
							</span>
							{route.is_public ? 'Public' : 'Private'}
						</button>
					{/if}
					<button class="btn btn-primary btn-sm" onclick={handleShare}>Share</button>
					{#if !isOwner && auth.user}
						<button
							class="btn btn-outline btn-sm"
							onclick={() => (showReportDialog = true)}
							aria-label="Report this route"
							title="Report this route"
						>
							<span class="material-symbols" aria-hidden="true">flag</span>
						</button>
					{/if}
				</div>
			</header>

			{#if shareLink}
				<div class="share-bar">
					<input type="text" readonly value={shareLink} />
					<button class="btn btn-outline btn-sm" onclick={copyShareLink}>
						{shareCopied ? 'Copied!' : 'Copy'}
					</button>
				</div>
			{/if}

			<!-- Elevation summary — always rendered when the route stores
			     a non-zero gain. Per-waypoint min/max/loss are derived
			     from the elevations array; routes without per-point
			     elevation data fall back to the stored gain only. -->
			{#if route.elevation_m != null && route.elevation_m > 0}
				<section class="section">
					<h2>Elevation</h2>
					<div class="elev-grid">
						<div class="elev-tile">
							<span class="elev-label">
								<span class="material-symbols">trending_up</span>
								Gain
							</span>
							<span class="elev-value">
								{(hasElevationData ? elevationStats.gain : route.elevation_m)} m
							</span>
						</div>
						{#if hasElevationData}
							<div class="elev-tile">
								<span class="elev-label">
									<span class="material-symbols">trending_down</span>
									Loss
								</span>
								<span class="elev-value">{elevationStats.loss} m</span>
							</div>
							<div class="elev-tile">
								<span class="elev-label">
									<span class="material-symbols">terrain</span>
									Max
								</span>
								<span class="elev-value">{elevationStats.max} m</span>
							</div>
							<div class="elev-tile">
								<span class="elev-label">
									<span class="material-symbols">vertical_align_bottom</span>
									Min
								</span>
								<span class="elev-value">{elevationStats.min} m</span>
							</div>
						{/if}
					</div>
					{#if hasElevationData}
						<div class="elev-chart">
							<ElevationProfile
								{elevations}
								totalDistance={route.distance_m}
								onhover={(idx) => (chartHoverIdx = idx)}
							/>
						</div>
					{/if}
				</section>
			{/if}

			<section class="section">
				<SegmentsPanel
					routeId={route.id}
					routeDistanceM={route.distance_m}
					canCreate={auth.loggedIn}
				/>
			</section>

			<!-- Reviews -->
			<section class="section">
				<div class="reviews-header">
					<h2>
						Reviews
						{#if avgRating}
							<span class="avg-rating">({avgRating} / 5)</span>
						{/if}
					</h2>
					{#if auth.loggedIn}
						<button class="btn btn-outline btn-sm" onclick={() => showReviewForm = !showReviewForm}>
							{showReviewForm ? 'Cancel' : 'Rate'}
						</button>
					{/if}
				</div>

				{#if showReviewForm}
					<div class="review-form">
						<div class="star-row">
							{#each [1, 2, 3, 4, 5] as star}
								<button
									class="star-btn"
									class:filled={star <= reviewRating}
									onclick={() => reviewRating = star}
								>
									<span class="material-symbols">{star <= reviewRating ? 'star' : 'star_border'}</span>
								</button>
							{/each}
						</div>
						<textarea
							bind:value={reviewComment}
							placeholder="Comment (optional)"
							class="review-textarea"
							rows="2"
						></textarea>
						<button class="btn btn-primary btn-sm" onclick={submitReview}>Submit</button>
					</div>
				{/if}

				{#if reviews.length === 0}
					<p class="no-reviews">No reviews yet</p>
				{:else}
					{#each reviews as review}
						<div class="review-card">
							<div class="review-stars">
								{#each [1, 2, 3, 4, 5] as star}
									<span class="material-symbols star-display" class:filled={star <= review.rating}>
										{star <= review.rating ? 'star' : 'star_border'}
									</span>
								{/each}
								{#if review.created_at}
									<span class="review-date">{new Date(review.created_at).toLocaleDateString()}</span>
								{/if}
							</div>
							{#if review.comment}
								<p class="review-comment">{review.comment}</p>
							{/if}
						</div>
					{/each}
				{/if}
			</section>
		</aside>
		{/if}
		{/snippet}

		{#snippet right()}
			{#if route}
			<main class="map-panel">
				{#if displayWaypoints.length > 0}
					<RunMap
						track={displayWaypoints}
						totalDistanceM={route.distance_m}
						hoverIdx={chartHoverIdx}
						{previewLngLat}
					/>
					<RoutePreviewScrubber
						totalDistanceM={route.distance_m}
						fraction={scrubFraction}
						onchange={(f) => (scrubFraction = f)}
						onscrubbing={(active) => (scrubbing = active)}
					/>
				{:else}
					<div class="map-placeholder">
						<span class="material-symbols">map</span>
						<p>No waypoint data available</p>
					</div>
				{/if}
			</main>
			{/if}
		{/snippet}
	</SplitPane>
	</div>
</div>
{/if}

{#if route}
	<ReportDialog
		open={showReportDialog}
		targetKind="route"
		targetId={route.id}
		targetLabel={route.name ?? undefined}
		onclose={() => (showReportDialog = false)}
	/>
{/if}

<style>
	.route-detail {
		display: flex;
		flex-direction: column;
		height: 100vh;
	}

	.route-detail-body {
		display: flex;
		flex: 1;
		min-height: 0;
	}

	.page-back {
		padding: 0.6rem var(--space-lg);
		font-size: 0.9rem;
		font-weight: 500;
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}
	.page-back .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}

	/* In-panel back link — see the matching pattern in /runs/[id]. */
	.panel-back {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-text-tertiary);
		margin-bottom: var(--space-md);
		transition: color var(--transition-fast);
	}
	.panel-back:hover {
		color: var(--color-primary);
	}
	.panel-back .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1rem;
	}

	.map-panel {
		flex: 1;
		min-height: 0;
		background: var(--color-bg-tertiary);
		min-width: 0;
	}

	.stats-panel {
		flex: 1;
		min-height: 0;
		padding: var(--space-xl);
		overflow-y: auto;
		background: var(--color-surface);
		/* See /runs/[id] for the container-queries rationale —
		 * panel width is decoupled from viewport via SplitPane, so
		 * inner layouts respond to PANEL width. */
		container-type: inline-size;
		container-name: stats;
	}

	/*
	 * Container-query rules for narrow panel widths. The route
	 * detail surface is lighter than /runs/[id] (no splits table,
	 * no key-stats grid) but still has dense rows that need to
	 * relax: title + star button, meta-info inline strip, tags.
	 */
	@container stats (max-width: 380px) {
		.detail-header :global(.title-row) {
			flex-wrap: wrap;
		}
		.route-meta {
			gap: var(--space-xs);
		}
		.detail-header :global(h1) {
			font-size: 1.2rem;
		}
	}

	.loading {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}
	.not-found {
		text-align: center;
		padding: var(--space-2xl);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		color: var(--color-text-secondary);
	}
	.not-found h1 { color: var(--color-text); margin: 0; }

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		color: var(--color-text-secondary);
		transition: color var(--transition-fast);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}

	.title-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.star-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2rem;
		height: 2rem;
		padding: 0;
		background: transparent;
		border: none;
		border-radius: 50%;
		color: var(--color-text-tertiary);
		cursor: pointer;
		transition:
			background var(--transition-fast),
			color var(--transition-fast);
	}

	.star-btn:hover {
		background: var(--color-bg-tertiary);
	}

	.star-btn.starred {
		color: #fbbf24;
	}

	.star-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.4rem;
		font-variation-settings: 'FILL' 0;
		transition: font-variation-settings var(--transition-fast);
	}

	.star-btn.starred .material-symbols {
		font-variation-settings: 'FILL' 1;
	}

	h1 {
		font-size: 1.25rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}

	h2 {
		font-size: 0.85rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.section {
		margin-top: var(--space-xl);
	}

	.route-meta {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.route-description {
		margin: var(--space-sm) 0 0;
		color: var(--color-text-secondary);
		font-size: 0.92rem;
		line-height: 1.5;
		white-space: pre-wrap;
	}

	.actions {
		display: flex;
		gap: var(--space-xs);
		flex-wrap: wrap;
		justify-content: flex-end;
	}


	.share-bar {
		display: flex;
		gap: var(--space-sm);
		margin-bottom: var(--space-xl);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}

	.share-bar input {
		flex: 1;
		padding: var(--space-xs) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		background: var(--color-surface);
		font-family: 'SF Mono', 'Menlo', monospace;
	}

	.map-placeholder {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 100%;
		background: var(--color-bg-tertiary);
		color: var(--color-text-tertiary);
		gap: var(--space-sm);
	}

	.map-placeholder .material-symbols {
		font-size: 3rem;
	}

	.reviews-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}

	.avg-rating {
		font-size: 0.75rem;
		font-weight: 400;
		color: var(--color-text-tertiary);
		text-transform: none;
		letter-spacing: 0;
	}

	.review-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}

	.star-row {
		display: flex;
		gap: var(--space-xs);
	}

	.star-btn {
		background: none;
		border: none;
		cursor: pointer;
		padding: 0;
		color: var(--color-text-tertiary);
	}

	.star-btn.filled, .star-display.filled {
		color: #EAB308;
	}

	.star-display {
		font-size: 0.9rem;
		color: var(--color-text-tertiary);
	}

	.review-textarea {
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		font-size: 0.85rem;
		background: var(--color-surface);
		color: var(--color-text);
	}

	.no-reviews {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}

	.review-card {
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
	}

	.review-card:last-child {
		border-bottom: none;
	}

	.review-stars {
		display: flex;
		align-items: center;
		gap: 0.15rem;
	}

	.review-date {
		margin-left: var(--space-sm);
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}

	.review-comment {
		margin-top: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	.featured-pill {
		background: var(--color-primary);
		color: white;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		letter-spacing: 0.04em;
	}
	.tags-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		margin-top: 0.5rem;
	}
	.tag-chip {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		background: var(--color-bg-tertiary);
		color: var(--color-text);
		font-size: 0.78rem;
		padding: 0.15rem 0.55rem;
		border-radius: 9999px;
	}
	.tag-x {
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		font-size: 1rem;
		line-height: 1;
		padding: 0;
	}
	.tag-x:hover { color: var(--color-danger); }
	.tag-add input {
		padding: 0.15rem 0.55rem;
		border: 1px dashed var(--color-border);
		border-radius: 9999px;
		font-size: 0.78rem;
		background: transparent;
	}

	.elev-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.elev-tile {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		padding: 0.6rem 0.8rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}
	.elev-label {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.elev-label .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 0.95rem;
	}
	.elev-value {
		font-size: 1.05rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--color-text);
	}
	.elev-chart {
		margin-top: var(--space-sm);
	}
</style>
