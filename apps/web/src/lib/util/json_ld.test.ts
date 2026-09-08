import { test } from 'node:test';
import assert from 'node:assert/strict';

import { serialiseJsonLd } from './json_ld';
import { escapeHtml } from './html_escape';

test('serialiseJsonLd — a graph round-trips through JSON.parse unchanged', () => {
	const graph = {
		'@context': 'https://schema.org',
		'@type': 'WebPage',
		name: 'Sunday long run',
		numberOfItems: 3,
		breadcrumb: { '@type': 'BreadcrumbList', itemListElement: [{ position: 1 }] },
	};
	assert.deepEqual(JSON.parse(serialiseJsonLd(graph)), graph);
});

test('serialiseJsonLd — a value spelling </script> cannot terminate the element', () => {
	const hostile = '</script><img src=x onerror=alert(1)>';
	const out = serialiseJsonLd({ name: hostile });
	assert.ok(!out.includes('<'), 'a literal < survived');
	assert.ok(!out.includes('>'), 'a literal > survived');
	assert.ok(!out.includes('&'), 'a literal & survived');
	assert.equal(JSON.parse(out).name, hostile);
});

test('serialiseJsonLd — <!-- cannot appear, so the script-data-escaped state is unreachable', () => {
	const out = serialiseJsonLd({ name: '<!--<script>alert(1)</script>-->' });
	assert.ok(!out.includes('<!--'), 'an HTML comment open survived');
	assert.equal(JSON.parse(out).name, '<!--<script>alert(1)</script>-->');
});

// The form is load-bearing, not incidental: a <script> is a raw-text element,
// so an entity reference is NOT decoded inside it. escapeHtml's output would
// reach the JSON parser as the literal characters `&lt;` and corrupt the value
// while making it no safer.
test('serialiseJsonLd — escapes to JSON\'s \\u003c, never to an HTML entity', () => {
	const out = serialiseJsonLd({ name: '<' });
	assert.equal(out, '{"name":"\\u003c"}');
	assert.ok(!out.includes(escapeHtml('<')), 'the entity form reached the payload');
	assert.equal(JSON.parse(out).name, '<');
});

test('serialiseJsonLd — the escape lands inside string values and leaves the structure alone', () => {
	assert.equal(
		serialiseJsonLd({ '@type': 'WebPage', name: 'a<b', n: 1 }),
		'{"@type":"WebPage","name":"a\\u003cb","n":1}',
	);
});

test('serialiseJsonLd — a value that literally spells \\u003c is not decoded to <', () => {
	const literal = '\\u003cscript\\u003e';
	const out = serialiseJsonLd({ name: literal });
	assert.ok(!out.includes('<'));
	assert.equal(JSON.parse(out).name, literal);
});
