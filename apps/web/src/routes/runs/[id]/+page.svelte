<script lang="ts">
	import { onMount } from 'svelte';
	import RunMap, { type SelectedSegment } from '$lib/components/RunMap.svelte';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import {
		formatDuration,
		formatPace,
		formatDistance,
		formatDate,
		sourceLabel,
		sourceColor,
	} from '$lib/mock-data';
	import { fetchRunById, deleteRun, makeRunPublic, updateRunMetadata, saveRunAsRoute, fetchWorkout } from '$lib/data';
	import type { PlanWorkout } from '$lib/types';
	import { toRunGpx, downloadFile } from '$lib/gpx';
	import { movingTimeSeconds, elevationGainMetres } from '$lib/run_stats';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import type { Run } from '$lib/types';

	let { data: pageData } = $props();

	let run = $state<Run | null>(null);
	let loading = $state(true);
	let linkedWorkout = $state<PlanWorkout | null>(null);
	/// Selected segment from the map. Set when the user clicks a point
	/// on the trace; cleared by tapping the overlay's close button or
	/// re-clicking the same area is reset by the next selection. Drives
	/// the floating "Segment details" card overlaying the map.
	let selectedSegment = $state<SelectedSegment | null>(null);
	let editing = $state(false);
	let editTitle = $state('');
	let editNotes = $state('');
	let showDeleteConfirm = $state(false);

	onMount(async () => {
		run = await fetchRunById(pageData.id);
		loading = false;
		// If the recorder linked this run to a structured workout, pull
		// the planned workout row so the review section can show its
		// title alongside the per-step planned/actual table.
		const planWorkoutId = (run?.metadata as Record<string, unknown> | null)?.['plan_workout_id'];
		if (typeof planWorkoutId === 'string') {
			try {
				linkedWorkout = await fetchWorkout(planWorkoutId);
			} catch (_) {
				/* silent — review section just hides the workout-name row */
			}
		}
		// Best-effort: pull the user's HR zones from the settings bag
		// so zone breakdowns on this run use the runner's own
		// thresholds rather than defaults. Silent on failure.
		try {
			const uid = auth.user?.id;
			if (uid) {
				const { loadSettings, effective } = await import('$lib/settings');
				const settings = await loadSettings(uid);
				const zones = effective<Record<string, number>>(settings, 'hr_zones');
				if (zones) {
					const z1 = zones.z1, z2 = zones.z2, z3 = zones.z3, z4 = zones.z4, z5 = zones.z5;
					if ([z1, z2, z3, z4, z5].every((z) => typeof z === 'number' && z > 0)) {
						zoneCutoffs = [z1, z2, z3, z4, z5];
					}
				}
			}
		} catch (_) {
			/* noop */
		}
	});

	let runTitle = $derived((run?.metadata as Record<string, unknown> | null)?.title as string ?? '');
	let runNotes = $derived((run?.metadata as Record<string, unknown> | null)?.notes as string ?? '');
	let estimatedCalories = $derived(run ? Math.round(70 * 1.0 * run.distance_m / 1000) : 0);

	/// Structured-workout review. The recorder writes three keys on
	/// `runs.metadata` after a planned workout: `plan_workout_id`,
	/// `workout_step_results` (per-step planned-vs-actual), and
	/// `workout_adherence`. See docs/metadata.md for the full shape.
	interface WorkoutStepResult {
		step_index: number;
		kind: string;
		rep_index?: number;
		rep_total?: number;
		target_distance_m: number;
		actual_distance_m: number;
		target_pace_sec_per_km: number;
		actual_pace_sec_per_km: number | null;
		duration_s: number;
		status: 'completed' | 'skipped';
	}

	let workoutStepResults = $derived.by<WorkoutStepResult[]>(() => {
		const v = (run?.metadata as Record<string, unknown> | null)?.['workout_step_results'];
		return Array.isArray(v) ? (v as WorkoutStepResult[]) : [];
	});

	let workoutAdherence = $derived(
		(run?.metadata as Record<string, unknown> | null)?.['workout_adherence'] as
			| 'completed'
			| 'partial'
			| 'abandoned'
			| undefined,
	);

	function stepLabel(s: WorkoutStepResult): string {
		switch (s.kind) {
			case 'warmup':
				return 'Warmup';
			case 'cooldown':
				return 'Cooldown';
			case 'steady':
				return 'Steady';
			case 'rep':
				return s.rep_index && s.rep_total
					? `Rep ${s.rep_index}/${s.rep_total}`
					: 'Rep';
			case 'recovery':
				return s.rep_index && s.rep_total
					? `Recovery ${s.rep_index}/${s.rep_total - 1}`
					: 'Recovery';
			default:
				return s.kind;
		}
	}

	function formatPaceSec(s: number | null): string {
		if (s == null || !Number.isFinite(s) || s <= 0) return '—';
		const m = Math.floor(s / 60);
		const sec = Math.round(s % 60);
		return `${m}:${sec.toString().padStart(2, '0')}/km`;
	}

	function paceDeltaLabel(s: WorkoutStepResult): string {
		if (s.actual_pace_sec_per_km == null) return '—';
		const d = s.actual_pace_sec_per_km - s.target_pace_sec_per_km;
		if (Math.abs(d) < 1) return 'on pace';
		const sign = d > 0 ? '+' : '−';
		return `${sign}${Math.abs(Math.round(d))}s`;
	}

	function paceDeltaClass(s: WorkoutStepResult): string {
		if (s.actual_pace_sec_per_km == null) return 'neutral';
		const d = Math.abs(s.actual_pace_sec_per_km - s.target_pace_sec_per_km);
		const tol = 10; // matches the recorder's default tolerance
		if (d <= tol) return 'on';
		if (d <= tol * 2) return 'amber';
		return 'off';
	}

	function startEdit() {
		editTitle = runTitle;
		editNotes = runNotes;
		editing = true;
	}

	async function saveEdit() {
		if (!run) return;
		try {
			await updateRunMetadata(run.id, { title: editTitle, notes: editNotes });
			const metadata = { ...(run.metadata as Record<string, unknown> ?? {}), title: editTitle, notes: editNotes };
			run = { ...run, metadata } as Run;
			editing = false;
		} catch (e) {
			showToast(`Save failed: ${e}`, 'error');
		}
	}

	function handleDelete() {
		if (!run) return;
		showDeleteConfirm = true;
	}

	async function confirmDelete() {
		if (!run) return;
		showDeleteConfirm = false;
		try {
			await deleteRun(run.id);
			goto('/runs');
		} catch (e) {
			showToast(`Delete failed: ${e}`, 'error');
		}
	}

	async function handleShare() {
		if (!run) return;
		try {
			await makeRunPublic(run.id);
			const url = `${window.location.origin}/share/run/${run.id}`;
			await navigator.clipboard.writeText(url);
			showToast('Share link copied to clipboard', 'success');
		} catch (e) {
			showToast(`Share failed: ${e}`, 'error');
		}
	}

	async function handleSaveAsRoute() {
		if (!run?.track || run.track.length < 2) return;
		const defaultName =
			((run.metadata as Record<string, unknown> | null)?.title as string) ||
			`Route from ${new Date(run.started_at).toLocaleDateString()}`;
		const name = window.prompt('Name this route', defaultName);
		if (!name || !name.trim()) return;
		try {
			const { id } = await saveRunAsRoute(
				run.id,
				name.trim(),
				run.track.map((p) => ({ lat: p.lat, lng: p.lng, ele: p.ele ?? null })),
			);
			showToast('Saved as route.', 'success');
			goto(`/routes/${id}`);
		} catch (e) {
			showToast(`Save failed: ${e}`, 'error');
		}
	}

	let generatingImage = $state(false);
	let shareCardEl: HTMLElement | undefined;

	/// Render the off-screen `.share-card` DOM node to a 1080×1080 PNG
	/// via `html-to-image`, then either invoke the Web Share API (with
	/// the PNG as a File) or fall back to a plain download + toast
	/// when Web Share isn't available or doesn't accept files.
	async function handleShareImage() {
		if (!run || generatingImage) return;
		generatingImage = true;
		try {
			// Dynamic import keeps the 30 KB lib out of the initial
			// bundle for users who never click Share-as-image.
			const { toPng } = await import('html-to-image');
			if (!shareCardEl) throw new Error('share card not ready');
			const dataUrl = await toPng(shareCardEl, {
				pixelRatio: 2,
				cacheBust: true,
			});
			const title =
				((run.metadata as Record<string, unknown> | null)?.title as string) ||
				`Run ${new Date(run.started_at).toISOString().slice(0, 10)}`;
			const fileName =
				title.replace(/[^a-z0-9\-_. ]/gi, '_').replace(/\s+/g, '_') + '.png';

			// Try Web Share API first — on mobile this pops the OS
			// share sheet with the image pre-attached, which is the
			// whole point of this feature. Fall through to a download
			// on desktop browsers that don't implement share-with-files.
			const blob = await (await fetch(dataUrl)).blob();
			const file = new File([blob], fileName, { type: 'image/png' });
			if (
				typeof navigator.share === 'function' &&
				navigator.canShare &&
				navigator.canShare({ files: [file] })
			) {
				await navigator.share({ title, files: [file] });
			} else {
				const a = document.createElement('a');
				a.href = dataUrl;
				a.download = fileName;
				a.click();
				showToast('Image saved.', 'success');
			}
		} catch (e) {
			const msg = (e as Error).message;
			// User cancelling a Web Share sheet raises; that's fine.
			if (!msg.includes('abort') && !msg.includes('cancel')) {
				showToast(`Couldn't generate image: ${msg}`, 'error');
			}
		} finally {
			generatingImage = false;
		}
	}

	function handleDownloadGpx() {
		if (!run?.track || run.track.length < 2) return;
		const title =
			((run.metadata as Record<string, unknown> | null)?.title as string) ||
			`Run ${new Date(run.started_at).toISOString().slice(0, 10)}`;
		const gpx = toRunGpx(
			title,
			run.started_at,
			run.track.map((p) => ({
				lat: p.lat,
				lng: p.lng,
				ele: p.ele ?? null,
				ts: p.ts ?? null,
			})),
		);
		const safeName = title.replace(/[^a-z0-9\-_. ]/gi, '_').replace(/\s+/g, '_');
		downloadFile(gpx, `${safeName}.gpx`, 'application/gpx+xml');
	}

	/**
	 * Mobile-recorded runs stamp the activity into `metadata.activity_type`.
	 * Map to a human label + Material Symbols icon.
	 */
	const activityMeta: Record<
		string,
		{ label: string; icon: string }
	> = {
		run: { label: 'Run', icon: 'directions_run' },
		walk: { label: 'Walk', icon: 'directions_walk' },
		cycle: { label: 'Cycle', icon: 'directions_bike' },
		hike: { label: 'Hike', icon: 'terrain' },
	};

	let activity = $derived.by(() => {
		const key = run?.metadata?.['activity_type'];
		if (typeof key !== 'string') return null;
		return activityMeta[key] ?? { label: key, icon: 'directions_run' };
	});

	/** Derived from the GPS track rather than stored, matching mobile. */
	let movingSeconds = $derived(run?.track ? movingTimeSeconds(run.track) : 0);

	/** Prefer a real track-based elevation gain over the randomly-generated
	 *  mock value. Falls back to 0 for runs without elevation data. */
	let realElevationGain = $derived(run?.track ? elevationGainMetres(run.track) : 0);

	/** Total steps are stored on mobile save in `metadata.steps`. */
	let totalSteps = $derived.by(() => {
		const v = run?.metadata?.['steps'];
		return typeof v === 'number' ? v : null;
	});

	/** Average cadence = steps / moving_time_minutes. Null when we don't
	 *  have enough data to compute meaningfully. */
	let avgCadence = $derived.by(() => {
		if (totalSteps == null || movingSeconds < 30) return null;
		return Math.round((totalSteps / (movingSeconds / 60)) || 0);
	});

	/** Average heart rate. Watch apps (watch_ios, watch_wear) record this
	 *  into `metadata.avg_bpm` during a run. See `docs/metadata.md`. */
	let avgBpm = $derived.by(() => {
		const v = run?.metadata?.['avg_bpm'];
		return typeof v === 'number' && v > 0 ? Math.round(v) : null;
	});

	/// Real HR zone breakdown. Requires per-point `bpm` on the track —
	/// which watch and phone recorders will start writing alongside GPS
	/// over the course of the next few recording passes. When the
	/// track carries BPM samples, we compute a %-of-time-in-zone
	/// distribution from the user's own zone thresholds (settings bag
	/// `hr_zones`, falling back to sensible defaults keyed off max
	/// HR). When it doesn't, the panel reports "No HR samples on this
	/// run" instead of rendering fake percentages.
	const zoneDefs = [
		{ zone: 'Zone 1', label: 'Recovery', color: '#90CAF9' },
		{ zone: 'Zone 2', label: 'Easy', color: '#4CAF50' },
		{ zone: 'Zone 3', label: 'Aerobic', color: '#FFC107' },
		{ zone: 'Zone 4', label: 'Threshold', color: '#FF9800' },
		{ zone: 'Zone 5', label: 'Max', color: '#F44336' },
	];

	/// Per-point BPM samples paired with their timestamps so the zone
	/// breakdown can be time-weighted instead of sample-count-weighted.
	/// Sample-count is a fine proxy when sampling is regular (~1 Hz),
	/// but Strava streams and watch FIT files often emit irregularly,
	/// and time-weighting is what every other running app shows.
	let bpmTimedSamples = $derived.by(() => {
		const track = run?.track ?? [];
		const out: { bpm: number; tMs: number | null }[] = [];
		for (const p of track) {
			const b = p.bpm;
			if (typeof b !== 'number' || b < 30 || b > 230) continue;
			const tMs = p.ts ? Date.parse(p.ts) : NaN;
			out.push({ bpm: b, tMs: Number.isFinite(tMs) ? tMs : null });
		}
		return out;
	});

	let bpmSamples = $derived(bpmTimedSamples.map((s) => s.bpm));

	/// Min / max / avg from the per-point BPM stream. Avg is a simple
	/// arithmetic mean of samples — close enough for display, not the
	/// time-integrated form.
	let bpmStats = $derived.by(() => {
		const samples = bpmSamples;
		if (samples.length === 0) return null;
		let min = samples[0];
		let max = samples[0];
		let sum = 0;
		for (const b of samples) {
			if (b < min) min = b;
			if (b > max) max = b;
			sum += b;
		}
		return { min, max, avg: Math.round(sum / samples.length) };
	});

	/// Zone upper bounds (BPM) from the user's settings bag, or sane
	/// defaults keyed off their max HR (or 220 − 30 when unknown).
	/// Fetched once on mount in the existing settings load path; we
	/// fall back here when they're absent.
	let zoneCutoffs = $state<[number, number, number, number, number] | null>(null);

	function zoneIndex(bpm: number, cutoffs: [number, number, number, number, number]): number {
		if (bpm <= cutoffs[0]) return 0;
		if (bpm <= cutoffs[1]) return 1;
		if (bpm <= cutoffs[2]) return 2;
		if (bpm <= cutoffs[3]) return 3;
		return 4;
	}

	let hrZones = $derived.by(() => {
		const samples = bpmTimedSamples;
		if (samples.length === 0) return [];
		// Cutoffs default to the classic Karvonen-ish bands at 60 / 70
		// / 80 / 90 / 100 % of max HR when the user hasn't set them.
		const cutoffs = zoneCutoffs ?? [114, 133, 152, 171, 190];

		// Time-weighted when timestamps are available on every sample.
		// Each sample's "weight" is half the gap to the previous sample
		// + half the gap to the next, so the zone of a long-held BPM
		// dominates over a momentary spike. When timestamps are absent
		// (e.g. Strava streams without time series) fall back to count.
		const haveTime = samples.every((s) => s.tMs !== null);
		const weights = new Array(samples.length).fill(1);
		if (haveTime) {
			const ts = samples.map((s) => s.tMs as number);
			for (let i = 0; i < ts.length; i++) {
				const prev = i > 0 ? ts[i] - ts[i - 1] : 0;
				const next = i < ts.length - 1 ? ts[i + 1] - ts[i] : 0;
				// Cap any single gap at 30 s so a paused recording can't
				// inflate one sample's slice into the entire run.
				const w = Math.min(30000, prev / 2) + Math.min(30000, next / 2);
				weights[i] = Math.max(0, w);
			}
		}

		const totals = [0, 0, 0, 0, 0];
		let totalWeight = 0;
		for (let i = 0; i < samples.length; i++) {
			const z = zoneIndex(samples[i].bpm, cutoffs);
			totals[z] += weights[i];
			totalWeight += weights[i];
		}
		if (totalWeight <= 0) {
			// Degenerate — no time elapsed between samples. Fall back to
			// sample count so we still render something.
			for (let i = 0; i < samples.length; i++) {
				totals[zoneIndex(samples[i].bpm, cutoffs)] += 1;
			}
			totalWeight = samples.length;
		}

		// `seconds` is meaningful only when haveTime; otherwise it's a
		// proxy unit and we hide it from the UI.
		return zoneDefs.map((def, i) => ({
			...def,
			pct: Math.round((totals[i] / totalWeight) * 100),
			seconds: haveTime ? Math.round(totals[i] / 1000) : null,
		}));
	});

	function formatZoneTime(s: number): string {
		const h = Math.floor(s / 3600);
		const m = Math.floor((s % 3600) / 60);
		const sec = s % 60;
		if (h > 0) return `${h}h ${m}m`;
		if (m > 0) return `${m}m ${sec}s`;
		return `${sec}s`;
	}

	let baseTrack = $derived(run ? (run.track ?? generateMockTrack(run.distance_m)) : []);
	let elevations = $derived(baseTrack.map((p) => p.ele ?? 20 + Math.random() * 30));

	let splits = $derived.by(() => {
		if (!run) return [];
		const distanceKm = run.distance_m / 1000;
		const numSplits = Math.ceil(distanceKm);
		const avgPaceSec = run.duration_s / distanceKm;
		return Array.from({ length: numSplits }, (_, i) => {
			const variance = (Math.random() - 0.5) * 20;
			const splitPace = avgPaceSec + variance;
			const splitDistance = i < numSplits - 1 ? 1000 : (distanceKm - Math.floor(distanceKm)) * 1000 || 1000;
			const elevation = Math.round((Math.random() - 0.3) * 15);
			return { km: i + 1, pace_s: Math.round(splitPace), distance_m: splitDistance, elevation_m: elevation };
		});
	});

	function generateMockTrack(distanceM: number) {
		const points = Math.max(50, Math.round(distanceM / 20));
		const baseLat = -37.8136;
		const baseLng = 144.9631;
		const track = [];
		for (let i = 0; i < points; i++) {
			const angle = (i / points) * Math.PI * 2;
			const radius = (distanceM / 1000) * 0.004;
			track.push({
				lat: baseLat + Math.sin(angle) * radius + (Math.random() - 0.5) * 0.0005,
				lng: baseLng + Math.cos(angle) * radius + (Math.random() - 0.5) * 0.0005,
				ele: 20 + Math.sin(angle * 3) * 15 + Math.random() * 5,
			});
		}
		track.push(track[0]);
		return track;
	}
