import { test } from 'node:test';
import assert from 'node:assert/strict';
import { accountLabel } from './account_label.js';

test('accountLabel: returns the display name when present', () => {
	assert.equal(accountLabel('Jared Howard'), 'Jared Howard');
});

test('accountLabel: null display name falls back to "Account", never the email', () => {
	assert.equal(accountLabel(null), 'Account');
});

test('accountLabel: undefined display name falls back to "Account"', () => {
	assert.equal(accountLabel(undefined), 'Account');
});

test('accountLabel: empty / whitespace-only display name falls back to "Account"', () => {
	assert.equal(accountLabel(''), 'Account');
	assert.equal(accountLabel('   '), 'Account');
});

test('accountLabel: trims surrounding whitespace on a real name', () => {
	assert.equal(accountLabel('  Alex Chen  '), 'Alex Chen');
});
