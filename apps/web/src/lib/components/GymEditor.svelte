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
		<span>{t('gym.editor.titleLabel')}</span>
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
					<span class="material-symbols-outlined">delete</span>
				</button>
			</div>
			{#each ex.sets as _set, si (si)}
				<div class="set-row">
					<span class="set-label">{t('gym.setN', { n: si + 1 })}</span>
					<label>
						<span class="set-cap">{t('gym.reps')}</span>
						<input type="number" inputmode="numeric" min="0" bind:value={exercises[ei].sets[si].reps} />
					</label>
					<label>
						<span class="set-cap">{t('gym.weightUnit', { unit: weightUnitLabel() })}</span>
						<input type="number" inputmode="decimal" min="0" step="0.5" bind:value={exercises[ei].sets[si].weight} />
					</label>
					<label>
						<span class="set-cap">{t('gym.rpe')}</span>
						<input type="number" inputmode="decimal" min="0" max="10" step="0.5" bind:value={exercises[ei].sets[si].rpe} />
					</label>
					<button
						type="button"
						class="icon-btn"
						title={t('gym.editor.removeSet')}
						aria-label={t('gym.editor.removeSet')}
						onclick={() => removeSet(ei, si)}
					>
						<span class="material-symbols-outlined">close</span>
					</button>
				</div>
			{/each}
			<button type="button" class="btn btn-sm btn-outline add-set" onclick={() => addSet(ei)}>
				{t('gym.editor.addSet')}
			</button>
		</div>
	{/each}

	<button type="button" class="btn btn-outline add-exercise" onclick={addExercise}>
		{t('gym.editor.addExercise')}
	</button>

	<label class="share-row">
		<input type="checkbox" bind:checked={isPublic} />
		<span>{t('gym.editor.share')}</span>
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
		gap: var(--space-2xs);
	}
	.field > span {
		font-size: 0.85rem;
		color: var(--text-secondary);
	}
	input[type='text'],
	input[type='number'] {
		padding: var(--space-2xs) var(--space-sm);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
		background: var(--surface);
		color: var(--text-primary);
		font: inherit;
		width: 100%;
	}
	.exercise {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md);
		border: 1px solid var(--border);
		border-radius: var(--radius-md);
		background: var(--surface-subtle, var(--surface));
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
	.set-row {
		display: grid;
		grid-template-columns: auto 1fr 1fr 1fr auto;
		gap: var(--space-sm);
		align-items: end;
	}
	.set-label {
		font-size: 0.8rem;
		color: var(--text-secondary);
		padding-bottom: var(--space-2xs);
		white-space: nowrap;
	}
	.set-row label {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.set-cap {
		font-size: 0.7rem;
		color: var(--text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.02em;
	}
	.icon-btn {
		background: none;
		border: none;
		cursor: pointer;
		color: var(--text-secondary);
		padding: var(--space-2xs);
		border-radius: var(--radius-sm);
		display: inline-flex;
	}
	.icon-btn:hover {
		color: var(--danger, #c0392b);
		background: var(--surface);
	}
	.add-set {
		align-self: flex-start;
	}
	.add-exercise {
		align-self: flex-start;
	}
	.share-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.9rem;
	}
	.share-row input {
		width: auto;
	}
	.error {
		color: var(--danger, #c0392b);
		font-size: 0.9rem;
		margin: 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
	@media (max-width: 480px) {
		.set-row {
			grid-template-columns: 1fr 1fr 1fr auto;
		}
		.set-label {
			grid-column: 1 / -1;
		}
	}
</style>
