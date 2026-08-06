<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { deferDestructive } from '$lib/stores/undo.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import type { MapMarkerPin } from './RunMap.svelte';
	import type { RouteMarker, RouteMarkerKind } from '$lib/types';
	import {
		fetchRouteMarkers,
		addRouteMarker,
		updateRouteMarker,
		deleteRouteMarker
	} from '$lib/core/data';
	import {
		ROUTE_MARKER_KINDS,
		AID_SERVICES,
		kindSpec,
		sortMarkers,
		parseCutoff,
		parseTarget,
		isOfficialMarker
	} from '$lib/routes/route_markers';
	import { markerPointAtDistance, polylineLengthMetres } from '$lib/routes/route_geometry';
	import { formatDistance, getUnit } from '$lib/format/units.svelte';

	interface Props {
		routeId: string;
		isOwner: boolean;
		/// The route owner's user id — a marker is OFFICIAL (the owner's,
		/// read-only to everyone else) when `marker.user_id === routeOwnerId`.
		/// Any signed-in viewer may still add their OWN personal markers.
		routeOwnerId: string;
		/// The route polyline, used to place a marker by distance-along-route
		/// ("mile 5") as an alternative to a map tap / typed lat-lng. Empty
		/// when the route has no geometry — the distance field then hides.
		routeWaypoints?: { lat: number; lng: number }[];
		/// Pins published for RunMap to render (sorted, coloured). Out-bound.
		pins?: MapMarkerPin[];
		/// Whether the map should be in click-to-place mode. Out-bound.
		placing?: boolean;
		/// A lng/lat the host captured from a map click. In-bound; consumed
		/// once when set.
		pendingPlacement?: { lat: number; lng: number } | null;
		/// A marker id the host captured from a map pin click. In-bound;
		/// opens that marker for editing.
		selectId?: string | null;
		/// The in-flight marker (being added or edited), published for the
		/// map to render as a single draggable draft pin distinct from the
		/// saved pins. Out-bound. Null when nothing is being placed.
		draftPin?: MapMarkerPin | null;
		/// Whether new placements + pin drags snap to the route line.
		/// Out-bound so the map can apply it. Default on — course markers
		/// belong on the course.
		snapEnabled?: boolean;
		/// A drag the host captured from an existing pin (id + new lng/lat).
		/// In-bound; consumed once to persist the move.
		pendingDrag?: { id: string; lat: number; lng: number } | null;
	}
	let {
		routeId,
		isOwner,
		routeOwnerId,
		routeWaypoints = [],
		pins = $bindable([]),
		placing = $bindable(false),
		pendingPlacement = $bindable(null),
		selectId = $bindable(null),
		draftPin = $bindable(null),
		snapEnabled = $bindable(true),
		pendingDrag = $bindable(null)
	}: Props = $props();

	let markers = $state<RouteMarker[]>([]);
	let loaded = $state(false);

	// Draft form state for the marker currently being added or edited.
	let editingId = $state<string | null>(null); // null while adding a new one
	let draftKind = $state<RouteMarkerKind>('aid_station');
	let draftLabel = $state('');
	let draftServices = $state<string[]>([]);
	let draftCutoffClock = $state('');
	let draftTargetText = $state('');
	// Both meta time concepts accept EITHER a wall clock or an elapsed-from-start
	// value (`parseCutoff` / `parseTarget` read both, and the roadbook prefers
	// elapsed). One field per concept plus a mode switch beats four fields; only
	// the selected form is written, so the two alternatives can't disagree.
	let draftCutoffElapsed = $state(false);
	let draftTargetClock = $state(false);
	let draftNote = $state('');
	let draftLat = $state<number | null>(null);
	let draftLng = $state<number | null>(null);
	let draftLatText = $state('');
	let draftLngText = $state('');
	// Alternative "place by distance along the route" entry (part of the
	// add-by-mile path). Held in the viewer's display unit; converted to
	// metres and resolved to a lat/lng via the route polyline on input.
	let draftDistanceText = $state('');
	let distanceClamped = $state(false);
	let formOpen = $state(false);
	let saving = $state(false);

	let sorted = $derived(sortMarkers(markers));

	const METRES_PER_MILE = 1609.344;

	// Total length of the route line — the ceiling the distance input
	// clamps to, and the denominator for the display-unit hint.
	let routeLengthM = $derived(
		routeWaypoints.length >= 2 ? polylineLengthMetres(routeWaypoints) : 0
	);
	let canPlaceByDistance = $derived(routeLengthM > 0);

	// A marker is the current viewer's own iff they authored it — the RLS
	// edit/delete boundary. An OFFICIAL marker (the route owner's) is
	// read-only to everyone else; a signed-in viewer's own markers are a
	// private personal overlay they fully control.
	function isMine(mk: { user_id: string }): boolean {
		return auth.user?.id != null && mk.user_id === auth.user.id;
	}
	function official(mk: { user_id: string }): boolean {
		return isOfficialMarker(mk, routeOwnerId);
	}

	function distanceUnitToMetres(v: number): number {
		return getUnit() === 'mi' ? v * METRES_PER_MILE : v * 1000;
	}
	function metresToDistanceUnit(mVal: number): number {
		return getUnit() === 'mi' ? mVal / METRES_PER_MILE : mVal / 1000;
	}

	async function reload() {
		markers = await fetchRouteMarkers(routeId);
		loaded = true;
	}
	$effect(() => {
		void routeId;
		reload();
	});

	// Republish pins whenever the sorted markers change. The marker being
	// edited is withheld — it renders as the draggable draft pin instead,
	// so dragging it tweaks the open form rather than persisting straight
	// away.
	$effect(() => {
		pins = sorted
			.filter((mk) => mk.id !== editingId)
			.map((mk) => ({
				id: mk.id,
				label: mk.label,
				color: kindSpec(mk.kind).color,
				lat: mk.lat,
				lng: mk.lng
			}));
	});

	// Publish the in-flight marker as the draft pin once it has a position.
	$effect(() => {
		draftPin =
			formOpen && draftLat != null && draftLng != null
				? {
						id: editingId ?? '__draft__',
						label: draftLabel.trim() || m('routeMarker.newMarker'),
						color: kindSpec(draftKind).color,
						lat: draftLat,
						lng: draftLng
					}
				: null;
	});

	// A map click — or a drag of the draft pin — during add/edit fills the
	// pin position.
	$effect(() => {
		if (pendingPlacement && formOpen) {
			draftLat = pendingPlacement.lat;
			draftLng = pendingPlacement.lng;
			draftLatText = formatCoord(pendingPlacement.lat);
			draftLngText = formatCoord(pendingPlacement.lng);
			// A map tap wins over any stale distance the user typed — the
			// distance field is only a shortcut to a lat/lng, not the source
			// of truth once the pin has been dropped somewhere else.
			draftDistanceText = '';
			distanceClamped = false;
			pendingPlacement = null;
		}
	});

	function formatCoord(v: number): string {
		return String(Number(v.toFixed(6)));
	}

	function parseCoord(text: string, max: number): number | null {
		const t = text.trim();
		if (!t) return null;
		const v = Number(t);
		if (!Number.isFinite(v) || Math.abs(v) > max) return null;
		return v;
	}

	let coordInvalid = $derived(
		(draftLatText.trim() !== '' && parseCoord(draftLatText, 90) == null) ||
			(draftLngText.trim() !== '' && parseCoord(draftLngText, 180) == null)
	);

	// Typing a full, valid coordinate pair moves the draft pin live — the
	// keyboard-accessible twin of a map click.
	function applyCoordInput() {
		const lat = parseCoord(draftLatText, 90);
		const lng = parseCoord(draftLngText, 180);
		if (lat != null && lng != null) {
			draftLat = lat;
			draftLng = lng;
			draftDistanceText = '';
			distanceClamped = false;
		}
	}

	// The "place by distance along the route" path: convert the entered
	// distance (in the viewer's unit) to metres, resolve it to a point on
	// the route polyline, and move the draft pin there. Out-of-range
	// distances clamp to the finish (flagged via `distanceClamped` so the
	// UI can say so). No-ops on empty / non-numeric / no-geometry input.
	function applyDistanceInput() {
		distanceClamped = false;
		const t = draftDistanceText.trim();
		if (!t) return;
		const v = Number(t);
		if (!Number.isFinite(v) || v < 0) return;
		if (routeWaypoints.length < 2) return;
		const metres = distanceUnitToMetres(v);
		const pt = markerPointAtDistance(routeWaypoints, metres);
		if (!pt) return;
		if (metres > routeLengthM + 0.5) distanceClamped = true;
		draftLat = pt.lat;
		draftLng = pt.lng;
		draftLatText = formatCoord(pt.lat);
		draftLngText = formatCoord(pt.lng);
	}

	// A drag of an already-saved pin persists immediately (a quick reposition
	// that doesn't need the form). The edited marker never reaches here — it
	// is withheld from `pins` above.
	$effect(() => {
		if (pendingDrag) {
			const { id, lat, lng } = pendingDrag;
			pendingDrag = null;
			void persistMove(id, lat, lng);
		}
	});

	async function persistMove(id: string, lat: number, lng: number) {
		try {
			await updateRouteMarker(id, { lat, lng });
			await reload();
			showToast(m('routeMarker.moved'), 'success');
		} catch (e) {
			showToast(m('routeMarker.saveFailed', { error: `${e}` }), 'error');
		}
	}

	// A map pin click opens that marker for editing.
	$effect(() => {
		if (selectId) {
			const target = markers.find((mk) => mk.id === selectId);
			selectId = null;
			// Only the author can open a marker for editing — an official
			// marker is read-only to a non-owner viewer.
			if (target && isMine(target)) openEdit(target);
		}
	});

	function resetDraft() {
		editingId = null;
		draftKind = 'aid_station';
		draftLabel = '';
		draftServices = [];
		draftCutoffClock = '';
		draftTargetText = '';
		draftCutoffElapsed = false;
		draftTargetClock = false;
		draftNote = '';
		draftLat = null;
		draftLng = null;
		draftLatText = '';
		draftLngText = '';
		draftDistanceText = '';
		distanceClamped = false;
	}

	function openAdd() {
		resetDraft();
		formOpen = true;
		placing = true;
	}

	function openEdit(mk: RouteMarker) {
		editingId = mk.id;
		draftKind = mk.kind;
		draftLabel = mk.label;
		draftServices = Array.isArray(mk.meta?.services) ? [...(mk.meta.services as string[])] : [];
		const cutoff = parseCutoff(mk.meta);
		// Open in the form the marker was actually saved in.
		draftCutoffElapsed = cutoff?.elapsedS != null;
		draftCutoffClock = draftCutoffElapsed
			? formatElapsed(cutoff!.elapsedS!)
			: (cutoff?.clock ?? '');
		const target = parseTarget(mk.meta);
		draftTargetClock = target?.elapsedS == null && target?.clock != null;
		draftTargetText = draftTargetClock
			? (target!.clock as string)
			: target?.elapsedS != null
				? formatElapsed(target.elapsedS)
				: '';
		draftNote = typeof mk.meta?.note === 'string' ? (mk.meta.note as string) : '';
		draftLat = mk.lat;
		draftLng = mk.lng;
		draftLatText = formatCoord(mk.lat);
		draftLngText = formatCoord(mk.lng);
		// Prefill the distance field with the marker's along-route position
		// so "mile 5" round-trips when editing an existing marker.
		draftDistanceText =
			mk.position_m != null
				? String(Number(metresToDistanceUnit(mk.position_m).toFixed(2)))
				: '';
		distanceClamped = false;
		formOpen = true;
		placing = true;
	}

	function closeForm() {
		formOpen = false;
		placing = false;
		resetDraft();
	}

	function toggleService(s: string) {
		draftServices = draftServices.includes(s)
			? draftServices.filter((x) => x !== s)
			: [...draftServices, s];
	}

	function formatElapsed(s: number): string {
		const h = Math.floor(s / 3600);
		const min = Math.floor((s % 3600) / 60);
		const sec = s % 60;
		const two = (v: number) => String(v).padStart(2, '0');
		return h > 0 ? `${h}:${two(min)}:${two(sec)}` : `${min}:${two(sec)}`;
	}

	/**
	 * "h:mm:ss" / "mm:ss" / bare minutes → elapsed seconds; null = invalid.
	 * A two-part value reads as mm:ss unless the marker's position along the
	 * route makes the h:mm reading the plausible one (150–1500 s/km implied
	 * pace) — an 80 km aid station's "4:30" is 4 h 30, not 4½ minutes.
	 * Mirrors the mobile panel's parseMarkerElapsed.
	 */
	function parseElapsedText(raw: string, positionM: number | null = null): number | null {
		const parts = raw.trim().split(':');
		if (parts.length === 0 || parts.length > 3) return null;
		const nums: number[] = [];
		for (const p of parts) {
			if (!/^\d+$/.test(p.trim())) return null;
			nums.push(Number(p.trim()));
		}
		if (nums.length === 1) return nums[0] > 0 ? nums[0] * 60 : null;
		if (nums.length === 3) {
			const s = nums[0] * 3600 + nums[1] * 60 + nums[2];
			return s > 0 ? s : null;
		}
		const asHours = nums[0] * 3600 + nums[1] * 60;
		const asMinutes = nums[0] * 60 + nums[1];
		if (positionM != null && positionM > 0 && asHours > 0) {
			const pace = asHours / (positionM / 1000);
			if (pace >= 150 && pace <= 1500) return asHours;
		}
		return asMinutes > 0 ? asMinutes : null;
	}

	function editingPositionM(): number | null {
		if (!editingId) return null;
		return markers.find((mk) => mk.id === editingId)?.position_m ?? null;
	}

	// Start from the marker's existing bag rather than a blank one: `meta` is a
	// schemaless registry that also holds whatever a later version adds, and
	// rebuilding from scratch silently deleted all of it on any edit. Each key
	// the editor owns is explicitly set or deleted below, so switching kind
	// still drops the fields that kind can't carry.
	function buildMeta(): Record<string, unknown> {
		const existing = editingId ? markers.find((mk) => mk.id === editingId)?.meta : null;
		const meta: Record<string, unknown> = { ...((existing ?? {}) as Record<string, unknown>) };
		const spec = kindSpec(draftKind);
		if (spec.hasServices && draftServices.length > 0) meta.services = draftServices;
		else delete meta.services;
		if (spec.hasCutoff) {
			const raw = draftCutoffClock.trim();
			// The two forms are alternatives — leaving both would let them
			// disagree, and the roadbook silently prefers the elapsed one.
			delete meta[draftCutoffElapsed ? 'cutoff_clock' : 'cutoff_elapsed_s'];
			if (!raw) {
				delete meta[draftCutoffElapsed ? 'cutoff_elapsed_s' : 'cutoff_clock'];
			} else if (draftCutoffElapsed) {
				const s = parseElapsedText(raw, editingPositionM());
				if (s != null) meta.cutoff_elapsed_s = s;
			} else {
				meta.cutoff_clock = raw;
			}
		} else {
			// Not a cutoff kind any more — the whole cutoff concept goes,
			// including the elapsed form the editor can't edit.
			delete meta.cutoff_clock;
			delete meta.cutoff_elapsed_s;
		}
		const targetRaw = draftTargetText.trim();
		delete meta[draftTargetClock ? 'target_elapsed_s' : 'target_clock'];
		if (!targetRaw) {
			delete meta[draftTargetClock ? 'target_clock' : 'target_elapsed_s'];
		} else if (draftTargetClock) {
			meta.target_clock = targetRaw;
		} else {
			const targetS = parseElapsedText(targetRaw, editingPositionM());
			if (targetS != null) meta.target_elapsed_s = targetS;
		}
		if ((draftKind === 'note' || draftKind === 'hazard') && draftNote.trim()) {
			meta.note = draftNote.trim();
		} else {
			delete meta.note;
		}
		return meta;
	}

	async function save() {
		if (!draftLabel.trim()) {
			showToast(m('routeMarker.labelRequired'), 'error');
			return;
		}
		if (draftLatText.trim() !== '' || draftLngText.trim() !== '') {
			const lat = parseCoord(draftLatText, 90);
			const lng = parseCoord(draftLngText, 180);
			if (lat == null || lng == null) {
				showToast(m('routeMarker.coordInvalid'), 'error');
				return;
			}
			draftLat = lat;
			draftLng = lng;
		}
		if (draftLat == null || draftLng == null) {
			showToast(m('routeMarker.placeRequired'), 'info');
			return;
		}
		if (
			!draftTargetClock &&
			draftTargetText.trim() &&
			parseElapsedText(draftTargetText, editingPositionM()) == null
		) {
			showToast(m('routeMarker.targetInvalid'), 'error');
			return;
		}
		saving = true;
		try {
			const meta = buildMeta();
			if (editingId) {
				await updateRouteMarker(editingId, {
					kind: draftKind,
					label: draftLabel,
					lat: draftLat,
					lng: draftLng,
					meta
				});
			} else {
				await addRouteMarker({
					route_id: routeId,
					kind: draftKind,
					label: draftLabel,
					lat: draftLat,
					lng: draftLng,
					meta
				});
			}
			await reload();
			closeForm();
		} catch (e) {
			showToast(m('routeMarker.saveFailed', { error: `${e}` }), 'error');
		} finally {
			saving = false;
		}
	}

	// A marker is one pin the author placed in one tap, with nothing hanging
	// off it and no Storage object, so it takes the undo path rather than a
	// modal. The row leaves the local list at once (the pin disappears with
	// it, via the `sorted` -> `pins` effect) and the delete is held; a
	// server-derived `position_m` survives because the row is never touched.
	function removeMarker(id: string) {
		const before = markers;
		markers = markers.filter((mk) => mk.id !== id);
		if (editingId === id) closeForm();
		deferDestructive({
			message: m('routeMarker.removed'),
			commit: () => deleteRouteMarker(id),
			restore: () => {
				markers = before;
			},
			onCommitError: (e) =>
				showToast(m('routeMarker.deleteFailed', { error: `${e}` }), 'error'),
		});
	}

	function kindLabel(kind: string): string {
		return m(kindSpec(kind).labelKey as 'routeMarker.kind.aid_station');
	}

	function distanceLabel(mk: RouteMarker): string {
		return mk.position_m == null ? '' : formatDistance(mk.position_m);
	}

	function detailLine(mk: RouteMarker): string {
		const spec = kindSpec(mk.kind);
		const parts: string[] = [];
		if (spec.hasServices && Array.isArray(mk.meta?.services) && mk.meta.services.length > 0) {
			parts.push(
				(mk.meta.services as string[])
					.map((s) => m(`routeMarker.service.${s}` as 'routeMarker.service.water'))
					.join(' · ')
			);
		} else if (spec.hasCutoff) {
			const cutoff = parseCutoff(mk.meta);
			if (cutoff?.clock) parts.push(m('routeMarker.cutoffAt', { time: cutoff.clock }));
		} else if (typeof mk.meta?.note === 'string') {
			parts.push(mk.meta.note as string);
		}
		const target = parseTarget(mk.meta);
		if (target?.elapsedS != null) {
			parts.push(m('routeMarker.targetAt', { time: formatElapsed(target.elapsedS) }));
		}
		return parts.join(' · ');
	}
