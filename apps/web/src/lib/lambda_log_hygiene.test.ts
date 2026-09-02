// What the production Lambdas are allowed to put in a CloudWatch log line.
//
// These eight handlers are the only server-side compute outside Supabase, and
// the values passing through them are the most sensitive the product has: the
// osrm-proxy's request PATH *is* the runner's waypoint coordinates
// (`/api/routes/osrm/route/v1/foot/-0.1,51.5;-0.12,51.51`), the generate-route
// body carries a start coordinate, and the coach's provider stream carries the
// runner's own coaching conversation. Nothing stops a log line from naming any
// of it, and the shape that would do it is a copy-paste away: the five share
// Lambdas log `path: event.rawPath` — correct there, because a share path is a
// public URL carrying a public entity id — and that catch block is the
// obvious thing to copy into a sibling whose path is a location.
//
// Two rules, both derived from the shape the tree already uses. See
// decisions § 897.
//
// The rules follow the CODE INTO CloudWatch, not the directory. Each of these
// handlers is a thin wrapper whose whole job is to call a transport-agnostic
// core under `src/lib` (decisions § 53), and it is the core that makes the
// provider call, catches its error, and logs it -- into the wrapper's own log
// group. Walking `lambda/` alone therefore checked every file except the ones
// holding the shape the rules exist to stop, which is how
// `console.error('[route-request] provider call failed', e)` sat two frames
// below a guard written against exactly that line.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

const lambdaRoot = resolve(import.meta.dirname, '..', '..', 'lambda');
const libRoot = resolve(import.meta.dirname);

/**
 * Which `event.<field>` reads each handler's log lines may name. A share path
 * is a public URL naming a public entity, so those five declare `rawPath`;
 * nothing else declares anything, because nothing else has a request field
 * that is safe to write down.
 */
const ALLOWED_EVENT_FIELDS: Record<string, ReadonlySet<string>> = {
	coach: new Set(),
	'generate-route': new Set(),
	'osrm-proxy': new Set(),
	'share-badge': new Set(['rawPath']),
	'share-entity': new Set(['rawPath']),
	'share-recap': new Set(['rawPath']),
	'share-route': new Set(['rawPath']),
	'share-run': new Set(['rawPath']),
};

function handlerSources(): Array<{ lambda: string; rel: string; src: string }> {
	const out: Array<{ lambda: string; rel: string; src: string }> = [];
	for (const lambda of readdirSync(lambdaRoot)) {
		const srcDir = join(lambdaRoot, lambda, 'src');
		if (!statSync(join(lambdaRoot, lambda)).isDirectory()) continue;
		for (const entry of readdirSync(srcDir)) {
			if (!entry.endsWith('.ts')) continue;
			out.push({
				lambda,
				rel: `${lambda}/src/${entry}`,
				src: readFileSync(join(srcDir, entry), 'utf-8'),
			});
		}
	}
	return out;
}

/**
 * Every module under `src/lib` transitively reachable from a Lambda entry
 * point, by following relative imports. These run in the Lambda's process and
 * write to its log group, so the same two rules bind them -- but they are also
 * ordinary app modules, so the walk is by reachability rather than by a hand
 * kept list that would go stale the first time a handler grew an import.
 */
function lambdaReachableLibSources(): Array<{ rel: string; src: string }> {
	const seen = new Set<string>();
	const queue: string[] = [];
	for (const lambda of readdirSync(lambdaRoot)) {
		const srcDir = join(lambdaRoot, lambda, 'src');
		if (!statSync(join(lambdaRoot, lambda)).isDirectory()) continue;
		for (const entry of readdirSync(srcDir)) {
			if (entry.endsWith('.ts')) queue.push(join(srcDir, entry));
		}
	}
	const out: Array<{ rel: string; src: string }> = [];
	while (queue.length > 0) {
		const file = queue.pop()!;
		if (seen.has(file)) continue;
		seen.add(file);
		let src: string;
		try {
			src = readFileSync(file, 'utf-8');
		} catch {
			continue;
		}
		if (file.startsWith(libRoot + '/')) {
			out.push({ rel: file.slice(resolve(libRoot, '..', '..').length + 1), src });
		}
		for (const m of src.matchAll(/from '([^']+)'/g)) {
			const specifier = m[1];
			/** @see the closure test at the bottom of this file */
			let base: string;
			if (specifier.startsWith('.')) base = resolve(dirname(file), specifier);
			else if (specifier.startsWith('$lib/')) base = join(libRoot, specifier.slice(5));
			else continue;
			for (const candidate of [`${base}.ts`, join(base, 'index.ts')]) {
				try {
					if (statSync(candidate).isFile()) {
						queue.push(candidate);
						break;
					}
				} catch {
					// not this shape; try the next
				}
			}
		}
	}
	return out;
}

