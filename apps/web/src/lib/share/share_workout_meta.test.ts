import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildWorkoutShareTitle,
	buildWorkoutShareDescription,
	buildWorkoutShareCanonical,
	buildWorkoutJsonLd,
	buildShareWorkoutHead,
	distinctExerciseCount,
	formatKgStable,
} from './share_workout_meta';
import type { SharedWorkout, SharedWorkoutSet } from './share_workout_lookup';

function s(over: Partial<SharedWorkoutSet> = {}): SharedWorkoutSet {
	return { set_index: 0, exercise_name: 'Squat', reps: 5, weight_kg: 100, duration_s: null, ...over };
}

function w(over: Partial<SharedWorkout> = {}): SharedWorkout {
	return {
		id: 'w-1',
		user_id: 'u-1',
		title: 'Leg day',
		started_at: '2026-03-14T09:30:00Z',
		set_count: 3,
		volume_kg: 1500,
		sets: [s(), s({ set_index: 1 }), s({ set_index: 2, exercise_name: 'Bench press' })],
		...over,
	};
}

test('buildWorkoutShareTitle — caption wins, then athlete, then generic', () => {
	assert.equal(buildWorkoutShareTitle(w(), 'Alice'), 'Leg day — Threkir');
	assert.equal(buildWorkoutShareTitle(w({ title: null }), 'Alice'), 'Workout by Alice — Threkir');
	assert.equal(buildWorkoutShareTitle(w({ title: '   ' }), null), 'Workout — Threkir');
	assert.equal(buildWorkoutShareTitle(null, 'Alice'), 'Workout — Threkir');
});

test('buildWorkoutShareTitle — a pathological caption is collapsed and bounded', () => {
	const t = buildWorkoutShareTitle(w({ title: `${'x'.repeat(400)}` }), null);
	assert.ok(t.length < 100, `title should be bounded, got ${t.length}`);
	assert.ok(t.endsWith('… — Threkir'));
	assert.equal(buildWorkoutShareTitle(w({ title: 'Leg\n\n  day' }), null), 'Leg day — Threkir');
});

test('buildWorkoutShareDescription — exercises · sets · volume · athlete · date', () => {
	const d = buildWorkoutShareDescription(w(), 'Alice');
	assert.match(d, /2 exercises/);
	assert.match(d, /3 sets/);
	assert.match(d, /1500 kg lifted/);
	assert.match(d, /by Alice/);
	assert.match(d, /on 14 Mar 2026/);
});

test('buildWorkoutShareDescription — singular forms, and a bare workout still reads', () => {
	const d = buildWorkoutShareDescription(
		w({ set_count: 1, volume_kg: null, sets: [s()], started_at: null }),
		null,
	);
	assert.match(d, /1 exercise\b/);
	assert.match(d, /1 set\./);
	assert.doesNotMatch(d, /kg/);
	assert.equal(
		buildWorkoutShareDescription(w({ set_count: 0, volume_kg: 0, sets: [], started_at: null }), null),
		'Log your lifts on Threkir.',
	);
	assert.equal(
		buildWorkoutShareDescription(null, 'Alice'),
		'View a public gym workout on Threkir.',
	);
});

// The redacted public_gym_workouts / public_gym_sets views omit notes + rpe;
// this pins that no builder starts reading them off a widened lookup shape.
test('the meta never surfaces the owner-private notes / rpe fields', () => {
	const hostile = w() as SharedWorkout & { notes?: string; sets: Array<SharedWorkoutSet & { rpe?: number }> };
	hostile.notes = 'felt awful, back twinged, weighed 78kg';
	hostile.sets[0].rpe = 9;
	const head = buildShareWorkoutHead({
		id: 'w-1',
		workout: hostile,
		displayName: 'Alice',
		siteUrl: 'https://threkir.com',
	});
	for (const field of [head.title, head.description, head.jsonLd]) {
		assert.doesNotMatch(field, /twinged|78kg|rpe/i);
	}
});

test('formatKgStable — canonical kg, rounded, blank for absent / non-positive', () => {
	assert.equal(formatKgStable(1500), '1500 kg');
	assert.equal(formatKgStable(1499.6), '1500 kg');
	assert.equal(formatKgStable(0), '');
	assert.equal(formatKgStable(null), '');
	assert.equal(formatKgStable(Number.NaN), '');
	assert.equal(formatKgStable(Number.POSITIVE_INFINITY), '');
});

