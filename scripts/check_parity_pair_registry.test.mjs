import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	CLAUDE_DOC,
	SYNCER_DOC,
	checkRegistries,
	parseClaudePairs,
	parseSyncerRows,
	pathsInCell,
} from './check_parity_pair_registry.mjs';

/// The un-annotated names the real list opens with, and the rows that must
/// accompany them on the syncer side for the two fakes to agree. Tests that
/// override one side spread these back in, so the only drift in a case is the
/// drift it is testing.
const HEAD = ['training', 'segments'];
const HEAD_ROWS = [
	['training/training.ts', 'apps/mobile_android/lib/training.dart', 'training/training.test.ts', 'test/training_test.dart'],
	['segments/segments.ts', 'apps/mobile_android/lib/segments.dart', 'segments/segments.test.ts', 'test/segments_test.dart'],
];
/// track_projection's Dart half is a pair of helpers inside a widget file, so
/// its mobile cell is prose with the path embedded.
const TAIL_ROW = [
	'routes/track_projection.ts',
	'`projectTrack` inside `apps/mobile_android/lib/widgets/track_preview.dart`',
	'routes/track_projection.test.ts',
	'test/track_preview_test.dart',
];
const ROADBOOK_ROW = [
	'routes/roadbook.ts',
	'apps/mobile_android/lib/roadbook.dart',
	'routes/roadbook.test.ts',
	'test/roadbook_test.dart',
];

/// A CLAUDE.md shaped like the real one: the lockstep bullet on ONE line,
/// opening with a run of bare names, then entries that annotate their paths,
/// then the track_projection tail clause. The watch-port paragraph follows on
/// its own line — those are one-way ports and must NOT be read as pairs.
function fakeClaude({
	head = HEAD,
	annotated = [['roadbook', 'routes/roadbook.ts', 'roadbook.dart']],
	tail = true,
	listLabel = 'The pairs are:',
	bullet = 'TS↔Dart parity helpers must stay in lockstep.',
} = {}) {
	const entries = [
		...head.map((n) => `\`${n}\`, `),
		...annotated.map(([n, ts, dart]) => `\`${n}\` (web \`${ts}\` ↔ mobile \`${dart}\`), `),
	].join('');
	const tailText = tail
		? 'plus the `track_projection.ts` ↔ `projectTrack` helpers inside `track_preview.dart`.'
		: 'and that is the list.';
	return (
		`# Orientation\n\n` +
		`- **${bullet}** ${listLabel} ${entries}${tailText}\n\n` +
		`Many of these also carry a third parity rail in the watch firmware: \`storm\` ` +
		`(web \`fake/storm.ts\` ↔ mobile \`storm.dart\`) is watch-native and owes no twin.\n`
	);
}

/// A syncer file shaped like the real one: the canonical-list heading, a
/// header row, a separator, then one row per pair.
function fakeSyncer({
	rows = [...HEAD_ROWS, ROADBOOK_ROW, TAIL_ROW],
	heading = '## The pairs (canonical list)',
} = {}) {
	const body = rows
		.map(
			([web, mobile, webTest, dartTest]) =>
				`| \`apps/web/src/lib/${web}\` | \`${mobile}\` | \`${webTest}\` ↔ \`${dartTest}\` |`,
		)
		.join('\n');
	return `---\nname: shared-library-syncer\n---\n\n${heading}\n\n| Web | Mobile | Mirror test pair |\n|---|---|---|\n${body}\n\n> A closing note.\n`;
}

/// Every path in the fakes resolves, so a test asserting a drift error is not
/// reading a file-not-found error by accident.
const allExist = () => true;

