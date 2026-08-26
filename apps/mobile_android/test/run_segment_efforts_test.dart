import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/global_segments_screen.dart';
import '../lib/widgets/run_segment_efforts.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
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

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunSegmentEfforts(
          api: ApiClient(),
          runId: 'fake-run-id',
          routeId: null,
          track: const [],
        ),
      ),
    ),
  );
}

Future<void> _pumpWith(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunSegmentEfforts(
          api: api,
          runId: 'run-1',
          runOwnerId: 'viewer-1',
          routeId: null,
          track: const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

GlobalSegmentEffortWithSegment _catalogueEffort({int? rank = 4}) =>
    GlobalSegmentEffortWithSegment(
      effort: GlobalSegmentEffortRow(
        id: 'ge-1',
        globalSegmentId: 'gs-1',
        runId: 'run-1',
        userId: 'viewer-1',
        timeSeconds: 305,
        startedAt: DateTime.parse('2026-02-01T00:00:00Z'),
        createdAt: DateTime.parse('2026-02-01T00:00:00Z'),
      ),
      segment: GlobalSegmentRow(
        id: 'gs-1',
        name: 'Harlem Hill',
        waypoints: const [],
        distanceM: 857,
        elevationM: 18,
        surface: 'road',
        region: 'New York, US',
        isActive: true,
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      ),
      rank: rank,
    );

SegmentEffortWithSegment _routeEffort({int? rank = 2}) =>
    SegmentEffortWithSegment(
      effort: SegmentEffortRow(
        id: 'se-1',
        segmentId: 'seg-1',
        runId: 'run-1',
        userId: 'viewer-1',
        timeSeconds: 420,
        startedAt: DateTime.parse('2026-02-01T00:00:00Z'),
        createdAt: DateTime.parse('2026-02-01T00:00:00Z'),
      ),
      segment: SegmentRow(
        id: 'seg-1',
        routeId: 'route-1',
        name: 'Canal Straight',
        startDistanceM: 0,
        endDistanceM: 1000,
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      ),
      rank: rank,
    );

class _EffortsApi extends ApiClient {
  _EffortsApi({this.routeEfforts = const [], this.globalEfforts = const []});

  final List<SegmentEffortWithSegment> routeEfforts;
  final List<GlobalSegmentEffortWithSegment> globalEfforts;

  @override
  String? get userId => 'viewer-1';

  @override
  Future<List<SegmentEffortWithSegment>> fetchEffortsForRunWithSegments(
    String runId,
  ) async =>
      routeEfforts;

  @override
  Future<List<GlobalSegmentEffortWithSegment>> fetchGlobalEffortsForRun(
    String runId,
  ) async =>
      globalEfforts;
}

class _ThrowingCatalogueApi extends _EffortsApi {
  _ThrowingCatalogueApi({super.routeEfforts});

  @override
  Future<List<GlobalSegmentEffortWithSegment>> fetchGlobalEffortsForRun(
    String runId,
  ) async =>
      throw StateError('catalogue efforts unavailable');
}

class _CatalogueBrowseApi extends _EffortsApi {
  _CatalogueBrowseApi({super.globalEfforts});

  @override
  Future<List<GlobalSegmentRow>> fetchGlobalSegments({
    int limit = kGlobalSegmentCatalogueLimit,
  }) async =>
      const [];

  @override
  Future<GlobalSegmentRow?> fetchGlobalSegment(String id) async => null;
}

void main() {
  setUpAll(_ensureSupabase);

  group('RunSegmentEfforts — initial render', () {
    testWidgets('shows the "Checking segments…" loading hint',
        (tester) async {
      // Reason: while _loading is true the widget renders just a
      // small text label — that's the only deterministic surface in
      // tests without a working Supabase backend.
      await _pump(tester);
      expect(find.text('Checking segments…'), findsOneWidget);
    });
  });

  group('RunSegmentEfforts — an unanswered rank', () {
    // `segment_effort_ranks` / `global_segment_effort_ranks` deliver the rank
    // separately from the effort row, so an effort the RPC did not answer for
    // has no known standing. Both clients used to spend that as `?? 1`, which
    // renders the crown — the most flattering claim the chip can make, from
    // having no answer at all (decisions §746). Against `main` every
    // expectation below fails: the pill read '#1' in crown colours.

    testWidgets('a route effort with no rank renders the placeholder, not #1',
        (tester) async {
      await _pumpWith(tester, _EffortsApi(routeEfforts: [_routeEffort(rank: null)]));
      expect(find.text('Canal Straight'), findsOneWidget);
      expect(find.text(kUnknownRankText), findsOneWidget);
      expect(find.text('#1'), findsNothing);
    });

    testWidgets('a catalogue effort with no rank renders the placeholder',
        (tester) async {
      await _pumpWith(
        tester,
        _EffortsApi(globalEfforts: [_catalogueEffort(rank: null)]),
      );
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text(kUnknownRankText), findsOneWidget);
      expect(find.text('#1'), findsNothing);
    });

    testWidgets('the placeholder pill is named for assistive tech',
        (tester) async {
      // TalkBack reading out an em dash tells the runner nothing.
      final handle = tester.ensureSemantics();
      await _pumpWith(tester, _EffortsApi(routeEfforts: [_routeEffort(rank: null)]));
      expect(find.bySemanticsLabel('Rank unavailable'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an unknown standing does not take the crown fill',
        (tester) async {
      await _pumpWith(tester, _EffortsApi(routeEfforts: [_routeEffort(rank: null)]));
      final theme = Theme.of(
        tester.element(find.text(kUnknownRankText)),
      );
      expect(rankPillColors(theme, null), isNot(rankPillColors(theme, 1)));
      expect(rankPillColors(theme, null), rankPillColors(theme, 99));
    });
  });

  group('RunSegmentEfforts — catalogue efforts', () {
    testWidgets('a catalogue effort renders under its own heading with a browse link',
        (tester) async {
      await _pumpWith(
        tester,
        _EffortsApi(globalEfforts: [_catalogueEffort()]),
      );
      expect(find.text('Famous segments'), findsOneWidget);
      expect(find.text('Browse all'), findsOneWidget);
      expect(find.text('Harlem Hill'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('5:05'), findsOneWidget);
      // Must not read as a run with no efforts at all.
      expect(find.text('No segment efforts on this run.'), findsNothing);
    });

    testWidgets('a run with no catalogue effort renders no catalogue section',
        (tester) async {
      await _pumpWith(tester, _EffortsApi(routeEfforts: [_routeEffort()]));
      expect(find.text('Canal Straight'), findsOneWidget);
      expect(find.text('Famous segments'), findsNothing);
      expect(find.text('Browse all'), findsNothing);
    });

    testWidgets('tapping a catalogue row opens that segment', (tester) async {
      await _pumpWith(
        tester,
        _CatalogueBrowseApi(globalEfforts: [_catalogueEffort()]),
      );
      await tester.tap(find.text('Harlem Hill'));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSegmentDetailScreen), findsOneWidget);
    });

    testWidgets('Browse all opens the catalogue', (tester) async {
      await _pumpWith(
        tester,
        _CatalogueBrowseApi(globalEfforts: [_catalogueEffort()]),
      );
      await tester.tap(find.text('Browse all'));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSegmentsScreen), findsOneWidget);
    });

    testWidgets('a failed catalogue read keeps the route-segment chips',
        (tester) async {
      // The catalogue list is the additive layer of this panel; its failure
      // must not cost the run the efforts it already had.
      await _pumpWith(
        tester,
        _ThrowingCatalogueApi(routeEfforts: [_routeEffort()]),
      );
      expect(find.text('Canal Straight'), findsOneWidget);
      expect(find.text('Famous segments'), findsNothing);
    });
  });
}
