<script lang="ts">
	import { ringFraction } from '$lib/nutrition/nutrition_totals';
	import { computeDayBudget, type MacroKind } from '$lib/nutrition/nutrition_budget';
	import type { FoodMacros } from '$lib/nutrition/food_search';
	import type { NutritionTargets } from '$lib/nutrition/nutrition_targets';
	import { m } from '$lib/i18n/store.svelte';

	interface Props {
		consumed: FoodMacros;
		targets: NutritionTargets | null;
	}
	let { consumed, targets }: Props = $props();

	// Ring geometry — circumference of an r=18 circle (compact dashboard dial).
	const R = 18;
	const CIRC = 2 * Math.PI * R;

	type RingDef = {
		key: MacroKind;
		label: string;
		consumed: number;
		target: number | null;
		color: string;
	};
	const rings = $derived<RingDef[]>([
		{ key: 'calories', label: m('nutrition.calories'), consumed: consumed.calories, target: targets?.calories ?? null, color: 'var(--color-primary)' },
		{ key: 'protein', label: m('nutrition.protein'), consumed: consumed.proteinG, target: targets?.proteinG ?? null, color: 'var(--color-accent-cyan)' },
		{ key: 'carbs', label: m('nutrition.carbs'), consumed: consumed.carbsG, target: targets?.carbsG ?? null, color: 'var(--color-secondary)' },
		{ key: 'fat', label: m('nutrition.fat'), consumed: consumed.fatG, target: targets?.fatG ?? null, color: 'var(--color-warning)' },
	]);
	const dayBudget = $derived(computeDayBudget(consumed, targets));
	const calorieBudget = $derived(dayBudget?.calories ?? null);
</script>

<a class="card-elevated nutrition-rings-card" href="/nutrition" data-testid="dash-nutrition-rings">
	<div class="nutrition-rings-head">
		<div class="nutrition-rings-ident">
			<span class="material-symbols nutrition-rings-icon" aria-hidden="true">restaurant</span>
			<span class="today-label">{m('dash.todayNutritionLabel')}</span>
		</div>
		{#if calorieBudget}
			{#if calorieBudget.exceeded}
				<span class="budget-chip budget-over" data-testid="dash-nutrition-budget">{m('nutrition.over', { n: calorieBudget.over })}</span>
			{:else if calorieBudget.remaining === 0}
				<span class="budget-chip budget-on" data-testid="dash-nutrition-budget">{m('nutrition.onTarget')}</span>
			{:else}
				<span class="budget-chip budget-left" data-testid="dash-nutrition-budget">{m('nutrition.remaining', { n: calorieBudget.remaining ?? 0 })}</span>
			{/if}
		{/if}
		<span class="material-symbols nutrition-rings-arrow" aria-hidden="true">chevron_right</span>
	</div>
	<div class="nutrition-rings" class:untargeted={!targets}>
		{#each rings as r (r.key)}
			{@const frac = ringFraction(r.consumed, r.target)}
			{@const b = dayBudget ? dayBudget[r.key] : null}
			<div
				class="nutrition-ring"
				role="group"
				aria-label={`${r.label}: ${r.consumed}${r.target !== null ? ` / ${r.target}` : ''}`}
			>
				<div class="nutrition-ring-dial" style={`--ring-color: ${b?.exceeded ? 'var(--color-danger)' : r.color}`}>
					<svg viewBox="0 0 44 44" aria-hidden="true">
						<circle class="nutrition-ring-bg" cx="22" cy="22" r={R} stroke-width="5" fill="none" />
						{#if frac !== null}
							<circle
								class="nutrition-ring-fg"
								cx="22" cy="22" r={R} stroke-width="5" fill="none"
								stroke-dasharray={`${frac * CIRC} ${CIRC}`}
								transform="rotate(-90 22 22)"
							/>
						{/if}
					</svg>
					<span class="nutrition-ring-val" class:over={b?.exceeded}>{b?.exceeded ? `+${b.over}` : r.consumed}</span>
				</div>
				<span class="nutrition-ring-label">{r.label}</span>
			</div>
		{/each}
	</div>
</a>

<style>
	.nutrition-rings-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		/* Nutrition accent — kept distinct from the run/primary + gym accents
		   so the modality reads at a glance (label + glyph carry it, not
		   colour alone). */
		border-inline-start: 3px solid var(--color-warning);
		text-decoration: none;
		color: inherit;
		transition: background var(--transition-fast), box-shadow var(--transition-fast);
	}
	.nutrition-rings-card:hover {
		background: color-mix(in srgb, var(--color-warning) 7%, var(--color-surface));
		box-shadow: var(--shadow-sm);
	}
	.nutrition-rings-head {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.nutrition-rings-ident {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		flex: 1;
		min-width: 0;
	}
	.nutrition-rings-icon { font-size: 1.15rem; color: var(--color-warning); flex-shrink: 0; }
	.nutrition-rings-arrow { color: var(--color-text-tertiary); flex-shrink: 0; }

	.nutrition-rings {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-md);
		max-width: 26rem;
	}
	.nutrition-ring {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-2xs);
	}
	.nutrition-ring-dial { position: relative; width: 56px; height: 56px; }
	.nutrition-ring-dial svg { display: block; width: 100%; height: 100%; }
	.nutrition-ring-bg { stroke: color-mix(in srgb, var(--color-text-tertiary) 18%, transparent); }
	.nutrition-ring-fg {
		stroke: var(--ring-color, var(--color-primary));
		stroke-linecap: round;
		transition: stroke-dasharray 0.5s ease;
	}
	.nutrition-ring-val {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 0.78rem;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}
	.nutrition-ring-val.over { color: var(--color-danger); }
	.nutrition-ring-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}

	.budget-chip {
		font-size: 0.78rem;
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

	@media (max-width: 30rem) {
		.nutrition-rings { gap: var(--space-sm); }
		.nutrition-ring-dial { width: 48px; height: 48px; }
	}
</style>
