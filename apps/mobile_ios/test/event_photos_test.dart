import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/social_service.dart' show RecentRunRow;
import '../lib/widgets/event_photos.dart';

EventPhotoView _photo({
  String id = 'p1',
  String owner = 'owner-1',
  String? caption,
  String? uploader = 'Dana',
}) =>
    EventPhotoView(
      id: id,
      ownerId: owner,
      storagePath: '$owner/$id.jpg',
      caption: caption,
      positionIdx: 0,
      createdAt: DateTime.utc(2026, 6, 1),
      uploaderName: uploader,
    );

class _PhotosApi extends ApiClient {
  _PhotosApi({List<EventPhotoView>? seed})
      : _photos = List.of(seed ?? const []);

  final List<EventPhotoView> _photos;
  int addCalls = 0;
  String? lastRunId;
  String? lastEventId;
  DateTime? lastInstance;

  @override
  Future<List<EventPhotoView>> fetchEventPhotos(
    String eventId,
    DateTime instanceStart, {
    int limit = 100,
  }) async =>
      List.of(_photos);

  @override
  Future<RunPhotoRow> addRunPhoto({
    required String runId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    String? caption,
    int positionIdx = 0,
    String? eventId,
    DateTime? eventInstanceStart,
  }) async {
    addCalls++;
    lastRunId = runId;
    lastEventId = eventId;
    lastInstance = eventInstanceStart;
    _photos.add(_photo(id: 'added', uploader: 'Me'));
    return RunPhotoRow(
      id: 'added',
      runId: runId,
      ownerId: 'me',
      storagePath: 'me/added.$extension',
      positionIdx: positionIdx,
      createdAt: DateTime.now(),
      eventId: eventId,
      eventInstanceStart: eventInstanceStart,
    );
  }
}

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

EventPhotos _widget(
  _PhotosApi api, {
  bool canAdd = true,
  String? myEventRunId,
  List<RecentRunRow> recent = const [],
}) =>
    EventPhotos(
      api: api,
      eventId: 'event-1',
      instanceStart: DateTime.utc(2026, 6, 10, 8),
      canAdd: canAdd,
      myEventRunId: myEventRunId,
      fetchRecentRuns: () async => recent,
      pickImageOverride: () async =>
          XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'shot.jpg'),
    );

void main() {
  testWidgets('empty gallery + canAdd shows title, add button, hint',
      (tester) async {
    final api = _PhotosApi();
    await tester.pumpWidget(_host(_widget(api)));
    await tester.pumpAndSettle();
    expect(find.text('Photos (0)'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.textContaining('No photos yet.'), findsOneWidget);
  });

  testWidgets('empty gallery for anon viewer renders nothing', (tester) async {
    final api = _PhotosApi();
    await tester.pumpWidget(_host(_widget(api, canAdd: false)));
    await tester.pumpAndSettle();
    expect(find.text('Photos (0)'), findsNothing);
    expect(find.text('Add photo'), findsNothing);
  });

  testWidgets('seeded photos render tiles with uploader + caption',
      (tester) async {
    final api = _PhotosApi(seed: [
      _photo(id: 'a', caption: 'Great day', uploader: 'Dana'),
      _photo(id: 'b', uploader: null),
    ]);
    await tester.pumpWidget(_host(_widget(api, canAdd: false)));
    await tester.pumpAndSettle();
    expect(find.text('Photos (2)'), findsOneWidget);
    expect(find.text('Great day'), findsOneWidget);
    expect(find.text('Dana'), findsOneWidget);
    // Null uploader falls back to the "A runner" label.
    expect(find.text('A runner'), findsOneWidget);
  });

  testWidgets('finisher add attaches to own event run', (tester) async {
    final api = _PhotosApi();
    await tester.pumpWidget(_host(_widget(api, myEventRunId: 'run-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    expect(api.addCalls, 1);
    expect(api.lastRunId, 'run-me');
    expect(api.lastEventId, 'event-1');
    expect(api.lastInstance, DateTime.utc(2026, 6, 10, 8));
    expect(find.text('Photos (1)'), findsOneWidget);
  });

  testWidgets('non-finisher add picks a recent run first', (tester) async {
    final api = _PhotosApi();
    final recent = [
      RecentRunRow(
        id: 'run-pick',
        startedAt: DateTime.utc(2026, 6, 9, 7),
        durationS: 1800,
        distanceM: 5000,
        activityType: 'run',
      ),
    ];
    await tester.pumpWidget(_host(_widget(api, recent: recent)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    // The run picker sheet is open — choose the run.
    expect(find.text('Which run is this photo from?'), findsOneWidget);
    await tester.tap(find.textContaining('5.00 km'));
    await tester.pumpAndSettle();
    expect(api.addCalls, 1);
    expect(api.lastRunId, 'run-pick');
    expect(api.lastEventId, 'event-1');
  });
}
