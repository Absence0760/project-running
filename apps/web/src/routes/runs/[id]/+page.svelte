<script lang="ts">
	import { onMount } from 'svelte';
	import { fmtPace } from '$lib/format/units.svelte';
	import { env } from '$env/dynamic/public';
	import RunMap, { type SelectedSegment } from '$lib/components/RunMap.svelte';
	import RoutePreviewScrubber from '$lib/components/RoutePreviewScrubber.svelte';
	import { interpolateAlongRoute } from '$lib/routes/route_geometry';
	import { buildLocalStaticMapUrl, buildStaticMapUrl } from '$lib/routes/static_map';
	const PUBLIC_MAPTILER_KEY = env.PUBLIC_MAPTILER_KEY ?? '';
	const PUBLIC_TILE_STYLE_URL = env.PUBLIC_TILE_STYLE_URL ?? '';
	import ElevationProfile from '$lib/components/ElevationProfile.svelte';
	import RunSocial from '$lib/components/RunSocial.svelte';
	import RunPhotos from '$lib/components/RunPhotos.svelte';
	import RunGearChips from '$lib/components/RunGearChips.svelte';
	import RunSegmentEfforts from '$lib/components/RunSegmentEfforts.svelte';
	import RouteHistory from '$lib/components/RouteHistory.svelte';
	import SplitPane from '$lib/components/SplitPane.svelte';
	import { formatPace, formatSpeed, formatDistance, sourceLabel, sourceColor } from '$lib/core/mock-data';
	import { formatDate, formatDuration } from '$lib/format/time';
	import {
		fetchRunById,
		deleteRun,
		makeRunPublic,
		updateRunMetadata,
		saveRunAsRoute,
		fetchWorkout,
		fetchRunMatchedTrack,
		fetchRoutesIntersectingTrack,
		linkRunToRoute,
		enqueueRunRematch,
		type RunMatchInfo,
		type RouteMatchCandidate,
	} from '$lib/core/data';
	import { applyRunMetadataPatch } from '$lib/core/data_normalise';
	import type { PlanWorkout } from '$lib/types';
	import { toRunGpx, downloadFile } from '$lib/routes/gpx';
	import { movingTimeSeconds, elevationGainMetres, computeRealSplits } from '$lib/runs/run_stats';
	import { gradeAdjustedPaceSecPerKm } from '$lib/runs/grade_adjusted_pace';
	import { defaultZoneCutoffs } from '$lib/training/hr_zones';
	import { afterNavigate, goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { isInAnyZone, PRIVACY_ZONES_KEY, type PrivacyZone } from '$lib/routes/privacy';
	import {
		estimateRunCalories,
		ACTIVITY_KCAL_PER_KG_PER_KM,
		type CalorieGender,
	} from '$lib/runs/calories';
	import { supabase } from '$lib/core/supabase';
	import { m } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	let { data: pageData } = $props();

	let run = $state<Run | null>(null);
	let loading = $state(true);

	/// Track where the user came from so the in-page back button can
	/// genuinely go BACK (history.back) — which pops the history entry
	/// and lets /runs's snapshot.restore fire, preserving the loaded
	/// list + scroll position. Falling through to <a href="/runs"> would
	/// push a fresh entry and the user would land at the top of an
	/// empty list. Captured on the first afterNavigate after mount so
	/// SvelteKit's own forward navigations within this page (rare) don't
	/// overwrite it.
	let cameFromRuns = $state(false);
	afterNavigate(({ from }) => {
		if (from?.url.pathname === '/runs' && !cameFromRuns) {
			cameFromRuns = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromRuns) {
			e.preventDefault();
			history.back();
		}
		// else: <a href="/runs"> falls through and SvelteKit does a
		// normal soft-nav. The user gets a fresh /runs.
	}
	let linkedWorkout = $state<PlanWorkout | null>(null);
	/// Selected segment from the map. Set when the user clicks a point
	/// on the trace; cleared by tapping the overlay's close button or
	/// re-clicking the same area is reset by the next selection. Drives
	/// the floating "Segment details" card overlaying the map.
	let selectedSegment = $state<SelectedSegment | null>(null);
	let editing = $state(false);
	let editTitle = $state('');
	let editNotes = $state('');
	// DNF flag, mirrored from metadata.is_dnf into the edit form. Setting
	// it excludes the run from personal-records scoring server-side
	// (migration 20260530000001) — a DNF ultra must not promote as a PR
	// just because its truncated distance fits a shorter bracket.
	let editIsDnf = $state(false);
	let showDeleteConfirm = $state(false);
	let showShareConfirm = $state(false);
	let shareConfirmIntersectsZone = $state(false);
	let shareConfirmHasZones = $state(false);
	let bodyWeightKg = $state<number | null>(null);
	// HR-zone fallback inputs, read from the universal settings bag on
	// mount. Used only when explicit `hr_zones` is unset (Older #8).
	let maxHrBpm = $state<number | null>(null);
	let viewerAgeYears = $state<number | null>(null);
	// Persona-hunt Round 3 finding Woman #5. Read from
	// user_profiles.gender (same column the segments leaderboards
	// + training-pace calibration use). Null when unset → calorie
	// estimate uses the unmodified male-derived curve. ADR §77.
	let viewerGender = $state<CalorieGender>(null);
	/// Map-matched track + status from run_matched_tracks. Populated on
	/// mount in parallel with the main run fetch. Failure here is L4
	/// (auxiliary) per docs/architecture/conventions.md § Layered resilience — the
	/// raw track keeps rendering so the page always works.
	let matchInfo = $state<RunMatchInfo | null>(null);
	/// Latched while a re-match RPC is in flight so the button can't
	/// fire twice. Decoupled from `matchInfo.status === 'pending'`
	/// because the worker may bounce the row to 'pending' even before
	/// our RPC returns — the busy flag tracks our intent, the status
	/// pill tracks the row.
	let rematchBusy = $state(false);
	/// Auto-link candidates surfaced when run.route_id is null and
	/// the track overlaps a saved route. Picks the single best
	/// candidate (lowest combined start+end offset + plausible
	/// length match); if no candidate clears the bar this stays
	/// null and no UI renders.
	let suggestedRoute = $state<RouteMatchCandidate | null>(null);

	onMount(async () => {
		// Wait for the auth store to hydrate AND the user profile to
		// load before fetching. fetchRunById reads `auth.user?.id` and
		// returns null if it's null. There's a window where
		// auth.loading has flipped false (session check done) but
		// `user` is still null (fetchUser is in flight) — gating only
		// on auth.loading misses it.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		run = await fetchRunById(pageData.id);
		loading = false;
		// Best-effort matched-track fetch in the background. The map
		// will swap to the matched line once it lands; until then it
		// shows the raw track.
		fetchRunMatchedTrack(pageData.id)
			.then((info) => { matchInfo = info; })
			.catch((e) => { console.warn('matched-track fetch failed', e); });
		// Background route-suggestion. Only kicks in for runs that
		// aren't already linked to a route AND have a usable track —
		// silent on empty / failure paths.
		if (run && !run.route_id && run.track && run.track.length >= 2) {
			void suggestRoute(run.track, run.distance_m);
		}
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
				const { loadSettings, effective } = await import('$lib/settings/settings');
				const settings = await loadSettings(uid);
				const zones = effective<Record<string, number>>(settings, 'hr_zones');
				if (zones) {
					const z1 = zones.z1, z2 = zones.z2, z3 = zones.z3, z4 = zones.z4, z5 = zones.z5;
					if ([z1, z2, z3, z4, z5].every((z) => typeof z === 'number' && z > 0)) {
						zoneCutoffs = [z1, z2, z3, z4, z5];
					}
				}
				// Fallback inputs for when `hr_zones` is unset: an explicit
				// max-HR override, then age (Tanaka 208 − 0.7×age) derived
				// from the universal `date_of_birth` pref. Older #8 —
				// otherwise everyone defaulted to a 190-bpm ceiling.
				const mhr = effective<number>(settings, 'max_hr_bpm');
				if (typeof mhr === 'number' && mhr > 0) maxHrBpm = mhr;
				const dob = effective<string>(settings, 'date_of_birth');
				if (typeof dob === 'string') {
					const born = new Date(dob);
					if (!Number.isNaN(born.getTime())) {
						const now = new Date();
						let age = now.getFullYear() - born.getFullYear();
						const m = now.getMonth() - born.getMonth();
						if (m < 0 || (m === 0 && now.getDate() < born.getDate())) age--;
						if (age >= 0 && age < 120) viewerAgeYears = age;
					}
				}
				const bw = effective<number>(settings, 'body_weight_kg');
				if (typeof bw === 'number' && bw > 0) bodyWeightKg = bw;
			}
			// Read viewer gender for the calorie cross-formula
			// calibration (persona-hunt Round 3 finding Woman #5).
			// Same column the training-pace calibration reads — see
			// PlanEditor.svelte. L4 best-effort: if the row read fails
			// the estimate just falls back to the unmodified curve.
			try {
				// Self-read via get_my_profile(): `gender` is deny-by-default
				// for direct authenticated SELECTs (column lockdown,
				// 20260707_001). uid is the viewer's own id here.
				const { data: prof } = await supabase.rpc('get_my_profile');
				const g = (prof as { gender?: string | null } | null)?.gender;
				if (g === 'male' || g === 'female' || g === 'nonbinary') {
					viewerGender = g;
				}
			} catch (_) {
				/* L4 — fall back to null */
			}
		} catch (_) {
			/* noop */
		}
	});

	/// Decide whether any of the spatial candidates is a close-enough
	/// match to surface as a one-click suggestion. Two thresholds:
	/// combined endpoint offset under 2× the RPC tolerance (so start
	/// + end are both close to the route's start + end) AND distance
	/// within 20% of the track length (otherwise we're a sub-section
	/// or a superset, not the same route). Conservative on purpose
	/// — false positives would teach the runner to ignore the prompt.
	async function suggestRoute(
		track: { lat: number; lng: number }[],
		runDistanceM: number,
	) {
		try {
			const candidates = await fetchRoutesIntersectingTrack(track, 100, 5);
			if (candidates.length === 0) return;
			const best = candidates[0];
			const lengthRatio =
				Math.abs(best.distanceM - runDistanceM) / Math.max(runDistanceM, 1);
			if (best.startOffsetM + best.endOffsetM < 200 && lengthRatio < 0.2) {
				suggestedRoute = best;
			}
		} catch (e) {
			console.warn('suggestRoute failed', e);
		}
	}

	async function acceptSuggestedRoute() {
		const candidate = suggestedRoute;
		if (!run || !candidate) return;
		try {
			await linkRunToRoute(run.id, candidate.id);
			run = { ...run, route_id: candidate.id };
			suggestedRoute = null;
			showToast(m('runDetail.linkedToRoute', { name: candidate.name }), 'success');
		} catch (e) {
			console.error(e);
			showToast(m('runDetail.linkRouteFailed'), 'error');
		}
	}

	let runTitle = $derived((run?.metadata as Record<string, unknown> | null)?.title as string ?? '');
	let runNotes = $derived((run?.metadata as Record<string, unknown> | null)?.notes as string ?? '');
	let isDnf = $derived((run?.metadata as Record<string, unknown> | null)?.['is_dnf'] === true);
	/// Estimated calories — routes through the shared pure helper
	/// `apps/web/src/lib/runs/calories.ts` (mirrored byte-for-byte in
	/// the Dart twin) so the formula stays in lockstep across the
	/// web run-detail + mobile run-detail surfaces. The helper
	/// applies the cross-formula female calibration when the
	/// viewer's `user_profiles.gender` is `female` (see
	/// `docs/architecture/decisions.md § 77`). Pre-fix this page hardcoded
	/// `weight × distance` and ignored gender entirely — every
	/// female runner was over-estimated by ~5%.
	let runActivityType = $derived(
		((run?.metadata as Record<string, unknown> | null)?.activity_type as string) ??
			'run',
	);
	/// Garmin discipline (FIT sub_sport) — the trail/track/treadmill/road
	/// distinction the coarse activity_type throws away. Shown as a header
	/// chip so a trail run reads as trail, not generic "Run" (round-5 F1).
	let subSport = $derived(
		((run?.metadata as Record<string, unknown> | null)?.sub_sport as string | null) ?? null,
	);
	let disciplineLabel = $derived(
		subSport ? subSport.charAt(0).toUpperCase() + subSport.slice(1) : null,
	);
	/// Garmin Running Dynamics off the imported session (round-5 F2).
	let runningDynamics = $derived(
		((run?.metadata as Record<string, unknown> | null)?.running_dynamics as {
			vertical_oscillation_mm?: number;
			gct_ms?: number;
			stride_length_m?: number;
			power_w?: number;
		} | null) ?? null,
	);
	let hasRunningDynamics = $derived(
		runningDynamics != null &&
			(runningDynamics.vertical_oscillation_mm != null ||
				runningDynamics.gct_ms != null ||
				runningDynamics.stride_length_m != null ||
				runningDynamics.power_w != null),
	);
	let estimatedCalories = $derived(
		run
			? estimateRunCalories({
					distanceM: run.distance_m,
					weightKg: bodyWeightKg,
					activityKcalPerKgPerKm: ACTIVITY_KCAL_PER_KG_PER_KM[runActivityType],
					gender: viewerGender,
			  })
			: 0,
	);
	let calorieLabel = $derived(
		bodyWeightKg ? m('runDetail.caloriesLabel') : m('runDetail.caloriesEstLabel'),
	);

	/// Structured-workout review. The recorder writes three keys on
	/// `runs.metadata` after a planned workout: `plan_workout_id`,
	/// `workout_step_results` (per-step planned-vs-actual), and
	/// `workout_adherence`. See docs/backend/metadata.md for the full shape.
	interface WorkoutStepResult {
		step_index: number;
		kind: string;
		rep_index?: number;
		rep_total?: number;
		target_distance_m: number;
		actual_distance_m: number;
		// Present only on duration-based steps (workout execution v2).
		// When set + positive, the table renders time on the plan +
		// actual columns instead of km.
		target_duration_s?: number;
		target_pace_sec_per_km: number;
		actual_pace_sec_per_km: number | null;
		duration_s: number;
		status: 'completed' | 'skipped';
	}

	function isDurationStep(s: WorkoutStepResult): boolean {
		return typeof s.target_duration_s === 'number' && s.target_duration_s > 0;
	}

	function formatStepDuration(seconds: number): string {
		if (seconds >= 60) {
			const m = Math.floor(seconds / 60);
			const r = seconds % 60;
			return r === 0 ? `${m}m` : `${m}m ${r}s`;
		}
		return `${seconds}s`;
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
				return m('runDetail.stepWarmup');
			case 'cooldown':
				return m('runDetail.stepCooldown');
			case 'steady':
				return m('runDetail.stepSteady');
			case 'rep':
				return s.rep_index && s.rep_total
					? m('runDetail.stepRepNumbered', { index: s.rep_index, total: s.rep_total })
					: m('runDetail.stepRep');
			case 'recovery':
				return s.rep_index && s.rep_total
					? m('runDetail.stepRecoveryNumbered', { index: s.rep_index, total: s.rep_total - 1 })
					: m('runDetail.stepRecovery');
			default:
				return s.kind;
		}
	}


	function paceDeltaLabel(s: WorkoutStepResult): string {
		if (s.actual_pace_sec_per_km == null) return '—';
		const d = s.actual_pace_sec_per_km - s.target_pace_sec_per_km;
		if (Math.abs(d) < 1) return m('runDetail.onPace');
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
		editIsDnf = isDnf;
		editing = true;
	}

	async function saveEdit() {
		if (!run) return;
		try {
			// title/notes go through updateRunMetadata's normalised patch.
			// is_dnf isn't one of its keys (the normaliser only knows
			// title + notes), so when it changed apply the same
			// read-merge-write here in a single round-trip: build the
			// title/notes patch with the shared helper, then add or drop
			// is_dnf on top. Setting it true excludes the run from
			// personal-records scoring; the PR trigger drops it on the next
			// refresh. Un-toggling deletes the key rather than writing
			// `false`, matching the metadata-bag convention.
			if (editIsDnf !== isDnf) {
				const nextMeta = applyRunMetadataPatch(
					run.metadata as Record<string, unknown> | null | undefined,
					{ title: editTitle, notes: editNotes },
					new Date().toISOString(),
				);
				if (editIsDnf) nextMeta['is_dnf'] = true;
				else delete nextMeta['is_dnf'];
				const { error } = await supabase
					.from('runs')
					.update({ metadata: nextMeta })
					.eq('id', run.id);
				if (error) throw error;
				run = { ...run, metadata: nextMeta } as Run;
			} else {
				await updateRunMetadata(run.id, { title: editTitle, notes: editNotes });
				const metadata = { ...(run.metadata as Record<string, unknown> ?? {}), title: editTitle, notes: editNotes };
				run = { ...run, metadata } as Run;
			}
			editing = false;
		} catch (e) {
			showToast(m('runDetail.saveFailed', { error: String(e) }), 'error');
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
			showToast(m('runDetail.deleteFailed', { error: String(e) }), 'error');
		}
	}

	async function handleShare() {
		if (!run || !auth.user) return;
		// Skip the prompt when the run is already public — Share becomes
		// a re-copy-link in that case.
		if (run.is_public) {
			await proceedShare();
			return;
		}
		// Visibility-change consent: making a previously-private run
		// public is a non-trivial state change. A first-time / casual
		// user has typically never set up a privacy zone, so without
		// this dialog the share-icon tap silently exposes their full
		// track (incl. home / work coords). The dialog body specialises
		// on the user's actual situation: privacy-zone clip warning if
		// the track intersects a zone, otherwise a no-zones notice with
		// a link to set one up before sharing.
		let intersectsZone = false;
		let hasZones = false;
		try {
			const { loadSettings, effective } = await import('$lib/settings/settings');
			const settings = await loadSettings(auth.user.id);
			const zones =
				effective<PrivacyZone[]>(settings, PRIVACY_ZONES_KEY) ?? [];
			hasZones = zones.length > 0;
			if (run.track && run.track.length > 0 && hasZones) {
				intersectsZone = run.track.some((p) => isInAnyZone(p, zones));
			}
		} catch (_) {
			// Settings load failure shouldn't block sharing — fall
			// through to the no-zones branch.
		}
		shareConfirmIntersectsZone = intersectsZone;
		shareConfirmHasZones = hasZones;
		showShareConfirm = true;
	}

	async function proceedShare() {
		if (!run) return;
		showShareConfirm = false;
		try {
			await makeRunPublic(run.id);
			const url = `${window.location.origin}/share/run/${run.id}`;
			await navigator.clipboard.writeText(url);
			showToast(m('runDetail.shareLinkCopied'), 'success');
		} catch (e) {
			showToast(m('runDetail.shareFailed', { error: String(e) }), 'error');
		}
	}

	async function handleSaveAsRoute() {
		if (!run?.track || run.track.length < 2) return;
		// The chosen name is persisted to the DB (routes.name), so the
		// fallback is the run's ISO date rather than an English-prefixed,
		// locale-formatted string — a non-English user shouldn't end up
		// with an English route name baked into their data. They can still
		// rename it in the prompt below.
		const defaultName =
			((run.metadata as Record<string, unknown> | null)?.title as string) ||
			new Date(run.started_at).toISOString().slice(0, 10);
		const name = window.prompt(m('runDetail.nameThisRoute'), defaultName);
		if (!name || !name.trim()) return;
		try {
			const { id } = await saveRunAsRoute(
				run.id,
				name.trim(),
				run.track.map((p) => ({ lat: p.lat, lng: p.lng, ele: p.ele ?? null })),
			);
			showToast(m('runDetail.savedAsRoute'), 'success');
			goto(`/routes/${id}`);
		} catch (e) {
			showToast(m('runDetail.saveFailed', { error: String(e) }), 'error');
		}
	}

	let generatingImage = $state(false);
	let shareCardEl: HTMLElement | undefined = $state();

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
				showToast(m('runDetail.imageSaved'), 'success');
			}
		} catch (e) {
			const msg = (e as Error).message;
			// User cancelling a Web Share sheet raises; that's fine.
			if (!msg.includes('abort') && !msg.includes('cancel')) {
				showToast(m('runDetail.imageGenerateFailed', { error: msg }), 'error');
			}
		} finally {
			generatingImage = false;
		}
	}

	/// Owner-only: force a fresh map-match against the current track.
	/// Resets run_matched_tracks to pending and queues a `map_match`
	/// job (server-side RPC enqueue_run_rematch). The match-pill flips
	/// to 'pending' on the next mount; we also re-fetch immediately so
	/// the user sees feedback without a manual reload. Idempotent
	/// against already-queued jobs.
	async function handleRematch() {
		if (!run || rematchBusy) return;
		rematchBusy = true;
		try {
			await enqueueRunRematch(run.id);
			matchInfo = await fetchRunMatchedTrack(run.id);
			showToast(m('runDetail.reSnapping'), 'success');
		} catch (e) {
			const msg = (e as Error).message ?? String(e);
			showToast(m('runDetail.rematchFailed', { error: msg }), 'error');
		} finally {
			rematchBusy = false;
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
	// $derived so the m() labels track locale changes (a plain const captures
	// the locale once at init and never updates).
	const activityMeta = $derived<Record<string, { label: string; icon: string }>>({
		run: { label: m('runDetail.activityRun'), icon: 'directions_run' },
		walk: { label: m('runDetail.activityWalk'), icon: 'directions_walk' },
		cycle: { label: m('runDetail.activityCycle'), icon: 'directions_bike' },
		hike: { label: m('runDetail.activityHike'), icon: 'terrain' },
	});

	let activity = $derived.by(() => {
		const key = run?.metadata?.['activity_type'];
		if (typeof key !== 'string') return null;
		return activityMeta[key] ?? { label: key, icon: 'directions_run' };
	});

	/// Activity tag the map uses to scale its pace-heatmap breakpoints.
	/// Only the four kinds the heatmap knows about are passed through;
	/// anything else (or a missing tag) falls back to the legacy
	/// single-line render via `undefined`.
	let paceHeatmapActivity = $derived.by<'run' | 'walk' | 'cycle' | 'hike' | undefined>(() => {
		const key = run?.metadata?.['activity_type'];
		if (key === 'run' || key === 'walk' || key === 'cycle' || key === 'hike') return key;
		return undefined;
	});

	/** Derived from the GPS track rather than stored, matching mobile. */
	let movingSeconds = $derived(run?.track ? movingTimeSeconds(run.track) : 0);

	/** Prefer a real track-based elevation gain over the randomly-generated
	 *  mock value. Falls back to 0 for runs without elevation data. */
	let realElevationGain = $derived(run?.track ? elevationGainMetres(run.track) : 0);

	/** Grade-adjusted pace (sec/km) — effort-equivalent flat pace over hilly
	 *  terrain (Minetti 2002). Null on flat runs / tracks without elevation. */
	let gradeAdjustedPace = $derived(run?.track ? gradeAdjustedPaceSecPerKm(run.track) : null);

	/** Only surface GAP when it differs from raw average pace by a margin
	 *  worth showing — a near-flat run's GAP is the raw pace and the extra
	 *  cell is just noise. 2 s/km threshold. */
	let showGradeAdjustedPace = $derived.by(() => {
		if (gradeAdjustedPace == null || !run || run.distance_m <= 0) return false;
		const secs = movingSeconds > 0 ? movingSeconds : run.duration_s;
		const rawPaceSecPerKm = secs / (run.distance_m / 1000);
		return Math.abs(gradeAdjustedPace - rawPaceSecPerKm) >= 2;
	});

	/** Total steps are stored on mobile save in `metadata.steps`. */
	let totalSteps = $derived.by(() => {
		const v = run?.metadata?.['steps'];
		return typeof v === 'number' ? v : null;
	});

	/** Average cadence in steps-per-minute. Prefers a directly-reported
	 *  value (`metadata.cadence_spm`, written by the Garmin FIT importer
	 *  which has no pedometer step count — persona #17), then falls back
	 *  to steps / moving_time_minutes for pedometer-recorded runs. */
	let avgCadence = $derived.by(() => {
		const stored = run?.metadata?.['cadence_spm'];
		if (typeof stored === 'number' && stored > 0) return Math.round(stored);
		if (totalSteps == null || movingSeconds < 30) return null;
		return Math.round((totalSteps / (movingSeconds / 60)) || 0);
	});

	/** Average heart rate. Watch apps (watch_ios, watch_wear) record this
	 *  into `metadata.avg_bpm` during a run. See `docs/backend/metadata.md`. */
	let avgBpm = $derived.by(() => {
		const v = run?.metadata?.['avg_bpm'];
		return typeof v === 'number' && v > 0 ? Math.round(v) : null;
	});

	/** parkrun age-graded percentage (e.g. "54.23%"), set by the
	 *  parkrun importer into metadata.age_grade. See docs/backend/metadata.md. */
	let ageGrade = $derived.by(() => {
		const v = run?.metadata?.['age_grade'];
		return typeof v === 'string' && v.trim() ? v.trim() : null;
	});

	/// Visible key-stats count + parity. The grid's `auto-fit` columns
	/// look broken when the cell count is odd (one empty trailing slot
	/// at 2-col layouts is the most common shape). Counts the
	/// conditionals below + flips a flag the template uses to render
	/// an Activity-type filler when the total would otherwise be odd.
	///
	/// Always-rendered stats: Distance, Time, Pace, Speed, Elevation,
	/// Calories (Calories uses the body-weight fallback so it never
	/// hides) = 6.
	/// Conditional: Moving, Grade-adjusted pace, Steps, Cadence, AvgBpm,
	/// AgeGrade.
	let keyStatsCount = $derived(
		6 +
			(run && movingSeconds > 0 && movingSeconds !== run.duration_s ? 1 : 0) +
			(showGradeAdjustedPace ? 1 : 0) +
			(totalSteps != null ? 1 : 0) +
			(avgCadence != null ? 1 : 0) +
			(avgBpm != null ? 1 : 0) +
			(ageGrade != null ? 1 : 0),
	);
	let showActivityFiller = $derived(keyStatsCount % 2 === 1 && activity !== null);

	/// Real HR zone breakdown. Requires per-point `bpm` on the track —
	/// which watch and phone recorders will start writing alongside GPS
	/// over the course of the next few recording passes. When the
	/// track carries BPM samples, we compute a %-of-time-in-zone
	/// distribution from the user's own zone thresholds (settings bag
	/// `hr_zones`, falling back to sensible defaults keyed off max
	/// HR). When it doesn't, the panel reports "No HR samples on this
	/// run" instead of rendering fake percentages.
	const zoneDefs = $derived([
		{ zone: m('runDetail.zone1'), label: m('runDetail.zoneRecovery'), color: '#90CAF9' },
		{ zone: m('runDetail.zone2'), label: m('runDetail.zoneEasy'), color: '#4CAF50' },
		{ zone: m('runDetail.zone3'), label: m('runDetail.zoneAerobic'), color: '#FFC107' },
		{ zone: m('runDetail.zone4'), label: m('runDetail.zoneThreshold'), color: '#FF9800' },
		{ zone: m('runDetail.zone5'), label: m('runDetail.zoneMax'), color: '#F44336' },
	]);

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
	/// defaults keyed off their max HR (an explicit override, then
	/// Tanaka from age, then a 190-bpm fallback — see hr_zones.ts).
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
		// The default max HR comes from an explicit override, then the
		// runner's age (Tanaka), then 190 — see defaultZoneCutoffs.
		const cutoffs =
			zoneCutoffs ?? defaultZoneCutoffs({ maxHrBpm, ageYears: viewerAgeYears });

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

	/// Map track. Prefer the matched line when the worker has produced
	/// one (status='matched' AND non-empty payload); fall back to the
	/// raw recorded track. If neither exists (Strava sync without GPS,
	/// manual parkrun entry, HealthKit summary without polyline), the
	/// map panel renders an empty state — we deliberately do NOT
	/// synthesise a placeholder track. Stats below the map continue to
	/// derive from `run.track` directly so distance / splits / pace
	/// zones reflect what the runner actually did.
	let baseTrack = $derived(
		matchInfo?.track && matchInfo.track.length >= 2
			? matchInfo.track
			: run?.track ?? [],
	);
	let hasMapTrack = $derived(baseTrack.length >= 2);
	let elevations = $derived(baseTrack.map((p) => p.ele ?? 0));

	/// Linked-cursor index — fed by ElevationProfile's onhover, consumed
	/// by RunMap's hoverIdx. Null when the pointer is off the chart.
	/// The chart's idx-space is the elevations array's index space,
	/// which is identical to baseTrack's because elevations is derived
	/// 1:1 from baseTrack above.
	let chartHoverIdx = $state<number | null>(null);

	/// Route-direction scrubber state — mirrors the route-detail
	/// surface (and the mobile twin's `_RoutePreviewScrubber`). The
	/// user drags a 0..1 fraction across the run's polyline; while
	/// `scrubbing` is true, the map mounts a pulsing preview marker
	/// at the interpolated position so the runner can replay where
	/// they were along the track. May 2026 parity pass — mobile
	/// route-detail already had it; web's run-detail was missing.
	let scrubFraction = $state(0);
	let scrubbing = $state(false);
	let scrubPreviewLngLat = $derived.by<[number, number] | null>(() => {
		if (!scrubbing || !hasMapTrack) return null;
		const pt = interpolateAlongRoute(
			baseTrack.map((p) => ({ lat: p.lat, lng: p.lng })),
			scrubFraction,
		);
		return pt ? [pt.lng, pt.lat] : null;
	});

	let splits = $derived(run?.track ? computeRealSplits(run.track) : []);

	/// Manually-marked laps. The recorder writes `metadata.laps` as an
	/// array of `{ index, start_offset_s, distance_m, duration_s }` where
	/// `distance_m` / `duration_s` are the *per-lap* deltas, not cumulative
	/// (docs/backend/metadata.md § laps). `metadata` is null entirely when
	/// there were no laps, so guard on both the bag and the key.
	interface Lap {
		index: number;
		distance_m: number;
		duration_s: number;
	}
	let laps = $derived.by<Lap[]>(() => {
		const v = (run?.metadata as Record<string, unknown> | null)?.['laps'];
		if (!Array.isArray(v)) return [];
		return v
			.filter(
				(l): l is Lap =>
					l != null &&
					typeof (l as Lap).index === 'number' &&
					typeof (l as Lap).distance_m === 'number' &&
					typeof (l as Lap).duration_s === 'number',
			)
			.map((l) => ({
				index: l.index,
				distance_m: l.distance_m,
				duration_s: l.duration_s,
			}));
	});

	/// Static-map URL for the share card. Same pipeline as the
	/// runs/routes list thumbnails — `buildLocalStaticMapUrl` for
	/// the local Protomaps dev stack, `buildStaticMapUrl` for
	/// production MapTiler. 1080×600 to fit the share card cleanly
	/// at 1080-square; null when there's no track to render (the
	/// card falls back to the stats-only layout).
	let shareMapUrl = $derived.by(() => {
		if (!hasMapTrack || baseTrack.length < 2) return null;
		const pts = baseTrack.map((p) => ({ lat: p.lat, lng: p.lng }));
		return (
			buildLocalStaticMapUrl(pts, {
				w: 1080,
				h: 600,
				styleUrl: PUBLIC_TILE_STYLE_URL,
			}) ??
			buildStaticMapUrl(pts, {
				w: 1080,
				h: 600,
				style: 'streets-v2',
				key: PUBLIC_MAPTILER_KEY,
			})
		);
	});
</script>

{#if loading}
	<div class="run-detail">
		<div class="loading-grid" aria-busy="true" aria-label={m('runDetail.loadingRun')}>
			<div class="loading-map skeleton-shimmer"></div>
			<div class="loading-stats">
				<div class="skeleton-shimmer skeleton-title"></div>
				<div class="skeleton-shimmer skeleton-line"></div>
				<div class="loading-key-stats">
					<div class="skeleton-shimmer skeleton-stat"></div>
					<div class="skeleton-shimmer skeleton-stat"></div>
					<div class="skeleton-shimmer skeleton-stat"></div>
					<div class="skeleton-shimmer skeleton-stat"></div>
				</div>
				<div class="skeleton-shimmer skeleton-block"></div>
				<div class="skeleton-shimmer skeleton-block"></div>
			</div>
		</div>
	</div>
{:else if !run}
	<div class="run-detail">
		<a href="/runs" class="back-link page-back">
			<span class="material-symbols">arrow_back</span> {m('runDetail.allRuns')}
		</a>
		<div class="not-found">
			<h1>{m('runDetail.notFoundTitle')}</h1>
			<p>{m('runDetail.notFoundBody')}</p>
			<a href="/runs" class="btn btn-primary">{m('runDetail.backToRuns')}</a>
		</div>
	</div>
{:else}
<div class="run-detail">
	<div class="run-detail-body">
	<!-- Panels-on-left convention (May 2026 UX pass): info pane on the
		 left, map dominant on the right. The fraction is the LEFT
		 pane width, so 0.35 is "info ≈ 35% of viewport, map ≈ 65%". -->
	<SplitPane storageKey="run-detail-split" min={300} initialFraction={0.35}>
		{#snippet right()}
		{#if run}
	<main class="map-panel">
		{#if hasMapTrack}
			<RunMap
				track={baseTrack}
				animatable
				activity={paceHeatmapActivity}
				onSegmentSelect={(seg) => (selectedSegment = seg)}
				hoverIdx={chartHoverIdx}
				previewLngLat={scrubPreviewLngLat}
			/>
		{:else}
			<div class="map-empty">
				<span class="material-symbols">map</span>
				<p class="map-empty-title">{m('runDetail.noGpsTrack')}</p>
				<p class="map-empty-sub">
					{m('runDetail.noGpsTrackSub')}
				</p>
			</div>
		{/if}
		<!-- Map-match status pill. Only renders when we have a status
		     to communicate — pending / failed / skipped are the
		     informational cases ("the worker hasn't produced a
		     matched line yet" / "the engine couldn't"). The matched
		     case is silent because the cleaner display speaks for
		     itself. -->
		{#if matchInfo && matchInfo.status !== 'matched'}
			<aside class="match-pill match-pill-{matchInfo.status}" title={m('runDetail.mapMatching')}>
				{#if matchInfo.status === 'pending'}
					<span class="material-symbols">hourglass_top</span>
					{m('runDetail.snappingToRoads')}
				{:else if matchInfo.status === 'skipped'}
					<span class="material-symbols">block</span>
					{m('runDetail.notSnapped')}
				{:else if matchInfo.status === 'failed'}
					<span class="material-symbols">error</span>
					{m('runDetail.snapFailed')}
				{/if}
				{#if run && auth.user?.id === run.user_id && matchInfo.status !== 'pending'}
					<button
						type="button"
						class="match-pill-action"
						onclick={handleRematch}
						disabled={rematchBusy}
						title={m('runDetail.rematchTitle')}
					>
						<span class="material-symbols">refresh</span>
						{rematchBusy ? m('runDetail.queueing') : m('runDetail.rematch')}
					</button>
				{/if}
			</aside>
		{/if}
		<!-- Nike-style segment-detail card. Click any point on the trace
		     to drop a pin and see ±150 m of stats around that location:
		     distance covered, elapsed time (when the track has per-point
		     timestamps), avg pace, avg HR, elevation gain / loss. -->
		{#if selectedSegment}
			<aside class="segment-card">
				<header class="segment-card-head">
					<span class="segment-eyebrow">{m('runDetail.segmentEyebrow')}</span>
					<button
						class="segment-close"
						aria-label={m('runDetail.closeSegmentDetails')}
						onclick={() => (selectedSegment = null)}
					>
						<span class="material-symbols">close</span>
					</button>
				</header>
				<div class="segment-grid">
					<div class="segment-stat">
						<span class="segment-stat-label">{m('runDetail.distance')}</span>
						<span class="segment-stat-value">{formatDistance(selectedSegment.distance_m)}</span>
					</div>
					{#if selectedSegment.duration_s != null}
						<div class="segment-stat">
							<span class="segment-stat-label">{m('runDetail.time')}</span>
							<span class="segment-stat-value">{formatDuration(selectedSegment.duration_s)}</span>
						</div>
					{/if}
					{#if selectedSegment.avg_pace_sec_per_km != null}
						<div class="segment-stat">
							<span class="segment-stat-label">{m('runDetail.pace')}</span>
							<span class="segment-stat-value">
								{formatPace(selectedSegment.avg_pace_sec_per_km, 1000)}
							</span>
						</div>
					{/if}
					{#if selectedSegment.avg_bpm != null}
						<div class="segment-stat">
							<span class="segment-stat-label">{m('runDetail.avgHr')}</span>
							<span class="segment-stat-value">{selectedSegment.avg_bpm} bpm</span>
						</div>
					{/if}
					{#if selectedSegment.ele_gain_m > 0 || selectedSegment.ele_loss_m > 0}
						<div class="segment-stat">
							<span class="segment-stat-label">{m('runDetail.elev')}</span>
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
		{/if}
		{/snippet}

		{#snippet left()}
		{#if run}
	<aside class="stats-panel">
		<a href="/runs" class="back-link panel-back" onclick={handleBack}>
			<span class="material-symbols">arrow_back</span>
			{m('runDetail.allRuns')}
		</a>
		<header class="detail-header">
			<div class="detail-header-top">
				<div class="detail-title-block">
					<h1>{runTitle || formatDate(run.started_at)}</h1>
					<div class="detail-meta">
						{#if runTitle}
							<span class="meta-item">
								<span class="material-symbols">event</span>
								{formatDate(run.started_at)}
							</span>
						{/if}
						{#if activity}
							<span class="meta-item">
								<span class="material-symbols">{activity.icon}</span>
								{activity.label}
							</span>
						{/if}
						{#if disciplineLabel}
							<span class="meta-item discipline-chip" data-testid="discipline-chip">
								<span class="material-symbols">terrain</span>
								{disciplineLabel}
							</span>
						{/if}
						<span class="meta-item meta-source" style:--source-color={sourceColor(run.source)}>
							<span class="meta-source-dot"></span>
							{sourceLabel(run.source)}
						</span>
						<span class="meta-item visibility-chip" class:is-public={run.is_public}>
							<span class="material-symbols">{run.is_public ? 'public' : 'lock'}</span>
							{run.is_public ? m('runDetail.public') : m('runDetail.private')}
						</span>
						{#if isDnf}
							<span class="meta-item dnf-chip" data-testid="dnf-chip">
								<span class="material-symbols">flag</span>
								{m('runDetail.dnf')}
							</span>
						{/if}
					</div>
				</div>
				{#if auth.loggedIn}
					<div class="action-btns" role="toolbar" aria-label={m('runDetail.runActions')}>
						<button
							class="icon-btn"
							aria-label={m('runDetail.editAria')}
							title={m('runDetail.edit')}
							onclick={startEdit}
						>
							<span class="material-symbols">edit</span>
						</button>
						<button
							class="icon-btn"
							aria-label={run.is_public ? m('runDetail.copyShareLink') : m('runDetail.makePublicCopyLink')}
							title={run.is_public ? m('runDetail.copyShareLink') : m('runDetail.shareLink')}
							onclick={handleShare}
						>
							<span class="material-symbols">share</span>
						</button>
						<button
							class="icon-btn"
							aria-label={m('runDetail.downloadGpxAria')}
							title={m('runDetail.downloadGpx')}
							onclick={handleDownloadGpx}
							disabled={!run?.track || run.track.length < 2}
						>
							<span class="material-symbols">download</span>
						</button>
						<button
							class="icon-btn"
							aria-label={m('runDetail.saveAsRouteAria')}
							title={m('runDetail.saveAsRoute')}
							onclick={handleSaveAsRoute}
							disabled={!run?.track || run.track.length < 2}
						>
							<span class="material-symbols">bookmark_add</span>
						</button>
						<button
							class="icon-btn"
							aria-label={m('runDetail.shareAsImage')}
							title={m('runDetail.shareAsImage')}
							onclick={handleShareImage}
							disabled={generatingImage}
						>
							<span class="material-symbols">image</span>
						</button>
						<span class="action-divider" aria-hidden="true"></span>
						<button
							class="icon-btn danger"
							aria-label={m('runDetail.deleteRunAria')}
							title={m('runDetail.delete')}
							onclick={handleDelete}
						>
							<span class="material-symbols">delete</span>
						</button>
					</div>
				{/if}
			</div>
			{#if runNotes}
				<p class="run-notes">{runNotes}</p>
			{/if}
		</header>

		<!-- Auto-link suggestion: when the run isn't linked to a route
		     but its track overlaps one of the runner's saved routes,
		     surface a one-tap link prompt. The suggestion is computed
		     in the background after mount; renders nothing until a
		     confident match lands. -->
		{#if suggestedRoute && !run.route_id}
			<div class="route-suggest-banner">
				<span class="material-symbols">link</span>
				<div class="route-suggest-body">
					<div class="route-suggest-text">{m('runDetail.looksLikeYouRan')} <strong>{suggestedRoute.name}</strong></div>
					<div class="route-suggest-sub">{m('runDetail.linkThisRunPrompt')}</div>
				</div>
				<div class="route-suggest-actions">
					<button class="btn-sm btn-outline-sm" onclick={() => (suggestedRoute = null)}>{m('runDetail.dismiss')}</button>
					<button class="btn-sm btn-primary-sm" onclick={acceptSuggestedRoute}>{m('runDetail.link')}</button>
				</div>
			</div>
		{/if}

		{#if editing}
			<div class="edit-form">
				<input type="text" bind:value={editTitle} placeholder={m('runDetail.runTitlePlaceholder')} class="edit-input" />
				<textarea bind:value={editNotes} placeholder={m('runDetail.notesPlaceholder')} class="edit-textarea" rows="2"></textarea>
				<label class="edit-dnf">
					<input type="checkbox" bind:checked={editIsDnf} data-testid="dnf-toggle" />
					<span>
						<strong>{m('runDetail.markAsDnf')}</strong>
						<span class="edit-dnf-hint">
							{m('runDetail.dnfHint')}
						</span>
					</span>
				</label>
				{#if run.is_public}
					<p class="edit-public-hint">
						{m('runDetail.editPublicHint')}
					</p>
				{:else}
					<p class="edit-public-hint edit-public-hint-muted">
						{m('runDetail.editPrivateHint')}
					</p>
				{/if}
				<div class="edit-actions">
					<button class="btn-sm btn-outline-sm" onclick={() => editing = false}>{m('runDetail.cancel')}</button>
					<button class="btn-sm btn-primary-sm" onclick={saveEdit}>{m('runDetail.save')}</button>
				</div>
			</div>
		{/if}

		<!-- Key stats -->
		<div class="key-stats">
			<div class="key-stat">
				<span class="key-stat-value">{formatDistance(run.distance_m)}</span>
				<span class="key-stat-label">{m('runDetail.distance')}</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{formatDuration(run.duration_s)}</span>
				<span class="key-stat-label">{m('runDetail.time')}</span>
			</div>
			{#if movingSeconds > 0 && movingSeconds !== run.duration_s}
				<div class="key-stat">
					<span class="key-stat-value">{formatDuration(movingSeconds)}</span>
					<span class="key-stat-label">{m('runDetail.moving')}</span>
				</div>
			{/if}
			<div class="key-stat">
				<span class="key-stat-value"
					>{formatPace(
						movingSeconds > 0 ? movingSeconds : run.duration_s,
						run.distance_m
					)}</span
				>
				<span class="key-stat-label">{m('runDetail.avgPace')}</span>
			</div>
			{#if showGradeAdjustedPace && gradeAdjustedPace != null}
				<div class="key-stat">
					<span class="key-stat-value">{formatPace(gradeAdjustedPace, 1000)}</span>
					<span class="key-stat-label">{m('runDetail.gradeAdjustedPace')}</span>
				</div>
			{/if}
			<div class="key-stat">
				<span class="key-stat-value">{formatSpeed(
					movingSeconds > 0 ? movingSeconds : run.duration_s,
					run.distance_m,
				)}</span>
				<span class="key-stat-label">{m('runDetail.avgSpeed')}</span>
			</div>
			<div class="key-stat">
				<span class="key-stat-value">{realElevationGain} m</span>
				<span class="key-stat-label">{m('runDetail.elevation')}</span>
			</div>
			{#if estimatedCalories > 0}
				<div class="key-stat">
					<span class="key-stat-value">{estimatedCalories}</span>
					<span class="key-stat-label">{calorieLabel}</span>
				</div>
			{/if}
			{#if totalSteps != null}
				<div class="key-stat">
					<span class="key-stat-value">{totalSteps.toLocaleString()}</span>
					<span class="key-stat-label">{m('runDetail.steps')}</span>
				</div>
			{/if}
			{#if avgCadence != null}
				<div class="key-stat">
					<span class="key-stat-value">{avgCadence}</span>
					<span class="key-stat-label">{m('runDetail.cadenceSpm')}</span>
				</div>
			{/if}
			{#if avgBpm != null}
				<div class="key-stat">
					<span class="key-stat-value">{avgBpm}</span>
					<span class="key-stat-label">{m('runDetail.avgHrBpm')}</span>
				</div>
			{/if}
			{#if ageGrade != null}
				<div class="key-stat">
					<span class="key-stat-value">{ageGrade}</span>
					<span class="key-stat-label">{m('runDetail.ageGrade')}</span>
				</div>
			{/if}
			<!-- Parity filler. The auto-fit key-stats grid looks broken
				 with an odd cell count (one empty slot trailing at the
				 most common 2-col layout). When the conditional stats
				 above leave us with an odd total, render the Activity
				 Type as the last cell — it's universally available
				 (every run carries metadata.activity_type) + adds
				 genuine info rather than visual padding. -->
			{#if showActivityFiller && activity}
				<div class="key-stat key-stat-activity">
					<span class="key-stat-value">
						<span class="material-symbols">{activity.icon}</span>
						{activity.label}
					</span>
					<span class="key-stat-label">{m('runDetail.activity')}</span>
				</div>
			{/if}
		</div>

		<!-- Scrubber section. Lives in the info panel (not below the
			 map) so it's always visible above the page fold + the
			 marker on the map is anchored to a control the user can
			 actually see. Drag the thumb 0..1 across the polyline;
			 a pulsing dot on the map fades in while `scrubbing` is
			 true (via the `previewLngLat` prop on RunMap above). -->
		{#if hasMapTrack}
			<section class="section preview-section">
				<h2>{m('runDetail.preview')}</h2>
				<RoutePreviewScrubber
					totalDistanceM={run.distance_m}
					fraction={scrubFraction}
					onchange={(f) => (scrubFraction = f)}
					onscrubbing={(active) => (scrubbing = active)}
				/>
			</section>
		{/if}

		<!-- Elevation Profile — only render when we have real elevation
		     samples. Without a track every point is 0 and the chart
		     reads as a deceptive flat line. -->
		{#if hasMapTrack}
			<section class="section">
				<h2>{m('runDetail.elevationProfile')}</h2>
				<ElevationProfile
				{elevations}
				totalDistance={run.distance_m}
				onhover={(idx) => (chartHoverIdx = idx)}
			/>
			</section>
		{/if}

		<section class="section">
			<RunGearChips runId={run.id} runOwnerId={run.user_id} />
		</section>

		<RunPhotos runId={run.id} runOwnerId={run.user_id} wrapperClass="section" />

		{#if run.route_id}
			<section class="section">
				<h2>{m('runDetail.segments')}</h2>
				<RunSegmentEfforts
					runId={run.id}
					runOwnerId={run.user_id}
					routeId={run.route_id}
					track={run.track ?? []}
				/>
			</section>
			<section class="section">
				<h2>{m('runDetail.routeHistory')}</h2>
				<RouteHistory
					currentRunId={run.id}
					routeId={run.route_id}
					distanceM={run.distance_m}
					durationS={run.duration_s}
					metadata={run.metadata as Record<string, unknown> | null}
				/>
			</section>
		{/if}

		<!-- Kudos + comments — visible whether the run is private or public,
		     but the runs RLS keeps engagement on private runs invisible to
		     anyone but the owner. -->
		<section class="section">
			<h2>{m('runDetail.activity')}</h2>
			<RunSocial runId={run.id} runOwnerId={run.user_id} />
		</section>

		<!-- Structured workout review — only shown when the recorder
		     linked this run to a planned `plan_workouts` row. Driven
		     entirely by `metadata.workout_step_results` so the table
		     stays in sync without a second query. -->
		{#if workoutStepResults.length > 0}
			<section class="section workout-review">
				<header class="workout-header">
					<h2>{m('runDetail.workout')}</h2>
					{#if workoutAdherence}
						<span class="workout-adherence workout-adherence-{workoutAdherence}">
							{workoutAdherence === 'completed'
								? m('runDetail.adherenceCompleted')
								: workoutAdherence === 'partial'
									? m('runDetail.adherencePartial')
									: m('runDetail.adherenceAbandoned')}
						</span>
					{/if}
				</header>
				{#if linkedWorkout}
					<p class="workout-name">
						{linkedWorkout.notes ?? linkedWorkout.kind}
						<span class="workout-target">
							· {m('runDetail.plannedDistance', { distance: formatDistance(linkedWorkout.target_distance_m ?? 0) })}
						</span>
					</p>
				{/if}
				<table class="workout-table">
					<thead>
						<tr>
							<th>{m('runDetail.colStep')}</th>
							<th class="num">{m('runDetail.colPlan')}</th>
							<th class="num">{m('runDetail.colActual')}</th>
							<th class="num">{m('runDetail.pace')}</th>
							<th class="num">Δ</th>
						</tr>
					</thead>
					<tbody>
						{#each workoutStepResults as s}
							<tr class:skipped={s.status === 'skipped'}>
								<td>{stepLabel(s)}</td>
								<td class="num">
									{#if isDurationStep(s)}
										{formatStepDuration(s.target_duration_s ?? 0)}
									{:else}
										{formatDistance(s.target_distance_m)}
									{/if}
								</td>
								<td class="num">
									{#if isDurationStep(s)}
										{formatStepDuration(s.duration_s)}
									{:else}
										{formatDistance(s.actual_distance_m)}
									{/if}
								</td>
								<td class="num">{fmtPace(s.actual_pace_sec_per_km)}</td>
								<td class="num pace-delta pace-delta-{paceDeltaClass(s)}">
									{s.status === 'skipped' ? m('runDetail.skip') : paceDeltaLabel(s)}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</section>
		{/if}

		<!-- Laps — manually marked mid-run on a recording client. Per-lap
		     distance / duration / derived pace. Renders only when the run
		     carries a non-empty `metadata.laps`; absent for runs with no
		     laps (mobile parity, decisions §24). -->
		{#if laps.length > 0}
			<section class="section laps">
				<h2>{m('runDetail.laps')}</h2>
				<table class="splits-table laps-table">
					<thead>
						<tr>
							<th>{m('runDetail.lap')}</th>
							<th>{m('runDetail.distance')}</th>
							<th>{m('runDetail.time')}</th>
							<th>{m('runDetail.pace')}</th>
						</tr>
					</thead>
					<tbody>
						{#each laps as lap}
							<tr>
								<td>{lap.index}</td>
								<td>{formatDistance(lap.distance_m)}</td>
								<td>{formatDuration(lap.duration_s)}</td>
								<td class="split-pace">
									{lap.distance_m > 0 ? formatPace(lap.duration_s, lap.distance_m) : '—'}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</section>
		{/if}

		<!-- Running Dynamics — Garmin HRM-Pro / Run pod metrics off an
		     imported FIT session. Renders only the fields the watch recorded
		     (round-5 garmin F2). -->
		{#if hasRunningDynamics && runningDynamics}
			<section class="section running-dynamics">
				<h2>{m('runDetail.runningDynamics')}</h2>
				<div class="key-stats">
					{#if runningDynamics.vertical_oscillation_mm != null}
						<div class="key-stat">
							<span class="key-stat-value">{runningDynamics.vertical_oscillation_mm} mm</span>
							<span class="key-stat-label">{m('runDetail.verticalOscillation')}</span>
						</div>
					{/if}
					{#if runningDynamics.gct_ms != null}
						<div class="key-stat">
							<span class="key-stat-value">{runningDynamics.gct_ms} ms</span>
							<span class="key-stat-label">{m('runDetail.groundContact')}</span>
						</div>
					{/if}
					{#if runningDynamics.stride_length_m != null}
						<div class="key-stat">
							<span class="key-stat-value">{runningDynamics.stride_length_m.toFixed(2)} m</span>
							<span class="key-stat-label">{m('runDetail.strideLength')}</span>
						</div>
					{/if}
					{#if runningDynamics.power_w != null}
						<div class="key-stat">
							<span class="key-stat-value">{runningDynamics.power_w} W</span>
							<span class="key-stat-label">{m('runDetail.avgPower')}</span>
						</div>
					{/if}
				</div>
			</section>
		{/if}

		<!-- Splits — only rendered when the GPS track carries timestamps -->
		{#if splits.length > 0}
			{@const hasElevation = splits.some((s) => s.elevation_m != null)}
			<section class="section">
				<h2>{m('runDetail.splits')}</h2>
				<table class="splits-table">
					<thead>
						<tr>
							<th>{m('runDetail.km')}</th>
							<th>{m('runDetail.pace')}</th>
							{#if hasElevation}<th>{m('runDetail.elev')}</th>{/if}
						</tr>
					</thead>
					<tbody>
						{#each splits as split}
							<tr>
								<td>{split.km}</td>
								<td class="split-pace">
									{Math.floor(split.pace_s / 60)}:{String(split.pace_s % 60).padStart(2, '0')}
								</td>
								{#if hasElevation}
									<td class="split-elev" class:positive={(split.elevation_m ?? 0) > 0} class:negative={(split.elevation_m ?? 0) < 0}>
										{(split.elevation_m ?? 0) > 0 ? '+' : ''}{split.elevation_m ?? '—'} m
									</td>
								{/if}
							</tr>
						{/each}
					</tbody>
				</table>
			</section>
		{/if}

		<!-- HR zones — real distribution when the track carries per-
		     point BPM samples, honest "no data" card otherwise. The
		     recording clients (phone + watches) will start writing
		     `bpm` alongside GPS over the next few recording passes;
		     historical runs that only stored `metadata.avg_bpm` render
		     the empty-state copy. -->
		<section class="section">
			<h2>{m('runDetail.heartRateZones')}</h2>
			{#if hrZones.length > 0}
				{#if bpmStats}
					<div class="hr-stats">
						<div class="hr-stat"><span class="hr-stat-label">{m('runDetail.avg')}</span><span class="hr-stat-value">{bpmStats.avg}</span></div>
						<div class="hr-stat"><span class="hr-stat-label">{m('runDetail.min')}</span><span class="hr-stat-value">{bpmStats.min}</span></div>
						<div class="hr-stat"><span class="hr-stat-label">{m('runDetail.max')}</span><span class="hr-stat-value">{bpmStats.max}</span></div>
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
				{#if zoneCutoffs == null && maxHrBpm == null}
					<p class="hr-disclaimer">
						{m('runDetail.hrDisclaimerPrefix')}
						<a href="/settings/account">{m('runDetail.hrDisclaimerLink')}</a>
						{m('runDetail.hrDisclaimerSuffix')}
					</p>
				{/if}
			{:else}
				<p class="hr-empty">
					{#if avgBpm != null}
						{m('runDetail.hrAvgOnly', { bpm: avgBpm })}
					{:else}
						{m('runDetail.hrNoData')}
					{/if}
				</p>
			{/if}
		</section>
	</aside>
		{/if}
		{/snippet}
	</SplitPane>
	</div>
</div>

<ConfirmDialog
	open={showDeleteConfirm}
	title={m('runDetail.deleteDialogTitle')}
	message={m('runDetail.deleteDialogMessage')}
	confirmLabel={m('runDetail.delete')}
	onconfirm={confirmDelete}
	oncancel={() => showDeleteConfirm = false}
	danger
/>

<ConfirmDialog
	open={showShareConfirm}
	title={m('runDetail.shareDialogTitle')}
	message={shareConfirmIntersectsZone
		? m('runDetail.shareDialogMessageIntersects')
		: shareConfirmHasZones
			? m('runDetail.shareDialogMessageNoIntersect')
			: m('runDetail.shareDialogMessageNoZones')}
	confirmLabel={m('runDetail.makePublicConfirm')}
	onconfirm={proceedShare}
	oncancel={() => (showShareConfirm = false)}
	data-testid="share-confirm-dialog"
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
		<div class="share-card-eyebrow">Threkir</div>
		{#if shareMapUrl}
			<!-- Real map background so the share card shows WHERE the
				 run happened, not just the stats numbers. crossorigin=
				 anonymous so html-to-image's `toPng(...)` can read the
				 pixel buffer back from the canvas (tileserver-gl +
				 MapTiler both serve CORS headers, but the explicit
				 attribute is what unlocks the canvas readback). -->
			<img
				src={shareMapUrl}
				class="share-card-map"
				alt=""
				crossorigin="anonymous"
				data-testid="share-card-map"
			/>
		{/if}
		<div class="share-card-stats">
			<div class="share-stat">
				<div class="share-stat-label">{m('runDetail.distance')}</div>
				<div class="share-stat-value">{formatDistance(run.distance_m)}</div>
			</div>
			<div class="share-stat">
				<div class="share-stat-label">{m('runDetail.time')}</div>
				<div class="share-stat-value">{formatDuration(run.duration_s)}</div>
			</div>
			<div class="share-stat">
				<div class="share-stat-label">{m('runDetail.pace')}</div>
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
	.loading-grid {
		flex: 1;
		display: grid;
		grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
		min-height: 0;
	}
	.loading-map {
		min-height: 0;
		border-inline-end: 1px solid var(--color-border);
	}
	.loading-stats {
		padding: var(--space-xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		background: var(--color-surface);
	}
	.loading-key-stats {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-md);
		margin-top: var(--space-sm);
	}
	.skeleton-shimmer {
		background: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		animation: skeleton-shimmer 1.4s ease-in-out infinite;
		border-radius: var(--radius-md);
	}
	.skeleton-title { height: 1.8rem; width: 60%; }
	.skeleton-line { height: 0.9rem; width: 40%; }
	.skeleton-stat { height: 3.5rem; }
	.skeleton-block { height: 8rem; margin-top: var(--space-sm); }
	.back-link-skeleton { height: 2.5rem; }
	@keyframes skeleton-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (max-width: 900px) {
		.loading-grid { grid-template-columns: 1fr; grid-template-rows: 40vh 1fr; }
		.loading-map { border-inline-end: none; border-bottom: 1px solid var(--color-border); }
		.loading-key-stats { grid-template-columns: repeat(2, 1fr); }
	}
	.not-found {
		text-align: center;
		padding: var(--space-2xl);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		color: var(--color-text-secondary);
	}
	.not-found h1 { color: var(--color-text); margin: 0; }

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

	/* Narrow viewports: stack vertically with INFO on top + MAP
	 * below. The May 2026 panel-flip moved info into the left
	 * snippet; on a stacked layout that means info takes its
	 * natural height in document flow + the map gets a fixed
	 * pane below. The old rules pre-flip sized .split-left as
	 * if it were the map (45vh fixed) — that left the info pane
	 * cramped into a 320 px scroll area on phones.
	 *
	 * Now: .split-left (info) is auto-height + grows with
	 * content; .split-right (map) is a fixed 50vh pane below.
	 * Stats scroll with the page rather than inside the panel,
	 * which matches how every other detail page feels on phones.
	 */
	@media (max-width: 900px) {
		/* The desktop layout pins height: 100vh on `.run-detail`
		 * so the SplitPane has a fixed container to size into.
		 * On a stacked mobile view we want the document to scroll
		 * naturally — release the height pin below. */
		.run-detail {
			height: auto;
			min-height: 100vh;
		}
		.run-detail-body :global(.split-pane) {
			flex-direction: column;
			height: auto;
		}
		.run-detail-body :global(.split-left) {
			width: 100% !important;
			height: auto;
			flex: 0 0 auto;
		}
		.run-detail-body :global(.split-right) {
			width: 100%;
			height: 50vh;
			min-height: 320px;
			flex: 0 0 50vh;
		}
		.run-detail-body :global(.split-divider) {
			display: none;
		}
		.stats-panel {
			padding: var(--space-lg);
			overflow-y: visible;
		}
	}

	@media (max-width: 640px) {
		.key-stat-value {
			font-size: 1.3rem;
		}
		h1 {
			font-size: 1.3rem;
		}
	}

	/*
	 * Container-query responsive rules. Triggered by the WIDTH of
	 * `.stats-panel` (named container `stats`) — which the user
	 * can shrink via the SplitPane drag. The breakpoints adapt the
	 * dense layouts (key-stats grid, header row, meta strip,
	 * splits table) so a 320 px-wide panel still reads cleanly.
	 *
	 * Why named: makes the intent explicit + lets every rule below
	 * target the same container without each one repeating its
	 * dimensions. Falls back to standard `@container` when the
	 * Svelte compiler emits CSS.
	 */
	@container stats (max-width: 520px) {
		.stats-panel {
			padding: var(--space-lg);
		}
		.key-stat-value {
			font-size: 1.25rem;
		}
		.detail-header {
			margin-bottom: var(--space-lg);
		}
	}
	@container stats (max-width: 380px) {
		.stats-panel {
			padding: var(--space-md);
		}
		.detail-header-top {
			/* Title + action buttons go vertical so the buttons
			 * don't squeeze the title. */
			flex-direction: column;
			align-items: stretch;
		}
		h1 {
			font-size: 1.2rem;
		}
		.splits-table th,
		.splits-table td {
			font-size: 0.75rem;
			padding: var(--space-xs) 0;
		}
		/* Section spacing tightens so the user gets more content
		 * per scroll on a narrow panel. */
		.section {
			padding-top: var(--space-md);
			margin-bottom: var(--space-md);
		}
		.section h2 {
			font-size: 0.95rem;
		}
		/* Meta strip wraps cleanly + each item gets its own line
		 * on very narrow panels. */
		.detail-meta {
			gap: 0.3rem 0.6rem;
			font-size: 0.8rem;
		}
		/* Panel back link shrinks proportionally. */
		.panel-back {
			font-size: 0.75rem;
		}
	}

	.page-back {
		padding: var(--space-sm) var(--space-xl);
		font-size: 0.85rem;
		font-weight: 500;
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}
	.page-back:hover {
		background: var(--color-bg-secondary);
	}
	.page-back .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}

	/*
	 * Compact in-panel back link. Lives at the top of the stats
	 * panel rather than as a full-width strip above the SplitPane —
	 * reclaims the ~42px vertical strip the standalone bar used to
	 * cost. Visual hierarchy: muted-text color so it doesn't compete
	 * with the H1; gains primary color on hover for the affordance.
	 */
	.panel-back {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-text-tertiary);
		margin-bottom: var(--space-md);
		transition: color var(--transition-fast);
	}
	.panel-back:hover {
		color: var(--color-primary);
	}
	.panel-back .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1rem;
	}

	.map-panel {
		flex: 1;
		min-height: 0;
		background: var(--color-bg-tertiary);
		position: relative;
	}

	.map-empty {
		height: 100%;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		padding: var(--space-2xl);
		text-align: center;
		color: var(--color-text-secondary);
	}
	.map-empty > .material-symbols {
		font-size: 3rem;
		color: var(--color-text-tertiary);
	}
	.map-empty-title {
		margin: 0;
		font-size: 1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.map-empty-sub {
		margin: 0;
		font-size: 0.85rem;
		max-width: 32rem;
		line-height: 1.5;
	}

	.route-suggest-banner {
		display: flex;
		align-items: center;
		gap: 0.7rem;
		padding: 0.7rem 0.9rem;
		margin: 0.6rem 0 1rem;
		border-radius: var(--radius-lg);
		background: var(--color-bg-tertiary);
		border: 1px solid var(--color-border);
	}
	.route-suggest-banner > .material-symbols {
		font-size: 1.4rem;
		color: var(--color-primary);
	}
	.route-suggest-body { flex: 1; }
	.route-suggest-text { font-size: 0.9rem; }
	.route-suggest-sub {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		margin-top: 0.15rem;
	}
	.route-suggest-actions {
		display: flex;
		gap: 0.4rem;
	}

	.match-pill {
		position: absolute;
		top: 12px;
		inset-inline-start: 12px;
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.35rem 0.7rem;
		border-radius: 999px;
		background: rgba(20, 22, 38, 0.78);
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		line-height: 1;
		border: 1px solid var(--color-border);
		backdrop-filter: blur(6px);
		z-index: 5;
		pointer-events: none;
	}
	.match-pill .material-symbols {
		font-size: 0.95rem;
	}
	.match-pill-failed { color: var(--color-text); }
	.match-pill-skipped { color: var(--color-text-tertiary); }

	.match-pill-action {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		margin-inline-start: 0.4rem;
		padding: 0.15rem 0.45rem;
		border-radius: 999px;
		background: transparent;
		border: 1px solid var(--color-border);
		color: inherit;
		font-size: 0.72rem;
		line-height: 1;
		cursor: pointer;
		pointer-events: auto;
	}
	.match-pill-action:hover:not(:disabled) {
		background: rgba(255, 255, 255, 0.08);
	}
	.match-pill-action:disabled {
		opacity: 0.55;
		cursor: progress;
	}
	.match-pill-action .material-symbols {
		font-size: 0.85rem;
	}

	.segment-card {
		position: absolute;
		inset-inline-start: 12px;
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
		flex: 1;
		min-height: 0;
		padding: var(--space-xl);
		overflow-y: auto;
		background: var(--color-surface);
		/*
		 * Container queries — the panel is resizable via SplitPane,
		 * so its width is decoupled from the viewport. Layouts inside
		 * (key-stats grid, splits table, header row) need to respond
		 * to the PANEL's width, not the page's. Naming the container
		 * `stats` lets the `@container` rules below target it
		 * directly without polluting the global query namespace.
		 */
		container-type: inline-size;
		container-name: stats;
	}

	.detail-header {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-bottom: var(--space-xl);
	}

	.detail-header-top {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
	}

	.detail-title-block {
		min-width: 0;
		flex: 1;
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		line-height: 1.2;
		margin: 0;
		color: var(--color-text);
		overflow-wrap: anywhere;
	}

	.detail-meta {
		display: flex;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
		margin-top: var(--space-sm);
		flex-wrap: wrap;
	}

	.meta-item {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		line-height: 1;
	}

	.meta-item .material-symbols {
		font-size: 1rem;
		color: var(--color-text-tertiary);
	}

	.meta-source {
		gap: 0.4rem;
	}

	.meta-source-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 50%;
		background: var(--source-color, var(--color-text-tertiary));
		flex-shrink: 0;
	}

	.visibility-chip {
		padding: 0.2rem 0.55rem;
		border-radius: 9999px;
		background: var(--color-bg-tertiary);
		border: 1px solid var(--color-border);
		font-weight: 600;
		font-size: 0.72rem;
	}

	.visibility-chip.is-public {
		background: var(--color-success-light);
		border-color: transparent;
		color: var(--color-success);
	}

	.visibility-chip.is-public .material-symbols {
		color: var(--color-success);
	}

	.dnf-chip {
		padding: 0.2rem 0.55rem;
		border-radius: 9999px;
		background: var(--color-danger-light);
		border: 1px solid transparent;
		color: var(--color-danger);
		font-weight: 600;
		font-size: 0.72rem;
	}

	.dnf-chip .material-symbols {
		color: var(--color-danger);
	}

	.discipline-chip {
		padding: 0.2rem 0.55rem;
		border-radius: 9999px;
		background: var(--color-bg-tertiary);
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
		font-weight: 600;
		font-size: 0.72rem;
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

	h2 {
		font-size: 0.95rem;
		font-weight: 600;
		margin: 0 0 var(--space-md);
		color: var(--color-text);
		letter-spacing: 0;
	}

	/*
	 * Key-stats grid. Polish pass:
	 *   - `auto-fit` + `minmax(132px, 1fr)` so cells fluidly reflow
	 *     by their CONTAINER's width — no explicit 4 → 3 → 2 → 1
	 *     breakpoints needed (the container queries on the panel
	 *     remain for typography sizing, not column count).
	 *   - Hairline dividers via `gap: 1px` + a background colour
	 *     trick: parent paints `var(--color-border)`, cells paint
	 *     `var(--color-bg-secondary)`, the 1px gap shows through
	 *     as a clean tile separator regardless of how the row
	 *     wraps. Looks like a unified card from a distance + a
	 *     clear grid up close.
	 *   - `tabular-nums lining-nums` on the values so multi-digit
	 *     stats line up vertically + don't jitter when the underlying
	 *     value ticks (`12:34` vs `12:36` was visually shifting).
	 */
	.key-stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(132px, 1fr));
		gap: 1px;
		margin-bottom: var(--space-xl);
		background: var(--color-border);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
	}

	.key-stat {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		min-width: 0;
		padding: var(--space-md) var(--space-lg);
		background: var(--color-bg-secondary);
	}

	/* The Activity-type filler tile pairs an icon with the label
	 * text — needs a flex container at the value level so they
	 * line up cleanly. The rest of the key-stat-value rule below
	 * still applies (font-size, weight, tabular nums). */
	.key-stat-activity .key-stat-value {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	.key-stat-activity .key-stat-value .material-symbols {
		font-size: 1.25rem;
		color: var(--color-text-secondary);
	}

	.key-stat-value {
		font-variant-numeric: tabular-nums lining-nums;
		font-size: 1.5rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--color-text);
		line-height: 1.1;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.key-stat-label {
		/* 0.8125rem (13px) on the secondary colour rather than 0.7rem on
		   tertiary — readable at arm's length for presbyopic / older
		   runners without changing the layout (persona round-5 older). */
		font-size: 0.8125rem;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.section {
		margin-bottom: var(--space-xl);
		padding-top: var(--space-xl);
		border-top: 1px solid var(--color-border);
	}

	.section:first-of-type {
		padding-top: 0;
		border-top: none;
	}

	.splits-table {
		width: 100%;
		border-collapse: collapse;
	}

	.splits-table th {
		text-align: start;
		/* Match .key-stat-label — 13px on the secondary colour for
		   arm's-length legibility (persona round-5 older). */
		font-size: 0.8125rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
	}

	.splits-table td {
		padding: var(--space-sm) 0;
		font-size: 0.85rem;
		border-bottom: 1px solid var(--color-border);
	}

	.splits-table tr:last-child td {
		border-bottom: none;
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
		text-align: start;
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
		text-align: end;
		font-variant-numeric: tabular-nums;
	}

	.workout-table td {
		padding: var(--space-sm) 0;
		font-size: 0.82rem;
		border-bottom: 1px solid var(--color-border);
	}

	.workout-table tr:last-child td {
		border-bottom: none;
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

	.run-notes {
		margin: 0;
		padding: var(--space-sm) var(--space-md);
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		border-inline-start: 3px solid var(--color-primary);
	}

	.action-btns {
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
		flex-shrink: 0;
	}

	.action-divider {
		width: 1px;
		height: 1.4rem;
		background: var(--color-border);
		margin: 0 var(--space-xs);
	}

	.icon-btn {
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-sm);
		width: 2.25rem;
		height: 2.25rem;
		padding: 0;
		cursor: pointer;
		color: var(--color-text-secondary);
		display: inline-flex;
		align-items: center;
		justify-content: center;
		transition: background var(--transition-fast), color var(--transition-fast), border-color var(--transition-fast);
	}

	.icon-btn:hover:not(:disabled) {
		background: var(--color-bg-tertiary);
		color: var(--color-primary);
		border-color: var(--color-border);
	}

	.icon-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}

	.icon-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.icon-btn.danger:hover:not(:disabled) {
		background: var(--color-danger-light);
		color: var(--color-danger);
		border-color: transparent;
	}

	.icon-btn .material-symbols {
		font-size: 1.1rem;
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

	.edit-dnf {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		font-size: 0.82rem;
		cursor: pointer;
	}

	.edit-dnf input {
		margin-top: 0.2rem;
		flex-shrink: 0;
	}

	.edit-dnf span {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}

	.edit-dnf-hint {
		font-weight: 400;
		font-size: 0.75rem;
		color: var(--color-text-muted);
		line-height: 1.4;
	}

	.edit-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
	}

	.edit-public-hint {
		margin: 0;
		font-size: 0.75rem;
		color: var(--color-warning, #b45309);
	}

	.edit-public-hint-muted {
		color: var(--color-text-muted);
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

	.hr-disclaimer {
		font-size: 0.78rem;
		color: var(--color-text-muted);
		line-height: 1.5;
		margin: var(--space-sm) 0 0;
	}

	.hr-disclaimer a {
		color: var(--color-primary);
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
	.share-card-map {
		display: block;
		width: 100%;
		height: 360px;
		border-radius: 24px;
		object-fit: cover;
		border: 4px solid rgba(255, 255, 255, 0.15);
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
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
