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
		<a class="back-link" href="/nutrition">← {m('nutrition.heading')}</a>
		<h1>{m('nutrition.logHeading')}</h1>
	</header>

	<div class="search-row">
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
		<span class="label-text">{m('nutrition.mealSlot')}</span>
		<select bind:value={mealSlot} data-testid="meal-slot">
			{#each MEAL_SLOTS as s (s)}
				<option value={s}>{m(`nutrition.slot_${s}`)}</option>
			{/each}
		</select>
	</label>

	{#if searching}
		<p class="muted">{m('nutrition.searching')}</p>
	{:else if results.length > 0}
		<ul class="results" data-testid="food-results">
			{#each results as r (r.code)}
				<li>
					<button type="button" class="result" onclick={() => pick(r)}>
						<span class="result-name">{r.name}{#if r.brand} · <span class="brand">{r.brand}</span>{/if}</span>
						<span class="result-kcal">{r.per100g.calories} kcal / 100 g</span>
					</button>
				</li>
			{/each}
		</ul>
	{:else if searched}
		<p class="muted" data-testid="no-results">{m('nutrition.noResults')}</p>
	{/if}

	<button class="btn btn-outline manual-toggle" type="button" onclick={() => (manualOpen = !manualOpen)}>
		{m('nutrition.manualEntry')}
	</button>

	{#if manualOpen}
		<section class="card manual" data-testid="manual-entry">
			<label><span class="label-text">{m('nutrition.itemName')}</span>
				<input type="text" bind:value={manualName} data-testid="manual-name" /></label>
			<div class="macro-grid">
				<label><span class="label-text">{m('nutrition.calories')}</span>
					<input type="number" min="0" inputmode="numeric" bind:value={manualKcal} /></label>
				<label><span class="label-text">{m('nutrition.protein')} (g)</span>
					<input type="number" min="0" inputmode="numeric" bind:value={manualProtein} /></label>
				<label><span class="label-text">{m('nutrition.carbs')} (g)</span>
					<input type="number" min="0" inputmode="numeric" bind:value={manualCarbs} /></label>
				<label><span class="label-text">{m('nutrition.fat')} (g)</span>
					<input type="number" min="0" inputmode="numeric" bind:value={manualFat} /></label>
			</div>
			<button class="btn btn-primary" type="button" disabled={saving || !manualName.trim()} onclick={saveManual}>
				{m('nutrition.add')}
			</button>
		</section>
	{/if}
</div>

<Modal open={picked !== null} title={picked?.name ?? ''} narrow onclose={() => (picked = null)} data-testid="portion-dialog">
	{#if picked}
		<div class="portion">
			<label><span class="label-text">{m('nutrition.portionGrams')}</span>
				<input type="number" min="1" inputmode="numeric" bind:value={portionG} data-testid="portion-grams" /></label>
			{#if portionMacros}
				<p class="portion-macros">
					{portionMacros.calories} kcal · {portionMacros.proteinG}g P · {portionMacros.carbsG}g C · {portionMacros.fatG}g F
				</p>
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
	.page { padding: var(--space-xl) var(--space-2xl); display: flex; flex-direction: column; gap: var(--space-md); max-width: 48rem; }
	.page-head { display: flex; flex-direction: column; gap: 0.25rem; }
	.back-link { color: var(--color-text-secondary); font-size: 0.9rem; text-decoration: none; }
	.search-row input { width: 100%; }
	.slot-select { display: flex; flex-direction: column; gap: 0.25rem; max-width: 16rem; }
	.muted { color: var(--color-text-secondary); }
	.results { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: var(--space-xs); }
	.result { width: 100%; text-align: left; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: var(--space-sm) var(--space-md); cursor: pointer; display: flex; flex-direction: column; gap: 2px; }
	.result:hover { border-color: var(--color-accent, #D97A54); }
	.result-name { font-size: 0.95rem; }
	.brand { color: var(--color-text-secondary); }
	.result-kcal { font-size: 0.8rem; color: var(--color-text-secondary); }
	.manual-toggle { align-self: flex-start; }
	.manual { display: flex; flex-direction: column; gap: var(--space-sm); }
	.macro-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-sm); }
	.label-text { font-size: 0.8rem; color: var(--color-text-secondary); }
	.portion { display: flex; flex-direction: column; gap: var(--space-md); }
	.portion-macros { color: var(--color-text-secondary); font-size: 0.9rem; margin: 0; }
	.portion-actions { display: flex; justify-content: flex-end; gap: var(--space-sm); }
</style>
