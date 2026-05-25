<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchRoutes, fetchClubRoutes, createEvent } from '$lib/data';
	import { WEEKDAY_CHOICES } from '$lib/recurrence';
	import { formatDistance, getUnit } from '$lib/units.svelte';
	import type { Route, RecurrenceFreq, Weekday } from '$lib/types';

	// Conversion factor for the unit label / pace target. The form
	// keeps its working value in the user's preferred unit (km or mi)
	// and converts to metres / sec-per-km at save time so the DB
	// shape is unit-agnostic.
	const METRES_PER_MILE = 1609.344;

	interface Props {
		clubId: string;
		clubName: string;
		// Fired with the newly created event so the host can either close
		// the modal + refresh, or navigate to the event detail page.
		oncreated?: (event: { id: string }) => void;
		oncancel?: () => void;
	}
	let { clubId, clubName, oncreated, oncancel }: Props = $props();

	let myRoutes = $state<Route[]>([]);
	let clubRoutes = $state<Route[]>([]);

	let title = $state('');
	let description = $state('');
	let date = $state(defaultDate());
	let time = $state('07:00');
	let durationMin = $state<number | null>(null);
	let meetLabel = $state('');
	let routeId = $state<string>('');
	// `distanceInUnit` holds the value in the user's preferred unit
	// (km or mi). Conversion to metres happens at save time.
	let distanceInUnit = $state<number | null>(null);
	// pace per the user's preferred unit (sec / km or sec / mi).
	let paceMin = $state<number | null>(null);
	let paceSec = $state<number | null>(null);
	let distanceUnitLabel = $derived(getUnit() === 'mi' ? 'mi' : 'km');
	let paceUnitLabel = $derived(getUnit() === 'mi' ? 'per mi' : 'per km');
	let metresPerUnit = $derived(getUnit() === 'mi' ? METRES_PER_MILE : 1000);
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
		const pad = (n: number) => String(n).padStart(2, '0');
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	}

	onMount(async () => {
		const [mine, clubs] = await Promise.all([fetchRoutes(), fetchClubRoutes(clubId)]);
		// fetchRoutes() already includes the user's bookmarked routes (via
		// saved_routes union). Drop anything that's also in this club's
		// list so the picker shows each route once.
		const clubIds = new Set(clubs.map((r) => r.id));
		myRoutes = mine.filter((r) => !clubIds.has(r.id));
		clubRoutes = clubs;
	});

	$effect(() => {
		if (routeId) {
			const r =
				myRoutes.find((x) => x.id === routeId) ?? clubRoutes.find((x) => x.id === routeId);
			if (r) distanceInUnit = +(r.distance_m / metresPerUnit).toFixed(2);
		}
	});

	async function submit(e: Event) {
		e.preventDefault();
		if (!title.trim() || busy) return;
		busy = true;
		error = null;
		try {
			const startsAt = new Date(`${date}T${time}`).toISOString();
			// Pace input is per the user's unit; the DB stores
			// `pace_target_sec` as seconds per kilometre (the schema
			// is unit-agnostic — pace_target_sec is always per-km).
			// Convert mi-mode input back to per-km before saving.
			const paceSecPerUnit =
				paceMin != null ? paceMin * 60 + (paceSec ?? 0) : null;
			const paceSecPerKm =
				paceSecPerUnit != null
					? Math.round(paceSecPerUnit * (1000 / metresPerUnit))
					: null;
			const recurrenceFreq = recurrence === 'none' ? null : recurrence;
			const event = await createEvent({
				club_id: clubId,
				title: title.trim(),
				description: description.trim() || undefined,
				starts_at: startsAt,
				duration_min: durationMin ?? undefined,
				meet_label: meetLabel.trim() || undefined,
				route_id: routeId || null,
				distance_m:
					distanceInUnit != null ? distanceInUnit * metresPerUnit : undefined,
				pace_target_sec: paceSecPerKm ?? undefined,
				capacity: capacity ?? undefined,
				recurrence_freq: recurrenceFreq,
				recurrence_byday:
					recurrenceFreq && recurrenceFreq !== 'monthly' && byday.length > 0 ? byday : null,
				recurrence_until: recurrenceFreq && until ? new Date(until).toISOString() : null
			});
			oncreated?.(event);
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Failed to create event';
		} finally {
			busy = false;
		}
	}
</script>

<form onsubmit={submit} class="event-editor">
	<p class="sub">One-off meetup for {clubName}, or set a cadence below to repeat.</p>

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
			<input type="number" min="5" max="600" bind:value={durationMin} placeholder="e.g. 60" />
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
			{#if clubRoutes.length > 0}
				<optgroup label="{clubName} routes">
					{#each clubRoutes as r}
						<option value={r.id}>{r.name} ({formatDistance(r.distance_m)})</option>
					{/each}
				</optgroup>
			{/if}
			{#if myRoutes.length > 0}
				<optgroup label="My routes">
					{#each myRoutes as r}
						<option value={r.id}>{r.name} ({formatDistance(r.distance_m)})</option>
					{/each}
				</optgroup>
			{/if}
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
			<span>Distance <span class="optional">{distanceUnitLabel}</span></span>
			<input
				type="number"
				step="0.1"
				min="0"
				bind:value={distanceInUnit}
				placeholder="e.g. 10"
			/>
		</label>
		<label>
			<span>Target pace <span class="optional">{paceUnitLabel}</span></span>
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
		{#if oncancel}
			<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>Cancel</button>
		{/if}
		<button type="submit" class="btn btn-primary" disabled={!title.trim() || busy}>
			{busy ? 'Creating…' : 'Create event'}
		</button>
	</div>
</form>

<style>
	.event-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.sub {
		color: var(--color-text-secondary);
		font-size: 0.88rem;
		margin: 0;
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
	input[type='radio'],
	input[type='checkbox'] {
		width: auto;
		padding: 0;
		background: transparent;
		border: none;
	}
	input:focus,
	textarea:focus,
	select:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	input:focus-visible, textarea:focus-visible, select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
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
	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}
</style>
