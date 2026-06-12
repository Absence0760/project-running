<script lang="ts">
	import { onMount } from 'svelte';
	import {
		createSessionPlan,
		updateSessionPlan,
		fetchSessionMovementNames,
		type SessionPlanInput,
		type SessionPlanItemInput
	} from '$lib/core/data';
	import type { SessionPlanWithItems } from '$lib/types';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import {
		expandSessionSteps,
		type SessionItemKind,
		type SessionPlanInput as ExpandInput
	} from '$lib/social/session_steps';

	interface Props {
		existing?: SessionPlanWithItems | null;
		oncreated?: (id: string) => void;
		onupdated?: () => void;
		oncancel: () => void;
	}

	let { existing = null, oncreated, onupdated, oncancel }: Props = $props();

	type EditBlock = { name: string };
	type EditItem = {
		movement_name: string;
		kind: SessionItemKind;
		duration_s: string;
		reps: string;
		per_side: boolean;
		tempo: string;
		cue: string;
		block_index: number | null;
	};

	function initBlocks(src: SessionPlanWithItems | null): EditBlock[] {
		if (!src) return [];
		return [...src.blocks]
			.sort((a, b) => a.position - b.position)
			.map((b) => ({ name: b.name ?? '' }));
	}

	function initItems(src: SessionPlanWithItems | null): EditItem[] {
		if (!src || src.items.length === 0) {
			return [emptyItem()];
		}
		const orderedBlocks = [...src.blocks].sort((a, b) => a.position - b.position);
		const blockIndexById = new Map(orderedBlocks.map((b, i) => [b.id, i]));
		return [...src.items]
			.sort((a, b) => a.position - b.position)
			.map((it) => ({
				movement_name: it.movement_name,
				kind: it.kind,
				duration_s: it.duration_s == null ? '' : String(it.duration_s),
				reps: it.reps == null ? '' : String(it.reps),
				per_side: it.per_side,
				tempo: it.tempo ?? '',
				cue: it.cue ?? '',
				block_index: it.block_id == null ? null : (blockIndexById.get(it.block_id) ?? null)
			}));
	}

	function emptyItem(): EditItem {
		return {
			movement_name: '',
			kind: 'hold',
			duration_s: '',
			reps: '',
			per_side: false,
			tempo: '',
			cue: '',
			block_index: null
		};
	}

	let title = $state(existing?.title ?? '');
	let discipline = $state(existing?.discipline ?? '');
	let equipment = $state(existing?.equipment ?? '');
	let isPublic = $state(existing?.is_public ?? false);
	let blocks = $state<EditBlock[]>(initBlocks(existing));
	let items = $state<EditItem[]>(initItems(existing));
	let saving = $state(false);
	let movementSuggestions = $state<string[]>([]);

	onMount(async () => {
		movementSuggestions = await fetchSessionMovementNames();
	});

	function parseIntOrNull(raw: string): number | null {
		const n = Number.parseInt(raw, 10);
		return Number.isFinite(n) && n > 0 ? n : null;
	}

	const estMinutes = $derived.by(() => {
		const expandInput: ExpandInput = {
			blocks: blocks.map((_, i) => ({ id: `b${i}`, position: i, name: null })),
			items: items.map((it, i) => ({
				id: `i${i}`,
				block_id: it.block_index === null ? null : `b${it.block_index}`,
				position: i,
				movement_name: it.movement_name,
				kind: it.kind,
				duration_s: parseIntOrNull(it.duration_s),
				reps: parseIntOrNull(it.reps),
				per_side: it.per_side,
				tempo: null,
				cue: null
			}))
		};
		return Math.round(expandSessionSteps(expandInput).totalS / 60);
	});

	function addBlock() {
		blocks = [...blocks, { name: '' }];
	}

	function removeBlock(index: number) {
		blocks = blocks.filter((_, i) => i !== index);
		// Re-point items: drop the removed block, shift higher indices down.
		items = items.map((it) => {
			if (it.block_index === null) return it;
			if (it.block_index === index) return { ...it, block_index: null };
			if (it.block_index > index) return { ...it, block_index: it.block_index - 1 };
			return it;
		});
	}

	function addItem() {
		items = [...items, emptyItem()];
	}

	function removeItem(index: number) {
		items = items.filter((_, i) => i !== index);
		if (items.length === 0) items = [emptyItem()];
	}

	async function save() {
		const trimmedTitle = title.trim();
		if (!trimmedTitle) {
			showToast(t('session.titleRequired'), 'error');
			return;
		}
		const validItems = items.filter((it) => it.movement_name.trim() !== '');
		if (validItems.length === 0) {
			showToast(t('session.itemRequired'), 'error');
			return;
		}

		const itemInputs: SessionPlanItemInput[] = validItems.map((it) => ({
			movement_name: it.movement_name,
			kind: it.kind,
			duration_s: it.kind === 'reps' ? null : parseIntOrNull(it.duration_s),
			reps: it.kind === 'reps' ? parseIntOrNull(it.reps) : null,
			per_side: it.per_side,
			tempo: it.tempo.trim() || null,
			cue: it.cue.trim() || null,
			block_index: it.block_index
		}));

		const input: SessionPlanInput = {
			title: trimmedTitle,
			discipline: discipline.trim() || null,
			equipment: equipment.trim() || null,
			is_public: isPublic,
			club_id: existing?.club_id ?? null,
			est_duration_min: estMinutes > 0 ? estMinutes : null,
			blocks: blocks.map((b) => ({ name: b.name.trim() || null })),
			items: itemInputs
		};

		saving = true;
		try {
			if (existing) {
				await updateSessionPlan(existing.id, input);
				showToast(t('session.saved'), 'success');
				onupdated?.();
			} else {
				const id = await createSessionPlan(input);
				showToast(t('session.saved'), 'success');
				oncreated?.(id);
			}
		} catch (e) {
			console.error('session save failed', e);
			showToast(t('session.saveFailed'), 'error');
		} finally {
			saving = false;
		}
	}
