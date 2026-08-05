import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/offline_sync_store.dart';
import '../lib/widgets/pending_sync_banner.dart';

class _TestEntry implements SyncEntry {
  @override
  final String id;
  @override
  final SyncState syncState;
  @override
  final DateTime lastModifiedAt;

  _TestEntry(this.id, this.syncState) : lastModifiedAt = DateTime.utc(2026);

  @override
  bool get isTombstone => syncState == SyncState.pendingDelete;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'sync_state': syncState.wire};
}

/// In-memory [OfflineSyncStore]: persistence is overridden away so the widget
/// tests run entirely inside the fake-async zone (no tester.runAsync needed).
class _TestStore extends OfflineSyncStore<_TestEntry> {
  bool failPushes = false;
  int pushes = 0;

  @override
  String get storeSubdir => 'pending_banner_test';

  @override
  String get debugLabel => 'pending_banner_test_store';

  @override
  Map<String, dynamic> summaryOf(_TestEntry entry) => entry.toJson();

  @override
  _TestEntry entryFromJson(Map<String, dynamic> json) => _TestEntry(
      json['id'] as String, syncStateFromWire(json['sync_state'] as String?));

  @override
  _TestEntry asSynced(_TestEntry entry) =>
      _TestEntry(entry.id, SyncState.synced);

  @override
  _TestEntry asPendingCreate(_TestEntry entry) =>
      _TestEntry(entry.id, SyncState.pendingCreate);

  Future<void> _push() async {
    pushes++;
    if (failPushes) throw StateError('server rejected');
  }

  @override
  Future<void> pushCreate(ApiClient api, _TestEntry entry) => _push();

  @override
  Future<void> pushUpdate(ApiClient api, _TestEntry entry) => _push();

  @override
  Future<void> pushDelete(ApiClient api, _TestEntry entry) => _push();

  @override
  Future<void> persist(_TestEntry stored) async {
    rowsById[stored.id] = stored;
    notifyListeners();
  }

  @override
  Future<void> dropRow(String id) async {
    rowsById.remove(id);
    notifyListeners();
  }

  void seed(String id, SyncState state) {
    rowsById[id] = _TestEntry(id, state);
    notifyListeners();
  }
}

class _SignedOutApi extends ApiClient {
  @override
  String? get userId => null;
}

class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'user-1';
}

Widget _app({
  required ApiClient? api,
  required bool isOnline,
  required List<OfflineSyncStore<SyncEntry>> stores,
  Locale? locale,
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PendingSyncBanner(api: api, isOnline: isOnline, stores: stores),
      ),
    );

void main() {
  test('pendingCount counts every non-synced state, hasPending mirrors it', () {
    final store = _TestStore();
    expect(store.pendingCount, 0);
    expect(store.hasPending, isFalse);
    store.rowsById['a'] = _TestEntry('a', SyncState.synced);
    store.rowsById['b'] = _TestEntry('b', SyncState.pendingCreate);
    store.rowsById['c'] = _TestEntry('c', SyncState.pendingUpdate);
    store.rowsById['d'] = _TestEntry('d', SyncState.pendingDelete);
    expect(store.pendingCount, 3);
    expect(store.hasPending, isTrue);
  });

  testWidgets('renders nothing when no rows are pending', (tester) async {
    final store = _TestStore()..rowsById['a'] = _TestEntry('a', SyncState.synced);
    await tester.pumpWidget(
        _app(api: _SignedInApi(), isOnline: true, stores: [store]));
    expect(find.byIcon(Icons.sync_problem), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('pending while offline shows the saved-on-device copy, no retry',
      (tester) async {
    final store = _TestStore()
      ..seed('a', SyncState.pendingCreate)
      ..seed('b', SyncState.pendingUpdate);
    await tester.pumpWidget(
        _app(api: _SignedInApi(), isOnline: false, stores: [store]));
    expect(
      find.text('2 changes saved on this device — will sync when online'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('pending while signed out shows the offline copy even if online',
      (tester) async {
    final store = _TestStore()..seed('a', SyncState.pendingCreate);
    await tester.pumpWidget(
        _app(api: _SignedOutApi(), isOnline: true, stores: [store]));
    expect(
      find.text('1 change saved on this device — will sync when online'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('pending while online shows the failed copy; retry drains and '
      'clears the banner', (tester) async {
    final store = _TestStore()..seed('a', SyncState.pendingCreate);
    await tester.pumpWidget(
        _app(api: _SignedInApi(), isOnline: true, stores: [store]));
    expect(find.text("1 change hasn't synced"), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(store.pushes, 1);
    expect(store.hasPending, isFalse);
    expect(find.text("1 change hasn't synced"), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('retry leaves the banner up when the server keeps rejecting',
      (tester) async {
    final store = _TestStore()
      ..failPushes = true
      ..seed('a', SyncState.pendingCreate);
    await tester.pumpWidget(
        _app(api: _SignedInApi(), isOnline: true, stores: [store]));

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(store.pushes, 1);
    expect(store.hasPending, isTrue);
    expect(find.text("1 change hasn't synced"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the retry action reflows below the message at 320dp in German',
      (tester) async {
    // A `TextButton` at the tail of the message row takes its intrinsic width
    // first, so a long German label starved the `Expanded` message down to a
    // few pixels and the banner grew several hundred pixels tall — enough to
    // overflow the host screen's body Column (decisions § 488).
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _TestStore()..seed('a', SyncState.pendingCreate);
    await tester.pumpWidget(_app(
      api: _SignedInApi(),
      isOnline: true,
      stores: [store],
      locale: const Locale('de'),
    ));
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(tester.getSize(find.byType(PendingSyncBanner)).height, lessThan(120));
  });

  testWidgets('sums pending rows across several stores and retries them all',
      (tester) async {
    final a = _TestStore()..seed('a', SyncState.pendingCreate);
    final b = _TestStore()..seed('b', SyncState.pendingDelete);
    await tester.pumpWidget(
        _app(api: _SignedInApi(), isOnline: true, stores: [a, b]));
    expect(find.text("2 changes haven't synced"), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(a.pushes, 1);
    expect(b.pushes, 1);
    expect(a.hasPending, isFalse);
    expect(b.hasPending, isFalse);
    expect(find.text('Retry'), findsNothing);
  });
}
