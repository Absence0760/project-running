import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	FINISHED_SLACK_MS,
	isFinishedStale,
	statusAfterHydrate,
} from './live_spectator_status';

const NOW = 1_700_000_000_000;

function startedIso(endOffsetMs: number, durationS: number): string {
	return new Date(NOW + endOffsetMs - durationS * 1000).toISOString();
}

test('isFinishedStale: end beyond the slack is stale-finished', () => {
	assert.equal(
		isFinishedStale(startedIso(-FINISHED_SLACK_MS - 1_000, 1_800), 1_800, NOW),
		true,
	);
});

test('isFinishedStale: end inside the slack is NOT stale-finished', () => {
	assert.equal(isFinishedStale(startedIso(-30_000, 1_800), 1_800, NOW), false);
});

test('isFinishedStale: boundary — end exactly at now - slack stays live-path', () => {
	assert.equal(
		isFinishedStale(startedIso(-FINISHED_SLACK_MS, 1_800), 1_800, NOW),
		false,
	);
});

test('isFinishedStale: zero / missing duration is never finished (broadcast stub)', () => {
	assert.equal(isFinishedStale(startedIso(-3_600_000, 0), 0, NOW), false);
});

test('isFinishedStale: unparseable started_at fails open to not-finished', () => {
	assert.equal(isFinishedStale('not-a-date', 1_800, NOW), false);
});

test('statusAfterHydrate: surviving backlog is live whatever the row says', () => {
	assert.equal(
		statusAfterHydrate({
			startedAtIso: startedIso(-3_600_000, 1_800),
			durationS: 1_800,
			hadBacklog: true,
			nowMs: NOW,
		}),
		'live',
	);
});

test('statusAfterHydrate: no pings + end just passed → finished, never a demo (issue #603)', () => {
	assert.equal(
		statusAfterHydrate({
			startedAtIso: startedIso(-30_000, 570),
			durationS: 570,
			hadBacklog: false,
			nowMs: NOW,
		}),
		'finished',
	);
});

test('statusAfterHydrate: boundary — end exactly now counts as finished', () => {
	assert.equal(
		statusAfterHydrate({
			startedAtIso: startedIso(0, 600),
			durationS: 600,
			hadBacklog: false,
			nowMs: NOW,
		}),
		'finished',
	);
});

test('statusAfterHydrate: in-progress stub (duration 0, no pings) waits honestly', () => {
	assert.equal(
		statusAfterHydrate({
			startedAtIso: startedIso(0, 0),
			durationS: 0,
			hadBacklog: false,
			nowMs: NOW,
		}),
		'waiting',
	);
});

test('statusAfterHydrate: projected duration with a future end waits, not finished', () => {
	assert.equal(
		statusAfterHydrate({
			startedAtIso: new Date(NOW - 5 * 60_000).toISOString(),
			durationS: 3_600,
			hadBacklog: false,
			nowMs: NOW,
		}),
		'waiting',
	);
});

test('statusAfterHydrate: unparseable started_at waits rather than fabricating a state', () => {
	assert.equal(
		statusAfterHydrate({
			startedAtIso: 'not-a-date',
			durationS: 1_800,
			hadBacklog: false,
			nowMs: NOW,
		}),
		'waiting',
	);
});
