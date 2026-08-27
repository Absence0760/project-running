// The web half of issue #666's surfaced item 3, pinned derivationally.
//
// Mobile shipped `profileNotifYourRun` as a possessive FRAGMENT ("your run")
// substituted into a template that already carried a possessive ("gave kudos to
// your {dist}"), so every kudos or comment on a run with no recorded distance
// read "gave kudos to your your run". Web carried the identical defect on four
// templates — `notificationBell.kudos` / `.comment` and
// `notificationsList.verbKudos` / `.verbComment` — against two fragment keys,
// `notificationBell.yourRun` and `notificationsList.yourRun`, in ALL SIX
// locales: "deinem deinen Lauf", "a tu tu carrera", "à ton ta course",
// "あなたのあなたのラン", "à sua sua corrida".
//
// The round-14 index called this "2 keys". That is the count of the FRAGMENT
// keys; the broken renders were 4 templates x 6 locales = 24.
//
// The fix is not a smarter fragment, because no single fragment can be
// grammatical in both slots: German wants the dative "deinem" after the kudos
// verb and the accusative "deinen" after the comment verb, and French "course"
// is feminine where the interpolated "5,2 km" is masculine, so "ton {dist}"
// and "ta course" cannot share a template. Each no-distance branch therefore
// takes a WHOLE SENTENCE key of its own and interpolates nothing but the actor
// name, and the fragment keys are deleted.
//
// This test renders every branch the two components can actually produce, in
// every locale, rather than asserting a specific English string — which would
// have said nothing about the five locales where the same bug shipped.
//
// The rule it applies is NOT "reject a back-to-back repeat", which was the
// obvious shape and is not enough: German's doubling is "deinem deinen", two
// DIFFERENT inflections of the one possessive, and an exact-repeat matcher
// spares it. What the defect actually is, in all six locales, is a phrase
// carrying the second-person possessive TWICE. So that is what is counted, with
// the repeat check kept beside it as a language-agnostic second net.
//
// Invocation:
//   npx tsx --test src/lib/i18n/notification_phrasing.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { SUPPORTED_LOCALES, type Locale } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';
import { interpolate } from './interpolate';

// The exact key set `NotificationBell.verbFor` and `NotificationsList.verbFor`
// reach for, split by which branch of the distance check produces them.
const WITH_DISTANCE = [
	'notificationBell.kudos',
	'notificationBell.comment',
	'notificationsList.verbKudos',
	'notificationsList.verbComment',
];
const NO_DISTANCE = [
	'notificationBell.kudosNoDistance',
	'notificationBell.commentNoDistance',
	'notificationsList.verbKudosNoDistance',
	'notificationsList.verbCommentNoDistance',
];

// Every inflection of the second-person possessive each shipped locale uses in
// these phrases. German and French are listed in full because the defect there
// is two different forms, not one form twice.
const POSSESSIVES: Record<Locale, string[]> = {
	en: ['your'],
	de: ['dein', 'deine', 'deinem', 'deinen', 'deiner', 'deines'],
	es: ['tu', 'tus'],
	fr: ['ton', 'ta', 'tes'],
	ja: ['あなたの'],
	'pt-BR': ['seu', 'sua', 'seus', 'suas'],
	// European Portuguese uses the same third-person possessive as Brazilian in
	// this catalogue's register; the `tu` forms are listed too so a phrase that
	// switches register mid-sentence is still counted rather than slipping the
	// guard by using two different words for the one possessive.
	'pt-PT': ['seu', 'sua', 'seus', 'suas', 'teu', 'tua', 'teus', 'tuas'],
};

// Japanese has no word boundaries, so it is counted as a substring; the Latin
// locales need boundaries or French "ta" matches inside "état".
function possessiveCount(s: string, loc: Locale): number {
	let n = 0;
	for (const form of POSSESSIVES[loc]) {
		const re = /^[\p{Script=Latin}]/u.test(form)
			? new RegExp(`(?<!\\p{L})${form}(?!\\p{L})`, 'giu')
			: new RegExp(form, 'gu');
		n += [...s.matchAll(re)].length;
	}
	return n;
}

function adjacentRepeat(s: string): string | null {
	const t = s.split(/[\s、。,.!?]+/).filter(Boolean);
	for (let i = 1; i < t.length; i++) if (t[i] === t[i - 1]) return t[i];
	return null;
}

