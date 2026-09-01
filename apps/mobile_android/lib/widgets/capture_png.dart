import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The PNG bytes of a rasterised share card, or a thrown failure.
///
/// Four sheets rasterise a `RepaintBoundary` and hand the bytes to the share
/// sheet — the run card, the route card, the finisher certificate and the
/// period summary. Each wrote the same four lines, and each ended them with
/// `if (byteData == null) return;`.
///
/// That early return is the failure this module exists to remove. Every one of
/// those callers sits inside a `try` whose `catch` shows a share-failed banner
/// and whose `finally` clears the capturing flag, so a null encoding stopped
/// the spinner, re-enabled the button, and told the runner nothing at all —
/// indistinguishable from a share they cancelled themselves, and from one that
/// worked. Throwing routes the same failure into the banner the caller already
/// has.
Future<Uint8List> capturePngBytes(
  GlobalKey key, {
  double pixelRatio = 3.0,
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  return pngBytesOrThrow(await image.toByteData(format: ui.ImageByteFormat.png));
}

/// The bytes of [encoded], or a [StateError] when the encoder returned
/// nothing. Separate from [capturePngBytes] because the null branch is the
/// whole point and a real `RenderRepaintBoundary` cannot be made to produce
/// one on demand.
Uint8List pngBytesOrThrow(ByteData? encoded) {
  if (encoded == null) {
    throw StateError('the share card rasterised to no PNG bytes');
  }
  return encoded.buffer.asUint8List();
}
