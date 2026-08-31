// Locale negotiation, exhaustively — with the Portuguese split as the case
// the whole module exists for.
//
// decisions.md § 755 shipped a European catalogue on web; § 761 found three
// server-side normalizers folding every `pt*` tag to Brazilian and made all
// four tables agree with this one; § 784 measured what a mixed catalogue
// costs. Every one of those is downstream of one question: which catalogue
// does a given tag reach? `locale.test.ts` pins the headline answers. This
// file pins the whole surface — every supported tag from both entry points,
// every Portuguese region, casing, the q-list parser's edges, and the
// negative claim that nothing folds a European tag onto Brazilian.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	DEFAULT_LOCALE,
	LOCALE_LABELS,
	SUPPORTED_LOCALES,
	dirForLocale,
	isSupportedLocale,
	negotiateLocale,
	parseAcceptLanguage,
	type Locale,
} from './locale';

// --- the shipped set --------------------------------------------------------

test('every supported locale reaches itself from both entry points', () => {
	for (const loc of SUPPORTED_LOCALES) {
		assert.equal(negotiateLocale(loc), loc, `header ${loc}`);
		assert.equal(negotiateLocale(null, loc), loc, `stored ${loc}`);
		assert.equal(negotiateLocale('de-DE,fr;q=0.9', loc), loc, `stored ${loc} beats a header`);
	}
});

test('the supported set is the set the labels name, and no endonym repeats', () => {
	const labelled = Object.keys(LOCALE_LABELS).sort();
	assert.deepEqual(labelled, [...SUPPORTED_LOCALES].sort());
	const values = Object.values(LOCALE_LABELS);
	assert.equal(new Set(values).size, values.length, 'two locales share an endonym');
	for (const [loc, label] of Object.entries(LOCALE_LABELS)) {
		assert.ok(label.trim().length > 0, `${loc} has an empty endonym`);
	}
	// The two Portuguese entries must be distinguishable in a picker, or a
	// reader cannot choose between the catalogues § 755 shipped.
	assert.notEqual(LOCALE_LABELS['pt-PT'], LOCALE_LABELS['pt-BR']);
});

test('pt-PT precedes pt-BR in the shipped order', () => {
	// Web never negotiates off the order, but the list is kept identical to
	// the phone's, where it IS load-bearing: Flutter resolves a bare-`pt`
	// device against `supportedLocales` and takes the first entry matching on
	// language alone. Reversing these two silently routes Lisbon to Brazil.
	const order = [...SUPPORTED_LOCALES];
	assert.ok(order.indexOf('pt-PT') < order.indexOf('pt-BR'), order.join(','));
	assert.equal(order[0], DEFAULT_LOCALE, 'English leads the picker');
});

test('isSupportedLocale accepts only the canonical spelling', () => {
	for (const loc of SUPPORTED_LOCALES) assert.equal(isSupportedLocale(loc), true, loc);
	for (const bad of [null, undefined, '', ' ', 'PT-BR', 'pt-br', 'pt', 'pt_BR', 'en-GB', 'zz']) {
		assert.equal(isSupportedLocale(bad), false, String(bad));
	}
});

// --- the Portuguese split ---------------------------------------------------

const EUROPEAN_ORTHOGRAPHY_TAGS = ['pt', 'pt-PT', 'pt-AO', 'pt-MZ', 'pt-CV', 'pt-GW', 'pt-TL'];

test('every European-orthography Portuguese tag lands on the European catalogue', () => {
	for (const tag of EUROPEAN_ORTHOGRAPHY_TAGS) {
		assert.equal(negotiateLocale(tag), 'pt-PT', `header ${tag}`);
		assert.equal(negotiateLocale(null, tag), 'pt-PT', `stored ${tag}`);
	}
});

