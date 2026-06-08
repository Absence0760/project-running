import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  Run buildRun({
    Map<String, dynamic>? metadata,
    String? externalId,
    RunSource source = RunSource.app,
    List<Waypoint> track = const [],
  }) =>
      Run(
        id: 'run-1',
        startedAt: DateTime.utc(2026, 4, 23, 8),
        duration: const Duration(minutes: 30, seconds: 47),
        distanceMetres: 5234.5,
        track: track,
        source: source,
        externalId: externalId,
        metadata: metadata,
      );

  group('fromRun', () {
    test('extracts the metadata-derived scalars', () {
      final summary = RunSummary.fromRun(
        buildRun(
          source: RunSource.strava,
          externalId: 'strava:99',
          metadata: {
            MetadataKeys.activityType: 'trail',
            MetadataKeys.avgBpm: 162,
            MetadataKeys.elevationM: 845,
            MetadataKeys.indoor: true,
            MetadataKeys.lastModifiedAt: '2026-04-23T09:00:00.000Z',
            MetadataKeys.createdByUserId: 'user-7',
            MetadataKeys.laps: [
              {'distance_m': 1000}
            ],
          },
        ),
        synced: true,
      );

      expect(summary.id, 'run-1');
      expect(summary.startedAt, DateTime.utc(2026, 4, 23, 8));
      expect(summary.duration, const Duration(minutes: 30, seconds: 47));
      expect(summary.distanceMetres, 5234.5);
      expect(summary.source, RunSource.strava);
      expect(summary.activityType, 'trail');
      expect(summary.externalId, 'strava:99');
      expect(summary.avgBpm, 162.0);
      expect(summary.elevationM, 845.0);
      expect(summary.indoor, true);
      expect(summary.lastModifiedAt, '2026-04-23T09:00:00.000Z');
      expect(summary.createdByUserId, 'user-7');
      expect(summary.synced, true);
    });

    test('null metadata leaves the derived fields null/default', () {
      final summary = RunSummary.fromRun(buildRun(), synced: false);
      expect(summary.activityType, isNull);
      expect(summary.avgBpm, isNull);
      expect(summary.elevationM, isNull);
      expect(summary.indoor, false);
      expect(summary.lastModifiedAt, isNull);
      expect(summary.createdByUserId, isNull);
      expect(summary.synced, false);
    });
  });

  group('toRun', () {
    test('round-trips scalars with an empty track and rebuilt metadata', () {
      final summary = RunSummary.fromRun(
        buildRun(
          source: RunSource.watch,
          externalId: 'x:1',
          track: const [Waypoint(lat: 1, lng: 2)],
          metadata: {
            MetadataKeys.activityType: 'walk',
            MetadataKeys.avgBpm: 120,
            MetadataKeys.elevationM: 312,
            MetadataKeys.indoor: true,
            MetadataKeys.lastModifiedAt: '2026-04-23T09:00:00.000Z',
            MetadataKeys.createdByUserId: 'user-7',
          },
        ),
        synced: true,
      );

      final run = summary.toRun();
      expect(run.id, 'run-1');
      expect(run.startedAt, DateTime.utc(2026, 4, 23, 8));
      expect(run.duration, const Duration(minutes: 30, seconds: 47));
      expect(run.distanceMetres, 5234.5);
      expect(run.source, RunSource.watch);
      expect(run.externalId, 'x:1');
      // Track is never carried by the summary.
      expect(run.track, isEmpty);
      expect(run.routeId, isNull);
      expect(run.createdAt, isNull);
      expect(run.metadata?[MetadataKeys.activityType], 'walk');
      expect(run.metadata?[MetadataKeys.avgBpm], 120.0);
      expect(run.metadata?[MetadataKeys.lastModifiedAt],
          '2026-04-23T09:00:00.000Z');
      expect(run.metadata?[MetadataKeys.createdByUserId], 'user-7');
      expect(run.metadata?[MetadataKeys.elevationM], 312.0);
      expect(run.metadata?[MetadataKeys.indoor], true);
    });

    test('metadata is null when no derived fields are present', () {
      final run = RunSummary.fromRun(buildRun(), synced: false).toRun();
      expect(run.metadata, isNull);
    });

    test('indoor is omitted from rebuilt metadata when false', () {
      // Consumers test `metadata[indoor] != true`; an outdoor run must not
      // carry the key at all.
      final run = RunSummary.fromRun(
        buildRun(metadata: {MetadataKeys.activityType: 'run'}),
        synced: false,
      ).toRun();
      expect(run.metadata?.containsKey(MetadataKeys.indoor), isFalse);
    });
  });

  group('index json', () {
    test('round-trips through toIndexJson/fromIndexJson including nulls', () {
      final summary = RunSummary.fromRun(
        buildRun(
          source: RunSource.parkrun,
          externalId: null,
          metadata: {MetadataKeys.activityType: 'run'},
        ),
        synced: true,
      );

      final restored = RunSummary.fromIndexJson(summary.toIndexJson());
      expect(restored.id, summary.id);
      expect(restored.startedAt, summary.startedAt);
      expect(restored.duration, summary.duration);
      expect(restored.distanceMetres, summary.distanceMetres);
      expect(restored.source, RunSource.parkrun);
      expect(restored.activityType, 'run');
      expect(restored.externalId, isNull);
      expect(restored.avgBpm, isNull);
      expect(restored.lastModifiedAt, isNull);
      expect(restored.createdByUserId, isNull);
      expect(restored.synced, true);
    });

    test('round-trips elevation + indoor through the index', () {
      final summary = RunSummary.fromRun(
        buildRun(metadata: {
          MetadataKeys.elevationM: 712,
          MetadataKeys.indoor: true,
        }),
        synced: false,
      );
      final restored = RunSummary.fromIndexJson(summary.toIndexJson());
      expect(restored.elevationM, 712.0);
      expect(restored.indoor, true);
    });

    test('source falls back to app for an unknown wire value', () {
      final j = RunSummary.fromRun(buildRun(), synced: false).toIndexJson()
        ..['source'] = 'martian';
      expect(RunSummary.fromIndexJson(j).source, RunSource.app);
    });

    test('wire keys are the compact snake_case shape', () {
      final j = RunSummary.fromRun(buildRun(), synced: true).toIndexJson();
      expect(j.keys,
          containsAll(<String>['id', 'started_at', 'duration_us', 'distance_m']));
      expect(j['duration_us'], const Duration(minutes: 30, seconds: 47).inMicroseconds);
    });
  });

  group('withSynced', () {
    test('flips only the synced flag', () {
      final summary = RunSummary.fromRun(buildRun(), synced: false);
      final synced = summary.withSynced(true);
      expect(synced.synced, true);
      expect(synced.id, summary.id);
      expect(synced.startedAt, summary.startedAt);
      expect(synced.distanceMetres, summary.distanceMetres);
    });
  });
}
