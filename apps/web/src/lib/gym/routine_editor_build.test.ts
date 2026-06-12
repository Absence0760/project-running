import { test } from 'node:test';
import assert from 'node:assert/strict';

import { assignSupersetGroups } from './routine_editor_build';

test('no flags → every exercise standalone', () => {
	const out = assignSupersetGroups([false, false, false]);
	assert.deepEqual(out, [
		{ supersetGroup: null, supersetOrder: null },
		{ supersetGroup: null, supersetOrder: null },
		{ supersetGroup: null, supersetOrder: null },
	]);
});

test('single flag brackets a pair into one group, ordered 0 then 1', () => {
	const out = assignSupersetGroups([true, false]);
	assert.deepEqual(out, [
		{ supersetGroup: 1, supersetOrder: 0 },
		{ supersetGroup: 1, supersetOrder: 1 },
	]);
});

test('a run of flags forms one longer group', () => {
	const out = assignSupersetGroups([true, true, false]);
	assert.deepEqual(out, [
		{ supersetGroup: 1, supersetOrder: 0 },
		{ supersetGroup: 1, supersetOrder: 1 },
		{ supersetGroup: 1, supersetOrder: 2 },
	]);
});

test('overlapping flags merge into one continuous group', () => {
	// ex0 supersets ex1, ex2 supersets ex3, but ex1↔ex2 are adjacent and ex2 is
	// flagged, so the run never breaks — all four are one group (a circuit).
	const out = assignSupersetGroups([true, false, true, false]);
	assert.deepEqual(out, [
		{ supersetGroup: 1, supersetOrder: 0 },
		{ supersetGroup: 1, supersetOrder: 1 },
		{ supersetGroup: 1, supersetOrder: 2 },
		{ supersetGroup: 1, supersetOrder: 3 },
	]);
});

test('two supersets split by a standalone exercise get distinct group ids', () => {
	const out = assignSupersetGroups([true, false, false, false, true, false]);
	assert.deepEqual(out, [
		{ supersetGroup: 1, supersetOrder: 0 },
		{ supersetGroup: 1, supersetOrder: 1 },
		{ supersetGroup: null, supersetOrder: null },
		{ supersetGroup: null, supersetOrder: null },
		{ supersetGroup: 2, supersetOrder: 0 },
		{ supersetGroup: 2, supersetOrder: 1 },
	]);
});

test('a standalone exercise between two supersets stays ungrouped', () => {
	const out = assignSupersetGroups([true, false, false, true, false]);
	assert.deepEqual(out, [
		{ supersetGroup: 1, supersetOrder: 0 },
		{ supersetGroup: 1, supersetOrder: 1 },
		{ supersetGroup: null, supersetOrder: null },
		{ supersetGroup: 2, supersetOrder: 0 },
		{ supersetGroup: 2, supersetOrder: 1 },
	]);
});

test('a trailing flag is ignored (nothing follows to superset with)', () => {
	const out = assignSupersetGroups([false, true]);
	assert.deepEqual(out, [
		{ supersetGroup: null, supersetOrder: null },
		{ supersetGroup: null, supersetOrder: null },
	]);
});

test('group + order are both-null or both-set (superset_chk invariant)', () => {
	for (const a of assignSupersetGroups([true, false, false, true, true, false])) {
		assert.equal(a.supersetGroup === null, a.supersetOrder === null);
	}
});

test('empty input yields no assignments', () => {
	assert.deepEqual(assignSupersetGroups([]), []);
});
