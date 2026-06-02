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

  @override
  String get runStart => 'INICIAR';

  @override
  String get runStartA11yLabel => 'Iniciar corrida';

  @override
  String get runChooseRoute => 'Escolher rota';

  @override
  String get runChangeRoute => 'Trocar rota';

  @override
  String get runShareLiveLink => 'Compartilhar link ao vivo';

  @override
  String get runTrainingPlans => 'Planos de treino';

  @override
  String get runTapToCancel => 'Toque para cancelar';

  @override
  String get runFirstRunPrompt =>
      'Sua primeira corrida está a um toque de distância.';

  @override
  String get runLastActivity => 'Última atividade';

  @override
  String get runLastRun => 'Última corrida';

  @override
  String get runFollowing => 'SEGUINDO';

  @override
  String get runRaceFallbackTitle => 'Prova';

  @override
  String get runRaceArmed => 'Prova pronta';

  @override
  String get runRaceLive => 'Prova AO VIVO';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — aguardando a largada';
  }

  @override
  String runRaceElapsedTapStart(String label, String elapsed) {
    return '$label — $elapsed decorridos · toque em Iniciar';
  }

  @override
  String get runComplete => 'Corrida concluída';

  @override
  String get runStatDistance => 'Distância';

  @override
  String get runStatTime => 'Tempo';

  @override
  String get runStatMoving => 'Em movimento';

  @override
  String get runStatPace => 'Ritmo';

  @override
  String get runStatSpeed => 'Velocidade';

  @override
  String get runStatAvgPace => 'Ritmo médio';

  @override
  String get runStatAvgSpeed => 'Veloc. média';

  @override
  String get runStatCalories => 'Calorias';

  @override
  String get runStatElevation => 'Elevação';

  @override
  String get runStatSteps => 'Passos';

  @override
  String get runStatCadence => 'Cadência';

  @override
  String get runStatHeartRate => 'Freq. cardíaca';

  @override
  String get runUnitKcal => 'kcal';

  @override
  String get runUnitMetres => 'm';

  @override
  String get runUnitSpm => 'ppm';

  @override
  String get runUnitBpm => 'bpm';

  @override
  String get runMutePaceCues => 'Silenciar avisos de ritmo';

  @override
  String get runPaceCuesMuted => 'Avisos de ritmo silenciados';

  @override
  String get runSynced => 'Sincronizada';

  @override
  String get runSyncing => 'Sincronizando…';

  @override
  String get runDone => 'Concluído';

  @override
  String get runDiscardA11yLabel => 'Descartar corrida';

  @override
  String get runDiscardA11yHint => 'Descarta a gravação atual sem salvar';

  @override
  String get runResumeA11yLabel => 'Retomar corrida';

  @override
  String get runPauseA11yLabel => 'Pausar corrida';

  @override
  String get runResumeA11yHint => 'Retoma a gravação pausada';

  @override
  String get runPauseA11yHint => 'Pausa a gravação sem encerrá-la';

  @override
  String get runMarkLapA11yLabel => 'Marcar volta';

  @override
  String runMarkLapWithCountA11yLabel(int count) {
    return 'Marcar volta, $count até agora';
  }

  @override
  String get runMarkLapA11yHint => 'Registra o parcial atual';

  @override
  String get runCollapseStatsPanel => 'Recolher painel de estatísticas';

  @override
  String get runExpandStatsPanel => 'Expandir painel de estatísticas';

  @override
  String runRouteRemaining(String distance) {
    return 'faltam $distance';
  }

  @override
  String runOffRoute(int metres) {
    return 'Fora da rota — a $metres m';
  }

  @override
  String get runPermissionRevoked => 'Permissão de localização revogada';

  @override
  String get runGpsLost => 'Sinal de GPS perdido — vá para um local aberto';

  @override
  String get runWeakGps => 'GPS fraco — distância pausada';

  @override
  String get runA11yStarted => 'Corrida iniciada';

  @override
  String get runA11yResumed => 'Corrida retomada';

  @override
  String get runA11yPaused => 'Corrida pausada';

  @override
  String get runA11yFinished => 'Corrida finalizada';

  @override
  String runLapMarked(int count) {
    return 'Volta $count marcada';
  }

  @override
  String get runDiscardDialogTitle => 'Descartar corrida?';

  @override
  String get runDiscardDialogBody => 'Seu progresso será perdido.';

  @override
  String get runKeepRunning => 'Continuar correndo';

  @override
  String get runDiscard => 'Descartar';

  @override
  String get runStartWorkout => 'Iniciar treino';

  @override
  String get runStartWorkoutSubtitle =>
      'Corra com metas de etapa ao vivo, avisos de áudio e uma análise de planejado vs. realizado.';

  @override
  String get runViewWorkoutDetails => 'Ver detalhes';

  @override
  String get runWorkoutNoStructure =>
      'Este treino não tem uma estrutura executável.';

  @override
  String runWorkoutLoaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etapas',
      one: '$count etapa',
    );
    return 'Treino carregado · $_temp0 — toque em GO para iniciar';
  }

  @override
  String get runAbandonWorkoutTitle => 'Abandonar treino?';

  @override
  String get runAbandonWorkoutBody =>
      'O plano estruturado termina aqui; a gravação continua como corrida livre. Você pode parar a qualquer momento para salvar o que fez.';

  @override
  String get runCancel => 'Cancelar';

  @override
  String get runAbandon => 'Abandonar';

  @override
  String get runNoRoutesSaved =>
      'Nenhuma rota salva. Importe uma na aba Rotas.';

  @override
  String get runNotificationsOffHint =>
      'As notificações estão desativadas — a notificação de corrida ao vivo não aparecerá. A gravação continua funcionando.';

  @override
  String get runSettings => 'Configurações';

  @override
  String get runStartAnyway => 'Iniciar mesmo assim';

  @override
  String get runOpenSettings => 'Abrir configurações';

  @override
  String get runNotNow => 'Agora não';

  @override
  String get runShareSubject => 'Me acompanhe ao vivo';

  @override
  String runCouldNotShareLink(String error) {
    return 'Não foi possível compartilhar o link ao vivo: $error';
  }

  @override
  String get runHrStrapLostReconnecting =>
      'Cinta cardíaca perdida — reconectando…';

  @override
  String get runHrStrapReconnected => 'Cinta cardíaca reconectada';

  @override
  String get runHrStrapLostNoHr =>
      'Cinta cardíaca perdida — a gravação continua sem FC.';

  @override
  String get runHrStrapNotFound =>
      'Cinta cardíaca não encontrada — coloque-a e reconecte.';

  @override
  String get runReconnect => 'Reconectar';

  @override
  String get runHrStrapStillNotFound =>
      'Ainda sem cinta — a gravação continua sem FC.';

  @override
  String get runSaveFailedRelaunch =>
      'Não foi possível salvar localmente. Reinicie o app para recuperar.';

  @override
  String get runSyncFailedSaveOffline =>
      'Salva offline. Sincronize em Corridas.';

  @override
  String get runSavedOffline => 'Salva offline.';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings =>
      'Sem GPS — o rastreamento começará quando a Localização estiver ativada.';

  @override
  String get runGpsBlockedSettings =>
      'Sem GPS — permissão bloqueada. Ative-a para rastrear a rota.';

  @override
  String get runGpsPermissionPending =>
      'Sem GPS — o rastreamento começará quando a permissão for concedida.';

  @override
  String get runGpsAllowAllTheTime =>
      'Defina a Localização como \"Permitir o tempo todo\" — as corridas param de gravar quando você troca de app sem permissão em segundo plano.';

  @override
  String get runGpsSensorFailed =>
      'Gravando sem GPS — não foi possível iniciar o sensor.';

  @override
  String get runAgoJustNow => 'Agora mesmo';

  @override
  String runAgoMinutes(int count) {
    return 'há $count min';
  }

  @override
  String runAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count horas',
      one: 'há 1 hora',
    );
    return '$_temp0';
  }

  @override
  String get runAgoYesterday => 'Ontem';

  @override
  String runAgoDays(int count) {
    return 'há $count dias';
  }

  @override
  String runAgoWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count semanas',
      one: 'há 1 semana',
    );
    return '$_temp0';
  }

  @override
  String runAgoMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count meses',
      one: 'há 1 mês',
    );
    return '$_temp0';
  }

  @override
  String get runWorkoutAbandonedBand => 'Treino abandonado · correndo livre';

  @override
  String get runWorkoutCompleteBand =>
      'Treino concluído · toque em parar para salvar';

  @override
  String runWorkoutStepHeader(String label, String target, String pace) {
    return '$label · $target @ $pace';
  }

  @override
  String runWorkoutStepCounter(int current, int total) {
    return '$current/$total';
  }

  @override
  String get runWorkoutRewind => 'Voltar';

  @override
  String get runWorkoutSkip => 'Pular';

  @override
  String get runWorkoutAbandon => 'Abandonar';

  @override
  String runWorkoutRemainingYards(int yards) {
    return 'faltam $yards yd';
  }

  @override
  String runWorkoutRemainingMetres(int metres) {
    return 'faltam $metres m';
  }

  @override
  String runWorkoutRemainingDuration(String duration) {
    return 'faltam $duration';
  }
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

  @override
  String get runStart => 'INICIAR';

  @override
  String get runStartA11yLabel => 'Iniciar corrida';

  @override
  String get runChooseRoute => 'Escolher rota';

  @override
  String get runChangeRoute => 'Trocar rota';

  @override
  String get runShareLiveLink => 'Compartilhar link ao vivo';

  @override
  String get runTrainingPlans => 'Planos de treino';

  @override
  String get runTapToCancel => 'Toque para cancelar';

  @override
  String get runFirstRunPrompt =>
      'Sua primeira corrida está a um toque de distância.';

  @override
  String get runLastActivity => 'Última atividade';

  @override
  String get runLastRun => 'Última corrida';

  @override
  String get runFollowing => 'SEGUINDO';

  @override
  String get runRaceFallbackTitle => 'Prova';

  @override
  String get runRaceArmed => 'Prova pronta';

  @override
  String get runRaceLive => 'Prova AO VIVO';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — aguardando a largada';
  }

  @override
  String runRaceElapsedTapStart(String label, String elapsed) {
    return '$label — $elapsed decorridos · toque em Iniciar';
  }

  @override
  String get runComplete => 'Corrida concluída';

  @override
  String get runStatDistance => 'Distância';

  @override
  String get runStatTime => 'Tempo';

  @override
  String get runStatMoving => 'Em movimento';

  @override
  String get runStatPace => 'Ritmo';

  @override
  String get runStatSpeed => 'Velocidade';

  @override
  String get runStatAvgPace => 'Ritmo médio';

  @override
  String get runStatAvgSpeed => 'Veloc. média';

  @override
  String get runStatCalories => 'Calorias';

  @override
  String get runStatElevation => 'Elevação';

  @override
  String get runStatSteps => 'Passos';

  @override
  String get runStatCadence => 'Cadência';

  @override
  String get runStatHeartRate => 'Freq. cardíaca';

  @override
  String get runUnitKcal => 'kcal';

  @override
  String get runUnitMetres => 'm';

  @override
  String get runUnitSpm => 'ppm';

  @override
  String get runUnitBpm => 'bpm';

  @override
  String get runMutePaceCues => 'Silenciar avisos de ritmo';

  @override
  String get runPaceCuesMuted => 'Avisos de ritmo silenciados';

  @override
  String get runSynced => 'Sincronizada';

  @override
  String get runSyncing => 'Sincronizando…';

  @override
  String get runDone => 'Concluído';

  @override
  String get runDiscardA11yLabel => 'Descartar corrida';

  @override
  String get runDiscardA11yHint => 'Descarta a gravação atual sem salvar';

  @override
  String get runResumeA11yLabel => 'Retomar corrida';

  @override
  String get runPauseA11yLabel => 'Pausar corrida';

  @override
  String get runResumeA11yHint => 'Retoma a gravação pausada';

  @override
  String get runPauseA11yHint => 'Pausa a gravação sem encerrá-la';

  @override
  String get runMarkLapA11yLabel => 'Marcar volta';

  @override
  String runMarkLapWithCountA11yLabel(int count) {
    return 'Marcar volta, $count até agora';
  }

  @override
  String get runMarkLapA11yHint => 'Registra o parcial atual';

  @override
  String get runCollapseStatsPanel => 'Recolher painel de estatísticas';

  @override
  String get runExpandStatsPanel => 'Expandir painel de estatísticas';

  @override
  String runRouteRemaining(String distance) {
    return 'faltam $distance';
  }

  @override
  String runOffRoute(int metres) {
    return 'Fora da rota — a $metres m';
  }

  @override
  String get runPermissionRevoked => 'Permissão de localização revogada';

  @override
  String get runGpsLost => 'Sinal de GPS perdido — vá para um local aberto';

  @override
  String get runWeakGps => 'GPS fraco — distância pausada';

  @override
  String get runA11yStarted => 'Corrida iniciada';

  @override
  String get runA11yResumed => 'Corrida retomada';

  @override
  String get runA11yPaused => 'Corrida pausada';

  @override
  String get runA11yFinished => 'Corrida finalizada';

  @override
  String runLapMarked(int count) {
    return 'Volta $count marcada';
  }

  @override
  String get runDiscardDialogTitle => 'Descartar corrida?';

  @override
  String get runDiscardDialogBody => 'Seu progresso será perdido.';

  @override
  String get runKeepRunning => 'Continuar correndo';

  @override
  String get runDiscard => 'Descartar';

  @override
  String get runStartWorkout => 'Iniciar treino';

  @override
  String get runStartWorkoutSubtitle =>
      'Corra com metas de etapa ao vivo, avisos de áudio e uma análise de planejado vs. realizado.';

  @override
  String get runViewWorkoutDetails => 'Ver detalhes';

  @override
  String get runWorkoutNoStructure =>
      'Este treino não tem uma estrutura executável.';

  @override
  String runWorkoutLoaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etapas',
      one: '$count etapa',
    );
    return 'Treino carregado · $_temp0 — toque em GO para iniciar';
  }

  @override
  String get runAbandonWorkoutTitle => 'Abandonar treino?';

  @override
  String get runAbandonWorkoutBody =>
      'O plano estruturado termina aqui; a gravação continua como corrida livre. Você pode parar a qualquer momento para salvar o que fez.';

  @override
  String get runCancel => 'Cancelar';

  @override
  String get runAbandon => 'Abandonar';

  @override
  String get runNoRoutesSaved =>
      'Nenhuma rota salva. Importe uma na aba Rotas.';

  @override
  String get runNotificationsOffHint =>
      'As notificações estão desativadas — a notificação de corrida ao vivo não aparecerá. A gravação continua funcionando.';

  @override
  String get runSettings => 'Configurações';

  @override
  String get runStartAnyway => 'Iniciar mesmo assim';

  @override
  String get runOpenSettings => 'Abrir configurações';

  @override
  String get runNotNow => 'Agora não';

  @override
  String get runShareSubject => 'Me acompanhe ao vivo';

  @override
  String runCouldNotShareLink(String error) {
    return 'Não foi possível compartilhar o link ao vivo: $error';
  }

  @override
  String get runHrStrapLostReconnecting =>
      'Cinta cardíaca perdida — reconectando…';

  @override
  String get runHrStrapReconnected => 'Cinta cardíaca reconectada';

  @override
  String get runHrStrapLostNoHr =>
      'Cinta cardíaca perdida — a gravação continua sem FC.';

  @override
  String get runHrStrapNotFound =>
      'Cinta cardíaca não encontrada — coloque-a e reconecte.';

  @override
  String get runReconnect => 'Reconectar';

  @override
  String get runHrStrapStillNotFound =>
      'Ainda sem cinta — a gravação continua sem FC.';

  @override
  String get runSaveFailedRelaunch =>
      'Não foi possível salvar localmente. Reinicie o app para recuperar.';

  @override
  String get runSyncFailedSaveOffline =>
      'Salva offline. Sincronize em Corridas.';

  @override
  String get runSavedOffline => 'Salva offline.';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings =>
      'Sem GPS — o rastreamento começará quando a Localização estiver ativada.';

  @override
  String get runGpsBlockedSettings =>
      'Sem GPS — permissão bloqueada. Ative-a para rastrear a rota.';

  @override
  String get runGpsPermissionPending =>
      'Sem GPS — o rastreamento começará quando a permissão for concedida.';

  @override
  String get runGpsAllowAllTheTime =>
      'Defina a Localização como \"Permitir o tempo todo\" — as corridas param de gravar quando você troca de app sem permissão em segundo plano.';

  @override
  String get runGpsSensorFailed =>
      'Gravando sem GPS — não foi possível iniciar o sensor.';

  @override
  String get runAgoJustNow => 'Agora mesmo';

  @override
  String runAgoMinutes(int count) {
    return 'há $count min';
  }

  @override
  String runAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count horas',
      one: 'há 1 hora',
    );
    return '$_temp0';
  }

  @override
  String get runAgoYesterday => 'Ontem';

  @override
  String runAgoDays(int count) {
    return 'há $count dias';
  }

  @override
  String runAgoWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count semanas',
      one: 'há 1 semana',
    );
    return '$_temp0';
  }

  @override
  String runAgoMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count meses',
      one: 'há 1 mês',
    );
    return '$_temp0';
  }

  @override
  String get runWorkoutAbandonedBand => 'Treino abandonado · correndo livre';

  @override
  String get runWorkoutCompleteBand =>
      'Treino concluído · toque em parar para salvar';

  @override
  String runWorkoutStepHeader(String label, String target, String pace) {
    return '$label · $target @ $pace';
  }

  @override
  String runWorkoutStepCounter(int current, int total) {
    return '$current/$total';
  }

  @override
  String get runWorkoutRewind => 'Voltar';

  @override
  String get runWorkoutSkip => 'Pular';

  @override
  String get runWorkoutAbandon => 'Abandonar';

  @override
  String runWorkoutRemainingYards(int yards) {
    return 'faltam $yards yd';
  }

  @override
  String runWorkoutRemainingMetres(int metres) {
    return 'faltam $metres m';
  }

  @override
  String runWorkoutRemainingDuration(String duration) {
    return 'faltam $duration';
  }
}
