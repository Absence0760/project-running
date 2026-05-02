// Source-level guards that pin in place the security invariants for
// thumbnail rendering on the web app. Each test reads a source file as
// text and asserts a pattern is present, with a reason a future editor
// can read before deciding it's safe to break.
//
// Mirrors the `thumbnail privacy-zone clipping` group in
// `apps/mobile_android/test/architecture_guards_test.dart` — the two
// rules must stay in lockstep.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('RunTrackPreview routes non-owner fetches through clipTrackForUser', () => {
	// Reason: feed thumbnails are shown to non-owner viewers. Without
	// the clip step the polyline exposes the owner's privacy zones
	// (start / end / interior — see decisions §33). The clip RPC trims
	// them server-side. Removing this call re-introduces a privacy leak
	// — keep it.
	const source = read('src/lib/components/RunTrackPreview.svelte');
	assert.match(
		source,
		/clipTrackForUser/,
		'RunTrackPreview must clip through the privacy-zone RPC for non-owner viewers. See decisions §33.',
	);
});

test('feed page passes ownerUserId to RunTrackPreview', () => {
	// Reason: without the prop, RunTrackPreview can't tell viewer from
	// owner and skips the clip step. Always pass the run owner's id on
	// the feed.
	const source = read('src/routes/feed/+page.svelte');
	assert.match(
		source,
		/<RunTrackPreview[^>]*ownerUserId=/s,
		'Feed page must thread the run owner id into RunTrackPreview so the privacy-zone clip kicks in.',
	);
});
