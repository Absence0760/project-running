import 'package:flutter_test/flutter_test.dart';

import '../lib/trusted_contacts.dart';

void main() {
  // Persona-hunt Round 3 finding Woman #4. Dart twin of
  // `apps/web/src/lib/trusted_contacts.test.ts` — keep in lockstep.

  group('normaliseTrustedContact', () {
    test('keeps trimmed name + populated optionals', () {
      final out = normaliseTrustedContact(const TrustedContact(
        name: '  Alice  ',
        phone: ' +44 7700 900111 ',
        email: '  alice@example.com  ',
        relationship: ' partner ',
      ));
      expect(out, isNotNull);
      expect(out!.name, 'Alice');
      expect(out.phone, '+44 7700 900111');
      expect(out.email, 'alice@example.com');
      expect(out.relationship, 'partner');
    });

    test('drops empty-string optionals (does not store "")', () {
      final out = normaliseTrustedContact(const TrustedContact(
        name: 'Bob',
        phone: '',
        email: '   ',
        relationship: '',
      ));
      expect(out, isNotNull);
      expect(out!.name, 'Bob');
      expect(out.phone, isNull);
      expect(out.email, isNull);
      expect(out.relationship, isNull);
    });

    test('returns null when name is missing or whitespace-only', () {
      expect(normaliseTrustedContact(const TrustedContact(name: '')), isNull);
      expect(
          normaliseTrustedContact(const TrustedContact(name: '   ')), isNull);
      expect(
        normaliseTrustedContact(
            const TrustedContact(name: '', phone: '+1 555 0123')),
        isNull,
      );
    });
  });

  group('normaliseTrustedContacts', () {
    test('null / empty returns const []', () {
      expect(normaliseTrustedContacts(null), const <TrustedContact>[]);
      expect(normaliseTrustedContacts(const []), const <TrustedContact>[]);
    });

    test('filters invalid entries from a mixed list', () {
      final out = normaliseTrustedContacts(const [
        TrustedContact(name: 'Alice', phone: '+1'),
        TrustedContact(name: '', phone: '+1'),
        TrustedContact(name: '  '),
        TrustedContact(name: 'Bob'),
      ]);
      expect(out.length, 2);
      expect(out[0].name, 'Alice');
      expect(out[0].phone, '+1');
      expect(out[1].name, 'Bob');
    });

    test('caps at kMaxTrustedContacts', () {
      final input = List.generate(
        kMaxTrustedContacts + 3,
        (i) => TrustedContact(name: 'Contact $i'),
      );
      final out = normaliseTrustedContacts(input);
      expect(out.length, kMaxTrustedContacts);
    });
  });

  group('hasReachableChannel', () {
    test('true when phone OR email present', () {
      expect(
        hasReachableChannel(const TrustedContact(name: 'A', phone: '+1')),
        isTrue,
      );
      expect(
        hasReachableChannel(const TrustedContact(name: 'A', email: 'a@b.c')),
        isTrue,
      );
      expect(
        hasReachableChannel(
            const TrustedContact(name: 'A', phone: '+1', email: 'a@b.c')),
        isTrue,
      );
    });

    test('false when neither phone nor email present', () {
      expect(
        hasReachableChannel(const TrustedContact(name: 'A')),
        isFalse,
      );
      expect(
        hasReachableChannel(
            const TrustedContact(name: 'A', relationship: 'parent')),
        isFalse,
      );
    });
  });

  group('TrustedContact.toJson / fromJson', () {
    test('round-trips with all fields', () {
      const c = TrustedContact(
        name: 'Alice',
        phone: '+1',
        email: 'a@b.c',
        relationship: 'partner',
      );
      final json = c.toJson();
      final back = TrustedContact.fromJson(json);
      expect(back.name, c.name);
      expect(back.phone, c.phone);
      expect(back.email, c.email);
      expect(back.relationship, c.relationship);
    });

    test('omits null optionals from the JSON payload', () {
      const c = TrustedContact(name: 'Bob');
      final json = c.toJson();
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('phone'), isFalse);
      expect(json.containsKey('email'), isFalse);
      expect(json.containsKey('relationship'), isFalse);
    });
  });
}