test('Brazilian is reached by its own region tag and by nothing else', () => {
	assert.equal(negotiateLocale('pt-BR'), 'pt-BR');
	assert.equal(negotiateLocale(null, 'pt-BR'), 'pt-BR');
	// The negative claim § 761 had to make in four places: no other Portuguese
	// tag may fold onto Brazilian. Android, iOS and every browser report the
	// region, so `pt-BR` is the tag that actually arrives.
	for (const tag of EUROPEAN_ORTHOGRAPHY_TAGS) {
		assert.notEqual(negotiateLocale(tag), 'pt-BR', `header ${tag} folded to Brazilian`);
		assert.notEqual(negotiateLocale(null, tag), 'pt-BR', `stored ${tag} folded to Brazilian`);
	}
});

test('tag matching is case-insensitive in both directions', () => {
	// `navigator.language` is conventionally `pt-BR`, but the value is not
	// normalised by every browser and a stored value could arrive from an
	// older build. Casing must never decide which catalogue a reader gets.
	const cases: [string, Locale][] = [
		['PT-BR', 'pt-BR'],
		['pt-br', 'pt-BR'],
		['Pt-Br', 'pt-BR'],
		['PT-PT', 'pt-PT'],
		['pt-pt', 'pt-PT'],
		['PT', 'pt-PT'],
		['EN', 'en'],
		['DE-AT', 'de'],
		['Ja', 'ja'],
	];
	for (const [tag, expected] of cases) {
		assert.equal(negotiateLocale(tag), expected, `header ${tag}`);
		assert.equal(negotiateLocale(null, tag), expected, `stored ${tag}`);
	}
});

test('a Portuguese tag never loses to a lower-priority tag we ship exactly', () => {
	// The base-then-exact walk has to be per-tag: `pt-PT` (q=1) resolves by
	// its own exact entry, and even a `pt-AO` that only resolves by base must
	// beat an `en` sitting below it.
	assert.equal(negotiateLocale('pt-AO,en;q=0.5'), 'pt-PT');
	assert.equal(negotiateLocale('pt-PT,en;q=0.5'), 'pt-PT');
	assert.equal(negotiateLocale('pt-BR,en;q=0.5'), 'pt-BR');
	// ... and must not beat one sitting above it.
	assert.equal(negotiateLocale('en;q=1.0,pt-PT;q=0.5'), 'en');
});

test('the underscore spelling is deliberately NOT read on web', () => {
	// § 761: the three SERVER copies read `_` as a separator because they read
	// `user_settings.prefs.locale` — whatever a client wrote. Web negotiates a
	// `navigator.language` (always hyphens) and a `localStorage` value its own
	// `setLocale` wrote (always canonical), so it never sees one. Pinned so
	// the divergence is a recorded decision rather than an oversight, and so
	// adding underscore handling here is a deliberate act.
	assert.equal(negotiateLocale('pt_BR'), DEFAULT_LOCALE);
	assert.equal(negotiateLocale('de_AT'), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(null, 'pt_PT'), DEFAULT_LOCALE);
});

// --- the q-list parser ------------------------------------------------------

test('parseAcceptLanguage orders by q and preserves the header order within a q', () => {
	assert.deepEqual(parseAcceptLanguage('en;q=0.5,de;q=0.9,fr'), ['fr', 'de', 'en']);
	// Equal weights keep their written order — the sort is stable, and a
	// reordering would silently change which catalogue a reader gets.
	assert.deepEqual(parseAcceptLanguage('de,fr,es'), ['de', 'fr', 'es']);
	assert.deepEqual(parseAcceptLanguage('de;q=0.8,fr;q=0.8,es;q=0.8'), ['de', 'fr', 'es']);
});

test('parseAcceptLanguage drops the wildcard and the empties, keeps everything else', () => {
	assert.deepEqual(parseAcceptLanguage('*'), []);
	assert.deepEqual(parseAcceptLanguage(''), []);
	assert.deepEqual(parseAcceptLanguage(',,'), []);
	assert.deepEqual(parseAcceptLanguage('de,*;q=0.1'), ['de']);
	assert.deepEqual(parseAcceptLanguage('  de  ,  fr  '), ['de', 'fr']);
	// A duplicate tag is not deduplicated; it simply resolves the same way.
	assert.deepEqual(parseAcceptLanguage('de,de'), ['de', 'de']);
});

