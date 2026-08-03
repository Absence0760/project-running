import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { streakCardState } from './streak_card';

test('a pre-window best streak wins over the windowed figure', () => {
	// The defect the RPC fixes: a 10-day streak three years ago is outside
	// the ~2-year dashboard window, so the windowed compute reports 3 and
	// the old sub-label claimed 3 was the all-time best.
	const s = streakCardState({ current: 3, best: 10 }, { current: 3, best: 3 });
	assert.deepEqual(s, { current: 3, sub: { kind: 'best', n: 10 } });
});

test('server current is the headline when available', () => {
	const s = streakCardState({ current: 4, best: 9 }, { current: 3, best: 3 });
	assert.equal(s.current, 4);
});

test('all-time best fires only when the server confirms it', () => {
	const s = streakCardState({ current: 5, best: 5 }, { current: 5, best: 5 });
	assert.deepEqual(s.sub, { kind: 'allTimeBest' });
});

test('server data: a broken streak still shows the numeric best', () => {
	// Matches the pre-RPC template: best > current always wins the label,
	// so "restart" only ever renders from the no-server fallback below.
	const s = streakCardState({ current: 0, best: 6 }, { current: 0, best: 0 });
	assert.deepEqual(s, { current: 0, sub: { kind: 'best', n: 6 } });
});

test('server data: no runs ever offers a start', () => {
	const s = streakCardState({ current: 0, best: 0 }, { current: 0, best: 0 });
	assert.deepEqual(s, { current: 0, sub: { kind: 'start' } });
});

test('no server data: an active streak makes no all-time claim', () => {
	// Fail-closed (§ 470): rendering the windowed best as "Best: N" or
	// "All-time best!" is the silently-low number this card used to show.
	const s = streakCardState(null, { current: 3, best: 8 });
	assert.deepEqual(s, { current: 3, sub: { kind: 'none' } });
});

test('no server data: restart/start need no all-time knowledge', () => {
	// A windowed best > 0 proves a streak existed; "run to restart it"
	// claims nothing numeric, so it may render before the RPC resolves.
	assert.deepEqual(streakCardState(null, { current: 0, best: 2 }), {
		current: 0,
		sub: { kind: 'restart' },
	});
	assert.deepEqual(streakCardState(null, { current: 0, best: 0 }), {
		current: 0,
		sub: { kind: 'start' },
	});
});
