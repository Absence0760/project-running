import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

import { stripComments } from './core/strip_comments';

/**
 * Guard-rail: a response body is parsed inside a `try`, behind a `.catch`, or
 * with a registered reason why throwing is the contract.
 *
 * `res.json()` rejects on a 200 whose body is truncated or is not JSON — a
 * proxy error page, a captive portal, a connection cut mid-stream. § 1066
 * found `geocodeViaMapTiler` doing that inside a function documented to return
 * null, forty lines from a sibling that guarded it, and asked for the class to
 * be searched. It ran to two more (§ 1087): `geocodeViaNominatim`, the OTHER
 * branch of the same exported function, and `snapToRoad`, which has no
 * throwing branch at all — it hands back the unsnapped point on every failure,
 * so no caller has a reason to wrap it.
 *
 * The rule is not "every parse must be guarded": three of the sites here
 * document a THROWS contract, and their callers depend on it to tell a failed
 * source from an empty one. The contract lives in a doc comment, not in the
 * return type — `lookupBarcode` returns `Promise<T | null>` and throws on a
 * parse failure on purpose — so a deliberate site is registered by hand with
 * its reason and its count. A count that drifts fails, in both directions: a
 * new unguarded parse in a registered file, and a registered file that no
 * longer has one.
 *
 * Invocation:
 *   npx tsx --test src/lib/response_body_parse_guard.test.ts
 */

const libRoot = import.meta.dirname;
const webRoot = resolve(libRoot, '..', '..');
const srcRoot = resolve(webRoot, 'src');
const lambdaRoot = resolve(webRoot, 'lambda');

/// Sites where a rejecting parse is the documented contract,
/// `path relative to apps/web` -> `[count, why]`.
const REGISTER: Record<string, [number, string]> = {
	'src/lib/nutrition/food_search.ts': [
		3,
		'searchFoods / lookupBarcode / searchUsda each document THROWS on a ' +
			'network, non-2xx or parse failure so the merge caller can tell a ' +
			'failed source from an empty one and offer a retry',
	],
	'src/lib/routes/routing.ts': [
		2,
		'fetchRoute / fetchFullRoute throw on every failure by contract ' +
			'(`OSRM error:` / `no route found`); snapToRoad, which fails soft, ' +
			'is guarded',
	],
	'src/lib/integrations/import.ts': [
		4,
		'parseRouteFile throws by contract — on an unsupported extension and on ' +
			'every parse failure — and ImportRoute.svelte catches and renders the ' +
			'message; these four are File reads, which reject only on a read error',
	],
	'src/lib/routes/route_describe_client.ts': [
		1,
		'requestAiDescription throws on every non-200 and on a malformed 200; ' +
			'its one caller catches everything and shows the same message',
	],
};

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name === 'dist' || entry.name === '.svelte-kit') {
				continue;
			}
			sourceFiles(full, out);
			continue;
		}
		if (!/\.(ts|svelte|mjs|js)$/.test(entry.name)) continue;
		// A test drives a mocked fetch; it carries no contract to break.
		if (/\.(test|spec)\.ts$/.test(entry.name)) continue;
		out.push(full);
	}
	return out;
}

/// Half-open [open brace, close brace] spans of every `try` block. The catch
/// and finally clauses sit outside the span on purpose: a parse in a `catch`
/// is not protected by the `try` it follows.
function tryBodies(src: string): Array<[number, number]> {
	const out: Array<[number, number]> = [];
	for (const m of src.matchAll(/\btry\s*\{/g)) {
		const open = m.index + m[0].length - 1;
		let depth = 0;
		for (let i = open; i < src.length; i++) {
			if (src[i] === '{') depth++;
			else if (src[i] === '}') {
				depth--;
				if (depth === 0) {
					out.push([open, i]);
					break;
				}
			}
		}
	}
	return out;
}

/// An awaited body read: `res.json()`, `res.text()`, and the `file.text()` a
/// File shares the failure shape with. A member chain is allowed
/// (`await this.res.json()`); a call result is not, and cannot occur — a
/// Response has to be awaited before its body can be.
const BODY_PARSE = /\bawait\s+[A-Za-z_$][\w$.]*\.(?:json|text)\(\)/g;

interface Site {
	file: string;
	line: number;
	guarded: boolean;
}

function scan(): Site[] {
	const out: Site[] = [];
	for (const file of [...sourceFiles(srcRoot), ...sourceFiles(lambdaRoot)]) {
		const src = stripComments(readFileSync(file, 'utf-8'));
		const bodies = tryBodies(src);
		for (const m of src.matchAll(BODY_PARSE)) {
			const i = m.index;
			const rest = src.slice(i + m[0].length);
			const guarded = bodies.some(([a, b]) => i > a && i < b) || /^\s*\.catch\s*\(/.test(rest);
			out.push({
				file: relative(webRoot, file).split('\\').join('/'),
				line: src.slice(0, i).split('\n').length,
				guarded,
			});
		}
	}
	return out;
}

test('every response-body parse is guarded or registered as throw-contracted', () => {
	const sites = scan();
	// Assert the population: a scan matching nothing satisfies every
	// "no unguarded parse" assertion below without reading a line.
	assert.ok(
		sites.length >= 15,
		`expected the web tree to still carry its response-body parses, found ${sites.length}`,
	);
	const counts = new Map<string, number>();
	const unregistered: string[] = [];
	for (const s of sites) {
		if (s.guarded) continue;
		counts.set(s.file, (counts.get(s.file) ?? 0) + 1);
		if (REGISTER[s.file] === undefined) unregistered.push(`${s.file}:${s.line}`);
	}
	assert.deepEqual(
		unregistered,
		[],
		'these parse a response body outside a try and without a .catch. If the ' +
			'function returns null / an outcome on failure, guard it; if throwing ' +
			'is the documented contract, register it with the reason:\n  ' +
			unregistered.join('\n  '),
	);
	for (const [file, [expected, why]] of Object.entries(REGISTER)) {
		assert.equal(
			counts.get(file) ?? 0,
			expected,
			`${file} is registered for ${expected} throw-contracted body parses ` +
				`("${why}") but carries ${counts.get(file) ?? 0}`,
		);
	}
});
