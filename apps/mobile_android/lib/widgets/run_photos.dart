import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Map a picked filename to the extension we'll store the upload under.
/// `jpeg` collapses to `jpg` (Storage path stays consistent regardless of
/// what the picker reports), `heif` collapses to `heic` (same canonical
/// container), and anything missing or extension-less defaults to `jpg`.
String extensionForFilename(String filename) {
  final n = filename.toLowerCase();
  final dot = n.lastIndexOf('.');
  if (dot <= 0) return 'jpg';
  final raw = n.substring(dot + 1);
  if (raw == 'jpeg') return 'jpg';
  if (raw == 'heif') return 'heic';
  return raw;
}

/// Storage `Content-Type` to send for a given extension. Keeps the
/// browser-served preview correct on web run-share pages — the
/// `run-photos` bucket is public-read, so the type round-trips.
String contentTypeForExtension(String ext) {
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

/// Mirrors the web `RunPhotos.svelte` — grid of photos for a run, with
/// owner-gated upload (image_picker), caption edit, and delete.
class RunPhotos extends StatefulWidget {
  final ApiClient api;
  final String runId;
  final String runOwnerId;

  const RunPhotos({
    super.key,
    required this.api,
    required this.runId,
    required this.runOwnerId,
  });

  @override
  State<RunPhotos> createState() => _RunPhotosState();
}

class _RunPhotosState extends State<RunPhotos> {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _uploading = false;
  String? _editingId;
  final _captionCtrl = TextEditingController();
  final _pendingCaptionCtrl = TextEditingController();
  XFile? _pending;
  List<RunPhotoRow> _photos = const [];

  bool get _canManage => widget.api.userId == widget.runOwnerId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _pendingCaptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ps = await widget.api.fetchRunPhotos(widget.runId);
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

  String _publicUrl(String storagePath) =>
      Supabase.instance.client.storage.from('run-photos').getPublicUrl(storagePath);

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open picker: $e')),
      );
    }
  }

  Future<void> _uploadPending() async {
    final f = _pending;
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await f.readAsBytes();
      final ext = extensionForFilename(f.name);
      final added = await widget.api.addRunPhoto(
        runId: widget.runId,
        bytes: Uint8List.fromList(bytes),
        contentType: contentTypeForExtension(ext),
        extension: ext,
        caption: _pendingCaptionCtrl.text.trim().isEmpty
            ? null
            : _pendingCaptionCtrl.text.trim(),
        positionIdx: _photos.length,
      );
      if (!mounted) return;
      setState(() {
        _photos = [..._photos, added];
        _pending = null;
        _pendingCaptionCtrl.clear();
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<void> _deletePhoto(RunPhotoRow p) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete photo?'),
            content: const Text('This removes the photo from the run permanently.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.api.deleteRunPhoto(p);
      if (!mounted) return;
      setState(() => _photos = _photos.where((q) => q.id != p.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update caption: $e')),
      );
    }
  }

  void _openLightbox(RunPhotoRow p) {
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
                _publicUrl(p.storagePath),
                fit: BoxFit.contain,
              ),
            ),
            if (p.caption != null && p.caption!.isNotEmpty)
              Positioned(
                bottom: 32,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
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

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Loading photos…'),
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
              Text('Photos', style: theme.textTheme.titleMedium),
              if (_photos.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('(${_photos.length})',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant)),
              ],
              const Spacer(),
              if (_canManage)
                TextButton.icon(
                  onPressed: _pending == null ? _pickPhoto : null,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Add photo'),
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
                        decoration: const InputDecoration(
                          hintText: 'Caption (optional, 280 chars)',
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
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _uploading ? null : _uploadPending,
                            child: Text(_uploading ? 'Uploading…' : 'Upload'),
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
                    _publicUrl(p.storagePath),
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
                      decoration: const InputDecoration(
                        hintText: 'Caption…',
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
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: _saveCaption,
                          child: const Text('Save'),
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
                  tooltip: 'Edit caption',
                  onPressed: () => _startEdit(p),
                ),
                const SizedBox(width: 4),
                _circleBtn(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete photo',
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