test('a pair in CLAUDE.md but missing from the syncer table fails, and is named', () => {
	const claude = fakeClaude({
		annotated: [
			['roadbook', 'routes/roadbook.ts', 'roadbook.dart'],
			['route_snap', 'routes/route_snap.ts', 'route_snap.dart'],
		],
	});
	const { errors } = checkRegistries(claude, fakeSyncer(), allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /route_snap/);
	assert.match(errors[0], /no row in the shared-library-syncer table/);
	assert.doesNotMatch(errors[0], /roadbook/);
});

test('a row in the syncer table not named in CLAUDE.md fails too', () => {
	const syncer = fakeSyncer({
		rows: [
			...HEAD_ROWS,
			ROADBOOK_ROW,
			TAIL_ROW,
			['social/nearby.ts', 'apps/mobile_android/lib/nearby.dart', 'social/nearby.test.ts', 'test/nearby_test.dart'],
		],
	});
	const { errors } = checkRegistries(fakeClaude(), syncer, allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /nearby/);
	assert.match(errors[0], /not named in CLAUDE\.md/);
});

test('the bare head names and the track_projection tail count as registered pairs', () => {
	// Neither form annotates a path, so membership is all the guard can check
	// for them — and it must, or three real pairs would be silently exempt.
	const { errors } = checkRegistries(fakeClaude(), fakeSyncer(), allExist);
	assert.deepEqual(errors, []);

	const { pairs } = parseClaudePairs(fakeClaude());
	assert.deepEqual([...pairs.keys()], ['training', 'segments', 'roadbook', 'track_projection']);
});

test('the watch-port paragraph is not read as a pair list', () => {
	// `storm` sits on the line AFTER the bullet and is deliberately not a pair.
	const { pairs } = parseClaudePairs(fakeClaude());
	assert.equal(pairs.has('storm'), false);
	assert.equal(pairs.has('roadbook'), true);
});

test('a CLAUDE.md path that disagrees with its syncer row fails', () => {
	const claude = fakeClaude({ annotated: [['roadbook', 'runs/roadbook.ts', 'roadbook.dart']] });
	const { errors } = checkRegistries(claude, fakeSyncer(), allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /aimed at the wrong file/);
});

test('a CLAUDE.md mobile path the syncer row never mentions fails', () => {
	const claude = fakeClaude({ annotated: [['roadbook', 'routes/roadbook.ts', 'road_book.dart']] });
	const { errors } = checkRegistries(claude, fakeSyncer(), allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /road_book\.dart/);
	assert.match(errors[0], /mobile cell does not mention/);
});

test('a mobile path suffix-matches only on a whole segment', () => {
	// `heatmap.dart` must not satisfy a row naming `lib/run_heatmap.dart`.
	const claude = fakeClaude({ annotated: [['run_heatmap', 'routes/run_heatmap.ts', 'heatmap.dart']] });
	const syncer = fakeSyncer({
		rows: [
			...HEAD_ROWS,
			TAIL_ROW,
			['routes/run_heatmap.ts', 'apps/mobile_android/lib/run_heatmap.dart', 'routes/run_heatmap.test.ts', 'test/run_heatmap_test.dart'],
		],
	});
	const { errors } = checkRegistries(claude, syncer, allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /mobile cell does not mention/);
});

test('a registered path that does not exist on disk fails', () => {
	const { errors } = checkRegistries(fakeClaude(), fakeSyncer(), (p) => !p.endsWith('roadbook.dart'));

	assert.equal(errors.length, 1);
	assert.match(errors[0], /apps\/mobile_android\/lib\/roadbook\.dart/);
	assert.match(errors[0], /does not exist/);
});