/** Comment bodies blanked, so prose about a log line is not read as one. */
function code(src: string): string {
	return src
		.replace(/\/\*[\s\S]*?\*\//g, ' ')
		.split('\n')
		.map((l) => (/^\s*\/\//.test(l) ? '' : l.replace(/\s\/\/.*$/, '')))
		.join('\n');
}

/**
 * The top-level arguments of every `console.<level>(…)` call in `src`, as raw
 * text. Tracks bracket depth and string/template state so a `)` inside a
 * literal or a nested call does not end the argument list early.
 */
function consoleCallArgs(src: string): string[][] {
	const calls: string[][] = [];
	const re = /console\.(?:log|error|warn|info|debug)\(/g;
	let m: RegExpExecArray | null;
	while ((m = re.exec(src))) {
		let depth = 1;
		let i = m.index + m[0].length;
		let current = '';
		const args: string[] = [];
		let quote: string | null = null;
		for (; i < src.length && depth > 0; i++) {
			const c = src[i];
			if (quote) {
				if (c === '\\') {
					current += c + (src[i + 1] ?? '');
					i++;
					continue;
				}
				if (c === quote) quote = null;
				current += c;
				continue;
			}
			if (c === "'" || c === '"' || c === '`') {
				quote = c;
				current += c;
				continue;
			}
			if (c === '(' || c === '[' || c === '{') depth++;
			else if (c === ')' || c === ']' || c === '}') depth--;
			if (depth === 0) break;
			if (c === ',' && depth === 1) {
				args.push(current.trim());
				current = '';
				continue;
			}
			current += c;
		}
		if (current.trim()) args.push(current.trim());
		calls.push(args);
	}
	return calls;
}

test('no Lambda log line names a request field its handler has not declared', () => {
	const offenders: string[] = [];
	let calls = 0;

	for (const { lambda, rel, src } of handlerSources()) {
		const allowed = ALLOWED_EVENT_FIELDS[lambda];
		assert.ok(allowed, `${lambda} has no entry in ALLOWED_EVENT_FIELDS — declare what it may log.`);
		for (const args of consoleCallArgs(code(src))) {
			calls++;
			for (const arg of args) {
				for (const field of arg.matchAll(/\bevent\.(\w+)/g)) {
					if (!allowed.has(field[1])) {
						offenders.push(`${rel}: logs event.${field[1]}`);
					}
				}
			}
		}
	}

	// Population: an empty walk would satisfy the assertion below while
	// proving nothing.
	assert.ok(calls >= 10, `found only ${calls} console calls under lambda/ — walker broken?`);

	assert.deepEqual(
		offenders.sort(),
		[],
		"a request field reaches CloudWatch. The osrm-proxy's path IS the runner's " +
			'waypoint coordinates and the generate-route body carries a start ' +
			'coordinate; if a field really is safe to log, declare it in ' +
			'ALLOWED_EVENT_FIELDS with the reason it is.',
	);
});

test('every Lambda log line is a fixed message plus an object literal, never a raw value', () => {
	// `console.error('…', e)` hands the whole caught value to CloudWatch, and a
	// provider SDK's error object can carry the response body or the request
	// that produced it. Every catch in this tree normalises to
	// `{ message, stack }`; this is what keeps the next one from not.
	const offenders: string[] = [];
	let calls = 0;

	for (const { rel, src } of handlerSources()) {
		for (const args of consoleCallArgs(code(src))) {
			calls++;
			const [first, ...rest] = args;
			if (!first || !/^['"`]/.test(first)) {
				offenders.push(`${rel}: ${(first ?? '(no argument)').slice(0, 60)}`);
			}
			for (const arg of rest) {
				if (!arg.startsWith('{')) offenders.push(`${rel}: ${arg.slice(0, 60)}`);
			}
		}
	}

	assert.ok(calls >= 10, `found only ${calls} console calls under lambda/ — walker broken?`);
	assert.deepEqual(
		offenders.sort(),
		[],
		'a log line opens with something other than a literal message, or hands ' +
			'over a value that is not an object literal. Normalise a caught error ' +
			'to { message, stack } the way every other catch in this tree does.',
	);
});

test('no lambda-reachable core hands a caught value straight to CloudWatch', () => {
	// The wrapper's rule, applied one frame down. An argument that is a bare
	// identifier or member chain is the caught value itself: an Anthropic
	// `APIError` carries the response body, and for a 400 that body quotes the
	// part of the request it objected to -- on `/route-request` that is the
	// runner's typed sentence and their location label. Everything already in
	// this set narrows first (`supabaseErrorFields(...)`, `e.message`), so the
	// test admits a call or a conditional and refuses only the raw value.
	const BARE = /^[A-Za-z_$][\w$]*(?:\??\.[A-Za-z_$][\w$]*)*$/;
	const offenders: string[] = [];
	let calls = 0;
	const modules = lambdaReachableLibSources();

	for (const { rel, src } of modules) {
		for (const args of consoleCallArgs(code(src))) {
			calls++;
			const [first, ...rest] = args;
			if (!first || !/^['"`]/.test(first)) {
				offenders.push(`${rel}: opens with ${(first ?? '(no argument)').slice(0, 60)}`);
			}
			for (const arg of rest) {
				if (BARE.test(arg)) offenders.push(`${rel}: logs the raw value \`${arg}\``);
			}
		}
	}

	// Population: the walk resolving nothing would satisfy the assertion below
	// while proving nothing. Both counts are well under what the tree holds.
	assert.ok(
		modules.length >= 20,
		`only ${modules.length} lib modules reached from lambda/ — import walk broken?`,
	);
	assert.ok(calls >= 20, `found only ${calls} console calls in those modules — walker broken?`);

	assert.deepEqual(
		offenders.sort(),
		[],
		'a Lambda-reachable core logs a value it has not narrowed. Normalise a ' +
			'caught error to { message, stack } the way the wrappers do.',
	);
});

// The walk is by reachability precisely so it cannot go stale, and a specifier
// spelling it does not follow is exactly the way it would go stale anyway: a
// module one importer names through the `$lib` alias and another names
// relatively runs in the Lambda's process and writes to its log group either
// way. The walk followed only the relative spelling until this test was
// written.
//
// The property is closure — every module in the set resolves every import it
// makes into another module in the set — and it is checkable without naming a
// module. The resolution here is deliberately its OWN, not the walker's: a test
// that asks the walker how to resolve an import agrees with the walker by
// construction and cannot fail, which is what the first draft of this test did.
test('the reachable set is closed under both import spellings src/lib uses', () => {
	const modules = lambdaReachableLibSources();
	const webRoot = resolve(import.meta.dirname, '..', '..');
	const reached = new Set(modules.map((m) => resolve(webRoot, m.rel)));
	const missed: string[] = [];
	for (const { rel, src } of modules) {
		const from = resolve(webRoot, rel);
		for (const m of src.matchAll(/from '([^']+)'/g)) {
			const specifier = m[1];
			const base = specifier.startsWith('$lib/')
				? join(libRoot, specifier.slice(5))
				: specifier.startsWith('.')
					? resolve(dirname(from), specifier)
					: null;
			if (base === null) continue;
			for (const candidate of [`${base}.ts`, join(base, 'index.ts')]) {
				let isFile = false;
				try {
					isFile = statSync(candidate).isFile();
				} catch {
					continue;
				}
				if (!isFile) continue;
				if (candidate.startsWith(`${libRoot}/`) && !reached.has(candidate)) {
					missed.push(`${rel} imports '${specifier}', which the walk never reached`);
				}
				break;
			}
		}
	}
	assert.ok(modules.length >= 20, `only ${modules.length} modules reached — walk broken?`);
	assert.deepEqual(
		missed.sort(),
		[],
		'a module a Lambda can reach is outside the set these rules are applied to.',
	);
});

// The caller's own bearer token is the third thing that must not reach
// CloudWatch, alongside a request field and a raw caught error. Five of these
// cores logged `tokenPrefix: accessToken.slice(0, 20) + '...'` on a failed
// auth. For a Supabase JWT those twenty characters are the base64url header,
// byte-identical for every token the project ever issues, so the field
// identified nothing while writing bytes of a live credential into a log group
// kept for thirty days; Supabase's newer `sb_…` keys are opaque strings whose
// first twenty characters are not a constant at all.
//
// The rule is the token name, because that is what a source guard can read:
// the identifier holding the credential may not appear in a log line's
// arguments, in any spelling — sliced, interpolated, or whole. Whether the
// value was a JWT at all is already in the GoTrue error these lines log
// beside it.
test('no Lambda-reachable log line names the caller\'s bearer token', () => {
	const CREDENTIAL = /\b(accessToken|authHeader|refreshToken|apiKey|anonKey|secretKey)\b/;
	const offenders: string[] = [];
	let calls = 0;
	const modules = [
		...handlerSources().map((h) => ({ rel: h.rel, src: h.src })),
		...lambdaReachableLibSources(),
	];
	for (const { rel, src } of modules) {
		for (const args of consoleCallArgs(code(src))) {
			calls++;
			for (const arg of args) {
				const named = arg.match(CREDENTIAL);
				if (named) offenders.push(`${rel}: logs \`${named[1]}\``);
			}
		}
	}
	assert.ok(calls >= 20, `found only ${calls} console calls — walker broken?`);
	assert.deepEqual(
		offenders.sort(),
		[],
		"a log line names the caller's credential. No part of a bearer token is " +
			'worth thirty days in CloudWatch; the GoTrue error beside it already ' +
			'says whether the value parsed.',
	);
});
