<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { supabase } from '$lib/supabase';
	import {
		fetchLatestRacePings,
		fetchRaceSession,
		fetchEventById,
		fetchEventResults,
		type RacePingRow,
		type RaceSessionRow,
		type EventResultWithUser
	} from '$lib/data';
	import type { EventWithMeta } from '$lib/types';
	import type { RealtimeChannel } from '@supabase/supabase-js';

	// Route params: event id + ISO `instance_start`. The instance value
	// is URL-encoded by the organiser's "Spectator view" link on the
	// event page.
	let eventId = $derived($page.params.id as string);
	let instance = $derived(decodeURIComponent($page.params.instance as string));

	let event = $state<EventWithMeta | null>(null);
	let race = $state<RaceSessionRow | null>(null);
	let pings = $state<RacePingRow[]>([]);
	let results = $state<EventResultWithUser[]>([]);
	let profiles = $state<Map<string, { display_name: string | null }>>(new Map());
	let nowTick = $state(Date.now());
	let loading = $state(true);

	let channel: RealtimeChannel | null = null;

	async function load() {
		const [e, rs, ps, rr] = await Promise.all([
			fetchEventById(eventId),
			fetchRaceSession(eventId, instance),
			fetchLatestRacePings(eventId, instance),
			fetchEventResults(eventId, instance)
		]);
		event = e;
		race = rs;
		pings = ps;
		results = rr;
		// Collect display names for every user_id referenced by pings + results.
		const ids = new Set<string>();
		for (const p of ps) ids.add(p.user_id);
		for (const r of rr) ids.add(r.user_id);
		if (ids.size > 0) {
			const { data } = await supabase
				.from('user_profiles')
				.select('id, display_name')
				.in('id', [...ids]);
			const map = new Map<string, { display_name: string | null }>();
			for (const p of data ?? []) map.set(p.id, { display_name: p.display_name });
			profiles = map;
		}
		loading = false;
	}

	function subscribe() {
		channel = supabase
			.channel(`live-event-${eventId}-${instance}`)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'race_pings',
					filter: `event_id=eq.${eventId}`
				},
				async () => {
					pings = await fetchLatestRacePings(eventId, instance);
				}
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'race_sessions',
					filter: `event_id=eq.${eventId}`
				},
				async () => {
					race = await fetchRaceSession(eventId, instance);
				}
			)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'event_results',
					filter: `event_id=eq.${eventId}`
				},
				async () => {
					results = await fetchEventResults(eventId, instance);
				}
			)
			.subscribe();
	}

	onMount(async () => {
		await load();
		subscribe();
	});

	onDestroy(() => {
		if (channel) supabase.removeChannel(channel);
	});

	let tickTimer: ReturnType<typeof setInterval> | null = null;
	$effect(() => {
		if (race?.status === 'running') {
			tickTimer = setInterval(() => (nowTick = Date.now()), 1000);
			return () => {
				if (tickTimer) clearInterval(tickTimer);
				tickTimer = null;
			};
		}
	});

	let raceElapsedS = $derived(
		race?.status === 'running' && race.started_at
			? Math.max(0, Math.floor((nowTick - new Date(race.started_at).getTime()) / 1000))
			: race?.status === 'finished' && race.started_at && race.finished_at
			? Math.max(
					0,
					Math.floor(
						(new Date(race.finished_at).getTime() -
							new Date(race.started_at).getTime()) /
							1000
					)
			  )
			: 0
	);

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

	function paceSecPerKm(p: RacePingRow): number | null {
		if (!p.distance_m || p.distance_m < 50 || !p.elapsed_s || p.elapsed_s < 10) return null;
		return p.elapsed_s / (p.distance_m / 1000);
	}

	function formatPace(secPerKm: number | null): string {
		if (secPerKm === null) return '—';
		const m = Math.floor(secPerKm / 60);
		const s = Math.round(secPerKm % 60);
		return `${m}:${s.toString().padStart(2, '0')}/km`;
	}

	function nameFor(userId: string): string {
		return profiles.get(userId)?.display_name ?? 'Runner';
	}
</script>

<svelte:head>
	<title>Live race — {event?.title ?? 'Event'}</title>
