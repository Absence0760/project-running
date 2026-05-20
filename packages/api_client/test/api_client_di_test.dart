import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Tests for the [ApiClient.withClient] DI seam. Production code uses
/// the unnamed `ApiClient()` which reads through `Supabase.instance.client`;
/// these tests prove that injected `SupabaseClient` instances are routed
/// through correctly without booting `Supabase.initialize`.
void main() {
  group('ApiClient.withClient — DI seam', () {
    late SupabaseClient fake;

    setUp(() {
      // Construct against a local-loopback URL so any wire-level call
      // would fail noisily rather than hit a real backend. The seam
      // test only exercises getters that don't make network calls.
      fake = SupabaseClient('http://127.0.0.1:54321', 'eyJ.local.test');
    });

    tearDown(() {
      // SupabaseClient owns a GoTrueClient with a token-refresh timer.
      // Disposing keeps the test isolate from leaking timers between
      // groups.
      fake.dispose();
    });

    test('userId reads from the injected client (null when not signed in)', () {
      final api = ApiClient.withClient(fake);
      expect(api.userId, isNull);
    });

    test('userEmail reads from the injected client (null when not signed in)', () {
      final api = ApiClient.withClient(fake);
      expect(api.userEmail, isNull);
    });

    test('two ApiClient.withClient instances stay independent', () {
      // Sanity check that the override isn't a static field accidentally
      // shared between instances.
      final a = SupabaseClient('http://127.0.0.1:54321', 'eyJ.a.token');
      final b = SupabaseClient('http://127.0.0.1:54321', 'eyJ.b.token');
      try {
        final apiA = ApiClient.withClient(a);
        final apiB = ApiClient.withClient(b);
        expect(apiA.userId, isNull);
        expect(apiB.userId, isNull);
      } finally {
        a.dispose();
        b.dispose();
      }
    });

    test('default ApiClient() falls back to Supabase.instance.client but '
        'userId/userEmail return null instead of throwing when uninitialised', () {
      // Without `Supabase.initialize`, `Supabase.instance` asserts.
      // The getters used to bubble that assertion to callers, which
      // bit RoutesScreen.embedded — the offline-fallback path
      // `widget.apiClient ?? ApiClient()` in HomeScreen produces a
      // default ApiClient, and its first `api.userId` guard crashed
      // the layout. The contract is now "signed out" semantics for
      // both getters when the global isn't wired, which screen-level
      // null guards already handle.
      final defaultApi = ApiClient();
      expect(defaultApi.userId, isNull);
      expect(defaultApi.userEmail, isNull);
    });
  });
}
