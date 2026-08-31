// The mobile half of "a refund_failed order is invisible to the person it
// happened to" (decisions § 825).
//
// Mobile has no paid-registration surface at all — club_events.md stages that
// for P3 — so the notification inbox is not a nice-to-have echo of the web
// banner here, it is the ONLY place the buyer can be told. The donation arm
// has no other surface on ANY platform: `donations` carries no client SELECT
// policy, so the row is unreadable by the donor and the notification line is
// the whole message.
//
// That makes the rendered text the contract, which is why this renders it
// rather than grepping the source for `case 'refund_failed':`. The kind guard
// in profile_screen_test.dart would pass on an arm whose body returned an
// empty string.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';

NotificationRow _refundFailed({String? eventId}) => NotificationRow(
  id: 'n1',
  userId: 'me',
  kind: 'refund_failed',
  eventId: eventId,
  createdAt: DateTime.utc(2026, 8, 30, 9),
);

class _NotifApi extends ApiClient {
  _NotifApi(this._views);

  final List<NotificationView> _views;

  @override
  String? get userId => 'me';

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async =>
      const ProfileSummary(
        id: 'me',
        displayName: 'Me',
        followerCount: 0,
        followingCount: 0,
        viewerFollows: false,
      );

  @override
  Future<List<RunRow>> fetchPublicRunsByUser(
    String userId, {
    int limit = 50,
  }) async => const [];

  @override
  Future<List<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<AchievementRow>> fetchUserBadges(String userId) async => const [];

  @override
  Future<List<NotificationView>> fetchNotificationViews({
    int limit = 100,
  }) async => _views;
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester, _NotifApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProfileScreen(
        api: api,
        userId: 'me',
        initialTab: ProfileTab.notifications,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(_ensureSupabase);

  testWidgets('a reversed refund says what happened and where the money is', (
    tester,
  ) async {
    final api = _NotifApi([NotificationView(row: _refundFailed())]);
    await _pump(tester, api);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.profileNotifRefundFailed), findsOneWidget);
    // Not the generic fall-through, which would name no actor and read as
    // "someone interacted with your activity" about money we owe.
    expect(
      find.text(l10n.profileNotifGeneric(l10n.profileNotifSomeone)),
      findsNothing,
    );
  });

  testWidgets('the donation shape — no event FK — renders the same sentence', (
    tester,
  ) async {
    final withEvent = NotificationView(row: _refundFailed(eventId: 'e1'));
    final withoutEvent = NotificationView(row: _refundFailed());
    for (final view in [withEvent, withoutEvent]) {
      await _pump(tester, _NotifApi([view]));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.profileNotifRefundFailed), findsOneWidget);
    }
  });
}
