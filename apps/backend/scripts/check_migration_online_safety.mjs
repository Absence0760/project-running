#!/usr/bin/env node
// Fail loudly if a migration adds a CHECK or FOREIGN KEY constraint to a
// high-volume table without the online-safe `NOT VALID` two-step.
//
// Adding a CHECK or FK in a single `ALTER TABLE ... ADD CONSTRAINT ...` holds a
// strong lock while Postgres scans every existing row to validate it. On a
// tiny local / CI database that is invisible; against the populated prod
// `runs` (or `notifications`, `segment_efforts`, ...) it blocks readers and
// writers for the length of the scan — that is downtime. The online form is
// `ADD CONSTRAINT ... NOT VALID` (instant, no scan) followed by a separate
// `VALIDATE CONSTRAINT` (scans under the weaker SHARE UPDATE EXCLUSIVE lock,
// which lets writes through). The full pattern + worked examples live in
// docs/backend/migration_locks.md.
//
// EVERY committed migration is scanned, on every run. The shipped history is
// grandfathered by NAME — the entries in GRANDFATHERED_VIOLATIONS below — and
// not by a version boundary. That is the design, and it replaces a
// `GRANDFATHER_CUTOFF` under which the guard inspected nothing at rest:
//
//   * The cutoff exempted everything at or below it, and this file's own test
//     asserted the cutoff was at least the newest committed migration. So a
//     migration-bearing PR had to bump it, and the bump removed that migration
//     from the scan. Which of the two happened first decided whether the guard
//     ever read the new SQL, and both orders left an identical tree and an
//     identical green test. Between merges the scanned set was empty by
//     construction, across 436 migrations and eight rounds of bumping.
//   * A name cannot do that. An entry vouches for one constraint in one file,
//     it can only be written by someone who has read the violation it names,
//     and it exempts nothing else. Adding a migration needs no edit here at
//     all — which is the point, because the bookkeeping edit WAS the bypass.
//   * An entry matching no violation in the tree is an error, not dead weight:
//     the list cannot quietly accumulate cover for things that are gone.
//
// The scan is still deliberately NARROW to stay low-false-positive: it only
// flags constraints on GUARDED_TABLES (the high-volume / unbounded tables the
// migration-locks audit names). A NOT-VALID-less CHECK on a small, bounded
// config table (event_pricing, fundraisers, race_listings, ...) is harmless
// ceremony to demand, so those are not guarded.
//
// Run locally: node apps/backend/scripts/check_migration_online_safety.mjs

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { MIGRATIONS_DIR } from './check_migration_versions.mjs';
import { splitSqlStatements } from './sql_lex.mjs';

// High-volume / unbounded-growth tables where a validating ADD CONSTRAINT scan
// is real downtime against prod. Mirrors the table list in
// .claude/commands/audit/migration-locks.md.
export const GUARDED_TABLES = new Set([
  'runs',
  'notifications',
  'jobs',
  'live_run_pings',
  'race_pings',
  'segment_efforts',
  'run_kudos',
  'run_comments',
  'run_photos',
  'webhook_events',
  'rate_limits',
]);

