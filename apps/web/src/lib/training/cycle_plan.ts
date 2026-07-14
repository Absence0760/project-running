/**
 * Menstrual-cycle-aware and pregnancy-aware plan-adjustment logic.
 *
 * SENSITIVE: the inputs (cycle length, last-period-start, due date) are GDPR
 * Art 9 special-category reproductive-health data. This module is the PURE
 * half — it takes already-consented inputs plus a plan workout and returns
 * the modest, bounded patch to apply. Consent gating, the fail-closed feature
 * flag, and persistence live at the call sites (settings + plan-detail).
 *
 * The algorithm is deliberately conservative and reuses the recovery-week
 * ease shape (clear the strict pace target, scale distance) rather than
 * inventing new intensity math. Full rationale + exact bounds in
 * docs/architecture/decisions.md § 231 and docs/features/training.md.
 *
 * TS↔Dart parity pair with apps/mobile_android/lib/cycle_plan.dart — keep the
 * two in lockstep (equal test counts). Mirror Dart to the iOS twin.
 */

export type CyclePhase = 'menstrual' | 'follicular' | 'ovulatory' | 'luteal';
export type Trimester = 1 | 2 | 3;

/// Sane menstrual-cycle bounds. Outside this range the phase derivation is
/// refused (no adjustment) rather than guessing off an implausible input —
/// fail-safe: leaving the plan as prescribed beats mis-easing it.
export const MIN_CYCLE_LENGTH_DAYS = 21;
export const MAX_CYCLE_LENGTH_DAYS = 40;

// The luteal phase is ~14 days and far more stable across individuals than the
// follicular phase, so ovulation is estimated as cycleLength − 14 (the
// standard clinical assumption for a calendar-based estimate).
const LUTEAL_LENGTH_DAYS = 14;
// The first 5 days of the cycle are counted as menstruation.
const MENSTRUAL_DAYS = 5;
// The ovulatory window is the estimated ovulation day ± this many days.
const OVULATORY_RADIUS_DAYS = 1;
// The last N days before the next predicted period ("late luteal" /
// premenstrual) are eased alongside the menstrual days.
const LATE_LUTEAL_DAYS = 3;

/// Modest, bounded volume trim applied on eased cycle days — 15% off, NOT the
/// 40% of a full recovery week. Cycle science does not support a large,
/// deterministic per-phase volume cut; a gentle nudge plus running quality
/// sessions by feel is the defensible ceiling for an auto-adjustment.
export const CYCLE_EASE_SCALE = 0.85;

/// Pregnancy volume taper by trimester — a progressive reduction. These are
/// conservative caps, NOT a medical prescription: the in-UI disclaimer tells
/// the runner to follow their provider, and every quality/race session is
/// stripped to easy, effort-based running regardless of trimester.
export const PREGNANCY_VOLUME_SCALE: Record<Trimester, number> = {
	1: 0.9,
	2: 0.75,
	3: 0.5
};

/// Full-term gestation in weeks — the reference the trimester math counts back
/// from the due date.
const GESTATION_WEEKS = 40;

/// Kinds that carry a strict pace target and/or structured intervals — eased
/// (cycle) or stripped to easy (pregnancy).
const QUALITY_KINDS = new Set(['tempo', 'interval', 'marathon_pace']);

// ─────────────────────── Date helpers ───────────────────────
// Whole-day differences via UTC epoch-day math so they never drift across a
// local-midnight / DST boundary. ISO `YYYY-MM-DD` in, day counts out.

function isoToEpochDay(iso: string): number {
	const [y, m, d] = iso.split('-').map((n) => parseInt(n, 10));
	return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
}

export function daysBetweenIso(fromIso: string, toIso: string): number {
	return isoToEpochDay(toIso) - isoToEpochDay(fromIso);
}

// ─────────────────────── Menstrual cycle ───────────────────────

export interface CycleDayInfo {
	/// 0-based day within the current cycle (0 = first day of menstruation).
	dayInCycle: number;
	phase: CyclePhase;
	/// True on menstrual OR late-luteal days — the days the plan is eased.
	isEaseDay: boolean;
}

/**
 * Derive the cycle-day info for `dateIso` from the last-period-start anchor and
 * cycle length. Returns null when the cycle length is outside the sane band
 * (the caller then leaves the plan unadjusted). Dates before the anchor are
 * handled by wrapping the modulo into [0, cycleLength).
 */
