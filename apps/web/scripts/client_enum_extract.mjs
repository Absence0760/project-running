// Extract the value set of a *declared* client enumeration — a TypeScript
// union / array / keyed object list / record, or a Dart enum / const list /
// keyed object list / map — so the CHECK-constraint guard can compare it
// against the constraint the database actually enforces.
//
// Why a declaration rather than a grep: a file that merely MENTIONS every
// value of a CHECK set proves nothing (`format/time.ts` mentions 'day' and
// 'short', which is the whole of `app_quota.window_kind`). The unit of
// comparison has to be a named declaration whose members ARE the set, or
// the guard reports coincidences.
//
// Shapes, because the tree really does carry all of them:
//   union  — `export type RunSource = 'app' | 'watch';`
//   list   — `const MEAL_SLOTS = ['breakfast', 'lunch'];`
//   keyed  — `const ROUTE_MARKER_KINDS = [{ kind: 'aid_station', ... }, ...]`
//   keys   — `const order: Record<string, number> = { '1_mile': 0, ... }`
//   enum   — `enum ProgressionScheme { none, doubleProgression }` (Dart)
//
// The Dart `enum` shape is the one that needs a convention: the members are
// identifiers, and every boundary in the tree converts them to the wire
// token by camelCase→snake_case (`doubleProgression` ↔ `double_progression`,
// `fiveByFive` ↔ `five_by_five`). That conversion is applied here so the
// enum can be compared with the CHECK directly.

/** @param {string} s */
const snakeCase = (s) => s.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();

/**
 * Slice the balanced `open`/`close` block that starts at or after `from`.
 * A regex cannot do this: a keyed object list nests braces inside brackets,
 * and `[^\]]*` stops at the first `]` of a nested array.
 *
 * @param {string} src
 * @param {number} from
 * @param {string} open
 * @param {string} close
 * @returns {string | null}
 */
function balancedBlock(src, from, open, close) {
	const start = src.indexOf(open, from);
	if (start === -1) return null;
	let depth = 0;
	for (let i = start; i < src.length; i++) {
		const c = src[i];
		if (c === "'" || c === '"') {
			const quote = c;
			i++;
			while (i < src.length && src[i] !== quote) {
				if (src[i] === '\\') i++;
				i++;
			}
			continue;
		}
		if (c === open) depth++;
		else if (c === close) {
			depth--;
			if (depth === 0) return src.slice(start + 1, i);
		}
	}
	return null;
}

/** @param {string} block @returns {string[]} */
const stringLiterals = (block) => [...block.matchAll(/'([^']*)'/g)].map((m) => m[1]);

/**
 * Find where a named declaration begins. Accepts the `export`/`const`/`final`
 * /`static const`/`type`/`enum` prefixes both languages spell it with, and
 * anchors on the NAME so a same-named substring elsewhere cannot match.
 *
 * @param {string} src
 * @param {string} name
 * @returns {number}
 */
function declIndex(src, name) {
	// The trailing `=` / `{` is what separates DECLARING a thing called X from
	// declaring a field whose TYPE is X — `final SessionItemKind kind;` matched
	// the latter and made four of these look like redeclarations.
	const re = new RegExp(
		`(?:^|[\\s;}])(?:export\\s+)?(?:static\\s+)?(?:const|final|type|enum|let|var)\\s+` +
			`(?:List<[^>]*>\\s+|Map<[^>]*>\\s+)?${name}\\s*(?::[^=;{]*)?\\s*(?:=|\\{)`,
		'gm',
	);
	const hits = [...src.matchAll(re)];
	// Two declarations of one name in a file are usually two locals in two
	// functions, and taking the first would certify the wrong one — quietly,
	// which is the failure this whole guard exists to prevent. Say so instead.
	if (hits.length > 1) throw new Error(`"${name}" is declared ${hits.length} times in this file`);
	return hits.length === 0 ? -1 : (hits[0].index ?? -1);
}

/**
 * Where the initialiser begins — past the type annotation, which carries
 * brackets of its own. `const ROUTE_MARKER_KINDS: RouteMarkerKindSpec[] = [...]`
 * has an EMPTY `[]` before the real one, and reading that first yielded an
 * empty set for six of these declarations at once.
 *
 * @param {string} src
 * @param {number} at
 * @returns {number}
 */
function initialiserAt(src, at) {
	const eq = src.indexOf('=', at);
	return eq === -1 ? at : eq;
}

/**
 * @param {string} src   file contents
 * @param {{ shape: 'union'|'list'|'keyed'|'keys'|'enum', name: string, field?: string }} decl
 * @returns {Set<string> | null} null when the declaration is absent or empty
 */
export function extractClientEnum(src, decl) {
	const at = declIndex(src, decl.name);
	if (at === -1) return null;

	/** @type {string[]} */
	let values;
	if (decl.shape === 'union') {
		const end = src.indexOf(';', at);
		if (end === -1) return null;
		values = stringLiterals(src.slice(at, end));
	} else if (decl.shape === 'enum') {
		const body = balancedBlock(src, at, '{', '}');
		if (body === null) return null;
		values = body
			.split(';')[0]
			.split(',')
			.map((x) => x.trim())
			.filter((x) => /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(x))
			.map(snakeCase);
	} else if (decl.shape === 'keys') {
		const body = balancedBlock(src, initialiserAt(src, at), '{', '}');
		if (body === null) return null;
		// A record key is either quoted or a bare identifier; both are followed
		// by the colon that makes them a key rather than a value.
		values = [...body.matchAll(/(?:'([^']*)'|([A-Za-z_][A-Za-z0-9_]*))\s*:/g)].map(
			(m) => m[1] ?? m[2],
		);
	} else {
		const body = balancedBlock(src, initialiserAt(src, at), '[', ']');
		if (body === null) return null;
		values =
			decl.shape === 'keyed'
				? [...body.matchAll(new RegExp(`\\b${decl.field}\\s*:\\s*'([^']*)'`, 'g'))].map(
						(m) => m[1],
					)
				: stringLiterals(body);
	}

	const out = new Set(values);
	return out.size === 0 ? null : out;
}
