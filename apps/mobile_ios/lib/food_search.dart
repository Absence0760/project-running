import 'dart:convert';
import 'dart:io';

/// Food search for nutrition logging — two sources behind one shape.
///
/// Dart twin of `apps/web/src/lib/nutrition/food_search.ts` — keep the parse
/// + portion-scaling behaviour in lockstep. Logging is search -> tap ->
/// confirm portion, never blank macro entry (multi_modal.md § Nutrition).
/// Open Food Facts is free, open-data, no API key (`world.openfoodfacts.org`)
/// and backs the camera barcode fast-path ([lookupBarcode]).
/// USDA FoodData Central is a second source (`api.nal.usda.gov`) and DOES
/// require an API key — it is gated fail-closed: with no key the USDA source
/// is simply absent (OFF still works), no error, no broken UI.
///
/// The HTTP call is isolated behind an injectable [fetcher] (the same seam as
/// `routing.dart`) so the pure parse + scale logic is unit-testable without
/// network.

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

/// Which database a result came from. Drives the source label in the
/// composer and the `<source>:<code>` external_id namespace on logged
/// entries (`off:` / `usda:`).
enum FoodSource { off, usda }

class FoodSearchResult {
  /// Stable id within its source — an Open Food Facts barcode (`off`) or a
  /// USDA FDC id (`usda`). Combined with [source] it forms the
  /// `<source>:<code>` external_id namespace on logged entries.
  final String code;
  final FoodSource source;
  final String name;
  final String? brand;

  /// Macros per 100 g (both sources' canonical basis).
  final double calories100g;
  final double protein100g;
  final double carbs100g;
  final double fat100g;

