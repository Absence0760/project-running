import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/global_segments_screen.dart';

GlobalSegmentRow _segment({
  required String id,
  required String name,
  String surface = 'road',
  String? region,
  double distanceM = 1200,
  double? elevationM = 12,
  String? description,
  List<Map<String, dynamic>> waypoints = const [],
}) =>
    GlobalSegmentRow(
      id: id,
      name: name,
      description: description,
      waypoints: waypoints,
      distanceM: distanceM,
      elevationM: elevationM,
      surface: surface,
      region: region,
      isActive: true,
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );

final _catalogue = [
  _segment(
    id: 'a',
    name: 'Champs-Élysées Sprint',
    region: 'Paris, FR',
    distanceM: 2135,
    elevationM: 0,
  ),
  _segment(
    id: 'b',
    name: 'Harlem Hill',
    region: 'New York, US',
    surface: 'trail',
    distanceM: 857,
    elevationM: 18,
  ),
];

class _CatalogueApi extends ApiClient {
  _CatalogueApi(this.segments, {this.viewer = 'viewer-1'});

  final List<GlobalSegmentRow> segments;
  final String? viewer;

  @override
  String? get userId => viewer;

  @override
  Future<List<GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      segments;

  @override
  Future<GlobalSegmentRow?> fetchGlobalSegment(String id) async =>
      segments.where((s) => s.id == id).firstOrNull;

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int limit = 50,
  }) async =>
      const [];
}

class _ThrowingCatalogueApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';

  @override
  Future<List<GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      throw StateError('catalogue network down');
}

class _BoardApi extends _CatalogueApi {
  _BoardApi(super.segments, this.board);

  final List<GlobalSegmentLeaderboardEntry> board;

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int limit = 50,
  }) async =>
      board;
}

class _ThrowingBoardApi extends _CatalogueApi {
  _ThrowingBoardApi(super.segments);

  @override
  Future<List<GlobalSegmentLeaderboardEntry>> fetchGlobalSegmentLeaderboard(
    String segmentId, {
    String? gender,
    String? ageBand,
    String? clubId,
    int limit = 50,
  }) async =>
      throw StateError('leaderboard network down');
}

GlobalSegmentLeaderboardEntry _entry(String userId, String name, int rank) =>
    GlobalSegmentLeaderboardEntry(
      effort: GlobalSegmentEffortRow(
        id: 'e-$userId',
        globalSegmentId: 'a',
        runId: 'r-$userId',
        userId: userId,
        timeSeconds: 300.0 + rank,
        startedAt: DateTime.parse('2026-02-01T00:00:00Z'),
        createdAt: DateTime.parse('2026-02-01T00:00:00Z'),
      ),
      athlete: PublicProfile(id: userId, displayName: name),
      rank: rank,
    );

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

bool _supabaseReady = false;

Future<void> _ensureEnvironment() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  dotenv.loadFromString(envString: '', isOptional: true);
  dotenv.env.clear();
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

void main() {
  setUpAll(_ensureEnvironment);

  group('GlobalSegmentsScreen — browse', () {
    testWidgets('renders one card per catalogue segment with its region',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      expect(find.text('Champs-Élysées Sprint'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text('Paris, FR'), findsOneWidget);
      expect(find.text('2 segments'), findsOneWidget);
    });

    testWidgets('an accent-free query still reaches an accented name',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'champs-elysees');
      await tester.pumpAndSettle();
      expect(find.text('Champs-Élysées Sprint'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsNothing);
      expect(find.text('1 segment'), findsOneWidget);
    });

    testWidgets('a query that matches nothing says so rather than showing zero',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nowhere at all');
      await tester.pumpAndSettle();
      expect(
        find.text('No segments match these filters — try widening them.'),
        findsOneWidget,
      );
      expect(find.text('0 segments'), findsNothing);
    });

    testWidgets('the surface filter narrows to that surface only',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All surfaces').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trail').last);
      await tester.pumpAndSettle();
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text('Champs-Élysées Sprint'), findsNothing);
    });

    testWidgets('a failed catalogue load offers a retry, not an empty state',
        (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _ThrowingCatalogueApi())));
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t load the segment catalogue.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('No famous segments in the catalogue yet.'),
        findsNothing,
      );
    });

    testWidgets('an empty catalogue renders the empty state', (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(const []))));
      await tester.pumpAndSettle();
      expect(
        find.text('No famous segments in the catalogue yet.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a signed-out viewer still browses the world-readable catalogue',
        (tester) async {
      await tester.pumpWidget(
        _host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue, viewer: null))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Harlem Hill'), findsOneWidget);
    });

    testWidgets('tapping a card opens that segment', (tester) async {
      await tester.pumpWidget(_host(GlobalSegmentsScreen(api: _CatalogueApi(_catalogue))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Harlem Hill'));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSegmentDetailScreen), findsOneWidget);
      expect(find.text('Elevation gain'), findsOneWidget);
    });
  });

  group('GlobalSegmentDetailScreen', () {
    testWidgets('renders the segment stats and description', (tester) async {
      final api = _CatalogueApi([
        _segment(
          id: 'a',
          name: 'Harlem Hill',
          region: 'New York, US',
          distanceM: 857,
          elevationM: 18,
          description: 'The classic north-end climb.',
        ),
      ]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text('The classic north-end climb.'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Elevation gain'), findsOneWidget);
      expect(find.text('Road'), findsOneWidget);
    });

    testWidgets('an unknown or retired segment renders the not-found state',
        (tester) async {
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: _CatalogueApi(const []), segmentId: 'gone')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Segment not found'), findsOneWidget);
      expect(find.text('Leaderboard'), findsNothing);
    });

    testWidgets('the leaderboard marks the crown holder and the viewer',
        (tester) async {
      final api = _BoardApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        [_entry('other-1', 'Rival', 1), _entry('viewer-1', 'Me', 2)],
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rival'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('the viewer holding rank 1 sees the crown banner',
        (tester) async {
      final api = _BoardApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        [_entry('viewer-1', 'Me', 1)],
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('You hold this crown — Fastest overall.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed leaderboard offers a retry, not "No efforts yet"',
        (tester) async {
      final api = _ThrowingBoardApi([_segment(id: 'a', name: 'Harlem Hill')]);
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the leaderboard"), findsOneWidget);
      expect(
        find.text('No efforts yet — be the first to run this segment.'),
        findsNothing,
      );
    });

    testWidgets(
        'a signed-out viewer is asked to sign in rather than shown a doomed retry',
        (tester) async {
      final api = _CatalogueApi(
        [_segment(id: 'a', name: 'Harlem Hill')],
        viewer: null,
      );
      await tester.pumpWidget(
        _host(GlobalSegmentDetailScreen(api: api, segmentId: 'a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text("Couldn't load the leaderboard"), findsNothing);
      expect(find.text('Loading…'), findsNothing);
    });
  });
}
