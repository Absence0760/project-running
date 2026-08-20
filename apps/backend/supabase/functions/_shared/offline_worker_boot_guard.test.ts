import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

// Every stack-using CI job's setup polls clip-public-track for a 405 to prove
// the edge runtime is really serving. A worker can only boot offline if nothing
// in its module graph carries a bare `node:` specifier: the runtime resolves
// those types from registry.npmjs.org, and when that fetch fails the worker
// never starts, the probe hangs to its timeout, and the job dies before one
// test runs. esm.sh's default build imports `node:buffer` / `node:process`;
// `?target=deno` is the only variant measured to avoid them (`?no-dts` does
// not, and no released edge-runtime image does either). Decisions § 699.
//
// Type-only imports count. Leaving the `import type` in rate_limit.ts at the
// default re-arms the failure for clip-public-track by itself — measured, not
// assumed — so both files are pinned here.
const PROBE_PATH_FILES = [
	'clip-public-track/index.ts',
	'_shared/rate_limit.ts'
];

const here = new URL('.', import.meta.url).pathname;
const functionsRoot = `${here}..`;

Deno.test('the probe path imports supabase-js at ?target=deno so a worker boots offline', async () => {
	for (const rel of PROBE_PATH_FILES) {
		const src = await Deno.readTextFile(`${functionsRoot}/${rel}`);
		const imports = [...src.matchAll(/['"](https:\/\/esm\.sh\/@supabase\/supabase-js@[^'"]*)['"]/g)].map(
			(m) => m[1]
		);
		assert(
			imports.length > 0,
			`${rel} no longer imports supabase-js from esm.sh — if that is deliberate, update this guard`
		);
		for (const url of imports) {
			assert(
				url.includes('target=deno'),
				`${rel} imports ${url} without ?target=deno, which re-arms the offline worker-boot failure every CI job's setup probe depends on (decisions § 699)`
			);
		}
	}
});
