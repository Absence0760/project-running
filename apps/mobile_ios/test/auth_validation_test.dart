import 'package:flutter_test/flutter_test.dart';

import '../lib/auth_validation.dart';

void main() {
  test('kPasswordMinLength is the canonical 8 shared with web + Supabase', () {
    // Web mirrors this as PASSWORD_MIN_LENGTH (auth_rules.ts) and the
    // server enforces it via minimum_password_length in
    // apps/backend/supabase/config.toml — change all three together.
    expect(kPasswordMinLength, 8);
  });

  group('looksLikeEmail', () {
    test('accepts ordinary addresses', () {
      expect(looksLikeEmail('a@b.com'), isTrue);
      expect(looksLikeEmail('runner+tag@sub.example.co.uk'), isTrue);
    });

    test('accepts a dotless domain like the browser type=email does', () {
      expect(looksLikeEmail('a@localhost'), isTrue);
    });

    test('trims surrounding whitespace', () {
      expect(looksLikeEmail('  a@b.com  '), isTrue);
    });

    test('rejects empty and @-less values', () {
      expect(looksLikeEmail(''), isFalse);
      expect(looksLikeEmail('not-an-email'), isFalse);
    });

    test('rejects missing local part or domain', () {
      expect(looksLikeEmail('@b.com'), isFalse);
      expect(looksLikeEmail('a@'), isFalse);
    });

    test('rejects embedded whitespace and double @', () {
      expect(looksLikeEmail('a b@c.com'), isFalse);
      expect(looksLikeEmail('a@b@c.com'), isFalse);
    });
  });
}
