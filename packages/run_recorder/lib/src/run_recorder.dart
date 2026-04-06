import 'package:core_models/core_models.dart';

import 'run_snapshot.dart';

/// Manages a live GPS recording session.
///
/// Streams position updates, calculates pace, and handles auto-pause.
class RunRecorder {
  /// Emits a [RunSnapshot] on every GPS update during recording.
  Stream<RunSnapshot> get snapshots {
    // TODO: Implement GPS stream
    throw UnimplementedError();
  }

  /// Begin recording a run, optionally following a [route].
  Future<void> start({Route? route}) async {
    // TODO: Implement start recording
    throw UnimplementedError();
  }

  /// Finalise recording and return the completed [Run].
  Future<Run> stop() async {
    // TODO: Implement stop recording
    throw UnimplementedError();
  }
}
