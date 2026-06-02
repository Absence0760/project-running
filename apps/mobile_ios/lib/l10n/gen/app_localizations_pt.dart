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

  @override
  String get runsRangeToday => 'Hoje';

  @override
  String get runsRangeWeek => 'Esta semana';

  @override
  String get runsRangeMonth => 'Últimos 30 dias';

  @override
  String get runsRangeYear => 'Este ano';

  @override
  String get runsRangeAll => 'Todo o histórico';

  @override
  String get runsRangeCustom => 'Personalizado…';

  @override
  String runsRangeFrom(String date) {
    return 'A partir de $date';
  }

  @override
  String runsRangeUntil(String date) {
    return 'Até $date';
  }

  @override
  String runsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get runsDateRangeTooltip => 'Período';

  @override
  String get runsSortTooltip => 'Ordenar';

  @override
  String get runsSortNewest => 'Mais recentes primeiro';

  @override
  String get runsSortOldest => 'Mais antigas primeiro';

  @override
  String get runsSortLongest => 'Maior distância';

  @override
  String get runsSortFastest => 'Melhor ritmo';

  @override
  String runsSyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizar $count corridas',
      one: 'Sincronizar $count corrida',
    );
    return '$_temp0';
  }

  @override
  String get runsRefreshTooltip => 'Atualizar da nuvem';

  @override
  String get runsOfflineTooltip => 'Offline';

  @override
  String runsSelectionTitle(int count) {
    return '$count selecionadas';
  }

  @override
  String get runsSelectAllTooltip => 'Selecionar tudo';

  @override
  String get runsClearSelectionTooltip => 'Limpar';

  @override
  String get runsDeleteTooltip => 'Excluir';

  @override
  String get runsCancelTooltip => 'Cancelar';

  @override
  String get runsAddRun => 'Adicionar corrida';

  @override
  String get runsAddRunTooltip => 'Adicionar uma corrida manualmente';

  @override
  String runsLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get runsNoMatch => 'Nenhuma corrida corresponde a estes filtros';

  @override
  String get runsClearFilters => 'Limpar filtros';

  @override
  String get runsEmptyTitle => 'Ainda não há corridas';

  @override
  String get runsEmptyBody =>
      'Toque na aba Correr para iniciar sua primeira corrida';

  @override
  String get runsFilterAll => 'Todas';

  @override
  String get runsSourceAll => 'Todas as fontes';

  @override
  String runsSourceLabel(String source) {
    return 'Fonte: $source';
  }

  @override
  String get runsSourceFilterTooltip => 'Filtrar por fonte';

  @override
  String get runsSourceRecorded => 'Gravada';

  @override
  String get runsSourceWatch => 'Relógio';

  @override
  String get runsSourceStrava => 'Strava';

  @override
  String get runsSourceParkrun => 'parkrun';

  @override
  String get runsSourceHealthKit => 'HealthKit';

  @override
  String get runsSourceHealthConnect => 'Health Connect';

  @override
  String get runsRangePickerTitle => 'Selecionar datas';

  @override
  String get runsRangeStart => 'Início';

  @override
  String get runsRangeEnd => 'Fim';

  @override
  String get runsRangeTapDate => 'Toque em uma data';

  @override
  String get runsRangeApply => 'Aplicar';

  @override
  String get runsRangeClear => 'Limpar';

  @override
  String get runsPrevMonth => 'Mês anterior';

  @override
  String get runsNextMonth => 'Próximo mês';

  @override
  String get runsPrevYear => 'Ano anterior';

  @override
  String get runsNextYear => 'Próximo ano';

  @override
  String runsDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count corridas?',
      one: 'Excluir $count corrida?',
    );
    return '$_temp0';
  }

  @override
  String get runsDeleteConfirmBody => 'Isso não pode ser desfeito.';

  @override
  String get runsCancel => 'Cancelar';

  @override
  String get runsDelete => 'Excluir';

  @override
  String get runsQueuedToSync => 'Na fila para sincronizar';

  @override
  String get runsSignInToSync =>
      'Entre nas configurações para sincronizar as corridas';

  @override
  String get runsRefreshFailed =>
      'Não foi possível atualizar — verifique sua conexão';

  @override
  String get runsLoadMoreFailed => 'Não foi possível carregar mais corridas';

  @override
  String runsSyncPartial(int synced, int total, String error) {
    return '$synced/$total sincronizadas. Erro: $error';
  }

  @override
  String runsSyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count corridas não conseguiram enviar seu trajeto de GPS — o restante foi sincronizado. As corridas com falha serão tentadas novamente no próximo ciclo.',
      one:
          '$count corrida não conseguiu enviar seu trajeto de GPS — o restante foi sincronizado. Será tentado novamente no próximo ciclo.',
    );
    return '$_temp0';
  }

  @override
  String runsSyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Todas as $count corridas sincronizadas',
      one: '$count corrida sincronizada',
    );
    return '$_temp0';
  }

  @override
  String runsDeletePartial(int deleted, int queued) {
    return '$deleted excluídas; $queued na fila — será tentado novamente quando você estiver online.';
  }

  @override
  String runsDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas excluídas',
      one: '$count corrida excluída',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'Adicionar corrida';

  @override
  String get addRunSave => 'Salvar';

  @override
  String get addRunSectionWhen => 'Quando';

  @override
  String get addRunSectionActivity => 'Atividade';

  @override
  String get addRunSectionRoute => 'Rota (opcional)';

  @override
  String get addRunSectionDistance => 'Distância';

  @override
  String get addRunSectionDuration => 'Duração';

  @override
  String get addRunSectionTitle => 'Título (opcional)';

  @override
  String get addRunSectionNotes => 'Notas (opcional)';

  @override
  String get addRunClearRoute => 'Remover rota';

  @override
  String get addRunSearchRoutes => 'Buscar rotas salvas';

  @override
  String get addRunNoRoutes =>
      'Ainda não há rotas salvas — crie ou importe uma para anexá-la aqui';

  @override
  String get addRunDistanceInvalid => 'Insira uma distância maior que 0';

  @override
  String get addRunDurationInvalid => 'Insira uma duração';

  @override
  String get addRunTitleHint => 'ex.: Volta do almoço';

  @override
  String get addRunNotesHint => 'Como foi?';

  @override
  String get addRunSaveButton => 'Salvar corrida';

  @override
  String addRunSaveFailed(String error) {
    return 'Falha ao salvar a corrida: $error';
  }

  @override
  String get addRunSaved => 'Corrida adicionada ao histórico';

  @override
  String get addRunPickerSearchHint => 'Buscar rotas';

  @override
  String get addRunPickerClear => 'Limpar';

  @override
  String get addRunPickerCancel => 'Cancelar';

  @override
  String addRunPickerNoMatch(String query) {
    return 'Nenhuma rota corresponde a \"$query\"';
  }

  @override
  String get addRunPickerNoRoute => 'Sem rota';

  @override
  String get runDetailDnfBadge => 'DNF';

  @override
  String get runDetailEditTooltip => 'Editar corrida';

  @override
  String get runDetailShareTooltip => 'Compartilhar corrida';

  @override
  String get runDetailMoreTooltip => 'Mais';

  @override
  String get runDetailSaveAsRoute => 'Salvar como rota';

  @override
  String get runDetailDeleteRun => 'Excluir corrida';

  @override
  String get runDetailEditTitle => 'Editar corrida';

  @override
  String get runDetailFieldTitle => 'Título';

  @override
  String get runDetailFieldNotes => 'Notas';

  @override
  String get runDetailFieldDistance => 'Distância';

  @override
  String get runDetailFieldDuration => 'Duração';

  @override
  String get runDetailMarkDnf => 'Marcar como DNF';

  @override
  String get runDetailMarkDnfSubtitle =>
      'Exclui esta corrida dos recordes pessoais';

  @override
  String get runDetailEditInvalid => 'Insira uma distância e duração válidas';

  @override
  String get runDetailSave => 'Salvar';

  @override
  String get runDetailCancel => 'Cancelar';

  @override
  String get runDetailDelete => 'Excluir';

  @override
  String get runDetailLoadingGps => 'Carregando dados de GPS...';

  @override
  String get runDetailGpsUnavailable => 'Trajeto de GPS indisponível offline';

  @override
  String get runDetailPauseReplay => 'Pausar reprodução';

  @override
  String get runDetailReplay => 'Reproduzir esta corrida';

  @override
  String get runDetailStatElevGain => 'Ganho de elev.';

  @override
  String get runDetailStatElevLoss => 'Perda de elev.';

  @override
  String get runDetailStatAvgHr => 'FC média';

  @override
  String get runDetailStatAgeGrade => 'Índice por idade';

  @override
  String get runDetailSectionElevation => 'Elevação';

  @override
  String get runDetailSectionLaps => 'Voltas';

  @override
  String runDetailLapNumber(int number) {
    return 'Volta $number';
  }

  @override
  String get runDetailSectionRunningDynamics => 'Dinâmica de corrida';

  @override
  String get runDetailDynVerticalOsc => 'Oscilação vertical';

  @override
  String get runDetailDynGroundContact => 'Contato com o solo';

  @override
  String get runDetailDynStrideLength => 'Comprimento da passada';

  @override
  String get runDetailDynAvgPower => 'Potência média';

  @override
  String get runDetailSectionRouteHistory => 'Histórico da rota';

  @override
  String get runDetailThisRoute => 'esta rota';

  @override
  String runDetailPersonalBest(String route) {
    return 'Recorde pessoal em $route';
  }

  @override
  String runDetailBehindPb(String delta) {
    return '$delta atrás do recorde';
  }

  @override
  String runDetailAttemptOf(int rank, int total, String pb) {
    return 'Tentativa $rank de $total  —  Recorde: $pb';
  }

  @override
  String get runDetailSectionBestEfforts => 'Melhores marcas';

  @override
  String get runDetailSectionHeartRateZones => 'Zonas de frequência cardíaca';

  @override
  String get runDetailHrAvg => 'Média';

  @override
  String get runDetailHrMin => 'Mín';

  @override
  String get runDetailHrMax => 'Máx';

  @override
  String runDetailZoneRow(int number, String label) {
    return 'Zona $number · $label';
  }

  @override
  String get runDetailSectionSplits => 'Parciais';

  @override
  String get runDetailNoGpsForSplits => 'Sem dados de GPS para os parciais';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Corrida curta demais para um parcial completo de $unit';
  }

  @override
  String get runDetailSectionSegments => 'Segmentos';

  @override
  String get runDetailSaveAsRouteTitle => 'Salvar como rota';

  @override
  String get runDetailSaveAsRouteBody =>
      'Salve este trajeto de GPS como uma rota que você pode seguir novamente.';

  @override
  String get runDetailRouteNameLabel => 'Nome da rota';

  @override
  String get runDetailNoTrackToSave =>
      'Esta corrida não tem trajeto de GPS para salvar como rota';

  @override
  String runDetailRouteLinked(String route) {
    return 'Vinculada a $route';
  }

  @override
  String get runDetailRouteLinkFailed => 'Não foi possível vincular a rota';

  @override
  String get runDetailReSnapping => 'Reajustando às ruas…';

  @override
  String runDetailRematchFailed(String error) {
    return 'Falha no reajuste: $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return '\"$name\" salva — $kept pontos de passagem ($smoothed suavizados)';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'Não foi possível tornar a corrida pública: $error';
  }

  @override
  String get runDetailMakePublicTitle => 'Tornar esta corrida pública?';

  @override
  String get runDetailMakePublicBodyZone =>
      'Compartilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la. Esta corrida começa ou termina dentro de uma das suas zonas de privacidade, então quem visualizar verá um trajeto recortado com os trechos dentro da zona ocultos.';

  @override
  String get runDetailMakePublicBodyHasZones =>
      'Compartilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la. Nenhuma das suas zonas de privacidade cruza este trajeto, então o trajeto completo ficará visível.';

  @override
  String get runDetailMakePublicBodyNoZones =>
      'Compartilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la — incluindo os pontos de início e fim da sua corrida. Você não tem zonas de privacidade configuradas. Considere adicionar uma ao redor da sua casa antes de compartilhar.';

  @override
  String get runDetailMakePublic => 'Tornar pública';

  @override
  String get runDetailDeleteTitle => 'Excluir corrida?';

  @override
  String get runDetailDeleteBody => 'Isso não pode ser desfeito.';

  @override
  String get runDetailSuggestLink => 'Vincular';

  @override
  String get runDetailSuggestDismiss => 'Dispensar';

  @override
  String get runDetailSuggestRanRoute => 'Parece que você correu ';

  @override
  String get runDetailSuggestLinkPrompt => 'Vincular esta corrida a essa rota?';

  @override
  String get runDetailMatchPending => 'Ajustando às ruas…';

  @override
  String get runDetailMatchSkipped => 'Não ajustada (poucos pontos)';

  @override
  String get runDetailMatchFailed =>
      'Falha no ajuste — exibindo o trajeto bruto';

  @override
  String get runDetailMatchMatched => 'Ajustada';

  @override
  String get runDetailRematchQueueing => 'Adicionando à fila…';

  @override
  String get runDetailRematch => 'Reajustar';

  @override
  String get runDetailSegStatDistance => 'Distância';

  @override
  String get runDetailSegStatTime => 'Tempo';

  @override
  String get runDetailSegStatPace => 'Ritmo';

  @override
  String get runDetailSegStatHr => 'FC';

  @override
  String get runDetailSegStatGain => 'Ganho';

  @override
  String get runDetailSegDismiss => 'Dispensar';

  @override
  String get publicRunTitle => 'Corrida';

  @override
  String get publicRunLoadError => 'Não foi possível carregar esta corrida.';

  @override
  String get publicRunUnavailable =>
      'Esta corrida é privada ou não está mais disponível.';

  @override
  String get publicRunAuthorFallback => 'Corredor';

  @override
  String get publicRunStatDistance => 'Distância';

  @override
  String get publicRunStatTime => 'Tempo';

  @override
  String get publicRunStatPace => 'Ritmo';

  @override
  String get publicRunSectionSegments => 'Segmentos';

  @override
  String get routesSyncFailedOffline =>
      'Não foi possível sincronizar as rotas — trabalhando offline';

  @override
  String get routesLoadMoreFailed => 'Não foi possível carregar mais rotas';

  @override
  String routesStarUpdateFailed(String error) {
    return 'Não foi possível atualizar a estrela: $error';
  }

  @override
  String get routesImportFailedLocalOnly =>
      'Falha na importação: escolha o arquivo do armazenamento local, não de um seletor de documentos apenas na nuvem.';

  @override
  String routesImported(String name) {
    return '\"$name\" importada';
  }

  @override
  String routesImportFailed(String error) {
    return 'Falha na importação: $error';
  }

  @override
  String routesSaved(String name) {
    return '\"$name\" salva';
  }

  @override
  String get routesEmptyTitle => 'Nenhuma rota ainda';

  @override
  String get routesEmptyBody =>
      'Toque em Criar para desenhar uma rota no mapa ou importe um arquivo GPX, KML ou TCX.';

  @override
  String get routesBuild => 'Criar';

  @override
  String get routesImport => 'Importar';

  @override
  String get routesNoMatch => 'Nenhuma rota corresponde a esses filtros';

  @override
  String get routesClearFilters => 'Limpar filtros';

  @override
  String routesLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get routesQueuedToSync => 'Na fila para sincronizar';

  @override
  String get routesSavedForOffline => 'Salvo para uso offline';

  @override
  String get routesUnstarRoute => 'Remover estrela da rota';

  @override
  String get routesStarForWatch => 'Marcar para mostrar no relógio';

  @override
  String get routesDiscover => 'Descobrir';

  @override
  String get routesSyncFromCloud => 'Sincronizar da nuvem';

  @override
  String get routesPublicRoutes => 'Rotas públicas';

  @override
  String get routesHeatmap => 'Mapa de calor';

  @override
  String get routesExplorePublic => 'Explorar rotas públicas';

  @override
  String get routesHeatmapTooltip => 'Mapa de calor das rotas';

  @override
  String get routesSearchHint => 'Buscar rotas por nome…';

  @override
  String get routesClearSearch => 'Limpar busca';

  @override
  String get routesStarred => 'Com estrela';

  @override
  String routesCountMeta(int visible, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$visible de $total rotas',
      one: '$visible de $total rota',
    );
    return '$_temp0';
  }

  @override
  String get routesSurfaceAny => 'Qualquer superfície';

  @override
  String get routesSurfaceRoad => 'Estrada';

  @override
  String get routesSurfaceTrail => 'Trilha';

  @override
  String get routesSurfaceMixed => 'Mista';

  @override
  String get routesDistanceAny => 'Qualquer distância';

  @override
  String get routesSortNewest => 'Mais recentes primeiro';

  @override
  String get routesSortLongest => 'Mais longa';

  @override
  String get routesSortShortest => 'Mais curta';

  @override
  String get routesSortMostRun => 'Mais percorrida';

  @override
  String get routesSortAlpha => 'A–Z';

  @override
  String routesDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count rotas?',
      one: 'Excluir $count rota?',
    );
    return '$_temp0';
  }

  @override
  String get routesDeleteConfirmBody => 'Isso não pode ser desfeito.';

  @override
  String routesSelectionTitle(int count) {
    return '$count selecionada(s)';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted excluída(s); $failed com falha — verifique sua conexão.';
  }

  @override
  String routesDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rotas excluídas.',
      one: '$count rota excluída.',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteCleared => 'Rota limpa';

  @override
  String routeBuilderPointsSummary(int count, String distance) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pontos, $distance',
      one: '$count ponto, $distance',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteFailedStraightLines =>
      'Não foi possível traçar — mostrando linhas retas entre seus pontos.';

  @override
  String routeBuilderSegmentsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count segmentos não puderam se ajustar a uma via. Arraste os pinos afetados para ajustar.',
      one:
          '$count segmento não pôde se ajustar a uma via. Arraste o pino afetado para ajustar.',
    );
    return '$_temp0';
  }

  @override
  String routeBuilderRoutingFailed(String error) {
    return 'Falha ao traçar a rota: $error';
  }

  @override
  String get routeBuilderTooCloseToPin =>
      'Muito perto de outro pino — arraste um pouco mais longe.';

  @override
  String get routeBuilderPinAlreadyThere =>
      'Já há um pino aqui — toque mais distante para adicionar outro.';

  @override
  String get routeBuilderTargetTooLong =>
      'Insira uma distância alvo de até 1000 km.';

  @override
  String get routeBuilderSaveNeedTwo =>
      'Coloque pelo menos dois pontos primeiro.';

  @override
  String routeBuilderSavedLocally(String detail) {
    return 'Salvo localmente. $detail Será sincronizado da próxima vez.';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'Não foi possível acessar o servidor. Faça login ou verifique sua conexão e tente novamente.';

  @override
  String routeBuilderSaveFailed(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get routeBuilderSearchHint => 'Pesquisar lugares…';

  @override
  String get routeBuilderMore => 'Mais';

  @override
  String get routeBuilderGenerateLoop => 'Gerar circuito';

  @override
  String get routeBuilderUndo => 'Desfazer';

  @override
  String get routeBuilderClear => 'Limpar';

  @override
  String get routeBuilderSaving => 'Salvando…';

  @override
  String get routeBuilderSave => 'Salvar';

  @override
  String get routeBuilderLocateMe => 'Localizar-me';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'Toque para mover o ponto $number, ou use os ícones';
  }

  @override
  String routeBuilderEmptyHint(String mode) {
    return 'Toque no mapa para colocar pontos · $mode';
  }

  @override
  String routeBuilderOnePointHint(String mode) {
    return 'Coloque outro para traçar a linha · $mode';
  }

  @override
  String routeBuilderStatusGain(String distance, int gain, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pontos',
      one: '$count ponto',
    );
    return '$distance · $gain m ↑ · $_temp0';
  }

  @override
  String routeBuilderStatusNoGain(String distance, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pontos',
      one: '$count ponto',
    );
    return '$distance · $_temp0';
  }

  @override
  String routeBuilderDeletePoint(int number) {
    return 'Excluir o ponto $number';
  }

  @override
  String get routeBuilderCancelDrag => 'Cancelar arrasto';

  @override
  String get routeBuilderModeTrail => 'Trilha';

  @override
  String get routeBuilderModeRoad => 'Estrada';

  @override
  String get routeBuilderModeStraight => 'Reta';

  @override
  String get routeBuilderLoopDialogBody =>
      'Distância alvo — criaremos um circuito radial em torno do centro atual do mapa.';

  @override
  String get routeBuilderCancel => 'Cancelar';

  @override
  String get routeBuilderGenerate => 'Gerar';

  @override
  String get routeBuilderSaveDialogTitle => 'Salvar rota';

  @override
  String get routeBuilderNameLabel => 'Nome';

  @override
  String get routeBuilderNameHint => 'ex.: Circuito do rio';

  @override
  String get routeBuilderDescriptionLabel => 'Descrição (opcional)';

  @override
  String get routeBuilderDescriptionHint =>
      'Superfície, subidas, estacionamento, qualquer coisa que valha a pena anotar';

  @override
  String get routeBuilderSaveToLabel => 'Salvar em';

  @override
  String get routeBuilderSaveToPersonal => 'Pessoal';

  @override
  String get routeBuilderMakePublic => 'Tornar pública';

  @override
  String get routeBuilderMakePublicSubtitle =>
      'Outros podem encontrá-la em Descobrir';

  @override
  String get routeDetailStartRun => 'Iniciar corrida';

  @override
  String get routeDetailShare => 'Compartilhar';

  @override
  String get routeDetailShareAsImage => 'Compartilhar como imagem';

  @override
  String get routeDetailShareAsGpx => 'Compartilhar como GPX';

  @override
  String get routeDetailShareAsKml => 'Compartilhar como KML';

  @override
  String get routeDetailRemoveOfflineSave => 'Remover salvamento offline';

  @override
  String get routeDetailSaveForOffline => 'Salvar para uso offline';

  @override
  String get routeDetailUnstarRoute => 'Remover estrela da rota';

  @override
  String get routeDetailStarForWatch => 'Marcar para mostrar no relógio';

  @override
  String get routeDetailMakePrivate => 'Tornar privada';

  @override
  String get routeDetailMakePublic => 'Tornar pública';

  @override
  String get routeDetailRemoveBookmark => 'Remover marcador';

  @override
  String get routeDetailBookmarkRoute => 'Marcar rota';

  @override
  String get routeDetailReportRoute => 'Denunciar rota';

  @override
  String get routeDetailTransferToClub => 'Transferir para clube';

  @override
  String get routeDetailManageClub => 'Desanexar ou mover para outro clube';

  @override
  String get routeDetailDeleteRoute => 'Excluir rota';

  @override
  String get routeDetailStatDistance => 'Distância';

  @override
  String get routeDetailStatElevation => 'Elevação';

  @override
  String routeDetailStatReviews(int count) {
    return '$count avaliações';
  }

  @override
  String get routeDetailStatWaypoints => 'Pontos';

  @override
  String get routeDetailPublicRoute => 'Rota pública';

  @override
  String get routeDetailPrivateRoute => 'Rota privada';

  @override
  String get routeDetailPublicSubtitle =>
      'Qualquer pessoa com o link de compartilhamento pode ver esta rota';

  @override
  String get routeDetailPrivateSubtitle => 'Apenas você pode ver esta rota';

  @override
  String get routeDetailSavedForOffline => 'Salvo para uso offline';

  @override
  String get routeDetailSaveForOfflineTitle => 'Salvar para uso offline';

  @override
  String get routeDetailOfflinePinnedSubtitle =>
      'A rota fica neste telefone para você percorrê-la sem conexão.';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'Mantenha esta rota no seu telefone para usar sem rede.';

  @override
  String get routeDetailDescriptionHeading => 'Descrição';

  @override
  String routeDetailRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get routeDetailFeatured => 'Destaque';

  @override
  String get routeDetailSurfaceTrail => 'TRILHA';

  @override
  String get routeDetailSurfaceMixed => 'MISTA';

  @override
  String get routeDetailSurfaceRoad => 'ESTRADA';

  @override
  String get routeDetailAddTagHint => 'adicionar etiqueta';

  @override
  String get routeDetailReviewsHeading => 'Avaliações';

  @override
  String get routeDetailRate => 'Avaliar';

  @override
  String get routeDetailReviewsOffline => 'Avaliações indisponíveis offline';

  @override
  String get routeDetailNoReviews => 'Nenhuma avaliação ainda';

  @override
  String get routeDetailRateDialogTitle => 'Avaliar esta rota';

  @override
  String get routeDetailCommentLabel => 'Comentário (opcional)';

  @override
  String get routeDetailCancel => 'Cancelar';

  @override
  String get routeDetailSubmit => 'Enviar';

  @override
  String get routeDetailSignInToReview =>
      'Faça login para deixar uma avaliação';

  @override
  String routeDetailReviewFailed(String error) {
    return 'Falha ao enviar avaliação: $error';
  }

  @override
  String routeDetailBookmarkFailed(String error) {
    return 'Falha ao marcar: $error';
  }

  @override
  String get routeDetailPublicWillSync =>
      'Rota definida como pública. Será sincronizada da próxima vez.';

  @override
  String get routeDetailPrivateWillSync =>
      'Rota definida como privada. Será sincronizada da próxima vez.';

  @override
  String routeDetailVisibilityFailed(String error) {
    return 'Não foi possível atualizar a visibilidade: $error';
  }

  @override
  String routeDetailStarFailed(String error) {
    return 'Não foi possível atualizar a estrela: $error';
  }

  @override
  String get routeDetailOfflineSaved => 'Salvo para uso offline.';

  @override
  String get routeDetailOfflineRemoved => 'Removido dos salvamentos offline.';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'Não foi possível salvar a etiqueta: $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return 'Não foi possível compartilhar $format: $error';
  }

  @override
  String get routeDetailClubsLoadTimeout =>
      'Não foi possível carregar seus clubes — verifique sua rede.';

  @override
  String get routeDetailClubsLoadFailed =>
      'Não foi possível carregar seus clubes.';

  @override
  String get routeDetailDetached =>
      'Desanexada do clube; a rota agora é pessoal.';

  @override
  String get routeDetailMovedToClub =>
      'Rota movida para a biblioteca do clube.';

  @override
  String routeDetailTransferFailed(String error) {
    return 'Falha na transferência: $error';
  }

  @override
  String get routeDetailDeleteTitle => 'Excluir rota?';

  @override
  String get routeDetailDeleteBody => 'Isso não pode ser desfeito.';

  @override
  String get routeDetailDelete => 'Excluir';

  @override
  String routeDetailDeleteFailed(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get routeDetailPreview => 'Pré-visualização';

  @override
  String get routeDetailPreviewStart => 'Início';

  @override
  String get routeDetailPreviewFinish => 'Chegada';

  @override
  String get routeDetailTransferDialogTitle => 'Transferir para clube';

  @override
  String get routeDetailManageClubTitle => 'Gerenciar propriedade do clube';

  @override
  String get routeDetailTransferDialogBody =>
      'Os membros do clube verão esta rota na biblioteca do clube e poderão adotá-la em seus planos.';

  @override
  String get routeDetailManageClubBody =>
      'Mova esta rota para outro clube que você administra, ou desanexe-a de volta para pessoal.';

  @override
  String get routeDetailDetachToPersonal => 'Desanexar para pessoal';

  @override
  String get routeDetailDetachSubtitle =>
      'Remove a rota da biblioteca do clube atual.';

  @override
  String get routeDetailNoAdminClubs =>
      'Você ainda não possui nem administra nenhum clube.';

  @override
  String get routeDetailCurrentClub => 'Clube atual';

  @override
  String routeDetailClubMemberCount(String location, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros',
      one: '$count membro',
    );
    return '$location · $_temp0';
  }

  @override
  String get exploreRoutesTitle => 'Explorar rotas';

  @override
  String get exploreRoutesModeSearch => 'Buscar';

  @override
  String get exploreRoutesModeNearMe => 'Perto de mim';

  @override
  String get exploreRoutesSearchHint => 'Buscar rotas por nome...';

  @override
  String get exploreRoutesFeatured => 'Destaque';

  @override
  String get exploreRoutesSignInRequired =>
      'Faça login e conecte-se à internet para explorar rotas';

  @override
  String get exploreRoutesTimeout =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String get exploreRoutesSearchFailed =>
      'Falha na busca. Toque em Tentar novamente.';

  @override
  String get exploreRoutesLoadMoreFailed =>
      'Não foi possível carregar mais — verifique sua conexão';

  @override
  String get exploreRoutesLocationPermissionRequired =>
      'Permissão de localização necessária para encontrar rotas próximas';

  @override
  String get exploreRoutesNearbyFailed =>
      'Não foi possível encontrar rotas próximas. Toque em Tentar novamente.';

  @override
  String get exploreRoutesEmptyNoPublic => 'Nenhuma rota pública ainda';

  @override
  String get exploreRoutesEmptyNoMatch =>
      'Nenhuma rota corresponde à sua busca';

  @override
  String get exploreRoutesEmptyBody =>
      'As rotas compartilhadas pelo app web aparecem aqui';

  @override
  String get exploreRoutesDistanceAny => 'Qualquer distância';

  @override
  String get exploreRoutesSurfaceAny => 'Qualquer superfície';

  @override
  String get exploreRoutesSurfaceRoad => 'Estrada';

  @override
  String get exploreRoutesSurfaceTrail => 'Trilha';

  @override
  String get exploreRoutesSurfaceMixed => 'Mista';

  @override
  String get exploreRoutesSortMostRun => 'Mais percorridas';

  @override
  String get exploreRoutesSortNewest => 'Mais recentes';

  @override
  String get exploreRoutesSortFeatured => 'Destaque';

  @override
  String get exploreRoutesSort => 'Ordenar';

  @override
  String exploreRoutesSaveCheckConnection(String name) {
    return 'Não foi possível salvar \"$name\" — verifique sua conexão e tente novamente.';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return 'Não foi possível salvar \"$name\".';
  }

  @override
  String exploreRoutesSaved(String name) {
    return '\"$name\" salva na sua biblioteca';
  }

  @override
  String get exploreRoutesAlreadySaved => 'Já salva';

  @override
  String get exploreRoutesSaveToLibrary => 'Salvar na biblioteca';

  @override
  String get exploreRoutesSurfaceTrailShort => 'Trilha';

  @override
  String get exploreRoutesSurfaceMixedShort => 'Mista';

  @override
  String get exploreRoutesSurfaceRoadShort => 'Estrada';

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
  String get heatmapSearchHint => 'Pesquisar lugares…';

  @override
  String get heatmapFilters => 'Filtros';

  @override
  String heatmapRoutesStartHere(int count) {
    return '$count rotas começam aqui';
  }

  @override
  String heatmapRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rotas',
      one: '$count rota',
    );
    return '$_temp0';
  }

  @override
  String get heatmapNoRoutesHere => 'Nenhuma rota aqui';

  @override
  String get heatmapNoRoutesHint =>
      'Nenhuma rota aqui. Mova o mapa ou altere os filtros.';

  @override
  String heatmapClearKept(int count) {
    return 'Limpar $count mantida(s)';
  }

  @override
  String get heatmapUnpinFromMap => 'Desafixar do mapa';

  @override
  String get heatmapKeepOnMap => 'Manter no mapa';

  @override
  String get heatmapLocateMe => 'Localizar-me';

  @override
  String heatmapLocationUnavailable(String error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get heatmapBackToList => 'Voltar à lista';

  @override
  String get heatmapViewRoute => 'Ver rota';

  @override
  String get heatmapKept => 'Mantida';

  @override
  String get heatmapKeep => 'Manter';

  @override
  String get heatmapLensShow => 'Mostrar';

  @override
  String get heatmapLensDistance => 'Distância';

  @override
  String get heatmapLensMap => 'Mapa';

  @override
  String get heatmapHeatDensity => 'Densidade de calor';

  @override
  String get heatmapResetFilters => 'Redefinir filtros';

  @override
  String get heatmapLensPopular => 'Populares';

  @override
  String get heatmapLensFriends => 'Amigos';

  @override
  String get heatmapLensFeatured => 'Destaque';

  @override
  String get heatmapLensHiddenGems => 'Joias escondidas';

  @override
  String get publicRouteFallbackTitle => 'Rota';

  @override
  String get publicRouteLoadError => 'Não foi possível carregar esta rota.';

  @override
  String get publicRouteUnavailable =>
      'Esta rota é privada ou não está mais disponível.';

  @override
  String get publicRouteStatDistance => 'Distância';

  @override
  String get publicRouteStatElevation => 'Elevação';

  @override
  String get publicRouteStatWaypoints => 'Pontos';

  @override
  String get routesLoadErrorRetry =>
      'Não foi possível carregar suas rotas. Verifique sua conexão e tente novamente.';
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

  @override
  String get runsRangeToday => 'Hoje';

  @override
  String get runsRangeWeek => 'Esta semana';

  @override
  String get runsRangeMonth => 'Últimos 30 dias';

  @override
  String get runsRangeYear => 'Este ano';

  @override
  String get runsRangeAll => 'Todo o histórico';

  @override
  String get runsRangeCustom => 'Personalizado…';

  @override
  String runsRangeFrom(String date) {
    return 'A partir de $date';
  }

  @override
  String runsRangeUntil(String date) {
    return 'Até $date';
  }

  @override
  String runsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get runsDateRangeTooltip => 'Período';

  @override
  String get runsSortTooltip => 'Ordenar';

  @override
  String get runsSortNewest => 'Mais recentes primeiro';

  @override
  String get runsSortOldest => 'Mais antigas primeiro';

  @override
  String get runsSortLongest => 'Maior distância';

  @override
  String get runsSortFastest => 'Melhor ritmo';

  @override
  String runsSyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizar $count corridas',
      one: 'Sincronizar $count corrida',
    );
    return '$_temp0';
  }

  @override
  String get runsRefreshTooltip => 'Atualizar da nuvem';

  @override
  String get runsOfflineTooltip => 'Offline';

  @override
  String runsSelectionTitle(int count) {
    return '$count selecionadas';
  }

  @override
  String get runsSelectAllTooltip => 'Selecionar tudo';

  @override
  String get runsClearSelectionTooltip => 'Limpar';

  @override
  String get runsDeleteTooltip => 'Excluir';

  @override
  String get runsCancelTooltip => 'Cancelar';

  @override
  String get runsAddRun => 'Adicionar corrida';

  @override
  String get runsAddRunTooltip => 'Adicionar uma corrida manualmente';

  @override
  String runsLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get runsNoMatch => 'Nenhuma corrida corresponde a estes filtros';

  @override
  String get runsClearFilters => 'Limpar filtros';

  @override
  String get runsEmptyTitle => 'Ainda não há corridas';

  @override
  String get runsEmptyBody =>
      'Toque na aba Correr para iniciar sua primeira corrida';

  @override
  String get runsFilterAll => 'Todas';

  @override
  String get runsSourceAll => 'Todas as fontes';

  @override
  String runsSourceLabel(String source) {
    return 'Fonte: $source';
  }

  @override
  String get runsSourceFilterTooltip => 'Filtrar por fonte';

  @override
  String get runsSourceRecorded => 'Gravada';

  @override
  String get runsSourceWatch => 'Relógio';

  @override
  String get runsSourceStrava => 'Strava';

  @override
  String get runsSourceParkrun => 'parkrun';

  @override
  String get runsSourceHealthKit => 'HealthKit';

  @override
  String get runsSourceHealthConnect => 'Health Connect';

  @override
  String get runsRangePickerTitle => 'Selecionar datas';

  @override
  String get runsRangeStart => 'Início';

  @override
  String get runsRangeEnd => 'Fim';

  @override
  String get runsRangeTapDate => 'Toque em uma data';

  @override
  String get runsRangeApply => 'Aplicar';

  @override
  String get runsRangeClear => 'Limpar';

  @override
  String get runsPrevMonth => 'Mês anterior';

  @override
  String get runsNextMonth => 'Próximo mês';

  @override
  String get runsPrevYear => 'Ano anterior';

  @override
  String get runsNextYear => 'Próximo ano';

  @override
  String runsDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count corridas?',
      one: 'Excluir $count corrida?',
    );
    return '$_temp0';
  }

  @override
  String get runsDeleteConfirmBody => 'Isso não pode ser desfeito.';

  @override
  String get runsCancel => 'Cancelar';

  @override
  String get runsDelete => 'Excluir';

  @override
  String get runsQueuedToSync => 'Na fila para sincronizar';

  @override
  String get runsSignInToSync =>
      'Entre nas configurações para sincronizar as corridas';

  @override
  String get runsRefreshFailed =>
      'Não foi possível atualizar — verifique sua conexão';

  @override
  String get runsLoadMoreFailed => 'Não foi possível carregar mais corridas';

  @override
  String runsSyncPartial(int synced, int total, String error) {
    return '$synced/$total sincronizadas. Erro: $error';
  }

  @override
  String runsSyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count corridas não conseguiram enviar seu trajeto de GPS — o restante foi sincronizado. As corridas com falha serão tentadas novamente no próximo ciclo.',
      one:
          '$count corrida não conseguiu enviar seu trajeto de GPS — o restante foi sincronizado. Será tentado novamente no próximo ciclo.',
    );
    return '$_temp0';
  }

  @override
  String runsSyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Todas as $count corridas sincronizadas',
      one: '$count corrida sincronizada',
    );
    return '$_temp0';
  }

  @override
  String runsDeletePartial(int deleted, int queued) {
    return '$deleted excluídas; $queued na fila — será tentado novamente quando você estiver online.';
  }

  @override
  String runsDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas excluídas',
      one: '$count corrida excluída',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'Adicionar corrida';

  @override
  String get addRunSave => 'Salvar';

  @override
  String get addRunSectionWhen => 'Quando';

  @override
  String get addRunSectionActivity => 'Atividade';

  @override
  String get addRunSectionRoute => 'Rota (opcional)';

  @override
  String get addRunSectionDistance => 'Distância';

  @override
  String get addRunSectionDuration => 'Duração';

  @override
  String get addRunSectionTitle => 'Título (opcional)';

  @override
  String get addRunSectionNotes => 'Notas (opcional)';

  @override
  String get addRunClearRoute => 'Remover rota';

  @override
  String get addRunSearchRoutes => 'Buscar rotas salvas';

  @override
  String get addRunNoRoutes =>
      'Ainda não há rotas salvas — crie ou importe uma para anexá-la aqui';

  @override
  String get addRunDistanceInvalid => 'Insira uma distância maior que 0';

  @override
  String get addRunDurationInvalid => 'Insira uma duração';

  @override
  String get addRunTitleHint => 'ex.: Volta do almoço';

  @override
  String get addRunNotesHint => 'Como foi?';

  @override
  String get addRunSaveButton => 'Salvar corrida';

  @override
  String addRunSaveFailed(String error) {
    return 'Falha ao salvar a corrida: $error';
  }

  @override
  String get addRunSaved => 'Corrida adicionada ao histórico';

  @override
  String get addRunPickerSearchHint => 'Buscar rotas';

  @override
  String get addRunPickerClear => 'Limpar';

  @override
  String get addRunPickerCancel => 'Cancelar';

  @override
  String addRunPickerNoMatch(String query) {
    return 'Nenhuma rota corresponde a \"$query\"';
  }

  @override
  String get addRunPickerNoRoute => 'Sem rota';

  @override
  String get runDetailDnfBadge => 'DNF';

  @override
  String get runDetailEditTooltip => 'Editar corrida';

  @override
  String get runDetailShareTooltip => 'Compartilhar corrida';

  @override
  String get runDetailMoreTooltip => 'Mais';

  @override
  String get runDetailSaveAsRoute => 'Salvar como rota';

  @override
  String get runDetailDeleteRun => 'Excluir corrida';

  @override
  String get runDetailEditTitle => 'Editar corrida';

  @override
  String get runDetailFieldTitle => 'Título';

  @override
  String get runDetailFieldNotes => 'Notas';

  @override
  String get runDetailFieldDistance => 'Distância';

  @override
  String get runDetailFieldDuration => 'Duração';

  @override
  String get runDetailMarkDnf => 'Marcar como DNF';

  @override
  String get runDetailMarkDnfSubtitle =>
      'Exclui esta corrida dos recordes pessoais';

  @override
  String get runDetailEditInvalid => 'Insira uma distância e duração válidas';

  @override
  String get runDetailSave => 'Salvar';

  @override
  String get runDetailCancel => 'Cancelar';

  @override
  String get runDetailDelete => 'Excluir';

  @override
  String get runDetailLoadingGps => 'Carregando dados de GPS...';

  @override
  String get runDetailGpsUnavailable => 'Trajeto de GPS indisponível offline';

  @override
  String get runDetailPauseReplay => 'Pausar reprodução';

  @override
  String get runDetailReplay => 'Reproduzir esta corrida';

  @override
  String get runDetailStatElevGain => 'Ganho de elev.';

  @override
  String get runDetailStatElevLoss => 'Perda de elev.';

  @override
  String get runDetailStatAvgHr => 'FC média';

  @override
  String get runDetailStatAgeGrade => 'Índice por idade';

  @override
  String get runDetailSectionElevation => 'Elevação';

  @override
  String get runDetailSectionLaps => 'Voltas';

  @override
  String runDetailLapNumber(int number) {
    return 'Volta $number';
  }

  @override
  String get runDetailSectionRunningDynamics => 'Dinâmica de corrida';

  @override
  String get runDetailDynVerticalOsc => 'Oscilação vertical';

  @override
  String get runDetailDynGroundContact => 'Contato com o solo';

  @override
  String get runDetailDynStrideLength => 'Comprimento da passada';

  @override
  String get runDetailDynAvgPower => 'Potência média';

  @override
  String get runDetailSectionRouteHistory => 'Histórico da rota';

  @override
  String get runDetailThisRoute => 'esta rota';

  @override
  String runDetailPersonalBest(String route) {
    return 'Recorde pessoal em $route';
  }

  @override
  String runDetailBehindPb(String delta) {
    return '$delta atrás do recorde';
  }

  @override
  String runDetailAttemptOf(int rank, int total, String pb) {
    return 'Tentativa $rank de $total  —  Recorde: $pb';
  }

  @override
  String get runDetailSectionBestEfforts => 'Melhores marcas';

  @override
  String get runDetailSectionHeartRateZones => 'Zonas de frequência cardíaca';

  @override
  String get runDetailHrAvg => 'Média';

  @override
  String get runDetailHrMin => 'Mín';

  @override
  String get runDetailHrMax => 'Máx';

  @override
  String runDetailZoneRow(int number, String label) {
    return 'Zona $number · $label';
  }

  @override
  String get runDetailSectionSplits => 'Parciais';

  @override
  String get runDetailNoGpsForSplits => 'Sem dados de GPS para os parciais';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Corrida curta demais para um parcial completo de $unit';
  }

  @override
  String get runDetailSectionSegments => 'Segmentos';

  @override
  String get runDetailSaveAsRouteTitle => 'Salvar como rota';

  @override
  String get runDetailSaveAsRouteBody =>
      'Salve este trajeto de GPS como uma rota que você pode seguir novamente.';

  @override
  String get runDetailRouteNameLabel => 'Nome da rota';

  @override
  String get runDetailNoTrackToSave =>
      'Esta corrida não tem trajeto de GPS para salvar como rota';

  @override
  String runDetailRouteLinked(String route) {
    return 'Vinculada a $route';
  }

  @override
  String get runDetailRouteLinkFailed => 'Não foi possível vincular a rota';

  @override
  String get runDetailReSnapping => 'Reajustando às ruas…';

  @override
  String runDetailRematchFailed(String error) {
    return 'Falha no reajuste: $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return '\"$name\" salva — $kept pontos de passagem ($smoothed suavizados)';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'Não foi possível tornar a corrida pública: $error';
  }

  @override
  String get runDetailMakePublicTitle => 'Tornar esta corrida pública?';

  @override
  String get runDetailMakePublicBodyZone =>
      'Compartilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la. Esta corrida começa ou termina dentro de uma das suas zonas de privacidade, então quem visualizar verá um trajeto recortado com os trechos dentro da zona ocultos.';

  @override
  String get runDetailMakePublicBodyHasZones =>
      'Compartilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la. Nenhuma das suas zonas de privacidade cruza este trajeto, então o trajeto completo ficará visível.';

  @override
  String get runDetailMakePublicBodyNoZones =>
      'Compartilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la — incluindo os pontos de início e fim da sua corrida. Você não tem zonas de privacidade configuradas. Considere adicionar uma ao redor da sua casa antes de compartilhar.';

  @override
  String get runDetailMakePublic => 'Tornar pública';

  @override
  String get runDetailDeleteTitle => 'Excluir corrida?';

  @override
  String get runDetailDeleteBody => 'Isso não pode ser desfeito.';

  @override
  String get runDetailSuggestLink => 'Vincular';

  @override
  String get runDetailSuggestDismiss => 'Dispensar';

  @override
  String get runDetailSuggestRanRoute => 'Parece que você correu ';

  @override
  String get runDetailSuggestLinkPrompt => 'Vincular esta corrida a essa rota?';

  @override
  String get runDetailMatchPending => 'Ajustando às ruas…';

  @override
  String get runDetailMatchSkipped => 'Não ajustada (poucos pontos)';

  @override
  String get runDetailMatchFailed =>
      'Falha no ajuste — exibindo o trajeto bruto';

  @override
  String get runDetailMatchMatched => 'Ajustada';

  @override
  String get runDetailRematchQueueing => 'Adicionando à fila…';

  @override
  String get runDetailRematch => 'Reajustar';

  @override
  String get runDetailSegStatDistance => 'Distância';

  @override
  String get runDetailSegStatTime => 'Tempo';

  @override
  String get runDetailSegStatPace => 'Ritmo';

  @override
  String get runDetailSegStatHr => 'FC';

  @override
  String get runDetailSegStatGain => 'Ganho';

  @override
  String get runDetailSegDismiss => 'Dispensar';

  @override
  String get publicRunTitle => 'Corrida';

  @override
  String get publicRunLoadError => 'Não foi possível carregar esta corrida.';

  @override
  String get publicRunUnavailable =>
      'Esta corrida é privada ou não está mais disponível.';

  @override
  String get publicRunAuthorFallback => 'Corredor';

  @override
  String get publicRunStatDistance => 'Distância';

  @override
  String get publicRunStatTime => 'Tempo';

  @override
  String get publicRunStatPace => 'Ritmo';

  @override
  String get publicRunSectionSegments => 'Segmentos';

  @override
  String get routesSyncFailedOffline =>
      'Não foi possível sincronizar as rotas — trabalhando offline';

  @override
  String get routesLoadMoreFailed => 'Não foi possível carregar mais rotas';

  @override
  String routesStarUpdateFailed(String error) {
    return 'Não foi possível atualizar a estrela: $error';
  }

  @override
  String get routesImportFailedLocalOnly =>
      'Falha na importação: escolha o arquivo do armazenamento local, não de um seletor de documentos apenas na nuvem.';

  @override
  String routesImported(String name) {
    return '\"$name\" importada';
  }

  @override
  String routesImportFailed(String error) {
    return 'Falha na importação: $error';
  }

  @override
  String routesSaved(String name) {
    return '\"$name\" salva';
  }

  @override
  String get routesEmptyTitle => 'Nenhuma rota ainda';

  @override
  String get routesEmptyBody =>
      'Toque em Criar para desenhar uma rota no mapa ou importe um arquivo GPX, KML ou TCX.';

  @override
  String get routesBuild => 'Criar';

  @override
  String get routesImport => 'Importar';

  @override
  String get routesNoMatch => 'Nenhuma rota corresponde a esses filtros';

  @override
  String get routesClearFilters => 'Limpar filtros';

  @override
  String routesLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get routesQueuedToSync => 'Na fila para sincronizar';

  @override
  String get routesSavedForOffline => 'Salvo para uso offline';

  @override
  String get routesUnstarRoute => 'Remover estrela da rota';

  @override
  String get routesStarForWatch => 'Marcar para mostrar no relógio';

  @override
  String get routesDiscover => 'Descobrir';

  @override
  String get routesSyncFromCloud => 'Sincronizar da nuvem';

  @override
  String get routesPublicRoutes => 'Rotas públicas';

  @override
  String get routesHeatmap => 'Mapa de calor';

  @override
  String get routesExplorePublic => 'Explorar rotas públicas';

  @override
  String get routesHeatmapTooltip => 'Mapa de calor das rotas';

  @override
  String get routesSearchHint => 'Buscar rotas por nome…';

  @override
  String get routesClearSearch => 'Limpar busca';

  @override
  String get routesStarred => 'Com estrela';

  @override
  String routesCountMeta(int visible, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$visible de $total rotas',
      one: '$visible de $total rota',
    );
    return '$_temp0';
  }

  @override
  String get routesSurfaceAny => 'Qualquer superfície';

  @override
  String get routesSurfaceRoad => 'Estrada';

  @override
  String get routesSurfaceTrail => 'Trilha';

  @override
  String get routesSurfaceMixed => 'Mista';

  @override
  String get routesDistanceAny => 'Qualquer distância';

  @override
  String get routesSortNewest => 'Mais recentes primeiro';

  @override
  String get routesSortLongest => 'Mais longa';

  @override
  String get routesSortShortest => 'Mais curta';

  @override
  String get routesSortMostRun => 'Mais percorrida';

  @override
  String get routesSortAlpha => 'A–Z';

  @override
  String routesDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count rotas?',
      one: 'Excluir $count rota?',
    );
    return '$_temp0';
  }

  @override
  String get routesDeleteConfirmBody => 'Isso não pode ser desfeito.';

  @override
  String routesSelectionTitle(int count) {
    return '$count selecionada(s)';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted excluída(s); $failed com falha — verifique sua conexão.';
  }

  @override
  String routesDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rotas excluídas.',
      one: '$count rota excluída.',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteCleared => 'Rota limpa';

  @override
  String routeBuilderPointsSummary(int count, String distance) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pontos, $distance',
      one: '$count ponto, $distance',
    );
    return '$_temp0';
  }

  @override
  String get routeBuilderRouteFailedStraightLines =>
      'Não foi possível traçar — mostrando linhas retas entre seus pontos.';

  @override
  String routeBuilderSegmentsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count segmentos não puderam se ajustar a uma via. Arraste os pinos afetados para ajustar.',
      one:
          '$count segmento não pôde se ajustar a uma via. Arraste o pino afetado para ajustar.',
    );
    return '$_temp0';
  }

  @override
  String routeBuilderRoutingFailed(String error) {
    return 'Falha ao traçar a rota: $error';
  }

  @override
  String get routeBuilderTooCloseToPin =>
      'Muito perto de outro pino — arraste um pouco mais longe.';

  @override
  String get routeBuilderPinAlreadyThere =>
      'Já há um pino aqui — toque mais distante para adicionar outro.';

  @override
  String get routeBuilderTargetTooLong =>
      'Insira uma distância alvo de até 1000 km.';

  @override
  String get routeBuilderSaveNeedTwo =>
      'Coloque pelo menos dois pontos primeiro.';

  @override
  String routeBuilderSavedLocally(String detail) {
    return 'Salvo localmente. $detail Será sincronizado da próxima vez.';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'Não foi possível acessar o servidor. Faça login ou verifique sua conexão e tente novamente.';

  @override
  String routeBuilderSaveFailed(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get routeBuilderSearchHint => 'Pesquisar lugares…';

  @override
  String get routeBuilderMore => 'Mais';

  @override
  String get routeBuilderGenerateLoop => 'Gerar circuito';

  @override
  String get routeBuilderUndo => 'Desfazer';

  @override
  String get routeBuilderClear => 'Limpar';

  @override
  String get routeBuilderSaving => 'Salvando…';

  @override
  String get routeBuilderSave => 'Salvar';

  @override
  String get routeBuilderLocateMe => 'Localizar-me';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'Toque para mover o ponto $number, ou use os ícones';
  }

  @override
  String routeBuilderEmptyHint(String mode) {
    return 'Toque no mapa para colocar pontos · $mode';
  }

  @override
  String routeBuilderOnePointHint(String mode) {
    return 'Coloque outro para traçar a linha · $mode';
  }

  @override
  String routeBuilderStatusGain(String distance, int gain, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pontos',
      one: '$count ponto',
    );
    return '$distance · $gain m ↑ · $_temp0';
  }

  @override
  String routeBuilderStatusNoGain(String distance, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pontos',
      one: '$count ponto',
    );
    return '$distance · $_temp0';
  }

  @override
  String routeBuilderDeletePoint(int number) {
    return 'Excluir o ponto $number';
  }

  @override
  String get routeBuilderCancelDrag => 'Cancelar arrasto';

  @override
  String get routeBuilderModeTrail => 'Trilha';

  @override
  String get routeBuilderModeRoad => 'Estrada';

  @override
  String get routeBuilderModeStraight => 'Reta';

  @override
  String get routeBuilderLoopDialogBody =>
      'Distância alvo — criaremos um circuito radial em torno do centro atual do mapa.';

  @override
  String get routeBuilderCancel => 'Cancelar';

  @override
  String get routeBuilderGenerate => 'Gerar';

  @override
  String get routeBuilderSaveDialogTitle => 'Salvar rota';

  @override
  String get routeBuilderNameLabel => 'Nome';

  @override
  String get routeBuilderNameHint => 'ex.: Circuito do rio';

  @override
  String get routeBuilderDescriptionLabel => 'Descrição (opcional)';

  @override
  String get routeBuilderDescriptionHint =>
      'Superfície, subidas, estacionamento, qualquer coisa que valha a pena anotar';

  @override
  String get routeBuilderSaveToLabel => 'Salvar em';

  @override
  String get routeBuilderSaveToPersonal => 'Pessoal';

  @override
  String get routeBuilderMakePublic => 'Tornar pública';

  @override
  String get routeBuilderMakePublicSubtitle =>
      'Outros podem encontrá-la em Descobrir';

  @override
  String get routeDetailStartRun => 'Iniciar corrida';

  @override
  String get routeDetailShare => 'Compartilhar';

  @override
  String get routeDetailShareAsImage => 'Compartilhar como imagem';

  @override
  String get routeDetailShareAsGpx => 'Compartilhar como GPX';

  @override
  String get routeDetailShareAsKml => 'Compartilhar como KML';

  @override
  String get routeDetailRemoveOfflineSave => 'Remover salvamento offline';

  @override
  String get routeDetailSaveForOffline => 'Salvar para uso offline';

  @override
  String get routeDetailUnstarRoute => 'Remover estrela da rota';

  @override
  String get routeDetailStarForWatch => 'Marcar para mostrar no relógio';

  @override
  String get routeDetailMakePrivate => 'Tornar privada';

  @override
  String get routeDetailMakePublic => 'Tornar pública';

  @override
  String get routeDetailRemoveBookmark => 'Remover marcador';

  @override
  String get routeDetailBookmarkRoute => 'Marcar rota';

  @override
  String get routeDetailReportRoute => 'Denunciar rota';

  @override
  String get routeDetailTransferToClub => 'Transferir para clube';

  @override
  String get routeDetailManageClub => 'Desanexar ou mover para outro clube';

  @override
  String get routeDetailDeleteRoute => 'Excluir rota';

  @override
  String get routeDetailStatDistance => 'Distância';

  @override
  String get routeDetailStatElevation => 'Elevação';

  @override
  String routeDetailStatReviews(int count) {
    return '$count avaliações';
  }

  @override
  String get routeDetailStatWaypoints => 'Pontos';

  @override
  String get routeDetailPublicRoute => 'Rota pública';

  @override
  String get routeDetailPrivateRoute => 'Rota privada';

  @override
  String get routeDetailPublicSubtitle =>
      'Qualquer pessoa com o link de compartilhamento pode ver esta rota';

  @override
  String get routeDetailPrivateSubtitle => 'Apenas você pode ver esta rota';

  @override
  String get routeDetailSavedForOffline => 'Salvo para uso offline';

  @override
  String get routeDetailSaveForOfflineTitle => 'Salvar para uso offline';

  @override
  String get routeDetailOfflinePinnedSubtitle =>
      'A rota fica neste telefone para você percorrê-la sem conexão.';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'Mantenha esta rota no seu telefone para usar sem rede.';

  @override
  String get routeDetailDescriptionHeading => 'Descrição';

  @override
  String routeDetailRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get routeDetailFeatured => 'Destaque';

  @override
  String get routeDetailSurfaceTrail => 'TRILHA';

  @override
  String get routeDetailSurfaceMixed => 'MISTA';

  @override
  String get routeDetailSurfaceRoad => 'ESTRADA';

  @override
  String get routeDetailAddTagHint => 'adicionar etiqueta';

  @override
  String get routeDetailReviewsHeading => 'Avaliações';

  @override
  String get routeDetailRate => 'Avaliar';

  @override
  String get routeDetailReviewsOffline => 'Avaliações indisponíveis offline';

  @override
  String get routeDetailNoReviews => 'Nenhuma avaliação ainda';

  @override
  String get routeDetailRateDialogTitle => 'Avaliar esta rota';

  @override
  String get routeDetailCommentLabel => 'Comentário (opcional)';

  @override
  String get routeDetailCancel => 'Cancelar';

  @override
  String get routeDetailSubmit => 'Enviar';

  @override
  String get routeDetailSignInToReview =>
      'Faça login para deixar uma avaliação';

  @override
  String routeDetailReviewFailed(String error) {
    return 'Falha ao enviar avaliação: $error';
  }

  @override
  String routeDetailBookmarkFailed(String error) {
    return 'Falha ao marcar: $error';
  }

  @override
  String get routeDetailPublicWillSync =>
      'Rota definida como pública. Será sincronizada da próxima vez.';

  @override
  String get routeDetailPrivateWillSync =>
      'Rota definida como privada. Será sincronizada da próxima vez.';

  @override
  String routeDetailVisibilityFailed(String error) {
    return 'Não foi possível atualizar a visibilidade: $error';
  }

  @override
  String routeDetailStarFailed(String error) {
    return 'Não foi possível atualizar a estrela: $error';
  }

  @override
  String get routeDetailOfflineSaved => 'Salvo para uso offline.';

  @override
  String get routeDetailOfflineRemoved => 'Removido dos salvamentos offline.';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'Não foi possível salvar a etiqueta: $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return 'Não foi possível compartilhar $format: $error';
  }

  @override
  String get routeDetailClubsLoadTimeout =>
      'Não foi possível carregar seus clubes — verifique sua rede.';

  @override
  String get routeDetailClubsLoadFailed =>
      'Não foi possível carregar seus clubes.';

  @override
  String get routeDetailDetached =>
      'Desanexada do clube; a rota agora é pessoal.';

  @override
  String get routeDetailMovedToClub =>
      'Rota movida para a biblioteca do clube.';

  @override
  String routeDetailTransferFailed(String error) {
    return 'Falha na transferência: $error';
  }

  @override
  String get routeDetailDeleteTitle => 'Excluir rota?';

  @override
  String get routeDetailDeleteBody => 'Isso não pode ser desfeito.';

  @override
  String get routeDetailDelete => 'Excluir';

  @override
  String routeDetailDeleteFailed(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get routeDetailPreview => 'Pré-visualização';

  @override
  String get routeDetailPreviewStart => 'Início';

  @override
  String get routeDetailPreviewFinish => 'Chegada';

  @override
  String get routeDetailTransferDialogTitle => 'Transferir para clube';

  @override
  String get routeDetailManageClubTitle => 'Gerenciar propriedade do clube';

  @override
  String get routeDetailTransferDialogBody =>
      'Os membros do clube verão esta rota na biblioteca do clube e poderão adotá-la em seus planos.';

  @override
  String get routeDetailManageClubBody =>
      'Mova esta rota para outro clube que você administra, ou desanexe-a de volta para pessoal.';

  @override
  String get routeDetailDetachToPersonal => 'Desanexar para pessoal';

  @override
  String get routeDetailDetachSubtitle =>
      'Remove a rota da biblioteca do clube atual.';

  @override
  String get routeDetailNoAdminClubs =>
      'Você ainda não possui nem administra nenhum clube.';

  @override
  String get routeDetailCurrentClub => 'Clube atual';

  @override
  String routeDetailClubMemberCount(String location, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros',
      one: '$count membro',
    );
    return '$location · $_temp0';
  }

  @override
  String get exploreRoutesTitle => 'Explorar rotas';

  @override
  String get exploreRoutesModeSearch => 'Buscar';

  @override
  String get exploreRoutesModeNearMe => 'Perto de mim';

  @override
  String get exploreRoutesSearchHint => 'Buscar rotas por nome...';

  @override
  String get exploreRoutesFeatured => 'Destaque';

  @override
  String get exploreRoutesSignInRequired =>
      'Faça login e conecte-se à internet para explorar rotas';

  @override
  String get exploreRoutesTimeout =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String get exploreRoutesSearchFailed =>
      'Falha na busca. Toque em Tentar novamente.';

  @override
  String get exploreRoutesLoadMoreFailed =>
      'Não foi possível carregar mais — verifique sua conexão';

  @override
  String get exploreRoutesLocationPermissionRequired =>
      'Permissão de localização necessária para encontrar rotas próximas';

  @override
  String get exploreRoutesNearbyFailed =>
      'Não foi possível encontrar rotas próximas. Toque em Tentar novamente.';

  @override
  String get exploreRoutesEmptyNoPublic => 'Nenhuma rota pública ainda';

  @override
  String get exploreRoutesEmptyNoMatch =>
      'Nenhuma rota corresponde à sua busca';

  @override
  String get exploreRoutesEmptyBody =>
      'As rotas compartilhadas pelo app web aparecem aqui';

  @override
  String get exploreRoutesDistanceAny => 'Qualquer distância';

  @override
  String get exploreRoutesSurfaceAny => 'Qualquer superfície';

  @override
  String get exploreRoutesSurfaceRoad => 'Estrada';

  @override
  String get exploreRoutesSurfaceTrail => 'Trilha';

  @override
  String get exploreRoutesSurfaceMixed => 'Mista';

  @override
  String get exploreRoutesSortMostRun => 'Mais percorridas';

  @override
  String get exploreRoutesSortNewest => 'Mais recentes';

  @override
  String get exploreRoutesSortFeatured => 'Destaque';

  @override
  String get exploreRoutesSort => 'Ordenar';

  @override
  String exploreRoutesSaveCheckConnection(String name) {
    return 'Não foi possível salvar \"$name\" — verifique sua conexão e tente novamente.';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return 'Não foi possível salvar \"$name\".';
  }

  @override
  String exploreRoutesSaved(String name) {
    return '\"$name\" salva na sua biblioteca';
  }

  @override
  String get exploreRoutesAlreadySaved => 'Já salva';

  @override
  String get exploreRoutesSaveToLibrary => 'Salvar na biblioteca';

  @override
  String get exploreRoutesSurfaceTrailShort => 'Trilha';

  @override
  String get exploreRoutesSurfaceMixedShort => 'Mista';

  @override
  String get exploreRoutesSurfaceRoadShort => 'Estrada';

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
  String get heatmapSearchHint => 'Pesquisar lugares…';

  @override
  String get heatmapFilters => 'Filtros';

  @override
  String heatmapRoutesStartHere(int count) {
    return '$count rotas começam aqui';
  }

  @override
  String heatmapRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rotas',
      one: '$count rota',
    );
    return '$_temp0';
  }

  @override
  String get heatmapNoRoutesHere => 'Nenhuma rota aqui';

  @override
  String get heatmapNoRoutesHint =>
      'Nenhuma rota aqui. Mova o mapa ou altere os filtros.';

  @override
  String heatmapClearKept(int count) {
    return 'Limpar $count mantida(s)';
  }

  @override
  String get heatmapUnpinFromMap => 'Desafixar do mapa';

  @override
  String get heatmapKeepOnMap => 'Manter no mapa';

  @override
  String get heatmapLocateMe => 'Localizar-me';

  @override
  String heatmapLocationUnavailable(String error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get heatmapBackToList => 'Voltar à lista';

  @override
  String get heatmapViewRoute => 'Ver rota';

  @override
  String get heatmapKept => 'Mantida';

  @override
  String get heatmapKeep => 'Manter';

  @override
  String get heatmapLensShow => 'Mostrar';

  @override
  String get heatmapLensDistance => 'Distância';

  @override
  String get heatmapLensMap => 'Mapa';

  @override
  String get heatmapHeatDensity => 'Densidade de calor';

  @override
  String get heatmapResetFilters => 'Redefinir filtros';

  @override
  String get heatmapLensPopular => 'Populares';

  @override
  String get heatmapLensFriends => 'Amigos';

  @override
  String get heatmapLensFeatured => 'Destaque';

  @override
  String get heatmapLensHiddenGems => 'Joias escondidas';

  @override
  String get publicRouteFallbackTitle => 'Rota';

  @override
  String get publicRouteLoadError => 'Não foi possível carregar esta rota.';

  @override
  String get publicRouteUnavailable =>
      'Esta rota é privada ou não está mais disponível.';

  @override
  String get publicRouteStatDistance => 'Distância';

  @override
  String get publicRouteStatElevation => 'Elevação';

  @override
  String get publicRouteStatWaypoints => 'Pontos';

  @override
  String get routesLoadErrorRetry =>
      'Não foi possível carregar suas rotas. Verifique sua conexão e tente novamente.';
}
