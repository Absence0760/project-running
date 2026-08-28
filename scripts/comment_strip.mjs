// Blank the comments out of Rust and Dart source, keeping every other byte
// where it was.
//
// check_watch_ble_uuids.mjs read both of its sources with regexes that had no
// idea what a comment was, so a UUID quoted in prose answered for the live
// declaration (decisions § 773). The firmware's `gatt_service` match was not
// global, so the FIRST occurrence anywhere in ble.rs won — a doc comment
// beats the attribute below it — and the Dart side's 40-character window
// crossed a `//`, so a commented-out constant read as a live one. A stale
// table preserved in each file's comments then agreed with itself while both
// declarations had drifted: § 410's one-row shift passing the guard built to
// catch it, with the `size === 0` blindness checks satisfied by the wrong
// values.
//
// Comments are replaced by spaces rather than removed so every offset, line
// and column in the result still names the same place in the original.
//
// What is tracked, per language: `//` to end of line, `/* */` NESTED (both
// languages nest them), `"…"` with backslash escapes, Rust raw strings
// (`r"…"`, `r#"…"#`), Rust char literals — distinguished from lifetimes,
// which are not closed and would otherwise swallow the rest of the file —
// and Dart's `'…'`, `'''…'''`, `"""…"""` and `r`-prefixed strings.
//
// An unterminated block comment or string THROWS, for the reason
// apps/backend/scripts/sql_lex.mjs throws: source the lexer cannot read is
// source a guard must not report a verdict about.
//
// Unit tests: `node --test scripts/comment_strip.test.mjs`

/// A Rust char literal at the cursor — `'a'`, `'\n'`, `'\u{1F}'`. Anything
/// else beginning with `'` is a lifetime (`'static`, `'a`), which has no
/// closing quote at all.
const RUST_CHAR = /^'(?:\\(?:u\{[0-9a-fA-F]{1,6}\}|x[0-9a-fA-F]{2}|.)|[^\\'])'/;

/**
 * @param {string} src
 * @param {'rust' | 'dart'} lang
 * @returns {string} the source with every comment replaced by spaces.
 */
export function stripComments(src, lang) {
	let out = '';
	let i = 0;

	/** @param {number} from @param {number} to */
	const keep = (from, to) => {
		out += src.slice(from, to);
	};
	/** @param {number} from @param {number} to */
	const blank = (from, to) => {
		for (let k = from; k < to; k++) out += src[k] === '\n' ? '\n' : ' ';
	};
	/** @param {string} what @param {number} at */
	const unterminated = (what, at) => {
		const line = src.slice(0, at).split('\n').length;
		throw new Error(`comment_strip: unterminated ${what} at line ${line}`);
	};

	while (i < src.length) {
		const two = src.slice(i, i + 2);

		if (two === '//') {
			const nl = src.indexOf('\n', i);
			const end = nl === -1 ? src.length : nl;
			blank(i, end);
			i = end;
			continue;
		}

		if (two === '/*') {
			let depth = 0;
			let k = i;
			while (k < src.length) {
				if (src.slice(k, k + 2) === '/*') {
					depth++;
					k += 2;
					continue;
				}
				if (src.slice(k, k + 2) === '*/') {
					depth--;
					k += 2;
					if (depth === 0) break;
					continue;
				}
				k++;
			}
			if (depth !== 0) unterminated('block comment', i);
			blank(i, k);
			i = k;
			continue;
		}

		// Raw strings take no escapes, so only the delimiter closes them.
		if (lang === 'rust' && src[i] === 'r' && /[#"]/.test(src[i + 1] ?? '')) {
			let hashes = 0;
			while (src[i + 1 + hashes] === '#') hashes++;
			if (src[i + 1 + hashes] === '"') {
				const close = `"${'#'.repeat(hashes)}`;
				const at = src.indexOf(close, i + 2 + hashes);
				if (at === -1) unterminated('raw string', i);
				keep(i, at + close.length);
				i = at + close.length;
				continue;
			}
		}
		if (lang === 'dart' && src[i] === 'r' && /['"]/.test(src[i + 1] ?? '')) {
			const q = src[i + 1];
			const triple = src.slice(i + 1, i + 4) === q.repeat(3) ? q.repeat(3) : q;
			const at = src.indexOf(triple, i + 1 + triple.length);
			if (at === -1) unterminated('raw string', i);
			keep(i, at + triple.length);
			i = at + triple.length;
			continue;
		}

		if (lang === 'rust' && src[i] === "'") {
			const m = RUST_CHAR.exec(src.slice(i));
			if (m) {
				keep(i, i + m[0].length);
				i += m[0].length;
			} else {
				// A lifetime. One character, and the loop carries on.
				keep(i, i + 1);
				i++;
			}
			continue;
		}

		const quote = src[i];
		const isQuote = quote === '"' || (lang === 'dart' && quote === "'");
		if (isQuote) {
			const triple = src.slice(i, i + 3) === quote.repeat(3);
			const delim = triple ? quote.repeat(3) : quote;
			let k = i + delim.length;
			for (;;) {
				if (k >= src.length) unterminated('string', i);
				if (src[k] === '\\') {
					k += 2;
					continue;
				}
				if (src.slice(k, k + delim.length) === delim) break;
				if (!triple && src[k] === '\n') unterminated('string', i);
				k++;
			}
			keep(i, k + delim.length);
			i = k + delim.length;
			continue;
		}

		out += src[i];
		i++;
	}

	if (out.length !== src.length) {
		throw new Error(`comment_strip: length changed ${src.length} -> ${out.length}`);
	}
	return out;
}
