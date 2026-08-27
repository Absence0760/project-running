import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { SUPPORTED_LOCALES, LOCALE_LABELS } from "./locale";
import { CATALOGUE_LOADERS } from "./catalogues";

// A catalogue that ships but that no runtime path resolves to is translation
// work going nowhere: it is committed, it is bundled, and no reader can ever
// see it. `messages_parity.test.ts` proves each SHIPPED locale is complete;
// this proves the shipped set is the set that exists on disk, and that every
// member of it is selectable. The mobile twin lives in
// apps/mobile_android/test/architecture_guards_test.dart. decisions.md § 740.

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, "..", "..");

const supported = new Set<string>(SUPPORTED_LOCALES);

/**
 * Catalogues that no BARE base-language tag resolves to, each with the reason
 * a reader reaches them anyway. BASE_TO_LOCALE names one variant per language,
 * so a language shipping two catalogues necessarily leaves one off it. The
 * companion test asserts each entry is still exempt, so it cannot rot into a
 * blanket allowance.
 */
const BASE_FALLBACK_EXEMPT: Record<string, string> = {
	'pt-BR':
		'Portuguese ships two catalogues and BASE_TO_LOCALE points the bare tag at the ' +
		'European one, so Brazilian is reached through EXACT rather than by base. That ' +
		'costs a Brazilian reader nothing: Android, iOS and every browser report the ' +
		'region, so `pt-BR` is the tag that actually arrives. The bare `pt` is worth ' +
		'more to Portugal, which shares its orthography with pt-AO, pt-MZ and pt-CV — ' +
		'none of which we carry exactly — and it is what the phone does.',
};

/** The text between the bracket `marker` ends on and its match. */
function literalAfter(source: string, marker: string): string {
  const at = source.indexOf(marker);
  assert.ok(
    at >= 0,
    `could not find "${marker}" — renamed? Update this guard.`,
  );
  const open = marker[marker.length - 1];
  const close = open === "[" ? "]" : "}";
  let depth = 1;
  let i = at + marker.length;
  while (depth > 0 && i < source.length) {
    if (source[i] === open) depth++;
    if (source[i] === close) depth--;
    i++;
  }
  return source.slice(at + marker.length, i - 1);
}

function quotedValues(literal: string): Set<string> {
  return new Set([...literal.matchAll(/:\s*'([\w-]+)'/g)].map((m) => m[1]));
}

const localeSource = readFileSync(
  join(SRC, "lib", "i18n", "locale.ts"),
  "utf8",
);

function catalogueFiles(): string[] {
  return readdirSync(join(SRC, "lib", "i18n", "locales"))
    .filter((f) => f.endsWith(".ts") && !f.endsWith(".test.ts"))
    .map((f) => f.slice(0, -3));
}

test("a catalogue exists for exactly the locales we say we support", () => {
  assert.deepEqual(
    catalogueFiles().sort(),
    [...SUPPORTED_LOCALES].sort(),
    "lib/i18n/locales/ and SUPPORTED_LOCALES disagree. A file missing from the list " +
      "ships to nobody; a list entry with no file fails CATALOGUE_LOADERS at compile time.",
  );
});

test("every shipped locale is loadable and nameable", () => {
  assert.deepEqual(
    Object.keys(CATALOGUE_LOADERS).sort(),
    [...SUPPORTED_LOCALES].sort(),
  );
  for (const loc of SUPPORTED_LOCALES) {
    assert.ok(
      LOCALE_LABELS[loc]?.trim(),
      `${loc} has no endonym, so the picker renders a blank option for it`,
    );
  }
  assert.deepEqual(
    Object.keys(LOCALE_LABELS).sort(),
    [...SUPPORTED_LOCALES].sort(),
  );
});

test("every shipped locale is reachable by its exact tag", () => {
  assert.deepEqual(
    [
      ...quotedValues(
        literalAfter(localeSource, "EXACT: Record<string, Locale> = {"),
      ),
    ].sort(),
    [...SUPPORTED_LOCALES].sort(),
    "EXACT is the only path a stored preference or an exactly matching Accept-Language " +
      "tag takes; a locale absent from its values can be selected by nobody.",
  );
});

test("the language picker is derived from the supported set, not listed", () => {
  const page = readFileSync(
    join(SRC, "routes", "settings", "preferences", "+page.svelte"),
    "utf8",
  );
  const select = page.slice(page.indexOf('data-testid="language-select"'));
  const options = select.slice(0, select.indexOf("</select>"));
  assert.ok(
    options.includes("SUPPORTED_LOCALES"),
    "the picker must build its options from SUPPORTED_LOCALES",
  );
  for (const loc of SUPPORTED_LOCALES) {
    assert.ok(
      !options.includes(`'${loc}'`) && !options.includes(`"${loc}"`),
      `the picker spells ${loc} out. A hand-written list is how European Portuguese ` +
        "came to be unpickable on mobile while shipping in the binary.",
    );
  }
});

