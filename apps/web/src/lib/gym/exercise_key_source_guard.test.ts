// Source-level guard: nothing in the web tree folds an exercise name with the
// runtime's own `toLowerCase()`.
//
// The exercise grouping key has one derivation — `normaliseExerciseName`,
// which collapses the named whitespace class and lower-cases through the
// FROZEN Unicode table (decisions § 1175). `trim().toLowerCase()` is neither:
// it splits an internal whitespace run, and it answers a different letter from
// the table at 1 code point on Node and 465 on Dart. Six surfaces derived the
// key that way anyway; two of them were lookups WRITTEN with one spelling and
// READ with another, so a lift logged twice in one workout lost its PR chips
// on every block but the first, with no failure anywhere (decisions § 1248).
//
// Nothing stopped a seventh being written, which is why this scan exists: the
// defect is invisible at runtime, so source is the only place it can be seen.
// The Dart half is `apps/mobile_android/test/exercise_key_source_guard_test.dart`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { stripComments } from '../core/strip_comments';

const SRC = resolve('src');

/// A file that names an exercise anywhere in its CODE is banned from the
/// runtime fold outright, rather than only where the receiver happens to name
/// the value it is folding.
///
/// This is the rule that gives the scan teeth, and it is anchored to what the
/// file DOES rather than to where it sits: the gym surfaces call their locals
/// `raw`, `q` and `s`, so a receiver test alone reads the picker's
/// `q.toLowerCase()` as unrelated to exercises and the fold walks straight
/// past. A hand-listed set of gym directories would have the same hole one
/// rename later. Prose does not count — `stripComments` runs first, so a doc
/// comment saying "exercise the enhance path" leaves the file unbanned.
const NAMES_AN_EXERCISE = /exercise/i;

/// Modules that serve every domain, so naming an exercise somewhere says
/// nothing about what any one fold in them is folding. The file-level ban is
/// waived here and each fold is judged on its own receiver instead — which is
/// what spares `slugify`'s `name.toLowerCase()` and the runner-handle
/// comparisons while still firing the moment one of them folds an
/// `exercise_name`.
const BROAD_MODULES = ['lib/core/data.ts'];

/// Files that still fold an exercise name, with why the fix is not in this
/// change. Each is a real instance of the same defect, in a tree this change
/// does not own. The staleness test below fails when one of these stops
/// matching, so an exemption cannot outlive the site it excuses.
const PENDING: { path: string; why: string }[] = [
	{
		path: 'lib/coach/context.ts',
		why: 'the per-workout exercise tally in the coach prompt context. followups.md, owner tree apps/web/src/lib/coach/.',
	},
	{
		path: 'lib/components/ExerciseCataloguePicker.svelte',
		why: 'the catalogue search + sort, the web half of a fold the mobile pickers now take canonically. followups.md, owner tree apps/web/src/lib/components/.',
	},
];

