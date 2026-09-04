// What the SPA shell the five share Lambdas embed actually carries in its
// `<head>`, stated rather than assumed.
//
// The shell is `apps/web/build/index.html` -- adapter-static's SPA fallback,
// which CloudFront also serves as the site root and for every deep link (a
// missing S3 key answers 403, mapped to /index.html at 200). Each injector
// strips some of four signals from it before splicing its own head in, and for
// a long time each carried a comment asserting "adapter-static emits a default
// set that would render as duplicates", which was false of the artifact: the
// shell carries ONE title and none of the other three, so three of the four
// strips act on nothing today.
//
// They are not deleted, because which state holds is a property of another
// tree: a single `og:` default added to app.html, or the prerendered landing
// page landing at this filename (docs/product/followups.md), makes all four
// live again in one edit. So the claim is measured here instead, and this test
// is what fails when it changes -- in EITHER direction.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { countHeadSignals, stripStaleHeadSignals, type HeadSignal } from './head_splice';

const APP_HTML = fileURLToPath(new URL('../../app.html', import.meta.url));
const BUILT_SHELL = fileURLToPath(new URL('../../../build/index.html', import.meta.url));

/// The measured state, 2026-09-04. `%sveltekit.head%` contributes only the
/// hash-CSP meta and the modulepreload links to a fallback page, so app.html
/// alone decides these four counts and the artifact is checked against it
/// below whenever a build is present.
const SHELL_SIGNALS: Readonly<Record<HeadSignal, number>> = {
	title: 1,
	social: 0,
	canonical: 0,
	jsonLd: 0,
};

const WHY =
	'The share Lambdas strip these from the shell before splicing their own head in. ' +
	'A signal appearing here means a strip that was dead is now load-bearing (and its ' +
	'injector comment needs re-measuring); a signal disappearing means a strip lost its ' +
	'subject. Both are worth a deliberate decision -- see docs/features/seo.md.';

test('the SPA-shell template carries exactly one title and none of the other three signals', () => {
	assert.deepEqual(countHeadSignals(readFileSync(APP_HTML, 'utf8')), SHELL_SIGNALS, WHY);
});

test('a built shell agrees with the template it was generated from', (t) => {
	if (!existsSync(BUILT_SHELL)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	assert.deepEqual(countHeadSignals(readFileSync(BUILT_SHELL, 'utf8')), SHELL_SIGNALS, WHY);
});

test('only the title strip has work to do against the shell today', () => {
	// The measured half of the claim each injector comment makes. Stripping the
	// three signals the shell does not carry must be a no-op on it; stripping
	// the title must not be.
	const shell = readFileSync(APP_HTML, 'utf8');
	assert.equal(stripStaleHeadSignals(shell, ['social', 'canonical', 'jsonLd']), shell);
	assert.notEqual(stripStaleHeadSignals(shell, ['title']), shell);
});
