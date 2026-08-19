import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_ramp.dart';
import '../lib/race_plan_preset.dart';
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

/// Serves a fixed chronic-volume read to the ramp note. The demographic
/// fetches return quietly so no network is touched in the widget test.
class _RampTraining extends TrainingService {
  final RecentVolume? volume;
  _RampTraining(this.volume);

  @override
  Future<TrainingGender> fetchViewerGender() async => null;
  @override
  Future<int?> fetchViewerAge() async => null;
  @override
  Future<RecentVolume?> fetchRecentRunVolume() async => volume;
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      const [];
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

  group('PlanNewScreen — opening-week ramp note', () {
    Future<void> pumpTall(WidgetTester tester, RecentVolume? volume) {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlanNewScreen(training: _RampTraining(volume)),
        ),
      );
    }

    testWidgets('a plan far above the runner\'s recent volume is called out',
        (tester) async {
      await pumpTall(
        tester,
        const RecentVolume(weeklyM: 2000, acuteM: 2000, activeWeeks: 4),
      );
      await tester.pump();
      expect(find.text('Plan vs. your recent training'), findsOneWidget);
      expect(find.textContaining('Week 1 asks for'), findsOneWidget);
    });

    testWidgets('a plan the runner has already outgrown reads under',
        (tester) async {
      await pumpTall(
        tester,
        const RecentVolume(weeklyM: 1000000, acuteM: 1000000, activeWeeks: 4),
      );
      await tester.pump();
      expect(find.textContaining('This plan peaks at'), findsOneWidget);
    });

    testWidgets('too little history says nothing at all', (tester) async {
      // The gate the check exists for: two active weeks is arithmetic on
      // noise, and a confident verdict off it would be worse than silence.
      await pumpTall(
        tester,
        const RecentVolume(weeklyM: 2000, acuteM: 2000, activeWeeks: 2),
      );
      await tester.pump();
      expect(find.text('Plan vs. your recent training'), findsNothing);
    });

    testWidgets('a failed volume read leaves the wizard untouched',
        (tester) async {
      await pumpTall(tester, null);
      await tester.pump();
      expect(find.text('Plan vs. your recent training'), findsNothing);
      expect(find.text('Week outline'), findsOneWidget);
    });

    testWidgets('a walk-run plan is not told it is gentle', (tester) async {
      await pumpTall(
        tester,
        const RecentVolume(weeklyM: 1000000, acuteM: 1000000, activeWeeks: 4),
      );
      await tester.pump();
      expect(find.textContaining('This plan peaks at'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(find.text('Plan vs. your recent training'), findsNothing);
    });
  });

