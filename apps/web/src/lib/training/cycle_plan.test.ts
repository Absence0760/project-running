import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	daysBetweenIso,
	cycleDayInfo,
	trimesterForDate,
	cyclePlanWorkoutPatch,
	CYCLE_EASE_SCALE,
	PREGNANCY_VOLUME_SCALE,
	MIN_CYCLE_LENGTH_DAYS,
	MAX_CYCLE_LENGTH_DAYS
} from './cycle_plan';

// ─────────────────────── daysBetweenIso ───────────────────────

test('daysBetweenIso: forward, backward, zero', () => {
	assert.equal(daysBetweenIso('2026-06-01', '2026-06-08'), 7);
	assert.equal(daysBetweenIso('2026-06-08', '2026-06-01'), -7);
	assert.equal(daysBetweenIso('2026-06-01', '2026-06-01'), 0);
});

test('daysBetweenIso: crosses month + year boundaries', () => {
	assert.equal(daysBetweenIso('2026-06-28', '2026-07-03'), 5);
	assert.equal(daysBetweenIso('2026-12-30', '2027-01-02'), 3);
});

// ─────────────────────── cycleDayInfo ───────────────────────

test('cycleDayInfo: anchor day is menstrual day 0', () => {
	const info = cycleDayInfo('2026-06-01', 28, '2026-06-01');
	assert.equal(info?.dayInCycle, 0);
	assert.equal(info?.phase, 'menstrual');
	assert.equal(info?.isEaseDay, true);
});

test('cycleDayInfo: 28-day phase boundaries', () => {
	// menstrual days 0-4, follicular 5-11, ovulatory 13±1 = 12-14, luteal 15-27,
	// late-luteal (last 3) = 25-27.
	assert.equal(cycleDayInfo('2026-06-01', 28, '2026-06-06')?.phase, 'follicular'); // day 5
	assert.equal(cycleDayInfo('2026-06-01', 28, '2026-06-14')?.phase, 'ovulatory'); // day 13
	assert.equal(cycleDayInfo('2026-06-01', 28, '2026-06-20')?.phase, 'luteal'); // day 19
});

test('cycleDayInfo: late-luteal days are ease days, mid-luteal are not', () => {
	assert.equal(cycleDayInfo('2026-06-01', 28, '2026-06-20')?.isEaseDay, false); // day 19, mid-luteal
	assert.equal(cycleDayInfo('2026-06-01', 28, '2026-06-27')?.isEaseDay, true); // day 26, late-luteal
});

test('cycleDayInfo: wraps into the next cycle', () => {
	// day 30 of a 28-day cycle → dayInCycle 2 → menstrual.
	const info = cycleDayInfo('2026-06-01', 28, '2026-07-01');
	assert.equal(info?.dayInCycle, 2);
	assert.equal(info?.phase, 'menstrual');
});

test('cycleDayInfo: handles a date before the anchor', () => {
	// -1 day wraps to day 27 of a 28-day cycle.
	assert.equal(cycleDayInfo('2026-06-01', 28, '2026-05-31')?.dayInCycle, 27);
});

test('cycleDayInfo: short 21-day cycle keeps a valid ovulatory window', () => {
	// ovulation = 21-14 = 7 → ovulatory 6-8.
	assert.equal(cycleDayInfo('2026-06-01', 21, '2026-06-08')?.phase, 'ovulatory'); // day 7
	assert.equal(cycleDayInfo('2026-06-01', 21, '2026-06-19')?.isEaseDay, true); // day 18, late-luteal
});

test('cycleDayInfo: refuses out-of-band cycle lengths', () => {
	assert.equal(cycleDayInfo('2026-06-01', MIN_CYCLE_LENGTH_DAYS - 1, '2026-06-10'), null);
	assert.equal(cycleDayInfo('2026-06-01', MAX_CYCLE_LENGTH_DAYS + 1, '2026-06-10'), null);
	assert.equal(cycleDayInfo('2026-06-01', NaN, '2026-06-10'), null);
});

// ─────────────────────── trimesterForDate ───────────────────────

test('trimesterForDate: maps gestational age to trimesters', () => {
	// Due 2027-01-01. Full-term = 40wk. 39wk before due = ~week 1 → T1.
	assert.equal(trimesterForDate('2027-01-01', '2026-04-09'), 1); // ~week 1
	assert.equal(trimesterForDate('2027-01-01', '2026-08-01'), 2); // ~week 17
	assert.equal(trimesterForDate('2027-01-01', '2026-11-01'), 3); // ~week 30
});

test('trimesterForDate: near the due date is T3', () => {
	assert.equal(trimesterForDate('2027-01-01', '2026-12-25'), 3);
});

