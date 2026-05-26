import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TIER_LIMITS, emptyUsage } from './types';

test('emptyUsage — returns a fresh zeroed object every call', () => {
	const a = emptyUsage();
	const b = emptyUsage();
	assert.notEqual(a, b, 'must not be a shared reference');
	assert.equal(a.cache_creation_input_tokens, 0);
	assert.equal(a.cache_read_input_tokens, 0);
	assert.equal(a.input_tokens, 0);
	assert.equal(a.output_tokens, 0);
});

test('emptyUsage — caller can mutate without leaking back to a fresh emptyUsage', () => {
	const a = emptyUsage();
	a.input_tokens = 999;
	const b = emptyUsage();
	assert.equal(b.input_tokens, 0);
});

test('TIER_LIMITS.free — finite daily cap so anonymous abuse cannot drain quota', () => {
	assert.ok(Number.isFinite(TIER_LIMITS.free.dailyLimit));
	assert.ok(TIER_LIMITS.free.dailyLimit > 0);
	assert.ok(TIER_LIMITS.free.maxTokens > 0);
	assert.ok(TIER_LIMITS.free.maxRunsLimit > 0);
});

test('TIER_LIMITS.pro — finite daily cap (bounds Anthropic spend per stolen Pro session), larger token + runs windows than free', () => {
	assert.ok(Number.isFinite(TIER_LIMITS.pro.dailyLimit));
	assert.ok(TIER_LIMITS.pro.dailyLimit > TIER_LIMITS.free.dailyLimit);
	assert.ok(TIER_LIMITS.pro.maxTokens > TIER_LIMITS.free.maxTokens);
	assert.ok(TIER_LIMITS.pro.maxRunsLimit > TIER_LIMITS.free.maxRunsLimit);
});
