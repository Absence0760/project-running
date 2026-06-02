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
    testWidgets('renders the New event heading', (tester) async {
      await _openSheet(tester);
      expect(find.text('New event'), findsOneWidget);
    });

    testWidgets('renders the Title and Starts at fields', (tester) async {
      await _openSheet(tester);
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      // Starts-at is rendered with an InputDecorator (not a TextField)
      // because it opens a date/time picker on tap.
      expect(find.text('Starts at'), findsOneWidget);
    });
  });
}
