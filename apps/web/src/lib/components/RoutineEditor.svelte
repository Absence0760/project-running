<script lang="ts">
	import { untrack } from 'svelte';
	import { createGymRoutine, type GymRoutineInput } from '$lib/core/data';
	import { normaliseExerciseName } from '$lib/gym/gym_prs';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import { parseWeight, weightInputValue, weightUnitLabel } from '$lib/format/units.svelte';
	import type { PrefillExercise } from '$lib/gym/gym_routine';
	import { assignSupersetGroups } from '$lib/gym/routine_editor_build';
	import type { GymExerciseModality, GymProgressionScheme, GymSetType } from '$lib/types';

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

	type EditSet = {
		setType: GymSetType;
		reps: string;
		repsMax: string;
		weight: string;
		rest: string;
		duration: string;
		distance: string;
	};
	type EditExercise = {
		name: string;
		modality: GymExerciseModality;
		progression: GymProgressionScheme;
		incrementKg: string;
		percent: string;
		oneRm: string;
		targetRpe: string;
		/// Brackets this exercise into a superset with the one below it; a run of
		/// flagged exercises forms one group at build time.
		supersetWithNext: boolean;
		advancedOpen: boolean;
		sets: EditSet[];
	};

	const SET_TYPES: GymSetType[] = ['warmup', 'working', 'dropset', 'amrap', 'failure', 'backoff'];
	const MODALITIES: GymExerciseModality[] = ['weight_reps', 'time', 'distance', 'bodyweight_reps'];
	const SCHEMES: GymProgressionScheme[] = [
		'none',
		'linear',
		'double_progression',
		'five_by_five',
		'percent_cycle',
		'rpe_autoreg',
	];

	function emptySet(): EditSet {
		return {
			setType: 'working',
			reps: '',
			repsMax: '',
			weight: '',
			rest: '',
			duration: '',
			distance: '',
		};
	}

	function emptyExercise(): EditExercise {
		return {
			name: '',
			modality: 'weight_reps',
			progression: 'none',
			incrementKg: '',
			percent: '',
			oneRm: '',
			targetRpe: '',
			supersetWithNext: false,
			advancedOpen: false,
			sets: [emptySet()],
		};
	}

	function initExercises(src: PrefillExercise[] | null): EditExercise[] {
		if (!src || src.length === 0) return [emptyExercise()];
		return src.map((ex) => ({
			...emptyExercise(),
			name: ex.name,
			sets:
				ex.sets.length === 0
					? [emptySet()]
					: ex.sets.map((s) => ({ ...emptySet(), reps: s.reps, weight: weightInputValue(s.weightKg) })),
		}));
	}

	const seed = untrack(() => seedExercises);
	let title = $state(untrack(() => seedTitle));
	let exercises = $state<EditExercise[]>(initExercises(seed));
	let notes = $state('');
	let saving = $state(false);
	let error = $state('');

	function addExercise() {
		exercises = [...exercises, emptyExercise()];
	}
	function removeExercise(i: number) {
		exercises = exercises.filter((_, idx) => idx !== i);
		if (exercises.length === 0) exercises = [emptyExercise()];
	}
	function addSet(ei: number) {
		exercises[ei].sets = [...exercises[ei].sets, emptySet()];
	}
	function removeSet(ei: number, si: number) {
		exercises[ei].sets = exercises[ei].sets.filter((_, idx) => idx !== si);
		if (exercises[ei].sets.length === 0) exercises[ei].sets = [emptySet()];
	}

	function intOrNull(s: string): number | null {
		if (typeof s !== 'string' || s.trim() === '') return null;
		const n = parseInt(s, 10);
		return Number.isFinite(n) ? n : null;
	}
	function floatOrNull(s: string): number | null {
		if (typeof s !== 'string' || s.trim() === '') return null;
		const n = parseFloat(s);
		return Number.isFinite(n) ? n : null;
	}

	function setTypeLabel(s: GymSetType): string {
		return t(`gym.routine.setType.${s}`);
	}
	function modalityLabel(m: GymExerciseModality): string {
		return t(`gym.routine.modality.${m}`);
	}
	function schemeLabel(s: GymProgressionScheme): string {
		return t(`gym.routine.progression.${s}`);
	}

	function progressionParams(ex: EditExercise): Record<string, unknown> {
		const params: Record<string, unknown> = {};
		const inc = floatOrNull(ex.incrementKg);
		if (inc != null) params.incrementKg = parseWeight(ex.incrementKg);
		if (ex.progression === 'percent_cycle') {
			const pct = floatOrNull(ex.percent);
			const oneRm = floatOrNull(ex.oneRm);
			if (pct != null) params.percent = pct / 100;
			if (oneRm != null) params.oneRmKg = parseWeight(ex.oneRm);
		}
		if (ex.progression === 'rpe_autoreg') {
			const rpe = floatOrNull(ex.targetRpe);
			if (rpe != null) params.targetRpe = rpe;
		}
		return params;
	}

	function buildInput(): GymRoutineInput | null {
		// Drop blank-named exercises first so superset linking only sees real
		// rows (a blank row between two flagged blocks must not bridge them).
		const named = exercises.filter((e) => e.name.trim() !== '');
		if (named.length === 0) return null;
		const groups = assignSupersetGroups(named.map((e) => e.supersetWithNext));

		const built: GymRoutineInput['exercises'] = named.map((ex, i) => {
			const isRepModality = ex.modality === 'weight_reps' || ex.modality === 'bodyweight_reps';
			return {
				exercise_name: ex.name.trim(),
				exercise_key: normaliseExerciseName(ex.name.trim()),
				position: i,
				superset_group: groups[i].supersetGroup,
				superset_order: groups[i].supersetOrder,
				modality: ex.modality,
				progression: ex.progression,
				progression_params: progressionParams(ex),
				sets: ex.sets.map((s, si) => ({
					set_index: si,
					set_type: s.setType,
					target_reps_min: isRepModality ? intOrNull(s.reps) : null,
					target_reps_max: isRepModality ? intOrNull(s.repsMax) : null,
					target_weight_kg: ex.modality === 'weight_reps' ? parseWeight(s.weight) : null,
					target_rpe: null,
					rest_s: intOrNull(s.rest),
					target_duration_s: ex.modality === 'time' ? intOrNull(s.duration) : null,
					target_distance_m: ex.modality === 'distance' ? floatOrNull(s.distance) : null,
				})),
			};
		});
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

			<label class="field inline-field">
				<span class="section-label">{t('gym.routine.modality')}</span>
				<select
					class="text-input"
					bind:value={exercises[ei].modality}
					data-testid="routine-modality"
				>
					{#each MODALITIES as md (md)}
						<option value={md}>{modalityLabel(md)}</option>
					{/each}
				</select>
			</label>

			<div class="set-head" class:wr={ex.modality === 'weight_reps'}>
				<span class="section-label set-cap">{t('gym.routine.setType')}</span>
				{#if ex.modality === 'weight_reps' || ex.modality === 'bodyweight_reps'}
					<span class="section-label set-cap">{t('gym.routine.targetReps')}</span>
				{:else if ex.modality === 'time'}
					<span class="section-label set-cap">{t('gym.routine.targetDuration')}</span>
				{:else}
					<span class="section-label set-cap">{t('gym.routine.targetDistance')}</span>
				{/if}
				{#if ex.modality === 'weight_reps'}
					<span class="section-label set-cap"
						>{t('gym.routine.targetWeight', { unit: weightUnitLabel() })}</span
					>
				{/if}
				<span class="section-label set-cap">{t('gym.routine.restLabel')}</span>
				<span></span>
			</div>

			{#each ex.sets as _set, si (si)}
				<div class="set-row" class:wr={ex.modality === 'weight_reps'}>
					<select
						class="text-input"
						bind:value={exercises[ei].sets[si].setType}
						aria-label={t('gym.routine.setType')}
						data-testid="routine-set-type"
					>
						{#each SET_TYPES as st (st)}
							<option value={st}>{setTypeLabel(st)}</option>
						{/each}
					</select>

					{#if ex.modality === 'weight_reps' || ex.modality === 'bodyweight_reps'}
						<span class="rep-range">
							<input
								class="text-input"
								type="number"
								inputmode="numeric"
								min="0"
								bind:value={exercises[ei].sets[si].reps}
								aria-label={t('gym.routine.targetReps')}
								data-testid="routine-set-reps"
							/>
							<span class="range-sep">{t('gym.routine.targetRepsMax')}</span>
							<input
								class="text-input"
								type="number"
								inputmode="numeric"
								min="0"
								bind:value={exercises[ei].sets[si].repsMax}
								aria-label={t('gym.routine.targetRepsMax')}
								data-testid="routine-set-reps-max"
							/>
						</span>
					{:else if ex.modality === 'time'}
						<input
							class="text-input"
							type="number"
							inputmode="numeric"
							min="0"
							bind:value={exercises[ei].sets[si].duration}
							aria-label={t('gym.routine.targetDuration')}
							data-testid="routine-set-duration"
						/>
					{:else}
						<input
							class="text-input"
							type="number"
							inputmode="decimal"
							min="0"
							bind:value={exercises[ei].sets[si].distance}
							aria-label={t('gym.routine.targetDistance')}
							data-testid="routine-set-distance"
						/>
					{/if}

					{#if ex.modality === 'weight_reps'}
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
					{/if}

					<input
						class="text-input"
						type="number"
						inputmode="numeric"
						min="0"
						max="3600"
						bind:value={exercises[ei].sets[si].rest}
						aria-label={t('gym.routine.restLabel')}
						data-testid="routine-set-rest"
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

			<label class="superset-toggle">
				<input
					type="checkbox"
					bind:checked={exercises[ei].supersetWithNext}
					disabled={ei === exercises.length - 1}
					data-testid="routine-superset-toggle"
				/>
				<span>{t('gym.routine.supersetToggle')}</span>
			</label>

			<details bind:open={exercises[ei].advancedOpen} class="advanced">
				<summary>{t('gym.routine.advanced')}</summary>
				<div class="advanced-body">
					<label class="field">
						<span class="section-label">{t('gym.routine.progression')}</span>
						<select
							class="text-input"
							bind:value={exercises[ei].progression}
							data-testid="routine-progression"
						>
							{#each SCHEMES as sc (sc)}
								<option value={sc}>{schemeLabel(sc)}</option>
							{/each}
						</select>
					</label>

					{#if ex.progression === 'linear' || ex.progression === 'double_progression' || ex.progression === 'five_by_five' || ex.progression === 'rpe_autoreg'}
						<label class="field">
							<span class="section-label"
								>{t('gym.routine.progression.incrementLabel', { unit: weightUnitLabel() })}</span
							>
							<input
								class="text-input"
								type="number"
								inputmode="decimal"
								min="0"
								step="0.5"
								bind:value={exercises[ei].incrementKg}
								data-testid="routine-progression-increment"
							/>
						</label>
					{/if}

					{#if ex.progression === 'percent_cycle'}
						<label class="field">
							<span class="section-label">{t('gym.routine.progression.percentLabel')}</span>
							<input
								class="text-input"
								type="number"
								inputmode="decimal"
								min="0"
								max="200"
								bind:value={exercises[ei].percent}
								data-testid="routine-progression-percent"
							/>
						</label>
						<label class="field">
							<span class="section-label"
								>{t('gym.routine.progression.oneRmLabel', { unit: weightUnitLabel() })}</span
							>
							<input
								class="text-input"
								type="number"
								inputmode="decimal"
								min="0"
								bind:value={exercises[ei].oneRm}
								data-testid="routine-progression-onerm"
							/>
						</label>
					{/if}

					{#if ex.progression === 'rpe_autoreg'}
						<label class="field">
							<span class="section-label">{t('gym.routine.progression.targetRpeLabel')}</span>
							<input
								class="text-input"
								type="number"
								inputmode="decimal"
								min="0"
								max="10"
								step="0.5"
								bind:value={exercises[ei].targetRpe}
								data-testid="routine-progression-rpe"
							/>
						</label>
					{/if}
				</div>
			</details>
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
	.inline-field {
		max-width: 16rem;
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
		grid-template-columns: 7rem 1fr 5rem auto;
		gap: var(--space-2xs);
		align-items: center;
	}
	.set-head.wr,
	.set-row.wr {
		grid-template-columns: 7rem 1fr 5rem 5rem auto;
	}
	.rep-range {
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.rep-range .text-input {
		min-width: 0;
	}
	.range-sep {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
	.superset-toggle {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-top: var(--space-2xs);
	}
	.advanced {
		margin-top: var(--space-2xs);
	}
	.advanced summary {
		cursor: pointer;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.advanced-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding-top: var(--space-sm);
	}
	.advanced-body .field {
		max-width: 16rem;
	}
	.icon-btn {
		background: none;
		border: none;
		cursor: pointer;
		color: var(--color-text-tertiary);
		padding: var(--space-2xs);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
	.form-error {
		color: var(--color-danger);
		margin: 0;
	}
</style>
