import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/food_search.dart';

const _sample = {
  'products': [
    {
      'code': '111',
      'product_name': 'Rolled Oats',
      'brands': 'Quaker, StoreBrand',
      'nutriments': {
        'energy-kcal_100g': 389,
        'proteins_100g': 16.9,
        'carbohydrates_100g': 66.3,
        'fat_100g': 6.9,
      },
    },
    {
      'code': '222',
      'product_name': 'Mystery Item',
      'nutriments': {'proteins_100g': 5},
    },
    {
      'code': '333',
      'product_name': '   ',
      'nutriments': {'energy-kcal_100g': 100},
    },
  ],
};

void main() {
  test('parseOffSearch maps products and drops unloggable ones', () {
    final out = parseOffSearch(_sample);
    expect(out.length, 1);
    expect(out[0].code, '111');
    expect(out[0].name, 'Rolled Oats');
    expect(out[0].brand, 'Quaker'); // first brand only
    expect(out[0].calories100g, 389);
    expect(out[0].protein100g, 16.9);
  });

  test('parseOffSearch tolerates string-typed nutriment numbers', () {
    final out = parseOffSearch({
      'products': [
        {
          'code': 'c',
          'product_name': 'X',
          'nutriments': {'energy-kcal_100g': '250', 'proteins_100g': '10'},
        },
      ],
    });
    expect(out[0].calories100g, 250);
    expect(out[0].protein100g, 10);
  });

  test('parseOffSearch drops a product whose calorie field is a blank string',
      () {
    // double.tryParse('') is null in Dart (unlike JS Number('') === 0), so the
    // blank-energy products drop and the genuine numeric 0 (water) is kept —
    // parity with the web twin's blank-guard.
    final out = parseOffSearch({
      'products': [
        {
          'code': 'a',
          'product_name': 'Blank Energy',
          'nutriments': {'energy-kcal_100g': ''},
        },
        {
          'code': 'b',
          'product_name': 'Whitespace Energy',
          'nutriments': {'energy-kcal_100g': '   '},
        },
        {
          'code': 'c',
          'product_name': 'Water',
          'nutriments': {'energy-kcal_100g': 0},
        },
      ],
    });
    expect(out.length, 1);
    expect(out[0].code, 'c');
    expect(out[0].calories100g, 0);
  });

  test('parseOffSearch returns [] on malformed input', () {
    expect(parseOffSearch(null), isEmpty);
    expect(parseOffSearch(const {}), isEmpty);
    expect(parseOffSearch(const {'products': 'nope'}), isEmpty);
  });

  test('scalePortion scales per-100g to a gram portion, rounded', () {
    final r = parseOffSearch(_sample)[0];
    final half = scalePortion(r, 50);
    expect(half.calories, 195); // 389 * 0.5 = 194.5 -> 195
    expect(half.proteinG, 8); // 8.45 -> 8
    expect(scalePortion(r, 0).calories, 0);
  });

  test('searchFoods returns [] for an empty query without calling the fetcher',
      () async {
    var called = false;
    final out = await searchFoods('   ', fetcher: (u) async {
      called = true;
      return '{}';
    });
    expect(out, isEmpty);
    expect(called, false);
  });

  test('searchFoods parses a successful response via the injected fetcher',
      () async {
    final out = await searchFoods('oats', fetcher: (u) async {
      expect(u.queryParameters['search_terms'], 'oats');
      return jsonEncode(_sample);
    });
    expect(out.length, 1);
    expect(out[0].name, 'Rolled Oats');
  });

  test('searchFoods returns [] on a throw (manual-entry fallback)', () async {
    final out = await searchFoods('oats', fetcher: (u) async {
      throw Exception('network down');
    });
    expect(out, isEmpty);
  });
}
