import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { DEFAULT_SITE_URL, siteOrigin } from './site_url.js';

/**
 * The site origin's default used to be spelled 28 times — 15 as a named
 * `DEFAULT_SITE_URL` per module and 13 inline as `env.PUBLIC_SITE_URL || '…'`.
 * A default in 28 places is a default nobody can change: a host rename would
 * have to find all of them, and the ones it missed would emit a canonical
 * pointing at the old domain, which is §546's `<loc>`-disagrees-with-its-page
 * defect one layer up.
 *
 * The scan deliberately spares an email address and an iCal `uid`: those share
 * the string and are a different concept — a mailbox and an RFC 5545 identity
 * domain do not move when the site is served from another host. It also spares
 * comments, because prose naming the default is how a reader learns it.
 */

const webRoot = resolve(import.meta.dirname, '..', '..', '..');
const scanRoots = ['src', 'lambda'];
const host = DEFAULT_SITE_URL.replace('https://', '');

function sourceFiles(dir: string): string[] {
	let out: string[] = [];
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === 'build' || entry === 'dist') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) out = out.concat(sourceFiles(full));
		else if (/\.(ts|svelte)$/.test(entry) && !entry.includes('.test.')) out.push(full);
	}
	return out;
}

/** Comment bodies blanked, so prose naming the host is not a use of it. */
function code(src: string): string {
	return src
		.split('\n')
		.map((l) => (/^\s*(\/\/|\/\/\/)/.test(l) ? '' : l.replace(/\s\/\/.*$/, '')))
		.join('\n')
		.replace(/\/\*[\s\S]*?\*\//g, ' ');
}

test('the site origin default is spelled in exactly one place', () => {
	const offenders: string[] = [];
	let scanned = 0;

	for (const root of scanRoots) {
		for (const file of sourceFiles(join(webRoot, root))) {
			const rel = file.slice(webRoot.length + 1);
			if (rel === join('src', 'lib', 'core', 'site_url.ts')) continue;
			scanned++;
			const src = code(readFileSync(file, 'utf-8'));
			for (const line of src.split('\n')) {
				if (!line.includes(host)) continue;
				// An address or an iCal identity domain, not the origin. Keyed on
				// the `@` immediately before the host, so an interpolated uid
				// (`${startIso}@host`) is spared as surely as a literal mailbox.
				if (line.includes(`@${host}`)) continue;
				offenders.push(`${rel}: ${line.trim().slice(0, 80)}`);
			}
		}
	}

	// Population: a walker that found nothing would satisfy the assertion below
	// while proving nothing (decisions §534).
	assert.ok(scanned > 300, `scanned only ${scanned} source files — walker broken?`);

	assert.deepEqual(
		offenders.sort(),
		[],
		'these spell the site origin instead of importing DEFAULT_SITE_URL from ' +
			'$lib/core/site_url. An email address or an iCal uid is a different ' +
			'concept and is already spared.'
	);
});

test('siteOrigin folds a blank env to the default and trims a trailing slash', () => {
	assert.equal(siteOrigin(undefined), DEFAULT_SITE_URL);
	assert.equal(siteOrigin(null), DEFAULT_SITE_URL);
	// An env var set to empty is a deploy that failed to configure it, not a
	// request to serve canonicals from nowhere.
	assert.equal(siteOrigin(''), DEFAULT_SITE_URL);
	assert.equal(siteOrigin('   '), DEFAULT_SITE_URL);
	assert.equal(siteOrigin('https://preview.example.com'), 'https://preview.example.com');
	assert.equal(siteOrigin('https://preview.example.com/'), 'https://preview.example.com');
	assert.equal(siteOrigin('https://preview.example.com///'), 'https://preview.example.com');
	assert.equal(siteOrigin('  https://x.test  '), 'https://x.test');
});

/**
 * The second half of the same contract: not only is the default spelled once,
 * every read of `PUBLIC_SITE_URL` folds it through `siteOrigin`.
 *
 * The two folds this replaces are not equivalent and neither was safe. The
 * Lambdas used `?? DEFAULT_SITE_URL`, which fires only on null/undefined, so a
 * `PUBLIC_SITE_URL=""` survived as the origin and every og:url came out
 * root-relative (decisions § 895). The twenty-two callers under `src/routes/`
 * used `|| DEFAULT_SITE_URL`, which does catch the empty string — but not a
 * whitespace-only value, which is truthy and produced a canonical of
 * `   /share/run/<id>`, and not a trailing slash, which produced
 * `https://threkir.com//share/run/<id>` (both measured, § 970).
 *
 * `siteOrigin` is the one place either question is answered. This registers
 * every caller so a twenty-eighth cannot re-decide it.
 */
test('every read of PUBLIC_SITE_URL folds through siteOrigin', () => {
	const offenders: string[] = [];
	let reads = 0;

	for (const root of scanRoots) {
		for (const file of sourceFiles(join(webRoot, root))) {
			const rel = file.slice(webRoot.length + 1);
			if (rel === join('src', 'lib', 'core', 'site_url.ts')) continue;
			for (const line of code(readFileSync(file, 'utf-8')).split('\n')) {
				if (!line.includes('PUBLIC_SITE_URL')) continue;
				reads++;
				// `env.PUBLIC_SITE_URL` in a route, `process.env.PUBLIC_SITE_URL`
				// in a Lambda — the two runtimes expose it differently, which is
				// why the helper takes the value rather than reading it itself.
				if (!/siteOrigin\(\s*(?:process\.)?env\.PUBLIC_SITE_URL\s*\)/.test(line)) {
					offenders.push(`${rel}: ${line.trim().slice(0, 90)}`);
				}
			}
		}
	}

	// Population: a walker that found nothing would satisfy the assertion below
	// while proving nothing (decisions §534).
	assert.ok(reads >= 27, `found only ${reads} PUBLIC_SITE_URL reads — walker broken?`);

	assert.deepEqual(
		offenders.sort(),
		[],
		'these resolve the site origin by hand. `??` keeps an empty env var as the ' +
			'origin and `||` keeps a whitespace-only one; neither trims a trailing ' +
			'slash. Fold through siteOrigin from $lib/core/site_url.',
	);
});