test('distinctExerciseCount — counted on the canonical grouping key', () => {
	// Every pair below is ONE lift to `gym_workout_summaries` and to every
	// keyed surface. `trim().toLowerCase()` merged only the first of them:
	// it splits an internal whitespace run and answers a different letter
	// from the frozen table (§ 1274).
	const two = (a: string, b: string) =>
		distinctExerciseCount([s({ exercise_name: a }), s({ exercise_name: b })]);
	assert.equal(two('Back Squat', 'back squat '), 1);
	assert.equal(two('Bench  Press', 'Bench Press'), 1);
	assert.equal(two('Bench\u00a0Press', 'bench press'), 1);
	assert.equal(two('Bench\tPress', 'bench press'), 1);
	assert.equal(two('\u0130ncline Press', 'incline press'), 1);
	assert.equal(two('Bench Press', 'Back Squat'), 2);
	// A blank name is not an exercise — same rule the PR map applies.
	assert.equal(two('   ', '\u00a0'), 0);
	assert.equal(distinctExerciseCount([]), 0);
});

test('buildWorkoutShareDescription — two spellings of one lift unfurl as one exercise', () => {
	// The count reaches every unfurler that touches the link, so a workout
	// the app itself calls one exercise must not advertise two.
	const desc = buildWorkoutShareDescription(
		w({
			sets: [s({ exercise_name: 'Bench  Press' }), s({ set_index: 1, exercise_name: 'bench press' })],
			set_count: 2,
		}),
		'Ada',
	);
	assert.match(desc, /^1 exercise · 2 sets/);
});

test('buildWorkoutShareCanonical — absolute share/workout URL, slash-normalised', () => {
	assert.equal(
		buildWorkoutShareCanonical('https://threkir.com/', 'w-1'),
		'https://threkir.com/share/workout/w-1',
	);
	assert.equal(buildWorkoutShareCanonical(null, 'w-1'), '/share/workout/w-1');
});

test('buildWorkoutJsonLd — WebPage + breadcrumb, no medical type, no image claim', () => {
	const obj = JSON.parse(
		buildWorkoutJsonLd(w(), { id: 'w-1', base: 'https://threkir.com', displayName: 'Alice' }),
	);
	assert.equal(obj['@type'], 'WebPage');
	assert.equal(obj.name, 'Leg day');
	assert.equal(obj.url, 'https://threkir.com/share/workout/w-1');
	assert.equal(obj.breadcrumb['@type'], 'BreadcrumbList');
	assert.equal(obj.breadcrumb.itemListElement.length, 2);
	assert.equal(obj.breadcrumb.itemListElement[1].name, 'Leg day');
	assert.equal('primaryImageOfPage' in obj, false);
});

test('buildWorkoutJsonLd — escapes angle brackets so a caption cannot break out of the script tag', () => {
	const json = buildWorkoutJsonLd(w({ title: '</script><b>x</b>' }), {
		id: 'w-1',
		base: 'https://threkir.com',
	});
	assert.ok(!json.includes('<'));
	assert.ok(!json.includes('>'));
	assert.equal(JSON.parse(json).name, '</script><b>x</b>');
});

test('buildShareWorkoutHead — canonical, branded OG image, JSON-LD in one shape', () => {
	const head = buildShareWorkoutHead({
		id: 'w-1',
		workout: w(),
		displayName: 'Alice',
		siteUrl: 'https://threkir.com/',
	});
	assert.equal(head.canonical, 'https://threkir.com/share/workout/w-1');
	assert.equal(head.ogImageUrl, 'https://threkir.com/og-default.png');
	assert.equal(head.title, 'Leg day — Threkir');
	assert.equal(JSON.parse(head.jsonLd).url, head.canonical);
});

// A missing / private workout resolves to `workout: null`, and the head must
// still be a valid, generic one — a crawler on a stale link gets meta, not the
// literal "undefined".
test('buildShareWorkoutHead — a private / missing workout still yields a valid head', () => {
	const head = buildShareWorkoutHead({
		id: 'w-x',
		workout: null,
		displayName: null,
		siteUrl: 'https://threkir.com',
	});
	assert.equal(head.title, 'Workout — Threkir');
	assert.equal(head.canonical, 'https://threkir.com/share/workout/w-x');
	assert.doesNotMatch(head.description, /undefined|null/);
	assert.equal(JSON.parse(head.jsonLd)['@type'], 'WebPage');
});
