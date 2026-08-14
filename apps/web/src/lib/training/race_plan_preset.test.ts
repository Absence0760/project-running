import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	RACE_PLAN_MIN_WEEKS,
	goalEventForDistance,
	racePlanPreset,
	type RacePlanPreset,
} from './race_plan_preset';
import { GOAL_DISTANCES_M, defaultPlanWeeks } from './training';

const TODAY = '2026-08-14'; // a Friday

function utcDay(iso: string): number {
	const [y, m, d] = iso.split('-').map(Number);
	return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
}

function ok(r: ReturnType<typeof racePlanPreset>): RacePlanPreset {
	assert.equal(r.ok, true, `expected a preset, got ${JSON.stringify(r)}`);
	return (r as { ok: true; preset: RacePlanPreset }).preset;
}

/// Every preset must start on a Sunday (the generator anchors day 0 of the
/// start week to the Sunday long run) and must place race day inside the
/// final — "race" — week.
function assertAnchoring(preset: RacePlanPreset, raceDateIso: string): void {
	const start = utcDay(preset.startDate);
	assert.equal((((start + 4) % 7) + 7) % 7, 0, `${preset.startDate} is not a Sunday`);
	const race = utcDay(raceDateIso);
	const raceWeekStart = start + (preset.weeks - 1) * 7;
	assert.ok(
		race >= raceWeekStart && race <= raceWeekStart + 6,
		`race ${raceDateIso} falls outside the final week of a ${preset.weeks}-week plan from ${preset.startDate}`,
	);
}

test('a half marathon far out gets the goal default week count, anchored on race week', () => {
	const preset = ok(
		racePlanPreset({ raceDateIso: '2026-11-15', distanceM: 21_097.5, todayIso: TODAY }),
	);
	assert.equal(preset.goalEvent, 'distance_half');
	assert.equal(preset.weeks, defaultPlanWeeks('distance_half'));
	assert.equal(preset.startDate, '2026-08-30');
	assertAnchoring(preset, '2026-11-15');
});

test('weeks are capped at the goal default rather than filling the whole gap', () => {
	// A marathon over half a year out: 16 weeks starting later, not a 30-week grind.
	const preset = ok(
		racePlanPreset({ raceDateIso: '2027-03-14', distanceM: 42_195, todayIso: TODAY }),
	);
	assert.equal(preset.goalEvent, 'distance_full');
	assert.equal(preset.weeks, defaultPlanWeeks('distance_full'));
	assert.equal(preset.startDate, '2026-11-29');
	assertAnchoring(preset, '2027-03-14');
});

test('a nearer race shortens the plan instead of starting in the past', () => {
	// Sunday 2026-10-11 is 8 race-weeks out from the first legal start.
	const preset = ok(
		racePlanPreset({ raceDateIso: '2026-10-11', distanceM: 21_097.5, todayIso: TODAY }),
	);
	assert.ok(preset.weeks < defaultPlanWeeks('distance_half'));
	assert.equal(preset.startDate, '2026-08-16'); // the first Sunday on/after today
	assertAnchoring(preset, '2026-10-11');
});

test('race day mid-week still lands inside the final race week', () => {
	// Wednesday. The race week starts on the Sunday *before* race day, so the
	// plan must not be sized to the Sunday after it.
	const preset = ok(
		racePlanPreset({ raceDateIso: '2026-11-11', distanceM: 10_000, todayIso: TODAY }),
	);
	assert.equal(preset.goalEvent, 'distance_10k');
	assertAnchoring(preset, '2026-11-11');
	// The Sunday before 2026-11-11 is 2026-11-08.
	assert.equal(
		utcDay(preset.startDate) + (preset.weeks - 1) * 7,
		utcDay('2026-11-08'),
	);
});

test('a Saturday race is anchored to the same week as the Sunday before it', () => {
	const sat = ok(racePlanPreset({ raceDateIso: '2026-11-14', distanceM: 5000, todayIso: TODAY }));
	const sun = ok(racePlanPreset({ raceDateIso: '2026-11-08', distanceM: 5000, todayIso: TODAY }));
	assert.equal(sat.startDate, sun.startDate);
	assertAnchoring(sat, '2026-11-14');
});

test('today may be the start date when today is a Sunday', () => {
	// Exactly defaultPlanWeeks('distance_5k') race-weeks out, so the cap
	// doesn't push the start later and the plan can begin today.
	const preset = ok(
		racePlanPreset({ raceDateIso: '2026-10-04', distanceM: 5000, todayIso: '2026-08-16' }),
	);
	assert.equal(preset.weeks, defaultPlanWeeks('distance_5k'));
	assert.equal(preset.startDate, '2026-08-16');
});

test('a past race, and a race today, are refused', () => {
	assert.deepEqual(racePlanPreset({ raceDateIso: '2026-08-13', todayIso: TODAY }), {
		ok: false,
		reason: 'past',
	});
	assert.deepEqual(racePlanPreset({ raceDateIso: TODAY, todayIso: TODAY }), {
		ok: false,
		reason: 'past',
	});
});

