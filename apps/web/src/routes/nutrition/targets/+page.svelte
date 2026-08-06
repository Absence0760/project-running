<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { fetchLatestWeightKg, fetchRuns, fetchGymWorkouts } from '$lib/core/data';
	import { loadSettings, effective, updateUniversal } from '$lib/settings/settings';
	import {
		computeNutritionTargets,
		ageFromDob,
		mifflinStJeorBmr,
		ACTIVITY_LEVELS,
		GOAL_KCAL_DELTA,
		PROTEIN_G_PER_KG,
		FAT_KCAL_FRACTION,
		MIN_CALORIE_TARGET,
		type ActivityLevel,
		type WeightGoal,
		type NutritionTargets,
	} from '$lib/nutrition/nutrition_targets';
	import { exerciseCaloriesForDay } from '$lib/nutrition/exercise_calories';
	import { formatWeight } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let saveError = $state<string | null>(null);
	let targets = $state<NutritionTargets | null>(null);
	let weightKg = $state<number | null>(null);
	let heightCm = $state<number | null>(null);
	let ageYears = $state<number | null>(null);
	let sex = $state<string | null>(null);
	let exerciseKcal = $state(0);
	let activityLevel = $state<ActivityLevel>('moderate');
	let goal = $state<WeightGoal>('maintain');

	const activityFactor = $derived(
		ACTIVITY_LEVELS.find((a) => a.key === activityLevel)?.factor ?? 1.55,
	);
	const goalDelta = $derived(GOAL_KCAL_DELTA[goal] ?? 0);
	const bmrRaw = $derived(
		weightKg != null && heightCm != null && ageYears != null
			? mifflinStJeorBmr(weightKg, heightCm, ageYears, sex)
			: null,
	);
	const bmr = $derived(bmrRaw !== null ? Math.round(bmrRaw) : null);
	// The engine rounds the base to the nearest 10 and floors it at
	// MIN_CALORIE_TARGET, so a small/older user's shown terms would otherwise
	// visibly fail to add up to the base we print. Compared against the
	// unrounded BMR so this agrees with the engine at the boundary.
	const baseFloored = $derived(
		bmrRaw !== null && targets !== null && bmrRaw * activityFactor + goalDelta < MIN_CALORIE_TARGET,
	);

	async function load() {
		loading = true;
		loadError = null;
		try {
			const now = new Date();
			const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
			const tomorrow = new Date(todayStart.getTime() + 86_400_000);
			const [settings, weight, profileRes, recentRuns, recentGym] = await Promise.all([
				loadSettings(auth.user!.id),
				fetchLatestWeightKg(),
				supabase.rpc('get_my_profile'),
				fetchRuns({ limit: 50 }),
				fetchGymWorkouts(50),
			]);
			const startIso = todayStart.toISOString();
			const endIso = tomorrow.toISOString();
			const isToday = (iso: string) => iso >= startIso && iso < endIso;
			weightKg = weight;
			const prof = profileRes.data as
				| { height_cm: number | null; date_of_birth: string | null; gender: string | null }
				| null;
			heightCm = prof?.height_cm ?? null;
			ageYears = ageFromDob(prof?.date_of_birth, Date.now());
			sex = prof?.gender ?? null;
			activityLevel =
				effective<ActivityLevel>(settings, 'nutrition_activity_level', 'moderate') ?? 'moderate';
			goal = effective<WeightGoal>(settings, 'nutrition_goal', 'maintain') ?? 'maintain';
			exerciseKcal = exerciseCaloriesForDay({
				runs: recentRuns.filter((r) => isToday(r.started_at)).map((r) => ({ distanceM: r.distance_m })),
				gymSessions: recentGym
					.filter((w) => isToday(w.started_at))
					.map((w) => ({ durationS: w.duration_s })),
				weightKg: weight,
			});
			recompute();
		} catch (e) {
			loadError = (e as Error).message;
		}
		loading = false;
	}

	function recompute() {
		targets = computeNutritionTargets({
			weightKg,
			heightCm,
			ageYears,
			sex,
			activityLevel,
			goal,
			exerciseKcal,
		});
	}

	async function savePref(changes: Record<string, unknown>) {
		recompute();
		saveError = null;
		try {
			await updateUniversal(auth.user!.id, changes);
		} catch (e) {
			saveError = (e as Error).message;
		}
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) {
			loading = false;
			return;
		}
		await load();
	});
</script>

<svelte:head><title>{m('nutrition.targets.title')} — Threkir</title></svelte:head>

