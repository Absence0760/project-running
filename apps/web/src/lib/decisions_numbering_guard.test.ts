import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Guard-rail: every `## N.` entry in `docs/architecture/decisions.md` owns its
 * number outright, and every `§N` cross-reference inside the file points at an
 * entry that exists.
 *
 * The ADR log is append-only and several Claude sessions share one checkout, so
 * two sessions appending on the same day both read the same "next" number and
 * both take it. That happened three times — 104 (2026-05-31), 137 (2026-06-09)
 * and 178 (2026-06-20) each ended up claimed by two unrelated entries — and it
 * is not cosmetic: `§137` alone had 49 inbound references across the repo, split
 * between the env-file convention and server-side route generation, so a reader
 * following one could not tell which entry was meant. The collision was cleared
 * by renumbering the lower-referenced member of each pair to 574 / 575 / 576.
 *
 * Uniqueness is the load-bearing half and carries no exemptions. The dangling-
 * reference half is the companion risk a renumber creates: change a heading's
 * number and any `§N` naming it silently points at nothing. Its allowlist holds
 * only references that were already dangling before this guard existed, each
 * pinned so that fixing one forces its entry out — the list can shrink, never
 * grow.
 *
 * The third assertion closes the same failure from the outside: a `decisions.md#N-title`
 * link embeds the title as well as the number, so it breaks on a renumber AND on a
 * title edit that never touches a number. It is checked only in Markdown, where such a
 * string is genuinely a link — `contains('decisions.md#68')` inside a Dart guard test is
 * a prefix matcher, not a link, and would be a false positive.
 */

const repoRoot = resolve(import.meta.dirname, '..', '..', '..', '..');
const decisionsPath = resolve(repoRoot, 'docs/architecture/decisions.md');

/// References that named a non-existent entry before this guard was written.
/// Each is a pre-existing defect, not a licence to add more. Remove an entry the
/// moment its reference is corrected — the pinning assertion below fails if a
/// listed number stops dangling, so this map cannot silently rot.
const KNOWN_DANGLING_REFS = new Map<number, string>([
	[613, '"the §613 frozen-trace-on-reload behaviour" — no entry 613; likely an issue number'],
	[4704, '"§ 4704\'s `+` packing" — no entry 4704, and § 470 is unrelated to the glyph table']
]);

function decisionsDoc(): string {
	return readFileSync(decisionsPath, 'utf-8');
}

/// Entry numbers in document order, one per `## N.` heading.
function headingNumbers(doc: string): number[] {
	return [...doc.matchAll(/^## (\d+)\./gm)].map((m) => Number(m[1]));
}

test('every decisions.md entry number is claimed by exactly one entry', () => {
	const numbers = headingNumbers(decisionsDoc());
	assert.ok(numbers.length > 500, `expected the full ADR log, parsed only ${numbers.length}`);

	const seen = new Set<number>();
	const duplicated = new Set<number>();
	for (const n of numbers) {
		if (seen.has(n)) duplicated.add(n);
		seen.add(n);
	}

	assert.deepEqual(
		[...duplicated].sort((a, b) => a - b),
		[],
		`docs/architecture/decisions.md has entry numbers claimed by more than one "## N." heading: ` +
			`${[...duplicated].sort((a, b) => a - b).join(', ')}. Two sessions appended the same number. ` +
			`Renumber ONE member of each pair to a fresh number above the current maximum, leave it where ` +
			`it sits in the file, and update the inbound references that mean the entry you moved.`
	);
});

test('every §N reference inside decisions.md resolves to an entry', () => {
	const doc = decisionsDoc();
	const existing = new Set(headingNumbers(doc));
	const referenced = new Set([...doc.matchAll(/§\s?(\d+)/g)].map((m) => Number(m[1])));

	const dangling = [...referenced].filter((n) => !existing.has(n)).sort((a, b) => a - b);
	const unexpected = dangling.filter((n) => !KNOWN_DANGLING_REFS.has(n));

	assert.deepEqual(
		unexpected,
		[],
		`docs/architecture/decisions.md references entries that do not exist: ${unexpected.join(', ')}. ` +
			`Point the reference at the entry it means; do not add it to KNOWN_DANGLING_REFS.`
	);

	const repaired = [...KNOWN_DANGLING_REFS.keys()].filter((n) => !dangling.includes(n));
	assert.deepEqual(
		repaired,
		[],
		`KNOWN_DANGLING_REFS lists ${repaired.join(', ')}, which no longer dangle. Delete those entries — ` +
			`the allowlist may only shrink.`
	);
});

/// GitHub's heading slug: lowercase, drop everything but word chars, spaces and
/// hyphens, then map each space to its own hyphen. Runs of spaces are NOT
/// collapsed — "app + domain" loses the `+` and keeps both spaces, which is why
/// the real anchors carry double hyphens.
function slugFor(heading: string): string {
	return heading
		.toLowerCase()
		.replace(/[^\w\s-]/g, '')
		.trim()
		.replace(/ /g, '-');
}

test('every decisions.md anchor link in a Markdown file resolves to a heading', () => {
	const doc = decisionsDoc();
	const slugs = new Set(
		[...doc.matchAll(/^#{2,6} (.+)$/gm)].map((m) => slugFor(m[1]))
	);

	const files = execFileSync('git', ['ls-files', '*.md'], { cwd: repoRoot, encoding: 'utf-8' })
		.split('\n')
		.filter(Boolean);

	const broken: string[] = [];
	for (const file of files) {
		const text = readFileSync(resolve(repoRoot, file), 'utf-8');
		for (const m of text.matchAll(/decisions\.md#([\w-]+)/g)) {
			if (!slugs.has(m[1])) broken.push(`${file} -> #${m[1]}`);
		}
	}

	assert.deepEqual(
		broken,
		[],
		`Markdown links point at decisions.md anchors that no heading produces:\n  ${broken.join('\n  ')}\n` +
			`An anchor embeds the entry's TITLE as well as its number, so renumbering an entry or ` +
			`rewording its heading breaks every link naming it. Update the links.`
	);
});