test('trimesterForDate: null before conception window', () => {
	// >40 weeks before the due date — not pregnant yet on that date.
	assert.equal(trimesterForDate('2027-01-01', '2026-01-01'), null);
});

test('trimesterForDate: null more than two weeks past due', () => {
	assert.equal(trimesterForDate('2027-01-01', '2027-02-01'), null);
});

// ─────────────────────── cyclePlanWorkoutPatch — cycle mode ───────────────────────

const CYCLE = { mode: 'cycle', cycleLengthDays: 28, lastPeriodStartIso: '2026-06-01' } as const;

test('cycle: leaves rest + race + non-ease days untouched', () => {
	assert.equal(
		cyclePlanWorkoutPatch({ kind: 'rest', target_distance_m: null, scheduled_date: '2026-06-01' }, CYCLE),
		null
	);
	assert.equal(
		cyclePlanWorkoutPatch({ kind: 'race', target_distance_m: 42_195, scheduled_date: '2026-06-01' }, CYCLE),
		null
	);
	// Follicular day (day 8) — not eased.
	assert.equal(
		cyclePlanWorkoutPatch({ kind: 'long', target_distance_m: 20_000, scheduled_date: '2026-06-09' }, CYCLE),
		null
	);
});

test('cycle: eases long-run volume on a menstrual day', () => {
	const patch = cyclePlanWorkoutPatch(
		{ kind: 'long', target_distance_m: 20_000, scheduled_date: '2026-06-02' },
		CYCLE
	);
	assert.equal(patch?.target_distance_m, Math.round(20_000 * CYCLE_EASE_SCALE));
	assert.equal(patch?.kind, undefined); // kind unchanged
});

test('cycle: quality session runs by feel on a late-luteal day', () => {
	const patch = cyclePlanWorkoutPatch(
		{ kind: 'interval', target_distance_m: 8000, scheduled_date: '2026-06-27' },
		CYCLE
	);
	assert.equal(patch?.target_pace_sec_per_km, null);
	assert.equal(patch?.target_pace_tolerance_sec, null);
	assert.equal(patch?.target_distance_m, Math.round(8000 * CYCLE_EASE_SCALE));
	assert.equal(patch?.kind, undefined); // still an interval, just by feel
});

test('cycle: distance-less easy day on an ease day yields no patch', () => {
	assert.equal(
		cyclePlanWorkoutPatch({ kind: 'easy', target_distance_m: null, scheduled_date: '2026-06-02' }, CYCLE),
		null
	);
});

// ─────────────────────── cyclePlanWorkoutPatch — pregnancy mode ───────────────────────

const PREG = { mode: 'pregnancy', dueDateIso: '2027-01-01' } as const;

test('pregnancy: strips a quality session to easy + tapers volume', () => {
	const patch = cyclePlanWorkoutPatch(
		{ kind: 'interval', target_distance_m: 8000, scheduled_date: '2026-11-01' }, // T3
		PREG
	);
	assert.equal(patch?.kind, 'easy');
	assert.equal(patch?.target_pace_sec_per_km, null);
	assert.equal(patch?.structure, null);
	assert.equal(patch?.target_distance_m, Math.round(8000 * PREGNANCY_VOLUME_SCALE[3]));
});

test('pregnancy: converts the goal race to an easy run', () => {
	const patch = cyclePlanWorkoutPatch(
		{ kind: 'race', target_distance_m: 21_097, scheduled_date: '2026-08-01' }, // T2
		PREG
	);
	assert.equal(patch?.kind, 'easy');
	assert.equal(patch?.target_distance_m, Math.round(21_097 * PREGNANCY_VOLUME_SCALE[2]));
});

test('pregnancy: tapers an easy run by trimester without changing its kind', () => {
	const patch = cyclePlanWorkoutPatch(
		{ kind: 'easy', target_distance_m: 10_000, scheduled_date: '2026-04-09' }, // T1
		PREG
	);
	assert.equal(patch?.kind, undefined);
	assert.equal(patch?.target_distance_m, Math.round(10_000 * PREGNANCY_VOLUME_SCALE[1]));
});

test('pregnancy: leaves weeks outside the pregnancy untouched', () => {
	assert.equal(
		cyclePlanWorkoutPatch({ kind: 'interval', target_distance_m: 8000, scheduled_date: '2026-01-01' }, PREG),
		null
	);
});

test('pregnancy: leaves rest untouched', () => {
	assert.equal(
		cyclePlanWorkoutPatch({ kind: 'rest', target_distance_m: null, scheduled_date: '2026-11-01' }, PREG),
		null
	);
});
