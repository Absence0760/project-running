<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/mock-data';
	import { toGpx, toKml, downloadFile } from '$lib/gpx';
	import { fetchRouteById, getRouteReviews, upsertRouteReview, updateRouteTags } from '$lib/data';
	import { supabase } from '$lib/supabase';
	import { auth } from '$lib/stores/auth.svelte';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import type { Route } from '$lib/types';

	let { data } = $props();

	let route = $state<Route | null>(null);
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
		route = await fetchRouteById(data.id);
		loading = false;
		if (route) {
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
			alert(`Failed to submit review: ${e}`);
		}
	}

	let shareLink = $state('');
	let shareCopied = $state(false);
	let tagDraft = $state('');
	let tagsSaving = $state(false);

	let isOwner = $derived(route !== null && auth.user?.id === route.user_id);

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
			alert(`Could not save tag: ${e}`);
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
			alert(`Could not remove tag: ${e}`);
		} finally {
			tagsSaving = false;
		}
	}

	function handleExportGpx() {
		if (!route || !route.waypoints.length) return;
		const coords: [number, number][] = route.waypoints.map((w) => [w.lng, w.lat]);
		const eles = route.waypoints.map((w) => w.ele ?? 0);
		const gpx = toGpx(route.name, coords, eles);
		const filename = route.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.gpx';
		downloadFile(gpx, filename, 'application/gpx+xml');
	}

	function handleExportKml() {
		if (!route || !route.waypoints.length) return;
		const coords: [number, number][] = route.waypoints.map((w) => [w.lng, w.lat]);
		const eles = route.waypoints.map((w) => w.ele ?? 0);
		const kml = toKml(route.name, coords, eles);
		const filename = route.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '.kml';
		downloadFile(kml, filename, 'application/vnd.google-earth.kml+xml');
	}

	async function handleShare() {
		if (!route) return;
		// Make route public if it isn't already
		if (!route.is_public) {
			await supabase.from('routes').update({ is_public: true }).eq('id', route.id);
			route.is_public = true;
		}
		shareLink = `${window.location.origin}/share/route/${route.id}`;
		shareCopied = false;
	}

	async function copyShareLink() {
		await navigator.clipboard.writeText(shareLink);
		shareCopied = true;
		setTimeout(() => (shareCopied = false), 2000);
	}

	let elevations = $derived(route?.waypoints?.map((w) => w.ele ?? 0) ?? []);
</script>

{#if loading}
	<div class="page"><p class="loading">&nbsp;</p></div>
{:else if route}
	<div class="page">
		<a href="/routes" class="back-link">
			<span class="material-symbols">arrow_back</span>
			Routes
		</a>

		<header class="detail-header">
			<div>
				<h1>{route.name}</h1>
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
				<button class="btn btn-outline" onclick={handleExportGpx}>GPX</button>
				<button class="btn btn-outline" onclick={handleExportKml}>KML</button>
				<button class="btn btn-primary" onclick={handleShare}>Share</button>
			</div>
		</header>

		{#if shareLink}
			<div class="share-bar">
				<input type="text" readonly value={shareLink} />
				<button class="btn btn-outline" onclick={copyShareLink}>
					{shareCopied ? 'Copied!' : 'Copy'}
				</button>
			</div>
		{/if}

		{#if route.waypoints.length > 0}
			<div class="map-container">
				<RunMap track={route.waypoints} />
			</div>

			<section class="card">
				<h2>Elevation Profile</h2>
				<ElevationProfile {elevations} totalDistance={route.distance_m} />
			</section>
		{:else}
			<div class="map-container">
				<div class="map-placeholder">
					<span class="material-symbols">map</span>
					<p>No waypoint data available</p>
				</div>
			</div>
		{/if}

		<!-- Reviews -->
		<section class="card reviews-section">
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
	</div>
{/if}

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 56rem;
	}

	.loading {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-lg);
		transition: color var(--transition-fast);
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
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

	.actions {
		display: flex;
		gap: var(--space-sm);
	}

	.btn {
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		transition: all var(--transition-fast);
		cursor: pointer;
	}

	.btn-outline {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text);
	}

	.btn-outline:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
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

	.map-container {
		margin-bottom: var(--space-xl);
		height: 24rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
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

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
	}

	.reviews-section {
		margin-top: var(--space-xl);
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

	.btn-sm {
		padding: var(--space-xs) var(--space-md);
		font-size: 0.8rem;
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
</style>
