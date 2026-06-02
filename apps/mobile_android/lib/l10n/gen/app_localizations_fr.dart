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

  @override
  String get runStart => 'DÉMARRER';

  @override
  String get runStartA11yLabel => 'Démarrer la course';

  @override
  String get runChooseRoute => 'Choisir un parcours';

  @override
  String get runChangeRoute => 'Changer de parcours';

  @override
  String get runShareLiveLink => 'Partager le lien en direct';

  @override
  String get runTrainingPlans => 'Plans d\'entraînement';

  @override
  String get runTapToCancel => 'Touchez pour annuler';

  @override
  String get runFirstRunPrompt =>
      'Votre première course n\'est qu\'à un toucher.';

  @override
  String get runLastActivity => 'Dernière activité';

  @override
  String get runLastRun => 'Dernière course';

  @override
  String get runFollowing => 'SUIVI';

  @override
  String get runRaceFallbackTitle => 'Course';

  @override
  String get runRaceArmed => 'Course armée';

  @override
  String get runRaceLive => 'Course EN DIRECT';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — en attente du départ';
  }

  @override
  String runRaceElapsedTapStart(String label, String elapsed) {
    return '$label — $elapsed écoulées · touchez Démarrer';
  }

  @override
  String get runComplete => 'Course terminée';

  @override
  String get runStatDistance => 'Distance';

  @override
  String get runStatTime => 'Temps';

  @override
  String get runStatMoving => 'En mouvement';

  @override
  String get runStatPace => 'Allure';

  @override
  String get runStatSpeed => 'Vitesse';

  @override
  String get runStatAvgPace => 'Allure moy.';

  @override
  String get runStatAvgSpeed => 'Vitesse moy.';

  @override
  String get runStatCalories => 'Calories';

  @override
  String get runStatElevation => 'Dénivelé';

  @override
  String get runStatSteps => 'Pas';

  @override
  String get runStatCadence => 'Cadence';

  @override
  String get runStatHeartRate => 'Fréq. cardiaque';

  @override
  String get runUnitKcal => 'kcal';

  @override
  String get runUnitMetres => 'm';

  @override
  String get runUnitSpm => 'ppm';

  @override
  String get runUnitBpm => 'bpm';

  @override
  String get runMutePaceCues => 'Couper les indications d\'allure';

  @override
  String get runPaceCuesMuted => 'Indications d\'allure coupées';

  @override
  String get runSynced => 'Synchronisé';

  @override
  String get runSyncing => 'Synchronisation…';

  @override
  String get runDone => 'Terminé';

  @override
  String get runDiscardA11yLabel => 'Abandonner la course';

  @override
  String get runDiscardA11yHint =>
      'Supprime l\'enregistrement en cours sans l\'enregistrer';

  @override
  String get runResumeA11yLabel => 'Reprendre la course';

  @override
  String get runPauseA11yLabel => 'Mettre en pause';

  @override
  String get runResumeA11yHint => 'Reprend l\'enregistrement en pause';

  @override
  String get runPauseA11yHint =>
      'Met l\'enregistrement en pause sans le terminer';

  @override
  String get runMarkLapA11yLabel => 'Marquer un tour';

  @override
  String runMarkLapWithCountA11yLabel(int count) {
    return 'Marquer un tour, $count jusqu\'ici';
  }

  @override
  String get runMarkLapA11yHint => 'Enregistre le temps intermédiaire actuel';

  @override
  String get runCollapseStatsPanel => 'Réduire le panneau de stats';

  @override
  String get runExpandStatsPanel => 'Agrandir le panneau de stats';

  @override
  String runRouteRemaining(String distance) {
    return '$distance restant';
  }

  @override
  String runOffRoute(int metres) {
    return 'Hors parcours — à $metres m';
  }

  @override
  String get runPermissionRevoked => 'Autorisation de localisation révoquée';

  @override
  String get runGpsLost => 'Signal GPS perdu — sortez à découvert';

  @override
  String get runWeakGps => 'GPS faible — distance en pause';

  @override
  String get runA11yStarted => 'Course démarrée';

  @override
  String get runA11yResumed => 'Course reprise';

  @override
  String get runA11yPaused => 'Course en pause';

  @override
  String get runA11yFinished => 'Course terminée';

  @override
  String runLapMarked(int count) {
    return 'Tour $count marqué';
  }

  @override
  String get runDiscardDialogTitle => 'Abandonner la course ?';

  @override
  String get runDiscardDialogBody => 'Votre progression sera perdue.';

  @override
  String get runKeepRunning => 'Continuer à courir';

  @override
  String get runDiscard => 'Abandonner';

  @override
  String get runStartWorkout => 'Démarrer la séance';

  @override
  String get runStartWorkoutSubtitle =>
      'Courez avec des objectifs d\'étape en direct, des indications audio et un bilan prévu/réalisé.';

  @override
  String get runViewWorkoutDetails => 'Voir les détails';

  @override
  String get runWorkoutNoStructure =>
      'Cette séance n\'a aucune structure exécutable.';

  @override
  String runWorkoutLoaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count étapes',
      one: '$count étape',
    );
    return 'Séance chargée · $_temp0 — touchez GO pour démarrer';
  }

  @override
  String get runAbandonWorkoutTitle => 'Abandonner la séance ?';

  @override
  String get runAbandonWorkoutBody =>
      'Le plan structuré s\'arrête ici ; l\'enregistrement continue en course libre. Vous pouvez arrêter à tout moment pour enregistrer ce que vous avez fait.';

  @override
  String get runCancel => 'Annuler';

  @override
  String get runAbandon => 'Abandonner';

  @override
  String get runNoRoutesSaved =>
      'Aucun parcours enregistré. Importez-en un depuis l\'onglet Parcours.';

  @override
  String get runNotificationsOffHint =>
      'Les notifications sont désactivées — la notification de course en direct ne s\'affichera pas. L\'enregistrement fonctionne quand même.';

  @override
  String get runSettings => 'Réglages';

  @override
  String get runStartAnyway => 'Démarrer quand même';

  @override
  String get runOpenSettings => 'Ouvrir les réglages';

  @override
  String get runNotNow => 'Pas maintenant';

  @override
  String get runShareSubject => 'Suis-moi en direct';

  @override
  String runCouldNotShareLink(String error) {
    return 'Impossible de partager le lien en direct : $error';
  }

  @override
  String get runHrStrapLostReconnecting =>
      'Ceinture cardio perdue — reconnexion…';

  @override
  String get runHrStrapReconnected => 'Ceinture cardio reconnectée';

  @override
  String get runHrStrapLostNoHr =>
      'Ceinture cardio perdue — l\'enregistrement continue sans FC.';

  @override
  String get runHrStrapNotFound =>
      'Ceinture cardio introuvable — mettez-la, puis reconnectez.';

  @override
  String get runReconnect => 'Reconnecter';

  @override
  String get runHrStrapStillNotFound =>
      'Toujours pas de ceinture — l\'enregistrement continue sans FC.';

  @override
  String get runSaveFailedRelaunch =>
      'Impossible d\'enregistrer localement. Relancez l\'app pour récupérer.';

  @override
  String get runSyncFailedSaveOffline =>
      'Enregistré hors ligne. Synchronisez depuis Courses.';

  @override
  String get runSavedOffline => 'Enregistré hors ligne.';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings =>
      'Pas de GPS — le suivi démarrera quand la localisation sera activée.';

  @override
  String get runGpsBlockedSettings =>
      'Pas de GPS — autorisation bloquée. Activez-la pour suivre le parcours.';

  @override
  String get runGpsPermissionPending =>
      'Pas de GPS — le suivi démarrera quand l\'autorisation sera accordée.';

  @override
  String get runGpsAllowAllTheTime =>
      'Réglez la localisation sur « Toujours autoriser » — les courses arrêtent d\'enregistrer quand vous changez d\'app sans autorisation en arrière-plan.';

  @override
  String get runGpsSensorFailed =>
      'Enregistrement sans GPS — impossible de démarrer le capteur.';

  @override
  String get runAgoJustNow => 'À l\'instant';

  @override
  String runAgoMinutes(int count) {
    return 'il y a $count min';
  }

  @override
  String runAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count heures',
      one: 'il y a 1 heure',
    );
    return '$_temp0';
  }

  @override
  String get runAgoYesterday => 'Hier';

  @override
  String runAgoDays(int count) {
    return 'il y a $count jours';
  }

  @override
  String runAgoWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count semaines',
      one: 'il y a 1 semaine',
    );
    return '$_temp0';
  }

  @override
  String runAgoMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count mois',
      one: 'il y a 1 mois',
    );
    return '$_temp0';
  }

  @override
  String get runWorkoutAbandonedBand => 'Séance abandonnée · course libre';

  @override
  String get runWorkoutCompleteBand =>
      'Séance terminée · touchez stop pour enregistrer';

  @override
  String runWorkoutStepHeader(String label, String target, String pace) {
    return '$label · $target @ $pace';
  }

  @override
  String runWorkoutStepCounter(int current, int total) {
    return '$current/$total';
  }

  @override
  String get runWorkoutRewind => 'Reculer';

  @override
  String get runWorkoutSkip => 'Passer';

  @override
  String get runWorkoutAbandon => 'Abandonner';

  @override
  String runWorkoutRemainingYards(int yards) {
    return '$yards yd restants';
  }

  @override
  String runWorkoutRemainingMetres(int metres) {
    return '$metres m restants';
  }

  @override
  String runWorkoutRemainingDuration(String duration) {
    return '$duration restant';
  }
}
