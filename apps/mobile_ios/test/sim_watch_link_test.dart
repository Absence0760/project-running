import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../lib/sim_watch_link.dart';

const _fixFrame =
    '{"v":1,"uptime_s":42,"fix":{"lat":40.015000,"lon":-105.270500,'
    '"speed_mps":3.00,"course_deg":90.0,"sats":8,"alt_m":1624.0,'
    '"tod_s":27015,"age_s":1}}';
const _noFixFrame = '{"v":1,"uptime_s":1,"fix":null}';
const _elevFrame =
    '{"v":1,"uptime_s":50,"fix":null,'
    '"elev":{"alt_m":1600.5,"gain_m":540.0,"loss_m":120.0}}';
const _elevNullFrame = '{"v":1,"uptime_s":50,"fix":null,"elev":null}';

void main() {
  test('parses a full status frame', () {
    final status = SimWatchStatus.fromJsonLine(_fixFrame);
    expect(status, isNotNull);
    expect(status!.version, 1);
    expect(status.uptimeS, 42);
    final fix = status.fix!;
    expect(fix.lat, closeTo(40.015, 1e-9));
    expect(fix.lon, closeTo(-105.2705, 1e-9));
    expect(fix.speedMps, closeTo(3.0, 1e-9));
    expect(fix.courseDeg, closeTo(90.0, 1e-9));
    expect(fix.sats, 8);
    expect(fix.altM, closeTo(1624.0, 1e-9));
    expect(fix.todS, 27015);
    expect(fix.ageS, 1);
  });

  test('null fix stays null, not a zeroed fix', () {
    final status = SimWatchStatus.fromJsonLine(_noFixFrame);
    expect(status!.fix, isNull);
    expect(status.uptimeS, 1);
  });

  test('null optional fields survive parsing', () {
    const frame = '{"v":1,"uptime_s":9,"fix":{"lat":1.0,"lon":2.0,'
        '"speed_mps":0.0,"course_deg":null,"sats":0,"alt_m":null,'
        '"tod_s":null,"age_s":0}}';
    final fix = SimWatchStatus.fromJsonLine(frame)!.fix!;
    expect(fix.courseDeg, isNull);
    expect(fix.altM, isNull);
    expect(fix.todS, isNull);
  });

  test('parses the elevation object when present', () {
    final elev = SimWatchStatus.fromJsonLine(_elevFrame)!.elev!;
    expect(elev.altM, closeTo(1600.5, 1e-9));
    expect(elev.gainM, closeTo(540.0, 1e-9));
    expect(elev.lossM, closeTo(120.0, 1e-9));
  });

  test('null elevation stays null, not a zeroed reading', () {
    expect(SimWatchStatus.fromJsonLine(_elevNullFrame)!.elev, isNull);
  });

  test('a frame with no elev key (older firmware) still parses, elev null', () {
    // Backward compat: _fixFrame predates the additive elev field.
    final status = SimWatchStatus.fromJsonLine(_fixFrame)!;
    expect(status.fix, isNotNull);
    expect(status.elev, isNull);
  });

  test('garbage lines return null instead of throwing', () {
    expect(SimWatchStatus.fromJsonLine(''), isNull);
    expect(SimWatchStatus.fromJsonLine('not json'), isNull);
    expect(SimWatchStatus.fromJsonLine('[1,2,3]'), isNull);
    expect(SimWatchStatus.fromJsonLine('{"fix":{}}'), isNull);
    expect(SimWatchStatus.fromJsonLine('{"v":1,"uptime_s":2,"fix":{}}')!.fix,
        isNull);
  });

  test('frame stream skips malformed lines and survives chunk splits', () async {
    final controller = StreamController<List<int>>();
    final collected = <SimWatchStatus>[];
    final done = simWatchFrames(controller.stream).forEach(collected.add);

    // A stream that joins mid-frame, then two frames, one split across
    // chunk boundaries — the UART bridge gives no framing guarantees.
    controller.add(utf8.encode('05,"sats":8}}\n'));
    controller.add(utf8.encode('$_noFixFrame\n'));
    final split = utf8.encode('$_fixFrame\n');
    controller.add(split.sublist(0, 25));
    controller.add(split.sublist(25));
    await controller.close();
    await done;

    expect(collected.length, 2);
    expect(collected[0].fix, isNull);
    expect(collected[1].fix!.sats, 8);
  });

  test('decodes a Uint8List-typed stream, the shape a real Socket has', () async {
    // Pins the bind-not-transform choice: Socket reifies as
    // Stream<Uint8List>, which transform(Utf8Decoder) rejects at runtime.
    final controller = StreamController<Uint8List>();
    final done = simWatchFrames(controller.stream).toList();
    controller.add(Uint8List.fromList(utf8.encode('$_fixFrame\n')));
    await controller.close();
    final collected = await done;
    expect(collected.single.fix!.sats, 8);
  });

  test('a socket landing after close() is destroyed, not leaked', () async {
    // The screen disposes mid-connect: close() runs while Socket.connect is
    // still dialling, so the socket arrives with no owner. connect() must
    // destroy it (the server sees the connection drop) instead of leaking it.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final clientSeen = Completer<Socket>();
    server.listen(clientSeen.complete);

    final link = SimWatchLink(host: '127.0.0.1', port: server.port);
    await link.close();
    await expectLater(link.connect(), throwsA(isA<SocketException>()));

    final client = await clientSeen.future;
    await expectLater(client.drain<void>(), completes);
    await server.close();
  });

  test('default host targets the emulator alias on Android only', () {
    // Host tests run on the workstation, so the loopback default applies.
    expect(simWatchDefaultHost(), '127.0.0.1');
    expect(simWatchDefaultPort, 7788);
  });
}
