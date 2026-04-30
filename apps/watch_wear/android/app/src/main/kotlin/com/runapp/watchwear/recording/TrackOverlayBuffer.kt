package com.runapp.watchwear.recording

/// Helpers for the bounded rolling-buffer pattern that powers the
/// in-run mini-map's "where I've been" overlay.
///
/// The buffer is a `MutableList` the caller appends to per GPS sample.
/// Once it grows past `cap`, `halveIfOverflowing` drops every other
/// point in-place so density halves and total size stays at most `cap`.
/// Geometric (every-other) downsampling means the buffer stays
/// uniform across the whole run — the early hours don't get evicted
/// in favour of recent points the way a FIFO drop would do.
///
/// Pure functions so this is unit-testable without booting the
/// recording service or mocking GPS.
object TrackOverlayBuffer {

    /// Halve the buffer in place when it exceeds `cap`. Keeps even
    /// indices (0, 2, 4, …) so the first and last points survive
    /// — visually important: the start of the run and the latest
    /// fix should stay anchored on the polyline.
    ///
    /// No-op if the buffer is at or below `cap`. Throws on `cap < 2`
    /// since the halving algorithm needs at least two points to
    /// preserve the start-and-current invariant.
    fun <T> halveIfOverflowing(buf: MutableList<T>, cap: Int) {
        require(cap >= 2) { "cap must be ≥ 2 (got $cap)" }
        if (buf.size <= cap) return
        // Walk forward keeping every even index. Doing this in place
        // with a write index avoids allocating a second list.
        var write = 0
        var read = 0
        while (read < buf.size) {
            buf[write] = buf[read]
            write++
            read += 2
        }
        // Drop the trailing slots we no longer need.
        while (buf.size > write) buf.removeAt(buf.size - 1)
    }
}
