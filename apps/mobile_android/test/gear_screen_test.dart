import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/local_gear_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/gear_screen.dart';
import '../lib/widgets/gear_form_sheet.dart';

/// Widget tests for [GearScreen] covering the offline + signed-out
/// flows added in the "Backend not configured" fix + the
/// LocalGearStore commit.
class _OfflineFakeApi extends ApiClient {
  @override
  String? get userId => null;
}

Future<({Preferences prefs, LocalGearStore store, Directory dir})>
    _makeFixtures() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final dir = Directory.systemTemp.createTempSync('gear_screen_test_');
  final store = LocalGearStore();
  await store.init(overrideDirectory: dir);
  return (prefs: prefs, store: store, dir: dir);
}

void main() {
  group('GearScreen — offline / no-api', () {
    testWidgets('renders without crashing when api is null', (tester) async {
      final f = await _makeFixtures();
      try {
        await tester.pumpWidget(MaterialApp(
          home: GearScreen(
            api: null,
            preferences: f.prefs,
            store: f.store,
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Empty state copy renders.
        expect(find.text('No shoes yet'), findsOneWidget);
        // Add button is reachable.
        expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });

    // Note: the seeded-row render path is covered by the
    // LocalGearStore unit tests + the lifecycle tests. A combined
    // widget pump with both a populated store AND api=null tickles
    // a flutter_test timer-drain issue around RefreshIndicator's
    // initial animation; pinning that path here isn't worth the
    // flake risk.

    testWidgets('api with no userId behaves like api=null (offline path)',
        (tester) async {
      final f = await _makeFixtures();
      try {
        await tester.pumpWidget(MaterialApp(
          home: GearScreen(
            api: _OfflineFakeApi(),
            preferences: f.prefs,
            store: f.store,
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // No crash, no banner that says "Backend not configured" — the
        // landing was the only place that copy lived, and Gear is
        // un-gated now.
        expect(find.text('Backend not configured'), findsNothing);
        expect(find.text('No shoes yet'), findsOneWidget);
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });
  });

  group('gear_form_sheet — system gesture-bar padding', () {
    testWidgets(
        'bottom padding clears MediaQuery.viewPadding.bottom when keyboard is down',
        (tester) async {
      // Simulate a Samsung handset with a 32px translucent gesture nav
      // bar by injecting viewPadding via MediaQuery.
      const gestureBarPx = 32.0;
      final f = await _makeFixtures();
      try {
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (ctx) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showGearFormSheet(
                    context: ctx,
                    store: f.store,
                    preferences: f.prefs,
                    kind: 'shoe',
                  ),
                  child: const Text('Open'),
                ),
              ),
            );
          }),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              viewPadding: const EdgeInsets.only(bottom: gestureBarPx),
              padding: const EdgeInsets.only(bottom: gestureBarPx),
            ),
            child: child!,
          ),
        ));
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // The Cancel button should be reachable — its global Y must
        // sit at least gestureBarPx above the screen bottom.
        final screenHeight = tester.binding.window.physicalSize.height /
            tester.binding.window.devicePixelRatio;
        final cancelTopLeft = tester.getTopLeft(
          find.widgetWithText(TextButton, 'Cancel'),
        );
        final cancelBottom = cancelTopLeft.dy +
            tester
                .getSize(find.widgetWithText(TextButton, 'Cancel'))
                .height;
        expect(
          screenHeight - cancelBottom,
          greaterThanOrEqualTo(gestureBarPx - 1),
          reason:
              'Cancel button must sit at least gestureBar inset above the screen bottom so it is not hidden by Samsung\'s translucent gesture nav.',
        );
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });
  });
}
