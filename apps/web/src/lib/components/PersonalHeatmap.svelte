<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv as mapStyleUrl } from '$lib/routes/map-style.svelte';
	import { watchMapResize } from '$lib/routes/map_resize';
	import { fetchRuns, fetchTrackByPath } from '$lib/core/data';
	import { buildHeatCells, heatBounds, toHeatGeoJSON, toTrackLinesGeoJSON, MAX_CELL_WEIGHT } from '$lib/routes/run_heatmap';
	import { hasAcceptedConsent } from '$lib/settings/consent.svelte';
	import type { TrackPoint } from '$lib/types';

	// Cap the number of tracks downloaded so a runner with thousands of
	// runs doesn't pull every blob on first paint. Newest-first; the
	// grid-quantising aggregation means older history past the cap adds
	// diminishing visual signal anyway. Concurrency bound keeps the
	// Storage fan-out polite.
	const MAX_TRACKS = 250;
	const DOWNLOAD_CONCURRENCY = 6;

	const SOURCE = 'personal-heat-src';
	const LAYER = 'personal-heat-layer';
	const LINE_SOURCE = 'personal-lines-src';
	const LINE_LAYER = 'personal-lines-layer';
	// Crossfade window (zoom levels): the heat cloud is fully opaque up to
	// FADE_MIN, then dissolves to nothing by FADE_MAX while the track lines
	// fade in over the same band — heatmaps thin out when you zoom in, so
	// past street level the precise paths read better than a fading blob.
	const FADE_MIN = 13;
	const FADE_MAX = 15.5;

	let mapEl: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let stopResizeWatch: (() => void) | null = null;
	let mapLoaded = false;

	let loading = $state(true);
	let trackCount = $state(0);
	let totalWithTracks = $state(0);
	let empty = $state(false);
	let errored = $state(false);
	// MapTiler logs the requester IP per tile fetch, so we never
	// instantiate maplibregl before the user has accepted the cookie
	// banner — including on this authenticated surface (audit/gdpr May
	// 2026 High: "implicit consent" for signed-in users is not a lawful
	// basis under ePrivacy Art 5(3)). Starts true only if consent is
	// already on record this session.
	let mapConsented = $state(hasAcceptedConsent());

	async function downloadTracks(paths: string[]): Promise<TrackPoint[][]> {
		const out: TrackPoint[][] = [];
		let cursor = 0;
		async function worker() {
			while (cursor < paths.length) {
				const i = cursor++;
				try {
					const t = (await fetchTrackByPath(paths[i])) as TrackPoint[];
					if (Array.isArray(t) && t.length > 0) {
						out.push(t);
						trackCount = out.length;
					}
				} catch (e) {
					// L4 best-effort — a single missing/corrupt blob must not
					// abort the whole heatmap. Skip and keep going.
					console.warn('heatmap: track download failed', e);
				}
			}
		}
		const workers = Array.from(
			{ length: Math.min(DOWNLOAD_CONCURRENCY, paths.length) },
			() => worker(),
		);
		await Promise.all(workers);
		return out;
	}

	async function build() {
		loading = true;
		empty = false;
		errored = false;
		try {
			const runs = await fetchRuns();
			const paths = runs
				.map((r) => (r as { track_url?: string | null }).track_url)
				.filter((p): p is string => typeof p === 'string' && p.length > 0)
				.slice(0, MAX_TRACKS);
			totalWithTracks = paths.length;
			if (paths.length === 0) {
				empty = true;
				return;
			}
			const tracks = await downloadTracks(paths);
			const cells = buildHeatCells(tracks);
			if (cells.length === 0) {
				empty = true;
				return;
			}
			const data = toHeatGeoJSON(cells);
			const lines = toTrackLinesGeoJSON(tracks);
			if (map && mapLoaded) {
				const src = map.getSource(SOURCE) as maplibregl.GeoJSONSource | undefined;
				src?.setData(data);
				const lineSrc = map.getSource(LINE_SOURCE) as maplibregl.GeoJSONSource | undefined;
				lineSrc?.setData(lines);
				const b = heatBounds(cells);
				if (b) {
					try {
						map.fitBounds(b, { padding: 48, maxZoom: 14, duration: 0 });
					} catch (e) {
						console.warn('heatmap: fitBounds failed', e);
					}
				}
			} else {
				pendingData = data;
				pendingLines = lines;
				pendingBounds = heatBounds(cells);
			}
		} catch (e) {
			console.error('personal heatmap build failed', e);
			// A thrown build means we never learned whether the runner has
			// mapped runs — surface a retryable error, NOT the "no runs yet"
			// empty state (which would tell an active runner they've never
			// run anywhere). If some tracks already rendered, keep them.
			if (trackCount === 0) errored = true;
		} finally {
			loading = false;
		}
	}

	// When the data resolves before the style's `load` fires, stash it
	// and apply on load.
	let pendingData: GeoJSON.FeatureCollection<GeoJSON.Point, { weight: number }> | null = null;
	let pendingLines: GeoJSON.FeatureCollection<GeoJSON.LineString> | null = null;
	let pendingBounds: [[number, number], [number, number]] | null = null;

	function loadMapNow() {
		mapConsented = true;
		initMap();
	}

	function initMap() {
		if (map) return;
		const prefersDark =
			typeof window !== 'undefined' &&
			window.matchMedia('(prefers-color-scheme: dark)').matches;

		map = new maplibregl.Map({
			container: mapEl,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: [0, 30],
			zoom: 1.5,
		});
		stopResizeWatch = watchMapResize(mapEl, map);

		requestAnimationFrame(() => {
			map?.resize();
			requestAnimationFrame(() => {
				map?.resize();
				setTimeout(() => map?.resize(), 100);
			});
		});

		if (import.meta.env.DEV && typeof window !== 'undefined') {
			(window as unknown as { __personalHeatmap?: unknown }).__personalHeatmap = map;
		}

		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

		map.on('load', () => {
			if (!map) return;
			mapLoaded = true;
			map.addSource(SOURCE, {
				type: 'geojson',
				data: pendingData ?? { type: 'FeatureCollection', features: [] },
			});
			map.addLayer({
				id: LAYER,
				type: 'heatmap',
				source: SOURCE,
				paint: {
					// Weight scales with how often the runner has passed through
					// a cell (clamped at MAX_CELL_WEIGHT in run_heatmap.ts).
					'heatmap-weight': [
						'interpolate',
						['linear'],
						['get', 'weight'],
						0, 0,
						MAX_CELL_WEIGHT, 1,
					],
					'heatmap-radius': [
						'interpolate',
						['linear'],
						['zoom'],
						6, 3,
						11, 7,
						14, 12,
						17, 18,
					],
					'heatmap-intensity': [
						'interpolate',
						['linear'],
						['zoom'],
						6, 0.5,
						14, 1.3,
					],
					'heatmap-color': [
						'interpolate',
						['linear'],
						['heatmap-density'],
						0, 'rgba(0,0,0,0)',
						0.2, 'rgba(59, 130, 246, 0.45)',
						0.4, 'rgba(16, 185, 129, 0.6)',
						0.6, 'rgba(245, 158, 11, 0.75)',
						1.0, 'rgba(239, 68, 68, 0.9)',
					],
					// Fade the heat cloud out as the track lines fade in, so
					// zooming past street level reveals the precise paths
					// instead of a dissolving blob.
					'heatmap-opacity': [
						'interpolate',
						['linear'],
						['zoom'],
						FADE_MIN, 0.85,
						FADE_MAX, 0,
					],
				},
			});

			// Track-line layer — the high-zoom half of the crossfade.
			// Drawn above the heat layer (invisible until ~FADE_MIN) so
			// once the cloud dissolves the runner sees their actual routes.
			map.addSource(LINE_SOURCE, {
				type: 'geojson',
				data: pendingLines ?? { type: 'FeatureCollection', features: [] },
			});
			map.addLayer({
				id: LINE_LAYER,
				type: 'line',
				source: LINE_SOURCE,
				layout: { 'line-join': 'round', 'line-cap': 'round' },
				paint: {
					'line-color': prefersDark ? '#818CF8' : '#4F46E5',
					'line-width': [
						'interpolate',
						['linear'],
						['zoom'],
						12, 1.5,
						16, 3,
						18, 4,
					],
					// Mirror image of the heatmap fade: invisible until
					// FADE_MIN, ramps in by FADE_MAX. Semi-transparent so
					// repeated routes visibly stack.
					'line-opacity': [
						'interpolate',
						['linear'],
						['zoom'],
						FADE_MIN, 0,
						FADE_MAX, 0.55,
					],
				},
			});
			if (pendingBounds) {
				try {
					map.fitBounds(pendingBounds, { padding: 48, maxZoom: 14, duration: 0 });
				} catch {
					/* world view fallback */
				}
			}
		});

		void build();
	}

	onMount(() => {
		// Only auto-init when consent is already on record; otherwise wait
		// for the "Load map" tap in the consent card below.
		if (mapConsented) initMap();
	});

	onDestroy(() => {
		if (import.meta.env.DEV && typeof window !== 'undefined') {
			(window as unknown as { __personalHeatmap?: unknown }).__personalHeatmap = undefined;
		}
		stopResizeWatch?.();
		map?.remove();
		map = null;
	});
