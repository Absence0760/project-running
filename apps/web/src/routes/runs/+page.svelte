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
	import { auth } from '$lib/stores/auth.svelte';
	import RunEditor from '$lib/components/RunEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { goto } from '$app/navigation';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import RunTrackPreview from '$lib/components/RunTrackPreview.svelte';
	import DateRangePicker from '$lib/components/DateRangePicker.svelte';
	import type { Run, RunSource } from '$lib/types';
	import type { Snapshot } from './$types';

	let runs = $state<Run[]>([]);
	let loading = $state(true);
	let sourceFilter = $state<RunSource | 'all'>('all');
	let activityFilter = $state<string>('run');
	type SortKey = 'newest' | 'oldest' | 'longest' | 'fastest';
	let sortKey = $state<SortKey>('newest');
	type DateRange = 'today' | 'week' | 'month' | 'year' | 'all' | 'custom';
	// Default scope = today's runs only. "All time" is opt-in and
	// streams in pages of PAGE_SIZE so a heavy account doesn't
	// pull thousands of rows on first paint.
	let dateRange = $state<DateRange>('today');

	const PAGE_SIZE = 50;
	let loadingMore = $state(false);
	let hasMore = $state(false);
	/// Tracks the last fetch mode so we only refetch on `paginated` ↔
	/// `full` transitions, not on every filter twiddle.
	let lastFetchMode = $state<'paginated' | 'full' | ''>('');
	let fetchMode = $derived<'paginated' | 'full'>(dateRange === 'all' ? 'paginated' : 'full');
	/// ISO yyyy-mm-dd bounds for the custom-range picker. Empty string
	/// means unbounded on that side.
	let customFrom = $state('');
	let customTo = $state('');

	/// Filters persist across navigation via localStorage so the user
	/// doesn't have to rebuild their view every time. Hydration happens
	/// once in onMount; after that an effect mirrors any change back
	/// to localStorage. The `filtersHydrated` flag gates the writer so
	/// the SSR/initial defaults don't clobber a saved blob.
	const FILTERS_KEY = 'runs_filters_v1';
	let filtersHydrated = $state(false);

	onMount(() => {
		try {
			const raw = localStorage.getItem(FILTERS_KEY);
			if (raw) {
				const saved = JSON.parse(raw);
				if (saved.sourceFilter) sourceFilter = saved.sourceFilter;
				if (saved.activityFilter) activityFilter = saved.activityFilter;
				if (saved.dateRange) dateRange = saved.dateRange;
				if (typeof saved.customFrom === 'string') customFrom = saved.customFrom;
				if (typeof saved.customTo === 'string') customTo = saved.customTo;
				if (saved.sortKey) sortKey = saved.sortKey;
			}
		} catch (_) {
			/* localStorage may be unavailable / blob may be corrupt — leave defaults */
		}
		filtersHydrated = true;
	});

	$effect(() => {
		if (!filtersHydrated) return;
		try {
			localStorage.setItem(
				FILTERS_KEY,
				JSON.stringify({ sourceFilter, activityFilter, dateRange, customFrom, customTo, sortKey }),
			);
		} catch (_) {
			/* silent */
		}
	});

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

	async function loadInitial() {
		loading = true;
		if (fetchMode === 'paginated') {
			runs = await fetchRuns({ limit: PAGE_SIZE, offset: 0 });
			hasMore = runs.length === PAGE_SIZE;
		} else {
			runs = await fetchRuns();
			hasMore = false;
		}
		loading = false;
	}

	async function loadMore() {
		if (loadingMore || !hasMore) return;
		loadingMore = true;
		const more = await fetchRuns({ limit: PAGE_SIZE, offset: runs.length });
		runs = [...runs, ...more];
		hasMore = more.length === PAGE_SIZE;
		loadingMore = false;
	}

	$effect(() => {
		// Don't fetch before the auth store has hydrated. fetchRuns
		// reads `auth.user?.id` and returns [] if it's null — which
		// would race on cold loads where the page mounts before the
		// auth cookie is processed and produce a permanent "No runs
		// found" state.
		//
		// Gate on BOTH `auth.loading` and `auth.user` because there's
		// a window where auth.svelte.ts has flipped loading=false
		// (session check is done) but `user` is still null
		// (fetchUser is in flight, profile not yet loaded). The
		// $effect re-fires when auth.user becomes set.
		if (auth.loading || !auth.user) return;
		if (fetchMode !== lastFetchMode) {
			lastFetchMode = fetchMode;
			loadInitial();
		}
	});

	/// Preserve the loaded list across in-app navigation so clicking a
	/// run, then `back`, lands the user at the same scroll position
	/// they were at — instead of a flash of "Loading…" plus a jump to
	/// the top. Filters are already in localStorage; what we add here
	/// is the runs array + pagination cursor so the page renders to
	/// its full height synchronously and SvelteKit's built-in scroll
	/// restoration can actually run. Snapshot fires for every internal
	/// navigation away (link, goto, popstate) and restores on return.
	export const snapshot: Snapshot<{
		runs: Run[];
		hasMore: boolean;
		lastFetchMode: 'paginated' | 'full' | '';
	}> = {
		capture: () => ({ runs, hasMore, lastFetchMode }),
		restore: (s) => {
			runs = s.runs;
			hasMore = s.hasMore;
			lastFetchMode = s.lastFetchMode;
			loading = false;
		},
	};

	let showRunModal = $state(false);
	let showRangePicker = $state(false);

	/// Last non-custom value of `dateRange`. Used to bounce back when
	/// the user picks Custom from the dropdown then closes the picker
	/// without committing — without this they'd be stranded in a
	/// "Custom but no bounds" state (which behaves like All time but
	/// reads as Custom in the dropdown).
	let prevNonCustomRange = $state<DateRange>('today');
	$effect(() => {
		if (dateRange !== 'custom') prevNonCustomRange = dateRange;
	});

	function handleRangePickerClose(): void {
		showRangePicker = false;
		if (dateRange === 'custom' && !customFrom && !customTo) {
			dateRange = prevNonCustomRange;
		}
	}

	/// Compact label for the toolbar chip when a custom range is set.
	/// "May 1 – May 7" (cross-year picks add the year suffix). When the
	/// user is in custom mode but hasn't set bounds yet (e.g. just
	/// flipped to Custom in the dropdown), we show "Pick dates…" instead.
	function customRangeChipLabel(): string {
		const months = [
			'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
			'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
		];
		const fmt = (s: string) => {
			const d = new Date(s + 'T00:00:00');
			const base = `${months[d.getMonth()]} ${d.getDate()}`;
			return d.getFullYear() === new Date().getFullYear()
				? base
				: `${base}, ${d.getFullYear()}`;
		};
		if (!customFrom && !customTo) return 'Pick dates…';
		if (customFrom && customTo) return `${fmt(customFrom)} – ${fmt(customTo)}`;
		if (customFrom) return `From ${fmt(customFrom)}`;
		return `Until ${fmt(customTo)}`;
	}

	async function handleRunCreated(run: { id: string }) {
		showRunModal = false;
		// Navigate straight to the new run so the user lands on the
		// detail page they'd otherwise have hit via the standalone form.
		goto(`/runs/${run.id}`);
	}
