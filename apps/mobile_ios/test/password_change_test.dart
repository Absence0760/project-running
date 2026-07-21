import 'package:flutter_test/flutter_test.dart';
import '../lib/password_change.dart';

// Mirror of `apps/web/src/lib/core/password_change.test.ts` — 7 cases, one
// per web test. Every case records whether the account's password was
// actually written, because the whole point of the helper is that a
// rotation can't happen without a positive proof of the current password.
void main() {
  group('changePassword', () {
    late List<String> verified;
    late List<String> updated;

    VerifyCurrentPassword verifyOk() => (current) async {
          verified.add(current);
          return current == 'currentpw123';
        };

    UpdatePassword updateOk() => (next) async {
          updated.add(next);
          return null;
        };

    setUp(() {
      verified = [];
      updated = [];
    });

    test('correct current password → password is updated', () async {
      final result = await changePassword(
        const PasswordChangeInput(
          currentPassword: 'currentpw123',
          newPassword: 'brandnewpw',
          confirmPassword: 'brandnewpw',
        ),
        verifyCurrentPassword: verifyOk(),
        updatePassword: updateOk(),
      );
      expect(result.ok, isTrue);
      expect(result.reason, isNull);
      expect(verified, ['currentpw123']);
      expect(updated, ['brandnewpw']);
    });

    test('wrong current password → rejected and nothing is written', () async {
      final result = await changePassword(
        const PasswordChangeInput(
          currentPassword: 'notmypassword',
          newPassword: 'brandnewpw',
          confirmPassword: 'brandnewpw',
        ),
        verifyCurrentPassword: verifyOk(),
        updatePassword: updateOk(),
      );
      expect(result.ok, isFalse);
      expect(result.reason, PasswordChangeReason.currentInvalid);
      expect(updated, isEmpty);
    });

    test('empty current password → rejected before any verification call',
        () async {
      final result = await changePassword(
        const PasswordChangeInput(
          currentPassword: '',
          newPassword: 'brandnewpw',
          confirmPassword: 'brandnewpw',
        ),
        verifyCurrentPassword: verifyOk(),
        updatePassword: updateOk(),
      );
      expect(result.ok, isFalse);
      expect(result.reason, PasswordChangeReason.currentMissing);
      expect(verified, isEmpty);
      expect(updated, isEmpty);
    });

    test('a verification that throws fails closed — no update', () async {
      // Offline, a 500 from GoTrue, a rate-limit rejection: none of those
      // are proof, so none of them may fall through to the write.
      final result = await changePassword(
        const PasswordChangeInput(
          currentPassword: 'currentpw123',
          newPassword: 'brandnewpw',
          confirmPassword: 'brandnewpw',
        ),
        verifyCurrentPassword: (_) async => throw Exception('Failed to fetch'),
        updatePassword: updateOk(),
      );
      expect(result.ok, isFalse);
      expect(result.reason, PasswordChangeReason.currentInvalid);
      expect(updated, isEmpty);
    });

    test('mismatched new entries are rejected before the current password '
        'is sent', () async {
      // The pair check is free and local; running it first keeps a typo in
      // the new field from burning a sign-in attempt against the rate limit.
      final result = await changePassword(
        const PasswordChangeInput(
          currentPassword: 'currentpw123',
          newPassword: 'brandnewpw',
          confirmPassword: 'brandnewpx',
        ),
        verifyCurrentPassword: verifyOk(),
        updatePassword: updateOk(),
      );
      expect(result.ok, isFalse);
      expect(result.reason, PasswordChangeReason.mismatch);
      expect(verified, isEmpty);
    });

    test('a too-short new password reports length, not mismatch', () async {
      final result = await changePassword(
        const PasswordChangeInput(
          currentPassword: 'currentpw123',
          newPassword: 'abc',
          confirmPassword: 'xyz',
        ),
        verifyCurrentPassword: verifyOk(),
        updatePassword: updateOk(),
      );
      expect(result.ok, isFalse);
      expect(result.reason, PasswordChangeReason.tooShort);
    });

    test('a failed update surfaces the provider message', () async {
      final result = await changePassword(
        const PasswordChangeInput(
          currentPassword: 'currentpw123',
          newPassword: 'brandnewpw',
          confirmPassword: 'brandnewpw',
        ),
        verifyCurrentPassword: verifyOk(),
        updatePassword: (_) async =>
            'New password should be different from the old password.',
      );
      expect(result.ok, isFalse);
      expect(result.reason, PasswordChangeReason.updateFailed);
      expect(
        result.detail,
        'New password should be different from the old password.',
      );
    });
  });
}
