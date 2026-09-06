import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/segments_panel.dart';

/// Segments list fetch always fails.
class _ThrowingListApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';
  @override
  Future<List<SegmentRow>> fetchSegmentsForRoute(String routeId,
          {int limit = 100}) async =>
      throw StateError('segments network down');
}

/// Segments list succeeds with one segment; the leaderboard fetch fails.
class _ThrowingLeaderboardApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';
  @override
  Future<List<SegmentRow>> fetchSegmentsForRoute(String routeId,
          {int limit = 100}) async =>
      [
        SegmentRow(
          id: 'seg-1',
          routeId: routeId,
          name: 'Test Segment',
          startDistanceM: 1000,
          endDistanceM: 2000,
          createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
        ),
      ];
  @override
  Future<List<SegmentLeaderboardEntry>> fetchSegmentLeaderboardTiered(
          String segmentId,
          {String? gender,
          String? ageBand,
          int limit = 50}) async =>
      throw StateError('leaderboard network down');
}

/// Segments list succeeds with one segment whose leaderboard puts the viewer
/// second, so the viewer row and a plain row render side by side.
class _ViewerLeaderboardApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';
  @override
  Future<List<SegmentRow>> fetchSegmentsForRoute(String routeId,
          {int limit = 100}) async =>
      [
        SegmentRow(
          id: 'seg-1',
          routeId: routeId,
          name: 'Test Segment',
          startDistanceM: 1000,
          endDistanceM: 2000,
          createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
        ),
      ];
  @override
  Future<List<SegmentLeaderboardEntry>> fetchSegmentLeaderboardTiered(
      String segmentId,
      {String? gender,
      String? ageBand,
      int limit = 50}) async {
    SegmentLeaderboardEntry entry(String user, String name, int rank) =>
        SegmentLeaderboardEntry(
          effort: SegmentEffortRow(
            id: 'e-$user',
            segmentId: segmentId,
            runId: 'r-$user',
            userId: user,
            timeSeconds: 300.0 + rank,
            startedAt: DateTime.parse('2026-01-02T00:00:00Z'),
            createdAt: DateTime.parse('2026-01-02T00:00:00Z'),
          ),
          athlete: PublicProfile(id: user, displayName: name),
          rank: rank,
        );
    return [entry('other-1', 'Rival', 1), entry('viewer-1', 'Me', 2)];
  }
}

/// Segments list resolves empty (no network); used to reach the create form.
class _EmptyListApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';
  @override
  Future<List<SegmentRow>> fetchSegmentsForRoute(String routeId,
          {int limit = 100}) async =>
      [];
}

Widget _hostWithApi(ApiClient api, {bool canCreate = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SegmentsPanel(
          api: api,
          routeId: 'fake-route-id',
          routeDistanceM: 5000,
          canCreate: canCreate,
        ),
      ),
    );

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

Future<void> _pump(WidgetTester tester, {bool canCreate = false}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SegmentsPanel(
          api: ApiClient(),
          routeId: 'fake-route-id',
          routeDistanceM: 5000,
          canCreate: canCreate,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('SegmentsPanel — initial render', () {
    testWidgets('renders the Segments heading', (tester) async {
      await _pump(tester);
      expect(find.text('Segments'), findsOneWidget);
    });

    testWidgets('shows the "Loading segments…" hint while fetching',
        (tester) async {
      // Reason: while _loading is true the body renders only a small
      // text label — no SegmentTile or "No segments" empty state.
      await _pump(tester);
      expect(find.text('Loading segments…'), findsOneWidget);
    });

    testWidgets('hides the New segment button when canCreate is false',
        (tester) async {
      // canCreate is now "signed-in viewer" (segments are community
      // contributions), so false = signed-out → no add button.
      await _pump(tester, canCreate: false);
      expect(find.text('New segment'), findsNothing);
    });

    testWidgets('shows the New segment button when canCreate is true',
        (tester) async {
      await _pump(tester, canCreate: true);
      expect(find.text('New segment'), findsOneWidget);
    });
  });

  group('SegmentsPanel — load failures surface (not silent-empty)', () {
    testWidgets('a failed segments load shows an error + retry', (tester) async {
      await tester.pumpWidget(_hostWithApi(_ThrowingListApi()));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't load segments"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Must NOT read as a genuinely empty route.
      expect(find.text('No segments on this route yet.'), findsNothing);
    });

    testWidgets(
        'a failed leaderboard load shows an error + retry, not "No efforts yet"',
        (tester) async {
      await tester.pumpWidget(_hostWithApi(_ThrowingLeaderboardApi()));
      await tester.pump();
      await tester.pump();
      expect(find.text('Test Segment'), findsOneWidget);

      await tester.tap(find.text('Test Segment'));
      await tester.pump();
      await tester.pump();

      expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('SegmentsPanel — leaderboard viewer row', () {
    // The viewer row's `primaryContainer@0.5` tint is 1.078:1 light / 1.013:1
    // dark against the row above it, so WCAG 1.4.1 needs a cue that is not
    // colour. The label reuses `navYou`; the weight is the second cue.
    testWidgets('marks the viewer with a label and a weight, not just a tint',
        (tester) async {
      await tester.pumpWidget(_hostWithApi(_ViewerLeaderboardApi()));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Test Segment'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Rival'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);

      TextStyle styleOf(String name) =>
          tester.widget<Text>(find.text(name)).style!;
      expect(styleOf('Me').fontWeight, FontWeight.w700);
      expect(styleOf('Rival').fontWeight, isNot(FontWeight.w700));
    });
  });

  group('SegmentsPanel — create validation', () {
    testWidgets('creating a segment with an empty name shows a validation banner',
        (tester) async {
      await tester.pumpWidget(_hostWithApi(_EmptyListApi(), canCreate: true));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('New segment'));
      await tester.pump();
      // Tap Create with the name still empty — before the fix this silently
      // did nothing.
      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(find.text('Enter a segment name'), findsOneWidget);
    });
  });

  group('canDeleteSegment', () {
    test('route owner can delete any segment (moderation)', () {
      expect(canDeleteSegment('someone-else', 'owner', true), isTrue);
      expect(canDeleteSegment(null, 'owner', true), isTrue);
    });
    test('a non-owner can delete only their own segment', () {
      expect(canDeleteSegment('me', 'me', false), isTrue);
      expect(canDeleteSegment('someone-else', 'me', false), isFalse);
    });
    test('a signed-out viewer can delete nothing', () {
      expect(canDeleteSegment('me', null, false), isFalse);
      expect(canDeleteSegment(null, null, false), isFalse);
    });
  });
}
