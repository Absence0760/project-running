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
// Dart's `${…}` interpolation is a nested CODE region, not string content,
// and is tracked as one (decisions § 816). Inside it live strings — including
// differently-quoted ones, which is what `'"${v.replaceAll('"', '""')}"'`
// is — braces of their own, further interpolations, comments, and newlines
// even when the enclosing string is single-quoted. Reading the region as
// content instead threw `unterminated string` on eight committed Dart files,
// four of them the byte-identical iOS twins, one of them library code rather
// than a test. A `$` that does not open a brace is the `$identifier` form and
// needs no tracking: it can hold no delimiter. `r`-prefixed strings take no
// interpolation at all — `$` is literal — so they stay a single verbatim span.
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

	/**
	 * The end of the nested block comment opening at `from`, past its closer.
	 * @param {number} from
	 */
	const blockCommentEnd = (from) => {
		let depth = 0;
		let k = from;
		while (k < src.length) {
			if (src.slice(k, k + 2) === '/*') {
				depth++;
				k += 2;
				continue;
			}
			if (src.slice(k, k + 2) === '*/') {
				depth--;
				k += 2;
				if (depth === 0) return k;
				continue;
			}
			k++;
		}
		unterminated('block comment', from);
		return k;
	};

	/**
	 * A Dart `r`-prefixed string at `from`, kept verbatim: raw strings take no
	 * escapes and no interpolation, so only the delimiter closes them.
	 * @param {number} from
	 * @returns {number} the index past the closing delimiter.
	 */
	const dartRawEnd = (from) => {
		const q = src[from + 1];
		const triple = src.slice(from + 1, from + 4) === q.repeat(3) ? q.repeat(3) : q;
		const at = src.indexOf(triple, from + 1 + triple.length);
		if (at === -1) unterminated('raw string', from);
		keep(from, at + triple.length);
		return at + triple.length;
	};

	/** @param {number} at */
	const isDartRaw = (at) => src[at] === 'r' && /['"]/.test(src[at + 1] ?? '');

	/**
	 * A Dart string at `from`, emitting its content verbatim and recursing into
	 * every `${…}` region it carries.
	 * @param {number} from
	 * @returns {number} the index past the closing delimiter.
	 */
	const dartStringEnd = (from) => {
		const quote = src[from];
		const triple = src.slice(from, from + 3) === quote.repeat(3);
		const delim = triple ? quote.repeat(3) : quote;
		let k = from + delim.length;
		let seg = from;
		for (;;) {
			if (k >= src.length) unterminated('string', from);
			if (src[k] === '\\') {
				k += 2;
				continue;
			}
			if (src.slice(k, k + delim.length) === delim) break;
			if (src[k] === '$' && src[k + 1] === '{') {
				keep(seg, k + 2);
				k = dartInterpolationEnd(k + 2, from);
				seg = k;
				continue;
			}
			// A newline can only reach here as string content: the interpolation
			// scanner has already consumed any that sat inside a `${…}`.
			if (!triple && src[k] === '\n') unterminated('string', from);
			k++;
		}
		keep(seg, k + delim.length);
		return k + delim.length;
	};

	/**
	 * A Dart `${…}` region, `from` pointing just past the `${`. Code, so its
	 * comments are blanked like any others and its own strings recurse.
	 * @param {number} from
	 * @param {number} stringAt the enclosing string, for the error's line number.
	 * @returns {number} the index past the matching `}`.
	 */
	const dartInterpolationEnd = (from, stringAt) => {
		let k = from;
		let depth = 1;
		let seg = from;
		for (;;) {
			if (k >= src.length) unterminated('string interpolation', stringAt);
			const two = src.slice(k, k + 2);
			if (two === '//') {
				keep(seg, k);
				const nl = src.indexOf('\n', k);
				const end = nl === -1 ? src.length : nl;
				blank(k, end);
				k = end;
				seg = k;
				continue;
			}
			if (two === '/*') {
				keep(seg, k);
				const end = blockCommentEnd(k);
				blank(k, end);
				k = end;
				seg = k;
				continue;
			}
			if (isDartRaw(k)) {
				keep(seg, k);
				k = dartRawEnd(k);
				seg = k;
				continue;
			}
			if (src[k] === '"' || src[k] === "'") {
				keep(seg, k);
				k = dartStringEnd(k);
				seg = k;
				continue;
			}
			if (src[k] === '{') {
				depth++;
				k++;
				continue;
			}
			if (src[k] === '}') {
				depth--;
				k++;
				if (depth === 0) {
					keep(seg, k);
					return k;
				}
				continue;
			}
			k++;
		}
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
			const end = blockCommentEnd(i);
			blank(i, end);
			i = end;
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
		if (lang === 'dart' && isDartRaw(i)) {
			i = dartRawEnd(i);
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
			if (lang === 'dart') {
				i = dartStringEnd(i);
				continue;
			}
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
