import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_gear_chips.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.viewerId, this.gear = const []});

  final String? viewerId;
  final List<GearRow> gear;

  @override
  String? get userId => viewerId;

  @override
  Future<List<GearRow>> fetchRunGear(String runId) async => gear;
}

GearRow _gear(String id, String kind, String name) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return GearRow(
    id: id,
    ownerId: '',
    kind: kind,
    name: name,
    createdAt: epoch,
    updatedAt: epoch,
    isDefault: false,
  );
}

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunGearChips(
          api: api,
          runId: 'run-1',
          runOwnerId: 'owner-1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RunGearChips — public (non-owner) view', () {
    testWidgets('renders assigned gear read-only for a non-owner viewer',
        (tester) async {
      await _pump(
        tester,
        _FakeApiClient(
          viewerId: 'someone-else',
          gear: [_gear('g1', 'shoe', 'Pegasus 40')],
        ),
      );
      expect(find.text('Pegasus 40'), findsOneWidget);
      // No owner-only edit affordance for a stranger.
      expect(find.text('Edit'), findsNothing);
      expect(find.text('+ Tag gear'), findsNothing);
    });

    testWidgets('renders assigned gear read-only for an anonymous viewer',
        (tester) async {
      await _pump(
        tester,
        _FakeApiClient(
          viewerId: null,
          gear: [_gear('g1', 'bike', 'Tarmac SL7')],
        ),
      );
      expect(find.text('Tarmac SL7'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('+ Tag gear'), findsNothing);
    });

    testWidgets('renders nothing when a non-owner run has no gear',
        (tester) async {
      await _pump(tester, _FakeApiClient(viewerId: 'someone-else'));
      expect(find.byType(Chip), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('+ Tag gear'), findsNothing);
    });
  });

  group('RunGearChips — owner view', () {
    testWidgets('owner sees the Edit affordance alongside the chips',
        (tester) async {
      await _pump(
        tester,
        _FakeApiClient(
          viewerId: 'owner-1',
          gear: [_gear('g1', 'shoe', 'Pegasus 40')],
        ),
      );
      expect(find.text('Pegasus 40'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('owner with no gear still sees the Tag affordance',
        (tester) async {
      await _pump(tester, _FakeApiClient(viewerId: 'owner-1'));
      expect(find.text('+ Tag gear'), findsOneWidget);
    });
  });
}
