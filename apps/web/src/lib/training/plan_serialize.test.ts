import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	planToMarkdown,
	planToJson,
	parsePlanMarkdown,
	parsePlanJson,
	type ExportPlan,
} from './plan_serialize';

const SAMPLE: ExportPlan = {
	name: 'Spring Marathon',
	goalEvent: 'distance_full',
	goalDistanceM: 42195,
	goalTimeSec: 3 * 3600 + 30 * 60,
	startDate: '2026-06-07',
	workouts: [
		{ week_index: 0, scheduled_date: '2026-06-07', kind: 'long', target_distance_m: 24_000, target_pace_sec_per_km: 330, notes: 'Easy long run' },
		{ week_index: 0, scheduled_date: '2026-06-08', kind: 'rest', target_distance_m: null, target_pace_sec_per_km: null, notes: null },
		{ week_index: 0, scheduled_date: '2026-06-09', kind: 'tempo', target_distance_m: 10_000, target_pace_sec_per_km: 270, notes: null },
		{ week_index: 1, scheduled_date: '2026-06-14', kind: 'long', target_distance_m: 27_000, target_pace_sec_per_km: 330, notes: null },
		{ week_index: 1, scheduled_date: '2026-06-16', kind: 'interval', target_distance_m: 8_000, target_pace_sec_per_km: 240, notes: '6x800' },
	],
};

function flatten(p: ReturnType<typeof parsePlanMarkdown>) {
	return p.generated.weeks.flatMap((w) =>
		w.workouts.map((wo) => ({
			week_index: w.week_index,
			scheduled_date: wo.scheduled_date,
			kind: wo.kind,
			target_distance_m: wo.target_distance_m,
			target_pace_sec_per_km: wo.target_pace_sec_per_km,
			notes: wo.notes,
		})),
	);
}

// ─────────────────────── Markdown round-trip ───────────────────────

test('planToMarkdown → parsePlanMarkdown round-trips the workouts', () => {
	const md = planToMarkdown(SAMPLE);
	const parsed = parsePlanMarkdown(md);
	assert.equal(parsed.name, SAMPLE.name);
	assert.equal(parsed.goalEvent, SAMPLE.goalEvent);
	assert.equal(parsed.goalDistanceM, SAMPLE.goalDistanceM);
	assert.equal(parsed.goalTimeSec, SAMPLE.goalTimeSec);
	assert.equal(parsed.startDate, SAMPLE.startDate);
	assert.deepEqual(flatten(parsed), SAMPLE.workouts);
});

