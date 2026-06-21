import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed [SettingsCache]. Keys are scoped by user id
/// (and, for the device bag, by device id too) so a sign-out + sign-in
/// as a different user on the same device can't read another user's
/// data. Pending writes are JSON-encoded so the persistence layer stays
/// schema-flexible — when a new key joins the registry it round-trips
/// without any cache migration.
class SharedPrefsSettingsCache implements SettingsCache {
  SharedPrefsSettingsCache(this._prefs);
  final SharedPreferences _prefs;

  static const _kUniversal = 'settings_cache_universal_';
  static const _kDevice = 'settings_cache_device_';
  static const _kPending = 'settings_cache_pending_';

  @override
  Map<String, dynamic>? readUniversal(String userId) =>
      _decodeMap(_prefs.getString('$_kUniversal$userId'));

  @override
  Map<String, dynamic>? readDevice(String userId, String deviceId) =>
      _decodeMap(_prefs.getString('$_kDevice${userId}_$deviceId'));

  @override
  Future<void> writeUniversal(
      String userId, Map<String, dynamic> prefs) async {
    await _prefs.setString('$_kUniversal$userId', jsonEncode(prefs));
  }

  @override
  Future<void> writeDevice(
      String userId, String deviceId, Map<String, dynamic> prefs) async {
    await _prefs.setString(
        '$_kDevice${userId}_$deviceId', jsonEncode(prefs));
  }

  @override
  List<PendingSettingsChange> readPending(String userId, String deviceId) {
    final raw = _prefs.getString('$_kPending${userId}_$deviceId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              PendingSettingsChange.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('settings_cache: corrupt pending queue, dropping: $e');
      return const [];
    }
  }

  @override
  Future<void> appendPending(String userId, String deviceId,
      PendingSettingsChange change) async {
    final queue = List<PendingSettingsChange>.from(readPending(userId, deviceId));
    queue.add(change);
    await _prefs.setString(
      '$_kPending${userId}_$deviceId',
      jsonEncode(queue.map((c) => c.toJson()).toList()),
    );
  }

  @override
  Future<void> clearPending(String userId, String deviceId) async {
    await _prefs.remove('$_kPending${userId}_$deviceId');
  }

  @override
  Future<void> dropUser(String userId) async {
    // The universal key is unanchored (`..._<userId>`), so it must match
    // EXACTLY — a `startsWith` would sweep a sibling user whose id is a
    // prefix (e.g. dropping `u1` would also clear `u12`). Device + pending
    // keys carry a trailing `_<deviceId>`, so anchoring on the trailing
    // underscore is enough. Mirrors web's LocalStoragePrefsCache (§79).
    final universalKey = '$_kUniversal$userId';
    final keys = _prefs.getKeys().where((k) =>
        k == universalKey ||
        k.startsWith('$_kDevice${userId}_') ||
        k.startsWith('$_kPending${userId}_'));
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }

  Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (e) {
      debugPrint('settings_cache: corrupt cached bag, dropping: $e');
    }
    return null;
  }
}
