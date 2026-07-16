import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/public_run_screen.dart';

/// Test seam: returns a canned public run + author profile so `_load`
/// resolves without a backend. Track fetches are stubbed to empty so
/// `LiveRunMap` mounts with no data.
class _FakeApi extends ApiClient {
  final RunRow run;
  final UserProfileRow author;
  _FakeApi({required this.run, required this.author});

  @override
  Future<RunRow?> fetchPublicRunById(String runId) async => run;

  @override
  Future<UserProfileRow?> fetchPublicProfile(String userId) async => author;

  @override
  Future<List<Waypoint>> fetchTrackByPath(String path) async => const [];

  @override
  Future<List<Waypoint>> fetchClippedTrackForRun(String runId) async =>
      const [];
}

RunRow _run() => RunRow(
      id: 'r1',
      userId: 'u1',
      startedAt: DateTime(2026, 6, 1, 8),
      durationS: 1800,
      distanceM: 5000,
      source: 'app',
      activityType: 'run',
      isDnf: false,
    );

/// A 100-hour, 240-mile ultra: the widest the stat cells ever get
/// ("104:32:11" / "386.24"), which is what overflowed the row.
RunRow _ultraRun() => RunRow(
      id: 'r1',
      userId: 'u1',
      startedAt: DateTime(2026, 6, 1, 8),
      durationS: 376331,
      distanceM: 386243,
      source: 'app',
      activityType: 'run',
      isDnf: false,
    );

UserProfileRow _author(String displayName) => UserProfileRow(
      id: 'u1',
      displayName: displayName,
      shadowHidden: false,
    );

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  // LiveRunMap reads dotenv for the tile-style key; an empty env makes
  // those reads return '' instead of throwing NotInitializedError.
  dotenv.loadFromString(isOptional: true);
  SharedPreferences.setMockInitialValues({});
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
      home: PublicRunScreen(api: ApiClient(), runId: 'fake-run-id'),
    ),
  );
}

Future<void> _pumpApi(WidgetTester tester, ApiClient api) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PublicRunScreen(api: api, runId: 'r1'),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('PublicRunScreen — initial render', () {
    testWidgets('renders the Run app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Run'), findsOneWidget);
    });

    testWidgets('first frame shows the loading indicator', (tester) async {
      await _pump(tester);
      // Single pump only — the post-fetch frame swaps in either
      // ErrorState or the run body once Supabase resolves.
      expect(find.byType(ActivityLoader), findsOneWidget);
    });
  });

  group('PublicRunScreen — long author display name on a narrow phone', () {
    testWidgets(
        'a long author name ellipsizes and stays inside the row',
        (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(720, 1280);
      view.devicePixelRatio = 2.0;
      addTearDown(view.reset);

      final longName = 'A' * 60;
      await _pumpApi(
        tester,
        _FakeApi(run: _run(), author: _author(longName)),
      );
      // initState's _load awaits Future.wait; settle it with timed
      // pumps instead of pumpAndSettle, which hangs on LiveRunMap's
      // marker/pulse animations.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);

      final nameFinder = find.text(longName);
      expect(nameFinder, findsOneWidget);
      final nameWidget = tester.widget<Text>(nameFinder);
      expect(nameWidget.maxLines, 1);
      expect(nameWidget.overflow, TextOverflow.ellipsis);
      expect(tester.getRect(nameFinder).right, lessThanOrEqualTo(360.0));
    });
  });

  group('PublicRunScreen — stat row at a narrow width', () {
    testWidgets('an ultra-length distance/time/pace does not overflow the row',
        (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(720, 1280);
      view.devicePixelRatio = 2.0;
      addTearDown(view.reset);

      await _pumpApi(
        tester,
        _FakeApi(run: _ultraRun(), author: _author('Al')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });
}
