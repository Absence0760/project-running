/// Pins the degrade-don't-throw contract on the two `SocialService`
/// methods whose `catch` is the entire point of the method.
///
/// `searchClubs` wraps the `search_clubs` RPC *and* the `_enrichClubs`
/// follow-up reads in one try whose catch falls back to the plain ILIKE
/// `browseClubs`, so a club search degrades instead of surfacing a red
/// error toast. Returning `_enrichClubs(rows)` bare put those follow-up
/// reads outside the try: the RPC-failure branch worked, but an
/// enrichment failure escaped to the caller and the fallback never ran
/// at all. Dart 3.13's `unawaited_return_in_try_block` is what surfaced
/// it; the dead fallback is why it mattered.
///
/// The fixture is a loopback PostgREST stand-in rather than the live
/// stack `services_integration_test.dart` drives, because the bug turns
/// on failing the enrichment reads *independently of* the RPC — a
/// distinction a real server can't be asked for.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/social_service.dart';

Map<String, dynamic> _clubJson(String id) => <String, dynamic>{
      'id': id,
      'owner_id': 'owner-1',
      'name': 'Club $id',
      'slug': id,
      'description': null,
      'avatar_url': null,
      'location_label': null,
      'is_public': true,
      'is_verified': false,
      'join_policy': 'open',
      'member_count': 3,
      'website_url': null,
      'instagram_url': null,
      'strava_url': null,
      'facebook_url': null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': null,
    };

/// Minimal PostgREST stand-in: enough routing to tell the RPC, the
/// enrichment reads, the ILIKE browse and the single-row lookups apart,
/// and to fail any one of them on demand. A null payload means "500".
class _FakePostgrest {
  _FakePostgrest(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakePostgrest> start() async =>
      _FakePostgrest(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  List<Map<String, dynamic>>? rpcRows = const [];
  List<Map<String, dynamic>> browseRows = const [];
  Map<String, dynamic>? eventRow = const {};
  bool failClubLookup = false;

  /// Fail only the first `club_members` read — the one enriching the RPC
  /// result — so the fallback's own enrichment still succeeds and the
  /// test can assert on the rows it returns.
  bool failFirstEnrichment = false;

  int enrichmentReads = 0;

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    await req.drain<void>();
    final res = req.response..headers.contentType = ContentType.json;
    // `.maybeSingle()` asks for a bare object; every other read wants an
    // array. Both shapes share a path, so the Accept header is the only
    // thing that separates them.
    final wantsObject = (req.headers.value(HttpHeaders.acceptHeader) ?? '')
        .contains('vnd.pgrst.object+json');
    final path = req.uri.path;

    if (path == '/rest/v1/rpc/search_clubs') {
      _write(res, rpcRows);
    } else if (path == '/rest/v1/club_members') {
      enrichmentReads++;
      _write(res, failFirstEnrichment && enrichmentReads == 1 ? null : const []);
    } else if (path == '/rest/v1/clubs') {
      if (wantsObject) {
        _write(res, failClubLookup ? null : _clubJson('club-9'));
      } else {
        _write(res, browseRows);
      }
    } else if (path == '/rest/v1/events') {
      _write(res, eventRow);
    } else {
      _write(res, null);
    }
    await res.close();
  }

  void _write(HttpResponse res, Object? body) {
    if (body == null) {
      res.statusCode = HttpStatus.internalServerError;
      res.write(jsonEncode(
        <String, String>{'message': 'fake postgrest failure', 'code': 'XX000'},
      ));
      return;
    }
    res.write(jsonEncode(body));
  }
}

void main() {
  late _FakePostgrest fake;
  late SupabaseClient client;
  late SocialService social;

  setUp(() async {
    fake = await _FakePostgrest.start();
    client = SupabaseClient('http://127.0.0.1:${fake.port}', 'eyJ.local.test');
    social = SocialService.withClient(client);
  });

  tearDown(() async {
    client.dispose();
    await fake.close();
  });

  Future<List<ClubView>> search() => social.searchClubs(
        'richmond',
        mapTilerKey: 'unused',
        geocoder: (_) async => null,
      );

  group('searchClubs degrades to browseClubs', () {
    test('when enriching the RPC result fails', () async {
      fake
        ..rpcRows = [_clubJson('rpc-club')]
        ..failFirstEnrichment = true
        ..browseRows = [_clubJson('fallback-club')];

      final result = await search();

      expect(result.single.row.id, 'fallback-club');
      expect(
        fake.enrichmentReads,
        2,
        reason: 'the fallback ran its own enrichment after the first failed',
      );
    });

    test('when the search_clubs RPC itself fails', () async {
      fake
        ..rpcRows = null
        ..browseRows = [_clubJson('fallback-club')];

      expect((await search()).single.row.id, 'fallback-club');
    });
  });

  // Contract coverage, not a discriminating regression test: the club
  // lookup swallows its own failures, so `fetchClubSlugForEvent` returns
  // null with or without the `await` on that call. What this pins is the
  // never-rethrow contract itself — a deep link is an auxiliary effect
  // and must not throw into the push-tap handler — so a later narrowing
  // of the inner catch fails here instead of in production.
  test('fetchClubSlugForEvent returns null rather than throwing when the '
      'club lookup fails', () async {
    fake
      ..eventRow = {'club_id': 'club-9'}
      ..failClubLookup = true;

    await expectLater(
      social.fetchClubSlugForEvent('event-1'),
      completion(isNull),
    );
  });
}
