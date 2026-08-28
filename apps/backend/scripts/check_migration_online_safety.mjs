#!/usr/bin/env node
// Fail loudly if a NEW migration adds a CHECK or FOREIGN KEY constraint to a
// high-volume table without the online-safe `NOT VALID` two-step.
//
// Adding a CHECK or FK in a single `ALTER TABLE … ADD CONSTRAINT …` holds a
// strong lock while Postgres scans every existing row to validate it. On a
// tiny local / CI database that is invisible; against the populated prod
// `runs` (or `notifications`, `segment_efforts`, …) it blocks readers and
// writers for the length of the scan — that is downtime. The online form is
// `ADD CONSTRAINT … NOT VALID` (instant, no scan) followed by a separate
// `VALIDATE CONSTRAINT` (scans under the weaker SHARE UPDATE EXCLUSIVE lock,
// which lets writes through). The full pattern + worked examples live in
// docs/backend/migration_locks.md.
//
// This guard is deliberately NARROW to stay low-false-positive:
//   * It only inspects migrations NEWER than GRANDFATHER_CUTOFF, so the whole
//     shipped history — including the #409/#410/#411 migrations the playbook
//     cites as what-NOT-to-do — is grandfathered and never trips.
//   * It only flags constraints on GUARDED_TABLES (the high-volume / unbounded
//     tables the migration-locks audit names). A NOT-VALID-less CHECK on a
//     small, bounded config table (event_pricing, fundraisers, race_listings,
//     …) is harmless ceremony to demand, so those are not guarded.
//
// Run locally: node apps/backend/scripts/check_migration_online_safety.mjs

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { MIGRATIONS_DIR, parseVersion } from './check_migration_versions.mjs';
import { splitSqlStatements } from './sql_lex.mjs';

