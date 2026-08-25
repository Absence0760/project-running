import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  group('SafetyContact.fromJson', () {
    test('a confirmed contact parses with isConfirmed true', () {
      final c = SafetyContact.fromJson({
        'id': 'sc1',
        'contact_email': 'partner@example.com',
        'contact_user_id': 'u2',
        'confirmed_at': '2026-06-02T08:00:00.000Z',
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.id, 'sc1');
      expect(c.contactEmail, 'partner@example.com');
      expect(c.contactUserId, 'u2');
      expect(c.confirmedAt, DateTime.utc(2026, 6, 2, 8));
      expect(c.createdAt, DateTime.utc(2026, 6, 1, 8));
      expect(c.isConfirmed, isTrue);
    });

    test('a confirmed contact with a phone and an opt-in is SMS-reachable',
        () {
      final c = SafetyContact.fromJson({
        'id': 'sc3',
        'contact_email': 'partner@example.com',
        'contact_phone': '+447700900123',
        'contact_user_id': 'u2',
        'confirmed_at': '2026-06-02T08:00:00.000Z',
        'sms_opt_in_at': '2026-06-02T08:00:00.000Z',
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.contactPhone, '+447700900123');
      expect(c.smsOptInAt, DateTime.utc(2026, 6, 2, 8));
      expect(c.isSmsReachable, isTrue);
      expect(c.isSmsAwaitingOptIn, isFalse);
    });

    test('a stored phone without the contact opt-in is NOT SMS-reachable', () {
      final c = SafetyContact.fromJson({
        'id': 'sc4',
        'contact_email': 'partner@example.com',
        'contact_phone': '+447700900123',
        'contact_user_id': 'u2',
        'confirmed_at': '2026-06-02T08:00:00.000Z',
        'sms_opt_in_at': null,
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.isSmsReachable, isFalse,
          reason: 'the number is the owner\'s claim, not the contact\'s consent');
      expect(c.isSmsAwaitingOptIn, isTrue);
    });

    test('an opt-in on an unconfirmed relationship is still not reachable',
        () {
      // The scan joins on confirmed_at as well; a row in this shape should
      // not exist, but the getter must not out-claim the query either way.
      final c = SafetyContact.fromJson({
        'id': 'sc5',
        'contact_email': 'partner@example.com',
        'contact_phone': '+447700900123',
        'contact_user_id': null,
        'confirmed_at': null,
        'sms_opt_in_at': '2026-06-02T08:00:00.000Z',
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.isSmsReachable, isFalse);
    });

    test('no phone at all is neither reachable nor awaiting an opt-in', () {
      final c = SafetyContact.fromJson({
        'id': 'sc6',
        'contact_email': 'partner@example.com',
        'contact_phone': null,
        'contact_user_id': 'u2',
        'confirmed_at': '2026-06-02T08:00:00.000Z',
        'sms_opt_in_at': null,
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.isSmsReachable, isFalse);
      expect(c.isSmsAwaitingOptIn, isFalse);
    });

    test('a pending contact (null confirmed_at / contact_user_id) is unconfirmed',
        () {
      final c = SafetyContact.fromJson({
        'id': 'sc2',
        'contact_email': 'friend@example.com',
        'contact_user_id': null,
        'confirmed_at': null,
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.contactUserId, isNull);
      expect(c.confirmedAt, isNull);
      expect(c.isConfirmed, isFalse);
    });
  });

  group('PendingSafetyRequest.fromJson', () {
    test('parses owner_name + created_at', () {
      final r = PendingSafetyRequest.fromJson({
        'id': 'req1',
        'owner_name': 'Alex',
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(r.id, 'req1');
      expect(r.ownerName, 'Alex');
      expect(r.createdAt, DateTime.utc(2026, 6, 1, 8));
      expect(r.hasPhone, isFalse,
          reason: 'an absent has_phone must not offer the SMS opt-in');
    });

    test('has_phone rides through so the confirm surface can offer SMS', () {
      final r = PendingSafetyRequest.fromJson({
        'id': 'req3',
        'owner_name': 'Alex',
        'has_phone': true,
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(r.hasPhone, isTrue);
    });

    test('a null owner_name falls back to empty string', () {
      final r = PendingSafetyRequest.fromJson({
        'id': 'req2',
        'owner_name': null,
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(r.ownerName, '');
    });
  });
}
