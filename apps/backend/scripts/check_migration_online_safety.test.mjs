import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import { MIGRATIONS_DIR } from './check_migration_versions.mjs';
import {
  GRANDFATHER_CUTOFF,
  isAfterCutoff,
  findUnsafeConstraintAdds,
  scanMigrations,
} from './check_migration_online_safety.mjs';

test('isAfterCutoff grandfathers the shipped history, flags newer days', () => {
  // The cutoff itself and everything before it is grandfathered.
  assert.equal(isAfterCutoff('20270422'), false);
  assert.equal(isAfterCutoff('20261210'), false); // #411
  assert.equal(isAfterCutoff('20260728'), false); // #410
  assert.equal(isAfterCutoff('20261207'), false); // #409
  // An older 14-digit migration is still grandfathered (normalised compare, not
  // a naive numeric one that would rank 2026…000002 above the 2027 cutoff).
  assert.equal(isAfterCutoff('20260528000002'), false);
  // A genuinely newer migration is guarded.
  assert.equal(isAfterCutoff('20270423'), true);
  assert.equal(isAfterCutoff('20270422000001'), true); // same-day, added later
  assert.equal(isAfterCutoff('20280101'), true);
});

test('findUnsafeConstraintAdds flags a NOT-VALID-less CHECK on a guarded table', () => {
  const sql = `alter table public.runs
    add constraint runs_activity_type_check
    check (activity_type in ('run', 'walk'));`;
  const findings = findUnsafeConstraintAdds(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
});

test('findUnsafeConstraintAdds flags a NOT-VALID-less FK drop+recreate (the #410 shape)', () => {
  const sql = `alter table runs
    drop constraint runs_user_id_fkey,
    add constraint runs_user_id_fkey
      foreign key (user_id) references auth.users (id) on delete cascade;`;
  const findings = findUnsafeConstraintAdds(sql);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].table, 'runs');
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

test('scanMigrations grandfathers a pre-cutoff violation but catches a post-cutoff one', () => {
  const unsafe = `alter table runs
    add constraint runs_new_check check (distance_m >= 0);`;
  // Same offending SQL, before vs after the cutoff.
  assert.deepEqual(
    scanMigrations([{ filename: '20261207_001_promote.sql', sql: unsafe }]),
    [],
  );
  const caught = scanMigrations([
    { filename: '20270501_001_new_runs_check.sql', sql: unsafe },
  ]);
  assert.equal(caught.length, 1);
  assert.equal(caught[0].filename, '20270501_001_new_runs_check.sql');
  assert.equal(caught[0].table, 'runs');
});

test('the committed migrations directory is clean under the guard', () => {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((filename) => ({
      filename,
      sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
    }));
  assert.deepEqual(scanMigrations(migrations), []);
});

test('the guard would catch a new violation dropped into the real tree', () => {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((filename) => ({
      filename,
      sql: readFileSync(join(MIGRATIONS_DIR, filename), 'utf8'),
    }));
  migrations.push({
    filename: '29990101_001_hypothetical_unsafe.sql',
    sql: `alter table notifications
      add constraint notifications_kind_check check (kind in ('a', 'b'));`,
  });
  const violations = scanMigrations(migrations);
  assert.equal(violations.length, 1);
  assert.equal(violations[0].filename, '29990101_001_hypothetical_unsafe.sql');
  assert.equal(violations[0].table, 'notifications');
});

test('GRANDFATHER_CUTOFF is the max version in the committed tree', () => {
  // If a real migration ever lands with a version > cutoff, this test forces a
  // conscious decision: either it used the NOT VALID two-step (fine) or the
  // cutoff was bumped for it (fine) — but the cutoff must not silently lag.
  const versions = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((f) => (/^([0-9]+)_/.exec(f) || [])[1])
    .filter(Boolean);
  const max = versions.reduce((a, b) => (a > b ? a : b), '');
  assert.equal(max.slice(0, 8) <= GRANDFATHER_CUTOFF, true);
});
