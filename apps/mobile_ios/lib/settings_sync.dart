import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'goals.dart';
import 'preferences.dart';

/// Bridge between local [Preferences] (SharedPreferences) and the
/// cross-device [SettingsService] (Supabase jsonb bags).
///
/// Local storage stays source-of-truth at runtime so the app works
/// offline. On sign-in we pull the cloud universal bag and overlay any
/// keys onto local state; on user-initiated changes we push back to the
/// cloud. The cloud is never the live read path for UI.
///
/// Known keys are registered in [docs/settings.md](../../docs/settings.md).
class SettingsSyncService extends ChangeNotifier {
  SettingsSyncService({
    required this.preferences,
  });

  final Preferences preferences;
  SettingsService? _settings;

  bool _synced = false;
  String? _lastError;

  SettingsService? get service => _settings;
  bool get synced => _synced;
  String? get lastError => _lastError;

  /// Called when the user signs out. Drops the cached [SettingsService]
  /// instance (which holds the previously-signed-in user's universal +
  /// device bags) so a subsequent sign-in by a DIFFERENT user on the
  /// same device doesn't read the previous user's settings during the
  /// brief window before [onSignedIn] re-fetches. Without this, a
  /// shared device shows User A's last-loaded preferred-unit / split
  /// interval / privacy zones to User B until B's sign-in completes
  /// the round-trip. Cosmetic on its own, but the privacy-zones path
  /// specifically matters because [LiveBroadcaster.privacyZonesProvider]
  /// reads the cached bag on every push — leaking the previous user's
  /// zones to a new user's broadcast would be a real privacy regression.
  /// Idempotent — safe to call multiple times.
  Future<void> onSignedOut() async {
    _settings = null;
    _synced = false;
    _lastError = null;
    notifyListeners();
  }

  /// Called after a successful sign-in. Fetches both bags, overlays the
  /// universal bag onto local [Preferences], and returns. Silent if the
  /// user isn't authenticated.
  Future<void> onSignedIn() async {
    try {
      _settings = await SettingsService(
        deviceId: preferences.deviceId,
        platform: _platformTag(),
        label: _deviceLabel(),
      ).load();
      _applyUniversal(_settings!.universal);
      _applyDevice(_settings!.device);
      _synced = true;
      _lastError = null;
    } catch (e) {
      _settings = null;
      _synced = false;
      _lastError = e.toString();
    }
    notifyListeners();
  }

  /// Push the user's current distance-unit choice to the universal bag.
  /// Call from the settings-screen toggle handler; noop when we haven't
  /// synced yet (e.g. user is offline / not signed in).
  Future<void> pushPreferredUnit() async {
    final s = _settings;
    if (s == null) return;
    await s.updateUniversal(<String, dynamic>{
      SettingsKeys.preferredUnit: preferences.useMiles ? 'mi' : 'km',
    });
    notifyListeners();
  }

  /// Push the user's spoken-split-announcements toggle to the device bag.
  Future<void> pushAudioCues() async {
    final s = _settings;
    if (s == null) return;
    await s.updateDevice(<String, dynamic>{
      SettingsKeys.voiceFeedbackEnabled: preferences.audioCues,
    });
    notifyListeners();
  }

  /// Push the user's custom split interval to the device bag. The bag
  /// stores km as a double per settings.md; a local value of 0 ("use the
  /// activity-type default") clears the key so the default logic still
  /// runs.
  Future<void> pushSplitInterval() async {
    final s = _settings;
    if (s == null) return;
    final metres = preferences.splitIntervalMetres;
    await s.updateDevice(<String, dynamic>{
      SettingsKeys.voiceFeedbackIntervalKm:
          metres > 0 ? metres / 1000.0 : null,
    });
    notifyListeners();
  }

