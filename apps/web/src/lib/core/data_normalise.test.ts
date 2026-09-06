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
	GLOBAL_SEGMENT_SCORING_LIMIT,
	singleEmbed,
	fitnessSnapshotDue,
	publicRouteListFill,
} from './data_normalise.js';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { stripComments } from './strip_comments.js';

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

test('shouldRescoreGlobalSegments: a saturated stamp is NOT re-scored forever '
	+ 'once the active catalogue outgrows the fetch limit', () => {
	// The gate compares an UNCAPPED count(*) of the active catalogue
	// against a stamp written from a fetch capped at
	// GLOBAL_SEGMENT_SCORING_LIMIT. Without the clamp, a catalogue of 520
	// makes `520 > 500` permanently true, so every run re-fetches 500
	// polylines + re-runs the haversine match on EVERY view forever —
	// a net pessimisation vs not gating at all. Pin the exact case.
	const saturated = { global_segments_scored_count: GLOBAL_SEGMENT_SCORING_LIMIT };
	assert.equal(shouldRescoreGlobalSegments(saturated, 520), false);
	assert.equal(shouldRescoreGlobalSegments(saturated, 900), false);
	assert.equal(shouldRescoreGlobalSegments(saturated, 5_000), false);
});

test('shouldRescoreGlobalSegments: boundary cases around the fetch limit', () => {
	// 499 / 500 / 501 against a 500-row stamp — the transition the drift
	// bug turned into a cliff.
	const saturated = { global_segments_scored_count: 500 };
	assert.equal(GLOBAL_SEGMENT_SCORING_LIMIT, 500, 'boundary cases below assume a 500-row cap');
	assert.equal(shouldRescoreGlobalSegments(saturated, 499), false);
	assert.equal(shouldRescoreGlobalSegments(saturated, 500), false);
	assert.equal(shouldRescoreGlobalSegments(saturated, 501), false);
	// Below the cap the stamp still tracks real growth — clamping must
	// not blunt the case the gate exists for.
	const partial = { global_segments_scored_count: 499 };
	assert.equal(shouldRescoreGlobalSegments(partial, 499), false);
	assert.equal(shouldRescoreGlobalSegments(partial, 500), true);
	assert.equal(shouldRescoreGlobalSegments(partial, 501), true);
});

