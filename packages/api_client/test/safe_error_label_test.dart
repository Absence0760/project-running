import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Pins the /audit/pii-in-logs fix on the safety-contact fetch paths:
/// a caught exception's content (which can echo a safety contact's
/// email via PostgREST details/hint) must never be interpolated into a
/// debugPrint line — only the runtime type + SQLSTATE code may appear.
void main() {
  group('safeErrorLabel', () {
    test('PostgrestException collapses to type + code, never message/details/hint', () {
      final e = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
        details: 'Key (contact_email)=(secret.contact@example.com) already exists.',
        hint: 'hint-sentinel',
      );
      final label = safeErrorLabel(e);
      expect(label, 'PostgrestException(code: 23505)');
      expect(label, isNot(contains('secret.contact@example.com')));
      expect(label, isNot(contains('duplicate key')));
      expect(label, isNot(contains('hint-sentinel')));
    });

    test('PostgrestException without a code labels it unknown', () {
      final e = PostgrestException(message: 'row content x@y.com');
      expect(safeErrorLabel(e), 'PostgrestException(code: unknown)');
    });

    test('arbitrary exception collapses to its runtime type only', () {
      final label = safeErrorLabel(const FormatException('body with pii@example.com'));
      expect(label, 'FormatException');
      expect(label, isNot(contains('pii@example.com')));
    });
  });

  group('safety-contact fetch failures log no exception content', () {
    late SupabaseClient fake;
    late List<String> logged;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      // Port 9 (discard) is never listening — every wire call fails
      // fast with a socket-level exception whose message embeds the
      // URL, standing in for content that must not reach the log.
      fake = SupabaseClient('http://127.0.0.1:9', 'eyJ.local.test');
      logged = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logged.add(message);
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      fake.dispose();
    });

    test('fetchMySafetyContacts fails soft and logs only the error type', () async {
      // The list read is owner-scoped, so it needs a session before it will
      // reach the wire at all (decisions §720).
      await fake.auth.setInitialSession(jsonEncode({
        'access_token': 'fake-token',
        'token_type': 'bearer',
        'user': {
          'id': 'user-1',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }));
      final api = ApiClient.withClient(fake);
      final contacts = await api.fetchMySafetyContacts();
      expect(contacts, isEmpty);
      final line = logged.singleWhere((l) => l.startsWith('fetchMySafetyContacts failed:'));
      expect(line, isNot(contains('127.0.0.1')));
      expect(line, isNot(contains('http')));
    });

    test('a signed-out fetchMySafetyContacts refuses before the wire', () async {
      // Not merely an optimisation: the owner scope has no value to filter on
      // without a session, and an unfiltered fallback is exactly the union
      // bug (decisions §720).
      final api = ApiClient.withClient(fake);
      expect(await api.fetchMySafetyContacts(), isEmpty);
      expect(logged, isEmpty);
    });

    test('a signed-out removeSafetyContact throws instead of deleting by id', () async {
      final api = ApiClient.withClient(fake);
      await expectLater(
        api.removeSafetyContact('11111111-1111-1111-1111-111111111111'),
        throwsA(predicate((Object e) =>
            e.toString().toLowerCase().contains('not authenticated'))),
      );
    });

    test('fetchPendingSafetyRequests fails soft and logs only the error type', () async {
      final api = ApiClient.withClient(fake);
      final requests = await api.fetchPendingSafetyRequests();
      expect(requests, isEmpty);
      final line = logged.singleWhere((l) => l.startsWith('fetchPendingSafetyRequests failed:'));
      expect(line, isNot(contains('127.0.0.1')));
      expect(line, isNot(contains('http')));
    });
  });
}
