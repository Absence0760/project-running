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
		setDefaultGear,
		fetchGearWearLogs,
		addGearWearLog,
		deleteGearWearLog,
		type GearKind,
		type GearWithDistance,
		type GearWearArea,
		type GearWearLog,
	} from '$lib/core/data';
	import { getUnit } from '$lib/format/units.svelte';
	import { gearWear } from '$lib/gear/gear_wear';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

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

	// Wear log — loaded lazily when the edit modal opens for an existing item.
	let wearLogs = $state<GearWearLog[]>([]);
	let wearLogLoading = $state(false);
	let wearNote = $state('');
	let wearArea = $state<GearWearArea | ''>('');
	let addingWear = $state(false);

	const WEAR_AREAS: GearWearArea[] = ['outsole', 'midsole', 'upper', 'other'];
	function wearAreaLabel(area: GearWearArea): string {
		switch (area) {
			case 'outsole': return t('settingsGear.wearLogAreaOutsole');
			case 'midsole': return t('settingsGear.wearLogAreaMidsole');
			case 'upper': return t('settingsGear.wearLogAreaUpper');
			case 'other': return t('settingsGear.wearLogAreaOther');
		}
	}

	async function loadWearLogs(gearId: string) {
		wearLogLoading = true;
		try {
			wearLogs = await fetchGearWearLogs(gearId);
		} finally {
			wearLogLoading = false;
		}
	}

	async function handleAddWear() {
		const note = wearNote.trim();
		if (!editingId || !note) return;
		addingWear = true;
		try {
			const created = await addGearWearLog({
				gearId: editingId,
				note,
				area: wearArea || null,
			});
			wearLogs = [created, ...wearLogs];
			wearNote = '';
			wearArea = '';
		} catch (e) {
			showToast(t('settingsGear.wearLogAddFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			addingWear = false;
		}
	}

	async function handleDeleteWear(log: GearWearLog) {
		try {
			await deleteGearWearLog(log.id);
			wearLogs = wearLogs.filter((l) => l.id !== log.id);
		} catch (e) {
			showToast(t('settingsGear.wearLogDeleteFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	// Rotations — named multi-pair groupings, distinct from the single
	// `is_default` current pair. A rotation can span both shoes and bikes
	// in principle, so the rotation section + filter are not tab-scoped.
	let rotations = $state<GearRotationWithMembers[]>([]);
	let rotationFilter = $state<string | null>(null);
	let newRotationName = $state('');
	let creatingRotation = $state(false);
	let renamingRotation = $state<GearRotationWithMembers | null>(null);
	let renameRotationName = $state('');
	let confirmingRotationDelete = $state<GearRotationWithMembers | null>(null);
	// Member-assignment modal: the rotation being edited + the working set.
	let managingRotation = $state<GearRotationWithMembers | null>(null);
	let managingMemberIds = $state<Set<string>>(new Set());
	let savingMembers = $state(false);

	async function reloadRotations() {
		rotations = await fetchMyGearRotations();
		// Drop a stale filter if its rotation was deleted.
		if (rotationFilter && !rotations.some((r) => r.id === rotationFilter)) {
			rotationFilter = null;
		}
	}

	async function handleCreateRotation() {
		const name = newRotationName.trim();
		if (!name) return;
		creatingRotation = true;
		try {
			await createGearRotation(name);
			newRotationName = '';
			await reloadRotations();
		} catch (e) {
			showToast(t('settingsGear.rotationSaveFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			creatingRotation = false;
		}
	}

	async function handleRenameRotation() {
		const r = renamingRotation;
		const name = renameRotationName.trim();
		if (!r || !name) return;
		try {
			await renameGearRotation(r.id, name);
			renamingRotation = null;
			renameRotationName = '';
			await reloadRotations();
		} catch (e) {
			showToast(t('settingsGear.rotationSaveFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	async function handleDeleteRotation() {
		const r = confirmingRotationDelete;
		if (!r) return;
		try {
			await deleteGearRotation(r.id);
			await reloadRotations();
		} catch (e) {
			showToast(t('settingsGear.rotationSaveFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			confirmingRotationDelete = null;
		}
	}

	function openManageRotation(r: GearRotationWithMembers) {
		managingRotation = r;
		managingMemberIds = new Set(r.gear_ids);
	}

	function toggleMember(gearId: string) {
		const next = new Set(managingMemberIds);
		if (next.has(gearId)) next.delete(gearId);
		else next.add(gearId);
		managingMemberIds = next;
	}

	async function handleSaveMembers() {
		const r = managingRotation;
		if (!r) return;
		savingMembers = true;
		try {
			await setGearRotationMembers(r.id, [...managingMemberIds]);
			managingRotation = null;
			await reloadRotations();
		} catch (e) {
			showToast(t('settingsGear.rotationSaveFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			savingMembers = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) return;
		gear = await fetchMyGear();
		await reloadRotations();
		loading = false;
	});

	// The set of gear ids in the active rotation filter (null filter → all).
	const filterMemberIds = $derived(
		rotationFilter == null
			? null
			: new Set(rotations.find((r) => r.id === rotationFilter)?.gear_ids ?? []),
	);
	const visible = $derived(
		gear
			.filter((g) => g.kind === activeTab)
			.filter((g) => filterMemberIds == null || filterMemberIds.has(g.id)),
	);
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
		wearLogs = [];
		wearNote = '';
		wearArea = '';
	}

	function openEdit(g: GearWithDistance) {
		editingId = g.id;
		formName = g.name;
		formBrand = g.brand ?? '';
		formModel = g.model ?? '';
		formPurchased = g.purchased_at ?? '';
		formTargetDisplay = metresToTargetDisplay(g.target_distance_m);
		formNotes = g.notes ?? '';
		wearLogs = [];
		wearNote = '';
		wearArea = '';
		loadWearLogs(g.id);
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
			showToast(t('settingsGear.saveFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			saving = false;
		}
	}

	async function handleToggleDefault(g: GearWithDistance) {
		try {
			// If this is already the default, clear it (no current gear).
			// Otherwise mark it — setDefaultGear handles unsetting any
			// sibling of the same kind first so the partial-unique index
			// stays honoured.
			await setDefaultGear(g.is_default ? null : g.id, g.kind);
			gear = await fetchMyGear();
		} catch (e) {
			showToast(t('settingsGear.failed', { error: e instanceof Error ? e.message : String(e) }), 'error');
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
			showToast(t('settingsGear.failed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	async function handleDelete() {
		if (!confirmingDelete) return;
		try {
			await deleteGear(confirmingDelete.id);
			gear = await fetchMyGear();
		} catch (e) {
			showToast(t('settingsGear.deleteFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
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
	<header class="page-head">
		<p class="kicker">{t('shell.settings')}</p>
		<h1>{t('settingsGear.title')}</h1>
		<p class="tagline">
			{t('settingsGear.tagline')}
		</p>
	</header>

	<div class="tabs">
		<button
			class="tab"
			class:active={activeTab === 'shoe'}
			onclick={() => (activeTab = 'shoe')}
		>
			<span class="material-symbols" aria-hidden="true">directions_run</span> {t('settingsGear.tabShoes')}
		</button>
		<button
			class="tab"
			class:active={activeTab === 'bike'}
			onclick={() => (activeTab = 'bike')}
		>
			<span class="material-symbols" aria-hidden="true">directions_bike</span> {t('settingsGear.tabBikes')}
		</button>
		<div class="spacer"></div>
		{#if rotations.length > 0}
			<label class="rotation-filter">
				<span class="sr-only">{t('settingsGear.rotationFilterLabel')}</span>
				<select bind:value={rotationFilter} aria-label={t('settingsGear.rotationFilterLabel')}>
					<option value={null}>{t('settingsGear.rotationFilterAll')}</option>
					{#each rotations as r (r.id)}
						<option value={r.id}>{r.name}</option>
					{/each}
				</select>
			</label>
		{/if}
		<button
			class="btn-primary"
			onclick={() => {
				resetForm();
				showCreate = true;
			}}
		>
			{activeTab === 'shoe' ? t('settingsGear.newShoes') : t('settingsGear.newBike')}
		</button>
	</div>

	{#if loading}
		<div class="skeleton-stack" aria-hidden="true">
			{#each Array(3) as _, i (i)}
				<div class="skel-row">
					<div class="skel-info">
						<span class="skel skel-line skel-w-40"></span>
						<span class="skel skel-bar"></span>
						<span class="skel skel-line skel-w-30"></span>
					</div>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{t('settingsGear.loadingGear')}</p>
	{:else if visible.length === 0}
		<section class="card empty-card">
			<span class="material-symbols empty-icon" aria-hidden="true">
				{activeTab === 'shoe' ? 'directions_run' : 'directions_bike'}
			</span>
			<h3>{activeTab === 'shoe' ? t('settingsGear.emptyShoesTitle') : t('settingsGear.emptyBikesTitle')}</h3>
			<p class="empty-text">
				{#if activeTab === 'shoe'}
					{t('settingsGear.emptyShoesText')}
				{:else}
					{t('settingsGear.emptyBikesText')}
				{/if}
			</p>
			<button
				class="btn btn-primary"
				type="button"
				onclick={() => {
					resetForm();
					showCreate = true;
				}}
			>
				<span class="material-symbols" aria-hidden="true">add</span>
				{activeTab === 'shoe' ? t('settingsGear.addShoes') : t('settingsGear.addBike')}
			</button>
		</section>
	{:else}
		{#if active.length > 0}
			<ul class="gear-list">
				{#each active as g (g.id)}
					{@const prog = progressFor(g)}
					{@const wear = gearWear(g.total_distance_m, g.target_distance_m)}
					<li class="gear-row" class:is-default={g.is_default}>
						<button class="gear-main" onclick={() => openEdit(g)}>
							<div class="gear-name">
								<strong>{g.name}</strong>
								{#if g.is_default}
									<span class="default-pill" title={t('settingsGear.currentPillTitle')}>{t('settingsGear.currentPill')}</span>
								{/if}
								{#if wear.status === 'worn'}
									<span class="wear-badge wear-worn" data-testid="wear-badge">
										<span class="material-symbols" aria-hidden="true">change_circle</span>
										{t('settingsGear.wearWorn')}
									</span>
								{:else if wear.status === 'due'}
									<span class="wear-badge wear-due" data-testid="wear-badge">
										<span class="material-symbols" aria-hidden="true">schedule</span>
										{t('settingsGear.wearDue')}
									</span>
								{/if}
								{#if g.brand || g.model}
									<span class="muted">{[g.brand, g.model].filter(Boolean).join(' ')}</span>
								{/if}
							</div>
							{#if g.target_distance_m}
								<div class="bar">
									<div class="bar-fill wear-{wear.status}" style="width: {prog.pct}%"></div>
								</div>
							{/if}
							<div class="gear-meta">
								<span>{prog.label}</span>
								<span class="muted">{t(g.run_count === 1 ? 'settingsGear.runCountOne' : 'settingsGear.runCountMany', { n: g.run_count })}</span>
							</div>
						</button>
						<div class="gear-actions">
							<button
								type="button"
								class="star-btn"
								class:active={g.is_default}
								aria-label={g.is_default
									? t('settingsGear.unmarkCurrent', { name: g.name ?? '' })
									: t('settingsGear.markCurrent', { name: g.name ?? '' })}
								aria-pressed={g.is_default}
								onclick={() => handleToggleDefault(g)}
							>
								<span class="material-symbols" aria-hidden="true">
									{g.is_default ? 'star' : 'star_outline'}
								</span>
							</button>
							<button class="btn-outline btn-sm" onclick={() => handleRetire(g)}>
								{t('settingsGear.retire')}
							</button>
							<button class="btn-danger btn-sm" onclick={() => (confirmingDelete = g)}>
								{t('settingsGear.delete')}
							</button>
						</div>
					</li>
				{/each}
			</ul>
		{/if}

		{#if retired.length > 0}
			<h3 class="section-title">{t('settingsGear.retiredSection')}</h3>
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
								<span class="muted">{t('settingsGear.retiredOn', { date: g.retired_at ?? '' })}</span>
							</div>
						</button>
						<div class="gear-actions">
							<button class="btn-outline btn-sm" onclick={() => handleRetire(g)}>
								{t('settingsGear.restore')}
							</button>
							<button class="btn-danger btn-sm" onclick={() => (confirmingDelete = g)}>
								{t('settingsGear.delete')}
							</button>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}

	{#if !loading}
		<section class="rotations">
			<h2 class="section-title">{t('settingsGear.rotationsHeading')}</h2>
			<p class="rotations-hint">{t('settingsGear.rotationsHint')}</p>

			<form
				class="rotation-create"
				onsubmit={(e) => {
					e.preventDefault();
					handleCreateRotation();
				}}
			>
				<input
					type="text"
					bind:value={newRotationName}
					maxlength="60"
					placeholder={t('settingsGear.rotationNamePlaceholder')}
					aria-label={t('settingsGear.rotationName')}
				/>
				<button class="btn-primary btn-sm" type="submit" disabled={creatingRotation || !newRotationName.trim()}>
					{t('settingsGear.rotationCreate')}
				</button>
			</form>

			{#if rotations.length === 0}
				<p class="rotations-empty">{t('settingsGear.rotationsEmpty')}</p>
			{:else}
				<ul class="rotation-list">
					{#each rotations as r (r.id)}
						<li class="rotation-row">
							<div class="rotation-info">
								<strong>{r.name}</strong>
								<span class="muted">
									{t(r.gear_ids.length === 1 ? 'settingsGear.rotationMemberCount' : 'settingsGear.rotationMemberCountMany', { n: r.gear_ids.length })}
								</span>
							</div>
							<div class="rotation-actions">
								<button class="btn-outline btn-sm" onclick={() => openManageRotation(r)}>
									{t('settingsGear.rotationManage')}
								</button>
								<button
									class="btn-outline btn-sm"
									onclick={() => {
										renamingRotation = r;
										renameRotationName = r.name;
									}}
								>
									{t('settingsGear.rotationRename')}
								</button>
								<button class="btn-danger btn-sm" onclick={() => (confirmingRotationDelete = r)}>
									{t('settingsGear.delete')}
								</button>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}
</div>

<Modal
	open={managingRotation !== null}
	onclose={() => (managingRotation = null)}
	title={managingRotation ? t('settingsGear.rotationManageTitle', { name: managingRotation.name }) : ''}
>
	{#if gear.length === 0}
		<p class="rotations-empty">{t('settingsGear.rotationNoGear')}</p>
	{:else}
		<ul class="member-list">
			{#each gear as g (g.id)}
				<li>
					<label class="member-row">
						<input
							type="checkbox"
							checked={managingMemberIds.has(g.id)}
							onchange={() => toggleMember(g.id)}
						/>
						<span class="member-name">
							{g.name}
							{#if g.brand || g.model}
								<span class="muted">{[g.brand, g.model].filter(Boolean).join(' ')}</span>
							{/if}
							{#if g.retired_at}
								<span class="muted">· {t('settingsGear.retiredSection')}</span>
							{/if}
						</span>
					</label>
				</li>
			{/each}
		</ul>
	{/if}
	<footer class="member-footer">
		<button class="btn-outline" type="button" onclick={() => (managingRotation = null)}>
			{t('settingsGear.cancel')}
		</button>
		<button class="btn-primary" type="button" disabled={savingMembers} onclick={handleSaveMembers}>
			{savingMembers ? t('settingsGear.saving') : t('settingsGear.rotationDone')}
		</button>
	</footer>
</Modal>

<Modal
	open={renamingRotation !== null}
	onclose={() => (renamingRotation = null)}
	title={t('settingsGear.rotationRename')}
>
	<form
		class="gear-form"
		onsubmit={(e) => {
			e.preventDefault();
			handleRenameRotation();
		}}
	>
		<label>
			{t('settingsGear.rotationName')}
			<input type="text" bind:value={renameRotationName} maxlength="60" required />
		</label>
		<footer>
			<button class="btn-outline" type="button" onclick={() => (renamingRotation = null)}>
				{t('settingsGear.cancel')}
			</button>
			<button class="btn-primary" type="submit" disabled={!renameRotationName.trim()}>
				{t('settingsGear.save')}
			</button>
		</footer>
	</form>
</Modal>

<ConfirmDialog
	open={confirmingRotationDelete !== null}
	title={t('settingsGear.rotationDeleteConfirmTitle')}
	message={confirmingRotationDelete
		? t('settingsGear.rotationDeleteConfirmMessage', { name: confirmingRotationDelete.name })
		: ''}
	confirmLabel={t('settingsGear.delete')}
	danger={true}
	onconfirm={handleDeleteRotation}
	oncancel={() => (confirmingRotationDelete = null)}
/>

<Modal
	open={showCreate || editingId !== null}
	onclose={() => {
		showCreate = false;
		resetForm();
	}}
	title={editingId
		? t('settingsGear.editTitle')
		: activeTab === 'shoe'
			? t('settingsGear.addShoes')
			: t('settingsGear.addBike')}
>
	<form
		class="gear-form"
		onsubmit={(e) => {
			e.preventDefault();
			handleSave();
		}}
	>
		<label>
			{t('settingsGear.fieldName')}
			<input type="text" bind:value={formName} maxlength="80" required placeholder="Pegasus 39" />
		</label>
		<div class="row">
			<label>
				{t('settingsGear.fieldBrand')}
				<input type="text" bind:value={formBrand} maxlength="60" placeholder="Nike" />
			</label>
			<label>
				{t('settingsGear.fieldModel')}
				<input type="text" bind:value={formModel} maxlength="60" placeholder="Air Zoom Pegasus 39" />
			</label>
		</div>
		<div class="row">
			<label>
				{t('settingsGear.fieldBought')}
				<input type="date" bind:value={formPurchased} />
			</label>
			<label>
				{t('settingsGear.fieldTarget', { unit: getUnit() })}
				<input type="number" min="1" bind:value={formTargetDisplay} placeholder="500" />
			</label>
		</div>
		<label>
			{t('settingsGear.fieldNotes')}
			<textarea bind:value={formNotes} maxlength="500" rows="3"></textarea>
		</label>

		{#if editingId}
			<section class="wear-log" data-testid="wear-log">
				<h4>{t('settingsGear.wearLogHeading')}</h4>
				<p class="wear-hint">{t('settingsGear.wearLogHint')}</p>

				<div class="wear-add">
					<div class="wear-add-row">
						<input
							type="text"
							class="wear-note-input"
							maxlength="500"
							bind:value={wearNote}
							placeholder={t('settingsGear.wearLogNotePlaceholder')}
							aria-label={t('settingsGear.wearLogAddNote')}
						/>
						<select bind:value={wearArea} aria-label={t('settingsGear.wearLogArea')}>
							<option value="">{t('settingsGear.wearLogAreaNone')}</option>
							{#each WEAR_AREAS as area (area)}
								<option value={area}>{wearAreaLabel(area)}</option>
							{/each}
						</select>
					</div>
					<button
						type="button"
						class="btn-outline btn-sm wear-add-btn"
						disabled={addingWear || !wearNote.trim()}
						onclick={handleAddWear}
					>
						{addingWear ? t('settingsGear.wearLogAdding') : t('settingsGear.wearLogAdd')}
					</button>
				</div>

				{#if wearLogLoading}
					<p class="wear-empty">{t('settingsGear.loadingGear')}</p>
				{:else if wearLogs.length === 0}
					<p class="wear-empty">{t('settingsGear.wearLogEmpty')}</p>
				{:else}
					<ul class="wear-list">
						{#each wearLogs as log (log.id)}
							<li class="wear-item">
								<div class="wear-item-main">
									<div class="wear-item-meta">
										<span class="wear-date">{log.logged_on}</span>
										{#if log.area}
											<span class="wear-area-pill">{wearAreaLabel(log.area)}</span>
										{/if}
									</div>
									<span class="wear-text">{log.note}</span>
								</div>
								<button
									type="button"
									class="wear-del"
									aria-label={t('settingsGear.wearLogDelete')}
									onclick={() => handleDeleteWear(log)}
								>
									<span class="material-symbols" aria-hidden="true">close</span>
								</button>
							</li>
						{/each}
					</ul>
				{/if}
			</section>
		{/if}

		<footer>
			<button class="btn-outline" type="button" onclick={() => { showCreate = false; resetForm(); }}>
				{t('settingsGear.cancel')}
			</button>
			<button class="btn-primary" type="submit" disabled={saving || !formName.trim()}>
				{saving ? t('settingsGear.saving') : editingId ? t('settingsGear.save') : t('settingsGear.add')}
			</button>
		</footer>
	</form>
</Modal>

<ConfirmDialog
	open={confirmingDelete !== null}
	title={t('settingsGear.deleteConfirmTitle')}
	message={confirmingDelete
		? t('settingsGear.deleteConfirmMessage', { name: confirmingDelete.name ?? '' })
		: ''}
	confirmLabel={t('settingsGear.delete')}
	danger={true}
	onconfirm={handleDelete}
	oncancel={() => (confirmingDelete = null)}
/>

<style>
	.page {
		max-width: 64rem;
		padding: var(--space-xl) var(--space-2xl);
	}
	.page-head { margin-bottom: var(--space-xl); }
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	.page-head h1 { font-size: 1.6rem; font-weight: 700; margin: 0 0 var(--space-xs); }
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 44rem;
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
		font-family: 'Material Symbols Outlined';
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

	.skeleton-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.skel-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		pointer-events: none;
	}
	.skel-info { flex: 1; display: flex; flex-direction: column; gap: 0.4rem; }
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
	.skel-line { height: 0.85rem; }
	.skel-bar { height: 0.4rem; border-radius: 3px; }
	.skel-w-30 { width: 30%; }
	.skel-w-40 { width: 40%; }
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
		text-align: start;
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
	/* Wear status recolours the fill so a worn shoe reads at a glance,
	   not just by reading the "X / Y km" label. */
	.bar-fill.wear-due {
		background: var(--color-warning);
	}
	.bar-fill.wear-worn {
		background: var(--color-danger);
	}

	.wear-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.02em;
		padding: 0.1rem 0.4rem;
		border-radius: var(--radius-sm);
		white-space: nowrap;
	}
	.wear-badge .material-symbols {
		font-size: 0.85rem;
	}
	/* Solid "-strong" fill + white text: those tokens are theme-independent
	   and pinned AA-with-white by contrast_guard.test.ts, so the badge stays
	   legible in dark mode (a tinted bg + -strong *text* goes invisible on
	   dark — the -strong tokens are background colours, not text colours). */
	.wear-due {
		color: #fff;
		background: var(--color-warning-strong);
	}
	.wear-worn {
		color: #fff;
		background: var(--color-danger-strong);
	}
	.gear-actions {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-shrink: 0;
	}
	.gear-row.is-default {
		border-color: var(--color-primary);
		box-shadow: inset 3px 0 0 var(--color-primary);
	}
	.default-pill {
		display: inline-flex;
		align-items: center;
		padding: 0.1rem 0.5rem;
		font-size: 0.65rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-primary);
		background: var(--color-primary-light);
		border-radius: 999px;
		margin-inline-start: 0.5rem;
	}
	.star-btn {
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-sm);
		width: 2rem;
		height: 2rem;
		padding: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		color: var(--color-text-tertiary);
		transition: color var(--transition-fast), background var(--transition-fast);
	}
	.star-btn:hover {
		color: var(--color-primary);
		background: var(--color-bg-tertiary);
	}
	.star-btn.active {
		color: var(--color-primary);
	}
	.star-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.3rem;
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

	.wear-log {
		border-top: 1px solid var(--color-border);
		padding-top: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.wear-log h4 {
		margin: 0;
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.wear-hint {
		margin: 0;
		font-size: 0.8rem;
		line-height: 1.45;
		color: var(--color-text-tertiary);
	}
	.wear-add {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.wear-add-row {
		display: flex;
		gap: var(--space-sm);
	}
	.wear-note-input { flex: 1; min-width: 0; }
	.wear-add-row select {
		padding: 0.5rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.wear-add-btn { align-self: flex-start; }
	.wear-empty {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
	}
	.wear-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.wear-item {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		padding: var(--space-xs) var(--space-sm);
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm);
	}
	.wear-item-main {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.wear-item-meta {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.wear-date {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.wear-area-pill {
		font-size: 0.65rem;
		font-weight: 700;
		letter-spacing: 0.03em;
		text-transform: uppercase;
		padding: 0.05rem 0.4rem;
		border-radius: 999px;
		color: var(--color-text-secondary);
		background: var(--color-surface);
	}
	.wear-text {
		font-size: 0.9rem;
		color: var(--color-text);
		overflow-wrap: anywhere;
	}
	.wear-del {
		flex-shrink: 0;
		background: transparent;
		border: none;
		cursor: pointer;
		color: var(--color-text-tertiary);
		padding: 0.15rem;
		border-radius: var(--radius-sm);
		display: inline-flex;
	}
	.wear-del:hover { color: var(--color-danger); background: var(--color-surface); }
	.wear-del .material-symbols { font-size: 1rem; }

	.rotation-filter select {
		padding: 0.4rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.rotations {
		margin-top: var(--space-2xl);
		padding-top: var(--space-xl);
		border-top: 1px solid var(--color-border);
	}
	.rotations-hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		line-height: 1.5;
		margin: 0 0 var(--space-md);
		max-width: 44rem;
	}
	.rotation-create {
		display: flex;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
		max-width: 30rem;
	}
	.rotation-create input {
		flex: 1;
		padding: 0.5rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.rotations-empty {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		margin: 0;
	}
	.rotation-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.rotation-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.rotation-info {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 0;
	}
	.rotation-actions {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-shrink: 0;
		flex-wrap: wrap;
		justify-content: flex-end;
	}
	.member-list {
		list-style: none;
		padding: 0;
		margin: 0 0 var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.member-row {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.5rem 0.4rem;
		cursor: pointer;
		font-size: 0.9rem;
	}
	.member-name {
		display: flex;
		gap: 0.4rem;
		align-items: baseline;
		flex-wrap: wrap;
	}
	.member-footer {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
		margin-top: var(--space-sm);
	}
</style>
