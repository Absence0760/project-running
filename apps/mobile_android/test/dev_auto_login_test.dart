import 'package:flutter_test/flutter_test.dart';

import '../lib/dev_auto_login.dart';

void main() {
  group('isLocalSupabaseUrl', () {
    test('true for the accepted loopback hosts', () {
      expect(isLocalSupabaseUrl('http://10.0.2.2:54321'), isTrue);
      expect(isLocalSupabaseUrl('http://localhost:54321'), isTrue);
      expect(isLocalSupabaseUrl('http://127.0.0.1:54321'), isTrue);
      expect(isLocalSupabaseUrl('http://host.docker.internal:54321'), isTrue);
    });

    test('false for production / remote hosts', () {
      expect(isLocalSupabaseUrl('https://abcdefgh.supabase.co'), isFalse);
      expect(isLocalSupabaseUrl('https://app.threkir.com'), isFalse);
    });

    test('false for null / empty / malformed', () {
      expect(isLocalSupabaseUrl(null), isFalse);
      expect(isLocalSupabaseUrl(''), isFalse);
      expect(isLocalSupabaseUrl('garbage'), isFalse);
    });
  });

  group('shouldAutoLogin', () {
    test('true only with credentials AND a local backend', () {
      expect(
        shouldAutoLogin(
          url: 'http://10.0.2.2:54321',
          email: 'runner@test.com',
          password: 'testtest',
        ),
        isTrue,
      );
    });

    test('false against a production URL even with credentials', () {
      expect(
        shouldAutoLogin(
          url: 'https://abcdefgh.supabase.co',
          email: 'runner@test.com',
          password: 'testtest',
        ),
        isFalse,
        reason: 'seed creds must never sign a user into production',
      );
    });

    test('false when either credential is missing or empty', () {
      const url = 'http://10.0.2.2:54321';
      expect(shouldAutoLogin(url: url, email: '', password: 'testtest'), isFalse);
      expect(shouldAutoLogin(url: url, email: 'runner@test.com', password: null),
          isFalse);
      expect(shouldAutoLogin(url: url, email: null, password: null), isFalse);
    });
  });
}
