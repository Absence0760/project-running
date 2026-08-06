// The Preferences page is the one Settings surface that is a single long
// scroll rather than a router into a sub-screen, and its group eyebrows used
// to scroll away with the rows (issue #666 C13). These pin the shape that
// replaced them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show SectionHeader;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

Future<Preferences> _prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pump(
  WidgetTester tester,
  Preferences prefs, {
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(preferences: prefs, settingsSync: null),
    ),
  );
  await tester.pumpAndSettle();
}

/// A viewport tall enough that the whole lazily-built list is laid out, so
/// order can be read off geometry rather than off scroll position.
const _wholePage = Size(400, 8000);

/// Group eyebrows the reader can actually see, top to bottom. A pinned header
/// being pushed out by the next one sits ABOVE the list's top edge, and a
/// sliver in the cache extent is laid out off-screen entirely — neither is
/// naming anybody's group.
List<String> _groupLabels(WidgetTester tester) {
  final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
  final found = <(double, String)>[];
  for (final e in find.byType(SectionHeader).evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.attached) continue;
    final dy = box.localToGlobal(Offset.zero).dy;
    if (dy < top - 0.5) continue;
    found.add((
      dy,
      (e.widget as SectionHeader).label,
    ));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// SectionHeader renders its label uppercased, so match the widget, not text.
Finder _headerNamed(String label) => find.byWidgetPredicate(
      (w) => w is SectionHeader && w.label == label,
    );

/// Rows in the list. A [SwitchListTile] builds a [ListTile], so counting the
/// latter alone counts each row exactly once.
int _rowCount() => find.byType(ListTile).evaluate().length;

void main() {
  setUp(initializeDateFormatting);

  testWidgets('every group is a pinned sliver header, not an inline row',
      (tester) async {
    await _pump(tester, await _prefs(), size: _wholePage);

    final headers = tester
        .widgetList<SliverPersistentHeader>(
          find.byType(SliverPersistentHeader),
        )
        .toList();
    // Assert the population, not only the property (decisions § 534): an
    // empty header set would satisfy `every` vacuously.
    expect(headers.length, greaterThanOrEqualTo(7));
    expect(headers.every((h) => h.pinned), isTrue);
    expect(headers.every((h) => h.delegate is PinnedSectionHeader), isTrue);
  });

  testWidgets('a group is still named after scrolling deep into the page',
      (tester) async {
    await _pump(tester, await _prefs());

    final atTop = _groupLabels(tester);
    expect(atTop, isNotEmpty);

    // Repeated drags: the list is lazily built, so one long fling would
    // outrun the slivers the viewport has inflated.
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    final deep = _groupLabels(tester);
    expect(deep, isNotEmpty,
        reason: 'nothing on screen names the group these rows belong to');
    expect(deep.first, isNot(atTop.first),
        reason: 'the drag did not actually leave the first group');
  });

  testWidgets('the pinned eyebrows do not stack up as you scroll',
      (tester) async {
    await _pump(tester, await _prefs());
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    // A bare pinned header pins against the VIEWPORT, so eight groups would
    // leave eight eyebrows piled at the top by the bottom of the page. Only
    // one group can own the top edge at a time.
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    // Two eyebrows within a row's height of each other is a pile, not a
    // boundary; the shortest real group still puts a row between them.
    final piled = [
      for (final e in find.byType(SectionHeader).evaluate())
        if ((e.renderObject as RenderBox).localToGlobal(Offset.zero).dy - top <
            60)
          (e.widget as SectionHeader).label,
    ];
    expect(_groupLabels(tester), isNotEmpty);
    expect(piled, hasLength(1));
  });

  testWidgets('the spoken-cues eyebrow no longer names the device rows below it',
      (tester) async {
    // Audio cues default on; the sub-group only exists then.
    await _pump(tester, await _prefs(), size: _wholePage);

    expect(_groupLabels(tester), contains('Spoken cues'));

    // "Keep screen on" and its four neighbours are device settings that used
    // to render AFTER the voice-cue eyebrow and so read as voice-cue rows.
    final cueHeader = _headerNamed('Spoken cues');
    expect(cueHeader, findsOneWidget);
    for (final row in ['Keep screen on', 'Advanced GPS', 'Show raw GPS track']) {
      expect(
        tester.getTopLeft(find.text(row)).dy,
        lessThan(tester.getTopLeft(cueHeader).dy),
        reason: '"$row" still sits under the Spoken cues label',
      );
    }
  });

  testWidgets('turning audio cues off drops the voice-cue group entirely',
      (tester) async {
    await _pump(tester, await _prefs(), size: _wholePage);
    final withCues = _rowCount();
    expect(withCues, greaterThan(30));

    await _pump(tester, await _prefs({'audio_cues': false}),
        size: _wholePage);
    expect(_headerNamed('Spoken cues'), findsNothing);
    expect(_rowCount(), lessThan(withCues));
  });
}
