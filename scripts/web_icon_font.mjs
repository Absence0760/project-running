#!/usr/bin/env node
// The web app's icon font: which glyphs it carries, and how that set is
// decided.
//
// `apps/web` renders every icon as a Material Symbols LIGATURE — the literal
// text `arrow_back` inside a `.material-symbols` span, which the font's `rlig`
// feature substitutes for one glyph. That is a pleasant authoring shape and it
// cost 3866 KB gzipped: `+layout.svelte` imported the npm package's stylesheet,
// which `@font-face`s the complete unsubsetted variable font — 4271 icons over
// four variation axes — `font-display: block`, on the root layout. Every reader
// waited on 1.8x the entire code budget to see a chevron (decisions § 771).
//
// So the shipped font is subset to the icons this app actually names, and that
// set has to be DERIVED from the source or the next icon someone adds renders
// as the word `arrow_back` clipped to a 1.25em box. Two rules produce it, and
// the second is the one that matters:
//
//   1. Element text — `<span class="material-symbols">arrow_back</span>`. The
//      name is unambiguous here, so a name this rule finds that the font cannot
//      render is a hard error rather than a filtered-out candidate: it is an
//      icon that does not render TODAY.
//   2. Every quoted `[a-z0-9_]+` literal anywhere under `apps/web/src` that the
//      upstream font can render. Most icons never appear as element text —
//      they arrive through `{item.icon}`, `{METRIC_ICON[c.metric]}`,
//      `{sidebarCollapsed ? 'chevron_right' : 'chevron_left'}` — so a rule
//      scoped to render sites would miss them. Intersecting all string literals
//      with the font's own ligature vocabulary over-includes (a `'route'` that
//      is a URL segment costs one glyph, ~230 bytes) and cannot under-include,
//      which is the only asymmetry worth having here: an extra glyph is 230
//      bytes, a missing one is a broken button.
//
// Rule 2 needs the vocabulary — the 4271 ligature texts the upstream font
// actually carries — and that is why it is committed at
// scripts/material_symbols_ligatures.txt rather than read from a package.
// `material-symbols/index.d.ts` is NOT that list: it omits `terrain`,
// `expand_more`, `emoji_events`, `place`, `loop` and every other alias whose
// ligature resolves to a differently-named glyph (`terrain` -> `landscape`),
// twelve of which this app renders. A guard built on it would have silently
// dropped them.
//
// Test-only sources are scanned too. They cannot render anything, so including
// them is 23 glyphs of pure over-inclusion — bought so that the rule is "every
// file under src", with no exception a future reader has to know about.
//
// Run:  `node scripts/gen_web_icon_font.mjs` (regenerates the font + manifest)
// Unit tests + the repo invariant: `node --test scripts/web_icon_font.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, extname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WEB_SRC = join(REPO_ROOT, 'apps', 'web', 'src');
export const VOCABULARY_FILE = join(REPO_ROOT, 'scripts', 'material_symbols_ligatures.txt');
export const ASSETS_DIR = join(REPO_ROOT, 'apps', 'web', 'src', 'lib', 'assets');
export const SUBSET_FONT = join(ASSETS_DIR, 'material-symbols-subset.woff2');
export const MANIFEST = join(ASSETS_DIR, 'material-symbols-subset.json');
export const UPSTREAM_PACKAGE = join(REPO_ROOT, 'node_modules', 'material-symbols');
export const UPSTREAM_FONT = join(UPSTREAM_PACKAGE, 'material-symbols-outlined.woff2');

/// Text sources under apps/web/src that can name an icon. `.svx` and `.md` are
/// the mdsvex `/learn` guides.
export const SOURCE_EXTENSIONS = new Set(['.svelte', '.ts', '.js', '.css', '.md', '.svx', '.html']);

/// A test module. Nothing under this name reaches a bundle, so a ligature
/// spelled inside one renders nowhere and must not pull a glyph into the
/// shipped face. The exclusion is not cosmetic: the reader's last pass takes
/// any quoted bare token that happens to be in the 4275-word vocabulary, and
/// the vocabulary is full of ordinary English -- `stack`, `padding`, `privacy`,
/// `javascript`. 24 of the 348 glyphs the walk selected were in the subset for
/// that reason alone, and a fixture that merely quotes such a word failed the
/// coverage gate on a font that was in fact correct.
export const TEST_SOURCE = /\.(test|spec)\.(ts|js|mjs)$/;

