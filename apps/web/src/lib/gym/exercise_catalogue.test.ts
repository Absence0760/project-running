import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { normaliseExerciseName } from './gym_prs';
import { dedupeShadowedExercises } from './exercise_catalogue';

// Mutation-tested against the rule it describes: dropping the `author_id`
// precedence (keeping the first row under a key) fails the two shadow cases,
// and keeping the LAST row instead fails whichever of them the fetch order
// contradicts.

// `name_key` is stamped by `exercises_stamp_name_key` on every write and held
// canonical by a validated CHECK, so a fixture stamps it exactly as the trigger
// does. `stale` is the one row shape that cannot be built that way: it is what
// a row looks like between a client carrying a regenerated fold table and the
// migration that re-folds the column.
const global_ = (name: string) => ({
	id: name,
	name,
	name_key: normaliseExerciseName(name),
	author_id: null,
});
const custom = (name: string, id = `${name}-mine`) => ({
	id,
	name,
	name_key: normaliseExerciseName(name),
	author_id: 'me',
});
const stale = (name: string, name_key: string, id = `${name}-stale`) => ({
	id,
	name,
	name_key,
	author_id: 'me',
});

test('a catalogue with no shadow is returned unchanged', () => {
	const rows = [global_('Back Squat'), global_('Bench Press'), custom('Zercher Squat')];
	assert.deepEqual(dedupeShadowedExercises(rows), rows);
});

test("the owner's custom wins over the global it shadows, whichever came first", () => {
	const g = global_('Bench Press');
	const c = custom('Bench Press');
	assert.deepEqual(dedupeShadowedExercises([g, c]), [c]);
	assert.deepEqual(dedupeShadowedExercises([c, g]), [c]);
});

test('the surviving row keeps the position of the first row under its key', () => {
	// The read orders by (name, id) before this runs, so a dedupe that appended
	// the winner would move a shadowed exercise to the end of an ordered list.
	const rows = [global_('Ab Wheel'), global_('Bench Press'), custom('Bench Press'), global_('Curl')];
	assert.deepEqual(
		dedupeShadowedExercises(rows).map((e) => e.name),
		['Ab Wheel', 'Bench Press', 'Curl'],
	);
	assert.equal(dedupeShadowedExercises(rows)[1].author_id, 'me');
});

test('the key is the canonical exercise key, not the display spelling', () => {
	// U+00A0 is in the shared whitespace class the key collapses, so these two
	// rows ARE one exercise — they bind to the same PRs and the same routine
	// rows. Deduping on the display spelling would leave both, and the picker
	// would then file them in two different places in its list, because
	// `compareFoldedNames` does not collapse that character.
	const g = global_('Bench Press');
	const c = custom('Bench\u00A0Press');
	assert.deepEqual(dedupeShadowedExercises([g, c]), [c]);
});

test('a case-only difference is one exercise too', () => {
	const g = global_('Bench Press');
	const c = custom('bench press');
	assert.deepEqual(dedupeShadowedExercises([g, c]), [c]);
});

test('two globals under one key cannot both survive', () => {
	// The partial unique forbids this pair, so it is unreachable from the
	// database — pinned so the reducer is total rather than only correct on the
	// shapes the schema currently allows.
	const key = normaliseExerciseName('Bench Press');
	const a = { id: 'a', name: 'Bench Press', name_key: key, author_id: null };
	const b = { id: 'b', name: 'bench  press', name_key: key, author_id: null };
	assert.deepEqual(dedupeShadowedExercises([a, b]), [a]);
});

test('an empty catalogue is empty, not an error', () => {
	assert.deepEqual(dedupeShadowedExercises([]), []);
});

test('the input array is not mutated', () => {
	const rows = [global_('Bench Press'), custom('Bench Press')];
	const before = rows.map((e) => e.id);
	dedupeShadowedExercises(rows);
	assert.deepEqual(rows.map((e) => e.id), before);
});

test('a custom created against a stale client list still resolves the shadow it makes', () => {
	// Both editors merge the fetched catalogue with the customs created this
	// session, and that list is a snapshot: the create affordance can be offered
	// for a name the server already holds as a global, because the author's
	// partial unique cannot see a row whose author_id is null. The insert then
	// succeeds and mints exactly the pair the read's own dedupe removes, so the
	// merge has to apply the rule too — a de-duplication by `id`, which is what
	// both editors did instead, leaves both rows under one folded key.
	const stale = [global_('Ab Wheel'), global_('Bench Press')];
	const mine = custom('bench press');
	assert.deepEqual(
		dedupeShadowedExercises([...stale, mine]).map((e) => e.id),
		['Ab Wheel', mine.id],
	);
});

test('a row present in both the fetched list and the created one is listed once', () => {
	// The host reloads the catalogue after a create, so the created row is in
	// the prop AND still in the local list. Listing it twice would render one
	// exercise as two; re-ordering it would move it under the reader.
	const mine = custom('Bicep Curl');
	const fetched = [global_('Ab Wheel'), mine, global_('Zercher Squat')];
	assert.deepEqual(
		dedupeShadowedExercises([...fetched, mine]).map((e) => e.name),
		['Ab Wheel', 'Bicep Curl', 'Zercher Squat'],
	);
});

test('the key is the STORED name_key, not a re-derivation of the display name', () => {
	// The column both partial uniques are built on, so what the database calls
	// one exercise is read off the database's own value. The two instruments
	// agree on every migrated row and part in the window between a client
	// carrying a regenerated fold table and the migration that re-folds the
	// column (decisions § 1176) — and in that window a re-derivation splits a
	// pair the unique index will not let anyone add a third row to.
	const g = global_('Bench Press');
	const mine = stale('Bench Press', 'bench press stale');
	assert.deepEqual(
		dedupeShadowedExercises([g, mine]).map((e) => e.id),
		[g.id, mine.id],
		'two rows the index considers different are two rows here',
	);

	// And the converse: one stored key is one exercise however the two rows
	// happen to be spelled.
	const other = stale('Bench  Press', normaliseExerciseName('Bench Press'));
	assert.deepEqual(
		dedupeShadowedExercises([g, other]).map((e) => e.id),
		[other.id],
	);
});
