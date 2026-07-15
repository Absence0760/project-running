import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Pins the fix for issue #233: the GDPR consent-withdrawal (and sibling
/// health-data) writers must THROW on a missing session, never silently
/// return — a silent return let the caller flip local state and show a
/// success banner while the consent stamp, height, and weight series
/// stayed live on the server, and the user would never retry.
///
/// The signed-out guard runs before any wire call, so a client pointed at
/// an unreachable host proves the throw happens locally: a socket error
/// would surface as a different exception type than [StateError].
void main() {
  late SupabaseClient signedOut;

  setUp(() {
    // Port 9 (discard) is never listening — if a method got past the
    // session guard it would fail with a socket exception, not StateError.
    signedOut = SupabaseClient('http://127.0.0.1:9', 'eyJ.local.test');
  });

  tearDown(() {
    signedOut.dispose();
  });

  group('consent + health-data writers throw when signed out', () {
    test('withdrawHealthDataConsent', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.withdrawHealthDataConsent(), throwsStateError);
    });

    test('withdrawCoachConsent', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.withdrawCoachConsent(), throwsStateError);
    });

    test('setMyHeightCm', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.setMyHeightCm(180), throwsStateError);
    });

    test('recordBodyWeightKg (pre-existing contract, kept)', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.recordBodyWeightKg(70), throwsStateError);
    });
  });
}
