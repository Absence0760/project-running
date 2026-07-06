// Widget tests for RunHeatmapScreen — the mobile mirror of web
// /runs/heatmap. The runs + track downloads are supplied through the
// fetchRunsFn / fetchTrackFn test seams so the chain (runs → track
// download → cell aggregation → render) is exercised without the
// network. flutter_map tile fetches fail under the test runner (same
// constraint the routes-heatmap test deals with); we pin the chrome +
// the data path + the legend / empty states, not tile-load success.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_heatmap_screen.dart';

class _FakeApiClient extends ApiClient {}

cm.Run _run(String id, {String? trackUrl}) => cm.Run(
      id: id,
      startedAt: DateTime.utc(2026, 1, 1),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: cm.RunSource.app,
      metadata: trackUrl == null ? null : {'track_url': trackUrl},
    );

List<cm.Waypoint> _track() => const [
      cm.Waypoint(lat: 51.5, lng: -0.12),
      cm.Waypoint(lat: 51.5001, lng: -0.1201),
      cm.Waypoint(lat: 51.5002, lng: -0.1202),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<cm.Run>> Function() fetchRunsFn,
  required Future<List<cm.Waypoint>> Function(String) fetchTrackFn,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunHeatmapScreen(
        api: _FakeApiClient(),
        fetchRunsFn: fetchRunsFn,
        fetchTrackFn: fetchTrackFn,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders the heatmap chrome', (tester) async {
    await _pump(
      tester,
      fetchRunsFn: () async => [_run('a', trackUrl: 'u/a.json.gz')],
      fetchTrackFn: (_) async => _track(),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.widgetWithText(AppBar, l10n.runHeatmapTitle), findsOneWidget);
  });


  testWidgets('aggregates downloaded tracks and shows the legend',
      (tester) async {
    var trackCalls = 0;
    await _pump(
      tester,
      fetchRunsFn: () async => [
        _run('a', trackUrl: 'u/a.json.gz'),
        _run('b', trackUrl: 'u/b.json.gz'),
      ],
      fetchTrackFn: (_) async {
        trackCalls++;
        return _track();
      },
    );
    // Let the bounded-concurrency downloads + aggregation settle.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(trackCalls, 2);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // Both tracks aggregated → the two-run legend summary, distinct from
    // the AppBar/legend title (which share the "Your heatmap" string).
    expect(find.text(l10n.runHeatmapLegendSummaryMany(2)), findsOneWidget);
  });

  testWidgets('shows the empty state when no run carries a track',
      (tester) async {
    await _pump(
      tester,
      fetchRunsFn: () async => [_run('a'), _run('b')],
      fetchTrackFn: (_) async => const [],
    );
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.runHeatmapEmptyTitle), findsOneWidget);
  });

  testWidgets('a failed runs fetch shows a retryable error, not the empty state',
      (tester) async {
    // A thrown fetch means we never learned whether the runner has mapped
    // runs — the screen must surface a distinct error + retry, NOT the
    // "No mapped runs yet" empty state (which would tell an active runner
    // they've never run anywhere). Retry recovers.
    var fail = true;
    await _pump(
      tester,
      fetchRunsFn: () async {
        if (fail) {
          fail = false;
          throw Exception('simulated failure');
        }
        return [_run('a', trackUrl: 'u/a.json.gz')];
      },
      fetchTrackFn: (_) async => _track(),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.runHeatmapErrorTitle), findsOneWidget);
    expect(find.text(l10n.runHeatmapEmptyTitle), findsNothing);

    // Retry — the second fetch succeeds, so the error clears and the legend
    // renders (never stuck on the error).
    await tester.tap(find.text(l10n.runHeatmapRetry));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l10n.runHeatmapErrorTitle), findsNothing);
    expect(find.text(l10n.runHeatmapLegendSummaryOne(1)), findsOneWidget);
  });
}
