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
      final api = ApiClient.withClient(fake);
      final contacts = await api.fetchMySafetyContacts();
      expect(contacts, isEmpty);
      final line = logged.singleWhere((l) => l.startsWith('fetchMySafetyContacts failed:'));
      expect(line, isNot(contains('127.0.0.1')));
      expect(line, isNot(contains('http')));
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