// Every migration at or below this version predates the migration-locks
// playbook and is grandfathered. Bump this ONLY when you deliberately and
// reviewably ship a guarded-table constraint the blocking way (and say why in
// the PR) — the normal path is the NOT VALID + VALIDATE two-step, which passes
// this guard without any change here.
// 20270430: public_runs view redefinition only (watch_workout denylist entry)
// — no constraint, no guarded-table DDL; the scanner passed it with zero
// violations before this bump.
// 20270501: run_streaks_for_user() RPC only (create function + grant/revoke)
// — no table DDL of any kind; the scanner passed it with zero violations
// before this bump.
// 20270502: length CHECKs on clubs.name / description / location_label and
// user_profiles.display_name. Neither table is in GUARDED_TABLES, and the
// migration takes the NOT VALID + VALIDATE two-step anyway, so the scanner
// passed it with zero violations before this bump.
// 20270503: length CHECKs on the remaining 52 user-writable free-text columns,
// plus the three VALIDATEs 20261124_001 never emitted. None of the 26 tables it
// touches is in GUARDED_TABLES, every ADD takes the NOT VALID two-step, and a
// bare VALIDATE takes SHARE UPDATE EXCLUSIVE (reads and writes pass), so the
// scanner passed it with zero violations before this bump.
// 20270509: routes.geom_public — a nullable ADD COLUMN with no default (a
// metadata-only flip), a keyset-batched backfill, one GIST index, and function
// bodies. No constraint of any kind, and `routes` is not in GUARDED_TABLES, so
// the scanner passed it with zero violations before this bump.
// 20270510: two new stable functions (gym_workout_summaries,
// gym_has_weighted_sets) with their grants — no table DDL of any kind, so
// the scanner passed it with zero violations before this bump.
// 20270511: user_profiles.ai_disclosure_version — a nullable ADD COLUMN with
// no default (a metadata-only flip), a pairing CHECK added NOT VALID and
// VALIDATEd in the documented two-step, plus function and trigger bodies.
// user_profiles is not in GUARDED_TABLES and the two-step is taken anyway, so
// the scanner passed it with zero violations before this bump.
// 20270512: table grants for the global-segment catalogue pair plus a matching
// UPDATE revoke. Privilege changes only — no table DDL of any kind, so the
// scanner passed it with zero violations before this bump.
// 20270513: replaces the global_segment_leaderboard function body to reduce to
// one row per athlete — no table DDL, so the scanner passed it with zero
// violations before this bump.
// 20270514: replaces refresh_personal_records_for_user and the two statement
// triggers' watch lists, then backfills. The backfill is scoped to the users who
// own a cycle run and refreshes each one's own rows, so there is no table-wide
// rewrite and no constraint of any kind; the scanner passed it with zero
// violations before this bump.
// 20270515: a single EXECUTE grant on an existing function — no table DDL, so
// the scanner passed it with zero violations before this bump.
// 20270516: marks event_results_rerank_trigger SECURITY DEFINER and revokes
// EXECUTE on the re-rank RPC from the client roles. Function body and privileges
// only — no table DDL, so the scanner passed it with zero violations before this
// bump.
// 20270517: re-emits clone_plan_template and assign_plan_to_athlete so both
// carry pace_zone + target_pace_end_sec_per_km. Function bodies only — no table
// DDL of any kind and no backfill, so the scanner passed it with zero
// violations before this bump.
// 20270518: swaps event_pricing's two partial unique indexes for one non-partial
// NULLS NOT DISTINCT index so an upsert can infer an arbiter. Index DDL only —
// no constraint of any kind, and event_pricing is not in GUARDED_TABLES — so the
// scanner passed it with zero violations before this bump.
// 20270519: marks route_markers_set_position and route_conditions_set_position
// SECURITY DEFINER so the BEFORE-INSERT position trigger can read routes.geom
// for a NON-owner contributor, and backfills the rows already written with a
// null position. Function bodies plus two backfill UPDATEs — no constraint or
// index DDL of any kind. Neither route_markers nor route_conditions is in
// GUARDED_TABLES (both are bounded by course markers per route, not by user
// activity), and the UPDATEs are single-statement rather than batched for that
// reason. The scanner passed it with zero violations before this bump.
// 20270520: binds a paid order to the instance it was bought for, splits
// event_attendees' INSERT grant per-column the way 20270102_001 split UPDATE,
// and adds a partial unique index on (order_id). One function body, two grant
// statements and one CREATE INDEX — no ADD CONSTRAINT anywhere, and
// event_attendees is not in GUARDED_TABLES — so the scanner passed it with zero
// violations before this bump.
// 20270521: adds shadow_hidden to heatmap_points_in_bbox' filter, makes the
// challenge-badge insert the serialization point in recompute_challenge_completion,
// and revokes EXECUTE on clip_track_for_user from authenticated. Two function
// bodies and one REVOKE — no table DDL at all, so the scanner passed it with
// zero violations before this bump.
// 20270522: widens enforce_paid_order_for_priced_event and the buyer
// self-cancel RLS policy to accept `partially_refunded` alongside `paid`.
// One function body and one policy — no table DDL at all, so the scanner
// passed it with zero violations before this bump.
// 20270523: re-emits segment_effort_ranks + global_segment_effort_ranks so
// they count one row per athlete, matching their leaderboards. Two function
// bodies — no table DDL at all, so the scanner passed it with zero violations
// before this bump. It deliberately adds no index on segment_efforts (a
// guarded table): the distinct count rides the existing
// (segment_id, time_seconds) range scan.
// 20270524: re-emits five SECURITY DEFINER bodies (two segment boards, the
// challenge board, is_event_visible, claim_event_result) so they honour the
// shadow-hidden gate. Five function bodies — no table DDL at all, so the
// scanner passed it with zero violations before this bump.
// 20270525: drops and recreates gym_exercise_set_history and its _batch
// sibling so both return set_type. A changed `returns table` cannot ride
// `create or replace` (42P13), so the drop is forced — but it touches
// pg_proc only, takes no lock on any table, and the migration transaction
// makes the swap atomic for concurrent callers. Two function bodies, no
// table DDL, so the scanner passed it with zero violations before this bump.
// 20270526: re-emits clubs_member_count_trigger + routes_run_count_trigger so
// both recompute their cache from the authoritative query instead of applying
// ±1 deltas, adds the two refresher functions they call, and reconciles the
// rows the delta form already got wrong. Four function bodies plus two
// backfills — no table DDL and no constraint, so the scanner passed it with
// zero violations before this bump. The clubs reconcile is one scoped UPDATE
// over a small bounded table; the routes reconcile walks keyset batches of 500
// so no single statement holds row locks across the table, and the refresher
// no-ops when the cache already agrees, so only drifted rows are written.
// 20270527: recreates search_public_events so the one-off weekday branch
// derives its ISO day in the EVENT's timezone rather than the caller's session
// timezone, matching the sibling p_time filter. One function body, no table DDL
// and no constraint, so the scanner passes it with zero violations after this
// bump too — a same-day 12-character version still sorts after a bare 8-digit
// cutoff, so bumping does not exempt it from the scan.
// 20270528: adds the gym_routine_history aggregate RPC so the routine-history
// panel stops reading up to 500 gym_workouts rows just to count them. One
// function body, no table DDL and no constraint, so the scanner passes it with
// zero violations after this bump too.
// 20270529: adds the delete_notifications(uuid[]) RPC so a bulk dismiss is one
// transaction instead of N chunked round-trips. One function body, no table DDL
// and no constraint, so the scanner passes it with zero violations after this
// bump too.
// 20270530: unschedules the refresh-mv-weekly-mileage pg_cron entry and drops
// the unread mv_weekly_mileage matview. `drop materialized view` takes ACCESS
// EXCLUSIVE on the matview alone (nothing reads it, its index goes with it) and
// no lock on `runs`; the unschedule writes one row of the small cron.job table.
// No constraint, no guarded-table DDL, so the scanner passes it with zero
// violations after this bump too.
//
// Bumped to 20270603 for 20270603_001_async_data_export.sql, which DOES touch a
// guarded table: it widens `jobs_kind_chk` for the new `data_export` kind. It
// takes the NOT VALID + VALIDATE two-step, so it would pass the scanner on its
// merits — the bump is the max-version bookkeeping this file's own test
// enforces, not an exemption. Worth noting for whoever adds the next job kind:
// every earlier kind migration used the single-step drop-and-recreate, which is
// a full scan of the queue under ACCESS EXCLUSIVE for a widen that cannot
// invalidate a single existing row. Those are grandfathered; new ones are not.
//
// Bumped to 20270605 for 20270605_001_withdraw_health_consent_keeps_age_record.sql,
// which is a bare `create or replace function` body (plus its grant/revoke pair)
// on top of 20270418_001 — no table DDL of any kind and no constraint, so the
// scanner passes it with zero violations after this bump too.
//
// Bumped to 20270606 for 20270606_001_segment_leaderboard_age_band_consent.sql,
// which puts the two segment boards' age band behind health_data_consent_at
// (§ 718 open item 2, now § 727). Two bare `create or replace function` bodies
// re-emitted from 20270524_001 with one predicate added at each of their two
// age sites — no table DDL of any kind and no constraint, so the scanner passes
// it with zero violations after this bump too. Both bodies join `segment_efforts`
// / `global_segment_efforts`, which ARE guarded tables, but a SELECT inside a
// function body is not ALTER TABLE and takes no DDL lock; the scanner only
// inspects `alter table` statements, so the join is invisible to it either way.
// Bumped to 20270607 for 20270607_001_data_export_ready_notification.sql, which
// DOES touch a guarded table: it widens `notifications_kind_check` for the new
// `data_export_ready` kind. It takes the NOT VALID + VALIDATE two-step, so it
// would pass the scanner on its merits — the bump is the max-version
// bookkeeping this file's own test enforces, not an exemption. It is the first
// `notifications` kind widen to take the two-step; all twelve before it
// (20260903_001 through 20270218_001) dropped and recreated the CHECK in one
// statement, which scans every notification ever written under ACCESS EXCLUSIVE
// for a widen that cannot invalidate a single existing row. Those are
// grandfathered; new ones are not. The migration's other DDL is a nullable
// `data_export_jobs.notified_at` ADD COLUMN with no default (catalogue-only, and
// the table is not guarded) plus one function body.
// Bumped to 20270608 for 20270608_001_direct_message_rate_limit.sql, which
// adds a BEFORE INSERT trigger + its function to `direct_messages`. No
// constraint of any kind, and `direct_messages` is not in GUARDED_TABLES, so
// the scanner passes it with zero violations after this bump too — the bump is
// the max-version bookkeeping this file's own test enforces, not an exemption.
// The lock it does take is out of the scanner's remit and is reasoned about in
// the migration's own header: CREATE TRIGGER holds SHARE ROW EXCLUSIVE, which
// pauses concurrent writes to that one table for a catalogue-only O(1) change
// and never blocks a reader.
// Bumped to 20270609 for
// 20270609_001_segment_effort_ranks_anon_reachable.sql, which re-emits the two
// rank RPC bodies to call private.viewer_blocks instead of naming
// is_blocked_either_way (whose anon EXECUTE grant 20261108_001 revoked, making
// both 42501 for a logged-out caller since 20270523_001) and grants anon
// EXECUTE on the catalogue twin. Two function bodies plus one grant — no table
// DDL, no constraint, so the scanner passes it with zero violations after this
// bump too; the bump is the max-version bookkeeping this file's own test
// enforces, not an exemption.
// Bumped to 20270610 for
// 20270610_001_challenge_create_rate_limit_shared_helper.sql, which is a single
// CREATE OR REPLACE FUNCTION re-emitting the create_challenge throttle trigger's
// body to call enforce_create_rate_limit instead of raising its own bare string.
// Replacing the function rather than the trigger takes no lock on challenges at
// all: no table DDL, no constraint, no backfill, so the scanner passes it with
// zero violations after this bump too. Same bookkeeping, not an exemption.
// Bumped to 20270615 for 20270615_001_challenge_goal_check.sql, which adds
// challenges_goal_ck. `challenges` is not in GUARDED_TABLES, and the migration
// takes the two-step online-safe form anyway: the constraint is added NOT VALID
// (a catalogue-only O(1) change under ACCESS EXCLUSIVE) and validated in a
// separate statement under SHARE UPDATE EXCLUSIVE, which blocks no reader and
// no writer. The scanner inspected it under the previous cutoff and returned
// zero violations, so this bump is the max-version bookkeeping this file's own
// test enforces, not an exemption.
export const GRANDFATHER_CUTOFF = '20270619';

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

