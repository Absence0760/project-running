import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Pins the fix for issue #236: data-layer action methods must THROW on a
/// missing session, never silently return — a silent return let callers
/// flip local state (unfollow, unblock, disconnect Strava, dismiss a
/// notification, ...) and show success while the server kept the old row.
/// Callers already carry catch + rollback paths; the throw activates them.
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

  group('social actions throw when signed out', () {
    test('unfollowUser', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.unfollowUser('u1'), throwsStateError);
    });

    test('unblockUser', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.unblockUser('u1'), throwsStateError);
    });

    test('editRunComment', () {
      final api = ApiClient.withClient(signedOut);
      expect(
        api.editRunComment(commentId: 'c1', body: 'hi'),
        throwsStateError,
      );
    });
  });

  group('notification actions throw when signed out', () {
    test('markNotificationRead', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.markNotificationRead('n1'), throwsStateError);
    });

    test('markAllNotificationsRead', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.markAllNotificationsRead(), throwsStateError);
    });

    test('deleteNotification', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.deleteNotification('n1'), throwsStateError);
    });
  });

  group('integration + coach + review actions throw when signed out', () {
    test('disconnectIntegration', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.disconnectIntegration('strava'), throwsStateError);
    });

    test('archiveCoachThread', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.archiveCoachThread(), throwsStateError);
    });

    test('deleteCoachArchive', () {
      final api = ApiClient.withClient(signedOut);
      expect(
        api.deleteCoachArchive(archivedAt: DateTime.utc(2026)),
        throwsStateError,
      );
    });

    test('deleteRouteReview', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.deleteRouteReview('r1'), throwsStateError);
    });
  });

  group('onboarding + recap writers throw when signed out', () {
    test('markOnboarded', () {
      final api = ApiClient.withClient(signedOut);
      expect(api.markOnboarded(), throwsStateError);
    });

    test('completeOnboarding', () {
      final api = ApiClient.withClient(signedOut);
      expect(
        api.completeOnboarding(
          preferredUnit: 'km',
          healthDataConsent: false,
        ),
        throwsStateError,
      );
    });

    test('publishRecap', () {
      final api = ApiClient.withClient(signedOut);
      expect(
        api.publishRecap(
          periodKind: 'year',
          periodKey: '2026',
          snapshot: const {},
        ),
        throwsStateError,
      );
    });
  });
}
