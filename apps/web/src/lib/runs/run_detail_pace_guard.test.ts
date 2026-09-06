// Source guard: one clock for every whole-run pace on /runs/[id].
//
// The page shows the run's pace in three places -- the key-stats grid, the
// grade-adjusted-pace threshold that decides whether the GAP cell appears at
// all, and the off-screen share card rasterised to a PNG. Each held its own
// copy of `movingSeconds > 0 ? movingSeconds : run.duration_s`, and the card's
// copy had drifted to the elapsed half alone: a 10 km with ten minutes of
// traffic lights read 5:00 /km on screen and posted 6:00 /km to social media,
// with nothing on the card saying which clock it meant (decisions § 1223).
//
// Anchored to the calls, not to the spelling of the fix: any whole-run pace or
// speed on this page is `format{Pace,Speed}(<seconds>, run.distance_m)`, and
// this asserts the seconds is the one shared derived value. A new cell that
// divides by the run's distance therefore cannot reintroduce a second clock.
//
// Runs with cwd = apps/web, like the other source guards in this directory.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from '../core/strip_comments';

const page = stripComments(
	readFileSync(resolve('src/routes/runs/[id]/+page.svelte'), 'utf-8'),
);

test('every whole-run pace and speed divides the shared paceSeconds', () => {
	const calls = [...page.matchAll(/format(?:Pace|Speed)\(\s*([^,]+?)\s*,\s*run\.distance_m\s*\)/g)];
	assert.ok(
		calls.length >= 3,
		`expected the grid pace, the grid speed and the share card to divide run.distance_m; found ${calls.length}`,
	);
	for (const c of calls) {
		assert.equal(
			c[1],
			'paceSeconds',
			`a whole-run pace/speed reads \`${c[1]}\` -- it must be the shared paceSeconds, or the page and the share card state two paces for one run`,
		);
	}
});

test('paceSeconds is declared once', () => {
	const decls = [...page.matchAll(/let\s+paceSeconds\b/g)];
	assert.equal(decls.length, 1, 'paceSeconds must have exactly one declaration');
	const src = page.slice(page.indexOf('let paceSeconds'));
	assert.match(
		src.slice(0, 200),
		/movingSeconds\s*>\s*0\s*\?\s*movingSeconds\s*:/,
		'paceSeconds must prefer moving time and fall back to elapsed',
	);
});

test('the share card states the clock its pace was taken over', () => {
	// The card is read with no page beside it, so a reader dividing its time by
	// its distance has to land on the pace printed under them.
	const start = page.indexOf('class="share-card-stats"');
	assert.ok(start > 0, 'the share card stat block moved');
	const block = page.slice(start, page.indexOf('share-card-date', start));
	const time = block.match(/formatDuration\(\s*([^)]+?)\s*\)/);
	const pace = block.match(/formatPace\(\s*([^,]+?)\s*,/);
	assert.ok(time && pace, 'the share card must render a duration and a pace');
	assert.equal(
		time[1],
		pace[1],
		'the share card\'s time and pace must be the same clock',
	);
	assert.match(
		block,
		/runDetail\.moving/,
		'the card must label the moving clock as moving when it uses one',
	);
});
