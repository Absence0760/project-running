import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, ProgressBar;

import '../backup.dart';
import '../cross_source_dedup.dart';
import '../csv_run_importer.dart';
import '../health_connect_importer.dart';
import '../import_failures.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../strava_importer.dart';
import '../widgets/import_failure_report.dart';

/// Build the post-import status line. Appends a no-route note when the batch
/// came in without any GPS geometry, so a map-less run detail reads as
/// expected rather than a bug (#37). The caller decides — a Health Connect
/// import carries tracks only when the exercise-route permission is granted.
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

  /// Test seam — the Health Connect workout-read permission sheet.
  /// Production callers leave null (the screen calls
  /// `HealthConnectImporter.requestPermission`).
  final Future<bool> Function()? requestHealthPermissionFn;

  /// Test seam — the Health Connect workout read. Production callers leave
  /// null (the screen calls `HealthConnectImporter.fetchWorkouts`).
  final Future<HealthConnectImport> Function()? fetchHealthWorkoutsFn;

  /// Test seam — the exercise-route permission sheet, which refuses outright
  /// off Android. Production callers leave null.
  final Future<bool> Function()? requestHealthRoutePermissionFn;

  /// Test seam — the Health Connect route read, which also refuses outright
  /// off Android. Production callers leave null.
  final Future<HealthConnectRoutes> Function()? fetchHealthRoutesFn;

  const ImportScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    this.routeStore,
    this.preferences,
    this.settingsSync,
    this.requestHealthPermissionFn,
    this.fetchHealthWorkoutsFn,
    this.requestHealthRoutePermissionFn,
    this.fetchHealthRoutesFn,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _busy = false;
  String _status = '';
  int _imported = 0;
  int _total = 0;
  // Warnings from the backup-ZIP restore, which reports whole-archive
  // problems rather than per-activity ones.
  List<String> _errors = [];
  ImportFailureLog _failures = newImportFailureLog();
  String _failureProvider = '';
  // How many runs of the last import are on this device and not on the
  // server. A push that threw defers the whole batch; a push that returned a
  // non-empty `failed` set defers exactly those. Reporting either as a plain
  // success hid it entirely, and reporting only "some" makes 3-of-400
  // indistinguishable from 400-of-400.
  int _cloudPushDeferredCount = 0;
  // Sessions the last Health Connect import found a route for but wasn't
  // allowed to read. Drives the route-permission offer — the runner is never
  // shown it speculatively, only once there are maps behind it.
  Set<String> _withheldRouteIds = const {};

  String get _healthLabel => healthLabelFor(isIOS: Platform.isIOS);

  Future<bool> _requestHealthPermission() =>
      widget.requestHealthPermissionFn?.call() ??
          HealthConnectImporter.requestPermission();

  Future<HealthConnectImport> _fetchHealthWorkouts() =>
      widget.fetchHealthWorkoutsFn?.call() ??
          HealthConnectImporter.fetchWorkouts();

  Future<bool> _requestHealthRoutePermission() =>
      widget.requestHealthRoutePermissionFn?.call() ??
          requestHealthRoutePermission(isAndroid: Platform.isAndroid);

  Future<HealthConnectRoutes> _fetchHealthRoutes() =>
      widget.fetchHealthRoutesFn?.call() ??
          HealthConnectImporter.fetchRoutes();

  Future<void> _importHealthConnect() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = l10n.importHealthRequestingPermission(_healthLabel);
      _imported = 0;
      _total = 0;
      _errors = [];
      _failures = newImportFailureLog();
      _cloudPushDeferredCount = 0;
    });

    try {
      final granted = await _requestHealthPermission();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = l10n.importHealthPermissionDenied(_healthLabel);
        });
        return;
      }

      await _maybeSeedBodyWeight();

      if (!mounted) return;
      setState(() => _status = l10n.importHealthReadingWorkouts);
      final imported = await _fetchHealthWorkouts();
      final runs = imported.runs;
      // Health Connect only releases a workout's route when the exercise-route
      // permission is granted, so an import can land with maps or without.
      // Only claim there are no tracks when there genuinely are none —
      // otherwise the note contradicts the maps the user can see (#37, #664).
      // The note asserts the source has no route data at all, so it is also
      // withheld when we know it does and was simply refused: the offer below
      // says the true thing instead.
      await _saveImportedRuns(
        runs,
        label: _healthLabel,
        provider: 'health',
        failures: imported.failures,
        noGpsNote: runs.every((r) => r.track.isEmpty) &&
            imported.withheldSessionIds.isEmpty,
      );
      if (!mounted) return;
      setState(() => _withheldRouteIds = imported.withheldSessionIds);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l10n.importHealthFailed(_healthLabel, e);
      });
    }
  }

  /// Ask Health Connect for the exercise-route grant, then fill the maps in.
  ///
  /// Reached only by tapping the offer that appears once an import has found
  /// routes it wasn't allowed to read — the second permission sheet is
  /// something the runner asks for, never something that happens because they
  /// tapped "import". Refusal is a normal outcome: the offer goes away and
  /// every already-imported run stays exactly as it is, summary-only.
  Future<void> _allowRouteImport() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = l10n.importHealthRoutesRequesting;
      _errors = [];
      _failures = newImportFailureLog();
      _cloudPushDeferredCount = 0;
    });

    final granted = await _requestHealthRoutePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _busy = false;
        _withheldRouteIds = const {};
        _status = l10n.importHealthRoutesDenied;
      });
      return;
    }

    setState(() => _status = l10n.importHealthRoutesAdding);
    try {
      final backfill = await _backfillHealthConnectTracks();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _withheldRouteIds = const {};
        _cloudPushDeferredCount = backfill.pushDeferredCount;
        _status = l10n.importHealthRoutesAdded(backfill.filled);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _withheldRouteIds = const {};
        _status = l10n.importHealthFailed(_healthLabel, e);
      });
    }
  }

  /// Re-read the routes now that Health Connect will release them and write
  /// them onto the runs already imported without one. A plain re-import can't
  /// do this: `isCrossSourceDuplicate` treats Health Connect as an aggregator
  /// and skips every workout already in the store, so the tracks would never
  /// land. Reports how many runs gained a map, and how many of those maps did
  /// not reach the server — the same two-part answer `_saveImportedRuns`
  /// gives.
  Future<({int filled, int pushDeferredCount})>
      _backfillHealthConnectTracks() async {
    final routes = await _fetchHealthRoutes();
    if (routes.tracks.isEmpty) return (filled: 0, pushDeferredCount: 0);

    // Hydrate only the runs a released route can actually fill — the summary
    // index carries source + external_id, so the whole history is filtered
    // before touching disk.
    final candidates = <Run>[];
    for (final summary in widget.runStore.summaryRuns) {
      final sessionId = HealthConnectImporter.sessionIdOf(summary);
      if (sessionId == null || !routes.tracks.containsKey(sessionId)) continue;
      final full = await widget.runStore.runById(summary.id);
      if (full != null) candidates.add(full);
    }

    final filled =
        HealthConnectImporter.runsWithBackfilledTracks(candidates, routes.tracks);
    // Keep the RESIDENT instances save() returns: markManySynced matches by
    // object identity, and our own `filled` copies can never match it.
    final storedFilled = <Run>[];
    for (final run in filled) {
      storedFilled.add(await widget.runStore.save(run));
    }

    final api = widget.apiClient;
    var pushDeferredCount = 0;
    if (filled.isNotEmpty && api != null && api.userId != null) {
      var landed = const <Run>[];
      try {
        final failed = await api.saveRunsBatch(filled);
        // A non-empty `failed` set is not an error and never throws: the
        // batch landed minus those runs, whose maps are on disk and not on
        // the server. Same claim as a thrown push, for fewer runs.
        pushDeferredCount =
            storedFilled.where((r) => failed.contains(r.id)).length;
        landed =
            storedFilled.where((r) => !failed.contains(r.id)).toList();
      } catch (e) {
        // The maps are on disk; only the upload failed, and SyncService
        // retries it. Same claim, same words as the import path — a map that
        // exists only on this device is not a finished backfill.
        debugPrint('Route backfill cloud push failed: $e');
        pushDeferredCount = filled.length;
      }
      await _markLandedSynced(landed);
    }
    return (filled: filled.length, pushDeferredCount: pushDeferredCount);
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

  /// Record on this device that [landed] reached the server.
  ///
  /// Its own effect, its own catch. A failure here is NOT the deferral the
  /// push sites report: those runs ARE on the server, and only this device's
  /// sidecar note of that fact failed to persist. The next cold start reads
  /// them back as unsynced and `SyncService` pushes them again, which upserts
  /// onto the rows already there — no duplicate, no loss, nothing for the
  /// runner to act on. Folding it into the push's catch reported the whole
  /// batch as sitting on the device when the uploads had all succeeded.
  Future<void> _markLandedSynced(Iterable<Run> landed) async {
    try {
      await widget.runStore.markManySynced(landed);
    } catch (e) {
      debugPrint('Import: recording the pushed runs as synced failed: $e');
    }
  }

  /// Common save loop used by both Strava and Health Connect imports.
  /// Saves each run locally, then batch-pushes to the cloud if signed in.
  /// [failures] carries whatever the parse stage already recorded, so the
  /// report is one list rather than a parse list plus a save list.
  Future<void> _saveImportedRuns(
    List<Run> runs, {
    required String label,
    required String provider,
    ImportFailureLog? failures,
    bool noGpsNote = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _total = runs.length;
      _status = l10n.importStatusSavingLocally;
    });

    final log = failures ?? newImportFailureLog();
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
        // The resident instance, not our own copy — see markManySynced.
        savedRuns.add(await widget.runStore.save(run));
      } catch (e) {
        debugPrint('Import: local save failed for ${run.id}: $e');
        recordImportFailure(
          log,
          name: run.metadata?[MetadataKeys.title]?.toString() ?? '',
          startedAt: run.startedAt.toUtc().toIso8601String(),
          error: e,
        );
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
    var pushDeferredCount = 0;
    if (canSync && savedRuns.isNotEmpty) {
      if (mounted) setState(() => _status = l10n.importStatusSyncingToCloud);
      var landed = const <Run>[];
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
        // partial-success contract as SyncService / background_sync. The ones
        // left out are on disk and not on the server, which is the deferral
        // the catch below reports; a half-landed batch that never threw used
        // to report a clean import.
        pushDeferredCount =
            savedRuns.where((r) => failed.contains(r.id)).length;
        landed = savedRuns.where((r) => !failed.contains(r.id)).toList();
      } catch (e) {
        // The runs are on disk; only the upload failed, and SyncService
        // retries it. Say so instead of reporting a clean import.
        debugPrint('Batch cloud push failed: $e');
        pushDeferredCount = savedRuns.length;
      }
      await _markLandedSynced(landed);
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _failures = log;
      _failureProvider = provider;
      _cloudPushDeferredCount = pushDeferredCount;
      _status = buildImportStatus(
        savedCount: savedRuns.length,
        errorCount: log.total,
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

    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = l10n.importStatusReadingCsv;
      _imported = 0;
      _total = 0;
      _errors = [];
      _failures = newImportFailureLog();
      _cloudPushDeferredCount = 0;
    });

    try {
      final content = await File(path).readAsString();
      final parsed = CsvRunImporter.parse(content);
      await _saveImportedRuns(
        parsed.runs,
        label: 'CSV',
        provider: 'csv',
        failures: parsed.failures,
      );
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

    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = l10n.importStatusRestoringBackup;
      _imported = 0;
      _total = 0;
      _errors = [];
      _failures = newImportFailureLog();
      _cloudPushDeferredCount = 0;
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

    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = l10n.importStatusReadingExport;
      _imported = 0;
      _total = 0;
      _errors = [];
      _failures = newImportFailureLog();
      _cloudPushDeferredCount = 0;
    });

    try {
      final file = File(result.files.first.path!);
      final parsed = await StravaImporter.importFromZip(file);
      await _saveImportedRuns(
        parsed.runs,
        label: 'Strava',
        provider: 'strava',
        failures: parsed.failures,
      );
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
                            color: Color(0xFFFC4C02), size: 24),
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
                                color: theme.colorScheme.onSurfaceVariant,
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
                            color: theme.colorScheme.primary, size: 24),
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
                                color: theme.colorScheme.onSurfaceVariant,
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
                      color: theme.colorScheme.onSurfaceVariant,
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
                  if (_withheldRouteIds.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.importHealthRoutesWithheld(_withheldRouteIds.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _allowRouteImport,
                        icon: const Icon(Icons.map_outlined),
                        label: Text(l10n.importHealthRoutesAllowButton),
                      ),
                    ),
                  ],
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
                            color: theme.colorScheme.tertiary, size: 24),
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
                                color: theme.colorScheme.onSurfaceVariant,
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
                      color: theme.colorScheme.onSurfaceVariant,
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
                          color: AppSemanticColors.of(context)
                              .success
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.unarchive_outlined,
                            color: AppSemanticColors.of(context).success,
                            size: 24),
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
                                color: theme.colorScheme.onSurfaceVariant,
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
                      color: theme.colorScheme.onSurfaceVariant,
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
                      ProgressBar(value: _imported / _total),
                    ],
                    if (!_busy && _cloudPushDeferredCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.importStatusCloudPushDeferred(
                            _cloudPushDeferredCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
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
          if (!_busy && _failures.isNotEmpty) ...[
            const SizedBox(height: 16),
            ImportFailureReport(
              log: _failures,
              provider: _failureProvider,
              onDismiss: () =>
                  setState(() => _failures = newImportFailureLog()),
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
