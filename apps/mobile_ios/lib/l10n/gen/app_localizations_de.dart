// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get trustedContactsClearedBanner => 'Vertrauenskontakte gelöscht.';

  @override
  String trustedContactsSavedBanner(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Vertrauenskontakte gespeichert.',
      one: '1 Vertrauenskontakt gespeichert.',
    );
    return '$_temp0';
  }

  @override
  String trustedContactsSaveFailedBanner(Object error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get trustedContactsTitle => 'Vertrauenskontakte';

  @override
  String trustedContactsIntro(Object max) {
    return 'Lege einen oder mehrere Vertrauenskontakte fest. Das Grundgerüst speichert die Liste mit deinem Konto, damit die geplanten Funktionen für „überfällige Läufe“ und den Notfallknopf wissen, wohin Benachrichtigungen gehen sollen. Bis zu $max.';
  }

  @override
  String get trustedContactsAddButton => 'Kontakt hinzufügen';

  @override
  String get trustedContactsSavingButton => 'Wird gespeichert…';

  @override
  String get trustedContactsSaveButton => 'Speichern';

  @override
  String get trustedContactsNameLabel => 'Name';

  @override
  String get trustedContactsNameHint => 'z. B. Alex Chen';

  @override
  String get trustedContactsPhoneLabel => 'Telefon';

  @override
  String get trustedContactsPhoneHint => '+1 555 123 4567';

  @override
  String get trustedContactsEmailLabel => 'E-Mail';

  @override
  String get trustedContactsEmailHint => 'alex@example.com';

  @override
  String get trustedContactsRelationshipLabel => 'Beziehung';

  @override
  String get trustedContactsRelationshipHint =>
      'Partner / Elternteil / Laufpartner';

  @override
  String get trustedContactsRemoveButton => 'Entfernen';

  @override
  String get clubInviteEnterCodeError =>
      'Gib den Einladungscode aus deinem Link ein.';

  @override
  String get clubInviteJoinedBanner => 'Du bist dem Club beigetreten.';

  @override
  String get clubInviteTitle => 'Club beitreten';

  @override
  String get clubInviteIntro =>
      'Füge den Einladungscode ein, den dein Club-Admin mit dir geteilt hat.';

  @override
  String get clubInviteCodeLabel => 'Einladungscode';

  @override
  String get clubInviteJoinButton => 'Beitreten';

  @override
  String recapShareHeadline(Object year) {
    return 'Mein Laufjahr $year:';
  }

  @override
  String recapShareTotals(Object total, Object count) {
    return '$total über $count Läufe';
  }

  @override
  String recapShareLongestRun(Object distance) {
    return 'Längster Lauf: $distance';
  }

  @override
  String recapShareBestStreak(Object days) {
    return 'Beste Serie: $days Tage';
  }

  @override
  String recapShareSubject(Object year) {
    return 'Rückblick $year';
  }

  @override
  String get recapTitle => 'Laufjahr';

  @override
  String get recapShareTooltip => 'Rückblick teilen';

  @override
  String get recapPrevYear => 'Vorheriges Jahr';

  @override
  String get recapNextYear => 'Nächstes Jahr';

  @override
  String recapNoRunsForYear(Object year) {
    return 'Keine Läufe für den Rückblick $year.';
  }

  @override
  String recapNoRunsYet(Object year) {
    return 'Noch keine Läufe in $year. Zeichne einen auf, um deinen Rückblick zu sehen.';
  }

  @override
  String recapAcrossRuns(Object count, Object runWord) {
    return 'über $count $runWord';
  }

  @override
  String get recapLongestRunLabel => 'Längster Lauf';

  @override
  String get recapBestStreakLabel => 'Beste Serie';

  @override
  String recapStreakDays(Object days, Object dayWord) {
    return '$days $dayWord';
  }

  @override
  String get recapTopWeekLabel => 'Beste Woche';

  @override
  String get recapUniqueRoutesLabel => 'Verschiedene Routen';

  @override
  String get recapEarliestStartLabel => 'Frühester Start';

  @override
  String get recapLatestStartLabel => 'Spätester Start';

  @override
  String get routePickerTitle => 'Route wählen';

  @override
  String get routePickerNoRoute => 'Keine Route';

  @override
  String get routePickerClearSearchTooltip => 'Suche löschen';

  @override
  String get routePickerSearchHint => 'Routen nach Namen suchen…';

  @override
  String get routePickerEmptyNoRoutes => 'Noch keine Routen gespeichert';

  @override
  String routePickerEmptyNoMatch(Object query) {
    return 'Keine Routen passen zu „$query“';
  }

  @override
  String get routePickerStarredHeader => 'Markiert';

  @override
  String get routePickerAllRoutesHeader => 'Alle Routen';

  @override
  String importStatusImported(Object count, Object label) {
    return '$count Läufe aus $label importiert';
  }

  @override
  String importStatusImportedWithErrors(Object count, Object errors) {
    return '$count Läufe importiert ($errors fehlgeschlagen)';
  }

  @override
  String importStatusNoGpsNote(Object base, Object label) {
    return '$base. $label hat keine Routendaten, daher haben diese Läufe keine Karte.';
  }

  @override
  String importHealthRequestingPermission(Object label) {
    return '$label-Berechtigung wird angefordert...';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return '$label-Berechtigung verweigert';
  }

  @override
  String get importHealthReadingWorkouts => 'Workouts werden gelesen...';

  @override
  String importHealthFailed(Object label, Object error) {
    return '$label-Import fehlgeschlagen: $error';
  }

  @override
  String get importStatusSavingLocally => 'Wird lokal gespeichert...';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return '$count Duplikat(e) übersprungen, bereits aus einer anderen Quelle importiert';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return '$done von $total lokal gespeichert';
  }

  @override
  String get importStatusSyncingToCloud =>
      'Wird in die Cloud synchronisiert...';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return '$done von $total synchronisiert';
  }

  @override
  String get importStatusReadingCsv => 'CSV wird gelesen...';

  @override
  String importCsvFailed(Object error) {
    return 'CSV-Import fehlgeschlagen: $error';
  }

  @override
  String get importStatusRestoringBackup => 'Backup wird wiederhergestellt...';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return '$runs Läufe · $tracks Tracks · $routes Routen wiederhergestellt';
  }

  @override
  String importBackupFailed(Object error) {
    return 'Backup-Wiederherstellung fehlgeschlagen: $error';
  }

  @override
  String get importStatusReadingExport => 'Export wird gelesen...';

  @override
  String importStravaFailed(Object error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get importTitle => 'Läufe importieren';

  @override
  String get importStravaCardTitle => 'Strava';

  @override
  String get importStravaCardSubtitle =>
      'Importiere jeden Lauf aus einem Strava-Datenexport-ZIP';

  @override
  String get importStravaHowToHeader => 'So erhältst du deinen Strava-Export:';

  @override
  String get importStravaHowToSteps =>
      '1. Öffne Strava → Einstellungen → Mein Konto\n2. Scrolle zu „Konto herunterladen oder löschen“\n3. Tippe auf „Erste Schritte“ → „Archiv anfordern“\n4. In einigen Stunden erhältst du eine E-Mail mit einem Download-Link\n5. Lade die .zip-Datei herunter und tippe unten auf Importieren';

  @override
  String get importStravaButton => 'Strava-ZIP importieren';

  @override
  String importHealthButton(Object label) {
    return 'Aus $label importieren';
  }

  @override
  String get importCsvCardTitle => 'CSV';

  @override
  String get importCsvCardSubtitle =>
      'Eine aus den Einstellungen exportierte CSV erneut importieren — nur Läufe, kein GPS';

  @override
  String get importCsvCardDescription =>
      'Jede CSV-Zeile wird zu einem manuellen Lauf (Datum, Distanz, Dauer, Quelle). Der Karten-Track ist nicht in der CSV enthalten, daher haben importierte Läufe keine Routenlinie.';

  @override
  String get importCsvButton => 'CSV importieren';

  @override
  String get importBackupCardTitle => 'Vollständiges Backup-ZIP';

  @override
  String get importBackupCardSubtitle =>
      'Läufe, Routen und GPS-Tracks aus einer Backup-Datei wiederherstellen';

  @override
  String get importBackupCardDescription =>
      'Verlustfreier Roundtrip. Funktioniert ohne Anmeldung — wiederhergestellte Läufe werden beim nächsten Anmelden mit deinem Konto synchronisiert. Erstelle ein Backup unter Einstellungen → Vollständiges Backup.';

  @override
  String get importBackupButton => 'Backup-ZIP wiederherstellen';

  @override
  String get importErrorsHeader => 'Fehler';

  @override
  String importErrorsMore(Object count) {
    return '... und $count weitere';
  }

  @override
  String get importHealthSubtitleIos =>
      'Hole Workouts, die du auf der Apple Watch, in Nike Run Club, Strava und anderen Apps aufgezeichnet hast, die in Apple Health schreiben';

  @override
  String get importHealthSubtitleAndroid =>
      'Hole Workouts aus Google Fit, Samsung Health, Garmin, Fitbit und jeder anderen Health-Connect-App';

  @override
  String get importHealthDescriptionIos =>
      'Liest Workout-Zusammenfassungen (Datum, Distanz, Dauer, Typ) des letzten Jahres. Apple Health gibt von Drittanbieter-Apps aufgezeichnete GPS-Routen nicht preis — so importierte Läufe haben keinen Karten-Track.';

  @override
  String get importHealthDescriptionAndroid =>
      'Liest Workout-Zusammenfassungen (Datum, Distanz, Dauer, Typ) des letzten Jahres. GPS-Routen werden von Health Connect nicht bereitgestellt — so importierte Läufe haben keinen Karten-Track.';

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'Follow konnte nicht aktualisiert werden: $error';
  }

  @override
  String get peopleSearchHint => 'Läufer nach Namen suchen';

  @override
  String get peopleClearSearchTooltip => 'Suche löschen';

  @override
  String get commonClearSearch => 'Suche löschen';

  @override
  String get commonDismiss => 'Schließen';

  @override
  String get settingsDevicesRemoveOverride => 'Überschreibung entfernen';

  @override
  String get peopleSearchResultsHeader => 'Suchergebnisse';

  @override
  String get peopleSuggestedHeader => 'Für dich vorgeschlagen';

  @override
  String peopleEmptySearchTitle(Object query) {
    return 'Keine Läufer passen zu „$query“';
  }

  @override
  String get peopleEmptySearchBody =>
      'Versuche einen kürzeren oder anderen Namen. Anzeigenamen sind öffentlich; Personen, die noch keinen festgelegt haben, erscheinen hier nicht.';

  @override
  String get peopleEmptySuggestionsTitle => 'Noch keine Vorschläge';

  @override
  String get peopleEmptySuggestionsBody =>
      'Vorschläge stammen von Personen in Clubs, denen du beigetreten bist. Tritt einem Club bei, um sie hier zu sehen.';

  @override
  String peoplePublicRunCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öffentliche Läufe',
      one: '1 öffentlicher Lauf',
    );
    return '$_temp0';
  }

  @override
  String peopleSharedClubsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gemeinsame Clubs',
      one: '1 gemeinsamer Club',
    );
    return '$_temp0';
  }

  @override
  String get peopleFallbackDisplayName => 'Läufer';

  @override
  String get peopleFollowingButton => 'Folgt';

  @override
  String get peopleFollowButton => 'Folgen';

  @override
  String get readinessCardHeader => 'BEREITSCHAFT';

  @override
  String get readinessBandHigh => 'hoch';

  @override
  String get readinessBandModerate => 'mäßig';

  @override
  String get readinessBandLow => 'niedrig';

  @override
  String get missingMapTilesTitle =>
      'OpenStreetMap-Ersatzkacheln werden verwendet';

  @override
  String get prefsLanguage => 'Sprache';

  @override
  String get prefsLanguageSystem => 'Systemstandard';

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
  String get navHome => 'Start';

  @override
  String get navRun => 'Lauf';

  @override
  String get navHistory => 'Verlauf';

  @override
  String get navSocial => 'Sozial';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navLog => 'Erfassen';

  @override
  String get logA11yLabel => 'Aktivität erfassen';

  @override
  String get navFitness => 'Fitness';

  @override
  String get navYou => 'Du';

  @override
  String get fitnessTabAll => 'Alle';

  @override
  String get fitnessTabRuns => 'Läufe';

  @override
  String get fitnessTabGym => 'Gym';

  @override
  String get fitnessTabNutrition => 'Ernährung';

  @override
  String get fitnessRunsRoutes => 'Routen';

  @override
  String get fitnessRunsPlans => 'Trainingspläne';

  @override
  String get homeAskCoach => 'Coach fragen';

  @override
  String get homeAskCoachSubtitle =>
      'Tipps zu Läufen, Krafttraining und Ernährung';

  @override
  String get youProfileTitle => 'Dein Profil';

  @override
  String get logSheetTitle => 'Erfassen';

  @override
  String get logRun => 'Lauf erfassen';

  @override
  String get logLift => 'Training erfassen';

  @override
  String get logFood => 'Essen erfassen';

  @override
  String get prefsKeepRunPrimary => 'Lauf als primäre Aktion';

  @override
  String get prefsKeepRunPrimarySubtitle =>
      'Mittlere Taste startet einen Lauf; lange drücken für das vollständige Menü';

  @override
  String get bodyMetricsTitle => 'Körperdaten';

  @override
  String get bodyMetricsTileSubtitle => 'Größe, Gewicht & Nährwertziele';

  @override
  String get bodyMetricsConsentTitle => 'Gesundheitsdaten speichern';

  @override
  String get bodyMetricsConsentSubtitle =>
      'Größe und Gewicht sind besondere Gesundheitsdaten. Zum Löschen ausschalten.';

  @override
  String get bodyMetricsHeight => 'Größe';

  @override
  String get bodyMetricsWeight => 'Gewicht';

  @override
  String get bodyMetricsActivityLevel => 'Aktivitätsniveau';

  @override
  String get bodyMetricsGoal => 'Ziel';

  @override
  String get bodyMetricsTargetsHint =>
      'Dient zur Schätzung deiner täglichen Kalorien- und Makroziele.';

  @override
  String get bodyMetricsConsentRequired =>
      'Aktiviere die Speicherung von Gesundheitsdaten, um Größe und Gewicht zu sichern.';

  @override
  String get bodyMetricsWithdrawTitle =>
      'Einwilligung zu Gesundheitsdaten widerrufen?';

  @override
  String get bodyMetricsWithdrawBody =>
      'Dadurch werden deine gespeicherte Größe und dein gesamter Gewichtsverlauf dauerhaft gelöscht. Das kann nicht rückgängig gemacht werden.';

  @override
  String get bodyMetricsWithdrawConfirm => 'Widerrufen & löschen';

  @override
  String get bodyMetricsSaved => 'Gespeichert';

  @override
  String bodyMetricsSaveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get safetyTitle => 'Sicherheitskontakte';

  @override
  String get safetyTileSubtitle =>
      'E-Mail an eine Vertrauensperson, wenn du einen Lauf beendest';

  @override
  String get safetyIntro =>
      'Ein Sicherheitskontakt erhält eine E-Mail, wenn du einen Lauf beendest — auch einen privaten — damit jemand, dem du vertraust, weiß, dass du sicher zurück bist.';

  @override
  String get safetyAddLabel => 'E-Mail des Kontakts';

  @override
  String get safetyAddButton => 'Kontakt hinzufügen';

  @override
  String get safetyAdding => 'Wird hinzugefügt…';

  @override
  String get safetyEmpty => 'Noch keine Sicherheitskontakte.';

  @override
  String get safetyStatusPending => 'Ausstehend — wartet auf Bestätigung';

  @override
  String get safetyStatusConfirmed => 'Bestätigt';

  @override
  String get safetyRemove => 'Entfernen';

  @override
  String get safetyRemoveConfirm => 'Diesen Sicherheitskontakt entfernen?';

  @override
  String safetyAddFailed(String error) {
    return 'Kontakt konnte nicht hinzugefügt werden: $error';
  }

  @override
  String get safetyInvalidEmail => 'Gib eine gültige E-Mail-Adresse ein.';

  @override
  String get safetyAddedToast =>
      'Kontakt hinzugefügt — wir haben ihm eine Bestätigungs-E-Mail geschickt.';

  @override
  String get safetyRemovedToast => 'Kontakt entfernt.';

  @override
  String get safetyIncomingTitle => 'Anfragen an dich';

  @override
  String get safetyIncomingIntro =>
      'Diese Personen möchten dich als Sicherheitskontakt. Bestätige, um eine E-Mail zu erhalten, wenn sie einen Lauf beenden.';

  @override
  String safetyIncomingFrom(String name) {
    return 'Von $name';
  }

  @override
  String get safetyConfirm => 'Bestätigen';

  @override
  String get safetyDecline => 'Ablehnen';

  @override
  String get safetyConfirmedToast => 'Du bist jetzt Sicherheitskontakt.';

  @override
  String get safetyDeclinedToast => 'Anfrage abgelehnt.';

  @override
  String get safetyUnknownRunner => 'Ein Threkir-Läufer';

  @override
  String get activitySedentary => 'Überwiegend sitzend (Bürojob)';

  @override
  String get activityLight => 'Leicht aktiv (wenig Alltagsbewegung)';

  @override
  String get activityModerate => 'Mäßig aktiv (oft auf den Beinen)';

  @override
  String get activityVeryActive => 'Sehr aktiver Tag (körperliche Arbeit)';

  @override
  String get activityExtraActive => 'Extrem aktiv (schwere körperliche Arbeit)';

  @override
  String get goalLose => 'Abnehmen';

  @override
  String get goalMaintain => 'Gewicht halten';

  @override
  String get goalGain => 'Zunehmen';

  @override
  String get homeTodaysLift => 'Heutiges Training';

  @override
  String get settingsSectionProfile => 'Profil';

  @override
  String get settingsSectionAppsData => 'Apps & Daten';

  @override
  String get settingsSectionAccountLegal => 'Konto & Rechtliches';

  @override
  String get prefsSectionUnitsDisplay => 'Einheiten & Anzeige';

  @override
  String get authEmailLabel => 'E-Mail';

  @override
  String get authPasswordLabel => 'Passwort';

  @override
  String get authOrDivider => 'ODER';

  @override
  String get signInTitle => 'Anmelden';

  @override
  String get signInHeadline => 'Läufe geräteübergreifend synchronisieren';

  @override
  String get signInSubtitle =>
      'Melde dich an, um Läufe zu sichern und in der Web-App anzusehen.';

  @override
  String get signInButton => 'Anmelden';

  @override
  String get signInForgotPassword => 'Passwort vergessen?';

  @override
  String get signInResetNeedEmail =>
      'Gib zuerst oben deine E-Mail ein und tippe dann auf „Passwort vergessen“.';

  @override
  String get signInResetSent =>
      'Falls diese E-Mail registriert ist, haben wir einen Link zum Zurücksetzen gesendet.';

  @override
  String get signInWithApple => 'Mit Apple anmelden';

  @override
  String get signInWithGoogle => 'Mit Google anmelden';

  @override
  String get signInContinueOffline => 'Offline fortfahren';

  @override
  String get signInCreateAccountPrompt => 'Noch kein Konto? Jetzt erstellen';

  @override
  String get signUpTitle => 'Konto erstellen';

  @override
  String get signUpHeadline => 'Zeichne deine Läufe auf';

  @override
  String get signUpSubtitle =>
      'Erstelle ein Konto, um Läufe zu sichern und in der Web-App anzusehen.';

  @override
  String get signUpButton => 'Konto erstellen';

  @override
  String get signUpConfirmAge => 'Ich bin 16 Jahre oder älter';

  @override
  String get signUpAcceptPrefix => 'Ich akzeptiere die ';

  @override
  String get signUpTermsLink => 'Nutzungsbedingungen';

  @override
  String get signUpAcceptConjunction => ' und die ';

  @override
  String get signUpPrivacyLink => 'Datenschutzerklärung';

  @override
  String get signUpErrorConfirmAge =>
      'Bitte bestätige, dass du 16 oder älter bist, um fortzufahren.';

  @override
  String get signUpErrorAcceptTerms =>
      'Bitte akzeptiere die Nutzungsbedingungen und die Datenschutzerklärung, um fortzufahren.';

  @override
  String get signUpContinueWithApple => 'Mit Apple fortfahren';

  @override
  String get signUpContinueWithGoogle => 'Mit Google fortfahren';

  @override
  String get signUpSignInPrompt => 'Du hast schon ein Konto? Anmelden';

  @override
  String signUpCouldNotOpen(String url) {
    return '$url konnte nicht geöffnet werden';
  }

  @override
  String get onboardingTrackTitle => 'Jeden Lauf aufzeichnen';

  @override
  String get onboardingTrackBody =>
      'GPS-Aufzeichnung mit Live-Karte, Zwischenzeiten, Tempo, Schrittfrequenz und Höhenmetern. Funktioniert komplett offline – melde dich später an, um geräteübergreifend zu synchronisieren.';

  @override
  String get onboardingRoutesTitle => 'Routen folgen';

  @override
  String get onboardingRoutesBody =>
      'Importiere GPX- oder KML-Dateien oder synchronisiere Routen aus der Web-App. Erhalte Abweichungshinweise während des Laufs.';

  @override
  String get onboardingLocationTitle => 'Standortzugriff';

  @override
  String get onboardingLocationBody =>
      'Threkir zeichnet deine Läufe auf, indem deine GPS-Position erfasst wird, während die App im Vordergrund UND im Hintergrund läuft (damit die Aufzeichnung weiterläuft, wenn dein Bildschirm aus ist oder du zum Fotografieren die App wechselst). Standortdaten werden auf deinem Gerät gespeichert und nur dann auf die Server von Threkir hochgeladen, wenn du einen Lauf teilst oder synchronisierst. Wenn du den Hintergrundstandort ablehnst, stoppt die Aufzeichnung, sobald du die App verlässt – du kannst das später unter Einstellungen → Apps → Threkir → Berechtigungen ändern.';

  @override
  String get onboardingPrivacyTitle => 'Wer sieht deine Läufe?';

  @override
  String get onboardingPrivacyBody =>
      'Wähle eine Standardeinstellung für neue Läufe. Du kannst sie jederzeit in den Einstellungen ändern und für jeden einzelnen Lauf überschreiben.';

  @override
  String get onboardingGrantPermission => 'Berechtigung erteilen';

  @override
  String get onboardingNext => 'Weiter';

  @override
  String get privacyPrivateTitle => 'Privat';

  @override
  String get privacyPrivateSubtitle =>
      'Nur du kannst deine Läufe sehen. Du kannst jeden Lauf später teilen.';

  @override
  String get privacyFollowersTitle => 'Follower';

  @override
  String get privacyFollowersSubtitle =>
      'Personen, die dir folgen, sehen neue Läufe in ihrem Feed.';

  @override
  String get privacyPublicTitle => 'Öffentlich';

  @override
  String get privacyPublicSubtitle =>
      'Jeder kann deine Läufe finden und ansehen.';

  @override
  String get runStart => 'START';

  @override
  String get runStartA11yLabel => 'Lauf starten';

  @override
  String get runChooseRoute => 'Route wählen';

  @override
  String get runChangeRoute => 'Route ändern';

  @override
  String get runShareLiveLink => 'Live-Link teilen';

  @override
  String get runTrainingPlans => 'Trainingspläne';

  @override
  String get runTapToCancel => 'Zum Abbrechen tippen';

  @override
  String get runFirstRunPrompt =>
      'Dein erster Lauf ist nur einen Tipp entfernt.';

  @override
  String get runLastActivity => 'Letzte Aktivität';

  @override
  String get runLastRun => 'Letzter Lauf';

  @override
  String get runFollowing => 'FOLGT';

  @override
  String get runRaceFallbackTitle => 'Rennen';

  @override
  String get runRaceArmed => 'Rennen bereit';

  @override
  String get runRaceLive => 'Rennen LIVE';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — warten auf START';
  }

  @override
  String runRaceElapsedTapStart(String label, String elapsed) {
    return '$label — $elapsed vergangen · auf Start tippen';
  }

  @override
  String get runComplete => 'Lauf beendet';

  @override
  String get runStatDistance => 'Distanz';

  @override
  String get runStatTime => 'Zeit';

  @override
  String get runStatMoving => 'Bewegung';

  @override
  String get runStatPace => 'Tempo';

  @override
  String get runStatSpeed => 'Geschwindigkeit';

  @override
  String get runStatAvgPace => 'Ø Tempo';

  @override
  String get runStatAvgSpeed => 'Ø Geschwindigkeit';

  @override
  String get runStatCalories => 'Kalorien';

  @override
  String get runStatElevation => 'Höhenmeter';

  @override
  String get runStatSteps => 'Schritte';

  @override
  String get runStatCadence => 'Schrittfrequenz';

  @override
  String get runStatHeartRate => 'Herzfrequenz';

  @override
  String get runUnitKcal => 'kcal';

  @override
  String get runUnitMetres => 'm';

  @override
  String get runUnitSpm => 'S/min';

  @override
  String get runUnitBpm => 'S/min';

  @override
  String get runMutePaceCues => 'Tempohinweise stumm';

  @override
  String get runPaceCuesMuted => 'Tempohinweise stumm';

  @override
  String get runSynced => 'Synchronisiert';

  @override
  String get runSyncing => 'Synchronisiere …';

  @override
  String get runDone => 'Fertig';

  @override
  String get runDiscardA11yLabel => 'Lauf verwerfen';

  @override
  String get runDiscardA11yHint =>
      'Verwirft die aktuelle Aufzeichnung, ohne sie zu speichern';

  @override
  String get runResumeA11yLabel => 'Lauf fortsetzen';

  @override
  String get runPauseA11yLabel => 'Lauf pausieren';

  @override
  String get runResumeA11yHint => 'Setzt die pausierte Aufzeichnung fort';

  @override
  String get runPauseA11yHint =>
      'Pausiert die Aufzeichnung, ohne sie zu beenden';

  @override
  String get runMarkLapA11yLabel => 'Runde markieren';

  @override
  String runMarkLapWithCountA11yLabel(int count) {
    return 'Runde markieren, bisher $count';
  }

  @override
  String get runMarkLapA11yHint => 'Zeichnet die aktuelle Zwischenzeit auf';

  @override
  String get runCollapseStatsPanel => 'Statistik einklappen';

  @override
  String get runExpandStatsPanel => 'Statistik ausklappen';

  @override
  String runRouteRemaining(String distance) {
    return 'noch $distance';
  }

  @override
  String runOffRoute(int metres) {
    return 'Abseits der Route — $metres m entfernt';
  }

  @override
  String get runPermissionRevoked => 'Standortberechtigung entzogen';

  @override
  String get runGpsLost => 'GPS-Signal verloren — geh ins Freie';

  @override
  String get runWeakGps => 'Schwaches GPS — Distanz pausiert';

  @override
  String get runA11yStarted => 'Lauf gestartet';

  @override
  String get runA11yResumed => 'Lauf fortgesetzt';

  @override
  String get runA11yPaused => 'Lauf pausiert';

  @override
  String get runA11yFinished => 'Lauf beendet';

  @override
  String runLapMarked(int count) {
    return 'Runde $count markiert';
  }

  @override
  String get runDiscardDialogTitle => 'Lauf verwerfen?';

  @override
  String get runDiscardDialogBody => 'Dein Fortschritt geht verloren.';

  @override
  String get runKeepRunning => 'Weiterlaufen';

  @override
  String get runDiscard => 'Verwerfen';

  @override
  String get runStartWorkout => 'Workout starten';

  @override
  String get runStartWorkoutSubtitle =>
      'Laufe mit Live-Schrittzielen, Audiohinweisen und einem Soll-Ist-Vergleich.';

  @override
  String get runViewWorkoutDetails => 'Details ansehen';

  @override
  String get runWorkoutNoStructure =>
      'Dieses Workout hat keine lauffähige Struktur.';

  @override
  String runWorkoutLoaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Schritte',
      one: '$count Schritt',
    );
    return 'Workout geladen · $_temp0 — zum Starten GO tippen';
  }

  @override
  String get runAbandonWorkoutTitle => 'Workout abbrechen?';

  @override
  String get runAbandonWorkoutBody =>
      'Der strukturierte Plan endet hier; die Aufzeichnung läuft als freier Lauf weiter. Du kannst jederzeit stoppen, um das Geschaffte zu speichern.';

  @override
  String get runCancel => 'Abbrechen';

  @override
  String get runAbandon => 'Abbrechen';

  @override
  String get runNoRoutesSaved =>
      'Keine Routen gespeichert. Importiere eine im Routen-Tab.';

  @override
  String get runNotificationsOffHint =>
      'Benachrichtigungen sind aus — die Live-Laufbenachrichtigung wird nicht angezeigt. Die Aufzeichnung funktioniert trotzdem.';

  @override
  String get runSettings => 'Einstellungen';

  @override
  String get runStartAnyway => 'Trotzdem starten';

  @override
  String get runOpenSettings => 'Einstellungen öffnen';

  @override
  String get runNotNow => 'Nicht jetzt';

  @override
  String get runShareSubject => 'Verfolge mich live';

  @override
  String runCouldNotShareLink(String error) {
    return 'Live-Link konnte nicht geteilt werden: $error';
  }

  @override
  String get runHrStrapLostReconnecting =>
      'Herzfrequenzgurt verloren — verbinde neu …';

  @override
  String get runHrStrapReconnected => 'Herzfrequenzgurt wieder verbunden';

  @override
  String get runHrStrapLostNoHr =>
      'Herzfrequenzgurt verloren — Aufzeichnung läuft ohne HF weiter.';

  @override
  String get runHrStrapNotFound =>
      'Herzfrequenzgurt nicht gefunden — anlegen und neu verbinden.';

  @override
  String get runReconnect => 'Neu verbinden';

  @override
  String get runHrStrapStillNotFound =>
      'Weiterhin kein Gurt — Aufzeichnung läuft ohne HF weiter.';

  @override
  String get runSaveFailedRelaunch =>
      'Lokales Speichern fehlgeschlagen. Starte die App neu, um wiederherzustellen.';

  @override
  String get runSyncFailedSaveOffline =>
      'Offline gespeichert. Synchronisiere unter Läufe.';

  @override
  String get runSavedOffline => 'Offline gespeichert.';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings =>
      'Kein GPS — die Aufzeichnung startet, sobald der Standort aktiv ist.';

  @override
  String get runGpsBlockedSettings =>
      'Kein GPS — Berechtigung blockiert. Aktiviere sie, um die Route aufzuzeichnen.';

  @override
  String get runGpsPermissionPending =>
      'Kein GPS — die Aufzeichnung startet, sobald die Berechtigung erteilt ist.';

  @override
  String get runGpsAllowAllTheTime =>
      'Stelle den Standort auf „Immer zulassen“ — Läufe stoppen die Aufzeichnung, wenn du ohne Hintergrundberechtigung die App wechselst.';

  @override
  String get runGpsSensorFailed =>
      'Aufzeichnung ohne GPS — der Sensor konnte nicht gestartet werden.';

  @override
  String get runAgoJustNow => 'Gerade eben';

  @override
  String runAgoMinutes(int count) {
    return 'vor $count Min.';
  }

  @override
  String runAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Stunden',
      one: 'vor $count Stunde',
    );
    return '$_temp0';
  }

  @override
  String get runAgoYesterday => 'Gestern';

  @override
  String runAgoDays(int count) {
    return 'vor $count Tagen';
  }

  @override
  String runAgoWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Wochen',
      one: 'vor $count Woche',
    );
    return '$_temp0';
  }

  @override
  String runAgoMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Monaten',
      one: 'vor $count Monat',
    );
    return '$_temp0';
  }

  @override
  String get runWorkoutAbandonedBand => 'Workout abgebrochen · freier Lauf';

  @override
  String get runWorkoutCompleteBand =>
      'Workout fertig · zum Speichern Stopp tippen';

  @override
  String runWorkoutStepHeader(String label, String target, String pace) {
    return '$label · $target @ $pace';
  }

  @override
  String runWorkoutStepCounter(int current, int total) {
    return '$current/$total';
  }

  @override
  String get runWorkoutRewind => 'Zurück';

  @override
  String get runWorkoutSkip => 'Überspringen';

  @override
  String get runWorkoutAbandon => 'Abbrechen';

  @override
  String runWorkoutRemainingYards(int yards) {
    return 'noch $yards yd';
  }

  @override
  String runWorkoutRemainingMetres(int metres) {
    return 'noch $metres m';
  }

  @override
  String runWorkoutRemainingDuration(String duration) {
    return 'noch $duration';
  }

  @override
  String get historyRangeToday => 'Heute';

  @override
  String get historyRangeWeek => 'Diese Woche';

  @override
  String get historyRangeMonth => 'Letzte 30 Tage';

  @override
  String get historyRangeYear => 'Dieses Jahr';

  @override
  String get historyRangeAll => 'Gesamter Zeitraum';

  @override
  String get historyRangeCustom => 'Benutzerdefiniert…';

  @override
  String historyRangeFrom(String date) {
    return 'Ab $date';
  }

  @override
  String historyRangeUntil(String date) {
    return 'Bis $date';
  }

  @override
  String historyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe',
      one: '$count Lauf',
    );
    return '$_temp0';
  }

  @override
  String get historyDateRangeTooltip => 'Zeitraum';

  @override
  String get historySortTooltip => 'Sortieren';

  @override
  String get historySortNewest => 'Neueste zuerst';

  @override
  String get historySortOldest => 'Älteste zuerst';

  @override
  String get historySortLongest => 'Längste Distanz';

  @override
  String get historySortFastest => 'Bestes Tempo';

  @override
  String historySyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe synchronisieren',
      one: '$count Lauf synchronisieren',
    );
    return '$_temp0';
  }

  @override
  String get historyRefreshTooltip => 'Aus der Cloud aktualisieren';

  @override
  String get historyOfflineTooltip => 'Offline';

  @override
  String historySelectionTitle(int count) {
    return '$count ausgewählt';
  }

  @override
  String get historySelectAllTooltip => 'Alle auswählen';

  @override
  String get historyClearSelectionTooltip => 'Leeren';

  @override
  String get historyDeleteTooltip => 'Löschen';

  @override
  String get historyCancelTooltip => 'Abbrechen';

  @override
  String get historyAddRun => 'Lauf hinzufügen';

  @override
  String get historyAddRunTooltip => 'Lauf manuell hinzufügen';

  @override
  String get historyLogTooltip => 'Lauf, Training oder Mahlzeit erfassen';

  @override
  String historyLoadMore(int count) {
    return '$count weitere laden';
  }

  @override
  String get historyNoMatch => 'Keine Läufe entsprechen diesen Filtern';

  @override
  String get historyKindAll => 'Alle';

  @override
  String get historyKindRuns => 'Läufe';

  @override
  String get historyKindLifts => 'Kraft';

  @override
  String get historyKindMeals => 'Mahlzeiten';

  @override
  String get historyViewAll => 'Alle ansehen';

  @override
  String get historyToday => 'Heute';

  @override
  String get historyYesterday => 'Gestern';

  @override
  String historySetCount(int n) {
    return '$n Sätze';
  }

  @override
  String historyKcal(int n) {
    return '$n kcal';
  }

  @override
  String get historyTimelineEmpty =>
      'In dieser Ansicht ist noch nichts erfasst.';

  @override
  String get historyClearFilters => 'Filter zurücksetzen';

  @override
  String get historyEmptyTitle => 'Noch keine Läufe';

  @override
  String get historyEmptyBody =>
      'Tippe auf den Lauf-Tab, um deinen ersten Lauf zu starten';

  @override
  String get historyFilterAll => 'Alle';

  @override
  String get historySourceAll => 'Alle Quellen';

  @override
  String historySourceLabel(String source) {
    return 'Quelle: $source';
  }

  @override
  String get historySourceFilterTooltip => 'Nach Quelle filtern';

  @override
  String get historySourceRecorded => 'Aufgezeichnet';

  @override
  String get historySourceWatch => 'Uhr';

  @override
  String get historySourceStrava => 'Strava';

  @override
  String get historySourceParkrun => 'parkrun';

  @override
  String get historySourceHealthKit => 'HealthKit';

  @override
  String get historySourceHealthConnect => 'Health Connect';

  @override
  String get historyRangePickerTitle => 'Daten auswählen';

  @override
  String get historyRangeStart => 'Start';

  @override
  String get historyRangeEnd => 'Ende';

  @override
  String get historyRangeTapDate => 'Datum antippen';

  @override
  String get historyRangeApply => 'Anwenden';

  @override
  String get historyRangeClear => 'Leeren';

  @override
  String get historyPrevMonth => 'Vorheriger Monat';

  @override
  String get historyNextMonth => 'Nächster Monat';

  @override
  String get historyPrevYear => 'Vorheriges Jahr';

  @override
  String get historyNextYear => 'Nächstes Jahr';

  @override
  String historyDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe löschen?',
      one: '$count Lauf löschen?',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody =>
      'Dies kann nicht rückgängig gemacht werden.';

  @override
  String get historyCancel => 'Abbrechen';

  @override
  String get historyDelete => 'Löschen';

  @override
  String get historyQueuedToSync => 'Zur Synchronisierung eingereiht';

  @override
  String get historySignInToSync =>
      'Melde dich in den Einstellungen an, um Läufe zu synchronisieren';

  @override
  String get historyRefreshFailed =>
      'Aktualisierung fehlgeschlagen – prüfe deine Verbindung';

  @override
  String get historyLoadMoreFailed =>
      'Weitere Läufe konnten nicht geladen werden';

  @override
  String historySyncPartial(int synced, int total, String error) {
    return '$synced/$total synchronisiert. Fehler: $error';
  }

  @override
  String historySyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Bei $count Läufen konnte die GPS-Aufzeichnung nicht hochgeladen werden — der Rest wurde synchronisiert. Die fehlgeschlagenen Läufe werden im nächsten Zyklus erneut versucht.',
      one:
          'Bei $count Lauf konnte die GPS-Aufzeichnung nicht hochgeladen werden — der Rest wurde synchronisiert. Es wird im nächsten Zyklus erneut versucht.',
    );
    return '$_temp0';
  }

  @override
  String historySyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Läufe synchronisiert',
      one: '$count Lauf synchronisiert',
    );
    return '$_temp0';
  }

  @override
  String historyDeletePartial(int deleted, int queued) {
    return '$deleted gelöscht; $queued eingereiht – wird erneut versucht, sobald du wieder online bist.';
  }

  @override
  String historyDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe gelöscht',
      one: '$count Lauf gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'Lauf hinzufügen';

  @override
  String get addRunSave => 'Speichern';

  @override
  String get addRunSectionWhen => 'Wann';

  @override
  String get addRunSectionActivity => 'Aktivität';

  @override
  String get addRunSectionRoute => 'Route (optional)';

  @override
  String get addRunSectionDistance => 'Distanz';

  @override
  String get addRunSectionDuration => 'Dauer';

  @override
  String get addRunSectionTitle => 'Titel (optional)';

  @override
  String get addRunSectionNotes => 'Notizen (optional)';

  @override
  String get addRunClearRoute => 'Route entfernen';

  @override
  String get addRunSearchRoutes => 'Gespeicherte Routen suchen';

  @override
  String get addRunNoRoutes =>
      'Noch keine gespeicherten Routen – erstelle oder importiere eine, um sie hier anzuhängen';

  @override
  String get addRunDistanceInvalid => 'Gib eine Distanz größer als 0 ein';

  @override
  String get addRunDurationInvalid => 'Gib eine Dauer ein';

  @override
  String get addRunTitleHint => 'z. B. Mittagsrunde';

  @override
  String get addRunNotesHint => 'Wie hat es sich angefühlt?';

  @override
  String get addRunSaveButton => 'Lauf speichern';

  @override
  String addRunSaveFailed(String error) {
    return 'Lauf konnte nicht gespeichert werden: $error';
  }

  @override
  String get addRunSaved => 'Lauf zum Verlauf hinzugefügt';

  @override
  String get addRunPickerSearchHint => 'Routen suchen';

  @override
  String get addRunPickerClear => 'Leeren';

  @override
  String get addRunPickerCancel => 'Abbrechen';

  @override
  String addRunPickerNoMatch(String query) {
    return 'Keine Routen passen zu \"$query\"';
  }

  @override
  String get addRunPickerNoRoute => 'Keine Route';

  @override
  String get runDetailDnfBadge => 'DNF';

  @override
  String get runDetailEditTooltip => 'Lauf bearbeiten';

  @override
  String get runDetailShareTooltip => 'Lauf teilen';

  @override
  String get runDetailMoreTooltip => 'Mehr';

  @override
  String get runDetailSaveAsRoute => 'Als Route speichern';

  @override
  String get runDetailDeleteRun => 'Lauf löschen';

  @override
  String get runDetailReportRun => 'Lauf melden';

  @override
  String get runDetailEditTitle => 'Lauf bearbeiten';

  @override
  String get runDetailFieldTitle => 'Titel';

  @override
  String get runDetailFieldNotes => 'Notizen';

  @override
  String get runDetailFieldDistance => 'Distanz';

  @override
  String get runDetailFieldDuration => 'Dauer';

  @override
  String get runDetailMarkDnf => 'Als DNF markieren';

  @override
  String get runDetailMarkDnfSubtitle =>
      'Schließt diesen Lauf von persönlichen Rekorden aus';

  @override
  String get runDetailEditInvalid => 'Gib eine gültige Distanz und Dauer ein';

  @override
  String get runDetailSave => 'Speichern';

  @override
  String get runDetailCancel => 'Abbrechen';

  @override
  String get runDetailDelete => 'Löschen';

  @override
  String get runDetailLoadingGps => 'GPS-Daten werden geladen...';

  @override
  String get runDetailGpsUnavailable =>
      'GPS-Aufzeichnung offline nicht verfügbar';

  @override
  String get runDetailPauseReplay => 'Wiedergabe pausieren';

  @override
  String get runDetailReplay => 'Diesen Lauf abspielen';

  @override
  String get runDetailStatElevGain => 'Aufstieg';

  @override
  String get runDetailStatElevLoss => 'Abstieg';

  @override
  String get runDetailStatAvgHr => 'Ø HF';

  @override
  String get runDetailStatAgeGrade => 'Altersklassen-Wertung';

  @override
  String get runDetailStatGradeAdjPace => 'Höhenkorr. Pace';

  @override
  String get runDetailSectionElevation => 'Höhenmeter';

  @override
  String get runDetailSectionLaps => 'Runden';

  @override
  String runDetailLapNumber(int number) {
    return 'Runde $number';
  }

  @override
  String get runDetailSectionRunningDynamics => 'Laufdynamik';

  @override
  String get runDetailDynVerticalOsc => 'Vertikale Bewegung';

  @override
  String get runDetailDynGroundContact => 'Bodenkontaktzeit';

  @override
  String get runDetailDynStrideLength => 'Schrittlänge';

  @override
  String get runDetailDynAvgPower => 'Ø Leistung';

  @override
  String get runDetailSectionRouteHistory => 'Routenverlauf';

  @override
  String get runDetailThisRoute => 'diese Route';

  @override
  String runDetailPersonalBest(String route) {
    return 'Persönliche Bestzeit auf $route';
  }

  @override
  String runDetailBehindPb(String delta) {
    return '$delta hinter Bestzeit';
  }

  @override
  String runDetailAttemptOf(int rank, int total, String pb) {
    return 'Versuch $rank von $total  —  Bestzeit: $pb';
  }

  @override
  String get runDetailSectionBestEfforts => 'Bestleistungen';

  @override
  String get runDetailSectionHeartRateZones => 'Herzfrequenzzonen';

  @override
  String get runDetailHrAvg => 'Ø';

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
  String get runDetailNoGpsForSplits => 'Keine GPS-Daten für Splits';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Lauf zu kurz für einen vollständigen $unit-Split';
  }

  @override
  String get runDetailSectionSegments => 'Segmente';

  @override
  String get runDetailSaveAsRouteTitle => 'Als Route speichern';

  @override
  String get runDetailSaveAsRouteBody =>
      'Speichere diese GPS-Aufzeichnung als Route, der du erneut folgen kannst.';

  @override
  String get runDetailRouteNameLabel => 'Routenname';

  @override
  String get runDetailNoTrackToSave =>
      'Dieser Lauf hat keine GPS-Aufzeichnung zum Speichern als Route';

  @override
  String runDetailRouteLinked(String route) {
    return 'Mit $route verknüpft';
  }

  @override
  String get runDetailRouteLinkFailed => 'Route konnte nicht verknüpft werden';

  @override
  String get runDetailReSnapping => 'Wird erneut an Straßen angepasst…';

  @override
  String runDetailRematchFailed(String error) {
    return 'Neuabgleich fehlgeschlagen: $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return '\"$name\" gespeichert — $kept Wegpunkte ($smoothed geglättet)';
  }

  @override
  String runDetailRouteSaveFailed(String name) {
    return '\"$name\" konnte nicht als Route gespeichert werden.';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'Lauf konnte nicht öffentlich gemacht werden: $error';
  }

  @override
  String get runDetailMakePublicTitle => 'Diesen Lauf öffentlich machen?';

  @override
  String get runDetailMakePublicBodyZone =>
      'Durch das Teilen wird dieser Lauf öffentlich, sodass jeder mit dem Link ihn ansehen kann. Dieser Lauf beginnt oder endet in einer deiner Datenschutzzonen, daher sehen Betrachter eine beschnittene Aufzeichnung, bei der die Abschnitte innerhalb der Zone ausgeblendet sind.';

  @override
  String get runDetailMakePublicBodyHasZones =>
      'Durch das Teilen wird dieser Lauf öffentlich, sodass jeder mit dem Link ihn ansehen kann. Keine deiner Datenschutzzonen überschneidet sich mit dieser Aufzeichnung, daher ist die vollständige Aufzeichnung sichtbar.';

  @override
  String get runDetailMakePublicBodyNoZones =>
      'Durch das Teilen wird dieser Lauf öffentlich, sodass jeder mit dem Link ihn ansehen kann — einschließlich Start- und Endpunkt deines Laufs. Du hast keine Datenschutzzonen eingerichtet. Erwäge, vor dem Teilen eine rund um dein Zuhause hinzuzufügen.';

  @override
  String get runDetailMakePublic => 'Öffentlich machen';

  @override
  String get runDetailDeleteTitle => 'Lauf löschen?';

  @override
  String get runDetailDeleteBody =>
      'Dies kann nicht rückgängig gemacht werden.';

  @override
  String get runDetailSuggestLink => 'Verknüpfen';

  @override
  String get runDetailSuggestDismiss => 'Verwerfen';

  @override
  String get runDetailSuggestRanRoute => 'Sieht aus, als wärst du ';

  @override
  String get runDetailSuggestLinkPrompt =>
      'Diesen Lauf mit dieser Route verknüpfen?';

  @override
  String get runDetailMatchPending => 'Wird an Straßen angepasst…';

  @override
  String get runDetailMatchSkipped => 'Nicht angepasst (zu wenige Punkte)';

  @override
  String get runDetailMatchFailed =>
      'Anpassung fehlgeschlagen – Rohaufzeichnung wird angezeigt';

  @override
  String get runDetailMatchMatched => 'Angepasst';

  @override
  String get runDetailRematchQueueing => 'Wird eingereiht…';

  @override
  String get runDetailRematch => 'Neu abgleichen';

  @override
  String get runDetailSegStatDistance => 'Distanz';

  @override
  String get runDetailSegStatTime => 'Zeit';

  @override
  String get runDetailSegStatPace => 'Tempo';

  @override
  String get runDetailSegStatHr => 'HF';

  @override
  String get runDetailSegStatGain => 'Aufstieg';

  @override
  String get runDetailSegDismiss => 'Verwerfen';

  @override
  String get publicRunTitle => 'Lauf';

  @override
  String get publicRunLoadError => 'Dieser Lauf konnte nicht geladen werden.';

  @override
  String get publicRunUnavailable =>
      'Dieser Lauf ist privat oder nicht mehr verfügbar.';

  @override
  String get publicRunAuthorFallback => 'Läufer';

  @override
  String get publicRunStatDistance => 'Distanz';

  @override
  String get publicRunStatTime => 'Zeit';

  @override
  String get publicRunStatPace => 'Tempo';

  @override
  String get publicRunSectionSegments => 'Segmente';

  @override
  String get routesSyncFailedOffline =>
      'Routen konnten nicht synchronisiert werden — offline';

  @override
  String get routesLoadMoreFailed =>
      'Weitere Routen konnten nicht geladen werden';

  @override
  String routesStarUpdateFailed(String error) {
    return 'Stern konnte nicht aktualisiert werden: $error';
  }

  @override
  String get routesImportFailedLocalOnly =>
      'Import fehlgeschlagen: Wähle die Datei aus dem lokalen Speicher, nicht aus einem reinen Cloud-Dokumentenauswähler.';

  @override
  String routesImported(String name) {
    return '\"$name\" importiert';
  }

  @override
  String routesImportFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String routesSaved(String name) {
    return '\"$name\" gespeichert';
  }

  @override
  String get routesEmptyTitle => 'Noch keine Routen';

  @override
  String get routesEmptyBody =>
      'Tippe auf Erstellen, um eine Route auf der Karte zu zeichnen, oder importiere eine GPX-, KML- oder TCX-Datei.';

  @override
  String get routesBuild => 'Erstellen';

  @override
  String get routesImport => 'Importieren';

  @override
  String get routesNoMatch => 'Keine Routen entsprechen diesen Filtern';

  @override
  String get routesClearFilters => 'Filter zurücksetzen';

  @override
  String routesLoadMore(int count) {
    return '$count weitere laden';
  }

  @override
  String get routesQueuedToSync => 'Zur Synchronisierung eingereiht';

  @override
  String get routesSavedForOffline => 'Für offline gespeichert';

  @override
  String get routesUnstarRoute => 'Markierung der Route entfernen';

  @override
  String get routesStarForWatch => 'Markieren, um auf der Uhr anzuzeigen';

  @override
  String get routesDiscover => 'Entdecken';

  @override
  String get routesSyncFromCloud => 'Aus der Cloud synchronisieren';

  @override
  String get routesPublicRoutes => 'Öffentliche Routen';

  @override
  String get routesHeatmap => 'Heatmap';

  @override
  String get routesExplorePublic => 'Öffentliche Routen erkunden';

  @override
  String get routesHeatmapTooltip => 'Routen-Heatmap';

  @override
  String get routesSearchHint => 'Routen nach Namen suchen…';

  @override
  String get routesClearSearch => 'Suche löschen';

  @override
  String get routesStarred => 'Markiert';

  @override
  String routesCountMeta(int visible, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$visible von $total Routen',
      one: '$visible von $total Route',
    );
    return '$_temp0';
  }

  @override
  String get routesSurfaceAny => 'Beliebiger Untergrund';

  @override
  String get routesSurfaceRoad => 'Straße';

  @override
  String get routesSurfaceTrail => 'Trail';

  @override
  String get routesSurfaceMixed => 'Gemischt';

  @override
  String get routesDistanceAny => 'Beliebige Distanz';

  @override
  String get routesSortNewest => 'Neueste zuerst';

  @override
  String get routesSortLongest => 'Längste';

  @override
  String get routesSortShortest => 'Kürzeste';

  @override
  String get routesSortMostRun => 'Am häufigsten gelaufen';

  @override
  String get routesSortAlpha => 'A–Z';

  @override
  String routesDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Routen löschen?',
      one: '$count Route löschen?',
    );
    return '$_temp0';
  }

  @override
  String get routesDeleteConfirmBody =>
      'Dies kann nicht rückgängig gemacht werden.';

  @override
  String routesSelectionTitle(int count) {
    return '$count ausgewählt';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted gelöscht; $failed fehlgeschlagen — überprüfe deine Verbindung.';
  }

  @override
  String routesDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Routen gelöscht.',
      one: '$count Route gelöscht.',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteCleared => 'Route gelöscht';

  @override
  String routeBuilderPointsSummary(int count, String distance) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Punkte, $distance',
      one: '$count Punkt, $distance',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteFailedStraightLines =>
      'Routing fehlgeschlagen — gerade Linien durch deine Punkte werden angezeigt.';

  @override
  String routeBuilderSegmentsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Segmente konnten nicht an eine Straße angepasst werden. Ziehe die betroffenen Punkte, um sie anzupassen.',
      one:
          '$count Segment konnte nicht an eine Straße angepasst werden. Ziehe den betroffenen Punkt, um ihn anzupassen.',
    );
    return '$_temp0';
  }

  @override
  String routeBuilderRoutingFailed(String error) {
    return 'Routing fehlgeschlagen: $error';
  }

  @override
  String get routeBuilderTooCloseToPin =>
      'Zu nah an einem anderen Punkt — zieh ihn etwas weiter.';

  @override
  String get routeBuilderPinAlreadyThere =>
      'Hier ist bereits ein Punkt — tippe weiter entfernt, um einen weiteren hinzuzufügen.';

  @override
  String get routeBuilderTargetTooLong =>
      'Gib eine Zieldistanz von bis zu 1000 km ein.';

  @override
  String get routeBuilderSaveNeedTwo =>
      'Setze zuerst mindestens zwei Wegpunkte.';

  @override
  String routeBuilderSavedLocally(String detail) {
    return 'Lokal gespeichert. $detail Wird beim nächsten Mal synchronisiert.';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return 'Standort nicht verfügbar: $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'Server nicht erreichbar. Melde dich an oder überprüfe deine Verbindung und versuche es erneut.';

  @override
  String routeBuilderSaveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get routeBuilderSearchHint => 'Orte suchen…';

  @override
  String get routeBuilderMore => 'Mehr';

  @override
  String get routeBuilderGenerateLoop => 'Schleife erzeugen';

  @override
  String get routeBuilderUndo => 'Rückgängig';

  @override
  String get routeBuilderClear => 'Löschen';

  @override
  String get routeBuilderClearConfirmTitle => 'Diese Route löschen?';

  @override
  String get routeBuilderClearConfirmBody =>
      'Alle Wegpunkte werden entfernt. Das kann nicht rückgängig gemacht werden.';

  @override
  String get routeBuilderSaving => 'Wird gespeichert…';

  @override
  String get routeBuilderSave => 'Speichern';

  @override
  String get routeBuilderLocateMe => 'Mich orten';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'Tippe, um Punkt $number zu verschieben, oder verwende die Symbole';
  }

  @override
  String routeBuilderEmptyHint(String mode) {
    return 'Tippe auf die Karte, um Wegpunkte zu setzen · $mode';
  }

  @override
  String routeBuilderOnePointHint(String mode) {
    return 'Setze einen weiteren, um die Linie zu zeichnen · $mode';
  }

  @override
  String routeBuilderStatusGain(String distance, int gain, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Punkte',
      one: '$count Punkt',
    );
    return '$distance · $gain m ↑ · $_temp0';
  }

  @override
  String routeBuilderStatusNoGain(String distance, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Punkte',
      one: '$count Punkt',
    );
    return '$distance · $_temp0';
  }

  @override
  String routeBuilderDeletePoint(int number) {
    return 'Punkt $number löschen';
  }

  @override
  String get routeBuilderCancelDrag => 'Ziehen abbrechen';

  @override
  String get routeBuilderModeTrail => 'Trail';

  @override
  String get routeBuilderModeRoad => 'Straße';

  @override
  String get routeBuilderModeStraight => 'Gerade';

  @override
  String get routeBuilderLoopDialogBody =>
      'Zieldistanz — wir bauen eine radiale Schleife um die aktuelle Kartenmitte.';

  @override
  String get routeBuilderCancel => 'Abbrechen';

  @override
  String get routeBuilderGenerate => 'Erzeugen';

  @override
  String get routeBuilderSaveDialogTitle => 'Route speichern';

  @override
  String get routeBuilderNameLabel => 'Name';

  @override
  String get routeBuilderNameHint => 'z. B. Flussschleife';

  @override
  String get routeBuilderDescriptionLabel => 'Beschreibung (optional)';

  @override
  String get routeBuilderDescriptionHint =>
      'Untergrund, Hügel, Parkplätze, alles Erwähnenswerte';

  @override
  String get routeBuilderSaveToLabel => 'Speichern in';

  @override
  String get routeBuilderSaveToPersonal => 'Persönlich';

  @override
  String get routeBuilderMakePublic => 'Öffentlich machen';

  @override
  String get routeBuilderMakePublicSubtitle =>
      'Andere finden sie unter Entdecken';

  @override
  String get routeDetailStartRun => 'Lauf starten';

  @override
  String get routeDetailShare => 'Teilen';

  @override
  String get routeDetailShareAsImage => 'Als Bild teilen';

  @override
  String get routeDetailShareAsGpx => 'Als GPX teilen';

  @override
  String get routeDetailShareAsKml => 'Als KML teilen';

  @override
  String get routeDetailShareAsGpxMarkers => 'Als GPX + Markierungen teilen';

  @override
  String get routeDetailRemoveOfflineSave => 'Offline-Speicherung entfernen';

  @override
  String get routeDetailSaveForOffline => 'Für offline speichern';

  @override
  String get routeDetailUnstarRoute => 'Markierung der Route entfernen';

  @override
  String get routeDetailStarForWatch => 'Markieren, um auf der Uhr anzuzeigen';

  @override
  String get routeDetailMakePrivate => 'Privat machen';

  @override
  String get routeDetailMakePublic => 'Öffentlich machen';

  @override
  String get routeDetailRemoveBookmark => 'Lesezeichen entfernen';

  @override
  String get routeDetailBookmarkRoute => 'Route mit Lesezeichen versehen';

  @override
  String get routeDetailReportRoute => 'Route melden';

  @override
  String get routeDetailTransferToClub => 'An Club übertragen';

  @override
  String get routeDetailManageClub =>
      'Trennen oder zu einem anderen Club verschieben';

  @override
  String get routeDetailDeleteRoute => 'Route löschen';

  @override
  String get routeDetailStatDistance => 'Distanz';

  @override
  String get routeDetailStatElevation => 'Höhe';

  @override
  String routeDetailStatReviews(int count) {
    return '$count Bewertungen';
  }

  @override
  String get routeDetailStatWaypoints => 'Wegpunkte';

  @override
  String get routeDetailPublicRoute => 'Öffentliche Route';

  @override
  String get routeDetailPrivateRoute => 'Private Route';

  @override
  String get routeDetailPublicSubtitle =>
      'Jeder mit dem Freigabelink kann diese Route ansehen';

  @override
  String get routeDetailPrivateSubtitle => 'Nur du kannst diese Route sehen';

  @override
  String get routeDetailSavedForOffline => 'Für offline gespeichert';

  @override
  String get routeDetailSaveForOfflineTitle => 'Für offline speichern';

  @override
  String get routeDetailOfflinePinnedSubtitle =>
      'Die Route bleibt auf diesem Telefon, damit du sie ohne Verbindung laufen kannst.';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'Behalte diese Route auf deinem Telefon für die Nutzung ohne Netzwerk.';

  @override
  String get routeDetailDescriptionHeading => 'Beschreibung';

  @override
  String get routeDetailDescribe => 'Diese Route beschreiben';

  @override
  String get routeDetailDescribing => 'Wird beschrieben…';

  @override
  String get routeDetailAiAttribution =>
      'Von KI aus den Streckendaten verfasst';

  @override
  String get routeDetailDescribeFailed =>
      'Beschreibung konnte nicht erstellt werden. Bitte erneut versuchen.';

  @override
  String get routeDetailEnhanceUpgradeHint =>
      'KI-Beschreibungen sind eine Pro-Funktion. Upgrade zum Verbessern.';

  @override
  String get routeDetailDescShapeLoop => 'Rundkurs';

  @override
  String get routeDetailDescShapeOutAndBack => 'Hin-und-zurück';

  @override
  String get routeDetailDescShapePointToPoint => 'Punkt-zu-Punkt';

  @override
  String get routeDetailDescSurfaceRoad => 'Straßen';

  @override
  String get routeDetailDescSurfaceTrail => 'Trail';

  @override
  String get routeDetailDescSurfaceMixed => 'Mixed-Surface';

  @override
  String get routeDetailDescElevFlat => 'flach';

  @override
  String get routeDetailDescElevRolling => 'leicht hügelig';

  @override
  String get routeDetailDescElevHilly => 'hügelig';

  @override
  String get routeDetailDescElevMountainous => 'bergig';

  @override
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  ) {
    return '$name ist eine $distance lange $surface-$shape-Route.';
  }

  @override
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  ) {
    return '$name ist eine $distance lange $shape-Route.';
  }

  @override
  String routeDetailDescClimb(String gain, String elevation, String perKm) {
    return 'Sie hat $gain Anstieg — $elevation, etwa $perKm pro km.';
  }

  @override
  String get routeDetailDescFlat => 'Sie hat kaum Höhenunterschied.';

  @override
  String routeDetailDescPerKm(int m) {
    return '$m m';
  }

  @override
  String routeDetailRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe',
      one: '$count Lauf',
    );
    return '$_temp0';
  }

  @override
  String get routeDetailFeatured => 'Empfohlen';

  @override
  String get routeDetailSurfaceTrail => 'TRAIL';

  @override
  String get routeDetailSurfaceMixed => 'GEMISCHT';

  @override
  String get routeDetailSurfaceRoad => 'STRASSE';

  @override
  String get routeDetailAddTagHint => 'Tag hinzufügen';

  @override
  String get routeDetailReviewsHeading => 'Bewertungen';

  @override
  String get routeDetailRate => 'Bewerten';

  @override
  String routeDetailRateStars(int n) {
    return 'Bewertung auf $n von 5 setzen';
  }

  @override
  String get routeDetailReviewsOffline => 'Bewertungen offline nicht verfügbar';

  @override
  String get routeDetailNoReviews => 'Noch keine Bewertungen';

  @override
  String get routeDetailRateDialogTitle => 'Diese Route bewerten';

  @override
  String get routeDetailCommentLabel => 'Kommentar (optional)';

  @override
  String get routeDetailCancel => 'Abbrechen';

  @override
  String get routeDetailSubmit => 'Senden';

  @override
  String get routeDetailSignInToReview =>
      'Melde dich an, um eine Bewertung abzugeben';

  @override
  String routeDetailReviewFailed(String error) {
    return 'Bewertung konnte nicht gesendet werden: $error';
  }

  @override
  String routeDetailBookmarkFailed(String error) {
    return 'Lesezeichen fehlgeschlagen: $error';
  }

  @override
  String get routeDetailPublicWillSync =>
      'Route auf öffentlich gesetzt. Wird beim nächsten Mal synchronisiert.';

  @override
  String get routeDetailPrivateWillSync =>
      'Route auf privat gesetzt. Wird beim nächsten Mal synchronisiert.';

  @override
  String routeDetailVisibilityFailed(String error) {
    return 'Sichtbarkeit konnte nicht aktualisiert werden: $error';
  }

  @override
  String routeDetailStarFailed(String error) {
    return 'Stern konnte nicht aktualisiert werden: $error';
  }

  @override
  String get routeDetailOfflineSaved => 'Für offline gespeichert.';

  @override
  String get routeDetailOfflineRemoved =>
      'Aus den Offline-Speicherungen entfernt.';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'Tag konnte nicht gespeichert werden: $error';
  }

  @override
  String routeDetailTagRemoveFailed(String error) {
    return 'Tag konnte nicht entfernt werden: $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return '$format konnte nicht geteilt werden: $error';
  }

  @override
  String get routeDetailClubsLoadTimeout =>
      'Deine Clubs konnten nicht geladen werden — überprüfe dein Netzwerk.';

  @override
  String get routeDetailClubsLoadFailed =>
      'Deine Clubs konnten nicht geladen werden.';

  @override
  String get routeDetailDetached =>
      'Vom Club getrennt; die Route ist jetzt persönlich.';

  @override
  String get routeDetailMovedToClub =>
      'Route in die Club-Bibliothek verschoben.';

  @override
  String routeDetailTransferFailed(String error) {
    return 'Übertragung fehlgeschlagen: $error';
  }

  @override
  String get routeDetailDeleteTitle => 'Route löschen?';

  @override
  String get routeDetailDeleteBody =>
      'Dies kann nicht rückgängig gemacht werden.';

  @override
  String get routeDetailDelete => 'Löschen';

  @override
  String routeDetailDeleteFailed(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get routeDetailPreview => 'Vorschau';

  @override
  String get routeDetailPreviewStart => 'Start';

  @override
  String get routeDetailPreviewFinish => 'Ziel';

  @override
  String get routeDetailTransferDialogTitle => 'An Club übertragen';

  @override
  String get routeDetailManageClubTitle => 'Club-Zugehörigkeit verwalten';

  @override
  String get routeDetailTransferDialogBody =>
      'Mitglieder des Clubs sehen diese Route in der Club-Bibliothek und können sie in ihre Pläne übernehmen.';

  @override
  String get routeDetailManageClubBody =>
      'Verschiebe diese Route in einen anderen Club, den du verwaltest, oder trenne sie wieder zu persönlich.';

  @override
  String get routeDetailDetachToPersonal => 'Zu persönlich trennen';

  @override
  String get routeDetailDetachSubtitle =>
      'Entfernt die Route aus der Bibliothek des aktuellen Clubs.';

  @override
  String get routeDetailNoAdminClubs =>
      'Du besitzt oder verwaltest noch keine Clubs.';

  @override
  String get routeDetailCurrentClub => 'Aktueller Club';

  @override
  String routeDetailClubMemberCount(String location, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '$count Mitglied',
    );
    return '$location · $_temp0';
  }

  @override
  String get exploreRoutesTitle => 'Routen erkunden';

  @override
  String get exploreRoutesModeSearch => 'Suche';

  @override
  String get exploreRoutesModeNearMe => 'In meiner Nähe';

  @override
  String get exploreRoutesSearchHint => 'Routen nach Namen suchen...';

  @override
  String get exploreRoutesFeatured => 'Empfohlen';

  @override
  String get exploreRoutesSignInRequired =>
      'Melde dich an und stelle eine Internetverbindung her, um Routen zu erkunden';

  @override
  String get exploreRoutesTimeout =>
      'Zeitüberschreitung der Verbindung. Überprüfe dein Netzwerk und versuche es erneut.';

  @override
  String get exploreRoutesSearchFailed =>
      'Suche fehlgeschlagen. Tippe auf Wiederholen, um es erneut zu versuchen.';

  @override
  String get exploreRoutesLoadMoreFailed =>
      'Weitere konnten nicht geladen werden — überprüfe deine Verbindung';

  @override
  String get exploreRoutesLocationPermissionRequired =>
      'Standortberechtigung erforderlich, um Routen in der Nähe zu finden';

  @override
  String get exploreRoutesNearbyFailed =>
      'Routen in der Nähe konnten nicht gefunden werden. Tippe auf Wiederholen, um es erneut zu versuchen.';

  @override
  String get exploreRoutesEmptyNoPublic => 'Noch keine öffentlichen Routen';

  @override
  String get exploreRoutesEmptyNoMatch =>
      'Keine Routen entsprechen deiner Suche';

  @override
  String get exploreRoutesEmptyBody =>
      'Vom Web-App geteilte Routen erscheinen hier';

  @override
  String get exploreRoutesDistanceAny => 'Beliebige Distanz';

  @override
  String get exploreRoutesSurfaceAny => 'Beliebiger Untergrund';

  @override
  String get exploreRoutesSurfaceRoad => 'Straße';

  @override
  String get exploreRoutesSurfaceTrail => 'Trail';

  @override
  String get exploreRoutesSurfaceMixed => 'Gemischt';

  @override
  String get exploreRoutesSortMostRun => 'Am häufigsten gelaufen';

  @override
  String get exploreRoutesSortNewest => 'Neueste';

  @override
  String get exploreRoutesSortFeatured => 'Empfohlen';

  @override
  String get exploreRoutesSort => 'Sortieren';

  @override
  String exploreRoutesSaveCheckConnection(String name) {
    return '\"$name\" konnte nicht gespeichert werden — überprüfe deine Verbindung und versuche es erneut.';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return '\"$name\" konnte nicht gespeichert werden.';
  }

  @override
  String exploreRoutesSaved(String name) {
    return '\"$name\" in deiner Bibliothek gespeichert';
  }

  @override
  String get exploreRoutesAlreadySaved => 'Bereits gespeichert';

  @override
  String get exploreRoutesSaveToLibrary => 'In Bibliothek speichern';

  @override
  String get exploreRoutesSurfaceTrailShort => 'Trail';

  @override
  String get exploreRoutesSurfaceMixedShort => 'Gemischt';

  @override
  String get exploreRoutesSurfaceRoadShort => 'Straße';

  @override
  String get exploreRoutesDistanceUnderKm => 'Unter 5 km';

  @override
  String get exploreRoutesDistanceMidKm => '5–10 km';

  @override
  String get exploreRoutesDistanceLongKm => '10–21 km';

  @override
  String get exploreRoutesDistanceUltraKm => '21 km+';

  @override
  String get exploreRoutesDistanceUnderMi => 'Unter 3 mi';

  @override
  String get exploreRoutesDistanceMidMi => '3–6 mi';

  @override
  String get exploreRoutesDistanceLongMi => '6–13 mi';

  @override
  String get exploreRoutesDistanceUltraMi => '13 mi+';

  @override
  String get heatmapSearchHint => 'Orte suchen…';

  @override
  String get heatmapFilters => 'Filter';

  @override
  String heatmapRoutesStartHere(int count) {
    return '$count Routen beginnen hier';
  }

  @override
  String heatmapRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Routen',
      one: '$count Route',
    );
    return '$_temp0';
  }

  @override
  String get heatmapNoRoutesHere => 'Hier keine Routen';

  @override
  String get heatmapNoRoutesHint =>
      'Hier keine Routen. Verschiebe die Karte oder ändere die Filter.';

  @override
  String heatmapClearKept(int count) {
    return '$count behaltene löschen';
  }

  @override
  String get heatmapUnpinFromMap => 'Von Karte lösen';

  @override
  String get heatmapKeepOnMap => 'Auf Karte behalten';

  @override
  String get heatmapLocateMe => 'Mich orten';

  @override
  String heatmapLocationUnavailable(String error) {
    return 'Standort nicht verfügbar: $error';
  }

  @override
  String get heatmapBackToList => 'Zurück zur Liste';

  @override
  String get heatmapViewRoute => 'Route ansehen';

  @override
  String get heatmapKept => 'Behalten';

  @override
  String get heatmapKeep => 'Behalten';

  @override
  String get heatmapLensShow => 'Anzeigen';

  @override
  String get heatmapLensDistance => 'Distanz';

  @override
  String get heatmapLensMap => 'Karte';

  @override
  String get heatmapHeatDensity => 'Heat-Dichte';

  @override
  String get heatmapResetFilters => 'Filter zurücksetzen';

  @override
  String get heatmapLensPopular => 'Beliebt';

  @override
  String get heatmapLensFriends => 'Freunde';

  @override
  String get heatmapLensFeatured => 'Empfohlen';

  @override
  String get heatmapLensHiddenGems => 'Geheimtipps';

  @override
  String get publicRouteFallbackTitle => 'Route';

  @override
  String get publicRouteLoadError => 'Diese Route konnte nicht geladen werden.';

  @override
  String get publicRouteUnavailable =>
      'Diese Route ist privat oder nicht mehr verfügbar.';

  @override
  String get publicRouteStatDistance => 'Distanz';

  @override
  String get publicRouteStatElevation => 'Höhe';

  @override
  String get publicRouteStatWaypoints => 'Wegpunkte';

  @override
  String get routesLoadErrorRetry =>
      'Deine Routen konnten nicht geladen werden. Überprüfe deine Verbindung und versuche es erneut.';

  @override
  String get feedTitle => 'Feed';

  @override
  String get feedFindPeople => 'Personen finden';

  @override
  String get feedActivityAll => 'Alle';

  @override
  String get feedActivityRun => 'Lauf';

  @override
  String get feedActivityWalk => 'Gehen';

  @override
  String get feedActivityCycle => 'Radfahren';

  @override
  String get feedActivityHike => 'Wandern';

  @override
  String get feedActivityLift => 'Kraft';

  @override
  String get feedLiftSetsLabel => 'Sätze';

  @override
  String get feedLiftVolume => 'Volumen';

  @override
  String get feedLiftUntitled => 'Training';

  @override
  String get feedLoadMore => 'Mehr laden';

  @override
  String feedLoadMoreFailed(String error) {
    return 'Mehr konnte nicht geladen werden: $error';
  }

  @override
  String get feedLoadError => 'Feed konnte nicht geladen werden.';

  @override
  String get feedEveryoneYouFollow => 'Alle, denen du folgst';

  @override
  String get feedRunnerFallback => 'Läufer';

  @override
  String get relativeJustNow => 'Gerade eben';

  @override
  String relativeMinutesAgo(int count) {
    return 'vor $count Min.';
  }

  @override
  String relativeHoursAgo(int count) {
    return 'vor $count Std.';
  }

  @override
  String get relativeYesterday => 'Gestern';

  @override
  String relativeDaysAgo(int count) {
    return 'vor $count T.';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Wochen',
      one: 'vor 1 Woche',
    );
    return '$_temp0';
  }

  @override
  String get coachArchiveToday => 'Heute';

  @override
  String coachArchiveDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Tagen',
    );
    return '$_temp0';
  }

  @override
  String get feedLast14Days => 'Letzte 14 Tage';

  @override
  String get feedEmptyTitle => 'Dein Feed ist leer';

  @override
  String get feedEmptyBody =>
      'Folge anderen Läufern, um ihre öffentlichen Läufe hier zu sehen.';

  @override
  String get feedNoMatchesTitle => 'Keine Treffer';

  @override
  String get feedNoMatchesBody =>
      'In den letzten 14 Tagen passt nichts zu den aktuellen Filtern.';

  @override
  String get feedNoActivityTitle => 'Keine aktuelle Aktivität';

  @override
  String get feedNoActivityBody =>
      'Niemand, dem du folgst, hat in den letzten 14 Tagen einen öffentlichen Lauf erfasst.';

  @override
  String get feedClearFilters => 'Filter zurücksetzen';

  @override
  String feedKudosUpdateFailed(String error) {
    return 'Kudos konnten nicht aktualisiert werden: $error';
  }

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileRunnerFallback => 'Läufer';

  @override
  String get profileTabRuns => 'Läufe';

  @override
  String get profileTabFollowers => 'Follower';

  @override
  String get profileTabFollowing => 'Abonniert';

  @override
  String get profileTabNotifications => 'Mitteilungen';

  @override
  String get profileReportUser => 'Nutzer melden';

  @override
  String get profileUnblock => 'Profil entsperren';

  @override
  String get profileBlock => 'Profil blockieren';

  @override
  String get profileLoadError => 'Profil konnte nicht geladen werden.';

  @override
  String get profileNotFound => 'Profil nicht gefunden.';

  @override
  String profileFollowStats(int followers, int following) {
    String _temp0 = intl.Intl.pluralLogic(
      followers,
      locale: localeName,
      other: '$followers Follower',
      one: '$followers Follower',
    );
    return '$_temp0 · $following abonniert';
  }

  @override
  String get profileFollowing => 'Folgt';

  @override
  String get profileFollow => 'Folgen';

  @override
  String get profileRunsEmptySelf => 'Du hast noch keine Läufe geteilt.';

  @override
  String get profileRunsEmptyOther => 'Noch keine öffentlichen Läufe.';

  @override
  String get profileFollowersEmpty => 'Noch keine Follower.';

  @override
  String get profileFollowingEmpty => 'Folgst noch niemandem.';

  @override
  String profileLoadMore(int count) {
    return '$count weitere laden';
  }

  @override
  String get profileLoadMoreFollowersFailed =>
      'Weitere Follower konnten nicht geladen werden';

  @override
  String get profileLoadMoreFollowingFailed =>
      'Weitere Abonnements konnten nicht geladen werden';

  @override
  String profileFollowUpdateFailed(String error) {
    return 'Follow konnte nicht aktualisiert werden: $error';
  }

  @override
  String profileBlockConfirmTitle(String name) {
    return '$name blockieren?';
  }

  @override
  String get profileBlockConfirmBody =>
      'Diese Person kann dir nicht mehr folgen, deinen Läufen keine Kudos geben und sie nicht kommentieren. Jede bestehende Follow-Beziehung zwischen euch in beide Richtungen wird aufgehoben. Du kannst die Blockierung auf dieser Seite jederzeit aufheben.';

  @override
  String get profileBlockConfirmAction => 'Blockieren';

  @override
  String get profileCancel => 'Abbrechen';

  @override
  String get profileThisRunner => 'diesen Läufer';

  @override
  String get profileRunnerNoun => 'Läufer';

  @override
  String profileBlocked(String name) {
    return '$name blockiert';
  }

  @override
  String profileBlockFailed(String error) {
    return 'Blockieren fehlgeschlagen: $error';
  }

  @override
  String profileUnblocked(String name) {
    return '$name entsperrt';
  }

  @override
  String profileUnblockFailed(String error) {
    return 'Entsperren fehlgeschlagen: $error';
  }

  @override
  String get profileNotifAll => 'Alle';

  @override
  String get profileNotifUnread => 'Ungelesen';

  @override
  String get profileMarkAllRead => 'Alle als gelesen markieren';

  @override
  String profileMarkAllReadFailed(String error) {
    return 'Konnte nicht alle als gelesen markieren: $error';
  }

  @override
  String get profileNotifsCaughtUp => 'Du bist auf dem neuesten Stand.';

  @override
  String get profileNotifsEmpty => 'Noch keine Mitteilungen.';

  @override
  String get profileDismiss => 'Verwerfen';

  @override
  String profileDismissFailed(String error) {
    return 'Verwerfen fehlgeschlagen: $error';
  }

  @override
  String get profileNotifSomeone => 'Jemand';

  @override
  String get profileNotifYourRun => 'deinen Lauf';

  @override
  String profileNotifKudos(String name, String dist) {
    return '$name hat deinem $dist Kudos gegeben';
  }

  @override
  String profileNotifComment(String name, String dist) {
    return '$name hat deinen $dist kommentiert';
  }

  @override
  String profileNotifCommentReply(String name) {
    return '$name hat auf deinen Kommentar geantwortet';
  }

  @override
  String profileNotifFollow(String name) {
    return '$name folgt dir jetzt';
  }

  @override
  String profileNotifEventRsvpTitled(String name, String title) {
    return '$name hat für dein Event \"$title\" zugesagt';
  }

  @override
  String profileNotifEventRsvp(String name) {
    return '$name hat für dein Event zugesagt';
  }

  @override
  String profileNotifPlanUpdate(String name) {
    return '$name hat deinen Trainingsplan aktualisiert';
  }

  @override
  String profileNotifMessage(String name) {
    return '$name hat dir eine Nachricht gesendet';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$name hat in $club gepostet';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$name hat in einem deiner Clubs gepostet';
  }

  @override
  String profileNotifRunCompletedDist(String name, String dist) {
    return '$name hat einen $dist Lauf abgeschlossen';
  }

  @override
  String profileNotifRunCompleted(String name) {
    return '$name hat einen Lauf abgeschlossen';
  }

  @override
  String profileNotifGeneric(String name) {
    return '$name hat mit deiner Aktivität interagiert';
  }

  @override
  String get socialTabFeed => 'Feed';

  @override
  String get socialTabPeople => 'Personen';

  @override
  String get socialTabClubs => 'Clubs';

  @override
  String get socialTabRoutes => 'Routen';

  @override
  String get socialTabDiscover => 'Entdecken';

  @override
  String get discoverSearchPlaceholder =>
      'Yoga, Pilates, HIIT, Laufgruppen suchen…';

  @override
  String get discoverActivityAll => 'Alle Aktivitäten';

  @override
  String get discoverCadenceLabel => 'Rhythmus';

  @override
  String get discoverCadenceAny => 'Beliebiger Rhythmus';

  @override
  String get discoverOneOff => 'Einmalig';

  @override
  String get discoverWeekly => 'Wöchentlich';

  @override
  String get discoverBiweekly => 'Alle 2 Wochen';

  @override
  String get discoverMonthly => 'Monatlich';

  @override
  String get discoverDayLabel => 'Tag';

  @override
  String get discoverDayAny => 'Beliebiger Tag';

  @override
  String get discoverDayMon => 'Mo';

  @override
  String get discoverDayTue => 'Di';

  @override
  String get discoverDayWed => 'Mi';

  @override
  String get discoverDayThu => 'Do';

  @override
  String get discoverDayFri => 'Fr';

  @override
  String get discoverDaySat => 'Sa';

  @override
  String get discoverDaySun => 'So';

  @override
  String get discoverTimeLabel => 'Tageszeit';

  @override
  String get discoverTimeAny => 'Beliebige Zeit';

  @override
  String get discoverMorning => 'Morgens';

  @override
  String get discoverAfternoon => 'Nachmittags';

  @override
  String get discoverEvening => 'Abends';

  @override
  String get discoverPriceLabel => 'Preis';

  @override
  String get discoverPriceAny => 'Beliebiger Preis';

  @override
  String get discoverFree => 'Kostenlos';

  @override
  String get discoverPaid => 'Kostenpflichtig';

  @override
  String get discoverLoading => 'Suche läuft…';

  @override
  String get discoverEmpty =>
      'Keine öffentlichen Aktivitäten passen zu diesen Filtern.';

  @override
  String get discoverSearchFailed =>
      'Aktivitäten konnten nicht geladen werden. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get clubsTitle => 'Clubs';

  @override
  String get clubsFindPeople => 'Personen finden';

  @override
  String get clubsNewClub => 'Neuer Club';

  @override
  String get clubsTabBrowse => 'Entdecken';

  @override
  String get clubsTabMine => 'Meine Clubs';

  @override
  String get clubsJoinWithCode => 'Mit Einladungscode beitreten';

  @override
  String get clubsSearchHint => 'Nach Name oder Ort suchen';

  @override
  String get clubsTimeoutError =>
      'Zeitüberschreitung. Überprüfe dein Netzwerk und versuche es erneut.';

  @override
  String get clubsLoadError =>
      'Clubs konnten nicht geladen werden. Tippe auf Wiederholen.';

  @override
  String get clubsBadgePrivate => 'PRIVAT';

  @override
  String clubsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '$count Mitglied',
    );
    return '$_temp0';
  }

  @override
  String get clubsEmptyBrowseTitle => 'Keine Clubs für diese Suche.';

  @override
  String get clubsEmptyMineTitle => 'Du bist noch keinem Club beigetreten.';

  @override
  String get clubsEmptyBrowseBody => 'Versuche einen anderen Namen oder Ort.';

  @override
  String get clubsEmptyMineBody => 'Geh zu Entdecken, um einen zu finden.';

  @override
  String get clubDetailTabFeed => 'Feed';

  @override
  String get clubDetailTabEvents => 'Events';

  @override
  String get clubDetailTabMembers => 'Mitglieder';

  @override
  String get clubDetailTabRoutes => 'Routen';

  @override
  String get clubDetailTabTemplates => 'Vorlagen';

  @override
  String get clubDetailReportClub => 'Club melden';

  @override
  String get clubDetailReportPost => 'Diesen Beitrag melden';

  @override
  String get clubDetailLoadFailedTitle =>
      'Dieser Club konnte nicht geladen werden.';

  @override
  String get clubDetailLoadFailedBody =>
      'Er wurde möglicherweise entfernt, oder deine Sitzung muss aktualisiert werden. Ziehe zum Aktualisieren, oder melde dich in den Einstellungen ab und wieder an.';

  @override
  String get clubDetailRetry => 'Wiederholen';

  @override
  String get clubDetailTimeoutError =>
      'Zeitüberschreitung. Überprüfe dein Netzwerk und versuche es erneut.';

  @override
  String get clubDetailRequestSent => 'Anfrage an Admins gesendet.';

  @override
  String clubDetailLeaveTitle(String club) {
    return '$club verlassen?';
  }

  @override
  String get clubDetailCancel => 'Abbrechen';

  @override
  String get clubDetailLeave => 'Verlassen';

  @override
  String clubDetailReplyFailed(String error) {
    return 'Antwort konnte nicht gesendet werden: $error';
  }

  @override
  String get clubDetailMemberFallback => 'Mitglied';

  @override
  String get clubDetailRequestPending => 'Anfrage ausstehend';

  @override
  String get clubDetailInviteOnly => 'Nur mit Einladung';

  @override
  String get clubDetailRequest => 'Anfragen';

  @override
  String get clubDetailJoin => 'Beitreten';

  @override
  String get clubDetailOwner => 'Inhaber';

  @override
  String get clubDetailNextEvent => 'NÄCHSTES EVENT';

  @override
  String clubDetailGoingCount(int count) {
    return '$count Zusagen';
  }

  @override
  String get clubDetailNoPostsMember =>
      'Noch keine Beiträge. Teile ein Update mit den Mitgliedern.';

  @override
  String get clubDetailNoPosts => 'Noch keine Updates.';

  @override
  String get clubDetailShareUpdateHint => 'Teile ein Update …';

  @override
  String get clubDetailPost => 'Posten';

  @override
  String get clubDetailReply => 'Antworten';

  @override
  String clubDetailHideReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Antworten ausblenden',
      one: '$count Antwort ausblenden',
    );
    return '$_temp0';
  }

  @override
  String clubDetailShowReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Antworten',
      one: '$count Antwort',
    );
    return '$_temp0';
  }

  @override
  String clubDetailReplyAuthorLine(String name, String time) {
    return '$name · $time';
  }

  @override
  String get clubDetailWriteReplyHint => 'Antwort schreiben …';

  @override
  String get clubDetailSend => 'Senden';

  @override
  String get clubDetailNoEventsAdmin =>
      'Keine bevorstehenden Events. Tippe auf Erstellen, um eins hinzuzufügen.';

  @override
  String get clubDetailNoEvents => 'Keine bevorstehenden Events.';

  @override
  String get clubDetailCreateEvent => 'Event erstellen';

  @override
  String get clubDetailGoing => 'Zugesagt';

  @override
  String clubDetailApproveFailed(String error) {
    return 'Genehmigung fehlgeschlagen: $error';
  }

  @override
  String clubDetailDenyFailed(String error) {
    return 'Ablehnung fehlgeschlagen: $error';
  }

  @override
  String clubDetailPendingRequests(int count) {
    return 'Ausstehende Anfragen ($count)';
  }

  @override
  String clubDetailUserShort(String id) {
    return 'Nutzer $id…';
  }

  @override
  String get clubDetailDeny => 'Ablehnen';

  @override
  String get clubDetailApprove => 'Genehmigen';

  @override
  String clubDetailMemberCountLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder.',
      one: '$count Mitglied.',
    );
    return '$_temp0';
  }

  @override
  String clubDetailRouteSaved(String name) {
    return '\"$name\" gespeichert';
  }

  @override
  String get clubDetailBuildRoute => 'Route für diesen Club erstellen';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'Noch keine Routen. Erstelle oben den offiziellen Kurs oder übertrage eine deiner persönlichen Routen über die Routendetailseite.';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'Noch keine Routen. Admins können eine ihrer persönlichen Routen über die Routendetailseite übertragen.';

  @override
  String get clubDetailRoutesEmpty =>
      'Mit diesem Club wurden noch keine Routen geteilt.';

  @override
  String get clubDetailTemplateAdded => 'Vorlage zu deinen Plänen hinzugefügt.';

  @override
  String clubDetailAdoptFailed(String error) {
    return 'Übernehmen fehlgeschlagen: $error';
  }

  @override
  String get clubDetailNoTemplatesAdmin =>
      'Noch keine Vorlagen. Veröffentliche einen deiner Pläne über dessen Detailseite.';

  @override
  String get clubDetailNoTemplates =>
      'Noch keine Planvorlagen für diesen Club.';

  @override
  String get clubDetailAdopt => 'Übernehmen';

  @override
  String get clubDetailSessionTemplatesTitle => 'Sitzungsvorlagen';

  @override
  String get clubDetailSessionAdopted =>
      'Sitzung zu deinen Plänen hinzugefügt.';

  @override
  String get clubDetailGymRoutineTemplatesTitle => 'Gym-Routinevorlagen';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'Mitglieder können eine Club-Gym-Routine in ihre eigenen Routinen übernehmen. Änderungen an einer Kopie wirken sich nicht auf die Vorlage aus.';

  @override
  String get clubDetailGymRoutineAdopted =>
      'Routine zu deinen Gym-Routinen hinzugefügt.';

  @override
  String clubDetailRoutineExerciseCount(int n) {
    return '$n Übungen';
  }

  @override
  String get eventNotFound => 'Event nicht gefunden.';

  @override
  String get eventLoadError =>
      'Dieses Event konnte nicht geladen werden. Tippe auf Wiederholen.';

  @override
  String get eventTimeoutError =>
      'Zeitüberschreitung. Überprüfe dein Netzwerk und versuche es erneut.';

  @override
  String eventDurationMin(int minutes) {
    return '· $minutes Min';
  }

  @override
  String eventGetDirectionsTo(String label) {
    return 'Route nach $label';
  }

  @override
  String get eventGetDirections => 'Route abrufen';

  @override
  String get eventCouldNotOpenMaps => 'Karten konnten nicht geöffnet werden.';

  @override
  String get eventPickOccurrence => 'TERMIN WÄHLEN';

  @override
  String get eventTargetPace => 'Zieltempo';

  @override
  String get eventClassSessionEyebrow => 'KURS';

  @override
  String get eventResultSubmitted => 'Ergebnis eingereicht.';

  @override
  String eventSubmitFailed(String error) {
    return 'Senden fehlgeschlagen: $error';
  }

  @override
  String eventRaceControlFailed(String error) {
    return 'Rennsteuerung fehlgeschlagen: $error';
  }

  @override
  String eventAttendees(int count) {
    return 'TEILNEHMER ($count)';
  }

  @override
  String get eventNoRsvps => 'Noch keine Zusagen – sei die/der Erste.';

  @override
  String get eventAttendeeMember => 'Mitglied';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventMarkAttended => 'Als teilgenommen markieren';

  @override
  String get eventMarkNoShow => 'Als nicht erschienen markieren';

  @override
  String get eventAttendanceAttended => 'Teilgenommen';

  @override
  String get eventAttendanceNoShow => 'Nicht erschienen';

  @override
  String get eventAttendanceFailed =>
      'Teilnahme konnte nicht aktualisiert werden. Bitte erneut versuchen.';

  @override
  String get eventRsvpFailed =>
      'Deine Zusage konnte nicht aktualisiert werden. Bitte erneut versuchen.';

  @override
  String get eventRsvpGoing => 'Bin dabei';

  @override
  String get eventRsvpMaybe => 'Vielleicht';

  @override
  String get eventRsvpDeclined => 'Kann nicht';

  @override
  String get eventRaceArmed => 'Scharf – wartet auf GO';

  @override
  String get eventRaceRunning => 'Läuft – live';

  @override
  String get eventRaceFinished => 'Beendet';

  @override
  String get eventRaceCancelled => 'Abgesagt';

  @override
  String get eventRaceNotArmed => 'Nicht scharf';

  @override
  String get eventRaceControlLabel => 'RENNSTEUERUNG';

  @override
  String get eventRaceAutoApprove =>
      'Eingereichte Zeiten automatisch genehmigen';

  @override
  String get eventRaceArm => 'Rennen scharf schalten';

  @override
  String get eventRaceArmedHint =>
      'Tippe auf Los, wenn das Rennen beginnt. Die Uhren der Teilnehmer zeigen jetzt das Scharf-Banner.';

  @override
  String get eventRaceFireGo => 'Los';

  @override
  String get eventRaceCancel => 'Abbrechen';

  @override
  String eventRaceStartedAt(String time) {
    return 'Gestartet um $time';
  }

  @override
  String get eventRaceEnd => 'Rennen beenden';

  @override
  String get eventRaceCancelRace => 'Rennen abbrechen';

  @override
  String get eventRaceEndConfirmBody =>
      'Rennen beenden? Damit wird das Event für alle Läufer abgeschlossen und kann nicht rückgängig gemacht werden.';

  @override
  String get eventRaceCancelConfirmBody =>
      'Rennen abbrechen? Damit wird das Event für alle Läufer abgebrochen und kann nicht rückgängig gemacht werden.';

  @override
  String get eventUpdatePosted => 'Update im Club-Feed veröffentlicht.';

  @override
  String eventPostUpdateFailed(String error) {
    return 'Update konnte nicht veröffentlicht werden: $error';
  }

  @override
  String get eventPostUpdateLabel => 'UPDATE POSTEN';

  @override
  String get eventUpdateHint => 'Wetterentscheidung? Treffpunkt geändert?';

  @override
  String get eventPostUpdate => 'Update posten';

  @override
  String get eventResultsTitle => 'Ergebnisse';

  @override
  String get eventRemoveMine => 'Meines entfernen';

  @override
  String get eventRemoveResultTitle => 'Dein Ergebnis entfernen?';

  @override
  String get eventRemoveResultBody =>
      'Deine eingereichte Zielzeit wird aus der Bestenliste dieser Veranstaltung entfernt. Du kannst später erneut einreichen.';

  @override
  String get eventRemoveResultConfirm => 'Ergebnis entfernen';

  @override
  String eventRemoveResultFailed(String error) {
    return 'Dein Ergebnis konnte nicht entfernt werden: $error';
  }

  @override
  String get eventSubmitMyTime => 'Meine Zeit einreichen';

  @override
  String get eventSubmitting => 'Wird gesendet …';

  @override
  String get eventNoResults =>
      'Noch keine Ergebnisse. Reiche deine Zeit nach dem Event ein und andere sehen sie hier.';

  @override
  String get eventResultRunner => 'Läufer';

  @override
  String get eventResultYou => '(du)';

  @override
  String get eventSubmitTimeTitle => 'Deine Zeit einreichen';

  @override
  String get eventSubmitTimeSubtitle =>
      'Wähle einen Lauf zum Anhängen oder erfasse ein DNF / DNS.';

  @override
  String get eventNoRecentRuns =>
      'Keine aktuellen Läufe gefunden. Zeichne zuerst einen Lauf auf und komm dann zurück.';

  @override
  String get eventRecordDnf => 'DNF erfassen';

  @override
  String get eventRecordDns => 'DNS erfassen';

  @override
  String get eventSubmitCancel => 'Abbrechen';

  @override
  String get liveSpectatorTitle => 'Live-Tracking';

  @override
  String get liveSpectatorConnectError => 'Verbindung nicht möglich.';

  @override
  String get liveSpectatorWaiting => 'Warte auf den ersten Ping des Läufers …';

  @override
  String get liveSpectatorBadgeLive => 'Live';

  @override
  String get liveSpectatorBadgeIdle => 'Inaktiv';

  @override
  String get liveSpectatorBadgeConnecting => 'Verbinde';

  @override
  String get liveSpectatorBadgeStale => 'Verzögert';

  @override
  String get liveSpectatorBadgeFinished => 'Beendet';

  @override
  String get liveSpectatorBadgeDnf => 'DNF';

  @override
  String get liveUpdatedNow => 'Gerade aktualisiert';

  @override
  String liveUpdatedSeconds(int n) {
    return 'Vor ${n}s aktualisiert';
  }

  @override
  String liveUpdatedMinutes(int n) {
    return 'Vor $n Min. aktualisiert';
  }

  @override
  String liveUpdatedHours(int n) {
    return 'Vor $n Std. aktualisiert';
  }

  @override
  String liveUpdatedDays(int n) {
    return 'Vor $n T. aktualisiert';
  }

  @override
  String get liveCutoffTitle => 'Nächstes Zeitlimit';

  @override
  String liveCutoffToGo(String distance) {
    return 'Noch $distance';
  }

  @override
  String liveCutoffEta(String eta) {
    return 'Voraussichtliche Ankunft $eta';
  }

  @override
  String liveCutoffAhead(String margin) {
    return '$margin Puffer';
  }

  @override
  String liveCutoffBehind(String margin) {
    return '$margin im Rückstand';
  }

  @override
  String get liveCutoffWaitingSignal =>
      'Warte auf ein frisches Signal für die Ankunftsprognose';

  @override
  String get plansTitle => 'Trainingspläne';

  @override
  String get plansNewPlan => 'Neuer Plan';

  @override
  String plansDeleteTitle(String name) {
    return '\"$name\" löschen?';
  }

  @override
  String get plansDeleteBody =>
      'Alle Wochen und Trainingseinheiten werden entfernt.';

  @override
  String get plansCancel => 'Abbrechen';

  @override
  String get plansDelete => 'Löschen';

  @override
  String get plansAbandon => 'Aufgeben';

  @override
  String plansAbandonTitle(String name) {
    return '„$name“ aufgeben?';
  }

  @override
  String get plansAbandonBody => 'Danach kannst du einen neuen Plan erstellen.';

  @override
  String plansActionFailed(String error) {
    return 'Plan konnte nicht aktualisiert werden: $error';
  }

  @override
  String plansDaysPerWeek(int count) {
    return '$count Tage/Wo.';
  }

  @override
  String get plansSignInTitle => 'Melde dich an, um Trainingspläne zu nutzen';

  @override
  String get plansSignInBody =>
      'Pläne werden mit deinem Konto synchronisiert und folgen dir über alle Geräte. Gehe zu Einstellungen → Anmelden, um dich zu verbinden.';

  @override
  String get plansEmptyTitle => 'Noch keine Pläne.';

  @override
  String get plansEmptyBody =>
      'Wähle ein Zielrennen und wir planen die Wochen für dich.';

  @override
  String get plansTimeoutError =>
      'Zeitüberschreitung der Verbindung. Prüfe dein Netzwerk und versuche es erneut.';

  @override
  String get plansLoadError =>
      'Trainingspläne konnten nicht geladen werden. Tippe auf Wiederholen, um es erneut zu versuchen.';

  @override
  String get planNewTitle => 'Neuer Plan';

  @override
  String get planNewNameLabel => 'Planname';

  @override
  String get planNewNameHint => 'z. B. Herbst-Halbmarathon';

  @override
  String get planNewGoalRace => 'Zielrennen';

  @override
  String get planNewStartDate => 'Startdatum';

  @override
  String get planNewDaysPerWeek => 'Tage pro Woche';

  @override
  String planNewDaysOption(int count) {
    return '$count Tage';
  }

  @override
  String get planNewGoalTimeSection => 'Zielzeit · optional';

  @override
  String get planNewBeginnerTitle => 'Neu im Laufen? Nutze einen Geh-Lauf-Plan';

  @override
  String get planNewBeginnerSubtitle =>
      'Ein sanfter C25K-Plan mit getakteten Lauf-/Geh-Intervallen, der zu einem durchgehenden Lauf aufbaut. Überschreibt das Zielzeit-Tempo.';

  @override
  String get planNewRecent5kSection => 'Aktuelle 5-km-Zeit · optional';

  @override
  String get planNewRecent5kHelp =>
      'Verankere die Tempos an einem echten Ergebnis statt am Ziel. Nutzt die Riegel-Äquivalenz, um auf die Zieldistanz hochzurechnen.';

  @override
  String get planNewRecent5kConfirm =>
      'Diese Zeit könnte ich heute laufen — sie entspricht meiner aktuellen Form.';

  @override
  String get planNewRecent5kWarning =>
      'Bis du bestätigst, bleiben die Tempos auf der konservativen, zielbasierten Schätzung. Sich an einem alten Ergebnis zu orientieren, kann für Wiedereinsteiger zu schnelle Tempos vorgeben.';

  @override
  String get planNewOverrideHint => 'Gesamtwochen überschreiben';

  @override
  String planNewOverrideLabel(int count) {
    return 'Wochen überschreiben (Standard: $count)';
  }

  @override
  String get planNewCancel => 'Abbrechen';

  @override
  String get planNewCreate => 'Plan erstellen';

  @override
  String get planNewCreating => 'Wird erstellt…';

  @override
  String get planNewPreviewTitle => 'Vorschau';

  @override
  String get planNewPaceEasy => 'Locker';

  @override
  String get planNewPaceMarathon => 'Marathon';

  @override
  String get planNewPaceTempo => 'Tempo';

  @override
  String get planNewPaceInterval => 'Intervall';

  @override
  String get planNewPaceRep => 'Wiederholung';

  @override
  String get planNewPacesFallback =>
      'Geschätzte Tempos — füge einen aktuellen Lauf oder eine Zielzeit hinzu für personalisierte Vorgaben.';

  @override
  String planNewVdot(String value) {
    return 'Daniels VDOT: $value';
  }

  @override
  String get planNewWeekOutline => 'Wochenübersicht';

  @override
  String planNewMoreWeeks(int count) {
    return '+ $count weitere Wochen';
  }

  @override
  String planNewSessions(int count) {
    return '$count Einheiten';
  }

  @override
  String get planNewTemplateTitle => 'Mit einer Vereinsvorlage starten';

  @override
  String get planNewTemplateSubtitle =>
      'Übernimm einen Plan, den ein Verein veröffentlicht hat. Er wird mit dem Startdatum unten in dein Konto kopiert — bearbeitbar wie jeder andere Plan.';

  @override
  String get planNewTemplateButton => 'Vorlagen durchsuchen';

  @override
  String get planNewTemplateCloning => 'Wird übernommen…';

  @override
  String planNewTemplateCloneFailed(String error) {
    return 'Vorlage konnte nicht übernommen werden: $error';
  }

  @override
  String get planNewTemplatePickerTitle => 'Vorlage wählen';

  @override
  String get planNewTemplatePickerCancel => 'Abbrechen';

  @override
  String get planLibraryTitle => 'Öffentliche Planbibliothek';

  @override
  String get planLibrarySubheading =>
      'Von anderen Läufern veröffentlichte Pläne. Klone einen in dein Konto, um zu starten.';

  @override
  String get planLibrarySearchHint => 'Pläne nach Name suchen';

  @override
  String get planLibraryLoadError =>
      'Bibliothek konnte nicht geladen werden. Erneut versuchen.';

  @override
  String get planLibraryRetry => 'Erneut versuchen';

  @override
  String get planLibraryEmpty => 'Noch keine veröffentlichten Pläne.';

  @override
  String planLibraryEmptySearch(String query) {
    return 'Keine Pläne passen zu „$query“.';
  }

  @override
  String planLibraryByAuthor(String author) {
    return 'von $author';
  }

  @override
  String get planLibraryAnonymous => 'einem Läufer';

  @override
  String planLibraryWeeks(int weeks) {
    return '$weeks Wochen';
  }

  @override
  String planLibraryDaysPerWeek(int days) {
    return '$days×/Woche';
  }

  @override
  String get planLibraryClone => 'In meine Pläne klonen';

  @override
  String get planLibraryCloning => 'Wird geklont…';

  @override
  String get planLibraryCloneSuccess => 'Plan geklont.';

  @override
  String planLibraryCloneFailed(String error) {
    return 'Klonen fehlgeschlagen: $error';
  }

  @override
  String get planLibraryStartDate => 'Startdatum';

  @override
  String get planLibraryNotFound =>
      'Dieser Plan ist nicht mehr in der öffentlichen Bibliothek.';

  @override
  String get planLibraryPreviewWeeks => 'Wochen';

  @override
  String planLibraryPreviewWeek(int n) {
    return 'Woche $n';
  }

  @override
  String get planDetailPublishLibraryLabel => 'Öffentliche Planbibliothek';

  @override
  String get planDetailPublishLibrary => 'In Bibliothek veröffentlichen';

  @override
  String get planDetailPublishLibraryHint =>
      'Teile eine Kopie dieses Plans, damit ihn jeder klonen kann. Deine Fitnesswerte werden nicht geteilt.';

  @override
  String get planDetailPublishLibrarySuccess =>
      'Plan in der öffentlichen Bibliothek veröffentlicht. Dein persönlicher Plan bleibt unverändert.';

  @override
  String planDetailPublishLibraryFailed(String error) {
    return 'Veröffentlichen fehlgeschlagen: $error';
  }

  @override
  String get planDetailUnpublishLibrary => 'Zurückziehen';

  @override
  String get planDetailUnpublishSuccess =>
      'Aus der öffentlichen Bibliothek entfernt.';

  @override
  String planDetailUnpublishFailed(String error) {
    return 'Zurückziehen fehlgeschlagen: $error';
  }

  @override
  String get planDetailAlreadyPublished =>
      'Dieser Plan ist in der öffentlichen Bibliothek.';

  @override
  String get plansBrowseLibrary => 'Bibliothek durchsuchen';

  @override
  String get planNewStarterTitle => 'Mit einem integrierten Plan starten';

  @override
  String get planNewStarterSubtitle =>
      'Wähle einen bewährten Trainingsplan – wir planen ihn ab deinem Startdatum; du kannst ihn danach anpassen.';

  @override
  String get planNewStarterButton => 'Startpläne durchsuchen';

  @override
  String get planNewStarterCreating => 'Wird erstellt…';

  @override
  String get planNewStarterPickerTitle => 'Startplan wählen';

  @override
  String get planNewStarterPickerCancel => 'Abbrechen';

  @override
  String planNewStarterCreateFailed(String error) {
    return 'Dieser Plan konnte nicht erstellt werden: $error';
  }

  @override
  String get planNewStarterC25k => 'Couch-to-5K (Anfänger Geh-Lauf)';

  @override
  String get planNewStarterHalf12 => 'Halbmarathon – 12 Wochen';

  @override
  String get planNewStarterMarathon16 => 'Marathon – 16 Wochen';

  @override
  String get planDetailTimeoutError =>
      'Zeitüberschreitung der Verbindung. Prüfe dein Netzwerk und versuche es erneut.';

  @override
  String get planDetailLoadError =>
      'Dieser Plan konnte nicht geladen werden. Tippe auf Wiederholen.';

  @override
  String get planDetailNotFound => 'Plan nicht gefunden.';

  @override
  String get planDetailLongestLongRun => 'Längster langer Lauf';

  @override
  String get planDetailPublishTooltip => 'Als Vereinsvorlage veröffentlichen';

  @override
  String planDetailDaysPerWeek(int count) {
    return '$count Tage/Wo.';
  }

  @override
  String get planDetailCurrentWeek => 'Diese Woche';

  @override
  String get planDetailToday => 'HEUTE';

  @override
  String get planDetailCompleted => 'Erledigt';

  @override
  String planDetailWeek(int number) {
    return 'Woche $number';
  }

  @override
  String planDetailDriftOverFlag(int pct) {
    return 'Diese Woche $pct% über Plan — nimm an den lockeren Tagen zurück, damit du kein Müdigkeitsloch gräbst.';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return 'Diese Woche $pct% unter Plan — der geplante Umfang treibt die Anpassung.';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      'Du hast den Long Run dieser Woche verpasst — hol ihn nach, wenn du kannst. Das ist die wichtigste Einheit.';

  @override
  String get planDetailMissedLongTaper =>
      'Du hast einen Long Run verpasst, aber du tapest — lass ihn aus und bleib frisch für den Wettkampf.';

  @override
  String get planDetailMissedLongRecovery =>
      'Du hast einen Long Run verpasst — verzichte auf das Nachholen. Eine Entlastungswoche steht an und dein Körper nutzt die Ruhe.';

  @override
  String get planDetailReplan => 'Restliche Wochen neu planen';

  @override
  String get planDetailAdaptiveReplan => 'Adaptive Neuplanung';

  @override
  String get planDetailAdaptiveOnTrack =>
      'Deine letzten Wochen sind im Plan – keine Anpassung nötig.';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      'Du bist zuletzt vom Plan abgewichen, aber es gibt gerade keine sichere Anpassung.';

  @override
  String get planDetailAdaptiveFitnessHeld =>
      'Zurückgehalten – du trägst gerade Ermüdung, daher ist mehr Volumen nicht ratsam.';

  @override
  String get planDetailAdaptiveReasonUnder =>
      'seit mehreren Wochen unter deinem Plan';

  @override
  String get planDetailAdaptiveReasonOver =>
      'seit mehreren Wochen über deinem Plan';

  @override
  String get planDetailAdaptiveConfidenceHigh => 'hohe Konfidenz';

  @override
  String get planDetailAdaptiveConfidenceMedium => 'mittlere Konfidenz';

  @override
  String planDetailAdaptiveBadge(String reason, String confidence) {
    return 'Auf Basis eines Trends – du warst $reason ($confidence)';
  }

  @override
  String get planDetailReplanOnTrack => 'Dein Plan läuft — nichts anzupassen.';

  @override
  String planDetailReplanApplied(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Einheiten angepasst',
      one: '1 Einheit angepasst',
    );
    return '$_temp0';
  }

  @override
  String get planDetailReplanPreviewTitle => 'Vorgeschlagene Änderungen';

  @override
  String planDetailReplanMakeUp(String from, String to) {
    return 'Long Run $from → $to — verpassten Long Run nachholen';
  }

  @override
  String planDetailReplanEase(String from, String to) {
    return '$from → $to — nach Überlastung zurücknehmen';
  }

  @override
  String get planDetailReplanCancel => 'Abbrechen';

  @override
  String get planDetailReplanApply => 'Änderungen übernehmen';

  @override
  String get planDetailDuplicateWeek => 'Woche duplizieren';

  @override
  String planDetailDuplicateWeekDone(int n) {
    return 'Woche $n dupliziert';
  }

  @override
  String planDetailBulkFailed(String error) {
    return 'Plan konnte nicht aktualisiert werden: $error';
  }

  @override
  String get planDetailEditTooltip => 'Training bearbeiten';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'Deine Vereine konnten nicht geladen werden — prüfe dein Netzwerk.';

  @override
  String get planDetailPublishLoadClubsFailed =>
      'Deine Vereine konnten nicht geladen werden.';

  @override
  String get planDetailPublishNoClubs =>
      'Du musst Inhaber oder Admin eines Vereins sein, um eine Vorlage zu veröffentlichen.';

  @override
  String planDetailPublishSuccess(String name) {
    return '\"$name\" als Vereinsvorlage veröffentlicht.';
  }

  @override
  String planDetailPublishFailed(String error) {
    return 'Veröffentlichung fehlgeschlagen: $error';
  }

  @override
  String get planDetailPublishPickerTitle => 'Im Verein veröffentlichen';

  @override
  String get planDetailPublishPickerBody =>
      'Mitglieder des Vereins können diesen Plan als eigenen übernehmen.';

  @override
  String planDetailPublishPickerMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '$count Mitglied',
    );
    return '$_temp0';
  }

  @override
  String get planDetailPublishCancel => 'Abbrechen';

  @override
  String get workoutTimeoutError =>
      'Zeitüberschreitung der Verbindung. Prüfe dein Netzwerk und versuche es erneut.';

  @override
  String get workoutLoadError =>
      'Dieses Training konnte nicht geladen werden. Tippe auf Wiederholen.';

  @override
  String get workoutNotFound => 'Training nicht gefunden.';

  @override
  String get workoutMetricDistance => 'Distanz';

  @override
  String get workoutMetricDuration => 'Dauer';

  @override
  String get workoutMetricTargetPace => 'Zieltempo';

  @override
  String get workoutCompleted => 'Erledigt';

  @override
  String get workoutUnlink => 'Verknüpfung lösen';

  @override
  String get workoutUnlinkTitle => 'Lauf entkoppeln';

  @override
  String get workoutUnlinkBody =>
      'Den zugeordneten Lauf entkoppeln? Die Einheit gilt dann wieder als nicht erledigt.';

  @override
  String get workoutUnlinkError =>
      'Lauf konnte nicht entkoppelt werden. Versuche es erneut.';

  @override
  String get workoutSkipped => 'Übersprungen';

  @override
  String get workoutSkip => 'Diese Einheit überspringen';

  @override
  String get workoutUnskip => 'Überspringen aufheben';

  @override
  String get workoutSkipError =>
      'Überspringen konnte nicht aktualisiert werden. Versuche es erneut.';

  @override
  String get workoutRelink => 'Neu verknüpfen';

  @override
  String get workoutRelinkTitle => 'Anderen Lauf verknüpfen';

  @override
  String get workoutRelinkHint =>
      'Wähle einen Lauf in der Nähe des Workout-Datums, um ihn als diese Einheit zu zählen. Läufe, die bereits mit einem anderen Workout verknüpft sind, werden nicht angezeigt.';

  @override
  String get workoutRelinkLoading => 'Läufe werden gesucht…';

  @override
  String get workoutRelinkError =>
      'Läufe konnten nicht geladen werden. Versuche es erneut.';

  @override
  String get workoutRelinkEmpty =>
      'Keine passenden Läufe in der Nähe dieses Datums.';

  @override
  String get workoutRelinkCurrent => 'Aktuell';

  @override
  String get workoutStart => 'Training starten';

  @override
  String get workoutSectionNotes => 'Notizen';

  @override
  String get workoutSectionStructure => 'Struktur';

  @override
  String get workoutSectionHowTo => 'So läufst du es';

  @override
  String get workoutStructWarmup => 'Aufwärmen';

  @override
  String get workoutStructRepeats => 'Wiederholungen';

  @override
  String get workoutStructSteady => 'Gleichmäßig';

  @override
  String get workoutStructCooldown => 'Abkühlen';

  @override
  String workoutStructWarmupValue(String distance) {
    return '$distance @ locker';
  }

  @override
  String workoutStructCooldownValue(String distance) {
    return '$distance @ locker';
  }

  @override
  String get workoutAdviceEasy =>
      'Plaudertempo. Wenn du dich nicht unterhalten kannst, läufst du zu schnell.';

  @override
  String get workoutAdviceLong =>
      'Bleib entspannt. Achte auf gleichmäßiges Atmen. Lass 10 % der Distanz weg, wenn das Wetter schlecht ist oder du Muskelkater hast — aber lass es nicht ausfallen.';

  @override
  String get workoutAdviceTempo =>
      '„Angenehm hart“. Du solltest das Gefühl haben, das Tempo bei höchster Anstrengung etwa eine Stunde halten zu können, aber nicht länger.';

  @override
  String get workoutAdviceInterval =>
      'Laufe die Wiederholungen so hart, dass sich die letzte wie die erste anfühlt. Wähle kein Tempo, das du nur zwei oder drei Wiederholungen halten kannst.';

  @override
  String get workoutAdviceMarathonPace =>
      'Halte exakt das Ziel-Marathontempo. Das ist eine Generalprobe — nicht schneller, nicht langsamer.';

  @override
  String get workoutAdviceWalkRun =>
      'Wechsle in den getakteten Intervallen zwischen lockerem Laufen und Gehen. Die Gehpausen gehören zum Training — nimm sie auch, wenn du dich frisch fühlst.';

  @override
  String get workoutAdviceRace =>
      'Vertraue dem Plan. Jage keiner Bestzeit auf der ersten Meile hinterher.';

  @override
  String get workoutAdviceRest =>
      'Ruhetag — wenn du dich bewegen musst, geh spazieren oder dehne dich.';

  @override
  String get coachTitle => 'Coach';

  @override
  String get coachNewConversation => 'Neue Unterhaltung';

  @override
  String get coachConsentHeadline => 'Bevor du mit dem Coach chattest';

  @override
  String get coachConsentIntro =>
      'Um dir fundierte Ratschläge zu geben, leitet der Coach einen Teil deiner Trainingsdaten an Anthropic weiter, unseren KI-Modellanbieter in den USA. Dieser Teil umfasst:';

  @override
  String get coachConsentBulletProfile =>
      'Dein Geburtsdatum, Geschlecht und HF-Zonen, falls festgelegt.';

  @override
  String get coachConsentBulletRuns => 'Ein Ausschnitt deiner letzten Läufe.';

  @override
  String get coachConsentBulletPlan =>
      'Den aktiven Trainingsplan, den du ausgewählt hast.';

  @override
  String get coachConsentBulletMessages =>
      'Die Chatnachrichten, die du im Bildschirm unten eingibst.';

  @override
  String get coachConsentProcessing =>
      'Anthropic verarbeitet die Daten im Auftrag von Threkir gemäß ihren Auftragsverarbeitungsbedingungen; standardmäßig trainieren sie ihre Modelle nicht mit Threkir-Kundendaten. Alle Details — einschließlich Übermittlungsmechanismus, Speicherdauer und deinen Widerrufsrechten — findest du in unserer Datenschutzerklärung.';

  @override
  String get coachConsentAction =>
      'Tippe auf „Ich stimme zu“, um fortzufahren. Tippe auf Abbrechen, um die Seite zu verlassen, ohne Daten zu senden.';

  @override
  String get coachConsentCancel => 'Abbrechen';

  @override
  String get coachConsentAccept => 'Ich stimme zu — Coach starten';

  @override
  String get coachConsentSaving => 'Einwilligung wird gespeichert…';

  @override
  String get coachNoPlanOption => 'Kein Plan (nur letzte Läufe)';

  @override
  String coachPlanActive(String name) {
    return '$name · aktiv';
  }

  @override
  String coachPlanDone(String name) {
    return '$name · fertig';
  }

  @override
  String get coachNewChatTooltip => 'Neuer Chat';

  @override
  String get coachHistoryTooltip => 'Chatverlauf';

  @override
  String get coachNewChat => 'Neuer Chat';

  @override
  String coachActiveThread(String suffix) {
    return 'Aktiv$suffix';
  }

  @override
  String get coachArchiveTapToView =>
      'Zum Ansehen tippen · zum Löschen wischen';

  @override
  String get coachContextNoPlan => 'Kein Plan';

  @override
  String coachContextPlanWeeks(String name, int weeks) {
    return '$name · $weeks Wo.';
  }

  @override
  String get coachContextNoRuns => 'Keine Läufe';

  @override
  String get coachContextLast => 'Letzte';

  @override
  String get coachContextHr => 'HF';

  @override
  String coachContextWeeklyGoal(String km) {
    return '$km km/Wo.';
  }

  @override
  String coachArchiveBanner(String label) {
    return 'Archiv ansehen · $label · schreibgeschützt';
  }

  @override
  String get coachBackToActive => 'Zurück zu aktiv';

  @override
  String get coachLimitReachedPro => 'Tageslimit erreicht. Komm morgen wieder.';

  @override
  String get coachLimitReachedFree =>
      'Tageslimit erreicht. Pro hat ein höheres Limit — upgrade in den Einstellungen.';

  @override
  String coachMessagesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'noch $count Nachrichten heute',
      one: 'noch $count Nachricht heute',
    );
    return '$_temp0';
  }

  @override
  String get coachEmptyPromptPlan =>
      'Frage nach dem heutigen Training, deinem Tempo oder wie deine letzten Läufe zum Plan passen.';

  @override
  String get coachEmptyPromptNoPlan =>
      'Frage nach deinen letzten Läufen, dem Tempo lockerer Läufe oder Trainingsgrundlagen.';

  @override
  String get coachSuggestPlanRest =>
      'Soll ich morgen laufen oder einen Ruhetag einlegen?';

  @override
  String get coachSuggestPlanOnTrack => 'Bin ich auf Kurs für meine Zielzeit?';

  @override
  String get coachSuggestPlanLongRun =>
      'Warum ist der lange Lauf dieser Woche wichtig?';

  @override
  String get coachSuggestPlanToday =>
      'Worauf sollte ich beim heutigen Training achten?';

  @override
  String get coachSuggestNoPlanLastRun => 'Wie war mein letzter Lauf?';

  @override
  String get coachSuggestNoPlanEasyPace =>
      'Welches Tempo sollten meine lockeren Läufe haben?';

  @override
  String get coachSuggestNoPlanWeekOff =>
      'Ich bin eine Woche nicht gelaufen — was soll ich tun?';

  @override
  String get coachSuggestNoPlanTempo => 'Was ist ein Tempolauf?';

  @override
  String get coachEditCancel => 'Abbrechen';

  @override
  String get coachEditSaveResend => 'Speichern & erneut senden';

  @override
  String get coachActionCopy => 'Kopieren';

  @override
  String get coachActionEdit => 'Bearbeiten';

  @override
  String get coachActionRegenerate => 'Neu generieren';

  @override
  String get coachActionHelpful => 'Hilfreich';

  @override
  String get coachActionNotHelpful => 'Nicht hilfreich';

  @override
  String get coachComposerHintLimit => 'Tageslimit erreicht';

  @override
  String get coachComposerHint => 'Frag den Coach…';

  @override
  String get coachArchiveTitle => 'Neue Unterhaltung beginnen?';

  @override
  String get coachArchiveBody =>
      'Der aktuelle Chat wird in den Verlauf verschoben. Du kannst ihn über die Seitenleiste wieder aufrufen.';

  @override
  String get coachArchiveCancel => 'Abbrechen';

  @override
  String get coachArchiveConfirm => 'Neuer Chat';

  @override
  String get coachSignInFirst => 'Bitte melde dich zuerst an.';

  @override
  String get coachSessionExpired =>
      'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.';

  @override
  String coachDailyLimitError(int limit) {
    return 'Tageslimit erreicht ($limit Nachrichten). Komm morgen wieder!';
  }

  @override
  String coachGenericError(int code) {
    return 'Coach-Fehler ($code)';
  }

  @override
  String get coachTransportError =>
      'Coach konnte nicht erreicht werden. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get coachStreamFailed => 'Stream fehlgeschlagen';

  @override
  String coachNewConversationFailed(String error) {
    return 'Neue Unterhaltung konnte nicht gestartet werden: $error';
  }

  @override
  String coachOpenArchiveFailed(String error) {
    return 'Archiv konnte nicht geöffnet werden: $error';
  }

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Archiv konnte nicht gelöscht werden: $error';
  }

  @override
  String get coachCopied => 'In die Zwischenablage kopiert';

  @override
  String get settingsAccountTitle => 'Konto';

  @override
  String get settingsAccountBackendNotConfigured =>
      'Backend nicht konfiguriert';

  @override
  String get settingsAccountSignOutFailed =>
      'Abmeldung fehlgeschlagen — prüfe deine Verbindung';

  @override
  String get settingsAccountChangePassword => 'Passwort ändern';

  @override
  String get settingsAccountNewPassword => 'Neues Passwort';

  @override
  String get settingsAccountConfirm => 'Bestätigen';

  @override
  String get settingsAccountCancel => 'Abbrechen';

  @override
  String get settingsAccountSave => 'Speichern';

  @override
  String get settingsAccountPasswordTooShort =>
      'Das Passwort muss mindestens 8 Zeichen lang sein';

  @override
  String get settingsAccountPasswordsMismatch =>
      'Die Passwörter stimmen nicht überein';

  @override
  String get settingsAccountPasswordUpdated => 'Passwort aktualisiert';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Passwort konnte nicht aktualisiert werden: $error';
  }

  @override
  String get settingsAccountDeleteTitle => 'Konto löschen?';

  @override
  String get settingsAccountDeleteBody =>
      'Dadurch werden deine Läufe, Routen und dein Profil dauerhaft vom Server entfernt. Lokale Gerätedaten bleiben erhalten, sofern du dich nicht als neuer Nutzer anmeldest. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get settingsAccountDeleteChallengeText =>
      'Gib „DELETE“ ein, um zu bestätigen';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return 'Gib deine E-Mail ($email) ein, um zu bestätigen';
  }

  @override
  String get settingsAccountDelete => 'Löschen';

  @override
  String get settingsAccountDeleteSignInFirst =>
      'Melde dich zuerst an, um dein Konto zu löschen.';

  @override
  String get settingsAccountDeleted => 'Konto gelöscht';

  @override
  String get settingsAccountCoachConsentWithdraw =>
      'Coach-Einwilligung widerrufen';

  @override
  String get settingsAccountCoachConsentActive =>
      'Hindere den Coach daran, deine Trainingsdaten zu verwenden. Du kannst jederzeit erneut einwilligen.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Coach-Einwilligung widerrufen.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Widerruf fehlgeschlagen: $error';
  }

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'Kontolöschung fehlgeschlagen: $error';
  }

  @override
  String get settingsAccountNoRunsToExport => 'Keine Läufe zum Exportieren.';

  @override
  String get settingsAccountCsvShareText => 'Run-App — Läufe-Export';

  @override
  String settingsAccountCsvExportFailed(Object error) {
    return 'CSV-Export fehlgeschlagen: $error';
  }

  @override
  String get settingsAccountBackupSignInFirst =>
      'Melde dich zuerst an, um deine Läufe zu sichern.';

  @override
  String get settingsAccountBackupPreparing => 'Backup wird vorbereitet…';

  @override
  String get settingsAccountBackupShareText => 'Run-App-Backup';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'Backup fehlgeschlagen: $error';
  }

  @override
  String get settingsAccountRestoreUnavailable =>
      'Backup-Dienst nicht verfügbar.';

  @override
  String get settingsAccountRestoreTitle => 'Aus Backup wiederherstellen?';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'Du bist nicht angemeldet. Läufe werden auf diesem Gerät wiederhergestellt und beim nächsten Anmelden mit deinem Konto synchronisiert.';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'Dies fügt Läufe und Routen hinzu oder überschreibt sie anhand übereinstimmender IDs im Backup. Läufe oder Routen, die nicht im Backup enthalten sind, werden nicht gelöscht.';

  @override
  String get settingsAccountRestore => 'Wiederherstellen';

  @override
  String get settingsAccountRestoring => 'Wird wiederhergestellt…';

  @override
  String settingsAccountRestoreDone(
    int runs,
    int tracks,
    int routes,
    String warnings,
  ) {
    return '$runs Läufe · $tracks Tracks · $routes Routen wiederhergestellt$warnings';
  }

  @override
  String settingsAccountRestoreWarningsSuffix(int count) {
    return ' · $count Warnungen';
  }

  @override
  String settingsAccountRestoreFailed(Object error) {
    return 'Wiederherstellung fehlgeschlagen: $error';
  }

  @override
  String get settingsAccountOfflineMode => 'Offline-Modus';

  @override
  String get settingsAccountSignedInSync =>
      'Angemeldet — Läufe werden synchronisiert';

  @override
  String get settingsAccountSignInToSync =>
      'Melde dich an, um Läufe geräteübergreifend zu synchronisieren';

  @override
  String get settingsAccountSignOut => 'Abmelden';

  @override
  String get settingsAccountSignIn => 'Anmelden';

  @override
  String get settingsAccountAvatar => 'Profilfoto';

  @override
  String get settingsAccountAvatarHint => 'JPEG, PNG oder WebP, bis zu 2 MB.';

  @override
  String get settingsAccountAvatarRemove => 'Foto entfernen';

  @override
  String get settingsAccountAvatarSaved => 'Profilfoto aktualisiert.';

  @override
  String get settingsAccountAvatarRemoved => 'Profilfoto entfernt.';

  @override
  String get settingsAccountAvatarUnsupported =>
      'Nicht unterstütztes Bild — wähle JPEG, PNG oder WebP.';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return 'Foto konnte nicht aktualisiert werden: $error';
  }

  @override
  String get settingsAccountViewProfile => 'Profil ansehen';

  @override
  String get settingsAccountViewProfileSubtitle =>
      'Deine Läufe, Follower, Gefolgte, Benachrichtigungen';

  @override
  String get settingsAccountGuidedRuns => 'Geführte Läufe';

  @override
  String get settingsAccountGuidedRunsSubtitle =>
      'Skriptgesteuerte Workouts mit Coach-Stimme und TTS-Hinweisen';

  @override
  String get settingsAccountPrivacyZones => 'Datenschutzzonen';

  @override
  String get settingsAccountPrivacyZonesSubtitle =>
      'Anfang/Ende öffentlicher Tracks in Wohnungsnähe abschneiden';

  @override
  String get settingsAccountTrustedContacts => 'Vertrauenskontakte';

  @override
  String get settingsAccountTrustedContactsSubtitle =>
      'Benannte Personen für die geplante Überfälligkeits- / Notfall-Funktion';

  @override
  String get settingsAccountSendErrorReports => 'Fehlerberichte senden';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Anonymisierte Absturz- + Fehlerdaten an Sentry (USA). Deaktivieren, um die Einwilligung zu widerrufen. Gilt beim nächsten Start.';

  @override
  String get settingsAccountErrorReportingEnabled =>
      'Fehlerberichte aktiviert — App neu starten, um sie anzuwenden.';

  @override
  String get settingsAccountErrorReportingDisabled =>
      'Fehlerberichte deaktiviert — App neu starten, um sie anzuwenden.';

  @override
  String get settingsAccountImport => 'Aus einer anderen App importieren';

  @override
  String get settingsAccountImportSubtitle => 'Strava, GPX, TCX';

  @override
  String get settingsAccountFullBackup => 'Vollständiges Backup';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'Jeder Lauf mit GPS-Track sowie Routen, Profil und Einstellungen. Wiederherstellbar im Web oder auf Android.';

  @override
  String get settingsAccountExportCsv => 'Läufe als CSV exportieren';

  @override
  String get settingsAccountExportCsvSubtitle =>
      'Datum, Distanz, Dauer, Tempo, Quelle — eine Zeile pro Lauf. Gleiche Form wie der DSGVO-Export im Web.';

  @override
  String get settingsAccountRestoreTile => 'Aus Backup wiederherstellen';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      'Wähle ein zuvor gespeichertes .zip-Backup.';

  @override
  String get settingsAccountDeleteAccount => 'Konto löschen';

  @override
  String get settingsAccountDeleteAccountSubtitle =>
      'Entfernt Serverdaten dauerhaft';

  @override
  String get integrationsTitle => 'Integrationen';

  @override
  String get integrationsJustNow => 'gerade eben';

  @override
  String integrationsMinutesAgo(int minutes) {
    return 'vor $minutes Min.';
  }

  @override
  String integrationsHoursAgo(int hours) {
    return 'vor $hours Std.';
  }

  @override
  String integrationsDaysAgo(int days) {
    return 'vor $days T.';
  }

  @override
  String integrationsWeeksAgo(int weeks) {
    return 'vor $weeks Wo.';
  }

  @override
  String integrationsCouldNotOpen(Object error) {
    return 'Konnte nicht geöffnet werden: $error';
  }

  @override
  String get integrationsStravaBrowserHint =>
      'Schließe die Strava-Anmeldung in deinem Browser ab, kehre dann hierher zurück und ziehe zum Aktualisieren.';

  @override
  String get integrationsStravaCancelled => 'Strava-Anmeldung abgebrochen.';

  @override
  String integrationsStravaSignInFailed(Object error) {
    return 'Strava-Anmeldung fehlgeschlagen: $error';
  }

  @override
  String get integrationsStravaCsrfMismatch =>
      'Strava-Anmeldung abgelehnt: CSRF-State stimmt nicht überein. Bitte erneut versuchen.';

  @override
  String integrationsStravaConnectFailed(String error) {
    return 'Strava-Verbindung fehlgeschlagen: $error';
  }

  @override
  String get integrationsStravaConnected => 'Strava verbunden.';

  @override
  String integrationsSyncResult(int imported, int skipped) {
    return 'Synchronisiert. $imported neu, $skipped bereits vorhanden.';
  }

  @override
  String integrationsSyncFailed(Object error) {
    return 'Synchronisierung fehlgeschlagen: $error';
  }

  @override
  String get integrationsStravaDisconnectTitle => 'Strava trennen?';

  @override
  String get integrationsStravaDisconnectBody =>
      'Künftige Aktivitäten werden nicht mehr automatisch synchronisiert. Bereits importierte Läufe bleiben in deiner Historie.';

  @override
  String get integrationsCancel => 'Abbrechen';

  @override
  String get integrationsDisconnect => 'Trennen';

  @override
  String get integrationsStravaDisconnected => 'Strava getrennt.';

  @override
  String integrationsDisconnectFailed(Object error) {
    return 'Trennen fehlgeschlagen: $error';
  }

  @override
  String get integrationsParkrunTitle => 'parkrun-Ergebnisse importieren';

  @override
  String get integrationsParkrunBody =>
      'Gib deine parkrun-Athletennummer ein (z. B. A123456). Wir holen deine Zielverlauf und fügen neue Ergebnisse zu deiner Läufe-Liste hinzu.';

  @override
  String get integrationsParkrunFieldLabel => 'Athletennummer';

  @override
  String get integrationsImport => 'Importieren';

  @override
  String get integrationsParkrunImporting =>
      'parkrun-Ergebnisse werden importiert…';

  @override
  String integrationsParkrunImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count parkrun-Ergebnisse importiert.',
      one: '$count parkrun-Ergebnis importiert.',
    );
    return '$_temp0';
  }

  @override
  String get integrationsParkrunNoneNew =>
      'Keine neuen parkrun-Ergebnisse seit dem letzten Import.';

  @override
  String integrationsImportFailed(Object error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get integrationsStravaName => 'Strava';

  @override
  String get integrationsStravaConnectSubtitle =>
      'Verbinden, um Aktivitäten automatisch zu synchronisieren';

  @override
  String get integrationsStravaWaitingFirstSync =>
      'Verbunden · wartet auf erste Synchronisierung';

  @override
  String integrationsStravaLastSync(String time) {
    return 'Verbunden · letzte Synchronisierung $time';
  }

  @override
  String get integrationsSyncNow => 'Jetzt synchronisieren';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Ergebnisse per Athletennummer importieren';

  @override
  String get integrationsSignInTitle => 'Anmelden, um Dienste zu verbinden';

  @override
  String get integrationsSignInSubtitle =>
      'Strava + parkrun erfordern ein Konto, damit synchronisierte Aktivitäten in deiner Historie landen.';

  @override
  String get integrationsHealthConnectTitle =>
      'Läufe in Health Connect schreiben';

  @override
  String get integrationsHealthConnectSubtitle =>
      'Sende jeden abgeschlossenen Lauf an Health Connect, damit er in Google Fit, Samsung Health, Fitbit und anderen erscheint.';

  @override
  String get integrationsHealthConnectDenied =>
      'Health-Connect-Berechtigung nicht erteilt — Läufe werden nicht geschrieben.';

  @override
  String integrationsHrPairFailed(Object error) {
    return 'Kopplung fehlgeschlagen: $error';
  }

  @override
  String get integrationsHrTitle => 'Herzfrequenzmesser';

  @override
  String get integrationsHrChecking => 'Wird geprüft…';

  @override
  String integrationsHrPaired(String name) {
    return 'Gekoppelt: $name';
  }

  @override
  String get integrationsHrNotPaired =>
      'Kein Gurt gekoppelt — zum Suchen tippen';

  @override
  String get integrationsHrForget => 'Entfernen';

  @override
  String get integrationsHrForgetConfirm =>
      'Diesen Herzfrequenzmesser entfernen? Du musst ihn neu koppeln, um ihn während eines Laufs zu verwenden.';

  @override
  String get integrationsHrScanTitle => 'Nach Herzfrequenzmesser suchen';

  @override
  String get integrationsHrScanHint =>
      'Wecke deinen Gurt / Brustgurt. Apps benötigen üblicherweise 3–8 Sekunden.';

  @override
  String get integrationsHrScanEmpty =>
      'Keine Gurte gefunden. Stelle sicher, dass er in der Nähe und aktiv ist.';

  @override
  String integrationsHrRssi(int rssi) {
    return 'RSSI $rssi dBm';
  }

  @override
  String get integrationsTreadmillTitle => 'Laufband';

  @override
  String get integrationsTreadmillChecking => 'Wird geprüft…';

  @override
  String integrationsTreadmillPaired(String name) {
    return 'Gekoppelt: $name';
  }

  @override
  String get integrationsTreadmillNotPaired =>
      'Kein Laufband gekoppelt – zum Suchen tippen';

  @override
  String get integrationsTreadmillForget => 'Entfernen';

  @override
  String get integrationsTreadmillForgetConfirm =>
      'Dieses Laufband entfernen? Du musst es neu koppeln, um es während eines Laufs zu verwenden.';

  @override
  String get integrationsTreadmillScanTitle => 'Nach Laufband suchen';

  @override
  String get integrationsTreadmillScanHint =>
      'Stelle sicher, dass das Bluetooth des Laufbands aktiv und das Band wach ist. Die Suche dauert 3–8 Sekunden.';

  @override
  String get integrationsTreadmillScanEmpty =>
      'Keine Laufbänder gefunden. Stelle sicher, dass es Bluetooth (FTMS) unterstützt und in der Nähe ist.';

  @override
  String integrationsTreadmillPairFailed(Object error) {
    return 'Kopplung fehlgeschlagen: $error';
  }

  @override
  String integrationsTreadmillLiveSpeed(String speed) {
    return '$speed km/h';
  }

  @override
  String get proTitle => 'Pro & Support';

  @override
  String proCouldNotOpen(Object error) {
    return 'Konnte nicht geöffnet werden: $error';
  }

  @override
  String get proWelcome => 'Willkommen bei Pro! Deine Vorteile werden geladen…';

  @override
  String get proPurchaseFailed =>
      'Kauf fehlgeschlagen. Versuche es später erneut.';

  @override
  String get proRestoreNeedsSignIn =>
      'Zum Wiederherstellen musst du angemeldet sein und RevenueCat konfiguriert haben. Verwalte dein Abo stattdessen auf der Web-Upgrade-Seite.';

  @override
  String get proRestored => 'Dein Pro-Abo wurde wiederhergestellt.';

  @override
  String get proRestoreNone =>
      'Keine aktiven Käufe für dieses Store-Konto gefunden.';

  @override
  String get proRestoreFailed =>
      'Wiederherstellung fehlgeschlagen. Versuche es später erneut.';

  @override
  String get proRestoreUnavailable =>
      'Wiederherstellung in diesem Build nicht verfügbar.';

  @override
  String proSubscribeTitle(String price) {
    return 'Pro abonnieren — $price/Monat';
  }

  @override
  String get proSubscribeSubtitleConfigured =>
      'Unbegrenzter KI-Coach + bevorzugte Verarbeitung. Verlängert sich monatlich automatisch, bis es unter Einstellungen → Abonnements gekündigt wird.';

  @override
  String get proSubscribeSubtitleWeb =>
      'Öffnet das Abo-Portal in deinem Browser. Verlängert sich monatlich automatisch bis zur Kündigung.';

  @override
  String get proRegionalNote =>
      'Abrechnung in US-Dollar. Die Verfügbarkeit hängt von deinem Land und deiner Zahlungsmethode ab — einige Regionen können von unserem Zahlungsdienstleister nicht bedient werden.';

  @override
  String get proRestorePurchases => 'Käufe wiederherstellen';

  @override
  String get proRestorePurchasesSubtitle =>
      'Käufe von einer früheren Installation oder einem anderen Gerät erneut verknüpfen';

  @override
  String get proManageSubscription => 'Abonnement verwalten';

  @override
  String get proManageSubscriptionSubtitle =>
      'Kündigen, Tarif ändern oder Zahlungsmethode aktualisieren';

  @override
  String get proSupport => 'Die App unterstützen';

  @override
  String get proSupportSubtitle => 'Einmalige Spende in deinem Browser';

  @override
  String get licensesTitle => 'Lizenzen';

  @override
  String get licensesVersion => 'Version';

  @override
  String get licensesOpenSource => 'Open-Source-Lizenzen';

  @override
  String get licensesOpenSourceSubtitle =>
      'Drittanbieter-Pakete, die mit dieser App gebündelt sind';

  @override
  String get devicesTitle => 'Geräte';

  @override
  String get devicesRenameTitle => 'Gerät umbenennen';

  @override
  String get devicesCancel => 'Abbrechen';

  @override
  String get devicesSave => 'Speichern';

  @override
  String devicesRenameFailed(Object error) {
    return 'Umbenennen fehlgeschlagen: $error';
  }

  @override
  String get devicesRemoveTitle => 'Gerät entfernen?';

  @override
  String get devicesRemoveBodyCurrent =>
      'Das ist das Gerät, das du gerade verwendest. Beim Entfernen werden die geräteweiten Voreinstellungs-Overrides gelöscht; das Gerät bleibt angemeldet.';

  @override
  String get devicesRemoveBodyOther =>
      'Entfernt den Geräteeintrag und alle geräteweiten Voreinstellungs-Overrides. Das Gerät bleibt angemeldet, bis es die App das nächste Mal öffnet.';

  @override
  String get devicesRemove => 'Entfernen';

  @override
  String devicesRemoveFailed(Object error) {
    return 'Entfernen fehlgeschlagen: $error';
  }

  @override
  String devicesSaveFailed(Object error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get devicesLoadError => 'Geräte konnten nicht geladen werden.';

  @override
  String get devicesEmpty =>
      'Noch keine Geräte — sie werden registriert, sobald ein Gerät die App zum ersten Mal angemeldet öffnet.';

  @override
  String get devicesThisDevice => 'Dieses Gerät';

  @override
  String devicesLastSeen(String time) {
    return 'Zuletzt gesehen $time';
  }

  @override
  String devicesOverrideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Overrides',
      one: '$count Override',
    );
    return '$_temp0';
  }

  @override
  String get devicesJustNow => 'gerade eben';

  @override
  String devicesMinutesAgo(int minutes) {
    return 'vor $minutes Min.';
  }

  @override
  String devicesHoursAgo(int hours) {
    return 'vor $hours Std.';
  }

  @override
  String devicesDaysAgo(int days) {
    return 'vor $days T.';
  }

  @override
  String get devicesRename => 'Umbenennen';

  @override
  String get devicesEditOverrides => 'Overrides bearbeiten…';

  @override
  String get devicesEveryKeySet =>
      'Jeder überschreibbare Schlüssel ist bereits gesetzt; entferne einen, bevor du einen weiteren hinzufügst.';

  @override
  String get devicesOverridesSheetTitle => 'Geräteweite Overrides';

  @override
  String get devicesOverridesSheetDesc =>
      'Diese Schlüssel überschreiben die universellen Einstellungen nur auf diesem Gerät.';

  @override
  String get devicesNoOverrides => 'Keine Overrides auf diesem Gerät.';

  @override
  String get devicesAddOverride => 'Override hinzufügen';

  @override
  String get devicesPickKey => 'Schlüssel auswählen';

  @override
  String get devicesEnterWholeNumber => 'Gib eine ganze Zahl ein.';

  @override
  String get devicesEnterNumber => 'Gib eine Zahl ein (z. B. 0,8).';

  @override
  String get devicesValue => 'Wert';

  @override
  String get devicesBack => 'Zurück';

  @override
  String get devicesAdd => 'Hinzufügen';

  @override
  String get devicesKeyPreferredUnitLabel => 'Bevorzugte Einheit';

  @override
  String get devicesKeyPreferredUnitHint => 'Distanzeinheit für alle Anzeigen.';

  @override
  String get devicesKeyDefaultActivityLabel => 'Standardaktivität';

  @override
  String get devicesKeyDefaultActivityHint =>
      'Vorausgewählte Aktivität auf dem Startbildschirm.';

  @override
  String get devicesKeyMapStyleLabel => 'Kartenstil';

  @override
  String get devicesKeyMapStyleHint => 'MapLibre-Stil für die Kartenansicht.';

  @override
  String get devicesKeyPaceFormatLabel => 'Tempoformat';

  @override
  String get devicesKeyPaceFormatHint => 'Anzeigeformat für das Tempo.';

  @override
  String get devicesKeyVoiceFeedbackLabel => 'Sprachfeedback';

  @override
  String get devicesKeyVoiceFeedbackHint =>
      'Tempo-/Distanzansagen während eines Laufs sprechen.';

  @override
  String get devicesKeyVoiceIntervalLabel => 'Sprachfeedback-Intervall (km)';

  @override
  String get devicesKeyVoiceIntervalHint =>
      'Distanz zwischen den gesprochenen Ansagen.';

  @override
  String get devicesKeyHapticLabel => 'Haptisches Feedback';

  @override
  String get devicesKeyHapticHint =>
      'Vibration bei Runden- und Tempozonen-Wechseln.';

  @override
  String get devicesKeyKeepScreenOnLabel => 'Bildschirm anlassen';

  @override
  String get devicesKeyKeepScreenOnHint =>
      'OS-Auto-Dimmen während der Aufzeichnung deaktivieren.';

  @override
  String get gearTitle => 'Ausrüstung';

  @override
  String get gearAddGear => 'Ausrüstung hinzufügen';

  @override
  String get gearDeleteTitle => 'Ausrüstung löschen?';

  @override
  String gearDeleteBody(String name) {
    return '„$name“ löschen? Die Kilometerhistorie vergangener Läufe geht verloren. Stattdessen ausmustern, um die Aufzeichnungen zu behalten.';
  }

  @override
  String get gearCancel => 'Abbrechen';

  @override
  String get gearDelete => 'Löschen';

  @override
  String get gearDeletedOffline =>
      'Lokal gelöscht — wird bei erneuter Verbindung synchronisiert.';

  @override
  String gearAttached(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name mit $count Läufen verknüpft.',
      one: '$name mit $count Lauf verknüpft.',
    );
    return '$_temp0';
  }

  @override
  String gearOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Offline — $count Änderungen in der Warteschlange, zeige zwischengespeicherte Ausrüstung.',
      one:
          'Offline — $count Änderung in der Warteschlange, zeige zwischengespeicherte Ausrüstung.',
    );
    return '$_temp0';
  }

  @override
  String get gearOfflineCached =>
      'Offline — zeige zwischengespeicherte Ausrüstung.';

  @override
  String get gearShoes => 'Schuhe';

  @override
  String get gearBikes => 'Fahrräder';

  @override
  String get gearRetired => 'AUSGEMUSTERT';

  @override
  String get gearEmptyShoes => 'Noch keine Schuhe';

  @override
  String get gearEmptyBikes => 'Noch keine Fahrräder';

  @override
  String get gearEmptySubtitle =>
      'Füge ein Paar hinzu, um die Kilometer zu verfolgen und Erinnerungen zum Ausmustern zu erhalten.';

  @override
  String gearRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe',
      one: '$count Lauf',
    );
    return '$_temp0';
  }

  @override
  String get gearWearDue => 'Bald ersetzen';

  @override
  String get gearWearWorn => 'Ersatzdistanz überschritten';

  @override
  String get gearRetire => 'Ausmustern';

  @override
  String get gearRestore => 'Wiederherstellen';

  @override
  String get privacyZonesTitle => 'Datenschutzzonen';

  @override
  String get privacyZonesSaved => 'Datenschutzzonen gespeichert.';

  @override
  String privacyZonesSaveFailed(Object error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return 'Standort nicht verfügbar: $error';
  }

  @override
  String get privacyZonesSave => 'Speichern';

  @override
  String get privacyZonesLocateMe => 'Mich orten';

  @override
  String get privacyZonesHint =>
      'Tippe auf die Karte, um eine Zone hinzuzufügen. Tracks auf öffentlichen Flächen werden am Anfang und Ende über den Zonenradius hinaus abgeschnitten.';

  @override
  String get privacyZonesSearchHint => 'Orte suchen…';

  @override
  String get privacyZonesRadius => 'Radius';

  @override
  String privacyZonesRadiusMeters(int meters) {
    return '$meters m';
  }

  @override
  String privacyZonesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zonen — tippe auf eine Markierung, um sie zu entfernen.',
      one: '$count Zone — tippe auf eine Markierung, um sie zu entfernen.',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'Alle löschen';

  @override
  String get privacyZonesRemoveTitle => 'Datenschutzzone entfernen?';

  @override
  String get privacyZonesRemoveBody =>
      'Diese Zone verbirgt deine Strecken in der Nähe bei öffentlichen Freigaben. Beim Entfernen wird dieser Bereich wieder sichtbar.';

  @override
  String get privacyZonesRemoveSemantics => 'Datenschutzzone entfernen';

  @override
  String get privacyZonesClearAllTitle => 'Alle Datenschutzzonen löschen?';

  @override
  String get privacyZonesClearAllBody =>
      'Dadurch werden alle Zonen entfernt und alle diese Bereiche bei öffentlichen Freigaben wieder sichtbar.';

  @override
  String get prefsTitle => 'Einstellungen';

  @override
  String get prefsUnitMetric => 'km, m';

  @override
  String get prefsUnitImperial => 'mi, ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · mit deinen anderen Geräten synchronisiert';
  }

  @override
  String get prefsClear => 'Löschen';

  @override
  String get prefsCancel => 'Abbrechen';

  @override
  String get prefsSave => 'Speichern';

  @override
  String get prefsSplitInterval => 'Split-Intervall';

  @override
  String get prefsSplitIntervalDefault => 'Standard';

  @override
  String get prefsSplitIntervalDefaultSubtitle =>
      'Standard (1 km beim Laufen, 5 km beim Radfahren)';

  @override
  String get prefsLivePaceAlert => 'Live-Tempowarnung';

  @override
  String get prefsLivePaceAlertMin => 'Min';

  @override
  String get prefsLivePaceAlertSec => 'Sek';

  @override
  String get prefsLivePaceAlertOff =>
      'Aus — lege ein Tempo fest, um während eines Laufs gesprochene Warnungen zu erhalten';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — gesprochene Warnung während eines Laufs bei 30 s+ Abweichung';
  }

  @override
  String get prefsActivityRun => 'Laufen';

  @override
  String get prefsActivityWalk => 'Gehen';

  @override
  String get prefsActivityHike => 'Wandern';

  @override
  String get prefsActivityCycle => 'Radfahren';

  @override
  String get prefsPaceFormat => 'Tempoformat';

  @override
  String get prefsPaceFormatMinPerKm => 'Minuten pro km';

  @override
  String get prefsPaceFormatMinPerMi => 'Minuten pro Meile';

  @override
  String get prefsPaceFormatKph => 'km/h';

  @override
  String get prefsPaceFormatMph => 'mph';

  @override
  String get prefsWeightUnit => 'Gewichtseinheit';

  @override
  String get prefsWeightUnitKg => 'Kilogramm (kg)';

  @override
  String get prefsWeightUnitLbs => 'Pfund (lbs)';

  @override
  String get prefsNotSet => 'Nicht festgelegt';

  @override
  String prefsHrZonesSummary(String zones) {
    return '$zones bpm';
  }

  @override
  String prefsWeeklyGoalSummary(String distance, String unit) {
    return '$distance $unit / Woche';
  }

  @override
  String get prefsMapStyle => 'Kartenstil';

  @override
  String get prefsMapStyleStreets => 'Straßen';

  @override
  String get prefsMapStyleSatellite => 'Satellit';

  @override
  String get prefsMapStyleOutdoors => 'Outdoor';

  @override
  String get prefsMapStyleDark => 'Dunkel';

  @override
  String get prefsDefaultRunVisibility => 'Standard-Sichtbarkeit für Läufe';

  @override
  String get prefsCoachPersonality => 'Coach-Persönlichkeit';

  @override
  String get prefsCoachSupportive => 'Unterstützend';

  @override
  String get prefsCoachDrillSergeant => 'Drill-Sergeant';

  @override
  String get prefsCoachAnalytical => 'Analytisch';

  @override
  String get prefsSectionNotifications => 'Benachrichtigungen';

  @override
  String get prefsEmailNotifications => 'E-Mail-Benachrichtigungen';

  @override
  String get prefsEmailNotifAll => 'Alle';

  @override
  String get prefsEmailNotifImportant => 'Nur wichtige';

  @override
  String get prefsEmailNotifOff => 'Aus';

  @override
  String get prefsPushNotifications => 'Push-Benachrichtigungen';

  @override
  String get prefsPushNotifAll => 'Alle';

  @override
  String get prefsPushNotifImportant => 'Nur wichtige';

  @override
  String get prefsPushNotifOff => 'Aus';

  @override
  String get prefsEmailWeeklyDigest =>
      'Wöchentliche Zusammenfassung per E-Mail';

  @override
  String get prefsEmailWeeklyDigestHint =>
      'Abonniere eine wöchentliche Übersicht über dein Training und Community-Highlights. Standardmäßig aus; getrennt von deinen Benachrichtigungs-E-Mails.';

  @override
  String get prefsWeekStart => 'Woche beginnt am';

  @override
  String get prefsWeekStartMonday => 'Montag';

  @override
  String get prefsWeekStartSunday => 'Sonntag';

  @override
  String get prefsDefaultActivity => 'Standardaktivität';

  @override
  String get prefsDateOfBirth => 'Geburtsdatum';

  @override
  String get prefsRestingHr => 'Ruhepuls';

  @override
  String get prefsMaxHr => 'Maximalpuls';

  @override
  String get prefsMaxHrNotSet =>
      'Nicht festgelegt — fällt zurück auf 208 − 0,7 × Alter';

  @override
  String prefsHrBpm(int bpm) {
    return '$bpm bpm';
  }

  @override
  String get prefsSectionFueling => 'Wettkampfverpflegung';

  @override
  String get prefsCarbsPerHour => 'Kohlenhydrate pro Stunde';

  @override
  String prefsCarbsPerHourValue(int grams) {
    return '$grams g/h';
  }

  @override
  String get prefsFluidPerHour => 'Flüssigkeit pro Stunde';

  @override
  String prefsFluidPerHourValue(int ml) {
    return '$ml ml/h';
  }

  @override
  String get prefsHrZones => 'Herzfrequenzzonen';

  @override
  String get prefsHrZonesDialogTitle => 'Herzfrequenzzonen (Obergrenzen, bpm)';

  @override
  String get prefsWeeklyGoal => 'Wöchentliches Kilometerziel';

  @override
  String get prefsSectionActivityRecording => 'Aktivität & Aufzeichnung';

  @override
  String get prefsSectionTrainingDemographics =>
      'Training & demografische Daten';

  @override
  String get prefsSectionPrivacySharing => 'Datenschutz & Teilen';

  @override
  String get prefsSectionAiCoach => 'KI-Coach';

  @override
  String get prefsSignInToEdit =>
      'Melde dich an, um profilbezogene Einstellungen zu bearbeiten, die geräteübergreifend synchronisiert werden.';

  @override
  String get prefsUseMiles => 'Meilen verwenden';

  @override
  String get prefsDarkMode => 'Dunkelmodus';

  @override
  String get prefsAudioCues => 'Audio-Hinweise';

  @override
  String get prefsAudioCuesSubtitle => 'Gesprochene Split-Ansagen';

  @override
  String get prefsMinimalVoiceCues => 'Minimale Sprachhinweise';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Überspringt die geschwätzigen Mid-Rep- und Tempoabweichungs-Hinweise';

  @override
  String get prefsKeepScreenOn => 'Bildschirm anlassen';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Während eines Laufs einen Wakelock halten';

  @override
  String get prefsAdvancedGps => 'Erweitertes GPS';

  @override
  String get prefsAdvancedGpsSubtitle =>
      'Höhere Genauigkeit, feinere Track-Details, mehr Akkuverbrauch';

  @override
  String get prefsDefaultRunPrivacy => 'Standard-Datenschutz für Läufe';

  @override
  String get prefsStravaAutoShare => 'Strava-Autoshare';

  @override
  String get prefsStravaAutoShareSubtitle =>
      'Jeden neuen Lauf automatisch an Strava senden. Erfordert eine verbundene Strava-Integration, sobald diese verfügbar ist.';

  @override
  String get prefsDiscoverable => 'In der Namenssuche anzeigen';

  @override
  String get prefsDiscoverableSubtitle =>
      'Wenn deaktiviert, erscheint dein Konto nicht, wenn andere Läufer nach Anzeigenamen suchen. Deine öffentlichen Läufe und dein Profil bleiben für jeden mit der URL erreichbar.';

  @override
  String get dashboardCoachTooltip => 'Coach';

  @override
  String get dashboardFeedTooltip => 'Aktivitäten-Feed';

  @override
  String get dashboardRecapTooltip => 'Jahresrückblick im Laufen';

  @override
  String get dashboardProfileTooltip => 'Mein Profil';

  @override
  String get dashboardWelcomeTitle => 'Willkommen!';

  @override
  String get dashboardWelcomeBody =>
      'Dein Dashboard füllt sich, sobald du einen Lauf aufzeichnest, ein Ziel setzt oder deinen Verlauf importierst.';

  @override
  String get dashboardSetGoal => 'Ziel setzen';

  @override
  String get dashboardImportRuns => 'Läufe importieren';

  @override
  String get dashboardPeriodWeek => 'Woche';

  @override
  String get dashboardPeriodMonth => 'Monat';

  @override
  String get dashboardPeriodAllTime => 'Gesamt';

  @override
  String get dashboardSectionStreak => 'Serie';

  @override
  String get dashboardWeekStripTitle => 'Diese Woche';

  @override
  String dashboardWeekStripCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aktivitäten',
      one: '$count Aktivität',
    );
    return '$_temp0';
  }

  @override
  String dashboardWeekStripDayAria(String dow, String dist) {
    return '$dow: $dist';
  }

  @override
  String dashboardWeekStripDayRestAria(String dow) {
    return '$dow: Ruhetag';
  }

  @override
  String get dashboardSectionLast20Weeks => 'Letzte 20 Wochen';

  @override
  String get dashboardSectionRecentLifts => 'Letzte Einheiten';

  @override
  String get dashboardViewAllGym => 'Alle ansehen';

  @override
  String get dashboardSectionPersonalBests => 'Persönliche Bestleistungen';

  @override
  String get dashboardLongestRun => 'Längster Lauf';

  @override
  String dashboardFastestDistance(String distance) {
    return 'Schnellste $distance';
  }

  @override
  String get dashboardGoals => 'Ziele';

  @override
  String get dashboardAdd => 'Hinzufügen';

  @override
  String get dashboardGoalWeekly => 'WÖCHENTLICH';

  @override
  String get dashboardGoalMonthly => 'MONATLICH';

  @override
  String dashboardGoalTitleFallback(String period) {
    return '$period-ZIEL';
  }

  @override
  String get dashboardSetWeeklyGoalA11y => 'Ein wöchentliches Laufziel setzen';

  @override
  String get dashboardSetFirstGoal => 'Setze dein erstes Ziel';

  @override
  String get dashboardSetFirstGoalBody =>
      'Verfolge Distanz, Zeit, Tempo oder die Anzahl der Läufe pro Woche oder Monat.';

  @override
  String get dashboardGoalTapToEdit => 'zum Bearbeiten tippen';

  @override
  String get dashboardGoalComplete => 'Abgeschlossen.';

  @override
  String get dashboardGoalInProgress => 'In Bearbeitung.';

  @override
  String dashboardGoalA11y(String period, String title, String status) {
    return '$period-Ziel — $title $status';
  }

  @override
  String dashboardRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe',
      one: '$count Lauf',
    );
    return '$_temp0';
  }

  @override
  String dashboardVert(String value) {
    return '$value Höhenmeter';
  }

  @override
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  ) {
    return 'Zusammenfassung $label, $distance über $runs$elevation';
  }

  @override
  String dashboardElevationGainSuffix(String value) {
    return ', $value Höhengewinn';
  }

  @override
  String get dashboardStreakCurrent => 'Aktuell';

  @override
  String get dashboardStreakHistory => 'Verlauf';

  @override
  String get dashboardStreakDayUnit => 'Tag';

  @override
  String get dashboardStreakDaysUnit => 'Tage';

  @override
  String dashboardStreakBest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '$count Tag',
    );
    return 'beste $_temp0';
  }

  @override
  String get dashboardStreakAllTimeBest => 'Allzeit-Bestwert';

  @override
  String get dashboardStreakRestart => 'Lauf heute, um sie neu zu starten';

  @override
  String get dashboardStreakStart => 'Lauf heute, um eine zu starten';

  @override
  String get dashboardHeatmapLess => 'Weniger';

  @override
  String get dashboardHeatmapMore => 'Mehr';

  @override
  String get dashboardHeatmapTapHint =>
      'Tippe auf eine Woche für deren Zusammenfassung';

  @override
  String get periodWeeklySummary => 'Wochenübersicht';

  @override
  String get periodMonthlySummary => 'Monatsübersicht';

  @override
  String get periodAllTimeSummary => 'Gesamtübersicht';

  @override
  String get periodShareTooltip => 'Teilen';

  @override
  String get periodPreviousTooltip => 'Zurück';

  @override
  String get periodNextTooltip => 'Weiter';

  @override
  String get periodSwitchToWeekly => 'Tippen, um zur Wochenansicht zu wechseln';

  @override
  String get periodSwitchToMonthly =>
      'Tippen, um zur Monatsansicht zu wechseln';

  @override
  String get periodSwitchToAllTime =>
      'Tippen, um zur Gesamtansicht zu wechseln';

  @override
  String get periodStatDistance => 'Distanz';

  @override
  String get periodStatRuns => 'Läufe';

  @override
  String get periodStatTime => 'Zeit';

  @override
  String get periodStatAvgPace => 'Ø Tempo';

  @override
  String get periodEmptyWeek => 'Keine Läufe diese Woche';

  @override
  String get periodEmptyMonth => 'Keine Läufe diesen Monat';

  @override
  String get periodShareSummary => 'Zusammenfassung teilen';

  @override
  String get periodShareText => 'Text';

  @override
  String get periodShareImage => 'Bild';

  @override
  String get periodShareImageFailed =>
      'Freigabe-Bild konnte nicht erstellt werden';

  @override
  String get periodShareCardTagline => 'BESSERER LÄUFER';

  @override
  String get periodShareStatDistance => 'DISTANZ';

  @override
  String get periodShareStatRuns => 'LÄUFE';

  @override
  String get periodShareStatTime => 'ZEIT';

  @override
  String get periodShareStatAvgPace => 'Ø TEMPO';

  @override
  String get trainingLoadTitle => 'Fitness, Ermüdung & Form';

  @override
  String trainingLoadSubtitleHr(int days) {
    return 'Herzfrequenz-TRIMP der letzten $days Tage.';
  }

  @override
  String get trainingLoadSubtitleVolume =>
      'Volumenbasiert — lege Ruhe- und Maximalpuls in den Einstellungen fest und zeichne mit einem Gurt auf, um auf TRIMP zu wechseln.';

  @override
  String get trainingLoadEmpty =>
      'Zeichne ein paar Läufe auf, um deinen Fitness-Trend zu sehen.';

  @override
  String get trainingLoadLegendFitness => 'Fitness';

  @override
  String get trainingLoadLegendFatigue => 'Ermüdung';

  @override
  String get trainingLoadLegendForm => 'Form';

  @override
  String trainingLoadLegendEntry(String label, int value) {
    return '$label · $value';
  }

  @override
  String get trainingLoadReadingLoaded =>
      'Belastet — zieh durch und erhole dich, wenn du bereit bist.';

  @override
  String get trainingLoadReadingTapered =>
      'Getapert — eine harte Einheit bringt dich nicht um.';

  @override
  String get trainingLoadReadingBalanced =>
      'Ausgeglichen — ruhiger oder harter Tag, deine Wahl.';

  @override
  String get trainingLoadIncludesLifts =>
      'Fitnessstudio-Einheiten enthalten – Krafttraining erhöht auch die Ermüdung.';

  @override
  String get intensityTitle => 'TRAININGSINTENSITÄT';

  @override
  String intensityWindow(int days) {
    return 'letzte $days Tage';
  }

  @override
  String intensityBasedOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufen mit Herzfrequenz',
      one: '$count Lauf mit Herzfrequenz',
    );
    return 'Basierend auf $_temp0';
  }

  @override
  String get mileageTitle => 'LAUFLEISTUNG';

  @override
  String get mileageWeek => 'Woche';

  @override
  String get mileageMonth => 'Monat';

  @override
  String get mileageYear => 'Jahr';

  @override
  String get mileageThisWeek => 'diese Woche';

  @override
  String get mileageThisMonth => 'diesen Monat';

  @override
  String get mileageThisYear => 'dieses Jahr';

  @override
  String get fitnessTitle => 'Fitness';

  @override
  String get fitnessStatVo2Max => 'VO₂ max';

  @override
  String get fitnessStatVo2MaxTooltip =>
      'Dein aerober Motor: wie viel Sauerstoff dein Körper pro Minute nutzen kann. Höher ist fitter.';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'Daniels\' Lauf-Fitness-Wert aus deiner besten aktuellen Renneinheit. Bestimmt deine Trainingstempos.';

  @override
  String get fitnessStatRuns => 'Läufe';

  @override
  String get fitnessStatRunsTooltip =>
      'Aktuelle Läufe, die lang genug sind, um in deine Fitness-Schätzung einzufließen.';

  @override
  String get fitnessStatCtl => 'Fitness (CTL)';

  @override
  String get fitnessStatCtlTooltip =>
      'Deine gleitende 42-Tage-Trainingslast. Baut sich langsam auf; das ist deine Ausdauerbasis.';

  @override
  String get fitnessStatAtl => 'Ermüdung (ATL)';

  @override
  String get fitnessStatAtlTooltip =>
      'Deine Last der letzten 7 Tage. Steigt nach harten Einheiten schnell und fällt mit Erholung.';

  @override
  String get fitnessStatTsb => 'Form (TSB)';

  @override
  String get fitnessStatTsbTooltip =>
      'Fitness minus Ermüdung. Positiv = frisch und rennbereit; negativ = noch ermüdet.';

  @override
  String get runSocialActivity => 'Aktivität';

  @override
  String get runSocialNoComments => 'Noch keine Kommentare.';

  @override
  String get runSocialReplyHint => 'Antwort schreiben…';

  @override
  String get runSocialCommentHint => 'Kommentar hinzufügen…';

  @override
  String get runSocialRunnerFallback => 'Läufer';

  @override
  String get runSocialReply => 'Antworten';

  @override
  String get runSocialDelete => 'Löschen';

  @override
  String get runSocialDeleteCommentTitle => 'Diesen Kommentar löschen?';

  @override
  String get runSocialDeleteCommentMessage =>
      'Dieser Kommentar wird dauerhaft entfernt. Das kann nicht rückgängig gemacht werden.';

  @override
  String get runSocialPost => 'Senden';

  @override
  String get runSocialCancel => 'Abbrechen';

  @override
  String runSocialKudosError(String error) {
    return 'Kudos konnten nicht aktualisiert werden: $error';
  }

  @override
  String runSocialPostError(String error) {
    return 'Senden fehlgeschlagen: $error';
  }

  @override
  String runSocialDeleteError(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get runPhotosLoading => 'Fotos werden geladen…';

  @override
  String get runPhotosTitle => 'Fotos';

  @override
  String get runPhotosAdd => 'Foto hinzufügen';

  @override
  String get runPhotosCaptionPendingHint =>
      'Bildunterschrift (optional, 280 Zeichen)';

  @override
  String get runPhotosCaptionHint => 'Bildunterschrift…';

  @override
  String get runPhotosCancel => 'Abbrechen';

  @override
  String get runPhotosSave => 'Speichern';

  @override
  String get runPhotosUpload => 'Hochladen';

  @override
  String get runPhotosUploading => 'Wird hochgeladen…';

  @override
  String get runPhotosEditCaption => 'Bildunterschrift bearbeiten';

  @override
  String get runPhotosDeleteTooltip => 'Foto löschen';

  @override
  String get runPhotosDeleteTitle => 'Foto löschen?';

  @override
  String get runPhotosDeleteBody =>
      'Dies entfernt das Foto dauerhaft vom Lauf.';

  @override
  String get runPhotosDeleteConfirm => 'Löschen';

  @override
  String runPhotosPickerError(String error) {
    return 'Auswahl konnte nicht geöffnet werden: $error';
  }

  @override
  String runPhotosUploadError(String error) {
    return 'Hochladen fehlgeschlagen: $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'Bildunterschrift konnte nicht aktualisiert werden: $error';
  }

  @override
  String get routePhotosLoading => 'Fotos werden geladen…';

  @override
  String get routePhotosTitle => 'Fotos';

  @override
  String get routePhotosAdd => 'Foto hinzufügen';

  @override
  String get routePhotosCaptionPendingHint =>
      'Bildunterschrift (optional, 280 Zeichen)';

  @override
  String get routePhotosCaptionHint => 'Bildunterschrift…';

  @override
  String get routePhotosCancel => 'Abbrechen';

  @override
  String get routePhotosSave => 'Speichern';

  @override
  String get routePhotosUpload => 'Hochladen';

  @override
  String get routePhotosUploading => 'Wird hochgeladen…';

  @override
  String get routePhotosEditCaption => 'Bildunterschrift bearbeiten';

  @override
  String get routePhotosDeleteTooltip => 'Foto löschen';

  @override
  String get routePhotosDeleteTitle => 'Foto löschen?';

  @override
  String get routePhotosDeleteBody =>
      'Dies entfernt das Foto dauerhaft von der Route.';

  @override
  String get routePhotosDeleteConfirm => 'Löschen';

  @override
  String routePhotosPickerError(String error) {
    return 'Auswahl konnte nicht geöffnet werden: $error';
  }

  @override
  String routePhotosUploadError(String error) {
    return 'Hochladen fehlgeschlagen: $error';
  }

  @override
  String routePhotosDeleteError(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'Bildunterschrift konnte nicht aktualisiert werden: $error';
  }

  @override
  String get runSegEffortsChecking => 'Segmente werden geprüft…';

  @override
  String get runSegEffortsNoRoute =>
      'Segmente werden pro Route zugeordnet — verknüpfe diesen Lauf mit einer gespeicherten Route, um in den Bestenlisten anzutreten.';

  @override
  String get runSegEffortsEmpty => 'Keine Segmentversuche bei diesem Lauf.';

  @override
  String get workoutReviewTitle => 'Training';

  @override
  String get workoutReviewColStep => 'Schritt';

  @override
  String get workoutReviewColPlan => 'Plan';

  @override
  String get workoutReviewColActual => 'Ist';

  @override
  String get workoutReviewColPace => 'Pace';

  @override
  String get workoutReviewColDelta => 'Δ';

  @override
  String get workoutReviewSkip => 'übersp.';

  @override
  String get workoutReviewLabelWarmup => 'Aufwärmen';

  @override
  String get workoutReviewLabelCooldown => 'Abwärmen';

  @override
  String get workoutReviewLabelSteady => 'Gleichmäßig';

  @override
  String get workoutReviewLabelRep => 'Wdh.';

  @override
  String workoutReviewLabelRepN(int index, int total) {
    return 'Wdh. $index/$total';
  }

  @override
  String get workoutReviewLabelRecovery => 'Erholung';

  @override
  String workoutReviewLabelRecoveryN(int index, int total) {
    return 'Erholung $index/$total';
  }

  @override
  String get workoutReviewLabelWalk => 'Gehen';

  @override
  String workoutReviewLabelWalkN(int index, int total) {
    return 'Gehen $index/$total';
  }

  @override
  String get segmentsPanelTitle => 'Segmente';

  @override
  String get segmentsPanelNew => 'Neues Segment';

  @override
  String get segmentsPanelCancel => 'Abbrechen';

  @override
  String get segmentsPanelLoading => 'Segmente werden geladen…';

  @override
  String get segmentsPanelEmpty => 'Noch keine Segmente auf dieser Route.';

  @override
  String get segmentsPanelNameLabel => 'Name';

  @override
  String get segmentsPanelNameHint => 'Höllenanstieg';

  @override
  String get segmentsPanelStartLabel => 'Start (m)';

  @override
  String get segmentsPanelEndLabel => 'Ende (m)';

  @override
  String segmentsPanelRouteHint(int metres) {
    return 'Route ist $metres m';
  }

  @override
  String get segmentsPanelCreate => 'Erstellen';

  @override
  String get segmentsPanelDeleteTooltip => 'Segment löschen';

  @override
  String get segmentsPanelDeleteTitle => 'Segment löschen?';

  @override
  String segmentsPanelDeleteBody(String name) {
    return '„$name“ wird entfernt.';
  }

  @override
  String get segmentsPanelDeleteConfirm => 'Löschen';

  @override
  String get segmentsPanelErrEndAfterStart => 'Ende muss größer als Start sein';

  @override
  String get segmentsPanelErrMinLength =>
      'Segment muss mindestens 100 m lang sein';

  @override
  String segmentsPanelCreateError(String error) {
    return 'Segment konnte nicht erstellt werden: $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get segmentsPanelAllGenders => 'Alle Geschlechter';

  @override
  String get segmentsPanelGenderMen => 'Männer';

  @override
  String get segmentsPanelGenderWomen => 'Frauen';

  @override
  String get segmentsPanelGenderNonbinary => 'Nichtbinär';

  @override
  String get segmentsPanelAllAges => 'Alle Altersgruppen';

  @override
  String get segmentsPanelResetFilters => 'Zurücksetzen';

  @override
  String get segmentsPanelLeaderboardLoading => 'Wird geladen…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'Keine Versuche entsprechen diesem Filter — versuche ihn zu erweitern.';

  @override
  String get segmentsPanelLeaderboardEmpty =>
      'Noch keine Versuche — sei der Erste auf diesem Segment.';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'Du hältst diese Krone — $label.';
  }

  @override
  String get segmentsPanelRunnerFallback => 'Läufer';

  @override
  String get goalEditorTitleNew => 'Neues Ziel';

  @override
  String get goalEditorTitleEdit => 'Ziel bearbeiten';

  @override
  String get goalEditorNameLabel => 'Name (optional)';

  @override
  String get goalEditorNameHint => 'z. B. Grundlagen-km';

  @override
  String get goalEditorPeriod => 'Zeitraum';

  @override
  String get goalEditorThisWeek => 'Diese Woche';

  @override
  String get goalEditorThisMonth => 'Diesen Monat';

  @override
  String get goalEditorTargets => 'Ziele';

  @override
  String get goalEditorTargetsHelp =>
      'Setze beliebige Kombinationen. Leere Felder werden ignoriert.';

  @override
  String get goalEditorTargetDistance => 'Distanz';

  @override
  String get goalEditorTargetTime => 'Zeit';

  @override
  String get goalEditorTargetPace => 'Ø Pace';

  @override
  String get goalEditorTargetRuns => 'Läufe';

  @override
  String get goalEditorSuffixMin => 'Min';

  @override
  String get goalEditorSuffixRuns => 'Läufe';

  @override
  String get goalEditorDelete => 'Löschen';

  @override
  String get goalEditorDeleteTitle => 'Dieses Ziel löschen?';

  @override
  String get goalEditorDeleteMessage =>
      'Dieses Ziel und seine Fortschrittsverfolgung werden entfernt. Du kannst jederzeit ein neues erstellen.';

  @override
  String get goalEditorCancel => 'Abbrechen';

  @override
  String get goalEditorSave => 'Speichern';

  @override
  String goalEditorSaveFailed(String error) {
    return 'Ziel konnte nicht gespeichert werden: $error';
  }

  @override
  String get goalEditorErrDistance => 'Distanz: positive Zahl eingeben';

  @override
  String get goalEditorErrTime => 'Zeit: positive Minutenzahl eingeben';

  @override
  String get goalEditorErrPace => 'Pace: mm:ss verwenden (z. B. 5:00)';

  @override
  String get goalEditorErrRuns => 'Läufe: positive ganze Zahl eingeben';

  @override
  String get goalEditorErrNoTarget => 'Mindestens ein Ziel festlegen';

  @override
  String get goalEditorSavedAnnounce => 'Ziel gespeichert';

  @override
  String get goalEditorDeletedAnnounce => 'Ziel gelöscht';

  @override
  String get eventFormTitle => 'Neue Veranstaltung';

  @override
  String get eventFormTitleLabel => 'Titel';

  @override
  String get eventFormStartsAt => 'Beginnt am';

  @override
  String get eventFormDescriptionLabel => 'Beschreibung (optional)';

  @override
  String get eventFormMeetLabel => 'Treffpunkt (optional)';

  @override
  String get eventFormMeetHint => 'Parkplatz am Wanderweg';

  @override
  String get eventFormDistanceLabel => 'Distanz (km)';

  @override
  String get eventFormDurationLabel => 'Dauer (Min)';

  @override
  String get eventFormRecurrence => 'Wiederholung';

  @override
  String get eventFormRecurOneOff => 'Einmalig';

  @override
  String get eventFormRecurWeekly => 'Wöchentlich';

  @override
  String get eventFormRecurBiweekly => 'Zweiwöchentlich';

  @override
  String get eventFormRecurMonthly => 'Monatlich';

  @override
  String get eventFormCancel => 'Abbrechen';

  @override
  String get eventFormCreate => 'Veranstaltung erstellen';

  @override
  String get eventEditorCategory => 'Veranstaltungstyp';

  @override
  String get eventEditorCatRun => 'Gruppenlauf';

  @override
  String get eventEditorCatCycle => 'Radfahren';

  @override
  String get eventEditorCatClass => 'Kurs';

  @override
  String get eventEditorCatSocial => 'Treffen';

  @override
  String get eventEditorCategoryHint =>
      'Wähle die Art der Veranstaltung – ein Kurs oder Treffen lässt Strecke, Distanz, Tempo und Rennergebnisse weg.';

  @override
  String get eventEditorMembersOnlyToggle => 'Nur für Mitglieder';

  @override
  String get eventEditorMembersOnlyHint =>
      'Nur Vereinsmitglieder können dieses Event sehen; es erscheint nicht in der öffentlichen Suche.';

  @override
  String get eventEditorDiscipline => 'Disziplin';

  @override
  String get eventEditorDisciplinePlaceholder =>
      'z. B. Vinyasa-Yoga, Pilates, Mobility';

  @override
  String get clubFormTitle => 'Neuer Club';

  @override
  String get clubFormNameLabel => 'Name';

  @override
  String get clubFormDescriptionLabel => 'Beschreibung (optional)';

  @override
  String get clubFormLocationLabel => 'Standort (optional)';

  @override
  String get clubFormLocationHint => 'Edinburgh, UK';

  @override
  String get clubFormPublic => 'Öffentlich';

  @override
  String get clubFormPrivate => 'Privat';

  @override
  String get clubFormJoinPolicy => 'Beitrittsregel';

  @override
  String get clubFormJoinOpen => 'Offen — jeder kann beitreten';

  @override
  String get clubFormJoinRequest => 'Anfrage — Admins genehmigen';

  @override
  String get clubFormJoinInvite => 'Nur mit Einladung';

  @override
  String get clubFormCancel => 'Abbrechen';

  @override
  String get clubFormCreate => 'Erstellen';

  @override
  String get clubFormErrSlug =>
      'Der Name braucht mindestens einen Buchstaben oder eine Ziffer.';

  @override
  String get clubFormErrUnreachable =>
      'Der Server ist gerade nicht erreichbar. Prüfe deine Verbindung oder melde dich an und versuche es erneut.';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonHarassment => 'Belästigung oder Missbrauch';

  @override
  String get reportReasonInappropriate => 'Unangemessene Inhalte';

  @override
  String get reportReasonImpersonation => 'Identitätsdiebstahl';

  @override
  String get reportReasonOther => 'Sonstiges';

  @override
  String get reportSuccess =>
      'Meldung übermittelt — danke, dass du dies zur Prüfung gemeldet hast.';

  @override
  String get reportTitleUser => 'Nutzer melden';

  @override
  String get reportTitleClub => 'Club melden';

  @override
  String get reportTitleRoute => 'Route melden';

  @override
  String get reportTitlePost => 'Beitrag melden';

  @override
  String get reportTitleRun => 'Lauf melden';

  @override
  String get reportTitleContent => 'Inhalt melden';

  @override
  String get reportDisclaimer =>
      'Deine Meldung geht an einen Moderator. Auch falsche Meldungen werden geprüft — bitte melde nur Inhalte, die gegen unsere Community-Richtlinien verstoßen.';

  @override
  String get reportReason => 'Grund';

  @override
  String get reportNotesLabel => 'Notizen (optional)';

  @override
  String get reportCancel => 'Abbrechen';

  @override
  String get reportSubmit => 'Meldung senden';

  @override
  String get reportErrDuplicate =>
      'Du hast bereits eine ausstehende Meldung zu diesem Inhalt.';

  @override
  String gearBackfillTitle(String gear) {
    return 'Frühere Läufe mit $gear verknüpfen?';
  }

  @override
  String gearBackfillBody(int count, String activity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $activity-Aktivitäten',
      one: '$count $activity-Aktivität',
    );
    return 'Wir haben $_temp0 nach dem Kauf gefunden. Entferne das Häkchen bei allen, bei denen du sie nicht getragen hast.';
  }

  @override
  String get gearBackfillActivityCycling => 'Rad';

  @override
  String get gearBackfillActivityRunning => 'Lauf';

  @override
  String get gearBackfillSelectNone => 'Keine auswählen';

  @override
  String get gearBackfillSelectAll => 'Alle auswählen';

  @override
  String gearBackfillSelectedCount(int selected, int total) {
    return '$selected von $total';
  }

  @override
  String get gearBackfillSkip => 'Überspringen';

  @override
  String get gearBackfillAttaching => 'Wird verknüpft…';

  @override
  String gearBackfillAttach(int count) {
    return '$count verknüpfen';
  }

  @override
  String gearBackfillAttachError(String error) {
    return 'Verknüpfen fehlgeschlagen: $error';
  }

  @override
  String get workoutEditTitle => 'Training bearbeiten';

  @override
  String get workoutEditKindLabel => 'Art';

  @override
  String get workoutEditDistanceLabel => 'Zieldistanz (km)';

  @override
  String get workoutEditDistanceHint => 'z. B. 8,0';

  @override
  String get workoutEditPaceLabel => 'Zielpace (mm:ss /km)';

  @override
  String get workoutEditPaceHint => 'z. B. 5:30';

  @override
  String get workoutEditNotesLabel => 'Notizen';

  @override
  String get workoutEditCancel => 'Abbrechen';

  @override
  String get workoutEditSave => 'Speichern';

  @override
  String get workoutEditErrDistance => 'Positive Distanz in km eingeben';

  @override
  String get workoutEditErrPace => 'Pace muss wie 5:30 aussehen';

  @override
  String workoutEditSaveError(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return 'ZUGESAGT · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'Beginnt jetzt';

  @override
  String upcomingEventInMinutes(int count) {
    return 'In $count Min';
  }

  @override
  String get upcomingEventInOneHour => 'In 1 Stunde';

  @override
  String upcomingEventInHours(int count) {
    return 'In $count Stunden';
  }

  @override
  String get upcomingEventTomorrow => 'Morgen';

  @override
  String upcomingEventInDays(int count) {
    return 'In $count Tagen';
  }

  @override
  String get todaysWorkoutDone => 'HEUTE ERLEDIGT';

  @override
  String get todaysWorkoutToday => 'HEUTIGES TRAINING';

  @override
  String get errorStateRetry => 'Erneut versuchen';

  @override
  String get shareCardRunTitle => 'Lauf teilen';

  @override
  String get shareCardExport => 'Exportieren';

  @override
  String get shareCardImage => 'Bild';

  @override
  String get shareCardStatDistance => 'Distanz';

  @override
  String get shareCardStatTime => 'Zeit';

  @override
  String get shareCardStatPace => 'Pace';

  @override
  String get shareCardStatSpeed => 'Tempo';

  @override
  String get shareCardBrandRun => 'RUN';

  @override
  String get shareCardImageError => 'Teilbild konnte nicht erstellt werden';

  @override
  String get shareCardFileError => 'Datei konnte nicht exportiert werden';

  @override
  String get shareCardRouteTitle => 'Route teilen';

  @override
  String get shareCardRouteShareImage => 'Bild teilen';

  @override
  String get shareCardRouteCapturing => 'Wird aufgenommen…';

  @override
  String get shareCardRouteStatDistance => 'Distanz';

  @override
  String get shareCardRouteStatClimb => 'Anstieg';

  @override
  String get billingToday => 'heute';

  @override
  String get billingYesterday => 'gestern';

  @override
  String billingDaysAgo(int count) {
    return 'vor $count Tagen';
  }

  @override
  String billingRenewalFailed(String relative) {
    return 'Pro-Verlängerung $relative fehlgeschlagen.';
  }

  @override
  String get billingRenewalBody =>
      'Aktualisiere deine Karte, sonst wirst du auf Free herabgestuft.';

  @override
  String get billingManage => 'Verwalten';

  @override
  String get planCalendarPrevMonth => 'Vorheriger Monat';

  @override
  String get planCalendarNextMonth => 'Nächster Monat';

  @override
  String runGearChipsLoadError(String error) {
    return 'Ausrüstung konnte nicht geladen werden: $error';
  }

  @override
  String get runGearChipsPickerTitle =>
      'Bei diesem Lauf verwendete Ausrüstung markieren';

  @override
  String get runGearChipsEmpty =>
      'Du hast noch keine Ausrüstung registriert. Füge welche unter Einstellungen → Ausrüstung hinzu.';

  @override
  String get runGearChipsCancel => 'Abbrechen';

  @override
  String get runGearChipsSave => 'Speichern';

  @override
  String get runGearChipsTag => '+ Ausrüstung markieren';

  @override
  String get runGearChipsEdit => 'Bearbeiten';

  @override
  String runGearChipsSaveError(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get gearFormTitleEdit => 'Ausrüstung bearbeiten';

  @override
  String get gearFormTitleAddShoes => 'Schuhe hinzufügen';

  @override
  String get gearFormTitleAddBike => 'Fahrrad hinzufügen';

  @override
  String get gearFormNameLabel => 'Name';

  @override
  String get gearFormNameHint => 'Pegasus 39';

  @override
  String get gearFormBrandLabel => 'Marke';

  @override
  String get gearFormModelLabel => 'Modell';

  @override
  String get gearFormBoughtLabel => 'Gekauft';

  @override
  String get gearFormBoughtPick => 'Zum Auswählen tippen';

  @override
  String gearFormRetireAt(String unit) {
    return 'Ausmustern bei ($unit)';
  }

  @override
  String get gearFormRetireHint => '500';

  @override
  String get gearFormNotesLabel => 'Notizen';

  @override
  String get gearFormCancel => 'Abbrechen';

  @override
  String get gearFormSaving => 'Wird gespeichert…';

  @override
  String get gearFormSave => 'Speichern';

  @override
  String get gearFormAdd => 'Hinzufügen';

  @override
  String gearFormSaveError(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get notificationBellTooltip => 'Benachrichtigungen';

  @override
  String get liveRunMapWaitingGps => 'Warte auf GPS...';

  @override
  String get liveRunMapRecentre => 'Auf meinen Standort zentrieren';

  @override
  String get ttsRunStarted => 'Lauf gestartet';

  @override
  String ttsRunComplete(String distance, int mins) {
    return 'Lauf beendet. $distance in $mins Minuten.';
  }

  @override
  String get ttsOffRoute => 'Abseits der Route';

  @override
  String get ttsPaceAlertFast => 'Tempo erhöhen';

  @override
  String get ttsPaceAlertSlow => 'Langsamer';

  @override
  String get ttsWorkoutComplete => 'Training abgeschlossen. Gut gemacht.';

  @override
  String get ttsStepHalfway => 'Halbzeit in dieser Wiederholung';

  @override
  String get ttsStepLastFifty => 'Noch fünfzig Meter';

  @override
  String ttsPaceDriftAhead(int delta) {
    return 'Etwas lockerer — $delta Sekunden zu schnell.';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return 'Etwas schneller — $delta Sekunden zu langsam.';
  }

  @override
  String ttsSpeedKm(String value) {
    return 'Tempo, $value Stundenkilometer';
  }

  @override
  String ttsSpeedMi(String value) {
    return 'Tempo, $value Meilen pro Stunde';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'Pace, $min Minuten $sec Sekunden pro Kilometer';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'Pace, $min Minuten $sec Sekunden pro Meile';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$value Kilometer';
  }

  @override
  String ttsDistanceMetres(int value) {
    return '$value Meter';
  }

  @override
  String ttsDistanceMileSingular(String value) {
    return '$value Meile';
  }

  @override
  String ttsDistanceMiles(String value) {
    return '$value Meilen';
  }

  @override
  String ttsDistanceYards(int value) {
    return '$value Yards';
  }

  @override
  String ttsSplit(String count, String unit, String tail) {
    return '$count $unit. $tail';
  }

  @override
  String get ttsStepWarmup => 'Aufwärmen';

  @override
  String get ttsStepRecovery => 'Erholung';

  @override
  String get ttsStepSteady => 'Gleichmäßig';

  @override
  String get ttsStepCooldown => 'Auslaufen';

  @override
  String get ttsStepRep => 'Wiederholung';

  @override
  String get ttsStepRun => 'Laufen';

  @override
  String get ttsStepWalk => 'Gehen';

  @override
  String ttsStepRepOf(int index, int total) {
    return 'Wiederholung $index von $total';
  }

  @override
  String ttsStepRunOf(int index, int total) {
    return 'Laufen $index von $total';
  }

  @override
  String ttsStepWalkOf(int index, int total) {
    return 'Gehen $index von $total';
  }

  @override
  String ttsStepPaceKm(int min, int sec) {
    return '$min Minuten $sec Sekunden pro Kilometer';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '$min Minuten pro Kilometer';
  }

  @override
  String ttsStepPaceMi(int min, int sec) {
    return '$min Minuten $sec Sekunden pro Meile';
  }

  @override
  String ttsStepPaceMiWhole(int min) {
    return '$min Minuten pro Meile';
  }

  @override
  String ttsDurationSeconds(int sec) {
    return '$sec Sekunden';
  }

  @override
  String ttsDurationMinutes(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min Minuten',
      one: '1 Minute',
    );
    return '$_temp0';
  }

  @override
  String ttsDurationMinutesSeconds(String minutes, int sec) {
    return '$minutes $sec Sekunden';
  }

  @override
  String ttsStepDuration(String intro, String duration) {
    return '$intro. $duration.';
  }

  @override
  String ttsStepDistancePace(String intro, String distance, String pace) {
    return '$intro. $distance bei $pace.';
  }

  @override
  String get guidedEasy30Title => '30-minütiger lockerer Lauf';

  @override
  String get guidedEasy30Subtitle => 'Coach-Stimme · 30 Min · lockeres Tempo';

  @override
  String get guidedEasy30Description =>
      'Ein entspannter Lauf im Plaudertempo für einen Erholungstag oder einfach zum Kopf-frei-Bekommen. Der Coach meldet sich alle fünf Minuten mit einem sanften Anstoß.';

  @override
  String get guidedEasy30Cue0 =>
      'Los geht’s. Starte locker — das ist dein Erholungstempo.';

  @override
  String get guidedEasy30Cue1 =>
      'Fünf Minuten drin. Lass die Schultern fallen. Bleib im Plaudertempo.';

  @override
  String get guidedEasy30Cue2 =>
      'Zehn Minuten. Schrittfrequenz-Check — schnelle Füße, leichtes Aufsetzen.';

  @override
  String get guidedEasy30Cue3 =>
      'Halbzeit. Du solltest dich dabei noch unterhalten können.';

  @override
  String get guidedEasy30Cue4 =>
      'Zwanzig Minuten. Achte auf deine Atmung — langsam durch die Nase ein, durch den Mund aus.';

  @override
  String get guidedEasy30Cue5 =>
      'Noch fünf Minuten. Bleib locker. Zieh nicht an.';

  @override
  String get guidedEasy30Cue6 => 'Noch eine Minute. Lockerer Abschluss.';

  @override
  String get guidedEasy30Cue7 => 'Fertig. Geh eine Minute aus. Gut gemacht.';

  @override
  String get guidedTempo25Title => '25-minütiger Tempo-Aufbau';

  @override
  String get guidedTempo25Subtitle => 'Coach-Stimme · 25 Min · 5-15-5';

  @override
  String get guidedTempo25Description =>
      'Fünf Minuten lockeres Aufwärmen, fünfzehn Minuten im Tempo (angenehm hart), fünf Minuten Auslaufen. Die wöchentliche Standard-Tempoeinheit.';

  @override
  String get guidedTempo25Cue0 =>
      'Aufwärmzeit. Fünf Minuten locker — weck die Beine auf.';

  @override
  String get guidedTempo25Cue1 =>
      'Noch eine Minute Aufwärmen. Erhöhe die Schrittfrequenz.';

  @override
  String get guidedTempo25Cue2 =>
      'Geh ins Tempo. Angenehm hart. Wie ein 10-km-Wettkampftempo.';

  @override
  String get guidedTempo25Cue3 =>
      'Fünf Minuten im Tempo. Stark, aber kontrolliert. Halte den Rhythmus.';

  @override
  String get guidedTempo25Cue4 =>
      'Zehn Minuten Tempo geschafft. Halte das Tempo.';

  @override
  String get guidedTempo25Cue5 =>
      'Noch zwei Minuten im Tempo. Bleib geschmeidig.';

  @override
  String get guidedTempo25Cue6 =>
      'Locker lassen. Fünf Minuten locker zum Auslaufen.';

  @override
  String get guidedTempo25Cue7 =>
      'Noch zwei Minuten. Bring den Puls wieder runter.';

  @override
  String get guidedTempo25Cue8 =>
      'Fertig. Geh und dehne dich. Großartige Arbeit.';

  @override
  String get guidedFirst15Title => 'Einsteiger: 15-minütiges Lauf/Geh-Training';

  @override
  String get guidedFirst15Subtitle =>
      'Coach-Stimme · 15 Min · Lauf/Geh-Intervalle';

  @override
  String get guidedFirst15Description =>
      'Neu beim Laufen? Drei Runden aus einer Minute Laufen und einer Minute Gehen, plus Aufwärmen und Auslaufen. Ein sanfter Einstieg; jeder fängt hier an.';

  @override
  String get guidedFirst15Cue0 =>
      'Beginne mit drei Minuten zügigem Gehen zum Aufwärmen.';

  @override
  String get guidedFirst15Cue1 =>
      'Wechsle zu einer Minute lockerem Laufen. Plaudertempo.';

  @override
  String get guidedFirst15Cue2 => 'Geh eine Minute.';

  @override
  String get guidedFirst15Cue3 => 'Lauf eine Minute.';

  @override
  String get guidedFirst15Cue4 => 'Geh eine Minute.';

  @override
  String get guidedFirst15Cue5 => 'Lauf eine Minute.';

  @override
  String get guidedFirst15Cue6 => 'Geh eine Minute.';

  @override
  String get guidedFirst15Cue7 => 'Lauf eine Minute — die letzte.';

  @override
  String get guidedFirst15Cue8 => 'Geh aus. Fünf Minuten Auslaufen.';

  @override
  String get guidedFirst15Cue9 => 'Noch eine Minute. Geh locker.';

  @override
  String get guidedFirst15Cue10 =>
      'Fertig. Das war ein echter Lauf. Komm bald wieder raus.';

  @override
  String guidedRunMinutesBadge(int minutes) {
    return '$minutes Min';
  }

  @override
  String guidedRunCueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ansagen im Lauf',
      one: '$count Ansage im Lauf',
    );
    return '$_temp0';
  }

  @override
  String get guidedRunFullScript => 'DAS GESAMTE SKRIPT';

  @override
  String get guidedRunPreviewCue => 'Ansage vorhören';

  @override
  String guidedRunPreviewError(String error) {
    return 'Vorhören fehlgeschlagen: $error';
  }

  @override
  String get ttsSplitUnitKilometre => 'Kilometer';

  @override
  String get ttsSplitUnitKilometres => 'Kilometer';

  @override
  String get ttsSplitUnitMile => 'Meile';

  @override
  String get ttsSplitUnitMiles => 'Meilen';

  @override
  String get workoutKindEasy => 'Locker';

  @override
  String get workoutKindLong => 'Langer Lauf';

  @override
  String get workoutKindRecovery => 'Erholung';

  @override
  String get workoutKindTempo => 'Tempo';

  @override
  String get workoutKindInterval => 'Intervalle';

  @override
  String get workoutKindMarathonPace => 'Marathontempo';

  @override
  String get workoutKindWalkRun => 'Geh-Lauf';

  @override
  String get workoutKindRace => 'Wettkampf';

  @override
  String get workoutKindRest => 'Ruhe';

  @override
  String get planPhaseBase => 'Grundlage';

  @override
  String get planPhaseBuild => 'Aufbau';

  @override
  String get planPhasePeak => 'Höhepunkt';

  @override
  String get planPhaseTaper => 'Tapering';

  @override
  String get planPhaseRace => 'Wettkampfwoche';

  @override
  String get runBackgroundLocationNudgeTitle => 'Standort immer zulassen';

  @override
  String get runBackgroundLocationNudgeBody =>
      'Android hat den Standort nur erlaubt, während die App geöffnet ist. Für eine genaue Distanz bei ausgeschaltetem Bildschirm setze den Standortzugriff in den Einstellungen auf „Immer zulassen“. Du kannst trotzdem starten – die Aufzeichnung funktioniert weiterhin, solange die App im Vordergrund ist.';

  @override
  String get runBatteryOptHintTitle =>
      'Aufzeichnung im Hintergrund aktiv halten';

  @override
  String get runBatteryOptHintBody =>
      'Manche Telefone (Samsung, Xiaomi, OnePlus und andere) versetzen Apps in den Ruhezustand, um Akku zu sparen, was die Aufzeichnung eines langen Laufs bei ausgeschaltetem Bildschirm stoppen kann. Schließe diese App in den Einstellungen sicherheitshalber von der Akku-Optimierung aus. Dein Lauf wird ohnehin aufgezeichnet – dies verhindert nur, dass das System ihn vorzeitig beendet.';

  @override
  String shareCardCaption(Object title, Object distance, Object duration) {
    return '$title — $distance in $duration';
  }

  @override
  String get settingsBackendNotConfigured => 'Backend nicht konfiguriert';

  @override
  String get settingsAccountSignedIn => 'Angemeldet';

  @override
  String get settingsDevicesSignedOutSubtitle =>
      'Melde dich an, um deine Geräte zu verwalten';

  @override
  String get verifiedClubTooltip => 'Offiziell verifizierter Club';

  @override
  String get raceDistance5k => '5 km';

  @override
  String get raceDistance10k => '10 km';

  @override
  String get raceDistanceHalfMarathon => 'Halbmarathon';

  @override
  String get raceDistanceMarathon => 'Marathon';

  @override
  String get settingsTabAccountSubtitle => 'Anmelden, sichern, Konto löschen';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Einheiten, Design, Aufzeichnung, Training, Datenschutz';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, Herzfrequenzgurt';

  @override
  String get settingsTabDevicesSubtitle =>
      'Wo du angemeldet bist und gerätespezifische Einstellungen';

  @override
  String get settingsTabGearSubtitle =>
      'Schuhe + Räder und Laufleistung pro Artikel verfolgen';

  @override
  String get settingsTabCoachingSubtitle =>
      'Athleten betreuen oder dem eigenen Coach folgen';

  @override
  String get settingsTabProSubtitle =>
      'Abonnieren, Käufe wiederherstellen, Abrechnung verwalten';

  @override
  String get settingsTabLicensesSubtitle =>
      'App-Version und Open-Source-Hinweise';

  @override
  String periodSummaryWeekOf(Object date) {
    return 'Woche vom $date';
  }

  @override
  String periodShareRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe',
      one: '1 Lauf',
    );
    return '$_temp0';
  }

  @override
  String periodShareAvgPace(Object pace) {
    return 'Ø Pace: $pace';
  }

  @override
  String get gymTitle => 'Gym';

  @override
  String get gymLog => 'Training erfassen';

  @override
  String get gymUntitled => 'Unbenanntes Training';

  @override
  String get gymOfflineCached =>
      'Offline – gespeicherte Trainings werden angezeigt';

  @override
  String get gymOfflineQueued =>
      'Offline – Änderungen werden später synchronisiert';

  @override
  String get gymEmptyTitle => 'Noch keine Gym-Trainings';

  @override
  String get gymEmptyBody =>
      'Erfasse eine Einheit, um sie hier zu verfolgen und in deine Trainingslast einfließen zu lassen.';

  @override
  String get gymPrBadge => 'PR';

  @override
  String gymExercisesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Übungen',
      one: '$count Übung',
    );
    return '$_temp0';
  }

  @override
  String gymVolumeShort(int volume) {
    return '$volume kg';
  }

  @override
  String get gymNotFound => 'Training nicht gefunden.';

  @override
  String get gymEdit => 'Bearbeiten';

  @override
  String get gymDelete => 'Löschen';

  @override
  String get gymPublic => 'Öffentlich';

  @override
  String get gymPrivate => 'Privat';

  @override
  String get gymMakePublic => 'Öffentlich machen';

  @override
  String get gymMakePrivate => 'Privat machen';

  @override
  String gymVisibilityFailed(Object error) {
    return 'Sichtbarkeit konnte nicht aktualisiert werden: $error';
  }

  @override
  String get gymNotes => 'Notizen';

  @override
  String get gymKg => 'kg';

  @override
  String get gymReps => 'Wdh.';

  @override
  String get gymRpe => 'RPE';

  @override
  String get gymDuration => 'Zeit (s)';

  @override
  String gymDurationValue(String seconds) {
    return '${seconds}s';
  }

  @override
  String gymSetN(int n) {
    return 'Satz $n';
  }

  @override
  String get gymPrWeight => 'Schwerste';

  @override
  String get gymPrVolume => 'Top-Volumen';

  @override
  String get gymPrE1rm => 'Beste gesch. 1RM';

  @override
  String get gymRecordsLink => 'Rekorde';

  @override
  String get gymRecordsTitle => 'Persönliche Rekorde';

  @override
  String get gymRecordsSubtitle =>
      'Deine Bestleistung für jede gewichtete Übung.';

  @override
  String get gymRecordsEmpty =>
      'Noch keine gewichteten Übungen erfasst. Trage ein Gewicht zu einem Satz ein, um deine Bestleistungen zu verfolgen.';

  @override
  String gymRecordsLastDone(String date) {
    return 'Zuletzt $date';
  }

  @override
  String gymRecordsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einheiten',
      one: '1 Einheit',
    );
    return '$_temp0';
  }

  @override
  String get gymExerciseBack => 'Zurück zu Rekorden';

  @override
  String get gymExerciseEmpty => 'Noch kein Verlauf für diese Übung.';

  @override
  String gymSinceFirstUp(String delta) {
    return '+$delta seit der ersten Einheit';
  }

  @override
  String gymSinceFirstDown(String delta) {
    return '−$delta seit der ersten Einheit';
  }

  @override
  String get gymSinceFirstFlat => 'keine Veränderung seit der ersten Einheit';

  @override
  String gymDetailLastTime(String date) {
    return 'Letztes Mal $date';
  }

  @override
  String get gymVolumeLabel => 'Volumen';

  @override
  String get gymDeleteConfirmTitle => 'Training löschen?';

  @override
  String get gymDeleteConfirmBody =>
      'Dadurch werden das Training und seine Sätze dauerhaft entfernt.';

  @override
  String get clubEventMembersOnly => 'Nur für Mitglieder';

  @override
  String get clubEventLogAsWorkout => 'Als Training erfassen';

  @override
  String get clubEventLogAsWorkoutHint =>
      'Füge diesen Kurs deinem eigenen Gym-Log hinzu — du kannst die Details vor dem Speichern anpassen.';

  @override
  String get clubEventLogAsWorkoutSaved => 'Zu deinem Gym-Log hinzugefügt';

  @override
  String get gymEditorNewTitle => 'Neues Training';

  @override
  String get gymEditorEditTitle => 'Training bearbeiten';

  @override
  String get gymEditorTitleLabel => 'Titel (optional)';

  @override
  String get gymEditorTitlePlaceholder => 'z. B. Push-Tag';

  @override
  String get gymEditorExercisePlaceholder => 'Übungsname';

  @override
  String get gymEditorRemoveExercise => 'Übung entfernen';

  @override
  String get gymEditorRemoveSet => 'Satz entfernen';

  @override
  String get gymEditorAddSet => 'Satz hinzufügen';

  @override
  String get gymEditorAddExercise => 'Übung hinzufügen';

  @override
  String get gymEditorShare => 'Im Feed teilen';

  @override
  String get gymEditorCancel => 'Abbrechen';

  @override
  String get gymEditorSave => 'Training speichern';

  @override
  String get gymEditorNeedExercise =>
      'Füge mindestens eine Übung mit Namen hinzu.';

  @override
  String get gymSaveFailed => 'Training konnte nicht gespeichert werden.';

  @override
  String get gymRoutineLink => 'Routinen';

  @override
  String get gymRoutineTitle => 'Routinen';

  @override
  String get gymRoutineNew => 'Neue Routine';

  @override
  String get gymRoutineBack => 'Zurück zu Routinen';

  @override
  String get gymRoutineNotFound => 'Routine nicht gefunden.';

  @override
  String gymRoutineExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Übungen',
      one: '$count Übung',
    );
    return '$_temp0';
  }

  @override
  String get gymRoutineStart => 'Routine starten';

  @override
  String get gymRoutinePublishLabel => 'In einem Club veröffentlichen';

  @override
  String get gymRoutinePublishPick => 'Club auswählen…';

  @override
  String get gymRoutinePublish => 'Veröffentlichen';

  @override
  String get gymRoutinePublishSuccess => 'Routine im Club veröffentlicht.';

  @override
  String get gymRoutinePublishFailed =>
      'Routine konnte nicht veröffentlicht werden.';

  @override
  String get gymRoutineClubTemplateBadge => 'Club-Vorlage';

  @override
  String get gymRoutineDelete => 'Löschen';

  @override
  String get gymRoutineDeleteConfirmTitle => 'Routine löschen?';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'Dies entfernt die Routine dauerhaft. Protokollierte Workouts bleiben erhalten.';

  @override
  String get gymRoutineDeleted => 'Routine gelöscht';

  @override
  String get gymRoutineCreated => 'Routine gespeichert';

  @override
  String get gymRoutineSaveFailed => 'Routine konnte nicht gespeichert werden.';

  @override
  String get gymRoutineEmptyTitle => 'Noch keine Routinen';

  @override
  String get gymRoutineEmptyBody =>
      'Speichere ein protokolliertes Workout als Routine oder erstelle eine neue, um sie wiederzuverwenden.';

  @override
  String get gymRoutineTargetReps => 'Ziel-Wiederholungen';

  @override
  String gymRoutineTargetWeight(String unit) {
    return 'Zielgewicht ($unit)';
  }

  @override
  String get gymRoutineEditorNewTitle => 'Neue Routine';

  @override
  String get gymRoutineEditorTitleLabel => 'Name der Routine';

  @override
  String get gymRoutineEditorTitlePlaceholder => 'z. B. Push-Tag A';

  @override
  String get gymRoutineEditorNotesLabel => 'Notizen (optional)';

  @override
  String get gymRoutineEditorSave => 'Routine speichern';

  @override
  String get gymRoutineEditorCancel => 'Abbrechen';

  @override
  String get gymRoutineEditorNeedTitle => 'Gib der Routine einen Namen.';

  @override
  String get gymRoutineEditorNeedExercise =>
      'Füge mindestens eine Übung mit Namen hinzu.';

  @override
  String get gymRoutineSaveAsRoutine => 'Als Routine speichern';

  @override
  String get gymRoutineRepeatLast => 'Letztes wiederholen';

  @override
  String get gymRoutineTargetRepsMax => 'bis';

  @override
  String get gymRoutineTargetDuration => 'Zielzeit (s)';

  @override
  String get gymRoutineTargetDistance => 'Zieldistanz (m)';

  @override
  String get gymRoutineRestLabel => 'Pause (s)';

  @override
  String get gymRoutineSetType => 'Satztyp';

  @override
  String get gymRoutineSetTypeWarmup => 'Aufwärmen';

  @override
  String get gymRoutineSetTypeWorking => 'Arbeitssatz';

  @override
  String get gymRoutineSetTypeDropset => 'Dropsatz';

  @override
  String get gymRoutineSetTypeAmrap => 'AMRAP';

  @override
  String get gymRoutineSetTypeFailure => 'Bis zum Versagen';

  @override
  String get gymRoutineSetTypeBackoff => 'Back-off';

  @override
  String get gymRoutineModality => 'Gemessen als';

  @override
  String get gymRoutineModalityWeightReps => 'Gewicht × Wdh.';

  @override
  String get gymRoutineModalityTime => 'Zeit';

  @override
  String get gymRoutineModalityDistance => 'Distanz';

  @override
  String get gymRoutineModalityBodyweightReps => 'Körpergewicht-Wdh.';

  @override
  String get gymRoutineSupersetToggle => 'Supersatz mit der nächsten Übung';

  @override
  String gymRoutineSupersetBadge(int group) {
    return 'Supersatz $group';
  }

  @override
  String get gymRoutineAdvanced => 'Erweitert';

  @override
  String get gymRoutineProgression => 'Progression';

  @override
  String get gymRoutineProgressionNone => 'Keine';

  @override
  String get gymRoutineProgressionLinear => 'Linear';

  @override
  String get gymRoutineProgressionDoubleProgression => 'Doppelte Progression';

  @override
  String get gymRoutineProgressionFiveByFive => '5×5';

  @override
  String get gymRoutineProgressionPercentCycle => '% des 1RM-Zyklus';

  @override
  String get gymRoutineProgressionRpeAutoreg => 'RPE-Autoregulation';

  @override
  String gymRoutineProgressionIncrementLabel(String unit) {
    return 'Gewichtsschritt ($unit)';
  }

  @override
  String get gymRoutineProgressionPercentLabel => '% des 1RM';

  @override
  String gymRoutineProgressionOneRmLabel(String unit) {
    return '1RM ($unit)';
  }

  @override
  String get gymRoutineProgressionTargetRpeLabel => 'Ziel-RPE';

  @override
  String get gymRoutineNextTarget => 'Nächstes Ziel';

  @override
  String get gymRoutineNextTargetIncreaseWeight =>
      'Nächstes Mal Gewicht erhöhen';

  @override
  String get gymRoutineNextTargetIncreaseReps =>
      'Nächstes Mal Wiederholungen erhöhen';

  @override
  String get gymRoutineNextTargetHold => 'Halten — Ziel wiederholen';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — Gewicht reduzieren';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'Wdh.-Anstieg $from→$to';
  }

  @override
  String get nutritionTitle => 'Ernährung';

  @override
  String get nutritionLogFood => 'Essen erfassen';

  @override
  String get nutritionCalories => 'Kalorien';

  @override
  String get nutritionProtein => 'Eiweiß';

  @override
  String get nutritionCarbs => 'Kohlenhydrate';

  @override
  String get nutritionFat => 'Fett';

  @override
  String get nutritionWater => 'Wasser';

  @override
  String get nutritionWaterAdd => 'Wasser hinzufügen';

  @override
  String get nutritionWaterRemove => 'Wasser entfernen';

  @override
  String get nutritionNoTargets =>
      'Gib in der Web-App Größe, Gewicht, Alter und Geschlecht an, um Kalorien- und Makro-Ziele zu sehen.';

  @override
  String get nutritionWeeklyTrend => 'Letzte 7 Tage';

  @override
  String nutritionCaloriesLeft(int n) {
    return '$n kcal übrig';
  }

  @override
  String nutritionCaloriesOver(int n) {
    return '$n kcal über dem Ziel';
  }

  @override
  String get nutritionOnTarget => 'Ziel erreicht';

  @override
  String nutritionMacroOver(int n) {
    return '$n über dem Ziel';
  }

  @override
  String get nutritionMacroReached => 'Ziel erreicht';

  @override
  String nutritionWaterAmount(String consumed, String target) {
    return '$consumed / $target L';
  }

  @override
  String get nutritionWaterGoalReached => 'Ziel erreicht';

  @override
  String nutritionWaterRemaining(int n) {
    return '$n ml übrig';
  }

  @override
  String get nutritionWeekOnGoal => 'Im Ziel';

  @override
  String nutritionWeekUnderGoal(int n) {
    return '$n unter Ziel/Tag';
  }

  @override
  String nutritionWeekOverGoal(int n) {
    return '$n über Ziel/Tag';
  }

  @override
  String get nutritionGoalLine => 'Tagesziel';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return 'Ziel $base + $exercise kcal heute verbrannt';
  }

  @override
  String get dashGymReadinessIncluded =>
      'Aktuelle Gym-Einheiten fließen in deine Ermüdung ein.';

  @override
  String get dashGymReadinessExcluded =>
      'Gym-Belastung ist von deiner Lauf-Bereitschaft ausgenommen.';

  @override
  String get prefsExcludeGymFromReadiness =>
      'Gym-Belastung von der Lauf-Bereitschaft ausschließen';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'Standardmäßig erhöhen Gym-Einheiten deine Ermüdung und senken deine Bereitschaft, wie ein Lauf. Aktiviere dies, um Fitness, Ermüdung und Form nur auf Läufen basieren zu lassen.';

  @override
  String get nutritionEmptyTitle => 'Heute noch nichts erfasst';

  @override
  String get nutritionEmptyBody =>
      'Erfasse eine Mahlzeit, um Kalorien und Makros zu verfolgen.';

  @override
  String get nutritionSlotBreakfast => 'Frühstück';

  @override
  String get nutritionSlotLunch => 'Mittagessen';

  @override
  String get nutritionSlotDinner => 'Abendessen';

  @override
  String get nutritionSlotSnack => 'Snack';

  @override
  String get nutritionMealProtein => 'Protein';

  @override
  String get nutritionMealCarbs => 'Kohlenhydrate';

  @override
  String get nutritionMealFat => 'Fett';

  @override
  String get nutritionMealItemsHeading => 'Einträge';

  @override
  String get nutritionMealNoItems => 'Für diese Mahlzeit nichts erfasst.';

  @override
  String get nutritionMealTrendHeading => 'Letzte 7 Tage';

  @override
  String get nutritionDelete => 'Löschen';

  @override
  String get nutritionDeleteEntryTitle => 'Diesen Eintrag löschen?';

  @override
  String nutritionDeleteEntryMessage(String item) {
    return '$item wird aus dem heutigen Protokoll entfernt.';
  }

  @override
  String get nutritionOfflineQueued =>
      'Offline – Änderungen werden später synchronisiert';

  @override
  String get nutritionOfflineCached =>
      'Offline – gespeicherte Einträge werden angezeigt';

  @override
  String get nutritionLogTitle => 'Essen erfassen';

  @override
  String get nutritionSearchHint => 'Nach einem Lebensmittel suchen';

  @override
  String get nutritionSearching => 'Suche läuft…';

  @override
  String get nutritionNoResults =>
      'Keine Treffer. Versuche einen anderen Begriff oder gib es unten manuell ein.';

  @override
  String get nutritionSearchFailed =>
      'Suche fehlgeschlagen. Prüfe deine Verbindung und versuche es erneut oder gib es unten manuell ein.';

  @override
  String get nutritionSearchRetry => 'Suche wiederholen';

  @override
  String get nutritionSaveFailed =>
      'Essen konnte nicht protokolliert werden. Versuche es erneut.';

  @override
  String get nutritionMealSlot => 'Mahlzeit';

  @override
  String get nutritionManualEntry => 'Manuell eingeben';

  @override
  String get nutritionItemName => 'Bezeichnung';

  @override
  String get nutritionPortionGrams => 'Portion (g)';

  @override
  String get nutritionAdd => 'Hinzufügen';

  @override
  String get nutritionCancel => 'Abbrechen';

  @override
  String get sessionTitle => 'Sessions';

  @override
  String get sessionEmpty => 'Noch keine Session-Pläne.';

  @override
  String get sessionEmptyHint =>
      'Erstelle im Web eine wiederverwendbare Yoga-, Pilates- oder Kurs-Abfolge.';

  @override
  String get sessionUntitled => 'Session ohne Titel';

  @override
  String get sessionNotFound => 'Session-Plan nicht gefunden.';

  @override
  String get sessionMakePublic => 'Öffentlich machen';

  @override
  String get sessionMakePrivate => 'Privat machen';

  @override
  String get sessionVisibilityError =>
      'Sichtbarkeit konnte nicht geändert werden.';

  @override
  String get sessionSteps => 'Abfolge';

  @override
  String sessionStepHold(Object name, Object seconds) {
    return '$name · halten ${seconds}s';
  }

  @override
  String sessionStepReps(Object name, Object reps) {
    return '$name · $reps Wdh.';
  }

  @override
  String sessionStepFlow(Object name, Object seconds) {
    return '$name · Flow ${seconds}s';
  }

  @override
  String sessionSideLeft(Object name) {
    return '$name (links)';
  }

  @override
  String sessionSideRight(Object name) {
    return '$name (rechts)';
  }

  @override
  String sessionEstDuration(Object minutes) {
    return 'ca. $minutes Min.';
  }

  @override
  String get gymSessionStart => 'Einheit starten';

  @override
  String gymSessionStep(Object exercise, Object set, Object total) {
    return '$exercise · Satz $set von $total';
  }

  @override
  String get gymSessionComplete => 'Einheit abgeschlossen';

  @override
  String get gymSessionSkipSet => 'Satz überspringen';

  @override
  String get gymSessionRewind => 'Zurück';

  @override
  String get gymSessionAbandon => 'Abbrechen';

  @override
  String get gymSessionFinish => 'Fertig';

  @override
  String get gymSessionDiscardTitle => 'Einheit verwerfen?';

  @override
  String get gymSessionDiscardBody =>
      'Dein Fortschritt in dieser Einheit wird nicht gespeichert.';

  @override
  String get gymSessionDiscardConfirm => 'Verwerfen';

  @override
  String get gymSessionSaved => 'Training gespeichert';

  @override
  String get gymSessionSaveFailed => 'Training konnte nicht gespeichert werden';

  @override
  String gymSessionSetProgress(Object done, Object total) {
    return '$done/$total';
  }

  @override
  String get gymSessionLogSet => 'Satz abschließen';

  @override
  String get gymSessionRest => 'Pause';

  @override
  String gymSessionRestRemaining(Object seconds) {
    return 'Pause ${seconds}s';
  }

  @override
  String get gymSessionRestSkip => 'Pause überspringen';

  @override
  String get gymSessionTarget => 'Ziel';

  @override
  String gymReviewAdherence(Object pct) {
    return '$pct% Umsetzung';
  }

  @override
  String get gymReviewVerdictCompleted => 'Abgeschlossen';

  @override
  String get gymReviewVerdictPartial => 'Teilweise erledigt';

  @override
  String get gymReviewVerdictAbandoned => 'Abgebrochen';

  @override
  String get gymReviewStatusHit => 'Erreicht';

  @override
  String get gymReviewStatusPartial => 'Teilweise';

  @override
  String get gymReviewStatusMissed => 'Verpasst';

  @override
  String get gymReviewStatusExtra => 'Extra';

  @override
  String get sessionRunStart => 'Einheit starten';

  @override
  String sessionRunStep(Object name) {
    return '$name';
  }

  @override
  String get sessionRunDone => 'Fertig';

  @override
  String get sessionRunSkip => 'Überspringen';

  @override
  String get sessionRunPause => 'Pause';

  @override
  String get sessionRunResume => 'Fortsetzen';

  @override
  String get sessionRunAbandon => 'Abbrechen';

  @override
  String get sessionRunFinish => 'Beenden';

  @override
  String sessionRunRemaining(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get sessionRunComplete => 'Einheit abgeschlossen';

  @override
  String get sessionRunSaved => 'Einheit gespeichert';

  @override
  String get sessionRunSaveFailed => 'Einheit konnte nicht gespeichert werden';

  @override
  String get sessionRunDiscardTitle => 'Einheit verwerfen?';

  @override
  String get sessionRunDiscardBody =>
      'Dein Fortschritt in dieser Einheit wird nicht gespeichert.';

  @override
  String get sessionRunDiscardConfirm => 'Verwerfen';

  @override
  String get sessionRunVerdictCompleted => 'Abgeschlossen';

  @override
  String get sessionRunVerdictPartial => 'Teilweise erledigt';

  @override
  String get sessionRunVerdictAbandoned => 'Abgebrochen';

  @override
  String sessionRunStepCount(int index, int total) {
    return 'Schritt $index von $total';
  }

  @override
  String get sessionRunSwitchSides => 'Seite wechseln';

  @override
  String get coachingTitle => 'Coaching';

  @override
  String get coachingLede =>
      'Betreue Athleten, indem du einen Einladungslink teilst, und sieh dir ihr Training an. Oder folge hier deinem eigenen Coach.';

  @override
  String get coachingCancel => 'Abbrechen';

  @override
  String get coachingMyAthletes => 'Meine Athleten';

  @override
  String get coachingMyAthletesSub =>
      'Läufer, die deine Einladung angenommen haben';

  @override
  String get coachingInviteAnAthlete => 'Athlet einladen';

  @override
  String get coachingCreating => 'Wird erstellt…';

  @override
  String get coachingPendingInvite => 'Ausstehende Einladung';

  @override
  String coachingPendingInviteSub(String date) {
    return 'Erstellt am $date · noch nicht angenommen';
  }

  @override
  String get coachingCopyLink => 'Link kopieren';

  @override
  String get coachingShareLink => 'Link teilen';

  @override
  String get coachingRevoke => 'Widerrufen';

  @override
  String get coachingNoAthletes =>
      'Noch keine Athleten. Lade einen ein, um zu starten.';

  @override
  String get coachingRunner => 'Läufer';

  @override
  String coachingCoachingSince(String date) {
    return 'Coaching seit $date';
  }

  @override
  String get coachingReview => 'Ansehen';

  @override
  String get coachingRemove => 'Entfernen';

  @override
  String get coachingMyCoaches => 'Meine Coaches';

  @override
  String get coachingMyCoachesSub => 'Coaches, die dein Training sehen können';

  @override
  String get coachingNoCoaches =>
      'Du hast noch keine Coach-Einladung angenommen.';

  @override
  String get coachingCoach => 'Coach';

  @override
  String coachingLinkedSince(String date) {
    return 'Verknüpft seit $date';
  }

  @override
  String get coachingLeave => 'Verlassen';

  @override
  String get coachingInviteLinkCopied => 'Einladungslink kopiert';

  @override
  String get coachingThisAthlete => 'diesen Athleten';

  @override
  String get coachingThisCoach => 'diesen Coach';

  @override
  String get coachingRevokeTitle => 'Einladung widerrufen?';

  @override
  String get coachingRevokeBody =>
      'Der Einladungslink funktioniert dann nicht mehr. Du kannst jederzeit einen neuen erstellen.';

  @override
  String get coachingRemoveAthleteTitle => 'Athlet entfernen?';

  @override
  String coachingRemoveAthleteBody(String name) {
    return 'Coaching von $name beenden? Du verlierst den Zugriff auf ihre Läufe und Pläne.';
  }

  @override
  String get coachingLeaveCoachTitle => 'Coach verlassen?';

  @override
  String coachingLeaveCoachBody(String name) {
    return 'Dein Training nicht mehr mit $name teilen?';
  }

  @override
  String coachingLoadError(String error) {
    return 'Coaching konnte nicht geladen werden: $error';
  }

  @override
  String coachingCreateInviteError(String error) {
    return 'Einladung konnte nicht erstellt werden: $error';
  }

  @override
  String coachingRevokeInviteError(String error) {
    return 'Einladung konnte nicht widerrufen werden: $error';
  }

  @override
  String coachingRemoveAthleteError(String error) {
    return 'Athlet konnte nicht entfernt werden: $error';
  }

  @override
  String coachingEndLinkError(String error) {
    return 'Verknüpfung konnte nicht beendet werden: $error';
  }

  @override
  String get coachingAthleteAthleteFallback => 'Athlet';

  @override
  String get coachingAthleteRunnerFallback => 'Läufer';

  @override
  String coachingAthleteCoachingSince(String date) {
    return 'Coaching seit $date';
  }

  @override
  String get coachingAthletePlanCompliance => 'Planeinhaltung';

  @override
  String get coachingAthleteNoActivePlan => 'Kein aktiver Trainingsplan.';

  @override
  String get coachingAthleteAssignTitle => 'Plan zuweisen';

  @override
  String coachingAthleteAssignHint(String name) {
    return 'Wähle einen deiner Pläne, um ihn $name zuzuweisen.';
  }

  @override
  String get coachingAthleteAssignSelectLabel => 'Plan';

  @override
  String get coachingAthleteAssignSelectPlaceholder => 'Plan auswählen…';

  @override
  String get coachingAthleteAssignStartLabel => 'Startdatum';

  @override
  String get coachingAthleteAssigning => 'Wird zugewiesen…';

  @override
  String get coachingAthleteAssignButton => 'Plan zuweisen';

  @override
  String get coachingAthleteAssignNoPlans =>
      'Erstelle zuerst einen Trainingsplan, dann kannst du ihn deinen Athleten zuweisen.';

  @override
  String get coachingAthleteAssignedByYou => 'Von dir zugewiesen';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'Dieser Athlet hat bereits einen aktiven Plan. Er muss ihn beenden, bevor du einen neuen zuweisen kannst.';

  @override
  String get coachingAthleteComplete => 'abgeschlossen';

  @override
  String coachingAthleteDoneCount(int done, int total) {
    return '$done von $total erledigt';
  }

  @override
  String coachingAthleteMissedCount(int n) {
    return '$n verpasst';
  }

  @override
  String get coachingAthleteStatusDone => 'Erledigt';

  @override
  String get coachingAthleteStatusMissed => 'Verpasst';

  @override
  String get coachingAthleteStatusUpcoming => 'Anstehend';

  @override
  String get coachingAthleteRecentRuns => 'Letzte Läufe';

  @override
  String get coachingAthleteNoRunsYet => 'Noch keine Läufe erfasst.';

  @override
  String get coachingAthletePrivate => 'Privat';

  @override
  String coachingAthleteAssignSuccess(String name) {
    return 'Plan $name zugewiesen';
  }

  @override
  String coachingAthleteLoadError(String error) {
    return 'Athlet konnte nicht geladen werden: $error';
  }

  @override
  String get routeMarkerHeading => 'Streckenmarker';

  @override
  String get routeMarkerAdd => 'Marker hinzufügen';

  @override
  String get routeMarkerEmpty =>
      'Noch keine Streckenmarker. Füge Verpflegungsstationen, Cut-offs und mehr entlang der Strecke hinzu.';

  @override
  String get routeMarkerEdit => 'Marker bearbeiten';

  @override
  String get routeMarkerDelete => 'Löschen';

  @override
  String get routeMarkerCancel => 'Abbrechen';

  @override
  String get routeMarkerSave => 'Speichern';

  @override
  String get routeMarkerSaving => 'Speichern…';

  @override
  String get routeMarkerKindLabel => 'Typ';

  @override
  String get routeMarkerNameLabel => 'Name';

  @override
  String get routeMarkerNamePlaceholder => 'z. B. Verpflegung 2';

  @override
  String get routeMarkerServicesLabel => 'Leistungen';

  @override
  String get routeMarkerCutoffLabel => 'Cut-off-Zeit';

  @override
  String get routeMarkerNoteLabel => 'Notiz';

  @override
  String get routeMarkerTapToPlace =>
      'Tippe auf die Karte, um diesen Marker zu platzieren.';

  @override
  String get routeMarkerPlaced =>
      'Platziert. Tippe erneut auf die Karte, um ihn zu verschieben.';

  @override
  String routeMarkerCutoffAt(String time) {
    return 'Cut-off $time';
  }

  @override
  String get routeMarkerLabelRequired => 'Gib dem Marker einen Namen.';

  @override
  String get routeMarkerPlaceRequired =>
      'Platziere den Marker zuerst auf der Karte.';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Marker konnte nicht gespeichert werden: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Marker konnte nicht gelöscht werden: $error';
  }

  @override
  String get routeMarkerDeleteConfirmTitle => 'Marker löschen?';

  @override
  String get routeMarkerDeleteConfirmMessage =>
      'Dadurch wird der Marker dauerhaft von der Strecke entfernt.';

  @override
  String get routeMarkerKindAidStation => 'Verpflegungsstation';

  @override
  String get routeMarkerKindCutoff => 'Cut-off';

  @override
  String get routeMarkerKindCrewAccess => 'Crew / Parken';

  @override
  String get routeMarkerKindHazard => 'Gefahr';

  @override
  String get routeMarkerKindNote => 'Notiz';

  @override
  String get routeMarkerKindClimb => 'Anstieg';

  @override
  String get routeMarkerKindCustom => 'Benutzerdefiniert';

  @override
  String get routeMarkerServiceWater => 'Wasser';

  @override
  String get routeMarkerServiceFood => 'Essen';

  @override
  String get routeMarkerServiceMedical => 'Sanitäter';

  @override
  String get routeMarkerServiceToilets => 'Toiletten';

  @override
  String get routeMarkerServiceDropBag => 'Dropbag';

  @override
  String get clubFormEditTitle => 'Club bearbeiten';

  @override
  String get clubEditorWebsite => 'Webseite';

  @override
  String get clubEditorInstagram => 'Instagram';

  @override
  String get clubEditorStrava => 'Strava';

  @override
  String get clubEditorFacebook => 'Facebook';

  @override
  String get clubEditorSaveChanges => 'Änderungen speichern';

  @override
  String get clubDetailVisitWebsite => 'Webseite besuchen';

  @override
  String get clubDetailEditClub => 'Club bearbeiten';

  @override
  String get roadbookTitle => 'Roadbook';

  @override
  String get roadbookCrewSheet => 'Roadbook (Crew-Sheet)';

  @override
  String get roadbookGoalTime => 'Zielzeit';

  @override
  String get roadbookStartTime => 'Startzeit';

  @override
  String get roadbookEffort => 'Aufwand';

  @override
  String get roadbookEven => 'Gleichmäßig';

  @override
  String get roadbookStart => 'Start';

  @override
  String get roadbookFinish => 'Ziel';

  @override
  String get roadbookShare => 'Teilen';

  @override
  String get roadbookNoMarkers =>
      'Füge Streckenmarker hinzu, um ein Roadbook zu erstellen.';

  @override
  String get roadbookAddElevation => 'Höhendaten hinzufügen';

  @override
  String get roadbookElevationUnavailable =>
      'Keine Höhendaten für diese Route verfügbar';

  @override
  String roadbookSummary(String distance, String vert, String time) {
    return '$distance · $vert Anstieg · Ziel $time';
  }

  @override
  String get roadbookFuel => 'Verpflegung';

  @override
  String get roadbookHeat => 'Hitze';

  @override
  String get roadbookCarbs => 'Kohlenhydrate';

  @override
  String get roadbookFluid => 'Flüssigkeit';

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
    return 'mitnehmen: $gels Gels · $fluid ml';
  }

  @override
  String get checkpointCheckinAction => 'Checkpoint-Check-in';

  @override
  String get checkpointCheckinTitle => 'Verpflegungsstation-Check-in';

  @override
  String get checkpointSyncNow => 'Jetzt synchronisieren';

  @override
  String get checkpointPending => 'Nicht synchronisiert';

  @override
  String get checkpointLoadFailed => 'Checkpoints konnten nicht geladen werden';

  @override
  String get checkpointRetry => 'Erneut versuchen';

  @override
  String get checkpointNone =>
      'Dieses Rennen hat noch keine Checkpoints. Lege sie im Web an, bevor die Crew Läufer eincheckt.';

  @override
  String get checkpointPickLabel => 'CHECKPOINT';

  @override
  String get checkpointBibLabel => 'Startnummer';

  @override
  String get checkpointBibHint => 'Startnummer scannen oder eingeben';

  @override
  String get checkpointBibRequired => 'Gib zuerst eine Startnummer ein';

  @override
  String get checkpointStampIn => 'EINGANG stempeln';

  @override
  String get checkpointStampOut => 'AUSGANG stempeln';

  @override
  String checkpointStampedIn(String bib) {
    return 'Startnummer $bib eingestempelt';
  }

  @override
  String checkpointStampedOut(String bib) {
    return 'Startnummer $bib ausgestempelt';
  }

  @override
  String get checkpointStampFailed => 'Stempel konnte nicht gespeichert werden';

  @override
  String checkpointLoggedHere(int count) {
    return 'HIER ERFASST ($count)';
  }

  @override
  String get checkpointNoneLoggedHere =>
      'An diesem Checkpoint wurden noch keine Läufer erfasst.';

  @override
  String checkpointBibRow(String bib) {
    return 'Startnummer $bib';
  }

  @override
  String checkpointInOut(String inTime, String outTime) {
    return 'Ein $inTime · Aus $outTime';
  }

  @override
  String get checkpointWeighInTitle => 'Wiegen';

  @override
  String get checkpointWeighInConsentBlurb =>
      'Körpergewicht und Hinweise zum medizinischen Stopp sind Gesundheitsdaten und werden nur mit Einwilligung des Läufers erfasst und sind nur für Rennoffizielle sichtbar.';

  @override
  String get checkpointWeighInConsent =>
      'Läufer willigt in die Erfassung von Gesundheitsdaten ein';

  @override
  String get checkpointWeighInWeightKg => 'Körpergewicht (kg)';

  @override
  String get checkpointMedicalHold => 'Medizinischen Stopp anordnen';

  @override
  String get checkpointWeighInSave => 'Speichern & stempeln';

  @override
  String get checkpointCancel => 'Abbrechen';
}
