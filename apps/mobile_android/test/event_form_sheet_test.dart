import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/event_gym_template.dart';
import '../lib/social_service.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/event_form_sheet.dart';

/// Captures createEvent args (incl. the typed-event fields) + returns a
/// stub EventRow so the success path + field self-hiding can be asserted
/// end-to-end. [throwOnCreate] drives the failure-surface path.
class _CapturingSocialService extends SocialService {
  _CapturingSocialService({this.throwOnCreate});
  final Object? throwOnCreate;

  bool createCalled = false;
  String? capturedTitle;
  String? capturedCategory;
  String? capturedDiscipline;
  double? capturedDistanceM;
  EventGymTemplate? capturedGymTemplate;
  String? capturedRecurrenceFreq;
  bool? capturedIsPublic;

  @override
  Future<EventRow> createEvent({
    required String clubId,
    required String title,
    required DateTime startsAt,
    String category = 'run',
    String? discipline,
    EventGymTemplate? gymTemplate,
    String? description,
    int? durationMin,
    String? meetLabel,
    double? meetLat,
    double? meetLng,
    String? routeId,
    double? distanceM,
    int? paceTargetSec,
    int? capacity,
    String? recurrenceFreq,
    List<String>? recurrenceByDay,
    DateTime? recurrenceUntil,
    int? recurrenceCount,
    bool isPublic = true,
  }) async {
    createCalled = true;
    capturedTitle = title;
    capturedCategory = category;
    capturedDiscipline = discipline;
    capturedDistanceM = distanceM;
    capturedGymTemplate = gymTemplate;
    capturedRecurrenceFreq = recurrenceFreq;
    capturedIsPublic = isPublic;
    if (throwOnCreate != null) throw throwOnCreate!;
    return EventRow(
      id: 'event-new',
      clubId: clubId,
      title: title,
      startsAt: startsAt,
      authorId: 'author-1',
      category: category,
      isPublic: isPublic,
      discipline: discipline,
    );
  }
}

class _Launcher extends StatefulWidget {
  final SocialService social;
  final bool clubIsPublic;
  const _Launcher({required this.social, this.clubIsPublic = true});

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                final r = await showEventFormSheet(
                  context,
                  social: widget.social,
                  clubId: 'club-1',
                  clubIsPublic: widget.clubIsPublic,
                );
                setState(() => _result = r ?? '<cancelled>');
              },
              child: const Text('Open'),
            ),
            if (_result != null) Text('result=$_result'),
          ],
        ),
      ),
    );
  }
}

