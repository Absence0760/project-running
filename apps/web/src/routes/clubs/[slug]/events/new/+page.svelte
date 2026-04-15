<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { fetchClubBySlug, fetchRoutes, createEvent } from '$lib/data';
	import { WEEKDAY_CHOICES } from '$lib/recurrence';
	import type { ClubWithMeta, Route, RecurrenceFreq, Weekday } from '$lib/types';

	let slug = $derived($page.params.slug as string);
	let club = $state<ClubWithMeta | null>(null);
	let myRoutes = $state<Route[]>([]);
	let loading = $state(true);

	let title = $state('');
	let description = $state('');
	let date = $state(defaultDate());
	let time = $state('07:00');
	let durationMin = $state<number | null>(null);
	let meetLabel = $state('');
	let routeId = $state<string>('');
	let distanceKm = $state<number | null>(null);
	let paceMin = $state<number | null>(null);
	let paceSec = $state<number | null>(null);
	let capacity = $state<number | null>(null);
	let busy = $state(false);
	let error = $state<string | null>(null);

	let recurrence = $state<'none' | RecurrenceFreq>('none');
	let byday = $state<Weekday[]>([]);
	let until = $state<string>('');

	function toggleByday(code: Weekday) {
		byday = byday.includes(code) ? byday.filter((c) => c !== code) : [...byday, code];
	}

	function defaultDate(): string {
		const d = new Date();
		d.setDate(d.getDate() + 1);
		// Local-tz yyyy-mm-dd; `toISOString` would give UTC which is off by
		// a day for any viewer not on UTC near midnight.
		const pad = (n: number) => String(n).padStart(2, '0');
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	}

	onMount(async () => {
		club = await fetchClubBySlug(slug);
		if (club?.viewer_role !== 'owner' && club?.viewer_role !== 'admin') {
			goto(`/clubs/${slug}`);
			return;
		}
		myRoutes = await fetchRoutes();
		loading = false;
	});

	$effect(() => {
		// If user picks a route, prefill distance from the route.
		if (routeId) {
			const r = myRoutes.find((x) => x.id === routeId);
			if (r) distanceKm = +(r.distance_m / 1000).toFixed(2);
		}
	});

	async function submit(e: Event) {
		e.preventDefault();
		if (!club || !title.trim() || busy) return;
		busy = true;
		error = null;
		try {
			const startsAt = new Date(`${date}T${time}`).toISOString();
			const paceSecTotal =
				paceMin != null ? paceMin * 60 + (paceSec ?? 0) : null;
			const recurrenceFreq = recurrence === 'none' ? null : recurrence;
			const event = await createEvent({
				club_id: club.id,
				title: title.trim(),
				description: description.trim() || undefined,
				starts_at: startsAt,
				duration_min: durationMin ?? undefined,
				meet_label: meetLabel.trim() || undefined,
				route_id: routeId || null,
				distance_m: distanceKm != null ? distanceKm * 1000 : undefined,
				pace_target_sec: paceSecTotal ?? undefined,
				capacity: capacity ?? undefined,
				recurrence_freq: recurrenceFreq,
				recurrence_byday:
					recurrenceFreq && recurrenceFreq !== 'monthly' && byday.length > 0 ? byday : null,
				recurrence_until: recurrenceFreq && until ? new Date(until).toISOString() : null
			});
			goto(`/clubs/${slug}/events/${event.id}`);
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Failed to create event';
		} finally {
			busy = false;
		}
	}
</script>

