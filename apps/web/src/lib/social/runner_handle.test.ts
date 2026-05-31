import { test } from 'node:test';
import assert from 'node:assert/strict';

import { runnerHandle, shouldRevealDisplayName } from './runner_handle';

test('runnerHandle: returns Runner #ABCD for a v4 uuid (first 4 hex chars, uppercased)', () => {
	assert.equal(
		runnerHandle('a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
		'Runner #A1B2',
	);
	assert.equal(
		runnerHandle('00000000-0000-0000-0000-000000000bad'),
		'Runner #0000',
	);
});

test('runnerHandle: drops hyphens from the uuid before taking the slice', () => {
	// If we kept hyphens, the first 4 chars of a uuid starting `aaa-`
	// would be `aaa-` — using "-" as part of the user-facing handle
	// is ugly. Strip first, then slice.
	assert.equal(runnerHandle('aaa-b2c3-...'), 'Runner #AAAB');
});

test('runnerHandle: returns plain "Runner" for null / undefined / empty / too-short input', () => {
	assert.equal(runnerHandle(null), 'Runner');
	assert.equal(runnerHandle(undefined), 'Runner');
	assert.equal(runnerHandle(''), 'Runner');
	// 3 hex chars after hyphen strip — not enough for the suffix.
	assert.equal(runnerHandle('a-1'), 'Runner');
});

test('runnerHandle: deterministic — same uuid produces same handle on every call', () => {
	const id = 'b2c3d4e5-f6a7-8901-bcde-f23456789012';
	assert.equal(runnerHandle(id), runnerHandle(id));
});

test('shouldRevealDisplayName: anon viewer → false', () => {
	assert.equal(
		shouldRevealDisplayName({
			viewerUserId: null,
			runnerUserId: 'r-1',
			viewerFollowsRunner: false,
			runnerFollowsViewer: false,
		}),
		false,
	);
});

test('shouldRevealDisplayName: missing runnerUserId → false (defensive)', () => {
	assert.equal(
		shouldRevealDisplayName({
			viewerUserId: 'v-1',
			runnerUserId: null,
			viewerFollowsRunner: false,
			runnerFollowsViewer: false,
		}),
		false,
	);
});

test('shouldRevealDisplayName: self-view → true', () => {
	assert.equal(
		shouldRevealDisplayName({
			viewerUserId: 'same-id',
			runnerUserId: 'same-id',
			viewerFollowsRunner: false,
			runnerFollowsViewer: false,
		}),
		true,
	);
});

test('shouldRevealDisplayName: viewer follows runner → true', () => {
	assert.equal(
		shouldRevealDisplayName({
			viewerUserId: 'v',
			runnerUserId: 'r',
			viewerFollowsRunner: true,
			runnerFollowsViewer: false,
		}),
		true,
	);
});

test('shouldRevealDisplayName: runner follows viewer → true', () => {
	// "Friend" is the soft definition — one-way follow in either
	// direction counts. The runner can't unilaterally reveal their
	// name to a stranger (they'd have to follow them first, which
	// is an intentional act).
	assert.equal(
		shouldRevealDisplayName({
			viewerUserId: 'v',
			runnerUserId: 'r',
			viewerFollowsRunner: false,
			runnerFollowsViewer: true,
		}),
		true,
	);
});

test('shouldRevealDisplayName: signed-in stranger with no follow edge → false', () => {
	// The privacy-conscious persona's core ask: a random signed-in
	// user who stumbles across a live URL must NOT see the runner's
	// real name unless there's at least a one-way follow.
	assert.equal(
		shouldRevealDisplayName({
			viewerUserId: 'stranger',
			runnerUserId: 'runner',
			viewerFollowsRunner: false,
			runnerFollowsViewer: false,
		}),
		false,
	);
});
