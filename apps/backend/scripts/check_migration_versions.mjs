#!/usr/bin/env node
// Fail loudly if two migration files parse to the same Supabase version key.
//
// The Supabase CLI derives a migration's version from the leading run of
// digits before the first underscore (`^([0-9]+)_`), NOT from the whole
// filename. So `20260601_001_a.sql` and `20260601_001_b.sql` BOTH parse to
// version `20260601` and collide on `supabase_migrations.schema_migrations`'s
// primary key — `supabase start` dies mid-apply with a cryptic
// "duplicate key value violates unique constraint schema_migrations_pkey"
// (run 26820381977, which took down five jobs at the slow stack-start step
// before anyone could see why). The `_NNN` suffix is decorative: it is not
// part of the version, so a second migration on a given date must use the
// 14-digit `YYYYMMDDHHMMSS` form (e.g. `20260601000001_...`) to stay unique.
//
// This guard replicates the CLI's parse and fails in milliseconds, turning a
// two-minute opaque container failure into an instant, named error at the top
// of the pipeline. Keep it ahead of `supabase start` in CI.

import { readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const MIGRATIONS_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'supabase',
  'migrations',
);

// Mirror of the Supabase CLI's migration-version regex: the leading digit run
// up to (and consumed by) the first underscore. Returns null for a filename
// that is not a versioned migration so the caller can ignore it.
export function parseVersion(filename) {
  const match = /^([0-9]+)_.*\.sql$/.exec(filename);
  return match ? match[1] : null;
}

export function findDuplicateVersions(filenames) {
  const byVersion = new Map();
  for (const name of filenames) {
    const version = parseVersion(name);
    if (version === null) continue;
    const bucket = byVersion.get(version);
    if (bucket) bucket.push(name);
    else byVersion.set(version, [name]);
  }
  return [...byVersion.entries()]
    .filter(([, files]) => files.length > 1)
    .map(([version, files]) => ({ version, files: files.sort() }));
}

function main() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'));
  const duplicates = findDuplicateVersions(files);
  if (duplicates.length === 0) {
    console.log(`OK: ${files.length} migrations, all version keys unique.`);
    return;
  }
  for (const { version, files: clashing } of duplicates) {
    console.error(
      `::error::Migration version "${version}" is claimed by ${clashing.length} files: ${clashing.join(', ')}. ` +
        `The Supabase CLI parses only the leading digits before the first underscore as the version, so the ` +
        `"_NNN" suffix does NOT disambiguate them — supabase start will fail with a schema_migrations_pkey ` +
        `collision. Rename all but one to the 14-digit YYYYMMDDHHMMSS form (e.g. ${version}000001_...).`,
    );
  }
  process.exit(1);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
