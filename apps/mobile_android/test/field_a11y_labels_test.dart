import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_routine_store.dart';
import '../lib/widgets/routine_builder_sheet.dart';

void main() {
  testWidgets('routine builder text fields expose semantics labels',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('field_a11y');
    final store = LocalRoutineStore();
    await store.init(overrideDirectory: dir);
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RoutineBuilderSheet(store: store)),
      ));
      await tester.pump();

      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>()
          .toSet();

      // The exercise-name field reuses its placeholder key as the field label
      // so a screen reader announces a named edit box, not "edit box".
      expect(labels, contains('Exercise name'));
      // The notes field reuses its section-label key.
      expect(labels, contains('Notes (optional)'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
