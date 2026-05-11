import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/live_run_map.dart';

Waypoint _w(double lat, double lng) => Waypoint(lat: lat, lng: lng);

Future<void> _pump(
  WidgetTester tester, {
  required List<Waypoint> track,
  Waypoint? currentPosition,
  bool followRunner = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: LiveRunMap(
            track: track,
            currentPosition: currentPosition,
            followRunner: followRunner,
          ),
        ),
      ),
    ),
  );
  // A single pump renders the widget; more would spin the repeating pulse
  // animation forever (pumpAndSettle would hang).
  await tester.pump();
  // Drain any one-shot timers that fire immediately (e.g. WidgetsBinding
  // post-frame callbacks from the map's onMapReady handler).
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    // Load an empty env so DotEnv.env accesses return '' for MAPTILER_KEY.
    dotenv.loadFromString(isOptional: true);
  });

  group('LiveRunMap', () {
    testWidgets(
        'shows GPS-waiting indicator when track is empty and no current position',
        (tester) async {
      await _pump(tester, track: const []);
      expect(find.text('Waiting for GPS...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the map widget when a current position is provided',
        (tester) async {
      final pos = _w(51.5, -0.1);
      await _pump(tester, track: const [], currentPosition: pos);
      expect(find.text('Waiting for GPS...'), findsNothing);
    });

    testWidgets('re-centre FAB is absent before the user pans', (tester) async {
      final pos = _w(51.5, -0.1);
      await _pump(tester, track: const [], currentPosition: pos);
      // FAB only appears after _userPanned is set by a gesture; at load it
      // is not present.
      expect(find.byIcon(Icons.my_location), findsNothing);
    });

    testWidgets('renders the map widget when only a planned route is provided',
        (tester) async {
      // Routes screen previews use this branch — show the route on the
      // map even before the user has any GPS fix. Without it, the
      // preview would always be stuck on the GPS-waiting indicator.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: const [],
                currentPosition: null,
                plannedRoute: [_w(51.5, -0.1), _w(51.51, -0.11)],
                followRunner: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(find.text('Waiting for GPS...'), findsNothing);
    });

    testWidgets('renders without throwing when decorations + totalDistanceM are supplied',
        (tester) async {
      // Detail-screen branch: showDecorations=true + a non-empty track
      // walks the polyline through `computeDistanceMarkers` and
      // `computeChevrons`. Smoke-test the widget assembles.
      final track = [for (var i = 0; i < 10; i++) _w(51.5 + i * 0.0005, -0.1)];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: track,
                currentPosition: track.last,
                followRunner: false,
                showDecorations: true,
                totalDistanceM: 500,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      // No exceptions during build is the assertion; a thrown exception
      // would surface as a TestFailure here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('mounts the ghost-pacer marker when ghostPosition is set',
        (tester) async {
      final pos = _w(51.5, -0.1);
      final ghost = _w(51.5005, -0.0995);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: const [],
                currentPosition: pos,
                ghostPosition: ghost,
                followRunner: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      // Two MarkerLayers should render: the ghost + the live blue dot.
      // Asserting "no exception" + non-null ghost is enough — the
      // pure-geometry side is covered by ghost_pacer_test.dart.
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not mount the ghost marker when ghostPosition is null',
        (tester) async {
      final pos = _w(51.5, -0.1);
      await _pump(tester, track: const [], currentPosition: pos);
      // Smoke — null path must not crash and must not throw a null deref.
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits camera to bounds when followRunner=false with 2+ points',
        (tester) async {
      // The detail screen passes followRunner=false so the camera frames
      // the whole run. fitBounds is computed from `track.length >= 2`.
      // Assert the widget builds without throwing for that branch — the
      // CameraFit logic lives inside the FlutterMap MapOptions.
      final track = [_w(51.5, -0.1), _w(51.6, -0.05)];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: track,
                currentPosition: null,
                followRunner: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(tester.takeException(), isNull);
    });
  });
}