/// The axes pinned out of the variable font, and the value each is pinned at.
///
/// Measured on the 347-glyph subset: all four axes 222 KB, drop GRAD 136 KB,
/// drop GRAD+opsz 69 KB, fully static 26 KB. The per-asset budget is 100 KB, so
/// only the third fits — and it is also the one that changes nothing the app
/// asks for. `GRAD` is written in the source exactly twice, both times as 0.
/// `opsz` is written exactly twice, both times as 24. Nothing sets either to
/// anything else, so pinning them there is what the CSS already requests; what
/// is lost is the automatic optical-size interpolation `font-optical-sizing:
/// auto` would otherwise do across icon sizes, and with the axis gone that
/// property is inert rather than wrong. FILL and wght STAY variable because the
/// app varies both deliberately — seven `'FILL' 1` / `'FILL' 0` rules and the
/// sidebar's `'wght' 500` / `'wght' 600` — and a static instance would render
/// every filled icon hollow and synthesise faux-bold for the rest.
export const PINNED_AXES = Object.freeze({ GRAD: 0, opsz: 24 });

/// `rlig` is where Material Symbols keeps the icon ligatures and `rclt` is the
/// contextual pass beside it; there is no `liga` in this font at all, which is
/// worth stating because the vendor stylesheet's `font-feature-settings:
/// "liga"` implies otherwise and a subset that keeps only `liga` keeps no icons.
export const LAYOUT_FEATURES = Object.freeze(['rlig', 'rclt']);

/// The ligature alphabet: every character an icon name can be spelled with.
/// Retained so the substitution still has its inputs.
export const LIGATURE_ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789_';

/// A `class=` attribute, in each of the three forms Svelte accepts. The value
/// is read out rather than pattern-matched in place so the icon-class test is a
/// plain substring check and the QUOTED / EXPRESSION distinction survives it —
/// a `class={...}` carrying the icon class is a rendering shape this extractor
/// cannot read, and has to say so rather than quietly find no icons in it.
export const CLASS_ATTRIBUTE = /class=(?:"([^"]*)"|'([^']*)'|\{([^}]*)\})/g;

/// What follows the element's `>`: an expression, whose ligature name is a
/// string literal QUOTED_TOKEN will find wherever it is defined, or the
/// ligature itself as literal text.
export const ELEMENT_EXPRESSION = /^\s*\{/;
export const ELEMENT_TEXT = /^\s*([a-z0-9_]+)\s*</;
/// An element with no content renders no icon. That is a bug on a real site and
/// not this extractor's to report; here it is only a shape with no name in it.
export const ELEMENT_EMPTY = /^\s*</;

/// Any single-, double- or backtick-quoted bare token.
export const QUOTED_TOKEN = /'([a-z0-9_]+)'|"([a-z0-9_]+)"|`([a-z0-9_]+)`/g;

/**
 * @typedef {{ path: string, text: string }} Source
 * @typedef {{ name: string, path: string }} Sited
 */

/** @param {string} buf @returns {string} */
export const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

/** @param {Buffer} buf @returns {string} */
export const sha256Bytes = (buf) => createHash('sha256').update(buf).digest('hex');

/// Every scannable source under `root`, path repo-relative and posix-spelled.
/**
 * @param {string} root
 * @returns {Source[]}
 */
export function collectSources(root) {
	/** @type {Source[]} */
	const out = [];
	/** @param {string} dir */
	const walk = (dir) => {
		for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) =>
			a.name < b.name ? -1 : a.name > b.name ? 1 : 0,
		)) {
			const abs = join(dir, entry.name);
			if (entry.isDirectory()) {
				walk(abs);
				continue;
			}
			if (!SOURCE_EXTENSIONS.has(extname(entry.name))) continue;
			if (TEST_SOURCE.test(entry.name)) continue;
			out.push({
				path: abs.slice(REPO_ROOT.length + 1).split(sep).join('/'),
				text: readFileSync(abs, 'utf8'),
			});
		}
	};
	walk(root);
	return out;
}

