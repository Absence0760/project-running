/// Character caps on user-authored text, stated once per client and enforced by
/// a matching CHECK constraint in the database.
///
/// Every entry here has a `<table>_<column>_len_chk` somewhere under
/// `apps/backend/supabase/migrations/` with the same number, and
/// `text_limits_test.dart` scans the whole directory to prove it — the caps are
/// spread over three migrations and reading only the one that happened to add
/// the first four is how four MORE caps stayed unregistered while this client
/// silently truncated below them (decisions § 792). A composer that caps lower than the constraint is merely conservative;
/// one that caps higher hands the user a postgres 23514 they cannot act on,
/// which is what mobile's 500-character club description and web's 600 both did
/// against a column that had no constraint at all (decisions § 545).
///
/// Dart twin of `apps/web/src/lib/core/text_limits.ts`.
library;

const int kClubNameMaxLength = 80;
const int kClubDescriptionMaxLength = 2000;
const int kClubLocationLabelMaxLength = 80;
const int kDisplayNameMaxLength = 60;
const int kClubPostBodyMaxLength = 4096;
const int kEventDescriptionMaxLength = 2000;
const int kPlanNameMaxLength = 120;
const int kParkrunNumberMaxLength = 32;

/// The constraint each cap is enforced by, so the guard can find it.
const Map<String, int> kTextLimitConstraints = {
  'clubs_name_len_chk': kClubNameMaxLength,
  'clubs_description_len_chk': kClubDescriptionMaxLength,
  'clubs_location_label_len_chk': kClubLocationLabelMaxLength,
  'user_profiles_display_name_len_chk': kDisplayNameMaxLength,
  'club_posts_body_len_chk': kClubPostBodyMaxLength,
  'events_description_len_chk': kEventDescriptionMaxLength,
  'training_plans_name_len_chk': kPlanNameMaxLength,
  'user_profiles_parkrun_number_len_chk': kParkrunNumberMaxLength,
};
