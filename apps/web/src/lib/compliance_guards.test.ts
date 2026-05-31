import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Guards for the compliance docs that audit/gdpr + audit/third-party-data-flows
 * (2026-05-30) graded Critical: the published sub-processor disclosure had
 * `TODO` placeholders where a region / DPA must appear. A `TODO` in the Privacy
 * Policy's sub-processor table is an Art 13(1)(e/f) transparency failure and a
 * store-review reject trigger, so these pin the resolved values in place. The
 * regions are sourced from config (apps/backend/deployment.md + the fly.toml
 * primary_region) — if the deployment region changes, update both the config
 * and the row, and these guards confirm they stay in lockstep.
 */

const repoRoot = resolve(import.meta.dirname, '..', '..', '..', '..');
const subProcessors = readFileSync(
	resolve(repoRoot, 'docs', 'compliance', 'sub-processors.md'),
	'utf-8',
);

/** The single markdown table row whose first cell contains `label`. */
function rowFor(label: string): string {
	const line = subProcessors
		.split('\n')
		.find((l) => l.trimStart().startsWith('|') && l.includes(label));
	assert.ok(line, `sub-processors.md must have a table row for ${label}`);
	return line!;
}

test('Supabase sub-processor row declares a concrete region (not TODO)', () => {
	const row = rowFor('**Supabase**');
	assert.ok(
		!/TODO/i.test(row),
		`Supabase row must not carry a TODO region — Art 13(1)(f). Got: ${row}`,
	);
	assert.ok(
		row.includes('eu-west-2'),
		`Supabase row must name the deployment region (eu-west-2, per apps/backend/deployment.md). Got: ${row}`,
	);
});

test('Fly.io sub-processor row declares a concrete region (not TODO)', () => {
	const row = rowFor('**Fly.io**');
	assert.ok(
		!/TODO/i.test(row),
		`Fly.io row must not carry a TODO region — run tracks transit it. Got: ${row}`,
	);
	assert.ok(
		row.includes('lhr'),
		`Fly.io row must name the primary_region (lhr, per apps/job_worker/fly.toml). Got: ${row}`,
	);
});

test('transactional-email sub-processor is resolved, not a TODO provider', () => {
	const row = rowFor('transactional email');
	assert.ok(
		!/TODO/i.test(row),
		`The auth transactional-email row must be resolved (no TODO provider/region/DPA). ` +
			`config.toml declares no custom SMTP, so it defaults to Supabase's managed ` +
			`sender under the Supabase DPA — keep that documented. Got: ${row}`,
	);
});

test('the sub-processor table carries no unresolved region placeholder', () => {
	// Belt-and-braces against the Critical: ANY TODO that gates a region
	// value, however worded ("which region", "which API region", …). The
	// pattern is deliberately loose around the middle so a word insertion
	// can't slip a live placeholder past the guard. The Sentry row's
	// "US (default) — verify project region" is intentionally NOT matched
	// (it states a region + a verify action, no TODO keyword).
	const offenders = subProcessors
		.split('\n')
		.filter((l) => /TODO/i.test(l) && /region/i.test(l));
	assert.deepEqual(
		offenders,
		[],
		`sub-processors.md still has TODO placeholder(s) gating a region:\n  ${offenders.join('\n  ')}`,
	);
});

// Legal-page launch invariant (audit-findings 2026-05-30 High, gdpr):
// these pages carry TODO placeholders (controller identity, Art 27 reps,
// governing law) that only counsel + the registered legal entity can
// fill. The draft/operative switch is the literal `<div class="draft-
// banner">` element — while it's present the TODOs are an honest draft;
// once it's removed the page is live and must contain none.
const legalPages = [
	{ name: 'Privacy Policy', file: ['apps', 'web', 'src', 'routes', 'privacy', '+page.svelte'] },
	{ name: 'Terms of Service', file: ['apps', 'web', 'src', 'routes', 'terms', '+page.svelte'] },
	{ name: 'Cookie Notice', file: ['apps', 'web', 'src', 'routes', 'cookie-notice', '+page.svelte'] },
];
for (const { name, file } of legalPages) {
	test(`${name}: an operative (non-draft) page has no TODO placeholders`, () => {
		const src = readFileSync(resolve(repoRoot, ...file), 'utf-8');
		// The banner DIV (not the `.draft-banner` CSS rule) is the
		// operative/draft switch; removing it publishes the page.
		const isDraft = src.includes('<div class="draft-banner">');
		if (isDraft) return; // honest placeholder state — allowed
		assert.ok(
			!/TODO/i.test(src),
			`${name} has the draft banner removed (operative) but still contains TODO ` +
				`placeholders — fill the controller identity / governing law / Art 27 ` +
				`representative(s) before publishing, or restore the draft banner.`,
		);
	});
}