export function cycleDayInfo(
	lastPeriodStartIso: string,
	cycleLengthDays: number,
	dateIso: string
): CycleDayInfo | null {
	if (
		!Number.isFinite(cycleLengthDays) ||
		cycleLengthDays < MIN_CYCLE_LENGTH_DAYS ||
		cycleLengthDays > MAX_CYCLE_LENGTH_DAYS
	) {
		return null;
	}
	const raw = daysBetweenIso(lastPeriodStartIso, dateIso);
	if (!Number.isFinite(raw)) return null;
	const len = Math.round(cycleLengthDays);
	const dayInCycle = ((raw % len) + len) % len;

	const ovulationDay = len - LUTEAL_LENGTH_DAYS;
	let phase: CyclePhase;
	if (dayInCycle < MENSTRUAL_DAYS) {
		phase = 'menstrual';
	} else if (dayInCycle < ovulationDay - OVULATORY_RADIUS_DAYS) {
		phase = 'follicular';
	} else if (dayInCycle <= ovulationDay + OVULATORY_RADIUS_DAYS) {
		phase = 'ovulatory';
	} else {
		phase = 'luteal';
	}
	const isLateLuteal = dayInCycle >= len - LATE_LUTEAL_DAYS;
	const isEaseDay = phase === 'menstrual' || isLateLuteal;
	return { dayInCycle, phase, isEaseDay };
}

// ─────────────────────── Pregnancy ───────────────────────

/**
 * Trimester for `dateIso` given the due date. Returns null when the date falls
 * outside the pregnancy — before the conception window (gestational age < 0)
 * or more than two weeks past the due date — so those weeks run as prescribed.
 */
export function trimesterForDate(dueDateIso: string, dateIso: string): Trimester | null {
	const daysUntilDue = daysBetweenIso(dateIso, dueDateIso);
	if (!Number.isFinite(daysUntilDue)) return null;
	const gestWeeks = GESTATION_WEEKS - daysUntilDue / 7;
	if (gestWeeks < 0) return null; // before conception — not pregnant yet on this date
	if (gestWeeks > GESTATION_WEEKS + 2) return null; // >2wk past due — stop adjusting stale weeks
	if (gestWeeks < 14) return 1;
	if (gestWeeks < 28) return 2;
	return 3;
}

// ─────────────────────── Workout patch ───────────────────────

export type CyclePlanConfig =
	| { mode: 'cycle'; cycleLengthDays: number; lastPeriodStartIso: string }
	| { mode: 'pregnancy'; dueDateIso: string };

export interface CyclePlanWorkoutPatch {
	kind?: string;
	target_distance_m?: number | null;
	target_pace_sec_per_km?: number | null;
	target_pace_tolerance_sec?: number | null;
	structure?: null;
}

/**
 * Compute the patch to apply to one plan workout under a cycle/pregnancy
 * adjustment. Returns null for workouts that shouldn't change on that date.
 *
 * Cycle mode: only menstrual + late-luteal days are eased — quality sessions
 * lose their strict pace target (run by feel; kind unchanged) and distances
 * scale to CYCLE_EASE_SCALE. Follicular / ovulatory / early-luteal days, rest,
 * and the goal race are left exactly as prescribed.
 *
 * Pregnancy mode: within the pregnancy every quality/race session is stripped
 * to easy, effort-based running (no intervals, no strict pace, structure
 * cleared) and all distances taper by trimester (PREGNANCY_VOLUME_SCALE).
 * Weeks outside the pregnancy are untouched.
 */
export function cyclePlanWorkoutPatch(
	w: { kind: string; target_distance_m: number | null; scheduled_date: string },
	cfg: CyclePlanConfig
): CyclePlanWorkoutPatch | null {
	if (w.kind === 'rest') return null;

	if (cfg.mode === 'cycle') {
		const info = cycleDayInfo(cfg.lastPeriodStartIso, cfg.cycleLengthDays, w.scheduled_date);
		if (!info || !info.isEaseDay) return null;
		if (w.kind === 'race') return null; // never touch the goal race
		const patch: CyclePlanWorkoutPatch = {};
		if (QUALITY_KINDS.has(w.kind)) {
			// Run the quality session by feel — clear the strict pace target and
			// its tolerance. Kind stays (a modest ease, not a recovery week).
			patch.target_pace_sec_per_km = null;
			patch.target_pace_tolerance_sec = null;
		}
		if (w.target_distance_m != null) {
			patch.target_distance_m = Math.round(w.target_distance_m * CYCLE_EASE_SCALE);
		}
		return Object.keys(patch).length > 0 ? patch : null;
	}

	const tri = trimesterForDate(cfg.dueDateIso, w.scheduled_date);
	if (tri == null) return null; // date falls outside the pregnancy → unchanged
	const patch: CyclePlanWorkoutPatch = {};
	if (QUALITY_KINDS.has(w.kind) || w.kind === 'race') {
		patch.kind = 'easy';
		patch.target_pace_sec_per_km = null;
		patch.target_pace_tolerance_sec = null;
		patch.structure = null;
	}
	if (w.target_distance_m != null) {
		patch.target_distance_m = Math.round(w.target_distance_m * PREGNANCY_VOLUME_SCALE[tri]);
	}
	return Object.keys(patch).length > 0 ? patch : null;
}
