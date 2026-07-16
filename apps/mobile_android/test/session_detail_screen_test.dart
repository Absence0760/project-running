import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/session_detail_screen.dart';

class _ThrowingFakeApi extends ApiClient {
  int calls = 0;

  @override
  String? get userId => 'me';

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
  })?> fetchSessionPlan(String id) async {
    calls++;
    throw Exception('network blip');
  }
}

class _NotFoundFakeApi extends ApiClient {
  @override
  String? get userId => 'me';

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
  })?> fetchSessionPlan(String id) async => null;
}

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<LocalGymStore> _gymStore(Directory dir) async {
  final store = LocalGymStore();
  await store.init(overrideDirectory: dir);
  return store;
}

void main() {
  testWidgets(
      'a fetch failure shows the error state with retry instead of a stuck spinner',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('session_detail_error');
    try {
      final api = _ThrowingFakeApi();
      final gym = await _gymStore(dir);
      await tester.pumpWidget(_wrap(SessionDetailScreen(
          api: api, gymStore: gym, planId: 'p1', titleHint: 'Morning Flow')));

      // The fake rejects on its first microtask, so the error frame is
      // already up by the first pump — there is no observable mid-fetch
      // spinner to assert on here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("Couldn't load this session plan."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Session plan not found.'), findsNothing);

      // Retry must re-invoke the fetch; the fake keeps throwing, so prove
      // the refetch by call count rather than a transient spinner frame.
      expect(api.calls, 1);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.calls, 2);
      expect(find.text("Couldn't load this session plan."), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a null (not-found) result stays distinct from the error state',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('session_detail_notfound');
    try {
      final api = _NotFoundFakeApi();
      final gym = await _gymStore(dir);
      await tester.pumpWidget(_wrap(SessionDetailScreen(
          api: api, gymStore: gym, planId: 'p1', titleHint: 'Morning Flow')));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Session plan not found.'), findsOneWidget);
      expect(find.text("Couldn't load this session plan."), findsNothing);
      expect(find.text('Retry'), findsNothing);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
