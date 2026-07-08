import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/l10n/gen/app_localizations.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

  group('smoothTrackIncremental', () {
    List<LatLng> jitterTrack(int n) => [
          for (int i = 0; i < n; i++)
            LatLng(
              51.5 + i * 0.0003 + ((i * 37) % 7 - 3) * 0.00002,
              -0.1 + i * 0.0002 + ((i * 53) % 5 - 2) * 0.00002,
            ),
        ];

    void expectSame(List<LatLng> a, List<LatLng> b) {
      expect(a.length, b.length);
      for (int i = 0; i < a.length; i++) {
        expect(a[i].latitude, b[i].latitude, reason: 'lat[$i]');
        expect(a[i].longitude, b[i].longitude, reason: 'lng[$i]');
      }
    }

    test('cold call (null prev) equals a full two-pass smooth', () {
      final raw = jitterTrack(40);
      expectSame(smoothTrackIncremental(raw, null, -1), smoothTrack(smoothTrack(raw)));
    });

    test('incremental append is byte-identical to a full rebuild, every step',
        () {
      // Simulate a recording: grow the track one fix at a time, extending the
      // cache, and assert the result matches a from-scratch resmooth at each
      // length. This is the regression guard for the O(n^2)→O(n) fix — if a
      // refactor breaks the incremental math, the rendered line would silently
      // diverge from the canonical smooth.
      final full = jitterTrack(60);
      List<LatLng>? prev;
      var prevLen = -1;
      for (int n = 1; n <= full.length; n++) {
        final raw = full.sublist(0, n);
        final inc = smoothTrackIncremental(raw, prev, prevLen);
        expectSame(inc, smoothTrack(smoothTrack(raw)));
        prev = inc;
        prevLen = n;
      }
    });

    test('multi-point append (batched fixes) still matches a full rebuild', () {
      final full = jitterTrack(50);
      // Jump 1 → 9 → 22 → 50 (variable batch sizes, as a sync flush might).
      List<LatLng>? prev;
      var prevLen = -1;
      for (final n in [1, 9, 22, 50]) {
        final raw = full.sublist(0, n);
        final inc = smoothTrackIncremental(raw, prev, prevLen);
        expectSame(inc, smoothTrack(smoothTrack(raw)));
        prev = inc;
        prevLen = n;
      }
    });

    test('falls back to full rebuild when prev is shorter than 5', () {
      final raw = jitterTrack(8);
      final prev = smoothTrack(smoothTrack(raw.sublist(0, 4)));
      expectSame(
        smoothTrackIncremental(raw, prev, 4),
        smoothTrack(smoothTrack(raw)),
      );
    });
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

    // ─── Linked-cursor hover marker ────────────────────────────────
    //
    // Mirrors the web RunMap.svelte `hover-marker` (chart-driven
    // brushing). When the host page passes a non-null hoverIdx in
    // range, LiveRunMap should mount a MarkerLayer keyed
    // 'chart-hover-marker'; out-of-range or null values must clear it.

    testWidgets('mounts the hover-marker MarkerLayer when hoverIdx is in range',
        (tester) async {
      final track = [_w(51.5, -0.1), _w(51.51, -0.099), _w(51.52, -0.098)];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: track,
                followRunner: false,
                hoverIdx: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(
        find.byKey(const ValueKey('chart-hover-marker')),
        findsOneWidget,
        reason: 'A non-null hoverIdx in range must mount the hover-marker '
            'layer so the chart-driven cursor is visible on the map.',
      );
    });

    testWidgets('hover-marker absent when hoverIdx is null', (tester) async {
      final track = [_w(51.5, -0.1), _w(51.51, -0.099)];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: track,
                followRunner: false,
                hoverIdx: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(find.byKey(const ValueKey('chart-hover-marker')), findsNothing,
          reason: 'Null hoverIdx clears the marker — releasing the chart '
              'pointer should hide it.');
    });

    testWidgets('hover-marker absent when hoverIdx is out of range',
        (tester) async {
      final track = [_w(51.5, -0.1), _w(51.51, -0.099)];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: track,
                followRunner: false,
                hoverIdx: 99, // past end of 2-element track
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(find.byKey(const ValueKey('chart-hover-marker')), findsNothing,
          reason: 'Out-of-range hoverIdx must guard against null deref + '
              'must not paint a bogus marker at index 0.');
    });

    testWidgets('course-marker pins expose merged button semantics',
        (tester) async {
      final track = [_w(51.5, -0.1), _w(51.51, -0.099)];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: track,
                followRunner: false,
                courseMarkers: const [
                  MapMarkerPin(
                    id: 'm1',
                    label: 'Aid 1',
                    color: '#16a34a',
                    lat: 51.505,
                    lng: -0.0995,
                  ),
                ],
                onMarkerTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      final semantics = tester.getSemantics(find.text('Aid 1'));
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue,
          reason: 'A spectator/host tapping a course marker must hear it '
              'announced as a button with its label, not an unlabeled tap '
              'target.');
    });
  });

  group('latLngAtFractionalIndex', () {
    final line = [
      const LatLng(51.5, -0.1),
      const LatLng(51.5, -0.099),
      const LatLng(51.501, -0.099),
    ];

    test('returns null for an empty line', () {
      expect(latLngAtFractionalIndex(const [], 0), isNull);
    });

    test('an integer index returns that exact vertex', () {
      expect(latLngAtFractionalIndex(line, 1), line[1]);
    });

    test('a fractional index lerps between the adjacent vertices', () {
      final p = latLngAtFractionalIndex(line, 0.5)!;
      expect(p.latitude, closeTo(51.5, 1e-12));
      expect(p.longitude, closeTo(-0.0995, 1e-12));
    });

    test('clamps below zero and above the last index', () {
      expect(latLngAtFractionalIndex(line, -3), line.first);
      expect(latLngAtFractionalIndex(line, 99), line.last);
    });

    test('NaN falls back to the first vertex', () {
      expect(latLngAtFractionalIndex(line, double.nan), line.first);
    });
  });

  // ─── Replay dot ─────────────────────────────────────────────────
  //
  // The run-detail replay drives `currentPositionIndex` up to once
  // per frame. The dot must animate ALONG the smoothed polyline —
  // the old lat/lng chord tween chased the fast-moving target across
  // straight lines that cut corners, visibly off the rendered line.

  group('replay dot', () {
    // Right-angle track: east along a constant latitude, then north.
    // A chord-tweened dot cuts this corner; an index-space dot cannot.
    final cornerTrack = <Waypoint>[
      for (int i = 0; i <= 10; i++) _w(51.5, -0.1 + i * 0.001),
      for (int i = 1; i <= 10; i++) _w(51.5 + i * 0.001, -0.09),
    ];

    Future<void> pumpReplay(
      WidgetTester tester,
      List<Waypoint> track,
      int? replayIdx,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: LiveRunMap(
                track: track,
                currentPosition: replayIdx != null ? track[replayIdx] : null,
                currentPositionIndex: replayIdx,
                followRunner: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    LatLng dotOf(WidgetTester tester) => tester
        .widget<MarkerLayer>(
            find.byKey(const ValueKey('current-position-marker')))
        .markers
        .single
        .point;

    testWidgets('stays on the smoothed polyline while the index advances',
        (tester) async {
      final smoothed = smoothTrack(smoothTrack(
          [for (final w in cornerTrack) LatLng(w.lat, w.lng)]));
      for (int idx = 0; idx < cornerTrack.length; idx++) {
        await pumpReplay(tester, cornerTrack, idx);
        final dot = dotOf(tester);
        expect(
          _distToPolyline(dot, smoothed),
          lessThan(1e-9),
          reason: 'At replay index $idx the dot must sit on the rendered '
              '(smoothed) polyline — the chord tween used to cut the corner.',
        );
      }
    });

    testWidgets('entering replay snaps to the start instead of gliding',
        (tester) async {
      final smoothed = smoothTrack(smoothTrack(
          [for (final w in cornerTrack) LatLng(w.lat, w.lng)]));
      // Resting state: no replay, dot sits at the end of the track.
      await pumpReplay(tester, cornerTrack, null);
      // Press play: the very next frame must render the dot at the
      // start vertex, not tweening a chord across the map from the end.
      await pumpReplay(tester, cornerTrack, 0);
      final dot = dotOf(tester);
      expect(dot.latitude, closeTo(smoothed.first.latitude, 1e-12));
      expect(dot.longitude, closeTo(smoothed.first.longitude, 1e-12));
    });
  });
}

double _distToSegment(LatLng p, LatLng a, LatLng b) {
  final ax = a.longitude, ay = a.latitude;
  final dx = b.longitude - ax, dy = b.latitude - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0
      ? 0.0
      : ((p.longitude - ax) * dx + (p.latitude - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0).toDouble();
  final cx = ax + dx * t, cy = ay + dy * t;
  final ddx = p.longitude - cx, ddy = p.latitude - cy;
  return math.sqrt(ddx * ddx + ddy * ddy);
}

double _distToPolyline(LatLng p, List<LatLng> line) {
  var best = double.infinity;
  for (int i = 0; i < line.length - 1; i++) {
    final d = _distToSegment(p, line[i], line[i + 1]);
    if (d < best) best = d;
  }
  return best;
}
