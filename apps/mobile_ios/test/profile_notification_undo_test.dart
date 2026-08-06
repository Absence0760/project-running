// Issue #666 U8, mobile half: the notification dismiss is the strongest undo
// case in the app — the row is SYSTEM-minted, so a stray tap was the one
// destruction the user could not reproduce by re-typing, and nothing hangs off
// it (decisions § 514 / § 521).
//
// Two properties beyond "Undo puts it back": dismissing a collapsed group is
// ONE intent so it takes one slot and one BATCHED delete (never N round-trips),
// and the delete is deferred, so while the offer stands nothing has reached the
// server at all.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/widgets/undo_bar.dart';

NotificationRow _row(String id, {String actorId = 'a1'}) => NotificationRow(
      id: id,
      userId: 'me',
      actorId: actorId,
      kind: 'follow',
      createdAt: DateTime.utc(2026, 8, 5, 12),
    );

class _NotifApi extends ApiClient {
  _NotifApi(this._rows);

  final List<NotificationRow> _rows;
  final List<List<String>> deletes = [];

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
  Future<List<RunRow>> fetchPublicRunsByUser(String userId,
          {int limit = 50}) async =>
      const [];

  @override
  Future<List<UserProfileRow>> fetchFollowers(String userId,
          {int limit = 20, int offset = 0}) async =>
      const [];

  @override
  Future<List<UserProfileRow>> fetchFollowing(String userId,
          {int limit = 20, int offset = 0}) async =>
      const [];

  @override
  Future<List<AchievementRow>> fetchUserBadges(String userId) async => const [];

  @override
  Future<List<NotificationView>> fetchNotificationViews({
    int limit = 100,
  }) async =>
      [for (final r in _rows) NotificationView(row: r)];

  @override
  Future<void> deleteNotifications(List<String> ids) async {
    deletes.add(List<String>.from(ids));
  }
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
  // The fetch resolves on the real event loop; pumping a couple of frames is
  // enough because the fake futures complete immediately.
  await tester.pump();
  await tester.pump();
}

/// The armed window owns a real Timer; a test that ends with it pending fails
/// on `!timersPending`.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 9));

void main() {
  setUpAll(_ensureSupabase);
  tearDown(debugResetUndo);

  testWidgets('dismissing one notification offers undo and defers the delete',
      (tester) async {
    final api = _NotifApi([_row('n1')]);
    await _pump(tester, api);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(find.text('Notification dismissed'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(api.deletes, isEmpty,
        reason: 'nothing reaches the server while the offer stands');

    await _drain(tester);
    expect(api.deletes, [
      ['n1']
    ]);
  });

  testWidgets('Undo cancels the delete outright — the server is never touched',
      (tester) async {
    final api = _NotifApi([_row('n1')]);
    await _pump(tester, api);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pump();

    await _drain(tester);
    expect(api.deletes, isEmpty);
    expect(find.text('Notification dismissed'), findsNothing);
  });

  testWidgets('dismissing a group is one bar and one batched delete',
      (tester) async {
    // Three same-kind notifications from the same actor collapse into one
    // group, so the row carries the group dismiss.
    final api = _NotifApi([
      _row('n1'),
      _row('n2'),
      _row('n3'),
    ]);
    await _pump(tester, api);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(find.text('3 notifications dismissed'), findsOneWidget);
    expect(api.deletes, isEmpty);

    await _drain(tester);
    expect(api.deletes, hasLength(1),
        reason: 'one intent is one statement, never N round-trips');
    expect(api.deletes.single..sort(), ['n1', 'n2', 'n3']);
  });

  testWidgets('the dismiss no longer opens a confirm dialog', (tester) async {
    final api = _NotifApi([_row('n1')]);
    await _pump(tester, api);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'confirm and undo are alternatives, not partners (§ 514)');
    await _drain(tester);
  });
}
