<script lang="ts">
	import { onMount } from 'svelte';
	import { formatISO } from '$lib/training/training';
	import {
		fetchRoutes,
		fetchClubRoutes,
		createEvent,
		fetchPayoutAccount,
		setEventPricing,
		fetchSessionPlans,
		setEventSessionPlan,
		type SessionPlan
	} from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { WEEKDAY_CHOICES } from '$lib/social/recurrence';
	import { EVENT_CATEGORIES, isAthleticCategory } from '$lib/social/event_category';
	import { gymTemplateFromInputs } from '$lib/social/event_gym_template';
	import { formatDistance, getUnit } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { Route, RecurrenceFreq, Weekday, EventCategory, RefundPolicy } from '$lib/types';

	// Conversion factor for the unit label / pace target. The form
	// keeps its working value in the user's preferred unit (km or mi)
	// and converts to metres / sec-per-km at save time so the DB
	// shape is unit-agnostic.
	const METRES_PER_MILE = 1609.344;

	interface Props {
		clubId: string;
		clubName: string;
		// Whether the parent club is public. The members-only toggle is only
		// meaningful in a public club — a private club's events are already
		// members-only via the club gate, so we hide the toggle there. Defaults
		// to true (show the toggle) when the caller doesn't know.
		clubIsPublic?: boolean | null;
		// Fired with the newly created event so the host can either close
		// the modal + refresh, or navigate to the event detail page.
		oncreated?: (event: { id: string }) => void;
		oncancel?: () => void;
	}
	let { clubId, clubName, clubIsPublic = true, oncreated, oncancel }: Props = $props();
	// Show the members-only toggle unless the club is explicitly private (a
	// private club's events are already members-only; null/legacy → treat as
	// public, matching the clubs.is_public default).
	let showVisibilityToggle = $derived(clubIsPublic !== false);

	let myRoutes = $state<Route[]>([]);
	let clubRoutes = $state<Route[]>([]);

	let category = $state<EventCategory>('run');
	let discipline = $state('');
	// Optional default workout length for the class -> gym seam. The discipline
	// above doubles as the workout title source — no second discipline field.
	let gymTemplateDurationMin = $state<number | null>(null);
	// Optional follow-along session plan to attach to a class event (M5).
	let sessionPlans = $state<SessionPlan[]>([]);
	let sessionPlanId = $state<string>('');
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

	// Paid registration (club_events.md slice P1). The toggle is disabled
	// until the host has a charges-enabled Stripe payout account — the DB
	// trigger rejects a price write otherwise, so the gate must be visible
	// here too. Orthogonal to category (applies to all four). P1 ships
	// series-level pricing; the per-instance override is schema-supported
	// but not surfaced here.
	let chargesEnabled = $state(false);
	let charge = $state(false);
	let priceMajor = $state<number | null>(null);
	let currency = $state('usd');
	let refundPolicy = $state<RefundPolicy>('full_until_24h');
	let salesCloseOffset = $state<number | null>(0);

	// Members-only events (is_public = false) are hidden from non-members +
	// discovery. Default public.
	let isPublic = $state(true);

	let recurrence = $state<'none' | RecurrenceFreq>('none');
	let byday = $state<Weekday[]>([]);
	let until = $state<string>('');
	let count = $state<number | null>(null);

	function toggleByday(code: Weekday) {
		byday = byday.includes(code) ? byday.filter((c) => c !== code) : [...byday, code];
	}

	const CATEGORY_LABELS: Record<EventCategory, () => string> = {
		run: () => m('eventEditor.catRun'),
		cycle: () => m('eventEditor.catCycle'),
		class: () => m('eventEditor.catClass'),
		social: () => m('eventEditor.catSocial')
	};

	// Hiding a field via {#if} leaves its bound state intact, so a user who
	// types a distance and then switches to a class would silently submit it.
	// Clear the now-irrelevant fields the moment the category leaves the set
	// that owns them, so what's on screen is what gets written.
	function pickCategory(next: EventCategory) {
		if (category === next) return;
		category = next;
		if (!isAthleticCategory(next)) {
			routeId = '';
			distanceInUnit = null;
			paceMin = null;
			paceSec = null;
		}
		if (next !== 'class') {
			discipline = '';
			gymTemplateDurationMin = null;
			sessionPlanId = '';
		}
	}

	function defaultDate(): string {
		const d = new Date();
		d.setDate(d.getDate() + 1);
		return formatISO(d);
	}

	onMount(async () => {
		const acct = await fetchPayoutAccount();
		chargesEnabled = acct?.charges_enabled ?? false;
		if (acct?.default_currency) currency = acct.default_currency;
		const [mine, clubs] = await Promise.all([fetchRoutes(), fetchClubRoutes(clubId)]);
		// fetchRoutes() already includes the user's bookmarked routes (via
		// saved_routes union). Drop anything that's also in this club's
		// list so the picker shows each route once.
		const clubIds = new Set(clubs.map((r) => r.id));
		myRoutes = mine.filter((r) => !clubIds.has(r.id));
		clubRoutes = clubs;
		try {
			sessionPlans = await fetchSessionPlans();
		} catch (e) {
			console.error('fetchSessionPlans failed', e);
		}
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
			const athletic = isAthleticCategory(category);
			const event = await createEvent({
				club_id: clubId,
				title: title.trim(),
				category,
				discipline: category === 'class' ? discipline.trim() || null : null,
				gym_template:
					category === 'class'
						? gymTemplateFromInputs(discipline.trim(), gymTemplateDurationMin)
						: null,
				description: description.trim() || undefined,
				starts_at: startsAt,
				duration_min: durationMin ?? undefined,
				meet_label: meetLabel.trim() || undefined,
				route_id: athletic ? routeId || null : null,
				distance_m:
					athletic && distanceInUnit != null ? distanceInUnit * metresPerUnit : undefined,
				pace_target_sec: athletic ? (paceSecPerKm ?? undefined) : undefined,
				capacity: capacity ?? undefined,
				recurrence_freq: recurrenceFreq,
				recurrence_byday:
					recurrenceFreq && recurrenceFreq !== 'monthly' && byday.length > 0 ? byday : null,
				recurrence_until: recurrenceFreq && until ? new Date(until).toISOString() : null,
				recurrence_count:
					recurrenceFreq && count && count > 0 ? Math.floor(count) : null,
				// In a private club every event is members-only regardless, so the
				// toggle is hidden and we leave this public (the column is moot —
				// the club gate already restricts read + discovery skips the club).
				is_public: showVisibilityToggle ? isPublic : true
			});
			// Pricing is a separate, charges_enabled-gated write (its own RLS
			// surface + trigger). Only attempt it when the host turned charging
			// on AND can actually take payment AND entered a positive price.
			if (charge && chargesEnabled && priceMajor != null && priceMajor > 0) {
				try {
					await setEventPricing(event.id, {
						price_cents: Math.round(priceMajor * 100),
						currency,
						refund_policy: refundPolicy,
						sales_close_offset_minutes: Math.max(0, Math.floor(salesCloseOffset ?? 0))
					});
				} catch (pe: unknown) {
					// The event exists; surface the pricing failure without
					// losing it. The host can re-price from the editor.
					error = m('eventEditor.pricingFailed', {
						error: pe instanceof Error ? pe.message : String(pe)
					});
					busy = false;
					return;
				}
			}
			// Attach the follow-along session plan to a class event. The DB
			// trigger enforces organiser-only, so a rejection surfaces as a
			// toast (fail-closed) without losing the created event.
			if (category === 'class' && sessionPlanId) {
				try {
					await setEventSessionPlan(event.id, sessionPlanId);
				} catch (se) {
					console.error('setEventSessionPlan failed', se);
					showToast(m('session.event.planFailed'), 'error');
				}
			}
			oncreated?.(event);
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : m('eventEditor.createFailed');
		} finally {
			busy = false;
		}
	}
