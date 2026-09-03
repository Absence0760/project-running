// Source hygiene across the Deno tier: what a log line may carry, and what
// a remote import may leave unpinned. The raw-error scan covers both server
// tiers — the rule is the same and so is the scanner, so the SvelteKit
// handlers are read here beside the Edge Functions rather than in a second
// copy of it.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripComments } from './core/strip_comments';

const __dirname = dirname(fileURLToPath(import.meta.url));

function collectEdgeFunctionIndexes(efDir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(efDir)) {
    if (name.startsWith('_')) continue; // _shared, etc.
    const candidate = resolve(efDir, name, 'index.ts');
    try {
      readFileSync(candidate);
      out.push(candidate);
    } catch {
      /* not a function dir (e.g. shared helpers); skip */
    }
  }
  return out;
}

function lastTopLevelArg(argText: string): string {
  // Walk forward, tracking nesting depth + string state. Return the
  // tail after the last top-level comma. Handles `(`, `[`, `{`,
  // template `${…}`, and single/double/backtick strings.
  let depth = 0;
  let lastCommaIdx = -1;
  let i = 0;
  while (i < argText.length) {
    const c = argText[i];
    if (c === '"' || c === "'" || c === '`') {
      const quote = c;
      i++;
      while (i < argText.length && argText[i] !== quote) {
        if (argText[i] === '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === ',' && depth === 0) lastCommaIdx = i;
    i++;
  }
  return lastCommaIdx === -1 ? argText : argText.slice(lastCommaIdx + 1);
}

function looksLikeRawErrorArg(arg: string): boolean {
  // Both callers hand this an argument taken from source already blanked by
  // `core/strip_comments`, so a comment cannot reach it. Two shapes count —
  // a bare identifier whose name signals an error (`err`, `insertErr`), and
  // a member access landing on `.error` (`proRes.error`, `lookup?.error`),
  // which is how every PostgREST result destructures.
  const stripped = arg.trim();
  if (stripped.length === 0) return false;
  // Accept: anything containing `.message` / `?.message` / `String(` /
  // `instanceof Error` / `JSON.stringify` / object-literal `{` / array
  // literal `[` / string literal / number / template literal.
  if (
    stripped.includes('.message') ||
    stripped.includes('?.message') ||
    stripped.startsWith('String(') ||
    stripped.includes('instanceof Error') ||
    stripped.includes('JSON.stringify') ||
    stripped.startsWith('{') ||
    stripped.startsWith('[') ||
    stripped.startsWith('"') ||
    stripped.startsWith("'") ||
    stripped.startsWith('`') ||
    /^-?\d/.test(stripped)
  ) {
    return false;
  }
  // What's left is a bare identifier (or expression without any of the
  // accepted scrubbers). Flag it if the name suggests an error value.
  if (/^[a-zA-Z_$][\w$]*$/.test(stripped) && /(err|Err|error|Error)$/.test(stripped)) {
    return true;
  }
  // A member access landing on `.error` / `.err`, optional-chained or
  // not. `const proRes = await supabase.rpc(...)` then
  // `console.error('…', proRes.error)` is the exact shape three
  // `/api/routes` handlers shipped.
  return /^[a-zA-Z_$][\w$]*(\??\.[a-zA-Z_$][\w$]*)*\??\.(error|err)$/.test(stripped);
}

// ─── audit:deps May 2026 closeouts ───────────────────────────────────
// Three source-level dep-hygiene pins so version drift across Edge
// Functions can't silently accumulate. Each one walks every EF
// `index.ts` + `_shared/*.ts` as text and asserts a property the
// audit explicitly called out.

test('Edge Functions do not log raw PostgrestError objects', () => {
  // Reason: PostgrestError objects carry `.message`, `.details`,
  // `.hint`, and `.code`. The `details` / `hint` fields can include
  // partial column values, constraint names, or row fragments. The
  // Supabase function-log aggregator is accessible to project
  // members (and exportable in some billing tiers), so a raw-object
  // log is schema/credential exposure even when the response to the
  // caller is clean. Pinned because audit:edge-functions 2026-05-25
  // caught four sites that had regressed from the .message pattern
  // used elsewhere in the same codebase.
  //
  // The check is conservative: it bans `console.error(..., name)` /
  // `console.error(..., nameErr)` where the trailing argument is a
  // bare identifier likely to be an error object. Allowed shapes:
  //   - `.message` / `?.message` accesses
  //   - `String(...)` wrappers
  //   - `e instanceof Error ? e.message : String(e)` ternaries
  //   - object literals (e.g. `{ status: ... }`)
  //   - string literals
  // — any of which scrubs the structured fields the leak relies on.
  const efDir = resolve(__dirname, '../../../backend/supabase/functions');
  const indexes = collectEdgeFunctionIndexes(efDir);
  assert.ok(
    indexes.length >= 6,
    `Expected at least 6 Edge Function index.ts files under ${efDir}, ` +
      `found ${indexes.length}. Has the directory layout moved?`,
  );

  const offenders: Array<{ path: string; line: number; call: string }> = [];
  // Match `console.error( … )` with a balanced-paren scan inside.
  const callRe = /console\.error\s*\(/g;
  for (const path of indexes) {
    const source = stripComments(readFileSync(path, 'utf-8'));
    let m: RegExpExecArray | null;
    while ((m = callRe.exec(source)) !== null) {
      const start = m.index + m[0].length;
      // Find the matching closing paren.
      let depth = 1;
      let i = start;
      while (depth > 0 && i < source.length) {
        const c = source[i];
        if (c === '(') depth++;
        else if (c === ')') depth--;
        i++;
      }
      const argText = source.slice(start, i - 1);
      // Split top-level by comma — only need the LAST arg (the error
      // value); commas inside string literals / template literals
      // are rare in console.error calls and over-counting just makes
      // the assertion stricter (false-positive direction is safe).
      const lastArg = lastTopLevelArg(argText).trim();
      if (looksLikeRawErrorArg(lastArg)) {
        const lineNo = source.slice(0, m.index).split('\n').length;
        offenders.push({ path, line: lineNo, call: lastArg });
      }
    }
  }

  assert.strictEqual(
    offenders.length,
    0,
    'Edge Functions must not log raw error objects as the last arg ' +
      'of console.error — wrap with `.message`, `String(...)`, or ' +
      'the `e instanceof Error ? e.message : String(e)` pattern.\n' +
      `Offenders:\n${offenders.map((o) => `  ${o.path}:${o.line} → console.error(…, ${o.call})`).join('\n')}`,
  );
});

test('web server handlers do not log raw PostgrestError objects', () => {
  // Same leak, second tier. The Edge Function guard above globbed only
  // `supabase/functions/*/index.ts`, so the SvelteKit server surface —
  // which runs the same PostgREST calls against the same rows and logs
  // into the same CloudWatch group — was never covered. Three
  // `/api/routes` handlers were logging `proRes.error` whole while
  // `supabaseErrorFields` sat one import away (issue #734).
  //
  // Roots are the server handlers, not the whole app: the `+server.ts`
  // route entry points plus the `lib/` modules they delegate to. Client
  // components are out of scope — their console lands in the visitor's
  // own devtools, not a shared aggregator.
  const roots = [
    resolve(__dirname, '..', 'routes', 'api'),
    resolve(__dirname, 'routes'),
    resolve(__dirname, 'coach'),
  ];

  const tsFiles: string[] = [];
  const collectTs = (dir: string): void => {
    for (const name of readdirSync(dir)) {
      if (name.startsWith('.')) continue;
      const full = resolve(dir, name);
      try {
        readdirSync(full);
        collectTs(full);
      } catch {
        if (full.endsWith('.ts') && !full.endsWith('.test.ts')) tsFiles.push(full);
      }
    }
  };
  for (const root of roots) collectTs(root);
  assert.ok(
    tsFiles.length >= 10,
    `Expected ≥10 server .ts files across ${roots.join(', ')}, found ${tsFiles.length}. ` +
      'Has the directory layout moved?',
  );

  const offenders: Array<{ path: string; line: number; call: string }> = [];
  const callRe = /console\.error\s*\(/g;
  for (const path of tsFiles) {
    const source = stripComments(readFileSync(path, 'utf-8'));
    let m: RegExpExecArray | null;
    while ((m = callRe.exec(source)) !== null) {
      const start = m.index + m[0].length;
      let depth = 1;
      let i = start;
      while (depth > 0 && i < source.length) {
        const c = source[i];
        if (c === '(') depth++;
        else if (c === ')') depth--;
        i++;
      }
      const lastArg = lastTopLevelArg(source.slice(start, i - 1)).trim();
      if (looksLikeRawErrorArg(lastArg)) {
        offenders.push({
          path,
          line: source.slice(0, m.index).split('\n').length,
          call: lastArg,
        });
      }
    }
  }

  assert.strictEqual(
    offenders.length,
    0,
    'Web server handlers must not log a raw Supabase/PostgREST error as the ' +
      'last arg of console.error — `.details` / `.hint` echo row fragments. ' +
      'Route it through `supabaseErrorFields()` from lib/core/supabase_error.\n' +
      `Offenders:\n${offenders.map((o) => `  ${o.path}:${o.line} → console.error(…, ${o.call})`).join('\n')}`,
  );
});

test('every Deno import in Edge Functions has a version pin', () => {
	// Reason: Deno fetches at module-resolution time, so an unpinned
	// `https://esm.sh/x` or `https://deno.land/std/...` import would
	// silently pull a different version on every cold start. The
	// audit:deps May 2026 sweep confirmed every import was pinned
	// today; this pin keeps it that way. Catches a future "let's see
	// what the latest version does" experiment that ships without a
	// version suffix.
	const efDir = resolve(__dirname, '../../../backend/supabase/functions');
	const offenders: Array<{ file: string; line: number; url: string }> = [];
	const collectTs = (dir: string, out: string[]): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith('.')) continue;
			const full = resolve(dir, name);
			try {
				const entries = readdirSync(full);
				// It's a directory — recurse.
				collectTs(full, out);
				void entries;
			} catch {
				// Not a directory — check if it's a .ts file.
				if (full.endsWith('.ts')) out.push(full);
			}
		}
	};
	const tsFiles: string[] = [];
	collectTs(efDir, tsFiles);
	assert.ok(tsFiles.length >= 8, `Expected ≥8 .ts files under ${efDir}, found ${tsFiles.length}.`);
	// Pattern: `from 'https://...'` — flag if no @version suffix appears
	// before the next slash or quote.
	const importRe = /from\s+['"](https:\/\/[^'"]+)['"]/g;
	for (const path of tsFiles) {
		const source = readFileSync(path, 'utf-8');
		let m: RegExpExecArray | null;
		while ((m = importRe.exec(source)) !== null) {
			const url = m[1];
			// Acceptable shapes: ...@x.y.z/..., ...@x.y.z, ...@vx.y.z/...,
			// ...@<sha>/...
			// Anything without an @ before the next / or end is unpinned.
			// `v` prefix is common on deno.land/x/ (e.g. zipjs@v2.7.45),
			// SHA pins are 7-40 hex chars. Loose match covers both.
			const host = url.replace(/^https:\/\//, '').split('/')[0];
			const path_after_host = url.replace(/^https:\/\/[^/]+/, '');
			const hasVersionPin = /@v?[\d.]+/.test(url) || /@[0-9a-f]{7,40}\b/.test(url);
			if (!hasVersionPin) {
				const lineNo = source.slice(0, m.index).split('\n').length;
				offenders.push({ file: path, line: lineNo, url });
			}
			void host;
			void path_after_host;
		}
	}
	assert.strictEqual(
		offenders.length,
		0,
		'Every Deno import in Edge Functions must carry a @version pin. ' +
			'Unpinned imports re-resolve on every cold start — a supply-chain risk.\n' +
			`Offenders:\n${offenders.map((o) => `  ${o.file}:${o.line} → ${o.url}`).join('\n')}`,
	);
});

test('Edge Functions pin @supabase/supabase-js in lockstep', () => {
	// Reason: a partial bump where some EFs are at 2.105 and others at
	// 2.107 produces split behaviour on auth / RLS / Storage paths
	// (each major-line evolves its session handling differently).
	// Catches a one-off "I bumped this function but forgot the rest"
	// commit. The lockstep target lives in the production EFs; the
	// _shared/strava.ts + _shared/rate_limit.ts type-only imports must
	// match.
	const efDir = resolve(__dirname, '../../../backend/supabase/functions');
	const versions = new Set<string>();
	const sites: Array<{ file: string; line: number; ver: string }> = [];
	const collectTs = (dir: string, out: string[]): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith('.')) continue;
			const full = resolve(dir, name);
			try {
				readdirSync(full);
				collectTs(full, out);
			} catch {
				if (full.endsWith('.ts')) out.push(full);
			}
		}
	};
	const tsFiles: string[] = [];
	collectTs(efDir, tsFiles);
	const versionRe = /@supabase\/supabase-js@(\d+\.\d+\.\d+)/g;
	for (const path of tsFiles) {
		const source = readFileSync(path, 'utf-8');
		let m: RegExpExecArray | null;
		while ((m = versionRe.exec(source)) !== null) {
			versions.add(m[1]);
			const lineNo = source.slice(0, m.index).split('\n').length;
			sites.push({ file: path, line: lineNo, ver: m[1] });
		}
	}
	assert.ok(sites.length >= 8, `Expected ≥8 supabase-js pins, found ${sites.length}.`);
	assert.strictEqual(
		versions.size,
		1,
		'Every Edge Function must pin @supabase/supabase-js to the SAME version. ' +
			`Found ${versions.size} distinct versions: ${[...versions].join(', ')}.\n` +
			`Sites:\n${sites.map((s) => `  ${s.file}:${s.line} → ${s.ver}`).join('\n')}`,
	);
});

