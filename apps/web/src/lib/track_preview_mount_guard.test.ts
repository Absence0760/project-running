// `TrackPreview` takes a points array and draws it. It has no visibility gate
// and no clip, so mounting it with a row's own `waypoints` on a surface whose
// viewer is not the owner is the pre-audit shape that leaked bookmarked, club
// and public routes (decisions.md § 33), and it is the shape § 772's filing
// would have rebuilt if it had been implemented literally.
//
// `security_guards.test.ts` pins four SURFACES off it by name — the routes
// list, the clubs Routes tab, `/routes/[id]` and the DM thread. Four named
// surfaces is a list, and § 738's standing lesson is that a list rots: the
// fifth non-owner surface to want a route thumbnail is invisible to all four
// assertions. This derives the rule instead — only the clip-aware wrappers
// may mount the renderer — and holds each of them to still clipping, so an
// entry cannot stay permitted after it stops earning it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..');

/**
 * The components allowed to hand points to `TrackPreview`, each with the
 * viewer-aware read that earns it. The companion assertion below fails when a
 * file here stops performing that read, so this is a derivation with a stated
 * reason rather than a set of exemptions to remember.
 */
const CLIPPING_WRAPPERS: Record<string, RegExp> = {
	'lib/components/RunTrackPreview.svelte':
		/import \{[^}]*\bfetchClippedTrackForRun\b[^}]*\} from '\$lib\/core\/data'/,
	'lib/components/RouteTrackPreview.svelte':
		/import \{[^}]*\bfetchClippedRouteForViewer\b[^}]*\} from '\$lib\/core\/data'/,
	'lib/components/DmRouteAttachment.svelte':
		/import \{[^}]*\bfetchRouteById\b[^}]*\} from '\$lib\/core\/data'/,
};

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) svelteFiles(full, out);
		else if (entry.endsWith('.svelte')) out.push(full);
	}
	return out;
}

function rel(file: string): string {
	return relative(SRC, file).split('\\').join('/');
}

/// The half-open `[start, end)` spans a comment covers.
///
/// An unterminated opener runs to the end of the input, which is what a browser
/// does with it and what makes the set complete: the alternative -- deleting
/// each `<!-- ... -->` from the text -- both leaves a bare `<!--` behind and
/// can JOIN what sits either side of a removed comment into a new complete one
/// (`<!-` + `<!-- x -->` + `- ... -->` becomes `<!-- ... -->`), which this
/// guard would then read as live markup.
function commentSpans(source: string): [number, number][] {
	const spans: [number, number][] = [];
	for (const pattern of [
		/<!--[\s\S]*?(?:-->|$)/g,
		/\/\*[\s\S]*?(?:\*\/|$)/g,
		/(?<!:)\/\/[^\n]*/g,
	]) {
		for (const m of source.matchAll(pattern)) {
			spans.push([m.index, m.index + m[0].length]);
		}
	}
	return spans;
}

/** Source with comments blanked, so prose quoting the tag never trips the scan. */
export function withoutComments(source: string): string {
	// Blanked in place rather than deleted: every offset is preserved, so no
	// removal can splice two fragments into something that reads as markup.
	const chars = [...source];
	for (const [start, end] of commentSpans(source)) {
		for (let i = start; i < end && i < chars.length; i += 1) {
			if (chars[i] !== '\n') chars[i] = ' ';
		}
	}
	return chars.join('');
}

function mountsTrackPreview(file: string): boolean {
	return /<TrackPreview\b/.test(withoutComments(readFileSync(file, 'utf-8')));
}

test('the scan reaches the tree and still sees a real mount', () => {
	// A derived rule is only as good as its scan, and both halves of this
	// one fail SILENTLY: a walk that reaches nothing and a `mountsTrack
	// Preview` that stops matching each report an empty offender list,
	// which is what a clean tree reports too (§ 762). Positive controls,
	// off the real files rather than off a fixture, so the check cannot
	// drift away from what it is checking.
	const files = svelteFiles(SRC);
	assert.ok(files.length > 100, `the walk reached only ${files.length} .svelte files`);
	for (const path of Object.keys(CLIPPING_WRAPPERS)) {
		assert.ok(
			mountsTrackPreview(join(SRC, path)),
			`${path} is permitted because it mounts TrackPreview, and the scan can no ` +
				'longer see that it does — every offender it reports is now a false negative',
		);
	}
	assert.ok(
		!mountsTrackPreview(join(SRC, 'lib/components/Avatar.svelte')),
		'the scan matches a file that mounts nothing — it is reporting on the wrong thing',
	);
});

