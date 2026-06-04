<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import {
		fetchFoodLog,
		fetchLatestWeightKg,
		deleteFoodEntry,
		type FoodEntry,
	} from '$lib/core/data';
	import { loadSettings, effective } from '$lib/settings/settings';
	import {
		computeNutritionTargets,
		ageFromDob,
		type ActivityLevel,
		type WeightGoal,
		type NutritionTargets,
	} from '$lib/nutrition/nutrition_targets';
	import {
		sumMacros,
		groupByMealSlot,
		ringFraction,
		type MealSlotGroup,
	} from '$lib/nutrition/nutrition_totals';
	import type { FoodMacros } from '$lib/nutrition/food_search';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	let loading = $state(true);
	let entries = $state<FoodEntry[]>([]);
	let targets = $state<NutritionTargets | null>(null);
	let weekDays = $state<{ label: string; calories: number }[]>([]);
	let waterMl = $state(0);

	const WATER_UNIT_ML = 250;

	function dayStartIso(d: Date): string {
		const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
		return x.toISOString();
	}
	function todayKey(): string {
		const d = new Date();
		return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
	}

	const consumed = $derived<FoodMacros>(sumMacros(entries));
	const groups = $derived<MealSlotGroup<FoodEntry>[]>(groupByMealSlot(entries));

	function waterStorageKey(): string {
		return `water_ml_${todayKey()}`;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) {
			loading = false;
			return;
		}
		try {
			const now = new Date();
			const todayStart = dayStartIso(now);
			const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
			entries = await fetchFoodLog(todayStart, tomorrow.toISOString());

			// Targets: assemble body metrics + activity/goal prefs.
			const [settings, weightKg, profileRes] = await Promise.all([
				loadSettings(auth.user.id),
				fetchLatestWeightKg(),
				supabase.rpc('get_my_profile'),
			]);
			const prof = profileRes.data as
				| { height_cm: number | null; date_of_birth: string | null; gender: string | null }
				| null;
			targets = computeNutritionTargets({
				weightKg,
				heightCm: prof?.height_cm ?? null,
				ageYears: ageFromDob(prof?.date_of_birth, Date.now()),
				sex: prof?.gender ?? null,
				activityLevel: effective<ActivityLevel>(settings, 'nutrition_activity_level', 'moderate') ?? 'moderate',
				goal: effective<WeightGoal>(settings, 'nutrition_goal', 'maintain') ?? 'maintain',
			});

			// Weekly calorie trend (last 7 days incl. today).
			const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6);
			const weekEntries = await fetchFoodLog(weekStart.toISOString(), tomorrow.toISOString());
			const byDay = new Map<string, number>();
			for (const e of weekEntries) {
				const d = new Date(e.started_at);
				const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
				byDay.set(key, (byDay.get(key) ?? 0) + (e.calories ?? 0));
			}
			const days: { label: string; calories: number }[] = [];
			for (let i = 6; i >= 0; i--) {
				const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
				const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
				days.push({
					label: d.toLocaleDateString(undefined, { weekday: 'short' }),
					calories: Math.round(byDay.get(key) ?? 0),
				});
			}
			weekDays = days;

			const stored = localStorage.getItem(waterStorageKey());
			waterMl = stored ? Number(stored) || 0 : 0;
		} catch (e) {
			console.warn('nutrition load failed', e);
		}
		loading = false;
	});

	function addWater() {
		waterMl += WATER_UNIT_ML;
		localStorage.setItem(waterStorageKey(), String(waterMl));
	}
	function removeWater() {
		waterMl = Math.max(0, waterMl - WATER_UNIT_ML);
		localStorage.setItem(waterStorageKey(), String(waterMl));
	}

	async function removeEntry(id: string) {
		try {
			await deleteFoodEntry(id);
			entries = entries.filter((e) => e.id !== id);
		} catch (e) {
			showToast(`Delete failed: ${(e as Error).message}`, 'error');
		}
	}

	// Ring geometry — circumference of an r=26 circle.
	const R = 26;
	const CIRC = 2 * Math.PI * R;
	type RingDef = { key: string; label: string; consumed: number; target: number | null; unit: string };
	const rings = $derived<RingDef[]>([
		{ key: 'calories', label: m('nutrition.calories'), consumed: consumed.calories, target: targets?.calories ?? null, unit: 'kcal' },
		{ key: 'protein', label: m('nutrition.protein'), consumed: consumed.proteinG, target: targets?.proteinG ?? null, unit: 'g' },
		{ key: 'carbs', label: m('nutrition.carbs'), consumed: consumed.carbsG, target: targets?.carbsG ?? null, unit: 'g' },
		{ key: 'fat', label: m('nutrition.fat'), consumed: consumed.fatG, target: targets?.fatG ?? null, unit: 'g' },
	]);
	const maxWeekCalories = $derived(Math.max(1, ...weekDays.map((d) => d.calories)));
	const hasAnyData = $derived(entries.length > 0 || weekDays.some((d) => d.calories > 0));
