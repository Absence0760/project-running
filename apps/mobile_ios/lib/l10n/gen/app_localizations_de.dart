// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

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
  String get runsRangeToday => 'Heute';

  @override
  String get runsRangeWeek => 'Diese Woche';

  @override
  String get runsRangeMonth => 'Letzte 30 Tage';

  @override
  String get runsRangeYear => 'Dieses Jahr';

  @override
  String get runsRangeAll => 'Gesamter Zeitraum';

  @override
  String get runsRangeCustom => 'Benutzerdefiniert…';

  @override
  String runsRangeFrom(String date) {
    return 'Ab $date';
  }

  @override
  String runsRangeUntil(String date) {
    return 'Bis $date';
  }

  @override
  String runsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe',
      one: '$count Lauf',
    );
    return '$_temp0';
  }

  @override
  String get runsDateRangeTooltip => 'Zeitraum';

  @override
  String get runsSortTooltip => 'Sortieren';

  @override
  String get runsSortNewest => 'Neueste zuerst';

  @override
  String get runsSortOldest => 'Älteste zuerst';

  @override
  String get runsSortLongest => 'Längste Distanz';

  @override
  String get runsSortFastest => 'Bestes Tempo';

  @override
  String runsSyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe synchronisieren',
      one: '$count Lauf synchronisieren',
    );
    return '$_temp0';
  }

  @override
  String get runsRefreshTooltip => 'Aus der Cloud aktualisieren';

  @override
  String get runsOfflineTooltip => 'Offline';

  @override
  String runsSelectionTitle(int count) {
    return '$count ausgewählt';
  }

  @override
  String get runsSelectAllTooltip => 'Alle auswählen';

  @override
  String get runsClearSelectionTooltip => 'Leeren';

  @override
  String get runsDeleteTooltip => 'Löschen';

  @override
  String get runsCancelTooltip => 'Abbrechen';

  @override
  String get runsAddRun => 'Lauf hinzufügen';

  @override
  String get runsAddRunTooltip => 'Lauf manuell hinzufügen';

  @override
  String runsLoadMore(int count) {
    return '$count weitere laden';
  }

  @override
  String get runsNoMatch => 'Keine Läufe entsprechen diesen Filtern';

  @override
  String get runsClearFilters => 'Filter zurücksetzen';

  @override
  String get runsEmptyTitle => 'Noch keine Läufe';

  @override
  String get runsEmptyBody =>
      'Tippe auf den Lauf-Tab, um deinen ersten Lauf zu starten';

  @override
  String get runsFilterAll => 'Alle';

  @override
  String get runsSourceAll => 'Alle Quellen';

  @override
  String runsSourceLabel(String source) {
    return 'Quelle: $source';
  }

  @override
  String get runsSourceFilterTooltip => 'Nach Quelle filtern';

  @override
  String get runsSourceRecorded => 'Aufgezeichnet';

  @override
  String get runsSourceWatch => 'Uhr';

  @override
  String get runsSourceStrava => 'Strava';

  @override
  String get runsSourceParkrun => 'parkrun';

  @override
  String get runsSourceHealthKit => 'HealthKit';

  @override
  String get runsSourceHealthConnect => 'Health Connect';

  @override
  String get runsRangePickerTitle => 'Daten auswählen';

  @override
  String get runsRangeStart => 'Start';

  @override
  String get runsRangeEnd => 'Ende';

  @override
  String get runsRangeTapDate => 'Datum antippen';

  @override
  String get runsRangeApply => 'Anwenden';

  @override
  String get runsRangeClear => 'Leeren';

  @override
  String get runsPrevMonth => 'Vorheriger Monat';

  @override
  String get runsNextMonth => 'Nächster Monat';

  @override
  String get runsPrevYear => 'Vorheriges Jahr';

  @override
  String get runsNextYear => 'Nächstes Jahr';

  @override
  String runsDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Läufe löschen?',
      one: '$count Lauf löschen?',
    );
    return '$_temp0';
  }

  @override
  String get runsDeleteConfirmBody =>
      'Dies kann nicht rückgängig gemacht werden.';

  @override
  String get runsCancel => 'Abbrechen';

  @override
  String get runsDelete => 'Löschen';

  @override
  String get runsQueuedToSync => 'Zur Synchronisierung eingereiht';

  @override
  String get runsSignInToSync =>
      'Melde dich in den Einstellungen an, um Läufe zu synchronisieren';

  @override
  String get runsRefreshFailed =>
      'Aktualisierung fehlgeschlagen – prüfe deine Verbindung';

  @override
  String get runsLoadMoreFailed => 'Weitere Läufe konnten nicht geladen werden';

  @override
  String runsSyncPartial(int synced, int total, String error) {
    return '$synced/$total synchronisiert. Fehler: $error';
  }

  @override
  String runsSyncTrackFailed(int count) {
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
  String runsSyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Läufe synchronisiert',
      one: '$count Lauf synchronisiert',
    );
    return '$_temp0';
  }

  @override
  String runsDeletePartial(int deleted, int queued) {
    return '$deleted gelöscht; $queued eingereiht – wird erneut versucht, sobald du wieder online bist.';
  }

  @override
  String runsDeleteDone(int count) {
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
}
