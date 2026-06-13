import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	qualifyingRuns,
	vdotFromRun,
	currentVdot,
	vo2MaxFromVdot,
	runTss,
	thresholdPaceSecPerKmFromVdot,
	trainingLoad,
	computeSnapshot,
	recoveryAdvice,
	daysUntilNextHardSession,
	HARD_SESSION_TSB_THRESHOLD,
	isReturningFromLayoff,
	isReturningFromGap,
} from './fitness';
import type { Run } from '../types';

function r(partial: {
	started_at: string;
	distance_m: number;
	duration_s: number;
	source?: Run['source'];
	metadata?: Record<string, unknown> | null;
}): Run {
	return {
		id: 'r' + partial.started_at,
		user_id: 'u1',
		started_at: partial.started_at,
		distance_m: partial.distance_m,
		duration_s: partial.duration_s,
		source: partial.source ?? 'app',
		track_url: null,
		track: null,
		route_id: null,
		event_id: null,
		external_id: null,
		is_public: null,
		created_at: null,
		updated_at: null,
		metadata: partial.metadata ?? null,
	} as unknown as Run;
}

const NOW = Date.parse('2026-04-30T07:00:00Z');

// ─────────────── qualifyingRuns ───────────────

test('qualifyingRuns — drops sub-1.5km runs (too noisy for VDOT)', () => {
	const longEnough = r({ started_at: '2026-04-01T07:00:00Z', distance_m: 5000, duration_s: 1500 });
	const tooShort = r({ started_at: '2026-04-02T07:00:00Z', distance_m: 1000, duration_s: 360 });
	assert.deepEqual(qualifyingRuns([longEnough, tooShort]), [longEnough]);
});

// Persona round-5 runner-comeback: a runner rebuilding at 1.5-2 km/run must
// still see a fitness signal. The old 3 km floor hid them entirely; the new
// 1.5 km floor (paired with the 5-min duration gate) admits a sustained short
// run while still rejecting noisy 1 km all-out efforts.
test('qualifyingRuns — admits a sustained 1.5-2km comeback run', () => {
	const comeback = r({ started_at: '2026-04-01T07:00:00Z', distance_m: 1800, duration_s: 600 });
	assert.deepEqual(qualifyingRuns([comeback]), [comeback]);
});

test('qualifyingRuns — drops sub-5min runs (sprint efforts)', () => {
	const longEnough = r({ started_at: '2026-04-01T07:00:00Z', distance_m: 5000, duration_s: 1500 });
	const tooShort = r({ started_at: '2026-04-02T07:00:00Z', distance_m: 5000, duration_s: 200 });
	assert.deepEqual(qualifyingRuns([longEnough, tooShort]), [longEnough]);
});

test('qualifyingRuns — drops indoor/treadmill runs (belt distance is not VDOT-worthy)', () => {
	const outdoor = r({ started_at: '2026-04-01T07:00:00Z', distance_m: 5000, duration_s: 1500 });
	const treadmill = r({
		started_at: '2026-04-02T07:00:00Z',
		distance_m: 5000,
		duration_s: 1500,
		source: 'garmin',
		metadata: { indoor: true }
	});
	assert.deepEqual(qualifyingRuns([outdoor, treadmill]), [outdoor]);
});

test('qualifyingRuns — accepts every recognised source, drops others', () => {
	const accepted = (['app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect'] as const).map((s) =>
		r({ started_at: '2026-04-01T07:00:00Z', distance_m: 5000, duration_s: 1500, source: s }),
	);
	const rejected = r({
		started_at: '2026-04-01T07:00:00Z',
		distance_m: 5000,
		duration_s: 1500,
		source: 'manual_entry' as Run['source'],
	});
	const out = qualifyingRuns([...accepted, rejected]);
	assert.equal(out.length, accepted.length);
});

// ─────────────── vdotFromRun ───────────────

test('vdotFromRun — sub-1km run returns null', () => {
	assert.equal(vdotFromRun(500, 200), null);
});

test('vdotFromRun — sub-2min run returns null', () => {
	assert.equal(vdotFromRun(1500, 100), null);
});

test('vdotFromRun — 20-minute 5k yields a VDOT around 50', () => {
	const v = vdotFromRun(5000, 20 * 60);
	assert.ok(v != null);
	assert.ok(v! > 48 && v! < 52, `expected ~50, got ${v}`);
});

