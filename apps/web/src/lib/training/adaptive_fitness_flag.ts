/**
 * Fail-closed deploy gate for the plan-generator-v2 P2 fitness direction gate
 * (decisions §144, §150).
 *
 * P2 is the first phase where health-derived load (the CTL/ATL/TSB series
 * `training_load.ts` already computes for the dashboard) feeds a training
 * PRESCRIPTION. It collects nothing new — no column, no table, no sub-processor,
 * no extra hop — but the read still needs CISO / Security-Analyst sign-off
 * before it reaches real users, so `/plans/[id]` passes the fitness input to
 * `adaptiveReplanRemaining` only when `PUBLIC_ADAPTIVE_FITNESS_GATE` is
 * explicitly truthy. Unset / empty / "false" / "0" → off, and with it off the
 * engine sees no fitness at all and behaves exactly as shipped P1.
 *
 * Flipping the flag on for a prod build IS the sign-off-gated action; the code
 * path is complete and reviewable on `main` either way.
 */
import { env } from '$env/dynamic/public';
import { adaptiveFitnessGateEnabled } from './plan_adaptive_replan';

export function isAdaptiveFitnessGateEnabled(): boolean {
	return adaptiveFitnessGateEnabled(env.PUBLIC_ADAPTIVE_FITNESS_GATE);
}
