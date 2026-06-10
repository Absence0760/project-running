<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import {
		fetchFoodLog,
		fetchLatestWeightKg,
		fetchRuns,
		fetchGymWorkouts,
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
	import { exerciseCaloriesForDay } from '$lib/nutrition/exercise_calories';
	import {
		sumMacros,
		groupByMealSlot,
		ringFraction,
		type MealSlotGroup,
	} from '$lib/nutrition/nutrition_totals';
	import { computeDayBudget, type MacroKind } from '$lib/nutrition/nutrition_budget';
	import { hydrationTargetMl, hydrationBudget } from '$lib/nutrition/hydration';
	import { weeklyIntakeSummary } from '$lib/nutrition/nutrition_week';
	import type { FoodMacros } from '$lib/nutrition/food_search';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import FoodLogEditor from '$lib/components/FoodLogEditor.svelte';

	let loading = $state(true);
	let showLog = $state(false);
	let confirmDeleteEntry = $state<FoodEntry | null>(null);
	let deletingEntry = $state(false);
	let entries = $state<FoodEntry[]>([]);
	let targets = $state<NutritionTargets | null>(null);
	let exerciseKcal = $state(0);
	let weekDays = $state<{ label: string; calories: number }[]>([]);
	let waterMl = $state(0);
	let weightKg = $state<number | null>(null);
	let exerciseMinutes = $state(0);

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

	function litres(ml: number): string {
		return (ml / 1000).toFixed(2).replace(/\.?0+$/, '');
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

	async function load() {
		if (!auth.user) return;
		try {
			const now = new Date();
			const todayStart = dayStartIso(now);
			const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
			entries = await fetchFoodLog(todayStart, tomorrow.toISOString());

			// Targets: assemble body metrics + activity/goal prefs, plus today's
			// runs + gym sessions for the dynamic-TDEE "base + exercise" goal.
			const [settings, weight, profileRes, recentRuns, recentGym] = await Promise.all([
				loadSettings(auth.user.id),
				fetchLatestWeightKg(),
				supabase.rpc('get_my_profile'),
				fetchRuns({ limit: 50 }),
				fetchGymWorkouts(50),
			]);
			weightKg = weight;
			const tomorrowIso = tomorrow.toISOString();
			const isToday = (iso: string) => iso >= todayStart && iso < tomorrowIso;
			const todayRuns = recentRuns.filter((r) => isToday(r.started_at));
			const todayGym = recentGym.filter((w) => isToday(w.started_at));
			exerciseKcal = exerciseCaloriesForDay({
				runs: todayRuns.map((r) => ({ distanceM: r.distance_m })),
				gymSessions: todayGym.map((w) => ({ durationS: w.duration_s })),
				weightKg: weight,
			});
			// Active minutes today = run + gym duration, for the hydration goal's
			// sweat-replacement add (runs without a duration contribute nothing).
			const activeSeconds =
				todayRuns.reduce((s, r) => s + (r.duration_s ?? 0), 0) +
				todayGym.reduce((s, w) => s + (w.duration_s ?? 0), 0);
			exerciseMinutes = Math.round(activeSeconds / 60);
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
				exerciseKcal,
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

	async function removeEntry() {
		const entry = confirmDeleteEntry;
		if (!entry || deletingEntry) return;
		deletingEntry = true;
		try {
			await deleteFoodEntry(entry.id);
			entries = entries.filter((e) => e.id !== entry.id);
			confirmDeleteEntry = null;
		} catch (e) {
			showToast(m('nutrition.deleteFailed', { error: (e as Error).message }), 'error');
		} finally {
			deletingEntry = false;
		}
	}

	// Ring geometry — circumference of an r=26 circle.
	const R = 26;
	const CIRC = 2 * Math.PI * R;
	type RingDef = {
		key: MacroKind;
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
	const dayBudget = $derived(computeDayBudget(consumed, targets));
	// The arc clamps at full, so an over day is invisible without this.
	const calorieBudget = $derived(dayBudget?.calories ?? null);
	const waterTargetMl = $derived(hydrationTargetMl(weightKg, exerciseMinutes));
	const waterBudget = $derived(hydrationBudget(waterMl, waterTargetMl));
	const hasMeals = $derived(groups.length > 0);
	const hasAnyData = $derived(entries.length > 0 || weekDays.some((d) => d.calories > 0));
	const weekSummary = $derived(
		weeklyIntakeSummary(weekDays.map((d) => d.calories), targets?.calories ?? null),
	);
	const trendAvg = $derived(weekSummary.avgCalories);
	// Bars + the avg/goal reference lines share one scale; include the goal so
	// its line stays on-chart even when no logged day reaches it.
	const trendMax = $derived(
		Math.max(1, ...weekDays.map((d) => d.calories), targets?.calories ?? 0),
	);
</script>

<svelte:head><title>{m('nutrition.heading')} — Threkir</title></svelte:head>

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
			{#if targets && calorieBudget}
				<div class="card-head">
					<span class="section-label">{m('dash.today')}</span>
					<div class="budget-head">
						<span class="card-meta">{consumed.calories} / {targets.calories} kcal</span>
						{#if calorieBudget.exceeded}
							<span class="budget-chip budget-over" data-testid="calorie-budget">{m('nutrition.over', { n: calorieBudget.over })}</span>
						{:else if calorieBudget.remaining === 0}
							<span class="budget-chip budget-on" data-testid="calorie-budget">{m('nutrition.onTarget')}</span>
						{:else}
							<span class="budget-chip budget-left" data-testid="calorie-budget">{m('nutrition.remaining', { n: calorieBudget.remaining ?? 0 })}</span>
						{/if}
					</div>
				</div>
			{/if}
			<div class="rings" class:rings-untargeted={!targets}>
				{#each rings as r (r.key)}
					{@const frac = ringFraction(r.consumed, r.target)}
					{@const pct = frac !== null ? Math.round(frac * 100) : null}
					{@const b = dayBudget ? dayBudget[r.key] : null}
					<div
						class="ring"
						class:ring-hero={r.key === 'calories'}
						class:ring-over={b?.exceeded}
						class:ring-reached={b?.reached}
						role="group"
						aria-label={`${r.label}: ${r.consumed} ${r.unit}${r.target !== null ? ` of ${r.target} ${r.unit} target` : ''}`}
					>
						<div class="ring-dial" style={`--ring-color: ${b?.exceeded ? 'var(--color-danger)' : r.color}`}>
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
						{#if b?.exceeded}
							<span class="ring-pct ring-pct-over" aria-label={m('nutrition.macroOver', { n: b.over })}>+{b.over}</span>
						{:else if b?.reached}
							<span class="ring-pct ring-pct-reached" aria-label={m('nutrition.macroReached')}><span class="material-symbols" aria-hidden="true">check</span>{pct}%</span>
						{:else if pct !== null}
							<span class="ring-pct">{pct}%</span>
						{:else}
							<span class="ring-pct ring-pct-empty">{r.unit}</span>
						{/if}
					</div>
				{/each}
			</div>
			{#if targets && targets.exerciseKcal > 0}
				<p class="goal-breakdown" data-testid="goal-breakdown">
					<span class="material-symbols breakdown-icon" aria-hidden="true">local_fire_department</span>
					{m('nutrition.goalBreakdown', {
						base: targets.baseCalories,
						exercise: targets.exerciseKcal,
					})}
				</p>
			{/if}
			{#if !targets}
				<p class="section-hint" data-testid="no-targets">
					<span class="material-symbols hint-icon" aria-hidden="true">info</span>
					{m('nutrition.noTargets')}
				</p>
			{/if}
		</section>

		{@const drunkPips = Math.round(waterMl / WATER_UNIT_ML)}
		{@const pipCount = Math.max(8, Math.round(waterTargetMl / WATER_UNIT_ML), drunkPips)}
		<section class="card-elevated water-card">
			<div class="card-head">
				<span class="section-label">{m('nutrition.water')}</span>
				<div class="budget-head" aria-live="polite">
					<span class="water-amount">{litres(waterMl)} / {litres(waterTargetMl)} L</span>
					{#if waterBudget.reached}
						<span class="budget-chip budget-on" data-testid="water-budget">{m('nutrition.waterGoalReached')}</span>
					{:else}
						<span class="budget-chip budget-left" data-testid="water-budget">{m('nutrition.waterRemaining', { n: waterBudget.remainingMl })}</span>
					{/if}
				</div>
			</div>
			<div class="water-controls">
				<button class="btn btn-outline btn-sm water-btn" type="button" onclick={removeWater} aria-label={m('nutrition.waterRemove')}>−</button>
				<div class="water-pips" class:water-pips-reached={waterBudget.reached} aria-hidden="true">
					{#each Array(pipCount) as _, i (i)}
						<span class="water-pip" class:filled={i < drunkPips}></span>
					{/each}
				</div>
				<span class="water-units">{drunkPips} × 250 ml</span>
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
										<button class="icon-btn" type="button" onclick={() => (confirmDeleteEntry = e)} aria-label={`${m('nutrition.delete')} ${e.item_name}`}>
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
					<div class="trend-meta">
						{#if trendAvg > 0}<span class="card-meta">{trendAvg} kcal avg</span>{/if}
						{#if weekSummary.deltaPerDay !== null}
							{@const delta = weekSummary.deltaPerDay}
							{#if delta === 0}
								<span class="week-delta week-delta-on" data-testid="week-delta">{m('nutrition.weekOnGoal')}</span>
							{:else if delta < 0}
								<span class="week-delta week-delta-under" data-testid="week-delta">{m('nutrition.weekUnderGoal', { n: -delta })}</span>
							{:else}
								<span class="week-delta week-delta-over" data-testid="week-delta">{m('nutrition.weekOverGoal', { n: delta })}</span>
							{/if}
						{/if}
					</div>
				</div>
				<div class="trend-bars">
					<div class="trend-track">
						{#if trendAvg > 0}
							<div
								class="trend-avg-line"
								style={`bottom: ${Math.round((trendAvg / trendMax) * 100)}%`}
								aria-hidden="true"
							></div>
						{/if}
						{#if targets}
							<div
								class="trend-goal-line"
								style={`bottom: ${Math.round((targets.calories / trendMax) * 100)}%`}
								title={`${m('nutrition.goalLine')}: ${targets.calories} kcal`}
								aria-hidden="true"
							></div>
						{/if}
						{#each weekDays as d, i (d.label + i)}
							<div class="trend-col" class:trend-today={i === weekDays.length - 1}>
								<span class="trend-val">{d.calories > 0 ? d.calories : ''}</span>
								<div
									class="trend-bar"
									style={`height: ${Math.round((d.calories / trendMax) * 100)}%`}
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

<Modal open={showLog} title={m('nutrition.logHeading')} narrow onclose={() => (showLog = false)}>
	<FoodLogEditor oncreated={onLogged} />
</Modal>

<ConfirmDialog
	open={confirmDeleteEntry !== null}
	title={m('nutrition.deleteEntryTitle')}
	message={m('nutrition.deleteEntryMessage', { item: confirmDeleteEntry?.item_name ?? '' })}
	confirmLabel={m('nutrition.delete')}
	onconfirm={removeEntry}
	oncancel={() => (confirmDeleteEntry = null)}
	danger
/>

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
		/* Card fills the page width like its siblings, but the four
		   fixed-size dials stay grouped rather than drifting apart. */
		max-width: 40rem;
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
	/* Over a ceiling macro (calories / fat): the one ring state worth
	   flagging — the arc already recoloured to danger via --ring-color. */
	.ring-pct-over {
		color: var(--color-danger);
		font-weight: 700;
	}
	/* A goal macro (protein / carbs) cleared — a quiet win, never an alert. */
	.ring-pct-reached {
		display: inline-flex;
		align-items: center;
		gap: 1px;
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
		font-weight: 600;
	}
	.ring-pct-reached .material-symbols { font-size: 0.85rem; }

	/* Calorie-budget headline chip — "X left" / "X over" / "On target".
	   The single glanceable answer to "how much can I still eat today". */
	.budget-head {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		flex-wrap: wrap;
		justify-content: flex-end;
	}
	.budget-chip {
		font-size: 0.8rem;
		font-weight: 700;
		padding: 2px 9px;
		border-radius: 9999px;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.budget-left {
		color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
	}
	.budget-on {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
		background: color-mix(in srgb, var(--color-success) 16%, transparent);
	}
	.budget-over {
		color: color-mix(in srgb, var(--color-danger) 65%, var(--color-text));
		background: color-mix(in srgb, var(--color-danger) 14%, transparent);
	}

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

	/* Dynamic-TDEE breakdown — shown on a day with logged workouts so the
	   raised goal is legible ("base + exercise"), not a mystery jump. */
	.goal-breakdown {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		margin: var(--space-md) 0 0;
		padding-top: var(--space-md);
		border-top: 1px solid var(--color-border);
	}
	.breakdown-icon { font-size: 1.05rem; color: var(--color-warning); flex-shrink: 0; }

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
	.water-pips-reached .water-pip.filled { background: var(--color-success); }
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
	.macro-f { color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text)); background: color-mix(in srgb, var(--color-warning) 18%, transparent); }
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
		inset-inline: 0;
		border-top: 1px dashed var(--color-text-tertiary);
		opacity: 0.55;
		pointer-events: none;
	}
	/* The calorie goal — a coloured dashed line distinct from the subtle grey
	   avg line, so "where I am" vs "where I'm aiming" read apart at a glance. */
	.trend-goal-line {
		position: absolute;
		inset-inline: 0;
		border-top: 1.5px dashed var(--color-primary);
		opacity: 0.7;
		pointer-events: none;
	}
	.trend-meta {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		flex-wrap: wrap;
		justify-content: flex-end;
	}
	.week-delta {
		font-size: 0.78rem;
		font-weight: 700;
		padding: 2px 9px;
		border-radius: 9999px;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.week-delta-under {
		color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 14%, transparent);
	}
	.week-delta-on {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
		background: color-mix(in srgb, var(--color-success) 16%, transparent);
	}
	.week-delta-over {
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
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
