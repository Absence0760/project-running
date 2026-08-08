import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Full-screen viewer shared by the run / club / route / event photo grids.
/// Tap anywhere to dismiss, pinch to zoom.
///
/// The full-resolution bytes arrive over a signed URL that may already have
/// expired by the time the thumbnail is tapped, and there is nothing else on
/// the barrier to look at — so an image that is merely slow and an image that
/// will never arrive both used to render as the same unbroken black rectangle.
void showPhotoLightbox(
  BuildContext context, {
  required String url,
  String? caption,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => PhotoLightbox(url: url, caption: caption),
  );
}

class PhotoLightbox extends StatelessWidget {
  final String url;
  final String? caption;

  const PhotoLightbox({super.key, required this.url, this.caption});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = caption;
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              // Without this the viewer is one unnamed rectangle: the caption
              // below is a separate node and is often absent entirely.
              semanticLabel: (caption?.trim().isNotEmpty ?? false)
                  ? caption!.trim()
                  : l10n.photoOpen,
              frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
                  wasSynchronouslyLoaded || frame != null
                      ? child
                      : Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            semanticsLabel: l10n.photoLightboxLoading,
                          ),
                        ),
              errorBuilder: (_, _, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined,
                          size: 48, color: Colors.white70),
                      const SizedBox(height: 12),
                      Text(
                        l10n.photoLightboxError,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.photoLightboxErrorHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (text != null && text.isNotEmpty)
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          // Tap-anywhere-to-dismiss is invisible to a screen reader and to
          // anyone who doesn't know the gesture. The barrier and system back
          // still work; this makes the exit an actual named control.
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              tooltip: l10n.photoLightboxClose,
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
