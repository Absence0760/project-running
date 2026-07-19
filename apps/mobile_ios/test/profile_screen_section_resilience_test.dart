import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/widgets/error_state.dart';

/// One failing per-tab fetch (Achievements here) must scope its error to
/// that tab — the header, Runs, Followers, and Following must still render.
/// Regression guard for #508 (a single bundled Future.wait failure blanked
/// the whole profile with "Could not load profile").
class _FakeApi extends ApiClient {
  final bool badgesThrow;
  _FakeApi({this.badgesThrow = true});

  @override
  String? get userId => 'viewer';

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async =>
      const ProfileSummary(
        id: 'u1',
        displayName: 'Ultra Runner',
        followerCount: 2,
        followingCount: 1,
        viewerFollows: false,
      );

  @override
  Future<List<RunRow>> fetchPublicRunsByUser(String userId, {int limit = 50}) async => [
        RunRow(
          id: 'r1',
          userId: 'u1',
          startedAt: DateTime(2026, 6, 1, 8),
          durationS: 1800,
          distanceM: 5000,
          source: 'app',
          activityType: 'run',
          isDnf: false,
        ),
      ];

  @override
  Future<List<UserProfileRow>> fetchFollowers(String userId,
          {int limit = 20, int offset = 0}) async =>
      const [UserProfileRow(id: 'f1', displayName: 'Follower One', shadowHidden: false)];

  @override
  Future<List<UserProfileRow>> fetchFollowing(String userId,
          {int limit = 20, int offset = 0}) async =>
      const [UserProfileRow(id: 'g1', displayName: 'Followed One', shadowHidden: false)];

  @override
  Future<List<AchievementRow>> fetchUserBadges(String userId) async {
    if (badgesThrow) throw Exception('badges boom');
    return const [];
  }

  @override
  Future<bool> isBlockedByViewer(String targetUserId) async => false;
}

Widget _host(ApiClient api) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProfileScreen(api: api, userId: 'u1'),
    );

void main() {
  testWidgets('a failing Achievements fetch does not blank the other tabs',
      (tester) async {
    await tester.pumpWidget(_host(_FakeApi(badgesThrow: true)));
    await tester.pumpAndSettle();

    // Header rendered from the summary fetch.
    expect(find.text('Ultra Runner'), findsWidgets);
    // Runs tab (default) rendered its data despite the badges failure.
    expect(find.byIcon(Icons.directions_run), findsWidgets);
    // No page-level error / spinner, and no scoped error on the Runs tab.
    expect(find.text('Could not load profile.'), findsNothing);
    expect(find.byType(ErrorState), findsNothing);

    // The failure is scoped to the Achievements tab.
    await tester.tap(find.text('Achievements'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text("Couldn't load this section."), findsOneWidget);

    // Followers / Following still render their loaded rows.
    await tester.tap(find.text('Followers'));
    await tester.pumpAndSettle();
    expect(find.text('Follower One'), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
  });

  testWidgets('a clean load shows every tab without an error state',
      (tester) async {
    await tester.pumpWidget(_host(_FakeApi(badgesThrow: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Achievements'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
  });
}