test('planToMarkdown emits a header table + one row per workout', () => {
	const md = planToMarkdown(SAMPLE);
	assert.match(md, /^# Spring Marathon/);
	assert.match(md, /\| Week \| Date \| Type \| Distance \| Pace \| Notes \|/);
	const rows = md.split('\n').filter((l) => l.startsWith('| ') && !/Week \| Date/.test(l) && !/---/.test(l));
	assert.equal(rows.length, SAMPLE.workouts.length);
});

test('parsePlanMarkdown recomputes phase from week position', () => {
	const base = new Date('2026-06-07T00:00:00Z').getTime();
	const workouts = Array.from({ length: 6 }, (_, wk) => ({
		week_index: wk,
		scheduled_date: new Date(base + wk * 7 * 86_400_000).toISOString().slice(0, 10),
		kind: 'long' as const,
		target_distance_m: 20_000,
		target_pace_sec_per_km: 330,
		notes: null,
	}));
	const parsed = parsePlanMarkdown(planToMarkdown({ ...SAMPLE, workouts }));
	// phaseFor(0, 6) → base; the final week is always 'race'.
	assert.equal(parsed.generated.weeks[0].phase, 'base');
	assert.equal(parsed.generated.weeks[5].phase, 'race');
});

test('parsePlanMarkdown sums weekly volume from the workout distances', () => {
	const parsed = parsePlanMarkdown(planToMarkdown(SAMPLE));
	assert.equal(parsed.generated.weeks[0].target_volume_m, 24_000 + 10_000);
	assert.equal(parsed.generated.weeks[1].target_volume_m, 27_000 + 8_000);
});

test('parsePlanMarkdown accepts a hand-written table with mile distances', () => {
	const md = [
		'# Coach plan',
		'- Goal event: distance_10k',
		'- Start date: 2026-07-05',
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | long | 10 mi | 5:30 | |',
		'| 1 | 2026-07-07 | easy | 5 mi |  | recovery |',
	].join('\n');
	const parsed = parsePlanMarkdown(md);
	const flat = flatten(parsed);
	assert.equal(flat.length, 2);
	assert.ok(Math.abs(flat[0].target_distance_m! - 10 * 1609.344) < 0.01);
	assert.equal(flat[0].target_pace_sec_per_km, 330);
	assert.equal(flat[1].notes, 'recovery');
});

test('parsePlanMarkdown accepts a hand-written row that omits the trailing Notes column', () => {
	const md = [
		'# Coach plan',
		'| Week | Date | Type | Distance | Pace |',
		'| --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | easy | 5 km | 5:00 |',
	].join('\n');
	const parsed = parsePlanMarkdown(md);
	const flat = flatten(parsed);
	assert.equal(flat.length, 1, 'the notes-less row must not be silently dropped');
	assert.equal(flat[0].kind, 'easy');
	assert.equal(flat[0].notes, null);
});

test('fmtPaceCell / fmtHmsCell never emit a :60 seconds field for a fractional input', () => {
	// 359.6 s/km must format as 6:00, not 5:60 (which re-parses a minute off).
	const withFractionalPace = {
		...SAMPLE,
		workouts: [{ ...SAMPLE.workouts[0], target_pace_sec_per_km: 359.6 }],
	};
	const md = planToMarkdown(withFractionalPace);
	assert.ok(!/:60\b/.test(md), `markdown contained a :60 field:\n${md}`);
	const parsed = parsePlanMarkdown(md);
	assert.equal(flatten(parsed)[0].target_pace_sec_per_km, 360);
});

// ─────────────────────── error handling ───────────────────────

test('parsePlanMarkdown throws on an unknown workout kind', () => {
	const md = [
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | sprintz | 5 km | | |',
	].join('\n');
	assert.throws(() => parsePlanMarkdown(md), /Unknown workout type/);
});

test('parsePlanMarkdown throws on a malformed date', () => {
	const md = [
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 07/05/2026 | easy | 5 km | | |',
	].join('\n');
	assert.throws(() => parsePlanMarkdown(md), /Bad date/);
});

test('parsePlanMarkdown throws when there are no rows', () => {
	assert.throws(() => parsePlanMarkdown('# Just a title\n\nno table here'), /No workout rows/);
});

test('parsePlanMarkdown defaults goalEvent to custom + infers distance from longest run', () => {
	const md = [
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | long | 30 km | | |',
		'| 1 | 2026-07-07 | easy | 8 km | | |',
	].join('\n');
	const parsed = parsePlanMarkdown(md);
	assert.equal(parsed.goalEvent, 'custom');
	assert.equal(parsed.goalDistanceM, 30_000);
});

// ─────────────────────── JSON round-trip ───────────────────────

test('planToJson → parsePlanJson round-trips the workouts', () => {
	const parsed = parsePlanJson(planToJson(SAMPLE));
	assert.equal(parsed.name, SAMPLE.name);
	assert.equal(parsed.goalDistanceM, SAMPLE.goalDistanceM);
	assert.deepEqual(flatten(parsed), SAMPLE.workouts);
});

test('parsePlanJson throws on non-JSON + on missing workouts', () => {
	assert.throws(() => parsePlanJson('not json {'), /valid JSON/);
	assert.throws(() => parsePlanJson('{"name":"x"}'), /workouts array/);
});

test('notes with a pipe survive the round-trip (sanitized to a slash)', () => {
	const withPipe: ExportPlan = {
		...SAMPLE,
		workouts: [
			{ week_index: 0, scheduled_date: '2026-06-07', kind: 'easy', target_distance_m: 5000, target_pace_sec_per_km: null, notes: 'do 4x | strides' },
		],
	};
	const parsed = parsePlanMarkdown(planToMarkdown(withPipe));
	assert.equal(flatten(parsed)[0].notes, 'do 4x / strides');
});
