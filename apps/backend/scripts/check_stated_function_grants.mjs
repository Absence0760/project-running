#!/usr/bin/env node
// Fail loudly when a routine some tree CALLS holds its EXECUTE from the image's
// default privileges rather than from a statement in this repo.
//
// The mechanism is the one 20270707000001 (decisions § 1098) records. What a
// fresh function in `public` arrives with depends on the Supabase image:
//
//   * Supabase Cloud, and CI (`supabase/setup-cli` pinned to 2.84.2), carry an
//     `alter default privileges` for `postgres` handing anon, authenticated and
//     service_role an EXECUTE entry BY NAME. A later `revoke ... from public`
//     removes nothing, and the ACL admits all three whether or not any
//     migration said so.
//   * The workstation CLI (2.109.1) starts a function at `proacl` NULL, the
//     built-in owner+PUBLIC default, so the same revoke collapses the ACL to
//     `{postgres}` plus whatever a migration granted by name.
//
// That asymmetry is why `anon_execute_registry_test.sql`'s assertions (7)-(8)
// cannot do this job. They read the CATALOGUE, so on the image the PR gate runs
// they hold for every routine whether the grant was stated or inherited -- the
// registry is vacuous exactly where it matters. This guard reads the migration
// TEXT instead: it replays create / drop / grant / revoke in version order and
// derives the ACL the repo STATES, which is the same answer on every image and
// needs no database at all.
//
// -- What it demands, and where the demand comes from -------------------------
// Two sources, and the derived one is much the larger:
//
//   1. DERIVED from the call sites. Every RPC name the client trees call must
//      carry a stated `authenticated` grant; every one the server trees call
//      must carry a stated `service_role` one. CALLER_TREES below is the whole
//      classification. Nothing is registered by hand, so a PR that adds a
//      caller for a routine whose grant no migration states fails on that PR
//      rather than the round after -- which is the point. Measured when this
//      guard was written: 92 RPC names across the web and Lambda trees and 46
//      across the two Dart ones, of which exactly one (`clip_track_for_user`,
//      whose grant 20270521_001 withdrew as a privacy-zone oracle) had no
//      stated `authenticated` grant; and 19 across the Edge Functions and the
//      Go worker, of which exactly one (`host_can_take_payment`, called by both
//      checkout functions on a service-role client) had no stated
//      `service_role` one. § 1098's own inventory, taken by hand, missed the
//      second -- its call sites put the name on the line after `.rpc(`.
//
//   2. REGISTERED, for a caller no source tree names. The rows come from the
//      `stated` table in
//      `apps/backend/supabase/tests/anon_execute_registry_test.sql` so the
//      pgtap suite and this guard read ONE registry: the suite proves the
//      catalogue matches on the image that can tell, this guard proves the
//      migration text says it on every image. `fundraiser_totals`'s
//      service_role caller is a pgtap file, which is exactly that case.
//
// `authenticated` is the bar for a client tree rather than "anon or
// authenticated" because PostgREST resolves the role from the caller's JWT: a
// signed-in reader of a public share page calls as `authenticated`, so a
// routine granted only to `anon` refuses the majority of the callers a client
// tree has. Measured, no routine any client tree calls is anon-only today.
//
// `service_role` is the bar for a server tree even where the call happens to be
// on a user-JWT client. Over-demanding costs nothing there: service_role
// bypasses RLS by design and holds the underlying tables outright, so stating
// the grant confers no reach -- the point is that it be STATED rather than
// inherited from an image that may change.
//
// -- What it deliberately does not catch -------------------------------------
// A routine is keyed by its schema-qualified NAME, so two overloads of one name
// would share a verdict; there are none in `public` or `private` today
// (measured against the local catalogue, as
// check_migration_function_revoke_noop.mjs records for the same reason). It
// grades EXECUTE only -- table and column grants are
// check_migration_column_revoke_noop.mjs's business. It says nothing about
// whether a role SHOULD hold the grant, only that a caller's grant is stated;
// the withholding direction is that other guard's, and the catalogue state is
// `anon_execute_registry_test.sql`'s. `apps/mobile_ios/lib` is not scanned
// because it is byte-identical to `apps/mobile_android/lib` by invariant
// (decisions § 39), pinned by its own guard. And a Go RPC name assembled by
// string concatenation outside the one `SupabaseClient.rpc` helper would be
// missed; the helper's own callers all pass a literal, and a non-literal there
// is reported rather than skipped.
//
// It REFUSES rather than reporting clean when it cannot see: no migrations, no
// registry rows, a configured caller tree with no source files, an
// `alter default privileges ... on functions` (which would move the very
// default the replay assumes), or a call site whose callee it cannot read.
//
// Run locally: node apps/backend/scripts/check_stated_function_grants.mjs
// CI:  the `pgtap RLS suite` job in .github/workflows/ci.yml.
// Unit tests: node --test apps/backend/scripts/check_stated_function_grants.test.mjs

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { MIGRATIONS_DIR, parseVersion } from './check_migration_versions.mjs';
import { splitSqlStatements } from './sql_lex.mjs';

