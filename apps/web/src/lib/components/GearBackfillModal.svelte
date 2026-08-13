<script lang="ts">
	import Modal from '$lib/components/Modal.svelte';
	import { addGearToRuns } from '$lib/core/data';
	import { formatDate } from '$lib/format/time';
	import { formatDistance } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { activityTypeIcon } from '$lib/runs/activity_type';
	import { showToast } from '$lib/stores/toast.svelte';

	interface BackfillCandidate {
		id: string;
		started_at: string;
		distance_m: number;
		activity_type?: string | null;
	}

	interface Props {
		open: boolean;
		gearId: string;
		gearName: string;
		gearKind: string;
		/// Already filtered + newest-first by `gearBackfillCandidates`.
		candidates: readonly BackfillCandidate[];
		onclose: () => void;
		/// Fired only after the write lands, with the number of runs attached.
		onattached: (count: number) => void;
	}

	let { open, gearId, gearName, gearKind, candidates, onclose, onattached }: Props =
		$props();

	// Everything starts checked: the runner registered gear they have been
	// using, so "all of them" is the common answer and unchecking the odd
	// outlier is less work than checking twenty rows. Tracking the EXCLUDED
	// ids rather than the included ones is what makes that the default
	// without copying the candidate list into state at construction.
	let deselected = $state<Set<string>>(new Set());
	let saving = $state(false);

	const selectedIds = $derived(
		candidates.filter((c) => !deselected.has(c.id)).map((c) => c.id),
	);
	const allSelected = $derived(candidates.length > 0 && deselected.size === 0);

	function toggle(id: string) {
		const next = new Set(deselected);
		if (next.has(id)) next.delete(id);
		else next.add(id);
		deselected = next;
	}

	function toggleAll() {
		deselected = allSelected ? new Set(candidates.map((c) => c.id)) : new Set();
	}

	async function attach() {
		if (selectedIds.length === 0) {
			onclose();
			return;
		}
		saving = true;
		try {
			const n = await addGearToRuns(gearId, selectedIds);
			onattached(n);
		} catch (e) {
			// Stay open on failure so the offer isn't lost — it only ever
			// appears once, right after the gear is created.
			saving = false;
			showToast(
				m('settingsGear.backfillAttachFailed', {
					error: e instanceof Error ? e.message : String(e),
				}),
				'error',
			);
		}
	}

	const bodyText = $derived(
		gearKind === 'bike'
			? m(
					candidates.length === 1
						? 'settingsGear.backfillBodyBikeOne'
						: 'settingsGear.backfillBodyBike',
					{ n: candidates.length },
				)
			: m(
					candidates.length === 1
						? 'settingsGear.backfillBodyShoeOne'
						: 'settingsGear.backfillBodyShoe',
					{ n: candidates.length },
				),
	);
</script>

<Modal
	{open}
	{onclose}
	title={m('settingsGear.backfillTitle', { name: gearName })}
	data-testid="gear-backfill-modal"
>
	<p class="backfill-body">{bodyText}</p>

	<div class="backfill-bulk">
		<label class="bulk-toggle">
			<input
				type="checkbox"
				checked={allSelected}
				disabled={saving}
				onchange={toggleAll}
			/>
			<span>{allSelected ? m('settingsGear.backfillSelectNone') : m('settingsGear.backfillSelectAll')}</span>
		</label>
		<span class="bulk-count" data-testid="gear-backfill-count">
			{m('settingsGear.backfillSelectedCount', {
				selected: selectedIds.length,
				total: candidates.length,
			})}
		</span>
	</div>

	<ul class="backfill-list">
		{#each candidates as c (c.id)}
			<li>
				<label class="candidate">
					<input
						type="checkbox"
						checked={!deselected.has(c.id)}
						disabled={saving}
						onchange={() => toggle(c.id)}
					/>
					<span class="material-symbols" aria-hidden="true">
						{activityTypeIcon(c.activity_type)}
					</span>
					<span class="candidate-date">{formatDate(c.started_at)}</span>
					<span class="candidate-distance">{formatDistance(c.distance_m)}</span>
				</label>
			</li>
		{/each}
	</ul>

	<footer class="backfill-footer">
		<button class="btn-outline" type="button" disabled={saving} onclick={onclose}>
			{m('settingsGear.backfillSkip')}
		</button>
		<button class="btn-primary" type="button" disabled={saving} onclick={attach}>
			{#if saving}
				{m('settingsGear.backfillAttaching')}
			{:else if selectedIds.length === 0}
				{m('settingsGear.backfillSkip')}
			{:else}
				{m('settingsGear.backfillAttach', { n: selectedIds.length })}
			{/if}
		</button>
	</footer>
</Modal>

<style>
	.backfill-body {
		margin: 0 0 var(--space-md);
		font-size: 0.9rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
	}
	.backfill-bulk {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		padding-bottom: var(--space-xs);
		border-bottom: 1px solid var(--color-border);
	}
	.bulk-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.9rem;
		cursor: pointer;
	}
	.bulk-count {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.backfill-list {
		list-style: none;
		padding: 0;
		margin: var(--space-xs) 0 0;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		max-height: 50vh;
		overflow-y: auto;
	}
	.candidate {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.45rem 0.4rem;
		border-radius: var(--radius-sm);
		font-size: 0.9rem;
		cursor: pointer;
	}
	.candidate:hover { background: var(--color-bg-tertiary); }
	.candidate .material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		/* rem, not em: an em font-size can't be priced against the type floor
		   by a static scan, and this glyph doesn't need to track the row. */
		font-size: 1rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.candidate-date { flex: 1; min-width: 0; }
	.candidate-distance {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.backfill-footer {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
		margin-top: var(--space-md);
	}
</style>
