import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import {
	STRAVA_LOOKBACK_DEFAULT_DAYS,
	STRAVA_LOOKBACK_MAX_DAYS,
	STRAVA_LOOKBACK_OPTIONS,
	isStravaLookbackReachable,
	parseStravaSyncResult,
	parseImportCompleteness
} from './strava_sync_result';

test('a finished walk is the only shape that reports complete', () => {
	const r = parseStravaSyncResult({
		imported: 12,
		skipped: 3,
		failed: 1,
		rate_limited: false,
		complete: true,
	});
	assert.equal(r.complete, true);
	assert.equal(r.rateLimited, false);
	assert.deepEqual([r.imported, r.skipped, r.failed], [12, 3, 1]);
});

test('a throttled walk is partial and names the cause', () => {
	const r = parseStravaSyncResult({
		imported: 40,
		skipped: 0,
		failed: 0,
		rate_limited: true,
		complete: false,
	});
	assert.equal(r.complete, false);
	assert.equal(r.rateLimited, true);
	assert.equal(r.imported, 40);
});

test('the other truncation causes are partial without a named cause', () => {
	// An upstream error, a malformed page and the 20-page cap all return
	// `rate_limited: false, complete: false`. Before `complete` existed they
	// were indistinguishable from a finished sync, which is the whole bug.
	const r = parseStravaSyncResult({
		imported: 1000,
		skipped: 0,
		failed: 0,
		rate_limited: false,
		complete: false,
	});
	assert.equal(r.complete, false);
	assert.equal(r.rateLimited, false);
});

test('an absent complete field reads as partial, not as finished', () => {
	// The fail-closed direction, and deliberately the opposite of
	// cloudExportShortfall's: a false "partial" costs one extra click, a
	// false "complete" costs the runs that aged out of the window.
	assert.equal(parseStravaSyncResult({ imported: 5, skipped: 0, failed: 0 }).complete, false);
	assert.equal(parseStravaSyncResult({}).complete, false);
});

test('a complete field that is not the boolean true does not earn completeness', () => {
	for (const value of ['true', 1, {}, [], null, 'yes']) {
		assert.equal(
			parseStravaSyncResult({ complete: value }).complete,
			false,
			`complete: ${JSON.stringify(value)} must not read as finished`,
		);
	}
});

test('rate_limited must be the boolean true to claim a throttle', () => {
	for (const value of ['true', 1, {}, null]) {
		assert.equal(parseStravaSyncResult({ rate_limited: value }).rateLimited, false);
	}
});

test('an unrecognised payload zeroes the counts and reports partial', () => {
	for (const payload of [null, undefined, 'ok', 42, [], [{ imported: 9 }]]) {
		const r = parseStravaSyncResult(payload);
		assert.deepEqual(
			[
				r.imported,
				r.skipped,
				r.failed,
				r.rateLimited,
				r.complete,
				r.resumable,
				r.athleteId,
				r.error,
			],
			[0, 0, 0, false, false, false, null, null],
			`payload ${JSON.stringify(payload)} must not read as a sync`,
		);
	}
});

test('only a non-negative integer is a count', () => {
	const r = parseStravaSyncResult({
		imported: -3,
		skipped: 4.5,
		failed: '7',
		complete: true,
	});
	// A malformed count reads as 0 rather than as a number the toast would
	// then state as fact. Completeness is a separate claim and survives.
	assert.deepEqual([r.imported, r.skipped, r.failed], [0, 0, 0]);
	assert.equal(r.complete, true);
	assert.equal(parseStravaSyncResult({ imported: Number.NaN }).imported, 0);
	assert.equal(parseStravaSyncResult({ imported: Number.POSITIVE_INFINITY }).imported, 0);
	assert.equal(parseStravaSyncResult({ imported: 0 }).imported, 0);
});

test('a whole double is a count, as it is on the Dart twin', () => {
	// JSON has one number type: `Number.isInteger(12.0)` is true, so the Dart
	// side must not reject a `double` that happens to be whole.
	assert.equal(parseStravaSyncResult({ imported: 12.0 }).imported, 12);
});

test('an embedded error forces partial even when the body claims complete', () => {
	const r = parseStravaSyncResult({
		error: 'strava_not_connected',
		imported: 0,
		skipped: 0,
		failed: 0,
		complete: true,
	});
	assert.equal(r.error, 'strava_not_connected');
	assert.equal(r.complete, false);
});

test('a blank error is no error', () => {
	assert.equal(parseStravaSyncResult({ error: '   ', complete: true }).error, null);
	assert.equal(parseStravaSyncResult({ error: '   ', complete: true }).complete, true);
	assert.equal(parseStravaSyncResult({ error: 404 }).error, null);
});

test('athlete_id is carried through only as a non-empty string', () => {
	assert.equal(parseStravaSyncResult({ athlete_id: '12345' }).athleteId, '12345');
	assert.equal(parseStravaSyncResult({ athlete_id: '' }).athleteId, null);
	assert.equal(parseStravaSyncResult({ athlete_id: 12345 }).athleteId, null);
	assert.equal(parseStravaSyncResult({}).athleteId, null);
});

