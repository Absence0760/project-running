// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get trustedContactsClearedBanner => 'Contacts de confiance effacés.';

  @override
  String trustedContactsSavedBanner(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contacts de confiance enregistrés.',
      one: '1 contact de confiance enregistré.',
    );
    return '$_temp0';
  }

  @override
  String trustedContactsSaveFailedBanner(Object error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get trustedContactsTitle => 'Contacts de confiance';

  @override
  String trustedContactsIntro(Object max) {
    return 'Désignez un ou plusieurs contacts de confiance. La liste est enregistrée avec votre compte afin que les futures fonctions « course en retard » et bouton d\'alerte sachent à qui envoyer des notifications. Jusqu\'à $max.';
  }

  @override
  String get trustedContactsAddButton => 'Ajouter un contact';

  @override
  String get trustedContactsSavingButton => 'Enregistrement…';

  @override
  String get trustedContactsSaveButton => 'Enregistrer';

  @override
  String get trustedContactsNameLabel => 'Nom';

  @override
  String get trustedContactsNameHint => 'ex. Alex Chen';

  @override
  String get trustedContactsPhoneLabel => 'Téléphone';

  @override
  String get trustedContactsPhoneHint => '+33 6 12 34 56 78';

  @override
  String get trustedContactsEmailLabel => 'E-mail';

  @override
  String get trustedContactsEmailHint => 'alex@exemple.com';

  @override
  String get trustedContactsRelationshipLabel => 'Lien';

  @override
  String get trustedContactsRelationshipHint =>
      'partenaire / parent / partenaire de course';

  @override
  String get trustedContactsRemoveButton => 'Retirer';

  @override
  String get clubInviteEnterCodeError =>
      'Saisissez le code d\'invitation de votre lien.';

  @override
  String get clubInviteJoinedBanner => 'Vous avez rejoint le club.';

  @override
  String get clubInviteTitle => 'Rejoindre un club';

  @override
  String get clubInviteIntro =>
      'Collez le code d\'invitation que l\'administrateur du club vous a communiqué.';

  @override
  String get clubInviteCodeLabel => 'Code d\'invitation';

  @override
  String get clubInviteJoinButton => 'Rejoindre';

  @override
  String recapShareHeadline(Object year) {
    return 'Mon année $year en course :';
  }

  @override
  String recapShareTotals(Object total, Object count) {
    return '$total sur $count courses';
  }

  @override
  String recapShareLongestRun(Object distance) {
    return 'Course la plus longue : $distance';
  }

  @override
  String recapShareBestStreak(Object days) {
    return 'Meilleure série : $days jours';
  }

  @override
  String recapShareSubject(Object year) {
    return 'Bilan $year';
  }

  @override
  String get recapTitle => 'Année en course';

  @override
  String get recapShareTooltip => 'Partager le bilan';

  @override
  String get recapPublishAndShare => 'Publier et partager le lien';

  @override
  String get recapPublishFailed => 'Impossible de publier le récap. Réessayez.';

  @override
  String get recapPrevYear => 'Année précédente';

  @override
  String get recapNextYear => 'Année suivante';

  @override
  String recapNoRunsForYear(Object year) {
    return 'Aucune course à récapituler pour $year.';
  }

  @override
  String recapNoRunsYet(Object year) {
    return 'Aucune course en $year pour l\'instant. Enregistrez-en une pour voir votre bilan.';
  }

  @override
  String recapAcrossRuns(Object count, Object runWord) {
    return 'sur $count $runWord';
  }

  @override
  String get recapLongestRunLabel => 'Course la plus longue';

  @override
  String get recapBestStreakLabel => 'Meilleure série';

  @override
  String recapStreakDays(Object days, Object dayWord) {
    return '$days $dayWord';
  }

  @override
  String get recapTopWeekLabel => 'Meilleure semaine';

  @override
  String get recapUniqueRoutesLabel => 'Itinéraires uniques';

  @override
  String get recapEarliestStartLabel => 'Départ le plus tôt';

  @override
  String get recapLatestStartLabel => 'Départ le plus tard';

  @override
  String get routePickerTitle => 'Choisir un parcours';

  @override
  String get routePickerNoRoute => 'Aucun parcours';

  @override
  String get routePickerClearSearchTooltip => 'Effacer la recherche';

  @override
  String get routePickerSearchHint => 'Rechercher des parcours par nom…';

  @override
  String get routePickerEmptyNoRoutes =>
      'Aucun parcours enregistré pour l\'instant';

  @override
  String routePickerEmptyNoMatch(Object query) {
    return 'Aucun parcours ne correspond à « $query »';
  }

  @override
  String get routePickerStarredHeader => 'Favoris';

  @override
  String get routePickerAllRoutesHeader => 'Tous les parcours';

  @override
  String importStatusImported(Object count, Object label) {
    return '$count courses importées depuis $label';
  }

  @override
  String importStatusImportedWithErrors(Object count, Object errors) {
    return '$count courses importées ($errors en échec)';
  }

  @override
  String importStatusNoGpsNote(Object base, Object label) {
    return '$base. $label ne contient pas de données d\'itinéraire, ces courses n\'ont donc pas de carte.';
  }

  @override
  String importHealthRequestingPermission(Object label) {
    return 'Demande d\'autorisation $label…';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return 'Autorisation $label refusée';
  }

  @override
  String get importHealthReadingWorkouts => 'Lecture des séances…';

  @override
  String importHealthFailed(Object label, Object error) {
    return 'Échec de l\'import $label : $error';
  }

  @override
  String get importStatusSavingLocally => 'Enregistrement local…';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return '$count doublon(s) ignoré(s), déjà importé(s) depuis une autre source';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return '$done sur $total enregistrées localement';
  }

  @override
  String get importStatusSyncingToCloud => 'Synchronisation vers le cloud…';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return '$done sur $total synchronisées';
  }

  @override
  String get importStatusReadingCsv => 'Lecture du CSV…';

  @override
  String importCsvFailed(Object error) {
    return 'Échec de l\'import CSV : $error';
  }

  @override
  String get importStatusRestoringBackup => 'Restauration de la sauvegarde…';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return '$runs courses · $tracks traces · $routes itinéraires restaurés';
  }

  @override
  String importBackupFailed(Object error) {
    return 'Échec de la restauration de la sauvegarde : $error';
  }

  @override
  String get importStatusReadingExport => 'Lecture de l\'export…';

  @override
  String importStravaFailed(Object error) {
    return 'Échec de l\'import : $error';
  }

  @override
  String get importTitle => 'Importer des courses';

  @override
  String get importStravaCardTitle => 'Strava';

  @override
  String get importStravaCardSubtitle =>
      'Importez toutes vos courses depuis un ZIP d\'export de données Strava';

  @override
  String get importStravaHowToHeader => 'Comment obtenir votre export Strava :';

  @override
  String get importStravaHowToSteps =>
      '1. Ouvrez Strava → Réglages → Mon compte\n2. Faites défiler jusqu\'à « Télécharger ou supprimer votre compte »\n3. Touchez « Commencer » → « Demander votre archive »\n4. Vous recevrez un e-mail avec un lien de téléchargement dans quelques heures\n5. Téléchargez le .zip et touchez Importer ci-dessous';

  @override
  String get importStravaButton => 'Importer un ZIP Strava';

  @override
  String importHealthButton(Object label) {
    return 'Importer depuis $label';
  }

  @override
  String get importCsvCardTitle => 'CSV';

  @override
  String get importCsvCardSubtitle =>
      'Réimportez un CSV exporté depuis les Réglages — courses uniquement, sans GPS';

  @override
  String get importCsvCardDescription =>
      'Chaque ligne du CSV devient une course manuelle (date, distance, durée, source). La trace de la carte n\'est pas dans le CSV, les courses importées n\'auront donc pas de tracé d\'itinéraire.';

  @override
  String get importCsvButton => 'Importer un CSV';

  @override
  String get importBackupCardTitle => 'ZIP de sauvegarde complète';

  @override
  String get importBackupCardSubtitle =>
      'Restaurez courses, itinéraires et traces GPS depuis un fichier de sauvegarde';

  @override
  String get importBackupCardDescription =>
      'Aller-retour sans perte. Fonctionne sans connexion — les courses restaurées se synchronisent avec votre compte la prochaine fois que vous vous connectez. Créez une sauvegarde depuis Réglages → Sauvegarde complète.';

  @override
  String get importBackupButton => 'Restaurer un ZIP de sauvegarde';

  @override
  String get importErrorsHeader => 'Erreurs';

  @override
  String importErrorsMore(Object count) {
    return '… et $count de plus';
  }

  @override
  String get importHealthSubtitleIos =>
      'Récupérez les séances enregistrées sur Apple Watch, Nike Run Club, Strava et d\'autres apps qui écrivent dans Apple Santé';

  @override
  String get importHealthSubtitleAndroid =>
      'Récupérez les séances depuis Google Fit, Samsung Health, Garmin, Fitbit et toute autre app Health Connect';

  @override
  String get importHealthDescriptionIos =>
      'Lit les résumés de séances (date, distance, durée, type) de la dernière année. Apple Santé n\'expose pas les itinéraires GPS enregistrés par les apps tierces — les courses importées ainsi n\'auront pas de tracé sur la carte.';

  @override
  String get importHealthDescriptionAndroid =>
      'Lit les résumés de séances (date, distance, durée, type) de la dernière année. Les itinéraires GPS ne sont pas exposés par Health Connect — les courses importées ainsi n\'auront pas de tracé sur la carte.';

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'Impossible de mettre à jour l\'abonnement : $error';
  }

  @override
  String get peopleSearchHint => 'Rechercher des coureurs par nom';

  @override
  String get peopleClearSearchTooltip => 'Effacer la recherche';

  @override
  String get commonClearSearch => 'Effacer la recherche';

  @override
  String get commonDismiss => 'Fermer';

  @override
  String get settingsDevicesRemoveOverride => 'Supprimer le réglage';

  @override
  String get peopleSearchResultsHeader => 'Résultats de recherche';

  @override
  String get peopleSuggestedHeader => 'Suggérés pour vous';

  @override
  String peopleEmptySearchTitle(Object query) {
    return 'Aucun coureur ne correspond à « $query »';
  }

  @override
  String get peopleEmptySearchBody =>
      'Essayez un nom plus court ou différent. Les noms affichés sont publics ; les personnes qui n\'en ont pas encore défini n\'apparaîtront pas ici.';

  @override
  String get peopleEmptySuggestionsTitle => 'Aucune suggestion pour l\'instant';

  @override
  String get peopleEmptySuggestionsBody =>
      'Les suggestions proviennent des membres des clubs que vous avez rejoints. Rejoignez un club pour commencer à en voir ici.';

  @override
  String peoplePublicRunCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses publiques',
      one: '1 course publique',
    );
    return '$_temp0';
  }

  @override
  String peopleSharedClubsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clubs en commun',
      one: '1 club en commun',
    );
    return '$_temp0';
  }

  @override
  String get peopleFallbackDisplayName => 'Coureur';

  @override
  String get peopleFollowingButton => 'Abonné';

  @override
  String get peopleFollowButton => 'Suivre';

  @override
  String get readinessCardHeader => 'FORME DU JOUR';

  @override
  String get readinessBandHigh => 'élevée';

  @override
  String get readinessBandModerate => 'modérée';

  @override
  String get readinessBandLow => 'faible';

  @override
  String get missingMapTilesTitle =>
      'Utilisation des tuiles de secours OpenStreetMap';

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
  String get navLog => 'Ajouter';

  @override
  String get logA11yLabel => 'Enregistrer une activité';

  @override
  String get navFitness => 'Fitness';

  @override
  String get navYou => 'Vous';

  @override
  String get fitnessTabAll => 'Tout';

  @override
  String get fitnessTabRuns => 'Courses';

  @override
  String get fitnessTabGym => 'Muscu';

  @override
  String get fitnessTabNutrition => 'Nutrition';

  @override
  String get fitnessRunsRoutes => 'Itinéraires';

  @override
  String get fitnessRunsPlans => 'Plans d\'entraînement';

  @override
  String get homeAskCoach => 'Demander au coach';

  @override
  String get homeAskCoachSubtitle =>
      'Des conseils sur vos courses, votre muscu et votre nutrition';

  @override
  String get youProfileTitle => 'Votre profil';

  @override
  String get logSheetTitle => 'Ajouter';

  @override
  String get logRun => 'Enregistrer une course';

  @override
  String get logLift => 'Enregistrer la muscu';

  @override
  String get logFood => 'Enregistrer un aliment';

  @override
  String get prefsKeepRunPrimary => 'Course comme action principale';

  @override
  String get prefsKeepRunPrimarySubtitle =>
      'Appuyez sur le bouton central pour démarrer une course ; appui long pour le menu complet';

  @override
  String get bodyMetricsTitle => 'Données corporelles';

  @override
  String get bodyMetricsTileSubtitle =>
      'Taille, poids et objectifs nutritionnels';

  @override
  String get bodyMetricsConsentTitle => 'Stocker les données de santé';

  @override
  String get bodyMetricsConsentSubtitle =>
      'La taille et le poids sont des données de santé sensibles. Désactivez pour les effacer.';

  @override
  String get bodyMetricsHeight => 'Taille';

  @override
  String get bodyMetricsWeight => 'Poids';

  @override
  String get bodyMetricsActivityLevel => 'Niveau d\'activité';

  @override
  String get bodyMetricsGoal => 'Objectif';

  @override
  String get bodyMetricsTargetsHint =>
      'Sert à estimer vos objectifs quotidiens de calories et de macros.';

  @override
  String get bodyMetricsConsentRequired =>
      'Activez le stockage des données de santé pour enregistrer la taille et le poids.';

  @override
  String get bodyMetricsWithdrawTitle =>
      'Retirer le consentement aux données de santé ?';

  @override
  String get bodyMetricsWithdrawBody =>
      'Cela efface définitivement votre taille enregistrée et tout votre historique de poids. C\'est irréversible.';

  @override
  String get bodyMetricsWithdrawConfirm => 'Retirer et effacer';

  @override
  String get bodyMetricsSaved => 'Enregistré';

  @override
  String bodyMetricsSaveFailed(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get safetyTitle => 'Contacts de sécurité';

  @override
  String get safetyTileSubtitle =>
      'Envoyez un e-mail à une personne de confiance à la fin d\'une course';

  @override
  String get safetyIntro =>
      'Un contact de sécurité reçoit un e-mail lorsque vous terminez une course — même privée — pour qu\'une personne de confiance sache que vous êtes bien rentré.';

  @override
  String get safetyAddLabel => 'E-mail du contact';

  @override
  String get safetyAddButton => 'Ajouter un contact';

  @override
  String get safetyAdding => 'Ajout…';

  @override
  String get safetyEmpty => 'Aucun contact de sécurité pour le moment.';

  @override
  String get safetyStatusPending => 'En attente — confirmation requise';

  @override
  String get safetyStatusConfirmed => 'Confirmé';

  @override
  String get safetyRemove => 'Supprimer';

  @override
  String get safetyRemoveConfirm => 'Supprimer ce contact de sécurité ?';

  @override
  String safetyAddFailed(String error) {
    return 'Impossible d\'ajouter le contact : $error';
  }

  @override
  String get safetyInvalidEmail => 'Saisissez une adresse e-mail valide.';

  @override
  String get safetyAddedToast =>
      'Contact ajouté — nous lui avons envoyé un e-mail de confirmation.';

  @override
  String get safetyRemovedToast => 'Contact supprimé.';

  @override
  String get safetyIncomingTitle => 'Demandes pour vous';

  @override
  String get safetyIncomingIntro =>
      'Ces personnes vous ont demandé d\'être leur contact de sécurité. Confirmez pour recevoir un e-mail lorsqu\'elles terminent une course.';

  @override
  String safetyIncomingFrom(String name) {
    return 'De $name';
  }

  @override
  String get safetyConfirm => 'Confirmer';

  @override
  String get safetyDecline => 'Refuser';

  @override
  String get safetyConfirmedToast =>
      'Vous êtes maintenant contact de sécurité.';

  @override
  String get safetyDeclinedToast => 'Demande refusée.';

  @override
  String get safetyUnknownRunner => 'Un coureur Threkir';

  @override
  String get activitySedentary => 'Surtout assis (travail de bureau)';

  @override
  String get activityLight => 'Légèrement actif (peu de mouvement quotidien)';

  @override
  String get activityModerate => 'Modérément actif (souvent debout)';

  @override
  String get activityVeryActive => 'Journée très active (travail physique)';

  @override
  String get activityExtraActive =>
      'Extrêmement actif (travail physique intense)';

  @override
  String get goalLose => 'Perdre du poids';

  @override
  String get goalMaintain => 'Maintenir le poids';

  @override
  String get goalGain => 'Prendre du poids';

  @override
  String get homeTodaysLift => 'Séance du jour';

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
  String get setupPageTitle => 'Configurez votre compte';

  @override
  String get setupSkip => 'Ignorer la configuration';

  @override
  String get setupSkipStep => 'Ignorer';

  @override
  String get setupBack => 'Retour';

  @override
  String get setupContinue => 'Continuer';

  @override
  String get setupSaving => 'Enregistrement…';

  @override
  String get setupOpenDashboard => 'Ouvrir le tableau de bord';

  @override
  String get setupWelcomeToast => 'Bienvenue sur Threkir !';

  @override
  String setupSaveError(String message) {
    return 'Impossible d\'enregistrer votre configuration : $message';
  }

  @override
  String get setupNameTitle => 'Comment doit-on vous appeler ?';

  @override
  String get setupNameHint =>
      'C\'est le nom que les autres coureurs voient sur votre profil et vos courses partagées.';

  @override
  String get setupNameLabel => 'Nom affiché';

  @override
  String get setupNamePlaceholder => 'ex. Alex Coureur';

  @override
  String get setupUnitsTitle => 'Kilomètres ou miles ?';

  @override
  String get setupUnitsHint =>
      'Nous l\'utiliserons partout où des distances et des allures sont affichées. Modifiable à tout moment dans les Réglages.';

  @override
  String get setupUnitKm => 'Kilomètres';

  @override
  String get setupUnitKmSample => '5,0 km · 5:00 /km';

  @override
  String get setupUnitMi => 'Miles';

  @override
  String get setupUnitMiSample => '3,1 mi · 8:03 /mi';

  @override
  String get setupGoalTitle => 'Quel est votre objectif principal ?';

  @override
  String get setupGoalHint =>
      'Nous l\'utiliserons pour suggérer un plan d\'entraînement adapté. Facultatif — vous pouvez l\'ignorer.';

  @override
  String get setupGoalGeneralFitness => 'Rester en forme + en bonne santé';

  @override
  String get setupGoalWeightLoss => 'Perdre du poids';

  @override
  String get setupGoal5k => 'Courir un 5 km';

  @override
  String get setupGoal10k => 'Courir un 10 km';

  @override
  String get setupGoalHalf => 'Courir un semi-marathon';

  @override
  String get setupGoalMarathon => 'Courir un marathon';

  @override
  String get setupAboutTitle => 'Un peu sur vous';

  @override
  String get setupAboutHint =>
      'Facultatif. Aide à personnaliser les estimations d\'allure et de calories. Vous choisissez de partager ou non des données de santé.';

  @override
  String get setupGenderLabel => 'Genre';

  @override
  String get setupGenderPreferNot => 'Préfère ne pas répondre';

  @override
  String get setupGenderFemale => 'Femme';

  @override
  String get setupGenderMale => 'Homme';

  @override
  String get setupGenderNonbinary => 'Non binaire';

  @override
  String get setupDobLabel => 'Date de naissance';

  @override
  String get setupDobNote =>
      'Sert à exclure les comptes de moins de 18 ans de la recherche de personnes, et pour les résultats ajustés à l\'âge si vous partagez des données de santé.';

  @override
  String get setupDobPlaceholder => 'Touchez pour choisir';

  @override
  String get setupWeightLabel => 'Poids (kg)';

  @override
  String get setupWeightPlaceholder => 'ex. 70';

  @override
  String get setupHealthConsent =>
      'J\'autorise Threkir à utiliser mon genre et ma date de naissance pour personnaliser les estimations d\'allure, de fréquence cardiaque et de calories (données de santé sensibles, RGPD art. 9).';

  @override
  String get setupPrivacyTitle => 'Qui voit vos courses ?';

  @override
  String get setupPrivacyHint =>
      'Choisissez une valeur par défaut pour les nouvelles courses. Modifiable à tout moment et remplaçable course par course.';

  @override
  String get setupNotificationsTitle => 'Restez informé';

  @override
  String get setupNotificationsHint =>
      'Choisissez le nombre de notifications push souhaitées. Réglage affiné plus tard dans les Réglages.';

  @override
  String get setupDoneTitle => 'Tout est prêt';

  @override
  String get setupDoneHint =>
      'C\'est tout. Touchez « Ouvrir le tableau de bord » pour commencer à courir.';

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
  String get runTreadmillModeLabel => 'Mode tapis de course';

  @override
  String runTreadmillModeSpeed(String speed) {
    return 'Tapis $speed';
  }

  @override
  String get runTreadmillLostReconnecting =>
      'Tapis de course perdu, reconnexion…';

  @override
  String get runTreadmillReconnected => 'Tapis de course reconnecté';

  @override
  String get runTreadmillLostFallback =>
      'Tapis de course perdu — distance basculée sur le GPS';

  @override
  String get runTreadmillNotFound => 'Impossible de joindre le tapis de course';

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
  String get historyRangeToday => 'Aujourd\'hui';

  @override
  String get historyRangeWeek => 'Cette semaine';

  @override
  String get historyRangeMonth => '30 derniers jours';

  @override
  String get historyRangeYear => 'Cette année';

  @override
  String get historyRangeAll => 'Tout l\'historique';

  @override
  String get historyRangeCustom => 'Personnalisé…';

  @override
  String historyRangeFrom(String date) {
    return 'À partir du $date';
  }

  @override
  String historyRangeUntil(String date) {
    return 'Jusqu\'au $date';
  }

  @override
  String historyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses',
      one: '$count course',
    );
    return '$_temp0';
  }

  @override
  String get historyDateRangeTooltip => 'Plage de dates';

  @override
  String get historySortTooltip => 'Trier';

  @override
  String get historySortNewest => 'Plus récentes d\'abord';

  @override
  String get historySortOldest => 'Plus anciennes d\'abord';

  @override
  String get historySortLongest => 'Distance la plus longue';

  @override
  String get historySortFastest => 'Meilleure allure';

  @override
  String historySyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synchroniser $count courses',
      one: 'Synchroniser $count course',
    );
    return '$_temp0';
  }

  @override
  String get historyRefreshTooltip => 'Actualiser depuis le cloud';

  @override
  String get historyOfflineTooltip => 'Hors ligne';

  @override
  String historySelectionTitle(int count) {
    return '$count sélectionnée(s)';
  }

  @override
  String get historySelectAllTooltip => 'Tout sélectionner';

  @override
  String get historyClearSelectionTooltip => 'Effacer';

  @override
  String get historyDeleteTooltip => 'Supprimer';

  @override
  String get historyCancelTooltip => 'Annuler';

  @override
  String get historyAddRun => 'Ajouter une course';

  @override
  String get historyAddRunTooltip => 'Ajouter une course manuellement';

  @override
  String get historyLogTooltip =>
      'Enregistrer une course, une séance ou un repas';

  @override
  String historyLoadMore(int count) {
    return 'Charger $count de plus';
  }

  @override
  String get historyNoMatch => 'Aucune course ne correspond à ces filtres';

  @override
  String get historyKindAll => 'Tout';

  @override
  String get historyKindRuns => 'Courses';

  @override
  String get historyKindLifts => 'Muscu';

  @override
  String get historyKindMeals => 'Repas';

  @override
  String get historyViewAll => 'Tout voir';

  @override
  String get historyToday => 'Aujourd\'hui';

  @override
  String get historyYesterday => 'Hier';

  @override
  String historySetCount(int n) {
    return '$n séries';
  }

  @override
  String historyKcal(int n) {
    return '$n kcal';
  }

  @override
  String get historyTimelineEmpty =>
      'Rien d\'enregistré dans cette vue pour l\'instant.';

  @override
  String get historyClearFilters => 'Effacer les filtres';

  @override
  String get historyEmptyTitle => 'Aucune course pour l\'instant';

  @override
  String get historyEmptyBody =>
      'Touchez l\'onglet Course pour démarrer votre première course';

  @override
  String get historyFilterAll => 'Toutes';

  @override
  String get historySourceAll => 'Toutes les sources';

  @override
  String historySourceLabel(String source) {
    return 'Source : $source';
  }

  @override
  String get historySourceFilterTooltip => 'Filtrer par source';

  @override
  String get historySourceRecorded => 'Enregistrée';

  @override
  String get historySourceWatch => 'Montre';

  @override
  String get historySourceStrava => 'Strava';

  @override
  String get historySourceParkrun => 'parkrun';

  @override
  String get historySourceHealthKit => 'HealthKit';

  @override
  String get historySourceHealthConnect => 'Health Connect';

  @override
  String get historyRangePickerTitle => 'Sélectionner les dates';

  @override
  String get historyRangeStart => 'Début';

  @override
  String get historyRangeEnd => 'Fin';

  @override
  String get historyRangeTapDate => 'Touchez une date';

  @override
  String get historyRangeApply => 'Appliquer';

  @override
  String get historyRangeClear => 'Effacer';

  @override
  String get historyPrevMonth => 'Mois précédent';

  @override
  String get historyNextMonth => 'Mois suivant';

  @override
  String get historyPrevYear => 'Année précédente';

  @override
  String get historyNextYear => 'Année suivante';

  @override
  String historyDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count courses ?',
      one: 'Supprimer $count course ?',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody => 'Cette action est irréversible.';

  @override
  String get historyCancel => 'Annuler';

  @override
  String get historyDelete => 'Supprimer';

  @override
  String get historyQueuedToSync => 'En attente de synchronisation';

  @override
  String get historySignInToSync =>
      'Connectez-vous depuis les réglages pour synchroniser les courses';

  @override
  String get historyRefreshFailed =>
      'Impossible d\'actualiser — vérifiez votre connexion';

  @override
  String get historyLoadMoreFailed => 'Impossible de charger plus de courses';

  @override
  String historySyncPartial(int synced, int total, String error) {
    return '$synced/$total synchronisées. Erreur : $error';
  }

  @override
  String historySyncTrackFailed(int count) {
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
  String historySyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Les $count courses synchronisées',
      one: '$count course synchronisée',
    );
    return '$_temp0';
  }

  @override
  String historyDeletePartial(int deleted, int queued) {
    return '$deleted supprimée(s) ; $queued en attente — nouvelle tentative une fois en ligne.';
  }

  @override
  String historyDeleteDone(int count) {
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
  String get runDetailReportRun => 'Signaler la course';

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
  String get runDetailStatGradeAdjPace => 'Allure corrigée';

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
  String runDetailRouteSaveFailed(String name) {
    return 'Impossible d\'enregistrer « $name » comme itinéraire.';
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
  String get runDetailMatchOffline =>
      'Hors ligne — trace brute affichée, nouvelle tentative à venir';

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
  String get routeBuilderClearConfirmTitle => 'Effacer cet itinéraire ?';

  @override
  String get routeBuilderClearConfirmBody =>
      'Tous les points seront supprimés. Cette action est irréversible.';

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
  String get routeDetailShareAsGpxMarkers => 'Partager en GPX + repères';

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
  String get routeDetailDescribe => 'Décrire cet itinéraire';

  @override
  String get routeDetailDescribing => 'Description en cours…';

  @override
  String get routeDetailAiAttribution =>
      'Rédigé par l\'IA à partir des données de l\'itinéraire';

  @override
  String get routeDetailDescribeFailed =>
      'Impossible de générer une description. Veuillez réessayer.';

  @override
  String get routeDetailEnhanceUpgradeHint =>
      'Les descriptions par IA sont une fonctionnalité Pro. Passez à Pro pour en profiter.';

  @override
  String get routeDetailDescShapeLoop => 'en boucle';

  @override
  String get routeDetailDescShapeOutAndBack => 'aller-retour';

  @override
  String get routeDetailDescShapePointToPoint => 'point à point';

  @override
  String get routeDetailDescSurfaceRoad => 'sur route';

  @override
  String get routeDetailDescSurfaceTrail => 'sur sentier';

  @override
  String get routeDetailDescSurfaceMixed => 'à surface mixte';

  @override
  String get routeDetailDescElevFlat => 'plat';

  @override
  String get routeDetailDescElevRolling => 'légèrement vallonné';

  @override
  String get routeDetailDescElevHilly => 'vallonné';

  @override
  String get routeDetailDescElevMountainous => 'montagneux';

  @override
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  ) {
    return '$name est un itinéraire $shape $surface de $distance.';
  }

  @override
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  ) {
    return '$name est un itinéraire $shape de $distance.';
  }

  @override
  String routeDetailDescClimb(String gain, String elevation, String perKm) {
    return 'Il présente $gain de dénivelé positif — $elevation, environ $perKm par km.';
  }

  @override
  String get routeDetailDescFlat => 'Il présente peu ou pas de dénivelé.';

  @override
  String routeDetailDescPerKm(int m) {
    return '$m m';
  }

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
  String routeDetailRateStars(int n) {
    return 'Définir la note à $n sur 5';
  }

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
  String routeDetailTagRemoveFailed(String error) {
    return 'Impossible de supprimer l\'étiquette : $error';
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
  String get runHeatmapTitle => 'Votre carte de chaleur';

  @override
  String get runHeatmapTooltip => 'Carte de chaleur des courses';

  @override
  String get runHeatmapLoading => 'Chargement de vos courses…';

  @override
  String runHeatmapLoadingProgress(int n, int total) {
    return 'Chargement de vos courses… $n/$total';
  }

  @override
  String get runHeatmapEmptyTitle => 'Aucune course cartographiée';

  @override
  String get runHeatmapEmptyBody =>
      'Enregistrez ou importez des courses avec des traces GPS et elles s\'illumineront ici.';

  @override
  String get runHeatmapLegendTitle => 'Votre carte de chaleur';

  @override
  String runHeatmapLegendSummaryOne(int n) {
    return '$n course cartographiée — plus lumineux là où vous courez le plus.';
  }

  @override
  String runHeatmapLegendSummaryMany(int n) {
    return '$n courses cartographiées — plus lumineux là où vous courez le plus.';
  }

  @override
  String get runHeatmapScaleLess => 'moins';

  @override
  String get runHeatmapScaleMore => 'plus';

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

  @override
  String get feedTitle => 'Fil';

  @override
  String get feedFindPeople => 'Trouver des gens';

  @override
  String get feedActivityAll => 'Tout';

  @override
  String get feedActivityRun => 'Course';

  @override
  String get feedActivityWalk => 'Marche';

  @override
  String get feedActivityCycle => 'Vélo';

  @override
  String get feedActivityHike => 'Rando';

  @override
  String get feedActivityLift => 'Muscu';

  @override
  String get feedLiftSetsLabel => 'Séries';

  @override
  String get feedLiftVolume => 'Volume';

  @override
  String get feedLiftUntitled => 'Séance';

  @override
  String get feedLoadMore => 'Charger plus';

  @override
  String feedLoadMoreFailed(String error) {
    return 'Impossible de charger plus : $error';
  }

  @override
  String get feedLoadError => 'Impossible de charger le fil.';

  @override
  String get feedEveryoneYouFollow => 'Tous ceux que vous suivez';

  @override
  String get feedRunnerFallback => 'Coureur';

  @override
  String get relativeJustNow => 'À l\'instant';

  @override
  String relativeMinutesAgo(int count) {
    return 'il y a $count min';
  }

  @override
  String relativeHoursAgo(int count) {
    return 'il y a $count h';
  }

  @override
  String get relativeYesterday => 'Hier';

  @override
  String relativeDaysAgo(int count) {
    return 'il y a $count j';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count semaines',
      one: 'il y a 1 semaine',
    );
    return '$_temp0';
  }

  @override
  String get coachArchiveToday => 'Aujourd\'hui';

  @override
  String coachArchiveDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count jours',
    );
    return '$_temp0';
  }

  @override
  String get feedLast14Days => '14 derniers jours';

  @override
  String get feedEmptyTitle => 'Votre fil est vide';

  @override
  String get feedEmptyBody =>
      'Suivez d\'autres coureurs pour voir leurs courses publiques ici.';

  @override
  String get feedNoMatchesTitle => 'Aucun résultat';

  @override
  String get feedNoMatchesBody =>
      'Rien ne correspond aux filtres actuels sur les 14 derniers jours.';

  @override
  String get feedNoActivityTitle => 'Aucune activité récente';

  @override
  String get feedNoActivityBody =>
      'Personne que vous suivez n\'a enregistré de course publique ces 14 derniers jours.';

  @override
  String get feedClearFilters => 'Effacer les filtres';

  @override
  String feedKudosUpdateFailed(String error) {
    return 'Impossible de mettre à jour les kudos : $error';
  }

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileRunnerFallback => 'Coureur';

  @override
  String get profileTabRuns => 'Courses';

  @override
  String get profileTabFollowers => 'Abonnés';

  @override
  String get profileTabFollowing => 'Abonnements';

  @override
  String get profileTabNotifications => 'Notifications';

  @override
  String get profileReportUser => 'Signaler l\'utilisateur';

  @override
  String get profileUnblock => 'Débloquer ce profil';

  @override
  String get profileBlock => 'Bloquer ce profil';

  @override
  String get profileLoadError => 'Impossible de charger le profil.';

  @override
  String get profileNotFound => 'Profil introuvable.';

  @override
  String profileFollowStats(int followers, int following) {
    String _temp0 = intl.Intl.pluralLogic(
      followers,
      locale: localeName,
      other: '$followers abonnés',
      one: '$followers abonné',
    );
    return '$_temp0 · $following abonnements';
  }

  @override
  String get profileFollowing => 'Abonné';

  @override
  String get profileFollow => 'Suivre';

  @override
  String get profileRunsEmptySelf =>
      'Vous n\'avez pas encore partagé de course.';

  @override
  String get profileRunsEmptyOther => 'Aucune course publique pour le moment.';

  @override
  String get profileFollowersEmpty => 'Aucun abonné pour le moment.';

  @override
  String get profileFollowingEmpty => 'Vous ne suivez personne.';

  @override
  String profileLoadMore(int count) {
    return 'Charger $count de plus';
  }

  @override
  String get profileLoadMoreFollowersFailed =>
      'Impossible de charger plus d\'abonnés';

  @override
  String get profileLoadMoreFollowingFailed =>
      'Impossible de charger plus d\'abonnements';

  @override
  String profileFollowUpdateFailed(String error) {
    return 'Impossible de mettre à jour l\'abonnement : $error';
  }

  @override
  String profileBlockConfirmTitle(String name) {
    return 'Bloquer $name ?';
  }

  @override
  String get profileBlockConfirmBody =>
      'Cette personne ne pourra plus vous suivre, donner des kudos à vos courses ni les commenter. Tout abonnement existant entre vous dans un sens ou l\'autre sera supprimé. Vous pouvez débloquer depuis cette page à tout moment.';

  @override
  String get profileBlockConfirmAction => 'Bloquer';

  @override
  String get profileCancel => 'Annuler';

  @override
  String get profileThisRunner => 'ce coureur';

  @override
  String get profileRunnerNoun => 'coureur';

  @override
  String profileBlocked(String name) {
    return '$name bloqué';
  }

  @override
  String profileBlockFailed(String error) {
    return 'Échec du blocage : $error';
  }

  @override
  String profileUnblocked(String name) {
    return '$name débloqué';
  }

  @override
  String profileUnblockFailed(String error) {
    return 'Échec du déblocage : $error';
  }

  @override
  String get profileNotifAll => 'Toutes';

  @override
  String get profileNotifUnread => 'Non lues';

  @override
  String get profileMarkAllRead => 'Tout marquer comme lu';

  @override
  String profileMarkAllReadFailed(String error) {
    return 'Échec du marquage comme lu : $error';
  }

  @override
  String get profileNotifsCaughtUp => 'Vous êtes à jour.';

  @override
  String get profileNotifsEmpty => 'Aucune notification pour le moment.';

  @override
  String get profileDismiss => 'Ignorer';

  @override
  String profileDismissFailed(String error) {
    return 'Échec du rejet : $error';
  }

  @override
  String get profileNotifSomeone => 'Quelqu\'un';

  @override
  String get profileNotifYourRun => 'votre course';

  @override
  String profileNotifKudos(String name, String dist) {
    return '$name a donné des kudos à votre $dist';
  }

  @override
  String profileNotifComment(String name, String dist) {
    return '$name a commenté votre $dist';
  }

  @override
  String profileNotifCommentReply(String name) {
    return '$name a répondu à votre commentaire';
  }

  @override
  String profileNotifFollow(String name) {
    return '$name a commencé à vous suivre';
  }

  @override
  String profileNotifEventRsvpTitled(String name, String title) {
    return '$name a confirmé sa présence à votre événement « $title »';
  }

  @override
  String profileNotifEventRsvp(String name) {
    return '$name a confirmé sa présence à votre événement';
  }

  @override
  String profileNotifPlanUpdate(String name) {
    return '$name a mis à jour votre plan d\'entraînement';
  }

  @override
  String profileNotifMessage(String name) {
    return '$name vous a envoyé un message';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$name a publié dans $club';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$name a publié dans un club dont vous êtes membre';
  }

  @override
  String profileNotifRunCompletedDist(String name, String dist) {
    return '$name a terminé une course de $dist';
  }

  @override
  String profileNotifRunCompleted(String name) {
    return '$name a terminé une course';
  }

  @override
  String profileNotifGeneric(String name) {
    return '$name a interagi avec votre activité';
  }

  @override
  String get socialTabFeed => 'Fil';

  @override
  String get socialTabPeople => 'Personnes';

  @override
  String get socialTabClubs => 'Clubs';

  @override
  String get socialTabRoutes => 'Itinéraires';

  @override
  String get socialTabDiscover => 'Découvrir';

  @override
  String get discoverSearchPlaceholder =>
      'Rechercher yoga, pilates, HIIT, clubs de course…';

  @override
  String get discoverActivityAll => 'Toutes les activités';

  @override
  String get discoverCadenceLabel => 'Fréquence';

  @override
  String get discoverCadenceAny => 'Toute fréquence';

  @override
  String get discoverOneOff => 'Ponctuel';

  @override
  String get discoverWeekly => 'Hebdomadaire';

  @override
  String get discoverBiweekly => 'Toutes les 2 semaines';

  @override
  String get discoverMonthly => 'Mensuel';

  @override
  String get discoverDayLabel => 'Jour';

  @override
  String get discoverDayAny => 'N\'importe quel jour';

  @override
  String get discoverDayMon => 'Lun';

  @override
  String get discoverDayTue => 'Mar';

  @override
  String get discoverDayWed => 'Mer';

  @override
  String get discoverDayThu => 'Jeu';

  @override
  String get discoverDayFri => 'Ven';

  @override
  String get discoverDaySat => 'Sam';

  @override
  String get discoverDaySun => 'Dim';

  @override
  String get discoverTimeLabel => 'Moment de la journée';

  @override
  String get discoverTimeAny => 'N\'importe quand';

  @override
  String get discoverMorning => 'Matin';

  @override
  String get discoverAfternoon => 'Après-midi';

  @override
  String get discoverEvening => 'Soir';

  @override
  String get discoverPriceLabel => 'Prix';

  @override
  String get discoverPriceAny => 'Tout prix';

  @override
  String get discoverFree => 'Gratuit';

  @override
  String get discoverPaid => 'Payant';

  @override
  String get discoverLoading => 'Recherche…';

  @override
  String get discoverEmpty =>
      'Aucune activité publique ne correspond à ces filtres pour l\'instant.';

  @override
  String get discoverSearchFailed =>
      'Impossible de charger les activités. Vérifiez votre connexion et réessayez.';

  @override
  String get clubsTitle => 'Clubs';

  @override
  String get clubsFindPeople => 'Trouver des gens';

  @override
  String get clubsNewClub => 'Nouveau club';

  @override
  String get clubsTabBrowse => 'Parcourir';

  @override
  String get clubsTabMine => 'Mes clubs';

  @override
  String get clubsJoinWithCode => 'Rejoindre avec un code d\'invitation';

  @override
  String get clubsSearchHint => 'Rechercher par nom ou lieu';

  @override
  String get clubsTimeoutError =>
      'Délai de connexion dépassé. Vérifiez votre réseau et réessayez.';

  @override
  String get clubsLoadError =>
      'Impossible de charger les clubs. Appuyez sur Réessayer.';

  @override
  String get clubsBadgePrivate => 'PRIVÉ';

  @override
  String clubsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '$count membre',
    );
    return '$_temp0';
  }

  @override
  String get clubsEmptyBrowseTitle =>
      'Aucun club ne correspond à cette recherche.';

  @override
  String get clubsEmptyMineTitle => 'Vous n\'avez encore rejoint aucun club.';

  @override
  String get clubsEmptyBrowseBody => 'Essayez un autre nom ou lieu.';

  @override
  String get clubsEmptyMineBody => 'Allez dans Parcourir pour en trouver un.';

  @override
  String get clubDetailTabFeed => 'Fil';

  @override
  String get clubDetailTabEvents => 'Événements';

  @override
  String get clubDetailTabMembers => 'Membres';

  @override
  String get clubDetailTabRoutes => 'Itinéraires';

  @override
  String get clubDetailTabTemplates => 'Modèles';

  @override
  String get clubDetailTabPhotos => 'Photos';

  @override
  String get clubDetailReportClub => 'Signaler le club';

  @override
  String get clubDetailReportPost => 'Signaler cette publication';

  @override
  String get clubDetailLoadFailedTitle => 'Impossible de charger ce club.';

  @override
  String get clubDetailLoadFailedBody =>
      'Il a peut-être été supprimé, ou votre session doit être actualisée. Tirez pour réessayer, ou déconnectez-vous et reconnectez-vous depuis les Réglages.';

  @override
  String get clubDetailRetry => 'Réessayer';

  @override
  String get clubDetailTimeoutError =>
      'Délai de connexion dépassé. Vérifiez votre réseau et réessayez.';

  @override
  String get clubDetailRequestSent => 'Demande envoyée aux administrateurs.';

  @override
  String clubDetailLeaveTitle(String club) {
    return 'Quitter $club ?';
  }

  @override
  String get clubDetailCancel => 'Annuler';

  @override
  String get clubDetailLeave => 'Quitter';

  @override
  String clubDetailReplyFailed(String error) {
    return 'Impossible de publier la réponse : $error';
  }

  @override
  String get clubDetailMemberFallback => 'Membre';

  @override
  String get clubDetailRequestPending => 'Demande en attente';

  @override
  String get clubDetailInviteOnly => 'Sur invitation';

  @override
  String get clubDetailRequest => 'Demander';

  @override
  String get clubDetailJoin => 'Rejoindre';

  @override
  String get clubDetailOwner => 'Propriétaire';

  @override
  String get clubDetailNextEvent => 'PROCHAIN ÉVÉNEMENT';

  @override
  String clubDetailGoingCount(int count) {
    return '$count participants';
  }

  @override
  String get clubDetailNoPostsMember =>
      'Aucune publication. Partagez une mise à jour avec les membres.';

  @override
  String get clubDetailNoPosts => 'Aucune mise à jour pour le moment.';

  @override
  String get clubDetailShareUpdateHint => 'Partager une mise à jour…';

  @override
  String get clubDetailPost => 'Publier';

  @override
  String get clubDetailReply => 'Répondre';

  @override
  String clubDetailHideReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Masquer $count réponses',
      one: 'Masquer $count réponse',
    );
    return '$_temp0';
  }

  @override
  String clubDetailShowReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count réponses',
      one: '$count réponse',
    );
    return '$_temp0';
  }

  @override
  String clubDetailReplyAuthorLine(String name, String time) {
    return '$name · $time';
  }

  @override
  String get clubDetailWriteReplyHint => 'Écrire une réponse…';

  @override
  String get clubDetailSend => 'Envoyer';

  @override
  String get clubDetailNoEventsAdmin =>
      'Aucun événement à venir. Appuyez sur Créer pour en ajouter un.';

  @override
  String get clubDetailNoEvents => 'Aucun événement à venir.';

  @override
  String get clubDetailCreateEvent => 'Créer un événement';

  @override
  String get clubDetailGoing => 'Présent';

  @override
  String clubDetailApproveFailed(String error) {
    return 'Échec de l\'approbation : $error';
  }

  @override
  String clubDetailDenyFailed(String error) {
    return 'Échec du refus : $error';
  }

  @override
  String clubDetailPendingRequests(int count) {
    return 'Demandes en attente ($count)';
  }

  @override
  String clubDetailUserShort(String id) {
    return 'Utilisateur $id…';
  }

  @override
  String get clubDetailDeny => 'Refuser';

  @override
  String get clubDetailApprove => 'Approuver';

  @override
  String clubDetailMemberCountLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres.',
      one: '$count membre.',
    );
    return '$_temp0';
  }

  @override
  String clubDetailRouteSaved(String name) {
    return '« $name » enregistré';
  }

  @override
  String get clubDetailBuildRoute => 'Créer un itinéraire pour ce club';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'Aucun itinéraire pour le moment. Créez le parcours officiel ci-dessus, ou transférez l\'un de vos itinéraires personnels depuis la page de détail.';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'Aucun itinéraire. Les administrateurs peuvent transférer l\'un de leurs itinéraires personnels depuis la page de détail.';

  @override
  String get clubDetailRoutesEmpty =>
      'Aucun itinéraire partagé avec ce club pour le moment.';

  @override
  String get clubDetailTemplateAdded => 'Modèle ajouté à vos plans.';

  @override
  String clubDetailAdoptFailed(String error) {
    return 'Échec de l\'adoption : $error';
  }

  @override
  String get clubDetailNoTemplatesAdmin =>
      'Aucun modèle pour le moment. Publiez l\'un de vos plans depuis sa page de détail.';

  @override
  String get clubDetailNoTemplates =>
      'Aucun modèle de plan pour ce club pour le moment.';

  @override
  String get clubDetailAdopt => 'Adopter';

  @override
  String get clubDetailSessionTemplatesTitle => 'Modèles de séance';

  @override
  String get clubDetailSessionAdopted => 'Séance ajoutée à vos plans.';

  @override
  String get clubDetailGymRoutineTemplatesTitle => 'Modèles de routine de gym';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'Les membres peuvent adopter une routine de gym du club dans leurs propres routines. Les modifications d\'une copie ne se répercutent pas sur le modèle.';

  @override
  String get clubDetailGymRoutineAdopted =>
      'Routine ajoutée à vos routines de gym.';

  @override
  String clubDetailRoutineExerciseCount(int n) {
    return '$n exercices';
  }

  @override
  String get eventNotFound => 'Événement introuvable.';

  @override
  String get eventLoadError =>
      'Impossible de charger cet événement. Appuyez sur Réessayer.';

  @override
  String get eventTimeoutError =>
      'Délai de connexion dépassé. Vérifiez votre réseau et réessayez.';

  @override
  String eventDurationMin(int minutes) {
    return '· $minutes min';
  }

  @override
  String eventGetDirectionsTo(String label) {
    return 'Itinéraire vers $label';
  }

  @override
  String get eventGetDirections => 'Obtenir l\'itinéraire';

  @override
  String get eventCouldNotOpenMaps => 'Impossible d\'ouvrir la carte.';

  @override
  String get eventPickOccurrence => 'CHOISIR UNE OCCURRENCE';

  @override
  String get eventTargetPace => 'Allure cible';

  @override
  String get eventClassSessionEyebrow => 'COURS';

  @override
  String get eventResultSubmitted => 'Résultat soumis.';

  @override
  String eventSubmitFailed(String error) {
    return 'Échec de l\'envoi : $error';
  }

  @override
  String eventRaceControlFailed(String error) {
    return 'Échec du contrôle de course : $error';
  }

  @override
  String eventAttendees(int count) {
    return 'PARTICIPANTS ($count)';
  }

  @override
  String get eventNoRsvps =>
      'Aucune réponse pour le moment — soyez le premier.';

  @override
  String get eventAttendeeMember => 'Membre';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventMarkAttended => 'Marquer comme présent';

  @override
  String get eventMarkNoShow => 'Marquer comme absent';

  @override
  String get eventAttendanceAttended => 'Présent';

  @override
  String get eventAttendanceNoShow => 'Absent';

  @override
  String get eventAttendanceFailed =>
      'Impossible de mettre à jour la présence. Veuillez réessayer.';

  @override
  String get eventRsvpFailed =>
      'Impossible de mettre à jour ta réponse. Veuillez réessayer.';

  @override
  String get eventRsvpGoing => 'Je viens';

  @override
  String get eventRsvpMaybe => 'Peut-être';

  @override
  String get eventRsvpDeclined => 'Pas dispo';

  @override
  String get eventRaceArmed => 'Armé — en attente du GO';

  @override
  String get eventRaceRunning => 'En cours — en direct';

  @override
  String get eventRaceFinished => 'Terminé';

  @override
  String get eventRaceCancelled => 'Annulé';

  @override
  String get eventRaceNotArmed => 'Non armé';

  @override
  String get eventRaceControlLabel => 'CONTRÔLE DE COURSE';

  @override
  String get eventRaceAutoApprove =>
      'Approuver automatiquement les temps soumis';

  @override
  String get eventRaceArm => 'Armer la course';

  @override
  String get eventRaceArmedHint =>
      'Appuyez sur Lancer le Go quand la course commence. Les montres des participants affichent maintenant la bannière « armé ».';

  @override
  String get eventRaceFireGo => 'Lancer le Go';

  @override
  String get eventRaceCancel => 'Annuler';

  @override
  String eventRaceStartedAt(String time) {
    return 'Démarrée à $time';
  }

  @override
  String get eventRaceEnd => 'Terminer la course';

  @override
  String get eventRaceCancelRace => 'Annuler la course';

  @override
  String get eventRaceEndConfirmBody =>
      'Terminer la course ? Cela finalise l\'épreuve pour tous les coureurs et est irréversible.';

  @override
  String get eventRaceCancelConfirmBody =>
      'Annuler la course ? Cela interrompt l\'épreuve pour tous les coureurs et est irréversible.';

  @override
  String get eventUpdatePosted => 'Mise à jour publiée dans le fil du club.';

  @override
  String eventPostUpdateFailed(String error) {
    return 'Impossible de publier la mise à jour : $error';
  }

  @override
  String get eventPostUpdateLabel => 'PUBLIER UNE MISE À JOUR';

  @override
  String get eventUpdateHint =>
      'Décision météo ? Rendez-vous à un autre endroit ?';

  @override
  String get eventPostUpdate => 'Publier la mise à jour';

  @override
  String get eventResultsTitle => 'Résultats';

  @override
  String get eventRemoveMine => 'Supprimer le mien';

  @override
  String get eventRemoveResultTitle => 'Supprimer votre résultat ?';

  @override
  String get eventRemoveResultBody =>
      'Votre temps d\'arrivée soumis sera retiré du classement de cet événement. Vous pourrez le soumettre à nouveau plus tard.';

  @override
  String get eventRemoveResultConfirm => 'Supprimer le résultat';

  @override
  String eventRemoveResultFailed(String error) {
    return 'Impossible de supprimer votre résultat : $error';
  }

  @override
  String get eventSubmitMyTime => 'Soumettre mon temps';

  @override
  String get eventSubmitting => 'Envoi…';

  @override
  String get eventNoResults =>
      'Aucun résultat pour le moment. Soumettez votre temps après l\'événement et les autres le verront ici.';

  @override
  String get eventResultRunner => 'Coureur';

  @override
  String get eventResultYou => '(vous)';

  @override
  String get eventSubmitTimeTitle => 'Soumettez votre temps';

  @override
  String get eventSubmitTimeSubtitle =>
      'Choisissez une course à associer, ou enregistrez un DNF / DNS.';

  @override
  String get eventNoRecentRuns =>
      'Aucune course récente trouvée. Enregistrez d\'abord une course, puis revenez.';

  @override
  String get eventRecordDnf => 'Enregistrer un DNF';

  @override
  String get eventRecordDns => 'Enregistrer un DNS';

  @override
  String get eventSubmitCancel => 'Annuler';

  @override
  String get liveSpectatorTitle => 'Suivi en direct';

  @override
  String get liveSpectatorConnectError => 'Connexion impossible.';

  @override
  String get liveSpectatorWaiting => 'En attente du premier signal du coureur…';

  @override
  String get liveSpectatorBadgeLive => 'En direct';

  @override
  String get liveSpectatorBadgeIdle => 'Inactif';

  @override
  String get liveSpectatorBadgeConnecting => 'Connexion';

  @override
  String get liveSpectatorBadgeStale => 'Retardé';

  @override
  String get liveSpectatorBadgeApproximate => 'Approximatif';

  @override
  String get liveSpectatorApproximateSub =>
      'Vu pour la dernière fois près d\'ici — approximatif';

  @override
  String get liveSpectatorBadgeFinished => 'Terminé';

  @override
  String get liveSpectatorBadgeDnf => 'DNF';

  @override
  String get liveUpdatedNow => 'Mis à jour à l\'instant';

  @override
  String liveUpdatedSeconds(int n) {
    return 'Mis à jour il y a ${n}s';
  }

  @override
  String liveUpdatedMinutes(int n) {
    return 'Mis à jour il y a $n min';
  }

  @override
  String liveUpdatedHours(int n) {
    return 'Mis à jour il y a $n h';
  }

  @override
  String liveUpdatedDays(int n) {
    return 'Mis à jour il y a $n j';
  }

  @override
  String get liveCutoffTitle => 'Prochaine barrière horaire';

  @override
  String liveCutoffToGo(String distance) {
    return 'Encore $distance';
  }

  @override
  String liveCutoffEta(String eta) {
    return 'Arrivée prévue $eta';
  }

  @override
  String liveCutoffAhead(String margin) {
    return '$margin de marge';
  }

  @override
  String liveCutoffBehind(String margin) {
    return '$margin de retard';
  }

  @override
  String get liveCutoffWaitingSignal =>
      'En attente d\'un signal récent pour estimer l\'arrivée';

  @override
  String get plansTitle => 'Plans d\'entraînement';

  @override
  String get plansNewPlan => 'Nouveau plan';

  @override
  String plansDeleteTitle(String name) {
    return 'Supprimer « $name » ?';
  }

  @override
  String get plansDeleteBody =>
      'Toutes les semaines et séances seront supprimées.';

  @override
  String get plansCancel => 'Annuler';

  @override
  String get plansDelete => 'Supprimer';

  @override
  String get plansAbandon => 'Abandonner';

  @override
  String plansAbandonTitle(String name) {
    return 'Abandonner « $name » ?';
  }

  @override
  String get plansAbandonBody => 'Tu pourras créer un nouveau plan ensuite.';

  @override
  String plansActionFailed(String error) {
    return 'Impossible de mettre à jour le plan : $error';
  }

  @override
  String plansDaysPerWeek(int count) {
    return '$count jours/sem.';
  }

  @override
  String get plansSignInTitle =>
      'Connectez-vous pour utiliser les plans d\'entraînement';

  @override
  String get plansSignInBody =>
      'Les plans se synchronisent avec votre compte et vous suivent sur tous vos appareils. Allez dans Réglages → Se connecter pour vous connecter.';

  @override
  String get plansEmptyTitle => 'Aucun plan pour l\'instant.';

  @override
  String get plansEmptyBody =>
      'Choisissez une course objectif et nous planifierons les semaines pour vous.';

  @override
  String get plansTimeoutError =>
      'Délai de connexion dépassé. Vérifiez votre réseau et réessayez.';

  @override
  String get plansLoadError =>
      'Impossible de charger les plans d\'entraînement. Appuyez sur Réessayer.';

  @override
  String get planNewTitle => 'Nouveau plan';

  @override
  String get planNewNameLabel => 'Nom du plan';

  @override
  String get planNewNameHint => 'ex. Semi-marathon d\'automne';

  @override
  String get planNewGoalRace => 'Course objectif';

  @override
  String get planNewStartDate => 'Date de début';

  @override
  String get planNewDaysPerWeek => 'Jours par semaine';

  @override
  String planNewDaysOption(int count) {
    return '$count jours';
  }

  @override
  String get planNewGoalTimeSection => 'Temps objectif · facultatif';

  @override
  String get planNewBeginnerTitle =>
      'Débutant ? Utilisez un plan marche-course';

  @override
  String get planNewBeginnerSubtitle =>
      'Un programme doux de type C25K avec des intervalles course/marche chronométrés menant à une course continue. Remplace l\'allure du temps objectif.';

  @override
  String get planNewRecent5kSection => 'Temps récent sur 5 km · facultatif';

  @override
  String get planNewRecent5kHelp =>
      'Calez les allures sur un résultat réel plutôt que sur l\'objectif. Utilise l\'équivalence de Riegel pour projeter sur la distance objectif.';

  @override
  String get planNewRecent5kConfirm =>
      'C\'est un temps que je pourrais réaliser aujourd\'hui — il reflète ma forme actuelle.';

  @override
  String get planNewRecent5kWarning =>
      'Tant que vous ne confirmez pas, les allures restent sur l\'estimation prudente basée sur l\'objectif. Se baser sur un ancien résultat peut prescrire des allures trop rapides pour un coureur qui reprend.';

  @override
  String get planNewOverrideHint => 'Remplacer le nombre total de semaines';

  @override
  String planNewOverrideLabel(int count) {
    return 'Remplacer les semaines (par défaut : $count)';
  }

  @override
  String get planNewCancel => 'Annuler';

  @override
  String get planNewCreate => 'Créer le plan';

  @override
  String get planNewCreating => 'Création…';

  @override
  String get planNewPreviewTitle => 'Aperçu';

  @override
  String get planNewPaceEasy => 'Facile';

  @override
  String get planNewPaceMarathon => 'Marathon';

  @override
  String get planNewPaceTempo => 'Tempo';

  @override
  String get planNewPaceInterval => 'Intervalle';

  @override
  String get planNewPaceRep => 'Répétition';

  @override
  String get planNewPacesFallback =>
      'Allures estimées — ajoutez une course récente ou un temps objectif pour des cibles personnalisées.';

  @override
  String planNewVdot(String value) {
    return 'VDOT de Daniels : $value';
  }

  @override
  String get planNewWeekOutline => 'Aperçu des semaines';

  @override
  String planNewMoreWeeks(int count) {
    return '+ $count semaines de plus';
  }

  @override
  String planNewSessions(int count) {
    return '$count séances';
  }

  @override
  String get planNewTemplateTitle => 'Partir d’un modèle de club';

  @override
  String get planNewTemplateSubtitle =>
      'Adoptez un plan publié par un club dont vous faites partie. Il est cloné dans votre compte avec la date de début ci-dessous — modifiable comme tout autre plan.';

  @override
  String get planNewTemplateButton => 'Parcourir les modèles';

  @override
  String get planNewTemplateCloning => 'Adoption…';

  @override
  String planNewTemplateCloneFailed(String error) {
    return 'Impossible d’adopter ce modèle : $error';
  }

  @override
  String get planNewTemplatePickerTitle => 'Choisir un modèle';

  @override
  String get planNewTemplatePickerCancel => 'Annuler';

  @override
  String get planLibraryTitle => 'Bibliothèque publique de plans';

  @override
  String get planLibrarySubheading =>
      'Plans publiés par d\'autres coureurs. Clonez-en un dans votre compte pour commencer à vous entraîner.';

  @override
  String get planLibrarySearchHint => 'Rechercher des plans par nom';

  @override
  String get planLibraryLoadError =>
      'Impossible de charger la bibliothèque. Réessayer.';

  @override
  String get planLibraryRetry => 'Réessayer';

  @override
  String get planLibraryEmpty => 'Aucun plan publié pour l\'instant.';

  @override
  String planLibraryEmptySearch(String query) {
    return 'Aucun plan ne correspond à « $query ».';
  }

  @override
  String planLibraryByAuthor(String author) {
    return 'par $author';
  }

  @override
  String get planLibraryAnonymous => 'un coureur';

  @override
  String planLibraryWeeks(int weeks) {
    return '$weeks semaines';
  }

  @override
  String planLibraryDaysPerWeek(int days) {
    return '$days×/semaine';
  }

  @override
  String get planLibraryClone => 'Cloner dans mes plans';

  @override
  String get planLibraryCloning => 'Clonage…';

  @override
  String get planLibraryCloneSuccess => 'Plan cloné.';

  @override
  String planLibraryCloneFailed(String error) {
    return 'Échec du clonage : $error';
  }

  @override
  String get planLibraryStartDate => 'Date de début';

  @override
  String get planLibraryNotFound =>
      'Ce plan n\'est plus dans la bibliothèque publique.';

  @override
  String get planLibraryPreviewWeeks => 'Semaines';

  @override
  String planLibraryPreviewWeek(int n) {
    return 'Semaine $n';
  }

  @override
  String get planDetailPublishLibraryLabel => 'Bibliothèque publique de plans';

  @override
  String get planDetailPublishLibrary => 'Publier dans la bibliothèque';

  @override
  String get planDetailPublishLibraryHint =>
      'Partagez une copie de ce plan pour que chacun puisse le cloner. Vos données de forme ne sont pas partagées.';

  @override
  String get planDetailPublishLibrarySuccess =>
      'Plan publié dans la bibliothèque publique. Votre plan personnel est inchangé.';

  @override
  String planDetailPublishLibraryFailed(String error) {
    return 'Échec de la publication : $error';
  }

  @override
  String get planDetailUnpublishLibrary => 'Retirer';

  @override
  String get planDetailUnpublishSuccess =>
      'Retiré de la bibliothèque publique.';

  @override
  String planDetailUnpublishFailed(String error) {
    return 'Échec du retrait : $error';
  }

  @override
  String get planDetailAlreadyPublished =>
      'Ce plan est dans la bibliothèque publique.';

  @override
  String get plansBrowseLibrary => 'Parcourir la bibliothèque';

  @override
  String get planNewStarterTitle => 'Partir d\'un plan intégré';

  @override
  String get planNewStarterSubtitle =>
      'Choisis un plan d\'entraînement éprouvé — nous le planifions à partir de ta date de début ; tu pourras l\'ajuster ensuite.';

  @override
  String get planNewStarterButton => 'Parcourir les plans de départ';

  @override
  String get planNewStarterCreating => 'Création…';

  @override
  String get planNewStarterPickerTitle => 'Choisir un plan de départ';

  @override
  String get planNewStarterPickerCancel => 'Annuler';

  @override
  String planNewStarterCreateFailed(String error) {
    return 'Impossible de créer ce plan : $error';
  }

  @override
  String get planNewStarterC25k => 'Couch to 5K (débutant marche-course)';

  @override
  String get planNewStarterHalf12 => 'Semi-marathon — 12 semaines';

  @override
  String get planNewStarterMarathon16 => 'Marathon — 16 semaines';

  @override
  String get planDetailTimeoutError =>
      'Délai de connexion dépassé. Vérifiez votre réseau et réessayez.';

  @override
  String get planDetailLoadError =>
      'Impossible de charger ce plan. Appuyez sur Réessayer.';

  @override
  String get planDetailNotFound => 'Plan introuvable.';

  @override
  String get planDetailLongestLongRun => 'Sortie longue la plus longue';

  @override
  String get planDetailPublishTooltip => 'Publier comme modèle de club';

  @override
  String planDetailDaysPerWeek(int count) {
    return '$count jours/sem.';
  }

  @override
  String get planDetailCurrentWeek => 'Cette semaine';

  @override
  String get planDetailToday => 'AUJOURD\'HUI';

  @override
  String get planDetailCompleted => 'Terminé';

  @override
  String planDetailWeek(int number) {
    return 'Semaine $number';
  }

  @override
  String planDetailDriftOverFlag(int pct) {
    return '$pct% au-dessus du plan cette semaine — lève le pied les jours faciles pour ne pas creuser un trou de fatigue.';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return '$pct% en dessous du plan cette semaine — le volume prévu pilote l’adaptation.';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      'Tu as manqué la sortie longue de la semaine — caser-la si possible. C’est la séance la plus importante.';

  @override
  String get planDetailMissedLongTaper =>
      'Tu as manqué une sortie longue, mais tu es en affûtage — laisse tomber et reste frais pour la course.';

  @override
  String get planDetailMissedLongRecovery =>
      'Tu as manqué une sortie longue — n’essaie pas de la rattraper. Une semaine de récupération arrive et ton corps en profitera.';

  @override
  String get planDetailReplan => 'Replanifier les semaines restantes';

  @override
  String get planDetailAdaptiveReplan => 'Re-planification adaptative';

  @override
  String get planDetailAdaptiveOnTrack =>
      'Tes dernières semaines sont conformes au plan — aucun ajustement nécessaire.';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      'Tu as récemment dévié du plan, mais aucun ajustement sûr n\'est possible pour l\'instant.';

  @override
  String get planDetailAdaptiveFitnessHeld =>
      'Mis en pause — tu accumules de la fatigue en ce moment, augmenter le volume n\'est pas conseillé.';

  @override
  String get planDetailAdaptiveReasonUnder =>
      'en dessous de ton plan depuis plusieurs semaines';

  @override
  String get planDetailAdaptiveReasonOver =>
      'au-dessus de ton plan depuis plusieurs semaines';

  @override
  String get planDetailAdaptiveConfidenceHigh => 'confiance élevée';

  @override
  String get planDetailAdaptiveConfidenceMedium => 'confiance moyenne';

  @override
  String planDetailAdaptiveBadge(String reason, String confidence) {
    return 'D\'après une tendance — tu as été $reason ($confidence)';
  }

  @override
  String get planDetailReplanOnTrack =>
      'Ton plan est sur la bonne voie — rien à ajuster.';

  @override
  String planDetailReplanApplied(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n séances ajustées',
      one: '1 séance ajustée',
    );
    return '$_temp0';
  }

  @override
  String get planDetailReplanPreviewTitle => 'Changements proposés';

  @override
  String planDetailReplanMakeUp(String from, String to) {
    return 'Sortie longue $from → $to — rattraper une sortie longue manquée';
  }

  @override
  String planDetailReplanEase(String from, String to) {
    return '$from → $to — alléger après un excès de volume';
  }

  @override
  String get planDetailReplanCancel => 'Annuler';

  @override
  String get planDetailReplanApply => 'Appliquer les changements';

  @override
  String get planDetailDuplicateWeek => 'Dupliquer la semaine';

  @override
  String planDetailDuplicateWeekDone(int n) {
    return 'Semaine $n dupliquée';
  }

  @override
  String planDetailBulkFailed(String error) {
    return 'Impossible de mettre à jour le plan : $error';
  }

  @override
  String get planDetailEditTooltip => 'Modifier la séance';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'Impossible de charger vos clubs — vérifiez votre réseau.';

  @override
  String get planDetailPublishLoadClubsFailed =>
      'Impossible de charger vos clubs.';

  @override
  String get planDetailPublishNoClubs =>
      'Vous devez être propriétaire ou administrateur d\'un club pour publier un modèle.';

  @override
  String planDetailPublishSuccess(String name) {
    return '« $name » publié comme modèle de club.';
  }

  @override
  String planDetailPublishFailed(String error) {
    return 'Échec de la publication : $error';
  }

  @override
  String get planDetailPublishPickerTitle => 'Publier dans un club';

  @override
  String get planDetailPublishPickerBody =>
      'Les membres du club pourront adopter ce plan comme le leur.';

  @override
  String planDetailPublishPickerMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '$count membre',
    );
    return '$_temp0';
  }

  @override
  String get planDetailPublishCancel => 'Annuler';

  @override
  String get workoutTimeoutError =>
      'Délai de connexion dépassé. Vérifiez votre réseau et réessayez.';

  @override
  String get workoutLoadError =>
      'Impossible de charger cette séance. Appuyez sur Réessayer.';

  @override
  String get workoutNotFound => 'Séance introuvable.';

  @override
  String get workoutMetricDistance => 'Distance';

  @override
  String get workoutMetricDuration => 'Durée';

  @override
  String get workoutMetricTargetPace => 'Allure cible';

  @override
  String get workoutCompleted => 'Terminé';

  @override
  String get workoutUnlink => 'Dissocier';

  @override
  String get workoutUnlinkTitle => 'Dissocier la course';

  @override
  String get workoutUnlinkBody =>
      'Dissocier la course associée ? La séance réapparaîtra comme non effectuée.';

  @override
  String get workoutUnlinkError =>
      'Impossible de dissocier la course. Réessayez.';

  @override
  String get workoutSkipped => 'Ignoré';

  @override
  String get workoutSkip => 'Ignorer cette séance';

  @override
  String get workoutUnskip => 'Annuler l\'ignorance';

  @override
  String get workoutSkipError =>
      'Impossible de mettre à jour l\'ignorance. Réessayez.';

  @override
  String get workoutRelink => 'Réassocier';

  @override
  String get workoutRelinkTitle => 'Associer une autre course';

  @override
  String get workoutRelinkHint =>
      'Choisissez une course proche de la date de cette séance pour la compter comme cette séance. Les courses déjà associées à une autre séance ne sont pas affichées.';

  @override
  String get workoutRelinkLoading => 'Recherche de vos courses…';

  @override
  String get workoutRelinkError =>
      'Impossible de charger vos courses. Réessayez.';

  @override
  String get workoutRelinkEmpty => 'Aucune course éligible près de cette date.';

  @override
  String get workoutRelinkCurrent => 'Actuelle';

  @override
  String get workoutStart => 'Démarrer la séance';

  @override
  String get workoutSectionNotes => 'Notes';

  @override
  String get workoutSectionStructure => 'Structure';

  @override
  String get workoutSectionHowTo => 'Comment la courir';

  @override
  String get workoutStructWarmup => 'Échauffement';

  @override
  String get workoutStructRepeats => 'Répétitions';

  @override
  String get workoutStructSteady => 'Régulier';

  @override
  String get workoutStructCooldown => 'Récupération';

  @override
  String workoutStructWarmupValue(String distance) {
    return '$distance @ facile';
  }

  @override
  String workoutStructCooldownValue(String distance) {
    return '$distance @ facile';
  }

  @override
  String get workoutAdviceEasy =>
      'Allure de conversation. Si vous ne pouvez pas tenir une conversation, vous courez trop vite.';

  @override
  String get workoutAdviceLong =>
      'Restez détendu. Visez une respiration régulière. Réduisez la distance de 10 % si le temps est mauvais ou si vous êtes courbaturé — ne sautez pas la séance.';

  @override
  String get workoutAdviceTempo =>
      '« Confortablement difficile ». Vous devez sentir que vous pourriez tenir l\'allure environ une heure à effort maximal, mais pas plus.';

  @override
  String get workoutAdviceInterval =>
      'Courez les répétitions assez fort pour que la dernière ressemble à la première. Ne choisissez pas une allure que vous ne pouvez tenir que deux ou trois répétitions.';

  @override
  String get workoutAdviceMarathonPace =>
      'Calez-vous exactement sur l\'allure marathon objectif. C\'est une répétition — ni plus vite, ni plus lentement.';

  @override
  String get workoutAdviceWalkRun =>
      'Alternez course facile et marche sur les intervalles chronométrés. Les pauses de marche font partie de la séance — prenez-les même si vous vous sentez en forme.';

  @override
  String get workoutAdviceRace =>
      'Faites confiance au plan. Ne courez pas après un record dès le premier kilomètre.';

  @override
  String get workoutAdviceRest =>
      'Jour de repos — si vous devez bouger, marchez ou étirez-vous.';

  @override
  String get coachTitle => 'Coach';

  @override
  String get coachNewConversation => 'Nouvelle conversation';

  @override
  String get coachConsentHeadline => 'Avant de discuter avec Coach';

  @override
  String get coachConsentIntro =>
      'Pour vous donner des conseils pertinents, Coach transmet une partie de vos données d\'entraînement à Anthropic, notre fournisseur de modèles d\'IA aux États-Unis. Cette partie comprend :';

  @override
  String get coachConsentBulletProfile =>
      'Votre date de naissance, votre sexe et vos zones de FC si elles sont définies.';

  @override
  String get coachConsentBulletRuns =>
      'Un échantillon de vos courses les plus récentes.';

  @override
  String get coachConsentBulletPlan =>
      'Le plan d\'entraînement actif que vous avez sélectionné.';

  @override
  String get coachConsentBulletMessages =>
      'Les messages que vous tapez dans l\'écran ci-dessous.';

  @override
  String get coachConsentProcessing =>
      'Anthropic traite les données pour le compte de Threkir selon ses conditions de traitement ; par défaut, ils n\'entraînent pas leurs modèles sur les données clients de Threkir. Tous les détails — y compris le mécanisme de transfert, la conservation et vos droits de retrait — figurent dans notre politique de confidentialité.';

  @override
  String get coachConsentAction =>
      'Appuyez sur « J\'accepte » pour continuer. Appuyez sur Annuler pour quitter la page sans envoyer de données.';

  @override
  String get coachConsentCancel => 'Annuler';

  @override
  String get coachConsentAccept => 'J\'accepte — démarrer Coach';

  @override
  String get coachConsentSaving => 'Enregistrement du consentement…';

  @override
  String get coachNoPlanOption => 'Aucun plan (courses récentes uniquement)';

  @override
  String coachPlanActive(String name) {
    return '$name · actif';
  }

  @override
  String coachPlanDone(String name) {
    return '$name · terminé';
  }

  @override
  String get coachNewChatTooltip => 'Nouveau chat';

  @override
  String get coachHistoryTooltip => 'Historique des chats';

  @override
  String get coachNewChat => 'Nouveau chat';

  @override
  String coachActiveThread(String suffix) {
    return 'Actif$suffix';
  }

  @override
  String get coachArchiveTapToView =>
      'Toucher pour voir · glisser pour supprimer';

  @override
  String get coachContextNoPlan => 'Aucun plan';

  @override
  String coachContextPlanWeeks(String name, int weeks) {
    return '$name · $weeks sem.';
  }

  @override
  String get coachContextNoRuns => 'Aucune course';

  @override
  String get coachContextLast => 'Dernières';

  @override
  String get coachContextHr => 'FC';

  @override
  String coachContextWeeklyGoal(String km) {
    return '$km km/sem.';
  }

  @override
  String coachArchiveBanner(String label) {
    return 'Consultation des archives · $label · lecture seule';
  }

  @override
  String get coachBackToActive => 'Retour à l\'actif';

  @override
  String get coachLimitReachedPro =>
      'Limite quotidienne atteinte. Revenez demain.';

  @override
  String get coachLimitReachedFree =>
      'Limite quotidienne atteinte. Pro offre un plafond plus élevé — passez à Pro dans les Réglages.';

  @override
  String coachMessagesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages restants aujourd\'hui',
      one: '$count message restant aujourd\'hui',
    );
    return '$_temp0';
  }

  @override
  String get coachEmptyPromptPlan =>
      'Posez des questions sur la séance du jour, votre allure ou la comparaison de vos courses récentes au plan.';

  @override
  String get coachEmptyPromptNoPlan =>
      'Posez des questions sur vos courses récentes, l\'allure des sorties faciles ou les bases de l\'entraînement.';

  @override
  String get coachSuggestPlanRest =>
      'Dois-je courir demain ou prendre un jour de repos ?';

  @override
  String get coachSuggestPlanOnTrack =>
      'Suis-je en bonne voie pour mon temps objectif ?';

  @override
  String get coachSuggestPlanLongRun =>
      'Pourquoi la sortie longue de cette semaine est-elle importante ?';

  @override
  String get coachSuggestPlanToday =>
      'Sur quoi me concentrer pour la séance d\'aujourd\'hui ?';

  @override
  String get coachSuggestNoPlanLastRun =>
      'Comment s\'est passée ma dernière course ?';

  @override
  String get coachSuggestNoPlanEasyPace =>
      'À quelle allure faire mes sorties faciles ?';

  @override
  String get coachSuggestNoPlanWeekOff =>
      'Je n\'ai pas couru depuis une semaine — que faire ?';

  @override
  String get coachSuggestNoPlanTempo => 'Qu\'est-ce qu\'une séance de tempo ?';

  @override
  String get coachEditCancel => 'Annuler';

  @override
  String get coachEditSaveResend => 'Enregistrer et renvoyer';

  @override
  String get coachActionCopy => 'Copier';

  @override
  String get coachActionEdit => 'Modifier';

  @override
  String get coachActionRegenerate => 'Régénérer';

  @override
  String get coachActionHelpful => 'Utile';

  @override
  String get coachActionNotHelpful => 'Pas utile';

  @override
  String get coachComposerHintLimit => 'Limite quotidienne atteinte';

  @override
  String get coachComposerHint => 'Demandez à Coach…';

  @override
  String get coachArchiveTitle => 'Démarrer une nouvelle conversation ?';

  @override
  String get coachArchiveBody =>
      'Le chat actuel passe dans l\'historique. Vous pourrez le retrouver depuis la barre latérale.';

  @override
  String get coachArchiveCancel => 'Annuler';

  @override
  String get coachArchiveConfirm => 'Nouveau chat';

  @override
  String get coachSignInFirst => 'Veuillez d\'abord vous connecter.';

  @override
  String get coachSessionExpired =>
      'Votre session a expiré. Veuillez vous reconnecter.';

  @override
  String coachDailyLimitError(int limit) {
    return 'Limite quotidienne atteinte ($limit messages). Revenez demain !';
  }

  @override
  String coachGenericError(int code) {
    return 'Erreur Coach ($code)';
  }

  @override
  String get coachTransportError =>
      'Impossible de joindre Coach. Vérifiez votre connexion et réessayez.';

  @override
  String get coachStreamFailed => 'échec du flux';

  @override
  String coachNewConversationFailed(String error) {
    return 'Impossible de démarrer une nouvelle conversation : $error';
  }

  @override
  String coachOpenArchiveFailed(String error) {
    return 'Impossible d\'ouvrir l\'archive : $error';
  }

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Impossible de supprimer l\'archive : $error';
  }

  @override
  String get coachCopied => 'Copié dans le presse-papiers';

  @override
  String get settingsAccountTitle => 'Compte';

  @override
  String get settingsAccountBackendNotConfigured => 'Backend non configuré';

  @override
  String get settingsAccountSignOutFailed =>
      'Échec de la déconnexion — vérifie ta connexion';

  @override
  String get settingsAccountChangePassword => 'Changer le mot de passe';

  @override
  String get settingsAccountNewPassword => 'Nouveau mot de passe';

  @override
  String get settingsAccountConfirm => 'Confirmer';

  @override
  String get settingsAccountCancel => 'Annuler';

  @override
  String get settingsAccountSave => 'Enregistrer';

  @override
  String get settingsAccountPasswordTooShort =>
      'Le mot de passe doit comporter au moins 8 caractères';

  @override
  String get settingsAccountPasswordsMismatch =>
      'Les mots de passe ne correspondent pas';

  @override
  String get settingsAccountPasswordUpdated => 'Mot de passe mis à jour';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Impossible de mettre à jour le mot de passe : $error';
  }

  @override
  String get settingsAccountDeleteTitle => 'Supprimer le compte ?';

  @override
  String get settingsAccountDeleteBody =>
      'Cela supprime définitivement tes courses, itinéraires et ton profil du serveur. Les données locales de l\'appareil sont conservées, sauf si tu te connectes en tant que nouvel utilisateur. Cette action est irréversible.';

  @override
  String get settingsAccountDeleteChallengeText =>
      'Tape « DELETE » pour confirmer';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return 'Tape ton e-mail ($email) pour confirmer';
  }

  @override
  String get settingsAccountDelete => 'Supprimer';

  @override
  String get settingsAccountDeleteSignInFirst =>
      'Connecte-toi d\'abord pour supprimer ton compte.';

  @override
  String get settingsAccountDeleted => 'Compte supprimé';

  @override
  String get settingsAccountCoachConsentWithdraw =>
      'Retirer le consentement au Coach';

  @override
  String get settingsAccountCoachConsentActive =>
      'Empêchez le Coach d\'utiliser vos données d\'entraînement. Vous pouvez consentir à nouveau à tout moment.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Consentement au Coach retiré.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Échec du retrait : $error';
  }

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'Échec de la suppression du compte : $error';
  }

  @override
  String get settingsAccountNoRunsToExport => 'Aucune course à exporter.';

  @override
  String get settingsAccountCsvShareText => 'Run app — export des courses';

  @override
  String settingsAccountCsvExportFailed(Object error) {
    return 'Échec de l\'export CSV : $error';
  }

  @override
  String get settingsAccountBackupSignInFirst =>
      'Connecte-toi d\'abord pour sauvegarder tes courses.';

  @override
  String get settingsAccountBackupPreparing => 'Préparation de la sauvegarde…';

  @override
  String get settingsAccountBackupShareText => 'Sauvegarde Run app';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'Échec de la sauvegarde : $error';
  }

  @override
  String get settingsAccountRestoreUnavailable =>
      'Service de sauvegarde indisponible.';

  @override
  String get settingsAccountRestoreTitle => 'Restaurer depuis la sauvegarde ?';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'Tu n\'es pas connecté. Les courses seront restaurées sur cet appareil et synchronisées avec ton compte lors de ta prochaine connexion.';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'Cela ajoute ou écrase les courses et itinéraires dont les ID correspondent à ceux de la sauvegarde. Les courses ou itinéraires absents de la sauvegarde ne seront pas supprimés.';

  @override
  String get settingsAccountRestore => 'Restaurer';

  @override
  String get settingsAccountRestoring => 'Restauration…';

  @override
  String settingsAccountRestoreDone(
    int runs,
    int tracks,
    int routes,
    String warnings,
  ) {
    return '$runs courses · $tracks tracés · $routes itinéraires restaurés$warnings';
  }

  @override
  String settingsAccountRestoreWarningsSuffix(int count) {
    return ' · $count avertissements';
  }

  @override
  String settingsAccountRestoreFailed(Object error) {
    return 'Échec de la restauration : $error';
  }

  @override
  String get settingsAccountOfflineMode => 'Mode hors ligne';

  @override
  String get settingsAccountSignedInSync =>
      'Connecté — les courses se synchroniseront';

  @override
  String get settingsAccountSignInToSync =>
      'Connecte-toi pour synchroniser tes courses sur tous tes appareils';

  @override
  String get settingsAccountSignOut => 'Se déconnecter';

  @override
  String get settingsAccountSignIn => 'Se connecter';

  @override
  String get settingsAccountAvatar => 'Photo de profil';

  @override
  String get settingsAccountAvatarHint => 'JPEG, PNG ou WebP, jusqu\'à 2 Mo.';

  @override
  String get settingsAccountAvatarRemove => 'Supprimer la photo';

  @override
  String get settingsAccountAvatarSaved => 'Photo de profil mise à jour.';

  @override
  String get settingsAccountAvatarRemoved => 'Photo de profil supprimée.';

  @override
  String get settingsAccountAvatarUnsupported =>
      'Image non prise en charge — choisissez JPEG, PNG ou WebP.';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return 'Impossible de mettre à jour la photo : $error';
  }

  @override
  String get settingsAccountViewProfile => 'Voir le profil';

  @override
  String get settingsAccountViewProfileSubtitle =>
      'Tes courses, abonnés, abonnements, notifications';

  @override
  String get settingsAccountGuidedRuns => 'Courses guidées';

  @override
  String get settingsAccountGuidedRunsSubtitle =>
      'Séances scriptées avec voix de coach et repères TTS';

  @override
  String get settingsAccountPrivacyZones => 'Zones de confidentialité';

  @override
  String get settingsAccountPrivacyZonesSubtitle =>
      'Masque le début/la fin des tracés publics près de chez toi';

  @override
  String get settingsAccountTrustedContacts => 'Contacts de confiance';

  @override
  String get settingsAccountTrustedContactsSubtitle =>
      'Personnes désignées pour la fonction prévue de course en retard / alerte';

  @override
  String get settingsAccountSendErrorReports =>
      'Envoyer des rapports d\'erreur';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Données anonymisées de plantage et d\'erreur vers Sentry (USA). Désactive pour retirer ton consentement. Appliqué au prochain lancement.';

  @override
  String get settingsAccountErrorReportingEnabled =>
      'Rapports d\'erreur activés — redémarre l\'app pour appliquer.';

  @override
  String get settingsAccountErrorReportingDisabled =>
      'Rapports d\'erreur désactivés — redémarre l\'app pour appliquer.';

  @override
  String get settingsAccountImport => 'Importer depuis une autre app';

  @override
  String get settingsAccountImportSubtitle => 'Strava, GPX, TCX';

  @override
  String get settingsAccountFullBackup => 'Sauvegarde complète';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'Chaque course avec son tracé GPS, plus les itinéraires, le profil et les préférences. Restaurable sur le web ou Android.';

  @override
  String get settingsAccountExportCsv => 'Exporter les courses en CSV';

  @override
  String get settingsAccountExportCsvSubtitle =>
      'Date, distance, durée, allure, source — une ligne par course. Même format que l\'export RGPD du web.';

  @override
  String get settingsAccountRestoreTile => 'Restaurer depuis une sauvegarde';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      'Choisis une sauvegarde .zip enregistrée précédemment.';

  @override
  String get settingsAccountDeleteAccount => 'Supprimer le compte';

  @override
  String get settingsAccountDeleteAccountSubtitle =>
      'Supprime définitivement les données serveur';

  @override
  String get integrationsTitle => 'Intégrations';

  @override
  String get integrationsJustNow => 'à l\'instant';

  @override
  String integrationsMinutesAgo(int minutes) {
    return 'il y a $minutes min';
  }

  @override
  String integrationsHoursAgo(int hours) {
    return 'il y a $hours h';
  }

  @override
  String integrationsDaysAgo(int days) {
    return 'il y a $days j';
  }

  @override
  String integrationsWeeksAgo(int weeks) {
    return 'il y a $weeks sem';
  }

  @override
  String integrationsCouldNotOpen(Object error) {
    return 'Impossible d\'ouvrir : $error';
  }

  @override
  String get integrationsStravaBrowserHint =>
      'Termine la connexion Strava dans ton navigateur, puis reviens ici et tire pour actualiser.';

  @override
  String get integrationsStravaCancelled => 'Connexion Strava annulée.';

  @override
  String integrationsStravaSignInFailed(Object error) {
    return 'Échec de la connexion Strava : $error';
  }

  @override
  String get integrationsStravaCsrfMismatch =>
      'Connexion Strava refusée : incohérence de l\'état CSRF. Réessaie.';

  @override
  String integrationsStravaConnectFailed(String error) {
    return 'Échec de la connexion à Strava : $error';
  }

  @override
  String get integrationsStravaConnected => 'Strava connecté.';

  @override
  String integrationsSyncResult(int imported, int skipped) {
    return 'Synchronisé. $imported nouvelles, $skipped déjà présentes.';
  }

  @override
  String integrationsSyncFailed(Object error) {
    return 'Échec de la synchronisation : $error';
  }

  @override
  String get integrationsStravaDisconnectTitle => 'Déconnecter Strava ?';

  @override
  String get integrationsStravaDisconnectBody =>
      'Les activités futures ne seront plus synchronisées automatiquement. Les courses déjà importées restent dans ton historique.';

  @override
  String get integrationsCancel => 'Annuler';

  @override
  String get integrationsDisconnect => 'Déconnecter';

  @override
  String get integrationsStravaDisconnected => 'Strava déconnecté.';

  @override
  String integrationsDisconnectFailed(Object error) {
    return 'Échec de la déconnexion : $error';
  }

  @override
  String get integrationsParkrunTitle => 'Importer les résultats parkrun';

  @override
  String get integrationsParkrunBody =>
      'Saisis ton numéro d\'athlète parkrun (p. ex. A123456). Nous récupérons ton historique d\'arrivées et ajoutons les nouveaux résultats à ta liste de courses.';

  @override
  String get integrationsParkrunFieldLabel => 'Numéro d\'athlète';

  @override
  String get integrationsImport => 'Importer';

  @override
  String get integrationsParkrunImporting => 'Import des résultats parkrun…';

  @override
  String integrationsParkrunImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count résultats parkrun importés.',
      one: '$count résultat parkrun importé.',
    );
    return '$_temp0';
  }

  @override
  String get integrationsParkrunNoneNew =>
      'Aucun nouveau résultat parkrun depuis le dernier import.';

  @override
  String integrationsImportFailed(Object error) {
    return 'Échec de l\'import : $error';
  }

  @override
  String get integrationsStravaName => 'Strava';

  @override
  String get integrationsStravaConnectSubtitle =>
      'Connecte-toi pour synchroniser automatiquement les activités';

  @override
  String get integrationsStravaWaitingFirstSync =>
      'Connecté · en attente de la première synchro';

  @override
  String integrationsStravaLastSync(String time) {
    return 'Connecté · dernière synchro $time';
  }

  @override
  String get integrationsSyncNow => 'Synchroniser maintenant';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Importer les résultats par numéro d\'athlète';

  @override
  String get integrationsSignInTitle => 'Connecte-toi pour relier des services';

  @override
  String get integrationsSignInSubtitle =>
      'Strava + parkrun nécessitent un compte pour que les activités synchronisées arrivent dans ton historique.';

  @override
  String get integrationsHealthConnectTitle =>
      'Écrire les courses dans Health Connect';

  @override
  String get integrationsHealthConnectSubtitle =>
      'Envoie chaque course terminée à Health Connect pour qu\'elle apparaisse dans Google Fit, Samsung Health, Fitbit et d\'autres.';

  @override
  String get integrationsHealthConnectDenied =>
      'Autorisation Health Connect non accordée — les courses ne seront pas écrites.';

  @override
  String integrationsHrPairFailed(Object error) {
    return 'Échec de l\'appairage : $error';
  }

  @override
  String get integrationsHrTitle => 'Capteur de fréquence cardiaque';

  @override
  String get integrationsHrChecking => 'Vérification…';

  @override
  String integrationsHrPaired(String name) {
    return 'Appairé : $name';
  }

  @override
  String get integrationsHrNotPaired =>
      'Aucune ceinture appairée — touche pour scanner';

  @override
  String get integrationsHrForget => 'Oublier';

  @override
  String get integrationsHrForgetConfirm =>
      'Oublier ce capteur cardiaque ? Vous devrez le réappairer pour l\'utiliser pendant une course.';

  @override
  String get integrationsHrScanTitle => 'Rechercher un capteur cardiaque';

  @override
  String get integrationsHrScanHint =>
      'Réveille ta ceinture / sangle thoracique. Cela prend généralement 3 à 8 secondes.';

  @override
  String get integrationsHrScanEmpty =>
      'Aucune ceinture trouvée. Assure-toi qu\'elle est à proximité et active.';

  @override
  String integrationsHrRssi(int rssi) {
    return 'RSSI $rssi dBm';
  }

  @override
  String get integrationsTreadmillTitle => 'Tapis de course';

  @override
  String get integrationsTreadmillChecking => 'Vérification…';

  @override
  String integrationsTreadmillPaired(String name) {
    return 'Appairé : $name';
  }

  @override
  String get integrationsTreadmillNotPaired =>
      'Aucun tapis appairé — touchez pour rechercher';

  @override
  String get integrationsTreadmillForget => 'Oublier';

  @override
  String get integrationsTreadmillForgetConfirm =>
      'Oublier ce tapis de course ? Vous devrez le réappairer pour l\'utiliser pendant une course.';

  @override
  String get integrationsTreadmillScanTitle => 'Rechercher un tapis de course';

  @override
  String get integrationsTreadmillScanHint =>
      'Assurez-vous que le Bluetooth du tapis est activé et que le tapis est actif. La recherche prend 3 à 8 secondes.';

  @override
  String get integrationsTreadmillScanEmpty =>
      'Aucun tapis trouvé. Vérifiez qu\'il prend en charge le Bluetooth (FTMS) et qu\'il est à proximité.';

  @override
  String integrationsTreadmillPairFailed(Object error) {
    return 'Échec de l\'appairage : $error';
  }

  @override
  String integrationsTreadmillLiveSpeed(String speed) {
    return '$speed km/h';
  }

  @override
  String get proTitle => 'Pro et soutien';

  @override
  String proCouldNotOpen(Object error) {
    return 'Impossible d\'ouvrir : $error';
  }

  @override
  String get proWelcome =>
      'Bienvenue dans Pro ! Récupération de tes avantages…';

  @override
  String get proPurchaseFailed => 'Échec de l\'achat. Réessaie plus tard.';

  @override
  String get proRestoreNeedsSignIn =>
      'La restauration nécessite que tu sois connecté avec RevenueCat configuré. Gère ton abonnement sur la page de mise à niveau web à la place.';

  @override
  String get proRestored => 'Ton abonnement Pro a été restauré.';

  @override
  String get proRestoreNone =>
      'Aucun achat actif trouvé sur ce compte de store.';

  @override
  String get proRestoreFailed =>
      'Échec de la restauration. Réessaie plus tard.';

  @override
  String get proRestoreUnavailable =>
      'Restauration indisponible dans cette version.';

  @override
  String proSubscribeTitle(String price) {
    return 'S\'abonner à Pro — $price/mois';
  }

  @override
  String get proSubscribeSubtitleConfigured =>
      'Coach IA illimité + traitement prioritaire. Renouvellement mensuel automatique jusqu\'à résiliation dans Réglages → Abonnements.';

  @override
  String get proSubscribeSubtitleWeb =>
      'Ouvre le portail d\'abonnement dans ton navigateur. Renouvellement mensuel automatique jusqu\'à résiliation.';

  @override
  String get proRegionalNote =>
      'Facturé en dollars américains. La disponibilité dépend de ton pays et de ton moyen de paiement — certaines régions ne peuvent pas être desservies par notre prestataire de paiement.';

  @override
  String get proRestorePurchases => 'Restaurer les achats';

  @override
  String get proRestorePurchasesSubtitle =>
      'Relie les achats d\'une installation précédente ou d\'un autre appareil';

  @override
  String get proManageSubscription => 'Gérer l\'abonnement';

  @override
  String get proManageSubscriptionSubtitle =>
      'Résilier, changer de formule ou mettre à jour le moyen de paiement';

  @override
  String get proSupport => 'Soutenir l\'app';

  @override
  String get proSupportSubtitle => 'Don ponctuel dans ton navigateur';

  @override
  String get licensesTitle => 'Licences';

  @override
  String get licensesVersion => 'Version';

  @override
  String get licensesOpenSource => 'Licences open source';

  @override
  String get licensesOpenSourceSubtitle => 'Paquets tiers intégrés à cette app';

  @override
  String get devicesTitle => 'Appareils';

  @override
  String get devicesRenameTitle => 'Renommer l\'appareil';

  @override
  String get devicesCancel => 'Annuler';

  @override
  String get devicesSave => 'Enregistrer';

  @override
  String devicesRenameFailed(Object error) {
    return 'Échec du renommage : $error';
  }

  @override
  String get devicesRemoveTitle => 'Supprimer l\'appareil ?';

  @override
  String get devicesRemoveBodyCurrent =>
      'C\'est l\'appareil que tu utilises. Le supprimer efface les surcharges de préférences propres à l\'appareil ; l\'appareil reste connecté.';

  @override
  String get devicesRemoveBodyOther =>
      'Supprime l\'entrée de l\'appareil et toutes les surcharges de préférences propres à l\'appareil. L\'appareil reste connecté jusqu\'à la prochaine ouverture de l\'app.';

  @override
  String get devicesRemove => 'Supprimer';

  @override
  String devicesRemoveFailed(Object error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String devicesSaveFailed(Object error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get devicesLoadError => 'Impossible de charger les appareils.';

  @override
  String get devicesEmpty =>
      'Aucun appareil pour l\'instant — ils sont enregistrés la première fois qu\'un appareil ouvre l\'app en étant connecté.';

  @override
  String get devicesThisDevice => 'Cet appareil';

  @override
  String devicesLastSeen(String time) {
    return 'Vu pour la dernière fois $time';
  }

  @override
  String devicesOverrideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count surcharges',
      one: '$count surcharge',
    );
    return '$_temp0';
  }

  @override
  String get devicesJustNow => 'à l\'instant';

  @override
  String devicesMinutesAgo(int minutes) {
    return 'il y a $minutes min';
  }

  @override
  String devicesHoursAgo(int hours) {
    return 'il y a $hours h';
  }

  @override
  String devicesDaysAgo(int days) {
    return 'il y a $days j';
  }

  @override
  String get devicesRename => 'Renommer';

  @override
  String get devicesEditOverrides => 'Modifier les surcharges…';

  @override
  String get devicesEveryKeySet =>
      'Toutes les clés surchargeables sont déjà définies ; supprimes-en une avant d\'en ajouter une autre.';

  @override
  String get devicesOverridesSheetTitle => 'Surcharges par appareil';

  @override
  String get devicesOverridesSheetDesc =>
      'Ces clés remplacent les réglages universels uniquement sur cet appareil.';

  @override
  String get devicesNoOverrides => 'Aucune surcharge sur cet appareil.';

  @override
  String get devicesAddOverride => 'Ajouter une surcharge';

  @override
  String get devicesPickKey => 'Choisir une clé';

  @override
  String get devicesEnterWholeNumber => 'Saisis un nombre entier.';

  @override
  String get devicesEnterNumber => 'Saisis un nombre (p. ex. 0,8).';

  @override
  String get devicesValue => 'Valeur';

  @override
  String get devicesBack => 'Retour';

  @override
  String get devicesAdd => 'Ajouter';

  @override
  String get devicesKeyPreferredUnitLabel => 'Unité préférée';

  @override
  String get devicesKeyPreferredUnitHint =>
      'Unité de distance pour tous les affichages.';

  @override
  String get devicesKeyDefaultActivityLabel => 'Activité par défaut';

  @override
  String get devicesKeyDefaultActivityHint =>
      'Activité présélectionnée sur l\'écran de démarrage.';

  @override
  String get devicesKeyMapStyleLabel => 'Style de carte';

  @override
  String get devicesKeyMapStyleHint => 'Style MapLibre pour la vue carte.';

  @override
  String get devicesKeyPaceFormatLabel => 'Format d\'allure';

  @override
  String get devicesKeyPaceFormatHint => 'Format d\'affichage de l\'allure.';

  @override
  String get devicesKeyVoiceFeedbackLabel => 'Retour vocal';

  @override
  String get devicesKeyVoiceFeedbackHint =>
      'Énonce les annonces d\'allure / distance pendant une course.';

  @override
  String get devicesKeyVoiceIntervalLabel => 'Intervalle de retour vocal (km)';

  @override
  String get devicesKeyVoiceIntervalHint =>
      'Distance entre les annonces vocales.';

  @override
  String get devicesKeyHapticLabel => 'Retour haptique';

  @override
  String get devicesKeyHapticHint =>
      'Vibration aux changements de tour et de zone d\'allure.';

  @override
  String get devicesKeyKeepScreenOnLabel => 'Garder l\'écran allumé';

  @override
  String get devicesKeyKeepScreenOnHint =>
      'Désactive l\'atténuation auto de l\'OS pendant l\'enregistrement.';

  @override
  String get gearTitle => 'Équipement';

  @override
  String get gearAddGear => 'Ajouter un équipement';

  @override
  String get gearDeleteTitle => 'Supprimer l\'équipement ?';

  @override
  String gearDeleteBody(String name) {
    return 'Supprimer « $name » ? L\'historique de kilométrage des courses passées sera perdu. Mets-le plutôt à la retraite pour conserver les enregistrements.';
  }

  @override
  String get gearCancel => 'Annuler';

  @override
  String get gearDelete => 'Supprimer';

  @override
  String get gearDeletedOffline =>
      'Supprimé localement — sera synchronisé à la reconnexion.';

  @override
  String gearAttached(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name associé à $count courses.',
      one: '$name associé à $count course.',
    );
    return '$_temp0';
  }

  @override
  String gearOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hors ligne — $count modifications en attente, affichage de l\'équipement en cache.',
      one:
          'Hors ligne — $count modification en attente, affichage de l\'équipement en cache.',
    );
    return '$_temp0';
  }

  @override
  String get gearOfflineCached =>
      'Hors ligne — affichage de l\'équipement en cache.';

  @override
  String get gearShoes => 'Chaussures';

  @override
  String get gearBikes => 'Vélos';

  @override
  String get gearRetired => 'RETIRÉ';

  @override
  String get gearEmptyShoes => 'Aucune chaussure pour l\'instant';

  @override
  String get gearEmptyBikes => 'Aucun vélo pour l\'instant';

  @override
  String get gearEmptySubtitle =>
      'Ajoute une paire pour suivre le kilométrage et recevoir des rappels de remplacement.';

  @override
  String gearRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses',
      one: '$count course',
    );
    return '$_temp0';
  }

  @override
  String get gearWearDue => 'À remplacer bientôt';

  @override
  String get gearWearWorn => 'Distance de remplacement dépassée';

  @override
  String get gearRetire => 'Mettre à la retraite';

  @override
  String get gearRestore => 'Réactiver';

  @override
  String get gearRotationsTitle => 'Rotations';

  @override
  String get gearRotationsHint =>
      'Regroupez l\'équipement que vous alternez — un ensemble « Entraînement quotidien », un ensemble « Jour de course ». Une rotation n\'est qu\'un regroupement nommé ; elle ne change pas la paire qui marque automatiquement les nouvelles courses.';

  @override
  String get gearRotationsEmpty =>
      'Aucune rotation pour l\'instant. Créez-en une pour regrouper un ensemble de chaussures ou de vélos.';

  @override
  String get gearRotationName => 'Nom de la rotation';

  @override
  String get gearRotationNew => 'Nouvelle rotation';

  @override
  String get gearRotationCreate => 'Créer';

  @override
  String get gearRotationRename => 'Renommer';

  @override
  String get gearRotationManage => 'Modifier l\'équipement';

  @override
  String gearRotationManageTitle(String name) {
    return 'Équipement dans « $name »';
  }

  @override
  String get gearRotationDeleteTitle => 'Supprimer la rotation ?';

  @override
  String gearRotationDeleteBody(String name) {
    return 'Supprimer la rotation « $name » ? Votre équipement n\'est pas affecté — seul le regroupement est supprimé.';
  }

  @override
  String gearRotationMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '$count élément',
    );
    return '$_temp0';
  }

  @override
  String get gearRotationNoGear =>
      'Ajoutez d\'abord de l\'équipement, puis vous pourrez le regrouper en rotation.';

  @override
  String gearRotationSaveFailed(Object error) {
    return 'Impossible d\'enregistrer la rotation : $error';
  }

  @override
  String get gearRotationDone => 'Terminé';

  @override
  String get privacyZonesTitle => 'Zones de confidentialité';

  @override
  String get privacyZonesSaved => 'Zones de confidentialité enregistrées.';

  @override
  String privacyZonesSaveFailed(Object error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return 'Position indisponible : $error';
  }

  @override
  String get privacyZonesSave => 'Enregistrer';

  @override
  String get privacyZonesLocateMe => 'Me localiser';

  @override
  String get privacyZonesHint =>
      'Touche la carte pour ajouter une zone. Les tracés sur les surfaces publiques voient leur début et leur fin masqués au-delà du rayon de la zone.';

  @override
  String get privacyZonesSearchHint => 'Rechercher des lieux…';

  @override
  String get privacyZonesRadius => 'Rayon';

  @override
  String privacyZonesRadiusMeters(int meters) {
    return '$meters m';
  }

  @override
  String privacyZonesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zones — touche un repère pour le supprimer.',
      one: '$count zone — touche un repère pour la supprimer.',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'Tout effacer';

  @override
  String get privacyZonesRemoveTitle =>
      'Supprimer la zone de confidentialité ?';

  @override
  String get privacyZonesRemoveBody =>
      'Cette zone masque vos parcours à proximité dans les partages publics. La supprimer réexpose cette zone.';

  @override
  String get privacyZonesRemoveSemantics =>
      'Supprimer la zone de confidentialité';

  @override
  String get privacyZonesClearAllTitle =>
      'Effacer toutes les zones de confidentialité ?';

  @override
  String get privacyZonesClearAllBody =>
      'Cela supprime toutes les zones et réexpose toutes ces zones dans les partages publics.';

  @override
  String get prefsTitle => 'Préférences';

  @override
  String get prefsUnitMetric => 'km, m';

  @override
  String get prefsUnitImperial => 'mi, ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · synchronisé avec tes autres appareils';
  }

  @override
  String get prefsClear => 'Effacer';

  @override
  String get prefsCancel => 'Annuler';

  @override
  String get prefsSave => 'Enregistrer';

  @override
  String get prefsSplitInterval => 'Intervalle de split';

  @override
  String get prefsSplitIntervalDefault => 'Par défaut';

  @override
  String get prefsSplitIntervalDefaultSubtitle =>
      'Par défaut (1 km en course, 5 km à vélo)';

  @override
  String get prefsLivePaceAlert => 'Alerte d\'allure en direct';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 's';

  @override
  String get prefsLivePaceAlertOff =>
      'Désactivé — définis une allure pour recevoir des alertes vocales pendant une course';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — alerte vocale pendant une course si l\'écart dépasse 30 s';
  }

  @override
  String get prefsActivityRun => 'Course';

  @override
  String get prefsActivityWalk => 'Marche';

  @override
  String get prefsActivityHike => 'Randonnée';

  @override
  String get prefsActivityCycle => 'Vélo';

  @override
  String get prefsPaceFormat => 'Format d\'allure';

  @override
  String get prefsPaceFormatMinPerKm => 'Minutes par km';

  @override
  String get prefsPaceFormatMinPerMi => 'Minutes par mile';

  @override
  String get prefsPaceFormatKph => 'km/h';

  @override
  String get prefsPaceFormatMph => 'mph';

  @override
  String get prefsWeightUnit => 'Unité de poids';

  @override
  String get prefsWeightUnitKg => 'Kilogrammes (kg)';

  @override
  String get prefsWeightUnitLbs => 'Livres (lbs)';

  @override
  String get prefsNotSet => 'Non défini';

  @override
  String prefsHrZonesSummary(String zones) {
    return '$zones bpm';
  }

  @override
  String prefsWeeklyGoalSummary(String distance, String unit) {
    return '$distance $unit / semaine';
  }

  @override
  String get prefsMapStyle => 'Style de carte';

  @override
  String get prefsMapStyleStreets => 'Rues';

  @override
  String get prefsMapStyleSatellite => 'Satellite';

  @override
  String get prefsMapStyleOutdoors => 'Plein air';

  @override
  String get prefsMapStyleDark => 'Sombre';

  @override
  String get prefsDefaultRunVisibility => 'Visibilité par défaut des courses';

  @override
  String get prefsCoachPersonality => 'Personnalité du coach';

  @override
  String get prefsCoachSupportive => 'Encourageant';

  @override
  String get prefsCoachDrillSergeant => 'Sergent instructeur';

  @override
  String get prefsCoachAnalytical => 'Analytique';

  @override
  String get prefsSectionNotifications => 'Notifications';

  @override
  String get prefsEmailNotifications => 'Notifications par e-mail';

  @override
  String get prefsEmailNotifAll => 'Toutes';

  @override
  String get prefsEmailNotifImportant => 'Importantes uniquement';

  @override
  String get prefsEmailNotifOff => 'Désactivées';

  @override
  String get prefsPushNotifications => 'Notifications push';

  @override
  String get prefsPushNotifAll => 'Toutes';

  @override
  String get prefsPushNotifImportant => 'Importantes uniquement';

  @override
  String get prefsPushNotifOff => 'Désactivées';

  @override
  String get prefsEmailWeeklyDigest => 'E-mail récapitulatif hebdomadaire';

  @override
  String get prefsEmailWeeklyDigestHint =>
      'Inscrivez-vous à un récapitulatif hebdomadaire de votre entraînement et des temps forts de la communauté. Désactivé par défaut ; distinct de vos e-mails de notification.';

  @override
  String get prefsEmailLifecycleDrip => 'E-mail de conseils et encouragements';

  @override
  String get prefsEmailLifecycleDripHint =>
      'Inscrivez-vous pour recevoir occasionnellement des rappels de prise en main, de réengagement et de série. Désactivé par défaut ; distinct de votre récapitulatif hebdomadaire et de vos e-mails de notification.';

  @override
  String get prefsWeekStart => 'La semaine commence le';

  @override
  String get prefsWeekStartMonday => 'Lundi';

  @override
  String get prefsWeekStartSunday => 'Dimanche';

  @override
  String get prefsDefaultActivity => 'Activité par défaut';

  @override
  String get prefsDateOfBirth => 'Date de naissance';

  @override
  String get prefsRestingHr => 'Fréquence cardiaque au repos';

  @override
  String get prefsMaxHr => 'Fréquence cardiaque maximale';

  @override
  String get prefsMaxHrNotSet => 'Non défini — repli sur 208 − 0,7 × âge';

  @override
  String prefsHrBpm(int bpm) {
    return '$bpm bpm';
  }

  @override
  String get prefsSectionFueling => 'Ravitaillement de course';

  @override
  String get prefsCarbsPerHour => 'Glucides par heure';

  @override
  String prefsCarbsPerHourValue(int grams) {
    return '$grams g/h';
  }

  @override
  String get prefsFluidPerHour => 'Liquide par heure';

  @override
  String prefsFluidPerHourValue(int ml) {
    return '$ml ml/h';
  }

  @override
  String get prefsHrZones => 'Zones de fréquence cardiaque';

  @override
  String get prefsHrZonesDialogTitle =>
      'Zones de fréquence cardiaque (limites supérieures, bpm)';

  @override
  String get prefsWeeklyGoal => 'Objectif de kilométrage hebdomadaire';

  @override
  String get prefsSectionActivityRecording => 'Activité et enregistrement';

  @override
  String get prefsSectionTrainingDemographics =>
      'Entraînement et données démographiques';

  @override
  String get prefsSectionPrivacySharing => 'Confidentialité et partage';

  @override
  String get prefsSectionAiCoach => 'Coach IA';

  @override
  String get prefsSignInToEdit =>
      'Connecte-toi pour modifier les réglages de profil qui se synchronisent sur tous tes appareils.';

  @override
  String get prefsUseMiles => 'Utiliser les miles';

  @override
  String get prefsDarkMode => 'Mode sombre';

  @override
  String get prefsAudioCues => 'Repères audio';

  @override
  String get prefsAudioCuesSubtitle => 'Annonces vocales des splits';

  @override
  String get prefsMinimalVoiceCues => 'Repères vocaux minimaux';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Ignore les rappels bavards de mi-répétition et de dérive d\'allure';

  @override
  String get prefsKeepScreenOn => 'Garder l\'écran allumé';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Maintient un wakelock pendant une course';

  @override
  String get prefsAdvancedGps => 'GPS avancé';

  @override
  String get prefsAdvancedGpsSubtitle =>
      'Plus de précision, tracé plus détaillé, plus de batterie';

  @override
  String get prefsShowRawTrack => 'Afficher le tracé GPS brut';

  @override
  String get prefsShowRawTrackSubtitle =>
      'Affiche la ligne enregistrée non ajustée sur la carte de course, même lorsqu\'un tracé corrigé existe';

  @override
  String get prefsDefaultRunPrivacy => 'Confidentialité par défaut des courses';

  @override
  String get prefsStravaAutoShare => 'Partage auto Strava';

  @override
  String get prefsStravaAutoShareSubtitle =>
      'Pousse automatiquement chaque nouvelle course vers Strava. Nécessite une intégration Strava connectée une fois disponible.';

  @override
  String get prefsDiscoverable => 'Apparaître dans la recherche par nom';

  @override
  String get prefsDiscoverableSubtitle =>
      'Si désactivé, ton compte n\'apparaît pas lorsque d\'autres coureurs recherchent par nom d\'affichage. Tes courses publiques et ton profil restent accessibles à quiconque possède l\'URL.';

  @override
  String get dashboardCoachTooltip => 'Coach';

  @override
  String get dashboardFeedTooltip => 'Fil d\'activité';

  @override
  String get dashboardRecapTooltip => 'Année en course';

  @override
  String get dashboardProfileTooltip => 'Mon profil';

  @override
  String get dashboardWelcomeTitle => 'Bienvenue !';

  @override
  String get dashboardWelcomeBody =>
      'Ton tableau de bord se remplit dès que tu enregistres une course, définis un objectif ou importes ton historique.';

  @override
  String get dashboardSetGoal => 'Définir un objectif';

  @override
  String get dashboardImportRuns => 'Importer des courses';

  @override
  String get dashboardPeriodWeek => 'Semaine';

  @override
  String get dashboardPeriodMonth => 'Mois';

  @override
  String get dashboardPeriodAllTime => 'Tout';

  @override
  String get dashboardSectionStreak => 'Série';

  @override
  String get dashboardWeekStripTitle => 'Cette semaine';

  @override
  String dashboardWeekStripCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activités',
      one: '$count activité',
    );
    return '$_temp0';
  }

  @override
  String dashboardWeekStripDayAria(String dow, String dist) {
    return '$dow : $dist';
  }

  @override
  String dashboardWeekStripDayRestAria(String dow) {
    return '$dow : jour de repos';
  }

  @override
  String get dashboardSectionLast20Weeks => '20 dernières semaines';

  @override
  String get dashboardSectionRecentLifts => 'Séances récentes';

  @override
  String get dashboardViewAllGym => 'Tout voir';

  @override
  String get dashboardSectionPersonalBests => 'Records personnels';

  @override
  String get dashboardLongestRun => 'Course la plus longue';

  @override
  String dashboardFastestDistance(String distance) {
    return 'Plus rapide sur $distance';
  }

  @override
  String get dashboardGoals => 'Objectifs';

  @override
  String get dashboardAdd => 'Ajouter';

  @override
  String get dashboardGoalWeekly => 'HEBDOMADAIRE';

  @override
  String get dashboardGoalMonthly => 'MENSUEL';

  @override
  String dashboardGoalTitleFallback(String period) {
    return 'OBJECTIF $period';
  }

  @override
  String get dashboardSetWeeklyGoalA11y =>
      'Définir un objectif de course hebdomadaire';

  @override
  String get dashboardSetFirstGoal => 'Définis ton premier objectif';

  @override
  String get dashboardSetFirstGoalBody =>
      'Suis la distance, le temps, l\'allure ou le nombre de courses par semaine ou par mois.';

  @override
  String get dashboardGoalTapToEdit => 'appuie pour modifier';

  @override
  String get dashboardGoalComplete => 'Terminé.';

  @override
  String get dashboardGoalInProgress => 'En cours.';

  @override
  String dashboardGoalA11y(String period, String title, String status) {
    return 'Objectif $period — $title $status';
  }

  @override
  String dashboardRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses',
      one: '$count course',
    );
    return '$_temp0';
  }

  @override
  String dashboardVert(String value) {
    return '$value de dénivelé';
  }

  @override
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  ) {
    return 'Résumé $label, $distance sur $runs$elevation';
  }

  @override
  String dashboardElevationGainSuffix(String value) {
    return ', $value de dénivelé positif';
  }

  @override
  String get dashboardStreakCurrent => 'Actuelle';

  @override
  String get dashboardStreakHistory => 'Historique';

  @override
  String get dashboardStreakDayUnit => 'jour';

  @override
  String get dashboardStreakDaysUnit => 'jours';

  @override
  String dashboardStreakBest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '$count jour',
    );
    return 'meilleure $_temp0';
  }

  @override
  String get dashboardStreakAllTimeBest => 'record absolu';

  @override
  String get dashboardStreakRestart => 'cours aujourd\'hui pour la relancer';

  @override
  String get dashboardStreakStart => 'cours aujourd\'hui pour en commencer une';

  @override
  String get dashboardHeatmapLess => 'Moins';

  @override
  String get dashboardHeatmapMore => 'Plus';

  @override
  String get dashboardHeatmapTapHint =>
      'Appuie sur une semaine pour son résumé';

  @override
  String get periodWeeklySummary => 'Résumé hebdomadaire';

  @override
  String get periodMonthlySummary => 'Résumé mensuel';

  @override
  String get periodAllTimeSummary => 'Résumé global';

  @override
  String get periodShareTooltip => 'Partager';

  @override
  String get periodPreviousTooltip => 'Précédent';

  @override
  String get periodNextTooltip => 'Suivant';

  @override
  String get periodSwitchToWeekly => 'Appuie pour passer en hebdomadaire';

  @override
  String get periodSwitchToMonthly => 'Appuie pour passer en mensuel';

  @override
  String get periodSwitchToAllTime => 'Appuie pour passer en global';

  @override
  String get periodStatDistance => 'Distance';

  @override
  String get periodStatRuns => 'Courses';

  @override
  String get periodStatTime => 'Temps';

  @override
  String get periodStatAvgPace => 'Allure moy.';

  @override
  String get periodEmptyWeek => 'Aucune course cette semaine';

  @override
  String get periodEmptyMonth => 'Aucune course ce mois-ci';

  @override
  String get periodShareSummary => 'Partager le résumé';

  @override
  String get periodShareText => 'Texte';

  @override
  String get periodShareImage => 'Image';

  @override
  String get periodShareImageFailed =>
      'Impossible de créer l\'image de partage';

  @override
  String get periodShareCardTagline => 'MEILLEUR COUREUR';

  @override
  String get periodShareStatDistance => 'DISTANCE';

  @override
  String get periodShareStatRuns => 'COURSES';

  @override
  String get periodShareStatTime => 'TEMPS';

  @override
  String get periodShareStatAvgPace => 'ALLURE MOY.';

  @override
  String get trainingLoadTitle => 'Forme, Fatigue & Fraîcheur';

  @override
  String trainingLoadSubtitleHr(int days) {
    return 'TRIMP basé sur la fréquence cardiaque sur les $days derniers jours.';
  }

  @override
  String get trainingLoadSubtitleVolume =>
      'Basé sur le volume — définis ta FC de repos et max dans les préférences et enregistre avec une ceinture pour passer au TRIMP.';

  @override
  String get trainingLoadEmpty =>
      'Enregistre quelques courses pour voir ta tendance de forme.';

  @override
  String get trainingLoadLegendFitness => 'Forme';

  @override
  String get trainingLoadLegendFatigue => 'Fatigue';

  @override
  String get trainingLoadLegendForm => 'Fraîcheur';

  @override
  String trainingLoadLegendEntry(String label, int value) {
    return '$label · $value';
  }

  @override
  String get trainingLoadReadingLoaded =>
      'Chargé — persévère et récupère quand tu es prêt.';

  @override
  String get trainingLoadReadingTapered =>
      'Affûté — une grosse séance ne te cassera pas.';

  @override
  String get trainingLoadReadingBalanced =>
      'Équilibré — jour facile ou jour dur, à toi de choisir.';

  @override
  String get trainingLoadIncludesLifts =>
      'Séances de musculation incluses — elles ajoutent aussi de la fatigue.';

  @override
  String get intensityTitle => 'INTENSITÉ D\'ENTRAÎNEMENT';

  @override
  String intensityWindow(int days) {
    return '$days derniers jours';
  }

  @override
  String intensityBasedOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses avec FC',
      one: '$count course avec FC',
    );
    return 'D\'après $_temp0';
  }

  @override
  String get mileageTitle => 'KILOMÉTRAGE';

  @override
  String get mileageWeek => 'Semaine';

  @override
  String get mileageMonth => 'Mois';

  @override
  String get mileageYear => 'Année';

  @override
  String get mileageThisWeek => 'cette semaine';

  @override
  String get mileageThisMonth => 'ce mois-ci';

  @override
  String get mileageThisYear => 'cette année';

  @override
  String get fitnessTitle => 'Forme';

  @override
  String get fitnessStatVo2Max => 'VO₂ max';

  @override
  String get fitnessStatVo2MaxTooltip =>
      'Ton moteur aérobie : la quantité d\'oxygène que ton corps peut utiliser par minute. Plus c\'est élevé, plus tu es en forme.';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'Le score de forme de course de Daniels d\'après ton meilleur effort récent. Détermine tes allures d\'entraînement.';

  @override
  String get fitnessStatRuns => 'Courses';

  @override
  String get fitnessStatRunsTooltip =>
      'Courses récentes assez longues pour compter dans ton estimation de forme.';

  @override
  String get fitnessStatCtl => 'Forme (CTL)';

  @override
  String get fitnessStatCtlTooltip =>
      'Ta charge d\'entraînement glissante sur 42 jours. Se construit lentement ; c\'est ta base d\'endurance.';

  @override
  String get fitnessStatAtl => 'Fatigue (ATL)';

  @override
  String get fitnessStatAtlTooltip =>
      'Ta charge des 7 derniers jours. Monte vite après les grosses séances et baisse avec le repos.';

  @override
  String get fitnessStatTsb => 'Fraîcheur (TSB)';

  @override
  String get fitnessStatTsbTooltip =>
      'Forme moins fatigue. Positif = frais et prêt à courir ; négatif = encore fatigué.';

  @override
  String get runSocialActivity => 'Activité';

  @override
  String get runSocialNoComments => 'Pas encore de commentaires.';

  @override
  String get runSocialReplyHint => 'Écrire une réponse…';

  @override
  String get runSocialCommentHint => 'Ajouter un commentaire…';

  @override
  String get runSocialRunnerFallback => 'Coureur';

  @override
  String get runSocialReply => 'Répondre';

  @override
  String get runSocialDelete => 'Supprimer';

  @override
  String get runSocialDeleteCommentTitle => 'Supprimer ce commentaire ?';

  @override
  String get runSocialDeleteCommentMessage =>
      'Ce commentaire sera définitivement supprimé. Cette action est irréversible.';

  @override
  String get runSocialPost => 'Publier';

  @override
  String get runSocialCancel => 'Annuler';

  @override
  String runSocialKudosError(String error) {
    return 'Impossible de mettre à jour les kudos : $error';
  }

  @override
  String runSocialPostError(String error) {
    return 'Échec de la publication : $error';
  }

  @override
  String runSocialDeleteError(String error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String get runPhotosLoading => 'Chargement des photos…';

  @override
  String get runPhotosTitle => 'Photos';

  @override
  String get runPhotosAdd => 'Ajouter une photo';

  @override
  String get runPhotosCaptionPendingHint =>
      'Légende (facultatif, 280 caractères)';

  @override
  String get runPhotosCaptionHint => 'Légende…';

  @override
  String get runPhotosCancel => 'Annuler';

  @override
  String get runPhotosSave => 'Enregistrer';

  @override
  String get runPhotosUpload => 'Téléverser';

  @override
  String get runPhotosUploading => 'Téléversement…';

  @override
  String get runPhotosEditCaption => 'Modifier la légende';

  @override
  String get runPhotosDeleteTooltip => 'Supprimer la photo';

  @override
  String get runPhotosDeleteTitle => 'Supprimer la photo ?';

  @override
  String get runPhotosDeleteBody =>
      'La photo sera définitivement retirée de la course.';

  @override
  String get runPhotosDeleteConfirm => 'Supprimer';

  @override
  String runPhotosPickerError(String error) {
    return 'Impossible d\'ouvrir le sélecteur : $error';
  }

  @override
  String runPhotosUploadError(String error) {
    return 'Échec du téléversement : $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'Impossible de mettre à jour la légende : $error';
  }

  @override
  String get routePhotosLoading => 'Chargement des photos…';

  @override
  String get routePhotosTitle => 'Photos';

  @override
  String get routePhotosAdd => 'Ajouter une photo';

  @override
  String get routePhotosCaptionPendingHint =>
      'Légende (facultatif, 280 caractères)';

  @override
  String get routePhotosCaptionHint => 'Légende…';

  @override
  String get routePhotosCancel => 'Annuler';

  @override
  String get routePhotosSave => 'Enregistrer';

  @override
  String get routePhotosUpload => 'Téléverser';

  @override
  String get routePhotosUploading => 'Téléversement…';

  @override
  String get routePhotosEditCaption => 'Modifier la légende';

  @override
  String get routePhotosDeleteTooltip => 'Supprimer la photo';

  @override
  String get routePhotosDeleteTitle => 'Supprimer la photo ?';

  @override
  String get routePhotosDeleteBody =>
      'La photo sera définitivement retirée de l\'itinéraire.';

  @override
  String get routePhotosDeleteConfirm => 'Supprimer';

  @override
  String routePhotosPickerError(String error) {
    return 'Impossible d\'ouvrir le sélecteur : $error';
  }

  @override
  String routePhotosUploadError(String error) {
    return 'Échec du téléversement : $error';
  }

  @override
  String routePhotosDeleteError(String error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'Impossible de mettre à jour la légende : $error';
  }

  @override
  String get clubPhotosLoading => 'Chargement des photos…';

  @override
  String get clubPhotosTitle => 'Photos';

  @override
  String get clubPhotosAdd => 'Ajouter une photo';

  @override
  String get clubPhotosEmpty => 'Aucune photo dans ce club pour l\'instant.';

  @override
  String get clubPhotosCaptionPendingHint =>
      'Légende (facultatif, 280 caractères)';

  @override
  String get clubPhotosCaptionHint => 'Légende…';

  @override
  String get clubPhotosCancel => 'Annuler';

  @override
  String get clubPhotosSave => 'Enregistrer';

  @override
  String get clubPhotosUpload => 'Téléverser';

  @override
  String get clubPhotosUploading => 'Téléversement…';

  @override
  String get clubPhotosEditCaption => 'Modifier la légende';

  @override
  String get clubPhotosDeleteTooltip => 'Supprimer la photo';

  @override
  String get clubPhotosDeleteTitle => 'Supprimer la photo ?';

  @override
  String get clubPhotosDeleteBody =>
      'La photo sera définitivement retirée du club.';

  @override
  String get clubPhotosDeleteConfirm => 'Supprimer';

  @override
  String clubPhotosPickerError(String error) {
    return 'Impossible d\'ouvrir le sélecteur : $error';
  }

  @override
  String clubPhotosUploadError(String error) {
    return 'Échec du téléversement : $error';
  }

  @override
  String clubPhotosDeleteError(String error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String clubPhotosCaptionError(String error) {
    return 'Impossible de mettre à jour la légende : $error';
  }

  @override
  String get runSegEffortsChecking => 'Vérification des segments…';

  @override
  String get runSegEffortsNoRoute =>
      'Les segments sont associés par itinéraire — liez cette course à un itinéraire enregistré pour figurer dans ses classements.';

  @override
  String get runSegEffortsEmpty => 'Aucun effort de segment sur cette course.';

  @override
  String get workoutReviewTitle => 'Séance';

  @override
  String get workoutReviewColStep => 'Étape';

  @override
  String get workoutReviewColPlan => 'Plan';

  @override
  String get workoutReviewColActual => 'Réel';

  @override
  String get workoutReviewColPace => 'Allure';

  @override
  String get workoutReviewColDelta => 'Δ';

  @override
  String get workoutReviewSkip => 'ignoré';

  @override
  String get workoutReviewLabelWarmup => 'Échauffement';

  @override
  String get workoutReviewLabelCooldown => 'Récupération';

  @override
  String get workoutReviewLabelSteady => 'Constant';

  @override
  String get workoutReviewLabelRep => 'Rép.';

  @override
  String workoutReviewLabelRepN(int index, int total) {
    return 'Rép. $index/$total';
  }

  @override
  String get workoutReviewLabelRecovery => 'Récup.';

  @override
  String workoutReviewLabelRecoveryN(int index, int total) {
    return 'Récup. $index/$total';
  }

  @override
  String get workoutReviewLabelWalk => 'Marche';

  @override
  String workoutReviewLabelWalkN(int index, int total) {
    return 'Marche $index/$total';
  }

  @override
  String get segmentsPanelTitle => 'Segments';

  @override
  String get segmentsPanelNew => 'Nouveau segment';

  @override
  String get segmentsPanelCancel => 'Annuler';

  @override
  String get segmentsPanelLoading => 'Chargement des segments…';

  @override
  String get segmentsPanelEmpty =>
      'Aucun segment sur cet itinéraire pour le moment.';

  @override
  String get segmentsPanelNameLabel => 'Nom';

  @override
  String get segmentsPanelNameHint => 'Montée infernale';

  @override
  String get segmentsPanelStartLabel => 'Début (m)';

  @override
  String get segmentsPanelEndLabel => 'Fin (m)';

  @override
  String segmentsPanelRouteHint(int metres) {
    return 'l\'itinéraire fait $metres m';
  }

  @override
  String get segmentsPanelCreate => 'Créer';

  @override
  String get segmentsPanelDeleteTooltip => 'Supprimer le segment';

  @override
  String get segmentsPanelDeleteTitle => 'Supprimer le segment ?';

  @override
  String segmentsPanelDeleteBody(String name) {
    return '« $name » sera supprimé.';
  }

  @override
  String get segmentsPanelDeleteConfirm => 'Supprimer';

  @override
  String get segmentsPanelErrEndAfterStart =>
      'La fin doit être supérieure au début';

  @override
  String get segmentsPanelErrMinLength =>
      'Le segment doit faire au moins 100 m';

  @override
  String segmentsPanelCreateError(String error) {
    return 'Impossible de créer le segment : $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String get segmentsPanelAllGenders => 'Tous les genres';

  @override
  String get segmentsPanelGenderMen => 'Hommes';

  @override
  String get segmentsPanelGenderWomen => 'Femmes';

  @override
  String get segmentsPanelGenderNonbinary => 'Non binaire';

  @override
  String get segmentsPanelAllAges => 'Tous les âges';

  @override
  String get segmentsPanelResetFilters => 'Réinitialiser';

  @override
  String get segmentsPanelLeaderboardLoading => 'Chargement…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'Aucun effort ne correspond à ce filtre — essayez de l\'élargir.';

  @override
  String get segmentsPanelLeaderboardEmpty =>
      'Aucun effort pour l\'instant — soyez le premier à courir ce segment.';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'Vous détenez cette couronne — $label.';
  }

  @override
  String get segmentsPanelRunnerFallback => 'Coureur';

  @override
  String get goalEditorTitleNew => 'Nouvel objectif';

  @override
  String get goalEditorTitleEdit => 'Modifier l\'objectif';

  @override
  String get goalEditorNameLabel => 'Nom (facultatif)';

  @override
  String get goalEditorNameHint => 'ex. Kilomètres de base';

  @override
  String get goalEditorPeriod => 'Période';

  @override
  String get goalEditorThisWeek => 'Cette semaine';

  @override
  String get goalEditorThisMonth => 'Ce mois-ci';

  @override
  String get goalEditorTargets => 'Cibles';

  @override
  String get goalEditorTargetsHelp =>
      'Définissez n\'importe quelle combinaison. Les champs vides sont ignorés.';

  @override
  String get goalEditorTargetDistance => 'Distance';

  @override
  String get goalEditorTargetTime => 'Temps';

  @override
  String get goalEditorTargetPace => 'Allure moy.';

  @override
  String get goalEditorTargetRuns => 'Courses';

  @override
  String get goalEditorSuffixMin => 'min';

  @override
  String get goalEditorSuffixRuns => 'courses';

  @override
  String get goalEditorDelete => 'Supprimer';

  @override
  String get goalEditorDeleteTitle => 'Supprimer cet objectif ?';

  @override
  String get goalEditorDeleteMessage =>
      'Cet objectif et son suivi de progression seront supprimés. Vous pouvez en créer un nouveau à tout moment.';

  @override
  String get goalEditorCancel => 'Annuler';

  @override
  String get goalEditorSave => 'Enregistrer';

  @override
  String goalEditorSaveFailed(String error) {
    return 'Impossible d\'enregistrer l\'objectif : $error';
  }

  @override
  String get goalEditorErrDistance => 'Distance : saisissez un nombre positif';

  @override
  String get goalEditorErrTime =>
      'Temps : saisissez un nombre de minutes positif';

  @override
  String get goalEditorErrPace => 'Allure : utilisez mm:ss (ex. 5:00)';

  @override
  String get goalEditorErrRuns => 'Courses : saisissez un entier positif';

  @override
  String get goalEditorErrNoTarget => 'Définissez au moins une cible';

  @override
  String get goalEditorSavedAnnounce => 'Objectif enregistré';

  @override
  String get goalEditorDeletedAnnounce => 'Objectif supprimé';

  @override
  String get eventFormTitle => 'Nouvel événement';

  @override
  String get eventFormTitleLabel => 'Titre';

  @override
  String get eventFormStartsAt => 'Commence le';

  @override
  String get eventFormDescriptionLabel => 'Description (facultatif)';

  @override
  String get eventFormMeetLabel => 'Point de rendez-vous (facultatif)';

  @override
  String get eventFormMeetHint => 'Parking du départ du sentier';

  @override
  String get eventFormDistanceLabel => 'Distance (km)';

  @override
  String get eventFormDurationLabel => 'Durée (min)';

  @override
  String get eventFormRecurrence => 'Récurrence';

  @override
  String get eventFormRecurOneOff => 'Unique';

  @override
  String get eventFormRecurWeekly => 'Hebdomadaire';

  @override
  String get eventFormRecurBiweekly => 'Bimensuel';

  @override
  String get eventFormRecurMonthly => 'Mensuel';

  @override
  String get eventFormCancel => 'Annuler';

  @override
  String get eventFormCreate => 'Créer l\'événement';

  @override
  String get eventEditorCategory => 'Type d\'événement';

  @override
  String get eventEditorCatRun => 'Course en groupe';

  @override
  String get eventEditorCatCycle => 'Vélo';

  @override
  String get eventEditorCatClass => 'Cours';

  @override
  String get eventEditorCatSocial => 'Rencontre';

  @override
  String get eventEditorCategoryHint =>
      'Choisissez le type d\'événement — un cours ou une rencontre ignore l\'itinéraire, la distance, l\'allure et les résultats de course.';

  @override
  String get eventEditorMembersOnlyToggle => 'Réservé aux membres';

  @override
  String get eventEditorMembersOnlyHint =>
      'Seuls les membres du club peuvent voir cet événement ; il n\'apparaîtra pas dans la découverte publique.';

  @override
  String get eventEditorDiscipline => 'Discipline';

  @override
  String get eventEditorDisciplinePlaceholder =>
      'ex. yoga Vinyasa, Pilates, mobilité';

  @override
  String get clubFormTitle => 'Nouveau club';

  @override
  String get clubFormNameLabel => 'Nom';

  @override
  String get clubFormDescriptionLabel => 'Description (facultatif)';

  @override
  String get clubFormLocationLabel => 'Lieu (facultatif)';

  @override
  String get clubFormLocationHint => 'Édimbourg, R.-U.';

  @override
  String get clubFormPublic => 'Public';

  @override
  String get clubFormPrivate => 'Privé';

  @override
  String get clubFormJoinPolicy => 'Politique d\'adhésion';

  @override
  String get clubFormJoinOpen => 'Ouvert — tout le monde rejoint';

  @override
  String get clubFormJoinRequest => 'Demande — les admins approuvent';

  @override
  String get clubFormJoinInvite => 'Sur invitation';

  @override
  String get clubFormCancel => 'Annuler';

  @override
  String get clubFormCreate => 'Créer';

  @override
  String get clubFormErrSlug =>
      'Le nom doit contenir au moins une lettre ou un chiffre.';

  @override
  String get clubFormErrUnreachable =>
      'Impossible de joindre le serveur pour le moment. Vérifiez votre connexion ou connectez-vous, puis réessayez.';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonHarassment => 'Harcèlement ou abus';

  @override
  String get reportReasonInappropriate => 'Contenu inapproprié';

  @override
  String get reportReasonImpersonation => 'Usurpation d\'identité';

  @override
  String get reportReasonOther => 'Autre';

  @override
  String get reportSuccess =>
      'Signalement envoyé — merci de l\'avoir signalé pour examen.';

  @override
  String get reportTitleUser => 'Signaler l\'utilisateur';

  @override
  String get reportTitleClub => 'Signaler le club';

  @override
  String get reportTitleRoute => 'Signaler l\'itinéraire';

  @override
  String get reportTitlePost => 'Signaler la publication';

  @override
  String get reportTitleRun => 'Signaler la course';

  @override
  String get reportTitleContent => 'Signaler le contenu';

  @override
  String get reportDisclaimer =>
      'Votre signalement est transmis à un modérateur. Les faux signalements sont aussi examinés — ne signalez que les contenus qui enfreignent nos règles de la communauté.';

  @override
  String get reportReason => 'Motif';

  @override
  String get reportNotesLabel => 'Notes (facultatif)';

  @override
  String get reportCancel => 'Annuler';

  @override
  String get reportSubmit => 'Envoyer le signalement';

  @override
  String get reportErrDuplicate =>
      'Vous avez déjà un signalement en attente concernant ce contenu.';

  @override
  String gearBackfillTitle(String gear) {
    return 'Associer les courses passées à $gear ?';
  }

  @override
  String gearBackfillBody(int count, String activity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activités de $activity',
      one: '$count activité de $activity',
    );
    return 'Nous avons trouvé $_temp0 après votre achat. Décochez celles où vous ne les portiez pas.';
  }

  @override
  String get gearBackfillActivityCycling => 'vélo';

  @override
  String get gearBackfillActivityRunning => 'course';

  @override
  String get gearBackfillSelectNone => 'Tout désélectionner';

  @override
  String get gearBackfillSelectAll => 'Tout sélectionner';

  @override
  String gearBackfillSelectedCount(int selected, int total) {
    return '$selected sur $total';
  }

  @override
  String get gearBackfillSkip => 'Ignorer';

  @override
  String get gearBackfillAttaching => 'Association…';

  @override
  String gearBackfillAttach(int count) {
    return 'Associer $count';
  }

  @override
  String gearBackfillAttachError(String error) {
    return 'Échec de l\'association : $error';
  }

  @override
  String get workoutEditTitle => 'Modifier la séance';

  @override
  String get workoutEditKindLabel => 'Type';

  @override
  String get workoutEditDistanceLabel => 'Distance cible (km)';

  @override
  String get workoutEditDistanceHint => 'ex. 8.0';

  @override
  String get workoutEditPaceLabel => 'Allure cible (mm:ss /km)';

  @override
  String get workoutEditPaceHint => 'ex. 5:30';

  @override
  String get workoutEditNotesLabel => 'Notes';

  @override
  String get workoutEditCancel => 'Annuler';

  @override
  String get workoutEditSave => 'Enregistrer';

  @override
  String get workoutEditErrDistance => 'Saisissez une distance positive en km';

  @override
  String get workoutEditErrPace => 'L\'allure doit ressembler à 5:30';

  @override
  String workoutEditSaveError(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return 'INSCRIT · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'Commence maintenant';

  @override
  String upcomingEventInMinutes(int count) {
    return 'Dans $count min';
  }

  @override
  String get upcomingEventInOneHour => 'Dans 1 heure';

  @override
  String upcomingEventInHours(int count) {
    return 'Dans $count heures';
  }

  @override
  String get upcomingEventTomorrow => 'Demain';

  @override
  String upcomingEventInDays(int count) {
    return 'Dans $count jours';
  }

  @override
  String get todaysWorkoutDone => 'FAIT AUJOURD\'HUI';

  @override
  String get todaysWorkoutToday => 'SÉANCE DU JOUR';

  @override
  String get errorStateRetry => 'Réessayer';

  @override
  String get shareCardRunTitle => 'Partager la course';

  @override
  String get shareCardExport => 'Exporter';

  @override
  String get shareCardImage => 'Image';

  @override
  String get shareCardStatDistance => 'Distance';

  @override
  String get shareCardStatTime => 'Temps';

  @override
  String get shareCardStatPace => 'Allure';

  @override
  String get shareCardStatSpeed => 'Vitesse';

  @override
  String get shareCardBrandRun => 'RUN';

  @override
  String get shareCardImageError => 'Impossible de créer l\'image de partage';

  @override
  String get shareCardFileError => 'Impossible d\'exporter le fichier';

  @override
  String get shareCardRouteTitle => 'Partager l\'itinéraire';

  @override
  String get shareCardRouteShareImage => 'Partager l\'image';

  @override
  String get shareCardRouteCapturing => 'Capture…';

  @override
  String get shareCardRouteStatDistance => 'Distance';

  @override
  String get shareCardRouteStatClimb => 'Dénivelé';

  @override
  String get billingToday => 'aujourd\'hui';

  @override
  String get billingYesterday => 'hier';

  @override
  String billingDaysAgo(int count) {
    return 'il y a $count jours';
  }

  @override
  String billingRenewalFailed(String relative) {
    return 'Le renouvellement Pro a échoué $relative.';
  }

  @override
  String get billingRenewalBody =>
      'Mettez à jour votre carte, sinon vous repasserez en Free.';

  @override
  String get billingManage => 'Gérer';

  @override
  String get planCalendarPrevMonth => 'Mois précédent';

  @override
  String get planCalendarNextMonth => 'Mois suivant';

  @override
  String runGearChipsLoadError(String error) {
    return 'Échec du chargement de l\'équipement : $error';
  }

  @override
  String get runGearChipsPickerTitle =>
      'Marquer l\'équipement utilisé sur cette course';

  @override
  String get runGearChipsEmpty =>
      'Vous n\'avez pas encore enregistré d\'équipement. Ajoutez-en dans Paramètres → Équipement.';

  @override
  String get runGearChipsCancel => 'Annuler';

  @override
  String get runGearChipsSave => 'Enregistrer';

  @override
  String get runGearChipsTag => '+ Marquer l\'équipement';

  @override
  String get runGearChipsEdit => 'Modifier';

  @override
  String runGearChipsSaveError(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get gearFormTitleEdit => 'Modifier l\'équipement';

  @override
  String get gearFormTitleAddShoes => 'Ajouter des chaussures';

  @override
  String get gearFormTitleAddBike => 'Ajouter un vélo';

  @override
  String get gearFormNameLabel => 'Nom';

  @override
  String get gearFormNameHint => 'Pegasus 39';

  @override
  String get gearFormBrandLabel => 'Marque';

  @override
  String get gearFormModelLabel => 'Modèle';

  @override
  String get gearFormBoughtLabel => 'Acheté';

  @override
  String get gearFormBoughtPick => 'Appuyez pour choisir';

  @override
  String gearFormRetireAt(String unit) {
    return 'Remplacer à ($unit)';
  }

  @override
  String get gearFormRetireHint => '500';

  @override
  String get gearFormNotesLabel => 'Notes';

  @override
  String get gearFormCancel => 'Annuler';

  @override
  String get gearFormSaving => 'Enregistrement…';

  @override
  String get gearFormSave => 'Enregistrer';

  @override
  String get gearFormAdd => 'Ajouter';

  @override
  String gearFormSaveError(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get gearWearLogHeading => 'Journal d\'usure';

  @override
  String get gearWearLogHint =>
      'Notez comment cet équipement vieillit — semelle extérieure usée, amorti mort, tige effilochée.';

  @override
  String get gearWearLogEmpty => 'Aucune observation d\'usure pour l\'instant.';

  @override
  String get gearWearLogAddNote => 'Observation';

  @override
  String get gearWearLogNoteHint =>
      'ex. crampons de la semelle lissés au talon';

  @override
  String get gearWearLogArea => 'Zone';

  @override
  String get gearWearLogAreaNone => '—';

  @override
  String get gearWearLogAreaOutsole => 'Semelle extérieure';

  @override
  String get gearWearLogAreaMidsole => 'Amorti';

  @override
  String get gearWearLogAreaUpper => 'Tige';

  @override
  String get gearWearLogAreaOther => 'Autre';

  @override
  String get gearWearLogAdd => 'Ajouter une observation';

  @override
  String get gearWearLogAdding => 'Ajout…';

  @override
  String get gearWearLogDelete => 'Supprimer l\'observation';

  @override
  String gearWearLogAddError(String error) {
    return 'Impossible d\'ajouter l\'observation : $error';
  }

  @override
  String gearWearLogDeleteError(String error) {
    return 'Impossible de supprimer l\'observation : $error';
  }

  @override
  String get notificationBellTooltip => 'Notifications';

  @override
  String get liveRunMapWaitingGps => 'En attente du GPS...';

  @override
  String get liveRunMapRecentre => 'Recentrer sur ma position';

  @override
  String get ttsRunStarted => 'Course démarrée';

  @override
  String ttsRunComplete(String distance, int mins) {
    return 'Course terminée. $distance en $mins minutes.';
  }

  @override
  String get ttsOffRoute => 'Hors itinéraire';

  @override
  String get ttsPaceAlertFast => 'Accélérez';

  @override
  String get ttsPaceAlertSlow => 'Ralentissez';

  @override
  String get ttsWorkoutComplete => 'Séance terminée. Beau travail.';

  @override
  String get ttsStepHalfway => 'Mi-parcours de cette répétition';

  @override
  String get ttsStepLastFifty => 'Plus que cinquante mètres';

  @override
  String ttsPaceDriftAhead(int delta) {
    return 'Relâchez un peu — $delta secondes trop rapide.';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return 'Accélérez un peu — $delta secondes trop lent.';
  }

  @override
  String ttsSpeedKm(String value) {
    return 'Vitesse, $value kilomètres heure';
  }

  @override
  String ttsSpeedMi(String value) {
    return 'Vitesse, $value miles à l’heure';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'Allure, $min minutes $sec secondes au kilomètre';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'Allure, $min minutes $sec secondes au mile';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$value kilomètres';
  }

  @override
  String ttsDistanceMetres(int value) {
    return '$value mètres';
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
  String get ttsStepWarmup => 'Échauffement';

  @override
  String get ttsStepRecovery => 'Récupération';

  @override
  String get ttsStepSteady => 'Allure régulière';

  @override
  String get ttsStepCooldown => 'Retour au calme';

  @override
  String get ttsStepRep => 'Répétition';

  @override
  String get ttsStepRun => 'Course';

  @override
  String get ttsStepWalk => 'Marche';

  @override
  String ttsStepRepOf(int index, int total) {
    return 'Répétition $index sur $total';
  }

  @override
  String ttsStepRunOf(int index, int total) {
    return 'Course $index sur $total';
  }

  @override
  String ttsStepWalkOf(int index, int total) {
    return 'Marche $index sur $total';
  }

  @override
  String ttsStepPaceKm(int min, int sec) {
    return '$min minutes $sec secondes au kilomètre';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '$min minutes au kilomètre';
  }

  @override
  String ttsStepPaceMi(int min, int sec) {
    return '$min minutes $sec secondes au mile';
  }

  @override
  String ttsStepPaceMiWhole(int min) {
    return '$min minutes au mile';
  }

  @override
  String ttsDurationSeconds(int sec) {
    return '$sec secondes';
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
    return '$minutes $sec secondes';
  }

  @override
  String ttsStepDuration(String intro, String duration) {
    return '$intro. $duration.';
  }

  @override
  String ttsStepDistancePace(String intro, String distance, String pace) {
    return '$intro. $distance à $pace.';
  }

  @override
  String get guidedEasy30Title => 'Course tranquille de 30 minutes';

  @override
  String get guidedEasy30Subtitle => 'Voix du coach · 30 min · effort facile';

  @override
  String get guidedEasy30Description =>
      'Une course détendue à allure de conversation, pour un jour de récupération ou simplement pour se vider la tête. Le coach intervient toutes les cinq minutes avec un petit encouragement.';

  @override
  String get guidedEasy30Cue0 =>
      'C’est parti. Commencez tranquillement — c’est votre allure de récupération.';

  @override
  String get guidedEasy30Cue1 =>
      'Cinq minutes. Relâchez les épaules. Restez à allure de conversation.';

  @override
  String get guidedEasy30Cue2 =>
      'Dix minutes. Vérifiez la cadence — pieds rapides, foulée légère.';

  @override
  String get guidedEasy30Cue3 =>
      'Mi-parcours. Vous devez encore pouvoir parler en courant.';

  @override
  String get guidedEasy30Cue4 =>
      'Vingt minutes. Surveillez votre respiration — inspiration lente par le nez, expiration par la bouche.';

  @override
  String get guidedEasy30Cue5 =>
      'Encore cinq minutes. Restez détendu. N’accélérez pas.';

  @override
  String get guidedEasy30Cue6 => 'Plus qu’une minute. Terminez en douceur.';

  @override
  String get guidedEasy30Cue7 =>
      'Terminé. Marchez une minute pour récupérer. Beau travail.';

  @override
  String get guidedTempo25Title => 'Développement de tempo de 25 minutes';

  @override
  String get guidedTempo25Subtitle => 'Voix du coach · 25 min · 5-15-5';

  @override
  String get guidedTempo25Description =>
      'Cinq minutes d’échauffement facile, quinze minutes au tempo (confortablement difficile), cinq minutes de retour au calme. La séance de tempo hebdomadaire de base.';

  @override
  String get guidedTempo25Cue0 =>
      'Échauffement. Cinq minutes tranquilles — réveillez les jambes.';

  @override
  String get guidedTempo25Cue1 =>
      'Plus qu’une minute d’échauffement. Augmentez la cadence.';

  @override
  String get guidedTempo25Cue2 =>
      'Passez au tempo. Confortablement difficile. Comme un effort de 10 km en course.';

  @override
  String get guidedTempo25Cue3 =>
      'Cinq minutes au tempo. Fort mais maîtrisé. Gardez le rythme.';

  @override
  String get guidedTempo25Cue4 =>
      'Dix minutes de tempo faites. Tenez l’allure.';

  @override
  String get guidedTempo25Cue5 =>
      'Plus que deux minutes au tempo. Restez fluide.';

  @override
  String get guidedTempo25Cue6 =>
      'Relâchez. Cinq minutes tranquilles pour récupérer.';

  @override
  String get guidedTempo25Cue7 =>
      'Plus que deux minutes. Faites redescendre la fréquence cardiaque.';

  @override
  String get guidedTempo25Cue8 =>
      'Terminé. Marchez et étirez-vous. Excellent travail.';

  @override
  String get guidedFirst15Title => 'Débutant : 15 minutes course/marche';

  @override
  String get guidedFirst15Subtitle =>
      'Voix du coach · 15 min · intervalles course/marche';

  @override
  String get guidedFirst15Description =>
      'Nouveau dans la course ? Trois séries d’une minute de course et une minute de marche, plus un échauffement et un retour au calme. Une mise en route en douceur ; tout le monde commence ici.';

  @override
  String get guidedFirst15Cue0 =>
      'Commencez par trois minutes de marche rapide pour vous échauffer.';

  @override
  String get guidedFirst15Cue1 =>
      'Passez à une minute de course facile. Allure de conversation.';

  @override
  String get guidedFirst15Cue2 => 'Marchez une minute.';

  @override
  String get guidedFirst15Cue3 => 'Courez une minute.';

  @override
  String get guidedFirst15Cue4 => 'Marchez une minute.';

  @override
  String get guidedFirst15Cue5 => 'Courez une minute.';

  @override
  String get guidedFirst15Cue6 => 'Marchez une minute.';

  @override
  String get guidedFirst15Cue7 => 'Courez une minute — la dernière.';

  @override
  String get guidedFirst15Cue8 =>
      'Revenez à la marche. Cinq minutes de retour au calme.';

  @override
  String get guidedFirst15Cue9 => 'Plus qu’une minute. Marchez tranquillement.';

  @override
  String get guidedFirst15Cue10 =>
      'Terminé. C’était une vraie course. Revenez vite courir.';

  @override
  String guidedRunMinutesBadge(int minutes) {
    return '$minutes min';
  }

  @override
  String guidedRunCueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count consignes sur la course',
      one: '$count consigne sur la course',
    );
    return '$_temp0';
  }

  @override
  String get guidedRunFullScript => 'LE SCRIPT COMPLET';

  @override
  String get guidedRunPreviewCue => 'Écouter la consigne';

  @override
  String guidedRunPreviewError(String error) {
    return 'Impossible d’écouter : $error';
  }

  @override
  String get ttsSplitUnitKilometre => 'kilomètre';

  @override
  String get ttsSplitUnitKilometres => 'kilomètres';

  @override
  String get ttsSplitUnitMile => 'mile';

  @override
  String get ttsSplitUnitMiles => 'miles';

  @override
  String get workoutKindEasy => 'Facile';

  @override
  String get workoutKindLong => 'Sortie longue';

  @override
  String get workoutKindRecovery => 'Récupération';

  @override
  String get workoutKindTempo => 'Tempo';

  @override
  String get workoutKindInterval => 'Fractionné';

  @override
  String get workoutKindMarathonPace => 'Allure marathon';

  @override
  String get workoutKindWalkRun => 'Marche-course';

  @override
  String get workoutKindRace => 'Course';

  @override
  String get workoutKindRest => 'Repos';

  @override
  String get planPhaseBase => 'Base';

  @override
  String get planPhaseBuild => 'Développement';

  @override
  String get planPhasePeak => 'Pic';

  @override
  String get planPhaseTaper => 'Affûtage';

  @override
  String get planPhaseRace => 'Semaine de course';

  @override
  String get runBackgroundLocationNudgeTitle =>
      'Autoriser la localisation en permanence';

  @override
  String get runBackgroundLocationNudgeBody =>
      'Android n\'a autorisé la localisation que lorsque l\'application est ouverte. Pour une distance précise lorsque votre écran est éteint, réglez l\'accès à la localisation sur « Toujours autoriser » dans les Réglages. Vous pouvez démarrer quand même — l\'enregistrement fonctionne tant que l\'application est à l\'écran.';

  @override
  String get runBatteryOptHintTitle =>
      'Maintenir l\'enregistrement actif en arrière-plan';

  @override
  String get runBatteryOptHintBody =>
      'Certains téléphones (Samsung, Xiaomi, OnePlus et d\'autres) mettent les applications en veille pour économiser la batterie, ce qui peut interrompre l\'enregistrement d\'une longue sortie lorsque votre écran est éteint. Par précaution, excluez cette application de l\'optimisation de la batterie dans les Réglages. Votre sortie sera enregistrée dans tous les cas — cela empêche simplement le système de l\'interrompre.';

  @override
  String shareCardCaption(Object title, Object distance, Object duration) {
    return '$title — $distance en $duration';
  }

  @override
  String get settingsBackendNotConfigured => 'Backend non configuré';

  @override
  String get settingsAccountSignedIn => 'Connecté';

  @override
  String get settingsDevicesSignedOutSubtitle =>
      'Connectez-vous pour gérer vos appareils';

  @override
  String get verifiedClubTooltip => 'Club officiel vérifié';

  @override
  String get raceDistance5k => '5 km';

  @override
  String get raceDistance10k => '10 km';

  @override
  String get raceDistanceHalfMarathon => 'Semi-marathon';

  @override
  String get raceDistanceMarathon => 'Marathon';

  @override
  String get settingsTabAccountSubtitle =>
      'Connexion, sauvegarde, suppression du compte';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Unités, thème, enregistrement, entraînement, confidentialité';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, ceinture cardiaque';

  @override
  String get settingsTabDevicesSubtitle =>
      'Où vous êtes connecté et réglages par appareil';

  @override
  String get settingsTabGearSubtitle =>
      'Suivez chaussures + vélos et le kilométrage par article';

  @override
  String get settingsTabCoachingSubtitle =>
      'Encadrez des athlètes ou suivez votre propre coach';

  @override
  String get settingsTabProSubtitle =>
      'S\'abonner, restaurer les achats, gérer la facturation';

  @override
  String get settingsTabLicensesSubtitle =>
      'Version de l\'app et mentions open source';

  @override
  String periodSummaryWeekOf(Object date) {
    return 'Semaine du $date';
  }

  @override
  String periodShareRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses',
      one: '1 course',
    );
    return '$_temp0';
  }

  @override
  String periodShareAvgPace(Object pace) {
    return 'Allure moy. : $pace';
  }

  @override
  String get gymTitle => 'Muscu';

  @override
  String get gymLog => 'Enregistrer une séance';

  @override
  String get gymUntitled => 'Séance sans titre';

  @override
  String get gymOfflineCached => 'Hors ligne – séances enregistrées affichées';

  @override
  String get gymOfflineQueued =>
      'Hors ligne – les modifications seront synchronisées plus tard';

  @override
  String get gymEmptyTitle => 'Aucune séance de muscu';

  @override
  String get gymEmptyBody =>
      'Enregistre une séance pour la suivre ici et alimenter ta charge d\'entraînement.';

  @override
  String get gymPrBadge => 'Record';

  @override
  String gymExercisesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercices',
      one: '$count exercice',
    );
    return '$_temp0';
  }

  @override
  String gymVolumeShort(int volume) {
    return '$volume kg';
  }

  @override
  String get gymNotFound => 'Séance introuvable.';

  @override
  String get gymEdit => 'Modifier';

  @override
  String get gymDelete => 'Supprimer';

  @override
  String get gymPublic => 'Public';

  @override
  String get gymPrivate => 'Privé';

  @override
  String get gymMakePublic => 'Rendre public';

  @override
  String get gymMakePrivate => 'Rendre privé';

  @override
  String gymVisibilityFailed(Object error) {
    return 'Impossible de mettre à jour la visibilité : $error';
  }

  @override
  String get gymNotes => 'Notes';

  @override
  String get gymKg => 'kg';

  @override
  String get gymReps => 'Réps';

  @override
  String get gymRpe => 'RPE';

  @override
  String get gymDuration => 'Temps (s)';

  @override
  String gymDurationValue(String seconds) {
    return '${seconds}s';
  }

  @override
  String gymSetN(int n) {
    return 'Série $n';
  }

  @override
  String get gymPrWeight => 'Plus lourde';

  @override
  String get gymPrVolume => 'Meilleur volume';

  @override
  String get gymPrE1rm => 'Meilleur 1RM est.';

  @override
  String get gymRecordsLink => 'Records';

  @override
  String get gymRecordsTitle => 'Records personnels';

  @override
  String get gymRecordsSubtitle =>
      'Ta meilleure performance pour chaque exercice avec charge.';

  @override
  String get gymRecordsEmpty =>
      'Aucun exercice avec charge enregistré. Ajoute un poids à une série pour suivre tes records.';

  @override
  String gymRecordsLastDone(String date) {
    return 'Dernier $date';
  }

  @override
  String gymRecordsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séances',
      one: '1 séance',
    );
    return '$_temp0';
  }

  @override
  String get gymExerciseBack => 'Retour aux records';

  @override
  String get gymExerciseEmpty => 'Aucun historique pour cet exercice.';

  @override
  String gymSinceFirstUp(String delta) {
    return '+$delta depuis la première séance';
  }

  @override
  String gymSinceFirstDown(String delta) {
    return '−$delta depuis la première séance';
  }

  @override
  String get gymSinceFirstFlat => 'aucun changement depuis la première séance';

  @override
  String gymDetailLastTime(String date) {
    return 'Dernière fois $date';
  }

  @override
  String get gymVolumeLabel => 'Volume';

  @override
  String get gymDeleteConfirmTitle => 'Supprimer la séance ?';

  @override
  String get gymDeleteConfirmBody =>
      'Cette action supprime définitivement la séance et ses séries.';

  @override
  String get clubEventMembersOnly => 'Membres uniquement';

  @override
  String get clubEventLogAsWorkout => 'Enregistrer comme séance';

  @override
  String get clubEventLogAsWorkoutHint =>
      'Ajoutez ce cours à votre propre journal de muscu — vous pouvez ajuster les détails avant d\'enregistrer.';

  @override
  String get clubEventLogAsWorkoutSaved => 'Ajouté à votre journal de muscu';

  @override
  String get clubEventDownloadCertificate => 'Certificat de finisher';

  @override
  String get clubEventCertificateShare => 'Enregistrer ou partager';

  @override
  String clubEventCertificateShareText(String event) {
    return 'J\'ai terminé $event !';
  }

  @override
  String get clubEventCertificateFailed =>
      'Impossible de générer le certificat. Veuillez réessayer.';

  @override
  String get clubEventCertificateHeading => 'Certificat de réussite';

  @override
  String get clubEventCertificateCertifies => 'Ceci certifie que';

  @override
  String get clubEventCertificateCompleted => 'a terminé';

  @override
  String get clubEventCertificateTime => 'Temps';

  @override
  String get clubEventCertificateDistance => 'Distance';

  @override
  String clubEventCertificatePlace(String place) {
    return '$place place';
  }

  @override
  String get gymEditorNewTitle => 'Nouvelle séance';

  @override
  String get gymEditorEditTitle => 'Modifier la séance';

  @override
  String get gymEditorTitleLabel => 'Titre (facultatif)';

  @override
  String get gymEditorTitlePlaceholder => 'ex. Jour push';

  @override
  String get gymEditorExercisePlaceholder => 'Nom de l\'exercice';

  @override
  String get gymEditorRemoveExercise => 'Supprimer l\'exercice';

  @override
  String get gymEditorRemoveSet => 'Supprimer la série';

  @override
  String get gymEditorAddSet => 'Ajouter une série';

  @override
  String get gymEditorAddExercise => 'Ajouter un exercice';

  @override
  String get gymEditorShare => 'Partager dans le fil';

  @override
  String get gymEditorCancel => 'Annuler';

  @override
  String get gymEditorSave => 'Enregistrer la séance';

  @override
  String get gymEditorNeedExercise =>
      'Ajoute au moins un exercice avec un nom.';

  @override
  String get gymCatalogueBrowse => 'Parcourir le catalogue';

  @override
  String get gymCatalogueTitle => 'Catalogue d’exercices';

  @override
  String get gymCatalogueSearchPlaceholder => 'Rechercher des exercices';

  @override
  String get gymCatalogueCategoryLabel => 'Catégorie';

  @override
  String get gymCatalogueEmpty => 'Aucun exercice ne correspond.';

  @override
  String get gymCatalogueCustomBadge => 'Perso';

  @override
  String gymCatalogueCreate(String name) {
    return 'Ajouter « $name » comme exercice personnalisé';
  }

  @override
  String get gymCatalogueCreateFailed => 'Impossible d’ajouter cet exercice.';

  @override
  String get gymCatalogueCategoryAll => 'Tous';

  @override
  String get gymCatalogueCategoryChest => 'Pectoraux';

  @override
  String get gymCatalogueCategoryBack => 'Dos';

  @override
  String get gymCatalogueCategoryShoulders => 'Épaules';

  @override
  String get gymCatalogueCategoryLegs => 'Jambes';

  @override
  String get gymCatalogueCategoryArms => 'Bras';

  @override
  String get gymCatalogueCategoryCore => 'Gainage';

  @override
  String get gymCatalogueCategoryCardio => 'Cardio';

  @override
  String get gymCatalogueCategoryFullBody => 'Corps entier';

  @override
  String get gymCatalogueCategoryOther => 'Autre';

  @override
  String get gymSaveFailed => 'Impossible d\'enregistrer la séance.';

  @override
  String get gymRoutineLink => 'Routines';

  @override
  String get gymRoutineTitle => 'Routines';

  @override
  String get gymRoutineNew => 'Nouvelle routine';

  @override
  String get gymRoutineBack => 'Retour aux routines';

  @override
  String get gymRoutineNotFound => 'Routine introuvable.';

  @override
  String gymRoutineExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercices',
      one: '$count exercice',
    );
    return '$_temp0';
  }

  @override
  String get gymRoutineStart => 'Démarrer la routine';

  @override
  String get gymRoutinePublishLabel => 'Publier dans un club';

  @override
  String get gymRoutinePublishPick => 'Choisir un club…';

  @override
  String get gymRoutinePublish => 'Publier';

  @override
  String get gymRoutinePublishSuccess => 'Routine publiée dans le club.';

  @override
  String get gymRoutinePublishFailed => 'Impossible de publier la routine.';

  @override
  String get gymRoutineClubTemplateBadge => 'Modèle du club';

  @override
  String get gymRoutinePublicBadge => 'Dans la bibliothèque publique';

  @override
  String get gymRoutinePublishPublicLabel => 'Bibliothèque publique';

  @override
  String get gymRoutinePublishPublic => 'Publier dans la bibliothèque publique';

  @override
  String get gymRoutineUnpublishPublic => 'Retirer de la bibliothèque publique';

  @override
  String get gymRoutinePublishPublicHint =>
      'Toute personne connectée peut prévisualiser et adopter cette routine. Les séances enregistrées restent privées.';

  @override
  String get gymRoutinePublishPublicSuccess =>
      'Routine publiée dans la bibliothèque publique.';

  @override
  String get gymRoutineUnpublishPublicSuccess =>
      'Routine retirée de la bibliothèque publique.';

  @override
  String get gymRoutinePublishPublicFailed =>
      'Impossible de modifier la visibilité publique.';

  @override
  String get gymLibraryLink => 'Bibliothèque';

  @override
  String get gymLibraryTitle => 'Bibliothèque publique de routines';

  @override
  String get gymLibrarySearchHint => 'Rechercher des routines par nom';

  @override
  String get gymLibraryLoadError => 'Impossible de charger la bibliothèque.';

  @override
  String get gymLibraryEmpty => 'Aucune routine publiée pour l’instant.';

  @override
  String gymLibraryEmptySearch(String query) {
    return 'Aucune routine ne correspond à \"$query\".';
  }

  @override
  String gymLibraryByAuthor(String author) {
    return 'par $author';
  }

  @override
  String get gymLibraryAnonymous => 'un pratiquant';

  @override
  String get gymLibraryAdopt => 'Adopter dans mes routines';

  @override
  String get gymLibraryAdopting => 'Adoption…';

  @override
  String get gymLibraryAdoptFailed => 'Impossible d’adopter la routine.';

  @override
  String get gymRoutineDelete => 'Supprimer';

  @override
  String get gymRoutineDeleteConfirmTitle => 'Supprimer la routine ?';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'Cela supprime définitivement la routine. Les séances enregistrées ne sont pas affectées.';

  @override
  String get gymRoutineDeleted => 'Routine supprimée';

  @override
  String get gymRoutineCreated => 'Routine enregistrée';

  @override
  String get gymRoutineSaveFailed => 'Impossible d\'enregistrer la routine.';

  @override
  String get gymRoutineEmptyTitle => 'Aucune routine';

  @override
  String get gymRoutineEmptyBody =>
      'Enregistrez une séance comme routine, ou créez-en une, pour la réutiliser.';

  @override
  String get gymRoutineTargetReps => 'Répétitions cibles';

  @override
  String gymRoutineTargetWeight(String unit) {
    return 'Charge cible ($unit)';
  }

  @override
  String get gymRoutineEditorNewTitle => 'Nouvelle routine';

  @override
  String get gymRoutineEditorTitleLabel => 'Nom de la routine';

  @override
  String get gymRoutineEditorTitlePlaceholder => 'ex. Jour poussée A';

  @override
  String get gymRoutineEditorNotesLabel => 'Notes (facultatif)';

  @override
  String get gymRoutineEditorSave => 'Enregistrer la routine';

  @override
  String get gymRoutineEditorCancel => 'Annuler';

  @override
  String get gymRoutineEditorNeedTitle => 'Donnez un nom à la routine.';

  @override
  String get gymRoutineEditorNeedExercise =>
      'Ajoutez au moins un exercice avec un nom.';

  @override
  String get gymRoutineSaveAsRoutine => 'Enregistrer comme routine';

  @override
  String get gymRoutineRepeatLast => 'Répéter la dernière';

  @override
  String get gymRoutineTargetRepsMax => 'à';

  @override
  String get gymRoutineTargetDuration => 'Temps cible (s)';

  @override
  String get gymRoutineTargetDistance => 'Distance cible (m)';

  @override
  String get gymRoutineRestLabel => 'Repos (s)';

  @override
  String get gymRoutineSetType => 'Type de série';

  @override
  String get gymRoutineSetTypeWarmup => 'Échauffement';

  @override
  String get gymRoutineSetTypeWorking => 'Série de travail';

  @override
  String get gymRoutineSetTypeDropset => 'Drop set';

  @override
  String get gymRoutineSetTypeAmrap => 'AMRAP';

  @override
  String get gymRoutineSetTypeFailure => 'Jusqu\'à l\'échec';

  @override
  String get gymRoutineSetTypeBackoff => 'Back-off';

  @override
  String get gymRoutineModality => 'Mesuré en';

  @override
  String get gymRoutineModalityWeightReps => 'Poids × répétitions';

  @override
  String get gymRoutineModalityTime => 'Temps';

  @override
  String get gymRoutineModalityDistance => 'Distance';

  @override
  String get gymRoutineModalityBodyweightReps =>
      'Répétitions au poids du corps';

  @override
  String get gymRoutineSupersetToggle => 'Superset avec l\'exercice suivant';

  @override
  String gymRoutineSupersetBadge(int group) {
    return 'Superset $group';
  }

  @override
  String get gymRoutineAdvanced => 'Avancé';

  @override
  String get gymRoutineProgression => 'Progression';

  @override
  String get gymRoutineProgressionNone => 'Aucune';

  @override
  String get gymRoutineProgressionLinear => 'Linéaire';

  @override
  String get gymRoutineProgressionDoubleProgression => 'Double progression';

  @override
  String get gymRoutineProgressionFiveByFive => '5×5';

  @override
  String get gymRoutineProgressionPercentCycle => 'Cycle % du 1RM';

  @override
  String get gymRoutineProgressionRpeAutoreg => 'Autorégulation RPE';

  @override
  String gymRoutineProgressionIncrementLabel(String unit) {
    return 'Pas de poids ($unit)';
  }

  @override
  String get gymRoutineProgressionPercentLabel => '% du 1RM';

  @override
  String gymRoutineProgressionOneRmLabel(String unit) {
    return '1RM ($unit)';
  }

  @override
  String get gymRoutineProgressionTargetRpeLabel => 'RPE cible';

  @override
  String get gymRoutineNextTarget => 'Prochain objectif';

  @override
  String get gymRoutineNextTargetIncreaseWeight =>
      'Augmenter la charge la prochaine fois';

  @override
  String get gymRoutineNextTargetIncreaseReps =>
      'Augmenter les répétitions la prochaine fois';

  @override
  String get gymRoutineNextTargetHold => 'Maintenir — répéter cet objectif';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — réduire la charge';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'montée de répétitions $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrition';

  @override
  String get nutritionLogFood => 'Enregistrer un aliment';

  @override
  String get nutritionCalories => 'Calories';

  @override
  String get nutritionProtein => 'Protéines';

  @override
  String get nutritionCarbs => 'Glucides';

  @override
  String get nutritionFat => 'Lipides';

  @override
  String get nutritionWater => 'Eau';

  @override
  String get nutritionWaterAdd => 'Ajouter de l\'eau';

  @override
  String get nutritionWaterRemove => 'Retirer de l\'eau';

  @override
  String get nutritionNoTargets =>
      'Renseigne ta taille, ton poids, ton âge et ton sexe dans l\'app web pour voir les objectifs de calories et de macros.';

  @override
  String get nutritionWeeklyTrend => '7 derniers jours';

  @override
  String nutritionCaloriesLeft(int n) {
    return '$n kcal restantes';
  }

  @override
  String nutritionCaloriesOver(int n) {
    return '$n kcal de trop';
  }

  @override
  String get nutritionOnTarget => 'Objectif atteint';

  @override
  String nutritionMacroOver(int n) {
    return '$n au-dessus de l\'objectif';
  }

  @override
  String get nutritionMacroReached => 'Objectif atteint';

  @override
  String nutritionWaterAmount(String consumed, String target) {
    return '$consumed / $target L';
  }

  @override
  String get nutritionWaterGoalReached => 'Objectif atteint';

  @override
  String nutritionWaterRemaining(int n) {
    return '$n ml restants';
  }

  @override
  String get nutritionWeekOnGoal => 'Objectif atteint';

  @override
  String nutritionWeekUnderGoal(int n) {
    return '$n sous l\'objectif/jour';
  }

  @override
  String nutritionWeekOverGoal(int n) {
    return '$n au-dessus/jour';
  }

  @override
  String get nutritionGoalLine => 'Objectif quotidien';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return 'Objectif $base + $exercise kcal brûlées aujourd\'hui';
  }

  @override
  String get dashGymReadinessIncluded =>
      'Tes séances de muscu récentes sont prises en compte dans ta fatigue.';

  @override
  String get dashGymReadinessExcluded =>
      'La charge de muscu est exclue de ta forme à la course.';

  @override
  String get prefsExcludeGymFromReadiness =>
      'Exclure la charge de muscu de la forme à la course';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'Par défaut, les séances de muscu augmentent ta fatigue et réduisent ta forme, comme une course. Active ceci pour que ta forme, ta fatigue et ta fraîcheur ne reposent que sur les courses.';

  @override
  String get nutritionEmptyTitle => 'Rien d\'enregistré aujourd\'hui';

  @override
  String get nutritionEmptyBody =>
      'Enregistre un repas pour suivre tes calories et tes macros.';

  @override
  String get nutritionSlotBreakfast => 'Petit-déjeuner';

  @override
  String get nutritionSlotLunch => 'Déjeuner';

  @override
  String get nutritionSlotDinner => 'Dîner';

  @override
  String get nutritionSlotSnack => 'En-cas';

  @override
  String get nutritionMealProtein => 'Protéines';

  @override
  String get nutritionMealCarbs => 'Glucides';

  @override
  String get nutritionMealFat => 'Lipides';

  @override
  String get nutritionMealItemsHeading => 'Aliments';

  @override
  String get nutritionMealNoItems => 'Rien enregistré pour ce repas.';

  @override
  String get nutritionMealTrendHeading => '7 derniers jours';

  @override
  String get nutritionDelete => 'Supprimer';

  @override
  String get nutritionDeleteEntryTitle => 'Supprimer cette entrée ?';

  @override
  String nutritionDeleteEntryMessage(String item) {
    return '$item sera retiré du journal d\'aujourd\'hui.';
  }

  @override
  String get nutritionOfflineQueued =>
      'Hors ligne — les modifications se synchroniseront à la reconnexion';

  @override
  String get nutritionOfflineCached =>
      'Hors ligne — affichage des entrées enregistrées';

  @override
  String get nutritionLogTitle => 'Enregistrer un aliment';

  @override
  String get nutritionSearchHint => 'Rechercher un aliment';

  @override
  String get nutritionSearching => 'Recherche…';

  @override
  String get nutritionNoResults =>
      'Aucun résultat. Essaie un autre terme ou saisis-le manuellement ci-dessous.';

  @override
  String get nutritionSearchFailed =>
      'Échec de la recherche. Vérifie ta connexion, puis réessaie ou saisis-le manuellement ci-dessous.';

  @override
  String get nutritionSearchRetry => 'Réessayer la recherche';

  @override
  String get nutritionSourceOff => 'Open Food Facts';

  @override
  String get nutritionSourceUsda => 'USDA';

  @override
  String get nutritionScanBarcode => 'Scanner le code-barres';

  @override
  String get nutritionScanHint =>
      'Pointe la caméra vers un code-barres produit';

  @override
  String get nutritionScanLookingUp => 'Recherche…';

  @override
  String get nutritionScanNotFound =>
      'Aucun produit trouvé pour ce code-barres. Fais une recherche ou saisis-le manuellement.';

  @override
  String get nutritionScanFailed =>
      'Échec du scan. Fais une recherche ou saisis-le manuellement.';

  @override
  String get nutritionScanPermissionDenied =>
      'L\'accès à la caméra est nécessaire pour scanner un code-barres. Tu peux toujours faire une recherche ou saisir l\'aliment manuellement.';

  @override
  String get nutritionScanOpenSettings => 'Ouvrir les réglages';

  @override
  String get nutritionSaveFailed =>
      'Impossible d\'enregistrer l\'aliment. Réessaie.';

  @override
  String get nutritionMealSlot => 'Repas';

  @override
  String get nutritionManualEntry => 'Saisir manuellement';

  @override
  String get nutritionItemName => 'Nom de l\'aliment';

  @override
  String get nutritionPortionGrams => 'Portion (g)';

  @override
  String get nutritionAdd => 'Ajouter';

  @override
  String get nutritionCancel => 'Annuler';

  @override
  String get nutritionTemplates => 'Modèles de repas';

  @override
  String get nutritionSaveAsMeal => 'Enregistrer comme repas';

  @override
  String get nutritionSaveAsMealTitle => 'Enregistrer comme modèle de repas';

  @override
  String get nutritionTemplateName => 'Nom du modèle';

  @override
  String get nutritionTemplateNamePlaceholder =>
      'ex. Petit-déjeuner avant la course';

  @override
  String get nutritionSaveTemplate => 'Enregistrer le repas';

  @override
  String get nutritionTemplateSaved => 'Modèle de repas enregistré.';

  @override
  String nutritionTemplateSaveFailed(String error) {
    return 'Impossible d’enregistrer le modèle : $error';
  }

  @override
  String get nutritionLogTemplate => 'Enregistrer';

  @override
  String nutritionTemplateLogged(int n, String name) {
    return '$n éléments enregistrés depuis $name.';
  }

  @override
  String nutritionTemplateLogFailed(String error) {
    return 'Impossible d’enregistrer le modèle : $error';
  }

  @override
  String nutritionTemplateItems(int n) {
    return '$n éléments';
  }

  @override
  String get nutritionDeleteTemplate => 'Supprimer';

  @override
  String get nutritionDeleteTemplateTitle => 'Supprimer ce modèle de repas ?';

  @override
  String nutritionDeleteTemplateMessage(String name) {
    return '$name sera supprimé. Les repas déjà enregistrés à partir de celui-ci restent dans ton journal.';
  }

  @override
  String get nutritionRecipes => 'Recettes';

  @override
  String get nutritionSaveAsRecipe => 'Enregistrer comme recette';

  @override
  String get nutritionSaveAsRecipeTitle => 'Enregistrer comme recette';

  @override
  String get nutritionRecipeName => 'Nom de la recette';

  @override
  String get nutritionRecipeNamePlaceholder => 'ex. Bol poulet et riz';

  @override
  String get nutritionRecipeServings => 'Portions';

  @override
  String get nutritionRecipeServingsHint =>
      'Les ingrédients sont additionnés puis divisés par le nombre de portions. Enregistrer une portion ajoute une seule entrée avec les macros combinés.';

  @override
  String get nutritionSaveRecipe => 'Enregistrer la recette';

  @override
  String get nutritionRecipeSaved => 'Recette enregistrée.';

  @override
  String nutritionRecipeSaveFailed(String error) {
    return 'Impossible d’enregistrer la recette : $error';
  }

  @override
  String get nutritionLogRecipe => 'Enregistrer';

  @override
  String nutritionRecipeLogged(int n, String name) {
    return '$name enregistrée ($n portion).';
  }

  @override
  String nutritionRecipeLogFailed(String error) {
    return 'Impossible d’enregistrer la recette : $error';
  }

  @override
  String nutritionRecipeMeta(int n, num servings) {
    final intl.NumberFormat servingsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String servingsString = servingsNumberFormat.format(servings);

    return '$n ingrédients · $servingsString portions';
  }

  @override
  String get nutritionDeleteRecipe => 'Supprimer';

  @override
  String get nutritionDeleteRecipeTitle => 'Supprimer cette recette ?';

  @override
  String nutritionDeleteRecipeMessage(String name) {
    return '$name sera supprimée. Les repas déjà enregistrés à partir d’elle restent dans ton journal.';
  }

  @override
  String get sessionTitle => 'Séances';

  @override
  String get sessionEmpty => 'Aucun plan de séance pour le moment.';

  @override
  String get sessionEmptyHint =>
      'Créez sur le web une séquence de yoga, pilates ou cours réutilisable.';

  @override
  String get sessionUntitled => 'Séance sans titre';

  @override
  String get sessionNotFound => 'Plan de séance introuvable.';

  @override
  String get sessionMakePublic => 'Rendre public';

  @override
  String get sessionMakePrivate => 'Rendre privé';

  @override
  String get sessionVisibilityError => 'Impossible de modifier la visibilité.';

  @override
  String get sessionSteps => 'Séquence';

  @override
  String sessionStepHold(Object name, Object seconds) {
    return '$name · tenue ${seconds}s';
  }

  @override
  String sessionStepReps(Object name, Object reps) {
    return '$name · $reps répét.';
  }

  @override
  String sessionStepFlow(Object name, Object seconds) {
    return '$name · flow ${seconds}s';
  }

  @override
  String sessionSideLeft(Object name) {
    return '$name (gauche)';
  }

  @override
  String sessionSideRight(Object name) {
    return '$name (droite)';
  }

  @override
  String sessionEstDuration(Object minutes) {
    return '~ $minutes min';
  }

  @override
  String get gymSessionStart => 'Démarrer la séance';

  @override
  String gymSessionStep(Object exercise, Object set, Object total) {
    return '$exercise · série $set sur $total';
  }

  @override
  String get gymSessionComplete => 'Séance terminée';

  @override
  String get gymSessionSkipSet => 'Passer la série';

  @override
  String get gymSessionRewind => 'Précédent';

  @override
  String get gymSessionAbandon => 'Abandonner';

  @override
  String get gymSessionFinish => 'Terminer';

  @override
  String get gymSessionDiscardTitle => 'Abandonner la séance ?';

  @override
  String get gymSessionDiscardBody =>
      'Votre progression dans cette séance ne sera pas enregistrée.';

  @override
  String get gymSessionDiscardConfirm => 'Abandonner';

  @override
  String get gymSessionSaved => 'Entraînement enregistré';

  @override
  String get gymSessionSaveFailed =>
      'Impossible d\'enregistrer l\'entraînement';

  @override
  String gymSessionSetProgress(Object done, Object total) {
    return '$done/$total';
  }

  @override
  String get gymSessionLogSet => 'Terminer la série';

  @override
  String get gymSessionRest => 'Récupération';

  @override
  String gymSessionRestRemaining(Object seconds) {
    return 'Récup. ${seconds}s';
  }

  @override
  String get gymSessionRestSkip => 'Passer la récup.';

  @override
  String get gymSessionTarget => 'Objectif';

  @override
  String gymReviewAdherence(Object pct) {
    return '$pct% de respect';
  }

  @override
  String get gymReviewVerdictCompleted => 'Terminée';

  @override
  String get gymReviewVerdictPartial => 'Partiellement faite';

  @override
  String get gymReviewVerdictAbandoned => 'Abandonnée';

  @override
  String get gymReviewStatusHit => 'Atteint';

  @override
  String get gymReviewStatusPartial => 'Partiel';

  @override
  String get gymReviewStatusMissed => 'Manqué';

  @override
  String get gymReviewStatusExtra => 'Bonus';

  @override
  String get sessionRunStart => 'Démarrer la séance';

  @override
  String sessionRunStep(Object name) {
    return '$name';
  }

  @override
  String get sessionRunDone => 'Terminé';

  @override
  String get sessionRunSkip => 'Passer';

  @override
  String get sessionRunPause => 'Pause';

  @override
  String get sessionRunResume => 'Reprendre';

  @override
  String get sessionRunAbandon => 'Abandonner';

  @override
  String get sessionRunFinish => 'Terminer';

  @override
  String sessionRunRemaining(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get sessionRunComplete => 'Séance terminée';

  @override
  String get sessionRunSaved => 'Séance enregistrée';

  @override
  String get sessionRunSaveFailed => 'Impossible d\'enregistrer la séance';

  @override
  String get sessionRunDiscardTitle => 'Abandonner la séance ?';

  @override
  String get sessionRunDiscardBody =>
      'Votre progression dans cette séance ne sera pas enregistrée.';

  @override
  String get sessionRunDiscardConfirm => 'Abandonner';

  @override
  String get sessionRunVerdictCompleted => 'Terminée';

  @override
  String get sessionRunVerdictPartial => 'Partiellement faite';

  @override
  String get sessionRunVerdictAbandoned => 'Abandonnée';

  @override
  String sessionRunStepCount(int index, int total) {
    return 'Étape $index sur $total';
  }

  @override
  String get sessionRunSwitchSides => 'Changez de côté';

  @override
  String get coachingTitle => 'Coaching';

  @override
  String get coachingLede =>
      'Encadrez des athlètes en partageant un lien d\'invitation, puis suivez leur entraînement. Ou suivez votre propre coach ici.';

  @override
  String get coachingCancel => 'Annuler';

  @override
  String get coachingMyAthletes => 'Mes athlètes';

  @override
  String get coachingMyAthletesSub => 'Coureurs ayant accepté votre invitation';

  @override
  String get coachingInviteAnAthlete => 'Inviter un athlète';

  @override
  String get coachingCreating => 'Création…';

  @override
  String get coachingPendingInvite => 'Invitation en attente';

  @override
  String coachingPendingInviteSub(String date) {
    return 'Créée le $date · pas encore acceptée';
  }

  @override
  String get coachingCopyLink => 'Copier le lien';

  @override
  String get coachingShareLink => 'Partager le lien';

  @override
  String get coachingRevoke => 'Révoquer';

  @override
  String get coachingNoAthletes =>
      'Aucun athlète pour l\'instant. Invitez-en un pour commencer.';

  @override
  String get coachingRosterTitle => 'Liste des athlètes';

  @override
  String get coachingRosterSubtitle =>
      'Tous vos athlètes en un coup d\'œil — charge, suivi du plan et risque de blessure.';

  @override
  String get coachingRosterNeverRun => 'Aucune course';

  @override
  String get coachingRosterNoPlan => 'Aucun plan';

  @override
  String get coachingRosterRiskInsufficient => 'Nouveau';

  @override
  String get coachingRosterRiskLow => 'Faible';

  @override
  String get coachingRosterRiskOptimal => 'Optimal';

  @override
  String get coachingRosterRiskElevated => 'Élevé';

  @override
  String get coachingRosterRiskHigh => 'Très élevé';

  @override
  String get coachingRunner => 'Coureur';

  @override
  String coachingCoachingSince(String date) {
    return 'Coaching depuis le $date';
  }

  @override
  String get coachingReview => 'Examiner';

  @override
  String get coachingRemove => 'Retirer';

  @override
  String get coachingMyCoaches => 'Mes coachs';

  @override
  String get coachingMyCoachesSub =>
      'Coachs qui peuvent voir votre entraînement';

  @override
  String get coachingNoCoaches =>
      'Vous n\'avez pas encore accepté d\'invitation de coach.';

  @override
  String get coachingCoach => 'Coach';

  @override
  String coachingLinkedSince(String date) {
    return 'Lié depuis le $date';
  }

  @override
  String get coachingLeave => 'Quitter';

  @override
  String get coachingInviteLinkCopied => 'Lien d\'invitation copié';

  @override
  String get coachingThisAthlete => 'cet athlète';

  @override
  String get coachingThisCoach => 'ce coach';

  @override
  String get coachingRevokeTitle => 'Révoquer l\'invitation ?';

  @override
  String get coachingRevokeBody =>
      'Le lien d\'invitation cessera de fonctionner. Vous pouvez toujours en créer un nouveau.';

  @override
  String get coachingRemoveAthleteTitle => 'Retirer l\'athlète ?';

  @override
  String coachingRemoveAthleteBody(String name) {
    return 'Arrêter le coaching de $name ? Vous perdrez l\'accès à ses courses et plans.';
  }

  @override
  String get coachingLeaveCoachTitle => 'Quitter le coach ?';

  @override
  String coachingLeaveCoachBody(String name) {
    return 'Ne plus partager votre entraînement avec $name ?';
  }

  @override
  String coachingLoadError(String error) {
    return 'Impossible de charger le coaching : $error';
  }

  @override
  String coachingCreateInviteError(String error) {
    return 'Impossible de créer l\'invitation : $error';
  }

  @override
  String coachingRevokeInviteError(String error) {
    return 'Impossible de révoquer l\'invitation : $error';
  }

  @override
  String coachingRemoveAthleteError(String error) {
    return 'Impossible de retirer l\'athlète : $error';
  }

  @override
  String coachingEndLinkError(String error) {
    return 'Impossible de mettre fin au lien : $error';
  }

  @override
  String get coachingAthleteAthleteFallback => 'Athlète';

  @override
  String get coachingAthleteRunnerFallback => 'Coureur';

  @override
  String coachingAthleteCoachingSince(String date) {
    return 'Coaching depuis le $date';
  }

  @override
  String get coachingAthletePlanCompliance => 'Suivi du plan';

  @override
  String get coachingAthleteNoActivePlan => 'Aucun plan d\'entraînement actif.';

  @override
  String get coachingAthleteAssignTitle => 'Attribuer un plan';

  @override
  String coachingAthleteAssignHint(String name) {
    return 'Choisissez l\'un de vos plans à attribuer à $name.';
  }

  @override
  String get coachingAthleteAssignSelectLabel => 'Plan';

  @override
  String get coachingAthleteAssignSelectPlaceholder => 'Choisir un plan…';

  @override
  String get coachingAthleteAssignStartLabel => 'Date de début';

  @override
  String get coachingAthleteAssigning => 'Attribution…';

  @override
  String get coachingAthleteAssignButton => 'Attribuer le plan';

  @override
  String get coachingAthleteAssignNoPlans =>
      'Créez d\'abord un plan d\'entraînement, puis vous pourrez l\'attribuer à vos athlètes.';

  @override
  String get coachingAthleteAssignedByYou => 'Attribué par vous';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'Cet athlète a déjà un plan actif. Il devra le terminer ou y mettre fin avant que vous puissiez en attribuer un nouveau.';

  @override
  String get coachingAthleteComplete => 'terminé';

  @override
  String coachingAthleteDoneCount(int done, int total) {
    return '$done sur $total faits';
  }

  @override
  String coachingAthleteMissedCount(int n) {
    return '$n manqués';
  }

  @override
  String get coachingAthleteStatusDone => 'Fait';

  @override
  String get coachingAthleteStatusMissed => 'Manqué';

  @override
  String get coachingAthleteStatusUpcoming => 'À venir';

  @override
  String get coachingAthleteRecentRuns => 'Courses récentes';

  @override
  String get coachingAthleteNoRunsYet =>
      'Aucune course enregistrée pour l\'instant.';

  @override
  String get coachingAthletePrivate => 'Privé';

  @override
  String coachingAthleteAssignSuccess(String name) {
    return 'Plan attribué à $name';
  }

  @override
  String coachingAthleteLoadError(String error) {
    return 'Impossible de charger l\'athlète : $error';
  }

  @override
  String get routeMarkerHeading => 'Repères de parcours';

  @override
  String get routeMarkerAdd => 'Ajouter un repère';

  @override
  String get routeMarkerEmpty =>
      'Aucun repère de parcours. Ajoutez des ravitaillements, des barrières horaires et plus le long du parcours.';

  @override
  String get routeMarkerEdit => 'Modifier le repère';

  @override
  String get routeMarkerDelete => 'Supprimer';

  @override
  String get routeMarkerCancel => 'Annuler';

  @override
  String get routeMarkerSave => 'Enregistrer';

  @override
  String get routeMarkerSaving => 'Enregistrement…';

  @override
  String get routeMarkerKindLabel => 'Type';

  @override
  String get routeMarkerNameLabel => 'Nom';

  @override
  String get routeMarkerNamePlaceholder => 'ex. Ravito 2';

  @override
  String get routeMarkerServicesLabel => 'Services';

  @override
  String get routeMarkerCutoffLabel => 'Barrière horaire';

  @override
  String get routeMarkerNoteLabel => 'Note';

  @override
  String get routeMarkerTapToPlace => 'Touchez la carte pour placer ce repère.';

  @override
  String get routeMarkerPlaced =>
      'Placé. Touchez à nouveau la carte pour le déplacer.';

  @override
  String routeMarkerCutoffAt(String time) {
    return 'Barrière $time';
  }

  @override
  String get routeMarkerLabelRequired => 'Donnez un nom au repère.';

  @override
  String get routeMarkerPlaceRequired =>
      'Placez d\'abord le repère sur la carte.';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Impossible d\'enregistrer le repère : $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Impossible de supprimer le repère : $error';
  }

  @override
  String get routeMarkerDeleteConfirmTitle => 'Supprimer le repère ?';

  @override
  String get routeMarkerDeleteConfirmMessage =>
      'Cela supprime définitivement le repère du parcours.';

  @override
  String get routeMarkerKindAidStation => 'Ravitaillement';

  @override
  String get routeMarkerKindCutoff => 'Barrière horaire';

  @override
  String get routeMarkerKindCrewAccess => 'Assistance / parking';

  @override
  String get routeMarkerKindHazard => 'Danger';

  @override
  String get routeMarkerKindNote => 'Note';

  @override
  String get routeMarkerKindClimb => 'Montée';

  @override
  String get routeMarkerKindCustom => 'Personnalisé';

  @override
  String get routeMarkerServiceWater => 'Eau';

  @override
  String get routeMarkerServiceFood => 'Nourriture';

  @override
  String get routeMarkerServiceMedical => 'Médical';

  @override
  String get routeMarkerServiceToilets => 'Toilettes';

  @override
  String get routeMarkerServiceDropBag => 'Sac de ravitaillement';

  @override
  String get clubFormEditTitle => 'Modifier le club';

  @override
  String get clubEditorWebsite => 'Site web';

  @override
  String get clubEditorInstagram => 'Instagram';

  @override
  String get clubEditorStrava => 'Strava';

  @override
  String get clubEditorFacebook => 'Facebook';

  @override
  String get clubEditorSaveChanges => 'Enregistrer les modifications';

  @override
  String get clubDetailVisitWebsite => 'Visiter notre site';

  @override
  String get clubDetailEditClub => 'Modifier le club';

  @override
  String get roadbookTitle => 'Roadbook';

  @override
  String get roadbookCrewSheet => 'Roadbook (feuille d\'assistance)';

  @override
  String get roadbookGoalTime => 'Temps visé';

  @override
  String get roadbookStartTime => 'Heure de départ';

  @override
  String get roadbookEffort => 'Effort';

  @override
  String get roadbookEven => 'Régulier';

  @override
  String get roadbookStart => 'Départ';

  @override
  String get roadbookFinish => 'Arrivée';

  @override
  String get roadbookShare => 'Partager';

  @override
  String get roadbookNoMarkers =>
      'Ajoutez des repères de parcours pour créer un roadbook.';

  @override
  String get roadbookAddElevation => 'Ajouter le dénivelé';

  @override
  String get roadbookElevationUnavailable =>
      'Données d\'altitude indisponibles pour ce parcours';

  @override
  String roadbookSummary(String distance, String vert, String time) {
    return '$distance · $vert D+ · objectif $time';
  }

  @override
  String get roadbookFuel => 'Ravitaillement';

  @override
  String get roadbookHeat => 'Chaleur';

  @override
  String get roadbookCarbs => 'Glucides';

  @override
  String get roadbookFluid => 'Liquide';

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
    return 'emporter $gels gels · $fluid ml';
  }

  @override
  String get checkpointCheckinAction => 'Pointage au checkpoint';

  @override
  String get checkpointCheckinTitle => 'Pointage au ravitaillement';

  @override
  String get checkpointSyncNow => 'Synchroniser maintenant';

  @override
  String get checkpointPending => 'Non synchronisé';

  @override
  String get checkpointLoadFailed => 'Impossible de charger les checkpoints';

  @override
  String get checkpointRetry => 'Réessayer';

  @override
  String get checkpointNone =>
      'Cette course n\'a pas encore de checkpoints. Ajoutez-les sur le web avant que les bénévoles ne pointent les coureurs.';

  @override
  String get checkpointPickLabel => 'CHECKPOINT';

  @override
  String get checkpointBibLabel => 'Numéro de dossard';

  @override
  String get checkpointBibHint => 'Scannez ou saisissez un dossard';

  @override
  String get checkpointBibRequired => 'Saisissez d\'abord un numéro de dossard';

  @override
  String get checkpointStampIn => 'Pointer ENTRÉE';

  @override
  String get checkpointStampOut => 'Pointer SORTIE';

  @override
  String checkpointStampedIn(String bib) {
    return 'Dossard $bib pointé à l\'entrée';
  }

  @override
  String checkpointStampedOut(String bib) {
    return 'Dossard $bib pointé à la sortie';
  }

  @override
  String get checkpointStampFailed => 'Impossible d\'enregistrer ce pointage';

  @override
  String checkpointLoggedHere(int count) {
    return 'ENREGISTRÉS ICI ($count)';
  }

  @override
  String get checkpointNoneLoggedHere =>
      'Aucun coureur enregistré à ce checkpoint pour l\'instant.';

  @override
  String checkpointBibRow(String bib) {
    return 'Dossard $bib';
  }

  @override
  String checkpointInOut(String inTime, String outTime) {
    return 'Entrée $inTime · Sortie $outTime';
  }

  @override
  String get checkpointWeighInTitle => 'Pesée';

  @override
  String get checkpointWeighInConsentBlurb =>
      'Le poids corporel et les notes de mise sous surveillance médicale sont des données de santé, enregistrées uniquement avec le consentement du coureur et visibles uniquement par les officiels de la course.';

  @override
  String get checkpointWeighInConsent =>
      'Le coureur consent à l\'enregistrement de données de santé';

  @override
  String get checkpointWeighInWeightKg => 'Poids corporel (kg)';

  @override
  String get checkpointMedicalHold => 'Mettre sous surveillance médicale';

  @override
  String get checkpointWeighInSave => 'Enregistrer et pointer';

  @override
  String get checkpointCancel => 'Annuler';

  @override
  String get challengesTitle => 'Défis';

  @override
  String get challengesMyChallenges => 'Mes défis';

  @override
  String get challengesBrowse => 'Explorer';

  @override
  String get challengesEmpty => 'Aucun défi pour l\'instant.';

  @override
  String get challengesBrowseEmpty =>
      'Aucun défi public à rejoindre pour le moment.';

  @override
  String get challengesJoin => 'Rejoindre';

  @override
  String get challengesLeave => 'Quitter';

  @override
  String get challengesDelete => 'Supprimer';

  @override
  String get challengesMetricDistance => 'Distance';

  @override
  String get challengesMetricDuration => 'Temps';

  @override
  String get challengesMetricVert => 'Dénivelé';

  @override
  String get challengesMetricActivityCount => 'Activités';

  @override
  String get challengesMetricStreak => 'Jours actifs';

  @override
  String challengesGoalProgress(String value, String goal) {
    return '$value sur $goal';
  }

  @override
  String get challengesProgressComplete => 'Terminé';

  @override
  String challengesEndsIn(int n) {
    return 'Se termine dans $n jours';
  }

  @override
  String get challengesEndsToday => 'Se termine aujourd\'hui';

  @override
  String get challengesEnded => 'Terminé';

  @override
  String get challengesLeaderboard => 'Classement';

  @override
  String get challengesLeaderboardEmpty => 'Aucune progression enregistrée.';

  @override
  String challengesLeaderboardRank(int rank) {
    return '#$rank';
  }

  @override
  String challengesParticipants(int n) {
    return '$n participants';
  }

  @override
  String get challengesBadgeEarned => 'Badge obtenu';

  @override
  String challengesUnitDays(int n) {
    return '$n jours';
  }

  @override
  String challengesUnitActivities(int n) {
    return '$n';
  }

  @override
  String get challengesLeaveConfirmTitle => 'Quitter le défi ?';

  @override
  String get challengesLeaveConfirm =>
      'Votre progression dans ce défi ne sera plus suivie.';

  @override
  String get challengesDeleteConfirmTitle => 'Supprimer le défi ?';

  @override
  String get challengesDeleteConfirm =>
      'Cela supprime le défi et son classement pour tout le monde. Action irréversible.';

  @override
  String get challengesNotFound => 'Ce défi n\'est pas disponible.';

  @override
  String get challengesJoinFailed => 'Impossible de rejoindre le défi.';

  @override
  String get challengesLeaveFailed => 'Impossible de quitter le défi.';

  @override
  String get challengesLoadFailed => 'Impossible de charger les défis.';

  @override
  String fundraiserRaisedOfGoal(String raised, String goal) {
    return '$raised sur $goal collectés';
  }

  @override
  String fundraiserDonorCount(int count) {
    return '$count soutiens';
  }

  @override
  String get fundraiserOverGoal => 'Objectif dépassé !';

  @override
  String get fundraiserClosed => 'Cette collecte est clôturée.';

  @override
  String get fundraiserFeedTitle => 'Soutiens récents';

  @override
  String get fundraiserFeedEmpty => 'Soyez le premier à faire un don.';

  @override
  String get fundraiserAnonymous => 'Anonyme';

  @override
  String get fundraiserDonateOnWeb => 'Faire un don sur le web';

  @override
  String get racesTitle => 'Calendrier des courses';

  @override
  String get racesSearchPlaceholder => 'Rechercher des courses par nom…';

  @override
  String get racesNearPlace => 'Près d\'un lieu…';

  @override
  String racesKmAway(String distance) {
    return 'à $distance';
  }

  @override
  String get racesDistanceAny => 'Toute distance';

  @override
  String get racesDistance5k => '5 km';

  @override
  String get racesDistance10k => '10 km';

  @override
  String get racesDistanceHalf => 'Semi';

  @override
  String get racesDistanceMarathon => 'Marathon';

  @override
  String get racesDistanceUltra => 'Ultra';

  @override
  String get racesRegister => 'S\'inscrire';

  @override
  String get racesViewResults => 'Voir les résultats';

  @override
  String get racesImportResult => 'Importer mon résultat';

  @override
  String get racesSubmitRace => 'Ajouter une course';

  @override
  String get racesUnverified => 'Non vérifié';

  @override
  String get racesEmpty => 'Aucune course ne correspond encore à ces filtres.';

  @override
  String get racesSearchFailed =>
      'Impossible de charger les courses. Vérifiez votre connexion et réessayez.';

  @override
  String racesMatchPrompt(String name) {
    return 'Était-ce le $name ? Importez votre résultat officiel.';
  }

  @override
  String get racesMatchConfirm => 'Importer le résultat';

  @override
  String get racesMatchDismiss => 'Pas cette course';

  @override
  String get racesImported => 'Résultat officiel importé.';

  @override
  String get racesOfficialResult => 'Résultat officiel';

  @override
  String get racesChipTime => 'Temps puce';

  @override
  String get racesGunTime => 'Temps officiel';

  @override
  String get racesOverallPlace => 'Classement général';

  @override
  String get racesAgeGroupPlace => 'Classement par catégorie';

  @override
  String get racesAgeGroup => 'Catégorie d\'âge';

  @override
  String get racesBib => 'Dossard';

  @override
  String get racesPasteResultHint =>
      'Saisissez les détails de votre arrivée depuis la page de résultats de la course.';

  @override
  String get racesSave => 'Enregistrer';

  @override
  String get racesCancel => 'Annuler';

  @override
  String get racesEditorTitle => 'Ajouter une course';

  @override
  String get racesFieldName => 'Nom de la course';

  @override
  String get racesFieldDate => 'Date';

  @override
  String get racesFieldDistance => 'Distance (mètres)';

  @override
  String get racesFieldLocation => 'Lieu';

  @override
  String get racesFieldEntryUrl => 'Lien d\'inscription';

  @override
  String get racesFieldResultsUrl => 'Lien des résultats';

  @override
  String get racesSubmitFailed =>
      'Impossible d\'enregistrer la course. Veuillez réessayer.';

  @override
  String get racesImportFailed =>
      'Impossible d\'importer le résultat. Veuillez réessayer.';

  @override
  String get navRaces => 'Courses';

  @override
  String get integrationsRunsignup => 'RunSignUp';

  @override
  String get integrationsRunsignupConnect =>
      'Importez les résultats de course depuis RunSignUp.';

  @override
  String get integrationsRunsignupOpen => 'Ouvrir le calendrier des courses';

  @override
  String get integrationsRunsignupUnavailable =>
      'L\'import RunSignUp n\'est pas encore disponible. parkrun et le collage manuel fonctionnent toujours.';

  @override
  String get integrationsChronotrack => 'ChronoTrack';

  @override
  String get integrationsChronotrackConnect =>
      'Importez les résultats des épreuves chronométrées par ChronoTrack.';

  @override
  String get integrationsChronotrackOpen => 'Ouvrir le calendrier des courses';

  @override
  String get integrationsChronotrackUnavailable =>
      'L\'import ChronoTrack n\'est pas encore disponible. parkrun et le collage manuel fonctionnent toujours.';

  @override
  String get routeConditionsTitle => 'Conditions';

  @override
  String get routeConditionsReport => 'Signaler une condition';

  @override
  String get routeConditionsReporting => 'Envoi…';

  @override
  String get routeConditionsReported => 'Condition signalée';

  @override
  String get routeConditionsReportFailed =>
      'Impossible de signaler la condition';

  @override
  String get routeConditionsEmpty => 'Aucun signalement pour l\'instant.';

  @override
  String get routeConditionsLoading => 'Chargement…';

  @override
  String get routeConditionsCancel => 'Annuler';

  @override
  String get routeConditionsDelete => 'Supprimer';

  @override
  String get routeConditionsDeleteTitle => 'Supprimer le signalement ?';

  @override
  String get routeConditionsDeleteConfirm =>
      'Cela supprime définitivement le signalement.';

  @override
  String get routeConditionsDeleteFailed =>
      'Impossible de supprimer le signalement';

  @override
  String get routeConditionsKindLabel => 'Condition';

  @override
  String get routeConditionsSeverityLabel => 'Gravité';

  @override
  String get routeConditionsNoteLabel => 'Note';

  @override
  String get routeConditionsNotePlaceholder =>
      'Que rencontrera le prochain coureur ?';

  @override
  String routeConditionsAtDistance(String distance) {
    return 'à $distance';
  }

  @override
  String get routeConditionMuddy => 'Boueux';

  @override
  String get routeConditionFlooded => 'Inondé';

  @override
  String get routeConditionSnowIce => 'Neige / glace';

  @override
  String get routeConditionOvergrown => 'Envahi par la végétation';

  @override
  String get routeConditionClosed => 'Fermé';

  @override
  String get routeConditionHazard => 'Danger';

  @override
  String get routeConditionClear => 'Dégagé';

  @override
  String get routeConditionOther => 'Autre';

  @override
  String get routeConditionSeverityInfo => 'Info';

  @override
  String get routeConditionSeverityCaution => 'Attention';

  @override
  String get routeConditionSeverityImpassable => 'Impraticable';

  @override
  String get prefTurnByTurnCues => 'Guidage vocal virage par virage';

  @override
  String get prefTurnByTurnCuesSubtitle =>
      'Directions vocales en suivant un itinéraire enregistré';

  @override
  String ttsTurnLeftIn(String distance) {
    return 'Dans $distance, tournez à gauche';
  }

  @override
  String ttsTurnRightIn(String distance) {
    return 'Dans $distance, tournez à droite';
  }

  @override
  String get ttsTurnLeftNow => 'Tournez à gauche';

  @override
  String get ttsTurnRightNow => 'Tournez à droite';

  @override
  String get ttsSlightLeft => 'Serrez à gauche';

  @override
  String get ttsSlightRight => 'Serrez à droite';

  @override
  String get ttsUturn => 'Faites demi-tour';

  @override
  String routeOfflinePackDownloading(int done, int total) {
    return 'Mise en cache de la carte : $done / $total';
  }

  @override
  String get routeOfflinePackReady => 'Carte enregistrée hors ligne';

  @override
  String routeOfflinePackPartial(int done, int total) {
    return 'Carte partiellement enregistrée ($done / $total) — réessayer';
  }

  @override
  String get routeOfflinePackTooLarge =>
      'Cet itinéraire est trop grand pour la mise en cache hors ligne';

  @override
  String get badgesSectionTitle => 'Distinctions';

  @override
  String get badgesSectionSubtitle => 'Les jalons que vous avez atteints';

  @override
  String get badgesEmpty => 'Pas encore de badges — continuez à courir.';

  @override
  String get badgesEmptyOther => 'Aucun badge public pour l\'instant.';

  @override
  String badgesEarnedOn(String date) {
    return 'Obtenu le $date';
  }

  @override
  String badgesFeedEarned(String name, String badge) {
    return '$name a obtenu le badge $badge';
  }

  @override
  String get badgesARunner => 'Un coureur';

  @override
  String get badgesTierBronze => 'Bronze';

  @override
  String get badgesTierSilver => 'Argent';

  @override
  String get badgesTierGold => 'Or';

  @override
  String get badgesTierPlatinum => 'Platine';

  @override
  String get badgesDistanceSingle5kLabel => 'Premier 5 km';

  @override
  String get badgesDistanceSingle5kDesc => '5 km parcourus en une seule sortie';

  @override
  String get badgesDistanceSingleHalfLabel => 'Semi-marathon';

  @override
  String get badgesDistanceSingleHalfDesc =>
      '21,1 km parcourus en une seule sortie';

  @override
  String get badgesDistanceSingleMarathonLabel => 'Marathon';

  @override
  String get badgesDistanceSingleMarathonDesc =>
      '42,2 km parcourus en une seule sortie';

  @override
  String get badgesDistanceSingleUltraLabel => 'Ultra';

  @override
  String get badgesDistanceSingleUltraDesc =>
      '50 km ou plus parcourus en une seule sortie';

  @override
  String get badgesDistanceLifetime100Label => 'Club des 100 km';

  @override
  String get badgesDistanceLifetime100Desc => '100 km enregistrés au total';

  @override
  String get badgesDistanceLifetime500Label => '500 km';

  @override
  String get badgesDistanceLifetime500Desc => '500 km enregistrés au total';

  @override
  String get badgesDistanceLifetime1000Label => 'Club des 1 000 km';

  @override
  String get badgesDistanceLifetime1000Desc => '1 000 km enregistrés au total';

  @override
  String get badgesDistanceLifetime5000Label => '5 000 km';

  @override
  String get badgesDistanceLifetime5000Desc => '5 000 km enregistrés au total';

  @override
  String get badgesStreak7Label => 'Série hebdomadaire';

  @override
  String get badgesStreak7Desc => 'Couru 7 jours d\'affilée';

  @override
  String get badgesStreak30Label => 'Série mensuelle';

  @override
  String get badgesStreak30Desc => 'Couru 30 jours d\'affilée';

  @override
  String get badgesStreak100Label => 'Série de cent';

  @override
  String get badgesStreak100Desc => 'Couru 100 jours d\'affilée';

  @override
  String get badgesStreak365Label => 'Série annuelle';

  @override
  String get badgesStreak365Desc => 'Couru 365 jours d\'affilée';

  @override
  String get badgesPr1Label => 'Premier record';

  @override
  String get badgesPr1Desc => 'Vous avez établi votre premier record personnel';

  @override
  String get badgesPr3Label => 'Triple record';

  @override
  String get badgesPr3Desc => 'Records personnels détenus sur 3 distances';

  @override
  String get badgesPr5Label => 'Collectionneur de records';

  @override
  String get badgesPr5Desc =>
      'Records personnels détenus sur toutes les distances';

  @override
  String get badgesPlan1Label => 'Plan terminé';

  @override
  String get badgesPlan1Desc => 'Vous avez terminé un plan d\'entraînement';

  @override
  String get badgesPlan3Label => 'Triple finisher';

  @override
  String get badgesPlan3Desc => 'Vous avez terminé 3 plans d\'entraînement';

  @override
  String get badgesPlan10Label => 'Vétéran des plans';

  @override
  String get badgesPlan10Desc => 'Vous avez terminé 10 plans d\'entraînement';

  @override
  String get racePredictorTitle => 'Prédicteur de temps de course';

  @override
  String racePredictorAnchoredOn(String distance, String time) {
    return 'D\'après votre effort sur $distance en $time';
  }

  @override
  String get racePredictorColDistance => 'Distance';

  @override
  String get racePredictorColTime => 'Temps';

  @override
  String get racePredictorColPace => 'Allure';

  @override
  String get racePredictorColConfidence => 'Fiabilité';

  @override
  String get racePredictorConfidenceHigh => 'Élevée';

  @override
  String get racePredictorConfidenceModerate => 'Moyenne';

  @override
  String get racePredictorConfidenceLow => 'Faible';

  @override
  String get racePredictorConfReasonSimilar =>
      'Basé sur des efforts récents proches de cette distance.';

  @override
  String get racePredictorConfReasonExtrapolated =>
      'Extrapolé sur un grand écart de distance — à prendre comme une estimation.';

  @override
  String get racePredictorConfReasonStale =>
      'Ancré sur un effort vieux de quelques semaines.';

  @override
  String get racePredictorConfReasonLimited =>
      'Basé sur des données récentes limitées.';

  @override
  String get racePredictorFootnote =>
      'Équivalence de Riegel à partir de votre meilleur effort récent, pondérée par la récence. Les distances proches sont plus fiables.';
}
