/// Detect a P0001 raised by the `enforce_create_rate_limit` trigger
/// (migration 20260907_001) and convert it into a friendlier message
/// for the toast / inline error. The trigger raises an exception of
/// the form `rate limit exceeded for <bucket>, retry in <seconds>s`
/// with SQLSTATE P0001 and the hint
/// `You are creating these too quickly. Please wait and try again.`
///
/// Returns null when the error isn't a rate-limit one — callers should
/// rethrow the original error in that case so unrelated failures
/// aren't masked.
///
/// Mirrors `apps/web/src/lib/rate_limit_errors.ts` byte-for-behaviour
/// — keep both in lockstep. The web has the corresponding 9 unit tests
/// in `rate_limit_errors.test.ts`; the Dart mirror suite is in
/// `test/rate_limit_errors_test.dart`.
///
/// Takes a structural duck-typed pair of optional strings rather than
/// `PostgrestException` directly so the helper stays pure-Dart and the
/// unit tests don't need to instantiate a supabase_flutter error type.
String? rateLimitErrorMessage({String? code, String? message}) {
  if (code != 'P0001' || message == null || message.isEmpty) return null;
  final match = RegExp(
    r'rate limit exceeded for (\w+),\s*retry in\s+(\d+)s',
    caseSensitive: false,
  ).firstMatch(message);
  if (match == null) return null;
  final bucket = match.group(1)!;
  final secs = int.tryParse(match.group(2)!);
  String wait;
  if (secs == null || secs <= 0) {
    wait = 'a few seconds';
  } else if (secs < 90) {
    wait = '$secs second${secs == 1 ? '' : 's'}';
  } else {
    final mins = (secs / 60).ceil();
    wait = '$mins minute${mins == 1 ? '' : 's'}';
  }
  final verb = bucket == 'create_club'
      ? 'creating clubs'
      : bucket == 'create_route'
          ? 'creating routes'
          : bucket == 'create_report'
              ? 'filing reports'
              : (bucket == 'clone_plan_template' ||
                      bucket == 'clone_public_plan')
                  ? 'adopting plans'
                  : bucket == 'clone_session_template'
                      ? 'adopting session plans'
                      : bucket == 'clone_gym_routine_template'
                          ? 'adopting gym routines'
                          : bucket == 'publish_gym_routine_as_template'
                              ? 'publishing routines'
                              : 'doing that';
  return "You're $verb too quickly — please wait $wait and try again.";
}
