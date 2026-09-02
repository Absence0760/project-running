import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, relative } from 'node:path';

/**
 * No `supabase.functions.invoke` call site may rethrow supabase-js's error
 * as it stands (decisions § 904).
 *
 * Every non-2xx from an Edge Function arrives as a `FunctionsHttpError`
 * whose `message` is the fixed sentence "Edge Function returned a non-2xx
 * status code"; the function's own `{ error: '<code>' }` envelope is on
 * `context`. A bare `if (error) throw error;` therefore hands the caller a
 * statement about our transport in place of the refusal, and three surfaces
 * put that sentence in front of users before anyone noticed — one of them a
 * not-configured branch that could never be selected because the token it
 * matched on was never in the message it was applied to.
 *
 * The rule is mechanical and the drift is silent: a new call site written in
 * the obvious shape compiles, runs, and looks right. `core/edge_function_error.ts`
 * holds the unwrap; use `edgeFunctionErrorCode` when the caller maps codes
 * itself and `edgeFunctionErrorMessage` when it needs something to show.
 *
 * Sites that still rethrow are listed below WITH THE REASON, and a site that
 * stops rethrowing has to leave the list — a stale exemption is how a rule
 * quietly stops applying.
 */

/// Keyed by `<file basename>::<edge function name>`.
const REDTHROW_EXEMPT = new Map<string, string>([
	[
		'cloud_export.ts::export-data',
		'The legacy synchronous export transport. Its caller renders a generic ' +
			'failure either way, so nothing surfaces the message; filed for the ' +
			'unwrap in followups.md rather than changed blind.',
	],
	[
		'data.ts::clip-public-track',
		'Internal read used by the spectator track path; the throw is caught by ' +
			'callers that fall back to the unclipped-refused state rather than ' +
			'showing the message.',
	],
	[
		'data.ts::race-results-import',
		'Rethrown only after isProviderNotConfigured() has already read the ' +
			'envelope off `context`, which is the unwrap this rule is about.',
	],
]);

const SRC = resolve(import.meta.dirname, '..');
const SELF = resolve(import.meta.dirname, 'core', 'edge_function_error.ts');

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		const full = resolve(dir, entry);
		if (statSync(full).isDirectory()) {
			sourceFiles(full, out);
		} else if (
			(entry.endsWith('.ts') || entry.endsWith('.svelte')) &&
			!entry.endsWith('.test.ts') &&
			full !== SELF
		) {
			out.push(full);
		}
	}
	return out;
}

/// The error binding is read off the invoke's own destructure and the search
/// is for a rethrow of THAT name, not of any identifier. A window alone
/// false-positives: `disconnectIntegration` follows its invoke (bound as
/// `fnError`) with an ordinary PostgREST delete whose own `throw error;` is
/// perfectly correct and has nothing to do with this rule.
const INVOKE = /const\s*\{([^}]*)\}\s*=\s*await\s+supabase\.functions\.invoke\(\s*'([^']+)'/g;

/// `error` or `error: someName` inside the destructure.
function errorBinding(destructure: string): string | null {
	const m = /(?:^|,)\s*error\s*(?::\s*([A-Za-z_$][\w$]*))?\s*(?:,|$)/.exec(destructure);
	if (!m) return null;
	return m[1] ?? 'error';
}


function invokeSites(): { key: string; file: string; rethrows: boolean }[] {
	const sites: { key: string; file: string; rethrows: boolean }[] = [];
	for (const file of sourceFiles(SRC)) {
		const src = readFileSync(file, 'utf8');
		INVOKE.lastIndex = 0;
		let m: RegExpExecArray | null;
		while ((m = INVOKE.exec(src)) !== null) {
			const bound = errorBinding(m[1]);
			// The handling follows the call. 900 chars clears an intervening
			// guard — race-results-import reads the envelope off `context`
			// first and rethrows well below — without reaching the next
			// function; the identifier binding is what keeps it honest.
			const window = src.slice(m.index, m.index + 900);
			const base = file.slice(file.lastIndexOf('/') + 1);
			sites.push({
				key: `${base}::${m[2]}`,
				file: relative(SRC, file),
				rethrows:
					bound !== null &&
					new RegExp(`\\bthrow\\s+${bound}\\s*;`).test(window),
			});
		}
	}
	return sites;
}

test('the guard finds the call sites at all', () => {
	const sites = invokeSites();
	// A regex that matched nothing would make every assertion below vacuous.
	assert.ok(
		sites.length >= 8,
		`expected the invoke call sites to be found; got ${sites.length}`,
	);
});

test('no functions.invoke site rethrows supabase-js\'s error unexamined', () => {
	const offenders = invokeSites()
		.filter((s) => s.rethrows && !REDTHROW_EXEMPT.has(s.key))
		.map((s) => `${s.file} (${s.key})`);
	assert.deepEqual(
		offenders,
		[],
		'These rethrow the FunctionsHttpError as-is, so the caller gets "Edge Function ' +
			'returned a non-2xx status code" instead of the refusal. Unwrap it with ' +
			'core/edge_function_error.ts, or add the site to REDTHROW_EXEMPT with the ' +
			'reason nothing surfaces the message:\n  ' + offenders.join('\n  '),
	);
});

test('every exemption still names a site that rethrows', () => {
	const rethrowing = new Set(invokeSites().filter((s) => s.rethrows).map((s) => s.key));
	const stale = [...REDTHROW_EXEMPT.keys()].filter((k) => !rethrowing.has(k));
	assert.deepEqual(
		stale,
		[],
		`These exemptions no longer describe anything — the site was fixed or moved. ` +
			`Drop them: ${stale.join(', ')}`,
	);
});
