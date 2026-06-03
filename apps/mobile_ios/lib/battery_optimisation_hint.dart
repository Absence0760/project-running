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
/// a pure decision, surfaced once as a non-blocking, dismissible hint
/// before a long run (copy lives in the gen-l10n catalogue). The hint
/// never blocks the run.
library;

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
