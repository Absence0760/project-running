import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
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
