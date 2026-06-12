<script lang="ts">
	import { untrack } from 'svelte';
	import { createGymRoutine, type GymRoutineInput } from '$lib/core/data';
	import { normaliseExerciseName } from '$lib/gym/gym_prs';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import { parseWeight, weightInputValue, weightUnitLabel } from '$lib/format/units.svelte';
	import type { PrefillExercise } from '$lib/gym/gym_routine';

	interface Props {
		/// Optional in-memory blocks to seed the editor with (e.g. the output of
		/// routineFromWorkout for a "Save as routine" promotion). When absent the
		/// editor opens with one empty block.
		seedExercises?: PrefillExercise[] | null;
		seedTitle?: string;
		/// Distinct exercise names from the user's history, for autocomplete.
		suggestions?: string[];
		oncreated?: (id: string) => void;
		oncancel: () => void;
	}

	let {
		seedExercises = null,
		seedTitle = '',
		suggestions = [],
		oncreated,
		oncancel,
	}: Props = $props();

	type EditSet = { reps: string; weight: string };
	type EditExercise = { name: string; sets: EditSet[] };

	function emptySet(): EditSet {
		return { reps: '', weight: '' };
	}

	function initExercises(src: PrefillExercise[] | null): EditExercise[] {
		if (!src || src.length === 0) return [{ name: '', sets: [emptySet()] }];
		return src.map((ex) => ({
			name: ex.name,
			sets:
				ex.sets.length === 0
					? [emptySet()]
					: ex.sets.map((s) => ({ reps: s.reps, weight: weightInputValue(s.weightKg) })),
		}));
	}

	const seed = untrack(() => seedExercises);
	let title = $state(untrack(() => seedTitle));
	let exercises = $state<EditExercise[]>(initExercises(seed));
	let notes = $state('');
	let saving = $state(false);
	let error = $state('');

	function addExercise() {
		exercises = [...exercises, { name: '', sets: [emptySet()] }];
	}
	function removeExercise(i: number) {
		exercises = exercises.filter((_, idx) => idx !== i);
		if (exercises.length === 0) exercises = [{ name: '', sets: [emptySet()] }];
	}
	function addSet(ei: number) {
		exercises[ei].sets = [...exercises[ei].sets, emptySet()];
	}
	function removeSet(ei: number, si: number) {
		exercises[ei].sets = exercises[ei].sets.filter((_, idx) => idx !== si);
		if (exercises[ei].sets.length === 0) exercises[ei].sets = [emptySet()];
	}

	function intOrNull(s: string): number | null {
		const n = parseInt(s, 10);
		return Number.isFinite(n) ? n : null;
	}

	function buildInput(): GymRoutineInput | null {
		const built: GymRoutineInput['exercises'] = [];
		for (const ex of exercises) {
			const name = ex.name.trim();
			if (name === '') continue;
			built.push({
				exercise_name: name,
				exercise_key: normaliseExerciseName(name),
				position: built.length,
				sets: ex.sets.map((s, i) => ({
					set_index: i,
					target_reps_min: intOrNull(s.reps),
					target_reps_max: null,
					target_weight_kg: parseWeight(s.weight),
					target_rpe: null,
				})),
			});
		}
		if (built.length === 0) return null;
		return { title: title.trim(), notes: notes.trim() || null, exercises: built };
	}

	async function save() {
		if (title.trim() === '') {
			error = t('gym.routine.editor.needTitle');
			return;
		}
		const input = buildInput();
		if (!input) {
			error = t('gym.routine.editor.needExercise');
			return;
		}
		error = '';
		saving = true;
		try {
			const routine = await createGymRoutine(input);
			showToast(t('gym.routine.created'));
			oncreated?.(routine.id);
		} catch (e) {
			console.error('routine save failed', e);
			error = t('gym.routine.saveFailed');
		} finally {
			saving = false;
		}
	}
</script>

