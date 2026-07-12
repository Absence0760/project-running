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

/// ApiClient stub: a settable [userId] (the viewer) + one seeded review
/// authored by [reviewAuthorId]. Drives the report-flag gating on
/// `route_detail_screen`'s review cards.
class _ReviewsApi extends ApiClient {
  _ReviewsApi({this.viewerId, required this.reviewAuthorId});

  final String? viewerId;
  final String reviewAuthorId;

  @override
  String? get userId => viewerId;

  @override
  Future<List<cm.RouteReviewRow>> getRouteReviews(String routeId) async => [
        cm.RouteReviewRow(
          id: 'review-1',
          routeId: routeId,
          userId: reviewAuthorId,
          rating: 3,
          comment: 'e2e report-target review',
        ),
      ];
}

cm.Route _route() => cm.Route(
      id: 'r1',
      userId: 'route-owner',
      name: 'River Loop',
      waypoints: const [],
      distanceMetres: 8500,
      elevationGainMetres: 45,
      isPublic: true,
    );

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RouteDetailScreen(
          route: _route(),
          routeStore: LocalRouteStore(),
          preferences: prefs,
          isOwner: false,
          apiClient: api,
        ),
      ),
    );
    // Let _fetchReviews resolve.
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await tester.pump();
  await tester.pump(Duration.zero);
  // The reviews section sits below the map + stats; scroll it up.
  await tester.drag(find.byType(ListView), const Offset(0, -600));
  await tester.pump();
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RouteDetailScreen — review report affordance', () {
    testWidgets('a non-author signed-in viewer sees the report flag', (tester) async {
      await _pump(
        tester,
        _ReviewsApi(viewerId: 'viewer', reviewAuthorId: 'author'),
      );
      expect(find.text('e2e report-target review'), findsOneWidget);
      expect(find.byTooltip('Report review'), findsOneWidget);
    });

    testWidgets('the review author sees no flag on their own review', (tester) async {
      await _pump(
        tester,
        _ReviewsApi(viewerId: 'author', reviewAuthorId: 'author'),
      );
      expect(find.text('e2e report-target review'), findsOneWidget);
      expect(find.byTooltip('Report review'), findsNothing);
    });

    testWidgets('a signed-out viewer sees no flag', (tester) async {
      await _pump(
        tester,
        _ReviewsApi(viewerId: null, reviewAuthorId: 'author'),
      );
      expect(find.text('e2e report-target review'), findsOneWidget);
      expect(find.byTooltip('Report review'), findsNothing);
    });
  });
}