</script>

<div class="heat-wrap" role="region" aria-label={m('personalHeatmap.regionLabel')}>
	<div bind:this={mapEl} class="map" data-testid="personal-heatmap-map"></div>

	{#if !mapConsented}
		<!--
			audit/gdpr (2026-05-31) High: MapTiler logs the requester IP
			per tile fetch. We don't auto-load the map on this signed-in
			surface — "Load map" is the affirmative act under ePrivacy
			Art 5(3) / GDPR Art 6(1)(a).
		-->
		<div class="heat-consent" data-testid="personal-heatmap-consent">
			<div class="heat-consent-card">
				<strong>{m('personalHeatmap.consentTitle')}</strong>
				<p>
					{m('personalHeatmap.consentBodyPrefix')} <strong>MapTiler</strong>{m('personalHeatmap.consentBodyMid')} <strong>{m('personalHeatmap.loadMap')}</strong> {m('personalHeatmap.consentBodyBeforeLink')}
					<a href="/cookie-notice">{m('personalHeatmap.cookieNoticeLink')}</a> {m('personalHeatmap.consentBodySuffix')}
				</p>
				<button type="button" class="btn btn-primary" onclick={loadMapNow}>
					{m('personalHeatmap.loadMap')}
				</button>
			</div>
		</div>
	{:else if loading}
		<div class="heat-status" data-testid="personal-heatmap-loading">
			<span class="spinner" aria-hidden="true"></span>
			{#if trackCount > 0}
				{m('personalHeatmap.loadingProgress', { n: trackCount, total: totalWithTracks })}
			{:else}
				{m('personalHeatmap.loading')}
			{/if}
		</div>
	{:else if errored}
		<div class="heat-empty" data-testid="personal-heatmap-error">
			<span class="material-symbols">cloud_off</span>
			<strong>{m('personalHeatmap.errorTitle')}</strong>
			<p>{m('personalHeatmap.errorBody')}</p>
			<button type="button" class="btn btn-primary" onclick={() => void build()}>
				{m('personalHeatmap.retry')}
			</button>
		</div>
	{:else if empty}
		<div class="heat-empty" data-testid="personal-heatmap-empty">
			<span class="material-symbols">local_fire_department</span>
			<strong>{m('personalHeatmap.emptyTitle')}</strong>
			<p>{m('personalHeatmap.emptyBody')}</p>
		</div>
	{:else}
		<aside class="heat-legend" data-testid="personal-heatmap-legend">
			<strong>{m('personalHeatmap.legendTitle')}</strong>
			<p>{trackCount === 1 ? m('personalHeatmap.legendSummaryOne', { n: trackCount }) : m('personalHeatmap.legendSummaryMany', { n: trackCount })}</p>
			<span class="legend-scale" aria-hidden="true"></span>
			<span class="legend-scale-labels"><span>{m('personalHeatmap.scaleLess')}</span><span>{m('personalHeatmap.scaleMore')}</span></span>
		</aside>
	{/if}
</div>

<style>
	.heat-wrap {
		position: relative;
		display: flex;
		flex-direction: column;
		height: 100%;
		min-height: 28rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
		border: 1px solid var(--color-border);
	}
	.map {
		flex: 1 1 auto;
		min-height: 0;
		width: 100%;
	}
	.heat-status {
		position: absolute;
		top: var(--space-md);
		inset-inline-start: var(--space-md);
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.5rem 0.8rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		font-size: 0.85rem;
		color: var(--color-text);
		z-index: 2;
	}
	.spinner {
		width: 14px;
		height: 14px;
		border: 2px solid var(--color-border);
		border-top-color: var(--color-primary);
		border-radius: 50%;
		animation: spin 0.8s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	.heat-consent {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-xl);
		background: var(--color-bg-secondary);
		z-index: 3;
	}
	.heat-consent-card {
		max-width: 28rem;
		text-align: center;
		padding: var(--space-lg) var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		color: var(--color-text);
	}
	.heat-consent-card strong {
		display: block;
		margin-bottom: var(--space-sm);
		font-size: 1.1rem;
	}
	.heat-consent-card p {
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
	}
	.heat-empty {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.4rem;
		text-align: center;
		padding: var(--space-xl);
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
		z-index: 2;
	}
	.heat-empty .material-symbols {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
	}
	.heat-empty strong {
		color: var(--color-text);
		font-size: 1.1rem;
	}
	.heat-empty p {
		margin: 0;
		max-width: 26rem;
	}
	.heat-legend {
		position: absolute;
		top: var(--space-md);
		inset-inline-start: var(--space-md);
		max-width: 14rem;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
		font-size: 0.82rem;
		color: var(--color-text);
		z-index: 2;
	}
	.heat-legend strong {
		display: block;
		margin-bottom: 0.2rem;
	}
	.heat-legend p {
		margin: 0 0 0.5rem;
		color: var(--color-text-secondary);
	}
	.legend-scale {
		display: block;
		height: 8px;
		border-radius: 999px;
		background: linear-gradient(
			90deg,
			rgba(59, 130, 246, 0.7),
			rgba(16, 185, 129, 0.8),
			rgba(245, 158, 11, 0.85),
			rgba(239, 68, 68, 0.95)
		);
	}
	.legend-scale-labels {
		display: flex;
		justify-content: space-between;
		font-size: 0.68rem;
		color: var(--color-text-tertiary);
		margin-top: 0.15rem;
	}
</style>
