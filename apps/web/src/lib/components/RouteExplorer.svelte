<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDistance } from '$lib/core/mock-data';
	import { getUnit } from '$lib/format/units.svelte';
	import {
		searchPublicRoutes,
		nearbyPublicRoutes,
		fetchPopularRouteTags,
		bookmarkRoute,
		unbookmarkRoute,
	} from '$lib/core/data';
	import type { Route } from '$lib/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { supabase } from '$lib/core/supabase';
	import { m as t } from '$lib/i18n/store.svelte';
	import RouteTrackPreview from './RouteTrackPreview.svelte';

	let routes = $state<Route[]>([]);
	let loading = $state(true);
	let hasMore = $state(true);
	let searchError = $state(false);
	let query = $state('');
	let distanceFilter = $state<string>('any');
	let surfaceFilter = $state<string>('any');
	let selectedTags = $state<Set<string>>(new Set());
	let popularTags = $state<string[]>([]);
	let featuredOnly = $state(false);
	let sort = $state<'newest' | 'popular' | 'featured'>('popular');
	let mode = $state<'search' | 'nearby'>('search');
	let locationError = $state<string | null>(null);
	let savedIds = $state<Set<string>>(new Set());

	const PAGE_SIZE = 30;

	// Bucket bounds are stored in metres (so the search RPC is
	// unit-agnostic), but the labels surface in the user's preferred
	// unit. Derived so a pref flip re-renders the dropdown options.
	// Thresholds map cleanly: 5/10/21 km ↔ 3/6/13 mi (the canonical
	// race ladder in each system).
	const distanceOptions = $derived.by(
		(): Record<string, { min?: number; max?: number; label: string }> => {
			if (getUnit() === 'mi') {
				const m = 1609.344;
				return {
					any: { label: t('routeExplorer.distanceAny') },
					short: { max: 3 * m, label: t('routeExplorer.distanceUnder3Mi') },
					medium: { min: 3 * m, max: 6 * m, label: t('routeExplorer.distance3to6Mi') },
					long: { min: 6 * m, max: 13 * m, label: t('routeExplorer.distance6to13Mi') },
					ultra: { min: 13 * m, label: t('routeExplorer.distance13MiPlus') },
				};
			}
			return {
				any: { label: t('routeExplorer.distanceAny') },
				short: { max: 5000, label: t('routeExplorer.distanceUnder5Km') },
				medium: { min: 5000, max: 10000, label: t('routeExplorer.distance5to10Km') },
				long: { min: 10000, max: 21000, label: t('routeExplorer.distance10to21Km') },
				ultra: { min: 21000, label: t('routeExplorer.distance21KmPlus') },
			};
		},
	);

	const surfaceOptions = $derived<Record<string, string>>({
		any: t('routeExplorer.surfaceAny'),
		road: t('routeExplorer.surfaceRoad'),
		trail: t('routeExplorer.surfaceTrail'),
		mixed: t('routeExplorer.surfaceMixed'),
	});

	function searchOptions(offset: number) {
		const opts = distanceOptions[distanceFilter];
		return {
			query: query.trim() || undefined,
			minDistanceM: opts?.min,
			maxDistanceM: opts?.max,
			surface: surfaceFilter === 'any' ? undefined : surfaceFilter,
			tags: selectedTags.size > 0 ? [...selectedTags] : undefined,
			featuredOnly,
			sort,
			limit: PAGE_SIZE,
			offset,
		};
	}

	async function search() {
		loading = true;
		try {
			routes = await searchPublicRoutes(searchOptions(0));
			hasMore = routes.length >= PAGE_SIZE;
			searchError = false;
		} catch (e) {
			searchError = true;
			showToast(t('routeExplorer.searchError', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			loading = false;
		}
	}

	async function loadMore() {
		if (loading || !hasMore) return;
		loading = true;
		try {
			const more = await searchPublicRoutes(searchOptions(routes.length));
			routes = [...routes, ...more];
			hasMore = more.length >= PAGE_SIZE;
		} catch (e) {
			showToast(t('routeExplorer.searchError', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			loading = false;
		}
	}

	function toggleTag(tag: string) {
		const next = new Set(selectedTags);
		if (next.has(tag)) next.delete(tag);
		else next.add(tag);
		selectedTags = next;
		search();
	}

	/// Bookmark a public route — inserts a `saved_routes` reference,
	/// not a private clone (decisions.md § 30). Tap again to unbookmark.
	///
	/// Persona-hunt Round 2 finding Casual #4: pre-fix two rapid
	/// taps both read `savedIds.has(route.id) === false` (the first
	/// call's await hadn't yet updated savedIds), each fired
	/// bookmarkRoute, the second was silently 23505-deduped, then a
	/// third tap actually un-bookmarked — net result was a save the
	/// user wanted, an un-bookmark they didn't, and a "Removed from
	/// your library" toast they didn't expect. The `bookmarkBusy` Set
	/// guard matches the SocialFeed.svelte / RunSocial.svelte kudos
	/// guards.
	let bookmarkBusy = $state(new Set<string>());

	async function toggleBookmark(route: Route) {
		if (!auth.loggedIn) return;
		if (bookmarkBusy.has(route.id)) return;
		bookmarkBusy = new Set([...bookmarkBusy, route.id]);
		const isSaved = savedIds.has(route.id);
		try {
			if (isSaved) {
				await unbookmarkRoute(route.id);
				const next = new Set(savedIds);
				next.delete(route.id);
				savedIds = next;
				showToast(t('routeExplorer.toastRemoved', { name: route.name ?? '' }));
			} else {
				await bookmarkRoute(route.id);
				savedIds = new Set([...savedIds, route.id]);
				showToast(t('routeExplorer.toastSaved', { name: route.name ?? '' }), 'success');
			}
		} catch (e) {
			showToast(t('routeExplorer.toastBookmarkError', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			const next = new Set(bookmarkBusy);
			next.delete(route.id);
			bookmarkBusy = next;
		}
	}

	async function loadSavedIds() {
		if (!auth.loggedIn) return;
		// Cap at a sane upper bound — this only feeds the bookmark-icon
		// state on visible cards, so we don't need every saved row.
		const { data } = await supabase.from('saved_routes').select('route_id').limit(1000);
		savedIds = new Set((data ?? []).map((r) => r.route_id as string));
	}

	async function searchNearby() {
		loading = true;
		locationError = null;
		routes = [];
		hasMore = false;
		try {
			const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
				navigator.geolocation.getCurrentPosition(resolve, reject, {
					enableHighAccuracy: false,
					timeout: 10000,
				});
			});
			routes = await nearbyPublicRoutes({
				lat: pos.coords.latitude,
				lng: pos.coords.longitude,
				radiusM: 50000,
				limit: 50,
			});
		} catch (e) {
			locationError = e instanceof GeolocationPositionError
				? t('routeExplorer.locationDenied')
				: t('routeExplorer.locationError', { error: e instanceof Error ? e.message : String(e) });
		}
		loading = false;
	}

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter') search();
	}

	function switchMode(newMode: 'search' | 'nearby') {
		mode = newMode;
		if (mode === 'nearby') searchNearby();
		else search();
	}

	onMount(async () => {
		popularTags = await fetchPopularRouteTags();
		loadSavedIds();
		search();
	});
</script>

<div class="explorer">
	<div class="mode-tabs">
		<button class="mode-tab" class:active={mode === 'search'} onclick={() => switchMode('search')}>
			<span class="material-symbols">search</span> {t('routeExplorer.tabSearch')}
		</button>
		<button class="mode-tab" class:active={mode === 'nearby'} onclick={() => switchMode('nearby')}>
			<span class="material-symbols">near_me</span> {t('routeExplorer.tabNearMe')}
		</button>
	</div>

	{#if locationError}
		<div class="location-error">
			<span class="material-symbols">location_off</span>
			<span>{locationError}</span>
		</div>
	{/if}

	{#if mode === 'search'}
	<div class="search-bar">
		<span class="material-symbols search-icon">search</span>
		<input
			type="text"
			placeholder={t('routeExplorer.searchPlaceholder')}
			bind:value={query}
			onkeydown={handleKeydown}
		/>
		{#if query}
			<button
				type="button"
				class="clear-btn"
				aria-label={t('routeExplorer.clearSearch')}
				onclick={() => { query = ''; search(); }}
			>
				<span class="material-symbols" aria-hidden="true">close</span>
			</button>
		{/if}
	</div>

	<div class="filters">
		<select aria-label={t('routeExplorer.filterDistance')} bind:value={distanceFilter} onchange={() => search()}>
			{#each Object.entries(distanceOptions) as [key, opt]}
				<option value={key}>{opt.label}</option>
			{/each}
		</select>
		<select aria-label={t('routeExplorer.filterSurface')} bind:value={surfaceFilter} onchange={() => search()}>
			{#each Object.entries(surfaceOptions) as [key, label]}
				<option value={key}>{label}</option>
			{/each}
		</select>
		<select aria-label={t('routeExplorer.filterSort')} bind:value={sort} onchange={() => search()}>
			<option value="popular">{t('routeExplorer.sortMostRun')}</option>
			<option value="newest">{t('routeExplorer.sortNewest')}</option>
			<option value="featured">{t('routeExplorer.sortFeatured')}</option>
		</select>
		<label class="chip-toggle">
			<input type="checkbox" bind:checked={featuredOnly} onchange={() => search()} />
			<span>{t('routeExplorer.featuredOnly')}</span>
		</label>
		<button class="btn btn-outline" onclick={() => search()}>{t('routeExplorer.searchButton')}</button>
	</div>

	{#if popularTags.length > 0}
		<div class="tag-row">
			{#each popularTags as tag (tag)}
				<button
					class="tag-chip"
					class:active={selectedTags.has(tag)}
					onclick={() => toggleTag(tag)}
				>
					{tag}
				</button>
			{/each}
		</div>
	{/if}
	{/if}

	{#if searchError && routes.length === 0}
		<div class="empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">error_outline</span>
			<h3>{t('routeExplorer.searchErrorTitle')}</h3>
			<div class="empty-actions">
				<button class="btn btn-primary" onclick={search}>{t('routeExplorer.searchErrorRetry')}</button>
			</div>
		</div>
	{/if}

	{#if routes.length === 0 && !loading && !searchError}
		<div class="empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">explore</span>
			<h3>{query ? t('routeExplorer.emptyNoMatch') : t('routeExplorer.emptyNone')}</h3>
			<p class="empty-text">
				{#if query}
					{t('routeExplorer.emptyQueryHint')}
				{:else if mode === 'nearby'}
					{t('routeExplorer.emptyNearbyHint')}
				{:else}
					{t('routeExplorer.emptyDefaultHint')}
				{/if}
			</p>
			<div class="empty-actions">
				<a href="/routes/new" class="btn btn-primary">
					<span class="material-symbols" aria-hidden="true">add</span>
					{t('routeExplorer.buildRoute')}
				</a>
				{#if query || selectedTags.size > 0 || distanceFilter !== 'any' || surfaceFilter !== 'any' || featuredOnly}
					<button
						type="button"
						class="btn btn-outline"
						onclick={() => {
							query = '';
							distanceFilter = 'any';
							surfaceFilter = 'any';
							selectedTags = new Set();
							featuredOnly = false;
							search();
						}}
					>
						{t('routeExplorer.clearFilters')}
					</button>
				{/if}
			</div>
		</div>
	{:else}
		<div class="route-grid">
			{#each routes as route}
				<div class="route-card">
					<a href="/routes/{route.id}?from=explore" class="route-link">
						<div class="route-map-placeholder">
							<!-- RouteTrackPreview lazy-fetches the clipped
								 polyline via the SECURITY DEFINER RPC
								 (decisions §33) so non-owner Explore viewers
								 see the route shape on a real tile background
								 instead of just a generic surface icon. The
								 surface icon stays as the fallback inside
								 RouteTrackPreview when the polyline fetch
								 fails or returns <2 points. -->
							<RouteTrackPreview
								routeId={route.id}
								waypoints={[]}
								ownerUserId={route.user_id}
							/>
							{#if route.is_featured}
								<span class="featured-badge" title={t('routeExplorer.featuredRoute')}>
									<span class="material-symbols">star</span>
								</span>
							{/if}
						</div>
						<div class="route-info">
							<h3>{route.name}</h3>
							<div class="route-meta">
								<span class="meta-item">
									<span class="material-symbols meta-icon">straighten</span>
									{formatDistance(route.distance_m)}
								</span>
								{#if route.elevation_m}
									<span class="meta-item">
										<span class="material-symbols meta-icon">trending_up</span>
										{route.elevation_m}m
									</span>
								{/if}
								<span class="meta-item">
									<span class="material-symbols meta-icon">{route.surface === 'trail' ? 'terrain' : 'add_road'}</span>
									<span class="surface-tag">{route.surface}</span>
								</span>
								{#if route.run_count > 0}
									<span class="meta-item">
										<span class="material-symbols meta-icon">directions_run</span>
										{route.run_count}
									</span>
								{/if}
							</div>
							{#if route.tags && route.tags.length > 0}
								<div class="card-tags">
									{#each route.tags.slice(0, 4) as t (t)}
										<span class="card-tag">{t}</span>
									{/each}
								</div>
							{/if}
						</div>
					</a>
					{#if auth.loggedIn}
						<button
							class="save-btn"
							class:saved={savedIds.has(route.id)}
							onclick={() => toggleBookmark(route)}
							disabled={bookmarkBusy.has(route.id)}
							title={savedIds.has(route.id) ? t('routeExplorer.removeFromLibrary') : t('routeExplorer.saveToLibrary')}
						>
							<span class="material-symbols">{savedIds.has(route.id) ? 'bookmark' : 'bookmark_add'}</span>
						</button>
					{/if}
				</div>
			{/each}
		</div>

		{#if hasMore}
			<div class="load-more">
				<button class="btn btn-outline" onclick={loadMore} disabled={loading}>
					{loading ? t('routeExplorer.loading') : t('routeExplorer.loadMore')}
				</button>
			</div>
		{/if}
	{/if}

	{#if loading && routes.length === 0}
		<div class="route-grid" aria-hidden="true">
			{#each Array(6) as _, i (i)}
				<div class="skel-card">
					<span class="skel skel-thumb"></span>
					<div class="skel-card-body">
						<span class="skel skel-line skel-w-60"></span>
						<span class="skel skel-line skel-w-40"></span>
					</div>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{t('routeExplorer.searchingStatus')}</p>
	{/if}
</div>

<style>
	.explorer {
		display: block;
	}

	.mode-tabs {
		display: flex;
		gap: var(--space-xs);
		margin-bottom: var(--space-md);
	}

	.mode-tab {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-sm) var(--space-lg);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.mode-tab:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.mode-tab.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: white;
	}

	.location-error {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		margin-bottom: var(--space-md);
		background: rgba(239, 68, 68, 0.1);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
		font-size: 0.85rem;
	}

	.search-bar {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		margin-bottom: var(--space-md);
	}

	.search-bar:focus-within {
		border-color: var(--color-primary);
	}

	.search-icon {
		color: var(--color-text-tertiary);
		font-size: 1.25rem;
	}

	.search-bar input {
		flex: 1;
		border: none;
		background: none;
		font-size: 0.9rem;
		color: var(--color-text);
		outline: none;
		padding: var(--space-xs) 0;
	}

	.clear-btn {
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0;
		display: flex;
	}

	.clear-btn:hover {
		color: var(--color-text);
	}

	.filters {
		display: flex;
		gap: var(--space-sm);
		margin-bottom: var(--space-lg);
		flex-wrap: wrap;
	}

	.filters select {
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.85rem;
		cursor: pointer;
	}

	.filters select:focus {
		border-color: var(--color-primary);
		outline: none;
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	.filters select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
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
		color: var(--color-text);
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
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
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}
	.empty-actions .material-symbols {
		font-size: 1.1rem;
	}

	/* Skeleton loader — same shimmer language as /routes + /runs.
	   Card layout mirrors the real route-card so the grid stays at its
	   true height through the data swap. */
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
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		pointer-events: none;
	}
	.skel-thumb {
		display: block;
		width: 100%;
		height: 8rem;
		border-radius: 0;
	}
	.skel-card-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md) var(--space-lg);
	}
	.skel-line {
		height: 0.75rem;
	}
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

	.route-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-md);
	}

	.route-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: all var(--transition-fast);
		position: relative;
	}

	.route-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.route-link {
		display: block;
	}

	.route-map-placeholder {
		height: 8rem;
		background: var(--color-bg-tertiary);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.route-map-placeholder .material-symbols {
		font-size: 2rem;
		color: var(--color-text-tertiary);
	}

	.route-info {
		padding: var(--space-md) var(--space-lg);
		padding-inline-end: 3rem;
	}

	h3 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: var(--space-xs);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.route-meta {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.meta-item {
		display: flex;
		align-items: center;
		gap: 0.2rem;
	}

	.meta-icon {
		font-size: 0.85rem;
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.save-btn {
		position: absolute;
		bottom: var(--space-md);
		inset-inline-end: var(--space-md);
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: var(--space-xs);
		border-radius: var(--radius-sm);
		transition: all var(--transition-fast);
	}

	.save-btn:hover {
		color: var(--color-primary);
		background: rgba(79, 70, 229, 0.1);
	}

	.save-btn.saved {
		color: var(--color-primary);
	}

	.load-more {
		text-align: center;
		padding: var(--space-xl);
	}

	.tag-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		margin-bottom: var(--space-lg);
	}
	.tag-chip {
		padding: 0.25rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.tag-chip:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.tag-chip.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: white;
	}
	.chip-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		font-size: 0.85rem;
		cursor: pointer;
	}
	.featured-badge {
		position: absolute;
		top: 0.5rem;
		inset-inline-end: 0.5rem;
		background: var(--color-primary);
		color: white;
		width: 1.6rem;
		height: 1.6rem;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.featured-badge .material-symbols {
		font-size: 1rem;
	}
	.route-map-placeholder {
		position: relative;
	}
	.card-tags {
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
		margin-top: 0.5rem;
	}
	.card-tag {
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		font-size: 0.72rem;
		padding: 0.1rem 0.45rem;
		border-radius: 9999px;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		font-style: normal;
		display: inline-block;
		line-height: 1;
		text-transform: none;
		letter-spacing: normal;
		word-wrap: normal;
		white-space: nowrap;
		direction: ltr;
		-webkit-font-smoothing: antialiased;
	}
</style>
