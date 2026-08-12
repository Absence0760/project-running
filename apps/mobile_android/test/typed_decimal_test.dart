import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/typed_decimal.dart';

void main() {
  group('parseTypedDecimal', () {
    test('reads a dot decimal', () {
      expect(parseTypedDecimal('5.2'), 5.2);
      expect(parseTypedDecimal(' 5.2 '), 5.2);
      expect(parseTypedDecimal('0.5'), 0.5);
      expect(parseTypedDecimal('42'), 42);
    });

    test('reads a comma decimal — the de/es/fr/pt keyboard', () {
      expect(parseTypedDecimal('5,2'), 5.2);
      expect(parseTypedDecimal('0,5'), 0.5);
      expect(parseTypedDecimal('72,4'), 72.4);
    });

    test('never turns a comma decimal into a thousandfold value', () {
      // The bug this helper exists for: a filter that drops the comma made
      // "5,2" parse as 52, so a 5.2 km run was saved as 52 km.
      expect(parseTypedDecimal('5,2'), lessThan(10));
    });

    test('the rightmost of two separators is the decimal point', () {
      expect(parseTypedDecimal('1.234,5'), 1234.5);
      expect(parseTypedDecimal('1,234.5'), 1234.5);
    });

    test('a repeated separator can only be grouping', () {
      expect(parseTypedDecimal('1.234.567'), 1234567);
      expect(parseTypedDecimal('1,234,567'), 1234567);
    });

    test('a single separator is the decimal point', () {
      expect(parseTypedDecimal('1,234'), 1.234);
      expect(parseTypedDecimal('1.234'), 1.234);
    });

    test('drops the spaces fr/pt group with', () {
      expect(parseTypedDecimal('1 234,5'), 1234.5);
      expect(parseTypedDecimal('1\u00a0234,5'), 1234.5);
      expect(parseTypedDecimal('1\u202f234,5'), 1234.5);
    });

    test('leading and trailing separators still read', () {
      expect(parseTypedDecimal(',5'), 0.5);
      expect(parseTypedDecimal('.5'), 0.5);
      expect(parseTypedDecimal('5,'), 5);
      expect(parseTypedDecimal('5.'), 5);
    });

    test('keeps the sign', () {
      expect(parseTypedDecimal('-2,5'), -2.5);
    });

    test('rejects what is not a number', () {
      expect(parseTypedDecimal(null), isNull);
      expect(parseTypedDecimal(''), isNull);
      expect(parseTypedDecimal('   '), isNull);
      expect(parseTypedDecimal('abc'), isNull);
      expect(parseTypedDecimal('5 kg'), isNull);
      expect(parseTypedDecimal(','), isNull);
    });

    test('rejects the non-finite literals double.tryParse accepts', () {
      // A caller storing these would write NaN / Infinity into a numeric
      // column; the parser refuses them so no call site has to.
      expect(parseTypedDecimal('NaN'), isNull);
      expect(parseTypedDecimal('Infinity'), isNull);
      expect(parseTypedDecimal('-Infinity'), isNull);
    });
  });

  group('typedDecimalInputFormatters', () {
    test('keeps both separators and drops everything else', () {
      final formatter = typedDecimalInputFormatters.single;
      String filter(String s) => formatter
          .formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length)),
          )
          .text;

      expect(filter('5,2'), '5,2');
      expect(filter('5.2'), '5.2');
      expect(filter('5,2 km'), '5,2');
      expect(filter('-5'), '5');
    });
  });
}
