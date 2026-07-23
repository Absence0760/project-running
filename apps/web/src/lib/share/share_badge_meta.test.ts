import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildShareBadgeMeta } from './share_badge_meta';
import type { SharedBadge } from './share_badge_lookup';

function badge(over: Partial<SharedBadge> = {}): SharedBadge {
	return {
		id: 'b-1',
		user_id: 'u-1',
		badge_key: 'distance_single',
		tier: 'bronze',
		value_num: 5000,
		earned_at: '2026-05-16T08:00:00Z',
		...over,
	};
}

// ---------------- title ----------------

test('title — resolved badge + display name reads "{who} earned the {label} badge"', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: badge(),
		displayName: 'Alex',
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.title, 'Alex earned the First 5K badge');
});

test('title — resolved badge, no display name reads "{label} — Achievement"', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: badge(),
		displayName: null,
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.title, 'First 5K — Achievement');
});

test('title — whitespace-only display name is treated as absent', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: badge(),
		displayName: '   ',
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.title, 'First 5K — Achievement');
});

test('title — null badge falls back to the generic site title', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: null,
		displayName: 'Alex',
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.title, 'Achievements — Threkir');
});

test('title — unknown badge_key resolves to null and uses the generic title', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: badge({ badge_key: 'no_such_badge' }),
		displayName: 'Alex',
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.title, 'Achievements — Threkir');
});

// ---------------- description ----------------

test('description — resolved badge uses the catalogue desc', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: badge(),
		displayName: null,
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.description, 'Ran 5 km in a single run');
});

test('description — null badge falls back to the unavailable string', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: null,
		displayName: null,
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.description, "This badge isn't available.");
});

// ---------------- canonical + og image ----------------

test('canonical + ogImageUrl — absolute URLs off the site base', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: badge(),
		displayName: null,
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.canonical, 'https://threkir.com/share/badge/b-1');
	assert.equal(meta.ogImageUrl, 'https://threkir.com/og/badge/b-1.png');
});

test('canonical + ogImageUrl — a trailing slash on the site base is stripped', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-2',
		badge: badge(),
		displayName: null,
		siteUrl: 'https://threkir.com/',
	});
	assert.equal(meta.canonical, 'https://threkir.com/share/badge/b-2');
	assert.equal(meta.ogImageUrl, 'https://threkir.com/og/badge/b-2.png');
});

// ---------------- jsonLd ----------------

test('jsonLd — left unset (the badge page carries no structured-data node yet)', () => {
	const meta = buildShareBadgeMeta({
		id: 'b-1',
		badge: badge(),
		displayName: null,
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.jsonLd, undefined);
});
