import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart';
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

/// Drives the replace-active-plan confirm gate: `fetchActiveOverview`
/// returns a configurable existing active plan (or null), and `createPlan`
/// records whether it was reached. The viewer-demographic fetches return
/// quietly so no network is touched in the widget test.
class _GateTraining extends TrainingService {
  final ActivePlanOverview? activeOverview;
  bool createCalled = false;
  _GateTraining({this.activeOverview});

  @override
  Future<TrainingGender> fetchViewerGender() async => null;
  @override
  Future<int?> fetchViewerAge() async => null;
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      const [];
  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async => activeOverview;

  @override
  Future<TrainingPlanRow> createPlan({
    required String name,
    required GoalEvent goalEvent,
    required double goalDistanceM,
    int? goalTimeSec,
    int? recent5kSec,
    required DateTime startDate,
    required int daysPerWeek,
    String? notes,
    required GeneratedPlan generated,
  }) async {
    createCalled = true;
    // Throw after recording the call so the screen's try/catch keeps us on
    // the wizard (a real success navigates to PlanDetailScreen, which is
    // Supabase-backed and unbuildable in a widget test). The test only
    // asserts the gate reached createPlan.
    throw Exception('test: skip navigation');
  }
}

TrainingPlanRow _planRow(String id, String name) => TrainingPlanRow(
      id: id,
      userId: 'me-uuid',
      name: name,
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: DateTime(2026, 1, 4),
      endDate: DateTime(2026, 3, 1),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
      createdAt: DateTime(2026, 1, 1),
    );

ActivePlanOverview _overview(String name) => ActivePlanOverview(
      plan: _planRow('existing-plan', name),
      weeks: const [],
      workouts: const [],
      todayWorkout: null,
      completionPct: 0,
      currentWeekIndex: 0,
    );

ClubView _club(String id, String name) => ClubView(
      row: ClubRow(shadowHidden: false, 
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

  group('PlanNewScreen — replace-active-plan confirm gate', () {
    Future<void> pumpGate(WidgetTester tester, _GateTraining training) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlanNewScreen(training: training),
        ),
      );
      // initState fires the (overridden) viewer fetches — let them settle.
      await tester.pump();
    }

    // Fills the name, scrolls the Create button into view, and taps it.
    // The name TextField has no onChanged-driven rebuild, but
    // scrollUntilVisible pumps frames as it scrolls so the button picks up
    // the typed name and enables before the tap.
    Future<void> tapCreate(WidgetTester tester) async {
      await tester.enterText(
          find.widgetWithText(TextField, 'Plan name'), 'Autumn half');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Create plan'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create plan'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'creating with an existing active plan shows the replace confirm',
        (tester) async {
      // Reason: createPlan silently auto-completes the current active plan —
      // weeks of a build vanish with no warning unless we gate it.
      final training = _GateTraining(activeOverview: _overview('Spring base'));
      await pumpGate(tester, training);
      await tapCreate(tester);
      expect(find.text('Replace your active plan?'), findsOneWidget);
      expect(find.textContaining('Spring base'), findsOneWidget);
      expect(training.createCalled, isFalse);
    });

    testWidgets('Keep current dismisses the dialog without creating',
        (tester) async {
      final training = _GateTraining(activeOverview: _overview('Spring base'));
      await pumpGate(tester, training);
      await tapCreate(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Keep current'));
      await tester.pumpAndSettle();
      expect(find.text('Replace your active plan?'), findsNothing);
      expect(training.createCalled, isFalse);
    });

    testWidgets('Replace plan proceeds to createPlan', (tester) async {
      final training = _GateTraining(activeOverview: _overview('Spring base'));
      await pumpGate(tester, training);
      await tapCreate(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Replace plan'));
      await tester.pumpAndSettle();
      expect(training.createCalled, isTrue);
    });

    testWidgets('no active plan creates without a confirm dialog',
        (tester) async {
      final training = _GateTraining(activeOverview: null);
      await pumpGate(tester, training);
      await tapCreate(tester);
      expect(find.text('Replace your active plan?'), findsNothing);
      expect(training.createCalled, isTrue);
    });
  });

  group('goal preselection (onboarding nudge)', () {
    // The form sits in a lazy ListView; a tall surface builds the beginner
    // toggle so its state can be read.
    Future<void> pumpPreset(WidgetTester tester,
        {GoalEvent? goal, bool beginner = false}) {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlanNewScreen(
            training: TrainingService(),
            initialGoal: goal,
            initialBeginnerWalkRun: beginner,
          ),
        ),
      );
    }

    CheckboxListTile beginnerTile(WidgetTester tester) =>
        tester.widget<CheckboxListTile>(find.widgetWithText(
            CheckboxListTile, 'New to running? Use a walk-run plan'));

    testWidgets('initialBeginnerWalkRun ticks the walk-run toggle on mount',
        (tester) async {
      await pumpPreset(tester, goal: GoalEvent.distance5k, beginner: true);
      expect(beginnerTile(tester).value, isTrue);
    });

    testWidgets('defaults leave the walk-run toggle unticked', (tester) async {
      await pumpPreset(tester);
      expect(beginnerTile(tester).value, isFalse);
    });
  });

  group('PlanNewScreen — beginner walk-run hides pace jargon', () {
    const paceLabels = ['Easy', 'Marathon', 'Tempo', 'Interval', 'Rep'];

    testWidgets('a normal plan preview shows the five pace zones',
        (tester) async {
      await _pump(tester);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Week outline'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      for (final label in paceLabels) {
        expect(find.text(label), findsWidgets, reason: 'pace pill "$label"');
      }
    });

    testWidgets('ticking the walk-run toggle hides the pace zones + VDOT',
        (tester) async {
      // Reason: a beginner walk-run plan is duration-based intervals — the
      // Daniels VDOT badge + five pace zones are jargon the runner who ticked
      // "New to running?" can't parse. The preview must drop them and show
      // only the week outline (persona runner-new finding #1).
      await _pump(tester);
      await tester.pump();
      final toggle = find.text('New to running? Use a walk-run plan');
      await tester.scrollUntilVisible(
        toggle,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Week outline'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // The duration-based week outline is still rendered...
      expect(find.text('Week outline'), findsOneWidget);
      // ...but the pace zones + VDOT line are gone.
      for (final label in paceLabels) {
        expect(find.text(label), findsNothing, reason: 'pace pill "$label"');
      }
      expect(find.textContaining('Daniels VDOT'), findsNothing);
    });
  });
}