</script>

<form onsubmit={submit} class="editor-form event-editor">
	<p class="sub">{m('eventEditor.sub', { clubName })}</p>

	<div class="cat-field">
		<span class="cat-legend">{m('eventEditor.category')}</span>
		<div class="cat-row" role="radiogroup" aria-label={m('eventEditor.category')}>
			{#each EVENT_CATEGORIES as cat}
				<button
					type="button"
					class="cat-chip"
					class:active={category === cat}
					role="radio"
					aria-checked={category === cat}
					onclick={() => pickCategory(cat)}
				>
					{CATEGORY_LABELS[cat]()}
				</button>
			{/each}
		</div>
		<span class="hint">{m('eventEditor.categoryHint')}</span>
	</div>

	{#if category === 'class'}
		<label>
			<span>{m('eventEditor.discipline')}</span>
			<input
				type="text"
				bind:value={discipline}
				maxlength="60"
				placeholder={m('eventEditor.disciplinePlaceholder')}
			/>
		</label>
		<label>
			<span>{m('eventEditor.gymTemplateDuration')} <span class="optional">{m('eventEditor.optional')}</span></span>
			<input
				type="number"
				min="5"
				max="600"
				bind:value={gymTemplateDurationMin}
				placeholder={m('eventEditor.gymTemplateDurationPlaceholder')}
				data-testid="gym-template-duration"
			/>
			<span class="hint">{m('eventEditor.gymTemplateHint')}</span>
		</label>
		<label>
			<span>{m('session.event.planPicker')} <span class="optional">{m('eventEditor.optional')}</span></span>
			<select bind:value={sessionPlanId} data-testid="session-plan-picker">
				<option value="">{m('session.event.planNone')}</option>
				{#each sessionPlans as sp (sp.id)}
					<option value={sp.id}>{sp.title}</option>
				{/each}
			</select>
			{#if sessionPlans.length === 0}
				<span class="hint">{m('session.event.planEmptyHint')}</span>
			{/if}
		</label>
	{/if}

	<label>
		<span>{m('eventEditor.title')}</span>
		<input type="text" bind:value={title} required maxlength="120" placeholder={m('eventEditor.titlePlaceholder')} />
	</label>

	<label>
		<span>{m('eventEditor.details')} <span class="optional">{m('eventEditor.optional')}</span></span>
		<textarea
			bind:value={description}
			rows="3"
			maxlength="1000"
			placeholder={m('eventEditor.detailsPlaceholder')}
		></textarea>
	</label>

	<div class="row">
		<label>
			<span>{m('eventEditor.date')}</span>
			<input type="date" bind:value={date} required />
		</label>
		<label>
			<span>{m('eventEditor.startTime')}</span>
			<input type="time" bind:value={time} required />
		</label>
		<label>
			<span>{m('eventEditor.duration')} <span class="optional">{m('eventEditor.minLabel')}</span></span>
			<input type="number" min="5" max="600" bind:value={durationMin} placeholder={m('eventEditor.durationPlaceholder')} />
		</label>
	</div>

	<label>
		<span>{m('eventEditor.meetingPoint')} <span class="optional">{m('eventEditor.optional')}</span></span>
		<input type="text" bind:value={meetLabel} placeholder={m('eventEditor.meetingPointPlaceholder')} maxlength="120" />
	</label>

	{#if isAthleticCategory(category)}
		<label>
			<span>{m('eventEditor.route')} <span class="optional">{m('eventEditor.optional')}</span></span>
			<select bind:value={routeId} data-testid="event-route-select">
				<option value="">{m('eventEditor.noRoute')}</option>
				{#if clubRoutes.length > 0}
					<optgroup label={m('eventEditor.clubRoutes', { clubName })}>
						{#each clubRoutes as r}
							<option value={r.id}>{r.name} ({formatDistance(r.distance_m)})</option>
						{/each}
					</optgroup>
				{/if}
				{#if myRoutes.length > 0}
					<optgroup label={m('eventEditor.myRoutes')}>
						{#each myRoutes as r}
							<option value={r.id}>{r.name} ({formatDistance(r.distance_m)})</option>
						{/each}
					</optgroup>
				{/if}
			</select>
		</label>
	{/if}

	<fieldset>
		<legend>{m('eventEditor.repeats')}</legend>
		<div class="freq-row">
			{#each [
				{ value: 'none', label: m('eventEditor.freqNone') },
				{ value: 'weekly', label: m('eventEditor.freqWeekly') },
				{ value: 'biweekly', label: m('eventEditor.freqBiweekly') },
				{ value: 'monthly', label: m('eventEditor.freqMonthly') }
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
				<span class="hint">{m('eventEditor.onTheseDays')}</span>
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
				<span>{m('eventEditor.endsOn')} <span class="optional">{m('eventEditor.optional')}</span></span>
				<input type="date" bind:value={until} />
			</label>
			<label class="until">
				<span>{m('eventEditor.endAfter')} <span class="optional">{m('eventEditor.optional')}</span></span>
				<input
					type="number"
					min="1"
					max="520"
					bind:value={count}
					placeholder={m('eventEditor.endAfterPlaceholder')}
				/>
			</label>
		{/if}
	</fieldset>

	<div class="row">
		{#if isAthleticCategory(category)}
			<label>
				<span>{m('eventEditor.distance')} <span class="optional">{distanceUnitLabel}</span></span>
				<input
					type="number"
					step="0.1"
					min="0"
					bind:value={distanceInUnit}
					placeholder={m('eventEditor.distancePlaceholder')}
				/>
			</label>
			<label>
				<span>{m('eventEditor.targetPace')} <span class="optional">{paceUnitLabel}</span></span>
				<div class="pace">
					<input type="number" min="0" max="59" bind:value={paceMin} placeholder={m('eventEditor.paceMin')} />
					<span class="pace-sep">:</span>
					<input type="number" min="0" max="59" bind:value={paceSec} placeholder={m('eventEditor.paceSec')} />
				</div>
			</label>
		{/if}
		<label>
			<span>{m('eventEditor.capacity')} <span class="optional">{m('eventEditor.optional')}</span></span>
			<input type="number" min="1" bind:value={capacity} placeholder={m('eventEditor.capacityPlaceholder')} />
		</label>
	</div>

	{#if showVisibilityToggle}
		<fieldset class="visibility-field">
			<label class="visibility-toggle">
				<input
					type="checkbox"
					checked={!isPublic}
					onchange={(e) => (isPublic = !(e.currentTarget as HTMLInputElement).checked)}
					data-testid="members-only-toggle"
				/>
				<span>{m('eventEditor.membersOnlyToggle')}</span>
			</label>
			<p class="visibility-explainer">{m('eventEditor.membersOnlyHint')}</p>
		</fieldset>
	{/if}

	<fieldset class="charge-field">
		<label class="charge-toggle">
			<input
				type="checkbox"
				bind:checked={charge}
				disabled={!chargesEnabled}
				data-testid="charge-toggle"
			/>
			<span>{m('eventEditor.chargeToggle')}</span>
		</label>
		{#if !chargesEnabled}
			<p class="charge-explainer" data-testid="charge-needs-payout">
				{m('eventEditor.chargeNeedsPayout')}
				<a href="/settings/payouts">{m('eventEditor.chargeSetupLink')}</a>
			</p>
		{:else if charge}
			<p class="charge-explainer">{m('eventEditor.inPersonOnlyNote')}</p>
			<div class="row">
				<label>
					<span>{m('eventEditor.price')}</span>
					<input
						type="number"
						step="0.01"
						min="0.5"
						bind:value={priceMajor}
						placeholder={m('eventEditor.pricePlaceholder')}
					/>
				</label>
				<label>
					<span>{m('eventEditor.currency')}</span>
					<input type="text" bind:value={currency} maxlength="3" />
				</label>
				<label>
					<span>{m('eventEditor.salesClose')}</span>
					<input type="number" min="0" max="10080" bind:value={salesCloseOffset} />
				</label>
			</div>
			<label>
				<span>{m('eventEditor.refundPolicy')}</span>
				<select bind:value={refundPolicy}>
					<option value="full_until_start">{m('eventEditor.refundFullUntilStart')}</option>
					<option value="full_until_24h">{m('eventEditor.refundFullUntil24h')}</option>
					<option value="no_refund">{m('eventEditor.refundNone')}</option>
				</select>
			</label>
		{/if}
	</fieldset>

	{#if error}
		<p class="error">{error}</p>
	{/if}

	<div class="actions">
		{#if oncancel}
			<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>{m('eventEditor.cancel')}</button>
		{/if}
		<button type="submit" class="btn btn-primary" disabled={!title.trim() || busy}>
			{busy ? m('eventEditor.creating') : m('eventEditor.createEvent')}
		</button>
	</div>
</form>

<style>
	.sub {
		color: var(--color-text-secondary);
		font-size: 0.88rem;
		margin: 0;
	}
	.row {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-sm);
	}
	.cat-field {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.cat-legend {
		font-size: 0.9rem;
		font-weight: 600;
	}
	.cat-row {
		display: flex;
		gap: 0.4rem;
		flex-wrap: wrap;
	}
	.cat-chip {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text);
		padding: 0.45rem 0.9rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.88rem;
		cursor: pointer;
	}
	.cat-chip.active {
		background: var(--color-primary);
		color: var(--color-bg);
		border-color: var(--color-primary);
	}
	.cat-field .hint {
		color: var(--color-text-secondary);
		font-size: 0.82rem;
		font-weight: 400;
	}
	.freq-row {
		display: flex;
		gap: 1rem;
		flex-wrap: wrap;
	}
	.editor-form .radio-inline {
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
		margin-inline-end: 0.25rem;
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
	.editor-form .charge-toggle {
		flex-direction: row;
		align-items: center;
		gap: 0.5rem;
	}
	.charge-explainer {
		margin: 0.4rem 0 0;
		font-size: 0.82rem;
		font-weight: 400;
		color: var(--color-text-secondary);
		line-height: 1.45;
	}
	.charge-explainer a {
		color: var(--color-primary);
		font-weight: 600;
	}
	.editor-form .visibility-toggle {
		flex-direction: row;
		align-items: center;
		gap: 0.5rem;
	}
	.visibility-explainer {
		margin: 0.4rem 0 0;
		font-size: 0.82rem;
		font-weight: 400;
		color: var(--color-text-secondary);
		line-height: 1.45;
	}
</style>
