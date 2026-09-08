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

  group('a consent stamp the calendar cannot hold is withheld, never rolled',
      () {
    test('an impossible opt-in leaves the contact NOT SMS-reachable', () {
      // `DateTime.parse` reads this as 2027-02-18 — a stamp that would have
      // read as a real opt-in and armed the SMS escalation.
      expect(DateTime.parse('2026-13-45T99:99:99Z'),
          DateTime.utc(2027, 2, 18, 4, 40, 39));
      final c = SafetyContact.fromJson({
        'id': 'sc9',
        'contact_email': 'partner@example.com',
        'contact_phone': '+447700900123',
        'confirmed_at': '2026-06-02T08:00:00.000Z',
        'sms_opt_in_at': '2026-13-45T99:99:99Z',
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.smsOptInAt, isNull);
      expect(c.isSmsReachable, isFalse);
    });

    test('an impossible confirmation leaves the contact unconfirmed', () {
      final c = SafetyContact.fromJson({
        'id': 'sc10',
        'contact_email': 'partner@example.com',
        'confirmed_at': '2026-06-31T08:00:00Z',
        'created_at': '2026-06-01T08:00:00.000Z',
      });
      expect(c.confirmedAt, isNull);
      expect(c.isConfirmed, isFalse);
    });

    test('an impossible required stamp is refused rather than answered', () {
      expect(
        () => SafetyContact.fromJson({
          'id': 'sc11',
          'contact_email': 'partner@example.com',
          'created_at': '2026-06-32',
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('created_at'))),
      );
      expect(
        () => PendingSafetyRequest.fromJson({
          'id': 'req9',
          'owner_name': 'Alex',
          'created_at': '2026-06-32',
        }),
        throwsFormatException,
      );
    });

    test('the mirror-image opt-in is withheld the same way', () {
      final c = SafetyContactOf.fromJson({
        'id': 'sco1',
        'owner_id': 'u1',
        'contact_phone': '+447700900123',
        'sms_opt_in_at': '2026-06-31T08:00:00Z',
        'created_at': '2026-06-01T08:00:00.000Z',
      }, 'Alex');
      expect(c.smsOptInAt, isNull);
    });

    test('an impossible event start is refused rather than moved a fortnight',
        () {
      expect(
        () => PublicEventResult.fromRow({
          'id': 'e1',
          'club_id': 'c1',
          'club_name': 'Harriers',
          'club_slug': 'harriers',
          'title': 'Tuesday tempo',
          'category': 'run',
          'starts_at': '2026-13-45T99:99:99Z',
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('starts_at'))),
      );
    });
  });
}
