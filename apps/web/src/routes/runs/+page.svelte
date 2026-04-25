<script lang="ts">
	import { onMount } from 'svelte';
	import {
		formatDuration,
		formatPace,
		formatDistance,
		formatDate,
		sourceLabel,
		sourceColor,
	} from '$lib/mock-data';
	import { fetchRuns, deleteRuns } from '$lib/data';
	import RunEditor from '$lib/components/RunEditor.svelte';
	import { goto } from '$app/navigation';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import RunTrackPreview from '$lib/components/RunTrackPreview.svelte';
	import type { Run, RunSource } from '$lib/types';

	let runs = $state<Run[]>([]);
	let loading = $state(true);
	let sourceFilter = $state<RunSource | 'all'>('all');
	let activityFilter = $state<string>('all');
	type SortKey = 'newest' | 'oldest' | 'longest' | 'fastest';
	let sortKey = $state<SortKey>('newest');
	type DateRange = 'today' | 'week' | 'month' | 'year' | 'all' | 'custom';
	// Default to "all" on web so history is fully visible on first
	// open. (Android defaults to "week" because its list is the main
	// surface; web has a richer dashboard above.)
	let dateRange = $state<DateRange>('all');
	/// ISO yyyy-mm-dd bounds for the custom-range picker. Empty string
	/// means unbounded on that side.
	let customFrom = $state('');
	let customTo = $state('');

	/// Lower-bound / upper-bound cutoffs in local time for the selected
	/// range. `null` on either side means "no cutoff on this side".
	function rangeBounds(range: DateRange): { from: Date | null; to: Date | null } {
		const now = new Date();
		switch (range) {
			case 'today': {
				const d = new Date(now);
				d.setHours(0, 0, 0, 0);
				return { from: d, to: null };
			}
			case 'week': {
				// Monday-start week, matching Android's `weekStartLocal`.
				const d = new Date(now);
				d.setHours(0, 0, 0, 0);
				const dow = (d.getDay() + 6) % 7; // 0 = Mon
				d.setDate(d.getDate() - dow);
				return { from: d, to: null };
			}
			case 'month': {
				const d = new Date(now);
				d.setHours(0, 0, 0, 0);
				d.setDate(d.getDate() - 30);
				return { from: d, to: null };
			}
			case 'year':
				return { from: new Date(now.getFullYear(), 0, 1), to: null };
			case 'custom': {
				const from = customFrom ? new Date(customFrom + 'T00:00:00') : null;
				const to = customTo ? new Date(customTo + 'T23:59:59.999') : null;
				return { from, to };
			}
			case 'all':
				return { from: null, to: null };
		}
	}

	// Multi-select + bulk delete. Selection mode is off by default —
	// toggling on replaces the card's link behaviour with a checkbox
	// tap so the user doesn't navigate away mid-selection. Confirm
	// dialog wraps the destructive bulk action; a `deleting` flag
	// keeps the Delete button from double-firing.
	let selecting = $state(false);
	let selected = $state<Set<string>>(new Set());
	let showBulkConfirm = $state(false);
	let deleting = $state(false);

	function toggleSelect(id: string) {
		const next = new Set(selected);
		if (next.has(id)) next.delete(id);
		else next.add(id);
		selected = next;
	}

	function selectAllVisible() {
		selected = new Set(filteredRuns.map((r) => r.id));
	}

	function clearSelection() {
		selected = new Set();
	}

	function exitSelectMode() {
		selecting = false;
		clearSelection();
	}

	async function handleBulkDelete() {
		showBulkConfirm = false;
		if (selected.size === 0 || deleting) return;
		deleting = true;
		const ids = Array.from(selected);
		const { failed } = await deleteRuns(ids);
		// Remove the ones that succeeded from the in-memory list
		// without refetching — keeps the scroll position.
		const failedSet = new Set(failed);
		runs = runs.filter((r) => failedSet.has(r.id) || !selected.has(r.id));
		deleting = false;
		if (failed.length === 0) {
			showToast(
				`Deleted ${ids.length} run${ids.length === 1 ? '' : 's'}.`,
				'success',
			);
			exitSelectMode();
		} else {
			showToast(
				`${ids.length - failed.length} deleted, ${failed.length} failed.`,
				'error',
			);
			selected = failedSet;
		}
	}

	let filteredRuns = $derived.by(() => {
		const { from, to } = rangeBounds(dateRange);
		const out = runs.filter((r) => {
			if (sourceFilter !== 'all' && r.source !== sourceFilter) return false;
			if (activityFilter !== 'all') {
				const type = (r.metadata as Record<string, unknown> | null)?.activity_type ?? 'run';
				if (type !== activityFilter) return false;
			}
			const startedAt = new Date(r.started_at);
			if (from && startedAt < from) return false;
			if (to && startedAt > to) return false;
			return true;
		});
		// Sort in-place on the filtered copy so the user's chosen key
		// persists through filter flips. `fastest` uses pace (sec/km);
		// any run shorter than 10 m is kicked to the bottom because the
		// computed pace is meaningless.
		const pace = (r: Run) =>
			r.distance_m < 10 ? Infinity : r.duration_s / (r.distance_m / 1000);
		switch (sortKey) {
			case 'newest':
				out.sort((a, b) => b.started_at.localeCompare(a.started_at));
				break;
			case 'oldest':
				out.sort((a, b) => a.started_at.localeCompare(b.started_at));
				break;
			case 'longest':
				out.sort((a, b) => b.distance_m - a.distance_m);
				break;
			case 'fastest':
				out.sort((a, b) => pace(a) - pace(b));
				break;
		}
		return out;
	});

	const sources: { value: RunSource | 'all'; label: string }[] = [
		{ value: 'all', label: 'All Sources' },
		{ value: 'app', label: 'Recorded' },
		{ value: 'strava', label: 'Strava' },
		{ value: 'parkrun', label: 'parkrun' },
		{ value: 'healthkit', label: 'HealthKit' },
	];

	const activities: { value: string; label: string; icon: string }[] = [
		{ value: 'all', label: 'All', icon: 'apps' },
		{ value: 'run', label: 'Run', icon: 'directions_run' },
		{ value: 'walk', label: 'Walk', icon: 'directions_walk' },
		{ value: 'cycle', label: 'Cycle', icon: 'directions_bike' },
		{ value: 'hike', label: 'Hike', icon: 'terrain' },
	];

	onMount(async () => {
		runs = await fetchRuns();
		loading = false;
	});

	let showRunModal = $state(false);

	async function handleRunCreated(run: { id: string }) {
		showRunModal = false;
		// Navigate straight to the new run so the user lands on the
		// detail page they'd otherwise have hit via the standalone form.
		goto(`/runs/${run.id}`);
	}