{#if loading}
	<p class="centered muted">Loading…</p>
{:else if !club}
	<p class="centered muted">Club not found.</p>
{:else}
	<div class="page">
		<a class="back" href="/clubs/{slug}">
			<span class="material-symbols">arrow_back</span>
			Back to {club.name}
		</a>
		<h1>New event</h1>
		<p class="sub">One-off meetup for {club.name}. Recurrence comes in Phase 2.</p>

		<form onsubmit={submit}>
			<label>
				<span>Title</span>
				<input type="text" bind:value={title} required maxlength="120" placeholder="Sunday long run" />
			</label>

			<label>
				<span>Details <span class="optional">optional</span></span>
				<textarea
					bind:value={description}
					rows="3"
					maxlength="1000"
					placeholder="Pace groups, post-run coffee, terrain, what to bring"
				></textarea>
			</label>

			<div class="row">
				<label>
					<span>Date</span>
					<input type="date" bind:value={date} required />
				</label>
				<label>
					<span>Start time</span>
					<input type="time" bind:value={time} required />
				</label>
				<label>
					<span>Duration <span class="optional">min</span></span>
					<input
						type="number"
						min="5"
						max="600"
						bind:value={durationMin}
						placeholder="e.g. 60"
					/>
				</label>
			</div>

			<label>
				<span>Meeting point <span class="optional">optional</span></span>
				<input type="text" bind:value={meetLabel} placeholder="e.g. North Gate, Central Park" maxlength="120" />
			</label>

			<label>
				<span>Route <span class="optional">optional</span></span>
				<select bind:value={routeId}>
					<option value="">— no route —</option>
					{#each myRoutes as r}
						<option value={r.id}>{r.name} ({(r.distance_m / 1000).toFixed(1)} km)</option>
					{/each}
				</select>
			</label>

			<fieldset>
				<legend>Repeats</legend>
				<div class="freq-row">
					{#each [
						{ value: 'none', label: 'One-off' },
						{ value: 'weekly', label: 'Weekly' },
						{ value: 'biweekly', label: 'Every 2 weeks' },
						{ value: 'monthly', label: 'Monthly' }
					] as opt}
						<label class="radio-inline">
							<input
								type="radio"
								name="freq"
								checked={recurrence === opt.value}
								onchange={() => (recurrence = opt.value as 'none' | RecurrenceFreq)}
							/>
							<span>{opt.label}</span>
						</label>
					{/each}
				</div>

				{#if recurrence === 'weekly' || recurrence === 'biweekly'}
					<div class="byday-row">
						<span class="hint">On these days:</span>
						{#each WEEKDAY_CHOICES as wd}
							<button
								type="button"
								class="byday-chip"
								class:active={byday.includes(wd.code)}
								onclick={() => toggleByday(wd.code)}
							>
								{wd.label}
							</button>
						{/each}
					</div>
				{/if}

				{#if recurrence !== 'none'}
					<label class="until">
						<span>Ends on <span class="optional">optional</span></span>
						<input type="date" bind:value={until} />
					</label>
				{/if}
			</fieldset>

			<div class="row">
				<label>
					<span>Distance <span class="optional">km</span></span>
					<input type="number" step="0.1" min="0" bind:value={distanceKm} placeholder="e.g. 10" />
				</label>
				<label>
					<span>Target pace <span class="optional">per km</span></span>
					<div class="pace">
						<input type="number" min="0" max="59" bind:value={paceMin} placeholder="min" />
						<span class="pace-sep">:</span>
						<input type="number" min="0" max="59" bind:value={paceSec} placeholder="sec" />
					</div>
				</label>
				<label>
					<span>Capacity <span class="optional">optional</span></span>
					<input type="number" min="1" bind:value={capacity} placeholder="unlimited" />
				</label>
			</div>

			{#if error}
				<p class="error">{error}</p>
			{/if}

			<div class="actions">
				<button type="button" class="btn-secondary" onclick={() => history.back()}>Cancel</button>
				<button type="submit" class="btn-primary" disabled={!title.trim() || busy}>
					{busy ? 'Creating…' : 'Create event'}
				</button>
			</div>
		</form>
	</div>
{/if}

<style>
	.page {
		max-width: 44rem;
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

	h1 {
		font-size: 1.75rem;
		font-weight: 700;
	}

	.sub {
		color: var(--color-text-secondary);
		margin: 0.35rem 0 var(--space-lg) 0;
	}

	form {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	label {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		font-size: 0.9rem;
		font-weight: 600;
	}

	.optional {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}

	input,
	textarea,
	select {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.55rem 0.75rem;
		font: inherit;
		color: inherit;
		width: 100%;
	}

	input:focus,
	textarea:focus,
	select:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}

	.row {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-sm);
	}

	fieldset {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.8rem 1rem;
		background: var(--color-surface);
	}

	legend {
		font-weight: 600;
		font-size: 0.9rem;
		padding: 0 0.4rem;
	}

	.freq-row {
		display: flex;
		gap: 1rem;
		flex-wrap: wrap;
	}

	.radio-inline {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		flex-direction: row;
		font-weight: 500;
		font-size: 0.9rem;
		cursor: pointer;
	}

	.byday-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-wrap: wrap;
		margin-top: 0.75rem;
	}

	.byday-row .hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin-right: 0.25rem;
	}

	.byday-chip {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text);
		padding: 0.3rem 0.65rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.82rem;
		cursor: pointer;
	}

	.byday-chip.active {
		background: var(--color-primary);
		color: var(--color-bg);
		border-color: var(--color-primary);
	}

	.until {
		margin-top: 0.75rem;
	}

	.pace {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}

	.pace-sep {
		font-weight: 700;
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
	}

	.btn-primary {
		background: var(--color-primary);
		color: var(--color-bg);
		padding: 0.6rem 1.2rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: none;
		cursor: pointer;
	}

	.btn-primary:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.btn-secondary {
		background: transparent;
		color: var(--color-text);
		padding: 0.6rem 1.2rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: 1px solid var(--color-border);
		cursor: pointer;
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
