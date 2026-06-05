<script lang="ts">
	import { goto } from '$app/navigation';
	import { searchFoods, scalePortion, type FoodSearchResult } from '$lib/nutrition/food_search';
	import { createFoodEntry } from '$lib/core/data';
	import { MEAL_SLOTS, type MealSlot } from '$lib/nutrition/nutrition_totals';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import Modal from '$lib/components/Modal.svelte';

	let query = $state('');
	let searching = $state(false);
	let results = $state<FoodSearchResult[]>([]);
	let searched = $state(false);

	// The picked result is confirmed in a portion step before logging.
	let picked = $state<FoodSearchResult | null>(null);
	let portionG = $state<number>(100);
	let mealSlot = $state<MealSlot>('breakfast');
	let saving = $state(false);

	// Manual fallback (no DB match). The macro fields bind to <input
	// type="number">, so Svelte stores a number (or null when empty) — never
	// call string methods on them.
	let manualOpen = $state(false);
	let manualName = $state('');
	let manualKcal = $state<number | null>(null);
	let manualProtein = $state<number | null>(null);
	let manualCarbs = $state<number | null>(null);
	let manualFat = $state<number | null>(null);

	let searchTimer: ReturnType<typeof setTimeout> | null = null;
	function onQueryInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(() => void runSearch(), 350);
	}

	async function runSearch() {
		const q = query.trim();
		if (!q) {
			results = [];
			searched = false;
			return;
		}
		searching = true;
		try {
			results = await searchFoods(q);
		} finally {
			searching = false;
			searched = true;
		}
	}

	function pick(r: FoodSearchResult) {
		picked = r;
		portionG = 100;
	}

	const portionMacros = $derived(
		picked ? scalePortion(picked.per100g, portionG || 0) : null,
	);

	async function confirmLog() {
		if (!picked || !portionMacros) return;
		saving = true;
		try {
			await createFoodEntry({
				item_name: picked.name,
				meal_slot: mealSlot,
				calories: portionMacros.calories,
				protein_g: portionMacros.proteinG,
				carbs_g: portionMacros.carbsG,
				fat_g: portionMacros.fatG,
				external_id: `off:${picked.code}`,
			});
			showToast(m('nutrition.added'), 'success');
			await goto('/nutrition');
		} catch (e) {
			showToast(`${(e as Error).message}`, 'error');
			saving = false;
		}
	}

	async function saveManual() {
		const name = manualName.trim();
		if (!name) return;
		saving = true;
		try {
			await createFoodEntry({
				item_name: name,
				meal_slot: mealSlot,
				calories: manualKcal,
				protein_g: manualProtein,
				carbs_g: manualCarbs,
				fat_g: manualFat,
			});
			showToast(m('nutrition.added'), 'success');
			await goto('/nutrition');
		} catch (e) {
			showToast(`${(e as Error).message}`, 'error');
			saving = false;
		}
	}
</script>

<svelte:head><title>{m('nutrition.logHeading')}</title></svelte:head>

