import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// Tests for the [SettingsCache] interface contract — the in-memory
/// fake under test mirrors what the SharedPreferences-backed mobile
/// implementation must guarantee.
///
/// Reason: the mobile twin (apps/mobile_*) supplies a real
/// SharedPreferences-backed cache so signed-in users keep reading and
/// writing bag-backed prefs (DOB, HR zones, weekly goal, etc.) while
/// offline. The cache + drain semantics are the load-bearing piece;
/// pinning the contract here means a future implementer can drop in
/// a different storage (Hive, SQLite, NSUserDefaults) without
/// re-deriving the wire shape.
class _FakeCache implements SettingsCache {
  final Map<String, Map<String, dynamic>> universals = {};
  final Map<String, Map<String, dynamic>> devices = {};
  final Map<String, List<PendingSettingsChange>> pending = {};
  final List<String> dropped = [];

  @override
  Map<String, dynamic>? readUniversal(String userId) => universals[userId];

  @override
  Map<String, dynamic>? readDevice(String userId, String deviceId) =>
      devices['${userId}_$deviceId'];

  @override
  Future<void> writeUniversal(
      String userId, Map<String, dynamic> prefs) async {
    universals[userId] = Map<String, dynamic>.from(prefs);
  }

  @override
  Future<void> writeDevice(
      String userId, String deviceId, Map<String, dynamic> prefs) async {
    devices['${userId}_$deviceId'] = Map<String, dynamic>.from(prefs);
  }

  @override
  List<PendingSettingsChange> readPending(String userId, String deviceId) =>
      pending['${userId}_$deviceId'] ?? const [];

  @override
  Future<void> appendPending(String userId, String deviceId,
      PendingSettingsChange change) async {
    pending.putIfAbsent('${userId}_$deviceId', () => []).add(change);
  }

  @override
  Future<void> clearPending(String userId, String deviceId) async {
    pending.remove('${userId}_$deviceId');
  }

  @override
  Future<void> dropUser(String userId) async {
    dropped.add(userId);
    universals.remove(userId);
    devices.removeWhere((key, _) => key.startsWith('${userId}_'));
    pending.removeWhere((key, _) => key.startsWith('${userId}_'));
  }
}

void main() {
  group('PendingSettingsChange JSON round-trip', () {
    test('universal change survives encode + decode', () {
      final original = PendingSettingsChange(
        isDevice: false,
        changes: {'resting_hr_bpm': 52, 'date_of_birth': '1990-01-01'},
      );
      final clone = PendingSettingsChange.fromJson(original.toJson());
      expect(clone.isDevice, isFalse);
      expect(clone.changes['resting_hr_bpm'], 52);
      expect(clone.changes['date_of_birth'], '1990-01-01');
    });

    test('device change is tagged isDevice=true', () {
      final original = PendingSettingsChange(
        isDevice: true,
        changes: {'voice_feedback_enabled': false},
      );
      final clone = PendingSettingsChange.fromJson(original.toJson());
      expect(clone.isDevice, isTrue);
      expect(clone.changes, {'voice_feedback_enabled': false});
    });

    test('null change values (delete-marker) round-trip', () {
      final original = PendingSettingsChange(
        isDevice: false,
        changes: {'weekly_mileage_goal_m': null},
      );
      final clone = PendingSettingsChange.fromJson(original.toJson());
      expect(clone.changes.containsKey('weekly_mileage_goal_m'), isTrue);
      expect(clone.changes['weekly_mileage_goal_m'], isNull);
    });
  });

  group('SettingsCache fake contract', () {
    test('readUniversal returns null on miss', () {
      final c = _FakeCache();
      expect(c.readUniversal('u1'), isNull);
    });

    test('writeUniversal then readUniversal returns the same map', () async {
      final c = _FakeCache();
      await c.writeUniversal('u1', {'preferred_unit': 'mi'});
      expect(c.readUniversal('u1'), {'preferred_unit': 'mi'});
    });

    test('device cache is keyed by (userId, deviceId) — not shared',
        () async {
      final c = _FakeCache();
      await c.writeDevice('u1', 'phone', {'keep_screen_on': true});
      await c.writeDevice('u1', 'watch', {'keep_screen_on': false});
      expect(c.readDevice('u1', 'phone'), {'keep_screen_on': true});
      expect(c.readDevice('u1', 'watch'), {'keep_screen_on': false});
    });

    test('appendPending + readPending preserve order', () async {
      final c = _FakeCache();
      await c.appendPending('u1', 'd1',
          PendingSettingsChange(isDevice: false, changes: {'a': 1}));
      await c.appendPending('u1', 'd1',
          PendingSettingsChange(isDevice: true, changes: {'b': 2}));
      final q = c.readPending('u1', 'd1');
      expect(q, hasLength(2));
      expect(q[0].isDevice, isFalse);
      expect(q[0].changes['a'], 1);
      expect(q[1].isDevice, isTrue);
      expect(q[1].changes['b'], 2);
    });

    test('clearPending empties the queue but leaves cached bags alone',
        () async {
      final c = _FakeCache();
      await c.writeUniversal('u1', {'preferred_unit': 'km'});
      await c.appendPending('u1', 'd1',
          PendingSettingsChange(isDevice: false, changes: {'a': 1}));
      await c.clearPending('u1', 'd1');
      expect(c.readPending('u1', 'd1'), isEmpty);
      expect(c.readUniversal('u1'), {'preferred_unit': 'km'},
          reason: 'clearPending must NOT drop the universal cache row.');
    });

    test('dropUser removes everything for that user, leaves others intact',
        () async {
      final c = _FakeCache();
      await c.writeUniversal('u1', {'a': 1});
      await c.writeUniversal('u2', {'a': 2});
      await c.writeDevice('u1', 'd1', {'k': 'v'});
      await c.appendPending('u1', 'd1',
          PendingSettingsChange(isDevice: false, changes: {'a': 1}));
      await c.dropUser('u1');
      expect(c.readUniversal('u1'), isNull);
      expect(c.readDevice('u1', 'd1'), isNull);
      expect(c.readPending('u1', 'd1'), isEmpty);
      expect(c.readUniversal('u2'), {'a': 2},
          reason: 'dropUser must scope strictly to the named user.');
    });
  });
}
