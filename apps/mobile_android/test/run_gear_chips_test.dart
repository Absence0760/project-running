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

/// The assigned-gear read fails until [failures] is exhausted. Before the
/// fail-closed guard the owner saw an empty "+ Tag gear" state, and saving
/// from it deleted the run's real gear rows.
class _FailingReadApiClient extends ApiClient {
  _FailingReadApiClient({this.failures = 1 << 30, this.gear = const []});

  final int failures;
  final List<GearRow> gear;
  int reads = 0;

  @override
  String? get userId => 'owner-1';

  @override
  Future<List<GearRow>> fetchRunGear(String runId) async {
    reads++;
    if (reads <= failures) throw Exception('offline');
    return gear;
  }
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

    testWidgets('a long gear name ellipsizes and does not overflow the row',
        (tester) async {
      // Narrow surface so an uncapped chip would blow past the row width.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longName = 'Nike Vaporfly Next% 3 Special Limited Edition';
      await _pump(
        tester,
        _FakeApiClient(
          viewerId: 'someone-else',
          gear: [_gear('g1', 'shoe', longName)],
        ),
      );
      final text = tester.widget<Text>(find.text(longName));
      expect(text.overflow, TextOverflow.ellipsis);
      // No RenderFlex overflow was thrown while laying the chip out.
      expect(tester.takeException(), isNull);
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

  group('RunGearChips — failed read', () {
    testWidgets('withholds the picker rather than showing an empty baseline',
        (tester) async {
      await _pump(tester, _FailingReadApiClient());
      expect(find.textContaining("Couldn't load gear"), findsOneWidget);
      // Opening the picker from here would seed an empty selection, and
      // saving it would delete the run's real gear rows.
      expect(find.text('+ Tag gear'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('Retry re-reads and restores the chips', (tester) async {
      final api = _FailingReadApiClient(
        failures: 1,
        gear: [_gear('g1', 'shoe', 'Pegasus 40')],
      );
      await _pump(tester, api);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.reads, 2);
      expect(find.text('Pegasus 40'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });
  });
}
