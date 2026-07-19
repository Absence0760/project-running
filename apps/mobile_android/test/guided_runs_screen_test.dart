import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/guided_runs_screen.dart';

Widget _app(Widget home, {double bottomInset = 0}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GuidedRunsScreen reserves the bottom safe-area inset below the list',
      (tester) async {
    const inset = 48.0;
    await tester.pumpWidget(
      _app(const GuidedRunsScreen(), bottomInset: inset),
    );
    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final padding = listView.padding!.resolve(TextDirection.ltr);
    expect(padding.bottom, greaterThanOrEqualTo(inset));
    expect(padding.bottom, inset + 8);
  });

  testWidgets('GuidedRunsScreen keeps its base bottom padding with no inset',
      (tester) async {
    await tester.pumpWidget(_app(const GuidedRunsScreen()));
    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final padding = listView.padding!.resolve(TextDirection.ltr);
    expect(padding.bottom, 8);
  });
}
