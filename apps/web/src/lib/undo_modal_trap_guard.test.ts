// Source-level guards for the in-modal half of the undo contract
// (decisions § 514's open question). Round 11 built an undo on a delete
// that lives inside a `Modal`, found the Tab trap made the bar
// pointer-only, and reverted it. The resolution is that `Modal.svelte`'s
// ring admits one designated outside host, `[data-modal-trap-include]`,
// which `UndoBar` carries. These read the sources as text so a refactor
// that quietly drops either half fails here instead of shipping an
// affordance mouse users can reach and keyboard users cannot.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test("Modal.svelte's Tab ring admits designated hosts outside the dialog", () => {
	// Reason: without this the trap is exactly as wide as the dialog, and
	// any transient global affordance a modal action produces is
	// unreachable by keyboard — WCAG 2.1.1. Reverting to a
	// dialog-only querySelectorAll re-creates the dead end.
	const source = read('src/lib/components/Modal.svelte');
	assert.match(
		source,
		/querySelectorAll<HTMLElement>\('\[data-modal-trap-include\]'\)/,
		'the trap must collect focusables from [data-modal-trap-include] hosts',
	);
	assert.match(
		source,
		/\.filter\(\(host\) => !dialogEl\.contains\(host\)\)/,
		'a host already inside the dialog must not be counted twice',
	);
});

test('the outside ring is appended after the dialog, never before', () => {
	// Reason: WCAG 2.4.3. The included offer is a CONSEQUENCE of an action
	// taken in the dialog, so it reads after the dialog's own controls —
	// and that order must not depend on where in the layout the host is
	// mounted, which a DOM-order concatenation would leak.
	const source = read('src/lib/components/Modal.svelte');
	assert.match(
		source,
		/const ring = \[\.\.\.dialogRing, \.\.\.outerRing\]/,
		'ring order must be dialog-first',
	);
});

test('UndoBar puts the attribute on the always-mounted live region', () => {
	// Reason: two invariants at once. The region is always in the DOM (a
	// live region that arrives already populated is not announced), and it
	// is the region — not the conditional bar — that carries the trap
	// opt-in, so the attribute is present before the offer exists and the
	// bar's buttons are in the ring the moment they render.
	const source = read('src/lib/components/UndoBar.svelte');
	const region = source.slice(
		source.indexOf('<div'),
		source.indexOf('{#if pending}'),
	);
	assert.match(region, /class="undo-region"/, 'region markup not found');
	assert.match(
		region,
		/data-modal-trap-include/,
		'the trap opt-in must sit on the always-mounted region',
	);
	assert.match(region, /role="status"/, 'the live region must stay outside the {#if}');
});
