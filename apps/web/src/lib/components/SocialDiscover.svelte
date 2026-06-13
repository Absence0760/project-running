<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import {
		searchPublicEvents,
		type PublicEventResult,
		type PublicEventFilters,
		type EventWeekday,
	} from '$lib/core/data';
	import { formatDistance } from '$lib/format/units.svelte';

	let query = $state('');
	let category = $state<'' | 'run' | 'cycle' | 'class' | 'social'>('');
	let cadence = $state<'' | 'one_off' | 'weekly' | 'biweekly' | 'monthly'>('');
	let byday = $state<'' | EventWeekday>('');
	let time = $state<'' | 'morning' | 'afternoon' | 'evening'>('');
	let paid = $state<'' | 'free' | 'paid'>('');

	// "Near me / near a place": resolved to a club-location centroid (never the
	// event's revoked precise meet point). `center` is what reaches the RPC;
	// `nearPlace` is the typed text, `nearLabel` the active-filter chip caption.
	let nearPlace = $state('');
	let center = $state<{ lng: number; lat: number } | null>(null);
	let radiusM = $state<number | undefined>(undefined);
	let nearLabel = $state('');
	let geoError = $state('');

	let results = $state<PublicEventResult[]>([]);
	let loading = $state(true);

	const CATEGORIES: { v: '' | 'run' | 'cycle' | 'class' | 'social'; k: MessageKey }[] = [
		{ v: '', k: 'discover.activityAll' },
		{ v: 'run', k: 'eventEditor.catRun' },
		{ v: 'cycle', k: 'eventEditor.catCycle' },
		{ v: 'class', k: 'eventEditor.catClass' },
		{ v: 'social', k: 'eventEditor.catSocial' },
	];

	const WEEKDAYS: EventWeekday[] = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
	const WEEKDAY_KEY: Record<EventWeekday, MessageKey> = {
		MO: 'discover.dayMon',
		TU: 'discover.dayTue',
		WE: 'discover.dayWed',
		TH: 'discover.dayThu',
		FR: 'discover.dayFri',
		SA: 'discover.daySat',
		SU: 'discover.daySun',
	};

	async function run() {
		loading = true;
		const f: PublicEventFilters = {};
		if (query.trim()) f.query = query.trim();
		if (category) f.category = category;
		if (cadence) f.cadence = cadence;
		if (byday) f.byday = byday;
		if (time) f.time = time;
		if (paid) f.paid = paid;
		if (center) {
			f.center = center;
			if (radiusM != null) f.radiusM = radiusM;
		}
		results = await searchPublicEvents(f);
		loading = false;
	}

	// Debounced reactive search — reading the filter signals registers them as
	// deps, so any change reschedules the query; the initial run fires on mount.
	let timer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => {
		query;
		category;
		cadence;
		byday;
		paid;
		time;
		center;
		radiusM;
		clearTimeout(timer);
		timer = setTimeout(run, 250);
		return () => clearTimeout(timer);
	});

	// Geocode the typed place on its own debounce (mirrors searchClubs): a
	// resolved centroid sets `center`, which the search effect above picks up.
	// Driven by oninput, not a reactive effect, so the geolocation path can set
	// `center` without an empty `nearPlace` clobbering it.
	let placeTimer: ReturnType<typeof setTimeout> | undefined;
	function onNearPlaceInput() {
		clearTimeout(placeTimer);
		const term = nearPlace.trim();
		if (!term) {
			center = null;
			radiusM = undefined;
			nearLabel = '';
			geoError = '';
			return;
		}
		placeTimer = setTimeout(async () => {
			const { geocodePlace } = await import('$lib/routes/geocoding');
			const place = await geocodePlace(term);
			if (place) {
				center = place.center;
				radiusM = place.radiusM;
				nearLabel = term;
				geoError = '';
			} else {
				center = null;
				radiusM = undefined;
				nearLabel = '';
				geoError = m('discover.nearNoMatch');
			}
		}, 350);
	}

	function useMyLocation() {
		geoError = '';
		// navigator.geolocation is gated to secure contexts (localhost counts);
		// on plain http over a LAN it's undefined — surface that explicitly
		// rather than leaving a dead button.
		if (typeof navigator === 'undefined' || !navigator.geolocation) {
			geoError = m('discover.geoNeedsHttps');
			return;
		}
		navigator.geolocation.getCurrentPosition(
			(pos) => {
				center = { lng: pos.coords.longitude, lat: pos.coords.latitude };
				radiusM = undefined;
				nearPlace = '';
				nearLabel = m('discover.nearMe');
				geoError = '';
			},
			() => {
				geoError = m('discover.geoFailed');
			},
			{ enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 },
		);
	}

	function clearNear() {
		clearTimeout(placeTimer);
		nearPlace = '';
		center = null;
		radiusM = undefined;
		nearLabel = '';
		geoError = '';
	}

	function distanceLabel(r: PublicEventResult): string | null {
		if (r.distance_m == null) return null;
		return m('discover.distanceAway', { distance: formatDistance(r.distance_m) });
	}

	function categoryLabel(c: string): string {
		const hit = CATEGORIES.find((x) => x.v === c);
		return hit ? m(hit.k) : c;
	}

	function priceLabel(r: PublicEventResult): string {
		if (r.price_cents == null) return m('discover.free');
		try {
			return (r.price_cents / 100).toLocaleString(undefined, {
				style: 'currency',
				currency: (r.currency ?? 'usd').toUpperCase(),
			});
		} catch {
			return `${(r.price_cents / 100).toFixed(2)} ${(r.currency ?? '').toUpperCase()}`;
		}
	}

	function cadenceLabel(r: PublicEventResult): string {
		if (!r.recurrence_freq) return m('discover.oneOff');
		const freq =
			r.recurrence_freq === 'weekly'
				? m('discover.weekly')
				: r.recurrence_freq === 'biweekly'
					? m('discover.biweekly')
					: m('discover.monthly');
		const days = (r.recurrence_byday ?? [])
			.map((d) => m(WEEKDAY_KEY[d as EventWeekday] ?? 'discover.dayMon'))
			.join(', ');
		return days ? `${freq} · ${days}` : freq;
	}
