<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { m } from '$lib/i18n/store.svelte';
	import { formatDuration } from '$lib/format/time';
	import {
		fetchEventById,
		fetchEventCheckpoints,
		fetchPublicCrossings,
		fetchRaceSession,
		type EventCheckpoint
	} from '$lib/core/data';
	import { buildBoard, type BoardCheckpoint, type BoardRunner } from '$lib/runs/checkpoint_board';
	import type { EventWithMeta } from '$lib/types';

	let eventId = $derived($page.params.id as string);
	// Optional ?instance= for a recurring event; defaults to the event start.
	let instanceParam = $derived($page.url.searchParams.get('instance') ?? '');

	let event = $state<EventWithMeta | null>(null);
	let checkpoints = $state<EventCheckpoint[]>([]);
	let board = $state<BoardRunner[]>([]);
	let loading = $state(true);
	let notFound = $state(false);

	let boardCheckpoints = $derived<BoardCheckpoint[]>(
		checkpoints.map((c) => ({
			id: c.id,
			name: c.name,
			ordinal: c.ordinal,
			positionM: c.position_m,
			cutoffElapsedS: c.cutoff_elapsed_s
		}))
	);

	async function load() {
		loading = true;
		notFound = false;
		try {
			const ev = await fetchEventById(eventId);
			// RLS hides a private event's row from a non-member / anon viewer —
			// fetchEventById returns null, so render the not-found state.
			if (!ev) {
				notFound = true;
				return;
			}
			event = ev;
			const instanceStart = instanceParam || ev.starts_at;
			const [cps, session] = await Promise.all([
				fetchEventCheckpoints(eventId),
				fetchRaceSession(eventId, instanceStart)
			]);
			checkpoints = cps;
			const raceStartMs = new Date(session?.started_at ?? instanceStart).getTime();
			const crossings = await fetchPublicCrossings(eventId, instanceStart);
			board = buildBoard(
				boardCheckpoints,
				crossings.map((c) => ({
					checkpointId: c.checkpoint_id,
					userId: c.user_id,
					bib: c.bib,
					runnerName: c.runner_name,
					inTime: c.in_time
				})),
				raceStartMs
			);
		} catch {
			notFound = true;
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function runnerName(r: BoardRunner): string {
		if (r.name) return r.name;
		if (r.bib) return m('checkpoint.unknownRunner', { bib: r.bib });
		return m('checkpoint.anonymousRunner');
	}

	function statusLabel(s: string): string {
		return s === 'finished'
			? m('checkpoint.statusFinished')
			: s === 'dnf'
				? m('checkpoint.statusDnf')
				: m('checkpoint.statusRacing');
	}

	function legActual(r: BoardRunner, checkpointId: string): string {
		const leg = r.projection.legs.find((l) => l.checkpointId === checkpointId);
		if (leg?.reached && leg.actualElapsedS != null) {
			return formatDuration(Math.round(leg.actualElapsedS));
		}
		return m('checkpoint.notReached');
	}
</script>

<svelte:head>
	<title>{event ? `${event.title} — ${m('checkpoint.publicTitle')}` : m('checkpoint.publicTitle')}</title>
	<meta name="description" content={m('checkpoint.publicSplits')} />
</svelte:head>

<div class="results-page">
	{#if loading}
		<p class="muted">{m('checkpoint.publicLoading')}</p>
	{:else if notFound}
		<div class="empty-card">
			<img src="/icon-192.png" alt="" width="56" height="56" class="empty-mark" />
			<h3>{m('checkpoint.publicTitle')}</h3>
			<p class="empty-text">{m('checkpoint.publicNotFound')}</p>
		</div>
	{:else}
		<header class="rp-head">
			<h1>{event?.title}</h1>
			<p class="rp-sub">{m('checkpoint.publicTitle')}</p>
		</header>

		{#if board.length === 0}
			<div class="empty-card"><p class="empty-text">{m('checkpoint.publicEmpty')}</p></div>
		{:else}
			<p class="rp-count">{m('checkpoint.publicFinishers', { n: board.length })}</p>
			<div class="board-scroll">
				<table class="results" data-testid="public-results">
					<thead>
						<tr>
							<th>#</th>
							<th>{m('checkpoint.boardRunner')}</th>
							<th>{m('checkpoint.boardStatus')}</th>
							{#each checkpoints as cp (cp.id)}
								<th class="col-cp">{cp.name}</th>
							{/each}
						</tr>
					</thead>
					<tbody>
						{#each board as r, i (r.key)}
							<tr data-testid="public-results-row" class:dnf={r.projection.status === 'dnf'}>
								<td class="rank">{i + 1}</td>
								<td>
									<strong>{runnerName(r)}</strong>
									{#if r.bib}<span class="bib-tag">#{r.bib}</span>{/if}
								</td>
								<td><span class="status-chip status-{r.projection.status}">{statusLabel(r.projection.status)}</span></td>
								{#each checkpoints as cp (cp.id)}
									<td class="col-cp">{legActual(r, cp.id)}</td>
								{/each}
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	{/if}
</div>

<style>
	.results-page {
		max-width: 72rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-lg);
	}
	.rp-head h1 {
		margin: 0;
	}
	.rp-sub {
		margin: 0.25rem 0 0;
		color: var(--text-muted);
	}
	.rp-count {
		color: var(--text-muted);
		font-size: 0.9rem;
	}
	.board-scroll {
		overflow-x: auto;
	}
	.results {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}
	.results th,
	.results td {
		text-align: start;
		padding: 0.5rem 0.6rem;
		border-bottom: 1px solid var(--border);
		white-space: nowrap;
	}
	.results th {
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--text-muted);
	}
	.rank {
		font-weight: 700;
		color: var(--text-muted);
	}
	.bib-tag {
		margin-inline-start: 0.4rem;
		color: var(--text-muted);
		font-weight: 400;
	}
	tr.dnf strong {
		text-decoration: line-through;
		color: var(--text-muted);
	}
	.status-chip {
		display: inline-block;
		padding: 0.05rem 0.45rem;
		border-radius: var(--radius-pill, 999px);
		font-size: 0.75rem;
		font-weight: 700;
	}
	.status-racing {
		background: var(--surface-2);
		color: var(--text);
	}
	.status-finished {
		background: color-mix(in srgb, var(--success, #16a34a) 16%, transparent);
		color: var(--success, #16a34a);
	}
	.status-dnf {
		background: color-mix(in srgb, var(--danger, #dc2626) 16%, transparent);
		color: var(--danger, #dc2626);
	}
</style>
