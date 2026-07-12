import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../exif_strip.dart';
import '../l10n/gen/app_localizations.dart';
import '../social_service.dart' show RecentRunRow;
import 'run_photos.dart' show extensionForFilename, contentTypeForExtension;
import 'top_banner.dart';

/// Mirrors the web event-detail Photos section (persona #49): the
/// multi-attendee gallery of photos tagged to one event instance, readable
/// even when the underlying run is private (`fetchEventPhotos` RLS). Any
/// signed-in viewer can add: a finisher attaches to their own event run
/// (`myEventRunId`) with zero extra taps, everyone else picks which of
/// their recent runs the photo belongs to. Read-only for anon viewers.
class EventPhotos extends StatefulWidget {
  final ApiClient api;
  final String eventId;
  final DateTime instanceStart;

  /// The viewer's own finished run for this event, if any — a photo from a
  /// finisher attaches straight to it (web's `myEventRunId` fast path).
  final String? myEventRunId;

  /// Whether the viewer may add a photo (signed in). Anon viewers see the
  /// gallery read-only.
  final bool canAdd;

  /// Recent-run source for the non-finisher "which run is this from?"
  /// picker. Injected so the widget stays free of `SocialService`.
  final Future<List<RecentRunRow>> Function() fetchRecentRuns;

  /// Test seam — inject the gallery-pick source so the picker's error paths
  /// (permission denial, generic failure) are drivable without a real photo
  /// picker. Defaults to the live [ImagePicker] gallery pick.
  final Future<XFile?> Function()? pickImageOverride;

  const EventPhotos({
    super.key,
    required this.api,
    required this.eventId,
    required this.instanceStart,
    required this.canAdd,
    required this.fetchRecentRuns,
    this.myEventRunId,
    this.pickImageOverride,
  });

  @override
  State<EventPhotos> createState() => _EventPhotosState();
}

class _EventPhotosState extends State<EventPhotos> {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _uploading = false;
  List<EventPhotoView> _photos = const [];
  final Map<String, _SignedEntry> _signedUrls = <String, _SignedEntry>{};
  static const int _signedUrlTtlSeconds = 15 * 60;
  static const int _signedUrlRefreshAheadSeconds = 5 * 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> _pathsToSign(List<EventPhotoView> ps) {
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
      final ps = await widget.api
          .fetchEventPhotos(widget.eventId, widget.instanceStart);
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
      debugPrint('event-photos signed-url batch failed: $e');
    }
  }

  String _photoUrl(String storagePath) => _signedUrls[storagePath]?.url ?? '';

  String _galleryUrl(EventPhotoView p) {
    final t = p.thumb512Path;
    if (t != null && t.isNotEmpty) {
      final url = _signedUrls[t]?.url;
      if (url != null && url.isNotEmpty) return url;
    }
    return _photoUrl(p.storagePath);
  }

  Future<XFile?> _pick() async {
    return (widget.pickImageOverride ??
        () => _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: 2048,
            ))();
  }

  /// Resolve which run the photo attaches to, then pick + upload. A
  /// finisher goes straight to the picker via [myEventRunId]; everyone
  /// else chooses one of their recent runs first.
  Future<void> _openPhotoFlow() async {
    if (_uploading) return;
    final direct = widget.myEventRunId;
    if (direct != null) {
      await _pickAndUpload(direct);
      return;
    }
    final runs = await widget.fetchRecentRuns();
    if (!mounted) return;
    final runId = await _showRunPicker(runs);
    if (runId == null) return;
    await _pickAndUpload(runId);
  }

  Future<String?> _showRunPicker(List<RecentRunRow> runs) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(l10n.eventWhichRunPhoto,
                    style: theme.textTheme.titleMedium),
              ),
              if (runs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Text(l10n.eventNoRecentRuns,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in runs)
                        ListTile(
                          leading: const Icon(Icons.directions_run),
                          title: Text(
                            '${(r.distanceM / 1000).toStringAsFixed(2)} km'
                            ' · ${_dur(r.durationS)}',
                          ),
                          subtitle: Text(_dateLabel(r.startedAt)),
                          onTap: () => Navigator.pop(ctx, r.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUpload(String runId) async {
    XFile? file;
    try {
      file = await _pick();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
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
      return;
    }
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final clean = stripJpegExif(Uint8List.fromList(bytes));
      final ext = extensionForFilename(file.name);
      await widget.api.addRunPhoto(
        runId: runId,
        bytes: clean,
        contentType: contentTypeForExtension(ext),
        extension: ext,
        positionIdx: 0,
        eventId: widget.eventId,
        eventInstanceStart: widget.instanceStart,
      );
      await _load();
      if (mounted) setState(() => _uploading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showTopBanner(context, AppLocalizations.of(context).eventPhotoUploadFailed);
    }
  }

  void _openLightbox(EventPhotoView p) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          child: Center(
            child: Image.network(_photoUrl(p.storagePath), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  String _dur(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _dateLabel(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    return '${local.year}-${local.month.toString().padLeft(2, '0')}'
        '-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    if (_loading) return const SizedBox.shrink();
    if (_photos.isEmpty && !widget.canAdd) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.photo_library_outlined,
                size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(l10n.eventPhotosTitle(_photos.length),
                style: theme.textTheme.titleMedium),
            const Spacer(),
            if (widget.canAdd)
              TextButton.icon(
                onPressed: _uploading ? null : _openPhotoFlow,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(
                    _uploading ? l10n.eventPhotoUploading : l10n.eventAddPhoto),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_photos.isEmpty)
          Text(
            widget.canAdd
                ? '${l10n.eventNoPhotosYet} ${l10n.eventNoPhotosAddHint}'
                : l10n.eventNoPhotosYet,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _photos)
                _PhotoTile(
                  url: _galleryUrl(p),
                  caption: p.caption,
                  uploader: p.uploaderName ?? l10n.eventPhotoRunnerFallback,
                  onTap: () => _openLightbox(p),
                ),
            ],
          ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final String? caption;
  final String uploader;
  final VoidCallback onTap;
  const _PhotoTile({
    required this.url,
    required this.caption,
    required this.uploader,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 150,
                height: 150,
                color: cs.surfaceContainerHighest,
                child: url.isEmpty
                    ? Icon(Icons.image_outlined, color: cs.onSurfaceVariant)
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_outlined,
                            color: cs.onSurfaceVariant),
                      ),
              ),
            ),
          ),
          if (caption != null && caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(uploader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _SignedEntry {
  final String url;
  final int signedAtMs;
  const _SignedEntry(this.url, this.signedAtMs);
}
