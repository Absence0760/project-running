import 'package:core_models/core_models.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';

/// Registered key names for the `user_settings` / `user_device_settings` bags.
///
/// Keep in sync with [docs/backend/settings.md](../../../docs/backend/settings.md). Using
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
  /// Persona-hunt Round 3 finding Woman #2. Default true (every
  /// existing account stays findable until they actively opt out).
  /// `search_user_profiles` RPC (migration 20261015_001) reads
  /// this key.
  static const discoverableInSearch = 'discoverable_in_search';
  /// Persona-hunt Round 3 finding Woman #4. Array of
  /// `TrustedContact` rows (see `lib/trusted_contacts.dart` shape).
  /// The notify-on-overdue / panic-button delivery logic is
  /// deferred; this key just gives the data a stable home so
  /// runners can populate their list ahead of the feature.
  static const trustedContacts = 'trusted_contacts';
  static const coachPersonality = 'coach_personality';
  /// Which notification kinds are also delivered by email — `'all'` |
  /// `'important'` (default) | `'off'`. Read server-side by the Go
  /// worker's `notification_email` handler (migration 20261130_001);
  /// the in-app bell is unaffected.
  static const emailNotifications = 'email_notifications';
  static const weeklyMileageGoalMetres = 'weekly_mileage_goal_m';
  static const weekStartDay = 'week_start_day';
  static const mapStyle = 'map_style';
  static const unitsPaceFormat = 'units_pace_format';

  // Device (D)
  static const voiceFeedbackEnabled = 'voice_feedback_enabled';
  static const voiceFeedbackVerbosity = 'voice_feedback_verbosity';
  static const voiceFeedbackIntervalKm = 'voice_feedback_interval_km';
  static const hapticFeedbackEnabled = 'haptic_feedback_enabled';
  static const keepScreenOn = 'keep_screen_on';
}

/// Pluggable on-device cache for the two prefs bags. The mobile app
/// supplies a SharedPreferences-backed implementation so `SettingsService`
/// can pre-populate from disk before the network call, serve effective()
/// values when the user is offline, and queue writes to drain on next
/// successful network operation.
///
/// The api_client package itself ships a `_NoOpSettingsCache` default so
/// the class stays Flutter-binding-agnostic — server-side tests + the
/// web platform (which uses its own TS code path) don't pay for a
/// SharedPreferences dependency they don't need.
abstract class SettingsCache {
  /// Read the cached universal bag for [userId], or null when the cache
  /// has never been populated for this user.
  Map<String, dynamic>? readUniversal(String userId);

  /// Read the cached device bag for the (user, device) pair, or null.
  Map<String, dynamic>? readDevice(String userId, String deviceId);

  /// Persist the universal bag after a successful server fetch or
  /// optimistic local write.
  Future<void> writeUniversal(String userId, Map<String, dynamic> prefs);

  /// Persist the device bag.
  Future<void> writeDevice(
      String userId, String deviceId, Map<String, dynamic> prefs);

  /// Read the queue of writes that failed to push to the server during
  /// previous offline sessions. Drained on the next successful load.
  List<PendingSettingsChange> readPending(String userId, String deviceId);

  /// Append a failed write to the queue.
  Future<void> appendPending(
      String userId, String deviceId, PendingSettingsChange change);

  /// Clear the queue after a successful drain.
  Future<void> clearPending(String userId, String deviceId);

  /// Drop every cached row for [userId]. Called on sign-out so a
  /// subsequent sign-in on the same device can't read the previous
  /// user's data.
  Future<void> dropUser(String userId);
}

/// One queued offline write. Stored verbatim — `applyPrefsChanges` is
/// re-run on top of the live server bag when the queue drains, so
/// concurrent writes from other devices in the interim aren't clobbered.
class PendingSettingsChange {
  PendingSettingsChange({required this.isDevice, required this.changes});
  final bool isDevice;
  final Map<String, dynamic> changes;

  Map<String, dynamic> toJson() => {'isDevice': isDevice, 'changes': changes};
  factory PendingSettingsChange.fromJson(Map<String, dynamic> json) =>
      PendingSettingsChange(
        isDevice: json['isDevice'] as bool,
        changes: Map<String, dynamic>.from(json['changes'] as Map),
      );
}

class _NoOpSettingsCache implements SettingsCache {
  const _NoOpSettingsCache();
  @override
  Map<String, dynamic>? readUniversal(String userId) => null;
  @override
  Map<String, dynamic>? readDevice(String userId, String deviceId) => null;
  @override
  Future<void> writeUniversal(String userId, Map<String, dynamic> prefs) async {}
  @override
  Future<void> writeDevice(
      String userId, String deviceId, Map<String, dynamic> prefs) async {}
  @override
  List<PendingSettingsChange> readPending(String userId, String deviceId) =>
      const [];
  @override
  Future<void> appendPending(
      String userId, String deviceId, PendingSettingsChange change) async {}
  @override
  Future<void> clearPending(String userId, String deviceId) async {}
  @override
  Future<void> dropUser(String userId) async {}
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
///
/// Offline behaviour: when a [SettingsCache] is supplied, `load()`
/// pre-populates from cache so the UI has values immediately, then
/// refreshes from the server; if the server call fails the cached values
/// stay live. Writes apply optimistically to the cache + in-memory
/// state, then try to push to the server — failed pushes are queued and
/// drained on the next successful load.
class SettingsService {
  SettingsService({
    required String deviceId,
    required String platform,
    String? label,
    SettingsCache cache = const _NoOpSettingsCache(),
  })  : _deviceId = deviceId,
        _platform = platform,
        _label = label,
        _cache = cache;

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
  final SettingsCache _cache;

