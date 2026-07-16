import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/social_service.dart';

/// Pins the fix for issue #236 on the SocialService side: confirm-dialog
/// action methods must THROW on a missing session, never silently return —
/// leave-club / clear-RSVP / remove-result flows showed success while the
/// membership, RSVP, or result row survived on the server.
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

  group('SocialService actions throw when signed out', () {
    test('leaveClub', () {
      final social = SocialService.withClient(signedOut);
      expect(social.leaveClub('club-1'), throwsStateError);
    });

    test('clearRsvp', () {
      final social = SocialService.withClient(signedOut);
      expect(
        social.clearRsvp('event-1', DateTime.utc(2026, 7, 1)),
        throwsStateError,
      );
    });

    test('removeEventResult', () {
      final social = SocialService.withClient(signedOut);
      expect(
        social.removeEventResult('event-1', DateTime.utc(2026, 7, 1)),
        throwsStateError,
      );
    });
  });
}