  /// Merge [changes] into the universal bag. Thin passthrough used by the
  /// settings screen for keys that don't have a local [Preferences]
  /// mirror — the screen reads from and writes to the bag directly.
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    final s = _settings;
    if (s == null) return;
    await s.updateUniversal(changes);
    notifyListeners();
  }

  /// Merge [changes] into the device bag. See [updateUniversal].
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    final s = _settings;
    if (s == null) return;
    await s.updateDevice(changes);
    notifyListeners();
  }

  /// Test-only: drives the universal-bag overlay logic against a
  /// supplied Preferences instance. Lets unit tests exercise the
  /// key-by-key mapping without a Supabase round-trip.
  @visibleForTesting
  void debugApplyUniversal(Map<String, dynamic> prefs) =>
      _applyUniversal(prefs);

  /// Test-only: drives the device-bag overlay logic. See [debugApplyUniversal].
  @visibleForTesting
  void debugApplyDevice(Map<String, dynamic> prefs) => _applyDevice(prefs);

  void _applyUniversal(Map<String, dynamic> prefs) {
    final unit = prefs[SettingsKeys.preferredUnit];
    if (unit is String) {
      final useMiles = unit == 'mi';
      if (useMiles != preferences.useMiles) {
        preferences.setUseMiles(useMiles);
      }
    }
    final dat = prefs[SettingsKeys.defaultActivityType];
    if (dat is String && dat.isNotEmpty && dat != preferences.defaultActivityType) {
      preferences.setDefaultActivityType(dat);
    }
    // Body weight in kg — drives the run-detail calorie estimate.
    // null / non-positive clears the local cache so the calorie path
    // falls through to its documented 70 kg default.
    final bw = prefs[SettingsKeys.bodyWeightKg];
    if (bw is num) {
      preferences.setBodyWeightKg(bw > 0 ? bw.toDouble() : null);
    }
    // Default visibility for newly-saved runs. Public ⇒ is_public=true
    // on save, followers/private/unknown ⇒ false (no followers-only
    // column on `runs` today, conservative default).
    final pd = prefs[SettingsKeys.privacyDefault];
    if (pd is String) {
      preferences.setPrivacyDefault(pd);
    }
    // Seed a weekly distance RunGoal from the universal bag value when
    // the local list doesn't already have one. We never *replace* an
    // existing local goal — the dashboard's editor is the richer
    // surface (multi-target, monthly, etc.) and wins on edit. Pushing
    // the *other* direction (local → bag) is handled in
    // [pushWeeklyDistanceGoal].
    final raw = prefs[SettingsKeys.weeklyMileageGoalMetres];
    if (raw is num && raw > 0) {
      final hasWeeklyDistance = preferences.goals.any((g) =>
          g.period == GoalPeriod.week && g.distanceMetres != null);
      if (!hasWeeklyDistance) {
        preferences.upsertGoal(RunGoal(
          id: newGoalId(),
          period: GoalPeriod.week,
          distanceMetres: raw.toDouble(),
        ));
      }
    }
  }

  /// Push the user's *single* weekly-distance goal back to the universal
  /// bag, or clear the bag when it's removed. Multi-target / monthly /
  /// pace goals stay client-only — the bag scalar can't represent them.
  Future<void> pushWeeklyDistanceGoal() async {
    final s = _settings;
    if (s == null) return;
    final weekly = preferences.goals.firstWhere(
      (g) => g.period == GoalPeriod.week && g.distanceMetres != null,
      orElse: () => const RunGoal(id: '', period: GoalPeriod.week),
    );
    await s.updateUniversal(<String, dynamic>{
      SettingsKeys.weeklyMileageGoalMetres:
          weekly.distanceMetres == null ? null : weekly.distanceMetres!.round(),
    });
    notifyListeners();
  }

  void _applyDevice(Map<String, dynamic> prefs) {
    final voice = prefs[SettingsKeys.voiceFeedbackEnabled];
    if (voice is bool && voice != preferences.audioCues) {
      preferences.setAudioCues(voice);
    }
    final intervalKm = prefs[SettingsKeys.voiceFeedbackIntervalKm];
    if (intervalKm is num) {
      final metres = (intervalKm * 1000).round();
      if (metres != preferences.splitIntervalMetres) {
        preferences.setSplitIntervalMetres(metres);
      }
    }
    final keep = prefs[SettingsKeys.keepScreenOn];
    if (keep is bool && keep != preferences.keepScreenOn) {
      preferences.setKeepScreenOn(keep);
    }
  }

  /// Push the user's keep-screen-on toggle to the device bag.
  Future<void> pushKeepScreenOn() async {
    final s = _settings;
    if (s == null) return;
    await s.updateDevice(<String, dynamic>{
      SettingsKeys.keepScreenOn: preferences.keepScreenOn,
    });
    notifyListeners();
  }

  static String _platformTag() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _deviceLabel() {
    // `Platform.operatingSystemVersion` is a verbose string — good enough
    // for a human-readable label in the per-device list on the web.
    return Platform.operatingSystemVersion;
  }
}
