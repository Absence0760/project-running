import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/session_detail_screen.dart';
import '../lib/screens/sessions_screen.dart';

SessionPlanRow _plan(String id, String title,
        {String? discipline, int? estMin}) =>
    SessionPlanRow(
      id: id,
      authorId: 'u1',
      title: title,
      discipline: discipline,
      estDurationMin: estMin,
      isPublic: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

SessionPlanItemRow _item(
  String id, {
  required int position,
  required String name,
  String kind = 'hold',
  int? durationS,
  int? reps,
  bool perSide = false,
  String? cue,
}) =>
    SessionPlanItemRow(
      id: id,
      planId: 'p1',
      position: position,
      movementName: name,
      kind: kind,
      durationS: durationS,
      reps: reps,
      perSide: perSide,
      cue: cue,
    );

class _FakeApi extends ApiClient {
  _FakeApi({this.plans = const [], this.items = const []});

  final List<SessionPlanRow> plans;
  final List<SessionPlanItemRow> items;

  @override
  Future<List<SessionPlanRow>> fetchSessionPlans() async => plans;

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
  })?> fetchSessionPlan(String id) async {
    final p = plans.where((e) => e.id == id).firstOrNull;
    if (p == null) return null;
    return (plan: p, blocks: const <SessionPlanBlockRow>[], items: items);
  }
}

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  testWidgets('empty list renders the self-hiding empty state', (tester) async {
    await tester.pumpWidget(_wrap(SessionsScreen(api: _FakeApi())));
    await tester.pumpAndSettle();
    expect(find.text('No session plans yet.'), findsOneWidget);
  });

  testWidgets('populated list shows a row with discipline + est duration',
      (tester) async {
    final api = _FakeApi(plans: [
      _plan('p1', 'Morning Flow', discipline: 'Vinyasa', estMin: 30),
    ]);
    await tester.pumpWidget(_wrap(SessionsScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Morning Flow'), findsOneWidget);
    expect(find.textContaining('Vinyasa'), findsOneWidget);
  });

  testWidgets('detail expands a per-side hold into Left/Right steps',
      (tester) async {
    final api = _FakeApi(
      plans: [_plan('p1', 'Morning Flow')],
      items: [
        _item('i0', position: 0, name: 'Downward Dog', durationS: 30),
        _item('i1',
            position: 1, name: 'Low Lunge', durationS: 45, perSide: true),
        _item('i2',
            position: 2, name: 'The Hundred', kind: 'reps', reps: 100),
      ],
    );
    await tester.pumpWidget(
      _wrap(SessionDetailScreen(api: api, planId: 'p1', titleHint: 'Morning Flow')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Low Lunge (Left)'), findsOneWidget);
    expect(find.textContaining('Low Lunge (Right)'), findsOneWidget);
    expect(find.textContaining('100 reps'), findsOneWidget);
  });
}