test('Edge Functions use Deno.serve, not std http/server.ts', () => {
	// Reason: `std@0.177.0/http/server.ts` was the pre-Deno-1.35 way
	// to start an HTTP server. Since 1.35 the built-in `Deno.serve`
	// is the supported entry point — no supply-chain hop, no version
	// drift between prod (0.177) and tests (0.224) that we had before
	// the audit:deps May 2026 sweep. A future "let's restore the
	// import" change would re-introduce the drift; pin it out.
	const efDir = resolve(__dirname, '../../../backend/supabase/functions');
	const offenders: Array<{ file: string; line: number }> = [];
	const collectTs = (dir: string, out: string[]): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith('.')) continue;
			const full = resolve(dir, name);
			try {
				readdirSync(full);
				collectTs(full, out);
			} catch {
				if (full.endsWith('.ts') && !full.endsWith('.test.ts')) out.push(full);
			}
		}
	};
	const tsFiles: string[] = [];
	collectTs(efDir, tsFiles);
	const stdServeRe = /from\s+['"]https:\/\/deno\.land\/std@[\d.]+\/http\/server\.ts['"]/g;
	for (const path of tsFiles) {
		const source = readFileSync(path, 'utf-8');
		let m: RegExpExecArray | null;
		while ((m = stdServeRe.exec(source)) !== null) {
			const lineNo = source.slice(0, m.index).split('\n').length;
			offenders.push({ file: path, line: lineNo });
		}
	}
	assert.strictEqual(
		offenders.length,
		0,
		'Edge Function source files (non-test) must NOT import `serve` from std/http — use built-in `Deno.serve` instead.\n' +
			`Offenders:\n${offenders.map((o) => `  ${o.file}:${o.line}`).join('\n')}`,
	);
});

// ─── audit:cost-controls May 2026 closeouts ──────────────────────────
// Six source-level pins on the Terraform IaC so cost-control regressions
// fail CI rather than waiting for the bill at end of month. Each test
// reads infra/* as text and asserts a property that the audit explicitly
// called out.
