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
/**
 * @param {string} filename
 * @returns {string | null}
 */
export function parseVersion(filename) {
  const match = /^([0-9]+)_.*\.sql$/.exec(filename);
  return match ? match[1] : null;
}

/**
 * @param {readonly string[]} filenames
 * @returns {{ version: string, files: string[] }[]}
 */
export function findDuplicateVersions(filenames) {
  /** @type {Map<string, string[]>} */
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

/// Whether the scan read anything it could have judged.
///
/// Every verdict below is "no duplicate found", which an empty directory
/// satisfies — so a walk pointed at the wrong path, or one that stopped
/// matching `.sql`, reports `OK: 0 migrations` and exits 0. Same shape as the
/// blindness checks the watch and iOS guards carry: a guard that inspected
/// nothing enforces nothing.
/**
 * @param {readonly string[]} filenames every `.sql` the directory holds
 * @returns {string[]} the reasons this scan cannot be trusted, empty when it can
 */
export function scanBlindness(filenames) {
  if (filenames.length === 0) {
    return [
      `no .sql files under ${MIGRATIONS_DIR}, so the uniqueness check below passes over ` +
        'nothing. Either every migration was deleted, or this guard is reading the wrong ' +
        'directory.',
    ];
  }
  const versioned = filenames.filter((f) => parseVersion(f) !== null);
  if (versioned.length === 0) {
    return [
      `none of the ${filenames.length} .sql file(s) under ${MIGRATIONS_DIR} carries a leading ` +
        'version key, so no two of them can collide and this check has nothing to compare. ' +
        'The Supabase CLI names migrations `<digits>_<name>.sql`.',
    ];
  }
  return [];
}

function main() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'));
  const blind = scanBlindness(files);
  if (blind.length > 0) {
    for (const reason of blind) console.error(`::error::${reason}`);
    process.exit(1);
  }
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
