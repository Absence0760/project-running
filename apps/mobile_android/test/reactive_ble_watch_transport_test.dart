import 'package:flutter_test/flutter_test.dart';

import '../lib/reactive_ble_watch_transport.dart';

/// The firmware's GATT table, transcribed from the `#[characteristic(...)]`
/// attributes on `LinkService` in `apps/custom_watch/app/src/tasks/ble.rs` —
/// the source of truth for this contract. The phone can only sync against
/// these exact handles, and the BLE path cannot run in the Renode sim (no
/// S140 SoftDevice), so a mismatch is invisible until hardware exists. That
/// is exactly how the phone spent its life reading the manifest from `..e1`
/// (the live-status `frame`) and writing chunk requests to `..e2`
/// (read+notify only — the write was rejected outright).
///
///   ..e1  frame         read, notify
///   ..e2  run_manifest  read, notify
///   ..e3  run_chunk     write, notify
///   ..e4  settings      write
///   ..e5  course        write
///   ..e6  workout       write
///   ..e7  screens       write
///   ..e8  roadbook      write
///   ..e9  push_status   read
const _service = 'd1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _runManifest = 'd1f6a7e2-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _runChunk = 'd1f6a7e3-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _settings = 'd1f6a7e4-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _course = 'd1f6a7e5-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _workout = 'd1f6a7e6-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _screens = 'd1f6a7e7-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _roadbook = 'd1f6a7e8-5b2c-4e9a-9c3d-1a2b3c4d5e6f';
const _pushStatus = 'd1f6a7e9-5b2c-4e9a-9c3d-1a2b3c4d5e6f';

/// The `frame` characteristic: the per-second live-status notify, claimed by
/// [ReactiveBleWatchFrameSource] on its own connection rather than by the
/// per-operation sync transport. It spent its life unclaimed here, which is
/// why the manifest assertion below still names it explicitly.
const _frame = 'd1f6a7e1-5b2c-4e9a-9c3d-1a2b3c4d5e6f';

void main() {
  group('ReactiveBleWatchTransport GATT UUIDs', () {
    test('service matches the firmware gatt_service uuid', () {
      expect(ReactiveBleWatchTransport.serviceUuid.toString(), _service);
    });

    test('manifest reads from run_manifest (..e2), not the status frame', () {
      expect(ReactiveBleWatchTransport.manifestCharUuid.toString(),
          _runManifest);
      expect(
        ReactiveBleWatchTransport.manifestCharUuid.toString(),
        isNot(_frame),
      );
    });

    test('chunk request and chunk data share run_chunk (..e3)', () {
      expect(ReactiveBleWatchTransport.chunkCharUuid.toString(), _runChunk);
    });

    test('settings writes to ..e4', () {
      expect(ReactiveBleWatchTransport.settingsCharUuid.toString(), _settings);
    });

    test('course writes to ..e5', () {
      expect(ReactiveBleWatchTransport.courseCharUuid.toString(), _course);
    });

    test('workout writes to ..e6', () {
      expect(ReactiveBleWatchTransport.workoutCharUuid.toString(), _workout);
    });

    test('screens writes to ..e7', () {
      expect(ReactiveBleWatchTransport.screensCharUuid.toString(), _screens);
    });

    test('roadbook writes to ..e8', () {
      expect(ReactiveBleWatchTransport.roadbookCharUuid.toString(), _roadbook);
    });

    test('push verdicts read from ..e9', () {
      expect(
          ReactiveBleWatchTransport.pushStatusCharUuid.toString(), _pushStatus);
    });

    test('the status link reads frames from ..e1', () {
      expect(ReactiveBleWatchFrameSource.frameCharUuid.toString(), _frame);
    });

    test('every characteristic sits on a distinct handle', () {
      final uuids = <String>{
        ReactiveBleWatchFrameSource.frameCharUuid.toString(),
        ReactiveBleWatchTransport.manifestCharUuid.toString(),
        ReactiveBleWatchTransport.chunkCharUuid.toString(),
        ReactiveBleWatchTransport.settingsCharUuid.toString(),
        ReactiveBleWatchTransport.courseCharUuid.toString(),
        ReactiveBleWatchTransport.workoutCharUuid.toString(),
        ReactiveBleWatchTransport.screensCharUuid.toString(),
        ReactiveBleWatchTransport.roadbookCharUuid.toString(),
        ReactiveBleWatchTransport.pushStatusCharUuid.toString(),
      };
      expect(uuids, hasLength(9));
    });
  });
}
