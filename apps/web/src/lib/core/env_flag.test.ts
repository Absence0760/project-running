import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isTruthyFlagValue } from './env_flag';

test('isTruthyFlagValue — accepts every affirmative literal', () => {
	for (const v of ['1', 'true', 'yes', 'on']) {
		assert.equal(isTruthyFlagValue(v), true, `${v} should enable`);
	}
});

test('isTruthyFlagValue — affirmatives are case-insensitive', () => {
	for (const v of ['TRUE', 'True', 'YES', 'On', 'ON']) {
		assert.equal(isTruthyFlagValue(v), true, `${v} should enable`);
	}
});

test('isTruthyFlagValue — surrounding whitespace is trimmed', () => {
	for (const v of [' true ', '\t1', 'yes\n', '  on  ']) {
		assert.equal(isTruthyFlagValue(v), true, `"${v}" should enable`);
	}
});

test('isTruthyFlagValue — fail-closed for unset / empty', () => {
	for (const v of [null, undefined, '', '   ']) {
		assert.equal(isTruthyFlagValue(v), false, `${String(v)} should stay off`);
	}
});

test('isTruthyFlagValue — fail-closed for negatives + junk', () => {
	for (const v of ['0', 'false', 'no', 'off', 'enabled', 'y', 't', '2', 'truthy']) {
		assert.equal(isTruthyFlagValue(v), false, `${v} should stay off`);
	}
});
