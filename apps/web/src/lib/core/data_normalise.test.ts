import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	trimOrNull,
	normaliseRunMetadataFields,
	applyRunMetadataPatch,
	normalisePlanWorkoutNotes,
	readGlobalSegmentsScoredCount,
	shouldRescoreGlobalSegments,
	stampGlobalSegmentsScored,
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

// ---------------------------------------------------------------------------
// global-segments-scored stamp — the issue #333 idempotency guard that stops
// the run-detail catalogue backfill re-fetching 500 polylines + re-matching
// on every owner view.
// ---------------------------------------------------------------------------

test('readGlobalSegmentsScoredCount: absent key → null', () => {
	assert.equal(readGlobalSegmentsScoredCount(null), null);
	assert.equal(readGlobalSegmentsScoredCount(undefined), null);
	assert.equal(readGlobalSegmentsScoredCount({}), null);
	assert.equal(readGlobalSegmentsScoredCount({ title: 'x' }), null);
});

test('readGlobalSegmentsScoredCount: malformed value → null (fails open)', () => {
	assert.equal(readGlobalSegmentsScoredCount({ global_segments_scored_count: 'nope' }), null);
	assert.equal(readGlobalSegmentsScoredCount({ global_segments_scored_count: -1 }), null);
	assert.equal(readGlobalSegmentsScoredCount({ global_segments_scored_count: Number.NaN }), null);
	assert.equal(readGlobalSegmentsScoredCount({ global_segments_scored_count: null }), null);
});

test('readGlobalSegmentsScoredCount: well-formed value parses (0 is valid)', () => {
	assert.equal(readGlobalSegmentsScoredCount({ global_segments_scored_count: 12 }), 12);
	assert.equal(readGlobalSegmentsScoredCount({ global_segments_scored_count: 0 }), 0);
});

test('shouldRescoreGlobalSegments: never-scored run → true', () => {
	assert.equal(shouldRescoreGlobalSegments(null, 12), true);
	assert.equal(shouldRescoreGlobalSegments({}, 12), true);
});

test('shouldRescoreGlobalSegments: SKIPS the expensive path when the run was '
	+ 'already scored against a catalogue at least this large', () => {
	// This is the regression guard: a scored run whose catalogue has not
	// grown must NOT re-fetch + re-match. Before the fix the function had
	// no stamp to read, so this was unconditionally re-scored every view.
	const meta = { global_segments_scored_count: 12 };
	assert.equal(shouldRescoreGlobalSegments(meta, 12), false);
	assert.equal(shouldRescoreGlobalSegments(meta, 5), false); // catalogue shrank
});

test('shouldRescoreGlobalSegments: re-scores when the catalogue grew', () => {
	assert.equal(shouldRescoreGlobalSegments({ global_segments_scored_count: 12 }, 13), true);
});

test('shouldRescoreGlobalSegments: unknown active count fails open to true', () => {
	const meta = { global_segments_scored_count: 12 };
	assert.equal(shouldRescoreGlobalSegments(meta, null), true);
	assert.equal(shouldRescoreGlobalSegments(meta, undefined), true);
});

test('stampGlobalSegmentsScored: writes the stamp without clobbering the bag', () => {
	const next = stampGlobalSegmentsScored({ title: 'Morning run', notes: 'felt great' }, 12);
	assert.equal(next.title, 'Morning run');
	assert.equal(next.notes, 'felt great');
	assert.equal(next.global_segments_scored_count, 12);
});

test('stampGlobalSegmentsScored: round-trips through the reader as not-needing-rescore', () => {
	const next = stampGlobalSegmentsScored(null, 8);
	assert.equal(shouldRescoreGlobalSegments(next, 8), false);
});
