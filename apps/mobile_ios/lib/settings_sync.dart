import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

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
///
/// **Ported verbatim from `mobile_android/lib/settings_sync.dart`** — keep
/// in sync with the Android twin until this is lifted into a shared
/// package. Any behavioural change here must land on Android too.
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

  void _applyUniversal(Map<String, dynamic> prefs) {
    final unit = prefs[SettingsKeys.preferredUnit];
    if (unit is String) {
      final useMiles = unit == 'mi';
      if (useMiles != preferences.useMiles) {
        preferences.setUseMiles(useMiles);
      }
    }
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
    return Platform.operatingSystemVersion;
  }
}
