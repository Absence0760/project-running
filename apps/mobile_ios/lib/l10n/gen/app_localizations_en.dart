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
}