test('a race too close to build a plan for is refused, not squeezed', () => {
	// 2026-09-06 is the third Sunday from the first legal start — three weeks.
	assert.deepEqual(racePlanPreset({ raceDateIso: '2026-08-30', todayIso: TODAY }), {
		ok: false,
		reason: 'too_soon',
	});
	assert.deepEqual(racePlanPreset({ raceDateIso: '2026-08-18', todayIso: TODAY }), {
		ok: false,
		reason: 'too_soon',
	});
});

test('the minimum-week boundary is inclusive', () => {
	// The Sunday RACE_PLAN_MIN_WEEKS - 1 weeks after the first legal start
	// (2026-08-16) is the first race a plan may be built for.
	const firstOk = '2026-09-06';
	const preset = ok(racePlanPreset({ raceDateIso: firstOk, todayIso: TODAY }));
	assert.equal(preset.weeks, RACE_PLAN_MIN_WEEKS);
	assert.equal(preset.startDate, '2026-08-16');
	assert.deepEqual(racePlanPreset({ raceDateIso: '2026-08-30', todayIso: TODAY }), {
		ok: false,
		reason: 'too_soon',
	});
});

test('an unusable date is refused as invalid, never silently treated as past', () => {
	for (const bad of ['', 'tomorrow', '2026-13-01', '2026-02-31', '26-11-15', '2026-11-15T00:00']) {
		assert.deepEqual(
			racePlanPreset({ raceDateIso: bad, todayIso: TODAY }),
			{ ok: false, reason: 'invalid' },
			bad,
		);
	}
	assert.deepEqual(racePlanPreset({ raceDateIso: '2026-11-15', todayIso: 'nope' }), {
		ok: false,
		reason: 'invalid',
	});
});

test('a distance matching no standard rung claims no goal event', () => {
	// A 50k trail ultra: the wizard has no custom-distance input, so calling
	// this a marathon would train the runner for the wrong race.
	const preset = ok(racePlanPreset({ raceDateIso: '2027-03-14', distanceM: 50_000, todayIso: TODAY }));
	assert.equal(preset.goalEvent, null);
	assert.equal(preset.weeks, defaultPlanWeeks('custom'));
});

test('a listing with no distance still presets the dates', () => {
	const preset = ok(racePlanPreset({ raceDateIso: '2027-03-14', distanceM: null, todayIso: TODAY }));
	assert.equal(preset.goalEvent, null);
	assertAnchoring(preset, '2027-03-14');
});

test('goalEventForDistance tolerates rounded listings but not neighbouring rungs', () => {
	assert.equal(goalEventForDistance(21_100), 'distance_half');
	assert.equal(goalEventForDistance(42_200), 'distance_full');
	assert.equal(goalEventForDistance(5000), 'distance_5k');
	assert.equal(goalEventForDistance(10_000), 'distance_10k');
	// A 10-miler sits between rungs and gets neither.
	assert.equal(goalEventForDistance(16_093), null);
	for (const rung of Object.values(GOAL_DISTANCES_M)) {
		// 1.02 is the boundary itself and lands on either side of it under
		// binary rounding, so probe just inside and well outside instead.
		assert.equal(goalEventForDistance(rung * 1.019), goalEventForDistance(rung));
		assert.equal(goalEventForDistance(rung * 1.05), null);
	}
});

test('goalEventForDistance rejects absent and nonsense distances', () => {
	for (const bad of [null, undefined, 0, -5000, NaN, Infinity]) {
		assert.equal(goalEventForDistance(bad), null, String(bad));
	}
});

test('a window spanning a DST transition is still counted in whole weeks', () => {
	// Northern-hemisphere clocks change on 2026-11-01 (US) and 2026-10-25
	// (EU); both fall inside this window. A millisecond-difference count
	// would truncate a day short and shift the anchor by a week.
	const preset = ok(
		racePlanPreset({ raceDateIso: '2026-12-06', distanceM: 42_195, todayIso: '2026-08-14' }),
	);
	assert.equal(preset.weeks, defaultPlanWeeks('distance_full'));
	assertAnchoring(preset, '2026-12-06');
	assert.equal(preset.startDate, '2026-08-23');
});

test('the anchoring invariant holds for every weekday and a year of race dates', () => {
	const start = utcDay('2026-08-15');
	for (let offset = 0; offset < 400; offset++) {
		const iso = new Date((start + offset) * 86_400_000).toISOString().slice(0, 10);
		const r = racePlanPreset({ raceDateIso: iso, distanceM: 21_097.5, todayIso: TODAY });
		if (!r.ok) {
			assert.ok(r.reason === 'too_soon', `${iso}: ${r.reason}`);
			continue;
		}
		assertAnchoring(r.preset, iso);
		assert.ok(r.preset.weeks >= RACE_PLAN_MIN_WEEKS, iso);
		assert.ok(r.preset.weeks <= defaultPlanWeeks('distance_half'), iso);
		assert.ok(r.preset.startDate >= TODAY, `${iso} starts in the past`);
	}
});
