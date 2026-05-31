import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	trimOrNull,
	normaliseRunMetadataFields,
	applyRunMetadataPatch,
	normalisePlanWorkoutNotes,
} from './data_normalise.js';

// ---------------------------------------------------------------------------
// trimOrNull — the JS `s?.trim() || null` mirror
// ---------------------------------------------------------------------------

test('trimOrNull: null stays null', () => {
	assert.equal(trimOrNull(null), null);
});

test('trimOrNull: undefined stays null', () => {
	assert.equal(trimOrNull(undefined), null);
});

test('trimOrNull: empty string collapses to null', () => {
	assert.equal(trimOrNull(''), null);
});

test('trimOrNull: whitespace-only collapses to null', () => {
	assert.equal(trimOrNull('   \t\n  '), null);
});

test('trimOrNull: content with edge whitespace is trimmed', () => {
	assert.equal(trimOrNull('  hello  '), 'hello');
});

test('trimOrNull: internal whitespace is preserved', () => {
	assert.equal(trimOrNull('  one   two  three  '), 'one   two  three');
});

test('trimOrNull: emoji-only round-trips intact', () => {
	assert.equal(trimOrNull('🏃'), '🏃');
});

test('trimOrNull: "0" stays "0" — guards against `|| null` truthiness trap', () => {
	// Web's original `s?.trim() || null` pattern would collapse "0" to
	// null in JS because "0" is *technically* truthy, BUT a naive port
	// to a language with different truthy semantics could regress this.
	// In JS the string "0" is truthy, so this assertion holds. Mirror
	// of the Dart-side `trimToNull` + `normaliseRunPhotoCaption` tests.
	assert.equal(trimOrNull('0'), '0');
});

// ---------------------------------------------------------------------------
// normaliseRunMetadataFields — used by updateRunMetadata
// ---------------------------------------------------------------------------

test('normaliseRunMetadataFields: empty input → empty output', () => {
	assert.deepEqual(normaliseRunMetadataFields({}), {});
});

test('normaliseRunMetadataFields: trims title + notes', () => {
	assert.deepEqual(
		normaliseRunMetadataFields({ title: '  Long run  ', notes: '  Easy pace  ' }),
		{ title: 'Long run', notes: 'Easy pace' },
	);
});

test('normaliseRunMetadataFields: drops keys that trim to empty', () => {
	// Critical contract — the dropped key is how a whitespace-only
	// edit clears the metadata bag entry instead of writing `""`.
	assert.deepEqual(
		normaliseRunMetadataFields({ title: '', notes: '   ' }),
		{},
	);
});

test('normaliseRunMetadataFields: ignores keys whose value is not a string', () => {
	// Defensive — if a future caller passes `undefined` for one half
	// of the patch, that half must not appear in the output.
	const out = normaliseRunMetadataFields({ title: 'kept', notes: undefined });
	assert.deepEqual(out, { title: 'kept' });
});

// ---------------------------------------------------------------------------
// applyRunMetadataPatch — the end-to-end metadata merge
// ---------------------------------------------------------------------------

const NOW = '2026-06-01T12:00:00.000Z';

test('applyRunMetadataPatch: writes title + notes onto an empty bag', () => {
	const next = applyRunMetadataPatch(null, { title: 'A', notes: 'B' }, NOW);
	assert.deepEqual(next, { title: 'A', notes: 'B', last_modified_at: NOW });
});

test('applyRunMetadataPatch: preserves unrelated keys', () => {
	const next = applyRunMetadataPatch(
		{ activity_type: 'run', strava_id: 12345 },
		{ title: 'A' },
		NOW,
	);
	assert.equal(next.activity_type, 'run');
	assert.equal(next.strava_id, 12345);
	assert.equal(next.title, 'A');
	assert.equal(next.last_modified_at, NOW);
});

test('applyRunMetadataPatch: empty patch field REMOVES the key (the bug fix)', () => {
	// Before this fix, clearing the notes field left `notes: ""`.
	// Now a whitespace-only edit removes the key entirely so
	// `metadata.notes !== undefined` checks work correctly.
	const next = applyRunMetadataPatch(
		{ title: 'Old', notes: 'Old notes' },
		{ title: 'New', notes: '   ' },
		NOW,
	);
	assert.equal(next.title, 'New');
	assert.equal(Object.prototype.hasOwnProperty.call(next, 'notes'), false,
		'notes key must be removed when the patch clears it');
});

test('applyRunMetadataPatch: empty patch field on an empty bag is a no-op', () => {
	const next = applyRunMetadataPatch({}, { notes: '' }, NOW);
	assert.equal(Object.prototype.hasOwnProperty.call(next, 'notes'), false);
});

test('applyRunMetadataPatch: always stamps last_modified_at', () => {
	const next = applyRunMetadataPatch({ title: 'x' }, {}, NOW);
	assert.equal(next.last_modified_at, NOW);
});

test('applyRunMetadataPatch: only the keys in fields are touched — '
	+ 'other metadata.title-style keys stay intact', () => {
	// Sanity-check the "drop key, re-add normalised" loop only
	// touches keys present in the patch.
	const next = applyRunMetadataPatch(
		{ title: 'Keep me', other_field: 'untouched' },
		{ notes: 'New' },
		NOW,
	);
	assert.equal(next.title, 'Keep me');
	assert.equal(next.other_field, 'untouched');
	assert.equal(next.notes, 'New');
});

// ---------------------------------------------------------------------------
// normalisePlanWorkoutNotes — used by updatePlanWorkout
// ---------------------------------------------------------------------------

test('normalisePlanWorkoutNotes: null stays null', () => {
	assert.equal(normalisePlanWorkoutNotes(null), null);
});

test('normalisePlanWorkoutNotes: undefined stays undefined '
	+ '(so it can be `omitted` from the patch)', () => {
	// Subtle: undefined means "the caller didn't intend to touch this
	// field"; null means "explicitly clear it". The helper must
	// preserve that distinction.
	assert.equal(normalisePlanWorkoutNotes(undefined), undefined);
});

test('normalisePlanWorkoutNotes: empty string → null (clear the column)', () => {
	assert.equal(normalisePlanWorkoutNotes(''), null);
});

test('normalisePlanWorkoutNotes: whitespace-only → null', () => {
	assert.equal(normalisePlanWorkoutNotes('   \n\t  '), null);
});

test('normalisePlanWorkoutNotes: content is trimmed but preserved', () => {
	assert.equal(normalisePlanWorkoutNotes('  Reps  '), 'Reps');
});