/// A runtime case fold, however it is spelled. Only the LOWER half is
/// bannable file-wide: upper-casing is a presentation transform, never a key
/// derivation. An upper-case fold applied to something the code calls an
/// exercise is still reported, on the receiver rule below — a key derived that
/// way would be just as wrong. The Dart half draws the same line, where nine
/// section labels depend on it.
const RUNTIME_FOLD = /\.to(?:Locale)?(?<case>Lower|Upper)Case\s*\(/g;

interface Hit {
	path: string;
	line: number;
	text: string;
}

/// The receiver expression a fold is applied to: the member chain immediately
/// left of the `.`, with balanced call and index groups walked over so
/// `(s.exercise_name ?? '').trim().toLowerCase()` reports the whole chain
/// rather than stopping at `.trim()`.
function receiverOf(code: string, at: number): string {
	let i = at - 1;
	while (i >= 0) {
		const c = code[i];
		if (/[\s]/.test(c) || /[A-Za-z0-9_$.?!]/.test(c)) {
			i--;
			continue;
		}
		if (c === ')' || c === ']') {
			const open = c === ')' ? '(' : '[';
			let depth = 0;
			while (i >= 0) {
				if (code[i] === c) depth++;
				else if (code[i] === open && --depth === 0) {
					i--;
					break;
				}
				i--;
			}
			continue;
		}
		break;
	}
	return code.slice(i + 1, at);
}

/// The statement a fold sits in — back to the nearest `;`, `,`, `{` or `}`. Catches
/// the shape the receiver alone cannot, where the value being folded was named
/// by the declaration rather than by the chain (`const exerciseKey = n.trim()
/// .toLowerCase()`). A value assigned to a neutral name in an EARLIER
/// statement and folded in this one is still out of reach; the blanket ban
/// inside the gym trees is what covers the surfaces where that matters.
function statementAt(code: string, at: number): string {
	let i = at - 1;
	while (i >= 0 && !';,{}'.includes(code[i])) i--;
	return code.slice(i + 1, at);
}

/// Every runtime case fold in [source] that this guard objects to, given where
/// the file lives. Takes the source rather than reading it so the mutation
/// test below can feed the same function a planted violation.
export function foldHits(path: string, source: string): Hit[] {
	// Matches are found in the string-blanked text so a documentation string
	// naming the banned shape is never read as an instance of it; the receiver
	// is read out of the comment-stripped text, where a quoted index like
	// `s['exercise_name']` still names what is being folded. Both transforms
	// preserve offsets.
	const code = stripComments(source);
	const scan = blankQuoted(code);
	const fileNamesAnExercise = NAMES_AN_EXERCISE.test(scan) && !BROAD_MODULES.includes(path);
	const out: Hit[] = [];
	for (const m of scan.matchAll(RUNTIME_FOLD)) {
		const at = m.index ?? 0;
		const named =
			NAMES_AN_EXERCISE.test(receiverOf(code, at)) || NAMES_AN_EXERCISE.test(statementAt(code, at));
		const lowering = m.groups?.case === 'Lower';
		if (!(lowering && fileNamesAnExercise) && !named) continue;
		const line = code.slice(0, at).split('\n').length;
		out.push({ path, line, text: source.split('\n')[line - 1]?.trim() ?? '' });
	}
	return out;
}

/// Bodies of single- and double-quoted strings blanked, offsets preserved.
/// `stripComments` emits string literals verbatim by design (a misread there
/// could delete code), so a documentation string naming the banned shape would
/// otherwise be reported as an instance of it. Template literals are left
/// alone: `${x.toLowerCase()}` inside one is a real fold.
function blankQuoted(code: string): string {
	let out = '';
	let i = 0;
	while (i < code.length) {
		const c = code[i];
		if (c !== "'" && c !== '"') {
			out += c;
			i++;
			continue;
		}
		out += c;
		i++;
		while (i < code.length && code[i] !== c && code[i] !== '\n') {
			const escaped = code[i] === '\\';
			out += escaped ? '  ' : ' ';
			i += escaped ? 2 : 1;
		}
		if (i < code.length && code[i] === c) {
			out += c;
			i++;
		}
	}
	return out;
}

function scannableFiles(dir: string): string[] {
	const out: string[] = [];
	for (const e of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, e.name);
		if (e.isDirectory()) out.push(...scannableFiles(full));
		else if (/\.(ts|svelte)$/.test(e.name) && !e.name.endsWith('.test.ts')) out.push(full);
	}
	return out;
}

function scanTree(): Hit[] {
	const out: Hit[] = [];
	for (const full of scannableFiles(SRC)) {
		const rel = relative(SRC, full).split(sep).join('/');
		out.push(...foldHits(rel, readFileSync(full, 'utf-8')));
	}
	return out;
}

test('the guard scans a tree that is actually there', () => {
	// § 510: a guard whose root has moved reports nothing at all, which reads
	// as a clean sweep. Anchor on a file the scan must always find.
	const files = scannableFiles(SRC).map((f) => relative(SRC, f).split(sep).join('/'));
	assert.ok(files.length > 500, `only ${files.length} scannable files under src/ — has the tree moved?`);
	assert.ok(files.includes('lib/gym/gym_prs.ts'), 'lib/gym/gym_prs.ts is not in the scan');
	assert.ok(files.includes('routes/gym/[id]/+page.svelte'), 'the gym detail page is not in the scan');
});

test('no web surface folds an exercise name with the runtime case mapping', () => {
	const pending = new Set(PENDING.map((p) => p.path));
	const offenders = scanTree().filter((h) => !pending.has(h.path));
	assert.deepEqual(
		offenders,
		[],
		'Fold an exercise name with normaliseExerciseName from $lib/gym/gym_prs, ' +
			'never the runtime case mapping — it splits an internal whitespace run ' +
			'and answers a different letter from the frozen table:\n' +
			offenders.map((h) => `  ${h.path}:${h.line}  ${h.text}`).join('\n'),
	);
});

