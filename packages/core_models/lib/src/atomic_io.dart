import 'dart:convert';
import 'dart:io';

/// Per-process counter giving each in-flight atomic write a distinct temp
/// path. Two concurrent writes to the same target file would otherwise
/// share one `.tmp` sibling — the first `rename` consumes it and the
/// second throws on a missing source. A unique suffix lets both complete
/// independently (last `rename` wins, matching the prior last-write-wins
/// semantics of a bare `writeAsString`).
int _atomicWriteSeq = 0;

/// Atomically replace [file]'s contents with [contents].
///
/// A bare `File.writeAsString` truncates the destination to zero bytes
/// before streaming the new bytes, so a process death (OOM-kill, power
/// loss, force-quit) mid-write leaves a zero-byte or partial file that
/// `jsonDecode` rejects on the next cold-start — the record silently
/// disappears. This writes to a `.tmp` sibling, flushes it to disk, then
/// renames it over the target. `rename` is atomic on POSIX / Android
/// ext4·f2fs / iOS APFS: a reader sees either the old file or the fully
/// written new one, never a partial.
Future<void> writeStringAtomic(File file, String contents) async {
  final tmp = File('${file.path}.${_atomicWriteSeq++}.tmp');
  try {
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  } catch (e) {
    // Don't leave a stray temp file behind on failure.
    try {
      if (tmp.existsSync()) await tmp.delete();
    } catch (_) {/* best-effort cleanup */}
    rethrow;
  }
}

/// Convenience wrapper: JSON-encode [json] and write it atomically to
/// [file]. See [writeStringAtomic] for the crash-safety contract.
Future<void> writeJsonAtomic(File file, Object? json) =>
    writeStringAtomic(file, jsonEncode(json));

/// A `writeStringAtomic` temp sibling older than this is an orphan of a
/// crashed write, never a write still in flight — an atomic write completes in
/// milliseconds, and the age gate keeps the sweep from deleting the temp file
/// of a genuinely concurrent writer (the background-sync isolate runs its own
/// store instances over the same directories).
const Duration kAtomicOrphanMinAge = Duration(hours: 1);

/// Delete `<name>.<n>.tmp` files left in [dir] when the process died between
/// [writeStringAtomic]'s flush and its rename. Every store listing filters on
/// `.json`, so an orphan is invisible to the store and otherwise sits on disk
/// forever holding a full row — a GPS track, a route's waypoints — that
/// outlives sign-out. Synchronous on purpose: it runs inside the cold-load
/// directory walk, which must stay on `listSync` (decisions §48). [onError]
/// lets a Flutter caller route failures to `debugPrint`; this package has no
/// logger of its own.
void sweepAtomicWriteOrphans(
  Directory dir, {
  void Function(String message)? onError,
}) {
  final cutoff = DateTime.now().subtract(kAtomicOrphanMinAge);
  try {
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.tmp')) continue;
      try {
        if (entity.statSync().modified.isAfter(cutoff)) continue;
        entity.deleteSync();
      } catch (e) {
        onError?.call('orphan sweep failed ${entity.path}: $e');
      }
    }
  } catch (e) {
    onError?.call('orphan sweep failed: $e');
  }
}
