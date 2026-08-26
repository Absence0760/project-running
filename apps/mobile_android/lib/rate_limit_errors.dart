/// Detect a P0001 raised by the `enforce_create_rate_limit` trigger
/// (migration 20260907_001) and pull the two facts it carries out of
/// the message: which bucket refused, and how long the caller must
/// wait. The trigger raises an exception of the form
/// `rate limit exceeded for <bucket>, retry in <seconds>s` with
/// SQLSTATE P0001 and the hint
/// `You are creating these too quickly. Please wait and try again.`
///
/// Parse only — no prose. The sentence a reader sees is a per-locale
/// decision (the verb phrase inflects, the wait pluralises), so it
/// lives in the ARB catalogues and is assembled at the render layer by
/// `rate_limit_message.dart`. See decisions.md § 744.
///
/// Returns null when the error isn't a rate-limit one — callers should
/// rethrow the original error in that case so unrelated failures
/// aren't masked.
///
/// Mirrors `apps/web/src/lib/util/rate_limit_errors.ts` — keep both in
/// lockstep. The mirror suite is `test/rate_limit_errors_test.dart`.
///
/// Takes a structural duck-typed pair of optional strings rather than
/// `PostgrestException` directly so the helper stays pure-Dart and the
/// unit tests don't need to instantiate a supabase_flutter error type.
library;

class RateLimitInfo {
  const RateLimitInfo({required this.bucket, required this.seconds});

  /// The bucket name verbatim, as the trigger spelled it. Deliberately a
  /// plain String rather than an enum of the buckets that exist today: a
  /// bucket a later migration adds must still reach the render layer as
  /// itself, so that layer can pick the honest generic sentence for it.
  final String bucket;

  /// Whole seconds still to wait, or null when the trigger reported a
  /// non-positive figure. Null is "wait a moment", not "wait zero" — the
  /// render layer has its own copy for it.
  final int? seconds;

  @override
  bool operator ==(Object other) =>
      other is RateLimitInfo &&
      other.bucket == bucket &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(bucket, seconds);

  @override
  String toString() => 'RateLimitInfo(bucket: $bucket, seconds: $seconds)';
}

RateLimitInfo? parseRateLimitError({String? code, String? message}) {
  if (code != 'P0001' || message == null || message.isEmpty) return null;
  final match = RegExp(
    r'rate limit exceeded for (\w+),\s*retry in\s+(\d+)s',
    caseSensitive: false,
  ).firstMatch(message);
  if (match == null) return null;
  final secs = int.tryParse(match.group(2)!);
  return RateLimitInfo(
    bucket: match.group(1)!,
    seconds: secs != null && secs > 0 ? secs : null,
  );
}
