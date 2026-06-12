import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/session_detail_screen.dart';

SessionPlanRow _plan(String id, {required String authorId, bool isPublic = false}) =>
    SessionPlanRow(
      id: id,
      authorId: authorId,
      title: 'Morning Flow',
      isPublic: isPublic,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

SessionPlanItemRow _item() => SessionPlanItemRow(
      id: 'i0',
      planId: 'p1',
      position: 0,
      movementName: 'Downward Dog',
      kind: 'hold',
      durationS: 30,
      perSide: false,
    );

class _FakeApi extends ApiClient {
  _FakeApi({required this.plan, required this.viewerId});

  final SessionPlanRow plan;
  final String? viewerId;
  final List<({String id, bool isPublic})> publicCalls = [];

  @override
  String? get userId => viewerId;

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
  })?> fetchSessionPlan(String id) async =>
      (plan: plan, blocks: const <SessionPlanBlockRow>[], items: [_item()]);

  @override
  Future<void> setSessionPlanPublic(String id, bool isPublic) async {
    publicCalls.add((id: id, isPublic: isPublic));
  }
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
  testWidgets('owner sees the make-public toggle; tapping it flips visibility',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('session_detail_vis');
    try {
      final api = _FakeApi(
        plan: _plan('p1', authorId: 'me'),
        viewerId: 'me',
      );
      final gym = await _gymStore(dir);
      await tester.pumpWidget(_wrap(SessionDetailScreen(
          api: api, gymStore: gym, planId: 'p1', titleHint: 'Morning Flow')));
      await tester.pumpAndSettle();

      // Private by default → the make-public action is shown.
      expect(find.byTooltip('Make public'), findsOneWidget);

      await tester.tap(find.byTooltip('Make public'));
      await tester.pumpAndSettle();

      expect(api.publicCalls, [(id: 'p1', isPublic: true)]);
      // Tooltip now reflects the public state.
      expect(find.byTooltip('Make private'), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a non-owner viewer sees no visibility toggle', (tester) async {
    final dir = Directory.systemTemp.createTempSync('session_detail_vis_nonowner');
    try {
      final api = _FakeApi(
        plan: _plan('p1', authorId: 'someone-else', isPublic: true),
        viewerId: 'me',
      );
      final gym = await _gymStore(dir);
      await tester.pumpWidget(_wrap(SessionDetailScreen(
          api: api, gymStore: gym, planId: 'p1', titleHint: 'Morning Flow')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Make public'), findsNothing);
      expect(find.byTooltip('Make private'), findsNothing);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
