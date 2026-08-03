// The dashboard fetch was changed from an unbounded `fetchRuns()`
// (`select('*')`, paging the ENTIRE history 1000 rows at a time incl. the
// metadata jsonb bag) to a bounded `fetchRunsForDashboard()` — a ~2-year
// window, column-narrowed. Issue #332.
//
// The perf change itself can't be unit-tested (it's a Supabase query
// shape — pinned by the source guard in data.test.ts). What MUST be
// proven is the risk the window introduces: that no dashboard card
// computation silently goes blank or wrong when it only sees the last
// ~2 years instead of all runs ever. Every consumer here is recency-
// scoped (90-day load curve, this-week goal, recency-weighted race
// predictor, day streak), so the windowed set must produce the SAME
// answer the full history would — that's the safety contract.
//
// Runs with cwd = apps/web (`test:unit`). data.ts can't be imported here
// (it pulls the supabase singleton + `$env`), so the window contract is
// imported from the pure `./dashboard_runs` sibling that data.ts uses.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	DASHBOARD_RUNS_WINDOW_DAYS,
	dashboardRunsWindowStart,
	periodNeedsFullHistory,
	type PeriodType,
} from './dashboard_runs';
import { computeRunStreaks } from '../runs/streaks';
import { computeTrainingLoadSeries } from '../training/training_load';
import { qualifyingRuns, isReturningFromGap } from '../training/fitness';
import { predictRaceLadder } from '../training/race_predictor';
import { evaluateGoal, type RunGoal } from '../training/goals';
import type { Run } from '../types';

const DAY_MS = 86_400_000;
const NOW = new Date('2026-07-15T09:00:00Z');

/// A deterministic history that spans WELL past the window: 500 runs, one
/// every other day going back ~2.7 years (500 * 2 = 1000 days). So ~365
/// of them fall inside the 730-day window and ~135 fall outside it — a
/// >400-run, >1-year fixture that exercises both sides of the boundary.
function buildHistory(): Run[] {
	const runs: Run[] = [];
	for (let i = 0; i < 500; i++) {
		const started = new Date(NOW.getTime() - i * 2 * DAY_MS);
		// Vary distance so max/streak/predictor have signal; a heavy
		// marathon-length effort sits OUTSIDE the window (i=450 → 900 days
		// ago) to prove the window doesn't need it for recency cards.
		const distance_m = i === 450 ? 42_195 : 5_000 + (i % 7) * 800;
		runs.push({
			id: `run-${i}`,
			user_id: 'u1',
			started_at: started.toISOString(),
			distance_m,
			duration_s: Math.round(distance_m * 0.3),
			source: 'app',
			activity_type: 'run',
			metadata: { avg_bpm: 150 + (i % 5) },
			track: null,
		} as unknown as Run);
	}
	return runs;
}

function windowed(runs: Run[]): Run[] {
	const cutoff = dashboardRunsWindowStart(NOW).getTime();
	return runs.filter((r) => new Date(r.started_at).getTime() >= cutoff);
}

test('the window drops old runs but keeps recent ones (bounds the fetch)', () => {
	const full = buildHistory();
	const win = windowed(full);
	assert.ok(full.length > 400, 'fixture sanity: >400 runs across the full history');
	assert.ok(win.length < full.length, 'window must drop runs older than ~2 years');
	// 730-day window over an every-other-day history ≈ 365 runs, spanning
	// well over a year — a generous recent set, not the whole history.
	assert.ok(win.length > 350, 'window must still cover a year-plus of recent runs');
	const cutoff = dashboardRunsWindowStart(NOW).getTime();
	assert.ok(
		win.every((r) => new Date(r.started_at).getTime() >= cutoff),
		'no run older than the window may survive it',
	);
	// The marathon effort planted at ~900 days ago is intentionally outside.
	assert.ok(
		full.some((r) => r.distance_m === 42_195),
		'fixture sanity: the deep-history marathon exists in the full set',
	);
	assert.ok(
		!win.some((r) => r.distance_m === 42_195),
		'fixture sanity: the deep-history marathon is outside the window',
	);
});