/// The icon set the subset must carry, plus the two ways the read can be wrong.
///
/// `unrenderable` is an icon written as element text that the upstream font has
/// no ligature for — a broken icon in the app today, not a subsetting decision.
/// `unreadable` is a mention of the class in markup that ICON_ELEMENT_TEXT
/// cannot parse, which would drop icons silently; both are errors, not
/// warnings.
/**
 * @param {readonly Source[]} sources
 * @param {ReadonlySet<string>} vocabulary
 * @returns {{ icons: string[], unrenderable: Sited[], unreadable: Sited[] }}
 */
export function selectIcons(sources, vocabulary) {
	/** @type {Set<string>} */
	const icons = new Set();
	/** @type {Sited[]} */
	const unrenderable = [];
	/** @type {Sited[]} */
	const unreadable = [];
	for (const source of sources) {
		for (const attribute of source.text.matchAll(CLASS_ATTRIBUTE)) {
			const value = attribute[1] ?? attribute[2] ?? attribute[3];
			if (!/\bmaterial-symbols\b/.test(value)) continue;
			const site = { name: attribute[0], path: source.path };
			if (attribute[3] !== undefined) {
				unreadable.push(site);
				continue;
			}
			const rest = source.text.slice(attribute.index + attribute[0].length);
			const tagEnd = /^[^>]*>/.exec(rest);
			if (!tagEnd) {
				unreadable.push(site);
				continue;
			}
			const content = rest.slice(tagEnd[0].length);
			if (ELEMENT_EXPRESSION.test(content) || ELEMENT_EMPTY.test(content)) continue;
			const literal = ELEMENT_TEXT.exec(content);
			if (!literal) {
				unreadable.push(site);
				continue;
			}
			if (vocabulary.has(literal[1])) icons.add(literal[1]);
			else unrenderable.push({ name: literal[1], path: source.path });
		}
		for (const m of source.text.matchAll(QUOTED_TOKEN)) {
			const token = m[1] ?? m[2] ?? m[3];
			if (vocabulary.has(token)) icons.add(token);
		}
	}
	return { icons: [...icons].sort(), unrenderable, unreadable };
}

/** @param {string} text @returns {Set<string>} */
export function parseVocabulary(text) {
	return new Set(text.split('\n').filter((line) => line.length > 0));
}

/// One `'AXIS' value` pair inside a `font-variation-settings` declaration.
export const VARIATION_SETTING = /'([A-Za-z]{4})'\s+(-?[\d.]+)/g;

/**
 * Every request in the sources for a PINNED axis at a value the subset cannot
 * render.
 *
 * Pinning an axis instantiates it: the shipped face carries `GRAD` at 0 and
 * `opsz` at 24 and no others, so a rule asking for a different value is not
 * refused — it is silently ignored, and the icon renders at the pinned value
 * with nothing on screen or in the console saying the declaration did nothing.
 * That failure mode did not exist before the font was subset (decisions § 780),
 * which is why the requests have to be read back out of the source rather than
 * assumed to still match.
 *
 * @param {{ path: string, text: string }[]} sources
 * @param {Readonly<Record<string, number>>} [pinned]
 * @returns {{ path: string, axis: string, value: number, pinnedAt: number }[]}
 */
export function pinnedAxisConflicts(sources, pinned = PINNED_AXES) {
	/** @type {{ path: string, axis: string, value: number, pinnedAt: number }[]} */
	const out = [];
	for (const { path, text } of sources) {
		for (const decl of text.matchAll(/font-variation-settings\s*:\s*([^;}]*)/g)) {
			for (const m of decl[1].matchAll(VARIATION_SETTING)) {
				const axis = m[1];
				if (!(axis in pinned)) continue;
				const value = Number(m[2]);
				if (value === pinned[axis]) continue;
				out.push({ path, axis, value, pinnedAt: pinned[axis] });
			}
		}
	}
	return out;
}