test('vdotFromRun — 3-hour marathon yields a VDOT around 53-55', () => {
	const v = vdotFromRun(42195, 3 * 3600);
	assert.ok(v != null);
	assert.ok(v! > 52 && v! < 56, `expected ~54, got ${v}`);
});

test('vdotFromRun — a distance-glitch run (impossible speed) is rejected, not used as the ceiling', () => {
	// 5 km logged in 10 min = 30 km/h → VDOT ~111 on the raw formula. A GPS
	// spike or bad import must not set the fitness ceiling.
	assert.equal(vdotFromRun(5000, 10 * 60), null);
	// A world-class but real 5k (14:00) stays under the ceiling and qualifies.
	const elite = vdotFromRun(5000, 14 * 60);
	assert.ok(elite != null && elite! < 90, `elite 5k should qualify, got ${elite}`);
});

test('currentVdot — a glitch run does not poison the 90-day ceiling', () => {
	const base = '2026-05-01T10:00:00Z';
	const now = new Date('2026-05-10T10:00:00Z').getTime();
	const runs = [
		// A legit 5k at ~20:00 → VDOT ~50.
		{ started_at: base, distance_m: 5000, duration_s: 1200, source: 'app', metadata: {} },
		// A glitch: 5 km in 10 min → VDOT ~111, must be dropped.
		{ started_at: base, distance_m: 5000, duration_s: 600, source: 'app', metadata: {} },
	] as unknown as Parameters<typeof currentVdot>[0];
	const v = currentVdot(runs, now);
	assert.ok(v != null && v! < 90, `ceiling should be the real run, got ${v}`);
});

test('vdotFromRun — faster pace yields a higher VDOT', () => {
	const fast = vdotFromRun(5000, 18 * 60)!;
	const slow = vdotFromRun(5000, 25 * 60)!;
	assert.ok(fast > slow, `fast ${fast} should beat slow ${slow}`);
});

// ─────────────── currentVdot ───────────────

test('currentVdot — picks the best qualifying run in the last 90 days', () => {
	const fast = r({ started_at: '2026-04-15T07:00:00Z', distance_m: 5000, duration_s: 18 * 60 });
	const slow = r({ started_at: '2026-04-22T07:00:00Z', distance_m: 5000, duration_s: 25 * 60 });
	const v = currentVdot([fast, slow], NOW);
	assert.ok(v != null);
	// Best 5k is the 18-min run → VDOT ~54.
	assert.ok(v! > 52);
});

test('currentVdot — ignores runs older than the 90-day window', () => {
	const recentSlow = r({ started_at: '2026-04-15T07:00:00Z', distance_m: 5000, duration_s: 25 * 60 });
	const oldFast = r({ started_at: '2025-12-01T07:00:00Z', distance_m: 5000, duration_s: 18 * 60 });
	const v = currentVdot([recentSlow, oldFast], NOW);
	assert.ok(v != null);
	// Only the slow one counts → VDOT around 38-42.
	assert.ok(v! < 50, `old fast run should be excluded, got ${v}`);
});

test('currentVdot — empty list returns null', () => {
	assert.equal(currentVdot([], NOW), null);
});

// ─────────────── vo2MaxFromVdot ───────────────

test('vo2MaxFromVdot — passes through (same number, different label)', () => {
	assert.equal(vo2MaxFromVdot(50), 50);
	assert.equal(vo2MaxFromVdot(null), null);
});

// ─────────────── thresholdPaceSecPerKmFromVdot ───────────────

test('thresholdPaceSecPerKmFromVdot — null in returns null', () => {
	assert.equal(thresholdPaceSecPerKmFromVdot(null), null);
});

test('thresholdPaceSecPerKmFromVdot — VDOT 50 falls in the 240-260 s/km band', () => {
	const t = thresholdPaceSecPerKmFromVdot(50);
	assert.ok(t != null);
	assert.ok(t! > 230 && t! < 270, `got ${t}`);
});

test('thresholdPaceSecPerKmFromVdot — higher VDOT yields a faster threshold', () => {
	const elite = thresholdPaceSecPerKmFromVdot(70)!;
	const beginner = thresholdPaceSecPerKmFromVdot(30)!;
	assert.ok(elite < beginner);
});

// ─────────────── runTss ───────────────

test('runTss — sub-100m or sub-30s or zero threshold returns 0', () => {
	assert.equal(runTss(50, 60, 300), 0);
	assert.equal(runTss(1000, 10, 300), 0);
	assert.equal(runTss(5000, 1500, 0), 0);
});

