@TestOn('vm')
library;

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Wire-level pin for issue #227's 0-row half: `user_profiles` rows are
/// client-provisioned (no signup trigger), so a plain
/// `.update().eq(id, uid)` against a user whose row doesn't exist yet
/// matches 0 rows and reports success — the wizard then navigated away
/// while `onboarded_at` stayed null and the gate bounced the user back to
/// step 1. The stamp writers are now row-count-verified with an insert
/// fallback (§248), so the write must land a row even when no profile row
/// existed.
///
/// **Skipped unless `SUPABASE_TEST_URL` is set** — same harness contract
/// as `consent_withdrawal_integration_test.dart`. Signs up fresh throwaway
/// users (local config has `enable_confirmations = false`, so the session
/// is immediate) precisely because a fresh user is the no-profile-row case.
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');

void main() {
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'onboarding write integration tests — skipped (SUPABASE_TEST_URL not set)',
      () {},
    );
    return;
  }

  // get_my_profile() `returns user_profiles`, so a missing row comes back
  // as an all-null composite (id == null), not as SQL NULL.
  Map<String, dynamic>? profileRow(dynamic res) {
    final row = (res is List ? (res.isEmpty ? null : res.first) : res)
        as Map<String, dynamic>?;
    if (row == null || row['id'] == null) return null;
    return row;
  }

  SupabaseClient newClient() => SupabaseClient(
        url,
        anonKey,
        authOptions:
            const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );

  Future<void> signUpFresh(SupabaseClient client, String tag) async {
    final email =
        'onboard-it-$tag-${DateTime.now().millisecondsSinceEpoch}@test.local';
    final res = await client.auth.signUp(email: email, password: 'testtest');
    expect(res.session, isNotNull,
        reason: 'local signUp must return an immediate session '
            '(enable_confirmations = false)');
  }

  test('markOnboarded lands the stamp when no profile row exists', () async {
    final client = newClient();
    addTearDown(() async {
      await client.auth.signOut();
      client.dispose();
    });
    final api = ApiClient.withClient(client);
    await signUpFresh(client, 'skip');

    final before = profileRow(await client.rpc('get_my_profile'));
    expect(before, isNull,
        reason: 'fresh user must have no client-provisioned profile row — '
            'the 0-row trigger this test exists for');

    await api.markOnboarded();

    final after = profileRow(await client.rpc('get_my_profile'));
    expect(after, isNotNull, reason: 'the stamp must land a row, not 0-row');
    expect(after!['onboarded_at'], isNotNull);
  });

  test('completeOnboarding lands the answers when no profile row exists',
      () async {
    final client = newClient();
    addTearDown(() async {
      await client.auth.signOut();
      client.dispose();
    });
    final api = ApiClient.withClient(client);
    await signUpFresh(client, 'finish');

    expect(profileRow(await client.rpc('get_my_profile')), isNull);

    await api.completeOnboarding(
      displayName: '  Alex Runner  ',
      preferredUnit: 'mi',
      healthDataConsent: false,
    );

    final after = profileRow(await client.rpc('get_my_profile'));
    expect(after, isNotNull);
    expect(after!['onboarded_at'], isNotNull);
    expect(after['display_name'], 'Alex Runner');
    expect(after['preferred_unit'], 'mi');
  });

  test('completeOnboarding with every optional field blank still stamps',
      () async {
    final client = newClient();
    addTearDown(() async {
      await client.auth.signOut();
      client.dispose();
    });
    final api = ApiClient.withClient(client);
    await signUpFresh(client, 'blank');

    await api.completeOnboarding(
      displayName: '',
      preferredUnit: 'km',
      healthDataConsent: false,
    );

    final after = profileRow(await client.rpc('get_my_profile'));
    expect(after, isNotNull);
    expect(after!['onboarded_at'], isNotNull,
        reason: 'skipped sections must never block the stamp — finishing '
            'means finished (issue #227)');
  });
}
