import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Longest a capture waits for basemap tiles before rasterising anyway.
///
/// A ceiling, not the mechanism. [MapTileReadiness.settled] returns the moment
/// the tiles have actually settled — the next frame, for the cached case — and
/// this only bounds a tile whose fetch never calls back at all. It is not a
/// latency guess: flutter_map stamps `loadFinishedAt` on a FAILED tile as well
/// as a loaded one, so an offline or 403 tile settles immediately and the
/// export matches the preview the user is looking at.
const Duration kTileSettleCeiling = Duration(seconds: 8);

/// Observes a [TileLayer]'s tiles so a rasteriser can wait for the real thing.
///
/// Wire [observe] as `TileLayer.tileBuilder` and await [settled] before
/// `RenderRepaintBoundary.toImage`. A fixed sleep is a guess about network
/// latency and is wrong in both directions: too short and a cold fetch bakes a
/// part-black map into the exported PNG, too long and every cached share waits
/// for nothing.
///
/// Assumes a camera that does not move — every share card fixes its bounds and
/// disables interaction — so a tile once rendered is never evicted and the
/// accumulated set stays the set on screen.
class MapTileReadiness {
  final Map<TileCoordinates, TileImage> _tiles = {};

  /// Pass as [TileLayer.tileBuilder]. Renders [tile] unchanged; the point is
  /// the side effect of recording which tiles the layer is showing.
  Widget observe(BuildContext context, Widget tile, TileImage image) {
    _tiles[image.coordinates] = image;
    return tile;
  }

  /// Whether every tile the layer has rendered has finished loading or failed.
  bool get isSettled =>
      _tiles.isNotEmpty &&
      _tiles.values.every((t) => t.loadFinishedAt != null);

  /// Resolves once [isSettled], or [ceiling] after the call.
  ///
  /// Returns whether the tiles really settled, so a caller can disclose a
  /// degraded capture rather than presenting one as complete.
  ///
  /// Polls on a timer rather than listening to each [TileImage]: the layer
  /// creates its tiles across the first frames of layout, so a listener set
  /// snapshotted up front would miss every tile that arrives after it — and
  /// the empty set is exactly the state [isSettled] must not accept.
  Future<bool> settled({Duration ceiling = kTileSettleCeiling}) {
    if (isSettled) return Future.value(true);
    final done = Completer<bool>();
    late final Timer poll;
    final deadline = Timer(ceiling, () {
      if (done.isCompleted) return;
      poll.cancel();
      done.complete(false);
    });
    poll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!isSettled) return;
      poll.cancel();
      deadline.cancel();
      done.complete(true);
    });
    return done.future;
  }
}
