import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { parseImportCompleteness } from './import_completeness';

// Mirrored, case for case, by
// `packages/core_models/test/import_completeness_test.dart`.

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

// The primitives this module exports are the ones `strava_sync_result.ts`
// grades its own counts with. A copy there would drift silently — nothing
// compares two modules on the same platform — so this pins that the sync
// parser still reads them from here rather than having grown its own.
test('the strava sync parser composes on these primitives, it does not copy them', () => {
	const src = readFileSync(
		new URL('./strava_sync_result.ts', import.meta.url),
		'utf8',
	);
	assert.match(
		src,
		/import \{[^}]*importResponseCount[^}]*importResponseText[^}]*\} from '\.\/import_completeness'/,
		'strava_sync_result.ts no longer imports the shared count/text primitives',
	);
	assert.doesNotMatch(
		src,
		/^function (count|text)\(/m,
		'strava_sync_result.ts has grown a private copy of a primitive this module owns',
	);
});
