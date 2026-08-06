import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { TEXT_LIMITS, TEXT_LIMIT_CONSTRAINTS } from './text_limits';

const MIGRATION =
	'../backend/supabase/migrations/20270502_001_club_and_profile_text_caps.sql';

/**
 * The caps in `text_limits.ts` are only useful if they are the SAME numbers the
 * database enforces. A composer capped above the constraint hands the user a
 * 23514 they cannot act on; one capped below silently truncates. So the guard
 * reads the cap out of the migration rather than restating it.
 */
function capsFromMigration(): Record<string, number> {
	const sql = readFileSync(new URL(MIGRATION, import.meta.url), 'utf8');
	const caps: Record<string, number> = {};
	// `add constraint <name> check (… char_length(<col>) <= <n>) not valid;`
	const re =
		/add\s+constraint\s+(\w+)\s+check\s*\([^;]*?char_length\([^)]*\)\s*<=\s*(\d+)/gi;
	for (const match of sql.matchAll(re)) caps[match[1]] = Number(match[2]);
	return caps;
}

describe('TEXT_LIMITS vs the database CHECK constraints', () => {
	const caps = capsFromMigration();

	it('parsed a non-empty set of caps out of the migration', () => {
		// Without this the per-key loop below would pass over nothing if the
		// regex ever stopped matching (decisions § 534).
		expect(Object.keys(caps).length).toBe(
			Object.keys(TEXT_LIMIT_CONSTRAINTS).length
		);
	});

	for (const [key, constraint] of Object.entries(TEXT_LIMIT_CONSTRAINTS)) {
		it(`${key} matches ${constraint}`, () => {
			expect(caps[constraint]).toBe(TEXT_LIMITS[key as keyof typeof TEXT_LIMITS]);
		});
	}

	it('the migration emits a VALIDATE for every constraint it adds', () => {
		const sql = readFileSync(new URL(MIGRATION, import.meta.url), 'utf8');
		// `20261124_001` added three NOT VALID caps and never validated any of
		// them, so those rows are permanently unchecked. This file must not
		// repeat that.
		for (const constraint of Object.values(TEXT_LIMIT_CONSTRAINTS)) {
			expect(sql).toContain(`validate constraint ${constraint}`);
		}
	});
});
