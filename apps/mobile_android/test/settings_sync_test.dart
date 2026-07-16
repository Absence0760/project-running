import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/goals.dart';
import '../lib/preferences.dart';
import '../lib/settings_sync.dart';

Future<Preferences> freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

class _MemCache implements SettingsCache {
  final Map<String, Map<String, dynamic>> universal = {};
  final Map<String, Map<String, dynamic>> device = {};

  @override
  Map<String, dynamic>? readUniversal(String userId) => universal[userId];
  @override
  Map<String, dynamic>? readDevice(String userId, String deviceId) =>
      device['$userId/$deviceId'];
  @override
  Future<void> writeUniversal(String userId, Map<String, dynamic> prefs) async =>
      universal[userId] = prefs;
  @override
  Future<void> writeDevice(
          String userId, String deviceId, Map<String, dynamic> prefs) async =>
      device['$userId/$deviceId'] = prefs;
  @override
  List<PendingSettingsChange> readPending(String userId, String deviceId) =>
      const [];
  @override
  Future<void> appendPending(
      String userId, String deviceId, PendingSettingsChange change) async {}
  @override
  Future<void> clearPending(String userId, String deviceId) async {}
  @override
  Future<void> dropUser(String userId) async {
    universal.remove(userId);
    device.removeWhere((k, _) => k.startsWith('$userId/'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('debugApplyUniversal', () {
    test('preferred_unit "mi" sets useMiles to true', () async {
      final prefs = await freshPrefs();
      expect(prefs.useMiles, isFalse);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.preferredUnit: 'mi'});

      expect(prefs.useMiles, isTrue);
    });

    test('preferred_unit "km" leaves useMiles=false (or flips back)',
        () async {
      final prefs = await freshPrefs();
      await prefs.setUseMiles(true);
      expect(prefs.useMiles, isTrue);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.preferredUnit: 'km'});

      expect(prefs.useMiles, isFalse);
    });

    test('non-string preferred_unit value is silently ignored', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.preferredUnit: 42});

