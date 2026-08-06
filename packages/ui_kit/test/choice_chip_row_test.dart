import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// These assert the DERIVATION, never an absolute fit: CI cannot render the
/// device's font, and `flutter_test`'s default is fixed-advance — one em per
/// glyph, 2-6x wider than real Roboto (decisions § 500). Every claim below is
/// therefore made under a font strictly wider than the shipping one, so it
/// holds a fortiori on a real device.

Future<double> _pump(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required List<String> labels,
  List<IconData?> icons = const [],
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ChoiceChipRow<int>(
              options: [
                for (var i = 0; i < labels.length; i++)
                  ChoiceChipOption(
                    value: i,
                    label: labels[i],
                    icon: i < icons.length ? icons[i] : null,
                  ),
              ],
              selected: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return tester.getSize(find.byType(ChoiceChipRow<int>)).height;
}

void main() {
  test('an option carries its own already-localized label', () {
    const option = ChoiceChipOption<int>(value: 1, label: 'Semaine');
    expect(option.label, 'Semaine');
    expect(option.icon, isNull);
  });

  testWidgets(
      'a squeezed row never divides its width between the options — each '
      'chip keeps the width its own label asks for', (tester) async {
    // The labels that lost characters under SegmentedButton, in the locales
    // that lost them. Their absolute widths are not asserted (the test font is
    // fixed-advance, § 500) — the viewport below is DERIVED from what this
    // font actually produced, so the property holds in any font.
    const labels = ['Cette semaine', 'Diesen Monat', 'Transcurrido'];
    await _pump(tester, width: 4000, textScale: 1.0, labels: labels);
    final unbounded = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => tester.getSize(find.byWidget(c)).width)
        .toList();
    expect(unbounded, hasLength(labels.length));

    // Wide enough for the fattest chip and nothing more, so a control that
    // shares width out would give every option a third of this.
    final squeezed = unbounded.reduce((a, b) => a > b ? a : b) + 8;
    await _pump(tester, width: squeezed, textScale: 1.0, labels: labels);
    final constrained = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => tester.getSize(find.byWidget(c)).width)
        .toList();
    for (var i = 0; i < labels.length; i++) {
      expect(constrained[i], closeTo(unbounded[i], 0.5),
          reason: '"${labels[i]}" was resized by the row');
    }
  });

  testWidgets('a row that no longer fits gains runs rather than losing width',
      (tester) async {
    const labels = ['Cette semaine', 'Diesen Monat', 'Transcurrido'];
    final wide = await _pump(tester, width: 4000, textScale: 1.0, labels: labels);
    final chipWidth = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => tester.getSize(find.byWidget(c)).width)
        .reduce((a, b) => a > b ? a : b);
    final narrow =
        await _pump(tester, width: chipWidth + 8, textScale: 1.0, labels: labels);
    expect(narrow, greaterThan(wide),
        reason: 'the constrained row must gain runs, not lose characters');
  });

  testWidgets('one run lays out as a single line, so the common case is '
      'unchanged', (tester) async {
    final single = await _pump(
        tester, width: 1200, textScale: 1.0, labels: ['A', 'B']);
    final alsoSingle = await _pump(
        tester, width: 1200, textScale: 1.0, labels: ['A', 'B', 'C', 'D']);
    expect(alsoSingle, single);
  });

  testWidgets('selection is not colour alone: the selected chip shows a '
      'checkmark', (tester) async {
    await _pump(tester, width: 400, textScale: 1.0, labels: ['One', 'Two']);
    final chips =
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
    expect(chips, hasLength(2));
    expect(chips[0].selected, isTrue);
    expect(chips[1].selected, isFalse);
    // showCheckmark is left at Material's default (true) rather than switched
    // off for width, which is what the SegmentedButton sites had been doing.
    expect(chips[0].showCheckmark, isNull);
  });

  testWidgets('a leading icon rides in the avatar slot', (tester) async {
    await _pump(tester,
        width: 400,
        textScale: 1.0,
        labels: ['Shoes', 'Bikes'],
        icons: [Icons.directions_run, Icons.directions_bike]);
    expect(find.byIcon(Icons.directions_bike), findsOneWidget);
  });

  testWidgets(
      'the control it replaces fails the same property, which is why it was '
      'replaced', (tester) async {
    // Not a guard on shipped code — SegmentedButton is banned from `lib` by
    // `segmented_button_guard_test.dart`. This proves the property above
    // discriminates: given the same options and the same derived width, the
    // segmented control shares the width out and truncates.
    const labels = ['Cette semaine', 'Diesen Monat', 'Transcurrido'];
    Widget app(double width) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < labels.length; i++)
                      ButtonSegment(value: i, label: Text(labels[i])),
                  ],
                  selected: const {0},
                  onSelectionChanged: (_) {},
                ),
              ),
            ),
          ),
        );
    Map<String, double> labelWidths() {
      final out = <String, double>{};
      void walk(RenderObject o) {
        if (o is RenderParagraph) {
          final text = o.text.toPlainText();
          if (labels.contains(text)) out[text] = o.size.width;
        }
        o.visitChildren(walk);
      }

      walk(tester.renderObject(find.byType(SegmentedButton<int>)));
      return out;
    }

    await tester.pumpWidget(app(4000));
    final unbounded = labelWidths();
    final full = tester.getSize(find.byType(SegmentedButton<int>)).width;
    expect(unbounded, hasLength(labels.length));

    await tester.pumpWidget(app(full / 2));
    final constrained = labelWidths();
    expect(constrained, hasLength(labels.length));
    // Every label lost width to the container — the defect a chip cannot have,
    // because a chip is sized by its label rather than by its share of a row.
    for (final label in labels) {
      expect(constrained[label]!, lessThan(unbounded[label]!),
          reason: '"$label" kept its width, so this control no longer '
              'demonstrates the failure the row was built to avoid');
    }
  });

  testWidgets('tapping an option reports its value', (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ChoiceChipRow<int>(
          options: const [
            ChoiceChipOption(value: 1, label: 'One'),
            ChoiceChipOption(value: 2, label: 'Two'),
          ],
          selected: 1,
          onChanged: (v) => picked = v,
        ),
      ),
    ));
    await tester.tap(find.text('Two'));
    expect(picked, 2);
  });
}
