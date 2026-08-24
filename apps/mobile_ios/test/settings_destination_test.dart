// The route/intent seam an embedded surface uses to open a Settings
// sub-screen it holds none of the dependencies for (decisions § 710).
//
// This file covers the intent half — parking, draining, and re-requesting.
// The host half (a parked destination becoming the right pushed screen) is
// pinned against a real shell in `home_screen_test.dart`, and the first
// consumer's affordance in `people_screen_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import '../lib/settings_destination.dart';

void main() {
  setUp(() => pendingSettingsDestination.value = null);
  tearDown(() => pendingSettingsDestination.value = null);

  test('openSettings parks the destination for the shell to drain', () {
    openSettings(SettingsDestination.preferences);
    expect(pendingSettingsDestination.value, SettingsDestination.preferences);
  });

  test('nothing is parked until a surface asks', () {
    expect(pendingSettingsDestination.value, isNull);
  });

  test('a request notifies listeners exactly once', () {
    final seen = <SettingsDestination?>[];
    void listener() => seen.add(pendingSettingsDestination.value);
    pendingSettingsDestination.addListener(listener);
    addTearDown(() => pendingSettingsDestination.removeListener(listener));

    openSettings(SettingsDestination.safety);
    expect(seen, [SettingsDestination.safety]);
  });

  test('the same destination can be requested again after a drain', () {
    final seen = <SettingsDestination?>[];
    void listener() => seen.add(pendingSettingsDestination.value);
    pendingSettingsDestination.addListener(listener);
    addTearDown(() => pendingSettingsDestination.removeListener(listener));

    openSettings(SettingsDestination.preferences);
    // The host clears the slot as it navigates — which is precisely what lets
    // a second identical request notify, since a ValueNotifier is silent on an
    // unchanged value.
    pendingSettingsDestination.value = null;
    openSettings(SettingsDestination.preferences);

    expect(seen, [
      SettingsDestination.preferences,
      null,
      SettingsDestination.preferences,
    ]);
  });

  test('a request made with no shell listening stays parked', () {
    // A surface can ask before the shell is up (or from a host that never
    // drains); the request waits rather than being dropped on the floor.
    openSettings(SettingsDestination.about);
    expect(pendingSettingsDestination.value, SettingsDestination.about);
  });

  test('a later request replaces an undrained one', () {
    openSettings(SettingsDestination.about);
    openSettings(SettingsDestination.pro);
    expect(pendingSettingsDestination.value, SettingsDestination.pro,
        reason: 'one slot — the newest intent is the one the runner meant');
  });
}
