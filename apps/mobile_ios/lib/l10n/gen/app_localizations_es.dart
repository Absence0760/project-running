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
}
