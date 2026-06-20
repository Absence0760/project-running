<script lang="ts">
	import { formatDistance } from '$lib/format/units.svelte';
	import { formatDate } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import type { RaceListingResult } from '$lib/core/data';

	interface Props {
		race: RaceListingResult;
		onimport?: (race: RaceListingResult) => void;
	}
	let { race, onimport }: Props = $props();

	let awayLabel = $derived(
		race.distance_m_away == null
			? null
			: m('races.kmAway', { distance: formatDistance(race.distance_m_away) })
	);
</script>

<li class="card-elevated race" data-testid="race-card">
	<div class="race-main">
		<strong class="race-title">{race.name}</strong>
		<span class="race-meta">
			{formatDate(race.race_date)}
			{#if race.distance_m}· {formatDistance(race.distance_m)}{/if}
			{#if race.location_label}· {race.location_label}{/if}
			{#if awayLabel}· <span class="race-away" data-testid="race-away">{awayLabel}</span>{/if}
		</span>
		{#if !race.is_verified}
			<span class="race-unverified" data-testid="race-unverified">{m('races.unverified')}</span>
		{/if}
	</div>
	<div class="race-actions">
		{#if race.entry_url}
			<a
				class="btn btn-outline btn-sm"
				href={race.entry_url}
				target="_blank"
				rel="noopener noreferrer"
				data-testid="race-register"
			>
				{m('races.register')}
			</a>
		{/if}
		{#if race.results_url}
			<a
				class="btn btn-outline btn-sm"
				href={race.results_url}
				target="_blank"
				rel="noopener noreferrer"
				data-testid="race-view-results"
			>
				{m('races.viewResults')}
			</a>
		{/if}
		<button
			type="button"
			class="btn btn-primary btn-sm"
			onclick={() => onimport?.(race)}
			data-testid="race-import"
		>
			{m('races.importResult')}
		</button>
	</div>
</li>

<style>
	.race {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
	}
	.race-main {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 0;
	}
	.race-title {
		font-size: 1rem;
	}
	.race-meta {
		font-size: 0.85rem;
		color: var(--color-text-muted, #666);
	}
	.race-away {
		font-weight: 600;
		color: var(--color-text);
	}
	.race-unverified {
		align-self: flex-start;
		font-size: 0.72rem;
		font-weight: 600;
		padding: 0.1rem 0.45rem;
		border-radius: 999px;
		background: var(--color-border);
		color: var(--color-text-muted, #666);
	}
	.race-actions {
		display: flex;
		gap: 0.4rem;
		flex-shrink: 0;
		flex-wrap: wrap;
		justify-content: flex-end;
	}
</style>
