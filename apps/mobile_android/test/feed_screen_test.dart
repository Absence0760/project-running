import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/feed_screen.dart';
import '../lib/widgets/error_state.dart';

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

PublicProfile _author({String id = 'u-1', String? name = 'Alex Runner'}) =>
    PublicProfile(id: id, displayName: name);

RunFeedEntry _runEntry({
  String id = 'run-1',
  double distanceM = 5000,
  int durationS = 1500,
  String authorId = 'u-1',
  String? authorName = 'Alex Runner',
}) =>
    RunFeedEntry(
      run: RunRow(
        id: id,
        userId: authorId,
        startedAt: DateTime.utc(2026, 6, 10, 7),
        durationS: durationS,
        distanceM: distanceM,
        source: 'manual',
        activityType: 'run',
        isDnf: false,
        isPublic: true,
      ),
      author: _author(id: authorId, name: authorName),
    );

UserProfileRow _profileRow(String id, String name) => UserProfileRow(shadowHidden: false, 
      id: id,
      displayName: name,
    );

BadgeAwardEntry _badgeAward({
  String authorId = 'u-1',
  String? authorName = 'Alex Runner',
  String badgeKey = 'streak',
  String tier = 'gold',
}) =>
    BadgeAwardEntry(
      badge: AchievementRow(
        id: '$badgeKey-$tier-$authorId',
        userId: authorId,
        badgeKey: badgeKey,
        tier: tier,
        sourceKind: 'streak',
        earnedAt: DateTime.utc(2026, 6, 9, 8),
        isPublic: true,
      ),
      authorId: authorId,
      authorName: authorName,
    );

/// Fake feed-backing ApiClient. Reports a signed-in user, returns canned
/// entries + followees + engagement, and records kudos give/rescind calls.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.entries = const [],
    this.followees = const [],
    this.engagement = const {},
    this.badgeAwards = const [],
    this.signedIn = true,
  });
  List<ActivityFeedEntry> entries;
  List<UserProfileRow> followees;
  Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>
      engagement;
  List<BadgeAwardEntry> badgeAwards;
  bool signedIn;
  int giveCalls = 0;
  int rescindCalls = 0;
  String? lastActivityType;
  String? lastAuthorId;

  @override
  String? get userId => signedIn ? 'me' : null;

  @override
  Future<List<ActivityFeedEntry>> fetchFollowingActivityFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async {
    lastActivityType = activityType;
    lastAuthorId = authorId;
    // Filtering happens server-side; the fake honours the author filter so
    // the "no matches" empty state can be exercised.
    if (cursor != null) return const [];
    return entries;
  }

  int followingCalls = 0;
  @override
  Future<List<UserProfileRow>> fetchFollowing(String userId,
      {int limit = 100, int offset = 0}) async {
    followingCalls++;
    return followees;
  }

  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async => engagement;

  @override
  Future<bool> giveKudos(String runId) async {
    giveCalls++;
    return true;
  }

  @override
  Future<bool> rescindKudos(String runId) async {
    rescindCalls++;
    return true;
  }

  @override
  Future<List<BadgeAwardEntry>> fetchFollowingBadgeAwards({
    int limit = 20,
    ({DateTime earnedAt, String id})? cursor,
  }) async =>
      badgeAwards;
}

/// Fake whose initial feed load throws, to drive the error state.
class _ThrowingApi extends _FakeApi {
  @override
  Future<List<ActivityFeedEntry>> fetchFollowingActivityFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async =>
      throw Exception('feed down');
}

/// Fake whose kudos write throws the ApiClient signed-out guard, to drive
/// the optimistic-rollback banner + the friendly-error classification.
class _KudosFailApi extends _FakeApi {
  _KudosFailApi({super.entries, super.engagement});
  @override
  Future<bool> giveKudos(String runId) async {
    giveCalls++;
    throw Exception('Not authenticated');
  }
}