</script>

<div class="page">
	<header class="page-header">
		<div class="title-row">
			<div class="title-actions">
				{#if selecting}
					<button class="link-btn" onclick={selectAllVisible} type="button"
						>Select all</button
					>
					<button class="link-btn" onclick={exitSelectMode} type="button"
						>Done</button
					>
				{:else}
					<button
						class="link-btn"
						onclick={() => (selecting = true)}
						type="button">Select</button
					>
					<button class="add-btn" type="button" onclick={() => (showRunModal = true)}>+ Add run</button>
				{/if}
			</div>
		</div>
		<div class="filters">
			{#each sources as src}
				<button
					class="filter-btn"
					class:active={sourceFilter === src.value}
					onclick={() => (sourceFilter = src.value)}
				>
					{src.label}
				</button>
			{/each}
		</div>
		<div class="filters" style="margin-top: var(--space-xs)">
			{#each activities as act}
				<button
					class="filter-btn"
					class:active={activityFilter === act.value}
					onclick={() => (activityFilter = act.value)}
				>
					<span class="material-symbols" style="font-size: 0.9rem; vertical-align: middle">{act.icon}</span>
					{act.label}
				</button>
			{/each}
		</div>
		<div class="filters" style="margin-top: var(--space-xs)">
			{#each [{v: 'all', l: 'All time'}, {v: 'today', l: 'Today'}, {v: 'week', l: 'This week'}, {v: 'month', l: 'Last 30 days'}, {v: 'year', l: 'This year'}, {v: 'custom', l: 'Custom…'}] as r (r.v)}
				<button
					class="filter-btn"
					class:active={dateRange === r.v}
					onclick={() => (dateRange = r.v as DateRange)}
				>
					{r.l}
				</button>
			{/each}
		</div>
		{#if dateRange === 'custom'}
			<div class="date-picker-row">
				<label>
					From
					<input type="date" bind:value={customFrom} />
				</label>
				<label>
					To
					<input type="date" bind:value={customTo} />
				</label>
				{#if customFrom || customTo}
					<button
						type="button"
						class="link-btn"
						onclick={() => {
							customFrom = '';
							customTo = '';
						}}>Clear</button
					>
				{/if}
			</div>
		{/if}
		<div class="sort-row" style="margin-top: var(--space-xs)">
			<label class="sort-label">
				Sort
				<select bind:value={sortKey} class="sort-select">
					<option value="newest">Newest first</option>
					<option value="oldest">Oldest first</option>
					<option value="longest">Longest</option>
					<option value="fastest">Fastest pace</option>
				</select>
			</label>
		</div>
	</header>

	{#if loading}
		<p class="loading-text">&nbsp;</p>
	{:else}
		<div class="run-list">
			{#each filteredRuns as run}
				{@const isSelected = selected.has(run.id)}
				<svelte:element
					this={selecting ? 'button' : 'a'}
					class="run-card"
					class:selecting
					class:selected={selecting && isSelected}
					href={selecting ? undefined : `/runs/${run.id}`}
					type={selecting ? 'button' : undefined}
					onclick={selecting ? () => toggleSelect(run.id) : undefined}
				>
					{#if selecting}
						<span
							class="select-box"
							class:checked={isSelected}
							aria-hidden="true"
						>
							{isSelected ? '✓' : ''}
						</span>
					{/if}
					{#if run.track_url}
						<div class="run-map-placeholder">
							<RunTrackPreview trackUrl={run.track_url} />
						</div>
					{/if}
					<div class="run-details">
						<div class="run-top">
							<span class="run-date">{formatDate(run.started_at)}</span>
							<span class="source-badge" style="background: {sourceColor(run.source)}"
								>{sourceLabel(run.source)}</span
							>
						</div>
						<div class="run-stats">
							<div class="run-stat">
								<span class="run-stat-value">{formatDistance(run.distance_m)}</span>
								<span class="run-stat-label">Distance</span>
							</div>
							<div class="run-stat">
								<span class="run-stat-value">{formatDuration(run.duration_s)}</span>
								<span class="run-stat-label">Time</span>
							</div>
							<div class="run-stat">
								<span class="run-stat-value"
									>{formatPace(run.duration_s, run.distance_m)}</span
								>
								<span class="run-stat-label">Pace</span>
							</div>
						</div>
						{#if run.metadata?.event}
							<div class="run-event">
								{run.metadata.event}
								{#if run.metadata.position} &middot; Position {run.metadata.position}{/if}
							</div>
						{/if}
					</div>
				</svelte:element>
			{/each}
		</div>

		{#if selecting && selected.size > 0}
			<div class="bulk-bar" role="toolbar" aria-label="Selection actions">
				<span>{selected.size} selected</span>
				<button
					type="button"
					class="bulk-delete"
					disabled={deleting}
					onclick={() => (showBulkConfirm = true)}
				>
					{deleting ? 'Deleting…' : 'Delete'}
				</button>
			</div>
		{/if}

		<ConfirmDialog
			open={showBulkConfirm}
			title="Delete {selected.size} run{selected.size === 1 ? '' : 's'}?"
			message="This permanently removes the runs and their GPS tracks. Can't be undone."
			confirmLabel="Delete"
			danger
			onconfirm={handleBulkDelete}
			oncancel={() => (showBulkConfirm = false)}
		/>

		{#if filteredRuns.length === 0}
			<div class="empty">No runs found for this filter.</div>
		{/if}
	{/if}
</div>

{#if showRunModal}
	<div class="modal-backdrop" role="presentation" onclick={() => (showRunModal = false)}></div>
	<div class="modal" role="dialog" aria-modal="true" aria-label="Add a run">
		<header class="modal-header">
			<h2>Add a run</h2>
			<button
				class="modal-close"
				type="button"
				aria-label="Close"
				onclick={() => (showRunModal = false)}
			>
				<span class="material-symbols">close</span>
			</button>
		</header>
		<div class="modal-body">
			<RunEditor oncreated={handleRunCreated} oncancel={() => (showRunModal = false)} />
		</div>
	</div>
{/if}

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 96rem;
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-md);
	}

	.filters {
		display: flex;
		gap: var(--space-xs);
	}

	.filter-btn {
		padding: var(--space-xs) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
	}

	.filter-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.filter-btn.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: white;
	}

	.loading-text {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.run-list {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-md);
	}

	.run-card {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: all var(--transition-fast);
		text-decoration: none;
		color: inherit;
	}

	.run-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.run-map-placeholder {
		width: 100%;
		height: 8rem;
		background: var(--color-bg-tertiary);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.run-map-placeholder .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
	}

	.run-details {
		flex: 1;
		min-width: 0;
		padding: var(--space-md) var(--space-lg);
	}

	.run-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-sm);
		gap: var(--space-sm);
	}

	.run-date {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.source-badge {
		font-size: 0.65rem;
		font-weight: 600;
		color: white;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		white-space: nowrap;
	}

	.run-stats {
		display: flex;
		justify-content: space-between;
		gap: var(--space-md);
	}

	.run-stat {
		display: flex;
		flex-direction: column;
	}

	.run-stat-value {
		font-weight: 700;
		font-size: 1.05rem;
	}

	.run-stat-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.run-event {
		margin-top: var(--space-sm);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.empty {
		text-align: center;
		padding: var(--space-2xl);
		color: var(--color-text-tertiary);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	.date-picker-row {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		margin-top: var(--space-sm);
		flex-wrap: wrap;
	}
	.date-picker-row label {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.date-picker-row input[type='date'] {
		padding: 0.35rem 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text-primary);
		font-size: 0.85rem;
	}
	.sort-row {
		display: flex;
		align-items: center;
	}
	.sort-label {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.sort-select {
		padding: 0.35rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text-primary);
		font-size: 0.85rem;
	}
	.title-row {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		margin-bottom: var(--space-sm);
	}
	.title-actions {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}
	.link-btn {
		background: transparent;
		border: none;
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		padding: 0.4rem 0.3rem;
	}
	.add-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-lg);
		background: var(--color-primary);
		color: white;
		border-radius: var(--radius-md);
		font-size: 0.875rem;
		font-weight: 600;
		text-decoration: none;
		border: none;
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.add-btn:hover { background: var(--color-primary-hover); }
	/* Select mode renders as <button> instead of <a>, but the visual
	   layout is identical to the link version — same map preview, same
	   stats grid. The checkbox is positioned over the top-left corner
	   so the card itself doesn't have to reflow. */
	.run-card.selecting {
		position: relative;
		text-align: left;
		cursor: pointer;
		font: inherit;
		color: inherit;
		padding: 0;
		width: 100%;
	}
	/* The link version is naturally `position: relative` via the grid
	   item it sits in; the button version needs it for the absolute
	   `.select-box` overlay to anchor correctly. */
	.run-card.selecting .run-map-placeholder { pointer-events: none; }
	/* Cards without a map preview have their date row at the top of the
	   card, where the absolute-positioned checkbox sits. Push it right
	   so the box doesn't sit over the date text. The padding is harmless
	   when a map is present (the date row is below the map). */
	.run-card.selecting .run-top { padding-left: 2rem; }
	.run-card.selecting.selected {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 2px var(--color-primary-light);
	}
	.select-box {
		position: absolute;
		top: 0.6rem;
		left: 0.6rem;
		z-index: 2;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 24px;
		height: 24px;
		background: var(--color-surface);
		border: 1.5px solid var(--color-border);
		border-radius: 6px;
		color: var(--color-bg);
		font-size: 0.95rem;
		font-weight: 700;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.25);
	}
	.select-box.checked {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: #FFFFFF;
	}
	.bulk-bar {
		position: sticky;
		bottom: 16px;
		margin: 1rem auto 0;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		padding: 0.75rem 1rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
		max-width: 32rem;
		font-size: 0.9rem;
	}
	.bulk-delete {
		padding: 0.5rem 1rem;
		background: #d32f2f;
		color: white;
		border: none;
		border-radius: var(--radius-md);
		font-weight: 600;
		cursor: pointer;
	}
	.bulk-delete:disabled { opacity: 0.55; cursor: not-allowed; }

	.modal-backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		z-index: 200;
	}
	.modal {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		width: min(36rem, calc(100vw - 2rem));
		max-height: calc(100vh - 4rem);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-lg);
		z-index: 201;
		display: flex;
		flex-direction: column;
		overflow: hidden;
	}
	.modal-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-md) var(--space-lg);
		border-bottom: 1px solid var(--color-border);
		flex-shrink: 0;
	}
	.modal-header h2 {
		font-size: 1.05rem;
		font-weight: 700;
	}
	.modal-close {
		background: none;
		border: none;
		color: var(--color-text-secondary);
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.3rem;
		border-radius: var(--radius-sm);
		transition: background var(--transition-fast);
	}
	.modal-close:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.modal-body {
		padding: var(--space-lg);
		overflow-y: auto;
	}
</style>
