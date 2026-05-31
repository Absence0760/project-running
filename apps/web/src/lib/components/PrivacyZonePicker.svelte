<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import { env } from '$env/dynamic/public';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	import { mapStyleUrlFromEnv as mapStyleUrl } from '$lib/routes/map-style.svelte';
	import { watchMapResize } from '$lib/routes/map_resize';
	import type { PrivacyZone } from '$lib/routes/privacy';

	interface Props {
		oncreated: (zone: PrivacyZone) => void;
		oncancel: () => void;
	}
	let { oncreated, oncancel }: Props = $props();

	let mapEl: HTMLDivElement;
	let map: maplibregl.Map | null = null;
	let marker: maplibregl.Marker | null = null;
	let stopResizeWatch: (() => void) | null = null;

	let lat = $state<number | null>(null);
	let lng = $state<number | null>(null);
	let radius = $state(250);
	let geoBusy = $state(false);
	let geoError = $state<string | null>(null);

	onMount(() => {
		const prefersDark =
			typeof window !== 'undefined' &&
			window.matchMedia('(prefers-color-scheme: dark)').matches;

		map = new maplibregl.Map({
			container: mapEl,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: [-74.006, 40.7128],
			zoom: 13,
		});

		stopResizeWatch = watchMapResize(mapEl, map);

		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

		map.on('click', (e) => {
			setMarker(e.lngLat.lat, e.lngLat.lng);
		});

		map.on('load', () => {
			drawCircle();
		});
	});

	onDestroy(() => {
		stopResizeWatch?.();
		map?.remove();
		map = null;
	});

	function setMarker(nextLat: number, nextLng: number) {
		lat = nextLat;
		lng = nextLng;
		if (!map) return;
		if (!marker) {
			marker = new maplibregl.Marker({ color: '#dc2626', draggable: true })
				.setLngLat([nextLng, nextLat])
				.addTo(map);
			marker.on('dragend', () => {
				const ll = marker!.getLngLat();
				lat = ll.lat;
				lng = ll.lng;
				drawCircle();
			});
		} else {
			marker.setLngLat([nextLng, nextLat]);
		}
		drawCircle();
	}

	/// Render a translucent circle around the marker. Re-runs whenever
	/// lat/lng/radius change. Uses turf-style geometry but inline so we
	/// don't pull in another dependency.
	function drawCircle() {
		if (!map || !map.isStyleLoaded() || lat == null || lng == null) return;
		const points: [number, number][] = [];
		const steps = 64;
		const earthRadiusM = 6371000;
		const latRad = (lat * Math.PI) / 180;
		const dLat = (radius / earthRadiusM) * (180 / Math.PI);
		const dLng = ((radius / earthRadiusM) * (180 / Math.PI)) / Math.cos(latRad);
		for (let i = 0; i <= steps; i++) {
			const angle = (i / steps) * Math.PI * 2;
			points.push([lng + dLng * Math.cos(angle), lat + dLat * Math.sin(angle)]);
		}
		const data: GeoJSON.Feature<GeoJSON.Polygon> = {
			type: 'Feature',
			properties: {},
			geometry: { type: 'Polygon', coordinates: [points] },
		};

		const src = map.getSource('zone-circle') as maplibregl.GeoJSONSource | undefined;
		if (src) {
			src.setData(data);
		} else {
			map.addSource('zone-circle', { type: 'geojson', data });
			map.addLayer({
				id: 'zone-circle-fill',
				type: 'fill',
				source: 'zone-circle',
				paint: {
					'fill-color': '#dc2626',
					'fill-opacity': 0.18,
				},
			});
			map.addLayer({
				id: 'zone-circle-line',
				type: 'line',
				source: 'zone-circle',
				paint: {
					'line-color': '#dc2626',
					'line-width': 2,
				},
			});
		}
	}

	$effect(() => {
		// Re-render when radius changes.
		radius;
		drawCircle();
	});

	async function useCurrentLocation() {
		if (!navigator.geolocation) {
			geoError = 'Geolocation is not available in this browser.';
			return;
		}
		geoBusy = true;
		geoError = null;
		try {
			const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
				navigator.geolocation.getCurrentPosition(resolve, reject, {
					enableHighAccuracy: false,
					timeout: 10000,
				});
			});
			setMarker(pos.coords.latitude, pos.coords.longitude);
			map?.flyTo({ center: [pos.coords.longitude, pos.coords.latitude], zoom: 15 });
		} catch (e) {
			geoError =
				e instanceof GeolocationPositionError
					? 'Location access denied — enable it in your browser settings.'
					: `Could not get location: ${e}`;
		} finally {
			geoBusy = false;
		}
	}

	function save() {
		if (lat == null || lng == null) return;
		oncreated({ lat, lng, radius_m: radius });
	}
</script>

<div class="picker">
	<p class="hint">
		Click anywhere on the map (or use your current location) to set the centre, then drag the
		marker to fine-tune. Anything within the red circle will be hidden from public shares.
	</p>

	<div class="map" bind:this={mapEl}></div>

	<div class="controls">
		<button type="button" class="btn btn-outline" onclick={useCurrentLocation} disabled={geoBusy}>
			<span class="material-symbols">my_location</span>
			{geoBusy ? 'Locating…' : 'Use current location'}
		</button>

		<label class="radius">
			<span>Radius: <strong>{radius} m</strong></span>
			<input type="range" min="100" max="1000" step="50" bind:value={radius} />
		</label>
	</div>

	{#if geoError}
		<p class="error">{geoError}</p>
	{/if}

	<div class="actions">
		<button type="button" class="btn btn-outline" onclick={oncancel}>Cancel</button>
		<button type="button" class="btn btn-primary" onclick={save} disabled={lat == null}>
			Add zone
		</button>
	</div>
</div>

<style>
	.picker {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.hint {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}

	.map {
		height: 22rem;
		width: 100%;
		border-radius: var(--radius-md);
		overflow: hidden;
		border: 1px solid var(--color-border);
	}

	.controls {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md);
		align-items: center;
	}

	.controls .btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}

	.radius {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		min-width: 14rem;
	}

	.radius input {
		width: 100%;
	}

	.error {
		color: var(--color-danger, #ef4444);
		font-size: 0.85rem;
		margin: 0;
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
</style>
