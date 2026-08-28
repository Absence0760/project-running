import { readFileSync } from 'node:fs';
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
