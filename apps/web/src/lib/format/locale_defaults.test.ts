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

test('defaultWeekStartForLocale agrees with the Dart twin on the CLDR set', () => {
	// The hand-written 16-region table disagreed with CLDR for 19 regions, and
	// web consults Intl first while mobile cannot — so these locales seeded a
	// different week start per platform and `current_week` bucketed the
	// dashboard onto different seven days.
	for (const loc of [
		'pt-PT', 'th-TH', 'id-ID', 'en-SG', 'ar-SA', 'es-DO', 'es-GT', 'es-HN',
		'es-SV', 'es-NI', 'es-PA', 'es-PY', 'en-KE', 'am-ET', 'ur-PK', 'bn-BD',
	]) {
		assert.equal(defaultWeekStartForLocale(loc), 'sunday', loc);
	}
	// Argentina is Monday-first in CLDR; the old table wrongly listed it.
	assert.equal(defaultWeekStartForLocale('es-AR'), 'monday');
	// A Saturday-first region (firstDay 6) is modelled as monday on both sides.
	assert.equal(defaultWeekStartForLocale('ar-EG'), 'monday');
});