test('runTss — pace at threshold yields an intensity of 1.0 → ~100 TSS per hour', () => {
	// 1 hour at threshold pace = exactly 100 TSS by Coggan's reference.
	// Run pace s/km = 3600 / 12 km = 300, threshold same.
	const tss = runTss(12000, 3600, 300);
	assert.ok(Math.abs(tss - 100) < 1, `got ${tss}`);
});

test('runTss — running faster than threshold raises TSS faster than linearly', () => {
	const slow = runTss(10000, 3600, 300); // pace 360 s/km
	const fast = runTss(12000, 3600, 300); // pace 300 s/km (= threshold)
	const faster = runTss(15000, 3600, 300); // pace 240 s/km
	assert.ok(fast > slow);
	assert.ok(faster > fast);
	// Quadratic in intensity, so each step up is bigger than the prior.
	assert.ok(faster - fast > fast - slow);
});

// ─────────────── trainingLoad ───────────────

test('trainingLoad — null threshold or no runs yields all-null', () => {
	const empty = trainingLoad([], 300, NOW);
	assert.equal(empty.acuteLoad, null);
	const noThresh = trainingLoad(
		[r({ started_at: '2026-04-15T07:00:00Z', distance_m: 5000, duration_s: 1500 })],
		null,
		NOW,
	);
	assert.equal(noThresh.acuteLoad, null);
});

test('trainingLoad — emits non-null curves with at least one qualifying run', () => {
	// One run a week for ~6 weeks → CTL should be >0 by the end.
	const runs: Run[] = [];
	for (let week = 0; week < 6; week++) {
		const t = NOW - (40 - week * 7) * 24 * 3600 * 1000;
		runs.push(
			r({
				started_at: new Date(t).toISOString(),
				distance_m: 10000,
				duration_s: 3600,
			}),
		);
	}
	const load = trainingLoad(runs, 300, NOW);
	assert.ok(load.acuteLoad != null);
	assert.ok(load.chronicLoad != null);
	assert.ok(load.trainingStressBal != null);
	assert.ok(load.acuteLoad! > 0);
	assert.ok(load.chronicLoad! > 0);
});

// Pins the reconciled EWMA convention: runs bucket by LOCAL day and the
// curves use alpha = 1 − exp(−1/halflife) (matching training_load.ts), NOT
// UTC bucketing + a 1/N step. A single 10 km / 60-min run (TSS = 69.44…) at
// threshold pace 300 s/km, logged at local noon 9 days before a local-07:00
// `now`, walked across a 43-day window. Both inputs are local-clock so the
// numbers are timezone-stable (noon never rolls a calendar day). Computed,
// not guessed — change these only if the convention changes.
test('trainingLoad — single run produces the reconciled (alpha-EWMA, local-day) ATL/CTL/TSB', () => {
	const now = new Date(2026, 3, 30, 7, 0, 0).getTime(); // local 2026-04-30 07:00
	const run = r({
		started_at: new Date(2026, 3, 21, 12, 0, 0).toISOString(), // local 2026-04-21 noon
		distance_m: 10000,
		duration_s: 3600,
	});
	const load = trainingLoad([run], 300, now);
	assert.ok(load.acuteLoad != null && load.chronicLoad != null && load.trainingStressBal != null);
	assert.ok(Math.abs(load.acuteLoad! - 2.555695151929763) < 1e-9, `atl ${load.acuteLoad}`);
	assert.ok(Math.abs(load.chronicLoad! - 1.3187582819498793) < 1e-9, `ctl ${load.chronicLoad}`);
	assert.ok(
		Math.abs(load.trainingStressBal! - -1.2369368699798837) < 1e-9,
		`tsb ${load.trainingStressBal}`,
	);
});

test('trainingLoad — TSB rises during a 14-day taper with no further runs', () => {
	const buildEnd = NOW - 14 * 24 * 3600 * 1000;
	const runs: Run[] = [];
	// Heavy 4-week build, then nothing.
	for (let week = 0; week < 4; week++) {
		const t = buildEnd - (28 - week * 7) * 24 * 3600 * 1000;
		runs.push(
			r({
				started_at: new Date(t).toISOString(),
				distance_m: 15000,
				duration_s: 4500,
			}),
		);
	}
	const atBuildEnd = trainingLoad(runs, 300, buildEnd);
	const atTaperEnd = trainingLoad(runs, 300, NOW);
	assert.ok(atTaperEnd.trainingStressBal! > atBuildEnd.trainingStressBal!);
});

// ─────────────── computeSnapshot ───────────────

