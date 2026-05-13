<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchMyGear,
		createGear,
		updateGear,
		retireGear,
		unretireGear,
		deleteGear,
		type GearKind,
		type GearWithDistance,
	} from '$lib/data';
	import { getUnit } from '$lib/units.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	let gear = $state<GearWithDistance[]>([]);
	let loading = $state(true);
	let activeTab = $state<GearKind>('shoe');
	let editingId = $state<string | null>(null);
	let showCreate = $state(false);
	let confirmingDelete = $state<GearWithDistance | null>(null);

	// Form state shared between Create + Edit modals — simpler than
	// two parallel widgets when the field set is identical.
	let formName = $state('');
	let formBrand = $state('');
	let formModel = $state('');
	let formPurchased = $state('');
	let formTargetDisplay = $state('');
	let formNotes = $state('');
	let saving = $state(false);

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		gear = await fetchMyGear();
		loading = false;
	});

	const visible = $derived(gear.filter((g) => g.kind === activeTab));
	const active = $derived(visible.filter((g) => !g.retired_at));
	const retired = $derived(visible.filter((g) => g.retired_at));

	function targetDisplayToMetres(s: string): number | null {
		const n = parseFloat(s);
		if (!Number.isFinite(n) || n <= 0) return null;
		return Math.round(n * (getUnit() === 'mi' ? 1609.344 : 1000));
	}
	function metresToTargetDisplay(m: number | null): string {
		if (m == null) return '';
		const div = getUnit() === 'mi' ? 1609.344 : 1000;
		return (m / div).toFixed(0);
	}

	function resetForm() {
		formName = '';
		formBrand = '';
		formModel = '';
		formPurchased = '';
		formTargetDisplay = '';
		formNotes = '';
		editingId = null;
	}

	function openEdit(g: GearWithDistance) {
		editingId = g.id;
		formName = g.name;
		formBrand = g.brand ?? '';
		formModel = g.model ?? '';
		formPurchased = g.purchased_at ?? '';
		formTargetDisplay = metresToTargetDisplay(g.target_distance_m);
		formNotes = g.notes ?? '';
	}

	async function handleSave() {
		if (!formName.trim()) return;
		saving = true;
		try {
			const target = targetDisplayToMetres(formTargetDisplay);
			if (editingId) {
				await updateGear(editingId, {
					name: formName.trim(),
					brand: formBrand.trim() || null,
					model: formModel.trim() || null,
					purchased_at: formPurchased || null,
					target_distance_m: target,
					notes: formNotes.trim() || null,
				});
			} else {
				await createGear({
					kind: activeTab,
					name: formName.trim(),
					brand: formBrand.trim() || null,
					model: formModel.trim() || null,
					purchased_at: formPurchased || null,
					target_distance_m: target,
					notes: formNotes.trim() || null,
				});
			}
			gear = await fetchMyGear();
			resetForm();
			showCreate = false;
		} catch (e) {
			showToast(`Save failed: ${(e as Error).message}`, 'error');
		} finally {
			saving = false;
		}
	}

	async function handleRetire(g: GearWithDistance) {
		try {
			if (g.retired_at) {
				await unretireGear(g.id);
			} else {
				await retireGear(g.id);
			}
			gear = await fetchMyGear();
		} catch (e) {
			showToast(`Failed: ${(e as Error).message}`, 'error');
		}
	}

	async function handleDelete() {
		if (!confirmingDelete) return;
		try {
			await deleteGear(confirmingDelete.id);
			gear = await fetchMyGear();
		} catch (e) {
			showToast(`Delete failed: ${(e as Error).message}`, 'error');
		} finally {
			confirmingDelete = null;
		}
	}

	function progressFor(g: GearWithDistance): { pct: number; label: string } {
		const target = g.target_distance_m ?? 0;
		const accrued = g.total_distance_m;
		const div = getUnit() === 'mi' ? 1609.344 : 1000;
		const unitLabel = getUnit() === 'mi' ? 'mi' : 'km';
		if (target <= 0) {
			return { pct: 0, label: `${(accrued / div).toFixed(1)} ${unitLabel}` };
		}
		const pct = Math.min(100, (accrued / target) * 100);
		return {
			pct,
			label: `${(accrued / div).toFixed(1)} / ${(target / div).toFixed(0)} ${unitLabel}`,
		};
	}
