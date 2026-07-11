/**
 * Training-consistency derivation for the dashboard "Consistency" card.
 *
 * Consistency — how regularly you train, week to week — is a distinct signal
 * from the dashboard's other analytics: VDOT measures your fitness ceiling,
 * the training-load trio measures acute fatigue/form, the race predictor
 * projects times, the mileage chart shows raw volume, and the run streak
 * counts consecutive DAYS. This measures the fraction of recent calendar
 * WEEKS you trained at all, the trailing run of active weeks, and whether
 * your weekly volume is steady or spiky.
 *
 * Pure: no Supabase, no DOM, no rune state — so it unit-tests under
 * `tsx --test`. Web-only by design (no Dart twin); deliberately kept off the
 * enforced web↔mobile parity list.
 */

export type WeekStart = 'monday' | 'sunday';

/// The minimum an activity needs to expose: when it happened and how far it
/// went. The dashboard feeds its already-fetched `Run[]` straight in.
export interface ConsistencyActivity {
	started_at: string;
	distance_m: number;
}

export type VolumeSteadiness = 'steady' | 'variable';

export interface ConsistencyStats {
	/// Number of trailing calendar weeks the window spans (current week last).
	windowWeeks: number;
	/// Weeks in the window with at least one activity.
	weeksActive: number;
	/// weeksActive / windowWeeks as a 0..100 rounded percentage.
	activePct: number;
	/// Trailing run of consecutive active weeks ending at the current week.
	/// An empty in-progress current week does NOT break it (grace), mirroring
	/// the daily-streak grace rule the run streak already uses.
	currentStreak: number;
	/// Longest run of consecutive active weeks anywhere in the window.
	longestStreak: number;
	/// Per-week distance (metres, rounded), oldest → newest, length ===
	/// windowWeeks. Drives the mini week strip.
	weeklyDistanceM: number[];
	/// Coefficient of variation (stddev / mean) of ACTIVE weeks' volume, or
	/// null with < 2 active weeks. `steadiness` buckets it for the UI chip.
	volumeCov: number | null;
	steadiness: VolumeSteadiness | null;
}

/// Weekly-volume CoV at or below this reads as "steady". ~0.4 lets a normal
/// build / recovery cadence stay steady while a 10 / 70 / 5 / 60 km sawtooth
/// reads variable. Documented threshold, pinned by a unit test.
export const kSteadyCovThreshold = 0.4;

/// Midnight (local) at the start of the calendar week containing `d`,
/// honouring `weekStart`. Same offset math the dashboard's inline weekStart
/// derivation and current_week.ts use.
function weekStartMidnight(d: Date, weekStart: WeekStart): Date {
	const ws = new Date(d);
	const offset = weekStart === 'sunday' ? d.getDay() : (d.getDay() + 6) % 7;
	ws.setDate(d.getDate() - offset);
	ws.setHours(0, 0, 0, 0);
	return ws;
}

/// Compute consistency over the last `windowWeeks` calendar weeks ending with
/// the week containing `now`. Returns null when there isn't enough history to
/// speak to consistency (< 2 active weeks) so the card self-hides — you can't
/// call a single active week "consistent". `now` defaults to the real clock;
/// pass an explicit date in tests + on the server for determinism.
export function computeConsistency(
	activities: ConsistencyActivity[],
	weekStart: WeekStart = 'monday',
	windowWeeks = 12,
	now: Date = new Date(),
): ConsistencyStats | null {
	if (windowWeeks < 1) return null;

	const cur = weekStartMidnight(now, weekStart);
	const windowStart = new Date(cur);
	windowStart.setDate(cur.getDate() - (windowWeeks - 1) * 7);
	windowStart.setHours(0, 0, 0, 0);
	const windowStartMs = windowStart.getTime();
	const weekMs = 7 * 86_400_000;

	const weekly = new Array<number>(windowWeeks).fill(0);
	for (const a of activities) {
		const dist = a.distance_m;
		if (!(dist > 0)) continue;
		const t = new Date(a.started_at);
		if (Number.isNaN(t.getTime())) continue;
		// Index by whole weeks between local week-start midnights. Both ends
		// are local midnights, so Math.round absorbs the ±1h DST drift that
		// would otherwise land a boundary run one week off.
		const aws = weekStartMidnight(t, weekStart).getTime();
		const idx = Math.round((aws - windowStartMs) / weekMs);
		if (idx < 0 || idx >= windowWeeks) continue;
		weekly[idx] += dist;
	}

	const activeFlags = weekly.map((distance) => distance > 0);
	const weeksActive = activeFlags.filter(Boolean).length;
	if (weeksActive < 2) return null;

	let currentStreak = 0;
	let i = windowWeeks - 1;
	if (!activeFlags[i]) i -= 1; // grace: a partial, still-empty current week can't break the streak
	while (i >= 0 && activeFlags[i]) {
		currentStreak += 1;
		i -= 1;
	}

	let longestStreak = 0;
	let run = 0;
	for (const active of activeFlags) {
		if (active) {
			run += 1;
			if (run > longestStreak) longestStreak = run;
		} else {
			run = 0;
		}
	}

	// CoV over ACTIVE weeks only — an off week is already captured by
	// weeksActive, so folding its zero into the spread would double-count it
	// and label an otherwise-steady runner "variable" for one skipped week.
	const activeVols = weekly.filter((distance) => distance > 0);
	const mean = activeVols.reduce((s, v) => s + v, 0) / activeVols.length;
	let volumeCov: number | null = null;
	let steadiness: VolumeSteadiness | null = null;
	if (mean > 0 && activeVols.length >= 2) {
		const variance =
			activeVols.reduce((s, v) => s + (v - mean) ** 2, 0) / activeVols.length;
		volumeCov = Math.sqrt(variance) / mean;
		steadiness = volumeCov <= kSteadyCovThreshold ? 'steady' : 'variable';
	}

	return {
		windowWeeks,
		weeksActive,
		activePct: Math.round((weeksActive / windowWeeks) * 100),
		currentStreak,
		longestStreak,
		weeklyDistanceM: weekly.map((distance) => Math.round(distance)),
		volumeCov,
		steadiness,
	};
}
