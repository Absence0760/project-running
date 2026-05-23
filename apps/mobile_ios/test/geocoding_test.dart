import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/geocoding.dart';

class _StubFetcher {
  final String body;
  Uri? lastUrl;
  int callCount = 0;
  _StubFetcher(this.body);
  Future<String> call(Uri url) async {
    lastUrl = url;
    callCount++;
    return body;
  }
}

void main() {
  group('searchPlaces', () {
    test('empty list when query is shorter than 2 chars', () async {
      final out = await searchPlaces(
        'a',
        apiKey: 'k',
        fetcher: (_) async => fail('fetcher must not be called'),
      );
      expect(out, isEmpty);
    });

    test('empty apiKey routes through the Nominatim fallback', () async {
      // May 2026 audit: previously this returned `const []` outright
      // when apiKey was empty. Now it falls through to Nominatim so
      // a Protomaps-only dev stack with no MAPTILER_KEY still has a
      // working search box — mirrors `searchPlacesWithKey` on web.
      // The fetcher must be HIT (the Nominatim URL), the URL must
      // be the openstreetmap.org host (NOT MapTiler), and the
      // results must parse Nominatim's `display_name` + lat / lon
      // string fields.
      Uri? hitUrl;
      Future<String> stub(Uri url) async {
        hitUrl = url;
        return jsonEncode([
          {
            'display_name': 'London, England',
            'lat': '51.5074',
            'lon': '-0.1278',
          },
        ]);
      }
      final out = await searchPlaces(
        'London',
        apiKey: '',
        fetcher: stub,
      );
      expect(hitUrl, isNotNull,
          reason: 'empty apiKey must still hit a fetcher (the Nominatim fallback)');
      expect(hitUrl!.host, 'nominatim.openstreetmap.org');
      expect(out, hasLength(1));
      expect(out.first.name, 'London, England');
      expect(out.first.lat, closeTo(51.5074, 1e-6));
      expect(out.first.lng, closeTo(-0.1278, 1e-6));
    });

    test('parses MapTiler features into PlaceResult', () async {
      final stub = _StubFetcher(jsonEncode({
        'features': [
          {
            'place_name': 'London, United Kingdom',
            'center': [-0.1278, 51.5074],
          },
          {
            'place_name': 'Londonderry, Northern Ireland',
            'center': [-7.3086, 54.9966],
          },
        ],
      }));
      final out = await searchPlaces(
        'London',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out, hasLength(2));
      expect(out.first.name, 'London, United Kingdom');
      expect(out.first.lat, closeTo(51.5074, 1e-9));
      expect(out.first.lng, closeTo(-0.1278, 1e-9));
    });

    test('URL-encodes the query and includes limit + key', () async {
      final stub = _StubFetcher(jsonEncode({'features': []}));
      await searchPlaces(
        "St John's",
        apiKey: 'mytoken',
        limit: 3,
        fetcher: stub.call,
      );
      // Path must be encoded (spaces → %20). Single quote stays raw —
      // matches JavaScript's encodeURIComponent (RFC 3986 unreserved).
      expect(stub.lastUrl!.path, contains("St%20John's.json"));
      expect(stub.lastUrl!.queryParameters['key'], 'mytoken');
      expect(stub.lastUrl!.queryParameters['limit'], '3');
    });

    test('empty list when fetcher throws', () async {
      Future<String> bomb(Uri _) async => throw StateError('boom');
      final out = await searchPlaces(
        'London',
        apiKey: 'k',
        fetcher: bomb,
      );
      expect(out, isEmpty);
    });

    test('skips features with malformed center coords', () async {
      final stub = _StubFetcher(jsonEncode({
        'features': [
          {
            'place_name': 'Valid',
            'center': [-0.1, 51.5],
          },
          {
            'place_name': 'Missing center',
            // No center key
          },
          {
            'place_name': 'Short center',
            'center': [42.0], // only one coord
          },
        ],
      }));
      final out = await searchPlaces(
        'London',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out, hasLength(1));
      expect(out.first.name, 'Valid');
    });

    test('falls back to "text" when "place_name" is absent', () async {
      final stub = _StubFetcher(jsonEncode({
        'features': [
          {
            'text': 'Just text',
            'center': [-0.1, 51.5],
          },
        ],
      }));
      final out = await searchPlaces(
        'London',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out.first.name, 'Just text');
    });

    test('empty list when the fetcher exceeds kGeocodingTimeout', () async {
      // Stub fetcher that never resolves — without the inner timeout
      // the AppBar search overlay would spin forever on a flaky
      // network. With it the catch-all returns an empty list.
      Future<String> hangingFetcher(Uri _) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return '{}';
      }
      final out = await searchPlaces(
        'London',
        apiKey: 'k',
        fetcher: hangingFetcher,
      ).timeout(
        const Duration(seconds: 9),
        onTimeout: () => fail('searchPlaces did not honour kGeocodingTimeout'),
      );
      expect(out, isEmpty);
    });
  });

  group('haversineM', () {
    test('zero distance for identical points', () {
      expect(haversineM(0, 0, 0, 0), closeTo(0, 1e-9));
    });
    test('matches a known city pair to within 1 km', () {
      // London (-0.1278, 51.5074) ↔ Paris (2.3522, 48.8566) ~344 km.
      final d = haversineM(-0.1278, 51.5074, 2.3522, 48.8566);
      expect(d, closeTo(344000, 1000));
    });
  });

  group('bboxRadius', () {
    test('returns half-diagonal for a square bbox around the centroid', () {
      // 1-degree square at the equator → each corner is 0.5° from the
      // centroid in both directions. 0.5° lat ≈ 55.5 km, 0.5° lng at
      // the equator ≈ 55.5 km → half-diagonal ≈ 78.5 km.
      final r = bboxRadius([-0.5, -0.5, 0.5, 0.5], 0, 0);
      expect(r, closeTo(78500, 1500));
    });
  });

  group('geocodePlace', () {
    test('returns null when query is too short', () async {
      final out = await geocodePlace(
        'a',
        apiKey: 'k',
        fetcher: (_) async => fail('fetcher must not be called'),
      );
      expect(out, isNull);
    });

    test('returns null when apiKey is empty', () async {
      final out = await geocodePlace(
        'Virginia',
        apiKey: '',
        fetcher: (_) async => fail('fetcher must not be called'),
      );
      expect(out, isNull);
    });

    test('returns null on no features', () async {
      final stub = _StubFetcher(jsonEncode({'features': []}));
      final out = await geocodePlace(
        'Virginia',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out, isNull);
    });

    test('parses the top feature into GeocodedPlace with bbox-derived radius',
        () async {
      final stub = _StubFetcher(jsonEncode({
        'features': [
          {
            'place_name': 'Virginia, United States',
            'center': [-78.6569, 37.4316],
            'bbox': [-83.6754, 36.5407, -75.2422, 39.4660],
            'place_type': ['region'],
          },
        ],
      }));
      final out = await geocodePlace(
        'Virginia',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out, isNotNull);
      expect(out!.name, 'Virginia, United States');
      expect(out.lng, closeTo(-78.6569, 1e-6));
      expect(out.lat, closeTo(37.4316, 1e-6));
      // Virginia's bbox is wide — radius should sit in the 400-600 km
      // range. This is the bbox-radius behaviour web depends on for
      // the "Virginia" search expanding past a single-city ILIKE.
      expect(out.radiusM, greaterThan(400000));
      expect(out.radiusM, lessThan(600000));
      expect(out.placeType, 'region');
    });

    test('defaults radius to 5000 m when bbox is absent', () async {
      // POI / address-level features sometimes omit bbox. The fallback
      // keeps the centroid usable without sweeping the surrounding
      // continent.
      final stub = _StubFetcher(jsonEncode({
        'features': [
          {
            'place_name': 'A precise address',
            'center': [-78.0, 37.0],
            'place_type': ['address'],
          },
        ],
      }));
      final out = await geocodePlace(
        'A precise address',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out, isNotNull);
      expect(out!.radiusM, closeTo(5000, 1e-9));
      expect(out.placeType, 'address');
    });

    test('returns null when feature lacks center', () async {
      final stub = _StubFetcher(jsonEncode({
        'features': [
          {'place_name': 'No center'},
        ],
      }));
      final out = await geocodePlace(
        'No center',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out, isNull);
    });

    test('returns null on fetcher error', () async {
      Future<String> bomb(Uri _) async => throw StateError('boom');
      final out = await geocodePlace(
        'London',
        apiKey: 'k',
        fetcher: bomb,
      );
      expect(out, isNull);
    });

    test('falls back to "text" when "place_name" is absent', () async {
      final stub = _StubFetcher(jsonEncode({
        'features': [
          {
            'text': 'Falls back',
            'center': [0.0, 0.0],
            'bbox': [-0.1, -0.1, 0.1, 0.1],
          },
        ],
      }));
      final out = await geocodePlace(
        'Falls back',
        apiKey: 'k',
        fetcher: stub.call,
      );
      expect(out!.name, 'Falls back');
    });
  });
}
