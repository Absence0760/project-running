// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get trustedContactsClearedBanner => 'Contatos de confiança removidos.';

  @override
  String trustedContactsSavedBanner(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contatos de confiança salvos.',
      one: '1 contato de confiança salvo.',
    );
    return '$_temp0';
  }

  @override
  String trustedContactsSaveFailedBanner(Object error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get trustedContactsTitle => 'Contatos de confiança';

  @override
  String trustedContactsIntro(Object max) {
    return 'Defina um ou mais contatos de confiança. A estrutura armazena a lista junto à sua conta para que os recursos planejados de \"corrida atrasada\" e botão de pânico tenham para onde enviar notificações. Até $max.';
  }

  @override
  String get trustedContactsAddButton => 'Adicionar contato';

  @override
  String get trustedContactsSavingButton => 'Salvando…';

  @override
  String get trustedContactsSaveButton => 'Salvar';

  @override
  String get trustedContactsNameLabel => 'Nome';

  @override
  String get trustedContactsNameHint => 'ex.: Alex Chen';

  @override
  String get trustedContactsPhoneLabel => 'Telefone';

  @override
  String get trustedContactsPhoneHint => '+55 11 91234 5678';

  @override
  String get trustedContactsEmailLabel => 'E-mail';

  @override
  String get trustedContactsEmailHint => 'alex@exemplo.com';

  @override
  String get trustedContactsRelationshipLabel => 'Relação';

  @override
  String get trustedContactsRelationshipHint =>
      'parceiro(a) / pai ou mãe / parceiro(a) de corrida';

  @override
  String get trustedContactsRemoveButton => 'Remover';

  @override
  String get clubInviteEnterCodeError =>
      'Digite o código de convite do seu link.';

  @override
  String get clubInviteJoinedBanner => 'Você entrou no clube.';

  @override
  String get clubInviteTitle => 'Entrar no clube';

  @override
  String get clubInviteIntro =>
      'Cole o código de convite que o administrador do clube compartilhou com você.';

  @override
  String get clubInviteCodeLabel => 'Código de convite';

  @override
  String get clubInviteJoinButton => 'Entrar';

  @override
  String recapShareHeadline(Object year) {
    return 'Meu $year na corrida:';
  }

  @override
  String recapShareTotals(Object total, Object count) {
    return '$total em $count corridas';
  }

  @override
  String recapShareLongestRun(Object distance) {
    return 'Corrida mais longa: $distance';
  }

  @override
  String recapShareBestStreak(Object days) {
    return 'Melhor sequência: $days dias';
  }

  @override
  String recapShareSubject(Object year) {
    return 'Retrospectiva $year';
  }

  @override
  String get recapTitle => 'Ano na corrida';

  @override
  String get recapShareTooltip => 'Compartilhar retrospectiva';

  @override
  String get recapPublishAndShare => 'Publicar e partilhar ligação';

  @override
  String get recapPublishFailed =>
      'Não foi possível publicar o resumo. Tente novamente.';

  @override
  String get recapPrevYear => 'Ano anterior';

  @override
  String get recapNextYear => 'Próximo ano';

  @override
  String recapNoRunsForYear(Object year) {
    return 'Nenhuma corrida para a retrospectiva de $year.';
  }

  @override
  String recapNoRunsYet(Object year) {
    return 'Ainda não há corridas em $year. Registre uma para ver sua retrospectiva.';
  }

  @override
  String recapAcrossRuns(Object count, Object runWord) {
    return 'em $count $runWord';
  }

  @override
  String get recapLongestRunLabel => 'Corrida mais longa';

  @override
  String get recapBestStreakLabel => 'Melhor sequência';

  @override
  String recapStreakDays(Object days, Object dayWord) {
    return '$days $dayWord';
  }

  @override
  String get recapTopWeekLabel => 'Melhor semana';

  @override
  String get recapUniqueRoutesLabel => 'Rotas únicas';

  @override
  String get recapEarliestStartLabel => 'Início mais cedo';

  @override
  String get recapLatestStartLabel => 'Início mais tarde';

  @override
  String get routePickerTitle => 'Escolher rota';

  @override
  String get routePickerNoRoute => 'Sem rota';

  @override
  String get routePickerClearSearchTooltip => 'Limpar busca';

  @override
  String get routePickerSearchHint => 'Buscar rotas por nome…';

  @override
  String get routePickerEmptyNoRoutes => 'Nenhuma rota salva ainda';

  @override
  String routePickerEmptyNoMatch(Object query) {
    return 'Nenhuma rota corresponde a \"$query\"';
  }

  @override
  String get routePickerStarredHeader => 'Com estrela';

  @override
  String get routePickerAllRoutesHeader => 'Todas as rotas';

  @override
  String importStatusImported(Object count, Object label) {
    return '$count corridas importadas de $label';
  }

  @override
  String importStatusImportedWithErrors(Object count, Object errors) {
    return '$count corridas importadas ($errors com falha)';
  }

  @override
  String importStatusNoGpsNote(Object base, Object label) {
    return '$base. $label não tem dados de rota, então essas corridas não têm mapa.';
  }

  @override
  String importHealthRequestingPermission(Object label) {
    return 'Solicitando permissão do $label...';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return 'Permissão do $label negada';
  }

  @override
  String get importHealthReadingWorkouts => 'Lendo treinos...';

  @override
  String importHealthFailed(Object label, Object error) {
    return 'Falha na importação do $label: $error';
  }

  @override
  String get importStatusSavingLocally => 'Salvando localmente...';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return '$count duplicata(s) ignorada(s) já importada(s) de outra fonte';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return '$done de $total salvas localmente';
  }

  @override
  String get importStatusSyncingToCloud => 'Sincronizando com a nuvem...';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return '$done de $total sincronizadas';
  }

  @override
  String get importStatusReadingCsv => 'Lendo CSV...';

  @override
  String importCsvFailed(Object error) {
    return 'Falha na importação do CSV: $error';
  }

  @override
  String get importStatusRestoringBackup => 'Restaurando backup...';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return '$runs corridas · $tracks trajetos · $routes rotas restauradas';
  }

  @override
  String importBackupFailed(Object error) {
    return 'Falha ao restaurar o backup: $error';
  }

  @override
  String get importStatusReadingExport => 'Lendo exportação...';

  @override
  String importStravaFailed(Object error) {
    return 'Falha na importação: $error';
  }

  @override
  String get importTitle => 'Importar corridas';

  @override
  String get importStravaCardTitle => 'Strava';

  @override
  String get importStravaCardSubtitle =>
      'Importe todas as corridas de um ZIP de exportação de dados do Strava';

  @override
  String get importStravaHowToHeader => 'Como obter sua exportação do Strava:';

  @override
  String get importStravaHowToSteps =>
      '1. Abra o Strava → Configurações → Minha conta\n2. Role até \"Baixar ou excluir sua conta\"\n3. Toque em \"Começar\" → \"Solicitar seu arquivo\"\n4. Você receberá um e-mail com um link de download em algumas horas\n5. Baixe o .zip e toque em Importar abaixo';

  @override
  String get importStravaButton => 'Importar ZIP do Strava';

  @override
  String importHealthButton(Object label) {
    return 'Importar do $label';
  }

  @override
  String get importCsvCardTitle => 'CSV';

  @override
  String get importCsvCardSubtitle =>
      'Reimporte um CSV exportado em Configurações — apenas corridas, sem GPS';

  @override
  String get importCsvCardDescription =>
      'Cada linha do CSV vira uma corrida manual (data, distância, duração, fonte). O trajeto no mapa não está no CSV, então as corridas importadas não terão linha de rota.';

  @override
  String get importCsvButton => 'Importar CSV';

  @override
  String get importBackupCardTitle => 'ZIP de backup completo';

  @override
  String get importBackupCardSubtitle =>
      'Restaure corridas, rotas e trajetos de GPS de um arquivo de backup';

  @override
  String get importBackupCardDescription =>
      'Ida e volta sem perdas. Funciona sem login — as corridas restauradas sincronizam com sua conta na próxima vez que você entrar. Faça um backup em Configurações → Backup completo.';

  @override
  String get importBackupButton => 'Restaurar ZIP de backup';

  @override
  String get importErrorsHeader => 'Erros';

  @override
  String importErrorsMore(Object count) {
    return '... e mais $count';
  }

  @override
  String get importHealthSubtitleIos =>
      'Importe treinos gravados no Apple Watch, Nike Run Club, Strava e outros apps que gravam no Apple Saúde';

  @override
  String get importHealthSubtitleAndroid =>
      'Importe treinos do Google Fit, Samsung Health, Garmin, Fitbit e qualquer outro app do Health Connect';

  @override
  String get importHealthDescriptionIos =>
      'Lê resumos de treino (data, distância, duração, tipo) do último ano. O Apple Saúde não expõe rotas de GPS gravadas por apps de terceiros — as corridas importadas assim não terão trajeto no mapa.';

  @override
  String get importHealthDescriptionAndroid =>
      'Lê resumos de treino (data, distância, duração, tipo) do último ano. As rotas de GPS não são expostas pelo Health Connect — as corridas importadas assim não terão trajeto no mapa.';

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'Não foi possível atualizar o seguimento: $error';
  }

  @override
  String get peopleSearchHint => 'Buscar corredores por nome';

  @override
  String get peopleClearSearchTooltip => 'Limpar busca';

  @override
  String get commonClearSearch => 'Limpar busca';

  @override
  String get commonDismiss => 'Dispensar';

  @override
  String get settingsDevicesRemoveOverride => 'Remover substituição';

  @override
  String get peopleSearchResultsHeader => 'Resultados da busca';

  @override
  String get peopleSuggestedHeader => 'Sugestões para você';

  @override
  String peopleEmptySearchTitle(Object query) {
    return 'Nenhum corredor corresponde a \"$query\"';
  }

  @override
  String get peopleEmptySearchBody =>
      'Tente um nome mais curto ou diferente. Os nomes de exibição são públicos; quem ainda não definiu um não aparece aqui.';

  @override
  String get peopleEmptySuggestionsTitle => 'Nenhuma sugestão ainda';

  @override
  String get peopleEmptySuggestionsBody =>
      'As sugestões vêm de pessoas dos clubes em que você entrou. Entre em um clube para começar a vê-las aqui.';

  @override
  String peoplePublicRunCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas públicas',
      one: '1 corrida pública',
    );
    return '$_temp0';
  }

  @override
  String peopleSharedClubsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clubes em comum',
      one: '1 clube em comum',
    );
    return '$_temp0';
  }

  @override
  String get peopleFallbackDisplayName => 'Corredor';

  @override
  String get peopleFollowingButton => 'Seguindo';

  @override
  String get peopleFollowButton => 'Seguir';

  @override
  String get readinessCardHeader => 'PRONTIDÃO';

  @override
  String get readinessBandHigh => 'alta';

  @override
  String get readinessBandModerate => 'moderada';

  @override
  String get readinessBandLow => 'baixa';

  @override
  String get missingMapTilesTitle =>
      'Usando tiles alternativos do OpenStreetMap';

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
  String get navLog => 'Registrar';

  @override
  String get logA11yLabel => 'Registrar uma atividade';

  @override
  String get navFitness => 'Fitness';

  @override
  String get navYou => 'Você';

  @override
  String get fitnessTabAll => 'Tudo';

  @override
  String get fitnessTabRuns => 'Corridas';

  @override
  String get fitnessTabGym => 'Academia';

  @override
  String get fitnessTabNutrition => 'Nutrição';

  @override
  String get fitnessRunsRoutes => 'Rotas';

  @override
  String get fitnessRunsPlans => 'Planos de treino';

  @override
  String get homeAskCoach => 'Pergunte ao seu treinador';

  @override
  String get homeAskCoachSubtitle =>
      'Dicas sobre suas corridas, academia e nutrição';

  @override
  String get youProfileTitle => 'Seu perfil';

  @override
  String get logSheetTitle => 'Registrar';

  @override
  String get logRun => 'Registrar corrida';

  @override
  String get logLift => 'Registrar musculação';

  @override
  String get logFood => 'Registrar comida';

  @override
  String get prefsKeepRunPrimary => 'Corrida como ação principal';

  @override
  String get prefsKeepRunPrimarySubtitle =>
      'Toque no botão central para iniciar uma corrida; mantenha pressionado para o menu completo';

  @override
  String get bodyMetricsTitle => 'Dados corporais';

  @override
  String get bodyMetricsTileSubtitle => 'Altura, peso e metas nutricionais';

  @override
  String get bodyMetricsConsentTitle => 'Armazenar dados de saúde';

  @override
  String get bodyMetricsConsentSubtitle =>
      'Altura e peso são dados de saúde sensíveis. Desative para apagá-los.';

  @override
  String get bodyMetricsHeight => 'Altura';

  @override
  String get bodyMetricsWeight => 'Peso';

  @override
  String get bodyMetricsActivityLevel => 'Nível de atividade';

  @override
  String get bodyMetricsGoal => 'Meta';

  @override
  String get bodyMetricsTargetsHint =>
      'Usado para estimar suas metas diárias de calorias e macros.';

  @override
  String get bodyMetricsConsentRequired =>
      'Ative o armazenamento de dados de saúde para salvar altura e peso.';

  @override
  String get bodyMetricsWithdrawTitle =>
      'Retirar o consentimento de dados de saúde?';

  @override
  String get bodyMetricsWithdrawBody =>
      'Isso apaga permanentemente sua altura salva e todo o seu histórico de peso. Não pode ser desfeito.';

  @override
  String get bodyMetricsWithdrawConfirm => 'Retirar e apagar';

  @override
  String get bodyMetricsSaved => 'Salvo';

  @override
  String bodyMetricsSaveFailed(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get safetyTitle => 'Contatos de segurança';

  @override
  String get safetyTileSubtitle =>
      'Envie um e-mail a um contato de confiança ao concluir uma corrida';

  @override
  String get safetyIntro =>
      'Um contato de segurança recebe um e-mail quando você conclui uma corrida — mesmo uma privada — para que alguém de confiança saiba que você voltou em segurança.';

  @override
  String get safetyAddLabel => 'E-mail do contato';

  @override
  String get safetyAddButton => 'Adicionar contato';

  @override
  String get safetyAdding => 'Adicionando…';

  @override
  String get safetyEmpty => 'Nenhum contato de segurança ainda.';

  @override
  String get safetyStatusPending => 'Pendente — aguardando a confirmação';

  @override
  String get safetyStatusConfirmed => 'Confirmado';

  @override
  String get safetyRemove => 'Remover';

  @override
  String get safetyRemoveConfirm => 'Remover este contato de segurança?';

  @override
  String safetyAddFailed(String error) {
    return 'Não foi possível adicionar o contato: $error';
  }

  @override
  String get safetyInvalidEmail => 'Digite um e-mail válido.';

  @override
  String get safetyAddedToast =>
      'Contato adicionado — enviamos um e-mail de confirmação.';

  @override
  String get safetyRemovedToast => 'Contato removido.';

  @override
  String get safetyIncomingTitle => 'Pedidos para você';

  @override
  String get safetyIncomingIntro =>
      'Estas pessoas pediram para você ser o contato de segurança delas. Confirme para receber um e-mail quando concluírem uma corrida.';

  @override
  String safetyIncomingFrom(String name) {
    return 'De $name';
  }

  @override
  String get safetyConfirm => 'Confirmar';

  @override
  String get safetyDecline => 'Recusar';

  @override
  String get safetyConfirmedToast => 'Agora você é contato de segurança.';

  @override
  String get safetyDeclinedToast => 'Pedido recusado.';

  @override
  String get safetyUnknownRunner => 'Um corredor do Threkir';

  @override
  String get activitySedentary =>
      'Maior parte sentado (trabalho de escritório)';

  @override
  String get activityLight => 'Levemente ativo (pouca movimentação diária)';

  @override
  String get activityModerate => 'Moderadamente ativo (muito tempo em pé)';

  @override
  String get activityVeryActive => 'Dia muito ativo (trabalho físico)';

  @override
  String get activityExtraActive =>
      'Extremamente ativo (trabalho físico pesado)';

  @override
  String get goalLose => 'Perder peso';

  @override
  String get goalMaintain => 'Manter peso';

  @override
  String get goalGain => 'Ganhar peso';

  @override
  String get homeTodaysLift => 'Treino de hoje';

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
  String get setupPageTitle => 'Configure sua conta';

  @override
  String get setupSkip => 'Pular configuração';

  @override
  String get setupSkipStep => 'Pular';

  @override
  String get setupBack => 'Voltar';

  @override
  String get setupContinue => 'Continuar';

  @override
  String get setupSaving => 'Salvando…';

  @override
  String get setupOpenDashboard => 'Abrir painel';

  @override
  String get setupWelcomeToast => 'Bem-vindo ao Threkir!';

  @override
  String setupSaveError(String message) {
    return 'Não foi possível salvar sua configuração: $message';
  }

  @override
  String get setupNameTitle => 'Como devemos te chamar?';

  @override
  String get setupNameHint =>
      'Este é o nome que outros corredores veem no seu perfil e nas corridas compartilhadas.';

  @override
  String get setupNameLabel => 'Nome de exibição';

  @override
  String get setupNamePlaceholder => 'ex.: Alex Corredor';

  @override
  String get setupUnitsTitle => 'Quilômetros ou milhas?';

  @override
  String get setupUnitsHint =>
      'Vamos usar isso em todos os lugares onde distâncias e ritmos aparecem. Você pode mudar quando quiser em Configurações.';

  @override
  String get setupUnitKm => 'Quilômetros';

  @override
  String get setupUnitKmSample => '5,0 km · 5:00 /km';

  @override
  String get setupUnitMi => 'Milhas';

  @override
  String get setupUnitMiSample => '3,1 mi · 8:03 /mi';

  @override
  String get setupGoalTitle => 'Qual é seu principal objetivo?';

  @override
  String get setupGoalHint =>
      'Vamos usar isso para sugerir um plano de treino adequado. Opcional — você pode pular.';

  @override
  String get setupGoalGeneralFitness => 'Manter a forma + saúde';

  @override
  String get setupGoalWeightLoss => 'Perder peso';

  @override
  String get setupGoal5k => 'Correr 5K';

  @override
  String get setupGoal10k => 'Correr 10K';

  @override
  String get setupGoalHalf => 'Correr uma meia maratona';

  @override
  String get setupGoalMarathon => 'Correr uma maratona';

  @override
  String get setupAboutTitle => 'Um pouco sobre você';

  @override
  String get setupAboutHint =>
      'Opcional. Ajuda a personalizar estimativas de ritmo e calorias. Você decide se compartilha dados de saúde.';

  @override
  String get setupGenderLabel => 'Gênero';

  @override
  String get setupGenderPreferNot => 'Prefiro não dizer';

  @override
  String get setupGenderFemale => 'Feminino';

  @override
  String get setupGenderMale => 'Masculino';

  @override
  String get setupGenderNonbinary => 'Não binário';

  @override
  String get setupDobLabel => 'Data de nascimento';

  @override
  String get setupDobNote =>
      'Usada para manter contas de menores de 18 anos fora da busca de pessoas e para resultados ajustados por idade, se você compartilhar dados de saúde.';

  @override
  String get setupDobPlaceholder => 'Toque para escolher';

  @override
  String get setupWeightLabel => 'Peso (kg)';

  @override
  String get setupWeightPlaceholder => 'ex.: 70';

  @override
  String get setupHealthConsent =>
      'Consinto que o Threkir use meu gênero e data de nascimento para personalizar estimativas de ritmo, frequência cardíaca e calorias (dados de saúde de categoria especial, RGPD art. 9).';

  @override
  String get setupPrivacyTitle => 'Quem vê suas corridas?';

  @override
  String get setupPrivacyHint =>
      'Escolha um padrão para novas corridas. Você pode alterá-lo a qualquer momento e substituí-lo em cada corrida.';

  @override
  String get setupNotificationsTitle => 'Fique por dentro';

  @override
  String get setupNotificationsHint =>
      'Escolha quantas notificações push deseja. Você pode ajustar isso depois em Configurações.';

  @override
  String get setupDoneTitle => 'Tudo pronto';

  @override
  String get setupDoneHint =>
      'É isso. Toque em “Abrir painel” para começar a correr.';

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
  String get runTreadmillModeLabel => 'Modo passadeira';

  @override
  String runTreadmillModeSpeed(String speed) {
    return 'Passadeira $speed';
  }

  @override
  String get runTreadmillLostReconnecting =>
      'Passadeira perdida, a reconectar…';

  @override
  String get runTreadmillReconnected => 'Passadeira reconectada';

  @override
  String get runTreadmillLostFallback =>
      'Passadeira perdida — distância a voltar para o GPS';

  @override
  String get runTreadmillNotFound => 'Não foi possível conectar à passadeira';

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
  String get historyRangeToday => 'Hoje';

  @override
  String get historyRangeWeek => 'Esta semana';

  @override
  String get historyRangeMonth => 'Últimos 30 dias';

  @override
  String get historyRangeYear => 'Este ano';

  @override
  String get historyRangeAll => 'Todo o histórico';

  @override
  String get historyRangeCustom => 'Personalizado…';

  @override
  String historyRangeFrom(String date) {
    return 'A partir de $date';
  }

  @override
  String historyRangeUntil(String date) {
    return 'Até $date';
  }

  @override
  String historyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get historyDateRangeTooltip => 'Período';

  @override
  String get historySortTooltip => 'Ordenar';

  @override
  String get historySortNewest => 'Mais recentes primeiro';

  @override
  String get historySortOldest => 'Mais antigas primeiro';

  @override
  String get historySortLongest => 'Maior distância';

  @override
  String get historySortFastest => 'Melhor ritmo';

  @override
  String historySyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizar $count corridas',
      one: 'Sincronizar $count corrida',
    );
    return '$_temp0';
  }

  @override
  String get historyRefreshTooltip => 'Atualizar da nuvem';

  @override
  String get historyOfflineTooltip => 'Offline';

  @override
  String historySelectionTitle(int count) {
    return '$count selecionadas';
  }

  @override
  String get historySelectAllTooltip => 'Selecionar tudo';

  @override
  String get historyClearSelectionTooltip => 'Limpar';

  @override
  String get historyDeleteTooltip => 'Excluir';

  @override
  String get historyCancelTooltip => 'Cancelar';

  @override
  String get historyAddRun => 'Adicionar corrida';

  @override
  String get historyAddRunTooltip => 'Adicionar uma corrida manualmente';

  @override
  String get historyLogTooltip => 'Registrar corrida, treino ou refeição';

  @override
  String historyLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get historyNoMatch => 'Nenhuma corrida corresponde a estes filtros';

  @override
  String get historyKindAll => 'Tudo';

  @override
  String get historyKindRuns => 'Corridas';

  @override
  String get historyKindLifts => 'Musculação';

  @override
  String get historyKindMeals => 'Refeições';

  @override
  String get historyViewAll => 'Ver tudo';

  @override
  String get historyToday => 'Hoje';

  @override
  String get historyYesterday => 'Ontem';

  @override
  String historySetCount(int n) {
    return '$n séries';
  }

  @override
  String historyKcal(int n) {
    return '$n kcal';
  }

  @override
  String get historyTimelineEmpty =>
      'Nada registrado nesta visualização ainda.';

  @override
  String get historyClearFilters => 'Limpar filtros';

  @override
  String get historyEmptyTitle => 'Ainda não há corridas';

  @override
  String get historyEmptyBody =>
      'Toque na aba Correr para iniciar sua primeira corrida';

  @override
  String get historyFilterAll => 'Todas';

  @override
  String get historySourceAll => 'Todas as fontes';

  @override
  String historySourceLabel(String source) {
    return 'Fonte: $source';
  }

  @override
  String get historySourceFilterTooltip => 'Filtrar por fonte';

  @override
  String get historySourceRecorded => 'Gravada';

  @override
  String get historySourceWatch => 'Relógio';

  @override
  String get historySourceStrava => 'Strava';

  @override
  String get historySourceParkrun => 'parkrun';

  @override
  String get historySourceHealthKit => 'HealthKit';

  @override
  String get historySourceHealthConnect => 'Health Connect';

  @override
  String get historyRangePickerTitle => 'Selecionar datas';

  @override
  String get historyRangeStart => 'Início';

  @override
  String get historyRangeEnd => 'Fim';

  @override
  String get historyRangeTapDate => 'Toque em uma data';

  @override
  String get historyRangeApply => 'Aplicar';

  @override
  String get historyRangeClear => 'Limpar';

  @override
  String get historyPrevMonth => 'Mês anterior';

  @override
  String get historyNextMonth => 'Próximo mês';

  @override
  String get historyPrevYear => 'Ano anterior';

  @override
  String get historyNextYear => 'Próximo ano';

  @override
  String historyDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count corridas?',
      one: 'Excluir $count corrida?',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody => 'Isso não pode ser desfeito.';

  @override
  String get historyCancel => 'Cancelar';

  @override
  String get historyDelete => 'Excluir';

  @override
  String get historyQueuedToSync => 'Na fila para sincronizar';

  @override
  String get historySignInToSync =>
      'Entre nas configurações para sincronizar as corridas';

  @override
  String get historyRefreshFailed =>
      'Não foi possível atualizar — verifique sua conexão';

  @override
  String get historyLoadMoreFailed => 'Não foi possível carregar mais corridas';

  @override
  String historySyncPartial(int synced, int total, String error) {
    return '$synced/$total sincronizadas. Erro: $error';
  }

  @override
  String historySyncTrackFailed(int count) {
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
  String historySyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Todas as $count corridas sincronizadas',
      one: '$count corrida sincronizada',
    );
    return '$_temp0';
  }

  @override
  String historyDeletePartial(int deleted, int queued) {
    return '$deleted excluídas; $queued na fila — será tentado novamente quando você estiver online.';
  }

  @override
  String historyDeleteDone(int count) {
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
  String get runDetailReportRun => 'Denunciar corrida';

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
  String get runDetailStatGradeAdjPace => 'Ritmo ajustado';

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
  String runDetailRouteSaveFailed(String name) {
    return 'Não foi possível salvar \"$name\" como rota.';
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
  String get runDetailMatchOffline =>
      'Offline — exibindo o trajeto bruto, tentaremos novamente';

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
  String get routeBuilderClearConfirmTitle => 'Limpar esta rota?';

  @override
  String get routeBuilderClearConfirmBody =>
      'Todos os pontos serão removidos. Isso não pode ser desfeito.';

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
  String get routeDetailShareAsGpxMarkers =>
      'Compartilhar como GPX + marcadores';

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
  String get routeDetailDescribe => 'Descrever esta rota';

  @override
  String get routeDetailDescribing => 'Descrevendo…';

  @override
  String get routeDetailAiAttribution =>
      'Escrito por IA a partir dos dados da rota';

  @override
  String get routeDetailDescribeFailed =>
      'Não foi possível gerar uma descrição. Tente novamente.';

  @override
  String get routeDetailEnhanceUpgradeHint =>
      'Descrições com IA são um recurso Pro. Faça upgrade para aprimorar.';

  @override
  String get routeDetailDescShapeLoop => 'em circuito';

  @override
  String get routeDetailDescShapeOutAndBack => 'ida e volta';

  @override
  String get routeDetailDescShapePointToPoint => 'ponto a ponto';

  @override
  String get routeDetailDescSurfaceRoad => 'de asfalto';

  @override
  String get routeDetailDescSurfaceTrail => 'de trilha';

  @override
  String get routeDetailDescSurfaceMixed => 'de superfície mista';

  @override
  String get routeDetailDescElevFlat => 'plana';

  @override
  String get routeDetailDescElevRolling => 'levemente ondulada';

  @override
  String get routeDetailDescElevHilly => 'com subidas';

  @override
  String get routeDetailDescElevMountainous => 'montanhosa';

  @override
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  ) {
    return '$name é uma rota $shape $surface de $distance.';
  }

  @override
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  ) {
    return '$name é uma rota $shape de $distance.';
  }

  @override
  String routeDetailDescClimb(String gain, String elevation, String perKm) {
    return 'Tem $gain de ganho de elevação — $elevation, cerca de $perKm por km.';
  }

  @override
  String get routeDetailDescFlat =>
      'Tem pouca ou nenhuma variação de elevação.';

  @override
  String routeDetailDescPerKm(int m) {
    return '$m m';
  }

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
  String routeDetailRateStars(int n) {
    return 'Definir a avaliação como $n de 5';
  }

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
  String routeDetailTagRemoveFailed(String error) {
    return 'Não foi possível remover a etiqueta: $error';
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
  String get runHeatmapTitle => 'Seu mapa de calor';

  @override
  String get runHeatmapTooltip => 'Mapa de calor de corridas';

  @override
  String get runHeatmapLoading => 'Carregando suas corridas…';

  @override
  String runHeatmapLoadingProgress(int n, int total) {
    return 'Carregando suas corridas… $n/$total';
  }

  @override
  String get runHeatmapEmptyTitle => 'Nenhuma corrida mapeada ainda';

  @override
  String get runHeatmapEmptyBody =>
      'Grave ou importe corridas com trajetos de GPS e elas vão aparecer aqui.';

  @override
  String get runHeatmapLegendTitle => 'Seu mapa de calor';

  @override
  String runHeatmapLegendSummaryOne(int n) {
    return '$n corrida mapeada — mais brilhante onde você corre mais.';
  }

  @override
  String runHeatmapLegendSummaryMany(int n) {
    return '$n corridas mapeadas — mais brilhante onde você corre mais.';
  }

  @override
  String get runHeatmapScaleLess => 'menos';

  @override
  String get runHeatmapScaleMore => 'mais';

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

  @override
  String get feedTitle => 'Feed';

  @override
  String get feedFindPeople => 'Encontrar pessoas';

  @override
  String get feedActivityAll => 'Tudo';

  @override
  String get feedActivityRun => 'Corrida';

  @override
  String get feedActivityWalk => 'Caminhada';

  @override
  String get feedActivityCycle => 'Ciclismo';

  @override
  String get feedActivityHike => 'Trilha';

  @override
  String get feedActivityLift => 'Força';

  @override
  String get feedLiftSetsLabel => 'Séries';

  @override
  String get feedLiftVolume => 'Volume';

  @override
  String get feedLiftUntitled => 'Treino';

  @override
  String get feedLoadMore => 'Carregar mais';

  @override
  String feedLoadMoreFailed(String error) {
    return 'Não foi possível carregar mais: $error';
  }

  @override
  String get feedLoadError => 'Não foi possível carregar o feed.';

  @override
  String get feedEveryoneYouFollow => 'Todos que você segue';

  @override
  String get feedRunnerFallback => 'Corredor';

  @override
  String get relativeJustNow => 'Agora mesmo';

  @override
  String relativeMinutesAgo(int count) {
    return 'há $count min';
  }

  @override
  String relativeHoursAgo(int count) {
    return 'há $count h';
  }

  @override
  String get relativeYesterday => 'Ontem';

  @override
  String relativeDaysAgo(int count) {
    return 'há $count d';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count semanas',
      one: 'há 1 semana',
    );
    return '$_temp0';
  }

  @override
  String get coachArchiveToday => 'Hoje';

  @override
  String coachArchiveDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count dias',
    );
    return '$_temp0';
  }

  @override
  String get feedLast14Days => 'Últimos 14 dias';

  @override
  String get feedEmptyTitle => 'Seu feed está vazio';

  @override
  String get feedEmptyBody =>
      'Siga outros corredores para ver as corridas públicas deles aqui.';

  @override
  String get feedNoMatchesTitle => 'Nenhum resultado';

  @override
  String get feedNoMatchesBody =>
      'Nada corresponde aos filtros atuais nos últimos 14 dias.';

  @override
  String get feedNoActivityTitle => 'Nenhuma atividade recente';

  @override
  String get feedNoActivityBody =>
      'Ninguém que você segue registrou uma corrida pública nos últimos 14 dias.';

  @override
  String get feedClearFilters => 'Limpar filtros';

  @override
  String feedKudosUpdateFailed(String error) {
    return 'Não foi possível atualizar os kudos: $error';
  }

  @override
  String get profileTitle => 'Perfil';

  @override
  String get profileRunnerFallback => 'Corredor';

  @override
  String get profileTabRuns => 'Corridas';

  @override
  String get profileTabFollowers => 'Seguidores';

  @override
  String get profileTabFollowing => 'Seguindo';

  @override
  String get profileTabNotifications => 'Notificações';

  @override
  String get profileReportUser => 'Denunciar usuário';

  @override
  String get profileUnblock => 'Desbloquear este perfil';

  @override
  String get profileBlock => 'Bloquear este perfil';

  @override
  String get profileLoadError => 'Não foi possível carregar o perfil.';

  @override
  String get profileNotFound => 'Perfil não encontrado.';

  @override
  String profileFollowStats(int followers, int following) {
    String _temp0 = intl.Intl.pluralLogic(
      followers,
      locale: localeName,
      other: '$followers seguidores',
      one: '$followers seguidor',
    );
    return '$_temp0 · seguindo $following';
  }

  @override
  String get profileFollowing => 'Seguindo';

  @override
  String get profileFollow => 'Seguir';

  @override
  String get profileRunsEmptySelf =>
      'Você ainda não compartilhou nenhuma corrida.';

  @override
  String get profileRunsEmptyOther => 'Nenhuma corrida pública ainda.';

  @override
  String get profileFollowersEmpty => 'Nenhum seguidor ainda.';

  @override
  String get profileFollowingEmpty => 'Você ainda não segue ninguém.';

  @override
  String profileLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get profileLoadMoreFollowersFailed =>
      'Não foi possível carregar mais seguidores';

  @override
  String get profileLoadMoreFollowingFailed =>
      'Não foi possível carregar mais seguidos';

  @override
  String profileFollowUpdateFailed(String error) {
    return 'Não foi possível atualizar o seguimento: $error';
  }

  @override
  String profileBlockConfirmTitle(String name) {
    return 'Bloquear $name?';
  }

  @override
  String get profileBlockConfirmBody =>
      'Essa pessoa não poderá seguir você, dar kudos às suas corridas nem comentá-las. Qualquer seguimento existente entre vocês em qualquer direção será removido. Você pode desbloquear nesta página a qualquer momento.';

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
    return 'Não foi possível bloquear: $error';
  }

  @override
  String profileUnblocked(String name) {
    return '$name desbloqueado';
  }

  @override
  String profileUnblockFailed(String error) {
    return 'Não foi possível desbloquear: $error';
  }

  @override
  String get profileNotifAll => 'Todas';

  @override
  String get profileNotifUnread => 'Não lidas';

  @override
  String get profileMarkAllRead => 'Marcar todas como lidas';

  @override
  String profileMarkAllReadFailed(String error) {
    return 'Não foi possível marcar todas como lidas: $error';
  }

  @override
  String get profileNotifsCaughtUp => 'Você está em dia.';

  @override
  String get profileNotifsEmpty => 'Nenhuma notificação ainda.';

  @override
  String get profileDismiss => 'Dispensar';

  @override
  String profileDismissFailed(String error) {
    return 'Não foi possível dispensar: $error';
  }

  @override
  String get profileNotifSomeone => 'Alguém';

  @override
  String get profileNotifYourRun => 'sua corrida';

  @override
  String profileNotifKudos(String name, String dist) {
    return '$name deu kudos à sua $dist';
  }

  @override
  String profileNotifComment(String name, String dist) {
    return '$name comentou na sua $dist';
  }

  @override
  String profileNotifCommentReply(String name) {
    return '$name respondeu ao seu comentário';
  }

  @override
  String profileNotifFollow(String name) {
    return '$name começou a seguir você';
  }

  @override
  String profileNotifEventRsvpTitled(String name, String title) {
    return '$name confirmou presença no seu evento \"$title\"';
  }

  @override
  String profileNotifEventRsvp(String name) {
    return '$name confirmou presença no seu evento';
  }

  @override
  String profileNotifPlanUpdate(String name) {
    return '$name atualizou seu plano de treino';
  }

  @override
  String profileNotifMessage(String name) {
    return '$name enviou uma mensagem para você';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$name publicou em $club';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$name publicou em um clube do qual você participa';
  }

  @override
  String profileNotifRunCompletedDist(String name, String dist) {
    return '$name concluiu uma corrida de $dist';
  }

  @override
  String profileNotifRunCompleted(String name) {
    return '$name concluiu uma corrida';
  }

  @override
  String profileNotifGeneric(String name) {
    return '$name interagiu com sua atividade';
  }

  @override
  String get socialTabFeed => 'Feed';

  @override
  String get socialTabPeople => 'Pessoas';

  @override
  String get socialTabClubs => 'Clubes';

  @override
  String get socialTabRoutes => 'Rotas';

  @override
  String get socialTabDiscover => 'Descobrir';

  @override
  String get discoverSearchPlaceholder =>
      'Buscar yoga, pilates, HIIT, clubes de corrida…';

  @override
  String get discoverActivityAll => 'Todas as atividades';

  @override
  String get discoverCadenceLabel => 'Frequência';

  @override
  String get discoverCadenceAny => 'Qualquer frequência';

  @override
  String get discoverOneOff => 'Único';

  @override
  String get discoverWeekly => 'Semanal';

  @override
  String get discoverBiweekly => 'A cada 2 semanas';

  @override
  String get discoverMonthly => 'Mensal';

  @override
  String get discoverDayLabel => 'Dia';

  @override
  String get discoverDayAny => 'Qualquer dia';

  @override
  String get discoverDayMon => 'Seg';

  @override
  String get discoverDayTue => 'Ter';

  @override
  String get discoverDayWed => 'Qua';

  @override
  String get discoverDayThu => 'Qui';

  @override
  String get discoverDayFri => 'Sex';

  @override
  String get discoverDaySat => 'Sáb';

  @override
  String get discoverDaySun => 'Dom';

  @override
  String get discoverTimeLabel => 'Hora do dia';

  @override
  String get discoverTimeAny => 'Qualquer hora';

  @override
  String get discoverMorning => 'Manhã';

  @override
  String get discoverAfternoon => 'Tarde';

  @override
  String get discoverEvening => 'Noite';

  @override
  String get discoverPriceLabel => 'Preço';

  @override
  String get discoverPriceAny => 'Qualquer preço';

  @override
  String get discoverFree => 'Grátis';

  @override
  String get discoverPaid => 'Pago';

  @override
  String get discoverLoading => 'Buscando…';

  @override
  String get discoverEmpty =>
      'Nenhuma atividade pública corresponde a esses filtros ainda.';

  @override
  String get discoverSearchFailed =>
      'Não foi possível carregar as atividades. Verifique sua conexão e tente novamente.';

  @override
  String get clubsTitle => 'Clubes';

  @override
  String get clubsFindPeople => 'Encontrar pessoas';

  @override
  String get clubsNewClub => 'Novo clube';

  @override
  String get clubsTabBrowse => 'Explorar';

  @override
  String get clubsTabMine => 'Meus clubes';

  @override
  String get clubsJoinWithCode => 'Entrar com código de convite';

  @override
  String get clubsSearchHint => 'Pesquisar por nome ou local';

  @override
  String get clubsTimeoutError =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String get clubsLoadError =>
      'Não foi possível carregar os clubes. Toque em Tentar novamente.';

  @override
  String get clubsBadgePrivate => 'PRIVADO';

  @override
  String clubsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros',
      one: '$count membro',
    );
    return '$_temp0';
  }

  @override
  String get clubsEmptyBrowseTitle =>
      'Nenhum clube corresponde a essa pesquisa.';

  @override
  String get clubsEmptyMineTitle => 'Você ainda não entrou em nenhum clube.';

  @override
  String get clubsEmptyBrowseBody => 'Tente outro nome ou local.';

  @override
  String get clubsEmptyMineBody => 'Vá em Explorar para encontrar um.';

  @override
  String get clubDetailTabFeed => 'Feed';

  @override
  String get clubDetailTabEvents => 'Eventos';

  @override
  String get clubDetailTabMembers => 'Membros';

  @override
  String get clubDetailTabRoutes => 'Rotas';

  @override
  String get clubDetailTabTemplates => 'Modelos';

  @override
  String get clubDetailTabPhotos => 'Fotos';

  @override
  String get clubDetailReportClub => 'Denunciar clube';

  @override
  String get clubDetailReportPost => 'Denunciar esta publicação';

  @override
  String get clubDetailLoadFailedTitle =>
      'Não foi possível carregar este clube.';

  @override
  String get clubDetailLoadFailedBody =>
      'Pode ter sido removido, ou sua sessão precisa ser atualizada. Puxe para tentar novamente, ou saia e entre novamente em Configurações.';

  @override
  String get clubDetailRetry => 'Tentar novamente';

  @override
  String get clubDetailTimeoutError =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String get clubDetailRequestSent =>
      'Solicitação enviada aos administradores.';

  @override
  String clubDetailLeaveTitle(String club) {
    return 'Sair de $club?';
  }

  @override
  String get clubDetailCancel => 'Cancelar';

  @override
  String get clubDetailLeave => 'Sair';

  @override
  String clubDetailReplyFailed(String error) {
    return 'Não foi possível publicar a resposta: $error';
  }

  @override
  String get clubDetailMemberFallback => 'Membro';

  @override
  String get clubDetailRequestPending => 'Solicitação pendente';

  @override
  String get clubDetailInviteOnly => 'Apenas com convite';

  @override
  String get clubDetailRequest => 'Solicitar';

  @override
  String get clubDetailJoin => 'Entrar';

  @override
  String get clubDetailOwner => 'Proprietário';

  @override
  String get clubDetailNextEvent => 'PRÓXIMO EVENTO';

  @override
  String clubDetailGoingCount(int count) {
    return '$count confirmados';
  }

  @override
  String get clubDetailNoPostsMember =>
      'Nenhuma publicação ainda. Compartilhe uma novidade com os membros.';

  @override
  String get clubDetailNoPosts => 'Nenhuma novidade ainda.';

  @override
  String get clubDetailShareUpdateHint => 'Compartilhe uma novidade…';

  @override
  String get clubDetailPost => 'Publicar';

  @override
  String get clubDetailReply => 'Responder';

  @override
  String clubDetailHideReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ocultar $count respostas',
      one: 'Ocultar $count resposta',
    );
    return '$_temp0';
  }

  @override
  String clubDetailShowReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count respostas',
      one: '$count resposta',
    );
    return '$_temp0';
  }

  @override
  String clubDetailReplyAuthorLine(String name, String time) {
    return '$name · $time';
  }

  @override
  String get clubDetailWriteReplyHint => 'Escreva uma resposta…';

  @override
  String get clubDetailSend => 'Enviar';

  @override
  String get clubDetailNoEventsAdmin =>
      'Nenhum evento futuro. Toque em Criar para adicionar um.';

  @override
  String get clubDetailNoEvents => 'Nenhum evento futuro.';

  @override
  String get clubDetailCreateEvent => 'Criar evento';

  @override
  String get clubDetailGoing => 'Confirmado';

  @override
  String clubDetailApproveFailed(String error) {
    return 'Falha ao aprovar: $error';
  }

  @override
  String clubDetailDenyFailed(String error) {
    return 'Falha ao recusar: $error';
  }

  @override
  String clubDetailPendingRequests(int count) {
    return 'Solicitações pendentes ($count)';
  }

  @override
  String clubDetailUserShort(String id) {
    return 'Usuário $id…';
  }

  @override
  String get clubDetailDeny => 'Recusar';

  @override
  String get clubDetailApprove => 'Aprovar';

  @override
  String clubDetailMemberCountLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros.',
      one: '$count membro.',
    );
    return '$_temp0';
  }

  @override
  String clubDetailRouteSaved(String name) {
    return '\"$name\" salva';
  }

  @override
  String get clubDetailBuildRoute => 'Criar rota para este clube';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'Nenhuma rota ainda. Crie o percurso oficial acima, ou transfira uma das suas rotas pessoais na tela de detalhes da rota.';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'Nenhuma rota ainda. Os administradores podem transferir uma de suas rotas pessoais na tela de detalhes da rota.';

  @override
  String get clubDetailRoutesEmpty =>
      'Nenhuma rota compartilhada com este clube ainda.';

  @override
  String get clubDetailTemplateAdded => 'Modelo adicionado aos seus planos.';

  @override
  String clubDetailAdoptFailed(String error) {
    return 'Falha ao adotar: $error';
  }

  @override
  String get clubDetailNoTemplatesAdmin =>
      'Nenhum modelo ainda. Publique um dos seus planos na página de detalhes.';

  @override
  String get clubDetailNoTemplates =>
      'Nenhum modelo de plano para este clube ainda.';

  @override
  String get clubDetailAdopt => 'Adotar';

  @override
  String get clubDetailSessionTemplatesTitle => 'Modelos de sessão';

  @override
  String get clubDetailSessionAdopted => 'Sessão adicionada aos seus planos.';

  @override
  String get clubDetailGymRoutineTemplatesTitle =>
      'Modelos de rotina de academia';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'Os membros podem adotar uma rotina de academia do clube nas próprias rotinas. As edições em uma cópia não se propagam para o modelo.';

  @override
  String get clubDetailGymRoutineAdopted =>
      'Rotina adicionada às suas rotinas de academia.';

  @override
  String clubDetailRoutineExerciseCount(int n) {
    return '$n exercícios';
  }

  @override
  String get eventNotFound => 'Evento não encontrado.';

  @override
  String get eventLoadError =>
      'Não foi possível carregar este evento. Toque em Tentar novamente.';

  @override
  String get eventTimeoutError =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String eventDurationMin(int minutes) {
    return '· $minutes min';
  }

  @override
  String eventGetDirectionsTo(String label) {
    return 'Como chegar a $label';
  }

  @override
  String get eventGetDirections => 'Como chegar';

  @override
  String get eventCouldNotOpenMaps => 'Não foi possível abrir os mapas.';

  @override
  String get eventPickOccurrence => 'ESCOLHA UMA OCORRÊNCIA';

  @override
  String get eventTargetPace => 'Ritmo alvo';

  @override
  String get eventClassSessionEyebrow => 'AULA';

  @override
  String get eventResultSubmitted => 'Resultado enviado.';

  @override
  String eventSubmitFailed(String error) {
    return 'Falha ao enviar: $error';
  }

  @override
  String eventRaceControlFailed(String error) {
    return 'Falha no controle da corrida: $error';
  }

  @override
  String eventAttendees(int count) {
    return 'PARTICIPANTES ($count)';
  }

  @override
  String get eventNoRsvps => 'Nenhuma confirmação ainda — seja o primeiro.';

  @override
  String get eventAttendeeMember => 'Membro';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventMarkAttended => 'Marcar como presente';

  @override
  String get eventMarkNoShow => 'Marcar como ausente';

  @override
  String get eventAttendanceAttended => 'Presente';

  @override
  String get eventAttendanceNoShow => 'Ausente';

  @override
  String get eventAttendanceFailed =>
      'Não foi possível atualizar a presença. Tente novamente.';

  @override
  String get eventRsvpFailed =>
      'Não foi possível atualizar sua confirmação. Tente novamente.';

  @override
  String get eventRsvpGoing => 'Eu vou';

  @override
  String get eventRsvpMaybe => 'Talvez';

  @override
  String get eventRsvpDeclined => 'Não posso ir';

  @override
  String get eventRaceArmed => 'Armado — aguardando o GO';

  @override
  String get eventRaceRunning => 'Em andamento — ao vivo';

  @override
  String get eventRaceFinished => 'Concluído';

  @override
  String get eventRaceCancelled => 'Cancelado';

  @override
  String get eventRaceNotArmed => 'Não armado';

  @override
  String get eventRaceControlLabel => 'CONTROLE DA CORRIDA';

  @override
  String get eventRaceAutoApprove =>
      'Aprovar automaticamente os tempos enviados';

  @override
  String get eventRaceArm => 'Armar corrida';

  @override
  String get eventRaceArmedHint =>
      'Toque em Disparar o Go quando a corrida começar. Os relógios dos participantes mostram agora o aviso de armado.';

  @override
  String get eventRaceFireGo => 'Disparar o Go';

  @override
  String get eventRaceCancel => 'Cancelar';

  @override
  String eventRaceStartedAt(String time) {
    return 'Iniciada às $time';
  }

  @override
  String get eventRaceEnd => 'Encerrar corrida';

  @override
  String get eventRaceCancelRace => 'Cancelar corrida';

  @override
  String get eventRaceEndConfirmBody =>
      'Encerrar a corrida? Isso finaliza o evento para todos os corredores e não pode ser desfeito.';

  @override
  String get eventRaceCancelConfirmBody =>
      'Cancelar a corrida? Isso aborta o evento para todos os corredores e não pode ser desfeito.';

  @override
  String get eventUpdatePosted => 'Novidade publicada no feed do clube.';

  @override
  String eventPostUpdateFailed(String error) {
    return 'Não foi possível publicar a novidade: $error';
  }

  @override
  String get eventPostUpdateLabel => 'PUBLICAR UMA NOVIDADE';

  @override
  String get eventUpdateHint =>
      'Decisão por causa do tempo? Encontro em outro local?';

  @override
  String get eventPostUpdate => 'Publicar novidade';

  @override
  String get eventResultsTitle => 'Resultados';

  @override
  String get eventRemoveMine => 'Remover o meu';

  @override
  String get eventRemoveResultTitle => 'Remover seu resultado?';

  @override
  String get eventRemoveResultBody =>
      'Seu tempo de chegada enviado será removido da classificação deste evento. Você pode enviar novamente mais tarde.';

  @override
  String get eventRemoveResultConfirm => 'Remover resultado';

  @override
  String eventRemoveResultFailed(String error) {
    return 'Não foi possível remover seu resultado: $error';
  }

  @override
  String get eventSubmitMyTime => 'Enviar meu tempo';

  @override
  String get eventSubmitting => 'Enviando…';

  @override
  String get eventNoResults =>
      'Nenhum resultado ainda. Envie seu tempo após o evento e os outros verão aqui.';

  @override
  String get eventResultRunner => 'Corredor';

  @override
  String get eventResultYou => '(você)';

  @override
  String get eventSubmitTimeTitle => 'Envie seu tempo';

  @override
  String get eventSubmitTimeSubtitle =>
      'Escolha uma corrida para anexar, ou registre um DNF / DNS.';

  @override
  String get eventNoRecentRuns =>
      'Nenhuma corrida recente encontrada. Registre uma corrida primeiro e volte.';

  @override
  String get eventRecordDnf => 'Registrar DNF';

  @override
  String get eventRecordDns => 'Registrar DNS';

  @override
  String get eventSubmitCancel => 'Cancelar';

  @override
  String get liveSpectatorTitle => 'Acompanhamento ao vivo';

  @override
  String get liveSpectatorConnectError => 'Não foi possível conectar.';

  @override
  String get liveSpectatorWaiting =>
      'Aguardando o corredor enviar o primeiro sinal…';

  @override
  String get liveSpectatorBadgeLive => 'Ao vivo';

  @override
  String get liveSpectatorBadgeIdle => 'Parado';

  @override
  String get liveSpectatorBadgeConnecting => 'Conectando';

  @override
  String get liveSpectatorBadgeStale => 'Atrasado';

  @override
  String get liveSpectatorBadgeApproximate => 'Aproximado';

  @override
  String get liveSpectatorApproximateSub =>
      'Visto pela última vez perto daqui — aproximado';

  @override
  String get liveSpectatorBadgeFinished => 'Concluído';

  @override
  String get liveSpectatorBadgeDnf => 'DNF';

  @override
  String get liveUpdatedNow => 'Atualizado agora mesmo';

  @override
  String liveUpdatedSeconds(int n) {
    return 'Atualizado há ${n}s';
  }

  @override
  String liveUpdatedMinutes(int n) {
    return 'Atualizado há $n min';
  }

  @override
  String liveUpdatedHours(int n) {
    return 'Atualizado há $n h';
  }

  @override
  String liveUpdatedDays(int n) {
    return 'Atualizado há $n d';
  }

  @override
  String get liveCutoffTitle => 'Próximo corte';

  @override
  String liveCutoffToGo(String distance) {
    return 'Faltam $distance';
  }

  @override
  String liveCutoffEta(String eta) {
    return 'Chegada prevista $eta';
  }

  @override
  String liveCutoffAhead(String margin) {
    return '$margin de margem';
  }

  @override
  String liveCutoffBehind(String margin) {
    return '$margin de atraso';
  }

  @override
  String get liveCutoffWaitingSignal =>
      'À espera de um sinal recente para prever a chegada';

  @override
  String get plansTitle => 'Planos de treino';

  @override
  String get plansNewPlan => 'Novo plano';

  @override
  String plansDeleteTitle(String name) {
    return 'Excluir \"$name\"?';
  }

  @override
  String get plansDeleteBody => 'Todas as semanas e treinos serão removidos.';

  @override
  String get plansCancel => 'Cancelar';

  @override
  String get plansDelete => 'Excluir';

  @override
  String get plansAbandon => 'Abandonar';

  @override
  String plansAbandonTitle(String name) {
    return 'Abandonar \"$name\"?';
  }

  @override
  String get plansAbandonBody => 'Depois você pode criar um novo plano.';

  @override
  String plansActionFailed(String error) {
    return 'Não foi possível atualizar o plano: $error';
  }

  @override
  String plansDaysPerWeek(int count) {
    return '$count dias/sem.';
  }

  @override
  String get plansSignInTitle => 'Entre para usar os planos de treino';

  @override
  String get plansSignInBody =>
      'Os planos sincronizam com a sua conta e acompanham você em todos os dispositivos. Vá em Configurações → Entrar para conectar.';

  @override
  String get plansEmptyTitle => 'Nenhum plano ainda.';

  @override
  String get plansEmptyBody =>
      'Escolha uma prova-alvo e montaremos as semanas para você.';

  @override
  String get plansTimeoutError =>
      'Tempo de conexão esgotado. Verifique sua rede e tente novamente.';

  @override
  String get plansLoadError =>
      'Não foi possível carregar os planos de treino. Toque em tentar novamente.';

  @override
  String get planNewTitle => 'Novo plano';

  @override
  String get planNewNameLabel => 'Nome do plano';

  @override
  String get planNewNameHint => 'ex. Meia maratona de outono';

  @override
  String get planNewGoalRace => 'Prova-alvo';

  @override
  String get planNewStartDate => 'Data de início';

  @override
  String get planNewDaysPerWeek => 'Dias por semana';

  @override
  String planNewDaysOption(int count) {
    return '$count dias';
  }

  @override
  String get planNewGoalTimeSection => 'Tempo-alvo · opcional';

  @override
  String get planNewBeginnerTitle =>
      'Começando a correr? Use um plano de caminhada-corrida';

  @override
  String get planNewBeginnerSubtitle =>
      'Um cronograma suave no estilo C25K de intervalos cronometrados de corrida/caminhada que evolui até uma corrida contínua. Substitui o ritmo do tempo-alvo.';

  @override
  String get planNewRecent5kSection => 'Tempo recente de 5K · opcional';

  @override
  String get planNewRecent5kHelp =>
      'Baseie os ritmos em um resultado real em vez da meta. Usa a equivalência de Riegel para projetar até a distância-alvo.';

  @override
  String get planNewRecent5kConfirm =>
      'É um tempo que eu conseguiria correr hoje — reflete meu condicionamento atual.';

  @override
  String get planNewRecent5kWarning =>
      'Até você confirmar, os ritmos permanecem na estimativa conservadora baseada na meta. Basear-se em um resultado antigo pode prescrever ritmos rápidos demais para quem está voltando.';

  @override
  String get planNewOverrideHint => 'Substituir o total de semanas';

  @override
  String planNewOverrideLabel(int count) {
    return 'Substituir semanas (padrão: $count)';
  }

  @override
  String get planNewCancel => 'Cancelar';

  @override
  String get planNewCreate => 'Criar plano';

  @override
  String get planNewCreating => 'Criando…';

  @override
  String get planNewPreviewTitle => 'Prévia';

  @override
  String get planNewPaceEasy => 'Leve';

  @override
  String get planNewPaceMarathon => 'Maratona';

  @override
  String get planNewPaceTempo => 'Tempo';

  @override
  String get planNewPaceInterval => 'Intervalo';

  @override
  String get planNewPaceRep => 'Repetição';

  @override
  String get planNewPacesFallback =>
      'Ritmos estimados — adicione uma corrida recente ou um tempo-alvo para metas personalizadas.';

  @override
  String planNewVdot(String value) {
    return 'VDOT de Daniels: $value';
  }

  @override
  String get planNewWeekOutline => 'Resumo das semanas';

  @override
  String planNewMoreWeeks(int count) {
    return '+ $count semanas a mais';
  }

  @override
  String planNewSessions(int count) {
    return '$count sessões';
  }

  @override
  String get planNewTemplateTitle => 'Começar com um modelo do clube';

  @override
  String get planNewTemplateSubtitle =>
      'Adote um plano que um clube ao qual você pertence publicou. Ele é clonado na sua conta com a data de início abaixo — edite como qualquer outro plano.';

  @override
  String get planNewTemplateButton => 'Ver modelos';

  @override
  String get planNewTemplateCloning => 'Adotando…';

  @override
  String planNewTemplateCloneFailed(String error) {
    return 'Não foi possível adotar esse modelo: $error';
  }

  @override
  String get planNewTemplatePickerTitle => 'Escolha um modelo';

  @override
  String get planNewTemplatePickerCancel => 'Cancelar';

  @override
  String get planLibraryTitle => 'Biblioteca pública de planos';

  @override
  String get planLibrarySubheading =>
      'Planos publicados por outros corredores. Clone um na sua conta para começar a treinar.';

  @override
  String get planLibrarySearchHint => 'Buscar planos por nome';

  @override
  String get planLibraryLoadError =>
      'Não foi possível carregar a biblioteca. Tente novamente.';

  @override
  String get planLibraryRetry => 'Tentar novamente';

  @override
  String get planLibraryEmpty => 'Ainda não há planos publicados.';

  @override
  String planLibraryEmptySearch(String query) {
    return 'Nenhum plano corresponde a “$query”.';
  }

  @override
  String planLibraryByAuthor(String author) {
    return 'por $author';
  }

  @override
  String get planLibraryAnonymous => 'um corredor';

  @override
  String planLibraryWeeks(int weeks) {
    return '$weeks semanas';
  }

  @override
  String planLibraryDaysPerWeek(int days) {
    return '$days×/semana';
  }

  @override
  String get planLibraryClone => 'Clonar nos meus planos';

  @override
  String get planLibraryCloning => 'Clonando…';

  @override
  String get planLibraryCloneSuccess => 'Plano clonado.';

  @override
  String planLibraryCloneFailed(String error) {
    return 'Falha ao clonar: $error';
  }

  @override
  String get planLibraryStartDate => 'Data de início';

  @override
  String get planLibraryNotFound =>
      'Este plano não está mais na biblioteca pública.';

  @override
  String get planLibraryPreviewWeeks => 'Semanas';

  @override
  String planLibraryPreviewWeek(int n) {
    return 'Semana $n';
  }

  @override
  String get planDetailPublishLibraryLabel => 'Biblioteca pública de planos';

  @override
  String get planDetailPublishLibrary => 'Publicar na biblioteca';

  @override
  String get planDetailPublishLibraryHint =>
      'Compartilhe uma cópia deste plano para que qualquer pessoa possa cloná-lo. Seus dados de condicionamento não são compartilhados.';

  @override
  String get planDetailPublishLibrarySuccess =>
      'Plano publicado na biblioteca pública. Seu plano pessoal não muda.';

  @override
  String planDetailPublishLibraryFailed(String error) {
    return 'Falha ao publicar: $error';
  }

  @override
  String get planDetailUnpublishLibrary => 'Remover';

  @override
  String get planDetailUnpublishSuccess => 'Removido da biblioteca pública.';

  @override
  String planDetailUnpublishFailed(String error) {
    return 'Falha ao remover: $error';
  }

  @override
  String get planDetailAlreadyPublished =>
      'Este plano está na biblioteca pública.';

  @override
  String get plansBrowseLibrary => 'Explorar biblioteca';

  @override
  String get planNewStarterTitle => 'Começar com um plano integrado';

  @override
  String get planNewStarterSubtitle =>
      'Escolha um plano de treino comprovado e o agendamos a partir da sua data de início; você pode ajustá-lo depois.';

  @override
  String get planNewStarterButton => 'Explorar planos iniciais';

  @override
  String get planNewStarterCreating => 'Criando…';

  @override
  String get planNewStarterPickerTitle => 'Escolha um plano inicial';

  @override
  String get planNewStarterPickerCancel => 'Cancelar';

  @override
  String planNewStarterCreateFailed(String error) {
    return 'Não foi possível criar esse plano: $error';
  }

  @override
  String get planNewStarterC25k => 'Couch to 5K (iniciante caminhada-corrida)';

  @override
  String get planNewStarterHalf12 => 'Meia maratona — 12 semanas';

  @override
  String get planNewStarterMarathon16 => 'Maratona — 16 semanas';

  @override
  String get planDetailTimeoutError =>
      'Tempo de conexão esgotado. Verifique sua rede e tente novamente.';

  @override
  String get planDetailLoadError =>
      'Não foi possível carregar este plano. Toque em tentar novamente.';

  @override
  String get planDetailNotFound => 'Plano não encontrado.';

  @override
  String get planDetailLongestLongRun => 'Corrida longa mais longa';

  @override
  String get planDetailPublishTooltip => 'Publicar como modelo do clube';

  @override
  String planDetailDaysPerWeek(int count) {
    return '$count dias/sem.';
  }

  @override
  String get planDetailCurrentWeek => 'Esta semana';

  @override
  String get planDetailToday => 'HOJE';

  @override
  String get planDetailCompleted => 'Concluído';

  @override
  String planDetailWeek(int number) {
    return 'Semana $number';
  }

  @override
  String planDetailDriftOverFlag(int pct) {
    return 'Esta semana $pct% acima do plano — pegue leve nos dias fáceis para não cavar um buraco de fadiga.';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return 'Esta semana $pct% abaixo do plano — o volume planejado impulsiona a adaptação.';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      'Você perdeu o longão desta semana — encaixe se puder. É a sessão que mais importa.';

  @override
  String get planDetailMissedLongTaper =>
      'Você perdeu um longão, mas está em polimento — deixe pra lá e chegue descansado para a prova.';

  @override
  String get planDetailMissedLongRecovery =>
      'Você perdeu um longão — não tente repor. Uma semana de recuperação vem aí e seu corpo vai aproveitar o descanso.';

  @override
  String get planDetailReplan => 'Replanejar as semanas restantes';

  @override
  String get planDetailAdaptiveReplan => 'Replanejamento adaptativo';

  @override
  String get planDetailAdaptiveOnTrack =>
      'Suas últimas semanas estão dentro do plano — nenhum ajuste necessário.';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      'Você se desviou do plano recentemente, mas não há um ajuste seguro a fazer agora.';

  @override
  String get planDetailAdaptiveFitnessHeld =>
      'Pausado — você está acumulando fadiga agora, então aumentar o volume não é recomendado.';

  @override
  String get planDetailAdaptiveReasonUnder =>
      'abaixo do seu plano por várias semanas';

  @override
  String get planDetailAdaptiveReasonOver =>
      'acima do seu plano por várias semanas';

  @override
  String get planDetailAdaptiveConfidenceHigh => 'confiança alta';

  @override
  String get planDetailAdaptiveConfidenceMedium => 'confiança média';

  @override
  String planDetailAdaptiveBadge(String reason, String confidence) {
    return 'Com base em uma tendência — você esteve $reason ($confidence)';
  }

  @override
  String get planDetailReplanOnTrack =>
      'Seu plano está em dia — nada a ajustar.';

  @override
  String planDetailReplanApplied(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n treinos ajustados',
      one: '1 treino ajustado',
    );
    return '$_temp0';
  }

  @override
  String get planDetailReplanPreviewTitle => 'Mudanças propostas';

  @override
  String planDetailReplanMakeUp(String from, String to) {
    return 'Longão $from → $to — repor um longão perdido';
  }

  @override
  String planDetailReplanEase(String from, String to) {
    return '$from → $to — aliviar após excesso de volume';
  }

  @override
  String get planDetailReplanCancel => 'Cancelar';

  @override
  String get planDetailReplanApply => 'Aplicar mudanças';

  @override
  String get planDetailDuplicateWeek => 'Duplicar semana';

  @override
  String planDetailDuplicateWeekDone(int n) {
    return 'Semana $n duplicada';
  }

  @override
  String planDetailBulkFailed(String error) {
    return 'Não foi possível atualizar o plano: $error';
  }

  @override
  String get planDetailEditTooltip => 'Editar treino';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'Não foi possível carregar seus clubes — verifique sua rede.';

  @override
  String get planDetailPublishLoadClubsFailed =>
      'Não foi possível carregar seus clubes.';

  @override
  String get planDetailPublishNoClubs =>
      'Você precisa ser dono ou administrador de um clube para publicar um modelo.';

  @override
  String planDetailPublishSuccess(String name) {
    return '\"$name\" publicado como modelo do clube.';
  }

  @override
  String planDetailPublishFailed(String error) {
    return 'Falha ao publicar: $error';
  }

  @override
  String get planDetailPublishPickerTitle => 'Publicar no clube';

  @override
  String get planDetailPublishPickerBody =>
      'Os membros do clube poderão adotar este plano como seu.';

  @override
  String planDetailPublishPickerMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros',
      one: '$count membro',
    );
    return '$_temp0';
  }

  @override
  String get planDetailPublishCancel => 'Cancelar';

  @override
  String get workoutTimeoutError =>
      'Tempo de conexão esgotado. Verifique sua rede e tente novamente.';

  @override
  String get workoutLoadError =>
      'Não foi possível carregar este treino. Toque em tentar novamente.';

  @override
  String get workoutNotFound => 'Treino não encontrado.';

  @override
  String get workoutMetricDistance => 'Distância';

  @override
  String get workoutMetricDuration => 'Duração';

  @override
  String get workoutMetricTargetPace => 'Ritmo-alvo';

  @override
  String get workoutCompleted => 'Concluído';

  @override
  String get workoutUnlink => 'Desvincular';

  @override
  String get workoutUnlinkTitle => 'Desvincular corrida';

  @override
  String get workoutUnlinkBody =>
      'Desvincular a corrida associada? A sessão voltará a aparecer como não concluída.';

  @override
  String get workoutUnlinkError =>
      'Não foi possível desvincular a corrida. Tente novamente.';

  @override
  String get workoutSkipped => 'Ignorado';

  @override
  String get workoutSkip => 'Ignorar este treino';

  @override
  String get workoutUnskip => 'Desfazer ignorar';

  @override
  String get workoutSkipError =>
      'Não foi possível atualizar o status de ignorado. Tente novamente.';

  @override
  String get workoutRelink => 'Revincular';

  @override
  String get workoutRelinkTitle => 'Vincular outra corrida';

  @override
  String get workoutRelinkHint =>
      'Escolha uma corrida próxima da data deste treino para contá-la como esta sessão. Corridas já vinculadas a outro treino não são exibidas.';

  @override
  String get workoutRelinkLoading => 'Procurando suas corridas…';

  @override
  String get workoutRelinkError =>
      'Não foi possível carregar suas corridas. Tente novamente.';

  @override
  String get workoutRelinkEmpty => 'Nenhuma corrida elegível perto desta data.';

  @override
  String get workoutRelinkCurrent => 'Atual';

  @override
  String get workoutStart => 'Iniciar treino';

  @override
  String get workoutSectionNotes => 'Notas';

  @override
  String get workoutSectionStructure => 'Estrutura';

  @override
  String get workoutSectionHowTo => 'Como correr';

  @override
  String get workoutStructWarmup => 'Aquecimento';

  @override
  String get workoutStructRepeats => 'Repetições';

  @override
  String get workoutStructSteady => 'Constante';

  @override
  String get workoutStructCooldown => 'Desaquecimento';

  @override
  String workoutStructWarmupValue(String distance) {
    return '$distance @ leve';
  }

  @override
  String workoutStructCooldownValue(String distance) {
    return '$distance @ leve';
  }

  @override
  String get workoutAdviceEasy =>
      'Ritmo de conversa. Se você não consegue conversar, está correndo rápido demais.';

  @override
  String get workoutAdviceLong =>
      'Fique relaxado. Busque uma respiração constante. Reduza 10% da distância se o clima estiver ruim ou você estiver dolorido — mas não pule.';

  @override
  String get workoutAdviceTempo =>
      '\"Confortavelmente difícil\". Você deve sentir que conseguiria manter o ritmo por cerca de uma hora em esforço máximo, mas não mais.';

  @override
  String get workoutAdviceInterval =>
      'Corra as repetições com intensidade suficiente para que a última pareça a primeira. Não escolha um ritmo que você só consiga manter por duas ou três repetições.';

  @override
  String get workoutAdviceMarathonPace =>
      'Trave exatamente no ritmo-alvo de maratona. Esta é uma sessão de ensaio — nem mais rápido, nem mais devagar.';

  @override
  String get workoutAdviceWalkRun =>
      'Alterne corrida leve e caminhada nos intervalos cronometrados. As pausas para caminhar fazem parte do treino — faça-as mesmo se estiver descansado.';

  @override
  String get workoutAdviceRace =>
      'Confie no plano. Não persiga um recorde no primeiro quilômetro.';

  @override
  String get workoutAdviceRest =>
      'Dia de descanso — se precisar se mexer, caminhe ou alongue.';

  @override
  String get coachTitle => 'Coach';

  @override
  String get coachNewConversation => 'Nova conversa';

  @override
  String get coachConsentHeadline => 'Antes de conversar com o Coach';

  @override
  String get coachConsentIntro =>
      'Para dar conselhos fundamentados, o Coach envia uma parte dos seus dados de treino à Anthropic, nosso provedor de modelos de IA nos Estados Unidos. Essa parte inclui:';

  @override
  String get coachConsentBulletProfile =>
      'Sua data de nascimento, gênero e zonas de FC, se definidas.';

  @override
  String get coachConsentBulletRuns =>
      'Uma amostra das suas corridas mais recentes.';

  @override
  String get coachConsentBulletPlan =>
      'O plano de treino ativo que você selecionou.';

  @override
  String get coachConsentBulletMessages =>
      'As mensagens de chat que você digita na tela abaixo.';

  @override
  String get coachConsentProcessing =>
      'A Anthropic processa os dados em nome da Threkir conforme seus termos de processamento; por padrão, não treinam seus modelos com dados de clientes da Threkir. Todos os detalhes — incluindo o mecanismo de transferência, a retenção e seus direitos de retirada — estão na nossa política de privacidade.';

  @override
  String get coachConsentAction =>
      'Toque em \"Eu consinto\" para continuar. Toque em cancelar para sair da página sem enviar dados.';

  @override
  String get coachConsentCancel => 'Cancelar';

  @override
  String get coachConsentAccept => 'Eu consinto — iniciar o Coach';

  @override
  String get coachConsentSaving => 'Registrando consentimento…';

  @override
  String get coachNoPlanOption => 'Sem plano (apenas corridas recentes)';

  @override
  String coachPlanActive(String name) {
    return '$name · ativo';
  }

  @override
  String coachPlanDone(String name) {
    return '$name · concluído';
  }

  @override
  String get coachNewChatTooltip => 'Novo chat';

  @override
  String get coachHistoryTooltip => 'Histórico de chat';

  @override
  String get coachNewChat => 'Novo chat';

  @override
  String coachActiveThread(String suffix) {
    return 'Ativo$suffix';
  }

  @override
  String get coachArchiveTapToView => 'Toque para ver · deslize para excluir';

  @override
  String get coachContextNoPlan => 'Sem plano';

  @override
  String coachContextPlanWeeks(String name, int weeks) {
    return '$name · $weeks sem.';
  }

  @override
  String get coachContextNoRuns => 'Sem corridas';

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
    return 'Visualizando arquivo · $label · somente leitura';
  }

  @override
  String get coachBackToActive => 'Voltar ao ativo';

  @override
  String get coachLimitReachedPro => 'Limite diário atingido. Volte amanhã.';

  @override
  String get coachLimitReachedFree =>
      'Limite diário atingido. O Pro tem um teto maior — atualize nas Configurações.';

  @override
  String coachMessagesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'restam $count mensagens hoje',
      one: 'resta $count mensagem hoje',
    );
    return '$_temp0';
  }

  @override
  String get coachEmptyPromptPlan =>
      'Pergunte sobre o treino de hoje, seu ritmo ou como as corridas recentes se comparam ao plano.';

  @override
  String get coachEmptyPromptNoPlan =>
      'Pergunte sobre suas corridas recentes, o ritmo de corridas leves ou o básico do treino.';

  @override
  String get coachSuggestPlanRest =>
      'Devo correr amanhã ou fazer um dia de descanso?';

  @override
  String get coachSuggestPlanOnTrack =>
      'Estou no caminho para o meu tempo-alvo?';

  @override
  String get coachSuggestPlanLongRun =>
      'Por que o longão desta semana importa?';

  @override
  String get coachSuggestPlanToday => 'No que devo focar no treino de hoje?';

  @override
  String get coachSuggestNoPlanLastRun => 'Como foi minha última corrida?';

  @override
  String get coachSuggestNoPlanEasyPace =>
      'Em que ritmo devem ser minhas corridas leves?';

  @override
  String get coachSuggestNoPlanWeekOff =>
      'Não corro há uma semana — o que devo fazer?';

  @override
  String get coachSuggestNoPlanTempo => 'O que é uma corrida de tempo?';

  @override
  String get coachEditCancel => 'Cancelar';

  @override
  String get coachEditSaveResend => 'Salvar e reenviar';

  @override
  String get coachActionCopy => 'Copiar';

  @override
  String get coachActionEdit => 'Editar';

  @override
  String get coachActionRegenerate => 'Regenerar';

  @override
  String get coachActionHelpful => 'Útil';

  @override
  String get coachActionNotHelpful => 'Não útil';

  @override
  String get coachComposerHintLimit => 'Limite diário atingido';

  @override
  String get coachComposerHint => 'Pergunte ao Coach…';

  @override
  String get coachArchiveTitle => 'Iniciar uma nova conversa?';

  @override
  String get coachArchiveBody =>
      'O chat atual vai para o histórico. Você pode revê-lo na barra lateral.';

  @override
  String get coachArchiveCancel => 'Cancelar';

  @override
  String get coachArchiveConfirm => 'Novo chat';

  @override
  String get coachSignInFirst => 'Por favor, entre primeiro.';

  @override
  String get coachSessionExpired =>
      'Sua sessão expirou. Por favor, entre novamente.';

  @override
  String coachDailyLimitError(int limit) {
    return 'Limite diário atingido ($limit mensagens). Volte amanhã!';
  }

  @override
  String coachGenericError(int code) {
    return 'Erro do Coach ($code)';
  }

  @override
  String get coachTransportError =>
      'Não foi possível alcançar o Coach. Verifique sua conexão e tente novamente.';

  @override
  String get coachStreamFailed => 'falha no fluxo';

  @override
  String coachNewConversationFailed(String error) {
    return 'Não foi possível iniciar uma nova conversa: $error';
  }

  @override
  String coachOpenArchiveFailed(String error) {
    return 'Não foi possível abrir o arquivo: $error';
  }

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Não foi possível excluir o arquivo: $error';
  }

  @override
  String get coachCopied => 'Copiado para a área de transferência';

  @override
  String get settingsAccountTitle => 'Conta';

  @override
  String get settingsAccountBackendNotConfigured => 'Backend não configurado';

  @override
  String get settingsAccountSignOutFailed =>
      'Falha ao sair — verifique sua conexão';

  @override
  String get settingsAccountChangePassword => 'Alterar senha';

  @override
  String get settingsAccountNewPassword => 'Nova senha';

  @override
  String get settingsAccountConfirm => 'Confirmar';

  @override
  String get settingsAccountCancel => 'Cancelar';

  @override
  String get settingsAccountSave => 'Salvar';

  @override
  String get settingsAccountPasswordTooShort =>
      'A senha deve ter pelo menos 8 caracteres';

  @override
  String get settingsAccountPasswordsMismatch => 'As senhas não coincidem';

  @override
  String get settingsAccountPasswordUpdated => 'Senha atualizada';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Não foi possível atualizar a senha: $error';
  }

  @override
  String get settingsAccountDeleteTitle => 'Excluir conta?';

  @override
  String get settingsAccountDeleteBody =>
      'Isso remove permanentemente suas corridas, rotas e perfil do servidor. Os dados locais do dispositivo são mantidos, a menos que você entre como um novo usuário. Isso não pode ser desfeito.';

  @override
  String get settingsAccountDeleteChallengeText =>
      'Digite \"DELETE\" para confirmar';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return 'Digite seu e-mail ($email) para confirmar';
  }

  @override
  String get settingsAccountDelete => 'Excluir';

  @override
  String get settingsAccountDeleteSignInFirst =>
      'Entre primeiro para excluir sua conta.';

  @override
  String get settingsAccountDeleted => 'Conta excluída';

  @override
  String get settingsAccountCoachConsentWithdraw =>
      'Retirar consentimento do Coach';

  @override
  String get settingsAccountCoachConsentActive =>
      'Impeça o Coach de usar seus dados de treino. Você pode consentir novamente quando quiser.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Consentimento do Coach retirado.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Falha ao retirar o consentimento: $error';
  }

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'Falha ao excluir a conta: $error';
  }

  @override
  String get settingsAccountNoRunsToExport => 'Nenhuma corrida para exportar.';

  @override
  String get settingsAccountCsvShareText => 'Run app — exportação de corridas';

  @override
  String settingsAccountCsvExportFailed(Object error) {
    return 'Falha na exportação CSV: $error';
  }

  @override
  String get settingsAccountBackupSignInFirst =>
      'Entre primeiro para fazer backup das suas corridas.';

  @override
  String get settingsAccountBackupPreparing => 'Preparando backup…';

  @override
  String get settingsAccountBackupShareText => 'Backup do Run app';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'Falha no backup: $error';
  }

  @override
  String get settingsAccountRestoreUnavailable =>
      'Serviço de backup indisponível.';

  @override
  String get settingsAccountRestoreTitle => 'Restaurar do backup?';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'Você não está conectado. As corridas serão restauradas neste dispositivo e sincronizadas com sua conta na próxima vez que você entrar.';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'Isso adiciona ou substitui corridas e rotas com IDs correspondentes no backup. Não excluirá corridas ou rotas que não estejam no backup.';

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
    return 'Restauradas $runs corridas · $tracks trajetos · $routes rotas$warnings';
  }

  @override
  String settingsAccountRestoreWarningsSuffix(int count) {
    return ' · $count avisos';
  }

  @override
  String settingsAccountRestoreFailed(Object error) {
    return 'Falha na restauração: $error';
  }

  @override
  String get settingsAccountOfflineMode => 'Modo off-line';

  @override
  String get settingsAccountSignedInSync =>
      'Conectado — as corridas serão sincronizadas';

  @override
  String get settingsAccountSignInToSync =>
      'Entre para sincronizar corridas entre dispositivos';

  @override
  String get settingsAccountSignOut => 'Sair';

  @override
  String get settingsAccountSignIn => 'Entrar';

  @override
  String get settingsAccountAvatar => 'Foto de perfil';

  @override
  String get settingsAccountAvatarHint => 'JPEG, PNG ou WebP, até 2 MB.';

  @override
  String get settingsAccountAvatarRemove => 'Remover foto';

  @override
  String get settingsAccountAvatarSaved => 'Foto de perfil atualizada.';

  @override
  String get settingsAccountAvatarRemoved => 'Foto de perfil removida.';

  @override
  String get settingsAccountAvatarUnsupported =>
      'Imagem não suportada — escolha JPEG, PNG ou WebP.';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return 'Não foi possível atualizar a foto: $error';
  }

  @override
  String get settingsAccountViewProfile => 'Ver perfil';

  @override
  String get settingsAccountViewProfileSubtitle =>
      'Suas corridas, seguidores, seguindo, notificações';

  @override
  String get settingsAccountGuidedRuns => 'Corridas guiadas';

  @override
  String get settingsAccountGuidedRunsSubtitle =>
      'Treinos roteirizados com voz de treinador e avisos por TTS';

  @override
  String get settingsAccountPrivacyZones => 'Zonas de privacidade';

  @override
  String get settingsAccountPrivacyZonesSubtitle =>
      'Corta o início/fim de trajetos públicos perto de casa';

  @override
  String get settingsAccountTrustedContacts => 'Contatos de confiança';

  @override
  String get settingsAccountTrustedContactsSubtitle =>
      'Pessoas designadas para o recurso planejado de corrida atrasada / pânico';

  @override
  String get settingsAccountSendErrorReports => 'Enviar relatórios de erro';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Dados anonimizados de falhas e erros para o Sentry (EUA). Desative para retirar o consentimento. Aplica-se na próxima inicialização.';

  @override
  String get settingsAccountErrorReportingEnabled =>
      'Relatórios de erro ativados — reinicie o app para aplicar.';

  @override
  String get settingsAccountErrorReportingDisabled =>
      'Relatórios de erro desativados — reinicie o app para aplicar.';

  @override
  String get settingsAccountImport => 'Importar de outro app';

  @override
  String get settingsAccountImportSubtitle => 'Strava, GPX, TCX';

  @override
  String get settingsAccountFullBackup => 'Backup completo';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'Cada corrida com seu trajeto GPS, além de rotas, perfil e preferências. Restaura na web ou no Android.';

  @override
  String get settingsAccountExportCsv => 'Exportar corridas como CSV';

  @override
  String get settingsAccountExportCsvSubtitle =>
      'Data, distância, duração, ritmo, origem — uma linha por corrida. Mesmo formato da exportação LGPD/GDPR da web.';

  @override
  String get settingsAccountRestoreTile => 'Restaurar do backup';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      'Escolha um backup .zip salvo anteriormente.';

  @override
  String get settingsAccountDeleteAccount => 'Excluir conta';

  @override
  String get settingsAccountDeleteAccountSubtitle =>
      'Remove permanentemente os dados do servidor';

  @override
  String get integrationsTitle => 'Integrações';

  @override
  String get integrationsJustNow => 'agora mesmo';

  @override
  String integrationsMinutesAgo(int minutes) {
    return 'há $minutes min';
  }

  @override
  String integrationsHoursAgo(int hours) {
    return 'há $hours h';
  }

  @override
  String integrationsDaysAgo(int days) {
    return 'há $days d';
  }

  @override
  String integrationsWeeksAgo(int weeks) {
    return 'há $weeks sem';
  }

  @override
  String integrationsCouldNotOpen(Object error) {
    return 'Não foi possível abrir: $error';
  }

  @override
  String get integrationsStravaBrowserHint =>
      'Conclua o login do Strava no navegador, depois volte aqui e puxe para atualizar.';

  @override
  String get integrationsStravaCancelled => 'Login do Strava cancelado.';

  @override
  String integrationsStravaSignInFailed(Object error) {
    return 'Falha no login do Strava: $error';
  }

  @override
  String get integrationsStravaCsrfMismatch =>
      'Login do Strava rejeitado: estado CSRF não corresponde. Tente novamente.';

  @override
  String integrationsStravaConnectFailed(String error) {
    return 'Falha ao conectar com o Strava: $error';
  }

  @override
  String get integrationsStravaConnected => 'Strava conectado.';

  @override
  String integrationsSyncResult(int imported, int skipped) {
    return 'Sincronizado. $imported novas, $skipped já presentes.';
  }

  @override
  String integrationsSyncFailed(Object error) {
    return 'Falha na sincronização: $error';
  }

  @override
  String get integrationsStravaDisconnectTitle => 'Desconectar o Strava?';

  @override
  String get integrationsStravaDisconnectBody =>
      'As atividades futuras deixarão de sincronizar automaticamente. As corridas já importadas permanecem no seu histórico.';

  @override
  String get integrationsCancel => 'Cancelar';

  @override
  String get integrationsDisconnect => 'Desconectar';

  @override
  String get integrationsStravaDisconnected => 'Strava desconectado.';

  @override
  String integrationsDisconnectFailed(Object error) {
    return 'Falha ao desconectar: $error';
  }

  @override
  String get integrationsParkrunTitle => 'Importar resultados do parkrun';

  @override
  String get integrationsParkrunBody =>
      'Digite seu número de atleta do parkrun (ex.: A123456). Buscaremos seu histórico de chegadas e adicionaremos os novos resultados à sua lista de corridas.';

  @override
  String get integrationsParkrunFieldLabel => 'Número de atleta';

  @override
  String get integrationsImport => 'Importar';

  @override
  String get integrationsParkrunImporting =>
      'Importando resultados do parkrun…';

  @override
  String integrationsParkrunImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados do parkrun importados.',
      one: '$count resultado do parkrun importado.',
    );
    return '$_temp0';
  }

  @override
  String get integrationsParkrunNoneNew =>
      'Nenhum novo resultado do parkrun desde a última importação.';

  @override
  String integrationsImportFailed(Object error) {
    return 'Falha na importação: $error';
  }

  @override
  String get integrationsStravaName => 'Strava';

  @override
  String get integrationsStravaConnectSubtitle =>
      'Conecte para sincronizar atividades automaticamente';

  @override
  String get integrationsStravaWaitingFirstSync =>
      'Conectado · aguardando a primeira sincronização';

  @override
  String integrationsStravaLastSync(String time) {
    return 'Conectado · última sincronização $time';
  }

  @override
  String get integrationsSyncNow => 'Sincronizar agora';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Importar resultados pelo número de atleta';

  @override
  String get integrationsSignInTitle => 'Entre para conectar serviços';

  @override
  String get integrationsSignInSubtitle =>
      'Strava + parkrun exigem uma conta para que as atividades sincronizadas entrem no seu histórico.';

  @override
  String get integrationsHealthConnectTitle =>
      'Gravar corridas no Health Connect';

  @override
  String get integrationsHealthConnectSubtitle =>
      'Envia cada corrida concluída ao Health Connect para que apareça no Google Fit, Samsung Health, Fitbit e outros.';

  @override
  String get integrationsHealthConnectDenied =>
      'Permissão do Health Connect não concedida — as corridas não serão gravadas.';

  @override
  String integrationsHrPairFailed(Object error) {
    return 'Falha no pareamento: $error';
  }

  @override
  String get integrationsHrTitle => 'Monitor de frequência cardíaca';

  @override
  String get integrationsHrChecking => 'Verificando…';

  @override
  String integrationsHrPaired(String name) {
    return 'Pareado: $name';
  }

  @override
  String get integrationsHrNotPaired =>
      'Nenhuma cinta pareada — toque para buscar';

  @override
  String get integrationsHrForget => 'Esquecer';

  @override
  String get integrationsHrForgetConfirm =>
      'Esquecer este monitor de frequência cardíaca? Terá de o emparelhar novamente para o usar durante uma corrida.';

  @override
  String get integrationsHrScanTitle => 'Buscar monitor de frequência cardíaca';

  @override
  String get integrationsHrScanHint =>
      'Ative sua cinta / faixa peitoral. Geralmente leva de 3 a 8 segundos.';

  @override
  String get integrationsHrScanEmpty =>
      'Nenhuma cinta encontrada. Verifique se está por perto e ativa.';

  @override
  String integrationsHrRssi(int rssi) {
    return 'RSSI $rssi dBm';
  }

  @override
  String get integrationsTreadmillTitle => 'Passadeira';

  @override
  String get integrationsTreadmillChecking => 'A verificar…';

  @override
  String integrationsTreadmillPaired(String name) {
    return 'Emparelhada: $name';
  }

  @override
  String get integrationsTreadmillNotPaired =>
      'Nenhuma passadeira emparelhada — toque para procurar';

  @override
  String get integrationsTreadmillForget => 'Esquecer';

  @override
  String get integrationsTreadmillForgetConfirm =>
      'Esquecer esta passadeira? Terá de a emparelhar novamente para a usar durante uma corrida.';

  @override
  String get integrationsTreadmillScanTitle => 'Procurar passadeira';

  @override
  String get integrationsTreadmillScanHint =>
      'Certifique-se de que o Bluetooth da passadeira está ligado e o tapete ativo. A procura demora 3 a 8 segundos.';

  @override
  String get integrationsTreadmillScanEmpty =>
      'Nenhuma passadeira encontrada. Verifique se suporta Bluetooth (FTMS) e está por perto.';

  @override
  String integrationsTreadmillPairFailed(Object error) {
    return 'Falha ao emparelhar: $error';
  }

  @override
  String integrationsTreadmillLiveSpeed(String speed) {
    return '$speed km/h';
  }

  @override
  String get proTitle => 'Pro e suporte';

  @override
  String proCouldNotOpen(Object error) {
    return 'Não foi possível abrir: $error';
  }

  @override
  String get proWelcome => 'Bem-vindo ao Pro! Carregando seus benefícios…';

  @override
  String get proPurchaseFailed =>
      'A compra falhou. Tente novamente mais tarde.';

  @override
  String get proRestoreNeedsSignIn =>
      'Para restaurar, você precisa estar conectado com o RevenueCat configurado. Gerencie sua assinatura na página de upgrade da web.';

  @override
  String get proRestored => 'Sua assinatura Pro foi restaurada.';

  @override
  String get proRestoreNone =>
      'Nenhuma compra ativa encontrada nesta conta da loja.';

  @override
  String get proRestoreFailed =>
      'A restauração falhou. Tente novamente mais tarde.';

  @override
  String get proRestoreUnavailable => 'Restauração indisponível nesta versão.';

  @override
  String proSubscribeTitle(String price) {
    return 'Assinar o Pro — $price/mês';
  }

  @override
  String get proSubscribeSubtitleConfigured =>
      'Treinador de IA ilimitado + processamento prioritário. Renova automaticamente todo mês até ser cancelado em Configurações → Assinaturas.';

  @override
  String get proSubscribeSubtitleWeb =>
      'Abre o portal de assinatura no seu navegador. Renova automaticamente todo mês até ser cancelado.';

  @override
  String get proRegionalNote =>
      'Cobrado em dólares americanos. A disponibilidade depende do seu país e forma de pagamento — algumas regiões não podem ser atendidas pelo nosso processador de pagamentos.';

  @override
  String get proRestorePurchases => 'Restaurar compras';

  @override
  String get proRestorePurchasesSubtitle =>
      'Revincule compras de uma instalação anterior ou de outro dispositivo';

  @override
  String get proManageSubscription => 'Gerenciar assinatura';

  @override
  String get proManageSubscriptionSubtitle =>
      'Cancelar, mudar de plano ou atualizar a forma de pagamento';

  @override
  String get proSupport => 'Apoiar o app';

  @override
  String get proSupportSubtitle => 'Doação única no seu navegador';

  @override
  String get licensesTitle => 'Licenças';

  @override
  String get licensesVersion => 'Versão';

  @override
  String get licensesOpenSource => 'Licenças de código aberto';

  @override
  String get licensesOpenSourceSubtitle =>
      'Pacotes de terceiros incluídos neste app';

  @override
  String get devicesTitle => 'Dispositivos';

  @override
  String get devicesRenameTitle => 'Renomear dispositivo';

  @override
  String get devicesCancel => 'Cancelar';

  @override
  String get devicesSave => 'Salvar';

  @override
  String devicesRenameFailed(Object error) {
    return 'Falha ao renomear: $error';
  }

  @override
  String get devicesRemoveTitle => 'Remover dispositivo?';

  @override
  String get devicesRemoveBodyCurrent =>
      'Este é o dispositivo que você está usando. Removê-lo apaga as substituições de preferências por dispositivo; o dispositivo continua conectado.';

  @override
  String get devicesRemoveBodyOther =>
      'Remove a entrada do dispositivo e quaisquer substituições de preferências por dispositivo. O dispositivo continua conectado até abrir o app novamente.';

  @override
  String get devicesRemove => 'Remover';

  @override
  String devicesRemoveFailed(Object error) {
    return 'Falha ao remover: $error';
  }

  @override
  String devicesSaveFailed(Object error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get devicesLoadError => 'Não foi possível carregar os dispositivos.';

  @override
  String get devicesEmpty =>
      'Ainda não há dispositivos — eles são registrados na primeira vez que um dispositivo abre o app conectado.';

  @override
  String get devicesThisDevice => 'Este dispositivo';

  @override
  String devicesLastSeen(String time) {
    return 'Visto pela última vez $time';
  }

  @override
  String devicesOverrideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count substituições',
      one: '$count substituição',
    );
    return '$_temp0';
  }

  @override
  String get devicesJustNow => 'agora mesmo';

  @override
  String devicesMinutesAgo(int minutes) {
    return 'há $minutes min';
  }

  @override
  String devicesHoursAgo(int hours) {
    return 'há $hours h';
  }

  @override
  String devicesDaysAgo(int days) {
    return 'há $days d';
  }

  @override
  String get devicesRename => 'Renomear';

  @override
  String get devicesEditOverrides => 'Editar substituições…';

  @override
  String get devicesEveryKeySet =>
      'Todas as chaves substituíveis já estão definidas; remova uma antes de adicionar outra.';

  @override
  String get devicesOverridesSheetTitle => 'Substituições por dispositivo';

  @override
  String get devicesOverridesSheetDesc =>
      'Essas chaves substituem as configurações universais apenas neste dispositivo.';

  @override
  String get devicesNoOverrides => 'Nenhuma substituição neste dispositivo.';

  @override
  String get devicesAddOverride => 'Adicionar substituição';

  @override
  String get devicesPickKey => 'Escolher uma chave';

  @override
  String get devicesEnterWholeNumber => 'Digite um número inteiro.';

  @override
  String get devicesEnterNumber => 'Digite um número (ex.: 0,8).';

  @override
  String get devicesValue => 'Valor';

  @override
  String get devicesBack => 'Voltar';

  @override
  String get devicesAdd => 'Adicionar';

  @override
  String get devicesKeyPreferredUnitLabel => 'Unidade preferida';

  @override
  String get devicesKeyPreferredUnitHint =>
      'Unidade de distância para todas as telas.';

  @override
  String get devicesKeyDefaultActivityLabel => 'Atividade padrão';

  @override
  String get devicesKeyDefaultActivityHint =>
      'Atividade pré-selecionada na tela inicial.';

  @override
  String get devicesKeyMapStyleLabel => 'Estilo do mapa';

  @override
  String get devicesKeyMapStyleHint =>
      'Estilo MapLibre para a visualização do mapa.';

  @override
  String get devicesKeyPaceFormatLabel => 'Formato de ritmo';

  @override
  String get devicesKeyPaceFormatHint => 'Formato de exibição do ritmo.';

  @override
  String get devicesKeyVoiceFeedbackLabel => 'Feedback de voz';

  @override
  String get devicesKeyVoiceFeedbackHint =>
      'Fala avisos de ritmo / distância durante uma corrida.';

  @override
  String get devicesKeyVoiceIntervalLabel =>
      'Intervalo de feedback de voz (km)';

  @override
  String get devicesKeyVoiceIntervalHint =>
      'Distância entre os avisos falados.';

  @override
  String get devicesKeyHapticLabel => 'Feedback tátil';

  @override
  String get devicesKeyHapticHint =>
      'Vibração em mudanças de volta e zona de ritmo.';

  @override
  String get devicesKeyKeepScreenOnLabel => 'Manter a tela ligada';

  @override
  String get devicesKeyKeepScreenOnHint =>
      'Desativa o escurecimento automático do SO durante a gravação.';

  @override
  String get gearTitle => 'Equipamento';

  @override
  String get gearAddGear => 'Adicionar equipamento';

  @override
  String get gearDeleteTitle => 'Excluir equipamento?';

  @override
  String gearDeleteBody(String name) {
    return 'Excluir \"$name\"? O histórico de quilometragem das corridas anteriores será perdido. Aposente em vez disso para manter os registros.';
  }

  @override
  String get gearCancel => 'Cancelar';

  @override
  String get gearDelete => 'Excluir';

  @override
  String get gearDeletedOffline =>
      'Excluído localmente — será sincronizado quando você reconectar.';

  @override
  String gearAttached(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name associado a $count corridas.',
      one: '$name associado a $count corrida.',
    );
    return '$_temp0';
  }

  @override
  String gearOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Off-line — $count edições na fila, mostrando equipamento em cache.',
      one: 'Off-line — $count edição na fila, mostrando equipamento em cache.',
    );
    return '$_temp0';
  }

  @override
  String get gearOfflineCached => 'Off-line — mostrando equipamento em cache.';

  @override
  String get gearShoes => 'Tênis';

  @override
  String get gearBikes => 'Bicicletas';

  @override
  String get gearRetired => 'APOSENTADO';

  @override
  String get gearEmptyShoes => 'Ainda não há tênis';

  @override
  String get gearEmptyBikes => 'Ainda não há bicicletas';

  @override
  String get gearEmptySubtitle =>
      'Adicione um par para acompanhar a quilometragem e receber lembretes de aposentadoria.';

  @override
  String gearRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get gearWearDue => 'Substituir em breve';

  @override
  String get gearWearWorn => 'Distância de troca ultrapassada';

  @override
  String get gearRetire => 'Aposentar';

  @override
  String get gearRestore => 'Restaurar';

  @override
  String get gearRotationsTitle => 'Rodízios';

  @override
  String get gearRotationsHint =>
      'Agrupe os equipamentos que você reveza — um conjunto de \"Treino diário\", um conjunto de \"Dia de prova\". Um rodízio é apenas um agrupamento nomeado; ele não muda qual par marca automaticamente as novas corridas.';

  @override
  String get gearRotationsEmpty =>
      'Nenhum rodízio ainda. Crie um para agrupar um conjunto de tênis ou bicicletas.';

  @override
  String get gearRotationName => 'Nome do rodízio';

  @override
  String get gearRotationNew => 'Novo rodízio';

  @override
  String get gearRotationCreate => 'Criar';

  @override
  String get gearRotationRename => 'Renomear';

  @override
  String get gearRotationManage => 'Editar equipamentos';

  @override
  String gearRotationManageTitle(String name) {
    return 'Equipamentos em \"$name\"';
  }

  @override
  String get gearRotationDeleteTitle => 'Excluir rodízio?';

  @override
  String gearRotationDeleteBody(String name) {
    return 'Excluir o rodízio \"$name\"? Seu equipamento não é afetado — apenas o agrupamento é removido.';
  }

  @override
  String gearRotationMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get gearRotationNoGear =>
      'Adicione equipamentos primeiro, depois você poderá agrupá-los em um rodízio.';

  @override
  String gearRotationSaveFailed(Object error) {
    return 'Não foi possível salvar o rodízio: $error';
  }

  @override
  String get gearRotationDone => 'Concluído';

  @override
  String get privacyZonesTitle => 'Zonas de privacidade';

  @override
  String get privacyZonesSaved => 'Zonas de privacidade salvas.';

  @override
  String privacyZonesSaveFailed(Object error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get privacyZonesSave => 'Salvar';

  @override
  String get privacyZonesLocateMe => 'Localizar-me';

  @override
  String get privacyZonesHint =>
      'Toque no mapa para adicionar uma zona. Trajetos em superfícies públicas têm o início e o fim cortados além do raio da zona.';

  @override
  String get privacyZonesSearchHint => 'Buscar lugares…';

  @override
  String get privacyZonesRadius => 'Raio';

  @override
  String privacyZonesRadiusMeters(int meters) {
    return '$meters m';
  }

  @override
  String privacyZonesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zonas — toque em um marcador para remover.',
      one: '$count zona — toque em um marcador para remover.',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'Limpar tudo';

  @override
  String get privacyZonesRemoveTitle => 'Remover zona de privacidade?';

  @override
  String get privacyZonesRemoveBody =>
      'Esta zona oculta seus trajetos por perto nos compartilhamentos públicos. Removê-la reexpõe esta área.';

  @override
  String get privacyZonesRemoveSemantics => 'Remover zona de privacidade';

  @override
  String get privacyZonesClearAllTitle =>
      'Limpar todas as zonas de privacidade?';

  @override
  String get privacyZonesClearAllBody =>
      'Isso remove todas as zonas, reexpondo todas essas áreas nos compartilhamentos públicos.';

  @override
  String get prefsTitle => 'Preferências';

  @override
  String get prefsUnitMetric => 'km, m';

  @override
  String get prefsUnitImperial => 'mi, ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · sincronizado com seus outros dispositivos';
  }

  @override
  String get prefsClear => 'Limpar';

  @override
  String get prefsCancel => 'Cancelar';

  @override
  String get prefsSave => 'Salvar';

  @override
  String get prefsSplitInterval => 'Intervalo de parciais';

  @override
  String get prefsSplitIntervalDefault => 'Padrão';

  @override
  String get prefsSplitIntervalDefaultSubtitle =>
      'Padrão (1 km ao correr, 5 km ao pedalar)';

  @override
  String get prefsLivePaceAlert => 'Alerta de ritmo ao vivo';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 's';

  @override
  String get prefsLivePaceAlertOff =>
      'Desativado — defina um ritmo para receber avisos falados durante uma corrida';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — aviso falado durante uma corrida quando o desvio for de 30 s ou mais';
  }

  @override
  String get prefsActivityRun => 'Corrida';

  @override
  String get prefsActivityWalk => 'Caminhada';

  @override
  String get prefsActivityHike => 'Trilha';

  @override
  String get prefsActivityCycle => 'Ciclismo';

  @override
  String get prefsPaceFormat => 'Formato de ritmo';

  @override
  String get prefsPaceFormatMinPerKm => 'Minutos por km';

  @override
  String get prefsPaceFormatMinPerMi => 'Minutos por milha';

  @override
  String get prefsPaceFormatKph => 'km/h';

  @override
  String get prefsPaceFormatMph => 'mph';

  @override
  String get prefsWeightUnit => 'Unidade de peso';

  @override
  String get prefsWeightUnitKg => 'Quilogramas (kg)';

  @override
  String get prefsWeightUnitLbs => 'Libras (lbs)';

  @override
  String get prefsNotSet => 'Não definido';

  @override
  String prefsHrZonesSummary(String zones) {
    return '$zones bpm';
  }

  @override
  String prefsWeeklyGoalSummary(String distance, String unit) {
    return '$distance $unit / semana';
  }

  @override
  String get prefsMapStyle => 'Estilo do mapa';

  @override
  String get prefsMapStyleStreets => 'Ruas';

  @override
  String get prefsMapStyleSatellite => 'Satélite';

  @override
  String get prefsMapStyleOutdoors => 'Ar livre';

  @override
  String get prefsMapStyleDark => 'Escuro';

  @override
  String get prefsDefaultRunVisibility => 'Visibilidade padrão das corridas';

  @override
  String get prefsCoachPersonality => 'Personalidade do treinador';

  @override
  String get prefsCoachSupportive => 'Apoiador';

  @override
  String get prefsCoachDrillSergeant => 'Sargento durão';

  @override
  String get prefsCoachAnalytical => 'Analítico';

  @override
  String get prefsSectionNotifications => 'Notificações';

  @override
  String get prefsEmailNotifications => 'Notificações por e-mail';

  @override
  String get prefsEmailNotifAll => 'Todas';

  @override
  String get prefsEmailNotifImportant => 'Apenas importantes';

  @override
  String get prefsEmailNotifOff => 'Desativadas';

  @override
  String get prefsPushNotifications => 'Notificações push';

  @override
  String get prefsPushNotifAll => 'Todas';

  @override
  String get prefsPushNotifImportant => 'Apenas importantes';

  @override
  String get prefsPushNotifOff => 'Desativadas';

  @override
  String get prefsEmailWeeklyDigest => 'E-mail de resumo semanal';

  @override
  String get prefsEmailWeeklyDigestHint =>
      'Inscreva-se para receber um resumo semanal do seu treino e dos destaques da comunidade. Desativado por padrão; separado dos seus e-mails de notificação.';

  @override
  String get prefsEmailLifecycleDrip => 'E-mail de dicas e incentivo';

  @override
  String get prefsEmailLifecycleDripHint =>
      'Inscreva-se para receber lembretes ocasionais de integração, reengajamento e sequência. Desativado por padrão; separado do seu resumo semanal e dos seus e-mails de notificação.';

  @override
  String get prefsWeekStart => 'A semana começa em';

  @override
  String get prefsWeekStartMonday => 'Segunda-feira';

  @override
  String get prefsWeekStartSunday => 'Domingo';

  @override
  String get prefsDefaultActivity => 'Atividade padrão';

  @override
  String get prefsDateOfBirth => 'Data de nascimento';

  @override
  String get prefsRestingHr => 'Frequência cardíaca em repouso';

  @override
  String get prefsMaxHr => 'Frequência cardíaca máxima';

  @override
  String get prefsMaxHrNotSet => 'Não definido — usa 208 − 0,7 × idade';

  @override
  String prefsHrBpm(int bpm) {
    return '$bpm bpm';
  }

  @override
  String get prefsSectionFueling => 'Reabastecimento de prova';

  @override
  String get prefsCarbsPerHour => 'Carboidratos por hora';

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
  String get prefsHrZones => 'Zonas de frequência cardíaca';

  @override
  String get prefsHrZonesDialogTitle =>
      'Zonas de frequência cardíaca (limites superiores, bpm)';

  @override
  String get prefsWeeklyGoal => 'Meta de quilometragem semanal';

  @override
  String get prefsSectionActivityRecording => 'Atividade e gravação';

  @override
  String get prefsSectionTrainingDemographics => 'Treino e dados demográficos';

  @override
  String get prefsSectionPrivacySharing => 'Privacidade e compartilhamento';

  @override
  String get prefsSectionAiCoach => 'Treinador de IA';

  @override
  String get prefsSignInToEdit =>
      'Entre para editar configurações de perfil que sincronizam entre dispositivos.';

  @override
  String get prefsUseMiles => 'Usar milhas';

  @override
  String get prefsDarkMode => 'Modo escuro';

  @override
  String get prefsAudioCues => 'Avisos de áudio';

  @override
  String get prefsAudioCuesSubtitle => 'Anúncios falados de parciais';

  @override
  String get prefsMinimalVoiceCues => 'Avisos de voz mínimos';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Pula os avisos tagarelas de meio de repetição e desvio de ritmo';

  @override
  String get prefsKeepScreenOn => 'Manter a tela ligada';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Mantém um wakelock durante uma corrida';

  @override
  String get prefsAdvancedGps => 'GPS avançado';

  @override
  String get prefsAdvancedGpsSubtitle =>
      'Mais precisão, trajeto mais detalhado, mais consumo de bateria';

  @override
  String get prefsShowRawTrack => 'Mostrar trajeto GPS bruto';

  @override
  String get prefsShowRawTrackSubtitle =>
      'Desenha a linha gravada sem ajuste no mapa da corrida, mesmo quando existe um trajeto corrigido';

  @override
  String get prefsDefaultRunPrivacy => 'Privacidade padrão das corridas';

  @override
  String get prefsStravaAutoShare => 'Compartilhamento automático no Strava';

  @override
  String get prefsStravaAutoShareSubtitle =>
      'Envia automaticamente cada nova corrida para o Strava. Requer uma integração do Strava conectada quando estiver disponível.';

  @override
  String get prefsDiscoverable => 'Aparecer na busca por nome';

  @override
  String get prefsDiscoverableSubtitle =>
      'Quando desativado, sua conta não aparece quando outros corredores buscam pelo nome de exibição. Suas corridas públicas e seu perfil continuam acessíveis para qualquer pessoa com o URL.';

  @override
  String get dashboardCoachTooltip => 'Treinador';

  @override
  String get dashboardFeedTooltip => 'Feed de atividades';

  @override
  String get dashboardRecapTooltip => 'Ano em corrida';

  @override
  String get dashboardProfileTooltip => 'Meu perfil';

  @override
  String get dashboardWelcomeTitle => 'Bem-vindo!';

  @override
  String get dashboardWelcomeBody =>
      'Seu painel é preenchido assim que você registra uma corrida, define uma meta ou importa seu histórico.';

  @override
  String get dashboardSetGoal => 'Definir meta';

  @override
  String get dashboardImportRuns => 'Importar corridas';

  @override
  String get dashboardPeriodWeek => 'Semana';

  @override
  String get dashboardPeriodMonth => 'Mês';

  @override
  String get dashboardPeriodAllTime => 'Total';

  @override
  String get dashboardSectionStreak => 'Sequência';

  @override
  String get dashboardWeekStripTitle => 'Esta semana';

  @override
  String dashboardWeekStripCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count atividades',
      one: '$count atividade',
    );
    return '$_temp0';
  }

  @override
  String dashboardWeekStripDayAria(String dow, String dist) {
    return '$dow: $dist';
  }

  @override
  String dashboardWeekStripDayRestAria(String dow) {
    return '$dow: dia de descanso';
  }

  @override
  String get dashboardSectionLast20Weeks => 'Últimas 20 semanas';

  @override
  String get dashboardSectionRecentLifts => 'Sessões recentes';

  @override
  String get dashboardViewAllGym => 'Ver tudo';

  @override
  String get dashboardSectionPersonalBests => 'Recordes pessoais';

  @override
  String get dashboardLongestRun => 'Corrida mais longa';

  @override
  String dashboardFastestDistance(String distance) {
    return 'Mais rápido em $distance';
  }

  @override
  String get dashboardGoals => 'Metas';

  @override
  String get dashboardAdd => 'Adicionar';

  @override
  String get dashboardGoalWeekly => 'SEMANAL';

  @override
  String get dashboardGoalMonthly => 'MENSAL';

  @override
  String dashboardGoalTitleFallback(String period) {
    return 'META $period';
  }

  @override
  String get dashboardSetWeeklyGoalA11y =>
      'Definir uma meta semanal de corrida';

  @override
  String get dashboardSetFirstGoal => 'Defina sua primeira meta';

  @override
  String get dashboardSetFirstGoalBody =>
      'Acompanhe distância, tempo, ritmo ou número de corridas por semana ou mês.';

  @override
  String get dashboardGoalTapToEdit => 'toque para editar';

  @override
  String get dashboardGoalComplete => 'Concluída.';

  @override
  String get dashboardGoalInProgress => 'Em andamento.';

  @override
  String dashboardGoalA11y(String period, String title, String status) {
    return 'Meta $period — $title $status';
  }

  @override
  String dashboardRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String dashboardVert(String value) {
    return '$value de elevação';
  }

  @override
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  ) {
    return 'Resumo de $label, $distance em $runs$elevation';
  }

  @override
  String dashboardElevationGainSuffix(String value) {
    return ', $value de ganho de elevação';
  }

  @override
  String get dashboardStreakCurrent => 'Atual';

  @override
  String get dashboardStreakHistory => 'Histórico';

  @override
  String get dashboardStreakDayUnit => 'dia';

  @override
  String get dashboardStreakDaysUnit => 'dias';

  @override
  String dashboardStreakBest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dias',
      one: '$count dia',
    );
    return 'melhor $_temp0';
  }

  @override
  String get dashboardStreakAllTimeBest => 'recorde de todos os tempos';

  @override
  String get dashboardStreakRestart => 'corra hoje para reiniciá-la';

  @override
  String get dashboardStreakStart => 'corra hoje para começar uma';

  @override
  String get dashboardHeatmapLess => 'Menos';

  @override
  String get dashboardHeatmapMore => 'Mais';

  @override
  String get dashboardHeatmapTapHint => 'Toque em uma semana para ver o resumo';

  @override
  String get periodWeeklySummary => 'Resumo semanal';

  @override
  String get periodMonthlySummary => 'Resumo mensal';

  @override
  String get periodAllTimeSummary => 'Resumo geral';

  @override
  String get periodShareTooltip => 'Compartilhar';

  @override
  String get periodPreviousTooltip => 'Anterior';

  @override
  String get periodNextTooltip => 'Próximo';

  @override
  String get periodSwitchToWeekly => 'Toque para mudar para semanal';

  @override
  String get periodSwitchToMonthly => 'Toque para mudar para mensal';

  @override
  String get periodSwitchToAllTime => 'Toque para mudar para total';

  @override
  String get periodStatDistance => 'Distância';

  @override
  String get periodStatRuns => 'Corridas';

  @override
  String get periodStatTime => 'Tempo';

  @override
  String get periodStatAvgPace => 'Ritmo médio';

  @override
  String get periodEmptyWeek => 'Nenhuma corrida esta semana';

  @override
  String get periodEmptyMonth => 'Nenhuma corrida este mês';

  @override
  String get periodShareSummary => 'Compartilhar resumo';

  @override
  String get periodShareText => 'Texto';

  @override
  String get periodShareImage => 'Imagem';

  @override
  String get periodShareImageFailed =>
      'Não foi possível criar a imagem de compartilhamento';

  @override
  String get periodShareCardTagline => 'CORREDOR MELHOR';

  @override
  String get periodShareStatDistance => 'DISTÂNCIA';

  @override
  String get periodShareStatRuns => 'CORRIDAS';

  @override
  String get periodShareStatTime => 'TEMPO';

  @override
  String get periodShareStatAvgPace => 'RITMO MÉDIO';

  @override
  String get trainingLoadTitle => 'Forma, Fadiga e Frescor';

  @override
  String trainingLoadSubtitleHr(int days) {
    return 'TRIMP de frequência cardíaca dos últimos $days dias.';
  }

  @override
  String get trainingLoadSubtitleVolume =>
      'Baseado em volume — defina FC de repouso e máxima nas preferências e registre com uma cinta para mudar para TRIMP.';

  @override
  String get trainingLoadEmpty =>
      'Registre algumas corridas para ver sua tendência de forma.';

  @override
  String get trainingLoadLegendFitness => 'Forma';

  @override
  String get trainingLoadLegendFatigue => 'Fadiga';

  @override
  String get trainingLoadLegendForm => 'Frescor';

  @override
  String trainingLoadLegendEntry(String label, int value) {
    return '$label · $value';
  }

  @override
  String get trainingLoadReadingLoaded =>
      'Carregado — siga em frente e recupere quando estiver pronto.';

  @override
  String get trainingLoadReadingTapered =>
      'Em afunilamento — uma sessão difícil não vai te quebrar.';

  @override
  String get trainingLoadReadingBalanced =>
      'Equilibrado — dia leve ou dia difícil, você decide.';

  @override
  String get trainingLoadIncludesLifts =>
      'Inclui sessões de academia — musculação também soma fadiga.';

  @override
  String get intensityTitle => 'INTENSIDADE DE TREINO';

  @override
  String intensityWindow(int days) {
    return 'últimos $days dias';
  }

  @override
  String intensityBasedOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas com FC',
      one: '$count corrida com FC',
    );
    return 'Com base em $_temp0';
  }

  @override
  String get mileageTitle => 'QUILOMETRAGEM';

  @override
  String get mileageWeek => 'Semana';

  @override
  String get mileageMonth => 'Mês';

  @override
  String get mileageYear => 'Ano';

  @override
  String get mileageThisWeek => 'esta semana';

  @override
  String get mileageThisMonth => 'este mês';

  @override
  String get mileageThisYear => 'este ano';

  @override
  String get fitnessTitle => 'Forma';

  @override
  String get fitnessStatVo2Max => 'VO₂ máx';

  @override
  String get fitnessStatVo2MaxTooltip =>
      'Seu motor aeróbico: quanto oxigênio seu corpo consegue usar por minuto. Quanto maior, melhor a forma.';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'A pontuação de forma de Daniels com base no seu melhor esforço recente. Define seus ritmos de treino.';

  @override
  String get fitnessStatRuns => 'Corridas';

  @override
  String get fitnessStatRunsTooltip =>
      'Corridas recentes longas o suficiente para contar na sua estimativa de forma.';

  @override
  String get fitnessStatCtl => 'Forma (CTL)';

  @override
  String get fitnessStatCtlTooltip =>
      'Sua carga de treino móvel de 42 dias. Cresce devagar; é sua base de resistência.';

  @override
  String get fitnessStatAtl => 'Fadiga (ATL)';

  @override
  String get fitnessStatAtlTooltip =>
      'Sua carga dos últimos 7 dias. Sobe rápido após sessões difíceis e cai com o descanso.';

  @override
  String get fitnessStatTsb => 'Frescor (TSB)';

  @override
  String get fitnessStatTsbTooltip =>
      'Forma menos fadiga. Positivo = descansado e pronto para competir; negativo = com fadiga acumulada.';

  @override
  String get runSocialActivity => 'Atividade';

  @override
  String get runSocialNoComments => 'Ainda não há comentários.';

  @override
  String get runSocialReplyHint => 'Escreva uma resposta…';

  @override
  String get runSocialCommentHint => 'Adicione um comentário…';

  @override
  String get runSocialRunnerFallback => 'Corredor';

  @override
  String get runSocialReply => 'Responder';

  @override
  String get runSocialDelete => 'Excluir';

  @override
  String get runSocialDeleteCommentTitle => 'Excluir este comentário?';

  @override
  String get runSocialDeleteCommentMessage =>
      'Este comentário será removido permanentemente. Não é possível desfazer.';

  @override
  String get runSocialPost => 'Publicar';

  @override
  String get runSocialCancel => 'Cancelar';

  @override
  String runSocialKudosError(String error) {
    return 'Não foi possível atualizar os kudos: $error';
  }

  @override
  String runSocialPostError(String error) {
    return 'Falha ao publicar: $error';
  }

  @override
  String runSocialDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get runPhotosLoading => 'Carregando fotos…';

  @override
  String get runPhotosTitle => 'Fotos';

  @override
  String get runPhotosAdd => 'Adicionar foto';

  @override
  String get runPhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get runPhotosCaptionHint => 'Legenda…';

  @override
  String get runPhotosCancel => 'Cancelar';

  @override
  String get runPhotosSave => 'Salvar';

  @override
  String get runPhotosUpload => 'Enviar';

  @override
  String get runPhotosUploading => 'Enviando…';

  @override
  String get runPhotosEditCaption => 'Editar legenda';

  @override
  String get runPhotosDeleteTooltip => 'Excluir foto';

  @override
  String get runPhotosDeleteTitle => 'Excluir foto?';

  @override
  String get runPhotosDeleteBody =>
      'Isto remove a foto da corrida permanentemente.';

  @override
  String get runPhotosDeleteConfirm => 'Excluir';

  @override
  String runPhotosPickerError(String error) {
    return 'Não foi possível abrir o seletor: $error';
  }

  @override
  String runPhotosUploadError(String error) {
    return 'Falha no envio: $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get routePhotosLoading => 'Carregando fotos…';

  @override
  String get routePhotosTitle => 'Fotos';

  @override
  String get routePhotosAdd => 'Adicionar foto';

  @override
  String get routePhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get routePhotosCaptionHint => 'Legenda…';

  @override
  String get routePhotosCancel => 'Cancelar';

  @override
  String get routePhotosSave => 'Salvar';

  @override
  String get routePhotosUpload => 'Enviar';

  @override
  String get routePhotosUploading => 'Enviando…';

  @override
  String get routePhotosEditCaption => 'Editar legenda';

  @override
  String get routePhotosDeleteTooltip => 'Excluir foto';

  @override
  String get routePhotosDeleteTitle => 'Excluir foto?';

  @override
  String get routePhotosDeleteBody =>
      'Isto remove a foto do percurso permanentemente.';

  @override
  String get routePhotosDeleteConfirm => 'Excluir';

  @override
  String routePhotosPickerError(String error) {
    return 'Não foi possível abrir o seletor: $error';
  }

  @override
  String routePhotosUploadError(String error) {
    return 'Falha no envio: $error';
  }

  @override
  String routePhotosDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get clubPhotosLoading => 'Carregando fotos…';

  @override
  String get clubPhotosTitle => 'Fotos';

  @override
  String get clubPhotosAdd => 'Adicionar foto';

  @override
  String get clubPhotosEmpty => 'Ainda não há fotos neste clube.';

  @override
  String get clubPhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get clubPhotosCaptionHint => 'Legenda…';

  @override
  String get clubPhotosCancel => 'Cancelar';

  @override
  String get clubPhotosSave => 'Salvar';

  @override
  String get clubPhotosUpload => 'Enviar';

  @override
  String get clubPhotosUploading => 'Enviando…';

  @override
  String get clubPhotosEditCaption => 'Editar legenda';

  @override
  String get clubPhotosDeleteTooltip => 'Excluir foto';

  @override
  String get clubPhotosDeleteTitle => 'Excluir foto?';

  @override
  String get clubPhotosDeleteBody =>
      'Isto remove a foto do clube permanentemente.';

  @override
  String get clubPhotosDeleteConfirm => 'Excluir';

  @override
  String clubPhotosPickerError(String error) {
    return 'Não foi possível abrir o seletor: $error';
  }

  @override
  String clubPhotosUploadError(String error) {
    return 'Falha no envio: $error';
  }

  @override
  String clubPhotosDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String clubPhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get runSegEffortsChecking => 'Verificando segmentos…';

  @override
  String get runSegEffortsNoRoute =>
      'Os segmentos são associados por rota — vincule esta corrida a uma rota salva para competir nos rankings dela.';

  @override
  String get runSegEffortsEmpty => 'Nenhum esforço de segmento nesta corrida.';

  @override
  String get workoutReviewTitle => 'Treino';

  @override
  String get workoutReviewColStep => 'Etapa';

  @override
  String get workoutReviewColPlan => 'Plano';

  @override
  String get workoutReviewColActual => 'Real';

  @override
  String get workoutReviewColPace => 'Ritmo';

  @override
  String get workoutReviewColDelta => 'Δ';

  @override
  String get workoutReviewSkip => 'pular';

  @override
  String get workoutReviewLabelWarmup => 'Aquecimento';

  @override
  String get workoutReviewLabelCooldown => 'Desaquecimento';

  @override
  String get workoutReviewLabelSteady => 'Constante';

  @override
  String get workoutReviewLabelRep => 'Rep.';

  @override
  String workoutReviewLabelRepN(int index, int total) {
    return 'Rep. $index/$total';
  }

  @override
  String get workoutReviewLabelRecovery => 'Recuperação';

  @override
  String workoutReviewLabelRecoveryN(int index, int total) {
    return 'Recuperação $index/$total';
  }

  @override
  String get workoutReviewLabelWalk => 'Caminhada';

  @override
  String workoutReviewLabelWalkN(int index, int total) {
    return 'Caminhada $index/$total';
  }

  @override
  String get segmentsPanelTitle => 'Segmentos';

  @override
  String get segmentsPanelNew => 'Novo segmento';

  @override
  String get segmentsPanelCancel => 'Cancelar';

  @override
  String get segmentsPanelLoading => 'Carregando segmentos…';

  @override
  String get segmentsPanelEmpty => 'Ainda não há segmentos nesta rota.';

  @override
  String get segmentsPanelNameLabel => 'Nome';

  @override
  String get segmentsPanelNameHint => 'Subida do terror';

  @override
  String get segmentsPanelStartLabel => 'Início (m)';

  @override
  String get segmentsPanelEndLabel => 'Fim (m)';

  @override
  String segmentsPanelRouteHint(int metres) {
    return 'a rota tem $metres m';
  }

  @override
  String get segmentsPanelCreate => 'Criar';

  @override
  String get segmentsPanelDeleteTooltip => 'Excluir segmento';

  @override
  String get segmentsPanelDeleteTitle => 'Excluir segmento?';

  @override
  String segmentsPanelDeleteBody(String name) {
    return '“$name” será removido.';
  }

  @override
  String get segmentsPanelDeleteConfirm => 'Excluir';

  @override
  String get segmentsPanelErrEndAfterStart =>
      'O fim deve ser maior que o início';

  @override
  String get segmentsPanelErrMinLength =>
      'O segmento deve ter pelo menos 100 m';

  @override
  String segmentsPanelCreateError(String error) {
    return 'Não foi possível criar o segmento: $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get segmentsPanelAllGenders => 'Todos os gêneros';

  @override
  String get segmentsPanelGenderMen => 'Homens';

  @override
  String get segmentsPanelGenderWomen => 'Mulheres';

  @override
  String get segmentsPanelGenderNonbinary => 'Não binário';

  @override
  String get segmentsPanelAllAges => 'Todas as idades';

  @override
  String get segmentsPanelResetFilters => 'Redefinir';

  @override
  String get segmentsPanelLeaderboardLoading => 'Carregando…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'Nenhum esforço corresponde a este filtro — tente ampliá-lo.';

  @override
  String get segmentsPanelLeaderboardEmpty =>
      'Ainda não há esforços — seja o primeiro a correr este segmento.';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'Você detém esta coroa — $label.';
  }

  @override
  String get segmentsPanelRunnerFallback => 'Corredor';

  @override
  String get goalEditorTitleNew => 'Nova meta';

  @override
  String get goalEditorTitleEdit => 'Editar meta';

  @override
  String get goalEditorNameLabel => 'Nome (opcional)';

  @override
  String get goalEditorNameHint => 'ex. Base de quilômetros';

  @override
  String get goalEditorPeriod => 'Período';

  @override
  String get goalEditorThisWeek => 'Esta semana';

  @override
  String get goalEditorThisMonth => 'Este mês';

  @override
  String get goalEditorTargets => 'Metas';

  @override
  String get goalEditorTargetsHelp =>
      'Defina qualquer combinação. Campos em branco são ignorados.';

  @override
  String get goalEditorTargetDistance => 'Distância';

  @override
  String get goalEditorTargetTime => 'Tempo';

  @override
  String get goalEditorTargetPace => 'Ritmo médio';

  @override
  String get goalEditorTargetRuns => 'Corridas';

  @override
  String get goalEditorSuffixMin => 'min';

  @override
  String get goalEditorSuffixRuns => 'corridas';

  @override
  String get goalEditorDelete => 'Excluir';

  @override
  String get goalEditorDeleteTitle => 'Excluir esta meta?';

  @override
  String get goalEditorDeleteMessage =>
      'Esta meta e o acompanhamento de progresso serão removidos. Você pode criar uma nova quando quiser.';

  @override
  String get goalEditorCancel => 'Cancelar';

  @override
  String get goalEditorSave => 'Salvar';

  @override
  String goalEditorSaveFailed(String error) {
    return 'Não foi possível salvar a meta: $error';
  }

  @override
  String get goalEditorErrDistance => 'Distância: insira um número positivo';

  @override
  String get goalEditorErrTime => 'Tempo: insira um número positivo de minutos';

  @override
  String get goalEditorErrPace => 'Ritmo: use mm:ss (ex. 5:00)';

  @override
  String get goalEditorErrRuns => 'Corridas: insira um número inteiro positivo';

  @override
  String get goalEditorErrNoTarget => 'Defina pelo menos uma meta';

  @override
  String get goalEditorSavedAnnounce => 'Meta salva';

  @override
  String get goalEditorDeletedAnnounce => 'Meta excluída';

  @override
  String get eventFormTitle => 'Novo evento';

  @override
  String get eventFormTitleLabel => 'Título';

  @override
  String get eventFormStartsAt => 'Começa em';

  @override
  String get eventFormDescriptionLabel => 'Descrição (opcional)';

  @override
  String get eventFormMeetLabel => 'Ponto de encontro (opcional)';

  @override
  String get eventFormMeetHint => 'Estacionamento do início da trilha';

  @override
  String get eventFormDistanceLabel => 'Distância (km)';

  @override
  String get eventFormDurationLabel => 'Duração (min)';

  @override
  String get eventFormRecurrence => 'Recorrência';

  @override
  String get eventFormRecurOneOff => 'Único';

  @override
  String get eventFormRecurWeekly => 'Semanal';

  @override
  String get eventFormRecurBiweekly => 'Quinzenal';

  @override
  String get eventFormRecurMonthly => 'Mensal';

  @override
  String get eventFormCancel => 'Cancelar';

  @override
  String get eventFormCreate => 'Criar evento';

  @override
  String get eventEditorCategory => 'Tipo de evento';

  @override
  String get eventEditorCatRun => 'Corrida em grupo';

  @override
  String get eventEditorCatCycle => 'Ciclismo';

  @override
  String get eventEditorCatClass => 'Aula';

  @override
  String get eventEditorCatSocial => 'Social';

  @override
  String get eventEditorCategoryHint =>
      'Escolha o tipo de evento — uma aula ou encontro social ignora rota, distância, ritmo e resultados de corrida.';

  @override
  String get eventEditorMembersOnlyToggle => 'Somente para membros';

  @override
  String get eventEditorMembersOnlyHint =>
      'Apenas membros do clube podem ver este evento, e ele não aparecerá na busca pública.';

  @override
  String get eventEditorDiscipline => 'Modalidade';

  @override
  String get eventEditorDisciplinePlaceholder =>
      'ex.: ioga Vinyasa, Pilates, mobilidade';

  @override
  String get clubFormTitle => 'Novo clube';

  @override
  String get clubFormNameLabel => 'Nome';

  @override
  String get clubFormDescriptionLabel => 'Descrição (opcional)';

  @override
  String get clubFormLocationLabel => 'Localização (opcional)';

  @override
  String get clubFormLocationHint => 'Edimburgo, Reino Unido';

  @override
  String get clubFormPublic => 'Público';

  @override
  String get clubFormPrivate => 'Privado';

  @override
  String get clubFormJoinPolicy => 'Política de adesão';

  @override
  String get clubFormJoinOpen => 'Aberto — qualquer um entra';

  @override
  String get clubFormJoinRequest => 'Solicitação — admins aprovam';

  @override
  String get clubFormJoinInvite => 'Apenas por convite';

  @override
  String get clubFormCancel => 'Cancelar';

  @override
  String get clubFormCreate => 'Criar';

  @override
  String get clubFormErrSlug =>
      'O nome precisa de pelo menos uma letra ou dígito.';

  @override
  String get clubFormErrUnreachable =>
      'Não é possível acessar o servidor agora. Verifique sua conexão ou entre na conta e tente novamente.';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonHarassment => 'Assédio ou abuso';

  @override
  String get reportReasonInappropriate => 'Conteúdo impróprio';

  @override
  String get reportReasonImpersonation => 'Falsidade ideológica';

  @override
  String get reportReasonOther => 'Outro';

  @override
  String get reportSuccess =>
      'Denúncia enviada — obrigado por sinalizar isto para revisão.';

  @override
  String get reportTitleUser => 'Denunciar usuário';

  @override
  String get reportTitleClub => 'Denunciar clube';

  @override
  String get reportTitleRoute => 'Denunciar rota';

  @override
  String get reportTitlePost => 'Denunciar publicação';

  @override
  String get reportTitleRun => 'Denunciar corrida';

  @override
  String get reportTitleContent => 'Denunciar conteúdo';

  @override
  String get reportDisclaimer =>
      'Sua denúncia vai para um moderador. Denúncias falsas também são analisadas — sinalize apenas conteúdo que viole nossas diretrizes da comunidade.';

  @override
  String get reportReason => 'Motivo';

  @override
  String get reportNotesLabel => 'Notas (opcional)';

  @override
  String get reportCancel => 'Cancelar';

  @override
  String get reportSubmit => 'Enviar denúncia';

  @override
  String get reportErrDuplicate =>
      'Você já tem uma denúncia pendente sobre este conteúdo.';

  @override
  String gearBackfillTitle(String gear) {
    return 'Vincular corridas anteriores a $gear?';
  }

  @override
  String gearBackfillBody(int count, String activity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count atividades de $activity',
      one: '$count atividade de $activity',
    );
    return 'Encontramos $_temp0 após a compra. Desmarque aquelas em que você não os usou.';
  }

  @override
  String get gearBackfillActivityCycling => 'ciclismo';

  @override
  String get gearBackfillActivityRunning => 'corrida';

  @override
  String get gearBackfillSelectNone => 'Desmarcar todas';

  @override
  String get gearBackfillSelectAll => 'Selecionar todas';

  @override
  String gearBackfillSelectedCount(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get gearBackfillSkip => 'Pular';

  @override
  String get gearBackfillAttaching => 'Vinculando…';

  @override
  String gearBackfillAttach(int count) {
    return 'Vincular $count';
  }

  @override
  String gearBackfillAttachError(String error) {
    return 'Falha ao vincular: $error';
  }

  @override
  String get workoutEditTitle => 'Editar treino';

  @override
  String get workoutEditKindLabel => 'Tipo';

  @override
  String get workoutEditDistanceLabel => 'Distância alvo (km)';

  @override
  String get workoutEditDistanceHint => 'ex. 8.0';

  @override
  String get workoutEditPaceLabel => 'Ritmo alvo (mm:ss /km)';

  @override
  String get workoutEditPaceHint => 'ex. 5:30';

  @override
  String get workoutEditNotesLabel => 'Notas';

  @override
  String get workoutEditCancel => 'Cancelar';

  @override
  String get workoutEditSave => 'Salvar';

  @override
  String get workoutEditErrDistance => 'Insira uma distância positiva em km';

  @override
  String get workoutEditErrPace => 'O ritmo deve ter o formato 5:30';

  @override
  String workoutEditSaveError(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return 'CONFIRMADO · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'Começando agora';

  @override
  String upcomingEventInMinutes(int count) {
    return 'Em $count min';
  }

  @override
  String get upcomingEventInOneHour => 'Em 1 hora';

  @override
  String upcomingEventInHours(int count) {
    return 'Em $count horas';
  }

  @override
  String get upcomingEventTomorrow => 'Amanhã';

  @override
  String upcomingEventInDays(int count) {
    return 'Em $count dias';
  }

  @override
  String get todaysWorkoutDone => 'FEITO HOJE';

  @override
  String get todaysWorkoutToday => 'TREINO DE HOJE';

  @override
  String get errorStateRetry => 'Tentar novamente';

  @override
  String get shareCardRunTitle => 'Compartilhar corrida';

  @override
  String get shareCardExport => 'Exportar';

  @override
  String get shareCardImage => 'Imagem';

  @override
  String get shareCardStatDistance => 'Distância';

  @override
  String get shareCardStatTime => 'Tempo';

  @override
  String get shareCardStatPace => 'Ritmo';

  @override
  String get shareCardStatSpeed => 'Velocidade';

  @override
  String get shareCardBrandRun => 'RUN';

  @override
  String get shareCardImageError =>
      'Não foi possível criar a imagem de compartilhamento';

  @override
  String get shareCardFileError => 'Não foi possível exportar o arquivo';

  @override
  String get shareCardRouteTitle => 'Compartilhar rota';

  @override
  String get shareCardRouteShareImage => 'Compartilhar imagem';

  @override
  String get shareCardRouteCapturing => 'Capturando…';

  @override
  String get shareCardRouteStatDistance => 'Distância';

  @override
  String get shareCardRouteStatClimb => 'Subida';

  @override
  String get billingToday => 'hoje';

  @override
  String get billingYesterday => 'ontem';

  @override
  String billingDaysAgo(int count) {
    return 'há $count dias';
  }

  @override
  String billingRenewalFailed(String relative) {
    return 'A renovação Pro falhou $relative.';
  }

  @override
  String get billingRenewalBody =>
      'Atualize seu cartão ou você será rebaixado para o Free.';

  @override
  String get billingManage => 'Gerenciar';

  @override
  String get planCalendarPrevMonth => 'Mês anterior';

  @override
  String get planCalendarNextMonth => 'Próximo mês';

  @override
  String runGearChipsLoadError(String error) {
    return 'Falha ao carregar equipamento: $error';
  }

  @override
  String get runGearChipsPickerTitle =>
      'Marcar o equipamento usado nesta corrida';

  @override
  String get runGearChipsEmpty =>
      'Você ainda não registrou nenhum equipamento. Adicione em Configurações → Equipamento.';

  @override
  String get runGearChipsCancel => 'Cancelar';

  @override
  String get runGearChipsSave => 'Salvar';

  @override
  String get runGearChipsTag => '+ Marcar equipamento';

  @override
  String get runGearChipsEdit => 'Editar';

  @override
  String runGearChipsSaveError(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get gearFormTitleEdit => 'Editar equipamento';

  @override
  String get gearFormTitleAddShoes => 'Adicionar tênis';

  @override
  String get gearFormTitleAddBike => 'Adicionar bicicleta';

  @override
  String get gearFormNameLabel => 'Nome';

  @override
  String get gearFormNameHint => 'Pegasus 39';

  @override
  String get gearFormBrandLabel => 'Marca';

  @override
  String get gearFormModelLabel => 'Modelo';

  @override
  String get gearFormBoughtLabel => 'Comprado';

  @override
  String get gearFormBoughtPick => 'Toque para escolher';

  @override
  String gearFormRetireAt(String unit) {
    return 'Aposentar em ($unit)';
  }

  @override
  String get gearFormRetireHint => '500';

  @override
  String get gearFormNotesLabel => 'Notas';

  @override
  String get gearFormCancel => 'Cancelar';

  @override
  String get gearFormSaving => 'Salvando…';

  @override
  String get gearFormSave => 'Salvar';

  @override
  String get gearFormAdd => 'Adicionar';

  @override
  String gearFormSaveError(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get gearWearLogHeading => 'Registro de desgaste';

  @override
  String get gearWearLogHint =>
      'Anote como este equipamento está envelhecendo — desgaste do solado, entressola morta, cabedal puído.';

  @override
  String get gearWearLogEmpty => 'Nenhuma observação de desgaste ainda.';

  @override
  String get gearWearLogAddNote => 'Observação';

  @override
  String get gearWearLogNoteHint => 'ex.: cravos do solado gastos no calcanhar';

  @override
  String get gearWearLogArea => 'Área';

  @override
  String get gearWearLogAreaNone => '—';

  @override
  String get gearWearLogAreaOutsole => 'Solado';

  @override
  String get gearWearLogAreaMidsole => 'Entressola';

  @override
  String get gearWearLogAreaUpper => 'Cabedal';

  @override
  String get gearWearLogAreaOther => 'Outro';

  @override
  String get gearWearLogAdd => 'Adicionar observação';

  @override
  String get gearWearLogAdding => 'Adicionando…';

  @override
  String get gearWearLogDelete => 'Excluir observação';

  @override
  String gearWearLogAddError(String error) {
    return 'Não foi possível adicionar a observação: $error';
  }

  @override
  String gearWearLogDeleteError(String error) {
    return 'Não foi possível excluir a observação: $error';
  }

  @override
  String get notificationBellTooltip => 'Notificações';

  @override
  String get liveRunMapWaitingGps => 'Aguardando GPS...';

  @override
  String get liveRunMapRecentre => 'Recentralizar na minha localização';

  @override
  String get ttsRunStarted => 'Corrida iniciada';

  @override
  String ttsRunComplete(String distance, int mins) {
    return 'Corrida concluída. $distance em $mins minutos.';
  }

  @override
  String get ttsOffRoute => 'Fora da rota';

  @override
  String get ttsPaceAlertFast => 'Acelere o ritmo';

  @override
  String get ttsPaceAlertSlow => 'Diminua o ritmo';

  @override
  String get ttsWorkoutComplete => 'Treino concluído. Bom trabalho.';

  @override
  String get ttsStepHalfway => 'Metade desta repetição';

  @override
  String get ttsStepLastFifty => 'Faltam cinquenta metros';

  @override
  String ttsPaceDriftAhead(int delta) {
    return 'Alivie um pouco — $delta segundos rápido demais.';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return 'Acelere um pouco — $delta segundos lento demais.';
  }

  @override
  String ttsSpeedKm(String value) {
    return 'Velocidade, $value quilômetros por hora';
  }

  @override
  String ttsSpeedMi(String value) {
    return 'Velocidade, $value milhas por hora';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por quilômetro';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por milha';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$value quilômetros';
  }

  @override
  String ttsDistanceMetres(int value) {
    return '$value metros';
  }

  @override
  String ttsDistanceMileSingular(String value) {
    return '$value milha';
  }

  @override
  String ttsDistanceMiles(String value) {
    return '$value milhas';
  }

  @override
  String ttsDistanceYards(int value) {
    return '$value jardas';
  }

  @override
  String ttsSplit(String count, String unit, String tail) {
    return '$count $unit. $tail';
  }

  @override
  String get ttsStepWarmup => 'Aquecimento';

  @override
  String get ttsStepRecovery => 'Recuperação';

  @override
  String get ttsStepSteady => 'Ritmo constante';

  @override
  String get ttsStepCooldown => 'Desaquecimento';

  @override
  String get ttsStepRep => 'Repetição';

  @override
  String get ttsStepRun => 'Corrida';

  @override
  String get ttsStepWalk => 'Caminhada';

  @override
  String ttsStepRepOf(int index, int total) {
    return 'Repetição $index de $total';
  }

  @override
  String ttsStepRunOf(int index, int total) {
    return 'Corrida $index de $total';
  }

  @override
  String ttsStepWalkOf(int index, int total) {
    return 'Caminhada $index de $total';
  }

  @override
  String ttsStepPaceKm(int min, int sec) {
    return '$min minutos $sec segundos por quilômetro';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '$min minutos por quilômetro';
  }

  @override
  String ttsStepPaceMi(int min, int sec) {
    return '$min minutos $sec segundos por milha';
  }

  @override
  String ttsStepPaceMiWhole(int min) {
    return '$min minutos por milha';
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
  String get guidedEasy30Title => 'Corrida leve de 30 minutos';

  @override
  String get guidedEasy30Subtitle => 'Voz do treinador · 30 min · esforço leve';

  @override
  String get guidedEasy30Description =>
      'Uma corrida tranquila em ritmo de conversa, para um dia de recuperação ou só para clarear a cabeça. O treinador aparece a cada cinco minutos com um empurrãozinho gentil.';

  @override
  String get guidedEasy30Cue0 =>
      'Vamos lá. Comece leve — este é o seu ritmo de recuperação.';

  @override
  String get guidedEasy30Cue1 =>
      'Cinco minutos. Relaxe os ombros. Mantenha o ritmo de conversa.';

  @override
  String get guidedEasy30Cue2 =>
      'Dez minutos. Verifique a cadência — pés rápidos, pisada leve.';

  @override
  String get guidedEasy30Cue3 =>
      'Metade. Você ainda deve conseguir conversar enquanto corre.';

  @override
  String get guidedEasy30Cue4 =>
      'Vinte minutos. Observe a respiração — inspire devagar pelo nariz, expire pela boca.';

  @override
  String get guidedEasy30Cue5 =>
      'Faltam cinco minutos. Mantenha-se relaxado. Não acelere.';

  @override
  String get guidedEasy30Cue6 => 'Falta um minuto. Termine leve.';

  @override
  String get guidedEasy30Cue7 =>
      'Concluído. Caminhe um minuto para recuperar. Mandou bem.';

  @override
  String get guidedTempo25Title => 'Construtor de tempo de 25 minutos';

  @override
  String get guidedTempo25Subtitle => 'Voz do treinador · 25 min · 5-15-5';

  @override
  String get guidedTempo25Description =>
      'Cinco minutos de aquecimento leve, quinze minutos em tempo (confortavelmente forte), cinco minutos de desaquecimento. A clássica sessão de tempo semanal.';

  @override
  String get guidedTempo25Cue0 =>
      'Hora do aquecimento. Cinco minutos leves — acorde as pernas.';

  @override
  String get guidedTempo25Cue1 =>
      'Falta um minuto de aquecimento. Aumente a cadência.';

  @override
  String get guidedTempo25Cue2 =>
      'Suba para o tempo. Confortavelmente forte. Como um esforço de prova de 10K.';

  @override
  String get guidedTempo25Cue3 =>
      'Cinco minutos em tempo. Forte, mas controlado. Mantenha o ritmo.';

  @override
  String get guidedTempo25Cue4 =>
      'Dez minutos de tempo feitos. Segure o ritmo.';

  @override
  String get guidedTempo25Cue5 =>
      'Faltam dois minutos em tempo. Mantenha-se fluido.';

  @override
  String get guidedTempo25Cue6 =>
      'Alivie. Cinco minutos leves para desaquecer.';

  @override
  String get guidedTempo25Cue7 =>
      'Faltam dois minutos. Traga a frequência cardíaca de volta para baixo.';

  @override
  String get guidedTempo25Cue8 =>
      'Concluído. Caminhe e alongue. Ótimo trabalho.';

  @override
  String get guidedFirst15Title => 'Iniciante: 15 minutos corrida/caminhada';

  @override
  String get guidedFirst15Subtitle =>
      'Voz do treinador · 15 min · intervalos corrida/caminhada';

  @override
  String get guidedFirst15Description =>
      'Novo na corrida? Três séries de um minuto correndo e um minuto caminhando, mais aquecimento e desaquecimento. Uma entrada suave; todo mundo começa aqui.';

  @override
  String get guidedFirst15Cue0 =>
      'Comece com três minutos de caminhada acelerada para aquecer.';

  @override
  String get guidedFirst15Cue1 =>
      'Mude para um minuto de corrida leve. Ritmo de conversa.';

  @override
  String get guidedFirst15Cue2 => 'Caminhe um minuto.';

  @override
  String get guidedFirst15Cue3 => 'Corra um minuto.';

  @override
  String get guidedFirst15Cue4 => 'Caminhe um minuto.';

  @override
  String get guidedFirst15Cue5 => 'Corra um minuto.';

  @override
  String get guidedFirst15Cue6 => 'Caminhe um minuto.';

  @override
  String get guidedFirst15Cue7 => 'Corra um minuto — o último.';

  @override
  String get guidedFirst15Cue8 =>
      'Volte para a caminhada. Cinco minutos de desaquecimento.';

  @override
  String get guidedFirst15Cue9 => 'Falta um minuto. Caminhe leve.';

  @override
  String get guidedFirst15Cue10 =>
      'Concluído. Isso foi uma corrida de verdade. Volte a correr em breve.';

  @override
  String guidedRunMinutesBadge(int minutes) {
    return '$minutes min';
  }

  @override
  String guidedRunCueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count indicações na corrida',
      one: '$count indicação na corrida',
    );
    return '$_temp0';
  }

  @override
  String get guidedRunFullScript => 'O ROTEIRO COMPLETO';

  @override
  String get guidedRunPreviewCue => 'Ouvir indicação';

  @override
  String guidedRunPreviewError(String error) {
    return 'Não foi possível ouvir: $error';
  }

  @override
  String get ttsSplitUnitKilometre => 'quilômetro';

  @override
  String get ttsSplitUnitKilometres => 'quilômetros';

  @override
  String get ttsSplitUnitMile => 'milha';

  @override
  String get ttsSplitUnitMiles => 'milhas';

  @override
  String get workoutKindEasy => 'Leve';

  @override
  String get workoutKindLong => 'Longão';

  @override
  String get workoutKindRecovery => 'Recuperação';

  @override
  String get workoutKindTempo => 'Tempo';

  @override
  String get workoutKindInterval => 'Intervalado';

  @override
  String get workoutKindMarathonPace => 'Ritmo de maratona';

  @override
  String get workoutKindWalkRun => 'Caminhada-corrida';

  @override
  String get workoutKindRace => 'Prova';

  @override
  String get workoutKindRest => 'Descanso';

  @override
  String get planPhaseBase => 'Base';

  @override
  String get planPhaseBuild => 'Construção';

  @override
  String get planPhasePeak => 'Pico';

  @override
  String get planPhaseTaper => 'Polimento';

  @override
  String get planPhaseRace => 'Semana de prova';

  @override
  String get runBackgroundLocationNudgeTitle =>
      'Permitir localização o tempo todo';

  @override
  String get runBackgroundLocationNudgeBody =>
      'O Android só concedeu a localização enquanto o app está aberto. Para uma distância precisa com a tela desligada, defina o acesso à localização como \"Permitir o tempo todo\" nas Configurações. Você pode começar mesmo assim — a gravação continua funcionando enquanto o app estiver na tela.';

  @override
  String get runBatteryOptHintTitle =>
      'Manter a gravação ativa em segundo plano';

  @override
  String get runBatteryOptHintBody =>
      'Alguns celulares (Samsung, Xiaomi, OnePlus e outros) colocam os apps em suspensão para economizar bateria, o que pode interromper a gravação de uma corrida longa quando a tela está desligada. Por segurança, exclua este app da otimização de bateria nas Configurações. Sua corrida será gravada de qualquer forma — isso apenas impede que o sistema a interrompa.';

  @override
  String shareCardCaption(Object title, Object distance, Object duration) {
    return '$title — $distance em $duration';
  }

  @override
  String get settingsBackendNotConfigured => 'Backend não configurado';

  @override
  String get settingsAccountSignedIn => 'Conectado';

  @override
  String get settingsDevicesSignedOutSubtitle =>
      'Entre para gerenciar seus dispositivos';

  @override
  String get verifiedClubTooltip => 'Clube verificado oficial';

  @override
  String get raceDistance5k => '5 km';

  @override
  String get raceDistance10k => '10 km';

  @override
  String get raceDistanceHalfMarathon => 'Meia maratona';

  @override
  String get raceDistanceMarathon => 'Maratona';

  @override
  String get settingsTabAccountSubtitle => 'Entrar, backup, excluir conta';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Unidades, tema, gravação, treino, privacidade';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, cinta de frequência cardíaca';

  @override
  String get settingsTabDevicesSubtitle =>
      'Onde você está conectado e ajustes por dispositivo';

  @override
  String get settingsTabGearSubtitle =>
      'Acompanhe tênis + bikes e a quilometragem por item';

  @override
  String get settingsTabCoachingSubtitle =>
      'Treine atletas ou siga o seu próprio treinador';

  @override
  String get settingsTabProSubtitle =>
      'Assine, restaure compras, gerencie a cobrança';

  @override
  String get settingsTabLicensesSubtitle =>
      'Versão do app e avisos de código aberto';

  @override
  String periodSummaryWeekOf(Object date) {
    return 'Semana de $date';
  }

  @override
  String periodShareRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '1 corrida',
    );
    return '$_temp0';
  }

  @override
  String periodShareAvgPace(Object pace) {
    return 'Ritmo médio: $pace';
  }

  @override
  String get gymTitle => 'Academia';

  @override
  String get gymLog => 'Registrar treino';

  @override
  String get gymUntitled => 'Treino sem título';

  @override
  String get gymOfflineCached => 'Offline: mostrando treinos salvos';

  @override
  String get gymOfflineQueued =>
      'Offline: as alterações serão sincronizadas mais tarde';

  @override
  String get gymEmptyTitle => 'Nenhum treino de academia ainda';

  @override
  String get gymEmptyBody =>
      'Registre um treino para acompanhá-lo aqui e alimentar sua carga de treino.';

  @override
  String get gymPrBadge => 'RP';

  @override
  String gymExercisesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercícios',
      one: '$count exercício',
    );
    return '$_temp0';
  }

  @override
  String gymVolumeShort(int volume) {
    return '$volume kg';
  }

  @override
  String get gymNotFound => 'Treino não encontrado.';

  @override
  String get gymEdit => 'Editar';

  @override
  String get gymDelete => 'Excluir';

  @override
  String get gymPublic => 'Público';

  @override
  String get gymPrivate => 'Privado';

  @override
  String get gymMakePublic => 'Tornar público';

  @override
  String get gymMakePrivate => 'Tornar privado';

  @override
  String gymVisibilityFailed(Object error) {
    return 'Não foi possível atualizar a visibilidade: $error';
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
  String get gymDuration => 'Tempo (s)';

  @override
  String gymDurationValue(String seconds) {
    return '${seconds}s';
  }

  @override
  String gymSetN(int n) {
    return 'Série $n';
  }

  @override
  String get gymPrWeight => 'Mais pesada';

  @override
  String get gymPrVolume => 'Melhor volume';

  @override
  String get gymPrE1rm => 'Melhor 1RM est.';

  @override
  String get gymRecordsLink => 'Recordes';

  @override
  String get gymRecordsTitle => 'Recordes pessoais';

  @override
  String get gymRecordsSubtitle =>
      'A tua melhor marca em cada exercício com peso.';

  @override
  String get gymRecordsEmpty =>
      'Ainda não há exercícios com peso registados. Adiciona um peso a uma série para começar a acompanhar os teus recordes.';

  @override
  String gymRecordsLastDone(String date) {
    return 'Último $date';
  }

  @override
  String gymRecordsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessões',
      one: '1 sessão',
    );
    return '$_temp0';
  }

  @override
  String get gymExerciseBack => 'Voltar aos recordes';

  @override
  String get gymExerciseEmpty => 'Ainda não há histórico deste exercício.';

  @override
  String gymSinceFirstUp(String delta) {
    return '+$delta desde a primeira sessão';
  }

  @override
  String gymSinceFirstDown(String delta) {
    return '−$delta desde a primeira sessão';
  }

  @override
  String get gymSinceFirstFlat => 'sem alteração desde a primeira sessão';

  @override
  String gymDetailLastTime(String date) {
    return 'Última vez $date';
  }

  @override
  String get gymVolumeLabel => 'Volume';

  @override
  String get gymDeleteConfirmTitle => 'Excluir treino?';

  @override
  String get gymDeleteConfirmBody =>
      'Isso remove permanentemente o treino e suas séries.';

  @override
  String get clubEventMembersOnly => 'Somente membros';

  @override
  String get clubEventLogAsWorkout => 'Registrar como treino';

  @override
  String get clubEventLogAsWorkoutHint =>
      'Adicione esta aula ao seu próprio registro de academia — você pode ajustar os detalhes antes de salvar.';

  @override
  String get clubEventLogAsWorkoutSaved =>
      'Adicionado ao seu registro de academia';

  @override
  String get clubEventDownloadCertificate => 'Certificado de conclusão';

  @override
  String get clubEventCertificateShare => 'Guardar ou partilhar';

  @override
  String clubEventCertificateShareText(String event) {
    return 'Concluí $event!';
  }

  @override
  String get clubEventCertificateFailed =>
      'Não foi possível gerar o certificado. Tente novamente.';

  @override
  String get clubEventCertificateHeading => 'Certificado de Conclusão';

  @override
  String get clubEventCertificateCertifies => 'Isto certifica que';

  @override
  String get clubEventCertificateCompleted => 'concluiu';

  @override
  String get clubEventCertificateTime => 'Tempo';

  @override
  String get clubEventCertificateDistance => 'Distância';

  @override
  String clubEventCertificatePlace(String place) {
    return '$place lugar';
  }

  @override
  String get gymEditorNewTitle => 'Novo treino';

  @override
  String get gymEditorEditTitle => 'Editar treino';

  @override
  String get gymEditorTitleLabel => 'Título (opcional)';

  @override
  String get gymEditorTitlePlaceholder => 'ex.: Dia de push';

  @override
  String get gymEditorExercisePlaceholder => 'Nome do exercício';

  @override
  String get gymEditorRemoveExercise => 'Remover exercício';

  @override
  String get gymEditorRemoveSet => 'Remover série';

  @override
  String get gymEditorAddSet => 'Adicionar série';

  @override
  String get gymEditorAddExercise => 'Adicionar exercício';

  @override
  String get gymEditorShare => 'Compartilhar no feed';

  @override
  String get gymEditorCancel => 'Cancelar';

  @override
  String get gymEditorSave => 'Salvar treino';

  @override
  String get gymEditorNeedExercise =>
      'Adicione ao menos um exercício com nome.';

  @override
  String get gymCatalogueBrowse => 'Procurar catálogo';

  @override
  String get gymCatalogueTitle => 'Catálogo de exercícios';

  @override
  String get gymCatalogueSearchPlaceholder => 'Procurar exercícios';

  @override
  String get gymCatalogueCategoryLabel => 'Categoria';

  @override
  String get gymCatalogueEmpty => 'Nenhum exercício corresponde.';

  @override
  String get gymCatalogueCustomBadge => 'Personalizado';

  @override
  String gymCatalogueCreate(String name) {
    return 'Adicionar “$name” como exercício personalizado';
  }

  @override
  String get gymCatalogueCreateFailed =>
      'Não foi possível adicionar esse exercício.';

  @override
  String get gymCatalogueCategoryAll => 'Todos';

  @override
  String get gymCatalogueCategoryChest => 'Peito';

  @override
  String get gymCatalogueCategoryBack => 'Costas';

  @override
  String get gymCatalogueCategoryShoulders => 'Ombros';

  @override
  String get gymCatalogueCategoryLegs => 'Pernas';

  @override
  String get gymCatalogueCategoryArms => 'Braços';

  @override
  String get gymCatalogueCategoryCore => 'Core';

  @override
  String get gymCatalogueCategoryCardio => 'Cardio';

  @override
  String get gymCatalogueCategoryFullBody => 'Corpo inteiro';

  @override
  String get gymCatalogueCategoryOther => 'Outros';

  @override
  String get gymSaveFailed => 'Não foi possível salvar o treino.';

  @override
  String get gymRoutineLink => 'Rotinas';

  @override
  String get gymRoutineTitle => 'Rotinas';

  @override
  String get gymRoutineNew => 'Nova rotina';

  @override
  String get gymRoutineBack => 'Voltar para rotinas';

  @override
  String get gymRoutineNotFound => 'Rotina não encontrada.';

  @override
  String gymRoutineExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercícios',
      one: '$count exercício',
    );
    return '$_temp0';
  }

  @override
  String get gymRoutineStart => 'Iniciar rotina';

  @override
  String get gymRoutinePublishLabel => 'Publicar em um clube';

  @override
  String get gymRoutinePublishPick => 'Escolha um clube…';

  @override
  String get gymRoutinePublish => 'Publicar';

  @override
  String get gymRoutinePublishSuccess => 'Rotina publicada no clube.';

  @override
  String get gymRoutinePublishFailed => 'Não foi possível publicar a rotina.';

  @override
  String get gymRoutineClubTemplateBadge => 'Modelo do clube';

  @override
  String get gymRoutinePublicBadge => 'Na biblioteca pública';

  @override
  String get gymRoutinePublishPublicLabel => 'Biblioteca pública';

  @override
  String get gymRoutinePublishPublic => 'Publicar na biblioteca pública';

  @override
  String get gymRoutineUnpublishPublic => 'Remover da biblioteca pública';

  @override
  String get gymRoutinePublishPublicHint =>
      'Qualquer pessoa com sessão iniciada pode ver e adotar esta rotina. Os treinos registados continuam privados.';

  @override
  String get gymRoutinePublishPublicSuccess =>
      'Rotina publicada na biblioteca pública.';

  @override
  String get gymRoutineUnpublishPublicSuccess =>
      'Rotina removida da biblioteca pública.';

  @override
  String get gymRoutinePublishPublicFailed =>
      'Não foi possível alterar a visibilidade pública.';

  @override
  String get gymLibraryLink => 'Biblioteca';

  @override
  String get gymLibraryTitle => 'Biblioteca pública de rotinas';

  @override
  String get gymLibrarySearchHint => 'Procurar rotinas por nome';

  @override
  String get gymLibraryLoadError => 'Não foi possível carregar a biblioteca.';

  @override
  String get gymLibraryEmpty => 'Ainda não há rotinas publicadas.';

  @override
  String gymLibraryEmptySearch(String query) {
    return 'Nenhuma rotina corresponde a \"$query\".';
  }

  @override
  String gymLibraryByAuthor(String author) {
    return 'por $author';
  }

  @override
  String get gymLibraryAnonymous => 'um praticante';

  @override
  String get gymLibraryAdopt => 'Adotar nas minhas rotinas';

  @override
  String get gymLibraryAdopting => 'A adotar…';

  @override
  String get gymLibraryAdoptFailed => 'Não foi possível adotar a rotina.';

  @override
  String get gymRoutineDelete => 'Excluir';

  @override
  String get gymRoutineDeleteConfirmTitle => 'Excluir rotina?';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'Isso remove a rotina permanentemente. Os treinos registrados não são afetados.';

  @override
  String get gymRoutineDeleted => 'Rotina excluída';

  @override
  String get gymRoutineCreated => 'Rotina salva';

  @override
  String get gymRoutineSaveFailed => 'Não foi possível salvar a rotina.';

  @override
  String get gymRoutineEmptyTitle => 'Nenhuma rotina ainda';

  @override
  String get gymRoutineEmptyBody =>
      'Salve um treino registrado como rotina, ou crie uma, para reutilizá-la.';

  @override
  String get gymRoutineTargetReps => 'Repetições-alvo';

  @override
  String gymRoutineTargetWeight(String unit) {
    return 'Carga-alvo ($unit)';
  }

  @override
  String get gymRoutineEditorNewTitle => 'Nova rotina';

  @override
  String get gymRoutineEditorTitleLabel => 'Nome da rotina';

  @override
  String get gymRoutineEditorTitlePlaceholder => 'ex.: Dia de empurrar A';

  @override
  String get gymRoutineEditorNotesLabel => 'Notas (opcional)';

  @override
  String get gymRoutineEditorSave => 'Salvar rotina';

  @override
  String get gymRoutineEditorCancel => 'Cancelar';

  @override
  String get gymRoutineEditorNeedTitle => 'Dê um nome à rotina.';

  @override
  String get gymRoutineEditorNeedExercise =>
      'Adicione pelo menos um exercício com nome.';

  @override
  String get gymRoutineSaveAsRoutine => 'Salvar como rotina';

  @override
  String get gymRoutineRepeatLast => 'Repetir o último';

  @override
  String get gymRoutineTargetRepsMax => 'a';

  @override
  String get gymRoutineTargetDuration => 'Tempo alvo (s)';

  @override
  String get gymRoutineTargetDistance => 'Distância alvo (m)';

  @override
  String get gymRoutineRestLabel => 'Descanso (s)';

  @override
  String get gymRoutineSetType => 'Tipo de série';

  @override
  String get gymRoutineSetTypeWarmup => 'Aquecimento';

  @override
  String get gymRoutineSetTypeWorking => 'Série de trabalho';

  @override
  String get gymRoutineSetTypeDropset => 'Drop set';

  @override
  String get gymRoutineSetTypeAmrap => 'AMRAP';

  @override
  String get gymRoutineSetTypeFailure => 'Até a falha';

  @override
  String get gymRoutineSetTypeBackoff => 'Back-off';

  @override
  String get gymRoutineModality => 'Medido por';

  @override
  String get gymRoutineModalityWeightReps => 'Peso × reps';

  @override
  String get gymRoutineModalityTime => 'Tempo';

  @override
  String get gymRoutineModalityDistance => 'Distância';

  @override
  String get gymRoutineModalityBodyweightReps => 'Reps com peso corporal';

  @override
  String get gymRoutineSupersetToggle => 'Supersérie com o próximo exercício';

  @override
  String gymRoutineSupersetBadge(int group) {
    return 'Supersérie $group';
  }

  @override
  String get gymRoutineAdvanced => 'Avançado';

  @override
  String get gymRoutineProgression => 'Progressão';

  @override
  String get gymRoutineProgressionNone => 'Nenhuma';

  @override
  String get gymRoutineProgressionLinear => 'Linear';

  @override
  String get gymRoutineProgressionDoubleProgression => 'Dupla progressão';

  @override
  String get gymRoutineProgressionFiveByFive => '5×5';

  @override
  String get gymRoutineProgressionPercentCycle => 'Ciclo % de 1RM';

  @override
  String get gymRoutineProgressionRpeAutoreg => 'Autorregulação RPE';

  @override
  String gymRoutineProgressionIncrementLabel(String unit) {
    return 'Passo de peso ($unit)';
  }

  @override
  String get gymRoutineProgressionPercentLabel => '% de 1RM';

  @override
  String gymRoutineProgressionOneRmLabel(String unit) {
    return '1RM ($unit)';
  }

  @override
  String get gymRoutineProgressionTargetRpeLabel => 'RPE alvo';

  @override
  String get gymRoutineNextTarget => 'Próximo alvo';

  @override
  String get gymRoutineNextTargetIncreaseWeight => 'Aumentar carga na próxima';

  @override
  String get gymRoutineNextTargetIncreaseReps =>
      'Aumentar repetições na próxima';

  @override
  String get gymRoutineNextTargetHold => 'Manter — repetir este alvo';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — reduzir a carga';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'subida de reps $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrição';

  @override
  String get nutritionLogFood => 'Registrar comida';

  @override
  String get nutritionCalories => 'Calorias';

  @override
  String get nutritionProtein => 'Proteínas';

  @override
  String get nutritionCarbs => 'Carboidratos';

  @override
  String get nutritionFat => 'Gorduras';

  @override
  String get nutritionWater => 'Água';

  @override
  String get nutritionWaterAdd => 'Adicionar água';

  @override
  String get nutritionWaterRemove => 'Remover água';

  @override
  String get nutritionNoTargets =>
      'Informe sua altura, peso, idade e sexo no app web para ver as metas de calorias e macros.';

  @override
  String get nutritionWeeklyTrend => 'Últimos 7 dias';

  @override
  String nutritionCaloriesLeft(int n) {
    return '$n kcal restantes';
  }

  @override
  String nutritionCaloriesOver(int n) {
    return '$n kcal acima';
  }

  @override
  String get nutritionOnTarget => 'Na meta';

  @override
  String nutritionMacroOver(int n) {
    return '$n acima da meta';
  }

  @override
  String get nutritionMacroReached => 'Meta atingida';

  @override
  String nutritionWaterAmount(String consumed, String target) {
    return '$consumed / $target L';
  }

  @override
  String get nutritionWaterGoalReached => 'Meta atingida';

  @override
  String nutritionWaterRemaining(int n) {
    return '$n ml restantes';
  }

  @override
  String get nutritionWeekOnGoal => 'Na meta';

  @override
  String nutritionWeekUnderGoal(int n) {
    return '$n abaixo da meta/dia';
  }

  @override
  String nutritionWeekOverGoal(int n) {
    return '$n acima da meta/dia';
  }

  @override
  String get nutritionGoalLine => 'Meta diária';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return 'Meta $base + $exercise kcal queimadas hoje';
  }

  @override
  String get dashGymReadinessIncluded =>
      'As tuas sessões recentes de ginásio entram na tua fadiga.';

  @override
  String get dashGymReadinessExcluded =>
      'A carga do ginásio fica de fora do teu preparo para correr.';

  @override
  String get prefsExcludeGymFromReadiness =>
      'Excluir a carga do ginásio do preparo para correr';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'Por padrão, as sessões de ginásio aumentam a tua fadiga e reduzem o teu preparo, como uma corrida. Ativa isto para que o teu condicionamento, fadiga e forma se baseiem apenas nas corridas.';

  @override
  String get nutritionEmptyTitle => 'Nada registrado hoje';

  @override
  String get nutritionEmptyBody =>
      'Registre uma refeição para acompanhar suas calorias e macros.';

  @override
  String get nutritionSlotBreakfast => 'Café da manhã';

  @override
  String get nutritionSlotLunch => 'Almoço';

  @override
  String get nutritionSlotDinner => 'Jantar';

  @override
  String get nutritionSlotSnack => 'Lanche';

  @override
  String get nutritionMealProtein => 'Proteína';

  @override
  String get nutritionMealCarbs => 'Carboidratos';

  @override
  String get nutritionMealFat => 'Gordura';

  @override
  String get nutritionMealItemsHeading => 'Itens';

  @override
  String get nutritionMealNoItems => 'Nada registrado para esta refeição.';

  @override
  String get nutritionMealTrendHeading => 'Últimos 7 dias';

  @override
  String get nutritionDelete => 'Excluir';

  @override
  String get nutritionDeleteEntryTitle => 'Excluir este item?';

  @override
  String nutritionDeleteEntryMessage(String item) {
    return '$item será removido do registro de hoje.';
  }

  @override
  String get nutritionOfflineQueued =>
      'Offline — as alterações serão sincronizadas ao reconectar';

  @override
  String get nutritionOfflineCached => 'Offline — mostrando entradas salvas';

  @override
  String get nutritionLogTitle => 'Registrar comida';

  @override
  String get nutritionSearchHint => 'Buscar um alimento';

  @override
  String get nutritionSearching => 'Buscando…';

  @override
  String get nutritionNoResults =>
      'Sem resultados. Tente outro termo ou insira manualmente abaixo.';

  @override
  String get nutritionSearchFailed =>
      'A busca falhou. Verifique sua conexão e tente novamente ou insira manualmente abaixo.';

  @override
  String get nutritionSearchRetry => 'Tentar busca novamente';

  @override
  String get nutritionSourceOff => 'Open Food Facts';

  @override
  String get nutritionSourceUsda => 'USDA';

  @override
  String get nutritionScanBarcode => 'Escanear código de barras';

  @override
  String get nutritionScanHint =>
      'Aponte a câmera para o código de barras do produto';

  @override
  String get nutritionScanLookingUp => 'Buscando…';

  @override
  String get nutritionScanNotFound =>
      'Nenhum produto encontrado para esse código de barras. Faça uma busca ou insira manualmente.';

  @override
  String get nutritionScanFailed =>
      'Falha ao escanear. Faça uma busca ou insira manualmente.';

  @override
  String get nutritionScanPermissionDenied =>
      'É necessário acesso à câmera para escanear um código de barras. Você ainda pode buscar ou inserir o alimento manualmente.';

  @override
  String get nutritionScanOpenSettings => 'Abrir configurações';

  @override
  String get nutritionSaveFailed =>
      'Não foi possível registrar o alimento. Tente novamente.';

  @override
  String get nutritionMealSlot => 'Refeição';

  @override
  String get nutritionManualEntry => 'Inserir manualmente';

  @override
  String get nutritionItemName => 'Nome do item';

  @override
  String get nutritionPortionGrams => 'Porção (g)';

  @override
  String get nutritionAdd => 'Adicionar';

  @override
  String get nutritionCancel => 'Cancelar';

  @override
  String get nutritionTemplates => 'Modelos de refeição';

  @override
  String get nutritionSaveAsMeal => 'Salvar como refeição';

  @override
  String get nutritionSaveAsMealTitle => 'Salvar como modelo de refeição';

  @override
  String get nutritionTemplateName => 'Nome do modelo';

  @override
  String get nutritionTemplateNamePlaceholder =>
      'ex.: Café da manhã antes da corrida';

  @override
  String get nutritionSaveTemplate => 'Salvar refeição';

  @override
  String get nutritionTemplateSaved => 'Modelo de refeição salvo.';

  @override
  String nutritionTemplateSaveFailed(String error) {
    return 'Não foi possível salvar o modelo: $error';
  }

  @override
  String get nutritionLogTemplate => 'Registrar';

  @override
  String nutritionTemplateLogged(int n, String name) {
    return '$n itens registrados de $name.';
  }

  @override
  String nutritionTemplateLogFailed(String error) {
    return 'Não foi possível registrar o modelo: $error';
  }

  @override
  String nutritionTemplateItems(int n) {
    return '$n itens';
  }

  @override
  String get nutritionDeleteTemplate => 'Excluir';

  @override
  String get nutritionDeleteTemplateTitle => 'Excluir este modelo de refeição?';

  @override
  String nutritionDeleteTemplateMessage(String name) {
    return '$name será removido. As refeições já registradas a partir dele permanecem no seu diário.';
  }

  @override
  String get nutritionRecipes => 'Receitas';

  @override
  String get nutritionSaveAsRecipe => 'Guardar como receita';

  @override
  String get nutritionSaveAsRecipeTitle => 'Guardar como receita';

  @override
  String get nutritionRecipeName => 'Nome da receita';

  @override
  String get nutritionRecipeNamePlaceholder => 'ex. Tigela de frango com arroz';

  @override
  String get nutritionRecipeServings => 'Porções';

  @override
  String get nutritionRecipeServingsHint =>
      'Os ingredientes são somados e depois divididos pelas porções. Registar uma porção adiciona uma única entrada com os macros combinados.';

  @override
  String get nutritionSaveRecipe => 'Guardar receita';

  @override
  String get nutritionRecipeSaved => 'Receita guardada.';

  @override
  String nutritionRecipeSaveFailed(String error) {
    return 'Não foi possível guardar a receita: $error';
  }

  @override
  String get nutritionLogRecipe => 'Registar';

  @override
  String nutritionRecipeLogged(int n, String name) {
    return '$name registada ($n porção).';
  }

  @override
  String nutritionRecipeLogFailed(String error) {
    return 'Não foi possível registar a receita: $error';
  }

  @override
  String nutritionRecipeMeta(int n, num servings) {
    final intl.NumberFormat servingsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String servingsString = servingsNumberFormat.format(servings);

    return '$n ingredientes · $servingsString porções';
  }

  @override
  String get nutritionDeleteRecipe => 'Eliminar';

  @override
  String get nutritionDeleteRecipeTitle => 'Eliminar esta receita?';

  @override
  String nutritionDeleteRecipeMessage(String name) {
    return '$name será removida. As refeições já registadas a partir dela permanecem no seu diário.';
  }

  @override
  String get sessionTitle => 'Sessões';

  @override
  String get sessionEmpty => 'Ainda não há planos de sessão.';

  @override
  String get sessionEmptyHint =>
      'Crie na web uma sequência reutilizável de yoga, pilates ou aula.';

  @override
  String get sessionUntitled => 'Sessão sem título';

  @override
  String get sessionNotFound => 'Plano de sessão não encontrado.';

  @override
  String get sessionMakePublic => 'Tornar público';

  @override
  String get sessionMakePrivate => 'Tornar privado';

  @override
  String get sessionVisibilityError =>
      'Não foi possível alterar a visibilidade.';

  @override
  String get sessionSteps => 'Sequência';

  @override
  String sessionStepHold(Object name, Object seconds) {
    return '$name · sustentar ${seconds}s';
  }

  @override
  String sessionStepReps(Object name, Object reps) {
    return '$name · $reps reps.';
  }

  @override
  String sessionStepFlow(Object name, Object seconds) {
    return '$name · flow ${seconds}s';
  }

  @override
  String sessionSideLeft(Object name) {
    return '$name (esquerda)';
  }

  @override
  String sessionSideRight(Object name) {
    return '$name (direita)';
  }

  @override
  String sessionEstDuration(Object minutes) {
    return '~ $minutes min';
  }

  @override
  String get gymSessionStart => 'Iniciar sessão';

  @override
  String gymSessionStep(Object exercise, Object set, Object total) {
    return '$exercise · série $set de $total';
  }

  @override
  String get gymSessionComplete => 'Sessão concluída';

  @override
  String get gymSessionSkipSet => 'Ignorar série';

  @override
  String get gymSessionRewind => 'Anterior';

  @override
  String get gymSessionAbandon => 'Abandonar';

  @override
  String get gymSessionFinish => 'Concluir';

  @override
  String get gymSessionDiscardTitle => 'Descartar a sessão?';

  @override
  String get gymSessionDiscardBody =>
      'O teu progresso nesta sessão não será guardado.';

  @override
  String get gymSessionDiscardConfirm => 'Descartar';

  @override
  String get gymSessionSaved => 'Treino guardado';

  @override
  String get gymSessionSaveFailed => 'Não foi possível guardar o treino';

  @override
  String gymSessionSetProgress(Object done, Object total) {
    return '$done/$total';
  }

  @override
  String get gymSessionLogSet => 'Concluir série';

  @override
  String get gymSessionRest => 'Descanso';

  @override
  String gymSessionRestRemaining(Object seconds) {
    return 'Descanso ${seconds}s';
  }

  @override
  String get gymSessionRestSkip => 'Ignorar descanso';

  @override
  String get gymSessionTarget => 'Meta';

  @override
  String gymReviewAdherence(Object pct) {
    return '$pct% de cumprimento';
  }

  @override
  String get gymReviewVerdictCompleted => 'Concluída';

  @override
  String get gymReviewVerdictPartial => 'Parcialmente feita';

  @override
  String get gymReviewVerdictAbandoned => 'Abandonada';

  @override
  String get gymReviewStatusHit => 'Cumprido';

  @override
  String get gymReviewStatusPartial => 'Parcial';

  @override
  String get gymReviewStatusMissed => 'Falhado';

  @override
  String get gymReviewStatusExtra => 'Extra';

  @override
  String get sessionRunStart => 'Iniciar sessão';

  @override
  String sessionRunStep(Object name) {
    return '$name';
  }

  @override
  String get sessionRunDone => 'Feito';

  @override
  String get sessionRunSkip => 'Ignorar';

  @override
  String get sessionRunPause => 'Pausar';

  @override
  String get sessionRunResume => 'Retomar';

  @override
  String get sessionRunAbandon => 'Abandonar';

  @override
  String get sessionRunFinish => 'Concluir';

  @override
  String sessionRunRemaining(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get sessionRunComplete => 'Sessão concluída';

  @override
  String get sessionRunSaved => 'Sessão guardada';

  @override
  String get sessionRunSaveFailed => 'Não foi possível guardar a sessão';

  @override
  String get sessionRunDiscardTitle => 'Descartar a sessão?';

  @override
  String get sessionRunDiscardBody =>
      'O teu progresso nesta sessão não será guardado.';

  @override
  String get sessionRunDiscardConfirm => 'Descartar';

  @override
  String get sessionRunVerdictCompleted => 'Concluída';

  @override
  String get sessionRunVerdictPartial => 'Parcialmente feita';

  @override
  String get sessionRunVerdictAbandoned => 'Abandonada';

  @override
  String sessionRunStepCount(int index, int total) {
    return 'Etapa $index de $total';
  }

  @override
  String get sessionRunSwitchSides => 'Troque de lado';

  @override
  String get coachingTitle => 'Treinamento';

  @override
  String get coachingLede =>
      'Treine atletas compartilhando um link de convite e acompanhe o treino deles. Ou siga o seu próprio treinador aqui.';

  @override
  String get coachingCancel => 'Cancelar';

  @override
  String get coachingMyAthletes => 'Meus atletas';

  @override
  String get coachingMyAthletesSub => 'Corredores que aceitaram seu convite';

  @override
  String get coachingInviteAnAthlete => 'Convidar um atleta';

  @override
  String get coachingCreating => 'Criando…';

  @override
  String get coachingPendingInvite => 'Convite pendente';

  @override
  String coachingPendingInviteSub(String date) {
    return 'Criado em $date · ainda não aceito';
  }

  @override
  String get coachingCopyLink => 'Copiar link';

  @override
  String get coachingShareLink => 'Compartilhar link';

  @override
  String get coachingRevoke => 'Revogar';

  @override
  String get coachingNoAthletes =>
      'Nenhum atleta ainda. Convide um para começar.';

  @override
  String get coachingRosterTitle => 'Lista de atletas';

  @override
  String get coachingRosterSubtitle =>
      'Todos os seus atletas num relance — carga, adesão ao plano e risco de lesão.';

  @override
  String get coachingRosterNeverRun => 'Nenhuma corrida ainda';

  @override
  String get coachingRosterNoPlan => 'Sem plano';

  @override
  String get coachingRosterRiskInsufficient => 'Novo';

  @override
  String get coachingRosterRiskLow => 'Baixo';

  @override
  String get coachingRosterRiskOptimal => 'Ótimo';

  @override
  String get coachingRosterRiskElevated => 'Elevado';

  @override
  String get coachingRosterRiskHigh => 'Alto';

  @override
  String get coachingRunner => 'Corredor';

  @override
  String coachingCoachingSince(String date) {
    return 'Treinando desde $date';
  }

  @override
  String get coachingReview => 'Revisar';

  @override
  String get coachingRemove => 'Remover';

  @override
  String get coachingMyCoaches => 'Meus treinadores';

  @override
  String get coachingMyCoachesSub => 'Treinadores que podem ver seu treino';

  @override
  String get coachingNoCoaches =>
      'Você ainda não aceitou o convite de um treinador.';

  @override
  String get coachingCoach => 'Treinador';

  @override
  String coachingLinkedSince(String date) {
    return 'Vinculado desde $date';
  }

  @override
  String get coachingLeave => 'Sair';

  @override
  String get coachingInviteLinkCopied => 'Link de convite copiado';

  @override
  String get coachingThisAthlete => 'este atleta';

  @override
  String get coachingThisCoach => 'este treinador';

  @override
  String get coachingRevokeTitle => 'Revogar convite?';

  @override
  String get coachingRevokeBody =>
      'O link de convite deixará de funcionar. Você sempre pode criar um novo.';

  @override
  String get coachingRemoveAthleteTitle => 'Remover atleta?';

  @override
  String coachingRemoveAthleteBody(String name) {
    return 'Parar de treinar $name? Você perderá o acesso às corridas e planos dele.';
  }

  @override
  String get coachingLeaveCoachTitle => 'Sair do treinador?';

  @override
  String coachingLeaveCoachBody(String name) {
    return 'Parar de compartilhar seu treino com $name?';
  }

  @override
  String coachingLoadError(String error) {
    return 'Não foi possível carregar o treinamento: $error';
  }

  @override
  String coachingCreateInviteError(String error) {
    return 'Não foi possível criar o convite: $error';
  }

  @override
  String coachingRevokeInviteError(String error) {
    return 'Não foi possível revogar o convite: $error';
  }

  @override
  String coachingRemoveAthleteError(String error) {
    return 'Não foi possível remover o atleta: $error';
  }

  @override
  String coachingEndLinkError(String error) {
    return 'Não foi possível encerrar o vínculo: $error';
  }

  @override
  String get coachingAthleteAthleteFallback => 'Atleta';

  @override
  String get coachingAthleteRunnerFallback => 'Corredor';

  @override
  String coachingAthleteCoachingSince(String date) {
    return 'Treinando desde $date';
  }

  @override
  String get coachingAthletePlanCompliance => 'Cumprimento do plano';

  @override
  String get coachingAthleteNoActivePlan => 'Sem plano de treino ativo.';

  @override
  String get coachingAthleteAssignTitle => 'Atribuir um plano';

  @override
  String coachingAthleteAssignHint(String name) {
    return 'Escolha um dos seus planos para atribuir a $name.';
  }

  @override
  String get coachingAthleteAssignSelectLabel => 'Plano';

  @override
  String get coachingAthleteAssignSelectPlaceholder => 'Escolha um plano…';

  @override
  String get coachingAthleteAssignStartLabel => 'Data de início';

  @override
  String get coachingAthleteAssigning => 'Atribuindo…';

  @override
  String get coachingAthleteAssignButton => 'Atribuir plano';

  @override
  String get coachingAthleteAssignNoPlans =>
      'Crie primeiro um plano de treino, depois você poderá atribuí-lo aos seus atletas.';

  @override
  String get coachingAthleteAssignedByYou => 'Atribuído por você';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'Este atleta já tem um plano ativo. Ele precisará concluí-lo ou encerrá-lo antes que você possa atribuir um novo.';

  @override
  String get coachingAthleteComplete => 'concluído';

  @override
  String coachingAthleteDoneCount(int done, int total) {
    return '$done de $total feitos';
  }

  @override
  String coachingAthleteMissedCount(int n) {
    return '$n perdidos';
  }

  @override
  String get coachingAthleteStatusDone => 'Feito';

  @override
  String get coachingAthleteStatusMissed => 'Perdido';

  @override
  String get coachingAthleteStatusUpcoming => 'Próximo';

  @override
  String get coachingAthleteRecentRuns => 'Corridas recentes';

  @override
  String get coachingAthleteNoRunsYet => 'Nenhuma corrida registrada ainda.';

  @override
  String get coachingAthletePrivate => 'Privado';

  @override
  String coachingAthleteAssignSuccess(String name) {
    return 'Plano atribuído a $name';
  }

  @override
  String coachingAthleteLoadError(String error) {
    return 'Não foi possível carregar o atleta: $error';
  }

  @override
  String get routeMarkerHeading => 'Marcadores do percurso';

  @override
  String get routeMarkerAdd => 'Adicionar marcador';

  @override
  String get routeMarkerEmpty =>
      'Nenhum marcador ainda. Adicione postos de apoio, cortes de tempo e mais ao longo do percurso.';

  @override
  String get routeMarkerEdit => 'Editar marcador';

  @override
  String get routeMarkerDelete => 'Excluir';

  @override
  String get routeMarkerCancel => 'Cancelar';

  @override
  String get routeMarkerSave => 'Salvar';

  @override
  String get routeMarkerSaving => 'Salvando…';

  @override
  String get routeMarkerKindLabel => 'Tipo';

  @override
  String get routeMarkerNameLabel => 'Nome';

  @override
  String get routeMarkerNamePlaceholder => 'ex.: Apoio 2';

  @override
  String get routeMarkerServicesLabel => 'Serviços';

  @override
  String get routeMarkerCutoffLabel => 'Horário de corte';

  @override
  String get routeMarkerNoteLabel => 'Nota';

  @override
  String get routeMarkerTapToPlace =>
      'Toque no mapa para posicionar este marcador.';

  @override
  String get routeMarkerPlaced =>
      'Posicionado. Toque no mapa novamente para movê-lo.';

  @override
  String routeMarkerCutoffAt(String time) {
    return 'Corte $time';
  }

  @override
  String get routeMarkerLabelRequired => 'Dê um nome ao marcador.';

  @override
  String get routeMarkerPlaceRequired =>
      'Posicione o marcador no mapa primeiro.';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Não foi possível salvar o marcador: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Não foi possível excluir o marcador: $error';
  }

  @override
  String get routeMarkerDeleteConfirmTitle => 'Excluir marcador?';

  @override
  String get routeMarkerDeleteConfirmMessage =>
      'Isso remove o marcador do percurso permanentemente.';

  @override
  String get routeMarkerKindAidStation => 'Posto de apoio';

  @override
  String get routeMarkerKindCutoff => 'Corte de tempo';

  @override
  String get routeMarkerKindCrewAccess => 'Equipe / estacionamento';

  @override
  String get routeMarkerKindHazard => 'Perigo';

  @override
  String get routeMarkerKindNote => 'Nota';

  @override
  String get routeMarkerKindClimb => 'Subida';

  @override
  String get routeMarkerKindCustom => 'Personalizado';

  @override
  String get routeMarkerServiceWater => 'Água';

  @override
  String get routeMarkerServiceFood => 'Comida';

  @override
  String get routeMarkerServiceMedical => 'Médico';

  @override
  String get routeMarkerServiceToilets => 'Banheiros';

  @override
  String get routeMarkerServiceDropBag => 'Drop bag';

  @override
  String get clubFormEditTitle => 'Editar clube';

  @override
  String get clubEditorWebsite => 'Site';

  @override
  String get clubEditorInstagram => 'Instagram';

  @override
  String get clubEditorStrava => 'Strava';

  @override
  String get clubEditorFacebook => 'Facebook';

  @override
  String get clubEditorSaveChanges => 'Salvar alterações';

  @override
  String get clubDetailVisitWebsite => 'Visite nosso site';

  @override
  String get clubDetailEditClub => 'Editar clube';

  @override
  String get roadbookTitle => 'Roadbook';

  @override
  String get roadbookCrewSheet => 'Roadbook (planilha da equipe)';

  @override
  String get roadbookGoalTime => 'Tempo-alvo';

  @override
  String get roadbookStartTime => 'Horário de largada';

  @override
  String get roadbookEffort => 'Esforço';

  @override
  String get roadbookEven => 'Uniforme';

  @override
  String get roadbookStart => 'Largada';

  @override
  String get roadbookFinish => 'Chegada';

  @override
  String get roadbookShare => 'Compartilhar';

  @override
  String get roadbookNoMarkers =>
      'Adicione marcadores ao percurso para criar um roadbook.';

  @override
  String get roadbookAddElevation => 'Adicionar altimetria';

  @override
  String get roadbookElevationUnavailable =>
      'Dados de altimetria indisponíveis para este percurso';

  @override
  String roadbookSummary(String distance, String vert, String time) {
    return '$distance · $vert de ganho · meta $time';
  }

  @override
  String get roadbookFuel => 'Abastecimento';

  @override
  String get roadbookHeat => 'Calor';

  @override
  String get roadbookCarbs => 'Carboidratos';

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
    return 'levar $gels géis · $fluid ml';
  }

  @override
  String get checkpointCheckinAction => 'Check-in no ponto de controlo';

  @override
  String get checkpointCheckinTitle => 'Check-in no abastecimento';

  @override
  String get checkpointSyncNow => 'Sincronizar agora';

  @override
  String get checkpointPending => 'Por sincronizar';

  @override
  String get checkpointLoadFailed =>
      'Não foi possível carregar os pontos de controlo';

  @override
  String get checkpointRetry => 'Tentar novamente';

  @override
  String get checkpointNone =>
      'Esta prova ainda não tem pontos de controlo. Adicione-os na web antes de a equipa registar os corredores.';

  @override
  String get checkpointPickLabel => 'PONTO DE CONTROLO';

  @override
  String get checkpointBibLabel => 'Número de peito';

  @override
  String get checkpointBibHint => 'Digitalize ou escreva um número';

  @override
  String get checkpointBibRequired => 'Introduza primeiro um número de peito';

  @override
  String get checkpointStampIn => 'Registar ENTRADA';

  @override
  String get checkpointStampOut => 'Registar SAÍDA';

  @override
  String checkpointStampedIn(String bib) {
    return 'Número $bib com entrada registada';
  }

  @override
  String checkpointStampedOut(String bib) {
    return 'Número $bib com saída registada';
  }

  @override
  String get checkpointStampFailed => 'Não foi possível guardar esse registo';

  @override
  String checkpointLoggedHere(int count) {
    return 'REGISTADOS AQUI ($count)';
  }

  @override
  String get checkpointNoneLoggedHere =>
      'Ainda não há corredores registados neste ponto de controlo.';

  @override
  String checkpointBibRow(String bib) {
    return 'Número $bib';
  }

  @override
  String checkpointInOut(String inTime, String outTime) {
    return 'Entrada $inTime · Saída $outTime';
  }

  @override
  String get checkpointWeighInTitle => 'Pesagem';

  @override
  String get checkpointWeighInConsentBlurb =>
      'O peso corporal e as notas de retenção médica são dados de saúde, registados apenas com o consentimento do corredor e visíveis apenas para os oficiais da prova.';

  @override
  String get checkpointWeighInConsent =>
      'O corredor consente o registo de dados de saúde';

  @override
  String get checkpointWeighInWeightKg => 'Peso corporal (kg)';

  @override
  String get checkpointMedicalHold => 'Colocar em retenção médica';

  @override
  String get checkpointWeighInSave => 'Guardar e registar';

  @override
  String get checkpointCancel => 'Cancelar';

  @override
  String get challengesTitle => 'Desafios';

  @override
  String get challengesMyChallenges => 'Meus desafios';

  @override
  String get challengesBrowse => 'Explorar';

  @override
  String get challengesEmpty => 'Nenhum desafio ainda.';

  @override
  String get challengesBrowseEmpty =>
      'Nenhum desafio público para entrar no momento.';

  @override
  String get challengesJoin => 'Entrar';

  @override
  String get challengesLeave => 'Sair';

  @override
  String get challengesDelete => 'Eliminar';

  @override
  String get challengesMetricDistance => 'Distância';

  @override
  String get challengesMetricDuration => 'Tempo';

  @override
  String get challengesMetricVert => 'Elevação';

  @override
  String get challengesMetricActivityCount => 'Atividades';

  @override
  String get challengesMetricStreak => 'Dias ativos';

  @override
  String challengesGoalProgress(String value, String goal) {
    return '$value de $goal';
  }

  @override
  String get challengesProgressComplete => 'Concluído';

  @override
  String challengesEndsIn(int n) {
    return 'Termina em $n dias';
  }

  @override
  String get challengesEndsToday => 'Termina hoje';

  @override
  String get challengesEnded => 'Encerrado';

  @override
  String get challengesLeaderboard => 'Ranking';

  @override
  String get challengesLeaderboardEmpty => 'Nenhum progresso registrado ainda.';

  @override
  String challengesLeaderboardRank(int rank) {
    return '#$rank';
  }

  @override
  String challengesParticipants(int n) {
    return '$n participantes';
  }

  @override
  String get challengesBadgeEarned => 'Emblema conquistado';

  @override
  String challengesUnitDays(int n) {
    return '$n dias';
  }

  @override
  String challengesUnitActivities(int n) {
    return '$n';
  }

  @override
  String get challengesLeaveConfirmTitle => 'Sair do desafio?';

  @override
  String get challengesLeaveConfirm =>
      'O seu progresso neste desafio deixará de ser acompanhado.';

  @override
  String get challengesDeleteConfirmTitle => 'Eliminar desafio?';

  @override
  String get challengesDeleteConfirm =>
      'Isto remove o desafio e o ranking para todos. Não pode ser anulado.';

  @override
  String get challengesNotFound => 'Este desafio não está disponível.';

  @override
  String get challengesJoinFailed => 'Não foi possível entrar no desafio.';

  @override
  String get challengesLeaveFailed => 'Não foi possível sair do desafio.';

  @override
  String get challengesLoadFailed => 'Não foi possível carregar os desafios.';

  @override
  String fundraiserRaisedOfGoal(String raised, String goal) {
    return '$raised de $goal angariados';
  }

  @override
  String fundraiserDonorCount(int count) {
    return '$count apoiantes';
  }

  @override
  String get fundraiserOverGoal => 'Meta superada!';

  @override
  String get fundraiserClosed => 'Esta campanha está encerrada.';

  @override
  String get fundraiserFeedTitle => 'Apoiantes recentes';

  @override
  String get fundraiserFeedEmpty => 'Seja o primeiro a doar.';

  @override
  String get fundraiserAnonymous => 'Anónimo';

  @override
  String get fundraiserDonateOnWeb => 'Doar na web';

  @override
  String get racesTitle => 'Calendário de corridas';

  @override
  String get racesSearchPlaceholder => 'Procurar corridas por nome…';

  @override
  String get racesNearPlace => 'Perto de um local…';

  @override
  String racesKmAway(String distance) {
    return 'a $distance';
  }

  @override
  String get racesDistanceAny => 'Qualquer distância';

  @override
  String get racesDistance5k => '5K';

  @override
  String get racesDistance10k => '10K';

  @override
  String get racesDistanceHalf => 'Meia';

  @override
  String get racesDistanceMarathon => 'Maratona';

  @override
  String get racesDistanceUltra => 'Ultra';

  @override
  String get racesRegister => 'Inscrever-se';

  @override
  String get racesViewResults => 'Ver resultados';

  @override
  String get racesImportResult => 'Importar o meu resultado';

  @override
  String get racesSubmitRace => 'Adicionar uma corrida';

  @override
  String get racesUnverified => 'Não verificada';

  @override
  String get racesEmpty =>
      'Ainda não há corridas que correspondam a estes filtros.';

  @override
  String get racesSearchFailed =>
      'Não foi possível carregar as corridas. Verifica a tua ligação e tenta novamente.';

  @override
  String racesMatchPrompt(String name) {
    return 'Foi esta a $name? Importa o teu resultado oficial.';
  }

  @override
  String get racesMatchConfirm => 'Importar resultado';

  @override
  String get racesMatchDismiss => 'Não é esta corrida';

  @override
  String get racesImported => 'Resultado oficial importado.';

  @override
  String get racesOfficialResult => 'Resultado oficial';

  @override
  String get racesChipTime => 'Tempo líquido';

  @override
  String get racesGunTime => 'Tempo bruto';

  @override
  String get racesOverallPlace => 'Classificação geral';

  @override
  String get racesAgeGroupPlace => 'Classificação por escalão';

  @override
  String get racesAgeGroup => 'Escalão etário';

  @override
  String get racesBib => 'Dorsal';

  @override
  String get racesPasteResultHint =>
      'Introduz os detalhes da tua chegada a partir da página de resultados da corrida.';

  @override
  String get racesSave => 'Guardar';

  @override
  String get racesCancel => 'Cancelar';

  @override
  String get racesEditorTitle => 'Adicionar uma corrida';

  @override
  String get racesFieldName => 'Nome da corrida';

  @override
  String get racesFieldDate => 'Data';

  @override
  String get racesFieldDistance => 'Distância (metros)';

  @override
  String get racesFieldLocation => 'Localização';

  @override
  String get racesFieldEntryUrl => 'Link de inscrição';

  @override
  String get racesFieldResultsUrl => 'Link de resultados';

  @override
  String get racesSubmitFailed =>
      'Não foi possível guardar a corrida. Tenta novamente.';

  @override
  String get racesImportFailed =>
      'Não foi possível importar o resultado. Tenta novamente.';

  @override
  String get navRaces => 'Corridas';

  @override
  String get integrationsRunsignup => 'RunSignUp';

  @override
  String get integrationsRunsignupConnect =>
      'Importa resultados de corridas do RunSignUp.';

  @override
  String get integrationsRunsignupOpen => 'Abrir o calendário de corridas';

  @override
  String get integrationsRunsignupUnavailable =>
      'A importação do RunSignUp ainda não está disponível. O parkrun e a colagem manual continuam a funcionar.';

  @override
  String get routeConditionsTitle => 'Condições';

  @override
  String get routeConditionsReport => 'Relatar condição';

  @override
  String get routeConditionsReporting => 'Enviando…';

  @override
  String get routeConditionsReported => 'Condição relatada';

  @override
  String get routeConditionsReportFailed =>
      'Não foi possível relatar a condição';

  @override
  String get routeConditionsEmpty => 'Ainda não há relatos.';

  @override
  String get routeConditionsLoading => 'Carregando…';

  @override
  String get routeConditionsCancel => 'Cancelar';

  @override
  String get routeConditionsDelete => 'Excluir';

  @override
  String get routeConditionsDeleteTitle => 'Excluir relato?';

  @override
  String get routeConditionsDeleteConfirm =>
      'Isso remove o relato permanentemente.';

  @override
  String get routeConditionsDeleteFailed => 'Não foi possível excluir o relato';

  @override
  String get routeConditionsKindLabel => 'Condição';

  @override
  String get routeConditionsSeverityLabel => 'Gravidade';

  @override
  String get routeConditionsNoteLabel => 'Nota';

  @override
  String get routeConditionsNotePlaceholder =>
      'O que o próximo corredor vai encontrar?';

  @override
  String routeConditionsAtDistance(String distance) {
    return 'em $distance';
  }

  @override
  String get routeConditionMuddy => 'Lamacento';

  @override
  String get routeConditionFlooded => 'Alagado';

  @override
  String get routeConditionSnowIce => 'Neve / gelo';

  @override
  String get routeConditionOvergrown => 'Coberto de vegetação';

  @override
  String get routeConditionClosed => 'Fechado';

  @override
  String get routeConditionHazard => 'Perigo';

  @override
  String get routeConditionClear => 'Livre';

  @override
  String get routeConditionOther => 'Outro';

  @override
  String get routeConditionSeverityInfo => 'Info';

  @override
  String get routeConditionSeverityCaution => 'Cuidado';

  @override
  String get routeConditionSeverityImpassable => 'Intransitável';

  @override
  String get prefTurnByTurnCues => 'Instruções de voz curva a curva';

  @override
  String get prefTurnByTurnCuesSubtitle =>
      'Direções faladas ao seguir uma rota salva';

  @override
  String ttsTurnLeftIn(String distance) {
    return 'Em $distance, vire à esquerda';
  }

  @override
  String ttsTurnRightIn(String distance) {
    return 'Em $distance, vire à direita';
  }

  @override
  String get ttsTurnLeftNow => 'Vire à esquerda';

  @override
  String get ttsTurnRightNow => 'Vire à direita';

  @override
  String get ttsSlightLeft => 'Mantenha-se à esquerda';

  @override
  String get ttsSlightRight => 'Mantenha-se à direita';

  @override
  String get ttsUturn => 'Faça um retorno';

  @override
  String routeOfflinePackDownloading(int done, int total) {
    return 'Salvando mapa: $done / $total';
  }

  @override
  String get routeOfflinePackReady => 'Mapa salvo para uso offline';

  @override
  String routeOfflinePackPartial(int done, int total) {
    return 'Mapa parcialmente salvo ($done / $total) — tentar de novo';
  }

  @override
  String get routeOfflinePackTooLarge =>
      'Esta rota é grande demais para salvar offline';

  @override
  String get badgesSectionTitle => 'Conquistas';

  @override
  String get badgesSectionSubtitle => 'Marcos que você alcançou';

  @override
  String get badgesEmpty => 'Ainda sem medalhas — continue correndo.';

  @override
  String get badgesEmptyOther => 'Ainda não há medalhas públicas.';

  @override
  String badgesEarnedOn(String date) {
    return 'Conquistada em $date';
  }

  @override
  String badgesFeedEarned(String name, String badge) {
    return '$name conquistou a medalha $badge';
  }

  @override
  String get badgesARunner => 'Um corredor';

  @override
  String get badgesTierBronze => 'Bronze';

  @override
  String get badgesTierSilver => 'Prata';

  @override
  String get badgesTierGold => 'Ouro';

  @override
  String get badgesTierPlatinum => 'Platina';

  @override
  String get badgesDistanceSingle5kLabel => 'Primeiros 5 km';

  @override
  String get badgesDistanceSingle5kDesc => 'Correu 5 km em uma única corrida';

  @override
  String get badgesDistanceSingleHalfLabel => 'Meia maratona';

  @override
  String get badgesDistanceSingleHalfDesc =>
      'Correu 21,1 km em uma única corrida';

  @override
  String get badgesDistanceSingleMarathonLabel => 'Maratona';

  @override
  String get badgesDistanceSingleMarathonDesc =>
      'Correu 42,2 km em uma única corrida';

  @override
  String get badgesDistanceSingleUltraLabel => 'Ultra';

  @override
  String get badgesDistanceSingleUltraDesc =>
      'Correu 50 km ou mais em uma única corrida';

  @override
  String get badgesDistanceLifetime100Label => 'Clube dos 100 km';

  @override
  String get badgesDistanceLifetime100Desc => '100 km registrados no total';

  @override
  String get badgesDistanceLifetime500Label => '500 km';

  @override
  String get badgesDistanceLifetime500Desc => '500 km registrados no total';

  @override
  String get badgesDistanceLifetime1000Label => 'Clube dos 1.000 km';

  @override
  String get badgesDistanceLifetime1000Desc => '1.000 km registrados no total';

  @override
  String get badgesDistanceLifetime5000Label => '5.000 km';

  @override
  String get badgesDistanceLifetime5000Desc => '5.000 km registrados no total';

  @override
  String get badgesStreak7Label => 'Sequência semanal';

  @override
  String get badgesStreak7Desc => 'Correu 7 dias seguidos';

  @override
  String get badgesStreak30Label => 'Sequência mensal';

  @override
  String get badgesStreak30Desc => 'Correu 30 dias seguidos';

  @override
  String get badgesStreak100Label => 'Sequência de cem';

  @override
  String get badgesStreak100Desc => 'Correu 100 dias seguidos';

  @override
  String get badgesStreak365Label => 'Sequência anual';

  @override
  String get badgesStreak365Desc => 'Correu 365 dias seguidos';

  @override
  String get badgesPr1Label => 'Primeiro recorde';

  @override
  String get badgesPr1Desc => 'Estabeleceu seu primeiro recorde pessoal';

  @override
  String get badgesPr3Label => 'Recorde triplo';

  @override
  String get badgesPr3Desc => 'Detém recordes pessoais em 3 distâncias';

  @override
  String get badgesPr5Label => 'Colecionador de recordes';

  @override
  String get badgesPr5Desc => 'Detém recordes pessoais em todas as distâncias';

  @override
  String get badgesPlan1Label => 'Plano concluído';

  @override
  String get badgesPlan1Desc => 'Concluiu um plano de treino';

  @override
  String get badgesPlan3Label => 'Triplo concluído';

  @override
  String get badgesPlan3Desc => 'Concluiu 3 planos de treino';

  @override
  String get badgesPlan10Label => 'Veterano de planos';

  @override
  String get badgesPlan10Desc => 'Concluiu 10 planos de treino';

  @override
  String get racePredictorTitle => 'Previsão de tempo de prova';

  @override
  String racePredictorAnchoredOn(String distance, String time) {
    return 'A partir do seu esforço de $distance em $time';
  }

  @override
  String get racePredictorColDistance => 'Distância';

  @override
  String get racePredictorColTime => 'Tempo';

  @override
  String get racePredictorColPace => 'Ritmo';

  @override
  String get racePredictorColConfidence => 'Confiança';

  @override
  String get racePredictorConfidenceHigh => 'Alta';

  @override
  String get racePredictorConfidenceModerate => 'Média';

  @override
  String get racePredictorConfidenceLow => 'Baixa';

  @override
  String get racePredictorConfReasonSimilar =>
      'Baseado em esforços recentes próximos a esta distância.';

  @override
  String get racePredictorConfReasonExtrapolated =>
      'Extrapolado por uma grande diferença de distância — trate como uma estimativa.';

  @override
  String get racePredictorConfReasonStale =>
      'Ancorado em um esforço de algumas semanas atrás.';

  @override
  String get racePredictorConfReasonLimited =>
      'Baseado em dados recentes limitados.';

  @override
  String get racePredictorFootnote =>
      'Equivalência de Riegel a partir do seu melhor esforço recente, ponderada pela recência. Distâncias mais próximas são mais confiáveis.';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String get trustedContactsClearedBanner => 'Contatos de confiança removidos.';

  @override
  String trustedContactsSavedBanner(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contatos de confiança salvos.',
      one: '1 contato de confiança salvo.',
    );
    return '$_temp0';
  }

  @override
  String trustedContactsSaveFailedBanner(Object error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get trustedContactsTitle => 'Contatos de confiança';

  @override
  String trustedContactsIntro(Object max) {
    return 'Defina um ou mais contatos de confiança. A estrutura armazena a lista junto à sua conta para que os recursos planejados de \"corrida atrasada\" e botão de pânico tenham para onde enviar notificações. Até $max.';
  }

  @override
  String get trustedContactsAddButton => 'Adicionar contato';

  @override
  String get trustedContactsSavingButton => 'Salvando…';

  @override
  String get trustedContactsSaveButton => 'Salvar';

  @override
  String get trustedContactsNameLabel => 'Nome';

  @override
  String get trustedContactsNameHint => 'ex.: Alex Chen';

  @override
  String get trustedContactsPhoneLabel => 'Telefone';

  @override
  String get trustedContactsPhoneHint => '+55 11 91234 5678';

  @override
  String get trustedContactsEmailLabel => 'E-mail';

  @override
  String get trustedContactsEmailHint => 'alex@exemplo.com';

  @override
  String get trustedContactsRelationshipLabel => 'Relação';

  @override
  String get trustedContactsRelationshipHint =>
      'parceiro(a) / pai ou mãe / parceiro(a) de corrida';

  @override
  String get trustedContactsRemoveButton => 'Remover';

  @override
  String get clubInviteEnterCodeError =>
      'Digite o código de convite do seu link.';

  @override
  String get clubInviteJoinedBanner => 'Você entrou no clube.';

  @override
  String get clubInviteTitle => 'Entrar no clube';

  @override
  String get clubInviteIntro =>
      'Cole o código de convite que o administrador do clube compartilhou com você.';

  @override
  String get clubInviteCodeLabel => 'Código de convite';

  @override
  String get clubInviteJoinButton => 'Entrar';

  @override
  String recapShareHeadline(Object year) {
    return 'Meu $year na corrida:';
  }

  @override
  String recapShareTotals(Object total, Object count) {
    return '$total em $count corridas';
  }

  @override
  String recapShareLongestRun(Object distance) {
    return 'Corrida mais longa: $distance';
  }

  @override
  String recapShareBestStreak(Object days) {
    return 'Melhor sequência: $days dias';
  }

  @override
  String recapShareSubject(Object year) {
    return 'Retrospectiva $year';
  }

  @override
  String get recapTitle => 'Ano na corrida';

  @override
  String get recapShareTooltip => 'Compartilhar retrospectiva';

  @override
  String get recapPublishAndShare => 'Publicar e compartilhar link';

  @override
  String get recapPublishFailed =>
      'Não foi possível publicar o resumo. Tente novamente.';

  @override
  String get recapPrevYear => 'Ano anterior';

  @override
  String get recapNextYear => 'Próximo ano';

  @override
  String recapNoRunsForYear(Object year) {
    return 'Nenhuma corrida para a retrospectiva de $year.';
  }

  @override
  String recapNoRunsYet(Object year) {
    return 'Ainda não há corridas em $year. Registre uma para ver sua retrospectiva.';
  }

  @override
  String recapAcrossRuns(Object count, Object runWord) {
    return 'em $count $runWord';
  }

  @override
  String get recapLongestRunLabel => 'Corrida mais longa';

  @override
  String get recapBestStreakLabel => 'Melhor sequência';

  @override
  String recapStreakDays(Object days, Object dayWord) {
    return '$days $dayWord';
  }

  @override
  String get recapTopWeekLabel => 'Melhor semana';

  @override
  String get recapUniqueRoutesLabel => 'Rotas únicas';

  @override
  String get recapEarliestStartLabel => 'Início mais cedo';

  @override
  String get recapLatestStartLabel => 'Início mais tarde';

  @override
  String get routePickerTitle => 'Escolher rota';

  @override
  String get routePickerNoRoute => 'Sem rota';

  @override
  String get routePickerClearSearchTooltip => 'Limpar busca';

  @override
  String get routePickerSearchHint => 'Buscar rotas por nome…';

  @override
  String get routePickerEmptyNoRoutes => 'Nenhuma rota salva ainda';

  @override
  String routePickerEmptyNoMatch(Object query) {
    return 'Nenhuma rota corresponde a \"$query\"';
  }

  @override
  String get routePickerStarredHeader => 'Com estrela';

  @override
  String get routePickerAllRoutesHeader => 'Todas as rotas';

  @override
  String importStatusImported(Object count, Object label) {
    return '$count corridas importadas de $label';
  }

  @override
  String importStatusImportedWithErrors(Object count, Object errors) {
    return '$count corridas importadas ($errors com falha)';
  }

  @override
  String importStatusNoGpsNote(Object base, Object label) {
    return '$base. $label não tem dados de rota, então essas corridas não têm mapa.';
  }

  @override
  String importHealthRequestingPermission(Object label) {
    return 'Solicitando permissão do $label...';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return 'Permissão do $label negada';
  }

  @override
  String get importHealthReadingWorkouts => 'Lendo treinos...';

  @override
  String importHealthFailed(Object label, Object error) {
    return 'Falha na importação do $label: $error';
  }

  @override
  String get importStatusSavingLocally => 'Salvando localmente...';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return '$count duplicata(s) ignorada(s) já importada(s) de outra fonte';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return '$done de $total salvas localmente';
  }

  @override
  String get importStatusSyncingToCloud => 'Sincronizando com a nuvem...';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return '$done de $total sincronizadas';
  }

  @override
  String get importStatusReadingCsv => 'Lendo CSV...';

  @override
  String importCsvFailed(Object error) {
    return 'Falha na importação do CSV: $error';
  }

  @override
  String get importStatusRestoringBackup => 'Restaurando backup...';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return '$runs corridas · $tracks trajetos · $routes rotas restauradas';
  }

  @override
  String importBackupFailed(Object error) {
    return 'Falha ao restaurar o backup: $error';
  }

  @override
  String get importStatusReadingExport => 'Lendo exportação...';

  @override
  String importStravaFailed(Object error) {
    return 'Falha na importação: $error';
  }

  @override
  String get importTitle => 'Importar corridas';

  @override
  String get importStravaCardTitle => 'Strava';

  @override
  String get importStravaCardSubtitle =>
      'Importe todas as corridas de um ZIP de exportação de dados do Strava';

  @override
  String get importStravaHowToHeader => 'Como obter sua exportação do Strava:';

  @override
  String get importStravaHowToSteps =>
      '1. Abra o Strava → Configurações → Minha conta\n2. Role até \"Baixar ou excluir sua conta\"\n3. Toque em \"Começar\" → \"Solicitar seu arquivo\"\n4. Você receberá um e-mail com um link de download em algumas horas\n5. Baixe o .zip e toque em Importar abaixo';

  @override
  String get importStravaButton => 'Importar ZIP do Strava';

  @override
  String importHealthButton(Object label) {
    return 'Importar do $label';
  }

  @override
  String get importCsvCardTitle => 'CSV';

  @override
  String get importCsvCardSubtitle =>
      'Reimporte um CSV exportado em Configurações — apenas corridas, sem GPS';

  @override
  String get importCsvCardDescription =>
      'Cada linha do CSV vira uma corrida manual (data, distância, duração, fonte). O trajeto no mapa não está no CSV, então as corridas importadas não terão linha de rota.';

  @override
  String get importCsvButton => 'Importar CSV';

  @override
  String get importBackupCardTitle => 'ZIP de backup completo';

  @override
  String get importBackupCardSubtitle =>
      'Restaure corridas, rotas e trajetos de GPS de um arquivo de backup';

  @override
  String get importBackupCardDescription =>
      'Ida e volta sem perdas. Funciona sem login — as corridas restauradas sincronizam com sua conta na próxima vez que você entrar. Faça um backup em Configurações → Backup completo.';

  @override
  String get importBackupButton => 'Restaurar ZIP de backup';

  @override
  String get importErrorsHeader => 'Erros';

  @override
  String importErrorsMore(Object count) {
    return '... e mais $count';
  }

  @override
  String get importHealthSubtitleIos =>
      'Importe treinos gravados no Apple Watch, Nike Run Club, Strava e outros apps que gravam no Apple Saúde';

  @override
  String get importHealthSubtitleAndroid =>
      'Importe treinos do Google Fit, Samsung Health, Garmin, Fitbit e qualquer outro app do Health Connect';

  @override
  String get importHealthDescriptionIos =>
      'Lê resumos de treino (data, distância, duração, tipo) do último ano. O Apple Saúde não expõe rotas de GPS gravadas por apps de terceiros — as corridas importadas assim não terão trajeto no mapa.';

  @override
  String get importHealthDescriptionAndroid =>
      'Lê resumos de treino (data, distância, duração, tipo) do último ano. As rotas de GPS não são expostas pelo Health Connect — as corridas importadas assim não terão trajeto no mapa.';

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'Não foi possível atualizar o seguimento: $error';
  }

  @override
  String get peopleSearchHint => 'Buscar corredores por nome';

  @override
  String get peopleClearSearchTooltip => 'Limpar busca';

  @override
  String get commonClearSearch => 'Limpar busca';

  @override
  String get commonDismiss => 'Dispensar';

  @override
  String get settingsDevicesRemoveOverride => 'Remover substituição';

  @override
  String get peopleSearchResultsHeader => 'Resultados da busca';

  @override
  String get peopleSuggestedHeader => 'Sugestões para você';

  @override
  String peopleEmptySearchTitle(Object query) {
    return 'Nenhum corredor corresponde a \"$query\"';
  }

  @override
  String get peopleEmptySearchBody =>
      'Tente um nome mais curto ou diferente. Os nomes de exibição são públicos; quem ainda não definiu um não aparece aqui.';

  @override
  String get peopleEmptySuggestionsTitle => 'Nenhuma sugestão ainda';

  @override
  String get peopleEmptySuggestionsBody =>
      'As sugestões vêm de pessoas dos clubes em que você entrou. Entre em um clube para começar a vê-las aqui.';

  @override
  String peoplePublicRunCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas públicas',
      one: '1 corrida pública',
    );
    return '$_temp0';
  }

  @override
  String peopleSharedClubsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clubes em comum',
      one: '1 clube em comum',
    );
    return '$_temp0';
  }

  @override
  String get peopleFallbackDisplayName => 'Corredor';

  @override
  String get peopleFollowingButton => 'Seguindo';

  @override
  String get peopleFollowButton => 'Seguir';

  @override
  String get readinessCardHeader => 'PRONTIDÃO';

  @override
  String get readinessBandHigh => 'alta';

  @override
  String get readinessBandModerate => 'moderada';

  @override
  String get readinessBandLow => 'baixa';

  @override
  String get missingMapTilesTitle =>
      'Usando tiles alternativos do OpenStreetMap';

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
  String get navLog => 'Registrar';

  @override
  String get logA11yLabel => 'Registrar uma atividade';

  @override
  String get navFitness => 'Fitness';

  @override
  String get navYou => 'Você';

  @override
  String get fitnessTabAll => 'Tudo';

  @override
  String get fitnessTabRuns => 'Corridas';

  @override
  String get fitnessTabGym => 'Academia';

  @override
  String get fitnessTabNutrition => 'Nutrição';

  @override
  String get fitnessRunsRoutes => 'Rotas';

  @override
  String get fitnessRunsPlans => 'Planos de treino';

  @override
  String get homeAskCoach => 'Pergunte ao seu treinador';

  @override
  String get homeAskCoachSubtitle =>
      'Dicas sobre suas corridas, academia e nutrição';

  @override
  String get youProfileTitle => 'Seu perfil';

  @override
  String get logSheetTitle => 'Registrar';

  @override
  String get logRun => 'Registrar corrida';

  @override
  String get logLift => 'Registrar musculação';

  @override
  String get logFood => 'Registrar comida';

  @override
  String get prefsKeepRunPrimary => 'Corrida como ação principal';

  @override
  String get prefsKeepRunPrimarySubtitle =>
      'Toque no botão central para iniciar uma corrida; mantenha pressionado para o menu completo';

  @override
  String get bodyMetricsTitle => 'Dados corporais';

  @override
  String get bodyMetricsTileSubtitle => 'Altura, peso e metas nutricionais';

  @override
  String get bodyMetricsConsentTitle => 'Armazenar dados de saúde';

  @override
  String get bodyMetricsConsentSubtitle =>
      'Altura e peso são dados de saúde sensíveis. Desative para apagá-los.';

  @override
  String get bodyMetricsHeight => 'Altura';

  @override
  String get bodyMetricsWeight => 'Peso';

  @override
  String get bodyMetricsActivityLevel => 'Nível de atividade';

  @override
  String get bodyMetricsGoal => 'Meta';

  @override
  String get bodyMetricsTargetsHint =>
      'Usado para estimar suas metas diárias de calorias e macros.';

  @override
  String get bodyMetricsConsentRequired =>
      'Ative o armazenamento de dados de saúde para salvar altura e peso.';

  @override
  String get bodyMetricsWithdrawTitle =>
      'Retirar o consentimento de dados de saúde?';

  @override
  String get bodyMetricsWithdrawBody =>
      'Isso apaga permanentemente sua altura salva e todo o seu histórico de peso. Não pode ser desfeito.';

  @override
  String get bodyMetricsWithdrawConfirm => 'Retirar e apagar';

  @override
  String get bodyMetricsSaved => 'Salvo';

  @override
  String bodyMetricsSaveFailed(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get safetyTitle => 'Contatos de segurança';

  @override
  String get safetyTileSubtitle =>
      'Envie um e-mail a um contato de confiança ao concluir uma corrida';

  @override
  String get safetyIntro =>
      'Um contato de segurança recebe um e-mail quando você conclui uma corrida — mesmo uma privada — para que alguém de confiança saiba que você voltou em segurança.';

  @override
  String get safetyAddLabel => 'E-mail do contato';

  @override
  String get safetyAddButton => 'Adicionar contato';

  @override
  String get safetyAdding => 'Adicionando…';

  @override
  String get safetyEmpty => 'Nenhum contato de segurança ainda.';

  @override
  String get safetyStatusPending => 'Pendente — aguardando a confirmação';

  @override
  String get safetyStatusConfirmed => 'Confirmado';

  @override
  String get safetyRemove => 'Remover';

  @override
  String get safetyRemoveConfirm => 'Remover este contato de segurança?';

  @override
  String safetyAddFailed(String error) {
    return 'Não foi possível adicionar o contato: $error';
  }

  @override
  String get safetyInvalidEmail => 'Digite um e-mail válido.';

  @override
  String get safetyAddedToast =>
      'Contato adicionado — enviamos um e-mail de confirmação.';

  @override
  String get safetyRemovedToast => 'Contato removido.';

  @override
  String get safetyIncomingTitle => 'Pedidos para você';

  @override
  String get safetyIncomingIntro =>
      'Estas pessoas pediram para você ser o contato de segurança delas. Confirme para receber um e-mail quando concluírem uma corrida.';

  @override
  String safetyIncomingFrom(String name) {
    return 'De $name';
  }

  @override
  String get safetyConfirm => 'Confirmar';

  @override
  String get safetyDecline => 'Recusar';

  @override
  String get safetyConfirmedToast => 'Agora você é contato de segurança.';

  @override
  String get safetyDeclinedToast => 'Pedido recusado.';

  @override
  String get safetyUnknownRunner => 'Um corredor do Threkir';

  @override
  String get activitySedentary =>
      'Maior parte sentado (trabalho de escritório)';

  @override
  String get activityLight => 'Levemente ativo (pouca movimentação diária)';

  @override
  String get activityModerate => 'Moderadamente ativo (muito tempo em pé)';

  @override
  String get activityVeryActive => 'Dia muito ativo (trabalho físico)';

  @override
  String get activityExtraActive =>
      'Extremamente ativo (trabalho físico pesado)';

  @override
  String get goalLose => 'Perder peso';

  @override
  String get goalMaintain => 'Manter peso';

  @override
  String get goalGain => 'Ganhar peso';

  @override
  String get homeTodaysLift => 'Treino de hoje';

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
  String get setupPageTitle => 'Configure sua conta';

  @override
  String get setupSkip => 'Pular configuração';

  @override
  String get setupSkipStep => 'Pular';

  @override
  String get setupBack => 'Voltar';

  @override
  String get setupContinue => 'Continuar';

  @override
  String get setupSaving => 'Salvando…';

  @override
  String get setupOpenDashboard => 'Abrir painel';

  @override
  String get setupWelcomeToast => 'Bem-vindo ao Threkir!';

  @override
  String setupSaveError(String message) {
    return 'Não foi possível salvar sua configuração: $message';
  }

  @override
  String get setupNameTitle => 'Como devemos te chamar?';

  @override
  String get setupNameHint =>
      'Este é o nome que outros corredores veem no seu perfil e nas corridas compartilhadas.';

  @override
  String get setupNameLabel => 'Nome de exibição';

  @override
  String get setupNamePlaceholder => 'ex.: Alex Corredor';

  @override
  String get setupUnitsTitle => 'Quilômetros ou milhas?';

  @override
  String get setupUnitsHint =>
      'Vamos usar isso em todos os lugares onde distâncias e ritmos aparecem. Você pode mudar quando quiser em Configurações.';

  @override
  String get setupUnitKm => 'Quilômetros';

  @override
  String get setupUnitKmSample => '5,0 km · 5:00 /km';

  @override
  String get setupUnitMi => 'Milhas';

  @override
  String get setupUnitMiSample => '3,1 mi · 8:03 /mi';

  @override
  String get setupGoalTitle => 'Qual é seu principal objetivo?';

  @override
  String get setupGoalHint =>
      'Vamos usar isso para sugerir um plano de treino adequado. Opcional — você pode pular.';

  @override
  String get setupGoalGeneralFitness => 'Manter a forma + saúde';

  @override
  String get setupGoalWeightLoss => 'Perder peso';

  @override
  String get setupGoal5k => 'Correr 5K';

  @override
  String get setupGoal10k => 'Correr 10K';

  @override
  String get setupGoalHalf => 'Correr uma meia maratona';

  @override
  String get setupGoalMarathon => 'Correr uma maratona';

  @override
  String get setupAboutTitle => 'Um pouco sobre você';

  @override
  String get setupAboutHint =>
      'Opcional. Ajuda a personalizar estimativas de ritmo e calorias. Você decide se compartilha dados de saúde.';

  @override
  String get setupGenderLabel => 'Gênero';

  @override
  String get setupGenderPreferNot => 'Prefiro não dizer';

  @override
  String get setupGenderFemale => 'Feminino';

  @override
  String get setupGenderMale => 'Masculino';

  @override
  String get setupGenderNonbinary => 'Não binário';

  @override
  String get setupDobLabel => 'Data de nascimento';

  @override
  String get setupDobNote =>
      'Usada para manter contas de menores de 18 anos fora da busca de pessoas e para resultados ajustados por idade, se você compartilhar dados de saúde.';

  @override
  String get setupDobPlaceholder => 'Toque para escolher';

  @override
  String get setupWeightLabel => 'Peso (kg)';

  @override
  String get setupWeightPlaceholder => 'ex.: 70';

  @override
  String get setupHealthConsent =>
      'Consinto que o Threkir use meu gênero e data de nascimento para personalizar estimativas de ritmo, frequência cardíaca e calorias (dados de saúde de categoria especial, RGPD art. 9).';

  @override
  String get setupPrivacyTitle => 'Quem vê suas corridas?';

  @override
  String get setupPrivacyHint =>
      'Escolha um padrão para novas corridas. Você pode alterá-lo a qualquer momento e substituí-lo em cada corrida.';

  @override
  String get setupNotificationsTitle => 'Fique por dentro';

  @override
  String get setupNotificationsHint =>
      'Escolha quantas notificações push deseja. Você pode ajustar isso depois em Configurações.';

  @override
  String get setupDoneTitle => 'Tudo pronto';

  @override
  String get setupDoneHint =>
      'É isso. Toque em “Abrir painel” para começar a correr.';

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
  String get runTreadmillModeLabel => 'Modo esteira';

  @override
  String runTreadmillModeSpeed(String speed) {
    return 'Esteira $speed';
  }

  @override
  String get runTreadmillLostReconnecting => 'Esteira perdida, reconectando…';

  @override
  String get runTreadmillReconnected => 'Esteira reconectada';

  @override
  String get runTreadmillLostFallback =>
      'Esteira perdida — distância voltando para o GPS';

  @override
  String get runTreadmillNotFound => 'Não foi possível conectar à esteira';

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
  String get historyRangeToday => 'Hoje';

  @override
  String get historyRangeWeek => 'Esta semana';

  @override
  String get historyRangeMonth => 'Últimos 30 dias';

  @override
  String get historyRangeYear => 'Este ano';

  @override
  String get historyRangeAll => 'Todo o histórico';

  @override
  String get historyRangeCustom => 'Personalizado…';

  @override
  String historyRangeFrom(String date) {
    return 'A partir de $date';
  }

  @override
  String historyRangeUntil(String date) {
    return 'Até $date';
  }

  @override
  String historyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get historyDateRangeTooltip => 'Período';

  @override
  String get historySortTooltip => 'Ordenar';

  @override
  String get historySortNewest => 'Mais recentes primeiro';

  @override
  String get historySortOldest => 'Mais antigas primeiro';

  @override
  String get historySortLongest => 'Maior distância';

  @override
  String get historySortFastest => 'Melhor ritmo';

  @override
  String historySyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizar $count corridas',
      one: 'Sincronizar $count corrida',
    );
    return '$_temp0';
  }

  @override
  String get historyRefreshTooltip => 'Atualizar da nuvem';

  @override
  String get historyOfflineTooltip => 'Offline';

  @override
  String historySelectionTitle(int count) {
    return '$count selecionadas';
  }

  @override
  String get historySelectAllTooltip => 'Selecionar tudo';

  @override
  String get historyClearSelectionTooltip => 'Limpar';

  @override
  String get historyDeleteTooltip => 'Excluir';

  @override
  String get historyCancelTooltip => 'Cancelar';

  @override
  String get historyAddRun => 'Adicionar corrida';

  @override
  String get historyAddRunTooltip => 'Adicionar uma corrida manualmente';

  @override
  String get historyLogTooltip => 'Registrar corrida, treino ou refeição';

  @override
  String historyLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get historyNoMatch => 'Nenhuma corrida corresponde a estes filtros';

  @override
  String get historyKindAll => 'Tudo';

  @override
  String get historyKindRuns => 'Corridas';

  @override
  String get historyKindLifts => 'Musculação';

  @override
  String get historyKindMeals => 'Refeições';

  @override
  String get historyViewAll => 'Ver tudo';

  @override
  String get historyToday => 'Hoje';

  @override
  String get historyYesterday => 'Ontem';

  @override
  String historySetCount(int n) {
    return '$n séries';
  }

  @override
  String historyKcal(int n) {
    return '$n kcal';
  }

  @override
  String get historyTimelineEmpty =>
      'Nada registrado nesta visualização ainda.';

  @override
  String get historyClearFilters => 'Limpar filtros';

  @override
  String get historyEmptyTitle => 'Ainda não há corridas';

  @override
  String get historyEmptyBody =>
      'Toque na aba Correr para iniciar sua primeira corrida';

  @override
  String get historyFilterAll => 'Todas';

  @override
  String get historySourceAll => 'Todas as fontes';

  @override
  String historySourceLabel(String source) {
    return 'Fonte: $source';
  }

  @override
  String get historySourceFilterTooltip => 'Filtrar por fonte';

  @override
  String get historySourceRecorded => 'Gravada';

  @override
  String get historySourceWatch => 'Relógio';

  @override
  String get historySourceStrava => 'Strava';

  @override
  String get historySourceParkrun => 'parkrun';

  @override
  String get historySourceHealthKit => 'HealthKit';

  @override
  String get historySourceHealthConnect => 'Health Connect';

  @override
  String get historyRangePickerTitle => 'Selecionar datas';

  @override
  String get historyRangeStart => 'Início';

  @override
  String get historyRangeEnd => 'Fim';

  @override
  String get historyRangeTapDate => 'Toque em uma data';

  @override
  String get historyRangeApply => 'Aplicar';

  @override
  String get historyRangeClear => 'Limpar';

  @override
  String get historyPrevMonth => 'Mês anterior';

  @override
  String get historyNextMonth => 'Próximo mês';

  @override
  String get historyPrevYear => 'Ano anterior';

  @override
  String get historyNextYear => 'Próximo ano';

  @override
  String historyDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count corridas?',
      one: 'Excluir $count corrida?',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody => 'Isso não pode ser desfeito.';

  @override
  String get historyCancel => 'Cancelar';

  @override
  String get historyDelete => 'Excluir';

  @override
  String get historyQueuedToSync => 'Na fila para sincronizar';

  @override
  String get historySignInToSync =>
      'Entre nas configurações para sincronizar as corridas';

  @override
  String get historyRefreshFailed =>
      'Não foi possível atualizar — verifique sua conexão';

  @override
  String get historyLoadMoreFailed => 'Não foi possível carregar mais corridas';

  @override
  String historySyncPartial(int synced, int total, String error) {
    return '$synced/$total sincronizadas. Erro: $error';
  }

  @override
  String historySyncTrackFailed(int count) {
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
  String historySyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Todas as $count corridas sincronizadas',
      one: '$count corrida sincronizada',
    );
    return '$_temp0';
  }

  @override
  String historyDeletePartial(int deleted, int queued) {
    return '$deleted excluídas; $queued na fila — será tentado novamente quando você estiver online.';
  }

  @override
  String historyDeleteDone(int count) {
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
  String get runDetailReportRun => 'Denunciar corrida';

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
  String get runDetailStatGradeAdjPace => 'Ritmo ajustado';

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
  String runDetailRouteSaveFailed(String name) {
    return 'Não foi possível salvar \"$name\" como rota.';
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
  String get runDetailMatchOffline =>
      'Offline — exibindo o trajeto bruto, tentaremos novamente';

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
  String get routeBuilderClearConfirmTitle => 'Limpar esta rota?';

  @override
  String get routeBuilderClearConfirmBody =>
      'Todos os pontos serão removidos. Isso não pode ser desfeito.';

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
  String get routeDetailShareAsGpxMarkers =>
      'Compartilhar como GPX + marcadores';

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
  String get routeDetailDescribe => 'Descrever esta rota';

  @override
  String get routeDetailDescribing => 'Descrevendo…';

  @override
  String get routeDetailAiAttribution =>
      'Escrito por IA a partir dos dados da rota';

  @override
  String get routeDetailDescribeFailed =>
      'Não foi possível gerar uma descrição. Tente novamente.';

  @override
  String get routeDetailEnhanceUpgradeHint =>
      'Descrições com IA são um recurso Pro. Faça upgrade para aprimorar.';

  @override
  String get routeDetailDescShapeLoop => 'em circuito';

  @override
  String get routeDetailDescShapeOutAndBack => 'ida e volta';

  @override
  String get routeDetailDescShapePointToPoint => 'ponto a ponto';

  @override
  String get routeDetailDescSurfaceRoad => 'de asfalto';

  @override
  String get routeDetailDescSurfaceTrail => 'de trilha';

  @override
  String get routeDetailDescSurfaceMixed => 'de superfície mista';

  @override
  String get routeDetailDescElevFlat => 'plana';

  @override
  String get routeDetailDescElevRolling => 'levemente ondulada';

  @override
  String get routeDetailDescElevHilly => 'com subidas';

  @override
  String get routeDetailDescElevMountainous => 'montanhosa';

  @override
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  ) {
    return '$name é uma rota $shape $surface de $distance.';
  }

  @override
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  ) {
    return '$name é uma rota $shape de $distance.';
  }

  @override
  String routeDetailDescClimb(String gain, String elevation, String perKm) {
    return 'Tem $gain de ganho de elevação — $elevation, cerca de $perKm por km.';
  }

  @override
  String get routeDetailDescFlat =>
      'Tem pouca ou nenhuma variação de elevação.';

  @override
  String routeDetailDescPerKm(int m) {
    return '$m m';
  }

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
  String routeDetailRateStars(int n) {
    return 'Definir a avaliação como $n de 5';
  }

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
  String routeDetailTagRemoveFailed(String error) {
    return 'Não foi possível remover a etiqueta: $error';
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
  String get runHeatmapTitle => 'Seu mapa de calor';

  @override
  String get runHeatmapTooltip => 'Mapa de calor de corridas';

  @override
  String get runHeatmapLoading => 'Carregando suas corridas…';

  @override
  String runHeatmapLoadingProgress(int n, int total) {
    return 'Carregando suas corridas… $n/$total';
  }

  @override
  String get runHeatmapEmptyTitle => 'Nenhuma corrida mapeada ainda';

  @override
  String get runHeatmapEmptyBody =>
      'Grave ou importe corridas com trajetos de GPS e elas vão aparecer aqui.';

  @override
  String get runHeatmapLegendTitle => 'Seu mapa de calor';

  @override
  String runHeatmapLegendSummaryOne(int n) {
    return '$n corrida mapeada — mais brilhante onde você corre mais.';
  }

  @override
  String runHeatmapLegendSummaryMany(int n) {
    return '$n corridas mapeadas — mais brilhante onde você corre mais.';
  }

  @override
  String get runHeatmapScaleLess => 'menos';

  @override
  String get runHeatmapScaleMore => 'mais';

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

  @override
  String get feedTitle => 'Feed';

  @override
  String get feedFindPeople => 'Encontrar pessoas';

  @override
  String get feedActivityAll => 'Tudo';

  @override
  String get feedActivityRun => 'Corrida';

  @override
  String get feedActivityWalk => 'Caminhada';

  @override
  String get feedActivityCycle => 'Ciclismo';

  @override
  String get feedActivityHike => 'Trilha';

  @override
  String get feedActivityLift => 'Força';

  @override
  String get feedLiftSetsLabel => 'Séries';

  @override
  String get feedLiftVolume => 'Volume';

  @override
  String get feedLiftUntitled => 'Treino';

  @override
  String get feedLoadMore => 'Carregar mais';

  @override
  String feedLoadMoreFailed(String error) {
    return 'Não foi possível carregar mais: $error';
  }

  @override
  String get feedLoadError => 'Não foi possível carregar o feed.';

  @override
  String get feedEveryoneYouFollow => 'Todos que você segue';

  @override
  String get feedRunnerFallback => 'Corredor';

  @override
  String get relativeJustNow => 'Agora mesmo';

  @override
  String relativeMinutesAgo(int count) {
    return 'há $count min';
  }

  @override
  String relativeHoursAgo(int count) {
    return 'há $count h';
  }

  @override
  String get relativeYesterday => 'Ontem';

  @override
  String relativeDaysAgo(int count) {
    return 'há $count d';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count semanas',
      one: 'há 1 semana',
    );
    return '$_temp0';
  }

  @override
  String get coachArchiveToday => 'Hoje';

  @override
  String coachArchiveDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count dias',
    );
    return '$_temp0';
  }

  @override
  String get feedLast14Days => 'Últimos 14 dias';

  @override
  String get feedEmptyTitle => 'Seu feed está vazio';

  @override
  String get feedEmptyBody =>
      'Siga outros corredores para ver as corridas públicas deles aqui.';

  @override
  String get feedNoMatchesTitle => 'Nenhum resultado';

  @override
  String get feedNoMatchesBody =>
      'Nada corresponde aos filtros atuais nos últimos 14 dias.';

  @override
  String get feedNoActivityTitle => 'Nenhuma atividade recente';

  @override
  String get feedNoActivityBody =>
      'Ninguém que você segue registrou uma corrida pública nos últimos 14 dias.';

  @override
  String get feedClearFilters => 'Limpar filtros';

  @override
  String feedKudosUpdateFailed(String error) {
    return 'Não foi possível atualizar os kudos: $error';
  }

  @override
  String get profileTitle => 'Perfil';

  @override
  String get profileRunnerFallback => 'Corredor';

  @override
  String get profileTabRuns => 'Corridas';

  @override
  String get profileTabFollowers => 'Seguidores';

  @override
  String get profileTabFollowing => 'Seguindo';

  @override
  String get profileTabNotifications => 'Notificações';

  @override
  String get profileReportUser => 'Denunciar usuário';

  @override
  String get profileUnblock => 'Desbloquear este perfil';

  @override
  String get profileBlock => 'Bloquear este perfil';

  @override
  String get profileLoadError => 'Não foi possível carregar o perfil.';

  @override
  String get profileNotFound => 'Perfil não encontrado.';

  @override
  String profileFollowStats(int followers, int following) {
    String _temp0 = intl.Intl.pluralLogic(
      followers,
      locale: localeName,
      other: '$followers seguidores',
      one: '$followers seguidor',
    );
    return '$_temp0 · seguindo $following';
  }

  @override
  String get profileFollowing => 'Seguindo';

  @override
  String get profileFollow => 'Seguir';

  @override
  String get profileRunsEmptySelf =>
      'Você ainda não compartilhou nenhuma corrida.';

  @override
  String get profileRunsEmptyOther => 'Nenhuma corrida pública ainda.';

  @override
  String get profileFollowersEmpty => 'Nenhum seguidor ainda.';

  @override
  String get profileFollowingEmpty => 'Você ainda não segue ninguém.';

  @override
  String profileLoadMore(int count) {
    return 'Carregar mais $count';
  }

  @override
  String get profileLoadMoreFollowersFailed =>
      'Não foi possível carregar mais seguidores';

  @override
  String get profileLoadMoreFollowingFailed =>
      'Não foi possível carregar mais seguidos';

  @override
  String profileFollowUpdateFailed(String error) {
    return 'Não foi possível atualizar o seguimento: $error';
  }

  @override
  String profileBlockConfirmTitle(String name) {
    return 'Bloquear $name?';
  }

  @override
  String get profileBlockConfirmBody =>
      'Essa pessoa não poderá seguir você, dar kudos às suas corridas nem comentá-las. Qualquer seguimento existente entre vocês em qualquer direção será removido. Você pode desbloquear nesta página a qualquer momento.';

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
    return 'Não foi possível bloquear: $error';
  }

  @override
  String profileUnblocked(String name) {
    return '$name desbloqueado';
  }

  @override
  String profileUnblockFailed(String error) {
    return 'Não foi possível desbloquear: $error';
  }

  @override
  String get profileNotifAll => 'Todas';

  @override
  String get profileNotifUnread => 'Não lidas';

  @override
  String get profileMarkAllRead => 'Marcar todas como lidas';

  @override
  String profileMarkAllReadFailed(String error) {
    return 'Não foi possível marcar todas como lidas: $error';
  }

  @override
  String get profileNotifsCaughtUp => 'Você está em dia.';

  @override
  String get profileNotifsEmpty => 'Nenhuma notificação ainda.';

  @override
  String get profileDismiss => 'Dispensar';

  @override
  String profileDismissFailed(String error) {
    return 'Não foi possível dispensar: $error';
  }

  @override
  String get profileNotifSomeone => 'Alguém';

  @override
  String get profileNotifYourRun => 'sua corrida';

  @override
  String profileNotifKudos(String name, String dist) {
    return '$name deu kudos à sua $dist';
  }

  @override
  String profileNotifComment(String name, String dist) {
    return '$name comentou na sua $dist';
  }

  @override
  String profileNotifCommentReply(String name) {
    return '$name respondeu ao seu comentário';
  }

  @override
  String profileNotifFollow(String name) {
    return '$name começou a seguir você';
  }

  @override
  String profileNotifEventRsvpTitled(String name, String title) {
    return '$name confirmou presença no seu evento \"$title\"';
  }

  @override
  String profileNotifEventRsvp(String name) {
    return '$name confirmou presença no seu evento';
  }

  @override
  String profileNotifPlanUpdate(String name) {
    return '$name atualizou seu plano de treino';
  }

  @override
  String profileNotifMessage(String name) {
    return '$name enviou uma mensagem para você';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$name publicou em $club';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$name publicou em um clube do qual você participa';
  }

  @override
  String profileNotifRunCompletedDist(String name, String dist) {
    return '$name concluiu uma corrida de $dist';
  }

  @override
  String profileNotifRunCompleted(String name) {
    return '$name concluiu uma corrida';
  }

  @override
  String profileNotifGeneric(String name) {
    return '$name interagiu com sua atividade';
  }

  @override
  String get socialTabFeed => 'Feed';

  @override
  String get socialTabPeople => 'Pessoas';

  @override
  String get socialTabClubs => 'Clubes';

  @override
  String get socialTabRoutes => 'Rotas';

  @override
  String get socialTabDiscover => 'Descobrir';

  @override
  String get discoverSearchPlaceholder =>
      'Buscar yoga, pilates, HIIT, clubes de corrida…';

  @override
  String get discoverActivityAll => 'Todas as atividades';

  @override
  String get discoverCadenceLabel => 'Frequência';

  @override
  String get discoverCadenceAny => 'Qualquer frequência';

  @override
  String get discoverOneOff => 'Único';

  @override
  String get discoverWeekly => 'Semanal';

  @override
  String get discoverBiweekly => 'A cada 2 semanas';

  @override
  String get discoverMonthly => 'Mensal';

  @override
  String get discoverDayLabel => 'Dia';

  @override
  String get discoverDayAny => 'Qualquer dia';

  @override
  String get discoverDayMon => 'Seg';

  @override
  String get discoverDayTue => 'Ter';

  @override
  String get discoverDayWed => 'Qua';

  @override
  String get discoverDayThu => 'Qui';

  @override
  String get discoverDayFri => 'Sex';

  @override
  String get discoverDaySat => 'Sáb';

  @override
  String get discoverDaySun => 'Dom';

  @override
  String get discoverTimeLabel => 'Hora do dia';

  @override
  String get discoverTimeAny => 'Qualquer hora';

  @override
  String get discoverMorning => 'Manhã';

  @override
  String get discoverAfternoon => 'Tarde';

  @override
  String get discoverEvening => 'Noite';

  @override
  String get discoverPriceLabel => 'Preço';

  @override
  String get discoverPriceAny => 'Qualquer preço';

  @override
  String get discoverFree => 'Grátis';

  @override
  String get discoverPaid => 'Pago';

  @override
  String get discoverLoading => 'Buscando…';

  @override
  String get discoverEmpty =>
      'Nenhuma atividade pública corresponde a esses filtros ainda.';

  @override
  String get discoverSearchFailed =>
      'Não foi possível carregar as atividades. Verifique sua conexão e tente novamente.';

  @override
  String get clubsTitle => 'Clubes';

  @override
  String get clubsFindPeople => 'Encontrar pessoas';

  @override
  String get clubsNewClub => 'Novo clube';

  @override
  String get clubsTabBrowse => 'Explorar';

  @override
  String get clubsTabMine => 'Meus clubes';

  @override
  String get clubsJoinWithCode => 'Entrar com código de convite';

  @override
  String get clubsSearchHint => 'Pesquisar por nome ou local';

  @override
  String get clubsTimeoutError =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String get clubsLoadError =>
      'Não foi possível carregar os clubes. Toque em Tentar novamente.';

  @override
  String get clubsBadgePrivate => 'PRIVADO';

  @override
  String clubsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros',
      one: '$count membro',
    );
    return '$_temp0';
  }

  @override
  String get clubsEmptyBrowseTitle =>
      'Nenhum clube corresponde a essa pesquisa.';

  @override
  String get clubsEmptyMineTitle => 'Você ainda não entrou em nenhum clube.';

  @override
  String get clubsEmptyBrowseBody => 'Tente outro nome ou local.';

  @override
  String get clubsEmptyMineBody => 'Vá em Explorar para encontrar um.';

  @override
  String get clubDetailTabFeed => 'Feed';

  @override
  String get clubDetailTabEvents => 'Eventos';

  @override
  String get clubDetailTabMembers => 'Membros';

  @override
  String get clubDetailTabRoutes => 'Rotas';

  @override
  String get clubDetailTabTemplates => 'Modelos';

  @override
  String get clubDetailTabPhotos => 'Fotos';

  @override
  String get clubDetailReportClub => 'Denunciar clube';

  @override
  String get clubDetailReportPost => 'Denunciar esta publicação';

  @override
  String get clubDetailLoadFailedTitle =>
      'Não foi possível carregar este clube.';

  @override
  String get clubDetailLoadFailedBody =>
      'Pode ter sido removido, ou sua sessão precisa ser atualizada. Puxe para tentar novamente, ou saia e entre novamente em Configurações.';

  @override
  String get clubDetailRetry => 'Tentar novamente';

  @override
  String get clubDetailTimeoutError =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String get clubDetailRequestSent =>
      'Solicitação enviada aos administradores.';

  @override
  String clubDetailLeaveTitle(String club) {
    return 'Sair de $club?';
  }

  @override
  String get clubDetailCancel => 'Cancelar';

  @override
  String get clubDetailLeave => 'Sair';

  @override
  String clubDetailReplyFailed(String error) {
    return 'Não foi possível publicar a resposta: $error';
  }

  @override
  String get clubDetailMemberFallback => 'Membro';

  @override
  String get clubDetailRequestPending => 'Solicitação pendente';

  @override
  String get clubDetailInviteOnly => 'Apenas com convite';

  @override
  String get clubDetailRequest => 'Solicitar';

  @override
  String get clubDetailJoin => 'Entrar';

  @override
  String get clubDetailOwner => 'Proprietário';

  @override
  String get clubDetailNextEvent => 'PRÓXIMO EVENTO';

  @override
  String clubDetailGoingCount(int count) {
    return '$count confirmados';
  }

  @override
  String get clubDetailNoPostsMember =>
      'Nenhuma publicação ainda. Compartilhe uma novidade com os membros.';

  @override
  String get clubDetailNoPosts => 'Nenhuma novidade ainda.';

  @override
  String get clubDetailShareUpdateHint => 'Compartilhe uma novidade…';

  @override
  String get clubDetailPost => 'Publicar';

  @override
  String get clubDetailReply => 'Responder';

  @override
  String clubDetailHideReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ocultar $count respostas',
      one: 'Ocultar $count resposta',
    );
    return '$_temp0';
  }

  @override
  String clubDetailShowReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count respostas',
      one: '$count resposta',
    );
    return '$_temp0';
  }

  @override
  String clubDetailReplyAuthorLine(String name, String time) {
    return '$name · $time';
  }

  @override
  String get clubDetailWriteReplyHint => 'Escreva uma resposta…';

  @override
  String get clubDetailSend => 'Enviar';

  @override
  String get clubDetailNoEventsAdmin =>
      'Nenhum evento futuro. Toque em Criar para adicionar um.';

  @override
  String get clubDetailNoEvents => 'Nenhum evento futuro.';

  @override
  String get clubDetailCreateEvent => 'Criar evento';

  @override
  String get clubDetailGoing => 'Confirmado';

  @override
  String clubDetailApproveFailed(String error) {
    return 'Falha ao aprovar: $error';
  }

  @override
  String clubDetailDenyFailed(String error) {
    return 'Falha ao recusar: $error';
  }

  @override
  String clubDetailPendingRequests(int count) {
    return 'Solicitações pendentes ($count)';
  }

  @override
  String clubDetailUserShort(String id) {
    return 'Usuário $id…';
  }

  @override
  String get clubDetailDeny => 'Recusar';

  @override
  String get clubDetailApprove => 'Aprovar';

  @override
  String clubDetailMemberCountLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros.',
      one: '$count membro.',
    );
    return '$_temp0';
  }

  @override
  String clubDetailRouteSaved(String name) {
    return '\"$name\" salva';
  }

  @override
  String get clubDetailBuildRoute => 'Criar rota para este clube';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'Nenhuma rota ainda. Crie o percurso oficial acima, ou transfira uma das suas rotas pessoais na tela de detalhes da rota.';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'Nenhuma rota ainda. Os administradores podem transferir uma de suas rotas pessoais na tela de detalhes da rota.';

  @override
  String get clubDetailRoutesEmpty =>
      'Nenhuma rota compartilhada com este clube ainda.';

  @override
  String get clubDetailTemplateAdded => 'Modelo adicionado aos seus planos.';

  @override
  String clubDetailAdoptFailed(String error) {
    return 'Falha ao adotar: $error';
  }

  @override
  String get clubDetailNoTemplatesAdmin =>
      'Nenhum modelo ainda. Publique um dos seus planos na página de detalhes.';

  @override
  String get clubDetailNoTemplates =>
      'Nenhum modelo de plano para este clube ainda.';

  @override
  String get clubDetailAdopt => 'Adotar';

  @override
  String get clubDetailSessionTemplatesTitle => 'Modelos de sessão';

  @override
  String get clubDetailSessionAdopted => 'Sessão adicionada aos seus planos.';

  @override
  String get clubDetailGymRoutineTemplatesTitle =>
      'Modelos de rotina de academia';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'Os membros podem adotar uma rotina de academia do clube nas próprias rotinas. As edições em uma cópia não se propagam para o modelo.';

  @override
  String get clubDetailGymRoutineAdopted =>
      'Rotina adicionada às suas rotinas de academia.';

  @override
  String clubDetailRoutineExerciseCount(int n) {
    return '$n exercícios';
  }

  @override
  String get eventNotFound => 'Evento não encontrado.';

  @override
  String get eventLoadError =>
      'Não foi possível carregar este evento. Toque em Tentar novamente.';

  @override
  String get eventTimeoutError =>
      'A conexão expirou. Verifique sua rede e tente novamente.';

  @override
  String eventDurationMin(int minutes) {
    return '· $minutes min';
  }

  @override
  String eventGetDirectionsTo(String label) {
    return 'Como chegar a $label';
  }

  @override
  String get eventGetDirections => 'Como chegar';

  @override
  String get eventCouldNotOpenMaps => 'Não foi possível abrir os mapas.';

  @override
  String get eventPickOccurrence => 'ESCOLHA UMA OCORRÊNCIA';

  @override
  String get eventTargetPace => 'Ritmo alvo';

  @override
  String get eventClassSessionEyebrow => 'AULA';

  @override
  String get eventResultSubmitted => 'Resultado enviado.';

  @override
  String eventSubmitFailed(String error) {
    return 'Falha ao enviar: $error';
  }

  @override
  String eventRaceControlFailed(String error) {
    return 'Falha no controle da corrida: $error';
  }

  @override
  String eventAttendees(int count) {
    return 'PARTICIPANTES ($count)';
  }

  @override
  String get eventNoRsvps => 'Nenhuma confirmação ainda — seja o primeiro.';

  @override
  String get eventAttendeeMember => 'Membro';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventMarkAttended => 'Marcar como presente';

  @override
  String get eventMarkNoShow => 'Marcar como ausente';

  @override
  String get eventAttendanceAttended => 'Presente';

  @override
  String get eventAttendanceNoShow => 'Ausente';

  @override
  String get eventAttendanceFailed =>
      'Não foi possível atualizar a presença. Tente novamente.';

  @override
  String get eventRsvpFailed =>
      'Não foi possível atualizar sua confirmação. Tente novamente.';

  @override
  String get eventRsvpGoing => 'Eu vou';

  @override
  String get eventRsvpMaybe => 'Talvez';

  @override
  String get eventRsvpDeclined => 'Não posso ir';

  @override
  String get eventRaceArmed => 'Armado — aguardando o GO';

  @override
  String get eventRaceRunning => 'Em andamento — ao vivo';

  @override
  String get eventRaceFinished => 'Concluído';

  @override
  String get eventRaceCancelled => 'Cancelado';

  @override
  String get eventRaceNotArmed => 'Não armado';

  @override
  String get eventRaceControlLabel => 'CONTROLE DA CORRIDA';

  @override
  String get eventRaceAutoApprove =>
      'Aprovar automaticamente os tempos enviados';

  @override
  String get eventRaceArm => 'Armar corrida';

  @override
  String get eventRaceArmedHint =>
      'Toque em Disparar o Go quando a corrida começar. Os relógios dos participantes mostram agora o aviso de armado.';

  @override
  String get eventRaceFireGo => 'Disparar o Go';

  @override
  String get eventRaceCancel => 'Cancelar';

  @override
  String eventRaceStartedAt(String time) {
    return 'Iniciada às $time';
  }

  @override
  String get eventRaceEnd => 'Encerrar corrida';

  @override
  String get eventRaceCancelRace => 'Cancelar corrida';

  @override
  String get eventRaceEndConfirmBody =>
      'Encerrar a corrida? Isso finaliza o evento para todos os corredores e não pode ser desfeito.';

  @override
  String get eventRaceCancelConfirmBody =>
      'Cancelar a corrida? Isso aborta o evento para todos os corredores e não pode ser desfeito.';

  @override
  String get eventUpdatePosted => 'Novidade publicada no feed do clube.';

  @override
  String eventPostUpdateFailed(String error) {
    return 'Não foi possível publicar a novidade: $error';
  }

  @override
  String get eventPostUpdateLabel => 'PUBLICAR UMA NOVIDADE';

  @override
  String get eventUpdateHint =>
      'Decisão por causa do tempo? Encontro em outro local?';

  @override
  String get eventPostUpdate => 'Publicar novidade';

  @override
  String get eventResultsTitle => 'Resultados';

  @override
  String get eventRemoveMine => 'Remover o meu';

  @override
  String get eventRemoveResultTitle => 'Remover seu resultado?';

  @override
  String get eventRemoveResultBody =>
      'Seu tempo de chegada enviado será removido da classificação deste evento. Você pode enviar novamente mais tarde.';

  @override
  String get eventRemoveResultConfirm => 'Remover resultado';

  @override
  String eventRemoveResultFailed(String error) {
    return 'Não foi possível remover seu resultado: $error';
  }

  @override
  String get eventSubmitMyTime => 'Enviar meu tempo';

  @override
  String get eventSubmitting => 'Enviando…';

  @override
  String get eventNoResults =>
      'Nenhum resultado ainda. Envie seu tempo após o evento e os outros verão aqui.';

  @override
  String get eventResultRunner => 'Corredor';

  @override
  String get eventResultYou => '(você)';

  @override
  String get eventSubmitTimeTitle => 'Envie seu tempo';

  @override
  String get eventSubmitTimeSubtitle =>
      'Escolha uma corrida para anexar, ou registre um DNF / DNS.';

  @override
  String get eventNoRecentRuns =>
      'Nenhuma corrida recente encontrada. Registre uma corrida primeiro e volte.';

  @override
  String get eventRecordDnf => 'Registrar DNF';

  @override
  String get eventRecordDns => 'Registrar DNS';

  @override
  String get eventSubmitCancel => 'Cancelar';

  @override
  String get liveSpectatorTitle => 'Acompanhamento ao vivo';

  @override
  String get liveSpectatorConnectError => 'Não foi possível conectar.';

  @override
  String get liveSpectatorWaiting =>
      'Aguardando o corredor enviar o primeiro sinal…';

  @override
  String get liveSpectatorBadgeLive => 'Ao vivo';

  @override
  String get liveSpectatorBadgeIdle => 'Parado';

  @override
  String get liveSpectatorBadgeConnecting => 'Conectando';

  @override
  String get liveSpectatorBadgeStale => 'Atrasado';

  @override
  String get liveSpectatorBadgeApproximate => 'Aproximado';

  @override
  String get liveSpectatorApproximateSub =>
      'Visto pela última vez perto daqui — aproximado';

  @override
  String get liveSpectatorBadgeFinished => 'Concluído';

  @override
  String get liveSpectatorBadgeDnf => 'DNF';

  @override
  String get liveUpdatedNow => 'Atualizado agora mesmo';

  @override
  String liveUpdatedSeconds(int n) {
    return 'Atualizado há ${n}s';
  }

  @override
  String liveUpdatedMinutes(int n) {
    return 'Atualizado há $n min';
  }

  @override
  String liveUpdatedHours(int n) {
    return 'Atualizado há $n h';
  }

  @override
  String liveUpdatedDays(int n) {
    return 'Atualizado há $n d';
  }

  @override
  String get liveCutoffTitle => 'Próximo corte';

  @override
  String liveCutoffToGo(String distance) {
    return 'Faltam $distance';
  }

  @override
  String liveCutoffEta(String eta) {
    return 'Chegada prevista $eta';
  }

  @override
  String liveCutoffAhead(String margin) {
    return '$margin de margem';
  }

  @override
  String liveCutoffBehind(String margin) {
    return '$margin de atraso';
  }

  @override
  String get liveCutoffWaitingSignal =>
      'Aguardando um sinal recente para prever a chegada';

  @override
  String get plansTitle => 'Planos de treino';

  @override
  String get plansNewPlan => 'Novo plano';

  @override
  String plansDeleteTitle(String name) {
    return 'Excluir \"$name\"?';
  }

  @override
  String get plansDeleteBody => 'Todas as semanas e treinos serão removidos.';

  @override
  String get plansCancel => 'Cancelar';

  @override
  String get plansDelete => 'Excluir';

  @override
  String get plansAbandon => 'Abandonar';

  @override
  String plansAbandonTitle(String name) {
    return 'Abandonar \"$name\"?';
  }

  @override
  String get plansAbandonBody => 'Depois você pode criar um novo plano.';

  @override
  String plansActionFailed(String error) {
    return 'Não foi possível atualizar o plano: $error';
  }

  @override
  String plansDaysPerWeek(int count) {
    return '$count dias/sem.';
  }

  @override
  String get plansSignInTitle => 'Entre para usar os planos de treino';

  @override
  String get plansSignInBody =>
      'Os planos sincronizam com a sua conta e acompanham você em todos os dispositivos. Vá em Configurações → Entrar para conectar.';

  @override
  String get plansEmptyTitle => 'Nenhum plano ainda.';

  @override
  String get plansEmptyBody =>
      'Escolha uma prova-alvo e montaremos as semanas para você.';

  @override
  String get plansTimeoutError =>
      'Tempo de conexão esgotado. Verifique sua rede e tente novamente.';

  @override
  String get plansLoadError =>
      'Não foi possível carregar os planos de treino. Toque em tentar novamente.';

  @override
  String get planNewTitle => 'Novo plano';

  @override
  String get planNewNameLabel => 'Nome do plano';

  @override
  String get planNewNameHint => 'ex. Meia maratona de outono';

  @override
  String get planNewGoalRace => 'Prova-alvo';

  @override
  String get planNewStartDate => 'Data de início';

  @override
  String get planNewDaysPerWeek => 'Dias por semana';

  @override
  String planNewDaysOption(int count) {
    return '$count dias';
  }

  @override
  String get planNewGoalTimeSection => 'Tempo-alvo · opcional';

  @override
  String get planNewBeginnerTitle =>
      'Começando a correr? Use um plano de caminhada-corrida';

  @override
  String get planNewBeginnerSubtitle =>
      'Um cronograma suave no estilo C25K de intervalos cronometrados de corrida/caminhada que evolui até uma corrida contínua. Substitui o ritmo do tempo-alvo.';

  @override
  String get planNewRecent5kSection => 'Tempo recente de 5K · opcional';

  @override
  String get planNewRecent5kHelp =>
      'Baseie os ritmos em um resultado real em vez da meta. Usa a equivalência de Riegel para projetar até a distância-alvo.';

  @override
  String get planNewRecent5kConfirm =>
      'É um tempo que eu conseguiria correr hoje — reflete meu condicionamento atual.';

  @override
  String get planNewRecent5kWarning =>
      'Até você confirmar, os ritmos permanecem na estimativa conservadora baseada na meta. Basear-se em um resultado antigo pode prescrever ritmos rápidos demais para quem está voltando.';

  @override
  String get planNewOverrideHint => 'Substituir o total de semanas';

  @override
  String planNewOverrideLabel(int count) {
    return 'Substituir semanas (padrão: $count)';
  }

  @override
  String get planNewCancel => 'Cancelar';

  @override
  String get planNewCreate => 'Criar plano';

  @override
  String get planNewCreating => 'Criando…';

  @override
  String get planNewPreviewTitle => 'Prévia';

  @override
  String get planNewPaceEasy => 'Leve';

  @override
  String get planNewPaceMarathon => 'Maratona';

  @override
  String get planNewPaceTempo => 'Tempo';

  @override
  String get planNewPaceInterval => 'Intervalo';

  @override
  String get planNewPaceRep => 'Repetição';

  @override
  String get planNewPacesFallback =>
      'Ritmos estimados — adicione uma corrida recente ou um tempo-alvo para metas personalizadas.';

  @override
  String planNewVdot(String value) {
    return 'VDOT de Daniels: $value';
  }

  @override
  String get planNewWeekOutline => 'Resumo das semanas';

  @override
  String planNewMoreWeeks(int count) {
    return '+ $count semanas a mais';
  }

  @override
  String planNewSessions(int count) {
    return '$count sessões';
  }

  @override
  String get planNewTemplateTitle => 'Começar com um modelo do clube';

  @override
  String get planNewTemplateSubtitle =>
      'Adote um plano que um clube ao qual você pertence publicou. Ele é clonado na sua conta com a data de início abaixo — edite como qualquer outro plano.';

  @override
  String get planNewTemplateButton => 'Ver modelos';

  @override
  String get planNewTemplateCloning => 'Adotando…';

  @override
  String planNewTemplateCloneFailed(String error) {
    return 'Não foi possível adotar esse modelo: $error';
  }

  @override
  String get planNewTemplatePickerTitle => 'Escolha um modelo';

  @override
  String get planNewTemplatePickerCancel => 'Cancelar';

  @override
  String get planLibraryTitle => 'Biblioteca pública de planos';

  @override
  String get planLibrarySubheading =>
      'Planos publicados por outros corredores. Clone um na sua conta para começar a treinar.';

  @override
  String get planLibrarySearchHint => 'Buscar planos por nome';

  @override
  String get planLibraryLoadError =>
      'Não foi possível carregar a biblioteca. Tente novamente.';

  @override
  String get planLibraryRetry => 'Tentar novamente';

  @override
  String get planLibraryEmpty => 'Ainda não há planos publicados.';

  @override
  String planLibraryEmptySearch(String query) {
    return 'Nenhum plano corresponde a “$query”.';
  }

  @override
  String planLibraryByAuthor(String author) {
    return 'por $author';
  }

  @override
  String get planLibraryAnonymous => 'um corredor';

  @override
  String planLibraryWeeks(int weeks) {
    return '$weeks semanas';
  }

  @override
  String planLibraryDaysPerWeek(int days) {
    return '$days×/semana';
  }

  @override
  String get planLibraryClone => 'Clonar nos meus planos';

  @override
  String get planLibraryCloning => 'Clonando…';

  @override
  String get planLibraryCloneSuccess => 'Plano clonado.';

  @override
  String planLibraryCloneFailed(String error) {
    return 'Falha ao clonar: $error';
  }

  @override
  String get planLibraryStartDate => 'Data de início';

  @override
  String get planLibraryNotFound =>
      'Este plano não está mais na biblioteca pública.';

  @override
  String get planLibraryPreviewWeeks => 'Semanas';

  @override
  String planLibraryPreviewWeek(int n) {
    return 'Semana $n';
  }

  @override
  String get planDetailPublishLibraryLabel => 'Biblioteca pública de planos';

  @override
  String get planDetailPublishLibrary => 'Publicar na biblioteca';

  @override
  String get planDetailPublishLibraryHint =>
      'Compartilhe uma cópia deste plano para que qualquer pessoa possa cloná-lo. Seus dados de condicionamento não são compartilhados.';

  @override
  String get planDetailPublishLibrarySuccess =>
      'Plano publicado na biblioteca pública. Seu plano pessoal não muda.';

  @override
  String planDetailPublishLibraryFailed(String error) {
    return 'Falha ao publicar: $error';
  }

  @override
  String get planDetailUnpublishLibrary => 'Remover';

  @override
  String get planDetailUnpublishSuccess => 'Removido da biblioteca pública.';

  @override
  String planDetailUnpublishFailed(String error) {
    return 'Falha ao remover: $error';
  }

  @override
  String get planDetailAlreadyPublished =>
      'Este plano está na biblioteca pública.';

  @override
  String get plansBrowseLibrary => 'Explorar biblioteca';

  @override
  String get planNewStarterTitle => 'Começar com um plano integrado';

  @override
  String get planNewStarterSubtitle =>
      'Escolha um plano de treino comprovado e o agendamos a partir da sua data de início; você pode ajustá-lo depois.';

  @override
  String get planNewStarterButton => 'Explorar planos iniciais';

  @override
  String get planNewStarterCreating => 'Criando…';

  @override
  String get planNewStarterPickerTitle => 'Escolha um plano inicial';

  @override
  String get planNewStarterPickerCancel => 'Cancelar';

  @override
  String planNewStarterCreateFailed(String error) {
    return 'Não foi possível criar esse plano: $error';
  }

  @override
  String get planNewStarterC25k => 'Couch to 5K (iniciante caminhada-corrida)';

  @override
  String get planNewStarterHalf12 => 'Meia maratona — 12 semanas';

  @override
  String get planNewStarterMarathon16 => 'Maratona — 16 semanas';

  @override
  String get planDetailTimeoutError =>
      'Tempo de conexão esgotado. Verifique sua rede e tente novamente.';

  @override
  String get planDetailLoadError =>
      'Não foi possível carregar este plano. Toque em tentar novamente.';

  @override
  String get planDetailNotFound => 'Plano não encontrado.';

  @override
  String get planDetailLongestLongRun => 'Longão mais longo';

  @override
  String get planDetailPublishTooltip => 'Publicar como modelo do clube';

  @override
  String planDetailDaysPerWeek(int count) {
    return '$count dias/sem.';
  }

  @override
  String get planDetailCurrentWeek => 'Esta semana';

  @override
  String get planDetailToday => 'HOJE';

  @override
  String get planDetailCompleted => 'Concluído';

  @override
  String planDetailWeek(int number) {
    return 'Semana $number';
  }

  @override
  String planDetailDriftOverFlag(int pct) {
    return 'Esta semana $pct% acima do plano — pegue leve nos dias fáceis para não cavar um buraco de fadiga.';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return 'Esta semana $pct% abaixo do plano — o volume planejado impulsiona a adaptação.';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      'Você perdeu o longão desta semana — encaixe se puder. É a sessão que mais importa.';

  @override
  String get planDetailMissedLongTaper =>
      'Você perdeu um longão, mas está em polimento — deixe pra lá e chegue descansado para a prova.';

  @override
  String get planDetailMissedLongRecovery =>
      'Você perdeu um longão — não tente repor. Uma semana de recuperação vem aí e seu corpo vai aproveitar o descanso.';

  @override
  String get planDetailReplan => 'Replanejar as semanas restantes';

  @override
  String get planDetailAdaptiveReplan => 'Replanejamento adaptativo';

  @override
  String get planDetailAdaptiveOnTrack =>
      'Suas últimas semanas estão dentro do plano — nenhum ajuste necessário.';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      'Você se desviou do plano recentemente, mas não há um ajuste seguro a fazer agora.';

  @override
  String get planDetailAdaptiveFitnessHeld =>
      'Pausado — você está acumulando fadiga agora, então aumentar o volume não é recomendado.';

  @override
  String get planDetailAdaptiveReasonUnder =>
      'abaixo do seu plano por várias semanas';

  @override
  String get planDetailAdaptiveReasonOver =>
      'acima do seu plano por várias semanas';

  @override
  String get planDetailAdaptiveConfidenceHigh => 'confiança alta';

  @override
  String get planDetailAdaptiveConfidenceMedium => 'confiança média';

  @override
  String planDetailAdaptiveBadge(String reason, String confidence) {
    return 'Com base em uma tendência — você esteve $reason ($confidence)';
  }

  @override
  String get planDetailReplanOnTrack =>
      'Seu plano está em dia — nada a ajustar.';

  @override
  String planDetailReplanApplied(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n treinos ajustados',
      one: '1 treino ajustado',
    );
    return '$_temp0';
  }

  @override
  String get planDetailReplanPreviewTitle => 'Mudanças propostas';

  @override
  String planDetailReplanMakeUp(String from, String to) {
    return 'Longão $from → $to — repor um longão perdido';
  }

  @override
  String planDetailReplanEase(String from, String to) {
    return '$from → $to — aliviar após excesso de volume';
  }

  @override
  String get planDetailReplanCancel => 'Cancelar';

  @override
  String get planDetailReplanApply => 'Aplicar mudanças';

  @override
  String get planDetailDuplicateWeek => 'Duplicar semana';

  @override
  String planDetailDuplicateWeekDone(int n) {
    return 'Semana $n duplicada';
  }

  @override
  String planDetailBulkFailed(String error) {
    return 'Não foi possível atualizar o plano: $error';
  }

  @override
  String get planDetailEditTooltip => 'Editar treino';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'Não foi possível carregar seus clubes — verifique sua rede.';

  @override
  String get planDetailPublishLoadClubsFailed =>
      'Não foi possível carregar seus clubes.';

  @override
  String get planDetailPublishNoClubs =>
      'Você precisa ser dono ou administrador de um clube para publicar um modelo.';

  @override
  String planDetailPublishSuccess(String name) {
    return '\"$name\" publicado como modelo do clube.';
  }

  @override
  String planDetailPublishFailed(String error) {
    return 'Falha ao publicar: $error';
  }

  @override
  String get planDetailPublishPickerTitle => 'Publicar no clube';

  @override
  String get planDetailPublishPickerBody =>
      'Os membros do clube poderão adotar este plano como seu.';

  @override
  String planDetailPublishPickerMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membros',
      one: '$count membro',
    );
    return '$_temp0';
  }

  @override
  String get planDetailPublishCancel => 'Cancelar';

  @override
  String get workoutTimeoutError =>
      'Tempo de conexão esgotado. Verifique sua rede e tente novamente.';

  @override
  String get workoutLoadError =>
      'Não foi possível carregar este treino. Toque em tentar novamente.';

  @override
  String get workoutNotFound => 'Treino não encontrado.';

  @override
  String get workoutMetricDistance => 'Distância';

  @override
  String get workoutMetricDuration => 'Duração';

  @override
  String get workoutMetricTargetPace => 'Ritmo-alvo';

  @override
  String get workoutCompleted => 'Concluído';

  @override
  String get workoutUnlink => 'Desvincular';

  @override
  String get workoutUnlinkTitle => 'Desvincular corrida';

  @override
  String get workoutUnlinkBody =>
      'Desvincular a corrida associada? A sessão voltará a aparecer como não concluída.';

  @override
  String get workoutUnlinkError =>
      'Não foi possível desvincular a corrida. Tente novamente.';

  @override
  String get workoutSkipped => 'Ignorado';

  @override
  String get workoutSkip => 'Ignorar este treino';

  @override
  String get workoutUnskip => 'Desfazer ignorar';

  @override
  String get workoutSkipError =>
      'Não foi possível atualizar o status de ignorado. Tente novamente.';

  @override
  String get workoutRelink => 'Revincular';

  @override
  String get workoutRelinkTitle => 'Vincular outra corrida';

  @override
  String get workoutRelinkHint =>
      'Escolha uma corrida próxima da data deste treino para contá-la como esta sessão. Corridas já vinculadas a outro treino não são exibidas.';

  @override
  String get workoutRelinkLoading => 'Procurando suas corridas…';

  @override
  String get workoutRelinkError =>
      'Não foi possível carregar suas corridas. Tente novamente.';

  @override
  String get workoutRelinkEmpty => 'Nenhuma corrida elegível perto desta data.';

  @override
  String get workoutRelinkCurrent => 'Atual';

  @override
  String get workoutStart => 'Iniciar treino';

  @override
  String get workoutSectionNotes => 'Notas';

  @override
  String get workoutSectionStructure => 'Estrutura';

  @override
  String get workoutSectionHowTo => 'Como correr';

  @override
  String get workoutStructWarmup => 'Aquecimento';

  @override
  String get workoutStructRepeats => 'Repetições';

  @override
  String get workoutStructSteady => 'Constante';

  @override
  String get workoutStructCooldown => 'Desaquecimento';

  @override
  String workoutStructWarmupValue(String distance) {
    return '$distance @ leve';
  }

  @override
  String workoutStructCooldownValue(String distance) {
    return '$distance @ leve';
  }

  @override
  String get workoutAdviceEasy =>
      'Ritmo de conversa. Se você não consegue conversar, está correndo rápido demais.';

  @override
  String get workoutAdviceLong =>
      'Fique relaxado. Busque uma respiração constante. Reduza 10% da distância se o clima estiver ruim ou você estiver dolorido — mas não pule.';

  @override
  String get workoutAdviceTempo =>
      '\"Confortavelmente difícil\". Você deve sentir que conseguiria manter o ritmo por cerca de uma hora em esforço máximo, mas não mais.';

  @override
  String get workoutAdviceInterval =>
      'Corra as repetições com intensidade suficiente para que a última pareça a primeira. Não escolha um ritmo que você só consiga manter por duas ou três repetições.';

  @override
  String get workoutAdviceMarathonPace =>
      'Trave exatamente no ritmo-alvo de maratona. Esta é uma sessão de ensaio — nem mais rápido, nem mais devagar.';

  @override
  String get workoutAdviceWalkRun =>
      'Alterne corrida leve e caminhada nos intervalos cronometrados. As pausas para caminhar fazem parte do treino — faça-as mesmo se estiver descansado.';

  @override
  String get workoutAdviceRace =>
      'Confie no plano. Não persiga um recorde no primeiro quilômetro.';

  @override
  String get workoutAdviceRest =>
      'Dia de descanso — se precisar se mexer, caminhe ou alongue.';

  @override
  String get coachTitle => 'Coach';

  @override
  String get coachNewConversation => 'Nova conversa';

  @override
  String get coachConsentHeadline => 'Antes de conversar com o Coach';

  @override
  String get coachConsentIntro =>
      'Para dar conselhos fundamentados, o Coach envia uma parte dos seus dados de treino à Anthropic, nosso provedor de modelos de IA nos Estados Unidos. Essa parte inclui:';

  @override
  String get coachConsentBulletProfile =>
      'Sua data de nascimento, gênero e zonas de FC, se definidas.';

  @override
  String get coachConsentBulletRuns =>
      'Uma amostra das suas corridas mais recentes.';

  @override
  String get coachConsentBulletPlan =>
      'O plano de treino ativo que você selecionou.';

  @override
  String get coachConsentBulletMessages =>
      'As mensagens de chat que você digita na tela abaixo.';

  @override
  String get coachConsentProcessing =>
      'A Anthropic processa os dados em nome da Threkir conforme seus termos de processamento; por padrão, não treinam seus modelos com dados de clientes da Threkir. Todos os detalhes — incluindo o mecanismo de transferência, a retenção e seus direitos de retirada — estão na nossa política de privacidade.';

  @override
  String get coachConsentAction =>
      'Toque em \"Eu consinto\" para continuar. Toque em cancelar para sair da página sem enviar dados.';

  @override
  String get coachConsentCancel => 'Cancelar';

  @override
  String get coachConsentAccept => 'Eu consinto — iniciar o Coach';

  @override
  String get coachConsentSaving => 'Registrando consentimento…';

  @override
  String get coachNoPlanOption => 'Sem plano (apenas corridas recentes)';

  @override
  String coachPlanActive(String name) {
    return '$name · ativo';
  }

  @override
  String coachPlanDone(String name) {
    return '$name · concluído';
  }

  @override
  String get coachNewChatTooltip => 'Novo chat';

  @override
  String get coachHistoryTooltip => 'Histórico de chat';

  @override
  String get coachNewChat => 'Novo chat';

  @override
  String coachActiveThread(String suffix) {
    return 'Ativo$suffix';
  }

  @override
  String get coachArchiveTapToView => 'Toque para ver · deslize para excluir';

  @override
  String get coachContextNoPlan => 'Sem plano';

  @override
  String coachContextPlanWeeks(String name, int weeks) {
    return '$name · $weeks sem.';
  }

  @override
  String get coachContextNoRuns => 'Sem corridas';

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
    return 'Visualizando arquivo · $label · somente leitura';
  }

  @override
  String get coachBackToActive => 'Voltar ao ativo';

  @override
  String get coachLimitReachedPro => 'Limite diário atingido. Volte amanhã.';

  @override
  String get coachLimitReachedFree =>
      'Limite diário atingido. O Pro tem um teto maior — atualize nas Configurações.';

  @override
  String coachMessagesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'restam $count mensagens hoje',
      one: 'resta $count mensagem hoje',
    );
    return '$_temp0';
  }

  @override
  String get coachEmptyPromptPlan =>
      'Pergunte sobre o treino de hoje, seu ritmo ou como as corridas recentes se comparam ao plano.';

  @override
  String get coachEmptyPromptNoPlan =>
      'Pergunte sobre suas corridas recentes, o ritmo de corridas leves ou o básico do treino.';

  @override
  String get coachSuggestPlanRest =>
      'Devo correr amanhã ou fazer um dia de descanso?';

  @override
  String get coachSuggestPlanOnTrack =>
      'Estou no caminho para o meu tempo-alvo?';

  @override
  String get coachSuggestPlanLongRun =>
      'Por que o longão desta semana importa?';

  @override
  String get coachSuggestPlanToday => 'No que devo focar no treino de hoje?';

  @override
  String get coachSuggestNoPlanLastRun => 'Como foi minha última corrida?';

  @override
  String get coachSuggestNoPlanEasyPace =>
      'Em que ritmo devem ser minhas corridas leves?';

  @override
  String get coachSuggestNoPlanWeekOff =>
      'Não corro há uma semana — o que devo fazer?';

  @override
  String get coachSuggestNoPlanTempo => 'O que é uma corrida de tempo?';

  @override
  String get coachEditCancel => 'Cancelar';

  @override
  String get coachEditSaveResend => 'Salvar e reenviar';

  @override
  String get coachActionCopy => 'Copiar';

  @override
  String get coachActionEdit => 'Editar';

  @override
  String get coachActionRegenerate => 'Regenerar';

  @override
  String get coachActionHelpful => 'Útil';

  @override
  String get coachActionNotHelpful => 'Não útil';

  @override
  String get coachComposerHintLimit => 'Limite diário atingido';

  @override
  String get coachComposerHint => 'Pergunte ao Coach…';

  @override
  String get coachArchiveTitle => 'Iniciar uma nova conversa?';

  @override
  String get coachArchiveBody =>
      'O chat atual vai para o histórico. Você pode revê-lo na barra lateral.';

  @override
  String get coachArchiveCancel => 'Cancelar';

  @override
  String get coachArchiveConfirm => 'Novo chat';

  @override
  String get coachSignInFirst => 'Por favor, entre primeiro.';

  @override
  String get coachSessionExpired =>
      'Sua sessão expirou. Por favor, entre novamente.';

  @override
  String coachDailyLimitError(int limit) {
    return 'Limite diário atingido ($limit mensagens). Volte amanhã!';
  }

  @override
  String coachGenericError(int code) {
    return 'Erro do Coach ($code)';
  }

  @override
  String get coachTransportError =>
      'Não foi possível alcançar o Coach. Verifique sua conexão e tente novamente.';

  @override
  String get coachStreamFailed => 'falha no fluxo';

  @override
  String coachNewConversationFailed(String error) {
    return 'Não foi possível iniciar uma nova conversa: $error';
  }

  @override
  String coachOpenArchiveFailed(String error) {
    return 'Não foi possível abrir o arquivo: $error';
  }

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Não foi possível excluir o arquivo: $error';
  }

  @override
  String get coachCopied => 'Copiado para a área de transferência';

  @override
  String get settingsAccountTitle => 'Conta';

  @override
  String get settingsAccountBackendNotConfigured => 'Backend não configurado';

  @override
  String get settingsAccountSignOutFailed =>
      'Falha ao sair — verifique sua conexão';

  @override
  String get settingsAccountChangePassword => 'Alterar senha';

  @override
  String get settingsAccountNewPassword => 'Nova senha';

  @override
  String get settingsAccountConfirm => 'Confirmar';

  @override
  String get settingsAccountCancel => 'Cancelar';

  @override
  String get settingsAccountSave => 'Salvar';

  @override
  String get settingsAccountPasswordTooShort =>
      'A senha deve ter pelo menos 8 caracteres';

  @override
  String get settingsAccountPasswordsMismatch => 'As senhas não coincidem';

  @override
  String get settingsAccountPasswordUpdated => 'Senha atualizada';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Não foi possível atualizar a senha: $error';
  }

  @override
  String get settingsAccountDeleteTitle => 'Excluir conta?';

  @override
  String get settingsAccountDeleteBody =>
      'Isso remove permanentemente suas corridas, rotas e perfil do servidor. Os dados locais do dispositivo são mantidos, a menos que você entre como um novo usuário. Isso não pode ser desfeito.';

  @override
  String get settingsAccountDeleteChallengeText =>
      'Digite \"DELETE\" para confirmar';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return 'Digite seu e-mail ($email) para confirmar';
  }

  @override
  String get settingsAccountDelete => 'Excluir';

  @override
  String get settingsAccountDeleteSignInFirst =>
      'Entre primeiro para excluir sua conta.';

  @override
  String get settingsAccountDeleted => 'Conta excluída';

  @override
  String get settingsAccountCoachConsentWithdraw =>
      'Retirar consentimento do Coach';

  @override
  String get settingsAccountCoachConsentActive =>
      'Impeça o Coach de usar seus dados de treino. Você pode consentir novamente quando quiser.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Consentimento do Coach retirado.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Falha ao retirar o consentimento: $error';
  }

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'Falha ao excluir a conta: $error';
  }

  @override
  String get settingsAccountNoRunsToExport => 'Nenhuma corrida para exportar.';

  @override
  String get settingsAccountCsvShareText => 'Run app — exportação de corridas';

  @override
  String settingsAccountCsvExportFailed(Object error) {
    return 'Falha na exportação CSV: $error';
  }

  @override
  String get settingsAccountBackupSignInFirst =>
      'Entre primeiro para fazer backup das suas corridas.';

  @override
  String get settingsAccountBackupPreparing => 'Preparando backup…';

  @override
  String get settingsAccountBackupShareText => 'Backup do Run app';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'Falha no backup: $error';
  }

  @override
  String get settingsAccountRestoreUnavailable =>
      'Serviço de backup indisponível.';

  @override
  String get settingsAccountRestoreTitle => 'Restaurar do backup?';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'Você não está conectado. As corridas serão restauradas neste dispositivo e sincronizadas com sua conta na próxima vez que você entrar.';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'Isso adiciona ou substitui corridas e rotas com IDs correspondentes no backup. Não excluirá corridas ou rotas que não estejam no backup.';

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
    return 'Restauradas $runs corridas · $tracks trajetos · $routes rotas$warnings';
  }

  @override
  String settingsAccountRestoreWarningsSuffix(int count) {
    return ' · $count avisos';
  }

  @override
  String settingsAccountRestoreFailed(Object error) {
    return 'Falha na restauração: $error';
  }

  @override
  String get settingsAccountOfflineMode => 'Modo off-line';

  @override
  String get settingsAccountSignedInSync =>
      'Conectado — as corridas serão sincronizadas';

  @override
  String get settingsAccountSignInToSync =>
      'Entre para sincronizar corridas entre dispositivos';

  @override
  String get settingsAccountSignOut => 'Sair';

  @override
  String get settingsAccountSignIn => 'Entrar';

  @override
  String get settingsAccountAvatar => 'Foto de perfil';

  @override
  String get settingsAccountAvatarHint => 'JPEG, PNG ou WebP, até 2 MB.';

  @override
  String get settingsAccountAvatarRemove => 'Remover foto';

  @override
  String get settingsAccountAvatarSaved => 'Foto de perfil atualizada.';

  @override
  String get settingsAccountAvatarRemoved => 'Foto de perfil removida.';

  @override
  String get settingsAccountAvatarUnsupported =>
      'Imagem não suportada — escolha JPEG, PNG ou WebP.';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return 'Não foi possível atualizar a foto: $error';
  }

  @override
  String get settingsAccountViewProfile => 'Ver perfil';

  @override
  String get settingsAccountViewProfileSubtitle =>
      'Suas corridas, seguidores, seguindo, notificações';

  @override
  String get settingsAccountGuidedRuns => 'Corridas guiadas';

  @override
  String get settingsAccountGuidedRunsSubtitle =>
      'Treinos roteirizados com voz de treinador e avisos por TTS';

  @override
  String get settingsAccountPrivacyZones => 'Zonas de privacidade';

  @override
  String get settingsAccountPrivacyZonesSubtitle =>
      'Corta o início/fim de trajetos públicos perto de casa';

  @override
  String get settingsAccountTrustedContacts => 'Contatos de confiança';

  @override
  String get settingsAccountTrustedContactsSubtitle =>
      'Pessoas designadas para o recurso planejado de corrida atrasada / pânico';

  @override
  String get settingsAccountSendErrorReports => 'Enviar relatórios de erro';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Dados anonimizados de falhas e erros para o Sentry (EUA). Desative para retirar o consentimento. Aplica-se na próxima inicialização.';

  @override
  String get settingsAccountErrorReportingEnabled =>
      'Relatórios de erro ativados — reinicie o app para aplicar.';

  @override
  String get settingsAccountErrorReportingDisabled =>
      'Relatórios de erro desativados — reinicie o app para aplicar.';

  @override
  String get settingsAccountImport => 'Importar de outro app';

  @override
  String get settingsAccountImportSubtitle => 'Strava, GPX, TCX';

  @override
  String get settingsAccountFullBackup => 'Backup completo';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'Cada corrida com seu trajeto GPS, além de rotas, perfil e preferências. Restaura na web ou no Android.';

  @override
  String get settingsAccountExportCsv => 'Exportar corridas como CSV';

  @override
  String get settingsAccountExportCsvSubtitle =>
      'Data, distância, duração, ritmo, origem — uma linha por corrida. Mesmo formato da exportação LGPD/GDPR da web.';

  @override
  String get settingsAccountRestoreTile => 'Restaurar do backup';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      'Escolha um backup .zip salvo anteriormente.';

  @override
  String get settingsAccountDeleteAccount => 'Excluir conta';

  @override
  String get settingsAccountDeleteAccountSubtitle =>
      'Remove permanentemente os dados do servidor';

  @override
  String get integrationsTitle => 'Integrações';

  @override
  String get integrationsJustNow => 'agora mesmo';

  @override
  String integrationsMinutesAgo(int minutes) {
    return 'há $minutes min';
  }

  @override
  String integrationsHoursAgo(int hours) {
    return 'há $hours h';
  }

  @override
  String integrationsDaysAgo(int days) {
    return 'há $days d';
  }

  @override
  String integrationsWeeksAgo(int weeks) {
    return 'há $weeks sem';
  }

  @override
  String integrationsCouldNotOpen(Object error) {
    return 'Não foi possível abrir: $error';
  }

  @override
  String get integrationsStravaBrowserHint =>
      'Conclua o login do Strava no navegador, depois volte aqui e puxe para atualizar.';

  @override
  String get integrationsStravaCancelled => 'Login do Strava cancelado.';

  @override
  String integrationsStravaSignInFailed(Object error) {
    return 'Falha no login do Strava: $error';
  }

  @override
  String get integrationsStravaCsrfMismatch =>
      'Login do Strava rejeitado: estado CSRF não corresponde. Tente novamente.';

  @override
  String integrationsStravaConnectFailed(String error) {
    return 'Falha ao conectar com o Strava: $error';
  }

  @override
  String get integrationsStravaConnected => 'Strava conectado.';

  @override
  String integrationsSyncResult(int imported, int skipped) {
    return 'Sincronizado. $imported novas, $skipped já presentes.';
  }

  @override
  String integrationsSyncFailed(Object error) {
    return 'Falha na sincronização: $error';
  }

  @override
  String get integrationsStravaDisconnectTitle => 'Desconectar o Strava?';

  @override
  String get integrationsStravaDisconnectBody =>
      'As atividades futuras deixarão de sincronizar automaticamente. As corridas já importadas permanecem no seu histórico.';

  @override
  String get integrationsCancel => 'Cancelar';

  @override
  String get integrationsDisconnect => 'Desconectar';

  @override
  String get integrationsStravaDisconnected => 'Strava desconectado.';

  @override
  String integrationsDisconnectFailed(Object error) {
    return 'Falha ao desconectar: $error';
  }

  @override
  String get integrationsParkrunTitle => 'Importar resultados do parkrun';

  @override
  String get integrationsParkrunBody =>
      'Digite seu número de atleta do parkrun (ex.: A123456). Buscaremos seu histórico de chegadas e adicionaremos os novos resultados à sua lista de corridas.';

  @override
  String get integrationsParkrunFieldLabel => 'Número de atleta';

  @override
  String get integrationsImport => 'Importar';

  @override
  String get integrationsParkrunImporting =>
      'Importando resultados do parkrun…';

  @override
  String integrationsParkrunImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados do parkrun importados.',
      one: '$count resultado do parkrun importado.',
    );
    return '$_temp0';
  }

  @override
  String get integrationsParkrunNoneNew =>
      'Nenhum novo resultado do parkrun desde a última importação.';

  @override
  String integrationsImportFailed(Object error) {
    return 'Falha na importação: $error';
  }

  @override
  String get integrationsStravaName => 'Strava';

  @override
  String get integrationsStravaConnectSubtitle =>
      'Conecte para sincronizar atividades automaticamente';

  @override
  String get integrationsStravaWaitingFirstSync =>
      'Conectado · aguardando a primeira sincronização';

  @override
  String integrationsStravaLastSync(String time) {
    return 'Conectado · última sincronização $time';
  }

  @override
  String get integrationsSyncNow => 'Sincronizar agora';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Importar resultados pelo número de atleta';

  @override
  String get integrationsSignInTitle => 'Entre para conectar serviços';

  @override
  String get integrationsSignInSubtitle =>
      'Strava + parkrun exigem uma conta para que as atividades sincronizadas entrem no seu histórico.';

  @override
  String get integrationsHealthConnectTitle =>
      'Gravar corridas no Health Connect';

  @override
  String get integrationsHealthConnectSubtitle =>
      'Envia cada corrida concluída ao Health Connect para que apareça no Google Fit, Samsung Health, Fitbit e outros.';

  @override
  String get integrationsHealthConnectDenied =>
      'Permissão do Health Connect não concedida — as corridas não serão gravadas.';

  @override
  String integrationsHrPairFailed(Object error) {
    return 'Falha no pareamento: $error';
  }

  @override
  String get integrationsHrTitle => 'Monitor de frequência cardíaca';

  @override
  String get integrationsHrChecking => 'Verificando…';

  @override
  String integrationsHrPaired(String name) {
    return 'Pareado: $name';
  }

  @override
  String get integrationsHrNotPaired =>
      'Nenhuma cinta pareada — toque para buscar';

  @override
  String get integrationsHrForget => 'Esquecer';

  @override
  String get integrationsHrForgetConfirm =>
      'Esquecer este monitor de frequência cardíaca? Você precisará pareá-lo novamente para usá-lo durante uma corrida.';

  @override
  String get integrationsHrScanTitle => 'Buscar monitor de frequência cardíaca';

  @override
  String get integrationsHrScanHint =>
      'Ative sua cinta / faixa peitoral. Geralmente leva de 3 a 8 segundos.';

  @override
  String get integrationsHrScanEmpty =>
      'Nenhuma cinta encontrada. Verifique se está por perto e ativa.';

  @override
  String integrationsHrRssi(int rssi) {
    return 'RSSI $rssi dBm';
  }

  @override
  String get integrationsTreadmillTitle => 'Esteira';

  @override
  String get integrationsTreadmillChecking => 'Verificando…';

  @override
  String integrationsTreadmillPaired(String name) {
    return 'Pareada: $name';
  }

  @override
  String get integrationsTreadmillNotPaired =>
      'Nenhuma esteira pareada — toque para procurar';

  @override
  String get integrationsTreadmillForget => 'Esquecer';

  @override
  String get integrationsTreadmillForgetConfirm =>
      'Esquecer esta esteira? Você precisará pareá-la novamente para usá-la durante uma corrida.';

  @override
  String get integrationsTreadmillScanTitle => 'Procurar esteira';

  @override
  String get integrationsTreadmillScanHint =>
      'Verifique se o Bluetooth da esteira está ligado e a esteira ativa. A busca leva de 3 a 8 segundos.';

  @override
  String get integrationsTreadmillScanEmpty =>
      'Nenhuma esteira encontrada. Verifique se ela é compatível com Bluetooth (FTMS) e está por perto.';

  @override
  String integrationsTreadmillPairFailed(Object error) {
    return 'Falha ao parear: $error';
  }

  @override
  String integrationsTreadmillLiveSpeed(String speed) {
    return '$speed km/h';
  }

  @override
  String get proTitle => 'Pro e suporte';

  @override
  String proCouldNotOpen(Object error) {
    return 'Não foi possível abrir: $error';
  }

  @override
  String get proWelcome => 'Bem-vindo ao Pro! Carregando seus benefícios…';

  @override
  String get proPurchaseFailed =>
      'A compra falhou. Tente novamente mais tarde.';

  @override
  String get proRestoreNeedsSignIn =>
      'Para restaurar, você precisa estar conectado com o RevenueCat configurado. Gerencie sua assinatura na página de upgrade da web.';

  @override
  String get proRestored => 'Sua assinatura Pro foi restaurada.';

  @override
  String get proRestoreNone =>
      'Nenhuma compra ativa encontrada nesta conta da loja.';

  @override
  String get proRestoreFailed =>
      'A restauração falhou. Tente novamente mais tarde.';

  @override
  String get proRestoreUnavailable => 'Restauração indisponível nesta versão.';

  @override
  String proSubscribeTitle(String price) {
    return 'Assinar o Pro — $price/mês';
  }

  @override
  String get proSubscribeSubtitleConfigured =>
      'Treinador de IA ilimitado + processamento prioritário. Renova automaticamente todo mês até ser cancelado em Configurações → Assinaturas.';

  @override
  String get proSubscribeSubtitleWeb =>
      'Abre o portal de assinatura no seu navegador. Renova automaticamente todo mês até ser cancelado.';

  @override
  String get proRegionalNote =>
      'Cobrado em dólares americanos. A disponibilidade depende do seu país e forma de pagamento — algumas regiões não podem ser atendidas pelo nosso processador de pagamentos.';

  @override
  String get proRestorePurchases => 'Restaurar compras';

  @override
  String get proRestorePurchasesSubtitle =>
      'Revincule compras de uma instalação anterior ou de outro dispositivo';

  @override
  String get proManageSubscription => 'Gerenciar assinatura';

  @override
  String get proManageSubscriptionSubtitle =>
      'Cancelar, mudar de plano ou atualizar a forma de pagamento';

  @override
  String get proSupport => 'Apoiar o app';

  @override
  String get proSupportSubtitle => 'Doação única no seu navegador';

  @override
  String get licensesTitle => 'Licenças';

  @override
  String get licensesVersion => 'Versão';

  @override
  String get licensesOpenSource => 'Licenças de código aberto';

  @override
  String get licensesOpenSourceSubtitle =>
      'Pacotes de terceiros incluídos neste app';

  @override
  String get devicesTitle => 'Dispositivos';

  @override
  String get devicesRenameTitle => 'Renomear dispositivo';

  @override
  String get devicesCancel => 'Cancelar';

  @override
  String get devicesSave => 'Salvar';

  @override
  String devicesRenameFailed(Object error) {
    return 'Falha ao renomear: $error';
  }

  @override
  String get devicesRemoveTitle => 'Remover dispositivo?';

  @override
  String get devicesRemoveBodyCurrent =>
      'Este é o dispositivo que você está usando. Removê-lo apaga as substituições de preferências por dispositivo; o dispositivo continua conectado.';

  @override
  String get devicesRemoveBodyOther =>
      'Remove a entrada do dispositivo e quaisquer substituições de preferências por dispositivo. O dispositivo continua conectado até abrir o app novamente.';

  @override
  String get devicesRemove => 'Remover';

  @override
  String devicesRemoveFailed(Object error) {
    return 'Falha ao remover: $error';
  }

  @override
  String devicesSaveFailed(Object error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get devicesLoadError => 'Não foi possível carregar os dispositivos.';

  @override
  String get devicesEmpty =>
      'Ainda não há dispositivos — eles são registrados na primeira vez que um dispositivo abre o app conectado.';

  @override
  String get devicesThisDevice => 'Este dispositivo';

  @override
  String devicesLastSeen(String time) {
    return 'Visto pela última vez $time';
  }

  @override
  String devicesOverrideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count substituições',
      one: '$count substituição',
    );
    return '$_temp0';
  }

  @override
  String get devicesJustNow => 'agora mesmo';

  @override
  String devicesMinutesAgo(int minutes) {
    return 'há $minutes min';
  }

  @override
  String devicesHoursAgo(int hours) {
    return 'há $hours h';
  }

  @override
  String devicesDaysAgo(int days) {
    return 'há $days d';
  }

  @override
  String get devicesRename => 'Renomear';

  @override
  String get devicesEditOverrides => 'Editar substituições…';

  @override
  String get devicesEveryKeySet =>
      'Todas as chaves substituíveis já estão definidas; remova uma antes de adicionar outra.';

  @override
  String get devicesOverridesSheetTitle => 'Substituições por dispositivo';

  @override
  String get devicesOverridesSheetDesc =>
      'Essas chaves substituem as configurações universais apenas neste dispositivo.';

  @override
  String get devicesNoOverrides => 'Nenhuma substituição neste dispositivo.';

  @override
  String get devicesAddOverride => 'Adicionar substituição';

  @override
  String get devicesPickKey => 'Escolher uma chave';

  @override
  String get devicesEnterWholeNumber => 'Digite um número inteiro.';

  @override
  String get devicesEnterNumber => 'Digite um número (ex.: 0,8).';

  @override
  String get devicesValue => 'Valor';

  @override
  String get devicesBack => 'Voltar';

  @override
  String get devicesAdd => 'Adicionar';

  @override
  String get devicesKeyPreferredUnitLabel => 'Unidade preferida';

  @override
  String get devicesKeyPreferredUnitHint =>
      'Unidade de distância para todas as telas.';

  @override
  String get devicesKeyDefaultActivityLabel => 'Atividade padrão';

  @override
  String get devicesKeyDefaultActivityHint =>
      'Atividade pré-selecionada na tela inicial.';

  @override
  String get devicesKeyMapStyleLabel => 'Estilo do mapa';

  @override
  String get devicesKeyMapStyleHint =>
      'Estilo MapLibre para a visualização do mapa.';

  @override
  String get devicesKeyPaceFormatLabel => 'Formato de ritmo';

  @override
  String get devicesKeyPaceFormatHint => 'Formato de exibição do ritmo.';

  @override
  String get devicesKeyVoiceFeedbackLabel => 'Feedback de voz';

  @override
  String get devicesKeyVoiceFeedbackHint =>
      'Fala avisos de ritmo / distância durante uma corrida.';

  @override
  String get devicesKeyVoiceIntervalLabel =>
      'Intervalo de feedback de voz (km)';

  @override
  String get devicesKeyVoiceIntervalHint =>
      'Distância entre os avisos falados.';

  @override
  String get devicesKeyHapticLabel => 'Feedback tátil';

  @override
  String get devicesKeyHapticHint =>
      'Vibração em mudanças de volta e zona de ritmo.';

  @override
  String get devicesKeyKeepScreenOnLabel => 'Manter a tela ligada';

  @override
  String get devicesKeyKeepScreenOnHint =>
      'Desativa o escurecimento automático do SO durante a gravação.';

  @override
  String get gearTitle => 'Equipamento';

  @override
  String get gearAddGear => 'Adicionar equipamento';

  @override
  String get gearDeleteTitle => 'Excluir equipamento?';

  @override
  String gearDeleteBody(String name) {
    return 'Excluir \"$name\"? O histórico de quilometragem das corridas anteriores será perdido. Aposente em vez disso para manter os registros.';
  }

  @override
  String get gearCancel => 'Cancelar';

  @override
  String get gearDelete => 'Excluir';

  @override
  String get gearDeletedOffline =>
      'Excluído localmente — será sincronizado quando você reconectar.';

  @override
  String gearAttached(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name associado a $count corridas.',
      one: '$name associado a $count corrida.',
    );
    return '$_temp0';
  }

  @override
  String gearOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Off-line — $count edições na fila, mostrando equipamento em cache.',
      one: 'Off-line — $count edição na fila, mostrando equipamento em cache.',
    );
    return '$_temp0';
  }

  @override
  String get gearOfflineCached => 'Off-line — mostrando equipamento em cache.';

  @override
  String get gearShoes => 'Tênis';

  @override
  String get gearBikes => 'Bicicletas';

  @override
  String get gearRetired => 'APOSENTADO';

  @override
  String get gearEmptyShoes => 'Ainda não há tênis';

  @override
  String get gearEmptyBikes => 'Ainda não há bicicletas';

  @override
  String get gearEmptySubtitle =>
      'Adicione um par para acompanhar a quilometragem e receber lembretes de aposentadoria.';

  @override
  String gearRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String get gearWearDue => 'Substituir em breve';

  @override
  String get gearWearWorn => 'Distância de troca ultrapassada';

  @override
  String get gearRetire => 'Aposentar';

  @override
  String get gearRestore => 'Restaurar';

  @override
  String get gearRotationsTitle => 'Rodízios';

  @override
  String get gearRotationsHint =>
      'Agrupe os equipamentos que você reveza — um conjunto de \"Treino diário\", um conjunto de \"Dia de prova\". Um rodízio é apenas um agrupamento nomeado; ele não muda qual par marca automaticamente as novas corridas.';

  @override
  String get gearRotationsEmpty =>
      'Nenhum rodízio ainda. Crie um para agrupar um conjunto de tênis ou bicicletas.';

  @override
  String get gearRotationName => 'Nome do rodízio';

  @override
  String get gearRotationNew => 'Novo rodízio';

  @override
  String get gearRotationCreate => 'Criar';

  @override
  String get gearRotationRename => 'Renomear';

  @override
  String get gearRotationManage => 'Editar equipamentos';

  @override
  String gearRotationManageTitle(String name) {
    return 'Equipamentos em \"$name\"';
  }

  @override
  String get gearRotationDeleteTitle => 'Excluir rodízio?';

  @override
  String gearRotationDeleteBody(String name) {
    return 'Excluir o rodízio \"$name\"? Seu equipamento não é afetado — apenas o agrupamento é removido.';
  }

  @override
  String gearRotationMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get gearRotationNoGear =>
      'Adicione equipamentos primeiro, depois você poderá agrupá-los em um rodízio.';

  @override
  String gearRotationSaveFailed(Object error) {
    return 'Não foi possível salvar o rodízio: $error';
  }

  @override
  String get gearRotationDone => 'Concluído';

  @override
  String get privacyZonesTitle => 'Zonas de privacidade';

  @override
  String get privacyZonesSaved => 'Zonas de privacidade salvas.';

  @override
  String privacyZonesSaveFailed(Object error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get privacyZonesSave => 'Salvar';

  @override
  String get privacyZonesLocateMe => 'Localizar-me';

  @override
  String get privacyZonesHint =>
      'Toque no mapa para adicionar uma zona. Trajetos em superfícies públicas têm o início e o fim cortados além do raio da zona.';

  @override
  String get privacyZonesSearchHint => 'Buscar lugares…';

  @override
  String get privacyZonesRadius => 'Raio';

  @override
  String privacyZonesRadiusMeters(int meters) {
    return '$meters m';
  }

  @override
  String privacyZonesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zonas — toque em um marcador para remover.',
      one: '$count zona — toque em um marcador para remover.',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'Limpar tudo';

  @override
  String get privacyZonesRemoveTitle => 'Remover zona de privacidade?';

  @override
  String get privacyZonesRemoveBody =>
      'Esta zona oculta seus trajetos por perto nos compartilhamentos públicos. Removê-la reexpõe esta área.';

  @override
  String get privacyZonesRemoveSemantics => 'Remover zona de privacidade';

  @override
  String get privacyZonesClearAllTitle =>
      'Limpar todas as zonas de privacidade?';

  @override
  String get privacyZonesClearAllBody =>
      'Isso remove todas as zonas, reexpondo todas essas áreas nos compartilhamentos públicos.';

  @override
  String get prefsTitle => 'Preferências';

  @override
  String get prefsUnitMetric => 'km, m';

  @override
  String get prefsUnitImperial => 'mi, ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · sincronizado com seus outros dispositivos';
  }

  @override
  String get prefsClear => 'Limpar';

  @override
  String get prefsCancel => 'Cancelar';

  @override
  String get prefsSave => 'Salvar';

  @override
  String get prefsSplitInterval => 'Intervalo de parciais';

  @override
  String get prefsSplitIntervalDefault => 'Padrão';

  @override
  String get prefsSplitIntervalDefaultSubtitle =>
      'Padrão (1 km ao correr, 5 km ao pedalar)';

  @override
  String get prefsLivePaceAlert => 'Alerta de ritmo ao vivo';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 's';

  @override
  String get prefsLivePaceAlertOff =>
      'Desativado — defina um ritmo para receber avisos falados durante uma corrida';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — aviso falado durante uma corrida quando o desvio for de 30 s ou mais';
  }

  @override
  String get prefsActivityRun => 'Corrida';

  @override
  String get prefsActivityWalk => 'Caminhada';

  @override
  String get prefsActivityHike => 'Trilha';

  @override
  String get prefsActivityCycle => 'Ciclismo';

  @override
  String get prefsPaceFormat => 'Formato de ritmo';

  @override
  String get prefsPaceFormatMinPerKm => 'Minutos por km';

  @override
  String get prefsPaceFormatMinPerMi => 'Minutos por milha';

  @override
  String get prefsPaceFormatKph => 'km/h';

  @override
  String get prefsPaceFormatMph => 'mph';

  @override
  String get prefsWeightUnit => 'Unidade de peso';

  @override
  String get prefsWeightUnitKg => 'Quilogramas (kg)';

  @override
  String get prefsWeightUnitLbs => 'Libras (lbs)';

  @override
  String get prefsNotSet => 'Não definido';

  @override
  String prefsHrZonesSummary(String zones) {
    return '$zones bpm';
  }

  @override
  String prefsWeeklyGoalSummary(String distance, String unit) {
    return '$distance $unit / semana';
  }

  @override
  String get prefsMapStyle => 'Estilo do mapa';

  @override
  String get prefsMapStyleStreets => 'Ruas';

  @override
  String get prefsMapStyleSatellite => 'Satélite';

  @override
  String get prefsMapStyleOutdoors => 'Ar livre';

  @override
  String get prefsMapStyleDark => 'Escuro';

  @override
  String get prefsDefaultRunVisibility => 'Visibilidade padrão das corridas';

  @override
  String get prefsCoachPersonality => 'Personalidade do treinador';

  @override
  String get prefsCoachSupportive => 'Apoiador';

  @override
  String get prefsCoachDrillSergeant => 'Sargento durão';

  @override
  String get prefsCoachAnalytical => 'Analítico';

  @override
  String get prefsSectionNotifications => 'Notificações';

  @override
  String get prefsEmailNotifications => 'Notificações por e-mail';

  @override
  String get prefsEmailNotifAll => 'Todas';

  @override
  String get prefsEmailNotifImportant => 'Apenas importantes';

  @override
  String get prefsEmailNotifOff => 'Desativadas';

  @override
  String get prefsPushNotifications => 'Notificações push';

  @override
  String get prefsPushNotifAll => 'Todas';

  @override
  String get prefsPushNotifImportant => 'Apenas importantes';

  @override
  String get prefsPushNotifOff => 'Desativadas';

  @override
  String get prefsEmailWeeklyDigest => 'E-mail de resumo semanal';

  @override
  String get prefsEmailWeeklyDigestHint =>
      'Inscreva-se para receber um resumo semanal do seu treino e dos destaques da comunidade. Desativado por padrão; separado dos seus e-mails de notificação.';

  @override
  String get prefsEmailLifecycleDrip => 'E-mail de dicas e incentivo';

  @override
  String get prefsEmailLifecycleDripHint =>
      'Inscreva-se para receber lembretes ocasionais de integração, reengajamento e sequência. Desativado por padrão; separado do seu resumo semanal e dos seus e-mails de notificação.';

  @override
  String get prefsWeekStart => 'A semana começa em';

  @override
  String get prefsWeekStartMonday => 'Segunda-feira';

  @override
  String get prefsWeekStartSunday => 'Domingo';

  @override
  String get prefsDefaultActivity => 'Atividade padrão';

  @override
  String get prefsDateOfBirth => 'Data de nascimento';

  @override
  String get prefsRestingHr => 'Frequência cardíaca em repouso';

  @override
  String get prefsMaxHr => 'Frequência cardíaca máxima';

  @override
  String get prefsMaxHrNotSet => 'Não definido — usa 208 − 0,7 × idade';

  @override
  String prefsHrBpm(int bpm) {
    return '$bpm bpm';
  }

  @override
  String get prefsSectionFueling => 'Reabastecimento de corrida';

  @override
  String get prefsCarbsPerHour => 'Carboidratos por hora';

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
  String get prefsHrZones => 'Zonas de frequência cardíaca';

  @override
  String get prefsHrZonesDialogTitle =>
      'Zonas de frequência cardíaca (limites superiores, bpm)';

  @override
  String get prefsWeeklyGoal => 'Meta de quilometragem semanal';

  @override
  String get prefsSectionActivityRecording => 'Atividade e gravação';

  @override
  String get prefsSectionTrainingDemographics => 'Treino e dados demográficos';

  @override
  String get prefsSectionPrivacySharing => 'Privacidade e compartilhamento';

  @override
  String get prefsSectionAiCoach => 'Treinador de IA';

  @override
  String get prefsSignInToEdit =>
      'Entre para editar configurações de perfil que sincronizam entre dispositivos.';

  @override
  String get prefsUseMiles => 'Usar milhas';

  @override
  String get prefsDarkMode => 'Modo escuro';

  @override
  String get prefsAudioCues => 'Avisos de áudio';

  @override
  String get prefsAudioCuesSubtitle => 'Anúncios falados de parciais';

  @override
  String get prefsMinimalVoiceCues => 'Avisos de voz mínimos';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Pula os avisos tagarelas de meio de repetição e desvio de ritmo';

  @override
  String get prefsKeepScreenOn => 'Manter a tela ligada';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Mantém um wakelock durante uma corrida';

  @override
  String get prefsAdvancedGps => 'GPS avançado';

  @override
  String get prefsAdvancedGpsSubtitle =>
      'Mais precisão, trajeto mais detalhado, mais consumo de bateria';

  @override
  String get prefsShowRawTrack => 'Mostrar trajeto GPS bruto';

  @override
  String get prefsShowRawTrackSubtitle =>
      'Desenha a linha gravada sem ajuste no mapa da corrida, mesmo quando existe um trajeto corrigido';

  @override
  String get prefsDefaultRunPrivacy => 'Privacidade padrão das corridas';

  @override
  String get prefsStravaAutoShare => 'Compartilhamento automático no Strava';

  @override
  String get prefsStravaAutoShareSubtitle =>
      'Envia automaticamente cada nova corrida para o Strava. Requer uma integração do Strava conectada quando estiver disponível.';

  @override
  String get prefsDiscoverable => 'Aparecer na busca por nome';

  @override
  String get prefsDiscoverableSubtitle =>
      'Quando desativado, sua conta não aparece quando outros corredores buscam pelo nome de exibição. Suas corridas públicas e seu perfil continuam acessíveis para qualquer pessoa com o URL.';

  @override
  String get dashboardCoachTooltip => 'Treinador';

  @override
  String get dashboardFeedTooltip => 'Feed de atividades';

  @override
  String get dashboardRecapTooltip => 'Ano em corrida';

  @override
  String get dashboardProfileTooltip => 'Meu perfil';

  @override
  String get dashboardWelcomeTitle => 'Bem-vindo!';

  @override
  String get dashboardWelcomeBody =>
      'Seu painel é preenchido assim que você registra uma corrida, define uma meta ou importa seu histórico.';

  @override
  String get dashboardSetGoal => 'Definir meta';

  @override
  String get dashboardImportRuns => 'Importar corridas';

  @override
  String get dashboardPeriodWeek => 'Semana';

  @override
  String get dashboardPeriodMonth => 'Mês';

  @override
  String get dashboardPeriodAllTime => 'Total';

  @override
  String get dashboardSectionStreak => 'Sequência';

  @override
  String get dashboardWeekStripTitle => 'Esta semana';

  @override
  String dashboardWeekStripCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count atividades',
      one: '$count atividade',
    );
    return '$_temp0';
  }

  @override
  String dashboardWeekStripDayAria(String dow, String dist) {
    return '$dow: $dist';
  }

  @override
  String dashboardWeekStripDayRestAria(String dow) {
    return '$dow: dia de descanso';
  }

  @override
  String get dashboardSectionLast20Weeks => 'Últimas 20 semanas';

  @override
  String get dashboardSectionRecentLifts => 'Sessões recentes';

  @override
  String get dashboardViewAllGym => 'Ver tudo';

  @override
  String get dashboardSectionPersonalBests => 'Recordes pessoais';

  @override
  String get dashboardLongestRun => 'Corrida mais longa';

  @override
  String dashboardFastestDistance(String distance) {
    return 'Mais rápido em $distance';
  }

  @override
  String get dashboardGoals => 'Metas';

  @override
  String get dashboardAdd => 'Adicionar';

  @override
  String get dashboardGoalWeekly => 'SEMANAL';

  @override
  String get dashboardGoalMonthly => 'MENSAL';

  @override
  String dashboardGoalTitleFallback(String period) {
    return 'META $period';
  }

  @override
  String get dashboardSetWeeklyGoalA11y =>
      'Definir uma meta semanal de corrida';

  @override
  String get dashboardSetFirstGoal => 'Defina sua primeira meta';

  @override
  String get dashboardSetFirstGoalBody =>
      'Acompanhe distância, tempo, ritmo ou número de corridas por semana ou mês.';

  @override
  String get dashboardGoalTapToEdit => 'toque para editar';

  @override
  String get dashboardGoalComplete => 'Concluída.';

  @override
  String get dashboardGoalInProgress => 'Em andamento.';

  @override
  String dashboardGoalA11y(String period, String title, String status) {
    return 'Meta $period — $title $status';
  }

  @override
  String dashboardRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '$count corrida',
    );
    return '$_temp0';
  }

  @override
  String dashboardVert(String value) {
    return '$value de elevação';
  }

  @override
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  ) {
    return 'Resumo de $label, $distance em $runs$elevation';
  }

  @override
  String dashboardElevationGainSuffix(String value) {
    return ', $value de ganho de elevação';
  }

  @override
  String get dashboardStreakCurrent => 'Atual';

  @override
  String get dashboardStreakHistory => 'Histórico';

  @override
  String get dashboardStreakDayUnit => 'dia';

  @override
  String get dashboardStreakDaysUnit => 'dias';

  @override
  String dashboardStreakBest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dias',
      one: '$count dia',
    );
    return 'melhor $_temp0';
  }

  @override
  String get dashboardStreakAllTimeBest => 'recorde de todos os tempos';

  @override
  String get dashboardStreakRestart => 'corra hoje para reiniciá-la';

  @override
  String get dashboardStreakStart => 'corra hoje para começar uma';

  @override
  String get dashboardHeatmapLess => 'Menos';

  @override
  String get dashboardHeatmapMore => 'Mais';

  @override
  String get dashboardHeatmapTapHint => 'Toque em uma semana para ver o resumo';

  @override
  String get periodWeeklySummary => 'Resumo semanal';

  @override
  String get periodMonthlySummary => 'Resumo mensal';

  @override
  String get periodAllTimeSummary => 'Resumo geral';

  @override
  String get periodShareTooltip => 'Compartilhar';

  @override
  String get periodPreviousTooltip => 'Anterior';

  @override
  String get periodNextTooltip => 'Próximo';

  @override
  String get periodSwitchToWeekly => 'Toque para mudar para semanal';

  @override
  String get periodSwitchToMonthly => 'Toque para mudar para mensal';

  @override
  String get periodSwitchToAllTime => 'Toque para mudar para total';

  @override
  String get periodStatDistance => 'Distância';

  @override
  String get periodStatRuns => 'Corridas';

  @override
  String get periodStatTime => 'Tempo';

  @override
  String get periodStatAvgPace => 'Ritmo médio';

  @override
  String get periodEmptyWeek => 'Nenhuma corrida esta semana';

  @override
  String get periodEmptyMonth => 'Nenhuma corrida este mês';

  @override
  String get periodShareSummary => 'Compartilhar resumo';

  @override
  String get periodShareText => 'Texto';

  @override
  String get periodShareImage => 'Imagem';

  @override
  String get periodShareImageFailed =>
      'Não foi possível criar a imagem de compartilhamento';

  @override
  String get periodShareCardTagline => 'CORREDOR MELHOR';

  @override
  String get periodShareStatDistance => 'DISTÂNCIA';

  @override
  String get periodShareStatRuns => 'CORRIDAS';

  @override
  String get periodShareStatTime => 'TEMPO';

  @override
  String get periodShareStatAvgPace => 'RITMO MÉDIO';

  @override
  String get trainingLoadTitle => 'Forma, Fadiga e Frescor';

  @override
  String trainingLoadSubtitleHr(int days) {
    return 'TRIMP de frequência cardíaca dos últimos $days dias.';
  }

  @override
  String get trainingLoadSubtitleVolume =>
      'Baseado em volume — defina FC de repouso e máxima nas preferências e registre com uma cinta para mudar para TRIMP.';

  @override
  String get trainingLoadEmpty =>
      'Registre algumas corridas para ver sua tendência de forma.';

  @override
  String get trainingLoadLegendFitness => 'Forma';

  @override
  String get trainingLoadLegendFatigue => 'Fadiga';

  @override
  String get trainingLoadLegendForm => 'Frescor';

  @override
  String trainingLoadLegendEntry(String label, int value) {
    return '$label · $value';
  }

  @override
  String get trainingLoadReadingLoaded =>
      'Carregado — siga em frente e recupere quando estiver pronto.';

  @override
  String get trainingLoadReadingTapered =>
      'Em afunilamento — uma sessão difícil não vai te quebrar.';

  @override
  String get trainingLoadReadingBalanced =>
      'Equilibrado — dia leve ou dia difícil, você decide.';

  @override
  String get trainingLoadIncludesLifts =>
      'Inclui sessões de academia — musculação também soma fadiga.';

  @override
  String get intensityTitle => 'INTENSIDADE DE TREINO';

  @override
  String intensityWindow(int days) {
    return 'últimos $days dias';
  }

  @override
  String intensityBasedOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas com FC',
      one: '$count corrida com FC',
    );
    return 'Com base em $_temp0';
  }

  @override
  String get mileageTitle => 'QUILOMETRAGEM';

  @override
  String get mileageWeek => 'Semana';

  @override
  String get mileageMonth => 'Mês';

  @override
  String get mileageYear => 'Ano';

  @override
  String get mileageThisWeek => 'esta semana';

  @override
  String get mileageThisMonth => 'este mês';

  @override
  String get mileageThisYear => 'este ano';

  @override
  String get fitnessTitle => 'Forma';

  @override
  String get fitnessStatVo2Max => 'VO₂ máx';

  @override
  String get fitnessStatVo2MaxTooltip =>
      'Seu motor aeróbico: quanto oxigênio seu corpo consegue usar por minuto. Quanto maior, melhor a forma.';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'A pontuação de forma de Daniels com base no seu melhor esforço recente. Define seus ritmos de treino.';

  @override
  String get fitnessStatRuns => 'Corridas';

  @override
  String get fitnessStatRunsTooltip =>
      'Corridas recentes longas o suficiente para contar na sua estimativa de forma.';

  @override
  String get fitnessStatCtl => 'Forma (CTL)';

  @override
  String get fitnessStatCtlTooltip =>
      'Sua carga de treino móvel de 42 dias. Cresce devagar; é sua base de resistência.';

  @override
  String get fitnessStatAtl => 'Fadiga (ATL)';

  @override
  String get fitnessStatAtlTooltip =>
      'Sua carga dos últimos 7 dias. Sobe rápido após sessões difíceis e cai com o descanso.';

  @override
  String get fitnessStatTsb => 'Frescor (TSB)';

  @override
  String get fitnessStatTsbTooltip =>
      'Forma menos fadiga. Positivo = descansado e pronto para competir; negativo = com fadiga acumulada.';

  @override
  String get runSocialActivity => 'Atividade';

  @override
  String get runSocialNoComments => 'Ainda não há comentários.';

  @override
  String get runSocialReplyHint => 'Escreva uma resposta…';

  @override
  String get runSocialCommentHint => 'Adicione um comentário…';

  @override
  String get runSocialRunnerFallback => 'Corredor';

  @override
  String get runSocialReply => 'Responder';

  @override
  String get runSocialDelete => 'Excluir';

  @override
  String get runSocialDeleteCommentTitle => 'Excluir este comentário?';

  @override
  String get runSocialDeleteCommentMessage =>
      'Este comentário será removido permanentemente. Não é possível desfazer.';

  @override
  String get runSocialPost => 'Publicar';

  @override
  String get runSocialCancel => 'Cancelar';

  @override
  String runSocialKudosError(String error) {
    return 'Não foi possível atualizar os kudos: $error';
  }

  @override
  String runSocialPostError(String error) {
    return 'Falha ao publicar: $error';
  }

  @override
  String runSocialDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get runPhotosLoading => 'Carregando fotos…';

  @override
  String get runPhotosTitle => 'Fotos';

  @override
  String get runPhotosAdd => 'Adicionar foto';

  @override
  String get runPhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get runPhotosCaptionHint => 'Legenda…';

  @override
  String get runPhotosCancel => 'Cancelar';

  @override
  String get runPhotosSave => 'Salvar';

  @override
  String get runPhotosUpload => 'Enviar';

  @override
  String get runPhotosUploading => 'Enviando…';

  @override
  String get runPhotosEditCaption => 'Editar legenda';

  @override
  String get runPhotosDeleteTooltip => 'Excluir foto';

  @override
  String get runPhotosDeleteTitle => 'Excluir foto?';

  @override
  String get runPhotosDeleteBody =>
      'Isto remove a foto da corrida permanentemente.';

  @override
  String get runPhotosDeleteConfirm => 'Excluir';

  @override
  String runPhotosPickerError(String error) {
    return 'Não foi possível abrir o seletor: $error';
  }

  @override
  String runPhotosUploadError(String error) {
    return 'Falha no envio: $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get routePhotosLoading => 'Carregando fotos…';

  @override
  String get routePhotosTitle => 'Fotos';

  @override
  String get routePhotosAdd => 'Adicionar foto';

  @override
  String get routePhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get routePhotosCaptionHint => 'Legenda…';

  @override
  String get routePhotosCancel => 'Cancelar';

  @override
  String get routePhotosSave => 'Salvar';

  @override
  String get routePhotosUpload => 'Enviar';

  @override
  String get routePhotosUploading => 'Enviando…';

  @override
  String get routePhotosEditCaption => 'Editar legenda';

  @override
  String get routePhotosDeleteTooltip => 'Excluir foto';

  @override
  String get routePhotosDeleteTitle => 'Excluir foto?';

  @override
  String get routePhotosDeleteBody =>
      'Isto remove a foto do percurso permanentemente.';

  @override
  String get routePhotosDeleteConfirm => 'Excluir';

  @override
  String routePhotosPickerError(String error) {
    return 'Não foi possível abrir o seletor: $error';
  }

  @override
  String routePhotosUploadError(String error) {
    return 'Falha no envio: $error';
  }

  @override
  String routePhotosDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get clubPhotosLoading => 'Carregando fotos…';

  @override
  String get clubPhotosTitle => 'Fotos';

  @override
  String get clubPhotosAdd => 'Adicionar foto';

  @override
  String get clubPhotosEmpty => 'Ainda não há fotos neste clube.';

  @override
  String get clubPhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get clubPhotosCaptionHint => 'Legenda…';

  @override
  String get clubPhotosCancel => 'Cancelar';

  @override
  String get clubPhotosSave => 'Salvar';

  @override
  String get clubPhotosUpload => 'Enviar';

  @override
  String get clubPhotosUploading => 'Enviando…';

  @override
  String get clubPhotosEditCaption => 'Editar legenda';

  @override
  String get clubPhotosDeleteTooltip => 'Excluir foto';

  @override
  String get clubPhotosDeleteTitle => 'Excluir foto?';

  @override
  String get clubPhotosDeleteBody =>
      'Isto remove a foto do clube permanentemente.';

  @override
  String get clubPhotosDeleteConfirm => 'Excluir';

  @override
  String clubPhotosPickerError(String error) {
    return 'Não foi possível abrir o seletor: $error';
  }

  @override
  String clubPhotosUploadError(String error) {
    return 'Falha no envio: $error';
  }

  @override
  String clubPhotosDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String clubPhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get runSegEffortsChecking => 'Verificando segmentos…';

  @override
  String get runSegEffortsNoRoute =>
      'Os segmentos são associados por rota — vincule esta corrida a uma rota salva para competir nos rankings dela.';

  @override
  String get runSegEffortsEmpty => 'Nenhum esforço de segmento nesta corrida.';

  @override
  String get workoutReviewTitle => 'Treino';

  @override
  String get workoutReviewColStep => 'Etapa';

  @override
  String get workoutReviewColPlan => 'Plano';

  @override
  String get workoutReviewColActual => 'Real';

  @override
  String get workoutReviewColPace => 'Ritmo';

  @override
  String get workoutReviewColDelta => 'Δ';

  @override
  String get workoutReviewSkip => 'pular';

  @override
  String get workoutReviewLabelWarmup => 'Aquecimento';

  @override
  String get workoutReviewLabelCooldown => 'Desaquecimento';

  @override
  String get workoutReviewLabelSteady => 'Constante';

  @override
  String get workoutReviewLabelRep => 'Rep.';

  @override
  String workoutReviewLabelRepN(int index, int total) {
    return 'Rep. $index/$total';
  }

  @override
  String get workoutReviewLabelRecovery => 'Recuperação';

  @override
  String workoutReviewLabelRecoveryN(int index, int total) {
    return 'Recuperação $index/$total';
  }

  @override
  String get workoutReviewLabelWalk => 'Caminhada';

  @override
  String workoutReviewLabelWalkN(int index, int total) {
    return 'Caminhada $index/$total';
  }

  @override
  String get segmentsPanelTitle => 'Segmentos';

  @override
  String get segmentsPanelNew => 'Novo segmento';

  @override
  String get segmentsPanelCancel => 'Cancelar';

  @override
  String get segmentsPanelLoading => 'Carregando segmentos…';

  @override
  String get segmentsPanelEmpty => 'Ainda não há segmentos nesta rota.';

  @override
  String get segmentsPanelNameLabel => 'Nome';

  @override
  String get segmentsPanelNameHint => 'Subida do terror';

  @override
  String get segmentsPanelStartLabel => 'Início (m)';

  @override
  String get segmentsPanelEndLabel => 'Fim (m)';

  @override
  String segmentsPanelRouteHint(int metres) {
    return 'a rota tem $metres m';
  }

  @override
  String get segmentsPanelCreate => 'Criar';

  @override
  String get segmentsPanelDeleteTooltip => 'Excluir segmento';

  @override
  String get segmentsPanelDeleteTitle => 'Excluir segmento?';

  @override
  String segmentsPanelDeleteBody(String name) {
    return '“$name” será removido.';
  }

  @override
  String get segmentsPanelDeleteConfirm => 'Excluir';

  @override
  String get segmentsPanelErrEndAfterStart =>
      'O fim deve ser maior que o início';

  @override
  String get segmentsPanelErrMinLength =>
      'O segmento deve ter pelo menos 100 m';

  @override
  String segmentsPanelCreateError(String error) {
    return 'Não foi possível criar o segmento: $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get segmentsPanelAllGenders => 'Todos os gêneros';

  @override
  String get segmentsPanelGenderMen => 'Homens';

  @override
  String get segmentsPanelGenderWomen => 'Mulheres';

  @override
  String get segmentsPanelGenderNonbinary => 'Não binário';

  @override
  String get segmentsPanelAllAges => 'Todas as idades';

  @override
  String get segmentsPanelResetFilters => 'Redefinir';

  @override
  String get segmentsPanelLeaderboardLoading => 'Carregando…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'Nenhum esforço corresponde a este filtro — tente ampliá-lo.';

  @override
  String get segmentsPanelLeaderboardEmpty =>
      'Ainda não há esforços — seja o primeiro a correr este segmento.';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'Você detém esta coroa — $label.';
  }

  @override
  String get segmentsPanelRunnerFallback => 'Corredor';

  @override
  String get goalEditorTitleNew => 'Nova meta';

  @override
  String get goalEditorTitleEdit => 'Editar meta';

  @override
  String get goalEditorNameLabel => 'Nome (opcional)';

  @override
  String get goalEditorNameHint => 'ex. Base de quilômetros';

  @override
  String get goalEditorPeriod => 'Período';

  @override
  String get goalEditorThisWeek => 'Esta semana';

  @override
  String get goalEditorThisMonth => 'Este mês';

  @override
  String get goalEditorTargets => 'Metas';

  @override
  String get goalEditorTargetsHelp =>
      'Defina qualquer combinação. Campos em branco são ignorados.';

  @override
  String get goalEditorTargetDistance => 'Distância';

  @override
  String get goalEditorTargetTime => 'Tempo';

  @override
  String get goalEditorTargetPace => 'Ritmo médio';

  @override
  String get goalEditorTargetRuns => 'Corridas';

  @override
  String get goalEditorSuffixMin => 'min';

  @override
  String get goalEditorSuffixRuns => 'corridas';

  @override
  String get goalEditorDelete => 'Excluir';

  @override
  String get goalEditorDeleteTitle => 'Excluir esta meta?';

  @override
  String get goalEditorDeleteMessage =>
      'Esta meta e o acompanhamento de progresso serão removidos. Você pode criar uma nova quando quiser.';

  @override
  String get goalEditorCancel => 'Cancelar';

  @override
  String get goalEditorSave => 'Salvar';

  @override
  String goalEditorSaveFailed(String error) {
    return 'Não foi possível salvar a meta: $error';
  }

  @override
  String get goalEditorErrDistance => 'Distância: insira um número positivo';

  @override
  String get goalEditorErrTime => 'Tempo: insira um número positivo de minutos';

  @override
  String get goalEditorErrPace => 'Ritmo: use mm:ss (ex. 5:00)';

  @override
  String get goalEditorErrRuns => 'Corridas: insira um número inteiro positivo';

  @override
  String get goalEditorErrNoTarget => 'Defina pelo menos uma meta';

  @override
  String get goalEditorSavedAnnounce => 'Meta salva';

  @override
  String get goalEditorDeletedAnnounce => 'Meta excluída';

  @override
  String get eventFormTitle => 'Novo evento';

  @override
  String get eventFormTitleLabel => 'Título';

  @override
  String get eventFormStartsAt => 'Começa em';

  @override
  String get eventFormDescriptionLabel => 'Descrição (opcional)';

  @override
  String get eventFormMeetLabel => 'Ponto de encontro (opcional)';

  @override
  String get eventFormMeetHint => 'Estacionamento do início da trilha';

  @override
  String get eventFormDistanceLabel => 'Distância (km)';

  @override
  String get eventFormDurationLabel => 'Duração (min)';

  @override
  String get eventFormRecurrence => 'Recorrência';

  @override
  String get eventFormRecurOneOff => 'Único';

  @override
  String get eventFormRecurWeekly => 'Semanal';

  @override
  String get eventFormRecurBiweekly => 'Quinzenal';

  @override
  String get eventFormRecurMonthly => 'Mensal';

  @override
  String get eventFormCancel => 'Cancelar';

  @override
  String get eventFormCreate => 'Criar evento';

  @override
  String get eventEditorCategory => 'Tipo de evento';

  @override
  String get eventEditorCatRun => 'Corrida em grupo';

  @override
  String get eventEditorCatCycle => 'Ciclismo';

  @override
  String get eventEditorCatClass => 'Aula';

  @override
  String get eventEditorCatSocial => 'Social';

  @override
  String get eventEditorCategoryHint =>
      'Escolha o tipo de evento — uma aula ou encontro social ignora rota, distância, ritmo e resultados de corrida.';

  @override
  String get eventEditorMembersOnlyToggle => 'Somente para membros';

  @override
  String get eventEditorMembersOnlyHint =>
      'Apenas membros do clube podem ver este evento, e ele não aparecerá na busca pública.';

  @override
  String get eventEditorDiscipline => 'Modalidade';

  @override
  String get eventEditorDisciplinePlaceholder =>
      'ex.: ioga Vinyasa, Pilates, mobilidade';

  @override
  String get clubFormTitle => 'Novo clube';

  @override
  String get clubFormNameLabel => 'Nome';

  @override
  String get clubFormDescriptionLabel => 'Descrição (opcional)';

  @override
  String get clubFormLocationLabel => 'Localização (opcional)';

  @override
  String get clubFormLocationHint => 'Edimburgo, Reino Unido';

  @override
  String get clubFormPublic => 'Público';

  @override
  String get clubFormPrivate => 'Privado';

  @override
  String get clubFormJoinPolicy => 'Política de adesão';

  @override
  String get clubFormJoinOpen => 'Aberto — qualquer um entra';

  @override
  String get clubFormJoinRequest => 'Solicitação — admins aprovam';

  @override
  String get clubFormJoinInvite => 'Apenas por convite';

  @override
  String get clubFormCancel => 'Cancelar';

  @override
  String get clubFormCreate => 'Criar';

  @override
  String get clubFormErrSlug =>
      'O nome precisa de pelo menos uma letra ou dígito.';

  @override
  String get clubFormErrUnreachable =>
      'Não é possível acessar o servidor agora. Verifique sua conexão ou entre na conta e tente novamente.';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonHarassment => 'Assédio ou abuso';

  @override
  String get reportReasonInappropriate => 'Conteúdo impróprio';

  @override
  String get reportReasonImpersonation => 'Falsidade ideológica';

  @override
  String get reportReasonOther => 'Outro';

  @override
  String get reportSuccess =>
      'Denúncia enviada — obrigado por sinalizar isto para revisão.';

  @override
  String get reportTitleUser => 'Denunciar usuário';

  @override
  String get reportTitleClub => 'Denunciar clube';

  @override
  String get reportTitleRoute => 'Denunciar rota';

  @override
  String get reportTitlePost => 'Denunciar publicação';

  @override
  String get reportTitleRun => 'Denunciar corrida';

  @override
  String get reportTitleContent => 'Denunciar conteúdo';

  @override
  String get reportDisclaimer =>
      'Sua denúncia vai para um moderador. Denúncias falsas também são analisadas — sinalize apenas conteúdo que viole nossas diretrizes da comunidade.';

  @override
  String get reportReason => 'Motivo';

  @override
  String get reportNotesLabel => 'Notas (opcional)';

  @override
  String get reportCancel => 'Cancelar';

  @override
  String get reportSubmit => 'Enviar denúncia';

  @override
  String get reportErrDuplicate =>
      'Você já tem uma denúncia pendente sobre este conteúdo.';

  @override
  String gearBackfillTitle(String gear) {
    return 'Vincular corridas anteriores a $gear?';
  }

  @override
  String gearBackfillBody(int count, String activity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count atividades de $activity',
      one: '$count atividade de $activity',
    );
    return 'Encontramos $_temp0 após a compra. Desmarque aquelas em que você não os usou.';
  }

  @override
  String get gearBackfillActivityCycling => 'ciclismo';

  @override
  String get gearBackfillActivityRunning => 'corrida';

  @override
  String get gearBackfillSelectNone => 'Desmarcar todas';

  @override
  String get gearBackfillSelectAll => 'Selecionar todas';

  @override
  String gearBackfillSelectedCount(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get gearBackfillSkip => 'Pular';

  @override
  String get gearBackfillAttaching => 'Vinculando…';

  @override
  String gearBackfillAttach(int count) {
    return 'Vincular $count';
  }

  @override
  String gearBackfillAttachError(String error) {
    return 'Falha ao vincular: $error';
  }

  @override
  String get workoutEditTitle => 'Editar treino';

  @override
  String get workoutEditKindLabel => 'Tipo';

  @override
  String get workoutEditDistanceLabel => 'Distância alvo (km)';

  @override
  String get workoutEditDistanceHint => 'ex. 8.0';

  @override
  String get workoutEditPaceLabel => 'Ritmo alvo (mm:ss /km)';

  @override
  String get workoutEditPaceHint => 'ex. 5:30';

  @override
  String get workoutEditNotesLabel => 'Notas';

  @override
  String get workoutEditCancel => 'Cancelar';

  @override
  String get workoutEditSave => 'Salvar';

  @override
  String get workoutEditErrDistance => 'Insira uma distância positiva em km';

  @override
  String get workoutEditErrPace => 'O ritmo deve ter o formato 5:30';

  @override
  String workoutEditSaveError(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return 'CONFIRMADO · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'Começando agora';

  @override
  String upcomingEventInMinutes(int count) {
    return 'Em $count min';
  }

  @override
  String get upcomingEventInOneHour => 'Em 1 hora';

  @override
  String upcomingEventInHours(int count) {
    return 'Em $count horas';
  }

  @override
  String get upcomingEventTomorrow => 'Amanhã';

  @override
  String upcomingEventInDays(int count) {
    return 'Em $count dias';
  }

  @override
  String get todaysWorkoutDone => 'FEITO HOJE';

  @override
  String get todaysWorkoutToday => 'TREINO DE HOJE';

  @override
  String get errorStateRetry => 'Tentar novamente';

  @override
  String get shareCardRunTitle => 'Compartilhar corrida';

  @override
  String get shareCardExport => 'Exportar';

  @override
  String get shareCardImage => 'Imagem';

  @override
  String get shareCardStatDistance => 'Distância';

  @override
  String get shareCardStatTime => 'Tempo';

  @override
  String get shareCardStatPace => 'Ritmo';

  @override
  String get shareCardStatSpeed => 'Velocidade';

  @override
  String get shareCardBrandRun => 'RUN';

  @override
  String get shareCardImageError =>
      'Não foi possível criar a imagem de compartilhamento';

  @override
  String get shareCardFileError => 'Não foi possível exportar o arquivo';

  @override
  String get shareCardRouteTitle => 'Compartilhar rota';

  @override
  String get shareCardRouteShareImage => 'Compartilhar imagem';

  @override
  String get shareCardRouteCapturing => 'Capturando…';

  @override
  String get shareCardRouteStatDistance => 'Distância';

  @override
  String get shareCardRouteStatClimb => 'Subida';

  @override
  String get billingToday => 'hoje';

  @override
  String get billingYesterday => 'ontem';

  @override
  String billingDaysAgo(int count) {
    return 'há $count dias';
  }

  @override
  String billingRenewalFailed(String relative) {
    return 'A renovação Pro falhou $relative.';
  }

  @override
  String get billingRenewalBody =>
      'Atualize seu cartão ou você será rebaixado para o Free.';

  @override
  String get billingManage => 'Gerenciar';

  @override
  String get planCalendarPrevMonth => 'Mês anterior';

  @override
  String get planCalendarNextMonth => 'Próximo mês';

  @override
  String runGearChipsLoadError(String error) {
    return 'Falha ao carregar equipamento: $error';
  }

  @override
  String get runGearChipsPickerTitle =>
      'Marcar o equipamento usado nesta corrida';

  @override
  String get runGearChipsEmpty =>
      'Você ainda não registrou nenhum equipamento. Adicione em Configurações → Equipamento.';

  @override
  String get runGearChipsCancel => 'Cancelar';

  @override
  String get runGearChipsSave => 'Salvar';

  @override
  String get runGearChipsTag => '+ Marcar equipamento';

  @override
  String get runGearChipsEdit => 'Editar';

  @override
  String runGearChipsSaveError(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get gearFormTitleEdit => 'Editar equipamento';

  @override
  String get gearFormTitleAddShoes => 'Adicionar tênis';

  @override
  String get gearFormTitleAddBike => 'Adicionar bicicleta';

  @override
  String get gearFormNameLabel => 'Nome';

  @override
  String get gearFormNameHint => 'Pegasus 39';

  @override
  String get gearFormBrandLabel => 'Marca';

  @override
  String get gearFormModelLabel => 'Modelo';

  @override
  String get gearFormBoughtLabel => 'Comprado';

  @override
  String get gearFormBoughtPick => 'Toque para escolher';

  @override
  String gearFormRetireAt(String unit) {
    return 'Aposentar em ($unit)';
  }

  @override
  String get gearFormRetireHint => '500';

  @override
  String get gearFormNotesLabel => 'Notas';

  @override
  String get gearFormCancel => 'Cancelar';

  @override
  String get gearFormSaving => 'Salvando…';

  @override
  String get gearFormSave => 'Salvar';

  @override
  String get gearFormAdd => 'Adicionar';

  @override
  String gearFormSaveError(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String get gearWearLogHeading => 'Registro de desgaste';

  @override
  String get gearWearLogHint =>
      'Anote como este equipamento está envelhecendo — desgaste do solado, entressola morta, cabedal puído.';

  @override
  String get gearWearLogEmpty => 'Nenhuma observação de desgaste ainda.';

  @override
  String get gearWearLogAddNote => 'Observação';

  @override
  String get gearWearLogNoteHint => 'ex.: cravos do solado gastos no calcanhar';

  @override
  String get gearWearLogArea => 'Área';

  @override
  String get gearWearLogAreaNone => '—';

  @override
  String get gearWearLogAreaOutsole => 'Solado';

  @override
  String get gearWearLogAreaMidsole => 'Entressola';

  @override
  String get gearWearLogAreaUpper => 'Cabedal';

  @override
  String get gearWearLogAreaOther => 'Outro';

  @override
  String get gearWearLogAdd => 'Adicionar observação';

  @override
  String get gearWearLogAdding => 'Adicionando…';

  @override
  String get gearWearLogDelete => 'Excluir observação';

  @override
  String gearWearLogAddError(String error) {
    return 'Não foi possível adicionar a observação: $error';
  }

  @override
  String gearWearLogDeleteError(String error) {
    return 'Não foi possível excluir a observação: $error';
  }

  @override
  String get notificationBellTooltip => 'Notificações';

  @override
  String get liveRunMapWaitingGps => 'Aguardando GPS...';

  @override
  String get liveRunMapRecentre => 'Recentralizar na minha localização';

  @override
  String get ttsRunStarted => 'Corrida iniciada';

  @override
  String ttsRunComplete(String distance, int mins) {
    return 'Corrida concluída. $distance em $mins minutos.';
  }

  @override
  String get ttsOffRoute => 'Fora da rota';

  @override
  String get ttsPaceAlertFast => 'Acelere o ritmo';

  @override
  String get ttsPaceAlertSlow => 'Diminua o ritmo';

  @override
  String get ttsWorkoutComplete => 'Treino concluído. Bom trabalho.';

  @override
  String get ttsStepHalfway => 'Metade desta repetição';

  @override
  String get ttsStepLastFifty => 'Faltam cinquenta metros';

  @override
  String ttsPaceDriftAhead(int delta) {
    return 'Alivie um pouco — $delta segundos rápido demais.';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return 'Acelere um pouco — $delta segundos lento demais.';
  }

  @override
  String ttsSpeedKm(String value) {
    return 'Velocidade, $value quilômetros por hora';
  }

  @override
  String ttsSpeedMi(String value) {
    return 'Velocidade, $value milhas por hora';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por quilômetro';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por milha';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$value quilômetros';
  }

  @override
  String ttsDistanceMetres(int value) {
    return '$value metros';
  }

  @override
  String ttsDistanceMileSingular(String value) {
    return '$value milha';
  }

  @override
  String ttsDistanceMiles(String value) {
    return '$value milhas';
  }

  @override
  String ttsDistanceYards(int value) {
    return '$value jardas';
  }

  @override
  String ttsSplit(String count, String unit, String tail) {
    return '$count $unit. $tail';
  }

  @override
  String get ttsStepWarmup => 'Aquecimento';

  @override
  String get ttsStepRecovery => 'Recuperação';

  @override
  String get ttsStepSteady => 'Ritmo constante';

  @override
  String get ttsStepCooldown => 'Desaquecimento';

  @override
  String get ttsStepRep => 'Repetição';

  @override
  String get ttsStepRun => 'Corrida';

  @override
  String get ttsStepWalk => 'Caminhada';

  @override
  String ttsStepRepOf(int index, int total) {
    return 'Repetição $index de $total';
  }

  @override
  String ttsStepRunOf(int index, int total) {
    return 'Corrida $index de $total';
  }

  @override
  String ttsStepWalkOf(int index, int total) {
    return 'Caminhada $index de $total';
  }

  @override
  String ttsStepPaceKm(int min, int sec) {
    return '$min minutos $sec segundos por quilômetro';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '$min minutos por quilômetro';
  }

  @override
  String ttsStepPaceMi(int min, int sec) {
    return '$min minutos $sec segundos por milha';
  }

  @override
  String ttsStepPaceMiWhole(int min) {
    return '$min minutos por milha';
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
  String get guidedEasy30Title => 'Corrida leve de 30 minutos';

  @override
  String get guidedEasy30Subtitle => 'Voz do treinador · 30 min · esforço leve';

  @override
  String get guidedEasy30Description =>
      'Uma corrida tranquila em ritmo de conversa, para um dia de recuperação ou só para clarear a cabeça. O treinador aparece a cada cinco minutos com um empurrãozinho gentil.';

  @override
  String get guidedEasy30Cue0 =>
      'Vamos lá. Comece leve — este é o seu ritmo de recuperação.';

  @override
  String get guidedEasy30Cue1 =>
      'Cinco minutos. Relaxe os ombros. Mantenha o ritmo de conversa.';

  @override
  String get guidedEasy30Cue2 =>
      'Dez minutos. Verifique a cadência — pés rápidos, pisada leve.';

  @override
  String get guidedEasy30Cue3 =>
      'Metade. Você ainda deve conseguir conversar enquanto corre.';

  @override
  String get guidedEasy30Cue4 =>
      'Vinte minutos. Observe a respiração — inspire devagar pelo nariz, expire pela boca.';

  @override
  String get guidedEasy30Cue5 =>
      'Faltam cinco minutos. Mantenha-se relaxado. Não acelere.';

  @override
  String get guidedEasy30Cue6 => 'Falta um minuto. Termine leve.';

  @override
  String get guidedEasy30Cue7 =>
      'Concluído. Caminhe um minuto para recuperar. Mandou bem.';

  @override
  String get guidedTempo25Title => 'Construtor de tempo de 25 minutos';

  @override
  String get guidedTempo25Subtitle => 'Voz do treinador · 25 min · 5-15-5';

  @override
  String get guidedTempo25Description =>
      'Cinco minutos de aquecimento leve, quinze minutos em tempo (confortavelmente forte), cinco minutos de desaquecimento. A clássica sessão de tempo semanal.';

  @override
  String get guidedTempo25Cue0 =>
      'Hora do aquecimento. Cinco minutos leves — acorde as pernas.';

  @override
  String get guidedTempo25Cue1 =>
      'Falta um minuto de aquecimento. Aumente a cadência.';

  @override
  String get guidedTempo25Cue2 =>
      'Suba para o tempo. Confortavelmente forte. Como um esforço de prova de 10K.';

  @override
  String get guidedTempo25Cue3 =>
      'Cinco minutos em tempo. Forte, mas controlado. Mantenha o ritmo.';

  @override
  String get guidedTempo25Cue4 =>
      'Dez minutos de tempo feitos. Segure o ritmo.';

  @override
  String get guidedTempo25Cue5 =>
      'Faltam dois minutos em tempo. Mantenha-se fluido.';

  @override
  String get guidedTempo25Cue6 =>
      'Alivie. Cinco minutos leves para desaquecer.';

  @override
  String get guidedTempo25Cue7 =>
      'Faltam dois minutos. Traga a frequência cardíaca de volta para baixo.';

  @override
  String get guidedTempo25Cue8 =>
      'Concluído. Caminhe e alongue. Ótimo trabalho.';

  @override
  String get guidedFirst15Title => 'Iniciante: 15 minutos corrida/caminhada';

  @override
  String get guidedFirst15Subtitle =>
      'Voz do treinador · 15 min · intervalos corrida/caminhada';

  @override
  String get guidedFirst15Description =>
      'Novo na corrida? Três séries de um minuto correndo e um minuto caminhando, mais aquecimento e desaquecimento. Uma entrada suave; todo mundo começa aqui.';

  @override
  String get guidedFirst15Cue0 =>
      'Comece com três minutos de caminhada acelerada para aquecer.';

  @override
  String get guidedFirst15Cue1 =>
      'Mude para um minuto de corrida leve. Ritmo de conversa.';

  @override
  String get guidedFirst15Cue2 => 'Caminhe um minuto.';

  @override
  String get guidedFirst15Cue3 => 'Corra um minuto.';

  @override
  String get guidedFirst15Cue4 => 'Caminhe um minuto.';

  @override
  String get guidedFirst15Cue5 => 'Corra um minuto.';

  @override
  String get guidedFirst15Cue6 => 'Caminhe um minuto.';

  @override
  String get guidedFirst15Cue7 => 'Corra um minuto — o último.';

  @override
  String get guidedFirst15Cue8 =>
      'Volte para a caminhada. Cinco minutos de desaquecimento.';

  @override
  String get guidedFirst15Cue9 => 'Falta um minuto. Caminhe leve.';

  @override
  String get guidedFirst15Cue10 =>
      'Concluído. Isso foi uma corrida de verdade. Volte a correr em breve.';

  @override
  String guidedRunMinutesBadge(int minutes) {
    return '$minutes min';
  }

  @override
  String guidedRunCueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count indicações na corrida',
      one: '$count indicação na corrida',
    );
    return '$_temp0';
  }

  @override
  String get guidedRunFullScript => 'O ROTEIRO COMPLETO';

  @override
  String get guidedRunPreviewCue => 'Ouvir indicação';

  @override
  String guidedRunPreviewError(String error) {
    return 'Não foi possível ouvir: $error';
  }

  @override
  String get ttsSplitUnitKilometre => 'quilômetro';

  @override
  String get ttsSplitUnitKilometres => 'quilômetros';

  @override
  String get ttsSplitUnitMile => 'milha';

  @override
  String get ttsSplitUnitMiles => 'milhas';

  @override
  String get workoutKindEasy => 'Leve';

  @override
  String get workoutKindLong => 'Longão';

  @override
  String get workoutKindRecovery => 'Recuperação';

  @override
  String get workoutKindTempo => 'Tempo';

  @override
  String get workoutKindInterval => 'Intervalado';

  @override
  String get workoutKindMarathonPace => 'Ritmo de maratona';

  @override
  String get workoutKindWalkRun => 'Caminhada-corrida';

  @override
  String get workoutKindRace => 'Prova';

  @override
  String get workoutKindRest => 'Descanso';

  @override
  String get planPhaseBase => 'Base';

  @override
  String get planPhaseBuild => 'Construção';

  @override
  String get planPhasePeak => 'Pico';

  @override
  String get planPhaseTaper => 'Polimento';

  @override
  String get planPhaseRace => 'Semana de prova';

  @override
  String get runBackgroundLocationNudgeTitle =>
      'Permitir localização o tempo todo';

  @override
  String get runBackgroundLocationNudgeBody =>
      'O Android só concedeu a localização enquanto o app está aberto. Para uma distância precisa com a tela desligada, defina o acesso à localização como \"Permitir o tempo todo\" nas Configurações. Você pode começar mesmo assim — a gravação continua funcionando enquanto o app estiver na tela.';

  @override
  String get runBatteryOptHintTitle =>
      'Manter a gravação ativa em segundo plano';

  @override
  String get runBatteryOptHintBody =>
      'Alguns celulares (Samsung, Xiaomi, OnePlus e outros) colocam os apps em suspensão para economizar bateria, o que pode interromper a gravação de uma corrida longa quando a tela está desligada. Por segurança, exclua este app da otimização de bateria nas Configurações. Sua corrida será gravada de qualquer forma — isso apenas impede que o sistema a interrompa.';

  @override
  String shareCardCaption(Object title, Object distance, Object duration) {
    return '$title — $distance em $duration';
  }

  @override
  String get settingsBackendNotConfigured => 'Backend não configurado';

  @override
  String get settingsAccountSignedIn => 'Conectado';

  @override
  String get settingsDevicesSignedOutSubtitle =>
      'Entre para gerenciar seus dispositivos';

  @override
  String get verifiedClubTooltip => 'Clube verificado oficial';

  @override
  String get raceDistance5k => '5 km';

  @override
  String get raceDistance10k => '10 km';

  @override
  String get raceDistanceHalfMarathon => 'Meia maratona';

  @override
  String get raceDistanceMarathon => 'Maratona';

  @override
  String get settingsTabAccountSubtitle => 'Entrar, backup, excluir conta';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Unidades, tema, gravação, treino, privacidade';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, cinta de frequência cardíaca';

  @override
  String get settingsTabDevicesSubtitle =>
      'Onde você está conectado e ajustes por dispositivo';

  @override
  String get settingsTabGearSubtitle =>
      'Acompanhe tênis + bikes e a quilometragem por item';

  @override
  String get settingsTabCoachingSubtitle =>
      'Treine atletas ou siga o seu próprio treinador';

  @override
  String get settingsTabProSubtitle =>
      'Assine, restaure compras, gerencie a cobrança';

  @override
  String get settingsTabLicensesSubtitle =>
      'Versão do app e avisos de código aberto';

  @override
  String periodSummaryWeekOf(Object date) {
    return 'Semana de $date';
  }

  @override
  String periodShareRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas',
      one: '1 corrida',
    );
    return '$_temp0';
  }

  @override
  String periodShareAvgPace(Object pace) {
    return 'Ritmo médio: $pace';
  }

  @override
  String get gymTitle => 'Academia';

  @override
  String get gymLog => 'Registrar treino';

  @override
  String get gymUntitled => 'Treino sem título';

  @override
  String get gymOfflineCached => 'Offline: mostrando treinos salvos';

  @override
  String get gymOfflineQueued =>
      'Offline: as alterações serão sincronizadas mais tarde';

  @override
  String get gymEmptyTitle => 'Nenhum treino de academia ainda';

  @override
  String get gymEmptyBody =>
      'Registre um treino para acompanhá-lo aqui e alimentar sua carga de treino.';

  @override
  String get gymPrBadge => 'RP';

  @override
  String gymExercisesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercícios',
      one: '$count exercício',
    );
    return '$_temp0';
  }

  @override
  String gymVolumeShort(int volume) {
    return '$volume kg';
  }

  @override
  String get gymNotFound => 'Treino não encontrado.';

  @override
  String get gymEdit => 'Editar';

  @override
  String get gymDelete => 'Excluir';

  @override
  String get gymPublic => 'Público';

  @override
  String get gymPrivate => 'Privado';

  @override
  String get gymMakePublic => 'Tornar público';

  @override
  String get gymMakePrivate => 'Tornar privado';

  @override
  String gymVisibilityFailed(Object error) {
    return 'Não foi possível atualizar a visibilidade: $error';
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
  String get gymDuration => 'Tempo (s)';

  @override
  String gymDurationValue(String seconds) {
    return '${seconds}s';
  }

  @override
  String gymSetN(int n) {
    return 'Série $n';
  }

  @override
  String get gymPrWeight => 'Mais pesada';

  @override
  String get gymPrVolume => 'Melhor volume';

  @override
  String get gymPrE1rm => 'Melhor 1RM est.';

  @override
  String get gymRecordsLink => 'Recordes';

  @override
  String get gymRecordsTitle => 'Recordes pessoais';

  @override
  String get gymRecordsSubtitle =>
      'Sua melhor marca em cada exercício com peso.';

  @override
  String get gymRecordsEmpty =>
      'Nenhum exercício com peso registrado ainda. Adicione um peso a uma série para começar a acompanhar seus recordes.';

  @override
  String gymRecordsLastDone(String date) {
    return 'Último $date';
  }

  @override
  String gymRecordsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessões',
      one: '1 sessão',
    );
    return '$_temp0';
  }

  @override
  String get gymExerciseBack => 'Voltar aos recordes';

  @override
  String get gymExerciseEmpty => 'Ainda não há histórico deste exercício.';

  @override
  String gymSinceFirstUp(String delta) {
    return '+$delta desde a primeira sessão';
  }

  @override
  String gymSinceFirstDown(String delta) {
    return '−$delta desde a primeira sessão';
  }

  @override
  String get gymSinceFirstFlat => 'sem mudança desde a primeira sessão';

  @override
  String gymDetailLastTime(String date) {
    return 'Última vez $date';
  }

  @override
  String get gymVolumeLabel => 'Volume';

  @override
  String get gymDeleteConfirmTitle => 'Excluir treino?';

  @override
  String get gymDeleteConfirmBody =>
      'Isso remove permanentemente o treino e suas séries.';

  @override
  String get clubEventMembersOnly => 'Somente membros';

  @override
  String get clubEventLogAsWorkout => 'Registrar como treino';

  @override
  String get clubEventLogAsWorkoutHint =>
      'Adicione esta aula ao seu próprio registro de academia — você pode ajustar os detalhes antes de salvar.';

  @override
  String get clubEventLogAsWorkoutSaved =>
      'Adicionado ao seu registro de academia';

  @override
  String get clubEventDownloadCertificate => 'Certificado de conclusão';

  @override
  String get clubEventCertificateShare => 'Salvar ou compartilhar';

  @override
  String clubEventCertificateShareText(String event) {
    return 'Concluí $event!';
  }

  @override
  String get clubEventCertificateFailed =>
      'Não foi possível gerar o certificado. Tente novamente.';

  @override
  String get clubEventCertificateHeading => 'Certificado de Conclusão';

  @override
  String get clubEventCertificateCertifies => 'Isto certifica que';

  @override
  String get clubEventCertificateCompleted => 'concluiu';

  @override
  String get clubEventCertificateTime => 'Tempo';

  @override
  String get clubEventCertificateDistance => 'Distância';

  @override
  String clubEventCertificatePlace(String place) {
    return '$place lugar';
  }

  @override
  String get gymEditorNewTitle => 'Novo treino';

  @override
  String get gymEditorEditTitle => 'Editar treino';

  @override
  String get gymEditorTitleLabel => 'Título (opcional)';

  @override
  String get gymEditorTitlePlaceholder => 'ex.: Dia de push';

  @override
  String get gymEditorExercisePlaceholder => 'Nome do exercício';

  @override
  String get gymEditorRemoveExercise => 'Remover exercício';

  @override
  String get gymEditorRemoveSet => 'Remover série';

  @override
  String get gymEditorAddSet => 'Adicionar série';

  @override
  String get gymEditorAddExercise => 'Adicionar exercício';

  @override
  String get gymEditorShare => 'Compartilhar no feed';

  @override
  String get gymEditorCancel => 'Cancelar';

  @override
  String get gymEditorSave => 'Salvar treino';

  @override
  String get gymEditorNeedExercise =>
      'Adicione ao menos um exercício com nome.';

  @override
  String get gymCatalogueBrowse => 'Procurar catálogo';

  @override
  String get gymCatalogueTitle => 'Catálogo de exercícios';

  @override
  String get gymCatalogueSearchPlaceholder => 'Buscar exercícios';

  @override
  String get gymCatalogueCategoryLabel => 'Categoria';

  @override
  String get gymCatalogueEmpty => 'Nenhum exercício corresponde.';

  @override
  String get gymCatalogueCustomBadge => 'Personalizado';

  @override
  String gymCatalogueCreate(String name) {
    return 'Adicionar “$name” como exercício personalizado';
  }

  @override
  String get gymCatalogueCreateFailed =>
      'Não foi possível adicionar esse exercício.';

  @override
  String get gymCatalogueCategoryAll => 'Todos';

  @override
  String get gymCatalogueCategoryChest => 'Peito';

  @override
  String get gymCatalogueCategoryBack => 'Costas';

  @override
  String get gymCatalogueCategoryShoulders => 'Ombros';

  @override
  String get gymCatalogueCategoryLegs => 'Pernas';

  @override
  String get gymCatalogueCategoryArms => 'Braços';

  @override
  String get gymCatalogueCategoryCore => 'Core';

  @override
  String get gymCatalogueCategoryCardio => 'Cardio';

  @override
  String get gymCatalogueCategoryFullBody => 'Corpo inteiro';

  @override
  String get gymCatalogueCategoryOther => 'Outros';

  @override
  String get gymSaveFailed => 'Não foi possível salvar o treino.';

  @override
  String get gymRoutineLink => 'Rotinas';

  @override
  String get gymRoutineTitle => 'Rotinas';

  @override
  String get gymRoutineNew => 'Nova rotina';

  @override
  String get gymRoutineBack => 'Voltar para rotinas';

  @override
  String get gymRoutineNotFound => 'Rotina não encontrada.';

  @override
  String gymRoutineExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercícios',
      one: '$count exercício',
    );
    return '$_temp0';
  }

  @override
  String get gymRoutineStart => 'Iniciar rotina';

  @override
  String get gymRoutinePublishLabel => 'Publicar em um clube';

  @override
  String get gymRoutinePublishPick => 'Escolha um clube…';

  @override
  String get gymRoutinePublish => 'Publicar';

  @override
  String get gymRoutinePublishSuccess => 'Rotina publicada no clube.';

  @override
  String get gymRoutinePublishFailed => 'Não foi possível publicar a rotina.';

  @override
  String get gymRoutineClubTemplateBadge => 'Modelo do clube';

  @override
  String get gymRoutinePublicBadge => 'Na biblioteca pública';

  @override
  String get gymRoutinePublishPublicLabel => 'Biblioteca pública';

  @override
  String get gymRoutinePublishPublic => 'Publicar na biblioteca pública';

  @override
  String get gymRoutineUnpublishPublic => 'Remover da biblioteca pública';

  @override
  String get gymRoutinePublishPublicHint =>
      'Qualquer pessoa conectada pode visualizar e adotar esta rotina. Os treinos registrados continuam privados.';

  @override
  String get gymRoutinePublishPublicSuccess =>
      'Rotina publicada na biblioteca pública.';

  @override
  String get gymRoutineUnpublishPublicSuccess =>
      'Rotina removida da biblioteca pública.';

  @override
  String get gymRoutinePublishPublicFailed =>
      'Não foi possível alterar a visibilidade pública.';

  @override
  String get gymLibraryLink => 'Biblioteca';

  @override
  String get gymLibraryTitle => 'Biblioteca pública de rotinas';

  @override
  String get gymLibrarySearchHint => 'Buscar rotinas por nome';

  @override
  String get gymLibraryLoadError => 'Não foi possível carregar a biblioteca.';

  @override
  String get gymLibraryEmpty => 'Ainda não há rotinas publicadas.';

  @override
  String gymLibraryEmptySearch(String query) {
    return 'Nenhuma rotina corresponde a \"$query\".';
  }

  @override
  String gymLibraryByAuthor(String author) {
    return 'por $author';
  }

  @override
  String get gymLibraryAnonymous => 'um praticante';

  @override
  String get gymLibraryAdopt => 'Adotar nas minhas rotinas';

  @override
  String get gymLibraryAdopting => 'Adotando…';

  @override
  String get gymLibraryAdoptFailed => 'Não foi possível adotar a rotina.';

  @override
  String get gymRoutineDelete => 'Excluir';

  @override
  String get gymRoutineDeleteConfirmTitle => 'Excluir rotina?';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'Isso remove a rotina permanentemente. Os treinos registrados não são afetados.';

  @override
  String get gymRoutineDeleted => 'Rotina excluída';

  @override
  String get gymRoutineCreated => 'Rotina salva';

  @override
  String get gymRoutineSaveFailed => 'Não foi possível salvar a rotina.';

  @override
  String get gymRoutineEmptyTitle => 'Nenhuma rotina ainda';

  @override
  String get gymRoutineEmptyBody =>
      'Salve um treino registrado como rotina, ou crie uma, para reutilizá-la.';

  @override
  String get gymRoutineTargetReps => 'Repetições-alvo';

  @override
  String gymRoutineTargetWeight(String unit) {
    return 'Carga-alvo ($unit)';
  }

  @override
  String get gymRoutineEditorNewTitle => 'Nova rotina';

  @override
  String get gymRoutineEditorTitleLabel => 'Nome da rotina';

  @override
  String get gymRoutineEditorTitlePlaceholder => 'ex.: Dia de empurrar A';

  @override
  String get gymRoutineEditorNotesLabel => 'Notas (opcional)';

  @override
  String get gymRoutineEditorSave => 'Salvar rotina';

  @override
  String get gymRoutineEditorCancel => 'Cancelar';

  @override
  String get gymRoutineEditorNeedTitle => 'Dê um nome à rotina.';

  @override
  String get gymRoutineEditorNeedExercise =>
      'Adicione pelo menos um exercício com nome.';

  @override
  String get gymRoutineSaveAsRoutine => 'Salvar como rotina';

  @override
  String get gymRoutineRepeatLast => 'Repetir o último';

  @override
  String get gymRoutineTargetRepsMax => 'a';

  @override
  String get gymRoutineTargetDuration => 'Tempo alvo (s)';

  @override
  String get gymRoutineTargetDistance => 'Distância alvo (m)';

  @override
  String get gymRoutineRestLabel => 'Descanso (s)';

  @override
  String get gymRoutineSetType => 'Tipo de série';

  @override
  String get gymRoutineSetTypeWarmup => 'Aquecimento';

  @override
  String get gymRoutineSetTypeWorking => 'Série de trabalho';

  @override
  String get gymRoutineSetTypeDropset => 'Drop set';

  @override
  String get gymRoutineSetTypeAmrap => 'AMRAP';

  @override
  String get gymRoutineSetTypeFailure => 'Até a falha';

  @override
  String get gymRoutineSetTypeBackoff => 'Back-off';

  @override
  String get gymRoutineModality => 'Medido por';

  @override
  String get gymRoutineModalityWeightReps => 'Peso × reps';

  @override
  String get gymRoutineModalityTime => 'Tempo';

  @override
  String get gymRoutineModalityDistance => 'Distância';

  @override
  String get gymRoutineModalityBodyweightReps => 'Reps com peso corporal';

  @override
  String get gymRoutineSupersetToggle => 'Supersérie com o próximo exercício';

  @override
  String gymRoutineSupersetBadge(int group) {
    return 'Supersérie $group';
  }

  @override
  String get gymRoutineAdvanced => 'Avançado';

  @override
  String get gymRoutineProgression => 'Progressão';

  @override
  String get gymRoutineProgressionNone => 'Nenhuma';

  @override
  String get gymRoutineProgressionLinear => 'Linear';

  @override
  String get gymRoutineProgressionDoubleProgression => 'Dupla progressão';

  @override
  String get gymRoutineProgressionFiveByFive => '5×5';

  @override
  String get gymRoutineProgressionPercentCycle => 'Ciclo % de 1RM';

  @override
  String get gymRoutineProgressionRpeAutoreg => 'Autorregulação RPE';

  @override
  String gymRoutineProgressionIncrementLabel(String unit) {
    return 'Passo de peso ($unit)';
  }

  @override
  String get gymRoutineProgressionPercentLabel => '% de 1RM';

  @override
  String gymRoutineProgressionOneRmLabel(String unit) {
    return '1RM ($unit)';
  }

  @override
  String get gymRoutineProgressionTargetRpeLabel => 'RPE alvo';

  @override
  String get gymRoutineNextTarget => 'Próximo alvo';

  @override
  String get gymRoutineNextTargetIncreaseWeight => 'Aumentar carga na próxima';

  @override
  String get gymRoutineNextTargetIncreaseReps =>
      'Aumentar repetições na próxima';

  @override
  String get gymRoutineNextTargetHold => 'Manter — repetir este alvo';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — reduzir a carga';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'subida de reps $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrição';

  @override
  String get nutritionLogFood => 'Registrar comida';

  @override
  String get nutritionCalories => 'Calorias';

  @override
  String get nutritionProtein => 'Proteínas';

  @override
  String get nutritionCarbs => 'Carboidratos';

  @override
  String get nutritionFat => 'Gorduras';

  @override
  String get nutritionWater => 'Água';

  @override
  String get nutritionWaterAdd => 'Adicionar água';

  @override
  String get nutritionWaterRemove => 'Remover água';

  @override
  String get nutritionNoTargets =>
      'Informe sua altura, peso, idade e sexo no app web para ver as metas de calorias e macros.';

  @override
  String get nutritionWeeklyTrend => 'Últimos 7 dias';

  @override
  String nutritionCaloriesLeft(int n) {
    return '$n kcal restantes';
  }

  @override
  String nutritionCaloriesOver(int n) {
    return '$n kcal acima';
  }

  @override
  String get nutritionOnTarget => 'Na meta';

  @override
  String nutritionMacroOver(int n) {
    return '$n acima da meta';
  }

  @override
  String get nutritionMacroReached => 'Meta atingida';

  @override
  String nutritionWaterAmount(String consumed, String target) {
    return '$consumed / $target L';
  }

  @override
  String get nutritionWaterGoalReached => 'Meta atingida';

  @override
  String nutritionWaterRemaining(int n) {
    return '$n ml restantes';
  }

  @override
  String get nutritionWeekOnGoal => 'Na meta';

  @override
  String nutritionWeekUnderGoal(int n) {
    return '$n abaixo da meta/dia';
  }

  @override
  String nutritionWeekOverGoal(int n) {
    return '$n acima da meta/dia';
  }

  @override
  String get nutritionGoalLine => 'Meta diária';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return 'Meta $base + $exercise kcal queimadas hoje';
  }

  @override
  String get dashGymReadinessIncluded =>
      'Suas sessões recentes de musculação entram na sua fadiga.';

  @override
  String get dashGymReadinessExcluded =>
      'A carga da musculação fica de fora do seu preparo para correr.';

  @override
  String get prefsExcludeGymFromReadiness =>
      'Excluir a carga da musculação do preparo para correr';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'Por padrão, as sessões de musculação aumentam sua fadiga e reduzem seu preparo, como uma corrida. Ative isto para que seu condicionamento, fadiga e forma se baseiem apenas nas corridas.';

  @override
  String get nutritionEmptyTitle => 'Nada registrado hoje';

  @override
  String get nutritionEmptyBody =>
      'Registre uma refeição para acompanhar suas calorias e macros.';

  @override
  String get nutritionSlotBreakfast => 'Café da manhã';

  @override
  String get nutritionSlotLunch => 'Almoço';

  @override
  String get nutritionSlotDinner => 'Jantar';

  @override
  String get nutritionSlotSnack => 'Lanche';

  @override
  String get nutritionMealProtein => 'Proteína';

  @override
  String get nutritionMealCarbs => 'Carboidratos';

  @override
  String get nutritionMealFat => 'Gordura';

  @override
  String get nutritionMealItemsHeading => 'Itens';

  @override
  String get nutritionMealNoItems => 'Nada registrado para esta refeição.';

  @override
  String get nutritionMealTrendHeading => 'Últimos 7 dias';

  @override
  String get nutritionDelete => 'Excluir';

  @override
  String get nutritionDeleteEntryTitle => 'Excluir este item?';

  @override
  String nutritionDeleteEntryMessage(String item) {
    return '$item será removido do registro de hoje.';
  }

  @override
  String get nutritionOfflineQueued =>
      'Offline — as alterações serão sincronizadas ao reconectar';

  @override
  String get nutritionOfflineCached => 'Offline — mostrando entradas salvas';

  @override
  String get nutritionLogTitle => 'Registrar comida';

  @override
  String get nutritionSearchHint => 'Buscar um alimento';

  @override
  String get nutritionSearching => 'Buscando…';

  @override
  String get nutritionNoResults =>
      'Sem resultados. Tente outro termo ou insira manualmente abaixo.';

  @override
  String get nutritionSearchFailed =>
      'A busca falhou. Verifique sua conexão e tente novamente ou insira manualmente abaixo.';

  @override
  String get nutritionSearchRetry => 'Tentar busca novamente';

  @override
  String get nutritionSourceOff => 'Open Food Facts';

  @override
  String get nutritionSourceUsda => 'USDA';

  @override
  String get nutritionScanBarcode => 'Escanear código de barras';

  @override
  String get nutritionScanHint =>
      'Aponte a câmera para o código de barras do produto';

  @override
  String get nutritionScanLookingUp => 'Buscando…';

  @override
  String get nutritionScanNotFound =>
      'Nenhum produto encontrado para esse código de barras. Faça uma busca ou insira manualmente.';

  @override
  String get nutritionScanFailed =>
      'Falha ao escanear. Faça uma busca ou insira manualmente.';

  @override
  String get nutritionScanPermissionDenied =>
      'É necessário acesso à câmera para escanear um código de barras. Você ainda pode buscar ou inserir o alimento manualmente.';

  @override
  String get nutritionScanOpenSettings => 'Abrir configurações';

  @override
  String get nutritionSaveFailed =>
      'Não foi possível registrar o alimento. Tente novamente.';

  @override
  String get nutritionMealSlot => 'Refeição';

  @override
  String get nutritionManualEntry => 'Inserir manualmente';

  @override
  String get nutritionItemName => 'Nome do item';

  @override
  String get nutritionPortionGrams => 'Porção (g)';

  @override
  String get nutritionAdd => 'Adicionar';

  @override
  String get nutritionCancel => 'Cancelar';

  @override
  String get nutritionTemplates => 'Modelos de refeição';

  @override
  String get nutritionSaveAsMeal => 'Salvar como refeição';

  @override
  String get nutritionSaveAsMealTitle => 'Salvar como modelo de refeição';

  @override
  String get nutritionTemplateName => 'Nome do modelo';

  @override
  String get nutritionTemplateNamePlaceholder =>
      'ex.: Café da manhã antes da corrida';

  @override
  String get nutritionSaveTemplate => 'Salvar refeição';

  @override
  String get nutritionTemplateSaved => 'Modelo de refeição salvo.';

  @override
  String nutritionTemplateSaveFailed(String error) {
    return 'Não foi possível salvar o modelo: $error';
  }

  @override
  String get nutritionLogTemplate => 'Registrar';

  @override
  String nutritionTemplateLogged(int n, String name) {
    return '$n itens registrados de $name.';
  }

  @override
  String nutritionTemplateLogFailed(String error) {
    return 'Não foi possível registrar o modelo: $error';
  }

  @override
  String nutritionTemplateItems(int n) {
    return '$n itens';
  }

  @override
  String get nutritionDeleteTemplate => 'Excluir';

  @override
  String get nutritionDeleteTemplateTitle => 'Excluir este modelo de refeição?';

  @override
  String nutritionDeleteTemplateMessage(String name) {
    return '$name será removido. As refeições já registradas a partir dele permanecem no seu diário.';
  }

  @override
  String get nutritionRecipes => 'Receitas';

  @override
  String get nutritionSaveAsRecipe => 'Salvar como receita';

  @override
  String get nutritionSaveAsRecipeTitle => 'Salvar como receita';

  @override
  String get nutritionRecipeName => 'Nome da receita';

  @override
  String get nutritionRecipeNamePlaceholder => 'ex. Tigela de frango com arroz';

  @override
  String get nutritionRecipeServings => 'Porções';

  @override
  String get nutritionRecipeServingsHint =>
      'Os ingredientes são somados e depois divididos pelas porções. Registrar uma porção adiciona uma única entrada com os macros combinados.';

  @override
  String get nutritionSaveRecipe => 'Salvar receita';

  @override
  String get nutritionRecipeSaved => 'Receita salva.';

  @override
  String nutritionRecipeSaveFailed(String error) {
    return 'Não foi possível salvar a receita: $error';
  }

  @override
  String get nutritionLogRecipe => 'Registrar';

  @override
  String nutritionRecipeLogged(int n, String name) {
    return '$name registrada ($n porção).';
  }

  @override
  String nutritionRecipeLogFailed(String error) {
    return 'Não foi possível registrar a receita: $error';
  }

  @override
  String nutritionRecipeMeta(int n, num servings) {
    final intl.NumberFormat servingsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String servingsString = servingsNumberFormat.format(servings);

    return '$n ingredientes · $servingsString porções';
  }

  @override
  String get nutritionDeleteRecipe => 'Excluir';

  @override
  String get nutritionDeleteRecipeTitle => 'Excluir esta receita?';

  @override
  String nutritionDeleteRecipeMessage(String name) {
    return '$name será removida. As refeições já registradas a partir dela permanecem no seu diário.';
  }

  @override
  String get sessionTitle => 'Sessões';

  @override
  String get sessionEmpty => 'Ainda não há planos de sessão.';

  @override
  String get sessionEmptyHint =>
      'Crie na web uma sequência reutilizável de yoga, pilates ou aula.';

  @override
  String get sessionUntitled => 'Sessão sem título';

  @override
  String get sessionNotFound => 'Plano de sessão não encontrado.';

  @override
  String get sessionMakePublic => 'Tornar público';

  @override
  String get sessionMakePrivate => 'Tornar privado';

  @override
  String get sessionVisibilityError =>
      'Não foi possível alterar a visibilidade.';

  @override
  String get sessionSteps => 'Sequência';

  @override
  String sessionStepHold(Object name, Object seconds) {
    return '$name · sustentar ${seconds}s';
  }

  @override
  String sessionStepReps(Object name, Object reps) {
    return '$name · $reps reps.';
  }

  @override
  String sessionStepFlow(Object name, Object seconds) {
    return '$name · flow ${seconds}s';
  }

  @override
  String sessionSideLeft(Object name) {
    return '$name (esquerda)';
  }

  @override
  String sessionSideRight(Object name) {
    return '$name (direita)';
  }

  @override
  String sessionEstDuration(Object minutes) {
    return '~ $minutes min';
  }

  @override
  String get gymSessionStart => 'Iniciar sessão';

  @override
  String gymSessionStep(Object exercise, Object set, Object total) {
    return '$exercise · série $set de $total';
  }

  @override
  String get gymSessionComplete => 'Sessão concluída';

  @override
  String get gymSessionSkipSet => 'Pular série';

  @override
  String get gymSessionRewind => 'Anterior';

  @override
  String get gymSessionAbandon => 'Abandonar';

  @override
  String get gymSessionFinish => 'Concluir';

  @override
  String get gymSessionDiscardTitle => 'Descartar a sessão?';

  @override
  String get gymSessionDiscardBody =>
      'Seu progresso nesta sessão não será salvo.';

  @override
  String get gymSessionDiscardConfirm => 'Descartar';

  @override
  String get gymSessionSaved => 'Treino salvo';

  @override
  String get gymSessionSaveFailed => 'Não foi possível salvar o treino';

  @override
  String gymSessionSetProgress(Object done, Object total) {
    return '$done/$total';
  }

  @override
  String get gymSessionLogSet => 'Concluir série';

  @override
  String get gymSessionRest => 'Descanso';

  @override
  String gymSessionRestRemaining(Object seconds) {
    return 'Descanso ${seconds}s';
  }

  @override
  String get gymSessionRestSkip => 'Pular descanso';

  @override
  String get gymSessionTarget => 'Meta';

  @override
  String gymReviewAdherence(Object pct) {
    return '$pct% de cumprimento';
  }

  @override
  String get gymReviewVerdictCompleted => 'Concluída';

  @override
  String get gymReviewVerdictPartial => 'Parcialmente feita';

  @override
  String get gymReviewVerdictAbandoned => 'Abandonada';

  @override
  String get gymReviewStatusHit => 'Cumprido';

  @override
  String get gymReviewStatusPartial => 'Parcial';

  @override
  String get gymReviewStatusMissed => 'Não feito';

  @override
  String get gymReviewStatusExtra => 'Extra';

  @override
  String get sessionRunStart => 'Iniciar sessão';

  @override
  String sessionRunStep(Object name) {
    return '$name';
  }

  @override
  String get sessionRunDone => 'Feito';

  @override
  String get sessionRunSkip => 'Pular';

  @override
  String get sessionRunPause => 'Pausar';

  @override
  String get sessionRunResume => 'Retomar';

  @override
  String get sessionRunAbandon => 'Abandonar';

  @override
  String get sessionRunFinish => 'Concluir';

  @override
  String sessionRunRemaining(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get sessionRunComplete => 'Sessão concluída';

  @override
  String get sessionRunSaved => 'Sessão salva';

  @override
  String get sessionRunSaveFailed => 'Não foi possível salvar a sessão';

  @override
  String get sessionRunDiscardTitle => 'Descartar a sessão?';

  @override
  String get sessionRunDiscardBody =>
      'Seu progresso nesta sessão não será salvo.';

  @override
  String get sessionRunDiscardConfirm => 'Descartar';

  @override
  String get sessionRunVerdictCompleted => 'Concluída';

  @override
  String get sessionRunVerdictPartial => 'Parcialmente feita';

  @override
  String get sessionRunVerdictAbandoned => 'Abandonada';

  @override
  String sessionRunStepCount(int index, int total) {
    return 'Etapa $index de $total';
  }

  @override
  String get sessionRunSwitchSides => 'Troque de lado';

  @override
  String get coachingTitle => 'Treinamento';

  @override
  String get coachingLede =>
      'Treine atletas compartilhando um link de convite e acompanhe o treino deles. Ou siga o seu próprio treinador aqui.';

  @override
  String get coachingCancel => 'Cancelar';

  @override
  String get coachingMyAthletes => 'Meus atletas';

  @override
  String get coachingMyAthletesSub => 'Corredores que aceitaram seu convite';

  @override
  String get coachingInviteAnAthlete => 'Convidar um atleta';

  @override
  String get coachingCreating => 'Criando…';

  @override
  String get coachingPendingInvite => 'Convite pendente';

  @override
  String coachingPendingInviteSub(String date) {
    return 'Criado em $date · ainda não aceito';
  }

  @override
  String get coachingCopyLink => 'Copiar link';

  @override
  String get coachingShareLink => 'Compartilhar link';

  @override
  String get coachingRevoke => 'Revogar';

  @override
  String get coachingNoAthletes =>
      'Nenhum atleta ainda. Convide um para começar.';

  @override
  String get coachingRosterTitle => 'Lista de atletas';

  @override
  String get coachingRosterSubtitle =>
      'Todos os seus atletas num relance — carga, adesão ao plano e risco de lesão.';

  @override
  String get coachingRosterNeverRun => 'Nenhuma corrida ainda';

  @override
  String get coachingRosterNoPlan => 'Sem plano';

  @override
  String get coachingRosterRiskInsufficient => 'Novo';

  @override
  String get coachingRosterRiskLow => 'Baixo';

  @override
  String get coachingRosterRiskOptimal => 'Ótimo';

  @override
  String get coachingRosterRiskElevated => 'Elevado';

  @override
  String get coachingRosterRiskHigh => 'Alto';

  @override
  String get coachingRunner => 'Corredor';

  @override
  String coachingCoachingSince(String date) {
    return 'Treinando desde $date';
  }

  @override
  String get coachingReview => 'Revisar';

  @override
  String get coachingRemove => 'Remover';

  @override
  String get coachingMyCoaches => 'Meus treinadores';

  @override
  String get coachingMyCoachesSub => 'Treinadores que podem ver seu treino';

  @override
  String get coachingNoCoaches =>
      'Você ainda não aceitou o convite de um treinador.';

  @override
  String get coachingCoach => 'Treinador';

  @override
  String coachingLinkedSince(String date) {
    return 'Vinculado desde $date';
  }

  @override
  String get coachingLeave => 'Sair';

  @override
  String get coachingInviteLinkCopied => 'Link de convite copiado';

  @override
  String get coachingThisAthlete => 'este atleta';

  @override
  String get coachingThisCoach => 'este treinador';

  @override
  String get coachingRevokeTitle => 'Revogar convite?';

  @override
  String get coachingRevokeBody =>
      'O link de convite deixará de funcionar. Você sempre pode criar um novo.';

  @override
  String get coachingRemoveAthleteTitle => 'Remover atleta?';

  @override
  String coachingRemoveAthleteBody(String name) {
    return 'Parar de treinar $name? Você perderá o acesso às corridas e planos dele.';
  }

  @override
  String get coachingLeaveCoachTitle => 'Sair do treinador?';

  @override
  String coachingLeaveCoachBody(String name) {
    return 'Parar de compartilhar seu treino com $name?';
  }

  @override
  String coachingLoadError(String error) {
    return 'Não foi possível carregar o treinamento: $error';
  }

  @override
  String coachingCreateInviteError(String error) {
    return 'Não foi possível criar o convite: $error';
  }

  @override
  String coachingRevokeInviteError(String error) {
    return 'Não foi possível revogar o convite: $error';
  }

  @override
  String coachingRemoveAthleteError(String error) {
    return 'Não foi possível remover o atleta: $error';
  }

  @override
  String coachingEndLinkError(String error) {
    return 'Não foi possível encerrar o vínculo: $error';
  }

  @override
  String get coachingAthleteAthleteFallback => 'Atleta';

  @override
  String get coachingAthleteRunnerFallback => 'Corredor';

  @override
  String coachingAthleteCoachingSince(String date) {
    return 'Treinando desde $date';
  }

  @override
  String get coachingAthletePlanCompliance => 'Cumprimento do plano';

  @override
  String get coachingAthleteNoActivePlan => 'Sem plano de treino ativo.';

  @override
  String get coachingAthleteAssignTitle => 'Atribuir um plano';

  @override
  String coachingAthleteAssignHint(String name) {
    return 'Escolha um dos seus planos para atribuir a $name.';
  }

  @override
  String get coachingAthleteAssignSelectLabel => 'Plano';

  @override
  String get coachingAthleteAssignSelectPlaceholder => 'Escolha um plano…';

  @override
  String get coachingAthleteAssignStartLabel => 'Data de início';

  @override
  String get coachingAthleteAssigning => 'Atribuindo…';

  @override
  String get coachingAthleteAssignButton => 'Atribuir plano';

  @override
  String get coachingAthleteAssignNoPlans =>
      'Crie primeiro um plano de treino, depois você poderá atribuí-lo aos seus atletas.';

  @override
  String get coachingAthleteAssignedByYou => 'Atribuído por você';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'Este atleta já tem um plano ativo. Ele precisará concluí-lo ou encerrá-lo antes que você possa atribuir um novo.';

  @override
  String get coachingAthleteComplete => 'concluído';

  @override
  String coachingAthleteDoneCount(int done, int total) {
    return '$done de $total feitos';
  }

  @override
  String coachingAthleteMissedCount(int n) {
    return '$n perdidos';
  }

  @override
  String get coachingAthleteStatusDone => 'Feito';

  @override
  String get coachingAthleteStatusMissed => 'Perdido';

  @override
  String get coachingAthleteStatusUpcoming => 'Próximo';

  @override
  String get coachingAthleteRecentRuns => 'Corridas recentes';

  @override
  String get coachingAthleteNoRunsYet => 'Nenhuma corrida registrada ainda.';

  @override
  String get coachingAthletePrivate => 'Privado';

  @override
  String coachingAthleteAssignSuccess(String name) {
    return 'Plano atribuído a $name';
  }

  @override
  String coachingAthleteLoadError(String error) {
    return 'Não foi possível carregar o atleta: $error';
  }

  @override
  String get routeMarkerHeading => 'Marcadores do percurso';

  @override
  String get routeMarkerAdd => 'Adicionar marcador';

  @override
  String get routeMarkerEmpty =>
      'Nenhum marcador ainda. Adicione postos de apoio, cortes de tempo e mais ao longo do percurso.';

  @override
  String get routeMarkerEdit => 'Editar marcador';

  @override
  String get routeMarkerDelete => 'Excluir';

  @override
  String get routeMarkerCancel => 'Cancelar';

  @override
  String get routeMarkerSave => 'Salvar';

  @override
  String get routeMarkerSaving => 'Salvando…';

  @override
  String get routeMarkerKindLabel => 'Tipo';

  @override
  String get routeMarkerNameLabel => 'Nome';

  @override
  String get routeMarkerNamePlaceholder => 'ex.: Apoio 2';

  @override
  String get routeMarkerServicesLabel => 'Serviços';

  @override
  String get routeMarkerCutoffLabel => 'Horário de corte';

  @override
  String get routeMarkerNoteLabel => 'Nota';

  @override
  String get routeMarkerTapToPlace =>
      'Toque no mapa para posicionar este marcador.';

  @override
  String get routeMarkerPlaced =>
      'Posicionado. Toque no mapa novamente para movê-lo.';

  @override
  String routeMarkerCutoffAt(String time) {
    return 'Corte $time';
  }

  @override
  String get routeMarkerLabelRequired => 'Dê um nome ao marcador.';

  @override
  String get routeMarkerPlaceRequired =>
      'Posicione o marcador no mapa primeiro.';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Não foi possível salvar o marcador: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Não foi possível excluir o marcador: $error';
  }

  @override
  String get routeMarkerDeleteConfirmTitle => 'Excluir marcador?';

  @override
  String get routeMarkerDeleteConfirmMessage =>
      'Isso remove o marcador do percurso permanentemente.';

  @override
  String get routeMarkerKindAidStation => 'Posto de apoio';

  @override
  String get routeMarkerKindCutoff => 'Corte de tempo';

  @override
  String get routeMarkerKindCrewAccess => 'Equipe / estacionamento';

  @override
  String get routeMarkerKindHazard => 'Perigo';

  @override
  String get routeMarkerKindNote => 'Nota';

  @override
  String get routeMarkerKindClimb => 'Subida';

  @override
  String get routeMarkerKindCustom => 'Personalizado';

  @override
  String get routeMarkerServiceWater => 'Água';

  @override
  String get routeMarkerServiceFood => 'Comida';

  @override
  String get routeMarkerServiceMedical => 'Médico';

  @override
  String get routeMarkerServiceToilets => 'Banheiros';

  @override
  String get routeMarkerServiceDropBag => 'Drop bag';

  @override
  String get clubFormEditTitle => 'Editar clube';

  @override
  String get clubEditorWebsite => 'Site';

  @override
  String get clubEditorInstagram => 'Instagram';

  @override
  String get clubEditorStrava => 'Strava';

  @override
  String get clubEditorFacebook => 'Facebook';

  @override
  String get clubEditorSaveChanges => 'Salvar alterações';

  @override
  String get clubDetailVisitWebsite => 'Visite nosso site';

  @override
  String get clubDetailEditClub => 'Editar clube';

  @override
  String get roadbookTitle => 'Roadbook';

  @override
  String get roadbookCrewSheet => 'Roadbook (planilha da equipe)';

  @override
  String get roadbookGoalTime => 'Tempo-alvo';

  @override
  String get roadbookStartTime => 'Horário de largada';

  @override
  String get roadbookEffort => 'Esforço';

  @override
  String get roadbookEven => 'Uniforme';

  @override
  String get roadbookStart => 'Largada';

  @override
  String get roadbookFinish => 'Chegada';

  @override
  String get roadbookShare => 'Compartilhar';

  @override
  String get roadbookNoMarkers =>
      'Adicione marcadores ao percurso para criar um roadbook.';

  @override
  String get roadbookAddElevation => 'Adicionar altimetria';

  @override
  String get roadbookElevationUnavailable =>
      'Dados de altimetria indisponíveis para este percurso';

  @override
  String roadbookSummary(String distance, String vert, String time) {
    return '$distance · $vert de ganho · meta $time';
  }

  @override
  String get roadbookFuel => 'Abastecimento';

  @override
  String get roadbookHeat => 'Calor';

  @override
  String get roadbookCarbs => 'Carboidratos';

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
    return 'levar $gels géis · $fluid ml';
  }

  @override
  String get checkpointCheckinAction => 'Check-in no posto de controle';

  @override
  String get checkpointCheckinTitle => 'Check-in no posto de hidratação';

  @override
  String get checkpointSyncNow => 'Sincronizar agora';

  @override
  String get checkpointPending => 'Não sincronizado';

  @override
  String get checkpointLoadFailed =>
      'Não foi possível carregar os postos de controle';

  @override
  String get checkpointRetry => 'Tentar novamente';

  @override
  String get checkpointNone =>
      'Esta corrida ainda não tem postos de controle. Adicione-os na web antes de a equipe registrar os corredores.';

  @override
  String get checkpointPickLabel => 'POSTO DE CONTROLE';

  @override
  String get checkpointBibLabel => 'Número de peito';

  @override
  String get checkpointBibHint => 'Escaneie ou digite um número';

  @override
  String get checkpointBibRequired => 'Digite primeiro um número de peito';

  @override
  String get checkpointStampIn => 'Registrar ENTRADA';

  @override
  String get checkpointStampOut => 'Registrar SAÍDA';

  @override
  String checkpointStampedIn(String bib) {
    return 'Número $bib com entrada registrada';
  }

  @override
  String checkpointStampedOut(String bib) {
    return 'Número $bib com saída registrada';
  }

  @override
  String get checkpointStampFailed => 'Não foi possível salvar esse registro';

  @override
  String checkpointLoggedHere(int count) {
    return 'REGISTRADOS AQUI ($count)';
  }

  @override
  String get checkpointNoneLoggedHere =>
      'Ainda não há corredores registrados neste posto de controle.';

  @override
  String checkpointBibRow(String bib) {
    return 'Número $bib';
  }

  @override
  String checkpointInOut(String inTime, String outTime) {
    return 'Entrada $inTime · Saída $outTime';
  }

  @override
  String get checkpointWeighInTitle => 'Pesagem';

  @override
  String get checkpointWeighInConsentBlurb =>
      'O peso corporal e as notas de retenção médica são dados de saúde, registrados apenas com o consentimento do corredor e visíveis apenas para os oficiais da corrida.';

  @override
  String get checkpointWeighInConsent =>
      'O corredor consente o registro de dados de saúde';

  @override
  String get checkpointWeighInWeightKg => 'Peso corporal (kg)';

  @override
  String get checkpointMedicalHold => 'Colocar em retenção médica';

  @override
  String get checkpointWeighInSave => 'Salvar e registrar';

  @override
  String get checkpointCancel => 'Cancelar';

  @override
  String get challengesTitle => 'Desafios';

  @override
  String get challengesMyChallenges => 'Meus desafios';

  @override
  String get challengesBrowse => 'Explorar';

  @override
  String get challengesEmpty => 'Nenhum desafio ainda.';

  @override
  String get challengesBrowseEmpty =>
      'Nenhum desafio público para entrar no momento.';

  @override
  String get challengesJoin => 'Entrar';

  @override
  String get challengesLeave => 'Sair';

  @override
  String get challengesDelete => 'Excluir';

  @override
  String get challengesMetricDistance => 'Distância';

  @override
  String get challengesMetricDuration => 'Tempo';

  @override
  String get challengesMetricVert => 'Elevação';

  @override
  String get challengesMetricActivityCount => 'Atividades';

  @override
  String get challengesMetricStreak => 'Dias ativos';

  @override
  String challengesGoalProgress(String value, String goal) {
    return '$value de $goal';
  }

  @override
  String get challengesProgressComplete => 'Concluído';

  @override
  String challengesEndsIn(int n) {
    return 'Termina em $n dias';
  }

  @override
  String get challengesEndsToday => 'Termina hoje';

  @override
  String get challengesEnded => 'Encerrado';

  @override
  String get challengesLeaderboard => 'Ranking';

  @override
  String get challengesLeaderboardEmpty => 'Nenhum progresso registrado ainda.';

  @override
  String challengesLeaderboardRank(int rank) {
    return '#$rank';
  }

  @override
  String challengesParticipants(int n) {
    return '$n participantes';
  }

  @override
  String get challengesBadgeEarned => 'Emblema conquistado';

  @override
  String challengesUnitDays(int n) {
    return '$n dias';
  }

  @override
  String challengesUnitActivities(int n) {
    return '$n';
  }

  @override
  String get challengesLeaveConfirmTitle => 'Sair do desafio?';

  @override
  String get challengesLeaveConfirm =>
      'Seu progresso neste desafio deixará de ser registrado.';

  @override
  String get challengesDeleteConfirmTitle => 'Excluir desafio?';

  @override
  String get challengesDeleteConfirm =>
      'Isso remove o desafio e o ranking para todos. Não pode ser desfeito.';

  @override
  String get challengesNotFound => 'Este desafio não está disponível.';

  @override
  String get challengesJoinFailed => 'Não foi possível entrar no desafio.';

  @override
  String get challengesLeaveFailed => 'Não foi possível sair do desafio.';

  @override
  String get challengesLoadFailed => 'Não foi possível carregar os desafios.';

  @override
  String fundraiserRaisedOfGoal(String raised, String goal) {
    return '$raised de $goal arrecadados';
  }

  @override
  String fundraiserDonorCount(int count) {
    return '$count apoiadores';
  }

  @override
  String get fundraiserOverGoal => 'Meta superada!';

  @override
  String get fundraiserClosed => 'Esta campanha está encerrada.';

  @override
  String get fundraiserFeedTitle => 'Apoiadores recentes';

  @override
  String get fundraiserFeedEmpty => 'Seja o primeiro a doar.';

  @override
  String get fundraiserAnonymous => 'Anônimo';

  @override
  String get fundraiserDonateOnWeb => 'Doar na web';

  @override
  String get racesTitle => 'Calendário de corridas';

  @override
  String get racesSearchPlaceholder => 'Pesquisar corridas por nome…';

  @override
  String get racesNearPlace => 'Perto de um local…';

  @override
  String racesKmAway(String distance) {
    return 'a $distance';
  }

  @override
  String get racesDistanceAny => 'Qualquer distância';

  @override
  String get racesDistance5k => '5K';

  @override
  String get racesDistance10k => '10K';

  @override
  String get racesDistanceHalf => 'Meia';

  @override
  String get racesDistanceMarathon => 'Maratona';

  @override
  String get racesDistanceUltra => 'Ultra';

  @override
  String get racesRegister => 'Inscrever-se';

  @override
  String get racesViewResults => 'Ver resultados';

  @override
  String get racesImportResult => 'Importar meu resultado';

  @override
  String get racesSubmitRace => 'Adicionar uma corrida';

  @override
  String get racesUnverified => 'Não verificada';

  @override
  String get racesEmpty =>
      'Ainda não há corridas que correspondam a esses filtros.';

  @override
  String get racesSearchFailed =>
      'Não foi possível carregar as corridas. Verifique sua conexão e tente novamente.';

  @override
  String racesMatchPrompt(String name) {
    return 'Foi esta a $name? Importe seu resultado oficial.';
  }

  @override
  String get racesMatchConfirm => 'Importar resultado';

  @override
  String get racesMatchDismiss => 'Não é esta corrida';

  @override
  String get racesImported => 'Resultado oficial importado.';

  @override
  String get racesOfficialResult => 'Resultado oficial';

  @override
  String get racesChipTime => 'Tempo líquido';

  @override
  String get racesGunTime => 'Tempo bruto';

  @override
  String get racesOverallPlace => 'Classificação geral';

  @override
  String get racesAgeGroupPlace => 'Classificação por categoria';

  @override
  String get racesAgeGroup => 'Categoria de idade';

  @override
  String get racesBib => 'Número de peito';

  @override
  String get racesPasteResultHint =>
      'Insira os detalhes da sua chegada a partir da página de resultados da corrida.';

  @override
  String get racesSave => 'Salvar';

  @override
  String get racesCancel => 'Cancelar';

  @override
  String get racesEditorTitle => 'Adicionar uma corrida';

  @override
  String get racesFieldName => 'Nome da corrida';

  @override
  String get racesFieldDate => 'Data';

  @override
  String get racesFieldDistance => 'Distância (metros)';

  @override
  String get racesFieldLocation => 'Local';

  @override
  String get racesFieldEntryUrl => 'Link de inscrição';

  @override
  String get racesFieldResultsUrl => 'Link de resultados';

  @override
  String get racesSubmitFailed =>
      'Não foi possível salvar a corrida. Tente novamente.';

  @override
  String get racesImportFailed =>
      'Não foi possível importar o resultado. Tente novamente.';

  @override
  String get navRaces => 'Corridas';

  @override
  String get integrationsRunsignup => 'RunSignUp';

  @override
  String get integrationsRunsignupConnect =>
      'Importe resultados de corridas do RunSignUp.';

  @override
  String get integrationsRunsignupOpen => 'Abrir o calendário de corridas';

  @override
  String get integrationsRunsignupUnavailable =>
      'A importação do RunSignUp ainda não está disponível. O parkrun e a colagem manual continuam funcionando.';

  @override
  String get routeConditionsTitle => 'Condições';

  @override
  String get routeConditionsReport => 'Relatar condição';

  @override
  String get routeConditionsReporting => 'Enviando…';

  @override
  String get routeConditionsReported => 'Condição relatada';

  @override
  String get routeConditionsReportFailed =>
      'Não foi possível relatar a condição';

  @override
  String get routeConditionsEmpty => 'Ainda não há relatos.';

  @override
  String get routeConditionsLoading => 'Carregando…';

  @override
  String get routeConditionsCancel => 'Cancelar';

  @override
  String get routeConditionsDelete => 'Excluir';

  @override
  String get routeConditionsDeleteTitle => 'Excluir relato?';

  @override
  String get routeConditionsDeleteConfirm =>
      'Isso remove o relato permanentemente.';

  @override
  String get routeConditionsDeleteFailed => 'Não foi possível excluir o relato';

  @override
  String get routeConditionsKindLabel => 'Condição';

  @override
  String get routeConditionsSeverityLabel => 'Gravidade';

  @override
  String get routeConditionsNoteLabel => 'Nota';

  @override
  String get routeConditionsNotePlaceholder =>
      'O que o próximo corredor vai encontrar?';

  @override
  String routeConditionsAtDistance(String distance) {
    return 'em $distance';
  }

  @override
  String get routeConditionMuddy => 'Lamacento';

  @override
  String get routeConditionFlooded => 'Alagado';

  @override
  String get routeConditionSnowIce => 'Neve / gelo';

  @override
  String get routeConditionOvergrown => 'Coberto de vegetação';

  @override
  String get routeConditionClosed => 'Fechado';

  @override
  String get routeConditionHazard => 'Perigo';

  @override
  String get routeConditionClear => 'Livre';

  @override
  String get routeConditionOther => 'Outro';

  @override
  String get routeConditionSeverityInfo => 'Info';

  @override
  String get routeConditionSeverityCaution => 'Cuidado';

  @override
  String get routeConditionSeverityImpassable => 'Intransitável';

  @override
  String get prefTurnByTurnCues => 'Instruções de voz curva a curva';

  @override
  String get prefTurnByTurnCuesSubtitle =>
      'Direções faladas ao seguir uma rota salva';

  @override
  String ttsTurnLeftIn(String distance) {
    return 'Em $distance, vire à esquerda';
  }

  @override
  String ttsTurnRightIn(String distance) {
    return 'Em $distance, vire à direita';
  }

  @override
  String get ttsTurnLeftNow => 'Vire à esquerda';

  @override
  String get ttsTurnRightNow => 'Vire à direita';

  @override
  String get ttsSlightLeft => 'Mantenha-se à esquerda';

  @override
  String get ttsSlightRight => 'Mantenha-se à direita';

  @override
  String get ttsUturn => 'Faça um retorno';

  @override
  String routeOfflinePackDownloading(int done, int total) {
    return 'Salvando mapa: $done / $total';
  }

  @override
  String get routeOfflinePackReady => 'Mapa salvo para uso offline';

  @override
  String routeOfflinePackPartial(int done, int total) {
    return 'Mapa parcialmente salvo ($done / $total) — tentar de novo';
  }

  @override
  String get routeOfflinePackTooLarge =>
      'Esta rota é grande demais para salvar offline';

  @override
  String get badgesSectionTitle => 'Conquistas';

  @override
  String get badgesSectionSubtitle => 'Marcos que você alcançou';

  @override
  String get badgesEmpty => 'Ainda sem medalhas — continue correndo.';

  @override
  String get badgesEmptyOther => 'Ainda não há medalhas públicas.';

  @override
  String badgesEarnedOn(String date) {
    return 'Conquistada em $date';
  }

  @override
  String badgesFeedEarned(String name, String badge) {
    return '$name conquistou a medalha $badge';
  }

  @override
  String get badgesARunner => 'Um corredor';

  @override
  String get badgesTierBronze => 'Bronze';

  @override
  String get badgesTierSilver => 'Prata';

  @override
  String get badgesTierGold => 'Ouro';

  @override
  String get badgesTierPlatinum => 'Platina';

  @override
  String get badgesDistanceSingle5kLabel => 'Primeiros 5 km';

  @override
  String get badgesDistanceSingle5kDesc => 'Correu 5 km em uma única corrida';

  @override
  String get badgesDistanceSingleHalfLabel => 'Meia maratona';

  @override
  String get badgesDistanceSingleHalfDesc =>
      'Correu 21,1 km em uma única corrida';

  @override
  String get badgesDistanceSingleMarathonLabel => 'Maratona';

  @override
  String get badgesDistanceSingleMarathonDesc =>
      'Correu 42,2 km em uma única corrida';

  @override
  String get badgesDistanceSingleUltraLabel => 'Ultra';

  @override
  String get badgesDistanceSingleUltraDesc =>
      'Correu 50 km ou mais em uma única corrida';

  @override
  String get badgesDistanceLifetime100Label => 'Clube dos 100 km';

  @override
  String get badgesDistanceLifetime100Desc => '100 km registrados no total';

  @override
  String get badgesDistanceLifetime500Label => '500 km';

  @override
  String get badgesDistanceLifetime500Desc => '500 km registrados no total';

  @override
  String get badgesDistanceLifetime1000Label => 'Clube dos 1.000 km';

  @override
  String get badgesDistanceLifetime1000Desc => '1.000 km registrados no total';

  @override
  String get badgesDistanceLifetime5000Label => '5.000 km';

  @override
  String get badgesDistanceLifetime5000Desc => '5.000 km registrados no total';

  @override
  String get badgesStreak7Label => 'Sequência semanal';

  @override
  String get badgesStreak7Desc => 'Correu 7 dias seguidos';

  @override
  String get badgesStreak30Label => 'Sequência mensal';

  @override
  String get badgesStreak30Desc => 'Correu 30 dias seguidos';

  @override
  String get badgesStreak100Label => 'Sequência de cem';

  @override
  String get badgesStreak100Desc => 'Correu 100 dias seguidos';

  @override
  String get badgesStreak365Label => 'Sequência anual';

  @override
  String get badgesStreak365Desc => 'Correu 365 dias seguidos';

  @override
  String get badgesPr1Label => 'Primeiro recorde';

  @override
  String get badgesPr1Desc => 'Estabeleceu seu primeiro recorde pessoal';

  @override
  String get badgesPr3Label => 'Recorde triplo';

  @override
  String get badgesPr3Desc => 'Detém recordes pessoais em 3 distâncias';

  @override
  String get badgesPr5Label => 'Colecionador de recordes';

  @override
  String get badgesPr5Desc => 'Detém recordes pessoais em todas as distâncias';

  @override
  String get badgesPlan1Label => 'Plano concluído';

  @override
  String get badgesPlan1Desc => 'Concluiu um plano de treino';

  @override
  String get badgesPlan3Label => 'Triplo concluído';

  @override
  String get badgesPlan3Desc => 'Concluiu 3 planos de treino';

  @override
  String get badgesPlan10Label => 'Veterano de planos';

  @override
  String get badgesPlan10Desc => 'Concluiu 10 planos de treino';

  @override
  String get racePredictorTitle => 'Previsão de tempo de prova';

  @override
  String racePredictorAnchoredOn(String distance, String time) {
    return 'A partir do seu esforço de $distance em $time';
  }

  @override
  String get racePredictorColDistance => 'Distância';

  @override
  String get racePredictorColTime => 'Tempo';

  @override
  String get racePredictorColPace => 'Ritmo';

  @override
  String get racePredictorColConfidence => 'Confiança';

  @override
  String get racePredictorConfidenceHigh => 'Alta';

  @override
  String get racePredictorConfidenceModerate => 'Média';

  @override
  String get racePredictorConfidenceLow => 'Baixa';

  @override
  String get racePredictorConfReasonSimilar =>
      'Baseado em esforços recentes próximos a esta distância.';

  @override
  String get racePredictorConfReasonExtrapolated =>
      'Extrapolado por uma grande diferença de distância — trate como uma estimativa.';

  @override
  String get racePredictorConfReasonStale =>
      'Ancorado em um esforço de algumas semanas atrás.';

  @override
  String get racePredictorConfReasonLimited =>
      'Baseado em dados recentes limitados.';

  @override
  String get racePredictorFootnote =>
      'Equivalência de Riegel a partir do seu melhor esforço recente, ponderada pela recência. Distâncias mais próximas são mais confiáveis.';
}
