import 'dart:typed_data';

import 'sim_watch_sync.dart' show crc32;

/// Pure Dart mirror of the custom watch's `watch_core::settings` wire format.
///
/// The phone pushes the user's config to the watch as a fixed little-endian
/// frame the firmware decodes:
///
///   magic("SET1", 4) | version(1) | flags(1) | flags2(1) | fields | crc32(4)
///
/// `flags` is a bitfield of which optional fields follow, in bit order:
/// bit0 max_hr, bit1 pacer, bit2 gear, bit3 zone_ceiling, bit4 sea_level_pa,
/// bit5 fuel, bit6 pages, bit7 hide_empty_pages. Version 2 (2026-07-22)
/// saturated that byte, so it appends a second presence byte `flags2` —
/// bit0 tz_offset_min — with its fields laid out after the first byte's.
/// Version 3 (2026-07-25) appends a CRC32 trailer over every byte before it:
/// the length check alone could not tell a single-byte corruption that swaps
/// two equal-width fields from a legitimate push, so the watch would apply
/// the QNH sea-level pressure as the run-view page mask. Version 4
/// (2026-07-26) takes the next five `flags2` bits for the settings the watch
/// could already honour but the phone could not reach — bit1
/// distance_interval_m, bit2 time_interval_s, bit3 pace_band, bit4
/// race_phases, bit5 guided_run — and widens the run-view page mask from 32 to
/// 64 bits so every page the firmware declares is addressable. `flags2` still
/// has two free bits, which is why v4 needed no third presence byte. Only the
/// present fields are written, so a partial update is a shorter frame; a fully
/// populated frame is 98 bytes, one write at the watch's 256-byte ATT MTU. The
/// firmware still decodes v1, v2 and v3 frames, but the phone always encodes
/// the current version.
///
/// Deliberately pure — no BLE, no platform channels — so [encode] is
/// unit-testable against a frozen golden vector shared with the Rust test.
/// The phone only ever encodes (the watch decodes), mirroring how the
/// run-sync path (`sim_watch_sync.dart`) is the phone's decode side — and it
/// reuses that module's [crc32], the same checksum the firmware shares
/// between `run_store` and `settings`.
const int _settingsVersion = 0x04;

/// Width of the CRC32 trailer, present since v3.
const int _crcLen = 4;

/// Capacity of the guided-run id field: a NUL-padded ASCII library id. The
/// longest shipped id is 16 bytes (`tempo-builder-25`); the slack is for ids a
/// later firmware library adds, since widening the field is a version bump.
const int guidedRunIdLen = 24;

const int _flagMaxHr = 0x01;
const int _flagPacer = 0x02;
const int _flagGear = 0x04;
const int _flagZoneCeiling = 0x08;
const int _flagSeaLevel = 0x10;
const int _flagFuel = 0x20;
const int _flagPages = 0x40;
const int _flagHideEmpty = 0x80;

const int _flag2TzOffset = 0x01;
const int _flag2DistanceInterval = 0x02;
const int _flag2TimeInterval = 0x04;
const int _flag2PaceBand = 0x08;
const int _flag2RacePhases = 0x10;
const int _flag2GuidedRun = 0x20;

