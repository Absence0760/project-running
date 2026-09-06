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
import '../lib/widgets/undo_bar.dart';

cm.Route _route() => cm.Route(
      id: 'r1',
      userId: 'someone-else',
      name: 'River Loop',
      waypoints: const [],
      distanceMetres: 8500,
      elevationGainMetres: 45,
      isPublic: true,
    );

cm.RouteReviewRow _review({required String userId, String id = 'rev1'}) =>
    cm.RouteReviewRow(
      id: id,
      routeId: 'r1',
      userId: userId,
      rating: 4,
      comment: 'Lovely riverside path',
      createdAt: DateTime.utc(2026, 5, 1),
    );

/// Serves a fixed review list and records delete calls. `deleteThrows`
/// drives the failure path.
class _ReviewsApi extends ApiClient {
  _ReviewsApi({required this.reviewerId, this.deleteThrows = false});

  final String reviewerId;
  final bool deleteThrows;
  int deleteCalls = 0;

  @override
  String? get userId => 'viewer';

  @override
  Future<List<cm.RouteReviewRow>> getRouteReviews(String routeId) async =>
      [_review(userId: reviewerId)];

  @override
  Future<void> deleteRouteReview(String routeId) async {
    deleteCalls++;
    if (deleteThrows) throw StateError('network down');
  }
}

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  // The reviews sit near the bottom of a lazy ListView, so on a phone-sized
  // viewport they are never built. A tall surface keeps the whole page in
  // one layout pass instead of driving scroll animations past LiveRunMap.
  tester.view.physicalSize = const Size(1200, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RouteDetailScreen(
        route: _route(),
        routeStore: LocalRouteStore(),
        preferences: prefs,
        apiClient: api,
        isOwner: false,
      ),
    ),
  );
  // pumpAndSettle would spin LiveRunMap's pulse animation forever.
  await tester.pump();
  await tester.pump(Duration.zero);
}

/// The route-level delete lives in the app bar under the same icon, so every
/// finder here is scoped by the review affordance's own tooltip.
Finder _deleteReviewButton(WidgetTester tester) => find.byTooltip(
      AppLocalizations.of(tester.element(find.byType(RouteDetailScreen)))
          .routeDetailDeleteReview,
    );

Finder _reportReviewButton(WidgetTester tester) => find.byTooltip(
      AppLocalizations.of(tester.element(find.byType(RouteDetailScreen)))
          .routeDetailReportReview,
    );

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });
  tearDown(debugResetUndo);

  group('route review delete', () {
    testWidgets('shows delete on your own review, not report', (tester) async {
      final api = _ReviewsApi(reviewerId: 'viewer');
      await _pump(tester, api);

      expect(_deleteReviewButton(tester), findsOneWidget);
      expect(_reportReviewButton(tester), findsNothing);
    });

    testWidgets('shows report on someone else\'s review, not delete',
        (tester) async {
      final api = _ReviewsApi(reviewerId: 'other-user');
      await _pump(tester, api);

      expect(_reportReviewButton(tester), findsOneWidget);
      expect(_deleteReviewButton(tester), findsNothing);
    });

    // Issue #666 U8, mobile half: the review delete dropped its confirm for a
    // deferred, undoable mutation (decisions § 514). The three tests below
    // replace the cancel / confirm / failure trio that pinned the dialog. The
    // property the cancel test really guarded — that one tap cannot lose the
    // review — is now Undo's job, and the replacement asserts the STRONGER
    // thing the confirm never offered: after Undo the server was never called
    // at all, so the row keeps its own id and created_at.
    testWidgets('the delete is deferred and Undo never calls the server',
        (tester) async {
      final api = _ReviewsApi(reviewerId: 'viewer');
      await _pump(tester, api);

      await tester.tap(_deleteReviewButton(tester));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'confirm and undo are alternatives, not partners');
      expect(find.text('Review removed'), findsOneWidget);
      expect(api.deleteCalls, 0);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(api.deleteCalls, 0);
      expect(_deleteReviewButton(tester), findsOneWidget,
          reason: 'the same review row is back, not a re-inserted copy');
    });

    testWidgets('the window closing deletes for real', (tester) async {
      final api = _ReviewsApi(reviewerId: 'viewer');
      await _pump(tester, api);

      await tester.tap(_deleteReviewButton(tester));
      await tester.pump();
      expect(api.deleteCalls, 0);

      await tester.pump(const Duration(seconds: 9));
      expect(api.deleteCalls, 1);
    });

    testWidgets('a failing commit restores the review and banners',
        (tester) async {
      final api = _ReviewsApi(reviewerId: 'viewer', deleteThrows: true);
      await _pump(tester, api);

      await tester.tap(_deleteReviewButton(tester));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();

      expect(api.deleteCalls, 1);
      expect(_deleteReviewButton(tester), findsOneWidget,
          reason: 'a list must never claim a row is gone while the server '
              'still holds it');
      expect(find.textContaining("Couldn't delete the review"), findsOneWidget);
    });
  });
}
