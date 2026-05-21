import 'package:core_models/core_models.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';

/// Registered key names for the `user_settings` / `user_device_settings` bags.
///
/// Keep in sync with [docs/settings.md](../../../docs/settings.md). Using
/// these constants everywhere (instead of string literals) is how we avoid
/// the class of bugs where one client writes `weeklyMileageGoal` and another
/// reads `weekly_mileage_goal_m`.
class SettingsKeys {
  SettingsKeys._();

  // Universal (U) or universal-default-with-device-override (UD)
  static const preferredUnit = 'preferred_unit';
  static const defaultActivityType = 'default_activity_type';
  static const hrZones = 'hr_zones';
  static const restingHrBpm = 'resting_hr_bpm';
  static const maxHrBpm = 'max_hr_bpm';
  static const bodyWeightKg = 'body_weight_kg';
  static const dateOfBirth = 'date_of_birth';
  static const privacyDefault = 'privacy_default';
  static const stravaAutoShare = 'strava_auto_share';
  static const coachPersonality = 'coach_personality';
  static const weeklyMileageGoalMetres = 'weekly_mileage_goal_m';
  static const weekStartDay = 'week_start_day';
  static const mapStyle = 'map_style';
  static const unitsPaceFormat = 'units_pace_format';
  static const autoPauseEnabled = 'auto_pause_enabled';
  static const autoPauseSpeedMps = 'auto_pause_speed_mps';

  // Device (D)
  static const voiceFeedbackEnabled = 'voice_feedback_enabled';
  static const voiceFeedbackIntervalKm = 'voice_feedback_interval_km';
  static const hapticFeedbackEnabled = 'haptic_feedback_enabled';
  static const keepScreenOn = 'keep_screen_on';
}

/// Typed accessor for `user_settings` + `user_device_settings`.
///
/// The DB stores two opaque jsonb bags; this class is the only place that
/// knows how to merge them. Effective lookup order is:
///
///   1. device override (`user_device_settings.prefs`)
///   2. universal value (`user_settings.prefs`)
///   3. fallback supplied by the caller
///
/// Absent keys and explicit `null` both fall through. Clients that want
/// "device explicitly opts out" should store a sentinel value (e.g. the
/// string `"off"`), never `null`.
class SettingsService {
  SettingsService({required String deviceId, required String platform, String? label})
      : _deviceId = deviceId,
        _platform = platform,
        _label = label;

  static SupabaseClient get _client {
    if (!ApiClient.isInitialized) {
      throw StateError(
        'SettingsService called before Supabase.initialize() resolved.',
      );
    }
    return Supabase.instance.client;
  }

  final String _deviceId;
  final String _platform;
  final String? _label;

  Map<String, dynamic> _universal = <String, dynamic>{};
  Map<String, dynamic> _device = <String, dynamic>{};

  String get deviceId => _deviceId;

  /// Fetch both rows for the current user. Upserts empty rows if either is
  /// missing so subsequent writes don't race on insert. Returns self so
  /// call sites can chain (`await SettingsService(...).load()`).
  Future<SettingsService> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final universalRes = await _client
        .from(UserSettingRow.table)
        .select()
        .eq(UserSettingRow.colUserId, userId)
        .maybeSingle();
    if (universalRes == null) {
      await _client.from(UserSettingRow.table).insert(<String, dynamic>{
        UserSettingRow.colUserId: userId,
        UserSettingRow.colPrefs: <String, dynamic>{},
      });
      _universal = <String, dynamic>{};
    } else {
      _universal = _asMap(universalRes['prefs']);
    }

