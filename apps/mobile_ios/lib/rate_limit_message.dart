/// The sentence a throttled caller reads, assembled from the ARBs.
///
/// `rate_limit_errors.dart` (the web-parity half) parses the postgres
/// P0001 into a [RateLimitInfo] and stops there, because both halves of
/// the sentence are per-locale decisions: the activity is a clause whose
/// verb inflects, and the wait pluralises. So the bucket picks a whole
/// translated sentence and the wait is the one noun phrase dropped into
/// it — a slot that survives every locale we ship, where an `{activity}`
/// slot would not (German puts the verb second and the object last).
///
/// Mirrors web's `i18n/rate_limit_message.ts`, but the render glue is
/// per-platform (the key identifiers differ by convention) and, unlike
/// the parser, is NOT part of the enforced lockstep. decisions.md § 744.
library;

import 'l10n/gen/app_localizations.dart';
import 'rate_limit_errors.dart';

/// Above this the wait reads better in minutes, rounded up so we never
/// invite a retry that is still inside the window.
const int kRateLimitMinuteCutoffS = 90;

String rateLimitWait(AppLocalizations l10n, int? seconds) {
  if (seconds == null) return l10n.rateLimitWaitSoon;
  if (seconds < kRateLimitMinuteCutoffS) return l10n.rateLimitWaitSeconds(seconds);
  return l10n.rateLimitWaitMinutes((seconds / 60).ceil());
}

/// Every bucket `enforce_create_rate_limit` is called with today. The two
/// direct-message buckets (a 30/60 s burst and a 250/3600 s hour cap,
/// decisions § 737) share one sentence: which of the two windows refused
/// is our accounting, not something to explain to a sender. So do the two
/// plan-adopt paths, which are the same act from two libraries.
String rateLimitMessage(AppLocalizations l10n, RateLimitInfo info) {
  final wait = rateLimitWait(l10n, info.seconds);
  switch (info.bucket) {
    case 'create_club':
      return l10n.rateLimitCreateClub(wait);
    case 'create_route':
      return l10n.rateLimitCreateRoute(wait);
    case 'create_report':
      return l10n.rateLimitCreateReport(wait);
    case 'clone_plan_template':
    case 'clone_public_plan':
      return l10n.rateLimitAdoptPlan(wait);
    case 'clone_session_template':
      return l10n.rateLimitAdoptSessionPlan(wait);
    case 'clone_gym_routine_template':
      return l10n.rateLimitAdoptGymRoutine(wait);
    case 'publish_gym_routine_as_template':
      return l10n.rateLimitPublishRoutine(wait);
    case 'send_direct_message':
    case 'send_direct_message_burst':
      return l10n.rateLimitSendMessage(wait);
    default:
      return l10n.rateLimitGeneric(wait);
  }
}

/// Parse-and-render in one call, for the catch blocks that show the
/// friendly string. Null when the error is not a rate-limit refusal, so
/// the caller falls through to its own handling rather than masking it.
String? rateLimitErrorMessage(
  AppLocalizations l10n, {
  String? code,
  String? message,
}) {
  final info = parseRateLimitError(code: code, message: message);
  return info == null ? null : rateLimitMessage(l10n, info);
}
