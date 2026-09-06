// What the SPA shell the five share Lambdas embed actually carries in its
// `<head>`, stated rather than assumed.
//
// The shell is `apps/web/build/200.html` -- adapter-static's SPA fallback,
// which CloudFront serves for every deep link (a missing S3 key answers 403,
// mapped to /200.html at 200). It was `build/index.html` until § 1268, which
// gave that filename back to the prerendered landing page; the site root and
// the deep-link body are different documents now, and this file measures the
// second one. Each injector
// strips some of four signals from it before splicing its own head in, and for
// a long time each carried a comment asserting "adapter-static emits a default
// set that would render as duplicates", which was false of the artifact: the
// shell carried ONE title and none of the other three, so three of the four
// strips acted on nothing. Since § 1167 moved the default title out of the
// template and into the root layout's `<svelte:head>` -- so a prerendered page
// stops shipping two titles, the first of them `Threkir` -- the fallback
// renders no components and carries NO title either, and all four strips act
// on nothing.
//
// They are not deleted, because which state holds is a property of another
// tree: a single `og:` default added to app.html makes all four live again in
// one edit, and so would a share Lambda left embedding `build/index.html`
// after § 1268 -- that file is the landing page now and carries all four.
// `src/lib/seo/spa_shell_filename.test.ts` is what catches the second case;
// this one measures the signals, in EITHER direction.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { countHeadSignals, stripStaleHeadSignals, type HeadSignal } from './head_splice';

const APP_HTML = fileURLToPath(new URL('../../app.html', import.meta.url));
const BUILT_SHELL = fileURLToPath(new URL('../../../build/200.html', import.meta.url));

/// The measured state, re-measured 2026-09-05 against `build/200.html`.
/// `%sveltekit.head%` contributes only the hash-CSP meta and the modulepreload
/// links to a fallback page, so app.html alone decides these four counts and
/// the artifact is checked against it below whenever a build is present. All
/// four have been zero since § 1167 and stayed zero through § 1268: the
/// landing page took the `index.html` filename, it did not take over the
/// shell's job, so the shell still renders no components and the four strips
/// still act on nothing.
const SHELL_SIGNALS: Readonly<Record<HeadSignal, number>> = {
	title: 0,
	social: 0,
	canonical: 0,
	jsonLd: 0,
};

const WHY =
	'The share Lambdas strip these from the shell before splicing their own head in. ' +
	'A signal appearing here means a strip that was dead is now load-bearing (and its ' +
	'injector comment needs re-measuring); a signal disappearing means a strip lost its ' +
	'subject. Both are worth a deliberate decision -- see docs/features/seo.md.';

test('the SPA-shell template carries none of the four head signals', () => {
	assert.deepEqual(countHeadSignals(readFileSync(APP_HTML, 'utf8')), SHELL_SIGNALS, WHY);
});

test('a built shell agrees with the template it was generated from', (t) => {
	if (!existsSync(BUILT_SHELL)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	assert.deepEqual(countHeadSignals(readFileSync(BUILT_SHELL, 'utf8')), SHELL_SIGNALS, WHY);
});

test('no strip has work to do against the shell today', () => {
	// The measured half of the claim each injector comment makes. The shell
	// carries none of the four, so stripping all of them together must be a
	// no-op -- which is a strictly stronger statement than the per-signal form
	// this replaced, and fails the moment any one of them reappears.
	const shell = readFileSync(APP_HTML, 'utf8');
	assert.equal(
		stripStaleHeadSignals(shell, ['title', 'social', 'canonical', 'jsonLd']),
		shell,
		WHY,
	);
});
