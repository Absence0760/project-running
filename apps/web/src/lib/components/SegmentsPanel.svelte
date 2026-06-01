<script lang="ts">
	import { onMount } from 'svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import { formatDuration } from '$lib/format/time';
	import {
		fetchSegmentsForRoute,
		fetchSegmentLeaderboardTiered,
		createSegment,
		deleteSegment,
		SEGMENT_AGE_BANDS,
		type Segment,
		type SegmentLeaderboardEntry,
		type SegmentGenderFilter,
		type SegmentAgeBand,
	} from '$lib/core/data';
	import { crownLabel } from '$lib/segments/segments';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { distanceInPreferred } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';

	interface Props {
		routeId: string;
		routeDistanceM: number;
		canCreate: boolean;
		/// The route's owning club, if any. When set, a "Club only" leaderboard
		/// toggle is offered that filters efforts to that club (persona #50).
		clubId?: string | null;
	}
	let { routeId, routeDistanceM, canCreate, clubId = null }: Props = $props();
	let clubOnly = $state(false);

	let segments = $state<Segment[]>([]);
	let loading = $state(true);
	let leaderboards = $state<Map<string, SegmentLeaderboardEntry[]>>(new Map());
	let openSegmentId = $state<string | null>(null);
	// v2: tier filter (gender + age band). Applies to whichever
	// segment's leaderboard is currently expanded. Cleared whenever
	// the user picks a different segment so the new view starts from
	// the unfiltered baseline.
	let genderFilter = $state<SegmentGenderFilter | null>(null);
	let ageFilter = $state<SegmentAgeBand | null>(null);

	let showCreate = $state(false);
	let creating = $state(false);
	let draftName = $state('');
	let draftStart = $state(0);
	let draftEnd = $state(0);

	$effect(() => {
		// Default the end of the new-segment range to 1km or the
		// route's full length, whichever is smaller. Re-syncs if the
		// route prop ever changes (it doesn't today, but keeps the
		// state-referenced-locally lint quiet without fighting it).
		if (draftEnd === 0 && routeDistanceM > 0) {
			draftEnd = Math.min(1000, Math.round(routeDistanceM));
		}
	});

	let confirmDelete = $state<Segment | null>(null);

	async function load() {
		loading = true;
		segments = await fetchSegmentsForRoute(routeId);
		loading = false;
	}

	onMount(load);

	function toggleLeaderboard(seg: Segment) {
		if (openSegmentId === seg.id) {
			openSegmentId = null;
			return;
		}
		// Reset filters when switching segments — a runner who narrowed
		// to "Women 30-34" on segment A doesn't want that carried into
		// segment B's first impression. The $effect below picks up the
		// combined state change and fires exactly one RPC.
		openSegmentId = seg.id;
		genderFilter = null;
		ageFilter = null;
		clubOnly = false;
	}

	async function refreshLeaderboard(segmentId: string) {
		const entries = await fetchSegmentLeaderboardTiered(segmentId, {
			gender: genderFilter,
			ageBand: ageFilter,
			clubId: clubOnly ? clubId : null,
		});
		leaderboards = new Map(leaderboards).set(segmentId, entries);
	}

	$effect(() => {
		// Single source of refetches for both opening a segment and
		// changing a filter. Reading every signal up front is what makes
		// the effect reactive to them.
		const segId = openSegmentId;
		const _g = genderFilter;
		const _a = ageFilter;
		const _c = clubOnly;
		void _g;
		void _a;
		void _c;
		if (segId) refreshLeaderboard(segId);
	});

	async function submitCreate() {
		const name = draftName.trim();
		if (!name) return;
		if (draftEnd <= draftStart) {
			showToast(t('segments.endGreaterThanStart'), 'error');
			return;
		}
		if (draftEnd - draftStart < 100) {
			showToast(t('segments.minLength'), 'error');
			return;
		}
		creating = true;
		try {
			const seg = await createSegment({
				route_id: routeId,
				name,
				start_distance_m: draftStart,
				end_distance_m: draftEnd,
			});
			segments = [...segments, seg].sort((a, b) => a.start_distance_m - b.start_distance_m);
			showCreate = false;
			draftName = '';
		} catch (e: any) {
			showToast(e?.message ?? t('segments.createFailed'), 'error');
		} finally {
			creating = false;
		}
	}

	async function doDelete() {
		const target = confirmDelete;
		if (!target) return;
		confirmDelete = null;
		try {
			await deleteSegment(target.id);
			segments = segments.filter((s) => s.id !== target.id);
			leaderboards = new Map(
				Array.from(leaderboards.entries()).filter(([id]) => id !== target.id),
			);
			if (openSegmentId === target.id) openSegmentId = null;
		} catch (e: any) {
			showToast(e?.message ?? t('segments.deleteFailed'), 'error');
		}
	}

	function fmtDist(m: number): string {
		const { value, unit } = distanceInPreferred(m);
		return `${value.toFixed(2)} ${unit}`;
	}

	function fmtTime(s: number): string {
		return formatDuration(Math.round(s));
	}