Future<void> _pump(WidgetTester tester, ApiClient api) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FeedScreen(api: api),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(_ensureSupabase);

  group('FeedScreen — initial render', () {
    testWidgets('renders the Feed app-bar title', (tester) async {
      await _pump(tester, _FakeApi());
      await _settle(tester);
      expect(find.text('Feed'), findsOneWidget);
    });

    testWidgets('first frame shows the loading spinner', (tester) async {
      await _pump(tester, _FakeApi());
      // Don't settle — assert the spinner before the load resolves.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('FeedScreen — list rendering', () {
    testWidgets('a feed entry renders the author name + distance stat',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry(distanceM: 5000)],
          followees: [_profileRow('u-1', 'Alex Runner')],
          engagement: {
            'run-1': (kudosCount: 2, viewerHasKudos: false, commentCount: 1),
          },
        ),
      );
      await _settle(tester);
      expect(find.text('Alex Runner'), findsWidgets);
      // 5 km distance stat in the default (km) unit.
      expect(find.textContaining('5.00'), findsOneWidget);
    });

    testWidgets('the kudos count from the engagement map renders',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry()],
          followees: [_profileRow('u-1', 'Alex Runner')],
          engagement: {
            'run-1': (kudosCount: 7, viewerHasKudos: true, commentCount: 3),
          },
        ),
      );
      await _settle(tester);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // viewerHasKudos → filled heart.
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      // Icon-only kudos / comment buttons carry accessibility labels.
      expect(find.bySemanticsLabel('Remove kudos'), findsOneWidget);
      expect(find.bySemanticsLabel('View comments'), findsOneWidget);
    });

    testWidgets('a not-yet-kudoed card exposes the give-kudos label',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: [_runEntry()],
          followees: [_profileRow('u-1', 'Alex Runner')],
          engagement: {
            'run-1': (kudosCount: 0, viewerHasKudos: false, commentCount: 0),
          },
        ),
      );
      await _settle(tester);
      expect(find.bySemanticsLabel('Give kudos'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove kudos'), findsNothing);
    });

    testWidgets('signed-out viewer still loads the feed but skips fetchFollowing',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry(distanceM: 5000)],
        followees: [_profileRow('u-1', 'Alex Runner')],
        signedIn: false,
      );
      await _pump(tester, api);
      await _settle(tester);
      // The entry still renders (the null-userId load path works)...
      expect(find.textContaining('5.00'), findsOneWidget);
      // ...but the author-dropdown follow query is skipped when signed out.
      expect(api.followingCalls, 0);
    });
  });

  group('FeedScreen — empty states', () {
    testWidgets('no follows shows the follow-people empty state',
        (tester) async {
      await _pump(tester, _FakeApi(entries: const [], followees: const []));
      await _settle(tester);
      // The empty state renders with the groups glyph and no toolbar.
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
      expect(find.byType(SegmentedButton<String>), findsNothing);
    });

    testWidgets('follows but no activity shows the toolbar + empty body',
        (tester) async {
      await _pump(
        tester,
        _FakeApi(
          entries: const [],
          followees: [_profileRow('u-1', 'Alex Runner')],
        ),
      );
      await _settle(tester);
      // Toolbar shows because there ARE follows.
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    });
  });

  group('FeedScreen — error state', () {
    testWidgets('a failed initial load shows ErrorState with Retry',
        (tester) async {
      await _pump(tester, _ThrowingApi());
      await _settle(tester);
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('FeedScreen — kudos toggle', () {
    testWidgets('tapping the kudos button optimistically increments + calls give',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry()],
        followees: [_profileRow('u-1', 'Alex Runner')],
        engagement: {
          'run-1': (kudosCount: 4, viewerHasKudos: false, commentCount: 0),
        },
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(find.text('4'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      // Optimistic: count goes to 5 and the heart fills.
      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await _settle(tester);
      expect(api.giveCalls, 1);
    });

    testWidgets('a failed kudos write rolls back the count + surfaces a banner',
        (tester) async {
      final api = _KudosFailApi(
        entries: [_runEntry()],
        engagement: {
          'run-1': (kudosCount: 4, viewerHasKudos: false, commentCount: 0),
        },
      );
      await _pump(tester, api);
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await _settle(tester);

      // Rollback: after the failed write the count returns to 4 and the
      // heart un-fills (the transient optimistic 5 is asserted by the
      // success test; here only the rolled-back end state is stable).
      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(api.giveCalls, 1);
      // The failure is surfaced, not swallowed — and classified: the
      // banner carries the friendly sign-in message, never the raw
      // "Exception: Not authenticated" (issue #240).
      expect(find.textContaining('Could not update kudos'), findsOneWidget);
      expect(find.textContaining('signed in'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      await tester.pump(const Duration(seconds: 4)); // drain banner timer
    });
  });

  group('FeedScreen — badge strip', () {
    testWidgets('renders a chip per recent badge award above the feed',
        (tester) async {
      final api = _FakeApi(
        entries: [_runEntry()],
        badgeAwards: [_badgeAward(authorName: 'Alex Runner')],
      );
      await _pump(tester, api);
      await _settle(tester);
      expect(
        find.textContaining('Alex Runner earned the Century streak badge'),
        findsOneWidget,
      );
    });

    testWidgets('no strip when there are no badge awards', (tester) async {
      final api = _FakeApi(entries: [_runEntry()], badgeAwards: const []);
      await _pump(tester, api);
      await _settle(tester);
      expect(find.byType(ActionChip), findsNothing);
    });
  });
}
