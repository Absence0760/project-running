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

  /// Inline error when the invite-code field is empty on submit
  ///
  /// In en, this message translates to:
  /// **'Enter the invite code from your link.'**
  String get clubInviteEnterCodeError;

  /// Confirmation banner after successfully redeeming a club invite
  ///
  /// In en, this message translates to:
  /// **'You\'ve joined the club.'**
  String get clubInviteJoinedBanner;

  /// App bar title for the club-invite redemption screen
  ///
  /// In en, this message translates to:
  /// **'Join club'**
  String get clubInviteTitle;

  /// Instruction text above the invite-code field
  ///
  /// In en, this message translates to:
  /// **'Paste the invite code your club admin shared with you.'**
  String get clubInviteIntro;

  /// Text field label for the club invite code
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get clubInviteCodeLabel;

  /// Button to redeem the club invite code
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get clubInviteJoinButton;

  /// First line of the shared year-in-running recap summary
  ///
  /// In en, this message translates to:
  /// **'My {year} in running:'**
  String recapShareHeadline(Object year);

  /// Distance-and-run-count line in the shared recap summary
  ///
  /// In en, this message translates to:
  /// **'{total} across {count} runs'**
  String recapShareTotals(Object total, Object count);

  /// Longest-run line in the shared recap summary
  ///
  /// In en, this message translates to:
  /// **'Longest run: {distance}'**
  String recapShareLongestRun(Object distance);

  /// Best-streak line in the shared recap summary
  ///
  /// In en, this message translates to:
  /// **'Best streak: {days} days'**
  String recapShareBestStreak(Object days);

  /// OS share-sheet subject for the year-in-running recap
  ///
  /// In en, this message translates to:
  /// **'{year} recap'**
  String recapShareSubject(Object year);

  /// App bar title for the year-in-running recap screen
  ///
  /// In en, this message translates to:
  /// **'Year in running'**
  String get recapTitle;

  /// Tooltip for the share-recap icon button
  ///
  /// In en, this message translates to:
  /// **'Share recap'**
  String get recapShareTooltip;

  /// Tooltip/label for the publish-and-share-link action on the recap screen
  ///
  /// In en, this message translates to:
  /// **'Publish & share link'**
  String get recapPublishAndShare;

  /// Banner shown when publishing a public recap fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t publish the recap. Try again.'**
  String get recapPublishFailed;

  /// Tooltip for the previous-year chevron on the recap screen
  ///
  /// In en, this message translates to:
  /// **'Previous year'**
  String get recapPrevYear;

  /// Tooltip for the next-year chevron on the recap screen
  ///
  /// In en, this message translates to:
  /// **'Next year'**
  String get recapNextYear;

  /// Empty-state shown for a year outside the valid range
  ///
  /// In en, this message translates to:
  /// **'No runs to recap for {year}.'**
  String recapNoRunsForYear(Object year);

  /// Empty-state shown when no runs exist for the selected year
  ///
  /// In en, this message translates to:
  /// **'No runs in {year} yet. Log one to see your recap.'**
  String recapNoRunsYet(Object year);

  /// Subtitle under the hero distance giving the run count
  ///
  /// In en, this message translates to:
  /// **'across {count} {runWord}'**
  String recapAcrossRuns(Object count, Object runWord);

  /// Stat card label for the longest run of the year
  ///
  /// In en, this message translates to:
  /// **'Longest run'**
  String get recapLongestRunLabel;

  /// Stat card label for the best running streak
  ///
  /// In en, this message translates to:
  /// **'Best streak'**
  String get recapBestStreakLabel;

  /// Stat card value for the best streak length in days
  ///
  /// In en, this message translates to:
  /// **'{days} {dayWord}'**
  String recapStreakDays(Object days, Object dayWord);

  /// Stat card label for the highest-mileage week
  ///
  /// In en, this message translates to:
  /// **'Top week'**
  String get recapTopWeekLabel;

  /// Stat card label for the count of unique routes run
  ///
  /// In en, this message translates to:
  /// **'Unique routes'**
  String get recapUniqueRoutesLabel;

  /// Stat card label for the earliest run start time
  ///
  /// In en, this message translates to:
  /// **'Earliest start'**
  String get recapEarliestStartLabel;

  /// Stat card label for the latest run start time
  ///
  /// In en, this message translates to:
  /// **'Latest start'**
  String get recapLatestStartLabel;

  /// App bar title for the full-screen route picker
  ///
  /// In en, this message translates to:
  /// **'Choose route'**
  String get routePickerTitle;

  /// App bar action to dismiss the picker without choosing a route
  ///
  /// In en, this message translates to:
  /// **'No route'**
  String get routePickerNoRoute;

  /// Tooltip for the clear-search button in the route picker
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get routePickerClearSearchTooltip;

  /// Placeholder hint for the route-picker search field
  ///
  /// In en, this message translates to:
  /// **'Search routes by name…'**
  String get routePickerSearchHint;

  /// Empty state when the user has no saved routes
  ///
  /// In en, this message translates to:
  /// **'No routes saved yet'**
  String get routePickerEmptyNoRoutes;

  /// Empty state when no saved route matches the search query
  ///
  /// In en, this message translates to:
  /// **'No routes match \"{query}\"'**
  String routePickerEmptyNoMatch(Object query);

  /// Section header above the starred routes block in the picker
  ///
  /// In en, this message translates to:
  /// **'Starred'**
  String get routePickerStarredHeader;

  /// Section header above the non-starred routes block in the picker
  ///
  /// In en, this message translates to:
  /// **'All routes'**
  String get routePickerAllRoutesHeader;

  /// Status line after a successful import with no errors
  ///
  /// In en, this message translates to:
  /// **'Imported {count} runs from {label}'**
  String importStatusImported(Object count, Object label);

  /// Status line after an import that had some failures
  ///
  /// In en, this message translates to:
  /// **'Imported {count} runs ({errors} failed)'**
  String importStatusImportedWithErrors(Object count, Object errors);

  /// Appended note when an imported source has no GPS route data
  ///
  /// In en, this message translates to:
  /// **'{base}. {label} has no route data, so these runs have no map.'**
  String importStatusNoGpsNote(Object base, Object label);

  /// Status while requesting the platform health-store permission
  ///
  /// In en, this message translates to:
  /// **'Requesting {label} permission...'**
  String importHealthRequestingPermission(Object label);

  /// Status when the health-store permission was denied
  ///
  /// In en, this message translates to:
  /// **'{label} permission denied'**
  String importHealthPermissionDenied(Object label);

  /// Status while reading workouts from the health store
  ///
  /// In en, this message translates to:
  /// **'Reading workouts...'**
  String get importHealthReadingWorkouts;

  /// Status when a health-store import fails
  ///
  /// In en, this message translates to:
  /// **'{label} import failed: {error}'**
  String importHealthFailed(Object label, Object error);

  /// Status while saving imported runs to the local store
  ///
  /// In en, this message translates to:
  /// **'Saving locally...'**
  String get importStatusSavingLocally;

  /// Status when cross-source duplicate runs are skipped during import
  ///
  /// In en, this message translates to:
  /// **'Skipped {count} duplicate(s) already imported from another source'**
  String importStatusSkippedDuplicates(Object count);

  /// Per-run progress status while saving imported runs locally
  ///
  /// In en, this message translates to:
  /// **'Saved {done} of {total} locally'**
  String importStatusSavedProgress(Object done, Object total);

  /// Status while pushing imported runs to the cloud
  ///
  /// In en, this message translates to:
  /// **'Syncing to cloud...'**
  String get importStatusSyncingToCloud;

  /// Per-run progress status while syncing imported runs to the cloud
  ///
  /// In en, this message translates to:
  /// **'Synced {done} of {total}'**
  String importStatusSyncProgress(Object done, Object total);

  /// Status while reading the selected CSV file
  ///
  /// In en, this message translates to:
  /// **'Reading CSV...'**
  String get importStatusReadingCsv;

  /// Status when the CSV import fails
  ///
  /// In en, this message translates to:
  /// **'CSV import failed: {error}'**
  String importCsvFailed(Object error);

  /// Status while restoring from a full-backup ZIP
  ///
  /// In en, this message translates to:
  /// **'Restoring backup...'**
  String get importStatusRestoringBackup;

  /// Status after a successful full-backup restore
  ///
  /// In en, this message translates to:
  /// **'Restored {runs} runs · {tracks} tracks · {routes} routes'**
  String importStatusBackupRestored(Object runs, Object tracks, Object routes);

  /// Status when restoring from a backup ZIP fails
  ///
  /// In en, this message translates to:
  /// **'Backup restore failed: {error}'**
  String importBackupFailed(Object error);

  /// Status while reading the Strava export ZIP
  ///
  /// In en, this message translates to:
  /// **'Reading export...'**
  String get importStatusReadingExport;

  /// Status when the Strava ZIP import fails
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importStravaFailed(Object error);

  /// App bar title for the bulk-import screen
  ///
  /// In en, this message translates to:
  /// **'Import runs'**
  String get importTitle;

  /// Card title for the Strava import source
  ///
  /// In en, this message translates to:
  /// **'Strava'**
  String get importStravaCardTitle;

  /// Card subtitle describing the Strava ZIP import
  ///
  /// In en, this message translates to:
  /// **'Import every run from a Strava data export ZIP'**
  String get importStravaCardSubtitle;

  /// Header above the Strava export step-by-step instructions
  ///
  /// In en, this message translates to:
  /// **'How to get your Strava export:'**
  String get importStravaHowToHeader;

  /// Step-by-step instructions for requesting a Strava data export
  ///
  /// In en, this message translates to:
  /// **'1. Open Strava → Settings → My Account\n2. Scroll to \"Download or Delete Your Account\"\n3. Tap \"Get Started\" → \"Request your archive\"\n4. You\'ll get an email with a download link in a few hours\n5. Download the .zip and tap Import below'**
  String get importStravaHowToSteps;

  /// Button to pick and import a Strava export ZIP
  ///
  /// In en, this message translates to:
  /// **'Import Strava ZIP'**
  String get importStravaButton;

  /// Button to import workouts from the platform health store
  ///
  /// In en, this message translates to:
  /// **'Import from {label}'**
  String importHealthButton(Object label);

  /// Card title for the CSV import source
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get importCsvCardTitle;

  /// Card subtitle describing the CSV import source
  ///
  /// In en, this message translates to:
  /// **'Re-import a CSV exported from Settings — runs only, no GPS'**
  String get importCsvCardSubtitle;

  /// Body copy explaining the CSV import limitations
  ///
  /// In en, this message translates to:
  /// **'Each CSV row becomes a manual run (date, distance, duration, source). The map trace is not in the CSV, so imported runs won\'t have a route line.'**
  String get importCsvCardDescription;

  /// Button to pick and import a CSV file
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get importCsvButton;

  /// Card title for the full-backup ZIP restore source
  ///
  /// In en, this message translates to:
  /// **'Full backup ZIP'**
  String get importBackupCardTitle;

  /// Card subtitle describing the full-backup restore
  ///
  /// In en, this message translates to:
  /// **'Restore runs, routes, and GPS traces from a backup file'**
  String get importBackupCardSubtitle;

  /// Body copy explaining the full-backup restore behaviour
  ///
  /// In en, this message translates to:
  /// **'Loss-less round-trip. Works without signing in — restored runs sync to your account the next time you do. Make a backup from Settings → Full backup.'**
  String get importBackupCardDescription;

  /// Button to pick and restore a full-backup ZIP
  ///
  /// In en, this message translates to:
  /// **'Restore backup ZIP'**
  String get importBackupButton;

  /// Header above the list of per-file import errors
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get importErrorsHeader;

  /// Truncation line when more than ten import errors exist
  ///
  /// In en, this message translates to:
  /// **'... and {count} more'**
  String importErrorsMore(Object count);

  /// iOS subtitle naming apps that write to Apple Health
  ///
  /// In en, this message translates to:
  /// **'Pull workouts you\'ve recorded on Apple Watch, Nike Run Club, Strava, and other apps that write to Apple Health'**
  String get importHealthSubtitleIos;

  /// Android subtitle naming apps that write to Health Connect
  ///
  /// In en, this message translates to:
  /// **'Pull workouts from Google Fit, Samsung Health, Garmin, Fitbit, and any other Health Connect app'**
  String get importHealthSubtitleAndroid;

  /// iOS body copy explaining what is imported from Apple Health and the no-track caveat
  ///
  /// In en, this message translates to:
  /// **'Reads workout summaries (date, distance, duration, type) from the last year. Apple Health doesn\'t expose GPS routes recorded by third-party apps — runs imported this way won\'t have a map trace.'**
  String get importHealthDescriptionIos;

  /// Android body copy explaining what is imported from Health Connect and the no-track caveat
  ///
  /// In en, this message translates to:
  /// **'Reads workout summaries (date, distance, duration, type) from the last year. GPS routes are not exposed by Health Connect — runs imported this way won\'t have a map trace.'**
  String get importHealthDescriptionAndroid;

  /// Error banner when toggling follow on a person fails
  ///
  /// In en, this message translates to:
  /// **'Could not update follow: {error}'**
  String peopleFollowFailedBanner(Object error);

  /// Placeholder hint for the people-search field
  ///
  /// In en, this message translates to:
  /// **'Search runners by name'**
  String get peopleSearchHint;

  /// Tooltip for the clear-search action button in the app bar
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get peopleClearSearchTooltip;

  /// Generic tooltip for a clear-search icon button
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get commonClearSearch;

  /// Generic tooltip for a dismiss / close icon button
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// Tooltip for the per-row remove-override icon button in the device override editor
  ///
  /// In en, this message translates to:
  /// **'Remove override'**
  String get settingsDevicesRemoveOverride;

  /// Section header shown above people search results
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get peopleSearchResultsHeader;

  /// Section header shown above suggested people
  ///
  /// In en, this message translates to:
  /// **'Suggested for you'**
  String get peopleSuggestedHeader;

  /// Empty-state title when no people match the search query
  ///
  /// In en, this message translates to:
  /// **'No runners match \"{query}\"'**
  String peopleEmptySearchTitle(Object query);

  /// Empty-state body when no people match the search query
  ///
  /// In en, this message translates to:
  /// **'Try a shorter or different name. Display names are public; people who haven\'t set one yet won\'t show up here.'**
  String get peopleEmptySearchBody;

  /// Empty-state title when there are no people suggestions
  ///
  /// In en, this message translates to:
  /// **'No suggestions yet'**
  String get peopleEmptySuggestionsTitle;

  /// Empty-state body when there are no people suggestions
  ///
  /// In en, this message translates to:
  /// **'Suggestions come from people in clubs you\'ve joined. Join a club to start seeing them here.'**
  String get peopleEmptySuggestionsBody;

  /// Person-row metadata: count of the person's public runs
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 public run} other{{count} public runs}}'**
  String peoplePublicRunCount(num count);

  /// Person-row metadata: count of clubs shared with the person
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 club together} other{{count} clubs together}}'**
  String peopleSharedClubsCount(num count);

  /// Fallback display name for a person with no name set
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get peopleFallbackDisplayName;

  /// Follow-toggle button label when already following the person
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get peopleFollowingButton;

  /// Follow-toggle button label when not following the person
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get peopleFollowButton;

  /// Header label on the dashboard readiness-to-run card
  ///
  /// In en, this message translates to:
  /// **'READINESS'**
  String get readinessCardHeader;

  /// Readiness band pill label for a high readiness score
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get readinessBandHigh;

  /// Readiness band pill label for a moderate readiness score
  ///
  /// In en, this message translates to:
  /// **'moderate'**
  String get readinessBandModerate;

  /// Readiness band pill label for a low readiness score
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get readinessBandLow;

  /// Diagnostic banner title shown when no map-tile source is configured (dev-facing)
  ///
  /// In en, this message translates to:
  /// **'Using OpenStreetMap fallback tiles'**
  String get missingMapTilesTitle;

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

  /// Tooltip/label for the centre Log action button in the bottom nav
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get navLog;

  /// Screen-reader label for the centre Log action button
  ///
  /// In en, this message translates to:
  /// **'Log an activity'**
  String get logA11yLabel;

  /// Bottom-nav label for the Fitness modality hub (All/Runs/Gym/Nutrition)
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get navFitness;

  /// Bottom-nav label for the You tab (profile + settings)
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get navYou;

  /// Fitness hub sub-tab showing the unified cross-modal activity timeline
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get fitnessTabAll;

  /// Fitness hub sub-tab for the run list and routes
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get fitnessTabRuns;

  /// Fitness hub sub-tab for gym workouts
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get fitnessTabGym;

  /// Fitness hub sub-tab for nutrition
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get fitnessTabNutrition;

  /// Label for the Routes entry on the Fitness hub's Runs sub-tab
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get fitnessRunsRoutes;

  /// Label for the Training plans entry on the Fitness hub's Runs sub-tab
  ///
  /// In en, this message translates to:
  /// **'Training plans'**
  String get fitnessRunsPlans;

  /// Title of the pinned coach entry at the top of the Home dashboard
  ///
  /// In en, this message translates to:
  /// **'Ask your coach'**
  String get homeAskCoach;

  /// Subtitle of the pinned coach entry at the top of the Home dashboard
  ///
  /// In en, this message translates to:
  /// **'Advice across your runs, lifts, and nutrition'**
  String get homeAskCoachSubtitle;

  /// Title of the profile entry at the top of the You tab
  ///
  /// In en, this message translates to:
  /// **'Your profile'**
  String get youProfileTitle;

  /// Title of the Log capture bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get logSheetTitle;

  /// Log sheet item: log a run (opens the recorder)
  ///
  /// In en, this message translates to:
  /// **'Log run'**
  String get logRun;

  /// Log sheet item: log a gym/lift workout
  ///
  /// In en, this message translates to:
  /// **'Log lift'**
  String get logLift;

  /// Log sheet item: log food (meal slot chosen in the composer)
  ///
  /// In en, this message translates to:
  /// **'Log food'**
  String get logFood;

  /// Settings toggle: make the centre Log button start a run on a single tap
  ///
  /// In en, this message translates to:
  /// **'Run as primary action'**
  String get prefsKeepRunPrimary;

  /// Subtitle for the run-as-primary-action settings toggle
  ///
  /// In en, this message translates to:
  /// **'Tap the centre button to start a run; long-press for the full log menu'**
  String get prefsKeepRunPrimarySubtitle;

  /// Title of the body-metrics settings screen
  ///
  /// In en, this message translates to:
  /// **'Body metrics'**
  String get bodyMetricsTitle;

  /// Settings tile subtitle for the body-metrics entry
  ///
  /// In en, this message translates to:
  /// **'Height, weight & nutrition targets'**
  String get bodyMetricsTileSubtitle;

  /// Toggle title for the GDPR Art 9 health-data consent gate
  ///
  /// In en, this message translates to:
  /// **'Store health data'**
  String get bodyMetricsConsentTitle;

  /// Explanation under the health-data consent toggle
  ///
  /// In en, this message translates to:
  /// **'Height and weight are special-category health data. Turn this off to erase them.'**
  String get bodyMetricsConsentSubtitle;

  /// Label for the height input (centimetres)
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get bodyMetricsHeight;

  /// Label for the weight input (user's weight unit)
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get bodyMetricsWeight;

  /// Label for the nutrition activity-level picker
  ///
  /// In en, this message translates to:
  /// **'Activity level'**
  String get bodyMetricsActivityLevel;

  /// Label for the nutrition weight-goal picker
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get bodyMetricsGoal;

  /// Helper text explaining what body metrics are used for
  ///
  /// In en, this message translates to:
  /// **'Used to estimate your daily calorie and macro targets.'**
  String get bodyMetricsTargetsHint;

  /// Error shown when saving body data without consent
  ///
  /// In en, this message translates to:
  /// **'Turn on health-data storage to save height and weight.'**
  String get bodyMetricsConsentRequired;

  /// No description provided for @bodyMetricsWithdrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw health-data consent?'**
  String get bodyMetricsWithdrawTitle;

  /// No description provided for @bodyMetricsWithdrawBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently erases your saved height and your entire weight history. This can\'t be undone.'**
  String get bodyMetricsWithdrawBody;

  /// No description provided for @bodyMetricsWithdrawConfirm.
  ///
  /// In en, this message translates to:
  /// **'Withdraw & erase'**
  String get bodyMetricsWithdrawConfirm;

  /// Confirmation toast after saving body metrics
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get bodyMetricsSaved;

  /// Error toast when saving body metrics fails
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String bodyMetricsSaveFailed(String error);

  /// Error toast when saving the activity-level / goal nutrition pref fails
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String bodyMetricsPrefSaveFailed(String error);

  /// Title of the safety-contacts settings screen
  ///
  /// In en, this message translates to:
  /// **'Safety contacts'**
  String get safetyTitle;

  /// Settings landing: Safety tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Email a trusted contact when you finish a run'**
  String get safetyTileSubtitle;

  /// Intro paragraph on the safety-contacts screen
  ///
  /// In en, this message translates to:
  /// **'A safety contact is emailed when you finish a run — even a private one — so someone you trust knows you got back safely.'**
  String get safetyIntro;

  /// Label for the add-contact email input
  ///
  /// In en, this message translates to:
  /// **'Contact email'**
  String get safetyAddLabel;

  /// Button to add a safety contact
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get safetyAddButton;

  /// Add button label while the add request is in flight
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get safetyAdding;

  /// Empty-state text when the user has no safety contacts
  ///
  /// In en, this message translates to:
  /// **'No safety contacts yet.'**
  String get safetyEmpty;

  /// Status badge for a contact who hasn't opted in yet
  ///
  /// In en, this message translates to:
  /// **'Pending — waiting for them to confirm'**
  String get safetyStatusPending;

  /// Status badge for a contact who has opted in
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get safetyStatusConfirmed;

  /// Button to remove a safety contact
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get safetyRemove;

  /// Confirmation dialog body when removing a safety contact
  ///
  /// In en, this message translates to:
  /// **'Remove this safety contact?'**
  String get safetyRemoveConfirm;

  /// Error toast when adding a safety contact fails
  ///
  /// In en, this message translates to:
  /// **'Could not add contact: {error}'**
  String safetyAddFailed(String error);

  /// Inline error when the entered email is not valid
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get safetyInvalidEmail;

  /// Toast after a safety contact is added
  ///
  /// In en, this message translates to:
  /// **'Contact added — we emailed them to confirm.'**
  String get safetyAddedToast;

  /// Toast after a safety contact is removed
  ///
  /// In en, this message translates to:
  /// **'Contact removed.'**
  String get safetyRemovedToast;

  /// Heading above incoming safety-contact requests
  ///
  /// In en, this message translates to:
  /// **'Requests for you'**
  String get safetyIncomingTitle;

  /// Intro under the incoming-requests heading
  ///
  /// In en, this message translates to:
  /// **'These people asked you to be their safety contact. Confirm to get an email when they finish a run.'**
  String get safetyIncomingIntro;

  /// Label naming the runner who sent an incoming request
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String safetyIncomingFrom(String name);

  /// Button to confirm an incoming safety-contact request
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get safetyConfirm;

  /// Button to decline an incoming safety-contact request
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get safetyDecline;

  /// Toast after confirming an incoming request
  ///
  /// In en, this message translates to:
  /// **'You\'re now a safety contact.'**
  String get safetyConfirmedToast;

  /// Toast after declining an incoming request
  ///
  /// In en, this message translates to:
  /// **'Request declined.'**
  String get safetyDeclinedToast;

  /// Fallback name when an incoming request's owner has no display name
  ///
  /// In en, this message translates to:
  /// **'A Threkir runner'**
  String get safetyUnknownRunner;

  /// Heading of the overdue-alert section on Settings → Safety contacts
  ///
  /// In en, this message translates to:
  /// **'Overdue alert'**
  String get safetyOverdueTitle;

  /// Explainer under the overdue-alert heading
  ///
  /// In en, this message translates to:
  /// **'If a live-shared run goes quiet for longer than this, your confirmed contacts get one email with your live link.'**
  String get safetyOverdueIntro;

  /// Label on the overdue silence-window dropdown
  ///
  /// In en, this message translates to:
  /// **'Alert after silence of'**
  String get safetyOverdueLabel;

  /// Dropdown choice that disables the overdue escalation
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get safetyOverdueOff;

  /// Dropdown choice for an overdue window
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String safetyOverdueMinutesOption(int minutes);

  /// Fine print under the overdue controls (signal-loss caveat, once per run)
  ///
  /// In en, this message translates to:
  /// **'Applies to any run with live sharing on. Silence can also mean loss of phone signal — the email says so. Contacts are alerted once per run; finishing sends the usual all-clear.'**
  String get safetyOverdueNote;

  /// Banner after the overdue window persists
  ///
  /// In en, this message translates to:
  /// **'Overdue alert updated'**
  String get safetyOverdueSaved;

  /// Title of the auto-live-share device toggle
  ///
  /// In en, this message translates to:
  /// **'Auto live share'**
  String get safetyAutoLiveShareTitle;

  /// Subtitle of the auto-live-share device toggle (public-by-link disclosure)
  ///
  /// In en, this message translates to:
  /// **'Start a live share automatically when a run starts on this phone. The in-progress run is viewable by anyone with the link.'**
  String get safetyAutoLiveShareSubtitle;

  /// Banner on the run screen when the auto-live-share pref attached the broadcaster
  ///
  /// In en, this message translates to:
  /// **'Live sharing is on — use Share live link to send it'**
  String get runAutoLiveShareStarted;

  /// Nutrition activity level: little exercise
  ///
  /// In en, this message translates to:
  /// **'Mostly sitting (desk job)'**
  String get activitySedentary;

  /// Nutrition activity level: 1-3 days/week
  ///
  /// In en, this message translates to:
  /// **'Lightly active (light daily movement)'**
  String get activityLight;

  /// Nutrition activity level: 3-5 days/week
  ///
  /// In en, this message translates to:
  /// **'Moderately active (on your feet often)'**
  String get activityModerate;

  /// Nutrition activity level: 6-7 days/week
  ///
  /// In en, this message translates to:
  /// **'Very active day (physical job)'**
  String get activityVeryActive;

  /// Nutrition activity level: training twice a day
  ///
  /// In en, this message translates to:
  /// **'Extremely active (hard physical labour)'**
  String get activityExtraActive;

  /// Nutrition weight goal: calorie deficit
  ///
  /// In en, this message translates to:
  /// **'Lose weight'**
  String get goalLose;

  /// Nutrition weight goal: maintenance
  ///
  /// In en, this message translates to:
  /// **'Maintain weight'**
  String get goalMaintain;

  /// Nutrition weight goal: calorie surplus
  ///
  /// In en, this message translates to:
  /// **'Gain weight'**
  String get goalGain;

  /// Home card header above today's logged gym workout
  ///
  /// In en, this message translates to:
  /// **'Today\'s lift'**
  String get homeTodaysLift;

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

  /// Notice shown when the Google button is tapped but the provider isn't configured yet
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is coming soon. For now, please use email.'**
  String get googleSignInSoon;

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

  /// App bar title of the post-signup setup wizard
  ///
  /// In en, this message translates to:
  /// **'Set up your account'**
  String get setupPageTitle;

  /// Header action that skips the whole setup wizard
  ///
  /// In en, this message translates to:
  /// **'Skip setup'**
  String get setupSkip;

  /// Action that skips the current setup-wizard step
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get setupSkipStep;

  /// Button that goes to the previous setup-wizard step
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get setupBack;

  /// Button that advances to the next setup-wizard step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get setupContinue;

  /// Final setup-wizard button label while the answers are being saved
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get setupSaving;

  /// Final setup-wizard button that saves and closes the wizard
  ///
  /// In en, this message translates to:
  /// **'Open dashboard'**
  String get setupOpenDashboard;

  /// Toast shown after the setup wizard completes
  ///
  /// In en, this message translates to:
  /// **'Welcome to Threkir!'**
  String get setupWelcomeToast;

  /// Toast shown when saving the setup wizard fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your setup: {message}'**
  String setupSaveError(String message);

  /// Setup wizard display-name step title
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get setupNameTitle;

  /// Setup wizard display-name step hint
  ///
  /// In en, this message translates to:
  /// **'This is the name other runners see on your profile and shared runs.'**
  String get setupNameHint;

  /// Setup wizard display-name field label
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get setupNameLabel;

  /// Setup wizard display-name field placeholder
  ///
  /// In en, this message translates to:
  /// **'e.g. Alex Runner'**
  String get setupNamePlaceholder;

  /// Setup wizard units step title
  ///
  /// In en, this message translates to:
  /// **'Kilometres or miles?'**
  String get setupUnitsTitle;

  /// Setup wizard units step hint
  ///
  /// In en, this message translates to:
  /// **'We\'ll use this everywhere distances and paces are shown. You can change it any time in Settings.'**
  String get setupUnitsHint;

  /// Setup wizard kilometres unit option
  ///
  /// In en, this message translates to:
  /// **'Kilometres'**
  String get setupUnitKm;

  /// Setup wizard kilometres unit sample line
  ///
  /// In en, this message translates to:
  /// **'5.0 km · 5:00 /km'**
  String get setupUnitKmSample;

  /// Setup wizard miles unit option
  ///
  /// In en, this message translates to:
  /// **'Miles'**
  String get setupUnitMi;

  /// Setup wizard miles unit sample line
  ///
  /// In en, this message translates to:
  /// **'3.1 mi · 8:03 /mi'**
  String get setupUnitMiSample;

  /// Setup wizard primary-goal step title
  ///
  /// In en, this message translates to:
  /// **'What\'s your main goal?'**
  String get setupGoalTitle;

  /// Setup wizard primary-goal step hint
  ///
  /// In en, this message translates to:
  /// **'We\'ll use this to suggest a training plan that fits. Optional — you can skip it.'**
  String get setupGoalHint;

  /// Setup wizard general-fitness goal option
  ///
  /// In en, this message translates to:
  /// **'Stay fit + healthy'**
  String get setupGoalGeneralFitness;

  /// Setup wizard weight-loss goal option
  ///
  /// In en, this message translates to:
  /// **'Lose weight'**
  String get setupGoalWeightLoss;

  /// Setup wizard 5K goal option
  ///
  /// In en, this message translates to:
  /// **'Run a 5K'**
  String get setupGoal5k;

  /// Setup wizard 10K goal option
  ///
  /// In en, this message translates to:
  /// **'Run a 10K'**
  String get setupGoal10k;

  /// Setup wizard half-marathon goal option
  ///
  /// In en, this message translates to:
  /// **'Run a half marathon'**
  String get setupGoalHalf;

  /// Setup wizard marathon goal option
  ///
  /// In en, this message translates to:
  /// **'Run a marathon'**
  String get setupGoalMarathon;

  /// Setup wizard demographics step title
  ///
  /// In en, this message translates to:
  /// **'A bit about you'**
  String get setupAboutTitle;

  /// Setup wizard demographics step hint
  ///
  /// In en, this message translates to:
  /// **'Optional. Helps tailor pace and calorie estimates. You choose whether to share health data.'**
  String get setupAboutHint;

  /// Setup wizard gender field label
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get setupGenderLabel;

  /// Setup wizard gender option declining to answer
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get setupGenderPreferNot;

  /// Setup wizard female gender option
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get setupGenderFemale;

  /// Setup wizard male gender option
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get setupGenderMale;

  /// Setup wizard non-binary gender option
  ///
  /// In en, this message translates to:
  /// **'Non-binary'**
  String get setupGenderNonbinary;

  /// Setup wizard date-of-birth field label
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get setupDobLabel;

  /// Setup wizard date-of-birth field note
  ///
  /// In en, this message translates to:
  /// **'Used to keep accounts of under-18s out of people search, and for age-graded results if you share health data.'**
  String get setupDobNote;

  /// Setup wizard date-of-birth empty-state text
  ///
  /// In en, this message translates to:
  /// **'Tap to choose'**
  String get setupDobPlaceholder;

  /// Setup wizard weight field label
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get setupWeightLabel;

  /// Setup wizard weight field placeholder
  ///
  /// In en, this message translates to:
  /// **'e.g. 70'**
  String get setupWeightPlaceholder;

  /// Setup wizard health-data (GDPR Art 9) consent checkbox label
  ///
  /// In en, this message translates to:
  /// **'I consent to Threkir using my gender and date of birth to personalise pace, heart-rate and calorie estimates (special-category health data, GDPR Art 9).'**
  String get setupHealthConsent;

  /// Setup wizard privacy-default step title
  ///
  /// In en, this message translates to:
  /// **'Who sees your runs?'**
  String get setupPrivacyTitle;

  /// Setup wizard privacy-default step hint
  ///
  /// In en, this message translates to:
  /// **'Choose a default for new runs. You can change it any time and override it on any single run.'**
  String get setupPrivacyHint;

  /// Setup wizard notifications step title
  ///
  /// In en, this message translates to:
  /// **'Stay in the loop'**
  String get setupNotificationsTitle;

  /// Setup wizard notifications step hint
  ///
  /// In en, this message translates to:
  /// **'Choose how many push notifications you\'d like. You can fine-tune this later in Settings.'**
  String get setupNotificationsHint;

  /// Setup wizard final step title
  ///
  /// In en, this message translates to:
  /// **'You\'re all set'**
  String get setupDoneTitle;

  /// Setup wizard final step hint
  ///
  /// In en, this message translates to:
  /// **'That\'s everything. Tap Open dashboard to start running.'**
  String get setupDoneHint;

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

  /// Screen-reader label for the hold-to-stop control on the recording overlay
  ///
  /// In en, this message translates to:
  /// **'Stop and save run'**
  String get runStopA11yLabel;

  /// Screen-reader hint for the stop-and-save control
  ///
  /// In en, this message translates to:
  /// **'Ends the recording and saves the run'**
  String get runStopA11yHint;

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

  /// Label for the live run-screen toggle that sources distance from a paired treadmill belt
  ///
  /// In en, this message translates to:
  /// **'Treadmill mode'**
  String get runTreadmillModeLabel;

  /// Subtitle showing the live treadmill belt speed while treadmill mode is on
  ///
  /// In en, this message translates to:
  /// **'Belt {speed}'**
  String runTreadmillModeSpeed(String speed);

  /// Banner shown when the treadmill belt drops and is reconnecting
  ///
  /// In en, this message translates to:
  /// **'Treadmill lost, reconnecting…'**
  String get runTreadmillLostReconnecting;

  /// Banner shown when the treadmill belt reconnects
  ///
  /// In en, this message translates to:
  /// **'Treadmill reconnected'**
  String get runTreadmillReconnected;

  /// Banner shown when the treadmill belt drops and distance reverts to the GPS/pedometer path
  ///
  /// In en, this message translates to:
  /// **'Treadmill lost — distance falling back to GPS'**
  String get runTreadmillLostFallback;

  /// Banner shown when treadmill mode is turned on but the belt can't be reached
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the treadmill'**
  String get runTreadmillNotFound;

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
  String get historyRangeToday;

  /// History date-range option / header label for runs from the current week
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get historyRangeWeek;

  /// History date-range option / header label for runs from the last 30 days
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get historyRangeMonth;

  /// History date-range option / header label for runs from the current year
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get historyRangeYear;

  /// History date-range option / header label for all runs ever
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get historyRangeAll;

  /// History date-range option for picking a custom date range
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get historyRangeCustom;

  /// History header label for an open-ended custom range with only a start date
  ///
  /// In en, this message translates to:
  /// **'From {date}'**
  String historyRangeFrom(String date);

  /// History header label for an open-ended custom range with only an end date
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String historyRangeUntil(String date);

  /// Run-count chip next to the date-range label in the History AppBar title
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run} other{{count} runs}}'**
  String historyCount(int count);

  /// Tooltip on the History AppBar date-range picker button
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get historyDateRangeTooltip;

  /// Tooltip on the History AppBar sort button
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get historySortTooltip;

  /// History sort option: newest runs first
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get historySortNewest;

  /// History sort option: oldest runs first
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get historySortOldest;

  /// History sort option: longest distance first
  ///
  /// In en, this message translates to:
  /// **'Longest distance'**
  String get historySortLongest;

  /// History sort option: fastest pace first
  ///
  /// In en, this message translates to:
  /// **'Best pace'**
  String get historySortFastest;

  /// Tooltip on the History AppBar sync button, showing how many runs are queued
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Sync {count} run} other{Sync {count} runs}}'**
  String historySyncTooltip(int count);

  /// Tooltip on the History AppBar cloud-refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh from cloud'**
  String get historyRefreshTooltip;

  /// Tooltip on the disabled cloud icon when signed out
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get historyOfflineTooltip;

  /// AppBar title in History multi-select mode, showing how many runs are selected
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String historySelectionTitle(int count);

  /// Tooltip on the select-all button in History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get historySelectAllTooltip;

  /// Tooltip on the clear-selection button in History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get historyClearSelectionTooltip;

  /// Tooltip on the delete button in History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get historyDeleteTooltip;

  /// Tooltip on the cancel button that exits History multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get historyCancelTooltip;

  /// Label on the floating action button that opens the manual add-run form
  ///
  /// In en, this message translates to:
  /// **'Add run'**
  String get historyAddRun;

  /// Tooltip on the add-run floating action button
  ///
  /// In en, this message translates to:
  /// **'Add a run manually'**
  String get historyAddRunTooltip;

  /// Tooltip on the History add button when it logs a lift, a meal, or opens the run/lift/meal picker
  ///
  /// In en, this message translates to:
  /// **'Log a run, lift or meal'**
  String get historyLogTooltip;

  /// Button at the bottom of the runs list that reveals the next page of runs
  ///
  /// In en, this message translates to:
  /// **'Load {count} more'**
  String historyLoadMore(int count);

  /// Empty-state shown when the active filters exclude every run
  ///
  /// In en, this message translates to:
  /// **'No runs match these filters'**
  String get historyNoMatch;

  /// Unified-timeline kind chip: all activity kinds
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get historyKindAll;

  /// Unified-timeline kind chip: runs only
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get historyKindRuns;

  /// Unified-timeline kind chip: gym sessions only
  ///
  /// In en, this message translates to:
  /// **'Lifts'**
  String get historyKindLifts;

  /// Unified-timeline kind chip: logged meals only
  ///
  /// In en, this message translates to:
  /// **'Meals'**
  String get historyKindMeals;

  /// Link from a single-modality History tab to that modality's full page (runs list / gym / nutrition)
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get historyViewAll;

  /// Day-group header for today in the unified timeline
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get historyToday;

  /// Day-group header for yesterday in the unified timeline
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get historyYesterday;

  /// Lift row secondary: number of sets
  ///
  /// In en, this message translates to:
  /// **'{n} sets'**
  String historySetCount(int n);

  /// Meal row secondary: calories
  ///
  /// In en, this message translates to:
  /// **'{n} kcal'**
  String historyKcal(int n);

  /// Empty state for a unified-timeline kind filter with no rows
  ///
  /// In en, this message translates to:
  /// **'Nothing logged in this view yet.'**
  String get historyTimelineEmpty;

  /// Button to reset all History filters when none match
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get historyClearFilters;

  /// Empty-state title shown when the store has no runs at all
  ///
  /// In en, this message translates to:
  /// **'No runs yet'**
  String get historyEmptyTitle;

  /// Empty-state body shown when the store has no runs at all
  ///
  /// In en, this message translates to:
  /// **'Tap the Run tab to start your first run'**
  String get historyEmptyBody;

  /// Activity filter chip that clears the activity filter (shows all activities)
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get historyFilterAll;

  /// Source-filter option that clears the source filter
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get historySourceAll;

  /// Label on the History source-filter dropdown, showing the active source
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String historySourceLabel(String source);

  /// Tooltip on the History source-filter dropdown
  ///
  /// In en, this message translates to:
  /// **'Filter by source'**
  String get historySourceFilterTooltip;

  /// Source-filter label for runs recorded in-app
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get historySourceRecorded;

  /// Source-filter label for runs recorded on a paired watch
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get historySourceWatch;

  /// Source-filter label for runs imported from Strava — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'Strava'**
  String get historySourceStrava;

  /// Source-filter label for parkrun-imported runs — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'parkrun'**
  String get historySourceParkrun;

  /// Source-filter label for HealthKit-imported runs — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'HealthKit'**
  String get historySourceHealthKit;

  /// Source-filter label for Health Connect-imported runs — brand name, not translated
  ///
  /// In en, this message translates to:
  /// **'Health Connect'**
  String get historySourceHealthConnect;

  /// Title of the custom date-range picker bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Select dates'**
  String get historyRangePickerTitle;

  /// Label on the start-date chip in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get historyRangeStart;

  /// Label on the end-date chip in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get historyRangeEnd;

  /// Placeholder on an unset endpoint chip in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Tap a date'**
  String get historyRangeTapDate;

  /// Apply button in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get historyRangeApply;

  /// Clear button in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get historyRangeClear;

  /// Tooltip on the previous-month chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get historyPrevMonth;

  /// Tooltip on the next-month chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get historyNextMonth;

  /// Tooltip on the previous-year chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Previous year'**
  String get historyPrevYear;

  /// Tooltip on the next-year chevron in the date-range picker
  ///
  /// In en, this message translates to:
  /// **'Next year'**
  String get historyNextYear;

  /// Title of the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete {count} run?} other{Delete {count} runs?}}'**
  String historyDeleteConfirmTitle(int count);

  /// Body of the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get historyDeleteConfirmBody;

  /// Cancel action in the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get historyCancel;

  /// Confirm action in the bulk-delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get historyDelete;

  /// Tooltip on the per-row unsynced icon in the runs list
  ///
  /// In en, this message translates to:
  /// **'Queued to sync'**
  String get historyQueuedToSync;

  /// Banner shown when tapping sync while signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in from Settings to sync runs'**
  String get historySignInToSync;

  /// Banner shown when a cloud refresh of the runs list fails
  ///
  /// In en, this message translates to:
  /// **'Could not refresh — check your connection'**
  String get historyRefreshFailed;

  /// Banner shown when loading the next page of runs fails
  ///
  /// In en, this message translates to:
  /// **'Could not load more runs'**
  String get historyLoadMoreFailed;

  /// Banner shown after a sync that partially failed
  ///
  /// In en, this message translates to:
  /// **'Synced {synced}/{total}. Error: {error}'**
  String historySyncPartial(int synced, int total, String error);

  /// Detail message (used as the error in historySyncPartial) when some runs' track uploads fail during a manual sync
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run failed to upload its GPS track — the rest were synced. It will retry on the next cycle.} other{{count} runs failed to upload their GPS track — the rest were synced. The failed runs will retry on the next cycle.}}'**
  String historySyncTrackFailed(int count);

  /// Banner shown after every unsynced run uploads successfully
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run synced} other{All {count} runs synced}}'**
  String historySyncAllDone(int count);

  /// Banner shown when some runs deleted but others were queued for retry
  ///
  /// In en, this message translates to:
  /// **'{deleted} deleted; {queued} queued — will retry when back online.'**
  String historyDeletePartial(int deleted, int queued);

  /// Banner shown after a successful bulk delete
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Deleted {count} run} other{Deleted {count} runs}}'**
  String historyDeleteDone(int count);

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

  /// Tooltip on the report-run button shown to non-owner viewers
  ///
  /// In en, this message translates to:
  /// **'Report run'**
  String get runDetailReportRun;

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

  /// Secondary-stat label for grade-adjusted pace on run-detail
  ///
  /// In en, this message translates to:
  /// **'Grade-Adj. Pace'**
  String get runDetailStatGradeAdjPace;

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

  /// Banner shown when saving a run's track as a route fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save \"{name}\" as a route.'**
  String runDetailRouteSaveFailed(String name);

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

  /// Map-match status pill: backend unreachable, raw track shown and matching retries on reconnect
  ///
  /// In en, this message translates to:
  /// **'Offline — showing raw track, will retry'**
  String get runDetailMatchOffline;

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

  /// Banner shown when the initial route sync fails and the app falls back to the cached list
  ///
  /// In en, this message translates to:
  /// **'Could not sync routes — working offline'**
  String get routesSyncFailedOffline;

  /// Banner shown when loading the next page of routes fails
  ///
  /// In en, this message translates to:
  /// **'Could not load more routes'**
  String get routesLoadMoreFailed;

  /// Banner shown when toggling a route's star fails to persist to the cloud
  ///
  /// In en, this message translates to:
  /// **'Could not update star: {error}'**
  String routesStarUpdateFailed(String error);

  /// Banner shown when an imported route file resolves to an unreadable cloud-only content URI
  ///
  /// In en, this message translates to:
  /// **'Import failed: pick the file from local storage, not a cloud-only document picker.'**
  String get routesImportFailedLocalOnly;

  /// Banner shown after a route file is successfully imported
  ///
  /// In en, this message translates to:
  /// **'Imported \"{name}\"'**
  String routesImported(String name);

  /// Banner shown when importing a route file fails for any other reason
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String routesImportFailed(String error);

  /// Banner shown after a route built in the in-app builder is saved
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\"'**
  String routesSaved(String name);

  /// Empty-state title shown when the route library is empty
  ///
  /// In en, this message translates to:
  /// **'No routes yet'**
  String get routesEmptyTitle;

  /// Empty-state body shown when the route library is empty
  ///
  /// In en, this message translates to:
  /// **'Tap Build to draw a route on the map, or Import a GPX, KML, or TCX file.'**
  String get routesEmptyBody;

  /// Label on the build-route FAB and the empty-state legend reminder
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get routesBuild;

  /// Label on the import-route FAB and the empty-state legend reminder
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get routesImport;

  /// Empty-state shown when the active filters exclude every route
  ///
  /// In en, this message translates to:
  /// **'No routes match these filters'**
  String get routesNoMatch;

  /// Button to reset all route filters when none match
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get routesClearFilters;

  /// Button that reveals the next page of routes
  ///
  /// In en, this message translates to:
  /// **'Load {count} more'**
  String routesLoadMore(int count);

  /// Tooltip on the per-row will-sync icon for locally-built routes
  ///
  /// In en, this message translates to:
  /// **'Queued to sync'**
  String get routesQueuedToSync;

  /// Tooltip on the per-row offline-pin icon in the routes list
  ///
  /// In en, this message translates to:
  /// **'Saved for offline'**
  String get routesSavedForOffline;

  /// Tooltip on the per-row star button when the route is starred
  ///
  /// In en, this message translates to:
  /// **'Unstar route'**
  String get routesUnstarRoute;

  /// Tooltip on the per-row star button when the route is not starred
  ///
  /// In en, this message translates to:
  /// **'Star to show on watch'**
  String get routesStarForWatch;

  /// Section header for the Explore / Heatmap discovery strip in the embedded routes view
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get routesDiscover;

  /// Tooltip on the cloud-download sync button in the routes list
  ///
  /// In en, this message translates to:
  /// **'Sync from cloud'**
  String get routesSyncFromCloud;

  /// Label on the button that opens the Explore public-routes screen from the embedded routes view
  ///
  /// In en, this message translates to:
  /// **'Public routes'**
  String get routesPublicRoutes;

  /// Tooltip on the standalone-AppBar heatmap action in the routes list
  ///
  /// In en, this message translates to:
  /// **'Routes heatmap'**
  String get routesHeatmapTooltip;

  /// Placeholder in the routes-list search field
  ///
  /// In en, this message translates to:
  /// **'Search routes by name…'**
  String get routesSearchHint;

  /// Tooltip on the clear-search button in the routes-list search field
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get routesClearSearch;

  /// Filter-chip label for the starred-only route filter
  ///
  /// In en, this message translates to:
  /// **'Starred'**
  String get routesStarred;

  /// Meta row showing how many routes are visible out of the total
  ///
  /// In en, this message translates to:
  /// **'{total, plural, one{{visible} of {total} route} other{{visible} of {total} routes}}'**
  String routesCountMeta(int visible, int total);

  /// Surface-filter dropdown option that clears the surface filter
  ///
  /// In en, this message translates to:
  /// **'Any surface'**
  String get routesSurfaceAny;

  /// Surface-filter dropdown option for road routes
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get routesSurfaceRoad;

  /// Surface-filter dropdown option for trail routes
  ///
  /// In en, this message translates to:
  /// **'Trail'**
  String get routesSurfaceTrail;

  /// Surface-filter dropdown option for mixed-surface routes
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get routesSurfaceMixed;

  /// Distance-filter dropdown option that clears the distance filter
  ///
  /// In en, this message translates to:
  /// **'Any distance'**
  String get routesDistanceAny;

  /// Sort dropdown option: newest routes first
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get routesSortNewest;

  /// Sort dropdown option: longest distance first
  ///
  /// In en, this message translates to:
  /// **'Longest'**
  String get routesSortLongest;

  /// Sort dropdown option: shortest distance first
  ///
  /// In en, this message translates to:
  /// **'Shortest'**
  String get routesSortShortest;

  /// Sort dropdown option: most-run routes first
  ///
  /// In en, this message translates to:
  /// **'Most-run'**
  String get routesSortMostRun;

  /// Sort dropdown option: alphabetical by name
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get routesSortAlpha;

  /// Title of the bulk-delete confirmation dialog in the routes list
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete {count} route?} other{Delete {count} routes?}}'**
  String routesDeleteConfirmTitle(int count);

  /// Body of the bulk-delete confirmation dialog in the routes list
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get routesDeleteConfirmBody;

  /// Title in the routes-list selection banner showing how many are selected
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String routesSelectionTitle(int count);

  /// Banner shown when some routes deleted but others failed
  ///
  /// In en, this message translates to:
  /// **'{deleted} deleted; {failed} failed — check your connection.'**
  String routesDeletePartial(int deleted, int failed);

  /// Banner shown after a successful bulk delete of routes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} route deleted.} other{{count} routes deleted.}}'**
  String routesDeleteDone(int count);

  /// Screen-reader announcement when the builder's route is cleared
  ///
  /// In en, this message translates to:
  /// **'Route cleared'**
  String get routeBuilderRouteCleared;

  /// Screen-reader announcement summarising the current route after a mutation
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} point, {distance}} other{{count} points, {distance}}}'**
  String routeBuilderPointsSummary(int count, String distance);

  /// Banner shown when every routing segment fell back to a straight line
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t route — showing straight lines through your pins.'**
  String get routeBuilderRouteFailedStraightLines;

  /// Banner shown when some routing segments couldn't snap to a road
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} segment couldn\'t snap to a road. Drag the affected pin to adjust.} other{{count} segments couldn\'t snap to a road. Drag the affected pins to adjust.}}'**
  String routeBuilderSegmentsFailed(int count);

  /// Banner shown when a routing pass throws
  ///
  /// In en, this message translates to:
  /// **'Routing failed: {error}'**
  String routeBuilderRoutingFailed(String error);

  /// Banner shown when a dragged waypoint lands too close to another
  ///
  /// In en, this message translates to:
  /// **'Too close to another pin — drag a bit further.'**
  String get routeBuilderTooCloseToPin;

  /// Banner shown when a tapped waypoint would duplicate an existing one
  ///
  /// In en, this message translates to:
  /// **'Pin already there — tap further apart to add another.'**
  String get routeBuilderPinAlreadyThere;

  /// Banner shown when the generate-loop target distance is out of range
  ///
  /// In en, this message translates to:
  /// **'Enter a target distance up to 1000 km.'**
  String get routeBuilderTargetTooLong;

  /// Banner shown when saving with fewer than two waypoints
  ///
  /// In en, this message translates to:
  /// **'Place at least two waypoints first.'**
  String get routeBuilderSaveNeedTwo;

  /// Banner shown when a built route saved locally but the cloud push failed
  ///
  /// In en, this message translates to:
  /// **'Saved locally. {detail} Will sync next time.'**
  String routeBuilderSavedLocally(String detail);

  /// Banner shown when the Locate-me FAB can't get a position
  ///
  /// In en, this message translates to:
  /// **'Location unavailable: {error}'**
  String routeBuilderLocationUnavailable(String error);

  /// Friendly save-route error message when Supabase couldn't be reached
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Sign in or check your connection and try again.'**
  String get routeBuilderServerUnreachable;

  /// Generic save-route error message
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String routeBuilderSaveFailed(String error);

  /// Placeholder in the route builder's place-search field
  ///
  /// In en, this message translates to:
  /// **'Search places…'**
  String get routeBuilderSearchHint;

  /// Tooltip on the route builder's overflow menu while searching
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get routeBuilderMore;

  /// Generate-loop action label (AppBar tooltip, menu item, and dialog title)
  ///
  /// In en, this message translates to:
  /// **'Generate loop'**
  String get routeBuilderGenerateLoop;

  /// Undo action label in the route builder
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get routeBuilderUndo;

  /// Clear action label in the route builder
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get routeBuilderClear;

  /// Confirm-clear dialog title in the route builder
  ///
  /// In en, this message translates to:
  /// **'Clear this route?'**
  String get routeBuilderClearConfirmTitle;

  /// Confirm-clear dialog body in the route builder
  ///
  /// In en, this message translates to:
  /// **'All waypoints will be removed. This can\'t be undone.'**
  String get routeBuilderClearConfirmBody;

  /// Save button label while a save is in progress
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get routeBuilderSaving;

  /// Save button label in the route builder
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get routeBuilderSave;

  /// Tooltip on the route builder's Locate-me FAB
  ///
  /// In en, this message translates to:
  /// **'Locate me'**
  String get routeBuilderLocateMe;

  /// Status pill text while a waypoint is lifted for dragging
  ///
  /// In en, this message translates to:
  /// **'Tap to move point {number}, or use the icons'**
  String routeBuilderTapToMovePoint(int number);

  /// Status pill text when no waypoints are placed yet, showing the active mode
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place waypoints · {mode}'**
  String routeBuilderEmptyHint(String mode);

  /// Status pill text when exactly one waypoint is placed, showing the active mode
  ///
  /// In en, this message translates to:
  /// **'Place another to draw the line · {mode}'**
  String routeBuilderOnePointHint(String mode);

  /// Status pill text with distance, elevation gain, and waypoint count
  ///
  /// In en, this message translates to:
  /// **'{distance} · {gain} m ↑ · {count, plural, one{{count} point} other{{count} points}}'**
  String routeBuilderStatusGain(String distance, int gain, int count);

  /// Status pill text with distance and waypoint count when elevation gain is unknown
  ///
  /// In en, this message translates to:
  /// **'{distance} · {count, plural, one{{count} point} other{{count} points}}'**
  String routeBuilderStatusNoGain(String distance, int count);

  /// Tooltip on the delete-dragged-waypoint button in the status pill
  ///
  /// In en, this message translates to:
  /// **'Delete point {number}'**
  String routeBuilderDeletePoint(int number);

  /// Tooltip on the cancel-drag button in the status pill
  ///
  /// In en, this message translates to:
  /// **'Cancel drag'**
  String get routeBuilderCancelDrag;

  /// Title of the waypoint-list bottom sheet + tooltip on the AppBar action that opens it
  ///
  /// In en, this message translates to:
  /// **'Route points'**
  String get routeBuilderPointList;

  /// Screen-reader announcement after reordering a waypoint in the list sheet
  ///
  /// In en, this message translates to:
  /// **'Point {from} moved to position {to}'**
  String routeBuilderPointMovedTo(int from, int to);

  /// Screen-reader announcement after deleting a waypoint from the list sheet
  ///
  /// In en, this message translates to:
  /// **'Point {number} removed'**
  String routeBuilderPointRemoved(int number);

  /// Semantics label on the per-row drag handle in the waypoint-list sheet
  ///
  /// In en, this message translates to:
  /// **'Reorder point {number}'**
  String routeBuilderReorderPoint(int number);

  /// Subtitle tag on the first waypoint row in the list sheet
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get routeBuilderPointStart;

  /// Subtitle tag on the last waypoint row in the list sheet
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get routeBuilderPointEnd;

  /// Mode-toggle label for the trail (foot) routing profile
  ///
  /// In en, this message translates to:
  /// **'Trail'**
  String get routeBuilderModeTrail;

  /// Mode-toggle label for the road (car) routing profile
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get routeBuilderModeRoad;

  /// Mode-toggle label for the straight-line (no routing) profile
  ///
  /// In en, this message translates to:
  /// **'Straight'**
  String get routeBuilderModeStraight;

  /// Body text of the generate-loop dialog
  ///
  /// In en, this message translates to:
  /// **'Target distance — we\'ll build a radial loop around the current map centre.'**
  String get routeBuilderLoopDialogBody;

  /// Cancel action in route builder dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get routeBuilderCancel;

  /// Confirm action in the generate-loop dialog
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get routeBuilderGenerate;

  /// Title of the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'Save route'**
  String get routeBuilderSaveDialogTitle;

  /// Label for the name field in the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get routeBuilderNameLabel;

  /// Hint for the name field in the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'e.g. River loop'**
  String get routeBuilderNameHint;

  /// Label for the description field in the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get routeBuilderDescriptionLabel;

  /// Hint for the description field in the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'Surface, hills, parking, anything worth noting'**
  String get routeBuilderDescriptionHint;

  /// Label for the club picker in the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'Save to'**
  String get routeBuilderSaveToLabel;

  /// Default option in the save-route club picker
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get routeBuilderSaveToPersonal;

  /// Title of the make-public toggle in the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'Make public'**
  String get routeBuilderMakePublic;

  /// Subtitle of the make-public toggle in the save-route dialog
  ///
  /// In en, this message translates to:
  /// **'Others can find it on Explore'**
  String get routeBuilderMakePublicSubtitle;

  /// Label on the route-detail Start-run FAB
  ///
  /// In en, this message translates to:
  /// **'Start run'**
  String get routeDetailStartRun;

  /// Tooltip on the route-detail share menu
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get routeDetailShare;

  /// Share-menu option to share the route as an image
  ///
  /// In en, this message translates to:
  /// **'Share as image'**
  String get routeDetailShareAsImage;

  /// Share-menu option to share the route as a GPX file
  ///
  /// In en, this message translates to:
  /// **'Share as GPX'**
  String get routeDetailShareAsGpx;

  /// Share-menu option to share the route as a KML file
  ///
  /// In en, this message translates to:
  /// **'Share as KML'**
  String get routeDetailShareAsKml;

  /// Share-menu option to share the route as a GPX file including the course markers (aid stations, cutoffs) as waypoints
  ///
  /// In en, this message translates to:
  /// **'Share as GPX + markers'**
  String get routeDetailShareAsGpxMarkers;

  /// Tooltip on the offline-pin button when the route is pinned
  ///
  /// In en, this message translates to:
  /// **'Remove offline save'**
  String get routeDetailRemoveOfflineSave;

  /// Tooltip on the offline-pin button when the route is not pinned
  ///
  /// In en, this message translates to:
  /// **'Save for offline use'**
  String get routeDetailSaveForOffline;

  /// Tooltip on the route-detail star button when starred
  ///
  /// In en, this message translates to:
  /// **'Unstar route'**
  String get routeDetailUnstarRoute;

  /// Tooltip on the route-detail star button when not starred
  ///
  /// In en, this message translates to:
  /// **'Star to show on watch'**
  String get routeDetailStarForWatch;

  /// Tooltip on the route-detail visibility toggle when public
  ///
  /// In en, this message translates to:
  /// **'Make private'**
  String get routeDetailMakePrivate;

  /// Tooltip on the route-detail visibility toggle when private
  ///
  /// In en, this message translates to:
  /// **'Make public'**
  String get routeDetailMakePublic;

  /// Tooltip on the route-detail bookmark button when bookmarked
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get routeDetailRemoveBookmark;

  /// Tooltip on the route-detail bookmark button when not bookmarked
  ///
  /// In en, this message translates to:
  /// **'Bookmark route'**
  String get routeDetailBookmarkRoute;

  /// Tooltip on the route-detail report button
  ///
  /// In en, this message translates to:
  /// **'Report route'**
  String get routeDetailReportRoute;

  /// Tooltip on the route-detail transfer button when the route is personal
  ///
  /// In en, this message translates to:
  /// **'Transfer to club'**
  String get routeDetailTransferToClub;

  /// Tooltip on the route-detail transfer button when the route belongs to a club
  ///
  /// In en, this message translates to:
  /// **'Detach or move to another club'**
  String get routeDetailManageClub;

  /// Tooltip on the route-detail delete button
  ///
  /// In en, this message translates to:
  /// **'Delete route'**
  String get routeDetailDeleteRoute;

  /// Stat label for distance on the route-detail screen
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get routeDetailStatDistance;

  /// Stat label for elevation on the route-detail screen
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get routeDetailStatElevation;

  /// Stat label for the review count on the route-detail screen
  ///
  /// In en, this message translates to:
  /// **'{count} reviews'**
  String routeDetailStatReviews(int count);

  /// Stat label for the waypoint count on the route-detail screen
  ///
  /// In en, this message translates to:
  /// **'Waypoints'**
  String get routeDetailStatWaypoints;

  /// Title of the inline visibility row when the route is public
  ///
  /// In en, this message translates to:
  /// **'Public route'**
  String get routeDetailPublicRoute;

  /// Title of the inline visibility row when the route is private
  ///
  /// In en, this message translates to:
  /// **'Private route'**
  String get routeDetailPrivateRoute;

  /// Subtitle of the inline visibility row when the route is public
  ///
  /// In en, this message translates to:
  /// **'Anyone with the share link can view this route'**
  String get routeDetailPublicSubtitle;

  /// Subtitle of the inline visibility row when the route is private
  ///
  /// In en, this message translates to:
  /// **'Only you can see this route'**
  String get routeDetailPrivateSubtitle;

  /// Title of the inline offline-save row when the route is pinned
  ///
  /// In en, this message translates to:
  /// **'Saved for offline'**
  String get routeDetailSavedForOffline;

  /// Title of the inline offline-save row when the route is not pinned
  ///
  /// In en, this message translates to:
  /// **'Save for offline'**
  String get routeDetailSaveForOfflineTitle;

  /// Subtitle of the inline offline-save row when the route is pinned
  ///
  /// In en, this message translates to:
  /// **'Route stays on this phone so you can run it without a connection.'**
  String get routeDetailOfflinePinnedSubtitle;

  /// Subtitle of the inline offline-save row when the route is not pinned
  ///
  /// In en, this message translates to:
  /// **'Keep this route on your phone for use without a network.'**
  String get routeDetailOfflineUnpinnedSubtitle;

  /// Section heading for the route description
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get routeDetailDescriptionHeading;

  /// Button that generates a description for a route with none stored
  ///
  /// In en, this message translates to:
  /// **'Describe this route'**
  String get routeDetailDescribe;

  /// Button label while a route description is being generated
  ///
  /// In en, this message translates to:
  /// **'Describing…'**
  String get routeDetailDescribing;

  /// Attribution line under an AI-written route description
  ///
  /// In en, this message translates to:
  /// **'Written by AI from this route\'s stats'**
  String get routeDetailAiAttribution;

  /// Non-blocking error when the AI enhancement fails; the templated baseline stays shown
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t generate a description. Please try again.'**
  String get routeDetailDescribeFailed;

  /// Upsell shown to free users; the templated description still shows
  ///
  /// In en, this message translates to:
  /// **'AI descriptions are a Pro feature. Upgrade to enhance.'**
  String get routeDetailEnhanceUpgradeHint;

  /// Route shape word: a route that returns to its start
  ///
  /// In en, this message translates to:
  /// **'loop'**
  String get routeDetailDescShapeLoop;

  /// Route shape word: out and back along the same path
  ///
  /// In en, this message translates to:
  /// **'out-and-back'**
  String get routeDetailDescShapeOutAndBack;

  /// Route shape word: starts and ends in different places
  ///
  /// In en, this message translates to:
  /// **'point-to-point'**
  String get routeDetailDescShapePointToPoint;

  /// Route surface word used inside the templated description sentence
  ///
  /// In en, this message translates to:
  /// **'road'**
  String get routeDetailDescSurfaceRoad;

  /// Route surface word used inside the templated description sentence
  ///
  /// In en, this message translates to:
  /// **'trail'**
  String get routeDetailDescSurfaceTrail;

  /// Route surface word used inside the templated description sentence
  ///
  /// In en, this message translates to:
  /// **'mixed-surface'**
  String get routeDetailDescSurfaceMixed;

  /// Elevation character word inside the templated climb clause
  ///
  /// In en, this message translates to:
  /// **'flat'**
  String get routeDetailDescElevFlat;

  /// Elevation character word inside the templated climb clause
  ///
  /// In en, this message translates to:
  /// **'gently rolling'**
  String get routeDetailDescElevRolling;

  /// Elevation character word inside the templated climb clause
  ///
  /// In en, this message translates to:
  /// **'hilly'**
  String get routeDetailDescElevHilly;

  /// Elevation character word inside the templated climb clause
  ///
  /// In en, this message translates to:
  /// **'mountainous'**
  String get routeDetailDescElevMountainous;

  /// Templated route description sentence with a surface word
  ///
  /// In en, this message translates to:
  /// **'{name} is a {distance} {surface} {shape} route.'**
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  );

  /// Templated route description sentence when the surface is unknown
  ///
  /// In en, this message translates to:
  /// **'{name} is a {distance} {shape} route.'**
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  );

  /// Templated climb clause appended when the route has elevation gain
  ///
  /// In en, this message translates to:
  /// **'It has {gain} of climbing — {elevation}, about {perKm} per km.'**
  String routeDetailDescClimb(String gain, String elevation, String perKm);

  /// Templated clause appended when the route is essentially flat
  ///
  /// In en, this message translates to:
  /// **'It has little to no elevation change.'**
  String get routeDetailDescFlat;

  /// Per-kilometre gain figure embedded in the climb clause
  ///
  /// In en, this message translates to:
  /// **'{m} m'**
  String routeDetailDescPerKm(int m);

  /// Meta chip showing how many runs used this route
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run} other{{count} runs}}'**
  String routeDetailRunCount(int count);

  /// Meta chip shown for featured routes
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get routeDetailFeatured;

  /// Uppercase surface label for trail routes in the meta chip
  ///
  /// In en, this message translates to:
  /// **'TRAIL'**
  String get routeDetailSurfaceTrail;

  /// Uppercase surface label for mixed-surface routes in the meta chip
  ///
  /// In en, this message translates to:
  /// **'MIXED'**
  String get routeDetailSurfaceMixed;

  /// Uppercase surface label for road routes in the meta chip
  ///
  /// In en, this message translates to:
  /// **'ROAD'**
  String get routeDetailSurfaceRoad;

  /// Hint for the owner-only add-tag field on route detail
  ///
  /// In en, this message translates to:
  /// **'add tag'**
  String get routeDetailAddTagHint;

  /// Section heading for the reviews list on route detail
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get routeDetailReviewsHeading;

  /// Label on the button that opens the rate-route dialog
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get routeDetailRate;

  /// Accessible tooltip for each star button in the rate-route dialog
  ///
  /// In en, this message translates to:
  /// **'Set rating to {n} of 5'**
  String routeDetailRateStars(int n);

  /// Empty-state shown when reviews can't be loaded offline
  ///
  /// In en, this message translates to:
  /// **'Reviews unavailable offline'**
  String get routeDetailReviewsOffline;

  /// Empty-state shown when a route has no reviews
  ///
  /// In en, this message translates to:
  /// **'No reviews yet'**
  String get routeDetailNoReviews;

  /// Title of the rate-route dialog
  ///
  /// In en, this message translates to:
  /// **'Rate this route'**
  String get routeDetailRateDialogTitle;

  /// Label for the comment field in the rate-route dialog
  ///
  /// In en, this message translates to:
  /// **'Comment (optional)'**
  String get routeDetailCommentLabel;

  /// Cancel action in route-detail dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get routeDetailCancel;

  /// Submit action in the rate-route dialog
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get routeDetailSubmit;

  /// Banner shown when a signed-out user tries to review a route
  ///
  /// In en, this message translates to:
  /// **'Sign in to leave a review'**
  String get routeDetailSignInToReview;

  /// Banner shown when submitting a review fails
  ///
  /// In en, this message translates to:
  /// **'Failed to submit review: {error}'**
  String routeDetailReviewFailed(String error);

  /// Banner shown when toggling a bookmark fails
  ///
  /// In en, this message translates to:
  /// **'Bookmark failed: {error}'**
  String routeDetailBookmarkFailed(String error);

  /// Banner shown when a route is made public while offline
  ///
  /// In en, this message translates to:
  /// **'Route set to public. Will sync next time.'**
  String get routeDetailPublicWillSync;

  /// Banner shown when a route is made private while offline
  ///
  /// In en, this message translates to:
  /// **'Route set to private. Will sync next time.'**
  String get routeDetailPrivateWillSync;

  /// Banner shown when toggling route visibility fails on the cloud
  ///
  /// In en, this message translates to:
  /// **'Could not update visibility: {error}'**
  String routeDetailVisibilityFailed(String error);

  /// Banner shown when toggling the route star fails on the cloud
  ///
  /// In en, this message translates to:
  /// **'Could not update star: {error}'**
  String routeDetailStarFailed(String error);

  /// Banner shown when a route is pinned for offline use
  ///
  /// In en, this message translates to:
  /// **'Saved for offline use.'**
  String get routeDetailOfflineSaved;

  /// Banner shown when a route is unpinned from offline use
  ///
  /// In en, this message translates to:
  /// **'Removed from offline saves.'**
  String get routeDetailOfflineRemoved;

  /// Banner shown when adding a route tag fails
  ///
  /// In en, this message translates to:
  /// **'Could not save tag: {error}'**
  String routeDetailTagSaveFailed(String error);

  /// Banner shown when removing a route tag fails
  ///
  /// In en, this message translates to:
  /// **'Could not remove tag: {error}'**
  String routeDetailTagRemoveFailed(String error);

  /// Banner shown when sharing a route as a file fails
  ///
  /// In en, this message translates to:
  /// **'Could not share {format}: {error}'**
  String routeDetailShareFailed(String format, String error);

  /// Banner shown when the transfer-to-club club fetch times out
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your clubs — check your network.'**
  String get routeDetailClubsLoadTimeout;

  /// Banner shown when the transfer-to-club club fetch fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your clubs.'**
  String get routeDetailClubsLoadFailed;

  /// Banner shown after detaching a route from a club
  ///
  /// In en, this message translates to:
  /// **'Detached from club; route is now personal.'**
  String get routeDetailDetached;

  /// Banner shown after moving a route into a club library
  ///
  /// In en, this message translates to:
  /// **'Route moved into the club library.'**
  String get routeDetailMovedToClub;

  /// Banner shown when transferring a route to/from a club fails
  ///
  /// In en, this message translates to:
  /// **'Transfer failed: {error}'**
  String routeDetailTransferFailed(String error);

  /// Title of the single-route delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete route?'**
  String get routeDetailDeleteTitle;

  /// Body of the single-route delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get routeDetailDeleteBody;

  /// Confirm action in the delete-route dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get routeDetailDelete;

  /// Banner shown when deleting a route fails
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String routeDetailDeleteFailed(String error);

  /// Label on the route-detail preview scrubber
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get routeDetailPreview;

  /// Start endpoint label under the route-detail preview scrubber
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get routeDetailPreviewStart;

  /// Finish endpoint label under the route-detail preview scrubber
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get routeDetailPreviewFinish;

  /// Title of the transfer-route sheet when the route is currently personal
  ///
  /// In en, this message translates to:
  /// **'Transfer to club'**
  String get routeDetailTransferDialogTitle;

  /// Title of the transfer-route sheet when the route already belongs to a club
  ///
  /// In en, this message translates to:
  /// **'Manage club ownership'**
  String get routeDetailManageClubTitle;

  /// Body of the transfer-route sheet when the route is currently personal
  ///
  /// In en, this message translates to:
  /// **'Members of the club will see this route in the club library and can adopt it onto their plans.'**
  String get routeDetailTransferDialogBody;

  /// Body of the transfer-route sheet when the route already belongs to a club
  ///
  /// In en, this message translates to:
  /// **'Move this route into another club you admin, or detach it back to personal.'**
  String get routeDetailManageClubBody;

  /// Title of the detach-to-personal option in the transfer-route sheet
  ///
  /// In en, this message translates to:
  /// **'Detach to personal'**
  String get routeDetailDetachToPersonal;

  /// Subtitle of the detach-to-personal option in the transfer-route sheet
  ///
  /// In en, this message translates to:
  /// **'Removes the route from the current club\'s library.'**
  String get routeDetailDetachSubtitle;

  /// Empty-state shown in the transfer-route sheet when the user has no admin clubs
  ///
  /// In en, this message translates to:
  /// **'You don\'t own or admin any clubs yet.'**
  String get routeDetailNoAdminClubs;

  /// Subtitle marking the route's current club in the transfer-route sheet
  ///
  /// In en, this message translates to:
  /// **'Current club'**
  String get routeDetailCurrentClub;

  /// Subtitle showing a club's location and member count in the transfer-route sheet
  ///
  /// In en, this message translates to:
  /// **'{location} · {count, plural, one{{count} member} other{{count} members}}'**
  String routeDetailClubMemberCount(String location, int count);

  /// AppBar title for the explore-public-routes screen
  ///
  /// In en, this message translates to:
  /// **'Explore Routes'**
  String get exploreRoutesTitle;

  /// Mode-toggle label for the search-by-name mode
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get exploreRoutesModeSearch;

  /// Mode-toggle label for the near-me mode
  ///
  /// In en, this message translates to:
  /// **'Near Me'**
  String get exploreRoutesModeNearMe;

  /// Placeholder in the explore search field
  ///
  /// In en, this message translates to:
  /// **'Search routes by name...'**
  String get exploreRoutesSearchHint;

  /// Featured-only filter-chip label on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get exploreRoutesFeatured;

  /// Error state shown when exploring routes while signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in and connect to the internet to explore routes'**
  String get exploreRoutesSignInRequired;

  /// Error state shown when an explore search times out
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network and try again.'**
  String get exploreRoutesTimeout;

  /// Error state shown when an explore search fails
  ///
  /// In en, this message translates to:
  /// **'Search failed. Tap retry to try again.'**
  String get exploreRoutesSearchFailed;

  /// Banner shown when loading the next page of explore results fails
  ///
  /// In en, this message translates to:
  /// **'Could not load more — check your connection'**
  String get exploreRoutesLoadMoreFailed;

  /// Error state shown when location permission is denied in near-me mode
  ///
  /// In en, this message translates to:
  /// **'Location permission required to find nearby routes'**
  String get exploreRoutesLocationPermissionRequired;

  /// Error state shown when a near-me search fails
  ///
  /// In en, this message translates to:
  /// **'Could not find nearby routes. Tap retry to try again.'**
  String get exploreRoutesNearbyFailed;

  /// Empty-state title when there are no public routes and no search query
  ///
  /// In en, this message translates to:
  /// **'No public routes yet'**
  String get exploreRoutesEmptyNoPublic;

  /// Empty-state title when a search returns no results
  ///
  /// In en, this message translates to:
  /// **'No routes match your search'**
  String get exploreRoutesEmptyNoMatch;

  /// Empty-state body on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Routes shared from the web app appear here'**
  String get exploreRoutesEmptyBody;

  /// Distance-filter option that clears the distance filter on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Any distance'**
  String get exploreRoutesDistanceAny;

  /// Surface-filter option that clears the surface filter on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Any surface'**
  String get exploreRoutesSurfaceAny;

  /// Surface-filter option for road routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get exploreRoutesSurfaceRoad;

  /// Surface-filter option for trail routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Trail'**
  String get exploreRoutesSurfaceTrail;

  /// Surface-filter option for mixed-surface routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get exploreRoutesSurfaceMixed;

  /// Sort option: most-run routes first on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Most run'**
  String get exploreRoutesSortMostRun;

  /// Sort option: newest routes first on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get exploreRoutesSortNewest;

  /// Sort option: featured routes first on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get exploreRoutesSortFeatured;

  /// Fallback label on the sort filter chip on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get exploreRoutesSort;

  /// Banner shown when a saved explore route can't fetch its geometry
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save \"{name}\" — check your connection and try again.'**
  String exploreRoutesSaveCheckConnection(String name);

  /// Banner shown when persisting a saved explore route fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save \"{name}\".'**
  String exploreRoutesSaveFailed(String name);

  /// Banner shown after a route is saved to the user's library from explore
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\" to your library'**
  String exploreRoutesSaved(String name);

  /// Tooltip on the save button when an explore route is already in the library
  ///
  /// In en, this message translates to:
  /// **'Already saved'**
  String get exploreRoutesAlreadySaved;

  /// Tooltip on the save button on an explore route card
  ///
  /// In en, this message translates to:
  /// **'Save to library'**
  String get exploreRoutesSaveToLibrary;

  /// Surface badge label for trail routes on an explore route card
  ///
  /// In en, this message translates to:
  /// **'Trail'**
  String get exploreRoutesSurfaceTrailShort;

  /// Surface badge label for mixed-surface routes on an explore route card
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get exploreRoutesSurfaceMixedShort;

  /// Surface badge label for road routes on an explore route card
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get exploreRoutesSurfaceRoadShort;

  /// Distance-filter label (km) for short routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Under 5 km'**
  String get exploreRoutesDistanceUnderKm;

  /// Distance-filter label (km) for medium routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'5-10 km'**
  String get exploreRoutesDistanceMidKm;

  /// Distance-filter label (km) for long routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'10-21 km'**
  String get exploreRoutesDistanceLongKm;

  /// Distance-filter label (km) for ultra routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'21 km+'**
  String get exploreRoutesDistanceUltraKm;

  /// Distance-filter label (mi) for short routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'Under 3 mi'**
  String get exploreRoutesDistanceUnderMi;

  /// Distance-filter label (mi) for medium routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'3-6 mi'**
  String get exploreRoutesDistanceMidMi;

  /// Distance-filter label (mi) for long routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'6-13 mi'**
  String get exploreRoutesDistanceLongMi;

  /// Distance-filter label (mi) for ultra routes on the explore screen
  ///
  /// In en, this message translates to:
  /// **'13 mi+'**
  String get exploreRoutesDistanceUltraMi;

  /// Placeholder in the heatmap place-search field
  ///
  /// In en, this message translates to:
  /// **'Search places…'**
  String get heatmapSearchHint;

  /// Tooltip on the heatmap Filters button
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get heatmapFilters;

  /// Header of the cluster sheet listing routes that share a start point
  ///
  /// In en, this message translates to:
  /// **'{count} routes start here'**
  String heatmapRoutesStartHere(int count);

  /// Route-count text on the heatmap results pill and list header
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} route} other{{count} routes}}'**
  String heatmapRouteCount(int count);

  /// Pill text shown when no routes are in view on the heatmap
  ///
  /// In en, this message translates to:
  /// **'No routes here'**
  String get heatmapNoRoutesHere;

  /// Empty-state shown in the heatmap results list
  ///
  /// In en, this message translates to:
  /// **'No routes here. Pan the map or change the filters.'**
  String get heatmapNoRoutesHint;

  /// Button to clear the pinned (kept-on-map) routes in the heatmap results list
  ///
  /// In en, this message translates to:
  /// **'Clear {count} kept'**
  String heatmapClearKept(int count);

  /// Tooltip on the keep-on-map toggle when a heatmap route is pinned
  ///
  /// In en, this message translates to:
  /// **'Unpin from map'**
  String get heatmapUnpinFromMap;

  /// Tooltip on the keep-on-map toggle when a heatmap route is not pinned
  ///
  /// In en, this message translates to:
  /// **'Keep on map'**
  String get heatmapKeepOnMap;

  /// Tooltip on the heatmap Locate-me FAB
  ///
  /// In en, this message translates to:
  /// **'Locate me'**
  String get heatmapLocateMe;

  /// Banner shown when the heatmap Locate-me FAB can't get a position
  ///
  /// In en, this message translates to:
  /// **'Location unavailable: {error}'**
  String heatmapLocationUnavailable(String error);

  /// Tooltip on the close button of the heatmap selection card
  ///
  /// In en, this message translates to:
  /// **'Back to list'**
  String get heatmapBackToList;

  /// Label on the View-route button in the heatmap selection card
  ///
  /// In en, this message translates to:
  /// **'View route'**
  String get heatmapViewRoute;

  /// Label on the keep button when a heatmap route is pinned
  ///
  /// In en, this message translates to:
  /// **'Kept'**
  String get heatmapKept;

  /// Label on the keep button when a heatmap route is not pinned
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get heatmapKeep;

  /// Filter-group label for the discovery-lens chips in the heatmap filter sheet
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get heatmapLensShow;

  /// Filter-group label for the race-distance chips in the heatmap filter sheet
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get heatmapLensDistance;

  /// Filter-group label for the map-display chips in the heatmap filter sheet
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get heatmapLensMap;

  /// Filter chip toggling the heat-density layer in the heatmap filter sheet
  ///
  /// In en, this message translates to:
  /// **'Heat density'**
  String get heatmapHeatDensity;

  /// Button to reset all heatmap filters
  ///
  /// In en, this message translates to:
  /// **'Reset filters'**
  String get heatmapResetFilters;

  /// Discovery-lens label for popular routes on the heatmap
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get heatmapLensPopular;

  /// Discovery-lens label for friends' routes on the heatmap
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get heatmapLensFriends;

  /// Discovery-lens label for featured routes on the heatmap
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get heatmapLensFeatured;

  /// Discovery-lens label for hidden-gem routes on the heatmap
  ///
  /// In en, this message translates to:
  /// **'Hidden gems'**
  String get heatmapLensHiddenGems;

  /// AppBar title for the personal run-track heatmap screen
  ///
  /// In en, this message translates to:
  /// **'Your heatmap'**
  String get runHeatmapTitle;

  /// Tooltip on the run-list action that opens the personal run-track heatmap
  ///
  /// In en, this message translates to:
  /// **'Run heatmap'**
  String get runHeatmapTooltip;

  /// Status pill shown while the personal heatmap downloads tracks
  ///
  /// In en, this message translates to:
  /// **'Loading your runs…'**
  String get runHeatmapLoading;

  /// Status pill with track download progress on the personal heatmap
  ///
  /// In en, this message translates to:
  /// **'Loading your runs… {n}/{total}'**
  String runHeatmapLoadingProgress(int n, int total);

  /// Empty-state title on the personal run-track heatmap
  ///
  /// In en, this message translates to:
  /// **'No mapped runs yet'**
  String get runHeatmapEmptyTitle;

  /// Empty-state body on the personal run-track heatmap
  ///
  /// In en, this message translates to:
  /// **'Record or import runs with GPS tracks and they\'ll light up here.'**
  String get runHeatmapEmptyBody;

  /// Error-state title on the personal run-track heatmap when the runs fetch fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your heatmap'**
  String get runHeatmapErrorTitle;

  /// Error-state body on the personal run-track heatmap when the runs fetch fails
  ///
  /// In en, this message translates to:
  /// **'Something went wrong loading your runs. Check your connection and try again.'**
  String get runHeatmapErrorBody;

  /// Retry button on the personal run-track heatmap error state
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get runHeatmapRetry;

  /// Legend title on the personal run-track heatmap
  ///
  /// In en, this message translates to:
  /// **'Your heatmap'**
  String get runHeatmapLegendTitle;

  /// Legend summary on the personal heatmap for a single mapped run
  ///
  /// In en, this message translates to:
  /// **'{n} mapped run — brighter where you run most.'**
  String runHeatmapLegendSummaryOne(int n);

  /// Legend summary on the personal heatmap for multiple mapped runs
  ///
  /// In en, this message translates to:
  /// **'{n} mapped runs — brighter where you run most.'**
  String runHeatmapLegendSummaryMany(int n);

  /// Low end of the colour-scale legend on the personal heatmap
  ///
  /// In en, this message translates to:
  /// **'less'**
  String get runHeatmapScaleLess;

  /// High end of the colour-scale legend on the personal heatmap
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get runHeatmapScaleMore;

  /// AppBar title for the public route view before the route name loads
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get publicRouteFallbackTitle;

  /// Error state shown when the public route fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load this route.'**
  String get publicRouteLoadError;

  /// Empty state shown when the public route is private or deleted
  ///
  /// In en, this message translates to:
  /// **'This route is private or no longer available.'**
  String get publicRouteUnavailable;

  /// Stat label for distance on the public route view
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get publicRouteStatDistance;

  /// Stat label for elevation on the public route view
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get publicRouteStatElevation;

  /// Stat label for the waypoint count on the public route view
  ///
  /// In en, this message translates to:
  /// **'Waypoints'**
  String get publicRouteStatWaypoints;

  /// Full-page error state shown when the route library fails to load and there is nothing cached
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your routes. Check your connection and try again.'**
  String get routesLoadErrorRetry;

  /// AppBar title for the activity feed screen
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get feedTitle;

  /// Tooltip on the find-people button in the feed AppBar
  ///
  /// In en, this message translates to:
  /// **'Find people'**
  String get feedFindPeople;

  /// Feed activity filter chip — all activity types
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get feedActivityAll;

  /// Feed activity filter chip — running
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get feedActivityRun;

  /// Feed activity filter chip — walking
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get feedActivityWalk;

  /// Feed activity filter chip — cycling
  ///
  /// In en, this message translates to:
  /// **'Cycle'**
  String get feedActivityCycle;

  /// Feed activity filter chip — hiking
  ///
  /// In en, this message translates to:
  /// **'Hike'**
  String get feedActivityHike;

  /// Feed activity filter chip — gym lifts
  ///
  /// In en, this message translates to:
  /// **'Lift'**
  String get feedActivityLift;

  /// Stat label under the set count on a feed lift card
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get feedLiftSetsLabel;

  /// Stat label under the total volume on a feed lift card
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get feedLiftVolume;

  /// Fallback title for an untitled public gym workout in the feed
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get feedLiftUntitled;

  /// Button to load the next page of feed entries
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get feedLoadMore;

  /// Banner shown when loading more feed entries fails
  ///
  /// In en, this message translates to:
  /// **'Could not load more: {error}'**
  String feedLoadMoreFailed(String error);

  /// Error state shown when the feed fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load feed.'**
  String get feedLoadError;

  /// Default option in the feed author-filter dropdown
  ///
  /// In en, this message translates to:
  /// **'Everyone you follow'**
  String get feedEveryoneYouFollow;

  /// Fallback name shown in the feed when an author has no display name
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get feedRunnerFallback;

  /// Relative-time label for under a minute ago
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get relativeJustNow;

  /// Compact relative-time label, minutes
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String relativeMinutesAgo(int count);

  /// Compact relative-time label, hours
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String relativeHoursAgo(int count);

  /// Relative-time label for one day ago
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get relativeYesterday;

  /// Compact relative-time label, days
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String relativeDaysAgo(int count);

  /// Relative-time label, weeks
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 week ago} other{{count} weeks ago}}'**
  String relativeWeeksAgo(int count);

  /// Coach archive label for today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get coachArchiveToday;

  /// Coach archive label, days ago (full word)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} days ago}}'**
  String coachArchiveDaysAgo(int count);

  /// Label noting the feed only shows the last 14 days of activity
  ///
  /// In en, this message translates to:
  /// **'Last 14 days'**
  String get feedLast14Days;

  /// Empty-state title when the user follows nobody
  ///
  /// In en, this message translates to:
  /// **'Your feed is empty'**
  String get feedEmptyTitle;

  /// Empty-state body when the user follows nobody
  ///
  /// In en, this message translates to:
  /// **'Follow other runners to see their public runs here.'**
  String get feedEmptyBody;

  /// Empty-state title when filters exclude all feed entries
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get feedNoMatchesTitle;

  /// Empty-state body when filters exclude all feed entries
  ///
  /// In en, this message translates to:
  /// **'Nothing matches the current filters in the last 14 days.'**
  String get feedNoMatchesBody;

  /// Empty-state title when followed users have no recent runs
  ///
  /// In en, this message translates to:
  /// **'No recent activity'**
  String get feedNoActivityTitle;

  /// Empty-state body when followed users have no recent runs
  ///
  /// In en, this message translates to:
  /// **'Nobody you follow has logged a public run in the last 14 days.'**
  String get feedNoActivityBody;

  /// Button to clear feed filters in the empty state
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get feedClearFilters;

  /// Banner shown when toggling kudos fails
  ///
  /// In en, this message translates to:
  /// **'Could not update kudos: {error}'**
  String feedKudosUpdateFailed(String error);

  /// AppBar title fallback for the profile screen when the display name is unknown
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Fallback name used when a profile has no display name
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get profileRunnerFallback;

  /// Profile tab label for the user's public runs
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get profileTabRuns;

  /// Profile tab label for the followers list
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get profileTabFollowers;

  /// Profile tab label for the following list
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get profileTabFollowing;

  /// Profile tab label for the notifications list (own profile only)
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get profileTabNotifications;

  /// Tooltip on the report-user button in the profile AppBar
  ///
  /// In en, this message translates to:
  /// **'Report user'**
  String get profileReportUser;

  /// Tooltip on the block toggle when the profile is blocked
  ///
  /// In en, this message translates to:
  /// **'Unblock this profile'**
  String get profileUnblock;

  /// Tooltip on the block toggle when the profile is not blocked
  ///
  /// In en, this message translates to:
  /// **'Block this profile'**
  String get profileBlock;

  /// Error state shown when the profile fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load profile.'**
  String get profileLoadError;

  /// Shown when the profile does not exist
  ///
  /// In en, this message translates to:
  /// **'Profile not found.'**
  String get profileNotFound;

  /// Header line summarising follower and following counts
  ///
  /// In en, this message translates to:
  /// **'{followers, plural, one{{followers} follower} other{{followers} followers}} · {following} following'**
  String profileFollowStats(int followers, int following);

  /// Follow button label when the viewer already follows this user
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get profileFollowing;

  /// Follow button label when the viewer does not follow this user
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get profileFollow;

  /// Empty runs tab on the viewer's own profile
  ///
  /// In en, this message translates to:
  /// **'You haven\'t shared any runs yet.'**
  String get profileRunsEmptySelf;

  /// Empty runs tab on another user's profile
  ///
  /// In en, this message translates to:
  /// **'No public runs yet.'**
  String get profileRunsEmptyOther;

  /// Empty state for the followers tab
  ///
  /// In en, this message translates to:
  /// **'No followers yet.'**
  String get profileFollowersEmpty;

  /// Empty state for the following tab
  ///
  /// In en, this message translates to:
  /// **'Not following anyone yet.'**
  String get profileFollowingEmpty;

  /// Button to load the next page of followers/following
  ///
  /// In en, this message translates to:
  /// **'Load {count} more'**
  String profileLoadMore(int count);

  /// Banner when loading more followers fails
  ///
  /// In en, this message translates to:
  /// **'Could not load more followers'**
  String get profileLoadMoreFollowersFailed;

  /// Banner when loading more following fails
  ///
  /// In en, this message translates to:
  /// **'Could not load more following'**
  String get profileLoadMoreFollowingFailed;

  /// Banner when toggling follow fails
  ///
  /// In en, this message translates to:
  /// **'Could not update follow: {error}'**
  String profileFollowUpdateFailed(String error);

  /// Title of the block-confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Block {name}?'**
  String profileBlockConfirmTitle(String name);

  /// Body of the block-confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'They won\'t be able to follow you, give kudos to your runs, or comment on them. Any existing follow between you in either direction will be cleared. You can unblock from this page at any time.'**
  String get profileBlockConfirmBody;

  /// Confirm action on the block-confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get profileBlockConfirmAction;

  /// Cancel action on profile dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get profileCancel;

  /// Fallback name used in block dialogs when the display name is unknown
  ///
  /// In en, this message translates to:
  /// **'this runner'**
  String get profileThisRunner;

  /// Lowercase fallback noun used in block/unblock confirmation banners
  ///
  /// In en, this message translates to:
  /// **'runner'**
  String get profileRunnerNoun;

  /// Banner shown after blocking a user
  ///
  /// In en, this message translates to:
  /// **'Blocked {name}'**
  String profileBlocked(String name);

  /// Banner shown when blocking fails
  ///
  /// In en, this message translates to:
  /// **'Could not block: {error}'**
  String profileBlockFailed(String error);

  /// Banner shown after unblocking a user
  ///
  /// In en, this message translates to:
  /// **'Unblocked {name}'**
  String profileUnblocked(String name);

  /// Banner shown when unblocking fails
  ///
  /// In en, this message translates to:
  /// **'Could not unblock: {error}'**
  String profileUnblockFailed(String error);

  /// Notifications filter segment — all notifications
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get profileNotifAll;

  /// Notifications filter segment — unread only
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get profileNotifUnread;

  /// Button to mark all notifications as read
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get profileMarkAllRead;

  /// Banner when mark-all-read fails
  ///
  /// In en, this message translates to:
  /// **'Failed to mark all read: {error}'**
  String profileMarkAllReadFailed(String error);

  /// Empty state for the unread notifications filter
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up.'**
  String get profileNotifsCaughtUp;

  /// Empty state for the all notifications filter
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get profileNotifsEmpty;

  /// Tooltip on the dismiss-notification button
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get profileDismiss;

  /// Banner when dismissing a notification fails
  ///
  /// In en, this message translates to:
  /// **'Failed to dismiss: {error}'**
  String profileDismissFailed(String error);

  /// Fallback actor name in notification text
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get profileNotifSomeone;

  /// Fallback for a run reference in notification text when distance is unknown
  ///
  /// In en, this message translates to:
  /// **'your run'**
  String get profileNotifYourRun;

  /// Notification text for a kudos
  ///
  /// In en, this message translates to:
  /// **'{name} gave kudos to your {dist}'**
  String profileNotifKudos(String name, String dist);

  /// Notification text for a comment
  ///
  /// In en, this message translates to:
  /// **'{name} commented on your {dist}'**
  String profileNotifComment(String name, String dist);

  /// Notification text for a comment reply
  ///
  /// In en, this message translates to:
  /// **'{name} replied to your comment'**
  String profileNotifCommentReply(String name);

  /// Notification text for a new follower
  ///
  /// In en, this message translates to:
  /// **'{name} started following you'**
  String profileNotifFollow(String name);

  /// Notification text for an event RSVP with a title
  ///
  /// In en, this message translates to:
  /// **'{name} RSVP\'d Going to your event \"{title}\"'**
  String profileNotifEventRsvpTitled(String name, String title);

  /// Notification text for an event RSVP without a title
  ///
  /// In en, this message translates to:
  /// **'{name} RSVP\'d Going to your event'**
  String profileNotifEventRsvp(String name);

  /// Notification text for a training-plan update
  ///
  /// In en, this message translates to:
  /// **'{name} updated your training plan'**
  String profileNotifPlanUpdate(String name);

  /// Notification text for a direct message
  ///
  /// In en, this message translates to:
  /// **'{name} sent you a message'**
  String profileNotifMessage(String name);

  /// Notification text for a club post with a known club name
  ///
  /// In en, this message translates to:
  /// **'{name} posted in {club}'**
  String profileNotifClubPostNamed(String name, String club);

  /// Notification text for a club post with unknown club name
  ///
  /// In en, this message translates to:
  /// **'{name} posted in a club you\'re in'**
  String profileNotifClubPost(String name);

  /// Notification text for a completed run with distance
  ///
  /// In en, this message translates to:
  /// **'{name} completed a {dist} run'**
  String profileNotifRunCompletedDist(String name, String dist);

  /// Notification text for a completed run without distance
  ///
  /// In en, this message translates to:
  /// **'{name} completed a run'**
  String profileNotifRunCompleted(String name);

  /// Fallback notification text for unknown kinds
  ///
  /// In en, this message translates to:
  /// **'{name} interacted with your activity'**
  String profileNotifGeneric(String name);

  /// Social hub sub-tab label — activity feed
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get socialTabFeed;

  /// Social hub sub-tab label — people search
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get socialTabPeople;

  /// Social hub sub-tab label — clubs
  ///
  /// In en, this message translates to:
  /// **'Clubs'**
  String get socialTabClubs;

  /// Social hub sub-tab label — routes
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get socialTabRoutes;

  /// Social hub sub-tab label — cross-club activity discovery
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get socialTabDiscover;

  /// Discover tab search field placeholder
  ///
  /// In en, this message translates to:
  /// **'Search yoga, pilates, HIIT, run clubs…'**
  String get discoverSearchPlaceholder;

  /// Discover tab — category filter chip that clears the category filter
  ///
  /// In en, this message translates to:
  /// **'All activities'**
  String get discoverActivityAll;

  /// Discover tab — label for the recurrence/cadence filter
  ///
  /// In en, this message translates to:
  /// **'Cadence'**
  String get discoverCadenceLabel;

  /// Discover tab — cadence filter option that matches any cadence
  ///
  /// In en, this message translates to:
  /// **'Any cadence'**
  String get discoverCadenceAny;

  /// Discover tab — a non-recurring (single) event
  ///
  /// In en, this message translates to:
  /// **'One-off'**
  String get discoverOneOff;

  /// Discover tab — a weekly recurring event
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get discoverWeekly;

  /// Discover tab — a fortnightly recurring event
  ///
  /// In en, this message translates to:
  /// **'Every 2 weeks'**
  String get discoverBiweekly;

  /// Discover tab — a monthly recurring event
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get discoverMonthly;

  /// Discover tab — label for the weekday filter
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get discoverDayLabel;

  /// Discover tab — weekday filter option that matches any day
  ///
  /// In en, this message translates to:
  /// **'Any day'**
  String get discoverDayAny;

  /// Discover tab — abbreviated Monday weekday label
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get discoverDayMon;

  /// Discover tab — abbreviated Tuesday weekday label
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get discoverDayTue;

  /// Discover tab — abbreviated Wednesday weekday label
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get discoverDayWed;

  /// Discover tab — abbreviated Thursday weekday label
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get discoverDayThu;

  /// Discover tab — abbreviated Friday weekday label
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get discoverDayFri;

  /// Discover tab — abbreviated Saturday weekday label
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get discoverDaySat;

  /// Discover tab — abbreviated Sunday weekday label
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get discoverDaySun;

  /// Discover tab — label for the time-of-day filter
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get discoverTimeLabel;

  /// Discover tab — time-of-day filter option that matches any time
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get discoverTimeAny;

  /// Discover tab — morning time-of-day bucket (05:00–11:59 local)
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get discoverMorning;

  /// Discover tab — afternoon time-of-day bucket (12:00–16:59 local)
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get discoverAfternoon;

  /// Discover tab — evening time-of-day bucket (17:00–04:59 local)
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get discoverEvening;

  /// Discover tab — label for the price (free/paid) filter
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get discoverPriceLabel;

  /// Discover tab — price filter option that matches free or paid
  ///
  /// In en, this message translates to:
  /// **'Any price'**
  String get discoverPriceAny;

  /// Discover tab — a free (no-cost) event
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get discoverFree;

  /// Discover tab — a paid (ticketed) event
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get discoverPaid;

  /// Discover tab — loading state while results are fetched
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get discoverLoading;

  /// Discover tab — empty state when no events match the filters
  ///
  /// In en, this message translates to:
  /// **'No public activities match these filters yet.'**
  String get discoverEmpty;

  /// Discover tab — error state shown when the activity search fails (distinct from the empty state)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load activities. Check your connection and try again.'**
  String get discoverSearchFailed;

  /// AppBar title for the standalone clubs screen
  ///
  /// In en, this message translates to:
  /// **'Clubs'**
  String get clubsTitle;

  /// Tooltip on the find-people button in the clubs AppBar
  ///
  /// In en, this message translates to:
  /// **'Find people'**
  String get clubsFindPeople;

  /// Label on the create-club FAB
  ///
  /// In en, this message translates to:
  /// **'New club'**
  String get clubsNewClub;

  /// Clubs segment — browse public clubs
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get clubsTabBrowse;

  /// Clubs segment — the user's own clubs
  ///
  /// In en, this message translates to:
  /// **'My clubs'**
  String get clubsTabMine;

  /// Button to redeem a club invite code
  ///
  /// In en, this message translates to:
  /// **'Join with invite code'**
  String get clubsJoinWithCode;

  /// Placeholder in the club search field
  ///
  /// In en, this message translates to:
  /// **'Search by name or location'**
  String get clubsSearchHint;

  /// Error shown when loading clubs times out
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network and try again.'**
  String get clubsTimeoutError;

  /// Error shown when loading clubs fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load clubs. Tap retry to try again.'**
  String get clubsLoadError;

  /// Badge on a private club tile
  ///
  /// In en, this message translates to:
  /// **'PRIVATE'**
  String get clubsBadgePrivate;

  /// Member count on a club tile
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} member} other{{count} members}}'**
  String clubsMemberCount(int count);

  /// Empty state for the browse tab
  ///
  /// In en, this message translates to:
  /// **'No clubs match that search.'**
  String get clubsEmptyBrowseTitle;

  /// Empty state for the my-clubs tab
  ///
  /// In en, this message translates to:
  /// **'You haven\'t joined a club yet.'**
  String get clubsEmptyMineTitle;

  /// Empty-state hint for the browse tab
  ///
  /// In en, this message translates to:
  /// **'Try a different name or location.'**
  String get clubsEmptyBrowseBody;

  /// Empty-state hint for the my-clubs tab
  ///
  /// In en, this message translates to:
  /// **'Head to Browse to find one.'**
  String get clubsEmptyMineBody;

  /// Club detail tab — feed
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get clubDetailTabFeed;

  /// Club detail tab — events
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get clubDetailTabEvents;

  /// Club detail tab — members
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get clubDetailTabMembers;

  /// Club detail tab — routes
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get clubDetailTabRoutes;

  /// Club detail tab — plan templates
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get clubDetailTabTemplates;

  /// Club detail tab — photo gallery
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get clubDetailTabPhotos;

  /// Tooltip on the report-club button
  ///
  /// In en, this message translates to:
  /// **'Report club'**
  String get clubDetailReportClub;

  /// Tooltip on the report-post button on a club feed post
  ///
  /// In en, this message translates to:
  /// **'Report this post'**
  String get clubDetailReportPost;

  /// Title shown when the club fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this club.'**
  String get clubDetailLoadFailedTitle;

  /// Body shown when the club fails to load
  ///
  /// In en, this message translates to:
  /// **'It may have been removed, or your session might need to be refreshed. Try pulling to retry, or sign out and back in from Settings.'**
  String get clubDetailLoadFailedBody;

  /// Retry button on the club load-error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get clubDetailRetry;

  /// Error shown when loading the club times out
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network and try again.'**
  String get clubDetailTimeoutError;

  /// Banner shown after requesting to join a club
  ///
  /// In en, this message translates to:
  /// **'Request sent to admins.'**
  String get clubDetailRequestSent;

  /// Title of the leave-club confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Leave {club}?'**
  String clubDetailLeaveTitle(String club);

  /// Cancel action on club dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get clubDetailCancel;

  /// Confirm action on the leave-club dialog / CTA when a member
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get clubDetailLeave;

  /// Banner when posting a reply fails
  ///
  /// In en, this message translates to:
  /// **'Could not post reply: {error}'**
  String clubDetailReplyFailed(String error);

  /// Fallback name for a club member with no display name
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get clubDetailMemberFallback;

  /// CTA label when the viewer's join request is pending
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get clubDetailRequestPending;

  /// CTA label when the club is invite-only and the viewer is not a member
  ///
  /// In en, this message translates to:
  /// **'Invite only'**
  String get clubDetailInviteOnly;

  /// CTA label to request to join a request-policy club
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get clubDetailRequest;

  /// CTA label to join an open club
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get clubDetailJoin;

  /// CTA label shown to the club owner
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get clubDetailOwner;

  /// Section label on the next-event card
  ///
  /// In en, this message translates to:
  /// **'NEXT EVENT'**
  String get clubDetailNextEvent;

  /// Attendee count line on event cards
  ///
  /// In en, this message translates to:
  /// **'{count} going'**
  String clubDetailGoingCount(int count);

  /// Empty feed for members
  ///
  /// In en, this message translates to:
  /// **'No posts yet. Share an update with members.'**
  String get clubDetailNoPostsMember;

  /// Empty feed for non-members
  ///
  /// In en, this message translates to:
  /// **'No updates yet.'**
  String get clubDetailNoPosts;

  /// Hint in the club post composer
  ///
  /// In en, this message translates to:
  /// **'Share an update…'**
  String get clubDetailShareUpdateHint;

  /// Submit button in the club post composer
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get clubDetailPost;

  /// Button to reply to a post when there are no replies
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get clubDetailReply;

  /// Toggle to hide an expanded reply thread
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Hide {count} reply} other{Hide {count} replies}}'**
  String clubDetailHideReplies(int count);

  /// Toggle to show a reply thread
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} reply} other{{count} replies}}'**
  String clubDetailShowReplies(int count);

  /// Author and relative-time line on a reply
  ///
  /// In en, this message translates to:
  /// **'{name} · {time}'**
  String clubDetailReplyAuthorLine(String name, String time);

  /// Hint in the reply composer
  ///
  /// In en, this message translates to:
  /// **'Write a reply…'**
  String get clubDetailWriteReplyHint;

  /// Send button in the reply composer
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get clubDetailSend;

  /// Empty events tab for admins
  ///
  /// In en, this message translates to:
  /// **'No upcoming events. Tap Create to add one.'**
  String get clubDetailNoEventsAdmin;

  /// Empty events tab for non-admins
  ///
  /// In en, this message translates to:
  /// **'No upcoming events.'**
  String get clubDetailNoEvents;

  /// Button to create a club event
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get clubDetailCreateEvent;

  /// RSVP badge on an event card
  ///
  /// In en, this message translates to:
  /// **'Going'**
  String get clubDetailGoing;

  /// Banner when approving a join request fails
  ///
  /// In en, this message translates to:
  /// **'Approve failed: {error}'**
  String clubDetailApproveFailed(String error);

  /// Banner when denying a join request fails
  ///
  /// In en, this message translates to:
  /// **'Deny failed: {error}'**
  String clubDetailDenyFailed(String error);

  /// Header for the pending-requests panel
  ///
  /// In en, this message translates to:
  /// **'Pending requests ({count})'**
  String clubDetailPendingRequests(int count);

  /// Placeholder name for a pending member shown by id prefix
  ///
  /// In en, this message translates to:
  /// **'User {id}…'**
  String clubDetailUserShort(String id);

  /// Button to deny a join request
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get clubDetailDeny;

  /// Title of the deny-join-request confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Reject join request'**
  String get clubDetailDenyTitle;

  /// Body of the deny-join-request confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Reject this request to join the club? They will not be added.'**
  String get clubDetailDenyMessage;

  /// Button to approve a join request
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get clubDetailApprove;

  /// Member count summary on the members tab
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} member.} other{{count} members.}}'**
  String clubDetailMemberCountLine(int count);

  /// Banner shown after saving a club route
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\"'**
  String clubDetailRouteSaved(String name);

  /// CTA to build a route for the club
  ///
  /// In en, this message translates to:
  /// **'Build route for this club'**
  String get clubDetailBuildRoute;

  /// Empty routes tab when the viewer can build
  ///
  /// In en, this message translates to:
  /// **'No routes yet. Build the official course above, or transfer one of your personal routes from the route detail screen.'**
  String get clubDetailRoutesEmptyBuild;

  /// Empty routes tab for admins who cannot build
  ///
  /// In en, this message translates to:
  /// **'No routes yet. Admins can transfer one of their personal routes from the route detail screen.'**
  String get clubDetailRoutesEmptyAdmin;

  /// Empty routes tab for members
  ///
  /// In en, this message translates to:
  /// **'No routes shared with this club yet.'**
  String get clubDetailRoutesEmpty;

  /// Banner shown after adopting a plan template
  ///
  /// In en, this message translates to:
  /// **'Template added to your plans.'**
  String get clubDetailTemplateAdded;

  /// Banner when adopting a template fails
  ///
  /// In en, this message translates to:
  /// **'Adopt failed: {error}'**
  String clubDetailAdoptFailed(String error);

  /// Empty templates tab for admins
  ///
  /// In en, this message translates to:
  /// **'No templates yet. Publish one of your plans from its detail page.'**
  String get clubDetailNoTemplatesAdmin;

  /// Empty templates tab for members
  ///
  /// In en, this message translates to:
  /// **'No plan templates yet for this club.'**
  String get clubDetailNoTemplates;

  /// Button to adopt a plan template
  ///
  /// In en, this message translates to:
  /// **'Adopt'**
  String get clubDetailAdopt;

  /// Heading above the club's adoptable yoga/pilates session-plan templates
  ///
  /// In en, this message translates to:
  /// **'Session templates'**
  String get clubDetailSessionTemplatesTitle;

  /// Confirmation after cloning a club session template into a personal plan
  ///
  /// In en, this message translates to:
  /// **'Session added to your plans.'**
  String get clubDetailSessionAdopted;

  /// Heading above the club's adoptable gym-routine templates
  ///
  /// In en, this message translates to:
  /// **'Gym routine templates'**
  String get clubDetailGymRoutineTemplatesTitle;

  /// Hint under the club gym-routine-templates heading
  ///
  /// In en, this message translates to:
  /// **'Members can adopt a club gym routine into their own routines. Edits to a copy don\'t propagate back to the template.'**
  String get clubDetailGymRoutineTemplatesHint;

  /// Confirmation after cloning a club gym-routine template into a personal routine
  ///
  /// In en, this message translates to:
  /// **'Routine added to your gym routines.'**
  String get clubDetailGymRoutineAdopted;

  /// Exercise count meta on a club gym-routine-template row
  ///
  /// In en, this message translates to:
  /// **'{n} exercises'**
  String clubDetailRoutineExerciseCount(int n);

  /// Shown when the event does not exist
  ///
  /// In en, this message translates to:
  /// **'Event not found.'**
  String get eventNotFound;

  /// Error shown when loading the event fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this event. Tap retry to try again.'**
  String get eventLoadError;

  /// Error shown when loading the event times out
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network and try again.'**
  String get eventTimeoutError;

  /// Duration suffix next to the event date
  ///
  /// In en, this message translates to:
  /// **'· {minutes} min'**
  String eventDurationMin(int minutes);

  /// Button to navigate to the named meet point
  ///
  /// In en, this message translates to:
  /// **'Get directions to {label}'**
  String eventGetDirectionsTo(String label);

  /// Button to navigate to the meet point (no label)
  ///
  /// In en, this message translates to:
  /// **'Get directions'**
  String get eventGetDirections;

  /// Banner when launching a maps app fails
  ///
  /// In en, this message translates to:
  /// **'Could not open maps.'**
  String get eventCouldNotOpenMaps;

  /// Header above the occurrence picker for recurring events
  ///
  /// In en, this message translates to:
  /// **'PICK AN OCCURRENCE'**
  String get eventPickOccurrence;

  /// Stat label for the event target pace
  ///
  /// In en, this message translates to:
  /// **'Target pace'**
  String get eventTargetPace;

  /// Eyebrow label above the discipline name on a class (e.g. yoga) event
  ///
  /// In en, this message translates to:
  /// **'CLASS'**
  String get eventClassSessionEyebrow;

  /// Banner shown after submitting an event result
  ///
  /// In en, this message translates to:
  /// **'Result submitted.'**
  String get eventResultSubmitted;

  /// Banner when submitting an event result fails
  ///
  /// In en, this message translates to:
  /// **'Submit failed: {error}'**
  String eventSubmitFailed(String error);

  /// Banner when a race-control mutation fails
  ///
  /// In en, this message translates to:
  /// **'Race control failed: {error}'**
  String eventRaceControlFailed(String error);

  /// Header for the attendees section
  ///
  /// In en, this message translates to:
  /// **'ATTENDEES ({count})'**
  String eventAttendees(int count);

  /// Header for the event photo gallery
  ///
  /// In en, this message translates to:
  /// **'Photos ({count})'**
  String eventPhotosTitle(int count);

  /// Add-photo action on the event gallery
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get eventAddPhoto;

  /// Label while an event photo uploads
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get eventPhotoUploading;

  /// Empty event-gallery state
  ///
  /// In en, this message translates to:
  /// **'No photos yet.'**
  String get eventNoPhotosYet;

  /// Prompt to add the first event photo
  ///
  /// In en, this message translates to:
  /// **'Be the first to add one.'**
  String get eventNoPhotosAddHint;

  /// Title of the recent-run picker for an event photo
  ///
  /// In en, this message translates to:
  /// **'Which run is this photo from?'**
  String get eventWhichRunPhoto;

  /// Empty state in the submit-time sheet
  ///
  /// In en, this message translates to:
  /// **'No recent runs found. Record a run first, then come back.'**
  String get eventNoRecentRuns;

  /// Fallback uploader name on an event photo
  ///
  /// In en, this message translates to:
  /// **'A runner'**
  String get eventPhotoRunnerFallback;

  /// Error when an event photo upload fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the photo.'**
  String get eventPhotoUploadFailed;

  /// Empty attendees state
  ///
  /// In en, this message translates to:
  /// **'No RSVPs yet — be the first.'**
  String get eventNoRsvps;

  /// Fallback attendee name with no display name
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get eventAttendeeMember;

  /// Suffix showing a non-going attendee's RSVP status
  ///
  /// In en, this message translates to:
  /// **'({status})'**
  String eventAttendeeStatus(String status);

  /// Host control — mark an attendee as having shown up
  ///
  /// In en, this message translates to:
  /// **'Mark attended'**
  String get eventMarkAttended;

  /// Host control — mark an attendee as a no-show
  ///
  /// In en, this message translates to:
  /// **'Mark no-show'**
  String get eventMarkNoShow;

  /// Read-only attendance badge — attended
  ///
  /// In en, this message translates to:
  /// **'Attended'**
  String get eventAttendanceAttended;

  /// Read-only attendance badge — did not attend
  ///
  /// In en, this message translates to:
  /// **'No-show'**
  String get eventAttendanceNoShow;

  /// Error banner when marking attendance fails
  ///
  /// In en, this message translates to:
  /// **'Could not update attendance. Please try again.'**
  String get eventAttendanceFailed;

  /// Error banner when an RSVP write fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your RSVP. Please try again.'**
  String get eventRsvpFailed;

  /// RSVP chip — going
  ///
  /// In en, this message translates to:
  /// **'I\'m in'**
  String get eventRsvpGoing;

  /// RSVP chip — maybe
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get eventRsvpMaybe;

  /// RSVP chip — declined
  ///
  /// In en, this message translates to:
  /// **'Can\'t make it'**
  String get eventRsvpDeclined;

  /// Race control banner — armed
  ///
  /// In en, this message translates to:
  /// **'Armed — waiting for GO'**
  String get eventRaceArmed;

  /// Race control banner — running
  ///
  /// In en, this message translates to:
  /// **'Running — live'**
  String get eventRaceRunning;

  /// Race control banner — finished
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get eventRaceFinished;

  /// Race control banner — cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get eventRaceCancelled;

  /// Race control banner — idle
  ///
  /// In en, this message translates to:
  /// **'Not armed'**
  String get eventRaceNotArmed;

  /// Section label on the race-control card
  ///
  /// In en, this message translates to:
  /// **'RACE CONTROL'**
  String get eventRaceControlLabel;

  /// Checkbox to auto-approve submitted times when arming
  ///
  /// In en, this message translates to:
  /// **'Auto-approve submitted times'**
  String get eventRaceAutoApprove;

  /// Button to arm the race
  ///
  /// In en, this message translates to:
  /// **'Arm race'**
  String get eventRaceArm;

  /// Hint shown when the race is armed
  ///
  /// In en, this message translates to:
  /// **'Tap Fire Go when the race begins. Participants\' watches show the armed banner now.'**
  String get eventRaceArmedHint;

  /// Button to start the race
  ///
  /// In en, this message translates to:
  /// **'Fire Go'**
  String get eventRaceFireGo;

  /// Button to cancel the race while armed
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get eventRaceCancel;

  /// Line showing when a running race started
  ///
  /// In en, this message translates to:
  /// **'Started at {time}'**
  String eventRaceStartedAt(String time);

  /// Button to end a running race
  ///
  /// In en, this message translates to:
  /// **'End race'**
  String get eventRaceEnd;

  /// Button to cancel a running race
  ///
  /// In en, this message translates to:
  /// **'Cancel race'**
  String get eventRaceCancelRace;

  /// No description provided for @eventRaceEndConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'End the race? This finalizes the event for every runner and can\'t be undone.'**
  String get eventRaceEndConfirmBody;

  /// No description provided for @eventRaceCancelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Cancel the race? This aborts the event for every runner and can\'t be undone.'**
  String get eventRaceCancelConfirmBody;

  /// Banner shown after posting an admin update
  ///
  /// In en, this message translates to:
  /// **'Update posted to the club feed.'**
  String get eventUpdatePosted;

  /// Banner when posting an admin update fails
  ///
  /// In en, this message translates to:
  /// **'Could not post update: {error}'**
  String eventPostUpdateFailed(String error);

  /// Section label on the admin update composer
  ///
  /// In en, this message translates to:
  /// **'POST AN UPDATE'**
  String get eventPostUpdateLabel;

  /// Hint in the admin update composer
  ///
  /// In en, this message translates to:
  /// **'Weather call? Meeting at a different spot?'**
  String get eventUpdateHint;

  /// Submit button on the admin update composer
  ///
  /// In en, this message translates to:
  /// **'Post update'**
  String get eventPostUpdate;

  /// Title of the event results section
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get eventResultsTitle;

  /// Button to remove the viewer's own result
  ///
  /// In en, this message translates to:
  /// **'Remove mine'**
  String get eventRemoveMine;

  /// Confirm dialog title for removing the viewer's own event result
  ///
  /// In en, this message translates to:
  /// **'Remove your result?'**
  String get eventRemoveResultTitle;

  /// Confirm dialog body for removing the viewer's own event result
  ///
  /// In en, this message translates to:
  /// **'Your submitted finish time will be removed from this event\'s leaderboard. You can submit again later.'**
  String get eventRemoveResultBody;

  /// Confirm button to remove the viewer's own event result
  ///
  /// In en, this message translates to:
  /// **'Remove result'**
  String get eventRemoveResultConfirm;

  /// Banner shown when removing the viewer's own event result fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove your result: {error}'**
  String eventRemoveResultFailed(String error);

  /// Button to submit the viewer's result
  ///
  /// In en, this message translates to:
  /// **'Submit my time'**
  String get eventSubmitMyTime;

  /// Button label while submitting a result
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get eventSubmitting;

  /// Empty results state
  ///
  /// In en, this message translates to:
  /// **'No results yet. Submit your time after the event and others will see it here.'**
  String get eventNoResults;

  /// Fallback name in a result row
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get eventResultRunner;

  /// Marker on the viewer's own result row
  ///
  /// In en, this message translates to:
  /// **'(you)'**
  String get eventResultYou;

  /// Title of the submit-time bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Submit your time'**
  String get eventSubmitTimeTitle;

  /// Subtitle of the submit-time sheet
  ///
  /// In en, this message translates to:
  /// **'Pick a run to attach, or record a DNF / DNS.'**
  String get eventSubmitTimeSubtitle;

  /// Button to record a DNF result
  ///
  /// In en, this message translates to:
  /// **'Record DNF'**
  String get eventRecordDnf;

  /// Button to record a DNS result
  ///
  /// In en, this message translates to:
  /// **'Record DNS'**
  String get eventRecordDns;

  /// Cancel button in the submit-time sheet
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get eventSubmitCancel;

  /// AppBar title for the live spectator screen
  ///
  /// In en, this message translates to:
  /// **'Live tracking'**
  String get liveSpectatorTitle;

  /// Error state when the live feed fails to connect
  ///
  /// In en, this message translates to:
  /// **'Could not connect.'**
  String get liveSpectatorConnectError;

  /// Empty state before any ping arrives
  ///
  /// In en, this message translates to:
  /// **'Waiting for the runner to send the first ping…'**
  String get liveSpectatorWaiting;

  /// Status badge — live
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get liveSpectatorBadgeLive;

  /// Status badge — idle
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get liveSpectatorBadgeIdle;

  /// Status badge — connecting
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get liveSpectatorBadgeConnecting;

  /// Status badge — last ping is stale, position may not be current
  ///
  /// In en, this message translates to:
  /// **'Delayed'**
  String get liveSpectatorBadgeStale;

  /// Status badge — last position is a coarse privacy-zone last-seen fix, not a precise location
  ///
  /// In en, this message translates to:
  /// **'Approximate'**
  String get liveSpectatorBadgeApproximate;

  /// Sub-line shown when the latest position is a coarse privacy-zone last-seen fix
  ///
  /// In en, this message translates to:
  /// **'Last seen near here — approximate'**
  String get liveSpectatorApproximateSub;

  /// Status badge — the run has finished (terminal state, distinct from a stale signal)
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get liveSpectatorBadgeFinished;

  /// Status badge — the participant is race-marked Did Not Finish (terminal state)
  ///
  /// In en, this message translates to:
  /// **'DNF'**
  String get liveSpectatorBadgeDnf;

  /// Spectator freshness — last ping under 10s ago
  ///
  /// In en, this message translates to:
  /// **'Updated just now'**
  String get liveUpdatedNow;

  /// Spectator freshness — seconds since last ping
  ///
  /// In en, this message translates to:
  /// **'Updated {n}s ago'**
  String liveUpdatedSeconds(int n);

  /// Spectator freshness — minutes since last ping
  ///
  /// In en, this message translates to:
  /// **'Updated {n} min ago'**
  String liveUpdatedMinutes(int n);

  /// Spectator freshness — hours since last ping
  ///
  /// In en, this message translates to:
  /// **'Updated {n}h ago'**
  String liveUpdatedHours(int n);

  /// Spectator freshness — days since last ping
  ///
  /// In en, this message translates to:
  /// **'Updated {n}d ago'**
  String liveUpdatedDays(int n);

  /// Spectator next-cutoff card title / fallback checkpoint name
  ///
  /// In en, this message translates to:
  /// **'Next cut-off'**
  String get liveCutoffTitle;

  /// Spectator next-cutoff card — distance remaining to the cutoff
  ///
  /// In en, this message translates to:
  /// **'{distance} to go'**
  String liveCutoffToGo(String distance);

  /// Spectator next-cutoff card — projected arrival as elapsed time
  ///
  /// In en, this message translates to:
  /// **'Projected arrival {eta}'**
  String liveCutoffEta(String eta);

  /// Spectator next-cutoff chip — projected to make the cutoff with margin to spare
  ///
  /// In en, this message translates to:
  /// **'{margin} to spare'**
  String liveCutoffAhead(String margin);

  /// Spectator next-cutoff chip — projected to miss the cutoff by margin
  ///
  /// In en, this message translates to:
  /// **'{margin} behind'**
  String liveCutoffBehind(String margin);

  /// Spectator next-cutoff card — shown instead of a verdict when the position is stale
  ///
  /// In en, this message translates to:
  /// **'Waiting for a fresh signal to project arrival'**
  String get liveCutoffWaitingSignal;

  /// Plans list AppBar title
  ///
  /// In en, this message translates to:
  /// **'Training plans'**
  String get plansTitle;

  /// FAB label to create a new plan
  ///
  /// In en, this message translates to:
  /// **'New plan'**
  String get plansNewPlan;

  /// Confirm-delete dialog title for a plan
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String plansDeleteTitle(String name);

  /// Confirm-delete dialog body for a plan
  ///
  /// In en, this message translates to:
  /// **'All weeks and workouts will be removed.'**
  String get plansDeleteBody;

  /// Cancel button in the delete-plan dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get plansCancel;

  /// Delete button in the delete-plan dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get plansDelete;

  /// Abandon button on an active plan tile
  ///
  /// In en, this message translates to:
  /// **'Abandon'**
  String get plansAbandon;

  /// Confirm-abandon dialog title for an active plan
  ///
  /// In en, this message translates to:
  /// **'Abandon \"{name}\"?'**
  String plansAbandonTitle(String name);

  /// Confirm-abandon dialog body for an active plan
  ///
  /// In en, this message translates to:
  /// **'You can create a new plan after.'**
  String get plansAbandonBody;

  /// Banner shown when abandoning or deleting a plan fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the plan: {error}'**
  String plansActionFailed(String error);

  /// Days-per-week meta chip on a plan tile
  ///
  /// In en, this message translates to:
  /// **'{count} days/wk'**
  String plansDaysPerWeek(int count);

  /// Sign-in prompt title on plans list
  ///
  /// In en, this message translates to:
  /// **'Sign in to use training plans'**
  String get plansSignInTitle;

  /// Sign-in prompt body on plans list
  ///
  /// In en, this message translates to:
  /// **'Plans sync to your account so they follow you across devices. Head to Settings → Sign in to connect.'**
  String get plansSignInBody;

  /// Empty-state title on plans list
  ///
  /// In en, this message translates to:
  /// **'No plans yet.'**
  String get plansEmptyTitle;

  /// Empty-state body on plans list
  ///
  /// In en, this message translates to:
  /// **'Pick a goal race and we\'ll schedule the weeks for you.'**
  String get plansEmptyBody;

  /// Plans list load timeout error
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network and try again.'**
  String get plansTimeoutError;

  /// Plans list generic load error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load training plans. Tap retry to try again.'**
  String get plansLoadError;

  /// New-plan wizard AppBar title
  ///
  /// In en, this message translates to:
  /// **'New plan'**
  String get planNewTitle;

  /// Plan-name field label
  ///
  /// In en, this message translates to:
  /// **'Plan name'**
  String get planNewNameLabel;

  /// Plan-name field hint
  ///
  /// In en, this message translates to:
  /// **'e.g. Autumn half marathon'**
  String get planNewNameHint;

  /// Goal-race dropdown label
  ///
  /// In en, this message translates to:
  /// **'Goal race'**
  String get planNewGoalRace;

  /// Start-date tile title
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get planNewStartDate;

  /// Days-per-week dropdown label
  ///
  /// In en, this message translates to:
  /// **'Days per week'**
  String get planNewDaysPerWeek;

  /// Days-per-week dropdown option
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String planNewDaysOption(int count);

  /// Goal-time section label
  ///
  /// In en, this message translates to:
  /// **'Goal time · optional'**
  String get planNewGoalTimeSection;

  /// Beginner walk-run checkbox title
  ///
  /// In en, this message translates to:
  /// **'New to running? Use a walk-run plan'**
  String get planNewBeginnerTitle;

  /// Beginner walk-run checkbox subtitle
  ///
  /// In en, this message translates to:
  /// **'A gentle C25K-style schedule of timed run/walk intervals that builds to a continuous run. Overrides goal-time pacing.'**
  String get planNewBeginnerSubtitle;

  /// Recent-5K section label
  ///
  /// In en, this message translates to:
  /// **'Recent 5K time · optional'**
  String get planNewRecent5kSection;

  /// Recent-5K help text
  ///
  /// In en, this message translates to:
  /// **'Anchor paces on a real result instead of the goal. Uses Riegel equivalence to project to the goal distance.'**
  String get planNewRecent5kHelp;

  /// Recent-5K current-fitness confirmation checkbox
  ///
  /// In en, this message translates to:
  /// **'This is a time I could run today — it reflects my current fitness.'**
  String get planNewRecent5kConfirm;

  /// Recent-5K unconfirmed warning
  ///
  /// In en, this message translates to:
  /// **'Until you confirm, paces stay on the conservative goal-based estimate. Anchoring on an old result can prescribe paces that are too fast for a returning runner.'**
  String get planNewRecent5kWarning;

  /// Override-weeks field hint
  ///
  /// In en, this message translates to:
  /// **'Override total weeks'**
  String get planNewOverrideHint;

  /// Override-weeks field label with default count
  ///
  /// In en, this message translates to:
  /// **'Override weeks ({count} default)'**
  String planNewOverrideLabel(int count);

  /// Cancel button in the new-plan wizard
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get planNewCancel;

  /// Create-plan button label
  ///
  /// In en, this message translates to:
  /// **'Create plan'**
  String get planNewCreate;

  /// Create-plan button label while busy
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get planNewCreating;

  /// Preview section title
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get planNewPreviewTitle;

  /// Easy-pace pill label
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get planNewPaceEasy;

  /// Marathon-pace pill label
  ///
  /// In en, this message translates to:
  /// **'Marathon'**
  String get planNewPaceMarathon;

  /// Tempo-pace pill label
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get planNewPaceTempo;

  /// Interval-pace pill label
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get planNewPaceInterval;

  /// Repetition-pace pill label
  ///
  /// In en, this message translates to:
  /// **'Rep'**
  String get planNewPaceRep;

  /// Fallback-paces preview note
  ///
  /// In en, this message translates to:
  /// **'Estimated paces — add a recent run or a goal time for personalised targets.'**
  String get planNewPacesFallback;

  /// VDOT preview line
  ///
  /// In en, this message translates to:
  /// **'Daniels VDOT: {value}'**
  String planNewVdot(String value);

  /// Week-outline preview section label
  ///
  /// In en, this message translates to:
  /// **'Week outline'**
  String get planNewWeekOutline;

  /// More-weeks preview footer
  ///
  /// In en, this message translates to:
  /// **'+ {count} more weeks'**
  String planNewMoreWeeks(int count);

  /// Active-sessions count on a preview week row
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String planNewSessions(int count);

  /// Plan-new club-template picker
  ///
  /// In en, this message translates to:
  /// **'Start from a club template'**
  String get planNewTemplateTitle;

  /// Plan-new club-template picker
  ///
  /// In en, this message translates to:
  /// **'Adopt a plan a club you belong to has published. It clones into your account with the start date below — edit it like any other plan.'**
  String get planNewTemplateSubtitle;

  /// Plan-new club-template picker
  ///
  /// In en, this message translates to:
  /// **'Browse templates'**
  String get planNewTemplateButton;

  /// Plan-new club-template picker
  ///
  /// In en, this message translates to:
  /// **'Adopting…'**
  String get planNewTemplateCloning;

  /// Toast when adopting a club template fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t adopt that template: {error}'**
  String planNewTemplateCloneFailed(String error);

  /// Plan-new club-template picker
  ///
  /// In en, this message translates to:
  /// **'Choose a template'**
  String get planNewTemplatePickerTitle;

  /// Plan-new club-template picker
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get planNewTemplatePickerCancel;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Public plan library'**
  String get planLibraryTitle;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Plans published by other runners. Clone one into your account to start training.'**
  String get planLibrarySubheading;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Search plans by name'**
  String get planLibrarySearchHint;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load the library. Retry.'**
  String get planLibraryLoadError;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get planLibraryRetry;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'No published plans yet.'**
  String get planLibraryEmpty;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'No plans match “{query}”.'**
  String planLibraryEmptySearch(String query);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'by {author}'**
  String planLibraryByAuthor(String author);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'a runner'**
  String get planLibraryAnonymous;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'{weeks} weeks'**
  String planLibraryWeeks(int weeks);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'{days}×/week'**
  String planLibraryDaysPerWeek(int days);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Clone into my plans'**
  String get planLibraryClone;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Cloning…'**
  String get planLibraryCloning;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Plan cloned.'**
  String get planLibraryCloneSuccess;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Failed to clone: {error}'**
  String planLibraryCloneFailed(String error);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get planLibraryStartDate;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'This plan is no longer in the public library.'**
  String get planLibraryNotFound;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Weeks'**
  String get planLibraryPreviewWeeks;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Week {n}'**
  String planLibraryPreviewWeek(int n);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Public plan library'**
  String get planDetailPublishLibraryLabel;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Publish to library'**
  String get planDetailPublishLibrary;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Share a copy of this plan so anyone can clone it. Your fitness numbers are not shared.'**
  String get planDetailPublishLibraryHint;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Plan published to the public library. Your personal plan is unchanged.'**
  String get planDetailPublishLibrarySuccess;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Failed to publish: {error}'**
  String planDetailPublishLibraryFailed(String error);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Unpublish'**
  String get planDetailUnpublishLibrary;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Removed from the public library.'**
  String get planDetailUnpublishSuccess;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Failed to unpublish: {error}'**
  String planDetailUnpublishFailed(String error);

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'This plan is in the public library.'**
  String get planDetailAlreadyPublished;

  /// Public plan library
  ///
  /// In en, this message translates to:
  /// **'Browse library'**
  String get plansBrowseLibrary;

  /// Plan-new built-in starter-plan picker
  ///
  /// In en, this message translates to:
  /// **'Start from a built-in plan'**
  String get planNewStarterTitle;

  /// Plan-new built-in starter-plan picker
  ///
  /// In en, this message translates to:
  /// **'Pick a proven training plan and we\'ll schedule it from your start date — you can tweak it after.'**
  String get planNewStarterSubtitle;

  /// Plan-new built-in starter-plan picker
  ///
  /// In en, this message translates to:
  /// **'Browse starter plans'**
  String get planNewStarterButton;

  /// Plan-new built-in starter-plan picker
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get planNewStarterCreating;

  /// Plan-new built-in starter-plan picker
  ///
  /// In en, this message translates to:
  /// **'Choose a starter plan'**
  String get planNewStarterPickerTitle;

  /// Plan-new built-in starter-plan picker
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get planNewStarterPickerCancel;

  /// Toast when creating from a starter plan fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create that plan: {error}'**
  String planNewStarterCreateFailed(String error);

  /// Title of the confirm dialog shown before a new plan retires the current active one
  ///
  /// In en, this message translates to:
  /// **'Replace your active plan?'**
  String get planNewReplaceActiveTitle;

  /// Body of the replace-active-plan confirm dialog when the existing plan has a name
  ///
  /// In en, this message translates to:
  /// **'You already have an active plan: \"{name}\". Creating a new plan will mark the current one as completed (you can still find it under Manage plans). Continue?'**
  String planNewReplaceActiveNamed(String name);

  /// Body of the replace-active-plan confirm dialog when the existing plan name is unknown
  ///
  /// In en, this message translates to:
  /// **'You already have an active plan. Creating a new plan will mark the current one as completed. Continue?'**
  String get planNewReplaceActiveUnnamed;

  /// Confirm button of the replace-active-plan dialog
  ///
  /// In en, this message translates to:
  /// **'Replace plan'**
  String get planNewReplaceActiveConfirm;

  /// Cancel button of the replace-active-plan dialog
  ///
  /// In en, this message translates to:
  /// **'Keep current'**
  String get planNewReplaceActiveKeep;

  /// Built-in starter plan name
  ///
  /// In en, this message translates to:
  /// **'Couch to 5K (beginner walk-run)'**
  String get planNewStarterC25k;

  /// Built-in starter plan name
  ///
  /// In en, this message translates to:
  /// **'Half Marathon — 12 weeks'**
  String get planNewStarterHalf12;

  /// Built-in starter plan name
  ///
  /// In en, this message translates to:
  /// **'Marathon — 16 weeks'**
  String get planNewStarterMarathon16;

  /// Plan-detail load timeout error
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network and try again.'**
  String get planDetailTimeoutError;

  /// Plan-detail generic load error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this plan. Tap retry to try again.'**
  String get planDetailLoadError;

  /// Plan-detail not-found body
  ///
  /// In en, this message translates to:
  /// **'Plan not found.'**
  String get planDetailNotFound;

  /// Plan-detail header stat label for the longest completed long run
  ///
  /// In en, this message translates to:
  /// **'Longest long run'**
  String get planDetailLongestLongRun;

  /// Publish-as-template AppBar action tooltip
  ///
  /// In en, this message translates to:
  /// **'Publish as club template'**
  String get planDetailPublishTooltip;

  /// Days-per-week meta on the hero card
  ///
  /// In en, this message translates to:
  /// **'{count} days/wk'**
  String planDetailDaysPerWeek(int count);

  /// Heading for the focused current-week 7-day strip on plan detail
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get planDetailCurrentWeek;

  /// Today-card eyebrow label
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get planDetailToday;

  /// Completed marker on the today card
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get planDetailCompleted;

  /// Week-card title
  ///
  /// In en, this message translates to:
  /// **'Week {number}'**
  String planDetailWeek(int number);

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Running {pct}% over plan this week — ease back on the easy days so you don\'t dig a fatigue hole.'**
  String planDetailDriftOverFlag(int pct);

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Running {pct}% under plan this week — the planned volume drives the adaptation.'**
  String planDetailDriftUnderFlag(int pct);

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'You missed this week\'s long run — fit it in if you can. It\'s the session that matters most.'**
  String get planDetailMissedLongMakeUp;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'You missed a long run, but you\'re tapering — let it go and stay fresh for race day.'**
  String get planDetailMissedLongTaper;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'You missed a long run — skip the make-up. A step-back week is coming and your body will use the rest.'**
  String get planDetailMissedLongRecovery;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Re-plan remaining weeks'**
  String get planDetailReplan;

  /// No description provided for @planDetailAdaptiveReplan.
  ///
  /// In en, this message translates to:
  /// **'Adaptive re-plan'**
  String get planDetailAdaptiveReplan;

  /// No description provided for @planDetailAdaptiveOnTrack.
  ///
  /// In en, this message translates to:
  /// **'Your recent weeks are on track — no adjustment needed.'**
  String get planDetailAdaptiveOnTrack;

  /// No description provided for @planDetailAdaptiveNoSafeChange.
  ///
  /// In en, this message translates to:
  /// **'You\'ve drifted from plan recently, but there\'s no safe adjustment to make right now.'**
  String get planDetailAdaptiveNoSafeChange;

  /// No description provided for @planDetailAdaptiveFitnessHeld.
  ///
  /// In en, this message translates to:
  /// **'Held back — you\'re carrying fatigue right now, so adding volume isn\'t advised.'**
  String get planDetailAdaptiveFitnessHeld;

  /// No description provided for @planDetailAdaptiveReasonUnder.
  ///
  /// In en, this message translates to:
  /// **'under your plan for multiple weeks'**
  String get planDetailAdaptiveReasonUnder;

  /// No description provided for @planDetailAdaptiveReasonOver.
  ///
  /// In en, this message translates to:
  /// **'over your plan for multiple weeks'**
  String get planDetailAdaptiveReasonOver;

  /// No description provided for @planDetailAdaptiveConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'high confidence'**
  String get planDetailAdaptiveConfidenceHigh;

  /// No description provided for @planDetailAdaptiveConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'medium confidence'**
  String get planDetailAdaptiveConfidenceMedium;

  /// Plan-detail adaptive re-plan trend badge
  ///
  /// In en, this message translates to:
  /// **'Based on a trend — you\'ve been {reason} ({confidence})'**
  String planDetailAdaptiveBadge(String reason, String confidence);

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Your plan\'s on track — nothing to adjust.'**
  String get planDetailReplanOnTrack;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'{n, plural, one{Adjusted 1 workout} other{Adjusted {n} workouts}}'**
  String planDetailReplanApplied(int n);

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Proposed changes'**
  String get planDetailReplanPreviewTitle;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Long run {from} → {to} — make up a missed long run'**
  String planDetailReplanMakeUp(String from, String to);

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'{from} → {to} — ease off after over-running'**
  String planDetailReplanEase(String from, String to);

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get planDetailReplanCancel;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get planDetailReplanApply;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Duplicate week'**
  String get planDetailDuplicateWeek;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Week {n} duplicated'**
  String planDetailDuplicateWeekDone(int n);

  /// Plan-detail duplicate-week confirm dialog title
  ///
  /// In en, this message translates to:
  /// **'Duplicate this week?'**
  String get planDetailDuplicateConfirmTitle;

  /// Plan-detail duplicate-week confirm dialog body
  ///
  /// In en, this message translates to:
  /// **'This inserts a copy of week {n} and pushes every later week and your race date back by 7 days.'**
  String planDetailDuplicateConfirmMessage(int n);

  /// Plan-detail duplicate-week confirm button
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get planDetailDuplicateConfirm;

  /// Plan-detail adherence/replan/duplicate
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the plan: {error}'**
  String planDetailBulkFailed(String error);

  /// Edit-workout button tooltip on a workout row
  ///
  /// In en, this message translates to:
  /// **'Edit workout'**
  String get planDetailEditTooltip;

  /// Publish flow: clubs-load timeout banner
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your clubs — check your network.'**
  String get planDetailPublishLoadClubsTimeout;

  /// Publish flow: clubs-load generic banner
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your clubs.'**
  String get planDetailPublishLoadClubsFailed;

  /// Publish flow: no eligible clubs banner
  ///
  /// In en, this message translates to:
  /// **'You need to own or admin a club before you can publish a template.'**
  String get planDetailPublishNoClubs;

  /// Publish flow: success banner
  ///
  /// In en, this message translates to:
  /// **'Published \"{name}\" as a club template.'**
  String planDetailPublishSuccess(String name);

  /// Publish flow: failure banner
  ///
  /// In en, this message translates to:
  /// **'Publish failed: {error}'**
  String planDetailPublishFailed(String error);

  /// Publish-club picker sheet title
  ///
  /// In en, this message translates to:
  /// **'Publish to club'**
  String get planDetailPublishPickerTitle;

  /// Publish-club picker sheet body
  ///
  /// In en, this message translates to:
  /// **'Members of the club will be able to adopt this plan as their own.'**
  String get planDetailPublishPickerBody;

  /// Member-count subtitle in the publish-club picker
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} member} other{{count} members}}'**
  String planDetailPublishPickerMembers(int count);

  /// Cancel button in the publish-club picker
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get planDetailPublishCancel;

  /// Workout-detail load timeout error
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check your network and try again.'**
  String get workoutTimeoutError;

  /// Workout-detail generic load error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this workout. Tap retry to try again.'**
  String get workoutLoadError;

  /// Workout-detail not-found body
  ///
  /// In en, this message translates to:
  /// **'Workout not found.'**
  String get workoutNotFound;

  /// Workout-detail distance metric label
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get workoutMetricDistance;

  /// Workout-detail duration metric label
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get workoutMetricDuration;

  /// Workout-detail target-pace metric label
  ///
  /// In en, this message translates to:
  /// **'Target pace'**
  String get workoutMetricTargetPace;

  /// Completed badge on workout detail
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get workoutCompleted;

  /// Unlink-completed-run button
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get workoutUnlink;

  /// No description provided for @workoutUnlinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlink run'**
  String get workoutUnlinkTitle;

  /// No description provided for @workoutUnlinkBody.
  ///
  /// In en, this message translates to:
  /// **'Unlink the matched run? The workout will show as not yet done.'**
  String get workoutUnlinkBody;

  /// No description provided for @workoutUnlinkError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t unlink the run. Try again.'**
  String get workoutUnlinkError;

  /// Skipped badge on workout detail
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get workoutSkipped;

  /// Skip button on workout detail
  ///
  /// In en, this message translates to:
  /// **'Skip this workout'**
  String get workoutSkip;

  /// Un-skip button on a skipped workout
  ///
  /// In en, this message translates to:
  /// **'Un-skip'**
  String get workoutUnskip;

  /// Error banner when toggling a workout skip fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the skip. Try again.'**
  String get workoutSkipError;

  /// Re-link-to-a-different-run button on workout detail
  ///
  /// In en, this message translates to:
  /// **'Re-link'**
  String get workoutRelink;

  /// Title of the re-link picker dialog
  ///
  /// In en, this message translates to:
  /// **'Link a different run'**
  String get workoutRelinkTitle;

  /// Explanatory hint in the re-link picker
  ///
  /// In en, this message translates to:
  /// **'Pick a run near this workout\'s date to count it as this session. Runs already linked to another workout aren\'t shown.'**
  String get workoutRelinkHint;

  /// Loading state in the re-link picker
  ///
  /// In en, this message translates to:
  /// **'Finding your runs…'**
  String get workoutRelinkLoading;

  /// Error state in the re-link picker
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your runs. Try again.'**
  String get workoutRelinkError;

  /// Empty state in the re-link picker
  ///
  /// In en, this message translates to:
  /// **'No eligible runs near this date.'**
  String get workoutRelinkEmpty;

  /// Tag on the currently-linked run in the re-link picker
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get workoutRelinkCurrent;

  /// Start-workout button on workout detail
  ///
  /// In en, this message translates to:
  /// **'Start workout'**
  String get workoutStart;

  /// Workout-detail Notes section header
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get workoutSectionNotes;

  /// Workout-detail Structure section header
  ///
  /// In en, this message translates to:
  /// **'Structure'**
  String get workoutSectionStructure;

  /// Workout-detail advice section header
  ///
  /// In en, this message translates to:
  /// **'How to run it'**
  String get workoutSectionHowTo;

  /// Structure-list warmup label
  ///
  /// In en, this message translates to:
  /// **'Warmup'**
  String get workoutStructWarmup;

  /// Structure-list repeats label
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get workoutStructRepeats;

  /// Structure-list steady label
  ///
  /// In en, this message translates to:
  /// **'Steady'**
  String get workoutStructSteady;

  /// Structure-list cooldown label
  ///
  /// In en, this message translates to:
  /// **'Cooldown'**
  String get workoutStructCooldown;

  /// Structure-list warmup value (distance at easy pace)
  ///
  /// In en, this message translates to:
  /// **'{distance} @ easy'**
  String workoutStructWarmupValue(String distance);

  /// Structure-list cooldown value (distance at easy pace)
  ///
  /// In en, this message translates to:
  /// **'{distance} @ easy'**
  String workoutStructCooldownValue(String distance);

  /// Advice text for easy / recovery workouts
  ///
  /// In en, this message translates to:
  /// **'Conversational pace. If you can\'t hold a conversation, you\'re running it too fast.'**
  String get workoutAdviceEasy;

  /// Advice text for long runs
  ///
  /// In en, this message translates to:
  /// **'Stay relaxed. Aim for steady breathing. Drop 10% of the distance if weather is rough or you\'re sore — don\'t skip.'**
  String get workoutAdviceLong;

  /// Advice text for tempo runs
  ///
  /// In en, this message translates to:
  /// **'\"Comfortably hard\". You should feel like you could hold the pace for about an hour at peak effort, but no longer.'**
  String get workoutAdviceTempo;

  /// Advice text for interval workouts
  ///
  /// In en, this message translates to:
  /// **'Run the reps hard enough that the last one feels like the first. Don\'t pick a pace you can only hold for two or three reps.'**
  String get workoutAdviceInterval;

  /// Advice text for marathon-pace workouts
  ///
  /// In en, this message translates to:
  /// **'Lock into goal marathon pace exactly. This is a rehearsal session — no faster, no slower.'**
  String get workoutAdviceMarathonPace;

  /// Advice text for walk-run workouts
  ///
  /// In en, this message translates to:
  /// **'Alternate easy running and walking on the timed intervals. The walk breaks are part of the workout — take them even when you feel fresh.'**
  String get workoutAdviceWalkRun;

  /// Advice text for race workouts
  ///
  /// In en, this message translates to:
  /// **'Trust the plan. Don\'t chase a PB in the first mile.'**
  String get workoutAdviceRace;

  /// Advice text for rest days
  ///
  /// In en, this message translates to:
  /// **'Rest day — if you need to move, walk or stretch.'**
  String get workoutAdviceRest;

  /// Coach screen AppBar title
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get coachTitle;

  /// Default active-thread title when empty
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get coachNewConversation;

  /// Consent gate headline
  ///
  /// In en, this message translates to:
  /// **'Before you chat with Coach'**
  String get coachConsentHeadline;

  /// Consent gate intro paragraph
  ///
  /// In en, this message translates to:
  /// **'To give you grounded advice, Coach forwards a slice of your training data to Anthropic, our AI model provider in the United States. That slice includes:'**
  String get coachConsentIntro;

  /// Consent gate bullet: profile data
  ///
  /// In en, this message translates to:
  /// **'Your date of birth, gender, and HR zones if set.'**
  String get coachConsentBulletProfile;

  /// Consent gate bullet: recent runs
  ///
  /// In en, this message translates to:
  /// **'A window of your most recent runs.'**
  String get coachConsentBulletRuns;

  /// Consent gate bullet: active plan
  ///
  /// In en, this message translates to:
  /// **'The active training plan you have selected.'**
  String get coachConsentBulletPlan;

  /// Consent gate bullet: chat messages
  ///
  /// In en, this message translates to:
  /// **'The chat messages you type in the screen below.'**
  String get coachConsentBulletMessages;

  /// Consent gate data-processing paragraph
  ///
  /// In en, this message translates to:
  /// **'Anthropic processes the data on Threkir\'s behalf under their data-processing terms; they do not train their models on Threkir customer data by default. Full details — including transfer mechanism, retention, and your withdrawal rights — are in our privacy policy.'**
  String get coachConsentProcessing;

  /// Consent gate action paragraph
  ///
  /// In en, this message translates to:
  /// **'Tap \"I consent\" to continue. Tap cancel to leave the page with no data sent.'**
  String get coachConsentAction;

  /// Consent gate cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get coachConsentCancel;

  /// Consent gate accept button
  ///
  /// In en, this message translates to:
  /// **'I consent — start Coach'**
  String get coachConsentAccept;

  /// Consent gate accept button while saving
  ///
  /// In en, this message translates to:
  /// **'Recording consent…'**
  String get coachConsentSaving;

  /// Plan-switcher dropdown: no plan option
  ///
  /// In en, this message translates to:
  /// **'No plan (recent runs only)'**
  String get coachNoPlanOption;

  /// Plan-switcher dropdown: active plan label
  ///
  /// In en, this message translates to:
  /// **'{name} · active'**
  String coachPlanActive(String name);

  /// Plan-switcher dropdown: completed plan label
  ///
  /// In en, this message translates to:
  /// **'{name} · done'**
  String coachPlanDone(String name);

  /// New-chat AppBar action tooltip
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get coachNewChatTooltip;

  /// Chat-history AppBar action tooltip
  ///
  /// In en, this message translates to:
  /// **'Chat history'**
  String get coachHistoryTooltip;

  /// New-chat button in the drawer
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get coachNewChat;

  /// Drawer subtitle for the active thread, with optional ' · N' message-count suffix
  ///
  /// In en, this message translates to:
  /// **'Active{suffix}'**
  String coachActiveThread(String suffix);

  /// Drawer subtitle on an archived thread row
  ///
  /// In en, this message translates to:
  /// **'Tap to view · swipe to delete'**
  String get coachArchiveTapToView;

  /// Context-strip chip when no plan is active
  ///
  /// In en, this message translates to:
  /// **'No plan'**
  String get coachContextNoPlan;

  /// Context-strip chip: plan name with week count
  ///
  /// In en, this message translates to:
  /// **'{name} · {weeks}w'**
  String coachContextPlanWeeks(String name, int weeks);

  /// Context-strip runs chip when there are no runs
  ///
  /// In en, this message translates to:
  /// **'No runs'**
  String get coachContextNoRuns;

  /// Context-strip runs chip prefix before the run-count selector
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get coachContextLast;

  /// Context-strip heart-rate-zones chip
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get coachContextHr;

  /// Context-strip weekly-goal chip
  ///
  /// In en, this message translates to:
  /// **'{km} km/wk'**
  String coachContextWeeklyGoal(String km);

  /// Archive-view banner text
  ///
  /// In en, this message translates to:
  /// **'Viewing archive · {label} · read-only'**
  String coachArchiveBanner(String label);

  /// Back-to-active button in the archive banner
  ///
  /// In en, this message translates to:
  /// **'Back to active'**
  String get coachBackToActive;

  /// Daily-cap banner for Pro tier
  ///
  /// In en, this message translates to:
  /// **'Daily limit reached. Come back tomorrow.'**
  String get coachLimitReachedPro;

  /// Daily-cap banner for free tier
  ///
  /// In en, this message translates to:
  /// **'Daily limit reached. Pro gets a higher cap — upgrade in Settings.'**
  String get coachLimitReachedFree;

  /// Daily-cap banner: messages remaining today
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} message left today} other{{count} messages left today}}'**
  String coachMessagesLeft(int count);

  /// Empty-chat prompt when a plan is active
  ///
  /// In en, this message translates to:
  /// **'Ask about today\'s workout, your pace, or how recent runs compare to plan.'**
  String get coachEmptyPromptPlan;

  /// Empty-chat prompt when no plan is active
  ///
  /// In en, this message translates to:
  /// **'Ask about your recent runs, easy-run pacing, or training basics.'**
  String get coachEmptyPromptNoPlan;

  /// Suggestion chip (plan)
  ///
  /// In en, this message translates to:
  /// **'Should I run tomorrow or take a rest day?'**
  String get coachSuggestPlanRest;

  /// Suggestion chip (plan)
  ///
  /// In en, this message translates to:
  /// **'Am I on track for my goal time?'**
  String get coachSuggestPlanOnTrack;

  /// Suggestion chip (plan)
  ///
  /// In en, this message translates to:
  /// **'Why does this week\'s long run matter?'**
  String get coachSuggestPlanLongRun;

  /// Suggestion chip (plan)
  ///
  /// In en, this message translates to:
  /// **'What should I focus on for today\'s workout?'**
  String get coachSuggestPlanToday;

  /// Suggestion chip (no plan)
  ///
  /// In en, this message translates to:
  /// **'How was my last run?'**
  String get coachSuggestNoPlanLastRun;

  /// Suggestion chip (no plan)
  ///
  /// In en, this message translates to:
  /// **'What pace should my easy runs be?'**
  String get coachSuggestNoPlanEasyPace;

  /// Suggestion chip (no plan)
  ///
  /// In en, this message translates to:
  /// **'I haven\'t run in a week — what should I do?'**
  String get coachSuggestNoPlanWeekOff;

  /// Suggestion chip (no plan)
  ///
  /// In en, this message translates to:
  /// **'What is a tempo run?'**
  String get coachSuggestNoPlanTempo;

  /// Cancel button in the inline message-edit form
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get coachEditCancel;

  /// Save-and-resend button in the inline message-edit form
  ///
  /// In en, this message translates to:
  /// **'Save & resend'**
  String get coachEditSaveResend;

  /// Copy bubble-action tooltip
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get coachActionCopy;

  /// Edit bubble-action tooltip
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get coachActionEdit;

  /// Regenerate bubble-action tooltip
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get coachActionRegenerate;

  /// Thumbs-up bubble-action tooltip
  ///
  /// In en, this message translates to:
  /// **'Helpful'**
  String get coachActionHelpful;

  /// Thumbs-down bubble-action tooltip
  ///
  /// In en, this message translates to:
  /// **'Not helpful'**
  String get coachActionNotHelpful;

  /// Composer hint when the daily cap is hit
  ///
  /// In en, this message translates to:
  /// **'Daily limit reached'**
  String get coachComposerHintLimit;

  /// Composer hint
  ///
  /// In en, this message translates to:
  /// **'Ask Coach…'**
  String get coachComposerHint;

  /// Archive-current dialog title
  ///
  /// In en, this message translates to:
  /// **'Start a new conversation?'**
  String get coachArchiveTitle;

  /// Archive-current dialog body
  ///
  /// In en, this message translates to:
  /// **'The current chat moves to history. You can revisit it from the sidebar.'**
  String get coachArchiveBody;

  /// Cancel button in the archive-current dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get coachArchiveCancel;

  /// Confirm button in the archive-current dialog
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get coachArchiveConfirm;

  /// Error when sending without a session
  ///
  /// In en, this message translates to:
  /// **'Please sign in first.'**
  String get coachSignInFirst;

  /// Error on 401 from /api/coach
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get coachSessionExpired;

  /// Error on 429: daily limit reached
  ///
  /// In en, this message translates to:
  /// **'Daily limit reached ({limit} messages). Come back tomorrow!'**
  String coachDailyLimitError(int limit);

  /// Generic error with HTTP status code
  ///
  /// In en, this message translates to:
  /// **'Coach error ({code})'**
  String coachGenericError(int code);

  /// Error on transport-layer failure
  ///
  /// In en, this message translates to:
  /// **'Could not reach the Coach. Check your connection and try again.'**
  String get coachTransportError;

  /// Fallback error message from the SSE error event
  ///
  /// In en, this message translates to:
  /// **'stream failed'**
  String get coachStreamFailed;

  /// Error starting a new conversation
  ///
  /// In en, this message translates to:
  /// **'Could not start a new conversation: {error}'**
  String coachNewConversationFailed(String error);

  /// Error opening an archive
  ///
  /// In en, this message translates to:
  /// **'Could not open archive: {error}'**
  String coachOpenArchiveFailed(String error);

  /// Banner shown when deleting a coach archive fails; the swiped row snaps back
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete archive: {error}'**
  String coachArchiveDeleteFailed(String error);

  /// Top-banner shown after copying a message
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get coachCopied;

  /// AppBar title for the Settings > Account screen
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountTitle;

  /// Banner shown when sign-in is attempted but no backend is configured
  ///
  /// In en, this message translates to:
  /// **'Backend not configured'**
  String get settingsAccountBackendNotConfigured;

  /// Banner shown when signing out fails
  ///
  /// In en, this message translates to:
  /// **'Sign out failed — check your connection'**
  String get settingsAccountSignOutFailed;

  /// Tile title and dialog title for changing the account password
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsAccountChangePassword;

  /// Label for the new-password field
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get settingsAccountNewPassword;

  /// Label for the confirm-password field
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get settingsAccountConfirm;

  /// Cancel button on the Account screen dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsAccountCancel;

  /// Save button on the Account screen dialogs
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsAccountSave;

  /// Validation error when the new password is shorter than 8 characters
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get settingsAccountPasswordTooShort;

  /// Validation error when the password and confirmation differ
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get settingsAccountPasswordsMismatch;

  /// Banner shown after the password is changed successfully
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get settingsAccountPasswordUpdated;

  /// Banner shown when the password change fails
  ///
  /// In en, this message translates to:
  /// **'Could not update password: {error}'**
  String settingsAccountPasswordUpdateFailed(Object error);

  /// Title of the delete-account confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get settingsAccountDeleteTitle;

  /// Body copy of the delete-account confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your runs, routes, and profile from the server. Local device data is kept unless you sign in as a new user. This cannot be undone.'**
  String get settingsAccountDeleteBody;

  /// Challenge field label when the account has no email on file
  ///
  /// In en, this message translates to:
  /// **'Type \"DELETE\" to confirm'**
  String get settingsAccountDeleteChallengeText;

  /// Challenge field label asking the user to type their email
  ///
  /// In en, this message translates to:
  /// **'Type your email ({email}) to confirm'**
  String settingsAccountDeleteChallengeEmail(String email);

  /// Confirm button on the delete-account dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsAccountDelete;

  /// Banner shown when the user tries to delete an account while signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in first to delete your account.'**
  String get settingsAccountDeleteSignInFirst;

  /// Banner shown after the account is deleted
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get settingsAccountDeleted;

  /// Settings > Account tile title to withdraw AI-coach consent (GDPR Art 7(3))
  ///
  /// In en, this message translates to:
  /// **'Withdraw AI Coach consent'**
  String get settingsAccountCoachConsentWithdraw;

  /// Subtitle under the withdraw-coach-consent tile
  ///
  /// In en, this message translates to:
  /// **'Stop the Coach from using your training data. You can grant consent again any time.'**
  String get settingsAccountCoachConsentActive;

  /// Banner shown after AI-coach consent is withdrawn
  ///
  /// In en, this message translates to:
  /// **'AI Coach consent withdrawn.'**
  String get settingsAccountCoachConsentWithdrawn;

  /// Banner shown when withdrawing AI-coach consent fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t withdraw consent: {error}'**
  String settingsAccountCoachConsentWithdrawFailed(Object error);

  /// Banner shown when account deletion fails
  ///
  /// In en, this message translates to:
  /// **'Account deletion failed: {error}'**
  String settingsAccountDeleteFailed(Object error);

  /// Banner shown when CSV export is requested but there are no runs
  ///
  /// In en, this message translates to:
  /// **'No runs to export.'**
  String get settingsAccountNoRunsToExport;

  /// Share-sheet caption for the CSV runs export
  ///
  /// In en, this message translates to:
  /// **'Run app — runs export'**
  String get settingsAccountCsvShareText;

  /// Banner shown when the CSV export fails
  ///
  /// In en, this message translates to:
  /// **'CSV export failed: {error}'**
  String settingsAccountCsvExportFailed(Object error);

  /// Banner shown when backup is requested while signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in first to back up your runs.'**
  String get settingsAccountBackupSignInFirst;

  /// Banner shown while the backup archive is being prepared
  ///
  /// In en, this message translates to:
  /// **'Preparing backup…'**
  String get settingsAccountBackupPreparing;

  /// Share-sheet caption for the full backup archive
  ///
  /// In en, this message translates to:
  /// **'Run app backup'**
  String get settingsAccountBackupShareText;

  /// Banner shown when the backup fails
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String settingsAccountBackupFailed(Object error);

  /// Banner shown when restore can't run because the local store is missing
  ///
  /// In en, this message translates to:
  /// **'Backup service unavailable.'**
  String get settingsAccountRestoreUnavailable;

  /// Title of the restore-from-backup confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Restore from backup?'**
  String get settingsAccountRestoreTitle;

  /// Restore dialog body shown when the user is signed out
  ///
  /// In en, this message translates to:
  /// **'You\'re not signed in. Runs will be restored to this device and synced to your account the next time you sign in.'**
  String get settingsAccountRestoreBodyOffline;

  /// Restore dialog body shown when the user is signed in
  ///
  /// In en, this message translates to:
  /// **'This adds or overwrites runs and routes matching IDs in the backup. It will not delete runs or routes that aren\'t in the backup.'**
  String get settingsAccountRestoreBodyOnline;

  /// Confirm button on the restore dialog
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get settingsAccountRestore;

  /// Banner shown while a backup is being restored
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get settingsAccountRestoring;

  /// Banner summarising a successful restore; warnings is an optional suffix
  ///
  /// In en, this message translates to:
  /// **'Restored {runs} runs · {tracks} tracks · {routes} routes{warnings}'**
  String settingsAccountRestoreDone(
    int runs,
    int tracks,
    int routes,
    String warnings,
  );

  /// Suffix appended to the restore summary when warnings occurred
  ///
  /// In en, this message translates to:
  /// **' · {count} warnings'**
  String settingsAccountRestoreWarningsSuffix(int count);

  /// Banner shown when restore fails
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String settingsAccountRestoreFailed(Object error);

  /// Account-row title shown when no email is on file
  ///
  /// In en, this message translates to:
  /// **'Offline mode'**
  String get settingsAccountOfflineMode;

  /// Account-row subtitle when the user is signed in
  ///
  /// In en, this message translates to:
  /// **'Signed in — runs will sync'**
  String get settingsAccountSignedInSync;

  /// Account-row subtitle when the user is signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync runs across devices'**
  String get settingsAccountSignInToSync;

  /// Tooltip on the sign-out button
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsAccountSignOut;

  /// Sign-in button on the Account screen
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get settingsAccountSignIn;

  /// Profile-photo (avatar) tile title in Account settings
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get settingsAccountAvatar;

  /// Subtitle under the profile-photo tile listing accepted formats
  ///
  /// In en, this message translates to:
  /// **'JPEG, PNG, or WebP, up to 2 MB.'**
  String get settingsAccountAvatarHint;

  /// Tooltip on the remove-avatar button
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get settingsAccountAvatarRemove;

  /// Title of the remove-avatar confirm dialog
  ///
  /// In en, this message translates to:
  /// **'Remove profile photo?'**
  String get settingsAccountAvatarRemoveTitle;

  /// Body of the remove-avatar confirm dialog
  ///
  /// In en, this message translates to:
  /// **'This removes your current profile photo. You can upload a new one anytime.'**
  String get settingsAccountAvatarRemoveConfirm;

  /// Banner shown after the avatar uploads
  ///
  /// In en, this message translates to:
  /// **'Profile photo updated.'**
  String get settingsAccountAvatarSaved;

  /// Banner shown after the avatar is removed
  ///
  /// In en, this message translates to:
  /// **'Profile photo removed.'**
  String get settingsAccountAvatarRemoved;

  /// Banner shown when a picked image isn't a supported avatar format
  ///
  /// In en, this message translates to:
  /// **'Unsupported image — choose a JPEG, PNG, or WebP.'**
  String get settingsAccountAvatarUnsupported;

  /// Banner shown when the avatar upload or removal fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update photo: {error}'**
  String settingsAccountAvatarFailed(Object error);

  /// Tile title that opens the user's own profile
  ///
  /// In en, this message translates to:
  /// **'View profile'**
  String get settingsAccountViewProfile;

  /// Subtitle of the View profile tile
  ///
  /// In en, this message translates to:
  /// **'Your runs, followers, following, notifications'**
  String get settingsAccountViewProfileSubtitle;

  /// Tile title for guided runs
  ///
  /// In en, this message translates to:
  /// **'Guided runs'**
  String get settingsAccountGuidedRuns;

  /// Subtitle of the Guided runs tile
  ///
  /// In en, this message translates to:
  /// **'Coach-voice scripted workouts with TTS cues'**
  String get settingsAccountGuidedRunsSubtitle;

  /// Tile title for privacy zones
  ///
  /// In en, this message translates to:
  /// **'Privacy zones'**
  String get settingsAccountPrivacyZones;

  /// Subtitle of the Privacy zones tile
  ///
  /// In en, this message translates to:
  /// **'Clip start/end of public tracks near home'**
  String get settingsAccountPrivacyZonesSubtitle;

  /// Toggle title for Sentry error reporting
  ///
  /// In en, this message translates to:
  /// **'Send error reports'**
  String get settingsAccountSendErrorReports;

  /// Subtitle of the error-reporting toggle
  ///
  /// In en, this message translates to:
  /// **'Anonymised crash + error data to Sentry (US). Toggle off to withdraw consent. Applies on next launch.'**
  String get settingsAccountSendErrorReportsSubtitle;

  /// Banner shown after enabling error reporting
  ///
  /// In en, this message translates to:
  /// **'Error reporting enabled — restart the app to apply.'**
  String get settingsAccountErrorReportingEnabled;

  /// Banner shown after disabling error reporting
  ///
  /// In en, this message translates to:
  /// **'Error reporting disabled — restart the app to apply.'**
  String get settingsAccountErrorReportingDisabled;

  /// Tile title for importing runs
  ///
  /// In en, this message translates to:
  /// **'Import from another app'**
  String get settingsAccountImport;

  /// Subtitle of the Import tile
  ///
  /// In en, this message translates to:
  /// **'Strava, GPX, TCX'**
  String get settingsAccountImportSubtitle;

  /// Tile title for the full backup export
  ///
  /// In en, this message translates to:
  /// **'Full backup'**
  String get settingsAccountFullBackup;

  /// Subtitle of the Full backup tile
  ///
  /// In en, this message translates to:
  /// **'Every run with its GPS trace, plus routes, profile, and preferences. Restores on web or Android.'**
  String get settingsAccountFullBackupSubtitle;

  /// Tile title for the CSV runs export
  ///
  /// In en, this message translates to:
  /// **'Export runs as CSV'**
  String get settingsAccountExportCsv;

  /// Subtitle of the Export runs as CSV tile
  ///
  /// In en, this message translates to:
  /// **'date, distance, duration, pace, source — one row per run. Same shape as the web GDPR export.'**
  String get settingsAccountExportCsvSubtitle;

  /// Tile title for restoring from a backup file
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get settingsAccountRestoreTile;

  /// Subtitle of the Restore from backup tile
  ///
  /// In en, this message translates to:
  /// **'Pick a previously saved .zip backup.'**
  String get settingsAccountRestoreTileSubtitle;

  /// Tile title for deleting the account
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsAccountDeleteAccount;

  /// Subtitle of the Delete account tile
  ///
  /// In en, this message translates to:
  /// **'Permanently removes server data'**
  String get settingsAccountDeleteAccountSubtitle;

  /// AppBar title for the Settings > Integrations screen
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get integrationsTitle;

  /// Relative-time label for an event less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get integrationsJustNow;

  /// Relative-time label in minutes
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String integrationsMinutesAgo(int minutes);

  /// Relative-time label in hours
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String integrationsHoursAgo(int hours);

  /// Relative-time label in days
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String integrationsDaysAgo(int days);

  /// Relative-time label in weeks
  ///
  /// In en, this message translates to:
  /// **'{weeks}w ago'**
  String integrationsWeeksAgo(int weeks);

  /// Banner shown when an external URL can't be opened
  ///
  /// In en, this message translates to:
  /// **'Could not open: {error}'**
  String integrationsCouldNotOpen(Object error);

  /// Banner shown when Strava connect falls back to the browser flow
  ///
  /// In en, this message translates to:
  /// **'Complete the Strava sign-in in your browser, then return here and pull to refresh.'**
  String get integrationsStravaBrowserHint;

  /// Banner shown when the user cancels the Strava OAuth flow
  ///
  /// In en, this message translates to:
  /// **'Strava sign-in cancelled.'**
  String get integrationsStravaCancelled;

  /// Banner shown when Strava sign-in fails
  ///
  /// In en, this message translates to:
  /// **'Strava sign-in failed: {error}'**
  String integrationsStravaSignInFailed(Object error);

  /// Banner shown when the Strava OAuth state doesn't match
  ///
  /// In en, this message translates to:
  /// **'Strava sign-in rejected: CSRF state mismatch. Please retry.'**
  String get integrationsStravaCsrfMismatch;

  /// Banner shown when the Strava token exchange fails
  ///
  /// In en, this message translates to:
  /// **'Strava connect failed: {error}'**
  String integrationsStravaConnectFailed(String error);

  /// Banner shown after Strava connects successfully
  ///
  /// In en, this message translates to:
  /// **'Strava connected.'**
  String get integrationsStravaConnected;

  /// Banner summarising a Strava sync
  ///
  /// In en, this message translates to:
  /// **'Synced. {imported} new, {skipped} already present.'**
  String integrationsSyncResult(int imported, int skipped);

  /// Banner shown when a Strava sync fails
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String integrationsSyncFailed(Object error);

  /// Title of the disconnect-Strava confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Disconnect Strava?'**
  String get integrationsStravaDisconnectTitle;

  /// Body of the disconnect-Strava confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Future activities will stop syncing automatically. Already-imported runs stay in your history.'**
  String get integrationsStravaDisconnectBody;

  /// Cancel button on Integrations dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get integrationsCancel;

  /// Disconnect button and popup-menu item
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get integrationsDisconnect;

  /// Banner shown after Strava is disconnected
  ///
  /// In en, this message translates to:
  /// **'Strava disconnected.'**
  String get integrationsStravaDisconnected;

  /// Banner shown when disconnecting fails
  ///
  /// In en, this message translates to:
  /// **'Disconnect failed: {error}'**
  String integrationsDisconnectFailed(Object error);

  /// Title of the parkrun import dialog
  ///
  /// In en, this message translates to:
  /// **'Import parkrun results'**
  String get integrationsParkrunTitle;

  /// Body of the parkrun import dialog
  ///
  /// In en, this message translates to:
  /// **'Enter your parkrun athlete number (e.g. A123456). We\'ll fetch your finish history and add any new results to your runs list.'**
  String get integrationsParkrunBody;

  /// Label for the parkrun athlete-number field
  ///
  /// In en, this message translates to:
  /// **'Athlete number'**
  String get integrationsParkrunFieldLabel;

  /// Import button on the parkrun dialog
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get integrationsImport;

  /// Progress text while parkrun results are imported
  ///
  /// In en, this message translates to:
  /// **'Importing parkrun results…'**
  String get integrationsParkrunImporting;

  /// Banner summarising imported parkrun results
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Imported {count} parkrun result.} other{Imported {count} parkrun results.}}'**
  String integrationsParkrunImported(int count);

  /// Banner shown when no new parkrun results were found
  ///
  /// In en, this message translates to:
  /// **'No new parkrun results since last import.'**
  String get integrationsParkrunNoneNew;

  /// Banner shown when the parkrun import fails
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String integrationsImportFailed(Object error);

  /// Strava integration tile title (brand name)
  ///
  /// In en, this message translates to:
  /// **'Strava'**
  String get integrationsStravaName;

  /// Strava tile subtitle when not connected
  ///
  /// In en, this message translates to:
  /// **'Connect to auto-sync activities'**
  String get integrationsStravaConnectSubtitle;

  /// Strava tile subtitle when connected but never synced
  ///
  /// In en, this message translates to:
  /// **'Connected · waiting for first sync'**
  String get integrationsStravaWaitingFirstSync;

  /// Strava tile subtitle showing the last sync time
  ///
  /// In en, this message translates to:
  /// **'Connected · last sync {time}'**
  String integrationsStravaLastSync(String time);

  /// Popup-menu item to trigger a Strava sync
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get integrationsSyncNow;

  /// parkrun integration tile title (brand name)
  ///
  /// In en, this message translates to:
  /// **'parkrun'**
  String get integrationsParkrunName;

  /// parkrun tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Import results by athlete number'**
  String get integrationsParkrunTileSubtitle;

  /// parkrun tile subtitle shown when the device region is outside the parkrun footprint
  ///
  /// In en, this message translates to:
  /// **'parkrun runs in a limited set of countries and may not have events near you — you can still import results with a parkrun athlete ID.'**
  String get integrationsParkrunRegionNote;

  /// Tile title shown when signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in to connect services'**
  String get integrationsSignInTitle;

  /// Tile subtitle shown when signed out
  ///
  /// In en, this message translates to:
  /// **'Strava + parkrun require an account so synced activities land in your history.'**
  String get integrationsSignInSubtitle;

  /// Toggle title for writing runs to Health Connect (Android)
  ///
  /// In en, this message translates to:
  /// **'Write runs to Health Connect'**
  String get integrationsHealthConnectTitle;

  /// Subtitle of the Health Connect write toggle
  ///
  /// In en, this message translates to:
  /// **'Send each finished run to Health Connect so it appears in Google Fit, Samsung Health, Fitbit and others.'**
  String get integrationsHealthConnectSubtitle;

  /// Banner shown when the Health Connect write permission is denied
  ///
  /// In en, this message translates to:
  /// **'Health Connect permission not granted — runs won\'t be written.'**
  String get integrationsHealthConnectDenied;

  /// Banner shown when pairing a heart-rate strap fails
  ///
  /// In en, this message translates to:
  /// **'Pair failed: {error}'**
  String integrationsHrPairFailed(Object error);

  /// Tile title for the BLE heart-rate monitor
  ///
  /// In en, this message translates to:
  /// **'Heart rate monitor'**
  String get integrationsHrTitle;

  /// HR tile subtitle while checking for a paired strap
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get integrationsHrChecking;

  /// HR tile subtitle showing the paired strap name
  ///
  /// In en, this message translates to:
  /// **'Paired: {name}'**
  String integrationsHrPaired(String name);

  /// HR tile subtitle when no strap is paired
  ///
  /// In en, this message translates to:
  /// **'No strap paired — tap to scan'**
  String get integrationsHrNotPaired;

  /// Tooltip on the forget-strap button
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get integrationsHrForget;

  /// Confirm dialog body shown before unpairing a heart-rate strap
  ///
  /// In en, this message translates to:
  /// **'Forget this heart rate monitor? You\'ll need to pair it again to use it during a run.'**
  String get integrationsHrForgetConfirm;

  /// Title of the HR scan bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Scan for heart rate monitor'**
  String get integrationsHrScanTitle;

  /// Hint text on the HR scan sheet
  ///
  /// In en, this message translates to:
  /// **'Wake your strap / chest band. Apps typically take 3–8 seconds.'**
  String get integrationsHrScanHint;

  /// Empty-state text on the HR scan sheet
  ///
  /// In en, this message translates to:
  /// **'No straps found. Make sure it\'s nearby and awake.'**
  String get integrationsHrScanEmpty;

  /// Signal-strength subtitle for a discovered strap
  ///
  /// In en, this message translates to:
  /// **'RSSI {rssi} dBm'**
  String integrationsHrRssi(int rssi);

  /// Tile title for the BLE FTMS treadmill
  ///
  /// In en, this message translates to:
  /// **'Treadmill'**
  String get integrationsTreadmillTitle;

  /// Treadmill tile subtitle while checking for a paired treadmill
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get integrationsTreadmillChecking;

  /// Treadmill tile subtitle showing the paired treadmill name
  ///
  /// In en, this message translates to:
  /// **'Paired: {name}'**
  String integrationsTreadmillPaired(String name);

  /// Treadmill tile subtitle when no treadmill is paired
  ///
  /// In en, this message translates to:
  /// **'No treadmill paired — tap to scan'**
  String get integrationsTreadmillNotPaired;

  /// Tooltip on the forget-treadmill button
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get integrationsTreadmillForget;

  /// Confirm dialog body shown before unpairing a treadmill
  ///
  /// In en, this message translates to:
  /// **'Forget this treadmill? You\'ll need to pair it again to use it during a run.'**
  String get integrationsTreadmillForgetConfirm;

  /// Title of the treadmill scan bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Scan for treadmill'**
  String get integrationsTreadmillScanTitle;

  /// Hint text on the treadmill scan sheet
  ///
  /// In en, this message translates to:
  /// **'Make sure the treadmill\'s Bluetooth is on and the belt is awake. Scanning takes 3–8 seconds.'**
  String get integrationsTreadmillScanHint;

  /// Empty-state text on the treadmill scan sheet
  ///
  /// In en, this message translates to:
  /// **'No treadmills found. Make sure it supports Bluetooth (FTMS) and is nearby.'**
  String get integrationsTreadmillScanEmpty;

  /// Banner shown when pairing a treadmill fails
  ///
  /// In en, this message translates to:
  /// **'Pair failed: {error}'**
  String integrationsTreadmillPairFailed(Object error);

  /// Live belt speed shown while connected to a treadmill
  ///
  /// In en, this message translates to:
  /// **'{speed} km/h'**
  String integrationsTreadmillLiveSpeed(String speed);

  /// AppBar title for the Settings > Pro & support screen
  ///
  /// In en, this message translates to:
  /// **'Pro & support'**
  String get proTitle;

  /// Banner shown when an external URL can't be opened
  ///
  /// In en, this message translates to:
  /// **'Could not open: {error}'**
  String proCouldNotOpen(Object error);

  /// Banner shown after a successful Pro purchase
  ///
  /// In en, this message translates to:
  /// **'Welcome to Pro! Pulling your benefits…'**
  String get proWelcome;

  /// Banner shown when a Pro purchase fails
  ///
  /// In en, this message translates to:
  /// **'Purchase failed. Try again later.'**
  String get proPurchaseFailed;

  /// Banner shown when restore can't run because RevenueCat is unconfigured
  ///
  /// In en, this message translates to:
  /// **'Restore needs you to be signed in with RevenueCat configured. Manage your subscription on the web upgrade page instead.'**
  String get proRestoreNeedsSignIn;

  /// Banner shown after purchases are restored
  ///
  /// In en, this message translates to:
  /// **'Restored your Pro subscription.'**
  String get proRestored;

  /// Banner shown when no purchases are found to restore
  ///
  /// In en, this message translates to:
  /// **'No active purchases found on this store account.'**
  String get proRestoreNone;

  /// Banner shown when restore fails
  ///
  /// In en, this message translates to:
  /// **'Restore failed. Try again later.'**
  String get proRestoreFailed;

  /// Banner shown when restore isn't available in the build
  ///
  /// In en, this message translates to:
  /// **'Restore unavailable in this build.'**
  String get proRestoreUnavailable;

  /// Tile title for the Pro subscription; price is a localized currency amount
  ///
  /// In en, this message translates to:
  /// **'Subscribe to Pro — {price}/month'**
  String proSubscribeTitle(String price);

  /// Pro tile subtitle when in-app purchase is configured
  ///
  /// In en, this message translates to:
  /// **'Unlimited AI coach + priority processing. Auto-renews monthly until cancelled in Settings → Subscriptions.'**
  String get proSubscribeSubtitleConfigured;

  /// Pro tile subtitle when falling back to the web portal
  ///
  /// In en, this message translates to:
  /// **'Opens the subscription portal in your browser. Auto-renews monthly until cancelled.'**
  String get proSubscribeSubtitleWeb;

  /// Honesty note about billing currency and regional availability
  ///
  /// In en, this message translates to:
  /// **'Billed in US dollars. Availability depends on your country and payment method — some regions can\'t be served by our payment processor.'**
  String get proRegionalNote;

  /// Tile title to restore purchases
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get proRestorePurchases;

  /// Subtitle of the Restore purchases tile
  ///
  /// In en, this message translates to:
  /// **'Re-link purchases from a previous install or another device'**
  String get proRestorePurchasesSubtitle;

  /// Tile title to manage the subscription
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get proManageSubscription;

  /// Subtitle of the Manage subscription tile
  ///
  /// In en, this message translates to:
  /// **'Cancel, change plan, or update payment method'**
  String get proManageSubscriptionSubtitle;

  /// Tile title for a one-off donation
  ///
  /// In en, this message translates to:
  /// **'Support the app'**
  String get proSupport;

  /// Subtitle of the Support the app tile
  ///
  /// In en, this message translates to:
  /// **'One-off donation in your browser'**
  String get proSupportSubtitle;

  /// AppBar title for the Settings > Licenses screen
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licensesTitle;

  /// Tile title showing the app version
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get licensesVersion;

  /// Tile title that opens the bundled-licenses page
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get licensesOpenSource;

  /// Subtitle of the Open-source licenses tile
  ///
  /// In en, this message translates to:
  /// **'Third-party packages bundled with this app'**
  String get licensesOpenSourceSubtitle;

  /// AppBar title for the Settings > Devices screen
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesTitle;

  /// Title of the rename-device dialog
  ///
  /// In en, this message translates to:
  /// **'Rename device'**
  String get devicesRenameTitle;

  /// Cancel button on Devices dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get devicesCancel;

  /// Save button on Devices dialogs
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get devicesSave;

  /// Banner shown when renaming a device fails
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String devicesRenameFailed(Object error);

  /// Title of the remove-device confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Remove device?'**
  String get devicesRemoveTitle;

  /// Remove dialog body when removing the current device
  ///
  /// In en, this message translates to:
  /// **'This is the device you\'re using. Removing it wipes the per-device preference overrides; the device stays signed in.'**
  String get devicesRemoveBodyCurrent;

  /// Remove dialog body when removing another device
  ///
  /// In en, this message translates to:
  /// **'Removes the device entry and any per-device preference overrides. The device stays signed in until it next opens the app.'**
  String get devicesRemoveBodyOther;

  /// Confirm button and popup-menu item to remove a device
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get devicesRemove;

  /// Banner shown when removing a device fails
  ///
  /// In en, this message translates to:
  /// **'Remove failed: {error}'**
  String devicesRemoveFailed(Object error);

  /// Banner shown when saving device overrides fails
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String devicesSaveFailed(Object error);

  /// Error-state message when the device list fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load devices.'**
  String get devicesLoadError;

  /// Empty-state text when there are no registered devices
  ///
  /// In en, this message translates to:
  /// **'No devices yet — they\'re registered the first time a device opens the app while signed in.'**
  String get devicesEmpty;

  /// Badge marking the current device
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get devicesThisDevice;

  /// Subtitle showing when a device was last active
  ///
  /// In en, this message translates to:
  /// **'Last seen {time}'**
  String devicesLastSeen(String time);

  /// Suffix showing the number of per-device overrides
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} override} other{{count} overrides}}'**
  String devicesOverrideCount(int count);

  /// Relative-time label for an event less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get devicesJustNow;

  /// Relative-time label in minutes
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String devicesMinutesAgo(int minutes);

  /// Relative-time label in hours
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String devicesHoursAgo(int hours);

  /// Relative-time label in days
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String devicesDaysAgo(int days);

  /// Popup-menu item to rename a device
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get devicesRename;

  /// Popup-menu item to edit a device's overrides
  ///
  /// In en, this message translates to:
  /// **'Edit overrides…'**
  String get devicesEditOverrides;

  /// Banner shown when no more override keys are available to add
  ///
  /// In en, this message translates to:
  /// **'Every overridable key is already set; remove one before adding another.'**
  String get devicesEveryKeySet;

  /// Title of the overrides bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Per-device overrides'**
  String get devicesOverridesSheetTitle;

  /// Description on the overrides bottom sheet
  ///
  /// In en, this message translates to:
  /// **'These keys override the universal settings on this device only.'**
  String get devicesOverridesSheetDesc;

  /// Empty-state text in the overrides sheet
  ///
  /// In en, this message translates to:
  /// **'No overrides on this device.'**
  String get devicesNoOverrides;

  /// Button to add a per-device override
  ///
  /// In en, this message translates to:
  /// **'Add override'**
  String get devicesAddOverride;

  /// Title of the key-picker step in the add-override sheet
  ///
  /// In en, this message translates to:
  /// **'Pick a key'**
  String get devicesPickKey;

  /// Validation error for an integer override value
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number.'**
  String get devicesEnterWholeNumber;

  /// Validation error for a decimal override value
  ///
  /// In en, this message translates to:
  /// **'Enter a number (e.g. 0.8).'**
  String get devicesEnterNumber;

  /// Label for the override value field
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get devicesValue;

  /// Back button in the add-override sheet
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get devicesBack;

  /// Confirm button in the add-override sheet
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get devicesAdd;

  /// Override key label: preferred unit
  ///
  /// In en, this message translates to:
  /// **'Preferred unit'**
  String get devicesKeyPreferredUnitLabel;

  /// Override key hint: preferred unit
  ///
  /// In en, this message translates to:
  /// **'Distance unit for all displays.'**
  String get devicesKeyPreferredUnitHint;

  /// Override key label: default activity type
  ///
  /// In en, this message translates to:
  /// **'Default activity type'**
  String get devicesKeyDefaultActivityLabel;

  /// Override key hint: default activity type
  ///
  /// In en, this message translates to:
  /// **'Pre-selected activity on the start screen.'**
  String get devicesKeyDefaultActivityHint;

  /// Override key label: map style
  ///
  /// In en, this message translates to:
  /// **'Map style'**
  String get devicesKeyMapStyleLabel;

  /// Override key hint: map style
  ///
  /// In en, this message translates to:
  /// **'MapLibre style for the map view.'**
  String get devicesKeyMapStyleHint;

  /// Override key label: pace format
  ///
  /// In en, this message translates to:
  /// **'Pace format'**
  String get devicesKeyPaceFormatLabel;

  /// Override key hint: pace format
  ///
  /// In en, this message translates to:
  /// **'Display format for pace.'**
  String get devicesKeyPaceFormatHint;

  /// Override key label: voice feedback
  ///
  /// In en, this message translates to:
  /// **'Voice feedback'**
  String get devicesKeyVoiceFeedbackLabel;

  /// Override key hint: voice feedback
  ///
  /// In en, this message translates to:
  /// **'Speak pace / distance callouts during a run.'**
  String get devicesKeyVoiceFeedbackHint;

  /// Override key label: voice feedback interval
  ///
  /// In en, this message translates to:
  /// **'Voice feedback interval (km)'**
  String get devicesKeyVoiceIntervalLabel;

  /// Override key hint: voice feedback interval
  ///
  /// In en, this message translates to:
  /// **'Distance between spoken callouts.'**
  String get devicesKeyVoiceIntervalHint;

  /// Override key label: haptic feedback
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get devicesKeyHapticLabel;

  /// Override key hint: haptic feedback
  ///
  /// In en, this message translates to:
  /// **'Vibration on lap + pace-zone changes.'**
  String get devicesKeyHapticHint;

  /// Override key label: keep screen on
  ///
  /// In en, this message translates to:
  /// **'Keep screen on'**
  String get devicesKeyKeepScreenOnLabel;

  /// Override key hint: keep screen on
  ///
  /// In en, this message translates to:
  /// **'Disable OS auto-dim while recording.'**
  String get devicesKeyKeepScreenOnHint;

  /// AppBar title for the Settings > Gear screen
  ///
  /// In en, this message translates to:
  /// **'Gear'**
  String get gearTitle;

  /// Tooltip and button label to add gear
  ///
  /// In en, this message translates to:
  /// **'Add gear'**
  String get gearAddGear;

  /// Title of the delete-gear confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete gear?'**
  String get gearDeleteTitle;

  /// Body of the delete-gear confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Mileage history on past runs will be lost. Retire instead to keep the records.'**
  String gearDeleteBody(String name);

  /// Cancel button on Gear dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gearCancel;

  /// Delete button and popup-menu item on the Gear screen
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gearDelete;

  /// Banner shown after deleting gear while offline
  ///
  /// In en, this message translates to:
  /// **'Deleted locally — will sync when you reconnect.'**
  String get gearDeletedOffline;

  /// Banner shown after backfilling gear onto past runs
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Attached {name} to {count} run.} other{Attached {name} to {count} runs.}}'**
  String gearAttached(String name, int count);

  /// Offline banner when edits are queued
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Offline — {count} edit queued, showing cached gear.} other{Offline — {count} edits queued, showing cached gear.}}'**
  String gearOfflineQueued(int count);

  /// Offline banner when no edits are queued
  ///
  /// In en, this message translates to:
  /// **'Offline — showing cached gear.'**
  String get gearOfflineCached;

  /// Segmented-button label for shoes
  ///
  /// In en, this message translates to:
  /// **'Shoes'**
  String get gearShoes;

  /// Segmented-button label for bikes
  ///
  /// In en, this message translates to:
  /// **'Bikes'**
  String get gearBikes;

  /// Section header for retired gear
  ///
  /// In en, this message translates to:
  /// **'RETIRED'**
  String get gearRetired;

  /// Empty-state title for shoes
  ///
  /// In en, this message translates to:
  /// **'No shoes yet'**
  String get gearEmptyShoes;

  /// Empty-state title for bikes
  ///
  /// In en, this message translates to:
  /// **'No bikes yet'**
  String get gearEmptyBikes;

  /// Empty-state subtitle on the Gear screen
  ///
  /// In en, this message translates to:
  /// **'Add a pair to track mileage and get retirement reminders.'**
  String get gearEmptySubtitle;

  /// Run count shown on a gear tile
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run} other{{count} runs}}'**
  String gearRunCount(int count);

  /// Badge on a gear tile when accrued distance is in the last ~15% of its replacement target
  ///
  /// In en, this message translates to:
  /// **'Replace soon'**
  String get gearWearDue;

  /// Badge on a gear tile when accrued distance has reached or exceeded its replacement target
  ///
  /// In en, this message translates to:
  /// **'Past replacement distance'**
  String get gearWearWorn;

  /// Popup-menu item to retire gear
  ///
  /// In en, this message translates to:
  /// **'Retire'**
  String get gearRetire;

  /// Popup-menu item to un-retire gear
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get gearRestore;

  /// AppBar title + gear-screen action for the gear rotations screen
  ///
  /// In en, this message translates to:
  /// **'Rotations'**
  String get gearRotationsTitle;

  /// Instructional copy on the rotations screen
  ///
  /// In en, this message translates to:
  /// **'Group the gear you cycle through — a \"Daily trainers\" set, a \"Race day\" set. A rotation is just a named grouping; it doesn\'t change which pair auto-tags new runs.'**
  String get gearRotationsHint;

  /// Empty-state copy on the rotations screen
  ///
  /// In en, this message translates to:
  /// **'No rotations yet. Create one to group a set of shoes or bikes.'**
  String get gearRotationsEmpty;

  /// Label/hint for the rotation-name field
  ///
  /// In en, this message translates to:
  /// **'Rotation name'**
  String get gearRotationName;

  /// Tooltip/label to create a rotation
  ///
  /// In en, this message translates to:
  /// **'New rotation'**
  String get gearRotationNew;

  /// Button to create a rotation
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get gearRotationCreate;

  /// Popup-menu item to rename a rotation
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get gearRotationRename;

  /// Popup-menu item / button to edit a rotation's gear members
  ///
  /// In en, this message translates to:
  /// **'Edit gear'**
  String get gearRotationManage;

  /// Title of the rotation member-edit sheet
  ///
  /// In en, this message translates to:
  /// **'Gear in \"{name}\"'**
  String gearRotationManageTitle(String name);

  /// Title of the delete-rotation confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete rotation?'**
  String get gearRotationDeleteTitle;

  /// Body of the delete-rotation confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete the \"{name}\" rotation? Your gear isn\'t affected — only the grouping is removed.'**
  String gearRotationDeleteBody(String name);

  /// Member count chip on a rotation row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} item} other{{count} items}}'**
  String gearRotationMemberCount(int count);

  /// Shown in the member-edit sheet when the user has no gear
  ///
  /// In en, this message translates to:
  /// **'Add some gear first, then you can group it into a rotation.'**
  String get gearRotationNoGear;

  /// Banner shown when a rotation operation fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save rotation: {error}'**
  String gearRotationSaveFailed(Object error);

  /// Save/confirm button in the rotation member-edit sheet
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get gearRotationDone;

  /// AppBar title for the Settings > Privacy zones screen
  ///
  /// In en, this message translates to:
  /// **'Privacy zones'**
  String get privacyZonesTitle;

  /// Banner shown after saving privacy zones
  ///
  /// In en, this message translates to:
  /// **'Privacy zones saved.'**
  String get privacyZonesSaved;

  /// Banner shown when saving privacy zones fails
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String privacyZonesSaveFailed(Object error);

  /// Banner shown when the Locate FAB can't get a fix
  ///
  /// In en, this message translates to:
  /// **'Location unavailable: {error}'**
  String privacyZonesLocationUnavailable(Object error);

  /// Save button in the AppBar
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get privacyZonesSave;

  /// Tooltip on the Locate FAB
  ///
  /// In en, this message translates to:
  /// **'Locate me'**
  String get privacyZonesLocateMe;

  /// Instructional copy above the privacy-zones map
  ///
  /// In en, this message translates to:
  /// **'Tap the map to add a zone. Tracks on public surfaces have their start and end clipped past the zone radius.'**
  String get privacyZonesHint;

  /// Hint text in the place-search field
  ///
  /// In en, this message translates to:
  /// **'Search places…'**
  String get privacyZonesSearchHint;

  /// Label for the zone-radius slider
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get privacyZonesRadius;

  /// Radius value in metres
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String privacyZonesRadiusMeters(int meters);

  /// Footer summarising the number of zones
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} zone — tap a marker to remove.} other{{count} zones — tap a marker to remove.}}'**
  String privacyZonesCount(int count);

  /// Button to remove all privacy zones
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get privacyZonesClearAll;

  /// No description provided for @privacyZonesRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove privacy zone?'**
  String get privacyZonesRemoveTitle;

  /// No description provided for @privacyZonesRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'This zone hides your tracks near here on public shares. Removing it re-exposes this area.'**
  String get privacyZonesRemoveBody;

  /// No description provided for @privacyZonesRemoveSemantics.
  ///
  /// In en, this message translates to:
  /// **'Remove privacy zone'**
  String get privacyZonesRemoveSemantics;

  /// No description provided for @privacyZonesClearAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all privacy zones?'**
  String get privacyZonesClearAllTitle;

  /// No description provided for @privacyZonesClearAllBody.
  ///
  /// In en, this message translates to:
  /// **'This removes every zone, re-exposing all of these areas on public shares.'**
  String get privacyZonesClearAllBody;

  /// AppBar title for the Settings > Preferences screen
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get prefsTitle;

  /// Unit subtitle when kilometres are selected
  ///
  /// In en, this message translates to:
  /// **'km, m'**
  String get prefsUnitMetric;

  /// Unit subtitle when miles are selected
  ///
  /// In en, this message translates to:
  /// **'mi, ft'**
  String get prefsUnitImperial;

  /// Unit subtitle with a note that the setting syncs across devices
  ///
  /// In en, this message translates to:
  /// **'{base} · synced to your other devices'**
  String prefsSyncedSuffix(String base);

  /// Clear button in Preferences dialogs
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get prefsClear;

  /// Cancel button in Preferences dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get prefsCancel;

  /// Save button in Preferences dialogs
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get prefsSave;

  /// Tile and dialog title for the split interval
  ///
  /// In en, this message translates to:
  /// **'Split interval'**
  String get prefsSplitInterval;

  /// Split-interval option meaning the app default
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get prefsSplitIntervalDefault;

  /// Subtitle shown when the split interval is at its default
  ///
  /// In en, this message translates to:
  /// **'Default (1 km for running, 5 km for cycling)'**
  String get prefsSplitIntervalDefaultSubtitle;

  /// Tile and dialog title for the live pace alert
  ///
  /// In en, this message translates to:
  /// **'Live pace alert'**
  String get prefsLivePaceAlert;

  /// Minutes field label in the live-pace-alert dialog
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get prefsLivePaceAlertMin;

  /// Seconds field label in the live-pace-alert dialog
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get prefsLivePaceAlertSec;

  /// Live-pace-alert subtitle when no target pace is set
  ///
  /// In en, this message translates to:
  /// **'Off — set a pace to get spoken alerts during a run'**
  String get prefsLivePaceAlertOff;

  /// Live-pace-alert subtitle showing the target pace
  ///
  /// In en, this message translates to:
  /// **'{pace} {paceLabel} — spoken alert during a run when 30s+ off'**
  String prefsLivePaceAlertOn(String pace, String paceLabel);

  /// Activity-type label: run
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get prefsActivityRun;

  /// Activity-type label: walk
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get prefsActivityWalk;

  /// Activity-type label: hike
  ///
  /// In en, this message translates to:
  /// **'Hike'**
  String get prefsActivityHike;

  /// Activity-type label: cycle
  ///
  /// In en, this message translates to:
  /// **'Cycle'**
  String get prefsActivityCycle;

  /// Tile and picker title for the pace format
  ///
  /// In en, this message translates to:
  /// **'Pace format'**
  String get prefsPaceFormat;

  /// Pace-format option: minutes per kilometre
  ///
  /// In en, this message translates to:
  /// **'Minutes per km'**
  String get prefsPaceFormatMinPerKm;

  /// Pace-format option: minutes per mile
  ///
  /// In en, this message translates to:
  /// **'Minutes per mile'**
  String get prefsPaceFormatMinPerMi;

  /// Pace-format option: kilometres per hour
  ///
  /// In en, this message translates to:
  /// **'km/h'**
  String get prefsPaceFormatKph;

  /// Pace-format option: miles per hour
  ///
  /// In en, this message translates to:
  /// **'mph'**
  String get prefsPaceFormatMph;

  /// Tile and picker title for the body/lift weight unit
  ///
  /// In en, this message translates to:
  /// **'Weight unit'**
  String get prefsWeightUnit;

  /// Weight-unit option: kilograms
  ///
  /// In en, this message translates to:
  /// **'Kilograms (kg)'**
  String get prefsWeightUnitKg;

  /// Weight-unit option: pounds
  ///
  /// In en, this message translates to:
  /// **'Pounds (lbs)'**
  String get prefsWeightUnitLbs;

  /// Placeholder shown when a setting has no value
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get prefsNotSet;

  /// HR-zones summary showing the upper bounds in bpm
  ///
  /// In en, this message translates to:
  /// **'{zones} bpm'**
  String prefsHrZonesSummary(String zones);

  /// Weekly-goal summary showing the target distance per week
  ///
  /// In en, this message translates to:
  /// **'{distance} {unit} / week'**
  String prefsWeeklyGoalSummary(String distance, String unit);

  /// Tile and picker title for the map style
  ///
  /// In en, this message translates to:
  /// **'Map style'**
  String get prefsMapStyle;

  /// Map-style option: streets
  ///
  /// In en, this message translates to:
  /// **'Streets'**
  String get prefsMapStyleStreets;

  /// Map-style option: satellite
  ///
  /// In en, this message translates to:
  /// **'Satellite'**
  String get prefsMapStyleSatellite;

  /// Map-style option: outdoors
  ///
  /// In en, this message translates to:
  /// **'Outdoors'**
  String get prefsMapStyleOutdoors;

  /// Map-style option: dark
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get prefsMapStyleDark;

  /// Picker title for the default run visibility
  ///
  /// In en, this message translates to:
  /// **'Default run visibility'**
  String get prefsDefaultRunVisibility;

  /// Tile and picker title for the coach personality
  ///
  /// In en, this message translates to:
  /// **'Coach personality'**
  String get prefsCoachPersonality;

  /// Coach-personality option: supportive
  ///
  /// In en, this message translates to:
  /// **'Supportive'**
  String get prefsCoachSupportive;

  /// Coach-personality option: drill sergeant
  ///
  /// In en, this message translates to:
  /// **'Drill sergeant'**
  String get prefsCoachDrillSergeant;

  /// Coach-personality option: analytical
  ///
  /// In en, this message translates to:
  /// **'Analytical'**
  String get prefsCoachAnalytical;

  /// Settings section label for notification preferences
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get prefsSectionNotifications;

  /// Tile and picker title for the email-notification preference
  ///
  /// In en, this message translates to:
  /// **'Email notifications'**
  String get prefsEmailNotifications;

  /// Email-notification option: send every kind of notification by email
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get prefsEmailNotifAll;

  /// Email-notification option: only important notifications (reminders, cancellations, messages, plan updates)
  ///
  /// In en, this message translates to:
  /// **'Important only'**
  String get prefsEmailNotifImportant;

  /// Email-notification option: no emails (in-app bell still shows everything)
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get prefsEmailNotifOff;

  /// Tile and picker title for the push-notification preference
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get prefsPushNotifications;

  /// Push-notification option: send every kind of notification as a push alert
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get prefsPushNotifAll;

  /// Push-notification option: only important notifications (reminders, cancellations, messages, plan updates)
  ///
  /// In en, this message translates to:
  /// **'Important only'**
  String get prefsPushNotifImportant;

  /// Push-notification option: no push alerts (in-app bell still shows everything)
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get prefsPushNotifOff;

  /// Toggle title for opting in to the weekly engagement digest email
  ///
  /// In en, this message translates to:
  /// **'Weekly digest email'**
  String get prefsEmailWeeklyDigest;

  /// Subtitle for the weekly-digest opt-in toggle
  ///
  /// In en, this message translates to:
  /// **'Opt in to a weekly summary of your training and community highlights. Off by default; separate from your notification emails.'**
  String get prefsEmailWeeklyDigestHint;

  /// Toggle title for opting in to the lifecycle-drip engagement email
  ///
  /// In en, this message translates to:
  /// **'Tips & encouragement email'**
  String get prefsEmailLifecycleDrip;

  /// Subtitle for the lifecycle-drip opt-in toggle
  ///
  /// In en, this message translates to:
  /// **'Opt in to occasional onboarding, re-engagement, and streak nudges. Off by default; separate from your weekly digest and notification emails.'**
  String get prefsEmailLifecycleDripHint;

  /// Tile and picker title for the week-start day
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get prefsWeekStart;

  /// Week-start option: Monday
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get prefsWeekStartMonday;

  /// Week-start option: Sunday
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get prefsWeekStartSunday;

  /// Tile and picker title for the default activity
  ///
  /// In en, this message translates to:
  /// **'Default activity'**
  String get prefsDefaultActivity;

  /// Tile title and date-picker help text for date of birth
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get prefsDateOfBirth;

  /// Tile and dialog title for resting heart rate
  ///
  /// In en, this message translates to:
  /// **'Resting heart rate'**
  String get prefsRestingHr;

  /// Tile and dialog title for max heart rate
  ///
  /// In en, this message translates to:
  /// **'Max heart rate'**
  String get prefsMaxHr;

  /// Max-HR subtitle when no value is set
  ///
  /// In en, this message translates to:
  /// **'Not set — falls back to 208 − 0.7 × age'**
  String get prefsMaxHrNotSet;

  /// Heart-rate value with bpm unit
  ///
  /// In en, this message translates to:
  /// **'{bpm} bpm'**
  String prefsHrBpm(int bpm);

  /// Settings section header for race-fueling intake rates
  ///
  /// In en, this message translates to:
  /// **'Race fueling'**
  String get prefsSectionFueling;

  /// Tile and dialog title for the race-fueling carbohydrate rate
  ///
  /// In en, this message translates to:
  /// **'Carbs per hour'**
  String get prefsCarbsPerHour;

  /// Carbohydrate intake rate value with unit
  ///
  /// In en, this message translates to:
  /// **'{grams} g/h'**
  String prefsCarbsPerHourValue(int grams);

  /// Tile and dialog title for the race-fueling fluid rate
  ///
  /// In en, this message translates to:
  /// **'Fluid per hour'**
  String get prefsFluidPerHour;

  /// Fluid intake rate value with unit
  ///
  /// In en, this message translates to:
  /// **'{ml} ml/h'**
  String prefsFluidPerHourValue(int ml);

  /// Tile title for heart-rate zones
  ///
  /// In en, this message translates to:
  /// **'Heart-rate zones'**
  String get prefsHrZones;

  /// Dialog title for editing heart-rate zones
  ///
  /// In en, this message translates to:
  /// **'Heart-rate zones (upper bounds, bpm)'**
  String get prefsHrZonesDialogTitle;

  /// Tile and dialog title for the weekly mileage goal
  ///
  /// In en, this message translates to:
  /// **'Weekly mileage goal'**
  String get prefsWeeklyGoal;

  /// Section header for activity and recording settings
  ///
  /// In en, this message translates to:
  /// **'Activity & recording'**
  String get prefsSectionActivityRecording;

  /// Section header for training and demographics settings
  ///
  /// In en, this message translates to:
  /// **'Training & demographics'**
  String get prefsSectionTrainingDemographics;

  /// Section header for privacy and sharing settings
  ///
  /// In en, this message translates to:
  /// **'Privacy & sharing'**
  String get prefsSectionPrivacySharing;

  /// Section header for AI coach settings
  ///
  /// In en, this message translates to:
  /// **'AI coach'**
  String get prefsSectionAiCoach;

  /// Notice shown when the bag-backed settings are not yet available
  ///
  /// In en, this message translates to:
  /// **'Sign in to edit profile-level settings that sync across devices.'**
  String get prefsSignInToEdit;

  /// Toggle title for using miles instead of kilometres
  ///
  /// In en, this message translates to:
  /// **'Use miles'**
  String get prefsUseMiles;

  /// Toggle title for dark mode
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get prefsDarkMode;

  /// Toggle title for spoken audio cues
  ///
  /// In en, this message translates to:
  /// **'Audio cues'**
  String get prefsAudioCues;

  /// Subtitle of the audio-cues toggle
  ///
  /// In en, this message translates to:
  /// **'Spoken split announcements'**
  String get prefsAudioCuesSubtitle;

  /// Toggle title for minimal voice cues
  ///
  /// In en, this message translates to:
  /// **'Minimal voice cues'**
  String get prefsMinimalVoiceCues;

  /// Subtitle of the minimal-voice-cues toggle
  ///
  /// In en, this message translates to:
  /// **'Skip the chatty mid-rep and pace-drift nudges'**
  String get prefsMinimalVoiceCuesSubtitle;

  /// Toggle title for keeping the screen on during a run
  ///
  /// In en, this message translates to:
  /// **'Keep screen on'**
  String get prefsKeepScreenOn;

  /// Subtitle of the keep-screen-on toggle
  ///
  /// In en, this message translates to:
  /// **'Hold a wakelock during a run'**
  String get prefsKeepScreenOnSubtitle;

  /// Toggle title for advanced GPS
  ///
  /// In en, this message translates to:
  /// **'Advanced GPS'**
  String get prefsAdvancedGps;

  /// Subtitle of the advanced-GPS toggle
  ///
  /// In en, this message translates to:
  /// **'Higher accuracy, finer track detail, more battery usage'**
  String get prefsAdvancedGpsSubtitle;

  /// Toggle title for forcing the raw GPS track on the run map instead of the map-matched line
  ///
  /// In en, this message translates to:
  /// **'Show raw GPS track'**
  String get prefsShowRawTrack;

  /// Subtitle of the show-raw-track toggle
  ///
  /// In en, this message translates to:
  /// **'Draw the unsnapped recorded line on the run map, even when a cleaned-up matched track exists'**
  String get prefsShowRawTrackSubtitle;

  /// Toggle title for showing the calorie estimate on run detail
  ///
  /// In en, this message translates to:
  /// **'Show calorie estimates'**
  String get prefsShowCalories;

  /// Subtitle of the show-calories toggle
  ///
  /// In en, this message translates to:
  /// **'Estimated from distance and body weight (a 70 kg default when unset). Turn off to hide the calorie figure on run pages.'**
  String get prefsShowCaloriesHint;

  /// Tile title for the default run privacy
  ///
  /// In en, this message translates to:
  /// **'Default run privacy'**
  String get prefsDefaultRunPrivacy;

  /// Toggle title for Strava auto-share
  ///
  /// In en, this message translates to:
  /// **'Strava auto-share'**
  String get prefsStravaAutoShare;

  /// Subtitle of the Strava auto-share toggle
  ///
  /// In en, this message translates to:
  /// **'Auto-push every new run to Strava. Requires a connected Strava integration once that lands.'**
  String get prefsStravaAutoShareSubtitle;

  /// Toggle title for being discoverable in name search
  ///
  /// In en, this message translates to:
  /// **'Show me in name search'**
  String get prefsDiscoverable;

  /// Subtitle of the discoverable-in-search toggle
  ///
  /// In en, this message translates to:
  /// **'When off, your account won\'t appear when other runners search by display name. Your public runs and profile remain reachable to anyone with the URL.'**
  String get prefsDiscoverableSubtitle;

  /// Dashboard toolbar tooltip for the AI Coach action
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get dashboardCoachTooltip;

  /// Dashboard toolbar tooltip for the activity-feed action
  ///
  /// In en, this message translates to:
  /// **'Activity feed'**
  String get dashboardFeedTooltip;

  /// Dashboard toolbar tooltip for the year-in-running recap action
  ///
  /// In en, this message translates to:
  /// **'Year in running'**
  String get dashboardRecapTooltip;

  /// Dashboard toolbar tooltip for opening the user's own profile
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get dashboardProfileTooltip;

  /// Dashboard empty-state welcome headline
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get dashboardWelcomeTitle;

  /// Dashboard empty-state explanatory body
  ///
  /// In en, this message translates to:
  /// **'Your dashboard fills in once you record a run, set a goal, or import your history.'**
  String get dashboardWelcomeBody;

  /// Dashboard empty-state primary button to create a goal
  ///
  /// In en, this message translates to:
  /// **'Set a goal'**
  String get dashboardSetGoal;

  /// Dashboard empty-state secondary button to bulk-import runs
  ///
  /// In en, this message translates to:
  /// **'Import runs'**
  String get dashboardImportRuns;

  /// Label for the weekly period stat card on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get dashboardPeriodWeek;

  /// Label for the monthly period stat card on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get dashboardPeriodMonth;

  /// Label for the all-time period stat card on the dashboard
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get dashboardPeriodAllTime;

  /// Section header above the run-streak card
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get dashboardSectionStreak;

  /// Title of the dashboard current-calendar-week activity ribbon
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get dashboardWeekStripTitle;

  /// Activity count in the week-strip header
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} activity} other{{count} activities}}'**
  String dashboardWeekStripCount(num count);

  /// Accessibility label for a logged day cell in the week strip
  ///
  /// In en, this message translates to:
  /// **'{dow}: {dist}'**
  String dashboardWeekStripDayAria(String dow, String dist);

  /// Accessibility label for a day cell with no logged activity
  ///
  /// In en, this message translates to:
  /// **'{dow}: rest day'**
  String dashboardWeekStripDayRestAria(String dow);

  /// Section header above the 20-week activity heatmap
  ///
  /// In en, this message translates to:
  /// **'Last 20 Weeks'**
  String get dashboardSectionLast20Weeks;

  /// Header of the dashboard recent-lifts trend card
  ///
  /// In en, this message translates to:
  /// **'Recent lifts'**
  String get dashboardSectionRecentLifts;

  /// Link from the recent-lifts card to the full Gym surface
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get dashboardViewAllGym;

  /// Section header above the personal-bests card
  ///
  /// In en, this message translates to:
  /// **'Personal Bests'**
  String get dashboardSectionPersonalBests;

  /// Personal-best row label for the longest single run
  ///
  /// In en, this message translates to:
  /// **'Longest run'**
  String get dashboardLongestRun;

  /// Personal-best row label for the fastest effort at a named distance
  ///
  /// In en, this message translates to:
  /// **'Fastest {distance}'**
  String dashboardFastestDistance(String distance);

  /// Section header above the goals list
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get dashboardGoals;

  /// Button label to add a new goal from the goals section header
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get dashboardAdd;

  /// Uppercase period badge on a weekly goal card
  ///
  /// In en, this message translates to:
  /// **'WEEKLY'**
  String get dashboardGoalWeekly;

  /// Uppercase period badge on a monthly goal card
  ///
  /// In en, this message translates to:
  /// **'MONTHLY'**
  String get dashboardGoalMonthly;

  /// Fallback goal-card title when no custom title is set, e.g. WEEKLY GOAL
  ///
  /// In en, this message translates to:
  /// **'{period} GOAL'**
  String dashboardGoalTitleFallback(String period);

  /// Accessibility label for the empty-goals call-to-action card
  ///
  /// In en, this message translates to:
  /// **'Set a weekly running goal'**
  String get dashboardSetWeeklyGoalA11y;

  /// Title of the empty-goals call-to-action card
  ///
  /// In en, this message translates to:
  /// **'Set your first goal'**
  String get dashboardSetFirstGoal;

  /// Body of the empty-goals call-to-action card
  ///
  /// In en, this message translates to:
  /// **'Track distance, time, pace, or number of runs each week or month.'**
  String get dashboardSetFirstGoalBody;

  /// Accessibility fragment used when a goal card has no custom title
  ///
  /// In en, this message translates to:
  /// **'tap to edit'**
  String get dashboardGoalTapToEdit;

  /// Accessibility fragment when a goal is complete
  ///
  /// In en, this message translates to:
  /// **'Complete.'**
  String get dashboardGoalComplete;

  /// Accessibility fragment when a goal is still in progress
  ///
  /// In en, this message translates to:
  /// **'In progress.'**
  String get dashboardGoalInProgress;

  /// Accessibility label for a goal card, combining period badge, title fragment and status fragment
  ///
  /// In en, this message translates to:
  /// **'{period} goal — {title} {status}'**
  String dashboardGoalA11y(String period, String title, String status);

  /// Run-count line under a period stat card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run} other{{count} runs}}'**
  String dashboardRunCount(int count);

  /// Elevation-gain line under a period stat card; value is pre-formatted with the user's unit
  ///
  /// In en, this message translates to:
  /// **'{value} vert'**
  String dashboardVert(String value);

  /// Accessibility label for a tappable period stat card; distance, runs and elevation are pre-formatted strings
  ///
  /// In en, this message translates to:
  /// **'{label} summary, {distance} across {runs}{elevation}'**
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  );

  /// Optional elevation-gain clause appended to the period-summary accessibility label; value is pre-formatted
  ///
  /// In en, this message translates to:
  /// **', {value} elevation gain'**
  String dashboardElevationGainSuffix(String value);

  /// Caption under the current run-streak figure
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get dashboardStreakCurrent;

  /// Caption under the best/history run-streak figure
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get dashboardStreakHistory;

  /// Singular day unit beside the current streak count
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get dashboardStreakDayUnit;

  /// Plural days unit beside the current streak count
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get dashboardStreakDaysUnit;

  /// Best run-streak readout when the best exceeds the current
  ///
  /// In en, this message translates to:
  /// **'best {count, plural, one{{count} day} other{{count} days}}'**
  String dashboardStreakBest(int count);

  /// Run-streak readout when the current streak is also the best
  ///
  /// In en, this message translates to:
  /// **'all-time best'**
  String get dashboardStreakAllTimeBest;

  /// Encouraging run-streak readout when there is a prior streak but none current
  ///
  /// In en, this message translates to:
  /// **'run today to restart it'**
  String get dashboardStreakRestart;

  /// Encouraging run-streak readout when the user has never had a streak
  ///
  /// In en, this message translates to:
  /// **'run today to start one'**
  String get dashboardStreakStart;

  /// Low-intensity end label of the activity-heatmap legend
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get dashboardHeatmapLess;

  /// High-intensity end label of the activity-heatmap legend
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get dashboardHeatmapMore;

  /// Hint under the tappable activity heatmap
  ///
  /// In en, this message translates to:
  /// **'Tap a week for its summary'**
  String get dashboardHeatmapTapHint;

  /// App bar title for the weekly period summary
  ///
  /// In en, this message translates to:
  /// **'Weekly Summary'**
  String get periodWeeklySummary;

  /// App bar title for the monthly period summary
  ///
  /// In en, this message translates to:
  /// **'Monthly Summary'**
  String get periodMonthlySummary;

  /// App bar title for the all-time period summary
  ///
  /// In en, this message translates to:
  /// **'All-Time Summary'**
  String get periodAllTimeSummary;

  /// Tooltip for the share action on the period summary
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get periodShareTooltip;

  /// Tooltip for the previous-period navigation arrow
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get periodPreviousTooltip;

  /// Tooltip for the next-period navigation arrow
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get periodNextTooltip;

  /// Hint under the period title to switch to the weekly view
  ///
  /// In en, this message translates to:
  /// **'Tap to switch to weekly'**
  String get periodSwitchToWeekly;

  /// Hint under the period title to switch to the monthly view
  ///
  /// In en, this message translates to:
  /// **'Tap to switch to monthly'**
  String get periodSwitchToMonthly;

  /// Hint under the period title to switch to the all-time view
  ///
  /// In en, this message translates to:
  /// **'Tap to switch to all-time'**
  String get periodSwitchToAllTime;

  /// Stat label for total distance on the period summary
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get periodStatDistance;

  /// Stat label for the run count on the period summary
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get periodStatRuns;

  /// Stat label for total time on the period summary
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get periodStatTime;

  /// Stat label for average pace on the period summary
  ///
  /// In en, this message translates to:
  /// **'Avg pace'**
  String get periodStatAvgPace;

  /// Empty-state text for a week with no runs
  ///
  /// In en, this message translates to:
  /// **'No runs this week'**
  String get periodEmptyWeek;

  /// Empty-state text for a month with no runs
  ///
  /// In en, this message translates to:
  /// **'No runs this month'**
  String get periodEmptyMonth;

  /// Title of the period share bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Share summary'**
  String get periodShareSummary;

  /// Button to share the period summary as plain text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get periodShareText;

  /// Button to share the period summary as an image
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get periodShareImage;

  /// Error banner when the period share image cannot be captured
  ///
  /// In en, this message translates to:
  /// **'Could not create share image'**
  String get periodShareImageFailed;

  /// Tagline footer on the shareable period summary card
  ///
  /// In en, this message translates to:
  /// **'BETTER RUNNER'**
  String get periodShareCardTagline;

  /// Uppercase distance label on the shareable period card
  ///
  /// In en, this message translates to:
  /// **'DISTANCE'**
  String get periodShareStatDistance;

  /// Uppercase runs label on the shareable period card
  ///
  /// In en, this message translates to:
  /// **'RUNS'**
  String get periodShareStatRuns;

  /// Uppercase time label on the shareable period card
  ///
  /// In en, this message translates to:
  /// **'TIME'**
  String get periodShareStatTime;

  /// Uppercase average-pace label on the shareable period card
  ///
  /// In en, this message translates to:
  /// **'AVG PACE'**
  String get periodShareStatAvgPace;

  /// Title of the training-load chart card
  ///
  /// In en, this message translates to:
  /// **'Fitness, Fatigue & Form'**
  String get trainingLoadTitle;

  /// Training-load subtitle when HR-based TRIMP is available
  ///
  /// In en, this message translates to:
  /// **'Heart-rate TRIMP over the last {days} days.'**
  String trainingLoadSubtitleHr(int days);

  /// Training-load subtitle when only volume-based load is available
  ///
  /// In en, this message translates to:
  /// **'Volume-based — set resting + max HR in preferences and record with a strap to upgrade to TRIMP.'**
  String get trainingLoadSubtitleVolume;

  /// Empty-state text for the training-load chart
  ///
  /// In en, this message translates to:
  /// **'Record a few runs to see your fitness trend.'**
  String get trainingLoadEmpty;

  /// Legend label for the CTL (fitness) series
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get trainingLoadLegendFitness;

  /// Legend label for the ATL (fatigue) series
  ///
  /// In en, this message translates to:
  /// **'Fatigue'**
  String get trainingLoadLegendFatigue;

  /// Legend label for the TSB (form) series
  ///
  /// In en, this message translates to:
  /// **'Form'**
  String get trainingLoadLegendForm;

  /// Legend entry combining a series label and its rounded value
  ///
  /// In en, this message translates to:
  /// **'{label} · {value}'**
  String trainingLoadLegendEntry(String label, int value);

  /// Training-load reading when form (TSB) is strongly negative
  ///
  /// In en, this message translates to:
  /// **'Loaded up — push through and recover when you\'re ready.'**
  String get trainingLoadReadingLoaded;

  /// Training-load reading when form (TSB) is strongly positive
  ///
  /// In en, this message translates to:
  /// **'Tapered — a hard session won\'t break you.'**
  String get trainingLoadReadingTapered;

  /// Training-load reading when form (TSB) is near zero
  ///
  /// In en, this message translates to:
  /// **'Balanced — easy day or hard day, your call.'**
  String get trainingLoadReadingBalanced;

  /// Hint on the fitness/fatigue/form chart when logged gym sessions contribute to the load curve
  ///
  /// In en, this message translates to:
  /// **'Gym sessions included — lifts add to fatigue too.'**
  String get trainingLoadIncludesLifts;

  /// Title of the dashboard training-intensity card
  ///
  /// In en, this message translates to:
  /// **'TRAINING INTENSITY'**
  String get intensityTitle;

  /// Window caption on the intensity card
  ///
  /// In en, this message translates to:
  /// **'last {days} days'**
  String intensityWindow(int days);

  /// Caption stating how many HR-tracked runs the intensity breakdown is based on
  ///
  /// In en, this message translates to:
  /// **'Based on {count, plural, one{{count} HR-tracked run} other{{count} HR-tracked runs}}'**
  String intensityBasedOn(int count);

  /// Title of the dashboard mileage card
  ///
  /// In en, this message translates to:
  /// **'MILEAGE'**
  String get mileageTitle;

  /// Weekly segment label on the mileage view toggle
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get mileageWeek;

  /// Monthly segment label on the mileage view toggle
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get mileageMonth;

  /// Yearly segment label on the mileage view toggle
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get mileageYear;

  /// Suffix on the mileage spotlight headline in weekly view
  ///
  /// In en, this message translates to:
  /// **'this week'**
  String get mileageThisWeek;

  /// Suffix on the mileage spotlight headline in monthly view
  ///
  /// In en, this message translates to:
  /// **'this month'**
  String get mileageThisMonth;

  /// Suffix on the mileage spotlight headline in yearly view
  ///
  /// In en, this message translates to:
  /// **'this year'**
  String get mileageThisYear;

  /// Title of the dashboard fitness card
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get fitnessTitle;

  /// Fitness card stat label for VO2 max
  ///
  /// In en, this message translates to:
  /// **'VO₂ max'**
  String get fitnessStatVo2Max;

  /// Tooltip explaining VO2 max
  ///
  /// In en, this message translates to:
  /// **'Your aerobic engine: how much oxygen your body can use per minute. Higher is fitter.'**
  String get fitnessStatVo2MaxTooltip;

  /// Fitness card stat label for VDOT
  ///
  /// In en, this message translates to:
  /// **'VDOT'**
  String get fitnessStatVdot;

  /// Tooltip explaining VDOT
  ///
  /// In en, this message translates to:
  /// **'Daniels\' running-fitness score from your best recent race effort. Drives your training paces.'**
  String get fitnessStatVdotTooltip;

  /// Fitness card stat label for the qualifying run count
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get fitnessStatRuns;

  /// Tooltip explaining the qualifying run count
  ///
  /// In en, this message translates to:
  /// **'Recent runs long enough to count toward your fitness estimate.'**
  String get fitnessStatRunsTooltip;

  /// Fitness card stat label for CTL (chronic training load)
  ///
  /// In en, this message translates to:
  /// **'Fitness (CTL)'**
  String get fitnessStatCtl;

  /// Tooltip explaining CTL
  ///
  /// In en, this message translates to:
  /// **'Your rolling 42-day training load. Builds slowly; this is your endurance base.'**
  String get fitnessStatCtlTooltip;

  /// Fitness card stat label for ATL (acute training load)
  ///
  /// In en, this message translates to:
  /// **'Fatigue (ATL)'**
  String get fitnessStatAtl;

  /// Tooltip explaining ATL
  ///
  /// In en, this message translates to:
  /// **'Your last 7 days of load. Rises fast after hard sessions and drops with rest.'**
  String get fitnessStatAtlTooltip;

  /// Fitness card stat label for TSB (training stress balance)
  ///
  /// In en, this message translates to:
  /// **'Form (TSB)'**
  String get fitnessStatTsb;

  /// Tooltip explaining TSB
  ///
  /// In en, this message translates to:
  /// **'Fitness minus fatigue. Positive = fresh and race-ready; negative = carrying fatigue.'**
  String get fitnessStatTsbTooltip;

  /// Section header above the kudos + comments on a run
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get runSocialActivity;

  /// Empty state when a run has no comments
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get runSocialNoComments;

  /// Hint text in the reply composer field
  ///
  /// In en, this message translates to:
  /// **'Write a reply…'**
  String get runSocialReplyHint;

  /// Hint text in the comment composer field
  ///
  /// In en, this message translates to:
  /// **'Add a comment…'**
  String get runSocialCommentHint;

  /// Fallback display name for a comment author with no name
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get runSocialRunnerFallback;

  /// Button to reply to a comment
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get runSocialReply;

  /// Button to delete a comment
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get runSocialDelete;

  /// Confirm dialog title before deleting a run comment
  ///
  /// In en, this message translates to:
  /// **'Delete this comment?'**
  String get runSocialDeleteCommentTitle;

  /// Confirm dialog body before deleting a run comment
  ///
  /// In en, this message translates to:
  /// **'This comment will be permanently removed. This can\'t be undone.'**
  String get runSocialDeleteCommentMessage;

  /// Button to post a comment
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get runSocialPost;

  /// Button to cancel a reply
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runSocialCancel;

  /// Accessibility label for the kudos button when the viewer has not given kudos
  ///
  /// In en, this message translates to:
  /// **'Give kudos'**
  String get kudosGiveLabel;

  /// Accessibility label for the kudos button when the viewer has already given kudos
  ///
  /// In en, this message translates to:
  /// **'Remove kudos'**
  String get kudosRemoveLabel;

  /// Accessibility label for the comment-count button on a feed card
  ///
  /// In en, this message translates to:
  /// **'View comments'**
  String get kudosViewCommentsLabel;

  /// Banner when toggling kudos fails
  ///
  /// In en, this message translates to:
  /// **'Could not update kudos: {error}'**
  String runSocialKudosError(String error);

  /// Banner when posting a comment fails
  ///
  /// In en, this message translates to:
  /// **'Failed to post: {error}'**
  String runSocialPostError(String error);

  /// Banner when deleting a comment fails
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String runSocialDeleteError(String error);

  /// Loading state for the run photo gallery
  ///
  /// In en, this message translates to:
  /// **'Loading photos…'**
  String get runPhotosLoading;

  /// Header for the run photo gallery
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get runPhotosTitle;

  /// Button to add a photo to a run
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get runPhotosAdd;

  /// Hint in the caption field for a photo about to be uploaded
  ///
  /// In en, this message translates to:
  /// **'Caption (optional, 280 chars)'**
  String get runPhotosCaptionPendingHint;

  /// Hint in the inline caption-edit field
  ///
  /// In en, this message translates to:
  /// **'Caption…'**
  String get runPhotosCaptionHint;

  /// Cancel button in the photo gallery
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runPhotosCancel;

  /// Save button for an edited caption
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get runPhotosSave;

  /// Button to upload the pending photo
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get runPhotosUpload;

  /// Button label while a photo is uploading
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get runPhotosUploading;

  /// Tooltip on the edit-caption button
  ///
  /// In en, this message translates to:
  /// **'Edit caption'**
  String get runPhotosEditCaption;

  /// Tooltip on the delete-photo button
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get runPhotosDeleteTooltip;

  /// Title of the delete-photo confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get runPhotosDeleteTitle;

  /// Body of the delete-photo confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This removes the photo from the run permanently.'**
  String get runPhotosDeleteBody;

  /// Confirm button in the delete-photo dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get runPhotosDeleteConfirm;

  /// Banner when the OS denies photo-library access for adding a run photo
  ///
  /// In en, this message translates to:
  /// **'Photo access is needed to add a photo. You can allow it in Settings.'**
  String get runPhotosPermissionDenied;

  /// Action label that opens the app's system settings to grant photo access
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get runPhotosOpenSettings;

  /// Generic banner when the image picker can't be opened
  ///
  /// In en, this message translates to:
  /// **'Could not open the photo picker. Please try again.'**
  String get runPhotosPickerFailed;

  /// Banner when a photo upload fails
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String runPhotosUploadError(String error);

  /// Banner when deleting a photo fails
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String runPhotosDeleteError(String error);

  /// Banner when updating a caption fails
  ///
  /// In en, this message translates to:
  /// **'Could not update caption: {error}'**
  String runPhotosCaptionError(String error);

  /// Loading state for the route photo gallery
  ///
  /// In en, this message translates to:
  /// **'Loading photos…'**
  String get routePhotosLoading;

  /// Header for the route photo gallery
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get routePhotosTitle;

  /// Button to add a photo to a route
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get routePhotosAdd;

  /// Hint in the caption field for a route photo about to be uploaded
  ///
  /// In en, this message translates to:
  /// **'Caption (optional, 280 chars)'**
  String get routePhotosCaptionPendingHint;

  /// Hint in the inline caption-edit field for a route photo
  ///
  /// In en, this message translates to:
  /// **'Caption…'**
  String get routePhotosCaptionHint;

  /// Cancel button in the route photo gallery
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get routePhotosCancel;

  /// Save button for an edited route-photo caption
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get routePhotosSave;

  /// Button to upload the pending route photo
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get routePhotosUpload;

  /// Button label while a route photo is uploading
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get routePhotosUploading;

  /// Tooltip on the edit-caption button for a route photo
  ///
  /// In en, this message translates to:
  /// **'Edit caption'**
  String get routePhotosEditCaption;

  /// Tooltip on the delete-photo button for a route photo
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get routePhotosDeleteTooltip;

  /// Title of the route delete-photo confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get routePhotosDeleteTitle;

  /// Body of the route delete-photo confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This removes the photo from the route permanently.'**
  String get routePhotosDeleteBody;

  /// Confirm button in the route delete-photo dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get routePhotosDeleteConfirm;

  /// Banner when the image picker can't be opened for a route photo
  ///
  /// In en, this message translates to:
  /// **'Could not open picker: {error}'**
  String routePhotosPickerError(String error);

  /// Banner when a route photo upload fails
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String routePhotosUploadError(String error);

  /// Banner when deleting a route photo fails
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String routePhotosDeleteError(String error);

  /// Banner when updating a route-photo caption fails
  ///
  /// In en, this message translates to:
  /// **'Could not update caption: {error}'**
  String routePhotosCaptionError(String error);

  /// Loading state for the club photo gallery
  ///
  /// In en, this message translates to:
  /// **'Loading photos…'**
  String get clubPhotosLoading;

  /// Header for the club photo gallery
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get clubPhotosTitle;

  /// Button to add a photo to a club
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get clubPhotosAdd;

  /// Empty state for the club photo gallery
  ///
  /// In en, this message translates to:
  /// **'No photos in this club yet.'**
  String get clubPhotosEmpty;

  /// Hint in the caption field for a club photo about to be uploaded
  ///
  /// In en, this message translates to:
  /// **'Caption (optional, 280 chars)'**
  String get clubPhotosCaptionPendingHint;

  /// Hint in the inline caption-edit field for a club photo
  ///
  /// In en, this message translates to:
  /// **'Caption…'**
  String get clubPhotosCaptionHint;

  /// Cancel button in the club photo gallery
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get clubPhotosCancel;

  /// Save button for an edited club-photo caption
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get clubPhotosSave;

  /// Button to upload the pending club photo
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get clubPhotosUpload;

  /// Button label while a club photo is uploading
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get clubPhotosUploading;

  /// Tooltip on the edit-caption button for a club photo
  ///
  /// In en, this message translates to:
  /// **'Edit caption'**
  String get clubPhotosEditCaption;

  /// Tooltip on the delete-photo button for a club photo
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get clubPhotosDeleteTooltip;

  /// Title of the club delete-photo confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get clubPhotosDeleteTitle;

  /// Body of the club delete-photo confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This removes the photo from the club permanently.'**
  String get clubPhotosDeleteBody;

  /// Confirm button in the club delete-photo dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get clubPhotosDeleteConfirm;

  /// Banner when the image picker can't be opened for a club photo
  ///
  /// In en, this message translates to:
  /// **'Could not open picker: {error}'**
  String clubPhotosPickerError(String error);

  /// Banner when a club photo upload fails
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String clubPhotosUploadError(String error);

  /// Banner when deleting a club photo fails
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String clubPhotosDeleteError(String error);

  /// Banner when updating a club-photo caption fails
  ///
  /// In en, this message translates to:
  /// **'Could not update caption: {error}'**
  String clubPhotosCaptionError(String error);

  /// Loading state while segment efforts are computed
  ///
  /// In en, this message translates to:
  /// **'Checking segments…'**
  String get runSegEffortsChecking;

  /// Hint when a run isn't linked to a route so no segments apply
  ///
  /// In en, this message translates to:
  /// **'Segments are matched per route — link this run to a saved route to compete on its leaderboards.'**
  String get runSegEffortsNoRoute;

  /// Empty state when a run has no segment efforts
  ///
  /// In en, this message translates to:
  /// **'No segment efforts on this run.'**
  String get runSegEffortsEmpty;

  /// Header for the post-run workout review section
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get workoutReviewTitle;

  /// Column header: workout step
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get workoutReviewColStep;

  /// Column header: planned value
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get workoutReviewColPlan;

  /// Column header: actual value
  ///
  /// In en, this message translates to:
  /// **'Actual'**
  String get workoutReviewColActual;

  /// Column header: pace
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get workoutReviewColPace;

  /// Column header: pace delta (uses the delta symbol)
  ///
  /// In en, this message translates to:
  /// **'Δ'**
  String get workoutReviewColDelta;

  /// Label shown in the delta column for a skipped step
  ///
  /// In en, this message translates to:
  /// **'skip'**
  String get workoutReviewSkip;

  /// Workout step label: warmup
  ///
  /// In en, this message translates to:
  /// **'Warmup'**
  String get workoutReviewLabelWarmup;

  /// Workout step label: cooldown
  ///
  /// In en, this message translates to:
  /// **'Cooldown'**
  String get workoutReviewLabelCooldown;

  /// Workout step label: steady
  ///
  /// In en, this message translates to:
  /// **'Steady'**
  String get workoutReviewLabelSteady;

  /// Workout step label: a single rep with no index
  ///
  /// In en, this message translates to:
  /// **'Rep'**
  String get workoutReviewLabelRep;

  /// Workout step label: rep i of n
  ///
  /// In en, this message translates to:
  /// **'Rep {index}/{total}'**
  String workoutReviewLabelRepN(int index, int total);

  /// Workout step label: a single recovery with no index
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get workoutReviewLabelRecovery;

  /// Workout step label: recovery i of n
  ///
  /// In en, this message translates to:
  /// **'Recovery {index}/{total}'**
  String workoutReviewLabelRecoveryN(int index, int total);

  /// Workout step label: a single walk with no index
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get workoutReviewLabelWalk;

  /// Workout step label: walk i of n
  ///
  /// In en, this message translates to:
  /// **'Walk {index}/{total}'**
  String workoutReviewLabelWalkN(int index, int total);

  /// Header for the route segments panel
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get segmentsPanelTitle;

  /// Button to start creating a new segment
  ///
  /// In en, this message translates to:
  /// **'New segment'**
  String get segmentsPanelNew;

  /// Button to cancel the new-segment form
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get segmentsPanelCancel;

  /// Loading state for the segments list
  ///
  /// In en, this message translates to:
  /// **'Loading segments…'**
  String get segmentsPanelLoading;

  /// Empty state when a route has no segments
  ///
  /// In en, this message translates to:
  /// **'No segments on this route yet.'**
  String get segmentsPanelEmpty;

  /// Label for the segment name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get segmentsPanelNameLabel;

  /// Example hint for the segment name field
  ///
  /// In en, this message translates to:
  /// **'Climb of doom'**
  String get segmentsPanelNameHint;

  /// Label for the segment start distance field (metres)
  ///
  /// In en, this message translates to:
  /// **'Start (m)'**
  String get segmentsPanelStartLabel;

  /// Label for the segment end distance field (metres)
  ///
  /// In en, this message translates to:
  /// **'End (m)'**
  String get segmentsPanelEndLabel;

  /// Helper text showing total route length in metres
  ///
  /// In en, this message translates to:
  /// **'route is {metres} m'**
  String segmentsPanelRouteHint(int metres);

  /// Button to create the segment
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get segmentsPanelCreate;

  /// Tooltip on the delete-segment button
  ///
  /// In en, this message translates to:
  /// **'Delete segment'**
  String get segmentsPanelDeleteTooltip;

  /// Title of the delete-segment confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete segment?'**
  String get segmentsPanelDeleteTitle;

  /// Body of the delete-segment dialog naming the segment
  ///
  /// In en, this message translates to:
  /// **'“{name}” will be removed.'**
  String segmentsPanelDeleteBody(String name);

  /// Confirm button in the delete-segment dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get segmentsPanelDeleteConfirm;

  /// Validation error: end must be after start
  ///
  /// In en, this message translates to:
  /// **'End must be greater than start'**
  String get segmentsPanelErrEndAfterStart;

  /// Validation error: segment too short
  ///
  /// In en, this message translates to:
  /// **'Segment must be at least 100 m'**
  String get segmentsPanelErrMinLength;

  /// Banner when creating a segment fails
  ///
  /// In en, this message translates to:
  /// **'Could not create segment: {error}'**
  String segmentsPanelCreateError(String error);

  /// Banner when deleting a segment fails
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String segmentsPanelDeleteError(String error);

  /// Leaderboard filter: all genders
  ///
  /// In en, this message translates to:
  /// **'All genders'**
  String get segmentsPanelAllGenders;

  /// Leaderboard gender filter: men
  ///
  /// In en, this message translates to:
  /// **'Men'**
  String get segmentsPanelGenderMen;

  /// Leaderboard gender filter: women
  ///
  /// In en, this message translates to:
  /// **'Women'**
  String get segmentsPanelGenderWomen;

  /// Leaderboard gender filter: nonbinary
  ///
  /// In en, this message translates to:
  /// **'Nonbinary'**
  String get segmentsPanelGenderNonbinary;

  /// Leaderboard filter: all age bands
  ///
  /// In en, this message translates to:
  /// **'All ages'**
  String get segmentsPanelAllAges;

  /// Button to reset leaderboard filters
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get segmentsPanelResetFilters;

  /// Loading state for a segment leaderboard
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get segmentsPanelLeaderboardLoading;

  /// Empty leaderboard with a filter applied
  ///
  /// In en, this message translates to:
  /// **'No efforts match this filter — try widening it.'**
  String get segmentsPanelLeaderboardEmptyFiltered;

  /// Empty leaderboard with no filter
  ///
  /// In en, this message translates to:
  /// **'No efforts yet — be the first to run this segment.'**
  String get segmentsPanelLeaderboardEmpty;

  /// Banner shown when the viewer holds the segment crown
  ///
  /// In en, this message translates to:
  /// **'You hold this crown — {label}.'**
  String segmentsPanelCrownBanner(String label);

  /// Fallback display name for a leaderboard athlete
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get segmentsPanelRunnerFallback;

  /// AppBar title when creating a goal
  ///
  /// In en, this message translates to:
  /// **'New goal'**
  String get goalEditorTitleNew;

  /// AppBar title when editing a goal
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get goalEditorTitleEdit;

  /// Section label for the optional goal name
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get goalEditorNameLabel;

  /// Example hint for the goal name field
  ///
  /// In en, this message translates to:
  /// **'e.g. Base miles'**
  String get goalEditorNameHint;

  /// Section label for the goal period
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get goalEditorPeriod;

  /// Goal period option: this week
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get goalEditorThisWeek;

  /// Goal period option: this month
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get goalEditorThisMonth;

  /// Section label for the goal targets
  ///
  /// In en, this message translates to:
  /// **'Targets'**
  String get goalEditorTargets;

  /// Helper text under the targets section
  ///
  /// In en, this message translates to:
  /// **'Set any combination. Blank fields are ignored.'**
  String get goalEditorTargetsHelp;

  /// Target field label: distance
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get goalEditorTargetDistance;

  /// Target field label: time
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get goalEditorTargetTime;

  /// Target field label: average pace
  ///
  /// In en, this message translates to:
  /// **'Avg pace'**
  String get goalEditorTargetPace;

  /// Target field label: number of runs
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get goalEditorTargetRuns;

  /// Suffix for the time-target field (minutes)
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get goalEditorSuffixMin;

  /// Suffix for the runs-target field
  ///
  /// In en, this message translates to:
  /// **'runs'**
  String get goalEditorSuffixRuns;

  /// Button to delete a goal
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get goalEditorDelete;

  /// Confirm dialog title before deleting a goal
  ///
  /// In en, this message translates to:
  /// **'Delete this goal?'**
  String get goalEditorDeleteTitle;

  /// Confirm dialog body before deleting a goal
  ///
  /// In en, this message translates to:
  /// **'This goal and its progress tracking will be removed. You can create a new one anytime.'**
  String get goalEditorDeleteMessage;

  /// Button to cancel the goal editor
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get goalEditorCancel;

  /// Button to save the goal
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get goalEditorSave;

  /// Banner shown when saving a goal fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the goal: {error}'**
  String goalEditorSaveFailed(String error);

  /// Validation error for the distance target
  ///
  /// In en, this message translates to:
  /// **'Distance: enter a positive number'**
  String get goalEditorErrDistance;

  /// Validation error for the time target
  ///
  /// In en, this message translates to:
  /// **'Time: enter a positive number of minutes'**
  String get goalEditorErrTime;

  /// Validation error for the pace target
  ///
  /// In en, this message translates to:
  /// **'Pace: use mm:ss (e.g. 5:00)'**
  String get goalEditorErrPace;

  /// Validation error for the runs target
  ///
  /// In en, this message translates to:
  /// **'Runs: enter a positive whole number'**
  String get goalEditorErrRuns;

  /// Validation error when no target is set
  ///
  /// In en, this message translates to:
  /// **'Set at least one target'**
  String get goalEditorErrNoTarget;

  /// Screen-reader status when a goal is saved
  ///
  /// In en, this message translates to:
  /// **'Goal saved'**
  String get goalEditorSavedAnnounce;

  /// Screen-reader status when a goal is deleted
  ///
  /// In en, this message translates to:
  /// **'Goal deleted'**
  String get goalEditorDeletedAnnounce;

  /// Header of the create-event sheet
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get eventFormTitle;

  /// Label for the event title field
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get eventFormTitleLabel;

  /// Label for the event start date/time field
  ///
  /// In en, this message translates to:
  /// **'Starts at'**
  String get eventFormStartsAt;

  /// Label for the optional event description field
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get eventFormDescriptionLabel;

  /// Label for the optional meeting-point field
  ///
  /// In en, this message translates to:
  /// **'Meeting point (optional)'**
  String get eventFormMeetLabel;

  /// Example hint for the meeting-point field
  ///
  /// In en, this message translates to:
  /// **'Trailhead car park'**
  String get eventFormMeetHint;

  /// Label for the event distance field (km)
  ///
  /// In en, this message translates to:
  /// **'Distance (km)'**
  String get eventFormDistanceLabel;

  /// Label for the event duration field (minutes)
  ///
  /// In en, this message translates to:
  /// **'Duration (min)'**
  String get eventFormDurationLabel;

  /// Section label for recurrence options
  ///
  /// In en, this message translates to:
  /// **'Recurrence'**
  String get eventFormRecurrence;

  /// Recurrence option: one-off
  ///
  /// In en, this message translates to:
  /// **'One-off'**
  String get eventFormRecurOneOff;

  /// Recurrence option: weekly
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get eventFormRecurWeekly;

  /// Recurrence option: every two weeks
  ///
  /// In en, this message translates to:
  /// **'Bi-weekly'**
  String get eventFormRecurBiweekly;

  /// Recurrence option: monthly
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get eventFormRecurMonthly;

  /// Button to cancel the event form
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get eventFormCancel;

  /// Button to create the event
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get eventFormCreate;

  /// Label for the event-category picker
  ///
  /// In en, this message translates to:
  /// **'Event type'**
  String get eventEditorCategory;

  /// Event category: a group run
  ///
  /// In en, this message translates to:
  /// **'Group run'**
  String get eventEditorCatRun;

  /// Event category: a cycle
  ///
  /// In en, this message translates to:
  /// **'Cycle'**
  String get eventEditorCatCycle;

  /// Event category: an instructor-led class
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get eventEditorCatClass;

  /// Event category: a social meetup
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get eventEditorCatSocial;

  /// Helper text under the event-category picker
  ///
  /// In en, this message translates to:
  /// **'Pick the kind of event — a class or social meetup skips route, distance, pace and race results.'**
  String get eventEditorCategoryHint;

  /// Toggle in the event editor (public clubs only) that makes the event members-only (events.is_public = false).
  ///
  /// In en, this message translates to:
  /// **'Members only'**
  String get eventEditorMembersOnlyToggle;

  /// Helper text under the members-only toggle in the event editor.
  ///
  /// In en, this message translates to:
  /// **'Only club members can see this event, and it won\'t appear in public discovery.'**
  String get eventEditorMembersOnlyHint;

  /// Label for the free-text class-discipline field
  ///
  /// In en, this message translates to:
  /// **'Discipline'**
  String get eventEditorDiscipline;

  /// Placeholder for the class-discipline field
  ///
  /// In en, this message translates to:
  /// **'e.g. Vinyasa yoga, Pilates, mobility'**
  String get eventEditorDisciplinePlaceholder;

  /// AppBar title of the create-club screen
  ///
  /// In en, this message translates to:
  /// **'New club'**
  String get clubFormTitle;

  /// Label for the club name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get clubFormNameLabel;

  /// Label for the optional club description field
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get clubFormDescriptionLabel;

  /// Label for the optional club location field
  ///
  /// In en, this message translates to:
  /// **'Location (optional)'**
  String get clubFormLocationLabel;

  /// Example hint for the club location field
  ///
  /// In en, this message translates to:
  /// **'Edinburgh, UK'**
  String get clubFormLocationHint;

  /// Visibility option: public club
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get clubFormPublic;

  /// Visibility option: private club
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get clubFormPrivate;

  /// Section label for the join policy
  ///
  /// In en, this message translates to:
  /// **'Join policy'**
  String get clubFormJoinPolicy;

  /// Join policy option: anyone can join
  ///
  /// In en, this message translates to:
  /// **'Open — anyone joins'**
  String get clubFormJoinOpen;

  /// Join policy option: admins approve
  ///
  /// In en, this message translates to:
  /// **'Request — admins approve'**
  String get clubFormJoinRequest;

  /// Join policy option: invite only
  ///
  /// In en, this message translates to:
  /// **'Invite only'**
  String get clubFormJoinInvite;

  /// Button to cancel the club form
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get clubFormCancel;

  /// Button to create the club
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get clubFormCreate;

  /// Validation error when the name has no usable characters
  ///
  /// In en, this message translates to:
  /// **'Name needs at least one letter or digit.'**
  String get clubFormErrSlug;

  /// Error when the server can't be reached during create
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server right now. Check your connection or sign in, then try again.'**
  String get clubFormErrUnreachable;

  /// Report reason label: spam
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportReasonSpam;

  /// Report reason label: harassment or abuse
  ///
  /// In en, this message translates to:
  /// **'Harassment or abuse'**
  String get reportReasonHarassment;

  /// Report reason label: inappropriate content
  ///
  /// In en, this message translates to:
  /// **'Inappropriate content'**
  String get reportReasonInappropriate;

  /// Report reason label: impersonation
  ///
  /// In en, this message translates to:
  /// **'Impersonation'**
  String get reportReasonImpersonation;

  /// Report reason label: other
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportReasonOther;

  /// Banner shown after a report is submitted
  ///
  /// In en, this message translates to:
  /// **'Report submitted — thanks for flagging this for review.'**
  String get reportSuccess;

  /// Report sheet title when reporting a user
  ///
  /// In en, this message translates to:
  /// **'Report user'**
  String get reportTitleUser;

  /// Report sheet title when reporting a club
  ///
  /// In en, this message translates to:
  /// **'Report club'**
  String get reportTitleClub;

  /// Report sheet title when reporting a route
  ///
  /// In en, this message translates to:
  /// **'Report route'**
  String get reportTitleRoute;

  /// Report sheet title when reporting a club post
  ///
  /// In en, this message translates to:
  /// **'Report post'**
  String get reportTitlePost;

  /// Report sheet title when reporting a run
  ///
  /// In en, this message translates to:
  /// **'Report run'**
  String get reportTitleRun;

  /// Report sheet title fallback for generic content
  ///
  /// In en, this message translates to:
  /// **'Report content'**
  String get reportTitleContent;

  /// Disclaimer text in the report sheet
  ///
  /// In en, this message translates to:
  /// **'Your report goes to a moderator. False reports are reviewed too — please only flag content that violates our community guidelines.'**
  String get reportDisclaimer;

  /// Section label for the report reason picker
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reportReason;

  /// Label for the optional report notes field
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get reportNotesLabel;

  /// Button to cancel the report sheet
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get reportCancel;

  /// Button to submit the report
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get reportSubmit;

  /// Inline error: already have a pending report
  ///
  /// In en, this message translates to:
  /// **'You already have a pending report against this content.'**
  String get reportErrDuplicate;

  /// Title of the backfill sheet asking to attach past runs
  ///
  /// In en, this message translates to:
  /// **'Attach past runs to {gear}?'**
  String gearBackfillTitle(String gear);

  /// Body explaining the matched activities found
  ///
  /// In en, this message translates to:
  /// **'We found {count, plural, one{{count} {activity} activity} other{{count} {activity} activities}} after you bought them. Uncheck any you weren\'t wearing them for.'**
  String gearBackfillBody(int count, String activity);

  /// Activity word for bikes in the backfill body
  ///
  /// In en, this message translates to:
  /// **'cycling'**
  String get gearBackfillActivityCycling;

  /// Activity word for shoes in the backfill body
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get gearBackfillActivityRunning;

  /// Toggle label to deselect all candidate runs
  ///
  /// In en, this message translates to:
  /// **'Select none'**
  String get gearBackfillSelectNone;

  /// Toggle label to select all candidate runs
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get gearBackfillSelectAll;

  /// Counter showing how many runs are selected
  ///
  /// In en, this message translates to:
  /// **'{selected} of {total}'**
  String gearBackfillSelectedCount(int selected, int total);

  /// Button to skip the backfill prompt
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get gearBackfillSkip;

  /// Button label while runs are being attached
  ///
  /// In en, this message translates to:
  /// **'Attaching…'**
  String get gearBackfillAttaching;

  /// Button to attach the selected runs
  ///
  /// In en, this message translates to:
  /// **'Attach {count}'**
  String gearBackfillAttach(int count);

  /// Banner when attaching runs fails
  ///
  /// In en, this message translates to:
  /// **'Attach failed: {error}'**
  String gearBackfillAttachError(String error);

  /// Header of the workout edit sheet
  ///
  /// In en, this message translates to:
  /// **'Edit workout'**
  String get workoutEditTitle;

  /// Label for the workout kind dropdown
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get workoutEditKindLabel;

  /// Label for the target distance field (km)
  ///
  /// In en, this message translates to:
  /// **'Target distance (km)'**
  String get workoutEditDistanceLabel;

  /// Example hint for the target distance field
  ///
  /// In en, this message translates to:
  /// **'e.g. 8.0'**
  String get workoutEditDistanceHint;

  /// Label for the target pace field
  ///
  /// In en, this message translates to:
  /// **'Target pace (mm:ss /km)'**
  String get workoutEditPaceLabel;

  /// Example hint for the target pace field
  ///
  /// In en, this message translates to:
  /// **'e.g. 5:30'**
  String get workoutEditPaceHint;

  /// Label for the workout notes field
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get workoutEditNotesLabel;

  /// Button to cancel the workout edit sheet
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get workoutEditCancel;

  /// Button to save the workout
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get workoutEditSave;

  /// Validation error for the distance field
  ///
  /// In en, this message translates to:
  /// **'Enter a positive distance in km'**
  String get workoutEditErrDistance;

  /// Validation error for the pace field
  ///
  /// In en, this message translates to:
  /// **'Pace must look like 5:30'**
  String get workoutEditErrPace;

  /// Inline error when saving a workout fails
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String workoutEditSaveError(String error);

  /// Badge above the event title showing it's RSVP'd
  ///
  /// In en, this message translates to:
  /// **'RSVP\'D · {relative}'**
  String upcomingEventBadge(String relative);

  /// Relative time: event starting now
  ///
  /// In en, this message translates to:
  /// **'Starting now'**
  String get upcomingEventStartingNow;

  /// Relative time: in N minutes
  ///
  /// In en, this message translates to:
  /// **'In {count} min'**
  String upcomingEventInMinutes(int count);

  /// Relative time: in one hour
  ///
  /// In en, this message translates to:
  /// **'In 1 hour'**
  String get upcomingEventInOneHour;

  /// Relative time: in N hours
  ///
  /// In en, this message translates to:
  /// **'In {count} hours'**
  String upcomingEventInHours(int count);

  /// Relative time: tomorrow
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get upcomingEventTomorrow;

  /// Relative time: in N days
  ///
  /// In en, this message translates to:
  /// **'In {count} days'**
  String upcomingEventInDays(int count);

  /// Badge when today's workout is already done
  ///
  /// In en, this message translates to:
  /// **'DONE TODAY'**
  String get todaysWorkoutDone;

  /// Badge for today's scheduled workout
  ///
  /// In en, this message translates to:
  /// **'TODAY\'S WORKOUT'**
  String get todaysWorkoutToday;

  /// Retry button on the shared error state
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get errorStateRetry;

  /// Title of the run share sheet
  ///
  /// In en, this message translates to:
  /// **'Share run'**
  String get shareCardRunTitle;

  /// Button to export a run to a file format
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get shareCardExport;

  /// Button to share the run as an image
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get shareCardImage;

  /// Stat label on the share card: distance
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get shareCardStatDistance;

  /// Stat label on the share card: time
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get shareCardStatTime;

  /// Stat label on the share card: pace
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get shareCardStatPace;

  /// Stat label on the share card: speed
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get shareCardStatSpeed;

  /// Branding wordmark on the run share card
  ///
  /// In en, this message translates to:
  /// **'RUN'**
  String get shareCardBrandRun;

  /// Banner when the share image can't be created
  ///
  /// In en, this message translates to:
  /// **'Could not create share image'**
  String get shareCardImageError;

  /// Banner when exporting a run file fails
  ///
  /// In en, this message translates to:
  /// **'Could not export file'**
  String get shareCardFileError;

  /// Title of the route share sheet
  ///
  /// In en, this message translates to:
  /// **'Share route'**
  String get shareCardRouteTitle;

  /// Button to share the route as an image
  ///
  /// In en, this message translates to:
  /// **'Share image'**
  String get shareCardRouteShareImage;

  /// Button label while the route image is captured
  ///
  /// In en, this message translates to:
  /// **'Capturing…'**
  String get shareCardRouteCapturing;

  /// Stat label on the route share card: distance
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get shareCardRouteStatDistance;

  /// Stat label on the route share card: climb
  ///
  /// In en, this message translates to:
  /// **'Climb'**
  String get shareCardRouteStatClimb;

  /// Relative time: today
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get billingToday;

  /// Relative time: yesterday
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get billingYesterday;

  /// Relative time: N days ago
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String billingDaysAgo(int count);

  /// Banner headline when a Pro renewal failed
  ///
  /// In en, this message translates to:
  /// **'Pro renewal failed {relative}.'**
  String billingRenewalFailed(String relative);

  /// Banner body prompting the user to update their card
  ///
  /// In en, this message translates to:
  /// **'Update your card or you\'ll be downgraded to Free.'**
  String get billingRenewalBody;

  /// Button to manage the subscription
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get billingManage;

  /// Tooltip on the previous-month chevron
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get planCalendarPrevMonth;

  /// Tooltip on the next-month chevron
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get planCalendarNextMonth;

  /// Banner when the gear inventory can't load
  ///
  /// In en, this message translates to:
  /// **'Failed to load gear: {error}'**
  String runGearChipsLoadError(String error);

  /// Header of the tag-gear bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Tag gear used on this run'**
  String get runGearChipsPickerTitle;

  /// Empty state in the gear picker
  ///
  /// In en, this message translates to:
  /// **'You haven\'t registered any gear yet. Add some in Settings → Gear.'**
  String get runGearChipsEmpty;

  /// Cancel button in the gear picker
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get runGearChipsCancel;

  /// Save button in the gear picker
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get runGearChipsSave;

  /// Button to tag gear when none is assigned
  ///
  /// In en, this message translates to:
  /// **'+ Tag gear'**
  String get runGearChipsTag;

  /// Button to edit assigned gear
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get runGearChipsEdit;

  /// Banner when saving tagged gear fails
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String runGearChipsSaveError(String error);

  /// Header of the gear form when editing
  ///
  /// In en, this message translates to:
  /// **'Edit gear'**
  String get gearFormTitleEdit;

  /// Header of the gear form when adding shoes
  ///
  /// In en, this message translates to:
  /// **'Add shoes'**
  String get gearFormTitleAddShoes;

  /// Header of the gear form when adding a bike
  ///
  /// In en, this message translates to:
  /// **'Add bike'**
  String get gearFormTitleAddBike;

  /// Label for the gear name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get gearFormNameLabel;

  /// Example hint for the gear name field
  ///
  /// In en, this message translates to:
  /// **'Pegasus 39'**
  String get gearFormNameHint;

  /// Label for the gear brand field
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get gearFormBrandLabel;

  /// Label for the gear model field
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get gearFormModelLabel;

  /// Label for the gear purchase-date field
  ///
  /// In en, this message translates to:
  /// **'Bought'**
  String get gearFormBoughtLabel;

  /// Placeholder when no purchase date is picked
  ///
  /// In en, this message translates to:
  /// **'Tap to pick'**
  String get gearFormBoughtPick;

  /// Label for the retirement target field with unit
  ///
  /// In en, this message translates to:
  /// **'Retire at ({unit})'**
  String gearFormRetireAt(String unit);

  /// Example hint for the retirement target field
  ///
  /// In en, this message translates to:
  /// **'500'**
  String get gearFormRetireHint;

  /// Label for the gear notes field
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get gearFormNotesLabel;

  /// Button to cancel the gear form
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gearFormCancel;

  /// Button label while the gear is saving
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get gearFormSaving;

  /// Button to save an edited gear row
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get gearFormSave;

  /// Button to add a new gear row
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get gearFormAdd;

  /// Banner when saving gear fails
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String gearFormSaveError(String error);

  /// Heading for the per-shoe wear-observation log in the gear edit form
  ///
  /// In en, this message translates to:
  /// **'Wear log'**
  String get gearWearLogHeading;

  /// Subtitle explaining the wear log
  ///
  /// In en, this message translates to:
  /// **'Note how this gear is ageing over time — outsole wear, a dead midsole, a fraying upper.'**
  String get gearWearLogHint;

  /// Empty state for the wear log
  ///
  /// In en, this message translates to:
  /// **'No wear observations yet.'**
  String get gearWearLogEmpty;

  /// Label for the wear-observation note field
  ///
  /// In en, this message translates to:
  /// **'Observation'**
  String get gearWearLogAddNote;

  /// Hint for the wear-observation note field
  ///
  /// In en, this message translates to:
  /// **'e.g. outsole lugs worn smooth on the heel'**
  String get gearWearLogNoteHint;

  /// Label for the optional wear-area dropdown
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get gearWearLogArea;

  /// No-area choice in the wear-area dropdown
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get gearWearLogAreaNone;

  /// Outsole wear area
  ///
  /// In en, this message translates to:
  /// **'Outsole'**
  String get gearWearLogAreaOutsole;

  /// Midsole wear area
  ///
  /// In en, this message translates to:
  /// **'Midsole'**
  String get gearWearLogAreaMidsole;

  /// Upper wear area
  ///
  /// In en, this message translates to:
  /// **'Upper'**
  String get gearWearLogAreaUpper;

  /// Other wear area
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get gearWearLogAreaOther;

  /// Button to add a wear observation
  ///
  /// In en, this message translates to:
  /// **'Add observation'**
  String get gearWearLogAdd;

  /// Button label while a wear observation is being added
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get gearWearLogAdding;

  /// Tooltip to delete a wear observation
  ///
  /// In en, this message translates to:
  /// **'Delete observation'**
  String get gearWearLogDelete;

  /// Banner when adding a wear observation fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add observation: {error}'**
  String gearWearLogAddError(String error);

  /// Banner when deleting a wear observation fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete observation: {error}'**
  String gearWearLogDeleteError(String error);

  /// Tooltip on the notification bell
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationBellTooltip;

  /// Overlay shown while waiting for the first GPS fix
  ///
  /// In en, this message translates to:
  /// **'Waiting for GPS...'**
  String get liveRunMapWaitingGps;

  /// Tooltip on the re-centre map button
  ///
  /// In en, this message translates to:
  /// **'Re-centre on my location'**
  String get liveRunMapRecentre;

  /// Spoken cue when a run starts
  ///
  /// In en, this message translates to:
  /// **'Run started'**
  String get ttsRunStarted;

  /// Spoken cue at the end of a run, with total distance and minutes
  ///
  /// In en, this message translates to:
  /// **'Run complete. {distance} in {mins} minutes.'**
  String ttsRunComplete(String distance, int mins);

  /// Spoken cue when the runner drifts off the selected route
  ///
  /// In en, this message translates to:
  /// **'Off route'**
  String get ttsOffRoute;

  /// Spoken cue telling the runner to speed up (too slow)
  ///
  /// In en, this message translates to:
  /// **'Pick up the pace'**
  String get ttsPaceAlertFast;

  /// Spoken cue telling the runner to slow down (too fast)
  ///
  /// In en, this message translates to:
  /// **'Slow down'**
  String get ttsPaceAlertSlow;

  /// Spoken cue when a structured workout finishes
  ///
  /// In en, this message translates to:
  /// **'Workout complete. Nice work.'**
  String get ttsWorkoutComplete;

  /// Spoken in-step progress cue at the halfway point
  ///
  /// In en, this message translates to:
  /// **'Halfway through this rep'**
  String get ttsStepHalfway;

  /// Spoken in-step progress cue near the end of a rep
  ///
  /// In en, this message translates to:
  /// **'Fifty metres to go'**
  String get ttsStepLastFifty;

  /// Spoken nudge when the runner is ahead of target pace by delta seconds per km
  ///
  /// In en, this message translates to:
  /// **'Ease up — {delta} seconds ahead pace.'**
  String ttsPaceDriftAhead(int delta);

  /// Spoken nudge when the runner is behind target pace by delta seconds per km
  ///
  /// In en, this message translates to:
  /// **'Pick it up — {delta} seconds behind pace.'**
  String ttsPaceDriftBehind(int delta);

  /// Spoken speed in km/h appended to a split cue
  ///
  /// In en, this message translates to:
  /// **'Speed, {value} kilometres per hour'**
  String ttsSpeedKm(String value);

  /// Spoken speed in mph appended to a split cue
  ///
  /// In en, this message translates to:
  /// **'Speed, {value} miles per hour'**
  String ttsSpeedMi(String value);

  /// Spoken pace in minutes/seconds per kilometre appended to a split cue
  ///
  /// In en, this message translates to:
  /// **'Pace, {min} minutes {sec} seconds per kilometre'**
  String ttsPaceKm(int min, int sec);

  /// Spoken pace in minutes/seconds per mile appended to a split cue
  ///
  /// In en, this message translates to:
  /// **'Pace, {min} minutes {sec} seconds per mile'**
  String ttsPaceMi(int min, int sec);

  /// Spoken distance in kilometres (value may be integer or decimal string)
  ///
  /// In en, this message translates to:
  /// **'{value} kilometres'**
  String ttsDistanceKm(String value);

  /// Spoken distance in metres
  ///
  /// In en, this message translates to:
  /// **'{value} metres'**
  String ttsDistanceMetres(int value);

  /// Spoken distance of exactly one mile
  ///
  /// In en, this message translates to:
  /// **'{value} mile'**
  String ttsDistanceMileSingular(String value);

  /// Spoken distance in miles (plural; value may be integer or decimal string)
  ///
  /// In en, this message translates to:
  /// **'{value} miles'**
  String ttsDistanceMiles(String value);

  /// Spoken sub-mile distance in yards
  ///
  /// In en, this message translates to:
  /// **'{value} yards'**
  String ttsDistanceYards(int value);

  /// Spoken split cue: distance count, unit word, then pace/speed tail
  ///
  /// In en, this message translates to:
  /// **'{count} {unit}. {tail}'**
  String ttsSplit(String count, String unit, String tail);

  /// Spoken workout-step intro: warmup
  ///
  /// In en, this message translates to:
  /// **'Warmup'**
  String get ttsStepWarmup;

  /// Spoken workout-step intro: recovery
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get ttsStepRecovery;

  /// Spoken workout-step intro: steady
  ///
  /// In en, this message translates to:
  /// **'Steady'**
  String get ttsStepSteady;

  /// Spoken workout-step intro: cooldown
  ///
  /// In en, this message translates to:
  /// **'Cooldown'**
  String get ttsStepCooldown;

  /// Spoken workout-step intro: a rep with no index
  ///
  /// In en, this message translates to:
  /// **'Rep'**
  String get ttsStepRep;

  /// Spoken workout-step intro: a run interval with no index
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get ttsStepRun;

  /// Spoken workout-step intro: a walk interval with no index
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get ttsStepWalk;

  /// Spoken workout-step intro: rep N of M
  ///
  /// In en, this message translates to:
  /// **'Rep {index} of {total}'**
  String ttsStepRepOf(int index, int total);

  /// Spoken workout-step intro: run interval N of M
  ///
  /// In en, this message translates to:
  /// **'Run {index} of {total}'**
  String ttsStepRunOf(int index, int total);

  /// Spoken workout-step intro: walk interval N of M
  ///
  /// In en, this message translates to:
  /// **'Walk {index} of {total}'**
  String ttsStepWalkOf(int index, int total);

  /// Workout-step pace tail in min/sec per kilometre
  ///
  /// In en, this message translates to:
  /// **'{min} minutes {sec} seconds per kilometre'**
  String ttsStepPaceKm(int min, int sec);

  /// Workout-step pace tail, whole minutes per kilometre
  ///
  /// In en, this message translates to:
  /// **'{min} minutes per kilometre'**
  String ttsStepPaceKmWhole(int min);

  /// Workout-step pace tail in min/sec per mile
  ///
  /// In en, this message translates to:
  /// **'{min} minutes {sec} seconds per mile'**
  String ttsStepPaceMi(int min, int sec);

  /// Workout-step pace tail, whole minutes per mile
  ///
  /// In en, this message translates to:
  /// **'{min} minutes per mile'**
  String ttsStepPaceMiWhole(int min);

  /// Spoken duration: seconds only
  ///
  /// In en, this message translates to:
  /// **'{sec} seconds'**
  String ttsDurationSeconds(int sec);

  /// Spoken duration: whole minutes
  ///
  /// In en, this message translates to:
  /// **'{min, plural, one{1 minute} other{{min} minutes}}'**
  String ttsDurationMinutes(int min);

  /// Spoken duration: a minutes phrase followed by seconds
  ///
  /// In en, this message translates to:
  /// **'{minutes} {sec} seconds'**
  String ttsDurationMinutesSeconds(String minutes, int sec);

  /// Workout-step cue: intro then duration
  ///
  /// In en, this message translates to:
  /// **'{intro}. {duration}.'**
  String ttsStepDuration(String intro, String duration);

  /// Workout-step cue: intro then distance at pace
  ///
  /// In en, this message translates to:
  /// **'{intro}. {distance} at {pace}.'**
  String ttsStepDistancePace(String intro, String distance, String pace);

  /// Guided run title: 30-minute easy run
  ///
  /// In en, this message translates to:
  /// **'30-Minute Easy Run'**
  String get guidedEasy30Title;

  /// Guided run subtitle: 30-minute easy run
  ///
  /// In en, this message translates to:
  /// **'Coach voice · 30 min · easy effort'**
  String get guidedEasy30Subtitle;

  /// Guided run description: 30-minute easy run
  ///
  /// In en, this message translates to:
  /// **'A relaxed, conversational-pace run for a recovery day or just clearing your head. Coach checks in every five minutes with a gentle nudge.'**
  String get guidedEasy30Description;

  /// Guided easy-30 cue at 0:00
  ///
  /// In en, this message translates to:
  /// **'Let’s go. Start easy — this is your recovery pace.'**
  String get guidedEasy30Cue0;

  /// Guided easy-30 cue at 5:00
  ///
  /// In en, this message translates to:
  /// **'Five minutes in. Drop your shoulders. Keep it conversational.'**
  String get guidedEasy30Cue1;

  /// Guided easy-30 cue at 10:00
  ///
  /// In en, this message translates to:
  /// **'Ten minutes. Cadence check — quick feet, light landing.'**
  String get guidedEasy30Cue2;

  /// Guided easy-30 cue at 15:00
  ///
  /// In en, this message translates to:
  /// **'Halfway. You should still be able to talk through this.'**
  String get guidedEasy30Cue3;

  /// Guided easy-30 cue at 20:00
  ///
  /// In en, this message translates to:
  /// **'Twenty minutes. Notice your breathing — slow nasal in, mouth out.'**
  String get guidedEasy30Cue4;

  /// Guided easy-30 cue at 25:00
  ///
  /// In en, this message translates to:
  /// **'Five to go. Stay relaxed. Don’t pick it up.'**
  String get guidedEasy30Cue5;

  /// Guided easy-30 cue at 29:00
  ///
  /// In en, this message translates to:
  /// **'One minute left. Easy finish.'**
  String get guidedEasy30Cue6;

  /// Guided easy-30 cue at 30:00
  ///
  /// In en, this message translates to:
  /// **'Done. Walk it out for a minute. Nice job.'**
  String get guidedEasy30Cue7;

  /// Guided run title: 25-minute tempo builder
  ///
  /// In en, this message translates to:
  /// **'25-Minute Tempo Builder'**
  String get guidedTempo25Title;

  /// Guided run subtitle: 25-minute tempo builder
  ///
  /// In en, this message translates to:
  /// **'Coach voice · 25 min · 5-15-5'**
  String get guidedTempo25Subtitle;

  /// Guided run description: 25-minute tempo builder
  ///
  /// In en, this message translates to:
  /// **'Five-minute easy warm-up, fifteen minutes at tempo (comfortably hard), five-minute cool-down. The bread-and-butter weekly tempo session.'**
  String get guidedTempo25Description;

  /// Guided tempo-25 cue at 0:00
  ///
  /// In en, this message translates to:
  /// **'Warm-up time. Five minutes easy — wake up the legs.'**
  String get guidedTempo25Cue0;

  /// Guided tempo-25 cue at 4:00
  ///
  /// In en, this message translates to:
  /// **'One minute left in the warm-up. Pick up the cadence.'**
  String get guidedTempo25Cue1;

  /// Guided tempo-25 cue at 5:00
  ///
  /// In en, this message translates to:
  /// **'Lift it to tempo. Comfortably hard. Like a 10K race effort.'**
  String get guidedTempo25Cue2;

  /// Guided tempo-25 cue at 10:00
  ///
  /// In en, this message translates to:
  /// **'Five minutes in tempo. Strong but controlled. Keep the rhythm.'**
  String get guidedTempo25Cue3;

  /// Guided tempo-25 cue at 15:00
  ///
  /// In en, this message translates to:
  /// **'Ten minutes of tempo done. Hold the pace.'**
  String get guidedTempo25Cue4;

  /// Guided tempo-25 cue at 18:00
  ///
  /// In en, this message translates to:
  /// **'Two minutes left at tempo. Stay smooth.'**
  String get guidedTempo25Cue5;

  /// Guided tempo-25 cue at 20:00
  ///
  /// In en, this message translates to:
  /// **'Ease off. Five minutes easy to cool down.'**
  String get guidedTempo25Cue6;

  /// Guided tempo-25 cue at 23:00
  ///
  /// In en, this message translates to:
  /// **'Two to go. Bring the heart rate back down.'**
  String get guidedTempo25Cue7;

  /// Guided tempo-25 cue at 25:00
  ///
  /// In en, this message translates to:
  /// **'Done. Walk and stretch. Great work.'**
  String get guidedTempo25Cue8;

  /// Guided run title: first-timer 15-minute run/walk
  ///
  /// In en, this message translates to:
  /// **'First-Timer 15-Minute Run/Walk'**
  String get guidedFirst15Title;

  /// Guided run subtitle: first-timer 15-minute run/walk
  ///
  /// In en, this message translates to:
  /// **'Coach voice · 15 min · run/walk intervals'**
  String get guidedFirst15Subtitle;

  /// Guided run description: first-timer 15-minute run/walk
  ///
  /// In en, this message translates to:
  /// **'New to running? Three rounds of one-minute run, one-minute walk, plus a warm-up and cool-down. A gentle on-ramp; everyone starts here.'**
  String get guidedFirst15Description;

  /// Guided first-15 cue at 0:00
  ///
  /// In en, this message translates to:
  /// **'Start with a three-minute brisk walk to warm up.'**
  String get guidedFirst15Cue0;

  /// Guided first-15 cue at 3:00
  ///
  /// In en, this message translates to:
  /// **'Switch to a one-minute easy run. Conversational pace.'**
  String get guidedFirst15Cue1;

  /// Guided first-15 cue at 4:00
  ///
  /// In en, this message translates to:
  /// **'Walk one minute.'**
  String get guidedFirst15Cue2;

  /// Guided first-15 cue at 5:00
  ///
  /// In en, this message translates to:
  /// **'Run one minute.'**
  String get guidedFirst15Cue3;

  /// Guided first-15 cue at 6:00
  ///
  /// In en, this message translates to:
  /// **'Walk one minute.'**
  String get guidedFirst15Cue4;

  /// Guided first-15 cue at 7:00
  ///
  /// In en, this message translates to:
  /// **'Run one minute.'**
  String get guidedFirst15Cue5;

  /// Guided first-15 cue at 8:00
  ///
  /// In en, this message translates to:
  /// **'Walk one minute.'**
  String get guidedFirst15Cue6;

  /// Guided first-15 cue at 9:00
  ///
  /// In en, this message translates to:
  /// **'Run one minute — last one.'**
  String get guidedFirst15Cue7;

  /// Guided first-15 cue at 10:00
  ///
  /// In en, this message translates to:
  /// **'Walk it down. Five-minute cool-down.'**
  String get guidedFirst15Cue8;

  /// Guided first-15 cue at 14:00
  ///
  /// In en, this message translates to:
  /// **'One minute left. Walk easy.'**
  String get guidedFirst15Cue9;

  /// Guided first-15 cue at 15:00
  ///
  /// In en, this message translates to:
  /// **'Done. That was a real run. Get out there again soon.'**
  String get guidedFirst15Cue10;

  /// Duration badge on a guided-run card
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String guidedRunMinutesBadge(int minutes);

  /// Cue-count label on a guided-run card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} cue across the run} other{{count} cues across the run}}'**
  String guidedRunCueCount(int count);

  /// Section header above the cue list on the guided-run detail screen
  ///
  /// In en, this message translates to:
  /// **'THE FULL SCRIPT'**
  String get guidedRunFullScript;

  /// Tooltip on the preview-cue button
  ///
  /// In en, this message translates to:
  /// **'Preview cue'**
  String get guidedRunPreviewCue;

  /// Error banner when a cue preview fails
  ///
  /// In en, this message translates to:
  /// **'Could not preview: {error}'**
  String guidedRunPreviewError(String error);

  /// Unit word for a split cue: singular kilometre
  ///
  /// In en, this message translates to:
  /// **'kilometre'**
  String get ttsSplitUnitKilometre;

  /// Unit word for a split cue: plural kilometres
  ///
  /// In en, this message translates to:
  /// **'kilometres'**
  String get ttsSplitUnitKilometres;

  /// Unit word for a split cue: singular mile
  ///
  /// In en, this message translates to:
  /// **'mile'**
  String get ttsSplitUnitMile;

  /// Unit word for a split cue: plural miles
  ///
  /// In en, this message translates to:
  /// **'miles'**
  String get ttsSplitUnitMiles;

  /// Training workout kind label: easy run
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get workoutKindEasy;

  /// Training workout kind label: long run
  ///
  /// In en, this message translates to:
  /// **'Long run'**
  String get workoutKindLong;

  /// Training workout kind label: recovery run
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get workoutKindRecovery;

  /// Training workout kind label: tempo run
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get workoutKindTempo;

  /// Training workout kind label: interval session
  ///
  /// In en, this message translates to:
  /// **'Intervals'**
  String get workoutKindInterval;

  /// Training workout kind label: marathon-pace run
  ///
  /// In en, this message translates to:
  /// **'Marathon pace'**
  String get workoutKindMarathonPace;

  /// Training workout kind label: walk-run
  ///
  /// In en, this message translates to:
  /// **'Walk-run'**
  String get workoutKindWalkRun;

  /// Training workout kind label: race
  ///
  /// In en, this message translates to:
  /// **'Race'**
  String get workoutKindRace;

  /// Training workout kind label: rest day
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get workoutKindRest;

  /// Training plan phase label: base
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get planPhaseBase;

  /// Training plan phase label: build
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get planPhaseBuild;

  /// Training plan phase label: peak
  ///
  /// In en, this message translates to:
  /// **'Peak'**
  String get planPhasePeak;

  /// Training plan phase label: taper
  ///
  /// In en, this message translates to:
  /// **'Taper'**
  String get planPhaseTaper;

  /// Training plan phase label: race week
  ///
  /// In en, this message translates to:
  /// **'Race week'**
  String get planPhaseRace;

  /// Title of the dialog nudging Android users to grant always-on location before a run
  ///
  /// In en, this message translates to:
  /// **'Allow location all the time'**
  String get runBackgroundLocationNudgeTitle;

  /// Body of the background-location nudge dialog shown before a run on Android
  ///
  /// In en, this message translates to:
  /// **'Android only granted location while the app is open. For accurate distance when your screen is off, set location access to \"Allow all the time\" in Settings. You can start anyway — recording still works while the app is on screen.'**
  String get runBackgroundLocationNudgeBody;

  /// Title of the one-time battery-optimisation hint dialog shown before a run on Android
  ///
  /// In en, this message translates to:
  /// **'Keep recording alive in the background'**
  String get runBatteryOptHintTitle;

  /// Body of the battery-optimisation hint dialog shown before a run on Android
  ///
  /// In en, this message translates to:
  /// **'Some phones (Samsung, Xiaomi, OnePlus and others) put apps to sleep to save battery, which can stop a long run from recording when your screen is off. To be safe, exclude this app from battery optimisation in Settings. Your run will record either way — this just stops the system from cutting it short.'**
  String get runBatteryOptHintBody;

  /// Share text accompanying a run share image or exported file: title, distance, and duration
  ///
  /// In en, this message translates to:
  /// **'{title} — {distance} in {duration}'**
  String shareCardCaption(Object title, Object distance, Object duration);

  /// Banner shown when a settings action needs a configured backend but none is available
  ///
  /// In en, this message translates to:
  /// **'Backend not configured'**
  String get settingsBackendNotConfigured;

  /// Account settings tile subtitle shown when signed in but no email address is available
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get settingsAccountSignedIn;

  /// Devices settings tile subtitle shown when signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage your devices'**
  String get settingsDevicesSignedOutSubtitle;

  /// Tooltip on the verified-club badge
  ///
  /// In en, this message translates to:
  /// **'Official verified club'**
  String get verifiedClubTooltip;

  /// Best-effort race distance label: 5 kilometres
  ///
  /// In en, this message translates to:
  /// **'5 km'**
  String get raceDistance5k;

  /// Best-effort race distance label: 10 kilometres
  ///
  /// In en, this message translates to:
  /// **'10 km'**
  String get raceDistance10k;

  /// Best-effort race distance label: half marathon
  ///
  /// In en, this message translates to:
  /// **'Half Marathon'**
  String get raceDistanceHalfMarathon;

  /// Best-effort race distance label: marathon
  ///
  /// In en, this message translates to:
  /// **'Marathon'**
  String get raceDistanceMarathon;

  /// Settings landing: Account tile subtitle when signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in, backup, delete account'**
  String get settingsTabAccountSubtitle;

  /// Settings landing: Preferences tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Units, theme, recording, training, privacy'**
  String get settingsTabPreferencesSubtitle;

  /// Settings landing: Integrations tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Strava, parkrun, heart-rate strap'**
  String get settingsTabIntegrationsSubtitle;

  /// Settings landing: Devices tile subtitle when signed in
  ///
  /// In en, this message translates to:
  /// **'Where you\'re signed in and per-device overrides'**
  String get settingsTabDevicesSubtitle;

  /// Settings landing: Gear tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Track shoes + bikes and per-item mileage'**
  String get settingsTabGearSubtitle;

  /// Settings landing: Coaching tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Coach athletes or follow your own coach'**
  String get settingsTabCoachingSubtitle;

  /// Settings landing: Pro & support tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Subscribe, restore purchases, manage billing'**
  String get settingsTabProSubtitle;

  /// Settings landing: Licenses tile subtitle
  ///
  /// In en, this message translates to:
  /// **'App version and open-source notices'**
  String get settingsTabLicensesSubtitle;

  /// Period-summary title for a single week, e.g. 'Week of 13 Apr'
  ///
  /// In en, this message translates to:
  /// **'Week of {date}'**
  String periodSummaryWeekOf(Object date);

  /// Run count line in the period-summary share text
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 run} other{{count} runs}}'**
  String periodShareRunCount(int count);

  /// Average-pace line in the period-summary share text
  ///
  /// In en, this message translates to:
  /// **'Avg pace: {pace}'**
  String periodShareAvgPace(Object pace);

  /// No description provided for @gymTitle.
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get gymTitle;

  /// No description provided for @gymLog.
  ///
  /// In en, this message translates to:
  /// **'Log workout'**
  String get gymLog;

  /// No description provided for @gymUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled workout'**
  String get gymUntitled;

  /// No description provided for @gymOfflineCached.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing saved workouts'**
  String get gymOfflineCached;

  /// No description provided for @gymOfflineQueued.
  ///
  /// In en, this message translates to:
  /// **'Offline — changes will sync when you reconnect'**
  String get gymOfflineQueued;

  /// No description provided for @gymEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No gym workouts yet'**
  String get gymEmptyTitle;

  /// No description provided for @gymEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Log a lift to track it here and feed your training load.'**
  String get gymEmptyBody;

  /// No description provided for @gymPrBadge.
  ///
  /// In en, this message translates to:
  /// **'PR'**
  String get gymPrBadge;

  /// Exercise count on a gym workout row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} exercise} other{{count} exercises}}'**
  String gymExercisesShort(int count);

  /// Total working volume (kg) on a gym workout row
  ///
  /// In en, this message translates to:
  /// **'{volume} kg'**
  String gymVolumeShort(int volume);

  /// No description provided for @gymNotFound.
  ///
  /// In en, this message translates to:
  /// **'Workout not found.'**
  String get gymNotFound;

  /// No description provided for @gymEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get gymEdit;

  /// No description provided for @gymDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gymDelete;

  /// Visibility chip on the gym workout detail when the workout is shared publicly.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get gymPublic;

  /// Visibility chip on the gym workout detail when the workout is private.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get gymPrivate;

  /// Action that flips a gym workout to public.
  ///
  /// In en, this message translates to:
  /// **'Make public'**
  String get gymMakePublic;

  /// Action that flips a gym workout back to private.
  ///
  /// In en, this message translates to:
  /// **'Make private'**
  String get gymMakePrivate;

  /// Banner when toggling a gym workout's visibility fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update visibility: {error}'**
  String gymVisibilityFailed(Object error);

  /// Banner when deleting a gym workout fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the workout: {error}'**
  String gymDeleteFailed(Object error);

  /// No description provided for @gymNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get gymNotes;

  /// No description provided for @gymKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get gymKg;

  /// No description provided for @gymReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get gymReps;

  /// No description provided for @gymRpe.
  ///
  /// In en, this message translates to:
  /// **'RPE'**
  String get gymRpe;

  /// No description provided for @gymDuration.
  ///
  /// In en, this message translates to:
  /// **'Time (s)'**
  String get gymDuration;

  /// A set's hold/interval time in seconds
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String gymDurationValue(String seconds);

  /// Set ordinal label in a gym workout
  ///
  /// In en, this message translates to:
  /// **'Set {n}'**
  String gymSetN(int n);

  /// No description provided for @gymPrWeight.
  ///
  /// In en, this message translates to:
  /// **'Heaviest'**
  String get gymPrWeight;

  /// No description provided for @gymPrVolume.
  ///
  /// In en, this message translates to:
  /// **'Top volume'**
  String get gymPrVolume;

  /// No description provided for @gymPrE1rm.
  ///
  /// In en, this message translates to:
  /// **'Best est. 1RM'**
  String get gymPrE1rm;

  /// No description provided for @gymRecordsLink.
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get gymRecordsLink;

  /// No description provided for @gymRecordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal records'**
  String get gymRecordsTitle;

  /// No description provided for @gymRecordsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your best lift for every weighted exercise.'**
  String get gymRecordsSubtitle;

  /// No description provided for @gymRecordsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No weighted lifts logged yet. Add a weight to a set to start tracking your bests.'**
  String get gymRecordsEmpty;

  /// Records card: when an exercise was last performed
  ///
  /// In en, this message translates to:
  /// **'Last {date}'**
  String gymRecordsLastDone(String date);

  /// Records card: distinct session count for an exercise
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 session} other{{count} sessions}}'**
  String gymRecordsSessions(int count);

  /// No description provided for @gymExerciseBack.
  ///
  /// In en, this message translates to:
  /// **'Back to records'**
  String get gymExerciseBack;

  /// No description provided for @gymExerciseEmpty.
  ///
  /// In en, this message translates to:
  /// **'No history for this exercise yet.'**
  String get gymExerciseEmpty;

  /// Exercise progression: est-1RM gain since first session
  ///
  /// In en, this message translates to:
  /// **'up {delta} since first session'**
  String gymSinceFirstUp(String delta);

  /// Exercise progression: est-1RM loss since first session
  ///
  /// In en, this message translates to:
  /// **'down {delta} since first session'**
  String gymSinceFirstDown(String delta);

  /// No description provided for @gymSinceFirstFlat.
  ///
  /// In en, this message translates to:
  /// **'no change since first session'**
  String get gymSinceFirstFlat;

  /// Workout detail: vs-last-time hint date for an exercise
  ///
  /// In en, this message translates to:
  /// **'Last time {date}'**
  String gymDetailLastTime(String date);

  /// No description provided for @gymVolumeLabel.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get gymVolumeLabel;

  /// No description provided for @gymDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete workout?'**
  String get gymDeleteConfirmTitle;

  /// No description provided for @gymDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the workout and its sets.'**
  String get gymDeleteConfirmBody;

  /// Badge on an event detail page shown when the event is members-only (events.is_public = false).
  ///
  /// In en, this message translates to:
  /// **'Members only'**
  String get clubEventMembersOnly;

  /// Button on a class event detail that opens the gym composer pre-filled from the class's gym_template.
  ///
  /// In en, this message translates to:
  /// **'Log this as a workout'**
  String get clubEventLogAsWorkout;

  /// Helper text under the log-as-workout button explaining the inform-tier behaviour.
  ///
  /// In en, this message translates to:
  /// **'Add this class to your own gym log — you can adjust the details before saving.'**
  String get clubEventLogAsWorkoutHint;

  /// Confirmation banner shown after the user saves the class as a gym workout.
  ///
  /// In en, this message translates to:
  /// **'Added to your gym log'**
  String get clubEventLogAsWorkoutSaved;

  /// Tooltip / title for the action that opens a finisher's downloadable certificate.
  ///
  /// In en, this message translates to:
  /// **'Finisher certificate'**
  String get clubEventDownloadCertificate;

  /// Button that captures the finisher certificate and opens the OS share sheet.
  ///
  /// In en, this message translates to:
  /// **'Save or share'**
  String get clubEventCertificateShare;

  /// Caption attached when sharing a finisher certificate image.
  ///
  /// In en, this message translates to:
  /// **'I finished {event}!'**
  String clubEventCertificateShareText(String event);

  /// Error banner when the finisher certificate image fails to render.
  ///
  /// In en, this message translates to:
  /// **'Could not generate the certificate. Please try again.'**
  String get clubEventCertificateFailed;

  /// Headline printed on the finisher certificate.
  ///
  /// In en, this message translates to:
  /// **'Certificate of Completion'**
  String get clubEventCertificateHeading;

  /// Line above the finisher's name on the certificate.
  ///
  /// In en, this message translates to:
  /// **'This certifies that'**
  String get clubEventCertificateCertifies;

  /// Line above the event title on the certificate.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get clubEventCertificateCompleted;

  /// Label before the finish time in the certificate's stat row.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get clubEventCertificateTime;

  /// Label before the distance in the certificate's stat row.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get clubEventCertificateDistance;

  /// Placing entry in the certificate's stat row, e.g. '3rd place'.
  ///
  /// In en, this message translates to:
  /// **'{place} place'**
  String clubEventCertificatePlace(String place);

  /// No description provided for @gymEditorNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New workout'**
  String get gymEditorNewTitle;

  /// No description provided for @gymEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit workout'**
  String get gymEditorEditTitle;

  /// No description provided for @gymEditorTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get gymEditorTitleLabel;

  /// No description provided for @gymEditorTitlePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Push day'**
  String get gymEditorTitlePlaceholder;

  /// No description provided for @gymEditorExercisePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Exercise name'**
  String get gymEditorExercisePlaceholder;

  /// No description provided for @gymEditorRemoveExercise.
  ///
  /// In en, this message translates to:
  /// **'Remove exercise'**
  String get gymEditorRemoveExercise;

  /// No description provided for @gymEditorRemoveSet.
  ///
  /// In en, this message translates to:
  /// **'Remove set'**
  String get gymEditorRemoveSet;

  /// No description provided for @gymEditorAddSet.
  ///
  /// In en, this message translates to:
  /// **'Add set'**
  String get gymEditorAddSet;

  /// No description provided for @gymEditorAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add exercise'**
  String get gymEditorAddExercise;

  /// No description provided for @gymEditorShare.
  ///
  /// In en, this message translates to:
  /// **'Share to feed'**
  String get gymEditorShare;

  /// No description provided for @gymEditorCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gymEditorCancel;

  /// No description provided for @gymEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save workout'**
  String get gymEditorSave;

  /// No description provided for @gymEditorNeedExercise.
  ///
  /// In en, this message translates to:
  /// **'Add at least one exercise with a name.'**
  String get gymEditorNeedExercise;

  /// No description provided for @gymCatalogueBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse catalogue'**
  String get gymCatalogueBrowse;

  /// No description provided for @gymCatalogueTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercise catalogue'**
  String get gymCatalogueTitle;

  /// No description provided for @gymCatalogueSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search exercises'**
  String get gymCatalogueSearchPlaceholder;

  /// No description provided for @gymCatalogueCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get gymCatalogueCategoryLabel;

  /// No description provided for @gymCatalogueEmpty.
  ///
  /// In en, this message translates to:
  /// **'No exercises match.'**
  String get gymCatalogueEmpty;

  /// No description provided for @gymCatalogueCustomBadge.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get gymCatalogueCustomBadge;

  /// Create-custom affordance in the exercise catalogue picker
  ///
  /// In en, this message translates to:
  /// **'Add “{name}” as a custom exercise'**
  String gymCatalogueCreate(String name);

  /// No description provided for @gymCatalogueCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add that exercise.'**
  String get gymCatalogueCreateFailed;

  /// No description provided for @gymCatalogueCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get gymCatalogueCategoryAll;

  /// No description provided for @gymCatalogueCategoryChest.
  ///
  /// In en, this message translates to:
  /// **'Chest'**
  String get gymCatalogueCategoryChest;

  /// No description provided for @gymCatalogueCategoryBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get gymCatalogueCategoryBack;

  /// No description provided for @gymCatalogueCategoryShoulders.
  ///
  /// In en, this message translates to:
  /// **'Shoulders'**
  String get gymCatalogueCategoryShoulders;

  /// No description provided for @gymCatalogueCategoryLegs.
  ///
  /// In en, this message translates to:
  /// **'Legs'**
  String get gymCatalogueCategoryLegs;

  /// No description provided for @gymCatalogueCategoryArms.
  ///
  /// In en, this message translates to:
  /// **'Arms'**
  String get gymCatalogueCategoryArms;

  /// No description provided for @gymCatalogueCategoryCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get gymCatalogueCategoryCore;

  /// No description provided for @gymCatalogueCategoryCardio.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get gymCatalogueCategoryCardio;

  /// No description provided for @gymCatalogueCategoryFullBody.
  ///
  /// In en, this message translates to:
  /// **'Full body'**
  String get gymCatalogueCategoryFullBody;

  /// No description provided for @gymCatalogueCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get gymCatalogueCategoryOther;

  /// No description provided for @gymSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save workout.'**
  String get gymSaveFailed;

  /// No description provided for @gymRoutineLink.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get gymRoutineLink;

  /// No description provided for @gymRoutineTitle.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get gymRoutineTitle;

  /// No description provided for @gymRoutineNew.
  ///
  /// In en, this message translates to:
  /// **'New routine'**
  String get gymRoutineNew;

  /// No description provided for @gymRoutineBack.
  ///
  /// In en, this message translates to:
  /// **'Back to routines'**
  String get gymRoutineBack;

  /// No description provided for @gymRoutineNotFound.
  ///
  /// In en, this message translates to:
  /// **'Routine not found.'**
  String get gymRoutineNotFound;

  /// Exercise count on a routine card / detail header
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} exercise} other{{count} exercises}}'**
  String gymRoutineExerciseCount(int count);

  /// No description provided for @gymRoutineStart.
  ///
  /// In en, this message translates to:
  /// **'Start routine'**
  String get gymRoutineStart;

  /// Label above the publish-as-template control on the routine detail screen
  ///
  /// In en, this message translates to:
  /// **'Publish to a club'**
  String get gymRoutinePublishLabel;

  /// Placeholder option in the publish-to-club dropdown
  ///
  /// In en, this message translates to:
  /// **'Pick a club…'**
  String get gymRoutinePublishPick;

  /// Button that publishes a personal routine as a club template
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get gymRoutinePublish;

  /// Confirmation after publishing a routine as a club template
  ///
  /// In en, this message translates to:
  /// **'Routine published to the club.'**
  String get gymRoutinePublishSuccess;

  /// Error after a failed publish-as-template
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t publish the routine.'**
  String get gymRoutinePublishFailed;

  /// Badge shown on a routine that is already a club-owned template
  ///
  /// In en, this message translates to:
  /// **'Club template'**
  String get gymRoutineClubTemplateBadge;

  /// Badge shown on a routine that is published to the public library
  ///
  /// In en, this message translates to:
  /// **'In the public library'**
  String get gymRoutinePublicBadge;

  /// Label above the public publish/unpublish control on the routine detail screen
  ///
  /// In en, this message translates to:
  /// **'Public library'**
  String get gymRoutinePublishPublicLabel;

  /// Button that publishes a personal routine to the public library
  ///
  /// In en, this message translates to:
  /// **'Publish to public library'**
  String get gymRoutinePublishPublic;

  /// Button that removes a routine from the public library
  ///
  /// In en, this message translates to:
  /// **'Remove from public library'**
  String get gymRoutineUnpublishPublic;

  /// Hint under the public-library publish control
  ///
  /// In en, this message translates to:
  /// **'Anyone signed in can preview and adopt this routine. Logged workouts stay private.'**
  String get gymRoutinePublishPublicHint;

  /// Confirmation after publishing a routine to the public library
  ///
  /// In en, this message translates to:
  /// **'Routine published to the public library.'**
  String get gymRoutinePublishPublicSuccess;

  /// Confirmation after removing a routine from the public library
  ///
  /// In en, this message translates to:
  /// **'Routine removed from the public library.'**
  String get gymRoutineUnpublishPublicSuccess;

  /// Error after a failed public-library visibility toggle
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update public visibility.'**
  String get gymRoutinePublishPublicFailed;

  /// Action that opens the public routine library
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get gymLibraryLink;

  /// App bar title of the public routine library
  ///
  /// In en, this message translates to:
  /// **'Public routine library'**
  String get gymLibraryTitle;

  /// Placeholder in the public routine library search field
  ///
  /// In en, this message translates to:
  /// **'Search routines by name'**
  String get gymLibrarySearchHint;

  /// Error state in the public routine library
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the library.'**
  String get gymLibraryLoadError;

  /// Empty state when the public routine library has no routines
  ///
  /// In en, this message translates to:
  /// **'No published routines yet.'**
  String get gymLibraryEmpty;

  /// Empty state when a public routine library search returns nothing
  ///
  /// In en, this message translates to:
  /// **'No routines match \"{query}\".'**
  String gymLibraryEmptySearch(String query);

  /// Attribution line on a public routine library entry
  ///
  /// In en, this message translates to:
  /// **'by {author}'**
  String gymLibraryByAuthor(String author);

  /// Fallback author name when a public routine's author has no display name
  ///
  /// In en, this message translates to:
  /// **'a lifter'**
  String get gymLibraryAnonymous;

  /// Button that clones a public routine into the viewer's library
  ///
  /// In en, this message translates to:
  /// **'Adopt into my routines'**
  String get gymLibraryAdopt;

  /// Busy label while adopting a public routine
  ///
  /// In en, this message translates to:
  /// **'Adopting…'**
  String get gymLibraryAdopting;

  /// Error after a failed public-routine adopt
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t adopt the routine.'**
  String get gymLibraryAdoptFailed;

  /// No description provided for @gymRoutineDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gymRoutineDelete;

  /// No description provided for @gymRoutineDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete routine?'**
  String get gymRoutineDeleteConfirmTitle;

  /// No description provided for @gymRoutineDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the routine. Logged workouts are unaffected.'**
  String get gymRoutineDeleteConfirmBody;

  /// No description provided for @gymRoutineDeleted.
  ///
  /// In en, this message translates to:
  /// **'Routine deleted'**
  String get gymRoutineDeleted;

  /// No description provided for @gymRoutineCreated.
  ///
  /// In en, this message translates to:
  /// **'Routine saved'**
  String get gymRoutineCreated;

  /// No description provided for @gymRoutineSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save routine.'**
  String get gymRoutineSaveFailed;

  /// No description provided for @gymRoutineEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No routines yet'**
  String get gymRoutineEmptyTitle;

  /// No description provided for @gymRoutineEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Save a logged workout as a routine, or build one from scratch, to reuse it.'**
  String get gymRoutineEmptyBody;

  /// No description provided for @gymRoutineTargetReps.
  ///
  /// In en, this message translates to:
  /// **'Target reps'**
  String get gymRoutineTargetReps;

  /// Routine builder/detail: target weight column header with unit
  ///
  /// In en, this message translates to:
  /// **'Target weight ({unit})'**
  String gymRoutineTargetWeight(String unit);

  /// No description provided for @gymRoutineEditorNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New routine'**
  String get gymRoutineEditorNewTitle;

  /// No description provided for @gymRoutineEditorTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Routine name'**
  String get gymRoutineEditorTitleLabel;

  /// No description provided for @gymRoutineEditorTitlePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Push day A'**
  String get gymRoutineEditorTitlePlaceholder;

  /// No description provided for @gymRoutineEditorNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get gymRoutineEditorNotesLabel;

  /// No description provided for @gymRoutineEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save routine'**
  String get gymRoutineEditorSave;

  /// No description provided for @gymRoutineEditorCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gymRoutineEditorCancel;

  /// No description provided for @gymRoutineEditorNeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Give the routine a name.'**
  String get gymRoutineEditorNeedTitle;

  /// No description provided for @gymRoutineEditorNeedExercise.
  ///
  /// In en, this message translates to:
  /// **'Add at least one exercise with a name.'**
  String get gymRoutineEditorNeedExercise;

  /// No description provided for @gymRoutineSaveAsRoutine.
  ///
  /// In en, this message translates to:
  /// **'Save as routine'**
  String get gymRoutineSaveAsRoutine;

  /// No description provided for @gymRoutineRepeatLast.
  ///
  /// In en, this message translates to:
  /// **'Repeat last'**
  String get gymRoutineRepeatLast;

  /// No description provided for @gymRoutineTargetRepsMax.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get gymRoutineTargetRepsMax;

  /// No description provided for @gymRoutineTargetDuration.
  ///
  /// In en, this message translates to:
  /// **'Target time (s)'**
  String get gymRoutineTargetDuration;

  /// No description provided for @gymRoutineTargetDistance.
  ///
  /// In en, this message translates to:
  /// **'Target distance (m)'**
  String get gymRoutineTargetDistance;

  /// No description provided for @gymRoutineRestLabel.
  ///
  /// In en, this message translates to:
  /// **'Rest (s)'**
  String get gymRoutineRestLabel;

  /// No description provided for @gymRoutineSetType.
  ///
  /// In en, this message translates to:
  /// **'Set type'**
  String get gymRoutineSetType;

  /// No description provided for @gymRoutineSetTypeWarmup.
  ///
  /// In en, this message translates to:
  /// **'Warm-up'**
  String get gymRoutineSetTypeWarmup;

  /// No description provided for @gymRoutineSetTypeWorking.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get gymRoutineSetTypeWorking;

  /// No description provided for @gymRoutineSetTypeDropset.
  ///
  /// In en, this message translates to:
  /// **'Drop set'**
  String get gymRoutineSetTypeDropset;

  /// No description provided for @gymRoutineSetTypeAmrap.
  ///
  /// In en, this message translates to:
  /// **'AMRAP'**
  String get gymRoutineSetTypeAmrap;

  /// No description provided for @gymRoutineSetTypeFailure.
  ///
  /// In en, this message translates to:
  /// **'To failure'**
  String get gymRoutineSetTypeFailure;

  /// No description provided for @gymRoutineSetTypeBackoff.
  ///
  /// In en, this message translates to:
  /// **'Back-off'**
  String get gymRoutineSetTypeBackoff;

  /// No description provided for @gymRoutineModality.
  ///
  /// In en, this message translates to:
  /// **'Measured by'**
  String get gymRoutineModality;

  /// No description provided for @gymRoutineModalityWeightReps.
  ///
  /// In en, this message translates to:
  /// **'Weight × reps'**
  String get gymRoutineModalityWeightReps;

  /// No description provided for @gymRoutineModalityTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get gymRoutineModalityTime;

  /// No description provided for @gymRoutineModalityDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get gymRoutineModalityDistance;

  /// No description provided for @gymRoutineModalityBodyweightReps.
  ///
  /// In en, this message translates to:
  /// **'Bodyweight reps'**
  String get gymRoutineModalityBodyweightReps;

  /// No description provided for @gymRoutineSupersetToggle.
  ///
  /// In en, this message translates to:
  /// **'Superset with the next exercise'**
  String get gymRoutineSupersetToggle;

  /// Routine detail: superset group badge
  ///
  /// In en, this message translates to:
  /// **'Superset {group}'**
  String gymRoutineSupersetBadge(int group);

  /// No description provided for @gymRoutineAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get gymRoutineAdvanced;

  /// No description provided for @gymRoutineProgression.
  ///
  /// In en, this message translates to:
  /// **'Progression'**
  String get gymRoutineProgression;

  /// No description provided for @gymRoutineProgressionNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get gymRoutineProgressionNone;

  /// No description provided for @gymRoutineProgressionLinear.
  ///
  /// In en, this message translates to:
  /// **'Linear'**
  String get gymRoutineProgressionLinear;

  /// No description provided for @gymRoutineProgressionDoubleProgression.
  ///
  /// In en, this message translates to:
  /// **'Double progression'**
  String get gymRoutineProgressionDoubleProgression;

  /// No description provided for @gymRoutineProgressionFiveByFive.
  ///
  /// In en, this message translates to:
  /// **'5×5'**
  String get gymRoutineProgressionFiveByFive;

  /// No description provided for @gymRoutineProgressionPercentCycle.
  ///
  /// In en, this message translates to:
  /// **'% of 1RM cycle'**
  String get gymRoutineProgressionPercentCycle;

  /// No description provided for @gymRoutineProgressionRpeAutoreg.
  ///
  /// In en, this message translates to:
  /// **'RPE auto-regulation'**
  String get gymRoutineProgressionRpeAutoreg;

  /// Routine builder: progression weight increment field, with unit
  ///
  /// In en, this message translates to:
  /// **'Weight step ({unit})'**
  String gymRoutineProgressionIncrementLabel(String unit);

  /// No description provided for @gymRoutineProgressionPercentLabel.
  ///
  /// In en, this message translates to:
  /// **'% of 1RM'**
  String get gymRoutineProgressionPercentLabel;

  /// Routine builder: progression 1RM field, with unit
  ///
  /// In en, this message translates to:
  /// **'1RM ({unit})'**
  String gymRoutineProgressionOneRmLabel(String unit);

  /// No description provided for @gymRoutineProgressionTargetRpeLabel.
  ///
  /// In en, this message translates to:
  /// **'Target RPE'**
  String get gymRoutineProgressionTargetRpeLabel;

  /// No description provided for @gymRoutineNextTarget.
  ///
  /// In en, this message translates to:
  /// **'Next target'**
  String get gymRoutineNextTarget;

  /// No description provided for @gymRoutineNextTargetIncreaseWeight.
  ///
  /// In en, this message translates to:
  /// **'Add load next time'**
  String get gymRoutineNextTargetIncreaseWeight;

  /// No description provided for @gymRoutineNextTargetIncreaseReps.
  ///
  /// In en, this message translates to:
  /// **'Add reps next time'**
  String get gymRoutineNextTargetIncreaseReps;

  /// No description provided for @gymRoutineNextTargetHold.
  ///
  /// In en, this message translates to:
  /// **'Hold — repeat this target'**
  String get gymRoutineNextTargetHold;

  /// No description provided for @gymRoutineNextTargetEstablishBaseline.
  ///
  /// In en, this message translates to:
  /// **'Establish baseline — set a starting weight'**
  String get gymRoutineNextTargetEstablishBaseline;

  /// No description provided for @gymRoutineNextTargetDeload.
  ///
  /// In en, this message translates to:
  /// **'Deload — back off the load'**
  String get gymRoutineNextTargetDeload;

  /// Workout review: next-target rep-climb delta
  ///
  /// In en, this message translates to:
  /// **'rep climb {from}→{to}'**
  String gymRoutineNextTargetRepClimb(int from, int to);

  /// No description provided for @nutritionTitle.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get nutritionTitle;

  /// No description provided for @nutritionLogFood.
  ///
  /// In en, this message translates to:
  /// **'Log food'**
  String get nutritionLogFood;

  /// No description provided for @nutritionCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get nutritionCalories;

  /// No description provided for @nutritionProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get nutritionProtein;

  /// No description provided for @nutritionCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get nutritionCarbs;

  /// No description provided for @nutritionFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get nutritionFat;

  /// No description provided for @nutritionWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get nutritionWater;

  /// No description provided for @nutritionWaterAdd.
  ///
  /// In en, this message translates to:
  /// **'Add water'**
  String get nutritionWaterAdd;

  /// No description provided for @nutritionWaterRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove water'**
  String get nutritionWaterRemove;

  /// No description provided for @nutritionNoTargets.
  ///
  /// In en, this message translates to:
  /// **'Add your height, weight, age and sex on the web app to see calorie + macro targets.'**
  String get nutritionNoTargets;

  /// No description provided for @nutritionWeeklyTrend.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get nutritionWeeklyTrend;

  /// Calorie budget chip: kcal still to eat
  ///
  /// In en, this message translates to:
  /// **'{n} kcal left'**
  String nutritionCaloriesLeft(int n);

  /// Calorie budget chip: kcal over the ceiling
  ///
  /// In en, this message translates to:
  /// **'{n} kcal over'**
  String nutritionCaloriesOver(int n);

  /// No description provided for @nutritionOnTarget.
  ///
  /// In en, this message translates to:
  /// **'On target'**
  String get nutritionOnTarget;

  /// Macro ring badge: amount over a ceiling macro
  ///
  /// In en, this message translates to:
  /// **'{n} over target'**
  String nutritionMacroOver(int n);

  /// No description provided for @nutritionMacroReached.
  ///
  /// In en, this message translates to:
  /// **'Target reached'**
  String get nutritionMacroReached;

  /// Water card readout: consumed / target litres
  ///
  /// In en, this message translates to:
  /// **'{consumed} / {target} L'**
  String nutritionWaterAmount(String consumed, String target);

  /// No description provided for @nutritionWaterGoalReached.
  ///
  /// In en, this message translates to:
  /// **'Goal reached'**
  String get nutritionWaterGoalReached;

  /// Water budget chip: ml still to drink
  ///
  /// In en, this message translates to:
  /// **'{n} ml left'**
  String nutritionWaterRemaining(int n);

  /// No description provided for @nutritionWeekOnGoal.
  ///
  /// In en, this message translates to:
  /// **'On goal'**
  String get nutritionWeekOnGoal;

  /// Weekly trend chip: avg kcal under the daily goal
  ///
  /// In en, this message translates to:
  /// **'{n} under goal/day'**
  String nutritionWeekUnderGoal(int n);

  /// Weekly trend chip: avg kcal over the daily goal
  ///
  /// In en, this message translates to:
  /// **'{n} over goal/day'**
  String nutritionWeekOverGoal(int n);

  /// Weekly trend chip: logged days that hit the protein goal, out of total logged days
  ///
  /// In en, this message translates to:
  /// **'Protein {met}/{total} days'**
  String nutritionWeekProtein(int met, int total);

  /// No description provided for @nutritionGoalLine.
  ///
  /// In en, this message translates to:
  /// **'Daily goal'**
  String get nutritionGoalLine;

  /// Calorie goal breakdown: base goal + exercise kcal added today
  ///
  /// In en, this message translates to:
  /// **'Goal {base} + {exercise} kcal burned today'**
  String nutritionGoalBreakdown(int base, int exercise);

  /// No description provided for @dashGymReadinessIncluded.
  ///
  /// In en, this message translates to:
  /// **'Recent gym sessions are factored into your fatigue.'**
  String get dashGymReadinessIncluded;

  /// No description provided for @dashGymReadinessExcluded.
  ///
  /// In en, this message translates to:
  /// **'Gym load is excluded from your run readiness.'**
  String get dashGymReadinessExcluded;

  /// No description provided for @prefsExcludeGymFromReadiness.
  ///
  /// In en, this message translates to:
  /// **'Exclude gym load from run readiness'**
  String get prefsExcludeGymFromReadiness;

  /// No description provided for @prefsExcludeGymFromReadinessHint.
  ///
  /// In en, this message translates to:
  /// **'By default, gym sessions add to your fatigue and lower your readiness, like a run. Turn this on to keep your fitness, fatigue and form based on runs only.'**
  String get prefsExcludeGymFromReadinessHint;

  /// No description provided for @nutritionEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No food logged today'**
  String get nutritionEmptyTitle;

  /// No description provided for @nutritionEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Log a meal to track your calories and macros.'**
  String get nutritionEmptyBody;

  /// No description provided for @nutritionSlotBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get nutritionSlotBreakfast;

  /// No description provided for @nutritionSlotLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get nutritionSlotLunch;

  /// No description provided for @nutritionSlotDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get nutritionSlotDinner;

  /// No description provided for @nutritionSlotSnack.
  ///
  /// In en, this message translates to:
  /// **'Snack'**
  String get nutritionSlotSnack;

  /// Per-meal nutrition detail screen
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get nutritionMealProtein;

  /// Per-meal nutrition detail screen
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get nutritionMealCarbs;

  /// Per-meal nutrition detail screen
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get nutritionMealFat;

  /// Per-meal nutrition detail screen
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get nutritionMealItemsHeading;

  /// Per-meal nutrition detail screen
  ///
  /// In en, this message translates to:
  /// **'Nothing logged for this meal.'**
  String get nutritionMealNoItems;

  /// Per-meal nutrition detail screen
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get nutritionMealTrendHeading;

  /// No description provided for @nutritionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get nutritionDelete;

  /// No description provided for @nutritionDeleteEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry?'**
  String get nutritionDeleteEntryTitle;

  /// Confirm dialog body before deleting a logged food entry
  ///
  /// In en, this message translates to:
  /// **'{item} will be removed from today\'s log.'**
  String nutritionDeleteEntryMessage(String item);

  /// Banner when deleting a logged food entry fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t delete the entry: {error}'**
  String nutritionDeleteFailed(String error);

  /// No description provided for @nutritionOfflineQueued.
  ///
  /// In en, this message translates to:
  /// **'Offline — changes will sync when you reconnect'**
  String get nutritionOfflineQueued;

  /// No description provided for @nutritionOfflineCached.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing saved entries'**
  String get nutritionOfflineCached;

  /// No description provided for @nutritionLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Log food'**
  String get nutritionLogTitle;

  /// No description provided for @nutritionSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a food'**
  String get nutritionSearchHint;

  /// No description provided for @nutritionSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get nutritionSearching;

  /// No description provided for @nutritionNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matches. Try another term or enter it manually below.'**
  String get nutritionNoResults;

  /// No description provided for @nutritionSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed. Check your connection, then retry or enter it manually below.'**
  String get nutritionSearchFailed;

  /// No description provided for @nutritionSearchRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry search'**
  String get nutritionSearchRetry;

  /// Source label on a food-search result that came from the Open Food Facts database. A brand name; not translated.
  ///
  /// In en, this message translates to:
  /// **'Open Food Facts'**
  String get nutritionSourceOff;

  /// Source label on a food-search result that came from USDA FoodData Central. A brand name; not translated.
  ///
  /// In en, this message translates to:
  /// **'USDA'**
  String get nutritionSourceUsda;

  /// Label/tooltip for the camera barcode-scan action in the nutrition log composer.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get nutritionScanBarcode;

  /// Guidance shown on the barcode scanner screen while waiting for a scan.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a product barcode'**
  String get nutritionScanHint;

  /// Shown while a scanned barcode is being looked up in the food database.
  ///
  /// In en, this message translates to:
  /// **'Looking up…'**
  String get nutritionScanLookingUp;

  /// Shown when a scanned barcode has no matching product in the food database.
  ///
  /// In en, this message translates to:
  /// **'No product found for that barcode. Try a search or enter it manually.'**
  String get nutritionScanNotFound;

  /// Shown when the barcode lookup fails (network/parse error).
  ///
  /// In en, this message translates to:
  /// **'Scan failed. Try a search or enter it manually.'**
  String get nutritionScanFailed;

  /// Shown when the camera permission is denied for barcode scanning.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan a barcode. You can still search or enter food manually.'**
  String get nutritionScanPermissionDenied;

  /// Action to open the OS app settings so the user can grant camera access.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get nutritionScanOpenSettings;

  /// No description provided for @nutritionSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t log food. Try again.'**
  String get nutritionSaveFailed;

  /// No description provided for @nutritionMealSlot.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get nutritionMealSlot;

  /// No description provided for @nutritionManualEntry.
  ///
  /// In en, this message translates to:
  /// **'Enter manually'**
  String get nutritionManualEntry;

  /// No description provided for @nutritionItemName.
  ///
  /// In en, this message translates to:
  /// **'Item name'**
  String get nutritionItemName;

  /// No description provided for @nutritionPortionGrams.
  ///
  /// In en, this message translates to:
  /// **'Portion (g)'**
  String get nutritionPortionGrams;

  /// No description provided for @nutritionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get nutritionAdd;

  /// No description provided for @nutritionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get nutritionCancel;

  /// No description provided for @nutritionTemplates.
  ///
  /// In en, this message translates to:
  /// **'Meal templates'**
  String get nutritionTemplates;

  /// AppBar action: save today’s logged meals as a reusable template
  ///
  /// In en, this message translates to:
  /// **'Save as meal'**
  String get nutritionSaveAsMeal;

  /// No description provided for @nutritionSaveAsMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Save as a meal template'**
  String get nutritionSaveAsMealTitle;

  /// No description provided for @nutritionTemplateName.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get nutritionTemplateName;

  /// No description provided for @nutritionTemplateNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Pre-run breakfast'**
  String get nutritionTemplateNamePlaceholder;

  /// No description provided for @nutritionSaveTemplate.
  ///
  /// In en, this message translates to:
  /// **'Save meal'**
  String get nutritionSaveTemplate;

  /// No description provided for @nutritionTemplateSaved.
  ///
  /// In en, this message translates to:
  /// **'Meal template saved.'**
  String get nutritionTemplateSaved;

  /// Banner when saving a meal template fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the template: {error}'**
  String nutritionTemplateSaveFailed(String error);

  /// No description provided for @nutritionLogTemplate.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get nutritionLogTemplate;

  /// Banner after logging a meal template: n items from the named template
  ///
  /// In en, this message translates to:
  /// **'Logged {n} items from {name}.'**
  String nutritionTemplateLogged(int n, String name);

  /// Banner when logging a meal template fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t log the template: {error}'**
  String nutritionTemplateLogFailed(String error);

  /// Banner when deleting a meal template fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t delete the template: {error}'**
  String nutritionTemplateDeleteFailed(String error);

  /// Subtitle on a meal-template row: number of items
  ///
  /// In en, this message translates to:
  /// **'{n} items'**
  String nutritionTemplateItems(int n);

  /// No description provided for @nutritionDeleteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get nutritionDeleteTemplate;

  /// No description provided for @nutritionDeleteTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this meal template?'**
  String get nutritionDeleteTemplateTitle;

  /// Confirm dialog body before deleting a meal template
  ///
  /// In en, this message translates to:
  /// **'{name} will be removed. Meals already logged from it stay in your diary.'**
  String nutritionDeleteTemplateMessage(String name);

  /// No description provided for @nutritionRecipes.
  ///
  /// In en, this message translates to:
  /// **'Recipes'**
  String get nutritionRecipes;

  /// AppBar action: save today’s logged meals as a reusable recipe (summed into one entry)
  ///
  /// In en, this message translates to:
  /// **'Save as recipe'**
  String get nutritionSaveAsRecipe;

  /// No description provided for @nutritionSaveAsRecipeTitle.
  ///
  /// In en, this message translates to:
  /// **'Save as a recipe'**
  String get nutritionSaveAsRecipeTitle;

  /// No description provided for @nutritionRecipeName.
  ///
  /// In en, this message translates to:
  /// **'Recipe name'**
  String get nutritionRecipeName;

  /// No description provided for @nutritionRecipeNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Chicken & rice bowl'**
  String get nutritionRecipeNamePlaceholder;

  /// No description provided for @nutritionRecipeServings.
  ///
  /// In en, this message translates to:
  /// **'Servings'**
  String get nutritionRecipeServings;

  /// No description provided for @nutritionRecipeServingsHint.
  ///
  /// In en, this message translates to:
  /// **'The ingredients are summed, then divided by servings. Logging one serving adds a single entry with the combined macros.'**
  String get nutritionRecipeServingsHint;

  /// No description provided for @nutritionSaveRecipe.
  ///
  /// In en, this message translates to:
  /// **'Save recipe'**
  String get nutritionSaveRecipe;

  /// No description provided for @nutritionRecipeSaved.
  ///
  /// In en, this message translates to:
  /// **'Recipe saved.'**
  String get nutritionRecipeSaved;

  /// Banner when saving a recipe fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the recipe: {error}'**
  String nutritionRecipeSaveFailed(String error);

  /// No description provided for @nutritionLogRecipe.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get nutritionLogRecipe;

  /// Banner after logging a recipe: n servings of the named recipe
  ///
  /// In en, this message translates to:
  /// **'Logged {name} ({n} serving).'**
  String nutritionRecipeLogged(int n, String name);

  /// Banner when logging a recipe fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t log the recipe: {error}'**
  String nutritionRecipeLogFailed(String error);

  /// Banner when deleting a recipe fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t delete the recipe: {error}'**
  String nutritionRecipeDeleteFailed(String error);

  /// Subtitle on a recipe row: ingredient count + servings
  ///
  /// In en, this message translates to:
  /// **'{n} ingredients · {servings} servings'**
  String nutritionRecipeMeta(int n, num servings);

  /// No description provided for @nutritionDeleteRecipe.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get nutritionDeleteRecipe;

  /// No description provided for @nutritionDeleteRecipeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this recipe?'**
  String get nutritionDeleteRecipeTitle;

  /// Confirm dialog body before deleting a recipe
  ///
  /// In en, this message translates to:
  /// **'{name} will be removed. Meals already logged from it stay in your diary.'**
  String nutritionDeleteRecipeMessage(String name);

  /// App bar title for the session-plans list (yoga/pilates/class sequences)
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessionTitle;

  /// Empty-state line on the session-plans list
  ///
  /// In en, this message translates to:
  /// **'No session plans yet.'**
  String get sessionEmpty;

  /// Empty-state hint pointing to the web editor (mobile is read-only in P1)
  ///
  /// In en, this message translates to:
  /// **'Build a reusable yoga, pilates or class sequence on the web.'**
  String get sessionEmptyHint;

  /// Fallback title for a session plan with no title
  ///
  /// In en, this message translates to:
  /// **'Untitled session'**
  String get sessionUntitled;

  /// Shown when a session plan can't be loaded
  ///
  /// In en, this message translates to:
  /// **'Session plan not found.'**
  String get sessionNotFound;

  /// Owner action to make a session plan publicly shareable
  ///
  /// In en, this message translates to:
  /// **'Make public'**
  String get sessionMakePublic;

  /// Owner action to make a public session plan private again
  ///
  /// In en, this message translates to:
  /// **'Make private'**
  String get sessionMakePrivate;

  /// Shown when toggling a session plan's public visibility fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change visibility.'**
  String get sessionVisibilityError;

  /// Heading above the expanded list of movement steps
  ///
  /// In en, this message translates to:
  /// **'Sequence'**
  String get sessionSteps;

  /// A timed hold step in the sequence
  ///
  /// In en, this message translates to:
  /// **'{name} · hold {seconds}s'**
  String sessionStepHold(Object name, Object seconds);

  /// A counted-reps step in the sequence
  ///
  /// In en, this message translates to:
  /// **'{name} · {reps} reps'**
  String sessionStepReps(Object name, Object reps);

  /// A continuous flow step in the sequence
  ///
  /// In en, this message translates to:
  /// **'{name} · flow {seconds}s'**
  String sessionStepFlow(Object name, Object seconds);

  /// The left half of a per-side movement step in the sequence
  ///
  /// In en, this message translates to:
  /// **'{name} (Left)'**
  String sessionSideLeft(Object name);

  /// The right half of a per-side movement step in the sequence
  ///
  /// In en, this message translates to:
  /// **'{name} (Right)'**
  String sessionSideRight(Object name);

  /// Estimated total duration of a session plan in minutes
  ///
  /// In en, this message translates to:
  /// **'Est. {minutes} min'**
  String sessionEstDuration(Object minutes);

  /// Button to begin the guided weightlifting session runner
  ///
  /// In en, this message translates to:
  /// **'Start session'**
  String get gymSessionStart;

  /// Current step label in the guided weightlifting session
  ///
  /// In en, this message translates to:
  /// **'{exercise} · set {set} of {total}'**
  String gymSessionStep(Object exercise, Object set, Object total);

  /// Heading shown when every set in the session is done
  ///
  /// In en, this message translates to:
  /// **'Session complete'**
  String get gymSessionComplete;

  /// Button to skip the current set in the session runner
  ///
  /// In en, this message translates to:
  /// **'Skip set'**
  String get gymSessionSkipSet;

  /// Button to step back to the previous set in the session runner
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get gymSessionRewind;

  /// Button to abandon the guided weightlifting session
  ///
  /// In en, this message translates to:
  /// **'Abandon'**
  String get gymSessionAbandon;

  /// Button to finish and save the guided weightlifting session
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get gymSessionFinish;

  /// Title of the dialog confirming abandonment of a guided session
  ///
  /// In en, this message translates to:
  /// **'Discard session?'**
  String get gymSessionDiscardTitle;

  /// Body of the dialog confirming abandonment of a guided session
  ///
  /// In en, this message translates to:
  /// **'Your progress in this session won\'t be saved.'**
  String get gymSessionDiscardBody;

  /// Confirm button to discard the guided session
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get gymSessionDiscardConfirm;

  /// Banner shown after a guided session is saved
  ///
  /// In en, this message translates to:
  /// **'Workout saved'**
  String get gymSessionSaved;

  /// Banner shown when saving a guided session fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save workout'**
  String get gymSessionSaveFailed;

  /// Logged-vs-planned set count on the guided-session finish view
  ///
  /// In en, this message translates to:
  /// **'{done}/{total}'**
  String gymSessionSetProgress(Object done, Object total);

  /// Button to log the current set's reps/weight and advance the guided session
  ///
  /// In en, this message translates to:
  /// **'Complete set'**
  String get gymSessionLogSet;

  /// Label for the rest period between sets in the session runner
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get gymSessionRest;

  /// Countdown of remaining rest seconds between sets
  ///
  /// In en, this message translates to:
  /// **'Rest {seconds}s'**
  String gymSessionRestRemaining(Object seconds);

  /// Button to skip the rest period and advance to the next set
  ///
  /// In en, this message translates to:
  /// **'Skip rest'**
  String get gymSessionRestSkip;

  /// Label preceding the planned reps and weight for the current set
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get gymSessionTarget;

  /// Adherence percentage summary on the guided-session review screen
  ///
  /// In en, this message translates to:
  /// **'{pct}% adherence'**
  String gymReviewAdherence(Object pct);

  /// Verdict label when the guided session was fully completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get gymReviewVerdictCompleted;

  /// Verdict label when the guided session was partly completed
  ///
  /// In en, this message translates to:
  /// **'Partly done'**
  String get gymReviewVerdictPartial;

  /// Verdict label when the guided session was abandoned
  ///
  /// In en, this message translates to:
  /// **'Abandoned'**
  String get gymReviewVerdictAbandoned;

  /// Per-set status when the planned target was met
  ///
  /// In en, this message translates to:
  /// **'Hit'**
  String get gymReviewStatusHit;

  /// Per-set status when only part of the planned target was met
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get gymReviewStatusPartial;

  /// Per-set status when the planned set was not performed
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get gymReviewStatusMissed;

  /// Per-set status for a set performed beyond the plan
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get gymReviewStatusExtra;

  /// Button to begin the timed yoga/pilates follow-along player
  ///
  /// In en, this message translates to:
  /// **'Start session'**
  String get sessionRunStart;

  /// Current movement name in the follow-along session player
  ///
  /// In en, this message translates to:
  /// **'{name}'**
  String sessionRunStep(Object name);

  /// Button to mark the current movement complete in the session player
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sessionRunDone;

  /// Button to skip the current movement in the session player
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get sessionRunSkip;

  /// Button to pause the follow-along session player
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get sessionRunPause;

  /// Button to resume the paused follow-along session player
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get sessionRunResume;

  /// Button to abandon the follow-along session
  ///
  /// In en, this message translates to:
  /// **'Abandon'**
  String get sessionRunAbandon;

  /// Button to finish and save the follow-along session
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get sessionRunFinish;

  /// Remaining seconds on the current timed movement
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String sessionRunRemaining(Object seconds);

  /// Heading shown when the follow-along session is finished
  ///
  /// In en, this message translates to:
  /// **'Session complete'**
  String get sessionRunComplete;

  /// Banner shown after a follow-along session is saved
  ///
  /// In en, this message translates to:
  /// **'Session saved'**
  String get sessionRunSaved;

  /// Banner shown when saving a follow-along session fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save session'**
  String get sessionRunSaveFailed;

  /// Title of the dialog confirming abandonment of a follow-along session
  ///
  /// In en, this message translates to:
  /// **'Discard session?'**
  String get sessionRunDiscardTitle;

  /// Body of the dialog confirming abandonment of a follow-along session
  ///
  /// In en, this message translates to:
  /// **'Your progress in this session won\'t be saved.'**
  String get sessionRunDiscardBody;

  /// Confirm button to discard the follow-along session
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get sessionRunDiscardConfirm;

  /// Verdict label when the follow-along session was fully completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get sessionRunVerdictCompleted;

  /// Verdict label when the follow-along session was partly completed
  ///
  /// In en, this message translates to:
  /// **'Partly done'**
  String get sessionRunVerdictPartial;

  /// Verdict label when the follow-along session was abandoned
  ///
  /// In en, this message translates to:
  /// **'Abandoned'**
  String get sessionRunVerdictAbandoned;

  /// Progress counter in the follow-along session player
  ///
  /// In en, this message translates to:
  /// **'Step {index} of {total}'**
  String sessionRunStepCount(int index, int total);

  /// Spoken cue when a per-side movement switches from left to right in the session player
  ///
  /// In en, this message translates to:
  /// **'Switch sides'**
  String get sessionRunSwitchSides;

  /// Title of the coach-athlete roster screen
  ///
  /// In en, this message translates to:
  /// **'Coaching'**
  String get coachingTitle;

  /// Intro line on the coaching roster screen
  ///
  /// In en, this message translates to:
  /// **'Coach athletes by sharing an invite link, then review their training. Or follow your own coach here.'**
  String get coachingLede;

  /// Cancel button in coaching confirmation dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get coachingCancel;

  /// Heading for the list of athletes a coach manages
  ///
  /// In en, this message translates to:
  /// **'My athletes'**
  String get coachingMyAthletes;

  /// Subheading under My athletes
  ///
  /// In en, this message translates to:
  /// **'Runners who accepted your invite'**
  String get coachingMyAthletesSub;

  /// Button that mints + copies a coach invite link
  ///
  /// In en, this message translates to:
  /// **'Invite an athlete'**
  String get coachingInviteAnAthlete;

  /// Label while a coach invite is being minted
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get coachingCreating;

  /// Title of an unredeemed coach invite row
  ///
  /// In en, this message translates to:
  /// **'Pending invite'**
  String get coachingPendingInvite;

  /// Subtitle of a pending invite row
  ///
  /// In en, this message translates to:
  /// **'Created {date} · not yet accepted'**
  String coachingPendingInviteSub(String date);

  /// Copy the invite link to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get coachingCopyLink;

  /// Share the invite link via the OS share sheet
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get coachingShareLink;

  /// Revoke (delete) a pending coach invite
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get coachingRevoke;

  /// Empty state for the athletes list
  ///
  /// In en, this message translates to:
  /// **'No athletes yet. Invite one to get started.'**
  String get coachingNoAthletes;

  /// Athlete roster card title
  ///
  /// In en, this message translates to:
  /// **'Athlete roster'**
  String get coachingRosterTitle;

  /// Athlete roster card subtitle
  ///
  /// In en, this message translates to:
  /// **'Every athlete at a glance — load, plan compliance, and injury risk.'**
  String get coachingRosterSubtitle;

  /// Roster cell when athlete has no runs
  ///
  /// In en, this message translates to:
  /// **'No runs yet'**
  String get coachingRosterNeverRun;

  /// Roster cell when athlete has no active plan
  ///
  /// In en, this message translates to:
  /// **'No plan'**
  String get coachingRosterNoPlan;

  /// Injury-risk band: insufficient history
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get coachingRosterRiskInsufficient;

  /// Injury-risk band: low
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get coachingRosterRiskLow;

  /// Injury-risk band: optimal
  ///
  /// In en, this message translates to:
  /// **'Optimal'**
  String get coachingRosterRiskOptimal;

  /// Injury-risk band: elevated
  ///
  /// In en, this message translates to:
  /// **'Elevated'**
  String get coachingRosterRiskElevated;

  /// Injury-risk band: high
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get coachingRosterRiskHigh;

  /// Fallback name for an athlete with no display name
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get coachingRunner;

  /// When a coach-athlete link was accepted
  ///
  /// In en, this message translates to:
  /// **'Coaching since {date}'**
  String coachingCoachingSince(String date);

  /// Open the athlete review screen
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get coachingReview;

  /// Remove an athlete from the coach's roster
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get coachingRemove;

  /// Heading for the list of coaches an athlete is linked to
  ///
  /// In en, this message translates to:
  /// **'My coaches'**
  String get coachingMyCoaches;

  /// Subheading under My coaches
  ///
  /// In en, this message translates to:
  /// **'Coaches who can see your training'**
  String get coachingMyCoachesSub;

  /// Empty state for the coaches list
  ///
  /// In en, this message translates to:
  /// **'You haven\'t accepted a coach invite yet.'**
  String get coachingNoCoaches;

  /// Fallback name for a coach with no display name
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get coachingCoach;

  /// When the athlete linked to this coach
  ///
  /// In en, this message translates to:
  /// **'Linked since {date}'**
  String coachingLinkedSince(String date);

  /// End the link with a coach
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get coachingLeave;

  /// Confirmation banner after copying an invite link
  ///
  /// In en, this message translates to:
  /// **'Invite link copied'**
  String get coachingInviteLinkCopied;

  /// Fallback name in the remove-athlete confirmation
  ///
  /// In en, this message translates to:
  /// **'this athlete'**
  String get coachingThisAthlete;

  /// Fallback name in the leave-coach confirmation
  ///
  /// In en, this message translates to:
  /// **'this coach'**
  String get coachingThisCoach;

  /// Title of the revoke-invite confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Revoke invite?'**
  String get coachingRevokeTitle;

  /// Body of the revoke-invite confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'The invite link will stop working. You can always create a new one.'**
  String get coachingRevokeBody;

  /// Title of the remove-athlete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Remove athlete?'**
  String get coachingRemoveAthleteTitle;

  /// Body of the remove-athlete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Stop coaching {name}? You\'ll lose access to their runs and plans.'**
  String coachingRemoveAthleteBody(String name);

  /// Title of the leave-coach confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Leave coach?'**
  String get coachingLeaveCoachTitle;

  /// Body of the leave-coach confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Stop sharing your training with {name}?'**
  String coachingLeaveCoachBody(String name);

  /// Error banner when the roster fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load coaching: {error}'**
  String coachingLoadError(String error);

  /// Error banner when minting an invite fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create invite: {error}'**
  String coachingCreateInviteError(String error);

  /// Error banner when revoking an invite fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t revoke invite: {error}'**
  String coachingRevokeInviteError(String error);

  /// Error banner when removing an athlete fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove athlete: {error}'**
  String coachingRemoveAthleteError(String error);

  /// Error banner when leaving a coach fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t end the link: {error}'**
  String coachingEndLinkError(String error);

  /// App-bar fallback title for an athlete with no display name
  ///
  /// In en, this message translates to:
  /// **'Athlete'**
  String get coachingAthleteAthleteFallback;

  /// Header fallback name for an athlete with no display name
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get coachingAthleteRunnerFallback;

  /// When the coaching link started, shown in the athlete header
  ///
  /// In en, this message translates to:
  /// **'Coaching since {date}'**
  String coachingAthleteCoachingSince(String date);

  /// Heading of the plan-compliance card on the athlete review screen
  ///
  /// In en, this message translates to:
  /// **'Plan compliance'**
  String get coachingAthletePlanCompliance;

  /// Shown when the athlete has no active plan
  ///
  /// In en, this message translates to:
  /// **'No active training plan.'**
  String get coachingAthleteNoActivePlan;

  /// Heading of the assign-a-plan control
  ///
  /// In en, this message translates to:
  /// **'Assign a plan'**
  String get coachingAthleteAssignTitle;

  /// Hint above the assign-a-plan control
  ///
  /// In en, this message translates to:
  /// **'Pick one of your plans to assign to {name}.'**
  String coachingAthleteAssignHint(String name);

  /// Label for the plan dropdown in the assign control
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get coachingAthleteAssignSelectLabel;

  /// Placeholder for the plan dropdown
  ///
  /// In en, this message translates to:
  /// **'Choose a plan…'**
  String get coachingAthleteAssignSelectPlaceholder;

  /// Label for the start-date picker in the assign control
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get coachingAthleteAssignStartLabel;

  /// Label on the assign button while assignment is in flight
  ///
  /// In en, this message translates to:
  /// **'Assigning…'**
  String get coachingAthleteAssigning;

  /// Button that assigns the selected plan to the athlete
  ///
  /// In en, this message translates to:
  /// **'Assign plan'**
  String get coachingAthleteAssignButton;

  /// Shown when the coach has no plans to assign
  ///
  /// In en, this message translates to:
  /// **'Create a training plan first, then you can assign it to your athletes.'**
  String get coachingAthleteAssignNoPlans;

  /// Badge when the active plan was assigned by the viewing coach
  ///
  /// In en, this message translates to:
  /// **'Assigned by you'**
  String get coachingAthleteAssignedByYou;

  /// Hint when the athlete has a plan not assigned by this coach
  ///
  /// In en, this message translates to:
  /// **'This athlete already has an active plan. They\'ll need to finish or end it before you can assign a new one.'**
  String get coachingAthleteCannotAssignHasPlan;

  /// Word following the completion percentage, e.g. '40% complete'
  ///
  /// In en, this message translates to:
  /// **'complete'**
  String get coachingAthleteComplete;

  /// Completed-vs-total workout count
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String coachingAthleteDoneCount(int done, int total);

  /// Count of missed workouts
  ///
  /// In en, this message translates to:
  /// **'{n} missed'**
  String coachingAthleteMissedCount(int n);

  /// Workout status pill: completed
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get coachingAthleteStatusDone;

  /// Workout status pill: missed
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get coachingAthleteStatusMissed;

  /// Workout status pill: upcoming
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get coachingAthleteStatusUpcoming;

  /// Heading of the recent-runs card on the athlete review screen
  ///
  /// In en, this message translates to:
  /// **'Recent runs'**
  String get coachingAthleteRecentRuns;

  /// Empty state for the recent-runs list
  ///
  /// In en, this message translates to:
  /// **'No runs logged yet.'**
  String get coachingAthleteNoRunsYet;

  /// Badge marking a private run visible to the coach
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get coachingAthletePrivate;

  /// Success banner after assigning a plan
  ///
  /// In en, this message translates to:
  /// **'Plan assigned to {name}'**
  String coachingAthleteAssignSuccess(String name);

  /// Error banner when the athlete review screen fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load athlete: {error}'**
  String coachingAthleteLoadError(String error);

  /// Heading for the route course-markers panel
  ///
  /// In en, this message translates to:
  /// **'Course markers'**
  String get routeMarkerHeading;

  /// Add a course marker
  ///
  /// In en, this message translates to:
  /// **'Add marker'**
  String get routeMarkerAdd;

  /// Empty state for the course-markers panel
  ///
  /// In en, this message translates to:
  /// **'No course markers yet. Add aid stations, cutoffs, and more along the route.'**
  String get routeMarkerEmpty;

  /// Edit a course marker
  ///
  /// In en, this message translates to:
  /// **'Edit marker'**
  String get routeMarkerEdit;

  /// Delete a course marker
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get routeMarkerDelete;

  /// Cancel the marker editor
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get routeMarkerCancel;

  /// Save a course marker
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get routeMarkerSave;

  /// Saving a course marker
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get routeMarkerSaving;

  /// Marker kind field label
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get routeMarkerKindLabel;

  /// Marker name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get routeMarkerNameLabel;

  /// Marker name field hint
  ///
  /// In en, this message translates to:
  /// **'e.g. Aid 2'**
  String get routeMarkerNamePlaceholder;

  /// Aid services field label
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get routeMarkerServicesLabel;

  /// Cutoff time field label
  ///
  /// In en, this message translates to:
  /// **'Cut-off time'**
  String get routeMarkerCutoffLabel;

  /// Note field label
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get routeMarkerNoteLabel;

  /// Hint to place a marker by tapping the map
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place this marker.'**
  String get routeMarkerTapToPlace;

  /// Toggle to snap a placed marker onto the route polyline
  ///
  /// In en, this message translates to:
  /// **'Snap to route line'**
  String get routeMarkerSnapToggle;

  /// Confirmation that a marker was placed
  ///
  /// In en, this message translates to:
  /// **'Placed. Tap the map again to move it.'**
  String get routeMarkerPlaced;

  /// Cutoff time detail line
  ///
  /// In en, this message translates to:
  /// **'Cut-off {time}'**
  String routeMarkerCutoffAt(String time);

  /// Validation: marker name required
  ///
  /// In en, this message translates to:
  /// **'Give the marker a name.'**
  String get routeMarkerLabelRequired;

  /// Validation: marker must be placed
  ///
  /// In en, this message translates to:
  /// **'Tap the map to place the marker first.'**
  String get routeMarkerPlaceRequired;

  /// Latitude field label for manual marker coordinate entry
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get routeMarkerLatLabel;

  /// Longitude field label for manual marker coordinate entry
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get routeMarkerLngLabel;

  /// Validation: typed marker coordinates out of range or unparseable
  ///
  /// In en, this message translates to:
  /// **'Enter a valid latitude (-90 to 90) and longitude (-180 to 180).'**
  String get routeMarkerCoordInvalid;

  /// Button opening the marker editor without a map tap, for keyboard / screen-reader placement
  ///
  /// In en, this message translates to:
  /// **'Enter coordinates instead'**
  String get routeMarkerEnterCoords;

  /// Error: save marker failed
  ///
  /// In en, this message translates to:
  /// **'Could not save marker: {error}'**
  String routeMarkerSaveFailed(String error);

  /// Error: delete marker failed
  ///
  /// In en, this message translates to:
  /// **'Could not delete marker: {error}'**
  String routeMarkerDeleteFailed(String error);

  /// Delete-marker confirm title
  ///
  /// In en, this message translates to:
  /// **'Delete marker?'**
  String get routeMarkerDeleteConfirmTitle;

  /// Delete-marker confirm message
  ///
  /// In en, this message translates to:
  /// **'This removes the marker from the route permanently.'**
  String get routeMarkerDeleteConfirmMessage;

  /// Marker kind: aid station
  ///
  /// In en, this message translates to:
  /// **'Aid station'**
  String get routeMarkerKindAidStation;

  /// Marker kind: cutoff
  ///
  /// In en, this message translates to:
  /// **'Cut-off'**
  String get routeMarkerKindCutoff;

  /// Marker kind: crew access
  ///
  /// In en, this message translates to:
  /// **'Crew / parking'**
  String get routeMarkerKindCrewAccess;

  /// Marker kind: hazard
  ///
  /// In en, this message translates to:
  /// **'Hazard'**
  String get routeMarkerKindHazard;

  /// Marker kind: note
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get routeMarkerKindNote;

  /// Marker kind: climb
  ///
  /// In en, this message translates to:
  /// **'Climb'**
  String get routeMarkerKindClimb;

  /// Marker kind: custom
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get routeMarkerKindCustom;

  /// Aid service: water
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get routeMarkerServiceWater;

  /// Aid service: food
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get routeMarkerServiceFood;

  /// Aid service: medical
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get routeMarkerServiceMedical;

  /// Aid service: toilets
  ///
  /// In en, this message translates to:
  /// **'Toilets'**
  String get routeMarkerServiceToilets;

  /// Aid service: drop bag
  ///
  /// In en, this message translates to:
  /// **'Drop bag'**
  String get routeMarkerServiceDropBag;

  /// Title of the edit-club form
  ///
  /// In en, this message translates to:
  /// **'Edit club'**
  String get clubFormEditTitle;

  /// Club website link field label
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get clubEditorWebsite;

  /// Club Instagram link field label
  ///
  /// In en, this message translates to:
  /// **'Instagram'**
  String get clubEditorInstagram;

  /// Club Strava link field label
  ///
  /// In en, this message translates to:
  /// **'Strava'**
  String get clubEditorStrava;

  /// Club Facebook link field label
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get clubEditorFacebook;

  /// Save button on the edit-club form
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get clubEditorSaveChanges;

  /// Club page website link label
  ///
  /// In en, this message translates to:
  /// **'Visit our website'**
  String get clubDetailVisitWebsite;

  /// Club page edit action tooltip
  ///
  /// In en, this message translates to:
  /// **'Edit club'**
  String get clubDetailEditClub;

  /// Roadbook screen title
  ///
  /// In en, this message translates to:
  /// **'Roadbook'**
  String get roadbookTitle;

  /// Route-detail roadbook entry button
  ///
  /// In en, this message translates to:
  /// **'Roadbook (crew sheet)'**
  String get roadbookCrewSheet;

  /// Goal time field label
  ///
  /// In en, this message translates to:
  /// **'Goal time'**
  String get roadbookGoalTime;

  /// Start time field label
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get roadbookStartTime;

  /// Effort pacing model
  ///
  /// In en, this message translates to:
  /// **'Effort'**
  String get roadbookEffort;

  /// Even pacing model
  ///
  /// In en, this message translates to:
  /// **'Even'**
  String get roadbookEven;

  /// Start checkpoint
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get roadbookStart;

  /// Finish checkpoint
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get roadbookFinish;

  /// Share roadbook
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get roadbookShare;

  /// Empty state on the roadbook screen
  ///
  /// In en, this message translates to:
  /// **'Add course markers to build a roadbook.'**
  String get roadbookNoMarkers;

  /// Fetch elevation action
  ///
  /// In en, this message translates to:
  /// **'Add elevation'**
  String get roadbookAddElevation;

  /// Elevation fetch failed
  ///
  /// In en, this message translates to:
  /// **'Elevation data unavailable for this route'**
  String get roadbookElevationUnavailable;

  /// Roadbook summary line
  ///
  /// In en, this message translates to:
  /// **'{distance} · {vert} vert · goal {time}'**
  String roadbookSummary(String distance, String vert, String time);

  /// Toggle to show the per-leg fueling plan on the roadbook
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get roadbookFuel;

  /// Toggle that bumps fluid targets for hot conditions
  ///
  /// In en, this message translates to:
  /// **'Heat'**
  String get roadbookHeat;

  /// Carbohydrate column/label on the fueling plan
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get roadbookCarbs;

  /// Fluid column/label on the fueling plan
  ///
  /// In en, this message translates to:
  /// **'Fluid'**
  String get roadbookFluid;

  /// Per-leg carbohydrate amount in grams
  ///
  /// In en, this message translates to:
  /// **'{grams} g'**
  String roadbookCarbsValue(String grams);

  /// Per-leg fluid amount in millilitres
  ///
  /// In en, this message translates to:
  /// **'{ml} ml'**
  String roadbookFluidValue(String ml);

  /// Hint for what fuel to carry out of an aid station to reach the next one
  ///
  /// In en, this message translates to:
  /// **'carry {gels} gels · {fluid} ml'**
  String roadbookCarryHint(String gels, String fluid);

  /// Organiser action on event detail opening the aid-station check-in screen
  ///
  /// In en, this message translates to:
  /// **'Checkpoint check-in'**
  String get checkpointCheckinAction;

  /// Title of the volunteer checkpoint check-in screen
  ///
  /// In en, this message translates to:
  /// **'Aid-station check-in'**
  String get checkpointCheckinTitle;

  /// Tooltip for the manual sync action
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get checkpointSyncNow;

  /// Badge shown when there are crossings not yet pushed to the server
  ///
  /// In en, this message translates to:
  /// **'Unsynced'**
  String get checkpointPending;

  /// Error state title when checkpoints fail to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load checkpoints'**
  String get checkpointLoadFailed;

  /// Retry loading checkpoints
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get checkpointRetry;

  /// Empty state when an event has no checkpoints
  ///
  /// In en, this message translates to:
  /// **'This race has no checkpoints yet. Add them on the web before crews check runners in.'**
  String get checkpointNone;

  /// Label above the checkpoint dropdown
  ///
  /// In en, this message translates to:
  /// **'CHECKPOINT'**
  String get checkpointPickLabel;

  /// Label for the bib entry field
  ///
  /// In en, this message translates to:
  /// **'Bib number'**
  String get checkpointBibLabel;

  /// Hint for the bib entry field
  ///
  /// In en, this message translates to:
  /// **'Scan or type a bib'**
  String get checkpointBibHint;

  /// Validation banner when no bib is entered
  ///
  /// In en, this message translates to:
  /// **'Enter a bib number first'**
  String get checkpointBibRequired;

  /// Button to record a runner arriving at the checkpoint
  ///
  /// In en, this message translates to:
  /// **'Stamp IN'**
  String get checkpointStampIn;

  /// Button to record a runner leaving the checkpoint
  ///
  /// In en, this message translates to:
  /// **'Stamp OUT'**
  String get checkpointStampOut;

  /// Confirmation after stamping a runner in
  ///
  /// In en, this message translates to:
  /// **'Bib {bib} stamped in'**
  String checkpointStampedIn(String bib);

  /// Confirmation after stamping a runner out
  ///
  /// In en, this message translates to:
  /// **'Bib {bib} stamped out'**
  String checkpointStampedOut(String bib);

  /// Error banner when a stamp fails to persist
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that stamp'**
  String get checkpointStampFailed;

  /// Header above the list of runners stamped at this checkpoint
  ///
  /// In en, this message translates to:
  /// **'LOGGED HERE ({count})'**
  String checkpointLoggedHere(int count);

  /// Empty state for the per-checkpoint crossing list
  ///
  /// In en, this message translates to:
  /// **'No runners logged at this checkpoint yet.'**
  String get checkpointNoneLoggedHere;

  /// Row label for a logged crossing identified by bib
  ///
  /// In en, this message translates to:
  /// **'Bib {bib}'**
  String checkpointBibRow(String bib);

  /// Subtitle showing a crossing's in and out times
  ///
  /// In en, this message translates to:
  /// **'In {inTime} · Out {outTime}'**
  String checkpointInOut(String inTime, String outTime);

  /// Title of the Art 9 weigh-in capture sheet
  ///
  /// In en, this message translates to:
  /// **'Weigh-in'**
  String get checkpointWeighInTitle;

  /// Explanatory text on the weigh-in consent sheet
  ///
  /// In en, this message translates to:
  /// **'Body weight and medical-hold notes are health data, recorded only with the runner\'s consent and visible only to race officials.'**
  String get checkpointWeighInConsentBlurb;

  /// Art 9 consent toggle on the weigh-in sheet
  ///
  /// In en, this message translates to:
  /// **'Runner consents to recording health data'**
  String get checkpointWeighInConsent;

  /// Body weight field label on the weigh-in sheet
  ///
  /// In en, this message translates to:
  /// **'Body weight (kg)'**
  String get checkpointWeighInWeightKg;

  /// Medical-hold toggle on the weigh-in sheet
  ///
  /// In en, this message translates to:
  /// **'Place on medical hold'**
  String get checkpointMedicalHold;

  /// Confirm button on the weigh-in sheet
  ///
  /// In en, this message translates to:
  /// **'Save & stamp'**
  String get checkpointWeighInSave;

  /// Cancel the weigh-in sheet
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get checkpointCancel;

  /// Challenges feature title / tab label
  ///
  /// In en, this message translates to:
  /// **'Challenges'**
  String get challengesTitle;

  /// Section heading for challenges the user joined
  ///
  /// In en, this message translates to:
  /// **'My challenges'**
  String get challengesMyChallenges;

  /// Section heading for public challenges to join
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get challengesBrowse;

  /// Empty state for the my-challenges section
  ///
  /// In en, this message translates to:
  /// **'No challenges yet.'**
  String get challengesEmpty;

  /// Empty state for the browse section
  ///
  /// In en, this message translates to:
  /// **'No public challenges to join right now.'**
  String get challengesBrowseEmpty;

  /// Join a challenge button
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get challengesJoin;

  /// Leave a challenge button
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get challengesLeave;

  /// Delete a challenge button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get challengesDelete;

  /// Distance metric label
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get challengesMetricDistance;

  /// Duration metric label
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get challengesMetricDuration;

  /// Elevation-gain metric label
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get challengesMetricVert;

  /// Activity-count metric label
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get challengesMetricActivityCount;

  /// Streak-days metric label
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get challengesMetricStreak;

  /// Progress label value vs goal
  ///
  /// In en, this message translates to:
  /// **'{value} of {goal}'**
  String challengesGoalProgress(String value, String goal);

  /// Goal-met label
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get challengesProgressComplete;

  /// On-pace verdict: ahead of the even-pace line
  ///
  /// In en, this message translates to:
  /// **'Ahead of pace'**
  String get challengesPaceAhead;

  /// On-pace verdict: on track to finish
  ///
  /// In en, this message translates to:
  /// **'On pace to finish'**
  String get challengesPaceOnTrack;

  /// On-pace verdict: behind the even-pace line
  ///
  /// In en, this message translates to:
  /// **'Behind pace'**
  String get challengesPaceBehind;

  /// Daily rate still needed to finish a behind-pace challenge
  ///
  /// In en, this message translates to:
  /// **'{rate} per day to finish'**
  String challengesPaceNeedPerDay(String rate);

  /// Days-left label
  ///
  /// In en, this message translates to:
  /// **'Ends in {n} days'**
  String challengesEndsIn(int n);

  /// Ends-today label
  ///
  /// In en, this message translates to:
  /// **'Ends today'**
  String get challengesEndsToday;

  /// Past-end label
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get challengesEnded;

  /// Leaderboard heading
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get challengesLeaderboard;

  /// Empty leaderboard state
  ///
  /// In en, this message translates to:
  /// **'No progress logged yet.'**
  String get challengesLeaderboardEmpty;

  /// Rank label
  ///
  /// In en, this message translates to:
  /// **'#{rank}'**
  String challengesLeaderboardRank(int rank);

  /// Participant count
  ///
  /// In en, this message translates to:
  /// **'{n} joined'**
  String challengesParticipants(int n);

  /// Completion badge label
  ///
  /// In en, this message translates to:
  /// **'Badge earned'**
  String get challengesBadgeEarned;

  /// Active-days value
  ///
  /// In en, this message translates to:
  /// **'{n} days'**
  String challengesUnitDays(int n);

  /// Activity-count value
  ///
  /// In en, this message translates to:
  /// **'{n}'**
  String challengesUnitActivities(int n);

  /// Leave-confirm dialog title
  ///
  /// In en, this message translates to:
  /// **'Leave challenge?'**
  String get challengesLeaveConfirmTitle;

  /// Leave-confirm dialog body
  ///
  /// In en, this message translates to:
  /// **'Your progress in this challenge will no longer be tracked.'**
  String get challengesLeaveConfirm;

  /// Delete-confirm dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete challenge?'**
  String get challengesDeleteConfirmTitle;

  /// Delete-confirm dialog body
  ///
  /// In en, this message translates to:
  /// **'This removes the challenge and its leaderboard for everyone. This can\'t be undone.'**
  String get challengesDeleteConfirm;

  /// Not-found / no-access state
  ///
  /// In en, this message translates to:
  /// **'This challenge isn\'t available.'**
  String get challengesNotFound;

  /// Join failure banner
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t join the challenge.'**
  String get challengesJoinFailed;

  /// Leave failure banner
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t leave the challenge.'**
  String get challengesLeaveFailed;

  /// Delete failure banner
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the challenge.'**
  String get challengesDeleteFailed;

  /// Load failure banner
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load challenges.'**
  String get challengesLoadFailed;

  /// Thermometer raised-of-goal label
  ///
  /// In en, this message translates to:
  /// **'{raised} of {goal} raised'**
  String fundraiserRaisedOfGoal(String raised, String goal);

  /// Donor count under the thermometer
  ///
  /// In en, this message translates to:
  /// **'{count} supporters'**
  String fundraiserDonorCount(int count);

  /// Shown when a fundraiser exceeds its goal
  ///
  /// In en, this message translates to:
  /// **'Over goal!'**
  String get fundraiserOverGoal;

  /// Closed-fundraiser notice
  ///
  /// In en, this message translates to:
  /// **'This fundraiser is closed.'**
  String get fundraiserClosed;

  /// Donation feed heading
  ///
  /// In en, this message translates to:
  /// **'Recent supporters'**
  String get fundraiserFeedTitle;

  /// Empty donation feed
  ///
  /// In en, this message translates to:
  /// **'Be the first to donate.'**
  String get fundraiserFeedEmpty;

  /// Anonymous donor label
  ///
  /// In en, this message translates to:
  /// **'Anonymous'**
  String get fundraiserAnonymous;

  /// Mobile web-handoff donate button
  ///
  /// In en, this message translates to:
  /// **'Donate on web'**
  String get fundraiserDonateOnWeb;

  /// Title of the race calendar / discovery screen
  ///
  /// In en, this message translates to:
  /// **'Race calendar'**
  String get racesTitle;

  /// Placeholder for the race name search field
  ///
  /// In en, this message translates to:
  /// **'Search races by name…'**
  String get racesSearchPlaceholder;

  /// Placeholder for the near-a-place geocode field
  ///
  /// In en, this message translates to:
  /// **'Near a place…'**
  String get racesNearPlace;

  /// Distance-from-you label on a race card
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String racesKmAway(String distance);

  /// Distance-band chip: no filter
  ///
  /// In en, this message translates to:
  /// **'Any distance'**
  String get racesDistanceAny;

  /// Distance-band chip: 5K
  ///
  /// In en, this message translates to:
  /// **'5K'**
  String get racesDistance5k;

  /// Distance-band chip: 10K
  ///
  /// In en, this message translates to:
  /// **'10K'**
  String get racesDistance10k;

  /// Distance-band chip: half marathon
  ///
  /// In en, this message translates to:
  /// **'Half'**
  String get racesDistanceHalf;

  /// Distance-band chip: marathon
  ///
  /// In en, this message translates to:
  /// **'Marathon'**
  String get racesDistanceMarathon;

  /// Distance-band chip: ultra
  ///
  /// In en, this message translates to:
  /// **'Ultra'**
  String get racesDistanceUltra;

  /// Link to a race's registration page
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get racesRegister;

  /// Link to a race's results page
  ///
  /// In en, this message translates to:
  /// **'View results'**
  String get racesViewResults;

  /// Action to import a runner's official race result
  ///
  /// In en, this message translates to:
  /// **'Import my result'**
  String get racesImportResult;

  /// Action to submit a crowd-sourced race listing
  ///
  /// In en, this message translates to:
  /// **'Add a race'**
  String get racesSubmitRace;

  /// Badge on a user-submitted, not-yet-verified listing
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get racesUnverified;

  /// Empty state for the race calendar
  ///
  /// In en, this message translates to:
  /// **'No races match these filters yet.'**
  String get racesEmpty;

  /// Error state when the race search fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load races. Check your connection and try again.'**
  String get racesSearchFailed;

  /// Inform-tier auto-match prompt on run detail
  ///
  /// In en, this message translates to:
  /// **'Was this the {name}? Import your official result.'**
  String racesMatchPrompt(String name);

  /// Confirm importing a matched race result
  ///
  /// In en, this message translates to:
  /// **'Import result'**
  String get racesMatchConfirm;

  /// Dismiss the auto-match prompt
  ///
  /// In en, this message translates to:
  /// **'Not this race'**
  String get racesMatchDismiss;

  /// Toast after a result is imported
  ///
  /// In en, this message translates to:
  /// **'Official result imported.'**
  String get racesImported;

  /// Heading for the imported official-result panel
  ///
  /// In en, this message translates to:
  /// **'Official result'**
  String get racesOfficialResult;

  /// Chip-time field label
  ///
  /// In en, this message translates to:
  /// **'Chip time'**
  String get racesChipTime;

  /// Gun-time field label
  ///
  /// In en, this message translates to:
  /// **'Gun time'**
  String get racesGunTime;

  /// Overall-place field label
  ///
  /// In en, this message translates to:
  /// **'Overall place'**
  String get racesOverallPlace;

  /// Age-group-place field label
  ///
  /// In en, this message translates to:
  /// **'Age-group place'**
  String get racesAgeGroupPlace;

  /// Age-group field label
  ///
  /// In en, this message translates to:
  /// **'Age group'**
  String get racesAgeGroup;

  /// Bib field label
  ///
  /// In en, this message translates to:
  /// **'Bib'**
  String get racesBib;

  /// Hint above the manual result paste form
  ///
  /// In en, this message translates to:
  /// **'Enter your finishing details from the race\'s results page.'**
  String get racesPasteResultHint;

  /// Save a race listing
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get racesSave;

  /// Cancel a race form
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get racesCancel;

  /// Title of the submit-listing form
  ///
  /// In en, this message translates to:
  /// **'Add a race'**
  String get racesEditorTitle;

  /// Race name field label
  ///
  /// In en, this message translates to:
  /// **'Race name'**
  String get racesFieldName;

  /// Race date field label
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get racesFieldDate;

  /// Race distance field label
  ///
  /// In en, this message translates to:
  /// **'Distance (metres)'**
  String get racesFieldDistance;

  /// Race location field label
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get racesFieldLocation;

  /// Registration link field label
  ///
  /// In en, this message translates to:
  /// **'Registration link'**
  String get racesFieldEntryUrl;

  /// Results link field label
  ///
  /// In en, this message translates to:
  /// **'Results link'**
  String get racesFieldResultsUrl;

  /// Error when submitting a listing fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the race. Please try again.'**
  String get racesSubmitFailed;

  /// Error when importing a result fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import the result. Please try again.'**
  String get racesImportFailed;

  /// Nav label for the races surface
  ///
  /// In en, this message translates to:
  /// **'Races'**
  String get navRaces;

  /// RunSignUp integration name
  ///
  /// In en, this message translates to:
  /// **'RunSignUp'**
  String get integrationsRunsignup;

  /// RunSignUp integration description
  ///
  /// In en, this message translates to:
  /// **'Import race results from RunSignUp.'**
  String get integrationsRunsignupConnect;

  /// Action linking to the race calendar from the RunSignUp tile
  ///
  /// In en, this message translates to:
  /// **'Open the race calendar'**
  String get integrationsRunsignupOpen;

  /// Explainer when the RunSignUp key is unconfigured
  ///
  /// In en, this message translates to:
  /// **'RunSignUp import isn\'t available yet. parkrun and manual paste still work.'**
  String get integrationsRunsignupUnavailable;

  /// ChronoTrack integration name
  ///
  /// In en, this message translates to:
  /// **'ChronoTrack'**
  String get integrationsChronotrack;

  /// ChronoTrack integration description
  ///
  /// In en, this message translates to:
  /// **'Import race results from ChronoTrack-timed events.'**
  String get integrationsChronotrackConnect;

  /// Action linking to the race calendar from the ChronoTrack tile
  ///
  /// In en, this message translates to:
  /// **'Open the race calendar'**
  String get integrationsChronotrackOpen;

  /// Explainer when the ChronoTrack credentials are unconfigured
  ///
  /// In en, this message translates to:
  /// **'ChronoTrack import isn\'t available yet. parkrun and manual paste still work.'**
  String get integrationsChronotrackUnavailable;

  /// Header for the route condition-reports panel
  ///
  /// In en, this message translates to:
  /// **'Conditions'**
  String get routeConditionsTitle;

  /// Button to open the condition-report composer
  ///
  /// In en, this message translates to:
  /// **'Report condition'**
  String get routeConditionsReport;

  /// Submit button busy label while a condition report is being sent
  ///
  /// In en, this message translates to:
  /// **'Reporting…'**
  String get routeConditionsReporting;

  /// Confirmation banner after a condition report is filed
  ///
  /// In en, this message translates to:
  /// **'Condition reported'**
  String get routeConditionsReported;

  /// Error banner when a condition report fails to send
  ///
  /// In en, this message translates to:
  /// **'Could not report condition'**
  String get routeConditionsReportFailed;

  /// Empty state for the route condition-reports panel
  ///
  /// In en, this message translates to:
  /// **'No condition reports yet.'**
  String get routeConditionsEmpty;

  /// Loading state for the route condition-reports panel
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get routeConditionsLoading;

  /// Cancel the condition-report composer
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get routeConditionsCancel;

  /// Delete a condition report
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get routeConditionsDelete;

  /// Title of the delete-condition confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete report?'**
  String get routeConditionsDeleteTitle;

  /// Body of the delete-condition confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This removes the condition report permanently.'**
  String get routeConditionsDeleteConfirm;

  /// Error banner when deleting a condition report fails
  ///
  /// In en, this message translates to:
  /// **'Could not delete report'**
  String get routeConditionsDeleteFailed;

  /// Label for the condition-kind dropdown in the composer
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get routeConditionsKindLabel;

  /// Label for the severity dropdown in the composer
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get routeConditionsSeverityLabel;

  /// Label for the optional note field in the composer
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get routeConditionsNoteLabel;

  /// Placeholder for the optional note field in the composer
  ///
  /// In en, this message translates to:
  /// **'What will the next runner hit?'**
  String get routeConditionsNotePlaceholder;

  /// Distance-along-route label on an anchored condition report
  ///
  /// In en, this message translates to:
  /// **'at {distance}'**
  String routeConditionsAtDistance(String distance);

  /// Condition kind: muddy
  ///
  /// In en, this message translates to:
  /// **'Muddy'**
  String get routeConditionMuddy;

  /// Condition kind: flooded
  ///
  /// In en, this message translates to:
  /// **'Flooded'**
  String get routeConditionFlooded;

  /// Condition kind: snow or ice
  ///
  /// In en, this message translates to:
  /// **'Snow / ice'**
  String get routeConditionSnowIce;

  /// Condition kind: overgrown
  ///
  /// In en, this message translates to:
  /// **'Overgrown'**
  String get routeConditionOvergrown;

  /// Condition kind: closed
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get routeConditionClosed;

  /// Condition kind: hazard
  ///
  /// In en, this message translates to:
  /// **'Hazard'**
  String get routeConditionHazard;

  /// Condition kind: clear
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get routeConditionClear;

  /// Condition kind: other
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get routeConditionOther;

  /// Severity: info
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get routeConditionSeverityInfo;

  /// Severity: caution
  ///
  /// In en, this message translates to:
  /// **'Caution'**
  String get routeConditionSeverityCaution;

  /// Severity: impassable
  ///
  /// In en, this message translates to:
  /// **'Impassable'**
  String get routeConditionSeverityImpassable;

  /// Settings toggle: spoken turn-by-turn cues while following a route
  ///
  /// In en, this message translates to:
  /// **'Turn-by-turn voice cues'**
  String get prefTurnByTurnCues;

  /// Subtitle for the turn-by-turn voice cues settings toggle
  ///
  /// In en, this message translates to:
  /// **'Spoken turn directions while following a saved route'**
  String get prefTurnByTurnCuesSubtitle;

  /// Spoken turn cue: left turn ahead at a distance
  ///
  /// In en, this message translates to:
  /// **'In {distance}, turn left'**
  String ttsTurnLeftIn(String distance);

  /// Spoken turn cue: right turn ahead at a distance
  ///
  /// In en, this message translates to:
  /// **'In {distance}, turn right'**
  String ttsTurnRightIn(String distance);

  /// Spoken turn cue: turn left now
  ///
  /// In en, this message translates to:
  /// **'Turn left'**
  String get ttsTurnLeftNow;

  /// Spoken turn cue: turn right now
  ///
  /// In en, this message translates to:
  /// **'Turn right'**
  String get ttsTurnRightNow;

  /// Spoken turn cue: slight left
  ///
  /// In en, this message translates to:
  /// **'Bear left'**
  String get ttsSlightLeft;

  /// Spoken turn cue: slight right
  ///
  /// In en, this message translates to:
  /// **'Bear right'**
  String get ttsSlightRight;

  /// Spoken turn cue: u-turn
  ///
  /// In en, this message translates to:
  /// **'Make a U-turn'**
  String get ttsUturn;

  /// Progress label while an offline map tile pack downloads
  ///
  /// In en, this message translates to:
  /// **'Caching map: {done} / {total}'**
  String routeOfflinePackDownloading(int done, int total);

  /// Status when an offline map tile pack finished downloading
  ///
  /// In en, this message translates to:
  /// **'Map saved for offline'**
  String get routeOfflinePackReady;

  /// Status when an offline map tile pack only partly downloaded
  ///
  /// In en, this message translates to:
  /// **'Map partly saved ({done} / {total}) — retry'**
  String routeOfflinePackPartial(int done, int total);

  /// Error when a route's offline tile pack would exceed the tile cap
  ///
  /// In en, this message translates to:
  /// **'This route is too large to cache offline'**
  String get routeOfflinePackTooLarge;

  /// Achievements tab / section title
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get badgesSectionTitle;

  /// Achievements section subtitle
  ///
  /// In en, this message translates to:
  /// **'Milestones you\'ve earned'**
  String get badgesSectionSubtitle;

  /// Empty state on your own achievements list
  ///
  /// In en, this message translates to:
  /// **'No badges yet — keep running.'**
  String get badgesEmpty;

  /// Empty state on someone else's achievements list
  ///
  /// In en, this message translates to:
  /// **'No public badges yet.'**
  String get badgesEmptyOther;

  /// Earned-date line on a badge tile
  ///
  /// In en, this message translates to:
  /// **'Earned {date}'**
  String badgesEarnedOn(String date);

  /// Feed badge-strip chip text
  ///
  /// In en, this message translates to:
  /// **'{name} earned the {badge} badge'**
  String badgesFeedEarned(String name, String badge);

  /// Fallback name when a badge awardee has no display name
  ///
  /// In en, this message translates to:
  /// **'A runner'**
  String get badgesARunner;

  /// Bronze tier label
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get badgesTierBronze;

  /// Silver tier label
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get badgesTierSilver;

  /// Gold tier label
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get badgesTierGold;

  /// Platinum tier label
  ///
  /// In en, this message translates to:
  /// **'Platinum'**
  String get badgesTierPlatinum;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'First 5K'**
  String get badgesDistanceSingle5kLabel;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 5 km in a single run'**
  String get badgesDistanceSingle5kDesc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Half marathon'**
  String get badgesDistanceSingleHalfLabel;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 21.1 km in a single run'**
  String get badgesDistanceSingleHalfDesc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Marathon'**
  String get badgesDistanceSingleMarathonLabel;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 42.2 km in a single run'**
  String get badgesDistanceSingleMarathonDesc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Ultra'**
  String get badgesDistanceSingleUltraLabel;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 50 km or more in a single run'**
  String get badgesDistanceSingleUltraDesc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'100 km club'**
  String get badgesDistanceLifetime100Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'100 km logged all-time'**
  String get badgesDistanceLifetime100Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'500 km'**
  String get badgesDistanceLifetime500Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'500 km logged all-time'**
  String get badgesDistanceLifetime500Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'1,000 km club'**
  String get badgesDistanceLifetime1000Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'1,000 km logged all-time'**
  String get badgesDistanceLifetime1000Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'5,000 km'**
  String get badgesDistanceLifetime5000Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'5,000 km logged all-time'**
  String get badgesDistanceLifetime5000Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Week streak'**
  String get badgesStreak7Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 7 days in a row'**
  String get badgesStreak7Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Month streak'**
  String get badgesStreak30Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 30 days in a row'**
  String get badgesStreak30Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Century streak'**
  String get badgesStreak100Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 100 days in a row'**
  String get badgesStreak100Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Year streak'**
  String get badgesStreak365Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Ran 365 days in a row'**
  String get badgesStreak365Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'First PR'**
  String get badgesPr1Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Set your first personal record'**
  String get badgesPr1Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Triple PR'**
  String get badgesPr3Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Hold personal records at 3 distances'**
  String get badgesPr3Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'PR collector'**
  String get badgesPr5Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Hold personal records at every distance'**
  String get badgesPr5Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Plan finisher'**
  String get badgesPlan1Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Completed a training plan'**
  String get badgesPlan1Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Triple finisher'**
  String get badgesPlan3Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Completed 3 training plans'**
  String get badgesPlan3Desc;

  /// Badge label
  ///
  /// In en, this message translates to:
  /// **'Plan veteran'**
  String get badgesPlan10Label;

  /// Badge description
  ///
  /// In en, this message translates to:
  /// **'Completed 10 training plans'**
  String get badgesPlan10Desc;

  /// Title of the dashboard race-time predictor card
  ///
  /// In en, this message translates to:
  /// **'Race-time predictor'**
  String get racePredictorTitle;

  /// Anchor line naming the effort the ladder is projected from
  ///
  /// In en, this message translates to:
  /// **'From your {distance} effort in {time}'**
  String racePredictorAnchoredOn(String distance, String time);

  /// Race predictor table column header for distance
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get racePredictorColDistance;

  /// Race predictor table column header for predicted time
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get racePredictorColTime;

  /// Race predictor table column header for pace
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get racePredictorColPace;

  /// Race predictor table column header for the confidence chip
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get racePredictorColConfidence;

  /// Race predictor confidence chip label, high
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get racePredictorConfidenceHigh;

  /// Race predictor confidence chip label, moderate
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get racePredictorConfidenceModerate;

  /// Race predictor confidence chip label, low
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get racePredictorConfidenceLow;

  /// Race predictor confidence reason tooltip, similar distance
  ///
  /// In en, this message translates to:
  /// **'Based on recent efforts close to this distance.'**
  String get racePredictorConfReasonSimilar;

  /// Race predictor confidence reason tooltip, extrapolated
  ///
  /// In en, this message translates to:
  /// **'Extrapolated across a large distance gap — treat as a ballpark.'**
  String get racePredictorConfReasonExtrapolated;

  /// Race predictor confidence reason tooltip, stale effort
  ///
  /// In en, this message translates to:
  /// **'Anchored to an effort that\'s a few weeks old.'**
  String get racePredictorConfReasonStale;

  /// Race predictor confidence reason tooltip, limited data
  ///
  /// In en, this message translates to:
  /// **'Based on limited recent data.'**
  String get racePredictorConfReasonLimited;

  /// Race predictor explanatory footnote
  ///
  /// In en, this message translates to:
  /// **'Riegel equivalence from your best recent effort, recency-weighted. Closer distances are more reliable.'**
  String get racePredictorFootnote;

  /// No description provided for @settingsSectionDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get settingsSectionDeveloper;

  /// No description provided for @settingsTabSimWatchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live status from the simulated custom watch'**
  String get settingsTabSimWatchSubtitle;

  /// No description provided for @simWatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Sim watch link'**
  String get simWatchTitle;

  /// No description provided for @simWatchHostLabel.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get simWatchHostLabel;

  /// No description provided for @simWatchPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get simWatchPortLabel;

  /// No description provided for @simWatchConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get simWatchConnect;

  /// No description provided for @simWatchConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get simWatchConnecting;

  /// No description provided for @simWatchDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get simWatchDisconnect;

  /// No description provided for @simWatchConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String simWatchConnectionFailed(String error);

  /// Button that pulls recorded runs off the custom watch over BLE
  ///
  /// In en, this message translates to:
  /// **'Sync runs from watch'**
  String get simWatchSyncAction;

  /// No description provided for @simWatchSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing… {done}/{total}'**
  String simWatchSyncing(int done, int total);

  /// No description provided for @simWatchResult.
  ///
  /// In en, this message translates to:
  /// **'Synced {synced} of {total} run(s) from the watch'**
  String simWatchResult(int synced, int total);

  /// No description provided for @simWatchSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Watch sync failed: {error}'**
  String simWatchSyncFailed(String error);

  /// Button that pushes the user's config to the custom watch over BLE
  ///
  /// In en, this message translates to:
  /// **'Push settings to watch'**
  String get simWatchPushSettingsAction;

  /// No description provided for @simWatchSettingsPushed.
  ///
  /// In en, this message translates to:
  /// **'Settings pushed to the watch'**
  String get simWatchSettingsPushed;

  /// No description provided for @simWatchPushSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Settings push failed: {error}'**
  String simWatchPushSettingsFailed(String error);

  /// No description provided for @simWatchNoRuns.
  ///
  /// In en, this message translates to:
  /// **'No runs on the watch to sync'**
  String get simWatchNoRuns;

  /// No description provided for @simWatchWaitingFrames.
  ///
  /// In en, this message translates to:
  /// **'Connected — waiting for frames…'**
  String get simWatchWaitingFrames;

  /// No description provided for @simWatchUptime.
  ///
  /// In en, this message translates to:
  /// **'Watch uptime'**
  String get simWatchUptime;

  /// No description provided for @simWatchNoFix.
  ///
  /// In en, this message translates to:
  /// **'No GPS fix yet'**
  String get simWatchNoFix;

  /// No description provided for @simWatchPosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get simWatchPosition;

  /// No description provided for @simWatchSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get simWatchSpeed;

  /// No description provided for @simWatchSatellites.
  ///
  /// In en, this message translates to:
  /// **'Satellites'**
  String get simWatchSatellites;

  /// No description provided for @simWatchAltitude.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get simWatchAltitude;

  /// No description provided for @simWatchBaroAltitude.
  ///
  /// In en, this message translates to:
  /// **'Barometric altitude'**
  String get simWatchBaroAltitude;

  /// No description provided for @simWatchAscent.
  ///
  /// In en, this message translates to:
  /// **'Ascent'**
  String get simWatchAscent;

  /// No description provided for @simWatchDescent.
  ///
  /// In en, this message translates to:
  /// **'Descent'**
  String get simWatchDescent;

  /// No description provided for @simWatchFixAge.
  ///
  /// In en, this message translates to:
  /// **'Fix age'**
  String get simWatchFixAge;

  /// No description provided for @simWatchSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String simWatchSeconds(int seconds);
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
