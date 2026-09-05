import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { MIGRATIONS_DIR } from './check_migration_versions.mjs';
import {
  GRANDFATHERED_VIOLATIONS,
  UnlexableMigration,
  auditMigrations,
  findOnlineSafetyViolations,
} from './check_migration_online_safety.mjs';

function committedMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((filename) => ({
      filename,
      sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
    }));
}

test('findOnlineSafetyViolations flags a NOT-VALID-less CHECK on a guarded table', () => {
  const sql = `alter table public.runs
    add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk'));`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_activity_type_check');
});

test('findOnlineSafetyViolations flags a NOT-VALID-less FK drop+recreate (the #410 shape)', () => {
  const sql = `alter table runs
    drop constraint runs_user_id_fkey,
    add constraint runs_user_id_fkey
      foreign key (user_id) references auth.users (id) on delete cascade;`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_user_id_fkey');
});

test('findOnlineSafetyViolations flags a NOT-VALID-less jobs_kind_chk widening', () => {
  // The #394 shape: a `jobs` kind CHECK widened via bare DROP + ADD CONSTRAINT,
  // which blocks the continuously-polled job queue while every row validates.
  const sql = `alter table public.jobs drop constraint jobs_kind_chk;
    alter table public.jobs
      add constraint jobs_kind_chk
      check (kind in ('map_match', 'new_kind'));`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'jobs');
  assert.equal(findings[0].constraint, 'jobs_kind_chk');
});

test('findOnlineSafetyViolations passes the ADD half of a jobs_kind_chk widening', () => {
  const sql = `alter table public.jobs drop constraint jobs_kind_chk;
    alter table public.jobs
      add constraint jobs_kind_chk
      check (kind in ('map_match', 'new_kind')) not valid;`;
  assert.deepEqual(findOnlineSafetyViolations(sql), []);
});

test('findOnlineSafetyViolations flags a bare ADD beside a NOT VALID one in the same ALTER', () => {
  // NOT VALID qualifies only the action it terminates. Testing the whole
  // statement for it exempted every sibling action in the same
  // comma-separated list, so the second ADD here took a validating scan of
  // every row in `runs` while the guard reported the migration clean.
  const sql = `alter table runs
    add constraint runs_distance_check check (distance_m >= 0) not valid,
    add constraint runs_duration_check check (duration_s >= 0);`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_duration_check');
});

test('findOnlineSafetyViolations reports BOTH bare ADDs in one ALTER, not just the first', () => {
  // Each action is its own violation and its own allowlist key, so a statement
  // that adds two blocking constraints cannot be exempted by naming one.
  const sql = `alter table runs
    add constraint runs_distance_check check (distance_m >= 0),
    add constraint runs_duration_check check (duration_s >= 0);`;
  const findings = findOnlineSafetyViolations(sql);
  assert.deepEqual(
    findings.map((f) => f.constraint),
    ['runs_distance_check', 'runs_duration_check'],
  );
});

test('findOnlineSafetyViolations passes a multi-action ALTER whose every ADD is NOT VALID', () => {
  const sql = `alter table runs
    add constraint runs_distance_check check (distance_m >= 0) not valid,
    add constraint runs_duration_check check (duration_s >= 0) not valid;`;
  assert.deepEqual(findOnlineSafetyViolations(sql), []);
});

test('findOnlineSafetyViolations does not split an action on a comma inside its parens', () => {
  // The commas in the IN-list and in a multi-column FK are not action
  // separators; cutting there would strand the trailing NOT VALID.
  const check = `alter table runs
    add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk', 'hike')) not valid;`;
  assert.deepEqual(findOnlineSafetyViolations(check), []);
  const fk = `alter table run_kudos
    add constraint run_kudos_run_user_fkey
    foreign key (run_id, user_id) references runs (id, user_id) not valid;`;
  assert.deepEqual(findOnlineSafetyViolations(fk), []);
});

test('findOnlineSafetyViolations passes the NOT VALID two-step', () => {
  const notValid = `alter table runs
    add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk')) not valid;`;
  assert.deepEqual(findOnlineSafetyViolations(notValid), []);
  // The later VALIDATE step is not an ADD, so it never trips either.
  const validate = `alter table runs validate constraint runs_activity_type_check;`;
  assert.deepEqual(findOnlineSafetyViolations(validate), []);
});

