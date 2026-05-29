<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { afterNavigate, goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import type { RealtimeChannel } from '@supabase/supabase-js';
	import {
		fetchEventById,
		fetchClubBySlug,
		fetchEventAttendees,
		fetchClubPosts,
		fetchRouteById,
		rsvpEvent,
		clearRsvp,
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
		fetchEventExceptions,
		cancelEventInstance,
		reinstateEventInstance,
		fetchEventPhotos,
		addRunPhoto,
		fetchEventMeetPoint,
		type EventResultWithUser,
		type RecentRunOption,
		type RaceSessionRow,
		type EventException,
		type EventPhoto
	} from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { expandInstances, describeRecurrence } from '$lib/recurrence';
	import { formatDistance, getUnit } from '$lib/units.svelte';
	import { env } from '$env/dynamic/public';
	import { buildStaticMarkerMapUrl, mapsDirectionsUrl } from '$lib/static_map';
	import { buildFinisherCertificateSvg, CERT_WIDTH, CERT_HEIGHT } from '$lib/finisher_certificate';
	import { rasterizeSvgToPng, downloadBlob } from '$lib/svg_raster';
	import type {
		EventWithMeta,
		ClubWithMeta,
		EventAttendee,
		ClubPostWithAuthor,
		Route,
		RsvpStatus
	} from '$lib/types';

	let slug = $derived($page.params.slug as string);
	let eventId = $derived($page.params.id as string);

	let club = $state<ClubWithMeta | null>(null);
	let event = $state<EventWithMeta | null>(null);
	// Meetup coordinates, members-only via the get_event_meet_point RPC
	// (the raw columns are revoked from clients). Persona social-group #10.
	let meetPoint = $state<{ lat: number; lng: number } | null>(null);
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
	let exceptions = $state<EventException[]>([]);
	let showCancelInstance = $state(false);
	let cancelReason = $state('');

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
	}

	// #49: the viewer can contribute to the event gallery when they have
	// a finisher result here (their own result row carries run_id; the
	// redaction view nulls it for everyone else). The photo attaches to
	// that run and is tagged with the event so it shows in the gallery.
	let myEventRunId = $derived(
		results.find((r) => r.user_id === myUserId && r.run_id)?.run_id ?? null
	);

	async function handleAddEventPhoto(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file || !event || !myEventRunId || photoUploading) return;
		photoUploading = true;
		try {
			await addRunPhoto({
				run_id: myEventRunId,
				file,
				event_id: event.id,
				event_instance_start: activeInstance
			});
			eventPhotos = await fetchEventPhotos(event.id, activeInstance!);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Photo upload failed';
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
			error = e instanceof Error ? e.message : 'Arm failed';
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
			error = e instanceof Error ? e.message : 'Start failed';
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
			error = e instanceof Error ? e.message : 'End failed';
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
			error = e instanceof Error ? e.message : 'Approval failed';
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
			error = e instanceof Error ? e.message : 'Submit failed';
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
			error = e instanceof Error ? e.message : 'Result submit failed';
		} finally {
			submitting = false;
		}
	}

	async function removeMyResult() {
		if (!event || !activeInstance) return;
		await removeEventResult(event.id, activeInstance);
		await reloadInstance();
	}

	function formatDuration(s: number): string {
		if (s <= 0) return '—';
		const h = Math.floor(s / 3600);
		const m = Math.floor((s % 3600) / 60);
		const sec = s % 60;
		if (h > 0) {
			return `${h}:${m.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
		}
		return `${m}:${sec.toString().padStart(2, '0')}`;
	}

	/// #44: build + download a finisher certificate PNG for a result row.
	/// Client-rendered SVG → PNG (no server PDF service). Available on any
	/// finished + approved result — finisher data is already public on the
	/// leaderboard, and a certificate is celebratory, not sensitive.
	let certBusy = $state<string | null>(null);
	async function downloadCertificate(r: EventResultWithUser) {
		if (!event || certBusy) return;
		certBusy = rowKey(r);
		try {
			const svg = buildFinisherCertificateSvg({
				eventTitle: event.title,
				finisherName: r.display_name ?? 'Runner',
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
		} finally {
			certBusy = null;
		}
	}

	function formatRunDate(iso: string): string {
		return new Date(iso).toLocaleDateString(undefined, {
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
		// Wait for auth.user before loading. The event page derives
		// `isAdmin` from `club.viewer_role` which is fetched against
		// the caller's identity; if `auth.user` hasn't resolved when
		// load() fires, viewer_role can come back null even for the
		// real owner, which collapses every admin affordance.
		// Same shape we patch on every authed page.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
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
			error = e instanceof Error ? e.message : 'RSVP failed';
		} finally {
			busy = false;
		}
	}

	function handleDeleteEvent() {
		if (!event) return;
		showDeleteEventConfirm = true;
	}

	async function confirmDeleteEvent() {
		if (!event) return;
		showDeleteEventConfirm = false;
		await deleteEvent(event.id);
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
			error = e instanceof Error ? e.message : 'Could not cancel this occurrence';
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
			error = e instanceof Error ? e.message : 'Could not reinstate this occurrence';
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
			error = e instanceof Error ? e.message : 'Failed to post update';
		} finally {
			busy = false;
		}
	}

	function fmtDate(iso: string): string {
		const d = new Date(iso);
		return d.toLocaleString(undefined, {
			weekday: 'long',
			month: 'long',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}

	function fmtPace(sec: number | null): string {
		if (!sec) return '';
		const m = Math.floor(sec / 60);
		const s = sec % 60;
		return `${m}:${String(s).padStart(2, '0')} /km`;
	}

	function fmtRelative(iso: string): string {
		const diff = Date.now() - new Date(iso).getTime();
		const min = Math.floor(diff / 60_000);
		if (min < 1) return 'Just now';
		if (min < 60) return `${min}m ago`;
		const hr = Math.floor(min / 60);
		if (hr < 24) return `${hr}h ago`;
		return `${Math.floor(hr / 24)}d ago`;
	}

	function initial(name: string | null | undefined): string {
		return (name?.trim()?.[0] ?? '?').toUpperCase();
	}

	function hashHue(id: string): number {
		let h = 0;
		for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
		return Math.abs(h) % 360;
	}
</script>

{#if loading}
	<div class="page" aria-busy="true" aria-label="Loading event">
		<span class="back-skel" aria-hidden="true">
			<span class="material-symbols">arrow_back</span>
			Back to club
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
	<p class="sr-only" role="status">Loading event…</p>
{:else if !event || !club}
	<div class="page">
		<a class="back" href="/clubs/{slug}">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			Back to clubs
		</a>
		<div class="empty-card">
			<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
			<h3>Event not found</h3>
			<p class="empty-text">
				This event may have been cancelled, or the club is private and you
				don't have access.
			</p>
			<div class="empty-actions">
				<a href="/clubs/{slug}" class="btn btn-primary">Back to club</a>
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
			Back to {club.name}
		</a>

		<header class="hero" class:past={isPast}>
			<div class="hero-body">
				<span class="hero-eyebrow">
					{#if event.recurrence_freq}
						{recurrenceLabel}
					{:else if isPast}
						Past event
					{:else}
						Upcoming event
					{/if}
				</span>
				<h1>{event.title}</h1>
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
					{#if event.distance_m != null}
						<div class="metric">
							<span class="label">Distance</span>
							<span class="value">{formatDistance(event.distance_m)}</span>
						</div>
					{/if}
					{#if event.pace_target_sec}
						<div class="metric">
							<span class="label">Target pace</span>
							<span class="value">{fmtPace(event.pace_target_sec)}</span>
						</div>
					{/if}
					<div class="metric">
						<span class="label">Going</span>
						<span class="value">
							{event.attendee_count}{event.capacity ? ` / ${event.capacity}` : ''}
						</span>
						{#if rsvpCounts.waitlisted > 0}
							<span class="waitlist-note">Full · {rsvpCounts.waitlisted} on waitlist</span>
						{/if}
					</div>
				</div>

				{#if route}
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
								href={mapsDirectionsUrl(meetPoint.lat, meetPoint.lng)}
								target="_blank"
								rel="noopener noreferrer"
								aria-label="Open the meeting point in maps"
							>
								<img src={meetMapUrl} alt="Map of the meeting point" loading="lazy" />
							</a>
						{/if}
						<a
							class="btn btn-secondary meet-directions"
							href={mapsDirectionsUrl(meetPoint.lat, meetPoint.lng)}
							target="_blank"
							rel="noopener noreferrer"
						>
							<span class="material-symbols" aria-hidden="true">directions</span>
							Get directions{event.meet_label ? ` to ${event.meet_label}` : ''}
						</a>
					</div>
				{/if}
			</div>
			<div class="hero-side">
				{#if activeException}
					<div class="cancelled-banner" role="status">
						<span class="material-symbols" aria-hidden="true">event_busy</span>
						<div>
							<strong>This occurrence was cancelled.</strong>
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
							Reinstate this occurrence
						</button>
					{/if}
				{:else if !isPast && auth.user}
					<div
						class="rsvp-tri"
						role="group"
						aria-label="Your RSVP"
					>
						<button
							type="button"
							class="rsvp-opt rsvp-going"
							class:active={viewerRsvpForActive === 'going' || viewerRsvpForActive === 'waitlisted'}
							aria-pressed={viewerRsvpForActive === 'going' || viewerRsvpForActive === 'waitlisted'}
							aria-label={viewerRsvpForActive === 'going'
								? 'Going'
								: viewerRsvpForActive === 'waitlisted'
									? 'Waitlisted'
									: "I'm in"}
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
									? 'Going'
									: viewerRsvpForActive === 'waitlisted'
										? 'Waitlisted'
										: "I'm in"}
							</span>
							<span class="rsvp-count" aria-hidden="true">{rsvpCounts.going}</span>
						</button>
						<button
							type="button"
							class="rsvp-opt rsvp-maybe"
							class:active={viewerRsvpForActive === 'maybe'}
							aria-pressed={viewerRsvpForActive === 'maybe'}
							aria-label="Maybe"
							onclick={() => rsvp('maybe')}
							disabled={busy}
						>
							<span class="material-symbols" aria-hidden="true">help_outline</span>
							<span class="rsvp-label">Maybe</span>
							<span class="rsvp-count" aria-hidden="true">{rsvpCounts.maybe}</span>
						</button>
						<button
							type="button"
							class="rsvp-opt rsvp-declined"
							class:active={viewerRsvpForActive === 'declined'}
							aria-pressed={viewerRsvpForActive === 'declined'}
							aria-label="Can't make it"
							onclick={() => rsvp('declined')}
							disabled={busy}
						>
							<span class="material-symbols" aria-hidden="true">close</span>
							<span class="rsvp-label">Can't make it</span>
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
							Cancel this occurrence
						</button>
					</div>
				{/if}
				{#if isAdmin}
					<div class="admin-actions">
						<button
							type="button"
							class="btn-ghost danger"
							onclick={handleDeleteEvent}
							aria-label="Delete event"
						>
							<span class="material-symbols" aria-hidden="true">delete</span>
							Delete event
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
				<span class="label">Pick an occurrence</span>
				<div class="instance-chips">
					{#each visibleInstances as iso}
						<button
							class="instance-chip"
							class:active={activeInstance === iso.toISOString()}
							onclick={() => pickInstance(iso.toISOString())}
						>
							{iso.toLocaleDateString(undefined, {
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
							? 'Show fewer'
							: `Show all ${liveInstances.length} upcoming`}
					</button>
				{/if}
			</section>
		{/if}

		{#if isMember}
			<section class="card">
				<h3>Post an update</h3>
				<p class="sub">Members will see this on the club feed, tagged to this event.</p>
				<form class="post-form" onsubmit={submitPost}>
					<textarea
						bind:value={draftPost}
						placeholder="Running late? Weather call? Meeting at a different spot? Say it here."
						rows="3"
						maxlength="1200"
					></textarea>
					<button class="btn-primary" type="submit" disabled={!draftPost.trim() || busy}>
						Post update
					</button>
				</form>
			</section>
		{/if}

		{#if eventPosts.length > 0}
			<section class="card">
				<h3>Updates</h3>
				<div class="feed">
					{#each eventPosts as p (p.id)}
						<article class="post">
							<div class="post-author">
								<div class="avatar-sm" style="--seed: {hashHue(p.author_id)}">
									{initial(p.author_display_name)}
								</div>
								<div>
									<strong>{p.author_display_name ?? 'Member'}</strong>
									<span class="when">{fmtRelative(p.created_at ?? new Date().toISOString())}</span>
								</div>
							</div>
							<p class="post-body">{p.body}</p>
						</article>
					{/each}
				</div>
			</section>
		{/if}

		{#if isRaceDirector}
			<section class="card race-panel">
				<div class="results-head">
					<h3>Race control</h3>
					<a class="btn-link" href={`/live/event/${event.id}/${encodeURIComponent(activeInstance ?? '')}`} target="_blank" rel="noopener">
						Spectator view ↗
					</a>
				</div>
				{#if !raceSession || raceSession.status === 'finished' || raceSession.status === 'cancelled'}
					<p class="muted">
						{raceSession?.status === 'finished'
							? 'This race is finished. Arm a new session to start another run.'
							: raceSession?.status === 'cancelled'
							? 'Previous race cancelled.'
							: 'Arm the race when everyone is ready to go — attendees see an armed screen on their watch and phone.'}
					</p>
					<label class="auto-approve">
						<input type="checkbox" bind:checked={autoApproveOnArm} />
						<span>Auto-approve submitted results</span>
					</label>
					<button type="button" class="btn btn-primary-sm" onclick={handleArm} disabled={raceBusy}>
						Arm race
					</button>
				{:else if raceSession.status === 'armed'}
					<p class="race-state armed">
						<span class="dot armed-dot"></span>
						<strong>Armed</strong> — attendees are waiting for your Start.
					</p>
					<div class="race-actions">
						<button type="button" class="btn btn-primary-sm big" onclick={handleStart} disabled={raceBusy}>
							GO
						</button>
						<button type="button" class="btn-link" onclick={() => handleEnd('cancelled')} disabled={raceBusy}>
							Cancel
						</button>
					</div>
				{:else if raceSession.status === 'running'}
					<p class="race-state running">
						<span class="dot running-dot"></span>
						<strong>Running</strong> — elapsed {formatDuration(raceElapsedS)}
					</p>
					<div class="race-actions">
						<button type="button" class="btn btn-danger" onclick={() => handleEnd('finished')} disabled={raceBusy}>
							End race
						</button>
					</div>
				{/if}
			</section>
		{:else if raceSession && (raceSession.status === 'armed' || raceSession.status === 'running')}
			<section class="card race-banner">
				{#if raceSession.status === 'armed'}
					<p><span class="dot armed-dot"></span><strong>Race armed</strong> — the organiser will start shortly. Your watch / phone will begin recording automatically.</p>
				{:else}
					<p><span class="dot running-dot"></span><strong>Race running</strong> — {formatDuration(raceElapsedS)} elapsed. Keep moving!</p>
				{/if}
			</section>
		{/if}

		<section class="card">
			<div class="results-head">
				<h3>Results ({results.length})</h3>
				{#if myUserId}
					{#if hasMyResult}
						<button type="button" class="btn-link" onclick={removeMyResult}>Remove mine</button>
					{:else}
						<button type="button" class="btn btn-primary-sm" onclick={openResultPicker} disabled={submitting}>
							{submitting ? 'Submitting…' : 'Submit my time'}
						</button>
					{/if}
				{/if}
			</div>
			{#if results.length === 0}
				<p class="muted">No results yet. Submit your time after the event and others will see it here.</p>
			{:else}
				<ol class="results">
					{#each results as r (rowKey(r))}
						<li class="result" class:me={r.user_id !== null && r.user_id === myUserId} class:pending={!r.organiser_approved}>
							<span class="rank">{r.organiser_approved ? (r.rank ?? '—') : '…'}</span>
							<div class="avatar-sm" style="--seed: {hashHue(rowKey(r))}">
								{initial(r.display_name)}
							</div>
							<div class="res-info">
								<strong>{r.display_name ?? 'Runner'}</strong>
								{#if r.user_id !== null && r.user_id === myUserId}<span class="you">(you)</span>{/if}
								{#if !r.organiser_approved}<span class="pending-tag">PENDING</span>{/if}
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
									title="Download finisher certificate"
									disabled={certBusy === rowKey(r)}
									onclick={() => downloadCertificate(r)}
								>
									{certBusy === rowKey(r) ? '…' : 'Certificate'}
								</button>
							{/if}
							{#if isRaceDirector && r.user_id !== null && !r.organiser_approved}
								<button type="button" class="btn-link approve" onclick={() => handleApprove(r.user_id!, true)}>Approve</button>
							{:else if isRaceDirector && r.user_id !== null && r.organiser_approved && r.user_id !== myUserId}
								<button type="button" class="btn-link reject" onclick={() => handleApprove(r.user_id!, false)}>Unverify</button>
							{/if}
						</li>
					{/each}
				</ol>
			{/if}

			{#if showResultPicker}
				<div class="picker">
					<h4>Attach a run</h4>
					{#if runOptions.length === 0}
						<p class="muted">No recent runs found. Record a run first.</p>
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
						<button type="button" class="btn-link" onclick={() => recordNonFinish('dnf')} disabled={submitting}>Record DNF</button>
						<button type="button" class="btn-link" onclick={() => recordNonFinish('dns')} disabled={submitting}>Record DNS</button>
						<button type="button" class="btn-link" onclick={() => (showResultPicker = false)}>Cancel</button>
					</div>
				</div>
			{/if}
		</section>

		<section class="card">
			<div class="results-head">
				<h3>Photos ({eventPhotos.length})</h3>
				{#if myEventRunId}
					<label class="btn-link photo-add">
						{photoUploading ? 'Uploading…' : 'Add photo'}
						<input
							type="file"
							accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
							onchange={handleAddEventPhoto}
							disabled={photoUploading}
							hidden
						/>
					</label>
				{/if}
			</div>
			{#if eventPhotos.length === 0}
				<p class="muted">
					No photos yet.{myEventRunId ? ' Add one from your run at this event.' : ''}
				</p>
			{:else}
				<div class="photo-gallery">
					{#each eventPhotos as p (p.id)}
						<figure class="photo-tile">
							<img src={p.thumbUrl ?? p.url} alt={p.caption ?? 'Event photo'} loading="lazy" />
							<figcaption>
								{#if p.caption}<span class="cap">{p.caption}</span>{/if}
								<span class="by">{p.uploader_name ?? 'Runner'}</span>
							</figcaption>
						</figure>
					{/each}
				</div>
			{/if}
		</section>

		<section class="card">
			<h3>Attendees ({attendees.length})</h3>
			{#if attendees.length === 0}
				<div class="attendees-empty">
					<span class="material-symbols" aria-hidden="true">group_add</span>
					<div>
						<strong>No RSVPs yet</strong>
						<span class="muted">
							{#if !isPast && isMember}
								Be the first to lock in your spot above.
							{:else if !isPast}
								Join the club to RSVP.
							{:else}
								No-one logged an RSVP for this event.
							{/if}
						</span>
					</div>
				</div>
			{:else}
				<div class="attendees">
					{#each attendees as a (a.user_id)}
						<div class="attendee" class:maybe={a.status === 'maybe'} class:declined={a.status === 'declined'}>
							<div class="avatar-sm" style="--seed: {hashHue(a.user_id)}">
								{initial(a.display_name)}
							</div>
							<div class="att-info">
								<strong>{a.display_name ?? 'Member'}</strong>
								<span class="status">{a.status}</span>
							</div>
						</div>
					{/each}
				</div>
			{/if}
		</section>
	</div>

<ConfirmDialog
	open={showEndRaceConfirm !== null}
	title={showEndRaceConfirm === 'cancelled' ? 'Cancel race' : 'End race'}
	message={showEndRaceConfirm === 'cancelled' ? 'Cancel the race?' : 'End the race?'}
	confirmLabel={showEndRaceConfirm === 'cancelled' ? 'Cancel race' : 'End race'}
	onconfirm={confirmEndRace}
	oncancel={() => showEndRaceConfirm = null}
	danger
/>

<ConfirmDialog
	open={showDeleteEventConfirm}
	title="Delete event"
	message={`Delete "${event?.title ?? ''}"?${event?.recurrence_freq ? ' All occurrences will be removed.' : ''}`}
	confirmLabel="Delete"
	onconfirm={confirmDeleteEvent}
	oncancel={() => showDeleteEventConfirm = false}
	danger
/>

<Modal
	open={showCancelInstance}
	title="Cancel this occurrence"
	onclose={() => (showCancelInstance = false)}
>
	<div class="cancel-instance-form">
		<p>
			Only this occurrence is called off — the rest of the series is unaffected.
			Everyone who RSVP'd to it (going, maybe, or waitlisted) is notified.
		</p>
		<label>
			<span>Reason (optional)</span>
			<textarea
				bind:value={cancelReason}
				rows="2"
				maxlength="300"
				placeholder="Course flooded, public holiday, marshal shortage…"
			></textarea>
		</label>
		<div class="cancel-instance-actions">
			<button
				type="button"
				class="btn btn-secondary"
				onclick={() => (showCancelInstance = false)}
				disabled={busy}
			>
				Keep it
			</button>
			<button
				type="button"
				class="btn btn-danger"
				onclick={confirmCancelInstance}
				disabled={busy}
			>
				{busy ? 'Cancelling…' : 'Cancel occurrence'}
			</button>
		</div>
	</div>
</Modal>
{/if}

<style>
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
		text-align: left;
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
		color: color-mix(in srgb, var(--color-warning) 85%, var(--color-text));
	}
	.rsvp-maybe.active .material-symbols,
	.rsvp-maybe.active .rsvp-count {
		color: color-mix(in srgb, var(--color-warning) 85%, var(--color-text));
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
	}

	.att-info .status {
		font-size: 0.75rem;
		text-transform: capitalize;
		color: var(--color-text-tertiary);
	}

	.avatar-sm {
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		background: hsl(var(--seed, 260), 50%, 55%);
		color: white;
		display: flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 0.85rem;
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
		text-align: left;
	}
	.run-option:hover { border-color: var(--color-primary); }
	.picker-actions {
		display: flex;
		gap: 0.4rem;
		margin-top: var(--space-md);
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
