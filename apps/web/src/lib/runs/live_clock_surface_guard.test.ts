// Source guard over the spectator surface's two clocks (decisions.md § 712).
//
// The helpers are unit-tested; what no unit test can see is that the PAGE
// still feeds them the right instants. The bug § 712 closed was not in a
// helper — it was one tile asked for two quantities — so the properties worth
// pinning here are the ones a well-meaning edit to the page would undo:
// measuring a finished run's race clock to `now`, withholding the timer
// instead of qualifying it, and driving cut-off maths off the frozen
// stopwatch when the start instant is resolvable.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const LIVE_PAGE = 'src/routes/live/[id]/+page.svelte';

function source(): string {
	return readFileSync(resolve(LIVE_PAGE), 'utf-8');
}

test('the race clock is measured to the conclusion instant once the run is terminal', () => {
	const src = source();
	assert.match(
		src,
		/raceClockAtMs\s*=\s*\$derived\(\s*status === 'finished'\s*\?\s*concludedAtMs\s*:\s*nowMs\s*\)/,
		'a finished run must measure to its conclusion instant — measuring to `now` makes a ' +
			'race clock that ticks forever on a run that stopped months ago',
	);
	assert.match(
		src,
		/raceClock\s*=\s*\$derived\(raceClockS\(startedAtMs,\s*raceClockAtMs\)\)/,
		'the race clock must come from raceClockS over the page-resolved instants',
	);
});

test('a run with no conclusion instant withholds the race clock rather than defaulting it', () => {
	const src = source();
	// A `?? nowMs` / `?? Date.now()` anywhere in the derivation is the exact
	// repair that reintroduces the bug: it turns "we cannot date the end of
	// this run" into "it ended just now".
	const derivation = src.match(/const raceClockAtMs = \$derived\([^;]*\);/s)?.[0] ?? '';
	assert.ok(derivation.length > 0, 'raceClockAtMs derivation not found');
	assert.doesNotMatch(
		derivation,
		/\?\?/,
		'the conclusion instant must not be defaulted — a null end withholds the tile',
	);
	assert.match(
		src,
		/\{#if raceClock != null\}/,
		'the race-clock tile renders only when the clock resolves',
	);
});

test('the runner timer is qualified when stale, never withheld or advanced', () => {
	const src = source();
	assert.match(
		src,
		/timerIsStale\s*=\s*\$derived\(status !== 'finished' && isStale\)/,
		'a concluded run is frozen on its saved duration, so the last-fix qualifier ' +
			'applies only while the run is still running',
	);
	// The tile itself is unconditional: the measurement is real and only its
	// currency is in doubt (§ 712), so the label changes and the number does
	// not disappear.
	const tile = src.match(/<div class="live-stat"[^>]*data-testid="runner-timer"[\s\S]{0,400}?<\/div>/)?.[0] ?? '';
	assert.ok(tile.length > 0, 'runner-timer tile not found');
	assert.match(tile, /formatDuration\(elapsed\)/, 'the timer shows the ping\'s own elapsed_s');
	assert.match(
		tile,
		/statTimerStale/,
		'a stale timer relabels rather than vanishing',
	);
	assert.doesNotMatch(
		tile,
		/liveElapsedS|raceClock/,
		'the timer tile must not be advanced by wall clock — that would overstate a ' +
			'runner who paused, which is the trade § 712 refused',
	);
});

test('cut-off maths runs on the race clock, with liveElapsedS only as the fallback', () => {
	const src = source();
	assert.match(
		src,
		/raceElapsedS\s*=\s*\$derived\(raceClock \?\? liveElapsedS\(/,
		'the race clock is preferred and liveElapsedS is reached only when the start ' +
			'instant could not be resolved — the ordering is the whole point of the pair',
	);
	// The ETA card consumes the resolved clock, not the raw ping value.
	assert.match(
		src,
		/elapsedS:\s*raceElapsedS/,
		'nextCutoffEta must be fed the race clock, not the frozen stopwatch',
	);
});

test('both stat tiles carry a testid, so an assertion cannot depend on tile order', () => {
	const src = source();
	for (const id of ['race-clock', 'runner-timer', 'live-distance', 'avg-pace']) {
		assert.match(src, new RegExp(`data-testid="${id}"`), `missing data-testid="${id}"`);
	}
});

test('the page reads started_at from the row it already holds, not a second fetch', () => {
	const src = source();
	// § 712's argument for the race clock needing no estimate is that
	// `public_runs` already serves `started_at` to an anonymous spectator.
	assert.match(src, /startedAtMs\b/, 'the page must hold the start instant');
	assert.match(
		src,
		/started_at/,
		'the start instant comes off the public run row',
	);
});
