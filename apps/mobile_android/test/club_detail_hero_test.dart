import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/club_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'realtime_drain.dart';

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

/// One paragraph past the composer's 500-character cap. `clubs.description`
/// carries no DB length constraint, so the layout has to survive whatever a
/// direct API write puts there, not merely what the composer allows.
final String _longDescription =
    'We are a friendly community running club that meets three times a week '
    'for social runs, tempo sessions and long weekend efforts along the river '
    'path. All paces welcome, from first-timers walking their first kilometre '
    'to sub-three marathoners. We finish every Saturday run at the cafe on '
    'the corner and we would love to see you there. ' *
        4;

ClubView _club(String? description) => ClubView(
      row: ClubRow(
        shadowHidden: false,
        id: 'club-1',
        ownerId: 'owner',
        name: 'Track Club',
        slug: 'track-club',
        isPublic: true,
        joinPolicy: 'open',
        memberCount: 5,
        isVerified: false,
        requiresActivityWaiver: false,
        description: description,
        locationLabel: 'Portland, OR',
      ),
      memberCount: 5,
      viewerRole: null,
      viewerStatus: null,
      joinPolicy: 'open',
    );

class _FakeSocial extends SocialService {
  _FakeSocial(this.description);

  final String? description;

  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _club(description);
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(
    String clubId, {
    int limit = 20,
  }) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async =>
      const [];
  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u-viewer';
  @override
  Future<List<GymRoutineRow>> fetchClubGymRoutineTemplates(String c) async =>
      const [];
  @override
  Future<List<SessionPlanRow>> fetchClubSessionTemplates(String c) async =>
      const [];
}

class _FakeTraining extends TrainingService {
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      const [];
}

Future<void> _pump(
  WidgetTester tester, {
  required String? description,
  Size size = const Size(360, 640),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ClubDetailScreen(
        social: _FakeSocial(description),
        training: _FakeTraining(),
        apiClient: _FakeApi(),
        slug: 'track-club',
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The description `Text` inside the hero — the clamped one, as opposed to the
/// unclamped copy the Read-more sheet renders.
Text _heroDescription(WidgetTester tester) => tester.widget<Text>(
      find.text(_longDescription).first,
    );

void main() {
  setUpAll(_ensureSupabase);

  group('club detail hero (issue #666 C12)', () {
    realtimeWidgetTest('a long description is clamped and offers the rest', (
      tester,
    ) async {
      await _pump(tester, description: _longDescription);

      // Population: the description really is present and really is clamped —
      // an assertion about maxLines proves nothing over a description the
      // screen never rendered.
      expect(find.text(_longDescription), findsOneWidget);
      expect(_heroDescription(tester).maxLines, kClubDescriptionMaxLines);
      expect(_heroDescription(tester).overflow, TextOverflow.ellipsis);
      expect(find.text('Read more'), findsOneWidget);
    });

    realtimeWidgetTest('a short description is not clamped away behind a '
        'Read more', (tester) async {
      await _pump(tester, description: 'We run on Tuesdays.');

      expect(find.text('We run on Tuesdays.'), findsOneWidget);
      expect(find.text('Read more'), findsNothing);
    });

    realtimeWidgetTest('Read more shows the whole description', (tester) async {
      await _pump(tester, description: _longDescription);

      await tester.tap(find.text('Read more'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Two copies now: the clamped hero one and the sheet's unclamped one.
      expect(find.text(_longDescription), findsNWidgets(2));
      final sheetCopy = tester
          .widgetList<Text>(find.text(_longDescription))
          .where((t) => t.maxLines == null);
      expect(sheetCopy, isNotEmpty);
    });

    // The derivation, not an absolute fit: description LENGTH no longer moves
    // the hero/tabs split, because the hero renders at most
    // [kClubDescriptionMaxLines] of it however long it is. Comparing two
    // lengths at one scale is font-independent — flutter_test's fixed-advance
    // font inflates both sides identically (decisions § 500) — where an
    // absolute "the tabs get N dp" would not be measurable in CI at all.
    for (final scale in <double>[1.0, 1.5]) {
      realtimeWidgetTest(
        'description length does not move the hero/tabs split at ${scale}x',
        (tester) async {
          await _pump(tester, description: _longDescription, textScale: scale);
          expect(find.text('Read more'), findsOneWidget);
          final atCap = tester.getSize(find.byType(TabBarView)).height;

          await _pump(
            tester,
            description: _longDescription * 10,
            textScale: scale,
          );
          expect(find.text('Read more'), findsOneWidget);
          final tenTimesLonger =
              tester.getSize(find.byType(TabBarView)).height;

          expect(atCap, greaterThan(0));
          expect(
            tenTimesLonger,
            atCap,
            reason: 'a longer description still eats the tab bodies',
          );
        },
      );
    }

    realtimeWidgetTest('a small phone no longer overflows on a long '
        'description', (tester) async {
      await _pump(
        tester,
        description: _longDescription,
        size: const Size(320, 568),
      );

      expect(find.text('Read more'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TabBarView)).height,
        greaterThan(0),
        reason: 'the hero starved the six tab bodies to nothing',
      );
    });
  });
}
