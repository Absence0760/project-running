<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import { routeSurfaceLabel } from '$lib/i18n/enum_labels.svelte';
	import { distanceInPreferred, formatElevation } from '$lib/format/units.svelte';
	import { fetchGlobalSegmentsWithError, type GlobalSegment } from '$lib/core/data';
	import {
		catalogueRegions,
		catalogueSurfaces,
		filterCatalogue,
		sortCatalogue,
		type CatalogueSort,
	} from '$lib/segments/catalogue_browse';

	let segments = $state<GlobalSegment[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	let query = $state('');
	let region = $state<string | null>(null);
	let surface = $state<string | null>(null);
	let sort = $state<CatalogueSort>('name');

	const SORTS: { value: CatalogueSort; key: MessageKey }[] = [
		{ value: 'name', key: 'segments.browseSortName' },
		{ value: 'shortest', key: 'segments.browseSortShortest' },
		{ value: 'longest', key: 'segments.browseSortLongest' },
		{ value: 'climb', key: 'segments.browseSortClimb' },
	];

	const regions = $derived(catalogueRegions(segments));
	const surfaces = $derived(catalogueSurfaces(segments));
	const shown = $derived(sortCatalogue(filterCatalogue(segments, { query, region, surface }), sort));
	const filtered = $derived(query.trim() !== '' || region != null || surface != null);

	// The catalogue is world-readable, so this page works signed out — no
	// auth.ready() gate, unlike the leaderboard on /segments/[id].
	async function load() {
		loading = true;
		loadError = null;
		try {
			const res = await fetchGlobalSegmentsWithError();
			if (res.error) {
				loadError = res.error;
				return;
			}
			segments = res.segments;
		} catch (e) {
			// A rejected fetch would otherwise leave `loading` false with an
			// empty list, which reads as "the catalogue is empty" — the exact
			// lie fetchGlobalSegmentsWithError's error contract exists to stop.
			loadError = e instanceof Error ? e.message : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function resetFilters() {
		query = '';
		region = null;
		surface = null;
		sort = 'name';
	}

	function fmtDist(metres: number | string): string {
		const { value, unit } = distanceInPreferred(Number(metres));
		return `${value.toFixed(2)} ${unit}`;
	}
</script>

<svelte:head><title>{m('segments.browseTitle')}</title></svelte:head>

<div class="catalogue">
	<header class="catalogue-header">
		<h1>{m('segments.browseTitle')}</h1>
		<p class="subtitle">{m('segments.browseIntro')}</p>
	</header>

	{#if loading}
		<p class="state-msg">{m('segments.loadingSegments')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert" data-testid="segment-catalogue-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('segments.browseFailed')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button type="button" class="btn btn-outline btn-sm" onclick={load}>
				{m('segmentDetail.retry')}
			</button>
		</div>
	{:else if segments.length === 0}
		<p class="state-msg" data-testid="segment-catalogue-empty">{m('segments.browseEmpty')}</p>
	{:else}
		<div class="filters">
			<label class="field search-field">
				<span>{m('segments.browseSearchLabel')}</span>
				<input
					type="search"
					bind:value={query}
					placeholder={m('segments.browseSearchPlaceholder')}
					data-testid="segment-catalogue-search"
				/>
			</label>
			{#if regions.length > 1}
				<label class="field">
					<span>{m('segments.browseRegion')}</span>
					<select bind:value={region} data-testid="segment-catalogue-region">
						<option value={null}>{m('segments.browseAllRegions')}</option>
						{#each regions as r (r)}
							<option value={r}>{r}</option>
						{/each}
					</select>
				</label>
			{/if}
			{#if surfaces.length > 1}
				<label class="field">
					<span>{m('segments.browseSurface')}</span>
					<select bind:value={surface} data-testid="segment-catalogue-surface">
						<option value={null}>{m('segments.browseAllSurfaces')}</option>
						{#each surfaces as s (s)}
							<option value={s}>{routeSurfaceLabel(s)}</option>
						{/each}
					</select>
				</label>
			{/if}
			<label class="field">
				<span>{m('segments.browseSort')}</span>
				<select bind:value={sort} data-testid="segment-catalogue-sort">
					{#each SORTS as option (option.value)}
						<option value={option.value}>{m(option.key)}</option>
					{/each}
				</select>
			</label>
			{#if filtered || sort !== 'name'}
				<button
					type="button"
					class="clear-btn"
					onclick={resetFilters}
					title={m('segments.clearFilters')}
					data-testid="segment-catalogue-reset"
				>
					{m('segments.reset')}
				</button>
			{/if}
		</div>

		{#if shown.length === 0}
			<p class="state-msg" data-testid="segment-catalogue-no-matches">
				{m('segments.browseNoMatches')}
			</p>
		{:else}
			<p class="count" role="status" data-testid="segment-catalogue-count">
				{m('segments.browseCount', { count: shown.length })}
			</p>
			<ul class="cards" data-testid="segment-catalogue-list">
				{#each shown as segment (segment.id)}
					<li>
						<a class="card" href="/segments/{segment.id}">
							<span class="card-name">{segment.name}</span>
							{#if segment.region}
								<span class="card-region">
									<span class="material-symbols" aria-hidden="true">place</span>
									{segment.region}
								</span>
							{/if}
							<span class="card-stats">
								<span class="stat">{fmtDist(segment.distance_m)}</span>
								{#if segment.elevation_m != null}
									<span class="stat">
										<span class="material-symbols" aria-hidden="true">altitude</span>
										{formatElevation(Number(segment.elevation_m))}
									</span>
								{/if}
								<span class="stat">{routeSurfaceLabel(segment.surface)}</span>
							</span>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

<style>
	.catalogue {
		max-width: 900px;
		margin: 0 auto;
		padding: var(--space-lg) var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.catalogue-header h1 {
		margin: 0 0 0.3rem;
		font-size: 1.4rem;
	}
	.subtitle {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.5;
	}
	.state-msg {
		margin: 0;
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: var(--color-danger-text);
		font-size: 1.3rem;
	}
	.filters {
		display: flex;
		flex-wrap: wrap;
		align-items: end;
		gap: var(--space-sm);
		padding: var(--space-sm);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-sm);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-secondary);
	}
	.search-field {
		flex: 1 1 14rem;
	}
	.field input,
	.field select {
		padding: 0.35rem 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-size: 0.85rem;
		color: var(--color-text);
		text-transform: none;
		letter-spacing: normal;
	}
	.field select {
		min-width: 9rem;
	}
	.clear-btn {
		padding: 0.35rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: transparent;
		font-size: 0.78rem;
		cursor: pointer;
		color: var(--color-text-secondary);
	}
	.clear-btn:hover {
		color: var(--color-primary);
		border-color: var(--color-primary);
	}
	.count {
		margin: 0;
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.cards {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(260px, 100%), 1fr));
		gap: var(--space-sm);
	}
	.card {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		height: 100%;
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		text-decoration: none;
		color: var(--color-text);
	}
	.card:hover {
		border-color: var(--color-primary);
	}
	.card-name {
		font-weight: 600;
	}
	.card-region,
	.card-stats {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 0.25rem;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
	}
	.card-stats {
		gap: 0.75rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.stat {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
	}
	.card-region .material-symbols,
	.stat .material-symbols {
		font-size: 0.95rem;
	}
</style>
