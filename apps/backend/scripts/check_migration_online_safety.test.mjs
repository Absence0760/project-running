import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { MIGRATIONS_DIR } from './check_migration_versions.mjs';
import {
  GRANDFATHERED_VIOLATIONS,
  UnlexableMigration,
  auditMigrations,
  findUnsafeConstraintAdds,
} from './check_migration_online_safety.mjs';

function committedMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((filename) => ({
      filename,
      sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
    }));
}

test('findUnsafeConstraintAdds flags a NOT-VALID-less CHECK on a guarded table', () => {
  const sql = `alter table public.runs
    add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk'));`;
  const findings = findUnsafeConstraintAdds(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_activity_type_check');
});

test('findUnsafeConstraintAdds flags a NOT-VALID-less FK drop+recreate (the #410 shape)', () => {
  const sql = `alter table runs
    drop constraint runs_user_id_fkey,
    add constraint runs_user_id_fkey
      foreign key (user_id) references auth.users (id) on delete cascade;`;
  const findings = findUnsafeConstraintAdds(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_user_id_fkey');
});

test('findUnsafeConstraintAdds flags a NOT-VALID-less jobs_kind_chk widening', () => {
  // The #394 shape: a `jobs` kind CHECK widened via bare DROP + ADD CONSTRAINT,
  // which blocks the continuously-polled job queue while every row validates.
  const sql = `alter table public.jobs drop constraint jobs_kind_chk;
    alter table public.jobs
      add constraint jobs_kind_chk
      check (kind in ('map_match', 'new_kind'));`;
  const findings = findUnsafeConstraintAdds(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'jobs');
  assert.equal(findings[0].constraint, 'jobs_kind_chk');
});

test('findUnsafeConstraintAdds passes a NOT VALID jobs_kind_chk widening', () => {
  const sql = `alter table public.jobs drop constraint jobs_kind_chk;
    alter table public.jobs
      add constraint jobs_kind_chk
      check (kind in ('map_match', 'new_kind')) not valid;
    alter table public.jobs validate constraint jobs_kind_chk;`;
  assert.deepEqual(findUnsafeConstraintAdds(sql), []);
});

test('findUnsafeConstraintAdds flags a bare ADD beside a NOT VALID one in the same ALTER', () => {
  // NOT VALID qualifies only the action it terminates. Testing the whole
  // statement for it exempted every sibling action in the same
  // comma-separated list, so the second ADD here took a validating scan of
  // every row in `runs` while the guard reported the migration clean.
  const sql = `alter table runs
    add constraint runs_distance_check check (distance_m >= 0) not valid,
    add constraint runs_duration_check check (duration_s >= 0);`;
  const findings = findUnsafeConstraintAdds(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_duration_check');
});

test('findUnsafeConstraintAdds reports BOTH bare ADDs in one ALTER, not just the first', () => {
  // Each action is its own violation and its own allowlist key, so a statement
  // that adds two blocking constraints cannot be exempted by naming one.
  const sql = `alter table runs
    add constraint runs_distance_check check (distance_m >= 0),
    add constraint runs_duration_check check (duration_s >= 0);`;
  const findings = findUnsafeConstraintAdds(sql);
  assert.deepEqual(
    findings.map((f) => f.constraint),
    ['runs_distance_check', 'runs_duration_check'],
  );
});

test('findUnsafeConstraintAdds passes a multi-action ALTER whose every ADD is NOT VALID', () => {
  const sql = `alter table runs
    add constraint runs_distance_check check (distance_m >= 0) not valid,
    add constraint runs_duration_check check (duration_s >= 0) not valid;`;
  assert.deepEqual(findUnsafeConstraintAdds(sql), []);
});

test('findUnsafeConstraintAdds does not split an action on a comma inside its parens', () => {
  // The commas in the IN-list and in a multi-column FK are not action
  // separators; cutting there would strand the trailing NOT VALID.
  const check = `alter table runs
    add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk', 'hike')) not valid;`;
  assert.deepEqual(findUnsafeConstraintAdds(check), []);
  const fk = `alter table run_kudos
    add constraint run_kudos_run_user_fkey
    foreign key (run_id, user_id) references runs (id, user_id) not valid;`;
  assert.deepEqual(findUnsafeConstraintAdds(fk), []);
});

test('findUnsafeConstraintAdds passes the NOT VALID two-step', () => {
  const notValid = `alter table runs
    add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk')) not valid;`;
  assert.deepEqual(findUnsafeConstraintAdds(notValid), []);
  // The later VALIDATE step is not an ADD, so it never trips either.
  const validate = `alter table runs validate constraint runs_activity_type_check;`;
  assert.deepEqual(findUnsafeConstraintAdds(validate), []);
});

test('an anonymous constraint is named null, so no allowlist entry can match it', () => {
  const findings = findUnsafeConstraintAdds(
    'alter table runs add check (distance_m >= 0);',
  );
  assert.equal(findings.length, 1);
  assert.equal(findings[0].constraint, null);
  const { violations } = auditMigrations(
    [{ filename: '29990101_001_anon.sql', sql: 'alter table runs add check (distance_m >= 0);' }],
    [{ filename: '29990101_001_anon.sql', table: 'runs', constraint: '' }],
  );
  assert.equal(violations.length, 1);
});

test('findUnsafeConstraintAdds ignores small, unguarded config tables', () => {
  const sql = `alter table event_pricing
    add constraint event_pricing_modality_check
    check (modality in ('in_person', 'virtual'));`;
  assert.deepEqual(findUnsafeConstraintAdds(sql), []);
});

test('findUnsafeConstraintAdds ignores ADD COLUMN and inline CREATE TABLE checks', () => {
  const addColumn = `alter table runs add column is_dnf boolean not null default false;`;
  assert.deepEqual(findUnsafeConstraintAdds(addColumn), []);
  const createTable = `create table runs (
    id uuid primary key,
    activity_type text check (activity_type in ('run', 'walk')));`;
  assert.deepEqual(findUnsafeConstraintAdds(createTable), []);
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
  const findings = findUnsafeConstraintAdds(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
  assert.equal(findings[0].constraint, 'runs_note_chk');
});

test('a NOT VALID spelled inside a string literal vouches for nothing', () => {
  const findings = findUnsafeConstraintAdds(
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
  assert.deepEqual(findUnsafeConstraintAdds(sql), []);
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
    [{ filename: '20260101_001_legacy.sql', table: 'runs', constraint: 'runs_a_chk' }],
  );
  assert.deepEqual(unmatched, []);
  assert.deepEqual(
    violations.map((v) => `${v.table}.${v.constraint}`),
    ['runs.runs_b_chk', 'jobs.jobs_kind_chk'],
  );
});

test('an allowlist entry naming the wrong file, table or constraint exempts nothing and is reported', () => {
  const sql = `alter table runs add constraint runs_a_chk check (a >= 0);`;
  for (const entry of [
    { filename: '20260101_002_other.sql', table: 'runs', constraint: 'runs_a_chk' },
    { filename: '20260101_001_legacy.sql', table: 'notifications', constraint: 'runs_a_chk' },
    { filename: '20260101_001_legacy.sql', table: 'runs', constraint: 'runs_typo_chk' },
  ]) {
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
    add constraint notifications_kind_check check (kind in ('a', 'b')) not valid;
    alter table notifications validate constraint notifications_kind_check;`;
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
