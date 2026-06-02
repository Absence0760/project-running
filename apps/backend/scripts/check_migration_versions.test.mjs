import { readdirSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  MIGRATIONS_DIR,
  parseVersion,
  findDuplicateVersions,
} from './check_migration_versions.mjs';

test('parseVersion takes only the leading digit run before the first underscore', () => {
  assert.equal(parseVersion('20260601_001_runs_metadata.sql'), '20260601');
  assert.equal(parseVersion('20260528000001_notifications.sql'), '20260528000001');
  // The "_001" suffix is decorative — two _NNN files on the same date collide.
  assert.equal(
    parseVersion('20260601_001_a.sql'),
    parseVersion('20260601_002_b.sql'),
  );
  assert.equal(parseVersion('not_a_migration.sql'), null);
  assert.equal(parseVersion('README.md'), null);
});

test('findDuplicateVersions catches the run-26820381977 collision shape', () => {
  const dupes = findDuplicateVersions([
    '20260601_001_notifications_realtime.sql',
    '20260601_001_runs_metadata_activity_type_required.sql',
    '20260602_001_pg_cron_schedules.sql',
  ]);
  assert.deepEqual(dupes, [
    {
      version: '20260601',
      files: [
        '20260601_001_notifications_realtime.sql',
        '20260601_001_runs_metadata_activity_type_required.sql',
      ],
    },
  ]);
});

test('findDuplicateVersions accepts the 14-digit disambiguation', () => {
  assert.deepEqual(
    findDuplicateVersions([
      '20260601000001_notifications_realtime.sql',
      '20260601_001_runs_metadata_activity_type_required.sql',
      '20260602_001_pg_cron_schedules.sql',
    ]),
    [],
  );
});

test('the committed migrations directory has no duplicate version keys', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'));
  assert.deepEqual(findDuplicateVersions(files), []);
});
