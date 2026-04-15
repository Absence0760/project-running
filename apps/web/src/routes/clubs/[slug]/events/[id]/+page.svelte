<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
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
		type EventResultWithUser,
		type RecentRunOption,
		type RaceSessionRow
	} from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { expandInstances, describeRecurrence } from '$lib/recurrence';
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
	let results = $state<EventResultWithUser[]>([]);
	let showResultPicker = $state(false);
	let runOptions = $state<RecentRunOption[]>([]);
	let submitting = $state(false);
	let raceSession = $state<RaceSessionRow | null>(null);
	let raceBusy = $state(false);
	let nowTick = $state(Date.now());
	let autoApproveOnArm = $state(true);

	/** The instance the user is currently RSVPing to. For one-off events this
	 * stays equal to `event.starts_at`; for recurring events, the user can
	 * pick any of the next N instances. */
	let activeInstance = $state<string | null>(null);

	let nextInstances = $derived(
		event
			? expandInstances(event, new Date(), new Date(Date.now() + 120 * 24 * 3600 * 1000), 6)
			: []
	);

	let recurrenceLabel = $derived(
		event ? describeRecurrence(event.recurrence_freq, event.recurrence_byday) : ''
	);

	let isAdmin = $derived(club?.viewer_role === 'owner' || club?.viewer_role === 'admin');
	let isPast = $derived(
		!!event &&
			(event.recurrence_freq
				? nextInstances.length === 0
				: new Date(event.starts_at).getTime() < Date.now())
	);

	async function load() {
		loading = true;
		[club, event] = await Promise.all([fetchClubBySlug(slug), fetchEventById(eventId)]);
		if (!event) {
			loading = false;
			return;
		}
		activeInstance = event.next_instance_start;
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
			fetchRaceSession(event.id, activeInstance)
		]);
		attendees = res[0];
		route = res[1];
		eventPosts = (res[2] as ClubPostWithAuthor[]).filter(
			(p) => p.event_id === event!.id && (!p.event_instance_start || p.event_instance_start === activeInstance)
		);
		results = res[3];
		raceSession = res[4];
	}

	async function handleArm() {
		if (!event || !activeInstance || raceBusy) return;
		raceBusy = true;
		try {
			raceSession = await armRace(event.id, activeInstance, autoApproveOnArm);
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
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Start failed';
		} finally {
			raceBusy = false;
		}
	}

	async function handleEnd(status: 'finished' | 'cancelled') {
		if (!event || !activeInstance || raceBusy) return;
		if (!confirm(status === 'cancelled' ? 'Cancel the race?' : 'End the race?')) return;
		raceBusy = true;
		try {
			raceSession = await endRace(event.id, activeInstance, status);
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

	function formatRunDate(iso: string): string {
		return new Date(iso).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}

	let myUserId = $derived(auth.user?.id ?? null);
	let hasMyResult = $derived(
		myUserId !== null && results.some((r) => r.user_id === myUserId)
	);

	async function pickInstance(iso: string) {
		activeInstance = iso;
		await reloadInstance();
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

	function subscribeRealtime() {
		if (!event || !club) return;
		channel = supabase
			.channel(`event-${event.id}`)
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
			.subscribe();
	}

	async function rsvp(status: RsvpStatus) {
		if (!event || !activeInstance || busy) return;
		busy = true;
		try {
			// `viewer_rsvp` only reflects the NEXT instance; when the user is
			// viewing a later instance we don't compare against it.
			const shouldClear =
				activeInstance === event.next_instance_start && event.viewer_rsvp === status;
			if (shouldClear) {
				await clearRsvp(event.id, activeInstance);
			} else {
				await rsvpEvent(event.id, status, activeInstance);
			}
			await load(); // reload for updated counts
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'RSVP failed';
		} finally {
			busy = false;
		}
	}

	async function handleDeleteEvent() {
		if (!event) return;
		if (!confirm(`Delete "${event.title}"?${event.recurrence_freq ? ' All occurrences will be removed.' : ''}`)) return;
		await deleteEvent(event.id);
		goto(`/clubs/${slug}`);
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
				{#if event.recurrence_freq}
					<p class="recurrence-label">
						<span class="material-symbols">autorenew</span>
						{recurrenceLabel}
					</p>
				{/if}
				<p class="date-line">
					<span class="material-symbols">calendar_today</span>
					{fmtDate(activeInstance ?? event.starts_at)}
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

		{#if event.recurrence_freq && nextInstances.length > 1}
			<section class="instance-picker">
				<span class="label">Pick an occurrence</span>
				<div class="instance-chips">
					{#each nextInstances as iso}
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
			</section>
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

		{#if isAdmin}
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
					{#each results as r (r.user_id)}
						<li class="result" class:me={r.user_id === myUserId} class:pending={!r.organiser_approved}>
							<span class="rank">{r.organiser_approved ? (r.rank ?? '—') : '…'}</span>
							<div class="avatar-sm" style="--seed: {hashHue(r.user_id)}">
								{initial(r.display_name)}
							</div>
							<div class="res-info">
								<strong>{r.display_name ?? 'Runner'}</strong>
								{#if r.user_id === myUserId}<span class="you">(you)</span>{/if}
								{#if !r.organiser_approved}<span class="pending-tag">PENDING</span>{/if}
								{#if r.finisher_status !== 'finished'}
									<span class="dnf-tag">{r.finisher_status.toUpperCase()}</span>
								{/if}
							</div>
							{#if r.finisher_status === 'finished'}
								<span class="time">{formatDuration(r.duration_s)}</span>
								<span class="dist muted">{(r.distance_m / 1000).toFixed(2)} km</span>
							{/if}
							{#if isAdmin && !r.organiser_approved}
								<button type="button" class="btn-link approve" onclick={() => handleApprove(r.user_id, true)}>Approve</button>
							{:else if isAdmin && r.organiser_approved && r.user_id !== myUserId}
								<button type="button" class="btn-link reject" onclick={() => handleApprove(r.user_id, false)}>Unverify</button>
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
										<span class="run-dist">{(run.distance_m / 1000).toFixed(2)} km</span>
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

	.recurrence-label {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		margin: 0.4rem 0 0 0;
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-primary);
		font-weight: 700;
	}

	.recurrence-label .material-symbols {
		font-size: 1rem;
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
	.btn-danger {
		padding: 0.35rem 0.75rem;
		font-size: 0.85rem;
		border-radius: var(--radius-md);
		background: var(--color-danger);
		color: white;
		border: none;
		font-weight: 600;
		cursor: pointer;
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
</style>
