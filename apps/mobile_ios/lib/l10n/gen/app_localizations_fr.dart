// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

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
  String recapMonthShareHeadline(Object period) {
    return 'Mon $period en course :';
  }

  @override
  String recapMonthShareSubject(Object period) {
    return 'Bilan $period';
  }

  @override
  String get recapTitle => 'Année en course';

  @override
  String get recapMonthTitle => 'Mois en course';

  @override
  String get recapPeriodYear => 'Année';

  @override
  String get recapPeriodMonth => 'Mois';

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
  String get recapPrevMonth => 'Mois précédent';

  @override
  String get recapNextMonth => 'Mois suivant';

  @override
  String recapNoRunsForPeriod(Object period) {
    return 'Aucune course à récapituler pour $period.';
  }

  @override
  String recapNoRunsYetInPeriod(Object period) {
    return 'Aucune course en $period pour l\'instant. Enregistrez-en une pour voir votre bilan.';
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
  String importFailuresHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activités n\'ont pas été importées',
      one: '1 activité n\'a pas été importée',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresIntro =>
      'Relancez l\'import pour réessayer : ce qui est déjà importé est ignoré, rien n\'est dupliqué.';

  @override
  String importFailuresTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count échecs supplémentaires n\'ont pas été enregistrés.',
      one: '1 échec supplémentaire n\'a pas été enregistré.',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresShowDetail => 'Afficher chaque activité';

  @override
  String get importFailuresShare => 'Partager le rapport (CSV)';

  @override
  String get importFailuresShareFailed => 'Impossible de partager le rapport.';

  @override
  String get importFailuresDismiss => 'Masquer';

  @override
  String get importFailuresNoDate => 'Date inconnue';

  @override
  String get importFailuresReasonNetwork => 'Connexion interrompue';

  @override
  String get importFailuresReasonAuth => 'Déconnecté';

  @override
  String get importFailuresReasonRateLimited => 'Trop de requêtes';

  @override
  String get importFailuresReasonTooLarge => 'Fichier trop volumineux';

  @override
  String get importFailuresReasonUnparseable => 'Fichier illisible';

  @override
  String get importFailuresReasonRejected => 'Refusé par le serveur';

  @override
  String get importFailuresReasonUnknown => 'Erreur inconnue';

  @override
  String importStatusCloudPushDeferred(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count courses sont enregistrées sur cet appareil : leur envoi vers le cloud n\'a pas abouti. Il sera retenté à la prochaine synchronisation.',
      one:
          '1 course est enregistrée sur cet appareil : son envoi vers le cloud n\'a pas abouti. Il sera retenté à la prochaine synchronisation.',
    );
    return '$_temp0';
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
  String importHealthRoutesWithheld(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count activités importées ont des cartes GPS que Threkir n\'est pas autorisé à lire.',
      one:
          '1 activité importée a une carte GPS que Threkir n\'est pas autorisé à lire.',
    );
    return '$_temp0 Health Connect protège l\'itinéraire d\'une séance par une autorisation distincte.';
  }

  @override
  String get importHealthRoutesAllowButton => 'Autoriser l\'import des cartes';

  @override
  String get importHealthRoutesRequesting =>
      'Demande d\'accès aux cartes à Health Connect…';

  @override
  String get importHealthRoutesDenied =>
      'Accès aux cartes non accordé. Les imports resteront sans carte — vous pouvez le changer dans Health Connect à tout moment.';

  @override
  String get importHealthRoutesAdding =>
      'Ajout des cartes aux activités importées…';

  @override
  String importHealthRoutesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cartes ajoutées à $count activités.',
      one: 'Carte ajoutée à 1 activité.',
      zero: 'Aucune carte n\'a pu être ajoutée.',
    );
    return '$_temp0';
  }

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
  String get commonCancel => 'Annuler';

  @override
  String get placeSearchNoResults => 'Aucun lieu trouvé';

  @override
  String get placeSearchUnavailable =>
      'La recherche de lieux est indisponible pour le moment';

  @override
  String get placeSearchRetry => 'Réessayer';

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
  String get peopleNearbyHeader => 'Coureurs à proximité';

  @override
  String get peopleNearbySubtitle =>
      'Coureurs inscrits près de la zone que vous avez définie. Distance approximative uniquement, jamais une position en direct.';

  @override
  String get peopleNearbyEmptyTitle => 'Personne à proximité pour l’instant';

  @override
  String get peopleNearbyEmptyBody =>
      'Activez « Me montrer aux coureurs à proximité » et définissez votre zone. Seuls les coureurs ayant fait de même peuvent vous trouver.';

  @override
  String get peopleNearbyEmptyAction => 'Ouvrir les Préférences';

  @override
  String get peopleNearbyLoadFailed =>
      'Impossible de charger les coureurs à proximité.';

  @override
  String peopleNearbyWithin(String distance) {
    return 'À moins de $distance';
  }

  @override
  String peopleNearbyBeyond(String distance) {
    return 'À plus de $distance';
  }

  @override
  String get prefsDiscoverableNearby => 'Me montrer aux coureurs à proximité';

  @override
  String get prefsDiscoverableNearbySubtitle =>
      'Désactivé par défaut. Une fois activé, les autres coureurs qui se sont aussi inscrits voient que vous êtes approximativement à proximité : une distance approximative par rapport à la zone que vous avez définie, jamais votre position.';

  @override
  String get nearbyAreaTitle => 'Votre zone';

  @override
  String get nearbyAreaExplainer =>
      'Choisissez la ville ou le quartier où vous courez. Elle est enregistrée arrondie à environ un kilomètre et n’est jamais votre position en direct. Les autres coureurs ne voient qu’une distance approximative, jamais la zone elle-même.';

  @override
  String get nearbyAreaNone => 'Aucune zone définie';

  @override
  String nearbyAreaCurrent(String label) {
    return 'Zone actuelle : $label';
  }

  @override
  String get nearbyAreaSearchHint => 'Rechercher une ville ou un quartier';

  @override
  String get nearbyAreaSearchUnavailable =>
      'La recherche de lieux est indisponible pour le moment.';

  @override
  String get nearbyAreaNoResults =>
      'Aucun lieu ne correspond à cette recherche.';

  @override
  String get nearbyAreaSaved => 'Zone enregistrée';

  @override
  String get nearbyAreaSaveFailed => 'Impossible d’enregistrer votre zone.';

  @override
  String get nearbyAreaLoadFailed => 'Impossible de charger votre zone.';

  @override
  String get nearbyAreaForget => 'Oublier ma zone';

  @override
  String get nearbyAreaForgetConfirmTitle => 'Oublier votre zone ?';

  @override
  String get nearbyAreaForgetConfirmBody =>
      'Vous n’apparaîtrez plus aux coureurs à proximité jusqu’à ce que vous définissiez à nouveau une zone.';

  @override
  String get nearbyAreaForgotten => 'Zone oubliée';

  @override
  String get nearbyAreaForgetFailed => 'Impossible d’oublier votre zone.';

  @override
  String get peopleFallbackDisplayName => 'Coureur';

  @override
  String get peopleFollowingButton => 'Abonné';

  @override
  String get peopleFollowButton => 'Suivre';

  @override
  String get peopleSignedOutMessage =>
      'Connectez-vous pour rechercher et suivre d\'autres coureurs.';

  @override
  String get peopleSuggestionsLoadFailed =>
      'Impossible de charger les suggestions.';

  @override
  String get readinessCardHeader => 'Forme du jour';

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
  String get runSurfaceLabel => 'Sections de la zone de course';

  @override
  String get runSurfaceTabPlans => 'Plans';

  @override
  String get runSurfaceTabRaces => 'Courses';

  @override
  String get gymSurfaceLabel => 'Sections muscu';

  @override
  String get gymTabLog => 'Journal';

  @override
  String get gymTabRecords => 'Records';

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
  String bodyMetricsPrefSaveFailed(String error) {
    return 'Impossible d\'enregistrer : $error';
  }

  @override
  String get bodyMetricsLoadError =>
      'Impossible de charger les données corporelles.';

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
  String get safetyAddHint => 'partenaire@example.com';

  @override
  String get safetyPhoneLabel => 'Téléphone pour SMS (facultatif)';

  @override
  String get safetyPhoneHint =>
      'Ajoutez un numéro de mobile et ce contact pourra aussi être alerté par SMS — il choisit lors de la confirmation. Les alertes par e-mail sont toujours envoyées.';

  @override
  String get safetyInvalidPhone =>
      'Saisissez le numéro au format international, par ex. +447700900123.';

  @override
  String get safetySmsBadge => 'SMS activé';

  @override
  String get safetySmsPending => 'SMS désactivé — pas encore accepté';

  @override
  String get safetyConfirmSmsLabel => 'M\'alerter aussi par SMS';

  @override
  String get safetyContactOfTitle => 'Vous êtes contact de sécurité';

  @override
  String get safetyContactOfIntro =>
      'Ces personnes vous ont désigné comme contact d\'urgence et vous avez confirmé. Vous pouvez changer la façon dont vous êtes alerté, ou vous retirer, à tout moment.';

  @override
  String safetyContactOfFor(String name) {
    return 'Contact d\'urgence de $name';
  }

  @override
  String get safetyContactOfSmsLabel =>
      'M\'alerter par SMS en plus de l\'e-mail';

  @override
  String get safetyContactOfNoPhone =>
      'Les alertes par SMS nécessitent un numéro de mobile pour vous, et aucun n\'est enregistré. Les e-mails sont toujours envoyés.';

  @override
  String get safetyContactOfSmsOnToast => 'Alertes SMS activées.';

  @override
  String get safetyContactOfSmsOffToast => 'Alertes SMS désactivées.';

  @override
  String get safetyContactOfSmsNoChange =>
      'Cette relation n\'est plus active — la personne l\'a probablement supprimée.';

  @override
  String safetyContactOfSmsFailed(String error) {
    return 'Impossible de modifier votre choix SMS : $error';
  }

  @override
  String get safetyContactOfWithdraw => 'Me retirer';

  @override
  String get safetyContactOfWithdrawConfirm =>
      'Ne plus être le contact de sécurité de cette personne ? Elle ne pourra plus vous alerter et devrait vous envoyer une nouvelle demande.';

  @override
  String get safetyContactOfWithdrawnToast =>
      'Vous n\'êtes plus contact de sécurité.';

  @override
  String safetyContactOfWithdrawFailed(String error) {
    return 'Impossible de se retirer : $error';
  }

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
  String safetyRemoveFailed(String error) {
    return 'Impossible de supprimer le contact : $error';
  }

  @override
  String safetySettingSaveFailed(String error) {
    return 'Impossible d\'enregistrer le réglage : $error';
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
  String get safetyOverdueTitle => 'Alerte de retard';

  @override
  String get safetyOverdueIntro =>
      'Si une course partagée en direct reste silencieuse plus longtemps que cette durée, vos contacts confirmés reçoivent un e-mail avec votre lien en direct.';

  @override
  String get safetyOverdueLabel => 'Alerter après un silence de';

  @override
  String get safetyOverdueOff => 'Désactivé';

  @override
  String safetyOverdueMinutesOption(int minutes) {
    return '$minutes min';
  }

  @override
  String get safetyOverdueNote =>
      'S\'applique à toute course avec partage en direct actif. Le silence peut aussi être une perte de signal — l\'e-mail le précise. Les contacts sont alertés une fois par course ; terminer la course envoie le message rassurant habituel.';

  @override
  String get safetyOverdueSaved => 'Alerte de retard mise à jour';

  @override
  String get safetyAutoLiveShareTitle => 'Partage en direct automatique';

  @override
  String get safetyAutoLiveShareSubtitle =>
      'Démarre automatiquement un partage en direct au début d\'une course sur ce téléphone. La course en cours est visible par toute personne ayant le lien ; à la fin de la course, elle retrouve votre visibilité par défaut.';

  @override
  String get safetyOffRouteTitle => 'Alerte hors itinéraire';

  @override
  String get safetyOffRouteSubtitle =>
      'Prévenez un contact confirmé si vous quittez durablement votre itinéraire prévu lors d\'une course partagée en direct.';

  @override
  String get runOffRouteAlertSent =>
      'Nous avons prévenu votre contact de sécurité : vous êtes hors itinéraire depuis un moment.';

  @override
  String get runAutoLiveShareStarted =>
      'Partage en direct actif — envoyez le lien via « Partager le lien en direct »';

  @override
  String get runSafetyNudgeSolo =>
      'Vous courez seul(e) après la tombée de la nuit ? Partagez un lien en direct pour que quelqu\'un puisse vous suivre.';

  @override
  String get runSafetyNudgeShareAction => 'Partager';

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
  String get authShowPassword => 'Afficher le mot de passe';

  @override
  String get authHidePassword => 'Masquer le mot de passe';

  @override
  String get authOrDivider => 'OU';

  @override
  String get authErrorOffline =>
      'Vous semblez être hors ligne. Vérifiez votre connexion et réessayez.';

  @override
  String get authErrorInvalidCredentials =>
      'E-mail ou mot de passe incorrect. Veuillez réessayer.';

  @override
  String get authErrorRateLimited =>
      'Trop de tentatives. Veuillez patienter un instant et réessayer.';

  @override
  String get authErrorGeneric =>
      'Une erreur s\'est produite. Veuillez réessayer.';

  @override
  String get authErrorNotSignedIn =>
      'Vous devez être connecté pour faire cela. Connectez-vous et réessayez.';

  @override
  String get authErrorEmailExists =>
      'Un compte existe déjà avec cet e-mail. Connectez-vous plutôt.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Confirmez d’abord votre e-mail — recherchez le lien de confirmation dans votre boîte de réception.';

  @override
  String authErrorWeakPassword(int minLength) {
    return 'Ce mot de passe est trop faible. Utilisez au moins $minLength caractères.';
  }

  @override
  String get authErrorInvalidEmail => 'Saisissez une adresse e-mail valide.';

  @override
  String authErrorPasswordTooShort(int minLength) {
    return 'Le mot de passe doit comporter au moins $minLength caractères.';
  }

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
  String get signInResendConfirmation => 'Renvoyer l’e-mail de confirmation';

  @override
  String get signInConfirmationResent =>
      'Si cette adresse est enregistrée, nous avons envoyé un nouveau lien de confirmation.';

  @override
  String get signInWithApple => 'Se connecter avec Apple';

  @override
  String get signInWithGoogle => 'Se connecter avec Google';

  @override
  String get googleSignInSoon =>
      'La connexion avec Google arrive bientôt. Pour l’instant, utilisez l’e-mail.';

  @override
  String get appleSignInSoon =>
      'La connexion avec Apple arrive bientôt. Pour l’instant, utilisez l’e-mail.';

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
  String get signUpAcceptConjunction => ' et la ';

  @override
  String get signUpErrorConfirmAge =>
      'Veuillez confirmer que vous avez 16 ans ou plus pour continuer.';

  @override
  String get signUpErrorAcceptTerms =>
      'Veuillez accepter les Conditions d\'utilisation et la Politique de confidentialité pour continuer.';

  @override
  String get signUpConfirmPasswordLabel => 'Confirmer le mot de passe';

  @override
  String signUpErrorPasswordTooShort(int min) {
    return 'Le mot de passe doit contenir au moins $min caractères.';
  }

  @override
  String get signUpErrorPasswordMismatch =>
      'Les mots de passe ne correspondent pas.';

  @override
  String get signUpCheckEmailTitle => 'Vérifiez votre boîte mail';

  @override
  String signUpCheckEmailBody(String email) {
    return 'Nous avons envoyé un lien de confirmation à $email. Ouvrez-le pour finaliser la création de votre compte.';
  }

  @override
  String get signUpCheckEmailBack => 'Retour à la connexion';

  @override
  String get signUpContinueWithApple => 'Continuer avec Apple';

  @override
  String get signUpContinueWithGoogle => 'Continuer avec Google';

  @override
  String get signUpSignInPrompt => 'Vous avez déjà un compte ? Connectez-vous';

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
  String get setupCreatePlanCta => 'Créer mon plan d\'entraînement';

  @override
  String get setupWelcomeToast => 'Bienvenue sur Threkir !';

  @override
  String setupSaveError(String message) {
    return 'Impossible d\'enregistrer votre configuration : $message';
  }

  @override
  String setupPrefsSaveError(String message) {
    return 'Votre compte est configuré, mais vos préférences n\'ont pas été enregistrées : $message';
  }

  @override
  String get setupOfflineHint =>
      'Impossible de joindre le serveur pour le moment. Vous pouvez terminer la configuration plus tard — tout est modifiable dans les Réglages.';

  @override
  String get setupFinishLater => 'Terminer plus tard';

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
  String get setupDoneHintGoal =>
      'C\'est tout. Créez un plan d\'entraînement pour votre objectif, ou ouvrez le tableau de bord pour commencer à courir.';

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
  String get runLastRunOpenA11yLabel =>
      'Ouvrir les détails de la dernière course';

  @override
  String get runChooseRoute => 'Choisir un parcours';

  @override
  String get runChangeRoute => 'Changer de parcours';

  @override
  String get runShareLiveLink => 'Partager le lien en direct';

  @override
  String get runLiveShareNeedsSignIn =>
      'Connectez-vous pour partager un lien de suivi en direct.';

  @override
  String get runLiveShareNotStarted =>
      'Le suivi en direct n\'a pas pu démarrer — appuyez sur Partager pour réessayer.';

  @override
  String get runLiveShareActive => 'En direct';

  @override
  String get runLiveShareActiveSemantics =>
      'Le partage en direct est actif. Appuyez pour repartager le lien ou arrêter le partage.';

  @override
  String get runLiveShareSheetTitle => 'Partage en direct actif';

  @override
  String get runLiveShareReshare => 'Repartager le lien';

  @override
  String get runLiveShareStop => 'Arrêter le partage';

  @override
  String get runLiveShareExpectedReturn => 'Pas rentré à…';

  @override
  String get runExpectedReturnTitle => 'Pas rentré à…';

  @override
  String get runExpectedReturnIntro =>
      'Choisissez l’heure à laquelle vous pensez avoir fini. Si cette activité est toujours en cours, vos contacts de sécurité confirmés recevront une alerte avec votre lien en direct.';

  @override
  String get runExpectedReturnServerNote =>
      'L’échéance est conservée sur le serveur : elle vaut même si ce téléphone lâche. Elle disparaît à l’enregistrement de l’activité — une activité terminée sans réseau peut encore alerter jusqu’à la synchronisation.';

  @override
  String runExpectedReturnOptionMinutes(int minutes) {
    return 'Dans $minutes min';
  }

  @override
  String runExpectedReturnOptionHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Dans $hours heures',
      one: 'Dans 1 heure',
    );
    return '$_temp0';
  }

  @override
  String runExpectedReturnBy(String time) {
    return 'De retour à $time';
  }

  @override
  String runExpectedReturnActive(String time) {
    return 'Alerte réglée sur $time.';
  }

  @override
  String get runExpectedReturnClear => 'Supprimer l’alerte';

  @override
  String get runExpectedReturnSetToast => 'Alerte d’heure de retour réglée.';

  @override
  String get runExpectedReturnClearedToast =>
      'Alerte d’heure de retour supprimée.';

  @override
  String get runExpectedReturnFailed =>
      'Impossible de mettre à jour l’alerte d’heure de retour.';

  @override
  String get runExpectedReturnUnavailable =>
      'Serveur injoignable — impossible de régler l’alerte d’heure de retour.';

  @override
  String get runLiveShareStopped => 'Partage en direct arrêté';

  @override
  String get runLiveShareEndedTitle => 'Partage en direct terminé';

  @override
  String get runLiveShareEndedBody =>
      'Le lien en direct n\'est plus mis à jour. Garder la course enregistrée publique pour que toute personne ayant le lien puisse la voir ? Sinon, elle suit votre visibilité par défaut.';

  @override
  String get runLiveShareKeepPublic => 'Garder publique';

  @override
  String get runLiveShareKeepPrivate => 'Garder privée';

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
  String get runStopA11yLabel => 'Arrêter et enregistrer la course';

  @override
  String get runStopA11yHint =>
      'Termine l\'enregistrement et enregistre la course';

  @override
  String get runHoldToStopHint => 'Maintenir pour arrêter';

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
  String get runResumeDialogTitle => 'Reprendre votre course ?';

  @override
  String get runResumeDialogBody =>
      'Une course d\'une session précédente est toujours en cours. Reprenez l\'enregistrement là où vous vous êtes arrêté, terminez-la maintenant ou supprimez-la.';

  @override
  String get runResumeAction => 'Reprendre';

  @override
  String get runResumeFinishAction => 'Terminer maintenant';

  @override
  String get runResumedBanner => 'Course reprise.';

  @override
  String get runResumeSavedBanner => 'Course précédente enregistrée.';

  @override
  String get runResumeDiscardedBanner => 'Course précédente supprimée.';

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
  String get runTreadmillConnecting => 'Connexion au tapis de course…';

  @override
  String get runTreadmillNoBeltData =>
      'Aucune donnée du tapis — distance via GPS';

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
  String get runBackgroundLocationPaused =>
      'Le suivi a été mis en pause pendant votre absence — le chrono a continué et rien n’a été perdu, mais la distance parcourue hors écran n’a pas été comptée. Réglez la localisation sur « Toujours autoriser » pour suivre en arrière-plan.';

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
  String get historyUnsyncedRowSemantics => 'pas encore synchronisée';

  @override
  String get historyBlockedRowSemantics => 'impossible à téléverser';

  @override
  String get historyBlockedRowTooltip => 'Impossible à téléverser';

  @override
  String historyBlockedTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses ne peuvent pas être téléversées',
      one: '$count course ne peut pas être téléversée',
    );
    return '$_temp0';
  }

  @override
  String historySyncBlocked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count courses ne peuvent pas être téléversées et ne seront pas réessayées. Ouvrez chacune d\'elles pour choisir la suite.',
      one:
          '$count course ne peut pas être téléversée et ne sera pas réessayée. Ouvrez-la pour choisir la suite.',
    );
    return '$_temp0';
  }

  @override
  String get runDetailBlockedDropTrack => 'Téléverser sans la trace';

  @override
  String get runDetailBlockedExport => 'Exporter une copie';

  @override
  String get runDetailBlockedTitle =>
      'Cette course ne peut pas être téléversée';

  @override
  String runDetailBlockedTrackTooLarge(int waypoints) {
    return 'Sa trace GPS ($waypoints points) dépasse ce que le stockage cloud peut contenir : réessayer ne fonctionnera jamais. Tout le reste de la course — distance, temps, allure, dénivelé — peut encore être enregistré.';
  }

  @override
  String get runDetailDropTrackBody =>
      'La trace est supprimée de cet appareil et la course est téléversée sans carte. Sa distance, son temps, son allure et son dénivelé restent inchangés. Exportez-en une copie d\'abord si vous souhaitez la conserver.';

  @override
  String get runDetailDropTrackConfirm => 'Téléverser sans elle';

  @override
  String get runDetailDropTrackDone =>
      'Trace supprimée. La course sera synchronisée au prochain cycle.';

  @override
  String get runDetailDropTrackFailed =>
      'Impossible de supprimer la trace. Veuillez réessayer.';

  @override
  String get runDetailDropTrackTitle => 'Téléverser sans la trace GPS ?';

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
  String get durationFieldHours => 'Heures';

  @override
  String get durationFieldMinutes => 'Minutes';

  @override
  String get durationFieldSeconds => 'Secondes';

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
  String get runDetailIncompleteBadge => 'Incomplète';

  @override
  String get runDetailIncompleteTooltip =>
      'Ta montre a redémarré en pleine course. Ces totaux ne correspondent qu\'à ce qu\'elle avait enregistré jusque-là, pas à toute l\'activité.';

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
  String get runDetailEditFailed =>
      'Impossible d\'enregistrer vos modifications. Veuillez réessayer.';

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
  String get runDetailStatHrCoverage => 'Couverture FC';

  @override
  String runDetailHrCoveragePercent(int pct) {
    return '$pct %';
  }

  @override
  String runDetailHrCoverageOnly(int pct) {
    return '$pct % couvert';
  }

  @override
  String get runDetailStatAvgHr => 'FC moy.';

  @override
  String get runDetailStatAgeGrade => 'Indice d\'âge';

  @override
  String get runDetailStatGradeAdjPace => 'Allure corrigée';

  @override
  String get runDetailSectionElevation => 'Dénivelé';

  @override
  String get runDetailPaceLegendTitle => 'Allure vs médiane';

  @override
  String get runDetailPaceBandFaster => 'Plus rapide';

  @override
  String get runDetailPaceBandSteady => 'Régulier';

  @override
  String get runDetailPaceBandSlower => 'Plus lent';

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
  String get runDetailHrDisclaimer =>
      'Les zones utilisent une FC max estimée selon l\'âge. Si tu prends des médicaments cardiaques (p. ex. bêtabloquants) ou si tu as mesuré ta FC max, définis-la dans Préférences pour des zones précises.';

  @override
  String get runDetailHrDisclaimerAction => 'Définir la FC max';

  @override
  String get runDetailSectionSplits => 'Splits';

  @override
  String get runDetailNoGpsForSplits => 'Aucune donnée GPS pour les splits';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Course trop courte pour un split complet de $unit';
  }

  @override
  String get runDetailPacing => 'Gestion de l’allure';

  @override
  String get runDetailPacingFirstHalf => 'Première moitié';

  @override
  String get runDetailPacingSecondHalf => 'Seconde moitié';

  @override
  String get runDetailPacingNegative => 'Négatif split';

  @override
  String get runDetailPacingEven => 'Allure régulière';

  @override
  String get runDetailPacingPositive => 'Positif split';

  @override
  String runDetailPacingFaster(String delta) {
    return '$delta plus rapide sur la seconde moitié';
  }

  @override
  String runDetailPacingSlower(String delta) {
    return '$delta plus lent sur la seconde moitié';
  }

  @override
  String get runDetailPacingHeld => 'Régulier sur les deux moitiés';

  @override
  String get runDetailPacingGapNegative =>
      'Corrigé du dénivelé, vous avez accéléré sur la seconde moitié.';

  @override
  String get runDetailPacingGapEven =>
      'Corrigé du dénivelé, votre effort a été régulier sur les deux moitiés.';

  @override
  String get runDetailPacingGapPositive =>
      'Corrigé du dénivelé, vous avez ralenti sur la seconde moitié.';

  @override
  String get runDetailGapColumn => 'Corrigée';

  @override
  String get runDetailGapColumnHint =>
      'L’allure corrigée est l’allure sur le plat qui aurait coûté le même effort que les côtes réellement parcourues.';

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
  String get runDetailMakePrivate => 'Rendre privée';

  @override
  String get runDetailMakePrivateTitle => 'Rendre cette course privée ?';

  @override
  String get runDetailMakePrivateBody =>
      'Le lien de partage public et la page des spectateurs en direct cesseront de fonctionner. Toute personne ouvrant un ancien lien ne verra plus cette course.';

  @override
  String runDetailMakePrivateFailed(String error) {
    return 'Impossible de rendre la course privée : $error';
  }

  @override
  String get runDetailMadePrivate => 'La course est désormais privée';

  @override
  String get runDetailDeleteTitle => 'Supprimer la course ?';

  @override
  String get runDetailDeleteBody => 'Cette action est irréversible.';

  @override
  String get runDetailDeleteQueued =>
      'Échec de la suppression dans le cloud ; la course est conservée pour l\'instant — nouvelle tentative une fois en ligne.';

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
  String get publicRunLiveTitle => 'En direct maintenant';

  @override
  String get publicRunLiveSub =>
      'Cette course est toujours en cours. Suivez-la sur le suivi en direct.';

  @override
  String get publicRunWatchLive => 'Suivre en direct';

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
  String routesImportedMany(int count) {
    return '$count itinéraires importés';
  }

  @override
  String routesImportFailed(String error) {
    return 'Échec de l\'import : $error';
  }

  @override
  String get routesImportSharedFailed =>
      'Impossible d\'importer ce fichier : ce n\'est pas un itinéraire valide.';

  @override
  String routesSaved(String name) {
    return '« $name » enregistré';
  }

  @override
  String get historySelectionHint =>
      'Appuyez longuement sur une course pour en sélectionner plusieurs';

  @override
  String get routesSelectionHint =>
      'Appuyez longuement sur un itinéraire pour en sélectionner plusieurs';

  @override
  String get routesEmptyTitle => 'Aucun itinéraire pour l\'instant';

  @override
  String get routesEmptyBody =>
      'Appuyez sur Créer pour tracer un itinéraire sur la carte, ou importez un fichier GPX, KML, KMZ, GeoJSON ou TCX.';

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
  String get routeBuilderSnapUnavailable =>
      'L\'accrochage aux routes est indisponible — les points se placent là où vous touchez, reliés par des lignes droites.';

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
  String get routeBuilderPointList => 'Points du parcours';

  @override
  String routeBuilderPointMovedTo(int from, int to) {
    return 'Point $from déplacé à la position $to';
  }

  @override
  String routeBuilderPointRemoved(int number) {
    return 'Point $number supprimé';
  }

  @override
  String routeBuilderReorderPoint(int number) {
    return 'Réordonner le point $number';
  }

  @override
  String get routeBuilderPointStart => 'Départ';

  @override
  String get routeBuilderPointEnd => 'Arrivée';

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
  String get routeDetailShareLink => 'Partager le lien';

  @override
  String get routeDetailSendToWatch => 'Envoyer à la montre';

  @override
  String routeDetailWatchCourseSent(int points) {
    return 'Parcours envoyé à la montre ($points points)';
  }

  @override
  String routeDetailWatchCourseSimplified(int source, int points) {
    return 'Parcours envoyé à la montre — réduit de $source à $points points pour tenir';
  }

  @override
  String get routeDetailWatchCourseTooShort =>
      'Cet itinéraire a trop peu de points pour être suivi sur la montre';

  @override
  String get routeDetailWatchPushRejected =>
      'La montre a refusé l\'envoi et a conservé ce qu\'elle avait déjà. Réessayez.';

  @override
  String routeDetailWatchCourseFailed(String error) {
    return 'Impossible d\'envoyer le parcours à la montre : $error';
  }

  @override
  String get routeDetailSendToAppleWatch => 'Envoyer à l\'Apple Watch';

  @override
  String routeDetailAppleWatchRouteSent(int points) {
    return 'Itinéraire envoyé à l\'Apple Watch ($points points)';
  }

  @override
  String routeDetailAppleWatchRouteSimplified(int source, int points) {
    return 'Itinéraire envoyé à l\'Apple Watch — réduit de $source à $points points pour tenir';
  }

  @override
  String get routeDetailAppleWatchRouteTooShort =>
      'Cet itinéraire a trop peu de points pour être suivi sur l\'Apple Watch';

  @override
  String routeDetailAppleWatchRouteFailed(String error) {
    return 'Impossible d\'envoyer l\'itinéraire à l\'Apple Watch : $error';
  }

  @override
  String routeDetailWatchCourseAndScheduleSent(int points, int checkpoints) {
    return 'Parcours ($points points) et plan de course ($checkpoints points de contrôle) envoyés à la montre';
  }

  @override
  String routeDetailWatchScheduleThinned(
    int points,
    int source,
    int checkpoints,
  ) {
    return 'Parcours ($points points) envoyé. Plan de course réduit de $source à $checkpoints points de contrôle pour tenir dans la montre';
  }

  @override
  String routeDetailWatchScheduleClockCutoffs(int checkpoints, int unresolved) {
    return 'Plan de course envoyé ($checkpoints points de contrôle), mais $unresolved barrières horaires nécessitent une heure de départ — définissez-la sur la feuille d’équipe pour qu’elles atteignent la montre';
  }

  @override
  String routeDetailWatchScheduleTooManyCutoffs(
    int points,
    int cutoffs,
    int max,
  ) {
    return 'Parcours ($points points) envoyé, mais le plan de course compte $cutoffs barrières et la montre en accepte $max — supprimez-en pour l’envoyer';
  }

  @override
  String get routeDetailMadePublicForLink =>
      'Rendu public pour que toute personne disposant du lien puisse le voir';

  @override
  String get routeDetailShareConfirmTitle => 'Rendre cet itinéraire public ?';

  @override
  String get routeDetailShareConfirmBody =>
      'Partager un lien rend cet itinéraire public : toute personne disposant du lien peut l\'ouvrir, et il peut apparaître dans Explorer. Vous pouvez le repasser en privé à tout moment.';

  @override
  String get routeDetailShareConfirmCta => 'Rendre public et partager';

  @override
  String routeDetailShareLinkFailed(String error) {
    return 'Impossible de partager le lien : $error';
  }

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
  String get routeDetailReportReview => 'Signaler l\'avis';

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
  String get routeDetailDescribeConsentRequired =>
      'Les descriptions par IA nécessitent votre consentement à l\'information sur l\'IA mise à jour.';

  @override
  String get routeDetailReviewDisclosure => 'Consulter l\'information';

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
  String get routeDetailDeleteReview => 'Supprimer votre avis';

  @override
  String routeDetailReviewDeleteFailed(String error) {
    return 'Impossible de supprimer l\'avis : $error';
  }

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
  String get runHeatmapSignedOutTitle =>
      'Connecte-toi pour voir ta carte de chaleur synchronisée';

  @override
  String get runHeatmapSignedOutBody =>
      'Les courses enregistrées sur cet appareil apparaissent ici. Connecte-toi pour inclure aussi tes courses synchronisées.';

  @override
  String get runHeatmapErrorTitle =>
      'Impossible de charger ta carte de chaleur';

  @override
  String get runHeatmapErrorBody =>
      'Une erreur s\'est produite lors du chargement de tes courses. Vérifie ta connexion et réessaie.';

  @override
  String get runHeatmapRetry => 'Réessayer';

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
  String runNotificationPausedTitle(String activity) {
    return '$activity • en pause';
  }

  @override
  String get activityTypeRun => 'Course';

  @override
  String get activityTypeWalk => 'Marche';

  @override
  String get activityTypeHike => 'Trail';

  @override
  String get activityTypeCycle => 'Vélo';

  @override
  String get activityTypeStroller => 'Poussette';

  @override
  String get feedActivityAll => 'Tout';

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
  String get profileSectionError => 'Impossible de charger cette section.';

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
  String get profileNotifYourRun => 'course';

  @override
  String profileNotifNameAndOthers(String name, int count) {
    return '$name et $count autres';
  }

  @override
  String profileNotifAndOthers(int count) {
    return 'et $count autres';
  }

  @override
  String get profileNotifShowLess => 'Afficher moins';

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
  String profileNotifPlanAssigned(String name) {
    return '$name vous a attribué un plan d\'entraînement';
  }

  @override
  String profileNotifEventCancelTitled(String title) {
    return 'Une occurrence de « $title » a été annulée';
  }

  @override
  String get profileNotifEventCancel =>
      'Une occurrence d\'événement à laquelle vous avez répondu a été annulée';

  @override
  String profileNotifEventReminderTitled(String title) {
    return '« $title » approche';
  }

  @override
  String get profileNotifEventReminder =>
      'Un événement auquel vous participez approche';

  @override
  String get profileNotifAchievement => 'Vous avez obtenu un nouveau succès';

  @override
  String get profileNotifChallengeComplete => 'Vous avez terminé un défi';

  @override
  String get profileNotifContentHidden =>
      'Une de vos publications a été masquée après un signalement';

  @override
  String get profileNotifDataExportReady =>
      'Votre export de données est prêt à télécharger';

  @override
  String get profileNotifRefundFailed =>
      'Un remboursement que nous avions lancé n’a pas pu aboutir. L’argent est toujours chez nous et nous trouverons un autre moyen de vous le rendre.';

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
  String get discoverSearchPlaceholder => 'Rechercher cours, clubs…';

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
  String get clubDetailReadMore => 'Lire la suite';

  @override
  String get clubDetailReportClub => 'Signaler le club';

  @override
  String get clubDetailReportPost => 'Signaler cette publication';

  @override
  String get clubDetailLoadFailedBody =>
      'Impossible de charger ce club. Il a peut-être été supprimé, ou votre session doit être actualisée. Tirez pour réessayer, ou déconnectez-vous et reconnectez-vous depuis les Réglages.';

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
  String get clubDetailDenyTitle => 'Refuser la demande d\'adhésion';

  @override
  String get clubDetailDenyMessage =>
      'Refuser cette demande d\'adhésion au club ? La personne ne sera pas ajoutée.';

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
  String eventPhotosTitle(int count) {
    return 'Photos ($count)';
  }

  @override
  String get eventAddPhoto => 'Ajouter une photo';

  @override
  String get eventPhotoUploading => 'Envoi…';

  @override
  String get eventNoPhotosYet => 'Pas encore de photos.';

  @override
  String get eventNoPhotosAddHint => 'Soyez le premier à en ajouter une.';

  @override
  String get eventWhichRunPhoto => 'De quelle course vient cette photo ?';

  @override
  String get eventNoRecentRuns =>
      'Aucune course récente trouvée. Enregistrez d\'abord une course, puis revenez.';

  @override
  String get eventPhotoRunnerFallback => 'Un coureur';

  @override
  String get eventPhotoUploadFailed => 'Impossible d\'envoyer la photo.';

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
  String get eventOccurrenceCancelled => 'Cette occurrence a été annulée.';

  @override
  String get eventRsvpWaitlisted => 'En liste d\'attente';

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
  String get liveSpectatorStatRaceTime => 'Temps de course';

  @override
  String get liveSpectatorStatTimer => 'Chrono';

  @override
  String get liveSpectatorStatTimerStale => 'Chrono, dernier point';

  @override
  String get liveSpectatorRecentPace => 'Récente';

  @override
  String liveSpectatorCourseProgress(int p) {
    return '$p % du parcours';
  }

  @override
  String liveSpectatorMotionStopped(int n) {
    return 'Aucun mouvement — $n min au même endroit';
  }

  @override
  String liveSpectatorMotionStoppedAtLeast(int n) {
    return 'Aucun mouvement — au moins $n min au même endroit';
  }

  @override
  String get liveSpectatorConcludedTitle => 'Course terminée';

  @override
  String get liveSpectatorConcludedBody =>
      'Voir le parcours complet, les splits et les statistiques.';

  @override
  String get liveSpectatorViewFullRun => 'Voir la course complète';

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
  String get liveCutoffSignalLost =>
      'Signal perdu — arrivée impossible à estimer';

  @override
  String get liveCutoffExpired => 'L\'heure de la barrière est dépassée';

  @override
  String liveCutoffRequiredPace(String pace) {
    return 'Il faut $pace à partir d\'ici';
  }

  @override
  String liveCutoffRequiredPaceStale(String pace) {
    return 'Il faut $pace depuis le dernier point';
  }

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
  String get planNewNameRequiredHint =>
      'Ajoutez un nom de plan pour activer Créer.';

  @override
  String planNewDefaultName(String goal) {
    return 'Plan $goal';
  }

  @override
  String planNewDefaultNameBeginner(String goal) {
    return 'Marche-course vers $goal';
  }

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
  String planNewRaceAnchored(int weeks) {
    return 'Calibré sur votre course : un plan de $weeks semaines dont la dernière semaine est celle de la course. Ajustez ce que vous voulez avant de le créer.';
  }

  @override
  String get planNewRacePast =>
      'Cette course a déjà eu lieu, les dates ci-dessous sont donc celles par défaut.';

  @override
  String get planNewRaceTooSoon =>
      'Cette course est trop proche pour bâtir un plan complet, les dates ci-dessous sont donc celles par défaut.';

  @override
  String get planNewRaceUnreadable =>
      'Nous n\'avons pas pu lire la date de cette course, les dates ci-dessous sont donc celles par défaut.';

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
  String get planNewRampLabel => 'Le plan face à ton entraînement récent';

  @override
  String planNewRampUnder(String peak, String recent) {
    return 'Ce plan culmine à $peak par semaine, en dessous des $recent par semaine que tu as courus en moyenne ces quatre dernières semaines. Une course objectif plus longue ou plus de jours d\'entraînement exploiteraient mieux cette base.';
  }

  @override
  String planNewRampElevated(String opening, String recent) {
    return 'La semaine 1 demande $opening contre tes $recent par semaine en moyenne ces quatre dernières semaines — c\'est une vraie marche. Vas-y progressivement, ou retire un jour d\'entraînement.';
  }

  @override
  String planNewRampHigh(String opening, String recent) {
    return 'La semaine 1 demande $opening, bien au-dessus de tes $recent par semaine en moyenne ces quatre dernières semaines. Moins de jours d\'entraînement, une course objectif plus courte, ou quelques semaines de fond d\'abord rendraient ce premier pas plus sûr.';
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
  String get planNewTemplateCloneFailed => 'Impossible d’adopter ce modèle.';

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
  String get planNewStarterCreateFailed => 'Impossible de créer ce plan.';

  @override
  String get planNewReplaceActiveTitle => 'Remplacer votre plan actif ?';

  @override
  String planNewReplaceActiveNamed(String name) {
    return 'Vous avez déjà un plan actif : \"$name\". Créer un nouveau plan marquera l\'actuel comme terminé (vous le retrouverez dans Gérer les plans). Continuer ?';
  }

  @override
  String get planNewReplaceActiveUnnamed =>
      'Vous avez déjà un plan actif. Créer un nouveau plan marquera l\'actuel comme terminé. Continuer ?';

  @override
  String get planNewReplaceActiveConfirm => 'Remplacer le plan';

  @override
  String get planNewReplaceActiveKeep => 'Garder l\'actuel';

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
  String get planDetailDuplicateConfirmTitle => 'Dupliquer cette semaine ?';

  @override
  String planDetailDuplicateConfirmMessage(int n) {
    return 'Cela insère une copie de la semaine $n et décale chaque semaine suivante et la date de votre course de 7 jours.';
  }

  @override
  String get planDetailDuplicateConfirm => 'Dupliquer';

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
  String get coachTitle => 'Coach IA';

  @override
  String get coachNewConversation => 'Nouvelle conversation';

  @override
  String get coachConsentHeadline =>
      'Avant d\'utiliser les fonctionnalités d\'IA';

  @override
  String get coachConsentIntro =>
      'Les fonctionnalités d\'IA de Threkir — Coach et l\'assistant d\'itinéraires — transmettent une partie de vos données à Anthropic, notre fournisseur de modèles d\'IA aux États-Unis. Selon la fonctionnalité utilisée, cette partie comprend :';

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
  String get coachConsentBulletRoutes =>
      'Pour l\'assistant d\'itinéraires : le nom et les caractéristiques du parcours, la demande que vous saisissez et une indication de lieu approximative — jamais vos coordonnées précises.';

  @override
  String get coachConsentProcessing =>
      'Anthropic traite les données pour le compte de Threkir selon ses conditions de traitement ; par défaut, ils n\'entraînent pas leurs modèles sur les données clients de Threkir. Tous les détails — y compris le mécanisme de transfert, la conservation et vos droits de retrait — figurent dans notre politique de confidentialité.';

  @override
  String get coachConsentAction =>
      'Appuyez sur « J\'accepte » pour continuer. Appuyez sur Annuler pour quitter la page sans envoyer de données.';

  @override
  String get coachConsentCancel => 'Annuler';

  @override
  String get coachConsentAccept =>
      'J\'accepte — activer les fonctionnalités d\'IA';

  @override
  String get coachConsentSaving => 'Enregistrement du consentement…';

  @override
  String aiDisclosureRecordFailed(Object error) {
    return 'Impossible d\'enregistrer le consentement : $error';
  }

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
  String get coachArchiveTapToView => 'Toucher pour voir';

  @override
  String get coachArchiveActions => 'Actions de la conversation';

  @override
  String get coachArchiveDelete => 'Supprimer la conversation';

  @override
  String get coachArchiveDeleteTitle => 'Supprimer cette conversation ?';

  @override
  String get coachArchiveDeleteBody =>
      'Cette conversation archivée sera définitivement supprimée.';

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
  String get coachSuggestNewFirstRun =>
      'Je n\'ai jamais couru — par où commencer ?';

  @override
  String get coachSuggestNewFirstFeel =>
      'Comment ma première course devrait-elle se ressentir ?';

  @override
  String get coachSuggestNewHowOften =>
      'À quelle fréquence courir quand on débute ?';

  @override
  String get coachSuggestNewWalkRun =>
      'Est-ce que je peux marcher pendant mes courses ?';

  @override
  String get coachEditMessageLabel => 'Modifier votre message';

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
  String get coachNewConversationFailed =>
      'Impossible de démarrer une nouvelle conversation.';

  @override
  String get coachOpenArchiveFailed => 'Impossible d\'ouvrir l\'archive.';

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Impossible de supprimer l\'archive : $error';
  }

  @override
  String get coachReactionFailed =>
      'Impossible d’enregistrer votre réaction. Réessayez.';

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
  String get settingsAccountPasswordsMismatch =>
      'Les mots de passe ne correspondent pas';

  @override
  String get settingsAccountPasswordUpdated => 'Mot de passe mis à jour';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Impossible de mettre à jour le mot de passe : $error';
  }

  @override
  String get settingsAccountCurrentPassword => 'Mot de passe actuel';

  @override
  String get settingsAccountPasswordStepUpHint =>
      'Pour votre sécurité, saisissez votre mot de passe actuel pour le modifier. Inscrit avec Google ou Apple ? Envoyez-vous un lien de réinitialisation pour en définir un.';

  @override
  String get settingsAccountCurrentPasswordRequired =>
      'Saisissez votre mot de passe actuel pour le modifier.';

  @override
  String get settingsAccountCurrentPasswordIncorrect =>
      'Ce mot de passe actuel est incorrect. Si vous n\'avez jamais défini de mot de passe, envoyez-vous plutôt un lien de réinitialisation.';

  @override
  String get settingsAccountSendResetLink =>
      'M\'envoyer un lien de réinitialisation';

  @override
  String get settingsAccountSendingResetLink => 'Envoi…';

  @override
  String get settingsAccountResetLinkSent =>
      'Lien de réinitialisation envoyé. Consultez vos e-mails pour définir un nouveau mot de passe.';

  @override
  String get settingsAccountChangeEmail => 'Changer d\'e-mail';

  @override
  String get settingsAccountNewEmail => 'Nouvel e-mail';

  @override
  String get settingsAccountEmailChangeInvalid =>
      'Saisissez une adresse e-mail valide et différente de l\'actuelle.';

  @override
  String settingsAccountEmailChangePending(Object old, Object newEmail) {
    return 'Confirmation en attente. Vérifiez à la fois votre ancienne boîte de réception ($old) et la nouvelle ($newEmail), et suivez le lien dans chacune pour finaliser le changement. Votre e-mail ne changera pas tant que vous ne l\'aurez pas confirmé depuis les deux.';
  }

  @override
  String settingsAccountEmailChangeFailed(Object error) {
    return 'Impossible de démarrer le changement d\'e-mail : $error';
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
      'Retirer le consentement aux fonctionnalités d\'IA';

  @override
  String get settingsAccountCoachConsentActive =>
      'Empêchez les fonctionnalités d\'IA de Threkir d\'utiliser vos données. Vous pouvez consentir à nouveau à tout moment.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Consentement aux fonctionnalités d\'IA retiré.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Échec du retrait : $error';
  }

  @override
  String get settingsAccountAiConsentUpdateTitle =>
      'Accepter l\'information sur l\'IA mise à jour';

  @override
  String get settingsAccountAiConsentUpdateSubtitle =>
      'L\'information couvre désormais davantage de fonctionnalités. Lisez-la et acceptez-la pour utiliser l\'assistant d\'itinéraires.';

  @override
  String get settingsAccountAiConsentGrantTitle =>
      'Consulter l\'information sur l\'IA';

  @override
  String get settingsAccountAiConsentGrantSubtitle =>
      'Les fonctionnalités d\'IA de Threkir demandent votre consentement avant d\'utiliser vos données. Lisez l\'information et acceptez-la ici.';

  @override
  String get settingsAccountAiConsentAccepted =>
      'Information sur l\'IA acceptée.';

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
  String settingsAccountBackupPartial(int count, int total) {
    return 'Export partiel — $count courses sur $total.';
  }

  @override
  String settingsAccountBackupPartialNotice(int count, int total) {
    return 'Ton dernier export est partiel : il contient $count des $total courses de ton compte. Rien n\'a été supprimé — relance l\'export pour réessayer. L\'archive complète du compte indique chaque section incomplète dans son manifest.json.';
  }

  @override
  String settingsAccountBackupTracksPartial(int missing, int total) {
    return 'Il manque $missing des $total fichiers GPS dans la sauvegarde.';
  }

  @override
  String settingsAccountBackupTracksPartialNotice(int missing, int total) {
    return 'Ta dernière sauvegarde n\'a pas pu télécharger $missing des $total fichiers de tracé GPS. Toutes les courses sont dans l\'archive ; relance l\'export pour récupérer les tracés. Son manifest.json indique complete: false.';
  }

  @override
  String settingsAccountRestoreIncompleteArchive(int runs) {
    return 'Cette archive se déclarait incomplète. $runs courses ont été restaurées et rien n\'a été écrasé — restaure depuis une sauvegarde complète pour combler les manques.';
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
  String get settingsAccountAvatarRemoveTitle =>
      'Supprimer la photo de profil ?';

  @override
  String get settingsAccountAvatarRemoveConfirm =>
      'Cela supprime votre photo de profil actuelle. Vous pouvez en importer une nouvelle à tout moment.';

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
  String get guidedRunsTitle => 'Courses guidées';

  @override
  String get guidedRunsSubtitle =>
      'Séances scriptées avec voix de coach et repères TTS';

  @override
  String get privacyZonesTitle => 'Zones de confidentialité';

  @override
  String get privacyZonesSubtitle =>
      'Masque le début/la fin des tracés publics près de chez toi';

  @override
  String get settingsAccountSendErrorReports =>
      'Envoyer des rapports d\'erreur';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Données anonymisées de plantage et d\'erreur vers Sentry (USA). Désactive pour retirer ton consentement. Appliqué au prochain lancement.';

  @override
  String get settingsAccountDisplayName => 'Nom affiché';

  @override
  String get settingsAccountDisplayNameHint =>
      'Le nom que voient les autres coureurs. Laisse vide pour utiliser « Runner ».';

  @override
  String get settingsAccountDisplayNameUnset =>
      'Non défini — tu apparais comme « Runner »';

  @override
  String get settingsAccountDisplayNameUpdated => 'Nom affiché mis à jour';

  @override
  String get settingsAccountDisplayNameUpdateFailed =>
      'Échec de la mise à jour du nom affiché. Réessaie.';

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
  String get settingsAccountAccountExport => 'Export du compte';

  @override
  String get settingsAccountAccountExportSubtitle =>
      'Tout ce que contient ton compte : courses, itinéraires, messages, commandes, intégrations, contacts d\'urgence. Créé sur notre serveur ; tu peux fermer l\'appli pendant ce temps.';

  @override
  String get settingsAccountExportQueued =>
      'Ton export est en cours de création. Tu peux fermer l\'appli — reviens ici pour le télécharger.';

  @override
  String get settingsAccountExportBuildingNotice =>
      'Ton export de compte est en cours de création. Tu peux fermer l\'appli ; il continue sans toi.';

  @override
  String get settingsAccountExportReadyNotice =>
      'Ton export de compte est prêt.';

  @override
  String get settingsAccountExportDownload => 'Télécharger et partager';

  @override
  String settingsAccountExportFailedNotice(String error) {
    return 'Ton dernier export de compte a échoué ($error). Rien n\'a été supprimé — demandes-en un autre.';
  }

  @override
  String get settingsAccountExportStalledNotice =>
      'Ton dernier export de compte ne répond plus. Rien n\'a été supprimé — demandes-en un autre.';

  @override
  String get settingsAccountExportExpiredNotice =>
      'Ton dernier export de compte a expiré. Les exports sont supprimés au bout de 7 jours — demandes-en un autre.';

  @override
  String get settingsAccountExportStatusUnavailable =>
      'Impossible de joindre le service d\'export pour vérifier l\'état. Il est peut-être encore en cours.';

  @override
  String get settingsAccountExportUnavailable =>
      'Le service d\'export du compte n\'est pas configuré dans cette version. La sauvegarde complète ci-dessous est créée sur cet appareil et n\'inclut pas les données de ton compte.';

  @override
  String settingsAccountExportUnsyncedWarning(int count) {
    return '$count courses ne sont pas encore synchronisées. L\'export du compte est créé sur le serveur, il ne les inclura donc pas — utilise la sauvegarde complète pour les conserver.';
  }

  @override
  String get settingsAccountBackupOnDeviceNotice =>
      'Ta dernière sauvegarde complète a été créée sur cet appareil. Elle contient tes courses, itinéraires, ton profil, tes préférences et tes journaux de salle et de repas — mais pas les données de ton compte. Utilise l\'export du compte pour la copie complète.';

  @override
  String settingsAccountExportRateLimited(int seconds) {
    return 'Limite d\'exports atteinte — réessaie dans $seconds secondes.';
  }

  @override
  String settingsAccountExportRequestFailed(String error) {
    return 'Impossible de demander ton export : $error';
  }

  @override
  String settingsAccountExportDownloadFailed(String error) {
    return 'Impossible de télécharger ton export : $error';
  }

  @override
  String settingsAccountExportReadyBanner(int count) {
    return 'Ton export de compte est prêt — $count courses.';
  }

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
  String integrationsSyncPartial(int imported, int skipped) {
    return 'La synchro s\'est arrêtée avant la fin. $imported nouvelles, $skipped déjà présentes : certaines activités n\'ont pas été récupérées. Relancez la synchro pour terminer.';
  }

  @override
  String integrationsSyncPartialRateLimited(int imported, int skipped) {
    return 'Strava limite les requêtes, la synchro s\'est donc arrêtée avant la fin. $imported nouvelles, $skipped déjà présentes. Réessayez dans environ 15 minutes.';
  }

  @override
  String integrationsSyncResultWithFailed(
    int imported,
    int skipped,
    int failed,
  ) {
    return 'Synchronisé. $imported nouvelles, $skipped déjà présentes, $failed échouées.';
  }

  @override
  String integrationsStravaConnectedPartial(int imported, int skipped) {
    return 'Strava connecté, mais le premier import s\'est arrêté avant la fin. $imported importées, $skipped déjà présentes : relancez la synchro pour terminer.';
  }

  @override
  String integrationsStravaConnectedPartialRateLimited(
    int imported,
    int skipped,
  ) {
    return 'Strava connecté, mais Strava limite les requêtes : le premier import s\'est arrêté avant la fin. $imported importées, $skipped déjà présentes. Relancez la synchro dans environ 15 minutes.';
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
  String integrationsImportPartialOf(int n, int total) {
    return 'Seule une partie de votre historique a pu être importée : $n sur $total.';
  }

  @override
  String integrationsImportPartial(int n) {
    return 'Tous les résultats n\'ont pas pu être lus. Importés : $n.';
  }

  @override
  String get integrationsImportTruncated =>
      'La liste des résultats était trop longue pour être lue jusqu\'au bout, votre résultat n\'a donc pas pu être confirmé. Saisissez-le manuellement.';

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
  String get integrationsStravaSyncHistory =>
      'Synchroniser l\'historique plus ancien…';

  @override
  String get integrationsStravaLookbackTitle => 'Jusqu\'où remonter';

  @override
  String get integrationsStravaLookback90 => '90 derniers jours';

  @override
  String get integrationsStravaLookback180 => '6 derniers mois';

  @override
  String get integrationsStravaLookback365 => 'Dernière année';

  @override
  String get integrationsSyncPartialNoteResumable =>
      'La dernière synchro s\'est arrêtée avant la fin de la période. Une nouvelle synchro reprendra là où elle s\'est arrêtée.';

  @override
  String get integrationsSyncPartialNote =>
      'La dernière synchro s\'est arrêtée avant la fin de la période sans enregistrer de point de reprise. Relancez-la pour réessayer.';

  @override
  String get integrationsSyncNow => 'Synchroniser maintenant';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Importer les résultats par numéro d\'athlète';

  @override
  String get integrationsParkrunRegionNote =>
      'parkrun n\'est présent que dans certains pays et il se peut qu\'aucun événement n\'ait lieu près de chez toi — tu peux quand même importer tes résultats avec un numéro d\'athlète parkrun.';

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
  String get proComingSoonTitle => 'Pro — bientôt disponible';

  @override
  String get proComingSoon =>
      'Pro débloque le coach IA — bientôt disponible. Tu peux tout de même soutenir l\'app ci-dessous.';

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
  String get aboutTitle => 'À propos et mises à jour';

  @override
  String get aboutVersion => 'Version';

  @override
  String get licensesOpenSource => 'Licences open source';

  @override
  String get licensesOpenSourceSubtitle => 'Paquets tiers intégrés à cette app';

  @override
  String get aboutCheckForUpdates => 'Rechercher des mises à jour';

  @override
  String get aboutCheckingUpdate => 'Recherche de mises à jour…';

  @override
  String get aboutUpdateAvailable => 'Mise à jour disponible';

  @override
  String get aboutUpdateAvailableSubtitle =>
      'Une version plus récente est prête à être installée.';

  @override
  String get aboutUpdate => 'Mettre à jour';

  @override
  String get aboutUpToDate => 'Vous avez la dernière version';

  @override
  String get aboutUpdateUnavailable =>
      'Cette version se met à jour via la boutique depuis laquelle vous l\'avez installée.';

  @override
  String get aboutUpdateFailed =>
      'Impossible de lancer la mise à jour. Réessayez depuis le Play Store.';

  @override
  String get legalPrivacy => 'Politique de confidentialité';

  @override
  String get legalTerms => 'Conditions d\'utilisation';

  @override
  String get legalCookieNotice => 'Avis relatif aux cookies';

  @override
  String get legalHealthDataNotice => 'Confidentialité des données de santé';

  @override
  String get mapAttributionSemantics =>
      'Attribution des données cartographiques';

  @override
  String mapAttributionProvider(String name) {
    return '© $name';
  }

  @override
  String mapAttributionOsmContributors(String name) {
    return '© les contributeurs $name';
  }

  @override
  String legalCouldNotOpen(String url) {
    return 'Impossible d\'ouvrir $url';
  }

  @override
  String get aboutLegalSection => 'Mentions légales';

  @override
  String get devicesTitle => 'Appareils connectés';

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
  String gearRotationNextUp(String name) {
    return 'Prochaine paire : $name';
  }

  @override
  String get gearRotationNextUpWhy => 'La moins usée de cette rotation.';

  @override
  String get gearRotationMakeCurrent => 'Définir comme paire actuelle';

  @override
  String gearRotationMakeCurrentLabel(String name) {
    return 'Définir $name comme paire actuelle — les nouvelles courses seront automatiquement associées à cette paire';
  }

  @override
  String get gearRotationNextUpIsCurrent => 'Déjà la paire actuelle.';

  @override
  String get gearRotationAllWorn =>
      'Toutes les paires ici ont atteint ou dépassé leur objectif de remplacement.';

  @override
  String gearRotationMakeCurrentFailed(Object error) {
    return 'Impossible de changer la paire actuelle : $error';
  }

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
  String get privacyZonesDiscardBody =>
      'Vous avez des zones de confidentialité non enregistrées. Quitter sans enregistrer ?';

  @override
  String get discardChangesTitle => 'Ignorer les modifications ?';

  @override
  String get discardChangesBody =>
      'Vous avez des modifications non enregistrées. Quitter sans enregistrer ?';

  @override
  String get discardChangesCancel => 'Annuler';

  @override
  String get discardChangesDiscard => 'Ignorer';

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
  String prefsSplitIntervalDefaultSubtitle(String run, String cycle) {
    return 'Par défaut ($run en course, $cycle à vélo)';
  }

  @override
  String get prefsSplitPaceMode => 'Annonce des splits';

  @override
  String get prefsSplitPaceModeSubtitle => 'Quelle allure chaque split annonce';

  @override
  String get prefsSplitPaceModeSplit => 'Allure du split';

  @override
  String get prefsSplitPaceModeAverage => 'Allure moyenne';

  @override
  String get prefsSplitPaceModeBoth => 'Les deux';

  @override
  String get prefsSplitPaceModeInfo =>
      'À chaque split, choisis l\'allure que tu entends : celle de ce seul split, ton allure moyenne depuis le début de la course, ou les deux. Pratique pour tenir un effort régulier. Exemple : « 1 kilomètre. Allure moyenne, 5 minutes 45 secondes au kilomètre. »';

  @override
  String get prefsTargetPace => 'Allure cible';

  @override
  String get prefsTargetPaceInfo =>
      'L\'allure que tu veux tenir. Seule, elle reste silencieuse — active le repère vocal « Alertes d\'écart d\'allure » pour entendre « accélère » ou « ralentis » quand tu t\'en écartes de plus de 30 secondes. Exemple : « Accélère de 8 secondes. »';

  @override
  String get prefsCueInfoTooltip => 'Qu\'est-ce que c\'est ?';

  @override
  String get prefsLivePaceAlert => 'Allure cible';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 's';

  @override
  String get prefsLivePaceAlertOff =>
      'Non définie — définis une cible, puis active les alertes d\'écart d\'allure';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — les alertes d\'écart d\'allure parlent dès 30 s d\'écart';
  }

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
  String get prefsEmailReOptInFailed =>
      'Impossible d\'annuler votre désabonnement précédent. Les e-mails peuvent rester bloqués ; réessayez.';

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
  String get prefsAudioCuesSubtitle =>
      'Annonce les splits, l\'allure et d\'autres repères pendant la course';

  @override
  String get prefsMinimalVoiceCues => 'Repères vocaux minimaux';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Ignore les rappels bavards de mi-répétition et de dérive d\'allure';

  @override
  String get prefsKeepScreenOn => 'Garder l\'écran allumé';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Garde l\'écran allumé pendant toute la course. Consomme nettement plus de batterie sur les longues sorties.';

  @override
  String get prefsDimScreenWhileRecording =>
      'Assombrir l\'écran pendant l\'enregistrement';

  @override
  String get prefsDimScreenWhileRecordingSubtitle =>
      'Assombrit la carte pendant une course pour économiser la batterie. Les statistiques restent lisibles.';

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
  String get prefsShowCalories => 'Afficher les estimations de calories';

  @override
  String get prefsShowCaloriesHint =>
      'Estimées à partir de la distance et du poids corporel (70 kg par défaut si non renseigné). Désactivez pour masquer les calories sur les pages de course.';

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
  String get dashboardProfileTooltip => 'Ton profil';

  @override
  String get dashboardWelcomeTitle => 'Bienvenue !';

  @override
  String get dashboardWelcomeBody =>
      'Ton tableau de bord se remplit dès que tu enregistres une course, définis un objectif ou importes ton historique.';

  @override
  String get dashboardStartRun => 'Démarrer une course';

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
  String dashboardPbAgeGrade(String percent) {
    return '$percent indice d\'âge';
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
  String get dashboardHeatmapTitle => 'Activité';

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
  String get mileageTitle => 'Kilométrage';

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
  String get runSocialReportComment => 'Signaler le commentaire';

  @override
  String get runSocialReportReply => 'Signaler la réponse';

  @override
  String get runSocialPost => 'Publier';

  @override
  String get runSocialCancel => 'Annuler';

  @override
  String get kudosGiveLabel => 'Donner des kudos';

  @override
  String get kudosRemoveLabel => 'Retirer les kudos';

  @override
  String get kudosViewCommentsLabel => 'Voir les commentaires';

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
  String get runPhotosPermissionDenied =>
      'L\'accès aux photos est nécessaire pour ajouter une photo. Vous pouvez l\'autoriser dans les Réglages.';

  @override
  String get runPhotosOpenSettings => 'Ouvrir les réglages';

  @override
  String get runPhotosPickerFailed =>
      'Impossible d\'ouvrir le sélecteur de photos. Veuillez réessayer.';

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
  String get runSegEffortsRankUnknown => 'Classement indisponible';

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
  String get workoutReviewAdherenceCompleted => 'Terminée';

  @override
  String get workoutReviewAdherencePartial => 'Partielle';

  @override
  String get workoutReviewAdherenceAbandoned => 'Abandonnée';

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
  String get segmentsPanelLoadError => 'Impossible de charger les segments';

  @override
  String get segmentsPanelLeaderboardError =>
      'Impossible de charger le classement';

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
  String get segmentsPanelErrNameRequired => 'Saisissez un nom de segment';

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
  String get clubFormErrName => 'Donnez un nom au club.';

  @override
  String get clubFormErrSlug =>
      'Le nom doit contenir au moins une lettre ou un chiffre.';

  @override
  String get eventFormErrTitle => 'Donnez un titre à l\'événement.';

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
  String get reportTitleComment => 'Signaler le commentaire';

  @override
  String get reportTitlePost => 'Signaler la publication';

  @override
  String get reportTitleRun => 'Signaler la course';

  @override
  String get reportTitleReview => 'Signaler l\'avis';

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
  String get runGearChipsLoadFailed => 'Impossible de charger l\'équipement.';

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
  String ttsSplitAverage(String count, String unit, String tail) {
    return '$count $unit. Moyenne $tail';
  }

  @override
  String ttsSplitBoth(String count, String unit, String tail, String avgTail) {
    return '$count $unit. $tail. Moyenne $avgTail';
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
  String get planPhaseGraduation => 'Semaine de fin de programme';

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
      'Connecte-toi pour voir où tu es connecté';

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
      'Connexion, profil, import et sauvegarde, suppression du compte';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Unités, thème, enregistrement, entraînement, confidentialité';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, calendrier des courses, ceinture cardio, tapis de course, montre';

  @override
  String get settingsTabDevicesSubtitle =>
      'Où tu es connecté et les réglages par appareil — appaire une ceinture ou un tapis dans Intégrations';

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
  String get settingsTabAboutSubtitle =>
      'Version, mises à jour et documents juridiques';

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
  String gymDeleteFailed(Object error) {
    return 'Impossible de supprimer la séance : $error';
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
  String get gymDistance => 'Distance (m)';

  @override
  String gymDistanceValue(String metres) {
    return '$metres m';
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
  String get clubEventAddToCalendar => 'Ajouter au calendrier';

  @override
  String get clubEventAddOccurrenceToCalendar => 'Ajouter cette occurrence';

  @override
  String get clubEventAddSeriesToCalendar => 'Ajouter toute la série';

  @override
  String get clubEventCalendarUnavailable =>
      'Impossible d\'ouvrir votre application Calendrier.';

  @override
  String clubEventCalendarCancelledNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Votre calendrier ne peut pas ignorer les dates annulées : $count occurrences annulées apparaîtront quand même.',
      one:
          'Votre calendrier ne peut pas ignorer les dates annulées : 1 occurrence annulée apparaîtra quand même.',
    );
    return '$_temp0';
  }

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
  String gymCatalogueOtherCategory(String name, String category) {
    return '« $name » est déjà dans le catalogue, dans $category.';
  }

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
  String get gymRoutineHistoryTitle => 'Historique de la routine';

  @override
  String get gymRoutineHistoryRecent => 'Séances récentes';

  @override
  String gymRoutineHistoryLastDone(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Faite il y a $days jours',
      one: 'Faite hier',
      zero: 'Faite aujourd’hui',
    );
    return '$_temp0';
  }

  @override
  String gymRoutineHistoryCompletedRate(int completed, int graded) {
    return '$completed sur $graded terminées';
  }

  @override
  String get gymRoutineHistoryVerdictUngraded => 'Non évaluée';

  @override
  String get gymRoutineHistoryLoadError =>
      'Impossible de charger l’historique de cette routine.';

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
  String get gymRoutineNextTargetEstablishBaseline =>
      'Établir une base — définir le poids de départ';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — réduire la charge';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'montée de répétitions $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrition';

  @override
  String get nutritionDayNavLabel => 'Jour du journal';

  @override
  String get nutritionDayPrevious => 'Jour précédent';

  @override
  String get nutritionDayNext => 'Jour suivant';

  @override
  String get nutritionDayToday => 'Aujourd\'hui';

  @override
  String get nutritionDayYesterday => 'Hier';

  @override
  String get nutritionDayBackfillHint =>
      'Tout ce que vous enregistrez ici est ajouté à ce jour.';

  @override
  String get nutritionDayEmptyPast => 'Rien d\'enregistré ce jour-là.';

  @override
  String nutritionDayGoalBreakdown(int base, int exercise) {
    return 'Objectif $base + $exercise kcal brûlées ce jour-là';
  }

  @override
  String nutritionDayTrendEnding(String date) {
    return '7 jours jusqu\'au $date';
  }

  @override
  String nutritionDayLogHeadingFor(String date) {
    return 'Enregistrer un aliment — $date';
  }

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
  String get nutritionFiber => 'Fibres';

  @override
  String get nutritionSugar => 'Sucre';

  @override
  String get nutritionSodium => 'Sodium';

  @override
  String get nutritionSaturatedFat => 'Graisses saturées';

  @override
  String get nutritionCholesterol => 'Cholestérol';

  @override
  String get nutritionNutrients => 'Nutriments';

  @override
  String get nutritionNutrientsHint =>
      'Valeurs de référence. Chaque total ne compte que les aliments enregistrés qui indiquent ce nutriment.';

  @override
  String get nutritionNutrientAtLeast => 'au moins';

  @override
  String nutritionNutrientPartial(int reported, int total, String nutrient) {
    return '$reported aliments enregistrés sur $total indiquent $nutrient';
  }

  @override
  String nutritionNutrientOver(String n, String unit) {
    return '$n $unit de trop';
  }

  @override
  String nutritionNutrientLeft(String n, String unit) {
    return '$n $unit restants';
  }

  @override
  String get nutritionNutrientReached => 'Objectif atteint';

  @override
  String get nutritionNutrientUntargeted => 'Pas d’objectif quotidien';

  @override
  String get nutritionWater => 'Eau';

  @override
  String get nutritionWaterAdd => 'Ajouter de l\'eau';

  @override
  String get nutritionWaterRemove => 'Retirer de l\'eau';

  @override
  String get nutritionNoTargets =>
      'Renseigne ta taille, ton poids, ton âge et ton sexe pour voir les objectifs de calories et de macros.';

  @override
  String get nutritionAddBodyMetrics => 'Ajouter mes données corporelles';

  @override
  String get nutritionTargetsLink => 'Objectifs';

  @override
  String get nutritionTargetsTitle => 'Objectifs de calories et de macros';

  @override
  String get nutritionTargetsSubtitle =>
      'Comment l\'objectif du jour est calculé, et les deux réglages qui le déterminent.';

  @override
  String get nutritionTargetsTotal => 'Objectif du jour';

  @override
  String get nutritionTargetsBmr => 'Métabolisme de repos';

  @override
  String get nutritionTargetsBase => 'Objectif de base';

  @override
  String nutritionTargetsBaseFloored(int n) {
    return 'Maintenu au plancher de $n kcal — l\'objectif quotidien le plus bas que nous recommandons.';
  }

  @override
  String get nutritionTargetsExercise => 'Entraînements du jour';

  @override
  String get nutritionTargetsExerciseHint =>
      'Les courses et séances de muscu enregistrées aujourd\'hui s\'ajoutent par-dessus.';

  @override
  String get nutritionTargetsMacrosHeading => 'Macros';

  @override
  String nutritionTargetsProteinHint(String n) {
    return '$n g par kg de poids corporel';
  }

  @override
  String get nutritionTargetsCarbsHint => 'Ce qui reste — ton carburant';

  @override
  String nutritionTargetsFatHint(int n) {
    return '$n% des calories';
  }

  @override
  String get nutritionTargetsDefaultsHeading => 'Tes valeurs par défaut';

  @override
  String get nutritionTargetsDefaultsHint =>
      'Le niveau d\'activité correspond à ta journée type hors entraînements — les courses et séances de muscu enregistrées sont ajoutées séparément. Les deux sont enregistrés dès que tu les modifies.';

  @override
  String get nutritionTargetsMetricsHeading => 'Mesures corporelles';

  @override
  String get nutritionTargetsMetricsHint =>
      'La taille, le poids, la date de naissance et le sexe sont des données de santé : ils se modifient dans les réglages, derrière leur consentement.';

  @override
  String get nutritionTargetsEditMetrics => 'Modifier dans les réglages';

  @override
  String get nutritionTargetsUnset => 'Non renseigné';

  @override
  String get nutritionTargetsEmptyTitle => 'Pas encore d\'objectifs';

  @override
  String get nutritionTargetsEmptyBody =>
      'Renseigne ta taille, ton poids, ta date de naissance et ton sexe et tes objectifs de calories et de macros apparaîtront ici.';

  @override
  String get nutritionTargetsAge => 'Âge';

  @override
  String nutritionTargetsAgeYears(int n) {
    return '$n ans';
  }

  @override
  String get nutritionTargetsAgeConsentWithheld =>
      'Nécessite le consentement aux données de santé';

  @override
  String get nutritionTargetsLoadError =>
      'Impossible de charger tes objectifs.';

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
  String nutritionWeekProtein(int met, int total) {
    return 'Protéines $met/$total jours';
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
  String nutritionDeleteFailed(String error) {
    return 'Impossible de supprimer l’entrée : $error';
  }

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
  String nutritionTemplateDeleteFailed(String error) {
    return 'Impossible de supprimer le modèle : $error';
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
  String nutritionRecipeDeleteFailed(String error) {
    return 'Impossible de supprimer la recette : $error';
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
  String get gymSessionLeaveSaveFailed =>
      'Impossible d\'enregistrer votre brouillon — vous êtes toujours ici, rien n\'est perdu. Réessayez ou abandonnez la séance volontairement.';

  @override
  String get gymSessionLeaveTitle => 'Quitter la séance ?';

  @override
  String get gymSessionLeaveBody =>
      'Vos séries enregistrées sont conservées en brouillon — vous pourrez reprendre la séance depuis l\'onglet Muscu, ou la supprimer.';

  @override
  String get gymSessionLeaveDraft => 'Quitter — garder le brouillon';

  @override
  String get gymSessionKeepGoing => 'Continuer la séance';

  @override
  String get gymDraftTitle => 'Séance en cours';

  @override
  String gymDraftSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séries enregistrées',
      one: '1 série enregistrée',
    );
    return '$_temp0';
  }

  @override
  String get gymDraftResume => 'Reprendre';

  @override
  String get gymDraftSave => 'Enregistrer en l\'état';

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
  String get coachingTitle => 'Athlètes et coachs';

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
  String get routeMarkerCutoffInvalid =>
      'Saisis la barrière horaire au format HH:MM (24 h)';

  @override
  String get routeMarkerTimeClock => 'Horloge';

  @override
  String get routeMarkerTimeElapsed => 'Écoulé';

  @override
  String get routeMarkerNoteLabel => 'Note';

  @override
  String get routeMarkerTapToPlace => 'Touchez la carte pour placer ce repère.';

  @override
  String get routeMarkerSnapToggle => 'Aligner sur le tracé de l\'itinéraire';

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
  String get routeMarkerLatLabel => 'Latitude';

  @override
  String get routeMarkerLngLabel => 'Longitude';

  @override
  String get routeMarkerCoordInvalid =>
      'Saisissez une latitude valide (-90 à 90) et une longitude valide (-180 à 180).';

  @override
  String get routeMarkerEnterCoords => 'Saisir l\'emplacement à la place';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Impossible d\'enregistrer le repère : $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Impossible de supprimer le repère : $error';
  }

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
  String get roadbookPlanTitle => 'Plan de course';

  @override
  String get roadbookPlanExplain =>
      'La montre en déduit les heures d\'arrivée et les barrières horaires. Définis une heure de départ pour envoyer aussi les barrières exprimées en heure de la journée.';

  @override
  String get roadbookPlanCancel => 'Annuler';

  @override
  String get roadbookPlanSend => 'Envoyer';

  @override
  String get roadbookPlanGoalInvalid => 'Saisis un temps visé comme 4:30:00';

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
  String get roadbookColTarget => 'Objectif';

  @override
  String get roadbookColLegPace => 'Allure du tronçon';

  @override
  String get roadbookTargetAhead => 'en avance';

  @override
  String get roadbookTargetOn => 'dans les temps';

  @override
  String get roadbookTargetBehind => 'en retard';

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
  String get checkpointWeighInBodyWeight => 'Poids corporel';

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
  String get challengesPaceAhead => 'En avance sur le rythme';

  @override
  String get challengesPaceOnTrack => 'Dans les temps';

  @override
  String get challengesPaceBehind => 'En retard sur le rythme';

  @override
  String challengesPaceNeedPerDay(String rate) {
    return '$rate par jour pour finir';
  }

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
  String get challengesStandingTitle => 'Votre classement';

  @override
  String get challengesStandingTitleTeam => 'Classement de votre équipe';

  @override
  String challengesStandingRank(int rank, int total) {
    return '#$rank sur $total';
  }

  @override
  String get challengesStandingTiedOne => 'À égalité avec 1 autre';

  @override
  String challengesStandingTiedMany(int n) {
    return 'À égalité avec $n autres';
  }

  @override
  String challengesStandingBehind(String gap, String name) {
    return '$gap derrière $name';
  }

  @override
  String challengesStandingAhead(String gap, String name) {
    return '$gap devant $name';
  }

  @override
  String get challengesStandingLeading => 'En tête';

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
  String get challengesDeleteFailed => 'Impossible de supprimer le défi.';

  @override
  String get challengesLoadFailed => 'Impossible de charger les défis.';

  @override
  String get challengesProgressUnavailable =>
      'Progression indisponible – ouvrez pour voir votre résultat';

  @override
  String get challengesTeamNoClub => 'Sans club';

  @override
  String get challengesTeamPrivateClub => 'Club privé';

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
  String racesDistanceAway(String distance) {
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
  String get racesTrainForThis => 'S\'entraîner pour cette course';

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
  String get racesRunSignUpBibHint =>
      'Saisissez votre dossard pour n\'importer que votre résultat, pas tout le classement.';

  @override
  String get racesUltraSignUpAthleteId => 'Identifiant athlète UltraSignup';

  @override
  String get racesUltraSignUpAthleteHint =>
      'Saisissez votre identifiant athlète UltraSignup, ou laissez le champ vide pour utiliser celui de cette course.';

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
  String get integrationsUltrasignup => 'UltraSignup';

  @override
  String get integrationsUltrasignupConnect =>
      'Importez les résultats trail et ultra depuis UltraSignup.';

  @override
  String get integrationsUltrasignupOpen => 'Ouvrir le calendrier des courses';

  @override
  String get integrationsUltrasignupUnavailable =>
      'L\'import UltraSignup n\'est pas encore disponible. parkrun et le collage manuel fonctionnent toujours.';

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

  @override
  String get settingsSectionDeveloper => 'Développeur';

  @override
  String get settingsTabSimWatchSubtitle =>
      'État en direct de la montre personnalisée simulée';

  @override
  String get simWatchTitle => 'Liaison montre simulée';

  @override
  String get simWatchHostLabel => 'Hôte';

  @override
  String get simWatchPortLabel => 'Port';

  @override
  String get simWatchConnect => 'Se connecter';

  @override
  String get simWatchConnecting => 'Connexion…';

  @override
  String get simWatchDisconnect => 'Se déconnecter';

  @override
  String simWatchConnectionFailed(String error) {
    return 'Échec de la connexion : $error';
  }

  @override
  String get simWatchSyncAction => 'Synchroniser les courses de la montre';

  @override
  String simWatchSyncing(int done, int total) {
    return 'Synchronisation… $done/$total';
  }

  @override
  String simWatchResult(int synced, int total) {
    return '$synced course(s) sur $total synchronisée(s) depuis la montre';
  }

  @override
  String simWatchSyncFailed(String error) {
    return 'Échec de la synchronisation de la montre : $error';
  }

  @override
  String get simWatchPushSettingsAction => 'Envoyer les réglages à la montre';

  @override
  String get simWatchSettingsPushed => 'Réglages envoyés à la montre';

  @override
  String simWatchPushSettingsFailed(String error) {
    return 'Échec de l\'envoi des réglages : $error';
  }

  @override
  String get simWatchPushWorkoutAction => 'Envoyer la séance à la montre';

  @override
  String simWatchWorkoutPushed(int steps) {
    return 'Séance envoyée à la montre ($steps étapes)';
  }

  @override
  String simWatchPushWorkoutFailed(String error) {
    return 'Échec de l\'envoi de la séance : $error';
  }

  @override
  String get simWatchPushRoadbookAction =>
      'Envoyer le plan de course à la montre';

  @override
  String simWatchRoadbookPushed(int checkpoints, int cutoffs) {
    return 'Plan de course envoyé à la montre ($checkpoints points de contrôle, $cutoffs barrières)';
  }

  @override
  String simWatchPushRoadbookFailed(String error) {
    return 'Échec de l’envoi du plan de course : $error';
  }

  @override
  String get simWatchPushCourseAction => 'Envoyer le parcours à la montre';

  @override
  String simWatchCoursePushed(int points) {
    return 'Parcours envoyé à la montre ($points points)';
  }

  @override
  String simWatchPushCourseFailed(String error) {
    return 'Échec de l\'envoi du parcours : $error';
  }

  @override
  String get simWatchNoRuns => 'Aucune course à synchroniser sur la montre';

  @override
  String get simWatchWaitingFrames => 'Connecté — en attente de trames…';

  @override
  String get simWatchUptime => 'Temps de fonctionnement';

  @override
  String get simWatchNoFix => 'Pas encore de position GPS';

  @override
  String get simWatchPosition => 'Position';

  @override
  String get simWatchSpeed => 'Vitesse';

  @override
  String get simWatchSatellites => 'Satellites';

  @override
  String get simWatchAltitude => 'Altitude';

  @override
  String get simWatchBaroAltitude => 'Altitude barométrique';

  @override
  String get simWatchAscent => 'Montée';

  @override
  String get simWatchDescent => 'Descente';

  @override
  String get simWatchFixAge => 'Âge de la position';

  @override
  String simWatchSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get sessionLoadError => 'Impossible de charger les séances.';

  @override
  String get sessionDetailLoadError =>
      'Impossible de charger ce plan de séance.';

  @override
  String get gymEditorRemoveExerciseTitle => 'Supprimer l\'exercice ?';

  @override
  String get gymEditorRemoveExerciseBody =>
      'Cet exercice et toutes ses séries seront supprimés de cette séance.';

  @override
  String get gymEditorRemoveExerciseConfirm => 'Supprimer';

  @override
  String get eventSubmitRunsLoadError =>
      'Impossible de charger vos courses récentes.';

  @override
  String get racesCouldNotOpenLink => 'Impossible d\'ouvrir ce lien.';

  @override
  String get prefsHrZonesClearTitle =>
      'Effacer les zones de fréquence cardiaque ?';

  @override
  String get prefsHrZonesClearBody =>
      'Vos cinq zones personnalisées seront effacées.';

  @override
  String get prefsHrZonesClearConfirm => 'Effacer';

  @override
  String get signInRequiredMessage =>
      'Connectez-vous pour utiliser cette fonctionnalité.';

  @override
  String get signInRequiredAction => 'Se connecter';

  @override
  String get backendUnavailableMessage =>
      'Impossible de joindre le serveur pour le moment. Les fonctionnalités en ligne sont indisponibles.';

  @override
  String get feedSignedOutMessage =>
      'Connectez-vous pour voir les courses des personnes que vous suivez.';

  @override
  String ttsPaceAlertSpeedUpByKm(int sec) {
    return 'Accélère de $sec secondes par kilomètre';
  }

  @override
  String ttsPaceAlertSpeedUpByMi(int sec) {
    return 'Accélère de $sec secondes par mile';
  }

  @override
  String ttsPaceAlertSlowDownByKm(int sec) {
    return 'Ralentis de $sec secondes par kilomètre';
  }

  @override
  String ttsPaceAlertSlowDownByMi(int sec) {
    return 'Ralentis de $sec secondes par mile';
  }

  @override
  String ttsCutoffCatchUp(String distance, String pace) {
    return 'Prochaine barrière horaire dans $distance. Il te faut $pace pour y arriver.';
  }

  @override
  String get ttsCutoffUnreachable =>
      'Prochaine barrière horaire : le délai est dépassé.';

  @override
  String ttsMarkerAheadOfPlan(String label, String time) {
    return '$label : $time d\'avance sur le plan';
  }

  @override
  String ttsMarkerBehindPlan(String label, String time) {
    return '$label : $time de retard sur le plan';
  }

  @override
  String ttsMarkerOnPlan(String label) {
    return '$label : dans les temps';
  }

  @override
  String ttsPhaseStart(int index, int total, String phrase) {
    return 'Phase $index sur $total. $phrase';
  }

  @override
  String get ttsPhaseHoldBack => 'Retiens-toi. Reste maîtrisé.';

  @override
  String get ttsPhaseSettle => 'Installe-toi sur ton allure cible.';

  @override
  String get ttsPhaseRace =>
      'C\'est le moment de courir. Donne ce qu\'il te reste.';

  @override
  String get ttsPhaseEven => 'Garde un effort régulier.';

  @override
  String ttsPhaseTargetPace(String pace) {
    return 'Objectif : $pace.';
  }

  @override
  String get prefsVoiceCueTypesLabel => 'Annonces vocales';

  @override
  String get prefsCueSplits => 'Intermédiaires';

  @override
  String get prefsCueSplitsSubtitle =>
      'Ton allure (ou vitesse) à chaque passage d\'un repère de split';

  @override
  String get prefsCueSplitsInfo =>
      'Annonce un bref résumé chaque fois que tu termines un split (règle la distance sous Intervalle de split). Utilise Annonce des splits pour choisir l\'allure du split, l\'allure moyenne ou les deux. Exemple : « 1 kilomètre. Allure, 5 minutes 30 secondes au kilomètre. »';

  @override
  String get prefsCueStartFinish => 'Départ et arrivée';

  @override
  String get prefsCueStartFinishSubtitle =>
      '« Course démarrée » au départ, et un résumé à l\'arrivée';

  @override
  String get prefsCueStartFinishInfo =>
      'Confirme le départ de la course et lit ta distance et ton temps à l\'arrêt. Exemple : « Course terminée. 10,0 kilomètres en 52 minutes. »';

  @override
  String get prefsCueOffRoute => 'Hors itinéraire';

  @override
  String get prefsCueOffRouteSubtitle =>
      'Un avertissement quand tu t\'écartes de l\'itinéraire suivi';

  @override
  String get prefsCueOffRouteInfo =>
      'Fonctionne seulement si tu démarres une course avec un itinéraire enregistré. T\'avertit dès que tu t\'en écartes pour te remettre sur la bonne voie. Exemple : « Hors itinéraire. »';

  @override
  String get prefsCuePaceAlerts => 'Alertes d\'écart d\'allure';

  @override
  String get prefsCuePaceAlertsSubtitle =>
      '« Accélère » / « ralentis » quand tu t\'écartes de ton allure cible';

  @override
  String get prefsCuePaceAlertsInfo =>
      'Nécessite une allure cible. Quand tu t\'en écartes de plus de 30 secondes environ, ceci t\'indique dans quel sens ajuster et de combien. Exemple : « Accélère de 8 secondes. »';

  @override
  String get prefsCueWorkoutSteps => 'Étapes de séance';

  @override
  String get prefsCueWorkoutStepsSubtitle =>
      'Annonce chaque étape d\'une séance structurée à son début';

  @override
  String get prefsCueWorkoutStepsInfo =>
      'Actif seulement pendant une séance structurée (une séance de plan ou une séance d\'intervalles). Annonce chaque étape et son objectif pour que tu gardes les yeux devant. Exemple : « Répétition 3 sur 5. 400 mètres à 4 minutes 30 secondes au kilomètre. »';

  @override
  String get prefsCueCutoffCatchUp => 'Rattrapage de barrière';

  @override
  String get prefsCueCutoffCatchUpSubtitle =>
      'L\'allure nécessaire pour une barrière horaire menacée';

  @override
  String get prefsCueCutoffCatchUpInfo =>
      'Actif seulement sur un itinéraire avec des barrières horaires. Si l\'une est menacée, il lit la distance qui t\'en sépare et l\'allure qui permet encore de la tenir. Exemple : « 2 kilomètres jusqu\'à la barrière. 6 minutes au kilomètre. »';

  @override
  String get prefsCueMarkerTargets => 'Repères du parcours';

  @override
  String get prefsCueMarkerTargetsSubtitle =>
      'Si tu es en avance ou en retard sur le plan à chaque repère';

  @override
  String get prefsCueMarkerTargetsInfo =>
      'Actif seulement sur un itinéraire dont les repères portent des temps cibles. À chaque passage, il te dit si tu es en avance ou en retard, et de combien. Exemple : « Ravitaillement 2 : 45 secondes d\'avance sur le plan. »';

  @override
  String get prefsCuePhaseTransitions => 'Phases de course';

  @override
  String get prefsCuePhaseTransitionsSubtitle =>
      'Un repère au début de chaque phase de ta stratégie de course';

  @override
  String get prefsCuePhaseTransitionsInfo =>
      'Actif seulement quand tu choisis une stratégie de course. Annonce chaque phase et son intention à son début. Exemple : « Phase 2 sur 3. Installe-toi sur ton allure cible. »';

  @override
  String get prefsCueGuidedRun => 'Courses guidées';

  @override
  String get prefsCueGuidedRunSubtitle =>
      'Le script du coach d\'une course guidée choisie avant le départ';

  @override
  String get prefsCueGuidedRunInfo =>
      'Actif seulement quand tu choisis une course guidée dans l\'onglet Course avant de partir. Annonce chaque consigne du script quand tu atteins son repère. Exemple : « Cinq minutes. Installe-toi sur une allure que tu tiendrais toute la journée. »';

  @override
  String get runGuidedRun => 'Course guidée';

  @override
  String get runGuidedRunNone => 'Aucune course guidée';

  @override
  String runGuidedRunOption(int minutes, String subtitle) {
    return '$minutes min · $subtitle';
  }

  @override
  String get runRaceStrategy => 'Stratégie de course';

  @override
  String get runStrategyNone => 'Aucune stratégie';

  @override
  String get runStrategyTenTenTen => '10-10-10';

  @override
  String get runStrategyNegativeSplit => 'Negative split';

  @override
  String get runStrategyEven => 'Allure régulière';

  @override
  String get runStrategyTenTenTenHint => 'Se retenir, se caler, finir fort';

  @override
  String get runStrategyNegativeSplitHint =>
      'Première moitié contrôlée, seconde plus rapide';

  @override
  String get runStrategyEvenHint =>
      'Une allure constante du départ à l\'arrivée';

  @override
  String get runStrategyGoalTime => 'Temps visé';

  @override
  String get runStrategyDistance => 'Distance';

  @override
  String get runStrategyNeedsDistance =>
      'Choisis un itinéraire ou saisis une distance pour activer les phases';

  @override
  String get runStrategyInvalidGoal =>
      'Saisissez le temps cible au format h:mm:ss';

  @override
  String runPhaseChip(int index, int total, String intent) {
    return 'Phase $index/$total — $intent';
  }

  @override
  String get phaseIntentHoldBack => 'Retenue';

  @override
  String get phaseIntentSettle => 'Calage';

  @override
  String get phaseIntentRace => 'Course';

  @override
  String get phaseIntentEven => 'Régulier';

  @override
  String routeMarkerTargetChip(String time) {
    return 'Objectif $time';
  }

  @override
  String get routeMarkerTargetLabel => 'Temps visé';

  @override
  String get routeMarkerTargetHelper => 'Heures : minutes : secondes';

  @override
  String get routeMarkerTargetInvalid =>
      'Saisis le temps visé au format h:mm:ss';

  @override
  String get routeMarkerOfficialBadge => 'Propriétaire du parcours';

  @override
  String get routeMarkerDistanceAlongLabel => 'Distance le long du parcours';

  @override
  String get routeMarkerDistanceInvalid =>
      'Saisis une distance valide le long du parcours.';

  @override
  String get watchScreensTitle => 'Écrans de la montre';

  @override
  String get watchScreensAction => 'Composer les écrans de la montre';

  @override
  String watchScreensCount(int count, int max) {
    return '$count écran(s) sur $max';
  }

  @override
  String get watchScreensEmptyTitle => 'Aucun écran composé';

  @override
  String get watchScreensEmptyBody =>
      'La montre parcourt ses pages intégrées tant que vous n\'en composez aucun. Ajoutez un écran pour choisir ce qu\'il affiche.';

  @override
  String get watchScreensAdd => 'Ajouter un écran';

  @override
  String watchScreensFull(int max) {
    return 'Une montre accepte au plus $max écrans.';
  }

  @override
  String watchScreensHeading(int index) {
    return 'Écran $index';
  }

  @override
  String get watchScreensLayout => 'Disposition';

  @override
  String watchScreensSlot(int index) {
    return 'Emplacement $index';
  }

  @override
  String get watchScreensMoveUp => 'Monter';

  @override
  String get watchScreensMoveDown => 'Descendre';

  @override
  String get watchScreensRemove => 'Supprimer l\'écran';

  @override
  String watchScreensRemoveTitle(int index) {
    return 'Supprimer l\'écran $index ?';
  }

  @override
  String watchScreensRemoveBody(int count) {
    return 'Ses $count mesure(s) disparaîtront avec lui.';
  }

  @override
  String get watchScreensRemoveConfirm => 'Supprimer';

  @override
  String get watchScreensCancel => 'Annuler';

  @override
  String watchScreensShrinkTitle(int count) {
    return 'Abandonner $count mesure(s) ?';
  }

  @override
  String watchScreensShrinkBody(String layout, int slots, String dropped) {
    return 'Une disposition $layout affiche $slots emplacement(s), donc $dropped ne serait plus affiché.';
  }

  @override
  String get watchScreensShrinkConfirm => 'Changer de disposition';

  @override
  String get watchScreensPushAction => 'Envoyer les écrans à la montre';

  @override
  String watchScreensPushed(int count) {
    return '$count écran(s) envoyé(s) à la montre';
  }

  @override
  String get watchScreensCleared => 'Écrans composés effacés sur la montre';

  @override
  String watchScreensPushFailed(String error) {
    return 'Échec de l\'envoi des écrans : $error';
  }

  @override
  String get watchScreensLoadFailed =>
      'Impossible de lire les écrans enregistrés.';

  @override
  String get watchScreensStartOver => 'Recommencer';

  @override
  String get watchLayoutSingle => 'Simple';

  @override
  String get watchLayoutDuo => 'Duo';

  @override
  String get watchLayoutTrio => 'Trio';

  @override
  String get watchMetricElapsed => 'Temps écoulé';

  @override
  String get watchMetricDistance => 'Distance';

  @override
  String get watchMetricAvgPace => 'Allure moyenne';

  @override
  String get watchMetricLapElapsed => 'Temps du tour';

  @override
  String get watchMetricHeartRate => 'Fréquence cardiaque';

  @override
  String get watchMetricPacerDelta => 'Écart au meneur d\'allure';

  @override
  String get watchMetricGuidedRunRemaining => 'Consigne de course guidée';

  @override
  String get watchMetricWorkoutRemaining => 'Étape de séance';

  @override
  String get watchMetricRacePrediction => 'Prévision de course';

  @override
  String get watchMetricCutoffMargin => 'Marge avant barrière';

  @override
  String get watchMetricTrainingStress => 'Charge d\'entraînement';

  @override
  String get watchMetricRoadbookNext => 'Prochain ravitaillement';

  @override
  String get watchMetricFuelCarbs => 'Glucides';

  @override
  String get watchMetricGearWear => 'Usure de l\'équipement';

  @override
  String get watchMetricEasyPace => 'Allure facile';

  @override
  String get watchMetricVo2Max => 'VO2 max';

  @override
  String get watchMetricAltitude => 'Altitude';

  @override
  String get watchMetricDistanceToStart => 'Distance jusqu\'au départ';

  @override
  String get watchMetricDaylightCountdown => 'Lumière du jour restante';

  @override
  String get watchMetricWaypointDistance => 'Distance au point de repère';

  @override
  String get watchMetricClimbGain => 'Dénivelé positif';

  @override
  String get watchMetricRecapDistance => 'Distance de l\'année';

  @override
  String get watchMetricCurrentStreak => 'Série en cours';

  @override
  String get watchMetricSyncedMovingTime => 'Temps en mouvement';

  @override
  String get watchMetricPrAge => 'Ancienneté du record';

  @override
  String get watchMetricPlanReplanChanges => 'Modifications du replanning';

  @override
  String get watchMetricPlanAdaptiveChanges => 'Modifications adaptatives';

  @override
  String get watchMetricReadinessScore => 'État de forme';

  @override
  String get watchMetricGoalPercent => 'Progression de l\'objectif';

  @override
  String get watchMetricTurnCueDistance => 'Prochain virage';

  @override
  String get watchMetricRouteSimplifyDistance => 'Distance du parcours';

  @override
  String get watchMetricAutoEffortMatched => 'Segments détectés';

  @override
  String get watchMetricRouteElevTotal => 'Dénivelé du parcours';

  @override
  String get watchMetricRaceDayDays => 'Jours avant la course';

  @override
  String get watchMetricSleepBudget => 'Budget de sommeil';

  @override
  String get watchMetricTimerRemaining => 'Minuteur';

  @override
  String get watchMetricBackyardBell => 'Compte à rebours de la cloche';

  @override
  String get watchMetricStormDelta => 'Tendance de tempête';

  @override
  String get watchMetricGap => 'Allure corrigée de la pente';

  @override
  String get watchMetricFluid => 'Liquide';

  @override
  String get watchLiveTitle => 'Suivre la course de la montre';

  @override
  String get watchLiveTileSubtitle =>
      'Relayer la position de votre montre vers un lien en direct';

  @override
  String get watchLiveIntro =>
      'Tant que cet écran est ouvert, votre téléphone relaie la position de la montre aux spectateurs environ une fois par seconde. Gardez le téléphone sur vous et à portée Bluetooth : quitter cet écran arrête le relais.';

  @override
  String get watchLiveStateOff => 'Non connecté';

  @override
  String get watchLiveStateConnecting => 'Connexion';

  @override
  String get watchLiveStateLive => 'En direct';

  @override
  String get watchLiveStateGap => 'Interruption';

  @override
  String get watchLiveStateLost => 'Abandon';

  @override
  String get watchLiveDetailOff => 'Rien n\'est envoyé.';

  @override
  String get watchLiveDetailSearching => 'Recherche de votre montre…';

  @override
  String get watchLiveDetailAwaitingFix =>
      'Connecté — en attente de la première position de la montre.';

  @override
  String get watchLiveDetailGap =>
      'les spectateurs voient la dernière position comme différée, pas comme actuelle';

  @override
  String get watchLiveDetailLost =>
      'Votre montre est éteinte ou hors de portée. Plus rien n\'est envoyé.';

  @override
  String get watchLiveStart => 'Démarrer le relais';

  @override
  String get watchLiveStop => 'Arrêter le relais';

  @override
  String get watchLiveRetry => 'Réessayer';

  @override
  String get watchLiveShare => 'Partager le lien en direct';

  @override
  String get watchLiveStartFailed =>
      'Impossible de démarrer la diffusion en direct — rien n\'est partagé.';

  @override
  String get watchLiveSyncAction => 'Synchroniser les courses de la montre';

  @override
  String get watchLiveSyncSubtitle =>
      'Récupère les courses enregistrées sur la montre. Le relais est suspendu pendant ce temps.';

  @override
  String pendingSyncOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count modifications enregistrées sur cet appareil — synchronisation dès le retour en ligne',
      one:
          '$count modification enregistrée sur cet appareil — synchronisation dès le retour en ligne',
    );
    return '$_temp0';
  }

  @override
  String pendingSyncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifications n\'ont pas été synchronisées',
      one: '$count modification n\'a pas été synchronisée',
    );
    return '$_temp0';
  }

  @override
  String get pendingSyncRetry => 'Réessayer';

  @override
  String get photoOpen => 'Ouvrir la photo';

  @override
  String get photoLightboxClose => 'Fermer la photo';

  @override
  String get photoLightboxLoading => 'Chargement de la photo…';

  @override
  String get photoLightboxError => 'Cette photo n\'a pas pu être chargée.';

  @override
  String get photoLightboxErrorHint => 'Touchez n\'importe où pour fermer.';

  @override
  String get commonLoading => 'Chargement…';

  @override
  String get commonMore => 'Plus';

  @override
  String get undoAction => 'Annuler';

  @override
  String get undoDismiss => 'Fermer';

  @override
  String get undoHint =>
      'L’annulation reste possible pendant un court instant.';

  @override
  String get undoRestored => 'Rétabli';

  @override
  String get prefsUndoWindow => 'Délai d’annulation';

  @override
  String get prefsUndoWindow8s => '8 secondes';

  @override
  String get prefsUndoWindow30s => '30 secondes';

  @override
  String get prefsUndoWindowManual => 'Jusqu’à ce que je le ferme';

  @override
  String undoDismissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notifications supprimées',
      one: 'Notification supprimée',
    );
    return '$_temp0';
  }

  @override
  String get routeConditionsRemoved => 'Signalement supprimé';

  @override
  String get gearWearLogRemoved => 'Observation supprimée';

  @override
  String nutritionEntryRemoved(String item) {
    return '$item supprimé';
  }

  @override
  String get runSocialCommentRemoved => 'Commentaire supprimé';

  @override
  String get routeDetailReviewRemoved => 'Avis supprimé';

  @override
  String get routeMarkerRemoved => 'Repère supprimé';

  @override
  String get roadbookNeedsRouteLine =>
      'Ajoutez au moins deux points à cet itinéraire pour créer un roadbook.';

  @override
  String get settingsGearUnavailable =>
      'L\'équipement n\'est pas disponible dans cette version';

  @override
  String get loadRampTitle => 'Progression de charge';

  @override
  String get loadRampRatioCaption =>
      'cette semaine vs votre moyenne sur 4 semaines';

  @override
  String get loadRampAcuteLabel => '7 derniers jours';

  @override
  String get loadRampChronicLabel => 'Moyenne hebdo (4 semaines)';

  @override
  String get loadRampBandLow => 'Faible';

  @override
  String get loadRampBandOptimal => 'Optimale';

  @override
  String get loadRampBandElevated => 'Élevée';

  @override
  String get loadRampBandHigh => 'Forte';

  @override
  String get loadRampMeaningLow =>
      'Vous courez sous votre base récente. Parfait pour un affûtage ou une semaine de récupération ; durable, c\'est du désentraînement.';

  @override
  String get loadRampMeaningOptimal =>
      'Votre semaine se situe dans la plage qui protège le mieux des blessures. Continuez à progresser à ce rythme.';

  @override
  String get loadRampMeaningElevated =>
      'Vous avez augmenté plus vite que votre base récente ne le supporte. Stabilisez cette semaine plutôt que d\'en rajouter.';

  @override
  String get loadRampMeaningHigh =>
      'C\'est une hausse brutale par rapport à votre base récente — le schéma le plus associé aux blessures. Envisagez une semaine plus légère.';

  @override
  String get loadRampTrendRamping => 'Votre charge augmente.';

  @override
  String get loadRampTrendSteady => 'Votre charge reste stable.';

  @override
  String get loadRampTrendTapering => 'Votre charge diminue.';

  @override
  String get comebackTitle => 'Retour après une coupure';

  @override
  String get comebackVerdictEasingIn => 'Reprise en douceur';

  @override
  String get comebackVerdictSteep => 'Grosse première semaine';

  @override
  String comebackLayoff(int weeks) {
    return '$weeks semaines sans courir';
  }

  @override
  String get comebackShareCaption =>
      'cette semaine par rapport à votre semaine moyenne avant la coupure';

  @override
  String get comebackMeaningEasingIn =>
      'Cette semaine reste nettement en dessous des semaines que vous couriez avant la coupure. Reconstruire progressivement à partir d’ici, c’est ce qui rend le retour durable.';

  @override
  String get comebackMeaningSteep =>
      'Cette semaine dépasse déjà la moitié de ce que vous couriez avant la coupure. Votre corps a perdu la base qui rendait ces semaines routinières : une semaine plus courte maintenant coûte bien moins qu’une rechute plus tard.';

  @override
  String get comebackThisWeekLabel => '7 derniers jours';

  @override
  String get comebackBaseLabel => 'Moyenne hebdomadaire avant la coupure';

  @override
  String get comebackFootnote =>
      'Votre courbe de charge d’entraînement revient dès que vous enchaînez à nouveau quelques semaines régulières.';

  @override
  String get segmentCatalogueTitle => 'Segments célèbres';

  @override
  String get segmentCatalogueIntro =>
      'Des montées, des ponts et des boucles de parc sélectionnés dans le monde entier. Cours-en un et ton temps rejoint automatiquement son classement.';

  @override
  String get segmentCatalogueSearchLabel => 'Rechercher';

  @override
  String get segmentCatalogueSearchHint => 'Nom ou lieu';

  @override
  String get segmentCatalogueRegion => 'Région';

  @override
  String get segmentCatalogueAllRegions => 'Toutes les régions';

  @override
  String get segmentCatalogueSurface => 'Surface';

  @override
  String get segmentCatalogueAllSurfaces => 'Toutes les surfaces';

  @override
  String get segmentCatalogueSort => 'Trier';

  @override
  String get segmentCatalogueSortName => 'Nom';

  @override
  String get segmentCatalogueSortShortest => 'Les plus courts d\'abord';

  @override
  String get segmentCatalogueSortLongest => 'Les plus longs d\'abord';

  @override
  String get segmentCatalogueSortClimb => 'Plus de dénivelé';

  @override
  String segmentCatalogueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segments',
      one: '$count segment',
    );
    return '$_temp0';
  }

  @override
  String get segmentCatalogueLoadFailed =>
      'Impossible de charger le catalogue de segments.';

  @override
  String get segmentCatalogueEmpty =>
      'Aucun segment célèbre dans le catalogue pour l\'instant.';

  @override
  String get segmentCatalogueNoMatches =>
      'Aucun segment ne correspond à ces filtres — essaie de les élargir.';

  @override
  String get segmentCatalogueBrowseAll => 'Tout parcourir';

  @override
  String get segmentCatalogueNotFoundTitle => 'Segment introuvable';

  @override
  String get segmentCatalogueNotFoundBody =>
      'Ce segment n\'est pas au catalogue ou a été retiré.';

  @override
  String get segmentCatalogueDetailFailedTitle =>
      'Impossible de charger ce segment';

  @override
  String get segmentCatalogueDetailFailedBody =>
      'Vérifie ta connexion et réessaie.';

  @override
  String get segmentCatalogueStatDistance => 'Distance';

  @override
  String get segmentCatalogueStatElevation => 'Dénivelé positif';

  @override
  String get segmentCatalogueStatSurface => 'Surface';

  @override
  String get segmentCatalogueLeaderboard => 'Classement';

  @override
  String get runSurfaceTabSegments => 'Segments';

  @override
  String rateLimitCreateClub(String wait) {
    return 'Vous créez des clubs trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitCreateRoute(String wait) {
    return 'Vous créez des parcours trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitCreateReport(String wait) {
    return 'Vous envoyez des signalements trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitCreateChallenge(String wait) {
    return 'Vous créez des défis trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitAdoptPlan(String wait) {
    return 'Vous adoptez des plans trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitAdoptSessionPlan(String wait) {
    return 'Vous adoptez des plans de séance trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitAdoptGymRoutine(String wait) {
    return 'Vous adoptez des routines de renfo trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitPublishRoutine(String wait) {
    return 'Vous publiez des routines trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitSendMessage(String wait) {
    return 'Vous envoyez des messages trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitGeneric(String wait) {
    return 'Vous faites cela trop rapidement — veuillez patienter $wait et réessayer.';
  }

  @override
  String rateLimitWaitSeconds(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n secondes',
      one: '1 seconde',
    );
    return '$_temp0';
  }

  @override
  String rateLimitWaitMinutes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get rateLimitWaitSoon => 'un instant';

  @override
  String get challengesCreate => 'Créer un défi';

  @override
  String get challengesTitleLabel => 'Titre';

  @override
  String get challengesDescriptionLabel => 'Description';

  @override
  String get challengesMetricLabel => 'Mesure';

  @override
  String get challengesScopeLabel => 'Type';

  @override
  String get challengesGoalOptional => 'Objectif (facultatif)';

  @override
  String get challengesActivityTypeLabel => 'Activité';

  @override
  String get challengesActivityAny => 'Toutes';

  @override
  String get challengesClubLabel => 'Club';

  @override
  String get challengesClubNone => 'Ouvert (tout le monde)';

  @override
  String get challengesStartLabel => 'Début';

  @override
  String get challengesEndLabel => 'Fin';

  @override
  String get challengesScopeIndividual => 'Individuel';

  @override
  String get challengesScopeClubVsClub => 'Club contre club';

  @override
  String get challengesScopeGroupGoal => 'Objectif de groupe';

  @override
  String get challengesSuffixHours => 'h';

  @override
  String get challengesSuffixActivities => 'activités';

  @override
  String get challengesSuffixDays => 'jours';

  @override
  String challengesGoalPreview(String value) {
    return 'Les participants voient $value';
  }

  @override
  String challengesGoalStreakCeiling(int n) {
    return 'Cette période contient au maximum $n jours actifs.';
  }

  @override
  String get challengesErrTitle => 'Donnez un titre au défi.';

  @override
  String get challengesErrGoal => 'Objectif : saisissez un nombre positif';

  @override
  String get challengesErrWindow => 'La fin doit être postérieure au début.';

  @override
  String limitsWeightOutOfRange(String min, String max, String unit) {
    return 'Indique un poids entre $min et $max $unit.';
  }

  @override
  String limitsHeightOutOfRange(String min, String max) {
    return 'Indique une taille entre $min et $max cm.';
  }

  @override
  String limitsServingsOutOfRange(String min, String max) {
    return 'Indique un nombre de portions entre $min et $max.';
  }

  @override
  String runDetailGuidedRun(String title) {
    return 'Course guidée : $title';
  }

  @override
  String get runDetailGuidedRunUnavailable =>
      'Course guidée absente de la bibliothèque';

  @override
  String get guidedRunUseThisRun => 'Utiliser cette course';
}
