import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

// Every stack-using CI job's setup polls clip-public-track for a 405 to prove
// the edge runtime is really serving. A worker can only boot offline if nothing
// in its module graph carries a bare `node:` specifier: the runtime resolves
// those types from registry.npmjs.org, and when that fetch fails the worker
// never starts, the probe hangs to its timeout, and the job dies before one
// test runs. esm.sh's default build imports `node:buffer` / `node:process`;
// `?target=deno` is the only variant measured to avoid them (`?no-dts` does
// not, and no released edge-runtime image does either). Decisions § 699.
//
// Type-only imports count — leaving one at the default re-arms the failure by
// itself, measured, not assumed — so this walks the probe function's WHOLE
// local module graph rather than a hand-written list of the files that happen
// to import supabase-js today. The list version went stale the moment
// `rate_limit.ts` moved its client type behind `_shared/database.ts`: it then
// asserted over a file with no supabase-js import at all while the module that
// had inherited the obligation was named nowhere.
const PROBE_ENTRY = 'clip-public-track/index.ts';

const FUNCTIONS_ROOT = new URL('../', import.meta.url);

const SUPABASE_JS = /^https:\/\/esm\.sh\/@supabase\/supabase-js@/;

/// Every `from '…'` / bare `import '…'` specifier in one module's source.
function specifiersOf(src: string): string[] {
	return [
		...src.matchAll(/(?:^|\n)\s*(?:import|export)[\s\S]*?from\s*['"]([^'"]+)['"]/g),
		...src.matchAll(/(?:^|\n)\s*import\s*['"]([^'"]+)['"]/g),
	].map((m) => m[1]);
}

Deno.test("the probe path's whole module graph imports supabase-js at ?target=deno", async () => {
	const visited = new Set<string>();
	const queue = [new URL(PROBE_ENTRY, FUNCTIONS_ROOT).href];
	const supabaseImports: { module: string; specifier: string }[] = [];

	while (queue.length > 0) {
		const href = queue.pop()!;
		if (visited.has(href)) continue;
		visited.add(href);

		const src = await Deno.readTextFile(new URL(href));
		const rel = href.slice(FUNCTIONS_ROOT.href.length);
		for (const spec of specifiersOf(src)) {
			if (SUPABASE_JS.test(spec)) {
				supabaseImports.push({ module: rel, specifier: spec });
				continue;
			}
			if (spec.startsWith('./') || spec.startsWith('../')) {
				queue.push(new URL(spec, href).href);
			}
		}
	}

	assert(
		visited.size > 1,
		`the walk from ${PROBE_ENTRY} reached only itself — the specifier scan is not ` +
			'seeing this tree\'s relative imports, so it would pass over any graph',
	);
	assert(
		supabaseImports.length > 0,
		`nothing on the probe path (${visited.size} modules from ${PROBE_ENTRY}) imports ` +
			'supabase-js from esm.sh any more. If that is deliberate, this guard now enforces ' +
			'nothing and should be retargeted at whatever the graph pulls in instead',
	);

	const wrong = supabaseImports.filter(({ specifier }) => !specifier.includes('target=deno'));
	assertEquals(
		wrong,
		[],
		'these modules on the probe path import supabase-js without ?target=deno, which ' +
			're-arms the offline worker-boot failure every CI job\'s setup probe depends on ' +
			`(decisions § 699): ${wrong.map((w) => `${w.module} -> ${w.specifier}`).join(', ')}`,
	);
});
