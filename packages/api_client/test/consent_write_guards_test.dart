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

    test('withdrawAiDisclosureConsent', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.withdrawAiDisclosureConsent(), throwsStateError);
    });

    test('recordAiDisclosureConsent', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.recordAiDisclosureConsent(2), throwsStateError);
    });

    test('setMyHeightCm', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.setMyHeightCm(180), throwsStateError);
    });

    // Not itself consent-gated (§ 718 — the column is the child-safety age
    // record), but it is a user_profiles writer in the same §248 family:
    // a silent return would leave a declared minor with no age record while
    // the caller reports the birth date saved.
    test('setMyDateOfBirth', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.setMyDateOfBirth(DateTime.utc(1990, 6, 15)), throwsStateError);
    });

    test('recordBodyWeightKg (pre-existing contract, kept)', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.recordBodyWeightKg(70), throwsStateError);
    });

    test('updateDisplayName (issue #226, same §248 write family)', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.updateDisplayName('Alex'), throwsStateError);
    });
  });
}
