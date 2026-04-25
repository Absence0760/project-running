<script lang="ts">
	import { onMount } from 'svelte';
	import { createManualRun, fetchRoutes } from '$lib/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { getUnit } from '$lib/units.svelte';
	import type { Route } from '$lib/types';

	interface Props {
		oncreated?: (run: { id: string }) => void;
		oncancel?: () => void;
	}
	let { oncreated, oncancel }: Props = $props();

	const METRES_PER_MILE = 1609.344;

	function nowLocalIso() {
		const d = new Date();
		const off = d.getTimezoneOffset() * 60_000;
		return new Date(d.getTime() - off).toISOString().slice(0, 16);
	}

	let unit = $state<'km' | 'mi'>('km');
	let startedAt = $state(nowLocalIso());
	let durationMin = $state(30);
	let durationSec = $state(0);
	let distance = $state(5);
	let activityType = $state<'run' | 'walk' | 'hike' | 'cycle'>('run');
	let notes = $state('');
	let routeId = $state('');
	let routes = $state<Route[]>([]);
	let submitting = $state(false);

	let distanceLabel = $derived(`Distance (${unit})`);

	onMount(async () => {
		unit = getUnit();
		try {
			routes = await fetchRoutes();
		} catch (_) {
			routes = [];
		}
	});

	async function handleSubmit(e: Event) {
		e.preventDefault();
		if (submitting) return;
		const totalSec =
			Math.max(0, Math.floor(durationMin)) * 60 + Math.max(0, Math.floor(durationSec));
		const perUnitMetres = unit === 'mi' ? METRES_PER_MILE : 1000;
		const distanceM = Math.max(0, distance * perUnitMetres);
		if (totalSec <= 0 || distanceM <= 0) {
			showToast('Distance and duration are both required.', 'error');
			return;
		}
		submitting = true;
		try {
			const iso = new Date(startedAt).toISOString();
			const { id } = await createManualRun({
				startedAt: iso,
				durationS: totalSec,
				distanceM,
				activityType,
				notes: notes.trim() || null,
				routeId: routeId || null
			});
			showToast('Run added.', 'success');
			oncreated?.({ id });
		} catch (err) {
			showToast(`Couldn't add run: ${(err as Error).message}`, 'error');
		} finally {
			submitting = false;
		}
	}
</script>

<form class="run-editor" onsubmit={handleSubmit}>
	<label class="field">
		<span class="field-label">Started at</span>
		<input type="datetime-local" bind:value={startedAt} required class="input" />
	</label>

	<label class="field">
		<span class="field-label">Activity</span>
		<div class="chip-row">
			{#each ['run', 'walk', 'hike', 'cycle'] as a}
				<button
					type="button"
					class="chip"
					class:active={activityType === a}
					onclick={() => (activityType = a as typeof activityType)}
				>
					{a.charAt(0).toUpperCase() + a.slice(1)}
				</button>
			{/each}
		</div>
	</label>

	<div class="row">
		<label class="field">
			<span class="field-label">{distanceLabel}</span>
			<input type="number" min="0" step="0.01" bind:value={distance} required class="input" />
		</label>
		<label class="field">
			<span class="field-label">Duration — min</span>
			<input type="number" min="0" step="1" bind:value={durationMin} required class="input" />
		</label>
		<label class="field">
			<span class="field-label">Sec</span>
			<input type="number" min="0" max="59" step="1" bind:value={durationSec} class="input" />
		</label>
	</div>

	<label class="field">
		<span class="field-label">Route (optional)</span>
		<select bind:value={routeId} class="input">
			<option value="">— No route —</option>
			{#each routes as r (r.id)}
				<option value={r.id}>{r.name}</option>
			{/each}
		</select>
		<span class="field-hint">
			Link this run to one of your saved routes — or leave blank to log it without a route.
		</span>
	</label>

	<label class="field">
		<span class="field-label">Notes (optional)</span>
		<textarea
			bind:value={notes}
			rows="3"
			class="input"
			placeholder="How did it feel? What was the weather like?"
		></textarea>
	</label>

	<div class="actions">
		{#if oncancel}
			<button
				type="button"
				class="btn btn-secondary"
				onclick={() => oncancel?.()}
				disabled={submitting}
			>
				Cancel
			</button>
		{/if}
		<button type="submit" class="btn btn-primary" disabled={submitting}>
			{submitting ? 'Saving…' : 'Save run'}
		</button>
	</div>
</form>

<style>
	.run-editor {
		display: grid;
		gap: 1.1rem;
	}
	.field { display: grid; gap: 0.35rem; }
	.field-label {
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.field-hint {
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}
	.input {
		padding: 0.55rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 0.95rem;
		font-family: inherit;
		width: 100%;
	}
	.row { display: grid; grid-template-columns: 2fr 1fr 1fr; gap: 0.75rem; }
	@media (max-width: 30rem) {
		.row { grid-template-columns: 1fr 1fr; }
	}
	.chip-row { display: flex; flex-wrap: wrap; gap: 0.4rem; }
	.chip {
		padding: 0.4rem 0.9rem;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
	}
	.chip.active {
		background: var(--color-primary);
		color: white;
		border-color: var(--color-primary);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
		margin-top: 0.3rem;
	}
</style>
