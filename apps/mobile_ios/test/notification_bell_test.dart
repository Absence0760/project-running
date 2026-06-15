// Widget tests for NotificationBell — the unread-count badge on the
// dashboard action toolbar. The actual notification inbox lives on
// the ProfileScreen Notifications tab; this bell is the entry point.
//
// The full chain — fetchUnreadNotificationCount → setState → red-dot
// render — is exercised here against a fake ApiClient that lets each
// test plant a specific unread count.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/notification_bell.dart';

class _FakeApiClient extends ApiClient {
  int unread = 0;
  int fetchCalls = 0;
  Object? errorToThrow;

  @override
  String? get userId => 'test-user-id';

  @override
  Future<int> fetchUnreadNotificationCount() async {
    fetchCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return unread;
  }
}

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: AppBar(
          actions: [NotificationBell(api: api)],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('NotificationBell', () {
    testWidgets('renders the bell icon + tooltip', (tester) async {
      final api = _FakeApiClient();
      await _pump(tester, api);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byTooltip('Notifications'), findsOneWidget);
    });

    testWidgets('fetches the unread count on mount', (tester) async {
      // Headline contract — the bell must hit the API on mount, not
      // wait for a tap. A regression that lazy-loaded only on tap
      // would leave the badge dark even when there are unread items.
      final api = _FakeApiClient()..unread = 3;
      await _pump(tester, api);
      expect(api.fetchCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('fetches exactly once on mount (no render-loop refetch)',
        (tester) async {
      // A regression that called _refresh() from build() instead of
      // initState would refetch on every rebuild — pin the single mount
      // fetch so that can't slip in.
      final api = _FakeApiClient()..unread = 4;
      await _pump(tester, api);
      await tester.pump();
      await tester.pump();
      expect(api.fetchCalls, 1);
    });

    testWidgets('badge is a colour-only dot, never a numeric count',
        (tester) async {
      // The dashboard surface stays a glance — the actual number lives
      // on the Notifications tab. A regression that rendered "12" in the
      // toolbar would clutter it.
      final api = _FakeApiClient()..unread = 12;
      await _pump(tester, api);
      expect(find.text('12'), findsNothing);
    });

    testWidgets('renders the red dot when unread > 0', (tester) async {
      // The bell uses a colour-only dot (not a count text) so it
      // stays minimal in the action toolbar. The full count surfaces
      // on the Notifications tab itself.
      final api = _FakeApiClient()..unread = 5;
      await _pump(tester, api);
      // The dot is the only Container with shape: BoxShape.circle
      // mounted inside the bell.
      final dot = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final dec = w.decoration;
        return dec is BoxDecoration && dec.shape == BoxShape.circle;
      });
      expect(dot, findsOneWidget);
    });

    testWidgets('renders the dot at the boundary unread == 1', (tester) async {
      // Boundary pin — `_unread > 0` must include exactly-one, not just
      // "many". An off-by-one (`>= 1` vs a stray `> 1`) would hide the
      // dot for a single unread notification.
      final api = _FakeApiClient()..unread = 1;
      await _pump(tester, api);
      final dot = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final dec = w.decoration;
        return dec is BoxDecoration && dec.shape == BoxShape.circle;
      });
      expect(dot, findsOneWidget);
    });

    testWidgets('does NOT render the dot when unread == 0', (tester) async {
      // Negative-shape pin — a regression that always rendered the
      // dot would mislead users into thinking they have unread
      // notifications.
      final api = _FakeApiClient()..unread = 0;
      await _pump(tester, api);
      final dot = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final dec = w.decoration;
        return dec is BoxDecoration && dec.shape == BoxShape.circle;
      });
      expect(dot, findsNothing);
    });

    testWidgets('swallows fetch errors — does not crash the dashboard',
        (tester) async {
      // L4 contract from docs/architecture/conventions.md § "Layered resilience" —
      // an auxiliary effect (the unread-fetch network call) must not
      // bring down the parent screen. A regression that re-threw the
      // exception would crash the dashboard build.
      final api = _FakeApiClient()
        ..errorToThrow = Exception('Network down');
      await _pump(tester, api);
      // Bell still renders.
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      // No badge dot when fetch failed.
      final dot = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final dec = w.decoration;
        return dec is BoxDecoration && dec.shape == BoxShape.circle;
      });
      expect(dot, findsNothing);
    });

    testWidgets('signed-out user (api.userId == null) does not crash',
        (tester) async {
      // Defensive — the bell is only rendered when viewerId != null
      // on the dashboard, but the widget itself shouldn't blow up if
      // someone hands it an unauthed ApiClient.
      final api = _SignedOutFakeApiClient();
      await _pump(tester, api);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });
  });
}

class _SignedOutFakeApiClient extends ApiClient {
  @override
  String? get userId => null;

  @override
  Future<int> fetchUnreadNotificationCount() async => 0;
}
