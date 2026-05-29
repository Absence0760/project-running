/// Pure decision for the pre-run background-location nudge (Android
/// onboarding persona #57).
///
/// On Android 11+ the initial location dialog only grants "while in
/// use" — `ACCESS_BACKGROUND_LOCATION` ("Allow all the time") is a
/// separate trip the OS routes through app settings. A run recorded
/// with the screen off then loses fixes until the user discovers and
/// fixes it. So before a run starts, if foreground location is granted
/// but background isn't, we surface a one-tap deep-link to app settings.
///
/// iOS has its own provisional "Always" escalation and isn't the gap
/// this addresses, so the nudge is Android-only.
library;

const String kBackgroundLocationNudgeTitle = 'Allow location all the time';

const String kBackgroundLocationNudgeBody =
    'Android only granted location while the app is open. For accurate '
    'distance when your screen is off, set location access to "Allow all '
    'the time" in Settings. You can start anyway — recording still works '
    'while the app is on screen.';

/// True when we should nudge the runner to upgrade to background
/// location. Only on Android, only when foreground access is already
/// granted (no point nudging before they've granted anything) but the
/// always-on permission is still missing.
bool shouldNudgeBackgroundLocation({
  required bool isAndroid,
  required bool foregroundGranted,
  required bool alwaysGranted,
}) {
  return isAndroid && foregroundGranted && !alwaysGranted;
}
