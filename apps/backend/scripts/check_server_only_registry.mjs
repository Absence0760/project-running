#!/usr/bin/env node
// Fail loudly when the `server_only` fixture in
// `apps/backend/supabase/tests/anon_execute_contract_test.sql` stops naming
// every `public` routine this repo STATES is withheld from `authenticated`.
//
// That fixture is the subject of assertions (5) and (6) in the pgtap file: (5)
// says no routine it names is executable by a signed-in account, (6) says
// service_role still holds the ones it was kept for. Both are catalogue reads,
// and both are exactly as complete as the list — a routine the fixture omits
// is a routine nothing asserts anything about. It was hand-kept, and it had
// drifted: 42 non-trigger `public` routines carry a revoke naming
// `authenticated`, the fixture listed 26, and two of the sixteen missing
// (`enqueue_safety_overdue_emails`, `sweep_challenge_completions`) were in the
// very cron family the fixture is the positive control for
// ([decisions § 1182]'s class, a list that vouches for what it names and is
// silent about what it omits).
//
// ── Why this is a script and not a longer fixture ──────────────────────────
// A longer fixture drifts again on the next lockdown migration. What does not
// drift is a DERIVATION — but it has to be derived from a different source
// than the one the assertion grades, or the assertion becomes vacuous by
// construction. Deriving the family from `pg_proc.proacl` ("every routine
// authenticated cannot execute") would make (5) a tautology: it would assert
// that routines without the privilege do not have the privilege.
//
// So the family is derived from the migration TEXT, the same replay
// `check_stated_function_grants.mjs` uses, and the pgtap file grades it
// against the CATALOGUE. Two sources, and the claim between them is real: the
// repo said it revoked this, and the database agrees it is revoked. A
// `drop function` + `create function` that silently re-opened one is caught by
// the pgtap side; a lockdown migration that never reaches the fixture is
// caught here.
//
// `keeps_service_role` is derived the same way, from the end state of the
// replay, so (6) is a claim about a STATED grant rather than about whichever
// default the running image happens to hand out. That matters: on the CI image
// (`supabase/setup-cli` 2.84.2) a fresh routine arrives with a service_role
// EXECUTE entry by name, so a fixture row marked `true` on the strength of a
// catalogue reading there would say nothing at all.
//
// ── What is in the family ─────────────────────────────────────────────────
// A `public` routine is in it when some migration writes an EXECUTE (or ALL)
// revoke naming `authenticated` for it, AND the replay's end state carries no
// stated `authenticated` grant — so a revoke a later migration deliberately
// undid drops out rather than sitting in the fixture as a false claim.
//
// Trigger-returning routines are excluded, because the pgtap file excludes
// them from (1), (2) and (5) and asserts that exclusion in (4): Postgres
// refuses a direct call with 0A000 before privileges are consulted, so no
// grant makes one reachable. Return type is read from the routine's own
// `create` statement, and a routine whose create statement this guard cannot
// find REFUSES rather than being assumed one way or the other.
//
// ── What it deliberately does not catch ───────────────────────────────────
// It grades the STATEMENT, exactly as its two sibling guards do. A cron
// routine whose migration simply forgot `authenticated` is not in the family
// and so is not demanded here — nothing in the repo states it should be
// withheld. That gap is closed on the other side, by the pgtap file's
// cron-schedule assertion, which derives its population from `cron.job` and
// therefore cannot be defeated by a migration that says nothing.
//
// Run locally: node apps/backend/scripts/check_server_only_registry.mjs
// Unit tests:  node --test apps/backend/scripts/check_server_only_registry.test.mjs

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { MIGRATIONS_DIR, parseVersion } from './check_migration_versions.mjs';
import { splitSqlStatements } from './sql_lex.mjs';
import { qualify, statedGrants } from './check_stated_function_grants.mjs';

export const SUITE_FILE = join(
  MIGRATIONS_DIR,
  '..',
  'tests',
  'anon_execute_contract_test.sql',
);