function phraseDefect(s: string, loc: Locale): string | null {
	const n = possessiveCount(s, loc);
	if (n > 1) return `carries the second-person possessive ${n} times`;
	const repeat = adjacentRepeat(s);
	if (repeat) return `repeats the token "${repeat}"`;
	return null;
}

// Must-flag / must-spare, because the whole guard is this predicate and § 503's
// rule is that a matcher earns a fixture table. The first six are the REAL
// pre-fix renders, one per locale — so the table proves the guard would have
// caught the shipped bug in every language, not only in English.
const FIXTURES: Array<[flagged: boolean, loc: Locale, s: string]> = [
	[true, 'en', 'Alice gave kudos to your your run'],
	[true, 'de', 'Alice hat deinem deinen Lauf Kudos gegeben'],
	[true, 'es', 'Alice dio kudos a tu tu carrera'],
	[true, 'fr', 'Alice a donné des kudos à ton ta course'],
	[true, 'ja', 'Alice があなたのあなたのランに kudos を送りました'],
	[true, 'pt-BR', 'Alice deu kudos à sua sua corrida'],
	[true, 'pt-PT', 'Alice deu kudos à sua sua corrida'],
	// The doubling the `tu` forms exist to catch: two DIFFERENT words for the
	// one possessive, which an exact-repeat matcher spares.
	[true, 'pt-PT', 'Alice deu kudos à tua sua corrida'],
	// The fixed renders, same six.
	[false, 'en', 'Alice gave kudos to your run'],
	[false, 'de', 'Alice hat deinem Lauf Kudos gegeben'],
	[false, 'es', 'Alice dio kudos a tu carrera'],
	[false, 'fr', 'Alice a donné des kudos à ta course'],
	[false, 'ja', 'Alice があなたのランに kudos を送りました'],
	[false, 'pt-BR', 'Alice deu kudos à sua corrida'],
	[false, 'pt-PT', 'Alice deu kudos à sua corrida'],
	// The distance branch, which keeps its single possessive.
	[false, 'en', 'Alice gave kudos to your 5.2 km'],
	[false, 'fr', 'Alice a commenté ton 5,2 km'],
	// A possessive form appearing INSIDE another word is not a second
	// possessive: French "ta" sits in "état", Spanish "tu" in "actualizar".
	[false, 'fr', 'Alice a commenté ta course en bon état'],
	[false, 'es', 'Alice comentó tu carrera al actualizar'],
	// An exact repeat with no possessive at all is still a defect.
	[true, 'en', 'Alice commented on the the run'],
];

test('the phrase-defect matcher flags every locale’s doubled possessive and spares the fix', () => {
	for (const [flagged, loc, s] of FIXTURES) {
		assert.equal(
			phraseDefect(s, loc) !== null,
			flagged,
			`the matcher must ${flagged ? 'flag' : 'spare'} [${loc}] ${JSON.stringify(s)}`,
		);
	}
});

test('no notification phrase doubles the possessive, in any locale, on either branch', async () => {
	let checked = 0;
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const [keys, args] of [
			[NO_DISTANCE, { name: 'Alice' }],
			[WITH_DISTANCE, { name: 'Alice', dist: '5.2 km' }],
		] as const) {
			for (const key of keys) {
				assert.ok(dict[key], `${loc}.${key} is missing`);
				const rendered = interpolate(dict[key], args);
				assert.equal(
					phraseDefect(rendered, loc),
					null,
					`${loc}.${key} ${phraseDefect(rendered, loc)}: ${rendered}`,
				);
				checked++;
			}
		}
	}
	// Assert the population, not only the property — an empty sweep would pass
	// this test while proving nothing about any locale.
	assert.equal(
		checked,
		SUPPORTED_LOCALES.length * 8,
		`checked ${checked} renders, expected ${SUPPORTED_LOCALES.length * 8} ` +
			`(${SUPPORTED_LOCALES.length} locales x 4 templates x 2 branches)`,
	);
});

// The root cause, stated as a rule rather than left to the phrasings above: a
// possessive fragment is what made the doubling POSSIBLE, so no catalogue may
// carry one under these names again. Deleting the keys is the fix; this keeps
// them deleted.
test('no catalogue carries a possessive run fragment for the notification slot', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const key of ['notificationBell.yourRun', 'notificationsList.yourRun']) {
			assert.equal(
				key in dict,
				false,
				`${loc} still carries ${key}. It is a possessive FRAGMENT substituted into a ` +
					`template that already has a possessive — the "your your run" defect. The ` +
					`no-distance branch takes a whole-sentence key instead.`,
			);
		}
	}
});
