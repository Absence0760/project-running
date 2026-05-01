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
}
