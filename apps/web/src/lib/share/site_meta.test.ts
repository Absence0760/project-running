import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	SITE_DESCRIPTION,
	buildOrganizationJsonLd,
	buildWebSiteJsonLd,
} from './site_meta';

// ---------------- buildOrganizationJsonLd ----------------

test('buildOrganizationJsonLd — Organization node with absolute url + logo', () => {
	const parsed = JSON.parse(buildOrganizationJsonLd('https://threkir.com'));
	assert.equal(parsed['@context'], 'https://schema.org');
	assert.equal(parsed['@type'], 'Organization');
	assert.equal(parsed.name, 'Threkir');
	assert.equal(parsed.url, 'https://threkir.com/');
	assert.equal(parsed.logo, 'https://threkir.com/icon-512.png');
	assert.equal(parsed.description, SITE_DESCRIPTION);
});

test('buildOrganizationJsonLd — trailing slash on base is normalised (single slash)', () => {
	const parsed = JSON.parse(buildOrganizationJsonLd('https://threkir.com/'));
	assert.equal(parsed.url, 'https://threkir.com/');
	assert.equal(parsed.logo, 'https://threkir.com/icon-512.png');
});

test('buildOrganizationJsonLd — null base yields root-relative urls', () => {
	const parsed = JSON.parse(buildOrganizationJsonLd(null));
	assert.equal(parsed.url, '/');
	assert.equal(parsed.logo, '/icon-512.png');
});

test('buildOrganizationJsonLd — carries no sameAs (omitted until real profiles exist)', () => {
	const parsed = JSON.parse(buildOrganizationJsonLd('https://threkir.com'));
	assert.equal('sameAs' in parsed, false);
});

// ---------------- buildWebSiteJsonLd ----------------

test('buildWebSiteJsonLd — WebSite node with name + url + description', () => {
	const parsed = JSON.parse(buildWebSiteJsonLd('https://threkir.com'));
	assert.equal(parsed['@type'], 'WebSite');
	assert.equal(parsed.name, 'Threkir');
	assert.equal(parsed.url, 'https://threkir.com/');
	assert.equal(parsed.description, SITE_DESCRIPTION);
});

test('buildWebSiteJsonLd — no SearchAction (no public search endpoint to target)', () => {
	const parsed = JSON.parse(buildWebSiteJsonLd('https://threkir.com'));
	assert.equal('potentialAction' in parsed, false);
});

// ---------------- escaping ----------------

test('JSON-LD payloads escape the script-terminating characters', () => {
	// Every builder must run escapeJsonLd so a `</script>` can never
	// terminate the injected element early. The base is templated, not
	// user input, but the escape is defence-in-depth + keeps the payload
	// valid when dropped into HTML verbatim.
	const raw = buildOrganizationJsonLd('https://threkir.com');
	assert.equal(raw.includes('<'), false);
	assert.equal(raw.includes('>'), false);
	// The escaped form must still parse back to valid JSON.
	assert.doesNotThrow(() => JSON.parse(raw));
});
