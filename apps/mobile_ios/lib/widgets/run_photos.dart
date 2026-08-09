import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth_error.dart';
import '../exif_strip.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/photo_lightbox.dart';
import '../widgets/top_banner.dart';
import 'confirm_destructive.dart';

/// Mirrors the web `RunPhotos.svelte` — grid of photos for a run, with
/// owner-gated upload (image_picker), caption edit, and delete.
class RunPhotos extends StatefulWidget {
  final ApiClient api;
  final String runId;
  final String runOwnerId;

  /// Test seam — inject the gallery-pick source so the picker's error
  /// paths (permission denial, generic failure) are drivable without a
  /// real photo picker. Defaults to the live [ImagePicker] gallery pick.
  final Future<XFile?> Function()? pickImageOverride;

  const RunPhotos({
    super.key,
    required this.api,
    required this.runId,
    required this.runOwnerId,
    this.pickImageOverride,
  });

  @override
  State<RunPhotos> createState() => _RunPhotosState();
}

class _RunPhotosState extends State<RunPhotos> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _uploading = false;
  String? _editingId;
  final _captionCtrl = TextEditingController();
  final _pendingCaptionCtrl = TextEditingController();
  XFile? _pending;
  List<RunPhotoRow> _photos = const [];
  // storage_path → (url, signedAtMs). Populated at _load() and after
  // _uploadPending(). The bucket is private (migration 20260712_001
  // closed the public-CDN bypass), so getPublicUrl no longer returns
  // bytes — every render path goes through createSignedUrl.
  // Cached entries older than `_signedUrlTtlSeconds` are evicted on
  // re-sign so a screen kept in the foreground past the TTL doesn't
  // start showing broken images.
  final Map<String, _SignedEntry> _signedUrls = <String, _SignedEntry>{};
  // 15 min: a signed URL minted while a run was public stays valid for
  // its full TTL at the Storage layer even after the run flips private,
  // so a shorter TTL shrinks that revocation gap. Kept well above the
  // 5-min refresh-ahead window below so a render never lands on a URL
  // that expires before the bytes arrive.
  static const int _signedUrlTtlSeconds = 15 * 60;
  // Refresh anything older than (TTL - 5 min) so a render mid-fetch
  // never lands on a URL that expires before the image bytes arrive.
  static const int _signedUrlRefreshAheadSeconds = 5 * 60;

  bool get _canManage => widget.api.userId == widget.runOwnerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captionCtrl.dispose();
    _pendingCaptionCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-sign on app foreground so a screen kept open past the
    // refresh-ahead threshold (TTL - 5 min) refreshes before the
    // user sees broken images. _signPaths is idempotent — entries
    // still inside the freshness window are a no-op.
    if (state == AppLifecycleState.resumed && _photos.isNotEmpty) {
      _signPaths(_pathsToSign(_photos));
    }
  }

  /// All paths that need signed URLs — the original for the lightbox
  /// + each present thumb_512_path for the gallery. Skips null
  /// thumbnails so we don't pad the signing batch with empty rows.
  List<String> _pathsToSign(List<RunPhotoRow> ps) {
    final out = <String>[];
    for (final p in ps) {
      out.add(p.storagePath);
      final t = p.thumb512Path;
      if (t != null && t.isNotEmpty) out.add(t);
    }
    return out;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ps = await widget.api.fetchRunPhotos(widget.runId);
      await _signPaths(_pathsToSign(ps));
      if (!mounted) return;
      setState(() {
        _photos = ps;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _signPaths(List<String> paths) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final refreshIfOlderMs =
        (_signedUrlTtlSeconds - _signedUrlRefreshAheadSeconds) * 1000;
    final missing = paths.where((p) {
      final entry = _signedUrls[p];
      if (entry == null) return true;
      return nowMs - entry.signedAtMs > refreshIfOlderMs;
    }).toList();
    if (missing.isEmpty) return;
    try {
      final signed = await Supabase.instance.client.storage
          .from('run-photos')
          .createSignedUrls(missing, _signedUrlTtlSeconds);
      for (final s in signed) {
        if (s.path.isNotEmpty) {
          _signedUrls[s.path] = _SignedEntry(s.signedUrl, nowMs);
        }
      }
    } catch (e) {
      debugPrint('run-photos signed-url batch failed: $e');
    }
  }

  String _photoUrl(String storagePath) =>
      _signedUrls[storagePath]?.url ?? '';

  /// Prefer the 512w thumbnail when the worker has filled it in;
  /// fall back to the original. Used by the gallery tile; the
  /// lightbox still pulls the original via [_photoUrl] for full
  /// quality. Empty string when neither URL has been signed yet so
  /// the Image.network errorBuilder fires the placeholder.
  String _galleryUrl(RunPhotoRow p) {
    final t = p.thumb512Path;
    if (t != null && t.isNotEmpty) {
      final url = _signedUrls[t]?.url;
      if (url != null && url.isNotEmpty) return url;
    }
    return _photoUrl(p.storagePath);
  }

  Future<void> _pickPhoto() async {
    try {
      final f = await (widget.pickImageOverride ??
          () => _picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
                maxWidth: 2048,
              ))();
      if (f == null) return;
      setState(() {
        _pending = f;
        _pendingCaptionCtrl.text = '';
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      // The picker throws a permission-denied PlatformException when the
      // OS photo-library grant is missing — surface friendly copy + a
      // one-tap route into app settings (mirrors the notification-hint +
      // barcode-scan siblings). Any other failure gets a generic friendly
      // message; never dump the raw exception ('$e') into the banner.
      if (e is PlatformException && e.code == 'photo_access_denied') {
        showTopBanner(
          context,
          l10n.runPhotosPermissionDenied,
          actionLabel: l10n.runPhotosOpenSettings,
          onAction: () => openAppSettings(),
          duration: const Duration(seconds: 6),
        );
      } else {
        showTopBanner(context, l10n.runPhotosPickerFailed);
      }
    }
  }

  Future<void> _uploadPending() async {
    final f = _pending;
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await f.readAsBytes();
      // Strip EXIF/XMP (incl. GPS) before the bytes leave the device: the
      // server worker only strips JPEG, and only after upload. Sniff the
      // bytes rather than trusting the picked filename, and refuse a
      // format we cannot clean instead of shipping the capture GPS.
      final raw = Uint8List.fromList(bytes);
      final contentType = detectImageMime(raw);
      if (contentType == null) throw const UnstrippableImageException('');
      final clean = stripImageExif(raw, contentType);
      final ext = imageExtensionForMime(contentType);
      final added = await widget.api.addRunPhoto(
        runId: widget.runId,
        bytes: clean,
        contentType: contentType,
        extension: ext,
        caption: _pendingCaptionCtrl.text.trim().isEmpty
            ? null
            : _pendingCaptionCtrl.text.trim(),
        positionIdx: _photos.length,
      );
      await _signPaths([added.storagePath]);
      if (!mounted) return;
      setState(() {
        _photos = [..._photos, added];
        _pending = null;
        _pendingCaptionCtrl.clear();
        _uploading = false;
      });
    } catch (e) {
      debugPrint('run photos upload error: $e');
      if (!mounted) return;
      setState(() => _uploading = false);
      showTopBanner(
          context, AppLocalizations.of(context).runPhotosUploadError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  Future<void> _deletePhoto(RunPhotoRow p) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.runPhotosDeleteTitle,
      body: l10n.runPhotosDeleteBody,
      confirmLabel: l10n.runPhotosDeleteConfirm,
      cancelLabel: l10n.runPhotosCancel,
    );
    if (!ok) return;
    try {
      await widget.api.deleteRunPhoto(p);
      if (!mounted) return;
      setState(() => _photos = _photos.where((q) => q.id != p.id).toList());
    } catch (e) {
      debugPrint('run photos delete error: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).runPhotosDeleteError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  void _startEdit(RunPhotoRow p) {
    setState(() {
      _editingId = p.id;
      _captionCtrl.text = p.caption ?? '';
    });
  }

  Future<void> _saveCaption() async {
    final id = _editingId;
    if (id == null) return;
    final next = _captionCtrl.text.trim();
    final value = next.isEmpty ? null : next;
    setState(() => _editingId = null);
    try {
      await widget.api.updateRunPhotoCaption(photoId: id, caption: value);
      if (!mounted) return;
      setState(() {
        _photos = _photos
            .map((p) => p.id == id
                ? RunPhotoRow(
                    id: p.id,
                    runId: p.runId,
                    ownerId: p.ownerId,
                    storagePath: p.storagePath,
                    caption: value,
                    positionIdx: p.positionIdx,
                    createdAt: p.createdAt,
                  )
                : p)
            .toList();
      });
    } catch (e) {
      debugPrint('run photos caption error: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).runPhotosCaptionError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  void _openLightbox(RunPhotoRow p) =>
      showPhotoLightbox(context, url: _photoUrl(p.storagePath), caption: p.caption);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(l10n.runPhotosLoading),
      );
    }
    if (_photos.isEmpty && !_canManage) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(l10n.runPhotosTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                    ),
                    if (_photos.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('(${_photos.length})',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (_canManage)
                TextButton.icon(
                  onPressed: _pending == null ? _pickPhoto : null,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(l10n.runPhotosAdd),
                ),
            ],
          ),
        ),
        if (_pending != null && _canManage)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: cs.outlineVariant, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerHighest,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_pending!.path),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _pendingCaptionCtrl,
                        maxLength: 280,
                        enabled: !_uploading,
                        decoration: InputDecoration(
                          hintText: l10n.runPhotosCaptionPendingHint,
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _uploading
                                ? null
                                : () => setState(() {
                                      _pending = null;
                                      _pendingCaptionCtrl.clear();
                                    }),
                            child: Text(l10n.runPhotosCancel),
                          ),
                          FilledButton(
                            onPressed: _uploading ? null : _uploadPending,
                            child: Text(_uploading
                                ? l10n.runPhotosUploading
                                : l10n.runPhotosUpload),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_photos.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, i) => _buildTile(_photos[i], theme),
          ),
      ],
    );
  }

  Widget _buildTile(RunPhotoRow p, ThemeData theme) {
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final editing = _editingId == p.id;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              // A bare Image under a GestureDetector is, to TalkBack, an
              // unlabelled roleless rectangle — so the gallery could not be
              // browsed or opened without sight. Web already ships this as a
              // <button aria-label> wrapping an <img alt>; this is mobile
              // catching up to it.
              child: Semantics(
                button: true,
                image: true,
                label: (p.caption?.trim().isNotEmpty ?? false)
                    ? p.caption!.trim()
                    : l10n.photoOpen,
                child: GestureDetector(
                  onTap: () => _openLightbox(p),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _galleryUrl(p),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (editing)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _captionCtrl,
                      maxLength: 280,
                      decoration: InputDecoration(
                        hintText: l10n.runPhotosCaptionHint,
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 4),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      overflowAlignment: OverflowBarAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _editingId = null),
                          child: Text(l10n.runPhotosCancel),
                        ),
                        FilledButton(
                          onPressed: _saveCaption,
                          child: Text(l10n.runPhotosSave),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (p.caption != null && p.caption!.isNotEmpty)
              Text(
                p.caption!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        if (_canManage && !editing)
          Positioned(
            top: 4,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _circleBtn(
                  icon: Icons.edit_outlined,
                  tooltip: l10n.runPhotosEditCaption,
                  onPressed: () => _startEdit(p),
                ),
                const SizedBox(width: 4),
                _circleBtn(
                  icon: Icons.delete_outline,
                  tooltip: l10n.runPhotosDeleteTooltip,
                  onPressed: () => _deletePhoto(p),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}


class _SignedEntry {
  final String url;
  final int signedAtMs;
  const _SignedEntry(this.url, this.signedAtMs);
}
