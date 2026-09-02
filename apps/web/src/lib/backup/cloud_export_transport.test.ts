// Which rail an export request takes, and what it may assume about the
// answer. Invocation:
//   npx tsx --test src/lib/backup/cloud_export_transport.test.ts
//
// `cloud_export.ts` reads `$env/dynamic/public` and supabase-js, so it
// cannot be executed here; `cloud_export_helpers.test.ts` covers every
// pure piece it composes. What neither covers is the composition, and the
// composition is where decisions § 717 and § 724 live: the Go service's
// SYNCHRONOUS `POST /v1/export` was deleted, so a call site that reaches
// for it again gets a 404 in production and nothing in this tree notices.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
	buildCloudExportBody,
	buildCloudExportJobStatusUrl,
	buildCloudExportJobsUrl,
} from './cloud_export_helpers';

const CALLER = 'src/lib/backup/cloud_export.ts';
const HELPERS = 'src/lib/backup/cloud_export_helpers.ts';

function stripComments(s: string): string {
	return s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function read(path: string): string {
	return stripComments(readFileSync(resolve(path), 'utf-8'));
}

test('the deleted synchronous rail has no builder and no caller', () => {
	// § 724 removed `POST /v1/export`. Both halves have to stay gone: a
	// surviving builder is what a future call site would reach for.
	assert.doesNotMatch(
		read(HELPERS),
		/export function buildCloudExportUrl\b/,
		'the synchronous export URL builder was deleted with decisions § 724',
	);
	const caller = read(CALLER);
	// Every path string in the caller must come from a builder, so the
	// only literal endpoints left are the ones the helpers own.
	assert.doesNotMatch(
		caller,
		/'\/v1\/export'|`\$\{[^}]*\}\/v1\/export`/,
		'the Go service has no synchronous export endpoint to POST to',
	);
	assert.match(caller, /buildCloudExportJobsUrl\(hubUrl\)/);
	assert.match(caller, /buildCloudExportJobStatusUrl\(hubUrl\)/);
});

test('the two hub URLs the caller uses are distinct and both under /v1/export/jobs', () => {
	const base = 'https://live.example.com';
	assert.equal(buildCloudExportJobsUrl(base), `${base}/v1/export/jobs`);
	assert.equal(buildCloudExportJobStatusUrl(base), `${base}/v1/export/jobs/latest`);
	assert.notEqual(buildCloudExportJobsUrl(base), buildCloudExportJobStatusUrl(base));
});

test('every declared export format has a body shape', () => {
	// The union is a rail against `data_export_jobs_format_chk`, checked by
	// scripts/check_constraint_unions.mjs. What that guard cannot see is a
	// format the body builder mangles — `backup` was the one the existing
	// suite never built.
	for (const format of ['csv', 'gpx', 'backup'] as const) {
		assert.equal(buildCloudExportBody(format), JSON.stringify({ format }));
		assert.deepEqual(JSON.parse(buildCloudExportBody(format)), { format });
	}
});

test('both hub calls require a session before they are made', () => {
	const caller = read(CALLER);
	assert.match(
		caller,
		/if \(!token\) throw new CloudExportError\('unauthorized'\)/,
		'hubSession must refuse rather than send an anonymous request',
	);
	// Both hub-rail entry points have to go through it — the endpoint's
	// JWTAuthorizer rejects anon, so an unauthenticated call is a 401 the
	// caller would surface as an export failure.
	assert.equal(
		[...caller.matchAll(/await hubSession\(\)/g)].length,
		2,
		'startCloudExport and fetchCloudExportJob must each resolve a session',
	);
});

test('an unconfigured hub answers `none` rather than throwing', () => {
	// The status read runs on mount. With `PUBLIC_EXPORT_HUB_URL` unset
	// there is no job to watch at all — the Edge Function rail builds
	// inline — so a caller must not have to branch on the transport.
	const caller = read(CALLER);
	const fn = caller.slice(
		caller.indexOf('export async function fetchCloudExportJob'),
		caller.indexOf('async function edgeFunctionExport'),
	);
	assert.ok(fn.length > 0, 'fetchCloudExportJob not found — did it move?');
	assert.match(
		fn,
		/if \(!hubUrl\) return \{ status: 'none' \};/,
		'an unconfigured hub must answer none, not throw',
	);
});

test('a rate-limited hub answer carries the retry window it was given', () => {
	const caller = read(CALLER);
	assert.match(caller, /res\.status === 429/, 'a 429 must be told apart from a 5xx');
	assert.match(
		caller,
		/headers\.get\('retry-after'\)/,
		'the wait must come from the response, not be invented',
	);
});

test('the enqueue answer is normalised, never cast', () => {
	// The enqueue and the status endpoint speak one status vocabulary, and
	// the normaliser is what makes an unknown status terminal instead of a
	// poll that never ends.
	const caller = read(CALLER);
	assert.equal(
		[...caller.matchAll(/cloudExportJobFromResponse\(/g)].length,
		2,
		'both the enqueue and the status read must go through the normaliser',
	);
	assert.doesNotMatch(
		caller,
		/as CloudExportJob\b/,
		'a cast would let an unrecognised status poll for ever',
	);
});

test('nothing a server said reaches the caller as a message', () => {
	// The failure toast interpolates whatever `.message` carries. Both rails
	// used to put a server's own words there: the hub's was
	// `Export failed (${status}): ${body}` and the Edge Function rail
	// rethrew supabase-js's fixed "Edge Function returned a non-2xx status
	// code" — a sentence about our transport, in English, shown to a subject
	// asking for their own data (decisions § 983). Every throw out of this
	// module is now a code the surface maps to translated copy.
	const caller = read(CALLER);
	const throws = [...caller.matchAll(/\bthrow\s+([^;]+);/g)].map((m) => m[1].trim());
	assert.ok(throws.length >= 5, `expected the throw sites to be found; got ${throws.length}`);
	assert.deepEqual(
		throws.filter((t) => !t.startsWith('new CloudExportError(')),
		[],
		'every refusal out of this module must be a CloudExportError carrying a code, ' +
			'never a sentence assembled from a status line or a server body',
	);
	// The failure vocabulary is closed: a fourth code would reach the
	// surface's `else` branch and read as a generic server failure.
	const codes = [...caller.matchAll(/new CloudExportError\(\s*'([a-z_]+)'/g)].map((m) => m[1]);
	assert.deepEqual(
		[...new Set(codes)].sort(),
		['export_failed', 'rate_limited', 'unauthorized'],
		'the codes thrown must match the CloudExportFailure union the surface maps',
	);
});

test('the export-data envelope is unwrapped, never rethrown', () => {
	const caller = read(CALLER);
	const fn = caller.slice(caller.indexOf('async function edgeFunctionExport'));
	assert.ok(fn.length > 0, 'edgeFunctionExport not found — did it move?');
	assert.doesNotMatch(fn, /\bthrow\s+error\s*;/, 'the FunctionsHttpError must not be rethrown');
	assert.match(
		fn,
		/await edgeFunctionErrorCode\(error\)/,
		"the function's own error code must be read off the envelope",
	);
});
