import 'dart:io';

import 'package:test/test.dart';

/// Source guards on the safety-contact list read + remove (issue #789 K,
/// decisions §720).
///
/// `safety_contacts` carries FOUR permissive policies, not two — "owner
/// read"/"owner delete" (`owner_id = auth.uid()`) AND "linked contact
/// read"/"linked contact delete" (`contact_user_id = auth.uid()`), both from
/// migration 20261218_001 and both still present after 20270416_001's initplan
/// wrap. Permissive policies OR, so an unfiltered read returns the UNION: the
/// caller's own contacts plus every relationship in which someone else named
/// THEM and they confirmed — which the settings screen rendered as the
/// caller's own list, under their own email address, with a Remove button that
/// the linked-contact DELETE policy let through and which therefore stripped
/// the OTHER person's emergency contact.
///
/// RLS is a security boundary (what a caller MAY read), never a query
/// specification (what they WANT), so the scope has to be said out loud. These
/// are static properties: a single-account local stack has no second party to
/// produce the union, so a wire test would not catch the regression.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();

  String slice(String signature) {
    final start = src.indexOf(signature);
    if (start < 0) return '';
    final end = src.indexOf('\n  /// ', start + 1);
    return src.substring(start, end == -1 ? src.length : end);
  }

  final fetch = slice('Future<List<SafetyContact>> fetchMySafetyContacts(');
  final remove = slice('Future<void> removeSafetyContact(');
  final contactOf = slice('Future<List<SafetyContactOf>> fetchSafetyContactOf(');

  test('both safety-contact methods exist', () {
    expect(fetch, isNotEmpty, reason: 'fetchMySafetyContacts moved or renamed');
    expect(remove, isNotEmpty, reason: 'removeSafetyContact moved or renamed');
  });

  test('the list read filters owner_id rather than leaning on RLS', () {
    expect(
      fetch.contains('.eq(SafetyContactRow.colOwnerId, userId)'),
      isTrue,
      reason: 'without it the read returns the union with the rows naming the '
          'caller as someone ELSE\'s safety contact',
    );
  });

  test('the contact-of read names the OTHER half rather than inheriting it', () {
    // The rows this read wants are exactly the ones the owner-scoped list
    // stopped returning. Both halves of the table are legitimately readable,
    // so neither query may leave the predicate to the policy.
    expect(contactOf, isNotEmpty, reason: 'fetchSafetyContactOf moved or renamed');
    expect(
      contactOf.contains('.eq(SafetyContactRow.colContactUserId, userId)'),
      isTrue,
      reason: 'without it the read returns the union with the caller\'s own '
          'safety contacts, presented as relationships they are the contact of',
    );
  });

  test('the delete is scoped to the caller\'s own row', () {
    expect(
      remove.contains('.eq(SafetyContactRow.colOwnerId, userId)'),
      isTrue,
      reason: 'an id-only delete succeeds against a row the caller merely '
          'appears on, silently removing another person\'s emergency contact; '
          'withdrawing from such a relationship is declineSafetyRequest',
    );
    expect(
      remove.contains("throw Exception('Not authenticated')"),
      isTrue,
      reason: 'a signed-out delete must refuse before issuing an unscoped '
          'query, with the phrasing classifyAuthError maps to "sign in"',
    );
  });
}