    final deviceRes = await _client
        .from(UserDeviceSettingRow.table)
        .select()
        .eq(UserDeviceSettingRow.colUserId, userId)
        .eq(UserDeviceSettingRow.colDeviceId, _deviceId)
        .maybeSingle();
    if (deviceRes == null) {
      await _client.from(UserDeviceSettingRow.table).insert(<String, dynamic>{
        UserDeviceSettingRow.colUserId: userId,
        UserDeviceSettingRow.colDeviceId: _deviceId,
        UserDeviceSettingRow.colPlatform: _platform,
        if (_label != null) UserDeviceSettingRow.colLabel: _label,
        UserDeviceSettingRow.colPrefs: <String, dynamic>{},
      });
      _device = <String, dynamic>{};
    } else {
      _device = _asMap(deviceRes['prefs']);
      // Heartbeat so `last_seen_at` reflects when the device last opened.
      // Best-effort — a failure here doesn't block a signed-in launch.
      try {
        await _client
            .from(UserDeviceSettingRow.table)
            .update(<String, dynamic>{
              UserDeviceSettingRow.colLastSeenAt:
                  DateTime.now().toUtc().toIso8601String(),
            })
            .eq(UserDeviceSettingRow.colUserId, userId)
            .eq(UserDeviceSettingRow.colDeviceId, _deviceId);
      } catch (_) {
        // ignore
      }
    }
    return this;
  }

  /// Effective value for [key], falling back through device → universal →
  /// [fallback]. Caller narrows the dynamic via the usual Dart casts.
  T? effective<T>(String key, {T? fallback}) {
    if (_device.containsKey(key) && _device[key] != null) {
      return _device[key] as T?;
    }
    if (_universal.containsKey(key) && _universal[key] != null) {
      return _universal[key] as T?;
    }
    return fallback;
  }

  Map<String, dynamic> get universal => Map.unmodifiable(_universal);
  Map<String, dynamic> get device => Map.unmodifiable(_device);

  /// Merge [changes] into the universal bag and persist. Existing keys
  /// not in [changes] are preserved. Keys set to `null` in [changes]
  /// are removed from the bag (not stored as null).
  ///
  /// **Concurrency note:** re-fetches the current row from the DB
  /// before merging so a concurrent write from another device (the
  /// user's other phone, the watch, the web tab in another window)
  /// isn't silently overwritten by this client's stale cache. Mirrors
  /// the read-merge-write pattern in `apps/web/src/lib/settings.ts:
  /// updateUniversal`. Before this fix, a mobile client whose
  /// `_universal` was loaded at sign-in would overwrite any
  /// universal-prefs key the watch / another phone wrote in the
  /// interim — silent data loss across devices.
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    final userId = _requireUser();
    final fresh = await _client
        .from(UserSettingRow.table)
        .select(UserSettingRow.colPrefs)
        .eq(UserSettingRow.colUserId, userId)
        .maybeSingle();
    final base = _asMap(fresh?[UserSettingRow.colPrefs]);
    final merged = applyPrefsChanges(base, changes);
    await _client.from(UserSettingRow.table).update(<String, dynamic>{
      UserSettingRow.colPrefs: merged,
      UserSettingRow.colUpdatedAt:
          DateTime.now().toUtc().toIso8601String(),
    }).eq(UserSettingRow.colUserId, userId);
    _universal = merged;
  }

  /// Merge [changes] into the device bag and persist. Same null
  /// semantics as [updateUniversal]. Re-fetches before merging for
  /// the same concurrency reason — the row is keyed on
  /// `(user_id, device_id)` so cross-device collisions are unlikely,
  /// but a second tab in the same browser writing the same device
  /// row in parallel would otherwise lose one of the writes.
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    final userId = _requireUser();
    final fresh = await _client
        .from(UserDeviceSettingRow.table)
        .select(UserDeviceSettingRow.colPrefs)
        .eq(UserDeviceSettingRow.colUserId, userId)
        .eq(UserDeviceSettingRow.colDeviceId, _deviceId)
        .maybeSingle();
    final base = _asMap(fresh?[UserDeviceSettingRow.colPrefs]);
    final merged = applyPrefsChanges(base, changes);
    await _client
        .from(UserDeviceSettingRow.table)
        .update(<String, dynamic>{
          UserDeviceSettingRow.colPrefs: merged,
          UserDeviceSettingRow.colUpdatedAt:
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq(UserDeviceSettingRow.colUserId, userId)
        .eq(UserDeviceSettingRow.colDeviceId, _deviceId);
    _device = merged;
  }

  String _requireUser() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    return userId;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return <String, dynamic>{};
  }

  /// Pure helper: apply [changes] on top of [base], returning a fresh
  /// map. Keys with null values in [changes] are removed from the
  /// result (not stored as null). Keys not in [changes] are preserved
  /// from [base]. Lifted to a `@visibleForTesting` static so the
  /// merge semantics — the load-bearing part of the read-merge-write
  /// concurrency fix — can be unit-tested without standing up
  /// Supabase.
  ///
  /// Mirrors the merge loop in `apps/web/src/lib/settings.ts:
  /// updateUniversal` / `updateDevice`. Subtle difference vs the
  /// JS version: Dart maps don't have a JS-style `undefined`, so the
  /// "delete key" trigger is purely `value == null`. JS treats both
  /// `null` and `undefined` as delete-triggers; the resulting bag
  /// shape is identical.
  @visibleForTesting
  static Map<String, dynamic> applyPrefsChanges(
    Map<String, dynamic> base,
    Map<String, dynamic> changes,
  ) {
    final merged = Map<String, dynamic>.from(base);
    for (final entry in changes.entries) {
      if (entry.value == null) {
        merged.remove(entry.key);
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }
}
