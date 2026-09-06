<script lang="ts">
	import { onMount } from 'svelte';
	import { formatPace, formatDistance, sourceLabel } from '$lib/core/mock-data';
	import { sourceColor, sourceInk } from '$lib/runs/source_badge';
	import { formatDate, formatDuration } from '$lib/format/time';
	import { fetchPublicRun, fetchClippedTrackForRun, fetchTrackByPath } from '$lib/core/data';
	import RunMap from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import RunSocial from '$lib/components/RunSocial.svelte';
	import RunPhotos from '$lib/components/RunPhotos.svelte';
	import RunGearChips from '$lib/components/RunGearChips.svelte';
	import FundraiserSection from '$lib/components/FundraiserSection.svelte';
	import ReportDialog from '$lib/components/ReportDialog.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { resolveTrackOwnership } from '$lib/runs/track_ownership';
	import { m } from '$lib/i18n/store.svelte';
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
	// Distinct from `notFound`: this page is mostly reached by someone the
	// runner shared a link with, and a stranger cannot tell a broken read from
	// a deleted run. Telling them the run does not exist is a claim; telling
	// them it could not be loaded is the truth, and it is the one they can act
	// on by retrying.
	let loadError = $state(false);

	async function load() {
		loading = true;
		notFound = false;
		loadError = false;
		const { run: r, error } = await fetchPublicRun(runId);
		if (error) {
			loadError = true;
			loading = false;
			return;
		}
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
			//
			// audit/storage (2026-05-25): track_url was removed from
			// the public_runs view in migration 20260924_001. The
			// owner branch derives the Storage path the same way the
			// clip-public-track EF does — both pin to the
			// `{user_id}/{run_id}.json.gz` shape that the CHECK
			// constraint on runs.track_url (20260621_001) enforces.
			//
			// This page is shell-less and mounts before the root
			// layout's auth gate resolves, so await auth.ready() before
			// reading the viewer id — otherwise an owner whose session
			// is still restoring reads null and gets misclassified as a
			// non-owner, taking the clip path (issue #347). Not a
			// security backstop; the EF re-derives identity from the JWT.
			const { isOwner } = await resolveTrackOwnership(
				auth.ready,
				() => auth.user?.id,
				r.user_id,
			);
			if (isOwner) {
				const ownerTrackPath = `${r.user_id}/${r.id}.json.gz`;
				try {
					track = (await fetchTrackByPath(ownerTrackPath)) as TrackPoint[];
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
	}

	onMount(load);

	let elevations = $derived(track.map((p) => p.ele ?? 0));

	// Linked-cursor index — same shape as /runs/[id]. ElevationProfile
	// onhover sets it; RunMap reads it. Idx-space is shared because
	// elevations derives 1:1 from the same track.
	let chartHoverIdx = $state<number | null>(null);

	let paceHeatmapActivity = $derived.by<'run' | 'walk' | 'cycle' | 'hike' | undefined>(() => {
		const key = run?.activity_type;
		if (key === 'run' || key === 'walk' || key === 'cycle' || key === 'hike') return key;
		return undefined;
	});

	// The runner's own caption (metadata.title) is the headline the
	// persona screenshots for social; fall back to the date when there's
	// no title. The OG <head> title already prefers the caption, so this
	// keeps the visible page body consistent with the share-card preview.
	let runTitle = $derived(
		((run?.metadata as Record<string, unknown> | null)?.title as string) ?? '',
	);

	let canReport = $derived(
		auth.loggedIn && run != null && auth.user?.id !== run.user_id,
	);
	let showReport = $state(false);
</script>

{#if loading}
	<p class="status">{m('shell.loading')}</p>
{:else if loadError}
	<p class="status" role="alert">
		{m('runDetail.loadErrorTitle')}
		<button class="btn btn-outline" onclick={load}>{m('runDetail.retry')}</button>
	</p>
{:else if notFound}
	<p class="status">{m('runShareView.runNotFound')}</p>
{:else if run}
	{#if !headerless}
		{#if runTitle}
			<h1 class:compact>{runTitle}</h1>
		{:else}
			<h1 class:compact>{formatDate(run.started_at)}</h1>
		{/if}
	{/if}
	<div class="run-meta">
		{#if runTitle}
			<span>{formatDate(run.started_at)}</span>
			<span class="meta-sep">&middot;</span>
		{/if}
		<span>{formatDistance(run.distance_m)}</span>
		<span class="meta-sep">&middot;</span>
		<span>{formatDuration(run.duration_s)}</span>
		<span class="meta-sep">&middot;</span>
		<span>{formatPace(run.duration_s, run.distance_m)}</span>
		<span class="meta-sep">&middot;</span>
		<span class="source-badge" style="background: {sourceColor(run.source)}; color: {sourceInk(run.source)}">{sourceLabel(run.source)}</span>
		{#if canReport}
			<button
				type="button"
				class="report-btn"
				aria-label={m('runDetail.reportRun')}
				title={m('runDetail.reportRun')}
				onclick={() => (showReport = true)}
			>
				<span class="material-symbols" aria-hidden="true">flag</span>
			</button>
		{/if}
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
			<h2>{m('runShareView.elevationProfile')}</h2>
			<ElevationProfile
				{elevations}
				totalDistance={run.distance_m}
				onhover={(idx) => (chartHoverIdx = idx)}
			/>
		</section>
	{/if}

	<FundraiserSection runId={run.id} isOwner={false} />

	<RunGearChips runId={run.id} runOwnerId={run.user_id} />

	<RunPhotos runId={run.id} runOwnerId={run.user_id} />

	{#if auth.loggedIn}
		<section class="card">
			<RunSocial runId={run.id} runOwnerId={run.user_id} />
		</section>
	{:else if !hideAnonCta}
		<div class="cta">
			<p>{m('runShareView.ctaTrackYourOwn')}</p>
			<a href="/login?signup=1" class="btn btn-primary">{m('runShareView.signUpForFree')}</a>
		</div>
	{/if}

	<ReportDialog
		open={showReport}
		targetKind="run"
		targetId={run.id}
		targetLabel={runTitle || formatDate(run.started_at)}
		onclose={() => (showReport = false)}
	/>
{/if}

<style>
	.status {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.report-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: none;
		border: none;
		padding: 0.15rem;
		margin-inline-start: 0.1rem;
		color: var(--color-text-tertiary);
		cursor: pointer;
		border-radius: var(--radius-sm);
	}
	.report-btn:hover {
		color: var(--color-danger-text);
	}
	.report-btn .material-symbols {
		font-size: 1.05rem;
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
		font-size: var(--font-size-section-label);
		font-weight: 600;
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
