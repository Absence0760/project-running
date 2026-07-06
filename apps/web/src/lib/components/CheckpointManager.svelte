<script lang="ts">
	import Modal from './Modal.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { getUnit } from '$lib/format/units.svelte';
	import {
		fetchEventCheckpoints,
		createEventCheckpoint,
		updateEventCheckpoint,
		deleteEventCheckpoint,
		type EventCheckpoint
	} from '$lib/core/data';

	interface Props {
		eventId: string;
	}
	let { eventId }: Props = $props();

	let checkpoints = $state<EventCheckpoint[]>([]);
	let loading = $state(true);
	let busy = $state(false);
	let showEditor = $state(false);
	let editing = $state<EventCheckpoint | null>(null);
	let toDelete = $state<EventCheckpoint | null>(null);

	// Form fields. Numeric <input bind:value> yields number|null (web gotcha),
	// so position/cutoff are number-bound; name/clock are string-bound.
	let fName = $state('');
	let fPosition = $state<number | null>(null);
	let fCutoff = $state('');
	let fCutoffClock = $state('');
	let fWeighIn = $state(false);

	const unitLabel = $derived(getUnit() === 'mi' ? 'mi' : 'km');

	async function load() {
		loading = true;
		try {
			checkpoints = await fetchEventCheckpoints(eventId);
		} catch (e) {
			showToast(e instanceof Error ? e.message : m('checkpoint.loadFailed'), 'error');
		} finally {
			loading = false;
		}
	}
	$effect(() => {
		void load();
	});

	function openAdd() {
		editing = null;
		fName = '';
		fPosition = null;
		fCutoff = '';
		fCutoffClock = '';
		fWeighIn = false;
		showEditor = true;
	}

	function openEdit(cp: EventCheckpoint) {
		editing = cp;
		fName = cp.name;
		fPosition = cp.position_m != null ? metresToUnit(cp.position_m) : null;
		fCutoff = cp.cutoff_elapsed_s != null ? formatElapsed(cp.cutoff_elapsed_s) : '';
		fCutoffClock = cp.cutoff_clock ?? '';
		fWeighIn = cp.requires_weigh_in;
		showEditor = true;
	}

	/** Display metres in the user's distance unit for the input field. */
	function metresToUnit(metres: number): number {
		return getUnit() === 'mi'
			? Math.round((metres / 1609.344) * 100) / 100
			: Math.round((metres / 1000) * 100) / 100;
	}
	function unitToMetres(value: number): number {
		return getUnit() === 'mi' ? value * 1609.344 : value * 1000;
	}

	/** h:mm or h:mm:ss elapsed → seconds; null on empty/invalid. */
	function parseElapsed(raw: string): number | null {
		const s = raw.trim();
		if (!s) return null;
		const parts = s.split(':').map((p) => Number(p));
		if (parts.some((p) => !Number.isFinite(p) || p < 0)) return null;
		if (parts.length === 2) return parts[0] * 3600 + parts[1] * 60;
		if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
		return null;
	}
	function formatElapsed(seconds: number): string {
		const h = Math.floor(seconds / 3600);
		const mn = Math.floor((seconds % 3600) / 60);
		return `${h}:${String(mn).padStart(2, '0')}`;
	}

	async function save() {
		const name = fName.trim();
		if (!name || busy) return;
		const cutoffElapsedS = parseElapsed(fCutoff);
		if (fCutoff.trim() && cutoffElapsedS === null) {
			showToast(m('checkpoint.saveFailed'), 'error');
			return;
		}
		const cutoffClock = fCutoffClock.trim() || null;
		const positionM = fPosition != null && Number.isFinite(fPosition) ? unitToMetres(fPosition) : null;
		busy = true;
		try {
			if (editing) {
				await updateEventCheckpoint(editing.id, {
					name,
					positionM,
					cutoffElapsedS,
					cutoffClock,
					requiresWeighIn: fWeighIn
				});
			} else {
				const nextOrdinal =
					checkpoints.length > 0 ? Math.max(...checkpoints.map((c) => c.ordinal)) + 1 : 1;
				await createEventCheckpoint({
					eventId,
					name,
					ordinal: nextOrdinal,
					positionM,
					cutoffElapsedS,
					cutoffClock,
					requiresWeighIn: fWeighIn
				});
			}
			showEditor = false;
			await load();
		} catch (e) {
			showToast(e instanceof Error ? e.message : m('checkpoint.saveFailed'), 'error');
		} finally {
			busy = false;
		}
	}

	async function confirmDelete() {
		const cp = toDelete;
		toDelete = null;
		if (!cp) return;
		try {
			await deleteEventCheckpoint(cp.id);
			await load();
		} catch (e) {
			showToast(e instanceof Error ? e.message : m('checkpoint.deleteFailed'), 'error');
		}
	}

	/** Swap two checkpoints' ordinals to reorder. The (event_id, ordinal)
	 *  unique constraint forbids a transient collision, so move to a temp
	 *  ordinal first, then settle. */
	async function move(index: number, dir: -1 | 1) {
		const other = index + dir;
		if (busy || other < 0 || other >= checkpoints.length) return;
		const a = checkpoints[index];
		const b = checkpoints[other];
		busy = true;
		try {
			const temp = Math.max(...checkpoints.map((c) => c.ordinal)) + 1000;
			await updateEventCheckpoint(a.id, { ordinal: temp });
			await updateEventCheckpoint(b.id, { ordinal: a.ordinal });
			await updateEventCheckpoint(a.id, { ordinal: b.ordinal });
			await load();
		} catch (e) {
			showToast(e instanceof Error ? e.message : m('checkpoint.saveFailed'), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<section class="card checkpoint-manager" data-testid="checkpoint-manager">
	<div class="cm-head">
		<div>
			<h3>{m('checkpoint.sectionTitle')}</h3>
			<p class="sub">{m('checkpoint.sectionSub')}</p>
		</div>
		<button type="button" class="btn btn-primary-sm" onclick={openAdd} data-testid="checkpoint-add">
			<span class="material-symbols" aria-hidden="true">add_location_alt</span>
			{m('checkpoint.add')}
		</button>
	</div>

	{#if loading}
		<p class="muted">{m('shell.loading')}</p>
	{:else if checkpoints.length === 0}
		<p class="muted">{m('checkpoint.none')}</p>
	{:else}
		<ol class="cp-list">
			{#each checkpoints as cp, i (cp.id)}
				<li class="cp-row" data-testid="checkpoint-row">
					<span class="cp-ordinal" aria-hidden="true">{cp.ordinal}</span>
					<div class="cp-main">
						<strong>{cp.name}</strong>
						<span class="cp-meta">
							{#if cp.position_m != null}
								<span class="cp-dist">{metresToUnit(cp.position_m)} {unitLabel}</span>
							{/if}
							{#if cp.cutoff_elapsed_s != null}
								<span class="cp-badge cutoff">{m('checkpoint.cutoffBadge', { time: formatElapsed(cp.cutoff_elapsed_s) })}</span>
							{:else if cp.cutoff_clock}
								<span class="cp-badge cutoff">{m('checkpoint.cutoffBadge', { time: cp.cutoff_clock })}</span>
							{/if}
							{#if cp.requires_weigh_in}
								<span class="cp-badge weigh">{m('checkpoint.weighInBadge')}</span>
							{/if}
						</span>
					</div>
					<div class="cp-actions">
						<button type="button" class="icon-btn" onclick={() => move(i, -1)} disabled={busy || i === 0} aria-label={m('checkpoint.moveUp')}>
							<span class="material-symbols" aria-hidden="true">arrow_upward</span>
						</button>
						<button type="button" class="icon-btn" onclick={() => move(i, 1)} disabled={busy || i === checkpoints.length - 1} aria-label={m('checkpoint.moveDown')}>
							<span class="material-symbols" aria-hidden="true">arrow_downward</span>
						</button>
						<button type="button" class="btn-link" onclick={() => openEdit(cp)}>{m('checkpoint.edit')}</button>
						<button type="button" class="btn-link danger" onclick={() => (toDelete = cp)}>{m('checkpoint.delete')}</button>
					</div>
				</li>
			{/each}
		</ol>
	{/if}
</section>

<Modal
	open={showEditor}
	onclose={() => (showEditor = false)}
	title={editing ? m('checkpoint.edit') : m('checkpoint.add')}
	narrow
	data-testid="checkpoint-editor"
>
	<form class="editor-form" onsubmit={(e) => { e.preventDefault(); save(); }}>
		<label>
			{m('checkpoint.nameLabel')}
			<input type="text" bind:value={fName} placeholder={m('checkpoint.namePlaceholder')} maxlength="120" required data-testid="checkpoint-name" />
		</label>
		<label>
			{m('checkpoint.positionLabel', { unit: unitLabel })}
			<input type="number" inputmode="decimal" step="0.01" min="0" bind:value={fPosition} />
		</label>
		<label>
			{m('checkpoint.cutoffElapsedLabel')}
			<input type="text" inputmode="numeric" bind:value={fCutoff} placeholder={m('checkpoint.cutoffElapsedPlaceholder')} />
		</label>
		<label>
			{m('checkpoint.cutoffClockLabel')}
			<input type="text" inputmode="numeric" bind:value={fCutoffClock} placeholder="HH:MM" pattern="[0-2][0-9]:[0-5][0-9]" />
		</label>
		<label class="toggle-row">
			<input type="checkbox" bind:checked={fWeighIn} data-testid="checkpoint-weigh-in" />
			<span>
				<strong>{m('checkpoint.requiresWeighIn')}</strong>
				<span class="toggle-hint">{m('checkpoint.requiresWeighInHint')}</span>
			</span>
		</label>
		<div class="form-actions">
			<button type="button" class="btn btn-secondary" onclick={() => (showEditor = false)}>{m('checkpoint.cancel')}</button>
			<button type="submit" class="btn btn-primary" disabled={busy || !fName.trim()} data-testid="checkpoint-save">{m('checkpoint.save')}</button>
		</div>
	</form>
</Modal>

<ConfirmDialog
	open={toDelete !== null}
	title={m('checkpoint.deleteTitle')}
	message={toDelete ? m('checkpoint.deleteBody', { name: toDelete.name }) : ''}
	confirmLabel={m('checkpoint.delete')}
	cancelLabel={m('checkpoint.cancel')}
	danger
	onconfirm={confirmDelete}
	oncancel={() => (toDelete = null)}
/>

<style>
	.cm-head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.cm-head .sub {
		margin: 0.25rem 0 0;
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		max-width: 48ch;
	}
	.cp-list {
		list-style: none;
		margin: var(--space-md) 0 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.cp-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: 0.6rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.cp-ordinal {
		flex: 0 0 1.75rem;
		height: 1.75rem;
		display: grid;
		place-items: center;
		border-radius: 50%;
		background: var(--color-bg-secondary);
		font-weight: 700;
		font-size: 0.85rem;
	}
	.cp-main {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
	}
	.cp-meta {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
		align-items: center;
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
	}
	.cp-badge {
		padding: 0.05rem 0.4rem;
		border-radius: var(--radius-sm);
		font-weight: 600;
		font-size: 0.75rem;
	}
	.cp-badge.cutoff {
		background: color-mix(in srgb, var(--warning, #b45309) 18%, transparent);
		color: var(--warning, #b45309);
	}
	.cp-badge.weigh {
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}
	.cp-actions {
		display: flex;
		align-items: center;
		gap: 0.3rem;
		flex-wrap: wrap;
	}
	.icon-btn {
		display: grid;
		place-items: center;
		width: 2rem;
		height: 2rem;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		cursor: pointer;
		color: var(--color-text-tertiary);
	}
	.icon-btn:hover:not(:disabled) {
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}
	.icon-btn:disabled {
		opacity: 0.35;
		cursor: default;
	}
	.btn-link.danger {
		color: var(--danger, #dc2626);
	}
	.toggle-hint {
		display: block;
		font-weight: 400;
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
	}
	.form-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
		margin-top: var(--space-md);
	}
</style>
