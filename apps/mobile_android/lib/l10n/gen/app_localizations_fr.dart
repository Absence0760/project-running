// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get prefsLanguage => 'Langue';

  @override
  String get prefsLanguageSystem => 'Paramètre système';

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
  String get navHome => 'Accueil';

  @override
  String get navRun => 'Courir';

  @override
  String get navHistory => 'Historique';

  @override
  String get navSocial => 'Social';

  @override
  String get navSettings => 'Réglages';

  @override
  String get settingsSectionProfile => 'Profil';

  @override
  String get settingsSectionAppsData => 'Apps et données';

  @override
  String get settingsSectionAccountLegal => 'Compte et mentions légales';

  @override
  String get prefsSectionUnitsDisplay => 'Unités et affichage';

  @override
  String get authEmailLabel => 'E-mail';

  @override
  String get authPasswordLabel => 'Mot de passe';

  @override
  String get authOrDivider => 'OU';

  @override
  String get signInTitle => 'Se connecter';

  @override
  String get signInHeadline =>
      'Synchronisez vos courses sur tous vos appareils';

  @override
  String get signInSubtitle =>
      'Connectez-vous pour sauvegarder vos courses et les consulter dans l\'app web.';

  @override
  String get signInButton => 'Se connecter';

  @override
  String get signInForgotPassword => 'Mot de passe oublié ?';

  @override
  String get signInResetNeedEmail =>
      'Saisissez d\'abord votre e-mail ci-dessus, puis appuyez sur Mot de passe oublié.';

  @override
  String get signInResetSent =>
      'Si cet e-mail est enregistré, nous avons envoyé un lien de réinitialisation.';

  @override
  String get signInWithApple => 'Se connecter avec Apple';

  @override
  String get signInWithGoogle => 'Se connecter avec Google';

  @override
  String get signInContinueOffline => 'Continuer hors ligne';

  @override
  String get signInCreateAccountPrompt => 'Pas encore de compte ? Créez-en un';

  @override
  String get signUpTitle => 'Créer un compte';

  @override
  String get signUpHeadline => 'Commencez à suivre vos courses';

  @override
  String get signUpSubtitle =>
      'Créez un compte pour sauvegarder vos courses et les consulter dans l\'app web.';

  @override
  String get signUpButton => 'Créer un compte';

  @override
  String get signUpConfirmAge => 'J\'ai 16 ans ou plus';

  @override
  String get signUpAcceptPrefix => 'J\'accepte les ';

  @override
  String get signUpTermsLink => 'Conditions d\'utilisation';

  @override
  String get signUpAcceptConjunction => ' et la ';

  @override
  String get signUpPrivacyLink => 'Politique de confidentialité';

  @override
  String get signUpErrorConfirmAge =>
      'Veuillez confirmer que vous avez 16 ans ou plus pour continuer.';

  @override
  String get signUpErrorAcceptTerms =>
      'Veuillez accepter les Conditions d\'utilisation et la Politique de confidentialité pour continuer.';

  @override
  String get signUpContinueWithApple => 'Continuer avec Apple';

  @override
  String get signUpContinueWithGoogle => 'Continuer avec Google';

  @override
  String get signUpSignInPrompt => 'Vous avez déjà un compte ? Connectez-vous';

  @override
  String signUpCouldNotOpen(String url) {
    return 'Impossible d\'ouvrir $url';
  }

  @override
  String get onboardingTrackTitle => 'Suivez chaque course';

  @override
  String get onboardingTrackBody =>
      'Enregistrement GPS avec carte en direct, splits, allure, cadence et dénivelé. Fonctionne entièrement hors ligne — connectez-vous plus tard pour synchroniser sur tous vos appareils.';

  @override
  String get onboardingRoutesTitle => 'Suivez des itinéraires';

  @override
  String get onboardingRoutesBody =>
      'Importez des fichiers GPX ou KML, ou synchronisez des itinéraires depuis l\'app web. Recevez des alertes de déviation pendant votre course.';

  @override
  String get onboardingLocationTitle => 'Accès à la localisation';

  @override
  String get onboardingLocationBody =>
      'Threkir enregistre vos courses en échantillonnant votre position GPS lorsque l\'app est au premier plan ET en arrière-plan (afin de continuer le suivi lorsque votre écran est éteint ou que vous changez d\'app pour prendre une photo). Les données de localisation sont stockées sur votre appareil et ne sont transmises aux serveurs de Threkir que lorsque vous choisissez de partager ou de synchroniser une course. Si vous refusez la localisation en arrière-plan, l\'enregistrement s\'arrêtera dès que vous quitterez l\'app — vous pourrez modifier cela plus tard dans Réglages → Apps → Threkir → Autorisations.';

  @override
  String get onboardingPrivacyTitle => 'Qui voit vos courses ?';

  @override
  String get onboardingPrivacyBody =>
      'Choisissez un réglage par défaut pour les nouvelles courses. Vous pouvez le modifier à tout moment dans les Réglages et le remplacer pour n\'importe quelle course.';

  @override
  String get onboardingGrantPermission => 'Accorder l\'autorisation';

  @override
  String get onboardingNext => 'Suivant';

  @override
  String get privacyPrivateTitle => 'Privé';

  @override
  String get privacyPrivateSubtitle =>
      'Vous seul pouvez voir vos courses. Vous pourrez partager n\'importe quelle course plus tard.';

  @override
  String get privacyFollowersTitle => 'Abonnés';

  @override
  String get privacyFollowersSubtitle =>
      'Les personnes qui vous suivent voient vos nouvelles courses dans leur fil.';

  @override
  String get privacyPublicTitle => 'Public';

  @override
  String get privacyPublicSubtitle =>
      'Tout le monde peut trouver et consulter vos courses.';
}
