import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { StepOutcome } from './gym_session_types';
import {
	GYM_SESSION_DRAFT_KEY,
	draftLoggedCount,
	draftMetadata,
	draftResults,
	draftRoutineId,
	hasSessionDraft,
	restoreSessionDraft,
	resumedStartedAt,
	stripSessionDraft,
} from './gym_session_draft';

const logged = (reps: number, weightKg: number | null = null): StepOutcome => ({
	kind: 'logged',
	entered: { reps, weightKg, rpe: null, durationS: null, distanceM: null },
});
const skipped: StepOutcome = { kind: 'skipped' };

test('results stop before the current step — the step in hand has no outcome yet', () => {
	const out = draftResults([logged(5), skipped, undefined], 2);
	assert.equal(out.length, 2);
	assert.deepEqual(
		out.map((r) => [r.step_index, r.status]),
		[
			[0, 'completed'],
			[1, 'skipped'],
		],
	);
});

test('results carry every entered value, weights canonical kg', () => {
	const outcome: StepOutcome = {
		kind: 'logged',
		entered: { reps: 8, weightKg: 62.5, rpe: 7.5, durationS: 45, distanceM: 400 },
	};
	assert.deepEqual(draftResults([outcome], 1), [
		{
			step_index: 0,
			status: 'completed',
			reps: 8,
			weight_kg: 62.5,
			rpe: 7.5,
			duration_s: 45,
			distance_m: 400,
		},
	]);
});

test('results stay dense so a positional replay cannot shift steps', () => {
	const out = draftResults([logged(5), undefined, logged(3)], 3);
	assert.deepEqual(
		out.map((r) => [r.step_index, r.status]),
		[
			[0, 'completed'],
			[1, 'skipped'],
			[2, 'completed'],
		],
	);
});

test('a current index past the outcome list is clamped', () => {
	assert.equal(draftResults([logged(5)], 9).length, 1);
	assert.deepEqual(draftResults([logged(5)], 0), []);
	assert.deepEqual(draftResults([logged(5)], -1), []);
});

test('the metadata bag carries the routine link beside the snapshot', () => {
	const meta = draftMetadata('r1', [logged(5)], 1, '2026-08-04T10:00:00.000Z');
	assert.equal(meta.routine_id, 'r1');
	const snap = meta[GYM_SESSION_DRAFT_KEY] as { saved_at: string; results: unknown[] };
	assert.equal(snap.saved_at, '2026-08-04T10:00:00.000Z');
	assert.equal(snap.results.length, 1);
	assert.equal(hasSessionDraft(meta), true);
	assert.equal(draftRoutineId(meta), 'r1');
});

test('a bag with no draft key is not a draft', () => {
	assert.equal(hasSessionDraft({ routine_id: 'r1', gym_adherence: 'completed' }), false);
	assert.equal(hasSessionDraft(null), false);
	assert.equal(hasSessionDraft('nonsense'), false);
	assert.equal(draftRoutineId({ routine_id: 'r1' }), null);
	assert.equal(restoreSessionDraft({ routine_id: 'r1' }, 3), null);
});

// The marker's shape is a three-rail contract: Dart's `routine_history.dart`
// asks `is Map` and the `gym_routine_history` RPC asks
// `jsonb_typeof(...) = 'object'`. `typeof x === 'object'` answers true for an
// array, so without this the same row read as in-flight on web and as
// performed on the other two.
test('a non-object under the draft key is not a draft — the SQL + Dart answer', () => {
	assert.equal(hasSessionDraft({ routine_id: 'r1', [GYM_SESSION_DRAFT_KEY]: [] }), false);
	assert.equal(
		hasSessionDraft({ routine_id: 'r1', [GYM_SESSION_DRAFT_KEY]: [{ step_index: 0 }] }),
		false,
	);
	assert.equal(hasSessionDraft({ [GYM_SESSION_DRAFT_KEY]: null }), false);
	assert.equal(hasSessionDraft({ [GYM_SESSION_DRAFT_KEY]: 'in flight' }), false);
	assert.equal(hasSessionDraft({ [GYM_SESSION_DRAFT_KEY]: 3 }), false);
	// …and every reader built on the same predicate agrees.
	assert.equal(draftRoutineId({ routine_id: 'r1', [GYM_SESSION_DRAFT_KEY]: [] }), null);
	assert.equal(restoreSessionDraft({ routine_id: 'r1', [GYM_SESSION_DRAFT_KEY]: [] }, 3), null);
	assert.equal(draftLoggedCount({ routine_id: 'r1', [GYM_SESSION_DRAFT_KEY]: [] }), 0);
});

