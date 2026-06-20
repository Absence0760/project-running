<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import {
		searchRaceListings,
		importRaceResult,
		isRunSignUpConfigured,
		type RaceListingResult,
		type RaceListingFilters,
		type RaceDistanceBand
	} from '$lib/core/data';
	import RaceCalendarCard from '$lib/components/RaceCalendarCard.svelte';
	import RaceListingEditor from '$lib/components/RaceListingEditor.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	let query = $state('');
	let distance = $state<'' | RaceDistanceBand>('');

	let nearPlace = $state('');
	let center = $state<{ lng: number; lat: number } | null>(null);
	let radiusM = $state<number | undefined>(undefined);
	let nearLabel = $state('');
	let geoError = $state('');

	let results = $state<RaceListingResult[]>([]);
	let loading = $state(true);
	let error = $state(false);

	let showEditor = $state(false);

	// RunSignUp availability probe → drives the import modal's provider choice.
	let runSignUpAvailable = $state(false);

	// Import flow modal state.
	let importing = $state<RaceListingResult | null>(null);
	let pasteBib = $state('');
	let pasteChip = $state('');
	let pasteGun = $state('');
	let pastePlace = $state<number | null>(null);
	let importBusy = $state(false);

	const DISTANCES: { v: '' | RaceDistanceBand; k: MessageKey }[] = [
		{ v: '', k: 'races.distanceAny' },
		{ v: '5k', k: 'races.distance5k' },
		{ v: '10k', k: 'races.distance10k' },
		{ v: 'half', k: 'races.distanceHalf' },
		{ v: 'marathon', k: 'races.distanceMarathon' },
		{ v: 'ultra', k: 'races.distanceUltra' }
	];

	async function run() {
		loading = true;
		error = false;
		const f: RaceListingFilters = {};
		if (query.trim()) f.query = query.trim();
		if (distance) f.distance = distance;
		if (center) {
			f.center = center;
			if (radiusM != null) f.radiusM = radiusM;
		}
		try {
			results = await searchRaceListings(f);
		} catch {
			error = true;
		} finally {
			loading = false;
		}
	}

	let timer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => {
		query;
		distance;
		center;
		radiusM;
		clearTimeout(timer);
		timer = setTimeout(run, 250);
		return () => clearTimeout(timer);
	});

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
		if (typeof navigator === 'undefined' || !navigator.geolocation) {
			geoError = m('discover.geoNeedsHttps');
			return;
		}
		navigator.geolocation.getCurrentPosition(
			(pos) => {
				center = { lng: pos.coords.longitude, lat: pos.coords.latitude };
				radiusM = undefined;
				nearPlace = '';
				nearLabel = m('races.nearMe');
				geoError = '';
			},
			() => {
				geoError = m('discover.geoFailed');
			},
			{ enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 }
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

	function openImport(race: RaceListingResult) {
		importing = race;
		pasteBib = '';
		pasteChip = '';
		pasteGun = '';
		pastePlace = null;
	}

	async function doRunSignUpImport() {
		if (!importing) return;
		importBusy = true;
		try {
			await importRaceResult({ provider: 'runsignup', listingId: importing.id });
			showToast(m('races.imported'), 'success');
			importing = null;
		} catch (e) {
			if ((e as Error).message === 'RUNSIGNUP_UNAVAILABLE') {
				showToast(m('integrations.runsignupUnavailable'), 'error');
			} else {
				showToast(m('races.importFailed'), 'error');
			}
		} finally {
			importBusy = false;
		}
	}

	async function doPasteImport() {
		if (!importing) return;
		importBusy = true;
		try {
			await importRaceResult({
				provider: 'paste',
				listingId: importing.id,
				result: {
					bib: pasteBib.trim() || undefined,
					chip_time: pasteChip.trim() || undefined,
					gun_time: pasteGun.trim() || undefined,
					overall_place: pastePlace ?? undefined
				}
			});
			showToast(m('races.imported'), 'success');
			importing = null;
		} catch {
			showToast(m('races.importFailed'), 'error');
		} finally {
			importBusy = false;
		}
	}

	function onCreated() {
		showEditor = false;
		run();
	}

	onMount(async () => {
		try {
			runSignUpAvailable = await isRunSignUpConfigured();
		} catch {
			runSignUpAvailable = false;
		}
	});
</script>

<svelte:head><title>{m('races.title')}</title></svelte:head>

<div class="races-page">
	<header class="races-header">
		<div>
			<h1>{m('races.title')}</h1>
			<p class="subtitle">{m('races.subtitle')}</p>
		</div>
		<button
			type="button"
			class="btn btn-primary"
			onclick={() => (showEditor = true)}
			data-testid="race-submit"
		>
			{m('races.submitRace')}
		</button>
	</header>

	<div class="filters">
		<input
			type="search"
			class="search"
			bind:value={query}
			placeholder={m('races.searchPlaceholder')}
			aria-label={m('races.searchPlaceholder')}
			data-testid="races-search"
		/>

		<div class="near-row">
			<input
				type="search"
				class="search near-input"
				bind:value={nearPlace}
				oninput={onNearPlaceInput}
				placeholder={m('races.nearPlace')}
				aria-label={m('races.nearPlace')}
				data-testid="races-near"
			/>
			<button type="button" class="chip near-locate" onclick={useMyLocation} data-testid="races-use-location">
				{m('discover.useMyLocation')}
			</button>
		</div>

		{#if nearLabel}
			<button type="button" class="near-active" onclick={clearNear} data-testid="races-near-clear">
				<span>{m('discover.nearLabel')}: {nearLabel}</span>
				<span aria-hidden="true">×</span>
			</button>
		{/if}
		{#if geoError}
			<p class="near-error" role="status">{geoError}</p>
		{/if}

		<div class="chip-row" role="group" aria-label={m('races.distanceAny')}>
			{#each DISTANCES as d (d.v)}
				<button
					type="button"
					class="chip"
					class:active={distance === d.v}
					aria-pressed={distance === d.v}
					onclick={() => (distance = d.v)}
					data-testid="races-dist-{d.v || 'any'}"
				>
					{m(d.k)}
				</button>
			{/each}
		</div>
	</div>

	{#if loading}
		<p class="state-msg">{m('races.loading')}</p>
	{:else if error}
		<div class="races-error" role="alert" data-testid="races-error">
			<span>{m('races.searchFailed')}</span>
			<button type="button" class="btn btn-outline" onclick={run}>{m('races.retry')}</button>
		</div>
	{:else if results.length === 0}
		<p class="state-msg" data-testid="races-empty">{m('races.empty')}</p>
	{:else}
		<ul class="results" data-testid="races-results">
			{#each results as r (r.id)}
				<RaceCalendarCard race={r} onimport={openImport} />
			{/each}
		</ul>
	{/if}
</div>

{#if showEditor}
	<RaceListingEditor oncreated={onCreated} oncancel={() => (showEditor = false)} />
{/if}

{#if importing}
	<div class="modal-backdrop" role="presentation" onclick={() => (importing = null)}>
		<div
			class="modal modal-narrow"
			role="dialog"
			aria-modal="true"
			aria-label={m('races.importResult')}
			onclick={(e) => e.stopPropagation()}
		>
			<div class="modal-header">
				<h2>{importing.name}</h2>
				<button type="button" class="modal-close" onclick={() => (importing = null)} aria-label={m('races.cancel')}>×</button>
			</div>
			<div class="modal-body import-body">
				{#if importing.provider === 'runsignup' && runSignUpAvailable}
					<button
						type="button"
						class="btn btn-primary"
						disabled={importBusy}
						onclick={doRunSignUpImport}
						data-testid="race-import-runsignup"
					>
						{m('races.importResult')}
					</button>
				{:else if importing.provider === 'runsignup' && !runSignUpAvailable}
					<p class="unavailable" data-testid="race-runsignup-unavailable">
						{m('integrations.runsignupUnavailable')}
					</p>
				{/if}

				<form
					class="editor-form"
					onsubmit={(e) => {
						e.preventDefault();
						doPasteImport();
					}}
				>
					<p class="paste-hint">{m('races.pasteResultHint')}</p>
					<label>
						<span>{m('races.bib')}</span>
						<input type="text" bind:value={pasteBib} data-testid="paste-bib" />
					</label>
					<label>
						<span>{m('races.chipTime')}</span>
						<input type="text" inputmode="numeric" placeholder="1:47:23" bind:value={pasteChip} data-testid="paste-chip" />
					</label>
					<label>
						<span>{m('races.gunTime')}</span>
						<input type="text" inputmode="numeric" placeholder="1:48:01" bind:value={pasteGun} data-testid="paste-gun" />
					</label>
					<label>
						<span>{m('races.overallPlace')}</span>
						<input type="number" inputmode="numeric" min="0" bind:value={pastePlace} data-testid="paste-place" />
					</label>
					<div class="form-actions">
						<button type="button" class="btn btn-outline" onclick={() => (importing = null)}>
							{m('races.cancel')}
						</button>
						<button
							type="submit"
							class="btn btn-primary"
							disabled={importBusy || (!pasteChip.trim() && !pasteGun.trim())}
							data-testid="paste-save"
						>
							{m('races.matchConfirm')}
						</button>
					</div>
				</form>
			</div>
		</div>
	</div>
{/if}

<style>
	.races-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		padding: var(--space-xl) var(--space-2xl);
	}
	.races-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
	}
	.subtitle {
		color: var(--color-text-muted, #666);
		margin: 0.25rem 0 0;
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
	.chip-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.chip {
		appearance: none;
		border: 1.5px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text);
		padding: 0.35rem 0.8rem;
		border-radius: 999px;
		font-size: 0.85rem;
		cursor: pointer;
	}
	.chip.active {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 600;
	}
	.results {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.state-msg {
		color: var(--color-text-muted, #666);
	}
	.races-error {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		color: var(--color-danger, #c0392b);
	}
	.import-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.paste-hint,
	.unavailable {
		color: var(--color-text-muted, #666);
		font-size: 0.9rem;
		margin: 0;
	}
</style>
