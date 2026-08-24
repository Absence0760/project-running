import 'package:flutter/foundation.dart';

/// A Settings sub-screen named as an INTENT rather than as a widget.
///
/// Every settings screen takes some slice of `Preferences` +
/// `SettingsSyncService` + `ApiClient` + the BLE handles, and a surface
/// embedded several layers inside a nav destination holds none of them — the
/// People tab's nearby list sits inside `SocialScreen`, which was handed a
/// social service and a route store and nothing else. Naming the destination
/// instead of constructing it lets such a surface link into Settings without
/// its host acquiring the whole settings dependency set on the way past
/// (decisions § 710).
///
/// Deliberately only the PUSHABLE sub-screens. The Settings landing itself is
/// not a destination here: it is embedded in the You tab rather than pushed,
/// so "open Settings" is a tab switch with different back-stack semantics,
/// and no caller has asked for it.
enum SettingsDestination {
  preferences,
  account,
  safety,
  integrations,
  bodyMetrics,
  about,
  pro,
}

/// Cross-screen handoff for "open this Settings sub-screen".
///
/// The same shape as `pendingPushTarget` / `pendingStartRunWithRoute` in
/// `main.dart`: the requester parks an intent, [HomeScreen] drains it and does
/// the navigation with the dependencies it already holds. A notifier rather
/// than a callback threaded down every embed path — every surface that could
/// want Settings is mounted under the one shell.
///
/// Lives here rather than in `main.dart` so a leaf surface can depend on the
/// seam without importing the app's entrypoint, mirroring
/// `shared_file_import.dart`'s `incomingRouteImport`.
final ValueNotifier<SettingsDestination?> pendingSettingsDestination =
    ValueNotifier<SettingsDestination?>(null);

/// Ask the shell to open [destination]. Safe to call from any surface at any
/// depth, and from a surface with no navigator of its own.
///
/// Parks the request rather than performing it, so a request made before the
/// shell can act on it is honoured on its next drain rather than lost. The
/// host clears the slot as it navigates, which is also what lets the same
/// destination be requested twice in a row.
void openSettings(SettingsDestination destination) {
  pendingSettingsDestination.value = destination;
}