test("every localized Learn guide names a locale we ship", () => {
  const dir = join(SRC, "lib", "learn", "guides");
  const strays: string[] = [];
  for (const file of readdirSync(dir)) {
    if (!file.endsWith(".md")) continue;
    const stem = file.slice(0, -3);
    const dot = stem.lastIndexOf(".");
    if (dot === -1) continue;
    const loc = stem.slice(dot + 1);
    if (!supported.has(loc)) strays.push(file);
  }
  assert.deepEqual(
    strays,
    [],
    "a guide is written for a locale the app cannot resolve to, so getGuide falls back " +
      "to English and the translation prerenders for nobody",
  );
});

test("a catalogue no base-language tag reaches carries a reason", () => {
  const baseTargets = quotedValues(
    literalAfter(localeSource, "BASE_TO_LOCALE: Record<string, Locale> = {"),
  );
  const unreached = [...SUPPORTED_LOCALES]
    .filter((loc) => !baseTargets.has(loc) && !(loc in BASE_FALLBACK_EXEMPT))
    .sort();
  assert.deepEqual(
    unreached,
    [],
    "a visitor sending only a base language (`pt`, `de`) lands on BASE_TO_LOCALE. These " +
      "catalogues are off it with no recorded reason — either map the base to one of " +
      "them, or add the entry to BASE_FALLBACK_EXEMPT saying how a reader reaches it.",
  );
});

test("every base-fallback exemption still needs its exemption", () => {
  const baseTargets = quotedValues(
    literalAfter(localeSource, "BASE_TO_LOCALE: Record<string, Locale> = {"),
  );
  for (const [loc, reason] of Object.entries(BASE_FALLBACK_EXEMPT)) {
    assert.ok(
      supported.has(loc),
      `${loc} is exempted from the base-fallback rule but is not shipped — drop the entry.`,
    );
    assert.ok(
      !baseTargets.has(loc),
      `${loc} is now a base-fallback target (${reason}) — drop it from ` +
        "BASE_FALLBACK_EXEMPT so the guard covers it.",
    );
    assert.ok(reason.trim().length > 0);
  }
});

/**
 * Words only one of the two Portuguese variants uses. A catalogue tagged for
 * one variant containing the other's word is the failure this locale keeps
 * producing: `pt-PT.ts` shipped with 33 keys still saying `senha` and six
 * saying `morada` for an e-mail or IP address, because the substitution corpus
 * § 755 mined was taken from `app_pt.arb`, whose auth block had never been
 * Europeanised either. Every existing guard here asks whether a catalogue is
 * REACHABLE; none asked whether it says what its tag claims.
 *
 * Deliberately narrow — each is a word the other variant does not use at all,
 * not one it uses less. A frequency rule needs a threshold and a threshold is
 * a number nobody can defend. The mobile twin is the `locale reach` group in
 * apps/mobile_android/test/architecture_guards_test.dart.
 */
const BRAZILIAN_ONLY = [
	"você", "senha", "tela", "arquivo", "celular", "esteira", "excluir",
	"registrar", "compartilhar", "baixar", "ônibus", "geladeira", "xícara",
	"aplicativo", "cadastrar", "planejar", "gerenciar", "tênis", "quilômetro",
	"gênero", "acessar", "câmera", "escanear",
];
const EUROPEAN_ONLY = [
	"palavra-passe", "ecrã", "ficheiro", "telemóvel", "passadeira", "partilhar",
	"quilómetro", "género", "autocarro", "frigorífico", "chávena", "ginásio",
];
const VARIANT_WORDS: Record<string, string[]> = {
	"pt-PT": BRAZILIAN_ONLY,
	"pt-BR": EUROPEAN_ONLY,
};
/**
 * `excluir` and `arquivo` carry a second sense in Portugal (exclude, archive)
 * that is not a Brazilianism, and `vocês` is the plural. Naming the keys keeps
 * the words in the scan everywhere else, where they are the delete and file
 * senses.
 */
const VARIANT_SENSE_EXEMPT = new Set([
	"routeDetail.sendDm.intro",
	"routeDetail.sendDm.relationMutual",
	"profile.blockConfirmMessage",
	"clubEditor.descriptionPlaceholder",
	"settingsAccount.newEmailPlaceholder",
	"nutrition.targets.exerciseHint",
	"nutrition.targets.defaultsHint",
]);

test("a Portuguese catalogue does not read as the variant it is not", async () => {
	for (const [tag, words] of Object.entries(VARIANT_WORDS)) {
		assert.ok(supported.has(tag), `${tag} is not a shipped locale.`);
		const messages = await CATALOGUE_LOADERS[tag as keyof typeof CATALOGUE_LOADERS]();
		const offenders: string[] = [];
		for (const [key, value] of Object.entries(messages)) {
			if (VARIANT_SENSE_EXEMPT.has(key) || typeof value !== "string") continue;
			for (const word of words) {
				if (
					new RegExp(`(?<![a-zà-ÿ])${word}(s|es)?(?![a-zà-ÿ])`, "iu").test(value)
				) {
					offenders.push(`${key}: "${word}"`);
				}
			}
		}
		assert.deepEqual(
			offenders,
			[],
			`locales/${tag}.ts is tagged ${tag} but reads as the other variant. A tag ` +
				"that disagrees with its content is worse than a missing catalogue: the " +
				"reader is told this is their Portuguese and it is not.",
		);
	}
});

