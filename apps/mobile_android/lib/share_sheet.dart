import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

export 'package:share_plus/share_plus.dart' show XFile;

/// The anchor used when no widget box can be resolved and the view's own size
/// is unknown. Deliberately a real one-logical-pixel rect at the view origin:
/// UIKit rejects an empty rect, so a zero anchor is the failure this module
/// exists to prevent, not a neutral default.
@visibleForTesting
const Rect shareOriginFallbackRect = Rect.fromLTWH(0, 0, 1, 1);

const double _viewAnchorSide = 8;

/// The rect the OS share sheet should popover from, in logical pixels.
///
/// iPadOS presents `UIActivityViewController` as a popover and will not present
/// one without a non-empty source rect inside the host view. The app ships to
/// iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), and share_plus 12's iOS plugin turns
/// a missing or empty anchor into a `PlatformException` — no sheet appears at
/// all — so every share has to carry one.
///
/// Derivation degrades rather than throwing: the invoking widget's own box, else
/// a small rect at the centre of the view, else [shareOriginFallbackRect]. The
/// widget rect is clipped to the view because the plugin also requires the
/// anchor to sit inside the host view's frame, which a part-scrolled or
/// mid-animation box need not.
Rect shareOriginFor(BuildContext context) {
  try {
    final view = _viewRect();
    final object = context.findRenderObject();
    if (object is RenderBox && object.attached && object.hasSize) {
      final rect = object.localToGlobal(Offset.zero) & object.size;
      if (rect.isFinite) {
        final anchored = view == null ? rect : rect.intersect(view);
        if (anchored.width > 0 && anchored.height > 0) return anchored;
      }
    }
    if (view != null) return _viewCentreAnchor(view);
  } catch (e) {
    debugPrint('shareOriginFor: no widget anchor, falling back: $e');
  }
  return shareOriginFallbackRect;
}

Rect? _viewRect() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return null;
  final ratio = view.devicePixelRatio;
  if (!ratio.isFinite || ratio <= 0) return null;
  final size = view.physicalSize / ratio;
  if (size.isEmpty || !size.isFinite) return null;
  return Offset.zero & size;
}

Rect _viewCentreAnchor(Rect view) {
  final side = math.min(_viewAnchorSide, math.min(view.width, view.height));
  return Rect.fromCenter(center: view.center, width: side, height: side);
}

/// Hand [files] to the OS share sheet, anchored on [context]'s widget.
///
/// The context is required rather than an optional `Rect` so a caller cannot
/// share without an anchor — the iPad bug this replaced was nine call sites
/// each free to omit one.
Future<void> shareFilesFrom(
  BuildContext context, {
  required List<XFile> files,
  String? text,
  String? subject,
}) async {
  final origin = shareOriginFor(context);
  await SharePlus.instance.share(
    ShareParams(
      files: files,
      text: text,
      subject: subject,
      sharePositionOrigin: origin,
    ),
  );
}

/// Hand [text] to the OS share sheet, anchored on [context]'s widget.
Future<void> shareTextFrom(
  BuildContext context, {
  required String text,
  String? subject,
}) async {
  final origin = shareOriginFor(context);
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: subject,
      sharePositionOrigin: origin,
    ),
  );
}
