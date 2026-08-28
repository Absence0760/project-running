// Split Postgres SQL into statements, the way Postgres reads it.
//
// A `;` only terminates a statement when it is not inside something. Splitting
// on the character alone fragments every `$$`-quoted function body — 504 of
// them across the committed migrations, carrying 3540 semicolons between them —
// so a guard reading the pieces grades text that was never a statement.
// The failure is not only cosmetic and not only in the safe direction: eating
// `--` to end of line before knowing whether it is a comment swallows the
// terminator of any statement whose literal contains one (there is a committed
// example, 20270518_001), which glues the next statement onto it and lets a
// `not valid` from the following line vouch for the one before.
//
// Constructs tracked: `--` line comments, `/* */` block comments (NESTED, as
// Postgres nests them), `'…'` literals with `''` and E-string backslash
// escapes, `"…"` quoted identifiers with `""` escapes, and `$tag$…$tag$`
// dollar quotes. `$1` is a positional parameter, not a dollar quote — a tag
// cannot start with a digit.
//
// Unterminated anything THROWS rather than consuming to end of file: SQL the
// lexer cannot read is SQL a guard must not report a verdict about.

/** A dollar-quote opener at the cursor: `$$` or `$tag$`. */
const DOLLAR_OPEN = /^\$([A-Za-z_\u0080-\uffff][A-Za-z0-9_\u0080-\uffff]*)?\$/;

/**
 * True when the quote at `index` opens an E-string, whose body takes
 * backslash escapes (`e'a\'b'` is one literal, not two).
 * @param {string} sql
 * @param {number} index
 * @returns {boolean}
 */
function isEscapeString(sql, index) {
	if (index === 0) return false;
	const prev = sql[index - 1];
	if (prev !== 'e' && prev !== 'E') return false;
	const before = index >= 2 ? sql[index - 2] : '';
	return !/[A-Za-z0-9_$]/.test(before);
}

/**
 * @param {string} sql
 * @param {{ blankLiterals?: boolean }} [options] blank the CONTENT of every
 *   literal, quoted identifier and dollar-quoted body, keeping the delimiters.
 *   A guard grading SQL keywords wants this: `check (note <> 'not valid')`
 *   otherwise reads as a statement carrying `not valid`.
 * @returns {string[]} one entry per statement, comments removed, in file order.
 *   A trailing fragment after the last `;` is included; whitespace-only ones
 *   are dropped.
 */
export function splitSqlStatements(sql, options = {}) {
	const blank = options.blankLiterals === true;
	/** @type {string[]} */
	const statements = [];
	let buffer = '';
	let i = 0;

	/**
	 * @param {number} at
	 * @param {string} what
	 */
	const unterminated = (at, what) => {
		const line = sql.slice(0, at).split('\n').length;
		return new Error(`unterminated ${what} opened at line ${line}`);
	};

	while (i < sql.length) {
		const char = sql[i];

		if (char === '-' && sql[i + 1] === '-') {
			while (i < sql.length && sql[i] !== '\n') i++;
			buffer += ' ';
			continue;
		}

		if (char === '/' && sql[i + 1] === '*') {
			const opened = i;
			let depth = 0;
			while (i < sql.length) {
				if (sql[i] === '/' && sql[i + 1] === '*') {
					depth++;
					i += 2;
					continue;
				}
				if (sql[i] === '*' && sql[i + 1] === '/') {
					depth--;
					i += 2;
					if (depth === 0) break;
					continue;
				}
				i++;
			}
			if (depth !== 0) throw unterminated(opened, 'block comment');
			buffer += ' ';
			continue;
		}

		if (char === "'" || char === '"') {
			const opened = i;
			const escapes = char === "'" && isEscapeString(sql, i);
			let body = '';
			i++;
			let closed = false;
			while (i < sql.length) {
				if (escapes && sql[i] === '\\' && i + 1 < sql.length) {
					body += sql.slice(i, i + 2);
					i += 2;
					continue;
				}
				if (sql[i] === char && sql[i + 1] === char) {
					body += char + char;
					i += 2;
					continue;
				}
				if (sql[i] === char) {
					i++;
					closed = true;
					break;
				}
				body += sql[i];
				i++;
			}
			if (!closed) {
				throw unterminated(opened, char === "'" ? 'string literal' : 'quoted identifier');
			}
			buffer += char + (blank ? '' : body) + char;
			continue;
		}

		if (char === '$') {
			const open = DOLLAR_OPEN.exec(sql.slice(i));
			if (open) {
				const tag = open[0];
				const end = sql.indexOf(tag, i + tag.length);
				if (end === -1) throw unterminated(i, `dollar-quoted body ${tag}`);
				buffer += tag + (blank ? '' : sql.slice(i + tag.length, end)) + tag;
				i = end + tag.length;
				continue;
			}
		}

		if (char === ';') {
			statements.push(buffer);
			buffer = '';
			i++;
			continue;
		}

		buffer += char;
		i++;
	}
	statements.push(buffer);

	return statements.filter((s) => s.trim() !== '');
}
