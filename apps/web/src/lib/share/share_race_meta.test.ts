import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildRaceShareTitle,
	buildRaceShareDescription,
	buildRaceShareCanonical,
	buildRaceJsonLd,
} from './share_race_meta';
import type { SharedRace } from './share_race_lookup';

function r(over: Partial<SharedRace> = {}): SharedRace {
	return {
		id: 'r-1',
		name: 'London Marathon',
		race_date: '2026-04-26',
		distance_m: 42195,
		location_label: 'London, UK',
		entry_url: 'https://example.com/enter',
		is_verified: true,
		...over,
	};
}

test('buildRaceShareTitle — name + site suffix, generic fallback', () => {
	assert.equal(buildRaceShareTitle(r()), 'London Marathon — Threkir');
	assert.equal(buildRaceShareTitle(null), 'Race — Threkir');
});

test('buildRaceShareDescription — leads with date · distance · location', () => {
	const d = buildRaceShareDescription(r());
	assert.match(d, /26 Apr 2026/);
	assert.match(d, /42\.20 km/);
	assert.match(d, /London, UK/);
});

test('buildRaceShareCanonical — absolute share/race URL, slash-normalised', () => {
	assert.equal(
		buildRaceShareCanonical('https://threkir.com/', 'r-1'),
		'https://threkir.com/share/race/r-1'
	);
	assert.equal(buildRaceShareCanonical(null, 'r-1'), '/share/race/r-1');
});

test('buildRaceJsonLd — SportsEvent with startDate + coarse location, no geo', () => {
	const obj = JSON.parse(buildRaceJsonLd(r(), { id: 'r-1', base: 'https://threkir.com' }));
	assert.equal(obj['@type'], 'SportsEvent');
	assert.equal(obj.name, 'London Marathon');
	assert.equal(obj.url, 'https://threkir.com/share/race/r-1');
	assert.equal(obj.startDate, '2026-04-26');
	assert.equal(obj.sport, 'Running');
	assert.equal(obj.location['@type'], 'Place');
	assert.equal(obj.location.name, 'London, UK');
	assert.equal('geo' in obj, false);
});

test('buildRaceJsonLd — escapes angle brackets so a name cannot break out of the script tag', () => {
	const json = buildRaceJsonLd(r({ name: '</script><b>x</b>' }), {
		id: 'r-1',
		base: 'https://threkir.com',
	});
	assert.ok(!json.includes('<'));
	assert.ok(!json.includes('>'));
	assert.equal(JSON.parse(json).name, '</script><b>x</b>');
});
