#!/usr/bin/env node
// Fail loudly when a migration revokes EXECUTE on a function from PUBLIC or
// from `anon` but not both, which withholds nothing on one of the two Supabase
// images this repo runs against.
//
// `anon` can reach a function through two independent channels: the built-in
// PUBLIC grant Postgres gives every new routine, and a grant of anon's own.
// Which of the two exists depends on the Supabase CLI image, and the two
// images disagree:
//
//   * Workstation, CLI 2.109.1 — a new `public` function has `proacl` NULL,
//     the built-in default, and anon reaches it ONLY through PUBLIC. So
//     `revoke … from public` withholds and `revoke … from anon` is a no-op.
//   * CI and Supabase Cloud, CLI 2.84.2 (pinned in ci.yml) — an
//     `alter default privileges` hands the new function an EXPLICIT anon
//     grant, so `revoke … from public` leaves it in place and only
//     `revoke … from anon` withholds.
//
// The evidence that separates them is this repo's own shipped test, not a
// probe. `coach_roster_summary_test.sql` asserts, under `set local role anon`,
// that the call raises `not authenticated` — which requires the ACL to ADMIT
// anon so the body can refuse it. That function was only ever revoked
// `from public` (20270206_001, 20270314_001). On CI the assertion passes; on
// the workstation the same SQL raises `permission denied for function`.
//
// So neither single-grantee revoke is portable, and a guard that picks one
// image's rule is wrong on the other. Only `from public, anon` withholds under
// either default, which is why that is the house form — and it is the form
// this guard requires. The two channels need not close in one statement: a
// later migration closing the other one repairs it forward.
//
// A DELIBERATE re-open discharges the obligation, because it is portable in
// its own right: `revoke … from public` followed by `grant execute … to anon`
// leaves anon holding on both images, which is a decision rather than a
// divergence. Only a channel left at its image-dependent DEFAULT is reported.
//
// `authenticated` is carried for the same reason in one direction only: a
// revoke naming it is defeated by PUBLIC on the workstation image exactly as
// an anon revoke is. Nothing requires an anon lockdown to close authenticated
// as well — every RPC here is meant for signed-in callers unless it says
// otherwise, and ~110 migrations grant it back on the next line.
//
// The whole tree is scanned, on every run, with no allowlist and no version
// cutoff — [§ 775] retired a cutoff whose bookkeeping edit was the bypass. The
// set is replayed in version order and a revoke is reported only if the other
// channel is STILL at its default at the end, so a repair is a migration
// rather than an edit here, and a later re-default puts the report back.
//
// What it deliberately does not catch. It grades the STATEMENT, so a routine
// nobody ever wrote a lockdown for is not its business, and neither is one
// whose well-formed lockdown a later `drop`-and-`create` re-opened — the
// statement was portable as written, and "every routine is locked down" is a
// claim about STATE that a pgtap catalogue assertion makes ([§ 781]). A
// routine is keyed by its schema-qualified NAME, so two overloads of one name
// share a verdict (there are none in `public` or `private` today, measured).
// Table and column revokes are check_migration_column_revoke_noop.mjs's
// business. `service_role` is not tracked; it keeps full access by design. And
// `alter default privileges` on routines is NOT modelled — it would move the
// very default this guard replays against, so a migration carrying one fails
// here rather than letting the replay keep issuing verdicts under a premise
// the tree has changed.
//
// Run locally: node apps/backend/scripts/check_migration_function_revoke_noop.mjs

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { MIGRATIONS_DIR, parseVersion } from './check_migration_versions.mjs';
import { splitSqlStatements } from './sql_lex.mjs';

export const CLIENT_ROLES = ['anon', 'authenticated'];