test('DASHBOARD_RUNS_WINDOW_DAYS is a generous multi-year window', () => {
	// Guards against a future "just shrink the ceiling" band-aid — the fix
	// is a generous window, not a small cap.
	assert.equal(DASHBOARD_RUNS_WINDOW_DAYS, 730);
});

test('training-load 90-day series is identical windowed vs full history', () => {
	const full = buildHistory();
	const prefs = { resting_hr_bpm: 50, max_hr_bpm: 190 };
	const fromFull = computeTrainingLoadSeries(full, prefs, 90, NOW);
	const fromWin = computeTrainingLoadSeries(windowed(full), prefs, 90, NOW);
	assert.ok(fromWin.length > 0, 'load series must not be blank on the windowed set');
	assert.deepEqual(
		fromWin,
		fromFull,
		'the 90-day load curve must be unchanged by the window — its inputs are all recent',
	);
});

test('this-week goal progress is identical windowed vs full history', () => {
	const full = buildHistory();
	const goal: RunGoal = { id: 'g1', period: 'week', distanceMetres: 20_000 };
	const fromFull = evaluateGoal(goal, full, NOW, 'monday');
	const fromWin = evaluateGoal(goal, windowed(full), NOW, 'monday');
	assert.ok(fromWin.overallPercent > 0, 'weekly goal must register progress on the windowed set');
	assert.deepEqual(
		fromWin,
		fromFull,
		'weekly goal progress must be unchanged by the window — only this-week runs count',
	);
});

test('run streak (current + best) is computed, not blanked, on the windowed set', () => {
	const full = buildHistory();
	const startsWin = windowed(full).map((r) => new Date(r.started_at));
	const streaks = computeRunStreaks(startsWin, NOW);
	// Every-other-day history → no consecutive-day streak > 1, but the
	// computation must still run and return a coherent, non-negative shape.
	assert.ok(streaks.current >= 0 && streaks.best >= streaks.current, 'streak shape must be coherent');
	// A dense recent block still produces the right streak from the window.
	const dense = [0, 1, 2, 3].map((d) => new Date(NOW.getTime() - d * DAY_MS));
	const denseStreak = computeRunStreaks(windowed([...full]).map((r) => new Date(r.started_at)).concat(dense), NOW);
	assert.ok(denseStreak.current >= 4, 'a 4-day recent block must yield a current streak of >= 4 from the window');
});

test('race predictor produces a ladder from windowed qualifying efforts', () => {
	const full = buildHistory();
	const win = windowed(full);
	const efforts = qualifyingRuns(win).map((r) => ({
		distanceM: r.distance_m,
		durationS: r.duration_s,
		ageDays: Math.max(0, (NOW.getTime() - new Date(r.started_at).getTime()) / DAY_MS),
	}));
	assert.ok(efforts.length > 0, 'the windowed set must yield qualifying efforts for the predictor');
	const ladder = predictRaceLadder(efforts);
	assert.ok(ladder != null, 'race predictor must return a ladder (not null) from the windowed efforts');
	assert.ok(ladder!.rungs.length > 0, 'the predicted ladder must carry rungs');
});

test('isReturningFromGap runs on the windowed set without error', () => {
	const full = buildHistory();
	// A steady every-other-day runner is not returning from a gap.
	assert.equal(
		typeof isReturningFromGap(windowed(full), NOW.getTime()),
		'boolean',
		'isReturningFromGap must return a boolean on the windowed set',
	);
});

// ── The window's cost: an "all time" roll-up must not come from it ──
//
// #332's fix bounded the dashboard fetch, then handed the SAME bounded set
// to the period drilldown — which offers an "all time" tab and unbounded
// Previous paging. So the modal opened by the exact "Longest run / all
// time" stat card reported totals short by everything older than the
// window (issue #664). `periodNeedsFullHistory` is the contract that
// routes such a period to the real history instead.

