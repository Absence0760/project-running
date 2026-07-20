import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isTrackOwner, resolveTrackOwnership } from './track_ownership';

test('isTrackOwner: owner viewer is the owner', () => {
	assert.equal(isTrackOwner('u-1', 'u-1'), true);
});

test('isTrackOwner: a different signed-in viewer is not the owner', () => {
	assert.equal(isTrackOwner('u-2', 'u-1'), false);
});

test('isTrackOwner: anon viewer (null / undefined) is not the owner', () => {
	assert.equal(isTrackOwner(null, 'u-1'), false);
	assert.equal(isTrackOwner(undefined, 'u-1'), false);
});

test('isTrackOwner: null/undefined owner is never matched (no undefined===undefined leak)', () => {
	assert.equal(isTrackOwner(null, null), false);
	assert.equal(isTrackOwner(undefined, undefined), false);
});

test('resolveTrackOwnership waits for auth.ready before reading the viewer id', async () => {
	// Mount-time race: the owner's session has not finished restoring, so
	// the viewer id reads null until the ready gate resolves.
	let viewerId: string | null = null;
	let openGate!: () => void;
	const ready = () => new Promise<void>((resolve) => (openGate = resolve));

	const pending = resolveTrackOwnership(ready, () => viewerId, 'owner-1');

	// Session restores after mount: the viewer id becomes the owner and
	// the gate opens.
	viewerId = 'owner-1';
	openGate();

	const { isOwner, shouldClip } = await pending;
	// Reading the viewer id BEFORE awaiting ready (the pre-fix bug) would
	// have captured null here and misclassified the owner as a non-owner.
	assert.equal(isOwner, true);
	assert.equal(shouldClip, false);
});

test('resolveTrackOwnership: settled anon viewer stays a clipped non-owner', async () => {
	const ready = () => Promise.resolve();
	const { isOwner, shouldClip } = await resolveTrackOwnership(
		ready,
		() => null,
		'owner-1',
	);
	assert.equal(isOwner, false);
	assert.equal(shouldClip, true);
});

test('resolveTrackOwnership: no known owner never clips', async () => {
	const ready = () => Promise.resolve();
	const { isOwner, shouldClip } = await resolveTrackOwnership(
		ready,
		() => 'u-1',
		null,
	);
	assert.equal(isOwner, false);
	assert.equal(shouldClip, false);
});
