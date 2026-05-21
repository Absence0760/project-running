import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Tests for the [ApiClient.isInitialized] guard. The guard exists to
/// stop the cryptic `LateInitializationError: Field 'client' has not
/// been initialized` that the Supabase SDK throws when its internal
/// `late SupabaseClient client` field is read before
/// `Supabase.initialize` resolves.
///
/// Before this guard landed, `main.dart` silently swallowed a failed
/// Supabase init via `.catchError` and then constructed an
/// `ApiClient()` regardless. The first method call (e.g. `saveRoute`)
/// blew up deep inside the SDK with a stack trace the user couldn't
/// act on. Now `ApiClient()` refuses to construct and the bootstrap's
/// `if (hasSupabase && ApiClient.isInitialized)` gate keeps `api`
/// null, so the rest of the app falls through to the existing
/// offline-mode UX.
void main() {
  group('ApiClient.isInitialized — bootstrap guard', () {
    setUp(() {
      // Each test starts from the not-initialized state. Production
      // code never flips the flag back, but the test setup needs to
      // exercise both states deliberately.
      ApiClient.debugResetInitialized();
    });

    test('isInitialized is false before initialize() runs', () {
      expect(ApiClient.isInitialized, isFalse);
    });

    test('default ApiClient() does NOT throw before initialize() — '
        'HomeScreen relies on a fallback `apiClient ?? ApiClient()` and '
        'the userId/userEmail getters wrap _client in try/catch to degrade '
        'to "signed out" semantics', () {
      // The guard against the original bug is on `_client` (used by
      // network methods), not on the constructor — see ApiClient
      // docstring for the rationale. This test pins the contract so
      // a future refactor doesn't quietly add a constructor throw and
      // break the offline-mode fallback.
      ApiClient.debugResetInitialized();
      expect(() => ApiClient(), returnsNormally);
    });

    test(
        'method that reaches _client on an uninitialized ApiClient throws '
        'a typed StateError (not LateInitializationError) — this is the '
        'guard that the original bug report regressed on', () async {
      ApiClient.debugResetInitialized();
      final api = ApiClient();
      // `signOut` is the smallest method that touches `_client` — no
      // network round-trip, just a getter resolution. If the guard
      // regresses, this throws LateInitializationError from deep in
      // the Supabase SDK; with the guard in place, it throws a
      // StateError naming the bootstrap problem.
      Object? captured;
      try {
        await api.signOut();
      } catch (e) {
        captured = e;
      }
      expect(captured, isA<StateError>(),
          reason: 'Expected StateError, got ${captured?.runtimeType}.');
      expect((captured as StateError).message,
          contains('Supabase.initialize'));
    });

    test('userId / userEmail return null when uninitialised — they wrap '
        '_client access in try/catch so callers can degrade gracefully', () {
      ApiClient.debugResetInitialized();
      final api = ApiClient();
      expect(api.userId, isNull);
      expect(api.userEmail, isNull);
    });

    test('ApiClient.withClient(fake) still works when not initialized — '
        'tests must be able to drive the wire layer without Supabase init', () {
      // This is the seam that every withClient-based test relies on.
      // If this regresses, the bulk of the api_client + service tests
      // start failing en masse — the regression would be loud.
      final fake = SupabaseClient('http://127.0.0.1:54321', 'eyJ.local.test');
      try {
        expect(ApiClient.isInitialized, isFalse);
        final api = ApiClient.withClient(fake);
        // Reading a non-network field doesn't throw — the test-only
        // override bypasses the guard.
        expect(api.userId, isNull);
      } finally {
        fake.dispose();
      }
    });

  });

  group('ApiClient.debugResetInitialized — test-only escape hatch', () {
    test('flips isInitialized back to false', () {
      // Simulate a fixture that thinks it has set the flag.
      ApiClient.debugResetInitialized();
      expect(ApiClient.isInitialized, isFalse);
    });
  });
}
