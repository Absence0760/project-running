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
}