// The CLI's version key is the leading digit run; normalise the 8-digit
// `YYYYMMDD` and 14-digit `YYYYMMDDHHMMSS` forms to one comparable width so
// string comparison is monotonic across both (a same-day 14-digit migration
// sorts AFTER the bare 8-digit day, an earlier day sorts before).
/**
 * @param {string} version
 * @returns {string}
 */
function normaliseVersion(version) {
  return version.length >= 14 ? version.slice(0, 14) : version.padEnd(14, '0');
}

/**
 * @param {string} version
 * @param {string} [cutoff]
 * @returns {boolean}
 */
export function isAfterCutoff(version, cutoff = GRANDFATHER_CUTOFF) {
  return normaliseVersion(version) > normaliseVersion(cutoff);
}

// The target table of an `ALTER TABLE [IF EXISTS] [ONLY] [public.]<table> …`.
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

// True when the statement adds a CHECK or FK constraint (named or anonymous)
// without the NOT VALID escape hatch.
/**
 * @param {string} statement
 * @returns {boolean}
 */
function addsBlockingConstraint(statement) {
  return alterActions(statement).some(
    (action) =>
      /\badd\s+(?:constraint\s+[a-z0-9_"]+\s+)?(?:check\s*\(|foreign\s+key\b)/.test(
        action,
      ) && !action.includes('not valid'),
  );
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

/** @typedef {{ table: string, statement: string }} ConstraintFinding */
/** @typedef {{ filename: string, sql: string }} MigrationSource */
/** @typedef {{ filename: string, table: string, statement: string }} ConstraintViolation */

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
    if (!addsBlockingConstraint(statement)) continue;
    findings.push({ table, statement: statement.slice(0, 120) });
  }
  return findings;
}