test('an anonymous constraint is named null, so no allowlist entry can match it', () => {
  const findings = findOnlineSafetyViolations(
    'alter table runs add check (distance_m >= 0);',
  );
  assert.equal(findings.length, 1);
  assert.equal(findings[0].constraint, null);
  const { violations } = auditMigrations(
    [{ filename: '29990101_001_anon.sql', sql: 'alter table runs add check (distance_m >= 0);' }],
    [{ filename: '29990101_001_anon.sql', kind: 'blocking_add', table: 'runs', constraint: '' }],
  );
  assert.equal(violations.length, 1);
});

test('findOnlineSafetyViolations ignores small, unguarded config tables', () => {
  const sql = `alter table event_pricing
    add constraint event_pricing_modality_check
    check (modality in ('in_person', 'virtual'));`;
  assert.deepEqual(findOnlineSafetyViolations(sql), []);
});

test('findOnlineSafetyViolations ignores ADD COLUMN and inline CREATE TABLE checks', () => {
  const addColumn = `alter table runs add column is_dnf boolean not null default false;`;
  assert.deepEqual(findOnlineSafetyViolations(addColumn), []);
  const createTable = `create table runs (
    id uuid primary key,
    activity_type text check (activity_type in ('run', 'walk')));`;
  assert.deepEqual(findOnlineSafetyViolations(createTable), []);
});

// The four below are the shapes a `;` split and a comment-strip that ran
// before it got wrong. Two of them are FALSE NEGATIVES on the guarded tables
// this file exists to protect — the filing that reported the parser said it
// "fails in the safe direction", and it does not.
test('a `--` inside a literal cannot borrow the next statement\'s NOT VALID', () => {
  const sql = [
    "alter table runs add constraint runs_note_chk check (note not like '%--%');",
    'alter table runs add constraint runs_v_chk check (v > 0) not valid;',
  ].join('\n');
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_note_chk');
});

test('a NOT VALID spelled inside a string literal vouches for nothing', () => {
  const findings = findOnlineSafetyViolations(
    "alter table runs add constraint runs_state_chk check (state <> 'not valid');",
  );
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
});

test('DDL inside a function body is not the migration taking the lock', () => {
  const sql = [
    'create or replace function rebuild() returns void language plpgsql as $$',
    'begin',
    "  insert into audit(note) values ('ran; ok');",
    "  alter table notifications add constraint notifications_kind_check check (kind in ('a','b'));",
    'end;',
    '$$;',
  ].join('\n');
  assert.deepEqual(findOnlineSafetyViolations(sql), []);
});

test('a migration whose SQL does not lex is named, not skipped', () => {
  assert.throws(
    () =>
      auditMigrations([{ filename: '29990101_001_broken.sql', sql: "select 'unclosed" }]),
    (/** @type {unknown} */ error) =>
      error instanceof UnlexableMigration &&
      error.filename === '29990101_001_broken.sql' &&
      /unterminated string literal/.test(error.message),
  );
});

test('the allowlist exempts the one constraint it names and nothing else', () => {
  const sql = `alter table runs add constraint runs_a_chk check (a >= 0);
    alter table runs add constraint runs_b_chk check (b >= 0);
    alter table jobs add constraint jobs_kind_chk check (kind in ('x'));`;
  const { violations, unmatched } = auditMigrations(
    [{ filename: '20260101_001_legacy.sql', sql }],
    [{ filename: '20260101_001_legacy.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_a_chk' }],
  );
  assert.deepEqual(unmatched, []);
  assert.deepEqual(
    violations.map((v) => `${v.table}.${v.constraint}`),
    ['runs.runs_b_chk', 'jobs.jobs_kind_chk'],
  );
});

