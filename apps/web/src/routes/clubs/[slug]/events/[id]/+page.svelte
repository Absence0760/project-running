<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import { initial, hashHue } from '$lib/format/avatar';
	import { formatDuration as baseDuration, activeFormatLocale } from '$lib/format/time';
	import { page } from '$app/stores';
	import { afterNavigate, goto } from '$app/navigation';
	import { supabase } from '$lib/core/supabase';
	import type { RealtimeChannel } from '@supabase/supabase-js';
	import {
		fetchEventById,
		fetchClubBySlug,
		fetchEventAttendees,
		fetchClubPosts,
		fetchRouteById,
		rsvpEvent,
		clearRsvp,
		markAttendance,
		deleteEvent,
		createClubPost,
		fetchEventResults,
		submitEventResult,
		removeEventResult,
		fetchRecentRunsForPicker,
		fetchRaceSession,
		armRace,
		startRace,
		endRace,
		approveEventResult,
		approveEventResultById,
		bulkImportEventResults,
		requestEventResultClaim,
		fetchMyEventResultClaims,
		fetchPendingEventResultClaims,
		decideEventResultClaim,
		type EventResultClaimWithUser,
		fetchEventExceptions,
		cancelEventInstance,
		reinstateEventInstance,
		fetchEventPhotos,
		addRunPhoto,
		fetchEventMeetPoint,
		fetchEventPricing,
		startEventCheckout,
		fetchMyOrder,
		type EventResultWithUser,
		type RecentRunOption,
		type RaceSessionRow,
		type EventException,
		type EventPhoto,
		fetchSessionPlan,
		fetchSessionPlans,
		setEventSessionPlan,
		type SessionPlan,
		type SessionPlanWithItems
	} from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import GymEditor from '$lib/components/GymEditor.svelte';
	import CheckpointManager from '$lib/components/CheckpointManager.svelte';
	import { expandInstances, describeRecurrence } from '$lib/social/recurrence';
	import { isAthleticCategory } from '$lib/social/event_category';
	import { workoutDraftFromTemplate } from '$lib/social/event_gym_template';
	import { expandSessionSteps, type SessionPlanInput } from '$lib/social/session_steps';
	import { formatDistance, getUnit, fmtPace } from '$lib/format/units.svelte';
	import { formatPrice } from '$lib/format/format_price';
	import { registrationOpen } from '$lib/social/paid_registration';
	import { env } from '$env/dynamic/public';
	import { buildStaticMarkerMapUrl, mapsDirectionsUrl, geoUri } from '$lib/routes/static_map';
	import { buildFinisherCertificateSvg, CERT_WIDTH, CERT_HEIGHT } from '$lib/runs/finisher_certificate';
	import { rasterizeSvgToPng, downloadBlob } from '$lib/format/svg_raster';
	import { parseChipTimingCsv, resultsToCsv, type ParsedResultRow } from '$lib/runs/event_results_csv';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type {
		EventWithMeta,
		ClubWithMeta,
		EventAttendee,
		ClubPostWithAuthor,
		Route,
		RsvpStatus,
		EventAttendance,
		EventPricing
	} from '$lib/types';

	let slug = $derived($page.params.slug as string);
	let eventId = $derived($page.params.id as string);

	let club = $state<ClubWithMeta | null>(null);
	let event = $state<EventWithMeta | null>(null);
	// Meetup coordinates, members-only via the get_event_meet_point RPC
	// (the raw columns are revoked from clients). Persona social-group #10.
	let meetPoint = $state<{ lat: number; lng: number } | null>(null);
	// On Android, a `geo:` link hands off to the user's native maps app
	// (Google Maps, Waze, Organic Maps…); the universal https URL is the
	// safe fallback for desktop / iOS browsers (persona round-5
	// social-group). Set client-side — the page is statically prerendered.
	let isAndroid = $state(false);
	let directionsHref = $derived(
		meetPoint
			? isAndroid
				? geoUri(meetPoint.lat, meetPoint.lng, event?.meet_label ?? undefined)
				: mapsDirectionsUrl(meetPoint.lat, meetPoint.lng)
			: '',
	);
	let meetMapUrl = $derived(
		meetPoint
			? buildStaticMarkerMapUrl(meetPoint.lat, meetPoint.lng, {
					w: 320,
					h: 180,
					style: 'streets-v2',
					key: env.PUBLIC_MAPTILER_KEY ?? ''
				})
			: null
	);
	let attendees = $state<(EventAttendee & { display_name: string | null; avatar_url: string | null })[]>([]);
	let eventPosts = $state<ClubPostWithAuthor[]>([]);
	let route = $state<Route | null>(null);
	let loading = $state(true);
	let busy = $state(false);
	let error = $state<string | null>(null);
	let draftPost = $state('');
	let results = $state<EventResultWithUser[]>([]);
	let eventPhotos = $state<EventPhoto[]>([]);
	let photoUploading = $state(false);
	let showResultPicker = $state(false);
	let runOptions = $state<RecentRunOption[]>([]);
	let submitting = $state(false);
	let raceSession = $state<RaceSessionRow | null>(null);
	let raceBusy = $state(false);
	let nowTick = $state(Date.now());
	let autoApproveOnArm = $state(true);
	let showEndRaceConfirm = $state<'finished' | 'cancelled' | null>(null);
	let showDeleteEventConfirm = $state(false);
	let showRemoveResultConfirm = $state(false);
	let exceptions = $state<EventException[]>([]);
	let showCancelInstance = $state(false);
	let cancelReason = $state('');

	// Paid registration (club_events.md slice P1). `pricing` is the
	// effective price for the active instance (per-instance override wins
	// over the series default; null = free event, original RSVP flow).
	let pricing = $state<EventPricing | null>(null);
	let registering = $state(false);
	// Post-checkout reconciliation: the webhook may lag the redirect, so
	// when ?paid=1 returns we poll for the buyer's paid order rather than
	// trusting the URL. 'idle' before the poll, 'processing' while polling,
	// 'confirmed' once the order/attendee row materialises, 'slow' if the
	// poll budget elapses (degrade to "refresh shortly", never a false fail).
	let paymentState = $state<'idle' | 'processing' | 'confirmed' | 'slow'>('idle');

	/** The instance the user is currently RSVPing to. For one-off events this
	 * stays equal to `event.starts_at`; for recurring events, the user can
	 * pick any of the next N instances. */
	let activeInstance = $state<string | null>(null);

	let cameFromClub = $state(false);
	afterNavigate(({ from }) => {
		if (!cameFromClub && from?.url.pathname === `/clubs/${slug}`) {
			cameFromClub = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromClub) {
			e.preventDefault();
			history.back();
		}
	}

	// All upcoming occurrences within a year. The previous (max 6, 120-day)
	// cap left weeks 7+ of a weekly series unreachable (parkrun persona #40);
	// expandInstances still honours recurrence_until / recurrence_count, so a
	// bounded series stops naturally. The picker shows a preview and expands
	// to the full list on demand (see INSTANCE_PREVIEW_COUNT below).
	let nextInstances = $derived(
		event
			? expandInstances(event, new Date(), new Date(Date.now() + 365 * 24 * 3600 * 1000))
			: []
	);
	// Cancelled occurrences (persona #39) are filtered out of the live picker.
	let cancelledSet = $derived(
		new Set(exceptions.map((e) => new Date(e.instance_start).toISOString()))
	);
	let liveInstances = $derived(
		nextInstances.filter((d) => !cancelledSet.has(d.toISOString()))
	);
	let activeException = $derived(
		activeInstance
			? exceptions.find(
					(e) => new Date(e.instance_start).toISOString() === activeInstance
				) ?? null
			: null
	);
	let showAllInstances = $state(false);
	const INSTANCE_PREVIEW_COUNT = 8;
	let visibleInstances = $derived(
		showAllInstances ? liveInstances : liveInstances.slice(0, INSTANCE_PREVIEW_COUNT)
	);

	let recurrenceLabel = $derived(
		event ? describeRecurrence(event.recurrence_freq, event.recurrence_byday) : ''
	);

	let isAdmin = $derived(club?.viewer_role === 'owner' || club?.viewer_role === 'admin');
	let isEventOrganiser = $derived(
		isAdmin || club?.viewer_role === 'event_organiser'
	);
	let isRaceDirector = $derived(
		isAdmin || club?.viewer_role === 'race_director'
	);
	let isMember = $derived(club?.viewer_role != null);
	// run / cycle carry route, distance, pace, race mode and a results
	// leaderboard; class / social are attendance-only. Default athletic until
	// the event loads so a momentary null never flashes a class layout for a run.
	let isAthletic = $derived(event ? isAthleticCategory(event.category) : true);

	// The class -> gym seam (inform-tier): a signed-in attendee can one-tap-log
	// a templated class as their own gym workout. Gated on category === 'class'
	// AND a non-null gym_template AND a signed-in viewer — a run/cycle/social
	// event never offers it.
	let canLogAsWorkout = $derived(
		!!event && event.category === 'class' && event.gym_template != null && auth.user != null
	);
	let showLogWorkout = $state(false);

	// Host-only attendance marking (instructor_business.md M6): the organiser
	// of a `class` event records who actually showed up. Orthogonal to RSVP —
	// non-hosts only ever see the resulting state read-only.
	let canMarkAttendance = $derived(
		isEventOrganiser && event?.category === 'class'
	);
	let markingAttendance = $state<string | null>(null);

	// Session planner (session_planner.md P1): a class event may carry a
	// session_plan_id. Show the attached sequence read-only here; an organiser
	// can attach/detach an existing plan. The DB trigger is the real gate.
	let sessionPlan = $state<SessionPlanWithItems | null>(null);
	let myPlans = $state<SessionPlan[]>([]);
	let showAttach = $state(false);
	let attachChoice = $state<string>('');
	let isClass = $derived(!!event && event.category === 'class');
	let sessionSteps = $derived.by(() => {
		if (!sessionPlan) return [];
		const input: SessionPlanInput = {
			blocks: sessionPlan.blocks.map((b) => ({ id: b.id, position: b.position, name: b.name })),
			items: sessionPlan.items.map((it) => ({
				id: it.id,
				block_id: it.block_id,
				position: it.position,
				movement_name: it.movement_name,
				kind: it.kind,
				duration_s: it.duration_s,
				reps: it.reps,
				per_side: it.per_side,
				tempo: it.tempo,
				cue: it.cue
			}))
		};
		return expandSessionSteps(input).steps;
	});

	async function loadSessionPlan() {
		const planId = event?.session_plan_id ?? null;
		sessionPlan = planId ? await fetchSessionPlan(planId) : null;
	}

	async function openAttach() {
		myPlans = await fetchSessionPlans();
		attachChoice = event?.session_plan_id ?? '';
		showAttach = true;
	}

	async function saveAttach() {
		if (!event) return;
		try {
			await setEventSessionPlan(event.id, attachChoice || null);
			event = { ...event, session_plan_id: attachChoice || null };
			await loadSessionPlan();
			showAttach = false;
			showToast(m('session.attached'), 'success');
		} catch (e) {
			showToast(e instanceof Error ? e.message : m('session.saveFailed'), 'error');
		}
	}

	function sessionStepLabel(step: (typeof sessionSteps)[number]): string {
		// A per-side item expands into two steps (left then right). The read
		// view localizes the side word so the two are distinguishable —
		// expandSessionSteps only carries the `side`, it deliberately leaves
		// the wording to the display layer.
		const name =
			step.side === 'left'
				? m('session.sideLeft', { name: step.movementName })
				: step.side === 'right'
					? m('session.sideRight', { name: step.movementName })
					: step.movementName;
		if (step.kind === 'reps') {
			return m('session.stepReps', { name, reps: step.reps ?? 0 });
		}
		if (step.kind === 'flow') {
			return m('session.stepFlow', { name, seconds: step.durationS ?? 0 });
		}
		return m('session.stepHold', { name, seconds: step.durationS ?? 0 });
	}

	let isPast = $derived(
		!!event &&
			(event.recurrence_freq
				? liveInstances.length === 0
				: new Date(event.starts_at).getTime() < Date.now())
	);

	let rsvpCounts = $derived.by(() => {
		const c = { going: 0, maybe: 0, declined: 0, waitlisted: 0 };
		for (const a of attendees) {
			if (a.status === 'going') c.going += 1;
			else if (a.status === 'maybe') c.maybe += 1;
			else if (a.status === 'declined') c.declined += 1;
			else if (a.status === 'waitlisted') c.waitlisted += 1;
		}
		return c;
	});

	let viewerRsvpForActive = $derived.by(() => {
		if (!event || !activeInstance) return null;
		if (activeInstance === event.next_instance_start) return event.viewer_rsvp;
		const me = attendees.find((a) => a.user_id === auth.user?.id);
		return (me?.status as RsvpStatus | undefined) ?? null;
	});

	// A paid registration is the order-backed `going` row (not maybe/declined).
	let viewerHasPaidSlot = $derived(
		pricing != null &&
			(viewerRsvpForActive === 'going' || viewerRsvpForActive === 'waitlisted')
	);

	let priceFormatted = $derived(
		pricing
			? formatPrice(pricing.price_cents / 100, {
					currency: pricing.currency.toUpperCase()
				})
			: ''
	);

	// Registration state for a priced event (free events keep the RSVP tri).
	let regState = $derived.by(() => {
		if (!pricing || !event || !activeInstance) return null;
		return registrationOpen(
			new Date(nowTick),
			activeInstance,
			pricing.sales_close_offset_minutes,
			event.capacity ?? null,
			rsvpCounts.going + rsvpCounts.waitlisted,
			viewerHasPaidSlot
		);
	});

	async function load() {
		loading = true;
		const prevInstance = activeInstance;
		[club, event, exceptions] = await Promise.all([
			fetchClubBySlug(slug),
			fetchEventById(eventId),
			fetchEventExceptions(eventId)
		]);
		if (!event) {
			loading = false;
			return;
		}
		// Preserve the user's instance selection across loads — otherwise
		// rsvp() (which calls load()) silently warps the user back to the
		// next instance after every click on a later one.
		activeInstance = prevInstance ?? event.next_instance_start;
		// Members-only meetup coordinates (null for non-members / no point set).
		meetPoint = await fetchEventMeetPoint(event.id);
		await loadSessionPlan();
		await reloadInstance();
		loading = false;
	}

	async function reloadInstance() {
		if (!event || !club || !activeInstance) return;
		const res = await Promise.all([
			fetchEventAttendees(event.id, activeInstance),
			event.route_id ? fetchRouteById(event.route_id) : Promise.resolve(null),
			fetchClubPosts(club.id, 50),
			fetchEventResults(event.id, activeInstance),
			fetchRaceSession(event.id, activeInstance),
			fetchEventPhotos(event.id, activeInstance)
		]);
		attendees = res[0];
		route = res[1];
		eventPosts = (res[2] as ClubPostWithAuthor[]).filter(
			(p) => p.event_id === event!.id && (!p.event_instance_start || p.event_instance_start === activeInstance)
		);
		results = res[3];
		raceSession = res[4];
		eventPhotos = res[5];
		pricing = await fetchEventPricing(event.id, activeInstance);
		// Bib-result claims (persona #43): the viewer's own claim state for
		// the pending-row affordance, and the organiser's adjudication queue.
		myClaims = myUserId
			? await fetchMyEventResultClaims(event.id, activeInstance)
			: new Map();
		pendingClaims = isEventOrganiser
			? await fetchPendingEventResultClaims(event.id, activeInstance)
			: [];
	}

	let myClaims = $state<Map<string, 'pending' | 'approved' | 'rejected'>>(new Map());
	let pendingClaims = $state<EventResultClaimWithUser[]>([]);

	async function claimResult(resultId: string) {
		try {
			await requestEventResultClaim(resultId);
			showToast(m('clubEvent.claimSubmitted'), 'success');
			await reloadInstance();
		} catch (err) {
			showToast(err instanceof Error ? err.message : m('clubEvent.claimSubmitFailed'), 'error');
		}
	}

	async function decideClaim(claimId: string, approve: boolean) {
		try {
			await decideEventResultClaim(claimId, approve);
			showToast(approve ? m('clubEvent.claimApproved') : m('clubEvent.claimRejected'), 'success');
			await reloadInstance();
		} catch (err) {
			showToast(err instanceof Error ? err.message : m('clubEvent.claimUpdateFailed'), 'error');
		}
	}

	// #49: when the viewer has a finisher result here, their own result row
	// carries run_id (the redaction view nulls it for everyone else), so the
	// photo attaches to that run with zero extra clicks. Group runs and other
	// non-race events have no result rows, so any signed-in attendee instead
	// picks which of their own runs the photo belongs to (persona round-5
	// runner-social-group) — addRunPhoto needs a run_id the uploader owns.
	let myEventRunId = $derived(
		results.find((r) => r.user_id === myUserId && r.run_id)?.run_id ?? null
	);
	let canAddPhoto = $derived(auth.user != null);
	let showPhotoRunPicker = $state(false);
	let pendingPhotoRunId = $state<string | null>(null);
	let photoFileInput: HTMLInputElement | null = $state(null);

	async function openPhotoFlow() {
		if (!canAddPhoto || photoUploading) return;
		if (myEventRunId) {
			pendingPhotoRunId = myEventRunId;
			photoFileInput?.click();
			return;
		}
		if (runOptions.length === 0) {
			runOptions = await fetchRecentRunsForPicker(20);
		}
		showPhotoRunPicker = true;
	}

	function pickRunForPhoto(runId: string) {
		pendingPhotoRunId = runId;
		showPhotoRunPicker = false;
		photoFileInput?.click();
	}

	async function handleAddEventPhoto(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		const runId = pendingPhotoRunId;
		pendingPhotoRunId = null;
		if (!file || !event || !runId || photoUploading) return;
		photoUploading = true;
		try {
			await addRunPhoto({
				run_id: runId,
				file,
				event_id: event.id,
				event_instance_start: activeInstance
			});
			eventPhotos = await fetchEventPhotos(event.id, activeInstance!);
		} catch (err) {
			error = err instanceof Error ? err.message : m('clubEvent.photoUploadFailed');
		} finally {
			photoUploading = false;
		}
	}

	/**
	 * Fan a race-state change out to every other subscriber on this
	 * channel as a broadcast. Supabase's postgres_changes filter has a
	 * server-side setup latency that trails the SUBSCRIBED ack — an
	 * INSERT/UPDATE that lands inside that window is dropped on the
	 * subscriber side. Broadcasts don't share that fragility (broadcast
	 * delivery is gated on the JOIN ack alone), so we emit one alongside
	 * every race_sessions write. Members listen for both: the broadcast
	 * is the fast path, the postgres_changes subscription remains as a
	 * fallback / late-joiner signal. The pollRaceSession() heartbeat
	 * below is the third line of defence if both drop.
	 */
	function broadcastRaceStateChanged() {
		channel?.send({
			type: 'broadcast',
			event: 'race-state-changed',
			payload: {}
		});
	}

	async function handleArm() {
		if (!event || !activeInstance || raceBusy) return;
		raceBusy = true;
		try {
			raceSession = await armRace(event.id, activeInstance, autoApproveOnArm);
			broadcastRaceStateChanged();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.armFailed');
		} finally {
			raceBusy = false;
		}
	}

	async function handleStart() {
		if (!event || !activeInstance || raceBusy) return;
		raceBusy = true;
		try {
			raceSession = await startRace(event.id, activeInstance);
			broadcastRaceStateChanged();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.startFailed');
		} finally {
			raceBusy = false;
		}
	}

	function handleEnd(status: 'finished' | 'cancelled') {
		if (!event || !activeInstance || raceBusy) return;
		showEndRaceConfirm = status;
	}

	async function confirmEndRace() {
		if (!event || !activeInstance || !showEndRaceConfirm) return;
		const status = showEndRaceConfirm;
		showEndRaceConfirm = null;
		raceBusy = true;
		try {
			raceSession = await endRace(event.id, activeInstance, status);
			broadcastRaceStateChanged();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.endFailed');
		} finally {
			raceBusy = false;
		}
	}

	async function handleApprove(userId: string, approve: boolean) {
		if (!event || !activeInstance) return;
		try {
			await approveEventResult(event.id, activeInstance, userId, approve);
			await reloadInstance();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.approvalFailed');
		}
	}

	// Bib-only imported finishers have user_id = NULL and are unreachable by the
	// user-id-keyed approve RPC, so approve them by row id instead (persona
	// round-5 event-organizer).
	async function handleApproveById(resultId: string, approve: boolean) {
		try {
			await approveEventResultById(resultId, approve);
			await reloadInstance();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.approvalFailed');
		}
	}

	// Tick for the live elapsed display during a race.
	let tickTimer: ReturnType<typeof setInterval> | null = null;
	$effect(() => {
		if (raceSession?.status === 'running') {
			tickTimer = setInterval(() => (nowTick = Date.now()), 500);
			return () => {
				if (tickTimer) clearInterval(tickTimer);
				tickTimer = null;
			};
		}
	});

	let raceElapsedS = $derived(
		raceSession?.status === 'running' && raceSession.started_at
			? Math.max(0, Math.floor((nowTick - new Date(raceSession.started_at).getTime()) / 1000))
			: 0
	);

	async function openResultPicker() {
		if (runOptions.length === 0) {
			runOptions = await fetchRecentRunsForPicker(20);
		}
		showResultPicker = true;
	}

	async function pickRunAsResult(run: RecentRunOption) {
		if (!event || !activeInstance || submitting) return;
		submitting = true;
		try {
			await submitEventResult({
				eventId: event.id,
				instanceStart: activeInstance,
				durationS: run.duration_s,
				distanceM: run.distance_m,
				runId: run.id,
				finisherStatus: 'finished'
			});
			showResultPicker = false;
			await reloadInstance();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.submitFailed');
		} finally {
			submitting = false;
		}
	}

	async function recordNonFinish(status: 'dnf' | 'dns') {
		if (!event || !activeInstance || submitting) return;
		submitting = true;
		try {
			await submitEventResult({
				eventId: event.id,
				instanceStart: activeInstance,
				durationS: 0,
				distanceM: 0,
				finisherStatus: status
			});
			showResultPicker = false;
			await reloadInstance();
		} catch (e) {
			// Match the surrounding pattern: surface failures via the
			// page-level `error` banner rather than letting them
			// propagate uncaught. Pre-fix, a network drop on DNF / DNS
			// left the picker open with no feedback and the user
			// guessing whether their non-finish was recorded.
			error = e instanceof Error ? e.message : m('clubEvent.resultSubmitFailed');
		} finally {
			submitting = false;
		}
	}

	async function removeMyResult() {
		if (!event || !activeInstance || submitting) return;
		submitting = true;
		try {
			await removeEventResult(event.id, activeInstance);
			showRemoveResultConfirm = false;
			await reloadInstance();
		} catch (e) {
			error = e instanceof Error ? e.message : m('clubEvent.resultRemoveFailed');
		} finally {
			submitting = false;
		}
	}

	function formatDuration(s: number): string {
		return s <= 0 ? '—' : baseDuration(s);
	}

	/// #44: build + download a finisher certificate PNG for a result row.
	/// Client-rendered SVG → PNG (no server PDF service). Available on any
	/// finished + approved result — finisher data is already public on the
	/// leaderboard, and a certificate is celebratory, not sensitive.
	// --- Organiser bulk results import (persona #43) ---
	let importOpen = $state(false);
	let importBusy = $state(false);
	let importErrors = $state<string[]>([]);
	let importPreview = $state<ParsedResultRow[]>([]);
	let importFileName = $state<string | null>(null);
	let importInput: HTMLInputElement | null = $state(null);

	function openImport() {
		importOpen = true;
		importErrors = [];
		importPreview = [];
		importFileName = null;
	}

	function closeImport() {
		importOpen = false;
		importErrors = [];
		importPreview = [];
		importFileName = null;
		if (importInput) importInput.value = '';
	}

	async function onImportFile(e: Event) {
		const file = (e.currentTarget as HTMLInputElement).files?.[0];
		if (!file) return;
		importFileName = file.name;
		try {
			const text = await file.text();
			const { rows, errors } = parseChipTimingCsv(text, event?.distance_m ?? 0);
			importPreview = rows;
			importErrors = errors;
		} catch {
			importPreview = [];
			importErrors = [m('clubEvent.importReadError')];
		}
	}

	async function confirmImport() {
		if (!event || !activeInstance || importBusy || importPreview.length === 0) return;
		importBusy = true;
		try {
			await bulkImportEventResults({
				eventId: event.id,
				instanceStart: activeInstance,
				rows: importPreview
			});
			showToast(
				m(importPreview.length === 1 ? 'clubEvent.importedToastOne' : 'clubEvent.importedToastMany', {
					n: importPreview.length
				}),
				'success'
			);
			closeImport();
			await reloadInstance();
		} catch (err) {
			console.error('bulk result import failed', err);
			showToast(m('clubEvent.importFailed'), 'error');
		} finally {
			importBusy = false;
		}
	}

	let certBusy = $state<string | null>(null);
	async function downloadCertificate(r: EventResultWithUser) {
		if (!event || certBusy) return;
		certBusy = rowKey(r);
		try {
			const svg = buildFinisherCertificateSvg({
				eventTitle: event.title,
				finisherName: r.display_name ?? m('clubEvent.runnerFallback'),
				durationS: r.duration_s,
				distanceM: r.distance_m,
				rank: r.rank,
				dateIso: activeInstance ?? event.starts_at,
				unit: getUnit(),
				clubName: club?.name ?? null,
			});
			const blob = await rasterizeSvgToPng(svg, CERT_WIDTH, CERT_HEIGHT);
			const safe = event.title.replace(/[^a-z0-9]+/gi, '-').toLowerCase();
			downloadBlob(blob, `threkir-certificate-${safe}.png`);
		} catch (e) {
			console.error('certificate generation failed', e);
			showToast(m('clubEvent.certificateFailed'), 'error');
		} finally {
			certBusy = null;
		}
	}

	function exportResultsCsv() {
		if (!event || results.length === 0) return;
		const csv = resultsToCsv(
			results.map((r) => ({
				bib: r.bib,
				finisherName: r.finisher_name ?? r.display_name,
				durationS: r.duration_s,
				distanceM: r.distance_m,
				finisherStatus: r.finisher_status,
				rank: r.rank,
			}))
		);
		const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
		const safe = event.title.replace(/[^a-z0-9]+/gi, '-').toLowerCase();
		downloadBlob(blob, `threkir-results-${safe}.csv`);
	}

	function formatRunDate(iso: string): string {
		return new Date(iso).toLocaleDateString(activeFormatLocale(), {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}

	let myUserId = $derived(auth.user?.id ?? null);

	// Stable per-row key for the leaderboard. Account rows have a unique
	// user_id per instance; bib-only imported rows (persona #43) have a
	// unique bib. The identity CHECK guarantees one of them is set.
	function rowKey(r: EventResultWithUser): string {
		return r.user_id ?? r.bib ?? '';
	}
	let hasMyResult = $derived(
		myUserId !== null && results.some((r) => r.user_id === myUserId)
	);

	async function pickInstance(iso: string) {
		activeInstance = iso;
		await reloadInstance();
	}

	let channel: RealtimeChannel | null = null;
	// Mirrors the channel's SUBSCRIBED state so the page can advertise
	// "realtime is live" via a data attribute. The race-control e2e
	// suite races against this — the admin clicks Arm before the
	// member's WS handshake completes, the INSERT event is missed,
	// and the banner never appears. Waiting on data-realtime-ready
	// closes that window deterministically.
	let realtimeReady = $state(false);

	onMount(async () => {
		isAndroid = /Android/i.test(navigator.userAgent);
		// Wait for auth.user before loading. The event page derives
		// `isAdmin` from `club.viewer_role` which is fetched against
		// the caller's identity; if `auth.user` hasn't resolved when
		// load() fires, viewer_role can come back null even for the
		// real owner, which collapses every admin affordance.
		// Same shape we patch on every authed page.
		await auth.ready();
		await load();
		// Returned from Stripe Checkout: reconcile the order (?paid=1).
		if ($page.url.searchParams.get('paid') === '1') {
			void pollForPaidOrder();
		}
		// Guard each side-effect: if subscribeRealtime throws (the
		// `.on('postgres_changes', ...) after subscribe()` bug that
		// bites when Supabase's RealtimeClient returns a cached
		// already-subscribed channel from a prior page lifecycle),
		// the heartbeat must still start — otherwise dropped realtime
		// events strand the spectator on stale state.
		try {
			subscribeRealtime();
		} catch (e) {
			console.warn('subscribeRealtime failed; falling back to poll', e);
		}
		startRaceSessionHeartbeat();
	});

	onDestroy(() => {
		if (pingRetryTimer) {
			clearTimeout(pingRetryTimer);
			pingRetryTimer = null;
		}
		if (raceHeartbeat) {
			clearInterval(raceHeartbeat);
			raceHeartbeat = null;
		}
		if (channel) {
			supabase.removeChannel(channel);
			channel = null;
		}
		realtimeReady = false;
	});

	/**
	 * Heartbeat that re-fetches just the race session row. Realtime
	 * is best-effort: a dropped broadcast (CI load, transient WS
	 * hiccup, channel-cold-start filter-wiring lag) leaves the page
	 * stale and the spectator has no way to know. This is the
	 * cheap belt-and-suspenders — single small row, always
	 * reassigned (Svelte 5's $state proxy occasionally misses
	 * transitions when the previous and next values shallow-compare
	 * equal but the page hasn't reconciled). Stops once the race
	 * is in a terminal state (finished / cancelled) so a long-lived
	 * page on a finished event doesn't keep polling.
	 *
	 * Interval: 2 s. Originally 5 s, but `event-race-control.spec.ts`
	 * (CI run 26337440523) caught a real failure mode where the
	 * member's channel cold-start wiring missed the admin's `armed`
	 * broadcast AND postgres_changes row, and the next 5 s heartbeat
	 * fired AFTER the test's 15 s `.race-banner` wait had already
	 * expired (the test's clock budget includes auth + page mount +
	 * `.realtime-ready` settle, leaving ~10 s for the banner). 2 s
	 * fits ~5 polls inside the wait, restoring the contract that a
	 * spectator can't lose a race-state transition silently. Backend
	 * cost is 1 small SELECT every 2 s while the event page is open
	 * — well under the rate limit any single open tab can drive.
	 */
	let raceHeartbeat: ReturnType<typeof setInterval> | null = null;
	function startRaceSessionHeartbeat() {
		if (raceHeartbeat) return;
		raceHeartbeat = setInterval(async () => {
			if (!event || !activeInstance) return;
			if (raceSession?.status === 'finished' || raceSession?.status === 'cancelled') {
				if (raceHeartbeat) {
					clearInterval(raceHeartbeat);
					raceHeartbeat = null;
				}
				return;
			}
			const fresh = await fetchRaceSession(event.id, activeInstance);
			raceSession = fresh;
		}, 2000);
	}

	/**
	 * Event page realtime: watch attendee rows for this event so the "going"
	 * count + attendee list refresh as others RSVP, and watch club_posts so
	 * admin updates tagged to this event appear without refresh.
	 */
	let debounceTimer: ReturnType<typeof setTimeout> | null = null;
	function scheduleReload() {
		if (debounceTimer) clearTimeout(debounceTimer);
		debounceTimer = setTimeout(() => {
			if (event && activeInstance) reloadInstance();
		}, 250);
	}

	let pingRetryTimer: ReturnType<typeof setTimeout> | null = null;
	function sendReadyPing() {
		channel?.send({ type: 'broadcast', event: 'ready-ping', payload: {} });
	}
	function schedulePingRetry() {
		if (pingRetryTimer) clearTimeout(pingRetryTimer);
		pingRetryTimer = setTimeout(() => {
			pingRetryTimer = null;
			if (realtimeReady || !channel) return;
			sendReadyPing();
			schedulePingRetry();
		}, 1500);
	}

	function subscribeRealtime() {
		if (!event || !club) return;
		channel = supabase
			.channel(`event-${event.id}`, {
				// Opt-in to receive our own broadcasts — the readiness
				// roundtrip below relies on the echo.
				config: { broadcast: { self: true } }
			})
			// Self-broadcast roundtrip — see the .subscribe() callback
			// below. Listen FIRST so the echo can't beat the listener.
			.on('broadcast', { event: 'ready-ping' }, () => {
				if (pingRetryTimer) {
					clearTimeout(pingRetryTimer);
					pingRetryTimer = null;
				}
				realtimeReady = true;
				console.log(`[realtime] event-${event?.id} ready=true`);
			})
			// Fast path for race-state transitions. Admin's handleArm /
			// handleStart / confirmEndRace each emit one of these right
			// after the race_sessions write. Receivers reload the event
			// detail — same handler as postgres_changes, so duplicate
			// delivery is harmless (debounced by scheduleReload).
			.on('broadcast', { event: 'race-state-changed' }, scheduleReload)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'event_attendees',
					filter: `event_id=eq.${event.id}`
				},
				scheduleReload
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'club_posts',
					filter: `club_id=eq.${club.id}`
				},
				scheduleReload
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'race_sessions',
					filter: `event_id=eq.${event.id}`
				},
				scheduleReload
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'event_results',
					filter: `event_id=eq.${event.id}`
				},
				scheduleReload
			)
			.subscribe((status) => {
				console.log(`[realtime] event-${event?.id} status=${status}`);
				if (status !== 'SUBSCRIBED') {
					realtimeReady = false;
					return;
				}
				// Don't flip readiness on SUBSCRIBED alone — the server's
				// postgres_changes filter wiring trails the join ack by
				// a tick (race-banner regression observed in multi-
				// context CI). Send a self-broadcast on the same channel
				// and let the echo flip the flag — the echo's roundtrip
				// proves the channel is fully wired bidirectionally. Uses
				// the realtime WS, not setTimeout, so chromium's timer
				// throttling on backgrounded tabs doesn't affect it.
				// Retry every 1.5 s until the echo arrives — under CI
				// load the first ping is occasionally dropped, which
				// used to strand readiness past the test timeout.
				sendReadyPing();
				schedulePingRetry();
				// Belt-and-suspenders fallback: even if every ping echo
				// is dropped (CI WS hiccup or cold-start filter wiring
				// still settling), flip readiness 5 s after SUBSCRIBED
				// so consumers eventually proceed. By that point the
				// channel has had ample time to wire its postgres_changes
				// subscriptions server-side. Mirrors the same fallback
				// added to `/clubs/[slug]/+page.svelte`.
				setTimeout(() => {
					if (channel) realtimeReady = true;
				}, 5000);
			});
	}

	async function rsvp(status: RsvpStatus) {
		if (!event || !activeInstance || busy) return;
		busy = true;
		try {
			// The "going" button stands for both going and waitlisted (a
			// waitlisted RSVP is a pending "going"), so clicking it while
			// waitlisted leaves the queue.
			const shouldClear =
				viewerRsvpForActive === status ||
				(status === 'going' && viewerRsvpForActive === 'waitlisted');
			if (shouldClear) {
				await clearRsvp(event.id, activeInstance);
			} else {
				await rsvpEvent(event.id, status, activeInstance);
			}
			await load();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.rsvpFailed');
		} finally {
			busy = false;
		}
	}

	async function setAttendance(userId: string, current: EventAttendance | null, value: EventAttendance) {
		if (!event || !activeInstance || markingAttendance) return;
		// Toggle off when the host taps the already-set state.
		const next: EventAttendance | null = current === value ? null : value;
		markingAttendance = userId;
		try {
			// Scope the mark to the occurrence currently in view — the attendee has
			// a distinct row per instance_start on a recurring event.
			await markAttendance(event.id, userId, activeInstance, next);
			attendees = attendees.map((a) => (a.user_id === userId ? { ...a, attendance: next } : a));
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : m('clubEvent.attendanceFailed'), 'error');
		} finally {
			markingAttendance = null;
		}
	}

	async function register() {
		if (!event || !activeInstance || registering) return;
		if (!auth.user) {
			goto(`/login?next=${encodeURIComponent($page.url.pathname)}`);
			return;
		}
		registering = true;
		try {
			const { url } = await startEventCheckout(event.id, activeInstance);
			window.location.href = url;
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : m('clubEvent.registerFailed'), 'error');
			registering = false;
		}
	}

	/// Reconcile a ?paid=1 redirect. The stripe-events webhook flips the
	/// order to paid + writes the attendee row asynchronously, so poll the
	/// buyer's own order for up to ~5s (the <5s pattern from /settings/upgrade
	/// + paywall.md) before degrading to "processing, refresh shortly". Never
	/// a false-failure toast — the money may already be taken.
	async function pollForPaidOrder() {
		if (!event || !activeInstance) return;
		paymentState = 'processing';
		for (let i = 0; i < 10; i++) {
			const order = await fetchMyOrder(event.id, activeInstance);
			if (order?.status === 'paid') {
				paymentState = 'confirmed';
				showToast(m('clubEvent.paymentConfirmed'), 'success');
				await load();
				return;
			}
			await new Promise((r) => setTimeout(r, 500));
		}
		paymentState = 'slow';
		// Refresh once more so a late webhook is reflected without a manual reload.
		await load();
	}

	function handleDeleteEvent() {
		if (!event) return;
		showDeleteEventConfirm = true;
	}

	async function confirmDeleteEvent() {
		if (!event) return;
		showDeleteEventConfirm = false;
		try {
			await deleteEvent(event.id);
		} catch (e) {
			showToast(
				m('clubHome.deleteEventFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
			return;
		}
		goto(`/clubs/${slug}`);
	}

	async function confirmCancelInstance() {
		if (!event || !activeInstance || busy) return;
		busy = true;
		try {
			await cancelEventInstance(event.id, activeInstance, cancelReason || null);
			cancelReason = '';
			showCancelInstance = false;
			await load();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.cancelOccurrenceFailed');
		} finally {
			busy = false;
		}
	}

	async function reinstateInstance() {
		if (!event || !activeInstance || busy) return;
		busy = true;
		try {
			await reinstateEventInstance(event.id, activeInstance);
			await load();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.reinstateOccurrenceFailed');
		} finally {
			busy = false;
		}
	}

	async function submitPost(e: Event) {
		e.preventDefault();
		if (!club || !event || !activeInstance || !draftPost.trim() || busy) return;
		busy = true;
		try {
			await createClubPost({
				club_id: club.id,
				event_id: event.id,
				event_instance_start: event.recurrence_freq ? activeInstance : null,
				body: draftPost
			});
			draftPost = '';
			await reloadInstance();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('clubEvent.postUpdateFailed');
		} finally {
			busy = false;
		}
	}

	function fmtDate(iso: string): string {
		const d = new Date(iso);
		return d.toLocaleString(activeFormatLocale(), {
			weekday: 'long',
			month: 'long',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}


	function fmtRelative(iso: string): string {
		const diff = Date.now() - new Date(iso).getTime();
		const min = Math.floor(diff / 60_000);
		if (min < 1) return m('clubEvent.justNow');
		if (min < 60) return m('clubEvent.minutesAgo', { n: min });
		const hr = Math.floor(min / 60);
		if (hr < 24) return m('clubEvent.hoursAgo', { n: hr });
		return m('clubEvent.daysAgo', { n: Math.floor(hr / 24) });
	}


</script>

{#if loading}
	<div class="page" aria-busy="true" aria-label={m('clubEvent.loadingEvent')}>
		<span class="back-skel" aria-hidden="true">
			<span class="material-symbols">arrow_back</span>
			{m('clubEvent.backToClub')}
		</span>
		<div class="hero skel-hero" aria-hidden="true">
			<div class="skel-hero-text">
				<span class="skel skel-line skel-w-20"></span>
				<span class="skel skel-line skel-w-60"></span>
				<span class="skel skel-line skel-w-40"></span>
				<span class="skel skel-line skel-w-80"></span>
			</div>
			<div class="skel-hero-actions">
				<span class="skel skel-block"></span>
				<span class="skel skel-block"></span>
				<span class="skel skel-block"></span>
			</div>
		</div>
		<div class="skel-card" aria-hidden="true">
			<span class="skel skel-line skel-w-30"></span>
			<span class="skel skel-line skel-w-80"></span>
		</div>
	</div>
	<p class="sr-only" role="status">{m('clubEvent.loadingEventStatus')}</p>
{:else if !event || !club}
	<div class="page">
		<a class="back" href="/clubs/{slug}">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('clubEvent.backToClubs')}
		</a>
		<div class="empty-card">
			<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
			<h3>{m('clubEvent.notFoundTitle')}</h3>
			<p class="empty-text">
				{m('clubEvent.notFoundBody')}
			</p>
			<div class="empty-actions">
				<a href="/clubs/{slug}" class="btn btn-primary">{m('clubEvent.backToClub')}</a>
			</div>
		</div>
	</div>
{:else}
	<div
		class="page"
		class:realtime-ready={realtimeReady}
		data-debug-race-status={raceSession?.status ?? 'null'}
		data-debug-race-keys={raceSession ? Object.keys(raceSession).sort().join(',') : 'none'}
		data-debug-is-race-director={String(isRaceDirector)}
	>
		<a class="back" href="/clubs/{slug}" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('clubEvent.backToNamed', { name: club.name })}
		</a>

		<header class="hero" class:past={isPast}>
			<div class="hero-body">
				<span class="hero-eyebrow">
					{#if event.recurrence_freq}
						{recurrenceLabel}
					{:else if isPast}
						{m('clubEvent.pastEvent')}
					{:else}
						{m('clubEvent.upcomingEvent')}
					{/if}
				</span>
				<h1>{event.title}</h1>
				{#if event.is_public === false}
					<p class="members-only-badge" data-testid="members-only-badge">
						<span class="material-symbols" aria-hidden="true">lock</span>
						<span>{m('clubEvent.membersOnly')}</span>
					</p>
				{/if}
				{#if !isAthletic && event.discipline}
					<p class="discipline-chip">
						<span class="discipline-eyebrow">{m('clubEvent.disciplineLabel')}</span>
						<span class="discipline-value">{event.discipline}</span>
					</p>
				{/if}
				<p class="hero-tagline">
					<span class="material-symbols" aria-hidden="true">calendar_today</span>
					<span>{fmtDate(activeInstance ?? event.starts_at)}</span>
					{#if event.duration_min}
						<span class="dot-sep" aria-hidden="true">·</span>
						<span>{event.duration_min} min</span>
					{/if}
					{#if event.meet_label}
						<span class="dot-sep" aria-hidden="true">·</span>
						<span class="meet-inline">
							<span class="material-symbols" aria-hidden="true">place</span>
							{event.meet_label}
						</span>
					{/if}
				</p>
				{#if event.description}
					<p class="desc">{event.description}</p>
				{/if}

				<div class="metrics">
					{#if isAthletic && event.distance_m != null}
						<div class="metric">
							<span class="label">{m('clubEvent.distanceLabel')}</span>
							<span class="value">{formatDistance(event.distance_m)}</span>
						</div>
					{/if}
					{#if isAthletic && event.pace_target_sec}
						<div class="metric">
							<span class="label">{m('clubEvent.targetPaceLabel')}</span>
							<span class="value">{fmtPace(event.pace_target_sec)}</span>
						</div>
					{/if}
					<div class="metric">
						<span class="label">{m('clubEvent.goingLabel')}</span>
						<span class="value">
							{event.attendee_count}{event.capacity ? ` / ${event.capacity}` : ''}
						</span>
						{#if rsvpCounts.waitlisted > 0}
							<span class="waitlist-note">{m(rsvpCounts.waitlisted === 1 ? 'clubEvent.waitlistNoteOne' : 'clubEvent.waitlistNoteMany', { n: rsvpCounts.waitlisted })}</span>
						{/if}
					</div>
				</div>

				{#if isAthletic && route}
					<a class="route-chip" href="/routes/{route.id}">
						<span class="material-symbols" aria-hidden="true">route</span>
						{route.name}
						<span class="muted">— {formatDistance(route.distance_m)}</span>
					</a>
				{/if}

				{#if meetPoint}
					<div class="meet-point">
						{#if meetMapUrl}
							<a
								class="meet-map"
								href={directionsHref}
								target="_blank"
								rel="noopener noreferrer"
								aria-label={m('clubEvent.openMeetInMaps')}
							>
								<img src={meetMapUrl} alt={m('clubEvent.meetMapAlt')} loading="lazy" />
							</a>
						{/if}
						<a
							class="btn btn-secondary meet-directions"
							href={directionsHref}
							target="_blank"
							rel="noopener noreferrer"
						>
							<span class="material-symbols" aria-hidden="true">directions</span>
							{event.meet_label
								? m('clubEvent.getDirectionsTo', { label: event.meet_label })
								: m('clubEvent.getDirections')}
						</a>
					</div>
				{/if}
			</div>
			<div class="hero-side">
				{#if activeException}
					<div class="cancelled-banner" role="status">
						<span class="material-symbols" aria-hidden="true">event_busy</span>
						<div>
							<strong>{m('clubEvent.occurrenceCancelled')}</strong>
							{#if activeException.reason}
								<span class="cancel-reason">{activeException.reason}</span>
							{/if}
						</div>
					</div>
					{#if isEventOrganiser}
						<button
							type="button"
							class="btn-ghost"
							onclick={reinstateInstance}
							disabled={busy}
						>
							<span class="material-symbols" aria-hidden="true">event_available</span>
							{m('clubEvent.reinstateOccurrence')}
						</button>
					{/if}
				{:else if !isPast && pricing}
					<div class="register-box" data-testid="register-box">
						<div class="register-price">
							<span class="register-price-label">{m('clubEvent.priceLabel')}</span>
							<span class="register-price-amount">{priceFormatted}</span>
						</div>
						{#if paymentState === 'processing'}
							<p class="register-status processing" role="status">
								<span class="material-symbols" aria-hidden="true">hourglass_top</span>
								{m('clubEvent.paymentProcessing')}
							</p>
						{:else if paymentState === 'slow'}
							<p class="register-status processing" role="status">
								<span class="material-symbols" aria-hidden="true">schedule</span>
								{m('clubEvent.paymentProcessingSlow')}
							</p>
						{/if}
						{#if !auth.user}
							<a class="btn btn-primary register-cta" href={`/login?next=${encodeURIComponent($page.url.pathname)}`}>
								{m('clubEvent.registerSignInFirst')}
							</a>
						{:else if regState === 'already_registered'}
							<div class="register-status registered" role="status">
								<span class="material-symbols" aria-hidden="true">check_circle</span>
								{m('clubEvent.registered')}
							</div>
						{:else if regState === 'sold_out'}
							<div class="register-status closed" role="status">
								<span class="material-symbols" aria-hidden="true">block</span>
								{m('clubEvent.registerSoldOut')}
							</div>
						{:else if regState === 'sales_closed'}
							<div class="register-status closed" role="status">
								<span class="material-symbols" aria-hidden="true">lock_clock</span>
								{m('clubEvent.registerSalesClosed')}
							</div>
						{:else}
							<button
								type="button"
								class="btn btn-primary register-cta"
								onclick={register}
								disabled={registering}
								data-testid="register-cta"
							>
								{registering
									? m('clubEvent.registering')
									: m('clubEvent.registerForPrice', { price: priceFormatted })}
							</button>
						{/if}
					</div>
				{:else if !isPast && auth.user}
					<div
						class="rsvp-tri"
						role="group"
						aria-label={m('clubEvent.yourRsvp')}
					>
						<button
							type="button"
							class="rsvp-opt rsvp-going"
							class:active={viewerRsvpForActive === 'going' || viewerRsvpForActive === 'waitlisted'}
							aria-pressed={viewerRsvpForActive === 'going' || viewerRsvpForActive === 'waitlisted'}
							aria-label={viewerRsvpForActive === 'going'
								? m('clubEvent.going')
								: viewerRsvpForActive === 'waitlisted'
									? m('clubEvent.waitlisted')
									: m('clubEvent.imIn')}
							onclick={() => rsvp('going')}
							disabled={busy}
						>
							<span class="material-symbols" aria-hidden="true">
								{viewerRsvpForActive === 'going'
									? 'check_circle'
									: viewerRsvpForActive === 'waitlisted'
										? 'hourglass_top'
										: 'directions_run'}
							</span>
							<span class="rsvp-label">
								{viewerRsvpForActive === 'going'
									? m('clubEvent.going')
									: viewerRsvpForActive === 'waitlisted'
										? m('clubEvent.waitlisted')
										: m('clubEvent.imIn')}
							</span>
							<span class="rsvp-count" aria-hidden="true">{rsvpCounts.going}</span>
						</button>
						<button
							type="button"
							class="rsvp-opt rsvp-maybe"
							class:active={viewerRsvpForActive === 'maybe'}
							aria-pressed={viewerRsvpForActive === 'maybe'}
							aria-label={m('clubEvent.maybe')}
							onclick={() => rsvp('maybe')}
							disabled={busy}
						>
							<span class="material-symbols" aria-hidden="true">help_outline</span>
							<span class="rsvp-label">{m('clubEvent.maybe')}</span>
							<span class="rsvp-count" aria-hidden="true">{rsvpCounts.maybe}</span>
						</button>
						<button
							type="button"
							class="rsvp-opt rsvp-declined"
							class:active={viewerRsvpForActive === 'declined'}
							aria-pressed={viewerRsvpForActive === 'declined'}
							aria-label={m('clubEvent.cantMakeIt')}
							onclick={() => rsvp('declined')}
							disabled={busy}
						>
							<span class="material-symbols" aria-hidden="true">close</span>
							<span class="rsvp-label">{m('clubEvent.cantMakeIt')}</span>
							<span class="rsvp-count" aria-hidden="true">{rsvpCounts.declined}</span>
						</button>
					</div>
				{/if}
				{#if isEventOrganiser && event.recurrence_freq && activeInstance && !activeException}
					<div class="admin-actions">
						<button
							type="button"
							class="btn-ghost danger"
							onclick={() => (showCancelInstance = true)}
						>
							<span class="material-symbols" aria-hidden="true">event_busy</span>
							{m('clubEvent.cancelOccurrence')}
						</button>
					</div>
				{/if}
				{#if isAdmin}
					<div class="admin-actions">
						<button
							type="button"
							class="btn-ghost danger"
							onclick={handleDeleteEvent}
							aria-label={m('clubEvent.deleteEvent')}
						>
							<span class="material-symbols" aria-hidden="true">delete</span>
							{m('clubEvent.deleteEvent')}
						</button>
					</div>
				{/if}
			</div>
		</header>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		{#if event.recurrence_freq && liveInstances.length > 1}
			<section class="instance-picker">
				<span class="label">{m('clubEvent.pickOccurrence')}</span>
				<div class="instance-chips">
					{#each visibleInstances as iso}
						<button
							class="instance-chip"
							class:active={activeInstance === iso.toISOString()}
							onclick={() => pickInstance(iso.toISOString())}
						>
							{iso.toLocaleDateString(activeFormatLocale(), {
								weekday: 'short',
								month: 'short',
								day: 'numeric'
							})}
						</button>
					{/each}
				</div>
				{#if liveInstances.length > INSTANCE_PREVIEW_COUNT}
					<button
						type="button"
						class="instance-toggle"
						onclick={() => (showAllInstances = !showAllInstances)}
						aria-expanded={showAllInstances}
					>
						{showAllInstances
							? m('clubEvent.showFewer')
							: m('clubEvent.showAllUpcoming', { n: liveInstances.length })}
					</button>
				{/if}
			</section>
		{/if}

		{#if isMember}
			<section class="card">
				<h3>{m('clubEvent.postUpdateTitle')}</h3>
				<p class="sub">{m('clubEvent.postUpdateSub')}</p>
				<form class="post-form" onsubmit={submitPost}>
					<textarea
						bind:value={draftPost}
						placeholder={m('clubEvent.postUpdatePlaceholder')}
						rows="3"
						maxlength="1200"
					></textarea>
					<button class="btn-primary" type="submit" disabled={!draftPost.trim() || busy}>
						{m('clubEvent.postUpdateButton')}
					</button>
				</form>
			</section>
		{/if}

		{#if eventPosts.length > 0}
			<section class="card">
				<h3>{m('clubEvent.updatesTitle')}</h3>
				<div class="feed">
					{#each eventPosts as p (p.id)}
						<article class="post">
							<div class="post-author">
								<Avatar name={p.author_display_name} size="2rem" font="0.85rem" bg="seed" sat={50} seedHue={hashHue(p.author_id)} />
								<div>
									<strong>{p.author_display_name ?? m('clubEvent.memberFallback')}</strong>
									<span class="when">{fmtRelative(p.created_at ?? new Date().toISOString())}</span>
								</div>
							</div>
							<p class="post-body">{p.body}</p>
						</article>
					{/each}
				</div>
			</section>
		{/if}

		{#if isAthletic}
		{#if isRaceDirector}
			<section class="card race-panel">
				<div class="results-head">
					<h3>{m('clubEvent.raceControlTitle')}</h3>
					<a class="btn-link" href={`/live/event/${event.id}/${encodeURIComponent(activeInstance ?? '')}`} target="_blank" rel="noopener">
						{m('clubEvent.spectatorView')}
					</a>
				</div>
				{#if !raceSession || raceSession.status === 'finished' || raceSession.status === 'cancelled'}
					<p class="muted">
						{raceSession?.status === 'finished'
							? m('clubEvent.raceFinishedHint')
							: raceSession?.status === 'cancelled'
							? m('clubEvent.racePreviousCancelled')
							: m('clubEvent.raceArmHint')}
					</p>
					<label class="auto-approve">
						<input type="checkbox" bind:checked={autoApproveOnArm} />
						<span>{m('clubEvent.autoApproveResults')}</span>
					</label>
					<button type="button" class="btn btn-primary-sm" onclick={handleArm} disabled={raceBusy}>
						{m('clubEvent.armRace')}
					</button>
				{:else if raceSession.status === 'armed'}
					<p class="race-state armed">
						<span class="dot armed-dot"></span>
						<strong>{m('clubEvent.armedLabel')}</strong> {m('clubEvent.armedHint')}
					</p>
					<div class="race-actions">
						<button type="button" class="btn btn-primary-sm big" onclick={handleStart} disabled={raceBusy}>
							{m('clubEvent.go')}
						</button>
						<button type="button" class="btn-link" onclick={() => handleEnd('cancelled')} disabled={raceBusy}>
							{m('clubEvent.cancel')}
						</button>
					</div>
				{:else if raceSession.status === 'running'}
					<p class="race-state running">
						<span class="dot running-dot"></span>
						<strong>{m('clubEvent.runningLabel')}</strong> {m('clubEvent.runningElapsed', { time: formatDuration(raceElapsedS) })}
					</p>
					<div class="race-actions">
						<button type="button" class="btn btn-danger" onclick={() => handleEnd('finished')} disabled={raceBusy}>
							{m('clubEvent.endRace')}
						</button>
					</div>
				{/if}
			</section>
		{:else if raceSession && (raceSession.status === 'armed' || raceSession.status === 'running')}
			<section class="card race-banner">
				{#if raceSession.status === 'armed'}
					<p><span class="dot armed-dot"></span><strong>{m('clubEvent.raceArmedLabel')}</strong> {m('clubEvent.raceArmedHint')}</p>
				{:else}
					<p><span class="dot running-dot"></span><strong>{m('clubEvent.raceRunningLabel')}</strong> {m('clubEvent.raceRunningHint', { time: formatDuration(raceElapsedS) })}</p>
				{/if}
			</section>
		{/if}

		{#if isRaceDirector}
			<CheckpointManager eventId={event.id} />
			<section class="card checkpoint-board-link">
				<div class="results-head">
					<div>
						<h3>{m('checkpoint.boardTitle')}</h3>
						<p class="sub">{m('checkpoint.boardSub')}</p>
					</div>
					<a
						class="btn btn-primary-sm"
						href={`/clubs/${slug}/events/${event.id}/board?instance=${encodeURIComponent(activeInstance ?? event.starts_at)}`}
						data-testid="open-board"
					>
						{m('checkpoint.boardOpen')}
					</a>
				</div>
			</section>
		{/if}

		<section class="card">
			<div class="results-head">
				<h3>{m('clubEvent.resultsTitle', { n: results.length })}</h3>
				<div class="results-actions">
					{#if isEventOrganiser}
						<button type="button" class="btn-link" onclick={openImport}>{m('clubEvent.importResultsCsv')}</button>
						{#if results.length > 0}
							<button type="button" class="btn-link" onclick={exportResultsCsv}>{m('clubEvent.downloadResultsCsv')}</button>
						{/if}
					{/if}
					{#if myUserId}
						{#if hasMyResult}
							<button type="button" class="btn-link" onclick={() => (showRemoveResultConfirm = true)} disabled={submitting}>{m('clubEvent.removeMine')}</button>
						{:else}
							<button type="button" class="btn btn-primary-sm" onclick={openResultPicker} disabled={submitting}>
								{submitting ? m('clubEvent.submitting') : m('clubEvent.submitMyTime')}
							</button>
						{/if}
					{/if}
				</div>
			</div>
			{#if results.length === 0}
				<p class="muted">{m('clubEvent.noResultsYet')}</p>
			{:else}
				<ol class="results">
					{#each results as r (rowKey(r))}
						<li class="result" class:me={r.user_id !== null && r.user_id === myUserId} class:pending={!r.organiser_approved}>
							<span class="rank">{r.organiser_approved ? (r.rank ?? '—') : '…'}</span>
							<Avatar name={r.display_name} size="2rem" font="0.85rem" bg="seed" sat={50} seedHue={hashHue(rowKey(r))} />
							<div class="res-info">
								<strong>{r.display_name ?? m('clubEvent.runnerFallback')}</strong>
								{#if r.user_id !== null && r.user_id === myUserId}<span class="you">{m('clubEvent.youTag')}</span>{/if}
								{#if !r.organiser_approved}<span class="pending-tag">{m('clubEvent.pendingTag')}</span>{/if}
								{#if r.finisher_status !== 'finished'}
									<span class="dnf-tag">{r.finisher_status.toUpperCase()}</span>
								{/if}
							</div>
							{#if r.finisher_status === 'finished'}
								<span class="time">{formatDuration(r.duration_s)}</span>
								<span class="dist muted">{formatDistance(r.distance_m)}</span>
							{/if}
							{#if r.finisher_status === 'finished' && r.organiser_approved}
								<button
									type="button"
									class="btn-link cert"
									title={m('clubEvent.downloadCertificate')}
									disabled={certBusy === rowKey(r)}
									onclick={() => downloadCertificate(r)}
								>
									{certBusy === rowKey(r) ? '…' : m('clubEvent.certificate')}
								</button>
							{/if}
							{#if isRaceDirector && r.user_id !== null && !r.organiser_approved}
								<button type="button" class="btn-link approve" onclick={() => handleApprove(r.user_id!, true)}>{m('clubEvent.approve')}</button>
							{:else if isRaceDirector && r.user_id !== null && r.organiser_approved && r.user_id !== myUserId}
								<button type="button" class="btn-link reject" onclick={() => handleApprove(r.user_id!, false)}>{m('clubEvent.unverify')}</button>
							{:else if isRaceDirector && r.user_id === null && !r.organiser_approved}
								<button type="button" class="btn-link approve" onclick={() => handleApproveById(r.id, true)}>{m('clubEvent.approve')}</button>
							{:else if isRaceDirector && r.user_id === null && r.organiser_approved}
								<button type="button" class="btn-link reject" onclick={() => handleApproveById(r.id, false)}>{m('clubEvent.unverify')}</button>
							{/if}
							{#if myUserId && r.user_id === null && !hasMyResult}
								{#if myClaims.get(r.id) === 'pending'}
									<span class="claim-pending">{m('clubEvent.claimPending')}</span>
								{:else}
									<button type="button" class="btn-link claim" onclick={() => claimResult(r.id)}>{m('clubEvent.thisIsMe')}</button>
								{/if}
							{/if}
						</li>
					{/each}
				</ol>
			{/if}

			{#if isEventOrganiser && pendingClaims.length > 0}
				<div class="claims-queue">
					<h4>{m('clubEvent.resultClaimsTitle', { n: pendingClaims.length })}</h4>
					<p class="muted claims-help">{m('clubEvent.resultClaimsHelp')}</p>
					<ul>
						{#each pendingClaims as c (c.id)}
							<li>
								<span class="claim-desc">
									<strong>{c.claimant_name ?? m('clubEvent.runnerFallback')}</strong> {m('clubEvent.claimsBib', { bib: c.bib ?? '—' })}
									{#if c.finisher_name}<span class="muted">({c.finisher_name})</span>{/if}
								</span>
								<button type="button" class="btn-link approve" onclick={() => decideClaim(c.id, true)}>{m('clubEvent.approve')}</button>
								<button type="button" class="btn-link reject" onclick={() => decideClaim(c.id, false)}>{m('clubEvent.reject')}</button>
							</li>
						{/each}
					</ul>
				</div>
			{/if}

			{#if showResultPicker}
				<div class="picker">
					<h4>{m('clubEvent.attachRun')}</h4>
					{#if runOptions.length === 0}
						<p class="muted">{m('clubEvent.noRecentRuns')}</p>
					{:else}
						<ul class="run-options">
							{#each runOptions as run (run.id)}
								<li>
									<button
										type="button"
										class="run-option"
										onclick={() => pickRunAsResult(run)}
										disabled={submitting}
									>
										<span class="run-date">{formatRunDate(run.started_at)}</span>
										<span class="run-dist">{formatDistance(run.distance_m)}</span>
										<span class="run-time">{formatDuration(run.duration_s)}</span>
										<span class="run-kind muted">{run.activity_type}</span>
									</button>
								</li>
							{/each}
						</ul>
					{/if}
					<div class="picker-actions">
						<button type="button" class="btn-link" onclick={() => recordNonFinish('dnf')} disabled={submitting}>{m('clubEvent.recordDnf')}</button>
						<button type="button" class="btn-link" onclick={() => recordNonFinish('dns')} disabled={submitting}>{m('clubEvent.recordDns')}</button>
						<button type="button" class="btn-link" onclick={() => (showResultPicker = false)}>{m('clubEvent.cancel')}</button>
					</div>
				</div>
			{/if}

			{#if importOpen}
				<div class="picker import-panel">
					<h4>{m('clubEvent.importTitle')}</h4>
					<p class="muted import-help">
						{m('clubEvent.importHelpPrefix')} <code>bib</code>, <code>name</code> {m('clubEvent.importHelpAnd')} <code>time</code> {m('clubEvent.importHelpColumns')}
						(<code>status</code> {m('clubEvent.importHelpStatus')} <code>dnf</code> / <code>dns</code>).
						{m('clubEvent.importHelpSuffix')}
					</p>
					<label class="btn-link import-file">
						{importFileName ? m('clubEvent.importFileName', { name: importFileName }) : m('clubEvent.chooseCsvFile')}
						<input
							bind:this={importInput}
							type="file"
							accept=".csv,text/csv"
							onchange={onImportFile}
							hidden
						/>
					</label>
					{#if importErrors.length > 0}
						<ul class="import-errors">
							{#each importErrors.slice(0, 8) as err}
								<li>{err}</li>
							{/each}
							{#if importErrors.length > 8}
								<li>{m('clubEvent.andMore', { n: importErrors.length - 8 })}</li>
							{/if}
						</ul>
					{/if}
					{#if importPreview.length > 0}
						<p class="import-summary">{m(importPreview.length === 1 ? 'clubEvent.importReadyOne' : 'clubEvent.importReadyMany', { n: importPreview.length })}</p>
					{/if}
					<div class="picker-actions">
						<button
							type="button"
							class="btn btn-primary-sm"
							onclick={confirmImport}
							disabled={importBusy || importPreview.length === 0}
						>
							{importBusy
								? m('clubEvent.importing')
								: m(importPreview.length === 1 ? 'clubEvent.importButtonOne' : 'clubEvent.importButtonMany', { n: importPreview.length })}
						</button>
						<button type="button" class="btn-link" onclick={closeImport} disabled={importBusy}>{m('clubEvent.cancel')}</button>
					</div>
				</div>
			{/if}
		</section>
		{:else}
		<section class="card">
			<p class="muted">{m('clubEvent.attendanceOnly')}</p>
			{#if canLogAsWorkout}
				<div class="log-workout">
					<button
						type="button"
						class="btn btn-primary"
						data-testid="log-as-workout"
						onclick={() => (showLogWorkout = true)}
					>
						<span class="material-symbols" aria-hidden="true">fitness_center</span>
						{m('clubEvent.logAsWorkout')}
					</button>
					<p class="muted log-workout-hint">{m('clubEvent.logAsWorkoutHint')}</p>
				</div>
			{/if}
		</section>
		{/if}

		{#if isClass && (sessionPlan || isEventOrganiser)}
			<section class="card" data-testid="session-sequence">
				<div class="results-head">
					<h3>{m('session.sequence')}</h3>
					{#if isEventOrganiser}
						<button type="button" class="btn-link" onclick={openAttach}>
							{m('session.attachToEvent')}
						</button>
					{/if}
				</div>
				{#if sessionPlan}
					<a class="session-plan-name" href={`/sessions/${sessionPlan.id}`}>
						{sessionPlan.title}
					</a>
					<ol class="session-steps">
						{#each sessionSteps as step (step.itemId + (step.side ?? ''))}
							<li>
								<span>{sessionStepLabel(step)}</span>
								{#if step.cue}<span class="muted session-cue">{step.cue}</span>{/if}
							</li>
						{/each}
					</ol>
				{:else}
					<p class="muted">{m('session.attachNone')}</p>
				{/if}
			</section>
		{/if}

		<section class="card">
			<div class="results-head">
				<h3>{m('clubEvent.photosTitle', { n: eventPhotos.length })}</h3>
				{#if canAddPhoto}
					<button
						type="button"
						class="btn-link photo-add"
						onclick={openPhotoFlow}
						disabled={photoUploading}
					>
						{photoUploading ? m('clubEvent.uploading') : m('clubEvent.addPhoto')}
					</button>
				{/if}
			</div>
			<input
				bind:this={photoFileInput}
				type="file"
				accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
				onchange={handleAddEventPhoto}
				disabled={photoUploading}
				hidden
			/>
			{#if showPhotoRunPicker}
				<div class="picker">
					<h4>{m('clubEvent.whichRunPhoto')}</h4>
					{#if runOptions.length === 0}
						<p class="muted">{m('clubEvent.noRecentRuns')}</p>
					{:else}
						<ul class="run-options">
							{#each runOptions as run (run.id)}
								<li>
									<button
										type="button"
										class="run-option"
										onclick={() => pickRunForPhoto(run.id)}
									>
										<span class="run-date">{formatRunDate(run.started_at)}</span>
										<span class="run-dist">{formatDistance(run.distance_m)}</span>
										<span class="run-time">{formatDuration(run.duration_s)}</span>
										<span class="run-kind muted">{run.activity_type}</span>
									</button>
								</li>
							{/each}
						</ul>
					{/if}
					<div class="picker-actions">
						<button type="button" class="btn-link" onclick={() => (showPhotoRunPicker = false)}>{m('clubEvent.cancel')}</button>
					</div>
				</div>
			{/if}
			{#if eventPhotos.length === 0}
				<p class="muted">
					{m('clubEvent.noPhotosYet')}{canAddPhoto ? ` ${m('clubEvent.noPhotosAddHint')}` : ''}
				</p>
			{:else}
				<div class="photo-gallery">
					{#each eventPhotos as p (p.id)}
						<figure class="photo-tile">
							<img src={p.thumbUrl ?? p.url} alt={p.caption ?? m('clubEvent.eventPhotoAlt')} loading="lazy" />
							<figcaption>
								{#if p.caption}<span class="cap">{p.caption}</span>{/if}
								<span class="by">{p.uploader_name ?? m('clubEvent.runnerFallback')}</span>
							</figcaption>
						</figure>
					{/each}
				</div>
			{/if}
		</section>

		<section class="card">
			<h3>{m('clubEvent.attendeesTitle', { n: attendees.length })}</h3>
			{#if attendees.length === 0}
				<div class="attendees-empty">
					<span class="material-symbols" aria-hidden="true">group_add</span>
					<div>
						<strong>{m('clubEvent.noRsvpsYet')}</strong>
						<span class="muted">
							{#if !isPast && isMember}
								{m('clubEvent.beFirstRsvp')}
							{:else if !isPast}
								{m('clubEvent.joinToRsvp')}
							{:else}
								{m('clubEvent.noRsvpsLogged')}
							{/if}
						</span>
					</div>
				</div>
			{:else}
				<div class="attendees">
					{#each attendees as a (a.user_id)}
						<div class="attendee" class:maybe={a.status === 'maybe'} class:declined={a.status === 'declined'}>
							<Avatar name={a.display_name} size="2rem" font="0.85rem" bg="seed" sat={50} seedHue={hashHue(a.user_id)} />
							<div class="att-info">
								<strong>{a.display_name ?? m('clubEvent.memberFallback')}</strong>
								<span class="status">{a.status}</span>
							</div>
							{#if canMarkAttendance}
								<div class="attendance-controls" role="group" aria-label={m('clubEvent.attendanceLabel')}>
									<button
										type="button"
										class="att-btn attended"
										class:active={a.attendance === 'attended'}
										aria-pressed={a.attendance === 'attended'}
										disabled={markingAttendance !== null}
										title={m('clubEvent.markAttended')}
										onclick={() => setAttendance(a.user_id, a.attendance, 'attended')}
									>
										<span class="material-symbols" aria-hidden="true">check</span>
										<span class="att-btn-label">{m('clubEvent.markAttended')}</span>
									</button>
									<button
										type="button"
										class="att-btn no-show"
										class:active={a.attendance === 'no_show'}
										aria-pressed={a.attendance === 'no_show'}
										disabled={markingAttendance !== null}
										title={m('clubEvent.markNoShow')}
										onclick={() => setAttendance(a.user_id, a.attendance, 'no_show')}
									>
										<span class="material-symbols" aria-hidden="true">close</span>
										<span class="att-btn-label">{m('clubEvent.markNoShow')}</span>
									</button>
								</div>
							{:else if a.attendance}
								<span class="attendance-badge {a.attendance}">
									{a.attendance === 'attended' ? m('clubEvent.attendanceAttended') : m('clubEvent.attendanceNoShow')}
								</span>
							{/if}
						</div>
					{/each}
				</div>
			{/if}
		</section>
	</div>

<ConfirmDialog
	open={showEndRaceConfirm !== null}
	title={showEndRaceConfirm === 'cancelled' ? m('clubEvent.cancelRaceTitle') : m('clubEvent.endRaceTitle')}
	message={showEndRaceConfirm === 'cancelled' ? m('clubEvent.cancelRaceMessage') : m('clubEvent.endRaceMessage')}
	confirmLabel={showEndRaceConfirm === 'cancelled' ? m('clubEvent.cancelRaceTitle') : m('clubEvent.endRaceTitle')}
	onconfirm={confirmEndRace}
	oncancel={() => showEndRaceConfirm = null}
	danger
/>

<ConfirmDialog
	open={showRemoveResultConfirm}
	title={m('clubEvent.removeMyResultTitle')}
	message={m('clubEvent.removeMyResultMessage')}
	confirmLabel={m('clubEvent.removeResultConfirm')}
	onconfirm={removeMyResult}
	oncancel={() => (showRemoveResultConfirm = false)}
	danger
/>

<ConfirmDialog
	open={showDeleteEventConfirm}
	title={m('clubEvent.deleteEvent')}
	message={`${m('clubEvent.deleteEventMessage', { title: event?.title ?? '' })}${event?.recurrence_freq ? ` ${m('clubEvent.deleteEventAllOccurrences')}` : ''}`}
	confirmLabel={m('clubEvent.delete')}
	onconfirm={confirmDeleteEvent}
	oncancel={() => showDeleteEventConfirm = false}
	danger
/>

<Modal
	open={showCancelInstance}
	title={m('clubEvent.cancelOccurrence')}
	onclose={() => (showCancelInstance = false)}
>
	<div class="cancel-instance-form">
		<p>
			{m('clubEvent.cancelInstanceBody')}
		</p>
		<label>
			<span>{m('clubEvent.reasonOptional')}</span>
			<textarea
				bind:value={cancelReason}
				rows="2"
				maxlength="300"
				placeholder={m('clubEvent.cancelReasonPlaceholder')}
			></textarea>
		</label>
		<div class="cancel-instance-actions">
			<button
				type="button"
				class="btn btn-secondary"
				onclick={() => (showCancelInstance = false)}
				disabled={busy}
			>
				{m('clubEvent.keepIt')}
			</button>
			<button
				type="button"
				class="btn btn-danger"
				onclick={confirmCancelInstance}
				disabled={busy}
			>
				{busy ? m('clubEvent.cancelling') : m('clubEvent.cancelOccurrence')}
			</button>
		</div>
	</div>
</Modal>

{#if event && canLogAsWorkout}
	<Modal
		open={showLogWorkout}
		title={m('clubEvent.logAsWorkout')}
		onclose={() => (showLogWorkout = false)}
	>
		<GymEditor
			prefill={{ title: workoutDraftFromTemplate(event.gym_template, event.title).title }}
			oncreated={() => {
				showLogWorkout = false;
				showToast(m('clubEvent.logAsWorkoutSaved'), 'success');
			}}
			oncancel={() => (showLogWorkout = false)}
		/>
	</Modal>
{/if}

{#if event && isClass && isEventOrganiser}
	<Modal open={showAttach} title={m('session.attachToEvent')} onclose={() => (showAttach = false)}>
		<div class="attach-body">
			<label class="attach-field">
				<span>{m('session.sequence')}</span>
				<select bind:value={attachChoice} data-testid="attach-plan-select">
					<option value="">{m('session.attachNone')}</option>
					{#each myPlans as plan (plan.id)}
						<option value={plan.id}>{plan.title}</option>
					{/each}
				</select>
			</label>
			<div class="attach-actions">
				<button type="button" class="btn btn-secondary" onclick={() => (showAttach = false)}>
					{m('session.cancel')}
				</button>
				<button
					type="button"
					class="btn btn-primary"
					data-testid="attach-plan-save"
					onclick={saveAttach}
				>
					{m('session.attachSave')}
				</button>
			</div>
		</div>
	</Modal>
{/if}
{/if}

<style>
	.session-plan-name {
		display: inline-block;
		font-weight: 600;
		margin-bottom: var(--space-xs);
	}
	.session-steps {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		padding-inline-start: var(--space-lg);
		margin: 0;
	}
	.session-steps li {
		display: flex;
		flex-direction: column;
	}
	.session-cue {
		font-size: 0.85rem;
	}
	.attach-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.attach-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.attach-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}

	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		text-decoration: none;
	}
	.back:hover { color: var(--color-primary); }
	.back .material-symbols { font-size: 1.05rem; }

	.hero {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(16rem, auto);
		gap: var(--space-lg);
		padding: var(--space-lg) var(--space-xl);
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 12%, var(--color-surface)) 0%,
			var(--color-surface) 70%
		);
		border: 1px solid color-mix(in srgb, var(--color-primary) 28%, var(--color-border));
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-sm);
		margin-bottom: var(--space-lg);
	}
	.hero.past {
		background: var(--color-surface);
		border-color: var(--color-border);
		box-shadow: none;
	}
	.hero-body {
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.hero-eyebrow {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	.hero.past .hero-eyebrow {
		color: var(--color-text-tertiary);
	}

	.hero h1 {
		font-size: 1.65rem;
		font-weight: 700;
		margin: 0;
		line-height: 1.15;
	}
	.discipline-chip {
		display: inline-flex;
		align-items: baseline;
		gap: 0.5rem;
		margin: var(--space-xs) 0 0 0;
	}
	.members-only-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		margin: var(--space-xs) 0 0 0;
		padding: 0.2rem 0.6rem;
		border-radius: 999px;
		background: color-mix(in srgb, var(--color-text) 8%, transparent);
		color: var(--color-text-secondary);
		font-size: 0.82rem;
		font-weight: 700;
	}
	.members-only-badge .material-symbols {
		font-size: 1rem;
	}
	.discipline-eyebrow {
		text-transform: uppercase;
		letter-spacing: 0.06em;
		font-size: 0.72rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
	}
	.discipline-value {
		font-size: 1.15rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.hero-tagline {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.35rem;
		margin: var(--space-xs) 0 0 0;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
	}
	.hero-tagline .material-symbols { font-size: 1.05rem; color: var(--color-text-tertiary); }
	.hero-tagline .dot-sep { color: var(--color-text-tertiary); }
	.meet-inline {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}

	.instance-picker {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 0.7rem 0.9rem;
		margin-bottom: var(--space-md);
	}

	.instance-picker .label {
		display: block;
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.07em;
		color: var(--color-text-tertiary);
		margin-bottom: 0.5rem;
	}

	.instance-chips {
		display: flex;
		gap: 0.4rem;
		flex-wrap: wrap;
	}

	.instance-chip {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text);
		padding: 0.35rem 0.75rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		cursor: pointer;
	}

	.instance-chip.active {
		background: var(--color-primary);
		color: var(--color-bg);
		border-color: var(--color-primary);
	}

	.instance-toggle {
		margin-top: 0.6rem;
		background: none;
		border: none;
		padding: 0;
		color: var(--color-primary);
		font-weight: 600;
		font-size: 0.85rem;
		cursor: pointer;
	}

	.desc {
		margin-top: var(--space-sm);
		line-height: 1.55;
		white-space: pre-wrap;
	}

	.metrics {
		display: flex;
		flex-wrap: wrap;
		gap: 2rem;
		margin-top: var(--space-sm);
	}
	.metric {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.metric .label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		font-weight: 600;
	}
	.metric .value {
		font-size: 1.15rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.metric .waitlist-note {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.cancelled-banner {
		display: flex;
		align-items: flex-start;
		gap: 0.6rem;
		padding: 0.7rem 0.9rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		margin-bottom: 0.6rem;
	}
	.cancelled-banner .cancel-reason {
		display: block;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin-top: 0.15rem;
	}
	.cancel-instance-form { display: grid; gap: 0.8rem; }
	.cancel-instance-form label { display: grid; gap: 0.3rem; }
	.cancel-instance-form textarea {
		width: 100%;
		padding: 0.5rem 0.65rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-family: inherit;
	}
	.cancel-instance-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
	}

	.route-chip {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: var(--color-primary-light);
		color: var(--color-primary);
		padding: 0.4rem 0.85rem;
		border-radius: var(--radius-md);
		margin-top: var(--space-sm);
		font-weight: 600;
		font-size: 0.9rem;
		width: fit-content;
		text-decoration: none;
	}

	.meet-point {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		margin-top: var(--space-md);
		width: fit-content;
		max-width: 320px;
	}

	.meet-map {
		display: block;
		border-radius: var(--radius-md);
		overflow: hidden;
		line-height: 0;
		border: 1px solid var(--color-border);
	}

	.meet-map img {
		display: block;
		width: 320px;
		max-width: 100%;
		height: auto;
	}

	.meet-directions {
		width: fit-content;
	}

	.hero-side {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		align-self: start;
	}

	.register-box {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		padding: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.register-price {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 0.5rem;
	}
	.register-price-label {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.register-price-amount {
		font-size: 1.4rem;
		font-weight: 800;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
	}
	.register-cta {
		width: 100%;
		justify-content: center;
	}
	.register-status {
		display: flex;
		align-items: center;
		gap: 0.45rem;
		font-size: 0.9rem;
		font-weight: 600;
		margin: 0;
	}
	.register-status .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.15rem;
	}
	.register-status.registered {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
	}
	.register-status.closed {
		color: var(--color-text-tertiary);
	}
	.register-status.processing {
		color: var(--color-text-secondary);
	}
	.rsvp-tri {
		display: grid;
		grid-template-columns: 1fr;
		gap: 0.4rem;
		padding: 0.5rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		min-width: 14rem;
	}
	.rsvp-opt {
		display: grid;
		grid-template-columns: 1.4rem 1fr auto;
		align-items: center;
		gap: 0.55rem;
		padding: 0.55rem 0.7rem;
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-md);
		color: var(--color-text);
		font: inherit;
		font-weight: 600;
		font-size: 0.92rem;
		text-align: start;
		cursor: pointer;
		transition: background var(--transition-fast), border-color var(--transition-fast), color var(--transition-fast);
	}
	.rsvp-opt:hover:not(:disabled) {
		background: var(--color-bg-secondary);
	}
	.rsvp-opt:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}
	.rsvp-opt .material-symbols {
		font-size: 1.25rem;
		color: var(--color-text-tertiary);
	}
	.rsvp-opt .rsvp-count {
		font-variant-numeric: tabular-nums;
		font-size: 0.78rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		padding: 0.1rem 0.5rem;
		min-width: 1.6rem;
		text-align: center;
	}
	.rsvp-opt.active {
		font-weight: 700;
	}
	.rsvp-going.active {
		background: color-mix(in srgb, var(--color-success) 14%, transparent);
		border-color: var(--color-success);
		color: var(--color-success);
	}
	.rsvp-going.active .material-symbols,
	.rsvp-going.active .rsvp-count {
		color: var(--color-success);
		background: color-mix(in srgb, var(--color-success) 18%, transparent);
	}
	.rsvp-maybe.active {
		background: color-mix(in srgb, var(--color-warning) 16%, transparent);
		border-color: var(--color-warning);
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
	}
	.rsvp-maybe.active .material-symbols,
	.rsvp-maybe.active .rsvp-count {
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
		background: color-mix(in srgb, var(--color-warning) 22%, transparent);
	}
	.rsvp-declined.active {
		background: var(--color-danger-light);
		border-color: var(--color-danger);
		color: var(--color-danger);
	}
	.rsvp-declined.active .material-symbols,
	.rsvp-declined.active .rsvp-count {
		color: var(--color-danger);
		background: color-mix(in srgb, var(--color-danger) 18%, transparent);
	}

	.admin-actions {
		display: flex;
		justify-content: flex-end;
	}
	.btn-ghost {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
		padding: 0.4rem 0.75rem;
		border-radius: var(--radius-md);
		font: inherit;
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}
	.btn-ghost:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.btn-ghost .material-symbols { font-size: 1.05rem; }
	.btn-ghost.danger {
		color: var(--color-danger);
		border-color: color-mix(in srgb, var(--color-danger) 35%, var(--color-border));
	}
	.btn-ghost.danger:hover {
		background: var(--color-danger-light);
		color: var(--color-danger);
	}

	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}

	.card h3 {
		margin: 0 0 0.4rem 0;
	}

	.card .sub {
		color: var(--color-text-secondary);
		font-size: 0.88rem;
		margin: 0 0 var(--space-sm) 0;
	}

	.post-form {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.post-form textarea {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.6rem 0.75rem;
		font: inherit;
		color: inherit;
		resize: vertical;
	}

	.post-form .btn-primary {
		align-self: flex-end;
	}

	.feed {
		display: flex;
		flex-direction: column;
		gap: 0.8rem;
	}

	.post {
		border-top: 1px solid var(--color-border);
		padding-top: 0.8rem;
	}

	.post:first-child {
		border-top: none;
		padding-top: 0;
	}

	.post-author {
		display: flex;
		gap: 0.6rem;
		align-items: center;
		margin-bottom: 0.4rem;
	}

	.post-author div {
		display: flex;
		flex-direction: column;
	}

	.post-author .when {
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}

	.post-body {
		white-space: pre-wrap;
		line-height: 1.55;
	}

	.attendees {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(13rem, 1fr));
		gap: 0.5rem;
	}

	.attendee {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.5rem 0.7rem;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}

	.attendee.maybe {
		opacity: 0.75;
	}

	.attendee.declined {
		opacity: 0.5;
	}

	.att-info {
		display: flex;
		flex-direction: column;
		line-height: 1.2;
		flex: 1;
		min-width: 0;
	}

	.att-info .status {
		font-size: 0.75rem;
		text-transform: capitalize;
		color: var(--color-text-tertiary);
	}

	.attendance-controls {
		display: flex;
		gap: 0.25rem;
		flex-shrink: 0;
	}

	.att-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.2rem;
		width: 1.9rem;
		height: 1.9rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text-tertiary);
		cursor: pointer;
	}

	.att-btn .material-symbols {
		font-size: 1.1rem;
	}

	.att-btn-label {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	.att-btn:disabled {
		opacity: 0.5;
		cursor: default;
	}

	.att-btn.attended.active {
		background: var(--color-success-light, var(--color-bg-secondary));
		border-color: var(--color-success, var(--color-accent));
		color: var(--color-success, var(--color-accent));
	}

	.att-btn.no-show.active {
		background: var(--color-danger-light);
		border-color: var(--color-danger);
		color: var(--color-danger);
	}

	.attendance-badge {
		font-size: 0.7rem;
		font-weight: 600;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		flex-shrink: 0;
	}

	.attendance-badge.attended {
		background: var(--color-success-light, var(--color-bg-secondary));
		color: var(--color-success, var(--color-accent));
	}

	.attendance-badge.no_show {
		background: var(--color-danger-light);
		color: var(--color-danger);
	}


	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}

	.centered {
		text-align: center;
		padding: var(--space-2xl);
	}

	.muted {
		color: var(--color-text-tertiary);
	}

	.log-workout {
		margin-top: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		align-items: flex-start;
	}
	.log-workout .btn .material-symbols {
		font-size: 1.1rem;
		margin-inline-end: 0.25rem;
		vertical-align: text-bottom;
	}
	.log-workout-hint {
		font-size: 0.85rem;
		margin: 0;
	}

	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
	}
	.empty-card h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.empty-mark {
		display: block;
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-sm);
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.empty-actions {
		display: flex;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}

	.attendees-empty {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		color: var(--color-text-secondary);
	}
	.attendees-empty .material-symbols {
		font-size: 1.5rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.attendees-empty div {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.attendees-empty strong {
		color: var(--color-text);
		font-size: 0.95rem;
	}
	.attendees-empty span {
		font-size: 0.85rem;
	}

	.back-skel {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		opacity: 0.5;
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line { height: 0.75rem; }
	.skel-block {
		height: 2.4rem;
		border-radius: var(--radius-md);
	}
	.skel-w-20 { width: 20%; }
	.skel-w-30 { width: 30%; }
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	.skel-w-80 { width: 80%; }
	.skel-hero {
		grid-template-columns: 1fr minmax(14rem, 18rem);
	}
	.skel-hero-text {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		justify-content: center;
		min-width: 0;
	}
	.skel-hero-actions {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		margin-bottom: var(--space-md);
	}
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 60rem) {
		.hero {
			grid-template-columns: 1fr;
		}
		.hero-side {
			align-self: stretch;
		}
		.rsvp-tri { min-width: 0; }
		.skel-hero {
			grid-template-columns: 1fr;
		}
	}

	.results-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-sm);
	}
	.btn-primary-sm {
		padding: 0.35rem 0.75rem;
		font-size: 0.85rem;
		border-radius: var(--radius-md);
		background: var(--color-primary);
		color: white;
		border: none;
		font-weight: 600;
	}
	.btn-primary-sm:disabled { opacity: 0.6; }
	.btn-link {
		background: none;
		border: none;
		color: var(--color-primary);
		cursor: pointer;
		font-size: 0.85rem;
		padding: 0.2rem 0.4rem;
	}
	.btn-link:hover { text-decoration: underline; }
	.results {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.result {
		display: grid;
		grid-template-columns: 2rem 1.8rem 1fr auto auto;
		align-items: center;
		gap: 0.6rem;
		padding: 0.35rem 0.5rem;
		border-radius: var(--radius-md);
	}
	.result.me {
		background: var(--color-primary-light);
	}
	.result .rank {
		font-weight: 700;
		color: var(--color-primary);
		text-align: center;
		font-variant-numeric: tabular-nums;
	}
	.res-info {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		min-width: 0;
	}
	.res-info strong {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.you {
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}
	.dnf-tag {
		background: var(--color-danger-light);
		color: var(--color-danger);
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.1rem 0.35rem;
		border-radius: var(--radius-sm);
		letter-spacing: 0.04em;
	}
	.time {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.dist {
		font-size: 0.8rem;
	}
	.picker {
		margin-top: var(--space-lg);
		padding-top: var(--space-md);
		border-top: 1px solid var(--color-border);
	}
	.run-options {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.run-option {
		display: grid;
		grid-template-columns: 1fr auto auto auto;
		gap: 0.6rem;
		align-items: center;
		width: 100%;
		padding: 0.5rem 0.6rem;
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		cursor: pointer;
		font-size: 0.85rem;
		text-align: start;
	}
	.run-option:hover { border-color: var(--color-primary); }
	.picker-actions {
		display: flex;
		gap: 0.4rem;
		margin-top: var(--space-md);
	}
	.results-actions {
		display: flex;
		align-items: center;
		gap: var(--space-md);
	}
	.import-help {
		font-size: 0.85rem;
		margin: 0 0 var(--space-sm);
	}
	.import-file {
		display: inline-block;
	}
	.import-errors {
		margin: var(--space-sm) 0 0;
		padding-inline-start: 1.1rem;
		color: var(--color-danger);
		font-size: 0.85rem;
	}
	.import-summary {
		margin: var(--space-sm) 0 0;
		font-size: 0.9rem;
		font-weight: 600;
	}
	.claim-pending {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		font-style: italic;
	}
	.claims-queue {
		margin-top: var(--space-lg);
		padding-top: var(--space-md);
		border-top: 1px solid var(--color-border);
	}
	.claims-help {
		font-size: 0.85rem;
		margin: 0 0 var(--space-sm);
	}
	.claims-queue ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.claims-queue li {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.claim-desc {
		flex: 1;
		font-size: 0.9rem;
	}
	.race-panel {
		border: 1.5px solid var(--color-primary);
	}
	.race-banner {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
	}
	.race-state {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin: 0.3rem 0;
	}
	.race-state.armed { color: var(--color-primary); }
	.race-state.running { color: #2e7d32; }
	.dot {
		width: 0.6rem;
		height: 0.6rem;
		border-radius: 50%;
		display: inline-block;
	}
	.armed-dot { background: var(--color-primary); }
	.running-dot {
		background: #2e7d32;
		animation: pulse 1s infinite;
	}
	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.4; }
	}
	.race-actions {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin-top: var(--space-sm);
	}
	.btn-primary-sm.big {
		font-size: 1.4rem;
		padding: 0.6rem 2rem;
		letter-spacing: 0.1em;
	}
	.auto-approve {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.85rem;
		margin: 0.4rem 0 0.6rem;
	}
	.result.pending { opacity: 0.7; }
	.result.pending .rank { color: var(--color-text-tertiary); }
	.pending-tag {
		background: #fff3cd;
		color: #856404;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.1rem 0.35rem;
		border-radius: var(--radius-sm);
		letter-spacing: 0.04em;
	}
	.btn-link.approve { color: #2e7d32; }
	.btn-link.reject { color: var(--color-danger); }

	.photo-add {
		cursor: pointer;
	}
	.photo-gallery {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(8rem, 1fr));
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}
	.photo-tile {
		margin: 0;
		border-radius: var(--radius-md);
		overflow: hidden;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
	}
	.photo-tile img {
		width: 100%;
		aspect-ratio: 1 / 1;
		object-fit: cover;
		display: block;
	}
	.photo-tile figcaption {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
		padding: 0.3rem 0.45rem;
		font-size: 0.72rem;
	}
	.photo-tile .cap {
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.photo-tile .by {
		color: var(--color-text-tertiary);
	}
</style>
