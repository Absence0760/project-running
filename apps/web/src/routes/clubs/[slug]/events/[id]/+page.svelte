<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import {
		fetchEventById,
		fetchClubBySlug,
		fetchEventAttendees,
		fetchClubPosts,
		fetchRouteById,
		rsvpEvent,
		clearRsvp,
		deleteEvent,
		createClubPost
	} from '$lib/data';
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
	let attendees = $state<(EventAttendee & { display_name: string | null; avatar_url: string | null })[]>([]);
	let eventPosts = $state<ClubPostWithAuthor[]>([]);
	let route = $state<Route | null>(null);
	let loading = $state(true);
	let busy = $state(false);
	let error = $state<string | null>(null);
	let draftPost = $state('');

	let isAdmin = $derived(club?.viewer_role === 'owner' || club?.viewer_role === 'admin');
	let isPast = $derived(!!event && new Date(event.starts_at).getTime() < Date.now());

	async function load() {
		loading = true;
		[club, event] = await Promise.all([fetchClubBySlug(slug), fetchEventById(eventId)]);
		if (!event) {
			loading = false;
			return;
		}
		const results = await Promise.all([
			fetchEventAttendees(eventId),
			event.route_id ? fetchRouteById(event.route_id) : Promise.resolve(null),
			club ? fetchClubPosts(club.id, 50) : Promise.resolve([])
		]);
		attendees = results[0];
		route = results[1];
		eventPosts = (results[2] as ClubPostWithAuthor[]).filter((p) => p.event_id === eventId);
		loading = false;
	}

	onMount(load);

	async function rsvp(status: RsvpStatus) {
		if (!event || busy) return;
		busy = true;
		try {
			if (event.viewer_rsvp === status) {
				await clearRsvp(event.id);
			} else {
				await rsvpEvent(event.id, status);
			}
			await load();
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'RSVP failed';
		} finally {
			busy = false;
		}
	}

	async function handleDeleteEvent() {
		if (!event) return;
		if (!confirm(`Delete "${event.title}"?`)) return;
		await deleteEvent(event.id);
		goto(`/clubs/${slug}`);
	}

	async function submitPost(e: Event) {
		e.preventDefault();
		if (!club || !event || !draftPost.trim() || busy) return;
		busy = true;
		try {
			await createClubPost({
				club_id: club.id,
				event_id: event.id,
				body: draftPost
			});
			draftPost = '';
			eventPosts = (await fetchClubPosts(club.id, 50)).filter((p) => p.event_id === event!.id);
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
	<p class="centered muted">Loading…</p>
{:else if !event || !club}
	<div class="centered">
		<h2>Event not found</h2>
		<a href="/clubs/{slug}" class="btn-secondary">Back to club</a>
	</div>
{:else}
	<div class="page">
		<a class="back" href="/clubs/{slug}">
			<span class="material-symbols">arrow_back</span>
			Back to {club.name}
		</a>

		{#if isPast}
			<div class="banner past">This event has already happened.</div>
		{/if}

		<header class="hero">
			<div class="hero-left">
				<h1>{event.title}</h1>
				<p class="date-line">
					<span class="material-symbols">calendar_today</span>
					{fmtDate(event.starts_at)}
					{#if event.duration_min}
						<span class="muted">· {event.duration_min} min</span>
					{/if}
				</p>
				{#if event.meet_label}
					<p class="meet">
						<span class="material-symbols">place</span>
						{event.meet_label}
					</p>
				{/if}
				{#if event.description}
					<p class="desc">{event.description}</p>
				{/if}

				<div class="metrics">
					{#if event.distance_m != null}
						<div class="metric">
							<span class="label">Distance</span>
							<span class="value">{(event.distance_m / 1000).toFixed(2)} km</span>
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
					</div>
				</div>

				{#if route}
					<a class="route-chip" href="/routes/{route.id}">
						<span class="material-symbols">route</span>
						{route.name}
						<span class="muted">— {(route.distance_m / 1000).toFixed(2)} km</span>
					</a>
				{/if}
			</div>
			<div class="hero-actions">
				{#if !isPast}
					<button
						class="btn-primary"
						class:filled={event.viewer_rsvp === 'going'}
						onclick={() => rsvp('going')}
						disabled={busy}
					>
						{event.viewer_rsvp === 'going' ? 'Going' : "I'm in"}
					</button>
					<button
						class="btn-secondary"
						class:active={event.viewer_rsvp === 'maybe'}
						onclick={() => rsvp('maybe')}
						disabled={busy}
					>
						Maybe
					</button>
					<button
						class="btn-secondary"
						class:active={event.viewer_rsvp === 'declined'}
						onclick={() => rsvp('declined')}
						disabled={busy}
					>
						Can't make it
					</button>
				{/if}
				{#if isAdmin}
					<button class="btn-secondary danger" onclick={handleDeleteEvent}>Delete event</button>
				{/if}
			</div>
		</header>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		{#if isAdmin}
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

		<section class="card">
			<h3>Attendees ({attendees.length})</h3>
			{#if attendees.length === 0}
				<p class="muted">No RSVPs yet — be the first.</p>
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
{/if}

<style>
	.page {
		max-width: 56rem;
		margin: 0 auto;
		padding: var(--space-xl);
	}

	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
	}

	.banner {
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		padding: 0.5rem 0.85rem;
		border-radius: var(--radius-md);
		margin-bottom: var(--space-md);
		font-size: 0.9rem;
	}

	.hero {
		display: grid;
		grid-template-columns: 1fr auto;
		gap: var(--space-lg);
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-lg);
	}

	.hero h1 {
		font-size: 1.6rem;
		margin: 0;
	}

	.date-line,
	.meet {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		color: var(--color-text-secondary);
		margin: 0.5rem 0 0 0;
	}

	.date-line .material-symbols,
	.meet .material-symbols {
		font-size: 1.05rem;
	}

	.desc {
		margin-top: 0.75rem;
		line-height: 1.55;
		white-space: pre-wrap;
	}

	.metrics {
		display: flex;
		gap: 2rem;
		margin-top: 1rem;
	}

	.metric .label {
		display: block;
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
	}

	.metric .value {
		font-size: 1.1rem;
		font-weight: 700;
	}

	.route-chip {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: var(--color-primary-light);
		color: var(--color-primary);
		padding: 0.4rem 0.85rem;
		border-radius: var(--radius-md);
		margin-top: 1rem;
		font-weight: 600;
		font-size: 0.9rem;
	}

	.hero-actions {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		min-width: 10rem;
	}

	.btn-primary {
		background: var(--color-primary);
		color: var(--color-bg);
		padding: 0.6rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: none;
		cursor: pointer;
	}

	.btn-primary.filled {
		background: var(--color-primary-hover);
	}

	.btn-primary:disabled {
		opacity: 0.6;
	}

	.btn-secondary {
		background: transparent;
		color: var(--color-text);
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: 1px solid var(--color-border);
		cursor: pointer;
	}

	.btn-secondary.active {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.btn-secondary.danger {
		color: var(--color-danger);
		border-color: var(--color-danger-light);
	}

	.btn-secondary.danger:hover {
		background: var(--color-danger-light);
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
</style>
