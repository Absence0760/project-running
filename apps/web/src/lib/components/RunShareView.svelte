<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDuration, formatPace, formatDistance, formatDate, sourceLabel, sourceColor } from '$lib/mock-data';
	import { fetchPublicRun, fetchClippedTrackForRun, fetchTrackByPath } from '$lib/data';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import RunSocial from '$lib/components/RunSocial.svelte';
	import RunPhotos from '$lib/components/RunPhotos.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import type { Run, TrackPoint } from '$lib/types';

	let {
		runId,
		compact = false,
		headerless = false,
		hideAnonCta = false,
	}: { runId: string; compact?: boolean; headerless?: boolean; hideAnonCta?: boolean } = $props();

	let run = $state<Run | null>(null);
	let track = $state<TrackPoint[]>([]);
	let loading = $state(true);
	let notFound = $state(false);

	onMount(async () => {
		const r = await fetchPublicRun(runId);
		if (r) {
			run = r;
			// Owner views render the unclipped track via a direct Storage
			// download. Non-owner viewers go through the
			// clip-public-track Edge Function so the unclipped blob
			// never crosses the wire — the public-run Storage policy
			// was dropped in 20260619_001 (decisions.md §33). The EF
			// fails closed (return [] on RPC error) so a transient
			// outage renders an empty map for non-owners; owners stay
			// alive because they take the direct-Storage path.
			//
			// fetchPublicRun deliberately does NOT pre-fetch the track
			// (audit/storage High); each branch fetches on its own to
			// keep the owner / non-owner data paths independent.
			const isOwner = auth.user?.id === r.user_id;
			if (isOwner && r.track_url) {
				try {
					track = (await fetchTrackByPath(r.track_url)) as TrackPoint[];
				} catch (e) {
					console.warn('Failed to fetch owner track', e);
					track = [];
				}
			} else if (!isOwner) {
				// Symmetric to the owner branch — without try/catch, an EF
				// outage / throttle / transient 503 throws past `loading
				// = false` and the share page hangs on "Loading…" with
				// no recovery short of a reload. Empty track here matches
				// the "run with no track" graceful state: run-meta still
				// renders, the map just doesn't mount.
				try {
					track = (await fetchClippedTrackForRun(r.id)) as TrackPoint[];
				} catch (e) {
					console.warn('Failed to fetch clipped track', e);
					track = [];
				}
			}
		} else {
			notFound = true;
		}
		loading = false;
	});

	let elevations = $derived(track.map((p) => p.ele ?? 0));

	// Linked-cursor index — same shape as /runs/[id]. ElevationProfile
	// onhover sets it; RunMap reads it. Idx-space is shared because
	// elevations derives 1:1 from the same track.
	let chartHoverIdx = $state<number | null>(null);

	let paceHeatmapActivity = $derived.by<'run' | 'walk' | 'cycle' | 'hike' | undefined>(() => {
		const key = run?.metadata?.['activity_type'];
		if (key === 'run' || key === 'walk' || key === 'cycle' || key === 'hike') return key;
		return undefined;
	});
</script>

{#if loading}
	<p class="status">Loading…</p>
{:else if notFound}
	<p class="status">Run not found.</p>
{:else if run}
	{#if !headerless}
		<h1 class:compact>{formatDate(run.started_at)}</h1>
	{/if}
	<div class="run-meta">
		<span>{formatDistance(run.distance_m)}</span>
		<span class="meta-sep">&middot;</span>
		<span>{formatDuration(run.duration_s)}</span>
		<span class="meta-sep">&middot;</span>
		<span>{formatPace(run.duration_s, run.distance_m)}</span>
		<span class="meta-sep">&middot;</span>
		<span class="source-badge" style="background: {sourceColor(run.source)}">{sourceLabel(run.source)}</span>
	</div>

	{#if track.length > 0}
		<div class="map-container" class:compact>
			<!--
				requireExplicitConsent=true gates MapTiler init behind a
				"Load map" tap until the user has accepted the cookie
				banner (auto-passes when accepted). Anon visitors on
				/share/run/[id] are the load-bearing case for this
				audit/cookie-consent (2026-05-25) finding.
			-->
			<RunMap
				{track}
				activity={paceHeatmapActivity}
				hoverIdx={chartHoverIdx}
				requireExplicitConsent
			/>
		</div>
	{/if}

	{#if elevations.some((e) => e > 0)}
		<section class="card">
			<h2>Elevation Profile</h2>
			<ElevationProfile
				{elevations}
				totalDistance={run.distance_m}
				onhover={(idx) => (chartHoverIdx = idx)}
			/>
		</section>
	{/if}

	<section class="card">
		<RunPhotos runId={run.id} runOwnerId={run.user_id} />
	</section>

	{#if auth.loggedIn}
		<section class="card">
			<RunSocial runId={run.id} runOwnerId={run.user_id} />
		</section>
	{:else if !hideAnonCta}
		<div class="cta">
			<p>Track your own runs and join the conversation</p>
			<a href="/login?signup=1" class="btn btn-primary">Sign up for Free</a>
		</div>
	{/if}
{/if}

<style>
	.status {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}

	h1.compact {
		font-size: 1.25rem;
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.run-meta {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xl);
		flex-wrap: wrap;
	}

	.meta-sep {
		color: var(--color-text-tertiary);
	}

	.source-badge {
		font-size: 0.65rem;
		font-weight: 600;
		color: white;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		text-transform: uppercase;
	}

	.map-container {
		height: 24rem;
		border-radius: var(--radius-lg);
		overflow: hidden;
		margin-bottom: var(--space-xl);
	}

	.map-container.compact {
		height: 18rem;
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}

	.cta {
		text-align: center;
		padding: var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}

	.cta p {
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
	}
</style>
