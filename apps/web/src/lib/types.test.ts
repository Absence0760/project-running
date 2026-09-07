import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	parseActivityType,
	parseIntegrationProvider,
	parseJoinPolicy,
	parsePreferredUnit,
	parseRouteSurface,
	parseRunSource,
	parseSubscriptionTier,
	type ActivityType,
	type IntegrationProvider,
	type JoinPolicy,
	type RouteSurface,
	type RunSource,
} from './types';

test('parseRunSource — every valid RunSource passes through', () => {
	const all: RunSource[] = [
		'app',
		'watch',
		'healthkit',
		'healthconnect',
		'strava',
		'garmin',
		'parkrun',
		'race',
	];
	for (const s of all) {
		assert.equal(parseRunSource(s), s);
	}
});

test('parseRunSource — null falls back to app', () => {
	assert.equal(parseRunSource(null), 'app');
});

test('parseRunSource — undefined falls back to app', () => {
	assert.equal(parseRunSource(undefined), 'app');
});

test('parseRunSource — empty string falls back to app', () => {
	assert.equal(parseRunSource(''), 'app');
});

test('parseRunSource — unknown string falls back to app', () => {
	assert.equal(parseRunSource('zwift'), 'app');
});

test('parseRunSource — case-mismatched falls back to app', () => {
	assert.equal(parseRunSource('Watch'), 'app');
	assert.equal(parseRunSource('STRAVA'), 'app');
});

test('parseRouteSurface — every valid RouteSurface passes through', () => {
	const all: RouteSurface[] = ['road', 'trail', 'mixed'];
	for (const s of all) {
		assert.equal(parseRouteSurface(s), s);
	}
});

test('parseRouteSurface — null passes through as null (surface-less route)', () => {
	assert.equal(parseRouteSurface(null), null);
});

test('parseRouteSurface — undefined collapses to null', () => {
	assert.equal(parseRouteSurface(undefined), null);
});

test('parseRouteSurface — empty string collapses to null', () => {
	assert.equal(parseRouteSurface(''), null);
});

test('parseRouteSurface — unknown string collapses to null', () => {
	assert.equal(parseRouteSurface('gravel'), null);
});

test('parseRouteSurface — case-mismatched collapses to null', () => {
	assert.equal(parseRouteSurface('Trail'), null);
	assert.equal(parseRouteSurface('ROAD'), null);
});

// The four narrows below exist because the generated row and RPC types spell
// every one of these columns `string`, and each read used to assign that
// straight into its union. Two of the four fallbacks are load-bearing rather
// than cosmetic and are pinned as such.

test('parseActivityType — every valid ActivityType passes through', () => {
	const all: ActivityType[] = ['run', 'walk', 'hike', 'cycle', 'stroller'];
	for (const a of all) assert.equal(parseActivityType(a), a);
});

test('parseActivityType — an unknown, empty, null or mis-cased value reads as run', () => {
	assert.equal(parseActivityType('swim'), 'run');
	assert.equal(parseActivityType(''), 'run');
	assert.equal(parseActivityType(null), 'run');
	assert.equal(parseActivityType(undefined), 'run');
	assert.equal(parseActivityType('Run'), 'run');
});

test('parseIntegrationProvider — every valid IntegrationProvider passes through', () => {
	const all: IntegrationProvider[] = ['strava', 'garmin', 'parkrun', 'runsignup'];
	for (const p of all) assert.equal(parseIntegrationProvider(p), p);
});

test('parseIntegrationProvider — an unrecognised provider is null, not a guess', () => {
	// The connected-integrations list switches on the provider to pick a card;
	// a row this build has no branch for renders as nothing either way, so
	// dropping it is honest where mistyping it is not.
	assert.equal(parseIntegrationProvider('polar'), null);
	assert.equal(parseIntegrationProvider(''), null);
	assert.equal(parseIntegrationProvider(null), null);
	assert.equal(parseIntegrationProvider('Strava'), null);
});

test('parsePreferredUnit — mi passes through, everything else is km', () => {
	assert.equal(parsePreferredUnit('mi'), 'mi');
	assert.equal(parsePreferredUnit('km'), 'km');
	assert.equal(parsePreferredUnit('miles'), 'km');
	assert.equal(parsePreferredUnit(null), 'km');
	assert.equal(parsePreferredUnit('MI'), 'km');
});

test('parseSubscriptionTier — every valid SubscriptionTier passes through', () => {
	assert.equal(parseSubscriptionTier('free'), 'free');
	assert.equal(parseSubscriptionTier('pro'), 'pro');
	assert.equal(parseSubscriptionTier('lifetime'), 'lifetime');
});

test('parseSubscriptionTier — an unrecognised tier fails CLOSED to free', () => {
	// The one fallback in this file with a security consequence: the paywall
	// reads the tier, so a value the build does not understand reading as
	// 'pro' would open every gated surface. 'Pro' is included deliberately —
	// a case-mismatched entitlement must not be honoured either.
	assert.equal(parseSubscriptionTier('enterprise'), 'free');
	assert.equal(parseSubscriptionTier('Pro'), 'free');
	assert.equal(parseSubscriptionTier(''), 'free');
	assert.equal(parseSubscriptionTier(null), 'free');
	assert.equal(parseSubscriptionTier(undefined), 'free');
});

test('parseJoinPolicy — every valid JoinPolicy passes through', () => {
	const all: JoinPolicy[] = ['open', 'request', 'invite'];
	for (const j of all) assert.equal(parseJoinPolicy(j), j);
});

test('parseJoinPolicy — an unrecognised policy is request, neither open nor closed', () => {
	// 'open' would let a stranger join a club whose policy this build cannot
	// read; 'invite' would strand every legitimate applicant. 'request' is the
	// only fallback that does neither.
	assert.equal(parseJoinPolicy('approval'), 'request');
	assert.equal(parseJoinPolicy(''), 'request');
	assert.equal(parseJoinPolicy(null), 'request');
	assert.equal(parseJoinPolicy('Open'), 'request');
});
