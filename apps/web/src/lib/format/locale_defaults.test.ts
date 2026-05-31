import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { defaultUnitForLocale, defaultWeekStartForLocale } from './locale_defaults';

test('defaultUnitForLocale → mi for imperial regions, km otherwise', () => {
	assert.equal(defaultUnitForLocale('en-US'), 'mi');
	assert.equal(defaultUnitForLocale('en-GB'), 'mi');
	assert.equal(defaultUnitForLocale('en-LR'), 'mi');
	assert.equal(defaultUnitForLocale('my-MM'), 'mi');
	assert.equal(defaultUnitForLocale('de-DE'), 'km');
	assert.equal(defaultUnitForLocale('fr-FR'), 'km');
	assert.equal(defaultUnitForLocale('en-AU'), 'km');
	assert.equal(defaultUnitForLocale('ja-JP'), 'km');
});

test('defaultUnitForLocale defaults to km for an unparseable / region-less locale', () => {
	assert.equal(defaultUnitForLocale('en'), 'km');
	assert.equal(defaultUnitForLocale(''), 'km');
	assert.equal(defaultUnitForLocale('not-a-locale!!'), 'km');
});

test('defaultWeekStartForLocale → sunday for US, monday for Europe', () => {
	assert.equal(defaultWeekStartForLocale('en-US'), 'sunday');
	assert.equal(defaultWeekStartForLocale('en-CA'), 'sunday');
	assert.equal(defaultWeekStartForLocale('de-DE'), 'monday');
	assert.equal(defaultWeekStartForLocale('fr-FR'), 'monday');
	assert.equal(defaultWeekStartForLocale('en-GB'), 'monday');
});

test('defaultWeekStartForLocale defaults to monday for a region-less locale', () => {
	// Region-less stays on the neutral ISO/Monday default (not Intl's
	// 'en' → en-US → Sunday maximization).
	assert.equal(defaultWeekStartForLocale('en'), 'monday');
	assert.equal(defaultWeekStartForLocale(''), 'monday');
	assert.equal(defaultWeekStartForLocale('fr'), 'monday');
});
