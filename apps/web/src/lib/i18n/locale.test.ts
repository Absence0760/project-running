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
	for (const l of ['en', 'de', 'fr', 'es', 'ja', 'pt-BR']) {
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
	assert.equal(negotiateLocale(null, 'pt-PT'), 'pt-BR');
	assert.equal(negotiateLocale(null, 'fr-CA'), 'fr');
});

test('negotiateLocale: exact match beats base match across the q-list', () => {
	// pt-BR is exact even though de appears first only at lower q.
	assert.equal(negotiateLocale('pt-BR;q=0.9,de;q=1.0'), 'de');
	assert.equal(negotiateLocale('en-GB,en;q=0.9'), 'en');
});

test('negotiateLocale: base-language fallback for unshipped regional variants', () => {
	assert.equal(negotiateLocale('de-AT'), 'de');
	assert.equal(negotiateLocale('es-MX,es;q=0.9'), 'es');
	assert.equal(negotiateLocale('pt-PT'), 'pt-BR');
});

test('negotiateLocale: unsupported languages fall back to the default', () => {
	assert.equal(negotiateLocale('it-IT,it;q=0.9'), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(null, null), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(undefined), DEFAULT_LOCALE);
});