test('parseAcceptLanguage treats an unreadable q as no preference at all', () => {
	// `q=..` parses to NaN, which is not a weight — the tag sinks to the
	// bottom rather than being treated as a top preference.
	assert.deepEqual(parseAcceptLanguage('de;q=..,fr;q=0.1'), ['fr', 'de']);
	// A q parameter we cannot even recognise as one leaves the default 1.
	assert.deepEqual(parseAcceptLanguage('de;q=abc,fr;q=0.9'), ['de', 'fr']);
	// An explicit q=0 is kept and sorts last: RFC 7231 reads it as "not
	// acceptable", and dropping it would be a behaviour change, so the
	// current answer is pinned rather than assumed.
	assert.deepEqual(parseAcceptLanguage('de;q=0,fr;q=0.1'), ['fr', 'de']);
});

test('a header of only unsupported tags falls back to the default', () => {
	assert.equal(negotiateLocale('it,nl;q=0.9,sv;q=0.8'), DEFAULT_LOCALE);
	assert.equal(negotiateLocale('*'), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(''), DEFAULT_LOCALE);
	assert.equal(negotiateLocale('   '), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(null), DEFAULT_LOCALE);
	assert.equal(negotiateLocale(undefined, undefined), DEFAULT_LOCALE);
});

test('an unusable stored value falls through to the header rather than to English', () => {
	// A stored preference is only allowed to WIN; it must not be allowed to
	// suppress a header we could otherwise honour.
	assert.equal(negotiateLocale('ja', 'it'), 'ja');
	assert.equal(negotiateLocale('ja', ''), 'ja');
	assert.equal(negotiateLocale('ja', null), 'ja');
	assert.equal(negotiateLocale('pt-PT', 'zz-ZZ'), 'pt-PT');
	// And a stored value we can resolve by base still wins outright.
	assert.equal(negotiateLocale('ja', 'fr-CA'), 'fr');
});

test('the resolved locale is always one we can actually load', () => {
	// Fuzz the two entry points: whatever comes back must be a member of the
	// shipped set, or `CATALOGUE_LOADERS[next]` is undefined at runtime.
	const shipped = new Set<string>(SUPPORTED_LOCALES);
	const probes = [
		'en-GB', 'en-US,en;q=0.9', 'de-CH', 'fr-BE', 'es-419', 'ja-JP',
		'pt', 'pt-PT', 'pt-BR', 'pt-AO', 'PT-br',
		'zh-Hans-CN', 'ar-EG', 'he-IL', 'und', 'x-klingon', '*', '', '   ',
		'en;q=', 'en;;q=0.5', ';;;', 'q=0.5', '-', '--',
	];
	for (const p of probes) {
		assert.ok(shipped.has(negotiateLocale(p)), `header ${JSON.stringify(p)}`);
		assert.ok(shipped.has(negotiateLocale(null, p)), `stored ${JSON.stringify(p)}`);
		assert.ok(shipped.has(negotiateLocale(p, p)), `both ${JSON.stringify(p)}`);
	}
});

// --- direction --------------------------------------------------------------

test('every shipped locale is left-to-right, and the RTL switch still fires', () => {
	for (const loc of SUPPORTED_LOCALES) assert.equal(dirForLocale(loc), 'ltr', loc);
	for (const rtl of ['ar', 'he', 'fa', 'ur', 'ar-EG', 'HE-IL', 'FA', 'ur-PK']) {
		assert.equal(dirForLocale(rtl), 'rtl', rtl);
	}
	// An unknown or empty tag is LTR, never undefined — `<html dir>` takes a
	// value on every render.
	for (const other of ['', 'zz', 'en-GB', 'x', '-']) {
		assert.equal(dirForLocale(other), 'ltr', other);
	}
});
