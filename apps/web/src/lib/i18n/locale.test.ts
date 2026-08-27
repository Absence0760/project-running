import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	DEFAULT_LOCALE,
	dirForLocale,
	isSupportedLocale,
	negotiateLocale,
	parseAcceptLanguage,
} from './locale';

test('isSupportedLocale accepts canonical locales only', () => {
	assert.equal(isSupportedLocale('en'), true);
	assert.equal(isSupportedLocale('pt-BR'), true);
	assert.equal(isSupportedLocale('pt-br'), false); // not canonical-cased
	assert.equal(isSupportedLocale('it'), false);
	assert.equal(isSupportedLocale(null), false);
	assert.equal(isSupportedLocale(undefined), false);
});

test('dirForLocale is ltr for the starter set, rtl for Arabic/Hebrew bases', () => {
	for (const l of ['en', 'de', 'fr', 'es', 'ja', 'pt-BR', 'pt-PT']) {
		assert.equal(dirForLocale(l), 'ltr', l);
	}
	assert.equal(dirForLocale('ar'), 'rtl');
	assert.equal(dirForLocale('he-IL'), 'rtl');
	assert.equal(dirForLocale('fa'), 'rtl');
});

test('parseAcceptLanguage orders tags by q-weight and drops *', () => {
	assert.deepEqual(parseAcceptLanguage('de-DE,de;q=0.9,en;q=0.8,*;q=0.5'), [
		'de-DE',
		'de',
		'en',
	]);
	assert.deepEqual(parseAcceptLanguage('fr'), ['fr']);
	assert.deepEqual(parseAcceptLanguage(''), []);
});

test('negotiateLocale: a stored canonical preference wins outright', () => {
	assert.equal(negotiateLocale('de-DE', 'ja'), 'ja');
	assert.equal(negotiateLocale(null, 'pt-BR'), 'pt-BR');
});

test('negotiateLocale: a stored non-canonical tag resolves by base', () => {
	assert.equal(negotiateLocale(null, 'fr-CA'), 'fr');
	// Angola writes the European orthography and we carry no pt-AO catalogue,
	// so the base fallback is the one that serves it.
	assert.equal(negotiateLocale(null, 'pt-AO'), 'pt-PT');
});

test('negotiateLocale: both Portuguese catalogues are reachable by their own tag', () => {
	// The defect this closes: a Lisbon browser sends pt-PT and used to land on
	// the Brazilian catalogue, answering differently from the phone, which has
	// shipped a European catalogue since 2026-08-06.
	assert.equal(negotiateLocale('pt-PT'), 'pt-PT');
	assert.equal(negotiateLocale('pt-BR'), 'pt-BR');
	assert.equal(negotiateLocale(null, 'pt-PT'), 'pt-PT');
	assert.equal(negotiateLocale(null, 'pt-BR'), 'pt-BR');
	// A bare `pt` is nobody's real browser tag — every client reports the
	// region — so it goes to the variant that has no other tag to arrive on.
	assert.equal(negotiateLocale('pt'), 'pt-PT');
});

test('negotiateLocale: priority wins — a higher-q tag is matched (exact or base) before a lower-q one', () => {
	// Highest-q tag with any match wins.
	assert.equal(negotiateLocale('pt-BR;q=0.9,de;q=1.0'), 'de');
	assert.equal(negotiateLocale('en-GB,en;q=0.9'), 'en');
	// Regression (F1): a lower-priority EXACT tag must NOT beat a
	// higher-priority tag we only carry by base language. fr-CA (q=1) has
	// no exact catalogue but resolves to the fr base; en (q=0.5) is exact.
	// The user's top preference is French, so fr must win.
	assert.equal(negotiateLocale('fr-CA,en;q=0.5'), 'fr');
	assert.equal(negotiateLocale('de-AT;q=1.0,en;q=0.8'), 'de');
});

test('negotiateLocale: base-language fallback for unshipped regional variants', () => {
	assert.equal(negotiateLocale('de-AT'), 'de');
	assert.equal(negotiateLocale('es-MX,es;q=0.9'), 'es');
	assert.equal(negotiateLocale('pt-MZ'), 'pt-PT');
});

test('negotiateLocale: unsupported languages fall back to the default', () => {
	assert.equal(negotiateLocale('it-IT,it;q=0.9'), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(null, null), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(undefined), DEFAULT_LOCALE);
});