  group('PlanNewScreen — beginner input surface (#262 recent-5K, #263 name)',
      () {
    // The form is a lazy ListView; a tall surface builds every field so its
    // presence/absence can be asserted without scrolling.
    Future<void> pumpTall(WidgetTester tester,
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

    final riegelFinder = find.textContaining('Riegel equivalence');

    testWidgets('a normal plan shows the recent-5K + Riegel helper',
        (tester) async {
      await pumpTall(tester);
      await tester.pump();
      expect(riegelFinder, findsOneWidget);
    });

    testWidgets('the beginner walk-run preset hides the recent-5K + Riegel helper',
        (tester) async {
      // Reason (#262): a walk-run plan is duration-based intervals — a
      // recent-5K anchor + "Riegel equivalence" jargon is meaningless to a
      // runner who has never run a 5K. Mirrors the preview panel already
      // hiding the pace zones + VDOT in walk-run mode.
      await pumpTall(tester, beginner: true);
      await tester.pump();
      expect(riegelFinder, findsNothing);
    });

    testWidgets('the beginner preset prefills a default plan name (#263)',
        (tester) async {
      // Reason (#263): the onboarding nudge lands here with an empty name, so
      // the Create button was silently disabled — a dead-end tap. The preset
      // now seeds an editable default name so Create is reachable on arrival.
      await pumpTall(tester, goal: GoalEvent.distance5k, beginner: true);
      await tester.pump();
      final field = tester
          .widget<TextField>(find.widgetWithText(TextField, 'Plan name'));
      expect(field.controller?.text, 'Walk-run to 5K');
    });

    testWidgets('a no-preset plan shows the inline name-required hint (#263)',
        (tester) async {
      await pumpTall(tester);
      await tester.pump();
      expect(find.text('Add a plan name to enable Create.'), findsOneWidget);
    });
  });

  group('PlanNewScreen — the week-outline preview row survives the locale', () {
    // The phase name is the row's only localized phrase and sat in a 70px box:
    // French "Semaine de fin de programme" needs 186px in real Roboto at 1.0x,
    // so it reflowed the row four lines deep before the OS text scale was even
    // touched. It now absorbs the row's slack and ellipsizes (§486 — the label
    // truncates, never the value), while the week number rides a TextLane and
    // the two numerics take their intrinsic width.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so these assertions hold a
    // fortiori on a device.
    Future<void> pumpFrench(WidgetTester tester,
        {Size surface = const Size(320, 2400), double scale = 1.0}) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: PlanNewScreen(training: TrainingService()),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Aperçu des semaines'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }

    Finder weekLane() => find.ancestor(
          of: find.text('#1'),
          matching: find.byType(TextLane),
        );

    testWidgets('the week-number lane gives its digits their full width',
        (tester) async {
      await pumpFrench(tester);
      expect(weekLane(), findsOneWidget);
      final digits = tester.renderObject<RenderParagraph>(find.text('#1'));
      expect(
        tester.getSize(weekLane()).width,
        greaterThanOrEqualTo(digits.getMaxIntrinsicWidth(double.infinity)),
      );
    });

    testWidgets('the week-number lane grows with the OS text scale',
        (tester) async {
      // A wide surface, because the goal dropdown above the preview carries a
      // separate 2x overflow this round does not own.
      await pumpFrench(tester,
          surface: const Size(800, 2400), scale: 2.0);
      expect(tester.getSize(weekLane()).width, greaterThanOrEqualTo(60));
    });

    testWidgets('the phase label ellipsizes instead of reflowing the row',
        (tester) async {
      await pumpFrench(tester);
      final phase = find.text('Base').first;
      expect(tester.widget<Text>(phase).maxLines, 1);
      expect(tester.widget<Text>(phase).overflow, TextOverflow.ellipsis);
      final para = tester.renderObject<RenderParagraph>(phase);
      expect(para.size.height, lessThan(para.preferredLineHeight * 2),
          reason: 'the phase lane must stay one line tall');
    });
  });

  group('PlanNewScreen — the race the wizard was opened from', () {
    Future<void> pumpRace(WidgetTester tester,
        {required String raceDateIso, String? name, num? distanceM}) {
      // The form sits in a lazy ListView; a tall surface builds every field
      // the preset writes to so their state can be read.
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlanNewScreen(
            training: _RampTraining(null),
            social: _FakeSocial(const []),
            raceDateIso: raceDateIso,
            raceName: name,
            raceDistanceM: distanceM,
          ),
        ),
      );
    }

    List<String> fieldTexts(WidgetTester tester) => tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((e) => e.controller.text)
        .toList();

    String isoDaysOut(int days) =>
        toIsoDate(DateTime.now().add(Duration(days: days)));

    testWidgets('a half marathon far out sizes the wizard around race week',
        (tester) async {
      final raceIso = isoDaysOut(220);
      final expected = racePlanPreset(
        raceDateIso: raceIso,
        distanceM: 21097.5,
        todayIso: toIsoDate(DateTime.now()),
      ).preset!;
      await pumpRace(tester,
          raceDateIso: raceIso, name: 'Autumn Half', distanceM: 21097.5);
      await tester.pump();

      expect(find.byKey(const Key('plan-new-race-note')), findsOneWidget);
      expect(find.textContaining('${expected.weeks}-week plan'), findsOneWidget);
      expect(find.text(expected.startDate), findsOneWidget);
      final goal = tester.widget<DropdownButtonFormField<GoalEvent>>(
          find.byType(DropdownButtonFormField<GoalEvent>));
      expect(goal.initialValue, GoalEvent.distanceHalf);
      expect(fieldTexts(tester), contains('Autumn Half'));
      expect(fieldTexts(tester), contains('${expected.weeks}'));
    });

    testWidgets('a race already run falls back to the defaults and says why',
        (tester) async {
      await pumpRace(tester,
          raceDateIso: isoDaysOut(-3), name: 'Last Month 10K', distanceM: 10000);
      await tester.pump();

      expect(
        find.text(
            'That race has already been run, so the dates below are the usual defaults.'),
        findsOneWidget,
      );
      // The name would still claim the race after the dates fell back, so it
      // is withheld too — leaving the Create button on its own empty-name gate.
      expect(fieldTexts(tester), isNot(contains('Last Month 10K')));
    });

    testWidgets('a race too close to plan for is refused, not squeezed',
        (tester) async {
      await pumpRace(tester, raceDateIso: isoDaysOut(9), distanceM: 5000);
      await tester.pump();
      expect(
        find.text(
            'That race is too close to build a full plan for, so the dates below are the usual defaults.'),
        findsOneWidget,
      );
    });

    testWidgets('a distance matching no rung presets the dates but not the goal',
        (tester) async {
      // A 50k trail ultra: the goal dropdown has no custom-distance entry, so
      // snapping it to the marathon rung would preselect a different race.
      final raceIso = isoDaysOut(220);
      final expected = racePlanPreset(
        raceDateIso: raceIso,
        distanceM: 50000,
        todayIso: toIsoDate(DateTime.now()),
      ).preset!;
      await pumpRace(tester, raceDateIso: raceIso, distanceM: 50000);
      await tester.pump();
      final goal = tester.widget<DropdownButtonFormField<GoalEvent>>(
          find.byType(DropdownButtonFormField<GoalEvent>));
      expect(goal.initialValue, GoalEvent.distanceHalf); // the wizard default
      expect(find.text(expected.startDate), findsOneWidget);
    });

    testWidgets('no race leaves the wizard silent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlanNewScreen(
            training: _RampTraining(null),
            social: _FakeSocial(const []),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('plan-new-race-note')), findsNothing);
    });
  });
}

