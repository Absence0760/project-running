// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get clubInviteEnterCodeError =>
      'Enter the invite code from your link.';

  @override
  String get clubInviteJoinedBanner => 'You\'ve joined the club.';

  @override
  String get clubInviteTitle => 'Join club';

  @override
  String get clubInviteIntro =>
      'Paste the invite code your club admin shared with you.';

  @override
  String get clubInviteCodeLabel => 'Invite code';

  @override
  String get clubInviteJoinButton => 'Join';

  @override
  String recapShareHeadline(Object year) {
    return 'My $year in running:';
  }

  @override
  String recapShareTotals(Object total, Object count) {
    return '$total across $count runs';
  }

  @override
  String recapShareLongestRun(Object distance) {
    return 'Longest run: $distance';
  }

  @override
  String recapShareBestStreak(Object days) {
    return 'Best streak: $days days';
  }

  @override
  String recapShareSubject(Object year) {
    return '$year recap';
  }

  @override
  String get recapTitle => 'Year in running';

  @override
  String get recapShareTooltip => 'Share recap';

  @override
  String get recapPublishAndShare => 'Publish & share link';

  @override
  String get recapPublishFailed => 'Couldn\'t publish the recap. Try again.';

  @override
  String get recapPrevYear => 'Previous year';

  @override
  String get recapNextYear => 'Next year';

  @override
  String recapNoRunsForYear(Object year) {
    return 'No runs to recap for $year.';
  }

  @override
  String recapNoRunsYet(Object year) {
    return 'No runs in $year yet. Log one to see your recap.';
  }

  @override
  String recapAcrossRuns(Object count, Object runWord) {
    return 'across $count $runWord';
  }

  @override
  String get recapLongestRunLabel => 'Longest run';

  @override
  String get recapBestStreakLabel => 'Best streak';

  @override
  String recapStreakDays(Object days, Object dayWord) {
    return '$days $dayWord';
  }

  @override
  String get recapTopWeekLabel => 'Top week';

  @override
  String get recapUniqueRoutesLabel => 'Unique routes';

  @override
  String get recapEarliestStartLabel => 'Earliest start';

  @override
  String get recapLatestStartLabel => 'Latest start';

  @override
  String get routePickerTitle => 'Choose route';

  @override
  String get routePickerNoRoute => 'No route';

  @override
  String get routePickerClearSearchTooltip => 'Clear search';

  @override
  String get routePickerSearchHint => 'Search routes by name…';

  @override
  String get routePickerEmptyNoRoutes => 'No routes saved yet';

  @override
  String routePickerEmptyNoMatch(Object query) {
    return 'No routes match \"$query\"';
  }

  @override
  String get routePickerStarredHeader => 'Starred';

  @override
  String get routePickerAllRoutesHeader => 'All routes';

  @override
  String importStatusImported(Object count, Object label) {
    return 'Imported $count runs from $label';
  }

  @override
  String importStatusImportedWithErrors(Object count, Object errors) {
    return 'Imported $count runs ($errors failed)';
  }

  @override
  String importStatusNoGpsNote(Object base, Object label) {
    return '$base. $label has no route data, so these runs have no map.';
  }

  @override
  String importHealthRequestingPermission(Object label) {
    return 'Requesting $label permission...';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return '$label permission denied';
  }

  @override
  String get importHealthReadingWorkouts => 'Reading workouts...';

  @override
  String importHealthFailed(Object label, Object error) {
    return '$label import failed: $error';
  }

  @override
  String get importStatusSavingLocally => 'Saving locally...';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return 'Skipped $count duplicate(s) already imported from another source';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return 'Saved $done of $total locally';
  }

  @override
  String get importStatusSyncingToCloud => 'Syncing to cloud...';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return 'Synced $done of $total';
  }

  @override
  String get importStatusReadingCsv => 'Reading CSV...';

  @override
  String importCsvFailed(Object error) {
    return 'CSV import failed: $error';
  }

  @override
  String get importStatusRestoringBackup => 'Restoring backup...';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return 'Restored $runs runs · $tracks tracks · $routes routes';
  }

  @override
  String importBackupFailed(Object error) {
    return 'Backup restore failed: $error';
  }

  @override
  String get importStatusReadingExport => 'Reading export...';

  @override
  String importStravaFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get importTitle => 'Import runs';

  @override
  String get importStravaCardTitle => 'Strava';

  @override
  String get importStravaCardSubtitle =>
      'Import every run from a Strava data export ZIP';

  @override
  String get importStravaHowToHeader => 'How to get your Strava export:';

  @override
  String get importStravaHowToSteps =>
      '1. Open Strava → Settings → My Account\n2. Scroll to \"Download or Delete Your Account\"\n3. Tap \"Get Started\" → \"Request your archive\"\n4. You\'ll get an email with a download link in a few hours\n5. Download the .zip and tap Import below';

  @override
  String get importStravaButton => 'Import Strava ZIP';

  @override
  String importHealthButton(Object label) {
    return 'Import from $label';
  }

  @override
  String get importCsvCardTitle => 'CSV';

  @override
  String get importCsvCardSubtitle =>
      'Re-import a CSV exported from Settings — runs only, no GPS';

  @override
  String get importCsvCardDescription =>
      'Each CSV row becomes a manual run (date, distance, duration, source). The map trace is not in the CSV, so imported runs won\'t have a route line.';

  @override
  String get importCsvButton => 'Import CSV';

  @override
  String get importBackupCardTitle => 'Full backup ZIP';

  @override
  String get importBackupCardSubtitle =>
      'Restore runs, routes, and GPS traces from a backup file';

  @override
  String get importBackupCardDescription =>
      'Loss-less round-trip. Works without signing in — restored runs sync to your account the next time you do. Make a backup from Settings → Full backup.';

  @override
  String get importBackupButton => 'Restore backup ZIP';

  @override
  String get importErrorsHeader => 'Errors';

  @override
  String importErrorsMore(Object count) {
    return '... and $count more';
  }

  @override
  String get importHealthSubtitleIos =>
      'Pull workouts you\'ve recorded on Apple Watch, Nike Run Club, Strava, and other apps that write to Apple Health';

  @override
  String get importHealthSubtitleAndroid =>
      'Pull workouts from Google Fit, Samsung Health, Garmin, Fitbit, and any other Health Connect app';

  @override
  String get importHealthDescriptionIos =>
      'Reads workout summaries (date, distance, duration, type) from the last year. Apple Health doesn\'t expose GPS routes recorded by third-party apps — runs imported this way won\'t have a map trace.';

  @override
  String get importHealthDescriptionAndroid =>
      'Reads workout summaries (date, distance, duration, type) from the last year. GPS routes are not exposed by Health Connect — runs imported this way won\'t have a map trace.';

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'Could not update follow: $error';
  }

  @override
  String get peopleSearchHint => 'Search runners by name';

  @override
  String get peopleClearSearchTooltip => 'Clear search';

  @override
  String get commonClearSearch => 'Clear search';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get settingsDevicesRemoveOverride => 'Remove override';

  @override
  String get peopleSearchResultsHeader => 'Search results';

  @override
  String get peopleSuggestedHeader => 'Suggested for you';

  @override
  String peopleEmptySearchTitle(Object query) {
    return 'No runners match \"$query\"';
  }

  @override
  String get peopleEmptySearchBody =>
      'Try a shorter or different name. Display names are public; people who haven\'t set one yet won\'t show up here.';

  @override
  String get peopleEmptySuggestionsTitle => 'No suggestions yet';

  @override
  String get peopleEmptySuggestionsBody =>
      'Suggestions come from people in clubs you\'ve joined. Join a club to start seeing them here.';

  @override
  String peoplePublicRunCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count public runs',
      one: '1 public run',
    );
    return '$_temp0';
  }

  @override
  String peopleSharedClubsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clubs together',
      one: '1 club together',
    );
    return '$_temp0';
  }

  @override
  String get peopleFallbackDisplayName => 'Runner';

  @override
  String get peopleFollowingButton => 'Following';

  @override
  String get peopleFollowButton => 'Follow';

  @override
  String get readinessCardHeader => 'READINESS';

  @override
  String get readinessBandHigh => 'high';

  @override
  String get readinessBandModerate => 'moderate';

  @override
  String get readinessBandLow => 'low';

  @override
  String get missingMapTilesTitle => 'Using OpenStreetMap fallback tiles';

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
  String get navLog => 'Log';

  @override
  String get logA11yLabel => 'Log an activity';

  @override
  String get navFitness => 'Fitness';

  @override
  String get navYou => 'You';

  @override
  String get fitnessTabAll => 'All';

  @override
  String get fitnessTabRuns => 'Runs';

  @override
  String get fitnessTabGym => 'Gym';

  @override
  String get fitnessTabNutrition => 'Nutrition';

  @override
  String get fitnessRunsRoutes => 'Routes';

  @override
  String get fitnessRunsPlans => 'Training plans';

  @override
  String get homeAskCoach => 'Ask your coach';

  @override
  String get homeAskCoachSubtitle =>
      'Advice across your runs, lifts, and nutrition';

  @override
  String get youProfileTitle => 'Your profile';

  @override
  String get logSheetTitle => 'Log';

  @override
  String get logRun => 'Log run';

  @override
  String get logLift => 'Log lift';

  @override
  String get logFood => 'Log food';

  @override
  String get prefsKeepRunPrimary => 'Run as primary action';

  @override
  String get prefsKeepRunPrimarySubtitle =>
      'Tap the centre button to start a run; long-press for the full log menu';

  @override
  String get bodyMetricsTitle => 'Body metrics';

  @override
  String get bodyMetricsTileSubtitle => 'Height, weight & nutrition targets';

  @override
  String get bodyMetricsConsentTitle => 'Store health data';

  @override
  String get bodyMetricsConsentSubtitle =>
      'Height and weight are special-category health data. Turn this off to erase them.';

  @override
  String get bodyMetricsHeight => 'Height';

  @override
  String get bodyMetricsWeight => 'Weight';

  @override
  String get bodyMetricsActivityLevel => 'Activity level';

  @override
  String get bodyMetricsGoal => 'Goal';

  @override
  String get bodyMetricsTargetsHint =>
      'Used to estimate your daily calorie and macro targets.';

  @override
  String get bodyMetricsConsentRequired =>
      'Turn on health-data storage to save height and weight.';

  @override
  String get bodyMetricsWithdrawTitle => 'Withdraw health-data consent?';

  @override
  String get bodyMetricsWithdrawBody =>
      'This permanently erases your saved height and your entire weight history. This can\'t be undone.';

  @override
  String get bodyMetricsWithdrawConfirm => 'Withdraw & erase';

  @override
  String get bodyMetricsSaved => 'Saved';

  @override
  String bodyMetricsSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String bodyMetricsPrefSaveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String get safetyTitle => 'Safety contacts';

  @override
  String get safetyTileSubtitle =>
      'Email a trusted contact when you finish a run';

  @override
  String get safetyIntro =>
      'A safety contact is emailed when you finish a run — even a private one — so someone you trust knows you got back safely.';

  @override
  String get safetyAddLabel => 'Contact email';

  @override
  String get safetyAddButton => 'Add contact';

  @override
  String get safetyAdding => 'Adding…';

  @override
  String get safetyEmpty => 'No safety contacts yet.';

  @override
  String get safetyStatusPending => 'Pending — waiting for them to confirm';

  @override
  String get safetyStatusConfirmed => 'Confirmed';

  @override
  String get safetyRemove => 'Remove';

  @override
  String get safetyRemoveConfirm => 'Remove this safety contact?';

  @override
  String safetyAddFailed(String error) {
    return 'Could not add contact: $error';
  }

  @override
  String get safetyInvalidEmail => 'Enter a valid email address.';

  @override
  String get safetyAddedToast => 'Contact added — we emailed them to confirm.';

  @override
  String get safetyRemovedToast => 'Contact removed.';

  @override
  String get safetyIncomingTitle => 'Requests for you';

  @override
  String get safetyIncomingIntro =>
      'These people asked you to be their safety contact. Confirm to get an email when they finish a run.';

  @override
  String safetyIncomingFrom(String name) {
    return 'From $name';
  }

  @override
  String get safetyConfirm => 'Confirm';

  @override
  String get safetyDecline => 'Decline';

  @override
  String get safetyConfirmedToast => 'You\'re now a safety contact.';

  @override
  String get safetyDeclinedToast => 'Request declined.';

  @override
  String get safetyUnknownRunner => 'A Threkir runner';

  @override
  String get safetyOverdueTitle => 'Overdue alert';

  @override
  String get safetyOverdueIntro =>
      'If a live-shared run goes quiet for longer than this, your confirmed contacts get one email with your live link.';

  @override
  String get safetyOverdueLabel => 'Alert after silence of';

  @override
  String get safetyOverdueOff => 'Off';

  @override
  String safetyOverdueMinutesOption(int minutes) {
    return '$minutes min';
  }

  @override
  String get safetyOverdueNote =>
      'Applies to any run with live sharing on. Silence can also mean loss of phone signal — the email says so. Contacts are alerted once per run; finishing sends the usual all-clear.';

  @override
  String get safetyOverdueSaved => 'Overdue alert updated';

  @override
  String get safetyAutoLiveShareTitle => 'Auto live share';

  @override
  String get safetyAutoLiveShareSubtitle =>
      'Start a live share automatically when a run starts on this phone. The in-progress run is viewable by anyone with the link.';

  @override
  String get runAutoLiveShareStarted =>
      'Live sharing is on — use Share live link to send it';

  @override
  String get activitySedentary => 'Mostly sitting (desk job)';

  @override
  String get activityLight => 'Lightly active (light daily movement)';

  @override
  String get activityModerate => 'Moderately active (on your feet often)';

  @override
  String get activityVeryActive => 'Very active day (physical job)';

  @override
  String get activityExtraActive => 'Extremely active (hard physical labour)';

  @override
  String get goalLose => 'Lose weight';

  @override
  String get goalMaintain => 'Maintain weight';

  @override
  String get goalGain => 'Gain weight';

  @override
  String get homeTodaysLift => 'Today\'s lift';

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
  String get setupPageTitle => 'Set up your account';

  @override
  String get setupSkip => 'Skip setup';

  @override
  String get setupSkipStep => 'Skip';

  @override
  String get setupBack => 'Back';

  @override
  String get setupContinue => 'Continue';

  @override
  String get setupSaving => 'Saving…';

  @override
  String get setupOpenDashboard => 'Open dashboard';

  @override
  String get setupWelcomeToast => 'Welcome to Threkir!';

  @override
  String setupSaveError(String message) {
    return 'Couldn\'t save your setup: $message';
  }

  @override
  String get setupNameTitle => 'What should we call you?';

  @override
  String get setupNameHint =>
      'This is the name other runners see on your profile and shared runs.';

  @override
  String get setupNameLabel => 'Display name';

  @override
  String get setupNamePlaceholder => 'e.g. Alex Runner';

  @override
  String get setupUnitsTitle => 'Kilometres or miles?';

  @override
  String get setupUnitsHint =>
      'We\'ll use this everywhere distances and paces are shown. You can change it any time in Settings.';

  @override
  String get setupUnitKm => 'Kilometres';

  @override
  String get setupUnitKmSample => '5.0 km · 5:00 /km';

  @override
  String get setupUnitMi => 'Miles';

  @override
  String get setupUnitMiSample => '3.1 mi · 8:03 /mi';

  @override
  String get setupGoalTitle => 'What\'s your main goal?';

  @override
  String get setupGoalHint =>
      'We\'ll use this to suggest a training plan that fits. Optional — you can skip it.';

  @override
  String get setupGoalGeneralFitness => 'Stay fit + healthy';

  @override
  String get setupGoalWeightLoss => 'Lose weight';

  @override
  String get setupGoal5k => 'Run a 5K';

  @override
  String get setupGoal10k => 'Run a 10K';

  @override
  String get setupGoalHalf => 'Run a half marathon';

  @override
  String get setupGoalMarathon => 'Run a marathon';

  @override
  String get setupAboutTitle => 'A bit about you';

  @override
  String get setupAboutHint =>
      'Optional. Helps tailor pace and calorie estimates. You choose whether to share health data.';

  @override
  String get setupGenderLabel => 'Gender';

  @override
  String get setupGenderPreferNot => 'Prefer not to say';

  @override
  String get setupGenderFemale => 'Female';

  @override
  String get setupGenderMale => 'Male';

  @override
  String get setupGenderNonbinary => 'Non-binary';

  @override
  String get setupDobLabel => 'Date of birth';

  @override
  String get setupDobNote =>
      'Used to keep accounts of under-18s out of people search, and for age-graded results if you share health data.';

  @override
  String get setupDobPlaceholder => 'Tap to choose';

  @override
  String get setupWeightLabel => 'Weight (kg)';

  @override
  String get setupWeightPlaceholder => 'e.g. 70';

  @override
  String get setupHealthConsent =>
      'I consent to Threkir using my gender and date of birth to personalise pace, heart-rate and calorie estimates (special-category health data, GDPR Art 9).';

  @override
  String get setupPrivacyTitle => 'Who sees your runs?';

  @override
  String get setupPrivacyHint =>
      'Choose a default for new runs. You can change it any time and override it on any single run.';

  @override
  String get setupNotificationsTitle => 'Stay in the loop';

  @override
  String get setupNotificationsHint =>
      'Choose how many push notifications you\'d like. You can fine-tune this later in Settings.';

  @override
  String get setupDoneTitle => 'You\'re all set';

  @override
  String get setupDoneHint =>
      'That\'s everything. Tap Open dashboard to start running.';

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
  String get runStopA11yLabel => 'Stop and save run';

  @override
  String get runStopA11yHint => 'Ends the recording and saves the run';

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
  String get runTreadmillModeLabel => 'Treadmill mode';

  @override
  String runTreadmillModeSpeed(String speed) {
    return 'Belt $speed';
  }

  @override
  String get runTreadmillLostReconnecting => 'Treadmill lost, reconnecting…';

  @override
  String get runTreadmillReconnected => 'Treadmill reconnected';

  @override
  String get runTreadmillLostFallback =>
      'Treadmill lost — distance falling back to GPS';

  @override
  String get runTreadmillNotFound => 'Couldn\'t reach the treadmill';

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
  String get historyRangeToday => 'Today';

  @override
  String get historyRangeWeek => 'This week';

  @override
  String get historyRangeMonth => 'Last 30 days';

  @override
  String get historyRangeYear => 'This year';

  @override
  String get historyRangeAll => 'All time';

  @override
  String get historyRangeCustom => 'Custom…';

  @override
  String historyRangeFrom(String date) {
    return 'From $date';
  }

  @override
  String historyRangeUntil(String date) {
    return 'Until $date';
  }

  @override
  String historyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return '$_temp0';
  }

  @override
  String get historyDateRangeTooltip => 'Date range';

  @override
  String get historySortTooltip => 'Sort';

  @override
  String get historySortNewest => 'Newest first';

  @override
  String get historySortOldest => 'Oldest first';

  @override
  String get historySortLongest => 'Longest distance';

  @override
  String get historySortFastest => 'Best pace';

  @override
  String historySyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sync $count runs',
      one: 'Sync $count run',
    );
    return '$_temp0';
  }

  @override
  String get historyRefreshTooltip => 'Refresh from cloud';

  @override
  String get historyOfflineTooltip => 'Offline';

  @override
  String historySelectionTitle(int count) {
    return '$count selected';
  }

  @override
  String get historySelectAllTooltip => 'Select all';

  @override
  String get historyClearSelectionTooltip => 'Clear';

  @override
  String get historyDeleteTooltip => 'Delete';

  @override
  String get historyCancelTooltip => 'Cancel';

  @override
  String get historyAddRun => 'Add run';

  @override
  String get historyAddRunTooltip => 'Add a run manually';

  @override
  String get historyLogTooltip => 'Log a run, lift or meal';

  @override
  String historyLoadMore(int count) {
    return 'Load $count more';
  }

  @override
  String get historyNoMatch => 'No runs match these filters';

  @override
  String get historyKindAll => 'All';

  @override
  String get historyKindRuns => 'Runs';

  @override
  String get historyKindLifts => 'Lifts';

  @override
  String get historyKindMeals => 'Meals';

  @override
  String get historyViewAll => 'View all';

  @override
  String get historyToday => 'Today';

  @override
  String get historyYesterday => 'Yesterday';

  @override
  String historySetCount(int n) {
    return '$n sets';
  }

  @override
  String historyKcal(int n) {
    return '$n kcal';
  }

  @override
  String get historyTimelineEmpty => 'Nothing logged in this view yet.';

  @override
  String get historyClearFilters => 'Clear filters';

  @override
  String get historyEmptyTitle => 'No runs yet';

  @override
  String get historyEmptyBody => 'Tap the Run tab to start your first run';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historySourceAll => 'All sources';

  @override
  String historySourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String get historySourceFilterTooltip => 'Filter by source';

  @override
  String get historySourceRecorded => 'Recorded';

  @override
  String get historySourceWatch => 'Watch';

  @override
  String get historySourceStrava => 'Strava';

  @override
  String get historySourceParkrun => 'parkrun';

  @override
  String get historySourceHealthKit => 'HealthKit';

  @override
  String get historySourceHealthConnect => 'Health Connect';

  @override
  String get historyRangePickerTitle => 'Select dates';

  @override
  String get historyRangeStart => 'Start';

  @override
  String get historyRangeEnd => 'End';

  @override
  String get historyRangeTapDate => 'Tap a date';

  @override
  String get historyRangeApply => 'Apply';

  @override
  String get historyRangeClear => 'Clear';

  @override
  String get historyPrevMonth => 'Previous month';

  @override
  String get historyNextMonth => 'Next month';

  @override
  String get historyPrevYear => 'Previous year';

  @override
  String get historyNextYear => 'Next year';

  @override
  String historyDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count runs?',
      one: 'Delete $count run?',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody => 'This cannot be undone.';

  @override
  String get historyCancel => 'Cancel';

  @override
  String get historyDelete => 'Delete';

  @override
  String get historyQueuedToSync => 'Queued to sync';

  @override
  String get historySignInToSync => 'Sign in from Settings to sync runs';

  @override
  String get historyRefreshFailed =>
      'Could not refresh — check your connection';

  @override
  String get historyLoadMoreFailed => 'Could not load more runs';

  @override
  String historySyncPartial(int synced, int total, String error) {
    return 'Synced $synced/$total. Error: $error';
  }

  @override
  String historySyncTrackFailed(int count) {
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
  String historySyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count runs synced',
      one: '$count run synced',
    );
    return '$_temp0';
  }

  @override
  String historyDeletePartial(int deleted, int queued) {
    return '$deleted deleted; $queued queued — will retry when back online.';
  }

  @override
  String historyDeleteDone(int count) {
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
  String get runDetailReportRun => 'Report run';

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
  String get runDetailStatGradeAdjPace => 'Grade-Adj. Pace';

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
  String runDetailRouteSaveFailed(String name) {
    return 'Couldn\'t save \"$name\" as a route.';
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
  String get runDetailMatchOffline => 'Offline — showing raw track, will retry';

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

  @override
  String get routesSyncFailedOffline =>
      'Could not sync routes — working offline';

  @override
  String get routesLoadMoreFailed => 'Could not load more routes';

  @override
  String routesStarUpdateFailed(String error) {
    return 'Could not update star: $error';
  }

  @override
  String get routesImportFailedLocalOnly =>
      'Import failed: pick the file from local storage, not a cloud-only document picker.';

  @override
  String routesImported(String name) {
    return 'Imported \"$name\"';
  }

  @override
  String routesImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String routesSaved(String name) {
    return 'Saved \"$name\"';
  }

  @override
  String get routesEmptyTitle => 'No routes yet';

  @override
  String get routesEmptyBody =>
      'Tap Build to draw a route on the map, or Import a GPX, KML, or TCX file.';

  @override
  String get routesBuild => 'Build';

  @override
  String get routesImport => 'Import';

  @override
  String get routesNoMatch => 'No routes match these filters';

  @override
  String get routesClearFilters => 'Clear filters';

  @override
  String routesLoadMore(int count) {
    return 'Load $count more';
  }

  @override
  String get routesQueuedToSync => 'Queued to sync';

  @override
  String get routesSavedForOffline => 'Saved for offline';

  @override
  String get routesUnstarRoute => 'Unstar route';

  @override
  String get routesStarForWatch => 'Star to show on watch';

  @override
  String get routesDiscover => 'Discover';

  @override
  String get routesSyncFromCloud => 'Sync from cloud';

  @override
  String get routesPublicRoutes => 'Public routes';

  @override
  String get routesHeatmapTooltip => 'Routes heatmap';

  @override
  String get routesSearchHint => 'Search routes by name…';

  @override
  String get routesClearSearch => 'Clear search';

  @override
  String get routesStarred => 'Starred';

  @override
  String routesCountMeta(int visible, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$visible of $total routes',
      one: '$visible of $total route',
    );
    return '$_temp0';
  }

  @override
  String get routesSurfaceAny => 'Any surface';

  @override
  String get routesSurfaceRoad => 'Road';

  @override
  String get routesSurfaceTrail => 'Trail';

  @override
  String get routesSurfaceMixed => 'Mixed';

  @override
  String get routesDistanceAny => 'Any distance';

  @override
  String get routesSortNewest => 'Newest first';

  @override
  String get routesSortLongest => 'Longest';

  @override
  String get routesSortShortest => 'Shortest';

  @override
  String get routesSortMostRun => 'Most-run';

  @override
  String get routesSortAlpha => 'A–Z';

  @override
  String routesDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count routes?',
      one: 'Delete $count route?',
    );
    return '$_temp0';
  }

  @override
  String get routesDeleteConfirmBody => 'This cannot be undone.';

  @override
  String routesSelectionTitle(int count) {
    return '$count selected';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted deleted; $failed failed — check your connection.';
  }

  @override
  String routesDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count routes deleted.',
      one: '$count route deleted.',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteCleared => 'Route cleared';

  @override
  String routeBuilderPointsSummary(int count, String distance) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points, $distance',
      one: '$count point, $distance',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteFailedStraightLines =>
      'Couldn\'t route — showing straight lines through your pins.';

  @override
  String routeBuilderSegmentsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count segments couldn\'t snap to a road. Drag the affected pins to adjust.',
      one:
          '$count segment couldn\'t snap to a road. Drag the affected pin to adjust.',
    );
    return '$_temp0';
  }

  @override
  String routeBuilderRoutingFailed(String error) {
    return 'Routing failed: $error';
  }

  @override
  String get routeBuilderTooCloseToPin =>
      'Too close to another pin — drag a bit further.';

  @override
  String get routeBuilderPinAlreadyThere =>
      'Pin already there — tap further apart to add another.';

  @override
  String get routeBuilderTargetTooLong =>
      'Enter a target distance up to 1000 km.';

  @override
  String get routeBuilderSaveNeedTwo => 'Place at least two waypoints first.';

  @override
  String routeBuilderSavedLocally(String detail) {
    return 'Saved locally. $detail Will sync next time.';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return 'Location unavailable: $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'Can\'t reach the server. Sign in or check your connection and try again.';

  @override
  String routeBuilderSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get routeBuilderSearchHint => 'Search places…';

  @override
  String get routeBuilderMore => 'More';

  @override
  String get routeBuilderGenerateLoop => 'Generate loop';

  @override
  String get routeBuilderUndo => 'Undo';

  @override
  String get routeBuilderClear => 'Clear';

  @override
  String get routeBuilderClearConfirmTitle => 'Clear this route?';

  @override
  String get routeBuilderClearConfirmBody =>
      'All waypoints will be removed. This can\'t be undone.';

  @override
  String get routeBuilderSaving => 'Saving…';

  @override
  String get routeBuilderSave => 'Save';

  @override
  String get routeBuilderLocateMe => 'Locate me';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'Tap to move point $number, or use the icons';
  }

  @override
  String routeBuilderEmptyHint(String mode) {
    return 'Tap the map to place waypoints · $mode';
  }

  @override
  String routeBuilderOnePointHint(String mode) {
    return 'Place another to draw the line · $mode';
  }

  @override
  String routeBuilderStatusGain(String distance, int gain, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '$count point',
    );
    return '$distance · $gain m ↑ · $_temp0';
  }

  @override
  String routeBuilderStatusNoGain(String distance, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '$count point',
    );
    return '$distance · $_temp0';
  }

  @override
  String routeBuilderDeletePoint(int number) {
    return 'Delete point $number';
  }

  @override
  String get routeBuilderCancelDrag => 'Cancel drag';

  @override
  String get routeBuilderPointList => 'Route points';

  @override
  String routeBuilderPointMovedTo(int from, int to) {
    return 'Point $from moved to position $to';
  }

  @override
  String routeBuilderPointRemoved(int number) {
    return 'Point $number removed';
  }

  @override
  String routeBuilderReorderPoint(int number) {
    return 'Reorder point $number';
  }

  @override
  String get routeBuilderPointStart => 'Start';

  @override
  String get routeBuilderPointEnd => 'End';

  @override
  String get routeBuilderModeTrail => 'Trail';

  @override
  String get routeBuilderModeRoad => 'Road';

  @override
  String get routeBuilderModeStraight => 'Straight';

  @override
  String get routeBuilderLoopDialogBody =>
      'Target distance — we\'ll build a radial loop around the current map centre.';

  @override
  String get routeBuilderCancel => 'Cancel';

  @override
  String get routeBuilderGenerate => 'Generate';

  @override
  String get routeBuilderSaveDialogTitle => 'Save route';

  @override
  String get routeBuilderNameLabel => 'Name';

  @override
  String get routeBuilderNameHint => 'e.g. River loop';

  @override
  String get routeBuilderDescriptionLabel => 'Description (optional)';

  @override
  String get routeBuilderDescriptionHint =>
      'Surface, hills, parking, anything worth noting';

  @override
  String get routeBuilderSaveToLabel => 'Save to';

  @override
  String get routeBuilderSaveToPersonal => 'Personal';

  @override
  String get routeBuilderMakePublic => 'Make public';

  @override
  String get routeBuilderMakePublicSubtitle => 'Others can find it on Explore';

  @override
  String get routeDetailStartRun => 'Start run';

  @override
  String get routeDetailShare => 'Share';

  @override
  String get routeDetailShareAsImage => 'Share as image';

  @override
  String get routeDetailShareAsGpx => 'Share as GPX';

  @override
  String get routeDetailShareAsKml => 'Share as KML';

  @override
  String get routeDetailShareAsGpxMarkers => 'Share as GPX + markers';

  @override
  String get routeDetailRemoveOfflineSave => 'Remove offline save';

  @override
  String get routeDetailSaveForOffline => 'Save for offline use';

  @override
  String get routeDetailUnstarRoute => 'Unstar route';

  @override
  String get routeDetailStarForWatch => 'Star to show on watch';

  @override
  String get routeDetailMakePrivate => 'Make private';

  @override
  String get routeDetailMakePublic => 'Make public';

  @override
  String get routeDetailRemoveBookmark => 'Remove bookmark';

  @override
  String get routeDetailBookmarkRoute => 'Bookmark route';

  @override
  String get routeDetailReportRoute => 'Report route';

  @override
  String get routeDetailTransferToClub => 'Transfer to club';

  @override
  String get routeDetailManageClub => 'Detach or move to another club';

  @override
  String get routeDetailDeleteRoute => 'Delete route';

  @override
  String get routeDetailStatDistance => 'Distance';

  @override
  String get routeDetailStatElevation => 'Elevation';

  @override
  String routeDetailStatReviews(int count) {
    return '$count reviews';
  }

  @override
  String get routeDetailStatWaypoints => 'Waypoints';

  @override
  String get routeDetailPublicRoute => 'Public route';

  @override
  String get routeDetailPrivateRoute => 'Private route';

  @override
  String get routeDetailPublicSubtitle =>
      'Anyone with the share link can view this route';

  @override
  String get routeDetailPrivateSubtitle => 'Only you can see this route';

  @override
  String get routeDetailSavedForOffline => 'Saved for offline';

  @override
  String get routeDetailSaveForOfflineTitle => 'Save for offline';

  @override
  String get routeDetailOfflinePinnedSubtitle =>
      'Route stays on this phone so you can run it without a connection.';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'Keep this route on your phone for use without a network.';

  @override
  String get routeDetailDescriptionHeading => 'Description';

  @override
  String get routeDetailDescribe => 'Describe this route';

  @override
  String get routeDetailDescribing => 'Describing…';

  @override
  String get routeDetailAiAttribution =>
      'Written by AI from this route\'s stats';

  @override
  String get routeDetailDescribeFailed =>
      'Couldn\'t generate a description. Please try again.';

  @override
  String get routeDetailEnhanceUpgradeHint =>
      'AI descriptions are a Pro feature. Upgrade to enhance.';

  @override
  String get routeDetailDescShapeLoop => 'loop';

  @override
  String get routeDetailDescShapeOutAndBack => 'out-and-back';

  @override
  String get routeDetailDescShapePointToPoint => 'point-to-point';

  @override
  String get routeDetailDescSurfaceRoad => 'road';

  @override
  String get routeDetailDescSurfaceTrail => 'trail';

  @override
  String get routeDetailDescSurfaceMixed => 'mixed-surface';

  @override
  String get routeDetailDescElevFlat => 'flat';

  @override
  String get routeDetailDescElevRolling => 'gently rolling';

  @override
  String get routeDetailDescElevHilly => 'hilly';

  @override
  String get routeDetailDescElevMountainous => 'mountainous';

  @override
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  ) {
    return '$name is a $distance $surface $shape route.';
  }

  @override
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  ) {
    return '$name is a $distance $shape route.';
  }

  @override
  String routeDetailDescClimb(String gain, String elevation, String perKm) {
    return 'It has $gain of climbing — $elevation, about $perKm per km.';
  }

  @override
  String get routeDetailDescFlat => 'It has little to no elevation change.';

  @override
  String routeDetailDescPerKm(int m) {
    return '$m m';
  }

  @override
  String routeDetailRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return '$_temp0';
  }

  @override
  String get routeDetailFeatured => 'Featured';

  @override
  String get routeDetailSurfaceTrail => 'TRAIL';

  @override
  String get routeDetailSurfaceMixed => 'MIXED';

  @override
  String get routeDetailSurfaceRoad => 'ROAD';

  @override
  String get routeDetailAddTagHint => 'add tag';

  @override
  String get routeDetailReviewsHeading => 'Reviews';

  @override
  String get routeDetailRate => 'Rate';

  @override
  String routeDetailRateStars(int n) {
    return 'Set rating to $n of 5';
  }

  @override
  String get routeDetailReviewsOffline => 'Reviews unavailable offline';

  @override
  String get routeDetailNoReviews => 'No reviews yet';

  @override
  String get routeDetailRateDialogTitle => 'Rate this route';

  @override
  String get routeDetailCommentLabel => 'Comment (optional)';

  @override
  String get routeDetailCancel => 'Cancel';

  @override
  String get routeDetailSubmit => 'Submit';

  @override
  String get routeDetailSignInToReview => 'Sign in to leave a review';

  @override
  String routeDetailReviewFailed(String error) {
    return 'Failed to submit review: $error';
  }

  @override
  String routeDetailBookmarkFailed(String error) {
    return 'Bookmark failed: $error';
  }

  @override
  String get routeDetailPublicWillSync =>
      'Route set to public. Will sync next time.';

  @override
  String get routeDetailPrivateWillSync =>
      'Route set to private. Will sync next time.';

  @override
  String routeDetailVisibilityFailed(String error) {
    return 'Could not update visibility: $error';
  }

  @override
  String routeDetailStarFailed(String error) {
    return 'Could not update star: $error';
  }

  @override
  String get routeDetailOfflineSaved => 'Saved for offline use.';

  @override
  String get routeDetailOfflineRemoved => 'Removed from offline saves.';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'Could not save tag: $error';
  }

  @override
  String routeDetailTagRemoveFailed(String error) {
    return 'Could not remove tag: $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return 'Could not share $format: $error';
  }

  @override
  String get routeDetailClubsLoadTimeout =>
      'Couldn\'t load your clubs — check your network.';

  @override
  String get routeDetailClubsLoadFailed => 'Couldn\'t load your clubs.';

  @override
  String get routeDetailDetached =>
      'Detached from club; route is now personal.';

  @override
  String get routeDetailMovedToClub => 'Route moved into the club library.';

  @override
  String routeDetailTransferFailed(String error) {
    return 'Transfer failed: $error';
  }

  @override
  String get routeDetailDeleteTitle => 'Delete route?';

  @override
  String get routeDetailDeleteBody => 'This cannot be undone.';

  @override
  String get routeDetailDelete => 'Delete';

  @override
  String routeDetailDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get routeDetailPreview => 'Preview';

  @override
  String get routeDetailPreviewStart => 'Start';

  @override
  String get routeDetailPreviewFinish => 'Finish';

  @override
  String get routeDetailTransferDialogTitle => 'Transfer to club';

  @override
  String get routeDetailManageClubTitle => 'Manage club ownership';

  @override
  String get routeDetailTransferDialogBody =>
      'Members of the club will see this route in the club library and can adopt it onto their plans.';

  @override
  String get routeDetailManageClubBody =>
      'Move this route into another club you admin, or detach it back to personal.';

  @override
  String get routeDetailDetachToPersonal => 'Detach to personal';

  @override
  String get routeDetailDetachSubtitle =>
      'Removes the route from the current club\'s library.';

  @override
  String get routeDetailNoAdminClubs =>
      'You don\'t own or admin any clubs yet.';

  @override
  String get routeDetailCurrentClub => 'Current club';

  @override
  String routeDetailClubMemberCount(String location, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '$count member',
    );
    return '$location · $_temp0';
  }

  @override
  String get exploreRoutesTitle => 'Explore Routes';

  @override
  String get exploreRoutesModeSearch => 'Search';

  @override
  String get exploreRoutesModeNearMe => 'Near Me';

  @override
  String get exploreRoutesSearchHint => 'Search routes by name...';

  @override
  String get exploreRoutesFeatured => 'Featured';

  @override
  String get exploreRoutesSignInRequired =>
      'Sign in and connect to the internet to explore routes';

  @override
  String get exploreRoutesTimeout =>
      'Connection timed out. Check your network and try again.';

  @override
  String get exploreRoutesSearchFailed =>
      'Search failed. Tap retry to try again.';

  @override
  String get exploreRoutesLoadMoreFailed =>
      'Could not load more — check your connection';

  @override
  String get exploreRoutesLocationPermissionRequired =>
      'Location permission required to find nearby routes';

  @override
  String get exploreRoutesNearbyFailed =>
      'Could not find nearby routes. Tap retry to try again.';

  @override
  String get exploreRoutesEmptyNoPublic => 'No public routes yet';

  @override
  String get exploreRoutesEmptyNoMatch => 'No routes match your search';

  @override
  String get exploreRoutesEmptyBody =>
      'Routes shared from the web app appear here';

  @override
  String get exploreRoutesDistanceAny => 'Any distance';

  @override
  String get exploreRoutesSurfaceAny => 'Any surface';

  @override
  String get exploreRoutesSurfaceRoad => 'Road';

  @override
  String get exploreRoutesSurfaceTrail => 'Trail';

  @override
  String get exploreRoutesSurfaceMixed => 'Mixed';

  @override
  String get exploreRoutesSortMostRun => 'Most run';

  @override
  String get exploreRoutesSortNewest => 'Newest';

  @override
  String get exploreRoutesSortFeatured => 'Featured';

  @override
  String get exploreRoutesSort => 'Sort';

  @override
  String exploreRoutesSaveCheckConnection(String name) {
    return 'Couldn\'t save \"$name\" — check your connection and try again.';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return 'Couldn\'t save \"$name\".';
  }

  @override
  String exploreRoutesSaved(String name) {
    return 'Saved \"$name\" to your library';
  }

  @override
  String get exploreRoutesAlreadySaved => 'Already saved';

  @override
  String get exploreRoutesSaveToLibrary => 'Save to library';

  @override
  String get exploreRoutesSurfaceTrailShort => 'Trail';

  @override
  String get exploreRoutesSurfaceMixedShort => 'Mixed';

  @override
  String get exploreRoutesSurfaceRoadShort => 'Road';

  @override
  String get exploreRoutesDistanceUnderKm => 'Under 5 km';

  @override
  String get exploreRoutesDistanceMidKm => '5-10 km';

  @override
  String get exploreRoutesDistanceLongKm => '10-21 km';

  @override
  String get exploreRoutesDistanceUltraKm => '21 km+';

  @override
  String get exploreRoutesDistanceUnderMi => 'Under 3 mi';

  @override
  String get exploreRoutesDistanceMidMi => '3-6 mi';

  @override
  String get exploreRoutesDistanceLongMi => '6-13 mi';

  @override
  String get exploreRoutesDistanceUltraMi => '13 mi+';

  @override
  String get heatmapSearchHint => 'Search places…';

  @override
  String get heatmapFilters => 'Filters';

  @override
  String heatmapRoutesStartHere(int count) {
    return '$count routes start here';
  }

  @override
  String heatmapRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count routes',
      one: '$count route',
    );
    return '$_temp0';
  }

  @override
  String get heatmapNoRoutesHere => 'No routes here';

  @override
  String get heatmapNoRoutesHint =>
      'No routes here. Pan the map or change the filters.';

  @override
  String heatmapClearKept(int count) {
    return 'Clear $count kept';
  }

  @override
  String get heatmapUnpinFromMap => 'Unpin from map';

  @override
  String get heatmapKeepOnMap => 'Keep on map';

  @override
  String get heatmapLocateMe => 'Locate me';

  @override
  String heatmapLocationUnavailable(String error) {
    return 'Location unavailable: $error';
  }

  @override
  String get heatmapBackToList => 'Back to list';

  @override
  String get heatmapViewRoute => 'View route';

  @override
  String get heatmapKept => 'Kept';

  @override
  String get heatmapKeep => 'Keep';

  @override
  String get heatmapLensShow => 'Show';

  @override
  String get heatmapLensDistance => 'Distance';

  @override
  String get heatmapLensMap => 'Map';

  @override
  String get heatmapHeatDensity => 'Heat density';

  @override
  String get heatmapResetFilters => 'Reset filters';

  @override
  String get heatmapLensPopular => 'Popular';

  @override
  String get heatmapLensFriends => 'Friends';

  @override
  String get heatmapLensFeatured => 'Featured';

  @override
  String get heatmapLensHiddenGems => 'Hidden gems';

  @override
  String get runHeatmapTitle => 'Your heatmap';

  @override
  String get runHeatmapTooltip => 'Run heatmap';

  @override
  String get runHeatmapLoading => 'Loading your runs…';

  @override
  String runHeatmapLoadingProgress(int n, int total) {
    return 'Loading your runs… $n/$total';
  }

  @override
  String get runHeatmapEmptyTitle => 'No mapped runs yet';

  @override
  String get runHeatmapEmptyBody =>
      'Record or import runs with GPS tracks and they\'ll light up here.';

  @override
  String get runHeatmapErrorTitle => 'Couldn\'t load your heatmap';

  @override
  String get runHeatmapErrorBody =>
      'Something went wrong loading your runs. Check your connection and try again.';

  @override
  String get runHeatmapRetry => 'Try again';

  @override
  String get runHeatmapLegendTitle => 'Your heatmap';

  @override
  String runHeatmapLegendSummaryOne(int n) {
    return '$n mapped run — brighter where you run most.';
  }

  @override
  String runHeatmapLegendSummaryMany(int n) {
    return '$n mapped runs — brighter where you run most.';
  }

  @override
  String get runHeatmapScaleLess => 'less';

  @override
  String get runHeatmapScaleMore => 'more';

  @override
  String get publicRouteFallbackTitle => 'Route';

  @override
  String get publicRouteLoadError => 'Could not load this route.';

  @override
  String get publicRouteUnavailable =>
      'This route is private or no longer available.';

  @override
  String get publicRouteStatDistance => 'Distance';

  @override
  String get publicRouteStatElevation => 'Elevation';

  @override
  String get publicRouteStatWaypoints => 'Waypoints';

  @override
  String get routesLoadErrorRetry =>
      'Couldn\'t load your routes. Check your connection and try again.';

  @override
  String get feedTitle => 'Feed';

  @override
  String get feedFindPeople => 'Find people';

  @override
  String get feedActivityAll => 'All';

  @override
  String get feedActivityRun => 'Run';

  @override
  String get feedActivityWalk => 'Walk';

  @override
  String get feedActivityCycle => 'Cycle';

  @override
  String get feedActivityHike => 'Hike';

  @override
  String get feedActivityLift => 'Lift';

  @override
  String get feedLiftSetsLabel => 'Sets';

  @override
  String get feedLiftVolume => 'Volume';

  @override
  String get feedLiftUntitled => 'Workout';

  @override
  String get feedLoadMore => 'Load more';

  @override
  String feedLoadMoreFailed(String error) {
    return 'Could not load more: $error';
  }

  @override
  String get feedLoadError => 'Could not load feed.';

  @override
  String get feedEveryoneYouFollow => 'Everyone you follow';

  @override
  String get feedRunnerFallback => 'Runner';

  @override
  String get relativeJustNow => 'Just now';

  @override
  String relativeMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String relativeHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String get relativeYesterday => 'Yesterday';

  @override
  String relativeDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks ago',
      one: '1 week ago',
    );
    return '$_temp0';
  }

  @override
  String get coachArchiveToday => 'Today';

  @override
  String coachArchiveDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
    );
    return '$_temp0';
  }

  @override
  String get feedLast14Days => 'Last 14 days';

  @override
  String get feedEmptyTitle => 'Your feed is empty';

  @override
  String get feedEmptyBody =>
      'Follow other runners to see their public runs here.';

  @override
  String get feedNoMatchesTitle => 'No matches';

  @override
  String get feedNoMatchesBody =>
      'Nothing matches the current filters in the last 14 days.';

  @override
  String get feedNoActivityTitle => 'No recent activity';

  @override
  String get feedNoActivityBody =>
      'Nobody you follow has logged a public run in the last 14 days.';

  @override
  String get feedClearFilters => 'Clear filters';

  @override
  String feedKudosUpdateFailed(String error) {
    return 'Could not update kudos: $error';
  }

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileRunnerFallback => 'Runner';

  @override
  String get profileTabRuns => 'Runs';

  @override
  String get profileTabFollowers => 'Followers';

  @override
  String get profileTabFollowing => 'Following';

  @override
  String get profileTabNotifications => 'Notifications';

  @override
  String get profileReportUser => 'Report user';

  @override
  String get profileUnblock => 'Unblock this profile';

  @override
  String get profileBlock => 'Block this profile';

  @override
  String get profileLoadError => 'Could not load profile.';

  @override
  String get profileNotFound => 'Profile not found.';

  @override
  String profileFollowStats(int followers, int following) {
    String _temp0 = intl.Intl.pluralLogic(
      followers,
      locale: localeName,
      other: '$followers followers',
      one: '$followers follower',
    );
    return '$_temp0 · $following following';
  }

  @override
  String get profileFollowing => 'Following';

  @override
  String get profileFollow => 'Follow';

  @override
  String get profileRunsEmptySelf => 'You haven\'t shared any runs yet.';

  @override
  String get profileRunsEmptyOther => 'No public runs yet.';

  @override
  String get profileFollowersEmpty => 'No followers yet.';

  @override
  String get profileFollowingEmpty => 'Not following anyone yet.';

  @override
  String profileLoadMore(int count) {
    return 'Load $count more';
  }

  @override
  String get profileLoadMoreFollowersFailed => 'Could not load more followers';

  @override
  String get profileLoadMoreFollowingFailed => 'Could not load more following';

  @override
  String profileFollowUpdateFailed(String error) {
    return 'Could not update follow: $error';
  }

  @override
  String profileBlockConfirmTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get profileBlockConfirmBody =>
      'They won\'t be able to follow you, give kudos to your runs, or comment on them. Any existing follow between you in either direction will be cleared. You can unblock from this page at any time.';

  @override
  String get profileBlockConfirmAction => 'Block';

  @override
  String get profileCancel => 'Cancel';

  @override
  String get profileThisRunner => 'this runner';

  @override
  String get profileRunnerNoun => 'runner';

  @override
  String profileBlocked(String name) {
    return 'Blocked $name';
  }

  @override
  String profileBlockFailed(String error) {
    return 'Could not block: $error';
  }

  @override
  String profileUnblocked(String name) {
    return 'Unblocked $name';
  }

  @override
  String profileUnblockFailed(String error) {
    return 'Could not unblock: $error';
  }

  @override
  String get profileNotifAll => 'All';

  @override
  String get profileNotifUnread => 'Unread';

  @override
  String get profileMarkAllRead => 'Mark all read';

  @override
  String profileMarkAllReadFailed(String error) {
    return 'Failed to mark all read: $error';
  }

  @override
  String get profileNotifsCaughtUp => 'You\'re all caught up.';

  @override
  String get profileNotifsEmpty => 'No notifications yet.';

  @override
  String get profileDismiss => 'Dismiss';

  @override
  String profileDismissFailed(String error) {
    return 'Failed to dismiss: $error';
  }

  @override
  String get profileNotifSomeone => 'Someone';

  @override
  String get profileNotifYourRun => 'your run';

  @override
  String profileNotifKudos(String name, String dist) {
    return '$name gave kudos to your $dist';
  }

  @override
  String profileNotifComment(String name, String dist) {
    return '$name commented on your $dist';
  }

  @override
  String profileNotifCommentReply(String name) {
    return '$name replied to your comment';
  }

  @override
  String profileNotifFollow(String name) {
    return '$name started following you';
  }

  @override
  String profileNotifEventRsvpTitled(String name, String title) {
    return '$name RSVP\'d Going to your event \"$title\"';
  }

  @override
  String profileNotifEventRsvp(String name) {
    return '$name RSVP\'d Going to your event';
  }

  @override
  String profileNotifPlanUpdate(String name) {
    return '$name updated your training plan';
  }

  @override
  String profileNotifMessage(String name) {
    return '$name sent you a message';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$name posted in $club';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$name posted in a club you\'re in';
  }

  @override
  String profileNotifRunCompletedDist(String name, String dist) {
    return '$name completed a $dist run';
  }

  @override
  String profileNotifRunCompleted(String name) {
    return '$name completed a run';
  }

  @override
  String profileNotifGeneric(String name) {
    return '$name interacted with your activity';
  }

  @override
  String get socialTabFeed => 'Feed';

  @override
  String get socialTabPeople => 'People';

  @override
  String get socialTabClubs => 'Clubs';

  @override
  String get socialTabRoutes => 'Routes';

  @override
  String get socialTabDiscover => 'Discover';

  @override
  String get discoverSearchPlaceholder =>
      'Search yoga, pilates, HIIT, run clubs…';

  @override
  String get discoverActivityAll => 'All activities';

  @override
  String get discoverCadenceLabel => 'Cadence';

  @override
  String get discoverCadenceAny => 'Any cadence';

  @override
  String get discoverOneOff => 'One-off';

  @override
  String get discoverWeekly => 'Weekly';

  @override
  String get discoverBiweekly => 'Every 2 weeks';

  @override
  String get discoverMonthly => 'Monthly';

  @override
  String get discoverDayLabel => 'Day';

  @override
  String get discoverDayAny => 'Any day';

  @override
  String get discoverDayMon => 'Mon';

  @override
  String get discoverDayTue => 'Tue';

  @override
  String get discoverDayWed => 'Wed';

  @override
  String get discoverDayThu => 'Thu';

  @override
  String get discoverDayFri => 'Fri';

  @override
  String get discoverDaySat => 'Sat';

  @override
  String get discoverDaySun => 'Sun';

  @override
  String get discoverTimeLabel => 'Time of day';

  @override
  String get discoverTimeAny => 'Any time';

  @override
  String get discoverMorning => 'Morning';

  @override
  String get discoverAfternoon => 'Afternoon';

  @override
  String get discoverEvening => 'Evening';

  @override
  String get discoverPriceLabel => 'Price';

  @override
  String get discoverPriceAny => 'Any price';

  @override
  String get discoverFree => 'Free';

  @override
  String get discoverPaid => 'Paid';

  @override
  String get discoverLoading => 'Searching…';

  @override
  String get discoverEmpty => 'No public activities match these filters yet.';

  @override
  String get discoverSearchFailed =>
      'Couldn\'t load activities. Check your connection and try again.';

  @override
  String get clubsTitle => 'Clubs';

  @override
  String get clubsFindPeople => 'Find people';

  @override
  String get clubsNewClub => 'New club';

  @override
  String get clubsTabBrowse => 'Browse';

  @override
  String get clubsTabMine => 'My clubs';

  @override
  String get clubsJoinWithCode => 'Join with invite code';

  @override
  String get clubsSearchHint => 'Search by name or location';

  @override
  String get clubsTimeoutError =>
      'Connection timed out. Check your network and try again.';

  @override
  String get clubsLoadError => 'Couldn\'t load clubs. Tap retry to try again.';

  @override
  String get clubsBadgePrivate => 'PRIVATE';

  @override
  String clubsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '$count member',
    );
    return '$_temp0';
  }

  @override
  String get clubsEmptyBrowseTitle => 'No clubs match that search.';

  @override
  String get clubsEmptyMineTitle => 'You haven\'t joined a club yet.';

  @override
  String get clubsEmptyBrowseBody => 'Try a different name or location.';

  @override
  String get clubsEmptyMineBody => 'Head to Browse to find one.';

  @override
  String get clubDetailTabFeed => 'Feed';

  @override
  String get clubDetailTabEvents => 'Events';

  @override
  String get clubDetailTabMembers => 'Members';

  @override
  String get clubDetailTabRoutes => 'Routes';

  @override
  String get clubDetailTabTemplates => 'Templates';

  @override
  String get clubDetailTabPhotos => 'Photos';

  @override
  String get clubDetailReportClub => 'Report club';

  @override
  String get clubDetailReportPost => 'Report this post';

  @override
  String get clubDetailLoadFailedTitle => 'Couldn\'t load this club.';

  @override
  String get clubDetailLoadFailedBody =>
      'It may have been removed, or your session might need to be refreshed. Try pulling to retry, or sign out and back in from Settings.';

  @override
  String get clubDetailRetry => 'Retry';

  @override
  String get clubDetailTimeoutError =>
      'Connection timed out. Check your network and try again.';

  @override
  String get clubDetailRequestSent => 'Request sent to admins.';

  @override
  String clubDetailLeaveTitle(String club) {
    return 'Leave $club?';
  }

  @override
  String get clubDetailCancel => 'Cancel';

  @override
  String get clubDetailLeave => 'Leave';

  @override
  String clubDetailReplyFailed(String error) {
    return 'Could not post reply: $error';
  }

  @override
  String get clubDetailMemberFallback => 'Member';

  @override
  String get clubDetailRequestPending => 'Request pending';

  @override
  String get clubDetailInviteOnly => 'Invite only';

  @override
  String get clubDetailRequest => 'Request';

  @override
  String get clubDetailJoin => 'Join';

  @override
  String get clubDetailOwner => 'Owner';

  @override
  String get clubDetailNextEvent => 'NEXT EVENT';

  @override
  String clubDetailGoingCount(int count) {
    return '$count going';
  }

  @override
  String get clubDetailNoPostsMember =>
      'No posts yet. Share an update with members.';

  @override
  String get clubDetailNoPosts => 'No updates yet.';

  @override
  String get clubDetailShareUpdateHint => 'Share an update…';

  @override
  String get clubDetailPost => 'Post';

  @override
  String get clubDetailReply => 'Reply';

  @override
  String clubDetailHideReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hide $count replies',
      one: 'Hide $count reply',
    );
    return '$_temp0';
  }

  @override
  String clubDetailShowReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count replies',
      one: '$count reply',
    );
    return '$_temp0';
  }

  @override
  String clubDetailReplyAuthorLine(String name, String time) {
    return '$name · $time';
  }

  @override
  String get clubDetailWriteReplyHint => 'Write a reply…';

  @override
  String get clubDetailSend => 'Send';

  @override
  String get clubDetailNoEventsAdmin =>
      'No upcoming events. Tap Create to add one.';

  @override
  String get clubDetailNoEvents => 'No upcoming events.';

  @override
  String get clubDetailCreateEvent => 'Create event';

  @override
  String get clubDetailGoing => 'Going';

  @override
  String clubDetailApproveFailed(String error) {
    return 'Approve failed: $error';
  }

  @override
  String clubDetailDenyFailed(String error) {
    return 'Deny failed: $error';
  }

  @override
  String clubDetailPendingRequests(int count) {
    return 'Pending requests ($count)';
  }

  @override
  String clubDetailUserShort(String id) {
    return 'User $id…';
  }

  @override
  String get clubDetailDeny => 'Deny';

  @override
  String get clubDetailDenyTitle => 'Reject join request';

  @override
  String get clubDetailDenyMessage =>
      'Reject this request to join the club? They will not be added.';

  @override
  String get clubDetailApprove => 'Approve';

  @override
  String clubDetailMemberCountLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members.',
      one: '$count member.',
    );
    return '$_temp0';
  }

  @override
  String clubDetailRouteSaved(String name) {
    return 'Saved \"$name\"';
  }

  @override
  String get clubDetailBuildRoute => 'Build route for this club';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'No routes yet. Build the official course above, or transfer one of your personal routes from the route detail screen.';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'No routes yet. Admins can transfer one of their personal routes from the route detail screen.';

  @override
  String get clubDetailRoutesEmpty => 'No routes shared with this club yet.';

  @override
  String get clubDetailTemplateAdded => 'Template added to your plans.';

  @override
  String clubDetailAdoptFailed(String error) {
    return 'Adopt failed: $error';
  }

  @override
  String get clubDetailNoTemplatesAdmin =>
      'No templates yet. Publish one of your plans from its detail page.';

  @override
  String get clubDetailNoTemplates => 'No plan templates yet for this club.';

  @override
  String get clubDetailAdopt => 'Adopt';

  @override
  String get clubDetailSessionTemplatesTitle => 'Session templates';

  @override
  String get clubDetailSessionAdopted => 'Session added to your plans.';

  @override
  String get clubDetailGymRoutineTemplatesTitle => 'Gym routine templates';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'Members can adopt a club gym routine into their own routines. Edits to a copy don\'t propagate back to the template.';

  @override
  String get clubDetailGymRoutineAdopted =>
      'Routine added to your gym routines.';

  @override
  String clubDetailRoutineExerciseCount(int n) {
    return '$n exercises';
  }

  @override
  String get eventNotFound => 'Event not found.';

  @override
  String get eventLoadError =>
      'Couldn\'t load this event. Tap retry to try again.';

  @override
  String get eventTimeoutError =>
      'Connection timed out. Check your network and try again.';

  @override
  String eventDurationMin(int minutes) {
    return '· $minutes min';
  }

  @override
  String eventGetDirectionsTo(String label) {
    return 'Get directions to $label';
  }

  @override
  String get eventGetDirections => 'Get directions';

  @override
  String get eventCouldNotOpenMaps => 'Could not open maps.';

  @override
  String get eventPickOccurrence => 'PICK AN OCCURRENCE';

  @override
  String get eventTargetPace => 'Target pace';

  @override
  String get eventClassSessionEyebrow => 'CLASS';

  @override
  String get eventResultSubmitted => 'Result submitted.';

  @override
  String eventSubmitFailed(String error) {
    return 'Submit failed: $error';
  }

  @override
  String eventRaceControlFailed(String error) {
    return 'Race control failed: $error';
  }

  @override
  String eventAttendees(int count) {
    return 'ATTENDEES ($count)';
  }

  @override
  String get eventNoRsvps => 'No RSVPs yet — be the first.';

  @override
  String get eventAttendeeMember => 'Member';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventMarkAttended => 'Mark attended';

  @override
  String get eventMarkNoShow => 'Mark no-show';

  @override
  String get eventAttendanceAttended => 'Attended';

  @override
  String get eventAttendanceNoShow => 'No-show';

  @override
  String get eventAttendanceFailed =>
      'Could not update attendance. Please try again.';

  @override
  String get eventRsvpFailed => 'Couldn\'t update your RSVP. Please try again.';

  @override
  String get eventRsvpGoing => 'I\'m in';

  @override
  String get eventRsvpMaybe => 'Maybe';

  @override
  String get eventRsvpDeclined => 'Can\'t make it';

  @override
  String get eventRaceArmed => 'Armed — waiting for GO';

  @override
  String get eventRaceRunning => 'Running — live';

  @override
  String get eventRaceFinished => 'Finished';

  @override
  String get eventRaceCancelled => 'Cancelled';

  @override
  String get eventRaceNotArmed => 'Not armed';

  @override
  String get eventRaceControlLabel => 'RACE CONTROL';

  @override
  String get eventRaceAutoApprove => 'Auto-approve submitted times';

  @override
  String get eventRaceArm => 'Arm race';

  @override
  String get eventRaceArmedHint =>
      'Tap Fire Go when the race begins. Participants\' watches show the armed banner now.';

  @override
  String get eventRaceFireGo => 'Fire Go';

  @override
  String get eventRaceCancel => 'Cancel';

  @override
  String eventRaceStartedAt(String time) {
    return 'Started at $time';
  }

  @override
  String get eventRaceEnd => 'End race';

  @override
  String get eventRaceCancelRace => 'Cancel race';

  @override
  String get eventRaceEndConfirmBody =>
      'End the race? This finalizes the event for every runner and can\'t be undone.';

  @override
  String get eventRaceCancelConfirmBody =>
      'Cancel the race? This aborts the event for every runner and can\'t be undone.';

  @override
  String get eventUpdatePosted => 'Update posted to the club feed.';

  @override
  String eventPostUpdateFailed(String error) {
    return 'Could not post update: $error';
  }

  @override
  String get eventPostUpdateLabel => 'POST AN UPDATE';

  @override
  String get eventUpdateHint => 'Weather call? Meeting at a different spot?';

  @override
  String get eventPostUpdate => 'Post update';

  @override
  String get eventResultsTitle => 'Results';

  @override
  String get eventRemoveMine => 'Remove mine';

  @override
  String get eventRemoveResultTitle => 'Remove your result?';

  @override
  String get eventRemoveResultBody =>
      'Your submitted finish time will be removed from this event\'s leaderboard. You can submit again later.';

  @override
  String get eventRemoveResultConfirm => 'Remove result';

  @override
  String eventRemoveResultFailed(String error) {
    return 'Couldn\'t remove your result: $error';
  }

  @override
  String get eventSubmitMyTime => 'Submit my time';

  @override
  String get eventSubmitting => 'Submitting…';

  @override
  String get eventNoResults =>
      'No results yet. Submit your time after the event and others will see it here.';

  @override
  String get eventResultRunner => 'Runner';

  @override
  String get eventResultYou => '(you)';

  @override
  String get eventSubmitTimeTitle => 'Submit your time';

  @override
  String get eventSubmitTimeSubtitle =>
      'Pick a run to attach, or record a DNF / DNS.';

  @override
  String get eventNoRecentRuns =>
      'No recent runs found. Record a run first, then come back.';

  @override
  String get eventRecordDnf => 'Record DNF';

  @override
  String get eventRecordDns => 'Record DNS';

  @override
  String get eventSubmitCancel => 'Cancel';

  @override
  String get liveSpectatorTitle => 'Live tracking';

  @override
  String get liveSpectatorConnectError => 'Could not connect.';

  @override
  String get liveSpectatorWaiting =>
      'Waiting for the runner to send the first ping…';

  @override
  String get liveSpectatorBadgeLive => 'Live';

  @override
  String get liveSpectatorBadgeIdle => 'Idle';

  @override
  String get liveSpectatorBadgeConnecting => 'Connecting';

  @override
  String get liveSpectatorBadgeStale => 'Delayed';

  @override
  String get liveSpectatorBadgeApproximate => 'Approximate';

  @override
  String get liveSpectatorApproximateSub => 'Last seen near here — approximate';

  @override
  String get liveSpectatorBadgeFinished => 'Finished';

  @override
  String get liveSpectatorBadgeDnf => 'DNF';

  @override
  String get liveUpdatedNow => 'Updated just now';

  @override
  String liveUpdatedSeconds(int n) {
    return 'Updated ${n}s ago';
  }

  @override
  String liveUpdatedMinutes(int n) {
    return 'Updated $n min ago';
  }

  @override
  String liveUpdatedHours(int n) {
    return 'Updated ${n}h ago';
  }

  @override
  String liveUpdatedDays(int n) {
    return 'Updated ${n}d ago';
  }

  @override
  String get liveCutoffTitle => 'Next cut-off';

  @override
  String liveCutoffToGo(String distance) {
    return '$distance to go';
  }

  @override
  String liveCutoffEta(String eta) {
    return 'Projected arrival $eta';
  }

  @override
  String liveCutoffAhead(String margin) {
    return '$margin to spare';
  }

  @override
  String liveCutoffBehind(String margin) {
    return '$margin behind';
  }

  @override
  String get liveCutoffWaitingSignal =>
      'Waiting for a fresh signal to project arrival';

  @override
  String get plansTitle => 'Training plans';

  @override
  String get plansNewPlan => 'New plan';

  @override
  String plansDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get plansDeleteBody => 'All weeks and workouts will be removed.';

  @override
  String get plansCancel => 'Cancel';

  @override
  String get plansDelete => 'Delete';

  @override
  String get plansAbandon => 'Abandon';

  @override
  String plansAbandonTitle(String name) {
    return 'Abandon \"$name\"?';
  }

  @override
  String get plansAbandonBody => 'You can create a new plan after.';

  @override
  String plansActionFailed(String error) {
    return 'Couldn\'t update the plan: $error';
  }

  @override
  String plansDaysPerWeek(int count) {
    return '$count days/wk';
  }

  @override
  String get plansSignInTitle => 'Sign in to use training plans';

  @override
  String get plansSignInBody =>
      'Plans sync to your account so they follow you across devices. Head to Settings → Sign in to connect.';

  @override
  String get plansEmptyTitle => 'No plans yet.';

  @override
  String get plansEmptyBody =>
      'Pick a goal race and we\'ll schedule the weeks for you.';

  @override
  String get plansTimeoutError =>
      'Connection timed out. Check your network and try again.';

  @override
  String get plansLoadError =>
      'Couldn\'t load training plans. Tap retry to try again.';

  @override
  String get planNewTitle => 'New plan';

  @override
  String get planNewNameLabel => 'Plan name';

  @override
  String get planNewNameHint => 'e.g. Autumn half marathon';

  @override
  String get planNewGoalRace => 'Goal race';

  @override
  String get planNewStartDate => 'Start date';

  @override
  String get planNewDaysPerWeek => 'Days per week';

  @override
  String planNewDaysOption(int count) {
    return '$count days';
  }

  @override
  String get planNewGoalTimeSection => 'Goal time · optional';

  @override
  String get planNewBeginnerTitle => 'New to running? Use a walk-run plan';

  @override
  String get planNewBeginnerSubtitle =>
      'A gentle C25K-style schedule of timed run/walk intervals that builds to a continuous run. Overrides goal-time pacing.';

  @override
  String get planNewRecent5kSection => 'Recent 5K time · optional';

  @override
  String get planNewRecent5kHelp =>
      'Anchor paces on a real result instead of the goal. Uses Riegel equivalence to project to the goal distance.';

  @override
  String get planNewRecent5kConfirm =>
      'This is a time I could run today — it reflects my current fitness.';

  @override
  String get planNewRecent5kWarning =>
      'Until you confirm, paces stay on the conservative goal-based estimate. Anchoring on an old result can prescribe paces that are too fast for a returning runner.';

  @override
  String get planNewOverrideHint => 'Override total weeks';

  @override
  String planNewOverrideLabel(int count) {
    return 'Override weeks ($count default)';
  }

  @override
  String get planNewCancel => 'Cancel';

  @override
  String get planNewCreate => 'Create plan';

  @override
  String get planNewCreating => 'Creating…';

  @override
  String get planNewPreviewTitle => 'Preview';

  @override
  String get planNewPaceEasy => 'Easy';

  @override
  String get planNewPaceMarathon => 'Marathon';

  @override
  String get planNewPaceTempo => 'Tempo';

  @override
  String get planNewPaceInterval => 'Interval';

  @override
  String get planNewPaceRep => 'Rep';

  @override
  String get planNewPacesFallback =>
      'Estimated paces — add a recent run or a goal time for personalised targets.';

  @override
  String planNewVdot(String value) {
    return 'Daniels VDOT: $value';
  }

  @override
  String get planNewWeekOutline => 'Week outline';

  @override
  String planNewMoreWeeks(int count) {
    return '+ $count more weeks';
  }

  @override
  String planNewSessions(int count) {
    return '$count sessions';
  }

  @override
  String get planNewTemplateTitle => 'Start from a club template';

  @override
  String get planNewTemplateSubtitle =>
      'Adopt a plan a club you belong to has published. It clones into your account with the start date below — edit it like any other plan.';

  @override
  String get planNewTemplateButton => 'Browse templates';

  @override
  String get planNewTemplateCloning => 'Adopting…';

  @override
  String planNewTemplateCloneFailed(String error) {
    return 'Couldn\'t adopt that template: $error';
  }

  @override
  String get planNewTemplatePickerTitle => 'Choose a template';

  @override
  String get planNewTemplatePickerCancel => 'Cancel';

  @override
  String get planLibraryTitle => 'Public plan library';

  @override
  String get planLibrarySubheading =>
      'Plans published by other runners. Clone one into your account to start training.';

  @override
  String get planLibrarySearchHint => 'Search plans by name';

  @override
  String get planLibraryLoadError => 'Couldn’t load the library. Retry.';

  @override
  String get planLibraryRetry => 'Retry';

  @override
  String get planLibraryEmpty => 'No published plans yet.';

  @override
  String planLibraryEmptySearch(String query) {
    return 'No plans match “$query”.';
  }

  @override
  String planLibraryByAuthor(String author) {
    return 'by $author';
  }

  @override
  String get planLibraryAnonymous => 'a runner';

  @override
  String planLibraryWeeks(int weeks) {
    return '$weeks weeks';
  }

  @override
  String planLibraryDaysPerWeek(int days) {
    return '$days×/week';
  }

  @override
  String get planLibraryClone => 'Clone into my plans';

  @override
  String get planLibraryCloning => 'Cloning…';

  @override
  String get planLibraryCloneSuccess => 'Plan cloned.';

  @override
  String planLibraryCloneFailed(String error) {
    return 'Failed to clone: $error';
  }

  @override
  String get planLibraryStartDate => 'Start date';

  @override
  String get planLibraryNotFound =>
      'This plan is no longer in the public library.';

  @override
  String get planLibraryPreviewWeeks => 'Weeks';

  @override
  String planLibraryPreviewWeek(int n) {
    return 'Week $n';
  }

  @override
  String get planDetailPublishLibraryLabel => 'Public plan library';

  @override
  String get planDetailPublishLibrary => 'Publish to library';

  @override
  String get planDetailPublishLibraryHint =>
      'Share a copy of this plan so anyone can clone it. Your fitness numbers are not shared.';

  @override
  String get planDetailPublishLibrarySuccess =>
      'Plan published to the public library. Your personal plan is unchanged.';

  @override
  String planDetailPublishLibraryFailed(String error) {
    return 'Failed to publish: $error';
  }

  @override
  String get planDetailUnpublishLibrary => 'Unpublish';

  @override
  String get planDetailUnpublishSuccess => 'Removed from the public library.';

  @override
  String planDetailUnpublishFailed(String error) {
    return 'Failed to unpublish: $error';
  }

  @override
  String get planDetailAlreadyPublished =>
      'This plan is in the public library.';

  @override
  String get plansBrowseLibrary => 'Browse library';

  @override
  String get planNewStarterTitle => 'Start from a built-in plan';

  @override
  String get planNewStarterSubtitle =>
      'Pick a proven training plan and we\'ll schedule it from your start date — you can tweak it after.';

  @override
  String get planNewStarterButton => 'Browse starter plans';

  @override
  String get planNewStarterCreating => 'Creating…';

  @override
  String get planNewStarterPickerTitle => 'Choose a starter plan';

  @override
  String get planNewStarterPickerCancel => 'Cancel';

  @override
  String planNewStarterCreateFailed(String error) {
    return 'Couldn\'t create that plan: $error';
  }

  @override
  String get planNewReplaceActiveTitle => 'Replace your active plan?';

  @override
  String planNewReplaceActiveNamed(String name) {
    return 'You already have an active plan: \"$name\". Creating a new plan will mark the current one as completed (you can still find it under Manage plans). Continue?';
  }

  @override
  String get planNewReplaceActiveUnnamed =>
      'You already have an active plan. Creating a new plan will mark the current one as completed. Continue?';

  @override
  String get planNewReplaceActiveConfirm => 'Replace plan';

  @override
  String get planNewReplaceActiveKeep => 'Keep current';

  @override
  String get planNewStarterC25k => 'Couch to 5K (beginner walk-run)';

  @override
  String get planNewStarterHalf12 => 'Half Marathon — 12 weeks';

  @override
  String get planNewStarterMarathon16 => 'Marathon — 16 weeks';

  @override
  String get planDetailTimeoutError =>
      'Connection timed out. Check your network and try again.';

  @override
  String get planDetailLoadError =>
      'Couldn\'t load this plan. Tap retry to try again.';

  @override
  String get planDetailNotFound => 'Plan not found.';

  @override
  String get planDetailLongestLongRun => 'Longest long run';

  @override
  String get planDetailPublishTooltip => 'Publish as club template';

  @override
  String planDetailDaysPerWeek(int count) {
    return '$count days/wk';
  }

  @override
  String get planDetailCurrentWeek => 'This week';

  @override
  String get planDetailToday => 'TODAY';

  @override
  String get planDetailCompleted => 'Completed';

  @override
  String planDetailWeek(int number) {
    return 'Week $number';
  }

  @override
  String planDetailDriftOverFlag(int pct) {
    return 'Running $pct% over plan this week — ease back on the easy days so you don\'t dig a fatigue hole.';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return 'Running $pct% under plan this week — the planned volume drives the adaptation.';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      'You missed this week\'s long run — fit it in if you can. It\'s the session that matters most.';

  @override
  String get planDetailMissedLongTaper =>
      'You missed a long run, but you\'re tapering — let it go and stay fresh for race day.';

  @override
  String get planDetailMissedLongRecovery =>
      'You missed a long run — skip the make-up. A step-back week is coming and your body will use the rest.';

  @override
  String get planDetailReplan => 'Re-plan remaining weeks';

  @override
  String get planDetailAdaptiveReplan => 'Adaptive re-plan';

  @override
  String get planDetailAdaptiveOnTrack =>
      'Your recent weeks are on track — no adjustment needed.';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      'You\'ve drifted from plan recently, but there\'s no safe adjustment to make right now.';

  @override
  String get planDetailAdaptiveFitnessHeld =>
      'Held back — you\'re carrying fatigue right now, so adding volume isn\'t advised.';

  @override
  String get planDetailAdaptiveReasonUnder =>
      'under your plan for multiple weeks';

  @override
  String get planDetailAdaptiveReasonOver =>
      'over your plan for multiple weeks';

  @override
  String get planDetailAdaptiveConfidenceHigh => 'high confidence';

  @override
  String get planDetailAdaptiveConfidenceMedium => 'medium confidence';

  @override
  String planDetailAdaptiveBadge(String reason, String confidence) {
    return 'Based on a trend — you\'ve been $reason ($confidence)';
  }

  @override
  String get planDetailReplanOnTrack =>
      'Your plan\'s on track — nothing to adjust.';

  @override
  String planDetailReplanApplied(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Adjusted $n workouts',
      one: 'Adjusted 1 workout',
    );
    return '$_temp0';
  }

  @override
  String get planDetailReplanPreviewTitle => 'Proposed changes';

  @override
  String planDetailReplanMakeUp(String from, String to) {
    return 'Long run $from → $to — make up a missed long run';
  }

  @override
  String planDetailReplanEase(String from, String to) {
    return '$from → $to — ease off after over-running';
  }

  @override
  String get planDetailReplanCancel => 'Cancel';

  @override
  String get planDetailReplanApply => 'Apply changes';

  @override
  String get planDetailDuplicateWeek => 'Duplicate week';

  @override
  String planDetailDuplicateWeekDone(int n) {
    return 'Week $n duplicated';
  }

  @override
  String get planDetailDuplicateConfirmTitle => 'Duplicate this week?';

  @override
  String planDetailDuplicateConfirmMessage(int n) {
    return 'This inserts a copy of week $n and pushes every later week and your race date back by 7 days.';
  }

  @override
  String get planDetailDuplicateConfirm => 'Duplicate';

  @override
  String planDetailBulkFailed(String error) {
    return 'Couldn\'t update the plan: $error';
  }

  @override
  String get planDetailEditTooltip => 'Edit workout';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'Couldn\'t load your clubs — check your network.';

  @override
  String get planDetailPublishLoadClubsFailed => 'Couldn\'t load your clubs.';

  @override
  String get planDetailPublishNoClubs =>
      'You need to own or admin a club before you can publish a template.';

  @override
  String planDetailPublishSuccess(String name) {
    return 'Published \"$name\" as a club template.';
  }

  @override
  String planDetailPublishFailed(String error) {
    return 'Publish failed: $error';
  }

  @override
  String get planDetailPublishPickerTitle => 'Publish to club';

  @override
  String get planDetailPublishPickerBody =>
      'Members of the club will be able to adopt this plan as their own.';

  @override
  String planDetailPublishPickerMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '$count member',
    );
    return '$_temp0';
  }

  @override
  String get planDetailPublishCancel => 'Cancel';

  @override
  String get workoutTimeoutError =>
      'Connection timed out. Check your network and try again.';

  @override
  String get workoutLoadError =>
      'Couldn\'t load this workout. Tap retry to try again.';

  @override
  String get workoutNotFound => 'Workout not found.';

  @override
  String get workoutMetricDistance => 'Distance';

  @override
  String get workoutMetricDuration => 'Duration';

  @override
  String get workoutMetricTargetPace => 'Target pace';

  @override
  String get workoutCompleted => 'Completed';

  @override
  String get workoutUnlink => 'Unlink';

  @override
  String get workoutUnlinkTitle => 'Unlink run';

  @override
  String get workoutUnlinkBody =>
      'Unlink the matched run? The workout will show as not yet done.';

  @override
  String get workoutUnlinkError => 'Couldn\'t unlink the run. Try again.';

  @override
  String get workoutSkipped => 'Skipped';

  @override
  String get workoutSkip => 'Skip this workout';

  @override
  String get workoutUnskip => 'Un-skip';

  @override
  String get workoutSkipError => 'Couldn\'t update the skip. Try again.';

  @override
  String get workoutRelink => 'Re-link';

  @override
  String get workoutRelinkTitle => 'Link a different run';

  @override
  String get workoutRelinkHint =>
      'Pick a run near this workout\'s date to count it as this session. Runs already linked to another workout aren\'t shown.';

  @override
  String get workoutRelinkLoading => 'Finding your runs…';

  @override
  String get workoutRelinkError => 'Couldn\'t load your runs. Try again.';

  @override
  String get workoutRelinkEmpty => 'No eligible runs near this date.';

  @override
  String get workoutRelinkCurrent => 'Current';

  @override
  String get workoutStart => 'Start workout';

  @override
  String get workoutSectionNotes => 'Notes';

  @override
  String get workoutSectionStructure => 'Structure';

  @override
  String get workoutSectionHowTo => 'How to run it';

  @override
  String get workoutStructWarmup => 'Warmup';

  @override
  String get workoutStructRepeats => 'Repeats';

  @override
  String get workoutStructSteady => 'Steady';

  @override
  String get workoutStructCooldown => 'Cooldown';

  @override
  String workoutStructWarmupValue(String distance) {
    return '$distance @ easy';
  }

  @override
  String workoutStructCooldownValue(String distance) {
    return '$distance @ easy';
  }

  @override
  String get workoutAdviceEasy =>
      'Conversational pace. If you can\'t hold a conversation, you\'re running it too fast.';

  @override
  String get workoutAdviceLong =>
      'Stay relaxed. Aim for steady breathing. Drop 10% of the distance if weather is rough or you\'re sore — don\'t skip.';

  @override
  String get workoutAdviceTempo =>
      '\"Comfortably hard\". You should feel like you could hold the pace for about an hour at peak effort, but no longer.';

  @override
  String get workoutAdviceInterval =>
      'Run the reps hard enough that the last one feels like the first. Don\'t pick a pace you can only hold for two or three reps.';

  @override
  String get workoutAdviceMarathonPace =>
      'Lock into goal marathon pace exactly. This is a rehearsal session — no faster, no slower.';

  @override
  String get workoutAdviceWalkRun =>
      'Alternate easy running and walking on the timed intervals. The walk breaks are part of the workout — take them even when you feel fresh.';

  @override
  String get workoutAdviceRace =>
      'Trust the plan. Don\'t chase a PB in the first mile.';

  @override
  String get workoutAdviceRest =>
      'Rest day — if you need to move, walk or stretch.';

  @override
  String get coachTitle => 'Coach';

  @override
  String get coachNewConversation => 'New conversation';

  @override
  String get coachConsentHeadline => 'Before you chat with Coach';

  @override
  String get coachConsentIntro =>
      'To give you grounded advice, Coach forwards a slice of your training data to Anthropic, our AI model provider in the United States. That slice includes:';

  @override
  String get coachConsentBulletProfile =>
      'Your date of birth, gender, and HR zones if set.';

  @override
  String get coachConsentBulletRuns => 'A window of your most recent runs.';

  @override
  String get coachConsentBulletPlan =>
      'The active training plan you have selected.';

  @override
  String get coachConsentBulletMessages =>
      'The chat messages you type in the screen below.';

  @override
  String get coachConsentProcessing =>
      'Anthropic processes the data on Threkir\'s behalf under their data-processing terms; they do not train their models on Threkir customer data by default. Full details — including transfer mechanism, retention, and your withdrawal rights — are in our privacy policy.';

  @override
  String get coachConsentAction =>
      'Tap \"I consent\" to continue. Tap cancel to leave the page with no data sent.';

  @override
  String get coachConsentCancel => 'Cancel';

  @override
  String get coachConsentAccept => 'I consent — start Coach';

  @override
  String get coachConsentSaving => 'Recording consent…';

  @override
  String get coachNoPlanOption => 'No plan (recent runs only)';

  @override
  String coachPlanActive(String name) {
    return '$name · active';
  }

  @override
  String coachPlanDone(String name) {
    return '$name · done';
  }

  @override
  String get coachNewChatTooltip => 'New chat';

  @override
  String get coachHistoryTooltip => 'Chat history';

  @override
  String get coachNewChat => 'New chat';

  @override
  String coachActiveThread(String suffix) {
    return 'Active$suffix';
  }

  @override
  String get coachArchiveTapToView => 'Tap to view · swipe to delete';

  @override
  String get coachContextNoPlan => 'No plan';

  @override
  String coachContextPlanWeeks(String name, int weeks) {
    return '$name · ${weeks}w';
  }

  @override
  String get coachContextNoRuns => 'No runs';

  @override
  String get coachContextLast => 'Last';

  @override
  String get coachContextHr => 'HR';

  @override
  String coachContextWeeklyGoal(String km) {
    return '$km km/wk';
  }

  @override
  String coachArchiveBanner(String label) {
    return 'Viewing archive · $label · read-only';
  }

  @override
  String get coachBackToActive => 'Back to active';

  @override
  String get coachLimitReachedPro => 'Daily limit reached. Come back tomorrow.';

  @override
  String get coachLimitReachedFree =>
      'Daily limit reached. Pro gets a higher cap — upgrade in Settings.';

  @override
  String coachMessagesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages left today',
      one: '$count message left today',
    );
    return '$_temp0';
  }

  @override
  String get coachEmptyPromptPlan =>
      'Ask about today\'s workout, your pace, or how recent runs compare to plan.';

  @override
  String get coachEmptyPromptNoPlan =>
      'Ask about your recent runs, easy-run pacing, or training basics.';

  @override
  String get coachSuggestPlanRest =>
      'Should I run tomorrow or take a rest day?';

  @override
  String get coachSuggestPlanOnTrack => 'Am I on track for my goal time?';

  @override
  String get coachSuggestPlanLongRun =>
      'Why does this week\'s long run matter?';

  @override
  String get coachSuggestPlanToday =>
      'What should I focus on for today\'s workout?';

  @override
  String get coachSuggestNoPlanLastRun => 'How was my last run?';

  @override
  String get coachSuggestNoPlanEasyPace => 'What pace should my easy runs be?';

  @override
  String get coachSuggestNoPlanWeekOff =>
      'I haven\'t run in a week — what should I do?';

  @override
  String get coachSuggestNoPlanTempo => 'What is a tempo run?';

  @override
  String get coachEditCancel => 'Cancel';

  @override
  String get coachEditSaveResend => 'Save & resend';

  @override
  String get coachActionCopy => 'Copy';

  @override
  String get coachActionEdit => 'Edit';

  @override
  String get coachActionRegenerate => 'Regenerate';

  @override
  String get coachActionHelpful => 'Helpful';

  @override
  String get coachActionNotHelpful => 'Not helpful';

  @override
  String get coachComposerHintLimit => 'Daily limit reached';

  @override
  String get coachComposerHint => 'Ask Coach…';

  @override
  String get coachArchiveTitle => 'Start a new conversation?';

  @override
  String get coachArchiveBody =>
      'The current chat moves to history. You can revisit it from the sidebar.';

  @override
  String get coachArchiveCancel => 'Cancel';

  @override
  String get coachArchiveConfirm => 'New chat';

  @override
  String get coachSignInFirst => 'Please sign in first.';

  @override
  String get coachSessionExpired =>
      'Your session expired. Please sign in again.';

  @override
  String coachDailyLimitError(int limit) {
    return 'Daily limit reached ($limit messages). Come back tomorrow!';
  }

  @override
  String coachGenericError(int code) {
    return 'Coach error ($code)';
  }

  @override
  String get coachTransportError =>
      'Could not reach the Coach. Check your connection and try again.';

  @override
  String get coachStreamFailed => 'stream failed';

  @override
  String coachNewConversationFailed(String error) {
    return 'Could not start a new conversation: $error';
  }

  @override
  String coachOpenArchiveFailed(String error) {
    return 'Could not open archive: $error';
  }

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Couldn\'t delete archive: $error';
  }

  @override
  String get coachCopied => 'Copied to clipboard';

  @override
  String get settingsAccountTitle => 'Account';

  @override
  String get settingsAccountBackendNotConfigured => 'Backend not configured';

  @override
  String get settingsAccountSignOutFailed =>
      'Sign out failed — check your connection';

  @override
  String get settingsAccountChangePassword => 'Change password';

  @override
  String get settingsAccountNewPassword => 'New password';

  @override
  String get settingsAccountConfirm => 'Confirm';

  @override
  String get settingsAccountCancel => 'Cancel';

  @override
  String get settingsAccountSave => 'Save';

  @override
  String get settingsAccountPasswordTooShort =>
      'Password must be at least 8 characters';

  @override
  String get settingsAccountPasswordsMismatch => 'Passwords do not match';

  @override
  String get settingsAccountPasswordUpdated => 'Password updated';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Could not update password: $error';
  }

  @override
  String get settingsAccountDeleteTitle => 'Delete account?';

  @override
  String get settingsAccountDeleteBody =>
      'This permanently removes your runs, routes, and profile from the server. Local device data is kept unless you sign in as a new user. This cannot be undone.';

  @override
  String get settingsAccountDeleteChallengeText => 'Type \"DELETE\" to confirm';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return 'Type your email ($email) to confirm';
  }

  @override
  String get settingsAccountDelete => 'Delete';

  @override
  String get settingsAccountDeleteSignInFirst =>
      'Sign in first to delete your account.';

  @override
  String get settingsAccountDeleted => 'Account deleted';

  @override
  String get settingsAccountCoachConsentWithdraw => 'Withdraw AI Coach consent';

  @override
  String get settingsAccountCoachConsentActive =>
      'Stop the Coach from using your training data. You can grant consent again any time.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'AI Coach consent withdrawn.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Couldn\'t withdraw consent: $error';
  }

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'Account deletion failed: $error';
  }

  @override
  String get settingsAccountNoRunsToExport => 'No runs to export.';

  @override
  String get settingsAccountCsvShareText => 'Run app — runs export';

  @override
  String settingsAccountCsvExportFailed(Object error) {
    return 'CSV export failed: $error';
  }

  @override
  String get settingsAccountBackupSignInFirst =>
      'Sign in first to back up your runs.';

  @override
  String get settingsAccountBackupPreparing => 'Preparing backup…';

  @override
  String get settingsAccountBackupShareText => 'Run app backup';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'Backup failed: $error';
  }

  @override
  String get settingsAccountRestoreUnavailable => 'Backup service unavailable.';

  @override
  String get settingsAccountRestoreTitle => 'Restore from backup?';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'You\'re not signed in. Runs will be restored to this device and synced to your account the next time you sign in.';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'This adds or overwrites runs and routes matching IDs in the backup. It will not delete runs or routes that aren\'t in the backup.';

  @override
  String get settingsAccountRestore => 'Restore';

  @override
  String get settingsAccountRestoring => 'Restoring…';

  @override
  String settingsAccountRestoreDone(
    int runs,
    int tracks,
    int routes,
    String warnings,
  ) {
    return 'Restored $runs runs · $tracks tracks · $routes routes$warnings';
  }

  @override
  String settingsAccountRestoreWarningsSuffix(int count) {
    return ' · $count warnings';
  }

  @override
  String settingsAccountRestoreFailed(Object error) {
    return 'Restore failed: $error';
  }

  @override
  String get settingsAccountOfflineMode => 'Offline mode';

  @override
  String get settingsAccountSignedInSync => 'Signed in — runs will sync';

  @override
  String get settingsAccountSignInToSync =>
      'Sign in to sync runs across devices';

  @override
  String get settingsAccountSignOut => 'Sign out';

  @override
  String get settingsAccountSignIn => 'Sign in';

  @override
  String get settingsAccountAvatar => 'Profile photo';

  @override
  String get settingsAccountAvatarHint => 'JPEG, PNG, or WebP, up to 2 MB.';

  @override
  String get settingsAccountAvatarRemove => 'Remove photo';

  @override
  String get settingsAccountAvatarRemoveTitle => 'Remove profile photo?';

  @override
  String get settingsAccountAvatarRemoveConfirm =>
      'This removes your current profile photo. You can upload a new one anytime.';

  @override
  String get settingsAccountAvatarSaved => 'Profile photo updated.';

  @override
  String get settingsAccountAvatarRemoved => 'Profile photo removed.';

  @override
  String get settingsAccountAvatarUnsupported =>
      'Unsupported image — choose a JPEG, PNG, or WebP.';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return 'Couldn\'t update photo: $error';
  }

  @override
  String get settingsAccountViewProfile => 'View profile';

  @override
  String get settingsAccountViewProfileSubtitle =>
      'Your runs, followers, following, notifications';

  @override
  String get settingsAccountGuidedRuns => 'Guided runs';

  @override
  String get settingsAccountGuidedRunsSubtitle =>
      'Coach-voice scripted workouts with TTS cues';

  @override
  String get settingsAccountPrivacyZones => 'Privacy zones';

  @override
  String get settingsAccountPrivacyZonesSubtitle =>
      'Clip start/end of public tracks near home';

  @override
  String get settingsAccountSendErrorReports => 'Send error reports';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Anonymised crash + error data to Sentry (US). Toggle off to withdraw consent. Applies on next launch.';

  @override
  String get settingsAccountErrorReportingEnabled =>
      'Error reporting enabled — restart the app to apply.';

  @override
  String get settingsAccountErrorReportingDisabled =>
      'Error reporting disabled — restart the app to apply.';

  @override
  String get settingsAccountImport => 'Import from another app';

  @override
  String get settingsAccountImportSubtitle => 'Strava, GPX, TCX';

  @override
  String get settingsAccountFullBackup => 'Full backup';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'Every run with its GPS trace, plus routes, profile, and preferences. Restores on web or Android.';

  @override
  String get settingsAccountExportCsv => 'Export runs as CSV';

  @override
  String get settingsAccountExportCsvSubtitle =>
      'date, distance, duration, pace, source — one row per run. Same shape as the web GDPR export.';

  @override
  String get settingsAccountRestoreTile => 'Restore from backup';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      'Pick a previously saved .zip backup.';

  @override
  String get settingsAccountDeleteAccount => 'Delete account';

  @override
  String get settingsAccountDeleteAccountSubtitle =>
      'Permanently removes server data';

  @override
  String get integrationsTitle => 'Integrations';

  @override
  String get integrationsJustNow => 'just now';

  @override
  String integrationsMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String integrationsHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String integrationsDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String integrationsWeeksAgo(int weeks) {
    return '${weeks}w ago';
  }

  @override
  String integrationsCouldNotOpen(Object error) {
    return 'Could not open: $error';
  }

  @override
  String get integrationsStravaBrowserHint =>
      'Complete the Strava sign-in in your browser, then return here and pull to refresh.';

  @override
  String get integrationsStravaCancelled => 'Strava sign-in cancelled.';

  @override
  String integrationsStravaSignInFailed(Object error) {
    return 'Strava sign-in failed: $error';
  }

  @override
  String get integrationsStravaCsrfMismatch =>
      'Strava sign-in rejected: CSRF state mismatch. Please retry.';

  @override
  String integrationsStravaConnectFailed(String error) {
    return 'Strava connect failed: $error';
  }

  @override
  String get integrationsStravaConnected => 'Strava connected.';

  @override
  String integrationsSyncResult(int imported, int skipped) {
    return 'Synced. $imported new, $skipped already present.';
  }

  @override
  String integrationsSyncFailed(Object error) {
    return 'Sync failed: $error';
  }

  @override
  String get integrationsStravaDisconnectTitle => 'Disconnect Strava?';

  @override
  String get integrationsStravaDisconnectBody =>
      'Future activities will stop syncing automatically. Already-imported runs stay in your history.';

  @override
  String get integrationsCancel => 'Cancel';

  @override
  String get integrationsDisconnect => 'Disconnect';

  @override
  String get integrationsStravaDisconnected => 'Strava disconnected.';

  @override
  String integrationsDisconnectFailed(Object error) {
    return 'Disconnect failed: $error';
  }

  @override
  String get integrationsParkrunTitle => 'Import parkrun results';

  @override
  String get integrationsParkrunBody =>
      'Enter your parkrun athlete number (e.g. A123456). We\'ll fetch your finish history and add any new results to your runs list.';

  @override
  String get integrationsParkrunFieldLabel => 'Athlete number';

  @override
  String get integrationsImport => 'Import';

  @override
  String get integrationsParkrunImporting => 'Importing parkrun results…';

  @override
  String integrationsParkrunImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count parkrun results.',
      one: 'Imported $count parkrun result.',
    );
    return '$_temp0';
  }

  @override
  String get integrationsParkrunNoneNew =>
      'No new parkrun results since last import.';

  @override
  String integrationsImportFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get integrationsStravaName => 'Strava';

  @override
  String get integrationsStravaConnectSubtitle =>
      'Connect to auto-sync activities';

  @override
  String get integrationsStravaWaitingFirstSync =>
      'Connected · waiting for first sync';

  @override
  String integrationsStravaLastSync(String time) {
    return 'Connected · last sync $time';
  }

  @override
  String get integrationsSyncNow => 'Sync now';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Import results by athlete number';

  @override
  String get integrationsParkrunRegionNote =>
      'parkrun runs in a limited set of countries and may not have events near you — you can still import results with a parkrun athlete ID.';

  @override
  String get integrationsSignInTitle => 'Sign in to connect services';

  @override
  String get integrationsSignInSubtitle =>
      'Strava + parkrun require an account so synced activities land in your history.';

  @override
  String get integrationsHealthConnectTitle => 'Write runs to Health Connect';

  @override
  String get integrationsHealthConnectSubtitle =>
      'Send each finished run to Health Connect so it appears in Google Fit, Samsung Health, Fitbit and others.';

  @override
  String get integrationsHealthConnectDenied =>
      'Health Connect permission not granted — runs won\'t be written.';

  @override
  String integrationsHrPairFailed(Object error) {
    return 'Pair failed: $error';
  }

  @override
  String get integrationsHrTitle => 'Heart rate monitor';

  @override
  String get integrationsHrChecking => 'Checking…';

  @override
  String integrationsHrPaired(String name) {
    return 'Paired: $name';
  }

  @override
  String get integrationsHrNotPaired => 'No strap paired — tap to scan';

  @override
  String get integrationsHrForget => 'Forget';

  @override
  String get integrationsHrForgetConfirm =>
      'Forget this heart rate monitor? You\'ll need to pair it again to use it during a run.';

  @override
  String get integrationsHrScanTitle => 'Scan for heart rate monitor';

  @override
  String get integrationsHrScanHint =>
      'Wake your strap / chest band. Apps typically take 3–8 seconds.';

  @override
  String get integrationsHrScanEmpty =>
      'No straps found. Make sure it\'s nearby and awake.';

  @override
  String integrationsHrRssi(int rssi) {
    return 'RSSI $rssi dBm';
  }

  @override
  String get integrationsTreadmillTitle => 'Treadmill';

  @override
  String get integrationsTreadmillChecking => 'Checking…';

  @override
  String integrationsTreadmillPaired(String name) {
    return 'Paired: $name';
  }

  @override
  String get integrationsTreadmillNotPaired =>
      'No treadmill paired — tap to scan';

  @override
  String get integrationsTreadmillForget => 'Forget';

  @override
  String get integrationsTreadmillForgetConfirm =>
      'Forget this treadmill? You\'ll need to pair it again to use it during a run.';

  @override
  String get integrationsTreadmillScanTitle => 'Scan for treadmill';

  @override
  String get integrationsTreadmillScanHint =>
      'Make sure the treadmill\'s Bluetooth is on and the belt is awake. Scanning takes 3–8 seconds.';

  @override
  String get integrationsTreadmillScanEmpty =>
      'No treadmills found. Make sure it supports Bluetooth (FTMS) and is nearby.';

  @override
  String integrationsTreadmillPairFailed(Object error) {
    return 'Pair failed: $error';
  }

  @override
  String integrationsTreadmillLiveSpeed(String speed) {
    return '$speed km/h';
  }

  @override
  String get proTitle => 'Pro & support';

  @override
  String proCouldNotOpen(Object error) {
    return 'Could not open: $error';
  }

  @override
  String get proWelcome => 'Welcome to Pro! Pulling your benefits…';

  @override
  String get proPurchaseFailed => 'Purchase failed. Try again later.';

  @override
  String get proRestoreNeedsSignIn =>
      'Restore needs you to be signed in with RevenueCat configured. Manage your subscription on the web upgrade page instead.';

  @override
  String get proRestored => 'Restored your Pro subscription.';

  @override
  String get proRestoreNone =>
      'No active purchases found on this store account.';

  @override
  String get proRestoreFailed => 'Restore failed. Try again later.';

  @override
  String get proRestoreUnavailable => 'Restore unavailable in this build.';

  @override
  String proSubscribeTitle(String price) {
    return 'Subscribe to Pro — $price/month';
  }

  @override
  String get proSubscribeSubtitleConfigured =>
      'Unlimited AI coach + priority processing. Auto-renews monthly until cancelled in Settings → Subscriptions.';

  @override
  String get proSubscribeSubtitleWeb =>
      'Opens the subscription portal in your browser. Auto-renews monthly until cancelled.';

  @override
  String get proRegionalNote =>
      'Billed in US dollars. Availability depends on your country and payment method — some regions can\'t be served by our payment processor.';

  @override
  String get proRestorePurchases => 'Restore purchases';

  @override
  String get proRestorePurchasesSubtitle =>
      'Re-link purchases from a previous install or another device';

  @override
  String get proManageSubscription => 'Manage subscription';

  @override
  String get proManageSubscriptionSubtitle =>
      'Cancel, change plan, or update payment method';

  @override
  String get proSupport => 'Support the app';

  @override
  String get proSupportSubtitle => 'One-off donation in your browser';

  @override
  String get licensesTitle => 'Licenses';

  @override
  String get licensesVersion => 'Version';

  @override
  String get licensesOpenSource => 'Open-source licenses';

  @override
  String get licensesOpenSourceSubtitle =>
      'Third-party packages bundled with this app';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get devicesRenameTitle => 'Rename device';

  @override
  String get devicesCancel => 'Cancel';

  @override
  String get devicesSave => 'Save';

  @override
  String devicesRenameFailed(Object error) {
    return 'Rename failed: $error';
  }

  @override
  String get devicesRemoveTitle => 'Remove device?';

  @override
  String get devicesRemoveBodyCurrent =>
      'This is the device you\'re using. Removing it wipes the per-device preference overrides; the device stays signed in.';

  @override
  String get devicesRemoveBodyOther =>
      'Removes the device entry and any per-device preference overrides. The device stays signed in until it next opens the app.';

  @override
  String get devicesRemove => 'Remove';

  @override
  String devicesRemoveFailed(Object error) {
    return 'Remove failed: $error';
  }

  @override
  String devicesSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get devicesLoadError => 'Could not load devices.';

  @override
  String get devicesEmpty =>
      'No devices yet — they\'re registered the first time a device opens the app while signed in.';

  @override
  String get devicesThisDevice => 'This device';

  @override
  String devicesLastSeen(String time) {
    return 'Last seen $time';
  }

  @override
  String devicesOverrideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overrides',
      one: '$count override',
    );
    return '$_temp0';
  }

  @override
  String get devicesJustNow => 'just now';

  @override
  String devicesMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String devicesHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String devicesDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get devicesRename => 'Rename';

  @override
  String get devicesEditOverrides => 'Edit overrides…';

  @override
  String get devicesEveryKeySet =>
      'Every overridable key is already set; remove one before adding another.';

  @override
  String get devicesOverridesSheetTitle => 'Per-device overrides';

  @override
  String get devicesOverridesSheetDesc =>
      'These keys override the universal settings on this device only.';

  @override
  String get devicesNoOverrides => 'No overrides on this device.';

  @override
  String get devicesAddOverride => 'Add override';

  @override
  String get devicesPickKey => 'Pick a key';

  @override
  String get devicesEnterWholeNumber => 'Enter a whole number.';

  @override
  String get devicesEnterNumber => 'Enter a number (e.g. 0.8).';

  @override
  String get devicesValue => 'Value';

  @override
  String get devicesBack => 'Back';

  @override
  String get devicesAdd => 'Add';

  @override
  String get devicesKeyPreferredUnitLabel => 'Preferred unit';

  @override
  String get devicesKeyPreferredUnitHint => 'Distance unit for all displays.';

  @override
  String get devicesKeyDefaultActivityLabel => 'Default activity type';

  @override
  String get devicesKeyDefaultActivityHint =>
      'Pre-selected activity on the start screen.';

  @override
  String get devicesKeyMapStyleLabel => 'Map style';

  @override
  String get devicesKeyMapStyleHint => 'MapLibre style for the map view.';

  @override
  String get devicesKeyPaceFormatLabel => 'Pace format';

  @override
  String get devicesKeyPaceFormatHint => 'Display format for pace.';

  @override
  String get devicesKeyVoiceFeedbackLabel => 'Voice feedback';

  @override
  String get devicesKeyVoiceFeedbackHint =>
      'Speak pace / distance callouts during a run.';

  @override
  String get devicesKeyVoiceIntervalLabel => 'Voice feedback interval (km)';

  @override
  String get devicesKeyVoiceIntervalHint => 'Distance between spoken callouts.';

  @override
  String get devicesKeyHapticLabel => 'Haptic feedback';

  @override
  String get devicesKeyHapticHint => 'Vibration on lap + pace-zone changes.';

  @override
  String get devicesKeyKeepScreenOnLabel => 'Keep screen on';

  @override
  String get devicesKeyKeepScreenOnHint =>
      'Disable OS auto-dim while recording.';

  @override
  String get gearTitle => 'Gear';

  @override
  String get gearAddGear => 'Add gear';

  @override
  String get gearDeleteTitle => 'Delete gear?';

  @override
  String gearDeleteBody(String name) {
    return 'Delete \"$name\"? Mileage history on past runs will be lost. Retire instead to keep the records.';
  }

  @override
  String get gearCancel => 'Cancel';

  @override
  String get gearDelete => 'Delete';

  @override
  String get gearDeletedOffline =>
      'Deleted locally — will sync when you reconnect.';

  @override
  String gearAttached(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Attached $name to $count runs.',
      one: 'Attached $name to $count run.',
    );
    return '$_temp0';
  }

  @override
  String gearOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Offline — $count edits queued, showing cached gear.',
      one: 'Offline — $count edit queued, showing cached gear.',
    );
    return '$_temp0';
  }

  @override
  String get gearOfflineCached => 'Offline — showing cached gear.';

  @override
  String get gearShoes => 'Shoes';

  @override
  String get gearBikes => 'Bikes';

  @override
  String get gearRetired => 'RETIRED';

  @override
  String get gearEmptyShoes => 'No shoes yet';

  @override
  String get gearEmptyBikes => 'No bikes yet';

  @override
  String get gearEmptySubtitle =>
      'Add a pair to track mileage and get retirement reminders.';

  @override
  String gearRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return '$_temp0';
  }

  @override
  String get gearWearDue => 'Replace soon';

  @override
  String get gearWearWorn => 'Past replacement distance';

  @override
  String get gearRetire => 'Retire';

  @override
  String get gearRestore => 'Restore';

  @override
  String get gearRotationsTitle => 'Rotations';

  @override
  String get gearRotationsHint =>
      'Group the gear you cycle through — a \"Daily trainers\" set, a \"Race day\" set. A rotation is just a named grouping; it doesn\'t change which pair auto-tags new runs.';

  @override
  String get gearRotationsEmpty =>
      'No rotations yet. Create one to group a set of shoes or bikes.';

  @override
  String get gearRotationName => 'Rotation name';

  @override
  String get gearRotationNew => 'New rotation';

  @override
  String get gearRotationCreate => 'Create';

  @override
  String get gearRotationRename => 'Rename';

  @override
  String get gearRotationManage => 'Edit gear';

  @override
  String gearRotationManageTitle(String name) {
    return 'Gear in \"$name\"';
  }

  @override
  String get gearRotationDeleteTitle => 'Delete rotation?';

  @override
  String gearRotationDeleteBody(String name) {
    return 'Delete the \"$name\" rotation? Your gear isn\'t affected — only the grouping is removed.';
  }

  @override
  String gearRotationMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get gearRotationNoGear =>
      'Add some gear first, then you can group it into a rotation.';

  @override
  String gearRotationSaveFailed(Object error) {
    return 'Couldn\'t save rotation: $error';
  }

  @override
  String get gearRotationDone => 'Done';

  @override
  String get privacyZonesTitle => 'Privacy zones';

  @override
  String get privacyZonesSaved => 'Privacy zones saved.';

  @override
  String privacyZonesSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return 'Location unavailable: $error';
  }

  @override
  String get privacyZonesSave => 'Save';

  @override
  String get privacyZonesLocateMe => 'Locate me';

  @override
  String get privacyZonesHint =>
      'Tap the map to add a zone. Tracks on public surfaces have their start and end clipped past the zone radius.';

  @override
  String get privacyZonesSearchHint => 'Search places…';

  @override
  String get privacyZonesRadius => 'Radius';

  @override
  String privacyZonesRadiusMeters(int meters) {
    return '$meters m';
  }

  @override
  String privacyZonesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zones — tap a marker to remove.',
      one: '$count zone — tap a marker to remove.',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'Clear all';

  @override
  String get privacyZonesRemoveTitle => 'Remove privacy zone?';

  @override
  String get privacyZonesRemoveBody =>
      'This zone hides your tracks near here on public shares. Removing it re-exposes this area.';

  @override
  String get privacyZonesRemoveSemantics => 'Remove privacy zone';

  @override
  String get privacyZonesClearAllTitle => 'Clear all privacy zones?';

  @override
  String get privacyZonesClearAllBody =>
      'This removes every zone, re-exposing all of these areas on public shares.';

  @override
  String get prefsTitle => 'Preferences';

  @override
  String get prefsUnitMetric => 'km, m';

  @override
  String get prefsUnitImperial => 'mi, ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · synced to your other devices';
  }

  @override
  String get prefsClear => 'Clear';

  @override
  String get prefsCancel => 'Cancel';

  @override
  String get prefsSave => 'Save';

  @override
  String get prefsSplitInterval => 'Split interval';

  @override
  String get prefsSplitIntervalDefault => 'Default';

  @override
  String get prefsSplitIntervalDefaultSubtitle =>
      'Default (1 km for running, 5 km for cycling)';

  @override
  String get prefsLivePaceAlert => 'Live pace alert';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 'sec';

  @override
  String get prefsLivePaceAlertOff =>
      'Off — set a pace to get spoken alerts during a run';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — spoken alert during a run when 30s+ off';
  }

  @override
  String get prefsActivityRun => 'Run';

  @override
  String get prefsActivityWalk => 'Walk';

  @override
  String get prefsActivityHike => 'Hike';

  @override
  String get prefsActivityCycle => 'Cycle';

  @override
  String get prefsPaceFormat => 'Pace format';

  @override
  String get prefsPaceFormatMinPerKm => 'Minutes per km';

  @override
  String get prefsPaceFormatMinPerMi => 'Minutes per mile';

  @override
  String get prefsPaceFormatKph => 'km/h';

  @override
  String get prefsPaceFormatMph => 'mph';

  @override
  String get prefsWeightUnit => 'Weight unit';

  @override
  String get prefsWeightUnitKg => 'Kilograms (kg)';

  @override
  String get prefsWeightUnitLbs => 'Pounds (lbs)';

  @override
  String get prefsNotSet => 'Not set';

  @override
  String prefsHrZonesSummary(String zones) {
    return '$zones bpm';
  }

  @override
  String prefsWeeklyGoalSummary(String distance, String unit) {
    return '$distance $unit / week';
  }

  @override
  String get prefsMapStyle => 'Map style';

  @override
  String get prefsMapStyleStreets => 'Streets';

  @override
  String get prefsMapStyleSatellite => 'Satellite';

  @override
  String get prefsMapStyleOutdoors => 'Outdoors';

  @override
  String get prefsMapStyleDark => 'Dark';

  @override
  String get prefsDefaultRunVisibility => 'Default run visibility';

  @override
  String get prefsCoachPersonality => 'Coach personality';

  @override
  String get prefsCoachSupportive => 'Supportive';

  @override
  String get prefsCoachDrillSergeant => 'Drill sergeant';

  @override
  String get prefsCoachAnalytical => 'Analytical';

  @override
  String get prefsSectionNotifications => 'Notifications';

  @override
  String get prefsEmailNotifications => 'Email notifications';

  @override
  String get prefsEmailNotifAll => 'Everything';

  @override
  String get prefsEmailNotifImportant => 'Important only';

  @override
  String get prefsEmailNotifOff => 'Off';

  @override
  String get prefsPushNotifications => 'Push notifications';

  @override
  String get prefsPushNotifAll => 'Everything';

  @override
  String get prefsPushNotifImportant => 'Important only';

  @override
  String get prefsPushNotifOff => 'Off';

  @override
  String get prefsEmailWeeklyDigest => 'Weekly digest email';

  @override
  String get prefsEmailWeeklyDigestHint =>
      'Opt in to a weekly summary of your training and community highlights. Off by default; separate from your notification emails.';

  @override
  String get prefsEmailLifecycleDrip => 'Tips & encouragement email';

  @override
  String get prefsEmailLifecycleDripHint =>
      'Opt in to occasional onboarding, re-engagement, and streak nudges. Off by default; separate from your weekly digest and notification emails.';

  @override
  String get prefsWeekStart => 'Week starts on';

  @override
  String get prefsWeekStartMonday => 'Monday';

  @override
  String get prefsWeekStartSunday => 'Sunday';

  @override
  String get prefsDefaultActivity => 'Default activity';

  @override
  String get prefsDateOfBirth => 'Date of birth';

  @override
  String get prefsRestingHr => 'Resting heart rate';

  @override
  String get prefsMaxHr => 'Max heart rate';

  @override
  String get prefsMaxHrNotSet => 'Not set — falls back to 208 − 0.7 × age';

  @override
  String prefsHrBpm(int bpm) {
    return '$bpm bpm';
  }

  @override
  String get prefsSectionFueling => 'Race fueling';

  @override
  String get prefsCarbsPerHour => 'Carbs per hour';

  @override
  String prefsCarbsPerHourValue(int grams) {
    return '$grams g/h';
  }

  @override
  String get prefsFluidPerHour => 'Fluid per hour';

  @override
  String prefsFluidPerHourValue(int ml) {
    return '$ml ml/h';
  }

  @override
  String get prefsHrZones => 'Heart-rate zones';

  @override
  String get prefsHrZonesDialogTitle => 'Heart-rate zones (upper bounds, bpm)';

  @override
  String get prefsWeeklyGoal => 'Weekly mileage goal';

  @override
  String get prefsSectionActivityRecording => 'Activity & recording';

  @override
  String get prefsSectionTrainingDemographics => 'Training & demographics';

  @override
  String get prefsSectionPrivacySharing => 'Privacy & sharing';

  @override
  String get prefsSectionAiCoach => 'AI coach';

  @override
  String get prefsSignInToEdit =>
      'Sign in to edit profile-level settings that sync across devices.';

  @override
  String get prefsUseMiles => 'Use miles';

  @override
  String get prefsDarkMode => 'Dark mode';

  @override
  String get prefsAudioCues => 'Audio cues';

  @override
  String get prefsAudioCuesSubtitle => 'Spoken split announcements';

  @override
  String get prefsMinimalVoiceCues => 'Minimal voice cues';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Skip the chatty mid-rep and pace-drift nudges';

  @override
  String get prefsKeepScreenOn => 'Keep screen on';

  @override
  String get prefsKeepScreenOnSubtitle => 'Hold a wakelock during a run';

  @override
  String get prefsAdvancedGps => 'Advanced GPS';

  @override
  String get prefsAdvancedGpsSubtitle =>
      'Higher accuracy, finer track detail, more battery usage';

  @override
  String get prefsShowRawTrack => 'Show raw GPS track';

  @override
  String get prefsShowRawTrackSubtitle =>
      'Draw the unsnapped recorded line on the run map, even when a cleaned-up matched track exists';

  @override
  String get prefsDefaultRunPrivacy => 'Default run privacy';

  @override
  String get prefsStravaAutoShare => 'Strava auto-share';

  @override
  String get prefsStravaAutoShareSubtitle =>
      'Auto-push every new run to Strava. Requires a connected Strava integration once that lands.';

  @override
  String get prefsDiscoverable => 'Show me in name search';

  @override
  String get prefsDiscoverableSubtitle =>
      'When off, your account won\'t appear when other runners search by display name. Your public runs and profile remain reachable to anyone with the URL.';

  @override
  String get dashboardCoachTooltip => 'Coach';

  @override
  String get dashboardFeedTooltip => 'Activity feed';

  @override
  String get dashboardRecapTooltip => 'Year in running';

  @override
  String get dashboardProfileTooltip => 'My profile';

  @override
  String get dashboardWelcomeTitle => 'Welcome!';

  @override
  String get dashboardWelcomeBody =>
      'Your dashboard fills in once you record a run, set a goal, or import your history.';

  @override
  String get dashboardSetGoal => 'Set a goal';

  @override
  String get dashboardImportRuns => 'Import runs';

  @override
  String get dashboardPeriodWeek => 'Week';

  @override
  String get dashboardPeriodMonth => 'Month';

  @override
  String get dashboardPeriodAllTime => 'All time';

  @override
  String get dashboardSectionStreak => 'Streak';

  @override
  String get dashboardWeekStripTitle => 'This Week';

  @override
  String dashboardWeekStripCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activities',
      one: '$count activity',
    );
    return '$_temp0';
  }

  @override
  String dashboardWeekStripDayAria(String dow, String dist) {
    return '$dow: $dist';
  }

  @override
  String dashboardWeekStripDayRestAria(String dow) {
    return '$dow: rest day';
  }

  @override
  String get dashboardSectionLast20Weeks => 'Last 20 Weeks';

  @override
  String get dashboardSectionRecentLifts => 'Recent lifts';

  @override
  String get dashboardViewAllGym => 'View all';

  @override
  String get dashboardSectionPersonalBests => 'Personal Bests';

  @override
  String get dashboardLongestRun => 'Longest run';

  @override
  String dashboardFastestDistance(String distance) {
    return 'Fastest $distance';
  }

  @override
  String get dashboardGoals => 'Goals';

  @override
  String get dashboardAdd => 'Add';

  @override
  String get dashboardGoalWeekly => 'WEEKLY';

  @override
  String get dashboardGoalMonthly => 'MONTHLY';

  @override
  String dashboardGoalTitleFallback(String period) {
    return '$period GOAL';
  }

  @override
  String get dashboardSetWeeklyGoalA11y => 'Set a weekly running goal';

  @override
  String get dashboardSetFirstGoal => 'Set your first goal';

  @override
  String get dashboardSetFirstGoalBody =>
      'Track distance, time, pace, or number of runs each week or month.';

  @override
  String get dashboardGoalTapToEdit => 'tap to edit';

  @override
  String get dashboardGoalComplete => 'Complete.';

  @override
  String get dashboardGoalInProgress => 'In progress.';

  @override
  String dashboardGoalA11y(String period, String title, String status) {
    return '$period goal — $title $status';
  }

  @override
  String dashboardRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return '$_temp0';
  }

  @override
  String dashboardVert(String value) {
    return '$value vert';
  }

  @override
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  ) {
    return '$label summary, $distance across $runs$elevation';
  }

  @override
  String dashboardElevationGainSuffix(String value) {
    return ', $value elevation gain';
  }

  @override
  String get dashboardStreakCurrent => 'Current';

  @override
  String get dashboardStreakHistory => 'History';

  @override
  String get dashboardStreakDayUnit => 'day';

  @override
  String get dashboardStreakDaysUnit => 'days';

  @override
  String dashboardStreakBest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return 'best $_temp0';
  }

  @override
  String get dashboardStreakAllTimeBest => 'all-time best';

  @override
  String get dashboardStreakRestart => 'run today to restart it';

  @override
  String get dashboardStreakStart => 'run today to start one';

  @override
  String get dashboardHeatmapLess => 'Less';

  @override
  String get dashboardHeatmapMore => 'More';

  @override
  String get dashboardHeatmapTapHint => 'Tap a week for its summary';

  @override
  String get periodWeeklySummary => 'Weekly Summary';

  @override
  String get periodMonthlySummary => 'Monthly Summary';

  @override
  String get periodAllTimeSummary => 'All-Time Summary';

  @override
  String get periodShareTooltip => 'Share';

  @override
  String get periodPreviousTooltip => 'Previous';

  @override
  String get periodNextTooltip => 'Next';

  @override
  String get periodSwitchToWeekly => 'Tap to switch to weekly';

  @override
  String get periodSwitchToMonthly => 'Tap to switch to monthly';

  @override
  String get periodSwitchToAllTime => 'Tap to switch to all-time';

  @override
  String get periodStatDistance => 'Distance';

  @override
  String get periodStatRuns => 'Runs';

  @override
  String get periodStatTime => 'Time';

  @override
  String get periodStatAvgPace => 'Avg pace';

  @override
  String get periodEmptyWeek => 'No runs this week';

  @override
  String get periodEmptyMonth => 'No runs this month';

  @override
  String get periodShareSummary => 'Share summary';

  @override
  String get periodShareText => 'Text';

  @override
  String get periodShareImage => 'Image';

  @override
  String get periodShareImageFailed => 'Could not create share image';

  @override
  String get periodShareCardTagline => 'BETTER RUNNER';

  @override
  String get periodShareStatDistance => 'DISTANCE';

  @override
  String get periodShareStatRuns => 'RUNS';

  @override
  String get periodShareStatTime => 'TIME';

  @override
  String get periodShareStatAvgPace => 'AVG PACE';

  @override
  String get trainingLoadTitle => 'Fitness, Fatigue & Form';

  @override
  String trainingLoadSubtitleHr(int days) {
    return 'Heart-rate TRIMP over the last $days days.';
  }

  @override
  String get trainingLoadSubtitleVolume =>
      'Volume-based — set resting + max HR in preferences and record with a strap to upgrade to TRIMP.';

  @override
  String get trainingLoadEmpty =>
      'Record a few runs to see your fitness trend.';

  @override
  String get trainingLoadLegendFitness => 'Fitness';

  @override
  String get trainingLoadLegendFatigue => 'Fatigue';

  @override
  String get trainingLoadLegendForm => 'Form';

  @override
  String trainingLoadLegendEntry(String label, int value) {
    return '$label · $value';
  }

  @override
  String get trainingLoadReadingLoaded =>
      'Loaded up — push through and recover when you\'re ready.';

  @override
  String get trainingLoadReadingTapered =>
      'Tapered — a hard session won\'t break you.';

  @override
  String get trainingLoadReadingBalanced =>
      'Balanced — easy day or hard day, your call.';

  @override
  String get trainingLoadIncludesLifts =>
      'Gym sessions included — lifts add to fatigue too.';

  @override
  String get intensityTitle => 'TRAINING INTENSITY';

  @override
  String intensityWindow(int days) {
    return 'last $days days';
  }

  @override
  String intensityBasedOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count HR-tracked runs',
      one: '$count HR-tracked run',
    );
    return 'Based on $_temp0';
  }

  @override
  String get mileageTitle => 'MILEAGE';

  @override
  String get mileageWeek => 'Week';

  @override
  String get mileageMonth => 'Month';

  @override
  String get mileageYear => 'Year';

  @override
  String get mileageThisWeek => 'this week';

  @override
  String get mileageThisMonth => 'this month';

  @override
  String get mileageThisYear => 'this year';

  @override
  String get fitnessTitle => 'Fitness';

  @override
  String get fitnessStatVo2Max => 'VO₂ max';

  @override
  String get fitnessStatVo2MaxTooltip =>
      'Your aerobic engine: how much oxygen your body can use per minute. Higher is fitter.';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'Daniels\' running-fitness score from your best recent race effort. Drives your training paces.';

  @override
  String get fitnessStatRuns => 'Runs';

  @override
  String get fitnessStatRunsTooltip =>
      'Recent runs long enough to count toward your fitness estimate.';

  @override
  String get fitnessStatCtl => 'Fitness (CTL)';

  @override
  String get fitnessStatCtlTooltip =>
      'Your rolling 42-day training load. Builds slowly; this is your endurance base.';

  @override
  String get fitnessStatAtl => 'Fatigue (ATL)';

  @override
  String get fitnessStatAtlTooltip =>
      'Your last 7 days of load. Rises fast after hard sessions and drops with rest.';

  @override
  String get fitnessStatTsb => 'Form (TSB)';

  @override
  String get fitnessStatTsbTooltip =>
      'Fitness minus fatigue. Positive = fresh and race-ready; negative = carrying fatigue.';

  @override
  String get runSocialActivity => 'Activity';

  @override
  String get runSocialNoComments => 'No comments yet.';

  @override
  String get runSocialReplyHint => 'Write a reply…';

  @override
  String get runSocialCommentHint => 'Add a comment…';

  @override
  String get runSocialRunnerFallback => 'Runner';

  @override
  String get runSocialReply => 'Reply';

  @override
  String get runSocialDelete => 'Delete';

  @override
  String get runSocialDeleteCommentTitle => 'Delete this comment?';

  @override
  String get runSocialDeleteCommentMessage =>
      'This comment will be permanently removed. This can\'t be undone.';

  @override
  String get runSocialPost => 'Post';

  @override
  String get runSocialCancel => 'Cancel';

  @override
  String get kudosGiveLabel => 'Give kudos';

  @override
  String get kudosRemoveLabel => 'Remove kudos';

  @override
  String get kudosViewCommentsLabel => 'View comments';

  @override
  String runSocialKudosError(String error) {
    return 'Could not update kudos: $error';
  }

  @override
  String runSocialPostError(String error) {
    return 'Failed to post: $error';
  }

  @override
  String runSocialDeleteError(String error) {
    return 'Failed to delete: $error';
  }

  @override
  String get runPhotosLoading => 'Loading photos…';

  @override
  String get runPhotosTitle => 'Photos';

  @override
  String get runPhotosAdd => 'Add photo';

  @override
  String get runPhotosCaptionPendingHint => 'Caption (optional, 280 chars)';

  @override
  String get runPhotosCaptionHint => 'Caption…';

  @override
  String get runPhotosCancel => 'Cancel';

  @override
  String get runPhotosSave => 'Save';

  @override
  String get runPhotosUpload => 'Upload';

  @override
  String get runPhotosUploading => 'Uploading…';

  @override
  String get runPhotosEditCaption => 'Edit caption';

  @override
  String get runPhotosDeleteTooltip => 'Delete photo';

  @override
  String get runPhotosDeleteTitle => 'Delete photo?';

  @override
  String get runPhotosDeleteBody =>
      'This removes the photo from the run permanently.';

  @override
  String get runPhotosDeleteConfirm => 'Delete';

  @override
  String get runPhotosPermissionDenied =>
      'Photo access is needed to add a photo. You can allow it in Settings.';

  @override
  String get runPhotosOpenSettings => 'Open settings';

  @override
  String get runPhotosPickerFailed =>
      'Could not open the photo picker. Please try again.';

  @override
  String runPhotosUploadError(String error) {
    return 'Upload failed: $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return 'Delete failed: $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'Could not update caption: $error';
  }

  @override
  String get routePhotosLoading => 'Loading photos…';

  @override
  String get routePhotosTitle => 'Photos';

  @override
  String get routePhotosAdd => 'Add photo';

  @override
  String get routePhotosCaptionPendingHint => 'Caption (optional, 280 chars)';

  @override
  String get routePhotosCaptionHint => 'Caption…';

  @override
  String get routePhotosCancel => 'Cancel';

  @override
  String get routePhotosSave => 'Save';

  @override
  String get routePhotosUpload => 'Upload';

  @override
  String get routePhotosUploading => 'Uploading…';

  @override
  String get routePhotosEditCaption => 'Edit caption';

  @override
  String get routePhotosDeleteTooltip => 'Delete photo';

  @override
  String get routePhotosDeleteTitle => 'Delete photo?';

  @override
  String get routePhotosDeleteBody =>
      'This removes the photo from the route permanently.';

  @override
  String get routePhotosDeleteConfirm => 'Delete';

  @override
  String routePhotosPickerError(String error) {
    return 'Could not open picker: $error';
  }

  @override
  String routePhotosUploadError(String error) {
    return 'Upload failed: $error';
  }

  @override
  String routePhotosDeleteError(String error) {
    return 'Delete failed: $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'Could not update caption: $error';
  }

  @override
  String get clubPhotosLoading => 'Loading photos…';

  @override
  String get clubPhotosTitle => 'Photos';

  @override
  String get clubPhotosAdd => 'Add photo';

  @override
  String get clubPhotosEmpty => 'No photos in this club yet.';

  @override
  String get clubPhotosCaptionPendingHint => 'Caption (optional, 280 chars)';

  @override
  String get clubPhotosCaptionHint => 'Caption…';

  @override
  String get clubPhotosCancel => 'Cancel';

  @override
  String get clubPhotosSave => 'Save';

  @override
  String get clubPhotosUpload => 'Upload';

  @override
  String get clubPhotosUploading => 'Uploading…';

  @override
  String get clubPhotosEditCaption => 'Edit caption';

  @override
  String get clubPhotosDeleteTooltip => 'Delete photo';

  @override
  String get clubPhotosDeleteTitle => 'Delete photo?';

  @override
  String get clubPhotosDeleteBody =>
      'This removes the photo from the club permanently.';

  @override
  String get clubPhotosDeleteConfirm => 'Delete';

  @override
  String clubPhotosPickerError(String error) {
    return 'Could not open picker: $error';
  }

  @override
  String clubPhotosUploadError(String error) {
    return 'Upload failed: $error';
  }

  @override
  String clubPhotosDeleteError(String error) {
    return 'Delete failed: $error';
  }

  @override
  String clubPhotosCaptionError(String error) {
    return 'Could not update caption: $error';
  }

  @override
  String get runSegEffortsChecking => 'Checking segments…';

  @override
  String get runSegEffortsNoRoute =>
      'Segments are matched per route — link this run to a saved route to compete on its leaderboards.';

  @override
  String get runSegEffortsEmpty => 'No segment efforts on this run.';

  @override
  String get workoutReviewTitle => 'Workout';

  @override
  String get workoutReviewColStep => 'Step';

  @override
  String get workoutReviewColPlan => 'Plan';

  @override
  String get workoutReviewColActual => 'Actual';

  @override
  String get workoutReviewColPace => 'Pace';

  @override
  String get workoutReviewColDelta => 'Δ';

  @override
  String get workoutReviewSkip => 'skip';

  @override
  String get workoutReviewLabelWarmup => 'Warmup';

  @override
  String get workoutReviewLabelCooldown => 'Cooldown';

  @override
  String get workoutReviewLabelSteady => 'Steady';

  @override
  String get workoutReviewLabelRep => 'Rep';

  @override
  String workoutReviewLabelRepN(int index, int total) {
    return 'Rep $index/$total';
  }

  @override
  String get workoutReviewLabelRecovery => 'Recovery';

  @override
  String workoutReviewLabelRecoveryN(int index, int total) {
    return 'Recovery $index/$total';
  }

  @override
  String get workoutReviewLabelWalk => 'Walk';

  @override
  String workoutReviewLabelWalkN(int index, int total) {
    return 'Walk $index/$total';
  }

  @override
  String get segmentsPanelTitle => 'Segments';

  @override
  String get segmentsPanelNew => 'New segment';

  @override
  String get segmentsPanelCancel => 'Cancel';

  @override
  String get segmentsPanelLoading => 'Loading segments…';

  @override
  String get segmentsPanelEmpty => 'No segments on this route yet.';

  @override
  String get segmentsPanelNameLabel => 'Name';

  @override
  String get segmentsPanelNameHint => 'Climb of doom';

  @override
  String get segmentsPanelStartLabel => 'Start (m)';

  @override
  String get segmentsPanelEndLabel => 'End (m)';

  @override
  String segmentsPanelRouteHint(int metres) {
    return 'route is $metres m';
  }

  @override
  String get segmentsPanelCreate => 'Create';

  @override
  String get segmentsPanelDeleteTooltip => 'Delete segment';

  @override
  String get segmentsPanelDeleteTitle => 'Delete segment?';

  @override
  String segmentsPanelDeleteBody(String name) {
    return '“$name” will be removed.';
  }

  @override
  String get segmentsPanelDeleteConfirm => 'Delete';

  @override
  String get segmentsPanelErrEndAfterStart => 'End must be greater than start';

  @override
  String get segmentsPanelErrMinLength => 'Segment must be at least 100 m';

  @override
  String segmentsPanelCreateError(String error) {
    return 'Could not create segment: $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get segmentsPanelAllGenders => 'All genders';

  @override
  String get segmentsPanelGenderMen => 'Men';

  @override
  String get segmentsPanelGenderWomen => 'Women';

  @override
  String get segmentsPanelGenderNonbinary => 'Nonbinary';

  @override
  String get segmentsPanelAllAges => 'All ages';

  @override
  String get segmentsPanelResetFilters => 'Reset';

  @override
  String get segmentsPanelLeaderboardLoading => 'Loading…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'No efforts match this filter — try widening it.';

  @override
  String get segmentsPanelLeaderboardEmpty =>
      'No efforts yet — be the first to run this segment.';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'You hold this crown — $label.';
  }

  @override
  String get segmentsPanelRunnerFallback => 'Runner';

  @override
  String get goalEditorTitleNew => 'New goal';

  @override
  String get goalEditorTitleEdit => 'Edit goal';

  @override
  String get goalEditorNameLabel => 'Name (optional)';

  @override
  String get goalEditorNameHint => 'e.g. Base miles';

  @override
  String get goalEditorPeriod => 'Period';

  @override
  String get goalEditorThisWeek => 'This week';

  @override
  String get goalEditorThisMonth => 'This month';

  @override
  String get goalEditorTargets => 'Targets';

  @override
  String get goalEditorTargetsHelp =>
      'Set any combination. Blank fields are ignored.';

  @override
  String get goalEditorTargetDistance => 'Distance';

  @override
  String get goalEditorTargetTime => 'Time';

  @override
  String get goalEditorTargetPace => 'Avg pace';

  @override
  String get goalEditorTargetRuns => 'Runs';

  @override
  String get goalEditorSuffixMin => 'min';

  @override
  String get goalEditorSuffixRuns => 'runs';

  @override
  String get goalEditorDelete => 'Delete';

  @override
  String get goalEditorDeleteTitle => 'Delete this goal?';

  @override
  String get goalEditorDeleteMessage =>
      'This goal and its progress tracking will be removed. You can create a new one anytime.';

  @override
  String get goalEditorCancel => 'Cancel';

  @override
  String get goalEditorSave => 'Save';

  @override
  String goalEditorSaveFailed(String error) {
    return 'Couldn\'t save the goal: $error';
  }

  @override
  String get goalEditorErrDistance => 'Distance: enter a positive number';

  @override
  String get goalEditorErrTime => 'Time: enter a positive number of minutes';

  @override
  String get goalEditorErrPace => 'Pace: use mm:ss (e.g. 5:00)';

  @override
  String get goalEditorErrRuns => 'Runs: enter a positive whole number';

  @override
  String get goalEditorErrNoTarget => 'Set at least one target';

  @override
  String get goalEditorSavedAnnounce => 'Goal saved';

  @override
  String get goalEditorDeletedAnnounce => 'Goal deleted';

  @override
  String get eventFormTitle => 'New event';

  @override
  String get eventFormTitleLabel => 'Title';

  @override
  String get eventFormStartsAt => 'Starts at';

  @override
  String get eventFormDescriptionLabel => 'Description (optional)';

  @override
  String get eventFormMeetLabel => 'Meeting point (optional)';

  @override
  String get eventFormMeetHint => 'Trailhead car park';

  @override
  String get eventFormDistanceLabel => 'Distance (km)';

  @override
  String get eventFormDurationLabel => 'Duration (min)';

  @override
  String get eventFormRecurrence => 'Recurrence';

  @override
  String get eventFormRecurOneOff => 'One-off';

  @override
  String get eventFormRecurWeekly => 'Weekly';

  @override
  String get eventFormRecurBiweekly => 'Bi-weekly';

  @override
  String get eventFormRecurMonthly => 'Monthly';

  @override
  String get eventFormCancel => 'Cancel';

  @override
  String get eventFormCreate => 'Create event';

  @override
  String get eventEditorCategory => 'Event type';

  @override
  String get eventEditorCatRun => 'Group run';

  @override
  String get eventEditorCatCycle => 'Cycle';

  @override
  String get eventEditorCatClass => 'Class';

  @override
  String get eventEditorCatSocial => 'Social';

  @override
  String get eventEditorCategoryHint =>
      'Pick the kind of event — a class or social meetup skips route, distance, pace and race results.';

  @override
  String get eventEditorMembersOnlyToggle => 'Members only';

  @override
  String get eventEditorMembersOnlyHint =>
      'Only club members can see this event, and it won\'t appear in public discovery.';

  @override
  String get eventEditorDiscipline => 'Discipline';

  @override
  String get eventEditorDisciplinePlaceholder =>
      'e.g. Vinyasa yoga, Pilates, mobility';

  @override
  String get clubFormTitle => 'New club';

  @override
  String get clubFormNameLabel => 'Name';

  @override
  String get clubFormDescriptionLabel => 'Description (optional)';

  @override
  String get clubFormLocationLabel => 'Location (optional)';

  @override
  String get clubFormLocationHint => 'Edinburgh, UK';

  @override
  String get clubFormPublic => 'Public';

  @override
  String get clubFormPrivate => 'Private';

  @override
  String get clubFormJoinPolicy => 'Join policy';

  @override
  String get clubFormJoinOpen => 'Open — anyone joins';

  @override
  String get clubFormJoinRequest => 'Request — admins approve';

  @override
  String get clubFormJoinInvite => 'Invite only';

  @override
  String get clubFormCancel => 'Cancel';

  @override
  String get clubFormCreate => 'Create';

  @override
  String get clubFormErrSlug => 'Name needs at least one letter or digit.';

  @override
  String get clubFormErrUnreachable =>
      'Can\'t reach the server right now. Check your connection or sign in, then try again.';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonHarassment => 'Harassment or abuse';

  @override
  String get reportReasonInappropriate => 'Inappropriate content';

  @override
  String get reportReasonImpersonation => 'Impersonation';

  @override
  String get reportReasonOther => 'Other';

  @override
  String get reportSuccess =>
      'Report submitted — thanks for flagging this for review.';

  @override
  String get reportTitleUser => 'Report user';

  @override
  String get reportTitleClub => 'Report club';

  @override
  String get reportTitleRoute => 'Report route';

  @override
  String get reportTitlePost => 'Report post';

  @override
  String get reportTitleRun => 'Report run';

  @override
  String get reportTitleContent => 'Report content';

  @override
  String get reportDisclaimer =>
      'Your report goes to a moderator. False reports are reviewed too — please only flag content that violates our community guidelines.';

  @override
  String get reportReason => 'Reason';

  @override
  String get reportNotesLabel => 'Notes (optional)';

  @override
  String get reportCancel => 'Cancel';

  @override
  String get reportSubmit => 'Submit report';

  @override
  String get reportErrDuplicate =>
      'You already have a pending report against this content.';

  @override
  String gearBackfillTitle(String gear) {
    return 'Attach past runs to $gear?';
  }

  @override
  String gearBackfillBody(int count, String activity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $activity activities',
      one: '$count $activity activity',
    );
    return 'We found $_temp0 after you bought them. Uncheck any you weren\'t wearing them for.';
  }

  @override
  String get gearBackfillActivityCycling => 'cycling';

  @override
  String get gearBackfillActivityRunning => 'running';

  @override
  String get gearBackfillSelectNone => 'Select none';

  @override
  String get gearBackfillSelectAll => 'Select all';

  @override
  String gearBackfillSelectedCount(int selected, int total) {
    return '$selected of $total';
  }

  @override
  String get gearBackfillSkip => 'Skip';

  @override
  String get gearBackfillAttaching => 'Attaching…';

  @override
  String gearBackfillAttach(int count) {
    return 'Attach $count';
  }

  @override
  String gearBackfillAttachError(String error) {
    return 'Attach failed: $error';
  }

  @override
  String get workoutEditTitle => 'Edit workout';

  @override
  String get workoutEditKindLabel => 'Kind';

  @override
  String get workoutEditDistanceLabel => 'Target distance (km)';

  @override
  String get workoutEditDistanceHint => 'e.g. 8.0';

  @override
  String get workoutEditPaceLabel => 'Target pace (mm:ss /km)';

  @override
  String get workoutEditPaceHint => 'e.g. 5:30';

  @override
  String get workoutEditNotesLabel => 'Notes';

  @override
  String get workoutEditCancel => 'Cancel';

  @override
  String get workoutEditSave => 'Save';

  @override
  String get workoutEditErrDistance => 'Enter a positive distance in km';

  @override
  String get workoutEditErrPace => 'Pace must look like 5:30';

  @override
  String workoutEditSaveError(String error) {
    return 'Save failed: $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return 'RSVP\'D · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'Starting now';

  @override
  String upcomingEventInMinutes(int count) {
    return 'In $count min';
  }

  @override
  String get upcomingEventInOneHour => 'In 1 hour';

  @override
  String upcomingEventInHours(int count) {
    return 'In $count hours';
  }

  @override
  String get upcomingEventTomorrow => 'Tomorrow';

  @override
  String upcomingEventInDays(int count) {
    return 'In $count days';
  }

  @override
  String get todaysWorkoutDone => 'DONE TODAY';

  @override
  String get todaysWorkoutToday => 'TODAY\'S WORKOUT';

  @override
  String get errorStateRetry => 'Retry';

  @override
  String get shareCardRunTitle => 'Share run';

  @override
  String get shareCardExport => 'Export';

  @override
  String get shareCardImage => 'Image';

  @override
  String get shareCardStatDistance => 'Distance';

  @override
  String get shareCardStatTime => 'Time';

  @override
  String get shareCardStatPace => 'Pace';

  @override
  String get shareCardStatSpeed => 'Speed';

  @override
  String get shareCardBrandRun => 'RUN';

  @override
  String get shareCardImageError => 'Could not create share image';

  @override
  String get shareCardFileError => 'Could not export file';

  @override
  String get shareCardRouteTitle => 'Share route';

  @override
  String get shareCardRouteShareImage => 'Share image';

  @override
  String get shareCardRouteCapturing => 'Capturing…';

  @override
  String get shareCardRouteStatDistance => 'Distance';

  @override
  String get shareCardRouteStatClimb => 'Climb';

  @override
  String get billingToday => 'today';

  @override
  String get billingYesterday => 'yesterday';

  @override
  String billingDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String billingRenewalFailed(String relative) {
    return 'Pro renewal failed $relative.';
  }

  @override
  String get billingRenewalBody =>
      'Update your card or you\'ll be downgraded to Free.';

  @override
  String get billingManage => 'Manage';

  @override
  String get planCalendarPrevMonth => 'Previous month';

  @override
  String get planCalendarNextMonth => 'Next month';

  @override
  String runGearChipsLoadError(String error) {
    return 'Failed to load gear: $error';
  }

  @override
  String get runGearChipsPickerTitle => 'Tag gear used on this run';

  @override
  String get runGearChipsEmpty =>
      'You haven\'t registered any gear yet. Add some in Settings → Gear.';

  @override
  String get runGearChipsCancel => 'Cancel';

  @override
  String get runGearChipsSave => 'Save';

  @override
  String get runGearChipsTag => '+ Tag gear';

  @override
  String get runGearChipsEdit => 'Edit';

  @override
  String runGearChipsSaveError(String error) {
    return 'Save failed: $error';
  }

  @override
  String get gearFormTitleEdit => 'Edit gear';

  @override
  String get gearFormTitleAddShoes => 'Add shoes';

  @override
  String get gearFormTitleAddBike => 'Add bike';

  @override
  String get gearFormNameLabel => 'Name';

  @override
  String get gearFormNameHint => 'Pegasus 39';

  @override
  String get gearFormBrandLabel => 'Brand';

  @override
  String get gearFormModelLabel => 'Model';

  @override
  String get gearFormBoughtLabel => 'Bought';

  @override
  String get gearFormBoughtPick => 'Tap to pick';

  @override
  String gearFormRetireAt(String unit) {
    return 'Retire at ($unit)';
  }

  @override
  String get gearFormRetireHint => '500';

  @override
  String get gearFormNotesLabel => 'Notes';

  @override
  String get gearFormCancel => 'Cancel';

  @override
  String get gearFormSaving => 'Saving…';

  @override
  String get gearFormSave => 'Save';

  @override
  String get gearFormAdd => 'Add';

  @override
  String gearFormSaveError(String error) {
    return 'Save failed: $error';
  }

  @override
  String get gearWearLogHeading => 'Wear log';

  @override
  String get gearWearLogHint =>
      'Note how this gear is ageing over time — outsole wear, a dead midsole, a fraying upper.';

  @override
  String get gearWearLogEmpty => 'No wear observations yet.';

  @override
  String get gearWearLogAddNote => 'Observation';

  @override
  String get gearWearLogNoteHint => 'e.g. outsole lugs worn smooth on the heel';

  @override
  String get gearWearLogArea => 'Area';

  @override
  String get gearWearLogAreaNone => '—';

  @override
  String get gearWearLogAreaOutsole => 'Outsole';

  @override
  String get gearWearLogAreaMidsole => 'Midsole';

  @override
  String get gearWearLogAreaUpper => 'Upper';

  @override
  String get gearWearLogAreaOther => 'Other';

  @override
  String get gearWearLogAdd => 'Add observation';

  @override
  String get gearWearLogAdding => 'Adding…';

  @override
  String get gearWearLogDelete => 'Delete observation';

  @override
  String gearWearLogAddError(String error) {
    return 'Couldn\'t add observation: $error';
  }

  @override
  String gearWearLogDeleteError(String error) {
    return 'Couldn\'t delete observation: $error';
  }

  @override
  String get notificationBellTooltip => 'Notifications';

  @override
  String get liveRunMapWaitingGps => 'Waiting for GPS...';

  @override
  String get liveRunMapRecentre => 'Re-centre on my location';

  @override
  String get ttsRunStarted => 'Run started';

  @override
  String ttsRunComplete(String distance, int mins) {
    return 'Run complete. $distance in $mins minutes.';
  }

  @override
  String get ttsOffRoute => 'Off route';

  @override
  String get ttsPaceAlertFast => 'Pick up the pace';

  @override
  String get ttsPaceAlertSlow => 'Slow down';

  @override
  String get ttsWorkoutComplete => 'Workout complete. Nice work.';

  @override
  String get ttsStepHalfway => 'Halfway through this rep';

  @override
  String get ttsStepLastFifty => 'Fifty metres to go';

  @override
  String ttsPaceDriftAhead(int delta) {
    return 'Ease up — $delta seconds ahead pace.';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return 'Pick it up — $delta seconds behind pace.';
  }

  @override
  String ttsSpeedKm(String value) {
    return 'Speed, $value kilometres per hour';
  }

  @override
  String ttsSpeedMi(String value) {
    return 'Speed, $value miles per hour';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'Pace, $min minutes $sec seconds per kilometre';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'Pace, $min minutes $sec seconds per mile';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$value kilometres';
  }

  @override
  String ttsDistanceMetres(int value) {
    return '$value metres';
  }

  @override
  String ttsDistanceMileSingular(String value) {
    return '$value mile';
  }

  @override
  String ttsDistanceMiles(String value) {
    return '$value miles';
  }

  @override
  String ttsDistanceYards(int value) {
    return '$value yards';
  }

  @override
  String ttsSplit(String count, String unit, String tail) {
    return '$count $unit. $tail';
  }

  @override
  String get ttsStepWarmup => 'Warmup';

  @override
  String get ttsStepRecovery => 'Recovery';

  @override
  String get ttsStepSteady => 'Steady';

  @override
  String get ttsStepCooldown => 'Cooldown';

  @override
  String get ttsStepRep => 'Rep';

  @override
  String get ttsStepRun => 'Run';

  @override
  String get ttsStepWalk => 'Walk';

  @override
  String ttsStepRepOf(int index, int total) {
    return 'Rep $index of $total';
  }

  @override
  String ttsStepRunOf(int index, int total) {
    return 'Run $index of $total';
  }

  @override
  String ttsStepWalkOf(int index, int total) {
    return 'Walk $index of $total';
  }

  @override
  String ttsStepPaceKm(int min, int sec) {
    return '$min minutes $sec seconds per kilometre';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '$min minutes per kilometre';
  }

  @override
  String ttsStepPaceMi(int min, int sec) {
    return '$min minutes $sec seconds per mile';
  }

  @override
  String ttsStepPaceMiWhole(int min) {
    return '$min minutes per mile';
  }

  @override
  String ttsDurationSeconds(int sec) {
    return '$sec seconds';
  }

  @override
  String ttsDurationMinutes(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String ttsDurationMinutesSeconds(String minutes, int sec) {
    return '$minutes $sec seconds';
  }

  @override
  String ttsStepDuration(String intro, String duration) {
    return '$intro. $duration.';
  }

  @override
  String ttsStepDistancePace(String intro, String distance, String pace) {
    return '$intro. $distance at $pace.';
  }

  @override
  String get guidedEasy30Title => '30-Minute Easy Run';

  @override
  String get guidedEasy30Subtitle => 'Coach voice · 30 min · easy effort';

  @override
  String get guidedEasy30Description =>
      'A relaxed, conversational-pace run for a recovery day or just clearing your head. Coach checks in every five minutes with a gentle nudge.';

  @override
  String get guidedEasy30Cue0 =>
      'Let’s go. Start easy — this is your recovery pace.';

  @override
  String get guidedEasy30Cue1 =>
      'Five minutes in. Drop your shoulders. Keep it conversational.';

  @override
  String get guidedEasy30Cue2 =>
      'Ten minutes. Cadence check — quick feet, light landing.';

  @override
  String get guidedEasy30Cue3 =>
      'Halfway. You should still be able to talk through this.';

  @override
  String get guidedEasy30Cue4 =>
      'Twenty minutes. Notice your breathing — slow nasal in, mouth out.';

  @override
  String get guidedEasy30Cue5 => 'Five to go. Stay relaxed. Don’t pick it up.';

  @override
  String get guidedEasy30Cue6 => 'One minute left. Easy finish.';

  @override
  String get guidedEasy30Cue7 => 'Done. Walk it out for a minute. Nice job.';

  @override
  String get guidedTempo25Title => '25-Minute Tempo Builder';

  @override
  String get guidedTempo25Subtitle => 'Coach voice · 25 min · 5-15-5';

  @override
  String get guidedTempo25Description =>
      'Five-minute easy warm-up, fifteen minutes at tempo (comfortably hard), five-minute cool-down. The bread-and-butter weekly tempo session.';

  @override
  String get guidedTempo25Cue0 =>
      'Warm-up time. Five minutes easy — wake up the legs.';

  @override
  String get guidedTempo25Cue1 =>
      'One minute left in the warm-up. Pick up the cadence.';

  @override
  String get guidedTempo25Cue2 =>
      'Lift it to tempo. Comfortably hard. Like a 10K race effort.';

  @override
  String get guidedTempo25Cue3 =>
      'Five minutes in tempo. Strong but controlled. Keep the rhythm.';

  @override
  String get guidedTempo25Cue4 => 'Ten minutes of tempo done. Hold the pace.';

  @override
  String get guidedTempo25Cue5 => 'Two minutes left at tempo. Stay smooth.';

  @override
  String get guidedTempo25Cue6 => 'Ease off. Five minutes easy to cool down.';

  @override
  String get guidedTempo25Cue7 => 'Two to go. Bring the heart rate back down.';

  @override
  String get guidedTempo25Cue8 => 'Done. Walk and stretch. Great work.';

  @override
  String get guidedFirst15Title => 'First-Timer 15-Minute Run/Walk';

  @override
  String get guidedFirst15Subtitle =>
      'Coach voice · 15 min · run/walk intervals';

  @override
  String get guidedFirst15Description =>
      'New to running? Three rounds of one-minute run, one-minute walk, plus a warm-up and cool-down. A gentle on-ramp; everyone starts here.';

  @override
  String get guidedFirst15Cue0 =>
      'Start with a three-minute brisk walk to warm up.';

  @override
  String get guidedFirst15Cue1 =>
      'Switch to a one-minute easy run. Conversational pace.';

  @override
  String get guidedFirst15Cue2 => 'Walk one minute.';

  @override
  String get guidedFirst15Cue3 => 'Run one minute.';

  @override
  String get guidedFirst15Cue4 => 'Walk one minute.';

  @override
  String get guidedFirst15Cue5 => 'Run one minute.';

  @override
  String get guidedFirst15Cue6 => 'Walk one minute.';

  @override
  String get guidedFirst15Cue7 => 'Run one minute — last one.';

  @override
  String get guidedFirst15Cue8 => 'Walk it down. Five-minute cool-down.';

  @override
  String get guidedFirst15Cue9 => 'One minute left. Walk easy.';

  @override
  String get guidedFirst15Cue10 =>
      'Done. That was a real run. Get out there again soon.';

  @override
  String guidedRunMinutesBadge(int minutes) {
    return '$minutes min';
  }

  @override
  String guidedRunCueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cues across the run',
      one: '$count cue across the run',
    );
    return '$_temp0';
  }

  @override
  String get guidedRunFullScript => 'THE FULL SCRIPT';

  @override
  String get guidedRunPreviewCue => 'Preview cue';

  @override
  String guidedRunPreviewError(String error) {
    return 'Could not preview: $error';
  }

  @override
  String get ttsSplitUnitKilometre => 'kilometre';

  @override
  String get ttsSplitUnitKilometres => 'kilometres';

  @override
  String get ttsSplitUnitMile => 'mile';

  @override
  String get ttsSplitUnitMiles => 'miles';

  @override
  String get workoutKindEasy => 'Easy';

  @override
  String get workoutKindLong => 'Long run';

  @override
  String get workoutKindRecovery => 'Recovery';

  @override
  String get workoutKindTempo => 'Tempo';

  @override
  String get workoutKindInterval => 'Intervals';

  @override
  String get workoutKindMarathonPace => 'Marathon pace';

  @override
  String get workoutKindWalkRun => 'Walk-run';

  @override
  String get workoutKindRace => 'Race';

  @override
  String get workoutKindRest => 'Rest';

  @override
  String get planPhaseBase => 'Base';

  @override
  String get planPhaseBuild => 'Build';

  @override
  String get planPhasePeak => 'Peak';

  @override
  String get planPhaseTaper => 'Taper';

  @override
  String get planPhaseRace => 'Race week';

  @override
  String get runBackgroundLocationNudgeTitle => 'Allow location all the time';

  @override
  String get runBackgroundLocationNudgeBody =>
      'Android only granted location while the app is open. For accurate distance when your screen is off, set location access to \"Allow all the time\" in Settings. You can start anyway — recording still works while the app is on screen.';

  @override
  String get runBatteryOptHintTitle => 'Keep recording alive in the background';

  @override
  String get runBatteryOptHintBody =>
      'Some phones (Samsung, Xiaomi, OnePlus and others) put apps to sleep to save battery, which can stop a long run from recording when your screen is off. To be safe, exclude this app from battery optimisation in Settings. Your run will record either way — this just stops the system from cutting it short.';

  @override
  String shareCardCaption(Object title, Object distance, Object duration) {
    return '$title — $distance in $duration';
  }

  @override
  String get settingsBackendNotConfigured => 'Backend not configured';

  @override
  String get settingsAccountSignedIn => 'Signed in';

  @override
  String get settingsDevicesSignedOutSubtitle =>
      'Sign in to manage your devices';

  @override
  String get verifiedClubTooltip => 'Official verified club';

  @override
  String get raceDistance5k => '5 km';

  @override
  String get raceDistance10k => '10 km';

  @override
  String get raceDistanceHalfMarathon => 'Half Marathon';

  @override
  String get raceDistanceMarathon => 'Marathon';

  @override
  String get settingsTabAccountSubtitle => 'Sign in, backup, delete account';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Units, theme, recording, training, privacy';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, heart-rate strap';

  @override
  String get settingsTabDevicesSubtitle =>
      'Where you\'re signed in and per-device overrides';

  @override
  String get settingsTabGearSubtitle =>
      'Track shoes + bikes and per-item mileage';

  @override
  String get settingsTabCoachingSubtitle =>
      'Coach athletes or follow your own coach';

  @override
  String get settingsTabProSubtitle =>
      'Subscribe, restore purchases, manage billing';

  @override
  String get settingsTabLicensesSubtitle =>
      'App version and open-source notices';

  @override
  String periodSummaryWeekOf(Object date) {
    return 'Week of $date';
  }

  @override
  String periodShareRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '1 run',
    );
    return '$_temp0';
  }

  @override
  String periodShareAvgPace(Object pace) {
    return 'Avg pace: $pace';
  }

  @override
  String get gymTitle => 'Gym';

  @override
  String get gymLog => 'Log workout';

  @override
  String get gymUntitled => 'Untitled workout';

  @override
  String get gymOfflineCached => 'Offline — showing saved workouts';

  @override
  String get gymOfflineQueued =>
      'Offline — changes will sync when you reconnect';

  @override
  String get gymEmptyTitle => 'No gym workouts yet';

  @override
  String get gymEmptyBody =>
      'Log a lift to track it here and feed your training load.';

  @override
  String get gymPrBadge => 'PR';

  @override
  String gymExercisesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '$count exercise',
    );
    return '$_temp0';
  }

  @override
  String gymVolumeShort(int volume) {
    return '$volume kg';
  }

  @override
  String get gymNotFound => 'Workout not found.';

  @override
  String get gymEdit => 'Edit';

  @override
  String get gymDelete => 'Delete';

  @override
  String get gymPublic => 'Public';

  @override
  String get gymPrivate => 'Private';

  @override
  String get gymMakePublic => 'Make public';

  @override
  String get gymMakePrivate => 'Make private';

  @override
  String gymVisibilityFailed(Object error) {
    return 'Couldn\'t update visibility: $error';
  }

  @override
  String gymDeleteFailed(Object error) {
    return 'Couldn\'t delete the workout: $error';
  }

  @override
  String get gymNotes => 'Notes';

  @override
  String get gymKg => 'kg';

  @override
  String get gymReps => 'Reps';

  @override
  String get gymRpe => 'RPE';

  @override
  String get gymDuration => 'Time (s)';

  @override
  String gymDurationValue(String seconds) {
    return '${seconds}s';
  }

  @override
  String gymSetN(int n) {
    return 'Set $n';
  }

  @override
  String get gymPrWeight => 'Heaviest';

  @override
  String get gymPrVolume => 'Top volume';

  @override
  String get gymPrE1rm => 'Best est. 1RM';

  @override
  String get gymRecordsLink => 'Records';

  @override
  String get gymRecordsTitle => 'Personal records';

  @override
  String get gymRecordsSubtitle =>
      'Your best lift for every weighted exercise.';

  @override
  String get gymRecordsEmpty =>
      'No weighted lifts logged yet. Add a weight to a set to start tracking your bests.';

  @override
  String gymRecordsLastDone(String date) {
    return 'Last $date';
  }

  @override
  String gymRecordsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String get gymExerciseBack => 'Back to records';

  @override
  String get gymExerciseEmpty => 'No history for this exercise yet.';

  @override
  String gymSinceFirstUp(String delta) {
    return 'up $delta since first session';
  }

  @override
  String gymSinceFirstDown(String delta) {
    return 'down $delta since first session';
  }

  @override
  String get gymSinceFirstFlat => 'no change since first session';

  @override
  String gymDetailLastTime(String date) {
    return 'Last time $date';
  }

  @override
  String get gymVolumeLabel => 'Volume';

  @override
  String get gymDeleteConfirmTitle => 'Delete workout?';

  @override
  String get gymDeleteConfirmBody =>
      'This permanently removes the workout and its sets.';

  @override
  String get clubEventMembersOnly => 'Members only';

  @override
  String get clubEventLogAsWorkout => 'Log this as a workout';

  @override
  String get clubEventLogAsWorkoutHint =>
      'Add this class to your own gym log — you can adjust the details before saving.';

  @override
  String get clubEventLogAsWorkoutSaved => 'Added to your gym log';

  @override
  String get clubEventDownloadCertificate => 'Finisher certificate';

  @override
  String get clubEventCertificateShare => 'Save or share';

  @override
  String clubEventCertificateShareText(String event) {
    return 'I finished $event!';
  }

  @override
  String get clubEventCertificateFailed =>
      'Could not generate the certificate. Please try again.';

  @override
  String get clubEventCertificateHeading => 'Certificate of Completion';

  @override
  String get clubEventCertificateCertifies => 'This certifies that';

  @override
  String get clubEventCertificateCompleted => 'completed';

  @override
  String get clubEventCertificateTime => 'Time';

  @override
  String get clubEventCertificateDistance => 'Distance';

  @override
  String clubEventCertificatePlace(String place) {
    return '$place place';
  }

  @override
  String get gymEditorNewTitle => 'New workout';

  @override
  String get gymEditorEditTitle => 'Edit workout';

  @override
  String get gymEditorTitleLabel => 'Title (optional)';

  @override
  String get gymEditorTitlePlaceholder => 'e.g. Push day';

  @override
  String get gymEditorExercisePlaceholder => 'Exercise name';

  @override
  String get gymEditorRemoveExercise => 'Remove exercise';

  @override
  String get gymEditorRemoveSet => 'Remove set';

  @override
  String get gymEditorAddSet => 'Add set';

  @override
  String get gymEditorAddExercise => 'Add exercise';

  @override
  String get gymEditorShare => 'Share to feed';

  @override
  String get gymEditorCancel => 'Cancel';

  @override
  String get gymEditorSave => 'Save workout';

  @override
  String get gymEditorNeedExercise => 'Add at least one exercise with a name.';

  @override
  String get gymCatalogueBrowse => 'Browse catalogue';

  @override
  String get gymCatalogueTitle => 'Exercise catalogue';

  @override
  String get gymCatalogueSearchPlaceholder => 'Search exercises';

  @override
  String get gymCatalogueCategoryLabel => 'Category';

  @override
  String get gymCatalogueEmpty => 'No exercises match.';

  @override
  String get gymCatalogueCustomBadge => 'Custom';

  @override
  String gymCatalogueCreate(String name) {
    return 'Add “$name” as a custom exercise';
  }

  @override
  String get gymCatalogueCreateFailed => 'Couldn\'t add that exercise.';

  @override
  String get gymCatalogueCategoryAll => 'All';

  @override
  String get gymCatalogueCategoryChest => 'Chest';

  @override
  String get gymCatalogueCategoryBack => 'Back';

  @override
  String get gymCatalogueCategoryShoulders => 'Shoulders';

  @override
  String get gymCatalogueCategoryLegs => 'Legs';

  @override
  String get gymCatalogueCategoryArms => 'Arms';

  @override
  String get gymCatalogueCategoryCore => 'Core';

  @override
  String get gymCatalogueCategoryCardio => 'Cardio';

  @override
  String get gymCatalogueCategoryFullBody => 'Full body';

  @override
  String get gymCatalogueCategoryOther => 'Other';

  @override
  String get gymSaveFailed => 'Couldn\'t save workout.';

  @override
  String get gymRoutineLink => 'Routines';

  @override
  String get gymRoutineTitle => 'Routines';

  @override
  String get gymRoutineNew => 'New routine';

  @override
  String get gymRoutineBack => 'Back to routines';

  @override
  String get gymRoutineNotFound => 'Routine not found.';

  @override
  String gymRoutineExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '$count exercise',
    );
    return '$_temp0';
  }

  @override
  String get gymRoutineStart => 'Start routine';

  @override
  String get gymRoutinePublishLabel => 'Publish to a club';

  @override
  String get gymRoutinePublishPick => 'Pick a club…';

  @override
  String get gymRoutinePublish => 'Publish';

  @override
  String get gymRoutinePublishSuccess => 'Routine published to the club.';

  @override
  String get gymRoutinePublishFailed => 'Couldn\'t publish the routine.';

  @override
  String get gymRoutineClubTemplateBadge => 'Club template';

  @override
  String get gymRoutinePublicBadge => 'In the public library';

  @override
  String get gymRoutinePublishPublicLabel => 'Public library';

  @override
  String get gymRoutinePublishPublic => 'Publish to public library';

  @override
  String get gymRoutineUnpublishPublic => 'Remove from public library';

  @override
  String get gymRoutinePublishPublicHint =>
      'Anyone signed in can preview and adopt this routine. Logged workouts stay private.';

  @override
  String get gymRoutinePublishPublicSuccess =>
      'Routine published to the public library.';

  @override
  String get gymRoutineUnpublishPublicSuccess =>
      'Routine removed from the public library.';

  @override
  String get gymRoutinePublishPublicFailed =>
      'Couldn\'t update public visibility.';

  @override
  String get gymLibraryLink => 'Library';

  @override
  String get gymLibraryTitle => 'Public routine library';

  @override
  String get gymLibrarySearchHint => 'Search routines by name';

  @override
  String get gymLibraryLoadError => 'Couldn\'t load the library.';

  @override
  String get gymLibraryEmpty => 'No published routines yet.';

  @override
  String gymLibraryEmptySearch(String query) {
    return 'No routines match \"$query\".';
  }

  @override
  String gymLibraryByAuthor(String author) {
    return 'by $author';
  }

  @override
  String get gymLibraryAnonymous => 'a lifter';

  @override
  String get gymLibraryAdopt => 'Adopt into my routines';

  @override
  String get gymLibraryAdopting => 'Adopting…';

  @override
  String get gymLibraryAdoptFailed => 'Couldn\'t adopt the routine.';

  @override
  String get gymRoutineDelete => 'Delete';

  @override
  String get gymRoutineDeleteConfirmTitle => 'Delete routine?';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'This permanently removes the routine. Logged workouts are unaffected.';

  @override
  String get gymRoutineDeleted => 'Routine deleted';

  @override
  String get gymRoutineCreated => 'Routine saved';

  @override
  String get gymRoutineSaveFailed => 'Couldn\'t save routine.';

  @override
  String get gymRoutineEmptyTitle => 'No routines yet';

  @override
  String get gymRoutineEmptyBody =>
      'Save a logged workout as a routine, or build one from scratch, to reuse it.';

  @override
  String get gymRoutineTargetReps => 'Target reps';

  @override
  String gymRoutineTargetWeight(String unit) {
    return 'Target weight ($unit)';
  }

  @override
  String get gymRoutineEditorNewTitle => 'New routine';

  @override
  String get gymRoutineEditorTitleLabel => 'Routine name';

  @override
  String get gymRoutineEditorTitlePlaceholder => 'e.g. Push day A';

  @override
  String get gymRoutineEditorNotesLabel => 'Notes (optional)';

  @override
  String get gymRoutineEditorSave => 'Save routine';

  @override
  String get gymRoutineEditorCancel => 'Cancel';

  @override
  String get gymRoutineEditorNeedTitle => 'Give the routine a name.';

  @override
  String get gymRoutineEditorNeedExercise =>
      'Add at least one exercise with a name.';

  @override
  String get gymRoutineSaveAsRoutine => 'Save as routine';

  @override
  String get gymRoutineRepeatLast => 'Repeat last';

  @override
  String get gymRoutineTargetRepsMax => 'to';

  @override
  String get gymRoutineTargetDuration => 'Target time (s)';

  @override
  String get gymRoutineTargetDistance => 'Target distance (m)';

  @override
  String get gymRoutineRestLabel => 'Rest (s)';

  @override
  String get gymRoutineSetType => 'Set type';

  @override
  String get gymRoutineSetTypeWarmup => 'Warm-up';

  @override
  String get gymRoutineSetTypeWorking => 'Working';

  @override
  String get gymRoutineSetTypeDropset => 'Drop set';

  @override
  String get gymRoutineSetTypeAmrap => 'AMRAP';

  @override
  String get gymRoutineSetTypeFailure => 'To failure';

  @override
  String get gymRoutineSetTypeBackoff => 'Back-off';

  @override
  String get gymRoutineModality => 'Measured by';

  @override
  String get gymRoutineModalityWeightReps => 'Weight × reps';

  @override
  String get gymRoutineModalityTime => 'Time';

  @override
  String get gymRoutineModalityDistance => 'Distance';

  @override
  String get gymRoutineModalityBodyweightReps => 'Bodyweight reps';

  @override
  String get gymRoutineSupersetToggle => 'Superset with the next exercise';

  @override
  String gymRoutineSupersetBadge(int group) {
    return 'Superset $group';
  }

  @override
  String get gymRoutineAdvanced => 'Advanced';

  @override
  String get gymRoutineProgression => 'Progression';

  @override
  String get gymRoutineProgressionNone => 'None';

  @override
  String get gymRoutineProgressionLinear => 'Linear';

  @override
  String get gymRoutineProgressionDoubleProgression => 'Double progression';

  @override
  String get gymRoutineProgressionFiveByFive => '5×5';

  @override
  String get gymRoutineProgressionPercentCycle => '% of 1RM cycle';

  @override
  String get gymRoutineProgressionRpeAutoreg => 'RPE auto-regulation';

  @override
  String gymRoutineProgressionIncrementLabel(String unit) {
    return 'Weight step ($unit)';
  }

  @override
  String get gymRoutineProgressionPercentLabel => '% of 1RM';

  @override
  String gymRoutineProgressionOneRmLabel(String unit) {
    return '1RM ($unit)';
  }

  @override
  String get gymRoutineProgressionTargetRpeLabel => 'Target RPE';

  @override
  String get gymRoutineNextTarget => 'Next target';

  @override
  String get gymRoutineNextTargetIncreaseWeight => 'Add load next time';

  @override
  String get gymRoutineNextTargetIncreaseReps => 'Add reps next time';

  @override
  String get gymRoutineNextTargetHold => 'Hold — repeat this target';

  @override
  String get gymRoutineNextTargetEstablishBaseline =>
      'Establish baseline — set a starting weight';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — back off the load';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'rep climb $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrition';

  @override
  String get nutritionLogFood => 'Log food';

  @override
  String get nutritionCalories => 'Calories';

  @override
  String get nutritionProtein => 'Protein';

  @override
  String get nutritionCarbs => 'Carbs';

  @override
  String get nutritionFat => 'Fat';

  @override
  String get nutritionWater => 'Water';

  @override
  String get nutritionWaterAdd => 'Add water';

  @override
  String get nutritionWaterRemove => 'Remove water';

  @override
  String get nutritionNoTargets =>
      'Add your height, weight, age and sex on the web app to see calorie + macro targets.';

  @override
  String get nutritionWeeklyTrend => 'Last 7 days';

  @override
  String nutritionCaloriesLeft(int n) {
    return '$n kcal left';
  }

  @override
  String nutritionCaloriesOver(int n) {
    return '$n kcal over';
  }

  @override
  String get nutritionOnTarget => 'On target';

  @override
  String nutritionMacroOver(int n) {
    return '$n over target';
  }

  @override
  String get nutritionMacroReached => 'Target reached';

  @override
  String nutritionWaterAmount(String consumed, String target) {
    return '$consumed / $target L';
  }

  @override
  String get nutritionWaterGoalReached => 'Goal reached';

  @override
  String nutritionWaterRemaining(int n) {
    return '$n ml left';
  }

  @override
  String get nutritionWeekOnGoal => 'On goal';

  @override
  String nutritionWeekUnderGoal(int n) {
    return '$n under goal/day';
  }

  @override
  String nutritionWeekOverGoal(int n) {
    return '$n over goal/day';
  }

  @override
  String nutritionWeekProtein(int met, int total) {
    return 'Protein $met/$total days';
  }

  @override
  String get nutritionGoalLine => 'Daily goal';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return 'Goal $base + $exercise kcal burned today';
  }

  @override
  String get dashGymReadinessIncluded =>
      'Recent gym sessions are factored into your fatigue.';

  @override
  String get dashGymReadinessExcluded =>
      'Gym load is excluded from your run readiness.';

  @override
  String get prefsExcludeGymFromReadiness =>
      'Exclude gym load from run readiness';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'By default, gym sessions add to your fatigue and lower your readiness, like a run. Turn this on to keep your fitness, fatigue and form based on runs only.';

  @override
  String get nutritionEmptyTitle => 'No food logged today';

  @override
  String get nutritionEmptyBody =>
      'Log a meal to track your calories and macros.';

  @override
  String get nutritionSlotBreakfast => 'Breakfast';

  @override
  String get nutritionSlotLunch => 'Lunch';

  @override
  String get nutritionSlotDinner => 'Dinner';

  @override
  String get nutritionSlotSnack => 'Snack';

  @override
  String get nutritionMealProtein => 'Protein';

  @override
  String get nutritionMealCarbs => 'Carbs';

  @override
  String get nutritionMealFat => 'Fat';

  @override
  String get nutritionMealItemsHeading => 'Items';

  @override
  String get nutritionMealNoItems => 'Nothing logged for this meal.';

  @override
  String get nutritionMealTrendHeading => 'Last 7 days';

  @override
  String get nutritionDelete => 'Delete';

  @override
  String get nutritionDeleteEntryTitle => 'Delete this entry?';

  @override
  String nutritionDeleteEntryMessage(String item) {
    return '$item will be removed from today\'s log.';
  }

  @override
  String nutritionDeleteFailed(String error) {
    return 'Couldn’t delete the entry: $error';
  }

  @override
  String get nutritionOfflineQueued =>
      'Offline — changes will sync when you reconnect';

  @override
  String get nutritionOfflineCached => 'Offline — showing saved entries';

  @override
  String get nutritionLogTitle => 'Log food';

  @override
  String get nutritionSearchHint => 'Search for a food';

  @override
  String get nutritionSearching => 'Searching…';

  @override
  String get nutritionNoResults =>
      'No matches. Try another term or enter it manually below.';

  @override
  String get nutritionSearchFailed =>
      'Search failed. Check your connection, then retry or enter it manually below.';

  @override
  String get nutritionSearchRetry => 'Retry search';

  @override
  String get nutritionSourceOff => 'Open Food Facts';

  @override
  String get nutritionSourceUsda => 'USDA';

  @override
  String get nutritionScanBarcode => 'Scan barcode';

  @override
  String get nutritionScanHint => 'Point the camera at a product barcode';

  @override
  String get nutritionScanLookingUp => 'Looking up…';

  @override
  String get nutritionScanNotFound =>
      'No product found for that barcode. Try a search or enter it manually.';

  @override
  String get nutritionScanFailed =>
      'Scan failed. Try a search or enter it manually.';

  @override
  String get nutritionScanPermissionDenied =>
      'Camera access is needed to scan a barcode. You can still search or enter food manually.';

  @override
  String get nutritionScanOpenSettings => 'Open settings';

  @override
  String get nutritionSaveFailed => 'Couldn\'t log food. Try again.';

  @override
  String get nutritionMealSlot => 'Meal';

  @override
  String get nutritionManualEntry => 'Enter manually';

  @override
  String get nutritionItemName => 'Item name';

  @override
  String get nutritionPortionGrams => 'Portion (g)';

  @override
  String get nutritionAdd => 'Add';

  @override
  String get nutritionCancel => 'Cancel';

  @override
  String get nutritionTemplates => 'Meal templates';

  @override
  String get nutritionSaveAsMeal => 'Save as meal';

  @override
  String get nutritionSaveAsMealTitle => 'Save as a meal template';

  @override
  String get nutritionTemplateName => 'Template name';

  @override
  String get nutritionTemplateNamePlaceholder => 'e.g. Pre-run breakfast';

  @override
  String get nutritionSaveTemplate => 'Save meal';

  @override
  String get nutritionTemplateSaved => 'Meal template saved.';

  @override
  String nutritionTemplateSaveFailed(String error) {
    return 'Couldn’t save the template: $error';
  }

  @override
  String get nutritionLogTemplate => 'Log';

  @override
  String nutritionTemplateLogged(int n, String name) {
    return 'Logged $n items from $name.';
  }

  @override
  String nutritionTemplateLogFailed(String error) {
    return 'Couldn’t log the template: $error';
  }

  @override
  String nutritionTemplateDeleteFailed(String error) {
    return 'Couldn’t delete the template: $error';
  }

  @override
  String nutritionTemplateItems(int n) {
    return '$n items';
  }

  @override
  String get nutritionDeleteTemplate => 'Delete';

  @override
  String get nutritionDeleteTemplateTitle => 'Delete this meal template?';

  @override
  String nutritionDeleteTemplateMessage(String name) {
    return '$name will be removed. Meals already logged from it stay in your diary.';
  }

  @override
  String get nutritionRecipes => 'Recipes';

  @override
  String get nutritionSaveAsRecipe => 'Save as recipe';

  @override
  String get nutritionSaveAsRecipeTitle => 'Save as a recipe';

  @override
  String get nutritionRecipeName => 'Recipe name';

  @override
  String get nutritionRecipeNamePlaceholder => 'e.g. Chicken & rice bowl';

  @override
  String get nutritionRecipeServings => 'Servings';

  @override
  String get nutritionRecipeServingsHint =>
      'The ingredients are summed, then divided by servings. Logging one serving adds a single entry with the combined macros.';

  @override
  String get nutritionSaveRecipe => 'Save recipe';

  @override
  String get nutritionRecipeSaved => 'Recipe saved.';

  @override
  String nutritionRecipeSaveFailed(String error) {
    return 'Couldn’t save the recipe: $error';
  }

  @override
  String get nutritionLogRecipe => 'Log';

  @override
  String nutritionRecipeLogged(int n, String name) {
    return 'Logged $name ($n serving).';
  }

  @override
  String nutritionRecipeLogFailed(String error) {
    return 'Couldn’t log the recipe: $error';
  }

  @override
  String nutritionRecipeDeleteFailed(String error) {
    return 'Couldn’t delete the recipe: $error';
  }

  @override
  String nutritionRecipeMeta(int n, num servings) {
    final intl.NumberFormat servingsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String servingsString = servingsNumberFormat.format(servings);

    return '$n ingredients · $servingsString servings';
  }

  @override
  String get nutritionDeleteRecipe => 'Delete';

  @override
  String get nutritionDeleteRecipeTitle => 'Delete this recipe?';

  @override
  String nutritionDeleteRecipeMessage(String name) {
    return '$name will be removed. Meals already logged from it stay in your diary.';
  }

  @override
  String get sessionTitle => 'Sessions';

  @override
  String get sessionEmpty => 'No session plans yet.';

  @override
  String get sessionEmptyHint =>
      'Build a reusable yoga, pilates or class sequence on the web.';

  @override
  String get sessionUntitled => 'Untitled session';

  @override
  String get sessionNotFound => 'Session plan not found.';

  @override
  String get sessionMakePublic => 'Make public';

  @override
  String get sessionMakePrivate => 'Make private';

  @override
  String get sessionVisibilityError => 'Couldn\'t change visibility.';

  @override
  String get sessionSteps => 'Sequence';

  @override
  String sessionStepHold(Object name, Object seconds) {
    return '$name · hold ${seconds}s';
  }

  @override
  String sessionStepReps(Object name, Object reps) {
    return '$name · $reps reps';
  }

  @override
  String sessionStepFlow(Object name, Object seconds) {
    return '$name · flow ${seconds}s';
  }

  @override
  String sessionSideLeft(Object name) {
    return '$name (Left)';
  }

  @override
  String sessionSideRight(Object name) {
    return '$name (Right)';
  }

  @override
  String sessionEstDuration(Object minutes) {
    return 'Est. $minutes min';
  }

  @override
  String get gymSessionStart => 'Start session';

  @override
  String gymSessionStep(Object exercise, Object set, Object total) {
    return '$exercise · set $set of $total';
  }

  @override
  String get gymSessionComplete => 'Session complete';

  @override
  String get gymSessionSkipSet => 'Skip set';

  @override
  String get gymSessionRewind => 'Previous';

  @override
  String get gymSessionAbandon => 'Abandon';

  @override
  String get gymSessionFinish => 'Finish';

  @override
  String get gymSessionDiscardTitle => 'Discard session?';

  @override
  String get gymSessionDiscardBody =>
      'Your progress in this session won\'t be saved.';

  @override
  String get gymSessionDiscardConfirm => 'Discard';

  @override
  String get gymSessionSaved => 'Workout saved';

  @override
  String get gymSessionSaveFailed => 'Couldn\'t save workout';

  @override
  String gymSessionSetProgress(Object done, Object total) {
    return '$done/$total';
  }

  @override
  String get gymSessionLogSet => 'Complete set';

  @override
  String get gymSessionRest => 'Rest';

  @override
  String gymSessionRestRemaining(Object seconds) {
    return 'Rest ${seconds}s';
  }

  @override
  String get gymSessionRestSkip => 'Skip rest';

  @override
  String get gymSessionTarget => 'Target';

  @override
  String gymReviewAdherence(Object pct) {
    return '$pct% adherence';
  }

  @override
  String get gymReviewVerdictCompleted => 'Completed';

  @override
  String get gymReviewVerdictPartial => 'Partly done';

  @override
  String get gymReviewVerdictAbandoned => 'Abandoned';

  @override
  String get gymReviewStatusHit => 'Hit';

  @override
  String get gymReviewStatusPartial => 'Partial';

  @override
  String get gymReviewStatusMissed => 'Missed';

  @override
  String get gymReviewStatusExtra => 'Extra';

  @override
  String get sessionRunStart => 'Start session';

  @override
  String sessionRunStep(Object name) {
    return '$name';
  }

  @override
  String get sessionRunDone => 'Done';

  @override
  String get sessionRunSkip => 'Skip';

  @override
  String get sessionRunPause => 'Pause';

  @override
  String get sessionRunResume => 'Resume';

  @override
  String get sessionRunAbandon => 'Abandon';

  @override
  String get sessionRunFinish => 'Finish';

  @override
  String sessionRunRemaining(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get sessionRunComplete => 'Session complete';

  @override
  String get sessionRunSaved => 'Session saved';

  @override
  String get sessionRunSaveFailed => 'Couldn\'t save session';

  @override
  String get sessionRunDiscardTitle => 'Discard session?';

  @override
  String get sessionRunDiscardBody =>
      'Your progress in this session won\'t be saved.';

  @override
  String get sessionRunDiscardConfirm => 'Discard';

  @override
  String get sessionRunVerdictCompleted => 'Completed';

  @override
  String get sessionRunVerdictPartial => 'Partly done';

  @override
  String get sessionRunVerdictAbandoned => 'Abandoned';

  @override
  String sessionRunStepCount(int index, int total) {
    return 'Step $index of $total';
  }

  @override
  String get sessionRunSwitchSides => 'Switch sides';

  @override
  String get coachingTitle => 'Coaching';

  @override
  String get coachingLede =>
      'Coach athletes by sharing an invite link, then review their training. Or follow your own coach here.';

  @override
  String get coachingCancel => 'Cancel';

  @override
  String get coachingMyAthletes => 'My athletes';

  @override
  String get coachingMyAthletesSub => 'Runners who accepted your invite';

  @override
  String get coachingInviteAnAthlete => 'Invite an athlete';

  @override
  String get coachingCreating => 'Creating…';

  @override
  String get coachingPendingInvite => 'Pending invite';

  @override
  String coachingPendingInviteSub(String date) {
    return 'Created $date · not yet accepted';
  }

  @override
  String get coachingCopyLink => 'Copy link';

  @override
  String get coachingShareLink => 'Share link';

  @override
  String get coachingRevoke => 'Revoke';

  @override
  String get coachingNoAthletes =>
      'No athletes yet. Invite one to get started.';

  @override
  String get coachingRosterTitle => 'Athlete roster';

  @override
  String get coachingRosterSubtitle =>
      'Every athlete at a glance — load, plan compliance, and injury risk.';

  @override
  String get coachingRosterNeverRun => 'No runs yet';

  @override
  String get coachingRosterNoPlan => 'No plan';

  @override
  String get coachingRosterRiskInsufficient => 'New';

  @override
  String get coachingRosterRiskLow => 'Low';

  @override
  String get coachingRosterRiskOptimal => 'Optimal';

  @override
  String get coachingRosterRiskElevated => 'Elevated';

  @override
  String get coachingRosterRiskHigh => 'High';

  @override
  String get coachingRunner => 'Runner';

  @override
  String coachingCoachingSince(String date) {
    return 'Coaching since $date';
  }

  @override
  String get coachingReview => 'Review';

  @override
  String get coachingRemove => 'Remove';

  @override
  String get coachingMyCoaches => 'My coaches';

  @override
  String get coachingMyCoachesSub => 'Coaches who can see your training';

  @override
  String get coachingNoCoaches => 'You haven\'t accepted a coach invite yet.';

  @override
  String get coachingCoach => 'Coach';

  @override
  String coachingLinkedSince(String date) {
    return 'Linked since $date';
  }

  @override
  String get coachingLeave => 'Leave';

  @override
  String get coachingInviteLinkCopied => 'Invite link copied';

  @override
  String get coachingThisAthlete => 'this athlete';

  @override
  String get coachingThisCoach => 'this coach';

  @override
  String get coachingRevokeTitle => 'Revoke invite?';

  @override
  String get coachingRevokeBody =>
      'The invite link will stop working. You can always create a new one.';

  @override
  String get coachingRemoveAthleteTitle => 'Remove athlete?';

  @override
  String coachingRemoveAthleteBody(String name) {
    return 'Stop coaching $name? You\'ll lose access to their runs and plans.';
  }

  @override
  String get coachingLeaveCoachTitle => 'Leave coach?';

  @override
  String coachingLeaveCoachBody(String name) {
    return 'Stop sharing your training with $name?';
  }

  @override
  String coachingLoadError(String error) {
    return 'Couldn\'t load coaching: $error';
  }

  @override
  String coachingCreateInviteError(String error) {
    return 'Couldn\'t create invite: $error';
  }

  @override
  String coachingRevokeInviteError(String error) {
    return 'Couldn\'t revoke invite: $error';
  }

  @override
  String coachingRemoveAthleteError(String error) {
    return 'Couldn\'t remove athlete: $error';
  }

  @override
  String coachingEndLinkError(String error) {
    return 'Couldn\'t end the link: $error';
  }

  @override
  String get coachingAthleteAthleteFallback => 'Athlete';

  @override
  String get coachingAthleteRunnerFallback => 'Runner';

  @override
  String coachingAthleteCoachingSince(String date) {
    return 'Coaching since $date';
  }

  @override
  String get coachingAthletePlanCompliance => 'Plan compliance';

  @override
  String get coachingAthleteNoActivePlan => 'No active training plan.';

  @override
  String get coachingAthleteAssignTitle => 'Assign a plan';

  @override
  String coachingAthleteAssignHint(String name) {
    return 'Pick one of your plans to assign to $name.';
  }

  @override
  String get coachingAthleteAssignSelectLabel => 'Plan';

  @override
  String get coachingAthleteAssignSelectPlaceholder => 'Choose a plan…';

  @override
  String get coachingAthleteAssignStartLabel => 'Start date';

  @override
  String get coachingAthleteAssigning => 'Assigning…';

  @override
  String get coachingAthleteAssignButton => 'Assign plan';

  @override
  String get coachingAthleteAssignNoPlans =>
      'Create a training plan first, then you can assign it to your athletes.';

  @override
  String get coachingAthleteAssignedByYou => 'Assigned by you';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'This athlete already has an active plan. They\'ll need to finish or end it before you can assign a new one.';

  @override
  String get coachingAthleteComplete => 'complete';

  @override
  String coachingAthleteDoneCount(int done, int total) {
    return '$done of $total done';
  }

  @override
  String coachingAthleteMissedCount(int n) {
    return '$n missed';
  }

  @override
  String get coachingAthleteStatusDone => 'Done';

  @override
  String get coachingAthleteStatusMissed => 'Missed';

  @override
  String get coachingAthleteStatusUpcoming => 'Upcoming';

  @override
  String get coachingAthleteRecentRuns => 'Recent runs';

  @override
  String get coachingAthleteNoRunsYet => 'No runs logged yet.';

  @override
  String get coachingAthletePrivate => 'Private';

  @override
  String coachingAthleteAssignSuccess(String name) {
    return 'Plan assigned to $name';
  }

  @override
  String coachingAthleteLoadError(String error) {
    return 'Couldn\'t load athlete: $error';
  }

  @override
  String get routeMarkerHeading => 'Course markers';

  @override
  String get routeMarkerAdd => 'Add marker';

  @override
  String get routeMarkerEmpty =>
      'No course markers yet. Add aid stations, cutoffs, and more along the route.';

  @override
  String get routeMarkerEdit => 'Edit marker';

  @override
  String get routeMarkerDelete => 'Delete';

  @override
  String get routeMarkerCancel => 'Cancel';

  @override
  String get routeMarkerSave => 'Save';

  @override
  String get routeMarkerSaving => 'Saving…';

  @override
  String get routeMarkerKindLabel => 'Type';

  @override
  String get routeMarkerNameLabel => 'Name';

  @override
  String get routeMarkerNamePlaceholder => 'e.g. Aid 2';

  @override
  String get routeMarkerServicesLabel => 'Services';

  @override
  String get routeMarkerCutoffLabel => 'Cut-off time';

  @override
  String get routeMarkerNoteLabel => 'Note';

  @override
  String get routeMarkerTapToPlace => 'Tap the map to place this marker.';

  @override
  String get routeMarkerSnapToggle => 'Snap to route line';

  @override
  String get routeMarkerPlaced => 'Placed. Tap the map again to move it.';

  @override
  String routeMarkerCutoffAt(String time) {
    return 'Cut-off $time';
  }

  @override
  String get routeMarkerLabelRequired => 'Give the marker a name.';

  @override
  String get routeMarkerPlaceRequired =>
      'Tap the map to place the marker first.';

  @override
  String get routeMarkerLatLabel => 'Latitude';

  @override
  String get routeMarkerLngLabel => 'Longitude';

  @override
  String get routeMarkerCoordInvalid =>
      'Enter a valid latitude (-90 to 90) and longitude (-180 to 180).';

  @override
  String get routeMarkerEnterCoords => 'Enter coordinates instead';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Could not save marker: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Could not delete marker: $error';
  }

  @override
  String get routeMarkerDeleteConfirmTitle => 'Delete marker?';

  @override
  String get routeMarkerDeleteConfirmMessage =>
      'This removes the marker from the route permanently.';

  @override
  String get routeMarkerKindAidStation => 'Aid station';

  @override
  String get routeMarkerKindCutoff => 'Cut-off';

  @override
  String get routeMarkerKindCrewAccess => 'Crew / parking';

  @override
  String get routeMarkerKindHazard => 'Hazard';

  @override
  String get routeMarkerKindNote => 'Note';

  @override
  String get routeMarkerKindClimb => 'Climb';

  @override
  String get routeMarkerKindCustom => 'Custom';

  @override
  String get routeMarkerServiceWater => 'Water';

  @override
  String get routeMarkerServiceFood => 'Food';

  @override
  String get routeMarkerServiceMedical => 'Medical';

  @override
  String get routeMarkerServiceToilets => 'Toilets';

  @override
  String get routeMarkerServiceDropBag => 'Drop bag';

  @override
  String get clubFormEditTitle => 'Edit club';

  @override
  String get clubEditorWebsite => 'Website';

  @override
  String get clubEditorInstagram => 'Instagram';

  @override
  String get clubEditorStrava => 'Strava';

  @override
  String get clubEditorFacebook => 'Facebook';

  @override
  String get clubEditorSaveChanges => 'Save changes';

  @override
  String get clubDetailVisitWebsite => 'Visit our website';

  @override
  String get clubDetailEditClub => 'Edit club';

  @override
  String get roadbookTitle => 'Roadbook';

  @override
  String get roadbookCrewSheet => 'Roadbook (crew sheet)';

  @override
  String get roadbookGoalTime => 'Goal time';

  @override
  String get roadbookStartTime => 'Start time';

  @override
  String get roadbookEffort => 'Effort';

  @override
  String get roadbookEven => 'Even';

  @override
  String get roadbookStart => 'Start';

  @override
  String get roadbookFinish => 'Finish';

  @override
  String get roadbookShare => 'Share';

  @override
  String get roadbookNoMarkers => 'Add course markers to build a roadbook.';

  @override
  String get roadbookAddElevation => 'Add elevation';

  @override
  String get roadbookElevationUnavailable =>
      'Elevation data unavailable for this route';

  @override
  String roadbookSummary(String distance, String vert, String time) {
    return '$distance · $vert vert · goal $time';
  }

  @override
  String get roadbookFuel => 'Fuel';

  @override
  String get roadbookHeat => 'Heat';

  @override
  String get roadbookCarbs => 'Carbs';

  @override
  String get roadbookFluid => 'Fluid';

  @override
  String roadbookCarbsValue(String grams) {
    return '$grams g';
  }

  @override
  String roadbookFluidValue(String ml) {
    return '$ml ml';
  }

  @override
  String roadbookCarryHint(String gels, String fluid) {
    return 'carry $gels gels · $fluid ml';
  }

  @override
  String get checkpointCheckinAction => 'Checkpoint check-in';

  @override
  String get checkpointCheckinTitle => 'Aid-station check-in';

  @override
  String get checkpointSyncNow => 'Sync now';

  @override
  String get checkpointPending => 'Unsynced';

  @override
  String get checkpointLoadFailed => 'Couldn\'t load checkpoints';

  @override
  String get checkpointRetry => 'Retry';

  @override
  String get checkpointNone =>
      'This race has no checkpoints yet. Add them on the web before crews check runners in.';

  @override
  String get checkpointPickLabel => 'CHECKPOINT';

  @override
  String get checkpointBibLabel => 'Bib number';

  @override
  String get checkpointBibHint => 'Scan or type a bib';

  @override
  String get checkpointBibRequired => 'Enter a bib number first';

  @override
  String get checkpointStampIn => 'Stamp IN';

  @override
  String get checkpointStampOut => 'Stamp OUT';

  @override
  String checkpointStampedIn(String bib) {
    return 'Bib $bib stamped in';
  }

  @override
  String checkpointStampedOut(String bib) {
    return 'Bib $bib stamped out';
  }

  @override
  String get checkpointStampFailed => 'Couldn\'t save that stamp';

  @override
  String checkpointLoggedHere(int count) {
    return 'LOGGED HERE ($count)';
  }

  @override
  String get checkpointNoneLoggedHere =>
      'No runners logged at this checkpoint yet.';

  @override
  String checkpointBibRow(String bib) {
    return 'Bib $bib';
  }

  @override
  String checkpointInOut(String inTime, String outTime) {
    return 'In $inTime · Out $outTime';
  }

  @override
  String get checkpointWeighInTitle => 'Weigh-in';

  @override
  String get checkpointWeighInConsentBlurb =>
      'Body weight and medical-hold notes are health data, recorded only with the runner\'s consent and visible only to race officials.';

  @override
  String get checkpointWeighInConsent =>
      'Runner consents to recording health data';

  @override
  String get checkpointWeighInWeightKg => 'Body weight (kg)';

  @override
  String get checkpointMedicalHold => 'Place on medical hold';

  @override
  String get checkpointWeighInSave => 'Save & stamp';

  @override
  String get checkpointCancel => 'Cancel';

  @override
  String get challengesTitle => 'Challenges';

  @override
  String get challengesMyChallenges => 'My challenges';

  @override
  String get challengesBrowse => 'Browse';

  @override
  String get challengesEmpty => 'No challenges yet.';

  @override
  String get challengesBrowseEmpty => 'No public challenges to join right now.';

  @override
  String get challengesJoin => 'Join';

  @override
  String get challengesLeave => 'Leave';

  @override
  String get challengesDelete => 'Delete';

  @override
  String get challengesMetricDistance => 'Distance';

  @override
  String get challengesMetricDuration => 'Time';

  @override
  String get challengesMetricVert => 'Elevation';

  @override
  String get challengesMetricActivityCount => 'Activities';

  @override
  String get challengesMetricStreak => 'Active days';

  @override
  String challengesGoalProgress(String value, String goal) {
    return '$value of $goal';
  }

  @override
  String get challengesProgressComplete => 'Complete';

  @override
  String get challengesPaceAhead => 'Ahead of pace';

  @override
  String get challengesPaceOnTrack => 'On pace to finish';

  @override
  String get challengesPaceBehind => 'Behind pace';

  @override
  String challengesPaceNeedPerDay(String rate) {
    return '$rate per day to finish';
  }

  @override
  String challengesEndsIn(int n) {
    return 'Ends in $n days';
  }

  @override
  String get challengesEndsToday => 'Ends today';

  @override
  String get challengesEnded => 'Ended';

  @override
  String get challengesLeaderboard => 'Leaderboard';

  @override
  String get challengesLeaderboardEmpty => 'No progress logged yet.';

  @override
  String challengesLeaderboardRank(int rank) {
    return '#$rank';
  }

  @override
  String challengesParticipants(int n) {
    return '$n joined';
  }

  @override
  String get challengesBadgeEarned => 'Badge earned';

  @override
  String challengesUnitDays(int n) {
    return '$n days';
  }

  @override
  String challengesUnitActivities(int n) {
    return '$n';
  }

  @override
  String get challengesLeaveConfirmTitle => 'Leave challenge?';

  @override
  String get challengesLeaveConfirm =>
      'Your progress in this challenge will no longer be tracked.';

  @override
  String get challengesDeleteConfirmTitle => 'Delete challenge?';

  @override
  String get challengesDeleteConfirm =>
      'This removes the challenge and its leaderboard for everyone. This can\'t be undone.';

  @override
  String get challengesNotFound => 'This challenge isn\'t available.';

  @override
  String get challengesJoinFailed => 'Couldn\'t join the challenge.';

  @override
  String get challengesLeaveFailed => 'Couldn\'t leave the challenge.';

  @override
  String get challengesDeleteFailed => 'Couldn\'t delete the challenge.';

  @override
  String get challengesLoadFailed => 'Couldn\'t load challenges.';

  @override
  String fundraiserRaisedOfGoal(String raised, String goal) {
    return '$raised of $goal raised';
  }

  @override
  String fundraiserDonorCount(int count) {
    return '$count supporters';
  }

  @override
  String get fundraiserOverGoal => 'Over goal!';

  @override
  String get fundraiserClosed => 'This fundraiser is closed.';

  @override
  String get fundraiserFeedTitle => 'Recent supporters';

  @override
  String get fundraiserFeedEmpty => 'Be the first to donate.';

  @override
  String get fundraiserAnonymous => 'Anonymous';

  @override
  String get fundraiserDonateOnWeb => 'Donate on web';

  @override
  String get racesTitle => 'Race calendar';

  @override
  String get racesSearchPlaceholder => 'Search races by name…';

  @override
  String get racesNearPlace => 'Near a place…';

  @override
  String racesKmAway(String distance) {
    return '$distance away';
  }

  @override
  String get racesDistanceAny => 'Any distance';

  @override
  String get racesDistance5k => '5K';

  @override
  String get racesDistance10k => '10K';

  @override
  String get racesDistanceHalf => 'Half';

  @override
  String get racesDistanceMarathon => 'Marathon';

  @override
  String get racesDistanceUltra => 'Ultra';

  @override
  String get racesRegister => 'Register';

  @override
  String get racesViewResults => 'View results';

  @override
  String get racesImportResult => 'Import my result';

  @override
  String get racesSubmitRace => 'Add a race';

  @override
  String get racesUnverified => 'Unverified';

  @override
  String get racesEmpty => 'No races match these filters yet.';

  @override
  String get racesSearchFailed =>
      'Couldn\'t load races. Check your connection and try again.';

  @override
  String racesMatchPrompt(String name) {
    return 'Was this the $name? Import your official result.';
  }

  @override
  String get racesMatchConfirm => 'Import result';

  @override
  String get racesMatchDismiss => 'Not this race';

  @override
  String get racesImported => 'Official result imported.';

  @override
  String get racesOfficialResult => 'Official result';

  @override
  String get racesChipTime => 'Chip time';

  @override
  String get racesGunTime => 'Gun time';

  @override
  String get racesOverallPlace => 'Overall place';

  @override
  String get racesAgeGroupPlace => 'Age-group place';

  @override
  String get racesAgeGroup => 'Age group';

  @override
  String get racesBib => 'Bib';

  @override
  String get racesPasteResultHint =>
      'Enter your finishing details from the race\'s results page.';

  @override
  String get racesSave => 'Save';

  @override
  String get racesCancel => 'Cancel';

  @override
  String get racesEditorTitle => 'Add a race';

  @override
  String get racesFieldName => 'Race name';

  @override
  String get racesFieldDate => 'Date';

  @override
  String get racesFieldDistance => 'Distance (metres)';

  @override
  String get racesFieldLocation => 'Location';

  @override
  String get racesFieldEntryUrl => 'Registration link';

  @override
  String get racesFieldResultsUrl => 'Results link';

  @override
  String get racesSubmitFailed => 'Couldn\'t save the race. Please try again.';

  @override
  String get racesImportFailed =>
      'Couldn\'t import the result. Please try again.';

  @override
  String get navRaces => 'Races';

  @override
  String get integrationsRunsignup => 'RunSignUp';

  @override
  String get integrationsRunsignupConnect =>
      'Import race results from RunSignUp.';

  @override
  String get integrationsRunsignupOpen => 'Open the race calendar';

  @override
  String get integrationsRunsignupUnavailable =>
      'RunSignUp import isn\'t available yet. parkrun and manual paste still work.';

  @override
  String get integrationsChronotrack => 'ChronoTrack';

  @override
  String get integrationsChronotrackConnect =>
      'Import race results from ChronoTrack-timed events.';

  @override
  String get integrationsChronotrackOpen => 'Open the race calendar';

  @override
  String get integrationsChronotrackUnavailable =>
      'ChronoTrack import isn\'t available yet. parkrun and manual paste still work.';

  @override
  String get routeConditionsTitle => 'Conditions';

  @override
  String get routeConditionsReport => 'Report condition';

  @override
  String get routeConditionsReporting => 'Reporting…';

  @override
  String get routeConditionsReported => 'Condition reported';

  @override
  String get routeConditionsReportFailed => 'Could not report condition';

  @override
  String get routeConditionsEmpty => 'No condition reports yet.';

  @override
  String get routeConditionsLoading => 'Loading…';

  @override
  String get routeConditionsCancel => 'Cancel';

  @override
  String get routeConditionsDelete => 'Delete';

  @override
  String get routeConditionsDeleteTitle => 'Delete report?';

  @override
  String get routeConditionsDeleteConfirm =>
      'This removes the condition report permanently.';

  @override
  String get routeConditionsDeleteFailed => 'Could not delete report';

  @override
  String get routeConditionsKindLabel => 'Condition';

  @override
  String get routeConditionsSeverityLabel => 'Severity';

  @override
  String get routeConditionsNoteLabel => 'Note';

  @override
  String get routeConditionsNotePlaceholder => 'What will the next runner hit?';

  @override
  String routeConditionsAtDistance(String distance) {
    return 'at $distance';
  }

  @override
  String get routeConditionMuddy => 'Muddy';

  @override
  String get routeConditionFlooded => 'Flooded';

  @override
  String get routeConditionSnowIce => 'Snow / ice';

  @override
  String get routeConditionOvergrown => 'Overgrown';

  @override
  String get routeConditionClosed => 'Closed';

  @override
  String get routeConditionHazard => 'Hazard';

  @override
  String get routeConditionClear => 'Clear';

  @override
  String get routeConditionOther => 'Other';

  @override
  String get routeConditionSeverityInfo => 'Info';

  @override
  String get routeConditionSeverityCaution => 'Caution';

  @override
  String get routeConditionSeverityImpassable => 'Impassable';

  @override
  String get prefTurnByTurnCues => 'Turn-by-turn voice cues';

  @override
  String get prefTurnByTurnCuesSubtitle =>
      'Spoken turn directions while following a saved route';

  @override
  String ttsTurnLeftIn(String distance) {
    return 'In $distance, turn left';
  }

  @override
  String ttsTurnRightIn(String distance) {
    return 'In $distance, turn right';
  }

  @override
  String get ttsTurnLeftNow => 'Turn left';

  @override
  String get ttsTurnRightNow => 'Turn right';

  @override
  String get ttsSlightLeft => 'Bear left';

  @override
  String get ttsSlightRight => 'Bear right';

  @override
  String get ttsUturn => 'Make a U-turn';

  @override
  String routeOfflinePackDownloading(int done, int total) {
    return 'Caching map: $done / $total';
  }

  @override
  String get routeOfflinePackReady => 'Map saved for offline';

  @override
  String routeOfflinePackPartial(int done, int total) {
    return 'Map partly saved ($done / $total) — retry';
  }

  @override
  String get routeOfflinePackTooLarge =>
      'This route is too large to cache offline';

  @override
  String get badgesSectionTitle => 'Achievements';

  @override
  String get badgesSectionSubtitle => 'Milestones you\'ve earned';

  @override
  String get badgesEmpty => 'No badges yet — keep running.';

  @override
  String get badgesEmptyOther => 'No public badges yet.';

  @override
  String badgesEarnedOn(String date) {
    return 'Earned $date';
  }

  @override
  String badgesFeedEarned(String name, String badge) {
    return '$name earned the $badge badge';
  }

  @override
  String get badgesARunner => 'A runner';

  @override
  String get badgesTierBronze => 'Bronze';

  @override
  String get badgesTierSilver => 'Silver';

  @override
  String get badgesTierGold => 'Gold';

  @override
  String get badgesTierPlatinum => 'Platinum';

  @override
  String get badgesDistanceSingle5kLabel => 'First 5K';

  @override
  String get badgesDistanceSingle5kDesc => 'Ran 5 km in a single run';

  @override
  String get badgesDistanceSingleHalfLabel => 'Half marathon';

  @override
  String get badgesDistanceSingleHalfDesc => 'Ran 21.1 km in a single run';

  @override
  String get badgesDistanceSingleMarathonLabel => 'Marathon';

  @override
  String get badgesDistanceSingleMarathonDesc => 'Ran 42.2 km in a single run';

  @override
  String get badgesDistanceSingleUltraLabel => 'Ultra';

  @override
  String get badgesDistanceSingleUltraDesc =>
      'Ran 50 km or more in a single run';

  @override
  String get badgesDistanceLifetime100Label => '100 km club';

  @override
  String get badgesDistanceLifetime100Desc => '100 km logged all-time';

  @override
  String get badgesDistanceLifetime500Label => '500 km';

  @override
  String get badgesDistanceLifetime500Desc => '500 km logged all-time';

  @override
  String get badgesDistanceLifetime1000Label => '1,000 km club';

  @override
  String get badgesDistanceLifetime1000Desc => '1,000 km logged all-time';

  @override
  String get badgesDistanceLifetime5000Label => '5,000 km';

  @override
  String get badgesDistanceLifetime5000Desc => '5,000 km logged all-time';

  @override
  String get badgesStreak7Label => 'Week streak';

  @override
  String get badgesStreak7Desc => 'Ran 7 days in a row';

  @override
  String get badgesStreak30Label => 'Month streak';

  @override
  String get badgesStreak30Desc => 'Ran 30 days in a row';

  @override
  String get badgesStreak100Label => 'Century streak';

  @override
  String get badgesStreak100Desc => 'Ran 100 days in a row';

  @override
  String get badgesStreak365Label => 'Year streak';

  @override
  String get badgesStreak365Desc => 'Ran 365 days in a row';

  @override
  String get badgesPr1Label => 'First PR';

  @override
  String get badgesPr1Desc => 'Set your first personal record';

  @override
  String get badgesPr3Label => 'Triple PR';

  @override
  String get badgesPr3Desc => 'Hold personal records at 3 distances';

  @override
  String get badgesPr5Label => 'PR collector';

  @override
  String get badgesPr5Desc => 'Hold personal records at every distance';

  @override
  String get badgesPlan1Label => 'Plan finisher';

  @override
  String get badgesPlan1Desc => 'Completed a training plan';

  @override
  String get badgesPlan3Label => 'Triple finisher';

  @override
  String get badgesPlan3Desc => 'Completed 3 training plans';

  @override
  String get badgesPlan10Label => 'Plan veteran';

  @override
  String get badgesPlan10Desc => 'Completed 10 training plans';

  @override
  String get racePredictorTitle => 'Race-time predictor';

  @override
  String racePredictorAnchoredOn(String distance, String time) {
    return 'From your $distance effort in $time';
  }

  @override
  String get racePredictorColDistance => 'Distance';

  @override
  String get racePredictorColTime => 'Time';

  @override
  String get racePredictorColPace => 'Pace';

  @override
  String get racePredictorColConfidence => 'Confidence';

  @override
  String get racePredictorConfidenceHigh => 'High';

  @override
  String get racePredictorConfidenceModerate => 'Moderate';

  @override
  String get racePredictorConfidenceLow => 'Low';

  @override
  String get racePredictorConfReasonSimilar =>
      'Based on recent efforts close to this distance.';

  @override
  String get racePredictorConfReasonExtrapolated =>
      'Extrapolated across a large distance gap — treat as a ballpark.';

  @override
  String get racePredictorConfReasonStale =>
      'Anchored to an effort that\'s a few weeks old.';

  @override
  String get racePredictorConfReasonLimited => 'Based on limited recent data.';

  @override
  String get racePredictorFootnote =>
      'Riegel equivalence from your best recent effort, recency-weighted. Closer distances are more reliable.';

  @override
  String get settingsSectionDeveloper => 'Developer';

  @override
  String get settingsTabSimWatchSubtitle =>
      'Live status from the simulated custom watch';

  @override
  String get simWatchTitle => 'Sim watch link';

  @override
  String get simWatchHostLabel => 'Host';

  @override
  String get simWatchPortLabel => 'Port';

  @override
  String get simWatchConnect => 'Connect';

  @override
  String get simWatchConnecting => 'Connecting…';

  @override
  String get simWatchDisconnect => 'Disconnect';

  @override
  String simWatchConnectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get simWatchSyncAction => 'Sync runs from watch';

  @override
  String simWatchSyncing(int done, int total) {
    return 'Syncing… $done/$total';
  }

  @override
  String simWatchResult(int synced, int total) {
    return 'Synced $synced of $total run(s) from the watch';
  }

  @override
  String simWatchSyncFailed(String error) {
    return 'Watch sync failed: $error';
  }

  @override
  String get simWatchPushSettingsAction => 'Push settings to watch';

  @override
  String get simWatchSettingsPushed => 'Settings pushed to the watch';

  @override
  String simWatchPushSettingsFailed(String error) {
    return 'Settings push failed: $error';
  }

  @override
  String get simWatchNoRuns => 'No runs on the watch to sync';

  @override
  String get simWatchWaitingFrames => 'Connected — waiting for frames…';

  @override
  String get simWatchUptime => 'Watch uptime';

  @override
  String get simWatchNoFix => 'No GPS fix yet';

  @override
  String get simWatchPosition => 'Position';

  @override
  String get simWatchSpeed => 'Speed';

  @override
  String get simWatchSatellites => 'Satellites';

  @override
  String get simWatchAltitude => 'Altitude';

  @override
  String get simWatchBaroAltitude => 'Barometric altitude';

  @override
  String get simWatchAscent => 'Ascent';

  @override
  String get simWatchDescent => 'Descent';

  @override
  String get simWatchFixAge => 'Fix age';

  @override
  String simWatchSeconds(int seconds) {
    return '$seconds s';
  }
}
