// The register of every file allowed to spell a comment delimiter. A guard
// that reads source as text has to blank comments, and a hand-rolled
// stripper cannot — so the rule is single-sourced in core/strip_comments
// and this is the one place a lane adding a scanner has to edit.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripComments } from './core/strip_comments';

const __dirname = dirname(fileURLToPath(import.meta.url));

test('every source-scanning guard blanks comments through the one shared stripper', () => {
	// Reason: a guard that reads source as text has to blank comments, or the
	// prose above a rule reads as a use of it. Thirteen spellings across twelve
	// files each did it with their own chain of `.replace` calls, and a chain
	// cannot: `//` is a comment to the language but `/*` inside one is still an
	// opening delimiter to a regex, so stripping block comments FIRST makes
	// `// exactly as /clubs/* already do` open a block that runs to the next
	// `*/` in the file. Measured when that was found: 779 lines hidden across 3
	// files, 485 of them in `runs/[id]/+page.svelte`, which carries a
	// `PUBLIC_SITE_URL` fold that `site_url.test.ts` was scanning right past
	// while reporting a pass (decisions § 971). Blanking `//` first still
	// leaves the same hole open from inside a string literal, which no copy
	// handled (decisions § 1000).
	//
	// So the rule is now single-sourced, not merely ordered: `core/
	// strip_comments.ts` scans instead of substituting, and a guard that wants
	// comments blanked imports it.
	//
	// This check used to key on ONE spelling of the block strip, which is why
	// three hand-rolled scanners sat beside it unseen — including one whose
	// `/*` inside an HTML comment blanked 906 lines out from under a guard
	// reporting a pass, § 971 recurring where its own guard could not look
	// (decisions § 1034). A spelling is the wrong thing to key on: the
	// DELIMITERS are a closed set of three, and a regex that recognises a
	// JavaScript comment has to escape the slash in at least one of them. So
	// the needle is the delimiter, and the register below is every file still
	// allowed to spell one, with the count it may spell and why.
	const B = String.fromCharCode(92);
	const NEEDLES = [B + '/' + B + '/', B + '/' + B + '*', B + '*' + B + '/'];

	const REGISTER: Array<{ file: string; count: number; why: string }> = [
		{
			file: 'src/lib/contrast_guard.test.ts',
			count: 10,
			why: 'scans CSS, where `//` is not a comment: blanking it would delete a protocol-relative url() or a content: string.',
		},
		{
			file: 'src/lib/rtl_css_guards.test.ts',
			count: 2,
			why: 'scans CSS, same reason.',
		},
		{
			file: 'src/lib/a11y_guards.test.ts',
			count: 2,
			why: 'the :focus/:focus-visible pairing scan reads <style> blocks, which are CSS.',
		},
		{
			file: 'src/lib/consent_guards.test.ts',
			count: 2,
			why: 'the font-source scan reads app.css, where `//` is not a comment.',
		},
		{
			file: 'src/lib/seo_render_map_guard.test.ts',
			count: 1,
			why: 'trims the trailing wildcard off a CloudFront `path_pattern`, which is a route glob and not a comment.',
		},
		{
			file: 'src/lib/share/share_entity_dispatch_guard.test.ts',
			count: 1,
			why: 'the same CloudFront `path_pattern` wildcard trim.',
		},
		{
			file: 'src/lib/share_run_cache_control.test.ts',
			count: 1,
			why: 'matches the Terraform `path_pattern = "/og/run/*"` literal.',
		},
		{
			file: 'src/lib/share/share_head_origin.test.ts',
			count: 1,
			why: 'refuses a doubled slash in a URL PATH — the scheme`s own `//` is excluded by the needle, this one is not.',
		},
		{
			file: 'tests-e2e/fixtures/tsconfig-coverage.test.ts',
			count: 3,
			why: 'matches the `tests-e2e/**/*.<ext>` include globs; the config`s own comments go through the shared stripper.',
		},
	];

	const hits = (text: string): number => {
		let n = 0;
		for (const needle of NEEDLES) {
			let at = text.indexOf(needle);
			while (at !== -1) {
				// `https:` + `//` is a scheme, not a comment.
				if (text[at - 1] !== ':') n++;
				at = text.indexOf(needle, at + 1);
			}
		}
		return n;
	};

	// The needle set against every strip spelling this tree has carried, plus
	// the two shapes it must NOT claim. Written as source text rather than as
	// regex literals so this file does not become its own offender.
	for (const spelling of [
		'/^' + B + 's*' + B + '/' + B + '//',
		'/' + B + 's' + B + '/' + B + '/.*$/',
		'/(^|[^:])' + B + '/' + B + '/[^' + B + 'n]*/g',
		'/' + B + '/' + B + '/.*$/gm',
		'/(?<!:)' + B + '/' + B + '/[^' + B + 'n]*/g',
		'/' + B + '/' + B + '*[' + B + 's' + B + 'S]*?' + B + '*' + B + '//g',
		'/' + B + '/' + B + '*[' + B + 's' + B + 'S]*?(?:' + B + '*' + B + '/|$)/g',
	]) {
		assert.ok(hits(spelling) > 0, `the needle set does not see ${spelling}`);
	}
	assert.equal(hits("/^https:" + B + "/" + B + "/[a-z]+$/"), 0, 'a URL scheme is not a comment');
	assert.equal(hits('/^tests-e2e/**/*.ts$/'), 0, 'an unescaped glob is not a comment');

	const files: string[] = [];
	const webRoot = resolve(__dirname, '..', '..');
	for (const root of ['src', 'tests-e2e', 'lambda']) {
		(function walk(dir: string): void {
			for (const entry of readdirSync(dir, { withFileTypes: true })) {
				if (entry.name === 'node_modules') continue;
				const full = resolve(dir, entry.name);
				if (entry.isDirectory()) walk(full);
				else if (/\.(ts|svelte)$/.test(entry.name)) files.push(full);
			}
		})(resolve(webRoot, root));
	}

	// Population: a walker that found nothing would satisfy the assertions
	// below while proving nothing (decisions § 534).
	assert.ok(files.length > 500, `found only ${files.length} sources — walker broken?`);

	const found = new Map<string, number>();
	let importers = 0;
	for (const file of files) {
		// Through the shared stripper, so prose describing a delimiter is not
		// counted as one — this file`s own header would otherwise be first.
		const src = stripComments(readFileSync(file, 'utf-8'));
		const rel = file.slice(webRoot.length + 1).split(sep).join('/');
		let n = 0;
		for (const needle of NEEDLES) {
			let at = src.indexOf(needle);
			while (at !== -1) {
				// `https:` + `//` is a scheme, not a comment.
				if (src[at - 1] !== ':') n++;
				at = src.indexOf(needle, at + 1);
			}
		}
		if (n > 0) found.set(rel, n);
		if (/from '[^']*strip_comments'/.test(src)) importers++;
	}

	assert.ok(
		importers >= 18,
		`only ${importers} guards import the shared stripper — a copy has been reintroduced?`,
	);

	const registered = new Map(REGISTER.map((r) => [r.file, r.count]));
	const offenders = [...found]
		.filter(([f, n]) => registered.get(f) !== n)
		.map(([f, n]) => `${f} (${n}, registered ${registered.get(f) ?? 'not at all'})`);
	assert.deepEqual(
		offenders.sort(),
		[],
		'a comment delimiter spelled outside the register. If the file blanks ' +
			'comments, import `stripComments` from $lib/core/strip_comments — it is ' +
			'the only copy that survives a `/*` inside a line comment, a string or a ' +
			'regex literal. A CSS scanner, a route glob or a URL check goes in the ' +
			'register with the reason it is not comment handling.',
	);

	const stale = REGISTER.filter((r) => !found.has(r.file)).map((r) => r.file);
	assert.deepEqual(
		stale.sort(),
		[],
		'registered file(s) no longer spell a comment delimiter — delete the entry.',
	);
});
