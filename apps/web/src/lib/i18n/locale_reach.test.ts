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
	// `quilômetro` and `gênero` were one class caught one word at a time: every
	// Brazilian proparoxytone that takes ô/ê where Portugal takes ó/é.
	"cronômetro", "oxigênio", "autônomo", "autônoma",
	"planilha", "usuário", "deletar", "esporte",
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
 * Words European Portuguese really does use, but for a DIFFERENT sense than the
 * one Brazilian spends them on. `BRAZILIAN_ONLY` above cannot hold these: its
 * entries are words Portugal does not use at all, and a deny-list entry for a
 * word with a legitimate sense would have to be answered by dropping the word,
 * which blinds the scan everywhere. So the direction is inverted — the word is
 * banned outright and the sites that mean the other thing are named.
 *
 * `padrão` is *standard* and *pattern* in Portugal; the pre-set value is a
 * `predefinição`. Brazilian spends one word on all three, so a catalogue
 * derived from it reads as Brazilian at every default. Naming the survivors is
 * what makes this hold: a NEW string saying `padrão` fails here and forces the
 * per-site decision rather than inheriting the ambiguity again.
 *
 * The mobile twin is the `locale reach` group in
 * apps/mobile_android/test/architecture_guards_test.dart.
 */
const SENSE_SPLIT: Record<string, { word: RegExp; onlyAt: string[] }> = {
	"pt-PT": {
		word: /(?<![a-zà-ÿ])padr(ão|ões)(?![a-zà-ÿ])/iu,
		onlyAt: [
			// "the world standard for your age and sex"
			"dash.prAgeGradeTitle",
			// "the pattern most associated with injury"
			"loadRamp.meaning_high",
		],
	},
};

test("a sense-split word survives only where the other sense was recorded", async () => {
	for (const [tag, { word, onlyAt }] of Object.entries(SENSE_SPLIT)) {
		const messages = await CATALOGUE_LOADERS[tag as keyof typeof CATALOGUE_LOADERS]();
		const allowed = new Set(onlyAt);
		const offenders = Object.entries(messages)
			.filter(([k, v]) => !allowed.has(k) && typeof v === "string" && word.test(v))
			.map(([k]) => k);
		assert.deepEqual(
			offenders,
			[],
			`locales/${tag}.ts spends ${word.source} on a sense Portugal does not ` +
				"use it for. A default is a `predefinição`; `padrão` is a standard or " +
				"a pattern. If one of these really is the other sense, add it to " +
				"SENSE_SPLIT.onlyAt with the English source in a comment.",
		);
		// A named site that no longer says the word is a dead entry, and a dead
		// entry is how an allowlist stops being a decision and starts being noise.
		for (const key of onlyAt) {
			const value = messages[key as keyof typeof messages];
			assert.equal(
				typeof value,
				"string",
				`${tag}: SENSE_SPLIT names ${key}, which the catalogue no longer has.`,
			);
			assert.ok(
				word.test(value as string),
				`${tag}: ${key} no longer says ${word.source} — drop it from ` +
					"SENSE_SPLIT.onlyAt so the guard covers the key again.",
			);
		}
	}
});

/**
 * The wrist and the watch ship European Portuguese too, and neither had any
 * lexical guard at all — the two scans above read `lib/i18n/locales/` and the
 * mobile twin reads `lib/l10n/`, so half the surfaces this locale ships on
 * were covered and half were not. Both measured clean when this guard landed,
 * which is the reason to add it now rather than the reason not to: § 755's
 * wrist set and § 761's watchOS set were written in European Portuguese
 * directly, and the defect this whole arc is about is a later derivation from
 * Brazilian quietly undoing that.
 *
 * Cross-tier the way `delete-account`'s guard reads the Go worker's catalogue
 * (§ 761) — these are separate deployment units with no module between them,
 * so the alternative is four copies of one word list.
 */