const REPO_ROOT = join(MIGRATIONS_DIR, '..', '..', '..', '..');

export const REGISTRY_FILE = join(
  MIGRATIONS_DIR,
  '..',
  'tests',
  'anon_execute_registry_test.sql',
);

/** @typedef {{ dir: string, role: string, kind: 'ts' | 'dart' | 'go' }} CallerTree */

/**
 * Every tree that reaches a `public` routine over PostgREST, and the database
 * role its calls arrive as. `kind` picks the call-site reader.
 * @type {readonly CallerTree[]}
 */
export const CALLER_TREES = [
  { dir: 'apps/web/src', role: 'authenticated', kind: 'ts' },
  { dir: 'apps/web/lambda', role: 'authenticated', kind: 'ts' },
  { dir: 'packages/api_client/lib', role: 'authenticated', kind: 'dart' },
  { dir: 'apps/mobile_android/lib', role: 'authenticated', kind: 'dart' },
  { dir: 'apps/backend/supabase/functions', role: 'service_role', kind: 'ts' },
  { dir: 'apps/job_worker', role: 'service_role', kind: 'go' },
];

const SOURCE_SUFFIX = { ts: ['.ts'], dart: ['.dart'], go: ['.go'] };

const CREATE_ROUTINE =
  /^create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+([a-z_0-9."]+)\s*\(/i;
const DROP_ROUTINE = /^drop\s+(?:function|procedure|routine)\s+(?:if\s+exists\s+)?([a-z_0-9."]+)/i;
const GRANT_OR_REVOKE =
  /^(grant|revoke)\s+(?:grant\s+option\s+for\s+)?(.+?)\s+on\s+(all\s+(?:functions|procedures|routines)\s+in\s+schema|function|procedure|routine)\s+(.+?)\s+(?:to|from)\s+(.+)$/is;
const ALTER_DEFAULT_ROUTINES =
  /^alter\s+default\s+privileges\b.*\bon\s+(?:functions|procedures|routines)\b/is;

/**
 * `public.f` / `"f"` / `f(uuid, text)` all key as `public.f`.
 * @param {string} name
 * @returns {string}
 */
export function qualify(name) {
  const bare = name.replace(/\(.*$/s, '').trim().replace(/"/g, '').toLowerCase();
  return bare.includes('.') ? bare : `public.${bare}`;
}

/**
 * Split a comma-separated list, keeping a routine's argument list intact.
 * @param {string} text
 * @returns {string[]}
 */
function splitList(text) {
  return text
    .split(/,(?![^(]*\))/)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

/**
 * Replay the migration set and return, per routine, the roles this repo STATES
 * an EXECUTE grant for. A routine present with an empty set was created and
 * never granted to anyone by name; a routine absent was never created (or was
 * dropped and not recreated).
 * @param {{ filename: string, sql: string }[]} migrations any order; sorted here
 * @returns {{ scanned: string[], stated: Map<string, Set<string>>,
 *   unmodelled: { filename: string, statement: string }[] }}
 */
export function statedGrants(migrations) {
  const ordered = [...migrations].sort((a, b) => {
    const byVersion = (parseVersion(a.filename) ?? '').localeCompare(
      parseVersion(b.filename) ?? '',
    );
    return byVersion !== 0 ? byVersion : a.filename.localeCompare(b.filename);
  });

  /** @type {Map<string, Set<string>>} */
  const stated = new Map();
  /** @type {{ filename: string, statement: string }[]} */
  const unmodelled = [];
  /** @type {string[]} */
  const scanned = [];

  for (const { filename, sql } of ordered) {
    scanned.push(filename);
    for (const raw of splitSqlStatements(sql)) {
      const statement = raw.replace(/\s+/g, ' ').trim();

      if (ALTER_DEFAULT_ROUTINES.test(statement)) {
        unmodelled.push({ filename, statement });
        continue;
      }

      const created = CREATE_ROUTINE.exec(statement);
      if (created) {
        const routine = qualify(created[1]);
        if (!stated.has(routine)) stated.set(routine, new Set());
        continue;
      }
      const dropped = DROP_ROUTINE.exec(statement);
      if (dropped) {
        stated.delete(qualify(dropped[1]));
        continue;
      }

      const match = GRANT_OR_REVOKE.exec(statement);
      if (!match) continue;
      const [, rawVerb, privilegeClause, objectKind, target, roleClause] = match;
      if (!/^(?:all|execute)\b/i.test(privilegeClause.trim())) continue;
      const grant = rawVerb.toLowerCase() === 'grant';

      const bulk = /^all\b/i.test(objectKind.trim());
      const schemas = bulk
        ? new Set(splitList(target).map((s) => s.replace(/"/g, '').toLowerCase()))
        : null;
      const routines = schemas
        ? [...stated.keys()].filter((name) => schemas.has(name.slice(0, name.indexOf('.'))))
        : splitList(target).map(qualify);
      const roles = splitList(roleClause).map((role) => role.replace(/"/g, '').toLowerCase());

      for (const routine of routines) {
        const held = stated.get(routine) ?? new Set();
        stated.set(routine, held);
        for (const role of roles) {
          // A PUBLIC grant is the image-dependent channel this guard exists to
          // discount: it is what the workstation image gives free and the CI
          // one does not, so it can never stand in for a stated role grant.
          if (role === 'public') continue;
          if (grant) held.add(role);
          else held.delete(role);
        }
      }
    }
  }

  return { scanned, stated, unmodelled };
}

/**
 * Count the top-level `( ... )` groups in a VALUES clause, ignoring parentheses
 * inside string literals. The tuple reader below is a regex, and a regex that
 * matches four rows out of five reports a clean registry while silently
 * dropping the fifth -- so the two counts are compared and a disagreement
 * refuses.
 * @param {string} values
 * @returns {number}
 */
function countTuples(values) {
  let tuples = 0;
  let depth = 0;
  let quoted = false;
  for (let i = 0; i < values.length; i += 1) {
    const char = values[i];
    if (quoted) {
      if (char !== "'") continue;
      if (values[i + 1] === "'") i += 1;
      else quoted = false;
      continue;
    }
    if (char === "'") quoted = true;
    else if (char === '(') {
      if (depth === 0) tuples += 1;
      depth += 1;
    } else if (char === ')') depth -= 1;
  }
  return tuples;
}

/**
 * Pull the `stated` registry out of the pgtap suite, so the two guards read one
 * table. Returns [] when the insert is not there or when the tuple reader and
 * the tuple count disagree, either of which the caller refuses on.
 *
 * The statement is taken from the SQL lexer rather than by matching to the next
 * `;`: a `why` string containing a semicolon (the first row's does) truncates a
 * naive match after one tuple, which reads as a one-row registry rather than as
 * a parse failure.
 * @param {string} sql the contents of anon_execute_registry_test.sql
 * @returns {{ fn: string, args: string, caller: string }[]}
 */
export function parseRegistry(sql) {
  const statement = splitSqlStatements(sql).find((s) => /^\s*insert\s+into\s+stated\b/i.test(s));
  if (statement === undefined) return [];
  const values = /\bvalues\b(.+)$/is.exec(statement);
  if (values === null) return [];
  /** @type {{ fn: string, args: string, caller: string }[]} */
  const rows = [];
  const tuple = /\(\s*'([a-z_0-9]+)'\s*,\s*'([^']*)'\s*,\s*'([a-z_0-9]+)'\s*,/gi;
  let hit;
  while ((hit = tuple.exec(values[1])) !== null) {
    rows.push({ fn: hit[1], args: hit[2], caller: hit[3].toLowerCase() });
  }
  return rows.length === countTuples(values[1]) ? rows : [];
}

/**
 * Blank out every comment, keeping the file's length so an offset still points
 * where it did. TypeScript, Dart and Go share `//` and nested-free block
 * comments, and all three quote with `'`, `"` and backticks -- enough to keep a
 * `//` inside a URL literal from eating the rest of the line, which is what a
 * bare regex would do. A commented-out call is not a call site, and a comment
 * sitting BETWEEN `.rpc(` and its name (there is one, in data.ts) must not hide
 * the name; blanking both directions at once is why this runs first.
 * @param {string} source
 * @returns {string}
 */
export function blankComments(source) {
  let out = '';
  let i = 0;
  while (i < source.length) {
    const two = source.slice(i, i + 2);
    if (two === '//') {
      const end = source.indexOf('\n', i);
      const stop = end === -1 ? source.length : end;
      out += ' '.repeat(stop - i);
      i = stop;
      continue;
    }
    if (two === '/*') {
      const end = source.indexOf('*/', i + 2);
      const stop = end === -1 ? source.length : end + 2;
      out += source.slice(i, stop).replace(/[^\n]/g, ' ');
      i = stop;
      continue;
    }
    const quote = source[i];
    if (quote === "'" || quote === '"' || quote === '`') {
      let j = i + 1;
      while (j < source.length && source[j] !== quote) {
        if (source[j] === '\\') j += 1;
        if (source[j] === '\n' && quote !== '`') break;
        j += 1;
      }
      const stop = Math.min(j + 1, source.length);
      out += source.slice(i, stop);
      i = stop;
      continue;
    }
    out += source[i];
    i += 1;
  }
  return out;
}

/**
 * Read the quoted routine name that follows `at`, skipping whitespace. Returns
 * null when what follows is not a bare quoted identifier -- a variable, a
 * template string, a concatenation.
 * @param {string} source comment-blanked
 * @param {number} at index just past the opening `(`
 * @returns {string | null}
 */
function literalAt(source, at) {
  let i = at;
  while (i < source.length && /\s/.test(source[i])) i += 1;
  const quote = source[i];
  if (quote !== "'" && quote !== '"') return null;
  const end = source.indexOf(quote, i + 1);
  if (end === -1) return null;
  const name = source.slice(i + 1, end);
  return /^[a-z_0-9]+$/.test(name) ? name : null;
}

/**
 * Every RPC name a source file names, plus every call site whose callee it
 * could not read. A call whose name is not a literal is reported, never
 * skipped -- an unreadable callee is a routine this guard would otherwise vouch
 * for without having seen it.
 * @param {string} rawSource
 * @param {'ts' | 'dart' | 'go'} kind
 * @returns {{ names: string[], unreadable: string[] }}
 */
export function readCallSites(rawSource, kind) {
  const source = blankComments(rawSource);
  /** @type {string[]} */
  const names = [];
  /** @type {string[]} */
  const unreadable = [];

  // The only two ways a name reaches PostgREST from the Go worker: the
  // `SupabaseClient.rpc` helper, and a literal `/rest/v1/rpc/<name>` URL.
  const opener = kind === 'go' ? /\brpc\(\s*ctx\s*,/g : /\.rpc\(/g;
  for (const hit of source.matchAll(opener)) {
    const at = (hit.index ?? 0) + hit[0].length;
    const name = literalAt(source, at);
    if (name !== null) names.push(name);
    else {
      unreadable.push(
        rawSource
          .slice(hit.index ?? 0, (hit.index ?? 0) + 80)
          .replace(/\s+/g, ' ')
          .trim(),
      );
    }
  }
  if (kind === 'go') {
    for (const url of source.matchAll(/\/rest\/v1\/rpc\/([a-z_0-9]+)/g)) names.push(url[1]);
  }
  return { names, unreadable };
}

/**
 * @param {string} dir
 * @param {string[]} suffixes
 * @returns {string[]} absolute paths, test files excluded
 */
function sourceFiles(dir, suffixes) {
  /** @type {string[]} */
  const found = [];
  /** @param {string} at */
  const walk = (at) => {
    for (const entry of readdirSync(at, { withFileTypes: true })) {
      const path = join(at, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === 'node_modules' || entry.name === '.svelte-kit') continue;
        walk(path);
        continue;
      }
      if (!suffixes.some((suffix) => entry.name.endsWith(suffix))) continue;
      // A test naming an RPC in a source-grep assertion is not a call site.
      if (/(?:\.test|_test)\.[a-z]+$/.test(entry.name)) continue;
      found.push(path);
    }
  };
  try {
    if (!statSync(dir).isDirectory()) return [];
  } catch {
    return [];
  }
  walk(dir);
  return found;
}

/**
 * @param {string} root repo root
 * @param {readonly CallerTree[]} trees
 * @returns {{ demands: Map<string, { role: string, sites: string[] }>,
 *   emptyTrees: string[], unreadable: { file: string, snippet: string }[] }}
 */
export function scanCallers(root, trees) {
  /** @type {Map<string, { role: string, sites: string[] }>} */
  const demands = new Map();
  /** @type {string[]} */
  const emptyTrees = [];
  /** @type {{ file: string, snippet: string }[]} */
  const unreadable = [];

  for (const tree of trees) {
    const files = sourceFiles(join(root, tree.dir), SOURCE_SUFFIX[tree.kind]);
    if (files.length === 0) {
      emptyTrees.push(tree.dir);
      continue;
    }
    for (const file of files) {
      const read = readCallSites(readFileSync(file, 'utf8'), tree.kind);
      const shown = relative(root, file).split(sep).join('/');
      for (const snippet of read.unreadable) unreadable.push({ file: shown, snippet });
      for (const name of read.names) {
        const key = `${qualify(name)} ${tree.role}`;
        const seen = demands.get(key) ?? { role: tree.role, sites: [] };
        if (!seen.sites.includes(shown)) seen.sites.push(shown);
        demands.set(key, seen);
      }
    }
  }
  return { demands, emptyTrees, unreadable };
}

/**
 * @param {{ migrations: { filename: string, sql: string }[], registrySql: string,
 *   root: string, trees?: readonly CallerTree[] }} input
 * @returns {{ scanned: string[], registry: { fn: string, args: string, caller: string }[],
 *   unmodelled: { filename: string, statement: string }[], emptyTrees: string[],
 *   unreadable: { file: string, snippet: string }[],
 *   violations: { routine: string, role: string, source: string,
 *     held: string[] | null }[] }} `held` is null when no migration creates the
 *   routine at all, which is a different failure from an unstated grant.
 */
export function audit({ migrations, registrySql, root, trees = CALLER_TREES }) {
  const { scanned, stated, unmodelled } = statedGrants(migrations);
  const registry = parseRegistry(registrySql);
  const { demands, emptyTrees, unreadable } = scanCallers(root, trees);

  /** @type {Map<string, { routine: string, role: string, source: string }>} */
  const wanted = new Map();
  for (const [key, { role, sites }] of demands) {
    const listed = sites.slice(0, 3).join(', ');
    const more = sites.length > 3 ? ` and ${sites.length - 3} more` : '';
    wanted.set(key, {
      routine: key.slice(0, key.indexOf(' ')),
      role,
      source: `called from ${listed}${more}`,
    });
  }
  for (const row of registry) {
    const routine = qualify(row.fn);
    const key = `${routine} ${row.caller}`;
    if (wanted.has(key)) continue;
    wanted.set(key, {
      routine,
      role: row.caller,
      source: 'registered in apps/backend/supabase/tests/anon_execute_registry_test.sql',
    });
  }

  /** @type {{ routine: string, role: string, source: string, held: string[] | null }[]} */
  const violations = [];
  const ordered = [...wanted.values()].sort(
    (a, b) => a.routine.localeCompare(b.routine) || a.role.localeCompare(b.role),
  );
  for (const { routine, role, source } of ordered) {
    const held = stated.get(routine);
    if (held !== undefined && held.has(role)) continue;
    violations.push({
      routine,
      role,
      source,
      held: held === undefined ? null : [...held].sort(),
    });
  }

  return { scanned, registry, unmodelled, emptyTrees, unreadable, violations };
}

function main() {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((filename) => filename.endsWith('.sql'))
    .map((filename) => ({ filename, sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8') }));

  const result = audit({
    migrations,
    registrySql: readFileSync(REGISTRY_FILE, 'utf8'),
    root: REPO_ROOT,
  });

  let refused = false;

  if (result.scanned.length === 0) {
    console.error(
      `::error::The stated-grant scan read no migrations at all from ${MIGRATIONS_DIR}, so a clean ` +
        `report says nothing about the tree. Either the directory moved or the .sql filter stopped ` +
        `matching.`,
    );
    refused = true;
  }
  if (result.registry.length === 0) {
    console.error(
      `::error file=apps/backend/supabase/tests/anon_execute_registry_test.sql::No rows parsed out ` +
        `of the "stated" registry in anon_execute_registry_test.sql. That table is this guard's ` +
        `hand-declared half, so an empty parse silently drops every pair no source tree names, ` +
        `including fundraiser_totals, whose only service_role caller is a pgtap file. Either the ` +
        `insert moved or its shape changed; teach parseRegistry in ` +
        `apps/backend/scripts/check_stated_function_grants.mjs about the new one.`,
    );
    refused = true;
  }
  for (const dir of result.emptyTrees) {
    console.error(
      `::error::The caller tree "${dir}" holds no source files of its kind, so every RPC it calls ` +
        `is now demanded by nothing. Fix the path in CALLER_TREES in ` +
        `apps/backend/scripts/check_stated_function_grants.mjs, or drop the tree from the list if ` +
        `it no longer reaches PostgREST.`,
    );
    refused = true;
  }
  for (const { filename, statement } of result.unmodelled) {
    console.error(
      `::error file=apps/backend/supabase/migrations/${filename}::${filename} changes the DEFAULT ` +
        `privileges on routines, which is the premise this guard replays against - it derives the ` +
        `ACL this repo STATES on the assumption that nothing but an explicit grant puts a role ` +
        `there. The statement is "${statement}". Teach the replay in ` +
        `apps/backend/scripts/check_stated_function_grants.mjs about it rather than letting it ` +
        `keep issuing verdicts under a premise the tree has changed.`,
    );
    refused = true;
  }
  for (const { file, snippet } of result.unreadable) {
    console.error(
      `::error file=${file}::${file} calls an RPC whose name this guard cannot read - "${snippet}". ` +
        `A callee it cannot see is a routine it would otherwise vouch for without having looked, so ` +
        `it refuses instead. Pass the routine name as a string literal at the call site, or teach ` +
        `readCallSites in apps/backend/scripts/check_stated_function_grants.mjs the shape.`,
    );
    refused = true;
  }

  for (const { routine, role, source, held } of result.violations) {
    const bare = routine.slice(routine.indexOf('.') + 1);
    if (held === null) {
      console.error(
        `::error::"${routine}" is ${source}, and no migration in this tree creates it. That is not ` +
          `an image difference - the call resolves nowhere, so PostgREST answers PGRST202 on every ` +
          `deployment. Either the routine was never written (the caller is dead code, or the ` +
          `feature is a multi-statement path that never became an RPC) or it was dropped and the ` +
          `caller outlived it. Delete the call site or add the migration.`,
      );
      continue;
    }
    const holds = held.length === 0 ? 'no role grant at all' : held.map((r) => `"${r}"`).join(', ');
    console.error(
      `::error::"${routine}" is ${source}, but no migration grants EXECUTE on it to "${role}" - ` +
        `the repo states ${holds}. On Supabase Cloud and CI's pinned 2.84.2 the call works anyway, ` +
        `because that image's default privileges hand every new function an entry for anon, ` +
        `authenticated and service_role by name; on an image that does not (the workstation's ` +
        `2.109.1, and anything Supabase ships next) the same call is a 42501. Add "grant execute ` +
        `on function public.${bare}(<args>) to ${role};" in a migration that says why - or, if the ` +
        `routine is deliberately withheld from that role, stop calling it from a tree that runs as ` +
        `one.`,
    );
  }

  if (refused || result.violations.length > 0) process.exit(1);
  console.log(
    `OK: ${result.scanned.length} migrations replayed; every routine the ${CALLER_TREES.length} ` +
      `caller trees reach, and every one of the ${result.registry.length} registered pairs, holds ` +
      `EXECUTE through a grant this repo states.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
