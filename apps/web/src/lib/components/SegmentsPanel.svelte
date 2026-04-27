<script lang="ts">
	import { onMount } from 'svelte';
	import {
		fetchSegmentsForRoute,
		fetchSegmentLeaderboard,
		createSegment,
		deleteSegment,
		type Segment,
		type SegmentLeaderboardEntry,
	} from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { distanceInPreferred } from '$lib/units.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';

	interface Props {
		routeId: string;
		routeDistanceM: number;
		canCreate: boolean;
	}
	let { routeId, routeDistanceM, canCreate }: Props = $props();

	let segments = $state<Segment[]>([]);
	let loading = $state(true);
	let leaderboards = $state<Map<string, SegmentLeaderboardEntry[]>>(new Map());
	let openSegmentId = $state<string | null>(null);

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

	async function toggleLeaderboard(seg: Segment) {
		if (openSegmentId === seg.id) {
			openSegmentId = null;
			return;
		}
		openSegmentId = seg.id;
		if (!leaderboards.has(seg.id)) {
			const entries = await fetchSegmentLeaderboard(seg.id);
			leaderboards = new Map(leaderboards).set(seg.id, entries);
		}
	}

	async function submitCreate() {
		const name = draftName.trim();
		if (!name) return;
		if (draftEnd <= draftStart) {
			showToast('End must be greater than start', 'error');
			return;
		}
		if (draftEnd - draftStart < 100) {
			showToast('Segment must be at least 100 m', 'error');
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
			showToast(e?.message ?? 'Could not create segment', 'error');
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
			showToast(e?.message ?? 'Delete failed', 'error');
		}
	}

	function fmtDist(m: number): string {
		const { value, unit } = distanceInPreferred(m);
		return `${value.toFixed(2)} ${unit}`;
	}

	function fmtTime(s: number): string {
		const total = Math.round(s);
		const h = Math.floor(total / 3600);
		const m = Math.floor((total % 3600) / 60);
		const sec = total % 60;
		if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
		return `${m}:${String(sec).padStart(2, '0')}`;
	}

	function initial(name: string | null): string {
		return (name?.[0] ?? '?').toUpperCase();
	}
</script>

<div class="segments-panel">
	<header class="hd">
		<h2>Segments</h2>
		{#if canCreate}
			<button
				class="btn btn-outline btn-sm"
				type="button"
				onclick={() => (showCreate = !showCreate)}
			>
				{showCreate ? 'Cancel' : 'New segment'}
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
				<span>Name</span>
				<input type="text" bind:value={draftName} maxlength="120" placeholder="Climb of doom" />
			</label>
			<div class="range">
				<label>
					<span>Start (m)</span>
					<input
						type="number"
						min="0"
						max={routeDistanceM}
						step="10"
						bind:value={draftStart}
					/>
				</label>
				<label>
					<span>End (m)</span>
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
				{creating ? 'Creating…' : 'Create'}
			</button>
		</form>
	{/if}

	{#if loading}
		<p class="muted">Loading segments…</p>
	{:else if segments.length === 0}
		<p class="muted">No segments on this route yet.</p>
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
							{#if leaderboards.get(seg.id) == null}
								<p class="muted small">Loading…</p>
							{:else if (leaderboards.get(seg.id) ?? []).length === 0}
								<p class="muted small">No efforts yet — be the first to run this segment.</p>
							{:else}
								<ol>
									{#each leaderboards.get(seg.id) ?? [] as entry (entry.effort.id)}
										<li class:viewer={entry.effort.user_id === auth.user?.id}>
											<span class="rank">#{entry.rank}</span>
											<a href="/u/{entry.athlete.id}" class="athlete">
												<span class="avatar-sm">
													{#if entry.athlete.avatar_url}
														<img src={entry.athlete.avatar_url} alt="" />
													{:else}
														{initial(entry.athlete.display_name)}
													{/if}
												</span>
												<span class="athlete-name">
													{entry.athlete.display_name ?? 'Runner'}
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
									Delete segment
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
	title="Delete segment?"
	message="This removes the segment and all its efforts. Cannot be undone."
	confirmLabel="Delete"
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
		text-align: left;
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
	}
	.athlete {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		flex: 1;
		text-decoration: none;
		color: inherit;
	}
	.avatar-sm {
		width: 1.6rem;
		height: 1.6rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: white;
		display: grid;
		place-items: center;
		font-size: 0.72rem;
		font-weight: 700;
		overflow: hidden;
	}
	.avatar-sm img {
		width: 100%;
		height: 100%;
		object-fit: cover;
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