  const FoodSearchResult({
    required this.code,
    required this.source,
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
const _usdaSearchUrl = 'https://api.nal.usda.gov/fdc/v1/foods/search';

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
      source: FoodSource.off,
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
    source: FoodSource.off,
    name: name,
    brand: brandRaw.isEmpty ? null : brandRaw,
    calories100g: calories,
    protein100g: _num(n['proteins_100g']) ?? 0,
    carbs100g: _num(n['carbohydrates_100g']) ?? 0,
    fat100g: _num(n['fat_100g']) ?? 0,
  );
}

/// USDA FDC nutrient numbers (`nutrientNumber`, the stable identifier) for the
/// four macros we log. Energy in kcal is 208 on legacy/SR-Legacy/Survey rows;
/// some rows additionally carry 957 (Energy, Atwater general). We key only on
/// 208 to match Open Food Facts' kcal basis and never mix kJ in.
const _usdaEnergyKcal = '208';
const _usdaProtein = '203';
const _usdaCarbs = '205';
const _usdaFat = '204';

double? _usdaNutrient(dynamic nutrients, String nutrientNumber) {
  if (nutrients is! List) return null;
  for (final item in nutrients) {
    if (item is! Map) continue;
    // The /v1/foods/search shape flattens the nutrient onto the array item
    // (`nutrientNumber` + `value`), unlike /v1/food/{id} which nests under
    // `nutrient`. Read the flat shape; fall back to the nested one defensively.
    final nested = item['nutrient'];
    final numberRaw =
        item['nutrientNumber'] ?? (nested is Map ? nested['number'] : null);
    final number = numberRaw is String ? numberRaw : '${numberRaw ?? ''}';
    if (number != nutrientNumber) continue;
    final value = item['value'] ?? item['amount'];
    final n = _num(value);
    if (n != null) return n;
  }
  return null;
}

/// Map a raw USDA FoodData Central `/v1/foods/search` response into result
/// shapes. Pure. Drops foods with no description or no calorie figure (the
/// same unloggable-noise filter Open Food Facts gets), so a USDA row slots
/// into the identical confirm-portion flow. USDA macros are already per 100 g.
List<FoodSearchResult> parseUsdaSearch(dynamic json) {
  final foods = (json is Map ? json['foods'] : null);
  if (foods is! List) return const [];
  final out = <FoodSearchResult>[];
  for (final f in foods) {
    if (f is! Map) continue;
    final name = (f['description'] as String?)?.trim() ?? '';
    final fdcId = f['fdcId'];
    final code = fdcId is num
        ? '${fdcId.toInt()}'
        : (fdcId is String ? fdcId : '');
    final calories = _usdaNutrient(f['foodNutrients'], _usdaEnergyKcal);
    if (name.isEmpty || code.isEmpty || calories == null) continue;
    final brandRaw = (f['brandName'] as String?)?.trim() ??
        (f['brandOwner'] as String?)?.trim() ??
        '';
    out.add(FoodSearchResult(
      code: code,
      source: FoodSource.usda,
      name: name,
      brand: brandRaw.isEmpty ? null : brandRaw,
      calories100g: calories,
      protein100g: _usdaNutrient(f['foodNutrients'], _usdaProtein) ?? 0,
      carbs100g: _usdaNutrient(f['foodNutrients'], _usdaCarbs) ?? 0,
      fat100g: _usdaNutrient(f['foodNutrients'], _usdaFat) ?? 0,
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
      throw HttpException('food search ${res.statusCode}', uri: url);
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

/// Search USDA FoodData Central. Returns [] for a blank query OR a blank API
/// key (the fail-closed gate — no key means no USDA source, never an error).
/// Otherwise THROWS on a network / non-2xx / parse failure, mirroring
/// [searchFoods], so the merge caller can tell a failed source apart from an
/// empty one. The key travels as a query param per the FDC API contract.
Future<List<FoodSearchResult>> searchUsda(
  String query,
  String apiKey, {
  FoodFetcher? fetcher,
  int limit = 20,
}) async {
  final q = query.trim();
  if (q.isEmpty || apiKey.trim().isEmpty) return const [];
  final url = Uri.parse(_usdaSearchUrl).replace(queryParameters: {
    'query': q,
    'pageSize': '$limit',
    'api_key': apiKey.trim(),
  });
  final body = await (fetcher ?? _defaultFetcher)(url);
  return parseUsdaSearch(jsonDecode(body));
}

/// Merge results from Open Food Facts and (when a key is provided) USDA into
/// one labelled, deduped list. Each source is queried in parallel; a failure
/// or absence of one source NEVER suppresses the other — a thrown OFF search
/// with a healthy USDA search still returns the USDA rows, and vice versa.
/// Only when BOTH configured sources fail does this throw, so the caller's
/// retry-vs-empty distinction still holds.
///
/// [usdaApiKey] empty/null → USDA is simply not queried (the fail-closed
/// gate). Dedupe is by case-insensitive name+brand, keeping the first
/// occurrence; OFF is listed first so a barcoded branded product wins over the
/// looser USDA generic of the same name.
Future<List<FoodSearchResult>> searchFoodSources(
  String query, {
  FoodFetcher? fetcher,
  String? usdaApiKey,
  int limit = 20,
}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final usdaKey = (usdaApiKey ?? '').trim();

  final tasks = <Future<List<FoodSearchResult>>>[
    searchFoods(q, fetcher: fetcher, limit: limit),
  ];
  if (usdaKey.isNotEmpty) {
    tasks.add(searchUsda(q, usdaKey, fetcher: fetcher, limit: limit));
  }

  // Settle each source independently, preserving the source order (OFF first)
  // regardless of which finishes first — the dedupe keeps the first occurrence,
  // so the order decides the winner.
  final settled = await Future.wait(tasks.map((t) async {
    try {
      return _Settled(value: await t);
    } catch (e) {
      return _Settled(error: e);
    }
  }));

  final fulfilled = settled.where((s) => s.error == null).toList();
  // Every configured source failed → surface the failure (retry, not a
  // misleading empty). A partial failure degrades to the healthy source.
  if (fulfilled.isEmpty) {
    throw settled.first.error ?? Exception('Food search failed');
  }

  final merged = <FoodSearchResult>[];
  for (final s in fulfilled) {
    merged.addAll(s.value!);
  }
  return dedupeFoods(merged);
}

class _Settled {
  final List<FoodSearchResult>? value;
  final Object? error;
  const _Settled({this.value, this.error});
}

/// Drop duplicate foods by case-insensitive name+brand, keeping the first
/// occurrence (so the source order passed in decides the winner). Pure.
List<FoodSearchResult> dedupeFoods(List<FoodSearchResult> results) {
  final seen = <String>{};
  final out = <FoodSearchResult>[];
  for (final r in results) {
    final key =
        '${r.name.trim().toLowerCase()} ${(r.brand ?? '').trim().toLowerCase()}';
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(r);
  }
  return out;
}
