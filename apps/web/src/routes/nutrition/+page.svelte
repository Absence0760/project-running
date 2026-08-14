<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import {
		fetchFoodLogWithError,
		fetchLatestWeightKg,
		fetchRuns,
		fetchGymWorkouts,
		deleteFoodEntry,
		fetchMealTemplatesWithError,
		fetchMealTemplateDetail,
		createMealTemplate,
		deleteMealTemplate,
		logMealTemplate,
		fetchRecipesWithError,
		fetchRecipeDetail,
		createRecipe,
		deleteRecipe,
		logRecipe,
		type FoodEntry,
		type MealTemplateSummary,
		type RecipeSummary,
	} from '$lib/core/data';
	import { templateFromEntries } from '$lib/nutrition/meal_template';
	import { recipeFromEntries } from '$lib/nutrition/recipe';
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
	import { weeklyIntakeSummary, weeklyProteinSummary } from '$lib/nutrition/nutrition_week';
	import {
		DIARY_DATE_PARAM,
		diaryWindow,
		entryTimestampFor,
		isDiaryToday,
		isoDateOf,
		msUntilNextLocalMidnight,
		resolveDiaryDate,
		stepDiaryDate,
		trailingDates,
		waterDayKey,
	} from '$lib/nutrition/diary_day';
	import { formatDate } from '$lib/format/time';
	import type { FoodMacros } from '$lib/nutrition/food_search';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { deferDestructive } from '$lib/stores/undo.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import FoodLogEditor from '$lib/components/FoodLogEditor.svelte';

	// The diary day the page is showing — today unless `?date=` names an
	// earlier one. Held as state rather than derived so `load()` and every
	// write path read exactly the day the header shows.
	let viewDate = $state(isoDateOf(new Date()));
	let todayIso = $state(isoDateOf(new Date()));
	let yesterdayIso = $state(stepDiaryDate(isoDateOf(new Date()), -1, new Date()));
	let authReady = $state(false);
	// Deliberately plain `let`, not `$state`: the URL effect below writes them
	// and must not re-run on its own writes.
	let loadedDate: string | null = null;
	let loadGen = 0;

	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let showLog = $state(false);
	let entries = $state<FoodEntry[]>([]);
	let targets = $state<NutritionTargets | null>(null);
	let exerciseKcal = $state(0);
	let weekDays = $state<{ iso: string; label: string; calories: number; protein: number }[]>([]);
	let waterMl = $state(0);
	let weightKg = $state<number | null>(null);
	let exerciseMinutes = $state(0);

	let templates = $state<MealTemplateSummary[]>([]);
	let templatesError = $state(false);
	let showSaveMeal = $state(false);
	let mealName = $state('');
	let savingMeal = $state(false);
	let loggingTemplateId = $state<string | null>(null);
	let confirmDeleteTemplate = $state<MealTemplateSummary | null>(null);
	let deletingTemplate = $state(false);

	let recipes = $state<RecipeSummary[]>([]);
	let recipesError = $state(false);
	let showSaveRecipe = $state(false);
	let recipeName = $state('');
	let recipeServings = $state(1);
	let savingRecipe = $state(false);
	let loggingRecipeId = $state<string | null>(null);
	let confirmDeleteRecipe = $state<RecipeSummary | null>(null);
	let deletingRecipe = $state(false);

	const WATER_UNIT_ML = 250;

	/// Days of intake the trend chart covers, ending on the viewed day.
	const TREND_DAYS = 7;

	const consumed = $derived<FoodMacros>(sumMacros(entries));
	const groups = $derived<MealSlotGroup<FoodEntry>[]>(groupByMealSlot(entries));

	function waterStorageKey(): string {
		// User-scoped (issue #231): a shared browser profile's next account
		// must not inherit — or increment — the prior account's water count.
		// Day-scoped by the viewed day, so stepping back shows that day's count.
		return `water_ml_${auth.user?.id ?? 'anon'}_${waterDayKey(viewDate)}`;
	}

	function litres(ml: number): string {
		return (ml / 1000).toFixed(2).replace(/\.?0+$/, '');
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) {
			loading = false;
			return;
		}
		authReady = true;
	});

	// The URL owns which day is shown, so a back-filled day is linkable and the
	// browser's back button steps days. `?date=` is resolved fail-closed —
	// a malformed or future value lands on today rather than an empty day.
	$effect(() => {
		const requested = $page.url.searchParams.get(DIARY_DATE_PARAM);
		const now = new Date();
		todayIso = isoDateOf(now);
		yesterdayIso = stepDiaryDate(todayIso, -1, now);
		const next = resolveDiaryDate(requested, now);
		viewDate = next;
		if (!authReady || next === loadedDate) return;
		loadedDate = next;
		// The fetch is a side effect of the URL changing, not a dependency of it:
		// untracked so `load`'s own synchronous reads (`viewDate`, the auth store)
		// cannot re-arm the effect that just wrote them.
		untrack(() => void load());
	});

	// The effect above is the ONLY thing that recomputed the day, and it fires on
	// a URL or auth change — never on the clock. So a tab left open past local
	// midnight kept labelling the previous day "Today" and kept the Next-day step
	// disabled. Nothing was ever written to the wrong day (every write resolves
	// `entryTimestampFor(viewDate, new Date())` at save time), but the header lied.
	//
	// Two triggers, each costing one wakeup a day rather than the 1440 a polling
	// interval would: a single timeout armed for the next local midnight, which is
	// the only thing that reaches a tab that stays VISIBLE across it (a kitchen
	// screen, a second monitor); and a visibility check for the tab that was
	// backgrounded across it, where the browser throttled that timer or the
	// machine slept through it entirely.
	let rolloverTimer: ReturnType<typeof setTimeout> | null = null;

	function armRollover(now: Date) {
		if (rolloverTimer !== null) clearTimeout(rolloverTimer);
		rolloverTimer = setTimeout(syncDay, msUntilNextLocalMidnight(now));
	}

	function syncDay() {
		const now = new Date();
		const iso = isoDateOf(now);
		if (iso !== todayIso) {
			todayIso = iso;
			yesterdayIso = stepDiaryDate(iso, -1, now);
			// Re-resolved from the URL, not stepped from `viewDate`: a bare
			// `/nutrition` means "today" and must follow the clock onto the new day,
			// while an explicit past `?date=` stays exactly where it is and only
			// changes its label. Writing these does not re-arm the effect above —
			// it reads neither.
			const next = resolveDiaryDate($page.url.searchParams.get(DIARY_DATE_PARAM), now);
			if (next !== viewDate) {
				viewDate = next;
				loadedDate = next;
				void load();
			}
		}
		armRollover(now);
	}

	onMount(() => {
		const onVisibility = () => {
			if (document.visibilityState === 'visible') syncDay();
		};
		document.addEventListener('visibilitychange', onVisibility);
		armRollover(new Date());
		return () => {
			document.removeEventListener('visibilitychange', onVisibility);
			if (rolloverTimer !== null) clearTimeout(rolloverTimer);
		};
	});

	async function load() {
		if (!auth.user) return;
		const day = viewDate;
		const dayWindow = diaryWindow(day);
		const trendWindow = diaryWindow(day, TREND_DAYS);
		if (!dayWindow || !trendWindow) return;
		// Stepping days faster than the network answers leaves two loads in
		// flight; only the newest may write, or a slow response repaints the day
		// the user has already left.
		const gen = ++loadGen;
		const current = () => gen === loadGen;
		loading = true;
		loadError = null;
		try {
			// The food-log read is the primary surface: distinguish a real fetch
			// failure from a genuinely empty day so a transient error doesn't show
			// "nothing logged" and invite re-logging meals the user already has.
			const dayFood = await fetchFoodLogWithError(dayWindow.startIso, dayWindow.endIso);
			if (!current()) return;
			if (dayFood.error) {
				loadError = dayFood.error;
				loading = false;
				return;
			}
			entries = dayFood.entries;

			// Targets: assemble body metrics + activity/goal prefs, plus the
			// viewed day's runs + gym sessions for the "base + exercise" goal.
			const [settings, weight, profileRes, dayRuns, dayGym] = await Promise.all([
				loadSettings(auth.user.id),
				fetchLatestWeightKg(),
				supabase.rpc('get_my_profile'),
				fetchRuns({
					startedAtFrom: dayWindow.startIso,
					startedAtBefore: dayWindow.endIso,
				}),
				fetchGymWorkouts({
					startedAtFrom: dayWindow.startIso,
					startedAtBefore: dayWindow.endIso,
				}),
			]);
			if (!current()) return;
			weightKg = weight;
			exerciseKcal = exerciseCaloriesForDay({
				runs: dayRuns.map((r) => ({ distanceM: r.distance_m })),
				gymSessions: dayGym.map((w) => ({ durationS: w.duration_s })),
				weightKg: weight,
			});
			// Active minutes that day = run + gym duration, for the hydration
			// goal's sweat-replacement add (runs without a duration add nothing).
			const activeSeconds =
				dayRuns.reduce((s, r) => s + (r.duration_s ?? 0), 0) +
				dayGym.reduce((s, w) => s + (w.duration_s ?? 0), 0);
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

			// Trend: the seven days ending on the viewed day. Surface a fetch
			// failure the same way the day's-food path does — otherwise the
			// swallowed error leaves an empty trend chart indistinguishable from
			// a week with nothing logged.
			const week = await fetchFoodLogWithError(trendWindow.startIso, trendWindow.endIso);
			if (!current()) return;
			if (week.error) {
				loadError = week.error;
				loading = false;
				return;
			}
			const calByDay = new Map<string, number>();
			const proByDay = new Map<string, number>();
			for (const e of week.entries) {
				const key = isoDateOf(new Date(e.started_at));
				calByDay.set(key, (calByDay.get(key) ?? 0) + (e.calories ?? 0));
				proByDay.set(key, (proByDay.get(key) ?? 0) + (e.protein_g ?? 0));
			}
			weekDays = trailingDates(day, TREND_DAYS).map((iso) => ({
				iso,
				label: new Date(`${iso}T00:00:00`).toLocaleDateString(undefined, { weekday: 'short' }),
				calories: Math.round(calByDay.get(iso) ?? 0),
				protein: Math.round(proByDay.get(iso) ?? 0),
			}));

			const stored = localStorage.getItem(waterStorageKey());
			waterMl = stored ? Number(stored) || 0 : 0;

			await loadTemplates();
			await loadRecipes();
		} catch (e) {
			// A failed secondary load (week trend, water, targets) must not render
			// as an empty page indistinguishable from "nothing logged" — surface
			// the same load-error banner the primary day's-food path uses.
			console.warn('nutrition load failed', e);
			if (current()) loadError = (e as Error).message;
		}
		if (current()) loading = false;
	}

	async function loadTemplates() {
		const res = await fetchMealTemplatesWithError();
		templates = res.templates;
		templatesError = res.error !== null;
	}

	async function loadRecipes() {
		const res = await fetchRecipesWithError();
		recipes = res.recipes;
		recipesError = res.error !== null;
	}

	function onLogged() {
		showLog = false;
		void load();
	}

	/// Navigate the diary to `iso`. Today keeps the bare `/nutrition` URL so the
	/// canonical entry point never carries a redundant query string.
	function goToDay(iso: string): Promise<void> {
		const target = isDiaryToday(iso, new Date())
			? '/nutrition'
			: `/nutrition?${DIARY_DATE_PARAM}=${iso}`;
		return goto(target, { keepFocus: true, noScroll: true });
	}

	let prevDayBtn = $state<HTMLButtonElement | null>(null);

	async function stepForward() {
		const next = stepDiaryDate(viewDate, 1, new Date());
		// Landing on today disables the button that was just pressed, which would
		// drop focus to the document body. Hand it to its sibling instead.
		const willDisable = next === todayIso;
		await goToDay(next);
		if (willDisable) prevDayBtn?.focus();
	}

	/// Same reason as `stepForward`: the Today button unmounts on arrival.
	async function goToToday() {
		await goToDay(todayIso);
		prevDayBtn?.focus();
	}

	async function saveMeal() {
		if (savingMeal || entries.length === 0) return;
		savingMeal = true;
		try {
			const draft = templateFromEntries(mealName, entries);
			await createMealTemplate({
				name: draft.name,
				meal_slot: draft.mealSlot,
				items: draft.items.map((it) => ({
					position: it.position,
					item_name: it.itemName,
					meal_slot: it.mealSlot,
					calories: it.calories,
					protein_g: it.proteinG,
					carbs_g: it.carbsG,
					fat_g: it.fatG,
					external_id: it.externalId,
				})),
			});
			showToast(m('nutrition.templateSaved'), 'success');
			showSaveMeal = false;
			mealName = '';
			await loadTemplates();
		} catch (e) {
			showToast(m('nutrition.templateSaveFailed', { error: (e as Error).message }), 'error');
		} finally {
			savingMeal = false;
		}
	}

	async function logTemplate(t: MealTemplateSummary) {
		if (loggingTemplateId) return;
		loggingTemplateId = t.id;
		try {
			const detail = await fetchMealTemplateDetail(t.id);
			if (!detail) throw new Error('not found');
			const n = await logMealTemplate(detail, {
				startedAt: entryTimestampFor(viewDate, new Date()),
			});
			showToast(m('nutrition.templateLogged', { n, name: t.name }), 'success');
			await load();
		} catch (e) {
			showToast(m('nutrition.templateLogFailed', { error: (e as Error).message }), 'error');
		} finally {
			loggingTemplateId = null;
		}
	}

	async function removeTemplate() {
		const t = confirmDeleteTemplate;
		if (!t || deletingTemplate) return;
		deletingTemplate = true;
		try {
			await deleteMealTemplate(t.id);
			templates = templates.filter((x) => x.id !== t.id);
			confirmDeleteTemplate = null;
		} catch (e) {
			showToast(m('nutrition.deleteTemplateFailed', { error: (e as Error).message }), 'error');
		} finally {
			deletingTemplate = false;
		}
	}

	async function saveRecipe() {
		if (savingRecipe || entries.length === 0) return;
		savingRecipe = true;
		try {
			const draft = recipeFromEntries(recipeName, entries);
			await createRecipe({
				name: draft.name,
				servings: recipeServings >= 1 ? recipeServings : 1,
				meal_slot: draft.mealSlot,
				ingredients: draft.ingredients.map((it) => ({
					position: it.position,
					item_name: it.itemName,
					quantity: it.quantity,
					calories: it.calories,
					protein_g: it.proteinG,
					carbs_g: it.carbsG,
					fat_g: it.fatG,
					external_id: it.externalId,
				})),
			});
			showToast(m('nutrition.recipeSaved'), 'success');
			showSaveRecipe = false;
			recipeName = '';
			recipeServings = 1;
			await loadRecipes();
		} catch (e) {
			showToast(m('nutrition.recipeSaveFailed', { error: (e as Error).message }), 'error');
		} finally {
			savingRecipe = false;
		}
	}

	async function logRecipeEntry(r: RecipeSummary) {
		if (loggingRecipeId) return;
		loggingRecipeId = r.id;
		try {
			const detail = await fetchRecipeDetail(r.id);
			if (!detail) throw new Error('not found');
			const n = await logRecipe(detail, {
				startedAt: entryTimestampFor(viewDate, new Date()),
			});
			showToast(m('nutrition.recipeLogged', { n, name: r.name }), 'success');
			await load();
		} catch (e) {
			showToast(m('nutrition.recipeLogFailed', { error: (e as Error).message }), 'error');
		} finally {
			loggingRecipeId = null;
		}
	}

	async function removeRecipe() {
		const r = confirmDeleteRecipe;
		if (!r || deletingRecipe) return;
		deletingRecipe = true;
		try {
			await deleteRecipe(r.id);
			recipes = recipes.filter((x) => x.id !== r.id);
			confirmDeleteRecipe = null;
		} catch (e) {
			showToast(m('nutrition.deleteRecipeFailed', { error: (e as Error).message }), 'error');
		} finally {
			deletingRecipe = false;
		}
	}

	function addWater() {
		waterMl += WATER_UNIT_ML;
		localStorage.setItem(waterStorageKey(), String(waterMl));
	}
	function removeWater() {
		waterMl = Math.max(0, waterMl - WATER_UNIT_ML);
		localStorage.setItem(waterStorageKey(), String(waterMl));
	}

	// A logged entry is the app's most frequently deleted row and is
	// re-typed in seconds, so it takes the undo path rather than a modal:
	// the delete is deferred, not confirmed. The saved-meal and recipe
	// deletes below keep their confirms — those are authored, reusable
	// artefacts, deleted rarely.
	function removeEntry(entry: FoodEntry) {
		const before = entries;
		entries = entries.filter((e) => e.id !== entry.id);
		deferDestructive({
			message: m('nutrition.entryRemoved', { item: entry.item_name }),
			commit: () => deleteFoodEntry(entry.id),
			restore: () => {
				entries = before;
			},
			onCommitError: (e) =>
				showToast(
					m('nutrition.deleteFailed', { error: e instanceof Error ? e.message : String(e) }),
					'error',
				),
		});
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
	const proteinSummary = $derived(
		weeklyProteinSummary(weekDays.map((d) => d.protein), targets?.proteinG ?? null),
	);
	// The 7-day chart plots one metric at a time. Both series (calories +
	// protein) are already collected per day and each has its own logged-day
	// average (weekSummary / proteinSummary) and target, so the toggle only
	// re-selects which one the bars, value labels, avg line and goal line draw.
	let trendMetric = $state<'calories' | 'protein'>('calories');
	const trendSeries = $derived.by(() => {
		if (trendMetric === 'protein') {
			return {
				values: weekDays.map((d) => d.protein),
				avg: proteinSummary.avgProteinG,
				goal: targets?.proteinG ?? null,
				unit: 'g',
				avgLabel: m('nutrition.trendAvgProtein', { n: proteinSummary.avgProteinG }),
			};
		}
		return {
			values: weekDays.map((d) => d.calories),
			avg: weekSummary.avgCalories,
			goal: targets?.calories ?? null,
			unit: 'kcal',
			avgLabel: m('nutrition.trendAvgCalories', { n: weekSummary.avgCalories }),
		};
	});
	// Bars + the avg/goal reference lines share one scale; include the goal so
	// its line stays on-chart even when no logged day reaches it.
	const trendMax = $derived(
		Math.max(1, ...trendSeries.values, trendSeries.goal ?? 0),
	);

	const isViewingToday = $derived(viewDate === todayIso);
	const canGoForward = $derived(viewDate < todayIso);
	const dayLabel = $derived(
		isViewingToday
			? m('dash.today')
			: viewDate === yesterdayIso
				? m('nutrition.day.yesterday')
				: formatDate(viewDate),
	);
</script>

<svelte:head><title>{m('nutrition.heading')} — Threkir</title></svelte:head>

<div class="page">
	<header class="page-header">
		<h1>{m('nutrition.heading')}</h1>
		<div class="head-actions">
			<!-- Ungated on purpose: Targets is this surface's entry point to the
			     number every ring is measured against, so a user with none yet is
			     exactly who needs to reach it (multi_modal.md, §63 amendment). -->
			<a class="btn btn-secondary" href="/nutrition/targets" data-testid="nutrition-targets-link">
				<span class="material-symbols" aria-hidden="true">flag</span>
				{m('nutrition.targets.link')}
			</a>
			<button class="btn btn-primary" type="button" onclick={() => (showLog = true)} data-testid="log-food">{m('nutrition.logFood')}</button>
		</div>
	</header>

	<div class="day-bar">
		<nav class="day-nav" aria-label={m('nutrition.day.navLabel')}>
			<button
				bind:this={prevDayBtn}
				class="icon-btn day-step"
				type="button"
				onclick={() => void goToDay(stepDiaryDate(viewDate, -1, new Date()))}
				aria-label={m('nutrition.day.previous')}
				data-testid="diary-prev-day"
			>
				<span class="material-symbols" aria-hidden="true">chevron_left</span>
			</button>
			<span class="day-label" aria-live="polite" data-testid="diary-day">{dayLabel}</span>
			<button
				class="icon-btn day-step"
				type="button"
				disabled={!canGoForward}
				onclick={() => void stepForward()}
				aria-label={m('nutrition.day.next')}
				data-testid="diary-next-day"
			>
				<span class="material-symbols" aria-hidden="true">chevron_right</span>
			</button>
			{#if !isViewingToday}
				<button
					class="btn btn-outline btn-sm"
					type="button"
					onclick={() => void goToToday()}
					data-testid="diary-today"
				>{m('dash.today')}</button>
			{/if}
		</nav>
		{#if !isViewingToday}
			<p class="section-hint" data-testid="diary-backfill-hint">
				<span class="material-symbols hint-icon" aria-hidden="true">history</span>
				{m('nutrition.day.backfillHint')}
			</p>
		{/if}
	</div>

	{#if loading}
		<div class="skeleton-stack" aria-hidden="true">
			<div class="skel skel-rings"></div>
			<div class="skel skel-row"></div>
			<div class="skel skel-block"></div>
		</div>
	{:else if loadError}
		<div class="load-error-banner" role="alert" data-testid="nutrition-load-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('nutrition.loadFailed')}</strong>
				<span class="load-error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" type="button" onclick={() => void load()}>{m('nutrition.retry')}</button>
		</div>
	{:else}
		<section class="card-elevated rings-card" data-testid="macro-rings">
			{#if targets && calorieBudget}
				<div class="card-head">
					<span class="section-label">{dayLabel}</span>
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
					{m(isViewingToday ? 'nutrition.goalBreakdown' : 'nutrition.day.goalBreakdown', {
						base: targets.baseCalories,
						exercise: targets.exerciseKcal,
					})}
				</p>
			{/if}
			{#if !targets}
				<div class="no-targets" data-testid="no-targets">
					<p class="section-hint">
						<span class="material-symbols hint-icon" aria-hidden="true">info</span>
						{m('nutrition.noTargets')}
					</p>
					<a class="btn btn-secondary btn-sm" href="/settings/preferences#body-metrics" data-testid="add-body-metrics">
						<span class="material-symbols" aria-hidden="true">straighten</span>
						{m('nutrition.addBodyMetrics')}
					</a>
				</div>
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

		{#if templatesError}
			<section class="card-elevated templates-card" data-testid="templates-error">
				<div class="card-head">
					<span class="section-label">{m('nutrition.templates')}</span>
				</div>
				<p class="section-hint">
					<span class="material-symbols hint-icon" aria-hidden="true">error</span>
					{m('nutrition.templatesLoadFailed')}
					<button class="btn btn-outline btn-sm" type="button" onclick={() => void loadTemplates()}>{m('nutrition.templatesRetry')}</button>
				</p>
			</section>
		{:else if templates.length > 0}
			<section class="card-elevated templates-card" data-testid="meal-templates">
				<div class="card-head">
					<span class="section-label">{m('nutrition.templates')}</span>
				</div>
				<ul class="template-list">
					{#each templates as t (t.id)}
						<li class="template-row">
							<div class="template-main">
								<span class="template-name">{t.name}</span>
								<span class="template-meta">{m('nutrition.templateItems', { n: t.item_count })}</span>
							</div>
							<button
								class="btn btn-primary btn-sm"
								type="button"
								disabled={loggingTemplateId === t.id}
								onclick={() => void logTemplate(t)}
								data-testid="log-template"
							>{m('nutrition.logTemplate')}</button>
							<button
								class="icon-btn"
								type="button"
								onclick={() => (confirmDeleteTemplate = t)}
								aria-label={`${m('nutrition.deleteTemplate')} ${t.name}`}
							>
								<span class="material-symbols" aria-hidden="true">delete</span>
							</button>
						</li>
					{/each}
				</ul>
			</section>
		{/if}

		{#if recipesError}
			<section class="card-elevated templates-card" data-testid="recipes-error">
				<div class="card-head">
					<span class="section-label">{m('nutrition.recipes')}</span>
				</div>
				<p class="section-hint">
					<span class="material-symbols hint-icon" aria-hidden="true">error</span>
					{m('nutrition.recipesLoadFailed')}
					<button class="btn btn-outline btn-sm" type="button" onclick={() => void loadRecipes()}>{m('nutrition.templatesRetry')}</button>
				</p>
			</section>
		{:else if recipes.length > 0}
			<section class="card-elevated templates-card" data-testid="recipes">
				<div class="card-head">
					<span class="section-label">{m('nutrition.recipes')}</span>
				</div>
				<ul class="template-list">
					{#each recipes as r (r.id)}
						<li class="template-row">
							<div class="template-main">
								<span class="template-name">{r.name}</span>
								<span class="template-meta">{m('nutrition.recipeMeta', { n: r.ingredient_count, servings: r.servings })}</span>
							</div>
							<button
								class="btn btn-primary btn-sm"
								type="button"
								disabled={loggingRecipeId === r.id}
								onclick={() => void logRecipeEntry(r)}
								data-testid="log-recipe"
							>{m('nutrition.logRecipe')}</button>
							<button
								class="icon-btn"
								type="button"
								onclick={() => (confirmDeleteRecipe = r)}
								aria-label={`${m('nutrition.deleteRecipe')} ${r.name}`}
							>
								<span class="material-symbols" aria-hidden="true">delete</span>
							</button>
						</li>
					{/each}
				</ul>
			</section>
		{/if}

		{#if !hasMeals}
			<section class="card-elevated empty" data-testid="macro-rings-empty">
				<span class="material-symbols empty-icon" aria-hidden="true">restaurant</span>
				<h2>{isViewingToday ? m('nutrition.empty') : m('nutrition.day.emptyPast')}</h2>
				<p class="empty-text">{m('nutrition.searchPlaceholder')}</p>
				<button class="btn btn-primary" type="button" onclick={() => (showLog = true)}>{m('nutrition.logFood')}</button>
			</section>
		{:else}
			<section class="card-elevated meals-card">
				<div class="card-head">
					<span class="section-label">{dayLabel}</span>
					<div class="meals-head-right">
						<span class="card-meta">{consumed.calories} kcal</span>
						<button
							class="btn btn-outline btn-sm"
							type="button"
							onclick={() => {
								mealName = '';
								showSaveMeal = true;
							}}
							data-testid="save-as-meal"
						>{m('nutrition.saveAsMeal')}</button>
						<button
							class="btn btn-outline btn-sm"
							type="button"
							onclick={() => {
								recipeName = '';
								recipeServings = 1;
								showSaveRecipe = true;
							}}
							data-testid="save-as-recipe"
						>{m('nutrition.saveAsRecipe')}</button>
					</div>
				</div>
				<div class="meal-groups">
					{#each groups as g (g.slot)}
						<div class="meal-group">
							<a class="meal-head meal-head-link" href={`/nutrition/${viewDate}/${g.slot}`}>
								<h2>{m(`nutrition.slot_${g.slot}`)}</h2>
								<span class="meal-kcal">{g.calories} kcal<span class="material-symbols meal-chevron" aria-hidden="true">chevron_right</span></span>
							</a>
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
										<button class="icon-btn" type="button" onclick={() => removeEntry(e)} aria-label={`${m('nutrition.delete')} ${e.item_name}`}>
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
					<span class="section-label">{isViewingToday
						? m('nutrition.weeklyTrend')
						: m('nutrition.day.trendEnding', { date: formatDate(viewDate) })}</span>
					<div class="trend-meta">
						{#if trendSeries.avg > 0}<span class="card-meta">{trendSeries.avgLabel}</span>{/if}
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
						{#if proteinSummary.daysMetGoal !== null}
							<span
								class="week-delta week-protein"
								class:week-delta-on={proteinSummary.daysMetGoal === proteinSummary.loggedDays}
								data-testid="week-protein"
							>{m('nutrition.weekProtein', { met: proteinSummary.daysMetGoal, total: proteinSummary.loggedDays })}</span>
						{/if}
					</div>
				</div>
				<div class="trend-toggle" role="group" aria-label={m('nutrition.trendMetric')}>
					<button
						type="button"
						class="trend-toggle-btn"
						class:active={trendMetric === 'calories'}
						aria-pressed={trendMetric === 'calories'}
						onclick={() => (trendMetric = 'calories')}
						data-testid="trend-metric-calories"
					>{m('nutrition.calories')}</button>
					<button
						type="button"
						class="trend-toggle-btn"
						class:active={trendMetric === 'protein'}
						aria-pressed={trendMetric === 'protein'}
						onclick={() => (trendMetric = 'protein')}
						data-testid="trend-metric-protein"
					>{m('nutrition.protein')}</button>
				</div>
				<div class="trend-bars">
					<div class="trend-track">
						{#if trendSeries.avg > 0}
							<div
								class="trend-avg-line"
								style={`bottom: ${Math.round((trendSeries.avg / trendMax) * 100)}%`}
								aria-hidden="true"
							></div>
						{/if}
						{#if trendSeries.goal}
							<div
								class="trend-goal-line"
								style={`bottom: ${Math.round((trendSeries.goal / trendMax) * 100)}%`}
								title={`${m('nutrition.goalLine')}: ${trendSeries.goal} ${trendSeries.unit}`}
								aria-hidden="true"
							></div>
						{/if}
						{#each weekDays as d, i (d.iso)}
							{@const val = trendSeries.values[i] ?? 0}
							<div class="trend-col" class:trend-viewed={i === weekDays.length - 1}>
								<span class="trend-val">{val > 0 ? val : ''}</span>
								<div
									class="trend-bar"
									style={`height: ${Math.round((val / trendMax) * 100)}%`}
									title={`${d.label}: ${val} ${trendSeries.unit}`}
								></div>
							</div>
						{/each}
					</div>
					<div class="trend-days">
						{#each weekDays as d, i (d.iso)}
							<span class="trend-day" class:trend-viewed-day={i === weekDays.length - 1}>{d.label}</span>
						{/each}
					</div>
				</div>
			</section>
		{/if}
	{/if}
</div>

<Modal
	open={showLog}
	title={isViewingToday
		? m('nutrition.logHeading')
		: m('nutrition.day.logHeadingFor', { date: dayLabel })}
	narrow
	onclose={() => (showLog = false)}
>
	<FoodLogEditor oncreated={onLogged} diaryDate={viewDate} />
</Modal>

<Modal open={showSaveMeal} title={m('nutrition.saveAsMealTitle')} narrow onclose={() => (showSaveMeal = false)}>
	<form
		class="editor-form save-meal-form"
		onsubmit={(e) => {
			e.preventDefault();
			void saveMeal();
		}}
	>
		<label class="field">
			<span class="section-label">{m('nutrition.templateName')}</span>
			<input
				type="text"
				bind:value={mealName}
				placeholder={m('nutrition.templateNamePlaceholder')}
				data-testid="meal-name"
			/>
		</label>
		<div class="save-meal-actions">
			<button class="btn btn-outline" type="button" onclick={() => (showSaveMeal = false)}>{m('nutrition.cancel')}</button>
			<button class="btn btn-primary" type="submit" disabled={savingMeal || entries.length === 0} data-testid="confirm-save-meal">
				{m('nutrition.saveTemplate')}
			</button>
		</div>
	</form>
</Modal>

<ConfirmDialog
	open={confirmDeleteTemplate !== null}
	title={m('nutrition.deleteTemplateTitle')}
	message={m('nutrition.deleteTemplateMessage', { name: confirmDeleteTemplate?.name ?? '' })}
	confirmLabel={m('nutrition.deleteTemplate')}
	onconfirm={removeTemplate}
	oncancel={() => (confirmDeleteTemplate = null)}
	danger
/>

<Modal open={showSaveRecipe} title={m('nutrition.saveAsRecipeTitle')} narrow onclose={() => (showSaveRecipe = false)}>
	<form
		class="editor-form save-meal-form"
		onsubmit={(e) => {
			e.preventDefault();
			void saveRecipe();
		}}
	>
		<label class="field">
			<span class="section-label">{m('nutrition.recipeName')}</span>
			<input
				type="text"
				bind:value={recipeName}
				placeholder={m('nutrition.recipeNamePlaceholder')}
				data-testid="recipe-name"
			/>
		</label>
		<label class="field">
			<span class="section-label">{m('nutrition.recipeServings')}</span>
			<input
				type="number"
				min="1"
				step="0.5"
				bind:value={recipeServings}
				data-testid="recipe-servings"
			/>
		</label>
		<p class="section-hint">{m('nutrition.recipeServingsHint')}</p>
		<div class="save-meal-actions">
			<button class="btn btn-outline" type="button" onclick={() => (showSaveRecipe = false)}>{m('nutrition.cancel')}</button>
			<button class="btn btn-primary" type="submit" disabled={savingRecipe || entries.length === 0} data-testid="confirm-save-recipe">
				{m('nutrition.saveRecipe')}
			</button>
		</div>
	</form>
</Modal>

<ConfirmDialog
	open={confirmDeleteRecipe !== null}
	title={m('nutrition.deleteRecipeTitle')}
	message={m('nutrition.deleteRecipeMessage', { name: confirmDeleteRecipe?.name ?? '' })}
	confirmLabel={m('nutrition.deleteRecipe')}
	onconfirm={removeRecipe}
	oncancel={() => (confirmDeleteRecipe = null)}
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
		flex-wrap: wrap;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}
	.page-header h1 { margin: 0; }
	.head-actions {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
		justify-content: flex-end;
	}
	/* Cancels .page-header's bottom margin so the stepper reads as part of the
	   header rather than as a floating row above the first card. */
	.day-bar {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		margin-block-start: calc(var(--space-xl) * -1);
	}
	.day-nav {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		flex-wrap: wrap;
	}
	.day-step {
		width: 2.5rem;
		height: 2.5rem;
		color: var(--color-text-secondary);
	}
	/* .icon-btn's own hover is the danger tint the delete buttons want; a day
	   step is navigation, so it follows .btn-outline:hover onto primary. */
	.day-step:hover:not(:disabled) {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.day-step:disabled {
		opacity: 0.4;
		cursor: default;
	}
	.day-label {
		font-weight: 600;
		min-width: 9rem;
		text-align: center;
	}
	.no-targets {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}


	.card-head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-sm) var(--space-md);
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
		font-size: var(--font-size-section-label);
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
		color: var(--color-danger-text);
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
	.breakdown-icon { font-size: 1.05rem; color: var(--color-warning-text); flex-shrink: 0; }

	/* Water tracker — segmented pips give a glanceable fill level the bare
	   "N × 250 ml" string never conveyed. */
	.water-amount {
		font-size: 1.1rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	/* The +/- buttons hold a 2.5rem tap target, so this row wraps rather
	   than letting them shrink below it. */
	.water-controls {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
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

	.meals-head-right {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
	}

	/* Meal templates — a self-hiding section above the day's meals, mirroring
	   the gym Routines section above the workout list. */
	.template-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	.template-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-bg-secondary);
	}
	.template-row:last-child { border-bottom: none; }
	.template-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: var(--space-2xs); }
	.template-name {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.template-meta {
		color: var(--color-text-secondary);
		font-size: 0.8rem;
		font-variant-numeric: tabular-nums;
	}

	.save-meal-form { display: flex; flex-direction: column; gap: var(--space-lg); }
	.save-meal-actions { display: flex; justify-content: flex-end; gap: var(--space-sm); }

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
	.meal-head-link {
		text-decoration: none;
		color: inherit;
		cursor: pointer;
	}
	.meal-head-link:hover h2 {
		color: var(--color-primary);
	}
	.meal-kcal {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		font-variant-numeric: tabular-nums;
		display: inline-flex;
		align-items: center;
		gap: 0.1rem;
	}
	.meal-chevron {
		font-size: 1.1rem;
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
		font-size: var(--font-size-section-label);
		font-weight: 600;
		padding: 1px var(--space-sm);
		border-radius: var(--radius-sm);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.macro-p { color: var(--color-accent-cyan-text); background: color-mix(in srgb, var(--color-accent-cyan) 16%, transparent); }
	.macro-c { color: var(--color-secondary-text); background: color-mix(in srgb, var(--color-secondary) 16%, transparent); }
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
	.icon-btn:hover { background: var(--color-danger-light); color: var(--color-danger-text); }

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
		color: var(--color-danger-text);
		font-size: 1.4rem;
	}
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
	/* Metric switch — a compact segmented control so the same chart can plot
	   calories or protein without a second card. */
	.trend-toggle {
		display: inline-flex;
		gap: 2px;
		padding: 2px;
		margin-bottom: var(--space-md);
		background: color-mix(in srgb, var(--color-text-tertiary) 12%, transparent);
		border-radius: 9999px;
	}
	.trend-toggle-btn {
		appearance: none;
		border: none;
		background: none;
		cursor: pointer;
		padding: 0.25rem 0.85rem;
		border-radius: 9999px;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		transition: background var(--transition-fast), color var(--transition-fast);
	}
	.trend-toggle-btn:hover { color: var(--color-text); }
	.trend-toggle-btn.active {
		background: var(--color-surface);
		color: var(--color-primary);
		box-shadow: var(--shadow-sm);
	}
	.trend-toggle-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	/* Seven day-columns each need room for a 4-digit calorie label, which
	   is more than a 320px screen leaves. The bars and their day labels
	   scroll as ONE block so a column stays over its own label; a shared
	   min-width keeps them in register (WCAG 1.4.10). */
	.trend-bars { display: flex; flex-direction: column; gap: var(--space-xs); max-width: 100%; overflow-x: auto; }
	.trend-track,
	.trend-days { min-width: calc(7 * 1.75rem + 6 * var(--space-sm)); }
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
	.week-protein:not(.week-delta-on) {
		color: var(--color-text-secondary);
		background: color-mix(in srgb, var(--color-text) 8%, transparent);
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
		font-size: var(--font-size-section-label);
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
	.trend-viewed .trend-bar { background: var(--color-primary); }
	.trend-viewed .trend-val { color: var(--color-primary); font-weight: 700; }
	.trend-days { display: flex; gap: var(--space-sm); }
	.trend-day {
		flex: 1;
		text-align: center;
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	.trend-viewed-day { color: var(--color-text); font-weight: 700; }

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
		.rings { grid-template-columns: repeat(2, minmax(0, 1fr)); align-items: start; }
		.ring-hero { grid-column: 1 / -1; }
	}
</style>
