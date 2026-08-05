import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isEntityId } from './entity_id';

test('accepts a uuid in either case', () => {
	assert.equal(isEntityId('9f1c3a52-0000-4000-8000-000000000001'), true);
	assert.equal(isEntityId('9F1C3A52-0000-4000-8000-000000000001'), true);
});

test('rejects a club slug so an id lookup is never issued for one', () => {
	assert.equal(isEntityId('road-runners'), false);
	assert.equal(isEntityId('9f1c3a52'), false);
	assert.equal(isEntityId('9f1c3a52-0000-4000-8000-000000000001-extra'), false);
});

test('rejects empty and nullish input', () => {
	assert.equal(isEntityId(''), false);
	assert.equal(isEntityId(null), false);
	assert.equal(isEntityId(undefined), false);
});
