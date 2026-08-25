// The pre-upload strip is the client-side guarantee that a geotagged original
// never leaves the device. Every upload path computed a Content-Type from the
// file extension and then ran the bytes through `stripJpegExif`, which returns
// anything that is not a JPEG unchanged — so a PNG or WebP photo shipped its
// GPS chunk intact. `stripImageExif` is the MIME dispatcher that exists for
// exactly this, and only the avatar upload was using it.

import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_photos.dart';
import 'pump_until.dart';

class _CapturingApi extends ApiClient {
  Uint8List? uploaded;
  String? uploadedContentType;

  @override
  String? get userId => 'owner-1';

  @override
  Future<List<RunPhotoRow>> fetchRunPhotos(String runId,
          {int limit = 50}) async =>
      const [];

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
    uploaded = bytes;
    uploadedContentType = contentType;
    return RunPhotoRow(
      id: 'p1',
      runId: runId,
      ownerId: 'owner-1',
      storagePath: 'owner-1/$runId/p1.$extension',
      createdAt: DateTime.utc(2026, 3, 1),
      positionIdx: positionIdx,
    );
  }
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

List<int> _be32(int v) => [
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >> 8) & 0xff,
      v & 0xff,
    ];

List<int> _pngChunk(String type, List<int> data) {
  final typed = [...type.codeUnits, ...data];
  return [..._be32(data.length), ...typed, ..._be32(_crc32(typed))];
}

/// A real, decodable 1×1 greyscale PNG carrying an `eXIf` chunk. It has to
/// decode: the pending-upload preview renders it through `Image.file`.
Uint8List _geotaggedPng() {
  // zlib stream: one stored deflate block holding the single filtered
  // scanline `[filter 0, pixel 0]`, then its adler-32.
  const scanline = [0x00, 0x00];
  final idat = <int>[
    0x78, 0x01,
    0x01, 0x02, 0x00, 0xFD, 0xFF,
    ...scanline,
    0x00, 0x02, 0x00, 0x01,
  ];
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ..._pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 0, 0, 0, 0]),
    ..._pngChunk('eXIf', [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xDE, 0xAD]),
    ..._pngChunk('IDAT', idat),
    ..._pngChunk('IEND', const []),
  ]);
}

bool _hasChunk(Uint8List png, String type) {
  final want = type.codeUnits;
  for (var i = 8; i + 8 <= png.length; i++) {
    if (png[i] == want[0] &&
        png[i + 1] == want[1] &&
        png[i + 2] == want[2] &&
        png[i + 3] == want[3]) {
      return true;
    }
  }
  return false;
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // supabase_flutter opens an app_links deep-link stream on init. The upload
  // is driven under runAsync, so without a stub the real event loop turns and
  // the MissingPluginException lands as an unhandled error in this test.
  for (final name in const [
    'com.llfbandit.app_links/events',
    'com.llfbandit.app_links/messages',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            MethodChannel(name, const StandardMethodCodec()),
            (call) async => null);
  }
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

void main() {
  setUpAll(_ensureSupabase);

  testWidgets('a PNG photo uploads without its location metadata chunk',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('run-photos-exif');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/shot.png')
      ..writeAsBytesSync(_geotaggedPng());

    final api = _CapturingApi();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
              child: RunPhotos(
            api: api,
            runId: 'r1',
            runOwnerId: 'owner-1',
            pickImageOverride: () async => XFile(file.path),
          )),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add photo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();
    // The upload reads the picked file off disk, which is real I/O the fake
    // clock cannot advance.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await tester.pump();
    });
    await pumpUntil(tester, () => api.uploaded != null,
        describe: 'the stripped image to reach the upload api');
    await tester.pumpAndSettle();

    expect(api.uploadedContentType, 'image/png');
    expect(_hasChunk(api.uploaded!, 'eXIf'), isFalse,
        reason: 'the geotagged chunk must not leave the device');
    expect(_hasChunk(api.uploaded!, 'IDAT'), isTrue,
        reason: 'the image itself must survive the strip');
  });
}
