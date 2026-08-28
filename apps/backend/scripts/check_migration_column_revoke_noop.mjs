#!/usr/bin/env node
// Fail loudly when a migration revokes a privilege at COLUMN level while the
// role still holds it at TABLE level, which revokes nothing.
//
// Postgres resolves a privilege from the broadest grant it finds: "if a role
// has been granted privileges on a table, then revoking the same privileges
// from individual columns will have no effect". So
// `revoke select (secret) on t from authenticated` under a table-level
// `grant select on t to authenticated` reports REVOKE, writes no column ACL,
// and leaves `has_column_privilege` true. The statement reads as a lockdown
// and is a comment.
//
// 20260707_001 wrote the trap into its own header and prescribed the fix —
// revoke the TABLE-level privilege, then re-grant per column — and two later
// migrations reached for the broken shape anyway: 20261229_001 over
// `instructor_payout_accounts.stripe_connect_account_id` and 20270213_001 over
// five columns of `donations`, both describing it as defence in depth. On the
// first, whose own-row SELECT policy is permissive, the host could read their
// raw Stripe Connect account id for the life of the table. Nothing detected
// either: a no-op revoke leaves `pg_attribute.attacl` null, so a catalog guard
// looking for column carve-outs sees a table that never had one.
//
// This guard reads the STATEMENT, which is the only place the intent is
// legible. `column_grant_lockdown_registry_test.sql` reads the resulting
// STATE, which is what proves a lockdown is in force; neither subsumes the
// other, and this one is what stops migration N+1 shipping the shape again.
//
// It carries no allowlist and needs none. The migration set is replayed in
// version order and a column revoke is reported only if the role STILL holds
// the table-level privilege at the end of the replay — so a repair lands as a
// later migration rather than as a bookkeeping edit here, and a table-level
// grant that re-opens the table afterwards puts the report back. The two
// shipped violations are repaired by 20270621_001 and the uneditable files
// keep their history.
//
// The replay's one assumption is that a `create table` in `public` lands under
// Supabase's default privileges, which grant every DML verb to anon and
// authenticated (measured on the local stack: a fresh table's relacl carries
// `anon=arwdDxtm/postgres`). That is also the conservative direction — it can
// only make the guard flag a column revoke, never excuse one — and this repo
// requires every new table to grant its own client surface anyway.
//
// Only `anon` and `authenticated` are tracked. `service_role` keeps full table
// access by design, and no migration grants a table privilege to `public`.
//
// Run locally: node apps/backend/scripts/check_migration_column_revoke_noop.mjs

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { MIGRATIONS_DIR, parseVersion } from './check_migration_versions.mjs';
import { splitSqlStatements } from './sql_lex.mjs';

export const CLIENT_ROLES = ['anon', 'authenticated'];
const DML_PRIVILEGES = ['SELECT', 'INSERT', 'UPDATE', 'DELETE'];

