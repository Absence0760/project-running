// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get prefsLanguage => 'Language';

  @override
  String get prefsLanguageSystem => 'System default';

  @override
  String get localeNameEn => 'English';

  @override
  String get localeNameDe => 'Deutsch';

  @override
  String get localeNameFr => 'Français';

  @override
  String get localeNameEs => 'Español';

  @override
  String get localeNameJa => '日本語';

  @override
  String get localeNamePtBR => 'Português (Brasil)';

  @override
  String get navHome => 'Home';

  @override
  String get navRun => 'Run';

  @override
  String get navHistory => 'History';

  @override
  String get navSocial => 'Social';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsSectionProfile => 'Profile';

  @override
  String get settingsSectionAppsData => 'Apps & data';

  @override
  String get settingsSectionAccountLegal => 'Account & legal';

  @override
  String get prefsSectionUnitsDisplay => 'Units & display';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authOrDivider => 'OR';

  @override
  String get signInTitle => 'Sign In';

  @override
  String get signInHeadline => 'Sync runs across devices';

  @override
  String get signInSubtitle =>
      'Sign in to back up runs and view them on the web app.';

  @override
  String get signInButton => 'Sign In';

  @override
  String get signInForgotPassword => 'Forgot password?';

  @override
  String get signInResetNeedEmail =>
      'Enter your email above first, then tap Forgot password.';

  @override
  String get signInResetSent =>
      'If that email is registered, we\'ve sent a reset link.';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInContinueOffline => 'Continue offline';

  @override
  String get signInCreateAccountPrompt => 'Don\'t have an account? Create one';

  @override
  String get signUpTitle => 'Create Account';

  @override
  String get signUpHeadline => 'Start tracking your runs';

  @override
  String get signUpSubtitle =>
      'Create an account to back up runs and view them on the web app.';

  @override
  String get signUpButton => 'Create Account';

  @override
  String get signUpConfirmAge => 'I am 16 years of age or older';

  @override
  String get signUpAcceptPrefix => 'I accept the ';

  @override
  String get signUpTermsLink => 'Terms of Service';

  @override
  String get signUpAcceptConjunction => ' and ';

  @override
  String get signUpPrivacyLink => 'Privacy Policy';

  @override
  String get signUpErrorConfirmAge =>
      'Please confirm you are 16 or older to continue.';

  @override
  String get signUpErrorAcceptTerms =>
      'Please accept the Terms of Service and Privacy Policy to continue.';

  @override
  String get signUpContinueWithApple => 'Continue with Apple';

  @override
  String get signUpContinueWithGoogle => 'Continue with Google';

  @override
  String get signUpSignInPrompt => 'Already have an account? Sign in';

  @override
  String signUpCouldNotOpen(String url) {
    return 'Could not open $url';
  }

  @override
  String get onboardingTrackTitle => 'Track every run';

  @override
  String get onboardingTrackBody =>
      'GPS recording with live map, splits, pace, cadence, and elevation. Works fully offline — sign in later to sync across devices.';

  @override
  String get onboardingRoutesTitle => 'Follow routes';

  @override
  String get onboardingRoutesBody =>
      'Import GPX or KML files, or sync routes from the web app. Get off-route alerts while you run.';

  @override
  String get onboardingLocationTitle => 'Location access';

  @override
  String get onboardingLocationBody =>
      'Threkir records your runs by sampling your GPS location while the app is in the foreground AND in the background (so it keeps tracking when your screen is off or you switch apps to take a photo). Location data is stored on your device and only uploaded to Threkir\'s servers when you choose to share or sync a run. If you decline background location, runs will stop recording the moment you switch away from the app — you can change this later in Settings → Apps → Threkir → Permissions.';

  @override
  String get onboardingPrivacyTitle => 'Who sees your runs?';

  @override
  String get onboardingPrivacyBody =>
      'Pick a default for new runs. You can change it any time in Settings, and override it on any single run.';

  @override
  String get onboardingGrantPermission => 'Grant permission';

  @override
  String get onboardingNext => 'Next';

  @override
  String get privacyPrivateTitle => 'Private';

  @override
  String get privacyPrivateSubtitle =>
      'Only you can see your runs. You can share any run later.';

  @override
  String get privacyFollowersTitle => 'Followers';

  @override
  String get privacyFollowersSubtitle =>
      'People who follow you see new runs in their feed.';

  @override
  String get privacyPublicTitle => 'Public';

  @override
  String get privacyPublicSubtitle => 'Anyone can find and view your runs.';

  @override
  String get runStart => 'START';

  @override
  String get runStartA11yLabel => 'Start run';

  @override
  String get runChooseRoute => 'Choose route';

  @override
  String get runChangeRoute => 'Change route';

  @override
  String get runShareLiveLink => 'Share live link';

  @override
  String get runTrainingPlans => 'Training plans';

  @override
  String get runTapToCancel => 'Tap to cancel';

  @override
  String get runFirstRunPrompt => 'Your first run is one tap away.';

  @override
  String get runLastActivity => 'Last activity';

  @override
  String get runLastRun => 'Last run';

  @override
  String get runFollowing => 'FOLLOWING';

  @override
  String get runRaceFallbackTitle => 'Race';

  @override
  String get runRaceArmed => 'Race armed';

  @override
  String get runRaceLive => 'Race LIVE';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — waiting for GO';
  }

  @override
  String runRaceElapsedTapStart(String label, String elapsed) {
    return '$label — $elapsed elapsed · tap Start';
  }

  @override
  String get runComplete => 'Run Complete';

  @override
  String get runStatDistance => 'Distance';

  @override
  String get runStatTime => 'Time';

  @override
  String get runStatMoving => 'Moving';

  @override
  String get runStatPace => 'Pace';

  @override
  String get runStatSpeed => 'Speed';

  @override
  String get runStatAvgPace => 'Avg Pace';

  @override
  String get runStatAvgSpeed => 'Avg Speed';

  @override
  String get runStatCalories => 'Calories';

  @override
  String get runStatElevation => 'Elevation';

  @override
  String get runStatSteps => 'Steps';

  @override
  String get runStatCadence => 'Cadence';

  @override
  String get runStatHeartRate => 'Heart Rate';

  @override
  String get runUnitKcal => 'kcal';

  @override
  String get runUnitMetres => 'm';

  @override
  String get runUnitSpm => 'spm';

  @override
  String get runUnitBpm => 'bpm';

  @override
  String get runMutePaceCues => 'Mute pace cues';

  @override
  String get runPaceCuesMuted => 'Pace cues muted';

  @override
  String get runSynced => 'Synced';

  @override
  String get runSyncing => 'Syncing...';

  @override
  String get runDone => 'Done';

  @override
  String get runDiscardA11yLabel => 'Discard run';

  @override
  String get runDiscardA11yHint =>
      'Throws away the current recording without saving';

  @override
  String get runResumeA11yLabel => 'Resume run';

  @override
  String get runPauseA11yLabel => 'Pause run';

  @override
  String get runResumeA11yHint => 'Resumes the paused recording';

  @override
  String get runPauseA11yHint => 'Pauses the recording without ending it';

  @override
  String get runMarkLapA11yLabel => 'Mark lap';

  @override
  String runMarkLapWithCountA11yLabel(int count) {
    return 'Mark lap, $count so far';
  }

  @override
  String get runMarkLapA11yHint => 'Records the current split';

  @override
  String get runCollapseStatsPanel => 'Collapse stats panel';

  @override
  String get runExpandStatsPanel => 'Expand stats panel';

  @override
  String runRouteRemaining(String distance) {
    return '$distance to go';
  }

  @override
  String runOffRoute(int metres) {
    return 'Off route — ${metres}m away';
  }

  @override
  String get runPermissionRevoked => 'Location permission revoked';

  @override
  String get runGpsLost => 'GPS signal lost — move to open sky';

  @override
  String get runWeakGps => 'Weak GPS — distance paused';

  @override
  String get runA11yStarted => 'Run started';

  @override
  String get runA11yResumed => 'Run resumed';

  @override
  String get runA11yPaused => 'Run paused';

  @override
  String get runA11yFinished => 'Run finished';

  @override
  String runLapMarked(int count) {
    return 'Lap $count marked';
  }

  @override
  String get runDiscardDialogTitle => 'Discard run?';

  @override
  String get runDiscardDialogBody => 'Your progress will be lost.';

  @override
  String get runKeepRunning => 'Keep running';

  @override
  String get runDiscard => 'Discard';

  @override
  String get runStartWorkout => 'Start workout';

  @override
  String get runStartWorkoutSubtitle =>
      'Run with live step targets, audio cues, and a planned-vs-actual review.';

  @override
  String get runViewWorkoutDetails => 'View details';

  @override
  String get runWorkoutNoStructure => 'This workout has no runnable structure.';

  @override
  String runWorkoutLoaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '$count step',
    );
    return 'Workout loaded · $_temp0 — tap GO to start';
  }

  @override
  String get runAbandonWorkoutTitle => 'Abandon workout?';

  @override
  String get runAbandonWorkoutBody =>
      'The structured plan stops here; the recorder keeps running as a free run. You can stop anytime to save what you did.';

  @override
  String get runCancel => 'Cancel';

  @override
  String get runAbandon => 'Abandon';

  @override
  String get runNoRoutesSaved =>
      'No routes saved. Import one from the Routes tab.';

  @override
  String get runNotificationsOffHint =>
      'Notifications are off — the live run notification won\'t show. Recording still works.';

  @override
  String get runSettings => 'Settings';

  @override
  String get runStartAnyway => 'Start anyway';

  @override
  String get runOpenSettings => 'Open settings';

  @override
  String get runNotNow => 'Not now';

  @override
  String get runShareSubject => 'Track me live';

  @override
  String runCouldNotShareLink(String error) {
    return 'Could not share live link: $error';
  }

  @override
  String get runHrStrapLostReconnecting =>
      'Heart-rate strap lost — reconnecting…';

  @override
  String get runHrStrapReconnected => 'Heart-rate strap reconnected';

  @override
  String get runHrStrapLostNoHr =>
      'Heart-rate strap lost — recording continues without HR.';

  @override
  String get runHrStrapNotFound =>
      'Heart-rate strap not found — put it on, then reconnect.';

  @override
  String get runReconnect => 'Reconnect';

  @override
  String get runHrStrapStillNotFound =>
      'Still no strap — recording continues without HR.';

  @override
  String get runSaveFailedRelaunch =>
      'Couldn\'t save locally. Relaunch the app to recover.';

  @override
  String get runSyncFailedSaveOffline => 'Saved offline. Sync from Runs.';

  @override
  String get runSavedOffline => 'Saved offline.';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings =>
      'No GPS — tracking will start when Location is on.';

  @override
  String get runGpsBlockedSettings =>
      'No GPS — permission is blocked. Enable it to track route.';

  @override
  String get runGpsPermissionPending =>
      'No GPS — tracking will start when permission is granted.';

  @override
  String get runGpsAllowAllTheTime =>
      'Set Location to \"Allow all the time\" — runs stop recording when you switch apps without background permission.';

  @override
  String get runGpsSensorFailed =>
      'Recording without GPS — could not start the sensor.';

  @override
  String get runAgoJustNow => 'Just now';

  @override
  String runAgoMinutes(int count) {
    return '$count min ago';
  }

  @override
  String runAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '$count hour ago',
    );
    return '$_temp0';
  }

  @override
  String get runAgoYesterday => 'Yesterday';

  @override
  String runAgoDays(int count) {
    return '$count days ago';
  }

  @override
  String runAgoWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks ago',
      one: '$count week ago',
    );
    return '$_temp0';
  }

  @override
  String runAgoMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months ago',
      one: '$count month ago',
    );
    return '$_temp0';
  }

  @override
  String get runWorkoutAbandonedBand => 'Workout abandoned · running freely';

  @override
  String get runWorkoutCompleteBand => 'Workout complete · tap stop to save';

  @override
  String runWorkoutStepHeader(String label, String target, String pace) {
    return '$label · $target @ $pace';
  }

  @override
  String runWorkoutStepCounter(int current, int total) {
    return '$current/$total';
  }

  @override
  String get runWorkoutRewind => 'Rewind';

  @override
  String get runWorkoutSkip => 'Skip';

  @override
  String get runWorkoutAbandon => 'Abandon';

  @override
  String runWorkoutRemainingYards(int yards) {
    return '$yards yd to go';
  }

  @override
  String runWorkoutRemainingMetres(int metres) {
    return '$metres m to go';
  }

  @override
  String runWorkoutRemainingDuration(String duration) {
    return '$duration to go';
  }

  @override
  String get runsRangeToday => 'Today';

  @override
  String get runsRangeWeek => 'This week';

  @override
  String get runsRangeMonth => 'Last 30 days';

  @override
  String get runsRangeYear => 'This year';

  @override
  String get runsRangeAll => 'All time';

  @override
  String get runsRangeCustom => 'Custom…';

  @override
  String runsRangeFrom(String date) {
    return 'From $date';
  }

  @override
  String runsRangeUntil(String date) {
    return 'Until $date';
  }

  @override
  String runsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return '$_temp0';
  }

  @override
  String get runsDateRangeTooltip => 'Date range';

  @override
  String get runsSortTooltip => 'Sort';

  @override
  String get runsSortNewest => 'Newest first';

  @override
  String get runsSortOldest => 'Oldest first';

  @override
  String get runsSortLongest => 'Longest distance';

  @override
  String get runsSortFastest => 'Best pace';

  @override
  String runsSyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sync $count runs',
      one: 'Sync $count run',
    );
    return '$_temp0';
  }

  @override
  String get runsRefreshTooltip => 'Refresh from cloud';

  @override
  String get runsOfflineTooltip => 'Offline';

  @override
  String runsSelectionTitle(int count) {
    return '$count selected';
  }

  @override
  String get runsSelectAllTooltip => 'Select all';

  @override
  String get runsClearSelectionTooltip => 'Clear';

  @override
  String get runsDeleteTooltip => 'Delete';

  @override
  String get runsCancelTooltip => 'Cancel';

  @override
  String get runsAddRun => 'Add run';

  @override
  String get runsAddRunTooltip => 'Add a run manually';

  @override
  String runsLoadMore(int count) {
    return 'Load $count more';
  }

  @override
  String get runsNoMatch => 'No runs match these filters';

  @override
  String get runsClearFilters => 'Clear filters';

  @override
  String get runsEmptyTitle => 'No runs yet';

  @override
  String get runsEmptyBody => 'Tap the Run tab to start your first run';

  @override
  String get runsFilterAll => 'All';

  @override
  String get runsSourceAll => 'All sources';

  @override
  String runsSourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String get runsSourceFilterTooltip => 'Filter by source';

  @override
  String get runsSourceRecorded => 'Recorded';

  @override
  String get runsSourceWatch => 'Watch';

  @override
  String get runsSourceStrava => 'Strava';

  @override
  String get runsSourceParkrun => 'parkrun';

  @override
  String get runsSourceHealthKit => 'HealthKit';

  @override
  String get runsSourceHealthConnect => 'Health Connect';

  @override
  String get runsRangePickerTitle => 'Select dates';

  @override
  String get runsRangeStart => 'Start';

  @override
  String get runsRangeEnd => 'End';

  @override
  String get runsRangeTapDate => 'Tap a date';

  @override
  String get runsRangeApply => 'Apply';

  @override
  String get runsRangeClear => 'Clear';

  @override
  String get runsPrevMonth => 'Previous month';

  @override
  String get runsNextMonth => 'Next month';

  @override
  String get runsPrevYear => 'Previous year';

  @override
  String get runsNextYear => 'Next year';

  @override
  String runsDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count runs?',
      one: 'Delete $count run?',
    );
    return '$_temp0';
  }

  @override
  String get runsDeleteConfirmBody => 'This cannot be undone.';

  @override
  String get runsCancel => 'Cancel';

  @override
  String get runsDelete => 'Delete';

  @override
  String get runsQueuedToSync => 'Queued to sync';

  @override
  String get runsSignInToSync => 'Sign in from Settings to sync runs';

  @override
  String get runsRefreshFailed => 'Could not refresh — check your connection';

  @override
  String get runsLoadMoreFailed => 'Could not load more runs';

  @override
  String runsSyncPartial(int synced, int total, String error) {
    return 'Synced $synced/$total. Error: $error';
  }

  @override
  String runsSyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count runs failed to upload their GPS track — the rest were synced. The failed runs will retry on the next cycle.',
      one:
          '$count run failed to upload its GPS track — the rest were synced. It will retry on the next cycle.',
    );
    return '$_temp0';
  }

  @override
  String runsSyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count runs synced',
      one: '$count run synced',
    );
    return '$_temp0';
  }

  @override
  String runsDeletePartial(int deleted, int queued) {
    return '$deleted deleted; $queued queued — will retry when back online.';
  }

  @override
  String runsDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count runs',
      one: 'Deleted $count run',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'Add run';

  @override
  String get addRunSave => 'Save';

  @override
  String get addRunSectionWhen => 'When';

  @override
  String get addRunSectionActivity => 'Activity';

  @override
  String get addRunSectionRoute => 'Route (optional)';

  @override
  String get addRunSectionDistance => 'Distance';

  @override
  String get addRunSectionDuration => 'Duration';

  @override
  String get addRunSectionTitle => 'Title (optional)';

  @override
  String get addRunSectionNotes => 'Notes (optional)';

  @override
  String get addRunClearRoute => 'Clear route';

  @override
  String get addRunSearchRoutes => 'Search saved routes';

  @override
  String get addRunNoRoutes =>
      'No saved routes yet — build or import one to attach it here';

  @override
  String get addRunDistanceInvalid => 'Enter a distance greater than 0';

  @override
  String get addRunDurationInvalid => 'Enter a duration';

  @override
  String get addRunTitleHint => 'e.g. Lunchtime loop';

  @override
  String get addRunNotesHint => 'How did it feel?';

  @override
  String get addRunSaveButton => 'Save run';

  @override
  String addRunSaveFailed(String error) {
    return 'Failed to save run: $error';
  }

  @override
  String get addRunSaved => 'Run added to history';

  @override
  String get addRunPickerSearchHint => 'Search routes';

  @override
  String get addRunPickerClear => 'Clear';

  @override
  String get addRunPickerCancel => 'Cancel';

  @override
  String addRunPickerNoMatch(String query) {
    return 'No routes match \"$query\"';
  }

  @override
  String get addRunPickerNoRoute => 'No route';

  @override
  String get runDetailDnfBadge => 'DNF';

  @override
  String get runDetailEditTooltip => 'Edit run';

  @override
  String get runDetailShareTooltip => 'Share run';

  @override
  String get runDetailMoreTooltip => 'More';

  @override
  String get runDetailSaveAsRoute => 'Save as route';

  @override
  String get runDetailDeleteRun => 'Delete run';

  @override
  String get runDetailEditTitle => 'Edit run';

  @override
  String get runDetailFieldTitle => 'Title';

  @override
  String get runDetailFieldNotes => 'Notes';

  @override
  String get runDetailFieldDistance => 'Distance';

  @override
  String get runDetailFieldDuration => 'Duration';

  @override
  String get runDetailMarkDnf => 'Mark as DNF';

  @override
  String get runDetailMarkDnfSubtitle =>
      'Excludes this run from personal records';

  @override
  String get runDetailEditInvalid => 'Enter a valid distance and duration';

  @override
  String get runDetailSave => 'Save';

  @override
  String get runDetailCancel => 'Cancel';

  @override
  String get runDetailDelete => 'Delete';

  @override
  String get runDetailLoadingGps => 'Loading GPS data...';

  @override
  String get runDetailGpsUnavailable => 'GPS track unavailable offline';

  @override
  String get runDetailPauseReplay => 'Pause replay';

  @override
  String get runDetailReplay => 'Replay this run';

  @override
  String get runDetailStatElevGain => 'Elev Gain';

  @override
  String get runDetailStatElevLoss => 'Elev Loss';

  @override
  String get runDetailStatAvgHr => 'Avg HR';

  @override
  String get runDetailStatAgeGrade => 'Age grade';

  @override
  String get runDetailSectionElevation => 'Elevation';

  @override
  String get runDetailSectionLaps => 'Laps';

  @override
  String runDetailLapNumber(int number) {
    return 'Lap $number';
  }

  @override
  String get runDetailSectionRunningDynamics => 'Running Dynamics';

  @override
  String get runDetailDynVerticalOsc => 'Vertical oscillation';

  @override
  String get runDetailDynGroundContact => 'Ground contact';

  @override
  String get runDetailDynStrideLength => 'Stride length';

  @override
  String get runDetailDynAvgPower => 'Avg power';

  @override
  String get runDetailSectionRouteHistory => 'Route History';

  @override
  String get runDetailThisRoute => 'this route';

  @override
  String runDetailPersonalBest(String route) {
    return 'Personal best on $route';
  }

  @override
  String runDetailBehindPb(String delta) {
    return '$delta behind PB';
  }

  @override
  String runDetailAttemptOf(int rank, int total, String pb) {
    return 'Attempt $rank of $total  —  PB: $pb';
  }

  @override
  String get runDetailSectionBestEfforts => 'Best Efforts';

  @override
  String get runDetailSectionHeartRateZones => 'Heart rate zones';

  @override
  String get runDetailHrAvg => 'Avg';

  @override
  String get runDetailHrMin => 'Min';

  @override
  String get runDetailHrMax => 'Max';

  @override
  String runDetailZoneRow(int number, String label) {
    return 'Zone $number · $label';
  }

  @override
  String get runDetailSectionSplits => 'Splits';

  @override
  String get runDetailNoGpsForSplits => 'No GPS data for splits';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Run too short for a full $unit split';
  }

  @override
  String get runDetailSectionSegments => 'Segments';

  @override
  String get runDetailSaveAsRouteTitle => 'Save as route';

  @override
  String get runDetailSaveAsRouteBody =>
      'Save this GPS trace as a route you can follow again.';

  @override
  String get runDetailRouteNameLabel => 'Route name';

  @override
  String get runDetailNoTrackToSave =>
      'This run has no GPS track to save as a route';

  @override
  String runDetailRouteLinked(String route) {
    return 'Linked to $route';
  }

  @override
  String get runDetailRouteLinkFailed => 'Could not link route';

  @override
  String get runDetailReSnapping => 'Re-snapping to roads…';

  @override
  String runDetailRematchFailed(String error) {
    return 'Re-match failed: $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return 'Saved \"$name\" — $kept waypoints ($smoothed smoothed out)';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'Could not make run public: $error';
  }

  @override
  String get runDetailMakePublicTitle => 'Make this run public?';

  @override
  String get runDetailMakePublicBodyZone =>
      'Sharing flips this run to public so anyone with the link can view it. This run starts or ends inside one of your privacy zones, so viewers will see a clipped track with the in-zone segments hidden.';

  @override
  String get runDetailMakePublicBodyHasZones =>
      'Sharing flips this run to public so anyone with the link can view it. None of your privacy zones intersect this track, so the full track will be visible.';

  @override
  String get runDetailMakePublicBodyNoZones =>
      'Sharing flips this run to public so anyone with the link can view it — including the start and end points of your run. You have no privacy zones set up. Consider adding one around your home before sharing.';

  @override
  String get runDetailMakePublic => 'Make public';

  @override
  String get runDetailDeleteTitle => 'Delete run?';

  @override
  String get runDetailDeleteBody => 'This cannot be undone.';

  @override
  String get runDetailSuggestLink => 'Link';

  @override
  String get runDetailSuggestDismiss => 'Dismiss';

  @override
  String get runDetailSuggestRanRoute => 'Looks like you ran ';

  @override
  String get runDetailSuggestLinkPrompt => 'Link this run to that route?';

  @override
  String get runDetailMatchPending => 'Snapping to roads…';

  @override
  String get runDetailMatchSkipped => 'Not snapped (too few points)';

  @override
  String get runDetailMatchFailed => 'Snap failed — showing raw track';

  @override
  String get runDetailMatchMatched => 'Snapped';

  @override
  String get runDetailRematchQueueing => 'Queueing…';

  @override
  String get runDetailRematch => 'Re-match';

  @override
  String get runDetailSegStatDistance => 'Distance';

  @override
  String get runDetailSegStatTime => 'Time';

  @override
  String get runDetailSegStatPace => 'Pace';

  @override
  String get runDetailSegStatHr => 'HR';

  @override
  String get runDetailSegStatGain => 'Gain';

  @override
  String get runDetailSegDismiss => 'Dismiss';

  @override
  String get publicRunTitle => 'Run';

  @override
  String get publicRunLoadError => 'Could not load this run.';

  @override
  String get publicRunUnavailable =>
      'This run is private or no longer available.';

  @override
  String get publicRunAuthorFallback => 'Runner';

  @override
  String get publicRunStatDistance => 'Distance';

  @override
  String get publicRunStatTime => 'Time';

  @override
  String get publicRunStatPace => 'Pace';

  @override
  String get publicRunSectionSegments => 'Segments';
}
