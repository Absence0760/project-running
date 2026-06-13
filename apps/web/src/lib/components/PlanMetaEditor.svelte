<script lang="ts">
	import { untrack } from 'svelte';
	import Modal from './Modal.svelte';
	import { updatePlanMeta } from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';
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
			error = m('planMeta.nameRequired');
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
			showToast(m('planMeta.planUpdated'));
			onSaved();
		} catch (e: any) {
			error = e?.message ?? m('planMeta.saveFailed');
		} finally {
			saving = false;
		}
	}
</script>

<Modal open title={m('planMeta.title')} onclose={onClose} bodyClass="plan-meta-body">
	<form
		class="editor-form"
		onsubmit={(e) => {
			e.preventDefault();
			save();
		}}
	>
		<label class="field">
			<span class="field-label">{m('planMeta.name')}</span>
			<input type="text" bind:value={name} maxlength="80" required />
		</label>

		<label class="field">
			<span class="field-label">{m('planMeta.daysPerWeek')}</span>
			<select bind:value={daysPerWeek}>
				{#each [3, 4, 5, 6, 7] as n}
					<option value={n}>{m('planMeta.daysCount', { n })}</option>
				{/each}
			</select>
			<span class="field-hint">
				{m('planMeta.daysPerWeekHint')}
			</span>
		</label>

		<fieldset class="field">
			<legend class="field-label">{m('planMeta.goalTime')} <span class="optional">{m('planMeta.optional')}</span></legend>
			<div class="time-row">
				<input type="number" min="0" max="9" bind:value={goalTimeHours} placeholder={m('planMeta.hoursAbbr')} />
				<span>:</span>
				<input type="number" min="0" max="59" bind:value={goalTimeMin} placeholder={m('planMeta.minutesAbbr')} />
				<span>:</span>
				<input type="number" min="0" max="59" bind:value={goalTimeSec} placeholder={m('planMeta.secondsAbbr')} />
			</div>
			<span class="field-hint">
				{m('planMeta.goalTimeHint')}
			</span>
		</fieldset>

		<label class="field">
			<span class="field-label">{m('planMeta.notes')} <span class="optional">{m('planMeta.optional')}</span></span>
			<textarea bind:value={notes} rows="2" maxlength="500" placeholder={m('planMeta.notesPlaceholder')}></textarea>
		</label>

		<label class="field">
			<span class="field-label">{m('planMeta.rules')} <span class="optional">{m('planMeta.onePerLine')}</span></span>
			<textarea
				bind:value={rulesText}
				rows="3"
				maxlength="500"
				placeholder={m('planMeta.rulesPlaceholder')}
			></textarea>
			<span class="field-hint">{m('planMeta.rulesHint')}</span>
		</label>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		<div class="actions">
			<button type="button" class="btn btn-secondary" onclick={onClose} disabled={saving}>
				{m('planMeta.cancel')}
			</button>
			<button type="submit" class="btn btn-primary" disabled={saving || !name.trim()}>
				{saving ? m('planMeta.saving') : m('planMeta.save')}
			</button>
		</div>
	</form>
</Modal>

<style>
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
</style>