/// The watch's race-phase presets, in the firmware enum's declaration order —
/// which is also `RacePhasePreset`'s order in `race_phases.dart` and the web
/// union's. The wire carries the index, so this list's ORDER is the contract;
/// reordering it re-points every plan already pushed.
enum WatchRacePhasePreset { tenTenTen, negativeSplit, even }

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

  /// The curated run-view page set: bit i enables the page with firmware
  /// discriminant i (the watch's `Page::bit` order). 64-bit since v4, so every
  /// page the firmware declares is addressable — before it, the watch had to
  /// force-enable everything past bit 31 rather than let a mask the phone could
  /// not express curate a page out. The watch force-includes its Dashboard so an
  /// all-zero mask can't empty the cycle.
  final int? pages;

  /// Whether the watch's BTN3 cycle skips pages whose backing data is absent
  /// (the on-watch default is on).
  final bool? hideEmptyPages;

  /// Local-time offset for the watch's home clock, minutes east of UTC —
  /// auto-sourced from the phone's own zone (`DateTime.now().timeZoneOffset`)
  /// at push time, so the watch tells the time the runner's phone tells.
  final int? tzOffsetMin;

  /// Metres of distance between the watch's distance alerts. 0 turns the alert
  /// off — the same present-field-carrying-a-zero-sentinel shape as
  /// [zoneCeiling], so the phone can disarm the alert and not only arm it.
  final int? distanceIntervalM;

  /// Seconds of elapsed time between the watch's time alerts; 0 turns it off.
  final int? timeIntervalS;

  /// The pace window the watch alerts outside of, seconds per kilometre. An
  /// all-zero band turns it off. Both edges travel as ONE field under ONE
  /// presence bit: two bits would let a partial push arm a new fast edge
  /// against whatever stale slow edge the watch still held, which its
  /// `set_pace_band` then refuses as an inverted band — losing the whole update
  /// rather than half of it.
  final ({int fastSPerKm, int slowSPerKm})? paceBand;

  /// The race-phase plan. A null [distanceM] clears the plan (the watch setter
  /// takes the same shape); a null [goalTimeS] builds the phases with no target
  /// pace.
  final ({int? distanceM, int? goalTimeS, WatchRacePhasePreset preset})?
      racePhases;

  /// The guided run to arm, by its firmware library id (`easy-30`,
  /// `tempo-builder-25`, `first-timer-15`). An empty string deselects.
  ///
  /// The id rather than an index into the library: the library is compiled into
  /// the firmware, so a later build that inserts or reorders a run would
  /// silently re-point every index the phone holds — a runner who picked "easy
  /// 30" would get a fartlek after an OTA, and both sides would still look
  /// valid. An unknown id fails closed on the watch.
  final String? guidedRunId;

  const WatchSettings({
    this.maxHr,
    this.pacer,
    this.gear,
    this.zoneCeiling,
    this.seaLevelPa,
    this.fuel,
    this.pages,
    this.hideEmptyPages,
    this.tzOffsetMin,
    this.distanceIntervalM,
    this.timeIntervalS,
    this.paceBand,
    this.racePhases,
    this.guidedRunId,
  });

  Uint8List encode() {
    var len = 7 + _crcLen;
    if (maxHr != null) len += 2;
    if (pacer != null) len += 8;
    if (gear != null) len += 8;
    if (zoneCeiling != null) len += 1;
    if (seaLevelPa != null) len += 4;
    if (fuel != null) len += 8;
    if (pages != null) len += 8;
    if (hideEmptyPages != null) len += 1;
    if (tzOffsetMin != null) len += 2;
    if (distanceIntervalM != null) len += 4;
    if (timeIntervalS != null) len += 4;
    if (paceBand != null) len += 4;
    if (racePhases != null) len += 9;
    if (guidedRunId != null) len += guidedRunIdLen;

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
    if (pages != null) flags |= _flagPages;
    if (hideEmptyPages != null) flags |= _flagHideEmpty;
    out.setUint8(5, flags);

    var flags2 = 0;
    if (tzOffsetMin != null) flags2 |= _flag2TzOffset;
    if (distanceIntervalM != null) flags2 |= _flag2DistanceInterval;
    if (timeIntervalS != null) flags2 |= _flag2TimeInterval;
    if (paceBand != null) flags2 |= _flag2PaceBand;
    if (racePhases != null) flags2 |= _flag2RacePhases;
    if (guidedRunId != null) flags2 |= _flag2GuidedRun;
    out.setUint8(6, flags2);

    var off = 7;
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
    if (pages != null) {
      out.setUint64(off, pages!, Endian.little);
      off += 8;
    }
    if (hideEmptyPages != null) {
      out.setUint8(off, hideEmptyPages! ? 1 : 0);
      off += 1;
    }
    if (tzOffsetMin != null) {
      out.setInt16(off, tzOffsetMin!, Endian.little);
      off += 2;
    }
    if (distanceIntervalM != null) {
      out.setUint32(off, distanceIntervalM!, Endian.little);
      off += 4;
    }
    if (timeIntervalS != null) {
      out.setUint32(off, timeIntervalS!, Endian.little);
      off += 4;
    }
    if (paceBand != null) {
      out.setUint16(off, paceBand!.fastSPerKm, Endian.little);
      out.setUint16(off + 2, paceBand!.slowSPerKm, Endian.little);
      off += 4;
    }
    if (racePhases != null) {
      // 0 distance clears the plan, 0 goal time builds it with no target pace
      // — both are what the watch setter's nulls mean.
      out.setUint32(off, racePhases!.distanceM ?? 0, Endian.little);
      out.setUint32(off + 4, racePhases!.goalTimeS ?? 0, Endian.little);
      out.setUint8(off + 8, racePhases!.preset.index);
      off += 9;
    }
    if (guidedRunId != null) {
      final id = guidedRunId!.codeUnits;
      if (id.length > guidedRunIdLen) {
        // Truncating would either resolve to nothing or, worse, to a different
        // run whose id is a prefix of the one the runner picked.
        throw ArgumentError.value(
          guidedRunId,
          'guidedRunId',
          'longer than the $guidedRunIdLen-byte wire field',
        );
      }
      for (var i = 0; i < id.length; i++) {
        out.setUint8(off + i, id[i]);
      }
      off += guidedRunIdLen;
    }

    final frame = out.buffer.asUint8List();
    out.setUint32(off, crc32(frame.sublist(0, off)), Endian.little);
    return frame;
  }
}
