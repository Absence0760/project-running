import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth_error.dart';
import '../exif_strip.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';

/// Map a picked filename to the extension we'll store the upload under.
/// `jpeg` collapses to `jpg`, `heif` collapses to `heic`, and anything
/// missing or extension-less defaults to `jpg`.
String clubPhotoExtensionForFilename(String filename) {
  final n = filename.toLowerCase();
  final dot = n.lastIndexOf('.');
  if (dot <= 0) return 'jpg';
  final raw = n.substring(dot + 1);
  if (raw == 'jpeg') return 'jpg';
  if (raw == 'heif') return 'heic';
  return raw;
}

/// Storage `Content-Type` to send for a given extension. Keeps the
/// browser-served preview correct on the web share pages.
String clubPhotoContentTypeForExtension(String ext) {
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    default:
      return 'image/jpeg';
  }
}

/// Mirrors the web `ClubPhotos.svelte` — grid of photos for a club.
/// [canUpload] is true for any active member; [canModerate] for an
/// owner/admin (delete anyone's photo). Caption edit is photo-owner only.
class ClubPhotos extends StatefulWidget {
  final ApiClient api;
  final String clubId;
  final bool canUpload;
  final bool canModerate;

  const ClubPhotos({
    super.key,
    required this.api,
    required this.clubId,
    this.canUpload = false,
    this.canModerate = false,
  });

  @override
  State<ClubPhotos> createState() => _ClubPhotosState();
}

