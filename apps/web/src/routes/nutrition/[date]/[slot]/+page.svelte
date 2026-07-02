<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchFoodLogWithError, type FoodEntry } from '$lib/core/data';
	import { sumMacros, MEAL_SLOTS, type MealSlot } from '$lib/nutrition/nutrition_totals';
	import {
		entriesForSlotOnDay,
		slotCalorieTrend,
	} from '$lib/nutrition/meal_detail';
	import { formatDateShort } from '$lib/format/time';
	import ActivityLoader from '$lib/components/ActivityLoader.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let date = $derived($page.params.date as string);
	let slot = $derived($page.params.slot as MealSlot);
	let validSlot = $derived(MEAL_SLOTS.includes(slot));

	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let allEntries = $state<FoodEntry[]>([]);

	const slotEntries = $derived(entriesForSlotOnDay(allEntries, date, slot));
	const macros = $derived(sumMacros(slotEntries));
	// The same slot's calories over the trailing 7 days (this day inclusive).
	const trend = $derived(slotCalorieTrend(allEntries, date, slot));

	async function load() {
		loading = true;
		loadError = null;
		// fetchFoodLogWithError returns [] when there's no signed-in user, so the
		// fetch must wait for the session to hydrate — otherwise onMount races
		// auth readiness and the page renders an empty (0-kcal) slot. Mirrors the
		// daily /nutrition page's auth.ready() gate.
		await auth.ready();
		if (!auth.user) {
			allEntries = [];
			loading = false;
			return;
		}
		const start = new Date(`${date}T00:00:00`);
		const end = new Date(start);
		end.setDate(end.getDate() + 1);
		// Pull a 7-day window ending on this day so the day view + the trend
		// come from a single fetch.
		const windowStart = new Date(start);
		windowStart.setDate(windowStart.getDate() - 6);
		// Surface a real fetch failure as a retry banner — otherwise a 0-kcal slot
		// is indistinguishable from a genuinely empty meal.
		const res = await fetchFoodLogWithError(windowStart.toISOString(), end.toISOString());
		loadError = res.error;
		allEntries = res.entries;
		loading = false;
	}

	const maxTrend = $derived(Math.max(1, ...trend.map((t) => t.calories)));

	onMount(load);
</script>

<svelte:head>
	<title>{m('nutritionMeal.pageTitle')}</title>
</svelte:head>

