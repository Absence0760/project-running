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
}
