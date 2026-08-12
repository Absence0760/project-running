import 'package:flutter/services.dart';

/// Parses a number the user typed, accepting either decimal separator.
///
/// Five of the seven shipped locales (de, es, fr, pt, pt_BR) put a comma on
/// the decimal key and `double.tryParse` only understands a dot, so a typed
/// "5,2" is lost twice over: behind a `[0-9.]` input filter the comma is
/// deleted outright and 5.2 km is saved as a 52 km run, and without one the
/// parse returns null and the value is silently dropped.
///
/// A grouping separator is tolerated the way a reader would resolve it: when
/// both separators appear the rightmost is the decimal point ("1.234,5" and
/// "1,234.5" are the same number), and a separator that repeats can only be
/// grouping. A single separator is always read as the decimal point, so
/// "1,234" is 1.234 — the reading that keeps a mistyped weight or distance
/// small rather than inflating it by a thousand.
double? parseTypedDecimal(String? raw) {
  if (raw == null) return null;
  // \s spans the no-break spaces fr/pt group thousands with, not just ' '.
  final s = raw.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return null;

  final commas = ','.allMatches(s).length;
  final dots = '.'.allMatches(s).length;
  var normalised = s;
  if (commas > 0 && dots > 0) {
    final grouping = s.lastIndexOf(',') > s.lastIndexOf('.') ? '.' : ',';
    normalised = s.replaceAll(grouping, '');
  } else if (commas > 1 || dots > 1) {
    normalised = s.replaceAll(commas > 1 ? ',' : '.', '');
  }

  final v = double.tryParse(normalised.replaceAll(',', '.'));
  // double.tryParse also accepts "NaN" and "Infinity"; neither is a number a
  // caller can store, so they fail here rather than in each call site.
  if (v == null || !v.isFinite) return null;
  return v;
}

/// Input filter for a field [parseTypedDecimal] reads: both separators
/// survive, because filtering the comma out rewrites "5,2" as 52 before the
/// parser ever sees it.
final typedDecimalInputFormatters = List<TextInputFormatter>.unmodifiable(
  [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
);