const CREATE_TABLE = /^create\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_0-9."]+)/i;
const DROP_TABLE = /^drop\s+table\s+(?:if\s+exists\s+)?([a-z_0-9."]+)/i;
const GRANT_OR_REVOKE =
  /^(grant|revoke)\s+(?:grant\s+option\s+for\s+)?(.+?)\s+on\s+(?:table\s+)?(.+?)\s+(?:to|from)\s+(.+)$/is;

/**
 * `public.donations` / `"donations"` / `donations` all key as `donations`.
 * @param {string} name
 * @returns {string}
 */
function bare(name) {
  return name.trim().replace(/"/g, '').replace(/^public\./i, '').toLowerCase();
}

/**
 * @param {string} table
 * @param {string} role
 * @param {string} privilege
 * @returns {string}
 */
function key(table, role, privilege) {
  return `${table}|${role}|${privilege}`;
}

/**
 * The privileges a GRANT/REVOKE names, and the columns it scopes them to.
 * `select (a, b), update` is legal SQL, so the column list is per privilege.
 * @param {string} clause the text between the verb and `on`
 * @returns {{ privilege: string, columns: string[] | null }[] | null} null when
 *   the clause names something this guard does not model (a sequence privilege,
 *   `usage`, …) alongside nothing it does.
 */
export function parsePrivileges(clause) {
  const text = clause.trim();
  if (/^all\b/i.test(text)) {
    const columns = /^all\s*(?:privileges\s*)?\(([^)]*)\)/i.exec(text);
    return DML_PRIVILEGES.map((privilege) => ({
      privilege,
      columns: columns ? splitList(columns[1]) : null,
    }));
  }
  /** @type {{ privilege: string, columns: string[] | null }[]} */
  const out = [];
  const parts = text.split(/,(?![^(]*\))/);
  for (const part of parts) {
    const match = /^\s*([a-z ]+?)\s*(?:\(([^)]*)\))?\s*$/i.exec(part);
    if (!match) continue;
    const privilege = match[1].trim().toUpperCase();
    if (!DML_PRIVILEGES.includes(privilege)) continue;
    out.push({ privilege, columns: match[2] === undefined ? null : splitList(match[2]) });
  }
  return out.length > 0 ? out : null;
}

/**
 * @param {string} text
 * @returns {string[]}
 */
function splitList(text) {
  return text
    .split(',')
    .map((entry) => entry.trim().replace(/"/g, ''))
    .filter(Boolean);
}

/**
 * Replay the migration set and return every column-level revoke whose role
 * still holds the table-level privilege when the replay ends.
 * @param {{ filename: string, sql: string }[]} migrations any order; sorted here
 * @returns {{ scanned: string[], violations: { filename: string, table: string,
 *   role: string, privilege: string, statement: string }[] }}
 */
export function auditMigrations(migrations) {
  const ordered = [...migrations].sort((a, b) => {
    const versions = (parseVersion(a.filename) ?? '').localeCompare(parseVersion(b.filename) ?? '');
    return versions !== 0 ? versions : a.filename.localeCompare(b.filename);
  });

  /** Table-level privilege held, keyed table|role|privilege. Absent = held. */
  const revoked = new Set();
  /**
   * @param {string} table
   * @param {string} role
   * @param {string} privilege
   * @returns {boolean}
   */
  const held = (table, role, privilege) => !revoked.has(key(table, role, privilege));
  /** @type {{ filename: string, table: string, role: string, privilege: string, statement: string }[]} */
  const candidates = [];
  /** @type {string[]} */
  const scanned = [];

  for (const { filename, sql } of ordered) {
    scanned.push(filename);
    // Literals are kept rather than blanked: the lexer's blanking also empties
    // QUOTED IDENTIFIERS, and `revoke select ("secret") on "donations"` is then
    // a statement naming nothing. Every pattern below is anchored at the start
    // of a statement, so a GRANT written inside a string or a dollar-quoted
    // body is part of some other statement's text and matches nothing.
    for (const raw of splitSqlStatements(sql)) {
      const statement = raw.replace(/\s+/g, ' ').trim();

      const created = CREATE_TABLE.exec(statement);
      if (created) {
        for (const role of CLIENT_ROLES) {
          for (const privilege of DML_PRIVILEGES) revoked.delete(key(bare(created[1]), role, privilege));
        }
        continue;
      }
      const dropped = DROP_TABLE.exec(statement);
      if (dropped) {
        for (const role of CLIENT_ROLES) {
          for (const privilege of DML_PRIVILEGES) revoked.delete(key(bare(dropped[1]), role, privilege));
        }
        continue;
      }

      const match = GRANT_OR_REVOKE.exec(statement);
      if (!match) continue;
      const [, verb, privilegeClause, target, roleClause] = match;
      if (/^(function|procedure|schema|sequence|database|all\s)/i.test(target.trim())) continue;
      const privileges = parsePrivileges(privilegeClause);
      if (!privileges) continue;
      const tables = splitList(target).map(bare);
      const roles = splitList(roleClause)
        .map((role) => role.toLowerCase())
        .filter((role) => CLIENT_ROLES.includes(role));
      if (tables.length === 0 || roles.length === 0) continue;

      for (const { privilege, columns } of privileges) {
        for (const table of tables) {
          for (const role of roles) {
            if (columns !== null) {
              if (verb.toLowerCase() === 'revoke' && held(table, role, privilege)) {
                candidates.push({ filename, table, role, privilege, statement });
              }
              continue;
            }
            if (verb.toLowerCase() === 'grant') revoked.delete(key(table, role, privilege));
            else revoked.add(key(table, role, privilege));
          }
        }
      }
    }
  }

  const violations = candidates.filter(({ table, role, privilege }) => held(table, role, privilege));
  return { scanned, violations };
}

function main() {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((filename) => filename.endsWith('.sql'))
    .map((filename) => ({ filename, sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8') }));

  const { scanned, violations } = auditMigrations(migrations);

  if (scanned.length === 0) {
    console.error(
      `::error::The column-revoke scan read no migrations at all from ${MIGRATIONS_DIR}, so a ` +
        `clean report says nothing about the tree. Either the directory moved or the .sql filter ` +
        `stopped matching.`,
    );
    process.exit(1);
  }

  for (const { filename, table, role, privilege, statement } of violations) {
    console.error(
      `::error file=apps/backend/supabase/migrations/${filename}::${filename} revokes ` +
        `${privilege} on named columns of "${table}" from "${role}", which revokes nothing: ` +
        `"${role}" still holds ${privilege} on the whole table at the end of the migration set, ` +
        `and Postgres resolves a privilege from the broadest grant. The statement is ` +
        `"${statement}". Use the shape 20260707_001 prescribes instead — revoke the TABLE-level ` +
        `privilege from the role, then re-grant it column by column — and register the withheld ` +
        `columns in apps/backend/supabase/tests/column_grant_lockdown_registry_test.sql. A ` +
        `shipped migration is uneditable, so repair it forward in a new one; this guard has no ` +
        `allowlist and reads the end state.`,
    );
  }

  if (violations.length > 0) process.exit(1);
  console.log(
    `OK: ${scanned.length} migrations replayed, no column-level revoke left standing under a ` +
      `table-level grant.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