test('an allowlist entry naming the wrong file, table or constraint exempts nothing and is reported', () => {
  const sql = `alter table runs add constraint runs_a_chk check (a >= 0);`;
  /** @type {readonly import('./check_migration_online_safety.mjs').Grandfathered[]} */
  const wrong = [
    { filename: '20260101_002_other.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_a_chk' },
    { filename: '20260101_001_legacy.sql', kind: 'blocking_add', table: 'notifications', constraint: 'runs_a_chk' },
    { filename: '20260101_001_legacy.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_typo_chk' },
    { filename: '20260101_001_legacy.sql', kind: 'same_txn_validate', table: 'runs', constraint: 'runs_a_chk' },
  ];
  for (const entry of wrong) {
    const { violations, unmatched } = auditMigrations(
      [{ filename: '20260101_001_legacy.sql', sql }],
      [entry],
    );
    assert.equal(violations.length, 1, JSON.stringify(entry));
    assert.deepEqual(unmatched, [entry]);
  }
});

test('a new migration is scanned without any edit to the allowlist', () => {
  // The property the GRANDFATHER_CUTOFF design could not hold: a migration
  // newer than everything committed is inspected as it stands, and the guard
  // needs no bookkeeping change to see it. Under the cutoff, the bump that its
  // own test demanded was also what removed the file from the scan.
  const unsafe = `alter table notifications
    add constraint notifications_kind_check check (kind in ('a', 'b'));`;
  const { violations } = auditMigrations([
    { filename: '29990101_001_new_kind.sql', sql: unsafe },
  ]);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].filename, '29990101_001_new_kind.sql');
  assert.equal(violations[0].table, 'notifications');

  const safe = `alter table notifications
    add constraint notifications_kind_check check (kind in ('a', 'b')) not valid;`;
  assert.deepEqual(
    auditMigrations([{ filename: '29990101_001_new_kind.sql', sql: safe }]).violations,
    [],
  );
});

test('the scanned set is the WHOLE committed tree, never empty', () => {
  // This is the assertion the retired "GRANDFATHER_CUTOFF is the max version in
  // the committed tree" test made impossible: that test forced the cutoff at or
  // above the newest migration, which left the scan with nothing to read. A
  // guard reporting a clean tree over an empty set says nothing at all, so the
  // count is asserted rather than the verdict.
  const migrations = committedMigrations();
  const { scanned } = auditMigrations(migrations);
  assert.ok(scanned.length > 400, `expected the whole tree, scanned ${scanned.length}`);
  assert.deepEqual(scanned, migrations.map((m) => m.filename));
});

test('the committed migrations directory is clean under the guard', () => {
  const { violations, unmatched } = auditMigrations(committedMigrations());
  assert.deepEqual(violations, []);
  assert.deepEqual(unmatched, []);
});

test('every grandfathered entry still names a real violation in the tree', () => {
  // Dropping one entry must turn the tree red: an entry is cover for exactly
  // one blocking constraint that is really there, so a list that has drifted
  // past the SQL cannot pass.
  const migrations = committedMigrations();
  assert.ok(GRANDFATHERED_VIOLATIONS.length > 0);
  for (const dropped of GRANDFATHERED_VIOLATIONS) {
    const { violations } = auditMigrations(
      migrations,
      GRANDFATHERED_VIOLATIONS.filter((e) => e !== dropped),
    );
    assert.equal(
      violations.length,
      1,
      `dropping ${dropped.constraint} in ${dropped.filename} should expose exactly one violation`,
    );
    assert.equal(violations[0].filename, dropped.filename);
    assert.equal(violations[0].constraint, dropped.constraint);
  }
});

test('the guard would catch a new violation dropped into the real tree', () => {
  const migrations = committedMigrations();
  migrations.push({
    filename: '29990101_001_hypothetical_unsafe.sql',
    sql: `alter table notifications
      add constraint notifications_kind_check check (kind in ('a', 'b'));`,
  });
  const { violations } = auditMigrations(migrations);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].filename, '29990101_001_hypothetical_unsafe.sql');
  assert.equal(violations[0].table, 'notifications');
});

test('a VALIDATE alone in a file is the online form and passes', () => {
  // The half of the two-step that is actually online: its own migration, its
  // own transaction, so the scan runs under SHARE UPDATE EXCLUSIVE with nothing
  // stronger held and writers keep going.
  const sql = 'alter table notifications validate constraint notifications_kind_check;';
  assert.deepEqual(findOnlineSafetyViolations(sql), []);
});

