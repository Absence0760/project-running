<script lang="ts">
	import { untrack } from 'svelte';
	import {
		createGymWorkout,
		updateGymWorkout,
		type GymWorkoutWithSets,
		type GymSetInput,
	} from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import { parseWeight, weightInputValue, weightUnitLabel } from '$lib/format/units.svelte';

	interface Props {
		existing?: GymWorkoutWithSets | null;
		/// Distinct exercise names from the user's history, for the datalist
		/// autocomplete (multi_modal.md § Gym — "autocomplete from the
		/// user's own history, not a database").
		suggestions?: string[];
		oncreated?: () => void;
		onupdated?: () => void;
		oncancel: () => void;
	}

	let { existing = null, suggestions = [], oncreated, onupdated, oncancel }: Props = $props();

	type EditSet = { reps: string; weight: string; rpe: string };
	type EditExercise = { name: string; sets: EditSet[] };

	function emptySet(): EditSet {
		return { reps: '', weight: '', rpe: '' };
	}

	/// Reconstruct exercise blocks from a stored workout. Sets arrive in
	/// set_index order grouped by exercise (that's how the composer writes
	/// them), so consecutive runs of the same exercise_name rebuild a block.
	/// Takes `src` as a param so the prop read happens in the `$state`
	/// initializer (a legitimate one-time read), not in a free function.
	function initExercises(src: GymWorkoutWithSets | null): EditExercise[] {
		if (!src || src.sets.length === 0) {
			return [{ name: '', sets: [emptySet()] }];
		}
		const blocks: EditExercise[] = [];
		for (const s of src.sets) {
			const last = blocks[blocks.length - 1];
			const row: EditSet = {
				reps: s.reps == null ? '' : String(s.reps),
				// Stored kg -> the user's display unit for editing; parsed back
				// to kg on save. Storage stays canonical kg.
				weight: weightInputValue(s.weight_kg),
				rpe: s.rpe == null ? '' : String(s.rpe),
			};
			if (last && last.name === s.exercise_name) last.sets.push(row);
			else blocks.push({ name: s.exercise_name, sets: [row] });
		}
		return blocks;
	}

	// The editor is mounted fresh each time the host modal opens, so the
	// prop is read once at construction to seed local state. untrack keeps
	// that one-time read from registering a (never-changing) dependency.
	const seed = untrack(() => existing);
	let title = $state(seed?.workout.title ?? '');
	let isPublic = $state(seed?.workout.is_public ?? false);
	let exercises = $state<EditExercise[]>(initExercises(seed));
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

	function num(s: string): number | null {
		const n = parseFloat(s);
		return Number.isFinite(n) ? n : null;
	}

	function buildSets(): GymSetInput[] {
		const out: GymSetInput[] = [];
		for (const ex of exercises) {
			const name = ex.name.trim();
			if (name === '') continue;
			for (const set of ex.sets) {
				out.push({
					exercise_name: name,
					reps: num(set.reps),
					// The field carries the user's chosen unit; persist canonical kg.
					weight_kg: parseWeight(set.weight),
					rpe: num(set.rpe),
				});
			}
		}
		return out;
	}

	async function save() {
		const sets = buildSets();
		if (sets.length === 0) {
			error = t('gym.editor.needExercise');
			return;
		}
		error = '';
		saving = true;
		try {
			if (existing) {
				await updateGymWorkout(
					existing.workout.id,
					{ title: title.trim() || null, is_public: isPublic },
					sets,
				);
				showToast(t('gym.updated'));
				onupdated?.();
			} else {
				await createGymWorkout({ title: title.trim() || null, is_public: isPublic, sets });
				showToast(t('gym.created'));
				oncreated?.();
			}
		} catch (e) {
			console.error('gym save failed', e);
			error = t('gym.saveFailed');
		} finally {
			saving = false;
		}
	}
</script>

