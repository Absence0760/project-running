// Guard-rail: a share URL's PATH is defined once, in a builder.
//
// §520 settled which ORIGIN each use wants and found it was never the defect:
// a `<head>` canonical must resolve against `PUBLIC_SITE_URL` (the public home
// of the content is not whichever host the reader happens to be on), while a
// copy-to-clipboard link must resolve against `location.origin` (a preview
// host has to yield a preview link). Both are correct, which is exactly why
// the builders take the base as a parameter — one path definition, right
// origin per use.
//
// What was wrong is that three copy-links spelled the path by hand
// (`${window.location.origin}/share/run/${run.id}`) while the canonical two
// hundred lines up in the same file went through `buildRunShareCanonical`, and
// the sitemap spelled five more. A sitemap advertising a path the canonical
// does not agree with is worse than either alone: the crawler is handed URLs
// that point somewhere else.
//
// So the property pinned here is structural, not textual: every place that
// interpolates a base into a `/share/<entity>/` or `/recap/share/` path must
// appear in REGISTER with an exact count. A fourth hand-spelled copy-link, a
// new surface that assembles its own share URL, or a second spelling inside a
// builder module all fail — and a builder that stops being used fails too,
// because the count drops. Same shape as §526's literal register, and for the
// same reason: an allowlist of what is *banned* cannot see the next case.
//
// Invocation:
//   npx tsx --test src/lib/share/share_url_source_guard.test.ts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

const __dirname = resolve(new URL('.', import.meta.url).pathname);
const webRoot = resolve(__dirname, '../../..');
const srcRoot = resolve(webRoot, 'src');
const lambdaRoot = resolve(webRoot, 'lambda');

/// A base interpolated straight into a share path: `${b}/share/route/${r.id}`,
/// `${location.origin}/recap/share/${id}`,
/// `${normaliseSiteUrl(base)}/share/badge/${id}`. Requires the entity segment
/// and its trailing slash so prose like "`${base}/share/...`" in a doc comment
/// is not a match on its own — comment lines are stripped below regardless.
const SHARE_PATH = /\$\{[^}]*\}\/(?:recap\/share\/|share\/[a-z]+\/)/g;

/// Every allowed site, `path relative to apps/web` -> `[count, why]`. The
/// canonical builders are the definitions; everything else here is a debt.
const REGISTER: Record<string, [number, string]> = {
	'src/lib/share/share_meta.ts': [2, 'defines the run + route share paths'],
	'src/lib/share/share_badge_meta.ts': [1, 'defines the badge share path'],
	'src/lib/share/share_club_meta.ts': [1, 'defines the club share path'],
	'src/lib/share/share_event_meta.ts': [1, 'defines the event share path'],
	'src/lib/share/share_profile_meta.ts': [1, 'defines the profile share path'],
	'src/lib/share/share_race_meta.ts': [1, 'defines the race share path'],
	'src/lib/share/share_recap_meta.ts': [1, 'defines the recap share path'],
	'src/lib/share/share_session_meta.ts': [1, 'defines the session share path'],
	'src/lib/share/share_workout_meta.ts': [1, 'defines the workout share path'],
	// Open debt, not an exemption: both recap pages hand-spell the path that
	// `buildRecapShareCanonical` now defines, and the fix is to call it with
	// `location.origin`. Left standing because round 14's file partition put
	// these two pages in another agent's tree; landing an edit to them from
	// here is what §515 recorded as costing a round.
	'src/routes/recap/[year]/+page.svelte': [1, 'DEBT: use buildRecapShareCanonical'],
	'src/routes/recap/[year]/[month]/+page.svelte': [1, 'DEBT: use buildRecapShareCanonical'],
};

/// Strip `//`-style comments so a path written in prose inside a doc comment
/// is not counted as a construction site. Block comments are not used for doc
/// comments anywhere in this tree.
function stripComments(source: string): string {
	return source
		.split('\n')
		.map((line) => (/^\s*\/\//.test(line) ? '' : line))
		.join('\n');
}

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name === 'dist') continue;
			sourceFiles(full, out);
			continue;
		}
		if (!/\.(ts|svelte|mjs|js)$/.test(entry.name)) continue;
		if (entry.name.endsWith('.test.ts')) continue;
		out.push(full);
	}
	return out;
}

function scan(): Map<string, number> {
	const found = new Map<string, number>();
	for (const file of [...sourceFiles(srcRoot), ...sourceFiles(lambdaRoot)]) {
		const hits = stripComments(readFileSync(file, 'utf-8')).match(SHARE_PATH);
		if (!hits) continue;
		found.set(relative(webRoot, file).split('\\').join('/'), hits.length);
	}
	return found;
}

test('every hand-assembled share path is registered with its count', () => {
	const found = scan();
	const unregistered: string[] = [];
	const drifted: string[] = [];
	for (const [file, count] of found) {
		const entry = REGISTER[file];
		if (!entry) {
			unregistered.push(`${file} (${count})`);
			continue;
		}
		if (entry[0] !== count) drifted.push(`${file}: registered ${entry[0]}, found ${count}`);
	}
	assert.deepEqual(
		unregistered,
		[],
		'these files assemble a share URL by hand instead of calling the entity\'s ' +
			`build<X>ShareCanonical: ${unregistered.join(', ')}. Call the builder with the ` +
			'origin the use wants — PUBLIC_SITE_URL for a <head>, location.origin for a ' +
			'copy-link — so the path stays defined in one place (§ 520).',
	);
	assert.deepEqual(
		drifted,
		[],
		`share-path count drift: ${drifted.join('; ')}. A count that went UP is a second ` +
			'spelling of a path that already has a builder; one that went DOWN means a ' +
			'builder lost its last caller — update REGISTER either way.',
	);
});

test('a registered file that stops assembling the path fails the register', () => {
	const found = scan();
	const stale = Object.keys(REGISTER).filter((f) => !found.has(f));
	assert.deepEqual(
		stale,
		[],
		`REGISTER names files that no longer assemble a share path: ${stale.join(', ')}. ` +
			'Delete the entry — a register that keeps entries for resolved debts stops ' +
			'being a statement about the tree.',
	);
});

/// The three copy-links §520 left hand-spelled, pinned by their surface so a
/// revert is a failure rather than a silent regression to the old shape.
const COPY_LINK_SITES: Array<[string, RegExp]> = [
	['src/routes/runs/[id]/+page.svelte', /buildRunShareCanonical\(\s*window\.location\.origin/],
	['src/routes/routes/[id]/+page.svelte', /buildRouteShareCanonical\(\s*window\.location\.origin/],
	['src/routes/u/[id]/+page.svelte', /buildBadgeShareCanonical\(\s*location\.origin/],
	['src/routes/sessions/[id]/+page.svelte', /buildSessionShareCanonical\(\s*location\.origin/],
	['src/routes/gym/[id]/+page.svelte', /buildWorkoutShareCanonical\(\s*location\.origin/],
];

test('a copy-link resolves the builder against the live origin, not the site URL', () => {
	for (const [file, pattern] of COPY_LINK_SITES) {
		const source = readFileSync(resolve(webRoot, file), 'utf-8');
		assert.match(
			source,
			pattern,
			`${file} must build its copy-to-clipboard share link by calling the share ` +
				'canonical builder with location.origin. PUBLIC_SITE_URL would hand a ' +
				'preview-host user a production link to content that may not be there.',
		);
	}
});
