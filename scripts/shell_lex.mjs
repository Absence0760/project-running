// Split a shell command line into the commands a shell would actually run, and
// each command into its words.
//
// Two guards were reading shell with `String.split` and a regex, and both
// misread it (decisions § 773). `check_root_scripts.mjs` split on whitespace,
// so `pnpm -C apps/web --silent run check` named `--silent` as the script to
// look for and `cd apps/backend; supabase db reset` looked for a directory
// called `apps/backend;` — three false accusations from one manifest, while
// the genuinely missing directory after the `;` went unreported because the
// pattern only anchored on `&&`. `check_lambda_alias_sync.mjs` read the alias
// name out of a 400-character window that crossed command boundaries, so a
// `--name` belonging to some other command answered for the alias call.
//
// What is tracked: `'…'` (no escapes inside, as POSIX has none), `"…"` with
// backslash escapes, bare backslash escapes, `\`-newline continuation, `#`
// comments (only where a word may begin — `foo#bar` is one word), and the
// operators `;` `&` `&&` `|` `||` `(` `)` `` ` `` and newline. `$(` opens a
// nested command because that is what it is: `X=$(aws lambda get-alias --name
// live)` carries a real `aws` invocation that a scan for a command beginning
// `aws` must see.
//
// A BACKTICK is the same substitution written the older way, and it was not an
// operator here — so an unquoted `` `aws ssm get-parameter --name live` `` sat
// inside the WORD LIST of the command containing it, and § 773's decoy
// (`aws lambda update-alias --function-name `…--name live` --name stable`)
// answered `live` for an alias call whose real `--name` was `stable`. The `$(`
// spelling of that same decoy had already been closed; the backtick spelling
// re-opened it, latent only because nothing in the tree writes one outside a
// comment. Both delimiters end the word and open a command, so both fail in
// the same direction.
//
// No expansion of any kind: `$NAME` stays `$NAME`. A guard comparing text
// against a declaration wants the text that was written, and a lexer that
// guessed at a variable's value would be inventing evidence.
//
// An unterminated quote THROWS rather than consuming to end of input, for the
// reason sql_lex.mjs throws: a shell fragment the lexer cannot read is one a
// guard must not report a verdict about.
//
// Unit tests: `node --test scripts/shell_lex.test.mjs`

/** @typedef {{ line: number, words: string[] }} ShellCommand */

/// The two-character operators, longest first so `&&` is not read as `&` `&`.
/// The backtick appears once because it is its own opener and closer.
const OPERATORS = ['&&', '||', ';;', ';', '&', '|', '(', ')', '`'];

/**
 * @param {string} src
 * @returns {ShellCommand[]} one entry per command, in source order. Commands
 *   with no words (an empty line, a comment, a stray operator) are dropped.
 */
export function splitShellCommands(src) {
	/** @type {ShellCommand[]} */
	const commands = [];
	/** @type {string[]} */
	let words = [];
	let word = '';
	let hasWord = false;
	let line = 1;
	let commandLine = 1;

	const endWord = () => {
		if (!hasWord) return;
		words.push(word);
		word = '';
		hasWord = false;
	};
	const endCommand = () => {
		endWord();
		if (words.length > 0) commands.push({ line: commandLine, words });
		words = [];
		commandLine = line;
	};

	for (let i = 0; i < src.length; i++) {
		const c = src[i];

		if (c === '\n') {
			endCommand();
			line++;
			commandLine = line;
			continue;
		}

		if (c === '\\') {
			const next = src[i + 1];
			if (next === '\n') {
				i++;
				line++;
				continue;
			}
			if (next === undefined) throw new Error('shell_lex: trailing backslash');
			word += next;
			hasWord = true;
			i++;
			continue;
		}

		if (c === "'") {
			const close = src.indexOf("'", i + 1);
			if (close === -1) throw new Error(`shell_lex: unterminated ' at line ${line}`);
			word += src.slice(i + 1, close);
			hasWord = true;
			for (let k = i; k < close; k++) if (src[k] === '\n') line++;
			i = close;
			continue;
		}

		if (c === '"') {
			let k = i + 1;
			for (; k < src.length; k++) {
				if (src[k] === '\\' && k + 1 < src.length) {
					if (src[k + 1] === '\n') line++;
					else word += src[k + 1];
					k++;
					continue;
				}
				if (src[k] === '"') break;
				if (src[k] === '\n') line++;
				word += src[k];
			}
			if (k >= src.length) throw new Error(`shell_lex: unterminated " at line ${line}`);
			hasWord = true;
			i = k;
			continue;
		}

		if (c === '#' && !hasWord) {
			const nl = src.indexOf('\n', i);
			i = nl === -1 ? src.length : nl - 1;
			continue;
		}

		if (c === ' ' || c === '\t' || c === '\r') {
			endWord();
			continue;
		}

		// `$(` is command substitution: the `$` closes the word it was building
		// (`X=$` here) and the `(` opens a command of its own.
		const two = src.slice(i, i + 2);
		const op = OPERATORS.find((o) => two.startsWith(o) || (o.length === 2 && two === o));
		if (op !== undefined && two.startsWith(op)) {
			endCommand();
			i += op.length - 1;
			continue;
		}

		word += c;
		hasWord = true;
	}
	endCommand();
	return commands;
}
