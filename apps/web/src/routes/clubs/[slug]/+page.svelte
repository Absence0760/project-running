<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
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
		approveMember,
		rejectMember,
		setMemberRole,
		regenerateInviteToken,
		joinClub,
		leaveClub,
		createClubPost,
		deleteClubPost,
		deleteClub
	} from '$lib/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
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
	let tab = $state<'feed' | 'events' | 'members'>('feed');

	let draftPost = $state('');
	let postingBusy = $state(false);
	let joinBusy = $state(false);
	let error = $state<string | null>(null);
	let showLeaveConfirm = $state(false);
	let showRegenConfirm = $state(false);
	let showDeleteClubConfirm = $state(false);
	let showDeletePostConfirm = $state<string | null>(null);

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
		const [up, pa, po, me, pe] = await Promise.all([
			fetchUpcomingEvents(club.id),
			fetchPastEvents(club.id, 6),
			fetchClubPosts(club.id, 20),
			fetchClubMembers(club.id),
			club.viewer_role === 'owner' || club.viewer_role === 'admin'
				? fetchPendingRequests(club.id)
				: Promise.resolve([])
		]);
		upcoming = up;
		past = pa;
		posts = po;
		members = me;
		pending = pe;
		loading = false;
	}

	let channel: RealtimeChannel | null = null;

	onMount(async () => {
		await load();
		subscribeRealtime();
	});

	onDestroy(() => {
		if (channel) {
			supabase.removeChannel(channel);
			channel = null;
		}
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

	function subscribeRealtime() {
		if (!club) return;
		channel = supabase
			.channel(`club-${club.id}`)
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
			.subscribe();
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
		if (m == null) return '';
		return `${(m / 1000).toFixed(2)} km`;
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
	<p class="muted centered">Loading…</p>
{:else if !club}
	<div class="not-found">
		<h2>Club not found</h2>
		<p>This club may be private, or it may have been deleted.</p>
		<a href="/clubs" class="btn-secondary">Back to clubs</a>
	</div>
{:else}
	<div class="page">
		<a class="back" href="/clubs">
			<span class="material-symbols">arrow_back</span>
			All clubs
		</a>

		<div class="hero">
			<div class="avatar-lg" style="--seed: {hashHue(club.id)}">
				{initial(club.name)}
			</div>
			<div class="hero-text">
				<div class="hero-title-row">
					<h1>{club.name}</h1>
					{#if !club.is_public}
						<span class="badge">Private</span>
					{/if}
				</div>
				{#if club.location_label}
					<p class="location">
						<span class="material-symbols">place</span>
						{club.location_label}
					</p>
				{/if}
				<p class="members-line">
					<span class="material-symbols">group</span>
					{club.member_count} member{club.member_count === 1 ? '' : 's'}
				</p>
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
					<a class="btn-primary" href="/clubs/{club.slug}/events/new">
						<span class="material-symbols">add</span>
						New event
					</a>
				{/if}
			</div>
		</div>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		{#if isAdmin && (club.join_policy === 'invite' || club.invite_token)}
			<section class="admin-card">
				<div class="admin-card-title">
					<span class="material-symbols">link</span>
					<strong>Invite link</strong>
					<span class="policy-chip">{club.join_policy}</span>
				</div>
				{#if club.invite_token}
					<div class="invite-row">
						<code class="invite-link">{location.origin}/clubs/join/{club.invite_token}</code>
						<button class="btn-ghost" onclick={copyInvite}>
							<span class="material-symbols">content_copy</span>
							Copy
						</button>
						<button class="btn-ghost" onclick={regenerateInvite}>
							<span class="material-symbols">refresh</span>
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
					<span class="material-symbols">hourglass_top</span>
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
							<button class="btn-primary small" onclick={() => approve(p.user_id)}>Approve</button>
							<button class="btn-ghost" onclick={() => reject(p.user_id)}>Reject</button>
						</div>
					{/each}
				</div>
			</section>
		{/if}

		<div class="tabs">
			<button class="tab" class:active={tab === 'feed'} onclick={() => (tab = 'feed')}>Feed</button>
			<button class="tab" class:active={tab === 'events'} onclick={() => (tab = 'events')}>
				Events{upcoming.length ? ` (${upcoming.length})` : ''}
			</button>
			<button class="tab" class:active={tab === 'members'} onclick={() => (tab = 'members')}>
				Members
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
								<span class="material-symbols">calendar_today</span>
								{fmtDate(upcoming[0].starts_at)}
							</span>
							{#if upcoming[0].meet_label}
								<span>
									<span class="material-symbols">place</span>
									{upcoming[0].meet_label}
								</span>
							{/if}
							<span>
								<span class="material-symbols">group</span>
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
				<div class="empty">
					<p>No posts yet.</p>
					{#if isAdmin}
						<p class="hint">Share course changes, weather calls, or post-run plans with members.</p>
					{/if}
				</div>
			{:else}
				<div class="feed">
					{#each posts as post (post.id)}
						<article class="post">
							<div class="post-author">
								<div class="avatar-sm" style="--seed: {hashHue(post.author_id)}">
									{initial(post.author_display_name)}
								</div>
								<div>
									<strong>{post.author_display_name ?? 'Member'}</strong>
									<span class="when">{fmtRelative(post.created_at ?? new Date().toISOString())}</span>
								</div>
								{#if isAdmin}
									<button class="icon-btn" onclick={() => removePost(post.id)} aria-label="Delete post">
										<span class="material-symbols">close</span>
									</button>
								{/if}
							</div>
							<p class="post-body">{post.body}</p>

							{#if club.viewer_role}
								<div class="post-actions">
									<button class="link-btn" onclick={() => toggleReplies(post.id)}>
										<span class="material-symbols">chat_bubble_outline</span>
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
												<div class="avatar-sm" style="--seed: {hashHue(reply.author_id)}">
													{initial(reply.author_display_name)}
												</div>
												<div class="reply-body">
													<div class="reply-head">
														<strong>{reply.author_display_name ?? 'Member'}</strong>
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
												class="btn-primary small"
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
											<span class="material-symbols">place</span>
											{evt.meet_label}
										</span>
									{/if}
									{#if evt.distance_m != null}
										<span>
											<span class="material-symbols">straighten</span>
											{fmtKm(evt.distance_m)}
										</span>
									{/if}
									<span>
										<span class="material-symbols">group</span>
										{evt.attendee_count} going
									</span>
								</div>
							</div>
							{#if evt.viewer_rsvp === 'going'}
								<span class="chip chip-going">Going</span>
							{/if}
						</a>
					{/each}
				</div>
			{:else}
				<div class="empty">
					<p>No upcoming events.</p>
					{#if isAdmin}
						<a href="/clubs/{club.slug}/events/new" class="btn-primary">
							<span class="material-symbols">add</span>
							Create the first one
						</a>
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
										<span class="material-symbols">group</span>
										{evt.attendee_count} attended
									</span>
								</div>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		{:else if tab === 'members'}
			<div class="member-list">
				{#each members as m (m.user_id)}
					<div class="member">
						<div class="avatar-sm" style="--seed: {hashHue(m.user_id)}">
							{initial(m.display_name)}
						</div>
						<div class="member-info">
							<strong>{m.display_name ?? 'Member'}</strong>
							{#if isAdmin && m.role !== 'owner' && m.user_id !== club?.owner_id}
								<select
									class="role-select"
									value={m.role}
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
							{:else}
								<span class="role">{m.role.replace('_', ' ')}</span>
							{/if}
						</div>
					</div>
				{/each}
			</div>
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
{/if}

<style>
	.page {
		max-width: 56rem;
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

	.btn-primary,
	.btn-secondary {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 0.35rem;
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.9rem;
		cursor: pointer;
		text-decoration: none;
	}

	.btn-primary {
		background: var(--color-primary);
		color: var(--color-bg);
		border: none;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--color-primary-hover);
	}

	.btn-primary:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.btn-secondary {
		background: transparent;
		color: var(--color-text);
		border: 1px solid var(--color-border);
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

	.btn-primary.small {
		padding: 0.35rem 0.7rem;
		font-size: 0.85rem;
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
	.member-info .role {
		font-size: 0.75rem;
		text-transform: capitalize;
		color: var(--color-text-secondary);
	}

	.empty {
		padding: var(--space-xl);
		text-align: center;
		color: var(--color-text-secondary);
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-lg);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.75rem;
	}

	.empty .hint {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
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
</style>
