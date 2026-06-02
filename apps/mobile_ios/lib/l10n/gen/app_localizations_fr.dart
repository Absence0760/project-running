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

  @override
  String get runsRangeToday => 'Aujourd\'hui';

  @override
  String get runsRangeWeek => 'Cette semaine';

  @override
  String get runsRangeMonth => '30 derniers jours';

  @override
  String get runsRangeYear => 'Cette année';

  @override
  String get runsRangeAll => 'Tout l\'historique';

  @override
  String get runsRangeCustom => 'Personnalisé…';

  @override
  String runsRangeFrom(String date) {
    return 'À partir du $date';
  }

  @override
  String runsRangeUntil(String date) {
    return 'Jusqu\'au $date';
  }

  @override
  String runsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses',
      one: '$count course',
    );
    return '$_temp0';
  }

  @override
  String get runsDateRangeTooltip => 'Plage de dates';

  @override
  String get runsSortTooltip => 'Trier';

  @override
  String get runsSortNewest => 'Plus récentes d\'abord';

  @override
  String get runsSortOldest => 'Plus anciennes d\'abord';

  @override
  String get runsSortLongest => 'Distance la plus longue';

  @override
  String get runsSortFastest => 'Meilleure allure';

  @override
  String runsSyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synchroniser $count courses',
      one: 'Synchroniser $count course',
    );
    return '$_temp0';
  }

  @override
  String get runsRefreshTooltip => 'Actualiser depuis le cloud';

  @override
  String get runsOfflineTooltip => 'Hors ligne';

  @override
  String runsSelectionTitle(int count) {
    return '$count sélectionnée(s)';
  }

  @override
  String get runsSelectAllTooltip => 'Tout sélectionner';

  @override
  String get runsClearSelectionTooltip => 'Effacer';

  @override
  String get runsDeleteTooltip => 'Supprimer';

  @override
  String get runsCancelTooltip => 'Annuler';

  @override
  String get runsAddRun => 'Ajouter une course';

  @override
  String get runsAddRunTooltip => 'Ajouter une course manuellement';

  @override
  String runsLoadMore(int count) {
    return 'Charger $count de plus';
  }

  @override
  String get runsNoMatch => 'Aucune course ne correspond à ces filtres';

  @override
  String get runsClearFilters => 'Effacer les filtres';

  @override
  String get runsEmptyTitle => 'Aucune course pour l\'instant';

  @override
  String get runsEmptyBody =>
      'Touchez l\'onglet Course pour démarrer votre première course';

  @override
  String get runsFilterAll => 'Toutes';

  @override
  String get runsSourceAll => 'Toutes les sources';

  @override
  String runsSourceLabel(String source) {
    return 'Source : $source';
  }

  @override
  String get runsSourceFilterTooltip => 'Filtrer par source';

  @override
  String get runsSourceRecorded => 'Enregistrée';

  @override
  String get runsSourceWatch => 'Montre';

  @override
  String get runsSourceStrava => 'Strava';

  @override
  String get runsSourceParkrun => 'parkrun';

  @override
  String get runsSourceHealthKit => 'HealthKit';

  @override
  String get runsSourceHealthConnect => 'Health Connect';

  @override
  String get runsRangePickerTitle => 'Sélectionner les dates';

  @override
  String get runsRangeStart => 'Début';

  @override
  String get runsRangeEnd => 'Fin';

  @override
  String get runsRangeTapDate => 'Touchez une date';

  @override
  String get runsRangeApply => 'Appliquer';

  @override
  String get runsRangeClear => 'Effacer';

  @override
  String get runsPrevMonth => 'Mois précédent';

  @override
  String get runsNextMonth => 'Mois suivant';

  @override
  String get runsPrevYear => 'Année précédente';

  @override
  String get runsNextYear => 'Année suivante';

  @override
  String runsDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count courses ?',
      one: 'Supprimer $count course ?',
    );
    return '$_temp0';
  }

  @override
  String get runsDeleteConfirmBody => 'Cette action est irréversible.';

  @override
  String get runsCancel => 'Annuler';

  @override
  String get runsDelete => 'Supprimer';

  @override
  String get runsQueuedToSync => 'En attente de synchronisation';

  @override
  String get runsSignInToSync =>
      'Connectez-vous depuis les réglages pour synchroniser les courses';

  @override
  String get runsRefreshFailed =>
      'Impossible d\'actualiser — vérifiez votre connexion';

  @override
  String get runsLoadMoreFailed => 'Impossible de charger plus de courses';

  @override
  String runsSyncPartial(int synced, int total, String error) {
    return '$synced/$total synchronisées. Erreur : $error';
  }

  @override
  String runsSyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count courses n\'ont pas pu téléverser leur trace GPS — le reste a été synchronisé. Les courses en échec feront l\'objet d\'une nouvelle tentative au prochain cycle.',
      one:
          '$count course n\'a pas pu téléverser sa trace GPS — le reste a été synchronisé. Une nouvelle tentative aura lieu au prochain cycle.',
    );
    return '$_temp0';
  }

  @override
  String runsSyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Les $count courses synchronisées',
      one: '$count course synchronisée',
    );
    return '$_temp0';
  }

  @override
  String runsDeletePartial(int deleted, int queued) {
    return '$deleted supprimée(s) ; $queued en attente — nouvelle tentative une fois en ligne.';
  }

  @override
  String runsDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses supprimées',
      one: '$count course supprimée',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'Ajouter une course';

  @override
  String get addRunSave => 'Enregistrer';

  @override
  String get addRunSectionWhen => 'Quand';

  @override
  String get addRunSectionActivity => 'Activité';

  @override
  String get addRunSectionRoute => 'Itinéraire (facultatif)';

  @override
  String get addRunSectionDistance => 'Distance';

  @override
  String get addRunSectionDuration => 'Durée';

  @override
  String get addRunSectionTitle => 'Titre (facultatif)';

  @override
  String get addRunSectionNotes => 'Notes (facultatif)';

  @override
  String get addRunClearRoute => 'Effacer l\'itinéraire';

  @override
  String get addRunSearchRoutes => 'Rechercher des itinéraires enregistrés';

  @override
  String get addRunNoRoutes =>
      'Aucun itinéraire enregistré — créez-en ou importez-en un pour l\'associer ici';

  @override
  String get addRunDistanceInvalid => 'Saisissez une distance supérieure à 0';

  @override
  String get addRunDurationInvalid => 'Saisissez une durée';

  @override
  String get addRunTitleHint => 'ex. Boucle du midi';

  @override
  String get addRunNotesHint => 'Comment c\'était ?';

  @override
  String get addRunSaveButton => 'Enregistrer la course';

  @override
  String addRunSaveFailed(String error) {
    return 'Échec de l\'enregistrement de la course : $error';
  }

  @override
  String get addRunSaved => 'Course ajoutée à l\'historique';

  @override
  String get addRunPickerSearchHint => 'Rechercher des itinéraires';

  @override
  String get addRunPickerClear => 'Effacer';

  @override
  String get addRunPickerCancel => 'Annuler';

  @override
  String addRunPickerNoMatch(String query) {
    return 'Aucun itinéraire ne correspond à \"$query\"';
  }

  @override
  String get addRunPickerNoRoute => 'Aucun itinéraire';

  @override
  String get runDetailDnfBadge => 'DNF';

  @override
  String get runDetailEditTooltip => 'Modifier la course';

  @override
  String get runDetailShareTooltip => 'Partager la course';

  @override
  String get runDetailMoreTooltip => 'Plus';

  @override
  String get runDetailSaveAsRoute => 'Enregistrer comme itinéraire';

  @override
  String get runDetailDeleteRun => 'Supprimer la course';

  @override
  String get runDetailEditTitle => 'Modifier la course';

  @override
  String get runDetailFieldTitle => 'Titre';

  @override
  String get runDetailFieldNotes => 'Notes';

  @override
  String get runDetailFieldDistance => 'Distance';

  @override
  String get runDetailFieldDuration => 'Durée';

  @override
  String get runDetailMarkDnf => 'Marquer comme DNF';

  @override
  String get runDetailMarkDnfSubtitle =>
      'Exclut cette course des records personnels';

  @override
  String get runDetailEditInvalid =>
      'Saisissez une distance et une durée valides';

  @override
  String get runDetailSave => 'Enregistrer';

  @override
  String get runDetailCancel => 'Annuler';

  @override
  String get runDetailDelete => 'Supprimer';

  @override
  String get runDetailLoadingGps => 'Chargement des données GPS...';

  @override
  String get runDetailGpsUnavailable => 'Aucune trace GPS hors ligne';

  @override
  String get runDetailPauseReplay => 'Mettre en pause la relecture';

  @override
  String get runDetailReplay => 'Rejouer cette course';

  @override
  String get runDetailStatElevGain => 'Dénivelé +';

  @override
  String get runDetailStatElevLoss => 'Dénivelé -';

  @override
  String get runDetailStatAvgHr => 'FC moy.';

  @override
  String get runDetailStatAgeGrade => 'Indice d\'âge';

  @override
  String get runDetailSectionElevation => 'Dénivelé';

  @override
  String get runDetailSectionLaps => 'Tours';

  @override
  String runDetailLapNumber(int number) {
    return 'Tour $number';
  }

  @override
  String get runDetailSectionRunningDynamics => 'Dynamique de course';

  @override
  String get runDetailDynVerticalOsc => 'Oscillation verticale';

  @override
  String get runDetailDynGroundContact => 'Contact au sol';

  @override
  String get runDetailDynStrideLength => 'Longueur de foulée';

  @override
  String get runDetailDynAvgPower => 'Puissance moy.';

  @override
  String get runDetailSectionRouteHistory => 'Historique de l\'itinéraire';

  @override
  String get runDetailThisRoute => 'cet itinéraire';

  @override
  String runDetailPersonalBest(String route) {
    return 'Record personnel sur $route';
  }

  @override
  String runDetailBehindPb(String delta) {
    return '$delta derrière le record';
  }

  @override
  String runDetailAttemptOf(int rank, int total, String pb) {
    return 'Tentative $rank sur $total  —  Record : $pb';
  }

  @override
  String get runDetailSectionBestEfforts => 'Meilleures performances';

  @override
  String get runDetailSectionHeartRateZones => 'Zones de fréquence cardiaque';

  @override
  String get runDetailHrAvg => 'Moy.';

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
  String get runDetailNoGpsForSplits => 'Aucune donnée GPS pour les splits';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Course trop courte pour un split complet de $unit';
  }

  @override
  String get runDetailSectionSegments => 'Segments';

  @override
  String get runDetailSaveAsRouteTitle => 'Enregistrer comme itinéraire';

  @override
  String get runDetailSaveAsRouteBody =>
      'Enregistrez cette trace GPS comme itinéraire que vous pourrez suivre à nouveau.';

  @override
  String get runDetailRouteNameLabel => 'Nom de l\'itinéraire';

  @override
  String get runDetailNoTrackToSave =>
      'Cette course n\'a pas de trace GPS à enregistrer comme itinéraire';

  @override
  String runDetailRouteLinked(String route) {
    return 'Associée à $route';
  }

  @override
  String get runDetailRouteLinkFailed => 'Impossible d\'associer l\'itinéraire';

  @override
  String get runDetailReSnapping => 'Réajustement aux routes…';

  @override
  String runDetailRematchFailed(String error) {
    return 'Échec du réajustement : $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return '\"$name\" enregistré — $kept points de cheminement ($smoothed lissés)';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'Impossible de rendre la course publique : $error';
  }

  @override
  String get runDetailMakePublicTitle => 'Rendre cette course publique ?';

  @override
  String get runDetailMakePublicBodyZone =>
      'Le partage rend cette course publique afin que toute personne disposant du lien puisse la consulter. Cette course commence ou se termine dans l\'une de vos zones de confidentialité, les spectateurs verront donc une trace écourtée, les segments situés dans la zone étant masqués.';

  @override
  String get runDetailMakePublicBodyHasZones =>
      'Le partage rend cette course publique afin que toute personne disposant du lien puisse la consulter. Aucune de vos zones de confidentialité ne recoupe cette trace, la trace complète sera donc visible.';

  @override
  String get runDetailMakePublicBodyNoZones =>
      'Le partage rend cette course publique afin que toute personne disposant du lien puisse la consulter — y compris les points de départ et d\'arrivée de votre course. Vous n\'avez aucune zone de confidentialité configurée. Pensez à en ajouter une autour de votre domicile avant de partager.';

  @override
  String get runDetailMakePublic => 'Rendre publique';

  @override
  String get runDetailDeleteTitle => 'Supprimer la course ?';

  @override
  String get runDetailDeleteBody => 'Cette action est irréversible.';

  @override
  String get runDetailSuggestLink => 'Associer';

  @override
  String get runDetailSuggestDismiss => 'Ignorer';

  @override
  String get runDetailSuggestRanRoute => 'On dirait que vous avez parcouru ';

  @override
  String get runDetailSuggestLinkPrompt =>
      'Associer cette course à cet itinéraire ?';

  @override
  String get runDetailMatchPending => 'Ajustement aux routes…';

  @override
  String get runDetailMatchSkipped => 'Non ajustée (trop peu de points)';

  @override
  String get runDetailMatchFailed =>
      'Échec de l\'ajustement — trace brute affichée';

  @override
  String get runDetailMatchMatched => 'Ajustée';

  @override
  String get runDetailRematchQueueing => 'Mise en file…';

  @override
  String get runDetailRematch => 'Réajuster';

  @override
  String get runDetailSegStatDistance => 'Distance';

  @override
  String get runDetailSegStatTime => 'Temps';

  @override
  String get runDetailSegStatPace => 'Allure';

  @override
  String get runDetailSegStatHr => 'FC';

  @override
  String get runDetailSegStatGain => 'Dénivelé +';

  @override
  String get runDetailSegDismiss => 'Ignorer';

  @override
  String get publicRunTitle => 'Course';

  @override
  String get publicRunLoadError => 'Impossible de charger cette course.';

  @override
  String get publicRunUnavailable =>
      'Cette course est privée ou n\'est plus disponible.';

  @override
  String get publicRunAuthorFallback => 'Coureur';

  @override
  String get publicRunStatDistance => 'Distance';

  @override
  String get publicRunStatTime => 'Temps';

  @override
  String get publicRunStatPace => 'Allure';

  @override
  String get publicRunSectionSegments => 'Segments';
}
