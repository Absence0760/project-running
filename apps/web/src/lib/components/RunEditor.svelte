<script lang="ts">
	import { onMount } from 'svelte';
	import { createManualRun, fetchRoutes } from '$lib/core/data';
	import { loadSettings, effective } from '$lib/settings/settings';
	import { privacyDefaultToIsPublic } from '$lib/social/run_visibility';
	import { supabase } from '$lib/core/supabase';
	import { showToast } from '$lib/stores/toast.svelte';
	import { getUnit } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
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
	let activityType = $state<'run' | 'walk' | 'hike' | 'cycle' | 'stroller'>('run');
	let notes = $state('');
	let routeId = $state('');
	let routes = $state<Route[]>([]);
	let submitting = $state(false);
	// Seeded from the user's privacy_default on mount so the toggle reflects
	// their standing preference; a per-run change overrides it for this run.
	// `touched` guards against the async settings load (below) clobbering a
	// choice the user made before it resolved.
	let isPublic = $state(false);
	let touched = $state(false);

	let distanceLabel = $derived(m('runEditor.distanceLabel', { unit }));

	onMount(async () => {
		unit = getUnit();
		try {
			// getUser() (awaited) is reliable on first paint; the reactive
			// auth store may not be hydrated yet when onMount fires.
			const { data: authData } = await supabase.auth.getUser();
			const userId = authData.user?.id;
			if (userId) {
				const settings = await loadSettings(userId);
				const seeded = privacyDefaultToIsPublic(
					effective<string>(settings, 'privacy_default', 'followers')
				);
				if (!touched) isPublic = seeded;
			}
		} catch (_) {
			isPublic = false;
		}
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
			showToast(m('runEditor.distanceDurationRequired'), 'error');
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
				routeId: routeId || null,
				isPublic
			});
			showToast(m('runEditor.runAdded'), 'success');
			oncreated?.({ id });
		} catch (err) {
			showToast(m('runEditor.addRunFailed', { error: err instanceof Error ? err.message : String(err) }), 'error');
		} finally {
			submitting = false;
		}
	}
</script>

<form class="editor-form run-editor" onsubmit={handleSubmit}>
	<label class="field">
		<span class="field-label">{m('runEditor.startedAt')}</span>
		<input type="datetime-local" bind:value={startedAt} required class="input" />
	</label>

	<fieldset class="field activity-field">
		<legend class="field-label">{m('runEditor.activity')}</legend>
		<div class="chip-row" role="radiogroup" aria-label={m('runEditor.activity')}>
			{#each ['run', 'walk', 'hike', 'cycle', 'stroller'] as a}
				<button
					type="button"
					role="radio"
					aria-checked={activityType === a}
					class="chip"
					class:active={activityType === a}
					onclick={() => (activityType = a as typeof activityType)}
				>
					{m(`runEditor.activity_${a}` as MessageKey)}
				</button>
			{/each}
		</div>
	</fieldset>

	<div class="row">
		<label class="field">
			<span class="field-label">{distanceLabel}</span>
			<input type="number" min="0" step="0.01" bind:value={distance} required class="input" />
		</label>
		<label class="field">
			<span class="field-label">{m('runEditor.durationMin')}</span>
			<input type="number" min="0" step="1" bind:value={durationMin} required class="input" />
		</label>
		<label class="field">
			<span class="field-label">{m('runEditor.durationSec')}</span>
			<input type="number" min="0" max="59" step="1" bind:value={durationSec} class="input" />
		</label>
	</div>

	<label class="field">
		<span class="field-label">{m('runEditor.routeOptional')}</span>
		<select bind:value={routeId} class="input">
			<option value="">{m('runEditor.noRoute')}</option>
			{#each routes as r (r.id)}
				<option value={r.id}>{r.name}</option>
			{/each}
		</select>
		<span class="field-hint">
			{m('runEditor.routeHint')}
		</span>
	</label>

	<label class="field">
		<span class="field-label">{m('runEditor.notesOptional')}</span>
		<textarea
			bind:value={notes}
			rows="3"
			class="input"
			placeholder={m('runEditor.notesPlaceholder')}
		></textarea>
	</label>

	<label class="field toggle-field">
		<input
			type="checkbox"
			bind:checked={isPublic}
			onchange={() => (touched = true)}
			class="toggle-input"
		/>
		<span>
			<span class="field-label toggle-label">{m('runEditor.makePublic')}</span>
			<span class="field-hint">
				{m('runEditor.makePublicHint')}
			</span>
		</span>
	</label>

	<div class="actions">
		{#if oncancel}
			<button
				type="button"
				class="btn btn-secondary"
				onclick={() => oncancel?.()}
				disabled={submitting}
			>
				{m('runEditor.cancel')}
			</button>
		{/if}
		<button type="submit" class="btn btn-primary" disabled={submitting}>
			{submitting ? m('runEditor.saving') : m('runEditor.saveRun')}
		</button>
	</div>
</form>

<style>
	.run-editor {
		gap: 1.1rem;
	}
	.editor-form .toggle-field {
		flex-direction: row;
		align-items: start;
		gap: 0.6rem;
	}
	.toggle-field > span {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.toggle-input { margin-top: 0.2rem; }
	.activity-field { border: 0; padding: 0; margin: 0; }
	.activity-field .field-label { padding: 0; }
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
</style>