const OTHER_PT_PT_CATALOGUES: { path: string[]; read: (raw: string) => Record<string, string> }[] = [
	{
		path: ["apps", "watch_wear", "android", "app", "src", "main", "res", "values-b+pt+PT", "strings.xml"],
		read: (raw) =>
			Object.fromEntries(
				[...raw.matchAll(/<(string|item)(?:\s+name="([\w.]+)")?[^>]*>([\s\S]*?)<\/\1>/g)].map(
					(m, i) => [m[2] ?? `item[${i}]`, m[3]],
				),
			),
	},
	{
		path: ["apps", "watch_ios", "WatchApp", "Localizable.xcstrings"],
		read: (raw) => {
			const out: Record<string, string> = {};
			const catalogue = JSON.parse(raw) as {
				strings: Record<string, { localizations?: Record<string, PtUnit> }>;
			};
			for (const [key, entry] of Object.entries(catalogue.strings)) {
				const pt = entry.localizations?.["pt-PT"];
				if (!pt) continue;
				if (pt.stringUnit) out[key] = pt.stringUnit.value;
				for (const [form, unit] of Object.entries(pt.variations?.plural ?? {})) {
					if (unit.stringUnit) out[`${key}[${form}]`] = unit.stringUnit.value;
				}
			}
			return out;
		},
	},
];
type PtUnit = {
	stringUnit?: { value: string };
	variations?: { plural?: Record<string, { stringUnit?: { value: string } }> };
};

test("the wrist and watch pt-PT catalogues read as European Portuguese too", () => {
	const repo = join(SRC, "..", "..", "..");
	const words = [...BRAZILIAN_ONLY, "padrão"];
	for (const { path, read } of OTHER_PT_PT_CATALOGUES) {
		const file = join(repo, ...path);
		const strings = read(readFileSync(file, "utf8"));
		// A reader that stops matching finds nothing and reports success, which
		// is the failure mode a source-shape guard has (decisions § 762). The
		// catalogues only grow, so an empty read is a broken reader.
		assert.ok(
			Object.keys(strings).length > 0,
			`${path.join("/")} yielded no pt-PT strings — the reader has stopped ` +
				"matching the file's shape, so this guard is checking nothing.",
		);
		const offenders: string[] = [];
		for (const [key, value] of Object.entries(strings)) {
			for (const word of words) {
				if (new RegExp(`(?<![a-zà-ÿ])${word}(s|es|ões)?(?![a-zà-ÿ])`, "iu").test(value)) {
					offenders.push(`${key}: "${word}"`);
				}
			}
		}
		assert.deepEqual(
			offenders,
			[],
			`${path.join("/")} is a pt-PT catalogue reading as Brazilian. A default ` +
				"is a `predefinição`; the rest are words Portugal does not use at all.",
		);
	}
});

/**
 * Which SECOND PERSON a Portuguese catalogue addresses its reader in. Portuguese
 * has two and they do not mix inside one catalogue: `tu` takes `teu`/`tua`, the
 * clitic `te` and a second-person-singular verb, while `você` — the register
 * European Portuguese software uses, and the one § 755 chose for every
 * Portuguese surface derived since — takes `seu`/`sua`, `-lhe`/`-o`/`-a` and a
 * third-person verb. The mobile twin is the `locale reach` group in
 * apps/mobile_android/test/architecture_guards_test.dart (decisions § 782); this
 * is web's half of the same pair (§ 784).
 *
 * The markers split into two kinds and only one kind can be listed, so this is
 * two tests. A [TU_MARKERS] entry is a form no other person, tense or part of
 * speech spells the same way, which makes a token list exact. The affirmative
 * imperative is the other kind and is unlistable: its tu form is letter-for-
 * letter the third-person present indicative, so `Adiciona um peso` (tu, *add a
 * weight*) and `a app adiciona um peso` (*the app adds a weight*) are the same
 * word, and any token banning it fires on ordinary prose. That half is derived
 * against the Brazilian catalogue instead — see the second test.
 *
 * Two words are deliberately absent because they are NOT tu-only here, and both
 * are live in both catalogues: `precisas` is `precisar` in the tu form and the
 * feminine plural of `preciso` (`runDetail.hrDisclaimerSuffix`, "para zonas
 * precisas"), and `aceitas` is `aceitar` in the tu form and the feminine plural
 * participle (`settingsAccount.aiConsentUpdatedToast`, "Informações de IA
 * atualizadas aceitas"). Bare `tu` is absent for the opposite reason — a label
 * whose whole value names the reader is not a possessive in running prose, and
 * pt-PT deliberately ships `clubEvent.youTag` as `(tu)` and `messages.youPrefix`
 * as `Tu: ` after § 760 put the pronoun back into them.
 */
