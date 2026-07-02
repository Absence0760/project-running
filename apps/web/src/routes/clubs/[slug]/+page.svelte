<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { m as tr } from '$lib/i18n/store.svelte';
	import { onMount, onDestroy } from 'svelte';
	import { handleTablistKeydown } from '$lib/util/tablist';
	import Avatar from '$lib/components/Avatar.svelte';
	import { hashHue } from '$lib/format/avatar';
	import { page } from '$app/stores';
	import { goto, afterNavigate } from '$app/navigation';
	import { supabase } from '$lib/core/supabase';
	import type { RealtimeChannel } from '@supabase/supabase-js';
	import {
		fetchClubBySlug,
		fetchUpcomingEvents,
		fetchPastEvents,
		fetchClubMembers,
		fetchClubPosts,
		fetchPostReplies,
		fetchPendingRequests,
		fetchClubRoutes,
		fetchRoutes,
		setRouteClubId,
		fetchClubTemplates,
		setPlanIsTemplate,
		fetchClubSessionTemplates,
		cloneSessionTemplate,
		fetchClubGymRoutineTemplates,
		cloneGymRoutineTemplate,
		approveMember,
		bulkApproveMembers,
		rejectMember,
		removeMember,
		setMemberRole,
		regenerateInviteToken,
		joinClub,
		leaveClub,
		createClubPost,
		deleteClubPost,
		deleteClub
	} from '$lib/core/data';
	import { formatDistance } from '$lib/core/mock-data';
	import { auth } from '$lib/stores/auth.svelte';
	import RouteTrackPreview from '$lib/components/RouteTrackPreview.svelte';
	import type { GymRoutineSummary } from '$lib/core/data';
	import type { Route, TrainingPlan, SessionPlan } from '$lib/types';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import EventEditor from '$lib/components/EventEditor.svelte';
	import ClubEditor from '$lib/components/ClubEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ReportDialog from '$lib/components/ReportDialog.svelte';
	import VerifiedBadge from '$lib/components/VerifiedBadge.svelte';
	import ClubPhotos from '$lib/components/ClubPhotos.svelte';
	import type {
		ClubWithMeta,
		EventWithMeta,
		ClubPostWithAuthor,
		ClubMember
	} from '$lib/types';

	let slug = $derived($page.params.slug as string);
	let club = $state<ClubWithMeta | null>(null);
	let upcoming = $state<EventWithMeta[]>([]);
	let past = $state<EventWithMeta[]>([]);
	let posts = $state<ClubPostWithAuthor[]>([]);
	let members = $state<(ClubMember & { display_name: string | null; avatar_url: string | null })[]>([]);
	let pending = $state<(ClubMember & { display_name: string | null; avatar_url: string | null })[]>([]);
	let loading = $state(true);
	type Tab = 'feed' | 'events' | 'routes' | 'templates' | 'photos' | 'members';
	const TABS: readonly Tab[] = ['feed', 'events', 'routes', 'templates', 'photos', 'members'];
	let tab = $state<Tab>('feed');
	let showEventModal = $state(false);

	function setTab(next: Tab) {
		tab = next;
		const path = next === 'feed' ? `/clubs/${slug}` : `/clubs/${slug}?tab=${next}`;
		goto(path, { replaceState: true, noScroll: true, keepFocus: true });
	}

	/// Back-link wiring: if the user landed here from /clubs, fire
	/// history.back so /clubs's snapshot.restore (My-clubs list +
	/// scroll position) kicks in. Falling through to <a href="/clubs">
	/// would soft-nav forward, dropping the captured list. Same shape
	/// as /runs/[id] → /runs, /plans/[id] → /plans.
	let cameFromClubs = $state(false);
	afterNavigate(({ from }) => {
		if (from?.url.pathname === '/clubs' && !cameFromClubs) {
			cameFromClubs = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromClubs) {
			e.preventDefault();
			history.back();
		}
	}
	let clubRoutes = $state<Route[]>([]);
	let transferableRoutes = $state<Route[]>([]);
	let showTransferModal = $state(false);
	let showEditModal = $state(false);
	let transferRouteId = $state('');
	let clubTemplates = $state<TrainingPlan[]>([]);
	let sessionTemplates = $state<SessionPlan[]>([]);
	let adoptingSession = $state('');
	let gymRoutineTemplates = $state<GymRoutineSummary[]>([]);
	let adoptingRoutine = $state('');
	const templatesCount = $derived(
		clubTemplates.length + sessionTemplates.length + gymRoutineTemplates.length
	);

	async function handleEventCreated(event: { id: string }) {
		showEventModal = false;
		// Refresh the events lists so the new one shows up immediately;
		// admins typically stay on the club page after creating.
		await load();
		showToast(tr('clubHome.toastEventCreated'));
	}

	let draftPost = $state('');
	let postingBusy = $state(false);
	let joinBusy = $state(false);
	// Activity-risk acknowledgement (persona #45) — only gates the join button
	// for clubs that require it.
	let waiverAck = $state(false);
	let error = $state<string | null>(null);
	let showLeaveConfirm = $state(false);
	let showReportDialog = $state(false);
	let reportPostId = $state<string | null>(null);
	let showRegenConfirm = $state(false);
	let showDeleteClubConfirm = $state(false);
	let showDeletePostConfirm = $state<string | null>(null);
	let showRemoveRouteId = $state<string | null>(null);
	/** When non-null, the user_id of the member the admin is about to
	 *  remove. Drives the kick ConfirmDialog. */
	let removingMemberId = $state<string | null>(null);
	/** When non-null, the user_id of the pending join request the admin is
	 *  about to reject. Drives the reject ConfirmDialog. */
	let rejectingMemberId = $state<string | null>(null);

	/** Thread state. Key is parent post id. */
	let expandedThreads = $state<Record<string, ClubPostWithAuthor[] | null>>({});
	let replyDrafts = $state<Record<string, string>>({});
	let replyBusyId = $state<string | null>(null);

	let isAdmin = $derived(
		club?.viewer_role === 'owner' || club?.viewer_role === 'admin'
	);
	// event_organiser is a delegated role that can manage events without full
	// admin rights — the DB RLS (is_event_organiser) already permits it.
	let canManageEvents = $derived(isAdmin || club?.viewer_role === 'event_organiser');
	let isMember = $derived(club?.viewer_role != null);

	async function load() {
		loading = true;
		club = await fetchClubBySlug(slug);
		if (!club) {
			loading = false;
			return;
		}
		const [up, pa, po, me, pe, rt, tp, st, gr] = await Promise.all([
			fetchUpcomingEvents(club.id),
			fetchPastEvents(club.id, 6),
			fetchClubPosts(club.id, 20),
			fetchClubMembers(club.id),
			club.viewer_role === 'owner' || club.viewer_role === 'admin'
				? fetchPendingRequests(club.id)
				: Promise.resolve([]),
			fetchClubRoutes(club.id),
			fetchClubTemplates(club.id),
			fetchClubSessionTemplates(club.id),
			fetchClubGymRoutineTemplates(club.id)
		]);
		upcoming = up;
		past = pa;
		posts = po;
		members = me;
		pending = pe;
		clubRoutes = rt;
		clubTemplates = tp;
		sessionTemplates = st;
		gymRoutineTemplates = gr;
		loading = false;
	}

	async function adoptGymRoutineTemplate(templateId: string) {
		if (adoptingRoutine) return;
		adoptingRoutine = templateId;
		try {
			const newId = await cloneGymRoutineTemplate(templateId);
			showToast(tr('clubHome.gymRoutineAdopted'));
			goto(`/gym/routines/${newId}`);
		} catch (e) {
			showToast(
				tr('clubHome.toastFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
		} finally {
			adoptingRoutine = '';
		}
	}

	async function adoptSessionTemplate(templateId: string) {
		if (adoptingSession) return;
		adoptingSession = templateId;
		try {
			await cloneSessionTemplate(templateId);
			showToast(tr('clubHome.sessionAdopted'));
		} catch (e) {
			showToast(
				tr('clubHome.toastFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
		} finally {
			adoptingSession = '';
		}
	}

	async function unmakeTemplate(planId: string) {
		try {
			await setPlanIsTemplate(planId, false, null);
			showToast(tr('clubHome.toastTemplateRemoved'));
			await load();
		} catch (e) {
			showToast(tr('clubHome.toastFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	async function openTransferModal() {
		const mine = await fetchRoutes();
		// Only routes that don't already belong to a club are transferable.
		transferableRoutes = mine.filter((r) => r.club_id == null);
		transferRouteId = '';
		showTransferModal = true;
	}

	async function confirmTransfer() {
		if (!transferRouteId || !club) return;
		try {
			await setRouteClubId(transferRouteId, club.id);
			showTransferModal = false;
			showToast(tr('clubHome.toastRouteTransferred'));
			await load();
		} catch (e) {
			showToast(tr('clubHome.toastRouteTransferFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	async function confirmRemoveRoute() {
		const id = showRemoveRouteId;
		showRemoveRouteId = null;
		if (id) await removeRouteFromClub(id);
	}

	async function removeRouteFromClub(routeId: string) {
		try {
			await setRouteClubId(routeId, null);
			showToast(tr('clubHome.toastRouteReturned'));
			await load();
		} catch (e) {
			showToast(tr('clubHome.toastRouteRemoveFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	let channel: RealtimeChannel | null = null;
	// Same shape as /clubs/[slug]/events/[id] — expose Realtime
	// SUBSCRIBED status so e2e can wait deterministically before
	// firing a service-role INSERT against the channel's filters.
	let realtimeReady = $state(false);

	onMount(async () => {
		const initial = $page.url.searchParams.get('tab');
		if (initial && (TABS as readonly string[]).includes(initial)) {
			tab = initial as Tab;
		}

		// fetchClubBySlug uses supabase.auth.getSession() to populate
		// `viewer_role`, which `isMember` / `isAdmin` derive from. A hard
		// reload during the auth race would resolve the club row without
		// a viewer_role, hiding the post composer + admin affordances
		// indefinitely (no reactive re-fetch when auth lifts later).
		await auth.ready();
		await load();
		// Guard each side-effect: if subscribeRealtime throws (the
		// `.on('postgres_changes', ...) after subscribe()` bug that
		// bites when Supabase's RealtimeClient returns a cached
		// already-subscribed channel from a prior page lifecycle),
		// the poll fallback must still start — otherwise dropped
		// realtime events strand the page on stale data.
		try {
			subscribeRealtime();
		} catch (e) {
			console.warn('subscribeRealtime failed; falling back to poll', e);
		}
		startPostsColdStartPoll();
	});

	onDestroy(() => {
		if (pingRetryTimer) {
			clearTimeout(pingRetryTimer);
			pingRetryTimer = null;
		}
		if (postsColdStartPoll) {
			clearInterval(postsColdStartPoll);
			postsColdStartPoll = null;
		}
		if (channel) {
			supabase.removeChannel(channel);
			channel = null;
		}
		realtimeReady = false;
	});

	/**
	 * Cold-start safety net: even with the broadcast-echo readiness
	 * signal + the 5 s fallback (above), the postgres_changes
	 * INSERT event from a fresh subscriber can land in the join-ack
	 * filter-wiring window and never fire. Without an extra prod
	 * the page never picks up the new row.
	 *
	 * Serialized poll — one in-flight at a time, even if the
	 * interval fires while a fetch is mid-flight. Without the
	 * `inFlight` gate, a slow fetch finishing AFTER a faster one
	 * can overwrite `posts` with a stale snapshot
	 * (out-of-order assignment race).
	 *
	 * 1.5 s interval, 30 s window. By 30 s the cold-start window
	 * has long passed and either realtime is wired (every
	 * subsequent INSERT fires postgres_changes correctly) or the
	 * user has interacted (every page action triggers a fresh
	 * fetch via scheduleReload anyway).
	 *
	 * Caught by `tests-e2e/cross-cutting/realtime.spec.ts:248`
	 * failing in CI run 26340415025 (post never appeared because
	 * the service-role INSERT's postgres_changes event was dropped
	 * on the freshly-subscribed channel).
	 */
	let postsColdStartPoll: ReturnType<typeof setInterval> | null = null;
	function startPostsColdStartPoll() {
		let elapsedMs = 0;
		let inFlight = false;
		const INTERVAL_MS = 1500;
		const WINDOW_MS = 30_000;
		postsColdStartPoll = setInterval(async () => {
			elapsedMs += INTERVAL_MS;
			if (!club || elapsedMs > WINDOW_MS) {
				if (postsColdStartPoll) {
					clearInterval(postsColdStartPoll);
					postsColdStartPoll = null;
				}
				return;
			}
			if (inFlight) return;
			inFlight = true;
			try {
				posts = await fetchClubPosts(club.id, 20);
			} catch {
				/* best-effort; swallow transient fetch errors */
			} finally {
				inFlight = false;
			}
		}, INTERVAL_MS);
	}

	/**
	 * Reload the feed whenever a relevant row changes server-side. We don't
	 * try to patch state in-place — RLS is the authoritative filter for
	 * "what this viewer can see", and the payload's shape differs from
	 * `ClubPostWithAuthor`/`ClubWithMeta` (no joined author, no enrichment),
	 * so a fresh fetch is both simpler and correct. Debounced to coalesce
	 * bursts (e.g. an admin pasting a multi-line post fires one INSERT).
	 */
	let debounceTimer: ReturnType<typeof setTimeout> | null = null;
	function scheduleReload() {
		if (debounceTimer) clearTimeout(debounceTimer);
		debounceTimer = setTimeout(() => {
			if (club) load();
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
		if (!club) return;
		channel = supabase
			.channel(`club-${club.id}`, {
				config: { broadcast: { self: true } }
			})
			// Self-broadcast roundtrip readiness signal — see the
			// .subscribe() callback below.
			.on('broadcast', { event: 'ready-ping' }, () => {
				if (pingRetryTimer) {
					clearTimeout(pingRetryTimer);
					pingRetryTimer = null;
				}
				realtimeReady = true;
				console.log(`[realtime] club-${club?.id} ready=true`);
			})
			.on(
				'postgres_changes',
				{ event: '*', schema: 'public', table: 'club_posts', filter: `club_id=eq.${club.id}` },
				scheduleReload
			)
			.on(
				'postgres_changes',
				{ event: '*', schema: 'public', table: 'club_members', filter: `club_id=eq.${club.id}` },
				scheduleReload
			)
			.subscribe((status) => {
				console.log(`[realtime] club-${club?.id} status=${status}`);
				if (status !== 'SUBSCRIBED') {
					realtimeReady = false;
					return;
				}
				// Self-broadcast a ping; the echo (handled above) flips
				// readiness. The roundtrip proves the channel is fully
				// wired before we let any test rely on it. Retry every
				// 1.5 s until the echo arrives — under CI load the first
				// ping is occasionally dropped, which used to strand
				// readiness for the full 20 s test timeout.
				sendReadyPing();
				schedulePingRetry();
				// Belt-and-suspenders fallback: even if every ping echo
				// is dropped (CI WS hiccup, channel cold-start filter
				// wiring still settling), flip readiness 5 s after the
				// SUBSCRIBED ack so consumers eventually proceed. By
				// that point the channel has had ample time to wire
				// up its postgres_changes subscriptions server-side —
				// the broadcast echo was a fast-path verification, not
				// a strict precondition. Caught by
				// `tests-e2e/cross-cutting/realtime.spec.ts:248` going
				// red on CI run 26339562699 (.realtime-ready never
				// appeared within the 20 s wait).
				setTimeout(() => {
					if (channel) realtimeReady = true;
				}, 5000);
			});
	}

	async function join() {
		if (!club || joinBusy) return;
		joinBusy = true;
		try {
			const status = await joinClub(club.id, club.join_policy, waiverAck);
			if (status === 'pending') {
				error = tr('clubHome.requestSent');
			}
			await load();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : tr('clubHome.failedToJoin');
		} finally {
			joinBusy = false;
		}
	}

	function leave() {
		if (!club || joinBusy) return;
		showLeaveConfirm = true;
	}

	async function confirmLeave() {
		if (!club) return;
		showLeaveConfirm = false;
		joinBusy = true;
		try {
			await leaveClub(club.id);
			await load();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : tr('clubHome.failedToLeave');
		} finally {
			joinBusy = false;
		}
	}

	let pendingBusy = $state<Set<string>>(new Set());
	async function approve(userId: string) {
		if (!club || pendingBusy.has(userId)) return;
		pendingBusy = new Set(pendingBusy).add(userId);
		try {
			await approveMember(club.id, userId);
			await load();
		} catch (e: unknown) {
			showToast(tr('clubHome.toastApproveFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			const next = new Set(pendingBusy);
			next.delete(userId);
			pendingBusy = next;
		}
	}

	let approvingAll = $state(false);
	async function approveAll() {
		if (!club || pending.length === 0 || approvingAll) return;
		approvingAll = true;
		try {
			await bulkApproveMembers(
				club.id,
				pending.map((p) => p.user_id)
			);
			await load();
			showToast(tr('clubHome.toastApprovedAll'));
		} catch (e: unknown) {
			showToast(tr('clubHome.toastApproveAllFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			approvingAll = false;
		}
	}

	async function confirmReject() {
		const userId = rejectingMemberId;
		rejectingMemberId = null;
		if (!club || !userId || pendingBusy.has(userId)) return;
		pendingBusy = new Set(pendingBusy).add(userId);
		try {
			await rejectMember(club.id, userId);
			await load();
		} catch (e: unknown) {
			showToast(tr('clubHome.toastRejectFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			const next = new Set(pendingBusy);
			next.delete(userId);
			pendingBusy = next;
		}
	}

	async function confirmRemoveMember() {
		const userId = removingMemberId;
		removingMemberId = null;
		if (!club || !userId) return;
		try {
			await removeMember(club.id, userId);
			await load();
		} catch (e) {
			showToast(tr('clubHome.toastRemoveMemberFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	async function copyInvite() {
		if (!club?.invite_token) return;
		const link = `${location.origin}/clubs/join/${club.invite_token}`;
		await navigator.clipboard.writeText(link);
		error = tr('clubHome.inviteCopied');
	}

	function regenerateInvite() {
		if (!club) return;
		showRegenConfirm = true;
	}

	async function confirmRegenerate() {
		if (!club) return;
		showRegenConfirm = false;
		try {
			const token = await regenerateInviteToken(club.id);
			club = { ...club, invite_token: token };
		} catch (e) {
			showToast(
				tr('clubHome.regenerateFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
		}
	}

	async function toggleReplies(postId: string) {
		if (expandedThreads[postId]) {
			expandedThreads = { ...expandedThreads, [postId]: null };
			return;
		}
		const replies = await fetchPostReplies(postId);
		expandedThreads = { ...expandedThreads, [postId]: replies };
	}

	async function sendReply(postId: string) {
		if (!club || replyBusyId) return;
		const body = replyDrafts[postId]?.trim();
		if (!body) return;
		replyBusyId = postId;
		try {
			await createClubPost({ club_id: club.id, body, parent_post_id: postId });
			replyDrafts = { ...replyDrafts, [postId]: '' };
			const replies = await fetchPostReplies(postId);
			expandedThreads = { ...expandedThreads, [postId]: replies };
			// Refresh reply counts on the top-level post list.
			posts = await fetchClubPosts(club.id, 20);
		} finally {
			replyBusyId = null;
		}
	}

	async function submitPost(e: Event) {
		e.preventDefault();
		if (!club || !draftPost.trim() || postingBusy) return;
		postingBusy = true;
		try {
			await createClubPost({ club_id: club.id, body: draftPost });
			draftPost = '';
			posts = await fetchClubPosts(club.id, 20);
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : tr('clubHome.failedToPost');
		} finally {
			postingBusy = false;
		}
	}

	function removePost(id: string) {
		if (!club) return;
		showDeletePostConfirm = id;
	}

	async function confirmDeletePost() {
		if (!club || !showDeletePostConfirm) return;
		const id = showDeletePostConfirm;
		showDeletePostConfirm = null;
		try {
			await deleteClubPost(id);
			posts = await fetchClubPosts(club.id, 20);
		} catch (e) {
			showToast(
				tr('clubHome.deletePostFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
		}
	}

	function handleDeleteClub() {
		if (!club) return;
		showDeleteClubConfirm = true;
	}

	async function confirmDeleteClub() {
		if (!club) return;
		showDeleteClubConfirm = false;
		try {
			await deleteClub(club.id);
		} catch (e) {
			showToast(
				tr('clubHome.deleteClubFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
			return;
		}
		goto('/clubs');
	}

	function fmtDate(iso: string | null | undefined): string {
		if (!iso) return '';
		const d = new Date(iso);
		return d.toLocaleString(activeFormatLocale(), {
			weekday: 'short',
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}

	function fmtKm(m: number | null | undefined): string {
		// Defers to the unit-aware formatter in $lib/format/units.svelte so a
		// km → mi preference flip on /settings/preferences re-renders
		// every distance string on this page. The previous local
		// implementation hardcoded " km" — the audit caught it.
		if (m == null) return '';
		return formatDistance(m);
	}

	function fmtRelative(iso: string): string {
		const diff = Date.now() - new Date(iso).getTime();
		const min = Math.floor(diff / 60_000);
		if (min < 1) return tr('clubHome.justNow');
		if (min < 60) return tr('clubHome.minutesAgo', { n: min });
		const hr = Math.floor(min / 60);
		if (hr < 24) return tr('clubHome.hoursAgo', { n: hr });
		const d = Math.floor(hr / 24);
		if (d < 7) return tr('clubHome.daysAgo', { n: d });
		return new Date(iso).toLocaleDateString();
	}


</script>

{#if loading}
	<div class="page">
		<span class="back-skel" aria-hidden="true">
			<span class="material-symbols">arrow_back</span>
			{tr('clubHome.allClubs')}
		</span>
		<div class="hero skel-hero" aria-hidden="true">
			<span class="skel skel-avatar-lg"></span>
			<div class="skel-hero-text">
				<span class="skel skel-line skel-w-40"></span>
				<span class="skel skel-line skel-w-30"></span>
				<span class="skel skel-line skel-w-80"></span>
			</div>
		</div>
		<div class="tabs-skel" aria-hidden="true">
			{#each Array(5) as _, i (i)}
				<span class="skel skel-line skel-tab"></span>
			{/each}
		</div>
		<div class="feed-skel" aria-hidden="true">
			{#each Array(3) as _, i (i)}
				<div class="skel-post">
					<div class="skel-post-head">
						<span class="skel skel-avatar"></span>
						<div class="skel-post-meta">
							<span class="skel skel-line skel-w-30"></span>
							<span class="skel skel-line skel-w-20"></span>
						</div>
					</div>
					<span class="skel skel-line skel-w-80"></span>
					<span class="skel skel-line skel-w-60"></span>
				</div>
			{/each}
		</div>
	</div>
	<p class="sr-only" role="status">{tr('clubHome.loadingClub')}</p>
{:else if !club}
	<div class="not-found">
		<h2>{tr('clubHome.notFoundTitle')}</h2>
		<p>{tr('clubHome.notFoundBody')}</p>
		<a href="/clubs" class="btn-secondary">{tr('clubHome.backToClubs')}</a>
	</div>
{:else}
	<div class="page" class:realtime-ready={realtimeReady}>
		<a class="back" href="/clubs" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{tr('clubHome.allClubs')}
		</a>

		<div class="hero">
			<Avatar name={club.name} size="4.5rem" font="2rem" bg="seed" seedHue={hashHue(club.id)} />
			<div class="hero-text">
				<div class="hero-title-row">
					<h1>
						{club.name}
						{#if club.is_verified}
							<VerifiedBadge size={20} />
						{/if}
					</h1>
					{#if !club.is_public}
						<span class="badge">{tr('clubHome.privateBadge')}</span>
					{/if}
				</div>
				{#if club.location_label}
					<p class="location">
						<span class="material-symbols" aria-hidden="true">place</span>
						{club.location_label}
					</p>
				{/if}
				<p class="members-line">
					<span class="material-symbols" aria-hidden="true">group</span>
					{tr(club.member_count === 1 ? 'clubHome.memberCountOne' : 'clubHome.memberCountMany', { n: club.member_count })}
				</p>
				{#if club.viewer_role === 'owner'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						{tr('clubHome.roleOwnerPrefix')} <strong>{tr('clubHome.roleOwner')}</strong>
					</p>
				{:else if club.viewer_role === 'admin'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						{tr('clubHome.roleAdminPrefix')} <strong>{tr('clubHome.roleAdmin')}</strong>
					</p>
				{:else if club.viewer_role === 'event_organiser'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						{tr('clubHome.roleOrganiserPrefix')} <strong>{tr('clubHome.roleOrganiser')}</strong>
					</p>
				{:else if club.viewer_role === 'race_director'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						{tr('clubHome.roleDirectorPrefix')} <strong>{tr('clubHome.roleDirector')}</strong>
					</p>
				{:else if club.viewer_role === 'member'}
					<p class="role-line subtle">
						<span class="material-symbols" aria-hidden="true">check_circle</span>
						{tr('clubHome.roleMember')}
					</p>
				{/if}
				{#if club.description}
					<p class="desc">{club.description}</p>
				{/if}
				{#if club.website_url || club.instagram_url || club.strava_url || club.facebook_url}
					<p class="club-links">
						{#if club.website_url}
							<a href={club.website_url} target="_blank" rel="noopener noreferrer nofollow">
								<span class="material-symbols" aria-hidden="true">language</span>
								{tr('clubHome.visitWebsite')}
							</a>
						{/if}
						{#if club.instagram_url}
							<a href={club.instagram_url} target="_blank" rel="noopener noreferrer nofollow" aria-label="Instagram">
								<span class="material-symbols" aria-hidden="true">photo_camera</span>
							</a>
						{/if}
						{#if club.strava_url}
							<a href={club.strava_url} target="_blank" rel="noopener noreferrer nofollow" aria-label="Strava">
								<span class="material-symbols" aria-hidden="true">directions_run</span>
							</a>
						{/if}
						{#if club.facebook_url}
							<a href={club.facebook_url} target="_blank" rel="noopener noreferrer nofollow" aria-label="Facebook">
								<span class="material-symbols" aria-hidden="true">thumb_up</span>
							</a>
						{/if}
					</p>
				{/if}
			</div>
			<div class="hero-actions">
				{#if !club.viewer_role && club.viewer_status === 'pending'}
					<button class="btn-secondary" disabled>{tr('clubHome.requestPending')}</button>
				{:else if !club.viewer_role && club.join_policy === 'invite'}
					<button class="btn-secondary" disabled title={tr('clubHome.inviteOnlyTitle')}>
						{tr('clubHome.inviteOnly')}
					</button>
				{:else if !club.viewer_role}
					{#if club.requires_activity_waiver}
						<label class="waiver-ack">
							<input type="checkbox" bind:checked={waiverAck} />
							<span>{tr('clubHome.waiverAck')}</span>
						</label>
					{/if}
					<button
						class="btn-primary"
						onclick={join}
						disabled={joinBusy || (club.requires_activity_waiver && !waiverAck)}
					>
						{#if joinBusy}
							{club.join_policy === 'request' ? tr('clubHome.requesting') : tr('clubHome.joining')}
						{:else if club.join_policy === 'request'}
							{tr('clubHome.requestToJoin')}
						{:else}
							{tr('clubHome.joinClub')}
						{/if}
					</button>
				{:else if club.viewer_role === 'owner'}
					<button class="btn-secondary danger" onclick={handleDeleteClub}>{tr('clubHome.deleteClub')}</button>
				{:else}
					<button class="btn-secondary" onclick={leave} disabled={joinBusy}>
						{joinBusy ? tr('clubHome.leaving') : tr('clubHome.leave')}
					</button>
				{/if}
				{#if canManageEvents}
					<button class="btn-primary" type="button" onclick={() => (showEventModal = true)}>
						<span class="material-symbols" aria-hidden="true">add</span>
						{tr('clubHome.newEvent')}
					</button>
				{/if}
				{#if isAdmin}
					<button class="btn-secondary" type="button" onclick={() => (showEditModal = true)}>
						<span class="material-symbols" aria-hidden="true">edit</span>
						{tr('clubHome.editClub')}
					</button>
				{/if}
				{#if !isAdmin && auth.loggedIn}
					<button
						class="btn-secondary btn-icon-only"
						type="button"
						onclick={() => (showReportDialog = true)}
						aria-label={tr('clubHome.reportClub')}
						title={tr('clubHome.reportClub')}
					>
						<span class="material-symbols" aria-hidden="true">flag</span>
					</button>
				{/if}
			</div>
		</div>

		{#if error}
			<p class="error" role="alert">{error}</p>
		{/if}

		{#if isAdmin && (club.join_policy === 'invite' || club.invite_token)}
			<section class="admin-card">
				<div class="admin-card-title">
					<span class="material-symbols" aria-hidden="true">link</span>
					<strong>{tr('clubHome.inviteLink')}</strong>
					<span class="policy-chip">{club.join_policy}</span>
				</div>
				{#if club.invite_token}
					<div class="invite-row">
						<code class="invite-link">{location.origin}/clubs/join/{club.invite_token}</code>
						<button class="btn-ghost" onclick={copyInvite}>
							<span class="material-symbols" aria-hidden="true">content_copy</span>
							{tr('clubHome.copy')}
						</button>
						<button class="btn-ghost" onclick={regenerateInvite}>
							<span class="material-symbols" aria-hidden="true">refresh</span>
							{tr('clubHome.rotate')}
						</button>
					</div>
				{:else}
					<button class="btn-secondary" onclick={regenerateInvite}>{tr('clubHome.generateInviteLink')}</button>
				{/if}
			</section>
		{/if}

		{#if isAdmin && pending.length > 0}
			<section class="admin-card">
				<div class="admin-card-title">
					<span class="material-symbols" aria-hidden="true">hourglass_top</span>
					<strong>{tr('clubHome.pendingRequests', { n: pending.length })}</strong>
					{#if pending.length > 1}
						<button
							class="btn-secondary btn-sm approve-all"
							type="button"
							onclick={approveAll}
							disabled={approvingAll}
						>
							{approvingAll ? tr('clubHome.approving') : tr('clubHome.approveAll')}
						</button>
					{/if}
				</div>
				<div class="pending-list">
					{#each pending as p (p.user_id)}
						<div class="pending-row">
							<Avatar name={p.display_name} size="2.1rem" font="0.9rem" bg="seed" sat={50} seedHue={hashHue(p.user_id)} />
							<div class="pending-info">
								<strong>{p.display_name ?? tr('clubHome.memberFallback')}</strong>
								<span class="when">{tr('clubHome.requestedRelative', { time: fmtRelative(p.joined_at ?? new Date().toISOString()) })}</span>
							</div>
							<button class="btn-primary btn-sm" onclick={() => approve(p.user_id)} disabled={pendingBusy.has(p.user_id)}>{tr('clubHome.approve')}</button>
							<button class="btn-ghost" onclick={() => (rejectingMemberId = p.user_id)} disabled={pendingBusy.has(p.user_id)}>{tr('clubHome.reject')}</button>
						</div>
					{/each}
				</div>
			</section>
		{/if}

		<!-- tabindex=-1: keydown bubbles here from the focused tab; the tabs
		     carry the roving tabindex. Satisfies a11y_interactive_supports_focus. -->
		<div class="tabs" role="tablist" aria-label={tr('clubHome.tablistLabel')} tabindex={-1} onkeydown={handleTablistKeydown}>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'feed'}
				aria-selected={tab === 'feed'}
				tabindex={tab === 'feed' ? 0 : -1}
				onclick={() => setTab('feed')}
			>
				{tr('clubHome.tabFeed')}{posts.length ? ` (${posts.length})` : ''}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'events'}
				aria-selected={tab === 'events'}
				tabindex={tab === 'events' ? 0 : -1}
				onclick={() => setTab('events')}
			>
				{tr('clubHome.tabEvents')}{upcoming.length ? ` (${upcoming.length})` : ''}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'members'}
				aria-selected={tab === 'members'}
				tabindex={tab === 'members' ? 0 : -1}
				onclick={() => setTab('members')}
			>
				{tr('clubHome.tabMembers')} ({club.member_count})
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'routes'}
				aria-selected={tab === 'routes'}
				tabindex={tab === 'routes' ? 0 : -1}
				onclick={() => setTab('routes')}
			>
				{tr('clubHome.tabRoutes')}{clubRoutes.length ? ` (${clubRoutes.length})` : ''}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'templates'}
				aria-selected={tab === 'templates'}
				tabindex={tab === 'templates' ? 0 : -1}
				onclick={() => setTab('templates')}
			>
				{tr('clubHome.tabTemplates')}{templatesCount ? ` (${templatesCount})` : ''}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'photos'}
				aria-selected={tab === 'photos'}
				tabindex={tab === 'photos' ? 0 : -1}
				onclick={() => setTab('photos')}
			>
				{tr('clubHome.tabPhotos')}
			</button>
		</div>

		{#if tab === 'feed'}
			{#if upcoming.length > 0}
				<div class="next-event-card">
					<span class="label">{tr('clubHome.nextEvent')}</span>
					<a href="/clubs/{club.slug}/events/{upcoming[0].id}" class="next-event-link">
						<h3>{upcoming[0].title}</h3>
						<div class="next-event-meta">
							<span>
								<span class="material-symbols" aria-hidden="true">calendar_today</span>
								{fmtDate(upcoming[0].starts_at)}
							</span>
							{#if upcoming[0].meet_label}
								<span>
									<span class="material-symbols" aria-hidden="true">place</span>
									{upcoming[0].meet_label}
								</span>
							{/if}
							<span>
								<span class="material-symbols" aria-hidden="true">group</span>
								{tr('clubHome.goingCount', { n: upcoming[0].attendee_count })}
							</span>
						</div>
					</a>
				</div>
			{/if}

			{#if isMember}
				<form class="post-form" onsubmit={submitPost}>
					<textarea
						bind:value={draftPost}
						placeholder={tr('clubHome.postPlaceholder')}
						rows="3"
						maxlength="1200"
					></textarea>
					<button class="btn-primary" type="submit" disabled={!draftPost.trim() || postingBusy}>
						{postingBusy ? tr('clubHome.posting') : tr('clubHome.post')}
					</button>
				</form>
			{/if}

			{#if posts.length === 0}
				<div class="empty-card">
					<img src="/logo-mark.svg" alt="" width="56" height="56" class="empty-mark" />
					<h3>{tr('clubHome.emptyFeedTitle')}</h3>
					<p class="empty-text">
						{#if isMember}
							{tr('clubHome.emptyFeedMember')}
						{:else}
							{tr('clubHome.emptyFeedNonMember')}
						{/if}
					</p>
					{#if isMember}
						<div class="empty-actions">
							<button
								type="button"
								class="btn btn-primary"
								onclick={() => {
									const ta = document.querySelector<HTMLTextAreaElement>('.post-form textarea');
									ta?.focus();
								}}
							>
								<span class="material-symbols" aria-hidden="true">edit</span>
								{tr('clubHome.writeFirstPost')}
							</button>
						</div>
					{/if}
				</div>
			{:else}
				<div class="feed">
					{#each posts as post (post.id)}
						<article class="post">
							<div class="post-author">
								<a href="/u/{post.author_id}" class="author-link">
									<Avatar name={post.author_display_name} size="2.1rem" font="0.9rem" bg="seed" sat={50} seedHue={hashHue(post.author_id)} />
									<div>
										<strong>{post.author_display_name ?? tr('clubHome.memberFallback')}</strong>
										<span class="when">{fmtRelative(post.created_at ?? new Date().toISOString())}</span>
									</div>
								</a>
								{#if auth.loggedIn && auth.user?.id !== post.author_id}
									<button
										class="icon-btn"
										onclick={() => (reportPostId = post.id)}
										aria-label={tr('clubHome.reportPost')}
										title={tr('clubHome.reportPost')}
									>
										<span class="material-symbols" aria-hidden="true">flag</span>
									</button>
								{/if}
								{#if isAdmin}
									<button class="icon-btn" onclick={() => removePost(post.id)} aria-label={tr('clubHome.deletePostAria')}>
										<span class="material-symbols" aria-hidden="true">close</span>
									</button>
								{/if}
							</div>
							<p class="post-body">{post.body}</p>

							{#if club.viewer_role}
								<div class="post-actions">
									<button class="link-btn" onclick={() => toggleReplies(post.id)}>
										<span class="material-symbols" aria-hidden="true">chat_bubble_outline</span>
										{#if post.reply_count === 0}
											{tr('clubHome.reply')}
										{:else if expandedThreads[post.id]}
											{tr(post.reply_count === 1 ? 'clubHome.hideRepliesOne' : 'clubHome.hideRepliesMany', { n: post.reply_count })}
										{:else}
											{tr(post.reply_count === 1 ? 'clubHome.repliesCountOne' : 'clubHome.repliesCountMany', { n: post.reply_count })}
										{/if}
									</button>
								</div>

								{#if expandedThreads[post.id]}
									<div class="replies">
										{#each expandedThreads[post.id] ?? [] as reply (reply.id)}
											<div class="reply">
												<a href="/u/{reply.author_id}" class="reply-author-link">
													<Avatar name={reply.author_display_name} size="2.1rem" font="0.9rem" bg="seed" sat={50} seedHue={hashHue(reply.author_id)} />
												</a>
												<div class="reply-body">
													<div class="reply-head">
														<a href="/u/{reply.author_id}" class="author-link"><strong>{reply.author_display_name ?? tr('clubHome.memberFallback')}</strong></a>
														<span class="when">{fmtRelative(reply.created_at ?? new Date().toISOString())}</span>
													</div>
													<p>{reply.body}</p>
												</div>
											</div>
										{/each}
										<form
											class="reply-form"
											onsubmit={(e) => {
												e.preventDefault();
												sendReply(post.id);
											}}
										>
											<input
												type="text"
												placeholder={tr('clubHome.replyPlaceholder')}
												bind:value={replyDrafts[post.id]}
											/>
											<button
												class="btn-primary btn-sm"
												type="submit"
												disabled={!replyDrafts[post.id]?.trim() || replyBusyId === post.id}
											>
												{tr('clubHome.reply')}
											</button>
										</form>
									</div>
								{/if}
							{/if}
						</article>
					{/each}
				</div>
			{/if}
		{:else if tab === 'events'}
			{#if upcoming.length > 0}
				<h2 class="section-title">{tr('clubHome.upcoming')}</h2>
				<div class="event-list">
					{#each upcoming as evt (evt.id)}
						<a href="/clubs/{club.slug}/events/{evt.id}" class="event-row">
							<div class="event-date">
								{new Date(evt.starts_at).toLocaleDateString(activeFormatLocale(), {
									month: 'short',
									day: 'numeric'
								})}
								<span class="time">
									{new Date(evt.starts_at).toLocaleTimeString(activeFormatLocale(), {
										hour: 'numeric',
										minute: '2-digit'
									})}
								</span>
							</div>
							<div class="event-main">
								<h3>{evt.title}</h3>
								<div class="event-meta">
									{#if evt.meet_label}
										<span>
											<span class="material-symbols" aria-hidden="true">place</span>
											{evt.meet_label}
										</span>
									{/if}
									{#if evt.distance_m != null}
										<span>
											<span class="material-symbols" aria-hidden="true">straighten</span>
											{fmtKm(evt.distance_m)}
										</span>
									{/if}
									<span>
										<span class="material-symbols" aria-hidden="true">group</span>
										{tr('clubHome.goingCount', { n: evt.attendee_count })}
									</span>
								</div>
							</div>
							{#if evt.viewer_rsvp === 'going'}
								<span class="chip chip-going">{tr('clubHome.rsvpGoing')}</span>
							{:else if evt.viewer_rsvp === 'maybe'}
								<span class="chip chip-maybe">{tr('clubHome.rsvpMaybe')}</span>
							{/if}
						</a>
					{/each}
				</div>
			{:else}
				<div class="empty-card">
					<img src="/logo-mark.svg" alt="" width="56" height="56" class="empty-mark" />
					<h3>{tr('clubHome.emptyEventsTitle')}</h3>
					<p class="empty-text">
						{#if isAdmin}
							{tr('clubHome.emptyEventsAdmin')}
						{:else}
							{tr('clubHome.emptyEventsNonAdmin')}
						{/if}
					</p>
					{#if isAdmin}
						<div class="empty-actions">
							<button
								class="btn btn-primary"
								type="button"
								onclick={() => (showEventModal = true)}
							>
								<span class="material-symbols" aria-hidden="true">add</span>
								{tr('clubHome.createFirstEvent')}
							</button>
						</div>
					{/if}
				</div>
			{/if}

			{#if past.length > 0}
				<h2 class="section-title muted-title">{tr('clubHome.past')}</h2>
				<div class="event-list">
					{#each past as evt (evt.id)}
						<a href="/clubs/{club.slug}/events/{evt.id}" class="event-row past">
							<div class="event-date">
								{new Date(evt.starts_at).toLocaleDateString(activeFormatLocale(), {
									month: 'short',
									day: 'numeric'
								})}
							</div>
							<div class="event-main">
								<h3>{evt.title}</h3>
								<div class="event-meta">
									<span>
										<span class="material-symbols" aria-hidden="true">group</span>
										{tr('clubHome.attendedCount', { n: evt.attendee_count })}
									</span>
								</div>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		{:else if tab === 'routes'}
			{#if isAdmin}
				<div class="routes-actions">
					<a href="/routes/new?club={club.id}" class="btn btn-primary">
						<span class="material-symbols" aria-hidden="true">add</span>
						{tr('clubHome.newRoute')}
					</a>
					<button class="btn btn-outline" type="button" onclick={openTransferModal}>
						<span class="material-symbols" aria-hidden="true">arrow_outward</span>
						{tr('clubHome.transferFromMyRoutes')}
					</button>
				</div>
			{/if}
			{#if clubRoutes.length === 0}
				<div class="empty-card">
					<img src="/logo-mark.svg" alt="" width="56" height="56" class="empty-mark" />
					<h3>{tr('clubHome.emptyRoutesTitle')}</h3>
					<p class="empty-text">
						{#if isAdmin}
							{tr('clubHome.emptyRoutesAdmin')}
						{:else}
							{tr('clubHome.emptyRoutesNonAdmin')}
						{/if}
					</p>
					{#if isAdmin}
						<div class="empty-actions">
							<a href="/routes/new?club={club.id}" class="btn btn-primary">
								<span class="material-symbols" aria-hidden="true">add</span>
								{tr('clubHome.buildARoute')}
							</a>
							<button class="btn btn-outline" type="button" onclick={openTransferModal}>
								<span class="material-symbols" aria-hidden="true">arrow_outward</span>
								{tr('clubHome.transferOneIn')}
							</button>
						</div>
					{:else}
						<div class="empty-actions">
							<a href="/routes" class="btn btn-outline">
								<span class="material-symbols" aria-hidden="true">route</span>
								{tr('clubHome.browseMyRoutes')}
							</a>
						</div>
					{/if}
				</div>
			{:else}
				<div class="club-route-grid">
					{#each clubRoutes as route (route.id)}
						<div class="club-route-card">
							<a href="/routes/{route.id}" class="club-route-link">
								<div class="club-route-preview">
									{#if route.waypoints && route.waypoints.length > 1}
										<RouteTrackPreview
											routeId={route.id}
											waypoints={route.waypoints}
											ownerUserId={route.user_id}
										/>
									{:else}
										<span class="material-symbols" aria-hidden="true">route</span>
									{/if}
								</div>
								<div class="club-route-info">
									<h3>{route.name}</h3>
									<div class="club-route-meta">
										<span>{formatDistance(route.distance_m)}</span>
										{#if route.elevation_m}
											<span class="meta-sep">·</span>
											<span>{tr('clubHome.elevation', { n: route.elevation_m })}</span>
										{/if}
										<span class="meta-sep">·</span>
										<span class="surface-tag">{route.surface}</span>
										{#if route.is_public}
											<span class="meta-sep">·</span>
											<span class="public-tag">{tr('clubHome.publicTag')}</span>
										{/if}
									</div>
								</div>
							</a>
							{#if isAdmin}
								<button
									class="route-remove"
									type="button"
									title={tr('clubHome.removeRouteTitle')}
									aria-label={tr('clubHome.removeRouteAria')}
									onclick={() => (showRemoveRouteId = route.id)}
								>
									<span class="material-symbols" aria-hidden="true">link_off</span>
								</button>
							{/if}
						</div>
					{/each}
				</div>
			{/if}
		{:else if tab === 'templates'}
			{#if isAdmin}
				<div class="templates-toolbar">
					<a class="btn btn-primary" href="/plans/new?club={club.id}" data-testid="new-template">
						<span class="material-symbols" aria-hidden="true">add</span>
						{tr('clubHome.addTemplate')}
					</a>
				</div>
			{/if}

			{#if clubTemplates.length === 0 && sessionTemplates.length === 0 && gymRoutineTemplates.length === 0}
				<div class="empty-card">
					<img src="/logo-mark.svg" alt="" width="56" height="56" class="empty-mark" />
					<h3>{tr('clubHome.emptyTemplatesTitle')}</h3>
					<p class="empty-text">{tr('clubHome.emptyTemplatesBody')}</p>
				</div>
			{:else}
			<!-- Training plan templates -->
			{#if clubTemplates.length > 0}
			<section class="template-group">
				<div class="template-group-head">
					<h3>{tr('clubHome.trainingTemplatesTitle')}</h3>
				</div>
				<p class="section-hint">{tr('clubHome.templatesHint')}</p>
					<ul class="template-list">
						{#each clubTemplates as t (t.id)}
							<li class="template-row">
								<a href="/plans/{t.id}" class="template-link">
									<strong>{t.name}</strong>
									<span class="template-meta">
										{t.goal_event} · {formatDistance(Number(t.goal_distance_m))}
										· {tr('clubHome.daysPerWeek', { n: t.days_per_week })}
									</span>
								</a>
								<div class="template-actions">
									{#if isMember}
										<a href="/plans/new?from={t.id}" class="btn btn-primary btn-sm">
											<span class="material-symbols" aria-hidden="true">content_copy</span>
											{tr('clubHome.adopt')}
										</a>
									{/if}
									{#if isAdmin}
										<button
											class="btn btn-outline btn-sm"
											type="button"
											onclick={() => unmakeTemplate(t.id)}
											title={tr('clubHome.unpublishTitle')}
										>
											{tr('clubHome.unpublish')}
										</button>
									{/if}
								</div>
							</li>
						{/each}
					</ul>
			</section>
			{/if}

			<!-- Session templates -->
			{#if sessionTemplates.length > 0}
			<section class="template-group">
				<div class="template-group-head">
					<h3>{tr('clubHome.sessionTemplatesTitle')}</h3>
				</div>
				<p class="section-hint">{tr('clubHome.sessionTemplatesHint')}</p>
					<ul class="template-list">
						{#each sessionTemplates as s (s.id)}
							<li class="template-row">
								<a href="/sessions/{s.id}" class="template-link">
									<strong>{s.title}</strong>
									<span class="template-meta">
										{#if s.discipline}{s.discipline}{/if}
										{#if s.est_duration_min}· {tr('session.estDuration', { minutes: s.est_duration_min })}{/if}
									</span>
								</a>
								<div class="template-actions">
									{#if isMember}
										<button
											class="btn btn-primary btn-sm"
											type="button"
											disabled={adoptingSession === s.id}
											onclick={() => adoptSessionTemplate(s.id)}
											data-testid="session-template-adopt"
										>
											<span class="material-symbols" aria-hidden="true">content_copy</span>
											{tr('clubHome.adopt')}
										</button>
									{/if}
								</div>
							</li>
						{/each}
					</ul>
			</section>
			{/if}

			<!-- Gym routine templates -->
			{#if gymRoutineTemplates.length > 0}
			<section class="template-group">
				<div class="template-group-head">
					<h3>{tr('clubHome.gymRoutineTemplatesTitle')}</h3>
				</div>
				<p class="section-hint">{tr('clubHome.gymRoutineTemplatesHint')}</p>
					<ul class="template-list">
						{#each gymRoutineTemplates as g (g.id)}
							<li class="template-row">
								<a href="/gym/routines/{g.id}" class="template-link">
									<strong>{g.title}</strong>
									<span class="template-meta">
										{tr('clubHome.routineExerciseCount', { n: g.exercise_count })}
									</span>
								</a>
								<div class="template-actions">
									{#if isMember}
										<button
											class="btn btn-primary btn-sm"
											type="button"
											disabled={adoptingRoutine === g.id}
											onclick={() => adoptGymRoutineTemplate(g.id)}
											data-testid="gym-routine-template-adopt"
										>
											<span class="material-symbols" aria-hidden="true">content_copy</span>
											{tr('clubHome.adopt')}
										</button>
									{/if}
								</div>
							</li>
						{/each}
					</ul>
			</section>
			{/if}
			{/if}
		{:else if tab === 'photos'}
			<ClubPhotos clubId={club.id} canUpload={isMember} canModerate={isAdmin} />
		{:else if tab === 'members'}
			{#if members.length === 0}
				<div class="empty-card">
					<img src="/logo-mark.svg" alt="" width="56" height="56" class="empty-mark" />
					<h3>{tr('clubHome.emptyMembersTitle')}</h3>
					<p class="empty-text">
						{tr('clubHome.emptyMembersBody')}
					</p>
				</div>
			{:else}
				<div class="member-list">
					{#each members as m (m.user_id)}
						<div class="member">
							<a href="/u/{m.user_id}" class="member-link">
								<Avatar name={m.display_name} size="2.1rem" font="0.9rem" bg="seed" sat={50} seedHue={hashHue(m.user_id)} />
								<div class="member-name">
									<strong>{m.display_name ?? tr('clubHome.memberFallback')}</strong>
									{#if m.role !== 'member' && (!isAdmin || m.role === 'owner' || m.user_id === club?.owner_id)}
										<span class="role-badge role-{m.role}">{m.role.replace('_', ' ')}</span>
									{/if}
								</div>
							</a>
							<div class="member-info">
								{#if isAdmin && m.role !== 'owner' && m.user_id !== club?.owner_id}
									<select
										class="role-select"
										value={m.role}
										aria-label={tr('clubHome.changeRoleAria')}
										onchange={async (e) => {
											const target = e.currentTarget as HTMLSelectElement;
											const newRole = target.value as 'admin' | 'event_organiser' | 'race_director' | 'member';
											if (!club) return;
											try {
												await setMemberRole(club.id, m.user_id, newRole);
												m.role = newRole;
											} catch (err) {
												target.value = m.role;
												showToast(tr('clubHome.toastRoleChangeFailed', { error: err instanceof Error ? err.message : String(err) }), 'error');
											}
										}}
									>
										<option value="admin">{tr('clubHome.roleOptionAdmin')}</option>
										<option value="event_organiser">{tr('clubHome.roleOptionOrganiser')}</option>
										<option value="race_director">{tr('clubHome.roleOptionDirector')}</option>
										<option value="member">{tr('clubHome.roleOptionMember')}</option>
									</select>
									{#if m.user_id !== auth.user?.id}
										<button
											class="icon-btn danger"
											title={tr('clubHome.removeFromClubTitle')}
											aria-label={tr('clubHome.removeMemberAria')}
											onclick={() => (removingMemberId = m.user_id)}
										>
											<span class="material-symbols" aria-hidden="true">person_remove</span>
										</button>
									{/if}
								{/if}
							</div>
						</div>
					{/each}
				</div>
			{/if}
		{/if}
	</div>

<ConfirmDialog
	open={showLeaveConfirm}
	title={tr('clubHome.leaveClubTitle')}
	message={tr('clubHome.leaveClubMessage', { name: club?.name ?? '' })}
	confirmLabel={tr('clubHome.leave')}
	onconfirm={confirmLeave}
	oncancel={() => showLeaveConfirm = false}
	danger
/>

<ConfirmDialog
	open={showRegenConfirm}
	title={tr('clubHome.regenTitle')}
	message={tr('clubHome.regenMessage')}
	confirmLabel={tr('clubHome.regenerate')}
	onconfirm={confirmRegenerate}
	oncancel={() => showRegenConfirm = false}
/>

<ConfirmDialog
	open={showDeletePostConfirm !== null}
	title={tr('clubHome.deletePostTitle')}
	message={tr('clubHome.deletePostMessage')}
	confirmLabel={tr('clubHome.delete')}
	onconfirm={confirmDeletePost}
	oncancel={() => showDeletePostConfirm = null}
	danger
/>

<ConfirmDialog
	open={showRemoveRouteId !== null}
	title={tr('clubHome.removeRouteConfirmTitle')}
	message={tr('clubHome.removeRouteConfirmMessage')}
	confirmLabel={tr('clubHome.remove')}
	onconfirm={confirmRemoveRoute}
	oncancel={() => showRemoveRouteId = null}
	danger
/>

<ConfirmDialog
	open={showDeleteClubConfirm}
	title={tr('clubHome.deleteClubTitle')}
	message={tr('clubHome.deleteClubMessage', { name: club?.name ?? '' })}
	confirmLabel={tr('clubHome.delete')}
	onconfirm={confirmDeleteClub}
	oncancel={() => showDeleteClubConfirm = false}
	danger
/>

<ConfirmDialog
	open={removingMemberId !== null}
	title={tr('clubHome.removeMemberTitle')}
	message={tr('clubHome.removeMemberMessage', {
		name: members.find((m) => m.user_id === removingMemberId)?.display_name ?? tr('clubHome.thisMember'),
		club: club?.name ?? tr('clubHome.theClub')
	})}
	confirmLabel={tr('clubHome.remove')}
	onconfirm={confirmRemoveMember}
	oncancel={() => (removingMemberId = null)}
	danger
/>

<ConfirmDialog
	open={rejectingMemberId !== null}
	title={tr('clubHome.rejectRequestTitle')}
	message={tr('clubHome.rejectRequestMessage', {
		name: pending.find((p) => p.user_id === rejectingMemberId)?.display_name ?? tr('clubHome.thisMember'),
		club: club?.name ?? tr('clubHome.theClub')
	})}
	confirmLabel={tr('clubHome.reject')}
	onconfirm={confirmReject}
	oncancel={() => (rejectingMemberId = null)}
	danger
/>

{#if club}
	<ReportDialog
		open={showReportDialog}
		targetKind="club"
		targetId={club.id}
		targetLabel={club.name}
		onclose={() => (showReportDialog = false)}
	/>
{/if}

<ReportDialog
	open={reportPostId !== null}
	targetKind="club_post"
	targetId={reportPostId ?? ''}
	onclose={() => (reportPostId = null)}
/>

<Modal
	open={showEventModal && club != null}
	title={tr('clubHome.newEvent')}
	wide
	onclose={() => (showEventModal = false)}
>
	{#if club}
		<EventEditor
			clubId={club.id}
			clubName={club.name}
			clubIsPublic={club.is_public}
			oncreated={handleEventCreated}
			oncancel={() => (showEventModal = false)}
		/>
	{/if}
</Modal>

<Modal
	open={showEditModal && club != null}
	title={tr('clubHome.editClubTitle')}
	wide
	onclose={() => (showEditModal = false)}
>
	{#if club}
		<ClubEditor
			existing={club}
			onsaved={async () => {
				showEditModal = false;
				await load();
			}}
			oncancel={() => (showEditModal = false)}
		/>
	{/if}
</Modal>

<Modal
	open={showTransferModal}
	title={tr('clubHome.transferModalTitle')}
	onclose={() => (showTransferModal = false)}
>
	<form
		class="transfer-form"
		onsubmit={(e) => {
			e.preventDefault();
			confirmTransfer();
		}}
	>
		{#if transferableRoutes.length === 0}
			<p class="muted">{tr('clubHome.noTransferableRoutes')}</p>
		{:else}
			<label>
				<span>{tr('clubHome.pickARoute')}</span>
				<select bind:value={transferRouteId} required>
					<option value="">{tr('clubHome.selectPlaceholder')}</option>
					{#each transferableRoutes as r (r.id)}
						<option value={r.id}>{r.name} ({formatDistance(r.distance_m)})</option>
					{/each}
				</select>
			</label>
			<p class="hint muted">
				{tr('clubHome.transferHint')}
			</p>
		{/if}
		<div class="transfer-actions">
			<button type="button" class="btn btn-outline" onclick={() => (showTransferModal = false)}>
				{tr('clubHome.cancel')}
			</button>
			<button type="submit" class="btn btn-primary" disabled={!transferRouteId}>{tr('clubHome.transfer')}</button>
		</div>
	</form>
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
	}

	.hero {
		display: grid;
		grid-template-columns: auto 1fr auto;
		gap: var(--space-md);
		align-items: start;
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-lg);
	}



	.hero-text h1 {
		font-size: 1.6rem;
		margin: 0;
	}

	.hero-title-row {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}

	.location,
	.members-line {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0.25rem 0 0 0;
	}

	.location .material-symbols,
	.members-line .material-symbols {
		font-size: 1rem;
	}

	.desc {
		margin-top: 0.6rem;
		line-height: 1.5;
		color: var(--color-text);
	}

	.hero-actions {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		align-items: stretch;
	}

	.btn-secondary.danger {
		color: var(--color-danger);
		border-color: var(--color-danger-light);
	}
	.btn-secondary.danger:hover {
		background: var(--color-danger-light);
	}

	.badge {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
		background: var(--color-bg-tertiary);
		padding: 0.15rem 0.5rem;
		border-radius: var(--radius-sm);
	}

	.tabs {
		display: flex;
		gap: 1rem;
		margin-bottom: var(--space-md);
		border-bottom: 1px solid var(--color-border);
	}

	.tab {
		background: none;
		border: none;
		padding: 0.6rem 0.2rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 500;
	}

	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}

	.admin-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}

	.admin-card-title {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin-bottom: 0.6rem;
	}

	.approve-all {
		margin-inline-start: auto;
	}

	.policy-chip {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: 0.1rem 0.5rem;
		border-radius: var(--radius-sm);
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
	}

	.invite-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-wrap: wrap;
	}

	.invite-link {
		flex: 1;
		background: var(--color-bg-secondary);
		padding: 0.5rem 0.75rem;
		border-radius: var(--radius-md);
		font-family: ui-monospace, Menlo, monospace;
		font-size: 0.82rem;
		overflow-x: auto;
		white-space: nowrap;
	}

	.btn-ghost {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text);
		padding: 0.4rem 0.65rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.85rem;
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
	}

	.btn-ghost:hover {
		background: var(--color-bg-tertiary);
	}

	.pending-list {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}

	.pending-row {
		display: grid;
		grid-template-columns: auto 1fr auto auto;
		gap: 0.5rem;
		align-items: center;
		padding: 0.5rem 0.6rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}

	.pending-info {
		display: flex;
		flex-direction: column;
	}

	.pending-info .when {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}

	.post-actions {
		margin-top: 0.4rem;
	}

	.link-btn {
		background: none;
		border: none;
		color: var(--color-primary);
		font-weight: 600;
		font-size: 0.85rem;
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		padding: 0.2rem 0;
	}

	.link-btn .material-symbols {
		font-size: 1rem;
	}

	.replies {
		margin-top: 0.6rem;
		padding-inline-start: 0.6rem;
		border-inline-start: 2px solid var(--color-border);
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.reply {
		display: flex;
		gap: 0.5rem;
	}

	.reply-body {
		flex: 1;
		background: var(--color-bg-secondary);
		padding: 0.4rem 0.65rem;
		border-radius: var(--radius-md);
	}

	.reply-head {
		display: flex;
		gap: 0.5rem;
		align-items: baseline;
	}

	.reply-head .when {
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
	}

	.reply-body p {
		white-space: pre-wrap;
		margin-top: 0.15rem;
	}

	.reply-form {
		display: flex;
		gap: 0.4rem;
		margin-top: 0.3rem;
	}

	.reply-form input {
		flex: 1;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		padding: 0.4rem 0.6rem;
		border-radius: var(--radius-md);
		font: inherit;
		color: inherit;
	}

	.next-event-card {
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 10%, var(--color-surface)),
			var(--color-surface)
		);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}

	.next-event-card .label {
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-primary);
		font-weight: 700;
	}

	.next-event-link {
		display: block;
		color: inherit;
		margin-top: 0.35rem;
	}

	.next-event-link h3 {
		margin: 0 0 0.5rem 0;
		font-size: 1.15rem;
	}

	.next-event-meta,
	.event-meta {
		display: flex;
		flex-wrap: wrap;
		gap: 1rem;
		color: var(--color-text-secondary);
		font-size: 0.88rem;
	}

	.next-event-meta span,
	.event-meta span {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}

	.next-event-meta .material-symbols,
	.event-meta .material-symbols {
		font-size: 1rem;
	}

	.post-form {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}

	.post-form textarea {
		background: transparent;
		border: none;
		resize: vertical;
		font: inherit;
		color: inherit;
		outline: none;
		min-height: 3rem;
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: the
	   textarea base above suppresses the browser focus ring on
	   every state. Add :focus-visible so keyboard focus has a
	   ring. Mouse focus stays unstyled. */
	.post-form textarea:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.post-form .btn-primary {
		align-self: flex-end;
	}

	.feed {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.post {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
	}

	.post-author {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		margin-bottom: 0.5rem;
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

	.icon-btn {
		margin-inline-start: auto;
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0.25rem;
		border-radius: var(--radius-sm);
	}

	.icon-btn:hover {
		color: var(--color-danger);
		background: var(--color-danger-light);
	}

	.section-title {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: var(--space-lg) 0 var(--space-sm) 0;
	}

	.muted-title {
		margin-top: var(--space-xl);
	}

	.event-list {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}

	.event-row {
		display: grid;
		grid-template-columns: 4.5rem 1fr auto;
		align-items: center;
		gap: 1rem;
		padding: 0.8rem 1rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: inherit;
		transition: border-color var(--transition-base), transform var(--transition-base);
	}

	.event-row:hover {
		border-color: color-mix(in srgb, var(--color-primary) 40%, var(--color-border));
		transform: translateX(2px);
	}

	.event-row.past {
		opacity: 0.75;
	}

	.event-date {
		display: flex;
		flex-direction: column;
		align-items: center;
		color: var(--color-primary);
		font-weight: 700;
		font-size: 0.95rem;
		line-height: 1.15;
	}

	.event-date .time {
		color: var(--color-text-secondary);
		font-weight: 500;
		font-size: 0.78rem;
	}

	.event-main h3 {
		margin: 0 0 0.25rem 0;
		font-size: 1rem;
	}

	.chip-going {
		background: var(--color-primary-light);
		color: var(--color-primary);
		padding: 0.2rem 0.6rem;
		border-radius: var(--radius-sm);
		font-size: 0.8rem;
		font-weight: 600;
	}

	.chip-maybe {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
		padding: 0.2rem 0.6rem;
		border-radius: var(--radius-sm);
		font-size: 0.8rem;
		font-weight: 600;
	}

	.member-list {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr));
		gap: 0.6rem;
	}

	.member {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.55rem 0.8rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}

	.member-link {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		flex: 1;
		min-width: 0;
		text-decoration: none;
		color: inherit;
	}

	.member-link:hover strong,
	.author-link:hover strong {
		color: var(--color-primary);
	}

	.author-link {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		text-decoration: none;
		color: inherit;
	}

	.reply-author-link {
		text-decoration: none;
	}

	.member-info {
		display: flex;
		flex-direction: column;
	}

	.role-select {
		padding: 0.15rem 0.4rem;
		font-size: 0.75rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text-secondary);
		cursor: pointer;
	}

	.member-name {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
	}

	.role-badge {
		display: inline-block;
		font-size: 0.7rem;
		font-weight: 600;
		text-transform: capitalize;
		letter-spacing: 0.02em;
		padding: 0.05rem 0.45rem;
		border-radius: var(--radius-sm);
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		width: fit-content;
	}
	.role-badge.role-owner {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.role-badge.role-admin {
		background: color-mix(in srgb, var(--color-accent-cyan, var(--color-primary)) 18%, transparent);
		color: color-mix(in srgb, var(--color-accent-cyan, var(--color-primary)) 80%, var(--color-text));
	}
	.role-badge.role-event_organiser,
	.role-badge.role-race_director {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
	}

	/* Canonical empty-card pattern (mirrors /clubs, /routes, /runs, /plans).
	   Card with brand-mark, h3, explainer, primary CTA + secondary actions. */
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
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}
	.empty-actions .material-symbols {
		font-size: 1.1rem;
	}

	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}

	.not-found {
		text-align: center;
		padding: var(--space-2xl);
	}

	.centered {
		text-align: center;
		padding: var(--space-2xl);
	}

	.muted {
		color: var(--color-text-tertiary);
	}

	.routes-actions {
		display: flex;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
		flex-wrap: wrap;
	}

	.club-route-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(20rem, 1fr));
		gap: var(--space-md);
	}

	.club-route-card {
		position: relative;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		transition: all var(--transition-fast);
	}

	.club-route-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}

	.club-route-link {
		display: block;
		text-decoration: none;
		color: inherit;
	}

	.club-route-preview {
		height: 8rem;
		background: var(--color-bg-tertiary);
		border-bottom: 1px solid var(--color-border);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.club-route-preview .material-symbols {
		font-size: 2rem;
		color: var(--color-text-tertiary);
	}

	.club-route-info {
		padding: var(--space-md) var(--space-lg);
	}

	.club-route-info h3 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: var(--space-xs);
	}

	.club-route-meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.public-tag {
		color: var(--color-primary);
	}

	.surface-tag {
		text-transform: capitalize;
	}

	.route-remove {
		position: absolute;
		top: 0.5rem;
		inset-inline-end: 0.5rem;
		display: grid;
		place-items: center;
		width: 2rem;
		height: 2rem;
		background: rgba(0, 0, 0, 0.45);
		border: none;
		border-radius: 50%;
		color: white;
		cursor: pointer;
	}
	.route-remove:hover {
		background: var(--color-danger, #ef4444);
	}

	.transfer-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.transfer-form label {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}

	.transfer-form select {
		padding: var(--space-sm) var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
	}

	.transfer-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}

	.hint {
		font-size: 0.85rem;
	}

	.section-hint {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.5;
		margin: 0 0 var(--space-md) 0;
	}

	.templates-toolbar {
		display: flex;
		justify-content: flex-end;
		margin-bottom: var(--space-lg);
	}
	.template-group {
		margin-bottom: var(--space-2xl);
	}
	.template-group-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		flex-wrap: wrap;
		margin-bottom: var(--space-2xs);
	}
	.template-group-head h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 700;
	}
	.template-group .section-hint {
		margin-top: 0;
		margin-bottom: var(--space-md);
	}

	.template-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.template-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}

	.template-link {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		text-decoration: none;
		color: inherit;
		flex: 1;
		min-width: 0;
	}

	.template-meta {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.template-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		flex-shrink: 0;
	}
	.template-actions .material-symbols {
		font-size: 1rem;
	}

	.role-line {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-primary);
		font-size: 0.88rem;
		font-weight: 500;
		margin: 0.25rem 0 0 0;
	}
	.role-line.subtle {
		color: var(--color-text-secondary);
		font-weight: 400;
	}
	.role-line .material-symbols {
		font-size: 1rem;
	}
	.role-line strong {
		text-transform: capitalize;
	}

	/* Skeleton — same shimmer language as /clubs + /routes. The hero / tab
	   / feed scaffold lands at the real layout's height so the data swap
	   doesn't shift the page. */
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
	.skel-hero {
		grid-template-columns: auto 1fr;
	}
	.skel-avatar-lg {
		width: 4.5rem;
		height: 4.5rem;
		border-radius: 50%;
	}
	.skel-hero-text {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		justify-content: center;
	}
	.skel-avatar {
		width: 2.1rem;
		height: 2.1rem;
		border-radius: 50%;
		flex-shrink: 0;
	}
	.skel-line {
		height: 0.75rem;
	}
	.skel-w-20 { width: 20%; }
	.skel-w-30 { width: 30%; }
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	.skel-w-80 { width: 80%; }
	.tabs-skel {
		display: flex;
		gap: 1.5rem;
		margin-bottom: var(--space-md);
		padding-bottom: 0.7rem;
		border-bottom: 1px solid var(--color-border);
	}
	.skel-tab {
		width: 4rem;
		height: 0.9rem;
	}
	.feed-skel {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.skel-post {
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		pointer-events: none;
	}
	.skel-post-head {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}
	.skel-post-meta {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		flex: 1;
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

	/* <=50rem (small tablet / large phone). Stack hero action column
	   under the text block so it doesn't compress the title. */
	@media (max-width: 50rem) {
		.hero {
			grid-template-columns: auto 1fr;
		}
		.hero-actions {
			grid-column: 1 / -1;
			flex-direction: row;
			flex-wrap: wrap;
		}
		.tabs {
			overflow-x: auto;
			gap: 0.5rem;
			scrollbar-width: thin;
		}
		.tab {
			flex-shrink: 0;
		}
	}

	/* .modal-* classes live in app.css. */
</style>