  Map<String, dynamic> _universal = <String, dynamic>{};
  Map<String, dynamic> _device = <String, dynamic>{};
  bool _serverHydrated = false;

  String get deviceId => _deviceId;

  /// True once the server fetch has succeeded at least once on this
  /// instance. `false` means the data in [universal] / [device] is
  /// either empty or sourced entirely from the local cache. Callers can
  /// use this to badge a "currently offline" affordance — reads + writes
  /// still work in either state.
  bool get isServerHydrated => _serverHydrated;

  /// Fetch both rows for the current user. Upserts empty rows if either is
  /// missing so subsequent writes don't race on insert. Returns self so
  /// call sites can chain (`await SettingsService(...).load()`).
  ///
  /// Offline path: when a [SettingsCache] is wired, this method first
  /// hydrates [_universal] + [_device] from the on-disk cache so reads
  /// are immediately accurate even if the network call fails. If the
  /// server fetch succeeds the cache is overwritten and any
  /// previously-queued offline writes are drained on top. If the server
  /// fetch fails the method **always** returns successfully — even
  /// without a cache — with empty bags and [isServerHydrated] = false.
  /// Writes during this state apply to the cache + pending queue, and
  /// drain on the next successful load. This is the load-bearing
  /// difference vs the prior "rethrow when no cache" behaviour: a
  /// signed-in user who first opens the app offline still gets a usable
  /// Settings screen — their edits queue cleanly until the network
  /// returns. (Sign-out / drop-cache scenarios still throw at the
  /// auth-check above.)
  Future<SettingsService> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final cachedU = _cache.readUniversal(userId);
    final cachedD = _cache.readDevice(userId, _deviceId);
    if (cachedU != null) _universal = Map<String, dynamic>.from(cachedU);
    if (cachedD != null) _device = Map<String, dynamic>.from(cachedD);

    try {
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
        try {
          await _client
              .from(UserDeviceSettingRow.table)
              .update(<String, dynamic>{
                UserDeviceSettingRow.colLastSeenAt:
                    DateTime.now().toUtc().toIso8601String(),
              })
              .eq(UserDeviceSettingRow.colUserId, userId)
              .eq(UserDeviceSettingRow.colDeviceId, _deviceId);
        } catch (_) {}
      }
      _serverHydrated = true;
      await _cache.writeUniversal(userId, _universal);
      await _cache.writeDevice(userId, _deviceId, _device);
      await _drainPending(userId);
    } catch (e) {
      _serverHydrated = false;
    }
    return this;
  }

  Future<void> _drainPending(String userId) async {
    final queue = _cache.readPending(userId, _deviceId);
    if (queue.isEmpty) return;
    for (final change in queue) {
      try {
        if (change.isDevice) {
          await _pushDevice(userId, change.changes);
        } else {
          await _pushUniversal(userId, change.changes);
        }
      } catch (_) {
        return;
      }
    }
    await _cache.clearPending(userId, _deviceId);
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
  /// **Offline behaviour:** the change is always applied to the local
  /// in-memory map + cache so [effective] reflects the user's edit
  /// immediately. The server push is best-effort — on failure (network
  /// down, server returns 5xx, etc.) the change is queued to a pending
  /// list and replayed on the next successful [load].
  ///
  /// **Concurrency note:** the server push re-fetches the current row
  /// before merging so a concurrent write from another device isn't
  /// silently overwritten. Mirrors the read-merge-write pattern in
  /// `apps/web/src/lib/settings.ts: updateUniversal`.
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    final userId = _requireUser();
    _universal = applyPrefsChanges(_universal, changes);
    await _cache.writeUniversal(userId, _universal);
    try {
      await _pushUniversal(userId, changes);
    } catch (_) {
      await _cache.appendPending(
        userId,
        _deviceId,
        PendingSettingsChange(isDevice: false, changes: changes),
      );
    }
  }

  /// Merge [changes] into the device bag and persist. Same null and
  /// offline semantics as [updateUniversal].
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    final userId = _requireUser();
    _device = applyPrefsChanges(_device, changes);
    await _cache.writeDevice(userId, _deviceId, _device);
    try {
      await _pushDevice(userId, changes);
    } catch (_) {
      await _cache.appendPending(
        userId,
        _deviceId,
        PendingSettingsChange(isDevice: true, changes: changes),
      );
    }
  }

  Future<void> _pushUniversal(
      String userId, Map<String, dynamic> changes) async {
    final fresh = await _client
        .from(UserSettingRow.table)
        .select(UserSettingRow.colPrefs)
        .eq(UserSettingRow.colUserId, userId)
        .maybeSingle();
    final base = _asMap(fresh?[UserSettingRow.colPrefs]);
    final merged = applyPrefsChanges(base, changes);
    await _client.from(UserSettingRow.table).update(<String, dynamic>{
      UserSettingRow.colPrefs: merged,
      UserSettingRow.colUpdatedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(UserSettingRow.colUserId, userId);
    _universal = merged;
    await _cache.writeUniversal(userId, _universal);
  }

  Future<void> _pushDevice(
      String userId, Map<String, dynamic> changes) async {
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
    await _cache.writeDevice(userId, _deviceId, _device);
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
