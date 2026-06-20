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
const _productUrl = 'https://world.openfoodfacts.org/api/v2/product';

/// Keep only the digits of a scanned EAN/UPC. A barcode scanner can hand back
/// a trailing newline or a symbology label; Open Food Facts keys products by
/// the bare digit string. Returns null when nothing usable remains.
String? normaliseBarcode(String raw) {
  final digits = raw.replaceAll(RegExp('[^0-9]'), '');
  return digits.isEmpty ? null : digits;
}

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

/// Map a raw Open Food Facts `/api/v2/product/{barcode}` response into a
/// single result. Pure. The product-by-barcode endpoint returns
/// `{status, product}` (one object, not the `products` array the search
/// endpoint returns), so it can't reuse [parseOffSearch]. Returns null when
/// the product is missing (`status != 1`) or unloggable (no name / no calorie
/// figure) — the caller treats null as "no match, fall back to search".
FoodSearchResult? parseOffProduct(dynamic json) {
  final map = json is Map ? json : null;
  if (map == null || map['status'] != 1) return null;
  final p = map['product'];
  if (p is! Map) return null;
  final name = (p['product_name'] as String?)?.trim() ?? '';
  final code = p['code'] as String?;
  final nutr = p['nutriments'];
  final n = nutr is Map ? nutr : const {};
  final calories = _num(n['energy-kcal_100g']);
  if (name.isEmpty || code == null || code.isEmpty || calories == null) {
    return null;
  }
  final brandRaw = (p['brands'] as String?)?.split(',').first.trim() ?? '';
  return FoodSearchResult(
    code: code,
    name: name,
    brand: brandRaw.isEmpty ? null : brandRaw,
    calories100g: calories,
    protein100g: _num(n['proteins_100g']) ?? 0,
    carbs100g: _num(n['carbohydrates_100g']) ?? 0,
    fat100g: _num(n['fat_100g']) ?? 0,
  );
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

/// Search Open Food Facts. Returns [] only for a genuinely empty result
/// set; THROWS on a network / non-2xx / parse failure so the caller can
/// tell "no matches" apart from "search failed" and offer a retry instead
/// of a misleading empty state. (An empty query short-circuits to [].)
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
  final body = await (fetcher ?? _defaultFetcher)(url);
  return parseOffSearch(jsonDecode(body));
}

/// Look up a single product by scanned EAN/UPC barcode (the v1.1 camera
/// fast-path on the same Open Food Facts lookup). Returns null for a blank /
/// non-numeric code or a genuine no-match (`status != 1` / unloggable
/// product); THROWS on a network / non-2xx / parse failure so the caller can
/// tell "not in the database" apart from "lookup failed" and fall back to
/// manual search in either case while surfacing a distinct failure message.
Future<FoodSearchResult?> lookupBarcode(
  String barcode, {
  FoodFetcher? fetcher,
}) async {
  final code = normaliseBarcode(barcode);
  if (code == null) return null;
  final url = Uri.parse('$_productUrl/$code.json').replace(queryParameters: {
    'fields': 'code,product_name,brands,nutriments',
  });
  final body = await (fetcher ?? _defaultFetcher)(url);
  return parseOffProduct(jsonDecode(body));
}
