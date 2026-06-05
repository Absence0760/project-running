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