test('an array metadata bag is not a bag', () => {
	assert.equal(hasSessionDraft([{ [GYM_SESSION_DRAFT_KEY]: { results: [] } }]), false);
	assert.deepEqual(stripSessionDraft(['a']), {});
});

test('a draft with no usable routine link reports none', () => {
	assert.equal(draftRoutineId({ [GYM_SESSION_DRAFT_KEY]: { results: [] } }), null);
	assert.equal(draftRoutineId({ routine_id: '', [GYM_SESSION_DRAFT_KEY]: { results: [] } }), null);
});

test('a round trip through the wire shape restores the same outcomes', () => {
	const outcomes: (StepOutcome | undefined)[] = [logged(5, 60), skipped, logged(8, 40), undefined];
	const meta = draftMetadata('r1', outcomes, 3, '2026-08-04T10:00:00.000Z');
	const back = restoreSessionDraft(meta, 4);
	assert.ok(back);
	assert.equal(back.currentIndex, 3);
	assert.deepEqual(back.outcomes, [logged(5, 60), skipped, logged(8, 40), undefined]);
});

test('a mobile-written snapshot restores identically (same key, same field names)', () => {
	const fromMobile = {
		routine_id: 'r1',
		gym_session_draft: {
			saved_at: '2026-08-04T09:00:00.000Z',
			results: [
				{
					step_index: 0,
					status: 'completed',
					reps: 5,
					weight_kg: 60,
					rpe: null,
					duration_s: null,
					distance_m: null,
				},
				{
					step_index: 1,
					status: 'skipped',
					reps: null,
					weight_kg: null,
					rpe: null,
					duration_s: null,
					distance_m: null,
				},
			],
		},
	};
	const back = restoreSessionDraft(fromMobile, 3);
	assert.ok(back);
	assert.equal(back.currentIndex, 2);
	assert.deepEqual(back.outcomes, [logged(5, 60), skipped, undefined]);
});

test('a routine that shrank between save and resume replays only what still fits', () => {
	const meta = draftMetadata('r1', [logged(5), logged(6), logged(7)], 3, 'now');
	const back = restoreSessionDraft(meta, 2);
	assert.ok(back);
	assert.equal(back.currentIndex, 2);
	assert.equal(back.outcomes.length, 2);
});

test('an unreadable results list resumes on the same row rather than forking a new draft', () => {
	const back = restoreSessionDraft({ [GYM_SESSION_DRAFT_KEY]: { results: 'broken' } }, 3);
	assert.ok(back);
	assert.equal(back.currentIndex, 0);
	assert.deepEqual(back.outcomes, [undefined, undefined, undefined]);
});

test('a non-numeric value in a snapshot reads as absent, never NaN', () => {
	const back = restoreSessionDraft(
		{
			[GYM_SESSION_DRAFT_KEY]: {
				results: [{ step_index: 0, status: 'completed', reps: 'five', weight_kg: null }],
			},
		},
		1,
	);
	assert.ok(back);
	assert.deepEqual(back.outcomes[0], {
		kind: 'logged',
		entered: { reps: null, weightKg: null, rpe: null, durationS: null, distanceM: null },
	});
});

test('logged count ignores skipped steps', () => {
	const meta = draftMetadata('r1', [logged(5), skipped, logged(6)], 3, 'now');
	assert.equal(draftLoggedCount(meta), 2);
	assert.equal(draftLoggedCount({ routine_id: 'r1' }), 0);
});

test('elapsed re-anchors to now minus the saved duration', () => {
	const now = Date.parse('2026-08-04T12:00:00.000Z');
	assert.equal(resumedStartedAt(600, now), '2026-08-04T11:50:00.000Z');
	assert.equal(resumedStartedAt(null, now), '2026-08-04T12:00:00.000Z');
	assert.equal(resumedStartedAt(0, now), '2026-08-04T12:00:00.000Z');
	assert.equal(resumedStartedAt(-5, now), '2026-08-04T12:00:00.000Z');
});

test('save-as-is drops only the draft marker', () => {
	const meta = { ...draftMetadata('r1', [logged(5)], 1, 'now'), notes_kept: true };
	const stripped = stripSessionDraft(meta);
	assert.equal(stripped.routine_id, 'r1');
	assert.equal(stripped.notes_kept, true);
	assert.equal(GYM_SESSION_DRAFT_KEY in stripped, false);
	assert.deepEqual(stripSessionDraft(null), {});
});
