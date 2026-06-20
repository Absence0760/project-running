<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import {
		fetchRaceResultForRun,
		findRaceMatchCandidates,
		importRaceResult,
		type RaceResultForRun,
		type RaceListingResult
	} from '$lib/core/data';
	import { raceMatchScore, isRaceMatchCandidate } from '$lib/integrations/race_match';

	interface Props {
		runId: string;
		runOwnerId: string;
		startedAt: string;
		distanceM: number | null;
	}
	let { runId, runOwnerId, startedAt, distanceM }: Props = $props();

	const isOwner = $derived(auth.user?.id === runOwnerId);

	let result = $state<RaceResultForRun | null>(null);
	let candidate = $state<RaceListingResult | null>(null);
	let loading = $state(true);

	// Manual paste fallback (a candidate with no provider auto-pull).
	let pasting = $state(false);
	let pasteBib = $state('');
	let pasteChip = $state('');
	let pasteGun = $state('');
	let pastePlace = $state<number | null>(null);
	let busy = $state(false);

	const hasResult = $derived(
		!!result &&
			(result.chip_time != null ||
				result.gun_time != null ||
				result.overall_place != null ||
				result.race_name != null)
	);

	async function load() {
		loading = true;
		try {
			result = await fetchRaceResultForRun(runId);
		} catch {
			result = null;
		}
		// Auto-match seam: only offer a candidate when no official result is
		// already stamped. Best-effort — a failure here must never break the page.
		if (!hasResult && isOwner) {
			try {
				const listings = await findRaceMatchCandidates(runId);
				candidate = bestCandidate(listings);
			} catch {
				candidate = null;
			}
		}
		loading = false;
	}

	function bestCandidate(listings: RaceListingResult[]): RaceListingResult | null {
		const run = {
			runDate: startedAt,
			runStartLatLng: null,
			runDistanceM: distanceM
		};
		let best: RaceListingResult | null = null;
		let bestScore = 0;
		for (const l of listings) {
			const listing = {
				race_date: l.race_date,
				distance_m: l.distance_m,
				distance_m_away: l.distance_m_away
			};
			const score = raceMatchScore(run, listing);
			if (isRaceMatchCandidate(run, listing) && score > bestScore) {
				best = l;
				bestScore = score;
			}
		}
		return best;
	}

	async function confirmMatch(provider: 'runsignup' | 'paste') {
		if (!candidate) return;
		busy = true;
		try {
			await importRaceResult({
				provider,
				listingId: candidate.id,
				matchRunId: runId,
				result:
					provider === 'paste'
						? {
								bib: pasteBib.trim() || undefined,
								chip_time: pasteChip.trim() || undefined,
								gun_time: pasteGun.trim() || undefined,
								overall_place: pastePlace ?? undefined
							}
						: undefined
			});
			showToast(m('races.imported'), 'success');
			candidate = null;
			pasting = false;
			await load();
		} catch (e) {
			if ((e as Error).message === 'RUNSIGNUP_UNAVAILABLE') {
				// RunSignUp leg unconfigured — drop to the manual paste form.
				pasting = true;
			} else {
				showToast(m('races.importFailed'), 'error');
			}
		} finally {
			busy = false;
		}
	}

	function dismiss() {
		candidate = null;
		pasting = false;
	}

	onMount(load);
</script>

{#if !loading}
	{#if hasResult && result}
		<section class="section race-result" data-testid="race-result">
			<h2>{m('races.officialResult')}</h2>
			<dl class="race-grid">
				{#if result.race_name}
					<div><dt>{m('races.title')}</dt><dd data-testid="race-result-name">{result.race_name}</dd></div>
				{/if}
				{#if result.chip_time}
					<div><dt>{m('races.chipTime')}</dt><dd data-testid="race-result-chip">{result.chip_time}</dd></div>
				{/if}
				{#if result.gun_time}
					<div><dt>{m('races.gunTime')}</dt><dd>{result.gun_time}</dd></div>
				{/if}
				{#if result.overall_place != null}
					<div><dt>{m('races.overallPlace')}</dt><dd>{result.overall_place}</dd></div>
				{/if}
				{#if result.age_group_place != null}
					<div>
						<dt>{m('races.ageGroupPlace')}</dt>
						<dd>{result.age_group_place}{result.age_group ? ` (${result.age_group})` : ''}</dd>
					</div>
				{/if}
				{#if result.bib}
					<div><dt>{m('races.bib')}</dt><dd>{result.bib}</dd></div>
				{/if}
			</dl>
			{#if result.race_listing?.results_url}
				<a
					class="btn btn-outline btn-sm"
					href={result.race_listing.results_url}
					target="_blank"
					rel="noopener noreferrer"
				>
					{m('races.viewResults')}
				</a>
			{/if}
		</section>
	{:else if isOwner && candidate}
		<section class="section race-match" data-testid="race-match-prompt">
			<p class="match-text">{m('races.matchPrompt', { name: candidate.name })}</p>
			{#if pasting}
				<form
					class="editor-form paste-form"
					onsubmit={(e) => {
						e.preventDefault();
						confirmMatch('paste');
					}}
				>
					<label>
						<span>{m('races.bib')}</span>
						<input type="text" bind:value={pasteBib} data-testid="match-bib" />
					</label>
					<label>
						<span>{m('races.chipTime')}</span>
						<input type="text" inputmode="numeric" placeholder="1:47:23" bind:value={pasteChip} data-testid="match-chip" />
					</label>
					<label>
						<span>{m('races.gunTime')}</span>
						<input type="text" inputmode="numeric" placeholder="1:48:01" bind:value={pasteGun} data-testid="match-gun" />
					</label>
					<label>
						<span>{m('races.overallPlace')}</span>
						<input type="number" inputmode="numeric" min="0" bind:value={pastePlace} data-testid="match-place" />
					</label>
					<div class="match-actions">
						<button type="button" class="btn btn-outline btn-sm" onclick={dismiss}>{m('races.cancel')}</button>
						<button
							type="submit"
							class="btn btn-primary btn-sm"
							disabled={busy || (!pasteChip.trim() && !pasteGun.trim())}
							data-testid="match-save"
						>
							{m('races.matchConfirm')}
						</button>
					</div>
				</form>
			{:else}
				<div class="match-actions">
					<button type="button" class="btn btn-outline btn-sm" onclick={dismiss} data-testid="match-dismiss">
						{m('races.matchDismiss')}
					</button>
					<button
						type="button"
						class="btn btn-primary btn-sm"
						disabled={busy}
						onclick={() => confirmMatch(candidate?.provider === 'runsignup' ? 'runsignup' : 'paste')}
						data-testid="match-confirm"
					>
						{m('races.matchConfirm')}
					</button>
				</div>
			{/if}
		</section>
	{/if}
{/if}

<style>
	.race-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
		gap: var(--space-sm) var(--space-lg);
		margin: 0 0 var(--space-md);
	}
	.race-grid dt {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
		margin: 0;
	}
	.race-grid dd {
		margin: 0.1rem 0 0;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.match-text {
		margin: 0 0 var(--space-sm);
	}
	.match-actions {
		display: flex;
		gap: 0.4rem;
		justify-content: flex-end;
		flex-wrap: wrap;
	}
	.paste-form {
		margin-bottom: var(--space-sm);
	}
</style>