</script>

{#if loading}
	<div class="run-detail"><p class="loading-text">&nbsp;</p></div>
{:else if run}
<div class="run-detail">
	<a href="/runs" class="back-link page-back">
		<span class="material-symbols">arrow_back</span> All runs
	</a>
	<div class="run-detail-body">
	<main class="map-panel">
		<RunMap
			track={baseTrack}
			animatable
			onSegmentSelect={(seg) => (selectedSegment = seg)}
		/>
		<!-- Nike-style segment-detail card. Click any point on the trace
		     to drop a pin and see ±150 m of stats around that location:
		     distance covered, elapsed time (when the track has per-point
		     timestamps), avg pace, avg HR, elevation gain / loss. -->
		{#if selectedSegment}
			<aside class="segment-card">
				<header class="segment-card-head">
					<span class="segment-eyebrow">SEGMENT</span>
					<button
						class="segment-close"
						aria-label="Close segment details"
						onclick={() => (selectedSegment = null)}
					>
						<span class="material-symbols">close</span>
					</button>
				</header>
				<div class="segment-grid">
					<div class="segment-stat">
						<span class="segment-stat-label">Distance</span>
						<span class="segment-stat-value">{formatDistance(selectedSegment.distance_m)}</span>
					</div>
					{#if selectedSegment.duration_s != null}
						<div class="segment-stat">
							<span class="segment-stat-label">Time</span>
							<span class="segment-stat-value">{formatDuration(selectedSegment.duration_s)}</span>
						</div>
					{/if}
					{#if selectedSegment.avg_pace_sec_per_km != null}
						<div class="segment-stat">
							<span class="segment-stat-label">Pace</span>
							<span class="segment-stat-value">
								{formatPace(selectedSegment.avg_pace_sec_per_km, 1000)}
							</span>
						</div>
					{/if}
					{#if selectedSegment.avg_bpm != null}
						<div class="segment-stat">
							<span class="segment-stat-label">Avg HR</span>
							<span class="segment-stat-value">{selectedSegment.avg_bpm} bpm</span>
						</div>
					{/if}
					{#if selectedSegment.ele_gain_m > 0 || selectedSegment.ele_loss_m > 0}
						<div class="segment-stat">
							<span class="segment-stat-label">Elev</span>
							<span class="segment-stat-value">
								{#if selectedSegment.ele_gain_m > 0}+{selectedSegment.ele_gain_m}m{/if}
								{#if selectedSegment.ele_gain_m > 0 && selectedSegment.ele_loss_m > 0}
									·
								{/if}
								{#if selectedSegment.ele_loss_m > 0}−{selectedSegment.ele_loss_m}m{/if}
							</span>
						</div>
					{/if}
				</div>
			</aside>
		{/if}
	</main>

	<aside class="stats-panel">
		<header class="detail-header">
			<div>
				<h1>{runTitle || formatDate(run.started_at)}</h1>
				{#if runTitle}
					<div class="run-date-sub">{formatDate(run.started_at)}</div>
				{/if}
				{#if runNotes}
					<p class="run-notes">{runNotes}</p>
				{/if}
				{#if activity}
					<div class="detail-meta">
						<span class="activity-badge">
							<span class="material-symbols">{activity.icon}</span>
							{activity.label}
						</span>
					</div>
				{/if}
			</div>
			<div class="header-actions">
				<span class="source-badge" style="background: {sourceColor(run.source)}"
					>{sourceLabel(run.source)}</span>
				{#if auth.loggedIn}
					<div class="action-btns">
						<button class="icon-btn" title="Edit" onclick={startEdit}>
							<span class="material-symbols">edit</span>
						</button>
						<button class="icon-btn" title="Share link" onclick={handleShare}>
							<span class="material-symbols">share</span>
						</button>
						<button
							class="icon-btn"
							title="Download GPX"
							onclick={handleDownloadGpx}
							disabled={!run?.track || run.track.length < 2}
						>
							<span class="material-symbols">download</span>
						</button>
						<button
							class="icon-btn"
							title="Save as route"
							onclick={handleSaveAsRoute}
							disabled={!run?.track || run.track.length < 2}
						>
							<span class="material-symbols">bookmark_add</span>
						</button>
						<button
							class="icon-btn"
							title="Share as image"
							onclick={handleShareImage}
							disabled={generatingImage}
						>
							<span class="material-symbols">image</span>
						</button>
						<button class="icon-btn danger" title="Delete" onclick={handleDelete}>
							<span class="material-symbols">delete</span>
						</button>
					</div>
				{/if}
			</div>
		</header>

		{#if editing}
			<div class="edit-form">
				<input type="text" bind:value={editTitle} placeholder="Run title" class="edit-input" />
				<textarea bind:value={editNotes} placeholder="Notes" class="edit-textarea" rows="2"></textarea>
				<div class="edit-actions">
					<button class="btn-sm btn-outline-sm" onclick={() => editing = false}>Cancel</button>
					<button class="btn-sm btn-primary-sm" onclick={saveEdit}>Save</button>
				</div>
			</div>
		{/if}

		<!-- Key stats -->
		<div class="key-stats">
			<div class="key-stat">
				<span class="key-stat-value">{formatDistance(run.distance_m)}</span>
				<span class="key-stat-label">Distance</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{formatDuration(run.duration_s)}</span>
				<span class="key-stat-label">Time</span>
			</div>
			{#if movingSeconds > 0 && movingSeconds !== run.duration_s}
				<div class="key-stat">
					<span class="key-stat-value">{formatDuration(movingSeconds)}</span>
					<span class="key-stat-label">Moving</span>
				</div>
			{/if}
			<div class="key-stat">
				<span class="key-stat-value"
					>{formatPace(
						movingSeconds > 0 ? movingSeconds : run.duration_s,
						run.distance_m
					)}</span
				>
				<span class="key-stat-label">Avg Pace</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{realElevationGain} m</span>
				<span class="key-stat-label">Elevation</span>
			</div>
			{#if estimatedCalories > 0}
				<div class="key-stat">
					<span class="key-stat-value">{estimatedCalories}</span>
					<span class="key-stat-label">Calories kcal</span>
				</div>
			{/if}
			{#if totalSteps != null}
				<div class="key-stat">
					<span class="key-stat-value">{totalSteps.toLocaleString()}</span>
					<span class="key-stat-label">Steps</span>
				</div>
			{/if}
			{#if avgCadence != null}
				<div class="key-stat">
					<span class="key-stat-value">{avgCadence}</span>
					<span class="key-stat-label">Cadence spm</span>
				</div>
			{/if}
			{#if avgBpm != null}
				<div class="key-stat">
					<span class="key-stat-value">{avgBpm}</span>
					<span class="key-stat-label">Avg HR bpm</span>
				</div>
			{/if}
		</div>

		<!-- Elevation Profile -->
		<section class="section">
			<h2>Elevation Profile</h2>
			<ElevationProfile {elevations} totalDistance={run.distance_m} />
		</section>

		<!-- Structured workout review — only shown when the recorder
		     linked this run to a planned `plan_workouts` row. Driven
		     entirely by `metadata.workout_step_results` so the table
		     stays in sync without a second query. -->
		{#if workoutStepResults.length > 0}
			<section class="section workout-review">
				<header class="workout-header">
					<h2>Workout</h2>
					{#if workoutAdherence}
						<span class="workout-adherence workout-adherence-{workoutAdherence}">
							{workoutAdherence}
						</span>
					{/if}
				</header>
				{#if linkedWorkout}
					<p class="workout-name">
						{linkedWorkout.notes ?? linkedWorkout.kind}
						<span class="workout-target">
							· {Math.round((linkedWorkout.target_distance_metres ?? 0) / 1000 * 10) / 10} km planned
						</span>
					</p>
				{/if}
				<table class="workout-table">
					<thead>
						<tr>
							<th>Step</th>
							<th class="num">Plan</th>
							<th class="num">Actual</th>
							<th class="num">Pace</th>
							<th class="num">Δ</th>
						</tr>
					</thead>
					<tbody>
						{#each workoutStepResults as s}
							<tr class:skipped={s.status === 'skipped'}>
								<td>{stepLabel(s)}</td>
								<td class="num">{(s.target_distance_m / 1000).toFixed(2)} km</td>
								<td class="num">{(s.actual_distance_m / 1000).toFixed(2)} km</td>
								<td class="num">{formatPaceSec(s.actual_pace_sec_per_km)}</td>
								<td class="num pace-delta pace-delta-{paceDeltaClass(s)}">
									{s.status === 'skipped' ? 'skip' : paceDeltaLabel(s)}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</section>
		{/if}

		<!-- Splits -->
		<section class="section">
			<h2>Splits</h2>
			<table class="splits-table">
				<thead>
					<tr>
						<th>Km</th>
						<th>Pace</th>
						<th>Elev</th>
					</tr>
				</thead>
				<tbody>
					{#each splits as split}
						<tr>
							<td>{split.km}</td>
							<td class="split-pace">
								{Math.floor(split.pace_s / 60)}:{String(split.pace_s % 60).padStart(2, '0')}
							</td>
							<td class="split-elev" class:positive={split.elevation_m > 0} class:negative={split.elevation_m < 0}>
								{split.elevation_m > 0 ? '+' : ''}{split.elevation_m} m
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</section>

		<!-- HR zones — real distribution when the track carries per-
		     point BPM samples, honest "no data" card otherwise. The
		     recording clients (phone + watches) will start writing
		     `bpm` alongside GPS over the next few recording passes;
		     historical runs that only stored `metadata.avg_bpm` render
		     the empty-state copy. -->
		<section class="section">
			<h2>Heart Rate Zones</h2>
			{#if hrZones.length > 0}
				{#if bpmStats}
					<div class="hr-stats">
						<div class="hr-stat"><span class="hr-stat-label">Avg</span><span class="hr-stat-value">{bpmStats.avg}</span></div>
						<div class="hr-stat"><span class="hr-stat-label">Min</span><span class="hr-stat-value">{bpmStats.min}</span></div>
						<div class="hr-stat"><span class="hr-stat-label">Max</span><span class="hr-stat-value">{bpmStats.max}</span></div>
					</div>
				{/if}
				<div class="hr-bar">
					{#each hrZones as zone}
						<div
							class="hr-segment"
							style="width: {zone.pct}%; background: {zone.color}"
							title="{zone.zone}: {zone.pct}%{zone.seconds != null ? ` (${formatZoneTime(zone.seconds)})` : ''}"
						></div>
					{/each}
				</div>
				<div class="hr-legend">
					{#each hrZones as zone}
						<div class="hr-legend-item">
							<span class="hr-dot" style="background: {zone.color}"></span>
							<span class="hr-zone-name">{zone.label}</span>
							{#if zone.seconds != null}
								<span class="hr-zone-time">{formatZoneTime(zone.seconds)}</span>
							{/if}
							<span class="hr-zone-pct">{zone.pct}%</span>
						</div>
					{/each}
				</div>
			{:else}
				<p class="hr-empty">
					{#if avgBpm != null}
						Only the run's average heart rate was captured ({avgBpm}&nbsp;bpm).
						A full zone distribution needs per-point samples, which the
						recording apps will start writing alongside GPS soon.
					{:else}
						No heart-rate data on this run.
					{/if}
				</p>
			{/if}
		</section>
	</aside>
	</div>
</div>

<ConfirmDialog
	open={showDeleteConfirm}
	title="Delete run"
	message="Delete this run? This cannot be undone."
	confirmLabel="Delete"
	onconfirm={confirmDelete}
	oncancel={() => showDeleteConfirm = false}
	danger
/>

<!-- Off-screen share card. 1080 square, rendered to PNG by
     `html-to-image` when the user taps Share-as-image. Lives outside
     the main layout so it doesn't affect scrolling; positioned
     `fixed` at top:-9999px so it still has real layout dimensions
     (pure `display:none` would zero them out and break the canvas
     capture). Background tint + gradient matches the dashboard
     primary, independent of the active theme. -->
<div
	bind:this={shareCardEl}
	class="share-card"
	aria-hidden="true"
>
	<div class="share-card-inner">
		<div class="share-card-eyebrow">Better Runner</div>
		<div class="share-card-stats">
			<div class="share-stat">
				<div class="share-stat-label">Distance</div>
				<div class="share-stat-value">{formatDistance(run.distance_m)}</div>
			</div>
			<div class="share-stat">
				<div class="share-stat-label">Time</div>
				<div class="share-stat-value">{formatDuration(run.duration_s)}</div>
			</div>
			<div class="share-stat">
				<div class="share-stat-label">Pace</div>
				<div class="share-stat-value">
					{formatPace(run.duration_s, run.distance_m)}
				</div>
			</div>
		</div>
		<div class="share-card-date">
			{formatDate(run.started_at)}
		</div>
	</div>
</div>
{/if}

<style>
	.loading-text {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
	}

	.run-detail {
		display: flex;
		flex-direction: column;
		height: 100vh;
	}

	.run-detail-body {
		display: flex;
		flex: 1;
		min-height: 0;
	}

	.page-back {
		padding: 0.6rem var(--space-lg);
		font-size: 0.9rem;
		font-weight: 500;
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}
	.page-back .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}

	.map-panel {
		flex: 3;
		background: var(--color-bg-tertiary);
		position: relative;
	}

	.segment-card {
		position: absolute;
		left: 12px;
		bottom: 12px;
		min-width: 16rem;
		max-width: calc(100% - 24px);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
		padding: 0.6rem 0.8rem;
		z-index: 5;
	}

	.segment-card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		margin-bottom: 0.4rem;
	}

	.segment-eyebrow {
		font-size: 0.65rem;
		font-weight: 700;
		letter-spacing: 0.08em;
		color: var(--color-primary);
	}

	.segment-close {
		background: transparent;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0.1rem;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-sm);
	}

	.segment-close:hover {
		color: var(--color-text);
		background: var(--color-bg-tertiary);
	}

	.segment-close .material-symbols {
		font-size: 1.05rem;
	}

	.segment-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(5rem, 1fr));
		gap: 0.4rem 0.9rem;
	}

	.segment-stat {
		display: flex;
		flex-direction: column;
	}

	.segment-stat-label {
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
	}

	.segment-stat-value {
		font-size: 0.95rem;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.stats-panel {
		flex: 2;
		border-left: 1px solid var(--color-border);
		padding: var(--space-xl);
		overflow-y: auto;
		background: var(--color-surface);
	}

	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.25rem;
		font-weight: 700;
	}

	.detail-meta {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin-top: var(--space-xs);
		flex-wrap: wrap;
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		text-decoration: none;
	}

	.back-link:hover {
		color: var(--color-primary);
	}

	.activity-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		padding: 0.2rem 0.6rem;
		border-radius: 9999px;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		font-weight: 600;
	}

	.activity-badge .material-symbols {
		font-size: 0.95rem;
	}

	h2 {
		font-size: 0.9rem;
		font-weight: 600;
		margin-bottom: var(--space-md);
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.source-badge {
		font-size: 0.65rem;
		font-weight: 600;
		color: white;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}

	.key-stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
		padding-bottom: var(--space-xl);
		border-bottom: 1px solid var(--color-border);
	}

	.key-stat {
		display: flex;
		flex-direction: column;
	}

	.key-stat-value {
		font-size: 1.1rem;
		font-weight: 700;
	}

	.key-stat-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.section {
		margin-bottom: var(--space-xl);
	}

	.splits-table {
		width: 100%;
		border-collapse: collapse;
	}

	.splits-table th {
		text-align: left;
		font-size: 0.7rem;
		font-weight: 500;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
	}

	.splits-table td {
		padding: var(--space-sm) 0;
		font-size: 0.85rem;
		border-bottom: 1px solid var(--color-bg-secondary);
	}

	.split-pace {
		font-family: 'SF Mono', 'Menlo', monospace;
		font-weight: 600;
	}

	.split-elev {
		font-size: 0.8rem;
	}

	.split-elev.positive {
		color: var(--color-danger);
	}

	.workout-review .workout-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
	}

	.workout-adherence {
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: 0.15rem 0.5rem;
		border-radius: 9999px;
	}

	.workout-adherence-completed {
		background: rgba(16, 185, 129, 0.12);
		color: #10b981;
	}

	.workout-adherence-partial {
		background: rgba(245, 158, 11, 0.12);
		color: #d97706;
	}

	.workout-adherence-abandoned {
		background: rgba(239, 68, 68, 0.12);
		color: #ef4444;
	}

	.workout-name {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
	}

	.workout-target {
		color: var(--color-text-tertiary);
	}

	.workout-table {
		width: 100%;
		border-collapse: collapse;
	}

	.workout-table th {
		text-align: left;
		font-size: 0.7rem;
		font-weight: 500;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
	}

	.workout-table th.num,
	.workout-table td.num {
		text-align: right;
		font-variant-numeric: tabular-nums;
	}

	.workout-table td {
		padding: var(--space-sm) 0;
		font-size: 0.82rem;
		border-bottom: 1px solid var(--color-bg-secondary);
	}

	.workout-table tr.skipped td {
		opacity: 0.55;
	}

	.pace-delta {
		font-weight: 600;
	}

	.pace-delta-on { color: #10b981; }
	.pace-delta-amber { color: #d97706; }
	.pace-delta-off { color: #ef4444; }
	.pace-delta-neutral { color: var(--color-text-tertiary); }

	.split-elev.negative {
		color: var(--color-secondary);
	}

	.hr-bar {
		display: flex;
		height: 1.5rem;
		border-radius: var(--radius-sm);
		overflow: hidden;
		margin-bottom: var(--space-md);
	}

	.hr-segment {
		transition: width var(--transition-base);
	}

	.hr-legend {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}

	.hr-legend-item {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.8rem;
	}

	.hr-dot {
		width: 0.6rem;
		height: 0.6rem;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.hr-zone-name {
		flex: 1;
		color: var(--color-text-secondary);
	}

	.hr-zone-pct {
		font-weight: 600;
		font-family: 'SF Mono', 'Menlo', monospace;
		font-size: 0.75rem;
	}

	.hr-zone-time {
		color: var(--color-text-secondary);
		font-family: 'SF Mono', 'Menlo', monospace;
		font-size: 0.72rem;
		font-variant-numeric: tabular-nums;
	}

	.hr-stats {
		display: flex;
		gap: var(--space-md);
		margin-bottom: var(--space-sm);
	}

	.hr-stat {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		min-width: 3rem;
	}

	.hr-stat-label {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-secondary);
	}

	.hr-stat-value {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.run-date-sub {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.run-notes {
		margin-top: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
	}

	.header-actions {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: var(--space-sm);
	}

	.action-btns {
		display: flex;
		gap: var(--space-xs);
	}

	.icon-btn {
		background: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: var(--space-xs);
		cursor: pointer;
		color: var(--color-text-secondary);
		display: flex;
		align-items: center;
	}

	.icon-btn:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.icon-btn.danger:hover {
		border-color: var(--color-danger, #ef4444);
		color: var(--color-danger, #ef4444);
	}

	.edit-form {
		margin-bottom: var(--space-lg);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.edit-input, .edit-textarea {
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		font-size: 0.85rem;
		background: var(--color-surface);
		color: var(--color-text);
	}

	.edit-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
	}

	.btn-sm {
		padding: var(--space-xs) var(--space-md);
		border-radius: var(--radius-sm);
		font-size: 0.8rem;
		font-weight: 600;
		cursor: pointer;
	}

	.btn-outline-sm {
		background: none;
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
	}

	.btn-primary-sm {
		background: var(--color-primary);
		border: none;
		color: white;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1rem;
	}

	.hr-empty {
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		margin: 0;
	}

	.share-card {
		position: fixed;
		top: -9999px;
		left: -9999px;
		width: 1080px;
		height: 1080px;
		background: linear-gradient(135deg, #F2A07B 0%, #B9A7E8 55%, #6B4C8A 100%);
		color: #FFFFFF;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 96px;
		font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
	}
	.share-card-inner {
		width: 100%;
		height: 100%;
		display: flex;
		flex-direction: column;
		justify-content: space-between;
	}
	.share-card-eyebrow {
		font-size: 48px;
		font-weight: 800;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		opacity: 0.9;
	}
	.share-card-stats {
		display: grid;
		grid-template-columns: 1fr;
		gap: 64px;
	}
	.share-stat {
		display: flex;
		flex-direction: column;
	}
	.share-stat-label {
		font-size: 32px;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		opacity: 0.7;
	}
	.share-stat-value {
		font-size: 120px;
		font-weight: 900;
		line-height: 1;
		margin-top: 8px;
	}
	.share-card-date {
		font-size: 42px;
		font-weight: 600;
		opacity: 0.75;
	}
</style>