<div class="gym-editor">
	<label class="field">
		<span class="section-label">{t('gym.editor.titleLabel')}</span>
		<input type="text" bind:value={title} placeholder={t('gym.editor.titlePlaceholder')} />
	</label>

	<datalist id="gym-exercise-suggestions">
		{#each suggestions as s (s)}
			<option value={s}></option>
		{/each}
	</datalist>

	{#each exercises as ex, ei (ei)}
		<div class="exercise">
			<div class="exercise-head">
				<input
					class="exercise-name"
					type="text"
					list="gym-exercise-suggestions"
					bind:value={exercises[ei].name}
					placeholder={t('gym.editor.exercisePlaceholder')}
				/>
				<button
					type="button"
					class="icon-btn"
					title={t('gym.editor.removeExercise')}
					aria-label={t('gym.editor.removeExercise')}
					onclick={() => removeExercise(ei)}
				>
					<span class="material-symbols">delete</span>
				</button>
			</div>
			<div class="set-grid">
				<div class="set-head" aria-hidden="true">
					<span class="set-label"></span>
					<span class="set-cap">{t('gym.reps')}</span>
					<span class="set-cap">{t('gym.weightUnit', { unit: weightUnitLabel() })}</span>
					<span class="set-cap">{t('gym.rpe')}</span>
					<span></span>
				</div>
				{#each ex.sets as _set, si (si)}
					<div class="set-row">
						<span class="set-label">{t('gym.setN', { n: si + 1 })}</span>
						<label class="set-field">
							<span class="set-cap set-cap-inline">{t('gym.reps')}</span>
							<input
								type="number"
								inputmode="numeric"
								min="0"
								aria-label={t('gym.reps')}
								bind:value={exercises[ei].sets[si].reps}
							/>
						</label>
						<label class="set-field">
							<span class="set-cap set-cap-inline">{t('gym.weightUnit', { unit: weightUnitLabel() })}</span>
							<input
								type="number"
								inputmode="decimal"
								min="0"
								step="0.5"
								aria-label={t('gym.weightUnit', { unit: weightUnitLabel() })}
								bind:value={exercises[ei].sets[si].weight}
							/>
						</label>
						<label class="set-field">
							<span class="set-cap set-cap-inline">{t('gym.rpe')}</span>
							<input
								type="number"
								inputmode="decimal"
								min="0"
								max="10"
								step="0.5"
								aria-label={t('gym.rpe')}
								bind:value={exercises[ei].sets[si].rpe}
							/>
						</label>
						<button
							type="button"
							class="icon-btn set-remove"
							title={t('gym.editor.removeSet')}
							aria-label={t('gym.editor.removeSet')}
							onclick={() => removeSet(ei, si)}
						>
							<span class="material-symbols">close</span>
						</button>
					</div>
				{/each}
			</div>
			<button type="button" class="btn btn-sm btn-outline add-set" onclick={() => addSet(ei)}>
				<span class="material-symbols">add</span>
				{t('gym.editor.addSet')}
			</button>
		</div>
	{/each}

	<button type="button" class="btn btn-outline add-exercise" onclick={addExercise}>
		<span class="material-symbols">add</span>
		{t('gym.editor.addExercise')}
	</button>

	<label class="share-row">
		<input type="checkbox" bind:checked={isPublic} />
		<span class="share-text">
			<span class="share-title">{t('gym.editor.share')}</span>
			<span class="share-hint">{t('gym.editor.shareHint')}</span>
		</span>
	</label>

	{#if error}
		<p class="error" role="alert">{error}</p>
	{/if}

	<div class="actions">
		<button type="button" class="btn btn-secondary" onclick={oncancel} disabled={saving}>
			{t('gym.editor.cancel')}
		</button>
		<button type="button" class="btn btn-primary" onclick={save} disabled={saving}>
			{t('gym.editor.save')}
		</button>
	</div>
</div>

<style>
	.gym-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	input[type='text'],
	input[type='number'] {
		padding: 0.5rem 0.65rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font: inherit;
		font-size: 0.9rem;
		width: 100%;
		min-width: 0;
		height: 2.4rem;
		transition: border-color var(--transition-fast);
	}
	input[type='text']:focus,
	input[type='number']:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}
	input[type='number'] {
		font-variant-numeric: tabular-nums;
		text-align: center;
	}

	.exercise {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-md) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-bg-secondary);
	}
	.exercise-head {
		display: flex;
		gap: var(--space-sm);
		align-items: center;
	}
	.exercise-name {
		flex: 1;
		font-weight: 600;
	}

	.set-grid {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	/* Shared column template so the header row and every set row align
	   the reps / weight / RPE inputs into a clean spreadsheet. */
	.set-head,
	.set-row {
		display: grid;
		grid-template-columns: 3.5rem repeat(3, 1fr) 2rem;
		gap: var(--space-sm);
		align-items: center;
	}
	.set-head {
		padding-inline: 0;
	}
	.set-head .set-cap {
		text-align: center;
	}
	.set-label {
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		white-space: nowrap;
	}
	.set-field {
		display: block;
		min-width: 0;
	}
	/* Inline per-input captions only surface on the narrow single-column
	   layout, where the shared header row is hidden. */
	.set-cap-inline {
		display: none;
	}
	.set-cap {
		font-size: 0.65rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.icon-btn {
		background: none;
		border: none;
		cursor: pointer;
		color: var(--color-text-tertiary);
		padding: var(--space-2xs);
		border-radius: var(--radius-sm);
		display: inline-flex;
		align-items: center;
		justify-content: center;
	}
	.icon-btn:hover {
		color: var(--color-danger);
		background: var(--color-danger-light);
	}
	.icon-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.set-remove {
		justify-self: center;
	}

	.add-set,
	.add-exercise {
		align-self: flex-start;
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.add-set .material-symbols,
	.add-exercise .material-symbols {
		font-size: 1.05rem;
	}

	.share-row {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		cursor: pointer;
	}
	.share-row input {
		width: auto;
		margin-top: 0.15rem;
		accent-color: var(--color-primary);
	}
	.share-text {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.share-title {
		font-size: 0.9rem;
		font-weight: 500;
		color: var(--color-text);
	}
	.share-hint {
		font-size: 0.78rem;
		color: var(--color-text-secondary);
	}

	.error {
		color: var(--color-danger);
		font-size: 0.9rem;
		margin: 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
		padding-top: var(--space-xs);
	}

	@media (max-width: 480px) {
		/* Stack each set as a labelled 3-up block so inputs stay legible on
		   a phone — the shared header row is dropped in favour of inline
		   captions above each input. */
		.set-head {
			display: none;
		}
		.set-row {
			grid-template-columns: 1fr 1fr 1fr 2rem;
			align-items: end;
			row-gap: var(--space-xs);
			padding: var(--space-sm);
			border: 1px solid var(--color-border);
			border-radius: var(--radius-md);
			background: var(--color-surface);
		}
		.set-label {
			grid-column: 1 / -1;
		}
		.set-field {
			display: flex;
			flex-direction: column;
			gap: 0.15rem;
		}
		.set-cap-inline {
			display: block;
		}
		.set-remove {
			align-self: end;
			margin-bottom: 0.1rem;
		}
	}
</style>
