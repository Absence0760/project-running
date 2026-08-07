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
		.replace(/\/\*[\s\S]*?\*\//g, ' ')
		.split('\n')
		.map((l) => (/^\s*(\/\/|\/\/\/)/.test(l) ? '' : l.replace(/\s\/\/.*$/, '')))
		.join('\n');
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
