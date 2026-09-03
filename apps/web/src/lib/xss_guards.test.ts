// What a rendered markdown answer is allowed to contain. The coach reply is
// model output rendered as HTML, so its allowlists — attributes and URI
// schemes — are the boundary, and both clients carry one.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('CoachChat DOMPurify config disallows the `class` attribute', () => {
	// Reason: an LLM-emitted `<span class="modal-backdrop">` would
	// otherwise pick up the global app.css class and overlay the page,
	// a clickjacking vector flagged in audit pass-2 (commit a2ea656).
	// `class` must NOT appear in COACH_ALLOWED_ATTR; ALLOW_DATA_ATTR
	// must be false. The afterSanitizeAttributes hook must force
	// target=_blank + rel=noopener on every <a> so an LLM-emitted link
	// can't reach back into window.opener (reverse-tab phishing).
	const source = read('src/lib/coach/markdown.ts');
	const attrMatch = source.match(/COACH_ALLOWED_ATTR\s*=\s*\[([^\]]*)\]/);
	assert.ok(
		attrMatch,
		'Could not locate COACH_ALLOWED_ATTR — has it been renamed? See coach/markdown.ts.',
	);
	assert.doesNotMatch(
		attrMatch![1],
		/['"]class['"]/,
		'COACH_ALLOWED_ATTR must NOT include "class" — LLM-controlled class names can hijack global app.css selectors. See decisions audit pass-2.',
	);
	assert.match(
		source,
		/ALLOW_DATA_ATTR\s*:\s*false/,
		'CoachChat sanitiser must set ALLOW_DATA_ATTR=false — data-* attributes are a class-equivalent escape hatch.',
	);
	assert.match(
		source,
		/afterSanitizeAttributes[\s\S]{0,400}target['"\s,:=]+_blank/,
		'CoachChat sanitiser must force target=_blank on every <a> via afterSanitizeAttributes.',
	);
	assert.match(
		source,
		/afterSanitizeAttributes[\s\S]{0,400}noopener/,
		'CoachChat sanitiser must force rel="noopener" on every <a> — closes the window.opener reverse-tab phishing vector.',
	);
});

test('CoachChat DOMPurify config locks ALLOWED_URI_REGEXP to https/http/mailto', () => {
	// Reason: DOMPurify's default URI regexp is permissive — it accepts
	// `tel:`, `sms:`, `xmpp:`, `cid:`, `matrix:`, `callto:` on hrefs.
	// A coach response containing `[call](tel:+1...)` would otherwise
	// open the OS dialer on mobile browsers. This guard pins the
	// allow-list to the same scheme set as the mobile `_onCoachLinkTap`
	// (http, https, mailto). /audit/all xss Medium 2026-05-07.
	const source = read('src/lib/coach/markdown.ts');
	assert.match(
		source,
		/ALLOWED_URI_REGEXP\s*:\s*\/\^[^/]*https?[^/]*mailto[^/]*\//i,
		'CoachChat sanitiser must set ALLOWED_URI_REGEXP to /^(?:https?|mailto):/i. Removing it re-opens the tel:/sms:/xmpp: surface.',
	);
});

test('Mobile coach markdown allowlists http(s) + mailto schemes only', () => {
	// Reason: flutter_markdown's default onTapLink calls url_launcher on
	// every URI including `javascript:`, `file:`, `data:`. The web path
	// strips those via DOMPurify; mobile didn't until pass-2 (commit
	// 54ef7ce). The allowlist must include http + https + mailto only —
	// adding `tel:` etc. would silently widen the surface.
	for (const path of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
	]) {
		const source = read(path);
		const allowMatch = source.match(/allowedSchemes\s*=\s*\{([^}]*)\}/);
		assert.ok(
			allowMatch,
			`${path} must declare an explicit allowedSchemes set for the coach onTapLink handler.`,
		);
		const set = allowMatch![1];
		assert.match(set, /['"]http['"]/, `${path}: allowedSchemes must include 'http'.`);
		assert.match(set, /['"]https['"]/, `${path}: allowedSchemes must include 'https'.`);
		assert.match(set, /['"]mailto['"]/, `${path}: allowedSchemes must include 'mailto'.`);
		// Hard rules — none of these may appear.
		for (const banned of ['javascript', 'file', 'data', 'tel']) {
			assert.doesNotMatch(
				set,
				new RegExp(`['"]${banned}['"]`),
				`${path}: allowedSchemes must NOT include '${banned}' — see audit pass-2 commit 54ef7ce.`,
			);
		}
	}
});
