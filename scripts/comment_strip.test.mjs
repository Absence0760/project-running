import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { stripComments } from './comment_strip.mjs';
import { DART_FILE, FIRMWARE_FILE } from './check_watch_ble_uuids.mjs';

/**
 * What survives, with the blanking asserted separately by length: writing the
 * expected run of spaces out by hand is a test that fails on its own
 * arithmetic rather than on the code.
 * @param {string} src
 * @param {'rust' | 'dart'} lang
 */
function kept(src, lang) {
	const out = stripComments(src, lang);
	assert.equal(out.length, src.length, 'comments are blanked, not removed');
	return out.trimEnd();
}

test('a line comment is blanked and the line it sat on survives', () => {
	assert.equal(kept('let a = 1; // note\nlet b = 2;', 'rust'), `let a = 1; ${' '.repeat(7)}\nlet b = 2;`);
});

test('a block comment nests, as both languages nest them', () => {
	const src = 'a /* one /* two */ still */ b';
	assert.equal(kept(src, 'rust').replace(/ +/g, ' '), 'a b');
	assert.equal(kept(src, 'dart').replace(/ +/g, ' '), 'a b');
});

test('a comment marker inside a string is not a comment', () => {
	assert.equal(kept('let u = "a//b";', 'rust'), 'let u = "a//b";');
	assert.equal(kept("var u = 'a/*b*/c';", 'dart'), "var u = 'a/*b*/c';");
});

// A Rust lifetime has no closing quote, so treating `'` as a string opener
// swallows the rest of the file.
test('a Rust lifetime is not a string', () => {
	const src = "fn f<'a>(s: &'a str) -> &'static str { s } // tail\n";
	assert.equal(kept(src, 'rust'), "fn f<'a>(s: &'a str) -> &'static str { s }");
});

test('a Rust char literal is a string, escapes and all', () => {
	assert.equal(kept("let c = '\\n'; // x", 'rust'), "let c = '\\n';");
	assert.equal(kept("let c = '/'; // x", 'rust'), "let c = '/';");
});

test('raw strings take no escapes', () => {
	assert.equal(kept('let s = r#"a\\"//b"#; // x', 'rust'), 'let s = r#"a\\"//b"#;');
	assert.equal(kept("var s = r'a\\'; // x", 'dart'), "var s = r'a\\';");
});

test("Dart's triple quotes span lines", () => {
	const src = "var s = '''a\n// not a comment\nb'''; // this one is";
	assert.equal(kept(src, 'dart'), src.slice(0, src.indexOf("; //") + 1));
});

test('an unterminated block comment or string throws rather than eating the file', () => {
	assert.throws(() => stripComments('a /* b', 'rust'), /unterminated block comment/);
	assert.throws(() => stripComments('let s = "a', 'rust'), /unterminated string/);
	assert.throws(() => stripComments("var s = 'a\nvar t = 2;", 'dart'), /unterminated string/);
});

// Every offset has to still name the same place, or a caller reporting a line
// number reports the wrong one.
test('the committed sources come back the same length, line for line', () => {
	for (const [path, lang] of [
		[FIRMWARE_FILE, 'rust'],
		[DART_FILE, 'dart'],
	]) {
		const src = readFileSync(path, 'utf-8');
		const out = stripComments(src, /** @type {'rust' | 'dart'} */ (lang));
		assert.equal(out.length, src.length, path);
		assert.equal(out.split('\n').length, src.split('\n').length, path);
	}
});

// The four guards that read through this lexer report line and column numbers,
// so a blanked comment has to leave the code after it at the same offset — not
// merely at the same total length.
test('a mid-line comment leaves the code after it at the same column', () => {
	const src = 'let a = 1; /* note */ let b = 2;';
	const out = stripComments(src, 'rust');
	assert.equal(out.indexOf('let b'), src.indexOf('let b'));
	assert.equal(out.indexOf('let a'), src.indexOf('let a'));
});

test('a comment marker inside a block comment does not end it early', () => {
	assert.equal(
		kept('let x = 1; /* a // b */ let y = 2;', 'rust').replace(/ {2,}/g, ' '),
		'let x = 1; let y = 2;',
	);
});

test('a block-comment opener inside a string is not a comment', () => {
	// The whole point of lexing rather than regexing: the string survives, and
	// nothing after it is swallowed.
	assert.equal(kept('let s = "/* not a comment"; // x', 'rust'), 'let s = "/* not a comment";');
});

test("Rust's byte literals are strings, prefix and all", () => {
	assert.equal(kept('let s = b"ab//cd"; // x', 'rust'), 'let s = b"ab//cd";');
	assert.equal(kept('let s = br#"a//b"#; // x', 'rust'), 'let s = br#"a//b"#;');
	assert.equal(kept("let c = b'a'; // x", 'rust'), "let c = b'a';");
});

test('a Rust raw identifier is not a raw string', () => {
	// `r#type` opens with the same two characters `r#"…"#` does, and reading it
	// as a string would swallow to the next quote anywhere in the file.
	assert.equal(kept('let r#type = 1; // x', 'rust'), 'let r#type = 1;');
});

test("a Dart escaped quote does not close its string", () => {
	assert.equal(kept("var s = 'it\\'s'; // x", 'dart'), "var s = 'it\\'s';");
});