</script>

<div class="segments-panel">
	<header class="hd">
		<h2>{t('segments.heading')}</h2>
		{#if canCreate}
			<button
				class="btn btn-outline btn-sm"
				type="button"
				onclick={() => (showCreate = !showCreate)}
			>
				{showCreate ? t('segments.cancel') : t('segments.newSegment')}
			</button>
		{/if}
	</header>

	{#if showCreate}
		<form
			class="create"
			onsubmit={(e) => {
				e.preventDefault();
				submitCreate();
			}}
		>
			<label>
				<span>{t('segments.nameLabel')}</span>
				<input type="text" bind:value={draftName} maxlength="120" placeholder={t('segments.namePlaceholder')} />
			</label>
			<div class="range">
				<label>
					<span>{t('segments.startMeters')}</span>
					<input
						type="number"
						min="0"
						max={routeDistanceM}
						step="10"
						bind:value={draftStart}
					/>
				</label>
				<label>
					<span>{t('segments.endMeters')}</span>
					<input
						type="number"
						min="100"
						max={Math.round(routeDistanceM)}
						step="10"
						bind:value={draftEnd}
					/>
				</label>
				<span class="length-hint">
					{#if draftEnd > draftStart}
						{fmtDist(draftEnd - draftStart)}
					{/if}
				</span>
			</div>
			<button class="btn btn-primary btn-sm" type="submit" disabled={creating || !draftName.trim()}>
				{creating ? t('segments.creating') : t('segments.create')}
			</button>
		</form>
	{/if}

	{#if loading}
		<p class="muted">{t('segments.loadingSegments')}</p>
	{:else if segments.length === 0}
		<p class="muted">{t('segments.empty')}</p>
	{:else}
		<ul class="seg-list">
			{#each segments as seg (seg.id)}
				<li class="seg" class:open={openSegmentId === seg.id}>
					<button class="seg-row" type="button" onclick={() => toggleLeaderboard(seg)}>
						<div class="seg-name">
							<strong>{seg.name}</strong>
							<span class="seg-meta">
								{fmtDist(Number(seg.length_m ?? Number(seg.end_distance_m) - Number(seg.start_distance_m)))}
								<span class="meta-sep">·</span>
								{fmtDist(Number(seg.start_distance_m))}–{fmtDist(Number(seg.end_distance_m))}
							</span>
						</div>
						<span class="material-symbols caret">
							{openSegmentId === seg.id ? 'expand_less' : 'expand_more'}
						</span>
					</button>

					{#if openSegmentId === seg.id}
						<div class="leaderboard">
							<div class="tier-filters">
								<label>
									{t('segments.gender')}
									<select bind:value={genderFilter}>
										<option value={null}>{t('segments.all')}</option>
										<option value="male">{t('segments.men')}</option>
										<option value="female">{t('segments.women')}</option>
										<option value="nonbinary">{t('segments.nonbinary')}</option>
									</select>
								</label>
								<label>
									{t('segments.ageBand')}
									<select bind:value={ageFilter}>
										<option value={null}>{t('segments.allAges')}</option>
										{#each SEGMENT_AGE_BANDS as band}
											<option value={band}>{band}</option>
										{/each}
									</select>
								</label>
								{#if clubId}
									<label class="club-only-toggle">
										<input type="checkbox" bind:checked={clubOnly} />
										{t('segments.clubOnly')}
									</label>
								{/if}
								{#if genderFilter || ageFilter || clubOnly}
									<button
										class="clear-btn"
										type="button"
										onclick={() => {
											genderFilter = null;
											ageFilter = null;
											clubOnly = false;
										}}
										title={t('segments.clearFilters')}
									>
										{t('segments.reset')}
									</button>
								{/if}
							</div>
							{#if leaderboards.get(seg.id) == null}
								<p class="muted small">{t('segments.loading')}</p>
							{:else if (leaderboards.get(seg.id) ?? []).length === 0}
								<p class="muted small">
									{genderFilter || ageFilter
										? t('segments.noEffortsFiltered')
										: t('segments.noEffortsYet')}
								</p>
							{:else}
								{@const _board = leaderboards.get(seg.id) ?? []}
								{@const _crownHolder = _board.find((e) => e.rank === 1) ?? null}
								{@const _viewerHoldsCrown =
									_crownHolder != null && _crownHolder.effort.user_id === auth.user?.id}
								{#if _viewerHoldsCrown}
									<p class="crown-banner" title={crownLabel(genderFilter, ageFilter)}>
										<span class="material-symbols crown-icon">emoji_events</span>
										{t('segments.youHoldCrown', { label: crownLabel(genderFilter, ageFilter) ?? '' })}
									</p>
								{/if}
								<ol>
									{#each _board as entry (entry.effort.id)}
										<li class:viewer={entry.effort.user_id === auth.user?.id}>
											<span class="rank">
												{#if entry.rank === 1}
													<span
														class="material-symbols crown-icon"
														title={crownLabel(genderFilter, ageFilter)}
														aria-label={crownLabel(genderFilter, ageFilter)}
													>
														emoji_events
													</span>
												{:else}
													#{entry.rank}
												{/if}
											</span>
											<a href="/u/{entry.athlete.id}" class="athlete">
												<Avatar
													url={entry.athlete.avatar_url}
													name={entry.athlete.display_name}
													size="1.6rem"
													font="0.72rem"
												/>
												<span class="athlete-name">
													{entry.athlete.display_name ?? t('segments.runnerFallback')}
												</span>
											</a>
											<span class="time">{fmtTime(entry.effort.time_seconds)}</span>
										</li>
									{/each}
								</ol>
							{/if}
							{#if auth.user?.id === seg.created_by || canCreate}
								<button
									class="link-btn danger"
									type="button"
									onclick={() => (confirmDelete = seg)}
								>
									{t('segments.deleteSegment')}
								</button>
							{/if}
						</div>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<ConfirmDialog
	open={confirmDelete != null}
	title={t('segments.deleteConfirmTitle')}
	message={t('segments.deleteConfirmMessage')}
	confirmLabel={t('segments.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmDelete = null)}
/>

<style>
	.segments-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.hd {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	.hd h2 {
		margin: 0;
		font-size: 0.85rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
	}
	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		margin: 0;
	}
	.muted.small {
		font-size: 0.78rem;
	}
	.create {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}
	.create label {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
	}
	.create input {
		padding: 0.4rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-size: 0.9rem;
	}
	.range {
		display: flex;
		gap: var(--space-sm);
		align-items: end;
	}
	.range label {
		flex: 1;
	}
	.length-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		padding-bottom: 0.45rem;
	}
	.create button {
		align-self: flex-start;
	}

	.seg-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0;
	}
	.seg {
		border-bottom: 1px solid var(--color-border);
	}
	.seg:last-child {
		border-bottom: none;
	}
	.seg-row {
		display: flex;
		width: 100%;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-sm) 0;
		background: none;
		border: none;
		cursor: pointer;
		text-align: start;
		color: inherit;
	}
	.seg-row:hover {
		color: var(--color-primary);
	}
	.seg-name {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.seg-meta {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.meta-sep {
		margin: 0 0.3rem;
	}
	.caret {
		color: var(--color-text-tertiary);
		font-size: 1.2rem;
	}
	.leaderboard {
		padding: var(--space-sm) 0 var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.tier-filters {
		display: flex;
		flex-wrap: wrap;
		align-items: end;
		gap: var(--space-sm);
		padding: var(--space-sm);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-sm);
	}
	.tier-filters label {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-secondary);
	}
	.tier-filters select {
		padding: 0.3rem 0.5rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-size: 0.85rem;
		color: inherit;
		min-width: 8rem;
	}
	.clear-btn {
		align-self: end;
		padding: 0.35rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: transparent;
		font-size: 0.78rem;
		cursor: pointer;
		color: var(--color-text-secondary);
	}
	.clear-btn:hover {
		color: var(--color-primary);
		border-color: var(--color-primary);
	}
	.leaderboard ol {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.leaderboard li {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.85rem;
		padding: 0.3rem 0.5rem;
		border-radius: var(--radius-sm);
	}
	.leaderboard li.viewer {
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		font-weight: 600;
	}
	.rank {
		font-variant-numeric: tabular-nums;
		color: var(--color-text-tertiary);
		min-width: 2.5rem;
		display: inline-flex;
		align-items: center;
	}
	.crown-icon {
		color: #f5b30a;
		font-size: 1.1rem;
		line-height: 1;
	}
	.crown-banner {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin: 0;
		padding: var(--space-sm) var(--space-md);
		background: color-mix(in srgb, #f5b30a 12%, transparent);
		border: 1px solid color-mix(in srgb, #f5b30a 35%, transparent);
		border-radius: var(--radius-sm);
		font-size: 0.85rem;
		font-weight: 600;
	}
	.athlete {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		flex: 1;
		text-decoration: none;
		color: inherit;
	}
	.athlete-name {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.time {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
	.link-btn {
		align-self: flex-start;
		background: none;
		border: none;
		font-size: 0.78rem;
		padding: 0;
		cursor: pointer;
		color: var(--color-text-tertiary);
	}
	.link-btn.danger:hover {
		color: var(--color-danger, #ef4444);
	}
</style>
