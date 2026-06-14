import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/route_describe_client.dart';
import '../lib/route_description.dart';
import '../lib/screens/route_detail_screen.dart';

cm.Route _route() => cm.Route(
      id: 'r1',
      userId: 'test-user',
      name: 'River Loop',
      waypoints: const [],
      distanceMetres: 5000,
      elevationGainMetres: 90,
      surface: 'trail',
    );

Future<void> _pump(
  WidgetTester tester, {
  Future<bool> Function()? checkPro,
  Future<AiDescriptionResult> Function(RouteDescriptionInput)? describeAi,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await tester.runAsync(() => prefs.init());

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RouteDetailScreen(
        route: _route(),
        routeStore: LocalRouteStore(),
        preferences: prefs,
        checkPro: checkPro,
        describeAi: describeAi,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
}

Future<void> _tapDescribe(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -600));
  await tester.pump();
  await tester.tap(find.text('Describe this route'));
  // One frame to flush the templated baseline + the async Pro/AI work.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RouteDetailScreen describe affordance', () {
    testWidgets('shows the describe button for a route with no description',
        (tester) async {
      await _pump(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('Describe this route'), findsOneWidget);
    });

    testWidgets('non-Pro renders the templated baseline + upgrade hint, no AI',
        (tester) async {
      var aiCalled = false;
      await _pump(
        tester,
        checkPro: () async => false,
        describeAi: (_) async {
          aiCalled = true;
          return const AiDescriptionResult(
              description: 'AI', source: 'ai', upgrade: false);
        },
      );
      await _tapDescribe(tester);

      // Templated baseline: surface + shape + climb clause from the parts.
      expect(find.textContaining('River Loop is a'), findsOneWidget);
      expect(find.textContaining('trail'), findsOneWidget);
      // 90 m over 5 km = 18 m/km → "gently rolling".
      expect(find.textContaining('gently rolling'), findsOneWidget);
      // Free user sees the upsell, never the AI attribution.
      expect(find.text('AI descriptions are a Pro feature. Upgrade to enhance.'),
          findsOneWidget);
      expect(find.text("Written by AI from this route's stats"), findsNothing);
      expect(aiCalled, isFalse);
    });

    testWidgets('Pro replaces the baseline with the AI text + attribution',
        (tester) async {
      await _pump(
        tester,
        checkPro: () async => true,
        describeAi: (_) async => const AiDescriptionResult(
          description: 'A gorgeous riverside trail loop with a steady climb.',
          source: 'ai',
          upgrade: false,
        ),
      );
      await _tapDescribe(tester);

      expect(
        find.text('A gorgeous riverside trail loop with a steady climb.'),
        findsOneWidget,
      );
      expect(find.text("Written by AI from this route's stats"), findsOneWidget);
      // The upgrade hint is gone for a Pro user whose call returned upgrade:false.
      expect(find.text('AI descriptions are a Pro feature. Upgrade to enhance.'),
          findsNothing);
    });

    testWidgets('AI failure keeps the templated baseline + shows the error',
        (tester) async {
      await _pump(
        tester,
        checkPro: () async => true,
        describeAi: (_) async => throw StateError('boom'),
      );
      await _tapDescribe(tester);

      // Baseline survives the failure.
      expect(find.textContaining('River Loop is a'), findsOneWidget);
      expect(find.text('Couldn\'t generate a description. Please try again.'),
          findsOneWidget);
      // No AI attribution since the model call failed.
      expect(find.text("Written by AI from this route's stats"), findsNothing);
    });
  });
}
