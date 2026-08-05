import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/route_detail_screen.dart';
import '../lib/widgets/app_bar_actions.dart';

class _OwnerApi extends ApiClient {
  @override
  String? get userId => 'test-user';
}

cm.Route _route() => cm.Route(
      id: 'r1',
      userId: 'test-user',
      name: 'Bealach na Ba out and back with the long descent',
      waypoints: const [],
      distanceMetres: 8500,
      elevationGainMetres: 45,
      isPublic: false,
    );

Future<void> _pumpRouteDetail(WidgetTester tester, {required bool owner}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RouteDetailScreen(
      route: _route(),
      routeStore: LocalRouteStore(),
      preferences: prefs,
      apiClient: _OwnerApi(),
      isOwner: owner,
    ),
  ));
  // Timed pumps — pumpAndSettle spins LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

Future<void> _openOverflow(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpBare(WidgetTester tester, AppBarActions actions) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(appBar: AppBar(title: const Text('T'), actions: [actions])),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  group('AppBarActions (issue #666 C4)', () {
    testWidgets('a destructive action is never promoted to a visible slot',
        (tester) async {
      var deleted = false;
      await _pumpBare(
        tester,
        AppBarActions(actions: [
          AppBarAction(
            icon: const Icon(Icons.delete_outline),
            label: 'Delete',
            destructive: true,
            onPressed: () => deleted = true,
          ),
          AppBarAction(
            icon: const Icon(Icons.star_border),
            label: 'Star',
            onPressed: () {},
          ),
        ]),
      );

      // A PopupMenuButton renders its own IconButton, so the toolbar's slot
      // count is exactly its IconButton count: Star plus the overflow.
      expect(find.byType(IconButton), findsNWidgets(2));
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('no overflow button when everything fits', (tester) async {
      await _pumpBare(
        tester,
        AppBarActions(actions: [
          AppBarAction(
              icon: const Icon(Icons.star_border), label: 'A', onPressed: () {}),
          AppBarAction(
              icon: const Icon(Icons.public), label: 'B', onPressed: () {}),
          AppBarAction(
              icon: const Icon(Icons.sync), label: 'C', onPressed: () {}),
        ]),
      );

      expect(find.byType(IconButton), findsNWidgets(3));
      expect(find.byTooltip('More'), findsNothing);
    });
  });

  group('route detail toolbar (issue #666 C4)', () {
    // 56dp leading + 48 per action on a 360dp phone: six owner actions left
    // 16dp for the title, before the toolbar's own 16dp title gap.
    const narrow = Size(360, 900);

    testWidgets('an owner sees three toolbar slots, not six', (tester) async {
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpRouteDetail(tester, owner: true);

      // Share, one promoted action, and the overflow — three IconButtons,
      // counting each PopupMenuButton once through the one it renders.
      final toolbarButtons = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      );
      expect(tester.widgetList(toolbarButtons), hasLength(3));
    });

    testWidgets('the title keeps room for a route name', (tester) async {
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpRouteDetail(tester, owner: true);

      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Bealach na Ba out and back with the long descent'),
      );
      expect(tester.getSize(title).width, greaterThan(120));
    });

    testWidgets('star, visibility, club transfer and delete are in the '
        'overflow, delete last and marked', (tester) async {
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpRouteDetail(tester, owner: true);
      await _openOverflow(tester);

      final rows = find.byType(PopupMenuItem<int>);
      expect(tester.widgetList(rows), hasLength(4));
      for (final label in [
        'Star to show on watch',
        'Make public',
        'Transfer to club',
        'Delete route',
      ]) {
        expect(find.widgetWithText(PopupMenuItem<int>, label), findsOneWidget);
      }
      expect(
        tester.getTopLeft(find.text('Delete route')).dy,
        greaterThan(tester.getTopLeft(find.text('Transfer to club')).dy),
      );
      // Colour is a second signal a colour-blind reader may not get, so the
      // divider above it carries the same separation (§ 498).
      expect(find.byType(PopupMenuDivider), findsOneWidget);
    });

    testWidgets('a non-owner leads with the bookmark, not the offline pin',
        (tester) async {
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpRouteDetail(tester, owner: false);

      expect(
          find.descendant(
              of: find.byType(AppBar),
              matching: find.byIcon(Icons.bookmark_border)),
          findsOneWidget);
      // The body's inline offline-save tile carries the same icon, so scope
      // the absence check to the toolbar.
      expect(
          find.descendant(
              of: find.byType(AppBar),
              matching: find.byIcon(Icons.download_outlined)),
          findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await _openOverflow(tester);
      expect(find.widgetWithText(PopupMenuItem<int>, 'Save for offline use'),
          findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<int>, 'Report route'),
          findsOneWidget);
    });
  });
}
