import 'package:core_models/core_models.dart';

/// Which date of birth a health inference is allowed to use.
///
/// `date_of_birth` is two records under one column name (decisions § 718).
/// `user_profiles.date_of_birth` is the **age record**: its consumer is the
/// under-18 exclusion in `search_user_profiles` / `discoverable_runners_near`,
/// a child-protection purpose that does not rest on the runner's consent and
/// must not be defeated by declining it — so every entry point writes it
/// whenever a date is supplied, with no consent term.
/// `user_settings.prefs.date_of_birth` is the **Art 9 health-use mirror**:
/// written only under consent, cleared on withdrawal.
///
/// Reading the column and feeding it to a health inference — VO2max, HR max,
/// calorie targets, age grading, the masters recovery calibration — spends the
/// ungated record on the gated purpose. That is Art 9 processing and belongs
/// behind `health_data_consent_at`, exactly as the Coach context re-gates its
/// own read of the mirror.
///
/// This library is the one place that rule is written down. It takes the
/// `get_my_profile()` row a screen already reads (the RPC returns the whole
/// row, so the consent stamp arrives with the date — no extra round trip) and
/// answers with the date only when consent is on record. Screens that read the
/// settings-bag mirror instead need no gate: the mirror already follows consent
/// in both directions.
///
/// Twin of `apps/web/src/lib/core/health_consent.ts` — keep the rule, the
/// states, the precedence, and the test count in lockstep. Web takes a
/// `get_my_profile()` row of unknown shape and a `'usable' | 'absent' |
/// 'consent_withheld'` string union where Dart takes the generated row class
/// and an enum; the same idiomatic difference `password_change` records.

/// - [usable] — a date is on record and consent is too.
/// - [absent] — no date on record. Nothing to consent about.
/// - [consentWithheld] — a date is on record but the Art 9 consent is not, so
///   a health surface may say why the figure is missing rather than render a
///   blank or claim the runner never supplied one.
enum HealthUseDobState { usable, absent, consentWithheld }

/// Length of a bare `YYYY-MM-DD`.
const int _isoDateLength = 10;

/// Grade a `get_my_profile()` row. Fail-closed in both directions: a missing
/// row, a missing stamp and a missing date each withhold the date rather than
/// guess.
HealthUseDobState healthUseDobState(UserProfileRow? row) {
  if (row?.dateOfBirth == null) return HealthUseDobState.absent;
  return row!.healthDataConsentAt == null
      ? HealthUseDobState.consentWithheld
      : HealthUseDobState.usable;
}

/// The `YYYY-MM-DD` a health inference may use, or null. Normalised to the
/// leading date so a caller can hand it to `ageFromDob` / `ageGradeForRun`
/// exactly as the web twin's callers do.
String? healthUseDob(UserProfileRow? row) {
  if (healthUseDobState(row) != HealthUseDobState.usable) return null;
  return row!.dateOfBirth!.toIso8601String().substring(0, _isoDateLength);
}
