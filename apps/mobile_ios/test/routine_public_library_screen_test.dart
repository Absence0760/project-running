import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/screens/routine_public_library_screen.dart';

GymRoutineRow _routine(String id, String title) => GymRoutineRow(
      id: id,
      authorId: 'author-$id',
      title: title,
      periodisation: 'none',
      exerciseCount: 1,
      lastModifiedAt: DateTime.utc(2026, 5, 1),
      createdAt: DateTime.utc(2026, 5, 1),
      isPublicTemplate: true,
    );

class _LibraryApi extends ApiClient {
  _LibraryApi(this.entries);
  final List<({GymRoutineRow routine, String? authorHandle})> entries;

  @override
  Future<List<({GymRoutineRow routine, String? authorHandle})>>
      fetchPublicGymRoutineLibrary({String query = ''}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where((e) => e.routine.title.toLowerCase().contains(q))
        .toList();
  }
}

Future<({LocalRoutineStore store, LocalGymStore gym, Directory dir})> _fixture(
    String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_pub_lib_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: Directory('${dir.path}/routines'));
  final gym = LocalGymStore();
  await gym.init(overrideDirectory: Directory('${dir.path}/gym'));
  return (store: store, gym: gym, dir: dir);
}

Widget _app(ApiClient api, LocalRoutineStore store, LocalGymStore gym) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutinePublicLibraryScreen(api: api, store: store, gymStore: gym),
    );

void main() {
  testWidgets('lists public routines with author handle', (tester) async {
    final f = await _fixture('list');
    try {
      final api = _LibraryApi([
        (routine: _routine('r-1', 'Wendler 5/3/1'), authorHandle: 'Coach Sam'),
      ]);
      await tester.pumpWidget(_app(api, f.store, f.gym));
      await tester.pump();
      await tester.pump();
      expect(find.text('Wendler 5/3/1'), findsOneWidget);
      expect(find.text('by Coach Sam'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('empty library renders the empty state', (tester) async {
    final f = await _fixture('empty');
    try {
      await tester.pumpWidget(_app(_LibraryApi(const []), f.store, f.gym));
      await tester.pump();
      await tester.pump();
      expect(find.text('No published routines yet.'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