/// The roll-up PeriodSummary renders for the 'all' tab.
function allTimeStats(runs: Run[]) {
	return {
		distance: runs.reduce((s, r) => s + r.distance_m, 0),
		duration: runs.reduce((s, r) => s + r.duration_s, 0),
		count: runs.length,
		longest: runs.length ? Math.max(...runs.map((r) => r.distance_m)) : 0,
	};
}

/// What PeriodSummary computes over, given the prop set plus the loader.
function sourceRunsFor(
	type: PeriodType,
	periodStart: Date,
	propRuns: Run[],
	coveredFrom: Date | null,
	fullHistory: Run[],
): Run[] {
	return periodNeedsFullHistory(type, periodStart, coveredFrom) ? fullHistory : propRuns;
}

test('periodNeedsFullHistory: a complete-history caller never re-fetches', () => {
	// The standalone /dashboard/period route already holds every run.
	assert.equal(periodNeedsFullHistory('all', NOW, null), false);
	assert.equal(periodNeedsFullHistory('week', new Date('1999-01-04T00:00:00Z'), null), false);
});

test('periodNeedsFullHistory: an all-time tab can never be served by a bounded set', () => {
	assert.equal(periodNeedsFullHistory('all', NOW, dashboardRunsWindowStart(NOW)), true);
});

test('periodNeedsFullHistory: week/month only reach out when they predate the bound', () => {
	const cutoff = dashboardRunsWindowStart(NOW);
	const inside = new Date(cutoff.getTime() + 30 * DAY_MS);
	const outside = new Date(cutoff.getTime() - DAY_MS);
	assert.equal(periodNeedsFullHistory('week', inside, cutoff), false);
	assert.equal(periodNeedsFullHistory('month', inside, cutoff), false);
	assert.equal(periodNeedsFullHistory('week', outside, cutoff), true);
	assert.equal(periodNeedsFullHistory('month', outside, cutoff), true);
	// The boundary itself is covered — the fetch filters `started_at >= cutoff`.
	assert.equal(periodNeedsFullHistory('week', new Date(cutoff.getTime()), cutoff), false);
});

test('the all-time roll-up matches the lifetime aggregate, not the ~2-year window', () => {
	const full = buildHistory();
	const win = windowed(full);
	const cutoff = dashboardRunsWindowStart(NOW);

	// The under-report the window introduced, quantified: ~135 runs sit
	// outside it and the runner's longest run is one of them.
	const windowedRollUp = allTimeStats(win);
	const truth = allTimeStats(full);
	assert.ok(
		windowedRollUp.count < truth.count,
		'fixture sanity: the window drops runs from the all-time count',
	);
	assert.equal(truth.longest, 42_195, 'fixture sanity: the lifetime longest is the deep marathon');
	assert.ok(
		windowedRollUp.longest < truth.longest,
		'fixture sanity: the window cannot see the lifetime longest run',
	);

	// Routed through the contract, the all-time tab computes over the real
	// history — count, distance, duration and longest all match.
	assert.deepEqual(allTimeStats(sourceRunsFor('all', NOW, win, cutoff, full)), truth);
});

test('a month older than the window is rolled up from the real history', () => {
	const full = buildHistory();
	const win = windowed(full);
	const cutoff = dashboardRunsWindowStart(NOW);
	// Paging Previous past the bound used to hand back an empty month.
	const monthStart = new Date(Date.UTC(2024, 6, 1));
	const monthEnd = new Date(Date.UTC(2024, 7, 1)).getTime();
	assert.ok(monthStart.getTime() < cutoff.getTime(), 'fixture sanity: month predates the window');
	const inMonth = sourceRunsFor('month', monthStart, win, cutoff, full).filter((r) => {
		const t = new Date(r.started_at).getTime();
		return t >= monthStart.getTime() && t < monthEnd;
	});
	assert.ok(inMonth.length > 0, 'a month inside the runner history must not roll up empty');
});
