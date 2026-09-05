#!/usr/bin/env node
// Fail loudly when a migration takes a validating full-table scan on a
// high-volume table under a lock that blocks writers.
//
// Two shapes do that, and the guard grades both.
//
// (a) The single step. A CHECK or FK added in one `ALTER TABLE ... ADD
// CONSTRAINT ...` holds a strong lock while Postgres scans every existing row
// to validate it. On a tiny local / CI database that is invisible; against the
// populated prod `runs` (or `notifications`, `segment_efforts`, ...) it blocks
// readers and writers for the length of the scan — that is downtime.
//
// (b) The two-step written into ONE FILE. `ADD CONSTRAINT ... NOT VALID` is
// instant and `VALIDATE CONSTRAINT` scans under SHARE UPDATE EXCLUSIVE, which
// lets INSERT/UPDATE/DELETE through — but only while nothing stronger is
// already held. `apply-pending-migrations.sh` wraps each file in one `begin;
// ... commit;` (the ledger row has to commit atomically with the SQL, and the
// Supabase CLI wraps a file the same way — it is why `CREATE INDEX
// CONCURRENTLY` errors as apply-time DDL), and a lock taken by DDL is held
// until that transaction ends. So the `ADD`'s own ACCESS EXCLUSIVE — or a
// preceding `DROP CONSTRAINT`, `ADD COLUMN`, `CREATE INDEX`, `CREATE TRIGGER`
// — is still held while the scan runs, and SHARE UPDATE EXCLUSIVE is subsumed
// by it rather than being a downgrade. Same-file, the two-step and the single
// step block writers for the identical duration. Only splitting the `VALIDATE`
// into a LATER migration, in its own transaction, buys anything, and that is
// what docs/backend/migration_locks.md now says.
//
// The full pattern + worked examples live in docs/backend/migration_locks.md.
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
// shipping it anyway"; the normal path is `ADD ... NOT VALID` in one migration
// and `VALIDATE CONSTRAINT` in a LATER one, which needs nothing here. The
// `kind` is part of the key, so an entry vouching for a blocking add does not
// silently also vouch for a same-transaction validate in the same file.
/** @typedef {{ filename: string, kind: ViolationKind, table: string, constraint: string }} Grandfathered */
/** @type {readonly Grandfathered[]} */
export const GRANDFATHERED_VIOLATIONS = [
  { filename: '20260505_001_narrow_union_check_constraints.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_source_check' },
  { filename: '20260601_001_runs_metadata_activity_type_required.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_metadata_activity_type_check' },
  { filename: '20260728_001_cascade_auth_users_fks.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_user_id_fkey' },
  { filename: '20260822_001_jobs_kind_allowlist.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20260823_001_jobs_kind_allowlist_strava_event.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20260825_001_jobs_kind_allowlist_photo_process.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20260903_001_notify_event_rsvp.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20260928_001_gdpr_dsar_closeouts.sql', kind: 'blocking_add', table: 'rate_limits', constraint: 'rate_limits_user_id_fkey' },
  { filename: '20261019_001_event_instance_cancellation.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261024_001_plan_workout_audit_notify.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261026_001_direct_messages.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261101_001_notify_club_post_run_completed.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261130_001_notification_email_channel.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261130_001_notification_email_channel.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261202_001_welcome_email.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261207_001_promote_activity_type_is_dnf.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_activity_type_check' },
  { filename: '20261211_001_consolidate_kind_check_constraints.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20261211_001_consolidate_kind_check_constraints.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261218_001_safety_contacts.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20261219_001_web_push_channel.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270107_001_notify_plan_assigned.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270108_001_email_engagement.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270208_001_achievements.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270210_001_challenge_progress_rpc.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270211_001_notifications_kind_check_reconcile.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270212_001_native_push_channel.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270218_001_auto_hide_reports.sql', kind: 'blocking_add', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270223_001_lifecycle_drip.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270224_001_route_photo_thumbnails.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270301_001_club_photos.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270322_001_routes_fk_alignment.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_route_id_fkey' },
  { filename: '20270410_001_safety_sms_escalation.sql', kind: 'blocking_add', table: 'jobs', constraint: 'jobs_kind_chk' },

  // The `same_txn_validate` half: eleven files that wrote both steps of the
  // two-step, and so scanned under the lock the first step was still holding.
  // Every one was written and reviewed as the ONLINE form — the guard passed
  // them and migration_locks.md called them "far better than the single-step
  // form" — which is why they are grandfathered rather than blamed. They are
  // applied and uneditable; what changes is that the next one fails.
  { filename: '20260621_001_runs_track_url_path_check.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_track_url_path_shape' },
  { filename: '20260622_001_run_photos_storage_path_check.sql', kind: 'same_txn_validate', table: 'run_photos', constraint: 'run_photos_storage_path_shape' },
  { filename: '20260916_001_run_photos_thumb_path_lockdown.sql', kind: 'same_txn_validate', table: 'run_photos', constraint: 'run_photos_thumb_512_path_shape' },
  { filename: '20261127_001_runs_hr_series_url.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_hr_series_url_path_shape' },
  { filename: '20270603_001_async_data_export.sql', kind: 'same_txn_validate', table: 'jobs', constraint: 'jobs_kind_chk' },
  { filename: '20270607_001_data_export_ready_notification.sql', kind: 'same_txn_validate', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270701000001_refund_failed_notification.sql', kind: 'same_txn_validate', table: 'notifications', constraint: 'notifications_kind_check' },
  { filename: '20270704000001_runs_physical_quantity_bounds.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_distance_m_check' },
  { filename: '20270704000001_runs_physical_quantity_bounds.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_duration_s_check' },
  { filename: '20270704000001_runs_physical_quantity_bounds.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_elevation_gain_m_check' },
  { filename: '20270704000002_numeric_bounds_reject_nan.sql', kind: 'same_txn_validate', table: 'segment_efforts', constraint: 'segment_efforts_time_seconds_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'live_run_pings', constraint: 'live_run_pings_lat_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'live_run_pings', constraint: 'live_run_pings_lng_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'live_run_pings', constraint: 'live_run_pings_ele_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'live_run_pings', constraint: 'live_run_pings_distance_m_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'live_run_pings', constraint: 'live_run_pings_elapsed_s_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'live_run_pings', constraint: 'live_run_pings_bpm_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'race_pings', constraint: 'race_pings_lat_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'race_pings', constraint: 'race_pings_lng_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'race_pings', constraint: 'race_pings_distance_m_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'race_pings', constraint: 'race_pings_elapsed_s_check' },
  { filename: '20270705000001_ping_and_meet_point_numeric_bounds.sql', kind: 'same_txn_validate', table: 'race_pings', constraint: 'race_pings_bpm_check' },
  { filename: '20270705000004_never_bounded_integer_columns.sql', kind: 'same_txn_validate', table: 'rate_limits', constraint: 'rate_limits_count_check' },
  { filename: '20270705000004_never_bounded_integer_columns.sql', kind: 'same_txn_validate', table: 'run_photos', constraint: 'run_photos_position_idx_check' },
  { filename: '20270705000004_never_bounded_integer_columns.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_fastest_5k_s_check' },
  { filename: '20270705000004_never_bounded_integer_columns.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_fastest_10k_s_check' },
  { filename: '20270705000004_never_bounded_integer_columns.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_fastest_half_marathon_s_check' },
  { filename: '20270705000004_never_bounded_integer_columns.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_fastest_marathon_s_check' },
];

const ALTER_PREFIX =
  /^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?([a-z0-9_]+)\s*/;

// The target table of an `ALTER TABLE [IF EXISTS] [ONLY] [public.]<table> ...`.
/**
 * @param {string} statement
 * @returns {string | null}
 */
function alterTargetTable(statement) {
  const match = ALTER_PREFIX.exec(statement);
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
  // The first slice still carries `alter table <t>`. Strip it so an action is a
  // bare subcommand and can be read for what lock it takes, not just searched
  // for an ADD.
  actions[0] = actions[0].replace(ALTER_PREFIX, '');
  return actions.map((action) => action.trim()).filter((action) => action !== '');
}

// `VALIDATE CONSTRAINT` is the one ALTER TABLE subcommand in this tree that
// leaves writers running; every other form takes at least SHARE ROW EXCLUSIVE,
// which conflicts with the ROW EXCLUSIVE an INSERT holds. The name is returned
// so the allowlist can key on it, and a quoted identifier arrives blanked by
// the lexer, so it is unnamed here for the same fail-closed reason a quoted
// constraint name is: no entry can ever match it.
/**
 * @param {string} action
 * @returns {{ constraint: string | null } | null}
 */
function validateAction(action) {
  const name = /^validate\s+constraint\s+([a-z0-9_"]+)/.exec(action)?.[1];
  if (name === undefined) return null;
  return { constraint: /^[a-z0-9_]+$/.test(name) ? name : null };
}

// Statements other than ALTER TABLE that take a write-blocking lock on a table
// and hold it to commit: CREATE INDEX takes SHARE, CREATE TRIGGER takes SHARE
// ROW EXCLUSIVE, and both conflict with the SHARE UPDATE EXCLUSIVE a later
// VALIDATE would otherwise scan under. DML is deliberately absent — ROW
// EXCLUSIVE does not conflict with SHARE UPDATE EXCLUSIVE, so a backfill in the
// same file does not escalate the scan.
const CREATE_INDEX_ON =
  /^create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(?:[a-z0-9_"]+\s+)?on\s+(?:only\s+)?(?:public\.)?([a-z0-9_]+)/;
const CREATE_TRIGGER_ON =
  /^create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+.*?\bon\s+(?:public\.)?([a-z0-9_]+)/;

/**
 * @param {string} statement
 * @returns {string | null}
 */
function lockedByCreate(statement) {
  return (
    CREATE_INDEX_ON.exec(statement)?.[1] ?? CREATE_TRIGGER_ON.exec(statement)?.[1] ?? null
  );
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

/** @typedef {'blocking_add' | 'same_txn_validate'} ViolationKind */
/** @typedef {{ kind: ViolationKind, table: string, constraint: string | null, statement: string }} ConstraintFinding */
/** @typedef {{ filename: string, sql: string }} MigrationSource */
/** @typedef {{ filename: string, kind: ViolationKind, table: string, constraint: string | null, statement: string }} ConstraintViolation */
/** @typedef {{ scanned: string[], violations: ConstraintViolation[], unmatched: Grandfathered[] }} Audit */

// Returns the guarded-table lock violations in one migration's SQL: the
// single-step blocking adds, and the VALIDATEs that scan while an earlier
// statement in the same file is still holding a write-blocking lock on the
// same table. The walk is ordered because the second verdict depends on what
// came before — a VALIDATE alone in a file is the online form and passes.
/**
 * @param {string} sql
 * @returns {ConstraintFinding[]}
 * @throws when the SQL cannot be lexed; a verdict over text the lexer could
 *   not read would be a guess.
 */
export function findOnlineSafetyViolations(sql) {
  /** @type {ConstraintFinding[]} */
  const findings = [];
  /** @type {Set<string>} */
  const held = new Set();
  // Literals are blanked as well as split correctly: a `check (note <> 'not
  // valid')` otherwise reads as a statement that carries the escape hatch.
  const statements = splitSqlStatements(sql, { blankLiterals: true });
  for (const raw of statements) {
    const statement = raw.replace(/\s+/g, ' ').trim().toLowerCase();
    if (!statement.startsWith('alter table')) {
      const created = lockedByCreate(statement);
      if (created !== null && GUARDED_TABLES.has(created)) held.add(created);
      continue;
    }
    const table = alterTargetTable(statement);
    if (table === null || !GUARDED_TABLES.has(table)) continue;
    const actions = alterActions(statement);
    // One ALTER TABLE acquires the strongest lock any of its actions needs, for
    // the whole statement — so a VALIDATE sharing a statement with an ADD is
    // scanning under the ADD's lock however the two are ordered.
    const escalatesHere = actions.some((action) => validateAction(action) === null);
    for (const action of actions) {
      const validated = validateAction(action);
      if (validated !== null) {
        if (held.has(table) || escalatesHere) {
          findings.push({
            kind: 'same_txn_validate',
            table,
            constraint: validated.constraint,
            statement: statement.slice(0, 120),
          });
        }
        continue;
      }
      if (isBlockingAdd(action)) {
        findings.push({
          kind: 'blocking_add',
          table,
          constraint: constraintName(action),
          statement: statement.slice(0, 120),
        });
      }
    }
    if (escalatesHere) held.add(table);
  }
  return findings;
}

// An unnamed constraint has no key, so no entry can vouch for it. Folding null
// onto the empty string would let an entry with a blank name exempt every
// anonymous ADD in its file.
/**
 * @param {{ filename: string, kind: ViolationKind, table: string, constraint: string | null }} violation
 * @returns {string | null}
 */
function violationKey({ filename, kind, table, constraint }) {
  return constraint ? `${filename} ${kind} ${table} ${constraint}` : null;
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
      findings = findOnlineSafetyViolations(sql);
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

// If you are reading this because a migration you are WRITING failed, the fix
// is to split it — the file is not applied yet, so it can still be edited.
// GRANDFATHERED_VIOLATIONS is not the other half of a choice: it exists for
// migrations already applied to production, where the schema only moves forward
// and the SQL is uneditable. Every entry in it today is that. Adding one for an
// unmerged file ships the downtime and records that we meant to.
const GRANDFATHER_ADVICE =
  `If this migration is not merged yet, SPLIT IT — that is the fix, and it costs one more file. ` +
  `GRANDFATHERED_VIOLATIONS is for migrations already applied to prod, which cannot be edited; ` +
  `naming an unmerged file there ships the blocking scan on purpose, so it needs the table to be ` +
  `genuinely small despite being in GUARDED_TABLES, and a reason in the PR.`;

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

  for (const { filename, kind, table, constraint, statement } of audit.violations) {
    const named = constraint ? `the constraint "${constraint}"` : 'an unnamed CHECK/FK';
    console.error(
      kind === 'blocking_add'
        ? `::error file=apps/backend/supabase/migrations/${filename}::${filename} adds ${named} ` +
            `to the high-volume table "${table}" without NOT VALID: "${statement}". A single-step ` +
            `ADD CONSTRAINT scans every existing row under a blocking lock — downtime against ` +
            `prod. Split it into "ADD CONSTRAINT ... NOT VALID" here and a separate "VALIDATE ` +
            `CONSTRAINT" in a LATER migration file. See docs/backend/migration_locks.md. ` +
            GRANDFATHER_ADVICE
        : `::error file=apps/backend/supabase/migrations/${filename}::${filename} validates ` +
            `${named} on the high-volume table "${table}" in the same file that already took a ` +
            `write-blocking lock on it: "${statement}". Each migration file is applied inside one ` +
            `transaction, and a lock taken by DDL is held until that transaction ends — so the ` +
            `VALIDATE's SHARE UPDATE EXCLUSIVE is subsumed by the earlier lock, not a downgrade, ` +
            `and the scan blocks writers for its whole length exactly as a single-step ADD would. ` +
            `Move the VALIDATE CONSTRAINT into a LATER migration file, so it runs in its own ` +
            `transaction with no stronger lock held. See docs/backend/migration_locks.md. ` +
            GRANDFATHER_ADVICE,
    );
  }
  for (const { filename, kind, table, constraint } of audit.unmatched) {
    console.error(
      `::error::GRANDFATHERED_VIOLATIONS names "${constraint}" on "${table}" in ${filename} as a ` +
        `${kind}, and the scan found no such violation there. An entry that matches nothing is ` +
        `cover for nothing — the file was renamed, the SQL was rewritten, or the entry was never ` +
        `right. Correct it or delete it; leaving it is how a list of exemptions stops describing ` +
        `the tree it exempts.`,
    );
  }

  if (audit.violations.length > 0 || audit.unmatched.length > 0) process.exit(1);
  console.log(
    `OK: ${audit.scanned.length} migrations scanned, no guarded-table CHECK/FK added without ` +
      `NOT VALID and no VALIDATE scanning under a lock its own file already held, beyond the ` +
      `${GRANDFATHERED_VIOLATIONS.length} grandfathered by name.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
