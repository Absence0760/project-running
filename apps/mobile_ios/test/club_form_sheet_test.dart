import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/social_service.dart';
import '../lib/widgets/club_form_sheet.dart';

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
                final r = await showClubFormSheet(context, social: widget.social);
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
  // Bottom sheet content overflows the default 600x800 test viewport;
  // give it room so the SegmentedButton at the bottom of the form
  // actually paints into the layer tree.
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: _Launcher(social: SocialService())));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('showClubFormSheet', () {
    testWidgets('renders the New club heading and Name / Description / Location fields',
        (tester) async {
      await _openSheet(tester);
      expect(find.text('New club'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Description (optional)'),
          findsOneWidget);
      expect(find.widgetWithText(TextField, 'Location (optional)'),
          findsOneWidget);
    });

    testWidgets('renders the Public / Private visibility segmented button',
        (tester) async {
      await _openSheet(tester);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    });
  });
}
