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

  @override
  String get routesSyncFailedOffline =>
      'Impossible de synchroniser les itinéraires — hors ligne';

  @override
  String get routesLoadMoreFailed =>
      'Impossible de charger plus d\'itinéraires';

  @override
  String routesStarUpdateFailed(String error) {
    return 'Impossible de mettre à jour le favori : $error';
  }

  @override
  String get routesImportFailedLocalOnly =>
      'Échec de l\'import : choisissez le fichier dans le stockage local, pas dans un sélecteur de documents uniquement cloud.';

  @override
  String routesImported(String name) {
    return '« $name » importé';
  }

  @override
  String routesImportFailed(String error) {
    return 'Échec de l\'import : $error';
  }

  @override
  String routesSaved(String name) {
    return '« $name » enregistré';
  }

  @override
  String get routesEmptyTitle => 'Aucun itinéraire pour l\'instant';

  @override
  String get routesEmptyBody =>
      'Appuyez sur Créer pour tracer un itinéraire sur la carte, ou importez un fichier GPX, KML ou TCX.';

  @override
  String get routesBuild => 'Créer';

  @override
  String get routesImport => 'Importer';

  @override
  String get routesNoMatch => 'Aucun itinéraire ne correspond à ces filtres';

  @override
  String get routesClearFilters => 'Effacer les filtres';

  @override
  String routesLoadMore(int count) {
    return 'Charger $count de plus';
  }

  @override
  String get routesQueuedToSync => 'En attente de synchronisation';

  @override
  String get routesSavedForOffline => 'Enregistré hors ligne';

  @override
  String get routesUnstarRoute => 'Retirer l\'itinéraire des favoris';

  @override
  String get routesStarForWatch => 'Marquer pour afficher sur la montre';

  @override
  String get routesDiscover => 'Découvrir';

  @override
  String get routesSyncFromCloud => 'Synchroniser depuis le cloud';

  @override
  String get routesPublicRoutes => 'Itinéraires publics';

  @override
  String get routesHeatmap => 'Carte de chaleur';

  @override
  String get routesExplorePublic => 'Explorer les itinéraires publics';

  @override
  String get routesHeatmapTooltip => 'Carte de chaleur des itinéraires';

  @override
  String get routesSearchHint => 'Rechercher des itinéraires par nom…';

  @override
  String get routesClearSearch => 'Effacer la recherche';

  @override
  String get routesStarred => 'Favoris';

  @override
  String routesCountMeta(int visible, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$visible sur $total itinéraires',
      one: '$visible sur $total itinéraire',
    );
    return '$_temp0';
  }

  @override
  String get routesSurfaceAny => 'Toute surface';

  @override
  String get routesSurfaceRoad => 'Route';

  @override
  String get routesSurfaceTrail => 'Sentier';

  @override
  String get routesSurfaceMixed => 'Mixte';

  @override
  String get routesDistanceAny => 'Toute distance';

  @override
  String get routesSortNewest => 'Plus récents d\'abord';

  @override
  String get routesSortLongest => 'Plus long';

  @override
  String get routesSortShortest => 'Plus court';

  @override
  String get routesSortMostRun => 'Les plus parcourus';

  @override
  String get routesSortAlpha => 'A–Z';

  @override
  String routesDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count itinéraires ?',
      one: 'Supprimer $count itinéraire ?',
    );
    return '$_temp0';
  }

  @override
  String get routesDeleteConfirmBody => 'Cette action est irréversible.';

  @override
  String routesSelectionTitle(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted supprimé(s) ; $failed échec(s) — vérifiez votre connexion.';
  }

  @override
  String routesDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itinéraires supprimés.',
      one: '$count itinéraire supprimé.',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteCleared => 'Itinéraire effacé';

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
      'Échec du calcul d\'itinéraire — affichage de lignes droites entre vos points.';

  @override
  String routeBuilderSegmentsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count segments n\'ont pas pu s\'aligner sur une route. Déplacez les points concernés pour ajuster.',
      one:
          '$count segment n\'a pas pu s\'aligner sur une route. Déplacez le point concerné pour ajuster.',
    );
    return '$_temp0';
  }

  @override
  String routeBuilderRoutingFailed(String error) {
    return 'Échec du calcul d\'itinéraire : $error';
  }

  @override
  String get routeBuilderTooCloseToPin =>
      'Trop proche d\'un autre point — déplacez un peu plus loin.';

  @override
  String get routeBuilderPinAlreadyThere =>
      'Un point est déjà là — appuyez plus loin pour en ajouter un autre.';

  @override
  String get routeBuilderTargetTooLong =>
      'Saisissez une distance cible jusqu\'à 1000 km.';

  @override
  String get routeBuilderSaveNeedTwo => 'Placez d\'abord au moins deux points.';

  @override
  String routeBuilderSavedLocally(String detail) {
    return 'Enregistré localement. $detail Sera synchronisé la prochaine fois.';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return 'Position indisponible : $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'Serveur injoignable. Connectez-vous ou vérifiez votre connexion, puis réessayez.';

  @override
  String routeBuilderSaveFailed(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get routeBuilderSearchHint => 'Rechercher des lieux…';

  @override
  String get routeBuilderMore => 'Plus';

  @override
  String get routeBuilderGenerateLoop => 'Générer une boucle';

  @override
  String get routeBuilderUndo => 'Annuler';

  @override
  String get routeBuilderClear => 'Effacer';

  @override
  String get routeBuilderSaving => 'Enregistrement…';

  @override
  String get routeBuilderSave => 'Enregistrer';

  @override
  String get routeBuilderLocateMe => 'Me localiser';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'Appuyez pour déplacer le point $number, ou utilisez les icônes';
  }

  @override
  String routeBuilderEmptyHint(String mode) {
    return 'Appuyez sur la carte pour placer des points · $mode';
  }

  @override
  String routeBuilderOnePointHint(String mode) {
    return 'Placez-en un autre pour tracer la ligne · $mode';
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
    return 'Supprimer le point $number';
  }

  @override
  String get routeBuilderCancelDrag => 'Annuler le déplacement';

  @override
  String get routeBuilderModeTrail => 'Sentier';

  @override
  String get routeBuilderModeRoad => 'Route';

  @override
  String get routeBuilderModeStraight => 'Droite';

  @override
  String get routeBuilderLoopDialogBody =>
      'Distance cible — nous créerons une boucle radiale autour du centre actuel de la carte.';

  @override
  String get routeBuilderCancel => 'Annuler';

  @override
  String get routeBuilderGenerate => 'Générer';

  @override
  String get routeBuilderSaveDialogTitle => 'Enregistrer l\'itinéraire';

  @override
  String get routeBuilderNameLabel => 'Nom';

  @override
  String get routeBuilderNameHint => 'p. ex. Boucle de la rivière';

  @override
  String get routeBuilderDescriptionLabel => 'Description (facultatif)';

  @override
  String get routeBuilderDescriptionHint =>
      'Surface, dénivelé, stationnement, tout ce qui mérite d\'être noté';

  @override
  String get routeBuilderSaveToLabel => 'Enregistrer dans';

  @override
  String get routeBuilderSaveToPersonal => 'Personnel';

  @override
  String get routeBuilderMakePublic => 'Rendre public';

  @override
  String get routeBuilderMakePublicSubtitle =>
      'Les autres peuvent la trouver dans Découvrir';

  @override
  String get routeDetailStartRun => 'Démarrer la course';

  @override
  String get routeDetailShare => 'Partager';

  @override
  String get routeDetailShareAsImage => 'Partager en image';

  @override
  String get routeDetailShareAsGpx => 'Partager en GPX';

  @override
  String get routeDetailShareAsKml => 'Partager en KML';

  @override
  String get routeDetailRemoveOfflineSave =>
      'Supprimer l\'enregistrement hors ligne';

  @override
  String get routeDetailSaveForOffline =>
      'Enregistrer pour une utilisation hors ligne';

  @override
  String get routeDetailUnstarRoute => 'Retirer l\'itinéraire des favoris';

  @override
  String get routeDetailStarForWatch => 'Marquer pour afficher sur la montre';

  @override
  String get routeDetailMakePrivate => 'Rendre privé';

  @override
  String get routeDetailMakePublic => 'Rendre public';

  @override
  String get routeDetailRemoveBookmark => 'Retirer le signet';

  @override
  String get routeDetailBookmarkRoute => 'Ajouter aux signets';

  @override
  String get routeDetailReportRoute => 'Signaler l\'itinéraire';

  @override
  String get routeDetailTransferToClub => 'Transférer à un club';

  @override
  String get routeDetailManageClub => 'Détacher ou déplacer vers un autre club';

  @override
  String get routeDetailDeleteRoute => 'Supprimer l\'itinéraire';

  @override
  String get routeDetailStatDistance => 'Distance';

  @override
  String get routeDetailStatElevation => 'Dénivelé';

  @override
  String routeDetailStatReviews(int count) {
    return '$count avis';
  }

  @override
  String get routeDetailStatWaypoints => 'Points';

  @override
  String get routeDetailPublicRoute => 'Itinéraire public';

  @override
  String get routeDetailPrivateRoute => 'Itinéraire privé';

  @override
  String get routeDetailPublicSubtitle =>
      'Toute personne disposant du lien de partage peut voir cet itinéraire';

  @override
  String get routeDetailPrivateSubtitle =>
      'Vous seul pouvez voir cet itinéraire';

  @override
  String get routeDetailSavedForOffline => 'Enregistré hors ligne';

  @override
  String get routeDetailSaveForOfflineTitle => 'Enregistrer hors ligne';

  @override
  String get routeDetailOfflinePinnedSubtitle =>
      'L\'itinéraire reste sur ce téléphone pour que vous puissiez le parcourir sans connexion.';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'Conservez cet itinéraire sur votre téléphone pour une utilisation sans réseau.';

  @override
  String get routeDetailDescriptionHeading => 'Description';

  @override
  String routeDetailRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses',
      one: '$count course',
    );
    return '$_temp0';
  }

  @override
  String get routeDetailFeatured => 'En vedette';

  @override
  String get routeDetailSurfaceTrail => 'SENTIER';

  @override
  String get routeDetailSurfaceMixed => 'MIXTE';

  @override
  String get routeDetailSurfaceRoad => 'ROUTE';

  @override
  String get routeDetailAddTagHint => 'ajouter une étiquette';

  @override
  String get routeDetailReviewsHeading => 'Avis';

  @override
  String get routeDetailRate => 'Noter';

  @override
  String get routeDetailReviewsOffline => 'Avis indisponibles hors ligne';

  @override
  String get routeDetailNoReviews => 'Aucun avis pour l\'instant';

  @override
  String get routeDetailRateDialogTitle => 'Noter cet itinéraire';

  @override
  String get routeDetailCommentLabel => 'Commentaire (facultatif)';

  @override
  String get routeDetailCancel => 'Annuler';

  @override
  String get routeDetailSubmit => 'Envoyer';

  @override
  String get routeDetailSignInToReview => 'Connectez-vous pour laisser un avis';

  @override
  String routeDetailReviewFailed(String error) {
    return 'Échec de l\'envoi de l\'avis : $error';
  }

  @override
  String routeDetailBookmarkFailed(String error) {
    return 'Échec du signet : $error';
  }

  @override
  String get routeDetailPublicWillSync =>
      'Itinéraire défini comme public. Sera synchronisé la prochaine fois.';

  @override
  String get routeDetailPrivateWillSync =>
      'Itinéraire défini comme privé. Sera synchronisé la prochaine fois.';

  @override
  String routeDetailVisibilityFailed(String error) {
    return 'Impossible de mettre à jour la visibilité : $error';
  }

  @override
  String routeDetailStarFailed(String error) {
    return 'Impossible de mettre à jour le favori : $error';
  }

  @override
  String get routeDetailOfflineSaved =>
      'Enregistré pour une utilisation hors ligne.';

  @override
  String get routeDetailOfflineRemoved =>
      'Retiré des enregistrements hors ligne.';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'Impossible d\'enregistrer l\'étiquette : $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return 'Impossible de partager $format : $error';
  }

  @override
  String get routeDetailClubsLoadTimeout =>
      'Impossible de charger vos clubs — vérifiez votre réseau.';

  @override
  String get routeDetailClubsLoadFailed => 'Impossible de charger vos clubs.';

  @override
  String get routeDetailDetached =>
      'Détaché du club ; l\'itinéraire est désormais personnel.';

  @override
  String get routeDetailMovedToClub =>
      'Itinéraire déplacé dans la bibliothèque du club.';

  @override
  String routeDetailTransferFailed(String error) {
    return 'Échec du transfert : $error';
  }

  @override
  String get routeDetailDeleteTitle => 'Supprimer l\'itinéraire ?';

  @override
  String get routeDetailDeleteBody => 'Cette action est irréversible.';

  @override
  String get routeDetailDelete => 'Supprimer';

  @override
  String routeDetailDeleteFailed(String error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String get routeDetailPreview => 'Aperçu';

  @override
  String get routeDetailPreviewStart => 'Départ';

  @override
  String get routeDetailPreviewFinish => 'Arrivée';

  @override
  String get routeDetailTransferDialogTitle => 'Transférer à un club';

  @override
  String get routeDetailManageClubTitle => 'Gérer l\'appartenance au club';

  @override
  String get routeDetailTransferDialogBody =>
      'Les membres du club verront cet itinéraire dans la bibliothèque du club et pourront l\'ajouter à leurs plans.';

  @override
  String get routeDetailManageClubBody =>
      'Déplacez cet itinéraire vers un autre club que vous administrez, ou détachez-le pour le rendre personnel.';

  @override
  String get routeDetailDetachToPersonal => 'Détacher vers personnel';

  @override
  String get routeDetailDetachSubtitle =>
      'Retire l\'itinéraire de la bibliothèque du club actuel.';

  @override
  String get routeDetailNoAdminClubs =>
      'Vous ne possédez ni n\'administrez encore aucun club.';

  @override
  String get routeDetailCurrentClub => 'Club actuel';

  @override
  String routeDetailClubMemberCount(String location, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '$count membre',
    );
    return '$location · $_temp0';
  }

  @override
  String get exploreRoutesTitle => 'Explorer les itinéraires';

  @override
  String get exploreRoutesModeSearch => 'Recherche';

  @override
  String get exploreRoutesModeNearMe => 'À proximité';

  @override
  String get exploreRoutesSearchHint => 'Rechercher des itinéraires par nom...';

  @override
  String get exploreRoutesFeatured => 'En vedette';

  @override
  String get exploreRoutesSignInRequired =>
      'Connectez-vous et accédez à Internet pour explorer les itinéraires';

  @override
  String get exploreRoutesTimeout =>
      'Délai de connexion dépassé. Vérifiez votre réseau et réessayez.';

  @override
  String get exploreRoutesSearchFailed =>
      'Échec de la recherche. Appuyez sur Réessayer pour recommencer.';

  @override
  String get exploreRoutesLoadMoreFailed =>
      'Impossible de charger plus — vérifiez votre connexion';

  @override
  String get exploreRoutesLocationPermissionRequired =>
      'Autorisation de localisation requise pour trouver des itinéraires à proximité';

  @override
  String get exploreRoutesNearbyFailed =>
      'Impossible de trouver des itinéraires à proximité. Appuyez sur Réessayer pour recommencer.';

  @override
  String get exploreRoutesEmptyNoPublic =>
      'Aucun itinéraire public pour l\'instant';

  @override
  String get exploreRoutesEmptyNoMatch =>
      'Aucun itinéraire ne correspond à votre recherche';

  @override
  String get exploreRoutesEmptyBody =>
      'Les itinéraires partagés depuis l\'application web apparaissent ici';

  @override
  String get exploreRoutesDistanceAny => 'Toute distance';

  @override
  String get exploreRoutesSurfaceAny => 'Toute surface';

  @override
  String get exploreRoutesSurfaceRoad => 'Route';

  @override
  String get exploreRoutesSurfaceTrail => 'Sentier';

  @override
  String get exploreRoutesSurfaceMixed => 'Mixte';

  @override
  String get exploreRoutesSortMostRun => 'Les plus parcourus';

  @override
  String get exploreRoutesSortNewest => 'Plus récents';

  @override
  String get exploreRoutesSortFeatured => 'En vedette';

  @override
  String get exploreRoutesSort => 'Trier';

  @override
  String exploreRoutesSaveCheckConnection(String name) {
    return 'Impossible d\'enregistrer « $name » — vérifiez votre connexion et réessayez.';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return 'Impossible d\'enregistrer « $name ».';
  }

  @override
  String exploreRoutesSaved(String name) {
    return '« $name » enregistré dans votre bibliothèque';
  }

  @override
  String get exploreRoutesAlreadySaved => 'Déjà enregistré';

  @override
  String get exploreRoutesSaveToLibrary => 'Enregistrer dans la bibliothèque';

  @override
  String get exploreRoutesSurfaceTrailShort => 'Sentier';

  @override
  String get exploreRoutesSurfaceMixedShort => 'Mixte';

  @override
  String get exploreRoutesSurfaceRoadShort => 'Route';

  @override
  String get exploreRoutesDistanceUnderKm => 'Moins de 5 km';

  @override
  String get exploreRoutesDistanceMidKm => '5–10 km';

  @override
  String get exploreRoutesDistanceLongKm => '10–21 km';

  @override
  String get exploreRoutesDistanceUltraKm => '21 km+';

  @override
  String get exploreRoutesDistanceUnderMi => 'Moins de 3 mi';

  @override
  String get exploreRoutesDistanceMidMi => '3–6 mi';

  @override
  String get exploreRoutesDistanceLongMi => '6–13 mi';

  @override
  String get exploreRoutesDistanceUltraMi => '13 mi+';

  @override
  String get heatmapSearchHint => 'Rechercher des lieux…';

  @override
  String get heatmapFilters => 'Filtres';

  @override
  String heatmapRoutesStartHere(int count) {
    return '$count itinéraires commencent ici';
  }

  @override
  String heatmapRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itinéraires',
      one: '$count itinéraire',
    );
    return '$_temp0';
  }

  @override
  String get heatmapNoRoutesHere => 'Aucun itinéraire ici';

  @override
  String get heatmapNoRoutesHint =>
      'Aucun itinéraire ici. Déplacez la carte ou modifiez les filtres.';

  @override
  String heatmapClearKept(int count) {
    return 'Effacer $count conservé(s)';
  }

  @override
  String get heatmapUnpinFromMap => 'Retirer de la carte';

  @override
  String get heatmapKeepOnMap => 'Conserver sur la carte';

  @override
  String get heatmapLocateMe => 'Me localiser';

  @override
  String heatmapLocationUnavailable(String error) {
    return 'Position indisponible : $error';
  }

  @override
  String get heatmapBackToList => 'Retour à la liste';

  @override
  String get heatmapViewRoute => 'Voir l\'itinéraire';

  @override
  String get heatmapKept => 'Conservé';

  @override
  String get heatmapKeep => 'Conserver';

  @override
  String get heatmapLensShow => 'Afficher';

  @override
  String get heatmapLensDistance => 'Distance';

  @override
  String get heatmapLensMap => 'Carte';

  @override
  String get heatmapHeatDensity => 'Densité de chaleur';

  @override
  String get heatmapResetFilters => 'Réinitialiser les filtres';

  @override
  String get heatmapLensPopular => 'Populaire';

  @override
  String get heatmapLensFriends => 'Amis';

  @override
  String get heatmapLensFeatured => 'En vedette';

  @override
  String get heatmapLensHiddenGems => 'Trésors cachés';

  @override
  String get publicRouteFallbackTitle => 'Itinéraire';

  @override
  String get publicRouteLoadError => 'Impossible de charger cet itinéraire.';

  @override
  String get publicRouteUnavailable =>
      'Cet itinéraire est privé ou n\'est plus disponible.';

  @override
  String get publicRouteStatDistance => 'Distance';

  @override
  String get publicRouteStatElevation => 'Dénivelé';

  @override
  String get publicRouteStatWaypoints => 'Points';

  @override
  String get routesLoadErrorRetry =>
      'Impossible de charger vos itinéraires. Vérifiez votre connexion et réessayez.';
}