test('resumable must be the boolean true to claim a resume point', () => {
	// Same fail-closed direction as `complete`: telling a runner "sync again to
	// carry on" when nothing was recorded sends them back to a walk that will
	// restart from the beginning and stop in the same place.
	for (const value of ['true', 1, {}, null, undefined]) {
		assert.equal(parseStravaSyncResult({ resumable: value }).resumable, false);
	}
	assert.equal(parseStravaSyncResult({ resumable: true }).resumable, true);
});

test('a finished walk is never resumable, whatever the body says', () => {
	// A finished window subsumes any point inside it, and the function clears
	// the cursor when it reaches the end. A body claiming both is malformed;
	// resolving it here keeps every surface from having to.
	const r = parseStravaSyncResult({ complete: true, resumable: true });
	assert.equal(r.complete, true);
	assert.equal(r.resumable, false);
});

test('an embedded error leaves a resume point readable', () => {
	// `complete` is forced false by an error, and that must not drag the
	// resume point down with it: a walk that recorded one still has it.
	const r = parseStravaSyncResult({ error: 'partial', complete: true, resumable: true });
	assert.equal(r.complete, false);
	assert.equal(r.resumable, true);
});

test('the lookback options are ascending, start at the default and end at the max', () => {
	assert.equal(STRAVA_LOOKBACK_OPTIONS[0], STRAVA_LOOKBACK_DEFAULT_DAYS);
	assert.equal(STRAVA_LOOKBACK_OPTIONS.at(-1), STRAVA_LOOKBACK_MAX_DAYS);
	for (let i = 1; i < STRAVA_LOOKBACK_OPTIONS.length; i++) {
		assert.ok(STRAVA_LOOKBACK_OPTIONS[i] > STRAVA_LOOKBACK_OPTIONS[i - 1]);
	}
	assert.ok(STRAVA_LOOKBACK_OPTIONS.every((d) => isStravaLookbackReachable(d)));
	assert.equal(isStravaLookbackReachable(STRAVA_LOOKBACK_MAX_DAYS + 1), false);
	assert.equal(isStravaLookbackReachable(0), false);
	assert.equal(isStravaLookbackReachable(Number.NaN), false);
});

test('the maximum is the bound the Edge Function actually enforces', () => {
	// A third rail like `nearby`'s: the function answers 400
	// `invalid_lookback_days` above its own bound, so a client offering a
	// wider window would hand the runner a refusal naming neither number.
	const src = readFileSync(
		new URL('../../../../backend/supabase/functions/strava-import/index.ts', import.meta.url),
		'utf8',
	);
	const bound = src.match(/requested > (\d+)/)?.[1];
	assert.ok(bound, 'strava-import no longer bounds `lookbackDays` with `requested > <n>`');
	assert.equal(Number(bound), STRAVA_LOOKBACK_MAX_DAYS);
});

// parseImportCompleteness — the two scraper importers. Mirrored, case for
// case, by `packages/core_models/test/strava_sync_result_test.dart`.

test('a body this build cannot read is partial, never complete', () => {
	for (const body of [null, undefined, 'ok', 42, [], { imported: 3 }]) {
		const r = parseImportCompleteness(body);
		assert.equal(r.complete, false, JSON.stringify(body) ?? 'undefined');
	}
});

test('only an explicit true claims the import was whole', () => {
	assert.equal(parseImportCompleteness({ complete: true }).complete, true);
	for (const v of [false, 'true', 1, null, undefined]) {
		assert.equal(parseImportCompleteness({ complete: v }).complete, false, String(v));
	}
});

test('an embedded error forces partial beside a complete flag', () => {
	// The function answered about a walk it did not finish; the same rule
	// parseStravaSyncResult applies.
	assert.equal(parseImportCompleteness({ complete: true, error: 'upstream 502' }).complete, false);
	// A blank error is not an error.
	assert.equal(parseImportCompleteness({ complete: true, error: '  ' }).complete, true);
});

test('counts are non-negative integers or zero', () => {
	const r = parseImportCompleteness({ imported: 12, skipped: 3, complete: true });
	assert.equal(r.imported, 12);
	assert.equal(r.skipped, 3);
	for (const bad of [-1, 1.5, '4', null, undefined, NaN, Infinity]) {
		assert.equal(parseImportCompleteness({ imported: bad }).imported, 0, String(bad));
	}
});

test('total is carried when the function sent one', () => {
	assert.equal(parseImportCompleteness({ imported: 12, skipped: 8, total: 60 }).total, 60);
	// Absent means unknown, not zero — a caller must be able to tell
	// "12 of 60" from "12, and there may be more".
	assert.equal(parseImportCompleteness({ imported: 12 }).total, null);
	for (const bad of [-1, 2.5, '60', NaN, Infinity]) {
		assert.equal(parseImportCompleteness({ total: bad }).total, null, String(bad));
	}
});

test('a total below what was already processed is no total at all', () => {
	// "12 of 5" is worse than no denominator.
	assert.equal(parseImportCompleteness({ imported: 12, skipped: 0, total: 5 }).total, null);
	assert.equal(parseImportCompleteness({ imported: 12, skipped: 3, total: 15 }).total, 15);
	assert.equal(parseImportCompleteness({ imported: 12, skipped: 3, total: 14 }).total, null);
});
