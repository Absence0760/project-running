import 'dart:convert';
import 'dart:io';

/// Open Food Facts food search for nutrition logging.
///
/// Dart twin of `apps/web/src/lib/nutrition/food_search.ts` — keep the parse
/// + portion-scaling behaviour in lockstep. Logging is search -> tap ->
/// confirm portion, never blank macro entry (multi_modal.md § Nutrition).
/// Open Food Facts is free, open-data, no API key (`world.openfoodfacts.org`).
///
/// The HTTP call is isolated behind an injectable [fetcher] (the same seam as
/// `routing.dart`) so the pure parse + scale logic is unit-testable without
/// network. Barcode scan is a later v1.1 fast-path on the same lookup.

class FoodMacros {
  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  const FoodMacros({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

class FoodSearchResult {
  /// Open Food Facts barcode — stable id, used for the `off:<code>`
  /// external_id namespace on logged entries.
  final String code;
  final String name;
  final String? brand;

  /// Macros per 100 g (Open Food Facts' canonical basis).
  final double calories100g;
  final double protein100g;
  final double carbs100g;
  final double fat100g;

  const FoodSearchResult({
    required this.code,
    required this.name,
    required this.brand,
    required this.calories100g,
    required this.protein100g,
    required this.carbs100g,
    required this.fat100g,
  });
}

typedef FoodFetcher = Future<String> Function(Uri url);

const _searchUrl = 'https://world.openfoodfacts.org/cgi/search.pl';

double? _num(dynamic v) {
  final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
  if (n == null || !n.isFinite || n < 0) return null;
  return n;
}

/// Map a raw Open Food Facts search response into result shapes. Pure.
/// Drops products with no name or no calorie figure (unloggable noise).
List<FoodSearchResult> parseOffSearch(dynamic json) {
  final products = (json is Map ? json['products'] : null);
  if (products is! List) return const [];
  final out = <FoodSearchResult>[];
  for (final p in products) {
    if (p is! Map) continue;
    final name = (p['product_name'] as String?)?.trim() ?? '';
    final code = p['code'] as String?;
    final nutr = p['nutriments'];
    final n = nutr is Map ? nutr : const {};
    final calories = _num(n['energy-kcal_100g']);
    if (name.isEmpty || code == null || code.isEmpty || calories == null) {
      continue;
    }
    final brandRaw = (p['brands'] as String?)?.split(',').first.trim() ?? '';
    out.add(FoodSearchResult(
      code: code,
      name: name,
      brand: brandRaw.isEmpty ? null : brandRaw,
      calories100g: calories,
      protein100g: _num(n['proteins_100g']) ?? 0,
      carbs100g: _num(n['carbohydrates_100g']) ?? 0,
      fat100g: _num(n['fat_100g']) ?? 0,
    ));
  }
  return out;
}

/// Scale a per-100 g result to a portion in grams, rounded to whole units.
FoodMacros scalePortion(FoodSearchResult r, double grams) {
  final f = grams > 0 ? grams / 100 : 0;
  return FoodMacros(
    calories: (r.calories100g * f).round(),
    proteinG: (r.protein100g * f).round(),
    carbsG: (r.carbs100g * f).round(),
    fatG: (r.fat100g * f).round(),
  );
}

Future<String> _defaultFetcher(Uri url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw HttpException('OFF ${res.statusCode}', uri: url);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

/// Search Open Food Facts. Returns [] on a network/parse failure (the caller
/// falls back to manual entry — logging never blocks on the API being up).
Future<List<FoodSearchResult>> searchFoods(
  String query, {
  FoodFetcher? fetcher,
  int limit = 20,
}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final url = Uri.parse(_searchUrl).replace(queryParameters: {
    'search_terms': q,
    'search_simple': '1',
    'action': 'process',
    'json': '1',
    'page_size': '$limit',
    'fields': 'code,product_name,brands,nutriments',
  });
  try {
    final body = await (fetcher ?? _defaultFetcher)(url);
    return parseOffSearch(jsonDecode(body));
  } catch (_) {
    return const [];
  }
}
