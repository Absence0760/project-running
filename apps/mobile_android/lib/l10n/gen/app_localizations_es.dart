// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get prefsLanguage => 'Idioma';

  @override
  String get prefsLanguageSystem => 'Predeterminado del sistema';

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
  String get navHome => 'Inicio';

  @override
  String get navRun => 'Correr';

  @override
  String get navHistory => 'Historial';

  @override
  String get navSocial => 'Social';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get settingsSectionProfile => 'Perfil';

  @override
  String get settingsSectionAppsData => 'Apps y datos';

  @override
  String get settingsSectionAccountLegal => 'Cuenta y aspectos legales';

  @override
  String get prefsSectionUnitsDisplay => 'Unidades y pantalla';

  @override
  String get authEmailLabel => 'Correo electrónico';

  @override
  String get authPasswordLabel => 'Contraseña';

  @override
  String get authOrDivider => 'O';

  @override
  String get signInTitle => 'Iniciar sesión';

  @override
  String get signInHeadline => 'Sincroniza tus carreras entre dispositivos';

  @override
  String get signInSubtitle =>
      'Inicia sesión para respaldar tus carreras y verlas en la app web.';

  @override
  String get signInButton => 'Iniciar sesión';

  @override
  String get signInForgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get signInResetNeedEmail =>
      'Primero escribe tu correo arriba y luego toca ¿Olvidaste tu contraseña?';

  @override
  String get signInResetSent =>
      'Si ese correo está registrado, te hemos enviado un enlace para restablecerla.';

  @override
  String get signInWithApple => 'Iniciar sesión con Apple';

  @override
  String get signInWithGoogle => 'Iniciar sesión con Google';

  @override
  String get signInContinueOffline => 'Continuar sin conexión';

  @override
  String get signInCreateAccountPrompt => '¿No tienes cuenta? Crea una';

  @override
  String get signUpTitle => 'Crear cuenta';

  @override
  String get signUpHeadline => 'Empieza a registrar tus carreras';

  @override
  String get signUpSubtitle =>
      'Crea una cuenta para respaldar tus carreras y verlas en la app web.';

  @override
  String get signUpButton => 'Crear cuenta';

  @override
  String get signUpConfirmAge => 'Tengo 16 años o más';

  @override
  String get signUpAcceptPrefix => 'Acepto las ';

  @override
  String get signUpTermsLink => 'Condiciones del servicio';

  @override
  String get signUpAcceptConjunction => ' y la ';

  @override
  String get signUpPrivacyLink => 'Política de privacidad';

  @override
  String get signUpErrorConfirmAge =>
      'Confirma que tienes 16 años o más para continuar.';

  @override
  String get signUpErrorAcceptTerms =>
      'Acepta las Condiciones del servicio y la Política de privacidad para continuar.';

  @override
  String get signUpContinueWithApple => 'Continuar con Apple';

  @override
  String get signUpContinueWithGoogle => 'Continuar con Google';

  @override
  String get signUpSignInPrompt => '¿Ya tienes una cuenta? Inicia sesión';

  @override
  String signUpCouldNotOpen(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String get onboardingTrackTitle => 'Registra cada carrera';

  @override
  String get onboardingTrackBody =>
      'Grabación por GPS con mapa en vivo, parciales, ritmo, cadencia y desnivel. Funciona totalmente sin conexión: inicia sesión más tarde para sincronizar entre dispositivos.';

  @override
  String get onboardingRoutesTitle => 'Sigue rutas';

  @override
  String get onboardingRoutesBody =>
      'Importa archivos GPX o KML, o sincroniza rutas desde la app web. Recibe alertas de desvío mientras corres.';

  @override
  String get onboardingLocationTitle => 'Acceso a la ubicación';

  @override
  String get onboardingLocationBody =>
      'Threkir registra tus carreras tomando muestras de tu ubicación GPS mientras la app está en primer plano Y en segundo plano (para seguir registrando cuando la pantalla está apagada o cambias de app para hacer una foto). Los datos de ubicación se guardan en tu dispositivo y solo se suben a los servidores de Threkir cuando decides compartir o sincronizar una carrera. Si rechazas la ubicación en segundo plano, las carreras dejarán de registrarse en cuanto salgas de la app: puedes cambiarlo más tarde en Ajustes → Apps → Threkir → Permisos.';

  @override
  String get onboardingPrivacyTitle => '¿Quién ve tus carreras?';

  @override
  String get onboardingPrivacyBody =>
      'Elige un valor predeterminado para las nuevas carreras. Puedes cambiarlo cuando quieras en Ajustes y modificarlo en cualquier carrera concreta.';

  @override
  String get onboardingGrantPermission => 'Conceder permiso';

  @override
  String get onboardingNext => 'Siguiente';

  @override
  String get privacyPrivateTitle => 'Privada';

  @override
  String get privacyPrivateSubtitle =>
      'Solo tú puedes ver tus carreras. Puedes compartir cualquier carrera más tarde.';

  @override
  String get privacyFollowersTitle => 'Seguidores';

  @override
  String get privacyFollowersSubtitle =>
      'Quienes te siguen ven tus nuevas carreras en su feed.';

  @override
  String get privacyPublicTitle => 'Pública';

  @override
  String get privacyPublicSubtitle =>
      'Cualquiera puede encontrar y ver tus carreras.';

  @override
  String get runStart => 'INICIAR';

  @override
  String get runStartA11yLabel => 'Iniciar carrera';

  @override
  String get runChooseRoute => 'Elegir ruta';

  @override
  String get runChangeRoute => 'Cambiar ruta';

  @override
  String get runShareLiveLink => 'Compartir enlace en vivo';

  @override
  String get runTrainingPlans => 'Planes de entrenamiento';

  @override
  String get runTapToCancel => 'Toca para cancelar';

  @override
  String get runFirstRunPrompt => 'Tu primera carrera está a un toque.';

  @override
  String get runLastActivity => 'Última actividad';

  @override
  String get runLastRun => 'Última carrera';

  @override
  String get runFollowing => 'SIGUIENDO';

  @override
  String get runRaceFallbackTitle => 'Carrera';

  @override
  String get runRaceArmed => 'Carrera lista';

  @override
  String get runRaceLive => 'Carrera EN VIVO';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — esperando la salida';
  }

  @override
  String runRaceElapsedTapStart(String label, String elapsed) {
    return '$label — $elapsed transcurridos · toca Iniciar';
  }

  @override
  String get runComplete => 'Carrera completada';

  @override
  String get runStatDistance => 'Distancia';

  @override
  String get runStatTime => 'Tiempo';

  @override
  String get runStatMoving => 'En movimiento';

  @override
  String get runStatPace => 'Ritmo';

  @override
  String get runStatSpeed => 'Velocidad';

  @override
  String get runStatAvgPace => 'Ritmo medio';

  @override
  String get runStatAvgSpeed => 'Velocidad media';

  @override
  String get runStatCalories => 'Calorías';

  @override
  String get runStatElevation => 'Desnivel';

  @override
  String get runStatSteps => 'Pasos';

  @override
  String get runStatCadence => 'Cadencia';

  @override
  String get runStatHeartRate => 'Frec. cardíaca';

  @override
  String get runUnitKcal => 'kcal';

  @override
  String get runUnitMetres => 'm';

  @override
  String get runUnitSpm => 'ppm';

  @override
  String get runUnitBpm => 'lpm';

  @override
  String get runMutePaceCues => 'Silenciar avisos de ritmo';

  @override
  String get runPaceCuesMuted => 'Avisos de ritmo silenciados';

  @override
  String get runSynced => 'Sincronizada';

  @override
  String get runSyncing => 'Sincronizando…';

  @override
  String get runDone => 'Listo';

  @override
  String get runDiscardA11yLabel => 'Descartar carrera';

  @override
  String get runDiscardA11yHint => 'Descarta la grabación actual sin guardarla';

  @override
  String get runResumeA11yLabel => 'Reanudar carrera';

  @override
  String get runPauseA11yLabel => 'Pausar carrera';

  @override
  String get runResumeA11yHint => 'Reanuda la grabación en pausa';

  @override
  String get runPauseA11yHint => 'Pausa la grabación sin finalizarla';

  @override
  String get runMarkLapA11yLabel => 'Marcar vuelta';

  @override
  String runMarkLapWithCountA11yLabel(int count) {
    return 'Marcar vuelta, $count hasta ahora';
  }

  @override
  String get runMarkLapA11yHint => 'Registra el parcial actual';

  @override
  String get runCollapseStatsPanel => 'Contraer panel de estadísticas';

  @override
  String get runExpandStatsPanel => 'Expandir panel de estadísticas';

  @override
  String runRouteRemaining(String distance) {
    return 'faltan $distance';
  }

  @override
  String runOffRoute(int metres) {
    return 'Fuera de ruta — a $metres m';
  }

  @override
  String get runPermissionRevoked => 'Permiso de ubicación revocado';

  @override
  String get runGpsLost => 'Señal GPS perdida — sal a cielo abierto';

  @override
  String get runWeakGps => 'GPS débil — distancia en pausa';

  @override
  String get runA11yStarted => 'Carrera iniciada';

  @override
  String get runA11yResumed => 'Carrera reanudada';

  @override
  String get runA11yPaused => 'Carrera en pausa';

  @override
  String get runA11yFinished => 'Carrera finalizada';

  @override
  String runLapMarked(int count) {
    return 'Vuelta $count marcada';
  }

  @override
  String get runDiscardDialogTitle => '¿Descartar carrera?';

  @override
  String get runDiscardDialogBody => 'Perderás tu progreso.';

  @override
  String get runKeepRunning => 'Seguir corriendo';

  @override
  String get runDiscard => 'Descartar';

  @override
  String get runStartWorkout => 'Iniciar entrenamiento';

  @override
  String get runStartWorkoutSubtitle =>
      'Corre con objetivos de paso en vivo, avisos de audio y un análisis planificado vs. real.';

  @override
  String get runViewWorkoutDetails => 'Ver detalles';

  @override
  String get runWorkoutNoStructure =>
      'Este entrenamiento no tiene una estructura ejecutable.';

  @override
  String runWorkoutLoaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pasos',
      one: '$count paso',
    );
    return 'Entrenamiento cargado · $_temp0 — toca GO para empezar';
  }

  @override
  String get runAbandonWorkoutTitle => '¿Abandonar entrenamiento?';

  @override
  String get runAbandonWorkoutBody =>
      'El plan estructurado termina aquí; la grabación continúa como carrera libre. Puedes detenerte en cualquier momento para guardar lo que hiciste.';

  @override
  String get runCancel => 'Cancelar';

  @override
  String get runAbandon => 'Abandonar';

  @override
  String get runNoRoutesSaved =>
      'No hay rutas guardadas. Importa una desde la pestaña Rutas.';

  @override
  String get runNotificationsOffHint =>
      'Las notificaciones están desactivadas — la notificación de carrera en vivo no se mostrará. La grabación sigue funcionando.';

  @override
  String get runSettings => 'Ajustes';

  @override
  String get runStartAnyway => 'Iniciar de todos modos';

  @override
  String get runOpenSettings => 'Abrir ajustes';

  @override
  String get runNotNow => 'Ahora no';

  @override
  String get runShareSubject => 'Sígueme en vivo';

  @override
  String runCouldNotShareLink(String error) {
    return 'No se pudo compartir el enlace en vivo: $error';
  }

  @override
  String get runHrStrapLostReconnecting =>
      'Banda de FC perdida — reconectando…';

  @override
  String get runHrStrapReconnected => 'Banda de FC reconectada';

  @override
  String get runHrStrapLostNoHr =>
      'Banda de FC perdida — la grabación continúa sin FC.';

  @override
  String get runHrStrapNotFound =>
      'Banda de FC no encontrada — póntela y reconecta.';

  @override
  String get runReconnect => 'Reconectar';

  @override
  String get runHrStrapStillNotFound =>
      'Sigue sin haber banda — la grabación continúa sin FC.';

  @override
  String get runSaveFailedRelaunch =>
      'No se pudo guardar localmente. Reinicia la app para recuperar.';

  @override
  String get runSyncFailedSaveOffline =>
      'Guardada sin conexión. Sincroniza desde Carreras.';

  @override
  String get runSavedOffline => 'Guardada sin conexión.';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings =>
      'Sin GPS — el seguimiento empezará cuando la Ubicación esté activada.';

  @override
  String get runGpsBlockedSettings =>
      'Sin GPS — permiso bloqueado. Actívalo para seguir la ruta.';

  @override
  String get runGpsPermissionPending =>
      'Sin GPS — el seguimiento empezará cuando se conceda el permiso.';

  @override
  String get runGpsAllowAllTheTime =>
      'Configura la Ubicación en «Permitir siempre» — las carreras dejan de grabarse cuando cambias de app sin permiso en segundo plano.';

  @override
  String get runGpsSensorFailed =>
      'Grabando sin GPS — no se pudo iniciar el sensor.';

  @override
  String get runAgoJustNow => 'Ahora mismo';

  @override
  String runAgoMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String runAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count horas',
      one: 'hace 1 hora',
    );
    return '$_temp0';
  }

  @override
  String get runAgoYesterday => 'Ayer';

  @override
  String runAgoDays(int count) {
    return 'hace $count días';
  }

  @override
  String runAgoWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count semanas',
      one: 'hace 1 semana',
    );
    return '$_temp0';
  }

  @override
  String runAgoMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count meses',
      one: 'hace 1 mes',
    );
    return '$_temp0';
  }

  @override
  String get runWorkoutAbandonedBand =>
      'Entrenamiento abandonado · corriendo libre';

  @override
  String get runWorkoutCompleteBand =>
      'Entrenamiento completado · toca detener para guardar';

  @override
  String runWorkoutStepHeader(String label, String target, String pace) {
    return '$label · $target @ $pace';
  }

  @override
  String runWorkoutStepCounter(int current, int total) {
    return '$current/$total';
  }

  @override
  String get runWorkoutRewind => 'Retroceder';

  @override
  String get runWorkoutSkip => 'Saltar';

  @override
  String get runWorkoutAbandon => 'Abandonar';

  @override
  String runWorkoutRemainingYards(int yards) {
    return 'faltan $yards yd';
  }

  @override
  String runWorkoutRemainingMetres(int metres) {
    return 'faltan $metres m';
  }

  @override
  String runWorkoutRemainingDuration(String duration) {
    return 'faltan $duration';
  }

  @override
  String get runsRangeToday => 'Hoy';

  @override
  String get runsRangeWeek => 'Esta semana';

  @override
  String get runsRangeMonth => 'Últimos 30 días';

  @override
  String get runsRangeYear => 'Este año';

  @override
  String get runsRangeAll => 'Todo el historial';

  @override
  String get runsRangeCustom => 'Personalizado…';

  @override
  String runsRangeFrom(String date) {
    return 'Desde $date';
  }

  @override
  String runsRangeUntil(String date) {
    return 'Hasta $date';
  }

  @override
  String runsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras',
      one: '$count carrera',
    );
    return '$_temp0';
  }

  @override
  String get runsDateRangeTooltip => 'Rango de fechas';

  @override
  String get runsSortTooltip => 'Ordenar';

  @override
  String get runsSortNewest => 'Más recientes primero';

  @override
  String get runsSortOldest => 'Más antiguas primero';

  @override
  String get runsSortLongest => 'Mayor distancia';

  @override
  String get runsSortFastest => 'Mejor ritmo';

  @override
  String runsSyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizar $count carreras',
      one: 'Sincronizar $count carrera',
    );
    return '$_temp0';
  }

  @override
  String get runsRefreshTooltip => 'Actualizar desde la nube';

  @override
  String get runsOfflineTooltip => 'Sin conexión';

  @override
  String runsSelectionTitle(int count) {
    return '$count seleccionadas';
  }

  @override
  String get runsSelectAllTooltip => 'Seleccionar todo';

  @override
  String get runsClearSelectionTooltip => 'Limpiar';

  @override
  String get runsDeleteTooltip => 'Eliminar';

  @override
  String get runsCancelTooltip => 'Cancelar';

  @override
  String get runsAddRun => 'Añadir carrera';

  @override
  String get runsAddRunTooltip => 'Añadir una carrera manualmente';

  @override
  String runsLoadMore(int count) {
    return 'Cargar $count más';
  }

  @override
  String get runsNoMatch => 'Ninguna carrera coincide con estos filtros';

  @override
  String get runsClearFilters => 'Limpiar filtros';

  @override
  String get runsEmptyTitle => 'Aún no hay carreras';

  @override
  String get runsEmptyBody =>
      'Toca la pestaña Correr para iniciar tu primera carrera';

  @override
  String get runsFilterAll => 'Todas';

  @override
  String get runsSourceAll => 'Todas las fuentes';

  @override
  String runsSourceLabel(String source) {
    return 'Fuente: $source';
  }

  @override
  String get runsSourceFilterTooltip => 'Filtrar por fuente';

  @override
  String get runsSourceRecorded => 'Grabada';

  @override
  String get runsSourceWatch => 'Reloj';

  @override
  String get runsSourceStrava => 'Strava';

  @override
  String get runsSourceParkrun => 'parkrun';

  @override
  String get runsSourceHealthKit => 'HealthKit';

  @override
  String get runsSourceHealthConnect => 'Health Connect';

  @override
  String get runsRangePickerTitle => 'Seleccionar fechas';

  @override
  String get runsRangeStart => 'Inicio';

  @override
  String get runsRangeEnd => 'Fin';

  @override
  String get runsRangeTapDate => 'Toca una fecha';

  @override
  String get runsRangeApply => 'Aplicar';

  @override
  String get runsRangeClear => 'Limpiar';

  @override
  String get runsPrevMonth => 'Mes anterior';

  @override
  String get runsNextMonth => 'Mes siguiente';

  @override
  String get runsPrevYear => 'Año anterior';

  @override
  String get runsNextYear => 'Año siguiente';

  @override
  String runsDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Eliminar $count carreras?',
      one: '¿Eliminar $count carrera?',
    );
    return '$_temp0';
  }

  @override
  String get runsDeleteConfirmBody => 'Esto no se puede deshacer.';

  @override
  String get runsCancel => 'Cancelar';

  @override
  String get runsDelete => 'Eliminar';

  @override
  String get runsQueuedToSync => 'En cola para sincronizar';

  @override
  String get runsSignInToSync =>
      'Inicia sesión desde Ajustes para sincronizar las carreras';

  @override
  String get runsRefreshFailed =>
      'No se pudo actualizar — comprueba tu conexión';

  @override
  String get runsLoadMoreFailed => 'No se pudieron cargar más carreras';

  @override
  String runsSyncPartial(int synced, int total, String error) {
    return '$synced/$total sincronizadas. Error: $error';
  }

  @override
  String runsSyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count carreras no pudieron subir su trazado GPS — el resto se sincronizó. Las carreras fallidas se reintentarán en el próximo ciclo.',
      one:
          '$count carrera no pudo subir su trazado GPS — el resto se sincronizó. Se reintentará en el próximo ciclo.',
    );
    return '$_temp0';
  }

  @override
  String runsSyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Las $count carreras sincronizadas',
      one: '$count carrera sincronizada',
    );
    return '$_temp0';
  }

  @override
  String runsDeletePartial(int deleted, int queued) {
    return '$deleted eliminadas; $queued en cola — se reintentará al volver a estar en línea.';
  }

  @override
  String runsDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras eliminadas',
      one: '$count carrera eliminada',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'Añadir carrera';

  @override
  String get addRunSave => 'Guardar';

  @override
  String get addRunSectionWhen => 'Cuándo';

  @override
  String get addRunSectionActivity => 'Actividad';

  @override
  String get addRunSectionRoute => 'Ruta (opcional)';

  @override
  String get addRunSectionDistance => 'Distancia';

  @override
  String get addRunSectionDuration => 'Duración';

  @override
  String get addRunSectionTitle => 'Título (opcional)';

  @override
  String get addRunSectionNotes => 'Notas (opcional)';

  @override
  String get addRunClearRoute => 'Quitar ruta';

  @override
  String get addRunSearchRoutes => 'Buscar rutas guardadas';

  @override
  String get addRunNoRoutes =>
      'Aún no hay rutas guardadas — crea o importa una para adjuntarla aquí';

  @override
  String get addRunDistanceInvalid => 'Introduce una distancia mayor que 0';

  @override
  String get addRunDurationInvalid => 'Introduce una duración';

  @override
  String get addRunTitleHint => 'p. ej. Vuelta del mediodía';

  @override
  String get addRunNotesHint => '¿Cómo te sentiste?';

  @override
  String get addRunSaveButton => 'Guardar carrera';

  @override
  String addRunSaveFailed(String error) {
    return 'No se pudo guardar la carrera: $error';
  }

  @override
  String get addRunSaved => 'Carrera añadida al historial';

  @override
  String get addRunPickerSearchHint => 'Buscar rutas';

  @override
  String get addRunPickerClear => 'Limpiar';

  @override
  String get addRunPickerCancel => 'Cancelar';

  @override
  String addRunPickerNoMatch(String query) {
    return 'Ninguna ruta coincide con \"$query\"';
  }

  @override
  String get addRunPickerNoRoute => 'Sin ruta';

  @override
  String get runDetailDnfBadge => 'DNF';

  @override
  String get runDetailEditTooltip => 'Editar carrera';

  @override
  String get runDetailShareTooltip => 'Compartir carrera';

  @override
  String get runDetailMoreTooltip => 'Más';

  @override
  String get runDetailSaveAsRoute => 'Guardar como ruta';

  @override
  String get runDetailDeleteRun => 'Eliminar carrera';

  @override
  String get runDetailEditTitle => 'Editar carrera';

  @override
  String get runDetailFieldTitle => 'Título';

  @override
  String get runDetailFieldNotes => 'Notas';

  @override
  String get runDetailFieldDistance => 'Distancia';

  @override
  String get runDetailFieldDuration => 'Duración';

  @override
  String get runDetailMarkDnf => 'Marcar como DNF';

  @override
  String get runDetailMarkDnfSubtitle =>
      'Excluye esta carrera de los récords personales';

  @override
  String get runDetailEditInvalid =>
      'Introduce una distancia y duración válidas';

  @override
  String get runDetailSave => 'Guardar';

  @override
  String get runDetailCancel => 'Cancelar';

  @override
  String get runDetailDelete => 'Eliminar';

  @override
  String get runDetailLoadingGps => 'Cargando datos GPS...';

  @override
  String get runDetailGpsUnavailable =>
      'Trazado GPS no disponible sin conexión';

  @override
  String get runDetailPauseReplay => 'Pausar reproducción';

  @override
  String get runDetailReplay => 'Reproducir esta carrera';

  @override
  String get runDetailStatElevGain => 'Desnivel +';

  @override
  String get runDetailStatElevLoss => 'Desnivel -';

  @override
  String get runDetailStatAvgHr => 'FC media';

  @override
  String get runDetailStatAgeGrade => 'Grado por edad';

  @override
  String get runDetailSectionElevation => 'Desnivel';

  @override
  String get runDetailSectionLaps => 'Vueltas';

  @override
  String runDetailLapNumber(int number) {
    return 'Vuelta $number';
  }

  @override
  String get runDetailSectionRunningDynamics => 'Dinámica de carrera';

  @override
  String get runDetailDynVerticalOsc => 'Oscilación vertical';

  @override
  String get runDetailDynGroundContact => 'Contacto con el suelo';

  @override
  String get runDetailDynStrideLength => 'Longitud de zancada';

  @override
  String get runDetailDynAvgPower => 'Potencia media';

  @override
  String get runDetailSectionRouteHistory => 'Historial de la ruta';

  @override
  String get runDetailThisRoute => 'esta ruta';

  @override
  String runDetailPersonalBest(String route) {
    return 'Récord personal en $route';
  }

  @override
  String runDetailBehindPb(String delta) {
    return '$delta detrás del récord';
  }

  @override
  String runDetailAttemptOf(int rank, int total, String pb) {
    return 'Intento $rank de $total  —  Récord: $pb';
  }

  @override
  String get runDetailSectionBestEfforts => 'Mejores marcas';

  @override
  String get runDetailSectionHeartRateZones => 'Zonas de frecuencia cardíaca';

  @override
  String get runDetailHrAvg => 'Media';

  @override
  String get runDetailHrMin => 'Mín';

  @override
  String get runDetailHrMax => 'Máx';

  @override
  String runDetailZoneRow(int number, String label) {
    return 'Zona $number · $label';
  }

  @override
  String get runDetailSectionSplits => 'Parciales';

  @override
  String get runDetailNoGpsForSplits => 'Sin datos GPS para los parciales';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Carrera demasiado corta para un parcial completo de $unit';
  }

  @override
  String get runDetailSectionSegments => 'Segmentos';

  @override
  String get runDetailSaveAsRouteTitle => 'Guardar como ruta';

  @override
  String get runDetailSaveAsRouteBody =>
      'Guarda este trazado GPS como una ruta que podrás seguir de nuevo.';

  @override
  String get runDetailRouteNameLabel => 'Nombre de la ruta';

  @override
  String get runDetailNoTrackToSave =>
      'Esta carrera no tiene trazado GPS para guardar como ruta';

  @override
  String runDetailRouteLinked(String route) {
    return 'Vinculada a $route';
  }

  @override
  String get runDetailRouteLinkFailed => 'No se pudo vincular la ruta';

  @override
  String get runDetailReSnapping => 'Reajustando a las calles…';

  @override
  String runDetailRematchFailed(String error) {
    return 'Reajuste fallido: $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return '\"$name\" guardada — $kept puntos de paso ($smoothed suavizados)';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'No se pudo hacer pública la carrera: $error';
  }

  @override
  String get runDetailMakePublicTitle => '¿Hacer pública esta carrera?';

  @override
  String get runDetailMakePublicBodyZone =>
      'Compartir convierte esta carrera en pública para que cualquiera con el enlace pueda verla. Esta carrera empieza o termina dentro de una de tus zonas de privacidad, así que los espectadores verán un trazado recortado con los segmentos dentro de la zona ocultos.';

  @override
  String get runDetailMakePublicBodyHasZones =>
      'Compartir convierte esta carrera en pública para que cualquiera con el enlace pueda verla. Ninguna de tus zonas de privacidad se cruza con este trazado, así que el trazado completo será visible.';

  @override
  String get runDetailMakePublicBodyNoZones =>
      'Compartir convierte esta carrera en pública para que cualquiera con el enlace pueda verla — incluidos los puntos de inicio y fin de tu carrera. No tienes zonas de privacidad configuradas. Considera añadir una alrededor de tu casa antes de compartir.';

  @override
  String get runDetailMakePublic => 'Hacer pública';

  @override
  String get runDetailDeleteTitle => '¿Eliminar carrera?';

  @override
  String get runDetailDeleteBody => 'Esto no se puede deshacer.';

  @override
  String get runDetailSuggestLink => 'Vincular';

  @override
  String get runDetailSuggestDismiss => 'Descartar';

  @override
  String get runDetailSuggestRanRoute => 'Parece que corriste ';

  @override
  String get runDetailSuggestLinkPrompt => '¿Vincular esta carrera a esa ruta?';

  @override
  String get runDetailMatchPending => 'Ajustando a las calles…';

  @override
  String get runDetailMatchSkipped => 'Sin ajustar (muy pocos puntos)';

  @override
  String get runDetailMatchFailed =>
      'Ajuste fallido — mostrando el trazado sin procesar';

  @override
  String get runDetailMatchMatched => 'Ajustada';

  @override
  String get runDetailRematchQueueing => 'Encolando…';

  @override
  String get runDetailRematch => 'Reajustar';

  @override
  String get runDetailSegStatDistance => 'Distancia';

  @override
  String get runDetailSegStatTime => 'Tiempo';

  @override
  String get runDetailSegStatPace => 'Ritmo';

  @override
  String get runDetailSegStatHr => 'FC';

  @override
  String get runDetailSegStatGain => 'Desnivel +';

  @override
  String get runDetailSegDismiss => 'Descartar';

  @override
  String get publicRunTitle => 'Carrera';

  @override
  String get publicRunLoadError => 'No se pudo cargar esta carrera.';

  @override
  String get publicRunUnavailable =>
      'Esta carrera es privada o ya no está disponible.';

  @override
  String get publicRunAuthorFallback => 'Corredor';

  @override
  String get publicRunStatDistance => 'Distancia';

  @override
  String get publicRunStatTime => 'Tiempo';

  @override
  String get publicRunStatPace => 'Ritmo';

  @override
  String get publicRunSectionSegments => 'Segmentos';

  @override
  String get routesSyncFailedOffline =>
      'No se pudieron sincronizar las rutas — sin conexión';

  @override
  String get routesLoadMoreFailed => 'No se pudieron cargar más rutas';

  @override
  String routesStarUpdateFailed(String error) {
    return 'No se pudo actualizar la estrella: $error';
  }

  @override
  String get routesImportFailedLocalOnly =>
      'Error al importar: elige el archivo del almacenamiento local, no de un selector de documentos solo en la nube.';

  @override
  String routesImported(String name) {
    return '\"$name\" importada';
  }

  @override
  String routesImportFailed(String error) {
    return 'Error al importar: $error';
  }

  @override
  String routesSaved(String name) {
    return '\"$name\" guardada';
  }

  @override
  String get routesEmptyTitle => 'Aún no hay rutas';

  @override
  String get routesEmptyBody =>
      'Toca Crear para dibujar una ruta en el mapa, o importa un archivo GPX, KML o TCX.';

  @override
  String get routesBuild => 'Crear';

  @override
  String get routesImport => 'Importar';

  @override
  String get routesNoMatch => 'Ninguna ruta coincide con estos filtros';

  @override
  String get routesClearFilters => 'Borrar filtros';

  @override
  String routesLoadMore(int count) {
    return 'Cargar $count más';
  }

  @override
  String get routesQueuedToSync => 'En cola para sincronizar';

  @override
  String get routesSavedForOffline => 'Guardado sin conexión';

  @override
  String get routesUnstarRoute => 'Quitar estrella de la ruta';

  @override
  String get routesStarForWatch => 'Marcar para mostrar en el reloj';

  @override
  String get routesDiscover => 'Descubrir';

  @override
  String get routesSyncFromCloud => 'Sincronizar desde la nube';

  @override
  String get routesPublicRoutes => 'Rutas públicas';

  @override
  String get routesHeatmap => 'Mapa de calor';

  @override
  String get routesExplorePublic => 'Explorar rutas públicas';

  @override
  String get routesHeatmapTooltip => 'Mapa de calor de rutas';

  @override
  String get routesSearchHint => 'Buscar rutas por nombre…';

  @override
  String get routesClearSearch => 'Borrar búsqueda';

  @override
  String get routesStarred => 'Con estrella';

  @override
  String routesCountMeta(int visible, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$visible de $total rutas',
      one: '$visible de $total ruta',
    );
    return '$_temp0';
  }

  @override
  String get routesSurfaceAny => 'Cualquier superficie';

  @override
  String get routesSurfaceRoad => 'Carretera';

  @override
  String get routesSurfaceTrail => 'Sendero';

  @override
  String get routesSurfaceMixed => 'Mixta';

  @override
  String get routesDistanceAny => 'Cualquier distancia';

  @override
  String get routesSortNewest => 'Más recientes primero';

  @override
  String get routesSortLongest => 'Más larga';

  @override
  String get routesSortShortest => 'Más corta';

  @override
  String get routesSortMostRun => 'Más recorrida';

  @override
  String get routesSortAlpha => 'A–Z';

  @override
  String routesDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Eliminar $count rutas?',
      one: '¿Eliminar $count ruta?',
    );
    return '$_temp0';
  }

  @override
  String get routesDeleteConfirmBody => 'Esto no se puede deshacer.';

  @override
  String routesSelectionTitle(int count) {
    return '$count seleccionada(s)';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted eliminada(s); $failed con error — comprueba tu conexión.';
  }

  @override
  String routesDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rutas eliminadas.',
      one: '$count ruta eliminada.',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteCleared => 'Ruta borrada';

  @override
  String routeBuilderPointsSummary(int count, String distance) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puntos, $distance',
      one: '$count punto, $distance',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteFailedStraightLines =>
      'No se pudo calcular la ruta — se muestran líneas rectas entre tus puntos.';

  @override
  String routeBuilderSegmentsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count segmentos no pudieron ajustarse a una carretera. Arrastra los puntos afectados para ajustar.',
      one:
          '$count segmento no pudo ajustarse a una carretera. Arrastra el punto afectado para ajustar.',
    );
    return '$_temp0';
  }

  @override
  String routeBuilderRoutingFailed(String error) {
    return 'Error al calcular la ruta: $error';
  }

  @override
  String get routeBuilderTooCloseToPin =>
      'Demasiado cerca de otro punto — arrastra un poco más lejos.';

  @override
  String get routeBuilderPinAlreadyThere =>
      'Ya hay un punto ahí — toca más lejos para añadir otro.';

  @override
  String get routeBuilderTargetTooLong =>
      'Introduce una distancia objetivo de hasta 1000 km.';

  @override
  String get routeBuilderSaveNeedTwo => 'Coloca primero al menos dos puntos.';

  @override
  String routeBuilderSavedLocally(String detail) {
    return 'Guardado localmente. $detail Se sincronizará la próxima vez.';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return 'Ubicación no disponible: $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'No se puede conectar con el servidor. Inicia sesión o comprueba tu conexión e inténtalo de nuevo.';

  @override
  String routeBuilderSaveFailed(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String get routeBuilderSearchHint => 'Buscar lugares…';

  @override
  String get routeBuilderMore => 'Más';

  @override
  String get routeBuilderGenerateLoop => 'Generar bucle';

  @override
  String get routeBuilderUndo => 'Deshacer';

  @override
  String get routeBuilderClear => 'Borrar';

  @override
  String get routeBuilderSaving => 'Guardando…';

  @override
  String get routeBuilderSave => 'Guardar';

  @override
  String get routeBuilderLocateMe => 'Ubicarme';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'Toca para mover el punto $number, o usa los iconos';
  }

  @override
  String routeBuilderEmptyHint(String mode) {
    return 'Toca el mapa para colocar puntos · $mode';
  }

  @override
  String routeBuilderOnePointHint(String mode) {
    return 'Coloca otro para trazar la línea · $mode';
  }

  @override
  String routeBuilderStatusGain(String distance, int gain, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puntos',
      one: '$count punto',
    );
    return '$distance · $gain m ↑ · $_temp0';
  }

  @override
  String routeBuilderStatusNoGain(String distance, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puntos',
      one: '$count punto',
    );
    return '$distance · $_temp0';
  }

  @override
  String routeBuilderDeletePoint(int number) {
    return 'Eliminar el punto $number';
  }

  @override
  String get routeBuilderCancelDrag => 'Cancelar arrastre';

  @override
  String get routeBuilderModeTrail => 'Sendero';

  @override
  String get routeBuilderModeRoad => 'Carretera';

  @override
  String get routeBuilderModeStraight => 'Recta';

  @override
  String get routeBuilderLoopDialogBody =>
      'Distancia objetivo: crearemos un bucle radial alrededor del centro actual del mapa.';

  @override
  String get routeBuilderCancel => 'Cancelar';

  @override
  String get routeBuilderGenerate => 'Generar';

  @override
  String get routeBuilderSaveDialogTitle => 'Guardar ruta';

  @override
  String get routeBuilderNameLabel => 'Nombre';

  @override
  String get routeBuilderNameHint => 'p. ej. Bucle del río';

  @override
  String get routeBuilderDescriptionLabel => 'Descripción (opcional)';

  @override
  String get routeBuilderDescriptionHint =>
      'Superficie, colinas, estacionamiento, lo que valga la pena anotar';

  @override
  String get routeBuilderSaveToLabel => 'Guardar en';

  @override
  String get routeBuilderSaveToPersonal => 'Personal';

  @override
  String get routeBuilderMakePublic => 'Hacer pública';

  @override
  String get routeBuilderMakePublicSubtitle =>
      'Otros pueden encontrarla en Explorar';

  @override
  String get routeDetailStartRun => 'Iniciar carrera';

  @override
  String get routeDetailShare => 'Compartir';

  @override
  String get routeDetailShareAsImage => 'Compartir como imagen';

  @override
  String get routeDetailShareAsGpx => 'Compartir como GPX';

  @override
  String get routeDetailShareAsKml => 'Compartir como KML';

  @override
  String get routeDetailRemoveOfflineSave => 'Quitar guardado sin conexión';

  @override
  String get routeDetailSaveForOffline => 'Guardar para uso sin conexión';

  @override
  String get routeDetailUnstarRoute => 'Quitar estrella de la ruta';

  @override
  String get routeDetailStarForWatch => 'Marcar para mostrar en el reloj';

  @override
  String get routeDetailMakePrivate => 'Hacer privada';

  @override
  String get routeDetailMakePublic => 'Hacer pública';

  @override
  String get routeDetailRemoveBookmark => 'Quitar marcador';

  @override
  String get routeDetailBookmarkRoute => 'Marcar ruta';

  @override
  String get routeDetailReportRoute => 'Denunciar ruta';

  @override
  String get routeDetailTransferToClub => 'Transferir a un club';

  @override
  String get routeDetailManageClub => 'Separar o mover a otro club';

  @override
  String get routeDetailDeleteRoute => 'Eliminar ruta';

  @override
  String get routeDetailStatDistance => 'Distancia';

  @override
  String get routeDetailStatElevation => 'Elevación';

  @override
  String routeDetailStatReviews(int count) {
    return '$count reseñas';
  }

  @override
  String get routeDetailStatWaypoints => 'Puntos';

  @override
  String get routeDetailPublicRoute => 'Ruta pública';

  @override
  String get routeDetailPrivateRoute => 'Ruta privada';

  @override
  String get routeDetailPublicSubtitle =>
      'Cualquiera con el enlace para compartir puede ver esta ruta';

  @override
  String get routeDetailPrivateSubtitle => 'Solo tú puedes ver esta ruta';

  @override
  String get routeDetailSavedForOffline => 'Guardado sin conexión';

  @override
  String get routeDetailSaveForOfflineTitle => 'Guardar sin conexión';

  @override
  String get routeDetailOfflinePinnedSubtitle =>
      'La ruta permanece en este teléfono para que puedas recorrerla sin conexión.';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'Mantén esta ruta en tu teléfono para usarla sin red.';

  @override
  String get routeDetailDescriptionHeading => 'Descripción';

  @override
  String routeDetailRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras',
      one: '$count carrera',
    );
    return '$_temp0';
  }

  @override
  String get routeDetailFeatured => 'Destacada';

  @override
  String get routeDetailSurfaceTrail => 'SENDERO';

  @override
  String get routeDetailSurfaceMixed => 'MIXTA';

  @override
  String get routeDetailSurfaceRoad => 'CARRETERA';

  @override
  String get routeDetailAddTagHint => 'añadir etiqueta';

  @override
  String get routeDetailReviewsHeading => 'Reseñas';

  @override
  String get routeDetailRate => 'Valorar';

  @override
  String get routeDetailReviewsOffline => 'Reseñas no disponibles sin conexión';

  @override
  String get routeDetailNoReviews => 'Aún no hay reseñas';

  @override
  String get routeDetailRateDialogTitle => 'Valora esta ruta';

  @override
  String get routeDetailCommentLabel => 'Comentario (opcional)';

  @override
  String get routeDetailCancel => 'Cancelar';

  @override
  String get routeDetailSubmit => 'Enviar';

  @override
  String get routeDetailSignInToReview => 'Inicia sesión para dejar una reseña';

  @override
  String routeDetailReviewFailed(String error) {
    return 'Error al enviar la reseña: $error';
  }

  @override
  String routeDetailBookmarkFailed(String error) {
    return 'Error al marcar: $error';
  }

  @override
  String get routeDetailPublicWillSync =>
      'Ruta establecida como pública. Se sincronizará la próxima vez.';

  @override
  String get routeDetailPrivateWillSync =>
      'Ruta establecida como privada. Se sincronizará la próxima vez.';

  @override
  String routeDetailVisibilityFailed(String error) {
    return 'No se pudo actualizar la visibilidad: $error';
  }

  @override
  String routeDetailStarFailed(String error) {
    return 'No se pudo actualizar la estrella: $error';
  }

  @override
  String get routeDetailOfflineSaved => 'Guardado para uso sin conexión.';

  @override
  String get routeDetailOfflineRemoved =>
      'Eliminado de los guardados sin conexión.';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'No se pudo guardar la etiqueta: $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return 'No se pudo compartir $format: $error';
  }

  @override
  String get routeDetailClubsLoadTimeout =>
      'No se pudieron cargar tus clubes — comprueba tu red.';

  @override
  String get routeDetailClubsLoadFailed => 'No se pudieron cargar tus clubes.';

  @override
  String get routeDetailDetached =>
      'Separada del club; la ruta ahora es personal.';

  @override
  String get routeDetailMovedToClub => 'Ruta movida a la biblioteca del club.';

  @override
  String routeDetailTransferFailed(String error) {
    return 'Error en la transferencia: $error';
  }

  @override
  String get routeDetailDeleteTitle => '¿Eliminar ruta?';

  @override
  String get routeDetailDeleteBody => 'Esto no se puede deshacer.';

  @override
  String get routeDetailDelete => 'Eliminar';

  @override
  String routeDetailDeleteFailed(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String get routeDetailPreview => 'Vista previa';

  @override
  String get routeDetailPreviewStart => 'Inicio';

  @override
  String get routeDetailPreviewFinish => 'Meta';

  @override
  String get routeDetailTransferDialogTitle => 'Transferir a un club';

  @override
  String get routeDetailManageClubTitle => 'Gestionar pertenencia al club';

  @override
  String get routeDetailTransferDialogBody =>
      'Los miembros del club verán esta ruta en la biblioteca del club y podrán adoptarla en sus planes.';

  @override
  String get routeDetailManageClubBody =>
      'Mueve esta ruta a otro club que administres, o sepárala para que sea personal.';

  @override
  String get routeDetailDetachToPersonal => 'Separar a personal';

  @override
  String get routeDetailDetachSubtitle =>
      'Elimina la ruta de la biblioteca del club actual.';

  @override
  String get routeDetailNoAdminClubs =>
      'Aún no eres propietario ni administrador de ningún club.';

  @override
  String get routeDetailCurrentClub => 'Club actual';

  @override
  String routeDetailClubMemberCount(String location, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros',
      one: '$count miembro',
    );
    return '$location · $_temp0';
  }

  @override
  String get exploreRoutesTitle => 'Explorar rutas';

  @override
  String get exploreRoutesModeSearch => 'Buscar';

  @override
  String get exploreRoutesModeNearMe => 'Cerca de mí';

  @override
  String get exploreRoutesSearchHint => 'Buscar rutas por nombre...';

  @override
  String get exploreRoutesFeatured => 'Destacadas';

  @override
  String get exploreRoutesSignInRequired =>
      'Inicia sesión y conéctate a Internet para explorar rutas';

  @override
  String get exploreRoutesTimeout =>
      'Se agotó el tiempo de conexión. Comprueba tu red e inténtalo de nuevo.';

  @override
  String get exploreRoutesSearchFailed =>
      'Error en la búsqueda. Toca Reintentar para volver a intentarlo.';

  @override
  String get exploreRoutesLoadMoreFailed =>
      'No se pudieron cargar más — comprueba tu conexión';

  @override
  String get exploreRoutesLocationPermissionRequired =>
      'Se requiere permiso de ubicación para encontrar rutas cercanas';

  @override
  String get exploreRoutesNearbyFailed =>
      'No se pudieron encontrar rutas cercanas. Toca Reintentar para volver a intentarlo.';

  @override
  String get exploreRoutesEmptyNoPublic => 'Aún no hay rutas públicas';

  @override
  String get exploreRoutesEmptyNoMatch =>
      'Ninguna ruta coincide con tu búsqueda';

  @override
  String get exploreRoutesEmptyBody =>
      'Las rutas compartidas desde la app web aparecen aquí';

  @override
  String get exploreRoutesDistanceAny => 'Cualquier distancia';

  @override
  String get exploreRoutesSurfaceAny => 'Cualquier superficie';

  @override
  String get exploreRoutesSurfaceRoad => 'Carretera';

  @override
  String get exploreRoutesSurfaceTrail => 'Sendero';

  @override
  String get exploreRoutesSurfaceMixed => 'Mixta';

  @override
  String get exploreRoutesSortMostRun => 'Más recorridas';

  @override
  String get exploreRoutesSortNewest => 'Más recientes';

  @override
  String get exploreRoutesSortFeatured => 'Destacadas';

  @override
  String get exploreRoutesSort => 'Ordenar';

  @override
  String exploreRoutesSaveCheckConnection(String name) {
    return 'No se pudo guardar \"$name\" — comprueba tu conexión e inténtalo de nuevo.';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return 'No se pudo guardar \"$name\".';
  }

  @override
  String exploreRoutesSaved(String name) {
    return '\"$name\" guardada en tu biblioteca';
  }

  @override
  String get exploreRoutesAlreadySaved => 'Ya guardada';

  @override
  String get exploreRoutesSaveToLibrary => 'Guardar en biblioteca';

  @override
  String get exploreRoutesSurfaceTrailShort => 'Sendero';

  @override
  String get exploreRoutesSurfaceMixedShort => 'Mixta';

  @override
  String get exploreRoutesSurfaceRoadShort => 'Carretera';

  @override
  String get exploreRoutesDistanceUnderKm => 'Menos de 5 km';

  @override
  String get exploreRoutesDistanceMidKm => '5-10 km';

  @override
  String get exploreRoutesDistanceLongKm => '10-21 km';

  @override
  String get exploreRoutesDistanceUltraKm => '21 km+';

  @override
  String get exploreRoutesDistanceUnderMi => 'Menos de 3 mi';

  @override
  String get exploreRoutesDistanceMidMi => '3-6 mi';

  @override
  String get exploreRoutesDistanceLongMi => '6-13 mi';

  @override
  String get exploreRoutesDistanceUltraMi => '13 mi+';

  @override
  String get heatmapSearchHint => 'Buscar lugares…';

  @override
  String get heatmapFilters => 'Filtros';

  @override
  String heatmapRoutesStartHere(int count) {
    return '$count rutas comienzan aquí';
  }

  @override
  String heatmapRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rutas',
      one: '$count ruta',
    );
    return '$_temp0';
  }

  @override
  String get heatmapNoRoutesHere => 'No hay rutas aquí';

  @override
  String get heatmapNoRoutesHint =>
      'No hay rutas aquí. Mueve el mapa o cambia los filtros.';

  @override
  String heatmapClearKept(int count) {
    return 'Borrar $count guardada(s)';
  }

  @override
  String get heatmapUnpinFromMap => 'Quitar del mapa';

  @override
  String get heatmapKeepOnMap => 'Mantener en el mapa';

  @override
  String get heatmapLocateMe => 'Ubicarme';

  @override
  String heatmapLocationUnavailable(String error) {
    return 'Ubicación no disponible: $error';
  }

  @override
  String get heatmapBackToList => 'Volver a la lista';

  @override
  String get heatmapViewRoute => 'Ver ruta';

  @override
  String get heatmapKept => 'Guardada';

  @override
  String get heatmapKeep => 'Guardar';

  @override
  String get heatmapLensShow => 'Mostrar';

  @override
  String get heatmapLensDistance => 'Distancia';

  @override
  String get heatmapLensMap => 'Mapa';

  @override
  String get heatmapHeatDensity => 'Densidad de calor';

  @override
  String get heatmapResetFilters => 'Restablecer filtros';

  @override
  String get heatmapLensPopular => 'Populares';

  @override
  String get heatmapLensFriends => 'Amigos';

  @override
  String get heatmapLensFeatured => 'Destacadas';

  @override
  String get heatmapLensHiddenGems => 'Joyas ocultas';

  @override
  String get publicRouteFallbackTitle => 'Ruta';

  @override
  String get publicRouteLoadError => 'No se pudo cargar esta ruta.';

  @override
  String get publicRouteUnavailable =>
      'Esta ruta es privada o ya no está disponible.';

  @override
  String get publicRouteStatDistance => 'Distancia';

  @override
  String get publicRouteStatElevation => 'Elevación';

  @override
  String get publicRouteStatWaypoints => 'Puntos';

  @override
  String get routesLoadErrorRetry =>
      'No se pudieron cargar tus rutas. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get feedTitle => 'Feed';

  @override
  String get feedFindPeople => 'Buscar personas';

  @override
  String get feedActivityAll => 'Todo';

  @override
  String get feedActivityRun => 'Carrera';

  @override
  String get feedActivityWalk => 'Caminata';

  @override
  String get feedActivityCycle => 'Ciclismo';

  @override
  String get feedActivityHike => 'Senderismo';

  @override
  String get feedLoadMore => 'Cargar más';

  @override
  String feedLoadMoreFailed(String error) {
    return 'No se pudo cargar más: $error';
  }

  @override
  String get feedLoadError => 'No se pudo cargar el feed.';

  @override
  String get feedEveryoneYouFollow => 'Todos a quienes sigues';

  @override
  String get feedRunnerFallback => 'Corredor';

  @override
  String get feedLast14Days => 'Últimos 14 días';

  @override
  String get feedEmptyTitle => 'Tu feed está vacío';

  @override
  String get feedEmptyBody =>
      'Sigue a otros corredores para ver sus carreras públicas aquí.';

  @override
  String get feedNoMatchesTitle => 'Sin coincidencias';

  @override
  String get feedNoMatchesBody =>
      'Nada coincide con los filtros actuales en los últimos 14 días.';

  @override
  String get feedNoActivityTitle => 'Sin actividad reciente';

  @override
  String get feedNoActivityBody =>
      'Nadie a quien sigues ha registrado una carrera pública en los últimos 14 días.';

  @override
  String get feedClearFilters => 'Borrar filtros';

  @override
  String feedKudosUpdateFailed(String error) {
    return 'No se pudieron actualizar los kudos: $error';
  }

  @override
  String get profileTitle => 'Perfil';

  @override
  String get profileRunnerFallback => 'Corredor';

  @override
  String get profileTabRuns => 'Carreras';

  @override
  String get profileTabFollowers => 'Seguidores';

  @override
  String get profileTabFollowing => 'Siguiendo';

  @override
  String get profileTabNotifications => 'Notificaciones';

  @override
  String get profileReportUser => 'Reportar usuario';

  @override
  String get profileUnblock => 'Desbloquear este perfil';

  @override
  String get profileBlock => 'Bloquear este perfil';

  @override
  String get profileLoadError => 'No se pudo cargar el perfil.';

  @override
  String get profileNotFound => 'Perfil no encontrado.';

  @override
  String profileFollowStats(int followers, int following) {
    String _temp0 = intl.Intl.pluralLogic(
      followers,
      locale: localeName,
      other: '$followers seguidores',
      one: '$followers seguidor',
    );
    return '$_temp0 · $following siguiendo';
  }

  @override
  String get profileFollowing => 'Siguiendo';

  @override
  String get profileFollow => 'Seguir';

  @override
  String get profileRunsEmptySelf => 'Aún no has compartido ninguna carrera.';

  @override
  String get profileRunsEmptyOther => 'Aún no hay carreras públicas.';

  @override
  String get profileFollowersEmpty => 'Aún no hay seguidores.';

  @override
  String get profileFollowingEmpty => 'Aún no sigues a nadie.';

  @override
  String profileLoadMore(int count) {
    return 'Cargar $count más';
  }

  @override
  String get profileLoadMoreFollowersFailed =>
      'No se pudieron cargar más seguidores';

  @override
  String get profileLoadMoreFollowingFailed =>
      'No se pudieron cargar más seguidos';

  @override
  String profileFollowUpdateFailed(String error) {
    return 'No se pudo actualizar el seguimiento: $error';
  }

  @override
  String profileBlockConfirmTitle(String name) {
    return '¿Bloquear a $name?';
  }

  @override
  String get profileBlockConfirmBody =>
      'No podrá seguirte, dar kudos a tus carreras ni comentarlas. Cualquier seguimiento existente entre ustedes en cualquier dirección se eliminará. Puedes desbloquear desde esta página en cualquier momento.';

  @override
  String get profileBlockConfirmAction => 'Bloquear';

  @override
  String get profileCancel => 'Cancelar';

  @override
  String get profileThisRunner => 'este corredor';

  @override
  String get profileRunnerNoun => 'corredor';

  @override
  String profileBlocked(String name) {
    return '$name bloqueado';
  }

  @override
  String profileBlockFailed(String error) {
    return 'No se pudo bloquear: $error';
  }

  @override
  String profileUnblocked(String name) {
    return '$name desbloqueado';
  }

  @override
  String profileUnblockFailed(String error) {
    return 'No se pudo desbloquear: $error';
  }

  @override
  String get profileNotifAll => 'Todas';

  @override
  String get profileNotifUnread => 'No leídas';

  @override
  String get profileMarkAllRead => 'Marcar todas como leídas';

  @override
  String profileMarkAllReadFailed(String error) {
    return 'No se pudieron marcar todas como leídas: $error';
  }

  @override
  String get profileNotifsCaughtUp => 'Estás al día.';

  @override
  String get profileNotifsEmpty => 'Aún no hay notificaciones.';

  @override
  String get profileDismiss => 'Descartar';

  @override
  String profileDismissFailed(String error) {
    return 'No se pudo descartar: $error';
  }

  @override
  String get profileNotifSomeone => 'Alguien';

  @override
  String get profileNotifYourRun => 'tu carrera';

  @override
  String profileNotifKudos(String name, String dist) {
    return '$name dio kudos a tu $dist';
  }

  @override
  String profileNotifComment(String name, String dist) {
    return '$name comentó tu $dist';
  }

  @override
  String profileNotifCommentReply(String name) {
    return '$name respondió a tu comentario';
  }

  @override
  String profileNotifFollow(String name) {
    return '$name empezó a seguirte';
  }

  @override
  String profileNotifEventRsvpTitled(String name, String title) {
    return '$name confirmó asistencia a tu evento \"$title\"';
  }

  @override
  String profileNotifEventRsvp(String name) {
    return '$name confirmó asistencia a tu evento';
  }

  @override
  String profileNotifPlanUpdate(String name) {
    return '$name actualizó tu plan de entrenamiento';
  }

  @override
  String profileNotifMessage(String name) {
    return '$name te envió un mensaje';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$name publicó en $club';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$name publicó en un club al que perteneces';
  }

  @override
  String profileNotifRunCompletedDist(String name, String dist) {
    return '$name completó una carrera de $dist';
  }

  @override
  String profileNotifRunCompleted(String name) {
    return '$name completó una carrera';
  }

  @override
  String profileNotifGeneric(String name) {
    return '$name interactuó con tu actividad';
  }

  @override
  String get socialTabFeed => 'Feed';

  @override
  String get socialTabPeople => 'Personas';

  @override
  String get socialTabClubs => 'Clubes';

  @override
  String get socialTabRoutes => 'Rutas';

  @override
  String get clubsTitle => 'Clubes';

  @override
  String get clubsFindPeople => 'Buscar personas';

  @override
  String get clubsNewClub => 'Nuevo club';

  @override
  String get clubsTabBrowse => 'Explorar';

  @override
  String get clubsTabMine => 'Mis clubes';

  @override
  String get clubsJoinWithCode => 'Unirse con código de invitación';

  @override
  String get clubsSearchHint => 'Buscar por nombre o ubicación';

  @override
  String get clubsTimeoutError =>
      'Se agotó el tiempo de conexión. Comprueba tu red e inténtalo de nuevo.';

  @override
  String get clubsLoadError =>
      'No se pudieron cargar los clubes. Toca Reintentar.';

  @override
  String get clubsBadgePrivate => 'PRIVADO';

  @override
  String clubsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros',
      one: '$count miembro',
    );
    return '$_temp0';
  }

  @override
  String get clubsEmptyBrowseTitle => 'Ningún club coincide con esa búsqueda.';

  @override
  String get clubsEmptyMineTitle => 'Aún no te has unido a ningún club.';

  @override
  String get clubsEmptyBrowseBody => 'Prueba con otro nombre o ubicación.';

  @override
  String get clubsEmptyMineBody => 'Ve a Explorar para encontrar uno.';

  @override
  String get clubDetailTabFeed => 'Feed';

  @override
  String get clubDetailTabEvents => 'Eventos';

  @override
  String get clubDetailTabMembers => 'Miembros';

  @override
  String get clubDetailTabRoutes => 'Rutas';

  @override
  String get clubDetailTabTemplates => 'Plantillas';

  @override
  String get clubDetailReportClub => 'Reportar club';

  @override
  String get clubDetailLoadFailedTitle => 'No se pudo cargar este club.';

  @override
  String get clubDetailLoadFailedBody =>
      'Puede que se haya eliminado, o que tu sesión deba actualizarse. Desliza para reintentar, o cierra sesión y vuelve a entrar desde Ajustes.';

  @override
  String get clubDetailRetry => 'Reintentar';

  @override
  String get clubDetailTimeoutError =>
      'Se agotó el tiempo de conexión. Comprueba tu red e inténtalo de nuevo.';

  @override
  String get clubDetailRequestSent =>
      'Solicitud enviada a los administradores.';

  @override
  String clubDetailLeaveTitle(String club) {
    return '¿Salir de $club?';
  }

  @override
  String get clubDetailCancel => 'Cancelar';

  @override
  String get clubDetailLeave => 'Salir';

  @override
  String clubDetailReplyFailed(String error) {
    return 'No se pudo publicar la respuesta: $error';
  }

  @override
  String get clubDetailMemberFallback => 'Miembro';

  @override
  String get clubDetailRequestPending => 'Solicitud pendiente';

  @override
  String get clubDetailInviteOnly => 'Solo con invitación';

  @override
  String get clubDetailRequest => 'Solicitar';

  @override
  String get clubDetailJoin => 'Unirse';

  @override
  String get clubDetailOwner => 'Propietario';

  @override
  String get clubDetailNextEvent => 'PRÓXIMO EVENTO';

  @override
  String clubDetailGoingCount(int count) {
    return '$count asistirán';
  }

  @override
  String get clubDetailNoPostsMember =>
      'Aún no hay publicaciones. Comparte una novedad con los miembros.';

  @override
  String get clubDetailNoPosts => 'Aún no hay novedades.';

  @override
  String get clubDetailShareUpdateHint => 'Comparte una novedad…';

  @override
  String get clubDetailPost => 'Publicar';

  @override
  String get clubDetailReply => 'Responder';

  @override
  String clubDetailHideReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ocultar $count respuestas',
      one: 'Ocultar $count respuesta',
    );
    return '$_temp0';
  }

  @override
  String clubDetailShowReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count respuestas',
      one: '$count respuesta',
    );
    return '$_temp0';
  }

  @override
  String clubDetailReplyAuthorLine(String name, String time) {
    return '$name · $time';
  }

  @override
  String get clubDetailWriteReplyHint => 'Escribe una respuesta…';

  @override
  String get clubDetailSend => 'Enviar';

  @override
  String get clubDetailNoEventsAdmin =>
      'No hay próximos eventos. Toca Crear para añadir uno.';

  @override
  String get clubDetailNoEvents => 'No hay próximos eventos.';

  @override
  String get clubDetailCreateEvent => 'Crear evento';

  @override
  String get clubDetailGoing => 'Asistiré';

  @override
  String clubDetailApproveFailed(String error) {
    return 'No se pudo aprobar: $error';
  }

  @override
  String clubDetailDenyFailed(String error) {
    return 'No se pudo rechazar: $error';
  }

  @override
  String clubDetailPendingRequests(int count) {
    return 'Solicitudes pendientes ($count)';
  }

  @override
  String clubDetailUserShort(String id) {
    return 'Usuario $id…';
  }

  @override
  String get clubDetailDeny => 'Rechazar';

  @override
  String get clubDetailApprove => 'Aprobar';

  @override
  String clubDetailMemberCountLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros.',
      one: '$count miembro.',
    );
    return '$_temp0';
  }

  @override
  String clubDetailRouteSaved(String name) {
    return '\"$name\" guardada';
  }

  @override
  String get clubDetailBuildRoute => 'Crear ruta para este club';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'Aún no hay rutas. Crea el recorrido oficial arriba, o transfiere una de tus rutas personales desde la pantalla de detalle.';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'Aún no hay rutas. Los administradores pueden transferir una de sus rutas personales desde la pantalla de detalle.';

  @override
  String get clubDetailRoutesEmpty =>
      'Aún no se han compartido rutas con este club.';

  @override
  String get clubDetailTemplateAdded => 'Plantilla añadida a tus planes.';

  @override
  String clubDetailAdoptFailed(String error) {
    return 'No se pudo adoptar: $error';
  }

  @override
  String get clubDetailNoTemplatesAdmin =>
      'Aún no hay plantillas. Publica uno de tus planes desde su página de detalle.';

  @override
  String get clubDetailNoTemplates =>
      'Aún no hay plantillas de plan para este club.';

  @override
  String get clubDetailAdopt => 'Adoptar';

  @override
  String get eventNotFound => 'Evento no encontrado.';

  @override
  String get eventLoadError =>
      'No se pudo cargar este evento. Toca Reintentar.';

  @override
  String get eventTimeoutError =>
      'Se agotó el tiempo de conexión. Comprueba tu red e inténtalo de nuevo.';

  @override
  String eventDurationMin(int minutes) {
    return '· $minutes min';
  }

  @override
  String eventGetDirectionsTo(String label) {
    return 'Cómo llegar a $label';
  }

  @override
  String get eventGetDirections => 'Cómo llegar';

  @override
  String get eventCouldNotOpenMaps => 'No se pudieron abrir los mapas.';

  @override
  String get eventPickOccurrence => 'ELIGE UNA FECHA';

  @override
  String get eventTargetPace => 'Ritmo objetivo';

  @override
  String get eventResultSubmitted => 'Resultado enviado.';

  @override
  String eventSubmitFailed(String error) {
    return 'No se pudo enviar: $error';
  }

  @override
  String eventRaceControlFailed(String error) {
    return 'Falló el control de carrera: $error';
  }

  @override
  String eventAttendees(int count) {
    return 'ASISTENTES ($count)';
  }

  @override
  String get eventNoRsvps => 'Aún no hay confirmaciones — sé el primero.';

  @override
  String get eventAttendeeMember => 'Miembro';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventRsvpGoing => 'Voy';

  @override
  String get eventRsvpMaybe => 'Quizás';

  @override
  String get eventRsvpDeclined => 'No puedo';

  @override
  String get eventRaceArmed => 'Armado — esperando el GO';

  @override
  String get eventRaceRunning => 'En curso — en vivo';

  @override
  String get eventRaceFinished => 'Finalizado';

  @override
  String get eventRaceCancelled => 'Cancelado';

  @override
  String get eventRaceNotArmed => 'No armado';

  @override
  String get eventRaceControlLabel => 'CONTROL DE CARRERA';

  @override
  String get eventRaceAutoApprove =>
      'Aprobar automáticamente los tiempos enviados';

  @override
  String get eventRaceArm => 'Armar carrera';

  @override
  String get eventRaceArmedHint =>
      'Toca Dar la salida cuando empiece la carrera. Los relojes de los participantes muestran ahora el aviso de armado.';

  @override
  String get eventRaceFireGo => 'Dar la salida';

  @override
  String get eventRaceCancel => 'Cancelar';

  @override
  String eventRaceStartedAt(String time) {
    return 'Comenzó a las $time';
  }

  @override
  String get eventRaceEnd => 'Finalizar carrera';

  @override
  String get eventRaceCancelRace => 'Cancelar carrera';

  @override
  String get eventUpdatePosted => 'Novedad publicada en el feed del club.';

  @override
  String eventPostUpdateFailed(String error) {
    return 'No se pudo publicar la novedad: $error';
  }

  @override
  String get eventPostUpdateLabel => 'PUBLICAR UNA NOVEDAD';

  @override
  String get eventUpdateHint =>
      '¿Decisión por el clima? ¿Punto de encuentro distinto?';

  @override
  String get eventPostUpdate => 'Publicar novedad';

  @override
  String get eventResultsTitle => 'Resultados';

  @override
  String get eventRemoveMine => 'Quitar el mío';

  @override
  String get eventSubmitMyTime => 'Enviar mi tiempo';

  @override
  String get eventSubmitting => 'Enviando…';

  @override
  String get eventNoResults =>
      'Aún no hay resultados. Envía tu tiempo después del evento y los demás lo verán aquí.';

  @override
  String get eventResultRunner => 'Corredor';

  @override
  String get eventResultYou => '(tú)';

  @override
  String get eventSubmitTimeTitle => 'Envía tu tiempo';

  @override
  String get eventSubmitTimeSubtitle =>
      'Elige una carrera para adjuntar, o registra un DNF / DNS.';

  @override
  String get eventNoRecentRuns =>
      'No se encontraron carreras recientes. Registra una carrera primero y vuelve.';

  @override
  String get eventRecordDnf => 'Registrar DNF';

  @override
  String get eventRecordDns => 'Registrar DNS';

  @override
  String get eventSubmitCancel => 'Cancelar';

  @override
  String get liveSpectatorTitle => 'Seguimiento en vivo';

  @override
  String get liveSpectatorConnectError => 'No se pudo conectar.';

  @override
  String get liveSpectatorWaiting =>
      'Esperando que el corredor envíe el primer ping…';

  @override
  String get liveSpectatorBadgeLive => 'En vivo';

  @override
  String get liveSpectatorBadgeIdle => 'Inactivo';

  @override
  String get liveSpectatorBadgeConnecting => 'Conectando';
}
