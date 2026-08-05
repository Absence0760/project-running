import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// The type scale `font_size_literal_guard_test.dart` sends every call site to.
///
/// §482 declared `labelSmall` the 11 px micro-label floor and left the rest of
/// the scale to Material 3's own steps. That makes the set of legal sizes an
/// emergent fact rather than a written one, and the sweep that removed 27
/// `fontSize:` literals chose a step per site against it — so it is pinned here,
/// in both brightnesses, along with the derived properties that sweep relied on.
///
/// Every assertion runs inside a pumped tree on purpose. `ThemeData.textTheme`
/// read straight off `AppTheme.light` carries **no geometry at all** — only the
/// one step §482 overrides has a size, because Material applies the locale's
/// geometry in `ThemeData.localize` at build time. A scale test that reads the
/// getter directly therefore compares nulls and passes for the wrong reason.
///
/// The **ambient** defaults matter as much as the steps. Where a literal was
/// simply deleted, what supplies the size afterwards is the `DefaultTextStyle`
/// that `Material` installs, or the widget's own default (`TextField`,
/// `CircleAvatar`, `Chip`). Those are Flutter's values, not ours: a framework
/// upgrade that moves one of them silently resizes those sites, and this is
/// where that shows up.

/// Every step's size, keyed by the name a call site writes.
Map<String, double?> _sizes(TextTheme t) =>
    {for (final e in _named(t).entries) e.key: e.value?.fontSize};

Map<String, TextStyle?> _named(TextTheme t) => {
      'labelSmall': t.labelSmall,
      'labelMedium': t.labelMedium,
      'labelLarge': t.labelLarge,
      'bodySmall': t.bodySmall,
      'bodyMedium': t.bodyMedium,
      'bodyLarge': t.bodyLarge,
      'titleSmall': t.titleSmall,
      'titleMedium': t.titleMedium,
      'titleLarge': t.titleLarge,
      'headlineSmall': t.headlineSmall,
    };

/// Pumps [theme] and hands back the resolved `ThemeData` from inside the tree.
Future<ThemeData> _resolved(WidgetTester tester, ThemeData theme) async {
  late ThemeData resolved;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Builder(builder: (c) {
      resolved = Theme.of(c);
      return const SizedBox.shrink();
    }),
  ));
  return resolved;
}

void main() {
  for (final (name, base) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('$name resolves the declared steps', (tester) async {
      final theme = await _resolved(tester, base);
      expect(_sizes(theme.textTheme), {
        'labelSmall': 11.0,
        'labelMedium': 12.0,
        'labelLarge': 14.0,
        'bodySmall': 12.0,
        'bodyMedium': 14.0,
        'bodyLarge': 16.0,
        'titleSmall': 14.0,
        'titleMedium': 16.0,
        'titleLarge': 22.0,
        'headlineSmall': 24.0,
      });
    });

    testWidgets('$name has no step below the 11 px floor', (tester) async {
      final theme = await _resolved(tester, base);
      final below = _sizes(theme.textTheme)
          .entries
          .where((e) => (e.value ?? 99) < 11)
          .map((e) => '${e.key}=${e.value}')
          .toList();
      expect(below, isEmpty,
          reason: '§482 pins 11 px as the micro-label floor; a step under it '
              'would make the floor unreachable through the scale.');
    });

    // Why this is load-bearing: naming a step (`theme.textTheme.bodySmall`)
    // REPLACES the ambient style rather than merging into it, because the M3
    // geometry styles are `inherit: false`. That is only safe because every
    // step already carries `onSurface`. If a step's colour ever diverged, the
    // sweep's `style: theme.textTheme.<step>` sites would silently repaint.
    testWidgets('$name gives every step onSurface, non-inheriting',
        (tester) async {
      final theme = await _resolved(tester, base);
      final wrong = <String>[];
      _named(theme.textTheme).forEach((key, style) {
        if (style!.color != theme.colorScheme.onSurface) {
          wrong.add('$key colour is ${style.color}, '
              'not ${theme.colorScheme.onSurface}');
        }
        if (style.inherit) wrong.add('$key inherits');
      });
      expect(wrong, isEmpty, reason: wrong.join('; '));
    });
  }

  testWidgets('Material supplies bodyMedium as the ambient size', (t) async {
    late TextStyle ambient;
    late ThemeData theme;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Card(
          child: Builder(builder: (c) {
            ambient = DefaultTextStyle.of(c).style;
            theme = Theme.of(c);
            return const Text('x');
          }),
        ),
      ),
    ));
    expect(ambient.fontSize, theme.textTheme.bodyMedium?.fontSize);
  });

  testWidgets('the widget defaults the sweep leaned on', (t) async {
    late TextStyle avatar;
    late TextStyle chip;
    late ThemeData theme;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(builder: (outer) {
          theme = Theme.of(outer);
          return Column(children: [
            const TextField(
              key: Key('f'),
              decoration: InputDecoration(hintText: 'h'),
            ),
            CircleAvatar(
              child: Builder(builder: (c) {
                avatar = DefaultTextStyle.of(c).style;
                return const Text('A');
              }),
            ),
            Chip(
              label: Builder(builder: (c) {
                chip = DefaultTextStyle.of(c).style;
                return const Text('c');
              }),
            ),
          ]);
        }),
      ),
    ));
    final field = t
        .widget<EditableText>(find.descendant(
          of: find.byKey(const Key('f')),
          matching: find.byType(EditableText),
        ))
        .style;

    // A `TextField` whose per-site `style:` was deleted lands on `bodyLarge`,
    // a `CircleAvatar`'s initial on `titleMedium`. Each is the step a deleted
    // literal now resolves through.
    expect(field.fontSize, theme.textTheme.bodyLarge?.fontSize);
    expect(avatar.fontSize, theme.textTheme.titleMedium?.fontSize);

    // A `Chip` is the exception, and it is why the tag chip names a step
    // explicitly instead of deleting its style. `RawChip` resolves
    // `chipTheme.labelStyle ?? chipDefaults.labelStyle` — an OR, not a merge —
    // so §482's `labelStyle`, which exists only to carry the selected/
    // unselected `WidgetStateColor`, displaces M3's `labelLarge` entirely and
    // leaves the label with no size of its own. It falls through to the
    // ambient step, which is the same 14 by coincidence and not by design.
    expect(chip.fontSize, isNull);
  });
}
