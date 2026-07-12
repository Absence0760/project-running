import 'dart:typed_data';

/// Pure Dart mirror of the custom watch's `watch_core::settings` wire format.
///
/// The phone pushes the user's config to the watch as a fixed little-endian
/// frame the firmware decodes:
///
///   magic("SET1", 4) | version(1) | flags(1) | present fields...
///
/// `flags` is a bitfield of which optional fields follow, in bit order:
/// bit0 max_hr, bit1 pacer, bit2 gear, bit3 zone_ceiling, bit4 sea_level_pa,
/// bit5 fuel. Only the present fields are written, so a partial update is a
/// shorter frame; a fully populated frame is 37 bytes.
///
/// Deliberately pure — no BLE, no platform channels — so [encode] is
/// unit-testable against a frozen golden vector shared with the Rust test.
/// The phone only ever encodes (the watch decodes), mirroring how the
/// run-sync path (`sim_watch_sync.dart`) is the phone's decode side.
const int _settingsVersion = 0x01;

const int _flagMaxHr = 0x01;
const int _flagPacer = 0x02;
const int _flagGear = 0x04;
const int _flagZoneCeiling = 0x08;
const int _flagSeaLevel = 0x10;
const int _flagFuel = 0x20;

class WatchSettings {
  final int? maxHr;
  final ({int distanceM, int timeS})? pacer;

  /// A gear goal. A [targetM] of null (or 0.0) encodes "no target / untracked";
  /// a real target is always > 0.
  final ({double baselineM, double? targetM})? gear;

  /// 0 clears the ceiling (off); 1..=4 sets the ceiling zone.
  final int? zoneCeiling;

  /// QNH sea-level reference pressure (Pa) for the watch's barometric-altitude
  /// calculation — the mountain/desert weather-front recalibration.
  final double? seaLevelPa;

  /// Fuel-reminder cadences (seconds of moving time) overriding the watch's
  /// temperate fuel_plan defaults — the desert/hot-weather case.
  final ({int drinkIntervalS, int eatIntervalS})? fuel;

  const WatchSettings({
    this.maxHr,
    this.pacer,
    this.gear,
    this.zoneCeiling,
    this.seaLevelPa,
    this.fuel,
  });

  Uint8List encode() {
    var len = 6;
    if (maxHr != null) len += 2;
    if (pacer != null) len += 8;
    if (gear != null) len += 8;
    if (zoneCeiling != null) len += 1;
    if (seaLevelPa != null) len += 4;
    if (fuel != null) len += 8;

    final out = ByteData(len);
    out.setUint8(0, 0x53); // S
    out.setUint8(1, 0x45); // E
    out.setUint8(2, 0x54); // T
    out.setUint8(3, 0x31); // 1
    out.setUint8(4, _settingsVersion);

    var flags = 0;
    if (maxHr != null) flags |= _flagMaxHr;
    if (pacer != null) flags |= _flagPacer;
    if (gear != null) flags |= _flagGear;
    if (zoneCeiling != null) flags |= _flagZoneCeiling;
    if (seaLevelPa != null) flags |= _flagSeaLevel;
    if (fuel != null) flags |= _flagFuel;
    out.setUint8(5, flags);

    var off = 6;
    if (maxHr != null) {
      out.setUint16(off, maxHr!, Endian.little);
      off += 2;
    }
    if (pacer != null) {
      out.setUint32(off, pacer!.distanceM, Endian.little);
      out.setUint32(off + 4, pacer!.timeS, Endian.little);
      off += 8;
    }
    if (gear != null) {
      out.setFloat32(off, gear!.baselineM, Endian.little);
      out.setFloat32(off + 4, gear!.targetM ?? 0.0, Endian.little);
      off += 8;
    }
    if (zoneCeiling != null) {
      out.setUint8(off, zoneCeiling!);
      off += 1;
    }
    if (seaLevelPa != null) {
      out.setFloat32(off, seaLevelPa!, Endian.little);
      off += 4;
    }
    if (fuel != null) {
      out.setUint32(off, fuel!.drinkIntervalS, Endian.little);
      out.setUint32(off + 4, fuel!.eatIntervalS, Endian.little);
      off += 8;
    }

    return out.buffer.asUint8List();
  }
}
