// The production Lambdas resolve `PUBLIC_SITE_URL` through `siteOrigin`, and
// what happens when they do not.
//
// Every crawler-facing surface on this site — `/share/{run,route,badge,event,
// profile,club,race,session,workout}`, `/recap/share/*` and the five `/og/*`
// PNGs — is rendered in production by a Lambda, never by SvelteKit
// (adapter-static drops the `+server`/`+page.ts` halves, decisions § 53). The
// twenty in-app callers under `src/routes/` fold the env with
// `env.PUBLIC_SITE_URL || DEFAULT_SITE_URL`; all five Lambdas folded it with
// `?? DEFAULT_SITE_URL`. Those are not the same fold. `??` fires only on
// null/undefined, so a `PUBLIC_SITE_URL=""` in a function's environment — a
// deploy that failed to configure it, an `extra_lambda_env` that set the key
// empty, a self-hosted stack — survives as the empty string and reaches the
// head builders as the origin.
//
// `siteOrigin` exists for exactly this fold and says so in its own doc comment
// ("an env var set to the empty string is a deploy that failed to configure
// it, not a request to serve canonicals from nowhere"). It was unit-tested and
// had no callers at all. See decisions § 895.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { DEFAULT_SITE_URL, siteOrigin } from '../core/site_url.js';
import { buildShareRunMeta, renderShareRunHeadTags } from './share_run_meta.js';
import { buildShareEventHead, renderShareEventHeadTags } from './share_event_meta.js';

const lambdaRoot = resolve(import.meta.dirname, '..', '..', '..', 'lambda');

function sourceFiles(dir: string): string[] {
	let out: string[] = [];
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === 'dist') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) out = out.concat(sourceFiles(full));
		else if (/\.(ts|mjs)$/.test(entry)) out.push(full);
	}
	return out;
}

/** Comment bodies blanked, so the prose above a fold is not read as a fold. */
function code(src: string): string {
	return src
		.replace(/\/\*[\s\S]*?\*\//g, ' ')
		.split('\n')
		.map((l) => (/^\s*\/\//.test(l) ? '' : l.replace(/\s\/\/.*$/, '')))
		.join('\n');
}

test('every Lambda read of PUBLIC_SITE_URL goes through siteOrigin', () => {
	const offenders: string[] = [];
	let reads = 0;

	for (const file of sourceFiles(lambdaRoot)) {
		const rel = file.slice(lambdaRoot.length + 1);
		for (const line of code(readFileSync(file, 'utf-8')).split('\n')) {
			if (!line.includes('PUBLIC_SITE_URL')) continue;
			reads++;
			if (!/siteOrigin\(\s*process\.env\.PUBLIC_SITE_URL/.test(line)) {
				offenders.push(`${rel}: ${line.trim().slice(0, 90)}`);
			}
		}
	}

	// Population: a walker that found nothing would satisfy the assertion below
	// while proving nothing.
	assert.ok(reads >= 5, `found only ${reads} PUBLIC_SITE_URL reads under lambda/ — walker broken?`);

	assert.deepEqual(
		offenders.sort(),
		[],
		'these resolve the site origin by hand. A `?? DEFAULT_SITE_URL` keeps an ' +
			'empty env var as the origin and every og:url / og:image the function ' +
			'emits comes out root-relative; `siteOrigin` folds blank to the default ' +
			'and trims a trailing slash.',
	);
});

test('a blank origin makes the unfurl tags root-relative, which siteOrigin prevents', () => {
	const run = {
		id: 'r1',
		title: 'Morning',
		distance_m: 5000,
		duration_s: 1500,
		started_at: '2026-09-01T06:00:00Z',
	} as unknown as Parameters<typeof buildShareRunMeta>[0]['run'];

	// The fold the Lambdas used: `??` leaves an empty env var as the origin.
	const blank = buildShareRunMeta({ id: 'r1', run, displayName: 'Jo', siteUrl: '' });
	assert.equal(blank.canonical, '/share/run/r1');
	assert.equal(blank.ogImageUrl, '/og/run/r1.png');
	// Open Graph requires an absolute URL, and this is the same root-relative
	// unfurl image `share_url_source_guard.test.ts` already bans at the source
	// level — banned in the sources, still reachable through the env.
	assert.match(
		renderShareRunHeadTags(blank),
		/<meta property="og:image" content="\/og\/run\/r1\.png">/,
	);

	// The fold they use now.
	const folded = buildShareRunMeta({
		id: 'r1',
		run,
		displayName: 'Jo',
		siteUrl: siteOrigin(''),
	});
	assert.equal(folded.canonical, `${DEFAULT_SITE_URL}/share/run/r1`);
	assert.equal(folded.ogImageUrl, `${DEFAULT_SITE_URL}/og/run/r1.png`);
});

test('the share-entity head is absolute under every shape of a misconfigured env', () => {
	const event = {
		id: 'e1',
		title: 'Track night',
		starts_at: '2026-09-10T18:00:00Z',
	} as unknown as Parameters<typeof buildShareEventHead>[0]['event'];

	for (const configured of [undefined, null, '', '   ', 'https://threkir.com/']) {
		const tags = renderShareEventHeadTags(
			buildShareEventHead({ id: 'e1', event, siteUrl: siteOrigin(configured) }),
		);
		for (const property of ['og:url', 'og:image']) {
			const match = tags.match(new RegExp(`<meta property="${property}" content="([^"]*)">`));
			assert.ok(match, `${property} missing for ${JSON.stringify(configured)}`);
			assert.match(
				match[1],
				/^https:\/\//,
				`${property} is not absolute for ${JSON.stringify(configured)}: ${match[1]}`,
			);
			assert.doesNotMatch(
				match[1],
				/^https:\/\/[^/]+\/\//,
				`${property} carries a doubled slash for ${JSON.stringify(configured)}: ${match[1]}`,
			);
		}
	}
});
