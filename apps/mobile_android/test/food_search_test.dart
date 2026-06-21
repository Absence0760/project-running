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

const _usdaSample = {
  'foods': [
    {
      'fdcId': 555,
      'description': 'Oats, raw',
      'brandName': 'Generic',
      'foodNutrients': [
        {'nutrientNumber': '208', 'value': 389},
        {'nutrientNumber': '203', 'value': 16.9},
        {'nutrientNumber': '205', 'value': 66.3},
        {'nutrientNumber': '204', 'value': 6.9},
      ],
    },
    {
      'fdcId': 666,
      'description': 'Mystery Powder',
      'foodNutrients': [
        {'nutrientNumber': '203', 'value': 5},
      ],
    },
    {
      'fdcId': 777,
      'description': '   ',
      'foodNutrients': [
        {'nutrientNumber': '208', 'value': 100},
      ],
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
    expect(out[0].source, FoodSource.off);
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

  test('searchFoods rethrows a fetch failure (so the caller can show retry, not empty)',
      () async {
    expect(
      () => searchFoods('oats', fetcher: (u) async {
        throw Exception('network down');
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('searchFoods on valid-but-empty JSON is genuinely empty (returns [])',
      () async {
    final out = await searchFoods('oats', fetcher: (u) async => '{"products": []}');
    expect(out, isEmpty);
  });

  const product = {
    'status': 1,
    'product': {
      'code': '737628064502',
      'product_name': 'Rolled Oats',
      'brands': 'Quaker, StoreBrand',
      'nutriments': {
        'energy-kcal_100g': 389,
        'proteins_100g': 16.9,
        'carbohydrates_100g': 66.3,
        'fat_100g': 6.9,
      },
    },
  };

  test('normaliseBarcode strips non-digits and rejects empty', () {
    expect(normaliseBarcode(' 737628064502\n'), '737628064502');
    expect(normaliseBarcode('EAN 4006381333931'), '4006381333931');
    expect(normaliseBarcode('abc'), isNull);
    expect(normaliseBarcode(''), isNull);
  });

  test('parseOffProduct maps a found product', () {
    final r = parseOffProduct(product);
    expect(r, isNotNull);
    expect(r!.code, '737628064502');
    expect(r.name, 'Rolled Oats');
    expect(r.brand, 'Quaker');
    expect(r.calories100g, 389);
    expect(r.carbs100g, 66.3);
  });

  test('parseOffProduct returns null for a missing product or unloggable one',
      () {
    expect(parseOffProduct({'status': 0, 'product': const {}}), isNull);
    expect(parseOffProduct(null), isNull);
    expect(
      parseOffProduct({
        'status': 1,
        'product': {'code': 'x', 'product_name': 'No Energy', 'nutriments': const {}},
      }),
      isNull,
    );
  });

  test(
      'lookupBarcode returns null for a blank/non-numeric code without calling the fetcher',
      () async {
    var called = false;
    final out = await lookupBarcode('  ', fetcher: (u) async {
      called = true;
      return '{}';
    });
    expect(out, isNull);
    expect(called, false);
  });

  test('lookupBarcode parses a found product via the injected fetcher',
      () async {
    final r = await lookupBarcode('737628064502', fetcher: (u) async {
      expect(u.path, contains('/api/v2/product/737628064502.json'));
      return jsonEncode(product);
    });
    expect(r, isNotNull);
    expect(r!.name, 'Rolled Oats');
  });

  test('lookupBarcode returns null on a genuine no-match (status 0)', () async {
    final r = await lookupBarcode('000000000000',
        fetcher: (u) async => '{"status": 0}');
    expect(r, isNull);
  });

  test(
      'lookupBarcode rethrows a fetch failure (failure is distinct from no-match)',
      () async {
    expect(
      () => lookupBarcode('737628064502', fetcher: (u) async {
        throw Exception('network down');
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('parseUsdaSearch maps foods and drops unloggable ones', () {
    final out = parseUsdaSearch(_usdaSample);
    expect(out.length, 1);
    expect(out[0].code, '555'); // numeric fdcId stringified
    expect(out[0].source, FoodSource.usda);
    expect(out[0].name, 'Oats, raw');
    expect(out[0].brand, 'Generic');
    expect(out[0].calories100g, 389);
    expect(out[0].protein100g, 16.9);
    expect(out[0].carbs100g, 66.3);
    expect(out[0].fat100g, 6.9);
  });

  test('parseUsdaSearch tolerates the nested nutrient shape + string fdcId + brandOwner fallback',
      () {
    final out = parseUsdaSearch({
      'foods': [
        {
          'fdcId': 'abc',
          'description': 'Nested Food',
          'brandOwner': 'Acme',
          'foodNutrients': [
            {
              'nutrient': {'number': '208'},
              'amount': 250,
            },
            {
              'nutrient': {'number': '203'},
              'amount': 10,
            },
          ],
        },
      ],
    });
    expect(out[0].code, 'abc');
    expect(out[0].brand, 'Acme');
    expect(out[0].calories100g, 250);
    expect(out[0].protein100g, 10);
  });

  test('parseUsdaSearch ignores a non-208 energy nutrient (never mixes kJ in)',
      () {
    final out = parseUsdaSearch({
      'foods': [
        {
          'fdcId': 1,
          'description': 'KJ Only',
          // 268 = Energy in kJ; without a 208 row this food is unloggable
          'foodNutrients': [
            {'nutrientNumber': '268', 'value': 1600},
          ],
        },
      ],
    });
    expect(out, isEmpty);
  });

  test('parseUsdaSearch returns [] on malformed input', () {
    expect(parseUsdaSearch(null), isEmpty);
    expect(parseUsdaSearch(const {}), isEmpty);
    expect(parseUsdaSearch(const {'foods': 'nope'}), isEmpty);
  });

  test('searchUsda short-circuits to [] when the API key is blank (fail-closed gate)',
      () async {
    var called = false;
    Future<String> fetcher(Uri u) async {
      called = true;
      return '{}';
    }

    expect(await searchUsda('oats', '', fetcher: fetcher), isEmpty);
    expect(await searchUsda('oats', '   ', fetcher: fetcher), isEmpty);
    expect(called, false);
  });

  test('searchUsda parses a successful response + sends the key as a query param',
      () async {
    final out = await searchUsda('oats', 'SECRET', fetcher: (u) async {
      expect(u.queryParameters['query'], 'oats');
      expect(u.queryParameters['api_key'], 'SECRET');
      return jsonEncode(_usdaSample);
    });
    expect(out.length, 1);
    expect(out[0].source, FoodSource.usda);
  });

  test('searchUsda rethrows a fetch failure', () async {
    expect(
      () => searchUsda('oats', 'SECRET', fetcher: (u) async {
        throw Exception('forbidden');
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('searchFoodSources queries OFF only when no USDA key is set', () async {
    final urls = <Uri>[];
    final out = await searchFoodSources('oats', fetcher: (u) async {
      urls.add(u);
      return jsonEncode(_sample);
    });
    expect(urls.length, 1);
    expect(urls[0].toString(), contains('openfoodfacts'));
    expect(out.length, 1);
    expect(out[0].source, FoodSource.off);
  });

  test('searchFoodSources merges both sources, OFF first, when a USDA key is set',
      () async {
    final out = await searchFoodSources(
      'oats',
      usdaApiKey: 'SECRET',
      fetcher: (u) async => u.toString().contains('usda')
          ? jsonEncode(_usdaSample)
          : jsonEncode(_sample),
    );
    expect(out.length, 2);
    expect(out[0].source, FoodSource.off); // OFF listed first
    expect(out[1].source, FoodSource.usda);
  });

  test('searchFoodSources degrades to the healthy source when one fails',
      () async {
    final out = await searchFoodSources(
      'oats',
      usdaApiKey: 'SECRET',
      fetcher: (u) async {
        if (u.toString().contains('usda')) return jsonEncode(_usdaSample);
        throw Exception('OFF down');
      },
    );
    expect(out.length, 1);
    expect(out[0].source, FoodSource.usda); // OFF failure didn't suppress USDA
  });

  test('searchFoodSources throws only when every configured source fails',
      () async {
    expect(
      () => searchFoodSources(
        'oats',
        usdaApiKey: 'SECRET',
        fetcher: (u) async => throw Exception('all down'),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('dedupeFoods drops case-insensitive name+brand dupes, keeping the first',
      () {
    const off = FoodSearchResult(
      code: '1',
      source: FoodSource.off,
      name: 'Rolled Oats',
      brand: 'Quaker',
      calories100g: 389,
      protein100g: 16,
      carbs100g: 66,
      fat100g: 7,
    );
    const usdaDupe = FoodSearchResult(
      code: '2',
      source: FoodSource.usda,
      name: 'rolled oats',
      brand: 'quaker',
      calories100g: 380,
      protein100g: 15,
      carbs100g: 65,
      fat100g: 6,
    );
    const distinct = FoodSearchResult(
      code: '3',
      source: FoodSource.usda,
      name: 'Steel Cut Oats',
      brand: 'quaker',
      calories100g: 380,
      protein100g: 15,
      carbs100g: 65,
      fat100g: 6,
    );
    final out = dedupeFoods([off, usdaDupe, distinct]);
    expect(out.length, 2);
    expect(out[0].code, '1'); // OFF kept (first wins)
    expect(out[1].code, '3');
  });
}
