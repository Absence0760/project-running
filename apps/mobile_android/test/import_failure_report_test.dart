import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/import_failures.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/import_failure_report.dart';

Future<void> _pump(WidgetTester tester, ImportFailureLog log,
    {VoidCallback? onDismiss}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ImportFailureReport(
          log: log,
          provider: 'strava',
          onDismiss: onDismiss ?? () {},
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('names the count and one chip per reason', (tester) async {
    final log = newImportFailureLog();
    recordImportFailure(log,
        name: 'Morning Run', error: const FormatException('Failed to fetch'));
    recordImportFailure(log,
        name: 'Hill repeats', error: const FormatException('Failed to fetch'));
    recordImportFailure(log,
        name: 'Commute',
        error: const FormatException('TCX file contains no track points'));

    await _pump(tester, log);

    expect(find.text("3 activities didn't import"), findsOneWidget);
    expect(find.text('Connection dropped 2'), findsOneWidget);
    expect(find.text('File could not be read 1'), findsOneWidget);
  });

  testWidgets('expanding names each activity, its reason and its detail',
      (tester) async {
    final log = newImportFailureLog();
    recordImportFailure(log,
        name: 'Morning Run',
        startedAt: '2026-03-01T07:00:00Z',
        error: const FormatException('Failed to fetch'));

    await _pump(tester, log);
    expect(find.text('Morning Run'), findsNothing);

    await tester.tap(find.text('Show each activity'));
    await tester.pumpAndSettle();

    expect(find.text('Morning Run'), findsOneWidget);
    // The classified reason and the log-safe detail, not a bare count.
    expect(find.textContaining('Connection dropped'), findsWidgets);
    expect(find.text('Failed to fetch'), findsOneWidget);
  });

  testWidgets('a failure with no start date says so rather than inventing one',
      (tester) async {
    final log = newImportFailureLog();
    recordImportFailure(log, name: 'Row 4', error: 'Malformed row');
    await _pump(tester, log);
    await tester.tap(find.text('Show each activity'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Date unknown'), findsOneWidget);
  });

  testWidgets('the recording cap is stated, and counted in the heading',
      (tester) async {
    final log = newImportFailureLog();
    for (var i = 0; i < kMaxRecordedImportFailures + 3; i++) {
      recordImportFailure(log, name: 'Run $i', error: 'boom');
    }
    await _pump(tester, log);
    expect(find.text("203 activities didn't import"), findsOneWidget);
    expect(find.text('3 further failures were not recorded.'), findsOneWidget);
  });

  testWidgets('dismiss fires the callback', (tester) async {
    final log = newImportFailureLog();
    recordImportFailure(log, name: 'Morning Run', error: 'boom');
    var dismissed = false;
    await _pump(tester, log, onDismiss: () => dismissed = true);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(dismissed, isTrue);
  });
}