<div class="page">
	<header class="page-head">
		<a class="back-link" href="/nutrition">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{m('nutrition.heading')}
		</a>
		<h1>{m('nutrition.logHeading')}</h1>
	</header>

	<section class="card-elevated search-card">
		<div class="search-field">
			<span class="material-symbols search-icon" aria-hidden="true">search</span>
			<input
				type="search"
				bind:value={query}
				oninput={onQueryInput}
				placeholder={m('nutrition.searchPlaceholder')}
				data-testid="food-search"
				aria-label={m('nutrition.searchPlaceholder')}
			/>
		</div>
		<label class="slot-select">
			<span class="section-label">{m('nutrition.mealSlot')}</span>
			<select class="toolbar-select" bind:value={mealSlot} data-testid="meal-slot">
				{#each MEAL_SLOTS as s (s)}
					<option value={s}>{m(`nutrition.slot_${s}`)}</option>
				{/each}
			</select>
		</label>
	</section>

	{#if searching}
		<div class="results-state" data-testid="searching">
			{#each Array(4) as _, i (i)}
				<div class="skel-result" aria-hidden="true"></div>
			{/each}
			<span class="visually-hidden">{m('nutrition.searching')}</span>
		</div>
	{:else if results.length > 0}
		<ul class="results" data-testid="food-results">
			{#each results as r (r.code)}
				<li>
					<button type="button" class="result" onclick={() => pick(r)}>
						<span class="result-main">
							<span class="result-name">{r.name}</span>
							{#if r.brand}<span class="brand">{r.brand}</span>{/if}
						</span>
						<span class="result-kcal">{Math.round(r.per100g.calories)}<span class="result-kcal-unit"> kcal / 100 g</span></span>
						<span class="material-symbols result-chevron" aria-hidden="true">chevron_right</span>
					</button>
				</li>
			{/each}
		</ul>
	{:else if searched}
		<div class="results-state empty" data-testid="no-results">
			<span class="material-symbols empty-icon" aria-hidden="true">search_off</span>
			<p class="muted">{m('nutrition.noResults')}</p>
		</div>
	{/if}

	<div class="manual-section">
		<button class="btn btn-outline manual-toggle" type="button" aria-expanded={manualOpen} onclick={() => (manualOpen = !manualOpen)}>
			<span class="material-symbols" aria-hidden="true">edit_note</span>
			{m('nutrition.manualEntry')}
		</button>

		{#if manualOpen}
			<section class="card-elevated manual" data-testid="manual-entry">
				<label class="field"><span class="section-label">{m('nutrition.itemName')}</span>
					<input type="text" bind:value={manualName} data-testid="manual-name" /></label>
				<div class="macro-grid">
					<label class="field"><span class="section-label">{m('nutrition.calories')}</span>
						<input type="number" min="0" inputmode="numeric" bind:value={manualKcal} /></label>
					<label class="field"><span class="section-label">{m('nutrition.protein')} (g)</span>
						<input type="number" min="0" inputmode="numeric" bind:value={manualProtein} /></label>
					<label class="field"><span class="section-label">{m('nutrition.carbs')} (g)</span>
						<input type="number" min="0" inputmode="numeric" bind:value={manualCarbs} /></label>
					<label class="field"><span class="section-label">{m('nutrition.fat')} (g)</span>
						<input type="number" min="0" inputmode="numeric" bind:value={manualFat} /></label>
				</div>
				<button class="btn btn-primary manual-save" type="button" disabled={saving || !manualName.trim()} onclick={saveManual}>
					{m('nutrition.add')}
				</button>
			</section>
		{/if}
	</div>
</div>

<Modal open={picked !== null} title={picked?.name ?? ''} narrow onclose={() => (picked = null)} data-testid="portion-dialog">
	{#if picked}
		<div class="portion">
			<label class="field"><span class="section-label">{m('nutrition.portionGrams')}</span>
				<input type="number" min="1" inputmode="numeric" bind:value={portionG} data-testid="portion-grams" /></label>
			{#if portionMacros}
				<div class="portion-macros">
					<div class="portion-cal">
						<span class="portion-cal-val">{portionMacros.calories}</span>
						<span class="portion-cal-unit">kcal</span>
					</div>
					<dl class="portion-grid">
						<div><dt>{m('nutrition.protein')}</dt><dd>{portionMacros.proteinG} g</dd></div>
						<div><dt>{m('nutrition.carbs')}</dt><dd>{portionMacros.carbsG} g</dd></div>
						<div><dt>{m('nutrition.fat')}</dt><dd>{portionMacros.fatG} g</dd></div>
					</dl>
				</div>
			{/if}
			<div class="portion-actions">
				<button class="btn btn-outline" type="button" onclick={() => (picked = null)}>{m('nutrition.cancel')}</button>
				<button class="btn btn-primary" type="button" disabled={saving} onclick={confirmLog} data-testid="confirm-log">
					{m('nutrition.add')}
				</button>
			</div>
		</div>
	{/if}
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 44rem;
	}
	.page-head { display: flex; flex-direction: column; gap: var(--space-xs); }
	.page-head h1 { margin: 0; }
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-weight: 500;
		text-decoration: none;
		align-self: flex-start;
	}
	.back-link:hover { color: var(--color-primary); }
	.back-link .material-symbols { font-size: 1.05rem; }
	.muted { color: var(--color-text-secondary); }

	.search-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.search-field {
		position: relative;
		display: flex;
		align-items: center;
	}
	.search-icon {
		position: absolute;
		inset-inline-start: var(--space-md);
		color: var(--color-text-tertiary);
		font-size: 1.25rem;
		pointer-events: none;
	}
	.search-field input {
		width: 100%;
		padding: var(--space-sm) var(--space-md) var(--space-sm) calc(var(--space-md) + 1.75rem);
		font-size: 1rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}
	.search-field input:focus-visible {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
		background: var(--color-surface);
	}
	.slot-select {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		max-width: 16rem;
	}
	.slot-select .toolbar-select { font-size: 0.95rem; padding: var(--space-sm) calc(var(--space-md) + var(--space-lg)) var(--space-sm) var(--space-md); }

	.results { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: var(--space-xs); }
	.result {
		width: 100%;
		text-align: left;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md);
		cursor: pointer;
		display: flex;
		align-items: center;
		gap: var(--space-md);
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}
	.result:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-sm);
	}
	.result-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: var(--space-2xs); }
	.result-name { font-size: 0.95rem; color: var(--color-text); }
	.brand { color: var(--color-text-secondary); font-size: 0.8rem; }
	.result-kcal {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-text);
		white-space: nowrap;
		font-variant-numeric: tabular-nums;
	}
	.result-kcal-unit { font-size: 0.75rem; font-weight: 500; color: var(--color-text-tertiary); margin-inline-start: 3px; }
	.result-chevron { color: var(--color-text-tertiary); flex-shrink: 0; }

	.results-state {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.results-state.empty {
		align-items: center;
		text-align: center;
		gap: var(--space-sm);
		padding: var(--space-xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-lg);
	}
	.results-state.empty p { margin: 0; }
	.empty-icon { font-size: 2.25rem; color: var(--color-text-tertiary); opacity: 0.7; }
	.skel-result {
		height: 3.5rem;
		border-radius: var(--radius-md);
		background: linear-gradient(90deg, var(--color-bg-tertiary) 25%, var(--color-bg-secondary) 50%, var(--color-bg-tertiary) 75%);
		background-size: 200% 100%;
		animation: shimmer 1.4s ease-in-out infinite;
	}
	@keyframes shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel-result { animation: none; }
	}

	.manual-section { display: flex; flex-direction: column; gap: var(--space-md); }
	.manual-toggle {
		align-self: flex-start;
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.manual-toggle .material-symbols { font-size: 1.1rem; }
	.manual { display: flex; flex-direction: column; gap: var(--space-md); }
	.macro-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-md); }
	.field { display: flex; flex-direction: column; gap: var(--space-xs); }
	.field input {
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		color: var(--color-text);
		font-size: 0.95rem;
	}
	.field input:focus-visible {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
		background: var(--color-surface);
	}
	.manual-save { align-self: flex-start; }

	.portion { display: flex; flex-direction: column; gap: var(--space-lg); }
	.portion-macros {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}
	.portion-cal { display: flex; flex-direction: column; align-items: center; line-height: 1.1; flex-shrink: 0; }
	.portion-cal-val { font-size: 1.6rem; font-weight: 700; color: var(--color-text); font-variant-numeric: tabular-nums; }
	.portion-cal-unit { font-size: 0.75rem; color: var(--color-text-tertiary); text-transform: uppercase; letter-spacing: var(--section-label-tracking); }
	.portion-grid {
		flex: 1;
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-md);
		margin: 0;
	}
	.portion-grid div { display: flex; flex-direction: column; gap: var(--space-2xs); }
	.portion-grid dt {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: var(--section-label-tracking);
		color: var(--color-text-tertiary);
	}
	.portion-grid dd {
		margin: 0;
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.portion-actions { display: flex; justify-content: flex-end; gap: var(--space-sm); }
</style>
