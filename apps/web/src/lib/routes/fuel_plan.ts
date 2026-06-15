/**
 * Race fueling plan — a per-leg carbs/hr + fluid plan synced to the roadbook's
 * aid-station timeline. The deferred fueling half of the roadbook
 * (race_roadbook.md § Deferred / race_fueling_plan.md).
 *
 * `buildFuelPlan(legs, opts)` takes the roadbook's per-leg schedule and scales
 * a carbs + fluid target onto each leg by its **duration** (carbs/hr ×
 * leg-hours, fluid/hr × heat × leg-hours). On the start line and on each refill
 * checkpoint (one carrying water or food) it also emits `carryToNextAid` — the
 * fuel to carry out to reach the next refill (inclusive of the leg arriving
 * there), so a runner knows "carry 3 gels + 500 ml out of Aid 1". Optionally
 * estimates per-leg energy burn via `runCalories` when a bodyweight is supplied.
 *
 * Pure + framework-free. Twin of `apps/mobile_android/lib/fuel_plan.dart` —
 * keep the scaling, carry rules, edge cases, and test count in lockstep.
 */
import { runCalories } from '../nutrition/exercise_calories';

/** Conservative default intake rates (race_fueling_plan.md § Design). */
export const DEFAULT_CARBS_PER_HOUR_G = 60;
export const DEFAULT_FLUID_PER_HOUR_ML = 500;
/** Heat toggle multiplier on fluid (not carbs). */
export const HEAT_FLUID_FACTOR = 1.5;
/** Carbs per gel, for the `carryToNextAid` gel count. */
export const GEL_CARBS_G = 25;

/**
 * Minimal per-leg input. A roadbook `RoadbookLeg` structurally satisfies this,
 * so the web surface can pass `roadbook.legs` directly.
 */
export interface FuelLegInput {
	projectedElapsedS: number;
	legDistM: number;
	services: string[];
}

export interface FuelPlanOptions {
	carbsPerHourG: number;
	fluidPerHourMl: number;
	/** Multiplier on fluid for hot conditions. Default 1 (no bump). */
	heatFactor?: number;
	/** Carbs per gel for the carry-out gel count. Default `GEL_CARBS_G`. */
	gelCarbsG?: number;
	/** Bodyweight in kg; when set, each leg gets an estimated kcal burn. */
	weightKg?: number | null;
}

export interface FuelCarry {
	carbsG: number;
	fluidMl: number;
	gels: number;
}

export interface FuelLeg {
	carbsG: number;
	fluidMl: number;
	/** Estimated energy burn for the leg (0 when no bodyweight supplied). */
	kcal: number;
	/** Present on the start + each refill checkpoint — what to carry out. */
	carryToNextAid?: FuelCarry;
}

export interface FuelPlan {
	legs: FuelLeg[];
	totalCarbsG: number;
	totalFluidMl: number;
}

/** A leg is a refill point when its aid services carry water or food. */
function isRefill(leg: FuelLegInput): boolean {
	return leg.services.includes('water') || leg.services.includes('food');
}

/**
 * Build the fueling plan. The returned `legs` array is parallel to the input
 * (and to the roadbook's legs), so the surface can render fuel alongside each
 * checkpoint row.
 */
export function buildFuelPlan(legs: FuelLegInput[], opts: FuelPlanOptions): FuelPlan {
	const carbsPerHourG = Math.max(0, opts.carbsPerHourG);
	const fluidPerHourMl = Math.max(0, opts.fluidPerHourMl);
	const heatFactor = opts.heatFactor != null && opts.heatFactor > 0 ? opts.heatFactor : 1;
	const gelCarbsG = opts.gelCarbsG != null && opts.gelCarbsG > 0 ? opts.gelCarbsG : GEL_CARBS_G;
	const weightKg = opts.weightKg ?? null;

	const out: FuelLeg[] = [];
	let prevElapsed = 0;
	let totalCarbsG = 0;
	let totalFluidMl = 0;
	for (const leg of legs) {
		const durS = Math.max(0, leg.projectedElapsedS - prevElapsed);
		const h = durS / 3600;
		const carbsG = carbsPerHourG * h;
		const fluidMl = fluidPerHourMl * heatFactor * h;
		out.push({ carbsG, fluidMl, kcal: runCalories(leg.legDistM, weightKg) });
		totalCarbsG += carbsG;
		totalFluidMl += fluidMl;
		prevElapsed = leg.projectedElapsedS;
	}

	// Carry-out at the start (index 0) and at each refill checkpoint: sum the
	// fuel of every leg until the next refill, inclusive of the leg arriving
	// there (you consume it before you can refill).
	for (let i = 0; i < legs.length; i++) {
		if (i !== 0 && !isRefill(legs[i])) continue;
		let carbsG = 0;
		let fluidMl = 0;
		for (let j = i + 1; j < legs.length; j++) {
			carbsG += out[j].carbsG;
			fluidMl += out[j].fluidMl;
			if (isRefill(legs[j])) break;
		}
		out[i].carryToNextAid = {
			carbsG,
			fluidMl,
			gels: carbsG > 0 ? Math.ceil(carbsG / gelCarbsG) : 0
		};
	}

	return { legs: out, totalCarbsG, totalFluidMl };
}
