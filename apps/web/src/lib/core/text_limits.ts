/**
 * Character caps on user-authored text, stated once per client and enforced by
 * a matching CHECK constraint in the database.
 *
 * Every entry here has a `<table>_<column>_len_chk` in
 * `apps/backend/supabase/migrations/20270502_001_club_and_profile_text_caps.sql`
 * with the same number, and `text_limits.test.ts` parses that file to prove it.
 * A composer that caps lower than the constraint is merely conservative; one
 * that caps higher hands the user a postgres 23514 they cannot act on, which is
 * what web's 600-character club description and mobile's 500 both did against a
 * column that had no constraint at all (decisions § 545).
 *
 * Mirrored in `apps/mobile_android/lib/text_limits.dart`.
 */
export const TEXT_LIMITS = {
	clubName: 80,
	clubDescription: 2000,
	clubLocationLabel: 80,
	displayName: 60
} as const;

/** The constraint each cap is enforced by, so the guard can find it. */
export const TEXT_LIMIT_CONSTRAINTS: Record<keyof typeof TEXT_LIMITS, string> = {
	clubName: 'clubs_name_len_chk',
	clubDescription: 'clubs_description_len_chk',
	clubLocationLabel: 'clubs_location_label_len_chk',
	displayName: 'user_profiles_display_name_len_chk'
};