test('computeSnapshot — rolls VDOT, VO2 max, training load + qualifying-run count together', () => {
	const runs: Run[] = [];
	for (let week = 0; week < 6; week++) {
		const t = NOW - (40 - week * 7) * 24 * 3600 * 1000;
		runs.push(
			r({
				started_at: new Date(t).toISOString(),
				distance_m: 10000,
				duration_s: 50 * 60,
			}),
		);
	}
	const snap = computeSnapshot(runs, NOW);
	assert.ok(snap.vdot != null);
	assert.equal(snap.vo2Max, snap.vdot);
	assert.equal(snap.qualifyingRunCount, 6);
	assert.ok(snap.acuteLoad != null);
});

test('computeSnapshot — empty runs yields all-null + zero count', () => {
	const snap = computeSnapshot([], NOW);
	assert.equal(snap.vdot, null);
	assert.equal(snap.vo2Max, null);
	assert.equal(snap.acuteLoad, null);
	assert.equal(snap.chronicLoad, null);
	assert.equal(snap.trainingStressBal, null);
	assert.equal(snap.qualifyingRunCount, 0);
});

// ─────────────── recoveryAdvice ───────────────

test('recoveryAdvice — null inputs yield the no-data string', () => {
	assert.match(recoveryAdvice(null, null), /Not enough data/);
	assert.match(recoveryAdvice(null, 50), /Not enough data/);
	assert.match(recoveryAdvice(0, null), /Not enough data/);
});

test('recoveryAdvice — sub-10 CTL yields the consistency-building advice', () => {
	assert.match(recoveryAdvice(0, 5), /still building|consistency/i);
});

test('recoveryAdvice — heavy overload warns even at low CTL (overreached new runner)', () => {
	// ctl=8, tsb=-40 → acute load spiked far above chronic. The low-CTL
	// "still building" message must NOT mask the rest warning.
	const advice = recoveryAdvice(-40, 8);
	assert.match(advice, /heavily loaded|rest day/i);
	assert.doesNotMatch(advice, /still building|consistency/i);
});

test('recoveryAdvice — ladder rises through the TSB bands', () => {
	const heavy = recoveryAdvice(-40, 50);
	const loaded = recoveryAdvice(-15, 50);
	const sweet = recoveryAdvice(0, 50);
	const taper = recoveryAdvice(15, 50);
	const fresh = recoveryAdvice(40, 50);
	// Each band should produce a distinct human string.
	const all = new Set([heavy, loaded, sweet, taper, fresh]);
	assert.equal(all.size, 5, 'each band should map to a unique message');
	assert.match(heavy, /easy|rest|recovery/i);
	assert.match(fresh, /fresh|race|build/i);
});

test('recoveryAdvice — returning-from-layoff overrides the freshness rungs (comeback #29)', () => {
	// A high TSB + decent CTL would normally read "very fresh — race soon",
	// which is exactly the wrong call for a returning runner.
	const normal = recoveryAdvice(40, 50, false);
	const returning = recoveryAdvice(40, 50, true);
	assert.notEqual(normal, returning);
	assert.match(returning, /back|rebuild|gradual|break/i);
	assert.doesNotMatch(returning, /race soon/i);
});

// ─────────────── daysUntilNextHardSession ───────────────

test('daysUntilNextHardSession — null inputs return null', () => {
	assert.equal(daysUntilNextHardSession(null, 50), null);
	assert.equal(daysUntilNextHardSession(50, null), null);
});

test('daysUntilNextHardSession — already recovered returns 0', () => {
	// TSB = ctl - atl = 60 - 50 = +10, well above the -10 threshold.
	assert.equal(daysUntilNextHardSession(50, 60), 0);
	// Exactly at the threshold (TSB = -10) still counts as ready today.
	assert.equal(daysUntilNextHardSession(60, 50), 0);
});

test('daysUntilNextHardSession — heavy fatigue needs several easy days', () => {
	// Deeply loaded: atl 90, ctl 60 → TSB = -30. With rest, ATL decays
	// faster than CTL so TSB climbs back toward the -10 threshold.
	const d = daysUntilNextHardSession(90, 60);
	assert.ok(d != null && d >= 1, 'should be at least a day out');
	// Sanity-check it's the first day TSB crosses the threshold.
	const atlDecay = Math.exp(-1 / 7);
	const ctlDecay = Math.exp(-1 / 42);
	let a = 90;
	let c = 60;
	for (let i = 0; i < d!; i++) {
		assert.ok(c - a < HARD_SESSION_TSB_THRESHOLD, `day ${i} should still be loaded`);
		a *= atlDecay;
		c *= ctlDecay;
	}
	assert.ok(c - a >= HARD_SESSION_TSB_THRESHOLD, 'crosses the threshold on the returned day');
});

