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
	import Modal from '$lib/components/Modal.svelte';
	import NutritionLogEditor from '$lib/components/NutritionLogEditor.svelte';

	let loading = $state(true);
	let entries = $state<FoodEntry[]>([]);
	let targets = $state<NutritionTargets | null>(null);
	let weekDays = $state<{ label: string; calories: number }[]>([]);
	let waterMl = $state(0);
	let showLog = $state(false);

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

	async function load() {
		const user = auth.user;
		if (!user) return;
		try {
			const now = new Date();
			const todayStart = dayStartIso(now);
			const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
			entries = await fetchFoodLog(todayStart, tomorrow.toISOString());

			// Targets: assemble body metrics + activity/goal prefs.
			const [settings, weightKg, profileRes] = await Promise.all([
				loadSettings(user.id),
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
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) {
			loading = false;
			return;
		}
		await load();
	});

	function onLogged() {
		showLog = false;
		void load();
	}

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
	type RingDef = {
		key: string;
		label: string;
		consumed: number;
		target: number | null;
		unit: string;
		color: string;
	};
	const rings = $derived<RingDef[]>([
		{ key: 'calories', label: m('nutrition.calories'), consumed: consumed.calories, target: targets?.calories ?? null, unit: 'kcal', color: 'var(--color-primary)' },
		{ key: 'protein', label: m('nutrition.protein'), consumed: consumed.proteinG, target: targets?.proteinG ?? null, unit: 'g', color: 'var(--color-accent-cyan)' },
		{ key: 'carbs', label: m('nutrition.carbs'), consumed: consumed.carbsG, target: targets?.carbsG ?? null, unit: 'g', color: 'var(--color-secondary)' },
		{ key: 'fat', label: m('nutrition.fat'), consumed: consumed.fatG, target: targets?.fatG ?? null, unit: 'g', color: 'var(--color-warning)' },
	]);
	const maxWeekCalories = $derived(Math.max(1, ...weekDays.map((d) => d.calories)));
	const hasMeals = $derived(groups.length > 0);
	const hasAnyData = $derived(entries.length > 0 || weekDays.some((d) => d.calories > 0));
	// Average daily intake across days that actually have a log — the trend
	// card's reference line. Excludes empty days so a half-logged week isn't
	// dragged toward zero.
	const trendAvg = $derived.by(() => {
		const logged = weekDays.filter((d) => d.calories > 0);
		if (logged.length === 0) return 0;
		return Math.round(logged.reduce((s, d) => s + d.calories, 0) / logged.length);
	});
</script>

<svelte:head><title>{m('nutrition.heading')}</title></svelte:head>

<div class="page">
	<header class="page-header">
		<h1>{m('nutrition.heading')}</h1>
		<button class="btn btn-primary" type="button" onclick={() => (showLog = true)} data-testid="log-food">{m('nutrition.logFood')}</button>
	</header>

	{#if loading}
		<div class="skeleton-stack" aria-hidden="true">
			<div class="skel skel-rings"></div>
			<div class="skel skel-row"></div>
			<div class="skel skel-block"></div>
		</div>
	{:else}
		<section class="card-elevated rings-card" data-testid="macro-rings">
			{#if targets}
				<div class="card-head">
					<span class="section-label">{m('dash.today')}</span>
					<span class="card-meta">{consumed.calories} / {targets.calories} kcal</span>
				</div>
			{/if}
			<div class="rings" class:rings-untargeted={!targets}>
				{#each rings as r (r.key)}
					{@const frac = ringFraction(r.consumed, r.target)}
					{@const pct = frac !== null ? Math.round(frac * 100) : null}
					<div
						class="ring"
						class:ring-hero={r.key === 'calories'}
						role="group"
						aria-label={`${r.label}: ${r.consumed} ${r.unit}${r.target !== null ? ` of ${r.target} ${r.unit} target` : ''}`}
					>
						<div class="ring-dial" style={`--ring-color: ${r.color}`}>
							<svg viewBox="0 0 64 64" aria-hidden="true">
								<circle class="ring-bg" cx="32" cy="32" r={R} stroke-width="7" fill="none" />
								{#if frac !== null}
									<circle
										class="ring-fg"
										cx="32" cy="32" r={R} stroke-width="7" fill="none"
										stroke-dasharray={`${frac * CIRC} ${CIRC}`}
										transform="rotate(-90 32 32)"
									/>
								{/if}
							</svg>
							<div class="ring-text">
								<span class="ring-val">{r.consumed}</span>
								{#if r.target !== null}<span class="ring-target">/ {r.target}</span>{/if}
							</div>
						</div>
						<span class="ring-label">{r.label}</span>
						{#if pct !== null}<span class="ring-pct">{pct}%</span>{:else}<span class="ring-pct ring-pct-empty">{r.unit}</span>{/if}
					</div>
				{/each}
			</div>
			{#if !targets}
				<p class="section-hint" data-testid="no-targets">
					<span class="material-symbols hint-icon" aria-hidden="true">info</span>
					{m('nutrition.noTargets')}
				</p>
			{/if}
		</section>

		<section class="card-elevated water-card">
			<div class="card-head">
				<span class="section-label">{m('nutrition.water')}</span>
				<span class="water-amount">{(waterMl / 1000).toFixed(2).replace(/\.?0+$/, '')} L</span>
			</div>
			<div class="water-controls">
				<button class="btn btn-outline btn-sm water-btn" type="button" onclick={removeWater} aria-label={m('nutrition.waterRemove')}>−</button>
				<div class="water-pips" aria-hidden="true">
					{#each Array(Math.max(8, Math.round(waterMl / WATER_UNIT_ML))) as _, i (i)}
						<span class="water-pip" class:filled={i < Math.round(waterMl / WATER_UNIT_ML)}></span>
					{/each}
				</div>
				<span class="water-units">{Math.round(waterMl / WATER_UNIT_ML)} × 250 ml</span>
				<button class="btn btn-primary btn-sm water-btn" type="button" onclick={addWater} data-testid="add-water" aria-label={m('nutrition.waterAdd')}>＋</button>
			</div>
		</section>

		{#if !hasMeals}
			<section class="card-elevated empty" data-testid="macro-rings-empty">
				<span class="material-symbols empty-icon" aria-hidden="true">restaurant</span>
				<h2>{m('nutrition.empty')}</h2>
				<p class="empty-text">{m('nutrition.searchPlaceholder')}</p>
				<button class="btn btn-primary" type="button" onclick={() => (showLog = true)}>{m('nutrition.logFood')}</button>
			</section>
		{:else}
			<section class="card-elevated meals-card">
				<div class="card-head">
					<span class="section-label">{m('dash.today')}</span>
					<span class="card-meta">{consumed.calories} kcal</span>
				</div>
				<div class="meal-groups">
					{#each groups as g (g.slot)}
						<div class="meal-group">
							<div class="meal-head">
								<h2>{m(`nutrition.slot_${g.slot}`)}</h2>
								<span class="meal-kcal">{g.calories} kcal</span>
							</div>
							<ul class="meal-list">
								{#each g.entries as e (e.id)}
									<li>
										<div class="item-main">
											<span class="item-name">{e.item_name}</span>
											{#if e.protein_g || e.carbs_g || e.fat_g}
												<span class="item-macros">
													{#if e.protein_g}<span class="macro-chip macro-p">{e.protein_g}g P</span>{/if}{#if e.carbs_g}<span class="macro-chip macro-c">{e.carbs_g}g C</span>{/if}{#if e.fat_g}<span class="macro-chip macro-f">{e.fat_g}g F</span>{/if}
												</span>
											{/if}
										</div>
										<span class="item-kcal-wrap"><span class="item-kcal">{e.calories ?? 0}</span><span class="item-kcal-unit">kcal</span></span>
										<button class="icon-btn" type="button" onclick={() => removeEntry(e.id)} aria-label={`${m('nutrition.delete')} ${e.item_name}`}>
											<span class="material-symbols" aria-hidden="true">close</span>
										</button>
									</li>
								{/each}
							</ul>
						</div>
					{/each}
				</div>
			</section>
		{/if}

		{#if hasAnyData}
			<section class="card-elevated trend-card">
				<div class="card-head">
					<span class="section-label">{m('nutrition.weeklyTrend')}</span>
					{#if trendAvg > 0}<span class="card-meta">{trendAvg} kcal avg</span>{/if}
				</div>
	<div class="trend-bars">
					<div class="trend-track">
						{#if trendAvg > 0}
							<div
								class="trend-avg-line"
								style={`bottom: ${Math.round((trendAvg / maxWeekCalories) * 100)}%`}
								aria-hidden="true"
							></div>
						{/if}
						{#each weekDays as d, i (d.label + i)}
							<div class="trend-col" class:trend-today={i === weekDays.length - 1}>
								<span class="trend-val">{d.calories > 0 ? d.calories : ''}</span>
								<div
									class="trend-bar"
									style={`height: ${Math.round((d.calories / maxWeekCalories) * 100)}%`}
									title={`${d.label}: ${d.calories} kcal`}
								></div>
							</div>
						{/each}
					</div>
					<div class="trend-days">
						{#each weekDays as d, i (d.label + i)}
							<span class="trend-day" class:trend-today-day={i === weekDays.length - 1}>{d.label}</span>
						{/each}
					</div>
				</div>
			</section>
		{/if}
	{/if}
</div>

<Modal open={showLog} title={m('nutrition.logHeading')} onclose={() => (showLog = false)}>
	<NutritionLogEditor oncreated={onLogged} oncancel={() => (showLog = false)} />
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}
	.page-header h1 { margin: 0; }


	.card-head {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.card-meta {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}

	/* Macro rings — Calories is the hero (larger dial), the three macros
	   are secondary. Each ring colours its progress arc independently so
	   the four read as distinct metrics at a glance. */
	.rings {
		display: grid;
		grid-template-columns: 1.4fr repeat(3, 1fr);
		gap: var(--space-md);
		align-items: end;
	}
	.rings-untargeted { align-items: start; }
	.ring {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2xs);
	}
	.ring-dial {
		position: relative;
		width: 88px;
		height: 88px;
	}
	.ring-hero .ring-dial { width: 116px; height: 116px; }
	.ring-dial svg { display: block; width: 100%; height: 100%; }
	.ring-bg { stroke: color-mix(in srgb, var(--color-text-tertiary) 18%, transparent); }
	.ring-fg {
		stroke: var(--ring-color, var(--color-primary));
		stroke-linecap: round;
		transition: stroke-dasharray 0.5s ease;
	}
	.ring-text {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		line-height: 1.1;
	}
	.ring-val {
		font-weight: 700;
		font-size: 0.95rem;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.ring-hero .ring-val { font-size: 1.45rem; }
	.ring-target {
		font-size: 0.68rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.ring-hero .ring-target { font-size: 0.78rem; }
	.ring-label {
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.ring-pct {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.ring-pct-empty { text-transform: lowercase; }

	.section-hint {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: var(--space-md) 0 0;
		padding-top: var(--space-md);
		border-top: 1px solid var(--color-border);
	}
	.hint-icon { font-size: 1.1rem; color: var(--color-primary); flex-shrink: 0; }

	/* Water tracker — segmented pips give a glanceable fill level the bare
	   "N × 250 ml" string never conveyed. */
	.water-amount {
		font-size: 1.1rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.water-controls {
		display: flex;
		align-items: center;
		gap: var(--space-md);
	}
	.water-btn {
		min-width: 2.5rem;
		min-height: 2.5rem;
		font-size: 1.1rem;
		line-height: 1;
	}
	.water-pips {
		flex: 1;
		display: flex;
		gap: var(--space-xs);
		min-width: 0;
		flex-wrap: wrap;
	}
	.water-pip {
		flex: 1;
		min-width: var(--space-sm);
		height: 0.6rem;
		border-radius: 9999px;
		background: color-mix(in srgb, var(--color-text-tertiary) 22%, transparent);
		transition: background var(--transition-fast);
	}
	.water-pip.filled { background: var(--color-accent-cyan); }
	.water-units {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		white-space: nowrap;
		font-variant-numeric: tabular-nums;
	}

	/* Meals — one card with per-slot subsections so the day reads as a
	   single block rather than four floating fragments. */
	.meal-groups {
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.meal-head {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-md);
		padding-bottom: var(--space-2xs);
		border-bottom: 1px solid var(--color-border);
	}
	.meal-head h2 {
		margin: 0;
		font-size: 0.95rem;
		font-weight: 700;
	}
	.meal-kcal {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		font-variant-numeric: tabular-nums;
	}
	.meal-list {
		list-style: none;
		margin: var(--space-sm) 0 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	.meal-list li {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
	}
	.meal-list li:last-child { border-bottom: none; }
	.item-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: var(--space-2xs); }
	.item-name { font-size: 0.95rem; color: var(--color-text); }
	.item-macros { display: flex; flex-wrap: wrap; gap: var(--space-xs); }
	.macro-chip {
		font-size: 0.7rem;
		font-weight: 600;
		padding: 1px var(--space-sm);
		border-radius: var(--radius-sm);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.macro-p { color: var(--color-accent-cyan); background: color-mix(in srgb, var(--color-accent-cyan) 16%, transparent); }
	.macro-c { color: var(--color-secondary); background: color-mix(in srgb, var(--color-secondary) 16%, transparent); }
	.macro-f { color: var(--color-warning-strong, var(--color-warning)); background: color-mix(in srgb, var(--color-warning) 18%, transparent); }
	.item-kcal-wrap {
		display: inline-flex;
		align-items: baseline;
		gap: var(--space-2xs);
		white-space: nowrap;
	}
	.item-kcal {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
		color: var(--color-text);
	}
	.item-kcal-unit { font-weight: 500; font-size: 0.8rem; color: var(--color-text-tertiary); }
	.icon-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2rem;
		height: 2rem;
		flex-shrink: 0;
		background: none;
		border: none;
		border-radius: var(--radius-sm);
		cursor: pointer;
		color: var(--color-text-tertiary);
		transition: background var(--transition-fast), color var(--transition-fast);
	}
	.icon-btn .material-symbols { font-size: 1.15rem; }
	.icon-btn:hover { background: var(--color-danger-light); color: var(--color-danger); }

	.empty {
		text-align: center;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		align-items: center;
		padding: var(--space-2xl) var(--space-lg);
	}
	.empty h2 { margin: 0; font-size: 1.05rem; }
	.empty .btn { margin-top: var(--space-sm); }
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.7;
	}

	/* 7-day trend — value labels + a dashed average reference line, today
	   highlighted in the primary colour. The bar track is its own box so
	   the avg line positions against the bar area, not the day labels. */
	.trend-bars { display: flex; flex-direction: column; gap: var(--space-xs); }
	.trend-track {
		display: flex;
		align-items: flex-end;
		gap: var(--space-sm);
		height: 9rem;
		position: relative;
	}
	.trend-avg-line {
		position: absolute;
		left: 0;
		right: 0;
		border-top: 1px dashed var(--color-text-tertiary);
		opacity: 0.55;
		pointer-events: none;
	}
	.trend-col {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		height: 100%;
		justify-content: flex-end;
		gap: var(--space-2xs);
	}
	.trend-val {
		font-size: 0.65rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
		min-height: 0.9rem;
	}
	.trend-bar {
		width: 70%;
		min-height: 3px;
		/* A flat tint of the primary so past-day bars read on the card
		   surface in both themes (bg-tertiary == surface in dark, so it
		   would vanish). */
		background: color-mix(in srgb, var(--color-primary) 30%, var(--color-surface));
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
		transition: height 0.4s ease;
	}
	.trend-today .trend-bar { background: var(--color-primary); }
	.trend-today .trend-val { color: var(--color-primary); font-weight: 700; }
	.trend-days { display: flex; gap: var(--space-sm); }
	.trend-day {
		flex: 1;
		text-align: center;
		font-size: 0.7rem;
		color: var(--color-text-secondary);
	}
	.trend-today-day { color: var(--color-text); font-weight: 700; }

	/* Loading skeleton — matches card heights so data arrival doesn't jump. */
	.skeleton-stack { display: flex; flex-direction: column; gap: var(--space-lg); }
	.skel {
		border-radius: var(--radius-lg);
		background: linear-gradient(90deg, var(--color-bg-tertiary) 25%, var(--color-bg-secondary) 50%, var(--color-bg-tertiary) 75%);
		background-size: 200% 100%;
		animation: shimmer 1.4s ease-in-out infinite;
	}
	.skel-rings { height: 12rem; }
	.skel-row { height: 5.5rem; }
	.skel-block { height: 16rem; }
	@keyframes shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	@media (max-width: 36rem) {
		.rings { grid-template-columns: repeat(2, 1fr); align-items: start; }
		.ring-hero { grid-column: 1 / -1; }
	}
</style>
