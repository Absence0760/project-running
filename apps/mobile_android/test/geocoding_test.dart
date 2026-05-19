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

    test('empty list when apiKey is empty', () async {
      final out = await searchPlaces(
        'London',
        apiKey: '',
        fetcher: (_) async => fail('fetcher must not be called'),
      );
      expect(out, isEmpty);
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
}