test('daysUntilNextHardSession — returns null when recovery exceeds maxDays', () => {
	// A tiny maxDays window with deep fatigue can't recover in time.
	assert.equal(daysUntilNextHardSession(90, 60, 1), null);
});

test('isReturningFromLayoff — true when a recent run follows a >28d gap', () => {
	const runs = [
		r({ started_at: '2025-12-01T07:00:00Z', distance_m: 10000, duration_s: 3000 }),
		// ~60 days later, then resuming the day before NOW.
		r({ started_at: '2026-04-29T07:00:00Z', distance_m: 5000, duration_s: 1800 }),
	];
	assert.equal(isReturningFromLayoff(runs, NOW), true);
});

test('isReturningFromLayoff — false for a steady runner (no gap)', () => {
	const runs = [
		r({ started_at: '2026-04-20T07:00:00Z', distance_m: 8000, duration_s: 2400 }),
		r({ started_at: '2026-04-27T07:00:00Z', distance_m: 8000, duration_s: 2400 }),
		r({ started_at: '2026-04-29T07:00:00Z', distance_m: 8000, duration_s: 2400 }),
	];
	assert.equal(isReturningFromLayoff(runs, NOW), false);
});

test('isReturningFromLayoff — false for a single run (new runner, not returning)', () => {
	const runs = [r({ started_at: '2026-04-29T07:00:00Z', distance_m: 5000, duration_s: 1800 })];
	assert.equal(isReturningFromLayoff(runs, NOW), false);
});

test('isReturningFromLayoff — false when not currently active (gap is ongoing)', () => {
	// Last run was 40 days ago — they're mid-layoff, not "returning".
	const runs = [
		r({ started_at: '2026-02-01T07:00:00Z', distance_m: 10000, duration_s: 3000 }),
		r({ started_at: '2026-03-21T07:00:00Z', distance_m: 10000, duration_s: 3000 }),
	];
	assert.equal(isReturningFromLayoff(runs, NOW), false);
});

// ─────────────── isReturningFromGap (welcome-back surface) ───────────────

test('isReturningFromGap — false for no runs (a brand-new account is not "back")', () => {
	assert.equal(isReturningFromGap([], 60, NOW), false);
});

test('isReturningFromGap — true when the only/most-recent run is older than the gap', () => {
	// Most recent run was ~5 months ago — a long-absent runner reopening cold.
	const runs = [
		r({ started_at: '2025-09-01T07:00:00Z', distance_m: 10000, duration_s: 3000 }),
		r({ started_at: '2025-11-30T07:00:00Z', distance_m: 8000, duration_s: 2400 }),
	];
	assert.equal(isReturningFromGap(runs, 60, NOW), true);
});

test('isReturningFromGap — false for an active runner (a recent run inside the window)', () => {
	const runs = [
		r({ started_at: '2026-02-01T07:00:00Z', distance_m: 10000, duration_s: 3000 }),
		r({ started_at: '2026-04-20T07:00:00Z', distance_m: 8000, duration_s: 2400 }),
	];
	assert.equal(isReturningFromGap(runs, 60, NOW), false);
});

test('isReturningFromGap — counts non-qualifying runs (a logged treadmill walk still proves history)', () => {
	// Short + indoor: excluded from VDOT math, but it still means the user
	// has run before, so the welcome-back framing should fire on the gap.
	const runs = [
		r({
			started_at: '2025-10-01T07:00:00Z',
			distance_m: 1500,
			duration_s: 600,
			metadata: { indoor: true },
		}),
	];
	assert.equal(isReturningFromGap(runs, 60, NOW), true);
});

test('isReturningFromGap — true exactly at the boundary, false just inside it', () => {
	const dayMs = 24 * 3600_000;
	const exactly60 = r({
		started_at: new Date(NOW - 60 * dayMs).toISOString(),
		distance_m: 5000,
		duration_s: 1800,
	});
	assert.equal(isReturningFromGap([exactly60], 60, NOW), true);
	const fiftyNine = r({
		started_at: new Date(NOW - 59 * dayMs).toISOString(),
		distance_m: 5000,
		duration_s: 1800,
	});
	assert.equal(isReturningFromGap([fiftyNine], 60, NOW), false);
});
