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

class _FakeSettingsService implements SettingsService {
  final List<Map<String, dynamic>> universalWrites = [];
  final List<Map<String, dynamic>> deviceWrites = [];

  @override
  Map<String, dynamic> get universal => const <String, dynamic>{};
  @override
  Map<String, dynamic> get device => const <String, dynamic>{};
  @override
  bool get isServerHydrated => true;
  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
  }

  @override
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    deviceWrites.add(changes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    test('voice_cue_types map overlays per-cue toggles, absent ids stay on',
        () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice({
        SettingsKeys.voiceCueTypes: {
          VoiceCue.splits: false,
          VoiceCue.cutoffCatchUp: false,
          'future_unknown_cue': false,
          'not_a_bool': 'nope',
        },
      });

      expect(prefs.voiceCueEnabled(VoiceCue.splits), isFalse);
      expect(prefs.voiceCueEnabled(VoiceCue.cutoffCatchUp), isFalse);
      expect(prefs.voiceCueEnabled(VoiceCue.paceAlerts), isTrue);
      expect(prefs.voiceCueEnabled('future_unknown_cue'), isFalse);
      expect(prefs.voiceCueEnabled('not_a_bool'), isTrue);
    });

    test('a universal voice_cue_types map reaches the recorder', () async {
      // Web's settings page can only write the universal bag — the browser
      // is its own device row and never records — so a per-cue choice made
      // there is dead unless the universal overlay reads the key too.
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({
        SettingsKeys.voiceCueTypes: {VoiceCue.splits: false},
      });

      expect(prefs.voiceCueEnabled(VoiceCue.splits), isFalse);
      expect(prefs.voiceCueEnabled(VoiceCue.paceAlerts), isTrue);
    });

    test('a device voice_cue_types entry overrides the universal one',
        () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({
        SettingsKeys.voiceCueTypes: {
          VoiceCue.splits: false,
          VoiceCue.offRoute: false,
        },
      });
      svc.debugApplyDevice({
        SettingsKeys.voiceCueTypes: {VoiceCue.splits: true},
      });

      expect(prefs.voiceCueEnabled(VoiceCue.splits), isTrue);
      expect(prefs.voiceCueEnabled(VoiceCue.offRoute), isFalse);
    });

    test('a universal voice_feedback_enabled reaches the recorder', () async {
      // Web's master spoken-cues toggle can only write the universal bag —
      // the browser is its own device row and never records — so the choice
      // is dead unless the universal overlay reads the key too.
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.voiceFeedbackEnabled: false});

      expect(prefs.audioCues, isFalse);
    });

    test('a device voice_feedback_enabled overrides the universal one',
        () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.voiceFeedbackEnabled: false});
      svc.debugApplyDevice({SettingsKeys.voiceFeedbackEnabled: true});

      expect(prefs.audioCues, isTrue);
    });

    test('voice_feedback_enabled absent in both bags keeps the local default',
        () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal(const {});
      svc.debugApplyDevice(const {});

      expect(prefs.audioCues, isTrue);
    });

    test('non-bool universal voice_feedback_enabled is dropped, not coerced',
        () async {
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyUniversal({SettingsKeys.voiceFeedbackEnabled: 'yes'});
      expect(prefs.audioCues, isTrue);

      await prefs.setAudioCues(false);
      svc.debugApplyUniversal({SettingsKeys.voiceFeedbackEnabled: 1});
      expect(prefs.audioCues, isFalse);
    });

    test('voice_cue_types merge keeps locally-toggled ids the bag omits',
        () async {
      final prefs = await freshPrefs();
      await prefs.setVoiceCueEnabled(VoiceCue.offRoute, false);
      final svc = SettingsSyncService(preferences: prefs);

      svc.debugApplyDevice({
        SettingsKeys.voiceCueTypes: {VoiceCue.splits: false},
      });

      expect(prefs.voiceCueEnabled(VoiceCue.offRoute), isFalse);
      expect(prefs.voiceCueEnabled(VoiceCue.splits), isFalse);
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

    test('writes load the service on demand when onSignedIn never ran',
        () async {
      // A null service used to make every write return silently: the setup
      // wizard's whole answer bag (units, primary goal, notifications) was
      // discarded with nothing thrown and nothing queued. `load()` degrades
      // to the on-disk cache + pending queue rather than failing, so "not
      // loaded yet" is never a reason to drop a write.
      final prefs = await freshPrefs();
      final fake = _FakeSettingsService();
      final svc = SettingsSyncService(
        preferences: prefs,
        serviceLoader: () async => fake,
      );

      await svc.updateUniversal({SettingsKeys.primaryGoal: '10k'});
      await svc.updateDevice({SettingsKeys.keepScreenOn: true});
      await prefs.setUseMiles(true);
      await svc.pushPreferredUnit();

      expect(fake.universalWrites, [
        {SettingsKeys.primaryGoal: '10k'},
        {SettingsKeys.preferredUnit: 'mi'},
      ]);
      expect(fake.deviceWrites, [
        {SettingsKeys.keepScreenOn: true},
      ]);
      expect(svc.synced, isTrue);
      expect(svc.service, same(fake));
    });

    test('a write recovers after onSignedIn failed to load', () async {
      final prefs = await freshPrefs();
      final fake = _FakeSettingsService();
      var attempt = 0;
      final svc = SettingsSyncService(
        preferences: prefs,
        serviceLoader: () async {
          attempt += 1;
          if (attempt == 1) throw Exception('transient load failure');
          return fake;
        },
      );

      await svc.onSignedIn();
      expect(svc.service, isNull);
      expect(svc.synced, isFalse);

      await svc.updateUniversal({SettingsKeys.privacyDefault: 'private'});

      expect(fake.universalWrites, [
        {SettingsKeys.privacyDefault: 'private'},
      ]);
      expect(svc.synced, isTrue);
    });

    test('a write with no loadable service throws instead of reporting success',
        () async {
      // The keys routed through updateUniversal have no local Preferences
      // mirror, so a swallowed failure loses the value outright. The caller
      // has to be able to see it.
      final prefs = await freshPrefs();
      final svc = SettingsSyncService(
        preferences: prefs,
        serviceLoader: () async => throw Exception('Not authenticated'),
      );

      await expectLater(
        svc.updateUniversal({SettingsKeys.primaryGoal: '10k'}),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        svc.updateDevice({SettingsKeys.keepScreenOn: true}),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        svc.pushPreferredUnit(),
        throwsA(isA<Exception>()),
      );
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
