/**
 * Character caps on user-authored text, stated once per client and enforced by
 * a matching CHECK constraint in the database.
 *
 * Every entry here has a `<table>_<column>_len_chk` somewhere under
 * `apps/backend/supabase/migrations/` with the same number, and
 * `text_limits.test.ts` scans the whole directory to prove it — the caps are
 * spread over three migrations and reading only the one that happened to add
 * the first four is how four MORE caps stayed unregistered while three clients
 * silently truncated below them (decisions § 792).
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
	displayName: 60,
	clubPostBody: 4096,
	eventDescription: 2000,
	planName: 120,
	parkrunNumber: 32
} as const;

/** The constraint each cap is enforced by, so the guard can find it. */
export const TEXT_LIMIT_CONSTRAINTS: Record<keyof typeof TEXT_LIMITS, string> = {
	clubName: 'clubs_name_len_chk',
	clubDescription: 'clubs_description_len_chk',
	clubLocationLabel: 'clubs_location_label_len_chk',
	displayName: 'user_profiles_display_name_len_chk',
	clubPostBody: 'club_posts_body_len_chk',
	eventDescription: 'events_description_len_chk',
	planName: 'training_plans_name_len_chk',
	parkrunNumber: 'user_profiles_parkrun_number_len_chk'
};
