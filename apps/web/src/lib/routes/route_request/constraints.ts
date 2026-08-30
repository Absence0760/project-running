// Pure validation + clamping for the AI route-request constraint object.
//
// The LLM never routes — it only extracts intent into a structured
// constraints object, which the deterministic generator then consumes.
// The model's numbers are NEVER trusted: every field is clamped /
// whitelisted here, server-side, before it can cross into the generator
// (graph search owns correctness). A hallucinated or malicious value is
// dropped to a safe default, not executed.
//
// Kept free of the Anthropic SDK and the `$env` graph so the clamp logic
// is unit-testable in isolation (constraints.test.ts).

import {
	MAX_TARGET_DISTANCE_M,
	isValidTargetDistance,
} from '../route_loop';
import { ROUTE_PREFERENCES, type RoutePreference } from '../generate/graphhopper';

/// Lower bound for an extracted distance. The generator's own guard
/// (`isValidTargetDistance`) only rejects non-positive / NaN / absurd-large;
/// a 5 m "loop" is technically valid there but useless and almost certainly a
/// unit-confusion (the model read "5" as metres, not km). Floor at 500 m so a
/// degenerate extraction still yields a runnable short loop.
export const MIN_REQUEST_DISTANCE_M = 500;

/// Practical ceiling for an NL-requested route, well below the generator's
/// absolute `MAX_TARGET_DISTANCE_M` (1,000 km). The slider tops out at a
/// marathon (~42 km); a request for "500 km" is far more likely a parse error
/// than a real ask, so clamp to a sane upper bound the generator can actually
/// serve. 100 km comfortably covers ultras while rejecting unit-confusion.
export const MAX_REQUEST_DISTANCE_M = 100_000;

/// Fallback when the model omits a distance entirely (or emits an
/// unusable one). 5 km is the most common request and matches the
/// builder slider's default.
export const DEFAULT_REQUEST_DISTANCE_M = 5_000;

export type RouteShape = 'loop' | 'out_and_back' | 'point_to_point';
export type RouteRequestSurface = 'road' | 'trail' | 'mixed';

/// The validated constraint object handed back to the client. Every
/// field is already clamped / whitelisted — the UI maps it straight onto
/// the generator form. `assumptions` lists the fields we filled from a
/// default (rather than from the request) so the UI can surface "5 km
/// loop, avoiding main roads — adjust before generating".
export interface RouteConstraints {
	distanceM: number;
	shape: RouteShape;
	surface: RouteRequestSurface;
	avoidHighways: boolean;
	/// Road-design preference for the generator's custom model. Null is a real
	/// answer — "no preference" — not a missing one: every other field has a
	/// default the runner would have picked anyway, whereas defaulting this one
	/// would silently bias every generated route toward a design nobody asked for.
	preference: RoutePreference | null;
	assumptions: string[];
}

const SHAPES: ReadonlySet<string> = new Set(['loop', 'out_and_back', 'point_to_point']);
const SURFACES: ReadonlySet<string> = new Set(['road', 'trail', 'mixed']);
/// The vocabulary is owned by the generator, not by this module, so the set is
/// derived from it rather than transcribed: a hand-copied list only fails the
/// build when a value is REMOVED, and silently drops a newly added one — the
/// model would be told about a preference the generator accepts and this
/// boundary would then discard it.
const PREFERENCES: ReadonlySet<string> = new Set(ROUTE_PREFERENCES);

/// Fill a preference the request did not name from what it did name.
/// `avoid_highways` is the same ask `'quiet'` implements in the custom model,
/// and a trail request is asking for the green half of `'scenic'`; the explicit
/// negative constraint wins over the weaker surface inference when both hold.
/// `'cul_de_sac'` is never derived — it inverts part of the loop score and is an
/// explicit opt-in by design (graph_cycle_loop_generation.md § Extension), so
/// inferring it would hand a runner dead-end spurs they never asked for.
function derivePreference(
	avoidHighways: boolean | null,
	surface: RouteRequestSurface | null,
): RoutePreference | null {
	if (avoidHighways === true) return 'quiet';
	if (surface === 'trail') return 'scenic';
	return null;
}

/// Clamp an untrusted distance (in metres) to the request-sane band.
/// Returns null when the value can't be coerced to a finite number at all,
/// so the caller can record it as an assumption and fall back to the
/// default. A finite-but-out-of-band value is clamped, not rejected — the
/// model's intent (long / short) is preserved while staying serveable.
export function clampDistance(raw: unknown): number | null {
	const n = Number(raw);
	if (!Number.isFinite(n) || n <= 0) return null;
	const clamped = Math.min(MAX_REQUEST_DISTANCE_M, Math.max(MIN_REQUEST_DISTANCE_M, n));
	// Belt-and-braces: the generator must accept whatever we emit.
	// MIN/MAX above already sit inside (0, MAX_TARGET_DISTANCE_M], so this
	// only fails on a logic error in the bounds — fall back to default.
	if (!isValidTargetDistance(clamped) || clamped > MAX_TARGET_DISTANCE_M) return null;
	return Math.round(clamped);
}

/// Validate + clamp the model's raw tool-call output into a trustworthy
/// `RouteConstraints`. Never throws; every malformed / missing / hostile
/// field collapses to a documented default and is noted in `assumptions`.
/// This is the single trust boundary between the LLM and the generator.
export function validateConstraints(raw: unknown): RouteConstraints {
	const o = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
	const assumptions: string[] = [];

	const distanceM = clampDistance(o.distance_m);
	const surface = SURFACES.has(o.surface as string)
		? (o.surface as RouteRequestSurface)
		: null;
	const shape = SHAPES.has(o.shape as string) ? (o.shape as RouteShape) : null;
	const avoidHighways =
		typeof o.avoid_highways === 'boolean' ? o.avoid_highways : null;
	const preference = PREFERENCES.has(o.preference as string)
		? (o.preference as RoutePreference)
		: null;
	const resolvedPreference = preference ?? derivePreference(avoidHighways, surface);

	if (distanceM === null) assumptions.push('distance');
	if (surface === null) assumptions.push('surface');
	if (shape === null) assumptions.push('shape');
	if (avoidHighways === null) assumptions.push('avoid_highways');
	// Only a derivation is an assumption. Landing on null means we assumed
	// nothing — telling the runner we assumed a preference we did not set
	// would be the same dishonesty from the other direction.
	if (preference === null && resolvedPreference !== null) assumptions.push('preference');

	return {
		distanceM: distanceM ?? DEFAULT_REQUEST_DISTANCE_M,
		shape: shape ?? 'loop',
		surface: surface ?? 'road',
		avoidHighways: avoidHighways ?? false,
		preference: resolvedPreference,
		assumptions,
	};
}
