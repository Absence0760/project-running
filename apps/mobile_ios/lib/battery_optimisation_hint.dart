/// One-time OEM battery-optimisation disclosure (Android-first persona
/// round-5).
///
/// Many Android OEMs run an aggressive app-killer on top of stock Doze
/// (Samsung "Put app to sleep" / Stamina, Xiaomi MIUI, OnePlus, Huawei,
/// Oppo). Unless the app is exempted from battery optimisation, the OEM
/// freezes the recording foreground service mid-run with no warning — the
/// runner finishes a long effort to find the last hour missing. Stock
/// `ACCESS_BACKGROUND_LOCATION` (the persona #57 nudge) does not cover this;
/// the OEM kill is a separate setting the user has to relax per-app, the
/// pattern catalogued at dontkillmyapp.com.
///
/// This is the iOS-excluded sibling of `background_location_nudge.dart`:
/// the show-once decision plus the settings deep-link, surfaced as a
/// non-blocking, dismissible hint before a long run (copy lives in the
/// gen-l10n catalogue). The hint never blocks the run.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// True when we should surface the one-time battery-optimisation hint. Only
/// on Android (iOS does not have OEM app-killers), only when it hasn't been
/// shown before. Gating on a longer planned/likely effort is the caller's
/// job — the helper just enforces the Android-only + once contract.
bool shouldShowBatteryOptHint({
  required bool isAndroid,
  required bool alreadyShown,
}) {
  return isAndroid && !alreadyShown;
}

@visibleForTesting
const MethodChannel batterySettingsChannel =
    MethodChannel('run_app/battery_settings');

/// Deep-links to the Android battery-optimisation settings
/// (ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS — the screen the dialog copy
/// actually describes; the generic App Info page buries the exemption two
/// taps deep and OEM skins hide it entirely). Falls back to
/// [openAppSettingsFallback] when the intent can't resolve, off Android, or
/// the channel is missing. Never throws — this runs on the run-start path.
Future<void> openBatteryOptimisationExemption({
  required bool isAndroid,
  required Future<void> Function() openAppSettingsFallback,
}) async {
  if (isAndroid) {
    try {
      final opened = await batterySettingsChannel
          .invokeMethod<bool>('openBatteryOptimisationSettings');
      if (opened == true) return;
    } catch (e) {
      debugPrint('battery optimisation settings intent failed: $e');
    }
  }
  try {
    await openAppSettingsFallback();
  } catch (e) {
    debugPrint('openAppSettings (battery opt) failed: $e');
  }
}