      expect(prefs.useMiles, isFalse);
    });

    test('default_activity_type updates the local default', () async {
      final prefs = await freshPrefs();
      expect(prefs.defaultActivityType, isNot('cycle'));
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.defaultActivityType: 'cycle'});

      expect(prefs.defaultActivityType, 'cycle');
    });

    test('empty default_activity_type string is rejected', () async {
      final prefs = await freshPrefs();
      final original = prefs.defaultActivityType;
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.defaultActivityType: ''});

      expect(prefs.defaultActivityType, original);
    });

    test('weekly_mileage_goal_m seeds a weekly distance goal when none exists',
        () async {
      final prefs = await freshPrefs();
      expect(prefs.goals, isEmpty);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal(
          {SettingsKeys.weeklyMileageGoalMetres: 25000});

      final weekly = prefs.goals
          .where((g) => g.period == GoalPeriod.week && g.distanceMetres != null);
      expect(weekly, hasLength(1));
      expect(weekly.single.distanceMetres, 25000);
    });

    test('weekly_mileage_goal_m does NOT replace an existing weekly distance goal',
        () async {
      final prefs = await freshPrefs();
      await prefs.upsertGoal(const RunGoal(
        id: 'pre-existing',
        period: GoalPeriod.week,
        distanceMetres: 50000,
      ));
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal(
          {SettingsKeys.weeklyMileageGoalMetres: 25000});

      final weekly = prefs.goals
          .where((g) => g.period == GoalPeriod.week && g.distanceMetres != null)
          .toList();
      expect(weekly, hasLength(1));
      expect(weekly.single.id, 'pre-existing');
      expect(weekly.single.distanceMetres, 50000);
    });

    test('weekly_mileage_goal_m of 0 or negative is ignored', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.weeklyMileageGoalMetres: 0});
      expect(prefs.goals, isEmpty);

      svc.debugApplyUniversal({SettingsKeys.weeklyMileageGoalMetres: -5});
      expect(prefs.goals, isEmpty);
    });

    test('body_weight_kg overlays a positive value into local prefs',
        () async {
      // The run-detail calorie estimate reads `preferences.bodyWeightKg`
      // and falls through to 70 kg when unset. A user who set their
      // weight on /settings/account on web must see that value
      // reflected on mobile's calorie pill on next sign-in.
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.bodyWeightKg: 82.5});

      expect(prefs.bodyWeightKg, 82.5);
    });

    test('body_weight_kg of 0 / negative clears the local value (defensive)',
        () async {
      // A corrupted bag row must not poison the calorie path with a
      // zero weight (kcal = 0 × ... = 0). Clearing falls through to
      // the documented 70 kg default.
      final prefs = await freshPrefs();
      await prefs.setBodyWeightKg(80);
      expect(prefs.bodyWeightKg, 80);

      final svc = SettingsSyncService(preferences: prefs);
      svc.debugApplyUniversal({SettingsKeys.bodyWeightKg: 0});
      expect(prefs.bodyWeightKg, isNull);
    });

    test('body_weight_kg of non-numeric is silently ignored', () async {
      final prefs = await freshPrefs();
      await prefs.setBodyWeightKg(75);

      final svc = SettingsSyncService(preferences: prefs);
      svc.debugApplyUniversal({SettingsKeys.bodyWeightKg: 'eighty'});

      // Local value preserved — the bad bag value didn't clear it.
      expect(prefs.bodyWeightKg, 75);
    });

    test('privacy_default "public" overlays + flips newRunsArePublic',
        () async {
      // The user-flagged gap: setting was set in the UI but never
      // read at save time. The settings-sync overlay is the path
      // that carries the cloud value into local Preferences, and
      // `Preferences.newRunsArePublic` is what `run_screen` reads
      // to decide the saved-run visibility. Pin the chain.
      final prefs = await freshPrefs();
      expect(prefs.newRunsArePublic, isFalse);

      final svc = SettingsSyncService(preferences: prefs);
      svc.debugApplyUniversal({SettingsKeys.privacyDefault: 'public'});

      expect(prefs.privacyDefault, 'public');
      expect(prefs.newRunsArePublic, isTrue);
    });

    test('privacy_default "private" overlays + keeps newRunsArePublic false',
        () async {
      final prefs = await freshPrefs();
      await prefs.setPrivacyDefault('public');
      expect(prefs.newRunsArePublic, isTrue);

      final svc = SettingsSyncService(preferences: prefs);
      svc.debugApplyUniversal({SettingsKeys.privacyDefault: 'private'});

      expect(prefs.privacyDefault, 'private');
      expect(prefs.newRunsArePublic, isFalse);
    });

    test('privacy_default "followers" overlays but stays non-public', () async {
      // No DB column for followers-only yet (see Preferences test
      // group) — the overlay records the setter's value but
      // `newRunsArePublic` stays false until the schema grows.
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);
      svc.debugApplyUniversal({SettingsKeys.privacyDefault: 'followers'});

      expect(prefs.privacyDefault, 'followers');
      expect(prefs.newRunsArePublic, isFalse);
    });

    test('privacy_default of non-string is silently ignored', () async {
      final prefs = await freshPrefs();
      await prefs.setPrivacyDefault('public');

      final svc = SettingsSyncService(preferences: prefs);
      svc.debugApplyUniversal({SettingsKeys.privacyDefault: 42});

      // Local value preserved.
      expect(prefs.privacyDefault, 'public');
      expect(prefs.newRunsArePublic, isTrue);
    });

    test('empty bag is a no-op', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal(const {});

      expect(prefs.useMiles, isFalse);
      expect(prefs.goals, isEmpty);
    });

    test('unknown keys in the bag are ignored', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({
        'made_up_key': 'whatever',
        'another_unknown': 42,
      });

      expect(prefs.useMiles, isFalse);
    });
  });

  group('debugApplyDevice', () {
    test('voice_feedback_enabled true flips audioCues on', () async {
      final prefs = await freshPrefs();
      await prefs.setAudioCues(false);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice({SettingsKeys.voiceFeedbackEnabled: true});

      expect(prefs.audioCues, isTrue);
    });

    test('voice_feedback_interval_km maps to splitIntervalMetres', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice({SettingsKeys.voiceFeedbackIntervalKm: 1.5});

      expect(prefs.splitIntervalMetres, 1500);
    });

    test('voice_feedback_interval_km accepts integer-typed values', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice({SettingsKeys.voiceFeedbackIntervalKm: 2});

      expect(prefs.splitIntervalMetres, 2000);
    });

    test('non-bool voice_feedback_enabled is ignored', () async {
      final prefs = await freshPrefs();
      await prefs.setAudioCues(true);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice({SettingsKeys.voiceFeedbackEnabled: 'yes'});

      expect(prefs.audioCues, isTrue);
    });

    test('keep_screen_on flag round-trips', () async {
      final prefs = await freshPrefs();
      await prefs.setKeepScreenOn(false);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice({SettingsKeys.keepScreenOn: true});
      expect(prefs.keepScreenOn, isTrue);

      svc.debugApplyDevice({SettingsKeys.keepScreenOn: false});
      expect(prefs.keepScreenOn, isFalse);
    });

    test('empty device bag is a no-op', () async {
      final prefs = await freshPrefs();
      await prefs.setAudioCues(true);
      await prefs.setKeepScreenOn(true);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice(const {});

      expect(prefs.audioCues, isTrue);
      expect(prefs.keepScreenOn, isTrue);
    });
  });

  group('initial state', () {
    test('synced is false until onSignedIn runs', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      expect(svc.synced, isFalse);
      expect(svc.service, isNull);
      expect(svc.lastError, isNull);
    });

    test('push* methods are no-ops when settings is null', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      await svc.pushPreferredUnit();
      await svc.pushAudioCues();
      await svc.pushSplitInterval();
      await svc.pushKeepScreenOn();
      await svc.pushWeeklyDistanceGoal();
      await svc.updateUniversal({'key': 'value'});
      await svc.updateDevice({'key': 'value'});

      expect(svc.synced, isFalse);
    });
  });

  group('onSignedOut account reset (issue #231)', () {
    // The sign-in overlay only overwrites keys PRESENT in the next
    // account's bag, so any bag-mirrored pref left set at sign-out
    // carries the prior account's value into the next account.
    test('resets the bag-mirrored Preferences to defaults', () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      await prefs.setPrivacyDefault('public');
      await prefs.setBodyWeightKg(82.5);
      await prefs.setUseMiles(true);
      await prefs.setDefaultActivityType('cycle');
      await prefs.setCarbsPerHourG(90);
      await prefs.setFluidPerHourMl(750);
      await prefs.setAudioCues(false);
      await prefs.setSplitIntervalMetres(800);
      await prefs.upsertGoal(RunGoal(
        id: newGoalId(),
        period: GoalPeriod.week,
        distanceMetres: 40000,
      ));
      await prefs.setRunsLastFetchedAt(DateTime.utc(2026, 7, 1));

      await svc.onSignedOut();

      expect(prefs.privacyDefault, 'private',
          reason: "A's public-by-default must not make B's runs public");
      expect(prefs.newRunsArePublic, isFalse);
      expect(prefs.bodyWeightKg, isNull,
          reason: "A's body weight must not drive B's calorie estimates");
      expect(prefs.useMiles, isFalse);
      expect(prefs.defaultActivityType, 'run');
      expect(prefs.carbsPerHourG, 60, reason: 'documented fueling default');
      expect(prefs.fluidPerHourMl, 500);
      expect(prefs.audioCues, isTrue);
      expect(prefs.splitIntervalMetres, 0);
      expect(prefs.goals, isEmpty,
          reason: "A's goals must not render as B's");
      expect(prefs.runsLastFetchedAt, isNull,
          reason: "clearing the watermark forces B's first fetch down the "
              'FULL path — a delta against A\'s timestamp would skip '
              "B's older history");
    });

    test('drops the prior user\'s cached bags when the id is known',
        () async {
      final prefs = await freshPrefs();
      final cache = _MemCache();
      await cache.writeUniversal('user-a', {'privacy_zones': []});
      final svc = SettingsSyncService(preferences: prefs, cache: cache);

      await svc.onSignedOut(priorUserId: 'user-a');

      expect(cache.readUniversal('user-a'), isNull,
          reason: "A's cached bag (privacy zones included) must not stay "
              'on disk after sign-out');
    });

    test('reset is idempotent and safe with no cache / no prior id',
        () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);
      await svc.onSignedOut();
      await svc.onSignedOut(priorUserId: null);
      expect(prefs.privacyDefault, 'private');
    });
  });
}
