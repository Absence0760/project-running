<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { goto, afterNavigate } from '$app/navigation';
	import { supabase } from '$lib/supabase';
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
		approveMember,
		rejectMember,
		removeMember,
		setMemberRole,
		regenerateInviteToken,
		joinClub,
		leaveClub,
		createClubPost,
		deleteClubPost,
		deleteClub
	} from '$lib/data';
	import { formatDistance } from '$lib/mock-data';
	import { auth } from '$lib/stores/auth.svelte';
	import RouteTrackPreview from '$lib/components/RouteTrackPreview.svelte';
	import type { Route, TrainingPlan } from '$lib/types';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import EventEditor from '$lib/components/EventEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ReportDialog from '$lib/components/ReportDialog.svelte';
	import VerifiedBadge from '$lib/components/VerifiedBadge.svelte';
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
	type Tab = 'feed' | 'events' | 'routes' | 'templates' | 'members';
	const TABS: readonly Tab[] = ['feed', 'events', 'routes', 'templates', 'members'];
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
	let transferRouteId = $state('');
	let clubTemplates = $state<TrainingPlan[]>([]);

	async function handleEventCreated(event: { id: string }) {
		showEventModal = false;
		// Refresh the events lists so the new one shows up immediately;
		// admins typically stay on the club page after creating.
		await load();
		showToast('Event created.');
	}

	let draftPost = $state('');
	let postingBusy = $state(false);
	let joinBusy = $state(false);
	let error = $state<string | null>(null);
	let showLeaveConfirm = $state(false);
	let showReportDialog = $state(false);
	let showRegenConfirm = $state(false);
	let showDeleteClubConfirm = $state(false);
	let showDeletePostConfirm = $state<string | null>(null);
	/** When non-null, the user_id of the member the admin is about to
	 *  remove. Drives the kick ConfirmDialog. */
	let removingMemberId = $state<string | null>(null);

	/** Thread state. Key is parent post id. */
	let expandedThreads = $state<Record<string, ClubPostWithAuthor[] | null>>({});
	let replyDrafts = $state<Record<string, string>>({});

	let isAdmin = $derived(
		club?.viewer_role === 'owner' || club?.viewer_role === 'admin'
	);
	let isMember = $derived(club?.viewer_role != null);

	async function load() {
		loading = true;
		club = await fetchClubBySlug(slug);
		if (!club) {
			loading = false;
			return;
		}
		const [up, pa, po, me, pe, rt, tp] = await Promise.all([
			fetchUpcomingEvents(club.id),
			fetchPastEvents(club.id, 6),
			fetchClubPosts(club.id, 20),
			fetchClubMembers(club.id),
			club.viewer_role === 'owner' || club.viewer_role === 'admin'
				? fetchPendingRequests(club.id)
				: Promise.resolve([]),
			fetchClubRoutes(club.id),
			fetchClubTemplates(club.id)
		]);
		upcoming = up;
		past = pa;
		posts = po;
		members = me;
		pending = pe;
		clubRoutes = rt;
		clubTemplates = tp;
		loading = false;
	}

	async function unmakeTemplate(planId: string) {
		try {
			await setPlanIsTemplate(planId, false, null);
			showToast('Template removed from club.');
			await load();
		} catch (e) {
			showToast(`Failed: ${e}`, 'error');
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
			showToast('Route transferred to club.');
			await load();
		} catch (e) {
			showToast(`Failed to transfer route: ${e}`, 'error');
		}
	}

	async function removeRouteFromClub(routeId: string) {
		try {
			await setRouteClubId(routeId, null);
			showToast('Route returned to your personal library.');
			await load();
		} catch (e) {
			showToast(`Failed to remove route from club: ${e}`, 'error');
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
		// Poll briefly before kicking off load(). Same shape as /clubs,
		// /dashboard, /coach, /runs/[id], /settings/*.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
		subscribeRealtime();
	});

	onDestroy(() => {
		if (pingRetryTimer) {
			clearTimeout(pingRetryTimer);
			pingRetryTimer = null;
		}
		if (channel) {
			supabase.removeChannel(channel);
			channel = null;
		}
		realtimeReady = false;
	});

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
			});
	}

	async function join() {
		if (!club || joinBusy) return;
		joinBusy = true;
		try {
			const status = await joinClub(club.id, club.join_policy);
			if (status === 'pending') {
				error = `Request sent. An admin will review it.`;
			}
			await load();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Failed to join';
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
			error = e instanceof Error ? e.message : 'Failed to leave';
		} finally {
			joinBusy = false;
		}
	}

	async function approve(userId: string) {
		if (!club) return;
		await approveMember(club.id, userId);
		await load();
	}

	async function reject(userId: string) {
		if (!club) return;
		await rejectMember(club.id, userId);
		await load();
	}

	async function confirmRemoveMember() {
		const userId = removingMemberId;
		removingMemberId = null;
		if (!club || !userId) return;
		try {
			await removeMember(club.id, userId);
			await load();
		} catch (e) {
			showToast(`Failed to remove member: ${e}`, 'error');
		}
	}

	async function copyInvite() {
		if (!club?.invite_token) return;
		const link = `${location.origin}/clubs/join/${club.invite_token}`;
		await navigator.clipboard.writeText(link);
		error = 'Invite link copied to clipboard.';
	}

	function regenerateInvite() {
		if (!club) return;
		showRegenConfirm = true;
	}

	async function confirmRegenerate() {
		if (!club) return;
		showRegenConfirm = false;
		const token = await regenerateInviteToken(club.id);
		club = { ...club, invite_token: token };
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
		if (!club) return;
		const body = replyDrafts[postId]?.trim();
		if (!body) return;
		await createClubPost({ club_id: club.id, body, parent_post_id: postId });
		replyDrafts = { ...replyDrafts, [postId]: '' };
		const replies = await fetchPostReplies(postId);
		expandedThreads = { ...expandedThreads, [postId]: replies };
		// Refresh reply counts on the top-level post list.
		posts = await fetchClubPosts(club.id, 20);
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
			error = e instanceof Error ? e.message : 'Failed to post';
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
		await deleteClubPost(id);
		posts = await fetchClubPosts(club.id, 20);
	}

	function handleDeleteClub() {
		if (!club) return;
		showDeleteClubConfirm = true;
	}

	async function confirmDeleteClub() {
		if (!club) return;
		showDeleteClubConfirm = false;
		await deleteClub(club.id);
		goto('/clubs');
	}

	function fmtDate(iso: string | null | undefined): string {
		if (!iso) return '';
		const d = new Date(iso);
		return d.toLocaleString(undefined, {
			weekday: 'short',
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}

	function fmtKm(m: number | null | undefined): string {
		// Defers to the unit-aware formatter in $lib/units.svelte so a
		// km → mi preference flip on /settings/preferences re-renders
		// every distance string on this page. The previous local
		// implementation hardcoded " km" — the audit caught it.
		if (m == null) return '';
		return formatDistance(m);
	}

	function fmtRelative(iso: string): string {
		const diff = Date.now() - new Date(iso).getTime();
		const min = Math.floor(diff / 60_000);
		if (min < 1) return 'Just now';
		if (min < 60) return `${min}m ago`;
		const hr = Math.floor(min / 60);
		if (hr < 24) return `${hr}h ago`;
		const d = Math.floor(hr / 24);
		if (d < 7) return `${d}d ago`;
		return new Date(iso).toLocaleDateString();
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
	<div class="page">
		<span class="back-skel" aria-hidden="true">
			<span class="material-symbols">arrow_back</span>
			All clubs
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
	<p class="sr-only" role="status">Loading club…</p>
{:else if !club}
	<div class="not-found">
		<h2>Club not found</h2>
		<p>This club may be private, or it may have been deleted.</p>
		<a href="/clubs" class="btn-secondary">Back to clubs</a>
	</div>
{:else}
	<div class="page" class:realtime-ready={realtimeReady}>
		<a class="back" href="/clubs" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			All clubs
		</a>

		<div class="hero">
			<div class="avatar-lg" style="--seed: {hashHue(club.id)}">
				{initial(club.name)}
			</div>
			<div class="hero-text">
				<div class="hero-title-row">
					<h1>
						{club.name}
						{#if club.is_verified}
							<VerifiedBadge size={20} />
						{/if}
					</h1>
					{#if !club.is_public}
						<span class="badge">Private</span>
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
					{club.member_count} member{club.member_count === 1 ? '' : 's'}
				</p>
				{#if club.viewer_role === 'owner'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						You're the <strong>owner</strong>
					</p>
				{:else if club.viewer_role === 'admin'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						You're an <strong>admin</strong>
					</p>
				{:else if club.viewer_role === 'event_organiser'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						You're an <strong>event organiser</strong>
					</p>
				{:else if club.viewer_role === 'race_director'}
					<p class="role-line">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						You're a <strong>race director</strong>
					</p>
				{:else if club.viewer_role === 'member'}
					<p class="role-line subtle">
						<span class="material-symbols" aria-hidden="true">check_circle</span>
						You're a member
					</p>
				{/if}
				{#if club.description}
					<p class="desc">{club.description}</p>
				{/if}
			</div>
			<div class="hero-actions">
				{#if !club.viewer_role && club.viewer_status === 'pending'}
					<button class="btn-secondary" disabled>Request pending</button>
				{:else if !club.viewer_role && club.join_policy === 'invite'}
					<button class="btn-secondary" disabled title="Invite-only — ask an admin for the link.">
						Invite only
					</button>
				{:else if !club.viewer_role}
					<button class="btn-primary" onclick={join} disabled={joinBusy}>
						{#if joinBusy}
							{club.join_policy === 'request' ? 'Requesting…' : 'Joining…'}
						{:else if club.join_policy === 'request'}
							Request to join
						{:else}
							Join club
						{/if}
					</button>
				{:else if club.viewer_role === 'owner'}
					<button class="btn-secondary danger" onclick={handleDeleteClub}>Delete club</button>
				{:else}
					<button class="btn-secondary" onclick={leave} disabled={joinBusy}>
						{joinBusy ? 'Leaving…' : 'Leave'}
					</button>
				{/if}
				{#if isAdmin}
					<button class="btn-primary" type="button" onclick={() => (showEventModal = true)}>
						<span class="material-symbols" aria-hidden="true">add</span>
						New event
					</button>
				{/if}
				{#if !isAdmin && auth.loggedIn}
					<button
						class="btn-secondary btn-icon-only"
						type="button"
						onclick={() => (showReportDialog = true)}
						aria-label="Report this club"
						title="Report this club"
					>
						<span class="material-symbols" aria-hidden="true">flag</span>
					</button>
				{/if}
			</div>
		</div>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		{#if isAdmin && (club.join_policy === 'invite' || club.invite_token)}
			<section class="admin-card">
				<div class="admin-card-title">
					<span class="material-symbols" aria-hidden="true">link</span>
					<strong>Invite link</strong>
					<span class="policy-chip">{club.join_policy}</span>
				</div>
				{#if club.invite_token}
					<div class="invite-row">
						<code class="invite-link">{location.origin}/clubs/join/{club.invite_token}</code>
						<button class="btn-ghost" onclick={copyInvite}>
							<span class="material-symbols" aria-hidden="true">content_copy</span>
							Copy
						</button>
						<button class="btn-ghost" onclick={regenerateInvite}>
							<span class="material-symbols" aria-hidden="true">refresh</span>
							Rotate
						</button>
					</div>
				{:else}
					<button class="btn-secondary" onclick={regenerateInvite}>Generate invite link</button>
				{/if}
			</section>
		{/if}

		{#if isAdmin && pending.length > 0}
			<section class="admin-card">
				<div class="admin-card-title">
					<span class="material-symbols" aria-hidden="true">hourglass_top</span>
					<strong>Pending requests ({pending.length})</strong>
				</div>
				<div class="pending-list">
					{#each pending as p (p.user_id)}
						<div class="pending-row">
							<div class="avatar-sm" style="--seed: {hashHue(p.user_id)}">
								{initial(p.display_name)}
							</div>
							<div class="pending-info">
								<strong>{p.display_name ?? 'Member'}</strong>
								<span class="when">Requested {fmtRelative(p.joined_at ?? new Date().toISOString())}</span>
							</div>
							<button class="btn-primary btn-sm" onclick={() => approve(p.user_id)}>Approve</button>
							<button class="btn-ghost" onclick={() => reject(p.user_id)}>Reject</button>
						</div>
					{/each}
				</div>
			</section>
		{/if}

		<div class="tabs" role="tablist" aria-label="Club sections">
			<button
				role="tab"
				class="tab"
				class:active={tab === 'feed'}
				aria-selected={tab === 'feed'}
				onclick={() => setTab('feed')}
			>
				Feed{posts.length ? ` (${posts.length})` : ''}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'events'}
				aria-selected={tab === 'events'}
				onclick={() => setTab('events')}
			>
				Events{upcoming.length ? ` (${upcoming.length})` : ''}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'members'}
				aria-selected={tab === 'members'}
				onclick={() => setTab('members')}
			>
				Members ({club.member_count})
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'routes'}
				aria-selected={tab === 'routes'}
				onclick={() => setTab('routes')}
			>
				Routes{clubRoutes.length ? ` (${clubRoutes.length})` : ''}
			</button>
			<button
				role="tab"
				class="tab"
				class:active={tab === 'templates'}
				aria-selected={tab === 'templates'}
				onclick={() => setTab('templates')}
			>
				Templates{clubTemplates.length ? ` (${clubTemplates.length})` : ''}
			</button>
		</div>

		{#if tab === 'feed'}
			{#if upcoming.length > 0}
				<div class="next-event-card">
					<span class="label">Next event</span>
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
								{upcoming[0].attendee_count} going
							</span>
						</div>
					</a>
				</div>
			{/if}

			{#if isMember}
				<form class="post-form" onsubmit={submitPost}>
					<textarea
						bind:value={draftPost}
						placeholder="Share an update with members — course change, weather call, post-run social…"
						rows="3"
						maxlength="1200"
					></textarea>
					<button class="btn-primary" type="submit" disabled={!draftPost.trim() || postingBusy}>
						{postingBusy ? 'Posting…' : 'Post'}
					</button>
				</form>
			{/if}

			{#if posts.length === 0}
				<div class="empty-card">
					<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
					<h3>No posts yet</h3>
					<p class="empty-text">
						{#if isMember}
							Share course changes, weather calls, or post-run plans with members.
							Posts here notify every active member.
						{:else}
							This is where members trade course changes, weather calls, and
							post-run plans. Join the club to see and add posts.
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
								Write the first post
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
									<div class="avatar-sm" style="--seed: {hashHue(post.author_id)}">
										{initial(post.author_display_name)}
									</div>
									<div>
										<strong>{post.author_display_name ?? 'Member'}</strong>
										<span class="when">{fmtRelative(post.created_at ?? new Date().toISOString())}</span>
									</div>
								</a>
								{#if isAdmin}
									<button class="icon-btn" onclick={() => removePost(post.id)} aria-label="Delete post">
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
											Reply
										{:else if expandedThreads[post.id]}
											Hide {post.reply_count} {post.reply_count === 1 ? 'reply' : 'replies'}
										{:else}
											{post.reply_count} {post.reply_count === 1 ? 'reply' : 'replies'}
										{/if}
									</button>
								</div>

								{#if expandedThreads[post.id]}
									<div class="replies">
										{#each expandedThreads[post.id] ?? [] as reply (reply.id)}
											<div class="reply">
												<a href="/u/{reply.author_id}" class="reply-author-link">
													<div class="avatar-sm" style="--seed: {hashHue(reply.author_id)}">
														{initial(reply.author_display_name)}
													</div>
												</a>
												<div class="reply-body">
													<div class="reply-head">
														<a href="/u/{reply.author_id}" class="author-link"><strong>{reply.author_display_name ?? 'Member'}</strong></a>
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
												placeholder="Write a reply…"
												bind:value={replyDrafts[post.id]}
											/>
											<button
												class="btn-primary btn-sm"
												type="submit"
												disabled={!replyDrafts[post.id]?.trim()}
											>
												Reply
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
				<h2 class="section-title">Upcoming</h2>
				<div class="event-list">
					{#each upcoming as evt (evt.id)}
						<a href="/clubs/{club.slug}/events/{evt.id}" class="event-row">
							<div class="event-date">
								{new Date(evt.starts_at).toLocaleDateString(undefined, {
									month: 'short',
									day: 'numeric'
								})}
								<span class="time">
									{new Date(evt.starts_at).toLocaleTimeString(undefined, {
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
										{evt.attendee_count} going
									</span>
								</div>
							</div>
							{#if evt.viewer_rsvp === 'going'}
								<span class="chip chip-going">Going</span>
							{:else if evt.viewer_rsvp === 'maybe'}
								<span class="chip chip-maybe">Maybe</span>
							{/if}
						</a>
					{/each}
				</div>
			{:else}
				<div class="empty-card">
					<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
					<h3>No upcoming events</h3>
					<p class="empty-text">
						{#if isAdmin}
							Set up a weekly long run, a tempo session, or a race-day meetup.
							Members get a tab badge the moment you publish.
						{:else}
							Admins post group runs, tempo sessions, and races here. Check
							back soon — or browse past events below.
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
								Create the first event
							</button>
						</div>
					{/if}
				</div>
			{/if}

			{#if past.length > 0}
				<h2 class="section-title muted-title">Past</h2>
				<div class="event-list">
					{#each past as evt (evt.id)}
						<a href="/clubs/{club.slug}/events/{evt.id}" class="event-row past">
							<div class="event-date">
								{new Date(evt.starts_at).toLocaleDateString(undefined, {
									month: 'short',
									day: 'numeric'
								})}
							</div>
							<div class="event-main">
								<h3>{evt.title}</h3>
								<div class="event-meta">
									<span>
										<span class="material-symbols" aria-hidden="true">group</span>
										{evt.attendee_count} attended
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
						New route
					</a>
					<button class="btn btn-outline" type="button" onclick={openTransferModal}>
						<span class="material-symbols" aria-hidden="true">arrow_outward</span>
						Transfer from My routes
					</button>
				</div>
			{/if}
			{#if clubRoutes.length === 0}
				<div class="empty-card">
					<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
					<h3>No club routes yet</h3>
					<p class="empty-text">
						{#if isAdmin}
							Build the official course on the map, or transfer one of your
							personal routes here so every member can find it.
						{:else}
							Admins post the official courses, alternate routes, and race
							courses here. Build your own under My routes any time.
						{/if}
					</p>
					{#if isAdmin}
						<div class="empty-actions">
							<a href="/routes/new?club={club.id}" class="btn btn-primary">
								<span class="material-symbols" aria-hidden="true">add</span>
								Build a route
							</a>
							<button class="btn btn-outline" type="button" onclick={openTransferModal}>
								<span class="material-symbols" aria-hidden="true">arrow_outward</span>
								Transfer one in
							</button>
						</div>
					{:else}
						<div class="empty-actions">
							<a href="/routes" class="btn btn-outline">
								<span class="material-symbols" aria-hidden="true">route</span>
								Browse my routes
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
											<span>{route.elevation_m} m elev</span>
										{/if}
										<span class="meta-sep">·</span>
										<span class="surface-tag">{route.surface}</span>
										{#if route.is_public}
											<span class="meta-sep">·</span>
											<span class="public-tag">Public</span>
										{/if}
									</div>
								</div>
							</a>
							{#if isAdmin}
								<button
									class="route-remove"
									type="button"
									title="Remove from club (returns to uploader's library)"
									aria-label="Remove route from club"
									onclick={() => removeRouteFromClub(route.id)}
								>
									<span class="material-symbols" aria-hidden="true">link_off</span>
								</button>
							{/if}
						</div>
					{/each}
				</div>
			{/if}
		{:else if tab === 'templates'}
			{#if clubTemplates.length > 0}
				<p class="section-hint">
					Members can clone any template into a personal plan with a start date
					of their choosing. Edits to a clone don't propagate back to the
					template.
				</p>
				<ul class="template-list">
					{#each clubTemplates as t (t.id)}
						<li class="template-row">
							<a href="/plans/{t.id}" class="template-link">
								<strong>{t.name}</strong>
								<span class="template-meta">
									{t.goal_event} · {formatDistance(Number(t.goal_distance_m))}
									· {t.days_per_week}/wk
								</span>
							</a>
							<div class="template-actions">
								{#if isMember}
									<a href="/plans/new?from={t.id}" class="btn btn-primary btn-sm">
										<span class="material-symbols" aria-hidden="true">content_copy</span>
										Adopt
									</a>
								{/if}
								{#if isAdmin}
									<button
										class="btn btn-outline btn-sm"
										type="button"
										onclick={() => unmakeTemplate(t.id)}
										title="Remove from club templates (the plan stays in the author's library)"
									>
										Unpublish
									</button>
								{/if}
							</div>
						</li>
					{/each}
				</ul>
			{:else}
				<div class="empty-card">
					<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
					<h3>No plan templates yet</h3>
					<p class="empty-text">
						{#if isAdmin}
							Templates let members adopt a club-curated training plan with one
							click. Create a plan first, then on its detail page mark it as a
							template for this club.
						{:else}
							When admins publish training plans, members can adopt them with
							one click and start training on a schedule of their choosing.
						{/if}
					</p>
					{#if isAdmin}
						<div class="empty-actions">
							<a href="/plans/new" class="btn btn-primary">
								<span class="material-symbols" aria-hidden="true">add</span>
								Create a plan
							</a>
						</div>
					{/if}
				</div>
			{/if}
		{:else if tab === 'members'}
			{#if members.length === 0}
				<div class="empty-card">
					<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
					<h3>No members yet</h3>
					<p class="empty-text">
						As soon as someone joins, they'll appear here with their role.
					</p>
				</div>
			{:else}
				<div class="member-list">
					{#each members as m (m.user_id)}
						<div class="member">
							<a href="/u/{m.user_id}" class="member-link">
								<div class="avatar-sm" style="--seed: {hashHue(m.user_id)}" aria-hidden="true">
									{initial(m.display_name)}
								</div>
								<div class="member-name">
									<strong>{m.display_name ?? 'Member'}</strong>
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
										aria-label="Change member role"
										onchange={async (e) => {
											const target = e.currentTarget as HTMLSelectElement;
											const newRole = target.value as 'admin' | 'event_organiser' | 'race_director' | 'member';
											if (!club) return;
											try {
												await setMemberRole(club.id, m.user_id, newRole);
												m.role = newRole;
											} catch (err) {
												target.value = m.role;
												showToast('Failed to change role: ' + err, 'error');
											}
										}}
									>
										<option value="admin">Admin</option>
										<option value="event_organiser">Event organiser</option>
										<option value="race_director">Race director</option>
										<option value="member">Member</option>
									</select>
									{#if m.user_id !== auth.user?.id}
										<button
											class="icon-btn danger"
											title="Remove from club"
											aria-label="Remove member"
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
	title="Leave club"
	message={`Leave ${club?.name ?? ''}?`}
	confirmLabel="Leave"
	onconfirm={confirmLeave}
	oncancel={() => showLeaveConfirm = false}
	danger
/>

<ConfirmDialog
	open={showRegenConfirm}
	title="Regenerate invite link"
	message="Generate a new invite link? The current link stops working immediately."
	confirmLabel="Regenerate"
	onconfirm={confirmRegenerate}
	oncancel={() => showRegenConfirm = false}
/>

<ConfirmDialog
	open={showDeletePostConfirm !== null}
	title="Delete post"
	message="Delete this post?"
	confirmLabel="Delete"
	onconfirm={confirmDeletePost}
	oncancel={() => showDeletePostConfirm = null}
	danger
/>

<ConfirmDialog
	open={showDeleteClubConfirm}
	title="Delete club"
	message={`Delete ${club?.name ?? ''}? This removes all events, posts, and members.`}
	confirmLabel="Delete"
	onconfirm={confirmDeleteClub}
	oncancel={() => showDeleteClubConfirm = false}
	danger
/>

<ConfirmDialog
	open={removingMemberId !== null}
	title="Remove member"
	message={`Remove ${members.find((m) => m.user_id === removingMemberId)?.display_name ?? 'this member'} from ${club?.name ?? 'the club'}?`}
	confirmLabel="Remove"
	onconfirm={confirmRemoveMember}
	oncancel={() => (removingMemberId = null)}
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

<Modal
	open={showEventModal && club != null}
	title="New event"
	onclose={() => (showEventModal = false)}
>
	{#if club}
		<EventEditor
			clubId={club.id}
			clubName={club.name}
			oncreated={handleEventCreated}
			oncancel={() => (showEventModal = false)}
		/>
	{/if}
</Modal>

<Modal
	open={showTransferModal}
	title="Transfer route to club"
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
			<p class="muted">You don't have any personal routes that aren't already in a club.</p>
		{:else}
			<label>
				<span>Pick a route</span>
				<select bind:value={transferRouteId} required>
					<option value="">— select —</option>
					{#each transferableRoutes as r (r.id)}
						<option value={r.id}>{r.name} ({formatDistance(r.distance_m)})</option>
					{/each}
				</select>
			</label>
			<p class="hint muted">
				The route's uploader stays the same; ownership and editing rights move to the club's admins.
			</p>
		{/if}
		<div class="transfer-actions">
			<button type="button" class="btn btn-outline" onclick={() => (showTransferModal = false)}>
				Cancel
			</button>
			<button type="submit" class="btn btn-primary" disabled={!transferRouteId}>Transfer</button>
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

	.avatar-lg {
		width: 4.5rem;
		height: 4.5rem;
		border-radius: 50%;
		background: hsl(var(--seed, 260), 55%, 55%);
		color: white;
		display: flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 2rem;
	}

	.avatar-sm {
		width: 2.1rem;
		height: 2.1rem;
		border-radius: 50%;
		background: hsl(var(--seed, 260), 50%, 55%);
		color: white;
		display: flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 0.9rem;
		flex-shrink: 0;
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
		padding-left: 0.6rem;
		border-left: 2px solid var(--color-border);
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
		margin-left: auto;
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
		color: color-mix(in srgb, var(--color-warning) 80%, var(--color-text));
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
		color: color-mix(in srgb, var(--color-warning) 80%, var(--color-text));
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
		right: 0.5rem;
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
