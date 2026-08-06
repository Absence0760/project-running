import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar, ListSkeleton;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';

/// Signed-in viewer looking at their own profile — the five-tab shape
/// that carries Notifications.
class _SelfApi extends ApiClient {
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
      const [];
}

String _selectedTabLabel(WidgetTester tester) {
  final tabBar = tester.widget<TabBar>(find.byType(TabBar));
  return (tabBar.tabs[tabBar.controller!.index] as Tab).text!;
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

Future<void> _pump(
  WidgetTester tester, {
  required String userId,
  ProfileTab initialTab = ProfileTab.runs,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProfileScreen(
        api: ApiClient(),
        userId: userId,
        initialTab: initialTab,
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('ProfileScreen — initial render', () {
    testWidgets('renders the Profile fallback title before the summary loads',
        (tester) async {
      // Reason: until _summary fills in, the title shows the literal
      // string "Profile" — make sure the fallback renders.
      await _pump(tester, userId: 'someone-else');
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('first frame stands the header + tab layout the profile will '
        'settle into', (tester) async {
      await _pump(tester, userId: 'someone-else');
      // Single pump only — the post-fetch frame swaps in ErrorState.
      // Two skeletons: the header block above the divider, the tab body below.
      expect(find.byType(ListSkeleton), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
        'renders four tabs (Runs/Achievements/Followers/Following) for non-self',
        (tester) async {
      // Reason: Achievements is visible to everyone (RLS gates the private
      // rows); Notifications is gated to isSelf — it must NOT appear when
      // viewing another user's profile.
      await _pump(tester, userId: 'someone-else');
      expect(find.text('Runs'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Followers'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Notifications'), findsNothing);
    });
  });

  group('ProfileScreen — named tab deep links', () {
    Future<void> pumpSelf(WidgetTester tester, ProfileTab tab) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProfileScreen(
              api: _SelfApi(),
              userId: 'me',
              initialTab: tab,
            ),
          ),
        );

    testWidgets('ProfileTab.notifications opens the Notifications tab',
        (tester) async {
      await pumpSelf(tester, ProfileTab.notifications);
      await tester.pumpAndSettle();
      expect(_selectedTabLabel(tester), 'Notifications');
    });

    testWidgets('the tab a bare index 3 would have selected is NOT '
        'Notifications', (tester) async {
      // Documents the bug the enum closes: Achievements was inserted at
      // index 1, so the literal the bell used to pass now names Following.
      // If a future insertion moves things again this still holds, and the
      // test above still asserts the bell's real destination by label.
      await pumpSelf(tester, ProfileTab.notifications);
      await tester.pumpAndSettle();
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect((tabBar.tabs[3] as Tab).text, isNot('Notifications'));
    });

    testWidgets('defaults to the Runs tab', (tester) async {
      await pumpSelf(tester, ProfileTab.runs);
      await tester.pumpAndSettle();
      expect(_selectedTabLabel(tester), 'Runs');
    });

    testWidgets(
        'a tab this profile does not carry falls back to the first tab',
        (tester) async {
      // Someone else's profile has no Notifications tab. The old int
      // parameter clamped an out-of-range index onto the LAST tab
      // (Following) — a near-miss that reads like a bug. Naming the tab
      // makes the absence explicit and lands on Runs.
      await _pump(tester,
          userId: 'someone-else', initialTab: ProfileTab.notifications);
      await tester.pump();
      expect(_selectedTabLabel(tester), 'Runs');
    });
  });

  group('_verbFor — event_rsvp wiring', () {
    // Source-level grep for the verb strings the web NotificationsList
    // emits. Profile_screen owns the equivalent Dart switch; if the
    // verb / kind label diverges from web (or the migration name in
    // the project), the parity contract from decisions §31 / §38 is
    // broken. Cheaper than booting a tester with a fake API.
    final source =
        File('lib/screens/profile_screen.dart').readAsStringSync();

    test('handles the event_rsvp notification kind', () {
      expect(source.contains("case 'event_rsvp':"), isTrue,
          reason:
              'event_rsvp was added in migration 20260903_001 — the inbox '
              'verb switch must list it explicitly.');
    });

    test('verb string mirrors the web "RSVP\'d Going" phrasing', () {
      // The verb text now lives in the gen-l10n catalogues; the screen
      // dispatches to the localized key. Pin the key reference so the
      // event_rsvp verb can't silently drop off the inbox switch.
      expect(source.contains('l10n.profileNotifEventRsvpTitled'), isTrue,
          reason:
              'Verb text must match NotificationsList.svelte so push / '
              'inbox / web stay in lockstep.');
    });

    test('event_rsvp tap navigates into the club event detail', () {
      expect(source.contains('EventDetailScreen('), isTrue,
          reason:
              'Tapping an event_rsvp notification must open the same '
              'EventDetailScreen the club-event tab uses.');
    });
  });

  group('_verbFor — club_post + run_completed wiring (persona #38)', () {
    // Migration 20261101_001 added the club_post + run_completed fan-out
    // kinds. The mobile inbox verb switch + tap navigation must list them
    // explicitly and mirror the web NotificationsList phrasing so the two
    // surfaces stay in lockstep.
    final source =
        File('lib/screens/profile_screen.dart').readAsStringSync();

    test('handles the club_post + run_completed notification kinds', () {
      expect(source.contains("case 'club_post':"), isTrue,
          reason: 'club_post fan-out (migration 20261101_001) must render.');
      expect(source.contains("case 'run_completed':"), isTrue,
          reason:
              'run_completed fan-out (migration 20261101_001) must render.');
    });

    test('verb strings mirror the web NotificationsList phrasing', () {
      // Verb text moved into the gen-l10n catalogues; pin the localized
      // key references so the club_post + run_completed verbs stay wired.
      expect(source.contains('l10n.profileNotifClubPostNamed'), isTrue,
          reason: 'club_post verb must match the web "posted in <club>" line.');
      expect(source.contains('l10n.profileNotifRunCompletedDist'), isTrue,
          reason:
              'run_completed verb must match the web "completed a <dist> run" '
              'line.');
    });

    test('club_post tap opens the club detail; run_completed opens the run',
        () {
      expect(source.contains('ClubDetailScreen('), isTrue,
          reason:
              'Tapping a club_post notification must open ClubDetailScreen '
              'for the linked club slug.');
      expect(source.contains("kind == 'run_completed'"), isTrue,
          reason:
              'run_completed tap must route to PublicRunScreen via the '
              'row runId.');
    });
  });

  group('_verbFor — every NotificationKind is rendered explicitly', () {
    // The inbox switch fell through to profileNotifGeneric ("{name} interacted
    // with your activity") for event_cancel, event_reminder, plan_assigned,
    // achievement, challenge_complete and content_hidden — a line that is not
    // merely vague but wrong: nobody interacted with anything when a plan is
    // assigned or a moderation system hides a post.
    //
    // The two groups above pin one kind each by name, which is what let the
    // next six arrive unrendered. This reads the NotificationKind union from
    // apps/web/src/lib/types.ts — the same source the worker's Go copy guard
    // and web's notification_kind_coverage guard read — so a kind added to the
    // union without an arm here fails, rather than degrading in production.
    final source =
        File('lib/screens/profile_screen.dart').readAsStringSync();
    final decl = File('../web/src/lib/types.ts')
        .readAsStringSync()
        .split('export type NotificationKind')[1]
        .split(';')[0];
    final kinds = RegExp("'([a-z_]+)'")
        .allMatches(decl)
        .map((m) => m.group(1)!)
        .toList();

    test('the union parsed', () {
      expect(kinds.length, greaterThanOrEqualTo(15),
          reason: 'expected the full NotificationKind union, got $kinds');
    });

    for (final kind in kinds) {
      test('$kind has an explicit case in the inbox verb switch', () {
        expect(source.contains("case '$kind':"), isTrue,
            reason:
                "'$kind' falls through to profileNotifGeneric, which reads "
                '"{name} interacted with your activity" — wrong for every '
                'kind that is not a social interaction. Add an arm and a '
                'localized string in all seven ARBs.');
      });
    }
  });

  group('notification grouping wiring', () {
    // The inbox collapses same-kind + same-target notifications through
    // the notification_groups.dart parity helper. Pin the wiring so the
    // "Alice and N others" collapse can't silently regress to a flat list
    // (the logic itself is covered by notification_groups_test.dart).
    final source =
        File('lib/screens/profile_screen.dart').readAsStringSync();

    test('builds groups through the parity helper', () {
      expect(source.contains('groupNotifications('), isTrue,
          reason:
              'The inbox must collapse via notification_groups.dart, not '
              'render a flat NotificationView list.');
      expect(source.contains('_buildNotifGroupRow('), isTrue);
    });

    test('renders the "and N others" collapsed name + expand toggle', () {
      expect(source.contains('l10n.profileNotifNameAndOthers'), isTrue,
          reason:
              'The collapsed group lead must read "<name> and N others" to '
              'mirror the web NotificationsList.');
      expect(source.contains('l10n.profileNotifAndOthers'), isTrue);
      expect(source.contains('l10n.profileNotifShowLess'), isTrue);
      expect(source.contains('_expandedGroups'), isTrue);
    });

    test('opening / dismissing acts on the whole group', () {
      expect(source.contains('_openGroup('), isTrue,
          reason:
              'Tapping a group must mark every member read + navigate to '
              'the shared target.');
      expect(source.contains('_dismissGroup('), isTrue);
    });
  });

  group('runs tab — the shared run row', () {
    // Source-level guards on the Runs tab. Driving the full widget tree
    // requires a populated _runs list which means a fake Supabase fetch —
    // expensive for a structural guard. Pin the pieces by grep so a refactor
    // that re-forks the row (#666 C8) fails loud.
    final source =
        File('lib/screens/profile_screen.dart').readAsStringSync();

    test('Runs tab draws the shared run row, not a fork of it', () {
      expect(source.contains('RunListTile.public('), isTrue,
          reason:
              'the Runs tab had its own ListTile — no card, Divider '
              'separators, a 56dp leading slot against the shared row\'s 72, '
              'no vert chip and the pace in the subtitle — under a comment '
              'claiming it mirrored the History tab (#666 C8).');
      expect(source.contains('RunTrackPreview('), isFalse,
          reason:
              'the thumbnail belongs to the shared row; mounting one here is '
              'how the two lists drifted to different sizes in the first '
              'place.');
    });

    test('a non-owner thumbnail is clipped against the profile owner', () {
      expect(source.contains('ownerUserId: widget.userId'), isTrue,
          reason:
              'this list shows OTHER runners\' runs, so the thumbnail must go '
              'through the clip-public-track function rather than pulling the '
              'unclipped blob from Storage (decisions §33).');
    });

    test('Runs tab tile tap routes into PublicRunScreen', () {
      expect(source.contains('PublicRunScreen(api:'), isTrue,
          reason:
              'Tapping a run on a public profile must open the read-only '
              'PublicRunScreen which takes a runId — the old TODO comment '
              'about run-detail expecting a local Run is now obsolete.');
    });
  });

  group('block button wiring — persona-hunt Round 3 W1', () {
    // Source-level guards on the Block button in the AppBar. The
    // backend primitive (user_blocks + block_user / unblock_user RPCs)
    // shipped in migration 20261012_001; the UI surface here is the
    // mobile end of the persona finding. Widget-driving the dialog
    // requires a populated _summary which means a fake Supabase
    // fetch — pin the structural pieces by grep so the affordance
    // can't silently regress.
    final source =
        File('lib/screens/profile_screen.dart').readAsStringSync();

    test('Block IconButton renders in the AppBar for non-self viewers', () {
      expect(
          source.contains('tooltip: _blocked ? l10n.profileUnblock'),
          isTrue,
          reason:
              'AppBar must surface a Block / Unblock IconButton when the '
              'viewer is not viewing their own profile. Without it the '
              'block_user RPC is unreachable from this screen — the '
              'persona-hunt Round 3 W1 finding.');
    });

    test('Block IconButton calls blockUser via the confirm dialog', () {
      expect(source.contains('widget.api.blockUser(widget.userId)'), isTrue,
          reason:
              'Block tap must reach ApiClient.blockUser. A regression that '
              'wired it to a different RPC (or skipped the RPC entirely) '
              'would record nothing in user_blocks.');
      expect(source.contains('_confirmBlock'), isTrue,
          reason:
              'Block direction is destructive — block_user drains existing '
              'follow rows in either direction — so the tap MUST gate on '
              'a confirm dialog. A regression that fired blockUser '
              'directly from the IconButton onPressed would surprise the '
              'user with a one-tap follower drain.');
    });

    test('Unblock direction is non-destructive — no confirm dialog', () {
      // Reason: the unblock direction restores normal interaction
      // without losing any data, so it should be a one-tap toggle.
      // _toggleBlock branches: blocked → _doUnblock (no confirm),
      // unblocked → _confirmBlock then _doBlock. The presence of the
      // _doUnblock symbol + the conditional in _toggleBlock pins the
      // shape.
      expect(source.contains('_doUnblock'), isTrue);
      expect(
          source.contains('widget.api.unblockUser(widget.userId)'), isTrue);
    });
  });

  group('profile header (issue #666 C12)', () {
    // The header is a fixed band above `Expanded(TabBarView)` in a
    // non-scrolling `Column`, and `user_profiles.display_name` has no DB
    // length constraint. The derivation, not an absolute: name LENGTH must
    // not move the header/tabs split — font-independent, where an absolute
    // "the tabs get N dp" would not be measurable in CI (decisions § 500).
    testWidgets('display-name length does not move the header/tabs split',
        (tester) async {
      await _ensureSupabase();
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      Future<double> splitFor(String name) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // Keyed by the name: without it the second pump reuses the first
            // State, which never re-fetches, and the assertions would run
            // against the first name twice.
            home: ProfileScreen(
              key: ValueKey(name),
              api: _NamedApi(name),
              userId: 'me',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        // The AppBar title carries the same string; the header copy is the
        // one that can grow the band, and it is the capped one.
        expect(find.byType(IdentityAvatar), findsOneWidget);
        expect(
          tester
              .widgetList<Text>(find.text(name))
              .map((t) => t.maxLines)
              .toList(),
          contains(kProfileNameMaxLines),
        );
        return tester.getSize(find.byType(TabBarView)).height;
      }

      final atCap = await splitFor('Alexandra Bartholomew-Ngu' * 2);
      final tenTimesLonger =
          await splitFor('Alexandra Bartholomew-Ngu' * 20);

      expect(atCap, greaterThan(0));
      expect(tester.takeException(), isNull);
      expect(
        tenTimesLonger,
        atCap,
        reason: 'a longer display name still eats the tab bodies',
      );
    });
  });
}

/// Self-profile whose display name the caller chooses, so the header's
/// unbounded child can be driven directly.
class _NamedApi extends _SelfApi {
  _NamedApi(this.name);

  final String name;

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async =>
      ProfileSummary(
        id: 'me',
        displayName: name,
        followerCount: 0,
        followingCount: 0,
        viewerFollows: false,
      );
}
