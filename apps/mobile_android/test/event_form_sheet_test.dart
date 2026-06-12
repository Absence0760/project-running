import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/social_service.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/event_form_sheet.dart';

class _Launcher extends StatefulWidget {
  final SocialService social;
  const _Launcher({required this.social});

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

Future<void> _openSheet(WidgetTester tester) async {
  // Larger viewport so the scrollable form actually paints all rows.
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Launcher(social: SocialService())));
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
  });
}