<datalist id="routine-exercise-names">
	{#each suggestions as name (name)}
		<option value={name}></option>
	{/each}
</datalist>

<div class="routine-editor">
	<label class="field">
		<span class="section-label">{t('gym.routine.editor.titleLabel')}</span>
		<input
			class="text-input"
			type="text"
			bind:value={title}
			placeholder={t('gym.routine.editor.titlePlaceholder')}
			data-testid="routine-title"
		/>
	</label>

	{#each exercises as ex, ei (ei)}
		<div class="exercise-block card">
			<div class="exercise-head">
				<input
					class="text-input"
					type="text"
					list="routine-exercise-names"
					bind:value={exercises[ei].name}
					placeholder={t('gym.editor.exercisePlaceholder')}
					aria-label={t('gym.editor.exercisePlaceholder')}
					data-testid="routine-exercise-name"
				/>
				<button
					class="icon-btn"
					type="button"
					onclick={() => removeExercise(ei)}
					aria-label={t('gym.editor.removeExercise')}
				>
					<span class="material-symbols" aria-hidden="true">close</span>
				</button>
			</div>
			<div class="set-head">
				<span class="section-label set-cap">{t('gym.routine.targetReps')}</span>
				<span class="section-label set-cap"
					>{t('gym.routine.targetWeight', { unit: weightUnitLabel() })}</span
				>
				<span></span>
			</div>
			{#each ex.sets as _set, si (si)}
				<div class="set-row">
					<input
						class="text-input"
						type="number"
						inputmode="numeric"
						min="0"
						bind:value={exercises[ei].sets[si].reps}
						aria-label={t('gym.routine.targetReps')}
						data-testid="routine-set-reps"
					/>
					<input
						class="text-input"
						type="number"
						inputmode="decimal"
						min="0"
						step="0.5"
						bind:value={exercises[ei].sets[si].weight}
						aria-label={t('gym.routine.targetWeight', { unit: weightUnitLabel() })}
						data-testid="routine-set-weight"
					/>
					<button
						class="icon-btn"
						type="button"
						onclick={() => removeSet(ei, si)}
						aria-label={t('gym.editor.removeSet')}
					>
						<span class="material-symbols" aria-hidden="true">remove</span>
					</button>
				</div>
			{/each}
			<button class="btn btn-sm btn-outline" type="button" onclick={() => addSet(ei)}>
				<span class="material-symbols" aria-hidden="true">add</span>
				{t('gym.editor.addSet')}
			</button>
		</div>
	{/each}

	<button
		class="btn btn-secondary"
		type="button"
		onclick={addExercise}
		data-testid="routine-add-exercise"
	>
		<span class="material-symbols" aria-hidden="true">add</span>
		{t('gym.editor.addExercise')}
	</button>

	<label class="field">
		<span class="section-label">{t('gym.routine.editor.notesLabel')}</span>
		<textarea class="text-input" rows="2" bind:value={notes}></textarea>
	</label>

	{#if error}
		<p class="form-error" role="alert">{error}</p>
	{/if}

	<div class="actions">
		<button class="btn btn-outline" type="button" onclick={oncancel} disabled={saving}>
			{t('gym.routine.editor.cancel')}
		</button>
		<button
			class="btn btn-primary"
			type="button"
			onclick={save}
			disabled={saving}
			data-testid="routine-save"
		>
			{t('gym.routine.editor.save')}
		</button>
	</div>
</div>

<style>
	.routine-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.exercise-block {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		padding: var(--space-sm);
	}
	.exercise-head {
		display: flex;
		gap: var(--space-2xs);
		align-items: center;
	}
	.exercise-head .text-input {
		flex: 1;
	}
	.set-head,
	.set-row {
		display: grid;
		grid-template-columns: 1fr 1fr auto;
		gap: var(--space-2xs);
		align-items: center;
	}
	.icon-btn {
		background: none;
		border: none;
		cursor: pointer;
		color: var(--text-muted);
		padding: var(--space-2xs);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
	.form-error {
		color: var(--danger);
		margin: 0;
	}
</style>
