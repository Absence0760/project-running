/**
 * Comment bodies removed from JS / TS / Svelte source, so prose describing a
 * banned shape is never read as an instance of it.
 *
 * Every source-level guard in this tree needs this, and each one used to spell
 * its own chain of `.replace` calls. A chain cannot do it, and the copies got
 * three different cases wrong:
 *
 *  - Stripping `/* … *\/` before blanking `//` lets a line comment containing
 *    `/*` open a block that swallows every line to the next `*\/`. Measured at
 *    779 lines across 3 files when it was found (decisions § 971).
 *  - Blanking `//` first still leaves a `/*` inside a STRING literal opening
 *    the same phantom block.
 *  - Neither survives a regex literal: `/\/\*…\*\//g` carries both
 *    delimiters, escaped.
 *
 * One forward pass instead, over code / string / template / regex, with a
 * previous-significant-character test to tell a regex literal from division.
 * Comment characters become spaces and newlines are kept, so an offset or a
 * line number taken from the result is the file's own.
 *
 * Strings and regex literals are emitted VERBATIM, so a misread of either can
 * only leave a comment standing — never delete code. That direction is chosen:
 * an unstripped comment makes a guard report a violation it can be argued out
 * of, where a swallowed region makes a guard pass while seeing nothing.
 *
 * Single-quoted, double-quoted and regex literals cannot cross a newline in
 * JavaScript, so an unterminated one is treated as an ordinary character and
 * the damage from a misread is bounded to its line. Svelte markup is scanned
 * as code, which is what the copies this replaced did.
 */

/** Characters after which a `/` opens a regex literal rather than dividing. */
const REGEX_PRECEDERS = new Set([
	'',
	'(',
	',',
	'=',
	':',
	'[',
	'!',
	'&',
	'|',
	'?',
	';',
	'+',
	'-',
	'*',
	'%',
	'~',
	'^',
	'{',
]);

/** Keywords after which a `/` opens a regex literal. */
const REGEX_KEYWORDS = new Set([
	'return',
	'typeof',
	'instanceof',
	'in',
	'of',
	'new',
	'delete',
	'void',
	'case',
	'do',
	'else',
	'yield',
	'await',
	'throw',
]);

/** Index just past a quoted string starting at `i`, or -1 if it does not close on its line. */
function endOfQuoted(source: string, i: number): number {
	const quote = source[i];
	for (let k = i + 1; k < source.length; k++) {
		const c = source[k];
		if (c === '\\') {
			k++;
			continue;
		}
		if (c === '\n') return -1;
		if (c === quote) return k + 1;
	}
	return -1;
}

/** Index just past a regex literal starting at `i`, or -1 if it does not close on its line. */
function endOfRegex(source: string, i: number): number {
	let inClass = false;
	for (let k = i + 1; k < source.length; k++) {
		const c = source[k];
		if (c === '\\') {
			k++;
			continue;
		}
		if (c === '\n') return -1;
		if (inClass) {
			if (c === ']') inClass = false;
			continue;
		}
		if (c === '[') inClass = true;
		else if (c === '/') return k + 1;
	}
	return -1;
}

export function stripComments(source: string): string {
	const out: string[] = [];
	const n = source.length;

	// Frames for template literals: each `${` inside one re-enters code, and
	// the `}` that matches it returns to the template. Without the stack a
	// nested template (`${a ? `x` : `y`}`) closes the outer one early.
	const braceDepth: number[] = [];
	let inTemplate = false;

	// Trailing window of emitted code: its last non-whitespace character and
	// the identifier that character ends are what decide regex-versus-division.
	// A comment contributes nothing to it, so `return /* c *\/ /re/` still reads
	// the `return`.
	let tail = '';

	const blank = (from: number, to: number): void => {
		for (let k = from; k < to; k++) out.push(source[k] === '\n' ? '\n' : ' ');
	};

	const emit = (from: number, to: number): void => {
		const text = source.slice(from, to);
		out.push(text);
		tail = (tail + text).replace(/\s+$/, '').slice(-24);
	};

	const prev = (): { char: string; word: string } => ({
		char: tail.slice(-1),
		word: /[A-Za-z_$][\w$]*$/.exec(tail)?.[0] ?? '',
	});

	let i = 0;
	while (i < n) {
		const c = source[i];

		if (inTemplate) {
			if (c === '\\') {
				emit(i, Math.min(i + 2, n));
				i += 2;
				continue;
			}
			if (c === '`') {
				emit(i, i + 1);
				inTemplate = false;
				i++;
				continue;
			}
			if (c === '$' && source[i + 1] === '{') {
				emit(i, i + 2);
				braceDepth.push(0);
				inTemplate = false;
				i += 2;
				continue;
			}
			emit(i, i + 1);
			i++;
			continue;
		}

		if (c === '/' && source[i + 1] === '/') {
			let k = i;
			while (k < n && source[k] !== '\n') k++;
			blank(i, k);
			i = k;
			continue;
		}

		if (c === '/' && source[i + 1] === '*') {
			const close = source.indexOf('*/', i + 2);
			const k = close < 0 ? n : close + 2;
			blank(i, k);
			i = k;
			continue;
		}

		if (c === '"' || c === "'") {
			const k = endOfQuoted(source, i);
			emit(i, k < 0 ? i + 1 : k);
			i = k < 0 ? i + 1 : k;
			continue;
		}

		if (c === '`') {
			emit(i, i + 1);
			inTemplate = true;
			i++;
			continue;
		}

		if (c === '/') {
			const { char, word } = prev();
			if (REGEX_PRECEDERS.has(char) || REGEX_KEYWORDS.has(word)) {
				const k = endOfRegex(source, i);
				emit(i, k < 0 ? i + 1 : k);
				i = k < 0 ? i + 1 : k;
				continue;
			}
		}

		if (braceDepth.length > 0) {
			if (c === '{') braceDepth[braceDepth.length - 1]++;
			else if (c === '}') {
				if (braceDepth[braceDepth.length - 1] === 0) {
					braceDepth.pop();
					emit(i, i + 1);
					inTemplate = true;
					i++;
					continue;
				}
				braceDepth[braceDepth.length - 1]--;
			}
		}

		emit(i, i + 1);
		i++;
	}

	return out.join('');
}
