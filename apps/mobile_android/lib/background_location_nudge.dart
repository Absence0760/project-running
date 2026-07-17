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

/// True when we should nudge the runner to upgrade to background
/// location. Only on Android, only when foreground access is already
/// granted (no point nudging before they've granted anything) but the
/// always-on permission is still missing, and only if the runner hasn't
/// already dismissed the nudge — denying "all the time" is a deliberate,
/// informed choice, so one dismissal silences it (issue #266; the same
/// persisted-flag gate the sibling battery-optimisation hint uses).
bool shouldNudgeBackgroundLocation({
  required bool isAndroid,
  required bool foregroundGranted,
  required bool alwaysGranted,
  required bool alreadyDismissed,
}) {
  return isAndroid && foregroundGranted && !alwaysGranted && !alreadyDismissed;
}

/// True when a stored dismissal should be cleared. Once the always-on
/// permission is observed granted, the dismissal has served its purpose —
/// clearing it re-arms the nudge so a later revocation (manual, or the OS
/// auto-resetting unused permissions) surfaces it again: that regression
/// silently breaks screen-off recording, which is new information the
/// original dismissal never covered.
bool shouldRearmBackgroundLocationNudge({
  required bool alwaysGranted,
  required bool alreadyDismissed,
}) {
  return alwaysGranted && alreadyDismissed;
}
