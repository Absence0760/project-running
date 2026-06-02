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
