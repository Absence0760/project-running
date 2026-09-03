import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from './strip_comments';

const sp = (n: number) => ' '.repeat(n);

test('a line comment is removed and its line survives', () => {
	assert.equal(stripComments('const a = 1; // set a\nconst b = 2;'), 'const a = 1;' + sp(9) + '\nconst b = 2;');
});

test('a block comment is removed and the newlines it spanned survive', () => {
	assert.equal(stripComments('a\n/* one\n   two */\nb'), 'a\n' + sp(6) + '\n' + sp(9) + '\nb');
});

test('a line comment containing an opening block delimiter opens nothing', () => {
	// The exact § 971 defect: block-first swallows to the next `*/`.
	const src = ['// same shape as /clubs/* already does', 'const kept = 1;', '/* real */', 'const also = 2;'].join(
		'\n',
	);
	const out = stripComments(src);
	assert.ok(out.includes('const kept = 1;'), out);
	assert.ok(out.includes('const also = 2;'), out);
});

test('an opening block delimiter inside a string literal opens nothing', () => {
	const src = ["const glob = '/*';", 'const kept = 1;', "const end = '*/';", 'const also = 2;'].join('\n');
	const out = stripComments(src);
	assert.ok(out.includes('const kept = 1;'), out);
	assert.ok(out.includes('const also = 2;'), out);
	assert.ok(out.includes("'/*'"), out);
});

test('an opening block delimiter inside a template literal opens nothing', () => {
	const out = stripComments('const g = `/*`;\nconst kept = 1;\nconst e = `*/`;\nconst also = 2;');
	assert.ok(out.includes('const kept = 1;'), out);
	assert.ok(out.includes('const also = 2;'), out);
});

test('a comment marker inside a string is left alone', () => {
	assert.equal(
		stripComments("const u = 'https://example.com/a'; // note"),
		"const u = 'https://example.com/a';" + sp(8),
	);
	assert.equal(stripComments('const s = "// not a comment";'), 'const s = "// not a comment";');
});

test('a regex literal carrying both comment delimiters survives whole', () => {
	const src = 'const re = /\\/\\*[\\s\\S]*?\\*\\//g;\nconst kept = 1;';
	assert.equal(stripComments(src), src);
});

test('a regex literal with a slash inside a character class survives whole', () => {
	const src = 'const re = /[^/]*\\/x/;\nconst kept = 1;';
	assert.equal(stripComments(src), src);
});

test('division is not mistaken for a regex literal', () => {
	assert.equal(stripComments('const r = a / b; // c'), 'const r = a / b;' + sp(5));
});

test('a regex literal after a keyword is recognised', () => {
	assert.equal(stripComments('return /a\\/*b/.test(s); // c'), 'return /a\\/*b/.test(s);' + sp(5));
});

test('a comment inside a template expression is removed, and the template closes once', () => {
	const out = stripComments('const t = `a${b /* c */}d`;\nconst kept = 1;');
	assert.equal(out, 'const t = `a${b' + sp(8) + '}d`;\nconst kept = 1;');
});

test('a nested template inside an expression does not close the outer one early', () => {
	const src = 'const t = `${x ? `y` : `z`}`; // tail\nconst kept = 1;';
	assert.equal(stripComments(src), 'const t = `${x ? `y` : `z`}`;' + sp(8) + '\nconst kept = 1;');
});

test('an unterminated quote is treated as an ordinary character, not a string', () => {
	// A JS string cannot cross a newline, so an apostrophe in Svelte markup
	// must not swallow the rest of the file.
	const out = stripComments("<p>don't</p>\n// gone\nconst kept = 1;");
	assert.ok(out.includes('const kept = 1;'), out);
	assert.ok(!out.includes('gone'), out);
});

test('an unterminated block comment is blanked to end of file', () => {
	assert.equal(stripComments('a\n/* open\nb'), 'a\n' + sp(7) + '\n' + sp(1));
});

test('offsets and line count are the source file’s own', () => {
	const src = 'a; // x\n/* y\n   z */\nb;';
	const out = stripComments(src);
	assert.equal(out.length, src.length);
	assert.equal(out.split('\n').length, src.split('\n').length);
});

test('stripping this tree preserves length and is idempotent', () => {
	// Population + shape check over the real corpus the guards scan. A pass
	// that changed a file's length, or that found more to strip on a second
	// run, would mean the scanner had mis-synchronised somewhere.
	const root = resolve(import.meta.dirname, '..', '..');
	const files: string[] = [];
	(function walk(dir: string): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			if (entry.name === 'node_modules') continue;
			const full = resolve(dir, entry.name);
			if (entry.isDirectory()) walk(full);
			else if (/\.(ts|svelte)$/.test(entry.name)) files.push(full);
		}
	})(root);
	assert.ok(files.length > 500, `found only ${files.length} sources — walker broken?`);

	for (const file of files) {
		const src = readFileSync(file, 'utf-8');
		const once = stripComments(src);
		assert.equal(once.length, src.length, `length changed for ${file}`);
		assert.equal(stripComments(once), once, `not idempotent for ${file}`);
	}
});