const TU_MARKERS = [
	"teu", "tua", "teus", "tuas", "ti", "contigo",
	"podes", "estás", "tens", "queres", "vais", "deves", "sabes", "fazes",
	"és", "vês", "dizes", "escolhes", "alteras", "tomas", "usas", "utilizas",
	"digitas", "corres", "participas",
	"tiveres", "estiveres", "quiseres", "puderes", "fizeres", "registares",
	"tenhas", "estejas", "sejas", "possas", "vás", "faças",
];

/**
 * The enclitic object pronoun. `você` takes `-lhe` or `-o`/`-a`, never this, so
 * a hyphen followed by exactly `te` is a tu marker wherever it lands.
 */
const TU_ENCLITIC = /(?<![a-zà-ÿ])[a-zà-ÿ]+-te(?![a-zà-ÿ])/giu;

/**
 * The PROCLITIC `te`, scanned in `pt-PT` only. Brazilian written register mixes
 * `você` with a proclitic `te` widely enough that `pt-BR.ts` spends it on five
 * strings that read as ordinary Brazilian ("Outros podem te encontrar por ele"),
 * so a shared list carrying it would accuse those five rather than report a
 * defect. European `você` has no such tolerance — it takes `o`/`a`/`lhe` — so in
 * `pt-PT.ts` the word is the same mixed register the rest of this guard is about.
 */
const TU_PROCLITIC = /(?<![a-zà-ÿ-])te(?![a-zà-ÿ])/giu;

/**
 * The second-person-singular preterite, which is a SUFFIX rather than a list —
 * `-aste`/`-este`/`-iste` is that tense and no other. The words below end the
 * same way and are not verbs in that tense, so they are named rather than
 * letting the pattern go. Unlike the exemptions further down, this is a fact
 * about Portuguese and not about our copy: `este` is a demonstrative and
 * `desgaste` a noun whatever strings we ship, so an entry here cannot rot.
 */
const TU_PRETERITE = /(?<![a-zà-ÿ])[a-zà-ÿ]{3,}(?:aste|este|iste)(?![a-zà-ÿ])/giu;
const NOT_A_PRETERITE = new Set([
	"arraste", "desgaste", "deste", "este", "existe", "leste", "neste",
	"oeste", "registe",
]);

/**
 * Key prefixes allowed to address the reader as `tu`, with the reason.
 * **Empty, and that is the finding**, exactly as on the phone (§ 782): no string
 * in either Portuguese catalogue addresses its reader as `tu`, and the mechanism
 * survives for a future surface that genuinely must. Each prefix added here is
 * asserted below to still cover a key the guard would otherwise flag, so an
 * exemption cannot outlive the strings it was written for.
 */
const REGISTER_EXEMPT_PREFIXES: string[] = [];

/**
 * European/Brazilian word pairs that differ by the same one-letter ending an
 * imperative does and are not verbs at all, so the derived scan below cannot
 * tell them apart on shape. `equipa`/`equipe` is *team*. Each is asserted to
 * still be in use.
 */
const VARIANT_WORD_PAIRS: Record<string, string> = {
	equipa: "equipe",
};

function registerExempt(key: string): boolean {
	return REGISTER_EXEMPT_PREFIXES.some((p) => key.startsWith(p));
}

function tuMarkersIn(value: string, tag: string): string[] {
	const found: string[] = [];
	for (const marker of TU_MARKERS) {
		if (new RegExp(`(?<![a-zà-ÿ])${marker}(?![a-zà-ÿ])`, "iu").test(value)) {
			found.push(`"${marker}"`);
		}
	}
	for (const m of value.matchAll(TU_PRETERITE)) {
		if (!NOT_A_PRETERITE.has(m[0].toLowerCase())) found.push(`"${m[0]}"`);
	}
	if (TU_ENCLITIC.test(value)) found.push('the "-te" enclitic');
	TU_ENCLITIC.lastIndex = 0;
	if (tag === "pt-PT" && TU_PROCLITIC.test(value)) found.push('the proclitic "te"');
	TU_PROCLITIC.lastIndex = 0;
	return found;
}

const PORTUGUESE = ["pt-PT", "pt-BR"] as const;

async function catalogue(tag: (typeof PORTUGUESE)[number]) {
	return CATALOGUE_LOADERS[tag]() as Promise<Record<string, unknown>>;
}