</script>

<div class="discover">
	<div class="filters">
		<input
			type="search"
			class="search"
			bind:value={query}
			placeholder={m('discover.searchPlaceholder')}
			aria-label={m('discover.searchPlaceholder')}
			data-testid="discover-search"
		/>

		<div class="near-row">
			<input
				type="search"
				class="search near-input"
				bind:value={nearPlace}
				oninput={onNearPlaceInput}
				placeholder={m('discover.nearPlaceholder')}
				aria-label={m('discover.nearLabel')}
				data-testid="discover-near"
			/>
			<button
				type="button"
				class="chip near-locate"
				onclick={useMyLocation}
				data-testid="discover-use-location"
			>
				{m('discover.useMyLocation')}
			</button>
		</div>

		{#if nearLabel}
			<button
				type="button"
				class="near-active"
				onclick={clearNear}
				aria-label={m('discover.clearNear')}
				data-testid="discover-near-clear"
			>
				<span>{m('discover.nearLabel')}: {nearLabel}</span>
				<span aria-hidden="true">×</span>
			</button>
		{/if}

		{#if geoError}
			<p class="near-error" role="status" data-testid="discover-near-error">{geoError}</p>
		{/if}

		<div class="chip-row" role="group" aria-label={m('eventEditor.category')}>
			{#each CATEGORIES as c (c.v)}
				<button
					type="button"
					class="chip"
					class:active={category === c.v}
					aria-pressed={category === c.v}
					onclick={() => (category = c.v)}
					data-testid="discover-cat-{c.v || 'all'}"
				>
					{m(c.k)}
				</button>
			{/each}
		</div>

		<div class="select-row">
			<label class="field">
				<span>{m('discover.cadenceLabel')}</span>
				<select bind:value={cadence} data-testid="discover-cadence">
					<option value="">{m('discover.cadenceAny')}</option>
					<option value="one_off">{m('discover.oneOff')}</option>
					<option value="weekly">{m('discover.weekly')}</option>
					<option value="biweekly">{m('discover.biweekly')}</option>
					<option value="monthly">{m('discover.monthly')}</option>
				</select>
			</label>
			<label class="field">
				<span>{m('discover.dayLabel')}</span>
				<select bind:value={byday} data-testid="discover-day">
					<option value="">{m('discover.dayAny')}</option>
					{#each WEEKDAYS as d (d)}
						<option value={d}>{m(WEEKDAY_KEY[d])}</option>
					{/each}
				</select>
			</label>
			<label class="field">
				<span>{m('discover.timeLabel')}</span>
				<select bind:value={time} data-testid="discover-time">
					<option value="">{m('discover.timeAny')}</option>
					<option value="morning">{m('discover.morning')}</option>
					<option value="afternoon">{m('discover.afternoon')}</option>
					<option value="evening">{m('discover.evening')}</option>
				</select>
			</label>
			<div class="field">
				<span>{m('discover.priceLabel')}</span>
				<div class="chip-row">
					<button
						type="button"
						class="chip"
						class:active={paid === ''}
						aria-pressed={paid === ''}
						onclick={() => (paid = '')}>{m('discover.priceAny')}</button
					>
					<button
						type="button"
						class="chip"
						class:active={paid === 'free'}
						aria-pressed={paid === 'free'}
						onclick={() => (paid = 'free')}>{m('discover.free')}</button
					>
					<button
						type="button"
						class="chip"
						class:active={paid === 'paid'}
						aria-pressed={paid === 'paid'}
						onclick={() => (paid = 'paid')}>{m('discover.paid')}</button
					>
				</div>
			</div>
		</div>
	</div>

	{#if loading}
		<p class="state-msg">{m('discover.loading')}</p>
	{:else if results.length === 0}
		<p class="state-msg" data-testid="discover-empty">{m('discover.empty')}</p>
	{:else}
		<ul class="results" data-testid="discover-results">
			{#each results as r (r.id)}
				<li>
					<a class="card-elevated result" href="/clubs/{r.club_slug}/events/{r.id}">
						<div class="result-main">
							<strong class="result-title">{r.discipline || r.title}</strong>
							<span class="result-club">{r.club_name}</span>
							<span class="result-meta">
								{categoryLabel(r.category)} · {cadenceLabel(r)}
								{#if distanceLabel(r)}
									· <span class="result-distance" data-testid="discover-distance"
										>{distanceLabel(r)}</span
									>
								{/if}
							</span>
						</div>
						<span class="price-chip" class:free={r.price_cents == null}>{priceLabel(r)}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.discover {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.filters {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.search {
		width: 100%;
		padding: 0.6rem 0.85rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.95rem;
	}
	.search:focus-visible {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}
	.near-row {
		display: flex;
		gap: 0.4rem;
		align-items: stretch;
	}
	.near-input {
		flex: 1 1 auto;
		min-width: 0;
	}
	.near-locate {
		flex-shrink: 0;
		white-space: nowrap;
	}
	.near-active {
		align-self: flex-start;
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.3rem 0.7rem;
		border: 1.5px solid var(--color-primary);
		border-radius: 999px;
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
	}
	.near-error {
		color: var(--color-danger, #c0392b);
		font-size: 0.85rem;
		margin: 0;
	}
	.result-distance {
		font-weight: 600;
		color: var(--color-text);
	}
	.chip-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.chip {
		appearance: none;
		border: 1.5px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text-secondary);
		padding: 0.35rem 0.8rem;
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
	}
	.chip:hover {
		color: var(--color-text);
	}
	.chip.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: var(--color-on-primary, #fff);
	}
	.select-row {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md);
		align-items: flex-start;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}
	.field > span {
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.field select {
		padding: 0.45rem 0.75rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
	}
	.state-msg {
		color: var(--color-text-secondary);
		padding: var(--space-lg) 0;
	}
	.results {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.result {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		padding: var(--space-md);
		text-decoration: none;
		color: inherit;
	}
	.result-main {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
	}
	.result-title {
		font-size: 1rem;
		font-weight: 700;
	}
	.result-club {
		font-size: 0.9rem;
		color: var(--color-text);
	}
	.result-meta {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.price-chip {
		flex-shrink: 0;
		padding: 0.3rem 0.7rem;
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 700;
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.price-chip.free {
		background: color-mix(in srgb, var(--color-text) 8%, transparent);
		color: var(--color-text-secondary);
	}
</style>
