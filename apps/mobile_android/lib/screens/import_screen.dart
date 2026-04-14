import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../health_connect_importer.dart';
import '../local_run_store.dart';
import '../strava_importer.dart';

/// Bulk import screen — Strava ZIP today, more sources to follow.
class ImportScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;

  const ImportScreen({
    super.key,
    this.apiClient,
    required this.runStore,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _busy = false;
  String _status = '';
  int _imported = 0;
  int _total = 0;
  List<String> _errors = [];

  Future<void> _importHealthConnect() async {
    setState(() {
      _busy = true;
      _status = 'Requesting Health Connect permission...';
      _imported = 0;
      _total = 0;
      _errors = [];
    });

    try {
      final granted = await HealthConnectImporter.requestPermission();
      if (!granted) {
        setState(() {
          _busy = false;
          _status = 'Health Connect permission denied';
        });
        return;
      }

      setState(() => _status = 'Reading workouts...');
      final runs = await HealthConnectImporter.fetchWorkouts();
      await _saveImportedRuns(runs, label: 'Health Connect');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Health Connect import failed: $e';
      });
    }
  }

  /// Common save loop used by both Strava and Health Connect imports.
  /// Saves each run locally, then batch-pushes to the cloud if signed in.
  Future<void> _saveImportedRuns(List<Run> runs, {required String label}) async {
    setState(() {
      _total = runs.length;
      _status = 'Saving locally...';
    });

    final localErrors = <StravaImportError>[];
    final savedRuns = <Run>[];

    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      try {
        await widget.runStore.save(run);
        savedRuns.add(run);
      } catch (e) {
        localErrors.add(StravaImportError(run.id, e.toString()));
      }
      if (mounted) {
        setState(() {
          _imported = i + 1;
          _status = 'Saved ${i + 1} of ${runs.length} locally';
        });
      }
    }

    final api = widget.apiClient;
    final canSync = api != null && api.userId != null;
    if (canSync && savedRuns.isNotEmpty) {
      if (mounted) setState(() => _status = 'Syncing to cloud...');
      try {
        await api.saveRunsBatch(
          savedRuns,
          onProgress: (saved) {
            if (mounted) {
              setState(
                  () => _status = 'Synced $saved of ${savedRuns.length}');
            }
          },
        );
        for (final run in savedRuns) {
          await widget.runStore.markSynced(run.id);
        }
      } catch (e) {
        debugPrint('Batch cloud push failed: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = localErrors.map((e) => '${e.filename}: ${e.message}').toList();
      _status = localErrors.isEmpty
          ? 'Imported ${savedRuns.length} runs from $label'
          : 'Imported ${savedRuns.length} runs (${localErrors.length} failed)';
    });
  }

  Future<void> _importStrava() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Reading export...';
      _imported = 0;
      _total = 0;
      _errors = [];
    });

    try {
      final file = File(result.files.first.path!);
      final parsed = await StravaImporter.importFromZip(file);
      final preErrors = parsed.errors
          .map((e) => '${e.filename}: ${e.message}')
          .toList();
      await _saveImportedRuns(parsed.runs, label: 'Strava');
      if (mounted && preErrors.isNotEmpty) {
        setState(() => _errors = [...preErrors, ..._errors]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Import failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import runs')),
      body: SafeArea(
        top: false,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFC4C02).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.directions_run,
                            color: Color(0xFFFC4C02), size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Strava', style: theme.textTheme.titleMedium),
                            Text(
                              'Import every run from a Strava data export ZIP',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'How to get your Strava export:',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1. Open Strava → Settings → My Account\n'
                    '2. Scroll to "Download or Delete Your Account"\n'
                    '3. Tap "Get Started" → "Request your archive"\n'
                    '4. You\'ll get an email with a download link in a few hours\n'
                    '5. Download the .zip and tap Import below',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _importStrava,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import Strava ZIP'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.favorite,
                            color: theme.colorScheme.primary, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Health Connect',
                                style: theme.textTheme.titleMedium),
                            Text(
                              'Pull workouts from Google Fit, Samsung Health, '
                              'Garmin, Fitbit, and any other Health Connect app',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reads workout summaries (date, distance, duration, type) '
                    'from the last year. GPS routes are not exposed by Health '
                    'Connect — runs imported this way won\'t have a map trace.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _importHealthConnect,
                      icon: const Icon(Icons.health_and_safety),
                      label: const Text('Import from Health Connect'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_busy || _status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_busy) ...[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                        ] else
                          Icon(Icons.check_circle,
                              color: theme.colorScheme.primary, size: 18),
                        if (!_busy) const SizedBox(width: 12),
                        Expanded(child: Text(_status)),
                      ],
                    ),
                    if (_busy && _total > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: _imported / _total),
                    ],
                    if (_errors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('Errors',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 4),
                      ..._errors.take(10).map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(e,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                )),
                          )),
                      if (_errors.length > 10)
                        Text('... and ${_errors.length - 10} more',
                            style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}