</script>

<section class="markers-panel" aria-labelledby="markers-heading">
	<div class="markers-head">
		<h3 id="markers-heading">{m('routeMarker.heading')}</h3>
		{#if auth.loggedIn && !formOpen}
			<button type="button" class="btn btn-sm btn-outline" onclick={openAdd}>
				<span class="material-symbols">add_location_alt</span>
				{m('routeMarker.add')}
			</button>
		{/if}
	</div>

	{#if !isOwner && auth.loggedIn && !formOpen}
		<p class="markers-personal-hint">
			<span class="material-symbols" aria-hidden="true">visibility_off</span>
			{m('routeMarker.personalOverlayHint')}
		</p>
	{/if}

	{#if loaded && sorted.length === 0 && !formOpen}
		<p class="markers-empty">{m('routeMarker.empty')}</p>
	{/if}

	{#if isOwner && sorted.length > 0 && !formOpen}
		<p class="markers-drag-hint">
			<span class="material-symbols" aria-hidden="true">drag_pan</span>
			{m('routeMarker.dragHint')}
		</p>
	{/if}

	{#if sorted.length > 0}
		<ol class="markers-list">
			{#each sorted as mk (mk.id)}
				<li class="marker-row">
					<span class="marker-dot" style="background:{kindSpec(mk.kind).color}"></span>
					<div class="marker-body">
						<div class="marker-line1">
							<span class="marker-label">{mk.label}</span>
							{#if distanceLabel(mk)}<span class="marker-dist">{distanceLabel(mk)}</span>{/if}
						</div>
						<div class="marker-line2">
							{#if !isOwner && official(mk)}
								<span class="marker-badge official">
									<span class="material-symbols" aria-hidden="true">verified</span>
									{m('routeMarker.officialBadge')}
								</span>
							{:else if !isOwner && isMine(mk)}
								<span class="marker-badge yours">{m('routeMarker.yoursBadge')}</span>
							{/if}
							<span class="marker-kind">{kindLabel(mk.kind)}</span>
							{#if detailLine(mk)}<span class="marker-detail">{detailLine(mk)}</span>{/if}
						</div>
					</div>
					{#if isMine(mk) && !formOpen}
						<div class="marker-actions">
							<button
								type="button"
								class="icon-btn"
								title={m('routeMarker.edit')}
								aria-label={m('routeMarker.edit')}
								onclick={() => openEdit(mk)}
							>
								<span class="material-symbols">edit</span>
							</button>
							<button
								type="button"
								class="icon-btn"
								title={m('routeMarker.delete')}
								aria-label={m('routeMarker.delete')}
								onclick={() => removeMarker(mk.id)}
							>
								<span class="material-symbols">delete</span>
							</button>
						</div>
					{/if}
				</li>
			{/each}
		</ol>
	{/if}

	{#if formOpen}
		<form class="editor-form marker-form" onsubmit={(e) => (e.preventDefault(), save())}>
			<p class="marker-hint">
				<span class="material-symbols" aria-hidden="true">
					{draftLat == null ? 'ads_click' : 'open_with'}
				</span>
				{draftLat == null ? m('routeMarker.clickToPlace') : m('routeMarker.placed')}
			</p>
			<label class="toggle-row snap-row">
				<input type="checkbox" bind:checked={snapEnabled} />
				{m('routeMarker.snapToggle')}
			</label>
			<div class="coord-fields">
				<label>
					{m('routeMarker.latLabel')}
					<input
						type="text"
						inputmode="decimal"
						bind:value={draftLatText}
						oninput={applyCoordInput}
					/>
				</label>
				<label>
					{m('routeMarker.lngLabel')}
					<input
						type="text"
						inputmode="decimal"
						bind:value={draftLngText}
						oninput={applyCoordInput}
					/>
				</label>
			</div>
			{#if coordInvalid}
				<p class="error" role="alert">{m('routeMarker.coordInvalid')}</p>
			{/if}
			{#if canPlaceByDistance}
				<label class="distance-along">
					{m('routeMarker.distanceAlongLabel', { unit: getUnit() })}
					<input
						type="text"
						inputmode="decimal"
						bind:value={draftDistanceText}
						oninput={applyDistanceInput}
						placeholder={String(Number(metresToDistanceUnit(routeLengthM).toFixed(2)))}
					/>
					<span class="field-hint">{m('routeMarker.distanceAlongHint')}</span>
				</label>
				{#if distanceClamped}
					<p class="field-hint clamped" role="status">
						{m('routeMarker.distanceAlongClamped', {
							distance: formatDistance(routeLengthM)
						})}
					</p>
				{/if}
			{/if}
			<label>
				{m('routeMarker.kindLabel')}
				<select bind:value={draftKind}>
					{#each ROUTE_MARKER_KINDS as k (k.kind)}
						<option value={k.kind}>{kindLabel(k.kind)}</option>
					{/each}
				</select>
			</label>
			<label>
				{m('routeMarker.nameLabel')}
				<input type="text" bind:value={draftLabel} maxlength="120" placeholder={m('routeMarker.namePlaceholder')} />
			</label>

			{#if kindSpec(draftKind).hasServices}
				<fieldset class="services">
					<legend>{m('routeMarker.servicesLabel')}</legend>
					{#each AID_SERVICES as s (s)}
						<label class="toggle-row">
							<input
								type="checkbox"
								checked={draftServices.includes(s)}
								onchange={() => toggleService(s)}
							/>
							{m(`routeMarker.service.${s}` as 'routeMarker.service.water')}
						</label>
					{/each}
				</fieldset>
			{/if}

			{#if kindSpec(draftKind).hasCutoff}
				<div class="time-mode-row" role="radiogroup" aria-label={m('routeMarker.timeMode')}>
						<label class="toggle-row">
							<input
								type="radio"
								name="cutoff-mode"
								checked={!draftCutoffElapsed}
								onchange={() => {
									draftCutoffElapsed = false;
									draftCutoffClock = '';
								}}
							/>
							{m('routeMarker.timeClock')}
						</label>
						<label class="toggle-row">
							<input
								type="radio"
								name="cutoff-mode"
								checked={draftCutoffElapsed}
								onchange={() => {
									draftCutoffElapsed = true;
									draftCutoffClock = '';
								}}
							/>
						{m('routeMarker.timeElapsed')}
					</label>
				</div>
				<label>
					{m('routeMarker.cutoffLabel')}
					{#if draftCutoffElapsed}
						<input
							type="text"
							bind:value={draftCutoffClock}
							placeholder="h:mm:ss"
							inputmode="numeric"
						/>
					{:else}
						<input type="time" bind:value={draftCutoffClock} />
					{/if}
				</label>
			{/if}

			<div class="time-mode-row" role="radiogroup" aria-label={m('routeMarker.timeMode')}>
					<label class="toggle-row">
						<input
							type="radio"
							name="target-mode"
							checked={!draftTargetClock}
							onchange={() => {
								draftTargetClock = false;
								draftTargetText = '';
							}}
						/>
						{m('routeMarker.timeElapsed')}
					</label>
					<label class="toggle-row">
						<input
							type="radio"
							name="target-mode"
							checked={draftTargetClock}
							onchange={() => {
								draftTargetClock = true;
								draftTargetText = '';
							}}
						/>
						{m('routeMarker.timeClock')}
					</label>
				</div>
				<label>
					{m('routeMarker.targetLabel')}
					{#if draftTargetClock}
					<input type="time" bind:value={draftTargetText} />
				{:else}
					<input
						type="text"
						bind:value={draftTargetText}
						placeholder="h:mm:ss"
						inputmode="numeric"
					/>
				{/if}
			</label>

			{#if draftKind === 'note' || draftKind === 'hazard'}
				<label>
					{m('routeMarker.noteLabel')}
					<textarea bind:value={draftNote} rows="2" maxlength="280"></textarea>
				</label>
			{/if}

			<div class="marker-form-actions">
				<button type="button" class="btn btn-secondary btn-sm" onclick={closeForm}>
					{m('routeMarker.cancel')}
				</button>
				<button type="submit" class="btn btn-primary btn-sm" disabled={saving}>
					{saving ? m('routeMarker.saving') : m('routeMarker.save')}
				</button>
			</div>
		</form>
	{/if}
</section>

<style>
	/* The clock-vs-elapsed switch sits OUTSIDE its field's <label>: a nested
	   label makes the outer one label the radio, which breaks both the
	   accessible name and getByLabel in the e2e suite. */
	.time-mode-row {
		display: flex;
		gap: 0.75rem;
		margin-bottom: 0.25rem;
		font-size: 0.85rem;
	}
	.markers-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.markers-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.markers-head h3 {
		margin: 0;
		font-size: 1rem;
	}
	.markers-empty {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.markers-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.marker-row {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		padding: var(--space-2xs) 0;
	}
	.marker-dot {
		flex: 0 0 auto;
		width: 0.75rem;
		height: 0.75rem;
		border-radius: 999px;
		margin-top: 0.3rem;
		box-shadow: 0 0 0 2px var(--color-surface);
	}
	.marker-body {
		flex: 1 1 auto;
		min-width: 0;
	}
	.marker-line1 {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.marker-label {
		font-weight: 600;
		/* A marker label accepts up to 120 chars; without this it overflows the
		   row or crushes the along-route distance chip beside it. Shrink-and-clip
		   to one line (mobile clips the same label to maxLines: 1). */
		flex: 1 1 auto;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.marker-dist {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
		font-size: 0.85rem;
	}
	.marker-line2 {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		flex-wrap: wrap;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.marker-kind {
		text-transform: capitalize;
	}
	.marker-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		font-size: 0.7rem;
		font-weight: 600;
		line-height: 1;
		padding: 0.15rem 0.45rem;
		border-radius: 9999px;
		text-transform: none;
		letter-spacing: 0.01em;
	}
	.marker-badge .material-symbols {
		font-size: 0.85rem;
	}
	.marker-badge.official {
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
		color: var(--color-primary);
	}
	.marker-badge.yours {
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
	}
	.marker-detail::before {
		content: '· ';
	}
	.marker-actions {
		display: flex;
		gap: var(--space-2xs);
	}
	.icon-btn {
		background: none;
		border: none;
		cursor: pointer;
		color: var(--color-text-secondary);
		padding: 2px;
		display: inline-flex;
	}
	.icon-btn:hover {
		color: var(--color-text);
	}
	.marker-form {
		border-top: 1px solid var(--color-border);
		padding-top: var(--space-sm);
	}
	.marker-hint {
		margin: 0 0 var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.marker-hint .material-symbols {
		font-size: 1.1rem;
		color: var(--color-primary);
	}
	.snap-row {
		margin-bottom: var(--space-xs);
		font-size: 0.85rem;
	}
	.coord-fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-sm);
	}
	.markers-drag-hint {
		margin: 0;
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.markers-drag-hint .material-symbols {
		font-size: 1rem;
	}
	.markers-personal-hint {
		margin: 0;
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
	.markers-personal-hint .material-symbols {
		font-size: 1rem;
	}
	.distance-along .field-hint {
		display: block;
		margin-top: 0.15rem;
		font-size: 0.75rem;
		font-weight: 400;
		color: var(--color-text-tertiary);
	}
	.field-hint.clamped {
		margin: 0.15rem 0 0;
		color: var(--color-text-secondary);
	}
	.services {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
	}
	.marker-form-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
</style>