test('the mirror-test column resolves both of its relative forms', () => {
	assert.deepEqual(pathsInCell('`routes/roadbook.test.ts` ↔ `test/roadbook_test.dart`'), [
		'apps/web/src/lib/routes/roadbook.test.ts',
		'apps/mobile_android/test/roadbook_test.dart',
	]);
	// core_models' suite is already repo-relative and must not be re-rooted.
	assert.deepEqual(pathsInCell('`social/profile_query.test.ts` ↔ `packages/core_models/test/profile_query_test.dart`'), [
		'packages/core_models/test/profile_query_test.dart',
		'apps/web/src/lib/social/profile_query.test.ts',
	]);
	// Trailing prose naming symbols rather than files contributes nothing.
	assert.deepEqual(pathsInCell('`gym/gym_prs.test.ts` ↔ `test/gym_prs_test.dart` — see `normaliseExerciseName`'), [
		'apps/web/src/lib/gym/gym_prs.test.ts',
		'apps/mobile_android/test/gym_prs_test.dart',
	]);
});

// --- Vacuous-pass cases. A guard that silently matches nothing enforces
// nothing, so every way of losing a parser's grip must FAIL rather than
// report two empty sets as agreement.

test('a renamed CLAUDE.md bullet fails instead of passing over an empty set', () => {
	const claude = fakeClaude({ bullet: 'Parity helpers, keep them the same.' });
	const { errors } = checkRegistries(claude, fakeSyncer(), allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /this guard now checks nothing/);
});

test('a reworded pair-list label fails', () => {
	const claude = fakeClaude({ listLabel: 'Pairs:' });
	const { errors } = checkRegistries(claude, fakeSyncer(), allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /leaving it matching nothing/);
});

test('losing the annotated entry form fails rather than dropping the entries', () => {
	const claude =
		'- **TS↔Dart parity helpers must stay in lockstep.** The pairs are: `training`, ' +
		'`segments`, `roadbook` [web: routes/roadbook.ts].\n';
	const { errors } = checkRegistries(claude, fakeSyncer(), allExist);

	assert.ok(errors.some((e) => /can no longer read the list/.test(e)));
});

test('losing the bare-head run fails rather than dropping those pairs', () => {
	const claude =
		'- **TS↔Dart parity helpers must stay in lockstep.** The pairs are: ' +
		'`roadbook` (web `routes/roadbook.ts` ↔ mobile `roadbook.dart`).\n';
	const { errors } = checkRegistries(claude, fakeSyncer(), allExist);

	assert.ok(errors.some((e) => /run of bare names/.test(e)));
});

test('a renamed syncer heading fails', () => {
	const { errors } = checkRegistries(fakeClaude(), fakeSyncer({ heading: '## The pairs' }), allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /this guard now checks nothing/);
});

test('a syncer table whose column shape changed fails', () => {
	const syncer = '## The pairs (canonical list)\n\nSee the agent prose above.\n';
	const { errors } = checkRegistries(fakeClaude(), syncer, allExist);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /enforcing nothing/);
});

test('two empty registries do not read as agreement', () => {
	const { errors } = checkRegistries('# nothing here\n', '# nothing here\n', allExist);

	assert.equal(errors.length, 2);
	assert.ok(errors.every((e) => /checks nothing/.test(e)));
});

// --- The real files.

test('the committed registries agree', () => {
	const { errors, ok } = checkRegistries(
		readFileSync(CLAUDE_DOC, 'utf-8'),
		readFileSync(SYNCER_DOC, 'utf-8'),
	);

	assert.deepEqual(errors, []);
	assert.equal(ok.length, 2);
});

test('the real registries carry the whole pair set, not a fragment of it', () => {
	// The floor is a smoke test on the parsers themselves: the registry has
	// carried dozens of pairs since long before this guard, so a parse that
	// returns a handful means the prose or the table shifted under it in a way
	// the anchor checks did not catch.
	const { pairs } = parseClaudePairs(readFileSync(CLAUDE_DOC, 'utf-8'));
	const { rows } = parseSyncerRows(readFileSync(SYNCER_DOC, 'utf-8'));

	assert.ok(pairs.size >= 60, `CLAUDE.md parsed only ${pairs.size} pairs`);
	assert.ok(rows.size >= 60, `the syncer table parsed only ${rows.size} rows`);
	assert.equal(pairs.size, rows.size);
});
