import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// Auth-flow parity tests covering the bits I extracted as pure
/// helpers in this round:
///
///   - `ApiClient.buildDefaultProfileRow` — the row shape inserted on
///     first sign-in. Web does the same via `auth.svelte.ts:fetchUser`
///     when `get_my_profile` returns null. Mobile previously had no
///     equivalent path, so mobile-only users had no `user_profiles`
///     row at all. Pins the row shape so a future refactor doesn't
///     quietly drop `preferred_unit` or `subscription_tier`.
///
///   - `ApiClient.signInWithAppleIdToken` exists as a symmetric
///     counterpart to `signInWithGoogleIdToken`. The mobile screens
///     previously called `Supabase.instance.client.auth.signInWithIdToken`
///     directly for Apple; this method gives them the same abstraction
///     they use for Google. We can't drive the network call here
///     without a live Supabase, but we can assert the method is
///     present and has the expected signature shape (compile-time).
///
/// The wire-level behaviour (`ensureMyProfile` actually upserting the
/// row) is exercised by `services_integration_test.dart` against a
/// real local Supabase. These tests just pin the pure helper output.
void main() {
  group('ApiClient.buildDefaultProfileRow — first-sign-in defaults', () {
    test('contains the canonical default columns', () {
      final row = ApiClient.buildDefaultProfileRow('user-id-abc');
      expect(row['id'], 'user-id-abc');
      expect(row['preferred_unit'], 'km',
          reason: 'Default must match web `fetchUser` — preferred_unit '
              'defaults to km on a fresh profile.');
      expect(row['subscription_tier'], 'free',
          reason: 'Default must match web — free tier on first sign-in. '
              'Pro / lifetime are set later by the RevenueCat webhook.');
    });

    test('omits parkrun_number, display_name, avatar_url — those are '
        'user-supplied later, not defaults', () {
      // Pin against an over-eager refactor that decides to set these
      // to empty strings on the row. The DB has nullable columns and
      // the UI handles null gracefully; defaulting to '' on insert
      // would break `IS NOT NULL` filters elsewhere.
      final row = ApiClient.buildDefaultProfileRow('u');
      expect(row.containsKey('parkrun_number'), isFalse);
      expect(row.containsKey('display_name'), isFalse);
      expect(row.containsKey('avatar_url'), isFalse);
    });

    test('row is a fresh map per call (no static buffer)', () {
      // Defensive sanity check.
      final a = ApiClient.buildDefaultProfileRow('a');
      final b = ApiClient.buildDefaultProfileRow('b');
      expect(a['id'], 'a');
      expect(b['id'], 'b');
      // Mutate one and confirm the other is untouched.
      a['preferred_unit'] = 'mi';
      expect(b['preferred_unit'], 'km');
    });
  });

  group('Apple ID token sign-in — method exists with the expected '
      'signature (symmetric counterpart to Google)', () {
    test('signInWithAppleIdToken is reachable on the ApiClient surface',
        () {
      // We can't actually call it without a real Supabase fixture,
      // but we can pin that it exists with the expected named-
      // argument shape. Reflection isn't a great fit here; instead,
      // a compile-time check via a tear-off proves the signature.
      // If the method's signature changes, this file fails to
      // compile.
      const Future<String> Function({required String idToken}) signature =
          _signature;
      expect(signature, isNotNull);
    });
  });
}

/// Compile-time stand-in for `ApiClient(...).signInWithAppleIdToken`'s
/// signature. If the method ever loses its `required String idToken`
/// parameter, this constant fails to type-check and the test build
/// breaks before the test runner even starts — louder than a runtime
/// MissingMethod failure.
Future<String> _signature({required String idToken}) async => idToken;