// The blocking constraint adds already shipped, named one at a time. Every one
// is a `kind`-CHECK widen or an FK recreate that took a validating full scan
// under ACCESS EXCLUSIVE; they are applied and uneditable, which is what
// "grandfathered" means here and all it means. Twelve `notifications` widens
// (20260903_001 through 20270218_001) and thirteen `jobs` ones are the bulk of
// it — the recurring pattern migration_locks.md exists to stop.
//
// Adding to this list is not bookkeeping and must not become it. A new entry
// says "this constraint takes a blocking scan of a high-volume table and we are
// shipping it anyway"; the normal path is the NOT VALID + VALIDATE two-step,
// which needs nothing here.
/** @typedef {{ filename: string, table: string, constraint: string }} Grandfathered */
/** @type {readonly Grandfathered[]} */
export const GRANDFATHERED_VIOLATIONS = [
  { filename: '20260505_001_narrow_union_check_constraints.sql', table: 'runs', constraint: 'runs_source_check' },
  { filename: '20260601_001_runs_metadata_activity_type_required.sql', table: 'runs', constraint: 'runs_metadata_activity_type_check' },
  { filename: '20260728_001_cascade_auth_users_fks.sql', table: 'runs', constraint: 'runs_user_id_fkey' },
  { filename: '20260822_001_jobs_kind_allowlist.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20260823_001_jobs_kind_allowlist_strava_event.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20260825_001_jobs_kind_allowlist_photo_process.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20260903_001_notify_event_rsvp.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20260928_001_gdpr_dsar_closeouts.sql', table: 'rate_limits', constraint: 'rate_limits_user_id_fkey' },
  { filename: '20261019_001_event_instance_cancellation.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261024_001_plan_workout_audit_notify.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261026_001_direct_messages.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261101_001_notify_club_post_run_completed.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261130_001_notification_email_channel.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261130_001_notification_email_channel.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261202_001_welcome_email.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261207_001_promote_activity_type_is_dnf.sql', table: 'runs', constraint: 'runs_activity_type_check' },
  { filename: '20261211_001_consolidate_kind_check_constraints.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261211_001_consolidate_kind_check_constraints.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261218_001_safety_contacts.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261219_001_web_push_channel.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270107_001_notify_plan_assigned.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270108_001_email_engagement.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270208_001_achievements.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270210_001_challenge_progress_rpc.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270211_001_notifications_kind_check_reconcile.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270212_001_native_push_channel.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270218_001_auto_hide_reports.sql', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270223_001_lifecycle_drip.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270224_001_route_photo_thumbnails.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270301_001_club_photos.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270322_001_routes_fk_alignment.sql', table: 'runs', constraint: 'runs_route_id_fkey' },
  { filename: '20270410_001_safety_sms_escalation.sql', table: 'jobs', constraint: 'jobs_kind_chk' },
];

// The target table of an `ALTER TABLE [IF EXISTS] [ONLY] [public.]<table> ...`.
/**
 * @param {string} statement
 * @returns {string | null}
 */
function alterTargetTable(statement) {
  const match =
    /^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?([a-z0-9_]+)/.exec(
      statement,
    );
  return match ? match[1] : null;
}

// One ALTER TABLE carries a comma-separated list of actions, and NOT VALID
// qualifies only the ADD CONSTRAINT it terminates — so testing the whole
// statement for it exempts every sibling action too, and a two-step ADD
// alongside a bare one passed the guard. Split at paren depth 0 so a
// `check (kind in ('a', 'b'))` or a multi-column `foreign key (a, b)` is not
// cut in half.
/**
 * @param {string} statement
 * @returns {string[]}
 */
function alterActions(statement) {
  /** @type {string[]} */
  const actions = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < statement.length; i++) {
    const char = statement[i];
    if (char === '(') depth += 1;
    else if (char === ')') depth -= 1;
    else if (char === ',' && depth === 0) {
      actions.push(statement.slice(start, i));
      start = i + 1;
    }
  }
  actions.push(statement.slice(start));
  return actions;
}