test('only a clip-aware wrapper mounts the unclipped renderer', () => {
	const offenders: string[] = [];
	for (const file of svelteFiles(SRC)) {
		const path = rel(file);
		if (path === 'lib/components/TrackPreview.svelte') continue;
		if (path in CLIPPING_WRAPPERS) continue;
		if (mountsTrackPreview(file)) offenders.push(path);
	}
	assert.deepEqual(
		offenders,
		[],
		'TrackPreview draws whatever points it is given — it has no visibility gate and ' +
			'no privacy-zone clip. A surface whose viewer may not be the owner must go ' +
			'through RunTrackPreview / RouteTrackPreview / DmRouteAttachment, which resolve ' +
			'through a viewer-aware read first (decisions.md § 33, § 772):\n  ' +
			offenders.join('\n  '),
	);
});

test('every permitted wrapper still performs the read that permits it', () => {
	for (const [path, read] of Object.entries(CLIPPING_WRAPPERS)) {
		const file = join(SRC, path);
		// Read rather than stat-then-read: the permitted set is a claim about the
		// file's CONTENT, so the read is the check and there is no window between.
		let raw: string;
		try {
			raw = readFileSync(file, 'utf-8');
		} catch {
			throw new Error(`${path} is permitted but no longer readable`);
		}
		const source = withoutComments(raw);
		assert.match(
			source,
			read,
			`${path} may mount TrackPreview only because it imports its points read from ` +
				'the data layer by that name. It no longer does — an alias or a local ' +
				're-declaration would satisfy a bare name check while resolving somewhere ' +
				'else — so either restore the import or take it out of CLIPPING_WRAPPERS.',
		);
		assert.ok(
			mountsTrackPreview(file),
			`${path} no longer mounts TrackPreview — drop it from CLIPPING_WRAPPERS so ` +
				'the entry cannot outlive what it covers.',
		);
	}
});

test('no wrapper reaches the bare routes table for the line it renders', () => {
	// § 772: the bare `routes` row carries the UNCLIPPED waypoints column, and
	// a DM recipient is a non-owner by construction. The named read is the
	// whole mechanism; a `.from('routes')` beside it would bypass it.
	for (const path of Object.keys(CLIPPING_WRAPPERS)) {
		const source = withoutComments(readFileSync(join(SRC, path), 'utf-8'));
		assert.doesNotMatch(
			source,
			/\.from\(\s*['"]routes['"]\s*\)/,
			`${path} reads the bare routes table, which returns the unclipped waypoints column`,
		);
	}
});

test('the scan sees a bare mount and is not fooled by prose', () => {
	assert.ok(/<TrackPreview\b/.test(withoutComments('<TrackPreview points={r.waypoints} />')));
	assert.ok(/<TrackPreview\b/.test(withoutComments('\t\t\t<TrackPreview\n\t\t\t\t{points}\n\t\t\t/>')));
	assert.ok(!/<TrackPreview\b/.test(withoutComments('<!-- <TrackPreview points={x} /> -->')));
	assert.ok(!/<TrackPreview\b/.test(withoutComments('// bare <TrackPreview points={x} /> leaks')));
	assert.ok(!/<TrackPreview\b/.test(withoutComments('/* <TrackPreview /> */')));
	// A differently-named component must not be read as this one.
	assert.ok(!/<TrackPreview\b/.test(withoutComments('<TrackPreviewCard {points} />')));
});

test('no comment shape leaves a mount readable, and live markup survives', () => {
	// Blanking preserves offsets, so a removed comment can no longer splice what
	// sits either side of it into a new opener. What survives here is a mount
	// the guard REPORTS -- which is also what a browser does with it, since the
	// leading `<!-` opens a bogus comment that ends at the first `>`. Erring
	// toward reporting is the only safe direction for a guard: a commented-out
	// mount wrongly named costs an author one edit, where a real mount silently
	// swallowed is the defect this file exists to prevent.
	const joined = '<!-' + '<!-- x -->' + '- <TrackPreview /> -->';
	assert.match(withoutComments(joined), /<TrackPreview/);
	assert.ok(!withoutComments(joined).includes('<!--'));
	assert.equal(withoutComments('<!-- <TrackPreview /> -->').trim(), '');
	// An unterminated opener comments out the rest of the file, as it does in a
	// browser -- so nothing after it is a mount, and no `<!--` survives.
	assert.equal(withoutComments('<!-- <TrackPreview />').trim(), '');
	assert.equal(withoutComments('/* <TrackPreview />').trim(), '');
	assert.ok(!withoutComments('<!--<!-- x').includes('<!--'));
	// Offsets are preserved, so line numbers still line up with the source.
	assert.equal(withoutComments('<!-- x -->\nlive').split('\n')[1], 'live');
	assert.match(withoutComments('<TrackPreview />'), /TrackPreview/);
});
