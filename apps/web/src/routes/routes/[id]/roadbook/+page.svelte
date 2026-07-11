<script lang="ts">
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { fetchRouteById, fetchRouteMarkers } from '$lib/core/data';
	import type { Route, RouteMarker } from '$lib/types';
	import {
		buildRoadbook,
		type RoadbookWaypoint,
		type RoadbookMarker,
		type PacingModel,
		type CutoffStatus
	} from '$lib/routes/roadbook';
	import { kindSpec } from '$lib/routes/route_markers';
	import { toRouteGpxWithMarkers, type RouteGpxMarker } from '$lib/routes/route_gpx';
	import { downloadFile } from '$lib/routes/gpx';
	import {
		buildFuelPlan,
		DEFAULT_CARBS_PER_HOUR_G,
		DEFAULT_FLUID_PER_HOUR_ML,
		HEAT_FLUID_FACTOR
	} from '$lib/routes/fuel_plan';
	import { auth } from '$lib/stores/auth.svelte';
	import { loadSettings, effective } from '$lib/settings/settings';
	import { fetchElevations } from '$lib/routes/elevation';
	import { fmtSplitTime } from '$lib/runs/race_day';
	import { formatDistance, formatElevation } from '$lib/format/units.svelte';

	let { data }: { data: { id: string } } = $props();

	let route = $state<Route | null>(null);
	let markers = $state<RouteMarker[]>([]);
	let loading = $state(true);
	// The signed-in user's fueling-rate defaults (Settings → Preferences). The
	// roadbook can override these per-page via ?carbs= / ?fluid= (shareable),
	// falling back to these prefs, then the fuel_plan.ts constants when unset.
	let carbsPrefG = $state(DEFAULT_CARBS_PER_HOUR_G);
	let fluidPrefMl = $state(DEFAULT_FLUID_PER_HOUR_ML);
	// Open-Meteo elevations fetched on demand when the route lacks stored ele.
	let fetchedEle = $state<number[] | null>(null);
	let fetchingEle = $state(false);

	// Sensible starting goal until the user sets one: route distance at a
	// moderate trail pace. Editable; the URL is the source of truth.
	const DEFAULT_SEC_PER_KM = 390; // 6:30/km

	$effect(() => {
		void data.id;
		load();
	});

	async function load() {
		loading = true;
		route = await fetchRouteById(data.id);
		markers = route ? await fetchRouteMarkers(data.id) : [];
		await loadFuelPrefs();
		loading = false;
	}

	async function loadFuelPrefs() {
		await auth.ready();
		if (!auth.user) return;
		try {
			const settings = await loadSettings(auth.user.id);
			carbsPrefG = effective<number>(settings, 'carbs_per_hour', DEFAULT_CARBS_PER_HOUR_G) ?? DEFAULT_CARBS_PER_HOUR_G;
			fluidPrefMl = effective<number>(settings, 'fluid_per_hour', DEFAULT_FLUID_PER_HOUR_ML) ?? DEFAULT_FLUID_PER_HOUR_ML;
		} catch {
			// Keep the defaults — fueling figures are an auxiliary overlay.
		}
	}

	// ---- URL-backed controls (shareable) ----
	const params = $derived($page.url.searchParams);

	let goalSeconds = $derived.by(() => {
		// The `goal` param is raw seconds (the input below converts H:MM:SS → s).
		const raw = params.get('goal');
		const parsed = raw ? Number(raw) : NaN;
		if (Number.isFinite(parsed) && parsed > 0) return Math.round(parsed);
		const km = (route?.distance_m ?? 0) / 1000;
		return Math.max(60, Math.round(km * DEFAULT_SEC_PER_KM));
	});

	let startClockMin = $derived.by(() => {
		const raw = params.get('start');
		return raw ? parseClockToMinutes(raw) : null;
	});

	let model = $derived<PacingModel>(params.get('model') === 'even' ? 'even' : 'effort');

	// Fueling overlay — off by default. `?fuel=1` shows per-leg carbs + fluid;
	// `?heat=1` bumps fluid by the heat factor.
	let fuelOn = $derived(params.get('fuel') === '1');
	let heatOn = $derived(params.get('heat') === '1');

	// Effective intake rates: a per-page ?carbs= / ?fluid= override wins, then
	// the user's settings pref, then the fuel_plan.ts default.
	let carbsPerHourG = $derived.by(() => {
		const raw = params.get('carbs');
		const n = raw ? Number(raw) : NaN;
		return Number.isFinite(n) && n >= 0 ? n : carbsPrefG;
	});
	let fluidPerHourMl = $derived.by(() => {
		const raw = params.get('fluid');
		const n = raw ? Number(raw) : NaN;
		return Number.isFinite(n) && n >= 0 ? n : fluidPrefMl;
	});

	function updateParam(key: string, value: string | null) {
		const url = new URL($page.url);
		if (value == null || value === '') url.searchParams.delete(key);
		else url.searchParams.set(key, value);
		goto(`${url.pathname}${url.search}`, { replaceState: true, keepFocus: true, noScroll: true });
	}

	// ---- roadbook computation ----
	const waypoints = $derived.by<RoadbookWaypoint[]>(() => {
		const wps = route?.waypoints ?? [];
		return wps.map((w, i) => ({
			lat: w.lat,
			lng: w.lng,
			ele: w.ele ?? fetchedEle?.[i] ?? null
		}));
	});

	const roadbook = $derived(
		buildRoadbook(
			waypoints,
			markers.map(
				(mk): RoadbookMarker => ({
					position_m: mk.position_m,
					kind: mk.kind,
					label: mk.label,
					meta: mk.meta
				})
			),
			{ goalSeconds, startClockMin, model }
		)
	);

	const fuel = $derived(
		buildFuelPlan(roadbook.legs, {
			carbsPerHourG,
			fluidPerHourMl,
			heatFactor: heatOn ? HEAT_FLUID_FACTOR : 1
		})
	);

	async function addElevation() {
		if (!route || fetchingEle) return;
		fetchingEle = true;
		try {
			const coords = route.waypoints.map((w) => [w.lng, w.lat] as [number, number]);
			const eles = await fetchElevations(coords);
			if (eles.length === coords.length && eles.some((e) => e !== 0)) {
				fetchedEle = eles;
			} else {
				showToast(m('roadbook.elevationUnavailable'), 'info');
			}
		} catch {
			showToast(m('roadbook.elevationUnavailable'), 'info');
		} finally {
			fetchingEle = false;
		}
	}

	function checkpointLabel(leg: (typeof roadbook)['legs'][number]): string {
		if (leg.checkpoint === 'start') return m('roadbook.start');
		if (leg.checkpoint === 'finish') return m('roadbook.finish');
		return leg.checkpoint.label;
	}

	function checkpointColor(leg: (typeof roadbook)['legs'][number]): string {
		if (leg.checkpoint === 'start') return '#22c55e';
		if (leg.checkpoint === 'finish') return '#ef4444';
		return kindSpec(leg.checkpoint.kind).color;
	}

	function cutoffClass(status: CutoffStatus): string {
		return status === 'miss' ? 'cut-miss' : status === 'tight' ? 'cut-tight' : 'cut-safe';
	}

	function fmtMargin(seconds: number): string {
		const sign = seconds < 0 ? '−' : '+';
		return `${sign}${fmtSplitTime(Math.abs(seconds))}`;
	}

	function fmtClock(min: number | undefined): string {
		if (min == null) return '';
		const h = Math.floor(min / 60) % 24;
		const mm = Math.round(min % 60);
		return `${String(h).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
	}

	function parseClockToSeconds(raw: string): number | null {
		const parts = raw.split(':').map((p) => Number(p));
		if (parts.some((n) => !Number.isFinite(n))) return null;
		if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
		if (parts.length === 2) return parts[0] * 3600 + parts[1] * 60;
		return null;
	}

	function parseClockToMinutes(raw: string): number | null {
		const parts = raw.split(':').map((p) => Number(p));
		if (parts.length < 2 || parts.some((n) => !Number.isFinite(n))) return null;
		return parts[0] * 60 + parts[1];
	}

	// Goal input bound as H:MM:SS.
	let goalInput = $derived(fmtSplitTime(goalSeconds));
	let startInput = $derived(startClockMin == null ? '' : fmtClock(startClockMin));

	function onGoalChange(e: Event) {
		const v = (e.currentTarget as HTMLInputElement).value.trim();
		const secs = parseClockToSeconds(v);
		updateParam('goal', secs && secs > 0 ? String(secs) : null);
	}

	async function copyAsText() {
		const lines = [`${route?.name ?? m('roadbook.heading')} — ${m('roadbook.heading')}`, ''];
		lines.push(`${m('roadbook.colCheckpoint')} | ${m('roadbook.colDistance')} | ${m('roadbook.colArrival')} | ${m('roadbook.colCutoff')}`);
		for (const leg of roadbook.legs) {
			const cut = leg.cutoff
				? `${
						startClockMin != null
							? fmtClock(startClockMin + leg.cutoff.limitElapsedS / 60)
							: fmtSplitTime(leg.cutoff.limitElapsedS)
					} ${fmtMargin(leg.cutoff.marginS)}`
				: '';
			lines.push(
				`${checkpointLabel(leg)} | ${formatDistance(leg.cumDistM)} | ${fmtSplitTime(leg.projectedElapsedS)}${leg.projectedClockMin != null ? ` (${fmtClock(leg.projectedClockMin)})` : ''} | ${cut}`
			);
		}
		try {
			await navigator.clipboard.writeText(lines.join('\n'));
			showToast(m('roadbook.copied'), 'success');
		} catch {
			showToast(m('roadbook.copyFailed'), 'error');
		}
	}

	function serviceLabel(s: string): string {
		return m(`routeMarker.service.${s}` as 'routeMarker.service.water');
	}

	function handleExportGpxWithMarkers() {
		if (!route) return;
		const wps = route.waypoints ?? [];
		if (!wps.length) return;
		const coords: [number, number][] = wps.map((w) => [w.lng, w.lat]);
		const eles = wps.map((w, i) => w.ele ?? fetchedEle?.[i] ?? 0);
		const gpxMarkers: RouteGpxMarker[] = markers.map((mk) => ({
			label: mk.label,
			lat: mk.lat,
			lng: mk.lng,
			kind: mk.kind,
			meta: mk.meta
		}));
		const gpx = toRouteGpxWithMarkers(route.name, coords, eles, gpxMarkers);
		const filename =
			route.name.replace(/[^a-zA-Z0-9-_ ]/g, '').replace(/\s+/g, '_') + '_with_markers.gpx';
		downloadFile(gpx, filename, 'application/gpx+xml');
	}
</script>

<svelte:head>
	<title>{route ? `${route.name} — ${m('roadbook.heading')}` : m('roadbook.heading')}</title>
</svelte:head>

<div class="roadbook-page">
	{#if loading}
		<p class="muted">{m('roadbook.loading')}</p>
	{:else if !route}
		<p class="muted">{m('roadbook.routeNotFound')}</p>
	{:else}
		<header class="rb-header">
			<div>
				<a class="back" href={`/routes/${route.id}`}>← {route.name}</a>
				<h1>{m('roadbook.heading')}</h1>
			</div>
			<div class="rb-actions no-print">
				{#if markers.length > 0}
					<button class="btn btn-secondary btn-sm" onclick={handleExportGpxWithMarkers}>
						<span class="material-symbols" aria-hidden="true">download</span>
						{m('routeDetail.exportGpxMarkers')}
					</button>
				{/if}
				<button class="btn btn-secondary btn-sm" onclick={copyAsText}>
					<span class="material-symbols" aria-hidden="true">content_copy</span>
					{m('roadbook.copy')}
				</button>
				<button class="btn btn-secondary btn-sm" onclick={() => window.print()}>
					<span class="material-symbols" aria-hidden="true">print</span>
					{m('roadbook.print')}
				</button>
			</div>
		</header>

		<section class="rb-controls no-print">
			<label>
				{m('roadbook.goalTime')}
				<input
					type="text"
					inputmode="numeric"
					value={goalInput}
					placeholder="4:30:00"
					onchange={onGoalChange}
				/>
			</label>
			<label>
				{m('roadbook.startTime')}
				<input
					type="time"
					value={startInput}
					onchange={(e) => updateParam('start', (e.currentTarget as HTMLInputElement).value || null)}
				/>
			</label>
			<div class="model-toggle" role="group" aria-label={m('roadbook.pacingModel')}>
				<button class:active={model === 'effort'} onclick={() => updateParam('model', 'effort')}>
					{m('roadbook.modelEffort')}
				</button>
				<button class:active={model === 'even'} onclick={() => updateParam('model', null)}>
					{m('roadbook.modelEven')}
				</button>
			</div>
			<div class="model-toggle" role="group" aria-label={m('roadbook.fuel')}>
				<button
					class:active={fuelOn}
					aria-pressed={fuelOn}
					onclick={() => updateParam('fuel', fuelOn ? null : '1')}
				>
					{m('roadbook.fuel')}
				</button>
				{#if fuelOn}
					<button
						class:active={heatOn}
						aria-pressed={heatOn}
						onclick={() => updateParam('heat', heatOn ? null : '1')}
					>
						{m('roadbook.heat')}
					</button>
				{/if}
			</div>
		</section>

		{#if markers.length === 0}
			<p class="muted empty">{m('roadbook.noMarkers')} <a href={`/routes/${route.id}`}>{m('roadbook.addMarkers')}</a></p>
		{:else}
			<p class="rb-summary">
				{m('roadbook.summary', {
					distance: formatDistance(roadbook.totalDistM),
					vert: formatElevation(roadbook.totalGainM),
					time: fmtSplitTime(roadbook.totalSeconds)
				})}
				{#if model === 'effort' && !roadbook.hasElevation}
					<button class="link-btn no-print" onclick={addElevation} disabled={fetchingEle}>
						{fetchingEle ? m('roadbook.addingElevation') : m('roadbook.addElevation')}
					</button>
				{/if}
			</p>

			<table class="rb-table">
				<thead>
					<tr>
						<th>{m('roadbook.colCheckpoint')}</th>
						<th class="num">{m('roadbook.colDistance')}</th>
						<th class="num">{m('roadbook.colVert')}</th>
						<th class="num">{m('roadbook.colArrival')}</th>
						<th>{m('roadbook.colCutoff')}</th>
						{#if fuelOn}
							<th class="num">{m('roadbook.colCarbs')}</th>
							<th class="num">{m('roadbook.colFluid')}</th>
						{/if}
						<th class="no-print">{m('roadbook.colServices')}</th>
					</tr>
				</thead>
				<tbody>
					{#each roadbook.legs as leg, i (i)}
						<tr>
							<td>
								<span class="dot" style="background:{checkpointColor(leg)}"></span>
								{checkpointLabel(leg)}
							</td>
							<td class="num">{formatDistance(leg.cumDistM)}</td>
							<td class="num vert">
								{#if leg.legGainM >= 1 || leg.legLossM >= 1}
									<span class="up">+{Math.round(leg.legGainM)}</span>
									<span class="down">−{Math.round(leg.legLossM)}</span>
								{:else}—{/if}
							</td>
							<td class="num">
								{fmtSplitTime(leg.projectedElapsedS)}
								{#if leg.projectedClockMin != null}<span class="clock">{fmtClock(leg.projectedClockMin)}</span>{/if}
							</td>
							<td>
								{#if leg.cutoff}
									<span class="cut {cutoffClass(leg.cutoff.status)}">
										{fmtClock(startClockMin != null ? (startClockMin + leg.cutoff.limitElapsedS / 60) : undefined) || fmtSplitTime(leg.cutoff.limitElapsedS)}
										<small>{fmtMargin(leg.cutoff.marginS)}</small>
									</span>
								{/if}
							</td>
							{#if fuelOn}
								<td class="num fuel-cell" data-testid="fuel-carbs">
									{m('roadbook.carbsValue', { grams: String(Math.round(fuel.legs[i].carbsG)) })}
								</td>
								<td class="num fuel-cell">
									{m('roadbook.fluidValue', { ml: String(Math.round(fuel.legs[i].fluidMl)) })}
									{#if (fuel.legs[i].carryToNextAid?.gels ?? 0) > 0}
										<span class="carry-hint">
											{m('roadbook.carryHint', {
												gels: String(fuel.legs[i].carryToNextAid?.gels ?? 0),
												fluid: String(Math.round(fuel.legs[i].carryToNextAid?.fluidMl ?? 0))
											})}
										</span>
									{/if}
								</td>
							{/if}
							<td class="no-print services">
								{#each leg.services as s (s)}<span class="svc">{serviceLabel(s)}</span>{/each}
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		{/if}
	{/if}
</div>

<style>
	.roadbook-page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 64rem;
	}
	.rb-header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.rb-header h1 {
		margin: 0;
		font-size: 1.5rem;
	}
	.back {
		display: inline-block;
		color: var(--color-text-secondary);
		text-decoration: none;
		font-size: 0.9rem;
		margin-bottom: 2px;
	}
	.rb-actions {
		display: flex;
		gap: var(--space-sm);
	}
	.rb-controls {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.rb-controls label {
		display: flex;
		flex-direction: column;
		gap: 2px;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.rb-controls input {
		padding: 6px 8px;
		border: 1px solid var(--color-border);
		border-radius: 6px;
		background: var(--color-surface);
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.model-toggle {
		display: inline-flex;
		border: 1px solid var(--color-border);
		border-radius: 6px;
		overflow: hidden;
	}
	.model-toggle button {
		border: none;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		padding: 7px 12px;
		cursor: pointer;
		font-size: 0.85rem;
	}
	.model-toggle button.active {
		background: var(--color-primary);
		color: #fff;
	}
	.rb-summary {
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
	}
	.link-btn {
		background: none;
		border: none;
		color: var(--color-primary);
		cursor: pointer;
		padding: 0 0 0 8px;
		font: inherit;
	}
	.rb-table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.92rem;
	}
	.rb-table th,
	.rb-table td {
		text-align: start;
		padding: 8px 10px;
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}
	.rb-table th.num,
	.rb-table td.num {
		text-align: end;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.dot {
		display: inline-block;
		width: 0.7rem;
		height: 0.7rem;
		border-radius: 999px;
		margin-inline-end: 6px;
		vertical-align: middle;
	}
	.vert .up {
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
	}
	.vert .down {
		color: color-mix(in srgb, var(--color-accent-cyan) 50%, var(--color-text));
		margin-inline-start: 4px;
	}
	.clock {
		display: block;
		color: var(--color-text-secondary);
		font-size: 0.8rem;
	}
	.cut {
		display: inline-flex;
		flex-direction: column;
		padding: 2px 8px;
		border-radius: 6px;
		font-variant-numeric: tabular-nums;
	}
	.cut small {
		font-size: 0.75rem;
		opacity: 0.85;
	}
	.cut-safe {
		background: var(--color-success-light);
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.cut-tight {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
	}
	.cut-miss {
		background: var(--color-danger-light);
		color: color-mix(in srgb, var(--color-danger) 65%, var(--color-text));
	}
	.services .svc {
		display: inline-block;
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
		border-radius: 4px;
		padding: 1px 6px;
		margin: 0 4px 2px 0;
		font-size: 0.78rem;
	}
	.fuel-cell {
		white-space: nowrap;
	}
	.carry-hint {
		display: block;
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		white-space: nowrap;
	}
	.empty {
		margin-top: var(--space-md);
	}
	@media print {
		.no-print {
			display: none !important;
		}
		.roadbook-page {
			padding: 0;
			max-width: none;
		}
		.rb-table {
			font-size: 0.8rem;
		}
	}
</style>