test('shouldRescoreGlobalSegments: clamps against the caller-supplied limit', () => {
	// The limit is a parameter so the gate and the fetch call site read
	// the same number; pin that a different cap moves the clamp with it.
	const meta = { global_segments_scored_count: 10 };
	assert.equal(shouldRescoreGlobalSegments(meta, 50, 10), false);
	assert.equal(shouldRescoreGlobalSegments(meta, 50, 11), true);
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

// `runs.metadata` is a whole-column jsonb write, and the scoring pass that
// sits between the gate's read and the stamp's write takes seconds (a
// catalogue fetch + a haversine pass over every polyline). Model that window
// against a shared row so the data-loss contract is behavioural, not prose:
// merging into the bag read BEFORE the pass reverts anything the owner
// changed during it; merging into a bag re-read immediately before the write
// does not. `computeGlobalSegmentEffortsForRun` must do the latter — pinned
// structurally in data.test.ts.
function stampRun(
	store: { metadata: Record<string, unknown> },
	bagToMergeInto: Record<string, unknown> | null,
	catalogueCount: number,
): void {
	store.metadata = stampGlobalSegmentsScored(bagToMergeInto, catalogueCount);
}

test('stampGlobalSegmentsScored: merging a bag re-read before the write keeps a '
	+ 'concurrent title/notes edit', () => {
	const store = { metadata: { title: 'Morning run' } as Record<string, unknown> };

	// t0 — the gate reads the bag, then the expensive scoring pass starts.
	const gateRead = { ...store.metadata };

	// t1 — mid-pass, the owner renames the run from the edit dialog.
	store.metadata = { ...store.metadata, title: 'Tempo 8k', notes: 'negative split' };

	// t2 — the stamp write. Re-reading here merges onto the owner's edit.
	stampRun(store, { ...store.metadata }, 12);

	assert.equal(store.metadata.title, 'Tempo 8k', 'the concurrent rename must survive the stamp');
	assert.equal(store.metadata.notes, 'negative split');
	assert.equal(store.metadata.global_segments_scored_count, 12);
	// Sanity: the stale bag is genuinely different, so the assertion above
	// is not passing by accident.
	assert.equal(gateRead.title, 'Morning run');
});

test('stampGlobalSegmentsScored: merging the STALE pre-pass bag silently reverts '
	+ 'the concurrent edit (the bug this ordering exists to prevent)', () => {
	const store = { metadata: { title: 'Morning run' } as Record<string, unknown> };
	const gateRead = { ...store.metadata };
	store.metadata = { ...store.metadata, title: 'Tempo 8k', notes: 'negative split' };

	stampRun(store, gateRead, 12);

	assert.equal(store.metadata.title, 'Morning run', 'stale merge reverts the rename — data loss');
	assert.equal(store.metadata.notes, undefined, 'stale merge drops the notes the owner added');
});

// -------------------------------------------------------------------
// singleEmbed — one shape for a PostgREST to-one embed
// -------------------------------------------------------------------

test('singleEmbed collapses both shapes PostgREST can return for a to-one embed', () => {
	// Reason: the same `events → clubs(slug)` embed comes back as an object or
	// as a one-element array depending on the FK metadata PostgREST detects.
	// Three sites in data.ts normalised it and the fourth read `.slug` off the
	// raw value, so an array shape would have produced `club_slug: undefined`
	// under a type declaring `string`.
	assert.deepEqual(singleEmbed({ slug: 'harriers' }), { slug: 'harriers' });
	assert.deepEqual(singleEmbed([{ slug: 'harriers' }]), { slug: 'harriers' });
	assert.deepEqual(singleEmbed([{ slug: 'a' }, { slug: 'b' }]), { slug: 'a' });
});

test('singleEmbed answers null for every shape that carries no related row', () => {
	// Reason: an empty array and a null embed mean the same thing, and a caller
	// that treats one as a row gets `undefined` where it expected a value. The
	// caller decides whether that is a skip or a fallback — this returns null
	// for all three so there is only one case to decide about.
	assert.equal(singleEmbed([]), null);
	assert.equal(singleEmbed(null), null);
	assert.equal(singleEmbed(undefined), null);
});

test('no data.ts reader hand-rolls the to-one embed collapse', () => {
	// Reason: the four sites drifted precisely because each spelled the ternary
	// itself — three got it right and fetchNextRsvpedEvent did not, and nothing
	// could see the difference. A restated `Array.isArray(x) ? x[0] : x` is the
	// drift returning.
	const source = stripComments(
		readFileSync(resolve('src/lib/core/data.ts'), 'utf-8'),
	);
	const offenders = [...source.matchAll(/Array\.isArray\((\w+(?:\.\w+)*)\)\s*\?[^;\n]*\[0\]/g)].map(
		(mm) => mm[0],
	);
	assert.deepEqual(
		offenders,
		[],
		`these reads must collapse a to-one embed through singleEmbed:\n  ${offenders.join('\n  ')}`,
	);
});

test('the run track and HR sidecar uploads address the Storage bucket registry, not the table one', () => {
	// Reason: `saveRun`'s two uploads read `supabase.storage.from(TABLES.runs)`
	// while every other Storage call in the file uses `BUCKETS.runs`. The two
	// registries hold the same string today, which is exactly why the mistake
	// was invisible: renaming either one would silently send a runner's GPS
	// trace to a bucket that does not exist, and the upload failure path is a
	// console.warn.
	const source = stripComments(
		readFileSync(resolve('src/lib/core/data.ts'), 'utf-8'),
	);
	const storageReads = [...source.matchAll(/storage\s*\n?\s*\.from\((\w+)\./g)].map(
		(mm) => mm[1],
	);
	assert.ok(storageReads.length >= 10, 'expected the Storage call sites to be found');
	assert.deepEqual(
		[...new Set(storageReads)],
		['BUCKETS'],
		'every supabase.storage.from(...) must name the BUCKETS registry',
	);
});

// -------------------------------------------------------------------
// fitnessSnapshotDue — at most one snapshot per user per UTC day
// -------------------------------------------------------------------

test('a runner with no snapshot yet is owed one', () => {
	assert.equal(fitnessSnapshotDue(null, new Date('2026-03-14T10:00:00Z')), true);
	assert.equal(fitnessSnapshotDue(undefined, new Date('2026-03-14T10:00:00Z')), true);
});

test('a second dashboard mount on the same UTC day is not owed a snapshot', () => {
	// Reason: /dashboard recomputes on every mount and used to persist every
	// time. fetchFitnessSnapshots windows at 60 points, so three or four opens
	// a day fill the whole trend chart with one fortnight of duplicates and the
	// multi-month trend the chart exists for scrolls off.
	const now = new Date('2026-03-14T23:59:00Z');
	assert.equal(fitnessSnapshotDue('2026-03-14T00:00:01Z', now), false);
	assert.equal(fitnessSnapshotDue('2026-03-14T12:30:00Z', now), false);
});

test('the answer does not depend on the zone the reader happens to be in', () => {
	// Reason: the previous assertion is only DISCRIMINATING off UTC — on a UTC
	// runner (which CI is) a local-day implementation gives the same answers
	// and the guard passes over the bug. Sweep the zone instead: the boundary
	// is a property of the constraint this pairs with, not of the reader, so
	// every zone must agree. Node re-reads `process.env.TZ` per Date operation.
	const original = process.env.TZ;
	try {
		const cases: [string | null, string, boolean][] = [
			['2026-03-14T23:30:00Z', '2026-03-15T00:30:00Z', true],
			['2026-03-14T23:30:00Z', '2026-03-14T23:59:59Z', false],
			['2026-03-14T00:00:01Z', '2026-03-14T23:59:00Z', false],
			['2026-03-14T12:00:00Z', '2026-03-15T11:00:00Z', true],
		];
		for (const zone of ['UTC', 'Pacific/Auckland', 'America/Los_Angeles', 'Asia/Kolkata']) {
			process.env.TZ = zone;
			for (const [latest, now, expected] of cases) {
				assert.equal(
					fitnessSnapshotDue(latest, new Date(now)),
					expected,
					`${zone}: latest=${latest} now=${now} should be ${expected}`,
				);
			}
		}
	} finally {
		if (original === undefined) delete process.env.TZ;
		else process.env.TZ = original;
	}
});

test('the day boundary is UTC, not the reader local one', () => {
	// Reason: the uniqueness this pairs with is a database constraint over
	// `computed_at`, and a `date` cast there runs in the connection time zone —
	// UTC for PostgREST. A client measuring local days would ask for a second
	// row on the same database day (absorbed, but a pointless round trip) or
	// skip a genuinely new one, depending on which side of midnight it sits.
	// 23:30 UTC on the 14th and 00:30 UTC on the 15th are different UTC days
	// however far the reader is from Greenwich.
	assert.equal(
		fitnessSnapshotDue('2026-03-14T23:30:00Z', new Date('2026-03-15T00:30:00Z')),
		true,
	);
	assert.equal(
		fitnessSnapshotDue('2026-03-14T23:30:00Z', new Date('2026-03-14T23:59:59Z')),
		false,
	);
});

test('yesterday, last month and last year each owe a new snapshot', () => {
	const now = new Date('2026-03-01T09:00:00Z');
	assert.equal(fitnessSnapshotDue('2026-02-28T09:00:00Z', now), true);
	assert.equal(fitnessSnapshotDue('2025-03-01T09:00:00Z', now), true);
	assert.equal(fitnessSnapshotDue('2026-04-01T09:00:00Z', now), true);
});

test('an unreadable timestamp fails closed — no snapshot is written', () => {
	// Reason: the two mistakes are not symmetric. Skipping a write loses one
	// day point from a chart that self-heals tomorrow; writing when we cannot
	// tell is the duplicate spam the gate exists to stop.
	const now = new Date('2026-03-14T10:00:00Z');
	assert.equal(fitnessSnapshotDue('not a timestamp', now), false);
	assert.equal(fitnessSnapshotDue('', now), false);
	assert.equal(fitnessSnapshotDue('2026-03-14T10:00:00Z', new Date(NaN)), false);
});

test('the fitness-snapshot write is gated on the per-day check and reports its own failure', () => {
	// Reason: the write ran on every /dashboard mount with its `{ error }`
	// unbound — a PostgREST error resolves rather than throws, so the caller's
	// `.catch(() => {})` could never fire and a failing write was invisible.
	// The gate must sit between the sufficiency check and the insert, and the
	// insert must absorb only the duplicate a race with another tab produces
	// once fitness_snapshots_user_day_uniq exists.
	const source = stripComments(
		readFileSync(resolve('src/lib/core/data.ts'), 'utf-8'),
	);
	const start = source.indexOf('export async function insertFitnessSnapshot(');
	assert.ok(start > 0, 'insertFitnessSnapshot moved — re-anchor this guard');
	const body = source.slice(start, source.indexOf('\nexport ', start + 1));
	const gate = body.indexOf('fitnessSnapshotDue(');
	const insert = body.indexOf('.insert({');
	assert.ok(gate > 0, 'the write must be gated on fitnessSnapshotDue');
	assert.ok(insert > gate, 'the per-day gate must run before the insert, not after');
	assert.match(
		body,
		/const \{ error \} = await supabase/,
		"the insert's error must be bound — an unbound one is invisible to every caller",
	);
	assert.doesNotMatch(
		body,
		/\.upsert\(/,
		'fitness_snapshots has no UPDATE policy, so ON CONFLICT DO UPDATE is refused by RLS',
	);
});

// -------------------------------------------------------------------
// publicRouteListFill — the narrow public_routes row is filled, not cast
// -------------------------------------------------------------------

test('every column the public_routes half cannot serve is filled with what it means', () => {
	// Reason: the requirement is DERIVED from the two column lists the reads
	// actually use, so widening ROUTE_LIST_COLS without teaching the public
	// half about the new column fails here rather than silently producing rows
	// missing a field under a type that promises it. That is exactly how
	// `waypoints` came to be `undefined` on every route saved from Explore.
	const source = readFileSync(resolve('src/lib/core/data.ts'), 'utf-8');
	const listOf = (name: string): string[] => {
		const m = source.match(new RegExp(`const ${name}\\s*=\\s*\\n?\\s*'([^']*)'`));
		assert.ok(m, `Could not locate ${name} — rename?`);
		return m![1].split(',').map((c) => c.trim());
	};
	const owned = listOf('ROUTE_LIST_COLS');
	const publicCols = new Set(listOf('PUBLIC_ROUTE_LIST_COLS'));
	const withheld = owned.filter((c) => !publicCols.has(c));
	assert.ok(withheld.length > 0, 'the two lists differ — that is the point of the fill');
	const fill = publicRouteListFill() as Record<string, unknown>;
	const unfilled = withheld.filter((c) => !(c in fill));
	assert.deepEqual(
		unfilled,
		[],
		`public_routes cannot serve these and the fill does not supply them: ${unfilled.join(', ')}`,
	);
});

test('an empty waypoints array is the withheld-line signal, not an absent field', () => {
	// Reason: RouteTrackPreview treats `waypoints.length < 2` as "ask
	// clip_route_for_viewer for this viewer's clipped line" — the same path
	// the RouteExplorer cards take. `undefined` is not that signal; it is a
	// field the type says cannot be missing, and a consumer reading `.length`
	// off it throws.
	const fill = publicRouteListFill();
	assert.deepEqual(fill.waypoints, []);
	assert.equal(Array.isArray(fill.waypoints), true);
	// A fresh array per call — a shared one would be mutated across rows.
	assert.notEqual(publicRouteListFill().waypoints, fill.waypoints);
	// The star is the owner's flag, and every row from this view is somebody
	// else's, so false is the truth rather than a placeholder.
	assert.equal(fill.is_starred, false);
});

test('the saved-public route rows are filled before they are treated as routes', () => {
	// Reason: the defect was the `as unknown as Route[]` on the public half —
	// a cast asserting a shape the select cannot produce. Casting again, with
	// or without the fill, puts it back.
	const source = stripComments(
		readFileSync(resolve('src/lib/core/data.ts'), 'utf-8'),
	);
	const start = source.indexOf('export async function fetchRoutesWithError(');
	assert.ok(start > 0, 'fetchRoutesWithError moved — re-anchor this guard');
	const body = source.slice(start, source.indexOf('\nexport ', start + 1));
	assert.match(
		body,
		/savedPublicRes\.data[\s\S]{0,200}?publicRouteListFill\(\)/,
		'the public_routes rows must be filled, not asserted to be full Route rows',
	);
});
