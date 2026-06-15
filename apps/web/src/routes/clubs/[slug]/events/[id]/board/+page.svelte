<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { formatDuration } from '$lib/format/time';
	import { formatDistance, formatWeight, parseWeight, getUnit } from '$lib/format/units.svelte';
	import { isWeighInEnabled } from '$lib/runs/weigh_in_flag';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import {
		fetchEventById,
		fetchEventCheckpoints,
		fetchOrganiserCrossings,
		fetchRaceSession,
		upsertCheckpointCrossing,
		markCheckpointDnf,
		type EventCheckpoint,
		type OrganiserCrossing
	} from '$lib/core/data';
	import { buildBoard, type BoardCheckpoint, type BoardRunner } from '$lib/runs/checkpoint_board';
	import type { EventWithMeta } from '$lib/types';

	let slug = $derived($page.params.slug as string);
	let eventId = $derived($page.params.id as string);
	let instanceStart = $derived($page.url.searchParams.get('instance') ?? '');

	let event = $state<EventWithMeta | null>(null);
	let checkpoints = $state<EventCheckpoint[]>([]);
	let crossings = $state<OrganiserCrossing[]>([]);
	let raceStartIso = $state<string | null>(null);
	let loading = $state(true);
	let denied = $state(false);
	let busy = $state<string | null>(null);

	const weighInEnabled = isWeighInEnabled();

	let boardCheckpoints = $derived<BoardCheckpoint[]>(
		checkpoints.map((c) => ({
			id: c.id,
			name: c.name,
			ordinal: c.ordinal,
			positionM: c.position_m,
			cutoffElapsedS: c.cutoff_elapsed_s
		}))
	);

	let raceStartMs = $derived(
		raceStartIso ? new Date(raceStartIso).getTime() : instanceStart ? new Date(instanceStart).getTime() : Date.now()
	);

	// Per-identity latest health snapshot (for the weigh-in column), keyed the
	// same way buildBoard keys runners.
	let healthByKey = $derived.by(() => {
		const map = new Map<string, OrganiserCrossing>();
		for (const c of crossings) {
			const key = c.user_id ?? `bib:${c.bib ?? ''}`;
			const prev = map.get(key);
			// Keep the most recent crossing that carries any health signal.
			const hasHealth = c.body_weight_kg != null || c.medical_hold;
			if (hasHealth && (!prev || c.updated_at > prev.updated_at)) map.set(key, c);
		}
		return map;
	});

	let board = $derived<BoardRunner[]>(
		buildBoard(
			boardCheckpoints,
			crossings.map((c) => ({
				checkpointId: c.checkpoint_id,
				userId: c.user_id,
				bib: c.bib,
				runnerName: c.runner_name,
				inTime: c.in_time
			})),
			raceStartMs
		)
	);

	async function load() {
		loading = true;
		denied = false;
		try {
			const [ev, cps, session] = await Promise.all([
				fetchEventById(eventId),
				fetchEventCheckpoints(eventId),
				instanceStart ? fetchRaceSession(eventId, instanceStart) : Promise.resolve(null)
			]);
			event = ev;
			checkpoints = cps;
			raceStartIso = session?.started_at ?? (instanceStart || null);
			// The organiser RPC throws 42501 for non-organisers.
			crossings = await fetchOrganiserCrossings(eventId, instanceStart);
		} catch (e) {
			const msg = e instanceof Error ? e.message : '';
			if (/42501|organiser|permission/i.test(msg)) {
				denied = true;
			} else {
				showToast(m('checkpoint.loadFailed'), 'error');
			}
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		await load();
	});

	function runnerName(r: BoardRunner): string {
		if (r.name) return r.name;
		if (r.bib) return m('checkpoint.unknownRunner', { bib: r.bib });
		return m('checkpoint.anonymousRunner');
	}

	function legActual(r: BoardRunner, checkpointId: string): string {
		const leg = r.projection.legs.find((l) => l.checkpointId === checkpointId);
		if (!leg) return m('checkpoint.notReached');
		if (leg.reached && leg.actualElapsedS != null) {
			return m('checkpoint.reachedAt', { time: formatDuration(Math.round(leg.actualElapsedS)) });
		}
		if (leg.projectedElapsedS != null) {
			return m('checkpoint.projectedAt', { time: formatDuration(Math.round(leg.projectedElapsedS)) });
		}
		return m('checkpoint.notReached');
	}

	function legVerdict(r: BoardRunner, checkpointId: string): string | null {
		const leg = r.projection.legs.find((l) => l.checkpointId === checkpointId);
		if (!leg?.cutoff) return null;
		return leg.cutoff.status;
	}

	function statusLabel(s: string): string {
		return s === 'finished'
			? m('checkpoint.statusFinished')
			: s === 'dnf'
				? m('checkpoint.statusDnf')
				: m('checkpoint.statusRacing');
	}

	// DNF marking
	let dnfTarget = $state<BoardRunner | null>(null);
	async function confirmDnf() {
		const r = dnfTarget;
		dnfTarget = null;
		if (!r) return;
		busy = r.key;
		try {
			await markCheckpointDnf({
				eventId,
				instanceStart,
				userId: r.userId,
				bib: r.bib,
				runnerName: r.name
			});
			showToast(m('checkpoint.statusDnf'), 'success');
			await load();
		} catch (e) {
			showToast(e instanceof Error ? e.message : m('checkpoint.markDnfFailed'), 'error');
		} finally {
			busy = null;
		}
	}

	// Weigh-in entry (gated). Records a crossing at the runner's last reached
	// checkpoint with health fields + explicit consent.
	let weighTarget = $state<BoardRunner | null>(null);
	let wWeight = $state<number | null>(null);
	let wMedicalHold = $state(false);
	let wNote = $state('');
	let wConsent = $state(false);

	function openWeighIn(r: BoardRunner) {
		weighTarget = r;
		const existing = healthByKey.get(r.key);
		wWeight = existing?.body_weight_kg ?? null;
		wMedicalHold = existing?.medical_hold ?? false;
		wNote = existing?.medical_note ?? '';
		wConsent = false;
	}

	async function saveWeighIn() {
		const r = weighTarget;
		if (!r || busy) return;
		if (!wConsent) {
			showToast(m('checkpoint.healthConsentRequired'), 'error');
			return;
		}
		const checkpointId = r.projection.lastCheckpointId ?? checkpoints[0]?.id;
		if (!checkpointId) return;
		const kg = wWeight != null ? parseWeight(wWeight) : null;
		busy = r.key;
		try {
			await upsertCheckpointCrossing({
				eventId,
				checkpointId,
				instanceStart,
				userId: r.userId,
				bib: r.bib,
				runnerName: r.name,
				healthConsent: true,
				bodyWeightKg: kg,
				medicalHold: wMedicalHold,
				medicalNote: wNote.trim() || null
			});
			weighTarget = null;
			showToast(m('checkpoint.weighInSaved'), 'success');
			await load();
		} catch (e) {
			showToast(e instanceof Error ? e.message : m('checkpoint.weighInFailed'), 'error');
		} finally {
			busy = null;
		}
	}