const CREATE_ROUTINE = /^create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+([a-z_0-9."]+)\s*\(/i;
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
function qualify(name) {
  const bare = name.replace(/\(.*$/s, '').trim().replace(/"/g, '').toLowerCase();
  return bare.includes('.') ? bare : `public.${bare}`;
}

/**
 * Split a comma-separated list, keeping a routine's argument list intact:
 * `f(uuid, text), g(int)` is two entries, not three.
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
 * Replay the migration set and return every revoke that closes one of the two
 * channels to `anon` while the other is still at its image-dependent default.
 * @param {{ filename: string, sql: string }[]} migrations any order; sorted here
 * @returns {{ scanned: string[], unmodelled: { filename: string, statement: string }[],
 *   violations: { filename: string, routine: string, named: string, missing: string,
 *   statement: string }[] }}
 */
export function auditMigrations(migrations) {
  const ordered = [...migrations].sort((a, b) => {
    const versions = (parseVersion(a.filename) ?? '').localeCompare(parseVersion(b.filename) ?? '');
    return versions !== 0 ? versions : a.filename.localeCompare(b.filename);
  });

  /**
   * Per routine, the state of each channel anon can reach EXECUTE through.
   * `default` is whatever the image grants a new routine — the one state that
   * is not portable, and the only one reported.
   * @type {Map<string, { public: string, anon: string }>}
   */
  const channels = new Map();
  /** @type {{ filename: string, routine: string, named: string, missing: string, statement: string }[]} */
  const candidates = [];
  /** @type {{ filename: string, statement: string }[]} */
  const unmodelled = [];
  /** @type {string[]} */
  const scanned = [];

  /** @param {string} routine */
  const track = (routine) => {
    const seen = channels.get(routine);
    if (seen) return seen;
    const fresh = { public: 'default', anon: 'default' };
    channels.set(routine, fresh);
    return fresh;
  };

  for (const { filename, sql } of ordered) {
    scanned.push(filename);
    // Literals are kept rather than blanked, as in the column-revoke guard: the
    // lexer's blanking also empties QUOTED IDENTIFIERS. Every pattern below is
    // anchored at the start of a statement, so a REVOKE written inside a
    // dollar-quoted body is part of some other statement's text.
    for (const raw of splitSqlStatements(sql)) {
      const statement = raw.replace(/\s+/g, ' ').trim();

      if (ALTER_DEFAULT_ROUTINES.test(statement)) {
        unmodelled.push({ filename, statement });
        continue;
      }

      const created = CREATE_ROUTINE.exec(statement);
      if (created) {
        track(qualify(created[1]));
        continue;
      }
      const dropped = DROP_ROUTINE.exec(statement);
      if (dropped) {
        channels.delete(qualify(dropped[1]));
        continue;
      }

      const match = GRANT_OR_REVOKE.exec(statement);
      if (!match) continue;
      const [, rawVerb, privilegeClause, objectKind, target, roleClause] = match;
      if (!/^(?:all|execute)\b/i.test(privilegeClause.trim())) continue;
      const verb = rawVerb.toLowerCase();

      const bulk = /^all\b/i.test(objectKind.trim());
      const schemas = bulk
        ? new Set(splitList(target).map((s) => s.replace(/"/g, '').toLowerCase()))
        : null;
      const routines = schemas
        ? [...channels.keys()].filter((name) => schemas.has(name.slice(0, name.indexOf('.'))))
        : splitList(target).map(qualify);
      const roles = new Set(splitList(roleClause).map((role) => role.replace(/"/g, '').toLowerCase()));

      for (const routine of routines) {
        const state = track(routine);
        if (verb === 'revoke') {
          if (roles.has('public') && !roles.has('anon')) {
            candidates.push({ filename, routine, named: 'public', missing: 'anon', statement });
          }
          if (roles.has('anon') && !roles.has('public')) {
            candidates.push({ filename, routine, named: 'anon', missing: 'public', statement });
          }
          if (roles.has('authenticated') && !roles.has('public')) {
            candidates.push({ filename, routine, named: 'authenticated', missing: 'public', statement });
          }
        }
        if (roles.has('public')) state.public = verb === 'grant' ? 'granted' : 'closed';
        if (roles.has('anon')) state.anon = verb === 'grant' ? 'granted' : 'closed';
      }
    }
  }

  const violations = candidates.filter(({ routine, missing }) => {
    const state = channels.get(routine);
    return state !== undefined && (missing === 'anon' ? state.anon : state.public) === 'default';
  });
  return { scanned, unmodelled, violations };
}

/**
 * @param {{ routine: string, named: string, missing: string }} violation
 * @returns {string}
 */
function why(violation) {
  return violation.missing === 'anon'
    ? `"${violation.routine}" is closed to PUBLIC but nothing closes anon's own grant, which the ` +
        `CI and production image installs by default — so anon can still execute it there`
    : `"${violation.routine}" is closed to "${violation.named}" but nothing closes PUBLIC, which ` +
        `the workstation image relies on to reach the function — so it is still executable there`;
}

function main() {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((filename) => filename.endsWith('.sql'))
    .map((filename) => ({ filename, sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8') }));

  const { scanned, unmodelled, violations } = auditMigrations(migrations);

  if (scanned.length === 0) {
    console.error(
      `::error::The function-revoke scan read no migrations at all from ${MIGRATIONS_DIR}, so a ` +
        `clean report says nothing about the tree. Either the directory moved or the .sql filter ` +
        `stopped matching.`,
    );
    process.exit(1);
  }

  for (const { filename, statement } of unmodelled) {
    console.error(
      `::error file=apps/backend/supabase/migrations/${filename}::${filename} changes the DEFAULT ` +
        `privileges on routines, which is the very thing this guard replays against — it models a ` +
        `new routine as arriving with BOTH the PUBLIC channel and anon's own open, because which ` +
        `one an image really grants differs between CLI 2.109.1 and the pinned 2.84.2. The ` +
        `statement is "${statement}". Teach the replay in ` +
        `check_migration_function_revoke_noop.mjs about it rather than leaving it to issue ` +
        `verdicts under a premise the tree has changed.`,
    );
  }

  for (const violation of violations) {
    const { filename, named, statement } = violation;
    console.error(
      `::error file=apps/backend/supabase/migrations/${filename}::${filename} revokes EXECUTE from ` +
        `"${named}" alone, which does not withhold the function on both Supabase images: ` +
        `${why(violation)}. The statement is "${statement}". Name both — ` +
        `"revoke execute on function <f> from public, anon;" — in this migration or a later one, ` +
        `or grant the role EXECUTE outright if it is meant to have it. A shipped migration is ` +
        `uneditable, so repair it forward; this guard has no allowlist and reads the end state.`,
    );
  }

  if (violations.length > 0 || unmodelled.length > 0) process.exit(1);
  console.log(
    `OK: ${scanned.length} migrations replayed, every EXECUTE revoke closes both the PUBLIC and ` +
      `the anon channel.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