/**
 * A flat array literal of quoted strings, e.g. `['en', 'de', 'pt-BR']`. Only a
 * FLAT one: a fixture table of tuples names locales too, and each of those rows
 * is a case about one locale rather than a claim about the shipped set.
 */
const STRING_ARRAY = /\[\s*(?:'[\w-]+'|"[\w-]+")\s*(?:,\s*(?:'[\w-]+'|"[\w-]+")\s*)*,?\s*\]/g;

/** How many members of the shipped set a literal names. */
function localesNamed(literal: string): number {
	const quoted = new Set(
		[...literal.matchAll(/['"]([\w-]+)['"]/g)].map((m) => m[1]),
	);
	return [...SUPPORTED_LOCALES].filter((l) => quoted.has(l)).length;
}

/**
 * Three is the point at which a literal has stopped being a couple of examples
 * and started being a claim about the shipped set.
 */
const HAND_LIST_MIN = 3;

/**
 * file -> the reason a deliberate SUBSET of the locales is spelled out there.
 * The companion assertion below drops an entry that no longer names one, so
 * this cannot outlive what it covers.
 */
const LOCALE_SUBSET_ALLOWED: Record<string, string> = {
	"lib/format/number.test.ts":
		"the comma-decimal subset. That is a property OF those locales, not the set " +
		"we ship — en and ja group differently and belong in neither loop.",
};

const SCAN_SKIP = new Set(["node_modules", ".svelte-kit", "build", "dist"]);

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (SCAN_SKIP.has(entry)) continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) sourceFiles(full, out);
		else if (entry.endsWith(".ts") || entry.endsWith(".svelte")) out.push(full);
	}
	return out;
}

test("the hand-list matcher flags a spelled-out locale set and spares a fixture row", () => {
	const FIXTURES: Array<[flagged: boolean, literal: string]> = [
		// The seven loops this guard was written for, in their original spelling.
		[true, "['en', 'de', 'es', 'fr', 'ja', 'pt-BR']"],
		[true, '["en", "de", "fr", "es", "ja", "pt-BR", "pt-PT"]'],
		// A subset is still a claim about the set — it is allowlisted by FILE
		// with a reason, not waved through by the matcher.
		[true, "['de', 'fr', 'es', 'pt-BR', 'pt-PT']"],
		[true, "['en', 'de', 'fr']"],
		// Spared: two examples are examples.
		[false, "['en', 'de']"],
		[false, "['de-DE', 'de', 'en']"],
		// Spared: not the shipped set at all.
		[false, "['road', 'trail', 'mixed']"],
		[false, "['pt-AO', 'pt-MZ', 'pt-CV']"],
	];
	for (const [flagged, literal] of FIXTURES) {
		const matched = [...literal.matchAll(STRING_ARRAY)].some(
			(m) => localesNamed(m[0]) >= HAND_LIST_MIN,
		);
		assert.equal(
			matched,
			flagged,
			`must ${flagged ? "flag" : "spare"} ${JSON.stringify(literal)}`,
		);
	}
});

test("no source spells the supported locale set out instead of deriving it", () => {
	const files = sourceFiles(SRC);
	assert.ok(files.length > 400, `scanned only ${files.length} files`);
	const found: Record<string, string[]> = {};
	for (const file of files) {
		const rel = relative(SRC, file).split(sep).join("/");
		// locale.ts IS the declaration, and this file's own literals are the
		// matcher's must-flag fixtures; everything else must read the set.
		if (rel === "lib/i18n/locale.ts" || rel === "lib/i18n/locale_reach.test.ts") continue;
		for (const m of readFileSync(file, "utf8").matchAll(STRING_ARRAY)) {
			if (localesNamed(m[0]) >= HAND_LIST_MIN) (found[rel] ??= []).push(m[0]);
		}
	}
	const strays = Object.keys(found)
		.filter((rel) => !(rel in LOCALE_SUBSET_ALLOWED))
		.sort();
	assert.deepEqual(
		strays,
		[],
		"these spell the locale set out, so they check the locales someone remembered " +
			"rather than the ones that ship — six suites claiming to cover \"all six " +
			"catalogues\" silently skipped European Portuguese the day it landed. Import " +
			"SUPPORTED_LOCALES, or record the subset in LOCALE_SUBSET_ALLOWED with its reason.\n" +
			strays.map((r) => `  ${r}: ${found[r].join(" ")}`).join("\n"),
	);
	for (const rel of Object.keys(LOCALE_SUBSET_ALLOWED)) {
		assert.ok(
			found[rel],
			`${rel} is allowlisted as a deliberate locale subset but no longer names one — drop the entry`,
		);
	}
});
