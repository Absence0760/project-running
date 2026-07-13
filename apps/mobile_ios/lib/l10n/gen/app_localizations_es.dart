// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get clubInviteEnterCodeError =>
      'Introduce el código de invitación de tu enlace.';

  @override
  String get clubInviteJoinedBanner => 'Te has unido al club.';

  @override
  String get clubInviteTitle => 'Unirse a un club';

  @override
  String get clubInviteIntro =>
      'Pega el código de invitación que te compartió el administrador del club.';

  @override
  String get clubInviteCodeLabel => 'Código de invitación';

  @override
  String get clubInviteJoinButton => 'Unirse';

  @override
  String recapShareHeadline(Object year) {
    return 'Mi $year corriendo:';
  }

  @override
  String recapShareTotals(Object total, Object count) {
    return '$total en $count carreras';
  }

  @override
  String recapShareLongestRun(Object distance) {
    return 'Carrera más larga: $distance';
  }

  @override
  String recapShareBestStreak(Object days) {
    return 'Mejor racha: $days días';
  }

  @override
  String recapShareSubject(Object year) {
    return 'Resumen de $year';
  }

  @override
  String get recapTitle => 'Resumen del año';

  @override
  String get recapShareTooltip => 'Compartir resumen';

  @override
  String get recapPublishAndShare => 'Publicar y compartir enlace';

  @override
  String get recapPublishFailed =>
      'No se pudo publicar el resumen. Inténtalo de nuevo.';

  @override
  String get recapPrevYear => 'Año anterior';

  @override
  String get recapNextYear => 'Año siguiente';

  @override
  String recapNoRunsForYear(Object year) {
    return 'No hay carreras para resumir en $year.';
  }

  @override
  String recapNoRunsYet(Object year) {
    return 'Aún no hay carreras en $year. Registra una para ver tu resumen.';
  }

  @override
  String recapAcrossRuns(Object count, Object runWord) {
    return 'en $count $runWord';
  }

  @override
  String get recapLongestRunLabel => 'Carrera más larga';

  @override
  String get recapBestStreakLabel => 'Mejor racha';

  @override
  String recapStreakDays(Object days, Object dayWord) {
    return '$days $dayWord';
  }

  @override
  String get recapTopWeekLabel => 'Mejor semana';

  @override
  String get recapUniqueRoutesLabel => 'Rutas únicas';

  @override
  String get recapEarliestStartLabel => 'Salida más temprana';

  @override
  String get recapLatestStartLabel => 'Salida más tardía';

  @override
  String get routePickerTitle => 'Elegir ruta';

  @override
  String get routePickerNoRoute => 'Sin ruta';

  @override
  String get routePickerClearSearchTooltip => 'Borrar búsqueda';

  @override
  String get routePickerSearchHint => 'Buscar rutas por nombre…';

  @override
  String get routePickerEmptyNoRoutes => 'Aún no hay rutas guardadas';

  @override
  String routePickerEmptyNoMatch(Object query) {
    return 'Ninguna ruta coincide con \"$query\"';
  }

  @override
  String get routePickerStarredHeader => 'Con estrella';

  @override
  String get routePickerAllRoutesHeader => 'Todas las rutas';

  @override
  String importStatusImported(Object count, Object label) {
    return '$count carreras importadas desde $label';
  }

  @override
  String importStatusImportedWithErrors(Object count, Object errors) {
    return '$count carreras importadas ($errors con error)';
  }

  @override
  String importStatusNoGpsNote(Object base, Object label) {
    return '$base. $label no tiene datos de ruta, así que estas carreras no tienen mapa.';
  }

  @override
  String importHealthRequestingPermission(Object label) {
    return 'Solicitando permiso de $label...';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return 'Permiso de $label denegado';
  }

  @override
  String get importHealthReadingWorkouts => 'Leyendo entrenamientos...';

  @override
  String importHealthFailed(Object label, Object error) {
    return 'Error al importar desde $label: $error';
  }

  @override
  String get importStatusSavingLocally => 'Guardando localmente...';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return 'Se omitieron $count duplicado(s) ya importados desde otra fuente';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return '$done de $total guardadas localmente';
  }

  @override
  String get importStatusSyncingToCloud => 'Sincronizando con la nube...';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return '$done de $total sincronizadas';
  }

  @override
  String get importStatusReadingCsv => 'Leyendo CSV...';

  @override
  String importCsvFailed(Object error) {
    return 'Error al importar el CSV: $error';
  }

  @override
  String get importStatusRestoringBackup => 'Restaurando copia de seguridad...';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return 'Restauradas $runs carreras · $tracks trazados · $routes rutas';
  }

  @override
  String importBackupFailed(Object error) {
    return 'Error al restaurar la copia de seguridad: $error';
  }

  @override
  String get importStatusReadingExport => 'Leyendo exportación...';

  @override
  String importStravaFailed(Object error) {
    return 'Error al importar: $error';
  }

  @override
  String get importTitle => 'Importar carreras';

  @override
  String get importStravaCardTitle => 'Strava';

  @override
  String get importStravaCardSubtitle =>
      'Importa todas las carreras desde un ZIP de exportación de datos de Strava';

  @override
  String get importStravaHowToHeader =>
      'Cómo obtener tu exportación de Strava:';

  @override
  String get importStravaHowToSteps =>
      '1. Abre Strava → Ajustes → Mi cuenta\n2. Desplázate hasta «Descargar o eliminar tu cuenta»\n3. Toca «Comenzar» → «Solicitar tu archivo»\n4. Recibirás un correo con un enlace de descarga en unas horas\n5. Descarga el .zip y toca Importar abajo';

  @override
  String get importStravaButton => 'Importar ZIP de Strava';

  @override
  String importHealthButton(Object label) {
    return 'Importar desde $label';
  }

  @override
  String get importCsvCardTitle => 'CSV';

  @override
  String get importCsvCardSubtitle =>
      'Reimporta un CSV exportado desde Ajustes — solo carreras, sin GPS';

  @override
  String get importCsvCardDescription =>
      'Cada fila del CSV se convierte en una carrera manual (fecha, distancia, duración, fuente). El trazado del mapa no está en el CSV, así que las carreras importadas no tendrán línea de ruta.';

  @override
  String get importCsvButton => 'Importar CSV';

  @override
  String get importBackupCardTitle => 'ZIP de copia de seguridad completa';

  @override
  String get importBackupCardSubtitle =>
      'Restaura carreras, rutas y trazados GPS desde un archivo de copia de seguridad';

  @override
  String get importBackupCardDescription =>
      'Ida y vuelta sin pérdidas. Funciona sin iniciar sesión — las carreras restauradas se sincronizan con tu cuenta la próxima vez que lo hagas. Crea una copia de seguridad desde Ajustes → Copia de seguridad completa.';

  @override
  String get importBackupButton => 'Restaurar ZIP de copia de seguridad';

  @override
  String get importErrorsHeader => 'Errores';

  @override
  String importErrorsMore(Object count) {
    return '... y $count más';
  }

  @override
  String get importHealthSubtitleIos =>
      'Importa los entrenamientos que has registrado en Apple Watch, Nike Run Club, Strava y otras apps que escriben en Apple Salud';

  @override
  String get importHealthSubtitleAndroid =>
      'Importa entrenamientos de Google Fit, Samsung Health, Garmin, Fitbit y cualquier otra app de Health Connect';

  @override
  String get importHealthDescriptionIos =>
      'Lee los resúmenes de entrenamiento (fecha, distancia, duración, tipo) del último año. Apple Salud no expone las rutas GPS registradas por apps de terceros — las carreras importadas así no tendrán trazado en el mapa.';

  @override
  String get importHealthDescriptionAndroid =>
      'Lee los resúmenes de entrenamiento (fecha, distancia, duración, tipo) del último año. Health Connect no expone las rutas GPS — las carreras importadas así no tendrán trazado en el mapa.';

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'No se pudo actualizar el seguimiento: $error';
  }

  @override
  String get peopleSearchHint => 'Buscar corredores por nombre';

  @override
  String get peopleClearSearchTooltip => 'Borrar búsqueda';

  @override
  String get commonClearSearch => 'Borrar búsqueda';

  @override
  String get commonDismiss => 'Descartar';

  @override
  String get settingsDevicesRemoveOverride => 'Quitar ajuste';

  @override
  String get peopleSearchResultsHeader => 'Resultados de búsqueda';

  @override
  String get peopleSuggestedHeader => 'Sugeridos para ti';

  @override
  String peopleEmptySearchTitle(Object query) {
    return 'Ningún corredor coincide con \"$query\"';
  }

  @override
  String get peopleEmptySearchBody =>
      'Prueba con un nombre más corto o distinto. Los nombres visibles son públicos; quienes aún no han elegido uno no aparecerán aquí.';

  @override
  String get peopleEmptySuggestionsTitle => 'Aún no hay sugerencias';

  @override
  String get peopleEmptySuggestionsBody =>
      'Las sugerencias provienen de personas de los clubes a los que te has unido. Únete a un club para empezar a verlas aquí.';

  @override
  String peoplePublicRunCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras públicas',
      one: '1 carrera pública',
    );
    return '$_temp0';
  }

  @override
  String peopleSharedClubsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clubes en común',
      one: '1 club en común',
    );
    return '$_temp0';
  }

  @override
  String get peopleFallbackDisplayName => 'Corredor';

  @override
  String get peopleFollowingButton => 'Siguiendo';

  @override
  String get peopleFollowButton => 'Seguir';

  @override
  String get readinessCardHeader => 'PREPARACIÓN';

  @override
  String get readinessBandHigh => 'alta';

  @override
  String get readinessBandModerate => 'moderada';

  @override
  String get readinessBandLow => 'baja';

  @override
  String get missingMapTilesTitle =>
      'Usando teselas de respaldo de OpenStreetMap';

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
  String get navLog => 'Registrar';

  @override
  String get logA11yLabel => 'Registrar una actividad';

  @override
  String get navFitness => 'Fitness';

  @override
  String get navYou => 'Tú';

  @override
  String get fitnessTabAll => 'Todo';

  @override
  String get fitnessTabRuns => 'Carreras';

  @override
  String get fitnessTabGym => 'Gimnasio';

  @override
  String get fitnessTabNutrition => 'Nutrición';

  @override
  String get fitnessRunsRoutes => 'Rutas';

  @override
  String get fitnessRunsPlans => 'Planes de entrenamiento';

  @override
  String get homeAskCoach => 'Pregunta a tu entrenador';

  @override
  String get homeAskCoachSubtitle =>
      'Consejos sobre tus carreras, gimnasio y nutrición';

  @override
  String get youProfileTitle => 'Tu perfil';

  @override
  String get logSheetTitle => 'Registrar';

  @override
  String get logRun => 'Registrar carrera';

  @override
  String get logLift => 'Registrar pesas';

  @override
  String get logFood => 'Registrar comida';

  @override
  String get prefsKeepRunPrimary => 'Correr como acción principal';

  @override
  String get prefsKeepRunPrimarySubtitle =>
      'Toca el botón central para iniciar una carrera; mantén pulsado para el menú completo';

  @override
  String get bodyMetricsTitle => 'Datos corporales';

  @override
  String get bodyMetricsTileSubtitle => 'Altura, peso y objetivos de nutrición';

  @override
  String get bodyMetricsConsentTitle => 'Almacenar datos de salud';

  @override
  String get bodyMetricsConsentSubtitle =>
      'La altura y el peso son datos de salud sensibles. Desactiva para borrarlos.';

  @override
  String get bodyMetricsHeight => 'Altura';

  @override
  String get bodyMetricsWeight => 'Peso';

  @override
  String get bodyMetricsActivityLevel => 'Nivel de actividad';

  @override
  String get bodyMetricsGoal => 'Objetivo';

  @override
  String get bodyMetricsTargetsHint =>
      'Se usa para estimar tus objetivos diarios de calorías y macros.';

  @override
  String get bodyMetricsConsentRequired =>
      'Activa el almacenamiento de datos de salud para guardar altura y peso.';

  @override
  String get bodyMetricsWithdrawTitle =>
      '¿Retirar el consentimiento de datos de salud?';

  @override
  String get bodyMetricsWithdrawBody =>
      'Esto borra permanentemente tu altura guardada y todo tu historial de peso. No se puede deshacer.';

  @override
  String get bodyMetricsWithdrawConfirm => 'Retirar y borrar';

  @override
  String get bodyMetricsSaved => 'Guardado';

  @override
  String bodyMetricsSaveFailed(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String bodyMetricsPrefSaveFailed(String error) {
    return 'No se pudo guardar: $error';
  }

  @override
  String get safetyTitle => 'Contactos de seguridad';

  @override
  String get safetyTileSubtitle =>
      'Avisa por correo a un contacto de confianza al terminar una carrera';

  @override
  String get safetyIntro =>
      'Un contacto de seguridad recibe un correo cuando terminas una carrera —incluso una privada— para que alguien de confianza sepa que volviste a salvo.';

  @override
  String get safetyAddLabel => 'Correo del contacto';

  @override
  String get safetyAddButton => 'Añadir contacto';

  @override
  String get safetyAdding => 'Añadiendo…';

  @override
  String get safetyEmpty => 'Aún no hay contactos de seguridad.';

  @override
  String get safetyStatusPending => 'Pendiente: esperando su confirmación';

  @override
  String get safetyStatusConfirmed => 'Confirmado';

  @override
  String get safetyRemove => 'Eliminar';

  @override
  String get safetyRemoveConfirm => '¿Eliminar este contacto de seguridad?';

  @override
  String safetyAddFailed(String error) {
    return 'No se pudo añadir el contacto: $error';
  }

  @override
  String get safetyInvalidEmail => 'Introduce un correo válido.';

  @override
  String get safetyAddedToast =>
      'Contacto añadido: le enviamos un correo para confirmar.';

  @override
  String get safetyRemovedToast => 'Contacto eliminado.';

  @override
  String get safetyIncomingTitle => 'Solicitudes para ti';

  @override
  String get safetyIncomingIntro =>
      'Estas personas te pidieron ser su contacto de seguridad. Confirma para recibir un correo cuando terminen una carrera.';

  @override
  String safetyIncomingFrom(String name) {
    return 'De $name';
  }

  @override
  String get safetyConfirm => 'Confirmar';

  @override
  String get safetyDecline => 'Rechazar';

  @override
  String get safetyConfirmedToast => 'Ahora eres contacto de seguridad.';

  @override
  String get safetyDeclinedToast => 'Solicitud rechazada.';

  @override
  String get safetyUnknownRunner => 'Una persona de Threkir';

  @override
  String get safetyOverdueTitle => 'Alerta de retraso';

  @override
  String get safetyOverdueIntro =>
      'Si una carrera compartida en directo queda en silencio más de este tiempo, tus contactos confirmados reciben un correo con tu enlace en directo.';

  @override
  String get safetyOverdueLabel => 'Avisar tras un silencio de';

  @override
  String get safetyOverdueOff => 'Desactivado';

  @override
  String safetyOverdueMinutesOption(int minutes) {
    return '$minutes min';
  }

  @override
  String get safetyOverdueNote =>
      'Se aplica a cualquier carrera con el directo activado. El silencio también puede ser pérdida de señal; el correo lo aclara. Los contactos reciben un solo aviso por carrera; al terminar llega la confirmación habitual.';

  @override
  String get safetyOverdueSaved => 'Alerta de retraso actualizada';

  @override
  String get safetyAutoLiveShareTitle => 'Directo automático';

  @override
  String get safetyAutoLiveShareSubtitle =>
      'Inicia automáticamente el directo cuando empieza una carrera en este teléfono. La carrera en curso es visible para cualquiera con el enlace.';

  @override
  String get runAutoLiveShareStarted =>
      'Directo activado: envía el enlace con «Compartir enlace en directo»';

  @override
  String get activitySedentary => 'Mayormente sentado (trabajo de oficina)';

  @override
  String get activityLight => 'Ligeramente activo (poco movimiento diario)';

  @override
  String get activityModerate => 'Moderadamente activo (a menudo de pie)';

  @override
  String get activityVeryActive => 'Día muy activo (trabajo físico)';

  @override
  String get activityExtraActive =>
      'Extremadamente activo (trabajo físico intenso)';

  @override
  String get goalLose => 'Perder peso';

  @override
  String get goalMaintain => 'Mantener peso';

  @override
  String get goalGain => 'Ganar peso';

  @override
  String get homeTodaysLift => 'Pesas de hoy';

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
  String get authErrorOffline =>
      'Parece que no tienes conexión. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get authErrorInvalidCredentials =>
      'Correo electrónico o contraseña incorrectos. Inténtalo de nuevo.';

  @override
  String get authErrorRateLimited =>
      'Demasiados intentos. Espera un momento e inténtalo de nuevo.';

  @override
  String get authErrorGeneric => 'Algo salió mal. Inténtalo de nuevo.';

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
  String get googleSignInSoon =>
      'El inicio de sesión con Google llegará pronto. Por ahora, usa el correo.';

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
  String get setupPageTitle => 'Configura tu cuenta';

  @override
  String get setupSkip => 'Omitir configuración';

  @override
  String get setupSkipStep => 'Omitir';

  @override
  String get setupBack => 'Atrás';

  @override
  String get setupContinue => 'Continuar';

  @override
  String get setupSaving => 'Guardando…';

  @override
  String get setupOpenDashboard => 'Abrir panel';

  @override
  String get setupWelcomeToast => '¡Bienvenido a Threkir!';

  @override
  String setupSaveError(String message) {
    return 'No se pudo guardar tu configuración: $message';
  }

  @override
  String get setupNameTitle => '¿Cómo te llamamos?';

  @override
  String get setupNameHint =>
      'Este es el nombre que otros corredores ven en tu perfil y en tus carreras compartidas.';

  @override
  String get setupNameLabel => 'Nombre visible';

  @override
  String get setupNamePlaceholder => 'p. ej. Alex Corredor';

  @override
  String get setupUnitsTitle => '¿Kilómetros o millas?';

  @override
  String get setupUnitsHint =>
      'Lo usaremos en todos los lugares donde se muestran distancias y ritmos. Puedes cambiarlo cuando quieras en Ajustes.';

  @override
  String get setupUnitKm => 'Kilómetros';

  @override
  String get setupUnitKmSample => '5,0 km · 5:00 /km';

  @override
  String get setupUnitMi => 'Millas';

  @override
  String get setupUnitMiSample => '3,1 mi · 8:03 /mi';

  @override
  String get setupGoalTitle => '¿Cuál es tu objetivo principal?';

  @override
  String get setupGoalHint =>
      'Lo usaremos para sugerirte un plan de entrenamiento adecuado. Opcional: puedes omitirlo.';

  @override
  String get setupGoalGeneralFitness => 'Mantenerme en forma + sano';

  @override
  String get setupGoalWeightLoss => 'Perder peso';

  @override
  String get setupGoal5k => 'Correr un 5K';

  @override
  String get setupGoal10k => 'Correr un 10K';

  @override
  String get setupGoalHalf => 'Correr un medio maratón';

  @override
  String get setupGoalMarathon => 'Correr un maratón';

  @override
  String get setupAboutTitle => 'Un poco sobre ti';

  @override
  String get setupAboutHint =>
      'Opcional. Ayuda a adaptar las estimaciones de ritmo y calorías. Tú decides si compartes datos de salud.';

  @override
  String get setupGenderLabel => 'Género';

  @override
  String get setupGenderPreferNot => 'Prefiero no decirlo';

  @override
  String get setupGenderFemale => 'Mujer';

  @override
  String get setupGenderMale => 'Hombre';

  @override
  String get setupGenderNonbinary => 'No binario';

  @override
  String get setupDobLabel => 'Fecha de nacimiento';

  @override
  String get setupDobNote =>
      'Se usa para mantener las cuentas de menores de 18 años fuera de la búsqueda de personas y para resultados ajustados por edad si compartes datos de salud.';

  @override
  String get setupDobPlaceholder => 'Toca para elegir';

  @override
  String get setupWeightLabel => 'Peso (kg)';

  @override
  String get setupWeightPlaceholder => 'p. ej. 70';

  @override
  String get setupHealthConsent =>
      'Doy mi consentimiento para que Threkir use mi género y fecha de nacimiento para personalizar las estimaciones de ritmo, frecuencia cardíaca y calorías (datos de salud de categoría especial, RGPD art. 9).';

  @override
  String get setupPrivacyTitle => '¿Quién ve tus carreras?';

  @override
  String get setupPrivacyHint =>
      'Elige un valor predeterminado para las nuevas carreras. Puedes cambiarlo cuando quieras y modificarlo en cada carrera.';

  @override
  String get setupNotificationsTitle => 'Mantente al día';

  @override
  String get setupNotificationsHint =>
      'Elige cuántas notificaciones push quieres. Puedes ajustarlo más tarde en Ajustes.';

  @override
  String get setupDoneTitle => 'Todo listo';

  @override
  String get setupDoneHint =>
      'Eso es todo. Toca «Abrir panel» para empezar a correr.';

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
  String get runStopA11yLabel => 'Detener y guardar la carrera';

  @override
  String get runStopA11yHint => 'Finaliza la grabación y guarda la carrera';

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
  String get runResumeDialogTitle => '¿Reanudar tu carrera?';

  @override
  String get runResumeDialogBody =>
      'Una carrera de una sesión anterior sigue en curso. Reanuda la grabación donde la dejaste, finalízala ahora o descártala.';

  @override
  String get runResumeAction => 'Reanudar';

  @override
  String get runResumeFinishAction => 'Finalizar ahora';

  @override
  String get runResumedBanner => 'Carrera reanudada.';

  @override
  String get runResumeSavedBanner => 'Carrera anterior guardada.';

  @override
  String get runResumeDiscardedBanner => 'Carrera anterior descartada.';

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
  String get runTreadmillModeLabel => 'Modo cinta de correr';

  @override
  String runTreadmillModeSpeed(String speed) {
    return 'Cinta $speed';
  }

  @override
  String get runTreadmillLostReconnecting =>
      'Cinta de correr perdida, reconectando…';

  @override
  String get runTreadmillReconnected => 'Cinta de correr reconectada';

  @override
  String get runTreadmillLostFallback =>
      'Cinta de correr perdida — la distancia vuelve al GPS';

  @override
  String get runTreadmillNotFound =>
      'No se pudo conectar con la cinta de correr';

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
  String get historyRangeToday => 'Hoy';

  @override
  String get historyRangeWeek => 'Esta semana';

  @override
  String get historyRangeMonth => 'Últimos 30 días';

  @override
  String get historyRangeYear => 'Este año';

  @override
  String get historyRangeAll => 'Todo el historial';

  @override
  String get historyRangeCustom => 'Personalizado…';

  @override
  String historyRangeFrom(String date) {
    return 'Desde $date';
  }

  @override
  String historyRangeUntil(String date) {
    return 'Hasta $date';
  }

  @override
  String historyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras',
      one: '$count carrera',
    );
    return '$_temp0';
  }

  @override
  String get historyDateRangeTooltip => 'Rango de fechas';

  @override
  String get historySortTooltip => 'Ordenar';

  @override
  String get historySortNewest => 'Más recientes primero';

  @override
  String get historySortOldest => 'Más antiguas primero';

  @override
  String get historySortLongest => 'Mayor distancia';

  @override
  String get historySortFastest => 'Mejor ritmo';

  @override
  String historySyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizar $count carreras',
      one: 'Sincronizar $count carrera',
    );
    return '$_temp0';
  }

  @override
  String get historyRefreshTooltip => 'Actualizar desde la nube';

  @override
  String get historyOfflineTooltip => 'Sin conexión';

  @override
  String historySelectionTitle(int count) {
    return '$count seleccionadas';
  }

  @override
  String get historySelectAllTooltip => 'Seleccionar todo';

  @override
  String get historyClearSelectionTooltip => 'Limpiar';

  @override
  String get historyDeleteTooltip => 'Eliminar';

  @override
  String get historyCancelTooltip => 'Cancelar';

  @override
  String get historyAddRun => 'Añadir carrera';

  @override
  String get historyAddRunTooltip => 'Añadir una carrera manualmente';

  @override
  String get historyLogTooltip => 'Registrar una carrera, entreno o comida';

  @override
  String historyLoadMore(int count) {
    return 'Cargar $count más';
  }

  @override
  String get historyNoMatch => 'Ninguna carrera coincide con estos filtros';

  @override
  String get historyKindAll => 'Todo';

  @override
  String get historyKindRuns => 'Carreras';

  @override
  String get historyKindLifts => 'Pesas';

  @override
  String get historyKindMeals => 'Comidas';

  @override
  String get historyViewAll => 'Ver todo';

  @override
  String get historyToday => 'Hoy';

  @override
  String get historyYesterday => 'Ayer';

  @override
  String historySetCount(int n) {
    return '$n series';
  }

  @override
  String historyKcal(int n) {
    return '$n kcal';
  }

  @override
  String get historyTimelineEmpty =>
      'Aún no hay nada registrado en esta vista.';

  @override
  String get historyClearFilters => 'Limpiar filtros';

  @override
  String get historyEmptyTitle => 'Aún no hay carreras';

  @override
  String get historyEmptyBody =>
      'Toca la pestaña Correr para iniciar tu primera carrera';

  @override
  String get historyFilterAll => 'Todas';

  @override
  String get historySourceAll => 'Todas las fuentes';

  @override
  String historySourceLabel(String source) {
    return 'Fuente: $source';
  }

  @override
  String get historySourceFilterTooltip => 'Filtrar por fuente';

  @override
  String get historySourceRecorded => 'Grabada';

  @override
  String get historySourceWatch => 'Reloj';

  @override
  String get historySourceStrava => 'Strava';

  @override
  String get historySourceParkrun => 'parkrun';

  @override
  String get historySourceHealthKit => 'HealthKit';

  @override
  String get historySourceHealthConnect => 'Health Connect';

  @override
  String get historyRangePickerTitle => 'Seleccionar fechas';

  @override
  String get historyRangeStart => 'Inicio';

  @override
  String get historyRangeEnd => 'Fin';

  @override
  String get historyRangeTapDate => 'Toca una fecha';

  @override
  String get historyRangeApply => 'Aplicar';

  @override
  String get historyRangeClear => 'Limpiar';

  @override
  String get historyPrevMonth => 'Mes anterior';

  @override
  String get historyNextMonth => 'Mes siguiente';

  @override
  String get historyPrevYear => 'Año anterior';

  @override
  String get historyNextYear => 'Año siguiente';

  @override
  String historyDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Eliminar $count carreras?',
      one: '¿Eliminar $count carrera?',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody => 'Esto no se puede deshacer.';

  @override
  String get historyCancel => 'Cancelar';

  @override
  String get historyDelete => 'Eliminar';

  @override
  String get historyQueuedToSync => 'En cola para sincronizar';

  @override
  String get historySignInToSync =>
      'Inicia sesión desde Ajustes para sincronizar las carreras';

  @override
  String get historyRefreshFailed =>
      'No se pudo actualizar — comprueba tu conexión';

  @override
  String get historyLoadMoreFailed => 'No se pudieron cargar más carreras';

  @override
  String historySyncPartial(int synced, int total, String error) {
    return '$synced/$total sincronizadas. Error: $error';
  }

  @override
  String historySyncTrackFailed(int count) {
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
  String historySyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Las $count carreras sincronizadas',
      one: '$count carrera sincronizada',
    );
    return '$_temp0';
  }

  @override
  String historyDeletePartial(int deleted, int queued) {
    return '$deleted eliminadas; $queued en cola — se reintentará al volver a estar en línea.';
  }

  @override
  String historyDeleteDone(int count) {
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
  String get runDetailReportRun => 'Denunciar carrera';

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
  String get runDetailStatGradeAdjPace => 'Ritmo ajustado';

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
  String runDetailRouteSaveFailed(String name) {
    return 'No se pudo guardar \"$name\" como ruta.';
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
  String get runDetailMatchOffline =>
      'Sin conexión — mostrando el trazado sin procesar, se reintentará';

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
  String get routeBuilderClearConfirmTitle => '¿Borrar esta ruta?';

  @override
  String get routeBuilderClearConfirmBody =>
      'Se eliminarán todos los puntos. Esto no se puede deshacer.';

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
  String get routeBuilderPointList => 'Puntos de la ruta';

  @override
  String routeBuilderPointMovedTo(int from, int to) {
    return 'Punto $from movido a la posición $to';
  }

  @override
  String routeBuilderPointRemoved(int number) {
    return 'Punto $number eliminado';
  }

  @override
  String routeBuilderReorderPoint(int number) {
    return 'Reordenar el punto $number';
  }

  @override
  String get routeBuilderPointStart => 'Inicio';

  @override
  String get routeBuilderPointEnd => 'Fin';

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
  String get routeDetailShareAsGpxMarkers => 'Compartir como GPX + marcadores';

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
  String get routeDetailReportReview => 'Denunciar reseña';

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
  String get routeDetailDescribe => 'Describir esta ruta';

  @override
  String get routeDetailDescribing => 'Describiendo…';

  @override
  String get routeDetailAiAttribution =>
      'Escrito por IA a partir de los datos de la ruta';

  @override
  String get routeDetailDescribeFailed =>
      'No se pudo generar una descripción. Inténtalo de nuevo.';

  @override
  String get routeDetailEnhanceUpgradeHint =>
      'Las descripciones con IA son una función Pro. Mejora tu plan para usarla.';

  @override
  String get routeDetailDescShapeLoop => 'circular';

  @override
  String get routeDetailDescShapeOutAndBack => 'ida y vuelta';

  @override
  String get routeDetailDescShapePointToPoint => 'de punto a punto';

  @override
  String get routeDetailDescSurfaceRoad => 'de asfalto';

  @override
  String get routeDetailDescSurfaceTrail => 'de sendero';

  @override
  String get routeDetailDescSurfaceMixed => 'de superficie mixta';

  @override
  String get routeDetailDescElevFlat => 'llana';

  @override
  String get routeDetailDescElevRolling => 'suavemente ondulada';

  @override
  String get routeDetailDescElevHilly => 'con cuestas';

  @override
  String get routeDetailDescElevMountainous => 'montañosa';

  @override
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  ) {
    return '$name es una ruta $shape $surface de $distance.';
  }

  @override
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  ) {
    return '$name es una ruta $shape de $distance.';
  }

  @override
  String routeDetailDescClimb(String gain, String elevation, String perKm) {
    return 'Tiene $gain de desnivel positivo — $elevation, unos $perKm por km.';
  }

  @override
  String get routeDetailDescFlat => 'Apenas tiene desnivel.';

  @override
  String routeDetailDescPerKm(int m) {
    return '$m m';
  }

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
  String routeDetailRateStars(int n) {
    return 'Establecer la valoración en $n de 5';
  }

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
  String routeDetailTagRemoveFailed(String error) {
    return 'No se pudo quitar la etiqueta: $error';
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
  String get runHeatmapTitle => 'Tu mapa de calor';

  @override
  String get runHeatmapTooltip => 'Mapa de calor de carreras';

  @override
  String get runHeatmapLoading => 'Cargando tus carreras…';

  @override
  String runHeatmapLoadingProgress(int n, int total) {
    return 'Cargando tus carreras… $n/$total';
  }

  @override
  String get runHeatmapEmptyTitle => 'Aún no hay carreras mapeadas';

  @override
  String get runHeatmapEmptyBody =>
      'Graba o importa carreras con rutas de GPS y se iluminarán aquí.';

  @override
  String get runHeatmapErrorTitle => 'No se pudo cargar tu mapa de calor';

  @override
  String get runHeatmapErrorBody =>
      'Algo salió mal al cargar tus carreras. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get runHeatmapRetry => 'Reintentar';

  @override
  String get runHeatmapLegendTitle => 'Tu mapa de calor';

  @override
  String runHeatmapLegendSummaryOne(int n) {
    return '$n carrera mapeada: más brillante donde más corres.';
  }

  @override
  String runHeatmapLegendSummaryMany(int n) {
    return '$n carreras mapeadas: más brillante donde más corres.';
  }

  @override
  String get runHeatmapScaleLess => 'menos';

  @override
  String get runHeatmapScaleMore => 'más';

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
  String get feedActivityLift => 'Fuerza';

  @override
  String get feedLiftSetsLabel => 'Series';

  @override
  String get feedLiftVolume => 'Volumen';

  @override
  String get feedLiftUntitled => 'Entrenamiento';

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
  String get relativeJustNow => 'Ahora mismo';

  @override
  String relativeMinutesAgo(int count) {
    return 'hace $count min';
  }

  @override
  String relativeHoursAgo(int count) {
    return 'hace $count h';
  }

  @override
  String get relativeYesterday => 'Ayer';

  @override
  String relativeDaysAgo(int count) {
    return 'hace $count d';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count semanas',
      one: 'hace 1 semana',
    );
    return '$_temp0';
  }

  @override
  String get coachArchiveToday => 'Hoy';

  @override
  String coachArchiveDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count días',
    );
    return '$_temp0';
  }

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
  String profileNotifNameAndOthers(String name, int count) {
    return '$name y $count más';
  }

  @override
  String profileNotifAndOthers(int count) {
    return 'y $count más';
  }

  @override
  String get profileNotifShowLess => 'Mostrar menos';

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
  String get socialTabDiscover => 'Descubrir';

  @override
  String get discoverSearchPlaceholder =>
      'Busca yoga, pilates, HIIT, clubes de running…';

  @override
  String get discoverActivityAll => 'Todas las actividades';

  @override
  String get discoverCadenceLabel => 'Frecuencia';

  @override
  String get discoverCadenceAny => 'Cualquier frecuencia';

  @override
  String get discoverOneOff => 'Puntual';

  @override
  String get discoverWeekly => 'Semanal';

  @override
  String get discoverBiweekly => 'Cada 2 semanas';

  @override
  String get discoverMonthly => 'Mensual';

  @override
  String get discoverDayLabel => 'Día';

  @override
  String get discoverDayAny => 'Cualquier día';

  @override
  String get discoverDayMon => 'Lun';

  @override
  String get discoverDayTue => 'Mar';

  @override
  String get discoverDayWed => 'Mié';

  @override
  String get discoverDayThu => 'Jue';

  @override
  String get discoverDayFri => 'Vie';

  @override
  String get discoverDaySat => 'Sáb';

  @override
  String get discoverDaySun => 'Dom';

  @override
  String get discoverTimeLabel => 'Hora del día';

  @override
  String get discoverTimeAny => 'Cualquier hora';

  @override
  String get discoverMorning => 'Mañana';

  @override
  String get discoverAfternoon => 'Tarde';

  @override
  String get discoverEvening => 'Noche';

  @override
  String get discoverPriceLabel => 'Precio';

  @override
  String get discoverPriceAny => 'Cualquier precio';

  @override
  String get discoverFree => 'Gratis';

  @override
  String get discoverPaid => 'De pago';

  @override
  String get discoverLoading => 'Buscando…';

  @override
  String get discoverEmpty =>
      'Ninguna actividad pública coincide con estos filtros todavía.';

  @override
  String get discoverSearchFailed =>
      'No se pudieron cargar las actividades. Comprueba tu conexión e inténtalo de nuevo.';

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
  String get clubDetailTabPhotos => 'Fotos';

  @override
  String get clubDetailReportClub => 'Reportar club';

  @override
  String get clubDetailReportPost => 'Denunciar esta publicación';

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
  String get clubDetailDenyTitle => 'Rechazar solicitud de ingreso';

  @override
  String get clubDetailDenyMessage =>
      '¿Rechazar esta solicitud para unirse al club? No se añadirá a la persona.';

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
  String get clubDetailSessionTemplatesTitle => 'Plantillas de sesión';

  @override
  String get clubDetailSessionAdopted => 'Sesión añadida a tus planes.';

  @override
  String get clubDetailGymRoutineTemplatesTitle =>
      'Plantillas de rutina de gimnasio';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'Los miembros pueden adoptar una rutina de gimnasio del club en sus propias rutinas. Los cambios en una copia no se propagan a la plantilla.';

  @override
  String get clubDetailGymRoutineAdopted =>
      'Rutina añadida a tus rutinas de gimnasio.';

  @override
  String clubDetailRoutineExerciseCount(int n) {
    return '$n ejercicios';
  }

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
  String get eventClassSessionEyebrow => 'CLASE';

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
  String eventPhotosTitle(int count) {
    return 'Fotos ($count)';
  }

  @override
  String get eventAddPhoto => 'Añadir foto';

  @override
  String get eventPhotoUploading => 'Subiendo…';

  @override
  String get eventNoPhotosYet => 'Aún no hay fotos.';

  @override
  String get eventNoPhotosAddHint => 'Sé el primero en añadir una.';

  @override
  String get eventWhichRunPhoto => '¿De qué carrera es esta foto?';

  @override
  String get eventNoRecentRuns =>
      'No se encontraron carreras recientes. Registra una carrera primero y vuelve.';

  @override
  String get eventPhotoRunnerFallback => 'Un corredor';

  @override
  String get eventPhotoUploadFailed => 'No se pudo subir la foto.';

  @override
  String get eventNoRsvps => 'Aún no hay confirmaciones — sé el primero.';

  @override
  String get eventAttendeeMember => 'Miembro';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventMarkAttended => 'Marcar como asistió';

  @override
  String get eventMarkNoShow => 'Marcar como ausente';

  @override
  String get eventAttendanceAttended => 'Asistió';

  @override
  String get eventAttendanceNoShow => 'Ausente';

  @override
  String get eventAttendanceFailed =>
      'No se pudo actualizar la asistencia. Inténtalo de nuevo.';

  @override
  String get eventRsvpFailed =>
      'No se pudo actualizar tu confirmación. Inténtalo de nuevo.';

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
  String get eventRaceEndConfirmBody =>
      '¿Finalizar la carrera? Esto cierra el evento para todos los corredores y no se puede deshacer.';

  @override
  String get eventRaceCancelConfirmBody =>
      '¿Cancelar la carrera? Esto cancela el evento para todos los corredores y no se puede deshacer.';

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
  String get eventRemoveResultTitle => '¿Eliminar tu resultado?';

  @override
  String get eventRemoveResultBody =>
      'Tu tiempo de meta enviado se eliminará de la clasificación de este evento. Puedes volver a enviarlo más tarde.';

  @override
  String get eventRemoveResultConfirm => 'Eliminar resultado';

  @override
  String eventRemoveResultFailed(String error) {
    return 'No se pudo eliminar tu resultado: $error';
  }

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

  @override
  String get liveSpectatorBadgeStale => 'Retrasado';

  @override
  String get liveSpectatorBadgeApproximate => 'Aproximado';

  @override
  String get liveSpectatorApproximateSub =>
      'Visto por última vez cerca de aquí — aproximado';

  @override
  String get liveSpectatorBadgeFinished => 'Finalizado';

  @override
  String get liveSpectatorBadgeDnf => 'DNF';

  @override
  String get liveUpdatedNow => 'Actualizado ahora mismo';

  @override
  String liveUpdatedSeconds(int n) {
    return 'Actualizado hace ${n}s';
  }

  @override
  String liveUpdatedMinutes(int n) {
    return 'Actualizado hace $n min';
  }

  @override
  String liveUpdatedHours(int n) {
    return 'Actualizado hace $n h';
  }

  @override
  String liveUpdatedDays(int n) {
    return 'Actualizado hace $n d';
  }

  @override
  String get liveCutoffTitle => 'Próximo corte';

  @override
  String liveCutoffToGo(String distance) {
    return 'Faltan $distance';
  }

  @override
  String liveCutoffEta(String eta) {
    return 'Llegada prevista $eta';
  }

  @override
  String liveCutoffAhead(String margin) {
    return '$margin de margen';
  }

  @override
  String liveCutoffBehind(String margin) {
    return '$margin de retraso';
  }

  @override
  String get liveCutoffWaitingSignal =>
      'Esperando una señal reciente para estimar la llegada';

  @override
  String get liveCutoffSignalLost =>
      'Señal perdida: no se puede estimar la llegada';

  @override
  String get plansTitle => 'Planes de entrenamiento';

  @override
  String get plansNewPlan => 'Plan nuevo';

  @override
  String plansDeleteTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get plansDeleteBody =>
      'Se eliminarán todas las semanas y entrenamientos.';

  @override
  String get plansCancel => 'Cancelar';

  @override
  String get plansDelete => 'Eliminar';

  @override
  String get plansAbandon => 'Abandonar';

  @override
  String plansAbandonTitle(String name) {
    return '¿Abandonar «$name»?';
  }

  @override
  String get plansAbandonBody => 'Después podrás crear un nuevo plan.';

  @override
  String plansActionFailed(String error) {
    return 'No se pudo actualizar el plan: $error';
  }

  @override
  String plansDaysPerWeek(int count) {
    return '$count días/sem.';
  }

  @override
  String get plansSignInTitle =>
      'Inicia sesión para usar los planes de entrenamiento';

  @override
  String get plansSignInBody =>
      'Los planes se sincronizan con tu cuenta para acompañarte en todos los dispositivos. Ve a Ajustes → Iniciar sesión para conectarte.';

  @override
  String get plansEmptyTitle => 'Aún no hay planes.';

  @override
  String get plansEmptyBody =>
      'Elige una carrera objetivo y planificaremos las semanas por ti.';

  @override
  String get plansTimeoutError =>
      'Se agotó el tiempo de conexión. Comprueba tu red e inténtalo de nuevo.';

  @override
  String get plansLoadError =>
      'No se pudieron cargar los planes de entrenamiento. Toca Reintentar.';

  @override
  String get planNewTitle => 'Plan nuevo';

  @override
  String get planNewNameLabel => 'Nombre del plan';

  @override
  String get planNewNameHint => 'p. ej. Media maratón de otoño';

  @override
  String get planNewGoalRace => 'Carrera objetivo';

  @override
  String get planNewStartDate => 'Fecha de inicio';

  @override
  String get planNewDaysPerWeek => 'Días por semana';

  @override
  String planNewDaysOption(int count) {
    return '$count días';
  }

  @override
  String get planNewGoalTimeSection => 'Tiempo objetivo · opcional';

  @override
  String get planNewBeginnerTitle =>
      '¿Empiezas a correr? Usa un plan de caminar-correr';

  @override
  String get planNewBeginnerSubtitle =>
      'Un programa suave estilo C25K de intervalos cronometrados de correr/caminar que avanza hacia una carrera continua. Anula el ritmo del tiempo objetivo.';

  @override
  String get planNewRecent5kSection => 'Tiempo reciente de 5K · opcional';

  @override
  String get planNewRecent5kHelp =>
      'Ancla los ritmos en un resultado real en lugar del objetivo. Usa la equivalencia de Riegel para proyectar a la distancia objetivo.';

  @override
  String get planNewRecent5kConfirm =>
      'Es un tiempo que podría correr hoy: refleja mi forma física actual.';

  @override
  String get planNewRecent5kWarning =>
      'Hasta que confirmes, los ritmos se mantienen en la estimación conservadora basada en el objetivo. Anclarse en un resultado antiguo puede fijar ritmos demasiado rápidos para quien retoma.';

  @override
  String get planNewOverrideHint => 'Anular el total de semanas';

  @override
  String planNewOverrideLabel(int count) {
    return 'Anular semanas (predet. $count)';
  }

  @override
  String get planNewCancel => 'Cancelar';

  @override
  String get planNewCreate => 'Crear plan';

  @override
  String get planNewCreating => 'Creando…';

  @override
  String get planNewPreviewTitle => 'Vista previa';

  @override
  String get planNewPaceEasy => 'Suave';

  @override
  String get planNewPaceMarathon => 'Maratón';

  @override
  String get planNewPaceTempo => 'Tempo';

  @override
  String get planNewPaceInterval => 'Intervalo';

  @override
  String get planNewPaceRep => 'Repetición';

  @override
  String get planNewPacesFallback =>
      'Ritmos estimados: añade una carrera reciente o un tiempo objetivo para metas personalizadas.';

  @override
  String planNewVdot(String value) {
    return 'VDOT de Daniels: $value';
  }

  @override
  String get planNewWeekOutline => 'Resumen de semanas';

  @override
  String planNewMoreWeeks(int count) {
    return '+ $count semanas más';
  }

  @override
  String planNewSessions(int count) {
    return '$count sesiones';
  }

  @override
  String get planNewTemplateTitle => 'Empezar desde una plantilla de club';

  @override
  String get planNewTemplateSubtitle =>
      'Adopta un plan que haya publicado un club al que perteneces. Se clona en tu cuenta con la fecha de inicio de abajo — edítalo como cualquier otro plan.';

  @override
  String get planNewTemplateButton => 'Ver plantillas';

  @override
  String get planNewTemplateCloning => 'Adoptando…';

  @override
  String planNewTemplateCloneFailed(String error) {
    return 'No se pudo adoptar esa plantilla: $error';
  }

  @override
  String get planNewTemplatePickerTitle => 'Elige una plantilla';

  @override
  String get planNewTemplatePickerCancel => 'Cancelar';

  @override
  String get planLibraryTitle => 'Biblioteca pública de planes';

  @override
  String get planLibrarySubheading =>
      'Planes publicados por otros corredores. Clona uno en tu cuenta para empezar a entrenar.';

  @override
  String get planLibrarySearchHint => 'Buscar planes por nombre';

  @override
  String get planLibraryLoadError =>
      'No se pudo cargar la biblioteca. Reintentar.';

  @override
  String get planLibraryRetry => 'Reintentar';

  @override
  String get planLibraryEmpty => 'Aún no hay planes publicados.';

  @override
  String planLibraryEmptySearch(String query) {
    return 'Ningún plan coincide con «$query».';
  }

  @override
  String planLibraryByAuthor(String author) {
    return 'de $author';
  }

  @override
  String get planLibraryAnonymous => 'un corredor';

  @override
  String planLibraryWeeks(int weeks) {
    return '$weeks semanas';
  }

  @override
  String planLibraryDaysPerWeek(int days) {
    return '$days×/semana';
  }

  @override
  String get planLibraryClone => 'Clonar en mis planes';

  @override
  String get planLibraryCloning => 'Clonando…';

  @override
  String get planLibraryCloneSuccess => 'Plan clonado.';

  @override
  String planLibraryCloneFailed(String error) {
    return 'Error al clonar: $error';
  }

  @override
  String get planLibraryStartDate => 'Fecha de inicio';

  @override
  String get planLibraryNotFound =>
      'Este plan ya no está en la biblioteca pública.';

  @override
  String get planLibraryPreviewWeeks => 'Semanas';

  @override
  String planLibraryPreviewWeek(int n) {
    return 'Semana $n';
  }

  @override
  String get planDetailPublishLibraryLabel => 'Biblioteca pública de planes';

  @override
  String get planDetailPublishLibrary => 'Publicar en la biblioteca';

  @override
  String get planDetailPublishLibraryHint =>
      'Comparte una copia de este plan para que cualquiera pueda clonarlo. Tus datos de forma física no se comparten.';

  @override
  String get planDetailPublishLibrarySuccess =>
      'Plan publicado en la biblioteca pública. Tu plan personal no cambia.';

  @override
  String planDetailPublishLibraryFailed(String error) {
    return 'Error al publicar: $error';
  }

  @override
  String get planDetailUnpublishLibrary => 'Retirar';

  @override
  String get planDetailUnpublishSuccess =>
      'Eliminado de la biblioteca pública.';

  @override
  String planDetailUnpublishFailed(String error) {
    return 'Error al retirar: $error';
  }

  @override
  String get planDetailAlreadyPublished =>
      'Este plan está en la biblioteca pública.';

  @override
  String get plansBrowseLibrary => 'Explorar biblioteca';

  @override
  String get planNewStarterTitle => 'Empezar con un plan integrado';

  @override
  String get planNewStarterSubtitle =>
      'Elige un plan de entrenamiento probado y lo programamos desde tu fecha de inicio; podrás ajustarlo después.';

  @override
  String get planNewStarterButton => 'Explorar planes iniciales';

  @override
  String get planNewStarterCreating => 'Creando…';

  @override
  String get planNewStarterPickerTitle => 'Elige un plan inicial';

  @override
  String get planNewStarterPickerCancel => 'Cancelar';

  @override
  String planNewStarterCreateFailed(String error) {
    return 'No se pudo crear ese plan: $error';
  }

  @override
  String get planNewReplaceActiveTitle => '¿Reemplazar tu plan activo?';

  @override
  String planNewReplaceActiveNamed(String name) {
    return 'Ya tienes un plan activo: \"$name\". Crear un plan nuevo marcará el actual como completado (podrás encontrarlo en Gestionar planes). ¿Continuar?';
  }

  @override
  String get planNewReplaceActiveUnnamed =>
      'Ya tienes un plan activo. Crear un plan nuevo marcará el actual como completado. ¿Continuar?';

  @override
  String get planNewReplaceActiveConfirm => 'Reemplazar plan';

  @override
  String get planNewReplaceActiveKeep => 'Mantener el actual';

  @override
  String get planNewStarterC25k => 'Couch to 5K (principiante caminar-correr)';

  @override
  String get planNewStarterHalf12 => 'Media maratón — 12 semanas';

  @override
  String get planNewStarterMarathon16 => 'Maratón — 16 semanas';

  @override
  String get planDetailTimeoutError =>
      'Se agotó el tiempo de conexión. Comprueba tu red e inténtalo de nuevo.';

  @override
  String get planDetailLoadError =>
      'No se pudo cargar este plan. Toca Reintentar.';

  @override
  String get planDetailNotFound => 'Plan no encontrado.';

  @override
  String get planDetailLongestLongRun => 'Tirada larga más larga';

  @override
  String get planDetailPublishTooltip => 'Publicar como plantilla del club';

  @override
  String planDetailDaysPerWeek(int count) {
    return '$count días/sem.';
  }

  @override
  String get planDetailCurrentWeek => 'Esta semana';

  @override
  String get planDetailToday => 'HOY';

  @override
  String get planDetailCompleted => 'Completado';

  @override
  String planDetailWeek(int number) {
    return 'Semana $number';
  }

  @override
  String planDetailDriftOverFlag(int pct) {
    return 'Esta semana $pct% por encima del plan — afloja en los días suaves para no cavar un hoyo de fatiga.';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return 'Esta semana $pct% por debajo del plan — el volumen previsto impulsa la adaptación.';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      'Te perdiste la tirada larga de esta semana — encájala si puedes. Es la sesión que más importa.';

  @override
  String get planDetailMissedLongTaper =>
      'Te perdiste una tirada larga, pero estás afinando — déjala y llega fresco al día de la carrera.';

  @override
  String get planDetailMissedLongRecovery =>
      'Te perdiste una tirada larga — no la recuperes. Viene una semana de descarga y tu cuerpo aprovechará el descanso.';

  @override
  String get planDetailReplan => 'Replanificar las semanas restantes';

  @override
  String get planDetailAdaptiveReplan => 'Replanificación adaptativa';

  @override
  String get planDetailAdaptiveOnTrack =>
      'Tus últimas semanas van según el plan: no hace falta ajustar nada.';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      'Te has desviado del plan últimamente, pero ahora mismo no hay un ajuste seguro que hacer.';

  @override
  String get planDetailAdaptiveFitnessHeld =>
      'En pausa: ahora mismo arrastras fatiga, así que no se recomienda añadir volumen.';

  @override
  String get planDetailAdaptiveReasonUnder =>
      'por debajo de tu plan durante varias semanas';

  @override
  String get planDetailAdaptiveReasonOver =>
      'por encima de tu plan durante varias semanas';

  @override
  String get planDetailAdaptiveConfidenceHigh => 'confianza alta';

  @override
  String get planDetailAdaptiveConfidenceMedium => 'confianza media';

  @override
  String planDetailAdaptiveBadge(String reason, String confidence) {
    return 'Según una tendencia: has estado $reason ($confidence)';
  }

  @override
  String get planDetailReplanOnTrack => 'Tu plan va bien — nada que ajustar.';

  @override
  String planDetailReplanApplied(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n entrenamientos ajustados',
      one: '1 entrenamiento ajustado',
    );
    return '$_temp0';
  }

  @override
  String get planDetailReplanPreviewTitle => 'Cambios propuestos';

  @override
  String planDetailReplanMakeUp(String from, String to) {
    return 'Tirada larga $from → $to — recuperar una tirada larga perdida';
  }

  @override
  String planDetailReplanEase(String from, String to) {
    return '$from → $to — aligerar tras pasarte de volumen';
  }

  @override
  String get planDetailReplanCancel => 'Cancelar';

  @override
  String get planDetailReplanApply => 'Aplicar cambios';

  @override
  String get planDetailDuplicateWeek => 'Duplicar semana';

  @override
  String planDetailDuplicateWeekDone(int n) {
    return 'Semana $n duplicada';
  }

  @override
  String get planDetailDuplicateConfirmTitle => '¿Duplicar esta semana?';

  @override
  String planDetailDuplicateConfirmMessage(int n) {
    return 'Esto inserta una copia de la semana $n y desplaza cada semana posterior y la fecha de tu carrera 7 días.';
  }

  @override
  String get planDetailDuplicateConfirm => 'Duplicar';

  @override
  String planDetailBulkFailed(String error) {
    return 'No se pudo actualizar el plan: $error';
  }

  @override
  String get planDetailEditTooltip => 'Editar entrenamiento';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'No se pudieron cargar tus clubes: comprueba tu red.';

  @override
  String get planDetailPublishLoadClubsFailed =>
      'No se pudieron cargar tus clubes.';

  @override
  String get planDetailPublishNoClubs =>
      'Debes ser propietario o administrador de un club para publicar una plantilla.';

  @override
  String planDetailPublishSuccess(String name) {
    return 'Se publicó «$name» como plantilla del club.';
  }

  @override
  String planDetailPublishFailed(String error) {
    return 'Error al publicar: $error';
  }

  @override
  String get planDetailPublishPickerTitle => 'Publicar en un club';

  @override
  String get planDetailPublishPickerBody =>
      'Los miembros del club podrán adoptar este plan como propio.';

  @override
  String planDetailPublishPickerMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros',
      one: '$count miembro',
    );
    return '$_temp0';
  }

  @override
  String get planDetailPublishCancel => 'Cancelar';

  @override
  String get workoutTimeoutError =>
      'Se agotó el tiempo de conexión. Comprueba tu red e inténtalo de nuevo.';

  @override
  String get workoutLoadError =>
      'No se pudo cargar este entrenamiento. Toca Reintentar.';

  @override
  String get workoutNotFound => 'Entrenamiento no encontrado.';

  @override
  String get workoutMetricDistance => 'Distancia';

  @override
  String get workoutMetricDuration => 'Duración';

  @override
  String get workoutMetricTargetPace => 'Ritmo objetivo';

  @override
  String get workoutCompleted => 'Completado';

  @override
  String get workoutUnlink => 'Desvincular';

  @override
  String get workoutUnlinkTitle => 'Desvincular carrera';

  @override
  String get workoutUnlinkBody =>
      '¿Desvincular la carrera asociada? La sesión volverá a aparecer como no realizada.';

  @override
  String get workoutUnlinkError =>
      'No se pudo desvincular la carrera. Inténtalo de nuevo.';

  @override
  String get workoutSkipped => 'Omitido';

  @override
  String get workoutSkip => 'Omitir este entrenamiento';

  @override
  String get workoutUnskip => 'Deshacer omisión';

  @override
  String get workoutSkipError =>
      'No se pudo actualizar la omisión. Inténtalo de nuevo.';

  @override
  String get workoutRelink => 'Revincular';

  @override
  String get workoutRelinkTitle => 'Vincular otra carrera';

  @override
  String get workoutRelinkHint =>
      'Elige una carrera cercana a la fecha de este entrenamiento para contarla como esta sesión. No se muestran las carreras ya vinculadas a otro entrenamiento.';

  @override
  String get workoutRelinkLoading => 'Buscando tus carreras…';

  @override
  String get workoutRelinkError =>
      'No se pudieron cargar tus carreras. Inténtalo de nuevo.';

  @override
  String get workoutRelinkEmpty =>
      'No hay carreras válidas cerca de esta fecha.';

  @override
  String get workoutRelinkCurrent => 'Actual';

  @override
  String get workoutStart => 'Iniciar entrenamiento';

  @override
  String get workoutSectionNotes => 'Notas';

  @override
  String get workoutSectionStructure => 'Estructura';

  @override
  String get workoutSectionHowTo => 'Cómo correrlo';

  @override
  String get workoutStructWarmup => 'Calentamiento';

  @override
  String get workoutStructRepeats => 'Repeticiones';

  @override
  String get workoutStructSteady => 'Constante';

  @override
  String get workoutStructCooldown => 'Enfriamiento';

  @override
  String workoutStructWarmupValue(String distance) {
    return '$distance @ suave';
  }

  @override
  String workoutStructCooldownValue(String distance) {
    return '$distance @ suave';
  }

  @override
  String get workoutAdviceEasy =>
      'Ritmo de conversación. Si no puedes mantener una conversación, vas demasiado rápido.';

  @override
  String get workoutAdviceLong =>
      'Mantente relajado. Busca una respiración constante. Reduce un 10 % la distancia si el clima es malo o estás dolorido, pero no la omitas.';

  @override
  String get workoutAdviceTempo =>
      '«Cómodamente difícil». Debes sentir que podrías mantener el ritmo cerca de una hora al máximo esfuerzo, pero no más.';

  @override
  String get workoutAdviceInterval =>
      'Corre las repeticiones con la fuerza suficiente para que la última se sienta como la primera. No elijas un ritmo que solo puedas mantener dos o tres repeticiones.';

  @override
  String get workoutAdviceMarathonPace =>
      'Ajústate exactamente al ritmo objetivo de maratón. Es una sesión de ensayo: ni más rápido ni más lento.';

  @override
  String get workoutAdviceWalkRun =>
      'Alterna carrera suave y caminata en los intervalos cronometrados. Las pausas de caminar son parte del entrenamiento: tómalas aunque te sientas fresco.';

  @override
  String get workoutAdviceRace =>
      'Confía en el plan. No persigas un récord en el primer kilómetro.';

  @override
  String get workoutAdviceRest =>
      'Día de descanso: si necesitas moverte, camina o estírate.';

  @override
  String get coachTitle => 'Coach';

  @override
  String get coachNewConversation => 'Nueva conversación';

  @override
  String get coachConsentHeadline => 'Antes de chatear con Coach';

  @override
  String get coachConsentIntro =>
      'Para darte consejos fundamentados, Coach envía una parte de tus datos de entrenamiento a Anthropic, nuestro proveedor de modelos de IA en EE. UU. Esa parte incluye:';

  @override
  String get coachConsentBulletProfile =>
      'Tu fecha de nacimiento, sexo y zonas de FC si están configuradas.';

  @override
  String get coachConsentBulletRuns =>
      'Una muestra de tus carreras más recientes.';

  @override
  String get coachConsentBulletPlan =>
      'El plan de entrenamiento activo que has seleccionado.';

  @override
  String get coachConsentBulletMessages =>
      'Los mensajes de chat que escribes en la pantalla de abajo.';

  @override
  String get coachConsentProcessing =>
      'Anthropic procesa los datos en nombre de Threkir según sus términos de tratamiento de datos; por defecto, no entrenan sus modelos con los datos de clientes de Threkir. Todos los detalles —incluido el mecanismo de transferencia, la retención y tus derechos de retirada— están en nuestra política de privacidad.';

  @override
  String get coachConsentAction =>
      'Toca «Doy mi consentimiento» para continuar. Toca cancelar para salir de la página sin enviar datos.';

  @override
  String get coachConsentCancel => 'Cancelar';

  @override
  String get coachConsentAccept => 'Doy mi consentimiento — iniciar Coach';

  @override
  String get coachConsentSaving => 'Registrando consentimiento…';

  @override
  String get coachNoPlanOption => 'Sin plan (solo carreras recientes)';

  @override
  String coachPlanActive(String name) {
    return '$name · activo';
  }

  @override
  String coachPlanDone(String name) {
    return '$name · hecho';
  }

  @override
  String get coachNewChatTooltip => 'Chat nuevo';

  @override
  String get coachHistoryTooltip => 'Historial de chat';

  @override
  String get coachNewChat => 'Chat nuevo';

  @override
  String coachActiveThread(String suffix) {
    return 'Activo$suffix';
  }

  @override
  String get coachArchiveTapToView => 'Toca para ver · desliza para eliminar';

  @override
  String get coachContextNoPlan => 'Sin plan';

  @override
  String coachContextPlanWeeks(String name, int weeks) {
    return '$name · $weeks sem.';
  }

  @override
  String get coachContextNoRuns => 'Sin carreras';

  @override
  String get coachContextLast => 'Últimas';

  @override
  String get coachContextHr => 'FC';

  @override
  String coachContextWeeklyGoal(String km) {
    return '$km km/sem.';
  }

  @override
  String coachArchiveBanner(String label) {
    return 'Viendo archivo · $label · solo lectura';
  }

  @override
  String get coachBackToActive => 'Volver al activo';

  @override
  String get coachLimitReachedPro => 'Límite diario alcanzado. Vuelve mañana.';

  @override
  String get coachLimitReachedFree =>
      'Límite diario alcanzado. Pro ofrece un tope mayor: mejora en Ajustes.';

  @override
  String coachMessagesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'quedan $count mensajes hoy',
      one: 'queda $count mensaje hoy',
    );
    return '$_temp0';
  }

  @override
  String get coachEmptyPromptPlan =>
      'Pregunta sobre el entrenamiento de hoy, tu ritmo o cómo se comparan tus carreras recientes con el plan.';

  @override
  String get coachEmptyPromptNoPlan =>
      'Pregunta sobre tus carreras recientes, el ritmo de carreras suaves o lo básico del entrenamiento.';

  @override
  String get coachSuggestPlanRest =>
      '¿Debería correr mañana o tomar un día de descanso?';

  @override
  String get coachSuggestPlanOnTrack => '¿Voy bien para mi tiempo objetivo?';

  @override
  String get coachSuggestPlanLongRun =>
      '¿Por qué importa la tirada larga de esta semana?';

  @override
  String get coachSuggestPlanToday =>
      '¿En qué debería centrarme en el entrenamiento de hoy?';

  @override
  String get coachSuggestNoPlanLastRun => '¿Cómo fue mi última carrera?';

  @override
  String get coachSuggestNoPlanEasyPace =>
      '¿A qué ritmo deberían ser mis carreras suaves?';

  @override
  String get coachSuggestNoPlanWeekOff =>
      'Llevo una semana sin correr, ¿qué hago?';

  @override
  String get coachSuggestNoPlanTempo => '¿Qué es una carrera de tempo?';

  @override
  String get coachEditCancel => 'Cancelar';

  @override
  String get coachEditSaveResend => 'Guardar y reenviar';

  @override
  String get coachActionCopy => 'Copiar';

  @override
  String get coachActionEdit => 'Editar';

  @override
  String get coachActionRegenerate => 'Regenerar';

  @override
  String get coachActionHelpful => 'Útil';

  @override
  String get coachActionNotHelpful => 'No útil';

  @override
  String get coachComposerHintLimit => 'Límite diario alcanzado';

  @override
  String get coachComposerHint => 'Pregunta a Coach…';

  @override
  String get coachArchiveTitle => '¿Iniciar una nueva conversación?';

  @override
  String get coachArchiveBody =>
      'El chat actual pasa al historial. Puedes volver a verlo desde la barra lateral.';

  @override
  String get coachArchiveCancel => 'Cancelar';

  @override
  String get coachArchiveConfirm => 'Chat nuevo';

  @override
  String get coachSignInFirst => 'Por favor, inicia sesión primero.';

  @override
  String get coachSessionExpired =>
      'Tu sesión ha expirado. Por favor, inicia sesión de nuevo.';

  @override
  String coachDailyLimitError(int limit) {
    return 'Límite diario alcanzado ($limit mensajes). ¡Vuelve mañana!';
  }

  @override
  String coachGenericError(int code) {
    return 'Error de Coach ($code)';
  }

  @override
  String get coachTransportError =>
      'No se pudo contactar con Coach. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get coachStreamFailed => 'error de transmisión';

  @override
  String coachNewConversationFailed(String error) {
    return 'No se pudo iniciar una nueva conversación: $error';
  }

  @override
  String coachOpenArchiveFailed(String error) {
    return 'No se pudo abrir el archivo: $error';
  }

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'No se pudo eliminar el archivo: $error';
  }

  @override
  String get coachCopied => 'Copiado al portapapeles';

  @override
  String get settingsAccountTitle => 'Cuenta';

  @override
  String get settingsAccountBackendNotConfigured => 'Backend no configurado';

  @override
  String get settingsAccountSignOutFailed =>
      'Error al cerrar sesión: comprueba tu conexión';

  @override
  String get settingsAccountChangePassword => 'Cambiar contraseña';

  @override
  String get settingsAccountNewPassword => 'Nueva contraseña';

  @override
  String get settingsAccountConfirm => 'Confirmar';

  @override
  String get settingsAccountCancel => 'Cancelar';

  @override
  String get settingsAccountSave => 'Guardar';

  @override
  String get settingsAccountPasswordTooShort =>
      'La contraseña debe tener al menos 8 caracteres';

  @override
  String get settingsAccountPasswordsMismatch => 'Las contraseñas no coinciden';

  @override
  String get settingsAccountPasswordUpdated => 'Contraseña actualizada';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'No se pudo actualizar la contraseña: $error';
  }

  @override
  String get settingsAccountDeleteTitle => '¿Eliminar la cuenta?';

  @override
  String get settingsAccountDeleteBody =>
      'Esto elimina permanentemente tus carreras, rutas y perfil del servidor. Los datos locales del dispositivo se conservan a menos que inicies sesión como un usuario nuevo. Esto no se puede deshacer.';

  @override
  String get settingsAccountDeleteChallengeText =>
      'Escribe «DELETE» para confirmar';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return 'Escribe tu correo ($email) para confirmar';
  }

  @override
  String get settingsAccountDelete => 'Eliminar';

  @override
  String get settingsAccountDeleteSignInFirst =>
      'Inicia sesión primero para eliminar tu cuenta.';

  @override
  String get settingsAccountDeleted => 'Cuenta eliminada';

  @override
  String get settingsAccountCoachConsentWithdraw =>
      'Retirar consentimiento del Coach';

  @override
  String get settingsAccountCoachConsentActive =>
      'Impide que el Coach use tus datos de entrenamiento. Puedes volver a dar tu consentimiento cuando quieras.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Consentimiento del Coach retirado.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Error al retirar el consentimiento: $error';
  }

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'Error al eliminar la cuenta: $error';
  }

  @override
  String get settingsAccountNoRunsToExport => 'No hay carreras para exportar.';

  @override
  String get settingsAccountCsvShareText => 'Run app — exportación de carreras';

  @override
  String settingsAccountCsvExportFailed(Object error) {
    return 'Error en la exportación CSV: $error';
  }

  @override
  String get settingsAccountBackupSignInFirst =>
      'Inicia sesión primero para hacer una copia de tus carreras.';

  @override
  String get settingsAccountBackupPreparing =>
      'Preparando la copia de seguridad…';

  @override
  String get settingsAccountBackupShareText => 'Copia de seguridad de Run app';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'Error en la copia de seguridad: $error';
  }

  @override
  String get settingsAccountRestoreUnavailable =>
      'Servicio de copia de seguridad no disponible.';

  @override
  String get settingsAccountRestoreTitle =>
      '¿Restaurar desde la copia de seguridad?';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'No has iniciado sesión. Las carreras se restaurarán en este dispositivo y se sincronizarán con tu cuenta la próxima vez que inicies sesión.';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'Esto añade o sobrescribe las carreras y rutas con los ID que coincidan en la copia. No eliminará carreras ni rutas que no estén en la copia.';

  @override
  String get settingsAccountRestore => 'Restaurar';

  @override
  String get settingsAccountRestoring => 'Restaurando…';

  @override
  String settingsAccountRestoreDone(
    int runs,
    int tracks,
    int routes,
    String warnings,
  ) {
    return 'Restaurados $runs carreras · $tracks trazados · $routes rutas$warnings';
  }

  @override
  String settingsAccountRestoreWarningsSuffix(int count) {
    return ' · $count advertencias';
  }

  @override
  String settingsAccountRestoreFailed(Object error) {
    return 'Error en la restauración: $error';
  }

  @override
  String get settingsAccountOfflineMode => 'Modo sin conexión';

  @override
  String get settingsAccountSignedInSync =>
      'Sesión iniciada: las carreras se sincronizarán';

  @override
  String get settingsAccountSignInToSync =>
      'Inicia sesión para sincronizar carreras entre dispositivos';

  @override
  String get settingsAccountSignOut => 'Cerrar sesión';

  @override
  String get settingsAccountSignIn => 'Iniciar sesión';

  @override
  String get settingsAccountAvatar => 'Foto de perfil';

  @override
  String get settingsAccountAvatarHint => 'JPEG, PNG o WebP, hasta 2 MB.';

  @override
  String get settingsAccountAvatarRemove => 'Quitar foto';

  @override
  String get settingsAccountAvatarRemoveTitle => '¿Quitar foto de perfil?';

  @override
  String get settingsAccountAvatarRemoveConfirm =>
      'Se quitará tu foto de perfil actual. Puedes subir una nueva cuando quieras.';

  @override
  String get settingsAccountAvatarSaved => 'Foto de perfil actualizada.';

  @override
  String get settingsAccountAvatarRemoved => 'Foto de perfil eliminada.';

  @override
  String get settingsAccountAvatarUnsupported =>
      'Imagen no compatible — elige JPEG, PNG o WebP.';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return 'No se pudo actualizar la foto: $error';
  }

  @override
  String get settingsAccountViewProfile => 'Ver perfil';

  @override
  String get settingsAccountViewProfileSubtitle =>
      'Tus carreras, seguidores, seguidos, notificaciones';

  @override
  String get settingsAccountGuidedRuns => 'Carreras guiadas';

  @override
  String get settingsAccountGuidedRunsSubtitle =>
      'Entrenamientos guionizados con voz de entrenador y avisos TTS';

  @override
  String get settingsAccountPrivacyZones => 'Zonas de privacidad';

  @override
  String get settingsAccountPrivacyZonesSubtitle =>
      'Recorta el inicio/fin de los trazados públicos cerca de casa';

  @override
  String get settingsAccountSendErrorReports => 'Enviar informes de errores';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Datos anónimos de fallos y errores a Sentry (EE. UU.). Desactiva para retirar el consentimiento. Se aplica en el próximo inicio.';

  @override
  String get settingsAccountErrorReportingEnabled =>
      'Informes de errores activados: reinicia la app para aplicar.';

  @override
  String get settingsAccountErrorReportingDisabled =>
      'Informes de errores desactivados: reinicia la app para aplicar.';

  @override
  String get settingsAccountImport => 'Importar desde otra app';

  @override
  String get settingsAccountImportSubtitle => 'Strava, GPX, TCX';

  @override
  String get settingsAccountFullBackup => 'Copia de seguridad completa';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'Cada carrera con su trazado GPS, además de rutas, perfil y preferencias. Se restaura en web o Android.';

  @override
  String get settingsAccountExportCsv => 'Exportar carreras como CSV';

  @override
  String get settingsAccountExportCsvSubtitle =>
      'Fecha, distancia, duración, ritmo, fuente: una fila por carrera. Mismo formato que la exportación RGPD de la web.';

  @override
  String get settingsAccountRestoreTile => 'Restaurar desde copia de seguridad';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      'Elige una copia .zip guardada previamente.';

  @override
  String get settingsAccountDeleteAccount => 'Eliminar cuenta';

  @override
  String get settingsAccountDeleteAccountSubtitle =>
      'Elimina permanentemente los datos del servidor';

  @override
  String get integrationsTitle => 'Integraciones';

  @override
  String get integrationsJustNow => 'ahora mismo';

  @override
  String integrationsMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String integrationsHoursAgo(int hours) {
    return 'hace $hours h';
  }

  @override
  String integrationsDaysAgo(int days) {
    return 'hace $days d';
  }

  @override
  String integrationsWeeksAgo(int weeks) {
    return 'hace $weeks sem';
  }

  @override
  String integrationsCouldNotOpen(Object error) {
    return 'No se pudo abrir: $error';
  }

  @override
  String get integrationsStravaBrowserHint =>
      'Completa el inicio de sesión de Strava en tu navegador, luego vuelve aquí y desliza para actualizar.';

  @override
  String get integrationsStravaCancelled =>
      'Inicio de sesión de Strava cancelado.';

  @override
  String integrationsStravaSignInFailed(Object error) {
    return 'Error al iniciar sesión en Strava: $error';
  }

  @override
  String get integrationsStravaCsrfMismatch =>
      'Inicio de sesión de Strava rechazado: el estado CSRF no coincide. Inténtalo de nuevo.';

  @override
  String integrationsStravaConnectFailed(String error) {
    return 'Error al conectar con Strava: $error';
  }

  @override
  String get integrationsStravaConnected => 'Strava conectado.';

  @override
  String integrationsSyncResult(int imported, int skipped) {
    return 'Sincronizado. $imported nuevas, $skipped ya presentes.';
  }

  @override
  String integrationsSyncFailed(Object error) {
    return 'Error de sincronización: $error';
  }

  @override
  String get integrationsStravaDisconnectTitle => '¿Desconectar Strava?';

  @override
  String get integrationsStravaDisconnectBody =>
      'Las actividades futuras dejarán de sincronizarse automáticamente. Las carreras ya importadas permanecen en tu historial.';

  @override
  String get integrationsCancel => 'Cancelar';

  @override
  String get integrationsDisconnect => 'Desconectar';

  @override
  String get integrationsStravaDisconnected => 'Strava desconectado.';

  @override
  String integrationsDisconnectFailed(Object error) {
    return 'Error al desconectar: $error';
  }

  @override
  String get integrationsParkrunTitle => 'Importar resultados de parkrun';

  @override
  String get integrationsParkrunBody =>
      'Introduce tu número de atleta de parkrun (p. ej. A123456). Recuperaremos tu historial de llegadas y añadiremos los nuevos resultados a tu lista de carreras.';

  @override
  String get integrationsParkrunFieldLabel => 'Número de atleta';

  @override
  String get integrationsImport => 'Importar';

  @override
  String get integrationsParkrunImporting =>
      'Importando resultados de parkrun…';

  @override
  String integrationsParkrunImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados de parkrun importados.',
      one: '$count resultado de parkrun importado.',
    );
    return '$_temp0';
  }

  @override
  String get integrationsParkrunNoneNew =>
      'No hay nuevos resultados de parkrun desde la última importación.';

  @override
  String integrationsImportFailed(Object error) {
    return 'Error en la importación: $error';
  }

  @override
  String get integrationsStravaName => 'Strava';

  @override
  String get integrationsStravaConnectSubtitle =>
      'Conecta para sincronizar actividades automáticamente';

  @override
  String get integrationsStravaWaitingFirstSync =>
      'Conectado · esperando la primera sincronización';

  @override
  String integrationsStravaLastSync(String time) {
    return 'Conectado · última sincronización $time';
  }

  @override
  String get integrationsSyncNow => 'Sincronizar ahora';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Importar resultados por número de atleta';

  @override
  String get integrationsParkrunRegionNote =>
      'parkrun solo está presente en algunos países y puede que no haya eventos cerca de ti — aun así puedes importar resultados con un ID de atleta de parkrun.';

  @override
  String get integrationsSignInTitle => 'Inicia sesión para conectar servicios';

  @override
  String get integrationsSignInSubtitle =>
      'Strava + parkrun requieren una cuenta para que las actividades sincronizadas lleguen a tu historial.';

  @override
  String get integrationsHealthConnectTitle =>
      'Escribir carreras en Health Connect';

  @override
  String get integrationsHealthConnectSubtitle =>
      'Envía cada carrera terminada a Health Connect para que aparezca en Google Fit, Samsung Health, Fitbit y otros.';

  @override
  String get integrationsHealthConnectDenied =>
      'Permiso de Health Connect no concedido: las carreras no se escribirán.';

  @override
  String integrationsHrPairFailed(Object error) {
    return 'Error al emparejar: $error';
  }

  @override
  String get integrationsHrTitle => 'Monitor de frecuencia cardíaca';

  @override
  String get integrationsHrChecking => 'Comprobando…';

  @override
  String integrationsHrPaired(String name) {
    return 'Emparejado: $name';
  }

  @override
  String get integrationsHrNotPaired =>
      'Ninguna banda emparejada: toca para buscar';

  @override
  String get integrationsHrForget => 'Olvidar';

  @override
  String get integrationsHrForgetConfirm =>
      '¿Olvidar este monitor de frecuencia cardíaca? Tendrás que volver a emparejarlo para usarlo durante una carrera.';

  @override
  String get integrationsHrScanTitle => 'Buscar monitor de frecuencia cardíaca';

  @override
  String get integrationsHrScanHint =>
      'Activa tu banda / cinta pectoral. Suele tardar de 3 a 8 segundos.';

  @override
  String get integrationsHrScanEmpty =>
      'No se encontraron bandas. Asegúrate de que esté cerca y activa.';

  @override
  String integrationsHrRssi(int rssi) {
    return 'RSSI $rssi dBm';
  }

  @override
  String get integrationsTreadmillTitle => 'Cinta de correr';

  @override
  String get integrationsTreadmillChecking => 'Comprobando…';

  @override
  String integrationsTreadmillPaired(String name) {
    return 'Emparejada: $name';
  }

  @override
  String get integrationsTreadmillNotPaired =>
      'Ninguna cinta emparejada: toca para buscar';

  @override
  String get integrationsTreadmillForget => 'Olvidar';

  @override
  String get integrationsTreadmillForgetConfirm =>
      '¿Olvidar esta cinta de correr? Tendrás que volver a emparejarla para usarla durante una carrera.';

  @override
  String get integrationsTreadmillScanTitle => 'Buscar cinta de correr';

  @override
  String get integrationsTreadmillScanHint =>
      'Asegúrate de que el Bluetooth de la cinta esté activado y la banda despierta. La búsqueda tarda de 3 a 8 segundos.';

  @override
  String get integrationsTreadmillScanEmpty =>
      'No se encontraron cintas. Asegúrate de que sea compatible con Bluetooth (FTMS) y esté cerca.';

  @override
  String integrationsTreadmillPairFailed(Object error) {
    return 'Error al emparejar: $error';
  }

  @override
  String integrationsTreadmillLiveSpeed(String speed) {
    return '$speed km/h';
  }

  @override
  String get proTitle => 'Pro y apoyo';

  @override
  String proCouldNotOpen(Object error) {
    return 'No se pudo abrir: $error';
  }

  @override
  String get proWelcome => '¡Bienvenido a Pro! Cargando tus ventajas…';

  @override
  String get proPurchaseFailed => 'La compra falló. Inténtalo más tarde.';

  @override
  String get proRestoreNeedsSignIn =>
      'Para restaurar debes haber iniciado sesión con RevenueCat configurado. Gestiona tu suscripción en la página de mejora web.';

  @override
  String get proRestored => 'Se restauró tu suscripción Pro.';

  @override
  String get proRestoreNone =>
      'No se encontraron compras activas en esta cuenta de la tienda.';

  @override
  String get proRestoreFailed => 'La restauración falló. Inténtalo más tarde.';

  @override
  String get proRestoreUnavailable =>
      'Restauración no disponible en esta versión.';

  @override
  String proSubscribeTitle(String price) {
    return 'Suscribirse a Pro — $price/mes';
  }

  @override
  String get proSubscribeSubtitleConfigured =>
      'Entrenador de IA ilimitado + procesamiento prioritario. Se renueva automáticamente cada mes hasta que se cancele en Ajustes → Suscripciones.';

  @override
  String get proSubscribeSubtitleWeb =>
      'Abre el portal de suscripción en tu navegador. Se renueva automáticamente cada mes hasta su cancelación.';

  @override
  String get proRegionalNote =>
      'Se factura en dólares estadounidenses. La disponibilidad depende de tu país y método de pago: algunas regiones no pueden ser atendidas por nuestro procesador de pagos.';

  @override
  String get proRestorePurchases => 'Restaurar compras';

  @override
  String get proRestorePurchasesSubtitle =>
      'Vuelve a vincular compras de una instalación anterior u otro dispositivo';

  @override
  String get proManageSubscription => 'Gestionar suscripción';

  @override
  String get proManageSubscriptionSubtitle =>
      'Cancelar, cambiar de plan o actualizar el método de pago';

  @override
  String get proSupport => 'Apoyar la app';

  @override
  String get proSupportSubtitle => 'Donación única en tu navegador';

  @override
  String get licensesTitle => 'Licencias';

  @override
  String get licensesVersion => 'Versión';

  @override
  String get licensesOpenSource => 'Licencias de código abierto';

  @override
  String get licensesOpenSourceSubtitle =>
      'Paquetes de terceros incluidos con esta app';

  @override
  String get devicesTitle => 'Dispositivos';

  @override
  String get devicesRenameTitle => 'Renombrar dispositivo';

  @override
  String get devicesCancel => 'Cancelar';

  @override
  String get devicesSave => 'Guardar';

  @override
  String devicesRenameFailed(Object error) {
    return 'Error al renombrar: $error';
  }

  @override
  String get devicesRemoveTitle => '¿Eliminar dispositivo?';

  @override
  String get devicesRemoveBodyCurrent =>
      'Este es el dispositivo que estás usando. Al eliminarlo se borran las anulaciones de preferencias por dispositivo; el dispositivo sigue con la sesión iniciada.';

  @override
  String get devicesRemoveBodyOther =>
      'Elimina la entrada del dispositivo y cualquier anulación de preferencias por dispositivo. El dispositivo permanece con la sesión iniciada hasta que abra la app de nuevo.';

  @override
  String get devicesRemove => 'Eliminar';

  @override
  String devicesRemoveFailed(Object error) {
    return 'Error al eliminar: $error';
  }

  @override
  String devicesSaveFailed(Object error) {
    return 'Error al guardar: $error';
  }

  @override
  String get devicesLoadError => 'No se pudieron cargar los dispositivos.';

  @override
  String get devicesEmpty =>
      'Aún no hay dispositivos: se registran la primera vez que un dispositivo abre la app con la sesión iniciada.';

  @override
  String get devicesThisDevice => 'Este dispositivo';

  @override
  String devicesLastSeen(String time) {
    return 'Visto por última vez $time';
  }

  @override
  String devicesOverrideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anulaciones',
      one: '$count anulación',
    );
    return '$_temp0';
  }

  @override
  String get devicesJustNow => 'ahora mismo';

  @override
  String devicesMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String devicesHoursAgo(int hours) {
    return 'hace $hours h';
  }

  @override
  String devicesDaysAgo(int days) {
    return 'hace $days d';
  }

  @override
  String get devicesRename => 'Renombrar';

  @override
  String get devicesEditOverrides => 'Editar anulaciones…';

  @override
  String get devicesEveryKeySet =>
      'Todas las claves anulables ya están establecidas; elimina una antes de añadir otra.';

  @override
  String get devicesOverridesSheetTitle => 'Anulaciones por dispositivo';

  @override
  String get devicesOverridesSheetDesc =>
      'Estas claves anulan los ajustes universales solo en este dispositivo.';

  @override
  String get devicesNoOverrides => 'No hay anulaciones en este dispositivo.';

  @override
  String get devicesAddOverride => 'Añadir anulación';

  @override
  String get devicesPickKey => 'Elegir una clave';

  @override
  String get devicesEnterWholeNumber => 'Introduce un número entero.';

  @override
  String get devicesEnterNumber => 'Introduce un número (p. ej. 0,8).';

  @override
  String get devicesValue => 'Valor';

  @override
  String get devicesBack => 'Atrás';

  @override
  String get devicesAdd => 'Añadir';

  @override
  String get devicesKeyPreferredUnitLabel => 'Unidad preferida';

  @override
  String get devicesKeyPreferredUnitHint =>
      'Unidad de distancia para todas las pantallas.';

  @override
  String get devicesKeyDefaultActivityLabel => 'Actividad predeterminada';

  @override
  String get devicesKeyDefaultActivityHint =>
      'Actividad preseleccionada en la pantalla de inicio.';

  @override
  String get devicesKeyMapStyleLabel => 'Estilo de mapa';

  @override
  String get devicesKeyMapStyleHint =>
      'Estilo MapLibre para la vista del mapa.';

  @override
  String get devicesKeyPaceFormatLabel => 'Formato de ritmo';

  @override
  String get devicesKeyPaceFormatHint => 'Formato de visualización del ritmo.';

  @override
  String get devicesKeyVoiceFeedbackLabel => 'Comentarios de voz';

  @override
  String get devicesKeyVoiceFeedbackHint =>
      'Anuncia avisos de ritmo / distancia durante una carrera.';

  @override
  String get devicesKeyVoiceIntervalLabel =>
      'Intervalo de comentarios de voz (km)';

  @override
  String get devicesKeyVoiceIntervalHint =>
      'Distancia entre los avisos hablados.';

  @override
  String get devicesKeyHapticLabel => 'Respuesta háptica';

  @override
  String get devicesKeyHapticHint =>
      'Vibración en cambios de vuelta y zona de ritmo.';

  @override
  String get devicesKeyKeepScreenOnLabel => 'Mantener pantalla encendida';

  @override
  String get devicesKeyKeepScreenOnHint =>
      'Desactiva el atenuado automático del SO durante la grabación.';

  @override
  String get gearTitle => 'Equipo';

  @override
  String get gearAddGear => 'Añadir equipo';

  @override
  String get gearDeleteTitle => '¿Eliminar equipo?';

  @override
  String gearDeleteBody(String name) {
    return '¿Eliminar «$name»? Se perderá el historial de kilometraje de carreras anteriores. Retíralo en su lugar para conservar los registros.';
  }

  @override
  String get gearCancel => 'Cancelar';

  @override
  String get gearDelete => 'Eliminar';

  @override
  String get gearDeletedOffline =>
      'Eliminado localmente: se sincronizará cuando vuelvas a conectarte.';

  @override
  String gearAttached(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se asoció $name a $count carreras.',
      one: 'Se asoció $name a $count carrera.',
    );
    return '$_temp0';
  }

  @override
  String gearOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Sin conexión — $count cambios en cola, mostrando equipo en caché.',
      one: 'Sin conexión — $count cambio en cola, mostrando equipo en caché.',
    );
    return '$_temp0';
  }

  @override
  String get gearOfflineCached => 'Sin conexión: mostrando equipo en caché.';

  @override
  String get gearShoes => 'Zapatillas';

  @override
  String get gearBikes => 'Bicicletas';

  @override
  String get gearRetired => 'RETIRADO';

  @override
  String get gearEmptyShoes => 'Aún no hay zapatillas';

  @override
  String get gearEmptyBikes => 'Aún no hay bicicletas';

  @override
  String get gearEmptySubtitle =>
      'Añade un par para seguir el kilometraje y recibir recordatorios de retiro.';

  @override
  String gearRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras',
      one: '$count carrera',
    );
    return '$_temp0';
  }

  @override
  String get gearWearDue => 'Reemplazar pronto';

  @override
  String get gearWearWorn => 'Distancia de reemplazo superada';

  @override
  String get gearRetire => 'Retirar';

  @override
  String get gearRestore => 'Restaurar';

  @override
  String get gearRotationsTitle => 'Rotaciones';

  @override
  String get gearRotationsHint =>
      'Agrupa el equipo que alternas: un conjunto de «Entrenamiento diario», un conjunto de «Día de carrera». Una rotación es solo una agrupación con nombre; no cambia qué par etiqueta automáticamente las nuevas carreras.';

  @override
  String get gearRotationsEmpty =>
      'Aún no hay rotaciones. Crea una para agrupar un conjunto de zapatillas o bicicletas.';

  @override
  String get gearRotationName => 'Nombre de la rotación';

  @override
  String get gearRotationNew => 'Nueva rotación';

  @override
  String get gearRotationCreate => 'Crear';

  @override
  String get gearRotationRename => 'Renombrar';

  @override
  String get gearRotationManage => 'Editar equipo';

  @override
  String gearRotationManageTitle(String name) {
    return 'Equipo en «$name»';
  }

  @override
  String get gearRotationDeleteTitle => '¿Eliminar rotación?';

  @override
  String gearRotationDeleteBody(String name) {
    return '¿Eliminar la rotación «$name»? Tu equipo no se ve afectado: solo se elimina la agrupación.';
  }

  @override
  String gearRotationMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '$count elemento',
    );
    return '$_temp0';
  }

  @override
  String get gearRotationNoGear =>
      'Añade primero algo de equipo y luego podrás agruparlo en una rotación.';

  @override
  String gearRotationSaveFailed(Object error) {
    return 'No se pudo guardar la rotación: $error';
  }

  @override
  String get gearRotationDone => 'Listo';

  @override
  String get privacyZonesTitle => 'Zonas de privacidad';

  @override
  String get privacyZonesSaved => 'Zonas de privacidad guardadas.';

  @override
  String privacyZonesSaveFailed(Object error) {
    return 'Error al guardar: $error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return 'Ubicación no disponible: $error';
  }

  @override
  String get privacyZonesSave => 'Guardar';

  @override
  String get privacyZonesLocateMe => 'Ubicarme';

  @override
  String get privacyZonesHint =>
      'Toca el mapa para añadir una zona. Los trazados en superficies públicas se recortan al inicio y al final más allá del radio de la zona.';

  @override
  String get privacyZonesSearchHint => 'Buscar lugares…';

  @override
  String get privacyZonesRadius => 'Radio';

  @override
  String privacyZonesRadiusMeters(int meters) {
    return '$meters m';
  }

  @override
  String privacyZonesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zonas — toca un marcador para eliminarla.',
      one: '$count zona — toca un marcador para eliminarla.',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'Borrar todo';

  @override
  String get privacyZonesRemoveTitle => '¿Eliminar la zona de privacidad?';

  @override
  String get privacyZonesRemoveBody =>
      'Esta zona oculta tus recorridos cercanos en las publicaciones públicas. Eliminarla vuelve a exponer esta área.';

  @override
  String get privacyZonesRemoveSemantics => 'Eliminar zona de privacidad';

  @override
  String get privacyZonesClearAllTitle =>
      '¿Borrar todas las zonas de privacidad?';

  @override
  String get privacyZonesClearAllBody =>
      'Esto elimina todas las zonas y vuelve a exponer todas estas áreas en las publicaciones públicas.';

  @override
  String get prefsTitle => 'Preferencias';

  @override
  String get prefsUnitMetric => 'km, m';

  @override
  String get prefsUnitImperial => 'mi, ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · sincronizado con tus otros dispositivos';
  }

  @override
  String get prefsClear => 'Borrar';

  @override
  String get prefsCancel => 'Cancelar';

  @override
  String get prefsSave => 'Guardar';

  @override
  String get prefsSplitInterval => 'Intervalo de parciales';

  @override
  String get prefsSplitIntervalDefault => 'Predeterminado';

  @override
  String get prefsSplitIntervalDefaultSubtitle =>
      'Predeterminado (1 km al correr, 5 km en bici)';

  @override
  String get prefsLivePaceAlert => 'Alerta de ritmo en vivo';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 's';

  @override
  String get prefsLivePaceAlertOff =>
      'Desactivado: define un ritmo para recibir avisos hablados durante una carrera';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — aviso hablado durante una carrera cuando hay 30 s+ de desvío';
  }

  @override
  String get prefsActivityRun => 'Correr';

  @override
  String get prefsActivityWalk => 'Caminar';

  @override
  String get prefsActivityHike => 'Senderismo';

  @override
  String get prefsActivityCycle => 'Ciclismo';

  @override
  String get prefsPaceFormat => 'Formato de ritmo';

  @override
  String get prefsPaceFormatMinPerKm => 'Minutos por km';

  @override
  String get prefsPaceFormatMinPerMi => 'Minutos por milla';

  @override
  String get prefsPaceFormatKph => 'km/h';

  @override
  String get prefsPaceFormatMph => 'mph';

  @override
  String get prefsWeightUnit => 'Unidad de peso';

  @override
  String get prefsWeightUnitKg => 'Kilogramos (kg)';

  @override
  String get prefsWeightUnitLbs => 'Libras (lbs)';

  @override
  String get prefsNotSet => 'Sin definir';

  @override
  String prefsHrZonesSummary(String zones) {
    return '$zones ppm';
  }

  @override
  String prefsWeeklyGoalSummary(String distance, String unit) {
    return '$distance $unit / semana';
  }

  @override
  String get prefsMapStyle => 'Estilo de mapa';

  @override
  String get prefsMapStyleStreets => 'Calles';

  @override
  String get prefsMapStyleSatellite => 'Satélite';

  @override
  String get prefsMapStyleOutdoors => 'Aire libre';

  @override
  String get prefsMapStyleDark => 'Oscuro';

  @override
  String get prefsDefaultRunVisibility =>
      'Visibilidad predeterminada de las carreras';

  @override
  String get prefsCoachPersonality => 'Personalidad del entrenador';

  @override
  String get prefsCoachSupportive => 'Comprensivo';

  @override
  String get prefsCoachDrillSergeant => 'Sargento instructor';

  @override
  String get prefsCoachAnalytical => 'Analítico';

  @override
  String get prefsSectionNotifications => 'Notificaciones';

  @override
  String get prefsEmailNotifications => 'Notificaciones por correo';

  @override
  String get prefsEmailNotifAll => 'Todas';

  @override
  String get prefsEmailNotifImportant => 'Solo importantes';

  @override
  String get prefsEmailNotifOff => 'Desactivadas';

  @override
  String get prefsPushNotifications => 'Notificaciones push';

  @override
  String get prefsPushNotifAll => 'Todas';

  @override
  String get prefsPushNotifImportant => 'Solo importantes';

  @override
  String get prefsPushNotifOff => 'Desactivadas';

  @override
  String get prefsEmailWeeklyDigest => 'Correo de resumen semanal';

  @override
  String get prefsEmailWeeklyDigestHint =>
      'Suscríbete a un resumen semanal de tu entrenamiento y lo más destacado de la comunidad. Desactivado por defecto; independiente de tus correos de notificaciones.';

  @override
  String get prefsEmailLifecycleDrip => 'Correo de consejos y ánimo';

  @override
  String get prefsEmailLifecycleDripHint =>
      'Suscríbete para recibir recordatorios ocasionales de inicio, reactivación y rachas. Desactivado por defecto; independiente de tu resumen semanal y de tus correos de notificaciones.';

  @override
  String get prefsWeekStart => 'La semana empieza el';

  @override
  String get prefsWeekStartMonday => 'Lunes';

  @override
  String get prefsWeekStartSunday => 'Domingo';

  @override
  String get prefsDefaultActivity => 'Actividad predeterminada';

  @override
  String get prefsDateOfBirth => 'Fecha de nacimiento';

  @override
  String get prefsRestingHr => 'Frecuencia cardíaca en reposo';

  @override
  String get prefsMaxHr => 'Frecuencia cardíaca máxima';

  @override
  String get prefsMaxHrNotSet => 'Sin definir: se usa 208 − 0,7 × edad';

  @override
  String prefsHrBpm(int bpm) {
    return '$bpm ppm';
  }

  @override
  String get prefsSectionFueling => 'Avituallamiento de carrera';

  @override
  String get prefsCarbsPerHour => 'Carbohidratos por hora';

  @override
  String prefsCarbsPerHourValue(int grams) {
    return '$grams g/h';
  }

  @override
  String get prefsFluidPerHour => 'Líquido por hora';

  @override
  String prefsFluidPerHourValue(int ml) {
    return '$ml ml/h';
  }

  @override
  String get prefsHrZones => 'Zonas de frecuencia cardíaca';

  @override
  String get prefsHrZonesDialogTitle =>
      'Zonas de frecuencia cardíaca (límites superiores, ppm)';

  @override
  String get prefsWeeklyGoal => 'Objetivo de kilometraje semanal';

  @override
  String get prefsSectionActivityRecording => 'Actividad y grabación';

  @override
  String get prefsSectionTrainingDemographics =>
      'Entrenamiento y datos demográficos';

  @override
  String get prefsSectionPrivacySharing => 'Privacidad y uso compartido';

  @override
  String get prefsSectionAiCoach => 'Entrenador de IA';

  @override
  String get prefsSignInToEdit =>
      'Inicia sesión para editar los ajustes de perfil que se sincronizan entre dispositivos.';

  @override
  String get prefsUseMiles => 'Usar millas';

  @override
  String get prefsDarkMode => 'Modo oscuro';

  @override
  String get prefsAudioCues => 'Avisos de audio';

  @override
  String get prefsAudioCuesSubtitle => 'Anuncios hablados de parciales';

  @override
  String get prefsMinimalVoiceCues => 'Avisos de voz mínimos';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Omite los avisos charlatanes de media repetición y desvío de ritmo';

  @override
  String get prefsKeepScreenOn => 'Mantener pantalla encendida';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Mantiene un wakelock durante una carrera';

  @override
  String get prefsAdvancedGps => 'GPS avanzado';

  @override
  String get prefsAdvancedGpsSubtitle =>
      'Mayor precisión, trazado más detallado, más consumo de batería';

  @override
  String get prefsShowRawTrack => 'Mostrar trayecto GPS sin procesar';

  @override
  String get prefsShowRawTrackSubtitle =>
      'Dibuja la línea grabada sin ajustar en el mapa de la carrera, aunque exista un trayecto ya corregido';

  @override
  String get prefsShowCalories => 'Mostrar estimaciones de calorías';

  @override
  String get prefsShowCaloriesHint =>
      'Estimadas a partir de la distancia y el peso corporal (70 kg por defecto si no se ha configurado). Desactívalo para ocultar las calorías en las páginas de carrera.';

  @override
  String get prefsDefaultRunPrivacy =>
      'Privacidad predeterminada de las carreras';

  @override
  String get prefsStravaAutoShare => 'Compartir automático en Strava';

  @override
  String get prefsStravaAutoShareSubtitle =>
      'Envía automáticamente cada nueva carrera a Strava. Requiere una integración de Strava conectada cuando esté disponible.';

  @override
  String get prefsDiscoverable => 'Mostrarme en la búsqueda por nombre';

  @override
  String get prefsDiscoverableSubtitle =>
      'Si está desactivado, tu cuenta no aparecerá cuando otros corredores busquen por nombre visible. Tus carreras públicas y tu perfil siguen siendo accesibles para cualquiera que tenga la URL.';

  @override
  String get dashboardCoachTooltip => 'Entrenador';

  @override
  String get dashboardFeedTooltip => 'Feed de actividad';

  @override
  String get dashboardRecapTooltip => 'Año en carrera';

  @override
  String get dashboardProfileTooltip => 'Mi perfil';

  @override
  String get dashboardWelcomeTitle => '¡Bienvenido!';

  @override
  String get dashboardWelcomeBody =>
      'Tu panel se completa en cuanto registras una carrera, defines un objetivo o importas tu historial.';

  @override
  String get dashboardSetGoal => 'Definir un objetivo';

  @override
  String get dashboardImportRuns => 'Importar carreras';

  @override
  String get dashboardPeriodWeek => 'Semana';

  @override
  String get dashboardPeriodMonth => 'Mes';

  @override
  String get dashboardPeriodAllTime => 'Histórico';

  @override
  String get dashboardSectionStreak => 'Racha';

  @override
  String get dashboardWeekStripTitle => 'Esta semana';

  @override
  String dashboardWeekStripCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count actividades',
      one: '$count actividad',
    );
    return '$_temp0';
  }

  @override
  String dashboardWeekStripDayAria(String dow, String dist) {
    return '$dow: $dist';
  }

  @override
  String dashboardWeekStripDayRestAria(String dow) {
    return '$dow: día de descanso';
  }

  @override
  String get dashboardSectionLast20Weeks => 'Últimas 20 semanas';

  @override
  String get dashboardSectionRecentLifts => 'Sesiones recientes';

  @override
  String get dashboardViewAllGym => 'Ver todo';

  @override
  String get dashboardSectionPersonalBests => 'Mejores marcas personales';

  @override
  String get dashboardLongestRun => 'Carrera más larga';

  @override
  String dashboardFastestDistance(String distance) {
    return 'Más rápido en $distance';
  }

  @override
  String get dashboardGoals => 'Objetivos';

  @override
  String get dashboardAdd => 'Añadir';

  @override
  String get dashboardGoalWeekly => 'SEMANAL';

  @override
  String get dashboardGoalMonthly => 'MENSUAL';

  @override
  String dashboardGoalTitleFallback(String period) {
    return 'OBJETIVO $period';
  }

  @override
  String get dashboardSetWeeklyGoalA11y =>
      'Definir un objetivo de carrera semanal';

  @override
  String get dashboardSetFirstGoal => 'Define tu primer objetivo';

  @override
  String get dashboardSetFirstGoalBody =>
      'Sigue la distancia, el tiempo, el ritmo o el número de carreras por semana o mes.';

  @override
  String get dashboardGoalTapToEdit => 'toca para editar';

  @override
  String get dashboardGoalComplete => 'Completado.';

  @override
  String get dashboardGoalInProgress => 'En progreso.';

  @override
  String dashboardGoalA11y(String period, String title, String status) {
    return 'Objetivo $period — $title $status';
  }

  @override
  String dashboardRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras',
      one: '$count carrera',
    );
    return '$_temp0';
  }

  @override
  String dashboardVert(String value) {
    return '$value de desnivel';
  }

  @override
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  ) {
    return 'Resumen de $label, $distance en $runs$elevation';
  }

  @override
  String dashboardElevationGainSuffix(String value) {
    return ', $value de desnivel positivo';
  }

  @override
  String get dashboardStreakCurrent => 'Actual';

  @override
  String get dashboardStreakHistory => 'Historial';

  @override
  String get dashboardStreakDayUnit => 'día';

  @override
  String get dashboardStreakDaysUnit => 'días';

  @override
  String dashboardStreakBest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '$count día',
    );
    return 'mejor $_temp0';
  }

  @override
  String get dashboardStreakAllTimeBest => 'mejor de siempre';

  @override
  String get dashboardStreakRestart => 'corre hoy para reiniciarla';

  @override
  String get dashboardStreakStart => 'corre hoy para empezar una';

  @override
  String get dashboardHeatmapLess => 'Menos';

  @override
  String get dashboardHeatmapMore => 'Más';

  @override
  String get dashboardHeatmapTapHint => 'Toca una semana para ver su resumen';

  @override
  String get periodWeeklySummary => 'Resumen semanal';

  @override
  String get periodMonthlySummary => 'Resumen mensual';

  @override
  String get periodAllTimeSummary => 'Resumen histórico';

  @override
  String get periodShareTooltip => 'Compartir';

  @override
  String get periodPreviousTooltip => 'Anterior';

  @override
  String get periodNextTooltip => 'Siguiente';

  @override
  String get periodSwitchToWeekly => 'Toca para cambiar a semanal';

  @override
  String get periodSwitchToMonthly => 'Toca para cambiar a mensual';

  @override
  String get periodSwitchToAllTime => 'Toca para cambiar a histórico';

  @override
  String get periodStatDistance => 'Distancia';

  @override
  String get periodStatRuns => 'Carreras';

  @override
  String get periodStatTime => 'Tiempo';

  @override
  String get periodStatAvgPace => 'Ritmo medio';

  @override
  String get periodEmptyWeek => 'Sin carreras esta semana';

  @override
  String get periodEmptyMonth => 'Sin carreras este mes';

  @override
  String get periodShareSummary => 'Compartir resumen';

  @override
  String get periodShareText => 'Texto';

  @override
  String get periodShareImage => 'Imagen';

  @override
  String get periodShareImageFailed =>
      'No se pudo crear la imagen para compartir';

  @override
  String get periodShareCardTagline => 'MEJOR CORREDOR';

  @override
  String get periodShareStatDistance => 'DISTANCIA';

  @override
  String get periodShareStatRuns => 'CARRERAS';

  @override
  String get periodShareStatTime => 'TIEMPO';

  @override
  String get periodShareStatAvgPace => 'RITMO MEDIO';

  @override
  String get trainingLoadTitle => 'Estado, Fatiga y Forma';

  @override
  String trainingLoadSubtitleHr(int days) {
    return 'TRIMP de frecuencia cardíaca de los últimos $days días.';
  }

  @override
  String get trainingLoadSubtitleVolume =>
      'Basado en volumen: configura la FC en reposo y máxima en preferencias y registra con una banda para pasar a TRIMP.';

  @override
  String get trainingLoadEmpty =>
      'Registra algunas carreras para ver tu tendencia de estado físico.';

  @override
  String get trainingLoadLegendFitness => 'Estado';

  @override
  String get trainingLoadLegendFatigue => 'Fatiga';

  @override
  String get trainingLoadLegendForm => 'Forma';

  @override
  String trainingLoadLegendEntry(String label, int value) {
    return '$label · $value';
  }

  @override
  String get trainingLoadReadingLoaded =>
      'Cargado: sigue adelante y recupera cuando estés listo.';

  @override
  String get trainingLoadReadingTapered =>
      'En descarga: una sesión dura no te romperá.';

  @override
  String get trainingLoadReadingBalanced =>
      'Equilibrado: día suave o día duro, tú decides.';

  @override
  String get trainingLoadIncludesLifts =>
      'Incluye sesiones de gimnasio: las pesas también suman fatiga.';

  @override
  String get intensityTitle => 'INTENSIDAD DE ENTRENAMIENTO';

  @override
  String intensityWindow(int days) {
    return 'últimos $days días';
  }

  @override
  String intensityBasedOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras con FC',
      one: '$count carrera con FC',
    );
    return 'Según $_temp0';
  }

  @override
  String get mileageTitle => 'KILOMETRAJE';

  @override
  String get mileageWeek => 'Semana';

  @override
  String get mileageMonth => 'Mes';

  @override
  String get mileageYear => 'Año';

  @override
  String get mileageThisWeek => 'esta semana';

  @override
  String get mileageThisMonth => 'este mes';

  @override
  String get mileageThisYear => 'este año';

  @override
  String get fitnessTitle => 'Estado físico';

  @override
  String get fitnessStatVo2Max => 'VO₂ máx';

  @override
  String get fitnessStatVo2MaxTooltip =>
      'Tu motor aeróbico: cuánto oxígeno puede usar tu cuerpo por minuto. Cuanto más alto, mejor forma.';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'La puntuación de forma de Daniels según tu mejor esfuerzo reciente. Define tus ritmos de entrenamiento.';

  @override
  String get fitnessStatRuns => 'Carreras';

  @override
  String get fitnessStatRunsTooltip =>
      'Carreras recientes lo bastante largas para contar en tu estimación de forma.';

  @override
  String get fitnessStatCtl => 'Estado (CTL)';

  @override
  String get fitnessStatCtlTooltip =>
      'Tu carga de entrenamiento móvil de 42 días. Se construye despacio; es tu base de resistencia.';

  @override
  String get fitnessStatAtl => 'Fatiga (ATL)';

  @override
  String get fitnessStatAtlTooltip =>
      'Tu carga de los últimos 7 días. Sube rápido tras sesiones duras y baja con el descanso.';

  @override
  String get fitnessStatTsb => 'Forma (TSB)';

  @override
  String get fitnessStatTsbTooltip =>
      'Estado menos fatiga. Positivo = fresco y listo para competir; negativo = con fatiga acumulada.';

  @override
  String get runSocialActivity => 'Actividad';

  @override
  String get runSocialNoComments => 'Aún no hay comentarios.';

  @override
  String get runSocialReplyHint => 'Escribe una respuesta…';

  @override
  String get runSocialCommentHint => 'Añade un comentario…';

  @override
  String get runSocialRunnerFallback => 'Corredor';

  @override
  String get runSocialReply => 'Responder';

  @override
  String get runSocialDelete => 'Eliminar';

  @override
  String get runSocialReportComment => 'Denunciar comentario';

  @override
  String get runSocialReportReply => 'Denunciar respuesta';

  @override
  String get runSocialDeleteCommentTitle => '¿Eliminar este comentario?';

  @override
  String get runSocialDeleteCommentMessage =>
      'Este comentario se eliminará de forma permanente. No se puede deshacer.';

  @override
  String get runSocialPost => 'Publicar';

  @override
  String get runSocialCancel => 'Cancelar';

  @override
  String get kudosGiveLabel => 'Dar kudos';

  @override
  String get kudosRemoveLabel => 'Quitar kudos';

  @override
  String get kudosViewCommentsLabel => 'Ver comentarios';

  @override
  String runSocialKudosError(String error) {
    return 'No se pudieron actualizar los kudos: $error';
  }

  @override
  String runSocialPostError(String error) {
    return 'Error al publicar: $error';
  }

  @override
  String runSocialDeleteError(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String get runPhotosLoading => 'Cargando fotos…';

  @override
  String get runPhotosTitle => 'Fotos';

  @override
  String get runPhotosAdd => 'Añadir foto';

  @override
  String get runPhotosCaptionPendingHint =>
      'Pie de foto (opcional, 280 caracteres)';

  @override
  String get runPhotosCaptionHint => 'Pie de foto…';

  @override
  String get runPhotosCancel => 'Cancelar';

  @override
  String get runPhotosSave => 'Guardar';

  @override
  String get runPhotosUpload => 'Subir';

  @override
  String get runPhotosUploading => 'Subiendo…';

  @override
  String get runPhotosEditCaption => 'Editar pie de foto';

  @override
  String get runPhotosDeleteTooltip => 'Eliminar foto';

  @override
  String get runPhotosDeleteTitle => '¿Eliminar foto?';

  @override
  String get runPhotosDeleteBody =>
      'Esto elimina la foto de la carrera de forma permanente.';

  @override
  String get runPhotosDeleteConfirm => 'Eliminar';

  @override
  String get runPhotosPermissionDenied =>
      'Se necesita acceso a las fotos para añadir una foto. Puedes permitirlo en Ajustes.';

  @override
  String get runPhotosOpenSettings => 'Abrir ajustes';

  @override
  String get runPhotosPickerFailed =>
      'No se pudo abrir el selector de fotos. Inténtalo de nuevo.';

  @override
  String runPhotosUploadError(String error) {
    return 'Error al subir: $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'No se pudo actualizar el pie de foto: $error';
  }

  @override
  String get routePhotosLoading => 'Cargando fotos…';

  @override
  String get routePhotosTitle => 'Fotos';

  @override
  String get routePhotosAdd => 'Añadir foto';

  @override
  String get routePhotosCaptionPendingHint =>
      'Pie de foto (opcional, 280 caracteres)';

  @override
  String get routePhotosCaptionHint => 'Pie de foto…';

  @override
  String get routePhotosCancel => 'Cancelar';

  @override
  String get routePhotosSave => 'Guardar';

  @override
  String get routePhotosUpload => 'Subir';

  @override
  String get routePhotosUploading => 'Subiendo…';

  @override
  String get routePhotosEditCaption => 'Editar pie de foto';

  @override
  String get routePhotosDeleteTooltip => 'Eliminar foto';

  @override
  String get routePhotosDeleteTitle => '¿Eliminar foto?';

  @override
  String get routePhotosDeleteBody =>
      'Esto elimina la foto de la ruta de forma permanente.';

  @override
  String get routePhotosDeleteConfirm => 'Eliminar';

  @override
  String routePhotosPickerError(String error) {
    return 'No se pudo abrir el selector: $error';
  }

  @override
  String routePhotosUploadError(String error) {
    return 'Error al subir: $error';
  }

  @override
  String routePhotosDeleteError(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'No se pudo actualizar el pie de foto: $error';
  }

  @override
  String get clubPhotosLoading => 'Cargando fotos…';

  @override
  String get clubPhotosTitle => 'Fotos';

  @override
  String get clubPhotosAdd => 'Añadir foto';

  @override
  String get clubPhotosEmpty => 'Aún no hay fotos en este club.';

  @override
  String get clubPhotosCaptionPendingHint =>
      'Pie de foto (opcional, 280 caracteres)';

  @override
  String get clubPhotosCaptionHint => 'Pie de foto…';

  @override
  String get clubPhotosCancel => 'Cancelar';

  @override
  String get clubPhotosSave => 'Guardar';

  @override
  String get clubPhotosUpload => 'Subir';

  @override
  String get clubPhotosUploading => 'Subiendo…';

  @override
  String get clubPhotosEditCaption => 'Editar pie de foto';

  @override
  String get clubPhotosDeleteTooltip => 'Eliminar foto';

  @override
  String get clubPhotosDeleteTitle => '¿Eliminar foto?';

  @override
  String get clubPhotosDeleteBody =>
      'Esto elimina la foto del club de forma permanente.';

  @override
  String get clubPhotosDeleteConfirm => 'Eliminar';

  @override
  String clubPhotosPickerError(String error) {
    return 'No se pudo abrir el selector: $error';
  }

  @override
  String clubPhotosUploadError(String error) {
    return 'Error al subir: $error';
  }

  @override
  String clubPhotosDeleteError(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String clubPhotosCaptionError(String error) {
    return 'No se pudo actualizar el pie de foto: $error';
  }

  @override
  String get runSegEffortsChecking => 'Comprobando segmentos…';

  @override
  String get runSegEffortsNoRoute =>
      'Los segmentos se asocian por ruta: vincula esta carrera a una ruta guardada para competir en sus clasificaciones.';

  @override
  String get runSegEffortsEmpty =>
      'No hay esfuerzos de segmento en esta carrera.';

  @override
  String get workoutReviewTitle => 'Entrenamiento';

  @override
  String get workoutReviewColStep => 'Paso';

  @override
  String get workoutReviewColPlan => 'Plan';

  @override
  String get workoutReviewColActual => 'Real';

  @override
  String get workoutReviewColPace => 'Ritmo';

  @override
  String get workoutReviewColDelta => 'Δ';

  @override
  String get workoutReviewSkip => 'omitir';

  @override
  String get workoutReviewLabelWarmup => 'Calentamiento';

  @override
  String get workoutReviewLabelCooldown => 'Enfriamiento';

  @override
  String get workoutReviewLabelSteady => 'Constante';

  @override
  String get workoutReviewLabelRep => 'Rep.';

  @override
  String workoutReviewLabelRepN(int index, int total) {
    return 'Rep. $index/$total';
  }

  @override
  String get workoutReviewLabelRecovery => 'Recuperación';

  @override
  String workoutReviewLabelRecoveryN(int index, int total) {
    return 'Recuperación $index/$total';
  }

  @override
  String get workoutReviewLabelWalk => 'Caminata';

  @override
  String workoutReviewLabelWalkN(int index, int total) {
    return 'Caminata $index/$total';
  }

  @override
  String get segmentsPanelTitle => 'Segmentos';

  @override
  String get segmentsPanelNew => 'Nuevo segmento';

  @override
  String get segmentsPanelCancel => 'Cancelar';

  @override
  String get segmentsPanelLoading => 'Cargando segmentos…';

  @override
  String get segmentsPanelEmpty => 'Aún no hay segmentos en esta ruta.';

  @override
  String get segmentsPanelNameLabel => 'Nombre';

  @override
  String get segmentsPanelNameHint => 'Subida infernal';

  @override
  String get segmentsPanelStartLabel => 'Inicio (m)';

  @override
  String get segmentsPanelEndLabel => 'Fin (m)';

  @override
  String segmentsPanelRouteHint(int metres) {
    return 'la ruta mide $metres m';
  }

  @override
  String get segmentsPanelCreate => 'Crear';

  @override
  String get segmentsPanelDeleteTooltip => 'Eliminar segmento';

  @override
  String get segmentsPanelDeleteTitle => '¿Eliminar segmento?';

  @override
  String segmentsPanelDeleteBody(String name) {
    return 'Se eliminará «$name».';
  }

  @override
  String get segmentsPanelDeleteConfirm => 'Eliminar';

  @override
  String get segmentsPanelErrEndAfterStart =>
      'El fin debe ser mayor que el inicio';

  @override
  String get segmentsPanelErrMinLength =>
      'El segmento debe medir al menos 100 m';

  @override
  String segmentsPanelCreateError(String error) {
    return 'No se pudo crear el segmento: $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String get segmentsPanelAllGenders => 'Todos los géneros';

  @override
  String get segmentsPanelGenderMen => 'Hombres';

  @override
  String get segmentsPanelGenderWomen => 'Mujeres';

  @override
  String get segmentsPanelGenderNonbinary => 'No binario';

  @override
  String get segmentsPanelAllAges => 'Todas las edades';

  @override
  String get segmentsPanelResetFilters => 'Restablecer';

  @override
  String get segmentsPanelLeaderboardLoading => 'Cargando…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'Ningún esfuerzo coincide con este filtro: prueba a ampliarlo.';

  @override
  String get segmentsPanelLeaderboardEmpty =>
      'Aún no hay esfuerzos: sé el primero en correr este segmento.';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'Tienes esta corona: $label.';
  }

  @override
  String get segmentsPanelRunnerFallback => 'Corredor';

  @override
  String get goalEditorTitleNew => 'Nuevo objetivo';

  @override
  String get goalEditorTitleEdit => 'Editar objetivo';

  @override
  String get goalEditorNameLabel => 'Nombre (opcional)';

  @override
  String get goalEditorNameHint => 'p. ej. Kilómetros base';

  @override
  String get goalEditorPeriod => 'Período';

  @override
  String get goalEditorThisWeek => 'Esta semana';

  @override
  String get goalEditorThisMonth => 'Este mes';

  @override
  String get goalEditorTargets => 'Objetivos';

  @override
  String get goalEditorTargetsHelp =>
      'Establece cualquier combinación. Los campos vacíos se ignoran.';

  @override
  String get goalEditorTargetDistance => 'Distancia';

  @override
  String get goalEditorTargetTime => 'Tiempo';

  @override
  String get goalEditorTargetPace => 'Ritmo medio';

  @override
  String get goalEditorTargetRuns => 'Carreras';

  @override
  String get goalEditorSuffixMin => 'min';

  @override
  String get goalEditorSuffixRuns => 'carreras';

  @override
  String get goalEditorDelete => 'Eliminar';

  @override
  String get goalEditorDeleteTitle => '¿Eliminar este objetivo?';

  @override
  String get goalEditorDeleteMessage =>
      'Este objetivo y su seguimiento de progreso se eliminarán. Puedes crear uno nuevo cuando quieras.';

  @override
  String get goalEditorCancel => 'Cancelar';

  @override
  String get goalEditorSave => 'Guardar';

  @override
  String goalEditorSaveFailed(String error) {
    return 'No se pudo guardar el objetivo: $error';
  }

  @override
  String get goalEditorErrDistance => 'Distancia: introduce un número positivo';

  @override
  String get goalEditorErrTime =>
      'Tiempo: introduce un número positivo de minutos';

  @override
  String get goalEditorErrPace => 'Ritmo: usa mm:ss (p. ej. 5:00)';

  @override
  String get goalEditorErrRuns =>
      'Carreras: introduce un número entero positivo';

  @override
  String get goalEditorErrNoTarget => 'Establece al menos un objetivo';

  @override
  String get goalEditorSavedAnnounce => 'Objetivo guardado';

  @override
  String get goalEditorDeletedAnnounce => 'Objetivo eliminado';

  @override
  String get eventFormTitle => 'Nuevo evento';

  @override
  String get eventFormTitleLabel => 'Título';

  @override
  String get eventFormStartsAt => 'Comienza el';

  @override
  String get eventFormDescriptionLabel => 'Descripción (opcional)';

  @override
  String get eventFormMeetLabel => 'Punto de encuentro (opcional)';

  @override
  String get eventFormMeetHint => 'Aparcamiento del sendero';

  @override
  String get eventFormDistanceLabel => 'Distancia (km)';

  @override
  String get eventFormDurationLabel => 'Duración (min)';

  @override
  String get eventFormRecurrence => 'Repetición';

  @override
  String get eventFormRecurOneOff => 'Único';

  @override
  String get eventFormRecurWeekly => 'Semanal';

  @override
  String get eventFormRecurBiweekly => 'Quincenal';

  @override
  String get eventFormRecurMonthly => 'Mensual';

  @override
  String get eventFormCancel => 'Cancelar';

  @override
  String get eventFormCreate => 'Crear evento';

  @override
  String get eventEditorCategory => 'Tipo de evento';

  @override
  String get eventEditorCatRun => 'Carrera en grupo';

  @override
  String get eventEditorCatCycle => 'Ciclismo';

  @override
  String get eventEditorCatClass => 'Clase';

  @override
  String get eventEditorCatSocial => 'Social';

  @override
  String get eventEditorCategoryHint =>
      'Elige el tipo de evento — una clase o un encuentro social omite ruta, distancia, ritmo y resultados de carrera.';

  @override
  String get eventEditorMembersOnlyToggle => 'Solo para miembros';

  @override
  String get eventEditorMembersOnlyHint =>
      'Solo los miembros del club pueden ver este evento y no aparecerá en la búsqueda pública.';

  @override
  String get eventEditorDiscipline => 'Disciplina';

  @override
  String get eventEditorDisciplinePlaceholder =>
      'p. ej. yoga Vinyasa, Pilates, movilidad';

  @override
  String get clubFormTitle => 'Nuevo club';

  @override
  String get clubFormNameLabel => 'Nombre';

  @override
  String get clubFormDescriptionLabel => 'Descripción (opcional)';

  @override
  String get clubFormLocationLabel => 'Ubicación (opcional)';

  @override
  String get clubFormLocationHint => 'Edimburgo, RU';

  @override
  String get clubFormPublic => 'Público';

  @override
  String get clubFormPrivate => 'Privado';

  @override
  String get clubFormJoinPolicy => 'Política de ingreso';

  @override
  String get clubFormJoinOpen => 'Abierto: cualquiera se une';

  @override
  String get clubFormJoinRequest => 'Solicitud: los administradores aprueban';

  @override
  String get clubFormJoinInvite => 'Solo por invitación';

  @override
  String get clubFormCancel => 'Cancelar';

  @override
  String get clubFormCreate => 'Crear';

  @override
  String get clubFormErrSlug =>
      'El nombre necesita al menos una letra o dígito.';

  @override
  String get clubFormErrUnreachable =>
      'No se puede acceder al servidor ahora mismo. Comprueba tu conexión o inicia sesión e inténtalo de nuevo.';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonHarassment => 'Acoso o abuso';

  @override
  String get reportReasonInappropriate => 'Contenido inapropiado';

  @override
  String get reportReasonImpersonation => 'Suplantación de identidad';

  @override
  String get reportReasonOther => 'Otro';

  @override
  String get reportSuccess =>
      'Informe enviado: gracias por marcarlo para su revisión.';

  @override
  String get reportTitleUser => 'Denunciar usuario';

  @override
  String get reportTitleClub => 'Denunciar club';

  @override
  String get reportTitleRoute => 'Denunciar ruta';

  @override
  String get reportTitleComment => 'Denunciar comentario';

  @override
  String get reportTitlePost => 'Denunciar publicación';

  @override
  String get reportTitleRun => 'Denunciar carrera';

  @override
  String get reportTitleReview => 'Denunciar reseña';

  @override
  String get reportTitleContent => 'Denunciar contenido';

  @override
  String get reportDisclaimer =>
      'Tu informe se envía a un moderador. Los informes falsos también se revisan: marca solo el contenido que infrinja nuestras normas de la comunidad.';

  @override
  String get reportReason => 'Motivo';

  @override
  String get reportNotesLabel => 'Notas (opcional)';

  @override
  String get reportCancel => 'Cancelar';

  @override
  String get reportSubmit => 'Enviar informe';

  @override
  String get reportErrDuplicate =>
      'Ya tienes un informe pendiente sobre este contenido.';

  @override
  String gearBackfillTitle(String gear) {
    return '¿Vincular carreras anteriores a $gear?';
  }

  @override
  String gearBackfillBody(int count, String activity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count actividades de $activity',
      one: '$count actividad de $activity',
    );
    return 'Encontramos $_temp0 después de comprarlos. Desmarca aquellas en las que no los usaste.';
  }

  @override
  String get gearBackfillActivityCycling => 'ciclismo';

  @override
  String get gearBackfillActivityRunning => 'carrera';

  @override
  String get gearBackfillSelectNone => 'No seleccionar ninguna';

  @override
  String get gearBackfillSelectAll => 'Seleccionar todas';

  @override
  String gearBackfillSelectedCount(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get gearBackfillSkip => 'Omitir';

  @override
  String get gearBackfillAttaching => 'Vinculando…';

  @override
  String gearBackfillAttach(int count) {
    return 'Vincular $count';
  }

  @override
  String gearBackfillAttachError(String error) {
    return 'Error al vincular: $error';
  }

  @override
  String get workoutEditTitle => 'Editar entrenamiento';

  @override
  String get workoutEditKindLabel => 'Tipo';

  @override
  String get workoutEditDistanceLabel => 'Distancia objetivo (km)';

  @override
  String get workoutEditDistanceHint => 'p. ej. 8.0';

  @override
  String get workoutEditPaceLabel => 'Ritmo objetivo (mm:ss /km)';

  @override
  String get workoutEditPaceHint => 'p. ej. 5:30';

  @override
  String get workoutEditNotesLabel => 'Notas';

  @override
  String get workoutEditCancel => 'Cancelar';

  @override
  String get workoutEditSave => 'Guardar';

  @override
  String get workoutEditErrDistance => 'Introduce una distancia positiva en km';

  @override
  String get workoutEditErrPace => 'El ritmo debe tener el formato 5:30';

  @override
  String workoutEditSaveError(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return 'CONFIRMADO · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'Comienza ahora';

  @override
  String upcomingEventInMinutes(int count) {
    return 'En $count min';
  }

  @override
  String get upcomingEventInOneHour => 'En 1 hora';

  @override
  String upcomingEventInHours(int count) {
    return 'En $count horas';
  }

  @override
  String get upcomingEventTomorrow => 'Mañana';

  @override
  String upcomingEventInDays(int count) {
    return 'En $count días';
  }

  @override
  String get todaysWorkoutDone => 'HECHO HOY';

  @override
  String get todaysWorkoutToday => 'ENTRENAMIENTO DE HOY';

  @override
  String get errorStateRetry => 'Reintentar';

  @override
  String get shareCardRunTitle => 'Compartir carrera';

  @override
  String get shareCardExport => 'Exportar';

  @override
  String get shareCardImage => 'Imagen';

  @override
  String get shareCardStatDistance => 'Distancia';

  @override
  String get shareCardStatTime => 'Tiempo';

  @override
  String get shareCardStatPace => 'Ritmo';

  @override
  String get shareCardStatSpeed => 'Velocidad';

  @override
  String get shareCardBrandRun => 'RUN';

  @override
  String get shareCardImageError => 'No se pudo crear la imagen para compartir';

  @override
  String get shareCardFileError => 'No se pudo exportar el archivo';

  @override
  String get shareCardRouteTitle => 'Compartir ruta';

  @override
  String get shareCardRouteShareImage => 'Compartir imagen';

  @override
  String get shareCardRouteCapturing => 'Capturando…';

  @override
  String get shareCardRouteStatDistance => 'Distancia';

  @override
  String get shareCardRouteStatClimb => 'Desnivel';

  @override
  String get billingToday => 'hoy';

  @override
  String get billingYesterday => 'ayer';

  @override
  String billingDaysAgo(int count) {
    return 'hace $count días';
  }

  @override
  String billingRenewalFailed(String relative) {
    return 'La renovación Pro falló $relative.';
  }

  @override
  String get billingRenewalBody => 'Actualiza tu tarjeta o pasarás a Free.';

  @override
  String get billingManage => 'Gestionar';

  @override
  String get planCalendarPrevMonth => 'Mes anterior';

  @override
  String get planCalendarNextMonth => 'Mes siguiente';

  @override
  String runGearChipsLoadError(String error) {
    return 'Error al cargar el equipo: $error';
  }

  @override
  String get runGearChipsPickerTitle =>
      'Etiquetar el equipo usado en esta carrera';

  @override
  String get runGearChipsEmpty =>
      'Aún no has registrado ningún equipo. Añade alguno en Ajustes → Equipo.';

  @override
  String get runGearChipsCancel => 'Cancelar';

  @override
  String get runGearChipsSave => 'Guardar';

  @override
  String get runGearChipsTag => '+ Etiquetar equipo';

  @override
  String get runGearChipsEdit => 'Editar';

  @override
  String runGearChipsSaveError(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String get gearFormTitleEdit => 'Editar equipo';

  @override
  String get gearFormTitleAddShoes => 'Añadir zapatillas';

  @override
  String get gearFormTitleAddBike => 'Añadir bicicleta';

  @override
  String get gearFormNameLabel => 'Nombre';

  @override
  String get gearFormNameHint => 'Pegasus 39';

  @override
  String get gearFormBrandLabel => 'Marca';

  @override
  String get gearFormModelLabel => 'Modelo';

  @override
  String get gearFormBoughtLabel => 'Comprado';

  @override
  String get gearFormBoughtPick => 'Toca para elegir';

  @override
  String gearFormRetireAt(String unit) {
    return 'Retirar a los ($unit)';
  }

  @override
  String get gearFormRetireHint => '500';

  @override
  String get gearFormNotesLabel => 'Notas';

  @override
  String get gearFormCancel => 'Cancelar';

  @override
  String get gearFormSaving => 'Guardando…';

  @override
  String get gearFormSave => 'Guardar';

  @override
  String get gearFormAdd => 'Añadir';

  @override
  String gearFormSaveError(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String get gearWearLogHeading => 'Registro de desgaste';

  @override
  String get gearWearLogHint =>
      'Anota cómo envejece este equipo — desgaste de la suela, mediasuela muerta, parte superior deshilachada.';

  @override
  String get gearWearLogEmpty => 'Aún no hay observaciones de desgaste.';

  @override
  String get gearWearLogAddNote => 'Observación';

  @override
  String get gearWearLogNoteHint =>
      'p. ej. tacos de la suela gastados en el talón';

  @override
  String get gearWearLogArea => 'Zona';

  @override
  String get gearWearLogAreaNone => '—';

  @override
  String get gearWearLogAreaOutsole => 'Suela';

  @override
  String get gearWearLogAreaMidsole => 'Mediasuela';

  @override
  String get gearWearLogAreaUpper => 'Parte superior';

  @override
  String get gearWearLogAreaOther => 'Otro';

  @override
  String get gearWearLogAdd => 'Añadir observación';

  @override
  String get gearWearLogAdding => 'Añadiendo…';

  @override
  String get gearWearLogDelete => 'Eliminar observación';

  @override
  String gearWearLogAddError(String error) {
    return 'No se pudo añadir la observación: $error';
  }

  @override
  String gearWearLogDeleteError(String error) {
    return 'No se pudo eliminar la observación: $error';
  }

  @override
  String get notificationBellTooltip => 'Notificaciones';

  @override
  String get liveRunMapWaitingGps => 'Esperando GPS...';

  @override
  String get liveRunMapRecentre => 'Centrar en mi ubicación';

  @override
  String get ttsRunStarted => 'Carrera iniciada';

  @override
  String ttsRunComplete(String distance, int mins) {
    return 'Carrera completada. $distance en $mins minutos.';
  }

  @override
  String get ttsOffRoute => 'Fuera de la ruta';

  @override
  String get ttsPaceAlertFast => 'Acelera el ritmo';

  @override
  String get ttsPaceAlertSlow => 'Reduce la velocidad';

  @override
  String get ttsWorkoutComplete => 'Entrenamiento completado. Buen trabajo.';

  @override
  String get ttsStepHalfway => 'Mitad de esta repetición';

  @override
  String get ttsStepLastFifty => 'Quedan cincuenta metros';

  @override
  String ttsPaceDriftAhead(int delta) {
    return 'Afloja un poco — $delta segundos demasiado rápido.';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return 'Acelera un poco — $delta segundos demasiado lento.';
  }

  @override
  String ttsSpeedKm(String value) {
    return 'Velocidad, $value kilómetros por hora';
  }

  @override
  String ttsSpeedMi(String value) {
    return 'Velocidad, $value millas por hora';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por kilómetro';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por milla';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$value kilómetros';
  }

  @override
  String ttsDistanceMetres(int value) {
    return '$value metros';
  }

  @override
  String ttsDistanceMileSingular(String value) {
    return '$value milla';
  }

  @override
  String ttsDistanceMiles(String value) {
    return '$value millas';
  }

  @override
  String ttsDistanceYards(int value) {
    return '$value yardas';
  }

  @override
  String ttsSplit(String count, String unit, String tail) {
    return '$count $unit. $tail';
  }

  @override
  String get ttsStepWarmup => 'Calentamiento';

  @override
  String get ttsStepRecovery => 'Recuperación';

  @override
  String get ttsStepSteady => 'Ritmo constante';

  @override
  String get ttsStepCooldown => 'Enfriamiento';

  @override
  String get ttsStepRep => 'Repetición';

  @override
  String get ttsStepRun => 'Carrera';

  @override
  String get ttsStepWalk => 'Caminata';

  @override
  String ttsStepRepOf(int index, int total) {
    return 'Repetición $index de $total';
  }

  @override
  String ttsStepRunOf(int index, int total) {
    return 'Carrera $index de $total';
  }

  @override
  String ttsStepWalkOf(int index, int total) {
    return 'Caminata $index de $total';
  }

  @override
  String ttsStepPaceKm(int min, int sec) {
    return '$min minutos $sec segundos por kilómetro';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '$min minutos por kilómetro';
  }

  @override
  String ttsStepPaceMi(int min, int sec) {
    return '$min minutos $sec segundos por milla';
  }

  @override
  String ttsStepPaceMiWhole(int min) {
    return '$min minutos por milla';
  }

  @override
  String ttsDurationSeconds(int sec) {
    return '$sec segundos';
  }

  @override
  String ttsDurationMinutes(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String ttsDurationMinutesSeconds(String minutes, int sec) {
    return '$minutes $sec segundos';
  }

  @override
  String ttsStepDuration(String intro, String duration) {
    return '$intro. $duration.';
  }

  @override
  String ttsStepDistancePace(String intro, String distance, String pace) {
    return '$intro. $distance a $pace.';
  }

  @override
  String get guidedEasy30Title => 'Carrera suave de 30 minutos';

  @override
  String get guidedEasy30Subtitle =>
      'Voz del entrenador · 30 min · esfuerzo suave';

  @override
  String get guidedEasy30Description =>
      'Una carrera relajada a ritmo de conversación, para un día de recuperación o simplemente para despejar la mente. El entrenador interviene cada cinco minutos con un pequeño empujón.';

  @override
  String get guidedEasy30Cue0 =>
      'Vamos. Empieza suave — este es tu ritmo de recuperación.';

  @override
  String get guidedEasy30Cue1 =>
      'Cinco minutos. Relaja los hombros. Mantén el ritmo de conversación.';

  @override
  String get guidedEasy30Cue2 =>
      'Diez minutos. Revisa la cadencia — pies rápidos, pisada ligera.';

  @override
  String get guidedEasy30Cue3 =>
      'Mitad. Aún deberías poder hablar mientras corres.';

  @override
  String get guidedEasy30Cue4 =>
      'Veinte minutos. Fíjate en tu respiración — inhala lento por la nariz, exhala por la boca.';

  @override
  String get guidedEasy30Cue5 =>
      'Quedan cinco minutos. Mantente relajado. No aprietes.';

  @override
  String get guidedEasy30Cue6 => 'Queda un minuto. Termina suave.';

  @override
  String get guidedEasy30Cue7 =>
      'Listo. Camina un minuto para recuperar. Buen trabajo.';

  @override
  String get guidedTempo25Title => 'Constructor de tempo de 25 minutos';

  @override
  String get guidedTempo25Subtitle => 'Voz del entrenador · 25 min · 5-15-5';

  @override
  String get guidedTempo25Description =>
      'Cinco minutos de calentamiento suave, quince minutos a tempo (cómodamente duro), cinco minutos de enfriamiento. La sesión de tempo semanal de toda la vida.';

  @override
  String get guidedTempo25Cue0 =>
      'Hora de calentar. Cinco minutos suaves — despierta las piernas.';

  @override
  String get guidedTempo25Cue1 =>
      'Queda un minuto de calentamiento. Sube la cadencia.';

  @override
  String get guidedTempo25Cue2 =>
      'Sube a tempo. Cómodamente duro. Como un esfuerzo de carrera de 10K.';

  @override
  String get guidedTempo25Cue3 =>
      'Cinco minutos a tempo. Fuerte pero controlado. Mantén el ritmo.';

  @override
  String get guidedTempo25Cue4 =>
      'Diez minutos de tempo hechos. Mantén el ritmo.';

  @override
  String get guidedTempo25Cue5 =>
      'Quedan dos minutos a tempo. Mantente fluido.';

  @override
  String get guidedTempo25Cue6 => 'Afloja. Cinco minutos suaves para enfriar.';

  @override
  String get guidedTempo25Cue7 => 'Quedan dos minutos. Baja las pulsaciones.';

  @override
  String get guidedTempo25Cue8 => 'Listo. Camina y estírate. Gran trabajo.';

  @override
  String get guidedFirst15Title => 'Principiante: 15 minutos correr/caminar';

  @override
  String get guidedFirst15Subtitle =>
      'Voz del entrenador · 15 min · intervalos correr/caminar';

  @override
  String get guidedFirst15Description =>
      '¿Nuevo en la carrera? Tres rondas de un minuto corriendo y un minuto caminando, más un calentamiento y un enfriamiento. Un inicio suave; todos empiezan aquí.';

  @override
  String get guidedFirst15Cue0 =>
      'Empieza con tres minutos de caminata enérgica para calentar.';

  @override
  String get guidedFirst15Cue1 =>
      'Cambia a un minuto de carrera suave. Ritmo de conversación.';

  @override
  String get guidedFirst15Cue2 => 'Camina un minuto.';

  @override
  String get guidedFirst15Cue3 => 'Corre un minuto.';

  @override
  String get guidedFirst15Cue4 => 'Camina un minuto.';

  @override
  String get guidedFirst15Cue5 => 'Corre un minuto.';

  @override
  String get guidedFirst15Cue6 => 'Camina un minuto.';

  @override
  String get guidedFirst15Cue7 => 'Corre un minuto — el último.';

  @override
  String get guidedFirst15Cue8 =>
      'Baja el ritmo a caminata. Cinco minutos de enfriamiento.';

  @override
  String get guidedFirst15Cue9 => 'Queda un minuto. Camina suave.';

  @override
  String get guidedFirst15Cue10 =>
      'Listo. Eso fue una carrera de verdad. Sal a correr otra vez pronto.';

  @override
  String guidedRunMinutesBadge(int minutes) {
    return '$minutes min';
  }

  @override
  String guidedRunCueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count indicaciones en la carrera',
      one: '$count indicación en la carrera',
    );
    return '$_temp0';
  }

  @override
  String get guidedRunFullScript => 'EL GUION COMPLETO';

  @override
  String get guidedRunPreviewCue => 'Escuchar indicación';

  @override
  String guidedRunPreviewError(String error) {
    return 'No se pudo escuchar: $error';
  }

  @override
  String get ttsSplitUnitKilometre => 'kilómetro';

  @override
  String get ttsSplitUnitKilometres => 'kilómetros';

  @override
  String get ttsSplitUnitMile => 'milla';

  @override
  String get ttsSplitUnitMiles => 'millas';

  @override
  String get workoutKindEasy => 'Suave';

  @override
  String get workoutKindLong => 'Tirada larga';

  @override
  String get workoutKindRecovery => 'Recuperación';

  @override
  String get workoutKindTempo => 'Tempo';

  @override
  String get workoutKindInterval => 'Series';

  @override
  String get workoutKindMarathonPace => 'Ritmo de maratón';

  @override
  String get workoutKindWalkRun => 'Caminar-correr';

  @override
  String get workoutKindRace => 'Carrera';

  @override
  String get workoutKindRest => 'Descanso';

  @override
  String get planPhaseBase => 'Base';

  @override
  String get planPhaseBuild => 'Construcción';

  @override
  String get planPhasePeak => 'Pico';

  @override
  String get planPhaseTaper => 'Afinamiento';

  @override
  String get planPhaseRace => 'Semana de carrera';

  @override
  String get runBackgroundLocationNudgeTitle =>
      'Permitir la ubicación todo el tiempo';

  @override
  String get runBackgroundLocationNudgeBody =>
      'Android solo concedió la ubicación mientras la aplicación está abierta. Para una distancia precisa cuando la pantalla está apagada, configura el acceso a la ubicación como «Permitir todo el tiempo» en Ajustes. Puedes empezar de todos modos: la grabación sigue funcionando mientras la aplicación está en pantalla.';

  @override
  String get runBatteryOptHintTitle =>
      'Mantener la grabación activa en segundo plano';

  @override
  String get runBatteryOptHintBody =>
      'Algunos teléfonos (Samsung, Xiaomi, OnePlus y otros) suspenden las aplicaciones para ahorrar batería, lo que puede detener la grabación de una carrera larga cuando la pantalla está apagada. Para mayor seguridad, excluye esta aplicación de la optimización de batería en Ajustes. Tu carrera se grabará de todos modos: esto solo evita que el sistema la interrumpa.';

  @override
  String shareCardCaption(Object title, Object distance, Object duration) {
    return '$title — $distance en $duration';
  }

  @override
  String get settingsBackendNotConfigured => 'Backend no configurado';

  @override
  String get settingsAccountSignedIn => 'Sesión iniciada';

  @override
  String get settingsDevicesSignedOutSubtitle =>
      'Inicia sesión para gestionar tus dispositivos';

  @override
  String get verifiedClubTooltip => 'Club verificado oficial';

  @override
  String get raceDistance5k => '5 km';

  @override
  String get raceDistance10k => '10 km';

  @override
  String get raceDistanceHalfMarathon => 'Media maratón';

  @override
  String get raceDistanceMarathon => 'Maratón';

  @override
  String get settingsTabAccountSubtitle =>
      'Iniciar sesión, copia de seguridad, eliminar cuenta';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Unidades, tema, grabación, entrenamiento, privacidad';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, banda de frecuencia cardíaca';

  @override
  String get settingsTabDevicesSubtitle =>
      'Dónde tienes la sesión iniciada y ajustes por dispositivo';

  @override
  String get settingsTabGearSubtitle =>
      'Registra zapatillas + bicis y el kilometraje por artículo';

  @override
  String get settingsTabCoachingSubtitle =>
      'Entrena a atletas o sigue a tu propio entrenador';

  @override
  String get settingsTabProSubtitle =>
      'Suscríbete, restaura compras, gestiona la facturación';

  @override
  String get settingsTabLicensesSubtitle =>
      'Versión de la app y avisos de código abierto';

  @override
  String periodSummaryWeekOf(Object date) {
    return 'Semana del $date';
  }

  @override
  String periodShareRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carreras',
      one: '1 carrera',
    );
    return '$_temp0';
  }

  @override
  String periodShareAvgPace(Object pace) {
    return 'Ritmo medio: $pace';
  }

  @override
  String get gymTitle => 'Gimnasio';

  @override
  String get gymLog => 'Registrar entrenamiento';

  @override
  String get gymUntitled => 'Entrenamiento sin título';

  @override
  String get gymOfflineCached =>
      'Sin conexión: mostrando entrenamientos guardados';

  @override
  String get gymOfflineQueued =>
      'Sin conexión: los cambios se sincronizarán más tarde';

  @override
  String get gymEmptyTitle => 'Aún no hay entrenamientos de gimnasio';

  @override
  String get gymEmptyBody =>
      'Registra una sesión para seguirla aquí y alimentar tu carga de entrenamiento.';

  @override
  String get gymPrBadge => 'RP';

  @override
  String gymExercisesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ejercicios',
      one: '$count ejercicio',
    );
    return '$_temp0';
  }

  @override
  String gymVolumeShort(int volume) {
    return '$volume kg';
  }

  @override
  String get gymNotFound => 'Entrenamiento no encontrado.';

  @override
  String get gymEdit => 'Editar';

  @override
  String get gymDelete => 'Eliminar';

  @override
  String get gymPublic => 'Público';

  @override
  String get gymPrivate => 'Privado';

  @override
  String get gymMakePublic => 'Hacer público';

  @override
  String get gymMakePrivate => 'Hacer privado';

  @override
  String gymVisibilityFailed(Object error) {
    return 'No se pudo actualizar la visibilidad: $error';
  }

  @override
  String gymDeleteFailed(Object error) {
    return 'No se pudo eliminar el entrenamiento: $error';
  }

  @override
  String get gymNotes => 'Notas';

  @override
  String get gymKg => 'kg';

  @override
  String get gymReps => 'Reps';

  @override
  String get gymRpe => 'RPE';

  @override
  String get gymDuration => 'Tiempo (s)';

  @override
  String gymDurationValue(String seconds) {
    return '${seconds}s';
  }

  @override
  String gymSetN(int n) {
    return 'Serie $n';
  }

  @override
  String get gymPrWeight => 'Más pesada';

  @override
  String get gymPrVolume => 'Mejor volumen';

  @override
  String get gymPrE1rm => 'Mejor 1RM est.';

  @override
  String get gymRecordsLink => 'Récords';

  @override
  String get gymRecordsTitle => 'Récords personales';

  @override
  String get gymRecordsSubtitle => 'Tu mejor marca en cada ejercicio con peso.';

  @override
  String get gymRecordsEmpty =>
      'Aún no hay ejercicios con peso registrados. Añade un peso a una serie para empezar a seguir tus récords.';

  @override
  String gymRecordsLastDone(String date) {
    return 'Último $date';
  }

  @override
  String gymRecordsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones',
      one: '1 sesión',
    );
    return '$_temp0';
  }

  @override
  String get gymExerciseBack => 'Volver a récords';

  @override
  String get gymExerciseEmpty => 'Aún no hay historial de este ejercicio.';

  @override
  String gymSinceFirstUp(String delta) {
    return '+$delta desde la primera sesión';
  }

  @override
  String gymSinceFirstDown(String delta) {
    return '−$delta desde la primera sesión';
  }

  @override
  String get gymSinceFirstFlat => 'sin cambios desde la primera sesión';

  @override
  String gymDetailLastTime(String date) {
    return 'Última vez $date';
  }

  @override
  String get gymVolumeLabel => 'Volumen';

  @override
  String get gymDeleteConfirmTitle => '¿Eliminar entrenamiento?';

  @override
  String get gymDeleteConfirmBody =>
      'Esto elimina permanentemente el entrenamiento y sus series.';

  @override
  String get clubEventMembersOnly => 'Solo miembros';

  @override
  String get clubEventLogAsWorkout => 'Registrar como entrenamiento';

  @override
  String get clubEventLogAsWorkoutHint =>
      'Añade esta clase a tu propio registro de gimnasio — puedes ajustar los detalles antes de guardar.';

  @override
  String get clubEventLogAsWorkoutSaved => 'Añadido a tu registro de gimnasio';

  @override
  String get clubEventDownloadCertificate => 'Certificado de finalista';

  @override
  String get clubEventCertificateShare => 'Guardar o compartir';

  @override
  String clubEventCertificateShareText(String event) {
    return '¡Terminé $event!';
  }

  @override
  String get clubEventCertificateFailed =>
      'No se pudo generar el certificado. Inténtalo de nuevo.';

  @override
  String get clubEventCertificateHeading => 'Certificado de finalización';

  @override
  String get clubEventCertificateCertifies => 'Esto certifica que';

  @override
  String get clubEventCertificateCompleted => 'completó';

  @override
  String get clubEventCertificateTime => 'Tiempo';

  @override
  String get clubEventCertificateDistance => 'Distancia';

  @override
  String clubEventCertificatePlace(String place) {
    return '$place puesto';
  }

  @override
  String get gymEditorNewTitle => 'Nuevo entrenamiento';

  @override
  String get gymEditorEditTitle => 'Editar entrenamiento';

  @override
  String get gymEditorTitleLabel => 'Título (opcional)';

  @override
  String get gymEditorTitlePlaceholder => 'p. ej. Día de empuje';

  @override
  String get gymEditorExercisePlaceholder => 'Nombre del ejercicio';

  @override
  String get gymEditorRemoveExercise => 'Eliminar ejercicio';

  @override
  String get gymEditorRemoveSet => 'Eliminar serie';

  @override
  String get gymEditorAddSet => 'Añadir serie';

  @override
  String get gymEditorAddExercise => 'Añadir ejercicio';

  @override
  String get gymEditorShare => 'Compartir en el feed';

  @override
  String get gymEditorCancel => 'Cancelar';

  @override
  String get gymEditorSave => 'Guardar entrenamiento';

  @override
  String get gymEditorNeedExercise => 'Añade al menos un ejercicio con nombre.';

  @override
  String get gymCatalogueBrowse => 'Explorar catálogo';

  @override
  String get gymCatalogueTitle => 'Catálogo de ejercicios';

  @override
  String get gymCatalogueSearchPlaceholder => 'Buscar ejercicios';

  @override
  String get gymCatalogueCategoryLabel => 'Categoría';

  @override
  String get gymCatalogueEmpty => 'Ningún ejercicio coincide.';

  @override
  String get gymCatalogueCustomBadge => 'Personalizado';

  @override
  String gymCatalogueCreate(String name) {
    return 'Añadir «$name» como ejercicio personalizado';
  }

  @override
  String get gymCatalogueCreateFailed => 'No se pudo añadir ese ejercicio.';

  @override
  String get gymCatalogueCategoryAll => 'Todas';

  @override
  String get gymCatalogueCategoryChest => 'Pecho';

  @override
  String get gymCatalogueCategoryBack => 'Espalda';

  @override
  String get gymCatalogueCategoryShoulders => 'Hombros';

  @override
  String get gymCatalogueCategoryLegs => 'Piernas';

  @override
  String get gymCatalogueCategoryArms => 'Brazos';

  @override
  String get gymCatalogueCategoryCore => 'Core';

  @override
  String get gymCatalogueCategoryCardio => 'Cardio';

  @override
  String get gymCatalogueCategoryFullBody => 'Cuerpo completo';

  @override
  String get gymCatalogueCategoryOther => 'Otros';

  @override
  String get gymSaveFailed => 'No se pudo guardar el entrenamiento.';

  @override
  String get gymRoutineLink => 'Rutinas';

  @override
  String get gymRoutineTitle => 'Rutinas';

  @override
  String get gymRoutineNew => 'Nueva rutina';

  @override
  String get gymRoutineBack => 'Volver a rutinas';

  @override
  String get gymRoutineNotFound => 'Rutina no encontrada.';

  @override
  String gymRoutineExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ejercicios',
      one: '$count ejercicio',
    );
    return '$_temp0';
  }

  @override
  String get gymRoutineStart => 'Iniciar rutina';

  @override
  String get gymRoutinePublishLabel => 'Publicar en un club';

  @override
  String get gymRoutinePublishPick => 'Elige un club…';

  @override
  String get gymRoutinePublish => 'Publicar';

  @override
  String get gymRoutinePublishSuccess => 'Rutina publicada en el club.';

  @override
  String get gymRoutinePublishFailed => 'No se pudo publicar la rutina.';

  @override
  String get gymRoutineClubTemplateBadge => 'Plantilla del club';

  @override
  String get gymRoutinePublicBadge => 'En la biblioteca pública';

  @override
  String get gymRoutinePublishPublicLabel => 'Biblioteca pública';

  @override
  String get gymRoutinePublishPublic => 'Publicar en la biblioteca pública';

  @override
  String get gymRoutineUnpublishPublic => 'Quitar de la biblioteca pública';

  @override
  String get gymRoutinePublishPublicHint =>
      'Cualquier persona con sesión iniciada puede ver y adoptar esta rutina. Los entrenamientos registrados siguen siendo privados.';

  @override
  String get gymRoutinePublishPublicSuccess =>
      'Rutina publicada en la biblioteca pública.';

  @override
  String get gymRoutineUnpublishPublicSuccess =>
      'Rutina quitada de la biblioteca pública.';

  @override
  String get gymRoutinePublishPublicFailed =>
      'No se pudo cambiar la visibilidad pública.';

  @override
  String get gymLibraryLink => 'Biblioteca';

  @override
  String get gymLibraryTitle => 'Biblioteca pública de rutinas';

  @override
  String get gymLibrarySearchHint => 'Buscar rutinas por nombre';

  @override
  String get gymLibraryLoadError => 'No se pudo cargar la biblioteca.';

  @override
  String get gymLibraryEmpty => 'Aún no hay rutinas publicadas.';

  @override
  String gymLibraryEmptySearch(String query) {
    return 'Ninguna rutina coincide con \"$query\".';
  }

  @override
  String gymLibraryByAuthor(String author) {
    return 'por $author';
  }

  @override
  String get gymLibraryAnonymous => 'un usuario';

  @override
  String get gymLibraryAdopt => 'Adoptar en mis rutinas';

  @override
  String get gymLibraryAdopting => 'Adoptando…';

  @override
  String get gymLibraryAdoptFailed => 'No se pudo adoptar la rutina.';

  @override
  String get gymRoutineDelete => 'Eliminar';

  @override
  String get gymRoutineDeleteConfirmTitle => '¿Eliminar rutina?';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'Esto elimina la rutina de forma permanente. Los entrenamientos registrados no se ven afectados.';

  @override
  String get gymRoutineDeleted => 'Rutina eliminada';

  @override
  String get gymRoutineCreated => 'Rutina guardada';

  @override
  String get gymRoutineSaveFailed => 'No se pudo guardar la rutina.';

  @override
  String get gymRoutineEmptyTitle => 'Aún no hay rutinas';

  @override
  String get gymRoutineEmptyBody =>
      'Guarda un entrenamiento registrado como rutina, o crea una, para reutilizarla.';

  @override
  String get gymRoutineTargetReps => 'Repeticiones objetivo';

  @override
  String gymRoutineTargetWeight(String unit) {
    return 'Peso objetivo ($unit)';
  }

  @override
  String get gymRoutineEditorNewTitle => 'Nueva rutina';

  @override
  String get gymRoutineEditorTitleLabel => 'Nombre de la rutina';

  @override
  String get gymRoutineEditorTitlePlaceholder => 'p. ej. Día de empuje A';

  @override
  String get gymRoutineEditorNotesLabel => 'Notas (opcional)';

  @override
  String get gymRoutineEditorSave => 'Guardar rutina';

  @override
  String get gymRoutineEditorCancel => 'Cancelar';

  @override
  String get gymRoutineEditorNeedTitle => 'Ponle un nombre a la rutina.';

  @override
  String get gymRoutineEditorNeedExercise =>
      'Añade al menos un ejercicio con nombre.';

  @override
  String get gymRoutineSaveAsRoutine => 'Guardar como rutina';

  @override
  String get gymRoutineRepeatLast => 'Repetir el último';

  @override
  String get gymRoutineTargetRepsMax => 'a';

  @override
  String get gymRoutineTargetDuration => 'Tiempo objetivo (s)';

  @override
  String get gymRoutineTargetDistance => 'Distancia objetivo (m)';

  @override
  String get gymRoutineRestLabel => 'Descanso (s)';

  @override
  String get gymRoutineSetType => 'Tipo de serie';

  @override
  String get gymRoutineSetTypeWarmup => 'Calentamiento';

  @override
  String get gymRoutineSetTypeWorking => 'Serie de trabajo';

  @override
  String get gymRoutineSetTypeDropset => 'Drop set';

  @override
  String get gymRoutineSetTypeAmrap => 'AMRAP';

  @override
  String get gymRoutineSetTypeFailure => 'Al fallo';

  @override
  String get gymRoutineSetTypeBackoff => 'Back-off';

  @override
  String get gymRoutineModality => 'Medido por';

  @override
  String get gymRoutineModalityWeightReps => 'Peso × reps';

  @override
  String get gymRoutineModalityTime => 'Tiempo';

  @override
  String get gymRoutineModalityDistance => 'Distancia';

  @override
  String get gymRoutineModalityBodyweightReps => 'Reps con peso corporal';

  @override
  String get gymRoutineSupersetToggle =>
      'Superserie con el siguiente ejercicio';

  @override
  String gymRoutineSupersetBadge(int group) {
    return 'Superserie $group';
  }

  @override
  String get gymRoutineAdvanced => 'Avanzado';

  @override
  String get gymRoutineProgression => 'Progresión';

  @override
  String get gymRoutineProgressionNone => 'Ninguna';

  @override
  String get gymRoutineProgressionLinear => 'Lineal';

  @override
  String get gymRoutineProgressionDoubleProgression => 'Doble progresión';

  @override
  String get gymRoutineProgressionFiveByFive => '5×5';

  @override
  String get gymRoutineProgressionPercentCycle => 'Ciclo % de 1RM';

  @override
  String get gymRoutineProgressionRpeAutoreg => 'Autorregulación RPE';

  @override
  String gymRoutineProgressionIncrementLabel(String unit) {
    return 'Paso de peso ($unit)';
  }

  @override
  String get gymRoutineProgressionPercentLabel => '% de 1RM';

  @override
  String gymRoutineProgressionOneRmLabel(String unit) {
    return '1RM ($unit)';
  }

  @override
  String get gymRoutineProgressionTargetRpeLabel => 'RPE objetivo';

  @override
  String get gymRoutineNextTarget => 'Próximo objetivo';

  @override
  String get gymRoutineNextTargetIncreaseWeight => 'Subir carga la próxima vez';

  @override
  String get gymRoutineNextTargetIncreaseReps =>
      'Subir repeticiones la próxima vez';

  @override
  String get gymRoutineNextTargetHold => 'Mantener — repetir este objetivo';

  @override
  String get gymRoutineNextTargetEstablishBaseline =>
      'Establecer base — fija el peso inicial';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — reducir la carga';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'subida de reps $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrición';

  @override
  String get nutritionLogFood => 'Registrar comida';

  @override
  String get nutritionCalories => 'Calorías';

  @override
  String get nutritionProtein => 'Proteínas';

  @override
  String get nutritionCarbs => 'Carbohidratos';

  @override
  String get nutritionFat => 'Grasas';

  @override
  String get nutritionWater => 'Agua';

  @override
  String get nutritionWaterAdd => 'Añadir agua';

  @override
  String get nutritionWaterRemove => 'Quitar agua';

  @override
  String get nutritionNoTargets =>
      'Añade tu altura, peso, edad y sexo en la app web para ver los objetivos de calorías y macros.';

  @override
  String get nutritionWeeklyTrend => 'Últimos 7 días';

  @override
  String nutritionCaloriesLeft(int n) {
    return '$n kcal restantes';
  }

  @override
  String nutritionCaloriesOver(int n) {
    return '$n kcal de más';
  }

  @override
  String get nutritionOnTarget => 'En el objetivo';

  @override
  String nutritionMacroOver(int n) {
    return '$n por encima del objetivo';
  }

  @override
  String get nutritionMacroReached => 'Objetivo alcanzado';

  @override
  String nutritionWaterAmount(String consumed, String target) {
    return '$consumed / $target L';
  }

  @override
  String get nutritionWaterGoalReached => 'Objetivo alcanzado';

  @override
  String nutritionWaterRemaining(int n) {
    return '$n ml restantes';
  }

  @override
  String get nutritionWeekOnGoal => 'En el objetivo';

  @override
  String nutritionWeekUnderGoal(int n) {
    return '$n bajo el objetivo/día';
  }

  @override
  String nutritionWeekOverGoal(int n) {
    return '$n sobre el objetivo/día';
  }

  @override
  String nutritionWeekProtein(int met, int total) {
    return 'Proteína $met/$total días';
  }

  @override
  String get nutritionGoalLine => 'Objetivo diario';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return 'Meta $base + $exercise kcal quemadas hoy';
  }

  @override
  String get dashGymReadinessIncluded =>
      'Tus sesiones de gimnasio recientes se incluyen en tu fatiga.';

  @override
  String get dashGymReadinessExcluded =>
      'La carga del gimnasio se excluye de tu preparación para correr.';

  @override
  String get prefsExcludeGymFromReadiness =>
      'Excluir la carga del gimnasio de la preparación para correr';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'De forma predeterminada, las sesiones de gimnasio aumentan tu fatiga y reducen tu preparación, igual que una carrera. Actívalo para que tu forma, fatiga y frescura se basen solo en las carreras.';

  @override
  String get nutritionEmptyTitle => 'Aún no has registrado comida hoy';

  @override
  String get nutritionEmptyBody =>
      'Registra una comida para controlar tus calorías y macros.';

  @override
  String get nutritionSlotBreakfast => 'Desayuno';

  @override
  String get nutritionSlotLunch => 'Almuerzo';

  @override
  String get nutritionSlotDinner => 'Cena';

  @override
  String get nutritionSlotSnack => 'Tentempié';

  @override
  String get nutritionMealProtein => 'Proteínas';

  @override
  String get nutritionMealCarbs => 'Carbohidratos';

  @override
  String get nutritionMealFat => 'Grasas';

  @override
  String get nutritionMealItemsHeading => 'Alimentos';

  @override
  String get nutritionMealNoItems => 'Nada registrado para esta comida.';

  @override
  String get nutritionMealTrendHeading => 'Últimos 7 días';

  @override
  String get nutritionDelete => 'Eliminar';

  @override
  String get nutritionDeleteEntryTitle => '¿Eliminar esta entrada?';

  @override
  String nutritionDeleteEntryMessage(String item) {
    return '$item se eliminará del registro de hoy.';
  }

  @override
  String nutritionDeleteFailed(String error) {
    return 'No se pudo eliminar la entrada: $error';
  }

  @override
  String get nutritionOfflineQueued =>
      'Sin conexión: los cambios se sincronizarán al reconectar';

  @override
  String get nutritionOfflineCached =>
      'Sin conexión: mostrando entradas guardadas';

  @override
  String get nutritionLogTitle => 'Registrar comida';

  @override
  String get nutritionSearchHint => 'Busca un alimento';

  @override
  String get nutritionSearching => 'Buscando…';

  @override
  String get nutritionNoResults =>
      'Sin coincidencias. Prueba otro término o introdúcelo manualmente abajo.';

  @override
  String get nutritionSearchFailed =>
      'La búsqueda falló. Comprueba tu conexión y vuelve a intentarlo o introdúcelo manualmente abajo.';

  @override
  String get nutritionSearchRetry => 'Reintentar búsqueda';

  @override
  String get nutritionSourceOff => 'Open Food Facts';

  @override
  String get nutritionSourceUsda => 'USDA';

  @override
  String get nutritionScanBarcode => 'Escanear código de barras';

  @override
  String get nutritionScanHint =>
      'Apunta la cámara a un código de barras de producto';

  @override
  String get nutritionScanLookingUp => 'Buscando…';

  @override
  String get nutritionScanNotFound =>
      'No se encontró ningún producto para ese código de barras. Busca o introdúcelo manualmente.';

  @override
  String get nutritionScanFailed =>
      'Error al escanear. Busca o introdúcelo manualmente.';

  @override
  String get nutritionScanPermissionDenied =>
      'Se necesita acceso a la cámara para escanear un código de barras. Aún puedes buscar o introducir la comida manualmente.';

  @override
  String get nutritionScanOpenSettings => 'Abrir ajustes';

  @override
  String get nutritionSaveFailed =>
      'No se pudo registrar la comida. Inténtalo de nuevo.';

  @override
  String get nutritionMealSlot => 'Comida';

  @override
  String get nutritionManualEntry => 'Introducir manualmente';

  @override
  String get nutritionItemName => 'Nombre del alimento';

  @override
  String get nutritionPortionGrams => 'Porción (g)';

  @override
  String get nutritionAdd => 'Añadir';

  @override
  String get nutritionCancel => 'Cancelar';

  @override
  String get nutritionTemplates => 'Plantillas de comida';

  @override
  String get nutritionSaveAsMeal => 'Guardar como comida';

  @override
  String get nutritionSaveAsMealTitle => 'Guardar como plantilla de comida';

  @override
  String get nutritionTemplateName => 'Nombre de la plantilla';

  @override
  String get nutritionTemplateNamePlaceholder =>
      'p. ej. Desayuno antes de correr';

  @override
  String get nutritionSaveTemplate => 'Guardar comida';

  @override
  String get nutritionTemplateSaved => 'Plantilla de comida guardada.';

  @override
  String nutritionTemplateSaveFailed(String error) {
    return 'No se pudo guardar la plantilla: $error';
  }

  @override
  String get nutritionLogTemplate => 'Registrar';

  @override
  String nutritionTemplateLogged(int n, String name) {
    return 'Se registraron $n elementos de $name.';
  }

  @override
  String nutritionTemplateLogFailed(String error) {
    return 'No se pudo registrar la plantilla: $error';
  }

  @override
  String nutritionTemplateDeleteFailed(String error) {
    return 'No se pudo eliminar la plantilla: $error';
  }

  @override
  String nutritionTemplateItems(int n) {
    return '$n elementos';
  }

  @override
  String get nutritionDeleteTemplate => 'Eliminar';

  @override
  String get nutritionDeleteTemplateTitle =>
      '¿Eliminar esta plantilla de comida?';

  @override
  String nutritionDeleteTemplateMessage(String name) {
    return '$name se eliminará. Las comidas ya registradas a partir de ella permanecen en tu diario.';
  }

  @override
  String get nutritionRecipes => 'Recetas';

  @override
  String get nutritionSaveAsRecipe => 'Guardar como receta';

  @override
  String get nutritionSaveAsRecipeTitle => 'Guardar como receta';

  @override
  String get nutritionRecipeName => 'Nombre de la receta';

  @override
  String get nutritionRecipeNamePlaceholder => 'p. ej. Bol de pollo y arroz';

  @override
  String get nutritionRecipeServings => 'Raciones';

  @override
  String get nutritionRecipeServingsHint =>
      'Los ingredientes se suman y luego se dividen entre las raciones. Registrar una ración añade una sola entrada con los macros combinados.';

  @override
  String get nutritionSaveRecipe => 'Guardar receta';

  @override
  String get nutritionRecipeSaved => 'Receta guardada.';

  @override
  String nutritionRecipeSaveFailed(String error) {
    return 'No se pudo guardar la receta: $error';
  }

  @override
  String get nutritionLogRecipe => 'Registrar';

  @override
  String nutritionRecipeLogged(int n, String name) {
    return '$name registrada ($n ración).';
  }

  @override
  String nutritionRecipeLogFailed(String error) {
    return 'No se pudo registrar la receta: $error';
  }

  @override
  String nutritionRecipeDeleteFailed(String error) {
    return 'No se pudo eliminar la receta: $error';
  }

  @override
  String nutritionRecipeMeta(int n, num servings) {
    final intl.NumberFormat servingsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String servingsString = servingsNumberFormat.format(servings);

    return '$n ingredientes · $servingsString raciones';
  }

  @override
  String get nutritionDeleteRecipe => 'Eliminar';

  @override
  String get nutritionDeleteRecipeTitle => '¿Eliminar esta receta?';

  @override
  String nutritionDeleteRecipeMessage(String name) {
    return '$name se eliminará. Las comidas ya registradas a partir de ella permanecen en tu diario.';
  }

  @override
  String get sessionTitle => 'Sesiones';

  @override
  String get sessionEmpty => 'Aún no hay planes de sesión.';

  @override
  String get sessionEmptyHint =>
      'Crea en la web una secuencia reutilizable de yoga, pilates o clase.';

  @override
  String get sessionUntitled => 'Sesión sin título';

  @override
  String get sessionNotFound => 'Plan de sesión no encontrado.';

  @override
  String get sessionMakePublic => 'Hacer público';

  @override
  String get sessionMakePrivate => 'Hacer privado';

  @override
  String get sessionVisibilityError => 'No se pudo cambiar la visibilidad.';

  @override
  String get sessionSteps => 'Secuencia';

  @override
  String sessionStepHold(Object name, Object seconds) {
    return '$name · mantener ${seconds}s';
  }

  @override
  String sessionStepReps(Object name, Object reps) {
    return '$name · $reps reps.';
  }

  @override
  String sessionStepFlow(Object name, Object seconds) {
    return '$name · flujo ${seconds}s';
  }

  @override
  String sessionSideLeft(Object name) {
    return '$name (izquierda)';
  }

  @override
  String sessionSideRight(Object name) {
    return '$name (derecha)';
  }

  @override
  String sessionEstDuration(Object minutes) {
    return '~ $minutes min';
  }

  @override
  String get gymSessionStart => 'Iniciar sesión';

  @override
  String gymSessionStep(Object exercise, Object set, Object total) {
    return '$exercise · serie $set de $total';
  }

  @override
  String get gymSessionComplete => 'Sesión completada';

  @override
  String get gymSessionSkipSet => 'Saltar serie';

  @override
  String get gymSessionRewind => 'Anterior';

  @override
  String get gymSessionAbandon => 'Abandonar';

  @override
  String get gymSessionFinish => 'Finalizar';

  @override
  String get gymSessionDiscardTitle => '¿Descartar la sesión?';

  @override
  String get gymSessionDiscardBody =>
      'No se guardará tu progreso en esta sesión.';

  @override
  String get gymSessionDiscardConfirm => 'Descartar';

  @override
  String get gymSessionSaved => 'Entrenamiento guardado';

  @override
  String get gymSessionSaveFailed => 'No se pudo guardar el entrenamiento';

  @override
  String gymSessionSetProgress(Object done, Object total) {
    return '$done/$total';
  }

  @override
  String get gymSessionLogSet => 'Completar serie';

  @override
  String get gymSessionRest => 'Descanso';

  @override
  String gymSessionRestRemaining(Object seconds) {
    return 'Descanso ${seconds}s';
  }

  @override
  String get gymSessionRestSkip => 'Saltar descanso';

  @override
  String get gymSessionTarget => 'Objetivo';

  @override
  String gymReviewAdherence(Object pct) {
    return '$pct% de cumplimiento';
  }

  @override
  String get gymReviewVerdictCompleted => 'Completada';

  @override
  String get gymReviewVerdictPartial => 'Parcialmente hecha';

  @override
  String get gymReviewVerdictAbandoned => 'Abandonada';

  @override
  String get gymReviewStatusHit => 'Logrado';

  @override
  String get gymReviewStatusPartial => 'Parcial';

  @override
  String get gymReviewStatusMissed => 'Fallado';

  @override
  String get gymReviewStatusExtra => 'Extra';

  @override
  String get sessionRunStart => 'Iniciar sesión';

  @override
  String sessionRunStep(Object name) {
    return '$name';
  }

  @override
  String get sessionRunDone => 'Hecho';

  @override
  String get sessionRunSkip => 'Saltar';

  @override
  String get sessionRunPause => 'Pausar';

  @override
  String get sessionRunResume => 'Reanudar';

  @override
  String get sessionRunAbandon => 'Abandonar';

  @override
  String get sessionRunFinish => 'Finalizar';

  @override
  String sessionRunRemaining(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get sessionRunComplete => 'Sesión completada';

  @override
  String get sessionRunSaved => 'Sesión guardada';

  @override
  String get sessionRunSaveFailed => 'No se pudo guardar la sesión';

  @override
  String get sessionRunDiscardTitle => '¿Descartar la sesión?';

  @override
  String get sessionRunDiscardBody =>
      'No se guardará tu progreso en esta sesión.';

  @override
  String get sessionRunDiscardConfirm => 'Descartar';

  @override
  String get sessionRunVerdictCompleted => 'Completada';

  @override
  String get sessionRunVerdictPartial => 'Parcialmente hecha';

  @override
  String get sessionRunVerdictAbandoned => 'Abandonada';

  @override
  String sessionRunStepCount(int index, int total) {
    return 'Paso $index de $total';
  }

  @override
  String get sessionRunSwitchSides => 'Cambia de lado';

  @override
  String get coachingTitle => 'Entrenamiento';

  @override
  String get coachingLede =>
      'Entrena a atletas compartiendo un enlace de invitación y revisa su preparación. O sigue aquí a tu propio entrenador.';

  @override
  String get coachingCancel => 'Cancelar';

  @override
  String get coachingMyAthletes => 'Mis atletas';

  @override
  String get coachingMyAthletesSub => 'Corredores que aceptaron tu invitación';

  @override
  String get coachingInviteAnAthlete => 'Invitar a un atleta';

  @override
  String get coachingCreating => 'Creando…';

  @override
  String get coachingPendingInvite => 'Invitación pendiente';

  @override
  String coachingPendingInviteSub(String date) {
    return 'Creada el $date · aún sin aceptar';
  }

  @override
  String get coachingCopyLink => 'Copiar enlace';

  @override
  String get coachingShareLink => 'Compartir enlace';

  @override
  String get coachingRevoke => 'Revocar';

  @override
  String get coachingNoAthletes =>
      'Aún no hay atletas. Invita a uno para empezar.';

  @override
  String get coachingRosterTitle => 'Lista de atletas';

  @override
  String get coachingRosterSubtitle =>
      'Todos tus atletas de un vistazo: carga, cumplimiento del plan y riesgo de lesión.';

  @override
  String get coachingRosterNeverRun => 'Sin carreras todavía';

  @override
  String get coachingRosterNoPlan => 'Sin plan';

  @override
  String get coachingRosterRiskInsufficient => 'Nuevo';

  @override
  String get coachingRosterRiskLow => 'Bajo';

  @override
  String get coachingRosterRiskOptimal => 'Óptimo';

  @override
  String get coachingRosterRiskElevated => 'Elevado';

  @override
  String get coachingRosterRiskHigh => 'Alto';

  @override
  String get coachingRunner => 'Corredor';

  @override
  String coachingCoachingSince(String date) {
    return 'Entrenando desde el $date';
  }

  @override
  String get coachingReview => 'Revisar';

  @override
  String get coachingRemove => 'Quitar';

  @override
  String get coachingMyCoaches => 'Mis entrenadores';

  @override
  String get coachingMyCoachesSub =>
      'Entrenadores que pueden ver tu preparación';

  @override
  String get coachingNoCoaches =>
      'Todavía no has aceptado la invitación de un entrenador.';

  @override
  String get coachingCoach => 'Entrenador';

  @override
  String coachingLinkedSince(String date) {
    return 'Vinculado desde el $date';
  }

  @override
  String get coachingLeave => 'Salir';

  @override
  String get coachingInviteLinkCopied => 'Enlace de invitación copiado';

  @override
  String get coachingThisAthlete => 'este atleta';

  @override
  String get coachingThisCoach => 'este entrenador';

  @override
  String get coachingRevokeTitle => '¿Revocar invitación?';

  @override
  String get coachingRevokeBody =>
      'El enlace de invitación dejará de funcionar. Siempre puedes crear uno nuevo.';

  @override
  String get coachingRemoveAthleteTitle => '¿Quitar atleta?';

  @override
  String coachingRemoveAthleteBody(String name) {
    return '¿Dejar de entrenar a $name? Perderás el acceso a sus carreras y planes.';
  }

  @override
  String get coachingLeaveCoachTitle => '¿Salir del entrenador?';

  @override
  String coachingLeaveCoachBody(String name) {
    return '¿Dejar de compartir tu preparación con $name?';
  }

  @override
  String coachingLoadError(String error) {
    return 'No se pudo cargar el entrenamiento: $error';
  }

  @override
  String coachingCreateInviteError(String error) {
    return 'No se pudo crear la invitación: $error';
  }

  @override
  String coachingRevokeInviteError(String error) {
    return 'No se pudo revocar la invitación: $error';
  }

  @override
  String coachingRemoveAthleteError(String error) {
    return 'No se pudo quitar al atleta: $error';
  }

  @override
  String coachingEndLinkError(String error) {
    return 'No se pudo finalizar el vínculo: $error';
  }

  @override
  String get coachingAthleteAthleteFallback => 'Atleta';

  @override
  String get coachingAthleteRunnerFallback => 'Corredor';

  @override
  String coachingAthleteCoachingSince(String date) {
    return 'Entrenando desde el $date';
  }

  @override
  String get coachingAthletePlanCompliance => 'Cumplimiento del plan';

  @override
  String get coachingAthleteNoActivePlan => 'Sin plan de entrenamiento activo.';

  @override
  String get coachingAthleteAssignTitle => 'Asignar un plan';

  @override
  String coachingAthleteAssignHint(String name) {
    return 'Elige uno de tus planes para asignárselo a $name.';
  }

  @override
  String get coachingAthleteAssignSelectLabel => 'Plan';

  @override
  String get coachingAthleteAssignSelectPlaceholder => 'Elige un plan…';

  @override
  String get coachingAthleteAssignStartLabel => 'Fecha de inicio';

  @override
  String get coachingAthleteAssigning => 'Asignando…';

  @override
  String get coachingAthleteAssignButton => 'Asignar plan';

  @override
  String get coachingAthleteAssignNoPlans =>
      'Crea primero un plan de entrenamiento y luego podrás asignarlo a tus atletas.';

  @override
  String get coachingAthleteAssignedByYou => 'Asignado por ti';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'Este atleta ya tiene un plan activo. Tendrá que terminarlo o finalizarlo antes de que puedas asignar uno nuevo.';

  @override
  String get coachingAthleteComplete => 'completado';

  @override
  String coachingAthleteDoneCount(int done, int total) {
    return '$done de $total hechos';
  }

  @override
  String coachingAthleteMissedCount(int n) {
    return '$n perdidos';
  }

  @override
  String get coachingAthleteStatusDone => 'Hecho';

  @override
  String get coachingAthleteStatusMissed => 'Perdido';

  @override
  String get coachingAthleteStatusUpcoming => 'Próximo';

  @override
  String get coachingAthleteRecentRuns => 'Carreras recientes';

  @override
  String get coachingAthleteNoRunsYet => 'Aún no hay carreras registradas.';

  @override
  String get coachingAthletePrivate => 'Privado';

  @override
  String coachingAthleteAssignSuccess(String name) {
    return 'Plan asignado a $name';
  }

  @override
  String coachingAthleteLoadError(String error) {
    return 'No se pudo cargar el atleta: $error';
  }

  @override
  String get routeMarkerHeading => 'Marcadores de ruta';

  @override
  String get routeMarkerAdd => 'Añadir marcador';

  @override
  String get routeMarkerEmpty =>
      'Aún no hay marcadores. Añade avituallamientos, cortes de tiempo y más a lo largo de la ruta.';

  @override
  String get routeMarkerEdit => 'Editar marcador';

  @override
  String get routeMarkerDelete => 'Eliminar';

  @override
  String get routeMarkerCancel => 'Cancelar';

  @override
  String get routeMarkerSave => 'Guardar';

  @override
  String get routeMarkerSaving => 'Guardando…';

  @override
  String get routeMarkerKindLabel => 'Tipo';

  @override
  String get routeMarkerNameLabel => 'Nombre';

  @override
  String get routeMarkerNamePlaceholder => 'p. ej. Avituallamiento 2';

  @override
  String get routeMarkerServicesLabel => 'Servicios';

  @override
  String get routeMarkerCutoffLabel => 'Hora de corte';

  @override
  String get routeMarkerNoteLabel => 'Nota';

  @override
  String get routeMarkerTapToPlace =>
      'Toca el mapa para colocar este marcador.';

  @override
  String get routeMarkerSnapToggle => 'Ajustar a la línea de la ruta';

  @override
  String get routeMarkerPlaced =>
      'Colocado. Toca de nuevo el mapa para moverlo.';

  @override
  String routeMarkerCutoffAt(String time) {
    return 'Corte $time';
  }

  @override
  String get routeMarkerLabelRequired => 'Ponle un nombre al marcador.';

  @override
  String get routeMarkerPlaceRequired =>
      'Primero coloca el marcador en el mapa.';

  @override
  String get routeMarkerLatLabel => 'Latitud';

  @override
  String get routeMarkerLngLabel => 'Longitud';

  @override
  String get routeMarkerCoordInvalid =>
      'Introduce una latitud válida (-90 a 90) y una longitud válida (-180 a 180).';

  @override
  String get routeMarkerEnterCoords => 'Introducir coordenadas en su lugar';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'No se pudo guardar el marcador: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'No se pudo eliminar el marcador: $error';
  }

  @override
  String get routeMarkerDeleteConfirmTitle => '¿Eliminar marcador?';

  @override
  String get routeMarkerDeleteConfirmMessage =>
      'Esto elimina el marcador de la ruta de forma permanente.';

  @override
  String get routeMarkerKindAidStation => 'Avituallamiento';

  @override
  String get routeMarkerKindCutoff => 'Corte de tiempo';

  @override
  String get routeMarkerKindCrewAccess => 'Equipo / aparcamiento';

  @override
  String get routeMarkerKindHazard => 'Peligro';

  @override
  String get routeMarkerKindNote => 'Nota';

  @override
  String get routeMarkerKindClimb => 'Subida';

  @override
  String get routeMarkerKindCustom => 'Personalizado';

  @override
  String get routeMarkerServiceWater => 'Agua';

  @override
  String get routeMarkerServiceFood => 'Comida';

  @override
  String get routeMarkerServiceMedical => 'Médico';

  @override
  String get routeMarkerServiceToilets => 'Aseos';

  @override
  String get routeMarkerServiceDropBag => 'Bolsa de avituallamiento';

  @override
  String get clubFormEditTitle => 'Editar club';

  @override
  String get clubEditorWebsite => 'Sitio web';

  @override
  String get clubEditorInstagram => 'Instagram';

  @override
  String get clubEditorStrava => 'Strava';

  @override
  String get clubEditorFacebook => 'Facebook';

  @override
  String get clubEditorSaveChanges => 'Guardar cambios';

  @override
  String get clubDetailVisitWebsite => 'Visita nuestro sitio web';

  @override
  String get clubDetailEditClub => 'Editar club';

  @override
  String get roadbookTitle => 'Roadbook';

  @override
  String get roadbookCrewSheet => 'Roadbook (hoja de equipo)';

  @override
  String get roadbookGoalTime => 'Tiempo objetivo';

  @override
  String get roadbookStartTime => 'Hora de salida';

  @override
  String get roadbookEffort => 'Esfuerzo';

  @override
  String get roadbookEven => 'Uniforme';

  @override
  String get roadbookStart => 'Salida';

  @override
  String get roadbookFinish => 'Meta';

  @override
  String get roadbookShare => 'Compartir';

  @override
  String get roadbookNoMarkers =>
      'Añade marcadores de ruta para crear un roadbook.';

  @override
  String get roadbookAddElevation => 'Añadir altimetría';

  @override
  String get roadbookElevationUnavailable =>
      'Datos de altimetría no disponibles para esta ruta';

  @override
  String roadbookSummary(String distance, String vert, String time) {
    return '$distance · $vert desnivel · objetivo $time';
  }

  @override
  String get roadbookFuel => 'Avituallamiento';

  @override
  String get roadbookHeat => 'Calor';

  @override
  String get roadbookCarbs => 'Carbohidratos';

  @override
  String get roadbookFluid => 'Líquido';

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
    return 'llevar $gels geles · $fluid ml';
  }

  @override
  String get checkpointCheckinAction => 'Registro en checkpoint';

  @override
  String get checkpointCheckinTitle => 'Registro en avituallamiento';

  @override
  String get checkpointSyncNow => 'Sincronizar ahora';

  @override
  String get checkpointPending => 'Sin sincronizar';

  @override
  String get checkpointLoadFailed => 'No se pudieron cargar los checkpoints';

  @override
  String get checkpointRetry => 'Reintentar';

  @override
  String get checkpointNone =>
      'Esta carrera aún no tiene checkpoints. Añádelos en la web antes de que los voluntarios registren a los corredores.';

  @override
  String get checkpointPickLabel => 'CHECKPOINT';

  @override
  String get checkpointBibLabel => 'Número de dorsal';

  @override
  String get checkpointBibHint => 'Escanea o escribe un dorsal';

  @override
  String get checkpointBibRequired => 'Introduce primero un número de dorsal';

  @override
  String get checkpointStampIn => 'Marcar ENTRADA';

  @override
  String get checkpointStampOut => 'Marcar SALIDA';

  @override
  String checkpointStampedIn(String bib) {
    return 'Dorsal $bib marcado de entrada';
  }

  @override
  String checkpointStampedOut(String bib) {
    return 'Dorsal $bib marcado de salida';
  }

  @override
  String get checkpointStampFailed => 'No se pudo guardar ese registro';

  @override
  String checkpointLoggedHere(int count) {
    return 'REGISTRADOS AQUÍ ($count)';
  }

  @override
  String get checkpointNoneLoggedHere =>
      'Aún no hay corredores registrados en este checkpoint.';

  @override
  String checkpointBibRow(String bib) {
    return 'Dorsal $bib';
  }

  @override
  String checkpointInOut(String inTime, String outTime) {
    return 'Entrada $inTime · Salida $outTime';
  }

  @override
  String get checkpointWeighInTitle => 'Pesaje';

  @override
  String get checkpointWeighInConsentBlurb =>
      'El peso corporal y las notas de retención médica son datos de salud, registrados solo con el consentimiento del corredor y visibles solo para los oficiales de la carrera.';

  @override
  String get checkpointWeighInConsent =>
      'El corredor consiente el registro de datos de salud';

  @override
  String get checkpointWeighInWeightKg => 'Peso corporal (kg)';

  @override
  String get checkpointMedicalHold => 'Poner en retención médica';

  @override
  String get checkpointWeighInSave => 'Guardar y marcar';

  @override
  String get checkpointCancel => 'Cancelar';

  @override
  String get challengesTitle => 'Desafíos';

  @override
  String get challengesMyChallenges => 'Mis desafíos';

  @override
  String get challengesBrowse => 'Explorar';

  @override
  String get challengesEmpty => 'Aún no hay desafíos.';

  @override
  String get challengesBrowseEmpty =>
      'No hay desafíos públicos para unirse ahora mismo.';

  @override
  String get challengesJoin => 'Unirse';

  @override
  String get challengesLeave => 'Salir';

  @override
  String get challengesDelete => 'Eliminar';

  @override
  String get challengesMetricDistance => 'Distancia';

  @override
  String get challengesMetricDuration => 'Tiempo';

  @override
  String get challengesMetricVert => 'Desnivel';

  @override
  String get challengesMetricActivityCount => 'Actividades';

  @override
  String get challengesMetricStreak => 'Días activos';

  @override
  String challengesGoalProgress(String value, String goal) {
    return '$value de $goal';
  }

  @override
  String get challengesProgressComplete => 'Completado';

  @override
  String get challengesPaceAhead => 'Por delante del ritmo';

  @override
  String get challengesPaceOnTrack => 'A buen ritmo para terminar';

  @override
  String get challengesPaceBehind => 'Por detrás del ritmo';

  @override
  String challengesPaceNeedPerDay(String rate) {
    return '$rate por día para terminar';
  }

  @override
  String challengesEndsIn(int n) {
    return 'Termina en $n días';
  }

  @override
  String get challengesEndsToday => 'Termina hoy';

  @override
  String get challengesEnded => 'Finalizado';

  @override
  String get challengesLeaderboard => 'Clasificación';

  @override
  String get challengesLeaderboardEmpty => 'Aún no hay progreso registrado.';

  @override
  String challengesLeaderboardRank(int rank) {
    return '#$rank';
  }

  @override
  String challengesParticipants(int n) {
    return '$n unidos';
  }

  @override
  String get challengesBadgeEarned => 'Insignia obtenida';

  @override
  String challengesUnitDays(int n) {
    return '$n días';
  }

  @override
  String challengesUnitActivities(int n) {
    return '$n';
  }

  @override
  String get challengesLeaveConfirmTitle => '¿Salir del desafío?';

  @override
  String get challengesLeaveConfirm =>
      'Tu progreso en este desafío dejará de registrarse.';

  @override
  String get challengesDeleteConfirmTitle => '¿Eliminar desafío?';

  @override
  String get challengesDeleteConfirm =>
      'Esto elimina el desafío y su clasificación para todos. No se puede deshacer.';

  @override
  String get challengesNotFound => 'Este desafío no está disponible.';

  @override
  String get challengesJoinFailed => 'No se pudo unir al desafío.';

  @override
  String get challengesLeaveFailed => 'No se pudo salir del desafío.';

  @override
  String get challengesDeleteFailed => 'No se pudo eliminar el desafío.';

  @override
  String get challengesLoadFailed => 'No se pudieron cargar los desafíos.';

  @override
  String fundraiserRaisedOfGoal(String raised, String goal) {
    return '$raised de $goal recaudado';
  }

  @override
  String fundraiserDonorCount(int count) {
    return '$count colaboradores';
  }

  @override
  String get fundraiserOverGoal => '¡Meta superada!';

  @override
  String get fundraiserClosed => 'Esta campaña está cerrada.';

  @override
  String get fundraiserFeedTitle => 'Colaboradores recientes';

  @override
  String get fundraiserFeedEmpty => 'Sé el primero en donar.';

  @override
  String get fundraiserAnonymous => 'Anónimo';

  @override
  String get fundraiserDonateOnWeb => 'Donar en la web';

  @override
  String get racesTitle => 'Calendario de carreras';

  @override
  String get racesSearchPlaceholder => 'Buscar carreras por nombre…';

  @override
  String get racesNearPlace => 'Cerca de un lugar…';

  @override
  String racesKmAway(String distance) {
    return 'a $distance';
  }

  @override
  String get racesDistanceAny => 'Cualquier distancia';

  @override
  String get racesDistance5k => '5K';

  @override
  String get racesDistance10k => '10K';

  @override
  String get racesDistanceHalf => 'Media';

  @override
  String get racesDistanceMarathon => 'Maratón';

  @override
  String get racesDistanceUltra => 'Ultra';

  @override
  String get racesRegister => 'Inscribirse';

  @override
  String get racesViewResults => 'Ver resultados';

  @override
  String get racesImportResult => 'Importar mi resultado';

  @override
  String get racesSubmitRace => 'Añadir una carrera';

  @override
  String get racesUnverified => 'Sin verificar';

  @override
  String get racesEmpty =>
      'Aún no hay carreras que coincidan con estos filtros.';

  @override
  String get racesSearchFailed =>
      'No se pudieron cargar las carreras. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String racesMatchPrompt(String name) {
    return '¿Fue esta la $name? Importa tu resultado oficial.';
  }

  @override
  String get racesMatchConfirm => 'Importar resultado';

  @override
  String get racesMatchDismiss => 'No es esta carrera';

  @override
  String get racesImported => 'Resultado oficial importado.';

  @override
  String get racesOfficialResult => 'Resultado oficial';

  @override
  String get racesChipTime => 'Tiempo chip';

  @override
  String get racesGunTime => 'Tiempo oficial';

  @override
  String get racesOverallPlace => 'Puesto general';

  @override
  String get racesAgeGroupPlace => 'Puesto por categoría';

  @override
  String get racesAgeGroup => 'Categoría de edad';

  @override
  String get racesBib => 'Dorsal';

  @override
  String get racesPasteResultHint =>
      'Introduce los datos de tu llegada desde la página de resultados de la carrera.';

  @override
  String get racesSave => 'Guardar';

  @override
  String get racesCancel => 'Cancelar';

  @override
  String get racesEditorTitle => 'Añadir una carrera';

  @override
  String get racesFieldName => 'Nombre de la carrera';

  @override
  String get racesFieldDate => 'Fecha';

  @override
  String get racesFieldDistance => 'Distancia (metros)';

  @override
  String get racesFieldLocation => 'Ubicación';

  @override
  String get racesFieldEntryUrl => 'Enlace de inscripción';

  @override
  String get racesFieldResultsUrl => 'Enlace de resultados';

  @override
  String get racesSubmitFailed =>
      'No se pudo guardar la carrera. Inténtalo de nuevo.';

  @override
  String get racesImportFailed =>
      'No se pudo importar el resultado. Inténtalo de nuevo.';

  @override
  String get navRaces => 'Carreras';

  @override
  String get integrationsRunsignup => 'RunSignUp';

  @override
  String get integrationsRunsignupConnect =>
      'Importa resultados de carreras desde RunSignUp.';

  @override
  String get integrationsRunsignupOpen => 'Abrir el calendario de carreras';

  @override
  String get integrationsRunsignupUnavailable =>
      'La importación de RunSignUp aún no está disponible. parkrun y el pegado manual siguen funcionando.';

  @override
  String get integrationsChronotrack => 'ChronoTrack';

  @override
  String get integrationsChronotrackConnect =>
      'Importa resultados de carreras de eventos cronometrados con ChronoTrack.';

  @override
  String get integrationsChronotrackOpen => 'Abrir el calendario de carreras';

  @override
  String get integrationsChronotrackUnavailable =>
      'La importación de ChronoTrack aún no está disponible. parkrun y el pegado manual siguen funcionando.';

  @override
  String get routeConditionsTitle => 'Condiciones';

  @override
  String get routeConditionsReport => 'Reportar condición';

  @override
  String get routeConditionsReporting => 'Enviando…';

  @override
  String get routeConditionsReported => 'Condición reportada';

  @override
  String get routeConditionsReportFailed => 'No se pudo reportar la condición';

  @override
  String get routeConditionsEmpty => 'Aún no hay reportes.';

  @override
  String get routeConditionsLoading => 'Cargando…';

  @override
  String get routeConditionsCancel => 'Cancelar';

  @override
  String get routeConditionsDelete => 'Eliminar';

  @override
  String get routeConditionsDeleteTitle => '¿Eliminar reporte?';

  @override
  String get routeConditionsDeleteConfirm =>
      'Esto elimina el reporte de forma permanente.';

  @override
  String get routeConditionsDeleteFailed => 'No se pudo eliminar el reporte';

  @override
  String get routeConditionsKindLabel => 'Condición';

  @override
  String get routeConditionsSeverityLabel => 'Gravedad';

  @override
  String get routeConditionsNoteLabel => 'Nota';

  @override
  String get routeConditionsNotePlaceholder =>
      '¿Qué encontrará el próximo corredor?';

  @override
  String routeConditionsAtDistance(String distance) {
    return 'en $distance';
  }

  @override
  String get routeConditionMuddy => 'Embarrado';

  @override
  String get routeConditionFlooded => 'Inundado';

  @override
  String get routeConditionSnowIce => 'Nieve / hielo';

  @override
  String get routeConditionOvergrown => 'Cubierto de maleza';

  @override
  String get routeConditionClosed => 'Cerrado';

  @override
  String get routeConditionHazard => 'Peligro';

  @override
  String get routeConditionClear => 'Despejado';

  @override
  String get routeConditionOther => 'Otro';

  @override
  String get routeConditionSeverityInfo => 'Info';

  @override
  String get routeConditionSeverityCaution => 'Precaución';

  @override
  String get routeConditionSeverityImpassable => 'Intransitable';

  @override
  String get prefTurnByTurnCues => 'Indicaciones de voz giro a giro';

  @override
  String get prefTurnByTurnCuesSubtitle =>
      'Direcciones habladas al seguir una ruta guardada';

  @override
  String ttsTurnLeftIn(String distance) {
    return 'En $distance, gire a la izquierda';
  }

  @override
  String ttsTurnRightIn(String distance) {
    return 'En $distance, gire a la derecha';
  }

  @override
  String get ttsTurnLeftNow => 'Gire a la izquierda';

  @override
  String get ttsTurnRightNow => 'Gire a la derecha';

  @override
  String get ttsSlightLeft => 'Manténgase a la izquierda';

  @override
  String get ttsSlightRight => 'Manténgase a la derecha';

  @override
  String get ttsUturn => 'Haga un cambio de sentido';

  @override
  String routeOfflinePackDownloading(int done, int total) {
    return 'Almacenando mapa: $done / $total';
  }

  @override
  String get routeOfflinePackReady => 'Mapa guardado sin conexión';

  @override
  String routeOfflinePackPartial(int done, int total) {
    return 'Mapa parcialmente guardado ($done / $total) — reintentar';
  }

  @override
  String get routeOfflinePackTooLarge =>
      'Esta ruta es demasiado grande para guardar sin conexión';

  @override
  String get badgesSectionTitle => 'Logros';

  @override
  String get badgesSectionSubtitle => 'Hitos que has conseguido';

  @override
  String get badgesEmpty => 'Aún no tienes insignias: sigue corriendo.';

  @override
  String get badgesEmptyOther => 'Todavía no hay insignias públicas.';

  @override
  String badgesEarnedOn(String date) {
    return 'Conseguida el $date';
  }

  @override
  String badgesFeedEarned(String name, String badge) {
    return '$name consiguió la insignia $badge';
  }

  @override
  String get badgesARunner => 'Un corredor';

  @override
  String get badgesTierBronze => 'Bronce';

  @override
  String get badgesTierSilver => 'Plata';

  @override
  String get badgesTierGold => 'Oro';

  @override
  String get badgesTierPlatinum => 'Platino';

  @override
  String get badgesDistanceSingle5kLabel => 'Primeros 5 km';

  @override
  String get badgesDistanceSingle5kDesc => 'Corriste 5 km en una sola carrera';

  @override
  String get badgesDistanceSingleHalfLabel => 'Media maratón';

  @override
  String get badgesDistanceSingleHalfDesc =>
      'Corriste 21,1 km en una sola carrera';

  @override
  String get badgesDistanceSingleMarathonLabel => 'Maratón';

  @override
  String get badgesDistanceSingleMarathonDesc =>
      'Corriste 42,2 km en una sola carrera';

  @override
  String get badgesDistanceSingleUltraLabel => 'Ultra';

  @override
  String get badgesDistanceSingleUltraDesc =>
      'Corriste 50 km o más en una sola carrera';

  @override
  String get badgesDistanceLifetime100Label => 'Club de los 100 km';

  @override
  String get badgesDistanceLifetime100Desc => '100 km registrados en total';

  @override
  String get badgesDistanceLifetime500Label => '500 km';

  @override
  String get badgesDistanceLifetime500Desc => '500 km registrados en total';

  @override
  String get badgesDistanceLifetime1000Label => 'Club de los 1000 km';

  @override
  String get badgesDistanceLifetime1000Desc => '1000 km registrados en total';

  @override
  String get badgesDistanceLifetime5000Label => '5000 km';

  @override
  String get badgesDistanceLifetime5000Desc => '5000 km registrados en total';

  @override
  String get badgesStreak7Label => 'Racha semanal';

  @override
  String get badgesStreak7Desc => 'Corriste 7 días seguidos';

  @override
  String get badgesStreak30Label => 'Racha mensual';

  @override
  String get badgesStreak30Desc => 'Corriste 30 días seguidos';

  @override
  String get badgesStreak100Label => 'Racha de cien';

  @override
  String get badgesStreak100Desc => 'Corriste 100 días seguidos';

  @override
  String get badgesStreak365Label => 'Racha anual';

  @override
  String get badgesStreak365Desc => 'Corriste 365 días seguidos';

  @override
  String get badgesPr1Label => 'Primer récord';

  @override
  String get badgesPr1Desc => 'Estableciste tu primer récord personal';

  @override
  String get badgesPr3Label => 'Triple récord';

  @override
  String get badgesPr3Desc => 'Mantienes récords personales en 3 distancias';

  @override
  String get badgesPr5Label => 'Coleccionista de récords';

  @override
  String get badgesPr5Desc =>
      'Mantienes récords personales en todas las distancias';

  @override
  String get badgesPlan1Label => 'Plan completado';

  @override
  String get badgesPlan1Desc => 'Completaste un plan de entrenamiento';

  @override
  String get badgesPlan3Label => 'Triple finalizador';

  @override
  String get badgesPlan3Desc => 'Completaste 3 planes de entrenamiento';

  @override
  String get badgesPlan10Label => 'Veterano de planes';

  @override
  String get badgesPlan10Desc => 'Completaste 10 planes de entrenamiento';

  @override
  String get racePredictorTitle => 'Predictor de tiempo de carrera';

  @override
  String racePredictorAnchoredOn(String distance, String time) {
    return 'A partir de tu esfuerzo en $distance en $time';
  }

  @override
  String get racePredictorColDistance => 'Distancia';

  @override
  String get racePredictorColTime => 'Tiempo';

  @override
  String get racePredictorColPace => 'Ritmo';

  @override
  String get racePredictorColConfidence => 'Fiabilidad';

  @override
  String get racePredictorConfidenceHigh => 'Alta';

  @override
  String get racePredictorConfidenceModerate => 'Media';

  @override
  String get racePredictorConfidenceLow => 'Baja';

  @override
  String get racePredictorConfReasonSimilar =>
      'Basado en esfuerzos recientes cercanos a esta distancia.';

  @override
  String get racePredictorConfReasonExtrapolated =>
      'Extrapolado sobre una gran diferencia de distancia — tómalo como una aproximación.';

  @override
  String get racePredictorConfReasonStale =>
      'Anclado a un esfuerzo de hace unas semanas.';

  @override
  String get racePredictorConfReasonLimited =>
      'Basado en datos recientes limitados.';

  @override
  String get racePredictorFootnote =>
      'Equivalencia de Riegel a partir de tu mejor esfuerzo reciente, ponderada por recencia. Las distancias cercanas son más fiables.';

  @override
  String get settingsSectionDeveloper => 'Desarrollador';

  @override
  String get settingsTabSimWatchSubtitle =>
      'Estado en vivo del reloj personalizado simulado';

  @override
  String get simWatchTitle => 'Enlace del reloj simulado';

  @override
  String get simWatchHostLabel => 'Host';

  @override
  String get simWatchPortLabel => 'Puerto';

  @override
  String get simWatchConnect => 'Conectar';

  @override
  String get simWatchConnecting => 'Conectando…';

  @override
  String get simWatchDisconnect => 'Desconectar';

  @override
  String simWatchConnectionFailed(String error) {
    return 'Error de conexión: $error';
  }

  @override
  String get simWatchSyncAction => 'Sincronizar carreras del reloj';

  @override
  String simWatchSyncing(int done, int total) {
    return 'Sincronizando… $done/$total';
  }

  @override
  String simWatchResult(int synced, int total) {
    return 'Se sincronizaron $synced de $total carrera(s) del reloj';
  }

  @override
  String simWatchSyncFailed(String error) {
    return 'Error al sincronizar el reloj: $error';
  }

  @override
  String get simWatchPushSettingsAction => 'Enviar ajustes al reloj';

  @override
  String get simWatchSettingsPushed => 'Ajustes enviados al reloj';

  @override
  String simWatchPushSettingsFailed(String error) {
    return 'Error al enviar los ajustes: $error';
  }

  @override
  String get simWatchNoRuns => 'No hay carreras en el reloj para sincronizar';

  @override
  String get simWatchWaitingFrames => 'Conectado — esperando tramas…';

  @override
  String get simWatchUptime => 'Tiempo encendido del reloj';

  @override
  String get simWatchNoFix => 'Aún sin señal GPS';

  @override
  String get simWatchPosition => 'Posición';

  @override
  String get simWatchSpeed => 'Velocidad';

  @override
  String get simWatchSatellites => 'Satélites';

  @override
  String get simWatchAltitude => 'Altitud';

  @override
  String get simWatchBaroAltitude => 'Altitud barométrica';

  @override
  String get simWatchAscent => 'Ascenso';

  @override
  String get simWatchDescent => 'Descenso';

  @override
  String get simWatchFixAge => 'Antigüedad de la señal';

  @override
  String simWatchSeconds(int seconds) {
    return '$seconds s';
  }
}