const CREATE_ROUTINE =
  /^create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+([a-z_0-9."]+)\s*\(/i;
const RETURNS_TRIGGER = /\)\s*returns\s+trigger\b/i;
const GRANT_OR_REVOKE =
  /^(grant|revoke)\s+(?:grant\s+option\s+for\s+)?(.+?)\s+on\s+(all\s+(?:functions|procedures|routines)\s+in\s+schema|function|procedure|routine)\s+(.+?)\s+(?:to|from)\s+(.+)$/is;
const ALTER_DEFAULT_ROUTINES =
  /^alter\s+default\s+privileges\b.*\bon\s+(?:functions|procedures|routines)\b/is;

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
 * Count the top-level `( ... )` groups in a VALUES clause, ignoring parentheses
 * inside string literals. The row reader below is a regex, and a regex that
 * reads 25 of 26 rows reports a clean fixture while silently dropping the last
 * one — so the two counts are compared and a disagreement refuses.
 * @param {string} values
 * @returns {number}
 */
export function countTuples(values) {
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
 * Pull the `server_only` fixture out of the pgtap suite. Returns null — which
 * the caller refuses on — when the insert is absent or when the row reader and
 * the tuple count disagree.
 * @param {string} sql contents of anon_execute_contract_test.sql
 * @returns {{ fn: string, keepsServiceRole: boolean }[] | null}
 */
export function parseServerOnly(sql) {
  const statement = splitSqlStatements(sql).find((s) =>
    /^\s*insert\s+into\s+server_only\b/i.test(s),
  );
  if (statement === undefined) return null;
  const values = /\bvalues\b(.+)$/is.exec(statement);
  if (values === null) return null;
  /** @type {{ fn: string, keepsServiceRole: boolean }[]} */
  const rows = [];
  const tuple = /\(\s*'([a-z_0-9]+)'\s*,\s*(true|false)\s*\)/gi;
  let hit;
  while ((hit = tuple.exec(values[1])) !== null) {
    rows.push({ fn: hit[1], keepsServiceRole: hit[2].toLowerCase() === 'true' });
  }
  return rows.length === countTuples(values[1]) ? rows : null;
}

/**
 * Replay the migration set and return the `public` routines this repo states
 * are withheld from `authenticated`, each with whether it states a
 * `service_role` grant at the end.
 *
 * `unreadable` names routines that are in the family but whose `create`
 * statement was never seen, so their return type is unknown; the caller
 * refuses rather than guessing, because guessing "not a trigger" would demand
 * a fixture row for something the pgtap file excludes and guessing "trigger"
 * would drop a real one.
 * @param {{ filename: string, sql: string }[]} migrations any order; sorted here
 * @returns {{ scanned: number, family: Map<string, boolean>,
 *   unreadable: string[], unmodelled: { filename: string, statement: string }[] }}
 */
export function serverOnlyFamily(migrations) {
  const ordered = [...migrations].sort((a, b) => {
    const byVersion = (parseVersion(a.filename) ?? '').localeCompare(
      parseVersion(b.filename) ?? '',
    );
    return byVersion !== 0 ? byVersion : a.filename.localeCompare(b.filename);
  });

  /** @type {Map<string, boolean>} */
  const returnsTrigger = new Map();
  /** @type {Set<string>} */
  const revoked = new Set();
  /** @type {{ filename: string, statement: string }[]} */
  const unmodelled = [];

  for (const { filename, sql } of ordered) {
    for (const raw of splitSqlStatements(sql)) {
      const statement = raw.replace(/\s+/g, ' ').trim();

      if (ALTER_DEFAULT_ROUTINES.test(statement)) {
        unmodelled.push({ filename, statement });
        continue;
      }

      const created = CREATE_ROUTINE.exec(statement);
      if (created) {
        returnsTrigger.set(qualify(created[1]), RETURNS_TRIGGER.test(statement));
        continue;
      }

      const match = GRANT_OR_REVOKE.exec(statement);
      if (match === null) continue;
      const [, verb, privilegeClause, objectKind, target, roleClause] = match;
      if (verb.toLowerCase() !== 'revoke') continue;
      if (!/^(?:all|execute)\b/i.test(privilegeClause.trim())) continue;
      // A schema-wide revoke says nothing about which routines are meant to be
      // server-only; it is a sweep, and the per-routine statements around it
      // are what state the intent.
      if (/^all\b/i.test(objectKind.trim())) continue;
      const roles = splitList(roleClause).map((role) =>
        role.replace(/"/g, '').toLowerCase(),
      );
      if (!roles.includes('authenticated')) continue;
      for (const routine of splitList(target).map(qualify)) revoked.add(routine);
    }
  }

  const { stated } = statedGrants(ordered);

  /** @type {Map<string, boolean>} */
  const family = new Map();
  /** @type {string[]} */
  const unreadable = [];
  for (const routine of [...revoked].sort()) {
    if (!routine.startsWith('public.')) continue;
    // A revoke a later migration deliberately undid is not a withholding.
    if (stated.get(routine)?.has('authenticated')) continue;
    const trigger = returnsTrigger.get(routine);
    if (trigger === undefined) {
      unreadable.push(routine);
      continue;
    }
    if (trigger) continue;
    family.set(routine, stated.get(routine)?.has('service_role') === true);
  }

  return { scanned: ordered.length, family, unreadable, unmodelled };
}

/**
 * @param {{ migrations: { filename: string, sql: string }[], suiteSql: string }} input
 * @returns {{ refusal: string | null, scanned: number, rows: number,
 *   missing: string[], extra: string[], wrongServiceRole: string[] }}
 */
export function audit({ migrations, suiteSql }) {
  const blank = { scanned: 0, rows: 0, missing: [], extra: [], wrongServiceRole: [] };
  if (migrations.length === 0) {
    return { refusal: 'no migrations found', ...blank };
  }
  const { scanned, family, unreadable, unmodelled } = serverOnlyFamily(migrations);
  if (unmodelled.length > 0) {
    return {
      refusal: `an "alter default privileges ... on functions" moves the default this replay assumes (${unmodelled[0].filename})`,
      ...blank,
    };
  }
  if (unreadable.length > 0) {
    return {
      refusal: `no create statement found for ${unreadable.join(', ')}, so their return type is unknown`,
      ...blank,
    };
  }
  const rows = parseServerOnly(suiteSql);
  if (rows === null) {
    return { refusal: 'could not read the server_only fixture', ...blank };
  }
  if (rows.length === 0) {
    return { refusal: 'the server_only fixture is empty', ...blank };
  }

  const named = new Map(rows.map((r) => [`public.${r.fn}`, r.keepsServiceRole]));
  const missing = [...family.keys()].filter((fn) => !named.has(fn)).sort();
  const extra = [...named.keys()].filter((fn) => !family.has(fn)).sort();
  const wrongServiceRole = [...family.entries()]
    .filter(([fn, keeps]) => named.has(fn) && named.get(fn) !== keeps)
    .map(([fn, keeps]) => `${fn} (fixture says ${!keeps}, migrations state ${keeps})`)
    .sort();

  return { refusal: null, scanned, rows: rows.length, missing, extra, wrongServiceRole };
}

function main() {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((filename) => ({
      filename,
      sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
    }));
  const suiteSql = readFileSync(SUITE_FILE, 'utf8');
  const result = audit({ migrations, suiteSql });

  if (result.refusal !== null) {
    console.error(`REFUSED: ${result.refusal}`);
    process.exit(1);
  }
  const problems = [];
  for (const fn of result.missing) {
    problems.push(
      `${fn} is revoked from authenticated by a migration but is not in the server_only fixture — nothing asserts a signed-in account cannot reach it`,
    );
  }
  for (const fn of result.extra) {
    problems.push(
      `${fn} is in the server_only fixture but no migration states a revoke from authenticated for it`,
    );
  }
  for (const row of result.wrongServiceRole) problems.push(row);

  if (problems.length > 0) {
    console.error(
      `${problems.length} server_only registry problem(s) across ${result.scanned} migrations:`,
    );
    for (const problem of problems) console.error(`  - ${problem}`);
    process.exit(1);
  }
  console.log(
    `OK: ${result.scanned} migrations replayed; the server_only fixture names all ${result.rows} public non-trigger routines this repo states are withheld from authenticated, with matching service_role intent.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
