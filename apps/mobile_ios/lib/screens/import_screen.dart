import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backup.dart';
import '../cross_source_dedup.dart';
import '../csv_run_importer.dart';
import '../health_connect_importer.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../strava_importer.dart';

/// Build the post-import status line. Appends a no-route note for sources
/// (Health Connect) that expose workout summaries but not GPS geometry, so a
/// map-less run detail reads as expected rather than a bug (#37).
String buildImportStatus({
  required int savedCount,
  required int errorCount,
  required String label,
  required AppLocalizations l10n,
  bool noGpsNote = false,
}) {
  final base = errorCount == 0
      ? l10n.importStatusImported(savedCount, label)
      : l10n.importStatusImportedWithErrors(savedCount, errorCount);
  if (noGpsNote && savedCount > 0) {
    return l10n.importStatusNoGpsNote(base, label);
  }
  return base;
}

/// Bulk import screen — Strava ZIP, Health Connect / Apple Health,
/// CSV summary, and full-backup ZIP. CSV and Backup-ZIP both work
/// **offline-first** so a user can restore on a freshly-installed
/// device before signing in; `SyncService` pushes to Supabase the
/// next time the user signs in.
class ImportScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  /// Optional. When supplied, the Backup-ZIP path also restores routes;
  /// without it the path silently skips them. Callers that don't have a
  /// LocalRouteStore handy (smoke tests, share-target entry points) can
  /// still drive runs-only restore.
  final LocalRouteStore? routeStore;
  /// Optional. When supplied, a Health Connect import that finds a body
  /// weight seeds `body_weight_kg` (only when the user hasn't set one).
  final Preferences? preferences;
  final SettingsSyncService? settingsSync;

  const ImportScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    this.routeStore,
    this.preferences,
    this.settingsSync,
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

  String get _healthLabel => healthLabelFor(isIOS: Platform.isIOS);

  Future<void> _importHealthConnect() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = l10n.importHealthRequestingPermission(_healthLabel);
      _imported = 0;
      _total = 0;
      _errors = [];
    });

    try {
      final granted = await HealthConnectImporter.requestPermission();
      if (!granted) {
        setState(() {
          _busy = false;
          _status = l10n.importHealthPermissionDenied(_healthLabel);
        });
        return;
      }

      await _maybeSeedBodyWeight();

      setState(() => _status = l10n.importHealthReadingWorkouts);
      final runs = await HealthConnectImporter.fetchWorkouts();
      // Health Connect exposes workout summaries but not route geometry, so
      // these runs land without a GPS track / map — tell the user so a
      // map-less run detail doesn't read as a bug (garmin persona #37).
      await _saveImportedRuns(runs, label: _healthLabel, noGpsNote: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l10n.importHealthFailed(_healthLabel, e);
      });
    }
  }

  /// Seed `body_weight_kg` from Health Connect when the user hasn't set
  /// one. Never overwrites an existing weight. Best-effort: a failure here
  /// must not derail the workout import.
  Future<void> _maybeSeedBodyWeight() async {
    final prefs = widget.preferences;
    if (prefs == null || prefs.bodyWeightKg != null) return;
    final kg = await HealthConnectImporter.fetchLatestWeightKg();
    if (kg == null) return;
    prefs.setBodyWeightKg(kg);
    try {
      await widget.settingsSync?.updateUniversal(
        <String, dynamic>{SettingsKeys.bodyWeightKg: kg},
      );
    } catch (e) {
      debugPrint('Body-weight seed sync failed: $e');
    }
  }

  /// Common save loop used by both Strava and Health Connect imports.
  /// Saves each run locally, then batch-pushes to the cloud if signed in.
  Future<void> _saveImportedRuns(List<Run> runs,
      {required String label, bool noGpsNote = false}) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _total = runs.length;
      _status = l10n.importStatusSavingLocally;
    });

    final localErrors = <StravaImportError>[];
    final savedRuns = <Run>[];
    // Persona-hunt Round 2 #3: cross-source dedup. The store's
    // existing runs include any prior Strava + Garmin ZIP imports;
    // an HC import of the same Garmin activity should skip rather
    // than double-count. Same logic in reverse for a Strava-after-HC
    // sequence. Snapshot once before the loop so each fuzzy check
    // runs against a consistent baseline. Reads the full-history index, not the
    // resident window, so a re-import still collides with a run from years ago;
    // isCrossSourceDuplicate only reads source / startedAt / distanceMetres,
    // all carried by the summary.
    final existing = widget.runStore.summaryRuns;
    var skippedCrossSource = 0;

    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      if (isCrossSourceDuplicate(run, existing)) {
        skippedCrossSource++;
        if (mounted) {
          setState(() {
            _imported = i + 1;
            _status =
                l10n.importStatusSkippedDuplicates(skippedCrossSource);
          });
        }
        continue;
      }
      try {
        await widget.runStore.save(run);
        savedRuns.add(run);
      } catch (e) {
        localErrors.add(StravaImportError(run.id, e.toString()));
      }
      if (mounted) {
        setState(() {
          _imported = i + 1;
          _status = l10n.importStatusSavedProgress(i + 1, runs.length);
        });
      }
    }

    final api = widget.apiClient;
    final canSync = api != null && api.userId != null;
    if (canSync && savedRuns.isNotEmpty) {
      if (mounted) setState(() => _status = l10n.importStatusSyncingToCloud);
      try {
        final failed = await api.saveRunsBatch(
          savedRuns,
          onProgress: (saved) {
            if (mounted) {
              setState(() =>
                  _status = l10n.importStatusSyncProgress(saved, savedRuns.length));
            }
          },
        );
        // Mark only the runs that successfully uploaded — same
        // partial-success contract as SyncService / background_sync.
        await widget.runStore.markManySynced(
          savedRuns.where((r) => !failed.contains(r.id)).map((r) => r.id),
        );
      } catch (e) {
        debugPrint('Batch cloud push failed: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = localErrors.map((e) => '${e.filename}: ${e.message}').toList();
      _status = buildImportStatus(
        savedCount: savedRuns.length,
        errorCount: localErrors.length,
        label: label,
        noGpsNote: noGpsNote,
        l10n: l10n,
      );
    });
  }

  Future<void> _importCsv() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _status = l10n.importStatusReadingCsv;
      _imported = 0;
      _total = 0;
      _errors = [];
    });

    try {
      final content = await File(path).readAsString();
      final parsed = CsvRunImporter.parse(content);
      final preErrors =
          parsed.errors.map((e) => e.toString()).toList();
      await _saveImportedRuns(parsed.runs, label: 'CSV');
      if (mounted && preErrors.isNotEmpty) {
        setState(() => _errors = [...preErrors, ..._errors]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l10n.importCsvFailed(e);
      });
    }
  }

  Future<void> _importBackupZip() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _status = l10n.importStatusRestoringBackup;
      _imported = 0;
      _total = 0;
      _errors = [];
    });

    try {
      final res = await BackupService(api: widget.apiClient).restore(
        zipFile: File(path),
        runStore: widget.runStore,
        routeStore: widget.routeStore,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l10n.importStatusBackupRestored(
            res.runsImported, res.tracksUploaded, res.routesImported);
        _errors = res.warnings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l10n.importBackupFailed(e);
      });
    }
  }

  Future<void> _importStrava() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _busy = true;
      _status = l10n.importStatusReadingExport;
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
        _status = l10n.importStravaFailed(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importTitle)),
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
                          color: const Color(0xFFFC4C02).withValues(alpha: 0.15),
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
                            Text(l10n.importStravaCardTitle,
                                style: theme.textTheme.titleMedium),
                            Text(
                              l10n.importStravaCardSubtitle,
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
                    l10n.importStravaHowToHeader,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.importStravaHowToSteps,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _importStrava,
                      icon: const Icon(Icons.upload_file),
                      label: Text(l10n.importStravaButton),
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
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
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
                            Text(_healthLabel,
                                style: theme.textTheme.titleMedium),
                            Text(
                              Platform.isIOS
                                  ? l10n.importHealthSubtitleIos
                                  : l10n.importHealthSubtitleAndroid,
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
                    Platform.isIOS
                        ? l10n.importHealthDescriptionIos
                        : l10n.importHealthDescriptionAndroid,
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
                      label: Text(l10n.importHealthButton(_healthLabel)),
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
                          color: theme.colorScheme.tertiary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.table_chart_outlined,
                            color: theme.colorScheme.tertiary, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.importCsvCardTitle,
                                style: theme.textTheme.titleMedium),
                            Text(
                              l10n.importCsvCardSubtitle,
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
                    l10n.importCsvCardDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _importCsv,
                      icon: const Icon(Icons.upload_file),
                      label: Text(l10n.importCsvButton),
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
                          color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.unarchive_outlined,
                            color: Color(0xFF22C55E), size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.importBackupCardTitle,
                                style: theme.textTheme.titleMedium),
                            Text(
                              l10n.importBackupCardSubtitle,
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
                    l10n.importBackupCardDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _importBackupZip,
                      icon: const Icon(Icons.folder_zip_outlined),
                      label: Text(l10n.importBackupButton),
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
                      Text(l10n.importErrorsHeader,
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
                        Text(l10n.importErrorsMore(_errors.length - 10),
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

/// Human-readable label for the platform-specific health store the
/// `health` package transparently dispatches into. Android backs by
/// Health Connect; iOS backs by HealthKit (Apple Health). Pure
/// function — caller passes `Platform.isIOS` so it's unit-testable
/// without `debugDefaultTargetPlatformOverride` (which only affects
/// the Flutter target platform, not `dart:io`'s `Platform.isIOS`).
String healthLabelFor({required bool isIOS}) =>
    isIOS ? 'Apple Health' : 'Health Connect';
