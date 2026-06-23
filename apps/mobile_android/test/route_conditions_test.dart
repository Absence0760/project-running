import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/route_conditions.dart';

RouteConditionRow _row({
  String id = 'c1',
  String userId = 'viewer-1',
  String condition = 'muddy',
  String severity = 'caution',
  String? note,
  double? positionM,
}) =>
    RouteConditionRow(
      id: id,
      routeId: 'route-1',
      userId: userId,
      condition: condition,
      severity: severity,
      note: note,
      positionM: positionM,
      createdAt: DateTime.now(),
    );

class _ConditionsApi extends ApiClient {
  _ConditionsApi({
    this.viewer = 'viewer-1',
    List<RouteConditionRow>? seed,
    this.throwOnAdd = false,
  }) : _rows = List.of(seed ?? const []);

  final String? viewer;
  final bool throwOnAdd;
  final List<RouteConditionRow> _rows;
  int addCalls = 0;
  int deleteCalls = 0;

  @override
  String? get userId => viewer;

  @override
  Future<List<RouteConditionRow>> fetchRouteConditions(String routeId) async =>
      List.of(_rows);

  @override
  Future<RouteConditionRow> addRouteCondition({
    required String routeId,
    required String condition,
    required String severity,
    String? note,
    double? lat,
    double? lng,
  }) async {
    addCalls++;
    if (throwOnAdd) throw Exception('insert failed');
    return _row(id: 'new', condition: condition, severity: severity, note: note);
  }

  @override
  Future<void> deleteRouteCondition(String id) async {
    deleteCalls++;
  }
}

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('empty state renders with a Report affordance for a signed-in viewer',
      (tester) async {
    final api = _ConditionsApi();
    await tester.pumpWidget(_host(RouteConditions(
      api: api,
      routeId: 'route-1',
      routeOwnerId: 'owner-9',
    )));
    await tester.pumpAndSettle();

    expect(find.text('Conditions'), findsOneWidget);
    expect(find.text('No condition reports yet.'), findsOneWidget);
    expect(find.text('Report condition'), findsOneWidget);
  });

  testWidgets('a seeded condition renders chip + severity + note', (tester) async {
    final api = _ConditionsApi(seed: [
      _row(note: 'Creek crossing is high', positionM: 4200),
    ]);
    await tester.pumpWidget(_host(RouteConditions(
      api: api,
      routeId: 'route-1',
      routeOwnerId: 'owner-9',
    )));
    await tester.pumpAndSettle();

    expect(find.text('Muddy'), findsOneWidget);
    expect(find.text('CAUTION'), findsOneWidget);
    expect(find.text('Creek crossing is high'), findsOneWidget);
  });

  testWidgets('the composer writes via the api', (tester) async {
    final api = _ConditionsApi();
    await tester.pumpWidget(_host(RouteConditions(
      api: api,
      routeId: 'route-1',
      routeOwnerId: 'owner-9',
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report condition'));
    await tester.pumpAndSettle();
    // Submit (the composer's primary button shares the label).
    await tester.tap(find.widgetWithText(FilledButton, 'Report condition'));
    await tester.pump();

    expect(api.addCalls, 1);
    // showTopBanner leaves a pending auto-dismiss timer — drain it so the
    // test tears down cleanly (known mobile-test gotcha).
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a failed report surfaces a banner and keeps the composer open',
      (tester) async {
    final api = _ConditionsApi(throwOnAdd: true);
    await tester.pumpWidget(_host(RouteConditions(
      api: api,
      routeId: 'route-1',
      routeOwnerId: 'owner-9',
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report condition'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Report condition'));
    await tester.pumpAndSettle();

    expect(api.addCalls, 1);
    expect(find.text('Could not report condition'), findsOneWidget);
    // The composer stays open for a retry — its Submit button is still mounted.
    expect(find.widgetWithText(FilledButton, 'Report condition'), findsOneWidget);
    // Drain showTopBanner's auto-dismiss timer before teardown.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('read-only view (canReport false) hides the composer affordance',
      (tester) async {
    final api = _ConditionsApi();
    await tester.pumpWidget(_host(RouteConditions(
      api: api,
      routeId: 'route-1',
      routeOwnerId: 'owner-9',
      canReport: false,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Report condition'), findsNothing);
  });

  testWidgets('a signed-out viewer sees no composer', (tester) async {
    final api = _ConditionsApi(viewer: null);
    await tester.pumpWidget(_host(RouteConditions(
      api: api,
      routeId: 'route-1',
      routeOwnerId: 'owner-9',
    )));
    await tester.pumpAndSettle();

    expect(find.text('Report condition'), findsNothing);
  });
}