class _ClubPhotosState extends State<ClubPhotos> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _uploading = false;
  String? _editingId;
  final _captionCtrl = TextEditingController();
  final _pendingCaptionCtrl = TextEditingController();
  XFile? _pending;
  List<ClubPhotoRow> _photos = const [];
  // storage_path → (url, signedAtMs). The bucket is private (migration
  // 20270301_001), so getPublicUrl never returns bytes — every render path
  // goes through createSignedUrl. Cached entries older than the
  // refresh-ahead window are re-signed so a foregrounded screen never shows
  // a broken image.
  final Map<String, _SignedEntry> _signedUrls = <String, _SignedEntry>{};
  static const int _signedUrlTtlSeconds = 15 * 60;
  static const int _signedUrlRefreshAheadSeconds = 5 * 60;

  bool _isOwner(ClubPhotoRow p) => widget.api.userId == p.ownerId;
  bool _canDelete(ClubPhotoRow p) => widget.canModerate || _isOwner(p);

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
    if (state == AppLifecycleState.resumed && _photos.isNotEmpty) {
      _signPaths(_pathsToSign(_photos));
    }
  }

  List<String> _pathsToSign(List<ClubPhotoRow> ps) {
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
      final ps = await widget.api.fetchClubPhotos(widget.clubId);
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
          .from(StorageBuckets.clubPhotos)
          .createSignedUrls(missing, _signedUrlTtlSeconds);
      for (final s in signed) {
        if (s.path.isNotEmpty) {
          _signedUrls[s.path] = _SignedEntry(s.signedUrl, nowMs);
        }
      }
    } catch (e) {
      debugPrint('club-photos signed-url batch failed: $e');
    }
  }

  String _photoUrl(String storagePath) => _signedUrls[storagePath]?.url ?? '';

  String _galleryUrl(ClubPhotoRow p) {
    final t = p.thumb512Path;
    if (t != null && t.isNotEmpty) {
      final url = _signedUrls[t]?.url;
      if (url != null && url.isNotEmpty) return url;
    }
    return _photoUrl(p.storagePath);
  }

  Future<void> _pickPhoto() async {
    try {
      final f = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (f == null) return;
      setState(() {
        _pending = f;
        _pendingCaptionCtrl.text = '';
      });
    } catch (e) {
      debugPrint('club photos picker error: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubPhotosPickerError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  Future<void> _uploadPending() async {
    final f = _pending;
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await f.readAsBytes();
      // Strip EXIF/XMP (incl. GPS) before the bytes leave the device — the
      // server worker strips too, but only after upload, leaving a
      // geotagged-original window in the bucket.
      final clean = stripJpegExif(Uint8List.fromList(bytes));
      final ext = clubPhotoExtensionForFilename(f.name);
      final added = await widget.api.addClubPhoto(
        clubId: widget.clubId,
        bytes: clean,
        contentType: clubPhotoContentTypeForExtension(ext),
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
      debugPrint('club photos upload error: $e');
      if (!mounted) return;
      setState(() => _uploading = false);
      showTopBanner(
          context, AppLocalizations.of(context).clubPhotosUploadError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  Future<void> _deletePhoto(ClubPhotoRow p) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.clubPhotosDeleteTitle),
            content: Text(l10n.clubPhotosDeleteBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.clubPhotosCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.clubPhotosDeleteConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.api.deleteClubPhoto(p);
      if (!mounted) return;
      setState(() => _photos = _photos.where((q) => q.id != p.id).toList());
    } catch (e) {
      debugPrint('club photos delete error: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubPhotosDeleteError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  void _startEdit(ClubPhotoRow p) {
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
      await widget.api.updateClubPhotoCaption(photoId: id, caption: value);
      if (!mounted) return;
      setState(() {
        _photos = _photos
            .map((p) => p.id == id
                ? ClubPhotoRow(
                    id: p.id,
                    clubId: p.clubId,
                    ownerId: p.ownerId,
                    storagePath: p.storagePath,
                    thumb512Path: p.thumb512Path,
                    caption: value,
                    positionIdx: p.positionIdx,
                    createdAt: p.createdAt,
                  )
                : p)
            .toList();
      });
    } catch (e) {
      debugPrint('club photos caption error: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubPhotosCaptionError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  void _openLightbox(ClubPhotoRow p) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Image.network(
                _photoUrl(p.storagePath),
                fit: BoxFit.contain,
              ),
            ),
            if (p.caption != null && p.caption!.isNotEmpty)
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
                    p.caption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(l10n.clubPhotosLoading),
      );
    }
    if (_photos.isEmpty && !widget.canUpload) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(l10n.clubPhotosEmpty,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
      );
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
              Text(l10n.clubPhotosTitle, style: theme.textTheme.titleMedium),
              if (_photos.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('(${_photos.length})',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
              const Spacer(),
              if (widget.canUpload)
                TextButton.icon(
                  onPressed: _pending == null ? _pickPhoto : null,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(l10n.clubPhotosAdd),
                ),
            ],
          ),
        ),
        if (_photos.isEmpty && widget.canUpload && _pending == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.clubPhotosEmpty,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
        if (_pending != null && widget.canUpload)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: cs.outlineVariant, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(10),
              color: cs.surfaceContainerHighest,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
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
                          hintText: l10n.clubPhotosCaptionPendingHint,
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _uploading
                                ? null
                                : () => setState(() {
                                      _pending = null;
                                      _pendingCaptionCtrl.clear();
                                    }),
                            child: Text(l10n.clubPhotosCancel),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _uploading ? null : _uploadPending,
                            child: Text(_uploading
                                ? l10n.clubPhotosUploading
                                : l10n.clubPhotosUpload),
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

  Widget _buildTile(ClubPhotoRow p, ThemeData theme) {
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
                        hintText: l10n.clubPhotosCaptionHint,
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _editingId = null),
                          child: Text(l10n.clubPhotosCancel),
                        ),
                        FilledButton(
                          onPressed: _saveCaption,
                          child: Text(l10n.clubPhotosSave),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (p.caption != null && p.caption!.isNotEmpty)
              Text(
                p.caption!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        if (!editing && (_isOwner(p) || _canDelete(p)))
          Positioned(
            top: 4,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isOwner(p))
                  _circleBtn(
                    icon: Icons.edit_outlined,
                    tooltip: l10n.clubPhotosEditCaption,
                    onPressed: () => _startEdit(p),
                  ),
                if (_isOwner(p) && _canDelete(p)) const SizedBox(width: 4),
                if (_canDelete(p))
                  _circleBtn(
                    icon: Icons.delete_outline,
                    tooltip: l10n.clubPhotosDeleteTooltip,
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