test("a Portuguese catalogue addresses its reader in one register", async () => {
	// Both catalogues, not just the European one. `pt-BR.ts` is the reference the
	// derived imperative scan below measures against, so a tu marker landing in
	// IT makes that scan blind rather than merely wrong — the two words would
	// cancel and the pair would never be reported. That was live: the whole
	// `coachPage.*` consent block spoke tu in BOTH catalogues (§ 784).
	for (const tag of PORTUGUESE) {
		const messages = await catalogue(tag);
		const offenders: string[] = [];
		for (const [key, value] of Object.entries(messages)) {
			if (typeof value !== "string" || registerExempt(key)) continue;
			for (const marker of tuMarkersIn(value, tag)) offenders.push(`${key}: ${marker}`);
		}
		assert.deepEqual(
			offenders,
			[],
			`locales/${tag}.ts addresses its reader as \`tu\` here and as \`você\` ` +
				"everywhere else. One catalogue cannot be two products to one reader: use " +
				"`seu`/`sua`, `-lhe` and a third-person verb, per decisions § 755. If a " +
				"string really must be tu, add its prefix to REGISTER_EXEMPT_PREFIXES with " +
				"the reason written down.",
		);
	}
});

test("the pt-PT catalogue uses no tu imperative its Brazilian twin does not", async () => {
	// Derived rather than listed, because the tu affirmative imperative is spelled
	// exactly like the third-person present indicative and no token can separate
	// them. `pt-BR.ts` is uniformly `você` (pinned by the test above), so a word
	// this catalogue uses where Brazilian uses the same stem with the imperative's
	// other ending IS the tu form: `Importa` against `Importe`, `Ativa` against
	// `Ative`, `descarta` against `descarte`. Symmetric on purpose — the same scan
	// read the other way catches a `você` ending applied to a third-person
	// indicative, which is how "ele confirme e passa a receber" and "Isto adicione
	// ou sobrescreve" reached the catalogue. No threshold, no vocabulary list.
	const european = await catalogue("pt-PT");
	const brazilian = await catalogue("pt-BR");
	const word = /[a-zà-ÿ]+/giu;
	const wordsOf = (v: string) =>
		new Set([...v.matchAll(word)].map((m) => m[0].toLowerCase()));

	const offenders: string[] = [];
	for (const [key, value] of Object.entries(european)) {
		if (typeof value !== "string" || registerExempt(key)) continue;
		const other = brazilian[key];
		if (typeof other !== "string") continue;
		const ours = wordsOf(value);
		const theirs = wordsOf(other);
		for (const a of ours) {
			if (theirs.has(a) || a.length < 4) continue;
			for (const b of theirs) {
				if (ours.has(b) || b.length < 4) continue;
				if (a.slice(0, -1) !== b.slice(0, -1)) continue;
				const swap = a[a.length - 1] + b[b.length - 1];
				if (swap !== "ae" && swap !== "ea") continue;
				if (VARIANT_WORD_PAIRS[a] === b) continue;
				offenders.push(`${key}: "${a}" where pt-BR says "${b}"`);
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		"locales/pt-PT.ts gives an imperative in the tu form. Portugal says " +
			"`Importe`, not `Importa`, in the register this catalogue uses everywhere " +
			"else (decisions § 755). If the word is not a verb, add the pair to " +
			"VARIANT_WORD_PAIRS with what it means.",
	);
});

test("every register exemption still needs its exemption", async () => {
	// An exemption that covers nothing has stopped being a decision and become
	// noise — the shape SENSE_SPLIT above already uses for its named sites.
	const european = await catalogue("pt-PT");
	const brazilian = await catalogue("pt-BR");
	for (const prefix of REGISTER_EXEMPT_PREFIXES) {
		const covered = Object.entries(european).some(
			([k, v]) =>
				k.startsWith(prefix) && typeof v === "string" && tuMarkersIn(v, "pt-PT").length > 0,
		);
		assert.ok(
			covered,
			`REGISTER_EXEMPT_PREFIXES carries "${prefix}", but no key under it says ` +
				"`tu` any more. Drop the prefix so the guard covers those keys again.",
		);
	}
	const whole = [...Object.values(european), ...Object.values(brazilian)]
		.filter((v): v is string => typeof v === "string")
		.join("\n");
	for (const [a, b] of Object.entries(VARIANT_WORD_PAIRS)) {
		for (const w of [a, b]) {
			assert.ok(
				new RegExp(`(?<![a-zà-ÿ])${w}(?![a-zà-ÿ])`, "iu").test(whole),
				`VARIANT_WORD_PAIRS names "${w}", which neither Portuguese catalogue uses any more.`,
			);
		}
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
