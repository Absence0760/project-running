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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const lambdaRoot = resolve(import.meta.dirname, '..', '..', 'lambda');

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
