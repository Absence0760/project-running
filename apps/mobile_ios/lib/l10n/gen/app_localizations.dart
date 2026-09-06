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

  /// First line of the shared month-in-running recap summary
  ///
  /// In en, this message translates to:
  /// **'My {period} in running:'**
  String recapMonthShareHeadline(Object period);

  /// OS share-sheet subject for the month-in-running recap
  ///
  /// In en, this message translates to:
  /// **'{period} recap'**
  String recapMonthShareSubject(Object period);

  /// App bar title for the year-in-running recap screen
  ///
  /// In en, this message translates to:
  /// **'Year in running'**
  String get recapTitle;

  /// App bar title for the month-in-running recap screen
  ///
  /// In en, this message translates to:
  /// **'Month in running'**
  String get recapMonthTitle;

  /// Toggle label selecting the annual recap
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get recapPeriodYear;

  /// Toggle label selecting the monthly recap
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get recapPeriodMonth;

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

  /// Tooltip for the previous-month chevron on the recap screen
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get recapPrevMonth;

  /// Tooltip for the next-month chevron on the recap screen
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get recapNextMonth;

  /// Empty-state shown for a recap period outside the valid range
  ///
  /// In en, this message translates to:
  /// **'No runs to recap for {period}.'**
  String recapNoRunsForPeriod(Object period);

  /// Empty-state shown when no runs exist for the selected recap period
  ///
  /// In en, this message translates to:
  /// **'No runs in {period} yet. Log one to see your recap.'**
  String recapNoRunsYetInPeriod(Object period);

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

  /// Heading above the import failure report, counting the activities that did not import
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 activity didn\'t import} other{{count} activities didn\'t import}}'**
  String importFailuresHeading(int count);

  /// Explains that re-running the import retries the failures without duplicating
  ///
  /// In en, this message translates to:
  /// **'Re-run the import to retry these — anything that already landed is skipped, so nothing is duplicated.'**
  String get importFailuresIntro;

  /// Shown when the failure log hit its recording cap
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 further failure was not recorded.} other{{count} further failures were not recorded.}}'**
  String importFailuresTruncated(int count);

  /// Expander label revealing each failed activity
  ///
  /// In en, this message translates to:
  /// **'Show each activity'**
  String get importFailuresShowDetail;

  /// Button that shares the failure report as a CSV file
  ///
  /// In en, this message translates to:
  /// **'Share report (CSV)'**
  String get importFailuresShare;

  /// Banner when sharing the failure report CSV failed
  ///
  /// In en, this message translates to:
  /// **'Could not share the report.'**
  String get importFailuresShareFailed;

  /// Button that hides the import failure report
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get importFailuresDismiss;

  /// Placeholder when a failed activity has no known start date
  ///
  /// In en, this message translates to:
  /// **'Date unknown'**
  String get importFailuresNoDate;

  /// Import failure reason: the connection dropped
  ///
  /// In en, this message translates to:
  /// **'Connection dropped'**
  String get importFailuresReasonNetwork;

  /// Import failure reason: the session was signed out
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get importFailuresReasonAuth;

  /// Import failure reason: rate limited
  ///
  /// In en, this message translates to:
  /// **'Rate limited'**
  String get importFailuresReasonRateLimited;

  /// Import failure reason: the file was too large
  ///
  /// In en, this message translates to:
  /// **'File too large'**
  String get importFailuresReasonTooLarge;

  /// Import failure reason: the file could not be read
  ///
  /// In en, this message translates to:
  /// **'File could not be read'**
  String get importFailuresReasonUnparseable;

  /// Import failure reason: the server refused the write
  ///
  /// In en, this message translates to:
  /// **'Rejected by the server'**
  String get importFailuresReasonRejected;

  /// Import failure reason: unrecognised error
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get importFailuresReasonUnknown;

  /// Shown when imported runs saved locally but the upload to the cloud failed for some or all of them
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 run is saved on this device — its upload to the cloud didn\'t go through. It will retry on the next sync.} other{{count} runs are saved on this device — their upload to the cloud didn\'t go through. They will retry on the next sync.}}'**
  String importStatusCloudPushDeferred(int count);

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

  /// Offer shown after a Health Connect import found routes it was refused
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 imported activity has a GPS map Threkir isn\'t allowed to read.} other{{count} imported activities have GPS maps Threkir isn\'t allowed to read.}} Health Connect keeps a workout\'s route behind its own permission.'**
  String importHealthRoutesWithheld(int count);

  /// No description provided for @importHealthRoutesAllowButton.
  ///
  /// In en, this message translates to:
  /// **'Allow map import'**
  String get importHealthRoutesAllowButton;

  /// No description provided for @importHealthRoutesRequesting.
  ///
  /// In en, this message translates to:
  /// **'Asking Health Connect for map access...'**
  String get importHealthRoutesRequesting;

  /// No description provided for @importHealthRoutesDenied.
  ///
  /// In en, this message translates to:
  /// **'Map access not granted. Imports stay summary-only — you can change this in Health Connect at any time.'**
  String get importHealthRoutesDenied;

  /// No description provided for @importHealthRoutesAdding.
  ///
  /// In en, this message translates to:
  /// **'Adding maps to imported activities...'**
  String get importHealthRoutesAdding;

  /// Status after backfilling maps onto already-imported activities
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No maps could be added.} one{Added a map to 1 activity.} other{Added maps to {count} activities.}}'**
  String importHealthRoutesAdded(int count);

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

  /// Generic cancel action for a destructive-confirm dialog whose surface has no cancel label of its own
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Dropdown row shown when a place search succeeded but matched nothing
  ///
  /// In en, this message translates to:
  /// **'No places found'**
  String get placeSearchNoResults;

  /// Dropdown row shown when the place-search provider failed, rate-limited, or timed out — deliberately distinct from a no-results answer
  ///
  /// In en, this message translates to:
  /// **'Place search is unavailable right now'**
  String get placeSearchUnavailable;

  /// Action on the place-search-unavailable row that re-runs the lookup
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get placeSearchRetry;

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

  /// Section heading for the opt-in coarse-location runners-nearby list on the People screen
  ///
  /// In en, this message translates to:
  /// **'Runners nearby'**
  String get peopleNearbyHeader;

  /// Explanatory subtitle under the runners-nearby heading
  ///
  /// In en, this message translates to:
  /// **'Runners who opted in near the area you set. Approximate distance only — never a live location.'**
  String get peopleNearbySubtitle;

  /// Empty-state title when the runners-nearby list comes back with no one
  ///
  /// In en, this message translates to:
  /// **'Nobody nearby yet'**
  String get peopleNearbyEmptyTitle;

  /// Empty-state body for the runners-nearby list, pointing at the opt-in and area setter
  ///
  /// In en, this message translates to:
  /// **'Turn on \"Show me to runners nearby\" and set your area. Only runners who did the same can find you.'**
  String get peopleNearbyEmptyBody;

  /// Button on the runners-nearby empty state that opens the Preferences settings screen
  ///
  /// In en, this message translates to:
  /// **'Open Preferences'**
  String get peopleNearbyEmptyAction;

  /// Error-state message when the runners-nearby list fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load runners nearby.'**
  String get peopleNearbyLoadFailed;

  /// Coarse distance label for a nearby runner — the bucket's upper bound, never an exact distance
  ///
  /// In en, this message translates to:
  /// **'Within {distance}'**
  String peopleNearbyWithin(String distance);

  /// Coarse distance label for the open-ended furthest bucket
  ///
  /// In en, this message translates to:
  /// **'Beyond {distance}'**
  String peopleNearbyBeyond(String distance);

  /// Toggle title for opting in to coarse-location runners-nearby discovery
  ///
  /// In en, this message translates to:
  /// **'Show me to runners nearby'**
  String get prefsDiscoverableNearby;

  /// Subtitle for the runners-nearby opt-in toggle
  ///
  /// In en, this message translates to:
  /// **'Off by default. When on, other runners who also opted in can see that you are roughly nearby — an approximate distance from the area you set, never your location.'**
  String get prefsDiscoverableNearbySubtitle;

  /// Title of the coarse-area setter screen and of the Settings row that opens it
  ///
  /// In en, this message translates to:
  /// **'Your area'**
  String get nearbyAreaTitle;

  /// Explanatory paragraph at the top of the coarse-area setter
  ///
  /// In en, this message translates to:
  /// **'Pick the city or neighbourhood you run in. It is stored rounded to about a kilometre and is never your live location. Other runners only ever see an approximate distance, never the area itself.'**
  String get nearbyAreaExplainer;

  /// Shown when the runner has not set a coarse area
  ///
  /// In en, this message translates to:
  /// **'No area set'**
  String get nearbyAreaNone;

  /// Shows the coarse area the runner has set
  ///
  /// In en, this message translates to:
  /// **'Current area: {label}'**
  String nearbyAreaCurrent(String label);

  /// Hint text of the place-search field on the coarse-area setter
  ///
  /// In en, this message translates to:
  /// **'Search for a city or neighbourhood'**
  String get nearbyAreaSearchHint;

  /// Shown when the geocoding provider fails — distinct from no matches
  ///
  /// In en, this message translates to:
  /// **'Place search is unavailable right now.'**
  String get nearbyAreaSearchUnavailable;

  /// Shown when the place search returns no matches
  ///
  /// In en, this message translates to:
  /// **'No places matched that search.'**
  String get nearbyAreaNoResults;

  /// Confirmation banner after the coarse area is stored
  ///
  /// In en, this message translates to:
  /// **'Area saved'**
  String get nearbyAreaSaved;

  /// Failure banner when storing the coarse area fails
  ///
  /// In en, this message translates to:
  /// **'Could not save your area.'**
  String get nearbyAreaSaveFailed;

  /// Error-state message when reading the stored coarse-area label fails
  ///
  /// In en, this message translates to:
  /// **'Could not load your area.'**
  String get nearbyAreaLoadFailed;

  /// Destructive action that clears the stored coarse area
  ///
  /// In en, this message translates to:
  /// **'Forget my area'**
  String get nearbyAreaForget;

  /// Confirm-dialog title for clearing the stored coarse area
  ///
  /// In en, this message translates to:
  /// **'Forget your area?'**
  String get nearbyAreaForgetConfirmTitle;

  /// Confirm-dialog body for clearing the stored coarse area
  ///
  /// In en, this message translates to:
  /// **'You will stop appearing to runners nearby until you set an area again.'**
  String get nearbyAreaForgetConfirmBody;

  /// Confirmation banner after the coarse area is cleared
  ///
  /// In en, this message translates to:
  /// **'Area forgotten'**
  String get nearbyAreaForgotten;

  /// Failure banner when clearing the coarse area fails
  ///
  /// In en, this message translates to:
  /// **'Could not forget your area.'**
  String get nearbyAreaForgetFailed;

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

  /// Body of the signed-out state on the People screen; people search is auth-gated so a signed-out search can only fail
  ///
  /// In en, this message translates to:
  /// **'Sign in to search for and follow other runners.'**
  String get peopleSignedOutMessage;

  /// Error-state message when the suggested-people list fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load suggestions.'**
  String get peopleSuggestionsLoadFailed;

  /// Header label on the dashboard readiness-to-run card
  ///
  /// In en, this message translates to:
  /// **'Readiness'**
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

  /// Accessibility label for the labelled peer strip on the run surface
  ///
  /// In en, this message translates to:
  /// **'Run surface sections'**
  String get runSurfaceLabel;

  /// Run surface peer strip entry opening the training plan library
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get runSurfaceTabPlans;

  /// Run surface peer strip entry opening the race calendar
  ///
  /// In en, this message translates to:
  /// **'Races'**
  String get runSurfaceTabRaces;

  /// Accessibility label for the labelled peer strip on the gym surface
  ///
  /// In en, this message translates to:
  /// **'Gym sections'**
  String get gymSurfaceLabel;

  /// Gym peer strip entry for the logged-workout list
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get gymTabLog;

  /// Gym peer strip entry opening personal records
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get gymTabRecords;

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

  /// Error state shown when the body-metrics screen fails to load the saved profile
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your body metrics.'**
  String get bodyMetricsLoadError;

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

  /// Example email placeholder in the add-safety-contact input; the local part is localized, the example.com domain is RFC 2606 reserved and must stay
  ///
  /// In en, this message translates to:
  /// **'partner@example.com'**
  String get safetyAddHint;

  /// Label for the optional safety-contact phone input (E.164 international format)
  ///
  /// In en, this message translates to:
  /// **'Phone for SMS (optional)'**
  String get safetyPhoneLabel;

  /// Hint under the add-contact form explaining that SMS is additive and needs the contact’s own consent
  ///
  /// In en, this message translates to:
  /// **'Add a mobile number and this contact can also be alerted by SMS — they choose whether to when they confirm. Alerts by email are always sent.'**
  String get safetyPhoneHint;

  /// Inline validation banner when the typed phone cannot be read as an international number
  ///
  /// In en, this message translates to:
  /// **'Enter the phone in international format, e.g. +447700900123.'**
  String get safetyInvalidPhone;

  /// Badge on a safety contact who has a number on file AND opted in to SMS
  ///
  /// In en, this message translates to:
  /// **'SMS on'**
  String get safetySmsBadge;

  /// Shown on a safety contact with a number on file whose owner has not consented to SMS; the alert reaches them by email only
  ///
  /// In en, this message translates to:
  /// **'SMS off — they haven\'t opted in yet'**
  String get safetySmsPending;

  /// Checkbox on an incoming safety-contact request, offered only when the requester stored a phone number
  ///
  /// In en, this message translates to:
  /// **'Also alert me by SMS'**
  String get safetyConfirmSmsLabel;

  /// Heading above the relationships the user is the safety contact of
  ///
  /// In en, this message translates to:
  /// **'You are a safety contact'**
  String get safetyContactOfTitle;

  /// Intro under the you-are-a-safety-contact heading
  ///
  /// In en, this message translates to:
  /// **'These runners named you as their emergency contact and you confirmed. Change how you\'re alerted, or withdraw, whenever you like.'**
  String get safetyContactOfIntro;

  /// Names the runner whose safety contact the user is
  ///
  /// In en, this message translates to:
  /// **'Emergency contact for {name}'**
  String safetyContactOfFor(String name);

  /// Toggle label for the contact-side SMS consent
  ///
  /// In en, this message translates to:
  /// **'Alert me by SMS as well as email'**
  String get safetyContactOfSmsLabel;

  /// Shown instead of the SMS toggle when the runner stored no number
  ///
  /// In en, this message translates to:
  /// **'SMS alerts need a mobile number for you, and none is on file. Email alerts are always sent.'**
  String get safetyContactOfNoPhone;

  /// Toast after turning SMS alerts on
  ///
  /// In en, this message translates to:
  /// **'SMS alerts on.'**
  String get safetyContactOfSmsOnToast;

  /// Toast after turning SMS alerts off
  ///
  /// In en, this message translates to:
  /// **'SMS alerts off.'**
  String get safetyContactOfSmsOffToast;

  /// Shown when the relationship no longer exists server-side
  ///
  /// In en, this message translates to:
  /// **'That request is no longer active — the runner may have removed it.'**
  String get safetyContactOfSmsNoChange;

  /// Error toast when changing the SMS consent fails
  ///
  /// In en, this message translates to:
  /// **'Could not update your SMS choice: {error}'**
  String safetyContactOfSmsFailed(String error);

  /// Button to withdraw from being someone else’s safety contact
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get safetyContactOfWithdraw;

  /// Confirm-dialog body for withdrawing as a safety contact
  ///
  /// In en, this message translates to:
  /// **'Stop being this runner\'s safety contact? They won\'t be able to alert you any more, and they\'d have to send a new request to add you back.'**
  String get safetyContactOfWithdrawConfirm;

  /// Toast after withdrawing as a safety contact
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer a safety contact.'**
  String get safetyContactOfWithdrawnToast;

  /// Error toast when withdrawing as a safety contact fails
  ///
  /// In en, this message translates to:
  /// **'Could not withdraw: {error}'**
  String safetyContactOfWithdrawFailed(String error);

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

  /// Error toast when removing a safety contact fails
  ///
  /// In en, this message translates to:
  /// **'Could not remove contact: {error}'**
  String safetyRemoveFailed(String error);

  /// Error toast when a safety setting write fails and the control is reverted
  ///
  /// In en, this message translates to:
  /// **'Could not save setting: {error}'**
  String safetySettingSaveFailed(String error);

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
  /// **'Start a live share automatically when a run starts on this phone. The in-progress run is viewable by anyone with the link; when the run ends it returns to your default run visibility.'**
  String get safetyAutoLiveShareSubtitle;

  /// Title of the off-route auto-notify toggle on the safety settings screen
  ///
  /// In en, this message translates to:
  /// **'Off-route alert'**
  String get safetyOffRouteTitle;

  /// Subtitle of the off-route auto-notify toggle
  ///
  /// In en, this message translates to:
  /// **'Alert a confirmed contact if you go and stay off your planned route on a live-shared run.'**
  String get safetyOffRouteSubtitle;

  /// Banner on the run screen when a sustained off-route departure escalated to safety contacts
  ///
  /// In en, this message translates to:
  /// **'We alerted your safety contact — you\'ve been off route for a while.'**
  String get runOffRouteAlertSent;

  /// Banner on the run screen when the auto-live-share pref attached the broadcaster
  ///
  /// In en, this message translates to:
  /// **'Live sharing is on — use Share live link to send it'**
  String get runAutoLiveShareStarted;

  /// One-time dismissible nudge on the run screen when a solo run starts after dark with no live share
  ///
  /// In en, this message translates to:
  /// **'Running solo after dark? Share a live link so someone can follow along.'**
  String get runSafetyNudgeSolo;

  /// Action button on the solo-run safety nudge banner; shares a live link for the current run
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get runSafetyNudgeShareAction;

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

  /// Tooltip/a11y label for the eye toggle that reveals an obscured password field
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// Tooltip/a11y label for the eye toggle while the password is revealed
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// Divider text between the email/password form and the OAuth buttons
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get authOrDivider;

  /// Friendly auth error shown when sign-in/sign-up fails because the device has no network connection
  ///
  /// In en, this message translates to:
  /// **'You appear to be offline. Check your connection and try again.'**
  String get authErrorOffline;

  /// Friendly auth error shown when sign-in fails because the email or password was wrong
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password. Please try again.'**
  String get authErrorInvalidCredentials;

  /// Friendly auth error shown when sign-in/sign-up is rate-limited (too many requests)
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get authErrorRateLimited;

  /// Friendly fallback auth error shown when sign-in/sign-up fails for an unrecognised reason
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get authErrorGeneric;

  /// Friendly error shown when an action requires a signed-in account
  ///
  /// In en, this message translates to:
  /// **'You need to be signed in to do that. Sign in and try again.'**
  String get authErrorNotSignedIn;

  /// Friendly auth error shown when sign-up fails because the email is already registered
  ///
  /// In en, this message translates to:
  /// **'That email already has an account. Sign in instead.'**
  String get authErrorEmailExists;

  /// Friendly auth error shown when sign-in fails because the email address hasn't been confirmed yet
  ///
  /// In en, this message translates to:
  /// **'Confirm your email first — check your inbox for the confirmation link.'**
  String get authErrorEmailNotConfirmed;

  /// Friendly auth error shown when the server rejects a password as too weak
  ///
  /// In en, this message translates to:
  /// **'That password is too weak. Use at least {minLength} characters.'**
  String authErrorWeakPassword(int minLength);

  /// Inline validation error under the sign-up email field when the entered value is not email-shaped
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get authErrorInvalidEmail;

  /// Inline validation error when an entered password is shorter than the minimum length
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {minLength} characters.'**
  String authErrorPasswordTooShort(int minLength);

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

  /// Button that re-sends the signup confirmation email after an email-not-confirmed sign-in failure
  ///
  /// In en, this message translates to:
  /// **'Resend confirmation email'**
  String get signInResendConfirmation;

  /// Privacy-preserving confirmation shown after re-sending the signup confirmation email
  ///
  /// In en, this message translates to:
  /// **'If that email is registered, we\'ve sent a new confirmation link.'**
  String get signInConfirmationResent;

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

  /// Notice shown when the Apple button is tapped but the Android web-auth flow isn't configured yet
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in is coming soon. For now, please use email.'**
  String get appleSignInSoon;

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

  /// Conjunction between the Terms of Service and Privacy Policy links in the terms-acceptance checkbox label
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get signUpAcceptConjunction;

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

  /// Label for the password-confirmation field on the sign-up screen. Sign-up is the only surface that mints a password on mobile, so this is not shared with the sign-in screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get signUpConfirmPasswordLabel;

  /// Validation error shown when the chosen password is shorter than the minimum
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {min} characters.'**
  String signUpErrorPasswordTooShort(int min);

  /// Validation error shown when the password and its confirmation differ
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match.'**
  String get signUpErrorPasswordMismatch;

  /// Headline of the check-your-email state shown after a sign-up that needs email confirmation
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get signUpCheckEmailTitle;

  /// Body of the check-your-email state shown after a sign-up that needs email confirmation
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to {email}. Open it to finish setting up your account.'**
  String signUpCheckEmailBody(String email);

  /// Button on the check-your-email state that returns to the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get signUpCheckEmailBack;

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

  /// Setup-wizard finish-step CTA that saves and opens the plan wizard preselected to the runner's chosen goal
  ///
  /// In en, this message translates to:
  /// **'Create my training plan'**
  String get setupCreatePlanCta;

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

  /// Toast shown when the setup wizard saved the profile but the preferences bag write failed
  ///
  /// In en, this message translates to:
  /// **'Your account is set up, but your preferences didn\'t save: {message}'**
  String setupPrefsSaveError(String message);

  /// Hint shown next to the setup wizard's offline fail-safe exit after a save failed
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server right now. You can finish setup later — everything here is editable in Settings.'**
  String get setupOfflineHint;

  /// Setup wizard fail-safe exit that closes the wizard without a server write and defers the onboarding stamp
  ///
  /// In en, this message translates to:
  /// **'Finish later'**
  String get setupFinishLater;

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

  /// Setup wizard final step hint when the runner picked a goal, so the primary action is Create my training plan
  ///
  /// In en, this message translates to:
  /// **'That\'s everything. Create a training plan for your goal, or open the dashboard to start running.'**
  String get setupDoneHintGoal;

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

  /// Screen-reader label for the tappable recent-run card on the start-run screen
  ///
  /// In en, this message translates to:
  /// **'Open last run details'**
  String get runLastRunOpenA11yLabel;

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

  /// Shown when a signed-out user tries to share a live tracking link, which cannot broadcast
  ///
  /// In en, this message translates to:
  /// **'Sign in to share a live tracking link.'**
  String get runLiveShareNeedsSignIn;

  /// Shown when the live broadcast failed to start after sharing the link, so the shared link would otherwise be dead
  ///
  /// In en, this message translates to:
  /// **'Live tracking couldn\'t start — tap Share to retry.'**
  String get runLiveShareNotStarted;

  /// Label on the persistent recording-screen pill that shows a live-tracking share is active
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get runLiveShareActive;

  /// Accessibility label for the live-share indicator pill on the recording screen
  ///
  /// In en, this message translates to:
  /// **'Live sharing is on. Tap to re-share the link or stop sharing.'**
  String get runLiveShareActiveSemantics;

  /// Title of the sheet opened from the live-share indicator, offering re-share and stop actions
  ///
  /// In en, this message translates to:
  /// **'Live sharing on'**
  String get runLiveShareSheetTitle;

  /// Action that re-opens the OS share sheet to resend the live tracking link
  ///
  /// In en, this message translates to:
  /// **'Share link again'**
  String get runLiveShareReshare;

  /// Action that stops the live-tracking share without ending the run
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get runLiveShareStop;

  /// Live-share sheet action opening the per-run expected-return control
  ///
  /// In en, this message translates to:
  /// **'Not back by…'**
  String get runLiveShareExpectedReturn;

  /// Title of the per-run expected-return dialog
  ///
  /// In en, this message translates to:
  /// **'Not back by…'**
  String get runExpectedReturnTitle;

  /// Intro in the expected-return dialog
  ///
  /// In en, this message translates to:
  /// **'Pick when you expect to be done. If this run is still going then, your confirmed safety contacts get one alert with your live link.'**
  String get runExpectedReturnIntro;

  /// Honesty note in the expected-return dialog: the alarm survives the app being killed, and a run saved offline can still escalate
  ///
  /// In en, this message translates to:
  /// **'The deadline is kept on the server, so it still counts if this phone dies. It clears when the run saves — a run that finishes with no signal can still alert until it syncs.'**
  String get runExpectedReturnServerNote;

  /// Expected-return option expressed in minutes from now
  ///
  /// In en, this message translates to:
  /// **'In {minutes} min'**
  String runExpectedReturnOptionMinutes(int minutes);

  /// Expected-return option expressed in hours from now
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{In 1 hour} other{In {hours} hours}}'**
  String runExpectedReturnOptionHours(int hours);

  /// Subtitle under an expected-return option showing the resulting local clock time
  ///
  /// In en, this message translates to:
  /// **'Back by {time}'**
  String runExpectedReturnBy(String time);

  /// Shown in the expected-return dialog when an alarm is already armed
  ///
  /// In en, this message translates to:
  /// **'Alert set for {time}.'**
  String runExpectedReturnActive(String time);

  /// Button clearing an armed expected-return alarm
  ///
  /// In en, this message translates to:
  /// **'Clear the alert'**
  String get runExpectedReturnClear;

  /// Banner after arming the expected-return alarm
  ///
  /// In en, this message translates to:
  /// **'Return-time alert set.'**
  String get runExpectedReturnSetToast;

  /// Banner after clearing the expected-return alarm
  ///
  /// In en, this message translates to:
  /// **'Return-time alert cleared.'**
  String get runExpectedReturnClearedToast;

  /// Banner when the expected-return write failed or was refused
  ///
  /// In en, this message translates to:
  /// **'Could not update the return-time alert.'**
  String get runExpectedReturnFailed;

  /// Banner when the expected-return state could not be read; the alarm lives on the server so it cannot be set offline
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server to set a return-time alert.'**
  String get runExpectedReturnUnavailable;

  /// Confirmation banner shown after the runner stops the live-tracking share mid-run
  ///
  /// In en, this message translates to:
  /// **'Live sharing stopped'**
  String get runLiveShareStopped;

  /// Title of the post-stop dialog asking whether a live-shared run should stay public
  ///
  /// In en, this message translates to:
  /// **'Live sharing ended'**
  String get runLiveShareEndedTitle;

  /// Body of the post-stop dialog: the live window is over and keeping the run public is an explicit choice
  ///
  /// In en, this message translates to:
  /// **'The live link no longer updates. Keep the saved run public so anyone with the link can view it? If not, it follows your default run visibility.'**
  String get runLiveShareEndedBody;

  /// Dialog action that keeps the finished live-shared run publicly viewable
  ///
  /// In en, this message translates to:
  /// **'Keep public'**
  String get runLiveShareKeepPublic;

  /// Dialog action that returns the finished live-shared run to the runner's default (not public) visibility
  ///
  /// In en, this message translates to:
  /// **'Keep private'**
  String get runLiveShareKeepPrivate;

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

  /// Caption under the stop button telling the user to press and hold (not tap) to end the run
  ///
  /// In en, this message translates to:
  /// **'Hold to stop'**
  String get runHoldToStopHint;

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

  /// Title of the cold-start prompt when a process-killed in-progress run is recovered
  ///
  /// In en, this message translates to:
  /// **'Resume your run?'**
  String get runResumeDialogTitle;

  /// Body of the cold-start resume prompt explaining the Resume / Finish / Discard choice
  ///
  /// In en, this message translates to:
  /// **'A run from an earlier session is still in progress. Resume recording where you left off, finish it now, or discard it.'**
  String get runResumeDialogBody;

  /// Primary action on the resume prompt — re-hydrate the recorder and continue the same run
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get runResumeAction;

  /// Action on the resume prompt — finalize the recovered partial into a completed run without recording more
  ///
  /// In en, this message translates to:
  /// **'Finish now'**
  String get runResumeFinishAction;

  /// Banner shown after the user resumes a process-killed run
  ///
  /// In en, this message translates to:
  /// **'Resumed your run.'**
  String get runResumedBanner;

  /// Banner shown after the user finalizes a recovered partial from the resume prompt
  ///
  /// In en, this message translates to:
  /// **'Saved your previous run.'**
  String get runResumeSavedBanner;

  /// Banner shown after the user discards a recovered partial from the resume prompt
  ///
  /// In en, this message translates to:
  /// **'Discarded your previous run.'**
  String get runResumeDiscardedBanner;

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

  /// Treadmill-mode toggle subtitle while the belt link is still being established
  ///
  /// In en, this message translates to:
  /// **'Connecting to the treadmill…'**
  String get runTreadmillConnecting;

  /// Treadmill-mode toggle subtitle while the belt is not feeding, so the headline distance comes from the GPS/pedometer path
  ///
  /// In en, this message translates to:
  /// **'No belt data — distance from GPS'**
  String get runTreadmillNoBeltData;

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

  /// Banner shown on returning to a recording run after the app was backgrounded under a foreground-only location grant and no fix arrived while away
  ///
  /// In en, this message translates to:
  /// **'Tracking paused while you were away — your run kept timing and nothing was lost, but distance covered off screen wasn’t counted. Set Location to \"Allow all the time\" to track in the background.'**
  String get runBackgroundLocationPaused;

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

  /// Screen-reader fragment on a runs-list row that is queued to sync
  ///
  /// In en, this message translates to:
  /// **'not yet synced'**
  String get historyUnsyncedRowSemantics;

  /// Screen-reader fragment on a runs-list row whose push is parked
  ///
  /// In en, this message translates to:
  /// **'cannot be uploaded'**
  String get historyBlockedRowSemantics;

  /// Tooltip on the per-row icon marking a run whose push is parked
  ///
  /// In en, this message translates to:
  /// **'Can\'t be uploaded'**
  String get historyBlockedRowTooltip;

  /// Tooltip on the History AppBar badge counting runs whose push is parked
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run can\'t be uploaded} other{{count} runs can\'t be uploaded}}'**
  String historyBlockedTooltip(int count);

  /// Banner on History when one or more runs are parked and will not be retried
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run can\'t be uploaded and won\'t be retried. Open it to choose what to do.} other{{count} runs can\'t be uploaded and won\'t be retried. Open each one to choose what to do.}}'**
  String historySyncBlocked(int count);

  /// Button on the parked-push card that uploads the run without its GPS trace
  ///
  /// In en, this message translates to:
  /// **'Upload without the trace'**
  String get runDetailBlockedDropTrack;

  /// Button on the parked-push card that opens the file-export sheet
  ///
  /// In en, this message translates to:
  /// **'Export a copy'**
  String get runDetailBlockedExport;

  /// Title of the run-detail card shown when the run's push is parked
  ///
  /// In en, this message translates to:
  /// **'This run can\'t be uploaded'**
  String get runDetailBlockedTitle;

  /// Body of the parked-push card when the run's GPS trace is larger than the cloud store allows
  ///
  /// In en, this message translates to:
  /// **'Its GPS trace ({waypoints} points) is larger than the cloud store will hold, so trying again will never work. Everything else about the run — distance, time, pace, elevation — can still be saved.'**
  String runDetailBlockedTrackTooLarge(int waypoints);

  /// Body of the confirmation dialog for uploading a run without its GPS trace
  ///
  /// In en, this message translates to:
  /// **'The trace is removed from this device and the run uploads without a map. Its distance, time, pace and elevation are unchanged. Export a copy first if you want to keep it.'**
  String get runDetailDropTrackBody;

  /// Confirm action in the drop-GPS-trace dialog
  ///
  /// In en, this message translates to:
  /// **'Upload without it'**
  String get runDetailDropTrackConfirm;

  /// Banner after the GPS trace was dropped so the run can sync
  ///
  /// In en, this message translates to:
  /// **'Trace removed. The run syncs on the next cycle.'**
  String get runDetailDropTrackDone;

  /// Banner when dropping the GPS trace failed
  ///
  /// In en, this message translates to:
  /// **'The trace could not be removed. Try again.'**
  String get runDetailDropTrackFailed;

  /// Title of the confirmation dialog for uploading a run without its GPS trace
  ///
  /// In en, this message translates to:
  /// **'Upload without the GPS trace?'**
  String get runDetailDropTrackTitle;

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

  /// Accessible label for the hours box of an hours/minutes/seconds duration entry — its visible 'h' suffix is decorative and is not part of the field's accessible name
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get durationFieldHours;

  /// Accessible label for the minutes box of an hours/minutes/seconds duration entry
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get durationFieldMinutes;

  /// Accessible label for the seconds box of an hours/minutes/seconds duration entry
  ///
  /// In en, this message translates to:
  /// **'Seconds'**
  String get durationFieldSeconds;

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

  /// Badge in the run-detail AppBar title for a run recovered after the watch reset mid-run — its totals are only what was recorded up to that point
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get runDetailIncompleteBadge;

  /// Long-press tooltip explaining the Incomplete badge on run detail
  ///
  /// In en, this message translates to:
  /// **'Your watch restarted mid-run. These totals are only what it had recorded up to that point, not the whole activity.'**
  String get runDetailIncompleteTooltip;

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

  /// Banner shown when saving the run edit to local storage fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your changes. Please try again.'**
  String get runDetailEditFailed;

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

  /// Secondary-stat label on run-detail for the share of the run the heart-rate sensor was delivering
  ///
  /// In en, this message translates to:
  /// **'HR coverage'**
  String get runDetailStatHrCoverage;

  /// Value of the HR-coverage secondary stat, a whole percent
  ///
  /// In en, this message translates to:
  /// **'{pct}%'**
  String runDetailHrCoveragePercent(int pct);

  /// Value shown in the average-heart-rate slot when the recorder suppressed the average because the sensor covered too little of the run
  ///
  /// In en, this message translates to:
  /// **'{pct}% covered'**
  String runDetailHrCoverageOnly(int pct);

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

  /// Caption of the pace-band legend under the run-detail elevation chart
  ///
  /// In en, this message translates to:
  /// **'Pace vs median'**
  String get runDetailPaceLegendTitle;

  /// Legend key for elevation-chart segments run faster than the run's median pace
  ///
  /// In en, this message translates to:
  /// **'Faster'**
  String get runDetailPaceBandFaster;

  /// Legend key for elevation-chart segments run within 10% of the run's median pace
  ///
  /// In en, this message translates to:
  /// **'Steady'**
  String get runDetailPaceBandSteady;

  /// Legend key for elevation-chart segments run slower than the run's median pace
  ///
  /// In en, this message translates to:
  /// **'Slower'**
  String get runDetailPaceBandSlower;

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

  /// Info note under the run-detail HR-zone breakdown when zones fall back to an age-estimated max HR (no hr_zones or max_hr_bpm override set)
  ///
  /// In en, this message translates to:
  /// **'Zones use an age-estimated max HR. On heart-rate medication (e.g. beta-blockers) or if you\'ve measured your max HR, set it in Preferences for accurate zones.'**
  String get runDetailHrDisclaimer;

  /// Button under the HR-zone disclaimer that opens Settings to set max HR / zones
  ///
  /// In en, this message translates to:
  /// **'Set max HR'**
  String get runDetailHrDisclaimerAction;

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

  /// Heading of the first-half vs second-half pacing card on run-detail
  ///
  /// In en, this message translates to:
  /// **'Pacing'**
  String get runDetailPacing;

  /// Label for the first half's pace in the pacing card
  ///
  /// In en, this message translates to:
  /// **'First half'**
  String get runDetailPacingFirstHalf;

  /// Label for the second half's pace in the pacing card
  ///
  /// In en, this message translates to:
  /// **'Second half'**
  String get runDetailPacingSecondHalf;

  /// Verdict chip when the second half was faster than the first
  ///
  /// In en, this message translates to:
  /// **'Negative split'**
  String get runDetailPacingNegative;

  /// Verdict chip when both halves were paced the same
  ///
  /// In en, this message translates to:
  /// **'Even split'**
  String get runDetailPacingEven;

  /// Verdict chip when the second half was slower than the first
  ///
  /// In en, this message translates to:
  /// **'Positive split'**
  String get runDetailPacingPositive;

  /// Pacing card summary when the second half was faster; delta is a seconds figure such as 14s
  ///
  /// In en, this message translates to:
  /// **'{delta} faster over the second half'**
  String runDetailPacingFaster(String delta);

  /// Pacing card summary when the second half was slower; delta is a seconds figure such as 14s
  ///
  /// In en, this message translates to:
  /// **'{delta} slower over the second half'**
  String runDetailPacingSlower(String delta);

  /// Pacing card summary when both halves were paced the same
  ///
  /// In en, this message translates to:
  /// **'Steady across both halves'**
  String get runDetailPacingHeld;

  /// Pacing card note when grade-adjusted effort rose over the second half
  ///
  /// In en, this message translates to:
  /// **'Adjusted for the terrain, you sped up over the second half.'**
  String get runDetailPacingGapNegative;

  /// Pacing card note when grade-adjusted effort was even across both halves
  ///
  /// In en, this message translates to:
  /// **'Adjusted for the terrain, your effort was even across both halves.'**
  String get runDetailPacingGapEven;

  /// Pacing card note when grade-adjusted effort fell over the second half
  ///
  /// In en, this message translates to:
  /// **'Adjusted for the terrain, you slowed over the second half.'**
  String get runDetailPacingGapPositive;

  /// Header of the grade-adjusted pace column in the splits list
  ///
  /// In en, this message translates to:
  /// **'Grade-adj.'**
  String get runDetailGapColumn;

  /// Explanation shown under the splits list when the grade-adjusted column is visible
  ///
  /// In en, this message translates to:
  /// **'Grade-adjusted pace is the flat-ground pace that would have cost the same effort as the hills you actually ran.'**
  String get runDetailGapColumnHint;

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

  /// Overflow-menu action + confirm button that flips a shared run back to private
  ///
  /// In en, this message translates to:
  /// **'Make private'**
  String get runDetailMakePrivate;

  /// Title of the make-run-private confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Make this run private?'**
  String get runDetailMakePrivateTitle;

  /// Body of the make-run-private confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'The public share link and the live spectator page will stop working. Anyone opening an old link will no longer see this run.'**
  String get runDetailMakePrivateBody;

  /// Banner shown when flipping a run back to private fails
  ///
  /// In en, this message translates to:
  /// **'Could not make run private: {error}'**
  String runDetailMakePrivateFailed(String error);

  /// Banner shown after a run was flipped back to private
  ///
  /// In en, this message translates to:
  /// **'Run is now private'**
  String get runDetailMadePrivate;

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

  /// Banner shown when the cloud-side delete of a run fails: the run stays on the device and the delete is queued for the sync retry
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete from the cloud; the run is kept for now — will retry when back online.'**
  String get runDetailDeleteQueued;

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

  /// Heading on the public run view when the run is still being broadcast live
  ///
  /// In en, this message translates to:
  /// **'Live right now'**
  String get publicRunLiveTitle;

  /// Sub-line explaining why the public run view shows no distance or time yet
  ///
  /// In en, this message translates to:
  /// **'This run is still in progress. Follow it on the live tracker.'**
  String get publicRunLiveSub;

  /// Button that opens the live spectator screen for an in-progress run
  ///
  /// In en, this message translates to:
  /// **'Watch live'**
  String get publicRunWatchLive;

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

  /// Banner after importing a file that held several tracks
  ///
  /// In en, this message translates to:
  /// **'Imported {count} routes'**
  String routesImportedMany(int count);

  /// Banner shown when importing a route file fails for any other reason
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String routesImportFailed(String error);

  /// Banner shown when a GPX/KML file opened from another app (WhatsApp Open with / share) couldn't be imported as a route
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import that file — it isn\'t a valid route.'**
  String get routesImportSharedFailed;

  /// Banner shown after a route built in the in-app builder is saved
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\"'**
  String routesSaved(String name);

  /// Caption under the History filters telling the reader a long press opens multi-select
  ///
  /// In en, this message translates to:
  /// **'Long-press a run to select several'**
  String get historySelectionHint;

  /// Caption under the Routes filters telling the reader a long press opens multi-select
  ///
  /// In en, this message translates to:
  /// **'Long-press a route to select several'**
  String get routesSelectionHint;

  /// Empty-state title shown when the route library is empty
  ///
  /// In en, this message translates to:
  /// **'No routes yet'**
  String get routesEmptyTitle;

  /// Empty-state body shown when the route library is empty
  ///
  /// In en, this message translates to:
  /// **'Tap Build to draw a route on the map, or Import a GPX, KML, KMZ, GeoJSON, or TCX file.'**
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

  /// One-time banner when this build can't snap to roads (OSRM not configured), so Trail/Road behave like Straight
  ///
  /// In en, this message translates to:
  /// **'Road snapping is unavailable — pins land where you tap, connected by straight lines.'**
  String get routeBuilderSnapUnavailable;

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

  /// Share-menu option to share a link to the public route page (opens the OS share sheet)
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get routeDetailShareLink;

  /// Share-menu option that pushes the route to the paired custom watch as a follow-along course
  ///
  /// In en, this message translates to:
  /// **'Send to watch'**
  String get routeDetailSendToWatch;

  /// Banner after the route was pushed to the watch unchanged
  ///
  /// In en, this message translates to:
  /// **'Course sent to the watch ({points} points)'**
  String routeDetailWatchCourseSent(int points);

  /// Banner after a route too long for the watch was simplified before being pushed
  ///
  /// In en, this message translates to:
  /// **'Course sent to the watch — thinned from {source} points to {points} to fit'**
  String routeDetailWatchCourseSimplified(int source, int points);

  /// Banner when a route cannot be sent to the watch because it has fewer than two positions
  ///
  /// In en, this message translates to:
  /// **'This route has too few points to follow on the watch'**
  String get routeDetailWatchCourseTooShort;

  /// No description provided for @routeDetailWatchPushRejected.
  ///
  /// In en, this message translates to:
  /// **'The watch refused the push and kept what it already had. Try again.'**
  String get routeDetailWatchPushRejected;

  /// Banner when the BLE course push to the watch fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the course to the watch: {error}'**
  String routeDetailWatchCourseFailed(String error);

  /// Share-menu option that pushes the route to the paired Apple Watch so it can be followed during a wrist-recorded run
  ///
  /// In en, this message translates to:
  /// **'Send to Apple Watch'**
  String get routeDetailSendToAppleWatch;

  /// Banner after the route was pushed to the Apple Watch unchanged
  ///
  /// In en, this message translates to:
  /// **'Route sent to Apple Watch ({points} points)'**
  String routeDetailAppleWatchRouteSent(int points);

  /// Banner after a route too dense for one Apple Watch push was thinned before being sent
  ///
  /// In en, this message translates to:
  /// **'Route sent to Apple Watch — thinned from {source} points to {points} to fit'**
  String routeDetailAppleWatchRouteSimplified(int source, int points);

  /// Banner when a route cannot be sent to the Apple Watch because it has fewer than two positions
  ///
  /// In en, this message translates to:
  /// **'This route has too few points to follow on Apple Watch'**
  String get routeDetailAppleWatchRouteTooShort;

  /// Banner when the Watch Connectivity route push to the Apple Watch fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the route to Apple Watch: {error}'**
  String routeDetailAppleWatchRouteFailed(String error);

  /// Banner when both the course and its full race schedule reached the watch
  ///
  /// In en, this message translates to:
  /// **'Course ({points} points) and race schedule ({checkpoints} checkpoints) sent to the watch'**
  String routeDetailWatchCourseAndScheduleSent(int points, int checkpoints);

  /// Banner when the race schedule had to be reduced to the watch's checkpoint cap
  ///
  /// In en, this message translates to:
  /// **'Course ({points} points) sent. Race schedule thinned from {source} to {checkpoints} checkpoints to fit the watch'**
  String routeDetailWatchScheduleThinned(
    int points,
    int source,
    int checkpoints,
  );

  /// Banner when clock-only cutoffs could not be resolved without a race start time
  ///
  /// In en, this message translates to:
  /// **'Race schedule sent ({checkpoints} checkpoints), but {unresolved} clock cut-offs need a race start time — set one on the crew sheet so the watch gets them'**
  String routeDetailWatchScheduleClockCutoffs(int checkpoints, int unresolved);

  /// Banner when the route has more cutoffs than the watch frame carries, so the schedule was refused
  ///
  /// In en, this message translates to:
  /// **'Course ({points} points) sent, but the race schedule has {cutoffs} cut-offs and the watch holds {max} — remove some to send it'**
  String routeDetailWatchScheduleTooManyCutoffs(
    int points,
    int cutoffs,
    int max,
  );

  /// Banner shown when tapping Share link auto-publishes a private route so its link resolves
  ///
  /// In en, this message translates to:
  /// **'Made public so anyone with the link can view it'**
  String get routeDetailMadePublicForLink;

  /// Title of the confirm dialog shown before Share flips a private route public
  ///
  /// In en, this message translates to:
  /// **'Make this route public?'**
  String get routeDetailShareConfirmTitle;

  /// Body of the confirm dialog shown before Share flips a private route public
  ///
  /// In en, this message translates to:
  /// **'Sharing a link makes this route public — anyone with the link can open it, and it can appear in Explore. You can switch it back to private anytime.'**
  String get routeDetailShareConfirmBody;

  /// Confirm button label on the make-route-public share dialog
  ///
  /// In en, this message translates to:
  /// **'Make public & share'**
  String get routeDetailShareConfirmCta;

  /// Banner shown when making the route public for a share link fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share the link: {error}'**
  String routeDetailShareLinkFailed(String error);

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

  /// Tooltip on the report button for an individual route review
  ///
  /// In en, this message translates to:
  /// **'Report review'**
  String get routeDetailReportReview;

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

  /// Shown when an AI description is refused because the AI disclosure has not been accepted
  ///
  /// In en, this message translates to:
  /// **'AI descriptions need your consent to the updated AI disclosure.'**
  String get routeDetailDescribeConsentRequired;

  /// Button that opens the AI disclosure from the route-description fallback notice
  ///
  /// In en, this message translates to:
  /// **'Review disclosure'**
  String get routeDetailReviewDisclosure;

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

  /// Tooltip on the delete button for the viewer's own route review
  ///
  /// In en, this message translates to:
  /// **'Delete your review'**
  String get routeDetailDeleteReview;

  /// Banner shown when deleting your own route review fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the review: {error}'**
  String routeDetailReviewDeleteFailed(String error);

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

  /// Heatmap empty-state title for a signed-out viewer with no local tracks
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your synced heatmap'**
  String get runHeatmapSignedOutTitle;

  /// Heatmap empty-state body for a signed-out viewer — must not claim the user has never run
  ///
  /// In en, this message translates to:
  /// **'Runs recorded on this device show up here. Sign in to include your synced runs too.'**
  String get runHeatmapSignedOutBody;

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

  /// Lock-screen notification title while the recording is manually paused
  ///
  /// In en, this message translates to:
  /// **'{activity} • paused'**
  String runNotificationPausedTitle(String activity);

  /// The one activity_type vocabulary — road/track running
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get activityTypeRun;

  /// The one activity_type vocabulary — walking
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get activityTypeWalk;

  /// The one activity_type vocabulary — off-road running (stored as `hike`)
  ///
  /// In en, this message translates to:
  /// **'Trail run'**
  String get activityTypeHike;

  /// The one activity_type vocabulary — cycling
  ///
  /// In en, this message translates to:
  /// **'Cycle'**
  String get activityTypeCycle;

  /// The one activity_type vocabulary — running while pushing a stroller
  ///
  /// In en, this message translates to:
  /// **'Stroller'**
  String get activityTypeStroller;

  /// Feed activity filter chip — all activity types
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get feedActivityAll;

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

  /// Error state shown when one profile tab (Runs / Achievements / Followers / Following / Notifications) fails to load, scoped to that tab
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this section.'**
  String get profileSectionError;

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

  /// Fallback noun for a run reference in notification text when the distance is unknown. Carries NO possessive: every consuming template already supplies one ("your {dist}")
  ///
  /// In en, this message translates to:
  /// **'run'**
  String get profileNotifYourRun;

  /// Actor name for a collapsed notification group (Alice and 4 others)
  ///
  /// In en, this message translates to:
  /// **'{name} and {count} others'**
  String profileNotifNameAndOthers(String name, int count);

  /// Expand toggle label for a collapsed notification group
  ///
  /// In en, this message translates to:
  /// **'and {count} others'**
  String profileNotifAndOthers(int count);

  /// Collapse toggle label for an expanded notification group
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get profileNotifShowLess;

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

  /// Notification text for a coach assigning the athlete a training plan
  ///
  /// In en, this message translates to:
  /// **'{name} assigned you a training plan'**
  String profileNotifPlanAssigned(String name);

  /// Notification text for a cancelled event occurrence, when the event title is known
  ///
  /// In en, this message translates to:
  /// **'An occurrence of \"{title}\" was cancelled'**
  String profileNotifEventCancelTitled(String title);

  /// Notification text for a cancelled event occurrence, when the title is unavailable
  ///
  /// In en, this message translates to:
  /// **'An event occurrence you RSVP\'d to was cancelled'**
  String get profileNotifEventCancel;

  /// Notification text for an upcoming event reminder, when the event title is known
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is coming up'**
  String profileNotifEventReminderTitled(String title);

  /// Notification text for an upcoming event reminder, when the title is unavailable
  ///
  /// In en, this message translates to:
  /// **'An event you\'re going to is coming up'**
  String get profileNotifEventReminder;

  /// Notification text for earning a new achievement
  ///
  /// In en, this message translates to:
  /// **'You earned a new achievement'**
  String get profileNotifAchievement;

  /// Notification text for completing a challenge
  ///
  /// In en, this message translates to:
  /// **'You completed a challenge'**
  String get profileNotifChallengeComplete;

  /// Notification text for one of the user's own posts being hidden after reports
  ///
  /// In en, this message translates to:
  /// **'One of your posts was hidden after being reported'**
  String get profileNotifContentHidden;

  /// Notification text for the user's own Art 20 data export finishing its build
  ///
  /// In en, this message translates to:
  /// **'Your data export is ready to download'**
  String get profileNotifDataExportReady;

  /// Notification text for a refund the bank reversed, on an event order or a donation
  ///
  /// In en, this message translates to:
  /// **'A refund we started couldn\'t be completed. The money is still with us and we\'ll arrange another way to return it.'**
  String get profileNotifRefundFailed;

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
  /// **'Search classes, clubs…'**
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

  /// Expands a clamped club description into a sheet showing the whole text.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get clubDetailReadMore;

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

  /// Body shown when the club fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this club. It may have been removed, or your session might need to be refreshed. Try pulling to retry, or sign out and back in from Settings.'**
  String get clubDetailLoadFailedBody;

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

  /// Banner on a cancelled occurrence of a recurring club event
  ///
  /// In en, this message translates to:
  /// **'This occurrence was cancelled.'**
  String get eventOccurrenceCancelled;

  /// Shown when the server demoted a full event RSVP to the waitlist
  ///
  /// In en, this message translates to:
  /// **'Waitlisted'**
  String get eventRsvpWaitlisted;

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

  /// Label for the live spectator race-clock stat tile — wall-clock time since the runner started, distinct from the runner's own recording timer
  ///
  /// In en, this message translates to:
  /// **'Race time'**
  String get liveSpectatorStatRaceTime;

  /// Label for the live spectator stat tile showing the runner's own recording timer as of the last fix
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get liveSpectatorStatTimer;

  /// Label for the runner's-timer stat tile once the last fix is stale, so the frozen figure cannot pass as current
  ///
  /// In en, this message translates to:
  /// **'Timer, last fix'**
  String get liveSpectatorStatTimerStale;

  /// Label for the recent-pace spectator stat tile (distinct from cumulative average pace)
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get liveSpectatorRecentPace;

  /// Course-progress label — how far along a linked route the runner is
  ///
  /// In en, this message translates to:
  /// **'{p}% of route'**
  String liveSpectatorCourseProgress(int p);

  /// Spectator chip: the runner is still pinging but has not left this spot for n minutes
  ///
  /// In en, this message translates to:
  /// **'Not moving — {n} min in the same spot'**
  String liveSpectatorMotionStopped(int n);

  /// Same chip when the stop reaches the start of the observed window, so n is a floor
  ///
  /// In en, this message translates to:
  /// **'Not moving — at least {n} min in the same spot'**
  String liveSpectatorMotionStoppedAtLeast(int n);

  /// Heading of the spectator conclusion card shown when the broadcast has concluded
  ///
  /// In en, this message translates to:
  /// **'Run complete'**
  String get liveSpectatorConcludedTitle;

  /// Body of the spectator conclusion card
  ///
  /// In en, this message translates to:
  /// **'See the full route, splits, and stats.'**
  String get liveSpectatorConcludedBody;

  /// CTA on the spectator conclusion card that opens the full public run
  ///
  /// In en, this message translates to:
  /// **'View the full run'**
  String get liveSpectatorViewFullRun;

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

  /// Spectator next-cutoff card — shown instead of a verdict while a fresh fix has no pace yet (still connecting)
  ///
  /// In en, this message translates to:
  /// **'Waiting for a fresh signal to project arrival'**
  String get liveCutoffWaitingSignal;

  /// Spectator next-cutoff card — shown instead of a verdict when the last fix is stale (runner went dark)
  ///
  /// In en, this message translates to:
  /// **'Signal lost — can\'t project arrival'**
  String get liveCutoffSignalLost;

  /// Spectator next-cutoff card — the checkpoint's limit is already in the past; no pace can make it
  ///
  /// In en, this message translates to:
  /// **'Cut-off time has passed'**
  String get liveCutoffExpired;

  /// Spectator next-cutoff card — flat pace still needed over the remaining distance to make the cutoff
  ///
  /// In en, this message translates to:
  /// **'Needs {pace} from here'**
  String liveCutoffRequiredPace(String pace);

  /// Spectator next-cutoff card — required pace when the position is stale, measured from the last known fix rather than where the runner is now
  ///
  /// In en, this message translates to:
  /// **'Needs {pace} from the last fix'**
  String liveCutoffRequiredPaceStale(String pace);

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

  /// Inline hint below the plan-name field explaining why the Create button is disabled when the name is empty
  ///
  /// In en, this message translates to:
  /// **'Add a plan name to enable Create.'**
  String get planNewNameRequiredHint;

  /// Default plan name prefilled when the plan wizard opens preselected to a goal (from the onboarding nudge)
  ///
  /// In en, this message translates to:
  /// **'{goal} plan'**
  String planNewDefaultName(String goal);

  /// Default plan name prefilled when the plan wizard opens on the beginner walk-run preset
  ///
  /// In en, this message translates to:
  /// **'Walk-run to {goal}'**
  String planNewDefaultNameBeginner(String goal);

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

  /// Note shown when the plan wizard was opened from a race listing and could size the plan around it
  ///
  /// In en, this message translates to:
  /// **'Sized for your race: a {weeks}-week plan whose final week is race week. Adjust anything below before creating it.'**
  String planNewRaceAnchored(int weeks);

  /// Note shown when the race the wizard was opened from has already been run
  ///
  /// In en, this message translates to:
  /// **'That race has already been run, so the dates below are the usual defaults.'**
  String get planNewRacePast;

  /// Note shown when the race the wizard was opened from is too close to build a plan for
  ///
  /// In en, this message translates to:
  /// **'That race is too close to build a full plan for, so the dates below are the usual defaults.'**
  String get planNewRaceTooSoon;

  /// Note shown when the race date the wizard was opened with could not be parsed
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t read that race\'s date, so the dates below are the usual defaults.'**
  String get planNewRaceUnreadable;

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

  /// Plan-wizard ramp-note section label
  ///
  /// In en, this message translates to:
  /// **'Plan vs. your recent training'**
  String get planNewRampLabel;

  /// Ramp note when the plan's peak week sits below the runner's recent weekly average
  ///
  /// In en, this message translates to:
  /// **'This plan peaks at {peak} a week, below the {recent} a week you\'ve averaged over the last four weeks. A longer goal race or more training days would make better use of that base.'**
  String planNewRampUnder(String peak, String recent);

  /// Ramp note when the plan's opening week is an elevated step above the runner's recent weekly average
  ///
  /// In en, this message translates to:
  /// **'Week 1 asks for {opening} against the {recent} a week you\'ve averaged over the last four weeks — a real step up. Ease into it, or drop a training day.'**
  String planNewRampElevated(String opening, String recent);

  /// Ramp note when the plan's opening week is far above the runner's recent weekly average
  ///
  /// In en, this message translates to:
  /// **'Week 1 asks for {opening}, well above the {recent} a week you\'ve averaged over the last four weeks. Fewer training days, a shorter goal race, or a few weeks of base building first would make that first step safer.'**
  String planNewRampHigh(String opening, String recent);

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
  /// **'Couldn\'t adopt that template.'**
  String get planNewTemplateCloneFailed;

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
  /// **'Couldn\'t create that plan.'**
  String get planNewStarterCreateFailed;

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
  /// **'AI Coach'**
  String get coachTitle;

  /// Default active-thread title when empty
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get coachNewConversation;

  /// Consent gate headline
  ///
  /// In en, this message translates to:
  /// **'Before you use Threkir\'s AI features'**
  String get coachConsentHeadline;

  /// Consent gate intro paragraph
  ///
  /// In en, this message translates to:
  /// **'Threkir\'s AI features — the Coach and the AI route assistant — forward a slice of your data to Anthropic, our AI model provider in the United States. Depending on which feature you use, that slice includes:'**
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

  /// Consent gate bullet: AI route assistant
  ///
  /// In en, this message translates to:
  /// **'For the AI route assistant: the route\'s name and stats, the request you type, and a coarse place label — never your precise coordinates.'**
  String get coachConsentBulletRoutes;

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
  /// **'I consent — enable AI features'**
  String get coachConsentAccept;

  /// Consent gate accept button while saving
  ///
  /// In en, this message translates to:
  /// **'Recording consent…'**
  String get coachConsentSaving;

  /// Banner shown when recording AI-disclosure consent fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record consent: {error}'**
  String aiDisclosureRecordFailed(Object error);

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
  /// **'Tap to view'**
  String get coachArchiveTapToView;

  /// Tooltip for the overflow menu on an archived coach conversation row
  ///
  /// In en, this message translates to:
  /// **'Conversation actions'**
  String get coachArchiveActions;

  /// Overflow action + confirm label for deleting an archived coach conversation
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get coachArchiveDelete;

  /// Title of the delete-archived-conversation confirm dialog
  ///
  /// In en, this message translates to:
  /// **'Delete this conversation?'**
  String get coachArchiveDeleteTitle;

  /// Body of the delete-archived-conversation confirm dialog
  ///
  /// In en, this message translates to:
  /// **'This archived conversation is deleted for good.'**
  String get coachArchiveDeleteBody;

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

  /// Suggestion chip (brand-new runner, zero runs)
  ///
  /// In en, this message translates to:
  /// **'I\'ve never run before — where do I start?'**
  String get coachSuggestNewFirstRun;

  /// Suggestion chip (brand-new runner, zero runs)
  ///
  /// In en, this message translates to:
  /// **'How should my first run feel?'**
  String get coachSuggestNewFirstFeel;

  /// Suggestion chip (brand-new runner, zero runs)
  ///
  /// In en, this message translates to:
  /// **'How often should I run as a beginner?'**
  String get coachSuggestNewHowOften;

  /// Suggestion chip (brand-new runner, zero runs)
  ///
  /// In en, this message translates to:
  /// **'Is it OK to walk during my runs?'**
  String get coachSuggestNewWalkRun;

  /// Accessible label for the inline message-edit text field
  ///
  /// In en, this message translates to:
  /// **'Edit your message'**
  String get coachEditMessageLabel;

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
  /// **'Could not start a new conversation.'**
  String get coachNewConversationFailed;

  /// Error opening an archive
  ///
  /// In en, this message translates to:
  /// **'Could not open archive.'**
  String get coachOpenArchiveFailed;

  /// Banner shown when deleting a coach archive fails; the swiped row snaps back
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete archive: {error}'**
  String coachArchiveDeleteFailed(String error);

  /// Banner shown when writing a thumbs up/down on a coach message fails; the thumb reverts
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your reaction. Try again.'**
  String get coachReactionFailed;

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

  /// Label for the current-password field in the change-password dialog
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get settingsAccountCurrentPassword;

  /// Explains why the current password is required and the reset-link alternative for OAuth-only accounts
  ///
  /// In en, this message translates to:
  /// **'For your security, enter your current password to change it. Signed up with Google or Apple? Email yourself a reset link to set one.'**
  String get settingsAccountPasswordStepUpHint;

  /// Validation error when the current-password field is empty
  ///
  /// In en, this message translates to:
  /// **'Enter your current password to change it.'**
  String get settingsAccountCurrentPasswordRequired;

  /// Error when the current password fails to verify
  ///
  /// In en, this message translates to:
  /// **'That current password is incorrect. If you have never set a password, email yourself a reset link instead.'**
  String get settingsAccountCurrentPasswordIncorrect;

  /// Button that mails a password-reset link, for OAuth-only accounts with no password to prove
  ///
  /// In en, this message translates to:
  /// **'Email me a reset link'**
  String get settingsAccountSendResetLink;

  /// In-flight label on the reset-link button
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get settingsAccountSendingResetLink;

  /// Banner shown after a password-reset link is mailed
  ///
  /// In en, this message translates to:
  /// **'Reset link sent. Check your email to set a new password.'**
  String get settingsAccountResetLinkSent;

  /// Tile title and dialog title for changing the account email
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get settingsAccountChangeEmail;

  /// Label for the new-email field in the change-email dialog
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get settingsAccountNewEmail;

  /// Validation error when the new email is malformed or unchanged
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address that\'s different from your current one.'**
  String get settingsAccountEmailChangeInvalid;

  /// Persistent note + banner after an email change is requested; names both inboxes
  ///
  /// In en, this message translates to:
  /// **'Confirmation pending. Check both your old inbox ({old}) and your new inbox ({newEmail}) and follow the link in each to finish the change. Your email won\'t change until you confirm from both.'**
  String settingsAccountEmailChangePending(Object old, Object newEmail);

  /// Banner shown when starting the email change fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the email change: {error}'**
  String settingsAccountEmailChangeFailed(Object error);

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

  /// Settings > Account tile title to withdraw AI-features consent (GDPR Art 7(3))
  ///
  /// In en, this message translates to:
  /// **'Withdraw AI features consent'**
  String get settingsAccountCoachConsentWithdraw;

  /// Subtitle under the withdraw-AI-consent tile
  ///
  /// In en, this message translates to:
  /// **'Stop Threkir\'s AI features from using your data. You can consent again any time.'**
  String get settingsAccountCoachConsentActive;

  /// Banner shown after AI-features consent is withdrawn
  ///
  /// In en, this message translates to:
  /// **'AI features consent withdrawn.'**
  String get settingsAccountCoachConsentWithdrawn;

  /// Banner shown when withdrawing AI-features consent fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t withdraw consent: {error}'**
  String settingsAccountCoachConsentWithdrawFailed(Object error);

  /// Settings > Account tile title to accept a widened AI disclosure
  ///
  /// In en, this message translates to:
  /// **'Accept the updated AI disclosure'**
  String get settingsAccountAiConsentUpdateTitle;

  /// Subtitle under the accept-updated-AI-disclosure tile
  ///
  /// In en, this message translates to:
  /// **'The disclosure now covers more features. Review and accept it to use the AI route assistant.'**
  String get settingsAccountAiConsentUpdateSubtitle;

  /// Settings > Account tile title to read and accept the AI disclosure for the first time
  ///
  /// In en, this message translates to:
  /// **'Review the AI disclosure'**
  String get settingsAccountAiConsentGrantTitle;

  /// Subtitle under the review-AI-disclosure tile
  ///
  /// In en, this message translates to:
  /// **'Threkir\'s AI features ask for your consent before using your data. Read the disclosure and accept it here.'**
  String get settingsAccountAiConsentGrantSubtitle;

  /// Banner shown after the widened AI disclosure is accepted
  ///
  /// In en, this message translates to:
  /// **'AI disclosure accepted.'**
  String get settingsAccountAiConsentAccepted;

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

  /// Banner shown after a server-built export that came back short of the account run history
  ///
  /// In en, this message translates to:
  /// **'Export is partial — {count} of {total} runs.'**
  String settingsAccountBackupPartial(int count, int total);

  /// Persistent notice under the full-backup tile naming how short the last export was
  ///
  /// In en, this message translates to:
  /// **'Your last export is partial: it holds {count} of the {total} runs on your account. Nothing was deleted — export again to retry. The full account archive names every short section in its manifest.json.'**
  String settingsAccountBackupPartialNotice(int count, int total);

  /// Banner shown after a locally-built backup whose GPS track downloads came up short
  ///
  /// In en, this message translates to:
  /// **'Backup is missing {missing} of {total} GPS files.'**
  String settingsAccountBackupTracksPartial(int missing, int total);

  /// Persistent notice under the full-backup tile naming how many GPS track files the last local backup could not download
  ///
  /// In en, this message translates to:
  /// **'Your last backup could not download {missing} of the {total} GPS track files. Every run is in the archive; export again to retry the traces. Its manifest.json says complete: false.'**
  String settingsAccountBackupTracksPartialNotice(int missing, int total);

  /// Persistent notice under the restore tile shown when the restored archive declared itself incomplete
  ///
  /// In en, this message translates to:
  /// **'That archive said it was incomplete. {runs} runs were restored and nothing was overwritten - restore from a complete backup to fill the gaps.'**
  String settingsAccountRestoreIncompleteArchive(int runs);

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

  /// Tile title for guided runs
  ///
  /// In en, this message translates to:
  /// **'Guided runs'**
  String get guidedRunsTitle;

  /// Subtitle of the Guided runs tile
  ///
  /// In en, this message translates to:
  /// **'Coach-voice scripted workouts with TTS cues'**
  String get guidedRunsSubtitle;

  /// AppBar title for the Settings > Privacy zones screen, and the title of the Settings tile that opens it
  ///
  /// In en, this message translates to:
  /// **'Privacy zones'**
  String get privacyZonesTitle;

  /// Subtitle of the Privacy zones tile
  ///
  /// In en, this message translates to:
  /// **'Clip start/end of public tracks near home'**
  String get privacyZonesSubtitle;

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

  /// Label for the account display-name tile and its edit dialog
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get settingsAccountDisplayName;

  /// Helper text under the display-name field explaining the fallback
  ///
  /// In en, this message translates to:
  /// **'The name other runners see. Leave blank to use \"Runner\".'**
  String get settingsAccountDisplayNameHint;

  /// Subtitle on the display-name tile when no display name is set
  ///
  /// In en, this message translates to:
  /// **'Not set — you appear as \"Runner\"'**
  String get settingsAccountDisplayNameUnset;

  /// Banner confirming the display name saved
  ///
  /// In en, this message translates to:
  /// **'Display name updated'**
  String get settingsAccountDisplayNameUpdated;

  /// Banner shown when the display-name save fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your display name. Please try again.'**
  String get settingsAccountDisplayNameUpdateFailed;

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

  /// Tile title for the queued server-built GDPR Art 20 export
  ///
  /// In en, this message translates to:
  /// **'Account export'**
  String get settingsAccountAccountExport;

  /// Subtitle for the account-export tile
  ///
  /// In en, this message translates to:
  /// **'Everything on your account — runs, routes, messages, orders, integrations, safety contacts. Built on our server; you can close the app while it runs.'**
  String get settingsAccountAccountExportSubtitle;

  /// Banner shown the moment an export job is queued
  ///
  /// In en, this message translates to:
  /// **'Building your export. You can close the app — come back here to download it.'**
  String get settingsAccountExportQueued;

  /// Persistent notice while the queued export job is running
  ///
  /// In en, this message translates to:
  /// **'Your account export is being built. You can close the app; it keeps building without you.'**
  String get settingsAccountExportBuildingNotice;

  /// Persistent notice when the queued export job has finished
  ///
  /// In en, this message translates to:
  /// **'Your account export is ready.'**
  String get settingsAccountExportReadyNotice;

  /// Button that downloads a ready account export and opens the share sheet
  ///
  /// In en, this message translates to:
  /// **'Download and share'**
  String get settingsAccountExportDownload;

  /// Persistent notice naming why the last queued export failed
  ///
  /// In en, this message translates to:
  /// **'Your last account export failed ({error}). Nothing was deleted — ask for another one.'**
  String settingsAccountExportFailedNotice(String error);

  /// Persistent notice when the export job went quiet for longer than the worker's retry budget
  ///
  /// In en, this message translates to:
  /// **'Your last account export stopped responding. Nothing was deleted — ask for another one.'**
  String get settingsAccountExportStalledNotice;

  /// Persistent notice when the export artifact has been swept
  ///
  /// In en, this message translates to:
  /// **'Your last account export has expired. Exports are deleted after 7 days — ask for another one.'**
  String get settingsAccountExportExpiredNotice;

  /// Persistent notice after repeated failed status reads
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the export service to check on your export. It may still be building.'**
  String get settingsAccountExportStatusUnavailable;

  /// Banner when no export service is configured
  ///
  /// In en, this message translates to:
  /// **'The account export service isn\'t set up in this build. Full backup below is built on this device and doesn\'t include your account records.'**
  String get settingsAccountExportUnavailable;

  /// Persistent notice under the account-export tile when the device holds undrained runs
  ///
  /// In en, this message translates to:
  /// **'{count} runs haven\'t synced yet. The account export is built on the server, so it won\'t include them — use Full backup to keep those.'**
  String settingsAccountExportUnsyncedWarning(int count);

  /// Persistent notice after a locally-built archive naming which archive the runner got
  ///
  /// In en, this message translates to:
  /// **'Your last full backup was built on this device. It holds your runs, routes, profile, preferences, gym and food logs — but not your account records. Use Account export for the complete copy.'**
  String get settingsAccountBackupOnDeviceNotice;

  /// Banner when the export quota refused the request
  ///
  /// In en, this message translates to:
  /// **'Export limit reached — try again in {seconds} seconds.'**
  String settingsAccountExportRateLimited(int seconds);

  /// Banner when the enqueue call failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t request your export: {error}'**
  String settingsAccountExportRequestFailed(String error);

  /// Banner when downloading a ready export failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download your export: {error}'**
  String settingsAccountExportDownloadFailed(String error);

  /// Banner raised when a watched export job finishes while the screen is open
  ///
  /// In en, this message translates to:
  /// **'Your account export is ready — {count} runs.'**
  String settingsAccountExportReadyBanner(int count);

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

  /// Banner shown when a Strava sync stopped before the end of the lookback window
  ///
  /// In en, this message translates to:
  /// **'Sync stopped early. {imported} new, {skipped} already present — some activities were not fetched. Sync again to finish.'**
  String integrationsSyncPartial(int imported, int skipped);

  /// Banner shown when Strava throttled us mid-sync
  ///
  /// In en, this message translates to:
  /// **'Strava is limiting requests, so the sync stopped early. {imported} new, {skipped} already present. Try again in about 15 minutes.'**
  String integrationsSyncPartialRateLimited(int imported, int skipped);

  /// Banner summarising a Strava sync in which some activities failed to ingest
  ///
  /// In en, this message translates to:
  /// **'Synced. {imported} new, {skipped} already present, {failed} failed.'**
  String integrationsSyncResultWithFailed(
    int imported,
    int skipped,
    int failed,
  );

  /// Banner shown when the first import after connecting Strava stopped early
  ///
  /// In en, this message translates to:
  /// **'Strava connected, but the first import stopped early. {imported} imported, {skipped} already present — sync again to finish.'**
  String integrationsStravaConnectedPartial(int imported, int skipped);

  /// Banner shown when Strava throttled the first import after connecting
  ///
  /// In en, this message translates to:
  /// **'Strava connected, but Strava is limiting requests so the first import stopped early. {imported} imported, {skipped} already present. Sync again in about 15 minutes.'**
  String integrationsStravaConnectedPartialRateLimited(
    int imported,
    int skipped,
  );

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

  /// Banner when an importer read only part of a history and knows the total
  ///
  /// In en, this message translates to:
  /// **'Only part of your history could be imported: {n} of {total}.'**
  String integrationsImportPartialOf(int n, int total);

  /// Banner when an importer read only part of a history and does not know the total
  ///
  /// In en, this message translates to:
  /// **'Not all results could be read. Imported: {n}.'**
  String integrationsImportPartial(int n);

  /// Banner when the upstream results list was truncated before the runner was found
  ///
  /// In en, this message translates to:
  /// **'The results list was too long to read to the end, so your result could not be confirmed. Enter it manually instead.'**
  String get integrationsImportTruncated;

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

  /// Popup-menu item opening the wider-lookback picker for Strava
  ///
  /// In en, this message translates to:
  /// **'Sync older history…'**
  String get integrationsStravaSyncHistory;

  /// Title of the dialog choosing how far back a Strava sync reaches
  ///
  /// In en, this message translates to:
  /// **'How far back to sync'**
  String get integrationsStravaLookbackTitle;

  /// Strava lookback option: the default 90-day window
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get integrationsStravaLookback90;

  /// Strava lookback option: six months
  ///
  /// In en, this message translates to:
  /// **'Last 6 months'**
  String get integrationsStravaLookback180;

  /// Strava lookback option: one year, the maximum the function accepts
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get integrationsStravaLookback365;

  /// Strava tile note after a truncated sync that recorded a resume point
  ///
  /// In en, this message translates to:
  /// **'The last sync stopped before the end of the window. Syncing again picks up where it stopped.'**
  String get integrationsSyncPartialNoteResumable;

  /// Strava tile note after a truncated sync that recorded no resume point
  ///
  /// In en, this message translates to:
  /// **'The last sync stopped before the end of the window and recorded no restart point. Sync again to retry it.'**
  String get integrationsSyncPartialNote;

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

  /// Pro tile title when the deploy has no live Pro perk to sell
  ///
  /// In en, this message translates to:
  /// **'Pro — coming soon'**
  String get proComingSoonTitle;

  /// Pro tile subtitle shown instead of a purchase CTA when no Pro perk is live
  ///
  /// In en, this message translates to:
  /// **'Pro unlocks the AI Coach — coming soon. You can still support the app below.'**
  String get proComingSoon;

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

  /// AppBar title for the Settings > About & updates screen
  ///
  /// In en, this message translates to:
  /// **'About & updates'**
  String get aboutTitle;

  /// Tile title showing the app version
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

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

  /// Tile that starts a user-initiated in-app update check
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get aboutCheckForUpdates;

  /// Shown on the About screen while an in-app update check is in flight
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get aboutCheckingUpdate;

  /// Title of the update-available row on the About screen (Play In-App Updates)
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get aboutUpdateAvailable;

  /// Subtitle of the update-available row on the About screen
  ///
  /// In en, this message translates to:
  /// **'A newer version is ready to install.'**
  String get aboutUpdateAvailableSubtitle;

  /// Button that starts the in-app update to the latest version
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get aboutUpdate;

  /// Shown on the About screen when no newer version is available
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version'**
  String get aboutUpToDate;

  /// Subtitle shown when the build has no in-app update channel (dev / sideload / iOS)
  ///
  /// In en, this message translates to:
  /// **'This build updates through the store you installed it from.'**
  String get aboutUpdateUnavailable;

  /// Banner shown when the in-app update flow fails to start
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the update. Try again from the Play Store.'**
  String get aboutUpdateFailed;

  /// Label for the Privacy Policy link (settings About screen + sign-up consent)
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get legalPrivacy;

  /// Label for the Terms of Service link (settings About screen + sign-up consent)
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get legalTerms;

  /// Label for the Cookie Notice link on the settings About screen
  ///
  /// In en, this message translates to:
  /// **'Cookie Notice'**
  String get legalCookieNotice;

  /// Label for the consumer health data privacy notice link on the settings About screen
  ///
  /// In en, this message translates to:
  /// **'Health data privacy'**
  String get legalHealthDataNotice;

  /// Accessibility label for the credit strip shown over every map
  ///
  /// In en, this message translates to:
  /// **'Map data attribution'**
  String get mapAttributionSemantics;

  /// Credit for the company that renders the basemap tiles. {name} is a company name and is never translated.
  ///
  /// In en, this message translates to:
  /// **'© {name}'**
  String mapAttributionProvider(String name);

  /// ODbL credit for the map data. {name} is the OpenStreetMap project name and is never translated; the word for the people who contribute to it is.
  ///
  /// In en, this message translates to:
  /// **'© {name} contributors'**
  String mapAttributionOsmContributors(String name);

  /// Banner shown when a legal-document link fails to open
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String legalCouldNotOpen(String url);

  /// Section header above the legal-document links on the About screen
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get aboutLegalSection;

  /// AppBar title for the Settings > Devices screen
  ///
  /// In en, this message translates to:
  /// **'Signed-in devices'**
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

  /// Which pair of a rotation comes out next, on the rotation row
  ///
  /// In en, this message translates to:
  /// **'Next up: {name}'**
  String gearRotationNextUp(String name);

  /// Why that pair was picked, beside the next-up read-out
  ///
  /// In en, this message translates to:
  /// **'Least worn in this rotation.'**
  String get gearRotationNextUpWhy;

  /// Button moving the current-pair star onto the next-up pair
  ///
  /// In en, this message translates to:
  /// **'Make current'**
  String get gearRotationMakeCurrent;

  /// Accessibility label for the make-current button
  ///
  /// In en, this message translates to:
  /// **'Make {name} the current pair — new runs will auto-tag with it'**
  String gearRotationMakeCurrentLabel(String name);

  /// Shown when the next-up pair already holds the star
  ///
  /// In en, this message translates to:
  /// **'Already the current pair.'**
  String get gearRotationNextUpIsCurrent;

  /// Warning when every pair in a rotation is at or past its target
  ///
  /// In en, this message translates to:
  /// **'Every pair here is at or past its replacement target.'**
  String get gearRotationAllWorn;

  /// Banner shown when moving the current-pair star fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change the current pair: {error}'**
  String gearRotationMakeCurrentFailed(Object error);

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

  /// Privacy-zones-specific body for the shared discard-changes confirm dialog
  ///
  /// In en, this message translates to:
  /// **'You have unsaved privacy zones. Leave without saving?'**
  String get privacyZonesDiscardBody;

  /// Title of the shared unsaved-changes confirm dialog shown when backing out of a create/edit form
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// Generic body of the shared unsaved-changes confirm dialog
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Leave without saving?'**
  String get discardChangesBody;

  /// Button that dismisses the discard-changes dialog and keeps the form open
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get discardChangesCancel;

  /// Confirm button that leaves the form discarding unsaved edits
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardChangesDiscard;

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

  /// Subtitle shown when the split interval is at its default. The two intervals are passed in already rendered in the runner's own distance unit — the default follows the preference (1 mi / 5 mi in imperial), so the string must not name one.
  ///
  /// In en, this message translates to:
  /// **'Default ({run} for running, {cycle} for cycling)'**
  String prefsSplitIntervalDefaultSubtitle(String run, String cycle);

  /// Tile title for choosing which pace the split cue reads
  ///
  /// In en, this message translates to:
  /// **'Splits announce'**
  String get prefsSplitPaceMode;

  /// Subtitle for the splits-announce tile
  ///
  /// In en, this message translates to:
  /// **'Which pace each split reads out'**
  String get prefsSplitPaceModeSubtitle;

  /// Splits-announce option: read the pace for that split only
  ///
  /// In en, this message translates to:
  /// **'Split pace'**
  String get prefsSplitPaceModeSplit;

  /// Splits-announce option: read the average pace over the whole run so far
  ///
  /// In en, this message translates to:
  /// **'Average pace'**
  String get prefsSplitPaceModeAverage;

  /// Splits-announce option: read both the split pace and the average
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get prefsSplitPaceModeBoth;

  /// Info popup body + example for the splits-announce setting
  ///
  /// In en, this message translates to:
  /// **'At each split, choose what pace you hear: the pace for just that split, your average pace for the whole run so far, or both. Handy for holding an even effort. Example: “1 kilometre. Average pace, 5 minutes 45 seconds per kilometre.”'**
  String get prefsSplitPaceModeInfo;

  /// Tile and dialog title for the target pace (the goal pace the Off-pace alerts cue watches)
  ///
  /// In en, this message translates to:
  /// **'Target pace'**
  String get prefsTargetPace;

  /// Info popup body + example for the target-pace setting
  ///
  /// In en, this message translates to:
  /// **'The pace you’re aiming to hold. On its own it stays silent — turn on the “Off-pace alerts” voice cue to hear “speed up” or “slow down” when you drift more than 30 seconds from it. Example: “Speed up by 8 seconds.”'**
  String get prefsTargetPaceInfo;

  /// Tooltip / accessibility label for the info button next to a cue
  ///
  /// In en, this message translates to:
  /// **'What is this?'**
  String get prefsCueInfoTooltip;

  /// Legacy key, now the Target pace tile/dialog title (was "Live pace alert")
  ///
  /// In en, this message translates to:
  /// **'Target pace'**
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

  /// Target-pace subtitle when no target pace is set
  ///
  /// In en, this message translates to:
  /// **'Not set — set a target, then turn on Off-pace alerts'**
  String get prefsLivePaceAlertOff;

  /// Live-pace-alert subtitle showing the target pace
  ///
  /// In en, this message translates to:
  /// **'{pace} {paceLabel} — Off-pace alerts speak when you drift 30s+'**
  String prefsLivePaceAlertOn(String pace, String paceLabel);

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

  /// Shown when lifting a prior one-click unsubscribe block fails after re-opting into an email stream
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t lift your earlier unsubscribe. Emails may still be blocked — try again.'**
  String get prefsEmailReOptInFailed;

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
  /// **'Speak splits, pace and other cues while you run'**
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

  /// Subtitle of the keep-screen-on toggle, disclosing its battery cost
  ///
  /// In en, this message translates to:
  /// **'Keeps the display lit for the whole run. Uses noticeably more battery on long efforts.'**
  String get prefsKeepScreenOnSubtitle;

  /// Toggle title for dimming the map while recording to save battery
  ///
  /// In en, this message translates to:
  /// **'Dim screen while recording'**
  String get prefsDimScreenWhileRecording;

  /// Subtitle of the dim-screen-while-recording toggle
  ///
  /// In en, this message translates to:
  /// **'Darken the map during a run to save battery. Stats stay readable.'**
  String get prefsDimScreenWhileRecordingSubtitle;

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
  /// **'Your profile'**
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

  /// Dashboard empty-state primary button that opens the recorder to start a run
  ///
  /// In en, this message translates to:
  /// **'Start a run'**
  String get dashboardStartRun;

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

  /// Muted second line under a personal-best time showing its age grade (e.g. 72.4% age grade)
  ///
  /// In en, this message translates to:
  /// **'{percent} age grade'**
  String dashboardPbAgeGrade(String percent);

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

  /// Card header over the calendar activity heatmap on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get dashboardHeatmapTitle;

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
  /// **'Mileage'**
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

  /// Accessibility label / tooltip on the flag button of another user's comment
  ///
  /// In en, this message translates to:
  /// **'Report comment'**
  String get runSocialReportComment;

  /// Accessibility label / tooltip on the flag button of another user's reply
  ///
  /// In en, this message translates to:
  /// **'Report reply'**
  String get runSocialReportReply;

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

  /// Accessible name for a segment-effort rank pill whose standing the rank RPC did not return
  ///
  /// In en, this message translates to:
  /// **'Rank unavailable'**
  String get runSegEffortsRankUnknown;

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

  /// Adherence pill on the run-detail workout review: every planned step done
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get workoutReviewAdherenceCompleted;

  /// Adherence pill on the run-detail workout review: some planned steps missed
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get workoutReviewAdherencePartial;

  /// Adherence pill on the run-detail workout review: workout abandoned
  ///
  /// In en, this message translates to:
  /// **'Abandoned'**
  String get workoutReviewAdherenceAbandoned;

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

  /// No description provided for @segmentsPanelLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load segments'**
  String get segmentsPanelLoadError;

  /// No description provided for @segmentsPanelLeaderboardError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the leaderboard'**
  String get segmentsPanelLeaderboardError;

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

  /// No description provided for @segmentsPanelErrNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a segment name'**
  String get segmentsPanelErrNameRequired;

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

  /// Per-field validation error when the club name is empty on save
  ///
  /// In en, this message translates to:
  /// **'Give the club a name.'**
  String get clubFormErrName;

  /// Validation error when the name has no usable characters
  ///
  /// In en, this message translates to:
  /// **'Name needs at least one letter or digit.'**
  String get clubFormErrSlug;

  /// Per-field validation error when the event title is empty on save
  ///
  /// In en, this message translates to:
  /// **'Give the event a title.'**
  String get eventFormErrTitle;

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

  /// Report sheet title when reporting a run comment
  ///
  /// In en, this message translates to:
  /// **'Report comment'**
  String get reportTitleComment;

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

  /// Report sheet title when reporting a route review
  ///
  /// In en, this message translates to:
  /// **'Report review'**
  String get reportTitleReview;

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

  /// Shown in place of the run-detail gear chips when the assigned-gear read failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load gear.'**
  String get runGearChipsLoadFailed;

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

  /// Spoken split cue reading the cumulative average pace/speed instead of the split's own. tail is the pace/speed utterance.
  ///
  /// In en, this message translates to:
  /// **'{count} {unit}. Average {tail}'**
  String ttsSplitAverage(String count, String unit, String tail);

  /// Spoken split cue reading the split's own pace/speed then the cumulative average.
  ///
  /// In en, this message translates to:
  /// **'{count} {unit}. {tail}. Average {avgTail}'**
  String ttsSplitBoth(String count, String unit, String tail, String avgTail);

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

  /// Training plan phase label: the final week of a beginner walk-run plan, when the runner first covers the distance continuously
  ///
  /// In en, this message translates to:
  /// **'Graduation week'**
  String get planPhaseGraduation;

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
  /// **'Sign in to see where you\'re signed in'**
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
  /// **'Sign-in, profile, import and backup, delete account'**
  String get settingsTabAccountSubtitle;

  /// Settings landing: Preferences tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Units, theme, recording, training, privacy'**
  String get settingsTabPreferencesSubtitle;

  /// Settings landing: Integrations tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Strava, parkrun, race calendar, heart-rate strap, treadmill, watch'**
  String get settingsTabIntegrationsSubtitle;

  /// Settings landing: Devices tile subtitle when signed in
  ///
  /// In en, this message translates to:
  /// **'Where you\'re signed in and per-device overrides — pair a strap or treadmill under Integrations'**
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

  /// Settings landing: About & updates tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Version, updates and legal documents'**
  String get settingsTabAboutSubtitle;

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

  /// Label on the guided-session input where the athlete records the distance they actually covered on a distance-modality set
  ///
  /// In en, this message translates to:
  /// **'Distance (m)'**
  String get gymDistance;

  /// A set's distance target in metres
  ///
  /// In en, this message translates to:
  /// **'{metres} m'**
  String gymDistanceValue(String metres);

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

  /// Button that hands a one-off club event to the phone's calendar app.
  ///
  /// In en, this message translates to:
  /// **'Add to calendar'**
  String get clubEventAddToCalendar;

  /// Button that hands only the selected occurrence of a recurring club event to the phone's calendar app.
  ///
  /// In en, this message translates to:
  /// **'Add this occurrence'**
  String get clubEventAddOccurrenceToCalendar;

  /// Button that hands a recurring club event to the phone's calendar app as a repeating entry.
  ///
  /// In en, this message translates to:
  /// **'Add whole series'**
  String get clubEventAddSeriesToCalendar;

  /// Banner shown when the calendar hand-off could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your calendar app.'**
  String get clubEventCalendarUnavailable;

  /// Note under the add-whole-series button naming how many called-off occurrences the repeating calendar entry will still show.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Your calendar can\'t skip called-off dates, so 1 cancelled occurrence will still appear.} other{Your calendar can\'t skip called-off dates, so {count} cancelled occurrences will still appear.}}'**
  String clubEventCalendarCancelledNote(int count);

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

  /// Shown when the typed name matches a catalogue entry the category filter is hiding
  ///
  /// In en, this message translates to:
  /// **'“{name}” is already in the catalogue, under {category}.'**
  String gymCatalogueOtherCategory(String name, String category);

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

  /// Routine detail: heading of the past-sessions panel
  ///
  /// In en, this message translates to:
  /// **'Routine history'**
  String get gymRoutineHistoryTitle;

  /// Routine detail: sub-heading above the recent session list
  ///
  /// In en, this message translates to:
  /// **'Recent sessions'**
  String get gymRoutineHistoryRecent;

  /// Routine detail: how long ago the routine was last performed
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Done today} =1{Done yesterday} other{Done {days} days ago}}'**
  String gymRoutineHistoryLastDone(int days);

  /// Routine detail: how many graded sessions of the routine were completed
  ///
  /// In en, this message translates to:
  /// **'{completed} of {graded} completed'**
  String gymRoutineHistoryCompletedRate(int completed, int graded);

  /// Routine detail: verdict badge for a session saved without an adherence grade
  ///
  /// In en, this message translates to:
  /// **'Not graded'**
  String get gymRoutineHistoryVerdictUngraded;

  /// Routine detail: the past-sessions panel could not be read
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this routine’s history.'**
  String get gymRoutineHistoryLoadError;

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

  /// No description provided for @nutritionDayNavLabel.
  ///
  /// In en, this message translates to:
  /// **'Diary day'**
  String get nutritionDayNavLabel;

  /// No description provided for @nutritionDayPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get nutritionDayPrevious;

  /// No description provided for @nutritionDayNext.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get nutritionDayNext;

  /// No description provided for @nutritionDayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get nutritionDayToday;

  /// No description provided for @nutritionDayYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get nutritionDayYesterday;

  /// No description provided for @nutritionDayBackfillHint.
  ///
  /// In en, this message translates to:
  /// **'Anything you log here is added to this day.'**
  String get nutritionDayBackfillHint;

  /// No description provided for @nutritionDayEmptyPast.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged on this day.'**
  String get nutritionDayEmptyPast;

  /// Calorie goal breakdown on a past diary day: base goal + exercise kcal burned that day
  ///
  /// In en, this message translates to:
  /// **'Goal {base} + {exercise} kcal burned that day'**
  String nutritionDayGoalBreakdown(int base, int exercise);

  /// Trend-card heading when the diary is showing a past day
  ///
  /// In en, this message translates to:
  /// **'7 days to {date}'**
  String nutritionDayTrendEnding(String date);

  /// Log-food composer title when the diary is showing a past day
  ///
  /// In en, this message translates to:
  /// **'Log food — {date}'**
  String nutritionDayLogHeadingFor(String date);

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

  /// No description provided for @nutritionFiber.
  ///
  /// In en, this message translates to:
  /// **'Fiber'**
  String get nutritionFiber;

  /// No description provided for @nutritionSugar.
  ///
  /// In en, this message translates to:
  /// **'Sugar'**
  String get nutritionSugar;

  /// No description provided for @nutritionSodium.
  ///
  /// In en, this message translates to:
  /// **'Sodium'**
  String get nutritionSodium;

  /// No description provided for @nutritionSaturatedFat.
  ///
  /// In en, this message translates to:
  /// **'Saturated fat'**
  String get nutritionSaturatedFat;

  /// No description provided for @nutritionCholesterol.
  ///
  /// In en, this message translates to:
  /// **'Cholesterol'**
  String get nutritionCholesterol;

  /// Section title for the nutrition day's extended-nutrient roll-up
  ///
  /// In en, this message translates to:
  /// **'Nutrients'**
  String get nutritionNutrients;

  /// Footnote under the nutrients section explaining partial coverage
  ///
  /// In en, this message translates to:
  /// **'Reference intakes. Each total counts only the logged items that report that nutrient.'**
  String get nutritionNutrientsHint;

  /// Prefix on a nutrient total that only some logged items reported
  ///
  /// In en, this message translates to:
  /// **'at least'**
  String get nutritionNutrientAtLeast;

  /// Accessible explanation of a partially-covered nutrient total
  ///
  /// In en, this message translates to:
  /// **'{reported} of {total} logged items report {nutrient}'**
  String nutritionNutrientPartial(int reported, int total, String nutrient);

  /// Nutrient chip: amount past a ceiling nutrient's daily reference
  ///
  /// In en, this message translates to:
  /// **'{n} {unit} over'**
  String nutritionNutrientOver(String n, String unit);

  /// Nutrient chip: amount still within a nutrient's daily reference
  ///
  /// In en, this message translates to:
  /// **'{n} {unit} left'**
  String nutritionNutrientLeft(String n, String unit);

  /// Nutrient chip: a floor nutrient has met its daily reference
  ///
  /// In en, this message translates to:
  /// **'Goal reached'**
  String get nutritionNutrientReached;

  /// Nutrient chip: this nutrient is reported but deliberately ungraded
  ///
  /// In en, this message translates to:
  /// **'No daily target'**
  String get nutritionNutrientUntargeted;

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
  /// **'Add your height, weight, age and sex to see calorie + macro targets.'**
  String get nutritionNoTargets;

  /// CTA on the nutrition rings card that opens Settings > Body metrics
  ///
  /// In en, this message translates to:
  /// **'Add body metrics'**
  String get nutritionAddBodyMetrics;

  /// Label of the always-available entry from the Nutrition rings card to the targets screen
  ///
  /// In en, this message translates to:
  /// **'Targets'**
  String get nutritionTargetsLink;

  /// Nutrition targets screen title
  ///
  /// In en, this message translates to:
  /// **'Calorie & macro targets'**
  String get nutritionTargetsTitle;

  /// Nutrition targets screen subtitle
  ///
  /// In en, this message translates to:
  /// **'How today\'s goal is worked out, and the two settings that shape it.'**
  String get nutritionTargetsSubtitle;

  /// Heading over the derived daily calorie goal
  ///
  /// In en, this message translates to:
  /// **'Eat-to goal today'**
  String get nutritionTargetsTotal;

  /// Derivation row: Mifflin-St Jeor resting metabolic rate
  ///
  /// In en, this message translates to:
  /// **'Resting metabolism'**
  String get nutritionTargetsBmr;

  /// Derivation subtotal: the non-exercise calorie goal
  ///
  /// In en, this message translates to:
  /// **'Base goal'**
  String get nutritionTargetsBase;

  /// Note shown when the base goal is held at the safety floor. {n} is that floor in kcal.
  ///
  /// In en, this message translates to:
  /// **'Held at the {n} kcal floor — the lowest daily goal we\'ll suggest.'**
  String nutritionTargetsBaseFloored(int n);

  /// Derivation row: today's logged workouts added on top
  ///
  /// In en, this message translates to:
  /// **'Today\'s workouts'**
  String get nutritionTargetsExercise;

  /// Hint under the workout add-on row
  ///
  /// In en, this message translates to:
  /// **'Runs and gym sessions you log today are added on top.'**
  String get nutritionTargetsExerciseHint;

  /// Heading of the macro-split card
  ///
  /// In en, this message translates to:
  /// **'Macros'**
  String get nutritionTargetsMacrosHeading;

  /// Hint under the protein target. {n} is grams per kg of bodyweight.
  ///
  /// In en, this message translates to:
  /// **'{n} g per kg of bodyweight'**
  String nutritionTargetsProteinHint(String n);

  /// Hint under the carbohydrate target
  ///
  /// In en, this message translates to:
  /// **'Whatever\'s left — your fuel'**
  String get nutritionTargetsCarbsHint;

  /// Hint under the fat target. {n} is a percentage of calories.
  ///
  /// In en, this message translates to:
  /// **'{n}% of calories'**
  String nutritionTargetsFatHint(int n);

  /// Heading of the card holding the two non-sensitive target levers
  ///
  /// In en, this message translates to:
  /// **'Your defaults'**
  String get nutritionTargetsDefaultsHeading;

  /// Hint explaining that activity level excludes logged workouts and both levers auto-save
  ///
  /// In en, this message translates to:
  /// **'Activity level is your typical day excluding workouts — the runs and gym sessions you log are added separately. Both save as you change them.'**
  String get nutritionTargetsDefaultsHint;

  /// Heading of the read-only body-metrics card
  ///
  /// In en, this message translates to:
  /// **'Body metrics'**
  String get nutritionTargetsMetricsHeading;

  /// Hint explaining that body metrics are health data edited in Settings behind the consent gate
  ///
  /// In en, this message translates to:
  /// **'Height, weight, date of birth and sex are health data, so they\'re edited in Settings behind their consent gate.'**
  String get nutritionTargetsMetricsHint;

  /// Action opening the consent-gated body-metrics editor in Settings
  ///
  /// In en, this message translates to:
  /// **'Edit in Settings'**
  String get nutritionTargetsEditMetrics;

  /// Placeholder for a body metric the user has not provided
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get nutritionTargetsUnset;

  /// Title of the no-targets-yet state on the targets screen
  ///
  /// In en, this message translates to:
  /// **'No targets yet'**
  String get nutritionTargetsEmptyTitle;

  /// Body of the no-targets-yet state on the targets screen
  ///
  /// In en, this message translates to:
  /// **'Add your height, weight, date of birth and sex and your calorie + macro targets appear here.'**
  String get nutritionTargetsEmptyBody;

  /// Body-metrics row label for age
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get nutritionTargetsAge;

  /// Age in whole years. {n} is the age.
  ///
  /// In en, this message translates to:
  /// **'{n} years'**
  String nutritionTargetsAgeYears(int n);

  /// Body-metrics row value when a date of birth is on record but the Art 9 health-data consent is not, so the age cannot be used for the calorie target
  ///
  /// In en, this message translates to:
  /// **'Needs health-data consent'**
  String get nutritionTargetsAgeConsentWithheld;

  /// Error state when the targets screen's read fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your targets.'**
  String get nutritionTargetsLoadError;

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

  /// Banner when deleting a logged food entry fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t delete the entry: {error}'**
  String nutritionDeleteFailed(String error);

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

  /// Banner shown when the explicit leave-and-keep-draft save failed and the runner was kept on the session rather than navigated away with the work lost
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your draft — you\'re still here, so nothing is lost. Try again, or discard the session on purpose.'**
  String get gymSessionLeaveSaveFailed;

  /// Title of the three-way dialog shown when backing out of a live guided session
  ///
  /// In en, this message translates to:
  /// **'Leave workout?'**
  String get gymSessionLeaveTitle;

  /// Body of the leave-session dialog explaining the draft-and-resume path
  ///
  /// In en, this message translates to:
  /// **'Your logged sets are kept as a draft — you can pick the session back up from the Gym tab, or discard it.'**
  String get gymSessionLeaveBody;

  /// Leave-session dialog action that exits while keeping the resumable draft
  ///
  /// In en, this message translates to:
  /// **'Leave — keep draft'**
  String get gymSessionLeaveDraft;

  /// Leave-session dialog action that stays in the live session
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get gymSessionKeepGoing;

  /// Title of the gym-screen card offering to resume an in-flight guided-session draft
  ///
  /// In en, this message translates to:
  /// **'Workout in progress'**
  String get gymDraftTitle;

  /// Logged-set count on the gym-screen resume card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 set logged} other{{count} sets logged}}'**
  String gymDraftSetCount(int count);

  /// Resume-card action restoring the guided session from its draft
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get gymDraftResume;

  /// Resume-card action keeping the draft's logged sets as a finished workout without resuming
  ///
  /// In en, this message translates to:
  /// **'Save as is'**
  String get gymDraftSave;

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
  /// **'Athletes & coaches'**
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

  /// Course marker cut-off time validation
  ///
  /// In en, this message translates to:
  /// **'Enter the cut-off as HH:MM (24-hour)'**
  String get routeMarkerCutoffInvalid;

  /// Toggle: the marker time is a wall-clock time of day
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get routeMarkerTimeClock;

  /// Toggle: the marker time is measured from the race start
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get routeMarkerTimeElapsed;

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

  /// Button opening the marker editor without a map tap (accepts lat/lng or a distance along the route), for keyboard / screen-reader placement
  ///
  /// In en, this message translates to:
  /// **'Enter location instead'**
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

  /// Title of the sheet asking for the goal time and race start before a schedule is sent to the watch
  ///
  /// In en, this message translates to:
  /// **'Race plan'**
  String get roadbookPlanTitle;

  /// Explains why the goal time and start clock are being asked for
  ///
  /// In en, this message translates to:
  /// **'The watch builds its arrival and cut-off times from these. Set a start time so cut-offs given as a time of day can be sent too.'**
  String get roadbookPlanExplain;

  /// Dismiss the race-plan sheet without sending a schedule
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get roadbookPlanCancel;

  /// Confirm the race plan and send the schedule
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get roadbookPlanSend;

  /// Validation error when the goal time cannot be parsed
  ///
  /// In en, this message translates to:
  /// **'Enter a goal time like 4:30:00'**
  String get roadbookPlanGoalInvalid;

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

  /// Label on the roadbook target-time verdict chip
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get roadbookColTarget;

  /// Roadbook per-leg pace label - the pace this stretch has to be run at to hold the goal
  ///
  /// In en, this message translates to:
  /// **'Leg pace'**
  String get roadbookColLegPace;

  /// Roadbook target verdict: the projection is ahead of the planned time
  ///
  /// In en, this message translates to:
  /// **'ahead'**
  String get roadbookTargetAhead;

  /// Roadbook target verdict: the projection is within the on-schedule band
  ///
  /// In en, this message translates to:
  /// **'on plan'**
  String get roadbookTargetOn;

  /// Roadbook target verdict: the projection is behind the planned time
  ///
  /// In en, this message translates to:
  /// **'behind'**
  String get roadbookTargetBehind;

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

  /// Body weight field label on the weigh-in sheet. Deliberately names NO unit: the field's suffix carries the runner's own weight unit, so a label saying kg contradicts an lb suffix.
  ///
  /// In en, this message translates to:
  /// **'Body weight'**
  String get checkpointWeighInBodyWeight;

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

  /// Heading of the viewer standing card above the challenge leaderboard
  ///
  /// In en, this message translates to:
  /// **'Your standing'**
  String get challengesStandingTitle;

  /// Heading of the standing card on a club-vs-club leaderboard
  ///
  /// In en, this message translates to:
  /// **'Your team\'s standing'**
  String get challengesStandingTitleTeam;

  /// Viewer rank out of the board size
  ///
  /// In en, this message translates to:
  /// **'#{rank} of {total}'**
  String challengesStandingRank(int rank, int total);

  /// Standing card: exactly one other entrant shares the viewer rank
  ///
  /// In en, this message translates to:
  /// **'Tied with 1 other'**
  String get challengesStandingTiedOne;

  /// Standing card: several other entrants share the viewer rank
  ///
  /// In en, this message translates to:
  /// **'Tied with {n} others'**
  String challengesStandingTiedMany(int n);

  /// Standing card: metric gap to the nearest entrant ranked above
  ///
  /// In en, this message translates to:
  /// **'{gap} behind {name}'**
  String challengesStandingBehind(String gap, String name);

  /// Standing card: metric margin over the nearest entrant ranked below
  ///
  /// In en, this message translates to:
  /// **'{gap} ahead of {name}'**
  String challengesStandingAhead(String gap, String name);

  /// Standing card: the viewer leads the board outright
  ///
  /// In en, this message translates to:
  /// **'Leading'**
  String get challengesStandingLeading;

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

  /// Shown on a joined-challenge row whose per-caller value is not in the my_active_challenges window — never a zero bar
  ///
  /// In en, this message translates to:
  /// **'Progress unavailable — open for your result'**
  String get challengesProgressUnavailable;

  /// Club-vs-club leaderboard label for the unaffiliated participant group
  ///
  /// In en, this message translates to:
  /// **'No club'**
  String get challengesTeamNoClub;

  /// Club-vs-club leaderboard label for a club the viewer cannot read
  ///
  /// In en, this message translates to:
  /// **'Private club'**
  String get challengesTeamPrivateClub;

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

  /// Distance-from-you label on a race card. {distance} is already formatted in the user's unit (km or mi).
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String racesDistanceAway(String distance);

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

  /// Race card action that opens the plan wizard sized around that race
  ///
  /// In en, this message translates to:
  /// **'Train for this race'**
  String get racesTrainForThis;

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

  /// Hint above the RunSignUp import action requiring a bib to scope the import
  ///
  /// In en, this message translates to:
  /// **'Enter your bib number so we import only your result, not the whole field.'**
  String get racesRunSignUpBibHint;

  /// Label for the UltraSignup athlete-id field in the race import sheet
  ///
  /// In en, this message translates to:
  /// **'UltraSignup athlete ID'**
  String get racesUltraSignUpAthleteId;

  /// Hint above the UltraSignup import action explaining the optional athlete id
  ///
  /// In en, this message translates to:
  /// **'Enter your UltraSignup athlete ID, or leave it blank to use the one this listing carries.'**
  String get racesUltraSignUpAthleteHint;

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

  /// UltraSignup integration name
  ///
  /// In en, this message translates to:
  /// **'UltraSignup'**
  String get integrationsUltrasignup;

  /// UltraSignup integration description
  ///
  /// In en, this message translates to:
  /// **'Import trail and ultra results from UltraSignup.'**
  String get integrationsUltrasignupConnect;

  /// Action linking to the race calendar from the UltraSignup tile
  ///
  /// In en, this message translates to:
  /// **'Open the race calendar'**
  String get integrationsUltrasignupOpen;

  /// Explainer when the UltraSignup key is unconfigured
  ///
  /// In en, this message translates to:
  /// **'UltraSignup import isn\'t available yet. parkrun and manual paste still work.'**
  String get integrationsUltrasignupUnavailable;

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

  /// Button that pushes a structured demo workout to the custom watch over BLE
  ///
  /// In en, this message translates to:
  /// **'Push workout to watch'**
  String get simWatchPushWorkoutAction;

  /// No description provided for @simWatchWorkoutPushed.
  ///
  /// In en, this message translates to:
  /// **'Workout pushed to the watch ({steps} steps)'**
  String simWatchWorkoutPushed(int steps);

  /// No description provided for @simWatchPushWorkoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Workout push failed: {error}'**
  String simWatchPushWorkoutFailed(String error);

  /// Tooltip for the dev sim-watch action that pushes the canned RBK1 roadbook schedule
  ///
  /// In en, this message translates to:
  /// **'Push roadbook to watch'**
  String get simWatchPushRoadbookAction;

  /// Status line after the dev sim-watch roadbook push succeeds
  ///
  /// In en, this message translates to:
  /// **'Roadbook pushed to the watch ({checkpoints} checkpoints, {cutoffs} cut-offs)'**
  String simWatchRoadbookPushed(int checkpoints, int cutoffs);

  /// Status line after the dev sim-watch roadbook push fails
  ///
  /// In en, this message translates to:
  /// **'Roadbook push failed: {error}'**
  String simWatchPushRoadbookFailed(String error);

  /// Button that pushes a demo breadcrumb course to the custom watch over BLE
  ///
  /// In en, this message translates to:
  /// **'Push course to watch'**
  String get simWatchPushCourseAction;

  /// No description provided for @simWatchCoursePushed.
  ///
  /// In en, this message translates to:
  /// **'Course pushed to the watch ({points} points)'**
  String simWatchCoursePushed(int points);

  /// No description provided for @simWatchPushCourseFailed.
  ///
  /// In en, this message translates to:
  /// **'Course push failed: {error}'**
  String simWatchPushCourseFailed(String error);

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

  /// Error message when the session-plan list fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load sessions.'**
  String get sessionLoadError;

  /// Error message when a session plan detail fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this session plan.'**
  String get sessionDetailLoadError;

  /// Title of the remove-exercise confirmation dialog in the gym composer
  ///
  /// In en, this message translates to:
  /// **'Remove exercise?'**
  String get gymEditorRemoveExerciseTitle;

  /// Body of the remove-exercise confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This exercise and all its sets will be removed from this workout.'**
  String get gymEditorRemoveExerciseBody;

  /// Confirm button of the remove-exercise dialog
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get gymEditorRemoveExerciseConfirm;

  /// Error when the submit-time sheet fails to load recent runs
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your recent runs.'**
  String get eventSubmitRunsLoadError;

  /// Banner when a race entry/results URL cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that link.'**
  String get racesCouldNotOpenLink;

  /// Title of the clear-HR-zones confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Clear heart-rate zones?'**
  String get prefsHrZonesClearTitle;

  /// Body of the clear-HR-zones confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Your five custom zones will be cleared.'**
  String get prefsHrZonesClearBody;

  /// Confirm button of the clear-HR-zones dialog
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get prefsHrZonesClearConfirm;

  /// Generic body of the shared sign-in-required state on auth-only surfaces
  ///
  /// In en, this message translates to:
  /// **'Sign in to use this feature.'**
  String get signInRequiredMessage;

  /// CTA button on the shared sign-in-required state; opens the sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInRequiredAction;

  /// Body of the shared state when the backend is unreachable at launch (no sign-in CTA can help)
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server right now. Online features are unavailable.'**
  String get backendUnavailableMessage;

  /// Body of the sign-in-required state on the following feed
  ///
  /// In en, this message translates to:
  /// **'Sign in to see runs from people you follow.'**
  String get feedSignedOutMessage;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Speed up by {sec} seconds per kilometre'**
  String ttsPaceAlertSpeedUpByKm(int sec);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Speed up by {sec} seconds per mile'**
  String ttsPaceAlertSpeedUpByMi(int sec);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Slow down by {sec} seconds per kilometre'**
  String ttsPaceAlertSlowDownByKm(int sec);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Slow down by {sec} seconds per mile'**
  String ttsPaceAlertSlowDownByMi(int sec);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Next cutoff in {distance}. You need {pace} to make it.'**
  String ttsCutoffCatchUp(String distance, String pace);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Next cutoff: the time limit has passed.'**
  String get ttsCutoffUnreachable;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'{label}: {time} ahead of plan'**
  String ttsMarkerAheadOfPlan(String label, String time);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'{label}: {time} behind plan'**
  String ttsMarkerBehindPlan(String label, String time);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'{label}: on plan'**
  String ttsMarkerOnPlan(String label);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Phase {index} of {total}. {phrase}'**
  String ttsPhaseStart(int index, int total, String phrase);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Hold back. Stay controlled.'**
  String get ttsPhaseHoldBack;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Settle into your goal pace.'**
  String get ttsPhaseSettle;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Time to race. Give what you have left.'**
  String get ttsPhaseRace;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Hold an even effort.'**
  String get ttsPhaseEven;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Target {pace}.'**
  String ttsPhaseTargetPace(String pace);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Spoken cues'**
  String get prefsVoiceCueTypesLabel;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Splits'**
  String get prefsCueSplits;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Your pace (or speed) each time you pass a split marker'**
  String get prefsCueSplitsSubtitle;

  /// Info popup body + example for the Splits cue
  ///
  /// In en, this message translates to:
  /// **'Speaks a short summary every time you complete a split (set the distance under Split interval). Use Splits announce to pick split pace, average pace, or both. Example: “1 kilometre. Pace, 5 minutes 30 seconds per kilometre.”'**
  String get prefsCueSplitsInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Start and finish'**
  String get prefsCueStartFinish;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'“Run started” at the start, and a summary when you finish'**
  String get prefsCueStartFinishSubtitle;

  /// Info popup body + example for the start/finish cue
  ///
  /// In en, this message translates to:
  /// **'Confirms the run began and reads your distance and time when you stop. Example: “Run complete. 10.0 kilometres in 52 minutes.”'**
  String get prefsCueStartFinishInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Off-route warning'**
  String get prefsCueOffRoute;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'A heads-up when you stray from a route you’re following'**
  String get prefsCueOffRouteSubtitle;

  /// Info popup body + example for the off-route cue
  ///
  /// In en, this message translates to:
  /// **'Only works when you start a run with a saved route. Warns you once you drift away from it so you can get back on course. Example: “Off route.”'**
  String get prefsCueOffRouteInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Off-pace alerts'**
  String get prefsCuePaceAlerts;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'“Speed up” / “slow down” when you drift from your Target pace'**
  String get prefsCuePaceAlertsSubtitle;

  /// Info popup body + example for the off-pace alerts cue
  ///
  /// In en, this message translates to:
  /// **'Needs a Target pace set. When you drift more than about 30 seconds off it, this tells you which way to adjust and by how much. Example: “Speed up by 8 seconds.”'**
  String get prefsCuePaceAlertsInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Workout steps'**
  String get prefsCueWorkoutSteps;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Calls each step of a structured workout as it begins'**
  String get prefsCueWorkoutStepsSubtitle;

  /// Info popup body + example for the workout-steps cue
  ///
  /// In en, this message translates to:
  /// **'Only active during a structured workout (a plan session or interval workout). Announces each step and its target so you can keep your eyes up. Example: “Rep 3 of 5. 400 metres at 4 minutes 30 seconds per kilometre.”'**
  String get prefsCueWorkoutStepsInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Cutoff catch-up'**
  String get prefsCueCutoffCatchUp;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'The pace you need to make a cutoff you’re at risk of missing'**
  String get prefsCueCutoffCatchUpSubtitle;

  /// Info popup body + example for the cutoff catch-up cue
  ///
  /// In en, this message translates to:
  /// **'Only active on a route with course cutoffs. If one is at risk, it reads the distance to it and the pace that still makes it. Example: “2 kilometres to the cutoff. 6 minutes per kilometre.”'**
  String get prefsCueCutoffCatchUpInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Course marker targets'**
  String get prefsCueMarkerTargets;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Whether you’re ahead of or behind plan at each course marker'**
  String get prefsCueMarkerTargetsSubtitle;

  /// Info popup body + example for the marker-targets cue
  ///
  /// In en, this message translates to:
  /// **'Only active on a route whose course markers carry target times. As you pass each one it tells you if you’re ahead or behind, and by how much. Example: “Aid 2: 45 seconds ahead of plan.”'**
  String get prefsCueMarkerTargetsInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Race phases'**
  String get prefsCuePhaseTransitions;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'A cue when each phase of your race-strategy plan begins'**
  String get prefsCuePhaseTransitionsSubtitle;

  /// Info popup body + example for the race-phases cue
  ///
  /// In en, this message translates to:
  /// **'Only active when you pick a Race strategy for the run. Announces each phase and its intent as it starts. Example: “Phase 2 of 3. Settle into your goal pace.”'**
  String get prefsCuePhaseTransitionsInfo;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Guided runs'**
  String get prefsCueGuidedRun;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'The coach script of a guided run you armed before starting'**
  String get prefsCueGuidedRunSubtitle;

  /// Info popup body + example for the guided-run cue
  ///
  /// In en, this message translates to:
  /// **'Only active when you arm a guided run on the Run tab before you start. Speaks each scripted coach cue as you reach its mark. Example: “Five minutes in. Settle into a rhythm you could hold all day.”'**
  String get prefsCueGuidedRunInfo;

  /// Run screen — the idle-state affordance that arms a guided run for the next recording
  ///
  /// In en, this message translates to:
  /// **'Guided run'**
  String get runGuidedRun;

  /// Run screen — the guided-run picker row that clears the armed run
  ///
  /// In en, this message translates to:
  /// **'No guided run'**
  String get runGuidedRunNone;

  /// Run screen — a guided-run picker row subtitle
  ///
  /// In en, this message translates to:
  /// **'{minutes} min · {subtitle}'**
  String runGuidedRunOption(int minutes, String subtitle);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Race strategy'**
  String get runRaceStrategy;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'No strategy'**
  String get runStrategyNone;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'10-10-10'**
  String get runStrategyTenTenTen;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Negative split'**
  String get runStrategyNegativeSplit;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Even pace'**
  String get runStrategyEven;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Hold back, settle in, race the final stretch'**
  String get runStrategyTenTenTenHint;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'First half controlled, second half faster'**
  String get runStrategyNegativeSplitHint;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'One steady pace start to finish'**
  String get runStrategyEvenHint;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Goal time'**
  String get runStrategyGoalTime;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get runStrategyDistance;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Choose a route or enter a distance to enable phases'**
  String get runStrategyNeedsDistance;

  /// No description provided for @runStrategyInvalidGoal.
  ///
  /// In en, this message translates to:
  /// **'Enter the goal time as h:mm:ss'**
  String get runStrategyInvalidGoal;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Phase {index}/{total} — {intent}'**
  String runPhaseChip(int index, int total, String intent);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Hold back'**
  String get phaseIntentHoldBack;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Settle'**
  String get phaseIntentSettle;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Race'**
  String get phaseIntentRace;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Even'**
  String get phaseIntentEven;

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Target {time}'**
  String routeMarkerTargetChip(String time);

  /// Voice cues / race strategy
  ///
  /// In en, this message translates to:
  /// **'Target time'**
  String get routeMarkerTargetLabel;

  /// Persistent helper under the course-marker target-time field clarifying the h:mm:ss format
  ///
  /// In en, this message translates to:
  /// **'Hours : minutes : seconds'**
  String get routeMarkerTargetHelper;

  /// Course marker target-time validation
  ///
  /// In en, this message translates to:
  /// **'Enter the target time as h:mm:ss'**
  String get routeMarkerTargetInvalid;

  /// Badge on a course marker that belongs to the route owner (official), shown to a non-owner viewer
  ///
  /// In en, this message translates to:
  /// **'Route owner'**
  String get routeMarkerOfficialBadge;

  /// Editor field to place a course marker by distance along the route instead of lat/lng
  ///
  /// In en, this message translates to:
  /// **'Distance along route'**
  String get routeMarkerDistanceAlongLabel;

  /// Validation when the distance-along-route value can't be parsed
  ///
  /// In en, this message translates to:
  /// **'Enter a valid distance along the route.'**
  String get routeMarkerDistanceInvalid;

  /// Title of the composed-watch-screen editor
  ///
  /// In en, this message translates to:
  /// **'Watch screens'**
  String get watchScreensTitle;

  /// Tooltip opening the composed-watch-screen editor
  ///
  /// In en, this message translates to:
  /// **'Compose watch screens'**
  String get watchScreensAction;

  /// No description provided for @watchScreensCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} screens'**
  String watchScreensCount(int count, int max);

  /// No description provided for @watchScreensEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No screens composed'**
  String get watchScreensEmptyTitle;

  /// Empty state explaining what composing a watch screen does
  ///
  /// In en, this message translates to:
  /// **'The watch walks its built-in pages until you compose one. Add a screen to choose what it shows.'**
  String get watchScreensEmptyBody;

  /// No description provided for @watchScreensAdd.
  ///
  /// In en, this message translates to:
  /// **'Add screen'**
  String get watchScreensAdd;

  /// No description provided for @watchScreensFull.
  ///
  /// In en, this message translates to:
  /// **'A watch holds at most {max} screens.'**
  String watchScreensFull(int max);

  /// No description provided for @watchScreensHeading.
  ///
  /// In en, this message translates to:
  /// **'Screen {index}'**
  String watchScreensHeading(int index);

  /// No description provided for @watchScreensLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get watchScreensLayout;

  /// No description provided for @watchScreensSlot.
  ///
  /// In en, this message translates to:
  /// **'Slot {index}'**
  String watchScreensSlot(int index);

  /// No description provided for @watchScreensMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get watchScreensMoveUp;

  /// No description provided for @watchScreensMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get watchScreensMoveDown;

  /// No description provided for @watchScreensRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove screen'**
  String get watchScreensRemove;

  /// No description provided for @watchScreensRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove screen {index}?'**
  String watchScreensRemoveTitle(int index);

  /// No description provided for @watchScreensRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Its {count} metric(s) go with it.'**
  String watchScreensRemoveBody(int count);

  /// No description provided for @watchScreensRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get watchScreensRemoveConfirm;

  /// No description provided for @watchScreensCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get watchScreensCancel;

  /// No description provided for @watchScreensShrinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop {count} metric(s)?'**
  String watchScreensShrinkTitle(int count);

  /// Warning naming the metrics a narrower layout would drop
  ///
  /// In en, this message translates to:
  /// **'A {layout} screen draws {slots} slot(s), so {dropped} would no longer be shown.'**
  String watchScreensShrinkBody(String layout, int slots, String dropped);

  /// No description provided for @watchScreensShrinkConfirm.
  ///
  /// In en, this message translates to:
  /// **'Change layout'**
  String get watchScreensShrinkConfirm;

  /// Button that pushes the composed screen set to the watch over BLE
  ///
  /// In en, this message translates to:
  /// **'Push screens to watch'**
  String get watchScreensPushAction;

  /// No description provided for @watchScreensPushed.
  ///
  /// In en, this message translates to:
  /// **'Pushed {count} screen(s) to the watch'**
  String watchScreensPushed(int count);

  /// No description provided for @watchScreensCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared the composed screens on the watch'**
  String get watchScreensCleared;

  /// No description provided for @watchScreensPushFailed.
  ///
  /// In en, this message translates to:
  /// **'Screens push failed: {error}'**
  String watchScreensPushFailed(String error);

  /// No description provided for @watchScreensLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The saved screens couldn\'t be read.'**
  String get watchScreensLoadFailed;

  /// No description provided for @watchScreensStartOver.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get watchScreensStartOver;

  /// No description provided for @watchLayoutSingle.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get watchLayoutSingle;

  /// No description provided for @watchLayoutDuo.
  ///
  /// In en, this message translates to:
  /// **'Duo'**
  String get watchLayoutDuo;

  /// No description provided for @watchLayoutTrio.
  ///
  /// In en, this message translates to:
  /// **'Trio'**
  String get watchLayoutTrio;

  /// No description provided for @watchMetricElapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed time'**
  String get watchMetricElapsed;

  /// No description provided for @watchMetricDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get watchMetricDistance;

  /// No description provided for @watchMetricAvgPace.
  ///
  /// In en, this message translates to:
  /// **'Average pace'**
  String get watchMetricAvgPace;

  /// No description provided for @watchMetricLapElapsed.
  ///
  /// In en, this message translates to:
  /// **'Lap time'**
  String get watchMetricLapElapsed;

  /// No description provided for @watchMetricHeartRate.
  ///
  /// In en, this message translates to:
  /// **'Heart rate'**
  String get watchMetricHeartRate;

  /// No description provided for @watchMetricPacerDelta.
  ///
  /// In en, this message translates to:
  /// **'Pacer delta'**
  String get watchMetricPacerDelta;

  /// No description provided for @watchMetricGuidedRunRemaining.
  ///
  /// In en, this message translates to:
  /// **'Guided-run cue'**
  String get watchMetricGuidedRunRemaining;

  /// No description provided for @watchMetricWorkoutRemaining.
  ///
  /// In en, this message translates to:
  /// **'Workout step'**
  String get watchMetricWorkoutRemaining;

  /// No description provided for @watchMetricRacePrediction.
  ///
  /// In en, this message translates to:
  /// **'Race prediction'**
  String get watchMetricRacePrediction;

  /// No description provided for @watchMetricCutoffMargin.
  ///
  /// In en, this message translates to:
  /// **'Cut-off margin'**
  String get watchMetricCutoffMargin;

  /// No description provided for @watchMetricTrainingStress.
  ///
  /// In en, this message translates to:
  /// **'Training load'**
  String get watchMetricTrainingStress;

  /// No description provided for @watchMetricRoadbookNext.
  ///
  /// In en, this message translates to:
  /// **'Next aid station'**
  String get watchMetricRoadbookNext;

  /// No description provided for @watchMetricFuelCarbs.
  ///
  /// In en, this message translates to:
  /// **'Fuel carbs'**
  String get watchMetricFuelCarbs;

  /// No description provided for @watchMetricGearWear.
  ///
  /// In en, this message translates to:
  /// **'Gear wear'**
  String get watchMetricGearWear;

  /// No description provided for @watchMetricEasyPace.
  ///
  /// In en, this message translates to:
  /// **'Easy pace'**
  String get watchMetricEasyPace;

  /// No description provided for @watchMetricVo2Max.
  ///
  /// In en, this message translates to:
  /// **'VO2 max'**
  String get watchMetricVo2Max;

  /// No description provided for @watchMetricAltitude.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get watchMetricAltitude;

  /// No description provided for @watchMetricDistanceToStart.
  ///
  /// In en, this message translates to:
  /// **'Distance to start'**
  String get watchMetricDistanceToStart;

  /// No description provided for @watchMetricDaylightCountdown.
  ///
  /// In en, this message translates to:
  /// **'Daylight left'**
  String get watchMetricDaylightCountdown;

  /// No description provided for @watchMetricWaypointDistance.
  ///
  /// In en, this message translates to:
  /// **'Waypoint distance'**
  String get watchMetricWaypointDistance;

  /// No description provided for @watchMetricClimbGain.
  ///
  /// In en, this message translates to:
  /// **'Climb gain'**
  String get watchMetricClimbGain;

  /// No description provided for @watchMetricRecapDistance.
  ///
  /// In en, this message translates to:
  /// **'Year distance'**
  String get watchMetricRecapDistance;

  /// No description provided for @watchMetricCurrentStreak.
  ///
  /// In en, this message translates to:
  /// **'Current streak'**
  String get watchMetricCurrentStreak;

  /// No description provided for @watchMetricSyncedMovingTime.
  ///
  /// In en, this message translates to:
  /// **'Moving time'**
  String get watchMetricSyncedMovingTime;

  /// No description provided for @watchMetricPrAge.
  ///
  /// In en, this message translates to:
  /// **'PR age'**
  String get watchMetricPrAge;

  /// No description provided for @watchMetricPlanReplanChanges.
  ///
  /// In en, this message translates to:
  /// **'Re-plan changes'**
  String get watchMetricPlanReplanChanges;

  /// No description provided for @watchMetricPlanAdaptiveChanges.
  ///
  /// In en, this message translates to:
  /// **'Adaptive changes'**
  String get watchMetricPlanAdaptiveChanges;

  /// No description provided for @watchMetricReadinessScore.
  ///
  /// In en, this message translates to:
  /// **'Readiness'**
  String get watchMetricReadinessScore;

  /// No description provided for @watchMetricGoalPercent.
  ///
  /// In en, this message translates to:
  /// **'Goal progress'**
  String get watchMetricGoalPercent;

  /// No description provided for @watchMetricTurnCueDistance.
  ///
  /// In en, this message translates to:
  /// **'Next turn'**
  String get watchMetricTurnCueDistance;

  /// No description provided for @watchMetricRouteSimplifyDistance.
  ///
  /// In en, this message translates to:
  /// **'Course distance'**
  String get watchMetricRouteSimplifyDistance;

  /// No description provided for @watchMetricAutoEffortMatched.
  ///
  /// In en, this message translates to:
  /// **'Segments matched'**
  String get watchMetricAutoEffortMatched;

  /// No description provided for @watchMetricRouteElevTotal.
  ///
  /// In en, this message translates to:
  /// **'Route elevation'**
  String get watchMetricRouteElevTotal;

  /// No description provided for @watchMetricRaceDayDays.
  ///
  /// In en, this message translates to:
  /// **'Days to race'**
  String get watchMetricRaceDayDays;

  /// No description provided for @watchMetricSleepBudget.
  ///
  /// In en, this message translates to:
  /// **'Sleep budget'**
  String get watchMetricSleepBudget;

  /// No description provided for @watchMetricTimerRemaining.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get watchMetricTimerRemaining;

  /// No description provided for @watchMetricBackyardBell.
  ///
  /// In en, this message translates to:
  /// **'Bell countdown'**
  String get watchMetricBackyardBell;

  /// No description provided for @watchMetricStormDelta.
  ///
  /// In en, this message translates to:
  /// **'Storm trend'**
  String get watchMetricStormDelta;

  /// No description provided for @watchMetricGap.
  ///
  /// In en, this message translates to:
  /// **'Grade-adjusted pace'**
  String get watchMetricGap;

  /// No description provided for @watchMetricFluid.
  ///
  /// In en, this message translates to:
  /// **'Fluid'**
  String get watchMetricFluid;

  /// No description provided for @watchLiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow watch run'**
  String get watchLiveTitle;

  /// No description provided for @watchLiveTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Relay your custom watch\'s position to a live link'**
  String get watchLiveTileSubtitle;

  /// No description provided for @watchLiveIntro.
  ///
  /// In en, this message translates to:
  /// **'While this screen is open your phone relays the watch\'s position to spectators about once a second. Keep the phone with you and in Bluetooth range — leaving this screen ends the relay.'**
  String get watchLiveIntro;

  /// No description provided for @watchLiveStateOff.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get watchLiveStateOff;

  /// No description provided for @watchLiveStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get watchLiveStateConnecting;

  /// No description provided for @watchLiveStateLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get watchLiveStateLive;

  /// No description provided for @watchLiveStateGap.
  ///
  /// In en, this message translates to:
  /// **'Gap'**
  String get watchLiveStateGap;

  /// No description provided for @watchLiveStateLost.
  ///
  /// In en, this message translates to:
  /// **'Gave up'**
  String get watchLiveStateLost;

  /// No description provided for @watchLiveDetailOff.
  ///
  /// In en, this message translates to:
  /// **'Nothing is being sent.'**
  String get watchLiveDetailOff;

  /// No description provided for @watchLiveDetailSearching.
  ///
  /// In en, this message translates to:
  /// **'Looking for your watch…'**
  String get watchLiveDetailSearching;

  /// No description provided for @watchLiveDetailAwaitingFix.
  ///
  /// In en, this message translates to:
  /// **'Connected — waiting for the watch\'s first position.'**
  String get watchLiveDetailAwaitingFix;

  /// No description provided for @watchLiveDetailGap.
  ///
  /// In en, this message translates to:
  /// **'spectators see the last position as delayed, not current'**
  String get watchLiveDetailGap;

  /// No description provided for @watchLiveDetailLost.
  ///
  /// In en, this message translates to:
  /// **'Your watch is off or out of range. Nothing new is being sent.'**
  String get watchLiveDetailLost;

  /// No description provided for @watchLiveStart.
  ///
  /// In en, this message translates to:
  /// **'Start relay'**
  String get watchLiveStart;

  /// No description provided for @watchLiveStop.
  ///
  /// In en, this message translates to:
  /// **'Stop relay'**
  String get watchLiveStop;

  /// No description provided for @watchLiveRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get watchLiveRetry;

  /// No description provided for @watchLiveShare.
  ///
  /// In en, this message translates to:
  /// **'Share live link'**
  String get watchLiveShare;

  /// No description provided for @watchLiveStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the live broadcast — nothing is being shared.'**
  String get watchLiveStartFailed;

  /// No description provided for @watchLiveSyncAction.
  ///
  /// In en, this message translates to:
  /// **'Sync runs from watch'**
  String get watchLiveSyncAction;

  /// No description provided for @watchLiveSyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pulls recorded runs off the watch. The relay pauses while it runs.'**
  String get watchLiveSyncSubtitle;

  /// Pending-sync banner while offline or signed out
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} change saved on this device — will sync when online} other{{count} changes saved on this device — will sync when online}}'**
  String pendingSyncOffline(int count);

  /// Pending-sync banner when a push failed while online
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} change hasn\'t synced} other{{count} changes haven\'t synced}}'**
  String pendingSyncFailed(int count);

  /// Retry button on the pending-sync banner
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get pendingSyncRetry;

  /// Semantics label for a tappable photo thumbnail that opens the full-screen viewer; used when the photo has no caption of its own
  ///
  /// In en, this message translates to:
  /// **'Open photo'**
  String get photoOpen;

  /// Label for the full-screen photo viewer's close control
  ///
  /// In en, this message translates to:
  /// **'Close photo'**
  String get photoLightboxClose;

  /// Accessible label for the spinner shown while a full-size photo loads in the lightbox
  ///
  /// In en, this message translates to:
  /// **'Loading photo…'**
  String get photoLightboxLoading;

  /// Shown in the photo lightbox when the full-size image fails to load (expired signed URL, offline)
  ///
  /// In en, this message translates to:
  /// **'This photo couldn\'t be loaded.'**
  String get photoLightboxError;

  /// Hint under the photo lightbox error telling the user how to dismiss the viewer
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere to close.'**
  String get photoLightboxErrorHint;

  /// Generic screen-reader announcement for a surface that is still loading
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// Tooltip on an app-bar overflow menu button
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commonMore;

  /// Label of the undo bar action button that cancels the pending destructive action
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoAction;

  /// Tooltip on the undo bar close button, which commits the pending destructive action now
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get undoDismiss;

  /// Screen-reader-only sentence appended to the undo bar announcement
  ///
  /// In en, this message translates to:
  /// **'Undo is available for a short time.'**
  String get undoHint;

  /// Banner shown after the user taps Undo and the row is back
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get undoRestored;

  /// Preferences row label for how long a destructive action stays reversible
  ///
  /// In en, this message translates to:
  /// **'Undo window'**
  String get prefsUndoWindow;

  /// Undo window choice: eight seconds (the default)
  ///
  /// In en, this message translates to:
  /// **'8 seconds'**
  String get prefsUndoWindow8s;

  /// Undo window choice: thirty seconds
  ///
  /// In en, this message translates to:
  /// **'30 seconds'**
  String get prefsUndoWindow30s;

  /// Undo window choice: no time limit, the offer waits for an explicit dismiss
  ///
  /// In en, this message translates to:
  /// **'Until I dismiss it'**
  String get prefsUndoWindowManual;

  /// Undo bar sentence after dismissing one or more notifications
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Notification dismissed} other{{count} notifications dismissed}}'**
  String undoDismissed(int count);

  /// Undo bar sentence after removing a route condition report
  ///
  /// In en, this message translates to:
  /// **'Condition report removed'**
  String get routeConditionsRemoved;

  /// Undo bar sentence after removing a gear wear-log observation
  ///
  /// In en, this message translates to:
  /// **'Observation removed'**
  String get gearWearLogRemoved;

  /// Undo bar sentence after removing a logged food entry
  ///
  /// In en, this message translates to:
  /// **'{item} removed'**
  String nutritionEntryRemoved(String item);

  /// Undo bar sentence after removing a run comment or reply
  ///
  /// In en, this message translates to:
  /// **'Comment removed'**
  String get runSocialCommentRemoved;

  /// Undo bar sentence after removing the viewer's own route review
  ///
  /// In en, this message translates to:
  /// **'Review removed'**
  String get routeDetailReviewRemoved;

  /// Undo bar sentence after removing a course marker
  ///
  /// In en, this message translates to:
  /// **'Marker removed'**
  String get routeMarkerRemoved;

  /// Reason shown beside the disabled crew-sheet button when the route has fewer than two points
  ///
  /// In en, this message translates to:
  /// **'Add at least two points to this route to build a roadbook.'**
  String get roadbookNeedsRouteLine;

  /// Reason on the disabled Gear tile when no gear store is wired on this mount
  ///
  /// In en, this message translates to:
  /// **'Gear isn\'t available on this build'**
  String get settingsGearUnavailable;

  /// Dashboard load-ramp card title
  ///
  /// In en, this message translates to:
  /// **'Training load ramp'**
  String get loadRampTitle;

  /// Caption under the acute:chronic ratio figure
  ///
  /// In en, this message translates to:
  /// **'this week vs your 4-week average'**
  String get loadRampRatioCaption;

  /// Label for the last-7-days distance figure
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get loadRampAcuteLabel;

  /// Label for the four-week weekly-average distance figure
  ///
  /// In en, this message translates to:
  /// **'4-week weekly average'**
  String get loadRampChronicLabel;

  /// Injury-risk band chip: low
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get loadRampBandLow;

  /// Injury-risk band chip: optimal
  ///
  /// In en, this message translates to:
  /// **'Optimal'**
  String get loadRampBandOptimal;

  /// Injury-risk band chip: elevated
  ///
  /// In en, this message translates to:
  /// **'Elevated'**
  String get loadRampBandElevated;

  /// Injury-risk band chip: high
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get loadRampBandHigh;

  /// What a low band means for the runner
  ///
  /// In en, this message translates to:
  /// **'You\'re running below your recent base. Fine for a taper or a recovery week; sustained, it\'s detraining.'**
  String get loadRampMeaningLow;

  /// What an optimal band means for the runner
  ///
  /// In en, this message translates to:
  /// **'Your week sits in the range that best protects against injury. Keep building at this rate.'**
  String get loadRampMeaningOptimal;

  /// What an elevated band means for the runner
  ///
  /// In en, this message translates to:
  /// **'You\'ve stepped up faster than your recent base supports. Hold this week steady rather than adding more.'**
  String get loadRampMeaningElevated;

  /// What a high band means for the runner
  ///
  /// In en, this message translates to:
  /// **'This is a sharp spike over your recent base — the pattern most associated with injury. Consider an easier week.'**
  String get loadRampMeaningHigh;

  /// Load-trend footnote: ramping
  ///
  /// In en, this message translates to:
  /// **'Your load is ramping up.'**
  String get loadRampTrendRamping;

  /// Load-trend footnote: steady
  ///
  /// In en, this message translates to:
  /// **'Your load is holding steady.'**
  String get loadRampTrendSteady;

  /// Load-trend footnote: tapering
  ///
  /// In en, this message translates to:
  /// **'Your load is tapering off.'**
  String get loadRampTrendTapering;

  /// Dashboard comeback card title
  ///
  /// In en, this message translates to:
  /// **'Coming back from a break'**
  String get comebackTitle;

  /// Comeback verdict chip: easing in
  ///
  /// In en, this message translates to:
  /// **'Easing in'**
  String get comebackVerdictEasingIn;

  /// Comeback verdict chip: big first week
  ///
  /// In en, this message translates to:
  /// **'Big first week'**
  String get comebackVerdictSteep;

  /// How long the runner was away, in whole weeks
  ///
  /// In en, this message translates to:
  /// **'{weeks} weeks without a run'**
  String comebackLayoff(int weeks);

  /// Caption under the share-of-pre-break-base figure
  ///
  /// In en, this message translates to:
  /// **'this week vs your average week before the break'**
  String get comebackShareCaption;

  /// What an easing-in comeback means for the runner
  ///
  /// In en, this message translates to:
  /// **'This week sits comfortably under the weeks you were running before the break. Building back gradually from here is what makes the comeback stick.'**
  String get comebackMeaningEasingIn;

  /// What a steep first week back means for the runner
  ///
  /// In en, this message translates to:
  /// **'This week is already more than half of what you were running before the break. Your body has lost the base that made those weeks routine, so a shorter week now costs far less than a setback later.'**
  String get comebackMeaningSteep;

  /// Label for the last-7-days distance figure
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get comebackThisWeekLabel;

  /// Label for the pre-break weekly-average distance figure
  ///
  /// In en, this message translates to:
  /// **'Weekly average before the break'**
  String get comebackBaseLabel;

  /// Note that the load-ramp card returns once the runner is consistent again
  ///
  /// In en, this message translates to:
  /// **'Your training load ramp comes back once you have a few consistent weeks again.'**
  String get comebackFootnote;

  /// Screen title for the famous-segment catalogue browse list
  ///
  /// In en, this message translates to:
  /// **'Famous segments'**
  String get segmentCatalogueTitle;

  /// Intro line under the catalogue title
  ///
  /// In en, this message translates to:
  /// **'Curated climbs, bridges and park loops from around the world. Run one and your time lands on its leaderboard automatically.'**
  String get segmentCatalogueIntro;

  /// Label for the catalogue search field
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get segmentCatalogueSearchLabel;

  /// Hint text in the catalogue search field
  ///
  /// In en, this message translates to:
  /// **'Name or place'**
  String get segmentCatalogueSearchHint;

  /// Label for the catalogue region filter
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get segmentCatalogueRegion;

  /// Catalogue region filter option that clears the filter
  ///
  /// In en, this message translates to:
  /// **'All regions'**
  String get segmentCatalogueAllRegions;

  /// Label for the catalogue surface filter
  ///
  /// In en, this message translates to:
  /// **'Surface'**
  String get segmentCatalogueSurface;

  /// Catalogue surface filter option that clears the filter
  ///
  /// In en, this message translates to:
  /// **'All surfaces'**
  String get segmentCatalogueAllSurfaces;

  /// Label for the catalogue sort selector
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get segmentCatalogueSort;

  /// Catalogue sort option — alphabetical by name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get segmentCatalogueSortName;

  /// Catalogue sort option — shortest segment first
  ///
  /// In en, this message translates to:
  /// **'Shortest first'**
  String get segmentCatalogueSortShortest;

  /// Catalogue sort option — longest segment first
  ///
  /// In en, this message translates to:
  /// **'Longest first'**
  String get segmentCatalogueSortLongest;

  /// Catalogue sort option — most elevation gain first
  ///
  /// In en, this message translates to:
  /// **'Most climb'**
  String get segmentCatalogueSortClimb;

  /// Count of segments currently shown by the catalogue filters
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} segment} other{{count} segments}}'**
  String segmentCatalogueCount(int count);

  /// Error state when the catalogue fetch fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load the segment catalogue.'**
  String get segmentCatalogueLoadFailed;

  /// Empty state when the catalogue itself holds no segments
  ///
  /// In en, this message translates to:
  /// **'No famous segments in the catalogue yet.'**
  String get segmentCatalogueEmpty;

  /// Empty state when the active filters match no segment
  ///
  /// In en, this message translates to:
  /// **'No segments match these filters — try widening them.'**
  String get segmentCatalogueNoMatches;

  /// Link from a run’s catalogue efforts to the whole catalogue
  ///
  /// In en, this message translates to:
  /// **'Browse all'**
  String get segmentCatalogueBrowseAll;

  /// Title when a catalogue segment id resolves to nothing
  ///
  /// In en, this message translates to:
  /// **'Segment not found'**
  String get segmentCatalogueNotFoundTitle;

  /// Body when a catalogue segment id resolves to nothing
  ///
  /// In en, this message translates to:
  /// **'This segment isn’t in the catalogue, or has been retired.'**
  String get segmentCatalogueNotFoundBody;

  /// Title when the catalogue segment detail fetch fails
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this segment'**
  String get segmentCatalogueDetailFailedTitle;

  /// Body when the catalogue segment detail fetch fails
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get segmentCatalogueDetailFailedBody;

  /// Stat label for a catalogue segment’s distance
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get segmentCatalogueStatDistance;

  /// Stat label for a catalogue segment’s elevation gain
  ///
  /// In en, this message translates to:
  /// **'Elevation gain'**
  String get segmentCatalogueStatElevation;

  /// Stat label for a catalogue segment’s surface
  ///
  /// In en, this message translates to:
  /// **'Surface'**
  String get segmentCatalogueStatSurface;

  /// Section header for a catalogue segment’s leaderboard
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get segmentCatalogueLeaderboard;

  /// Run-surface peer strip entry for the famous-segment catalogue
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get runSurfaceTabSegments;

  /// Rate-limit refusal when the create_club bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re creating clubs too quickly — please wait {wait} and try again.'**
  String rateLimitCreateClub(String wait);

  /// Rate-limit refusal when the create_route bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re creating routes too quickly — please wait {wait} and try again.'**
  String rateLimitCreateRoute(String wait);

  /// Rate-limit refusal when the create_report bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re filing reports too quickly — please wait {wait} and try again.'**
  String rateLimitCreateReport(String wait);

  /// Rate-limit refusal when the create_challenge bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re creating challenges too quickly — please wait {wait} and try again.'**
  String rateLimitCreateChallenge(String wait);

  /// Rate-limit refusal when a training-plan adopt bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re adopting plans too quickly — please wait {wait} and try again.'**
  String rateLimitAdoptPlan(String wait);

  /// Rate-limit refusal when the clone_session_template bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re adopting session plans too quickly — please wait {wait} and try again.'**
  String rateLimitAdoptSessionPlan(String wait);

  /// Rate-limit refusal when the clone_gym_routine_template bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re adopting gym routines too quickly — please wait {wait} and try again.'**
  String rateLimitAdoptGymRoutine(String wait);

  /// Rate-limit refusal when the publish_gym_routine_as_template bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re publishing routines too quickly — please wait {wait} and try again.'**
  String rateLimitPublishRoutine(String wait);

  /// Rate-limit refusal when either direct-message send bucket is spent
  ///
  /// In en, this message translates to:
  /// **'You\'re sending messages too quickly — please wait {wait} and try again.'**
  String rateLimitSendMessage(String wait);

  /// Rate-limit refusal for a bucket this build does not recognise
  ///
  /// In en, this message translates to:
  /// **'You\'re doing that too quickly — please wait {wait} and try again.'**
  String rateLimitGeneric(String wait);

  /// The wait a rate-limit refusal slots in, in seconds
  ///
  /// In en, this message translates to:
  /// **'{n, plural, one{1 second} other{{n} seconds}}'**
  String rateLimitWaitSeconds(int n);

  /// The wait a rate-limit refusal slots in, in whole minutes
  ///
  /// In en, this message translates to:
  /// **'{n, plural, one{1 minute} other{{n} minutes}}'**
  String rateLimitWaitMinutes(int n);

  /// The wait a rate-limit refusal slots in when the trigger reported no positive figure
  ///
  /// In en, this message translates to:
  /// **'a few seconds'**
  String get rateLimitWaitSoon;

  /// Label on the create-challenge FAB, the form's app-bar title and its submit button
  ///
  /// In en, this message translates to:
  /// **'Create challenge'**
  String get challengesCreate;

  /// Title field on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get challengesTitleLabel;

  /// Description field on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get challengesDescriptionLabel;

  /// Metric chip group on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get challengesMetricLabel;

  /// Scope chip group on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get challengesScopeLabel;

  /// Optional goal field on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Goal (optional)'**
  String get challengesGoalOptional;

  /// Activity-type picker on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get challengesActivityTypeLabel;

  /// The no-filter option in the create-challenge activity-type picker
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get challengesActivityAny;

  /// Club-anchor picker on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Club'**
  String get challengesClubLabel;

  /// The unanchored option in the create-challenge club picker
  ///
  /// In en, this message translates to:
  /// **'Open (anyone)'**
  String get challengesClubNone;

  /// Window-start row on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get challengesStartLabel;

  /// Window-end row on the create-challenge form
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get challengesEndLabel;

  /// The individual challenge scope
  ///
  /// In en, this message translates to:
  /// **'Individual'**
  String get challengesScopeIndividual;

  /// The club-vs-club challenge scope
  ///
  /// In en, this message translates to:
  /// **'Club vs club'**
  String get challengesScopeClubVsClub;

  /// The group-goal challenge scope
  ///
  /// In en, this message translates to:
  /// **'Group goal'**
  String get challengesScopeGroupGoal;

  /// Unit suffix on the goal field of a time-metric challenge (hours)
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get challengesSuffixHours;

  /// Unit suffix on the goal field of an activity-count challenge
  ///
  /// In en, this message translates to:
  /// **'activities'**
  String get challengesSuffixActivities;

  /// Unit suffix on the goal field of an active-days challenge
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get challengesSuffixDays;

  /// Readback under the create-challenge goal field showing the converted goal as entrants will see it
  ///
  /// In en, this message translates to:
  /// **'Entrants see {value}'**
  String challengesGoalPreview(String value);

  /// The most active days a challenge window can hold — shown as a hint under the goal field and as the inline error when the goal exceeds it
  ///
  /// In en, this message translates to:
  /// **'At most {n} active days fit in this window.'**
  String challengesGoalStreakCeiling(int n);

  /// Inline error when the create-challenge title is empty
  ///
  /// In en, this message translates to:
  /// **'Give the challenge a title.'**
  String get challengesErrTitle;

  /// Inline error when the create-challenge goal is not a positive number
  ///
  /// In en, this message translates to:
  /// **'Goal: enter a positive number'**
  String get challengesErrGoal;

  /// Inline error when the create-challenge window ends at or before it starts
  ///
  /// In en, this message translates to:
  /// **'The end must be after the start.'**
  String get challengesErrWindow;

  /// Inline error when a typed body weight is outside the range its column accepts
  ///
  /// In en, this message translates to:
  /// **'Enter a weight between {min} and {max} {unit}.'**
  String limitsWeightOutOfRange(String min, String max, String unit);

  /// Inline error when a typed height is outside the range its column accepts
  ///
  /// In en, this message translates to:
  /// **'Enter a height between {min} and {max} cm.'**
  String limitsHeightOutOfRange(String min, String max);

  /// Inline error when a typed serving count is outside the range its column accepts
  ///
  /// In en, this message translates to:
  /// **'Enter a number of servings between {min} and {max}.'**
  String limitsServingsOutOfRange(String min, String max);

  /// Run-detail chip naming the guided-run script a run was recorded under
  ///
  /// In en, this message translates to:
  /// **'Guided run: {title}'**
  String runDetailGuidedRun(String title);

  /// Run-detail readout when the stored guided_run_id names a workout this build no longer ships
  ///
  /// In en, this message translates to:
  /// **'Guided run no longer in the library'**
  String get runDetailGuidedRunUnavailable;

  /// Action on the guided-run detail screen that arms the script on the recorder
  ///
  /// In en, this message translates to:
  /// **'Use this run'**
  String get guidedRunUseThisRun;
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
