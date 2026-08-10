/// Versioned AI-processing consent — the record every surface that ships a
/// runner's data to Anthropic grades before it offers the feature. GDPR
/// Art 6(1)(a).
///
/// The record is `user_profiles.ai_disclosure_version` (which disclosure was
/// accepted) paired with `coach_consent_at` (when). Neither column is in the
/// cross-user column grant, so it is read through the SECURITY DEFINER
/// `get_my_profile()` RPC and written only by `record_ai_disclosure_consent()`
/// (migration 20270511_001).
///
/// Versions are a monotone ladder — each one a strict superset of the last —
/// which is what makes "accepted >= required" sound:
///
///   1  AI Coach only.
///   2  All AI features: the Coach plus the AI route assistant.
///
/// Adding the next AI feature means a new version with new copy, not a new
/// boolean and not quietly widening what an existing acceptance covers.
///
/// Dart twin of the client half of web's `core/ai_disclosure.ts` — the
/// ladder, the record shape, and the fail-closed grading. Web's
/// `gateAiDisclosure` / `aiDisclosureDenialBody` are server-side and have no
/// mobile counterpart: the clients grade the record to decide what to
/// *offer*, the server still decides what to *serve*.
library;

/// Minimum disclosure version the AI Coach requires.
const int kAiDisclosureVersionCoach = 1;

/// Minimum disclosure version the AI route assistant requires
/// (`/api/coach/route-describe` + `/api/coach/route-request`). Higher than
/// the Coach's because the route endpoints send a different payload — the
/// typed request text and a coarse location label — for a different purpose
/// than the Coach copy described.
const int kAiDisclosureVersionRouteAi = 2;

/// The newest disclosure this build knows how to present. Must equal the SQL
/// `ai_disclosure_current_version()` and web's `AI_DISCLOSURE_CURRENT_VERSION`.
const int kAiDisclosureCurrentVersion = kAiDisclosureVersionRouteAi;

/// Machine-readable marker on every AI-consent denial. It rides a `code`
/// field rather than `error` because the endpoints already use `error` for
/// their own (differently-shaped) strings — clients branch on `code`.
const String kAiDisclosureError = 'ai_disclosure_required';

/// - [missing] — nothing on record (never accepted, or withdrawn).
/// - [stale]   — accepted an older disclosure that did not cover this use.
/// - [unknown] — the record is unreadable or names a version this build
///               cannot describe. Denied rather than trusted: a disclosure
///               we cannot render is a disclosure we cannot prove was made.
enum AiDisclosureDenial { missing, stale, unknown }

/// The consent record as the server holds it, values untyped on purpose —
/// grading a malformed record is [checkAiDisclosure]'s job, not the parser's.
class AiDisclosureRecord {
  final Object? version;
  final Object? acceptedAt;

  const AiDisclosureRecord({this.version, this.acceptedAt});
}

class AiDisclosureCheck {
  final bool ok;
  final int? version;
  final AiDisclosureDenial? reason;

  const AiDisclosureCheck._(this.ok, this.version, this.reason);

  const AiDisclosureCheck.granted(int version) : this._(true, version, null);

  const AiDisclosureCheck.denied(AiDisclosureDenial reason)
      : this._(false, null, reason);
}

/// Pull the consent record out of a `get_my_profile()` row of unknown shape.
AiDisclosureRecord aiDisclosureFromProfileRow(Object? row) {
  if (row is! Map) return const AiDisclosureRecord();
  return AiDisclosureRecord(
    version: row['ai_disclosure_version'],
    acceptedAt: row['coach_consent_at'],
  );
}

/// Fail-closed: anything that is not a complete, known, sufficient record
/// denies.
AiDisclosureCheck checkAiDisclosure(
  AiDisclosureRecord record,
  int requiredVersion,
) {
  final acceptedAt = record.acceptedAt;
  final hasAcceptedAt = acceptedAt is String && acceptedAt.isNotEmpty;
  final version = record.version;
  if (version == null || !hasAcceptedAt) {
    return const AiDisclosureCheck.denied(AiDisclosureDenial.missing);
  }
  if (version is! int) {
    return const AiDisclosureCheck.denied(AiDisclosureDenial.unknown);
  }
  if (version < 1 || version > kAiDisclosureCurrentVersion) {
    return const AiDisclosureCheck.denied(AiDisclosureDenial.unknown);
  }
  if (version < requiredVersion) {
    return const AiDisclosureCheck.denied(AiDisclosureDenial.stale);
  }
  return AiDisclosureCheck.granted(version);
}
