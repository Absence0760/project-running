<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDuration } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import {
		fetchEffortsForRunWithError,
		computeSegmentEffortsForRun,
		fetchRoutesIntersectingTrack,
		computeGlobalSegmentEffortsForRun,
		fetchGlobalEffortsForRun,
		type SegmentEffortWithSegment,
		type GlobalSegmentEffortWithSegment,
	} from '$lib/core/data';
	import { pickAutoEffortRoute } from '$lib/segments/auto_segment_effort';
	import { distanceInPreferred } from '$lib/format/units.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import type { TrackPoint } from '$lib/types';

	function trackLengthM(pts: TrackPoint[]): number {
		let total = 0;
		for (let i = 1; i < pts.length; i++) {
			const a = pts[i - 1];
			const b = pts[i];
			const dLat = ((b.lat - a.lat) * Math.PI) / 180;
			const dLng = ((b.lng - a.lng) * Math.PI) / 180;
			const lat1 = (a.lat * Math.PI) / 180;
			const lat2 = (b.lat * Math.PI) / 180;
			const h =
				Math.sin(dLat / 2) ** 2 +
				Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
			total += 2 * 6_371_000 * Math.asin(Math.min(1, Math.sqrt(h)));
		}
		return total;
	}

	interface Props {
		runId: string;
		runOwnerId: string;
		routeId: string | null;
		track: TrackPoint[];
	}
	let { runId, runOwnerId, routeId, track }: Props = $props();

	let efforts = $state<SegmentEffortWithSegment[]>([]);
	let globalEfforts = $state<GlobalSegmentEffortWithSegment[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	const isOwner = $derived(runOwnerId === auth.user?.id);

	async function load() {
		loading = true;
		loadError = null;
		// Auto-effort generation per §37 v1: when the run owner views
		// the detail page, we walk the track against any segments on
		// the parent route and INSERT new efforts. The unique
		// constraint makes this idempotent.
		if (track.length > 1) {
			try {
				// Imported runs land with route_id null (strava persona #21), so
				// they never got segment efforts. When the track is an
				// unambiguous end-to-end match for one of the owner's saved
				// routes, compute against that route's segments — otherwise fall
				// back to the linked route_id. pickAutoEffortRoute returns null
				// for partial / ambiguous matches so no wrong efforts are written.
				let effortRouteId = routeId;
				if (!effortRouteId) {
					const candidates = await fetchRoutesIntersectingTrack(track);
					effortRouteId = pickAutoEffortRoute(candidates, trackLengthM(track));
				}
				if (effortRouteId) {
					await computeSegmentEffortsForRun({
						run_id: runId,
						user_id: runOwnerId,
						route_id: effortRouteId,
						track,
					});
				}
				// Catalogue-segment backfill (decisions §231): score the run
				// against the free-standing global/famous-segment geometries it
				// matches end-to-end. Owner-only; RLS also gates the write.
				if (isOwner) {
					await computeGlobalSegmentEffortsForRun({ run_id: runId, user_id: runOwnerId, track });
				}
			} catch (e) {
				console.warn('segment effort compute failed', e);
			}
		}
		try {
			const [res, globals] = await Promise.all([
				fetchEffortsForRunWithError(runId),
				fetchGlobalEffortsForRun(runId),
			]);
			if (res.error) {
				loadError = res.error;
				return;
			}
			efforts = res.efforts;
			globalEfforts = globals;
		} catch (e) {
			loadError = e instanceof Error ? e.message : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function fmtDist(m: number): string {
		const { value, unit } = distanceInPreferred(m);
		return `${value.toFixed(2)} ${unit}`;
	}

	function fmtTime(s: number): string {
		return formatDuration(Math.round(s));
	}

	function rankClass(rank: number): string {
		if (rank === 1) return 'gold';
		if (rank <= 3) return 'silver';
		if (rank <= 10) return 'bronze';
		return '';
	}
</script>

{#if loading}
	<p class="muted">{m('segmentEfforts.checking')}</p>
{:else if loadError}
	<div class="error-banner" role="alert">
		<span class="material-symbols" aria-hidden="true">error</span>
		<div>
			<strong>{m('runs.loadFailed')}</strong>
			<span class="error-detail">{loadError}</span>
		</div>
		<button class="btn btn-outline btn-sm" onclick={load}>{m('runs.retry')}</button>
	</div>
{:else if efforts.length > 0 || globalEfforts.length > 0}
	{#if efforts.length > 0}
		<ul class="efforts">
			{#each efforts as e (e.effort.id)}
				<li>
					<a class="effort-row" href="/routes/{e.segment.route_id}#segment-{e.segment.id}">
						<div class="effort-meta">
							<strong>{e.segment.name}</strong>
							<span class="muted small">
								{fmtDist(Number(e.segment.length_m ?? Number(e.segment.end_distance_m) - Number(e.segment.start_distance_m)))}
							</span>
						</div>
						<span class="rank-pill {rankClass(e.rank)}">#{e.rank}</span>
						<span class="time">{fmtTime(e.effort.time_seconds)}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
	{#if globalEfforts.length > 0}
		<p class="section-label">{m('segmentEfforts.catalogueHeading')}</p>
		<ul class="efforts">
			{#each globalEfforts as e (e.effort.id)}
				<li>
					<a class="effort-row" href="/segments/{e.segment.id}">
						<div class="effort-meta">
							<strong>{e.segment.name}</strong>
							<span class="muted small">
								{fmtDist(Number(e.segment.distance_m))}
								{#if e.segment.region}<span class="meta-sep">·</span>{e.segment.region}{/if}
							</span>
						</div>
						<span class="rank-pill {rankClass(e.rank)}">#{e.rank}</span>
						<span class="time">{fmtTime(e.effort.time_seconds)}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
{:else if routeId}
	<p class="muted">
		{m('segmentEfforts.none')}
	</p>
{:else}
	<p class="muted">
		{m('segmentEfforts.linkHint')}
	</p>
{/if}

<style>
	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		margin: 0;
	}
	.muted.small {
		font-size: 0.78rem;
	}
	.section-label {
		margin: 0.6rem 0 0.2rem;
		font-size: 0.72rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
	}
	.meta-sep {
		margin: 0 0.3rem;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.3rem;
	}
	.efforts {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.effort-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: 0.5rem 0.75rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
	}
	.effort-row:hover {
		background: color-mix(in srgb, var(--color-primary) 8%, var(--color-bg-secondary));
	}
	.effort-meta {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.effort-meta strong {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.rank-pill {
		display: inline-grid;
		place-items: center;
		min-width: 2.4rem;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		font-size: 0.78rem;
		font-weight: 700;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
	}
	.rank-pill.gold {
		background: #f59e0b;
		color: white;
	}
	.rank-pill.silver {
		background: #94a3b8;
		color: white;
	}
	.rank-pill.bronze {
		background: #b45309;
		color: white;
	}
	.time {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
</style>
