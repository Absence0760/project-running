/// Every rate-limit call site in the tree must be fail-closed.
///
/// `checkRateLimit` / `checkRateLimitTiered` default to fail-OPEN on an RPC
/// error, so the posture of a call site is decided by whether the author
/// remembered the fifth-or-sixth argument. Four sites had not — and they were
/// exactly the four whose work is an outbound call spending a resource that is
/// not ours (Strava's per-application budget, parkrun.org.uk's tolerance of our
/// egress IP, our RunSignUp / ChronoTrack / UltraSignup credentials), while the
/// nine cheap single-write sites were all guarded. Closed in decisions § 974;
/// this is what stops the shape coming back, on those four or on a tenth.
///
/// The rule is absolute rather than allowlisted on purpose: the RPC that fails
/// is `check_rate_limit` against the same database every one of these functions
/// must then write to, so letting the request through does not rescue it — it
/// only spends whatever the function spends before reaching its own failing
/// write. A caller that genuinely wants fail-open has to come here and say so.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/rate_limit_failclosed_guard.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const FUNCTIONS_DIR = new URL('../', import.meta.url).pathname;

/// The helper's own module declares the parameter and its default; reading it
/// as a call site would assert against the declaration rather than a caller.
const NOT_A_CALL_SITE = '_shared/rate_limit.ts';

function sourceFiles(): string[] {
  const out: string[] = [];
  const walk = (dir: string, prefix: string) => {
    for (const entry of Deno.readDirSync(dir)) {
      const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory) {
        walk(`${dir}${entry.name}/`, rel);
      } else if (entry.name.endsWith('.ts') && !entry.name.endsWith('.test.ts')) {
        out.push(rel);
      }
    }
  };
  walk(FUNCTIONS_DIR, '');
  return out.sort();
}

/// The argument text of the call starting at `open` (the index of its `(`).
/// Paren-counting rather than a regex: the argument list carries nested calls
/// (`await ipBucketKey(req)`) and an options object, and a non-greedy `\)` stops
/// at the first of them — which is how a guard reads `{ failClosed: true }` as
/// absent on a call that has it, or present on the call after it.
function callArgs(src: string, open: number): string | null {
  let depth = 0;
  let quote: string | null = null;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      if (c === '\\') i++;
      else if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      quote = c;
      continue;
    }
    if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return src.slice(open + 1, i);
    }
  }
  return null;
}

interface Site {
  file: string;
  args: string;
}

function callSites(): Site[] {
  const sites: Site[] = [];
  for (const file of sourceFiles()) {
    if (file === NOT_A_CALL_SITE) continue;
    const src = Deno.readTextFileSync(`${FUNCTIONS_DIR}${file}`);
    const re = /\bcheckRateLimit(?:Tiered)?\s*\(/g;
    for (const m of src.matchAll(re)) {
      const open = m.index! + m[0].length - 1;
      const args = callArgs(src, open);
      assert(args !== null, `${file}: unbalanced parentheses at a rate-limit call`);
      sites.push({ file, args: args! });
    }
  }
  return sites;
}

Deno.test('the guard reads real call sites, in more than one function', () => {
  const sites = callSites();
  // A vacuity floor. An empty walk, a broken path or a regex that stopped
  // matching all read as "every call site is fail-closed"; the count only ever
  // grows, so a floor below today's is a floor a refactor can still clear.
  assert(sites.length >= 12, `only ${sites.length} rate-limit call sites found`);
  const files = new Set(sites.map((s) => s.file));
  assert(files.size >= 8, `call sites found in only ${files.size} files`);
  // The names must be reachable: a site whose args are empty would satisfy the
  // absence test below without carrying an argument at all.
  for (const s of sites) {
    assert(s.args.trim().length > 0, `${s.file}: a rate-limit call with no arguments`);
  }
});

Deno.test('every rate-limit call site is fail-closed', () => {
  const open = callSites().filter((s) => !/failClosed:\s*true/.test(s.args));
  assertEquals(
    open.map((s) => s.file),
    [],
    'these rate-limit call sites fall open on an RPC error; pass { failClosed: true }',
  );
});

Deno.test('the four importers that spend a third-party resource are among them', () => {
  // Named explicitly, because the rule above is satisfied by a tree that has
  // lost these four functions entirely — and they are the reason it exists.
  const byFile = new Map<string, Site[]>();
  for (const s of callSites()) {
    byFile.set(s.file, [...(byFile.get(s.file) ?? []), s]);
  }
  for (
    const file of [
      'strava-import/index.ts',
      'parkrun-import/index.ts',
      'race-results-import/index.ts',
      'race-listings-sync/index.ts',
    ]
  ) {
    const sites = byFile.get(file);
    assert(sites && sites.length > 0, `${file} has no rate-limit call site`);
    for (const s of sites!) {
      assert(/failClosed:\s*true/.test(s.args), `${file}: a rate-limit call falls open`);
    }
  }
});
