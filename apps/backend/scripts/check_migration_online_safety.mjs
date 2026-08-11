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
export const GRANDFATHER_CUTOFF = '20270517';

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
function normaliseVersion(version) {
  return version.length >= 14 ? version.slice(0, 14) : version.padEnd(14, '0');
}

export function isAfterCutoff(version, cutoff = GRANDFATHER_CUTOFF) {
  return normaliseVersion(version) > normaliseVersion(cutoff);
}

function stripSqlComments(sql) {
  return sql.replace(/--[^\n]*/g, ' ').replace(/\/\*[\s\S]*?\*\//g, ' ');
}

// The target table of an `ALTER TABLE [IF EXISTS] [ONLY] [public.]<table> …`.
function alterTargetTable(statement) {
  const match =
    /^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?([a-z0-9_]+)/.exec(
      statement,
    );
  return match ? match[1] : null;
}

// True when the statement adds a CHECK or FK constraint (named or anonymous)
// without the NOT VALID escape hatch.
function addsBlockingConstraint(statement) {
  const adds =
    /\badd\s+(?:constraint\s+[a-z0-9_"]+\s+)?(?:check\s*\(|foreign\s+key\b)/.test(
      statement,
    );
  return adds && !statement.includes('not valid');
}

// Returns the guarded-table constraint violations in one migration's SQL.
export function findUnsafeConstraintAdds(sql) {
  const findings = [];
  const statements = stripSqlComments(sql).split(';');
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
export function scanMigrations(migrations, cutoff = GRANDFATHER_CUTOFF) {
  const violations = [];
  for (const { filename, sql } of migrations) {
    const version = parseVersion(filename);
    if (version === null || !isAfterCutoff(version, cutoff)) continue;
    for (const finding of findUnsafeConstraintAdds(sql)) {
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
  const violations = scanMigrations(migrations);
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