<div class="page">
	<a class="back" href="/nutrition">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>{m('nutrition.back')}
	</a>

	<header class="page-header">
		<h1>{m('nutrition.targets.title')}</h1>
		<p class="head-sub">{m('nutrition.targets.subtitle')}</p>
	</header>

	{#if loading}
		<div class="skeleton-stack" aria-hidden="true">
			<div class="skel skel-block"></div>
			<div class="skel skel-block"></div>
		</div>
		<p class="sr-only" role="status">{m('shell.loading')}</p>
	{:else if loadError}
		<div class="load-error-banner" role="alert" data-testid="targets-load-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('nutrition.loadFailed')}</strong>
				<span class="load-error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" type="button" onclick={() => void load()}>{m('nutrition.retry')}</button>
		</div>
	{:else}
		{#if targets}
			<section class="card-elevated goal-card" data-testid="targets-goal">
				<div class="card-head">
					<span class="section-label">{m('nutrition.targets.total')}</span>
					<span class="goal-total">{targets.calories} kcal</span>
				</div>
				<ul class="derivation">
					<li>
						<span class="term">{m('nutrition.targets.bmr')}</span>
						<span class="value">{bmr} kcal</span>
					</li>
					<li>
						<span class="term">{m('prefs.activityLevel')}</span>
						<span class="value">× {activityFactor}</span>
					</li>
					<li>
						<span class="term">{m('prefs.weightGoal')}</span>
						<span class="value">{goalDelta > 0 ? `+${goalDelta}` : goalDelta} kcal</span>
					</li>
					<li class="subtotal">
						<span class="term">{m('nutrition.targets.base')}</span>
						<span class="value">{targets.baseCalories} kcal</span>
					</li>
					{#if targets.exerciseKcal > 0}
						<li>
							<span class="term">
								{m('nutrition.targets.exercise')}
								<span class="term-hint">{m('nutrition.targets.exerciseHint')}</span>
							</span>
							<span class="value">+{targets.exerciseKcal} kcal</span>
						</li>
					{/if}
				</ul>
				{#if baseFloored}
					<p class="section-hint" data-testid="targets-floored">
						<span class="material-symbols hint-icon" aria-hidden="true">info</span>
						{m('nutrition.targets.baseFloored', { n: MIN_CALORIE_TARGET })}
					</p>
				{/if}
			</section>

			<section class="card-elevated macro-card" data-testid="targets-macros">
				<div class="card-head">
					<span class="section-label">{m('nutrition.targets.macrosHeading')}</span>
				</div>
				<ul class="macro-list">
					<li>
						<span class="term">
							{m('nutrition.protein')}
							<span class="term-hint">{m('nutrition.targets.proteinHint', { n: PROTEIN_G_PER_KG })}</span>
						</span>
						<span class="value">{targets.proteinG} g</span>
					</li>
					<li>
						<span class="term">
							{m('nutrition.carbs')}
							<span class="term-hint">{m('nutrition.targets.carbsHint')}</span>
						</span>
						<span class="value">{targets.carbsG} g</span>
					</li>
					<li>
						<span class="term">
							{m('nutrition.fat')}
							<span class="term-hint">
								{m('nutrition.targets.fatHint', { n: Math.round(FAT_KCAL_FRACTION * 100) })}
							</span>
						</span>
						<span class="value">{targets.fatG} g</span>
					</li>
				</ul>
			</section>
		{:else}
			<section class="card-elevated empty-card" data-testid="targets-empty">
				<span class="material-symbols empty-icon" aria-hidden="true">straighten</span>
				<h2>{m('nutrition.targets.emptyTitle')}</h2>
				<p>{m('nutrition.targets.emptyBody')}</p>
				<a class="btn btn-primary" href="/settings/preferences#body-metrics" data-testid="targets-empty-cta">
					{m('nutrition.addBodyMetrics')}
				</a>
			</section>
		{/if}

		<section class="card-elevated defaults-card">
			<div class="card-head">
				<span class="section-label">{m('nutrition.targets.defaultsHeading')}</span>
			</div>
			<div class="form-grid">
				<label>
					<span class="label-text">{m('prefs.activityLevel')}</span>
					<select
						bind:value={activityLevel}
						onchange={() => void savePref({ nutrition_activity_level: activityLevel })}
						data-testid="targets-activity-level"
					>
						{#each ACTIVITY_LEVELS as lvl (lvl.key)}
							<option value={lvl.key}>{m(`prefs.activity_${lvl.key}`)}</option>
						{/each}
					</select>
				</label>
				<label>
					<span class="label-text">{m('prefs.weightGoal')}</span>
					<select
						bind:value={goal}
						onchange={() => void savePref({ nutrition_goal: goal })}
						data-testid="targets-weight-goal"
					>
						<option value="lose">{m('prefs.goalLose')}</option>
						<option value="maintain">{m('prefs.goalMaintain')}</option>
						<option value="gain">{m('prefs.goalGain')}</option>
					</select>
				</label>
			</div>
			<p class="section-hint">{m('nutrition.targets.defaultsHint')}</p>
			{#if saveError}
				<p class="save-error" role="alert" data-testid="targets-save-error">
					<span class="material-symbols hint-icon" aria-hidden="true">error</span>
					{m('nutrition.targets.saveFailed')}
					<button class="btn btn-outline btn-sm" type="button" onclick={() => void savePref({ nutrition_activity_level: activityLevel, nutrition_goal: goal })}>
						{m('nutrition.retry')}
					</button>
				</p>
			{/if}
		</section>

		<section class="card-elevated metrics-card" data-testid="targets-metrics">
			<div class="card-head">
				<span class="section-label">{m('nutrition.targets.metricsHeading')}</span>
				<a class="btn btn-secondary btn-sm" href="/settings/preferences#body-metrics" data-testid="targets-edit-metrics">
					{m('nutrition.targets.editMetrics')}
				</a>
			</div>
			<ul class="metric-list">
				<li>
					<span class="term">{m('prefs.heightCm')}</span>
					<span class="value">{heightCm != null ? heightCm : m('nutrition.targets.unset')}</span>
				</li>
				<li>
					<span class="term">{m('prefs.weight')}</span>
					<span class="value">{weightKg != null ? formatWeight(weightKg) : m('nutrition.targets.unset')}</span>
				</li>
				<li>
					<span class="term">{m('nutrition.targets.age')}</span>
					<span class="value">
						{ageYears != null ? m('nutrition.targets.ageYears', { n: ageYears }) : m('nutrition.targets.unset')}
					</span>
				</li>
				<li>
					<span class="term">{m('prefs.gender')}</span>
					<span class="value">
						{#if sex === 'male'}{m('prefs.genderMale')}
						{:else if sex === 'female'}{m('prefs.genderFemale')}
						{:else}{m('prefs.genderPreferNotToSay')}{/if}
					</span>
				</li>
			</ul>
			<p class="section-hint">{m('nutrition.targets.metricsHint')}</p>
		</section>
	{/if}
</div>

<style>
	.page {
		max-width: 720px;
		margin: 0 auto;
		padding: var(--space-lg);
	}

	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		text-decoration: none;
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
	}

	.back:hover {
		color: var(--color-text);
	}

	.page-header {
		margin-bottom: var(--space-lg);
	}

	.page-header h1 {
		margin: 0;
		font-size: 1.6rem;
	}

	.head-sub {
		margin: 0.3rem 0 0;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
	}

	section {
		padding: var(--space-md);
		margin-bottom: var(--space-md);
	}

	.card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		flex-wrap: wrap;
		margin-bottom: var(--space-sm);
	}

	.section-label {
		font-size: 0.8rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-secondary);
	}

	.goal-total {
		font-size: 1.5rem;
		font-weight: 600;
		color: var(--color-primary);
	}

	.derivation,
	.macro-list,
	.metric-list {
		list-style: none;
		margin: 0;
		padding: 0;
	}

	.derivation li,
	.macro-list li,
	.metric-list li {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-sm);
		padding: 0.5rem 0;
		border-bottom: 1px solid var(--color-border);
	}

	.derivation li:last-child,
	.macro-list li:last-child,
	.metric-list li:last-child {
		border-bottom: none;
	}

	.derivation .subtotal {
		font-weight: 600;
	}

	.term {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
	}

	.term-hint {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}

	.value {
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.section-hint {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-wrap: wrap;
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.hint-icon {
		font-size: 1.1rem;
	}

	.save-error {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-wrap: wrap;
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
		color: var(--color-danger-text);
	}

	.form-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: var(--space-md);
	}

	.form-grid label {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}

	.label-text {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.empty-card {
		text-align: center;
	}

	.empty-card h2 {
		margin: var(--space-sm) 0 0.3rem;
		font-size: 1.1rem;
	}

	.empty-card p {
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}

	.empty-icon {
		font-size: 2rem;
		color: var(--color-text-secondary);
	}

	.load-error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
		padding: var(--space-md);
		border: 1px solid var(--color-danger);
		border-radius: var(--radius-md);
	}

	.load-error-detail {
		display: block;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.skeleton-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.skel {
		border-radius: var(--radius-lg);
		background: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 25%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 75%
		);
		background-size: 200% 100%;
		animation: shimmer 1.4s ease-in-out infinite;
	}

	.skel-block {
		height: 12rem;
	}

	@keyframes shimmer {
		0% {
			background-position: 200% 0;
		}
		100% {
			background-position: -200% 0;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.skel {
			animation: none;
		}
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
