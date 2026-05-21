import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/race_controller.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

/// Runtime coverage for the "Supabase not initialized" guard on every
/// service that bypasses [ApiClient] and reads `Supabase.instance.client`
/// directly. The bug class:
///   1. `Supabase.initialize` fails silently in `main.dart` (caught
///      and logged via `.catchError`).
///   2. A service is constructed unconditionally (e.g.
///      `final social = SocialService()`).
///   3. First method call hits the SDK's `late SupabaseClient client`
///      field → `LateInitializationError` surfaces deep inside
///      Supabase code with no actionable hint for the user.
///
/// The guard rewrites step 3 to throw a typed [StateError] naming the
/// bootstrap problem. The source-level architecture guards in
/// `architecture_guards_test.dart` pin the *guard itself*; these tests
/// pin the *runtime behaviour*.
///
/// **Important:** this file deliberately does NOT call
/// `Supabase.initialize` in `setUp` / `setUpAll`, so the test isolate
/// sees Supabase as never-initialized — the exact bootstrap state the
/// guards defend against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ApiClient.debugResetInitialized);

  group('TrainingService — bootstrap guard', () {
    test('method call before Supabase.initialize throws StateError, '
        'not LateInitializationError', () async {
      final svc = TrainingService();
      Object? captured;
      try {
        await svc.fetchMyPlans();
      } catch (e) {
        captured = e;
      }
      expect(captured, isA<StateError>(),
          reason: 'Expected StateError, got ${captured?.runtimeType}.');
      expect((captured as StateError).message,
          contains('Supabase.initialize'));
      expect(captured.message, contains('TrainingService'));
    });

    test('default TrainingService() still constructs without throwing — '
        'the guard only fires when a method actually touches _c', () {
      // Construction must not throw, or every test that wires
      // TrainingService as a placeholder dep regresses.
      expect(() => TrainingService(), returnsNormally);
    });
  });

  group('SocialService — bootstrap guard', () {
    test('method call before Supabase.initialize throws StateError',
        () async {
      final svc = SocialService();
      Object? captured;
      try {
        await svc.browseClubs();
      } catch (e) {
        captured = e;
      }
      expect(captured, isA<StateError>(),
          reason: 'Expected StateError, got ${captured?.runtimeType}.');
      expect(
          (captured as StateError).message, contains('Supabase.initialize'));
      expect(captured.message, contains('SocialService'));
    });

    test('currentUserId getter also routes through the guard', () {
      // Synchronous path — `_c.auth.currentUser?.id` is read on the
      // same tick, so the StateError surfaces without an await.
      final svc = SocialService();
      expect(() => svc.currentUserId, throwsStateError);
    });
  });

  group('RaceController — bootstrap guard', () {
    test('start() rejects with StateError before Supabase init', () async {
      final social = SocialService();
      final controller = RaceController(social);
      Object? captured;
      try {
        await controller.start();
      } catch (e) {
        captured = e;
      }
      expect(captured, isA<StateError>(),
          reason: 'Expected StateError, got ${captured?.runtimeType}.');
      // Either the SocialService guard (touched by RaceController as
      // it walks the user's events) or the RaceController guard fires
      // first — both name the same bootstrap problem so either is
      // acceptable.
      final msg = (captured as StateError).message;
      expect(msg, contains('Supabase.initialize'));
      expect(
        msg,
        anyOf(contains('RaceController'), contains('SocialService')),
      );
    });
  });

  group('Error type discipline — every guard throws StateError', () {
    // Pins the contract: callers can catch StateError to handle the
    // "Supabase not ready" path. If a guard regresses to bare
    // Exception or a string literal, this test fails first.
    test('all four call sites throw StateError, never Error / Exception',
        () async {
      final t = TrainingService();
      final s = SocialService();
      final r = RaceController(s);
      final probes = <Future<void> Function()>[
        t.fetchMyPlans,
        () async => s.browseClubs(),
        () async {
          s.currentUserId; // sync getter
        },
        r.start,
      ];
      for (final probe in probes) {
        Object? captured;
        try {
          await probe();
        } catch (e) {
          captured = e;
        }
        expect(
          captured,
          isA<StateError>(),
          reason: 'A probe threw ${captured?.runtimeType} instead of '
              'StateError. The "Supabase not initialized" guards must '
              'use StateError so catch sites can match without '
              "sniffing the SDK's internal types.",
        );
      }
    });
  });

  group('ApiClient.isInitialized — probe semantics', () {
    test('returns false when Supabase has never been initialized', () {
      // In this test isolate, no Supabase.initialize / ApiClient.initialize
      // has run, so the probe inside isInitialized throws and the
      // getter returns false.
      ApiClient.debugResetInitialized();
      expect(ApiClient.isInitialized, isFalse);
    });

    test(
        'ApiClient() does NOT throw before init — HomeScreen relies on a '
        'fallback `apiClient ?? ApiClient()` for the offline-mode path', () {
      ApiClient.debugResetInitialized();
      expect(() => ApiClient(), returnsNormally);
    });

    test(
        'but a method call on the fallback ApiClient throws a typed '
        'StateError (not LateInitializationError) — this is the actual '
        'guard the original bug report regressed on', () {
      ApiClient.debugResetInitialized();
      final api = ApiClient();
      expect(() => api.signOut(), throwsStateError);
    });
  });
}