test('a VALIDATE after the ADD in the same file is flagged, not passed', () => {
  // The shape migration_locks.md used to call "far better than the single-step
  // form" and this guard used to look for. One file is one transaction, so the
  // ADD's ACCESS EXCLUSIVE is still held while the VALIDATE scans.
  const sql = `alter table notifications
      add constraint notifications_kind_check check (kind in ('a', 'b')) not valid;
    alter table notifications validate constraint notifications_kind_check;`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].kind, 'same_txn_validate');
  assert.equal(findings[0].table, 'notifications');
  assert.equal(findings[0].constraint, 'notifications_kind_check');
});

test('a VALIDATE after a DROP CONSTRAINT in the same file is flagged', () => {
  const sql = `alter table jobs drop constraint jobs_kind_chk;
    alter table jobs add constraint jobs_kind_chk check (kind in ('x')) not valid;
    alter table jobs validate constraint jobs_kind_chk;`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].kind, 'same_txn_validate');
});

test('a VALIDATE after an ADD COLUMN on the same table is flagged', () => {
  // The lock is the table's, not the constraint's: 20261127_001 added a column
  // and then validated, and a rule keyed on constraint DDL alone would miss it.
  const sql = `alter table runs add column hr_series_url text;
    alter table runs validate constraint runs_hr_series_url_path_shape;`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].kind, 'same_txn_validate');
  assert.equal(findings[0].constraint, 'runs_hr_series_url_path_shape');
});

test('a VALIDATE after a CREATE INDEX on the same table is flagged', () => {
  const sql = `create index runs_started_at_idx on public.runs (started_at);
    alter table runs validate constraint runs_distance_m_check;`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].kind, 'same_txn_validate');
});

test('a VALIDATE sharing one ALTER with an ADD is flagged whichever comes first', () => {
  // A single ALTER TABLE takes the strongest lock any of its actions needs, for
  // the whole statement — so writing the VALIDATE first buys nothing.
  const sql = `alter table runs
    validate constraint runs_a_chk,
    add constraint runs_b_chk check (b >= 0) not valid;`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].kind, 'same_txn_validate');
  assert.equal(findings[0].constraint, 'runs_a_chk');
});

test('a VALIDATE is not escalated by DDL on a DIFFERENT table', () => {
  // ROW EXCLUSIVE and locks on other relations do not conflict with the scan's
  // SHARE UPDATE EXCLUSIVE. A rule that flagged any busy file would be noise.
  const sql = `alter table jobs add constraint jobs_kind_chk check (kind in ('x')) not valid;
    alter table runs validate constraint runs_distance_m_check;`;
  assert.deepEqual(findOnlineSafetyViolations(sql), []);
});

test('a VALIDATE on an unguarded table is not flagged', () => {
  const sql = `alter table race_listings add column x text;
    alter table race_listings validate constraint race_listings_x_chk;`;
  assert.deepEqual(findOnlineSafetyViolations(sql), []);
});

test('a blocking_add entry does not also exempt a same_txn_validate in its file', () => {
  // The `kind` is in the key precisely so one reviewed exemption cannot quietly
  // cover a second, differently-caused violation in the same file.
  const sql = `alter table runs add constraint runs_a_chk check (a >= 0);
    alter table runs validate constraint runs_a_chk;`;
  const { violations, unmatched } = auditMigrations(
    [{ filename: '20260101_001_legacy.sql', sql }],
    [{ filename: '20260101_001_legacy.sql', kind: 'blocking_add', table: 'runs', constraint: 'runs_a_chk' }],
  );
  assert.deepEqual(unmatched, []);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].kind, 'same_txn_validate');
});

test('a quoted VALIDATE target is unnamed, so no allowlist entry can cover it', () => {
  const sql = `alter table runs add column x text;
    alter table runs validate constraint "Runs_A_Chk";`;
  const findings = findOnlineSafetyViolations(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].constraint, null);
});

test('the grandfathered set covers both violation kinds', () => {
  // The shipped history holds 11 files that wrote both halves of the two-step
  // into one transaction. If the list ever loses that half, the assertion that
  // the tree is clean would be passing over a rule nothing exercises.
  const kinds = new Set(GRANDFATHERED_VIOLATIONS.map((e) => e.kind));
  assert.deepEqual([...kinds].sort(), ['blocking_add', 'same_txn_validate']);
});
