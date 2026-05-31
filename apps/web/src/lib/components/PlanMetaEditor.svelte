<script lang="ts">
	import { untrack } from 'svelte';
	import Modal from './Modal.svelte';
	import { updatePlanMeta } from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import type { TrainingPlan } from '$lib/types';

	interface Props {
		plan: TrainingPlan;
		onSaved: () => void;
		onClose: () => void;
	}
	let { plan, onSaved, onClose }: Props = $props();

	// Snapshot the incoming plan into editable state. We don't bind
	// directly to `plan.x` because the parent passes a $state proxy
	// and live edits would mutate the source before save. Each
	// initialiser runs inside `untrack` to silence Svelte 5's
	// state_referenced_locally warning — capturing the prop once is
	// exactly what we want; tracking would defeat the snapshot.
	let name = $state(untrack(() => plan.name));
	let notes = $state(untrack(() => plan.notes ?? ''));
	let daysPerWeek = $state(untrack(() => plan.days_per_week ?? 4));

	let goalTimeHours = $state<number | ''>(untrack(() =>
		plan.goal_time_seconds != null ? Math.floor(plan.goal_time_seconds / 3600) : ''
	));
	let goalTimeMin = $state<number | ''>(untrack(() =>
		plan.goal_time_seconds != null ? Math.floor((plan.goal_time_seconds % 3600) / 60) : ''
	));
	let goalTimeSec = $state<number | ''>(untrack(() =>
		plan.goal_time_seconds != null ? plan.goal_time_seconds % 60 : ''
	));

	let rulesText = $state(untrack(() =>
		Array.isArray(plan.rules) ? (plan.rules as string[]).join('\n') : ''
	));

	let saving = $state(false);
	let error = $state<string | null>(null);

	async function save() {
		if (!name.trim()) {
			error = 'Name is required';
			return;
		}
		saving = true;
		error = null;
		try {
			const goalSeconds =
				goalTimeHours === '' && goalTimeMin === '' && goalTimeSec === ''
					? null
					: (Number(goalTimeHours) || 0) * 3600 +
						(Number(goalTimeMin) || 0) * 60 +
						(Number(goalTimeSec) || 0);
			const rules = rulesText
				.split('\n')
				.map((s) => s.trim())
				.filter((s) => s.length > 0);
			await updatePlanMeta(plan.id, {
				name: name.trim(),
				notes: notes.trim() || null,
				goal_time_seconds: goalSeconds,
				days_per_week: daysPerWeek,
				rules: rules.length > 0 ? rules : null,
			});
			showToast('Plan updated.');
			onSaved();
		} catch (e: any) {
			error = e?.message ?? 'Save failed';
		} finally {
			saving = false;
		}
	}
</script>

<Modal open title="Edit plan" onclose={onClose} bodyClass="plan-meta-body">
	<form
		class="form"
		onsubmit={(e) => {
			e.preventDefault();
			save();
		}}
	>
		<label class="field">
			<span class="field-label">Name</span>
			<input type="text" bind:value={name} maxlength="80" required />
		</label>

		<label class="field">
			<span class="field-label">Days per week</span>
			<select bind:value={daysPerWeek}>
				{#each [3, 4, 5, 6, 7] as n}
					<option value={n}>{n} days</option>
				{/each}
			</select>
			<span class="field-hint">
				Changing this doesn't reshuffle existing workouts — edit individual days from the calendar below.
			</span>
		</label>

		<fieldset class="field">
			<legend class="field-label">Goal time <span class="optional">optional</span></legend>
			<div class="time-row">
				<input type="number" min="0" max="9" bind:value={goalTimeHours} placeholder="h" />
				<span>:</span>
				<input type="number" min="0" max="59" bind:value={goalTimeMin} placeholder="m" />
				<span>:</span>
				<input type="number" min="0" max="59" bind:value={goalTimeSec} placeholder="s" />
			</div>
			<span class="field-hint">
				Pace targets on existing workouts won't auto-recalculate — only the displayed goal updates.
			</span>
		</fieldset>

		<label class="field">
			<span class="field-label">Notes <span class="optional">optional</span></span>
			<textarea bind:value={notes} rows="2" maxlength="500" placeholder="Anything to remember about this plan…"></textarea>
		</label>

		<label class="field">
			<span class="field-label">Rules <span class="optional">one per line</span></span>
			<textarea
				bind:value={rulesText}
				rows="3"
				maxlength="500"
				placeholder="No tempos within 5 days of a race
Long run on Sundays only"
			></textarea>
			<span class="field-hint">Shown in the plan hero so you don't forget self-imposed constraints.</span>
		</label>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		<div class="actions">
			<button type="button" class="btn btn-secondary" onclick={onClose} disabled={saving}>
				Cancel
			</button>
			<button type="submit" class="btn btn-primary" disabled={saving || !name.trim()}>
				{saving ? 'Saving…' : 'Save'}
			</button>
		</div>
	</form>
</Modal>

<style>
	.form {
		display: grid;
		gap: var(--space-md);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}
	.field-label {
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.optional {
		font-weight: 400;
		text-transform: none;
		letter-spacing: 0;
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
	}
	.field-hint {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	input[type='text'],
	input[type='number'],
	select,
	textarea {
		padding: 0.5rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font: inherit;
	}
	textarea {
		resize: vertical;
		font-family: inherit;
	}
	.time-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	.time-row input {
		width: 4rem;
		text-align: center;
	}
	.time-row span {
		font-weight: 700;
	}
	.error {
		color: var(--color-danger);
		background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		margin: 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
