<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';
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
		parseCutoff
	} from '$lib/routes/route_markers';
	import { formatDistance } from '$lib/format/units.svelte';

	interface Props {
		routeId: string;
		isOwner: boolean;
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
	let draftNote = $state('');
	let draftLat = $state<number | null>(null);
	let draftLng = $state<number | null>(null);
	let draftLatText = $state('');
	let draftLngText = $state('');
	let formOpen = $state(false);
	let saving = $state(false);
	let confirmDeleteId = $state<string | null>(null);

	let sorted = $derived(sortMarkers(markers));

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
		}
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
			if (target && isOwner) openEdit(target);
		}
	});

	function resetDraft() {
		editingId = null;
		draftKind = 'aid_station';
		draftLabel = '';
		draftServices = [];
		draftCutoffClock = '';
		draftNote = '';
		draftLat = null;
		draftLng = null;
		draftLatText = '';
		draftLngText = '';
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
		draftCutoffClock = cutoff?.clock ?? '';
		draftNote = typeof mk.meta?.note === 'string' ? (mk.meta.note as string) : '';
		draftLat = mk.lat;
		draftLng = mk.lng;
		draftLatText = formatCoord(mk.lat);
		draftLngText = formatCoord(mk.lng);
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

	function buildMeta(): Record<string, unknown> {
		const meta: Record<string, unknown> = {};
		const spec = kindSpec(draftKind);
		if (spec.hasServices && draftServices.length > 0) meta.services = draftServices;
		if (spec.hasCutoff && draftCutoffClock.trim()) meta.cutoff_clock = draftCutoffClock.trim();
		if ((draftKind === 'note' || draftKind === 'hazard') && draftNote.trim()) {
			meta.note = draftNote.trim();
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

	async function doDelete() {
		const id = confirmDeleteId;
		confirmDeleteId = null;
		if (!id) return;
		try {
			await deleteRouteMarker(id);
			await reload();
			if (editingId === id) closeForm();
		} catch (e) {
			showToast(m('routeMarker.deleteFailed', { error: `${e}` }), 'error');
		}
	}

	function kindLabel(kind: string): string {
		return m(kindSpec(kind).labelKey as 'routeMarker.kind.aid_station');
	}

	function distanceLabel(mk: RouteMarker): string {
		return mk.position_m == null ? '' : formatDistance(mk.position_m);
	}

	function detailLine(mk: RouteMarker): string {
		const spec = kindSpec(mk.kind);
		if (spec.hasServices && Array.isArray(mk.meta?.services) && mk.meta.services.length > 0) {
			return (mk.meta.services as string[])
				.map((s) => m(`routeMarker.service.${s}` as 'routeMarker.service.water'))
				.join(' · ');
		}
		if (spec.hasCutoff) {
			const cutoff = parseCutoff(mk.meta);
			if (cutoff?.clock) return m('routeMarker.cutoffAt', { time: cutoff.clock });
		}
		if (typeof mk.meta?.note === 'string') return mk.meta.note as string;
		return '';
	}
</script>

<section class="markers-panel" aria-labelledby="markers-heading">
	<div class="markers-head">
		<h3 id="markers-heading">{m('routeMarker.heading')}</h3>
		{#if isOwner && !formOpen}
			<button type="button" class="btn btn-sm btn-outline" onclick={openAdd}>
				<span class="material-symbols">add_location_alt</span>
				{m('routeMarker.add')}
			</button>
		{/if}
	</div>

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
							<span class="marker-kind">{kindLabel(mk.kind)}</span>
							{#if detailLine(mk)}<span class="marker-detail">{detailLine(mk)}</span>{/if}
						</div>
					</div>
					{#if isOwner && !formOpen}
						<div class="marker-actions">
							<button
								type="button"
								class="icon-btn"
								title={m('routeMarker.edit')}
								onclick={() => openEdit(mk)}
							>
								<span class="material-symbols">edit</span>
							</button>
							<button
								type="button"
								class="icon-btn"
								title={m('routeMarker.delete')}
								onclick={() => (confirmDeleteId = mk.id)}
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
				<label>
					{m('routeMarker.cutoffLabel')}
					<input type="time" bind:value={draftCutoffClock} />
				</label>
			{/if}

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

<ConfirmDialog
	open={confirmDeleteId != null}
	title={m('routeMarker.deleteConfirmTitle')}
	message={m('routeMarker.deleteConfirmMessage')}
	confirmLabel={m('routeMarker.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmDeleteId = null)}
/>

<style>
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
		color: var(--text-secondary);
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
		box-shadow: 0 0 0 2px var(--surface);
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
	}
	.marker-dist {
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
		font-size: 0.85rem;
	}
	.marker-line2 {
		display: flex;
		gap: var(--space-xs);
		flex-wrap: wrap;
		font-size: 0.85rem;
		color: var(--text-secondary);
	}
	.marker-kind {
		text-transform: capitalize;
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
		color: var(--text-secondary);
		padding: 2px;
		display: inline-flex;
	}
	.icon-btn:hover {
		color: var(--text-primary);
	}
	.marker-form {
		border-top: 1px solid var(--border);
		padding-top: var(--space-sm);
	}
	.marker-hint {
		margin: 0 0 var(--space-xs);
		font-size: 0.85rem;
		color: var(--text-secondary);
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.marker-hint .material-symbols {
		font-size: 1.1rem;
		color: var(--color-primary, #4f46e5);
	}
	.snap-row {
		margin-bottom: var(--space-xs);
		font-size: 0.85rem;
	}
	.coord-fields {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-sm);
	}
	.markers-drag-hint {
		margin: 0;
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.8rem;
		color: var(--text-secondary);
	}
	.markers-drag-hint .material-symbols {
		font-size: 1rem;
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
