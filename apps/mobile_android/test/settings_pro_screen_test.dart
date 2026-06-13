import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_pro_screen.dart';

/// Pins the payment double-submit guard: tapping Subscribe puts the IAP
/// tiles into a busy state, so a second tap can't open a second checkout.
/// RevenueCat is unconfigured in the test env, so checkout falls through to
/// the external-upgrade URL — we gate that launch to hold the busy window
/// open and assert the tile is disabled while in flight.
void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:54321', anonKey: 'eyJ.local.test');
  });

  testWidgets('Subscribe tile disables while a checkout is in flight (no double-submit)',
      (tester) async {
    final gate = Completer<void>();
    var launchCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
        (call) async {
      // url_launcher probes (canLaunch/supportsMode) pass through; only the
      // actual launch holds the gate so the busy window stays open.
      if (call.method == 'launch' || call.method == 'launchUrl') {
        launchCalls++;
        await gate.future;
        return true;
      }
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsProScreen(),
      ),
    );
    await tester.pump();

    final subscribeTile = find.widgetWithIcon(ListTile, Icons.workspace_premium_outlined);
    expect(subscribeTile, findsOneWidget);
    expect(tester.widget<ListTile>(subscribeTile).enabled, isTrue);

    await tester.tap(subscribeTile);
    await tester.pump();

    // Busy: the tile is now disabled, so a second tap can't fire a second
    // checkout.
    expect(tester.widget<ListTile>(subscribeTile).enabled, isFalse);

    // Release the gate; the checkout completes and the tile re-enables.
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(launchCalls, 1);
  });
}