<div class="page">
	<a href="/nutrition" class="back-link" onclick={(e) => { e.preventDefault(); goto('/nutrition'); }}>
		<span class="material-symbols">arrow_back</span>
		{m('nutritionMeal.back')}
	</a>

	{#if !validSlot}
		<p class="empty">{m('nutritionMeal.invalidSlot')}</p>
	{:else}
		<header class="page-header">
			<p class="kicker">{formatDateShort(`${date}T00:00:00`)}</p>
			<h1>{m(`nutrition.slot_${slot}`)}</h1>
		</header>

		{#if loading}
			<div class="act-load"><ActivityLoader kind="fuel" size={76} label={m('nutrition.loading')} /></div>
		{:else if loadError}
			<div class="load-error-banner" role="alert" data-testid="meal-load-error">
				<span class="material-symbols" aria-hidden="true">error</span>
				<div>
					<strong>{m('nutrition.loadFailed')}</strong>
					<span class="load-error-detail">{loadError}</span>
				</div>
				<button class="btn btn-outline" type="button" onclick={() => void load()}>{m('nutrition.retry')}</button>
			</div>
		{:else}
			<section class="card-elevated macro-card" data-testid="meal-macros">
				<div class="macro-total">
					<span class="macro-total-val">{macros.calories}</span>
					<span class="macro-total-unit">kcal</span>
				</div>
				<div class="macro-breakdown">
					<div class="macro-stat"><span class="macro-stat-val">{macros.proteinG}g</span><span class="macro-stat-label">{m('nutritionMeal.protein')}</span></div>
					<div class="macro-stat"><span class="macro-stat-val">{macros.carbsG}g</span><span class="macro-stat-label">{m('nutritionMeal.carbs')}</span></div>
					<div class="macro-stat"><span class="macro-stat-val">{macros.fatG}g</span><span class="macro-stat-label">{m('nutritionMeal.fat')}</span></div>
				</div>
			</section>

			<section class="card-elevated items-card">
				<h2>{m('nutritionMeal.itemsHeading')}</h2>
				{#if slotEntries.length === 0}
					<p class="empty">{m('nutritionMeal.noItems')}</p>
				{:else}
					<ul class="item-list">
						{#each slotEntries as e (e.id)}
							<li>
								<span class="item-name">{e.item_name}</span>
								<span class="item-kcal">{e.calories ?? 0} kcal</span>
							</li>
						{/each}
					</ul>
				{/if}
			</section>

			<section class="card-elevated trend-card">
				<h2>{m('nutritionMeal.trendHeading')}</h2>
				<div class="trend-bars" data-testid="meal-trend">
					{#each trend as t (t.date)}
						<div class="trend-col" class:trend-today={t.date === date}>
							<div class="trend-bar-wrap">
								<div class="trend-bar" style="height: {Math.round((t.calories / maxTrend) * 100)}%"></div>
							</div>
							<span class="trend-cal">{t.calories}</span>
							<span class="trend-day">{formatDateShort(`${t.date}T00:00:00`)}</span>
						</div>
					{/each}
				</div>
			</section>
		{/if}
	{/if}
</div>

<style>
	.act-load {
		display: flex;
		justify-content: center;
		padding: var(--space-2xl) 0;
	}
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		color: var(--color-text-secondary);
		text-decoration: none;
		margin-bottom: var(--space-lg);
	}
	.page-header {
		margin-bottom: var(--space-lg);
	}
	.kicker {
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		font-size: 0.8rem;
		margin: 0 0 0.2rem;
	}
	.page-header h1 {
		margin: 0;
	}
	.card-elevated {
		padding: var(--space-lg);
		margin-bottom: var(--space-lg);
	}
	.macro-card {
		display: flex;
		align-items: center;
		gap: var(--space-2xl);
	}
	.macro-total {
		display: flex;
		align-items: baseline;
		gap: 0.3rem;
	}
	.macro-total-val {
		font-size: 2rem;
		font-weight: 700;
	}
	.macro-total-unit {
		color: var(--color-text-secondary);
	}
	.macro-breakdown {
		display: flex;
		gap: var(--space-xl);
	}
	.macro-stat {
		display: flex;
		flex-direction: column;
	}
	.macro-stat-val {
		font-weight: 600;
	}
	.macro-stat-label {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.items-card h2,
	.trend-card h2 {
		margin: 0 0 var(--space-md);
		font-size: 1rem;
	}
	.item-list {
		list-style: none;
		margin: 0;
		padding: 0;
	}
	.item-list li {
		display: flex;
		justify-content: space-between;
		gap: var(--space-md);
		padding: 0.5rem 0;
		border-bottom: 1px solid var(--color-border);
	}
	.item-list li:last-child {
		border-bottom: none;
	}
	.item-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		min-width: 0;
	}
	.item-kcal {
		color: var(--color-text-secondary);
		flex-shrink: 0;
	}
	.trend-bars {
		display: flex;
		align-items: flex-end;
		gap: 0.5rem;
		height: 140px;
	}
	.trend-col {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.25rem;
		height: 100%;
	}
	.trend-bar-wrap {
		flex: 1;
		width: 100%;
		display: flex;
		align-items: flex-end;
		justify-content: center;
	}
	.trend-bar {
		width: 60%;
		min-height: 2px;
		background: var(--color-primary);
		border-radius: 3px 3px 0 0;
		opacity: 0.6;
	}
	.trend-today .trend-bar {
		opacity: 1;
	}
	.trend-cal {
		font-size: 0.7rem;
		color: var(--color-text-secondary);
	}
	.trend-day {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
	}
	.empty {
		color: var(--color-text-secondary);
	}
	.load-error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.load-error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.load-error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.load-error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.4rem;
	}
</style>