</script>

<div class="page">
	<header class="page-header">
		<p class="subtitle">
			Track shoes and bikes. Tag runs with the gear you wore on the run-detail page;
			retirement targets nudge you when a pair crosses its planned mileage.
		</p>
	</header>

	<div class="tabs">
		<button
			class="tab"
			class:active={activeTab === 'shoe'}
			onclick={() => (activeTab = 'shoe')}
		>
			<span class="material-symbols">directions_run</span> Shoes
		</button>
		<button
			class="tab"
			class:active={activeTab === 'bike'}
			onclick={() => (activeTab = 'bike')}
		>
			<span class="material-symbols">directions_bike</span> Bikes
		</button>
		<div class="spacer"></div>
		<button
			class="btn-primary"
			onclick={() => {
				resetForm();
				showCreate = true;
			}}
		>
			+ New {activeTab === 'shoe' ? 'shoes' : 'bike'}
		</button>
	</div>

	{#if loading}
		<p class="muted">Loading gear…</p>
	{:else if visible.length === 0}
		<div class="empty">
			<span class="material-symbols">
				{activeTab === 'shoe' ? 'directions_run' : 'directions_bike'}
			</span>
			<p>
				No {activeTab === 'shoe' ? 'shoes' : 'bikes'} yet. Add a pair to start tracking mileage.
			</p>
		</div>
	{:else}
		{#if active.length > 0}
			<ul class="gear-list">
				{#each active as g (g.id)}
					{@const prog = progressFor(g)}
					<li class="gear-row">
						<button class="gear-main" onclick={() => openEdit(g)}>
							<div class="gear-name">
								<strong>{g.name}</strong>
								{#if g.brand || g.model}
									<span class="muted">{[g.brand, g.model].filter(Boolean).join(' ')}</span>
								{/if}
							</div>
							{#if g.target_distance_m}
								<div class="bar">
									<div class="bar-fill" style="width: {prog.pct}%"></div>
								</div>
							{/if}
							<div class="gear-meta">
								<span>{prog.label}</span>
								<span class="muted">{g.run_count} run{g.run_count === 1 ? '' : 's'}</span>
							</div>
						</button>
						<div class="gear-actions">
							<button class="btn-outline btn-sm" onclick={() => handleRetire(g)}>
								Retire
							</button>
							<button class="btn-danger btn-sm" onclick={() => (confirmingDelete = g)}>
								Delete
							</button>
						</div>
					</li>
				{/each}
			</ul>
		{/if}

		{#if retired.length > 0}
			<h3 class="section-title">Retired</h3>
			<ul class="gear-list retired-list">
				{#each retired as g (g.id)}
					{@const prog = progressFor(g)}
					<li class="gear-row retired">
						<button class="gear-main" onclick={() => openEdit(g)}>
							<div class="gear-name">
								<strong>{g.name}</strong>
								{#if g.brand || g.model}
									<span class="muted">{[g.brand, g.model].filter(Boolean).join(' ')}</span>
								{/if}
							</div>
							<div class="gear-meta">
								<span>{prog.label}</span>
								<span class="muted">retired {g.retired_at}</span>
							</div>
						</button>
						<div class="gear-actions">
							<button class="btn-outline btn-sm" onclick={() => handleRetire(g)}>
								Restore
							</button>
							<button class="btn-danger btn-sm" onclick={() => (confirmingDelete = g)}>
								Delete
							</button>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

<Modal
	open={showCreate || editingId !== null}
	onclose={() => {
		showCreate = false;
		resetForm();
	}}
	title={editingId ? 'Edit gear' : `Add ${activeTab === 'shoe' ? 'shoes' : 'bike'}`}
>
	<form
		class="gear-form"
		onsubmit={(e) => {
			e.preventDefault();
			handleSave();
		}}
	>
		<label>
			Name
			<input type="text" bind:value={formName} maxlength="80" required placeholder="Pegasus 39" />
		</label>
		<div class="row">
			<label>
				Brand
				<input type="text" bind:value={formBrand} maxlength="60" placeholder="Nike" />
			</label>
			<label>
				Model
				<input type="text" bind:value={formModel} maxlength="60" placeholder="Air Zoom Pegasus 39" />
			</label>
		</div>
		<div class="row">
			<label>
				Bought
				<input type="date" bind:value={formPurchased} />
			</label>
			<label>
				Retirement target ({getUnit()})
				<input type="number" min="1" bind:value={formTargetDisplay} placeholder="500" />
			</label>
		</div>
		<label>
			Notes
			<textarea bind:value={formNotes} maxlength="500" rows="3"></textarea>
		</label>
		<footer>
			<button class="btn-outline" type="button" onclick={() => { showCreate = false; resetForm(); }}>
				Cancel
			</button>
			<button class="btn-primary" type="submit" disabled={saving || !formName.trim()}>
				{saving ? 'Saving…' : editingId ? 'Save' : 'Add'}
			</button>
		</footer>
	</form>
</Modal>

<ConfirmDialog
	open={confirmingDelete !== null}
	title="Delete gear?"
	message={confirmingDelete
		? `Delete "${confirmingDelete.name}"? Mileage history on past runs will be lost. To keep records, retire instead.`
		: ''}
	confirmLabel="Delete"
	danger={true}
	onconfirm={handleDelete}
	oncancel={() => (confirmingDelete = null)}
/>

<style>
	.page {
		max-width: 64rem;
		padding: var(--space-xl) var(--space-2xl);
	}
	.page-header .subtitle {
		color: var(--color-text-secondary);
		margin-bottom: var(--space-lg);
	}
	.tabs {
		display: flex;
		align-items: center;
		gap: 0.25rem;
		border-bottom: 1px solid var(--color-border);
		margin-bottom: var(--space-lg);
	}
	.tab {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.6rem 1rem;
		background: transparent;
		border: none;
		border-bottom: 2px solid transparent;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-weight: 500;
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.tab:hover { color: var(--color-text); }
	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
		font-weight: 600;
	}
	.spacer { flex: 1; }
	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: var(--space-2xl);
		color: var(--color-text-tertiary);
	}
	.empty .material-symbols {
		font-size: 3rem;
		margin-bottom: var(--space-md);
	}
	.gear-list {
		list-style: none;
		padding: 0;
		margin: 0 0 var(--space-xl) 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.gear-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.gear-row.retired { opacity: 0.65; }
	.gear-main {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		text-align: left;
		background: transparent;
		border: none;
		padding: 0;
		cursor: pointer;
		min-width: 0;
	}
	.gear-name {
		display: flex;
		gap: 0.5rem;
		align-items: baseline;
		flex-wrap: wrap;
	}
	.gear-meta {
		display: flex;
		justify-content: space-between;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.muted { color: var(--color-text-tertiary); font-weight: normal; font-size: 0.85rem; }
	.bar {
		height: 6px;
		background: var(--color-bg-tertiary);
		border-radius: 3px;
		overflow: hidden;
	}
	.bar-fill {
		height: 100%;
		background: var(--color-primary);
		transition: width var(--transition-base);
	}
	.gear-actions {
		display: flex;
		gap: 0.4rem;
		flex-shrink: 0;
	}
	.section-title {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		margin: var(--space-lg) 0 var(--space-sm) 0;
	}
	.gear-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.gear-form label {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.gear-form input, .gear-form textarea {
		padding: 0.5rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.gear-form .row {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-md);
	}
	.gear-form footer {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
		margin-top: var(--space-sm);
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-size: 1.1em;
		vertical-align: middle;
	}
</style>
