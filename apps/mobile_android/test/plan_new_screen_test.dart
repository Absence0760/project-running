import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanNewScreen(training: TrainingService()),
    ),
  );
}

class _FakeSocial extends SocialService {
  final List<ClubView> clubs;
  _FakeSocial(this.clubs);
  @override
  Future<List<ClubView>> fetchMyClubs() async => clubs;
}

class _FakeTraining extends TrainingService {
  final Map<String, List<TrainingPlanRow>> templatesByClub;
  _FakeTraining(this.templatesByClub);
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      templatesByClub[clubId] ?? const [];
}

ClubView _club(String id, String name) => ClubView(
      row: ClubRow(
        id: id,
        ownerId: 'owner-uuid',
        name: name,
        slug: id,
        joinPolicy: 'open',
        memberCount: 5,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 5,
      viewerRole: 'member',
      viewerStatus: 'active',
      joinPolicy: 'open',
    );

TrainingPlanRow _template(String id, String name) => TrainingPlanRow(
      id: id,
      userId: 'owner-uuid',
      name: name,
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 3, 1),
      daysPerWeek: 4,
      status: 'completed',
      source: 'generated',
      isTemplate: true,
      isPublicTemplate: false,
      clubId: 'club-1',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('PlanNewScreen — initial render', () {
    testWidgets('renders the New plan app-bar title', (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(find.text('New plan'), findsOneWidget);
    });

    testWidgets('renders the Start date list tile', (tester) async {
      // Reason: the start date is the anchor for the whole generated
      // plan — its picker tile must be present so users can shift it.
      await _pump(tester);
      await tester.pump();
      expect(find.text('Start date'), findsOneWidget);
    });

    testWidgets('renders the Cancel and Create plan buttons',
        (tester) async {
      // Reason: the wizard is committed only via "Create plan"; the
      // Cancel pop must remain reachable so users can back out.
      // The buttons live at the bottom of a lazy ListView — scroll to
      // bring them into the viewport before asserting.
      await _pump(tester);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Create plan'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create plan'), findsOneWidget);
    });
  });

  group('PlanNewScreen — recent-5K recency gate (comeback persona #24)', () {
    final warnFinder = find.textContaining('too fast for a returning runner');
    final confirmFinder = find.textContaining('reflects my current fitness');

    testWidgets('no confirm checkbox or warning until a 5K time is entered',
        (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(confirmFinder, findsNothing);
      expect(warnFinder, findsNothing);
    });

    testWidgets('entering a 5K time surfaces the confirm box + warning',
        (tester) async {
      // Reason: a returning runner typing an old PR must be told the time
      // isn't trusted until confirmed, and that unconfirmed leaves paces on
      // the conservative goal-based estimate — otherwise the engine would
      // prescribe dangerously fast paces.
      await _pump(tester);
      await tester.pump();
      // The form is a lazy ListView and the recent-5K field sits below the
      // starter-plan picker, so it isn't built initially. Pass the bare
      // finder (no `.last` — the 'min' hint is unique) so scrollUntilVisible
      // can scroll-and-build it; `.last` over a not-yet-built finder throws
      // "Bad state: No element" and breaks the scroll loop.
      final minField = find.widgetWithText(TextField, 'min');
      await tester.scrollUntilVisible(
        minField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(minField, '22');
      await tester.pump();
      expect(confirmFinder, findsOneWidget);
      expect(warnFinder, findsOneWidget);
    });

    testWidgets('ticking the confirm box clears the warning', (tester) async {
      await _pump(tester);
      await tester.pump();
      final minField = find.widgetWithText(TextField, 'min');
      await tester.scrollUntilVisible(
        minField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(minField, '22');
      await tester.pump();
      // Tap the tile title (the raw Checkbox sits below the fold); the
      // CheckboxListTile toggles from a tap anywhere on the tile.
      await tester.ensureVisible(confirmFinder);
      await tester.pump();
      await tester.tap(confirmFinder);
      await tester.pump();
      expect(warnFinder, findsNothing);
    });
  });

  group('PlanNewScreen — club-template picker', () {
    Future<void> pumpWithTemplates(
      WidgetTester tester, {
      required List<ClubView> clubs,
      required Map<String, List<TrainingPlanRow>> templates,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlanNewScreen(
            training: _FakeTraining(templates),
            social: _FakeSocial(clubs),
          ),
        ),
      );
      // The template fetch is async network/store I/O — let it resolve.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
    }

    testWidgets('hidden when the viewer has no club templates',
        (tester) async {
      await pumpWithTemplates(tester, clubs: const [], templates: const {});
      expect(find.text('Start from a club template'), findsNothing);
    });

    testWidgets('shows the template card when a club has a template',
        (tester) async {
      await pumpWithTemplates(
        tester,
        clubs: [_club('club-1', 'Trail Club')],
        templates: {
          'club-1': [_template('tpl-1', 'Spring Half')],
        },
      );
      expect(find.text('Start from a club template'), findsOneWidget);
      expect(find.text('Browse templates'), findsOneWidget);
    });

    testWidgets('opening the picker lists each template with its club',
        (tester) async {
      await pumpWithTemplates(
        tester,
        clubs: [_club('club-1', 'Trail Club')],
        templates: {
          'club-1': [_template('tpl-1', 'Spring Half')],
        },
      );
      await tester.tap(find.text('Browse templates'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a template'), findsOneWidget);
      expect(find.text('Spring Half'), findsOneWidget);
      expect(find.text('Trail Club'), findsOneWidget);
    });
  });
}
