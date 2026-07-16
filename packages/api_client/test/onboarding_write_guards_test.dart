import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Pins the fix for issue #227: the onboarding stamp writers must THROW on
/// a missing session, never silently return — a silent return let the setup
/// wizard pop as if the stamp landed, and the home-screen gate re-pushed the
/// wizard from step 1 on the next launch with every answer lost.
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

  group('onboarding writers throw when signed out', () {
    test('markOnboarded', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.markOnboarded(), throwsStateError);
    });

    test('completeOnboarding', () {
      final api = ApiClient.withClient(signedOut);
      expect(
        api.completeOnboarding(
          displayName: 'Alex',
          preferredUnit: 'km',
          healthDataConsent: false,
        ),
        throwsStateError,
      );
    });
  });
}
