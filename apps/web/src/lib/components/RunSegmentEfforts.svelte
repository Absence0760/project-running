<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDuration } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import {
		fetchEffortsForRun,
		computeSegmentEffortsForRun,
		fetchRoutesIntersectingTrack,
		type SegmentEffortWithSegment,
	} from '$lib/core/data';
	import { pickAutoEffortRoute } from '$lib/segments/auto_segment_effort';
	import { distanceInPreferred } from '$lib/format/units.svelte';
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
	let loading = $state(true);

	async function load() {
		loading = true;
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
			} catch (e) {
				console.warn('segment effort compute failed', e);
			}
		}
		efforts = await fetchEffortsForRun(runId);
		loading = false;
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
{:else if efforts.length > 0}
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
