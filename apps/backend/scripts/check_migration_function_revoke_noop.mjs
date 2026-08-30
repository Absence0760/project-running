#!/usr/bin/env node
// Fail loudly when a migration revokes EXECUTE on a function from `anon` or
// `authenticated` while PUBLIC still holds it, which revokes nothing.
//
// A function created in this database arrives under Postgres's built-in
// default ACL — EXECUTE to the owner and to PUBLIC — and `anon` reaches it
// through PUBLIC, not through a grant of its own. So
// `revoke execute on function f(uuid) from anon` finds no grant to anon to
// remove: it reports REVOKE, materialises an ACL that still carries `=X`, and
// leaves `has_function_privilege('anon', …, 'EXECUTE')` true. The statement
// reads as a lockdown and is a comment — [decisions § 781]'s column-revoke
// no-op, one object class over, with PUBLIC playing the part the table level
// played there.
//
// Measured against the live catalogue, not assumed. A fresh function created
// by `postgres` in `public` has `proacl` NULL (the built-in default, PUBLIC
// included) and anon can execute it; `revoke … from public` turns that to
// `{postgres=X/postgres}` and anon to false, while `revoke … from anon` alone
// leaves `{=X/postgres,…}` and anon true. `enqueue_run_rematch` is the shipped
// instance and its ACL matches that probe byte for byte.
//
// This is why the house form is `from public, anon`: it is the `from public`
// half that does the work. `revoke … from public` on its own is CORRECT and is
// deliberately NOT reported — 110 functions are locked down that way and every
// one of them is closed to anon in the catalogue.
//
// The second way PUBLIC comes back is a `drop function` followed by a fresh
// `create`, which resets the ACL to the built-in default; `create or replace`
// on the same signature preserves it. Both are modelled, both measured.
//
// The whole tree is scanned, on every run, with no allowlist and no version
// cutoff — [§ 775] retired a cutoff whose bookkeeping edit was the bypass. The
// migration set is replayed in version order and a revoke is reported only if
// PUBLIC STILL holds EXECUTE on that function at the end of the replay, so a
// repair lands as a later migration (`revoke execute on function f(uuid) from
// public`) rather than as an edit here, and a later `grant … to public` puts
// the report back.
//
// What it deliberately does not catch: a function is keyed by its
// schema-qualified NAME, so two overloads of one name share a verdict (there
// are none in `public` or `private` today, measured); and the model's one
// premise — that a created function lands under the built-in default — is
// version-controlled rather than assumed, so an `alter default privileges`
// touching routines fails this guard instead of silently inverting it.
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
 * Replay the migration set and return every revoke of EXECUTE from a client
 * role that PUBLIC still holds at the end of the replay.
 * @param {{ filename: string, sql: string }[]} migrations any order; sorted here
 * @returns {{ scanned: string[], unmodelled: { filename: string, statement: string }[],
 *   violations: { filename: string, routine: string, role: string, statement: string }[] }}
 */
export function auditMigrations(migrations) {
  const ordered = [...migrations].sort((a, b) => {
    const versions = (parseVersion(a.filename) ?? '').localeCompare(parseVersion(b.filename) ?? '');
    return versions !== 0 ? versions : a.filename.localeCompare(b.filename);
  });

  /** Routines PUBLIC holds EXECUTE on, keyed schema.name. Absent = never seen. */
  const publicHolds = new Map();
  /** @type {{ filename: string, routine: string, role: string, statement: string }[]} */
  const candidates = [];
  /** @type {{ filename: string, statement: string }[]} */
  const unmodelled = [];
  /** @type {string[]} */
  const scanned = [];

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
        const routine = qualify(created[1]);
        if (!publicHolds.has(routine)) publicHolds.set(routine, true);
        continue;
      }
      const dropped = DROP_ROUTINE.exec(statement);
      if (dropped) {
        publicHolds.delete(qualify(dropped[1]));
        continue;
      }

      const match = GRANT_OR_REVOKE.exec(statement);
      if (!match) continue;
      const [, verb, privilegeClause, objectKind, target, roleClause] = match;
      if (!/^(?:all|execute)\b/i.test(privilegeClause.trim())) continue;

      const bulk = /^all\b/i.test(objectKind.trim());
      const schemas = bulk ? new Set(splitList(target).map((s) => s.replace(/"/g, '').toLowerCase())) : null;
      const routines = schemas
        ? [...publicHolds.keys()].filter((name) => schemas.has(name.slice(0, name.indexOf('.'))))
        : splitList(target).map(qualify);
      const roles = splitList(roleClause).map((role) => role.replace(/"/g, '').toLowerCase());

      for (const routine of routines) {
        if (!publicHolds.has(routine)) publicHolds.set(routine, true);
        if (roles.includes('public')) {
          publicHolds.set(routine, verb.toLowerCase() === 'grant');
          continue;
        }
        if (verb.toLowerCase() !== 'revoke' || publicHolds.get(routine) !== true) continue;
        for (const role of roles) {
          if (CLIENT_ROLES.includes(role)) candidates.push({ filename, routine, role, statement });
        }
      }
    }
  }

  const violations = candidates.filter(({ routine }) => publicHolds.get(routine) === true);
  return { scanned, unmodelled, violations };
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
        `privileges on routines, which is the one premise this guard replays against — that a ` +
        `created function lands under Postgres's built-in default of EXECUTE to PUBLIC. The ` +
        `statement is "${statement}". Re-measure the default against the local catalogue and ` +
        `teach the replay in check_migration_function_revoke_noop.mjs about it, rather than ` +
        `leaving it to report verdicts under a premise the tree has changed.`,
    );
  }

  for (const { filename, routine, role, statement } of violations) {
    console.error(
      `::error file=apps/backend/supabase/migrations/${filename}::${filename} revokes EXECUTE on ` +
        `"${routine}" from "${role}", which revokes nothing: PUBLIC still holds EXECUTE on that ` +
        `function at the end of the migration set, and "${role}" reaches it through PUBLIC rather ` +
        `than through a grant of its own. The statement is "${statement}". Revoke it from PUBLIC ` +
        `instead — the house form is "revoke execute on function <f> from public, anon;" — and ` +
        `re-grant the roles that must keep it. A shipped migration is uneditable, so repair it ` +
        `forward in a new one; this guard has no allowlist and reads the end state.`,
    );
  }

  if (violations.length > 0 || unmodelled.length > 0) process.exit(1);
  console.log(
    `OK: ${scanned.length} migrations replayed, no EXECUTE revoke left standing under a PUBLIC grant.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