// Every guarded-table violation across a set of {filename, sql} migrations
// newer than the cutoff.
/**
 * @param {readonly MigrationSource[]} migrations
 * @param {string} [cutoff]
 * @returns {ConstraintViolation[]}
 * @throws an {@link UnlexableMigration} naming the file whose SQL could not be
 *   read. Skipping it instead would report the whole tree clean over a file
 *   nothing inspected.
 */
export function scanMigrations(migrations, cutoff = GRANDFATHER_CUTOFF) {
  /** @type {ConstraintViolation[]} */
  const violations = [];
  for (const { filename, sql } of migrations) {
    const version = parseVersion(filename);
    if (version === null || !isAfterCutoff(version, cutoff)) continue;
    /** @type {ConstraintFinding[]} */
    let findings;
    try {
      findings = findUnsafeConstraintAdds(sql);
    } catch (cause) {
      throw new UnlexableMigration(filename, cause);
    }
    for (const finding of findings) {
      violations.push({ filename, ...finding });
    }
  }
  return violations;
}

function main() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'));
  const migrations = files.map((filename) => ({
    filename,
    sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
  }));
  /** @type {ConstraintViolation[]} */
  let violations;
  try {
    violations = scanMigrations(migrations);
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
  if (violations.length === 0) {
    console.log(
      `OK: no guarded-table CHECK/FK added without NOT VALID after ${GRANDFATHER_CUTOFF}.`,
    );
    return;
  }
  for (const { filename, table, statement } of violations) {
    console.error(
      `::error file=apps/backend/supabase/migrations/${filename}::${filename} adds a CHECK/FK to the high-volume ` +
        `table "${table}" without NOT VALID: "${statement}…". A single-step ADD CONSTRAINT scans every existing ` +
        `row under a blocking lock — downtime against prod. Split it into "ADD CONSTRAINT … NOT VALID" (instant) ` +
        `then a separate "VALIDATE CONSTRAINT" (scans under SHARE UPDATE EXCLUSIVE, lets writes through). See ` +
        `docs/backend/migration_locks.md. If this constraint is genuinely safe to validate inline, bump ` +
        `GRANDFATHER_CUTOFF in this script and say why in the PR.`,
    );
  }
  process.exit(1);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