test('every broad-module waiver is still load-bearing', () => {
	// A waiver that no longer waives anything is a line the next reader has to
	// re-derive. It stops being load-bearing the moment the module stops
	// naming an exercise at all, at which point the file-level ban was never
	// going to fire on it.
	for (const rel of BROAD_MODULES) {
		const scan = blankQuoted(stripComments(readFileSync(join(SRC, rel), 'utf-8')));
		assert.ok(
			NAMES_AN_EXERCISE.test(scan),
			`${rel} no longer names an exercise in code — delete its BROAD_MODULES entry.`,
		);
	}
});

test('every pending exemption still names a real fold', () => {
	for (const p of PENDING) {
		const hits = foldHits(p.path, readFileSync(join(SRC, p.path), 'utf-8'));
		assert.ok(
			hits.length > 0,
			`${p.path} no longer folds an exercise name — delete its PENDING entry ` +
				'so the next one cannot hide behind it.',
		);
	}
});

test('the scan sees the shapes it bans, and spares the ones it must not', () => {
	// Planted violations, each a shape the tree could plausibly grow. A scan is
	// the only instrument that can see this defect, so a shape it misses is a
	// shape that returns. The first two are the ones a directory-anchored or a
	// receiver-anchored rule alone would each walk past.
	const caught: [string, string, string][] = [
		[
			'the file names an exercise, the fold names a neutral local',
			'lib/components/Picker.svelte',
			'let entries = $state<Exercise[]>([]);\n\tconst q = query.trim().toLowerCase();',
		],
		[
			'the file names an exercise, the fold is a bare block name',
			'routes/anywhere/+page.svelte',
			'const names = exerciseNames;\n\tconst k = block.name.trim().toLowerCase();',
		],
		['the receiver names one, the file otherwise does not', 'lib/share/x.ts', 'const k = s.exercise_name.trim().toLowerCase();'],
		[
			'the receiver names one across a broken chain',
			'lib/social/y.ts',
			'const k = row.exercise_name\n\t\t.trim()\n\t\t.toLowerCase();',
		],
		['camelCase field', 'lib/social/z.ts', 'const k = set.exerciseName.toLowerCase();'],
		['locale variant', 'lib/social/w.ts', 'const k = s.exercise_name.toLocaleLowerCase();'],
		['upper-cased instead', 'lib/social/v.ts', 'const k = s.exercise_name.toUpperCase();'],
		[
			'nullish default in parens',
			'lib/social/u.ts',
			"const k = (s.exercise_name ?? '').trim().toLowerCase();",
		],
		['quoted index', 'lib/social/t.ts', "const k = s['exercise_name'].toLowerCase();"],
		[
			'named by the declaration rather than the chain',
			'lib/social/s.ts',
			'const exerciseKey = n.trim().toLowerCase();',
		],
	];
	for (const [label, path, source] of caught) {
		assert.equal(foldHits(path, source).length, 1, `missed: ${label}`);
	}

	const spared: [string, string, string][] = [
		['a comment describing the ban', 'lib/social/a.ts', '// never exercise_name.trim().toLowerCase()'],
		['a string mentioning it', 'lib/social/b.ts', "const doc = 'exercise_name.toLowerCase()';"],
		[
			'a file that only mentions an exercise in prose',
			'lib/routes/route_detail.ts',
			'/// a stub to exercise the enhance path\nconst q = query.trim().toLowerCase();',
		],
		['nothing names an exercise at all', 'lib/social/c.ts', 'const q = query.trim().toLowerCase();'],
		[
			'a section label upper-cased for presentation',
			'routes/gym/records/+page.svelte',
			'const names = exerciseNames;\n\tconst head = label.toUpperCase();',
		],
		[
			'a broad module folding something that is not an exercise',
			'lib/core/data.ts',
			'const cols = exercise_name;\n\tconst slug = name.toLowerCase();',
		],
	];
	for (const [label, path, source] of spared) {
		assert.deepEqual(foldHits(path, source), [], `false positive: ${label}`);
	}

	// The waiver is a waiver, not a blanket: a real fold inside a broad module
	// is still reported on its receiver.
	assert.equal(
		foldHits('lib/core/data.ts', 'const k = s.exercise_name.toLowerCase();').length,
		1,
		'a broad module must still be judged fold by fold',
	);
});
