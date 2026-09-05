import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isTrackOwner, resolveTrackOwnership } from './track_ownership';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { stripComments } from '../core/strip_comments';

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

// ── Source guard: the run-detail page's own owner/non-owner classification ──
//
// `isTrackOwner` decides ownership from two ids. `/runs/[id]` decides it from
// a FAILED READ, which is a different question with a different failure mode:
// `fetchRunById` returning no row means either "not yours" or "could not find
// out", and only the first licenses the non-owner branch.

test('the run-detail page only falls back to public attribution on a real not-yours', () => {
	// `public_runs` has no owner exclusion (`where r.is_public = true`), so the
	// attribution read succeeds on the viewer's OWN public run. When a
	// transient failure on the wide owner read was allowed to reach it, the
	// owner landed on the read-only stranger view — back-link to their own
	// profile, "a run by <themselves>", and no edit / delete / visibility /
	// GPX / save-as-route / rematch control — with the retry card suppressed
	// because the template tests `otherRunOwner` before `loadError`.
	const page = stripComments(
		readFileSync(resolve(import.meta.dirname, '../../routes/runs/[id]/+page.svelte'), 'utf-8'),
	);
	const call = page
		.split('\n')
		.find((l) => l.includes('otherRunOwner = ') && l.includes('fetchPublicRunAttribution'));
	assert.ok(call, 'the attribution fallback moved — re-anchor this guard');
	assert.match(
		call,
		/if \(!runError\)/,
		'the fallback must be gated on the owner read having answered — an errored read is not evidence of anything about ownership',
	);
});
