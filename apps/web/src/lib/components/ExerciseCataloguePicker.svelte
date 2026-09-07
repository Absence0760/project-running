<script lang="ts">
	import { untrack } from 'svelte';
	import type { Exercise, ExerciseCategory } from '$lib/types';
	import { createCustomExercise } from '$lib/core/data';
	import { cataloguePickerView } from './exercise_catalogue_picker';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	interface Props {
		/// The catalogue to browse — seeded globals + the user's customs, as
		/// supplied to GymEditor (migration 20270222_001).
		catalogue: Exercise[];
		/// Pick a catalogue entry. The host fills the exercise name from it; the
		/// entry's normalised key binds its exercise_id at save time.
		onpick: (exercise: Exercise) => void;
		/// A freshly-created owner custom. The host merges it into its binding map
		/// so a name typed/picked from it links its id even before the next reload.
		oncreated?: (exercise: Exercise) => void;
	}

	let { catalogue, onpick, oncreated }: Props = $props();

	// The category filter dropdown order: an "all" sentinel plus the nine
	// catalogue categories (exercises.category CHECK, migration 20270222_001).
	const CATEGORIES: ExerciseCategory[] = [
		'chest',
		'back',
		'shoulders',
		'legs',
		'arms',
		'core',
		'cardio',
		'full_body',
		'other',
	];

	let query = $state('');
	let category = $state<ExerciseCategory | 'all'>('all');

	// A local copy so a just-created custom appears in the list immediately,
	// without waiting for the host to reload the catalogue from the server.
	let entries = $state<Exercise[]>(untrack(() => [...catalogue]));

	// The picker's three states — a result list, an explanation, a create
	// affordance — are decided by `cataloguePickerView`, a pure module the unit
	// suite can hold. They used to be three `$derived` expressions here, which
	// is why the fix that closed § 1276's dead end shipped with no behavioural
	// pin (§ 1278) and why the residual half of that dead end survived it: the
	// exact-match test scanned the whole catalogue while the list also applied
	// the category filter, so an exact name in another category rendered
	// "No exercises match." beside no create button and no explanation.
	const view = $derived(cataloguePickerView(entries, { query, category }));

	function categoryLabel(c: ExerciseCategory): string {
		return t(`gym.catalogue.category.${c}`);
	}

	let creating = $state(false);

	const trimmed = $derived(query.trim());
	const canCreate = $derived(view.canCreate && !creating);

	async function create() {
		const name = trimmed;
		if (name === '' || creating) return;
		creating = true;
		const made = await createCustomExercise({
			name,
			category: category === 'all' ? 'other' : category,
		});
		creating = false;
		if (!made) {
			showToast(t('gym.catalogue.createFailed'));
			return;
		}
		entries = [...entries, made];
		oncreated?.(made);
		onpick(made);
	}
</script>

<div class="catalogue-picker" data-testid="exercise-catalogue-picker">
	<div class="controls">
		<label class="search">
			<span class="material-symbols" aria-hidden="true">search</span>
			<input
				type="text"
				bind:value={query}
				placeholder={t('gym.catalogue.searchPlaceholder')}
				aria-label={t('gym.catalogue.searchPlaceholder')}
				data-testid="catalogue-search"
			/>
		</label>
		<label class="filter">
			<span class="section-label">{t('gym.catalogue.categoryLabel')}</span>
			<select bind:value={category} data-testid="catalogue-category" aria-label={t('gym.catalogue.categoryLabel')}>
				<option value="all">{t('gym.catalogue.category.all')}</option>
				{#each CATEGORIES as c (c)}
					<option value={c}>{categoryLabel(c)}</option>
				{/each}
			</select>
		</label>
	</div>

	{#if view.matches.length > 0}
		<ul class="results" data-testid="catalogue-results">
			{#each view.matches as e (e.id)}
				<li>
					<button type="button" class="result" onclick={() => onpick(e)} data-testid="catalogue-pick">
						<span class="name">{e.name}</span>
						<span class="meta">
							{#if e.author_id}
								<span class="badge custom">{t('gym.catalogue.customBadge')}</span>
							{/if}
							<span class="cat">{categoryLabel(e.category)}</span>
						</span>
					</button>
				</li>
			{/each}
		</ul>
	{:else if view.hiddenExact}
		<p class="empty" data-testid="catalogue-other-category">
			{t('gym.catalogue.otherCategory', {
				name: view.hiddenExact.name,
				category: categoryLabel(view.hiddenExact.category),
			})}
		</p>
	{:else if !canCreate}
		<p class="empty">{t('gym.catalogue.empty')}</p>
	{/if}

	{#if canCreate}
		<button type="button" class="btn btn-outline create" onclick={create} disabled={creating} data-testid="catalogue-create">
			<span class="material-symbols" aria-hidden="true">add</span>
			{t('gym.catalogue.create', { name: trimmed })}
		</button>
	{/if}
</div>

<style>
	.catalogue-picker {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.controls {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.search {
		flex: 1 1 12rem;
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding-inline: var(--space-sm);
		background: var(--color-surface);
	}
	.search .material-symbols {
		font-size: 1.1rem;
		color: var(--color-text-tertiary);
	}
	.search input {
		border: none;
		background: none;
		flex: 1;
		min-width: 0;
		height: 2.4rem;
	}
	.search input:focus {
		outline: none;
	}
	.search input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.filter {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.filter select {
		height: 2.4rem;
	}
	.results {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		max-height: 22rem;
		overflow-y: auto;
	}
	.result {
		width: 100%;
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		cursor: pointer;
		text-align: start;
		color: inherit;
		transition: border-color var(--transition-fast);
	}
	.result:hover {
		border-color: var(--color-primary);
	}
	.result:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.name {
		font-weight: 600;
	}
	.meta {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		flex-shrink: 0;
	}
	.cat {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.badge.custom {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		letter-spacing: 0.03em;
		color: var(--color-primary);
		background: var(--color-primary-light);
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
	}
	.empty {
		margin: 0;
		padding: var(--space-lg);
		text-align: center;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.create {
		align-self: flex-start;
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
	}
	.create .material-symbols {
		font-size: 1.05rem;
	}
</style>
