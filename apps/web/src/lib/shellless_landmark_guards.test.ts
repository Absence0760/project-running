import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';

/**
 * Guards the `<main>` landmark on the SHELL-LESS route family (WCAG 1.3.1).
 *
 * `+layout.svelte` renders three branches. Two of them — the signed-in shell
 * and the anon-allowed content branch — wrap the slot in `<main
 * id="main-content">` and precede it with a skip link. The third, the
 * shell-less branch, renders a bare `<slot />`: whatever landmark those routes
 * get, they must own themselves.
 *
 * Ten of the twenty-four shipped without one. Three (`/auth/callback`,
 * `/learn/[slug]`, `/share/event/[id]/results`) had no `<main>` in any state.
 * The other seven had one only in a branch the visitor usually does not see:
 * `/share/{event,race,club,profile}` carried the landmark in their NOT-FOUND
 * card while the found entity — the primary state of four public, indexed,
 * SEO-bearing pages — rendered a bare `<section class="hero">`.
 *
 * The 2026-05-30 audit (see cross-cutting/skip-link.spec.ts) fixed exactly the
 * anon branch and left this one, which is why the gap survived: a route can sit
 * in `isShellless` and pass every existing a11y check.
 *
 * This guard derives the family from `+layout.svelte` rather than hard-coding a
 * list, so adding a shell-less prefix enrolls its pages automatically instead of
 * quietly opting them out.
 */

const webRoot = resolve(import.meta.dirname, '..', '..');
const routesDir = resolve(webRoot, 'src', 'routes');
const layout = readFileSync(resolve(routesDir, '+layout.svelte'), 'utf-8');

