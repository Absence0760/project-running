import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderCoachMarkdown } from './markdown.js';

// The `class` attribute is deliberately excluded from COACH_ALLOWED_ATTR so an
// LLM-emitted `<span class="modal-backdrop">` can't pick up the global overlay
// CSS and clickjack the page (audit-xss L1). This pins that invariant — it
// fails if a future edit adds `class` to the allow-list.
test('renderCoachMarkdown strips class attributes from LLM-emitted HTML', () => {
	const out = renderCoachMarkdown('<span class="modal-backdrop">trap</span>');
	assert.ok(out.includes('trap'), 'text content is preserved');
	assert.ok(!/class\s*=/.test(out), 'no class attribute survives sanitisation');
	assert.ok(!out.includes('modal-backdrop'), 'the global class name does not survive');
});

test('renderCoachMarkdown drops a javascript: link href but keeps the text', () => {
	const out = renderCoachMarkdown('[click](javascript:alert(document.cookie))');
	assert.ok(!out.toLowerCase().includes('javascript:'), 'javascript: scheme is removed');
	assert.ok(out.includes('click'), 'link text is preserved');
});

test('renderCoachMarkdown keeps an https link and forces target/rel', () => {
	const out = renderCoachMarkdown('[ok](https://threkir.com)');
	assert.ok(out.includes('href="https://threkir.com"'), 'https href survives');
	assert.ok(out.includes('rel="noopener noreferrer"'), 'rel is forced on every anchor');
	assert.ok(out.includes('target="_blank"'), 'target is forced on every anchor');
});

test('renderCoachMarkdown strips an event-handler attribute', () => {
	const out = renderCoachMarkdown('<img src="x" onerror="alert(1)">');
	assert.ok(!/onerror/i.test(out), 'inline event handler is removed');
});

// Multibyte + punctuation that lives in real LLM replies must survive the
// marked → DOMPurify round-trip verbatim. This pins the same invariant the
// `SSE: special characters` Playwright e2e checks, but at the cheap unit
// layer so a "works for ASCII, drops on multibyte" regression in marked or
// the sanitiser fails here first. Mirrors the e2e's STR exactly.
test('renderCoachMarkdown preserves emoji, accents, em-dash and curly quotes verbatim', () => {
	const STR = 'Pace: `5:30/km` — try “easy effort” 😅 (café tempo)';
	const out = renderCoachMarkdown(STR);
	assert.ok(out.includes('😅'), 'emoji survives');
	assert.ok(out.includes('café'), 'accented character survives');
	assert.ok(out.includes('—'), 'em-dash survives');
	assert.ok(out.includes('“easy effort”'), 'curly quotes survive');
	assert.ok(out.includes('<code>5:30/km</code>'), 'backtick span becomes a code element');
	// The e2e asserts the bubble textContent matches /😅.*café/ — guard the
	// same ordering at the HTML level (emoji precedes café, nothing between
	// drops out).
	assert.match(out, /😅[\s\S]*café/u, 'emoji precedes café with content intact');
});
