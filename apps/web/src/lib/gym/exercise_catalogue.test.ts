import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { dedupeShadowedExercises } from './exercise_catalogue';

// Mutation-tested against the rule it describes: dropping the `author_id`
// precedence (keeping the first row under a key) fails the two shadow cases,
// and keeping the LAST row instead fails whichever of them the fetch order
// contradicts.

const global_ = (name: string) => ({ id: name, name, author_id: null });
const custom = (name: string, id = `${name}-mine`) => ({ id, name, author_id: 'me' });

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
	const a = { id: 'a', name: 'Bench Press', author_id: null };
	const b = { id: 'b', name: 'bench  press', author_id: null };
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
