import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  static SupabaseClient get _client => Supabase.instance.client;

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

  /// Merge [changes] into the universal bag and persist. Existing keys not
  /// in [changes] are preserved. Keys set to `null` in [changes] are
  /// removed from the bag (not stored as null).
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    final userId = _requireUser();
    final merged = Map<String, dynamic>.from(_universal);
    for (final entry in changes.entries) {
      if (entry.value == null) {
        merged.remove(entry.key);
      } else {
        merged[entry.key] = entry.value;
      }
    }
    await _client.from(UserSettingRow.table).update(<String, dynamic>{
      UserSettingRow.colPrefs: merged,
      UserSettingRow.colUpdatedAt:
          DateTime.now().toUtc().toIso8601String(),
    }).eq(UserSettingRow.colUserId, userId);
    _universal = merged;
  }

  /// Merge [changes] into the device bag and persist. Same null semantics
  /// as [updateUniversal].
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    final userId = _requireUser();
    final merged = Map<String, dynamic>.from(_device);
    for (final entry in changes.entries) {
      if (entry.value == null) {
        merged.remove(entry.key);
      } else {
        merged[entry.key] = entry.value;
      }
    }
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
}
