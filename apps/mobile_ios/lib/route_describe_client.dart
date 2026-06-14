import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'route_description.dart';

/// Network glue for the route-detail "Describe this route" affordance.
///
/// The pure, locale/unit-aware templated baseline is built in the screen
/// from [describeRoute]'s parts; this module is the part that needs the
/// Supabase session + an HTTP POST to the Pro-gated enhancement endpoint.
/// It resolves to `{ description, source, upgrade }`, refreshing the JWT
/// once on a 401, mirroring CoachChat. The endpoint itself degrades to
/// the templated text on every failure, so a 200 with `source:'template'`
/// is the normal not-Pro / fallback shape; callers only treat a non-200
/// (or a thrown request) as a hard error and keep the locally-rendered
/// baseline.
///
/// Twin of `apps/web/src/lib/routes/route_describe_client.ts` — keep the
/// request body shape, the single 401 refresh-and-replay, and the
/// `source`/`upgrade` parsing in lockstep.

class AiDescriptionResult {
  final String description;

  /// 'ai' when the model produced it, 'template' on any server fallback.
  final String source;

  /// True when the server declined because the caller isn't Pro.
  final bool upgrade;

  const AiDescriptionResult({
    required this.description,
    required this.source,
    required this.upgrade,
  });
}

Map<String, dynamic> _toBody(RouteDescriptionInput input) => {
      'name': input.name,
      'distance_m': input.distanceM,
      'elevation_m': input.elevationM,
      'surface': input.surface,
      'start': input.start == null
          ? null
          : {'lat': input.start!.lat, 'lng': input.start!.lng},
      'end': input.end == null
          ? null
          : {'lat': input.end!.lat, 'lng': input.end!.lng},
    };

/// Request an AI-enhanced description. Throws only on a non-200 response
/// or a request failure — a 200 with `source:'template'` (not-Pro, or the
/// server's own fallback) is a normal, non-throwing result.
Future<AiDescriptionResult> requestAiDescription(
    RouteDescriptionInput input) async {
  final body = jsonEncode(_toBody(input));
  final base = (dotenv.env['WEB_BASE_URL'] ?? 'https://threkir.com')
      .replaceAll(RegExp(r'/$'), '');
  final uri = Uri.parse('$base/api/coach/route-describe');

  String? token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) throw StateError('not_authenticated');

  // Each call uses a fresh HttpClient so a redirect / error leaves no
  // half-open connection. Production Lambda reads
  // `x-supabase-authorization` only (CloudFront's OAC sigv4-signs the
  // `Authorization` header), matching the coach path.
  Future<HttpClientResponse> postWith(String t) async {
    final c = HttpClient();
    try {
      final r = await c.postUrl(uri);
      r.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      r.headers.set('x-supabase-authorization', 'Bearer $t');
      r.add(utf8.encode(body));
      return await r.close();
    } catch (_) {
      c.close(force: true);
      rethrow;
    }
  }

  var res = await postWith(token);
  if (res.statusCode == 401) {
    try {
      final refreshed =
          await Supabase.instance.client.auth.refreshSession();
      final newToken = refreshed.session?.accessToken;
      if (newToken != null) {
        token = newToken;
        res = await postWith(newToken);
      }
    } catch (e) {
      debugPrint('route_describe_client: refreshSession failed: $e');
    }
  }

  final raw = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    throw StateError('route_describe_failed_${res.statusCode}');
  }
  Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    throw StateError('route_describe_malformed');
  }
  final description = json['description'];
  if (description is! String) {
    throw StateError('route_describe_malformed');
  }
  return AiDescriptionResult(
    description: description,
    source: json['source'] == 'ai' ? 'ai' : 'template',
    upgrade: json['upgrade'] == true,
  );
}