// `${…}` is a nested CODE region (decisions § 816). Every case below is a
// shape the committed tree actually holds; before § 816 each one threw
// `unterminated string`, which the wire-vector guard then had to route around.

test('a differently-quoted string inside an interpolation does not end the string', () => {
	// `import_failures.dart`'s CSV quoting, verbatim. Library code, not a test.
	const src = `String _f(String v) => '"\${v.replaceAll('"', '""')}"'; // x`;
	assert.equal(kept(src, 'dart'), src.replace(' // x', ''));
});

test('a same-quoted string inside an interpolation does not end the string', () => {
	assert.equal(kept("var s = '${a('b')} c'; // x", 'dart'), "var s = '${a('b')} c';");
});

test('an interpolation may span lines even in a single-quoted string', () => {
	// `coach_screen_helpers_test.dart`'s SSE fixture in miniature: a newline and
	// a brace-carrying map literal inside a `${…}` in a '…' string, which Dart
	// allows and a content-only reading cannot.
	const src = ["var s = 'a: ${f({", "  'k': {'n': 1},", "})}'; // x"].join('\n');
	assert.equal(kept(src, 'dart'), src.replace(' // x', ''));
});

test('a bare newline is still unterminated when it is NOT inside an interpolation', () => {
	assert.throws(() => stripComments("var s = 'a\nvar t = 2;", 'dart'), /unterminated string/);
	assert.throws(() => stripComments("var s = 'a ${b}\nvar t = 2;", 'dart'), /unterminated string/);
});

test('a raw string interpolates nothing, so its ${ is content', () => {
	assert.equal(kept("var s = r'a ${not code'; // x", 'dart'), "var s = r'a ${not code';");
	const triple = `var s = r"""a \${b('c')}"""; // x`;
	assert.equal(kept(triple, 'dart'), triple.replace(' // x', ''));
});

test('the $identifier form needs no brace tracking', () => {
	assert.equal(kept("var s = 'a $b c'; // x", 'dart'), "var s = 'a $b c';");
	// An escaped `$` opens no region either, so the `{` after it is content.
	const escaped = String.raw`var s = 'a \${b} c'; // x`;
	assert.equal(kept(escaped, 'dart'), escaped.replace(' // x', ''));
});

test('braces nest inside an interpolation', () => {
	assert.equal(
		kept("var s = '${{'a': {'b': 1}}}'; // x", 'dart'),
		"var s = '${{'a': {'b': 1}}}';",
	);
});

test('a // inside a string inside an interpolation is not a comment', () => {
	assert.equal(
		kept("var s = 'at ${Uri.parse('https://x/y').host}'; // x", 'dart'),
		"var s = 'at ${Uri.parse('https://x/y').host}';",
	);
});

test('a real comment inside an interpolation IS blanked, like any other code', () => {
	// The region is code, so a comment in it is a comment. Only a multi-line
	// interpolation can carry a `//` and still close.
	const src = ["var s = '${f(", '  1, // one', ")}'; // x"].join('\n');
	assert.equal(
		kept(src, 'dart').replace(/ +$/gm, ''),
		["var s = '${f(", '  1,', ")}';"].join('\n'),
	);
	assert.equal(
		kept("var s = '${/* nine */ 9}'; // x", 'dart').replace(/ {2,}/g, ' '),
		"var s = '${ 9}';",
	);
});

/// decisions.md § 793 depended on an unlexable file THROWING rather than
/// returning something plausible, and § 816 keeps that: an interpolation that
/// never closes is source no guard may report a verdict about.
test('an interpolation that never closes throws rather than eating the file', () => {
	assert.throws(
		() => stripComments("var s = '${f(1); var t = 2;", 'dart'),
		/unterminated string interpolation/,
	);
});

// The hole § 816 closed was invisible because nothing read the whole tree, so
// this is the case that stops the next `${…}` shape reopening it silently.
test('every committed Dart file on the phone rail lexes', () => {
	/** @param {string} dir @returns {string[]} */
	const walk = (dir) =>
		readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
			const p = join(dir, e.name);
			return e.isDirectory() ? walk(p) : p.endsWith('.dart') ? [p] : [];
		});
	const root = join(import.meta.dirname, '..');
	const files = ['apps/mobile_android', 'packages'].flatMap((r) => walk(join(root, r)));
	assert.ok(files.length > 900, `expected the phone rail, found ${files.length} files`);
	/** @type {string[]} */
	const broken = [];
	for (const f of files) {
		const src = readFileSync(f, 'utf-8');
		try {
			const out = stripComments(src, 'dart');
			assert.equal(out.length, src.length, f);
			assert.equal(out.split('\n').length, src.split('\n').length, f);
		} catch (e) {
			broken.push(`${f}: ${e instanceof Error ? e.message : String(e)}`);
		}
	}
	assert.deepEqual(broken, []);
});

test('an unterminated raw string throws in both languages', () => {
	assert.throws(() => stripComments('let s = r#"abc', 'rust'), /unterminated raw string/);
	assert.throws(() => stripComments("var s = r'abc", 'dart'), /unterminated raw string/);
});

test('a nested block comment that closes only once is unterminated', () => {
	assert.throws(() => stripComments('a /* one /* two */ b', 'rust'), /unterminated block comment/);
	assert.equal(kept('a /*/ b */ c', 'rust').replace(/ {2,}/g, ' '), 'a c');
});
