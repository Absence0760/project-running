import 'package:core_models/core_models.dart';

import 'run_snapshot.dart';

/// Manages a live GPS recording session.
///
/// Streams position updates, calculates pace, and handles auto-pause.
class RunRecorder {
  /// Emits a [RunSnapshot] on every GPS update during recording.
  Stream<RunSnapshot> get snapshots {
    // TODO: Implement GPS stream
    return const Stream.empty();
  }

  /// Begin recording a run, optionally following a [route].
  Future<void> start({Route? route}) async {
    // TODO: Implement start recording
  }

  /// Finalise recording and return the completed [Run].
  Future<Run> stop() async {
    // TODO: Implement stop recording
    return Run(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startedAt: DateTime.now(),
      duration: Duration.zero,
      distanceMetres: 0,
      source: RunSource.app,
    );
  }
}
