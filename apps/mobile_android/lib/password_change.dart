/// Step-up rule for changing an existing account's password
/// (Settings → Account → Change password). A live access token alone must
/// never be enough to rotate the password: a token copied off an unlocked
/// device, taken by an XSS elsewhere in the authenticated app, or leaked
/// from a debug tool would otherwise let the holder lock the owner out
/// permanently (OWASP ASVS V2.1.14 / CWE-620). The caller proves possession
/// of the CURRENT password before the new one is written.
///
/// The mailed recovery token on web's `/auth/reset` deliberately does NOT
/// come through here — that flow is already gated by a single-use token
/// mailed to the address on file, which is the proof this function asks for
/// by another route.
///
/// Dart twin of `apps/web/src/lib/core/password_change.ts` — keep the
/// algorithm, edge cases, outputs, and result-reason set in lockstep.
/// Reuses `checkPasswordPair` from `auth_gates.dart` (the shared pair-check
/// half) rather than re-implementing it. Web models the failure as a
/// `{ok} | {ok, reason, detail?}` union; Dart carries the same information
/// as a small result class.
library;

import 'auth_gates.dart';

/// A stable, locale-independent reason a password change was rejected. The
/// caller resolves it to a localized message. The first two mirror
/// `PasswordPairReason`; the rest are the step-up's own failures.
enum PasswordChangeReason {
  tooShort,
  mismatch,
  currentMissing,
  currentInvalid,
  updateFailed,
}

/// The outcome of [changePassword]. `ok` true carries no reason; a failure
/// carries a [reason] and, for [PasswordChangeReason.updateFailed], the
/// provider's [detail]. Mirrors web's
/// `{ok: true} | {ok: false, reason, detail?}` union.
class PasswordChangeResult {
  final bool ok;
  final PasswordChangeReason? reason;
  final String? detail;

  const PasswordChangeResult.ok()
      : ok = true,
        reason = null,
        detail = null;

  const PasswordChangeResult.failure(this.reason, {this.detail}) : ok = false;
}

class PasswordChangeInput {
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;

  const PasswordChangeInput({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });
}

/// Resolves true only on a POSITIVE proof that [currentPassword] is the
/// account's password today. Anything else — a rejected credential, a
/// network failure, a missing email on the session — is false, and a throw
/// is treated the same way (caught by [changePassword]).
typedef VerifyCurrentPassword = Future<bool> Function(String currentPassword);

/// Writes the new password. Returns null on success, or the provider's
/// error message on failure (mirrors web's `{ error: string | null }`).
typedef UpdatePassword = Future<String?> Function(String newPassword);

/// Pure change-password step-up. Runs the free, local pair check first (a
/// typo in the new fields shouldn't burn a sign-in attempt against the rate
/// limit), then requires a non-empty current password, then a POSITIVE
/// re-authentication of the current password before the new one is written.
/// A rejection, a thrown error, and a session with no email all fail closed
/// and identically — never falling through to the write.
Future<PasswordChangeResult> changePassword(
  PasswordChangeInput input, {
  required VerifyCurrentPassword verifyCurrentPassword,
  required UpdatePassword updatePassword,
}) async {
  final pair = checkPasswordPair(input.newPassword, input.confirmPassword);
  if (pair != null) {
    return PasswordChangeResult.failure(_reasonForPair(pair));
  }

  if (input.currentPassword.isEmpty) {
    return const PasswordChangeResult.failure(
      PasswordChangeReason.currentMissing,
    );
  }

  bool verified = false;
  try {
    verified = await verifyCurrentPassword(input.currentPassword);
  } catch (_) {
    verified = false;
  }
  if (!verified) {
    return const PasswordChangeResult.failure(
      PasswordChangeReason.currentInvalid,
    );
  }

  final error = await updatePassword(input.newPassword);
  if (error != null) {
    return PasswordChangeResult.failure(
      PasswordChangeReason.updateFailed,
      detail: error,
    );
  }
  return const PasswordChangeResult.ok();
}

PasswordChangeReason _reasonForPair(PasswordPairReason reason) {
  switch (reason) {
    case PasswordPairReason.tooShort:
      return PasswordChangeReason.tooShort;
    case PasswordPairReason.mismatch:
      return PasswordChangeReason.mismatch;
  }
}
