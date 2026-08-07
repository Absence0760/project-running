// Issue #666 I8 / I15 / I16: a family of destinations whose ONLY entry point
// was an unlabelled AppBar glyph — a name that exists only in a tooltip is
// not a name on a touch device, and each of these is the sole route to its
// screen. Web renders every one of them as an icon-AND-text link; the mobile
// shape is the shared `SurfacePeerStrip` (decisions § 488).
//
// Also pinned here: the Settings gear tile used to `return` on a null store,
// producing a tap that did nothing at all with no disabled state (I16).
//
// Recap's fix is a labelled link rather than a peer — the recap is not a
// sibling surface of the dashboard — and is pinned by source grep rather than
// by a pump: the link only renders once the dashboard has runs AND a signed-in
// client, so a widget test would have to seed the store from disk to reach it.
// The grep proves the glyph is gone and the label is present; it does not
// prove layout.

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/preferences.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/screens/gear_screen.dart';
import '../lib/screens/plans_screen.dart';
import '../lib/screens/routine_library_screen.dart';
import '../lib/screens/settings_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/surface_peer_strip.dart';

class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';
  @override
  Future<List<Map<String, dynamic>>> fetchMyGearWithDistance() async => const [];
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ));
  await tester.pump();
}

List<String> _peerLabels(WidgetTester tester) {
  final strip = find.byType(SurfacePeerStrip);
  expect(strip, findsOneWidget, reason: 'the surface must carry a peer strip');
  return tester
      .widget<SurfacePeerStrip>(strip)
      .peers
      .map((p) => p.label)
      .toList();
}

void main() {
  testWidgets('gear names Rotations instead of an Icons.sync_alt glyph',
      (tester) async {
    final prefs = await _prefs();
    final store = LocalGearStore();
    await _pump(
      tester,
      GearScreen(api: _SignedInApi(), preferences: prefs, store: store),
    );

    expect(_peerLabels(tester), ['Gear', 'Rotations']);
    // `sync_alt` read as "sync", not as a shoe rotation (I15). It is gone
    // from the screen entirely, not merely joined by a label.
    expect(find.byIcon(Icons.sync_alt), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('plans names the library instead of an Icons.public glyph',
      (tester) async {
    await _pump(
      tester,
      PlansScreen(training: TrainingService(), apiClient: _SignedInApi()),
    );
    expect(_peerLabels(tester), ['Training plans', 'Browse library']);
    expect(find.byIcon(Icons.public), findsNothing);
  });

  testWidgets('the routine library names the public library',
      (tester) async {
    await _pump(
      tester,
      RoutineLibraryScreen(
        api: _SignedInApi(),
        store: LocalRoutineStore(),
        gymStore: LocalGymStore(),
      ),
    );
    expect(_peerLabels(tester), ['Routines', 'Library']);
    expect(find.byIcon(Icons.public), findsNothing);
    // The create action stays an icon: `+` is a conventional glyph for a
    // create affordance, not the sole name of a destination.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  group('settings gear tile (#666 I16)', () {
    testWidgets('is disabled with a stated reason when no store is wired',
        (tester) async {
      final prefs = await _prefs();
      await _pump(
        tester,
        SettingsScreen(
          preferences: prefs,
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
        ),
      );
      await tester.scrollUntilVisible(find.text('Gear'), 200,
          scrollable: find.byType(Scrollable).first);
      final tile = tester.widget<ListTile>(find.ancestor(
        of: find.text('Gear'),
        matching: find.byType(ListTile),
      ));
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      expect(find.text("Gear isn't available on this build"), findsOneWidget);
    });

    testWidgets('is enabled with its normal subtitle when a store is wired',
        (tester) async {
      final prefs = await _prefs();
      await _pump(
        tester,
        SettingsScreen(
          preferences: prefs,
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
          gearStore: LocalGearStore(),
        ),
      );
      await tester.scrollUntilVisible(find.text('Gear'), 200,
          scrollable: find.byType(Scrollable).first);
      final tile = tester.widget<ListTile>(find.ancestor(
        of: find.text('Gear'),
        matching: find.byType(ListTile),
      ));
      expect(tile.enabled, isTrue);
      expect(tile.onTap, isNotNull);
      expect(find.text('Track shoes + bikes and per-item mileage'),
          findsOneWidget);
    });
  });

  group('dashboard recap entry (#666 I8)', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/dashboard_screen.dart').readAsStringSync();
    });

    test('the recap is no longer a bare calendar glyph', () {
      // `calendar_today_outlined` beside four other unlabelled glyphs read as
      // a date picker, and it was the recap's ONLY entry point in the app.
      expect(
        src.contains('Icons.calendar_today'),
        isFalse,
        reason: 'the dashboard toolbar must not name the recap with a '
            'date-picker glyph',
      );
    });

    test('the recap link carries its name, not only a tooltip', () {
      final at = src.indexOf('RecapScreen(');
      expect(at, greaterThan(0), reason: 'the dashboard must reach RecapScreen');
      // The whole affordance is built in the ~24 lines around the push.
      final block = src.substring(at - 900 < 0 ? 0 : at - 900, at);
      expect(block.contains('TextButton.icon('), isTrue,
          reason: 'a labelled button, not an IconButton');
      final after = src.substring(at, at + 600);
      expect(after.contains('label: Text(l10n.dashboardRecapTooltip)'), isTrue,
          reason: 'the name must render as text');
      expect(after.contains('Icons.auto_awesome'), isTrue,
          reason: 'mirrors the auto_awesome glyph web pairs with the label');
    });

    test('the toolbar is down to four glyphs', () {
      // Five unlabelled glyphs crowded the toolbar; removing the recap leaves
      // coach / feed / notification bell / profile.
      final start = src.indexOf('final actions = <Widget>[');
      final end = src.indexOf('final actionToolbar', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final block = src.substring(start, end);
      expect('IconButton('.allMatches(block).length, 3,
          reason: 'coach + feed + profile are IconButtons; the bell is its '
              'own widget, so four glyphs in total');
      expect(block.contains('NotificationBell('), isTrue);
    });
  });
}
