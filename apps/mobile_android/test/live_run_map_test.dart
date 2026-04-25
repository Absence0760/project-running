import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/widgets/live_run_map.dart';

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
  });
}
