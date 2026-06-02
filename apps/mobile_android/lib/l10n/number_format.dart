import 'package:intl/intl.dart';

/// Locale-aware numeric formatting, the sibling of `date_format.dart`. The
/// display path used to call `toStringAsFixed(n)` everywhere, which hard-codes
/// `.` as the decimal separator — a German runner saw `5.21 km` instead of the
/// expected `5,21 km`. These helpers route fixed-fraction-digit formatting
/// through `intl`'s [NumberFormat] keyed by the active locale tag.
///
/// [formatFixed] is the single primitive: fixed fraction digits, **no thousands
/// grouping** (the old `toStringAsFixed` produced none — an elevation of
/// `10000` rendered `"10000"`, not `"10,000"`, and existing en unit-test
/// assertions depend on that). For `en` the output is byte-identical to the old
/// `toStringAsFixed(n)`; only the separator changes for other locales.
///
/// `NumberFormat` construction is non-trivial, and the run screen formats stats
/// per GPS snapshot, so formatters are memoised by `(localeTag, digits)`.

final Map<String, NumberFormat> _fixedFormatters = <String, NumberFormat>{};

/// Format [value] with exactly [digits] fraction digits, no thousands
/// grouping, using the decimal separator of [localeTag]. Drop-in replacement
/// for `value.toStringAsFixed(digits)` on display surfaces.
///
/// Memoised by `(localeTag, digits)` so the hot path doesn't construct a
/// `NumberFormat` per call.
String formatFixed(double value, int digits, String localeTag) {
  final key = '$localeTag/$digits';
  final fmt = _fixedFormatters.putIfAbsent(key, () {
    final f = NumberFormat.decimalPattern(localeTag)
      ..minimumFractionDigits = digits
      ..maximumFractionDigits = digits;
    f.turnOffGrouping();
    return f;
  });
  return fmt.format(value);
}
