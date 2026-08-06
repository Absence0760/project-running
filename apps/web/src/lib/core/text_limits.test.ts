import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { TEXT_LIMITS, TEXT_LIMIT_CONSTRAINTS } from './text_limits.js';

const MIGRATION =
	'../../../../backend/supabase/migrations/20270502_001_club_and_profile_text_caps.sql';

function migrationSql(): string {
	return readFileSync(new URL(MIGRATION, import.meta.url), 'utf8');
}

/**
 * The caps in `text_limits.ts` are only useful if they are the SAME numbers the
 * database enforces. A composer capped above the constraint hands the user a
 * 23514 they cannot act on; one capped below silently truncates. So the guard
 * reads the cap out of the migration rather than restating it.
 */
function capsFromMigration(): Record<string, number> {
	const caps: Record<string, number> = {};
	// `add constraint <name> check (… char_length(<col>) <= <n>) not valid;`
	const re =
		/add\s+constraint\s+(\w+)\s+check\s*\([^;]*?char_length\([^)]*\)\s*<=\s*(\d+)/gi;
	for (const match of migrationSql().matchAll(re)) caps[match[1]] = Number(match[2]);
	return caps;
}

test('parsed a cap out of the migration for every constraint', () => {
	// Without this the per-key loop below would pass over nothing if the regex
	// ever stopped matching (decisions § 534).
	assert.equal(
		Object.keys(capsFromMigration()).length,
		Object.keys(TEXT_LIMIT_CONSTRAINTS).length
	);
});

test('every client cap equals the constraint the database enforces', () => {
	const caps = capsFromMigration();
	for (const [key, constraint] of Object.entries(TEXT_LIMIT_CONSTRAINTS)) {
		assert.equal(
			caps[constraint],
			TEXT_LIMITS[key as keyof typeof TEXT_LIMITS],
			`${key} vs ${constraint}`
		);
	}
});

test('the migration emits a VALIDATE for every constraint it adds', () => {
	const sql = migrationSql();
	// `20261124_001` added three NOT VALID caps and never validated any of them,
	// so those rows are permanently unchecked. This file must not repeat that.
	for (const constraint of Object.values(TEXT_LIMIT_CONSTRAINTS)) {
		assert.ok(
			sql.includes(`validate constraint ${constraint}`),
			`no VALIDATE for ${constraint}`
		);
	}
});
