import { test } from 'node:test';
import assert from 'node:assert/strict';
import { extractProfileId } from './profile_query';

const UUID = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

test('bare uuid is returned lowercased', () => {
	assert.equal(extractProfileId(UUID), UUID);
	assert.equal(extractProfileId(`  ${UUID}  `), UUID);
});

test('an uppercase uuid is normalised to lowercase', () => {
	assert.equal(extractProfileId(UUID.toUpperCase()), UUID);
});

test('a /u/<uuid> path resolves', () => {
	assert.equal(extractProfileId(`/u/${UUID}`), UUID);
});

test('a full profile URL resolves', () => {
	assert.equal(extractProfileId(`https://threkir.com/u/${UUID}`), UUID);
});

test('a /u/<uuid> URL with a query/tab or trailing slash resolves', () => {
	assert.equal(extractProfileId(`https://threkir.com/u/${UUID}?tab=runs`), UUID);
	assert.equal(extractProfileId(`/u/${UUID}/`), UUID);
	assert.equal(extractProfileId(`/u/${UUID}#top`), UUID);
});

test('a plain name is not a profile id', () => {
	assert.equal(extractProfileId('Jane Doe'), null);
	assert.equal(extractProfileId('janedoe'), null);
	assert.equal(extractProfileId('@janedoe'), null);
});

test('empty / whitespace input is null', () => {
	assert.equal(extractProfileId(''), null);
	assert.equal(extractProfileId('   '), null);
});

test('a malformed uuid is not accepted', () => {
	assert.equal(extractProfileId('3f2504e0-4f89-41d3-9a0c'), null);
	assert.equal(extractProfileId('zzzzzzzz-4f89-41d3-9a0c-0305e82c3301'), null);
});

test('a uuid embedded in arbitrary text (not after /u/) is ignored', () => {
	assert.equal(extractProfileId(`hello ${UUID} world`), null);
	assert.equal(extractProfileId(`/runs/${UUID}`), null);
});
