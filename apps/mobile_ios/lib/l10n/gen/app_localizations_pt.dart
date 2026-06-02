// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get prefsLanguage => 'Idioma';

  @override
  String get prefsLanguageSystem => 'Padrão do sistema';

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
  String get navHome => 'Início';

  @override
  String get navRun => 'Corrida';

  @override
  String get navHistory => 'Histórico';

  @override
  String get navSocial => 'Social';

  @override
  String get navSettings => 'Config.';

  @override
  String get settingsSectionProfile => 'Perfil';

  @override
  String get settingsSectionAppsData => 'Apps e dados';

  @override
  String get settingsSectionAccountLegal => 'Conta e jurídico';

  @override
  String get prefsSectionUnitsDisplay => 'Unidades e exibição';

  @override
  String get authEmailLabel => 'E-mail';

  @override
  String get authPasswordLabel => 'Senha';

  @override
  String get authOrDivider => 'OU';

  @override
  String get signInTitle => 'Entrar';

  @override
  String get signInHeadline => 'Sincronize corridas entre dispositivos';

  @override
  String get signInSubtitle =>
      'Entre para fazer backup das corridas e vê-las no app web.';

  @override
  String get signInButton => 'Entrar';

  @override
  String get signInForgotPassword => 'Esqueceu a senha?';

  @override
  String get signInResetNeedEmail =>
      'Digite seu e-mail acima primeiro e depois toque em Esqueceu a senha.';

  @override
  String get signInResetSent =>
      'Se esse e-mail estiver cadastrado, enviamos um link de redefinição.';

  @override
  String get signInWithApple => 'Entrar com Apple';

  @override
  String get signInWithGoogle => 'Entrar com Google';

  @override
  String get signInContinueOffline => 'Continuar offline';

  @override
  String get signInCreateAccountPrompt => 'Não tem uma conta? Crie uma';

  @override
  String get signUpTitle => 'Criar conta';

  @override
  String get signUpHeadline => 'Comece a registrar suas corridas';

  @override
  String get signUpSubtitle =>
      'Crie uma conta para fazer backup das corridas e vê-las no app web.';

  @override
  String get signUpButton => 'Criar conta';

  @override
  String get signUpConfirmAge => 'Tenho 16 anos ou mais';

  @override
  String get signUpAcceptPrefix => 'Aceito os ';

  @override
  String get signUpTermsLink => 'Termos de Serviço';

  @override
  String get signUpAcceptConjunction => ' e a ';

  @override
  String get signUpPrivacyLink => 'Política de Privacidade';

  @override
  String get signUpErrorConfirmAge =>
      'Confirme que você tem 16 anos ou mais para continuar.';

  @override
  String get signUpErrorAcceptTerms =>
      'Aceite os Termos de Serviço e a Política de Privacidade para continuar.';

  @override
  String get signUpContinueWithApple => 'Continuar com Apple';

  @override
  String get signUpContinueWithGoogle => 'Continuar com Google';

  @override
  String get signUpSignInPrompt => 'Já tem uma conta? Entre';

  @override
  String signUpCouldNotOpen(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String get onboardingTrackTitle => 'Registre cada corrida';

  @override
  String get onboardingTrackBody =>
      'Gravação por GPS com mapa ao vivo, parciais, ritmo, cadência e elevação. Funciona totalmente offline — entre depois para sincronizar entre dispositivos.';

  @override
  String get onboardingRoutesTitle => 'Siga rotas';

  @override
  String get onboardingRoutesBody =>
      'Importe arquivos GPX ou KML, ou sincronize rotas do app web. Receba alertas de desvio enquanto corre.';

  @override
  String get onboardingLocationTitle => 'Acesso à localização';

  @override
  String get onboardingLocationBody =>
      'O Threkir registra suas corridas amostrando sua localização por GPS enquanto o app está em primeiro plano E em segundo plano (para continuar registrando quando a tela está desligada ou você troca de app para tirar uma foto). Os dados de localização ficam armazenados no seu dispositivo e só são enviados aos servidores do Threkir quando você escolhe compartilhar ou sincronizar uma corrida. Se você recusar a localização em segundo plano, as corridas param de ser registradas no momento em que você sai do app — você pode mudar isso depois em Configurações → Apps → Threkir → Permissões.';

  @override
  String get onboardingPrivacyTitle => 'Quem vê suas corridas?';

  @override
  String get onboardingPrivacyBody =>
      'Escolha um padrão para novas corridas. Você pode alterá-lo a qualquer momento nas Configurações e substituí-lo em qualquer corrida específica.';

  @override
  String get onboardingGrantPermission => 'Conceder permissão';

  @override
  String get onboardingNext => 'Avançar';

  @override
  String get privacyPrivateTitle => 'Privada';

  @override
  String get privacyPrivateSubtitle =>
      'Só você pode ver suas corridas. Você pode compartilhar qualquer corrida depois.';

  @override
  String get privacyFollowersTitle => 'Seguidores';

  @override
  String get privacyFollowersSubtitle =>
      'Quem segue você vê as novas corridas no feed.';

  @override
  String get privacyPublicTitle => 'Pública';

  @override
  String get privacyPublicSubtitle =>
      'Qualquer pessoa pode encontrar e ver suas corridas.';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String get prefsLanguage => 'Idioma';

  @override
  String get prefsLanguageSystem => 'Padrão do sistema';

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
  String get navHome => 'Início';

  @override
  String get navRun => 'Corrida';

  @override
  String get navHistory => 'Histórico';

  @override
  String get navSocial => 'Social';

  @override
  String get navSettings => 'Config.';

  @override
  String get settingsSectionProfile => 'Perfil';

  @override
  String get settingsSectionAppsData => 'Apps e dados';

  @override
  String get settingsSectionAccountLegal => 'Conta e jurídico';

  @override
  String get prefsSectionUnitsDisplay => 'Unidades e exibição';

  @override
  String get authEmailLabel => 'E-mail';

  @override
  String get authPasswordLabel => 'Senha';

  @override
  String get authOrDivider => 'OU';

  @override
  String get signInTitle => 'Entrar';

  @override
  String get signInHeadline => 'Sincronize corridas entre dispositivos';

  @override
  String get signInSubtitle =>
      'Entre para fazer backup das corridas e vê-las no app web.';

  @override
  String get signInButton => 'Entrar';

  @override
  String get signInForgotPassword => 'Esqueceu a senha?';

  @override
  String get signInResetNeedEmail =>
      'Digite seu e-mail acima primeiro e depois toque em Esqueceu a senha.';

  @override
  String get signInResetSent =>
      'Se esse e-mail estiver cadastrado, enviamos um link de redefinição.';

  @override
  String get signInWithApple => 'Entrar com Apple';

  @override
  String get signInWithGoogle => 'Entrar com Google';

  @override
  String get signInContinueOffline => 'Continuar offline';

  @override
  String get signInCreateAccountPrompt => 'Não tem uma conta? Crie uma';

  @override
  String get signUpTitle => 'Criar conta';

  @override
  String get signUpHeadline => 'Comece a registrar suas corridas';

  @override
  String get signUpSubtitle =>
      'Crie uma conta para fazer backup das corridas e vê-las no app web.';

  @override
  String get signUpButton => 'Criar conta';

  @override
  String get signUpConfirmAge => 'Tenho 16 anos ou mais';

  @override
  String get signUpAcceptPrefix => 'Aceito os ';

  @override
  String get signUpTermsLink => 'Termos de Serviço';

  @override
  String get signUpAcceptConjunction => ' e a ';

  @override
  String get signUpPrivacyLink => 'Política de Privacidade';

  @override
  String get signUpErrorConfirmAge =>
      'Confirme que você tem 16 anos ou mais para continuar.';

  @override
  String get signUpErrorAcceptTerms =>
      'Aceite os Termos de Serviço e a Política de Privacidade para continuar.';

  @override
  String get signUpContinueWithApple => 'Continuar com Apple';

  @override
  String get signUpContinueWithGoogle => 'Continuar com Google';

  @override
  String get signUpSignInPrompt => 'Já tem uma conta? Entre';

  @override
  String signUpCouldNotOpen(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String get onboardingTrackTitle => 'Registre cada corrida';

  @override
  String get onboardingTrackBody =>
      'Gravação por GPS com mapa ao vivo, parciais, ritmo, cadência e elevação. Funciona totalmente offline — entre depois para sincronizar entre dispositivos.';

  @override
  String get onboardingRoutesTitle => 'Siga rotas';

  @override
  String get onboardingRoutesBody =>
      'Importe arquivos GPX ou KML, ou sincronize rotas do app web. Receba alertas de desvio enquanto corre.';

  @override
  String get onboardingLocationTitle => 'Acesso à localização';

  @override
  String get onboardingLocationBody =>
      'O Threkir registra suas corridas amostrando sua localização por GPS enquanto o app está em primeiro plano E em segundo plano (para continuar registrando quando a tela está desligada ou você troca de app para tirar uma foto). Os dados de localização ficam armazenados no seu dispositivo e só são enviados aos servidores do Threkir quando você escolhe compartilhar ou sincronizar uma corrida. Se você recusar a localização em segundo plano, as corridas param de ser registradas no momento em que você sai do app — você pode mudar isso depois em Configurações → Apps → Threkir → Permissões.';

  @override
  String get onboardingPrivacyTitle => 'Quem vê suas corridas?';

  @override
  String get onboardingPrivacyBody =>
      'Escolha um padrão para novas corridas. Você pode alterá-lo a qualquer momento nas Configurações e substituí-lo em qualquer corrida específica.';

  @override
  String get onboardingGrantPermission => 'Conceder permissão';

  @override
  String get onboardingNext => 'Avançar';

  @override
  String get privacyPrivateTitle => 'Privada';

  @override
  String get privacyPrivateSubtitle =>
      'Só você pode ver suas corridas. Você pode compartilhar qualquer corrida depois.';

  @override
  String get privacyFollowersTitle => 'Seguidores';

  @override
  String get privacyFollowersSubtitle =>
      'Quem segue você vê as novas corridas no feed.';

  @override
  String get privacyPublicTitle => 'Pública';

  @override
  String get privacyPublicSubtitle =>
      'Qualquer pessoa pode encontrar e ver suas corridas.';
}
