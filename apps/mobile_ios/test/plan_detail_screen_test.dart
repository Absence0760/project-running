import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

ClubView _club({
  required String id,
  required String name,
  String? slug,
  String? location,
  int memberCount = 5,
  String? viewerRole,
  String joinPolicy = 'open',
}) =>
    ClubView(
      row: ClubRow(
        id: id,
        ownerId: 'owner-uuid',
        name: name,
        slug: slug ?? id,
        locationLabel: location,
        joinPolicy: joinPolicy,
        memberCount: memberCount,
      ),
      memberCount: memberCount,
      viewerRole: viewerRole,
      viewerStatus: viewerRole == null ? null : 'active',
      joinPolicy: joinPolicy,
    );

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: PlanDetailScreen(
        training: TrainingService(),
        planId: 'fake-plan-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('PlanDetailScreen — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold with just a centered spinner — no AppBar yet. This
      // is the only deterministic surface without a stub TrainingService.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('initial Scaffold has no AppBar yet', (tester) async {
      // Reason: the loading-state Scaffold is bare; the AppBar with
      // the plan name only paints after the fetch resolves.
      await _pump(tester);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('adminClubsForPublish', () {
    test('keeps owner + admin rows, drops other roles', () {
      final clubs = [
        _club(id: 'a', name: 'Alpha', viewerRole: 'owner'),
        _club(id: 'b', name: 'Beta', viewerRole: 'admin'),
        _club(id: 'c', name: 'Gamma', viewerRole: 'event_organiser'),
        _club(id: 'd', name: 'Delta', viewerRole: 'race_director'),
        _club(id: 'e', name: 'Epsilon', viewerRole: 'member'),
        _club(id: 'f', name: 'Zeta', viewerRole: null),
      ];
      final filtered = adminClubsForPublish(clubs);
      expect(filtered.map((c) => c.row.id).toList(), ['a', 'b'],
          reason: 'only owner + admin pass through — event_organiser, '
              'race_director, member, and missing-role rows must drop. '
              'Anything else lets a non-admin viewer publish a plan '
              'into a club they do not control.');
    });

    test('returns an empty list when no clubs qualify', () {
      final clubs = [
        _club(id: 'a', name: 'Alpha', viewerRole: 'member'),
      ];
      expect(adminClubsForPublish(clubs), isEmpty);
    });

    test('handles an empty input list', () {
      expect(adminClubsForPublish(const <ClubView>[]), isEmpty);
    });
  });

  group('PublishClubPicker', () {
    Future<void> pumpPicker(WidgetTester tester, List<ClubView> clubs) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PublishClubPicker(clubs: clubs)),
        ),
      );
    }

    testWidgets('renders one tile per club + the header copy',
        (tester) async {
      await pumpPicker(tester, [
        _club(id: 'a', name: 'Alpha', location: 'Sydney', memberCount: 12),
        _club(id: 'b', name: 'Beta', memberCount: 1),
      ]);
      expect(find.text('Publish to club'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      // Subtitle: location (or slug fallback) + member count.
      expect(find.textContaining('Sydney · 12 members'), findsOneWidget);
      // Singular agreement on memberCount == 1.
      expect(find.textContaining('1 member'), findsOneWidget);
    });

    testWidgets('tapping a row pops the club id', (tester) async {
      String? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showModalBottomSheet<String>(
                      context: context,
                      builder: (_) => PublishClubPicker(clubs: [
                        _club(id: 'club-uuid-42', name: 'Sydney RC'),
                      ]),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sydney RC'));
      await tester.pumpAndSettle();
      expect(popped, 'club-uuid-42',
          reason: 'tapping a row must pop the corresponding club id so '
              'the caller can hand it to publishPlanAsTemplate');
    });

    testWidgets('Cancel pops null without selecting', (tester) async {
      String? popped = 'sentinel';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showModalBottomSheet<String>(
                      context: context,
                      builder: (_) => PublishClubPicker(clubs: [
                        _club(id: 'a', name: 'Alpha'),
                      ]),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(popped, isNull);
    });
  });
}
