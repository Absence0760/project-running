import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/pro_sellable.dart';
import '../lib/screens/settings_pro_screen.dart';

/// Pins two things about the mobile Pro storefront:
///
/// 1. The hollow-subscription gate (decisions §466) — the purchase CTA
///    renders only when the deploy has a live Pro perk, mirroring web's
///    `proSellable` branch. Unknown (the manifest didn't answer) counts as
///    not sellable, so the failure direction is "don't take the money".
/// 2. The payment double-submit guard: tapping Subscribe puts the IAP tiles
///    into a busy state, so a second tap can't open a second checkout.
///    RevenueCat is unconfigured in the test env, so checkout falls through
///    to the external-upgrade URL — we gate that launch to hold the busy
///    window open and assert the tile is disabled while in flight.
void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:54321', anonKey: 'eyJ.local.test');
  });

  Future<void> pumpPro(WidgetTester tester, ProPerks perks) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsProScreen(loadPerks: () async => perks),
      ),
    );
    await tester.pump();
  }

  final subscribeTile =
      find.widgetWithIcon(ListTile, Icons.workspace_premium_outlined);

  testWidgets('no purchase CTA when the deploy has no live Pro perk',
      (tester) async {
    await pumpPro(tester, ProPerks.none);

    expect(find.text('Pro — coming soon'), findsOneWidget);
    expect(find.textContaining('Subscribe to Pro'), findsNothing);
    // The teaser tile is inert — no onTap, so no path to checkout at all.
    expect(tester.widget<ListTile>(subscribeTile).onTap, isNull);
    // The USD/regional disclosure belongs to a price we are not quoting.
    expect(find.textContaining('Billed in US dollars'), findsNothing);
    // Restore + manage stay reachable: an existing subscriber must still be
    // able to re-link or cancel on a deploy that has stopped selling.
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
  });

  testWidgets('purchase CTA returns when a single perk goes live',
      (tester) async {
    await pumpPro(tester, const ProPerks(coach: false, routeGen: true));

    expect(find.textContaining('Subscribe to Pro'), findsOneWidget);
    expect(find.text('Pro — coming soon'), findsNothing);
    expect(tester.widget<ListTile>(subscribeTile).onTap, isNotNull);
  });

  testWidgets('storefront stays a teaser while the perk lookup is unresolved',
      (tester) async {
    final pending = Completer<ProPerks>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsProScreen(loadPerks: () => pending.future),
      ),
    );
    await tester.pump();

    expect(find.text('Pro — coming soon'), findsOneWidget);
    expect(find.textContaining('Subscribe to Pro'), findsNothing);

    pending.complete(const ProPerks(coach: true, routeGen: false));
    // One pump to let the await continuation run, one to rebuild.
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Subscribe to Pro'), findsOneWidget);
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

    await pumpPro(tester, const ProPerks(coach: true, routeGen: false));

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
