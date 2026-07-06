import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildProfileShareTitle,
	buildProfileShareDescription,
	buildProfileShareCanonical,
	buildProfileJsonLd,
	profileDisplayName,
} from './share_profile_meta';
import type { SharedProfile } from './share_profile_lookup';

function p(over: Partial<SharedProfile> = {}): SharedProfile {
	return { id: 'u-1', display_name: 'Jane Runner', avatar_url: 'https://cdn/x.png', ...over };
}

test('profileDisplayName — falls back to Runner when empty', () => {
	assert.equal(profileDisplayName(p({ display_name: null })), 'Runner');
	assert.equal(profileDisplayName(null), 'Runner');
	assert.equal(profileDisplayName(p()), 'Jane Runner');
});

test('buildProfileShareTitle — name + site suffix, generic fallback', () => {
	assert.equal(buildProfileShareTitle(p()), 'Jane Runner — Threkir');
	assert.equal(buildProfileShareTitle(null), 'Runner — Threkir');
});

test('buildProfileShareDescription — mentions the runner + Threkir', () => {
	assert.match(buildProfileShareDescription(p()), /Follow Jane Runner's running on Threkir/);
	assert.equal(buildProfileShareDescription(null), 'A runner on Threkir.');
});

test('buildProfileShareCanonical — absolute share/profile URL, slash-normalised', () => {
	assert.equal(
		buildProfileShareCanonical('https://threkir.com/', 'u-1'),
		'https://threkir.com/share/profile/u-1'
	);
	assert.equal(buildProfileShareCanonical(null, 'u-1'), '/share/profile/u-1');
});

test('buildProfileJsonLd — ProfilePage with a Person mainEntity + avatar image, no private fields', () => {
	const obj = JSON.parse(buildProfileJsonLd(p(), { id: 'u-1', base: 'https://threkir.com' }));
	assert.equal(obj['@type'], 'ProfilePage');
	assert.equal(obj.url, 'https://threkir.com/share/profile/u-1');
	assert.equal(obj.mainEntity['@type'], 'Person');
	assert.equal(obj.mainEntity.name, 'Jane Runner');
	assert.equal(obj.mainEntity.image, 'https://cdn/x.png');
	// No location / email / private field.
	assert.equal('email' in obj.mainEntity, false);
	assert.equal('address' in obj.mainEntity, false);
});

test('buildProfileJsonLd — no avatar omits the image', () => {
	const obj = JSON.parse(
		buildProfileJsonLd(p({ avatar_url: null }), { id: 'u-1', base: 'https://threkir.com' })
	);
	assert.equal('image' in obj.mainEntity, false);
});

test('buildProfileJsonLd — escapes angle brackets so a name cannot break out of the script tag', () => {
	const json = buildProfileJsonLd(p({ display_name: '</script><b>x</b>' }), {
		id: 'u-1',
		base: 'https://threkir.com',
	});
	assert.ok(!json.includes('<'));
	assert.ok(!json.includes('>'));
	assert.equal(JSON.parse(json).mainEntity.name, '</script><b>x</b>');
});
