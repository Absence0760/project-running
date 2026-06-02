import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('pt'),
    Locale('pt', 'BR'),
  ];

  /// Settings > Preferences row title for the language picker
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get prefsLanguage;

  /// Language-picker option that follows the device locale instead of an explicit choice
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get prefsLanguageSystem;

  /// Endonym for English — never translated, identical across all catalogs
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get localeNameEn;

  /// Endonym for German — never translated, identical across all catalogs
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get localeNameDe;

  /// Endonym for French — never translated, identical across all catalogs
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get localeNameFr;

  /// Endonym for Spanish — never translated, identical across all catalogs
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get localeNameEs;

  /// Endonym for Japanese — never translated, identical across all catalogs
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get localeNameJa;

  /// Endonym for Brazilian Portuguese — never translated, identical across all catalogs
  ///
  /// In en, this message translates to:
  /// **'Português (Brasil)'**
  String get localeNamePtBR;

  /// Bottom-nav label for the dashboard/home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom-nav label for the run-recording tab
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get navRun;

  /// Bottom-nav label for the run-history tab
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// Bottom-nav label for the social tab
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get navSocial;

  /// Bottom-nav label for the settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Settings landing section header grouping Account + Preferences
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsSectionProfile;

  /// Settings landing section header grouping Integrations + Devices + Gear
  ///
  /// In en, this message translates to:
  /// **'Apps & data'**
  String get settingsSectionAppsData;

  /// Settings landing section header grouping Pro & support + Licenses
  ///
  /// In en, this message translates to:
  /// **'Account & legal'**
  String get settingsSectionAccountLegal;

  /// Settings > Preferences section header for units, pace format, map style, language, theme
  ///
  /// In en, this message translates to:
  /// **'Units & display'**
  String get prefsSectionUnitsDisplay;

  /// Label for the email field on the sign-in and sign-up screens
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// Label for the password field on the sign-in and sign-up screens
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// Divider text between the email/password form and the OAuth buttons
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get authOrDivider;

  /// AppBar title for the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInTitle;

  /// Headline on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Sync runs across devices'**
  String get signInHeadline;

  /// Subtitle under the sign-in headline
  ///
  /// In en, this message translates to:
  /// **'Sign in to back up runs and view them on the web app.'**
  String get signInSubtitle;

  /// Primary submit button on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInButton;

  /// Forgot-password link on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get signInForgotPassword;

  /// Validation message shown when the user taps Forgot password without a valid email in the field
  ///
  /// In en, this message translates to:
  /// **'Enter your email above first, then tap Forgot password.'**
  String get signInResetNeedEmail;

  /// Privacy-preserving confirmation shown after requesting a password reset email
  ///
  /// In en, this message translates to:
  /// **'If that email is registered, we\'ve sent a reset link.'**
  String get signInResetSent;

  /// Apple OAuth button label on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get signInWithApple;

  /// Google OAuth button label on the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// Button to dismiss the sign-in screen and use the app without an account
  ///
  /// In en, this message translates to:
  /// **'Continue offline'**
  String get signInContinueOffline;

  /// Link from the sign-in screen to the sign-up screen
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Create one'**
  String get signInCreateAccountPrompt;

  /// AppBar title for the sign-up screen
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get signUpTitle;

  /// Headline on the sign-up screen
  ///
  /// In en, this message translates to:
  /// **'Start tracking your runs'**
  String get signUpHeadline;

  /// Subtitle under the sign-up headline
  ///
  /// In en, this message translates to:
  /// **'Create an account to back up runs and view them on the web app.'**
  String get signUpSubtitle;

  /// Primary submit button on the sign-up screen
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get signUpButton;

  /// Checkbox label for the age-confirmation gate on sign-up (GDPR Art 8)
  ///
  /// In en, this message translates to:
  /// **'I am 16 years of age or older'**
  String get signUpConfirmAge;

  /// Leading text of the terms-acceptance checkbox label, before the Terms of Service link
  ///
  /// In en, this message translates to:
  /// **'I accept the '**
  String get signUpAcceptPrefix;

  /// Tappable Terms of Service link text inside the terms-acceptance checkbox label
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get signUpTermsLink;

  /// Conjunction between the Terms of Service and Privacy Policy links in the terms-acceptance checkbox label
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get signUpAcceptConjunction;

  /// Tappable Privacy Policy link text inside the terms-acceptance checkbox label
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get signUpPrivacyLink;

  /// Validation error shown when the age gate is not confirmed
  ///
  /// In en, this message translates to:
  /// **'Please confirm you are 16 or older to continue.'**
  String get signUpErrorConfirmAge;

  /// Validation error shown when the terms gate is not accepted
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms of Service and Privacy Policy to continue.'**
  String get signUpErrorAcceptTerms;

  /// Apple OAuth button label on the sign-up screen
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get signUpContinueWithApple;

  /// Google OAuth button label on the sign-up screen
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get signUpContinueWithGoogle;

  /// Link from the sign-up screen back to the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get signUpSignInPrompt;

  /// Banner shown when a legal-document link (Terms / Privacy) fails to open
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String signUpCouldNotOpen(String url);

  /// Title of the first onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Track every run'**
  String get onboardingTrackTitle;

  /// Body of the first onboarding slide
  ///
  /// In en, this message translates to:
  /// **'GPS recording with live map, splits, pace, cadence, and elevation. Works fully offline — sign in later to sync across devices.'**
  String get onboardingTrackBody;

  /// Title of the second onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Follow routes'**
  String get onboardingRoutesTitle;

  /// Body of the second onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Import GPX or KML files, or sync routes from the web app. Get off-route alerts while you run.'**
  String get onboardingRoutesBody;

  /// Title of the location-disclosure onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Location access'**
  String get onboardingLocationTitle;

  /// Play-policy background-location disclosure body on the location onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Threkir records your runs by sampling your GPS location while the app is in the foreground AND in the background (so it keeps tracking when your screen is off or you switch apps to take a photo). Location data is stored on your device and only uploaded to Threkir\'s servers when you choose to share or sync a run. If you decline background location, runs will stop recording the moment you switch away from the app — you can change this later in Settings → Apps → Threkir → Permissions.'**
  String get onboardingLocationBody;

  /// Title of the privacy-default chooser onboarding page
  ///
  /// In en, this message translates to:
  /// **'Who sees your runs?'**
  String get onboardingPrivacyTitle;

  /// Body of the privacy-default chooser onboarding page
  ///
  /// In en, this message translates to:
  /// **'Pick a default for new runs. You can change it any time in Settings, and override it on any single run.'**
  String get onboardingPrivacyBody;

  /// Bottom button label on the final onboarding page
  ///
  /// In en, this message translates to:
  /// **'Grant permission'**
  String get onboardingGrantPermission;

  /// Bottom button label advancing to the next onboarding page
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Title of the Private visibility default option
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privacyPrivateTitle;

  /// Subtitle of the Private visibility default option
  ///
  /// In en, this message translates to:
  /// **'Only you can see your runs. You can share any run later.'**
  String get privacyPrivateSubtitle;

  /// Title of the Followers visibility default option
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get privacyFollowersTitle;

  /// Subtitle of the Followers visibility default option
  ///
  /// In en, this message translates to:
  /// **'People who follow you see new runs in their feed.'**
  String get privacyFollowersSubtitle;

  /// Title of the Public visibility default option
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get privacyPublicTitle;

  /// Subtitle of the Public visibility default option
  ///
  /// In en, this message translates to:
  /// **'Anyone can find and view your runs.'**
  String get privacyPublicSubtitle;

  /// Label on the big circular start-run button on the idle run screen
  ///
  /// In en, this message translates to:
  /// **'START'**
  String get runStart;

  /// Screen-reader label for the start-run button
  ///
  /// In en, this message translates to:
  /// **'Start run'**
  String get runStartA11yLabel;

  /// Idle-screen button to pick a route to follow when no route is selected
  ///
  /// In en, this message translates to:
  /// **'Choose route'**
  String get runChooseRoute;

  /// Idle-screen button to change the selected route
  ///
  /// In en, this message translates to:
  /// **'Change route'**
  String get runChangeRoute;

  /// Idle-screen button that shares a live spectator link for the run
  ///
  /// In en, this message translates to:
  /// **'Share live link'**
  String get runShareLiveLink;

  /// Idle-screen button opening the training-plans list when no active plan exists
  ///
  /// In en, this message translates to:
  /// **'Training plans'**
  String get runTrainingPlans;

  /// Hint shown during the pre-run countdown — tapping anywhere aborts the start
  ///
  /// In en, this message translates to:
  /// **'Tap to cancel'**
  String get runTapToCancel;

  /// Empty-state encouragement on the idle run screen when there is no recent run, event, or plan
  ///
  /// In en, this message translates to:
  /// **'Your first run is one tap away.'**
  String get runFirstRunPrompt;

  /// Label on the last-run card when the recorded distance is negligible (treated as a generic activity)
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get runLastActivity;

  /// Label on the last-run card on the idle run screen
  ///
  /// In en, this message translates to:
  /// **'Last run'**
  String get runLastRun;

  /// Uppercase label on the route-preview card indicating the run will follow this route
  ///
  /// In en, this message translates to:
  /// **'FOLLOWING'**
  String get runFollowing;

  /// Fallback name for a live race when the event has no title
  ///
  /// In en, this message translates to:
  /// **'Race'**
  String get runRaceFallbackTitle;

  /// Status label on the race banner when the race is armed but not yet started
  ///
  /// In en, this message translates to:
  /// **'Race armed'**
  String get runRaceArmed;

  /// Status label on the race banner when the race is running
  ///
  /// In en, this message translates to:
  /// **'Race LIVE'**
  String get runRaceLive;

  /// Race banner subtitle while armed, awaiting the start signal
  ///
  /// In en, this message translates to:
  /// **'{label} — waiting for GO'**
  String runRaceWaitingForGo(String label);

  /// Race banner subtitle while running, showing elapsed time and prompting the user to start
  ///
  /// In en, this message translates to:
  /// **'{label} — {elapsed} elapsed · tap Start'**
  String runRaceElapsedTapStart(String label, String elapsed);

  /// Heading on the finished-run summary screen
  ///
  /// In en, this message translates to:
  /// **'Run Complete'**
  String get runComplete;

  /// Stat label for distance on the recording overlay and finish summary
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get runStatDistance;

  /// Stat label for elapsed time on the finish summary
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get runStatTime;

  /// Stat label for moving time (elapsed minus stops) on the finish summary
  ///
  /// In en, this message translates to:
  /// **'Moving'**
  String get runStatMoving;

  /// Stat label for pace
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get runStatPace;

  /// Stat label for speed (cycling activities)
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get runStatSpeed;

  /// Stat label for average pace on the recording overlay
  ///
  /// In en, this message translates to:
  /// **'Avg Pace'**
  String get runStatAvgPace;

  /// Stat label for average speed (cycling activities)
  ///
  /// In en, this message translates to:
  /// **'Avg Speed'**
  String get runStatAvgSpeed;

  /// Stat label for estimated calories burned
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get runStatCalories;

  /// Stat label for elevation gain
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get runStatElevation;

  /// Stat label for step count
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get runStatSteps;

  /// Stat label for cadence (steps per minute)
  ///
  /// In en, this message translates to:
  /// **'Cadence'**
  String get runStatCadence;

  /// Stat label for heart rate
  ///
  /// In en, this message translates to:
  /// **'Heart Rate'**
  String get runStatHeartRate;

  /// Unit suffix for the calories stat
  ///
  /// In en, this message translates to:
  /// **'kcal'**
  String get runUnitKcal;

  /// Unit suffix for the elevation stat (metres)
  ///
  /// In en, this message translates to:
  /// **'m'**
  String get runUnitMetres;

  /// Unit suffix for the cadence stat (steps per minute)
  ///
  /// In en, this message translates to:
  /// **'spm'**
  String get runUnitSpm;

  /// Unit suffix for the heart-rate stat (beats per minute)
  ///
  /// In en, this message translates to:
  /// **'bpm'**
  String get runUnitBpm;

  /// Toggle on the recording overlay to silence spoken pace cues for this run
  ///
  /// In en, this message translates to:
  /// **'Mute pace cues'**
  String get runMutePaceCues;

  /// State of the pace-cue toggle when spoken pace cues are silenced
  ///
  /// In en, this message translates to:
  /// **'Pace cues muted'**
  String get runPaceCuesMuted;

  /// Status on the finish summary when the run uploaded successfully
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get runSynced;

  /// Status on the finish summary while the run is uploading
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get runSyncing;

  /// Button on the finish summary that dismisses back to the idle run screen
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get runDone;

  /// Screen-reader label for the discard-run control on the recording overlay
  ///
  /// In en, this message translates to:
  /// **'Discard run'**
  String get runDiscardA11yLabel;

  /// Screen-reader hint for the discard-run control
  ///
  /// In en, this message translates to:
  /// **'Throws away the current recording without saving'**
  String get runDiscardA11yHint;

  /// Screen-reader label for the pause/resume control when paused
  ///
  /// In en, this message translates to:
  /// **'Resume run'**
  String get runResumeA11yLabel;

  /// Screen-reader label for the pause/resume control when running
  ///
  /// In en, this message translates to:
  /// **'Pause run'**
  String get runPauseA11yLabel;

  /// Screen-reader hint for the resume control
  ///
  /// In en, this message translates to:
  /// **'Resumes the paused recording'**
  String get runResumeA11yHint;

  /// Screen-reader hint for the pause control
  ///
  /// In en, this message translates to:
  /// **'Pauses the recording without ending it'**
  String get runPauseA11yHint;

  /// Screen-reader label for the mark-lap control when no laps yet
  ///
  /// In en, this message translates to:
  /// **'Mark lap'**
  String get runMarkLapA11yLabel;

  /// Screen-reader label for the mark-lap control, including the count of laps marked so far
  ///
  /// In en, this message translates to:
  /// **'Mark lap, {count} so far'**
  String runMarkLapWithCountA11yLabel(int count);

  /// Screen-reader hint for the mark-lap control
  ///
  /// In en, this message translates to:
  /// **'Records the current split'**
  String get runMarkLapA11yHint;

  /// Screen-reader label for the drag handle when the stats panel is expanded
  ///
  /// In en, this message translates to:
  /// **'Collapse stats panel'**
  String get runCollapseStatsPanel;

  /// Screen-reader label for the drag handle when the stats panel is collapsed
  ///
  /// In en, this message translates to:
  /// **'Expand stats panel'**
  String get runExpandStatsPanel;

  /// Badge showing remaining distance to the end of the selected route
  ///
  /// In en, this message translates to:
  /// **'{distance} to go'**
  String runRouteRemaining(String distance);

  /// Banner shown when the runner has strayed from the selected route
  ///
  /// In en, this message translates to:
  /// **'Off route — {metres}m away'**
  String runOffRoute(int metres);

  /// Banner shown when location permission is turned off mid-run
  ///
  /// In en, this message translates to:
  /// **'Location permission revoked'**
  String get runPermissionRevoked;

  /// Banner shown when GPS fixes stop arriving mid-run
  ///
  /// In en, this message translates to:
  /// **'GPS signal lost — move to open sky'**
  String get runGpsLost;

  /// Banner shown when GPS accuracy is too low and distance stops advancing
  ///
  /// In en, this message translates to:
  /// **'Weak GPS — distance paused'**
  String get runWeakGps;

  /// Screen-reader status announcement when recording begins
  ///
  /// In en, this message translates to:
  /// **'Run started'**
  String get runA11yStarted;

  /// Screen-reader status announcement when a paused run resumes
  ///
  /// In en, this message translates to:
  /// **'Run resumed'**
  String get runA11yResumed;

  /// Screen-reader status announcement when a run is paused
  ///
  /// In en, this message translates to:
  /// **'Run paused'**
  String get runA11yPaused;

  /// Screen-reader status announcement when a run finishes
  ///
  /// In en, this message translates to:
  /// **'Run finished'**
  String get runA11yFinished;

  /// Banner and screen-reader announcement when a lap is recorded
  ///
  /// In en, this message translates to:
  /// **'Lap {count} marked'**
  String runLapMarked(int count);

  /// Title of the confirm-discard dialog shown mid-run
  ///
  /// In en, this message translates to:
  /// **'Discard run?'**
  String get runDiscardDialogTitle;

  /// Body of the confirm-discard dialog shown mid-run
  ///
  /// In en, this message translates to:
  /// **'Your progress will be lost.'**
  String get runDiscardDialogBody;

  /// Cancel action on the confirm-discard dialog
  ///
  /// In en, this message translates to:
  /// **'Keep running'**
  String get runKeepRunning;

  /// Confirm action on the confirm-discard dialog
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get runDiscard;

  /// Option in the workout-entry sheet to begin a structured workout
  ///
  /// In en, this message translates to:
  /// **'Start workout'**
  String get runStartWorkout;

  /// Subtitle of the Start-workout option in the workout-entry sheet
  ///
  /// In en, this message translates to:
  /// **'Run with live step targets, audio cues, and a planned-vs-actual review.'**
  String get runStartWorkoutSubtitle;

  /// Option in the workout-entry sheet to open the workout detail screen
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get runViewWorkoutDetails;

  /// Banner shown when a selected workout has no runnable steps
  ///
  /// In en, this message translates to:
  /// **'This workout has no runnable structure.'**
  String get runWorkoutNoStructure;

  /// Banner shown when a structured workout is loaded and ready to start
  ///
  /// In en, this message translates to:
  /// **'Workout loaded · {count, plural, one{{count} step} other{{count} steps}} — tap GO to start'**
  String runWorkoutLoaded(int count);

  /// Title of the confirm-abandon-workout dialog
  ///
  /// In en, this message translates to:
  /// **'Abandon workout?'**
  String get runAbandonWorkoutTitle;

  /// Body of the confirm-abandon-workout dialog
  ///
  /// In en, this message translates to:
  /// **'The structured plan stops here; the recorder keeps running as a free run. You can stop anytime to save what you did.'**
  String get runAbandonWorkoutBody;

  /// Generic cancel action in run-screen dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runCancel;

  /// Confirm action on the abandon-workout dialog
  ///
  /// In en, this message translates to:
  /// **'Abandon'**
  String get runAbandon;

  /// Banner shown when the user taps Choose route but has no saved routes
  ///
  /// In en, this message translates to:
  /// **'No routes saved. Import one from the Routes tab.'**
  String get runNoRoutesSaved;

  /// One-time hint shown when notification permission is denied at run start
  ///
  /// In en, this message translates to:
  /// **'Notifications are off — the live run notification won\'t show. Recording still works.'**
  String get runNotificationsOffHint;

  /// Action label on banners that deep-link to system or app settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get runSettings;

  /// Dismiss action on the background-location nudge dialog — start the run without granting all-time location
  ///
  /// In en, this message translates to:
  /// **'Start anyway'**
  String get runStartAnyway;

  /// Confirm action on dialogs that deep-link to app settings
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get runOpenSettings;

  /// Dismiss action on the battery-optimisation hint dialog
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get runNotNow;

  /// Subject line of the OS share sheet when sharing a live run link
  ///
  /// In en, this message translates to:
  /// **'Track me live'**
  String get runShareSubject;

  /// Banner shown when sharing the live link fails
  ///
  /// In en, this message translates to:
  /// **'Could not share live link: {error}'**
  String runCouldNotShareLink(String error);

  /// Banner shown when the BLE heart-rate strap drops and is reconnecting
  ///
  /// In en, this message translates to:
  /// **'Heart-rate strap lost — reconnecting…'**
  String get runHrStrapLostReconnecting;

  /// Banner shown when the BLE heart-rate strap reconnects
  ///
  /// In en, this message translates to:
  /// **'Heart-rate strap reconnected'**
  String get runHrStrapReconnected;

  /// Banner shown when the BLE heart-rate strap drops and does not reconnect
  ///
  /// In en, this message translates to:
  /// **'Heart-rate strap lost — recording continues without HR.'**
  String get runHrStrapLostNoHr;

  /// Banner shown when the BLE heart-rate strap was not found at launch
  ///
  /// In en, this message translates to:
  /// **'Heart-rate strap not found — put it on, then reconnect.'**
  String get runHrStrapNotFound;

  /// Action label to manually reconnect the heart-rate strap
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get runReconnect;

  /// Banner shown when a manual heart-rate strap reconnect attempt fails
  ///
  /// In en, this message translates to:
  /// **'Still no strap — recording continues without HR.'**
  String get runHrStrapStillNotFound;

  /// Finish-summary error shown when the local save of a run failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save locally. Relaunch the app to recover.'**
  String get runSaveFailedRelaunch;

  /// Finish-summary status shown when cloud sync failed but the run is saved locally
  ///
  /// In en, this message translates to:
  /// **'Saved offline. Sync from Runs.'**
  String get runSyncFailedSaveOffline;

  /// Finish-summary status shown when the user is signed out and the run is saved locally only
  ///
  /// In en, this message translates to:
  /// **'Saved offline.'**
  String get runSavedOffline;

  /// Banner shown at each split/distance tick during a run, showing total distance and current pace or speed
  ///
  /// In en, this message translates to:
  /// **'{distance} — {pace}'**
  String runSplitTick(String distance, String pace);

  /// Banner shown when location services are disabled at run start
  ///
  /// In en, this message translates to:
  /// **'No GPS — tracking will start when Location is on.'**
  String get runGpsNoServiceSettings;

  /// Banner shown when location permission is permanently denied at run start
  ///
  /// In en, this message translates to:
  /// **'No GPS — permission is blocked. Enable it to track route.'**
  String get runGpsBlockedSettings;

  /// Banner shown when location permission is denied (not permanently) at run start
  ///
  /// In en, this message translates to:
  /// **'No GPS — tracking will start when permission is granted.'**
  String get runGpsPermissionPending;

  /// Banner shown when only while-in-use location permission is granted at run start
  ///
  /// In en, this message translates to:
  /// **'Set Location to \"Allow all the time\" — runs stop recording when you switch apps without background permission.'**
  String get runGpsAllowAllTheTime;

  /// Banner shown when the GPS sensor could not start for an unknown reason
  ///
  /// In en, this message translates to:
  /// **'Recording without GPS — could not start the sensor.'**
  String get runGpsSensorFailed;

  /// Relative-time label for an event within the last minute
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get runAgoJustNow;

  /// Relative-time label in minutes
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String runAgoMinutes(int count);

  /// Relative-time label in hours
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} hour ago} other{{count} hours ago}}'**
  String runAgoHours(int count);

  /// Relative-time label for one day ago
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get runAgoYesterday;

  /// Relative-time label in days (2-6 days)
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String runAgoDays(int count);

  /// Relative-time label in weeks
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} week ago} other{{count} weeks ago}}'**
  String runAgoWeeks(int count);

  /// Relative-time label in months
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} month ago} other{{count} months ago}}'**
  String runAgoMonths(int count);

  /// Workout-execution band text after the structured workout is abandoned
  ///
  /// In en, this message translates to:
  /// **'Workout abandoned · running freely'**
  String get runWorkoutAbandonedBand;

  /// Workout-execution band text when all steps are complete
  ///
  /// In en, this message translates to:
  /// **'Workout complete · tap stop to save'**
  String get runWorkoutCompleteBand;

  /// Workout-execution band header: step label, target distance/duration, and target pace
  ///
  /// In en, this message translates to:
  /// **'{label} · {target} @ {pace}'**
  String runWorkoutStepHeader(String label, String target, String pace);

  /// Workout-execution band step counter (current step of total)
  ///
  /// In en, this message translates to:
  /// **'{current}/{total}'**
  String runWorkoutStepCounter(int current, int total);

  /// Button to step back to the previous workout step
  ///
  /// In en, this message translates to:
  /// **'Rewind'**
  String get runWorkoutRewind;

  /// Button to skip to the next workout step
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get runWorkoutSkip;

  /// Button to abandon the structured workout and continue as a free run
  ///
  /// In en, this message translates to:
  /// **'Abandon'**
  String get runWorkoutAbandon;

  /// Workout-execution band remaining-distance label in yards
  ///
  /// In en, this message translates to:
  /// **'{yards} yd to go'**
  String runWorkoutRemainingYards(int yards);

  /// Workout-execution band remaining-distance label in metres
  ///
  /// In en, this message translates to:
  /// **'{metres} m to go'**
  String runWorkoutRemainingMetres(int metres);

  /// Workout-execution band remaining-time label for duration-based steps
  ///
  /// In en, this message translates to:
  /// **'{duration} to go'**
  String runWorkoutRemainingDuration(String duration);

  /// History date-range option / header label for runs from today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get runsRangeToday;

  /// History date-range option / header label for runs from the current week
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get runsRangeWeek;

  /// History date-range option / header label for runs from the last 30 days
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get runsRangeMonth;

  /// History date-range option / header label for runs from the current year
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get runsRangeYear;

  /// History date-range option / header label for all runs ever
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get runsRangeAll;

  /// History date-range option for picking a custom date range
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get runsRangeCustom;

  /// History header label for an open-ended custom range with only a start date
  ///
  /// In en, this message translates to:
  /// **'From {date}'**
  String runsRangeFrom(String date);

  /// History header label for an open-ended custom range with only an end date
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String runsRangeUntil(String date);

  /// Run-count chip next to the date-range label in the History AppBar title
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run} other{{count} runs}}'**
  String runsCount(int count);

  /// Tooltip on the History AppBar date-range picker button
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get runsDateRangeTooltip;

  /// Tooltip on the History AppBar sort button
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get runsSortTooltip;

  /// History sort option: newest runs first
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get runsSortNewest;

  /// History sort option: oldest runs first
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get runsSortOldest;

  /// History sort option: longest distance first
  ///
  /// In en, this message translates to:
  /// **'Longest distance'**
  String get runsSortLongest;

  /// History sort option: fastest pace first
  ///
  /// In en, this message translates to:
  /// **'Best pace'**
  String get runsSortFastest;

  /// Tooltip on the History AppBar sync button, showing how many runs are queued
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Sync {count} run} other{Sync {count} runs}}'**
  String runsSyncTooltip(int count);

  /// Tooltip on the History AppBar cloud-refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh from cloud'**
  String get runsRefreshTooltip;

  /// Tooltip on the disabled cloud icon when signed out
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get runsOfflineTooltip;

  /// AppBar title in History multi-select mode, showing how many runs are selected
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String runsSelectionTitle(int count);

  /// Tooltip on the select-all button in History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get runsSelectAllTooltip;

  /// Tooltip on the clear-selection button in History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get runsClearSelectionTooltip;

  /// Tooltip on the delete button in History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get runsDeleteTooltip;

  /// Tooltip on the cancel button that exits History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runsCancelTooltip;

  /// Label on the floating action button that opens the manual add-run form
  ///
  /// In en, this message translates to:
  /// **'Add run'**
  String get runsAddRun;

  /// Tooltip on the add-run floating action button
  ///
  /// In en, this message translates to:
  /// **'Add a run manually'**
  String get runsAddRunTooltip;

  /// Button at the bottom of the runs list that reveals the next page of runs
  ///
  /// In en, this message translates to:
  /// **'Load {count} more'**
  String runsLoadMore(int count);

  /// Empty-state shown when the active filters exclude every run
  ///
  /// In en, this message translates to:
  /// **'No runs match these filters'**
  String get runsNoMatch;

  /// Button to reset all History filters when none match
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get runsClearFilters;

  /// Empty-state title shown when the store has no runs at all
  ///
  /// In en, this message translates to:
  /// **'No runs yet'**
  String get runsEmptyTitle;

  /// Empty-state body shown when the store has no runs at all
  ///
  /// In en, this message translates to:
  /// **'Tap the Run tab to start your first run'**
  String get runsEmptyBody;

  /// Activity filter chip that clears the activity filter (shows all activities)
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get runsFilterAll;

  /// Source-filter option that clears the source filter
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get runsSourceAll;

  /// Label on the History source-filter dropdown, showing the active source
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String runsSourceLabel(String source);

  /// Tooltip on the History source-filter dropdown
  ///
  /// In en, this message translates to:
  /// **'Filter by source'**
  String get runsSourceFilterTooltip;

  /// Source-filter label for runs recorded in-app
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get runsSourceRecorded;

  /// Source-filter label for runs recorded on a paired watch
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get runsSourceWatch;

  /// Source-filter label for runs imported from Strava — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'Strava'**
  String get runsSourceStrava;

  /// Source-filter label for parkrun-imported runs — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'parkrun'**
  String get runsSourceParkrun;

  /// Source-filter label for HealthKit-imported runs — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'HealthKit'**
  String get runsSourceHealthKit;

  /// Source-filter label for Health Connect-imported runs — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'Health Connect'**
  String get runsSourceHealthConnect;

  /// Title of the custom date-range picker bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Select dates'**
  String get runsRangePickerTitle;

  /// Label on the start-date chip in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get runsRangeStart;

  /// Label on the end-date chip in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get runsRangeEnd;

  /// Placeholder on an unset endpoint chip in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Tap a date'**
  String get runsRangeTapDate;

  /// Apply button in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get runsRangeApply;

  /// Clear button in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get runsRangeClear;

  /// Tooltip on the previous-month chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get runsPrevMonth;

  /// Tooltip on the next-month chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get runsNextMonth;

  /// Tooltip on the previous-year chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Previous year'**
  String get runsPrevYear;

  /// Tooltip on the next-year chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Next year'**
  String get runsNextYear;

  /// Title of the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete {count} run?} other{Delete {count} runs?}}'**
  String runsDeleteConfirmTitle(int count);

  /// Body of the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get runsDeleteConfirmBody;

  /// Cancel action in the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runsCancel;

  /// Confirm action in the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get runsDelete;

  /// Tooltip on the per-row unsynced icon in the runs list
  ///
  /// In en, this message translates to:
  /// **'Queued to sync'**
  String get runsQueuedToSync;

  /// Banner shown when tapping sync while signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in from Settings to sync runs'**
  String get runsSignInToSync;

  /// Banner shown when a cloud refresh of the runs list fails
  ///
  /// In en, this message translates to:
  /// **'Could not refresh — check your connection'**
  String get runsRefreshFailed;

  /// Banner shown when loading the next page of runs fails
  ///
  /// In en, this message translates to:
  /// **'Could not load more runs'**
  String get runsLoadMoreFailed;

  /// Banner shown after a sync that partially failed
  ///
  /// In en, this message translates to:
  /// **'Synced {synced}/{total}. Error: {error}'**
  String runsSyncPartial(int synced, int total, String error);

  /// Detail message (used as the error in runsSyncPartial) when some runs' track uploads fail during a manual sync
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run failed to upload its GPS track — the rest were synced. It will retry on the next cycle.} other{{count} runs failed to upload their GPS track — the rest were synced. The failed runs will retry on the next cycle.}}'**
  String runsSyncTrackFailed(int count);

  /// Banner shown after every unsynced run uploads successfully
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run synced} other{All {count} runs synced}}'**
  String runsSyncAllDone(int count);

  /// Banner shown when some runs deleted but others were queued for retry
  ///
  /// In en, this message translates to:
  /// **'{deleted} deleted; {queued} queued — will retry when back online.'**
  String runsDeletePartial(int deleted, int queued);

  /// Banner shown after a successful bulk delete
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Deleted {count} run} other{Deleted {count} runs}}'**
  String runsDeleteDone(int count);

  /// AppBar title for the manual add-run form
  ///
  /// In en, this message translates to:
  /// **'Add run'**
  String get addRunTitle;

  /// AppBar save button on the manual add-run form
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get addRunSave;

  /// Section header for the date/time pickers on the add-run form
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get addRunSectionWhen;

  /// Section header for the activity-type chips on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get addRunSectionActivity;

  /// Section header for the optional route picker on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Route (optional)'**
  String get addRunSectionRoute;

  /// Section header for the distance field on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get addRunSectionDistance;

  /// Section header for the duration fields on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get addRunSectionDuration;

  /// Section header for the optional title field on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get addRunSectionTitle;

  /// Section header for the optional notes field on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get addRunSectionNotes;

  /// Tooltip on the button that clears the selected route on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Clear route'**
  String get addRunClearRoute;

  /// Placeholder in the route picker field when no route is selected
  ///
  /// In en, this message translates to:
  /// **'Search saved routes'**
  String get addRunSearchRoutes;

  /// Empty-state hint shown in the route section when the user has no saved routes
  ///
  /// In en, this message translates to:
  /// **'No saved routes yet — build or import one to attach it here'**
  String get addRunNoRoutes;

  /// Validation error for the distance field on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Enter a distance greater than 0'**
  String get addRunDistanceInvalid;

  /// Validation error for the duration fields on the add-run form
  ///
  /// In en, this message translates to:
  /// **'Enter a duration'**
  String get addRunDurationInvalid;

  /// Hint text in the title field on the add-run form
  ///
  /// In en, this message translates to:
  /// **'e.g. Lunchtime loop'**
  String get addRunTitleHint;

  /// Hint text in the notes field on the add-run form
  ///
  /// In en, this message translates to:
  /// **'How did it feel?'**
  String get addRunNotesHint;

  /// Primary save button at the bottom of the add-run form
  ///
  /// In en, this message translates to:
  /// **'Save run'**
  String get addRunSaveButton;

  /// Banner shown when saving a manual run fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save run: {error}'**
  String addRunSaveFailed(String error);

  /// Banner shown after a manual run is saved
  ///
  /// In en, this message translates to:
  /// **'Run added to history'**
  String get addRunSaved;

  /// Search-field hint in the full-screen route picker
  ///
  /// In en, this message translates to:
  /// **'Search routes'**
  String get addRunPickerSearchHint;

  /// Tooltip on the clear-search button in the route picker
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get addRunPickerClear;

  /// Tooltip on the close button in the route picker
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get addRunPickerCancel;

  /// Empty-state in the route picker when the search matches nothing
  ///
  /// In en, this message translates to:
  /// **'No routes match \"{query}\"'**
  String addRunPickerNoMatch(String query);

  /// Leading option in the route picker that attaches no route
  ///
  /// In en, this message translates to:
  /// **'No route'**
  String get addRunPickerNoRoute;

  /// Did-not-finish badge in the run-detail AppBar title — abbreviation, usually left as DNF
  ///
  /// In en, this message translates to:
  /// **'DNF'**
  String get runDetailDnfBadge;

  /// Tooltip on the edit-run button in the run-detail AppBar
  ///
  /// In en, this message translates to:
  /// **'Edit run'**
  String get runDetailEditTooltip;

  /// Tooltip on the share-run button in the run-detail AppBar
  ///
  /// In en, this message translates to:
  /// **'Share run'**
  String get runDetailShareTooltip;

  /// Tooltip on the overflow menu in the run-detail AppBar
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get runDetailMoreTooltip;

  /// Overflow-menu / dialog title action to save the run's track as a reusable route
  ///
  /// In en, this message translates to:
  /// **'Save as route'**
  String get runDetailSaveAsRoute;

  /// Overflow-menu action to delete the run
  ///
  /// In en, this message translates to:
  /// **'Delete run'**
  String get runDetailDeleteRun;

  /// Title of the edit-run dialog
  ///
  /// In en, this message translates to:
  /// **'Edit run'**
  String get runDetailEditTitle;

  /// Label for the title field in the edit-run dialog
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get runDetailFieldTitle;

  /// Label for the notes field in the edit-run dialog
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get runDetailFieldNotes;

  /// Label for the distance field in the edit-run dialog
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get runDetailFieldDistance;

  /// Label for the duration fields in the edit-run dialog
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get runDetailFieldDuration;

  /// Checkbox label in the edit-run dialog to mark the run did-not-finish
  ///
  /// In en, this message translates to:
  /// **'Mark as DNF'**
  String get runDetailMarkDnf;

  /// Subtitle under the DNF checkbox in the edit-run dialog
  ///
  /// In en, this message translates to:
  /// **'Excludes this run from personal records'**
  String get runDetailMarkDnfSubtitle;

  /// Banner shown when the edit-run dialog has invalid distance/duration
  ///
  /// In en, this message translates to:
  /// **'Enter a valid distance and duration'**
  String get runDetailEditInvalid;

  /// Save action in run-detail dialogs
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get runDetailSave;

  /// Cancel action in run-detail dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runDetailCancel;

  /// Confirm action in the delete-run dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get runDetailDelete;

  /// Overlay shown on the run-detail map while the GPS track downloads
  ///
  /// In en, this message translates to:
  /// **'Loading GPS data...'**
  String get runDetailLoadingGps;

  /// Overlay shown on the run-detail map when the track can't be fetched offline
  ///
  /// In en, this message translates to:
  /// **'GPS track unavailable offline'**
  String get runDetailGpsUnavailable;

  /// Tooltip on the trace-replay button while replaying
  ///
  /// In en, this message translates to:
  /// **'Pause replay'**
  String get runDetailPauseReplay;

  /// Tooltip on the trace-replay button while idle
  ///
  /// In en, this message translates to:
  /// **'Replay this run'**
  String get runDetailReplay;

  /// Secondary-stat label for elevation gain on run-detail
  ///
  /// In en, this message translates to:
  /// **'Elev Gain'**
  String get runDetailStatElevGain;

  /// Secondary-stat label for elevation loss on run-detail
  ///
  /// In en, this message translates to:
  /// **'Elev Loss'**
  String get runDetailStatElevLoss;

  /// Secondary-stat label for average heart rate on run-detail
  ///
  /// In en, this message translates to:
  /// **'Avg HR'**
  String get runDetailStatAvgHr;

  /// Secondary-stat label for parkrun age-graded percentage on run-detail
  ///
  /// In en, this message translates to:
  /// **'Age grade'**
  String get runDetailStatAgeGrade;

  /// Section header for the elevation chart on run-detail
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get runDetailSectionElevation;

  /// Section header for the laps list on run-detail
  ///
  /// In en, this message translates to:
  /// **'Laps'**
  String get runDetailSectionLaps;

  /// Title of a per-lap row on run-detail
  ///
  /// In en, this message translates to:
  /// **'Lap {number}'**
  String runDetailLapNumber(int number);

  /// Section header for Garmin running-dynamics metrics on run-detail
  ///
  /// In en, this message translates to:
  /// **'Running Dynamics'**
  String get runDetailSectionRunningDynamics;

  /// Running-dynamics row label for vertical oscillation
  ///
  /// In en, this message translates to:
  /// **'Vertical oscillation'**
  String get runDetailDynVerticalOsc;

  /// Running-dynamics row label for ground-contact time
  ///
  /// In en, this message translates to:
  /// **'Ground contact'**
  String get runDetailDynGroundContact;

  /// Running-dynamics row label for stride length
  ///
  /// In en, this message translates to:
  /// **'Stride length'**
  String get runDetailDynStrideLength;

  /// Running-dynamics row label for average running power
  ///
  /// In en, this message translates to:
  /// **'Avg power'**
  String get runDetailDynAvgPower;

  /// Section header for the route-comparison card on run-detail
  ///
  /// In en, this message translates to:
  /// **'Route History'**
  String get runDetailSectionRouteHistory;

  /// Fallback name used when the linked route has no name, in the route-history card
  ///
  /// In en, this message translates to:
  /// **'this route'**
  String get runDetailThisRoute;

  /// Route-history card line shown when this run is the PB on the route
  ///
  /// In en, this message translates to:
  /// **'Personal best on {route}'**
  String runDetailPersonalBest(String route);

  /// Route-history card line showing how far behind the personal best this run was
  ///
  /// In en, this message translates to:
  /// **'{delta} behind PB'**
  String runDetailBehindPb(String delta);

  /// Route-history card subtitle showing this run's rank among attempts and the PB time
  ///
  /// In en, this message translates to:
  /// **'Attempt {rank} of {total}  —  PB: {pb}'**
  String runDetailAttemptOf(int rank, int total, String pb);

  /// Section header for the auto-detected best-efforts list on run-detail
  ///
  /// In en, this message translates to:
  /// **'Best Efforts'**
  String get runDetailSectionBestEfforts;

  /// Section header for the HR-zone breakdown on run-detail
  ///
  /// In en, this message translates to:
  /// **'Heart rate zones'**
  String get runDetailSectionHeartRateZones;

  /// Stat label for average BPM in the HR-zone breakdown
  ///
  /// In en, this message translates to:
  /// **'Avg'**
  String get runDetailHrAvg;

  /// Stat label for minimum BPM in the HR-zone breakdown
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get runDetailHrMin;

  /// Stat label for maximum BPM in the HR-zone breakdown
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get runDetailHrMax;

  /// Per-zone legend row in the HR-zone breakdown
  ///
  /// In en, this message translates to:
  /// **'Zone {number} · {label}'**
  String runDetailZoneRow(int number, String label);

  /// Section header for the splits list on run-detail
  ///
  /// In en, this message translates to:
  /// **'Splits'**
  String get runDetailSectionSplits;

  /// Shown in the splits section when the run has no GPS track
  ///
  /// In en, this message translates to:
  /// **'No GPS data for splits'**
  String get runDetailNoGpsForSplits;

  /// Shown in the splits section when the run is shorter than one full split unit
  ///
  /// In en, this message translates to:
  /// **'Run too short for a full {unit} split'**
  String runDetailRunTooShortSplit(String unit);

  /// Section header for the segment-efforts panel on run-detail
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get runDetailSectionSegments;

  /// Title of the save-as-route dialog
  ///
  /// In en, this message translates to:
  /// **'Save as route'**
  String get runDetailSaveAsRouteTitle;

  /// Body of the save-as-route dialog
  ///
  /// In en, this message translates to:
  /// **'Save this GPS trace as a route you can follow again.'**
  String get runDetailSaveAsRouteBody;

  /// Label for the name field in the save-as-route dialog
  ///
  /// In en, this message translates to:
  /// **'Route name'**
  String get runDetailRouteNameLabel;

  /// Banner shown when trying to save a trackless run as a route
  ///
  /// In en, this message translates to:
  /// **'This run has no GPS track to save as a route'**
  String get runDetailNoTrackToSave;

  /// Banner shown after accepting an auto-link route suggestion
  ///
  /// In en, this message translates to:
  /// **'Linked to {route}'**
  String runDetailRouteLinked(String route);

  /// Banner shown when linking a run to a suggested route fails
  ///
  /// In en, this message translates to:
  /// **'Could not link route'**
  String get runDetailRouteLinkFailed;

  /// Banner shown after enqueueing a re-match of the run's track
  ///
  /// In en, this message translates to:
  /// **'Re-snapping to roads…'**
  String get runDetailReSnapping;

  /// Banner shown when the re-match request fails
  ///
  /// In en, this message translates to:
  /// **'Re-match failed: {error}'**
  String runDetailRematchFailed(String error);

  /// Banner shown after saving a run's track as a route, with waypoint counts
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\" — {kept} waypoints ({smoothed} smoothed out)'**
  String runDetailRouteSaved(String name, int kept, int smoothed);

  /// Banner shown when flipping a run to public fails
  ///
  /// In en, this message translates to:
  /// **'Could not make run public: {error}'**
  String runDetailMakePublicFailed(String error);

  /// Title of the make-run-public confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Make this run public?'**
  String get runDetailMakePublicTitle;

  /// Make-public dialog body when the track intersects a privacy zone
  ///
  /// In en, this message translates to:
  /// **'Sharing flips this run to public so anyone with the link can view it. This run starts or ends inside one of your privacy zones, so viewers will see a clipped track with the in-zone segments hidden.'**
  String get runDetailMakePublicBodyZone;

  /// Make-public dialog body when the user has zones but none intersect this track
  ///
  /// In en, this message translates to:
  /// **'Sharing flips this run to public so anyone with the link can view it. None of your privacy zones intersect this track, so the full track will be visible.'**
  String get runDetailMakePublicBodyHasZones;

  /// Make-public dialog body when the user has no privacy zones
  ///
  /// In en, this message translates to:
  /// **'Sharing flips this run to public so anyone with the link can view it — including the start and end points of your run. You have no privacy zones set up. Consider adding one around your home before sharing.'**
  String get runDetailMakePublicBodyNoZones;

  /// Confirm action in the make-run-public dialog
  ///
  /// In en, this message translates to:
  /// **'Make public'**
  String get runDetailMakePublic;

  /// Title of the single-run delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete run?'**
  String get runDetailDeleteTitle;

  /// Body of the single-run delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get runDetailDeleteBody;

  /// Confirm action on the auto-link route-suggestion banner
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get runDetailSuggestLink;

  /// Dismiss action on the auto-link route-suggestion banner
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get runDetailSuggestDismiss;

  /// Leading text of the auto-link route-suggestion banner, before the bold route name
  ///
  /// In en, this message translates to:
  /// **'Looks like you ran '**
  String get runDetailSuggestRanRoute;

  /// Sub-line of the auto-link route-suggestion banner
  ///
  /// In en, this message translates to:
  /// **'Link this run to that route?'**
  String get runDetailSuggestLinkPrompt;

  /// Map-match status pill: snap job is queued
  ///
  /// In en, this message translates to:
  /// **'Snapping to roads…'**
  String get runDetailMatchPending;

  /// Map-match status pill: snap skipped because the track had too few points
  ///
  /// In en, this message translates to:
  /// **'Not snapped (too few points)'**
  String get runDetailMatchSkipped;

  /// Map-match status pill: snap failed, raw track shown instead
  ///
  /// In en, this message translates to:
  /// **'Snap failed — showing raw track'**
  String get runDetailMatchFailed;

  /// Map-match status pill: track was snapped to roads
  ///
  /// In en, this message translates to:
  /// **'Snapped'**
  String get runDetailMatchMatched;

  /// Re-match button label while the enqueue is in flight
  ///
  /// In en, this message translates to:
  /// **'Queueing…'**
  String get runDetailRematchQueueing;

  /// Re-match button label on the map-match status pill
  ///
  /// In en, this message translates to:
  /// **'Re-match'**
  String get runDetailRematch;

  /// Stat label for distance in the tap-to-select segment card
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get runDetailSegStatDistance;

  /// Stat label for time in the segment card
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get runDetailSegStatTime;

  /// Stat label for pace in the segment card
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get runDetailSegStatPace;

  /// Stat label for heart rate in the segment card
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get runDetailSegStatHr;

  /// Stat label for elevation gain in the segment card
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get runDetailSegStatGain;

  /// Tooltip on the segment card's close button
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get runDetailSegDismiss;

  /// AppBar title for the read-only public run view
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get publicRunTitle;

  /// Error state shown when the public run fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load this run.'**
  String get publicRunLoadError;

  /// Empty state shown when the public run is private or deleted
  ///
  /// In en, this message translates to:
  /// **'This run is private or no longer available.'**
  String get publicRunUnavailable;

  /// Fallback author name on the public run view when the profile has no display name
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get publicRunAuthorFallback;

  /// Stat label for distance on the public run view
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get publicRunStatDistance;

  /// Stat label for time on the public run view
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get publicRunStatTime;

  /// Stat label for pace on the public run view
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get publicRunStatPace;

  /// Section header for the segments panel on the public run view
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get publicRunSectionSegments;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'ja',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