</script>

<svelte:head><title>{m('nutrition.heading')}</title></svelte:head>

<div class="page">
	<header class="page-head">
		<h1>{m('nutrition.heading')}</h1>
		<a class="btn btn-primary" href="/nutrition/log" data-testid="log-food">{m('nutrition.logFood')}</a>
	</header>

	{#if loading}
		<p class="muted">{m('nutrition.loading')}</p>
	{:else}
		<section class="card rings-card" data-testid="macro-rings">
			<div class="rings">
				{#each rings as r (r.key)}
					{@const frac = ringFraction(r.consumed, r.target)}
					<div class="ring">
						<svg viewBox="0 0 64 64" width="72" height="72" aria-hidden="true">
							<circle class="ring-bg" cx="32" cy="32" r={R} stroke-width="6" fill="none" />
							{#if frac !== null}
								<circle
									class="ring-fg"
									cx="32" cy="32" r={R} stroke-width="6" fill="none"
									stroke-dasharray={`${frac * CIRC} ${CIRC}`}
									transform="rotate(-90 32 32)"
								/>
							{/if}
						</svg>
						<div class="ring-text">
							<span class="ring-val">{r.consumed}</span>
							{#if r.target !== null}<span class="ring-target">/ {r.target}</span>{/if}
						</div>
						<span class="ring-label">{r.label}</span>
					</div>
				{/each}
			</div>
			{#if !targets}
				<p class="section-hint" data-testid="no-targets">{m('nutrition.noTargets')}</p>
			{/if}
		</section>

		<section class="card water-card">
			<div class="water-head">
				<span class="water-label">{m('nutrition.water')}</span>
				<span class="water-amount">{(waterMl / 1000).toFixed(2).replace(/\.?0+$/, '')} L</span>
			</div>
			<div class="water-controls">
				<button class="btn btn-outline btn-sm" type="button" onclick={removeWater} aria-label={m('nutrition.waterRemove')}>−</button>
				<span class="water-units">{Math.round(waterMl / WATER_UNIT_ML)} × 250 ml</span>
				<button class="btn btn-primary btn-sm" type="button" onclick={addWater} data-testid="add-water" aria-label={m('nutrition.waterAdd')}>＋</button>
			</div>
		</section>

		{#if groups.length === 0}
			<section class="card empty">
				<p>{m('nutrition.empty')}</p>
				<a class="btn btn-primary" href="/nutrition/log">{m('nutrition.logFood')}</a>
			</section>
		{:else}
			{#each groups as g (g.slot)}
				<section class="card meal-group">
					<div class="meal-head">
						<h2>{m(`nutrition.slot_${g.slot}`)}</h2>
						<span class="meal-kcal">{g.calories} kcal</span>
					</div>
					<ul class="meal-list">
						{#each g.entries as e (e.id)}
							<li>
								<div class="item-main">
									<span class="item-name">{e.item_name}</span>
									<span class="item-macros">
										{#if e.protein_g}{e.protein_g}g P · {/if}{#if e.carbs_g}{e.carbs_g}g C · {/if}{#if e.fat_g}{e.fat_g}g F{/if}
									</span>
								</div>
								<span class="item-kcal">{e.calories ?? 0}</span>
								<button class="icon-btn" type="button" onclick={() => removeEntry(e.id)} aria-label={m('nutrition.delete')}>×</button>
							</li>
						{/each}
					</ul>
				</section>
			{/each}
		{/if}

		{#if hasAnyData}
			<section class="card trend-card">
				<h2>{m('nutrition.weeklyTrend')}</h2>
				<div class="trend-bars">
					{#each weekDays as d (d.label + d.calories)}
						<div class="trend-col">
							<div class="trend-bar" style={`height: ${Math.round((d.calories / maxWeekCalories) * 100)}%`}></div>
							<span class="trend-day">{d.label}</span>
						</div>
					{/each}
				</div>
			</section>
		{/if}
	{/if}
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); display: flex; flex-direction: column; gap: var(--space-lg); }
	.page-head { display: flex; align-items: center; justify-content: space-between; gap: var(--space-md); }
	.muted { color: var(--color-text-secondary); }
	.rings { display: flex; gap: var(--space-lg); flex-wrap: wrap; }
	.ring { display: flex; flex-direction: column; align-items: center; position: relative; min-width: 72px; }
	.ring svg { display: block; }
	.ring-bg { stroke: var(--color-border); }
	.ring-fg { stroke: var(--color-accent, #D97A54); stroke-linecap: round; transition: stroke-dasharray 0.3s; }
	.ring-text { position: absolute; top: 26px; display: flex; flex-direction: column; align-items: center; line-height: 1; }
	.ring-val { font-weight: 600; font-size: 0.85rem; }
	.ring-target { font-size: 0.65rem; color: var(--color-text-secondary); }
	.ring-label { margin-top: 0.35rem; font-size: 0.75rem; color: var(--color-text-secondary); }
	.water-head { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: var(--space-sm); }
	.water-label { font-weight: 600; }
	.water-controls { display: flex; align-items: center; gap: var(--space-md); }
	.water-units { color: var(--color-text-secondary); font-size: 0.9rem; }
	.meal-head { display: flex; justify-content: space-between; align-items: baseline; }
	.meal-head h2 { margin: 0; font-size: 1rem; }
	.meal-kcal { color: var(--color-text-secondary); font-size: 0.9rem; }
	.meal-list { list-style: none; margin: var(--space-sm) 0 0; padding: 0; display: flex; flex-direction: column; gap: var(--space-xs); }
	.meal-list li { display: flex; align-items: center; gap: var(--space-md); }
	.item-main { flex: 1; display: flex; flex-direction: column; }
	.item-name { font-size: 0.95rem; }
	.item-macros { font-size: 0.78rem; color: var(--color-text-secondary); }
	.item-kcal { font-variant-numeric: tabular-nums; }
	.icon-btn { background: none; border: none; cursor: pointer; font-size: 1.1rem; color: var(--color-text-secondary); padding: 0 0.25rem; }
	.empty { text-align: center; display: flex; flex-direction: column; gap: var(--space-md); align-items: center; }
	.trend-bars { display: flex; align-items: flex-end; gap: var(--space-sm); height: 96px; }
	.trend-col { flex: 1; display: flex; flex-direction: column; align-items: center; height: 100%; justify-content: flex-end; gap: 4px; }
	.trend-bar { width: 60%; min-height: 2px; background: var(--color-accent, #D97A54); border-radius: var(--radius-sm); }
	.trend-day { font-size: 0.7rem; color: var(--color-text-secondary); }
	.section-hint { font-size: 0.85rem; color: var(--color-text-secondary); margin-top: var(--space-md); }
</style>