</script>

<svelte:head><title>{m('checkpoint.boardTitle')}</title></svelte:head>

<div class="page board-page">
	<a class="back" href={`/clubs/${slug}/events/${eventId}`}>
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('checkpoint.backToEvent')}
	</a>

	{#if loading}
		<p class="muted">{m('shell.loading')}</p>
	{:else if denied}
		<div class="empty-card">
			<h3>{m('checkpoint.boardTitle')}</h3>
			<p class="empty-text">{m('checkpoint.notOrganiser')}</p>
		</div>
	{:else}
		<header class="board-head">
			<div>
				<h1>{m('checkpoint.boardTitle')}</h1>
				{#if event}<p class="board-sub">{event.title}</p>{/if}
			</div>
			<button type="button" class="btn btn-secondary" onclick={load} disabled={busy !== null}>
				<span class="material-symbols" aria-hidden="true">refresh</span>
				{m('checkpoint.refresh')}
			</button>
		</header>

		{#if checkpoints.length === 0}
			<div class="empty-card"><p class="empty-text">{m('checkpoint.boardNoCheckpoints')}</p></div>
		{:else if board.length === 0}
			<div class="empty-card"><p class="empty-text">{m('checkpoint.boardEmpty')}</p></div>
		{:else}
			<div class="board-scroll">
				<table class="board" data-testid="board-table">
					<thead>
						<tr>
							<th class="col-runner">{m('checkpoint.boardRunner')}</th>
							<th>{m('checkpoint.boardStatus')}</th>
							{#each checkpoints as cp (cp.id)}
								<th class="col-cp">{cp.name}</th>
							{/each}
							{#if weighInEnabled}<th>{m('checkpoint.weighInTitle')}</th>{/if}
							<th></th>
						</tr>
					</thead>
					<tbody>
						{#each board as r (r.key)}
							<tr data-testid="board-row" class:dnf={r.projection.status === 'dnf'}>
								<td class="col-runner">
									<strong>{runnerName(r)}</strong>
									{#if r.bib}<span class="bib-tag">#{r.bib}</span>{/if}
								</td>
								<td>
									<span class="status-chip status-{r.projection.status}">{statusLabel(r.projection.status)}</span>
									{#if weighInEnabled && healthByKey.get(r.key)?.medical_hold}
										<span class="status-chip hold">{m('checkpoint.medicalHoldBadge')}</span>
									{/if}
								</td>
								{#each checkpoints as cp (cp.id)}
									{@const verdict = legVerdict(r, cp.id)}
									<td class="col-cp">
										<span class="leg-time">{legActual(r, cp.id)}</span>
										{#if verdict}
											<span class="verdict verdict-{verdict}">
												{verdict === 'safe'
													? m('checkpoint.verdictSafe')
													: verdict === 'tight'
														? m('checkpoint.verdictTight')
														: m('checkpoint.verdictMiss')}
											</span>
										{/if}
									</td>
								{/each}
								{#if weighInEnabled}
									{@const h = healthByKey.get(r.key)}
									<td>
										{#if h?.body_weight_kg != null}
											<span class="leg-time">{formatWeight(h.body_weight_kg)}</span>
										{/if}
										<button type="button" class="btn-link" onclick={() => openWeighIn(r)} disabled={busy !== null}>
											{m('checkpoint.recordWeighIn')}
										</button>
									</td>
								{/if}
								<td>
									{#if r.projection.status !== 'dnf'}
										<button type="button" class="btn-link danger" onclick={() => (dnfTarget = r)} disabled={busy !== null} data-testid="mark-dnf">
											{m('checkpoint.markDnf')}
										</button>
									{/if}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	{/if}
</div>

<ConfirmDialog
	open={dnfTarget !== null}
	title={m('checkpoint.markDnfTitle')}
	message={dnfTarget ? m('checkpoint.markDnfBody', { name: runnerName(dnfTarget) }) : ''}
	confirmLabel={m('checkpoint.markDnf')}
	cancelLabel={m('checkpoint.cancel')}
	danger
	onconfirm={confirmDnf}
	oncancel={() => (dnfTarget = null)}
/>

{#if weighInEnabled}
	<Modal
		open={weighTarget !== null}
		onclose={() => (weighTarget = null)}
		title={m('checkpoint.weighInTitle')}
		narrow
		data-testid="weigh-in-modal"
	>
		<form class="editor-form" onsubmit={(e) => { e.preventDefault(); saveWeighIn(); }}>
			<label>
				{m('checkpoint.bodyWeightLabel', { unit: getUnit() === 'mi' ? 'lbs' : 'kg' })}
				<input type="number" inputmode="decimal" step="0.1" min="0" bind:value={wWeight} />
			</label>
			<label class="toggle-row">
				<input type="checkbox" bind:checked={wMedicalHold} />
				<span><strong>{m('checkpoint.medicalHold')}</strong></span>
			</label>
			<label>
				{m('checkpoint.medicalNoteLabel')}
				<textarea bind:value={wNote} rows="2" maxlength="500"></textarea>
			</label>
			<label class="toggle-row consent">
				<input type="checkbox" bind:checked={wConsent} data-testid="weigh-in-consent" />
				<span><strong>{m('checkpoint.healthConsent')}</strong></span>
			</label>
			<div class="form-actions">
				<button type="button" class="btn btn-secondary" onclick={() => (weighTarget = null)}>{m('checkpoint.cancel')}</button>
				<button type="submit" class="btn btn-primary" disabled={busy !== null || !wConsent}>{m('checkpoint.recordWeighIn')}</button>
			</div>
		</form>
	</Modal>
{/if}

<style>
	.board-page {
		max-width: none;
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--text-muted);
		text-decoration: none;
		margin-bottom: var(--space-md);
	}
	.board-head {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		gap: var(--space-md);
		flex-wrap: wrap;
		margin-bottom: var(--space-lg);
	}
	.board-head h1 {
		margin: 0;
	}
	.board-sub {
		margin: 0.25rem 0 0;
		color: var(--text-muted);
	}
	.board-scroll {
		overflow-x: auto;
	}
	.board {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}
	.board th,
	.board td {
		text-align: left;
		padding: 0.5rem 0.6rem;
		border-bottom: 1px solid var(--border);
		vertical-align: top;
		white-space: nowrap;
	}
	.board th {
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--text-muted);
	}
	.col-runner {
		position: sticky;
		left: 0;
		background: var(--surface);
	}
	.bib-tag {
		margin-left: 0.4rem;
		color: var(--text-muted);
		font-weight: 400;
	}
	tr.dnf .col-runner strong {
		text-decoration: line-through;
		color: var(--text-muted);
	}
	.leg-time {
		display: block;
	}
	.verdict {
		display: inline-block;
		margin-top: 0.15rem;
		padding: 0.02rem 0.35rem;
		border-radius: var(--radius-sm);
		font-size: 0.72rem;
		font-weight: 700;
	}
	.verdict-safe {
		background: color-mix(in srgb, var(--success, #16a34a) 16%, transparent);
		color: var(--success, #16a34a);
	}
	.verdict-tight {
		background: color-mix(in srgb, var(--warning, #b45309) 18%, transparent);
		color: var(--warning, #b45309);
	}
	.verdict-miss {
		background: color-mix(in srgb, var(--danger, #dc2626) 16%, transparent);
		color: var(--danger, #dc2626);
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
	.status-chip.hold {
		margin-left: 0.3rem;
		background: color-mix(in srgb, var(--danger, #dc2626) 16%, transparent);
		color: var(--danger, #dc2626);
	}
	.btn-link.danger {
		color: var(--danger, #dc2626);
	}
	.form-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
		margin-top: var(--space-md);
	}
	.consent strong {
		font-weight: 600;
	}
</style>