const BLOCKING_ADD =
  /\badd\s+(?:constraint\s+([a-z0-9_"]+)\s+)?(?:check\s*\(|foreign\s+key\b)/;

// True when the action adds a CHECK or FK constraint (named or anonymous)
// without the NOT VALID escape hatch.
/**
 * @param {string} action
 * @returns {boolean}
 */
function isBlockingAdd(action) {
  return BLOCKING_ADD.test(action) && !action.includes('not valid');
}

// The constraint's name, or null when it has none this list could key on. A
// quoted identifier arrives blanked (`""`), because the lexer blanks literal
// and identifier CONTENT so it cannot vote on the scan — so a quoted name is
// unnamed as far as the allowlist is concerned, which fails closed: no entry
// can ever match it.
/**
 * @param {string} action
 * @returns {string | null}
 */
function constraintName(action) {
  const name = BLOCKING_ADD.exec(action)?.[1];
  return name && /^[a-z0-9_]+$/.test(name) ? name : null;
}

export class UnlexableMigration extends Error {
  /**
   * @param {string} filename
   * @param {unknown} cause
   */
  constructor(filename, cause) {
    super(`${filename}: ${cause instanceof Error ? cause.message : String(cause)}`);
    this.name = 'UnlexableMigration';
    this.filename = filename;
  }
}

/** @typedef {{ table: string, constraint: string | null, statement: string }} ConstraintFinding */
/** @typedef {{ filename: string, sql: string }} MigrationSource */
/** @typedef {{ filename: string, table: string, constraint: string | null, statement: string }} ConstraintViolation */
/** @typedef {{ scanned: string[], violations: ConstraintViolation[], unmatched: Grandfathered[] }} Audit */

// Returns the guarded-table constraint violations in one migration's SQL.
/**
 * @param {string} sql
 * @returns {ConstraintFinding[]}
 * @throws when the SQL cannot be lexed; a verdict over text the lexer could
 *   not read would be a guess.
 */
export function findUnsafeConstraintAdds(sql) {
  /** @type {ConstraintFinding[]} */
  const findings = [];
  // Literals are blanked as well as split correctly: a `check (note <> 'not
  // valid')` otherwise reads as a statement that carries the escape hatch.
  const statements = splitSqlStatements(sql, { blankLiterals: true });
  for (const raw of statements) {
    const statement = raw.replace(/\s+/g, ' ').trim().toLowerCase();
    if (!statement.startsWith('alter table')) continue;
    const table = alterTargetTable(statement);
    if (table === null || !GUARDED_TABLES.has(table)) continue;
    for (const action of alterActions(statement)) {
      if (!isBlockingAdd(action)) continue;
      findings.push({
        table,
        constraint: constraintName(action),
        statement: statement.slice(0, 120),
      });
    }
  }
  return findings;
}

// An unnamed constraint has no key, so no entry can vouch for it. Folding null
// onto the empty string would let an entry with a blank name exempt every
// anonymous ADD in its file.
/**
 * @param {{ filename: string, table: string, constraint: string | null }} violation
 * @returns {string | null}
 */
function violationKey({ filename, table, constraint }) {
  return constraint ? `${filename} ${table} ${constraint}` : null;
}

// Every guarded-table violation the allowlist does not name, the allowlist
// entries that named nothing, and the files actually read. `scanned` is
// returned rather than implied: the defect this design replaced was an empty
// scan set reporting a clean tree, and a caller that cannot see the set cannot
// notice.
/**
 * @param {readonly MigrationSource[]} migrations
 * @param {readonly Grandfathered[]} [allowlist]
 * @returns {Audit}
 * @throws an {@link UnlexableMigration} naming the file whose SQL could not be
 *   read. Skipping it instead would report the whole tree clean over a file
 *   nothing inspected.
 */
export function auditMigrations(migrations, allowlist = GRANDFATHERED_VIOLATIONS) {
  /** @type {ConstraintViolation[]} */
  const violations = [];
  /** @type {string[]} */
  const scanned = [];
  const allowed = new Set(allowlist.map(violationKey).filter((k) => k !== null));
  /** @type {Set<string>} */
  const used = new Set();

  for (const { filename, sql } of migrations) {
    scanned.push(filename);
    /** @type {ConstraintFinding[]} */
    let findings;
    try {
      findings = findUnsafeConstraintAdds(sql);
    } catch (cause) {
      throw new UnlexableMigration(filename, cause);
    }
    for (const finding of findings) {
      const violation = { filename, ...finding };
      const key = violationKey(violation);
      if (key !== null && allowed.has(key)) {
        used.add(key);
        continue;
      }
      violations.push(violation);
    }
  }

  return {
    scanned,
    violations,
    unmatched: allowlist.filter((entry) => {
      const key = violationKey(entry);
      return key === null || !used.has(key);
    }),
  };
}

function main() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'));
  const migrations = files.map((filename) => ({
    filename,
    sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
  }));
  /** @type {Audit} */
  let audit;
  try {
    audit = auditMigrations(migrations);
  } catch (error) {
    if (!(error instanceof UnlexableMigration)) throw error;
    console.error(
      `::error file=apps/backend/supabase/migrations/${error.filename}::${error.message}. ` +
        `The online-safety scanner reads this file as Postgres does — tracking dollar-quoted ` +
        `bodies, string literals and nested block comments — and it does not close. Postgres ` +
        `would reject the migration too. Fix the quoting; the scan cannot report on a file it ` +
        `could not read.`,
    );
    process.exit(1);
  }

  if (audit.scanned.length === 0) {
    console.error(
      `::error::The online-safety scan read no migrations at all from ${MIGRATIONS_DIR}, so a ` +
        `clean report says nothing about the tree. Either the directory moved or the .sql filter ` +
        `stopped matching.`,
    );
    process.exit(1);
  }

  for (const { filename, table, constraint, statement } of audit.violations) {
    console.error(
      `::error file=apps/backend/supabase/migrations/${filename}::${filename} adds ` +
        `${constraint ? `the constraint "${constraint}"` : 'an unnamed CHECK/FK'} to the ` +
        `high-volume table "${table}" without NOT VALID: "${statement}". A single-step ADD ` +
        `CONSTRAINT scans every existing row under a blocking lock — downtime against prod. Split ` +
        `it into "ADD CONSTRAINT ... NOT VALID" (instant) then a separate "VALIDATE CONSTRAINT" ` +
        `(scans under SHARE UPDATE EXCLUSIVE, lets writes through). See ` +
        `docs/backend/migration_locks.md. If this constraint is genuinely safe to validate inline, ` +
        `name it in GRANDFATHERED_VIOLATIONS in this script and say why in the PR.`,
    );
  }
  for (const { filename, table, constraint } of audit.unmatched) {
    console.error(
      `::error::GRANDFATHERED_VIOLATIONS names "${constraint}" on "${table}" in ${filename}, and ` +
        `the scan found no such blocking constraint add there. An entry that matches nothing is ` +
        `cover for nothing — the file was renamed, the SQL was rewritten, or the entry was never ` +
        `right. Correct it or delete it; leaving it is how a list of exemptions stops describing ` +
        `the tree it exempts.`,
    );
  }

  if (audit.violations.length > 0 || audit.unmatched.length > 0) process.exit(1);
  console.log(
    `OK: ${audit.scanned.length} migrations scanned, no guarded-table CHECK/FK added without ` +
      `NOT VALID beyond the ${GRANDFATHERED_VIOLATIONS.length} grandfathered by name.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
