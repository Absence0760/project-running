import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	classifyImportFailure,
	groupImportFailures,
	importFailureReportCsv,
	MAX_RECORDED_IMPORT_FAILURES,
	newImportFailureLog,
	recordImportFailure,
} from './import_failures';

test('a dropped connection classifies as network, not unknown', () => {
	assert.equal(classifyImportFailure(new TypeError('Failed to fetch')).reason, 'network');
	assert.equal(classifyImportFailure(new Error('NetworkError when attempting to fetch')).reason, 'network');
	assert.equal(classifyImportFailure(new Error('Load failed')).reason, 'network');
});

test('an expired session classifies as auth', () => {
	assert.equal(classifyImportFailure(new Error('Not signed in')).reason, 'auth');
	assert.equal(classifyImportFailure(new Error('JWT expired')).reason, 'auth');
	assert.equal(classifyImportFailure({ status: 401, message: 'nope' }).reason, 'auth');
});

test('an invalid token reads as auth, not as unparseable', () => {
	assert.equal(classifyImportFailure(new Error('invalid token')).reason, 'auth');
});

test('rate limiting is recognised from status, trigger code, and prose', () => {
	assert.equal(classifyImportFailure({ status: 429, message: 'slow down' }).reason, 'rate_limited');
	assert.equal(
		classifyImportFailure({ code: 'P0001', message: 'rate limit exceeded for create_route, retry in 30s' })
			.reason,
		'rate_limited',
	);
	assert.equal(classifyImportFailure(new Error('Too Many Requests')).reason, 'rate_limited');
});

test('an oversized upload reads as too_large, not rejected', () => {
	assert.equal(classifyImportFailure({ status: 413, message: 'nope' }).reason, 'too_large');
	assert.equal(
		classifyImportFailure(new Error('The object exceeded the maximum allowed size')).reason,
		'too_large',
	);
});

test('a database refusal classifies as rejected', () => {
	assert.equal(classifyImportFailure({ code: '42501', message: 'denied' }).reason, 'rejected');
	assert.equal(classifyImportFailure({ code: '23505', message: 'duplicate key' }).reason, 'rejected');
	assert.equal(
		classifyImportFailure(new Error('new row violates row-level security policy')).reason,
		'rejected',
	);
});

test('a data-exception SQLSTATE reads as rejected, not as an unreadable file', () => {
	// 22P02 carries "invalid input syntax", which the unparseable message
	// pattern would otherwise claim — the server answered and refused.
	assert.equal(
		classifyImportFailure({ code: '22P02', message: 'invalid input syntax for type uuid' }).reason,
		'rejected',
	);
	assert.equal(
		classifyImportFailure({ code: 'PGRST204', message: "Could not find the column" }).reason,
		'rejected',
	);
});

test('a code never overrides the network / auth / size signals', () => {
	assert.equal(
		classifyImportFailure({ code: 'PGRST000', message: 'TypeError: Failed to fetch' }).reason,
		'network',
	);
	assert.equal(classifyImportFailure({ code: '42501', message: 'JWT expired' }).reason, 'auth');
});

test('a bad archive member classifies as unparseable', () => {
	assert.equal(
		classifyImportFailure(new Error('Unsupported file format: .bin. Use GPX, KML, KMZ, GeoJSON, or TCX.'))
			.reason,
		'unparseable',
	);
	assert.equal(classifyImportFailure(new Error('TCX file contains no track points')).reason, 'unparseable');
});

test('an unrecognised failure stays unknown rather than guessing', () => {
	assert.equal(classifyImportFailure(new Error('something went sideways')).reason, 'unknown');
	assert.equal(classifyImportFailure(null).reason, 'unknown');
	assert.equal(classifyImportFailure(undefined).reason, 'unknown');
	assert.equal(classifyImportFailure({}).reason, 'unknown');
});

test('detail carries code and message but never details or hint', () => {
	const { detail } = classifyImportFailure({
		code: '42501',
		message: 'new row violates row-level security policy for table "runs"',
		details: 'Failing row contains (uuid, 51.5074, -0.1278)',
		hint: 'check the policy on runs',
	});
	assert.match(detail, /^42501: new row violates/);
	assert.ok(!detail.includes('51.5074'));
	assert.ok(!detail.includes('check the policy'));
});

