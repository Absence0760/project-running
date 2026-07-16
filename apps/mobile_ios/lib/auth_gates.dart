/// The password-pair check shared by every surface that mints a password.
///
/// Dart twin of the `checkPasswordPair` half of
/// `apps/web/src/lib/core/auth_gates.ts` — keep the algorithm, edge cases,
/// outputs, and test counts in lockstep. The sign-up consent gates on the
/// web side (`checkSignUpGates`) have no twin here: mobile's sign-up screen
/// is separate from sign-in, so those gates live inline in
/// `screens/sign_up_screen.dart` (`_checkGates`).
///
/// Web models the result as a `{ok} | {ok, reason}` union; Dart expresses
/// the same information as a nullable reason (null = the pair is good).
library;

/// GoTrue's default minimum. `config.toml` sets no
/// `minimum_password_length`, so a shorter password is rejected by the auth
/// server anyway — checking here turns an opaque API error into a
/// field-level message.
const int minPasswordLength = 6;

/// A stable, locale-independent reason a password pair was rejected. The
/// caller resolves it to a localized message — the keys differ per surface,
/// so the mapping stays at the call site rather than in here.
enum PasswordPairReason { tooShort, mismatch }

/// Pure check for the two password inputs on any surface that MINTS a
/// password. Returns null when the pair is good.
///
/// Sign-up is the only password-minting surface on mobile, and it took the
/// password in a single field: a typo there was silently baked into the
/// account. The user confirms their email, then can never sign in, because
/// the stored hash is of a string they never meant to type. That failure is
/// invisible to us and indistinguishable from a forgotten password to them.
///
/// Neither side is trimmed. Leading / trailing whitespace is a real part of
/// a password, and it is exactly the typo class this catches — trimming
/// would let `secret ` and `secret` through as equal and store whichever
/// the caller happened to pass first.
///
/// Length is checked before equality so two matching-but-too-short entries
/// report the fixable problem rather than a mismatch the user can't see.
PasswordPairReason? checkPasswordPair(String password, String confirmPassword) {
  if (password.length < minPasswordLength) return PasswordPairReason.tooShort;
  if (password != confirmPassword) return PasswordPairReason.mismatch;
  return null;
}
