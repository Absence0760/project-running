// A destination's name is the thing a user searches for (decisions § 539), so
// two destinations whose names differ only by a suffix are a contradiction on
// one surface. The app shipped exactly that pair: the sidebar's `/coach` read
// "Coach" and the account popover's `/coaching` read "Coaching" — one letter
// apart, and the second was NOT a sub-page of the first (one is the AI chat,
// the other the human coach↔athlete roster). Round 15's index called it a
// mobile-only defect; web carried the identical pair, which is why the rename
// had to happen here first.
//
// The check runs in every locale, because the collision is a property of the
// WORDS: a rename that separates the two in English can leave them colliding
// in German, and nothing else would notice.
//
// Invocation:
//   npx tsx --test src/lib/i18n/destination_names.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

/// Every key that names a top-level DESTINATION — a place with its own URL that
/// the user navigates to by name. Sidebar items, the account popover's two
/// entries, and the Settings left-nav tabs. Not page headings inside a
/// destination, and not action labels.
const DESTINATION_KEYS = [
	'nav.dashboard',
	'nav.history',
	'nav.runs',
	'nav.gym',
	'nav.nutrition',
	'nav.coach',
	'nav.social',
	'shell.viewProfile',
	'shell.coaching',
	'shell.settings',
	'settingsLayout.tabAccount',
	'settingsLayout.tabPreferences',
	'settingsLayout.tabIntegrations',
	'settingsLayout.tabDevices',
	'settingsLayout.tabGear',
	'settingsLayout.tabPayouts',
	'settingsLayout.tabProSupport',
	'settingsLayout.tabAbout',
	'safety.navTab',
];

/// Normalised for comparison: case, accents and separators are not what
/// distinguishes two destinations to a reader.
function fold(s: string): string {
	return s
		.normalize('NFD')
		.replace(/\p{M}/gu, '')
		.toLowerCase()
		.replace(/[\s&·/-]+/g, ' ')
		.trim();
}

/// A collision is either identical names, or one name being the other plus a
/// short MORPHOLOGICAL ending — "coach" + "ing", "Trainer" + "in", "Über" +
/// "sicht". The two limits are what keep it from firing on unrelated names that
/// merely happen to start alike:
///
///  * the extra must be at most `MAX_ENDING` characters, so Portuguese "Conta"
///    (Account) does not collide with "Contatos de segurança" (Safety
///    contacts) — a real pair in this catalogue;
///  * the extra must contain no space, because a whole extra WORD is a
///    distinguishing token the reader sees before the name ends.
const MAX_ENDING = 6;

function collides(a: string, b: string): boolean {
	const [x, y] = [fold(a), fold(b)];
	if (!x || !y) return false;
	if (x === y) return true;
	const [short, long] = x.length < y.length ? [x, y] : [y, x];
	if (!long.startsWith(short)) return false;
	const ending = long.slice(short.length);
	return ending.length <= MAX_ENDING && !ending.includes(' ');
}

// Must-flag / must-spare, both directions, because the guard IS this predicate.
const FIXTURES: Array<[flagged: boolean, a: string, b: string]> = [
	// The real pair, in every locale it would have shipped in.
	[true, 'Coach', 'Coaching'],
	[true, 'Coaching', 'Coach'],
	[true, 'Trainer', 'Trainerin'],
	[true, 'Treinador', 'Treinadores'],
	[true, 'コーチ', 'コーチング'],
	// An outright duplicate is the degenerate case of the same defect.
	[true, 'Gear', 'Gear'],
	[true, 'Gear', 'gear'],
	// Accents and separators do not distinguish two destinations.
	[true, 'A propos', 'À propos'],
	[true, 'Pro support', 'Pro & support'],
	// German "Über" (About) sat one ending away from "Übersicht" (Dashboard) —
	// caught by this guard on its first run, before it shipped.
	[true, 'Über', 'Übersicht'],
	// Spared: the fix — a second word before either name ends.
	[false, 'AI Coach', 'Athletes & coaches'],
	[false, 'Coach IA', 'Athlètes et coachs'],
	// Spared: a shared prefix that then diverges is not a collision.
	[false, 'Preferences', 'Pro & support'],
	// Spared: a real pair in the Portuguese catalogue. "Conta" (Account) starts
	// "Contatos de segurança" (Safety contacts) but nobody reads the second as
	// the first — the extra is a long, multi-word tail, not an ending.
	[false, 'Conta', 'Contatos de segurança'],
	[false, 'Gear', 'Gear rotations'],
	// Spared: German "Einstellungen" (Settings) vs "Voreinstellungen"
	// (Preferences) — the distinguishing syllable is at the FRONT, which is
	// where a scanning reader is.
	[false, 'Einstellungen', 'Voreinstellungen'],
	[false, 'Runs', 'Run heatmap'],
	[false, 'Gear', 'Gym'],
	[false, 'Dashboard', 'History'],
	// Spared: an empty side cannot collide (a missing key is the parity test's
	// job, not this one's).
	[false, '', 'Coach'],
];

test('the destination-collision predicate flags a suffix pair and spares a diverging one', () => {
	for (const [flagged, a, b] of FIXTURES) {
		assert.equal(
			collides(a, b),
			flagged,
			`must ${flagged ? 'flag' : 'spare'} ${JSON.stringify(a)} vs ${JSON.stringify(b)}`,
		);
	}
});

test('no two destination names collide, in any locale', async () => {
	let comparisons = 0;
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const named = DESTINATION_KEYS.map((k) => {
			assert.ok(dict[k], `${loc} has no name for the destination ${k}`);
			return [k, dict[k]] as const;
		});
		for (let i = 0; i < named.length; i++) {
			for (let j = i + 1; j < named.length; j++) {
				const [ka, a] = named[i];
				const [kb, b] = named[j];
				assert.equal(
					collides(a, b),
					false,
					`[${loc}] ${ka} (${JSON.stringify(a)}) and ${kb} (${JSON.stringify(b)}) ` +
						`name two different destinations with names one cannot tell apart. ` +
						`A name is what a user searches for — give each its own word.`,
				);
				comparisons++;
			}
		}
	}
	// Assert the population, not only the property — an empty key list would
	// satisfy every assertion above.
	const perLocale = (DESTINATION_KEYS.length * (DESTINATION_KEYS.length - 1)) / 2;
	assert.equal(
		comparisons,
		SUPPORTED_LOCALES.length * perLocale,
		`compared ${comparisons} pairs, expected ${SUPPORTED_LOCALES.length * perLocale}`,
	);
	assert.ok(perLocale > 100, `only ${perLocale} pairs per locale — the key list shrank`);
});
