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
	}
	let {
		routeId,
		isOwner,
		pins = $bindable([]),
		placing = $bindable(false),
		pendingPlacement = $bindable(null),
		selectId = $bindable(null)
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

	// Republish pins whenever the sorted markers change.
	$effect(() => {
		pins = sorted.map((mk) => ({
			id: mk.id,
			label: mk.label,
			color: kindSpec(mk.kind).color,
			lat: mk.lat,
			lng: mk.lng
		}));
	});

	// A map click during add/edit fills the pin position.
	$effect(() => {
		if (pendingPlacement && formOpen) {
			draftLat = pendingPlacement.lat;
			draftLng = pendingPlacement.lng;
			pendingPlacement = null;
		}
	});

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
				{draftLat == null ? m('routeMarker.clickToPlace') : m('routeMarker.placed')}
			</p>
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