</svelte:head>

<div class="page">
	<header>
		<h1>{event?.title ?? 'Live race'}</h1>
		{#if race}
			<p class="status-row">
				<span class="status-dot status-{race.status}"></span>
				<strong>{race.status.toUpperCase()}</strong>
				{#if race.status === 'running' || race.status === 'finished'}
					· elapsed {formatDuration(raceElapsedS)}
				{/if}
			</p>
		{:else}
			<p class="muted">No race session yet for this instance.</p>
		{/if}
	</header>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else}
		<section class="card">
			<h2>Runners on course ({pings.length})</h2>
			{#if pings.length === 0}
				<p class="muted">No live position data yet. Runners' watches / phones will push pings every ~10 seconds once the race starts.</p>
			{:else}
				<ol class="runners">
					{#each pings as p, i (p.user_id)}
						<li class="runner">
							<span class="pos">{i + 1}</span>
							<span class="name">{nameFor(p.user_id)}</span>
							<span class="dist">{((p.distance_m ?? 0) / 1000).toFixed(2)} km</span>
							<span class="pace">{formatPace(paceSecPerKm(p))}</span>
							<span class="elapsed">{formatDuration(p.elapsed_s ?? 0)}</span>
						</li>
					{/each}
				</ol>
			{/if}
		</section>

		{#if results.length > 0}
			<section class="card">
				<h2>Finished ({results.filter((r) => r.finisher_status === 'finished').length})</h2>
				<ol class="runners">
					{#each results as r (r.user_id)}
						<li class="runner" class:pending={!r.organiser_approved}>
							<span class="pos">{r.organiser_approved ? (r.rank ?? '—') : '…'}</span>
							<span class="name">{nameFor(r.user_id)}</span>
							{#if r.finisher_status !== 'finished'}
								<span class="dnf">{r.finisher_status.toUpperCase()}</span>
							{:else}
								<span class="dist">{(r.distance_m / 1000).toFixed(2)} km</span>
								<span class="elapsed">{formatDuration(r.duration_s)}</span>
							{/if}
							{#if !r.organiser_approved}
								<span class="pending-tag">PENDING</span>
							{/if}
						</li>
					{/each}
				</ol>
			</section>
		{/if}
	{/if}
</div>

<style>
	.page {
		max-width: 48rem;
		margin: 0 auto;
		padding: 1.5rem;
	}
	h1 {
		font-size: 1.6rem;
		font-weight: 700;
		margin: 0 0 0.3rem;
	}
	h2 {
		font-size: 0.9rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-secondary);
		margin-bottom: 0.8rem;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: 0.6rem;
		padding: 1rem;
		margin-bottom: 1.2rem;
	}
	.status-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	.status-dot {
		display: inline-block;
		width: 0.65rem;
		height: 0.65rem;
		border-radius: 50%;
	}
	.status-armed { background: #f59e0b; }
	.status-running {
		background: #10b981;
		animation: pulse 1s infinite;
	}
	.status-finished { background: #6b7280; }
	.status-cancelled { background: #ef4444; }
	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.4; }
	}
	.runners {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.runner {
		display: grid;
		grid-template-columns: 2rem 1fr auto auto auto auto;
		align-items: center;
		gap: 0.8rem;
		padding: 0.5rem 0.7rem;
		background: var(--color-bg);
		border-radius: 0.4rem;
		font-size: 0.9rem;
	}
	.runner.pending { opacity: 0.7; }
	.pos {
		font-weight: 700;
		color: var(--color-primary);
		font-variant-numeric: tabular-nums;
	}
	.name {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.dist, .pace, .elapsed {
		font-variant-numeric: tabular-nums;
		color: var(--color-text-secondary);
	}
	.elapsed {
		font-weight: 600;
		color: var(--color-text);
	}
	.dnf {
		color: var(--color-danger);
		font-weight: 700;
		font-size: 0.75rem;
	}
	.pending-tag {
		background: #fff3cd;
		color: #856404;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.1rem 0.35rem;
		border-radius: 0.3rem;
		letter-spacing: 0.04em;
	}
	.muted { color: var(--color-text-tertiary); }
</style>
