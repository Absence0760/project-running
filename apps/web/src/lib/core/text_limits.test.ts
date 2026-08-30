import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { TEXT_LIMITS, TEXT_LIMIT_CONSTRAINTS } from './text_limits.js';

// Relative to this file's own directory (`apps/web/src/lib/core/`), so it
// resolves the same however the suite is invoked: core → lib → src → web → apps.
const MIGRATIONS = fileURLToPath(
	new URL('../../../../backend/supabase/migrations/', import.meta.url)
);

function migrationsSql(): string {
	return readdirSync(MIGRATIONS)
		.filter((f) => f.endsWith('.sql'))
		.sort()
		.map((f) => readFileSync(join(MIGRATIONS, f), 'utf8'))
		.join('\n');
}

/**
 * The caps in `text_limits.ts` are only useful if they are the SAME numbers the
 * database enforces. A composer capped above the constraint hands the user a
 * 23514 they cannot act on; one capped below silently truncates. So the guard
 * reads the cap out of the migrations rather than restating it.
 *
 * The whole directory, not one file: the registered caps are added by three
 * different migrations, and a guard pointed at one of them can only ever
 * certify the caps that migration happened to contain.
 */
function capsFromMigrations(): Record<string, number> {
	const caps: Record<string, number> = {};
	// `add constraint <name> check (… char_length(<col>) <= <n>) not valid;`
	const re =
		/add\s+constraint\s+(\w+)\s+check\s*\([^;]*?char_length\([^)]*\)\s*<=\s*(\d+)/gi;
	for (const match of migrationsSql().matchAll(re)) caps[match[1]] = Number(match[2]);
	return caps;
}

test('parsed a cap out of the migrations for every registered constraint', () => {
	// Without this the per-key loop below would pass over nothing if the regex
	// ever stopped matching (decisions § 534).
	const caps = capsFromMigrations();
	for (const constraint of Object.values(TEXT_LIMIT_CONSTRAINTS)) {
		assert.ok(constraint in caps, `no CHECK found for ${constraint}`);
	}
});

test('every client cap equals the constraint the database enforces', () => {
	const caps = capsFromMigrations();
	for (const [key, constraint] of Object.entries(TEXT_LIMIT_CONSTRAINTS)) {
		assert.equal(
			caps[constraint],
			TEXT_LIMITS[key as keyof typeof TEXT_LIMITS],
			`${key} vs ${constraint}`
		);
	}
});

test('the migrations emit a VALIDATE for every registered constraint', () => {
	const sql = migrationsSql();
	// `20261124_001` added three NOT VALID caps and never validated any of them,
	// so those rows stayed permanently unchecked until `20270503_001` caught up.
	// A cap this registry claims must be one the database actually enforces on
	// the rows already there.
	for (const constraint of Object.values(TEXT_LIMIT_CONSTRAINTS)) {
		assert.ok(
			sql.includes(`validate constraint ${constraint}`),
			`no VALIDATE for ${constraint}`
		);
	}
});