Future<void> _openSheet(
  WidgetTester tester, {
  bool clubIsPublic = true,
  SocialService? social,
}) async {
  // Larger viewport so the scrollable form actually paints all rows.
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Launcher(
          social: social ?? SocialService(), clubIsPublic: clubIsPublic)));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('showEventFormSheet', () {
    testWidgets('opens as a full-screen dialog with the New event heading',
        (tester) async {
      await _openSheet(tester);
      // Heading now lives in the host AppBar (full-screen dialog), not an
      // inline Text in a bottom sheet.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('New event'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('renders the Title and Starts at fields', (tester) async {
      await _openSheet(tester);
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      // Starts-at is rendered with an InputDecorator (not a TextField)
      // because it opens a date/time picker on tap.
      expect(find.text('Starts at'), findsOneWidget);
    });

    testWidgets('shows the category picker with all four types as the first '
        'control', (tester) async {
      await _openSheet(tester);
      expect(find.text('Event type'), findsOneWidget);
      for (final label in ['Group run', 'Cycle', 'Class', 'Social']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
    });

    testWidgets('a run event shows the distance field and no discipline field',
        (tester) async {
      await _openSheet(tester);
      expect(find.widgetWithText(TextField, 'Distance (km)'), findsOneWidget);
      expect(find.text('Discipline'), findsNothing);
    });

    testWidgets('picking Class reveals the discipline field and hides the '
        'athletic distance field', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      expect(find.text('Discipline'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Distance (km)'), findsNothing);
    });

    testWidgets('picking Social hides both the discipline and distance fields',
        (tester) async {
      await _openSheet(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Social'));
      await tester.pumpAndSettle();
      expect(find.text('Discipline'), findsNothing);
      expect(find.widgetWithText(TextField, 'Distance (km)'), findsNothing);
    });

    testWidgets('a public club shows the members-only toggle, defaulting off',
        (tester) async {
      await _openSheet(tester);
      final toggle = find.widgetWithText(SwitchListTile, 'Members only');
      expect(toggle, findsOneWidget);
      // Default is public → the members-only switch is off.
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      // It's interactive.
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('a private club hides the members-only toggle', (tester) async {
      // A private club's events are already members-only via the club gate,
      // so the toggle is hidden there.
      await _openSheet(tester, clubIsPublic: false);
      expect(find.widgetWithText(SwitchListTile, 'Members only'), findsNothing);
    });
  });

  group('showEventFormSheet — submit', () {
    Future<void> tapCreate(WidgetTester tester) async {
      final btn = find.widgetWithText(FilledButton, 'Create event');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }

    testWidgets('blank title → Create is a no-op (no createEvent call)',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tapCreate(tester);
      expect(fake.createCalled, isFalse);
    });

    testWidgets('a run event submits distance in metres + run category',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Saturday 5k');
      await tester.enterText(
          find.widgetWithText(TextField, 'Distance (km)'), '5');
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      expect(fake.capturedTitle, 'Saturday 5k');
      expect(fake.capturedCategory, 'run');
      // 5 km entered → 5000 m persisted.
      expect(fake.capturedDistanceM, 5000);
      expect(fake.capturedDiscipline, isNull);
      expect(fake.capturedGymTemplate, isNull);
      expect(find.text('result=ok'), findsOneWidget);
    });

    testWidgets(
        'a class event submits discipline + gym_template and drops distance',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Class'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Discipline'), 'Vinyasa Yoga');
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Morning flow');
      await tester.enterText(
          find.widgetWithText(TextField, 'Duration (min)'), '60');
      await tapCreate(tester);
      expect(fake.capturedCategory, 'class');
      expect(fake.capturedDiscipline, 'Vinyasa Yoga');
      // Athletic distance is not collected for a class.
      expect(fake.capturedDistanceM, isNull);
      expect(fake.capturedGymTemplate, isNotNull);
      expect(fake.capturedGymTemplate!.discipline, 'Vinyasa Yoga');
      expect(fake.capturedGymTemplate!.durationMin, 60);
    });

    testWidgets(
        'typing a distance then switching to Social clears it before submit',
        (tester) async {
      // The self-hiding contract: a distance typed under "run" must not
      // survive a switch to a non-athletic category.
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Distance (km)'), '10');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Social'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Pub night');
      await tapCreate(tester);
      expect(fake.capturedCategory, 'social');
      expect(fake.capturedDistanceM, isNull);
    });

    testWidgets('picking Weekly threads a weekly recurrence freq',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Tuesday tempo');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Weekly'));
      await tester.pumpAndSettle();
      await tapCreate(tester);
      expect(fake.capturedRecurrenceFreq, 'weekly');
    });

    testWidgets('toggling members-only on a public club submits isPublic=false',
        (tester) async {
      final fake = _CapturingSocialService();
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Members run');
      final toggle = find.widgetWithText(SwitchListTile, 'Members only');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tapCreate(tester);
      expect(fake.capturedIsPublic, isFalse);
    });

    testWidgets('a failed create surfaces the error inline + does not pop',
        (tester) async {
      final fake =
          _CapturingSocialService(throwOnCreate: Exception('boom-create'));
      await _openSheet(tester, social: fake);
      await tester.enterText(
          find.widgetWithText(TextField, 'Title'), 'Doomed event');
      await tapCreate(tester);
      expect(fake.createCalled, isTrue);
      // Classified copy inline, never the raw exception (issue #240).
      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(find.textContaining('boom-create'), findsNothing);
      // The sheet stays open (result not yet set on the launcher).
      expect(find.textContaining('result='), findsNothing);
    });
  });
}