test('detail collapses whitespace and is bounded', () => {
	assert.equal(classifyImportFailure(new Error('a\n\tb   c')).detail, 'a b c');
	const long = classifyImportFailure(new Error('x'.repeat(500))).detail;
	assert.equal(long.length, 200);
	assert.ok(long.endsWith('…'));
});

test('a non-Error thrown value does not produce [object Object]', () => {
	assert.equal(classifyImportFailure({ foo: 'bar' }).detail, '');
	assert.equal(classifyImportFailure('plain string boom').detail, 'plain string boom');
});

test('recording a failure keeps the activity name and start', () => {
	const log = newImportFailureLog();
	recordImportFailure(log, { name: 'Morning Run', startedAt: '2026-03-01T07:00:00Z' }, new Error('Failed to fetch'));
	assert.equal(log.items.length, 1);
	assert.deepEqual(log.items[0], {
		name: 'Morning Run',
		startedAt: '2026-03-01T07:00:00Z',
		reason: 'network',
		detail: 'Failed to fetch',
	});
	assert.equal(log.truncated, 0);
});

test('a blank name falls back rather than rendering an empty row', () => {
	const log = newImportFailureLog();
	recordImportFailure(log, { name: '   ' }, new Error('boom'));
	assert.equal(log.items[0].name, 'Unnamed activity');
	assert.equal(log.items[0].startedAt, null);
});

test('the log caps retained failures and counts the overflow', () => {
	const log = newImportFailureLog();
	for (let i = 0; i < MAX_RECORDED_IMPORT_FAILURES + 17; i++) {
		recordImportFailure(log, { name: `Run ${i}` }, new Error('boom'));
	}
	assert.equal(log.items.length, MAX_RECORDED_IMPORT_FAILURES);
	assert.equal(log.truncated, 17);
});

test('grouping orders by count then reason', () => {
	const log = newImportFailureLog();
	recordImportFailure(log, { name: 'a' }, new Error('Failed to fetch'));
	recordImportFailure(log, { name: 'b' }, new Error('Failed to fetch'));
	recordImportFailure(log, { name: 'c' }, new Error('JWT expired'));
	recordImportFailure(log, { name: 'd' }, new Error('TCX file contains no track points'));
	assert.deepEqual(groupImportFailures(log), [
		{ reason: 'network', count: 2 },
		{ reason: 'auth', count: 1 },
		{ reason: 'unparseable', count: 1 },
	]);
});

test('grouping an empty log yields no rows', () => {
	assert.deepEqual(groupImportFailures(newImportFailureLog()), []);
});

test('the CSV report escapes embedded quotes and commas', () => {
	const log = newImportFailureLog();
	recordImportFailure(
		log,
		{ name: 'Hill "repeats", 8x400', startedAt: '2026-03-01T07:00:00Z' },
		new Error('Failed to fetch'),
	);
	const csv = importFailureReportCsv(log);
	const lines = csv.split('\n');
	assert.equal(lines[0], 'Activity,Started,Reason,Detail');
	assert.equal(lines[1], '"Hill ""repeats"", 8x400","2026-03-01T07:00:00Z","network","Failed to fetch"');
	assert.equal(lines.length, 2);
});

test('the CSV report states truncation rather than silently omitting', () => {
	const log = newImportFailureLog();
	for (let i = 0; i < MAX_RECORDED_IMPORT_FAILURES + 3; i++) {
		recordImportFailure(log, { name: `Run ${i}` }, new Error('boom'));
	}
	const lines = importFailureReportCsv(log).split('\n');
	assert.equal(lines.length, MAX_RECORDED_IMPORT_FAILURES + 2);
	assert.match(lines[lines.length - 1], /^"\(3 further failures not recorded\)","","truncated"/);
});

test('an empty log still produces a header-only report', () => {
	assert.equal(importFailureReportCsv(newImportFailureLog()), 'Activity,Started,Reason,Detail');
});
