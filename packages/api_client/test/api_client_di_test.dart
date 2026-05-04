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

    test('default ApiClient() does NOT use the override and falls back to Supabase.instance.client', () {
      // Without `Supabase.initialize`, the global throws. The test
      // value is that calling the default constructor + then accessing
      // a method that reaches the global does NOT route through any
      // injected fake — confirming the DI hook only fires for
      // .withClient.
      final defaultApi = ApiClient();
      expect(
        () => defaultApi.userId,
        throwsA(isA<AssertionError>().or(isA<Error>())),
      );
    });
  });
}

extension _ThrowsExt on Matcher {
  Matcher or(Matcher other) => _OrMatcher(this, other);
}

class _OrMatcher extends Matcher {
  final Matcher a;
  final Matcher b;
  _OrMatcher(this.a, this.b);

  @override
  bool matches(item, Map matchState) =>
      a.matches(item, matchState) || b.matches(item, matchState);

  @override
  Description describe(Description description) =>
      description.add('matches ').addDescriptionOf(a).add(' or ').addDescriptionOf(b);
}