</script>

<div class="page">
	<header class="page-header">
		<div class="toolbar">
			<div class="activity-group" role="group" aria-label="Activity type">
				{#each activities as act}
					<button
						class="activity-btn"
						class:active={activityFilter === act.value}
						onclick={() => (activityFilter = act.value)}
						title={act.label}
						aria-label={act.label}
						aria-pressed={activityFilter === act.value}
						type="button"
					>
						<span class="material-symbols">{act.icon}</span>
						<span class="activity-label">{act.label}</span>
					</button>
				{/each}
			</div>

			<div class="select-group">
				<select bind:value={sourceFilter} class="toolbar-select" aria-label="Source">
					{#each sources as src}
						<option value={src.value}>{src.label}</option>
					{/each}
				</select>
				<select
					bind:value={dateRange}
					class="toolbar-select"
					aria-label="Date range"
					onchange={() => {
						if (dateRange === 'custom') showRangePicker = true;
					}}
				>
					<option value="all">All time</option>
					<option value="today">Today</option>
					<option value="week">This week</option>
					<option value="month">Last 30 days</option>
					<option value="year">This year</option>
					<option value="custom">Custom…</option>
				</select>
				<select bind:value={sortKey} class="toolbar-select" aria-label="Sort">
					<option value="newest">Newest first</option>
					<option value="oldest">Oldest first</option>
					<option value="longest">Longest</option>
					<option value="fastest">Fastest pace</option>
				</select>
			</div>

			<div class="toolbar-actions">
				{#if selecting}
					<button class="link-btn" onclick={selectAllVisible} type="button">Select all</button>
					<button class="link-btn" onclick={exitSelectMode} type="button">Done</button>
				{:else}
					<button class="link-btn" onclick={() => (selecting = true)} type="button">Select</button>
					<button class="add-btn" type="button" onclick={() => (showRunModal = true)}>+ Add run</button>
				{/if}
			</div>
		</div>

		{#if dateRange === 'custom'}
			<div class="date-picker-row">
				<button
					type="button"
					class="range-chip"
					onclick={() => (showRangePicker = true)}
					aria-label="Open date range picker"
				>
					<span class="material-symbols">calendar_month</span>
					{customRangeChipLabel()}
				</button>
				{#if customFrom || customTo}
					<button
						type="button"
						class="link-btn"
						onclick={() => {
							customFrom = '';
							customTo = '';
						}}>Clear</button>
				{/if}
			</div>
		{/if}
	</header>

	{#if loading}
		<p class="loading-text">&nbsp;</p>
	{:else}
		<div class="run-list">
			{#each filteredRuns as run}
				{@const isSelected = selected.has(run.id)}
				<svelte:element
					this={selecting ? 'button' : 'a'}
					role={selecting ? 'button' : 'link'}
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

		{#if hasMore && fetchMode === 'paginated'}
			<div class="load-more-row">
				<button
					type="button"
					class="btn btn-outline"
					disabled={loadingMore}
					onclick={loadMore}
				>
					{loadingMore ? 'Loading…' : `Load ${PAGE_SIZE} more`}
				</button>
			</div>
		{/if}

		{#if filteredRuns.length === 0}
			<div class="empty">No runs found for this filter.</div>
		{/if}
	{/if}
</div>

<Modal
	open={showRunModal}
	title="Add a run"
	onclose={() => (showRunModal = false)}
>
	<RunEditor oncreated={handleRunCreated} oncancel={() => (showRunModal = false)} />
</Modal>

<DateRangePicker
	open={showRangePicker}
	onclose={handleRangePickerClose}
	initialFrom={customFrom}
	initialTo={customTo}
	onapply={(from, to) => {
		customFrom = from;
		customTo = to;
		showRangePicker = false;
	}}
	onclear={() => {
		customFrom = '';
		customTo = '';
	}}
/>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-md);
	}

	.toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
	}

	.activity-group {
		display: inline-flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		padding: 2px;
		gap: 2px;
	}

	.activity-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.35rem 0.7rem;
		border: none;
		border-radius: calc(var(--radius-md) - 2px);
		background: transparent;
		font: inherit;
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.activity-btn .material-symbols {
		font-size: 1.05rem;
	}
	.activity-btn:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.activity-btn.active {
		background: var(--color-primary);
		color: white;
	}
	.activity-btn.active:hover {
		background: var(--color-primary-hover);
	}

	.select-group {
		display: inline-flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}

	.toolbar-select {
		padding: 0.45rem 2rem 0.45rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.85rem;
		font-weight: 500;
		appearance: none;
		background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23999' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polyline points='6 9 12 15 18 9'/></svg>");
		background-repeat: no-repeat;
		background-position: right 0.6rem center;
		background-size: 0.75rem;
		cursor: pointer;
		transition: border-color var(--transition-fast);
	}
	.toolbar-select:hover {
		border-color: var(--color-primary);
	}
	.toolbar-select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}

	.toolbar-actions {
		display: inline-flex;
		align-items: center;
		gap: 0.6rem;
		margin-left: auto;
	}

	@media (max-width: 50rem) {
		.activity-label {
			display: none;
		}
		.toolbar-actions {
			margin-left: 0;
			width: 100%;
			justify-content: flex-end;
		}
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

	.load-more-row {
		display: flex;
		justify-content: center;
		padding: var(--space-md) 0 var(--space-xl);
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
	.range-chip {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.4rem 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.875rem;
		font-weight: 500;
		cursor: pointer;
	}
	.range-chip:hover {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.range-chip .material-symbols {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
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

	/* .modal-* classes live in app.css. */
</style>