/** The `shellLessExact` array literal, as declared in the layout. */
function exactPaths(): string[] {
	const block = /const shellLessExact = \[([\s\S]*?)\];/.exec(layout);
	assert.ok(block, 'could not find the shellLessExact array in +layout.svelte');
	return [...block[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
}

/** The `path.startsWith('…')` prefixes inside the isShellless predicate. */
function prefixes(): string[] {
	const body = /const isShellless = \(path: string\) =>([\s\S]*?);\n/.exec(layout);
	assert.ok(body, 'could not find the isShellless predicate in +layout.svelte');
	return [...body[1].matchAll(/path\.startsWith\('([^']+)'\)/g)].map((m) => m[1]);
}

/**
 * Markup with HTML comments removed. Several of these pages explain the missing
 * layout landmark in a comment that necessarily contains the literal text
 * `<main>`, and a commented-out landmark is not a landmark either way — so
 * every count below has to run over the real markup.
 *
 * Scanned by index rather than by regex replacement, because **HTML comments do
 * not nest**: the first `-->` closes the comment, so in
 * `<!-- a <!-- b --> <main> -->` the `<main>` is real markup that a browser
 * renders, and anything that kept stripping past that point would hide a
 * landmark this guard is meant to see. CodeQL reads the equivalent one-pass
 * regex as `js/incomplete-multi-character-sanitization` and prescribes
 * replacing to a fixpoint; that advice is for removing dangerous sequences from
 * untrusted input, and applying it here would have introduced the bug it warns
 * about, in the opposite direction. Nothing user-supplied reaches this — it
 * reads the repo's own source.
 */
export function stripHtmlComments(source: string): string {
	let out = '';
	let i = 0;
	for (;;) {
		const open = source.indexOf('<!--', i);
		if (open === -1) return out + source.slice(i);
		out += source.slice(i, open);
		const close = source.indexOf('-->', open + 4);
		// An unterminated comment runs to end-of-file, as a parser would treat it.
		if (close === -1) return out;
		i = close + 3;
	}
}

function markup(file: string): string {
	return stripHtmlComments(readFileSync(file, 'utf-8'));
}

/**
 * Splits the top-level `{#if}` … `{:else}` … `{/if}` chains out of Svelte
 * markup, returning one string per branch per chain.
 *
 * Depth-tracked over every block form so a nested `{#if}`/`{#each}` inside a
 * branch stays part of that branch instead of being read as a sibling.
 */
function topLevelIfChains(src: string): string[][] {
	const token = /\{#(if|each|await|key|snippet)\b|\{:(else if|else)\b|\{\/(if|each|await|key|snippet)\}/g;
	const chains: string[][] = [];
	let depth = 0;
	let branches: string[] | null = null;
	let start = 0;
	let match: RegExpExecArray | null;

	while ((match = token.exec(src))) {
		const text = match[0];
		if (text.startsWith('{#')) {
			if (depth === 0 && text.startsWith('{#if')) {
				branches = [];
				start = token.lastIndex;
			}
			depth++;
		} else if (text.startsWith('{/')) {
			depth--;
			if (depth === 0 && branches) {
				branches.push(src.slice(start, match.index));
				chains.push(branches);
				branches = null;
			}
		} else if (depth === 1 && branches) {
			// An `{:else}` belonging to the top-level chain closes a branch.
			branches.push(src.slice(start, match.index));
			start = token.lastIndex;
		}
	}
	return chains;
}

function pagesUnder(dir: string): string[] {
	let out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) out = out.concat(pagesUnder(full));
		else if (entry === '+page.svelte') out.push(full);
	}
	return out;
}

/** Every `+page.svelte` the shell-less predicate can route to. */
function shellLessPages(): string[] {
	const found = new Set<string>();

	for (const path of exactPaths()) {
		const file = resolve(routesDir, path === '/' ? '+page.svelte' : `.${path}/+page.svelte`);
		// An exact entry names one concrete page; a miss means the layout and the
		// route tree have drifted, which is itself worth failing on.
		assert.ok(
			statSync(file).isFile(),
			`+layout.svelte lists ${path} as shell-less but ${file} does not exist`,
		);
		found.add(file);
	}

	for (const prefix of prefixes()) {
		// `/learn` has no trailing slash while `/share/` does; both name a directory.
		const dir = resolve(routesDir, `.${prefix.replace(/\/$/, '')}`);
		const pages = pagesUnder(dir);
		assert.ok(
			pages.length > 0,
			`shell-less prefix ${prefix} matched no +page.svelte — the guard would ` +
				`silently cover nothing`,
		);
		for (const p of pages) found.add(p);
	}

	return [...found].sort();
}

const PAGES = shellLessPages();

test('the shell-less family is a real, non-empty population', () => {
	// § 534: a guard that asserts over an empty set passes vacuously. Both
	// halves of the predicate must have contributed.
	assert.ok(exactPaths().length > 0, 'no exact shell-less paths parsed out of the layout');
	assert.ok(prefixes().length > 0, 'no shell-less prefixes parsed out of the layout');
	assert.ok(
		PAGES.length >= 20,
		`expected the shell-less family to span at least 20 pages, derived ${PAGES.length} — ` +
			`the parse probably broke rather than the tree shrinking`,
	);
});

test('the layout gives the shell-less branch no landmark of its own', () => {
	// The premise of this whole guard. If the layout ever wraps the shell-less
	// branch in a <main>, the per-page landmarks below become NESTED (invalid,
	// and two main landmarks to a screen reader) and this file should be
	// rewritten rather than kept passing.
	const branch = /\{#if isShellless\(\$page\.url\.pathname\)\}([\s\S]*?)\{:else if/.exec(layout);
	assert.ok(branch, 'could not find the shell-less branch in +layout.svelte');
	assert.ok(
		!stripHtmlComments(branch[1]).includes('<main'),
		'the shell-less branch now renders its own <main> — the per-page landmarks ' +
			'this guard requires would nest inside it. Strip them before doing that.',
	);
});

test('every shell-less page owns a <main> landmark', () => {
	const missing = PAGES.filter((p) => !markup(p).includes('<main'));
	assert.deepEqual(
		missing.map((p) => p.slice(routesDir.length + 1)),
		[],
		'these shell-less pages render no <main> landmark; the layout does not give ' +
			'them one, so they ship a page with no main region at all (WCAG 1.3.1)',
	);
});

test('a landmark in one branch of an if-chain appears in all of them', () => {
	// This is the shape the defect actually took, and the reason a plain
	// "does the file contain a <main>" check would have passed on seven of the
	// ten offenders: /share/{event,race,club,profile} put the landmark in their
	// not-found branch only, so grep saw a main while the primary state had
	// none. Requiring consistency WITHIN a chain catches that without forcing a
	// landmark onto single-branch blocks (the anon signup CTA) that shouldn't
	// have one.
	const offenders: string[] = [];
	for (const p of PAGES) {
		for (const branches of topLevelIfChains(markup(p))) {
			const withMain = branches.filter((b) => b.includes('<main')).length;
			if (withMain > 0 && withMain < branches.length) {
				offenders.push(
					`${p.slice(routesDir.length + 1)} (${withMain}/${branches.length} branches)`,
				);
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'these pages render a <main> in some branches of a top-level {#if} chain but ' +
			'not others, so the landmark is missing in a reachable state',
	);
});

test('every <main> on a shell-less page is the skip-link target', () => {
	// Uniform ids are what let the reflow + landmark e2e specs address the
	// region as `main#main-content` on ANY shell-less route, and what a skip
	// link for this branch would need. A page whose branches disagree is the
	// shape the original defect took, so the count has to match per file.
	const offenders: string[] = [];
	for (const p of PAGES) {
		const src = markup(p);
		const mains = (src.match(/<main\b/g) ?? []).length;
		const tagged = (src.match(/<main\b[^>]*id="main-content"/g) ?? []).length;
		if (mains !== tagged) offenders.push(`${p.slice(routesDir.length + 1)} (${tagged}/${mains})`);
	}
	assert.deepEqual(
		offenders,
		[],
		'every <main> on a shell-less page must carry id="main-content" (count shown ' +
			'as tagged/total)',
	);
});

test('comment stripping follows HTML comment semantics', () => {
	// HTML comments do not nest: the first `-->` closes, so this <main> is a real
	// element and must survive stripping. A fixpoint-replacing stripper — what
	// CodeQL's advice for this rule prescribes — deletes it, which would make the
	// guard blind to a landmark that is genuinely there.
	assert.equal(stripHtmlComments('<!-- a <!-- b --> <main> -->'), ' <main> -->');
	// Both directions, so a stripper that returned its input unchanged, or one
	// that deleted everything, fails.
	assert.equal(stripHtmlComments('<!-- <main> -->').includes('<main'), false);
	assert.equal(stripHtmlComments('<main id="main-content">'), '<main id="main-content">');
	// Unterminated: a parser swallows the rest of the file, so neither may count.
	assert.equal(stripHtmlComments('<main> <!-- trailing <main>'), '<main> ');
});
