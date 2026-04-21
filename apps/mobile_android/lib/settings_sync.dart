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
      'preferred_unit': preferences.useMiles ? 'mi' : 'km',
    });
    notifyListeners();
  }

  void _applyUniversal(Map<String, dynamic> prefs) {
    final unit = prefs['preferred_unit'];
    if (unit is String) {
      final useMiles = unit == 'mi';
      if (useMiles != preferences.useMiles) {
        preferences.setUseMiles(useMiles);
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
    // `Platform.operatingSystemVersion` is a verbose string — good enough
    // for a human-readable label in the per-device list on the web.
    return Platform.operatingSystemVersion;
  }
}