</script>

<div class="session-editor">
	<datalist id="session-movement-suggestions">
		{#each movementSuggestions as s (s)}
			<option value={s}></option>
		{/each}
	</datalist>

	<label class="field">
		<span>{t('session.titleLabel')}</span>
		<input type="text" bind:value={title} maxlength="120" />
	</label>

	<div class="row">
		<label class="field">
			<span>{t('session.discipline')}</span>
			<input type="text" bind:value={discipline} placeholder={t('session.disciplinePlaceholder')} />
		</label>
		<label class="field">
			<span>{t('session.equipment')}</span>
			<input type="text" bind:value={equipment} placeholder={t('session.equipmentPlaceholder')} />
		</label>
	</div>

	<label class="checkbox">
		<input type="checkbox" bind:checked={isPublic} />
		<span>{t('session.makePublic')}</span>
	</label>

	<section>
		<header class="section-head">
			<h3>{t('session.blocks')}</h3>
			<button type="button" class="btn btn-sm btn-outline" onclick={addBlock}>
				{t('session.addBlock')}
			</button>
		</header>
		{#each blocks as block, bi (bi)}
			<div class="row block-row">
				<input
					type="text"
					bind:value={block.name}
					placeholder={t('session.blockNamePlaceholder')}
					aria-label={t('session.blockName')}
				/>
				<button
					type="button"
					class="btn btn-sm btn-danger"
					onclick={() => removeBlock(bi)}
					aria-label={t('session.removeBlock')}
				>
					&times;
				</button>
			</div>
		{/each}
	</section>

	<section>
		<header class="section-head">
			<h3>{t('session.items')}</h3>
			<button type="button" class="btn btn-sm btn-outline" onclick={addItem}>
				{t('session.addItem')}
			</button>
		</header>
		{#each items as item, ii (ii)}
			<div class="item-card">
				<div class="row">
					<input
						class="grow"
						type="text"
						list="session-movement-suggestions"
						bind:value={item.movement_name}
						placeholder={t('session.movementPlaceholder')}
						aria-label={t('session.movementName')}
					/>
					<button
						type="button"
						class="btn btn-sm btn-danger"
						onclick={() => removeItem(ii)}
						aria-label={t('session.removeItem')}
					>
						&times;
					</button>
				</div>
				<div class="row">
					<label class="field small">
						<span>{t('session.kind')}</span>
						<select bind:value={item.kind}>
							<option value="hold">{t('session.kindHold')}</option>
							<option value="reps">{t('session.kindReps')}</option>
							<option value="flow">{t('session.kindFlow')}</option>
						</select>
					</label>
					{#if item.kind === 'reps'}
						<label class="field small">
							<span>{t('session.reps')}</span>
							<input type="number" min="0" bind:value={item.reps} />
						</label>
					{:else}
						<label class="field small">
							<span>{t('session.durationSec')}</span>
							<input type="number" min="0" bind:value={item.duration_s} />
						</label>
					{/if}
					<label class="field small">
						<span>{t('session.inBlock')}</span>
						<select bind:value={item.block_index}>
							<option value={null}>{t('session.noBlock')}</option>
							{#each blocks as block, bi (bi)}
								<option value={bi}>{block.name.trim() || `#${bi + 1}`}</option>
							{/each}
						</select>
					</label>
				</div>
				<div class="row">
					<label class="checkbox">
						<input type="checkbox" bind:checked={item.per_side} />
						<span>{t('session.perSide')}</span>
					</label>
					<input
						class="grow"
						type="text"
						bind:value={item.tempo}
						placeholder={t('session.tempoPlaceholder')}
						aria-label={t('session.tempo')}
					/>
				</div>
				<input
					type="text"
					bind:value={item.cue}
					placeholder={t('session.cuePlaceholder')}
					aria-label={t('session.cue')}
				/>
			</div>
		{/each}
	</section>

	<p class="est">{t('session.estDuration', { minutes: estMinutes })}</p>

	<div class="actions">
		<button type="button" class="btn btn-secondary" onclick={oncancel} disabled={saving}>
			{t('session.cancel')}
		</button>
		<button type="button" class="btn btn-primary" onclick={save} disabled={saving}>
			{t('session.save')}
		</button>
	</div>
</div>

<style>
	.session-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		flex: 1;
	}
	.field span {
		font-size: 0.85rem;
		color: var(--text-muted);
	}
	.field.small {
		flex: 0 0 8rem;
	}
	.row {
		display: flex;
		gap: var(--space-sm);
		align-items: flex-end;
		flex-wrap: wrap;
	}
	.grow {
		flex: 1;
	}
	.checkbox {
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.section-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	.section-head h3 {
		margin: 0;
		font-size: 0.95rem;
	}
	.item-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding: var(--space-sm);
		border: 1px solid var(--border);
		border-radius: var(--radius-md);
	}
	.block-row {
		align-items: center;
	}
	.est {
		color: var(--text-muted);
		font-size: 0.9rem;
		margin: 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
</style>
