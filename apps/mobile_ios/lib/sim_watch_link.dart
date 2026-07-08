// Dev-only client for the simulated custom watch's phone link.
//
// `bin/watch-sim.sh` (repo root) boots the custom-watch firmware on an
// emulated nRF52840 and bridges its phone-link UART to a TCP socket
// (default port 7788). The watch streams one newline-terminated JSON
// status frame per second — schema v1, defined by `watch_core::link`
// (apps/custom_watch/core/src/link.rs), which is also what the future BLE
// GATT characteristic will carry. This client decodes that stream; it is
// reachable only from the dev-gated Sim Watch screen (loopback-backend
// gate, same rail as dev_auto_login.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const int simWatchDefaultPort = 7788;

// The Android emulator reaches the workstation via the 10.0.2.2 alias.
String simWatchDefaultHost() {
  if (kIsWeb) return '127.0.0.1';
  try {
    return Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
  } catch (_) {
    return '127.0.0.1';
  }
}

// Safe to call before (or without) dotenv initialization, e.g. in widget
// tests that build the settings screen directly.
String? maybeDevBackendUrl() {
  try {
    return dotenv.isInitialized ? dotenv.env['SUPABASE_URL'] : null;
  } catch (_) {
    return null;
  }
}

class SimWatchFix {
  final double lat;
  final double lon;
  final double speedMps;
  final double? courseDeg;
  final int sats;
  final double? altM;
  final int? todS;
  final int ageS;

  const SimWatchFix({
    required this.lat,
    required this.lon,
    required this.speedMps,
    required this.sats,
    required this.ageS,
    this.courseDeg,
    this.altM,
    this.todS,
  });

  static SimWatchFix? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final lat = json['lat'];
    final lon = json['lon'];
    if (lat is! num || lon is! num) return null;
    return SimWatchFix(
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      speedMps: (json['speed_mps'] as num?)?.toDouble() ?? 0,
      courseDeg: (json['course_deg'] as num?)?.toDouble(),
      sats: (json['sats'] as num?)?.toInt() ?? 0,
      altM: (json['alt_m'] as num?)?.toDouble(),
      todS: (json['tod_s'] as num?)?.toInt(),
      ageS: (json['age_s'] as num?)?.toInt() ?? 0,
    );
  }
}

class SimWatchStatus {
  final int version;
  final int uptimeS;
  final SimWatchFix? fix;

  const SimWatchStatus({
    required this.version,
    required this.uptimeS,
    this.fix,
  });

  /// Returns null on anything that isn't a valid frame — a UART stream can
  /// join mid-line, so garbage is routine, not exceptional.
  static SimWatchStatus? fromJsonLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['v'];
      final uptime = decoded['uptime_s'];
      if (version is! num || uptime is! num) return null;
      return SimWatchStatus(
        version: version.toInt(),
        uptimeS: uptime.toInt(),
        fix: SimWatchFix.fromJson(decoded['fix']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Decode a raw byte stream into status frames, skipping malformed lines.
Stream<SimWatchStatus> simWatchFrames(Stream<List<int>> bytes) async* {
  // bind, not transform: a real Socket reifies as Stream<Uint8List>, and
  // transform's runtime StreamTransformer<Uint8List, String> check rejects
  // Utf8Decoder even though the element type is compatible.
  final lines = const LineSplitter()
      .bind(const Utf8Decoder(allowMalformed: true).bind(bytes));
  await for (final line in lines) {
    final status = SimWatchStatus.fromJsonLine(line);
    if (status != null) yield status;
  }
}

class SimWatchLink {
  final String host;
  final int port;
  Socket? _socket;
  bool _closed = false;

  SimWatchLink({required this.host, this.port = simWatchDefaultPort});

  Future<Stream<SimWatchStatus>> connect() async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    if (_closed) {
      // close() raced the dial (screen disposed mid-connect): the socket
      // arrived with no owner left to close it, so destroy it here.
      socket.destroy();
      throw const SocketException('link closed during connect');
    }
    _socket = socket;
    return simWatchFrames(socket);
  }

  Future<void> close() async {
    _closed = true;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
  }
}
