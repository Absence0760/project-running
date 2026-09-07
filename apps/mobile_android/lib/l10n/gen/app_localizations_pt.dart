// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get clubInviteEnterCodeError =>
      'Introduza o código de convite do seu link.';

  @override
  String get clubInviteJoinedBanner => 'Entrou no clube.';

  @override
  String get clubInviteTitle => 'Entrar no clube';

  @override
  String get clubInviteIntro =>
      'Cole o código de convite que o administrador do clube partilhou consigo.';

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
  String recapMonthShareHeadline(Object period) {
    return 'O meu $period na corrida:';
  }

  @override
  String recapMonthShareSubject(Object period) {
    return 'Retrospectiva $period';
  }

  @override
  String get recapTitle => 'Ano na corrida';

  @override
  String get recapMonthTitle => 'Mês na corrida';

  @override
  String get recapPeriodYear => 'Ano';

  @override
  String get recapPeriodMonth => 'Mês';

  @override
  String get recapShareTooltip => 'Partilhar retrospectiva';

  @override
  String get recapPublishAndShare => 'Publicar e partilhar link';

  @override
  String get recapPublishFailed =>
      'Não foi possível publicar o resumo. Tente novamente.';

  @override
  String get recapPrevYear => 'Ano anterior';

  @override
  String get recapNextYear => 'Próximo ano';

  @override
  String get recapPrevMonth => 'Mês anterior';

  @override
  String get recapNextMonth => 'Próximo mês';

  @override
  String recapNoRunsForPeriod(Object period) {
    return 'Nenhuma corrida para a retrospectiva de $period.';
  }

  @override
  String recapNoRunsYetInPeriod(Object period) {
    return 'Ainda não há corridas em $period. Registe uma para ver a sua retrospectiva.';
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
  String get routePickerClearSearchTooltip => 'Limpar pesquisa';

  @override
  String get routePickerSearchHint => 'Procurar rotas por nome…';

  @override
  String get routePickerEmptyNoRoutes => 'Nenhuma rota guardada ainda';

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
    return 'A solicitar permissão do $label...';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return 'Permissão do $label negada';
  }

  @override
  String get importHealthReadingWorkouts => 'A ler treinos...';

  @override
  String importHealthFailed(Object label, Object error) {
    return 'Falha na importação do $label: $error';
  }

  @override
  String get importStatusSavingLocally => 'A guardar localmente...';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return '$count duplicata(s) ignorada(s) já importada(s) de outra fonte';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return '$done de $total guardadas localmente';
  }

  @override
  String get importStatusSyncingToCloud => 'A sincronizar com a nuvem...';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return '$done de $total sincronizadas';
  }

  @override
  String get importStatusReadingCsv => 'A ler CSV...';

  @override
  String importCsvFailed(Object error) {
    return 'Falha na importação do CSV: $error';
  }

  @override
  String get importStatusRestoringBackup => 'A restaurar backup...';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return '$runs corridas · $tracks trajetos · $routes rotas restauradas';
  }

  @override
  String importBackupFailed(Object error) {
    return 'Falha ao restaurar o backup: $error';
  }

  @override
  String get importStatusReadingExport => 'A ler exportação...';

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
  String get importStravaHowToHeader =>
      'Como obter a sua exportação do Strava:';

  @override
  String get importStravaHowToSteps =>
      '1. Abra o Strava → Definições → Minha conta\n2. Desloque até \"Transferir ou eliminar a sua conta\"\n3. Toque em \"Começar\" → \"Solicitar o seu ficheiro\"\n4. receberá um e-mail com um link de download em algumas horas\n5. Transfira o .zip e toque em Importar abaixo';

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
      'Reimporte um CSV exportado em Definições — apenas corridas, sem GPS';

  @override
  String get importCsvCardDescription =>
      'Cada linha do CSV vira uma corrida manual (data, distância, duração, fonte). O trajeto no mapa não está no CSV, então as corridas importadas não terão linha de rota.';

  @override
  String get importCsvButton => 'Importar CSV';

  @override
  String get importBackupCardTitle => 'ZIP de backup completo';

  @override
  String get importBackupCardSubtitle =>
      'Restaure corridas, rotas e trajetos de GPS de um ficheiro de backup';

  @override
  String get importBackupCardDescription =>
      'Ida e volta sem perdas. Funciona sem login — as corridas restauradas sincronizam com a sua conta na próxima vez que entrar. Faça um backup em Definições → Backup completo.';

  @override
  String get importBackupButton => 'Restaurar ZIP de backup';

  @override
  String get importErrorsHeader => 'Erros';

  @override
  String importErrorsMore(Object count) {
    return '... e mais $count';
  }

  @override
  String importFailuresHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count atividades não foram importadas',
      one: '1 atividade não foi importada',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresIntro =>
      'Volte a executar a importação para tentar novamente — o que já entrou é ignorado, por isso nada é duplicado.';

  @override
  String importFailuresTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mais $count falhas não foram registadas.',
      one: 'Mais 1 falha não foi registada.',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresShowDetail => 'Ver cada atividade';

  @override
  String get importFailuresShare => 'Partilhar relatório (CSV)';

  @override
  String get importFailuresShareFailed =>
      'Não foi possível partilhar o relatório.';

  @override
  String get importFailuresDismiss => 'Dispensar';

  @override
  String get importFailuresNoDate => 'Data desconhecida';

  @override
  String get importFailuresReasonNetwork => 'Ligação interrompida';

  @override
  String get importFailuresReasonAuth => 'Sessão terminada';

  @override
  String get importFailuresReasonRateLimited => 'Limite de pedidos';

  @override
  String get importFailuresReasonTooLarge => 'Ficheiro demasiado grande';

  @override
  String get importFailuresReasonUnparseable =>
      'Não foi possível ler o ficheiro';

  @override
  String get importFailuresReasonRejected => 'Recusado pelo servidor';

  @override
  String get importFailuresReasonUnknown => 'Erro desconhecido';

  @override
  String importStatusCloudPushDeferred(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count corridas estão guardadas neste dispositivo — o envio para a nuvem não foi concluído. Será tentado novamente na próxima sincronização.',
      one:
          '1 corrida está guardada neste dispositivo — o envio para a nuvem não foi concluído. Será tentado novamente na próxima sincronização.',
    );
    return '$_temp0';
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
  String importHealthRoutesWithheld(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count atividades importadas têm mapas de GPS que o Threkir não tem permissão para ler.',
      one:
          '1 atividade importada tem um mapa de GPS que o Threkir não tem permissão para ler.',
    );
    return '$_temp0 O Health Connect protege a rota de um treino com uma permissão própria.';
  }

  @override
  String get importHealthRoutesAllowButton => 'Permitir importar mapas';

  @override
  String get importHealthRoutesRequesting =>
      'A solicitar acesso aos mapas ao Health Connect...';

  @override
  String get importHealthRoutesDenied =>
      'Acesso aos mapas não concedido. As importações continuam sem mapa — pode mudar isto no Health Connect quando quiser.';

  @override
  String get importHealthRoutesAdding =>
      'A adicionar mapas às atividades importadas...';

  @override
  String importHealthRoutesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mapas adicionados a $count atividades.',
      one: 'Mapa adicionado a 1 atividade.',
      zero: 'Nenhum mapa pôde ser adicionado.',
    );
    return '$_temp0';
  }

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'Não foi possível atualizar o seguimento: $error';
  }

  @override
  String get peopleSearchHint => 'Procurar corredores por nome';

  @override
  String get peopleClearSearchTooltip => 'Limpar pesquisa';

  @override
  String get commonClearSearch => 'Limpar pesquisa';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get placeSearchNoResults => 'Nenhum lugar encontrado';

  @override
  String get placeSearchUnavailable =>
      'A pesquisa de locais está indisponível de momento';

  @override
  String get placeSearchRetry => 'Tentar novamente';

  @override
  String get commonDismiss => 'Dispensar';

  @override
  String get settingsDevicesRemoveOverride => 'Remover substituição';

  @override
  String get peopleSearchResultsHeader => 'Resultados da pesquisa';

  @override
  String get peopleSuggestedHeader => 'Sugestões para si';

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
      'As sugestões vêm de pessoas dos clubes em que entrou. Entre num clube para começar a vê-las aqui.';

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
  String get peopleNearbyHeader => 'Corredores por perto';

  @override
  String get peopleNearbySubtitle =>
      'Corredores que optaram por participar perto da área que definiu. Apenas distância aproximada, nunca uma localização em tempo real.';

  @override
  String get peopleNearbyEmptyTitle => 'Ainda não há ninguém por perto';

  @override
  String get peopleNearbyEmptyBody =>
      'Ative «Mostrar-me a corredores por perto» e defina a sua área. Só os corredores que fizeram o mesmo o podem encontrar.';

  @override
  String get peopleNearbyEmptyAction => 'Abrir Preferências';

  @override
  String get peopleNearbyLoadFailed =>
      'Não foi possível carregar os corredores por perto.';

  @override
  String peopleNearbyWithin(String distance) {
    return 'A menos de $distance';
  }

  @override
  String peopleNearbyBeyond(String distance) {
    return 'A mais de $distance';
  }

  @override
  String get prefsDiscoverableNearby => 'Mostrar-me a corredores por perto';

  @override
  String get prefsDiscoverableNearbySubtitle =>
      'Desativado por predefinição. Quando ativado, outros corredores que também optaram por participar veem que está aproximadamente por perto — uma distância aproximada à área que definiu, nunca a sua localização.';

  @override
  String get nearbyAreaTitle => 'A sua área';

  @override
  String get nearbyAreaExplainer =>
      'Escolha a cidade ou o bairro onde corre. É guardada arredondada a cerca de um quilómetro e nunca é a sua localização em tempo real. Os outros corredores só veem uma distância aproximada, nunca a área em si.';

  @override
  String get nearbyAreaNone => 'Nenhuma área definida';

  @override
  String nearbyAreaCurrent(String label) {
    return 'Área atual: $label';
  }

  @override
  String get nearbyAreaSearchHint => 'Procurar uma cidade ou bairro';

  @override
  String get nearbyAreaSearchUnavailable =>
      'A pesquisa de locais está indisponível neste momento.';

  @override
  String get nearbyAreaNoResults => 'Nenhum local corresponde a essa pesquisa.';

  @override
  String get nearbyAreaSaved => 'Área guardada';

  @override
  String get nearbyAreaSaveFailed => 'Não foi possível guardar a sua área.';

  @override
  String get nearbyAreaLoadFailed => 'Não foi possível carregar a sua área.';

  @override
  String get nearbyAreaForget => 'Esquecer a minha área';

  @override
  String get nearbyAreaForgetConfirmTitle => 'Esquecer a sua área?';

  @override
  String get nearbyAreaForgetConfirmBody =>
      'Deixará de aparecer a corredores por perto até definir novamente uma área.';

  @override
  String get nearbyAreaForgotten => 'Área esquecida';

  @override
  String get nearbyAreaForgetFailed => 'Não foi possível esquecer a sua área.';

  @override
  String get peopleFallbackDisplayName => 'Corredor';

  @override
  String get peopleFollowingButton => 'A seguir';

  @override
  String get peopleFollowButton => 'Seguir';

  @override
  String get peopleSignedOutMessage =>
      'Faça login para pesquisar e seguir outros corredores.';

  @override
  String get peopleSuggestionsLoadFailed =>
      'Não foi possível carregar as sugestões.';

  @override
  String get readinessCardHeader => 'Prontidão';

  @override
  String get readinessBandHigh => 'alta';

  @override
  String get readinessBandModerate => 'moderada';

  @override
  String get readinessBandLow => 'baixa';

  @override
  String get missingMapTilesTitle =>
      'A utilizar tiles alternativos do OpenStreetMap';

  @override
  String get prefsLanguage => 'Idioma';

  @override
  String get prefsLanguageSystem => 'Predefinição do sistema';

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
  String get navLog => 'Registar';

  @override
  String get logA11yLabel => 'Registar uma atividade';

  @override
  String get navFitness => 'Fitness';

  @override
  String get navYou => 'Tu';

  @override
  String get fitnessTabRuns => 'Corridas';

  @override
  String get fitnessTabGym => 'Ginásio';

  @override
  String get fitnessTabNutrition => 'Nutrição';

  @override
  String get fitnessRunsRoutes => 'Rotas';

  @override
  String get fitnessRunsPlans => 'Planos de treino';

  @override
  String get runSurfaceLabel => 'Secções da área de corrida';

  @override
  String get runSurfaceTabPlans => 'Planos';

  @override
  String get runSurfaceTabRaces => 'Corridas';

  @override
  String get gymSurfaceLabel => 'Secções do ginásio';

  @override
  String get gymTabLog => 'Registo';

  @override
  String get gymTabRecords => 'Recordes';

  @override
  String get homeAskCoach => 'Pergunte ao seu treinador';

  @override
  String get homeAskCoachSubtitle =>
      'Dicas sobre as suas corridas, ginásio e nutrição';

  @override
  String get youProfileTitle => 'O seu perfil';

  @override
  String get logSheetTitle => 'Registar';

  @override
  String get logRun => 'Registar corrida';

  @override
  String get logLift => 'Registar musculação';

  @override
  String get logFood => 'Registar comida';

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
      'Utilizado para estimar as suas metas diárias de calorias e macros.';

  @override
  String get bodyMetricsConsentRequired =>
      'Ative o armazenamento de dados de saúde para guardar altura e peso.';

  @override
  String get bodyMetricsWithdrawTitle =>
      'Retirar o consentimento de dados de saúde?';

  @override
  String get bodyMetricsWithdrawBody =>
      'Isto apaga permanentemente a sua altura guardada e todo o seu histórico de peso. Não pode ser desfeito.';

  @override
  String get bodyMetricsWithdrawConfirm => 'Retirar e apagar';

  @override
  String get bodyMetricsSaved => 'Guardado';

  @override
  String bodyMetricsSaveFailed(String error) {
    return 'Falha ao guardar: $error';
  }

  @override
  String bodyMetricsPrefSaveFailed(String error) {
    return 'Não foi possível guardar: $error';
  }

  @override
  String get bodyMetricsLoadError =>
      'Não foi possível carregar os dados corporais.';

  @override
  String get safetyTitle => 'Contactos de segurança';

  @override
  String get safetyTileSubtitle =>
      'Envie um e-mail a um contacto de confiança ao concluir uma corrida';

  @override
  String get safetyIntro =>
      'Um contacto de segurança recebe um e-mail quando conclui uma corrida — mesmo uma privada — para que alguém de confiança saiba que voltou em segurança.';

  @override
  String get safetyAddLabel => 'E-mail do contacto';

  @override
  String get safetyAddHint => 'parceiro@example.com';

  @override
  String get safetyPhoneLabel => 'Telefone para SMS (opcional)';

  @override
  String get safetyPhoneHint =>
      'Adicione um número de telemóvel e este contacto também poderá ser avisado por SMS — decide ao confirmar. Os avisos por e-mail são sempre enviados.';

  @override
  String get safetyInvalidPhone =>
      'Introduza o telefone no formato internacional, ex.: +447700900123.';

  @override
  String get safetySmsBadge => 'SMS ativado';

  @override
  String get safetySmsPending => 'SMS desativado — ainda não aceitou';

  @override
  String get safetyConfirmSmsLabel => 'Avisar-me também por SMS';

  @override
  String get safetyContactOfTitle => 'É contacto de segurança';

  @override
  String get safetyContactOfIntro =>
      'Estas pessoas indicaram-no como contacto de emergência e confirmou. Dá para mudar como é avisado, ou sair, quando quiser.';

  @override
  String safetyContactOfFor(String name) {
    return 'Contacto de emergência de $name';
  }

  @override
  String get safetyContactOfSmsLabel => 'Avisar por SMS além do e-mail';

  @override
  String get safetyContactOfNoPhone =>
      'Os avisos por SMS precisam de um número de telemóvel seu, e nenhum está registado. Os avisos por e-mail são sempre enviados.';

  @override
  String get safetyContactOfSmsOnToast => 'Avisos por SMS ativados.';

  @override
  String get safetyContactOfSmsOffToast => 'Avisos por SMS desativados.';

  @override
  String get safetyContactOfSmsNoChange =>
      'Esse vínculo não está mais ativo — a pessoa pode tê-lo removido.';

  @override
  String safetyContactOfSmsFailed(String error) {
    return 'Não foi possível mudar a sua preferência de SMS: $error';
  }

  @override
  String get safetyContactOfWithdraw => 'Sair';

  @override
  String get safetyContactOfWithdrawConfirm =>
      'Deixar de ser o contacto de segurança desta pessoa? Ela não poderá mais avisá-lo e precisaria enviar um novo pedido.';

  @override
  String get safetyContactOfWithdrawnToast =>
      'Não é mais contacto de segurança.';

  @override
  String safetyContactOfWithdrawFailed(String error) {
    return 'Não foi possível sair: $error';
  }

  @override
  String get safetyAddButton => 'Adicionar contacto';

  @override
  String get safetyAdding => 'A adicionar…';

  @override
  String get safetyEmpty => 'Nenhum contacto de segurança ainda.';

  @override
  String get safetyStatusPending => 'Pendente — aguardando a confirmação';

  @override
  String get safetyStatusConfirmed => 'Confirmado';

  @override
  String get safetyRemove => 'Remover';

  @override
  String get safetyRemoveConfirm => 'Remover este contacto de segurança?';

  @override
  String safetyAddFailed(String error) {
    return 'Não foi possível adicionar o contacto: $error';
  }

  @override
  String safetyRemoveFailed(String error) {
    return 'Não foi possível remover o contacto: $error';
  }

  @override
  String safetySettingSaveFailed(String error) {
    return 'Não foi possível guardar a definição: $error';
  }

  @override
  String get safetyInvalidEmail => 'Introduza um e-mail válido.';

  @override
  String get safetyAddedToast =>
      'Contacto adicionado — enviamos um e-mail de confirmação.';

  @override
  String get safetyRemovedToast => 'Contacto removido.';

  @override
  String get safetyIncomingTitle => 'Pedidos para si';

  @override
  String get safetyIncomingIntro =>
      'Estas pessoas pediram para si ser o contacto de segurança delas. Confirme para receber um e-mail quando concluírem uma corrida.';

  @override
  String safetyIncomingFrom(String name) {
    return 'De $name';
  }

  @override
  String get safetyConfirm => 'Confirmar';

  @override
  String get safetyDecline => 'Recusar';

  @override
  String get safetyConfirmedToast => 'Agora é contacto de segurança.';

  @override
  String get safetyDeclinedToast => 'Pedido recusado.';

  @override
  String get safetyUnknownRunner => 'Um corredor do Threkir';

  @override
  String get safetyOverdueTitle => 'Alerta de atraso';

  @override
  String get safetyOverdueIntro =>
      'Se uma corrida partilhada em direto ficar em silêncio por mais tempo que isto, os seus contactos confirmados recebem um e-mail com o seu link em direto.';

  @override
  String get safetyOverdueLabel => 'Avisar após silêncio de';

  @override
  String get safetyOverdueOff => 'Desativado';

  @override
  String safetyOverdueMinutesOption(int minutes) {
    return '$minutes min';
  }

  @override
  String get safetyOverdueNote =>
      'Vale para qualquer corrida com partilha em direto ativo. O silêncio também pode ser perda de sinal — o e-mail deixa isto claro. Os contactos recebem um único aviso por corrida; concluir envia a confirmação habitual.';

  @override
  String get safetyOverdueSaved => 'Alerta de atraso atualizado';

  @override
  String get safetyAutoLiveShareTitle => 'Partilha em direto automático';

  @override
  String get safetyAutoLiveShareSubtitle =>
      'Inicia automaticamente a partilha em direto quando uma corrida começa neste telemóvel. A corrida em curso fica visível para qualquer pessoa com o link; quando a corrida termina, volta à sua visibilidade predefinida.';

  @override
  String get safetyOffRouteTitle => 'Alerta de saída de rota';

  @override
  String get safetyOffRouteSubtitle =>
      'Avise um contacto confirmado se sair e continuar fora da rota planeada numa corrida partilhada em direto.';

  @override
  String get runOffRouteAlertSent =>
      'Avisamos o seu contacto de segurança — está fora da rota há um tempo.';

  @override
  String get runAutoLiveShareStarted =>
      'Em direto ativado — envie o link em “Partilhar link em direto”';

  @override
  String get runSafetyNudgeSolo =>
      'Vai correr sozinho(a) depois de escurecer? Partilhe um link em direto com alguém';

  @override
  String get runSafetyNudgeShareAction => 'Partilhar';

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
  String get authPasswordLabel => 'Palavra-passe';

  @override
  String get authShowPassword => 'Mostrar palavra-passe';

  @override
  String get authHidePassword => 'Ocultar palavra-passe';

  @override
  String get authOrDivider => 'OU';

  @override
  String get authErrorOffline =>
      'Parece estar offline. Verifique a sua ligação e tente novamente.';

  @override
  String get authErrorInvalidCredentials =>
      'E-mail ou palavra-passe incorretos. Tente novamente.';

  @override
  String get authErrorRateLimited =>
      'Muitas tentativas. Aguarde um momento e tente novamente.';

  @override
  String get authErrorGeneric => 'Algo deu errado. Tente novamente.';

  @override
  String get authErrorNotSignedIn =>
      'Precisa estar conectado para fazer isto. Entre e tente novamente.';

  @override
  String get authErrorEmailExists =>
      'Esse e-mail já tem uma conta. Entre em vez disto.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Confirme o seu e-mail primeiro — procure o link de confirmação na sua caixa de entrada.';

  @override
  String authErrorWeakPassword(int minLength) {
    return 'Essa palavra-passe é muito fraca. Utilize pelo menos $minLength caracteres.';
  }

  @override
  String get authErrorInvalidEmail => 'Introduza um endereço de e-mail válido.';

  @override
  String authErrorPasswordTooShort(int minLength) {
    return 'A palavra-passe deve ter pelo menos $minLength caracteres.';
  }

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
  String get signInForgotPassword => 'Esqueceu a palavra-passe?';

  @override
  String get signInResetNeedEmail =>
      'Introduza o seu e-mail acima primeiro e depois toque em Esqueceu a palavra-passe.';

  @override
  String get signInResetSent =>
      'Se esse e-mail estiver registado, enviamos um link de redefinição.';

  @override
  String get signInResendConfirmation => 'Reenviar e-mail de confirmação';

  @override
  String get signInConfirmationResent =>
      'Se esse e-mail estiver registado, enviamos um novo link de confirmação.';

  @override
  String get signInWithApple => 'Entrar com Apple';

  @override
  String get signInWithGoogle => 'Entrar com Google';

  @override
  String get googleSignInSoon =>
      'O login com o Google chega em breve. Por enquanto, utilize o e-mail.';

  @override
  String get appleSignInSoon =>
      'O login com a Apple chega em breve. Por enquanto, utilize o e-mail.';

  @override
  String get signInContinueOffline => 'Continuar offline';

  @override
  String get signInCreateAccountPrompt => 'Não tem uma conta? Crie uma';

  @override
  String get signUpTitle => 'Criar conta';

  @override
  String get signUpHeadline => 'Comece a registar as suas corridas';

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
  String get signUpAcceptConjunction => ' e a ';

  @override
  String get signUpErrorConfirmAge =>
      'Confirme que tem 16 anos ou mais para continuar.';

  @override
  String get signUpErrorAcceptTerms =>
      'Aceite os Termos de Serviço e a Política de Privacidade para continuar.';

  @override
  String get signUpConfirmPasswordLabel => 'Confirme a palavra-passe';

  @override
  String signUpErrorPasswordTooShort(int min) {
    return 'A palavra-passe precisa ter pelo menos $min caracteres.';
  }

  @override
  String get signUpErrorPasswordMismatch => 'As palavras-passe não coincidem.';

  @override
  String get signUpCheckEmailTitle => 'Verifique o seu e-mail';

  @override
  String signUpCheckEmailBody(String email) {
    return 'Enviamos um link de confirmação para $email. Abra-o para concluir a criação da sua conta.';
  }

  @override
  String get signUpCheckEmailBack => 'Voltar para entrar';

  @override
  String get signUpContinueWithApple => 'Continuar com Apple';

  @override
  String get signUpContinueWithGoogle => 'Continuar com Google';

  @override
  String get signUpSignInPrompt => 'Já tem uma conta? Entre';

  @override
  String get onboardingTrackTitle => 'Registe cada corrida';

  @override
  String get onboardingTrackBody =>
      'Gravação por GPS com mapa em direto, parciais, ritmo, cadência e elevação. Funciona totalmente offline — entre depois para sincronizar entre dispositivos.';

  @override
  String get onboardingRoutesTitle => 'Siga rotas';

  @override
  String get onboardingRoutesBody =>
      'Importe ficheiros GPX ou KML, ou sincronize rotas do app web. Receba alertas de desvio enquanto corre.';

  @override
  String get onboardingLocationTitle => 'Acesso à localização';

  @override
  String get onboardingLocationBody =>
      'O Threkir regista as suas corridas amostrando a sua localização por GPS enquanto o app está em primeiro plano E em segundo plano (para continuar a registar quando o ecrã está desligada ou troca de app para tirar uma fotografia). Os dados de localização ficam armazenados no seu dispositivo e só são enviados aos servidores do Threkir quando escolhe partilhar ou sincronizar uma corrida. Se recusar a localização em segundo plano, as corridas param de ser registadas no momento em que sai do app — pode mudar isto depois em Definições → Apps → Threkir → Permissões.';

  @override
  String get onboardingPrivacyTitle => 'Quem vê as suas corridas?';

  @override
  String get onboardingPrivacyBody =>
      'Escolha uma predefinição para novas corridas. Pode alterá-la a qualquer momento nas Definições e substituí-la em qualquer corrida específica.';

  @override
  String get onboardingGrantPermission => 'Conceder permissão';

  @override
  String get onboardingNext => 'Avançar';

  @override
  String get setupPageTitle => 'Configure a sua conta';

  @override
  String get setupSkip => 'Saltar configuração';

  @override
  String get setupSkipStep => 'Saltar';

  @override
  String get setupBack => 'Voltar';

  @override
  String get setupContinue => 'Continuar';

  @override
  String get setupSaving => 'A guardar…';

  @override
  String get setupOpenDashboard => 'Abrir painel';

  @override
  String get setupCreatePlanCta => 'Criar meu plano de treino';

  @override
  String get setupWelcomeToast => 'Bem-vindo ao Threkir!';

  @override
  String setupSaveError(String message) {
    return 'Não foi possível guardar a sua configuração: $message';
  }

  @override
  String setupPrefsSaveError(String message) {
    return 'A sua conta ficou configurada, mas as suas preferências não foram guardadas: $message';
  }

  @override
  String get setupOfflineHint =>
      'Não foi possível conectar ao servidor agora. Pode concluir a configuração mais tarde — tudo aqui pode ser editado em Definições.';

  @override
  String get setupFinishLater => 'Concluir mais tarde';

  @override
  String get setupNameTitle => 'Como devemos te chamar?';

  @override
  String get setupNameHint =>
      'Este é o nome que outros corredores veem no seu perfil e nas corridas partilhadas.';

  @override
  String get setupNameLabel => 'Nome de exibição';

  @override
  String get setupNamePlaceholder => 'ex.: Alex Corredor';

  @override
  String get setupUnitsTitle => 'Quilómetros ou milhas?';

  @override
  String get setupUnitsHint =>
      'Vamos utilizar isto em todos os lugares onde distâncias e ritmos aparecem. Pode mudar quando quiser em Definições.';

  @override
  String get setupUnitKm => 'Quilómetros';

  @override
  String get setupUnitKmSample => '5,0 km · 5:00 /km';

  @override
  String get setupUnitMi => 'Milhas';

  @override
  String get setupUnitMiSample => '3,1 mi · 8:03 /mi';

  @override
  String get setupGoalTitle => 'Qual é o seu principal objetivo?';

  @override
  String get setupGoalHint =>
      'Vamos utilizar isto para sugerir um plano de treino adequado. Opcional — pode saltar.';

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
  String get setupAboutTitle => 'Um pouco sobre si';

  @override
  String get setupAboutHint =>
      'Opcional. Ajuda a personalizar estimativas de ritmo e calorias. Decide se partilha dados de saúde.';

  @override
  String get setupGenderLabel => 'Género';

  @override
  String get setupGenderPreferNot => 'Prefiro não dizer';

  @override
  String get setupGenderFemale => 'Feminino';

  @override
  String get setupGenderMale => 'Masculino';

  @override
  String get setupDobLabel => 'Data de nascimento';

  @override
  String get setupDobNote =>
      'Utilizada para manter contas de menores de 18 anos fora da pesquisa de pessoas e para resultados ajustados por idade, se partilhar dados de saúde.';

  @override
  String get setupDobPlaceholder => 'Toque para escolher';

  @override
  String get setupWeightLabel => 'Peso (kg)';

  @override
  String get setupWeightPlaceholder => 'ex.: 70';

  @override
  String get setupHealthConsent =>
      'Consinto que o Threkir utilize meu género e data de nascimento para personalizar estimativas de ritmo, frequência cardíaca e calorias (dados de saúde de categoria especial, RGPD art. 9).';

  @override
  String get setupPrivacyTitle => 'Quem vê as suas corridas?';

  @override
  String get setupPrivacyHint =>
      'Escolha uma predefinição para novas corridas. Pode alterá-la a qualquer momento e substituí-la em cada corrida.';

  @override
  String get setupNotificationsTitle => 'Fique por dentro';

  @override
  String get setupNotificationsHint =>
      'Escolha quantas notificações push deseja. Pode ajustar isto depois em Definições.';

  @override
  String get setupDoneTitle => 'Tudo pronto';

  @override
  String get setupDoneHint =>
      'É isto. Toque em “Abrir painel” para começar a correr.';

  @override
  String get setupDoneHintGoal =>
      'É tudo. Crie um plano de treino para o seu objetivo ou abra o painel para começar a correr.';

  @override
  String get privacyPrivateTitle => 'Privada';

  @override
  String get privacyPrivateSubtitle =>
      'Só pode ver as suas corridas. Pode partilhar qualquer corrida depois.';

  @override
  String get privacyFollowersTitle => 'Seguidores';

  @override
  String get privacyFollowersSubtitle =>
      'Quem o segue vê as novas corridas no feed.';

  @override
  String get privacyPublicTitle => 'Pública';

  @override
  String get privacyPublicSubtitle =>
      'Qualquer pessoa pode encontrar e ver as suas corridas.';

  @override
  String get runStart => 'INICIAR';

  @override
  String get runStartA11yLabel => 'Iniciar corrida';

  @override
  String get runLastRunOpenA11yLabel => 'Abrir os detalhes da última corrida';

  @override
  String get runChooseRoute => 'Escolher rota';

  @override
  String get runChangeRoute => 'Trocar rota';

  @override
  String get runShareLiveLink => 'Partilhar link em direto';

  @override
  String get runLiveShareNeedsSignIn =>
      'Inicie sessão para partilhar um link de rastreio em direto.';

  @override
  String get runLiveShareNotStarted =>
      'Não foi possível iniciar o rastreio em direto — toque em Partilhar para tentar novamente.';

  @override
  String get runLiveShareActive => 'Em direto';

  @override
  String get runLiveShareActiveSemantics =>
      'A partilha em direto está ativa. Toque para partilhar novamente o link ou parar a partilha.';

  @override
  String get runLiveShareSheetTitle => 'Partilha em direto ativa';

  @override
  String get runLiveShareReshare => 'Partilhar link novamente';

  @override
  String get runLiveShareStop => 'Parar partilha';

  @override
  String get runLiveShareExpectedReturn => 'Sem voltar até…';

  @override
  String get runExpectedReturnTitle => 'Sem voltar até…';

  @override
  String get runExpectedReturnIntro =>
      'Escolha a que horas espera terminar. Se esta atividade ainda estiver a decorrer, os seus contactos de segurança confirmados recebem um aviso com o seu link em direto.';

  @override
  String get runExpectedReturnServerNote =>
      'O prazo fica guardado no servidor, por isso continua a contar mesmo que este telemóvel falhe. É limpo quando a atividade é guardada — uma atividade terminada sem rede ainda pode avisar até sincronizar.';

  @override
  String runExpectedReturnOptionMinutes(int minutes) {
    return 'Dentro de $minutes min';
  }

  @override
  String runExpectedReturnOptionHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Dentro de $hours horas',
      one: 'Dentro de 1 hora',
    );
    return '$_temp0';
  }

  @override
  String runExpectedReturnBy(String time) {
    return 'De volta às $time';
  }

  @override
  String runExpectedReturnActive(String time) {
    return 'Aviso definido para as $time.';
  }

  @override
  String get runExpectedReturnClear => 'Limpar o aviso';

  @override
  String get runExpectedReturnSetToast => 'Aviso de hora de regresso definido.';

  @override
  String get runExpectedReturnClearedToast =>
      'Aviso de hora de regresso limpo.';

  @override
  String get runExpectedReturnFailed =>
      'Não foi possível atualizar o aviso de hora de regresso.';

  @override
  String get runExpectedReturnUnavailable =>
      'Servidor inacessível — não é possível definir o aviso de hora de regresso.';

  @override
  String get runLiveShareStopped => 'Partilha em direto terminada';

  @override
  String get runLiveShareEndedTitle => 'Partilha em direto terminada';

  @override
  String get runLiveShareEndedBody =>
      'O link em direto já não é atualizado. Manter a corrida guardada pública para que qualquer pessoa com o link a possa ver? Caso contrário, segue a sua visibilidade predefinida.';

  @override
  String get runLiveShareKeepPublic => 'Manter pública';

  @override
  String get runLiveShareKeepPrivate => 'Manter privada';

  @override
  String get runTrainingPlans => 'Planos de treino';

  @override
  String get runTapToCancel => 'Toque para cancelar';

  @override
  String get runFirstRunPrompt =>
      'A sua primeira corrida está a um toque de distância.';

  @override
  String get runLastActivity => 'Última atividade';

  @override
  String get runLastRun => 'Última corrida';

  @override
  String get runFollowing => 'A seguir';

  @override
  String get runRaceFallbackTitle => 'Prova';

  @override
  String get runRaceArmed => 'Prova pronta';

  @override
  String get runRaceLive => 'Prova EM DIRETO';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — aguardando a partida';
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
  String get runSyncing => 'A sincronizar…';

  @override
  String get runDone => 'Concluído';

  @override
  String get runDiscardA11yLabel => 'Descartar corrida';

  @override
  String get runDiscardA11yHint => 'Descarta a gravação atual sem guardar';

  @override
  String get runStopA11yLabel => 'Parar e guardar corrida';

  @override
  String get runStopA11yHint => 'Encerra a gravação e guardada a corrida';

  @override
  String get runHoldToStopHint => 'Segure para parar';

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
  String get runMarkLapA11yHint => 'Regista o parcial atual';

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
  String get runDiscardDialogBody => 'O seu progresso será perdido.';

  @override
  String get runKeepRunning => 'Continuar correndo';

  @override
  String get runDiscard => 'Descartar';

  @override
  String get runResumeDialogTitle => 'Retomar a sua corrida?';

  @override
  String get runResumeDialogBody =>
      'Uma corrida de uma sessão anterior ainda está em curso. Retome a gravação de onde parou, finalize-a agora ou descarte-a.';

  @override
  String get runResumeAction => 'Retomar';

  @override
  String get runResumeFinishAction => 'Finalizar agora';

  @override
  String get runResumedBanner => 'Corrida retomada.';

  @override
  String get runResumeSavedBanner => 'Corrida anterior guardada.';

  @override
  String get runResumeDiscardedBanner => 'Corrida anterior descartada.';

  @override
  String get runStartWorkout => 'Iniciar treino';

  @override
  String get runStartWorkoutSubtitle =>
      'Corra com metas de etapa em direto, avisos de áudio e uma análise de planeado vs. realizado.';

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
      'O plano estruturado termina aqui; a gravação continua como corrida livre. Pode parar a qualquer momento para guardar o que fez.';

  @override
  String get runCancel => 'Cancelar';

  @override
  String get runAbandon => 'Abandonar';

  @override
  String get runNoRoutesSaved =>
      'Nenhuma rota guardada. Importe uma na separador Rotas.';

  @override
  String get runNotificationsOffHint =>
      'As notificações estão desativadas — a notificação de corrida em direto não aparecerá. A gravação continua a funcionar.';

  @override
  String get runSettings => 'Definições';

  @override
  String get runStartAnyway => 'Iniciar mesmo assim';

  @override
  String get runOpenSettings => 'Abrir definições';

  @override
  String get runNotNow => 'Agora não';

  @override
  String get runShareSubject => 'Me acompanhe em direto';

  @override
  String runCouldNotShareLink(String error) {
    return 'Não foi possível partilhar o link em direto: $error';
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
  String get runTreadmillConnecting => 'A conectar à passadeira…';

  @override
  String get runTreadmillNoBeltData =>
      'Sem dados da passadeira — distância pelo GPS';

  @override
  String get runSaveFailedRelaunch =>
      'Não foi possível guardar localmente. Reinicie o app para recuperar.';

  @override
  String get runSyncFailedSaveOffline =>
      'Guardada offline. Sincronize em Corridas.';

  @override
  String get runSavedOffline => 'Guardada offline.';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings =>
      'Sem GPS — o rastreio começará quando a Localização estiver ativada.';

  @override
  String get runGpsBlockedSettings =>
      'Sem GPS — permissão bloqueada. Ative-a para rastrear a rota.';

  @override
  String get runGpsPermissionPending =>
      'Sem GPS — o rastreio começará quando a permissão for concedida.';

  @override
  String get runBackgroundLocationPaused =>
      'O registo foi pausado enquanto esteve fora — o tempo continuou a contar e nada se perdeu, mas a distância percorrida fora do ecrã não foi contabilizada. Defina a Localização como \"Permitir sempre\" para continuar a registar em segundo plano.';

  @override
  String get runGpsSensorFailed =>
      'A gravar sem GPS — não foi possível iniciar o sensor.';

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
      'Treino concluído · toque em parar para guardar';

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
  String get runWorkoutSkip => 'Saltar';

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
  String get historyDeleteTooltip => 'Eliminar';

  @override
  String get historyCancelTooltip => 'Cancelar';

  @override
  String get historyAddRun => 'Adicionar corrida';

  @override
  String get historyAddRunTooltip => 'Adicionar uma corrida manualmente';

  @override
  String get historyLogTooltip => 'Registar corrida, treino ou refeição';

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
  String get historyTimelineEmpty => 'Nada registado nesta visualização ainda.';

  @override
  String get historyClearFilters => 'Limpar filtros';

  @override
  String get historyEmptyTitle => 'Ainda não há corridas';

  @override
  String get historyEmptyBody =>
      'Toque na separador Correr para iniciar a sua primeira corrida';

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
  String get historyRangeTapDate => 'Toque numa data';

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
      other: 'Eliminar $count corridas?',
      one: 'Eliminar $count corrida?',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody => 'Isto não pode ser desfeito.';

  @override
  String get historyCancel => 'Cancelar';

  @override
  String get historyDelete => 'Eliminar';

  @override
  String get historyUnsyncedRowSemantics => 'ainda não sincronizada';

  @override
  String get historyBlockedRowSemantics => 'não pode ser enviada';

  @override
  String get historyBlockedRowTooltip => 'Não pode ser enviada';

  @override
  String historyBlockedTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas não podem ser enviadas',
      one: '$count corrida não pode ser enviada',
    );
    return '$_temp0';
  }

  @override
  String historySyncBlocked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count corridas não podem ser enviadas e não serão tentadas novamente. Abra cada uma para escolher o que fazer.',
      one:
          '$count corrida não pode ser enviada e não será tentada novamente. Abra-a para escolher o que fazer.',
    );
    return '$_temp0';
  }

  @override
  String get runDetailBlockedDropTrack => 'Enviar sem o trajeto';

  @override
  String get runDetailBlockedExport => 'Exportar uma cópia';

  @override
  String get runDetailBlockedTitle => 'Esta corrida não pode ser enviada';

  @override
  String runDetailBlockedTrackTooLarge(int waypoints) {
    return 'O seu trajeto de GPS ($waypoints pontos) é maior do que o armazenamento na nuvem permite, por isso tentar de novo nunca vai resultar. Todo o resto da corrida — distância, tempo, ritmo, desnível — continua a poder ser guardado.';
  }

  @override
  String get runDetailDropTrackBody =>
      'O trajeto é removido deste dispositivo e a corrida é enviada sem mapa. A distância, o tempo, o ritmo e o desnível não mudam. Exporte primeiro uma cópia se quiser guardá-lo.';

  @override
  String get runDetailDropTrackConfirm => 'Enviar sem ele';

  @override
  String get runDetailDropTrackDone =>
      'Trajeto removido. A corrida será sincronizada no próximo ciclo.';

  @override
  String get runDetailDropTrackFailed =>
      'Não foi possível remover o trajeto. Tente novamente.';

  @override
  String get runDetailDropTrackTitle => 'Enviar sem o trajeto de GPS?';

  @override
  String get historyQueuedToSync => 'Na fila para sincronizar';

  @override
  String get historySignInToSync =>
      'Entre nas definições para sincronizar as corridas';

  @override
  String get historyRefreshFailed =>
      'Não foi possível atualizar — verifique a sua ligação';

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
          '$count corridas não conseguiram enviar o seu trajeto de GPS — o restante foi sincronizado. As corridas com falha serão tentadas novamente no próximo ciclo.',
      one:
          '$count corrida não conseguiu enviar o seu trajeto de GPS — o restante foi sincronizado. Será tentado novamente no próximo ciclo.',
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
    return '$deleted eliminadas; $queued na fila — será tentado novamente quando estiver online.';
  }

  @override
  String historyDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas eliminadas',
      one: '$count corrida eliminada',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'Adicionar corrida';

  @override
  String get addRunSave => 'Guardar';

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
  String get durationFieldHours => 'Horas';

  @override
  String get durationFieldMinutes => 'Minutos';

  @override
  String get durationFieldSeconds => 'Segundos';

  @override
  String get addRunSectionTitle => 'Título (opcional)';

  @override
  String get addRunSectionNotes => 'Notas (opcional)';

  @override
  String get addRunClearRoute => 'Remover rota';

  @override
  String get addRunSearchRoutes => 'Procurar rotas guardadas';

  @override
  String get addRunNoRoutes =>
      'Ainda não há rotas guardadas — crie ou importe uma para anexá-la aqui';

  @override
  String get addRunDistanceInvalid => 'Insira uma distância maior que 0';

  @override
  String get addRunDurationInvalid => 'Insira uma duração';

  @override
  String get addRunTitleHint => 'ex.: Volta do almoço';

  @override
  String get addRunNotesHint => 'Como foi?';

  @override
  String get addRunSaveButton => 'Guardar corrida';

  @override
  String addRunSaveFailed(String error) {
    return 'Falha ao guardar a corrida: $error';
  }

  @override
  String get addRunSaved => 'Corrida adicionada ao histórico';

  @override
  String get addRunPickerSearchHint => 'Procurar rotas';

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
  String get runDetailIncompleteBadge => 'Incompleta';

  @override
  String get runDetailIncompleteTooltip =>
      'O seu relógio reiniciou a meio da corrida. Estes totais são apenas o que tinha registado até esse momento, não a atividade inteira.';

  @override
  String get runDetailEditTooltip => 'Editar corrida';

  @override
  String get runDetailShareTooltip => 'Partilhar corrida';

  @override
  String get runDetailMoreTooltip => 'Mais';

  @override
  String get runDetailSaveAsRoute => 'Guardar como rota';

  @override
  String get runDetailDeleteRun => 'Eliminar corrida';

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
  String get runDetailEditFailed =>
      'Não foi possível guardar as suas alterações. Tente novamente.';

  @override
  String get runDetailSave => 'Guardar';

  @override
  String get runDetailCancel => 'Cancelar';

  @override
  String get runDetailDelete => 'Eliminar';

  @override
  String get runDetailLoadingGps => 'A carregar dados de GPS...';

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
  String get runDetailStatHrCoverage => 'Cobertura de FC';

  @override
  String runDetailHrCoveragePercent(int pct) {
    return '$pct%';
  }

  @override
  String runDetailHrCoverageOnly(int pct) {
    return '$pct% coberto';
  }

  @override
  String get runDetailStatAvgHr => 'FC média';

  @override
  String get runDetailStatAgeGrade => 'Índice por idade';

  @override
  String get runDetailStatGradeAdjPace => 'Ritmo ajustado';

  @override
  String get runDetailSectionElevation => 'Elevação';

  @override
  String get runDetailPaceLegendTitle => 'Ritmo vs mediana';

  @override
  String get runDetailPaceBandFaster => 'Mais depressa';

  @override
  String get runDetailPaceBandSteady => 'Constante';

  @override
  String get runDetailPaceBandSlower => 'Mais lento';

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
  String get runDetailDynGroundContact => 'Contacto com o solo';

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
    return 'Tentativa $rank de $total — Recorde: $pb';
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
  String get runDetailHrDisclaimer =>
      'As zonas utilizam uma FC máxima estimada pela idade. Se toma medicação cardíaca (ex.: betabloqueadores) ou já mediu a sua FC máxima, defina-a em Preferências para zonas precisas.';

  @override
  String get runDetailHrDisclaimerAction => 'Definir FC máx.';

  @override
  String get runDetailSectionSplits => 'Parciais';

  @override
  String get runDetailNoGpsForSplits => 'Sem dados de GPS para os parciais';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Corrida demasiado curta para um parcial completo de $unit';
  }

  @override
  String get runDetailPacing => 'Ritmo por metades';

  @override
  String get runDetailPacingFirstHalf => 'Primeira metade';

  @override
  String get runDetailPacingSecondHalf => 'Segunda metade';

  @override
  String get runDetailPacingNegative => 'Split negativo';

  @override
  String get runDetailPacingEven => 'Ritmo constante';

  @override
  String get runDetailPacingPositive => 'Split positivo';

  @override
  String runDetailPacingFaster(String delta) {
    return '$delta mais depressa na segunda metade';
  }

  @override
  String runDetailPacingSlower(String delta) {
    return '$delta mais lento na segunda metade';
  }

  @override
  String get runDetailPacingHeld => 'Constante nas duas metades';

  @override
  String get runDetailPacingGapNegative =>
      'Ajustado pelo relevo, acelerou na segunda metade.';

  @override
  String get runDetailPacingGapEven =>
      'Ajustado pelo relevo, o seu esforço foi igual nas duas metades.';

  @override
  String get runDetailPacingGapPositive =>
      'Ajustado pelo relevo, desacelerou na segunda metade.';

  @override
  String get runDetailGapColumn => 'Ajustado';

  @override
  String get runDetailGapColumnHint =>
      'O ritmo ajustado é o ritmo no plano que teria custado o mesmo esforço que as subidas que realmente correu.';

  @override
  String get runDetailSectionSegments => 'Segmentos';

  @override
  String get runDetailSaveAsRouteTitle => 'Guardar como rota';

  @override
  String get runDetailSaveAsRouteBody =>
      'Guarde este trajeto de GPS como uma rota que pode seguir novamente.';

  @override
  String get runDetailRouteNameLabel => 'Nome da rota';

  @override
  String get runDetailNoTrackToSave =>
      'Esta corrida não tem trajeto de GPS para guardar como rota';

  @override
  String runDetailRouteLinked(String route) {
    return 'Vinculada a $route';
  }

  @override
  String get runDetailRouteLinkFailed => 'Não foi possível vincular a rota';

  @override
  String get runDetailReSnapping => 'A reajustar às ruas…';

  @override
  String runDetailRematchFailed(String error) {
    return 'Falha no reajuste: $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return '\"$name\" guardada — $kept pontos de passagem ($smoothed suavizados)';
  }

  @override
  String runDetailRouteSaveFailed(String name) {
    return 'Não foi possível guardar \"$name\" como rota.';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'Não foi possível tornar a corrida pública: $error';
  }

  @override
  String get runDetailMakePublicTitle => 'Tornar esta corrida pública?';

  @override
  String get runDetailMakePublicBodyZone =>
      'Partilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la. Esta corrida começa ou termina dentro de uma das suas zonas de privacidade, então quem visualizar verá um trajeto recortado com os trechos dentro da zona ocultos.';

  @override
  String get runDetailMakePublicBodyHasZones =>
      'Partilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la. Nenhuma das suas zonas de privacidade cruza este trajeto, então o trajeto completo ficará visível.';

  @override
  String get runDetailMakePublicBodyNoZones =>
      'Partilhar torna esta corrida pública, para que qualquer pessoa com o link possa vê-la — incluindo os pontos de início e fim da sua corrida. Não tem zonas de privacidade configuradas. Considere adicionar uma ao redor da sua casa antes de partilhar.';

  @override
  String get runDetailMakePublic => 'Tornar pública';

  @override
  String get runDetailMakePrivate => 'Tornar privada';

  @override
  String get runDetailMakePrivateTitle => 'Tornar esta corrida privada?';

  @override
  String get runDetailMakePrivateBody =>
      'O link público de partilha e a página de espectadores em direto deixarão de funcionar. Quem abrir um link antigo deixará de ver esta corrida.';

  @override
  String runDetailMakePrivateFailed(String error) {
    return 'Não foi possível tornar a corrida privada: $error';
  }

  @override
  String get runDetailMadePrivate => 'A corrida agora é privada';

  @override
  String get runDetailDeleteTitle => 'Eliminar corrida?';

  @override
  String get runDetailDeleteBody => 'Isto não pode ser desfeito.';

  @override
  String get runDetailDeleteQueued =>
      'Não foi possível eliminar da nuvem; a corrida foi mantida por enquanto — será tentado novamente quando estiver online.';

  @override
  String get runDetailSuggestLink => 'Vincular';

  @override
  String get runDetailSuggestDismiss => 'Dispensar';

  @override
  String get runDetailSuggestRanRoute => 'Parece que correu ';

  @override
  String get runDetailSuggestLinkPrompt => 'Vincular esta corrida a essa rota?';

  @override
  String get runDetailMatchPending => 'A ajustar às ruas…';

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
  String get runDetailRematchQueueing => 'A adicionar à fila…';

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
  String get publicRunLiveTitle => 'Em direto agora';

  @override
  String get publicRunLiveSub =>
      'Esta corrida ainda está a decorrer. Acompanhe no rastreador em direto.';

  @override
  String get publicRunWatchLive => 'Ver em direto';

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
      'Falha na importação: escolha o ficheiro do armazenamento local, não de um seletor de documentos apenas na nuvem.';

  @override
  String routesImported(String name) {
    return '\"$name\" importada';
  }

  @override
  String routesImportedMany(int count) {
    return 'Importadas $count rotas';
  }

  @override
  String routesImportFailed(String error) {
    return 'Falha na importação: $error';
  }

  @override
  String get routesImportSharedFailed =>
      'Não foi possível importar o ficheiro: não é uma rota válida.';

  @override
  String routesSaved(String name) {
    return '\"$name\" guardada';
  }

  @override
  String get historySelectionHint =>
      'Toca e mantém numa corrida para selecionar várias';

  @override
  String get routesSelectionHint =>
      'Toca e mantém numa rota para selecionar várias';

  @override
  String get routesEmptyTitle => 'Nenhuma rota ainda';

  @override
  String get routesEmptyBody =>
      'Toque em Criar para desenhar uma rota no mapa ou importe um ficheiro GPX, KML, KMZ, GeoJSON ou TCX.';

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
  String get routesSavedForOffline => 'Guardado para uso offline';

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
  String get routesHeatmapTooltip => 'Mapa de calor das rotas';

  @override
  String get routesSearchHint => 'Procurar rotas por nome…';

  @override
  String get routesClearSearch => 'Limpar pesquisa';

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
  String get routesSurfaceTrail => 'Trilho';

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
      other: 'Eliminar $count rotas?',
      one: 'Eliminar $count rota?',
    );
    return '$_temp0';
  }

  @override
  String get routesDeleteConfirmBody => 'Isto não pode ser desfeito.';

  @override
  String routesSelectionTitle(int count) {
    return '$count selecionada(s)';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted eliminada(s); $failed com falha — verifique a sua ligação.';
  }

  @override
  String routesDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rotas eliminadas.',
      one: '$count rota eliminada.',
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
      'Não foi possível traçar — mostrando linhas retas entre os seus pontos.';

  @override
  String get routeBuilderSnapUnavailable =>
      'O ajuste às estradas está indisponível — os pinos ficam onde toca, ligados por linhas retas.';

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
    return 'Guardado localmente. $detail Será sincronizado da próxima vez.';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'Não foi possível aceder ao servidor. Faça login ou verifique a sua ligação e tente novamente.';

  @override
  String routeBuilderSaveFailed(String error) {
    return 'Falha ao guardar: $error';
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
      'Todos os pontos serão removidos. Isto não pode ser desfeito.';

  @override
  String get routeBuilderSaving => 'A guardar…';

  @override
  String get routeBuilderSave => 'Guardar';

  @override
  String get routeBuilderLocateMe => 'Localizar-me';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'Toque para mover o ponto $number, ou utilize os ícones';
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
    return 'Eliminar o ponto $number';
  }

  @override
  String get routeBuilderCancelDrag => 'Cancelar arrasto';

  @override
  String get routeBuilderPointList => 'Pontos da rota';

  @override
  String routeBuilderPointMovedTo(int from, int to) {
    return 'Ponto $from movido para a posição $to';
  }

  @override
  String routeBuilderPointRemoved(int number) {
    return 'Ponto $number removido';
  }

  @override
  String routeBuilderReorderPoint(int number) {
    return 'Reordenar o ponto $number';
  }

  @override
  String get routeBuilderPointStart => 'Início';

  @override
  String get routeBuilderPointEnd => 'Fim';

  @override
  String get routeBuilderModeTrail => 'Trilho';

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
  String get routeBuilderSaveDialogTitle => 'Guardar rota';

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
  String get routeBuilderSaveToLabel => 'Guardar em';

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
  String get routeDetailShare => 'Partilhar';

  @override
  String get routeDetailShareAsImage => 'Partilhar como imagem';

  @override
  String get routeDetailShareAsGpx => 'Partilhar como GPX';

  @override
  String get routeDetailShareAsKml => 'Partilhar como KML';

  @override
  String get routeDetailShareLink => 'Partilhar link';

  @override
  String get routeDetailSendToWatch => 'Enviar para o relógio';

  @override
  String routeDetailWatchCourseSent(int points) {
    return 'Percurso enviado para o relógio ($points pontos)';
  }

  @override
  String routeDetailWatchCourseSimplified(int source, int points) {
    return 'Percurso enviado para o relógio — reduzido de $source para $points pontos para caber';
  }

  @override
  String get routeDetailWatchCourseTooShort =>
      'Esta rota tem pontos de menos para ser seguida no relógio';

  @override
  String get routeDetailWatchPushRejected =>
      'O relógio recusou o envio e manteve o que já tinha. Tente novamente.';

  @override
  String routeDetailWatchCourseFailed(String error) {
    return 'Não foi possível enviar o percurso para o relógio: $error';
  }

  @override
  String get routeDetailSendToAppleWatch => 'Enviar para o Apple Watch';

  @override
  String routeDetailAppleWatchRouteSent(int points) {
    return 'Rota enviada para o Apple Watch ($points pontos)';
  }

  @override
  String routeDetailAppleWatchRouteSimplified(int source, int points) {
    return 'Rota enviada para o Apple Watch — reduzida de $source para $points pontos para caber';
  }

  @override
  String get routeDetailAppleWatchRouteTooShort =>
      'Esta rota tem pontos de menos para ser seguida no Apple Watch';

  @override
  String routeDetailAppleWatchRouteFailed(String error) {
    return 'Não foi possível enviar a rota para o Apple Watch: $error';
  }

  @override
  String routeDetailWatchCourseAndScheduleSent(int points, int checkpoints) {
    return 'Percurso ($points pontos) e plano de corrida ($checkpoints pontos de controlo) enviados para o relógio';
  }

  @override
  String routeDetailWatchScheduleThinned(
    int points,
    int source,
    int checkpoints,
  ) {
    return 'Percurso ($points pontos) enviado. Plano de corrida reduzido de $source para $checkpoints pontos de controlo para caber no relógio';
  }

  @override
  String routeDetailWatchScheduleClockCutoffs(int checkpoints, int unresolved) {
    return 'Plano de corrida enviado ($checkpoints pontos de controlo), mas $unresolved cortes por hora precisam de uma hora de partida — defina uma na folha de equipa para chegarem ao relógio';
  }

  @override
  String routeDetailWatchScheduleTooManyCutoffs(
    int points,
    int cutoffs,
    int max,
  ) {
    return 'Percurso ($points pontos) enviado, mas o plano de corrida tem $cutoffs cortes e o relógio suporta $max — remova alguns para o enviar';
  }

  @override
  String get routeDetailMadePublicForLink =>
      'Tornada pública para que qualquer pessoa com o link possa vê-la';

  @override
  String get routeDetailShareConfirmTitle => 'Tornar esta rota pública?';

  @override
  String get routeDetailShareConfirmBody =>
      'Partilhar um link torna esta rota pública — qualquer pessoa com o link pode abri-la e ela pode aparecer em Explorar. Pode torná-la privada novamente quando quiser.';

  @override
  String get routeDetailShareConfirmCta => 'Tornar pública e partilhar';

  @override
  String routeDetailShareLinkFailed(String error) {
    return 'Não foi possível partilhar o link: $error';
  }

  @override
  String get routeDetailShareAsGpxMarkers => 'Partilhar como GPX + marcadores';

  @override
  String get routeDetailRemoveOfflineSave => 'Remover gravação offline';

  @override
  String get routeDetailSaveForOffline => 'Guardar para uso offline';

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
  String get routeDetailReportReview => 'Denunciar avaliação';

  @override
  String get routeDetailTransferToClub => 'Transferir para clube';

  @override
  String get routeDetailManageClub => 'Desanexar ou mover para outro clube';

  @override
  String get routeDetailDeleteRoute => 'Eliminar rota';

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
      'Qualquer pessoa com o link de partilha pode ver esta rota';

  @override
  String get routeDetailPrivateSubtitle => 'Apenas pode ver esta rota';

  @override
  String get routeDetailSavedForOffline => 'Guardado para uso offline';

  @override
  String get routeDetailSaveForOfflineTitle => 'Guardar para uso offline';

  @override
  String get routeDetailOfflinePinnedSubtitle =>
      'A rota fica neste telefone para si percorrê-la sem ligação.';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'Mantenha esta rota no seu telefone para utilizar sem rede.';

  @override
  String get routeDetailDescriptionHeading => 'Descrição';

  @override
  String get routeDetailDescribe => 'Descrever esta rota';

  @override
  String get routeDetailDescribing => 'A descrever…';

  @override
  String get routeDetailAiAttribution =>
      'Escrito por IA a partir dos dados da rota';

  @override
  String get routeDetailDescribeFailed =>
      'Não foi possível gerar uma descrição. Tente novamente.';

  @override
  String get routeDetailDescribeConsentRequired =>
      'As descrições por IA precisam do seu consentimento às informações de IA atualizadas.';

  @override
  String get routeDetailReviewDisclosure => 'Ver as informações';

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
  String get routeDetailDescSurfaceTrail => 'de trilho';

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
  String get routeDetailSurfaceTrail => 'TRILHO';

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
  String get routeDetailDeleteReview => 'Eliminar a sua avaliação';

  @override
  String routeDetailReviewDeleteFailed(String error) {
    return 'Não foi possível eliminar a avaliação: $error';
  }

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
  String get routeDetailOfflineSaved => 'Guardado para uso offline.';

  @override
  String get routeDetailOfflineRemoved => 'Removido dos gravações offline.';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'Não foi possível guardar a etiqueta: $error';
  }

  @override
  String routeDetailTagRemoveFailed(String error) {
    return 'Não foi possível remover a etiqueta: $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return 'Não foi possível partilhar $format: $error';
  }

  @override
  String get routeDetailClubsLoadTimeout =>
      'Não foi possível carregar os seus clubes — verifique a sua rede.';

  @override
  String get routeDetailClubsLoadFailed =>
      'Não foi possível carregar os seus clubes.';

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
  String get routeDetailDeleteTitle => 'Eliminar rota?';

  @override
  String get routeDetailDeleteBody => 'Isto não pode ser desfeito.';

  @override
  String get routeDetailDelete => 'Eliminar';

  @override
  String routeDetailDeleteFailed(String error) {
    return 'Falha ao eliminar: $error';
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
  String get routeDetailManageClubTitle => 'Gerir propriedade do clube';

  @override
  String get routeDetailTransferDialogBody =>
      'Os membros do clube verão esta rota na biblioteca do clube e poderão adotá-la em os seus planos.';

  @override
  String get routeDetailManageClubBody =>
      'Mova esta rota para outro clube que administra, ou desanexe-a de volta para pessoal.';

  @override
  String get routeDetailDetachToPersonal => 'Desanexar para pessoal';

  @override
  String get routeDetailDetachSubtitle =>
      'Remove a rota da biblioteca do clube atual.';

  @override
  String get routeDetailNoAdminClubs =>
      'Ainda não possui nem administra nenhum clube.';

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
  String get exploreRoutesModeSearch => 'Procurar';

  @override
  String get exploreRoutesModeNearMe => 'Perto de mim';

  @override
  String get exploreRoutesSearchHint => 'Procurar rotas por nome...';

  @override
  String get exploreRoutesFeatured => 'Destaque';

  @override
  String get exploreRoutesSignInRequired =>
      'Faça login e conecte-se à internet para explorar rotas';

  @override
  String get exploreRoutesTimeout =>
      'A ligação expirou. Verifique a sua rede e tente novamente.';

  @override
  String get exploreRoutesSearchFailed =>
      'Falha na pesquisa. Toque em Tentar novamente.';

  @override
  String get exploreRoutesLoadMoreFailed =>
      'Não foi possível carregar mais — verifique a sua ligação';

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
      'Nenhuma rota corresponde à sua pesquisa';

  @override
  String get exploreRoutesEmptyBody =>
      'As rotas partilhadas pelo app web aparecem aqui';

  @override
  String get exploreRoutesDistanceAny => 'Qualquer distância';

  @override
  String get exploreRoutesSurfaceAny => 'Qualquer superfície';

  @override
  String get exploreRoutesSurfaceRoad => 'Estrada';

  @override
  String get exploreRoutesSurfaceTrail => 'Trilho';

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
    return 'Não foi possível guardar \"$name\" — verifique a sua ligação e tente novamente.';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return 'Não foi possível guardar \"$name\".';
  }

  @override
  String exploreRoutesSaved(String name) {
    return '\"$name\" guardada na sua biblioteca';
  }

  @override
  String get exploreRoutesAlreadySaved => 'Já guardada';

  @override
  String get exploreRoutesSaveToLibrary => 'Guardar na biblioteca';

  @override
  String get exploreRoutesSurfaceTrailShort => 'Trilho';

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
  String get runHeatmapTitle => 'O seu mapa de calor';

  @override
  String get runHeatmapTooltip => 'Mapa de calor de corridas';

  @override
  String get runHeatmapLoading => 'A carregar as suas corridas…';

  @override
  String runHeatmapLoadingProgress(int n, int total) {
    return 'A carregar as suas corridas… $n/$total';
  }

  @override
  String get runHeatmapEmptyTitle => 'Nenhuma corrida mapeada ainda';

  @override
  String get runHeatmapEmptyBody =>
      'Grave ou importe corridas com trajetos de GPS e elas vão aparecer aqui.';

  @override
  String get runHeatmapSignedOutTitle =>
      'Entre para ver o seu mapa de calor sincronizado';

  @override
  String get runHeatmapSignedOutBody =>
      'As corridas gravadas neste dispositivo aparecem aqui. Entre para incluir também as suas corridas sincronizadas.';

  @override
  String get runHeatmapErrorTitle =>
      'Não foi possível carregar o seu mapa de calor';

  @override
  String get runHeatmapErrorBody =>
      'Algo deu errado ao carregar as suas corridas. Verifique a sua ligação e tente novamente.';

  @override
  String get runHeatmapRetry => 'Tentar novamente';

  @override
  String get runHeatmapLegendTitle => 'O seu mapa de calor';

  @override
  String runHeatmapLegendSummaryOne(int n) {
    return '$n corrida mapeada — mais brilhante onde corre mais.';
  }

  @override
  String runHeatmapLegendSummaryMany(int n) {
    return '$n corridas mapeadas — mais brilhante onde corre mais.';
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
      'Não foi possível carregar as suas rotas. Verifique a sua ligação e tente novamente.';

  @override
  String get feedTitle => 'Feed';

  @override
  String get feedFindPeople => 'Encontrar pessoas';

  @override
  String runNotificationPausedTitle(String activity) {
    return '$activity • em pausa';
  }

  @override
  String get activityTypeRun => 'Corrida';

  @override
  String get activityTypeWalk => 'Caminhada';

  @override
  String get activityTypeHike => 'Trail';

  @override
  String get activityTypeCycle => 'Ciclismo';

  @override
  String get activityTypeStroller => 'Carrinho de bebé';

  @override
  String get feedActivityAll => 'Tudo';

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
  String get feedEveryoneYouFollow => 'Todos que segue';

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
  String get feedEmptyTitle => 'O seu feed está vazio';

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
      'Ninguém que segue registou uma corrida pública nos últimos 14 dias.';

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
  String get profileTabFollowing => 'A seguir';

  @override
  String get profileTabNotifications => 'Notificações';

  @override
  String get profileReportUser => 'Denunciar utilizador';

  @override
  String get profileUnblock => 'Desbloquear este perfil';

  @override
  String get profileBlock => 'Bloquear este perfil';

  @override
  String get profileLoadError => 'Não foi possível carregar o perfil.';

  @override
  String get profileSectionError => 'Não foi possível carregar esta secção.';

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
  String get profileFollowing => 'A seguir';

  @override
  String get profileFollow => 'Seguir';

  @override
  String get profileRunsEmptySelf => 'Ainda não partilhou nenhuma corrida.';

  @override
  String get profileRunsEmptyOther => 'Nenhuma corrida pública ainda.';

  @override
  String get profileFollowersEmpty => 'Nenhum seguidor ainda.';

  @override
  String get profileFollowingEmpty => 'Ainda não segue ninguém.';

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
      'Esta pessoa não poderá segui-lo, dar kudos às suas corridas nem comentá-las. Qualquer seguimento existente entre ambos, em qualquer direção, será removido. Pode desbloquear nesta página a qualquer momento.';

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
  String get profileNotifsCaughtUp => 'Está em dia.';

  @override
  String get profileNotifsEmpty => 'Ainda não há notificações.';

  @override
  String get profileDismiss => 'Dispensar';

  @override
  String profileDismissFailed(String error) {
    return 'Não foi possível dispensar: $error';
  }

  @override
  String get profileNotifSomeone => 'Alguém';

  @override
  String get profileNotifYourRun => 'corrida';

  @override
  String profileNotifNameAndOthers(String name, int count) {
    return '$name e mais $count';
  }

  @override
  String profileNotifAndOthers(int count) {
    return 'e mais $count';
  }

  @override
  String get profileNotifShowLess => 'Mostrar menos';

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
    return '$name começou a seguir o seu perfil';
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
    return '$name atualizou o seu plano de treino';
  }

  @override
  String profileNotifMessage(String name) {
    return '$name enviou-lhe uma mensagem';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$name publicou em $club';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$name publicou num clube em que participas';
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
  String profileNotifPlanAssigned(String name) {
    return '$name atribuiu-lhe um plano de treino';
  }

  @override
  String profileNotifEventCancelTitled(String title) {
    return 'Uma ocorrência de \"$title\" foi cancelada';
  }

  @override
  String get profileNotifEventCancel =>
      'Uma ocorrência de um evento que confirmaste foi cancelada';

  @override
  String profileNotifEventReminderTitled(String title) {
    return '\"$title\" está a chegar';
  }

  @override
  String get profileNotifEventReminder =>
      'Um evento a que vai comparecer está a chegar';

  @override
  String get profileNotifAchievement => 'Ganhaste uma nova conquista';

  @override
  String get profileNotifChallengeComplete => 'Completaste um desafio';

  @override
  String get profileNotifContentHidden =>
      'Uma das suas publicações foi ocultada após ser denunciada';

  @override
  String get profileNotifDataExportReady =>
      'A sua exportação de dados está pronta para transferir';

  @override
  String get profileNotifRefundFailed =>
      'Um reembolso que iniciámos não pôde ser concluído. O dinheiro continua connosco e vamos combinar outra forma de o devolver.';

  @override
  String profileNotifGeneric(String name) {
    return '$name interagiu com a sua atividade';
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
  String get discoverSearchPlaceholder => 'Procurar aulas, clubes…';

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
  String get discoverLoading => 'A procurar…';

  @override
  String get discoverEmpty =>
      'Nenhuma atividade pública corresponde a esses filtros ainda.';

  @override
  String get discoverSearchFailed =>
      'Não foi possível carregar as atividades. Verifique a sua ligação e tente novamente.';

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
      'A ligação expirou. Verifique a sua rede e tente novamente.';

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
  String get clubsEmptyMineTitle => 'Ainda não entrou em nenhum clube.';

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
  String get clubDetailTabPhotos => 'Fotografias';

  @override
  String get clubDetailReadMore => 'Ler mais';

  @override
  String get clubDetailReportClub => 'Denunciar clube';

  @override
  String get clubDetailReportPost => 'Denunciar esta publicação';

  @override
  String get clubDetailLoadFailedBody =>
      'Não foi possível carregar este clube. Pode ter sido removido, ou a sua sessão precisa ser atualizada. Puxe para tentar novamente, ou saia e entre novamente em Definições.';

  @override
  String get clubDetailTimeoutError =>
      'A ligação expirou. Verifique a sua rede e tente novamente.';

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
      'Nenhuma publicação ainda. Partilhe uma novidade com os membros.';

  @override
  String get clubDetailNoPosts => 'Nenhuma novidade ainda.';

  @override
  String get clubDetailShareUpdateHint => 'Partilhe uma novidade…';

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
    return 'Utilizador $id…';
  }

  @override
  String get clubDetailDeny => 'Recusar';

  @override
  String get clubDetailDenyTitle => 'Recusar pedido de adesão';

  @override
  String get clubDetailDenyMessage =>
      'Recusar este pedido para entrar no clube? A pessoa não será adicionada.';

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
    return '\"$name\" guardada';
  }

  @override
  String get clubDetailBuildRoute => 'Criar rota para este clube';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'Nenhuma rota ainda. Crie o percurso oficial acima, ou transfira uma das suas rotas pessoais no ecrã de detalhes da rota.';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'Nenhuma rota ainda. Os administradores podem transferir uma de as suas rotas pessoais no ecrã de detalhes da rota.';

  @override
  String get clubDetailRoutesEmpty =>
      'Nenhuma rota partilhada com este clube ainda.';

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
      'Modelos de rotina de ginásio';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'Os membros podem adotar uma rotina de ginásio do clube nas próprias rotinas. As edições numa cópia não se propagam para o modelo.';

  @override
  String get clubDetailGymRoutineAdopted =>
      'Rotina adicionada às suas rotinas de ginásio.';

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
      'A ligação expirou. Verifique a sua rede e tente novamente.';

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
    return 'Falha no controlo da corrida: $error';
  }

  @override
  String eventAttendees(int count) {
    return 'PARTICIPANTES ($count)';
  }

  @override
  String eventPhotosTitle(int count) {
    return 'Fotografias ($count)';
  }

  @override
  String get eventAddPhoto => 'Adicionar fotografia';

  @override
  String get eventPhotoUploading => 'A enviar…';

  @override
  String get eventNoPhotosYet => 'Ainda não há fotografias.';

  @override
  String get eventNoPhotosAddHint => 'Seja o primeiro a adicionar uma.';

  @override
  String get eventWhichRunPhoto => 'De qual corrida é esta fotografia?';

  @override
  String get eventNoRecentRuns =>
      'Nenhuma corrida recente encontrada. Registe uma corrida primeiro e volte.';

  @override
  String get eventPhotoRunnerFallback => 'Um corredor';

  @override
  String get eventPhotoUploadFailed => 'Não foi possível enviar a fotografia.';

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
      'Não foi possível atualizar a sua confirmação. Tente novamente.';

  @override
  String get eventRsvpGoing => 'Eu vou';

  @override
  String get eventRsvpMaybe => 'Talvez';

  @override
  String get eventOccurrenceCancelled => 'Esta ocorrência foi cancelada.';

  @override
  String get eventRsvpWaitlisted => 'Na lista de espera';

  @override
  String get eventRsvpDeclined => 'Não posso ir';

  @override
  String get eventRaceArmed => 'Armado — aguardando o GO';

  @override
  String get eventRaceRunning => 'Em curso — em direto';

  @override
  String get eventRaceFinished => 'Concluído';

  @override
  String get eventRaceCancelled => 'Cancelado';

  @override
  String get eventRaceNotArmed => 'Não armado';

  @override
  String get eventRaceControlLabel => 'CONTROLO DA CORRIDA';

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
      'Encerrar a corrida? Isto finaliza o evento para todos os corredores e não pode ser desfeito.';

  @override
  String get eventRaceCancelConfirmBody =>
      'Cancelar a corrida? Isto aborta o evento para todos os corredores e não pode ser desfeito.';

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
  String get eventRemoveResultTitle => 'Remover o seu resultado?';

  @override
  String get eventRemoveResultBody =>
      'O seu tempo de chegada enviado será removido da classificação deste evento. Pode enviar novamente mais tarde.';

  @override
  String get eventRemoveResultConfirm => 'Remover resultado';

  @override
  String eventRemoveResultFailed(String error) {
    return 'Não foi possível remover o seu resultado: $error';
  }

  @override
  String get eventSubmitMyTime => 'Enviar meu tempo';

  @override
  String get eventSubmitting => 'A enviar…';

  @override
  String get eventNoResults =>
      'Nenhum resultado ainda. Envie o seu tempo após o evento e os outros verão aqui.';

  @override
  String get eventResultRunner => 'Corredor';

  @override
  String get eventResultYou => '(tu)';

  @override
  String get eventSubmitTimeTitle => 'Envie o seu tempo';

  @override
  String get eventSubmitTimeSubtitle =>
      'Escolha uma corrida para anexar, ou registe um DNF / DNS.';

  @override
  String get eventRecordDnf => 'Registar DNF';

  @override
  String get eventRecordDns => 'Registar DNS';

  @override
  String get eventSubmitCancel => 'Cancelar';

  @override
  String get liveSpectatorTitle => 'Acompanhamento em direto';

  @override
  String get liveSpectatorConnectError => 'Não foi possível conectar.';

  @override
  String get liveSpectatorWaiting =>
      'A aguardar o corredor enviar o primeiro sinal…';

  @override
  String get liveSpectatorBadgeLive => 'Em direto';

  @override
  String get liveSpectatorBadgeIdle => 'Parado';

  @override
  String get liveSpectatorBadgeConnecting => 'A conectar';

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
  String get liveSpectatorStatRaceTime => 'Tempo de prova';

  @override
  String get liveSpectatorStatTimer => 'Cronómetro';

  @override
  String get liveSpectatorStatTimerStale => 'Cronómetro, último sinal';

  @override
  String get liveSpectatorRecentPace => 'Recente';

  @override
  String liveSpectatorCourseProgress(int p) {
    return '$p% do percurso';
  }

  @override
  String liveSpectatorMotionStopped(int n) {
    return 'Sem movimento — $n min no mesmo ponto';
  }

  @override
  String liveSpectatorMotionStoppedAtLeast(int n) {
    return 'Sem movimento — pelo menos $n min no mesmo ponto';
  }

  @override
  String get liveSpectatorConcludedTitle => 'Corrida concluída';

  @override
  String get liveSpectatorConcludedBody =>
      'Veja o percurso completo, as parciais e as estatísticas.';

  @override
  String get liveSpectatorViewFullRun => 'Ver a corrida completa';

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
  String get liveCutoffSignalLost =>
      'Sinal perdido — não é possível prever a chegada';

  @override
  String get liveCutoffExpired => 'O tempo de corte já passou';

  @override
  String liveCutoffRequiredPace(String pace) {
    return 'Precisa de $pace a partir daqui';
  }

  @override
  String liveCutoffRequiredPaceStale(String pace) {
    return 'Precisa de $pace desde a última posição';
  }

  @override
  String get plansTitle => 'Planos de treino';

  @override
  String get plansNewPlan => 'Novo plano';

  @override
  String plansDeleteTitle(String name) {
    return 'Eliminar \"$name\"?';
  }

  @override
  String get plansDeleteBody => 'Todas as semanas e treinos serão removidos.';

  @override
  String get plansCancel => 'Cancelar';

  @override
  String get plansDelete => 'Eliminar';

  @override
  String get plansAbandon => 'Abandonar';

  @override
  String plansAbandonTitle(String name) {
    return 'Abandonar \"$name\"?';
  }

  @override
  String get plansAbandonBody => 'Depois pode criar um novo plano.';

  @override
  String plansActionFailed(String error) {
    return 'Não foi possível atualizar o plano: $error';
  }

  @override
  String plansDaysPerWeek(int count) {
    return '$count dias/sem.';
  }

  @override
  String get plansSignInTitle => 'Entre para utilizar os planos de treino';

  @override
  String get plansSignInBody =>
      'Os planos sincronizam com a sua conta e acompanham-no em todos os dispositivos. Vá a Definições → Entrar para começar.';

  @override
  String get plansEmptyTitle => 'Nenhum plano ainda.';

  @override
  String get plansEmptyBody =>
      'Escolha uma prova-alvo e montaremos as semanas para si.';

  @override
  String get plansTimeoutError =>
      'Tempo de ligação esgotado. Verifique a sua rede e tente novamente.';

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
  String get planNewNameRequiredHint =>
      'Adicione um nome de plano para ativar Criar.';

  @override
  String planNewDefaultName(String goal) {
    return 'Plano de $goal';
  }

  @override
  String planNewDefaultNameBeginner(String goal) {
    return 'Caminhada-corrida até $goal';
  }

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
      'Está a começar a correr? Utilize um plano de caminhada-corrida';

  @override
  String get planNewBeginnerSubtitle =>
      'Um cronograma suave no estilo C25K de intervalos cronometrados de corrida/caminhada que evolui até uma corrida contínua. Substitui o ritmo do tempo-alvo.';

  @override
  String get planNewRecent5kSection => 'Tempo recente de 5K · opcional';

  @override
  String get planNewRecent5kHelp =>
      'Baseie os ritmos num resultado real em vez da meta. Utiliza a equivalência de Riegel para projetar até a distância-alvo.';

  @override
  String get planNewRecent5kConfirm =>
      'É um tempo que eu conseguiria correr hoje — reflete meu condicionamento atual.';

  @override
  String get planNewRecent5kWarning =>
      'Até confirmar, os ritmos permanecem na estimativa conservadora baseada na meta. Basear-se num resultado antigo pode prescrever ritmos demasiado rápidos para quem está a voltar.';

  @override
  String get planNewOverrideHint => 'Substituir o total de semanas';

  @override
  String planNewOverrideLabel(int count) {
    return 'Substituir semanas (predefinição: $count)';
  }

  @override
  String planNewRaceAnchored(int weeks) {
    return 'Ajustado à sua corrida: um plano de $weeks semanas cuja última semana é a da prova. Altere o que quiser antes de criar.';
  }

  @override
  String get planNewRacePast =>
      'Essa corrida já aconteceu, então as datas abaixo são as predefinidas.';

  @override
  String get planNewRaceTooSoon =>
      'Essa corrida está demasiado próxima para montar um plano completo, então as datas abaixo são as predefinidas.';

  @override
  String get planNewRaceUnreadable =>
      'Não conseguimos ler a data dessa corrida, então as datas abaixo são as predefinidas.';

  @override
  String get planNewCancel => 'Cancelar';

  @override
  String get planNewCreate => 'Criar plano';

  @override
  String get planNewCreating => 'A criar…';

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
  String get planNewRampLabel => 'O plano em relação ao seu treino recente';

  @override
  String planNewRampUnder(String peak, String recent) {
    return 'Este plano chega no máximo a $peak por semana, abaixo dos $recent por semana que correu em média nas últimas quatro semanas. Uma prova-alvo mais longa ou mais dias de treino aproveitariam melhor essa base.';
  }

  @override
  String planNewRampElevated(String opening, String recent) {
    return 'A semana 1 pede $opening contra os $recent por semana que correu em média nas últimas quatro semanas — é um degrau real. Entre com calma ou tire um dia de treino.';
  }

  @override
  String planNewRampHigh(String opening, String recent) {
    return 'A semana 1 pede $opening, bem acima dos $recent por semana que correu em média nas últimas quatro semanas. Menos dias de treino, uma prova-alvo mais curta ou algumas semanas de base antes deixariam esse primeiro passo mais seguro.';
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
      'Adote um plano que um clube ao qual pertence publicou. Ele é clonado na sua conta com a data de início abaixo — edite como qualquer outro plano.';

  @override
  String get planNewTemplateButton => 'Ver modelos';

  @override
  String get planNewTemplateCloning => 'A adotar…';

  @override
  String get planNewTemplateCloneFailed =>
      'Não foi possível adotar esse modelo.';

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
  String get planLibrarySearchHint => 'Procurar planos por nome';

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
  String get planLibraryCloning => 'A clonar…';

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
      'Partilhe uma cópia deste plano para que qualquer pessoa possa cloná-lo. Os seus dados de condicionamento não são partilhados.';

  @override
  String get planDetailPublishLibrarySuccess =>
      'Plano publicado na biblioteca pública. O seu plano pessoal não muda.';

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
      'Escolha um plano de treino comprovado e o agendamos a partir da sua data de início; pode ajustá-lo depois.';

  @override
  String get planNewStarterButton => 'Explorar planos iniciais';

  @override
  String get planNewStarterCreating => 'A criar…';

  @override
  String get planNewStarterPickerTitle => 'Escolha um plano inicial';

  @override
  String get planNewStarterPickerCancel => 'Cancelar';

  @override
  String get planNewStarterCreateFailed => 'Não foi possível criar esse plano.';

  @override
  String get planNewReplaceActiveTitle => 'Substituir o seu plano ativo?';

  @override
  String planNewReplaceActiveNamed(String name) {
    return 'Já tem um plano ativo: \"$name\". Criar um novo plano marcará o atual como concluído (ainda poderá encontrá-lo em Gerir planos). Continuar?';
  }

  @override
  String get planNewReplaceActiveUnnamed =>
      'Já tem um plano ativo. Criar um novo plano marcará o atual como concluído. Continuar?';

  @override
  String get planNewReplaceActiveConfirm => 'Substituir plano';

  @override
  String get planNewReplaceActiveKeep => 'Manter o atual';

  @override
  String get planNewStarterC25k => 'Couch to 5K (iniciante caminhada-corrida)';

  @override
  String get planNewStarterHalf12 => 'Meia maratona — 12 semanas';

  @override
  String get planNewStarterMarathon16 => 'Maratona — 16 semanas';

  @override
  String get planDetailTimeoutError =>
      'Tempo de ligação esgotado. Verifique a sua rede e tente novamente.';

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
    return 'Esta semana $pct% acima do plano — vá com calma nos dias fáceis para não cavar um buraco de fadiga.';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return 'Esta semana $pct% abaixo do plano — o volume planeado impulsiona a adaptação.';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      'Perdeu o longão desta semana — encaixe se puder. É a sessão que mais importa.';

  @override
  String get planDetailMissedLongTaper =>
      'Perdeu um longão, mas está em polimento — deixe para lá e chegue descansado para a prova.';

  @override
  String get planDetailMissedLongRecovery =>
      'Perdeu um longão — não tente repor. Uma semana de recuperação vem aí e o seu corpo vai aproveitar o descanso.';

  @override
  String get planDetailReplan => 'Replanear as semanas restantes';

  @override
  String get planDetailAdaptiveReplan => 'Replaneamento adaptativo';

  @override
  String get planDetailAdaptiveOnTrack =>
      'As suas últimas semanas estão dentro do plano — nenhum ajuste necessário.';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      'Se desviou do plano recentemente, mas não há um ajuste seguro a fazer agora.';

  @override
  String get planDetailAdaptiveFitnessHeld =>
      'Pausado — está a acumular fadiga agora, então aumentar o volume não é recomendado.';

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
    return 'Com base numa tendência — esteve $reason ($confidence)';
  }

  @override
  String get planDetailReplanOnTrack =>
      'O seu plano está em dia — nada a ajustar.';

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
  String get planDetailDuplicateConfirmTitle => 'Duplicar esta semana?';

  @override
  String planDetailDuplicateConfirmMessage(int n) {
    return 'Isto insere uma cópia da semana $n e empurra cada semana seguinte e a data da sua prova em 7 dias.';
  }

  @override
  String get planDetailDuplicateConfirm => 'Duplicar';

  @override
  String planDetailBulkFailed(String error) {
    return 'Não foi possível atualizar o plano: $error';
  }

  @override
  String get planDetailEditTooltip => 'Editar treino';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'Não foi possível carregar os seus clubes — verifique a sua rede.';

  @override
  String get planDetailPublishLoadClubsFailed =>
      'Não foi possível carregar os seus clubes.';

  @override
  String get planDetailPublishNoClubs =>
      'Precisa ser dono ou administrador de um clube para publicar um modelo.';

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
      'Tempo de ligação esgotado. Verifique a sua rede e tente novamente.';

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
  String get workoutRelinkLoading => 'A procurar as suas corridas…';

  @override
  String get workoutRelinkError =>
      'Não foi possível carregar as suas corridas. Tente novamente.';

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
      'Ritmo de conversa. Se não consegue conversar, está a correr demasiado depressa.';

  @override
  String get workoutAdviceLong =>
      'Fique relaxado. Procure uma respiração constante. Reduza 10% da distância se o clima estiver ruim ou estiver dolorido — mas não salte.';

  @override
  String get workoutAdviceTempo =>
      '\"Confortavelmente difícil\". deve sentir que conseguiria manter o ritmo por cerca de uma hora em esforço máximo, mas não mais.';

  @override
  String get workoutAdviceInterval =>
      'Corra as repetições com intensidade suficiente para que a última pareça a primeira. Não escolha um ritmo que só consiga manter por duas ou três repetições.';

  @override
  String get workoutAdviceMarathonPace =>
      'Trave exatamente no ritmo-alvo de maratona. Esta é uma sessão de ensaio — nem mais depressa, nem mais devagar.';

  @override
  String get workoutAdviceWalkRun =>
      'Alterne corrida leve e caminhada nos intervalos cronometrados. As pausas para caminhar fazem parte do treino — faça-as mesmo se estiver descansado.';

  @override
  String get workoutAdviceRace =>
      'Confie no plano. Não persiga um recorde no primeiro quilómetro.';

  @override
  String get workoutAdviceRest =>
      'Dia de descanso — se precisar se mexer, caminhe ou alongue.';

  @override
  String get coachTitle => 'Treinador IA';

  @override
  String get coachNewConversation => 'Nova conversa';

  @override
  String get coachConsentHeadline =>
      'Antes de utilizar as funcionalidades de IA';

  @override
  String get coachConsentIntro =>
      'As funcionalidades de IA da Threkir — o Coach e o assistente de rotas com IA — enviam uma parte dos seus dados à Anthropic, nosso provedor de modelos de IA nos Estados Unidos. Consoante a funcionalidade utilizada, essa parte inclui:';

  @override
  String get coachConsentBulletProfile =>
      'A sua data de nascimento, género e zonas de FC, se definidas.';

  @override
  String get coachConsentBulletRuns =>
      'Uma amostra das suas corridas mais recentes.';

  @override
  String get coachConsentBulletPlan =>
      'O plano de treino ativo que selecionou.';

  @override
  String get coachConsentBulletMessages =>
      'As mensagens de chat que introduz no ecrã abaixo.';

  @override
  String get coachConsentBulletRoutes =>
      'Para o assistente de rotas com IA: o nome e os dados da rota, o pedido que escreve e uma referência aproximada do lugar — nunca as suas coordenadas exatas.';

  @override
  String get coachConsentProcessing =>
      'A Anthropic processa os dados em nome da Threkir conforme os seus termos de processamento; por predefinição, não treinam os seus modelos com dados de clientes da Threkir. Todos os detalhes — incluindo o mecanismo de transferência, a retenção e os seus direitos de retirada — estão na nossa política de privacidade.';

  @override
  String get coachConsentAction =>
      'Toque em \"Eu consinto\" para continuar. Toque em cancelar para sair da página sem enviar dados.';

  @override
  String get coachConsentCancel => 'Cancelar';

  @override
  String get coachConsentAccept =>
      'Eu consinto — ativar as funcionalidades de IA';

  @override
  String get coachConsentSaving => 'A registar consentimento…';

  @override
  String aiDisclosureRecordFailed(Object error) {
    return 'Não foi possível registar o consentimento: $error';
  }

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
  String get coachArchiveTapToView => 'Toque para ver';

  @override
  String get coachArchiveActions => 'Ações da conversa';

  @override
  String get coachArchiveDelete => 'Eliminar conversa';

  @override
  String get coachArchiveDeleteTitle => 'Eliminar esta conversa?';

  @override
  String get coachArchiveDeleteBody =>
      'Esta conversa arquivada será eliminada definitivamente.';

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
    return 'A ver arquivo · $label · apenas leitura';
  }

  @override
  String get coachBackToActive => 'Voltar ao ativo';

  @override
  String get coachLimitReachedPro => 'Limite diário atingido. Volte amanhã.';

  @override
  String get coachLimitReachedFree =>
      'Limite diário atingido. O Pro tem um teto maior — atualize nas Definições.';

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
      'Pergunte sobre o treino de hoje, o seu ritmo ou como as corridas recentes se comparam ao plano.';

  @override
  String get coachEmptyPromptNoPlan =>
      'Pergunte sobre as suas corridas recentes, o ritmo de corridas leves ou o básico do treino.';

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
  String get coachSuggestNewFirstRun => 'Nunca corri antes — por onde começo?';

  @override
  String get coachSuggestNewFirstFeel =>
      'Como deve ser a sensação da minha primeira corrida?';

  @override
  String get coachSuggestNewHowOften =>
      'Com que frequência devo correr como iniciante?';

  @override
  String get coachSuggestNewWalkRun =>
      'Não faz mal caminhar durante as corridas?';

  @override
  String get coachEditMessageLabel => 'Editar a sua mensagem';

  @override
  String get coachEditCancel => 'Cancelar';

  @override
  String get coachEditSaveResend => 'Guardar e reenviar';

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
      'O chat atual vai para o histórico. Pode revê-lo na barra lateral.';

  @override
  String get coachArchiveCancel => 'Cancelar';

  @override
  String get coachArchiveConfirm => 'Novo chat';

  @override
  String get coachSignInFirst => 'Por favor, entre primeiro.';

  @override
  String get coachSessionExpired =>
      'A sua sessão expirou. Por favor, entre novamente.';

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
      'Não foi possível alcançar o Coach. Verifique a sua ligação e tente novamente.';

  @override
  String get coachStreamFailed => 'falha no fluxo';

  @override
  String get coachNewConversationFailed =>
      'Não foi possível iniciar uma nova conversa.';

  @override
  String get coachOpenArchiveFailed => 'Não foi possível abrir o ficheiro.';

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Não foi possível eliminar o arquivo: $error';
  }

  @override
  String get coachReactionFailed =>
      'Não foi possível guardar a sua reação. Tente novamente.';

  @override
  String get coachCopied => 'Copiado para a área de transferência';

  @override
  String get settingsAccountTitle => 'Conta';

  @override
  String get settingsAccountBackendNotConfigured => 'Backend não configurado';

  @override
  String get settingsAccountSignOutFailed =>
      'Falha ao sair — verifique a sua ligação';

  @override
  String get settingsAccountChangePassword => 'Alterar palavra-passe';

  @override
  String get settingsAccountNewPassword => 'Nova palavra-passe';

  @override
  String get settingsAccountConfirm => 'Confirmar';

  @override
  String get settingsAccountCancel => 'Cancelar';

  @override
  String get settingsAccountSave => 'Guardar';

  @override
  String get settingsAccountPasswordsMismatch =>
      'As palavras-passe não coincidem';

  @override
  String get settingsAccountPasswordUpdated => 'Palavra-passe atualizada';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Não foi possível atualizar a palavra-passe: $error';
  }

  @override
  String get settingsAccountCurrentPassword => 'Palavra-passe atual';

  @override
  String get settingsAccountPasswordStepUpHint =>
      'Para a sua segurança, introduza a sua palavra-passe atual para alterá-la. Registou-se com Google ou Apple? Envie um link de redefinição para si mesmo para definir uma.';

  @override
  String get settingsAccountCurrentPasswordRequired =>
      'Introduza a sua palavra-passe atual para alterá-la.';

  @override
  String get settingsAccountCurrentPasswordIncorrect =>
      'Essa palavra-passe atual está incorreta. Se nunca definiu uma palavra-passe, envie um link de redefinição para si mesmo.';

  @override
  String get settingsAccountSendResetLink => 'Enviar link de redefinição';

  @override
  String get settingsAccountSendingResetLink => 'A enviar…';

  @override
  String get settingsAccountResetLinkSent =>
      'Link de redefinição enviado. Verifique o seu e-mail para definir uma nova palavra-passe.';

  @override
  String get settingsAccountChangeEmail => 'Alterar e-mail';

  @override
  String get settingsAccountNewEmail => 'Novo e-mail';

  @override
  String get settingsAccountEmailChangeInvalid =>
      'Introduza um endereço de e-mail válido e diferente do atual.';

  @override
  String settingsAccountEmailChangePending(Object old, Object newEmail) {
    return 'Confirmação pendente. Verifique tanto a sua caixa de entrada antiga ($old) quanto a nova ($newEmail) e siga o link em cada uma para concluir a alteração. O seu e-mail só muda depois que confirmar nas duas.';
  }

  @override
  String settingsAccountEmailChangeFailed(Object error) {
    return 'Não foi possível iniciar a alteração de e-mail: $error';
  }

  @override
  String get settingsAccountDeleteTitle => 'Eliminar conta?';

  @override
  String get settingsAccountDeleteBody =>
      'Isto remove permanentemente as suas corridas, rotas e perfil do servidor. Os dados locais do dispositivo são mantidos, a menos que entre como um novo utilizador. Isto não pode ser desfeito.';

  @override
  String get settingsAccountDeleteChallengeText =>
      'Introduza \"DELETE\" para confirmar';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return 'Introduza o seu e-mail ($email) para confirmar';
  }

  @override
  String get settingsAccountDelete => 'Eliminar';

  @override
  String get settingsAccountDeleteSignInFirst =>
      'Entre primeiro para eliminar a sua conta.';

  @override
  String get settingsAccountDeleted => 'Conta eliminada';

  @override
  String get settingsAccountCoachConsentWithdraw =>
      'Retirar o consentimento para as funcionalidades de IA';

  @override
  String get settingsAccountCoachConsentActive =>
      'Impeça as funcionalidades de IA da Threkir de utilizarem os seus dados. Pode consentir novamente quando quiser.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Consentimento para as funcionalidades de IA retirado.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Falha ao retirar o consentimento: $error';
  }

  @override
  String get settingsAccountAiConsentUpdateTitle =>
      'Aceitar as informações de IA atualizadas';

  @override
  String get settingsAccountAiConsentUpdateSubtitle =>
      'As informações passaram a abranger mais funcionalidades. Leia-as e aceite-as para utilizar o assistente de rotas com IA.';

  @override
  String get settingsAccountAiConsentGrantTitle => 'Ver as informações de IA';

  @override
  String get settingsAccountAiConsentGrantSubtitle =>
      'As funcionalidades de IA da Threkir pedem o seu consentimento antes de utilizarem os seus dados. Leia as informações e aceite-as aqui.';

  @override
  String get settingsAccountAiConsentAccepted => 'Informações de IA aceites.';

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'Falha ao eliminar a conta: $error';
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
  String get settingsAccountBackupPreparing => 'A preparar backup…';

  @override
  String get settingsAccountBackupShareText => 'Backup do Run app';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'Falha no backup: $error';
  }

  @override
  String settingsAccountBackupPartial(int count, int total) {
    return 'Exportação parcial — $count de $total corridas.';
  }

  @override
  String settingsAccountBackupPartialNotice(int count, int total) {
    return 'A sua última exportação está parcial: contém $count das $total corridas da sua conta. Nada foi eliminado — exporte novamente para tentar outra vez. O ficheiro completo da conta lista cada secção incompleta no manifest.json.';
  }

  @override
  String settingsAccountBackupTracksPartial(int missing, int total) {
    return 'Faltam $missing de $total ficheiros GPS na cópia de segurança.';
  }

  @override
  String settingsAccountBackupTracksPartialNotice(int missing, int total) {
    return 'A sua última cópia de segurança não conseguiu transferir $missing de $total ficheiros de trajeto GPS. Todas as corridas estão no arquivo; exporte novamente para recuperar os trajetos. O respetivo manifest.json indica complete: false.';
  }

  @override
  String settingsAccountRestoreIncompleteArchive(int runs) {
    return 'Esse arquivo declarou-se incompleto. Foram restauradas $runs corridas e nada foi substituído — restaure a partir de uma cópia completa para preencher as lacunas.';
  }

  @override
  String get settingsAccountRestoreUnavailable =>
      'Serviço de backup indisponível.';

  @override
  String get settingsAccountRestoreTitle => 'Restaurar do backup?';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'Não está conectado. As corridas serão restauradas neste dispositivo e sincronizadas com a sua conta na próxima vez que entrar.';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'Isto adiciona ou substitui corridas e rotas com IDs correspondentes no backup. Não eliminará corridas ou rotas que não estejam no backup.';

  @override
  String get settingsAccountRestore => 'Restaurar';

  @override
  String get settingsAccountRestoring => 'A restaurar…';

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
  String get settingsAccountAvatar => 'Fotografia de perfil';

  @override
  String get settingsAccountAvatarHint => 'JPEG, PNG ou WebP, até 2 MB.';

  @override
  String get settingsAccountAvatarRemove => 'Remover fotografia';

  @override
  String get settingsAccountAvatarRemoveTitle =>
      'Remover fotografia de perfil?';

  @override
  String get settingsAccountAvatarRemoveConfirm =>
      'Isto remove a sua fotografia de perfil atual. Pode carregar uma nova a qualquer momento.';

  @override
  String get settingsAccountAvatarSaved => 'Fotografia de perfil atualizada.';

  @override
  String get settingsAccountAvatarRemoved => 'Fotografia de perfil removida.';

  @override
  String get settingsAccountAvatarUnsupported =>
      'Imagem não suportada — escolha JPEG, PNG ou WebP.';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return 'Não foi possível atualizar a fotografia: $error';
  }

  @override
  String get guidedRunsTitle => 'Corridas guiadas';

  @override
  String get guidedRunsSubtitle =>
      'Treinos roteirizados com voz de treinador e avisos por TTS';

  @override
  String get privacyZonesTitle => 'Zonas de privacidade';

  @override
  String get privacyZonesSubtitle =>
      'Corta o início/fim de trajetos públicos perto de casa';

  @override
  String get settingsAccountSendErrorReports => 'Enviar relatórios de erro';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Dados anonimizados de falhas e erros para o Sentry (EUA). Desative para retirar o consentimento. Aplica-se na próxima inicialização.';

  @override
  String get settingsAccountDisplayName => 'Nome de exibição';

  @override
  String get settingsAccountDisplayNameHint =>
      'O nome que outros corredores veem. Deixe em branco para utilizar \"Runner\".';

  @override
  String get settingsAccountDisplayNameUnset =>
      'Não definido — aparece como \"Runner\"';

  @override
  String get settingsAccountDisplayNameUpdated => 'Nome de exibição atualizado';

  @override
  String get settingsAccountDisplayNameUpdateFailed =>
      'Falha ao atualizar o nome de exibição. Tente novamente.';

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
  String get settingsAccountAccountExport => 'Exportação da conta';

  @override
  String get settingsAccountAccountExportSubtitle =>
      'Tudo o que há na sua conta — corridas, rotas, mensagens, pedidos, integrações, contactos de emergência. Criada no nosso servidor; pode fechar a app entretanto.';

  @override
  String get settingsAccountExportQueued =>
      'A sua exportação está a ser criada. Pode fechar a app — volte aqui para a transferir.';

  @override
  String get settingsAccountExportBuildingNotice =>
      'A exportação da sua conta está a ser criada. Pode fechar a app; ela continua sem si.';

  @override
  String get settingsAccountExportReadyNotice =>
      'A exportação da sua conta está pronta.';

  @override
  String get settingsAccountExportDownload => 'Transferir e partilhar';

  @override
  String settingsAccountExportFailedNotice(String error) {
    return 'A sua última exportação da conta falhou ($error). Nada foi apagado — peça outra.';
  }

  @override
  String get settingsAccountExportStalledNotice =>
      'A sua última exportação da conta deixou de responder. Nada foi apagado — peça outra.';

  @override
  String get settingsAccountExportExpiredNotice =>
      'A sua última exportação da conta expirou. As exportações são apagadas ao fim de 7 dias — peça outra.';

  @override
  String get settingsAccountExportStatusUnavailable =>
      'Não é possível contactar o serviço de exportação para verificar o estado. Pode ainda estar a ser criada.';

  @override
  String get settingsAccountExportUnavailable =>
      'O serviço de exportação da conta não está configurado nesta versão. O backup completo abaixo é criado neste dispositivo e não inclui os registos da sua conta.';

  @override
  String settingsAccountExportUnsyncedWarning(int count) {
    return '$count corridas ainda não foram sincronizadas. A exportação da conta é criada no servidor, por isso não as inclui — use o backup completo para as guardar.';
  }

  @override
  String get settingsAccountBackupOnDeviceNotice =>
      'O seu último backup completo foi criado neste dispositivo. Contém as suas corridas, rotas, perfil, preferências e registos de ginásio e alimentação — mas não os registos da sua conta. Use a exportação da conta para a cópia completa.';

  @override
  String settingsAccountExportRateLimited(int seconds) {
    return 'Limite de exportações atingido — tente novamente dentro de $seconds segundos.';
  }

  @override
  String settingsAccountExportRequestFailed(String error) {
    return 'Não foi possível pedir a sua exportação: $error';
  }

  @override
  String settingsAccountExportDownloadFailed(String error) {
    return 'Não foi possível transferir a sua exportação: $error';
  }

  @override
  String settingsAccountExportReadyBanner(int count) {
    return 'A exportação da sua conta está pronta — $count corridas.';
  }

  @override
  String get settingsAccountFullBackup => 'Backup completo';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'Cada corrida com o seu trajeto GPS, além de rotas, perfil e preferências. Restaura na web ou no Android.';

  @override
  String get settingsAccountExportCsv => 'Exportar corridas como CSV';

  @override
  String get settingsAccountExportCsvSubtitle =>
      'Data, distância, duração, ritmo, origem — uma linha por corrida. Mesmo formato da exportação LGPD/GDPR da web.';

  @override
  String get settingsAccountRestoreTile => 'Restaurar do backup';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      'Escolha um backup .zip guardado anteriormente.';

  @override
  String get settingsAccountDeleteAccount => 'Eliminar conta';

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
  String integrationsSyncPartial(int imported, int skipped) {
    return 'A sincronização parou antes do fim. $imported novas, $skipped já presentes — algumas atividades não foram transferidas. Sincronize novamente para concluir.';
  }

  @override
  String integrationsSyncPartialRateLimited(int imported, int skipped) {
    return 'O Strava está a limitar os pedidos, pelo que a sincronização parou antes do fim. $imported novas, $skipped já presentes. Tente novamente dentro de cerca de 15 minutos.';
  }

  @override
  String integrationsSyncResultWithFailed(
    int imported,
    int skipped,
    int failed,
  ) {
    return 'Sincronizado. $imported novas, $skipped já presentes, $failed com falha.';
  }

  @override
  String integrationsStravaConnectedPartial(int imported, int skipped) {
    return 'Strava conectado, mas a primeira importação parou antes do fim. $imported importadas, $skipped já presentes — sincronize novamente para concluir.';
  }

  @override
  String integrationsStravaConnectedPartialRateLimited(
    int imported,
    int skipped,
  ) {
    return 'Strava conectado, mas o Strava está a limitar os pedidos, pelo que a primeira importação parou antes do fim. $imported importadas, $skipped já presentes. Sincronize novamente dentro de cerca de 15 minutos.';
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
      'Introduza o seu número de atleta do parkrun (ex.: A123456). Procuraremos o seu histórico de chegadas e adicionaremos os novos resultados à sua lista de corridas.';

  @override
  String get integrationsParkrunFieldLabel => 'Número de atleta';

  @override
  String get integrationsImport => 'Importar';

  @override
  String get integrationsParkrunImporting =>
      'A importar resultados do parkrun…';

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
  String integrationsImportPartialOf(int n, int total) {
    return 'Só foi possível importar parte do seu histórico: $n de $total.';
  }

  @override
  String integrationsImportPartial(int n) {
    return 'Não foi possível ler todos os resultados. Importados: $n.';
  }

  @override
  String get integrationsImportTruncated =>
      'A lista de resultados era demasiado longa para ser lida até ao fim, por isso não foi possível confirmar o seu resultado. Introduza-o manualmente.';

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
  String get integrationsStravaSyncHistory =>
      'Sincronizar histórico mais antigo…';

  @override
  String get integrationsStravaLookbackTitle => 'Até quando sincronizar';

  @override
  String get integrationsStravaLookback90 => 'Últimos 90 dias';

  @override
  String get integrationsStravaLookback180 => 'Últimos 6 meses';

  @override
  String get integrationsStravaLookback365 => 'Último ano';

  @override
  String get integrationsSyncPartialNoteResumable =>
      'A última sincronização parou antes do fim do período. Sincronizar novamente continua a partir do ponto onde parou.';

  @override
  String get integrationsSyncPartialNote =>
      'A última sincronização parou antes do fim do período e não registou nenhum ponto de retoma. Sincronize novamente para tentar outra vez.';

  @override
  String get integrationsSyncNow => 'Sincronizar agora';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Importar resultados pelo número de atleta';

  @override
  String get integrationsParkrunRegionNote =>
      'O parkrun está presente apenas em alguns países e pode não haver eventos perto de si — ainda assim, pode importar resultados com um número de atleta do parkrun.';

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
  String get integrationsHrChecking => 'A verificar…';

  @override
  String integrationsHrPaired(String name) {
    return 'Pareado: $name';
  }

  @override
  String get integrationsHrNotPaired =>
      'Nenhuma cinta pareada — toque para procurar';

  @override
  String get integrationsHrForget => 'Esquecer';

  @override
  String get integrationsHrForgetConfirm =>
      'Esquecer este monitor de frequência cardíaca? Terá de o emparelhar novamente para o usar durante uma corrida.';

  @override
  String get integrationsHrScanTitle =>
      'Procurar monitor de frequência cardíaca';

  @override
  String get integrationsHrScanHint =>
      'Ative a sua cinta / faixa peitoral. Geralmente leva de 3 a 8 segundos.';

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
  String get proWelcome => 'Bem-vindo ao Pro! Carregando os seus benefícios…';

  @override
  String get proPurchaseFailed =>
      'A compra falhou. Tente novamente mais tarde.';

  @override
  String get proRestoreNeedsSignIn =>
      'Para restaurar, precisa estar conectado com o RevenueCat configurado. Gira a sua assinatura na página de upgrade da web.';

  @override
  String get proRestored => 'A sua assinatura Pro foi restaurada.';

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
      'Treinador de IA ilimitado + processamento prioritário. Renova automaticamente todo mês até ser cancelado em Definições → Assinaturas.';

  @override
  String get proSubscribeSubtitleWeb =>
      'Abre o portal de assinatura no seu navegador. Renova automaticamente todo mês até ser cancelado.';

  @override
  String get proComingSoonTitle => 'Pro — em breve';

  @override
  String get proComingSoon =>
      'O Pro desbloqueia o Coach de IA — em breve. Ainda pode apoiar o app abaixo.';

  @override
  String get proRegionalNote =>
      'Cobrado em dólares americanos. A disponibilidade depende do seu país e forma de pagamento — algumas regiões não podem ser atendidas pelo nosso processador de pagamentos.';

  @override
  String get proRestorePurchases => 'Restaurar compras';

  @override
  String get proRestorePurchasesSubtitle =>
      'Revincule compras de uma instalação anterior ou de outro dispositivo';

  @override
  String get proManageSubscription => 'Gerir assinatura';

  @override
  String get proManageSubscriptionSubtitle =>
      'Cancelar, mudar de plano ou atualizar a forma de pagamento';

  @override
  String get proSupport => 'Apoiar o app';

  @override
  String get proSupportSubtitle => 'Doação única no seu navegador';

  @override
  String get aboutTitle => 'Sobre e atualizações';

  @override
  String get aboutVersion => 'Versão';

  @override
  String get licensesOpenSource => 'Licenças de código aberto';

  @override
  String get licensesOpenSourceSubtitle =>
      'Pacotes de terceiros incluídos neste app';

  @override
  String get aboutCheckForUpdates => 'Procurar atualizações';

  @override
  String get aboutCheckingUpdate => 'A procurar atualizações…';

  @override
  String get aboutUpdateAvailable => 'Atualização disponível';

  @override
  String get aboutUpdateAvailableSubtitle =>
      'Está disponível uma versão mais recente para instalar.';

  @override
  String get aboutUpdate => 'Atualizar';

  @override
  String get aboutUpToDate => 'Tem a versão mais recente';

  @override
  String get aboutUpdateUnavailable =>
      'Esta versão é atualizada através da loja onde a instalou.';

  @override
  String get aboutUpdateFailed =>
      'Não foi possível iniciar a atualização. Tente novamente na Play Store.';

  @override
  String get legalPrivacy => 'Política de Privacidade';

  @override
  String get legalTerms => 'Termos de Serviço';

  @override
  String get legalCookieNotice => 'Aviso de cookies';

  @override
  String get legalHealthDataNotice => 'Privacidade dos dados de saúde';

  @override
  String get mapAttributionSemantics => 'Atribuição dos dados do mapa';

  @override
  String mapAttributionProvider(String name) {
    return '© $name';
  }

  @override
  String mapAttributionOsmContributors(String name) {
    return '© colaboradores do $name';
  }

  @override
  String legalCouldNotOpen(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String get aboutLegalSection => 'Informação legal';

  @override
  String get devicesTitle => 'Dispositivos conectados';

  @override
  String get devicesRenameTitle => 'Renomear dispositivo';

  @override
  String get devicesCancel => 'Cancelar';

  @override
  String get devicesSave => 'Guardar';

  @override
  String devicesRenameFailed(Object error) {
    return 'Falha ao renomear: $error';
  }

  @override
  String get devicesRemoveTitle => 'Remover dispositivo?';

  @override
  String get devicesRemoveBodyCurrent =>
      'Este é o dispositivo que está a utilizar. Removê-lo apaga as substituições de preferências por dispositivo; o dispositivo continua conectado.';

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
    return 'Falha ao guardar: $error';
  }

  @override
  String get devicesLoadError => 'Não foi possível carregar os dispositivos.';

  @override
  String get devicesEmpty =>
      'Ainda não há dispositivos — eles são registados na primeira vez que um dispositivo abre o app conectado.';

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
      'Essas chaves substituem as definições universais apenas neste dispositivo.';

  @override
  String get devicesNoOverrides => 'Nenhuma substituição neste dispositivo.';

  @override
  String get devicesAddOverride => 'Adicionar substituição';

  @override
  String get devicesPickKey => 'Escolher uma chave';

  @override
  String get devicesEnterWholeNumber => 'Introduza um número inteiro.';

  @override
  String get devicesEnterNumber => 'Introduza um número (ex.: 0,8).';

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
      'Unidade de distância para todos os ecrãs.';

  @override
  String get devicesKeyDefaultActivityLabel => 'Atividade predefinida';

  @override
  String get devicesKeyDefaultActivityHint =>
      'Atividade pré-selecionada no ecrã inicial.';

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
  String get devicesKeyKeepScreenOnLabel => 'Manter o ecrã ligado';

  @override
  String get devicesKeyKeepScreenOnHint =>
      'Desativa o escurecimento automático do SO durante a gravação.';

  @override
  String get gearTitle => 'Equipamento';

  @override
  String get gearAddGear => 'Adicionar equipamento';

  @override
  String get gearDeleteTitle => 'Eliminar equipamento?';

  @override
  String gearDeleteBody(String name) {
    return 'Eliminar \"$name\"? O histórico de quilometragem das corridas anteriores será perdido. Aposente em vez disto para manter os registos.';
  }

  @override
  String get gearCancel => 'Cancelar';

  @override
  String get gearDelete => 'Eliminar';

  @override
  String get gearDeletedOffline =>
      'Eliminado localmente — será sincronizado quando reconectar.';

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
  String get gearOfflineCached => 'Off-line — mostrando equipamento em cache.';

  @override
  String get gearShoes => 'Ténis';

  @override
  String get gearBikes => 'Bicicletas';

  @override
  String get gearRetired => 'APOSENTADO';

  @override
  String get gearEmptyShoes => 'Ainda não há ténis';

  @override
  String get gearEmptyBikes => 'Ainda não há bicicletas';

  @override
  String get gearEmptySubtitle =>
      'Adicione um par para acompanhar a quilometragem e receber lembretes de reforma.';

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
      'Agrupe os equipamentos que reveza — um conjunto de \"Treino diário\", um conjunto de \"Dia de prova\". Um rodízio é apenas um agrupamento nomeado; ele não muda qual par marca automaticamente as novas corridas.';

  @override
  String get gearRotationsEmpty =>
      'Nenhum rodízio ainda. Crie um para agrupar um conjunto de ténis ou bicicletas.';

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
  String get gearRotationDeleteTitle => 'Eliminar rodízio?';

  @override
  String gearRotationDeleteBody(String name) {
    return 'Eliminar o rodízio \"$name\"? O seu equipamento não é afetado — apenas o agrupamento é removido.';
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
      'Adicione equipamentos primeiro, depois poderá agrupá-los num rodízio.';

  @override
  String gearRotationSaveFailed(Object error) {
    return 'Não foi possível guardar o rodízio: $error';
  }

  @override
  String get gearRotationDone => 'Concluído';

  @override
  String gearRotationNextUp(String name) {
    return 'Próximo: $name';
  }

  @override
  String get gearRotationNextUpWhy => 'O menos desgastado deste rodízio.';

  @override
  String get gearRotationMakeCurrent => 'Definir como atual';

  @override
  String gearRotationMakeCurrentLabel(String name) {
    return 'Definir $name como o par atual — as novas corridas serão marcadas automaticamente com ele';
  }

  @override
  String get gearRotationNextUpIsCurrent => 'Já é o par atual.';

  @override
  String get gearRotationAllWorn =>
      'Todos os pares aqui atingiram ou ultrapassaram a meta de substituição.';

  @override
  String gearRotationMakeCurrentFailed(Object error) {
    return 'Não foi possível alterar o par atual: $error';
  }

  @override
  String get privacyZonesSaved => 'Zonas de privacidade guardadas.';

  @override
  String privacyZonesSaveFailed(Object error) {
    return 'Falha ao guardar: $error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return 'Localização indisponível: $error';
  }

  @override
  String get privacyZonesSave => 'Guardar';

  @override
  String get privacyZonesLocateMe => 'Localizar-me';

  @override
  String get privacyZonesHint =>
      'Toque no mapa para adicionar uma zona. Trajetos em superfícies públicas têm o início e o fim cortados além do raio da zona.';

  @override
  String get privacyZonesSearchHint => 'Procurar lugares…';

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
      other: '$count zonas — toque num marcador para remover.',
      one: '$count zona — toque num marcador para remover.',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'Limpar tudo';

  @override
  String get privacyZonesRemoveTitle => 'Remover zona de privacidade?';

  @override
  String get privacyZonesRemoveBody =>
      'Esta zona oculta os seus trajetos por perto nos partilhas públicos. Removê-la reexpõe esta área.';

  @override
  String get privacyZonesRemoveSemantics => 'Remover zona de privacidade';

  @override
  String get privacyZonesClearAllTitle =>
      'Limpar todas as zonas de privacidade?';

  @override
  String get privacyZonesClearAllBody =>
      'Isto remove todas as zonas, reexpondo todas essas áreas nos partilhas públicos.';

  @override
  String get privacyZonesDiscardBody =>
      'Tem zonas de privacidade não guardadas. Sair sem guardar?';

  @override
  String get discardChangesTitle => 'Descartar alterações?';

  @override
  String get discardChangesBody =>
      'Tem alterações não guardadas. Sair sem guardar?';

  @override
  String get discardChangesCancel => 'Cancelar';

  @override
  String get discardChangesDiscard => 'Descartar';

  @override
  String get prefsTitle => 'Preferências';

  @override
  String get prefsUnitMetric => 'km, m';

  @override
  String get prefsUnitImperial => 'mi, ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · sincronizado com os seus outros dispositivos';
  }

  @override
  String get prefsClear => 'Limpar';

  @override
  String get prefsCancel => 'Cancelar';

  @override
  String get prefsSave => 'Guardar';

  @override
  String get prefsSplitInterval => 'Intervalo de parciais';

  @override
  String get prefsSplitIntervalDefault => 'Predefinição';

  @override
  String prefsSplitIntervalDefaultSubtitle(String run, String cycle) {
    return 'Predefinição ($run ao correr, $cycle ao pedalar)';
  }

  @override
  String get prefsSplitPaceMode => 'Anúncio de parciais';

  @override
  String get prefsSplitPaceModeSubtitle => 'Que ritmo cada parcial anuncia';

  @override
  String get prefsSplitPaceModeSplit => 'Ritmo do parcial';

  @override
  String get prefsSplitPaceModeAverage => 'Ritmo médio';

  @override
  String get prefsSplitPaceModeBoth => 'Ambos';

  @override
  String get prefsSplitPaceModeInfo =>
      'Em cada parcial, escolha que ritmo ouve: o ritmo só desse parcial, o seu ritmo médio da corrida toda até agora, ou ambos. Útil para manter um esforço constante. Exemplo: “1 quilómetro. Ritmo médio, 5 minutos e 45 segundos por quilómetro.”';

  @override
  String get prefsTargetPace => 'Ritmo alvo';

  @override
  String get prefsTargetPaceInfo =>
      'O ritmo que quer manter. Sozinho, ele fica em silêncio — ative o aviso de voz “Alertas de desvio de ritmo” para ouvir “acelere” ou “diminua” quando se desviar mais de 30 segundos. Exemplo: “Acelere 8 segundos.”';

  @override
  String get prefsCueInfoTooltip => 'O que é isto?';

  @override
  String get prefsLivePaceAlert => 'Ritmo alvo';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 's';

  @override
  String get prefsLivePaceAlertOff =>
      'Não definido — defina um alvo e ative os alertas de desvio de ritmo';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — os alertas de desvio de ritmo falam ao desviar 30 s ou mais';
  }

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
  String get prefsDefaultRunVisibility =>
      'Visibilidade predefinida das corridas';

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
      'Inscreva-se para receber um resumo semanal do seu treino e dos destaques da comunidade. Desativado por predefinição; separado dos seus e-mails de notificação.';

  @override
  String get prefsEmailLifecycleDrip => 'E-mail de dicas e incentivo';

  @override
  String get prefsEmailLifecycleDripHint =>
      'Inscreva-se para receber lembretes ocasionais de integração, reengajamento e sequência. Desativado por predefinição; separado do seu resumo semanal e dos seus e-mails de notificação.';

  @override
  String get prefsEmailReOptInFailed =>
      'Não foi possível anular o seu cancelamento anterior. Os e-mails podem continuar bloqueados; tente novamente.';

  @override
  String get prefsWeekStart => 'A semana começa em';

  @override
  String get prefsWeekStartMonday => 'Segunda-feira';

  @override
  String get prefsWeekStartSunday => 'Domingo';

  @override
  String get prefsDefaultActivity => 'Atividade predefinida';

  @override
  String get prefsDateOfBirth => 'Data de nascimento';

  @override
  String get prefsRestingHr => 'Frequência cardíaca em repouso';

  @override
  String get prefsMaxHr => 'Frequência cardíaca máxima';

  @override
  String get prefsMaxHrNotSet => 'Não definido — utiliza 208 − 0,7 × idade';

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
  String get prefsSectionPrivacySharing => 'Privacidade e partilha';

  @override
  String get prefsSectionAiCoach => 'Treinador de IA';

  @override
  String get prefsSignInToEdit =>
      'Entre para editar definições de perfil que sincronizam entre dispositivos.';

  @override
  String get prefsUseMiles => 'Utilizar milhas';

  @override
  String get prefsDarkMode => 'Modo escuro';

  @override
  String get prefsAudioCues => 'Avisos de áudio';

  @override
  String get prefsAudioCuesSubtitle =>
      'Anuncia parciais, ritmo e outros avisos enquanto corre';

  @override
  String get prefsMinimalVoiceCues => 'Avisos de voz mínimos';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Pula os avisos tagarelas de meio de repetição e desvio de ritmo';

  @override
  String get prefsKeepScreenOn => 'Manter o ecrã ligado';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Mantém o ecrã ligado durante toda a corrida. Consome bem mais bateria em treinos longos.';

  @override
  String get prefsDimScreenWhileRecording => 'Escurecer o ecrã ao gravar';

  @override
  String get prefsDimScreenWhileRecordingSubtitle =>
      'Escurece o mapa durante a corrida para poupar bateria. As estatísticas continuam legíveis.';

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
  String get prefsShowCalories => 'Mostrar estimativas de calorias';

  @override
  String get prefsShowCaloriesHint =>
      'Estimadas a partir da distância e do peso corporal (predefinição de 70 kg quando não definido). Desative para ocultar as calorias nas páginas de corrida.';

  @override
  String get prefsDefaultRunPrivacy => 'Privacidade predefinida das corridas';

  @override
  String get prefsStravaAutoShare => 'Partilha automático no Strava';

  @override
  String get prefsStravaAutoShareSubtitle =>
      'Envia automaticamente cada nova corrida para o Strava. Requer uma integração do Strava conectada quando estiver disponível.';

  @override
  String get prefsDiscoverable => 'Aparecer na pesquisa por nome';

  @override
  String get prefsDiscoverableSubtitle =>
      'Quando desativado, a sua conta não aparece quando outros corredores procuram pelo nome de exibição. As suas corridas públicas e o seu perfil continuam acessíveis para qualquer pessoa com o URL.';

  @override
  String get dashboardCoachTooltip => 'Treinador';

  @override
  String get dashboardFeedTooltip => 'Feed de atividades';

  @override
  String get dashboardRecapTooltip => 'Ano em corrida';

  @override
  String get dashboardProfileTooltip => 'O seu perfil';

  @override
  String get dashboardWelcomeTitle => 'Bem-vindo!';

  @override
  String get dashboardWelcomeBody =>
      'O seu painel é preenchido assim que regista uma corrida, define uma meta ou importa o seu histórico.';

  @override
  String get dashboardStartRun => 'Iniciar uma corrida';

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
    return 'Mais depressa em $distance';
  }

  @override
  String dashboardPbAgeGrade(String percent) {
    return '$percent classificação por idade';
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
  String get dashboardSetFirstGoal => 'Defina a sua primeira meta';

  @override
  String get dashboardSetFirstGoalBody =>
      'Acompanhe distância, tempo, ritmo ou número de corridas por semana ou mês.';

  @override
  String get dashboardGoalTapToEdit => 'toque para editar';

  @override
  String get dashboardGoalComplete => 'Concluída.';

  @override
  String get dashboardGoalInProgress => 'Em curso.';

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
  String get dashboardHeatmapTitle => 'Atividade';

  @override
  String get dashboardHeatmapLess => 'Menos';

  @override
  String get dashboardHeatmapMore => 'Mais';

  @override
  String get dashboardHeatmapTapHint => 'Toque numa semana para ver o resumo';

  @override
  String get periodWeeklySummary => 'Resumo semanal';

  @override
  String get periodMonthlySummary => 'Resumo mensal';

  @override
  String get periodAllTimeSummary => 'Resumo geral';

  @override
  String get periodShareTooltip => 'Partilhar';

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
  String get periodShareSummary => 'Partilhar resumo';

  @override
  String get periodShareText => 'Texto';

  @override
  String get periodShareImage => 'Imagem';

  @override
  String get periodShareImageFailed =>
      'Não foi possível criar a imagem de partilha';

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
      'Baseado em volume — defina FC de repouso e máxima nas preferências e registe com uma cinta para mudar para TRIMP.';

  @override
  String get trainingLoadEmpty =>
      'Registe algumas corridas para ver a sua tendência de forma.';

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
      'Equilibrado — dia leve ou dia difícil, decide.';

  @override
  String get trainingLoadIncludesLifts =>
      'Inclui sessões de ginásio — musculação também soma fadiga.';

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
  String get mileageTitle => 'Quilometragem';

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
      'O seu motor aeróbico: quanto oxigénio o seu corpo consegue utilizar por minuto. Quanto maior, melhor a forma.';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'A pontuação de forma de Daniels com base no seu melhor esforço recente. Define os seus ritmos de treino.';

  @override
  String get fitnessStatRuns => 'Corridas';

  @override
  String get fitnessStatRunsTooltip =>
      'Corridas recentes longas o suficiente para contar na sua estimativa de forma.';

  @override
  String get fitnessStatCtl => 'Forma (CTL)';

  @override
  String get fitnessStatCtlTooltip =>
      'A sua carga de treino móvel de 42 dias. Cresce devagar; é a sua base de resistência.';

  @override
  String get fitnessStatAtl => 'Fadiga (ATL)';

  @override
  String get fitnessStatAtlTooltip =>
      'A sua carga dos últimos 7 dias. Sobe rápido após sessões difíceis e cai com o descanso.';

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
  String get runSocialDelete => 'Eliminar';

  @override
  String get runSocialReportComment => 'Denunciar comentário';

  @override
  String get runSocialReportReply => 'Denunciar resposta';

  @override
  String get runSocialPost => 'Publicar';

  @override
  String get runSocialCancel => 'Cancelar';

  @override
  String get kudosGiveLabel => 'Dar kudos';

  @override
  String get kudosRemoveLabel => 'Remover kudos';

  @override
  String get kudosViewCommentsLabel => 'Ver comentários';

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
    return 'Falha ao eliminar: $error';
  }

  @override
  String get runPhotosLoading => 'A carregar fotografias…';

  @override
  String get runPhotosTitle => 'Fotografias';

  @override
  String get runPhotosAdd => 'Adicionar fotografia';

  @override
  String get runPhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get runPhotosCaptionHint => 'Legenda…';

  @override
  String get runPhotosCancel => 'Cancelar';

  @override
  String get runPhotosSave => 'Guardar';

  @override
  String get runPhotosUpload => 'Enviar';

  @override
  String get runPhotosUploading => 'A enviar…';

  @override
  String get runPhotosEditCaption => 'Editar legenda';

  @override
  String get runPhotosDeleteTooltip => 'Eliminar fotografia';

  @override
  String get runPhotosDeleteTitle => 'Eliminar fotografia?';

  @override
  String get runPhotosDeleteBody =>
      'Isto remove a fotografia da corrida permanentemente.';

  @override
  String get runPhotosDeleteConfirm => 'Eliminar';

  @override
  String get runPhotosPermissionDenied =>
      'É necessário acesso às fotografias para adicionar uma fotografia. Pode permitir nas Definições.';

  @override
  String get runPhotosOpenSettings => 'Abrir definições';

  @override
  String get runPhotosPickerFailed =>
      'Não foi possível abrir o seletor de fotografias. Tente novamente.';

  @override
  String runPhotosUploadError(String error) {
    return 'Falha no envio: $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return 'Falha ao eliminar: $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get routePhotosLoading => 'A carregar fotografias…';

  @override
  String get routePhotosTitle => 'Fotografias';

  @override
  String get routePhotosAdd => 'Adicionar fotografia';

  @override
  String get routePhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get routePhotosCaptionHint => 'Legenda…';

  @override
  String get routePhotosCancel => 'Cancelar';

  @override
  String get routePhotosSave => 'Guardar';

  @override
  String get routePhotosUpload => 'Enviar';

  @override
  String get routePhotosUploading => 'A enviar…';

  @override
  String get routePhotosEditCaption => 'Editar legenda';

  @override
  String get routePhotosDeleteTooltip => 'Eliminar fotografia';

  @override
  String get routePhotosDeleteTitle => 'Eliminar fotografia?';

  @override
  String get routePhotosDeleteBody =>
      'Isto remove a fotografia do percurso permanentemente.';

  @override
  String get routePhotosDeleteConfirm => 'Eliminar';

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
    return 'Falha ao eliminar: $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get clubPhotosLoading => 'A carregar fotografias…';

  @override
  String get clubPhotosTitle => 'Fotografias';

  @override
  String get clubPhotosAdd => 'Adicionar fotografia';

  @override
  String get clubPhotosEmpty => 'Ainda não há fotografias neste clube.';

  @override
  String get clubPhotosCaptionPendingHint =>
      'Legenda (opcional, 280 caracteres)';

  @override
  String get clubPhotosCaptionHint => 'Legenda…';

  @override
  String get clubPhotosCancel => 'Cancelar';

  @override
  String get clubPhotosSave => 'Guardar';

  @override
  String get clubPhotosUpload => 'Enviar';

  @override
  String get clubPhotosUploading => 'A enviar…';

  @override
  String get clubPhotosEditCaption => 'Editar legenda';

  @override
  String get clubPhotosDeleteTooltip => 'Eliminar fotografia';

  @override
  String get clubPhotosDeleteTitle => 'Eliminar fotografia?';

  @override
  String get clubPhotosDeleteBody =>
      'Isto remove a fotografia do clube permanentemente.';

  @override
  String get clubPhotosDeleteConfirm => 'Eliminar';

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
    return 'Falha ao eliminar: $error';
  }

  @override
  String clubPhotosCaptionError(String error) {
    return 'Não foi possível atualizar a legenda: $error';
  }

  @override
  String get runSegEffortsRankUnknown => 'Classificação indisponível';

  @override
  String get runSegEffortsChecking => 'A verificar segmentos…';

  @override
  String get runSegEffortsNoRoute =>
      'Os segmentos são associados por rota — vincule esta corrida a uma rota guardada para competir nos rankings dela.';

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
  String get workoutReviewSkip => 'saltar';

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
  String get workoutReviewAdherenceCompleted => 'Concluído';

  @override
  String get workoutReviewAdherencePartial => 'Parcial';

  @override
  String get workoutReviewAdherenceAbandoned => 'Abandonado';

  @override
  String get segmentsPanelTitle => 'Segmentos';

  @override
  String get segmentsPanelNew => 'Novo segmento';

  @override
  String get segmentsPanelCancel => 'Cancelar';

  @override
  String get segmentsPanelLoading => 'A carregar segmentos…';

  @override
  String get segmentsPanelEmpty => 'Ainda não há segmentos nesta rota.';

  @override
  String get segmentsPanelLoadError => 'Não foi possível carregar os segmentos';

  @override
  String get segmentsPanelLeaderboardError =>
      'Não foi possível carregar o ranking';

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
  String get segmentsPanelDeleteTooltip => 'Eliminar segmento';

  @override
  String get segmentsPanelDeleteTitle => 'Eliminar segmento?';

  @override
  String segmentsPanelDeleteBody(String name) {
    return '“$name” será removido.';
  }

  @override
  String get segmentsPanelDeleteConfirm => 'Eliminar';

  @override
  String get segmentsPanelErrEndAfterStart =>
      'O fim deve ser maior que o início';

  @override
  String get segmentsPanelErrMinLength =>
      'O segmento deve ter pelo menos 100 m';

  @override
  String get segmentsPanelErrNameRequired => 'Insira um nome de segmento';

  @override
  String segmentsPanelCreateError(String error) {
    return 'Não foi possível criar o segmento: $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return 'Falha ao eliminar: $error';
  }

  @override
  String get segmentsPanelAllGenders => 'Todos os géneros';

  @override
  String get segmentsPanelGenderMen => 'Homens';

  @override
  String get segmentsPanelGenderWomen => 'Mulheres';

  @override
  String get segmentsPanelAllAges => 'Todas as idades';

  @override
  String get segmentsPanelResetFilters => 'Redefinir';

  @override
  String get segmentsPanelLeaderboardLoading => 'A carregar…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'Nenhum esforço corresponde a este filtro — tente ampliá-lo.';

  @override
  String get segmentsPanelLeaderboardEmpty =>
      'Ainda não há esforços — seja o primeiro a correr este segmento.';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'Detém esta coroa — $label.';
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
  String get goalEditorNameHint => 'ex. Base de quilómetros';

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
  String get goalEditorDelete => 'Eliminar';

  @override
  String get goalEditorDeleteTitle => 'Eliminar esta meta?';

  @override
  String get goalEditorDeleteMessage =>
      'Esta meta e o acompanhamento de progresso serão removidos. Pode criar uma nova quando quiser.';

  @override
  String get goalEditorCancel => 'Cancelar';

  @override
  String get goalEditorSave => 'Guardar';

  @override
  String goalEditorSaveFailed(String error) {
    return 'Não foi possível guardar a meta: $error';
  }

  @override
  String get goalEditorErrDistance => 'Distância: insira um número positivo';

  @override
  String get goalEditorErrTime => 'Tempo: insira um número positivo de minutos';

  @override
  String get goalEditorErrPace => 'Ritmo: utilize mm:ss (ex. 5:00)';

  @override
  String get goalEditorErrRuns => 'Corridas: insira um número inteiro positivo';

  @override
  String get goalEditorErrNoTarget => 'Defina pelo menos uma meta';

  @override
  String get goalEditorSavedAnnounce => 'Meta guardada';

  @override
  String get goalEditorDeletedAnnounce => 'Meta eliminada';

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
  String get eventFormMeetHint => 'Estacionamento do início do trilho';

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
  String get eventEditorMembersOnlyToggle => 'Apenas para membros';

  @override
  String get eventEditorMembersOnlyHint =>
      'Apenas membros do clube podem ver este evento, e ele não aparecerá na pesquisa pública.';

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
  String get clubFormErrName => 'Dê um nome ao clube.';

  @override
  String get clubFormErrSlug =>
      'O nome precisa de pelo menos uma letra ou dígito.';

  @override
  String get eventFormErrTitle => 'Dê um título ao evento.';

  @override
  String get clubFormErrUnreachable =>
      'Não é possível aceder ao servidor agora. Verifique a sua ligação ou entre na conta e tente novamente.';

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
  String get reportTitleUser => 'Denunciar utilizador';

  @override
  String get reportTitleClub => 'Denunciar clube';

  @override
  String get reportTitleRoute => 'Denunciar rota';

  @override
  String get reportTitleComment => 'Denunciar comentário';

  @override
  String get reportTitlePost => 'Denunciar publicação';

  @override
  String get reportTitleRun => 'Denunciar corrida';

  @override
  String get reportTitleReview => 'Denunciar avaliação';

  @override
  String get reportTitleContent => 'Denunciar conteúdo';

  @override
  String get reportDisclaimer =>
      'A sua denúncia vai para um moderador. Denúncias falsas também são analisadas — sinalize apenas conteúdo que viole nossas diretrizes da comunidade.';

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
      'Já tem uma denúncia pendente sobre este conteúdo.';

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
    return 'Encontramos $_temp0 após a compra. Desmarque aquelas em que não os usou.';
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
  String get gearBackfillSkip => 'Saltar';

  @override
  String get gearBackfillAttaching => 'A vincular…';

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
  String get workoutEditSave => 'Guardar';

  @override
  String get workoutEditErrDistance => 'Insira uma distância positiva em km';

  @override
  String get workoutEditErrPace => 'O ritmo deve ter o formato 5:30';

  @override
  String workoutEditSaveError(String error) {
    return 'Falha ao guardar: $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return 'CONFIRMADO · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'A começar agora';

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
  String get shareCardRunTitle => 'Partilhar corrida';

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
      'Não foi possível criar a imagem de partilha';

  @override
  String get shareCardFileError => 'Não foi possível exportar o ficheiro';

  @override
  String get shareCardRouteTitle => 'Partilhar rota';

  @override
  String get shareCardRouteShareImage => 'Partilhar imagem';

  @override
  String get shareCardRouteCapturing => 'A capturar…';

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
      'Atualize o seu cartão ou será rebaixado para o Free.';

  @override
  String get billingManage => 'Gerir';

  @override
  String get planCalendarPrevMonth => 'Mês anterior';

  @override
  String get planCalendarNextMonth => 'Próximo mês';

  @override
  String runGearChipsLoadError(String error) {
    return 'Falha ao carregar equipamento: $error';
  }

  @override
  String get runGearChipsLoadFailed =>
      'Não foi possível carregar o equipamento.';

  @override
  String get runGearChipsPickerTitle =>
      'Marcar o equipamento utilizado nesta corrida';

  @override
  String get runGearChipsEmpty =>
      'Ainda não registou nenhum equipamento. Adicione em Definições → Equipamento.';

  @override
  String get runGearChipsCancel => 'Cancelar';

  @override
  String get runGearChipsSave => 'Guardar';

  @override
  String get runGearChipsTag => '+ Marcar equipamento';

  @override
  String get runGearChipsEdit => 'Editar';

  @override
  String runGearChipsSaveError(String error) {
    return 'Falha ao guardar: $error';
  }

  @override
  String get gearFormTitleEdit => 'Editar equipamento';

  @override
  String get gearFormTitleAddShoes => 'Adicionar ténis';

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
  String get gearFormSaving => 'A guardar…';

  @override
  String get gearFormSave => 'Guardar';

  @override
  String get gearFormAdd => 'Adicionar';

  @override
  String gearFormSaveError(String error) {
    return 'Falha ao guardar: $error';
  }

  @override
  String get gearWearLogHeading => 'Registo de desgaste';

  @override
  String get gearWearLogHint =>
      'Anote como este equipamento está a envelhecer — desgaste do solado, entressola morta, cabedal puído.';

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
  String get gearWearLogAdding => 'A adicionar…';

  @override
  String get gearWearLogDelete => 'Eliminar observação';

  @override
  String gearWearLogAddError(String error) {
    return 'Não foi possível adicionar a observação: $error';
  }

  @override
  String gearWearLogDeleteError(String error) {
    return 'Não foi possível eliminar a observação: $error';
  }

  @override
  String get notificationBellTooltip => 'Notificações';

  @override
  String get liveRunMapWaitingGps => 'A aguardar GPS...';

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
  String get ttsPaceAlertSlow => 'Abrande o ritmo';

  @override
  String get ttsWorkoutComplete => 'Treino concluído. Bom trabalho.';

  @override
  String get ttsStepHalfway => 'Metade desta repetição';

  @override
  String get ttsStepLastFifty => 'Faltam cinquenta metros';

  @override
  String ttsPaceDriftAhead(int delta) {
    return 'Alivie um pouco — $delta segundos demasiado depressa.';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return 'Acelere um pouco — $delta segundos demasiado devagar.';
  }

  @override
  String ttsSpeedKm(String value) {
    return 'Velocidade, $value quilómetros por hora';
  }

  @override
  String ttsSpeedMi(String value) {
    return 'Velocidade, $value milhas por hora';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por quilómetro';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'Ritmo, $min minutos $sec segundos por milha';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$value quilómetros';
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
  String ttsSplitAverage(String count, String unit, String tail) {
    return '$count $unit. Média $tail';
  }

  @override
  String ttsSplitBoth(String count, String unit, String tail, String avgTail) {
    return '$count $unit. $tail. Média $avgTail';
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
    return '$min minutos $sec segundos por quilómetro';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '$min minutos por quilómetro';
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
      'Metade. Ainda deve conseguir conversar enquanto corre.';

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
      'Novo na corrida? Três séries de um minuto correndo e um minuto caminhando, mais aquecimento e desaquecimento. Uma entrada suave; toda a gente começa aqui.';

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
      'Concluído. Isto foi uma corrida de verdade. Volte a correr em breve.';

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
  String get ttsSplitUnitKilometre => 'quilómetro';

  @override
  String get ttsSplitUnitKilometres => 'quilómetros';

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
  String get planPhaseGraduation => 'Semana de conclusão';

  @override
  String get runBackgroundLocationNudgeTitle =>
      'Permitir localização o tempo todo';

  @override
  String get runBackgroundLocationNudgeBody =>
      'O Android só concedeu a localização enquanto o app está aberto. Para uma distância precisa com o ecrã desligado, defina o acesso à localização como \"Permitir o tempo todo\" nas Definições. Pode começar mesmo assim — a gravação continua a funcionar enquanto o app estiver no ecrã.';

  @override
  String get runBatteryOptHintTitle =>
      'Manter a gravação ativa em segundo plano';

  @override
  String get runBatteryOptHintBody =>
      'Alguns telemóveis (Samsung, Xiaomi, OnePlus e outros) colocam os apps em suspensão para economizar bateria, o que pode interromper a gravação de uma corrida longa quando o ecrã está desligada. Por segurança, elimine este app da otimização de bateria nas Definições. A sua corrida será gravada de qualquer forma — isto apenas impede que o sistema a interrompa.';

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
      'Entre para ver onde está conectado';

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
  String get settingsTabAccountSubtitle =>
      'Login, perfil, importação e backup, eliminar conta';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Unidades, tema, gravação, treino, privacidade';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, calendário de corridas, cinta cardíaca, passadeira, relógio';

  @override
  String get settingsTabDevicesSubtitle =>
      'Onde está conectado e as substituições por dispositivo — pareie cinta ou passadeira em Integrações';

  @override
  String get settingsTabGearSubtitle =>
      'Acompanhe ténis + bikes e a quilometragem por item';

  @override
  String get settingsTabCoachingSubtitle =>
      'Treine atletas ou siga o seu próprio treinador';

  @override
  String get settingsTabProSubtitle =>
      'Assine, restaure compras, gira a cobrança';

  @override
  String get settingsTabAboutSubtitle =>
      'Versão, atualizações e documentos legais';

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
  String get gymTitle => 'Ginásio';

  @override
  String get gymLog => 'Registar treino';

  @override
  String get gymUntitled => 'Treino sem título';

  @override
  String get gymOfflineCached => 'Offline: mostrando treinos guardados';

  @override
  String get gymEmptyTitle => 'Nenhum treino de ginásio ainda';

  @override
  String get gymEmptyBody =>
      'Registe um treino para acompanhá-lo aqui e alimentar a sua carga de treino.';

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
  String get gymDelete => 'Eliminar';

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
  String gymDeleteFailed(Object error) {
    return 'Não foi possível eliminar o treino: $error';
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
  String get gymDistance => 'Distância (m)';

  @override
  String gymDistanceValue(String metres) {
    return '$metres m';
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
      'A sua melhor marca em cada exercício com peso.';

  @override
  String get gymRecordsEmpty =>
      'Ainda não há exercícios com peso registados. Adicione um peso a uma série para começar a acompanhar os seus recordes.';

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
  String get gymDeleteConfirmTitle => 'Eliminar treino?';

  @override
  String get gymDeleteConfirmBody =>
      'Isto remove permanentemente o treino e as suas séries.';

  @override
  String get clubEventMembersOnly => 'Apenas membros';

  @override
  String get clubEventLogAsWorkout => 'Registar como treino';

  @override
  String get clubEventLogAsWorkoutHint =>
      'Adicione esta aula ao seu próprio registo de ginásio — pode ajustar os detalhes antes de guardar.';

  @override
  String get clubEventLogAsWorkoutSaved =>
      'Adicionado ao seu registo de ginásio';

  @override
  String get clubEventAddToCalendar => 'Adicionar ao calendário';

  @override
  String get clubEventAddOccurrenceToCalendar => 'Adicionar esta ocorrência';

  @override
  String get clubEventAddSeriesToCalendar => 'Adicionar toda a série';

  @override
  String get clubEventCalendarUnavailable =>
      'Não foi possível abrir a sua aplicação de calendário.';

  @override
  String clubEventCalendarCancelledNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'O seu calendário não consegue ignorar datas canceladas: $count ocorrências canceladas vão continuar a aparecer.',
      one:
          'O seu calendário não consegue ignorar datas canceladas: 1 ocorrência cancelada vai continuar a aparecer.',
    );
    return '$_temp0';
  }

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
  String get gymEditorShare => 'Partilhar no feed';

  @override
  String get gymEditorCancel => 'Cancelar';

  @override
  String get gymEditorSave => 'Guardar treino';

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
  String gymCatalogueOtherCategory(String name, String category) {
    return '“$name” já está no catálogo, em $category.';
  }

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
  String get gymSaveFailed => 'Não foi possível guardar o treino.';

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
  String get gymRoutinePublishLabel => 'Publicar num clube';

  @override
  String get gymRoutinePublishPick => 'Escolha um clube…';

  @override
  String get gymRoutinePublish => 'Publicar';

  @override
  String get gymRoutinePublishSuccess => 'Rotina publicada no clube.';

  @override
  String get gymRoutinePublishFailed => 'Não foi possível publicar a rotina.';

  @override
  String get gymRoutineHistoryTitle => 'Histórico da rotina';

  @override
  String get gymRoutineHistoryRecent => 'Sessões recentes';

  @override
  String gymRoutineHistoryLastDone(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Feita há $days dias',
      one: 'Feita ontem',
      zero: 'Feita hoje',
    );
    return '$_temp0';
  }

  @override
  String gymRoutineHistoryCompletedRate(int completed, int graded) {
    return '$completed de $graded concluídas';
  }

  @override
  String get gymRoutineHistoryVerdictUngraded => 'Sem avaliação';

  @override
  String get gymRoutineHistoryLoadError =>
      'Não foi possível carregar o histórico desta rotina.';

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
  String get gymRoutineDelete => 'Eliminar';

  @override
  String get gymRoutineDeleteConfirmTitle => 'Eliminar rotina?';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'Isto remove a rotina permanentemente. Os treinos registados não são afetados.';

  @override
  String get gymRoutineDeleted => 'Rotina eliminada';

  @override
  String get gymRoutineCreated => 'Rotina guardada';

  @override
  String get gymRoutineSaveFailed => 'Não foi possível guardar a rotina.';

  @override
  String get gymRoutineEmptyTitle => 'Nenhuma rotina ainda';

  @override
  String get gymRoutineEmptyBody =>
      'Guarde um treino registado como rotina, ou crie uma, para reutilizá-la.';

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
  String get gymRoutineEditorSave => 'Guardar rotina';

  @override
  String get gymRoutineEditorCancel => 'Cancelar';

  @override
  String get gymRoutineEditorNeedTitle => 'Dê um nome à rotina.';

  @override
  String get gymRoutineEditorNeedExercise =>
      'Adicione pelo menos um exercício com nome.';

  @override
  String get gymRoutineSaveAsRoutine => 'Guardar como rotina';

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
  String get gymRoutineNextTargetEstablishBaseline =>
      'Estabelecer base — defina o peso inicial';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — reduzir a carga';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'subida de reps $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrição';

  @override
  String get nutritionDayNavLabel => 'Dia do diário';

  @override
  String get nutritionDayPrevious => 'Dia anterior';

  @override
  String get nutritionDayNext => 'Próximo dia';

  @override
  String get nutritionDayToday => 'Hoje';

  @override
  String get nutritionDayYesterday => 'Ontem';

  @override
  String get nutritionDayBackfillHint =>
      'Tudo o que registar aqui é adicionado a este dia.';

  @override
  String get nutritionDayEmptyPast => 'Nada registado neste dia.';

  @override
  String nutritionDayGoalBreakdown(int base, int exercise) {
    return 'Meta $base + $exercise kcal queimadas nesse dia';
  }

  @override
  String nutritionDayTrendEnding(String date) {
    return '7 dias até $date';
  }

  @override
  String nutritionDayLogHeadingFor(String date) {
    return 'Registar comida — $date';
  }

  @override
  String get nutritionLogFood => 'Registar comida';

  @override
  String get nutritionCalories => 'Calorias';

  @override
  String get nutritionProtein => 'Proteínas';

  @override
  String get nutritionCarbs => 'Carboidratos';

  @override
  String get nutritionFat => 'Gorduras';

  @override
  String get nutritionFiber => 'Fibra';

  @override
  String get nutritionSugar => 'Açúcar';

  @override
  String get nutritionSodium => 'Sódio';

  @override
  String get nutritionSaturatedFat => 'Gorduras saturadas';

  @override
  String get nutritionCholesterol => 'Colesterol';

  @override
  String get nutritionNutrients => 'Nutrientes';

  @override
  String get nutritionNutrientsHint =>
      'Valores de referência. Cada total conta apenas os alimentos registados que indicam esse nutriente.';

  @override
  String get nutritionNutrientAtLeast => 'pelo menos';

  @override
  String nutritionNutrientPartial(int reported, int total, String nutrient) {
    return '$reported de $total alimentos registados indicam $nutrient';
  }

  @override
  String nutritionNutrientOver(String n, String unit) {
    return '$n $unit acima';
  }

  @override
  String nutritionNutrientLeft(String n, String unit) {
    return 'Faltam $n $unit';
  }

  @override
  String get nutritionNutrientReached => 'Objetivo atingido';

  @override
  String get nutritionNutrientUntargeted => 'Sem objetivo diário';

  @override
  String get nutritionWater => 'Água';

  @override
  String get nutritionWaterAdd => 'Adicionar água';

  @override
  String get nutritionWaterRemove => 'Remover água';

  @override
  String get nutritionNoTargets =>
      'Introduza a sua altura, peso, idade e sexo para ver as metas de calorias e macros.';

  @override
  String get nutritionAddBodyMetrics => 'Adicionar dados corporais';

  @override
  String get nutritionTargetsLink => 'Metas';

  @override
  String get nutritionTargetsTitle => 'Metas de calorias e macros';

  @override
  String get nutritionTargetsSubtitle =>
      'Como a meta de hoje é calculada e as duas definições que a determinam.';

  @override
  String get nutritionTargetsTotal => 'Meta de hoje';

  @override
  String get nutritionTargetsBmr => 'Metabolismo em repouso';

  @override
  String get nutritionTargetsBase => 'Meta base';

  @override
  String nutritionTargetsBaseFloored(int n) {
    return 'Mantida no limite mínimo de $n kcal — a menor meta diária que recomendamos.';
  }

  @override
  String get nutritionTargetsExercise => 'Treinos de hoje';

  @override
  String get nutritionTargetsExerciseHint =>
      'As corridas e sessões de musculação que registares hoje são somadas por cima.';

  @override
  String get nutritionTargetsMacrosHeading => 'Macros';

  @override
  String nutritionTargetsProteinHint(String n) {
    return '$n g por kg de peso corporal';
  }

  @override
  String get nutritionTargetsCarbsHint => 'O que sobra — o seu combustível';

  @override
  String nutritionTargetsFatHint(int n) {
    return '$n% das calorias';
  }

  @override
  String get nutritionTargetsDefaultsHeading => 'As suas predefinições';

  @override
  String get nutritionTargetsDefaultsHint =>
      'O nível de atividade é o seu dia típico sem contar os treinos — as corridas e sessões de musculação registadas são somadas à parte. Ambos são guardados quando os altera.';

  @override
  String get nutritionTargetsMetricsHeading => 'Dados corporais';

  @override
  String get nutritionTargetsMetricsHint =>
      'Altura, peso, data de nascimento e sexo são dados de saúde, por isso são editados nas Definições atrás do consentimento.';

  @override
  String get nutritionTargetsEditMetrics => 'Editar nas Definições';

  @override
  String get nutritionTargetsUnset => 'Não indicado';

  @override
  String get nutritionTargetsEmptyTitle => 'Ainda sem metas';

  @override
  String get nutritionTargetsEmptyBody =>
      'Indique a sua altura, peso, data de nascimento e sexo e as suas metas de calorias e macros aparecem aqui.';

  @override
  String get nutritionTargetsAge => 'Idade';

  @override
  String nutritionTargetsAgeYears(int n) {
    return '$n anos';
  }

  @override
  String get nutritionTargetsAgeConsentWithheld =>
      'Requer consentimento de dados de saúde';

  @override
  String get nutritionTargetsLoadError =>
      'Não foi possível carregar as suas metas.';

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
  String nutritionWeekProtein(int met, int total) {
    return 'Proteína $met/$total dias';
  }

  @override
  String get nutritionGoalLine => 'Meta diária';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return 'Meta $base + $exercise kcal queimadas hoje';
  }

  @override
  String get dashGymReadinessIncluded =>
      'As suas sessões recentes de ginásio entram na sua fadiga.';

  @override
  String get dashGymReadinessExcluded =>
      'A carga do ginásio fica de fora do seu preparo para correr.';

  @override
  String get prefsExcludeGymFromReadiness =>
      'Excluir a carga do ginásio da prontidão para correr';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'Por predefinição, as sessões de ginásio aumentam a sua fadiga e reduzem o seu preparo, como uma corrida. Ative isto para que o seu condicionamento, fadiga e forma se baseiem apenas nas corridas.';

  @override
  String get nutritionEmptyTitle => 'Nada registado hoje';

  @override
  String get nutritionEmptyBody =>
      'Registe uma refeição para acompanhar as suas calorias e macros.';

  @override
  String get nutritionSlotBreakfast => 'Pequeno-almoço';

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
  String get nutritionMealNoItems => 'Nada registado para esta refeição.';

  @override
  String get nutritionMealTrendHeading => 'Últimos 7 dias';

  @override
  String get nutritionDelete => 'Eliminar';

  @override
  String nutritionDeleteFailed(String error) {
    return 'Não foi possível eliminar a entrada: $error';
  }

  @override
  String get nutritionOfflineCached => 'Offline — mostrando entradas guardadas';

  @override
  String get nutritionLogTitle => 'Registar comida';

  @override
  String get nutritionSearchHint => 'Procurar um alimento';

  @override
  String get nutritionSearching => 'A procurar…';

  @override
  String get nutritionNoResults =>
      'Sem resultados. Tente outro termo ou insira manualmente abaixo.';

  @override
  String get nutritionSearchFailed =>
      'A pesquisa falhou. Verifique a sua ligação e tente novamente ou insira manualmente abaixo.';

  @override
  String get nutritionSearchRetry => 'Tentar pesquisa novamente';

  @override
  String get nutritionSourceOff => 'Open Food Facts';

  @override
  String get nutritionSourceUsda => 'USDA';

  @override
  String get nutritionScanBarcode => 'Digitalizar código de barras';

  @override
  String get nutritionScanHint =>
      'Aponte a câmara para o código de barras do produto';

  @override
  String get nutritionScanLookingUp => 'A procurar…';

  @override
  String get nutritionScanNotFound =>
      'Nenhum produto encontrado para esse código de barras. Faça uma pesquisa ou insira manualmente.';

  @override
  String get nutritionScanFailed =>
      'Falha ao digitalizar. Faça uma pesquisa ou insira manualmente.';

  @override
  String get nutritionScanPermissionDenied =>
      'É necessário acesso à câmara para digitalizar um código de barras. Ainda pode procurar ou inserir o alimento manualmente.';

  @override
  String get nutritionScanOpenSettings => 'Abrir definições';

  @override
  String get nutritionSaveFailed =>
      'Não foi possível registar o alimento. Tente novamente.';

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
  String get nutritionSaveAsMeal => 'Guardar como refeição';

  @override
  String get nutritionSaveAsMealTitle => 'Guardar como modelo de refeição';

  @override
  String get nutritionTemplateName => 'Nome do modelo';

  @override
  String get nutritionTemplateNamePlaceholder =>
      'ex.: Pequeno-almoço antes da corrida';

  @override
  String get nutritionSaveTemplate => 'Guardar refeição';

  @override
  String get nutritionTemplateSaved => 'Modelo de refeição guardado.';

  @override
  String nutritionTemplateSaveFailed(String error) {
    return 'Não foi possível guardar o modelo: $error';
  }

  @override
  String get nutritionLogTemplate => 'Registar';

  @override
  String nutritionTemplateLogged(int n, String name) {
    return '$n itens registados de $name.';
  }

  @override
  String nutritionTemplateLogFailed(String error) {
    return 'Não foi possível registar o modelo: $error';
  }

  @override
  String nutritionTemplateDeleteFailed(String error) {
    return 'Não foi possível eliminar o modelo: $error';
  }

  @override
  String nutritionTemplateItems(int n) {
    return '$n itens';
  }

  @override
  String get nutritionDeleteTemplate => 'Eliminar';

  @override
  String get nutritionDeleteTemplateTitle =>
      'Eliminar este modelo de refeição?';

  @override
  String nutritionDeleteTemplateMessage(String name) {
    return '$name será removido. As refeições já registadas a partir dele permanecem no seu diário.';
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
  String nutritionRecipeDeleteFailed(String error) {
    return 'Não foi possível eliminar a receita: $error';
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
      'O seu progresso nesta sessão não será guardado.';

  @override
  String get gymSessionDiscardConfirm => 'Descartar';

  @override
  String get gymSessionLeaveSaveFailed =>
      'Não foi possível guardar o seu rascunho — ainda está aqui, por isso nada se perdeu. Tente novamente ou descarte a sessão de propósito.';

  @override
  String get gymSessionLeaveTitle => 'Sair da sessão?';

  @override
  String get gymSessionLeaveBody =>
      'As suas séries registadas ficam guardadas como rascunho — pode retomar a sessão no separador Ginásio ou descartá-la.';

  @override
  String get gymSessionLeaveDraft => 'Sair — manter o rascunho';

  @override
  String get gymSessionKeepGoing => 'Continuar a treinar';

  @override
  String get gymDraftTitle => 'Sessão em curso';

  @override
  String gymDraftSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séries registadas',
      one: '1 série registada',
    );
    return '$_temp0';
  }

  @override
  String get gymDraftResume => 'Retomar';

  @override
  String get gymDraftSave => 'Guardar como está';

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
      'O seu progresso nesta sessão não será guardado.';

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
  String get coachingTitle => 'Atletas e treinadores';

  @override
  String get coachingLede =>
      'Treine atletas a partilhar um link de convite e acompanhe o treino deles. Ou siga o seu próprio treinador aqui.';

  @override
  String get coachingCancel => 'Cancelar';

  @override
  String get coachingMyAthletes => 'Meus atletas';

  @override
  String get coachingMyAthletesSub => 'Corredores que aceitaram o seu convite';

  @override
  String get coachingInviteAnAthlete => 'Convidar um atleta';

  @override
  String get coachingCreating => 'A criar…';

  @override
  String get coachingPendingInvite => 'Convite pendente';

  @override
  String coachingPendingInviteSub(String date) {
    return 'Criado em $date · ainda não aceito';
  }

  @override
  String get coachingCopyLink => 'Copiar link';

  @override
  String get coachingShareLink => 'Partilhar link';

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
    return 'A treinar desde $date';
  }

  @override
  String get coachingReview => 'Revisar';

  @override
  String get coachingRemove => 'Remover';

  @override
  String get coachingMyCoaches => 'Meus treinadores';

  @override
  String get coachingMyCoachesSub => 'Treinadores que podem ver o seu treino';

  @override
  String get coachingNoCoaches =>
      'Ainda não aceitou o convite de um treinador.';

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
      'O link de convite deixará de funcionar. Sempre pode criar um novo.';

  @override
  String get coachingRemoveAthleteTitle => 'Remover atleta?';

  @override
  String coachingRemoveAthleteBody(String name) {
    return 'Parar de treinar $name? Perderá o acesso às corridas e planos dele.';
  }

  @override
  String get coachingLeaveCoachTitle => 'Sair do treinador?';

  @override
  String coachingLeaveCoachBody(String name) {
    return 'Parar de partilhar o seu treino com $name?';
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
    return 'A treinar desde $date';
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
  String get coachingAthleteAssigning => 'A atribuir…';

  @override
  String get coachingAthleteAssignButton => 'Atribuir plano';

  @override
  String get coachingAthleteAssignNoPlans =>
      'Crie primeiro um plano de treino, depois poderá atribuí-lo aos seus atletas.';

  @override
  String get coachingAthleteAssignedByYou => 'Atribuído por si';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'Este atleta já tem um plano ativo. Ele precisará concluí-lo ou encerrá-lo antes que possa atribuir um novo.';

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
  String get coachingAthleteNoRunsYet => 'Nenhuma corrida registada ainda.';

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
  String get routeMarkerDelete => 'Eliminar';

  @override
  String get routeMarkerCancel => 'Cancelar';

  @override
  String get routeMarkerSave => 'Guardar';

  @override
  String get routeMarkerSaving => 'A guardar…';

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
  String get routeMarkerCutoffInvalid =>
      'Introduz o corte como HH:MM (24 horas)';

  @override
  String get routeMarkerTimeClock => 'Relógio';

  @override
  String get routeMarkerTimeElapsed => 'Decorrido';

  @override
  String get routeMarkerNoteLabel => 'Nota';

  @override
  String get routeMarkerTapToPlace =>
      'Toque no mapa para posicionar este marcador.';

  @override
  String get routeMarkerSnapToggle => 'Ajustar à linha do percurso';

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
  String get routeMarkerLatLabel => 'Latitude';

  @override
  String get routeMarkerLngLabel => 'Longitude';

  @override
  String get routeMarkerCoordInvalid =>
      'Insira uma latitude válida (-90 a 90) e uma longitude válida (-180 a 180).';

  @override
  String get routeMarkerEnterCoords => 'Inserir localização';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Não foi possível guardar o marcador: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Não foi possível eliminar o marcador: $error';
  }

  @override
  String get routeMarkerKindAidStation => 'Posto de apoio';

  @override
  String get routeMarkerKindCutoff => 'Corte de tempo';

  @override
  String get routeMarkerKindCrewAccess => 'Equipa / estacionamento';

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
  String get clubEditorSaveChanges => 'Guardar alterações';

  @override
  String get clubDetailVisitWebsite => 'Visite nosso site';

  @override
  String get clubDetailEditClub => 'Editar clube';

  @override
  String get roadbookTitle => 'Roadbook';

  @override
  String get roadbookCrewSheet => 'Roadbook (folha da equipa)';

  @override
  String get roadbookGoalTime => 'Tempo-alvo';

  @override
  String get roadbookStartTime => 'Horário de partida';

  @override
  String get roadbookPlanTitle => 'Plano de prova';

  @override
  String get roadbookPlanExplain =>
      'O relógio calcula a partir disto as horas de chegada e os cortes. Defina uma hora de partida para enviar também os cortes indicados como hora do dia.';

  @override
  String get roadbookPlanCancel => 'Cancelar';

  @override
  String get roadbookPlanSend => 'Enviar';

  @override
  String get roadbookPlanGoalInvalid =>
      'Introduz um tempo objetivo como 4:30:00';

  @override
  String get roadbookEffort => 'Esforço';

  @override
  String get roadbookEven => 'Uniforme';

  @override
  String get roadbookStart => 'Partida';

  @override
  String get roadbookFinish => 'Chegada';

  @override
  String get roadbookShare => 'Partilhar';

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
  String get roadbookColTarget => 'Meta';

  @override
  String get roadbookColLegPace => 'Ritmo do troço';

  @override
  String get roadbookTargetAhead => 'adiantado';

  @override
  String get roadbookTargetOn => 'no plano';

  @override
  String get roadbookTargetBehind => 'atrasado';

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
  String get checkpointWeighInBodyWeight => 'Peso corporal';

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
  String get challengesPaceAhead => 'Adiantado no ritmo';

  @override
  String get challengesPaceOnTrack => 'No ritmo para concluir';

  @override
  String get challengesPaceBehind => 'Atrasado no ritmo';

  @override
  String challengesPaceNeedPerDay(String rate) {
    return '$rate por dia para concluir';
  }

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
  String get challengesLeaderboardEmpty => 'Nenhum progresso registado ainda.';

  @override
  String challengesLeaderboardRank(int rank) {
    return '#$rank';
  }

  @override
  String get challengesStandingTitle => 'A sua posição';

  @override
  String get challengesStandingTitleTeam => 'Posição da sua equipa';

  @override
  String challengesStandingRank(int rank, int total) {
    return '#$rank de $total';
  }

  @override
  String get challengesStandingTiedOne => 'Empatado com mais 1';

  @override
  String challengesStandingTiedMany(int n) {
    return 'Empatado com mais $n';
  }

  @override
  String challengesStandingBehind(String gap, String name) {
    return '$gap atrás de $name';
  }

  @override
  String challengesStandingAhead(String gap, String name) {
    return '$gap à frente de $name';
  }

  @override
  String get challengesStandingLeading => 'Na liderança';

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
  String get challengesDeleteFailed => 'Não foi possível eliminar o desafio.';

  @override
  String get challengesLoadFailed => 'Não foi possível carregar os desafios.';

  @override
  String get challengesProgressUnavailable =>
      'Progresso indisponível — abra para ver o seu resultado';

  @override
  String get challengesTeamNoClub => 'Sem clube';

  @override
  String get challengesTeamPrivateClub => 'Clube privado';

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
  String racesDistanceAway(String distance) {
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
  String get racesTrainForThis => 'Treinar para esta corrida';

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
      'Não foi possível carregar as corridas. Verifique a sua ligação e tente novamente.';

  @override
  String racesMatchPrompt(String name) {
    return 'Foi esta a $name? Importe o seu resultado oficial.';
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
  String get racesRunSignUpBibHint =>
      'Insira o seu número de peito para importarmos apenas o seu resultado, não a lista inteira.';

  @override
  String get racesUltraSignUpAthleteId => 'ID de atleta do UltraSignup';

  @override
  String get racesUltraSignUpAthleteHint =>
      'Insira o seu ID de atleta do UltraSignup ou deixe em branco para usar o desta corrida.';

  @override
  String get racesPasteResultHint =>
      'Introduza os detalhes da sua chegada a partir da página de resultados da corrida.';

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
      'Não foi possível guardar a corrida. Tente novamente.';

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
      'A importação do RunSignUp ainda não está disponível. O parkrun e a colagem manual continuam a funcionar.';

  @override
  String get integrationsUltrasignup => 'UltraSignup';

  @override
  String get integrationsUltrasignupConnect =>
      'Importe resultados de trail e ultra do UltraSignup.';

  @override
  String get integrationsUltrasignupOpen => 'Abrir o calendário de corridas';

  @override
  String get integrationsUltrasignupUnavailable =>
      'A importação do UltraSignup ainda não está disponível. O parkrun e a colagem manual continuam a funcionar.';

  @override
  String get integrationsChronotrack => 'ChronoTrack';

  @override
  String get integrationsChronotrackConnect =>
      'Importe resultados de corridas de eventos cronometrados pelo ChronoTrack.';

  @override
  String get integrationsChronotrackOpen => 'Abrir o calendário de corridas';

  @override
  String get integrationsChronotrackUnavailable =>
      'A importação do ChronoTrack ainda não está disponível. O parkrun e a colagem manual continuam a funcionar.';

  @override
  String get routeConditionsTitle => 'Condições';

  @override
  String get routeConditionsReport => 'Relatar condição';

  @override
  String get routeConditionsReporting => 'A enviar…';

  @override
  String get routeConditionsReported => 'Condição relatada';

  @override
  String get routeConditionsReportFailed =>
      'Não foi possível relatar a condição';

  @override
  String get routeConditionsEmpty => 'Ainda não há relatos.';

  @override
  String get routeConditionsLoading => 'A carregar…';

  @override
  String get routeConditionsCancel => 'Cancelar';

  @override
  String get routeConditionsDelete => 'Eliminar';

  @override
  String get routeConditionsDeleteFailed =>
      'Não foi possível eliminar o relato';

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
      'Direções faladas ao seguir uma rota guardada';

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
  String get ttsUturn => 'Faça inversão de marcha';

  @override
  String routeOfflinePackDownloading(int done, int total) {
    return 'A guardar mapa: $done / $total';
  }

  @override
  String get routeOfflinePackReady => 'Mapa guardado para uso offline';

  @override
  String routeOfflinePackPartial(int done, int total) {
    return 'Mapa parcialmente guardado ($done / $total) — tentar novamente';
  }

  @override
  String get routeOfflinePackTooLarge =>
      'Esta rota é demasiado grande para guardar offline';

  @override
  String get badgesSectionTitle => 'Conquistas';

  @override
  String get badgesSectionSubtitle => 'Marcos que alcançou';

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
  String get badgesDistanceSingle5kDesc => 'Correu 5 km numa única corrida';

  @override
  String get badgesDistanceSingleHalfLabel => 'Meia maratona';

  @override
  String get badgesDistanceSingleHalfDesc =>
      'Correu 21,1 km numa única corrida';

  @override
  String get badgesDistanceSingleMarathonLabel => 'Maratona';

  @override
  String get badgesDistanceSingleMarathonDesc =>
      'Correu 42,2 km numa única corrida';

  @override
  String get badgesDistanceSingleUltraLabel => 'Ultra';

  @override
  String get badgesDistanceSingleUltraDesc =>
      'Correu 50 km ou mais numa única corrida';

  @override
  String get badgesDistanceLifetime100Label => 'Clube dos 100 km';

  @override
  String get badgesDistanceLifetime100Desc => '100 km registados no total';

  @override
  String get badgesDistanceLifetime500Label => '500 km';

  @override
  String get badgesDistanceLifetime500Desc => '500 km registados no total';

  @override
  String get badgesDistanceLifetime1000Label => 'Clube dos 1.000 km';

  @override
  String get badgesDistanceLifetime1000Desc => '1.000 km registados no total';

  @override
  String get badgesDistanceLifetime5000Label => '5.000 km';

  @override
  String get badgesDistanceLifetime5000Desc => '5.000 km registados no total';

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
  String get badgesPr1Desc => 'Estabeleceu o seu primeiro recorde pessoal';

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
      'Ancorado num esforço de algumas semanas atrás.';

  @override
  String get racePredictorConfReasonLimited =>
      'Baseado em dados recentes limitados.';

  @override
  String get racePredictorFootnote =>
      'Equivalência de Riegel a partir do seu melhor esforço recente, ponderada pela recência. Distâncias mais próximas são mais confiáveis.';

  @override
  String get settingsSectionDeveloper => 'Programador';

  @override
  String get settingsTabSimWatchSubtitle =>
      'Estado em direto do relógio personalizado simulado';

  @override
  String get simWatchTitle => 'Link do relógio simulado';

  @override
  String get simWatchHostLabel => 'Anfitrião';

  @override
  String get simWatchPortLabel => 'Porta';

  @override
  String get simWatchConnect => 'Ligar';

  @override
  String get simWatchConnecting => 'A ligar…';

  @override
  String get simWatchDisconnect => 'Desligar';

  @override
  String simWatchConnectionFailed(String error) {
    return 'Falha na ligação: $error';
  }

  @override
  String get simWatchSyncAction => 'Sincronizar corridas do relógio';

  @override
  String simWatchSyncing(int done, int total) {
    return 'A sincronizar… $done/$total';
  }

  @override
  String simWatchResult(int synced, int total) {
    return '$synced de $total corrida(s) sincronizada(s) do relógio';
  }

  @override
  String simWatchSyncFailed(String error) {
    return 'Falha na sincronização do relógio: $error';
  }

  @override
  String get simWatchPushSettingsAction => 'Enviar definições para o relógio';

  @override
  String get simWatchSettingsPushed => 'Definições enviadas para o relógio';

  @override
  String simWatchPushSettingsFailed(String error) {
    return 'Falha ao enviar definições: $error';
  }

  @override
  String get simWatchPushWorkoutAction => 'Enviar treino para o relógio';

  @override
  String simWatchWorkoutPushed(int steps) {
    return 'Treino enviado para o relógio ($steps etapas)';
  }

  @override
  String simWatchPushWorkoutFailed(String error) {
    return 'Falha ao enviar treino: $error';
  }

  @override
  String get simWatchPushRoadbookAction =>
      'Enviar plano de corrida para o relógio';

  @override
  String simWatchRoadbookPushed(int checkpoints, int cutoffs) {
    return 'Plano de corrida enviado para o relógio ($checkpoints pontos de controlo, $cutoffs cortes)';
  }

  @override
  String simWatchPushRoadbookFailed(String error) {
    return 'Falha ao enviar o plano de corrida: $error';
  }

  @override
  String get simWatchPushCourseAction => 'Enviar percurso para o relógio';

  @override
  String simWatchCoursePushed(int points) {
    return 'Percurso enviado para o relógio ($points pontos)';
  }

  @override
  String simWatchPushCourseFailed(String error) {
    return 'Falha ao enviar percurso: $error';
  }

  @override
  String get simWatchNoRuns => 'Nenhuma corrida no relógio para sincronizar';

  @override
  String get simWatchWaitingFrames => 'Ligado — a aguardar tramas…';

  @override
  String get simWatchUptime => 'Tempo de atividade do relógio';

  @override
  String get simWatchNoFix => 'Ainda sem sinal GPS';

  @override
  String get simWatchPosition => 'Posição';

  @override
  String get simWatchSpeed => 'Velocidade';

  @override
  String get simWatchSatellites => 'Satélites';

  @override
  String get simWatchAltitude => 'Altitude';

  @override
  String get simWatchBaroAltitude => 'Altitude barométrica';

  @override
  String get simWatchAscent => 'Subida';

  @override
  String get simWatchDescent => 'Descida';

  @override
  String get simWatchFixAge => 'Idade do sinal';

  @override
  String simWatchSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get sessionLoadError => 'Não foi possível carregar as sessões.';

  @override
  String get sessionDetailLoadError =>
      'Não foi possível carregar este plano de sessão.';

  @override
  String get gymEditorRemoveExerciseTitle => 'Remover exercício?';

  @override
  String get gymEditorRemoveExerciseBody =>
      'Este exercício e todas as suas séries serão removidos deste treino.';

  @override
  String get gymEditorRemoveExerciseConfirm => 'Remover';

  @override
  String get eventSubmitRunsLoadError =>
      'Não foi possível carregar as suas corridas recentes.';

  @override
  String get racesCouldNotOpenLink => 'Não foi possível abrir esse link.';

  @override
  String get prefsHrZonesClearTitle => 'Limpar zonas de frequência cardíaca?';

  @override
  String get prefsHrZonesClearBody =>
      'As suas cinco zonas personalizadas serão limpas.';

  @override
  String get prefsHrZonesClearConfirm => 'Limpar';

  @override
  String get signInRequiredMessage => 'Faça login para utilizar este recurso.';

  @override
  String get signInRequiredAction => 'Entrar';

  @override
  String get backendUnavailableMessage =>
      'Não foi possível conectar ao servidor no momento. Os recursos online estão indisponíveis.';

  @override
  String get feedSignedOutMessage =>
      'Faça login para ver as corridas das pessoas que segue.';

  @override
  String ttsPaceAlertSpeedUpByKm(int sec) {
    return 'Acelere $sec segundos por quilómetro';
  }

  @override
  String ttsPaceAlertSpeedUpByMi(int sec) {
    return 'Acelere $sec segundos por milha';
  }

  @override
  String ttsPaceAlertSlowDownByKm(int sec) {
    return 'Abrande $sec segundos por quilómetro';
  }

  @override
  String ttsPaceAlertSlowDownByMi(int sec) {
    return 'Abrande $sec segundos por milha';
  }

  @override
  String ttsCutoffCatchUp(String distance, String pace) {
    return 'Próximo corte em $distance. Precisa de $pace para conseguir.';
  }

  @override
  String get ttsCutoffUnreachable =>
      'Próximo corte: o limite de tempo já passou.';

  @override
  String ttsMarkerAheadOfPlan(String label, String time) {
    return '$label: $time adiantado em relação ao plano';
  }

  @override
  String ttsMarkerBehindPlan(String label, String time) {
    return '$label: $time atrasado em relação ao plano';
  }

  @override
  String ttsMarkerOnPlan(String label) {
    return '$label: dentro do plano';
  }

  @override
  String ttsPhaseStart(int index, int total, String phrase) {
    return 'Fase $index de $total. $phrase';
  }

  @override
  String get ttsPhaseHoldBack => 'Contenha-se. Mantenha o controlo.';

  @override
  String get ttsPhaseSettle => 'Assente no seu ritmo objetivo.';

  @override
  String get ttsPhaseRace => 'Hora de correr. Dê o que lhe resta.';

  @override
  String get ttsPhaseEven => 'Mantenha um esforço constante.';

  @override
  String ttsPhaseTargetPace(String pace) {
    return 'Objetivo: $pace.';
  }

  @override
  String get prefsVoiceCueTypesLabel => 'Avisos falados';

  @override
  String get prefsCueSplits => 'Parciais';

  @override
  String get prefsCueSplitsSubtitle =>
      'O seu ritmo (ou velocidade) cada vez que passa um marcador de parcial';

  @override
  String get prefsCueSplitsInfo =>
      'Diz um breve resumo cada vez que completa um parcial (defina a distância em Intervalo de parciais). Utilize Anúncio de parciais para escolher ritmo do parcial, ritmo médio ou ambos. Exemplo: “1 quilómetro. Ritmo, 5 minutos e 30 segundos por quilómetro.”';

  @override
  String get prefsCueStartFinish => 'Início e fim';

  @override
  String get prefsCueStartFinishSubtitle =>
      '“Corrida iniciada” no começo e um resumo ao terminar';

  @override
  String get prefsCueStartFinishInfo =>
      'Confirma que a corrida começou e lê a sua distância e tempo ao parar. Exemplo: “Corrida concluída. 10,0 quilómetros em 52 minutos.”';

  @override
  String get prefsCueOffRoute => 'Fora do percurso';

  @override
  String get prefsCueOffRouteSubtitle =>
      'Um aviso quando se afasta do percurso que está a seguir';

  @override
  String get prefsCueOffRouteInfo =>
      'Só funciona quando inicia uma corrida com um percurso guardado. Avisa assim que se afasta dele para voltar ao caminho. Exemplo: “Fora do percurso.”';

  @override
  String get prefsCuePaceAlerts => 'Alertas de desvio de ritmo';

  @override
  String get prefsCuePaceAlertsSubtitle =>
      '“Acelere” / “diminua” quando se desvia do seu ritmo alvo';

  @override
  String get prefsCuePaceAlertsInfo =>
      'Precisa de um ritmo alvo definido. Quando se desvia mais de uns 30 segundos, isto diz para que lado ajustar e quanto. Exemplo: “Acelere 8 segundos.”';

  @override
  String get prefsCueWorkoutSteps => 'Passos do treino';

  @override
  String get prefsCueWorkoutStepsSubtitle =>
      'Anuncia cada passo de um treino estruturado ao começar';

  @override
  String get prefsCueWorkoutStepsInfo =>
      'Só fica ativo durante um treino estruturado (uma sessão de plano ou treino de intervalos). Anuncia cada passo e o seu alvo para si manter os olhos à frente. Exemplo: “Repetição 3 de 5. 400 metros a 4 minutos e 30 segundos por quilómetro.”';

  @override
  String get prefsCueCutoffCatchUp => 'Apanhar o corte';

  @override
  String get prefsCueCutoffCatchUpSubtitle =>
      'O ritmo necessário para um corte que corre risco de perder';

  @override
  String get prefsCueCutoffCatchUpInfo =>
      'Só fica ativo num percurso com cortes de tempo. Se um estiver em risco, lê a distância até ele e o ritmo que ainda o alcança. Exemplo: “2 quilómetros até o corte. 6 minutos por quilómetro.”';

  @override
  String get prefsCueMarkerTargets => 'Marcadores do percurso';

  @override
  String get prefsCueMarkerTargetsSubtitle =>
      'Se está à frente ou atrás do plano em cada marcador';

  @override
  String get prefsCueMarkerTargetsInfo =>
      'Só fica ativo num percurso cujos marcadores têm tempos alvo. Ao passar por cada um, diz se está à frente ou atrás, e por quanto. Exemplo: “Posto 2: 45 segundos à frente do plano.”';

  @override
  String get prefsCuePhaseTransitions => 'Fases da corrida';

  @override
  String get prefsCuePhaseTransitionsSubtitle =>
      'Um aviso quando cada fase da sua estratégia de corrida começa';

  @override
  String get prefsCuePhaseTransitionsInfo =>
      'Só fica ativo quando escolhe uma estratégia de corrida. Anuncia cada fase e a sua intenção ao começar. Exemplo: “Fase 2 de 3. Estabilize no seu ritmo alvo.”';

  @override
  String get prefsCueGuidedRun => 'Corridas guiadas';

  @override
  String get prefsCueGuidedRunSubtitle =>
      'O guião do treinador de uma corrida guiada escolhida antes de começar';

  @override
  String get prefsCueGuidedRunInfo =>
      'Só fica ativo quando escolhe uma corrida guiada no separador Corrida antes de começar. Anuncia cada indicação do guião ao chegar à sua marca. Exemplo: “Cinco minutos. Estabilize num ritmo que aguentaria o dia todo.”';

  @override
  String get runGuidedRun => 'Corrida guiada';

  @override
  String get runGuidedRunNone => 'Sem corrida guiada';

  @override
  String runGuidedRunOption(int minutes, String subtitle) {
    return '$minutes min · $subtitle';
  }

  @override
  String get runRaceStrategy => 'Estratégia de corrida';

  @override
  String get runStrategyNone => 'Sem estratégia';

  @override
  String get runStrategyTenTenTen => '10-10-10';

  @override
  String get runStrategyNegativeSplit => 'Split negativo';

  @override
  String get runStrategyEven => 'Ritmo constante';

  @override
  String get runStrategyTenTenTenHint =>
      'Conter, assentar e correr o troço final';

  @override
  String get runStrategyNegativeSplitHint =>
      'Primeira metade controlada, segunda mais rápida';

  @override
  String get runStrategyEvenHint => 'Um ritmo constante do início ao fim';

  @override
  String get runStrategyGoalTime => 'Tempo objetivo';

  @override
  String get runStrategyDistance => 'Distância';

  @override
  String get runStrategyNeedsDistance =>
      'Escolha um percurso ou introduza uma distância para ativar fases';

  @override
  String get runStrategyInvalidGoal => 'Insira o tempo alvo como h:mm:ss';

  @override
  String runPhaseChip(int index, int total, String intent) {
    return 'Fase $index/$total — $intent';
  }

  @override
  String get phaseIntentHoldBack => 'Conter';

  @override
  String get phaseIntentSettle => 'Assentar';

  @override
  String get phaseIntentRace => 'Correr';

  @override
  String get phaseIntentEven => 'Constante';

  @override
  String routeMarkerTargetChip(String time) {
    return 'Objetivo $time';
  }

  @override
  String get routeMarkerTargetLabel => 'Tempo objetivo';

  @override
  String get routeMarkerTargetHelper => 'Horas : minutos : segundos';

  @override
  String get routeMarkerTargetInvalid =>
      'Introduz o tempo objetivo como h:mm:ss';

  @override
  String get routeMarkerOfficialBadge => 'Dono da rota';

  @override
  String get routeMarkerDistanceAlongLabel => 'Distância ao longo da rota';

  @override
  String get routeMarkerDistanceInvalid =>
      'Introduz uma distância válida ao longo da rota.';

  @override
  String get watchScreensTitle => 'Ecrãs do relógio';

  @override
  String get watchScreensAction => 'Compor os ecrãs do relógio';

  @override
  String watchScreensCount(int count, int max) {
    return '$count de $max ecrãs';
  }

  @override
  String get watchScreensEmptyTitle => 'Nenhum ecrã composto';

  @override
  String get watchScreensEmptyBody =>
      'O relógio percorre as páginas integradas até compor um. Adicione um ecrã para escolher o que mostra.';

  @override
  String get watchScreensAdd => 'Adicionar ecrã';

  @override
  String watchScreensFull(int max) {
    return 'Um relógio comporta no máximo $max ecrãs.';
  }

  @override
  String watchScreensHeading(int index) {
    return 'Ecrã $index';
  }

  @override
  String get watchScreensLayout => 'Esquema';

  @override
  String watchScreensSlot(int index) {
    return 'Espaço $index';
  }

  @override
  String get watchScreensMoveUp => 'Mover para cima';

  @override
  String get watchScreensMoveDown => 'Mover para baixo';

  @override
  String get watchScreensRemove => 'Remover ecrã';

  @override
  String watchScreensRemoveTitle(int index) {
    return 'Remover o ecrã $index?';
  }

  @override
  String watchScreensRemoveBody(int count) {
    return 'As suas $count métrica(s) vão com ele.';
  }

  @override
  String get watchScreensRemoveConfirm => 'Remover';

  @override
  String get watchScreensCancel => 'Cancelar';

  @override
  String watchScreensShrinkTitle(int count) {
    return 'Descartar $count métrica(s)?';
  }

  @override
  String watchScreensShrinkBody(String layout, int slots, String dropped) {
    return 'Um esquema $layout desenha $slots espaço(s), por isso $dropped deixaria de aparecer.';
  }

  @override
  String get watchScreensShrinkConfirm => 'Alterar o esquema';

  @override
  String get watchScreensPushAction => 'Enviar os ecrãs para o relógio';

  @override
  String watchScreensPushed(int count) {
    return '$count ecrã(s) enviado(s) para o relógio';
  }

  @override
  String get watchScreensCleared => 'Ecrãs compostos apagados no relógio';

  @override
  String watchScreensPushFailed(String error) {
    return 'Falha ao enviar os ecrãs: $error';
  }

  @override
  String get watchScreensLoadFailed =>
      'Não foi possível ler os ecrãs guardados.';

  @override
  String get watchScreensStartOver => 'Começar novamente';

  @override
  String get watchLayoutSingle => 'Simples';

  @override
  String get watchLayoutDuo => 'Duo';

  @override
  String get watchLayoutTrio => 'Trio';

  @override
  String get watchMetricElapsed => 'Tempo decorrido';

  @override
  String get watchMetricDistance => 'Distância';

  @override
  String get watchMetricAvgPace => 'Ritmo médio';

  @override
  String get watchMetricLapElapsed => 'Tempo da volta';

  @override
  String get watchMetricHeartRate => 'Frequência cardíaca';

  @override
  String get watchMetricPacerDelta => 'Diferença para o pacer';

  @override
  String get watchMetricGuidedRunRemaining => 'Aviso da corrida guiada';

  @override
  String get watchMetricWorkoutRemaining => 'Etapa do treino';

  @override
  String get watchMetricRacePrediction => 'Previsão de prova';

  @override
  String get watchMetricCutoffMargin => 'Margem para o corte';

  @override
  String get watchMetricTrainingStress => 'Carga de treino';

  @override
  String get watchMetricRoadbookNext => 'Próximo posto de apoio';

  @override
  String get watchMetricFuelCarbs => 'Hidratos de carbono';

  @override
  String get watchMetricGearWear => 'Desgaste do equipamento';

  @override
  String get watchMetricEasyPace => 'Ritmo leve';

  @override
  String get watchMetricVo2Max => 'VO2 máx.';

  @override
  String get watchMetricAltitude => 'Altitude';

  @override
  String get watchMetricDistanceToStart => 'Distância até à partida';

  @override
  String get watchMetricDaylightCountdown => 'Luz do dia restante';

  @override
  String get watchMetricWaypointDistance => 'Distância ao ponto marcado';

  @override
  String get watchMetricClimbGain => 'Ganho de subida';

  @override
  String get watchMetricRecapDistance => 'Distância do ano';

  @override
  String get watchMetricCurrentStreak => 'Sequência atual';

  @override
  String get watchMetricSyncedMovingTime => 'Tempo em movimento';

  @override
  String get watchMetricPrAge => 'Idade do recorde';

  @override
  String get watchMetricPlanReplanChanges => 'Alterações do replaneamento';

  @override
  String get watchMetricPlanAdaptiveChanges => 'Alterações adaptativas';

  @override
  String get watchMetricReadinessScore => 'Prontidão';

  @override
  String get watchMetricGoalPercent => 'Progresso do objetivo';

  @override
  String get watchMetricTurnCueDistance => 'Próxima curva';

  @override
  String get watchMetricRouteSimplifyDistance => 'Distância do percurso';

  @override
  String get watchMetricAutoEffortMatched => 'Segmentos correspondidos';

  @override
  String get watchMetricRouteElevTotal => 'Desnível do percurso';

  @override
  String get watchMetricRaceDayDays => 'Dias até à prova';

  @override
  String get watchMetricSleepBudget => 'Margem de sono';

  @override
  String get watchMetricTimerRemaining => 'Temporizador';

  @override
  String get watchMetricBackyardBell => 'Contagem decrescente do sino';

  @override
  String get watchMetricStormDelta => 'Tendência de tempestade';

  @override
  String get watchMetricGap => 'Ritmo ajustado à inclinação';

  @override
  String get watchMetricFluid => 'Líquido';

  @override
  String get watchLiveTitle => 'Seguir corrida do relógio';

  @override
  String get watchLiveTileSubtitle =>
      'Retransmitir a posição do seu relógio para um link em direto';

  @override
  String get watchLiveIntro =>
      'Enquanto este ecrã estiver aberto, o telemóvel retransmite a posição do relógio aos espetadores cerca de uma vez por segundo. Mantenha o telemóvel consigo e ao alcance do Bluetooth — sair deste ecrã termina a retransmissão.';

  @override
  String get watchLiveStateOff => 'Sem ligação';

  @override
  String get watchLiveStateConnecting => 'A ligar';

  @override
  String get watchLiveStateLive => 'Em direto';

  @override
  String get watchLiveStateGap => 'Falha';

  @override
  String get watchLiveStateLost => 'Desistiu';

  @override
  String get watchLiveDetailOff => 'Não está a ser enviado nada.';

  @override
  String get watchLiveDetailSearching => 'À procura do seu relógio…';

  @override
  String get watchLiveDetailAwaitingFix =>
      'Ligado — à espera da primeira posição do relógio.';

  @override
  String get watchLiveDetailGap =>
      'os espetadores veem a última posição como atrasada, não como atual';

  @override
  String get watchLiveDetailLost =>
      'O seu relógio está desligado ou fora de alcance. Não está a ser enviado nada de novo.';

  @override
  String get watchLiveStart => 'Iniciar retransmissão';

  @override
  String get watchLiveStop => 'Parar retransmissão';

  @override
  String get watchLiveRetry => 'Tentar novamente';

  @override
  String get watchLiveShare => 'Partilhar link em direto';

  @override
  String get watchLiveStartFailed =>
      'Não foi possível iniciar a emissão em direto — não está a ser partilhado nada.';

  @override
  String get watchLiveSyncAction => 'Sincronizar corridas do relógio';

  @override
  String get watchLiveSyncSubtitle =>
      'Transfere as corridas gravadas no relógio. A retransmissão fica em pausa durante esse período.';

  @override
  String pendingSyncOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count alterações guardadas neste dispositivo — serão sincronizadas quando estiver on-line',
      one:
          '$count alteração guardada neste dispositivo — será sincronizada quando estiver on-line',
    );
    return '$_temp0';
  }

  @override
  String pendingSyncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alterações não foram sincronizadas',
      one: '$count alteração não foi sincronizada',
    );
    return '$_temp0';
  }

  @override
  String get pendingSyncRetry => 'Tentar novamente';

  @override
  String get photoOpen => 'Abrir fotografia';

  @override
  String get photoLightboxClose => 'Fechar fotografia';

  @override
  String get photoLightboxLoading => 'A carregar a fotografia…';

  @override
  String get photoLightboxError => 'Não foi possível carregar esta fotografia.';

  @override
  String get photoLightboxErrorHint => 'Toque em qualquer sítio para fechar.';

  @override
  String get commonLoading => 'A carregar…';

  @override
  String get commonMore => 'Mais';

  @override
  String get undoAction => 'Desfazer';

  @override
  String get undoDismiss => 'Fechar';

  @override
  String get undoHint => 'Desfazer fica disponível por um curto período.';

  @override
  String get undoRestored => 'Restaurado';

  @override
  String get prefsUndoWindow => 'Janela para desfazer';

  @override
  String get prefsUndoWindow8s => '8 segundos';

  @override
  String get prefsUndoWindow30s => '30 segundos';

  @override
  String get prefsUndoWindowManual => 'Até eu fechar';

  @override
  String undoDismissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notificações descartadas',
      one: 'Notificação descartada',
    );
    return '$_temp0';
  }

  @override
  String get routeConditionsRemoved => 'Relato de condição removido';

  @override
  String get gearWearLogRemoved => 'Observação removida';

  @override
  String nutritionEntryRemoved(String item) {
    return '$item removido';
  }

  @override
  String get runSocialCommentRemoved => 'Comentário removido';

  @override
  String get routeDetailReviewRemoved => 'Avaliação removida';

  @override
  String get routeMarkerRemoved => 'Marcador removido';

  @override
  String get roadbookNeedsRouteLine =>
      'Adicione pelo menos dois pontos a esta rota para montar um roadbook.';

  @override
  String get settingsGearUnavailable =>
      'Equipamento não está disponível nesta versão';

  @override
  String get loadRampTitle => 'Progressão de carga';

  @override
  String get loadRampRatioCaption => 'esta semana vs a sua média de 4 semanas';

  @override
  String get loadRampAcuteLabel => 'Últimos 7 dias';

  @override
  String get loadRampChronicLabel => 'Média semanal (4 semanas)';

  @override
  String get loadRampBandLow => 'Baixa';

  @override
  String get loadRampBandOptimal => 'Ótima';

  @override
  String get loadRampBandElevated => 'Elevada';

  @override
  String get loadRampBandHigh => 'Alta';

  @override
  String get loadRampMeaningLow =>
      'Está a correr abaixo da sua base recente. Ok para um polimento ou semana de recuperação; se durar, é perda de forma.';

  @override
  String get loadRampMeaningOptimal =>
      'A sua semana está na faixa que melhor protege contra lesões. Continue evoluindo nesse ritmo.';

  @override
  String get loadRampMeaningElevated =>
      'Subiu mais depressa do que a sua base recente sustenta. Mantenha esta semana estável em vez de adicionar mais.';

  @override
  String get loadRampMeaningHigh =>
      'É um salto forte sobre a sua base recente — o padrão mais associado a lesões. Considere uma semana mais leve.';

  @override
  String get loadRampTrendRamping => 'A sua carga está a aumentar.';

  @override
  String get loadRampTrendSteady => 'A sua carga está estável.';

  @override
  String get loadRampTrendTapering => 'A sua carga está a diminuir.';

  @override
  String get comebackTitle => 'De regresso de uma pausa';

  @override
  String get comebackVerdictEasingIn => 'Retomada gradual';

  @override
  String get comebackVerdictSteep => 'Primeira semana puxada';

  @override
  String comebackLayoff(int weeks) {
    return '$weeks semanas sem correr';
  }

  @override
  String get comebackShareCaption =>
      'esta semana em relação à sua média semanal antes da pausa';

  @override
  String get comebackMeaningEasingIn =>
      'Esta semana está confortavelmente abaixo das semanas que corria antes da pausa. Reconstruir aos poucos a partir daqui é o que faz a volta se sustentar.';

  @override
  String get comebackMeaningSteep =>
      'Esta semana já passa da metade do que corria antes da pausa. O seu corpo perdeu a base que tornava aquelas semanas rotineiras, então uma semana mais curta agora custa muito menos do que uma recaída depois.';

  @override
  String get comebackThisWeekLabel => 'Últimos 7 dias';

  @override
  String get comebackBaseLabel => 'Média semanal antes da pausa';

  @override
  String get comebackFootnote =>
      'A sua curva de carga de treino volta assim que tiver algumas semanas consistentes novamente.';

  @override
  String get segmentCatalogueTitle => 'Segmentos famosos';

  @override
  String get segmentCatalogueIntro =>
      'Subidas, pontes e voltas de parque selecionadas no mundo todo. Corra um deles e o seu tempo entra no ranking automaticamente.';

  @override
  String get segmentCatalogueSearchLabel => 'Procurar';

  @override
  String get segmentCatalogueSearchHint => 'Nome ou lugar';

  @override
  String get segmentCatalogueRegion => 'Região';

  @override
  String get segmentCatalogueAllRegions => 'Todas as regiões';

  @override
  String get segmentCatalogueSurface => 'Piso';

  @override
  String get segmentCatalogueAllSurfaces => 'Todos os pisos';

  @override
  String get segmentCatalogueSort => 'Ordenar';

  @override
  String get segmentCatalogueSortName => 'Nome';

  @override
  String get segmentCatalogueSortShortest => 'Mais curtos primeiro';

  @override
  String get segmentCatalogueSortLongest => 'Mais longos primeiro';

  @override
  String get segmentCatalogueSortClimb => 'Mais altimetria';

  @override
  String segmentCatalogueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segmentos',
      one: '$count segmento',
    );
    return '$_temp0';
  }

  @override
  String get segmentCatalogueLoadFailed =>
      'Não foi possível carregar o catálogo de segmentos.';

  @override
  String get segmentCatalogueEmpty =>
      'Ainda não há segmentos famosos no catálogo.';

  @override
  String get segmentCatalogueNoMatches =>
      'Nenhum segmento corresponde a estes filtros — tente ampliá-los.';

  @override
  String get segmentCatalogueBrowseAll => 'Ver todos';

  @override
  String get segmentCatalogueNotFoundTitle => 'Segmento não encontrado';

  @override
  String get segmentCatalogueNotFoundBody =>
      'Este segmento não está no catálogo ou foi removido.';

  @override
  String get segmentCatalogueDetailFailedTitle =>
      'Não foi possível carregar este segmento';

  @override
  String get segmentCatalogueDetailFailedBody =>
      'Verifique a sua ligação e tente novamente.';

  @override
  String get segmentCatalogueStatDistance => 'Distância';

  @override
  String get segmentCatalogueStatElevation => 'Ganho de elevação';

  @override
  String get segmentCatalogueStatSurface => 'Piso';

  @override
  String get segmentCatalogueLeaderboard => 'Classificação';

  @override
  String get runSurfaceTabSegments => 'Segmentos';

  @override
  String rateLimitCreateClub(String wait) {
    return 'Está a criar clubes demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitCreateRoute(String wait) {
    return 'Está a criar percursos demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitCreateReport(String wait) {
    return 'Está a enviar denúncias demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitCreateChallenge(String wait) {
    return 'Está a criar desafios demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitAdoptPlan(String wait) {
    return 'Está a adotar planos demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitAdoptSessionPlan(String wait) {
    return 'Está a adotar planos de sessão demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitAdoptGymRoutine(String wait) {
    return 'Está a adotar rotinas de ginásio demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitPublishRoutine(String wait) {
    return 'Está a publicar rotinas demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitSendMessage(String wait) {
    return 'Está a enviar mensagens demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitGeneric(String wait) {
    return 'Está a fazer isto demasiado depressa — aguarde $wait e tente novamente.';
  }

  @override
  String rateLimitWaitSeconds(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n segundos',
      one: '1 segundo',
    );
    return '$_temp0';
  }

  @override
  String rateLimitWaitMinutes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get rateLimitWaitSoon => 'um momento';

  @override
  String get challengesCreate => 'Criar desafio';

  @override
  String get challengesTitleLabel => 'Título';

  @override
  String get challengesDescriptionLabel => 'Descrição';

  @override
  String get challengesMetricLabel => 'Métrica';

  @override
  String get challengesScopeLabel => 'Tipo';

  @override
  String get challengesGoalOptional => 'Meta (opcional)';

  @override
  String get challengesActivityTypeLabel => 'Atividade';

  @override
  String get challengesActivityAny => 'Qualquer';

  @override
  String get challengesClubLabel => 'Clube';

  @override
  String get challengesClubNone => 'Aberto (todos)';

  @override
  String get challengesStartLabel => 'Início';

  @override
  String get challengesEndLabel => 'Fim';

  @override
  String get challengesScopeIndividual => 'Individual';

  @override
  String get challengesScopeClubVsClub => 'Clube contra clube';

  @override
  String get challengesScopeGroupGoal => 'Meta de grupo';

  @override
  String get challengesSuffixHours => 'h';

  @override
  String get challengesSuffixActivities => 'atividades';

  @override
  String get challengesSuffixDays => 'dias';

  @override
  String challengesGoalPreview(String value) {
    return 'Os participantes veem $value';
  }

  @override
  String challengesGoalStreakCeiling(int n) {
    return 'Nesta janela cabem no máximo $n dias ativos.';
  }

  @override
  String get challengesErrTitle => 'Dê um título ao desafio.';

  @override
  String get challengesErrGoal => 'Meta: insira um número positivo';

  @override
  String get challengesErrWindow => 'O fim deve ser depois do início.';

  @override
  String limitsWeightOutOfRange(String min, String max, String unit) {
    return 'Introduza um peso entre $min e $max $unit.';
  }

  @override
  String limitsHeightOutOfRange(String min, String max) {
    return 'Introduza uma altura entre $min e $max cm.';
  }

  @override
  String limitsServingsOutOfRange(String min, String max) {
    return 'Introduza um número de doses entre $min e $max.';
  }

  @override
  String runDetailGuidedRun(String title) {
    return 'Corrida guiada: $title';
  }

  @override
  String get runDetailGuidedRunUnavailable =>
      'Corrida guiada já não consta da biblioteca';

  @override
  String get guidedRunUseThisRun => 'Utilizar esta corrida';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

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
  String recapMonthShareHeadline(Object period) {
    return 'Meu $period na corrida:';
  }

  @override
  String recapMonthShareSubject(Object period) {
    return 'Retrospectiva $period';
  }

  @override
  String get recapTitle => 'Ano na corrida';

  @override
  String get recapMonthTitle => 'Mês na corrida';

  @override
  String get recapPeriodYear => 'Ano';

  @override
  String get recapPeriodMonth => 'Mês';

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
  String get recapPrevMonth => 'Mês anterior';

  @override
  String get recapNextMonth => 'Próximo mês';

  @override
  String recapNoRunsForPeriod(Object period) {
    return 'Nenhuma corrida para a retrospectiva de $period.';
  }

  @override
  String recapNoRunsYetInPeriod(Object period) {
    return 'Ainda não há corridas em $period. Registre uma para ver sua retrospectiva.';
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
  String importFailuresHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count atividades não foram importadas',
      one: '1 atividade não foi importada',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresIntro =>
      'Refaça a importação para tentar de novo — o que já entrou é ignorado, então nada é duplicado.';

  @override
  String importFailuresTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mais $count falhas não foram registradas.',
      one: 'Mais 1 falha não foi registrada.',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresShowDetail => 'Ver cada atividade';

  @override
  String get importFailuresShare => 'Compartilhar relatório (CSV)';

  @override
  String get importFailuresShareFailed =>
      'Não foi possível compartilhar o relatório.';

  @override
  String get importFailuresDismiss => 'Dispensar';

  @override
  String get importFailuresNoDate => 'Data desconhecida';

  @override
  String get importFailuresReasonNetwork => 'Conexão interrompida';

  @override
  String get importFailuresReasonAuth => 'Sessão encerrada';

  @override
  String get importFailuresReasonRateLimited => 'Limite de requisições';

  @override
  String get importFailuresReasonTooLarge => 'Arquivo grande demais';

  @override
  String get importFailuresReasonUnparseable =>
      'Não foi possível ler o arquivo';

  @override
  String get importFailuresReasonRejected => 'Recusado pelo servidor';

  @override
  String get importFailuresReasonUnknown => 'Erro desconhecido';

  @override
  String importStatusCloudPushDeferred(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count corridas estão salvas neste dispositivo — o envio para a nuvem não foi concluído. Vai tentar de novo na próxima sincronização.',
      one:
          '1 corrida está salva neste dispositivo — o envio para a nuvem não foi concluído. Vai tentar de novo na próxima sincronização.',
    );
    return '$_temp0';
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
  String importHealthRoutesWithheld(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count atividades importadas têm mapas de GPS que o Threkir não tem permissão para ler.',
      one:
          '1 atividade importada tem um mapa de GPS que o Threkir não tem permissão para ler.',
    );
    return '$_temp0 O Health Connect protege a rota de um treino com uma permissão própria.';
  }

  @override
  String get importHealthRoutesAllowButton => 'Permitir importar mapas';

  @override
  String get importHealthRoutesRequesting =>
      'Solicitando acesso aos mapas ao Health Connect...';

  @override
  String get importHealthRoutesDenied =>
      'Acesso aos mapas não concedido. As importações continuam sem mapa — você pode mudar isso no Health Connect quando quiser.';

  @override
  String get importHealthRoutesAdding =>
      'Adicionando mapas às atividades importadas...';

  @override
  String importHealthRoutesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mapas adicionados a $count atividades.',
      one: 'Mapa adicionado a 1 atividade.',
      zero: 'Nenhum mapa pôde ser adicionado.',
    );
    return '$_temp0';
  }

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
  String get commonCancel => 'Cancelar';

  @override
  String get placeSearchNoResults => 'Nenhum lugar encontrado';

  @override
  String get placeSearchUnavailable =>
      'A busca de lugares está indisponível no momento';

  @override
  String get placeSearchRetry => 'Tentar novamente';

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
  String get peopleNearbyHeader => 'Corredores por perto';

  @override
  String get peopleNearbySubtitle =>
      'Corredores que optaram por participar perto da área que você definiu. Apenas distância aproximada, nunca uma localização em tempo real.';

  @override
  String get peopleNearbyEmptyTitle => 'Ainda não há ninguém por perto';

  @override
  String get peopleNearbyEmptyBody =>
      'Ative “Mostrar meu perfil a corredores por perto” e defina sua área. Só os corredores que fizeram o mesmo podem te encontrar.';

  @override
  String get peopleNearbyEmptyAction => 'Abrir Preferências';

  @override
  String get peopleNearbyLoadFailed =>
      'Não foi possível carregar os corredores por perto.';

  @override
  String peopleNearbyWithin(String distance) {
    return 'A menos de $distance';
  }

  @override
  String peopleNearbyBeyond(String distance) {
    return 'A mais de $distance';
  }

  @override
  String get prefsDiscoverableNearby =>
      'Mostrar meu perfil a corredores por perto';

  @override
  String get prefsDiscoverableNearbySubtitle =>
      'Desativado por padrão. Quando ativado, outros corredores que também optaram por participar veem que você está aproximadamente por perto — uma distância aproximada da área que você definiu, nunca sua localização.';

  @override
  String get nearbyAreaTitle => 'Sua área';

  @override
  String get nearbyAreaExplainer =>
      'Escolha a cidade ou o bairro onde você corre. Ela é salva arredondada para cerca de um quilômetro e nunca é sua localização em tempo real. Os outros corredores só veem uma distância aproximada, nunca a área em si.';

  @override
  String get nearbyAreaNone => 'Nenhuma área definida';

  @override
  String nearbyAreaCurrent(String label) {
    return 'Área atual: $label';
  }

  @override
  String get nearbyAreaSearchHint => 'Buscar uma cidade ou bairro';

  @override
  String get nearbyAreaSearchUnavailable =>
      'A busca de locais está indisponível neste momento.';

  @override
  String get nearbyAreaNoResults => 'Nenhum local corresponde a essa busca.';

  @override
  String get nearbyAreaSaved => 'Área salva';

  @override
  String get nearbyAreaSaveFailed => 'Não foi possível salvar sua área.';

  @override
  String get nearbyAreaLoadFailed => 'Não foi possível carregar sua área.';

  @override
  String get nearbyAreaForget => 'Esquecer minha área';

  @override
  String get nearbyAreaForgetConfirmTitle => 'Esquecer sua área?';

  @override
  String get nearbyAreaForgetConfirmBody =>
      'Você deixará de aparecer para corredores por perto até definir uma área novamente.';

  @override
  String get nearbyAreaForgotten => 'Área esquecida';

  @override
  String get nearbyAreaForgetFailed => 'Não foi possível esquecer sua área.';

  @override
  String get peopleFallbackDisplayName => 'Corredor';

  @override
  String get peopleFollowingButton => 'Seguindo';

  @override
  String get peopleFollowButton => 'Seguir';

  @override
  String get peopleSignedOutMessage =>
      'Faça login para pesquisar e seguir outros corredores.';

  @override
  String get peopleSuggestionsLoadFailed =>
      'Não foi possível carregar as sugestões.';

  @override
  String get readinessCardHeader => 'Prontidão';

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
  String get runSurfaceLabel => 'Seções da área de corrida';

  @override
  String get runSurfaceTabPlans => 'Planos';

  @override
  String get runSurfaceTabRaces => 'Corridas';

  @override
  String get gymSurfaceLabel => 'Seções da academia';

  @override
  String get gymTabLog => 'Registro';

  @override
  String get gymTabRecords => 'Recordes';

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
  String bodyMetricsPrefSaveFailed(String error) {
    return 'Não foi possível salvar: $error';
  }

  @override
  String get bodyMetricsLoadError =>
      'Não foi possível carregar os dados corporais.';

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
  String get safetyAddHint => 'parceiro@example.com';

  @override
  String get safetyPhoneLabel => 'Telefone para SMS (opcional)';

  @override
  String get safetyPhoneHint =>
      'Adicione um número de celular e este contato também poderá ser avisado por SMS — ele decide ao confirmar. Os avisos por e-mail são sempre enviados.';

  @override
  String get safetyInvalidPhone =>
      'Digite o telefone no formato internacional, ex.: +447700900123.';

  @override
  String get safetySmsBadge => 'SMS ativado';

  @override
  String get safetySmsPending => 'SMS desativado — ainda não aceitou';

  @override
  String get safetyConfirmSmsLabel => 'Avisar-me também por SMS';

  @override
  String get safetyContactOfTitle => 'Você é contato de segurança';

  @override
  String get safetyContactOfIntro =>
      'Estas pessoas indicaram você como contato de emergência e você confirmou. Dá para mudar como você é avisado, ou sair, quando quiser.';

  @override
  String safetyContactOfFor(String name) {
    return 'Contato de emergência de $name';
  }

  @override
  String get safetyContactOfSmsLabel => 'Avisar por SMS além do e-mail';

  @override
  String get safetyContactOfNoPhone =>
      'Os avisos por SMS precisam de um número de celular seu, e nenhum está cadastrado. Os avisos por e-mail são sempre enviados.';

  @override
  String get safetyContactOfSmsOnToast => 'Avisos por SMS ativados.';

  @override
  String get safetyContactOfSmsOffToast => 'Avisos por SMS desativados.';

  @override
  String get safetyContactOfSmsNoChange =>
      'Esse vínculo não está mais ativo — a pessoa pode tê-lo removido.';

  @override
  String safetyContactOfSmsFailed(String error) {
    return 'Não foi possível mudar sua preferência de SMS: $error';
  }

  @override
  String get safetyContactOfWithdraw => 'Sair';

  @override
  String get safetyContactOfWithdrawConfirm =>
      'Deixar de ser o contato de segurança desta pessoa? Ela não poderá mais avisar você e precisaria enviar um novo pedido.';

  @override
  String get safetyContactOfWithdrawnToast =>
      'Você não é mais contato de segurança.';

  @override
  String safetyContactOfWithdrawFailed(String error) {
    return 'Não foi possível sair: $error';
  }

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
  String safetyRemoveFailed(String error) {
    return 'Não foi possível remover o contato: $error';
  }

  @override
  String safetySettingSaveFailed(String error) {
    return 'Não foi possível salvar a configuração: $error';
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
  String get safetyOverdueTitle => 'Alerta de atraso';

  @override
  String get safetyOverdueIntro =>
      'Se uma corrida compartilhada ao vivo ficar em silêncio por mais tempo que isso, seus contatos confirmados recebem um e-mail com seu link ao vivo.';

  @override
  String get safetyOverdueLabel => 'Avisar após silêncio de';

  @override
  String get safetyOverdueOff => 'Desativado';

  @override
  String safetyOverdueMinutesOption(int minutes) {
    return '$minutes min';
  }

  @override
  String get safetyOverdueNote =>
      'Vale para qualquer corrida com compartilhamento ao vivo ativo. O silêncio também pode ser perda de sinal — o e-mail deixa isso claro. Os contatos recebem um único aviso por corrida; concluir envia a confirmação habitual.';

  @override
  String get safetyOverdueSaved => 'Alerta de atraso atualizado';

  @override
  String get safetyAutoLiveShareTitle => 'Compartilhamento ao vivo automático';

  @override
  String get safetyAutoLiveShareSubtitle =>
      'Inicia automaticamente o compartilhamento ao vivo quando uma corrida começa neste telefone. A corrida em andamento fica visível para qualquer pessoa com o link; quando a corrida termina, ela volta à sua visibilidade padrão.';

  @override
  String get safetyOffRouteTitle => 'Alerta de saída de rota';

  @override
  String get safetyOffRouteSubtitle =>
      'Avise um contato confirmado se você sair e continuar fora da rota planejada numa corrida compartilhada ao vivo.';

  @override
  String get runOffRouteAlertSent =>
      'Avisamos seu contato de segurança — você está fora da rota há um tempo.';

  @override
  String get runAutoLiveShareStarted =>
      'Ao vivo ativado — envie o link em “Compartilhar link ao vivo”';

  @override
  String get runSafetyNudgeSolo =>
      'Correndo sozinho(a) depois do escurecer? Compartilhe um link ao vivo para alguém acompanhar.';

  @override
  String get runSafetyNudgeShareAction => 'Compartilhar';

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
  String get authShowPassword => 'Mostrar senha';

  @override
  String get authHidePassword => 'Ocultar senha';

  @override
  String get authOrDivider => 'OU';

  @override
  String get authErrorOffline =>
      'Você parece estar offline. Verifique sua conexão e tente novamente.';

  @override
  String get authErrorInvalidCredentials =>
      'E-mail ou senha incorretos. Tente novamente.';

  @override
  String get authErrorRateLimited =>
      'Muitas tentativas. Aguarde um momento e tente novamente.';

  @override
  String get authErrorGeneric => 'Algo deu errado. Tente novamente.';

  @override
  String get authErrorNotSignedIn =>
      'Você precisa estar conectado para fazer isso. Entre e tente novamente.';

  @override
  String get authErrorEmailExists =>
      'Esse e-mail já tem uma conta. Entre em vez disso.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Confirme seu e-mail primeiro — procure o link de confirmação na sua caixa de entrada.';

  @override
  String authErrorWeakPassword(int minLength) {
    return 'Essa senha é muito fraca. Use pelo menos $minLength caracteres.';
  }

  @override
  String get authErrorInvalidEmail => 'Digite um endereço de e-mail válido.';

  @override
  String authErrorPasswordTooShort(int minLength) {
    return 'A senha deve ter pelo menos $minLength caracteres.';
  }

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
  String get signInResendConfirmation => 'Reenviar e-mail de confirmação';

  @override
  String get signInConfirmationResent =>
      'Se esse e-mail estiver registrado, enviamos um novo link de confirmação.';

  @override
  String get signInWithApple => 'Entrar com Apple';

  @override
  String get signInWithGoogle => 'Entrar com Google';

  @override
  String get googleSignInSoon =>
      'O login com o Google chega em breve. Por enquanto, use o e-mail.';

  @override
  String get appleSignInSoon =>
      'O login com a Apple chega em breve. Por enquanto, use o e-mail.';

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
  String get signUpAcceptConjunction => ' e a ';

  @override
  String get signUpErrorConfirmAge =>
      'Confirme que você tem 16 anos ou mais para continuar.';

  @override
  String get signUpErrorAcceptTerms =>
      'Aceite os Termos de Serviço e a Política de Privacidade para continuar.';

  @override
  String get signUpConfirmPasswordLabel => 'Confirme a senha';

  @override
  String signUpErrorPasswordTooShort(int min) {
    return 'A senha precisa ter pelo menos $min caracteres.';
  }

  @override
  String get signUpErrorPasswordMismatch => 'As senhas não coincidem.';

  @override
  String get signUpCheckEmailTitle => 'Verifique seu e-mail';

  @override
  String signUpCheckEmailBody(String email) {
    return 'Enviamos um link de confirmação para $email. Abra-o para concluir a criação da sua conta.';
  }

  @override
  String get signUpCheckEmailBack => 'Voltar para entrar';

  @override
  String get signUpContinueWithApple => 'Continuar com Apple';

  @override
  String get signUpContinueWithGoogle => 'Continuar com Google';

  @override
  String get signUpSignInPrompt => 'Já tem uma conta? Entre';

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
  String get setupCreatePlanCta => 'Criar meu plano de treino';

  @override
  String get setupWelcomeToast => 'Bem-vindo ao Threkir!';

  @override
  String setupSaveError(String message) {
    return 'Não foi possível salvar sua configuração: $message';
  }

  @override
  String setupPrefsSaveError(String message) {
    return 'Sua conta foi configurada, mas suas preferências não foram salvas: $message';
  }

  @override
  String get setupOfflineHint =>
      'Não foi possível conectar ao servidor agora. Você pode concluir a configuração mais tarde — tudo aqui pode ser editado em Configurações.';

  @override
  String get setupFinishLater => 'Concluir mais tarde';

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
  String get setupDoneHintGoal =>
      'É tudo. Crie um plano de treino para o seu objetivo ou abra o painel para começar a correr.';

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
  String get runLastRunOpenA11yLabel => 'Abrir os detalhes da última corrida';

  @override
  String get runChooseRoute => 'Escolher rota';

  @override
  String get runChangeRoute => 'Trocar rota';

  @override
  String get runShareLiveLink => 'Compartilhar link ao vivo';

  @override
  String get runLiveShareNeedsSignIn =>
      'Faça login para compartilhar um link de rastreamento ao vivo.';

  @override
  String get runLiveShareNotStarted =>
      'Não foi possível iniciar o rastreamento ao vivo — toque em Compartilhar para tentar novamente.';

  @override
  String get runLiveShareActive => 'Ao vivo';

  @override
  String get runLiveShareActiveSemantics =>
      'O compartilhamento ao vivo está ativo. Toque para compartilhar o link novamente ou parar de compartilhar.';

  @override
  String get runLiveShareSheetTitle => 'Compartilhamento ao vivo ativo';

  @override
  String get runLiveShareReshare => 'Compartilhar link novamente';

  @override
  String get runLiveShareStop => 'Parar de compartilhar';

  @override
  String get runLiveShareExpectedReturn => 'Sem voltar até…';

  @override
  String get runExpectedReturnTitle => 'Sem voltar até…';

  @override
  String get runExpectedReturnIntro =>
      'Escolha a que horas espera terminar. Se esta atividade ainda estiver em andamento, seus contatos de segurança confirmados recebem um aviso com seu link ao vivo.';

  @override
  String get runExpectedReturnServerNote =>
      'O prazo fica no servidor, então continua valendo mesmo se este celular parar. Ele é limpo quando a atividade é salva — uma atividade concluída sem sinal ainda pode avisar até sincronizar.';

  @override
  String runExpectedReturnOptionMinutes(int minutes) {
    return 'Em $minutes min';
  }

  @override
  String runExpectedReturnOptionHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Em $hours horas',
      one: 'Em 1 hora',
    );
    return '$_temp0';
  }

  @override
  String runExpectedReturnBy(String time) {
    return 'De volta às $time';
  }

  @override
  String runExpectedReturnActive(String time) {
    return 'Aviso definido para $time.';
  }

  @override
  String get runExpectedReturnClear => 'Limpar o aviso';

  @override
  String get runExpectedReturnSetToast => 'Aviso de horário de volta definido.';

  @override
  String get runExpectedReturnClearedToast =>
      'Aviso de horário de volta limpo.';

  @override
  String get runExpectedReturnFailed =>
      'Não foi possível atualizar o aviso de horário de volta.';

  @override
  String get runExpectedReturnUnavailable =>
      'Servidor inacessível — não é possível definir o aviso de horário de volta.';

  @override
  String get runLiveShareStopped => 'Compartilhamento ao vivo encerrado';

  @override
  String get runLiveShareEndedTitle => 'Compartilhamento ao vivo encerrado';

  @override
  String get runLiveShareEndedBody =>
      'O link ao vivo não é mais atualizado. Manter a corrida salva pública para que qualquer pessoa com o link possa vê-la? Caso contrário, ela segue sua visibilidade padrão.';

  @override
  String get runLiveShareKeepPublic => 'Manter pública';

  @override
  String get runLiveShareKeepPrivate => 'Manter privada';

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
  String get runStopA11yLabel => 'Parar e salvar corrida';

  @override
  String get runStopA11yHint => 'Encerra a gravação e salva a corrida';

  @override
  String get runHoldToStopHint => 'Segure para parar';

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
  String get runResumeDialogTitle => 'Retomar sua corrida?';

  @override
  String get runResumeDialogBody =>
      'Uma corrida de uma sessão anterior ainda está em andamento. Retome a gravação de onde parou, finalize-a agora ou descarte-a.';

  @override
  String get runResumeAction => 'Retomar';

  @override
  String get runResumeFinishAction => 'Finalizar agora';

  @override
  String get runResumedBanner => 'Corrida retomada.';

  @override
  String get runResumeSavedBanner => 'Corrida anterior salva.';

  @override
  String get runResumeDiscardedBanner => 'Corrida anterior descartada.';

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
  String get runTreadmillConnecting => 'Conectando à esteira…';

  @override
  String get runTreadmillNoBeltData =>
      'Sem dados da esteira — distância pelo GPS';

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
  String get runBackgroundLocationPaused =>
      'O rastreamento pausou enquanto você esteve fora — o tempo continuou correndo e nada foi perdido, mas a distância percorrida fora da tela não foi contada. Defina a Localização como \"Permitir o tempo todo\" para continuar rastreando em segundo plano.';

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
  String get historyUnsyncedRowSemantics => 'ainda não sincronizada';

  @override
  String get historyBlockedRowSemantics => 'não pode ser enviada';

  @override
  String get historyBlockedRowTooltip => 'Não pode ser enviada';

  @override
  String historyBlockedTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corridas não podem ser enviadas',
      one: '$count corrida não pode ser enviada',
    );
    return '$_temp0';
  }

  @override
  String historySyncBlocked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count corridas não podem ser enviadas e não serão tentadas novamente. Abra cada uma para escolher o que fazer.',
      one:
          '$count corrida não pode ser enviada e não será tentada novamente. Abra-a para escolher o que fazer.',
    );
    return '$_temp0';
  }

  @override
  String get runDetailBlockedDropTrack => 'Enviar sem o trajeto';

  @override
  String get runDetailBlockedExport => 'Exportar uma cópia';

  @override
  String get runDetailBlockedTitle => 'Esta corrida não pode ser enviada';

  @override
  String runDetailBlockedTrackTooLarge(int waypoints) {
    return 'Seu trajeto de GPS ($waypoints pontos) é maior do que o armazenamento na nuvem permite, então tentar de novo nunca vai funcionar. Todo o resto da corrida — distância, tempo, ritmo, ganho de elevação — ainda pode ser salvo.';
  }

  @override
  String get runDetailDropTrackBody =>
      'O trajeto é removido deste dispositivo e a corrida é enviada sem mapa. A distância, o tempo, o ritmo e o ganho de elevação não mudam. Exporte uma cópia antes se quiser guardá-lo.';

  @override
  String get runDetailDropTrackConfirm => 'Enviar sem ele';

  @override
  String get runDetailDropTrackDone =>
      'Trajeto removido. A corrida será sincronizada no próximo ciclo.';

  @override
  String get runDetailDropTrackFailed =>
      'Não foi possível remover o trajeto. Tente novamente.';

  @override
  String get runDetailDropTrackTitle => 'Enviar sem o trajeto de GPS?';

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
  String get durationFieldHours => 'Horas';

  @override
  String get durationFieldMinutes => 'Minutos';

  @override
  String get durationFieldSeconds => 'Segundos';

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
  String get runDetailIncompleteBadge => 'Incompleta';

  @override
  String get runDetailIncompleteTooltip =>
      'Seu relógio reiniciou no meio da corrida. Estes totais são apenas o que ele havia registrado até aquele ponto, não a atividade inteira.';

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
  String get runDetailEditFailed =>
      'Não foi possível salvar suas alterações. Tente novamente.';

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
  String get runDetailStatHrCoverage => 'Cobertura de FC';

  @override
  String runDetailHrCoveragePercent(int pct) {
    return '$pct%';
  }

  @override
  String runDetailHrCoverageOnly(int pct) {
    return '$pct% coberto';
  }

  @override
  String get runDetailStatAvgHr => 'FC média';

  @override
  String get runDetailStatAgeGrade => 'Índice por idade';

  @override
  String get runDetailStatGradeAdjPace => 'Ritmo ajustado';

  @override
  String get runDetailSectionElevation => 'Elevação';

  @override
  String get runDetailPaceLegendTitle => 'Ritmo x mediana';

  @override
  String get runDetailPaceBandFaster => 'Mais rápido';

  @override
  String get runDetailPaceBandSteady => 'Constante';

  @override
  String get runDetailPaceBandSlower => 'Mais lento';

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
  String get runDetailHrDisclaimer =>
      'As zonas usam uma FC máxima estimada pela idade. Se você toma medicação cardíaca (ex.: betabloqueadores) ou já mediu sua FC máxima, defina-a em Preferências para zonas precisas.';

  @override
  String get runDetailHrDisclaimerAction => 'Definir FC máx.';

  @override
  String get runDetailSectionSplits => 'Parciais';

  @override
  String get runDetailNoGpsForSplits => 'Sem dados de GPS para os parciais';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'Corrida curta demais para um parcial completo de $unit';
  }

  @override
  String get runDetailPacing => 'Ritmo por metades';

  @override
  String get runDetailPacingFirstHalf => 'Primeira metade';

  @override
  String get runDetailPacingSecondHalf => 'Segunda metade';

  @override
  String get runDetailPacingNegative => 'Split negativo';

  @override
  String get runDetailPacingEven => 'Ritmo constante';

  @override
  String get runDetailPacingPositive => 'Split positivo';

  @override
  String runDetailPacingFaster(String delta) {
    return '$delta mais rápido na segunda metade';
  }

  @override
  String runDetailPacingSlower(String delta) {
    return '$delta mais lento na segunda metade';
  }

  @override
  String get runDetailPacingHeld => 'Constante nas duas metades';

  @override
  String get runDetailPacingGapNegative =>
      'Ajustado pelo relevo, você acelerou na segunda metade.';

  @override
  String get runDetailPacingGapEven =>
      'Ajustado pelo relevo, seu esforço foi igual nas duas metades.';

  @override
  String get runDetailPacingGapPositive =>
      'Ajustado pelo relevo, você desacelerou na segunda metade.';

  @override
  String get runDetailGapColumn => 'Ajustado';

  @override
  String get runDetailGapColumnHint =>
      'O ritmo ajustado é o ritmo no plano que teria custado o mesmo esforço que as subidas que você realmente correu.';

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
  String get runDetailMakePrivate => 'Tornar privada';

  @override
  String get runDetailMakePrivateTitle => 'Tornar esta corrida privada?';

  @override
  String get runDetailMakePrivateBody =>
      'O link público de compartilhamento e a página de espectadores ao vivo deixarão de funcionar. Quem abrir um link antigo não verá mais esta corrida.';

  @override
  String runDetailMakePrivateFailed(String error) {
    return 'Não foi possível tornar a corrida privada: $error';
  }

  @override
  String get runDetailMadePrivate => 'A corrida agora é privada';

  @override
  String get runDetailDeleteTitle => 'Excluir corrida?';

  @override
  String get runDetailDeleteBody => 'Isso não pode ser desfeito.';

  @override
  String get runDetailDeleteQueued =>
      'Não foi possível excluir da nuvem; a corrida foi mantida por enquanto — será tentado novamente quando você estiver online.';

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
  String get publicRunLiveTitle => 'Ao vivo agora';

  @override
  String get publicRunLiveSub =>
      'Esta corrida ainda está em andamento. Acompanhe no rastreador ao vivo.';

  @override
  String get publicRunWatchLive => 'Assistir ao vivo';

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
  String routesImportedMany(int count) {
    return 'Importadas $count rotas';
  }

  @override
  String routesImportFailed(String error) {
    return 'Falha na importação: $error';
  }

  @override
  String get routesImportSharedFailed =>
      'Não foi possível importar o arquivo: não é uma rota válida.';

  @override
  String routesSaved(String name) {
    return '\"$name\" salva';
  }

  @override
  String get historySelectionHint =>
      'Toque e segure em uma corrida para selecionar várias';

  @override
  String get routesSelectionHint =>
      'Toque e segure em uma rota para selecionar várias';

  @override
  String get routesEmptyTitle => 'Nenhuma rota ainda';

  @override
  String get routesEmptyBody =>
      'Toque em Criar para desenhar uma rota no mapa ou importe um arquivo GPX, KML, KMZ, GeoJSON ou TCX.';

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
  String get routeBuilderSnapUnavailable =>
      'O ajuste às estradas está indisponível — os pinos ficam onde você toca, ligados por linhas retas.';

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
  String get routeBuilderPointList => 'Pontos da rota';

  @override
  String routeBuilderPointMovedTo(int from, int to) {
    return 'Ponto $from movido para a posição $to';
  }

  @override
  String routeBuilderPointRemoved(int number) {
    return 'Ponto $number removido';
  }

  @override
  String routeBuilderReorderPoint(int number) {
    return 'Reordenar o ponto $number';
  }

  @override
  String get routeBuilderPointStart => 'Início';

  @override
  String get routeBuilderPointEnd => 'Fim';

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
  String get routeDetailShareLink => 'Compartilhar link';

  @override
  String get routeDetailSendToWatch => 'Enviar para o relógio';

  @override
  String routeDetailWatchCourseSent(int points) {
    return 'Percurso enviado para o relógio ($points pontos)';
  }

  @override
  String routeDetailWatchCourseSimplified(int source, int points) {
    return 'Percurso enviado para o relógio — reduzido de $source para $points pontos para caber';
  }

  @override
  String get routeDetailWatchCourseTooShort =>
      'Esta rota tem pontos de menos para ser seguida no relógio';

  @override
  String get routeDetailWatchPushRejected =>
      'O relógio recusou o envio e manteve o que já tinha. Tente novamente.';

  @override
  String routeDetailWatchCourseFailed(String error) {
    return 'Não foi possível enviar o percurso para o relógio: $error';
  }

  @override
  String get routeDetailSendToAppleWatch => 'Enviar para o Apple Watch';

  @override
  String routeDetailAppleWatchRouteSent(int points) {
    return 'Rota enviada para o Apple Watch ($points pontos)';
  }

  @override
  String routeDetailAppleWatchRouteSimplified(int source, int points) {
    return 'Rota enviada para o Apple Watch — reduzida de $source para $points pontos para caber';
  }

  @override
  String get routeDetailAppleWatchRouteTooShort =>
      'Esta rota tem pontos de menos para ser seguida no Apple Watch';

  @override
  String routeDetailAppleWatchRouteFailed(String error) {
    return 'Não foi possível enviar a rota para o Apple Watch: $error';
  }

  @override
  String routeDetailWatchCourseAndScheduleSent(int points, int checkpoints) {
    return 'Percurso ($points pontos) e plano de corrida ($checkpoints pontos de controle) enviados para o relógio';
  }

  @override
  String routeDetailWatchScheduleThinned(
    int points,
    int source,
    int checkpoints,
  ) {
    return 'Percurso ($points pontos) enviado. Plano de corrida reduzido de $source para $checkpoints pontos de controle para caber no relógio';
  }

  @override
  String routeDetailWatchScheduleClockCutoffs(int checkpoints, int unresolved) {
    return 'Plano de corrida enviado ($checkpoints pontos de controle), mas $unresolved cortes por horário precisam de um horário de largada — defina um na folha da equipe para chegarem ao relógio';
  }

  @override
  String routeDetailWatchScheduleTooManyCutoffs(
    int points,
    int cutoffs,
    int max,
  ) {
    return 'Percurso ($points pontos) enviado, mas o plano de corrida tem $cutoffs cortes e o relógio suporta $max — remova alguns para enviá-lo';
  }

  @override
  String get routeDetailMadePublicForLink =>
      'Tornada pública para que qualquer pessoa com o link possa vê-la';

  @override
  String get routeDetailShareConfirmTitle => 'Tornar esta rota pública?';

  @override
  String get routeDetailShareConfirmBody =>
      'Compartilhar um link torna esta rota pública — qualquer pessoa com o link pode abri-la, e ela pode aparecer em Explorar. Você pode torná-la privada novamente quando quiser.';

  @override
  String get routeDetailShareConfirmCta => 'Tornar pública e compartilhar';

  @override
  String routeDetailShareLinkFailed(String error) {
    return 'Não foi possível compartilhar o link: $error';
  }

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
  String get routeDetailReportReview => 'Denunciar avaliação';

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
  String get routeDetailDescribeConsentRequired =>
      'As descrições por IA precisam do seu consentimento às informações de IA atualizadas.';

  @override
  String get routeDetailReviewDisclosure => 'Ver as informações';

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
  String get routeDetailDeleteReview => 'Excluir sua avaliação';

  @override
  String routeDetailReviewDeleteFailed(String error) {
    return 'Não foi possível excluir a avaliação: $error';
  }

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
  String get runHeatmapSignedOutTitle =>
      'Entre para ver seu mapa de calor sincronizado';

  @override
  String get runHeatmapSignedOutBody =>
      'As corridas gravadas neste dispositivo aparecem aqui. Entre para incluir também suas corridas sincronizadas.';

  @override
  String get runHeatmapErrorTitle =>
      'Não foi possível carregar seu mapa de calor';

  @override
  String get runHeatmapErrorBody =>
      'Algo deu errado ao carregar suas corridas. Verifique sua conexão e tente novamente.';

  @override
  String get runHeatmapRetry => 'Tentar novamente';

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
  String runNotificationPausedTitle(String activity) {
    return '$activity • pausado';
  }

  @override
  String get activityTypeRun => 'Corrida';

  @override
  String get activityTypeWalk => 'Caminhada';

  @override
  String get activityTypeHike => 'Trilha';

  @override
  String get activityTypeCycle => 'Ciclismo';

  @override
  String get activityTypeStroller => 'Carrinho';

  @override
  String get feedActivityAll => 'Tudo';

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
  String get profileSectionError => 'Não foi possível carregar esta seção.';

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
  String get profileNotifYourRun => 'corrida';

  @override
  String profileNotifNameAndOthers(String name, int count) {
    return '$name e mais $count';
  }

  @override
  String profileNotifAndOthers(int count) {
    return 'e mais $count';
  }

  @override
  String get profileNotifShowLess => 'Mostrar menos';

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
  String profileNotifPlanAssigned(String name) {
    return '$name atribuiu um plano de treino a você';
  }

  @override
  String profileNotifEventCancelTitled(String title) {
    return 'Uma ocorrência de \"$title\" foi cancelada';
  }

  @override
  String get profileNotifEventCancel =>
      'Uma ocorrência de evento que você confirmou foi cancelada';

  @override
  String profileNotifEventReminderTitled(String title) {
    return '\"$title\" está chegando';
  }

  @override
  String get profileNotifEventReminder =>
      'Um evento ao qual você vai comparecer está chegando';

  @override
  String get profileNotifAchievement => 'Você conquistou uma nova conquista';

  @override
  String get profileNotifChallengeComplete => 'Você completou um desafio';

  @override
  String get profileNotifContentHidden =>
      'Uma das suas publicações foi ocultada após ser denunciada';

  @override
  String get profileNotifDataExportReady =>
      'Sua exportação de dados está pronta para baixar';

  @override
  String get profileNotifRefundFailed =>
      'Um reembolso que iniciamos não pôde ser concluído. O dinheiro ainda está conosco e vamos combinar outra forma de devolver.';

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
  String get discoverSearchPlaceholder => 'Buscar aulas, clubes…';

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
  String get clubDetailReadMore => 'Ler mais';

  @override
  String get clubDetailReportClub => 'Denunciar clube';

  @override
  String get clubDetailReportPost => 'Denunciar esta publicação';

  @override
  String get clubDetailLoadFailedBody =>
      'Não foi possível carregar este clube. Pode ter sido removido, ou sua sessão precisa ser atualizada. Puxe para tentar novamente, ou saia e entre novamente em Configurações.';

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
  String get clubDetailDenyTitle => 'Recusar pedido de adesão';

  @override
  String get clubDetailDenyMessage =>
      'Recusar este pedido para entrar no clube? A pessoa não será adicionada.';

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
  String eventPhotosTitle(int count) {
    return 'Fotos ($count)';
  }

  @override
  String get eventAddPhoto => 'Adicionar foto';

  @override
  String get eventPhotoUploading => 'Enviando…';

  @override
  String get eventNoPhotosYet => 'Ainda não há fotos.';

  @override
  String get eventNoPhotosAddHint => 'Seja o primeiro a adicionar uma.';

  @override
  String get eventWhichRunPhoto => 'De qual corrida é esta foto?';

  @override
  String get eventNoRecentRuns =>
      'Nenhuma corrida recente encontrada. Registre uma corrida primeiro e volte.';

  @override
  String get eventPhotoRunnerFallback => 'Um corredor';

  @override
  String get eventPhotoUploadFailed => 'Não foi possível enviar a foto.';

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
  String get eventOccurrenceCancelled => 'Esta ocorrência foi cancelada.';

  @override
  String get eventRsvpWaitlisted => 'Na lista de espera';

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
  String get liveSpectatorStatRaceTime => 'Tempo de prova';

  @override
  String get liveSpectatorStatTimer => 'Cronômetro';

  @override
  String get liveSpectatorStatTimerStale => 'Cronômetro, último sinal';

  @override
  String get liveSpectatorRecentPace => 'Recente';

  @override
  String liveSpectatorCourseProgress(int p) {
    return '$p% do percurso';
  }

  @override
  String liveSpectatorMotionStopped(int n) {
    return 'Sem movimento — $n min no mesmo ponto';
  }

  @override
  String liveSpectatorMotionStoppedAtLeast(int n) {
    return 'Sem movimento — pelo menos $n min no mesmo ponto';
  }

  @override
  String get liveSpectatorConcludedTitle => 'Corrida concluída';

  @override
  String get liveSpectatorConcludedBody =>
      'Veja o percurso completo, as parciais e as estatísticas.';

  @override
  String get liveSpectatorViewFullRun => 'Ver a corrida completa';

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
  String get liveCutoffSignalLost =>
      'Sinal perdido — não é possível estimar a chegada';

  @override
  String get liveCutoffExpired => 'O tempo de corte já passou';

  @override
  String liveCutoffRequiredPace(String pace) {
    return 'Precisa de $pace a partir daqui';
  }

  @override
  String liveCutoffRequiredPaceStale(String pace) {
    return 'Precisa de $pace desde a última posição';
  }

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
  String get planNewNameRequiredHint =>
      'Adicione um nome de plano para ativar Criar.';

  @override
  String planNewDefaultName(String goal) {
    return 'Plano de $goal';
  }

  @override
  String planNewDefaultNameBeginner(String goal) {
    return 'Caminhada-corrida até $goal';
  }

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
  String planNewRaceAnchored(int weeks) {
    return 'Ajustado à sua corrida: um plano de $weeks semanas cuja última semana é a da prova. Altere o que quiser antes de criar.';
  }

  @override
  String get planNewRacePast =>
      'Essa corrida já aconteceu, então as datas abaixo são as padrão.';

  @override
  String get planNewRaceTooSoon =>
      'Essa corrida está próxima demais para montar um plano completo, então as datas abaixo são as padrão.';

  @override
  String get planNewRaceUnreadable =>
      'Não conseguimos ler a data dessa corrida, então as datas abaixo são as padrão.';

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
  String get planNewRampLabel => 'O plano em relação ao seu treino recente';

  @override
  String planNewRampUnder(String peak, String recent) {
    return 'Este plano chega no máximo a $peak por semana, abaixo dos $recent por semana que você correu em média nas últimas quatro semanas. Uma prova-alvo mais longa ou mais dias de treino aproveitariam melhor essa base.';
  }

  @override
  String planNewRampElevated(String opening, String recent) {
    return 'A semana 1 pede $opening contra os $recent por semana que você correu em média nas últimas quatro semanas — é um degrau real. Entre com calma ou tire um dia de treino.';
  }

  @override
  String planNewRampHigh(String opening, String recent) {
    return 'A semana 1 pede $opening, bem acima dos $recent por semana que você correu em média nas últimas quatro semanas. Menos dias de treino, uma prova-alvo mais curta ou algumas semanas de base antes deixariam esse primeiro passo mais seguro.';
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
  String get planNewTemplateCloneFailed =>
      'Não foi possível adotar esse modelo.';

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
  String get planNewStarterCreateFailed => 'Não foi possível criar esse plano.';

  @override
  String get planNewReplaceActiveTitle => 'Substituir seu plano ativo?';

  @override
  String planNewReplaceActiveNamed(String name) {
    return 'Você já tem um plano ativo: \"$name\". Criar um novo plano marcará o atual como concluído (você ainda poderá encontrá-lo em Gerenciar planos). Continuar?';
  }

  @override
  String get planNewReplaceActiveUnnamed =>
      'Você já tem um plano ativo. Criar um novo plano marcará o atual como concluído. Continuar?';

  @override
  String get planNewReplaceActiveConfirm => 'Substituir plano';

  @override
  String get planNewReplaceActiveKeep => 'Manter o atual';

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
  String get planDetailDuplicateConfirmTitle => 'Duplicar esta semana?';

  @override
  String planDetailDuplicateConfirmMessage(int n) {
    return 'Isso insere uma cópia da semana $n e empurra cada semana seguinte e a data da sua prova em 7 dias.';
  }

  @override
  String get planDetailDuplicateConfirm => 'Duplicar';

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
  String get coachTitle => 'Treinador IA';

  @override
  String get coachNewConversation => 'Nova conversa';

  @override
  String get coachConsentHeadline => 'Antes de usar os recursos de IA';

  @override
  String get coachConsentIntro =>
      'Os recursos de IA do Threkir — o Coach e o assistente de rotas com IA — enviam uma parte dos seus dados à Anthropic, nosso provedor de modelos de IA nos Estados Unidos. Dependendo do recurso que você usa, essa parte inclui:';

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
  String get coachConsentBulletRoutes =>
      'Para o assistente de rotas com IA: o nome e os dados da rota, o pedido que você digita e uma referência aproximada do lugar — nunca suas coordenadas exatas.';

  @override
  String get coachConsentProcessing =>
      'A Anthropic processa os dados em nome da Threkir conforme seus termos de processamento; por padrão, não treinam seus modelos com dados de clientes da Threkir. Todos os detalhes — incluindo o mecanismo de transferência, a retenção e seus direitos de retirada — estão na nossa política de privacidade.';

  @override
  String get coachConsentAction =>
      'Toque em \"Eu consinto\" para continuar. Toque em cancelar para sair da página sem enviar dados.';

  @override
  String get coachConsentCancel => 'Cancelar';

  @override
  String get coachConsentAccept => 'Eu consinto — ativar os recursos de IA';

  @override
  String get coachConsentSaving => 'Registrando consentimento…';

  @override
  String aiDisclosureRecordFailed(Object error) {
    return 'Não foi possível registrar o consentimento: $error';
  }

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
  String get coachArchiveTapToView => 'Toque para ver';

  @override
  String get coachArchiveActions => 'Ações da conversa';

  @override
  String get coachArchiveDelete => 'Excluir conversa';

  @override
  String get coachArchiveDeleteTitle => 'Excluir esta conversa?';

  @override
  String get coachArchiveDeleteBody =>
      'Esta conversa arquivada será excluída definitivamente.';

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
  String get coachSuggestNewFirstRun => 'Nunca corri antes — por onde começo?';

  @override
  String get coachSuggestNewFirstFeel =>
      'Como deve ser a sensação da minha primeira corrida?';

  @override
  String get coachSuggestNewHowOften =>
      'Com que frequência devo correr como iniciante?';

  @override
  String get coachSuggestNewWalkRun => 'Tudo bem caminhar durante as corridas?';

  @override
  String get coachEditMessageLabel => 'Edite sua mensagem';

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
  String get coachNewConversationFailed =>
      'Não foi possível iniciar uma nova conversa.';

  @override
  String get coachOpenArchiveFailed => 'Não foi possível abrir o arquivo.';

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'Não foi possível excluir o arquivo: $error';
  }

  @override
  String get coachReactionFailed =>
      'Não foi possível salvar sua reação. Tente novamente.';

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
  String get settingsAccountPasswordsMismatch => 'As senhas não coincidem';

  @override
  String get settingsAccountPasswordUpdated => 'Senha atualizada';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'Não foi possível atualizar a senha: $error';
  }

  @override
  String get settingsAccountCurrentPassword => 'Senha atual';

  @override
  String get settingsAccountPasswordStepUpHint =>
      'Para sua segurança, digite sua senha atual para alterá-la. Cadastrou-se com Google ou Apple? Envie um link de redefinição para você mesmo para definir uma.';

  @override
  String get settingsAccountCurrentPasswordRequired =>
      'Digite sua senha atual para alterá-la.';

  @override
  String get settingsAccountCurrentPasswordIncorrect =>
      'Essa senha atual está incorreta. Se você nunca definiu uma senha, envie um link de redefinição para você mesmo.';

  @override
  String get settingsAccountSendResetLink => 'Enviar link de redefinição';

  @override
  String get settingsAccountSendingResetLink => 'Enviando…';

  @override
  String get settingsAccountResetLinkSent =>
      'Link de redefinição enviado. Verifique seu e-mail para definir uma nova senha.';

  @override
  String get settingsAccountChangeEmail => 'Alterar e-mail';

  @override
  String get settingsAccountNewEmail => 'Novo e-mail';

  @override
  String get settingsAccountEmailChangeInvalid =>
      'Informe um endereço de e-mail válido e diferente do atual.';

  @override
  String settingsAccountEmailChangePending(Object old, Object newEmail) {
    return 'Confirmação pendente. Verifique tanto sua caixa de entrada antiga ($old) quanto a nova ($newEmail) e siga o link em cada uma para concluir a alteração. Seu e-mail só muda depois que você confirmar nas duas.';
  }

  @override
  String settingsAccountEmailChangeFailed(Object error) {
    return 'Não foi possível iniciar a alteração de e-mail: $error';
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
      'Retirar o consentimento para os recursos de IA';

  @override
  String get settingsAccountCoachConsentActive =>
      'Impeça os recursos de IA do Threkir de usarem seus dados. Você pode consentir novamente quando quiser.';

  @override
  String get settingsAccountCoachConsentWithdrawn =>
      'Consentimento para os recursos de IA retirado.';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return 'Falha ao retirar o consentimento: $error';
  }

  @override
  String get settingsAccountAiConsentUpdateTitle =>
      'Aceitar as informações de IA atualizadas';

  @override
  String get settingsAccountAiConsentUpdateSubtitle =>
      'As informações agora cobrem mais recursos. Leia-as e aceite-as para usar o assistente de rotas com IA.';

  @override
  String get settingsAccountAiConsentGrantTitle => 'Ver as informações de IA';

  @override
  String get settingsAccountAiConsentGrantSubtitle =>
      'Os recursos de IA do Threkir pedem seu consentimento antes de usar seus dados. Leia as informações e aceite-as aqui.';

  @override
  String get settingsAccountAiConsentAccepted => 'Informações de IA aceitas.';

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
  String settingsAccountBackupPartial(int count, int total) {
    return 'Exportação parcial — $count de $total corridas.';
  }

  @override
  String settingsAccountBackupPartialNotice(int count, int total) {
    return 'Sua última exportação está parcial: contém $count das $total corridas da sua conta. Nada foi excluído — exporte de novo para tentar outra vez. O arquivo completo da conta lista cada seção incompleta no manifest.json.';
  }

  @override
  String settingsAccountBackupTracksPartial(int missing, int total) {
    return 'Faltam $missing de $total arquivos GPS no backup.';
  }

  @override
  String settingsAccountBackupTracksPartialNotice(int missing, int total) {
    return 'Seu último backup não conseguiu baixar $missing de $total arquivos de trajeto GPS. Todas as corridas estão no arquivo; exporte de novo para recuperar os trajetos. O manifest.json dele indica complete: false.';
  }

  @override
  String settingsAccountRestoreIncompleteArchive(int runs) {
    return 'Esse arquivo se declarou incompleto. $runs corridas foram restauradas e nada foi sobrescrito — restaure a partir de um backup completo para preencher as lacunas.';
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
  String get settingsAccountAvatarRemoveTitle => 'Remover foto de perfil?';

  @override
  String get settingsAccountAvatarRemoveConfirm =>
      'Isso remove sua foto de perfil atual. Você pode enviar uma nova quando quiser.';

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
  String get guidedRunsTitle => 'Corridas guiadas';

  @override
  String get guidedRunsSubtitle =>
      'Treinos roteirizados com voz de treinador e avisos por TTS';

  @override
  String get privacyZonesTitle => 'Zonas de privacidade';

  @override
  String get privacyZonesSubtitle =>
      'Corta o início/fim de trajetos públicos perto de casa';

  @override
  String get settingsAccountSendErrorReports => 'Enviar relatórios de erro';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      'Dados anonimizados de falhas e erros para o Sentry (EUA). Desative para retirar o consentimento. Aplica-se na próxima inicialização.';

  @override
  String get settingsAccountDisplayName => 'Nome de exibição';

  @override
  String get settingsAccountDisplayNameHint =>
      'O nome que outros corredores veem. Deixe em branco para usar \"Runner\".';

  @override
  String get settingsAccountDisplayNameUnset =>
      'Não definido — você aparece como \"Runner\"';

  @override
  String get settingsAccountDisplayNameUpdated => 'Nome de exibição atualizado';

  @override
  String get settingsAccountDisplayNameUpdateFailed =>
      'Falha ao atualizar o nome de exibição. Tente novamente.';

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
  String get settingsAccountAccountExport => 'Exportação da conta';

  @override
  String get settingsAccountAccountExportSubtitle =>
      'Tudo o que há na sua conta — corridas, rotas, mensagens, pedidos, integrações, contatos de emergência. Criada no nosso servidor; você pode fechar o app enquanto isso.';

  @override
  String get settingsAccountExportQueued =>
      'Sua exportação está sendo criada. Você pode fechar o app — volte aqui para baixá-la.';

  @override
  String get settingsAccountExportBuildingNotice =>
      'A exportação da sua conta está sendo criada. Você pode fechar o app; ela continua sem você.';

  @override
  String get settingsAccountExportReadyNotice =>
      'A exportação da sua conta está pronta.';

  @override
  String get settingsAccountExportDownload => 'Baixar e compartilhar';

  @override
  String settingsAccountExportFailedNotice(String error) {
    return 'Sua última exportação da conta falhou ($error). Nada foi excluído — peça outra.';
  }

  @override
  String get settingsAccountExportStalledNotice =>
      'Sua última exportação da conta parou de responder. Nada foi excluído — peça outra.';

  @override
  String get settingsAccountExportExpiredNotice =>
      'Sua última exportação da conta expirou. As exportações são excluídas depois de 7 dias — peça outra.';

  @override
  String get settingsAccountExportStatusUnavailable =>
      'Não foi possível falar com o serviço de exportação para verificar o status. Ela pode ainda estar sendo criada.';

  @override
  String get settingsAccountExportUnavailable =>
      'O serviço de exportação da conta não está configurado nesta versão. O backup completo abaixo é criado neste dispositivo e não inclui os registros da sua conta.';

  @override
  String settingsAccountExportUnsyncedWarning(int count) {
    return '$count corridas ainda não foram sincronizadas. A exportação da conta é criada no servidor, então não vai incluí-las — use o backup completo para guardá-las.';
  }

  @override
  String get settingsAccountBackupOnDeviceNotice =>
      'Seu último backup completo foi criado neste dispositivo. Ele contém suas corridas, rotas, perfil, preferências e registros de academia e alimentação — mas não os registros da sua conta. Use a exportação da conta para a cópia completa.';

  @override
  String settingsAccountExportRateLimited(int seconds) {
    return 'Limite de exportações atingido — tente de novo em $seconds segundos.';
  }

  @override
  String settingsAccountExportRequestFailed(String error) {
    return 'Não foi possível solicitar sua exportação: $error';
  }

  @override
  String settingsAccountExportDownloadFailed(String error) {
    return 'Não foi possível baixar sua exportação: $error';
  }

  @override
  String settingsAccountExportReadyBanner(int count) {
    return 'A exportação da sua conta está pronta — $count corridas.';
  }

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
  String integrationsSyncPartial(int imported, int skipped) {
    return 'A sincronização parou antes do fim. $imported novas, $skipped já presentes — algumas atividades não foram baixadas. Sincronize de novo para concluir.';
  }

  @override
  String integrationsSyncPartialRateLimited(int imported, int skipped) {
    return 'O Strava está limitando as solicitações, então a sincronização parou antes do fim. $imported novas, $skipped já presentes. Tente de novo em cerca de 15 minutos.';
  }

  @override
  String integrationsSyncResultWithFailed(
    int imported,
    int skipped,
    int failed,
  ) {
    return 'Sincronizado. $imported novas, $skipped já presentes, $failed com falha.';
  }

  @override
  String integrationsStravaConnectedPartial(int imported, int skipped) {
    return 'Strava conectado, mas a primeira importação parou antes do fim. $imported importadas, $skipped já presentes — sincronize de novo para concluir.';
  }

  @override
  String integrationsStravaConnectedPartialRateLimited(
    int imported,
    int skipped,
  ) {
    return 'Strava conectado, mas o Strava está limitando as solicitações, então a primeira importação parou antes do fim. $imported importadas, $skipped já presentes. Sincronize de novo em cerca de 15 minutos.';
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
  String integrationsImportPartialOf(int n, int total) {
    return 'Só foi possível importar parte do seu histórico: $n de $total.';
  }

  @override
  String integrationsImportPartial(int n) {
    return 'Não foi possível ler todos os resultados. Importados: $n.';
  }

  @override
  String get integrationsImportTruncated =>
      'A lista de resultados era longa demais para ser lida até o fim, então não foi possível confirmar seu resultado. Digite-o manualmente.';

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
  String get integrationsStravaSyncHistory =>
      'Sincronizar histórico mais antigo…';

  @override
  String get integrationsStravaLookbackTitle => 'Até quando sincronizar';

  @override
  String get integrationsStravaLookback90 => 'Últimos 90 dias';

  @override
  String get integrationsStravaLookback180 => 'Últimos 6 meses';

  @override
  String get integrationsStravaLookback365 => 'Último ano';

  @override
  String get integrationsSyncPartialNoteResumable =>
      'A última sincronização parou antes do fim do período. Sincronizar de novo continua de onde parou.';

  @override
  String get integrationsSyncPartialNote =>
      'A última sincronização parou antes do fim do período e não registrou nenhum ponto de retomada. Sincronize de novo para tentar outra vez.';

  @override
  String get integrationsSyncNow => 'Sincronizar agora';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle =>
      'Importar resultados pelo número de atleta';

  @override
  String get integrationsParkrunRegionNote =>
      'O parkrun está presente apenas em alguns países e pode não haver eventos perto de você — ainda assim, você pode importar resultados com um número de atleta do parkrun.';

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
  String get proComingSoonTitle => 'Pro — em breve';

  @override
  String get proComingSoon =>
      'O Pro desbloqueia o Coach de IA — em breve. Você ainda pode apoiar o app abaixo.';

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
  String get aboutTitle => 'Sobre e atualizações';

  @override
  String get aboutVersion => 'Versão';

  @override
  String get licensesOpenSource => 'Licenças de código aberto';

  @override
  String get licensesOpenSourceSubtitle =>
      'Pacotes de terceiros incluídos neste app';

  @override
  String get aboutCheckForUpdates => 'Verificar atualizações';

  @override
  String get aboutCheckingUpdate => 'Procurando atualizações…';

  @override
  String get aboutUpdateAvailable => 'Atualização disponível';

  @override
  String get aboutUpdateAvailableSubtitle =>
      'Há uma versão mais recente pronta para instalar.';

  @override
  String get aboutUpdate => 'Atualizar';

  @override
  String get aboutUpToDate => 'Você está na versão mais recente';

  @override
  String get aboutUpdateUnavailable =>
      'Esta versão é atualizada pela loja onde você a instalou.';

  @override
  String get aboutUpdateFailed =>
      'Não foi possível iniciar a atualização. Tente novamente na Play Store.';

  @override
  String get legalPrivacy => 'Política de Privacidade';

  @override
  String get legalTerms => 'Termos de Serviço';

  @override
  String get legalCookieNotice => 'Aviso de cookies';

  @override
  String get legalHealthDataNotice => 'Privacidade dos dados de saúde';

  @override
  String get mapAttributionSemantics => 'Atribuição dos dados do mapa';

  @override
  String mapAttributionProvider(String name) {
    return '© $name';
  }

  @override
  String mapAttributionOsmContributors(String name) {
    return '© colaboradores do $name';
  }

  @override
  String legalCouldNotOpen(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String get aboutLegalSection => 'Jurídico';

  @override
  String get devicesTitle => 'Dispositivos conectados';

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
  String gearRotationNextUp(String name) {
    return 'Próximo: $name';
  }

  @override
  String get gearRotationNextUpWhy => 'O menos desgastado deste rodízio.';

  @override
  String get gearRotationMakeCurrent => 'Definir como atual';

  @override
  String gearRotationMakeCurrentLabel(String name) {
    return 'Definir $name como o par atual — as novas corridas serão marcadas automaticamente com ele';
  }

  @override
  String get gearRotationNextUpIsCurrent => 'Já é o par atual.';

  @override
  String get gearRotationAllWorn =>
      'Todos os pares aqui atingiram ou ultrapassaram a meta de substituição.';

  @override
  String gearRotationMakeCurrentFailed(Object error) {
    return 'Não foi possível alterar o par atual: $error';
  }

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
  String get privacyZonesDiscardBody =>
      'Você tem zonas de privacidade não salvas. Sair sem salvar?';

  @override
  String get discardChangesTitle => 'Descartar alterações?';

  @override
  String get discardChangesBody =>
      'Você tem alterações não salvas. Sair sem salvar?';

  @override
  String get discardChangesCancel => 'Cancelar';

  @override
  String get discardChangesDiscard => 'Descartar';

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
  String prefsSplitIntervalDefaultSubtitle(String run, String cycle) {
    return 'Padrão ($run ao correr, $cycle ao pedalar)';
  }

  @override
  String get prefsSplitPaceMode => 'Anúncio de parciais';

  @override
  String get prefsSplitPaceModeSubtitle => 'Que ritmo cada parcial anuncia';

  @override
  String get prefsSplitPaceModeSplit => 'Ritmo do parcial';

  @override
  String get prefsSplitPaceModeAverage => 'Ritmo médio';

  @override
  String get prefsSplitPaceModeBoth => 'Ambos';

  @override
  String get prefsSplitPaceModeInfo =>
      'Em cada parcial, escolha que ritmo você ouve: o ritmo só desse parcial, o seu ritmo médio da corrida toda até agora, ou ambos. Útil para manter um esforço constante. Exemplo: “1 quilômetro. Ritmo médio, 5 minutos e 45 segundos por quilômetro.”';

  @override
  String get prefsTargetPace => 'Ritmo alvo';

  @override
  String get prefsTargetPaceInfo =>
      'O ritmo que você quer manter. Sozinho, ele fica em silêncio — ative o aviso de voz “Alertas de desvio de ritmo” para ouvir “acelere” ou “diminua” quando você se desviar mais de 30 segundos. Exemplo: “Acelere 8 segundos.”';

  @override
  String get prefsCueInfoTooltip => 'O que é isto?';

  @override
  String get prefsLivePaceAlert => 'Ritmo alvo';

  @override
  String get prefsLivePaceAlertMin => 'min';

  @override
  String get prefsLivePaceAlertSec => 's';

  @override
  String get prefsLivePaceAlertOff =>
      'Não definido — defina um alvo e ative os alertas de desvio de ritmo';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — os alertas de desvio de ritmo falam ao desviar 30 s ou mais';
  }

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
  String get prefsEmailReOptInFailed =>
      'Não foi possível cancelar seu descadastramento anterior. Os e-mails podem continuar bloqueados; tente novamente.';

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
  String get prefsAudioCuesSubtitle =>
      'Anuncia parciais, ritmo e outros avisos enquanto você corre';

  @override
  String get prefsMinimalVoiceCues => 'Avisos de voz mínimos';

  @override
  String get prefsMinimalVoiceCuesSubtitle =>
      'Pula os avisos tagarelas de meio de repetição e desvio de ritmo';

  @override
  String get prefsKeepScreenOn => 'Manter a tela ligada';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'Mantém a tela ligada durante toda a corrida. Consome bem mais bateria em treinos longos.';

  @override
  String get prefsDimScreenWhileRecording => 'Escurecer a tela ao gravar';

  @override
  String get prefsDimScreenWhileRecordingSubtitle =>
      'Escurece o mapa durante a corrida para poupar bateria. As estatísticas continuam legíveis.';

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
  String get prefsShowCalories => 'Mostrar estimativas de calorias';

  @override
  String get prefsShowCaloriesHint =>
      'Estimadas a partir da distância e do peso corporal (padrão de 70 kg quando não definido). Desative para ocultar as calorias nas páginas de corrida.';

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
  String get dashboardProfileTooltip => 'Seu perfil';

  @override
  String get dashboardWelcomeTitle => 'Bem-vindo!';

  @override
  String get dashboardWelcomeBody =>
      'Seu painel é preenchido assim que você registra uma corrida, define uma meta ou importa seu histórico.';

  @override
  String get dashboardStartRun => 'Iniciar uma corrida';

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
  String dashboardPbAgeGrade(String percent) {
    return '$percent classificação por idade';
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
  String get dashboardHeatmapTitle => 'Atividade';

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
  String get mileageTitle => 'Quilometragem';

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
  String get runSocialReportComment => 'Denunciar comentário';

  @override
  String get runSocialReportReply => 'Denunciar resposta';

  @override
  String get runSocialPost => 'Publicar';

  @override
  String get runSocialCancel => 'Cancelar';

  @override
  String get kudosGiveLabel => 'Dar kudos';

  @override
  String get kudosRemoveLabel => 'Remover kudos';

  @override
  String get kudosViewCommentsLabel => 'Ver comentários';

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
  String get runPhotosPermissionDenied =>
      'É necessário acesso às fotos para adicionar uma foto. Você pode permitir nas Configurações.';

  @override
  String get runPhotosOpenSettings => 'Abrir configurações';

  @override
  String get runPhotosPickerFailed =>
      'Não foi possível abrir o seletor de fotos. Tente novamente.';

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
  String get runSegEffortsRankUnknown => 'Classificação indisponível';

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
  String get workoutReviewAdherenceCompleted => 'Concluído';

  @override
  String get workoutReviewAdherencePartial => 'Parcial';

  @override
  String get workoutReviewAdherenceAbandoned => 'Abandonado';

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
  String get segmentsPanelLoadError => 'Não foi possível carregar os segmentos';

  @override
  String get segmentsPanelLeaderboardError =>
      'Não foi possível carregar o ranking';

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
  String get segmentsPanelErrNameRequired => 'Insira um nome de segmento';

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
  String get clubFormErrName => 'Dê um nome ao clube.';

  @override
  String get clubFormErrSlug =>
      'O nome precisa de pelo menos uma letra ou dígito.';

  @override
  String get eventFormErrTitle => 'Dê um título ao evento.';

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
  String get reportTitleComment => 'Denunciar comentário';

  @override
  String get reportTitlePost => 'Denunciar publicação';

  @override
  String get reportTitleRun => 'Denunciar corrida';

  @override
  String get reportTitleReview => 'Denunciar avaliação';

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
  String get runGearChipsLoadFailed =>
      'Não foi possível carregar o equipamento.';

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
  String ttsSplitAverage(String count, String unit, String tail) {
    return '$count $unit. Média $tail';
  }

  @override
  String ttsSplitBoth(String count, String unit, String tail, String avgTail) {
    return '$count $unit. $tail. Média $avgTail';
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
  String get planPhaseGraduation => 'Semana de conclusão';

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
      'Entre para ver onde você está conectado';

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
  String get settingsTabAccountSubtitle =>
      'Login, perfil, importação e backup, excluir conta';

  @override
  String get settingsTabPreferencesSubtitle =>
      'Unidades, tema, gravação, treino, privacidade';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava, parkrun, calendário de corridas, cinta cardíaca, esteira, relógio';

  @override
  String get settingsTabDevicesSubtitle =>
      'Onde você está conectado e as substituições por dispositivo — pareie cinta ou esteira em Integrações';

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
  String get settingsTabAboutSubtitle =>
      'Versão, atualizações e documentos legais';

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
  String gymDeleteFailed(Object error) {
    return 'Não foi possível excluir o treino: $error';
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
  String get gymDistance => 'Distância (m)';

  @override
  String gymDistanceValue(String metres) {
    return '$metres m';
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
  String get clubEventAddToCalendar => 'Adicionar ao calendário';

  @override
  String get clubEventAddOccurrenceToCalendar => 'Adicionar esta ocorrência';

  @override
  String get clubEventAddSeriesToCalendar => 'Adicionar toda a série';

  @override
  String get clubEventCalendarUnavailable =>
      'Não foi possível abrir seu aplicativo de calendário.';

  @override
  String clubEventCalendarCancelledNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Seu calendário não consegue pular datas canceladas: $count ocorrências canceladas ainda vão aparecer.',
      one:
          'Seu calendário não consegue pular datas canceladas: 1 ocorrência cancelada ainda vai aparecer.',
    );
    return '$_temp0';
  }

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
  String gymCatalogueOtherCategory(String name, String category) {
    return '“$name” já está no catálogo, em $category.';
  }

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
  String get gymRoutineHistoryTitle => 'Histórico da rotina';

  @override
  String get gymRoutineHistoryRecent => 'Sessões recentes';

  @override
  String gymRoutineHistoryLastDone(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Feita há $days dias',
      one: 'Feita ontem',
      zero: 'Feita hoje',
    );
    return '$_temp0';
  }

  @override
  String gymRoutineHistoryCompletedRate(int completed, int graded) {
    return '$completed de $graded concluídas';
  }

  @override
  String get gymRoutineHistoryVerdictUngraded => 'Sem avaliação';

  @override
  String get gymRoutineHistoryLoadError =>
      'Não foi possível carregar o histórico desta rotina.';

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
  String get gymRoutineNextTargetEstablishBaseline =>
      'Estabelecer base — defina o peso inicial';

  @override
  String get gymRoutineNextTargetDeload => 'Deload — reduzir a carga';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return 'subida de reps $from→$to';
  }

  @override
  String get nutritionTitle => 'Nutrição';

  @override
  String get nutritionDayNavLabel => 'Dia do diário';

  @override
  String get nutritionDayPrevious => 'Dia anterior';

  @override
  String get nutritionDayNext => 'Próximo dia';

  @override
  String get nutritionDayToday => 'Hoje';

  @override
  String get nutritionDayYesterday => 'Ontem';

  @override
  String get nutritionDayBackfillHint =>
      'Tudo o que você registrar aqui é adicionado a este dia.';

  @override
  String get nutritionDayEmptyPast => 'Nada registrado neste dia.';

  @override
  String nutritionDayGoalBreakdown(int base, int exercise) {
    return 'Meta $base + $exercise kcal queimadas nesse dia';
  }

  @override
  String nutritionDayTrendEnding(String date) {
    return '7 dias até $date';
  }

  @override
  String nutritionDayLogHeadingFor(String date) {
    return 'Registrar comida — $date';
  }

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
  String get nutritionFiber => 'Fibra';

  @override
  String get nutritionSugar => 'Açúcar';

  @override
  String get nutritionSodium => 'Sódio';

  @override
  String get nutritionSaturatedFat => 'Gorduras saturadas';

  @override
  String get nutritionCholesterol => 'Colesterol';

  @override
  String get nutritionNutrients => 'Nutrientes';

  @override
  String get nutritionNutrientsHint =>
      'Valores de referência. Cada total conta apenas os alimentos registrados que informam esse nutriente.';

  @override
  String get nutritionNutrientAtLeast => 'pelo menos';

  @override
  String nutritionNutrientPartial(int reported, int total, String nutrient) {
    return '$reported de $total alimentos registrados informam $nutrient';
  }

  @override
  String nutritionNutrientOver(String n, String unit) {
    return '$n $unit acima';
  }

  @override
  String nutritionNutrientLeft(String n, String unit) {
    return '$n $unit restantes';
  }

  @override
  String get nutritionNutrientReached => 'Meta atingida';

  @override
  String get nutritionNutrientUntargeted => 'Sem meta diária';

  @override
  String get nutritionWater => 'Água';

  @override
  String get nutritionWaterAdd => 'Adicionar água';

  @override
  String get nutritionWaterRemove => 'Remover água';

  @override
  String get nutritionNoTargets =>
      'Informe sua altura, peso, idade e sexo para ver as metas de calorias e macros.';

  @override
  String get nutritionAddBodyMetrics => 'Adicionar dados corporais';

  @override
  String get nutritionTargetsLink => 'Metas';

  @override
  String get nutritionTargetsTitle => 'Metas de calorias e macros';

  @override
  String get nutritionTargetsSubtitle =>
      'Como a meta de hoje é calculada e os dois ajustes que a definem.';

  @override
  String get nutritionTargetsTotal => 'Meta de hoje';

  @override
  String get nutritionTargetsBmr => 'Metabolismo em repouso';

  @override
  String get nutritionTargetsBase => 'Meta base';

  @override
  String nutritionTargetsBaseFloored(int n) {
    return 'Mantida no piso de $n kcal — a menor meta diária que recomendamos.';
  }

  @override
  String get nutritionTargetsExercise => 'Treinos de hoje';

  @override
  String get nutritionTargetsExerciseHint =>
      'As corridas e sessões de musculação que você registrar hoje são somadas por cima.';

  @override
  String get nutritionTargetsMacrosHeading => 'Macros';

  @override
  String nutritionTargetsProteinHint(String n) {
    return '$n g por kg de peso corporal';
  }

  @override
  String get nutritionTargetsCarbsHint => 'O que sobra — seu combustível';

  @override
  String nutritionTargetsFatHint(int n) {
    return '$n% das calorias';
  }

  @override
  String get nutritionTargetsDefaultsHeading => 'Seus valores padrão';

  @override
  String get nutritionTargetsDefaultsHint =>
      'O nível de atividade é o seu dia típico sem contar os treinos — as corridas e sessões de musculação registradas são somadas à parte. Ambos são salvos quando você os altera.';

  @override
  String get nutritionTargetsMetricsHeading => 'Dados corporais';

  @override
  String get nutritionTargetsMetricsHint =>
      'Altura, peso, data de nascimento e sexo são dados de saúde, por isso são editados nas Configurações atrás do consentimento.';

  @override
  String get nutritionTargetsEditMetrics => 'Editar nas Configurações';

  @override
  String get nutritionTargetsUnset => 'Não informado';

  @override
  String get nutritionTargetsEmptyTitle => 'Ainda sem metas';

  @override
  String get nutritionTargetsEmptyBody =>
      'Informe sua altura, peso, data de nascimento e sexo e suas metas de calorias e macros aparecerão aqui.';

  @override
  String get nutritionTargetsAge => 'Idade';

  @override
  String nutritionTargetsAgeYears(int n) {
    return '$n anos';
  }

  @override
  String get nutritionTargetsAgeConsentWithheld =>
      'Requer consentimento de dados de saúde';

  @override
  String get nutritionTargetsLoadError =>
      'Não foi possível carregar suas metas.';

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
  String nutritionWeekProtein(int met, int total) {
    return 'Proteína $met/$total dias';
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
  String nutritionDeleteFailed(String error) {
    return 'Não foi possível excluir a entrada: $error';
  }

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
  String nutritionTemplateDeleteFailed(String error) {
    return 'Não foi possível excluir o modelo: $error';
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
  String nutritionRecipeDeleteFailed(String error) {
    return 'Não foi possível excluir a receita: $error';
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
  String get gymSessionLeaveSaveFailed =>
      'Não foi possível salvar seu rascunho — você ainda está aqui, então nada foi perdido. Tente novamente ou descarte a sessão de propósito.';

  @override
  String get gymSessionLeaveTitle => 'Sair da sessão?';

  @override
  String get gymSessionLeaveBody =>
      'Suas séries registradas ficam salvas como rascunho — você pode retomar a sessão na aba Academia ou descartá-la.';

  @override
  String get gymSessionLeaveDraft => 'Sair e manter o rascunho';

  @override
  String get gymSessionKeepGoing => 'Continuar treinando';

  @override
  String get gymDraftTitle => 'Sessão em andamento';

  @override
  String gymDraftSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count séries registradas',
      one: '1 série registrada',
    );
    return '$_temp0';
  }

  @override
  String get gymDraftResume => 'Retomar';

  @override
  String get gymDraftSave => 'Salvar como está';

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
  String get coachingTitle => 'Atletas e treinadores';

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
  String get routeMarkerCutoffInvalid =>
      'Informe o horário de corte como HH:MM (24 horas)';

  @override
  String get routeMarkerTimeClock => 'Relógio';

  @override
  String get routeMarkerTimeElapsed => 'Decorrido';

  @override
  String get routeMarkerNoteLabel => 'Nota';

  @override
  String get routeMarkerTapToPlace =>
      'Toque no mapa para posicionar este marcador.';

  @override
  String get routeMarkerSnapToggle => 'Ajustar à linha do percurso';

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
  String get routeMarkerLatLabel => 'Latitude';

  @override
  String get routeMarkerLngLabel => 'Longitude';

  @override
  String get routeMarkerCoordInvalid =>
      'Insira uma latitude válida (-90 a 90) e uma longitude válida (-180 a 180).';

  @override
  String get routeMarkerEnterCoords => 'Inserir localização';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'Não foi possível salvar o marcador: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'Não foi possível excluir o marcador: $error';
  }

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
  String get roadbookPlanTitle => 'Plano de prova';

  @override
  String get roadbookPlanExplain =>
      'O relógio calcula com isso os horários de chegada e os cortes. Defina um horário de largada para enviar também os cortes indicados como hora do dia.';

  @override
  String get roadbookPlanCancel => 'Cancelar';

  @override
  String get roadbookPlanSend => 'Enviar';

  @override
  String get roadbookPlanGoalInvalid => 'Digite um tempo alvo como 4:30:00';

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
  String get roadbookColTarget => 'Meta';

  @override
  String get roadbookColLegPace => 'Ritmo do trecho';

  @override
  String get roadbookTargetAhead => 'adiantado';

  @override
  String get roadbookTargetOn => 'no plano';

  @override
  String get roadbookTargetBehind => 'atrasado';

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
  String get checkpointWeighInBodyWeight => 'Peso corporal';

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
  String get challengesPaceAhead => 'Adiantado no ritmo';

  @override
  String get challengesPaceOnTrack => 'No ritmo para concluir';

  @override
  String get challengesPaceBehind => 'Atrasado no ritmo';

  @override
  String challengesPaceNeedPerDay(String rate) {
    return '$rate por dia para concluir';
  }

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
  String get challengesStandingTitle => 'Sua posição';

  @override
  String get challengesStandingTitleTeam => 'Posição da sua equipe';

  @override
  String challengesStandingRank(int rank, int total) {
    return '#$rank de $total';
  }

  @override
  String get challengesStandingTiedOne => 'Empatado com mais 1';

  @override
  String challengesStandingTiedMany(int n) {
    return 'Empatado com mais $n';
  }

  @override
  String challengesStandingBehind(String gap, String name) {
    return '$gap atrás de $name';
  }

  @override
  String challengesStandingAhead(String gap, String name) {
    return '$gap à frente de $name';
  }

  @override
  String get challengesStandingLeading => 'Na liderança';

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
  String get challengesDeleteFailed => 'Não foi possível excluir o desafio.';

  @override
  String get challengesLoadFailed => 'Não foi possível carregar os desafios.';

  @override
  String get challengesProgressUnavailable =>
      'Progresso indisponível — abra para ver seu resultado';

  @override
  String get challengesTeamNoClub => 'Sem clube';

  @override
  String get challengesTeamPrivateClub => 'Clube privado';

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
  String racesDistanceAway(String distance) {
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
  String get racesTrainForThis => 'Treinar para esta corrida';

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
  String get racesRunSignUpBibHint =>
      'Insira seu número de peito para importarmos apenas o seu resultado, não a lista inteira.';

  @override
  String get racesUltraSignUpAthleteId => 'ID de atleta do UltraSignup';

  @override
  String get racesUltraSignUpAthleteHint =>
      'Insira seu ID de atleta do UltraSignup ou deixe em branco para usar o desta corrida.';

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
  String get integrationsUltrasignup => 'UltraSignup';

  @override
  String get integrationsUltrasignupConnect =>
      'Importe resultados de trail e ultra do UltraSignup.';

  @override
  String get integrationsUltrasignupOpen => 'Abrir o calendário de corridas';

  @override
  String get integrationsUltrasignupUnavailable =>
      'A importação do UltraSignup ainda não está disponível. O parkrun e a colagem manual continuam funcionando.';

  @override
  String get integrationsChronotrack => 'ChronoTrack';

  @override
  String get integrationsChronotrackConnect =>
      'Importe resultados de corridas de eventos cronometrados pelo ChronoTrack.';

  @override
  String get integrationsChronotrackOpen => 'Abrir o calendário de corridas';

  @override
  String get integrationsChronotrackUnavailable =>
      'A importação do ChronoTrack ainda não está disponível. O parkrun e a colagem manual continuam funcionando.';

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

  @override
  String get settingsSectionDeveloper => 'Desenvolvedor';

  @override
  String get settingsTabSimWatchSubtitle =>
      'Status ao vivo do relógio personalizado simulado';

  @override
  String get simWatchTitle => 'Conexão do relógio simulado';

  @override
  String get simWatchHostLabel => 'Host';

  @override
  String get simWatchPortLabel => 'Porta';

  @override
  String get simWatchConnect => 'Conectar';

  @override
  String get simWatchConnecting => 'Conectando…';

  @override
  String get simWatchDisconnect => 'Desconectar';

  @override
  String simWatchConnectionFailed(String error) {
    return 'Falha na conexão: $error';
  }

  @override
  String get simWatchSyncAction => 'Sincronizar corridas do relógio';

  @override
  String simWatchSyncing(int done, int total) {
    return 'Sincronizando… $done/$total';
  }

  @override
  String simWatchResult(int synced, int total) {
    return '$synced de $total corrida(s) sincronizada(s) do relógio';
  }

  @override
  String simWatchSyncFailed(String error) {
    return 'Falha na sincronização do relógio: $error';
  }

  @override
  String get simWatchPushSettingsAction =>
      'Enviar configurações para o relógio';

  @override
  String get simWatchSettingsPushed => 'Configurações enviadas para o relógio';

  @override
  String simWatchPushSettingsFailed(String error) {
    return 'Falha ao enviar configurações: $error';
  }

  @override
  String get simWatchPushWorkoutAction => 'Enviar treino para o relógio';

  @override
  String simWatchWorkoutPushed(int steps) {
    return 'Treino enviado para o relógio ($steps etapas)';
  }

  @override
  String simWatchPushWorkoutFailed(String error) {
    return 'Falha ao enviar treino: $error';
  }

  @override
  String get simWatchPushRoadbookAction =>
      'Enviar plano de corrida para o relógio';

  @override
  String simWatchRoadbookPushed(int checkpoints, int cutoffs) {
    return 'Plano de corrida enviado para o relógio ($checkpoints pontos de controle, $cutoffs cortes)';
  }

  @override
  String simWatchPushRoadbookFailed(String error) {
    return 'Falha ao enviar o plano de corrida: $error';
  }

  @override
  String get simWatchPushCourseAction => 'Enviar percurso para o relógio';

  @override
  String simWatchCoursePushed(int points) {
    return 'Percurso enviado para o relógio ($points pontos)';
  }

  @override
  String simWatchPushCourseFailed(String error) {
    return 'Falha ao enviar percurso: $error';
  }

  @override
  String get simWatchNoRuns => 'Nenhuma corrida no relógio para sincronizar';

  @override
  String get simWatchWaitingFrames => 'Conectado — aguardando quadros…';

  @override
  String get simWatchUptime => 'Tempo de atividade do relógio';

  @override
  String get simWatchNoFix => 'Ainda sem sinal de GPS';

  @override
  String get simWatchPosition => 'Posição';

  @override
  String get simWatchSpeed => 'Velocidade';

  @override
  String get simWatchSatellites => 'Satélites';

  @override
  String get simWatchAltitude => 'Altitude';

  @override
  String get simWatchBaroAltitude => 'Altitude barométrica';

  @override
  String get simWatchAscent => 'Subida';

  @override
  String get simWatchDescent => 'Descida';

  @override
  String get simWatchFixAge => 'Idade do sinal';

  @override
  String simWatchSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get sessionLoadError => 'Não foi possível carregar as sessões.';

  @override
  String get sessionDetailLoadError =>
      'Não foi possível carregar este plano de sessão.';

  @override
  String get gymEditorRemoveExerciseTitle => 'Remover exercício?';

  @override
  String get gymEditorRemoveExerciseBody =>
      'Este exercício e todas as suas séries serão removidos deste treino.';

  @override
  String get gymEditorRemoveExerciseConfirm => 'Remover';

  @override
  String get eventSubmitRunsLoadError =>
      'Não foi possível carregar suas corridas recentes.';

  @override
  String get racesCouldNotOpenLink => 'Não foi possível abrir esse link.';

  @override
  String get prefsHrZonesClearTitle => 'Limpar zonas de frequência cardíaca?';

  @override
  String get prefsHrZonesClearBody =>
      'Suas cinco zonas personalizadas serão limpas.';

  @override
  String get prefsHrZonesClearConfirm => 'Limpar';

  @override
  String get signInRequiredMessage => 'Faça login para usar este recurso.';

  @override
  String get signInRequiredAction => 'Entrar';

  @override
  String get backendUnavailableMessage =>
      'Não foi possível conectar ao servidor no momento. Os recursos online estão indisponíveis.';

  @override
  String get feedSignedOutMessage =>
      'Faça login para ver as corridas das pessoas que você segue.';

  @override
  String ttsPaceAlertSpeedUpByKm(int sec) {
    return 'Acelere $sec segundos por quilômetro';
  }

  @override
  String ttsPaceAlertSpeedUpByMi(int sec) {
    return 'Acelere $sec segundos por milha';
  }

  @override
  String ttsPaceAlertSlowDownByKm(int sec) {
    return 'Diminua $sec segundos por quilômetro';
  }

  @override
  String ttsPaceAlertSlowDownByMi(int sec) {
    return 'Diminua $sec segundos por milha';
  }

  @override
  String ttsCutoffCatchUp(String distance, String pace) {
    return 'Próximo corte em $distance. Você precisa de $pace para conseguir.';
  }

  @override
  String get ttsCutoffUnreachable =>
      'Próximo corte: o limite de tempo já passou.';

  @override
  String ttsMarkerAheadOfPlan(String label, String time) {
    return '$label: $time à frente do plano';
  }

  @override
  String ttsMarkerBehindPlan(String label, String time) {
    return '$label: $time atrás do plano';
  }

  @override
  String ttsMarkerOnPlan(String label) {
    return '$label: dentro do plano';
  }

  @override
  String ttsPhaseStart(int index, int total, String phrase) {
    return 'Fase $index de $total. $phrase';
  }

  @override
  String get ttsPhaseHoldBack => 'Segure o ritmo. Mantenha o controle.';

  @override
  String get ttsPhaseSettle => 'Estabilize no seu ritmo alvo.';

  @override
  String get ttsPhaseRace => 'Hora de correr. Dê o que restou.';

  @override
  String get ttsPhaseEven => 'Mantenha um esforço constante.';

  @override
  String ttsPhaseTargetPace(String pace) {
    return 'Alvo: $pace.';
  }

  @override
  String get prefsVoiceCueTypesLabel => 'Avisos falados';

  @override
  String get prefsCueSplits => 'Parciais';

  @override
  String get prefsCueSplitsSubtitle =>
      'Seu ritmo (ou velocidade) cada vez que você passa um marcador de parcial';

  @override
  String get prefsCueSplitsInfo =>
      'Diz um breve resumo cada vez que você completa um parcial (defina a distância em Intervalo de parciais). Use Anúncio de parciais para escolher ritmo do parcial, ritmo médio ou ambos. Exemplo: “1 quilômetro. Ritmo, 5 minutos e 30 segundos por quilômetro.”';

  @override
  String get prefsCueStartFinish => 'Início e fim';

  @override
  String get prefsCueStartFinishSubtitle =>
      '“Corrida iniciada” no começo e um resumo ao terminar';

  @override
  String get prefsCueStartFinishInfo =>
      'Confirma que a corrida começou e lê sua distância e tempo ao parar. Exemplo: “Corrida concluída. 10,0 quilômetros em 52 minutos.”';

  @override
  String get prefsCueOffRoute => 'Fora do percurso';

  @override
  String get prefsCueOffRouteSubtitle =>
      'Um aviso quando você se afasta do percurso que está seguindo';

  @override
  String get prefsCueOffRouteInfo =>
      'Só funciona quando você inicia uma corrida com um percurso salvo. Avisa assim que você se afasta dele para voltar ao caminho. Exemplo: “Fora do percurso.”';

  @override
  String get prefsCuePaceAlerts => 'Alertas de desvio de ritmo';

  @override
  String get prefsCuePaceAlertsSubtitle =>
      '“Acelere” / “diminua” quando você se desvia do seu ritmo alvo';

  @override
  String get prefsCuePaceAlertsInfo =>
      'Precisa de um ritmo alvo definido. Quando você se desvia mais de uns 30 segundos, isto diz para que lado ajustar e quanto. Exemplo: “Acelere 8 segundos.”';

  @override
  String get prefsCueWorkoutSteps => 'Passos do treino';

  @override
  String get prefsCueWorkoutStepsSubtitle =>
      'Anuncia cada passo de um treino estruturado ao começar';

  @override
  String get prefsCueWorkoutStepsInfo =>
      'Só fica ativo durante um treino estruturado (uma sessão de plano ou treino de intervalos). Anuncia cada passo e seu alvo para você manter os olhos à frente. Exemplo: “Repetição 3 de 5. 400 metros a 4 minutos e 30 segundos por quilômetro.”';

  @override
  String get prefsCueCutoffCatchUp => 'Alcançar o corte';

  @override
  String get prefsCueCutoffCatchUpSubtitle =>
      'O ritmo necessário para um corte que você corre risco de perder';

  @override
  String get prefsCueCutoffCatchUpInfo =>
      'Só fica ativo em um percurso com cortes de tempo. Se um estiver em risco, lê a distância até ele e o ritmo que ainda o alcança. Exemplo: “2 quilômetros até o corte. 6 minutos por quilômetro.”';

  @override
  String get prefsCueMarkerTargets => 'Marcadores do percurso';

  @override
  String get prefsCueMarkerTargetsSubtitle =>
      'Se você está à frente ou atrás do plano em cada marcador';

  @override
  String get prefsCueMarkerTargetsInfo =>
      'Só fica ativo em um percurso cujos marcadores têm tempos alvo. Ao passar por cada um, diz se você está à frente ou atrás, e por quanto. Exemplo: “Posto 2: 45 segundos à frente do plano.”';

  @override
  String get prefsCuePhaseTransitions => 'Fases da corrida';

  @override
  String get prefsCuePhaseTransitionsSubtitle =>
      'Um aviso quando cada fase da sua estratégia de corrida começa';

  @override
  String get prefsCuePhaseTransitionsInfo =>
      'Só fica ativo quando você escolhe uma estratégia de corrida. Anuncia cada fase e sua intenção ao começar. Exemplo: “Fase 2 de 3. Estabilize no seu ritmo alvo.”';

  @override
  String get prefsCueGuidedRun => 'Corridas guiadas';

  @override
  String get prefsCueGuidedRunSubtitle =>
      'O roteiro do treinador de uma corrida guiada escolhida antes de começar';

  @override
  String get prefsCueGuidedRunInfo =>
      'Só fica ativo quando você escolhe uma corrida guiada na aba Corrida antes de começar. Anuncia cada indicação do roteiro ao chegar à sua marca. Exemplo: “Cinco minutos. Estabilize num ritmo que aguentaria o dia todo.”';

  @override
  String get runGuidedRun => 'Corrida guiada';

  @override
  String get runGuidedRunNone => 'Sem corrida guiada';

  @override
  String runGuidedRunOption(int minutes, String subtitle) {
    return '$minutes min · $subtitle';
  }

  @override
  String get runRaceStrategy => 'Estratégia de corrida';

  @override
  String get runStrategyNone => 'Sem estratégia';

  @override
  String get runStrategyTenTenTen => '10-10-10';

  @override
  String get runStrategyNegativeSplit => 'Split negativo';

  @override
  String get runStrategyEven => 'Ritmo constante';

  @override
  String get runStrategyTenTenTenHint =>
      'Segurar, estabilizar e correr o trecho final';

  @override
  String get runStrategyNegativeSplitHint =>
      'Primeira metade controlada, segunda mais rápida';

  @override
  String get runStrategyEvenHint => 'Um ritmo constante do início ao fim';

  @override
  String get runStrategyGoalTime => 'Tempo alvo';

  @override
  String get runStrategyDistance => 'Distância';

  @override
  String get runStrategyNeedsDistance =>
      'Escolha um percurso ou informe uma distância para ativar fases';

  @override
  String get runStrategyInvalidGoal => 'Insira o tempo alvo como h:mm:ss';

  @override
  String runPhaseChip(int index, int total, String intent) {
    return 'Fase $index/$total — $intent';
  }

  @override
  String get phaseIntentHoldBack => 'Segurar';

  @override
  String get phaseIntentSettle => 'Estabilizar';

  @override
  String get phaseIntentRace => 'Correr';

  @override
  String get phaseIntentEven => 'Constante';

  @override
  String routeMarkerTargetChip(String time) {
    return 'Alvo $time';
  }

  @override
  String get routeMarkerTargetLabel => 'Tempo alvo';

  @override
  String get routeMarkerTargetHelper => 'Horas : minutos : segundos';

  @override
  String get routeMarkerTargetInvalid => 'Informe o tempo alvo como h:mm:ss';

  @override
  String get routeMarkerOfficialBadge => 'Dono da rota';

  @override
  String get routeMarkerDistanceAlongLabel => 'Distância ao longo da rota';

  @override
  String get routeMarkerDistanceInvalid =>
      'Informe uma distância válida ao longo da rota.';

  @override
  String get watchScreensTitle => 'Telas do relógio';

  @override
  String get watchScreensAction => 'Compor as telas do relógio';

  @override
  String watchScreensCount(int count, int max) {
    return '$count de $max telas';
  }

  @override
  String get watchScreensEmptyTitle => 'Nenhuma tela composta';

  @override
  String get watchScreensEmptyBody =>
      'O relógio percorre as páginas integradas até você compor uma. Adicione uma tela para escolher o que ela mostra.';

  @override
  String get watchScreensAdd => 'Adicionar tela';

  @override
  String watchScreensFull(int max) {
    return 'Um relógio comporta no máximo $max telas.';
  }

  @override
  String watchScreensHeading(int index) {
    return 'Tela $index';
  }

  @override
  String get watchScreensLayout => 'Layout';

  @override
  String watchScreensSlot(int index) {
    return 'Espaço $index';
  }

  @override
  String get watchScreensMoveUp => 'Mover para cima';

  @override
  String get watchScreensMoveDown => 'Mover para baixo';

  @override
  String get watchScreensRemove => 'Remover tela';

  @override
  String watchScreensRemoveTitle(int index) {
    return 'Remover a tela $index?';
  }

  @override
  String watchScreensRemoveBody(int count) {
    return 'As $count métrica(s) vão junto.';
  }

  @override
  String get watchScreensRemoveConfirm => 'Remover';

  @override
  String get watchScreensCancel => 'Cancelar';

  @override
  String watchScreensShrinkTitle(int count) {
    return 'Descartar $count métrica(s)?';
  }

  @override
  String watchScreensShrinkBody(String layout, int slots, String dropped) {
    return 'Um layout $layout desenha $slots espaço(s), então $dropped deixaria de aparecer.';
  }

  @override
  String get watchScreensShrinkConfirm => 'Alterar o layout';

  @override
  String get watchScreensPushAction => 'Enviar as telas para o relógio';

  @override
  String watchScreensPushed(int count) {
    return '$count tela(s) enviada(s) para o relógio';
  }

  @override
  String get watchScreensCleared => 'Telas compostas apagadas no relógio';

  @override
  String watchScreensPushFailed(String error) {
    return 'Falha ao enviar as telas: $error';
  }

  @override
  String get watchScreensLoadFailed => 'Não foi possível ler as telas salvas.';

  @override
  String get watchScreensStartOver => 'Começar de novo';

  @override
  String get watchLayoutSingle => 'Simples';

  @override
  String get watchLayoutDuo => 'Duo';

  @override
  String get watchLayoutTrio => 'Trio';

  @override
  String get watchMetricElapsed => 'Tempo decorrido';

  @override
  String get watchMetricDistance => 'Distância';

  @override
  String get watchMetricAvgPace => 'Ritmo médio';

  @override
  String get watchMetricLapElapsed => 'Tempo da volta';

  @override
  String get watchMetricHeartRate => 'Frequência cardíaca';

  @override
  String get watchMetricPacerDelta => 'Diferença para o pacer';

  @override
  String get watchMetricGuidedRunRemaining => 'Aviso da corrida guiada';

  @override
  String get watchMetricWorkoutRemaining => 'Etapa do treino';

  @override
  String get watchMetricRacePrediction => 'Previsão de prova';

  @override
  String get watchMetricCutoffMargin => 'Margem para o corte';

  @override
  String get watchMetricTrainingStress => 'Carga de treino';

  @override
  String get watchMetricRoadbookNext => 'Próximo posto de apoio';

  @override
  String get watchMetricFuelCarbs => 'Carboidratos';

  @override
  String get watchMetricGearWear => 'Desgaste do equipamento';

  @override
  String get watchMetricEasyPace => 'Ritmo leve';

  @override
  String get watchMetricVo2Max => 'VO2 máx.';

  @override
  String get watchMetricAltitude => 'Altitude';

  @override
  String get watchMetricDistanceToStart => 'Distância até a largada';

  @override
  String get watchMetricDaylightCountdown => 'Luz do dia restante';

  @override
  String get watchMetricWaypointDistance => 'Distância ao ponto marcado';

  @override
  String get watchMetricClimbGain => 'Ganho de subida';

  @override
  String get watchMetricRecapDistance => 'Distância do ano';

  @override
  String get watchMetricCurrentStreak => 'Sequência atual';

  @override
  String get watchMetricSyncedMovingTime => 'Tempo em movimento';

  @override
  String get watchMetricPrAge => 'Idade do recorde';

  @override
  String get watchMetricPlanReplanChanges => 'Alterações do replanejamento';

  @override
  String get watchMetricPlanAdaptiveChanges => 'Alterações adaptativas';

  @override
  String get watchMetricReadinessScore => 'Prontidão';

  @override
  String get watchMetricGoalPercent => 'Progresso da meta';

  @override
  String get watchMetricTurnCueDistance => 'Próxima curva';

  @override
  String get watchMetricRouteSimplifyDistance => 'Distância do percurso';

  @override
  String get watchMetricAutoEffortMatched => 'Segmentos correspondidos';

  @override
  String get watchMetricRouteElevTotal => 'Desnível do percurso';

  @override
  String get watchMetricRaceDayDays => 'Dias até a prova';

  @override
  String get watchMetricSleepBudget => 'Margem de sono';

  @override
  String get watchMetricTimerRemaining => 'Temporizador';

  @override
  String get watchMetricBackyardBell => 'Contagem regressiva do sino';

  @override
  String get watchMetricStormDelta => 'Tendência de tempestade';

  @override
  String get watchMetricGap => 'Ritmo ajustado à inclinação';

  @override
  String get watchMetricFluid => 'Líquido';

  @override
  String get watchLiveTitle => 'Acompanhar corrida do relógio';

  @override
  String get watchLiveTileSubtitle =>
      'Retransmita a posição do seu relógio para um link ao vivo';

  @override
  String get watchLiveIntro =>
      'Enquanto esta tela estiver aberta, seu celular retransmite a posição do relógio aos espectadores cerca de uma vez por segundo. Mantenha o celular com você e dentro do alcance do Bluetooth — sair desta tela encerra a retransmissão.';

  @override
  String get watchLiveStateOff => 'Sem conexão';

  @override
  String get watchLiveStateConnecting => 'Conectando';

  @override
  String get watchLiveStateLive => 'Ao vivo';

  @override
  String get watchLiveStateGap => 'Intervalo';

  @override
  String get watchLiveStateLost => 'Desistiu';

  @override
  String get watchLiveDetailOff => 'Nada está sendo enviado.';

  @override
  String get watchLiveDetailSearching => 'Procurando seu relógio…';

  @override
  String get watchLiveDetailAwaitingFix =>
      'Conectado — aguardando a primeira posição do relógio.';

  @override
  String get watchLiveDetailGap =>
      'os espectadores veem a última posição como atrasada, não como atual';

  @override
  String get watchLiveDetailLost =>
      'Seu relógio está desligado ou fora de alcance. Nada novo está sendo enviado.';

  @override
  String get watchLiveStart => 'Iniciar retransmissão';

  @override
  String get watchLiveStop => 'Parar retransmissão';

  @override
  String get watchLiveRetry => 'Tentar novamente';

  @override
  String get watchLiveShare => 'Compartilhar link ao vivo';

  @override
  String get watchLiveStartFailed =>
      'Não foi possível iniciar a transmissão ao vivo — nada está sendo compartilhado.';

  @override
  String get watchLiveSyncAction => 'Sincronizar corridas do relógio';

  @override
  String get watchLiveSyncSubtitle =>
      'Baixa as corridas gravadas no relógio. A retransmissão fica pausada nesse período.';

  @override
  String pendingSyncOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count alterações salvas neste dispositivo — serão sincronizadas quando você estiver on-line',
      one:
          '$count alteração salva neste dispositivo — será sincronizada quando você estiver on-line',
    );
    return '$_temp0';
  }

  @override
  String pendingSyncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alterações não foram sincronizadas',
      one: '$count alteração não foi sincronizada',
    );
    return '$_temp0';
  }

  @override
  String get pendingSyncRetry => 'Tentar novamente';

  @override
  String get photoOpen => 'Abrir foto';

  @override
  String get photoLightboxClose => 'Fechar foto';

  @override
  String get photoLightboxLoading => 'Carregando a foto…';

  @override
  String get photoLightboxError => 'Não foi possível carregar esta foto.';

  @override
  String get photoLightboxErrorHint => 'Toque em qualquer lugar para fechar.';

  @override
  String get commonLoading => 'Carregando…';

  @override
  String get commonMore => 'Mais';

  @override
  String get undoAction => 'Desfazer';

  @override
  String get undoDismiss => 'Fechar';

  @override
  String get undoHint => 'Desfazer fica disponível por um curto período.';

  @override
  String get undoRestored => 'Restaurado';

  @override
  String get prefsUndoWindow => 'Janela para desfazer';

  @override
  String get prefsUndoWindow8s => '8 segundos';

  @override
  String get prefsUndoWindow30s => '30 segundos';

  @override
  String get prefsUndoWindowManual => 'Até eu fechar';

  @override
  String undoDismissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notificações descartadas',
      one: 'Notificação descartada',
    );
    return '$_temp0';
  }

  @override
  String get routeConditionsRemoved => 'Relato de condição removido';

  @override
  String get gearWearLogRemoved => 'Observação removida';

  @override
  String nutritionEntryRemoved(String item) {
    return '$item removido';
  }

  @override
  String get runSocialCommentRemoved => 'Comentário removido';

  @override
  String get routeDetailReviewRemoved => 'Avaliação removida';

  @override
  String get routeMarkerRemoved => 'Marcador removido';

  @override
  String get roadbookNeedsRouteLine =>
      'Adicione pelo menos dois pontos a esta rota para montar um roadbook.';

  @override
  String get settingsGearUnavailable =>
      'Equipamento não está disponível nesta versão';

  @override
  String get loadRampTitle => 'Progressão de carga';

  @override
  String get loadRampRatioCaption => 'esta semana vs sua média de 4 semanas';

  @override
  String get loadRampAcuteLabel => 'Últimos 7 dias';

  @override
  String get loadRampChronicLabel => 'Média semanal (4 semanas)';

  @override
  String get loadRampBandLow => 'Baixa';

  @override
  String get loadRampBandOptimal => 'Ótima';

  @override
  String get loadRampBandElevated => 'Elevada';

  @override
  String get loadRampBandHigh => 'Alta';

  @override
  String get loadRampMeaningLow =>
      'Você está correndo abaixo da sua base recente. Ok para um polimento ou semana de recuperação; se durar, é perda de forma.';

  @override
  String get loadRampMeaningOptimal =>
      'Sua semana está na faixa que melhor protege contra lesões. Continue evoluindo nesse ritmo.';

  @override
  String get loadRampMeaningElevated =>
      'Você subiu mais rápido do que sua base recente sustenta. Mantenha esta semana estável em vez de adicionar mais.';

  @override
  String get loadRampMeaningHigh =>
      'É um salto forte sobre sua base recente — o padrão mais associado a lesões. Considere uma semana mais leve.';

  @override
  String get loadRampTrendRamping => 'Sua carga está aumentando.';

  @override
  String get loadRampTrendSteady => 'Sua carga está estável.';

  @override
  String get loadRampTrendTapering => 'Sua carga está diminuindo.';

  @override
  String get comebackTitle => 'Voltando de uma pausa';

  @override
  String get comebackVerdictEasingIn => 'Retomada gradual';

  @override
  String get comebackVerdictSteep => 'Primeira semana puxada';

  @override
  String comebackLayoff(int weeks) {
    return '$weeks semanas sem correr';
  }

  @override
  String get comebackShareCaption =>
      'esta semana em relação à sua média semanal antes da pausa';

  @override
  String get comebackMeaningEasingIn =>
      'Esta semana está confortavelmente abaixo das semanas que você corria antes da pausa. Reconstruir aos poucos a partir daqui é o que faz a volta se sustentar.';

  @override
  String get comebackMeaningSteep =>
      'Esta semana já passa da metade do que você corria antes da pausa. Seu corpo perdeu a base que tornava aquelas semanas rotineiras, então uma semana mais curta agora custa muito menos do que uma recaída depois.';

  @override
  String get comebackThisWeekLabel => 'Últimos 7 dias';

  @override
  String get comebackBaseLabel => 'Média semanal antes da pausa';

  @override
  String get comebackFootnote =>
      'Sua curva de carga de treino volta assim que você tiver algumas semanas consistentes de novo.';

  @override
  String get segmentCatalogueTitle => 'Segmentos famosos';

  @override
  String get segmentCatalogueIntro =>
      'Subidas, pontes e voltas de parque selecionadas no mundo todo. Corra um deles e seu tempo entra no ranking automaticamente.';

  @override
  String get segmentCatalogueSearchLabel => 'Buscar';

  @override
  String get segmentCatalogueSearchHint => 'Nome ou lugar';

  @override
  String get segmentCatalogueRegion => 'Região';

  @override
  String get segmentCatalogueAllRegions => 'Todas as regiões';

  @override
  String get segmentCatalogueSurface => 'Piso';

  @override
  String get segmentCatalogueAllSurfaces => 'Todos os pisos';

  @override
  String get segmentCatalogueSort => 'Ordenar';

  @override
  String get segmentCatalogueSortName => 'Nome';

  @override
  String get segmentCatalogueSortShortest => 'Mais curtos primeiro';

  @override
  String get segmentCatalogueSortLongest => 'Mais longos primeiro';

  @override
  String get segmentCatalogueSortClimb => 'Mais altimetria';

  @override
  String segmentCatalogueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segmentos',
      one: '$count segmento',
    );
    return '$_temp0';
  }

  @override
  String get segmentCatalogueLoadFailed =>
      'Não foi possível carregar o catálogo de segmentos.';

  @override
  String get segmentCatalogueEmpty =>
      'Ainda não há segmentos famosos no catálogo.';

  @override
  String get segmentCatalogueNoMatches =>
      'Nenhum segmento corresponde a estes filtros — tente ampliá-los.';

  @override
  String get segmentCatalogueBrowseAll => 'Ver todos';

  @override
  String get segmentCatalogueNotFoundTitle => 'Segmento não encontrado';

  @override
  String get segmentCatalogueNotFoundBody =>
      'Este segmento não está no catálogo ou foi removido.';

  @override
  String get segmentCatalogueDetailFailedTitle =>
      'Não foi possível carregar este segmento';

  @override
  String get segmentCatalogueDetailFailedBody =>
      'Verifique sua conexão e tente novamente.';

  @override
  String get segmentCatalogueStatDistance => 'Distância';

  @override
  String get segmentCatalogueStatElevation => 'Ganho de elevação';

  @override
  String get segmentCatalogueStatSurface => 'Piso';

  @override
  String get segmentCatalogueLeaderboard => 'Classificação';

  @override
  String get runSurfaceTabSegments => 'Segmentos';

  @override
  String rateLimitCreateClub(String wait) {
    return 'Você está criando clubes rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitCreateRoute(String wait) {
    return 'Você está criando rotas rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitCreateReport(String wait) {
    return 'Você está enviando denúncias rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitCreateChallenge(String wait) {
    return 'Você está criando desafios rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitAdoptPlan(String wait) {
    return 'Você está adotando planos rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitAdoptSessionPlan(String wait) {
    return 'Você está adotando planos de sessão rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitAdoptGymRoutine(String wait) {
    return 'Você está adotando rotinas de academia rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitPublishRoutine(String wait) {
    return 'Você está publicando rotinas rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitSendMessage(String wait) {
    return 'Você está enviando mensagens rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitGeneric(String wait) {
    return 'Você está fazendo isso rápido demais — espere $wait e tente de novo.';
  }

  @override
  String rateLimitWaitSeconds(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n segundos',
      one: '1 segundo',
    );
    return '$_temp0';
  }

  @override
  String rateLimitWaitMinutes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get rateLimitWaitSoon => 'um momento';

  @override
  String get challengesCreate => 'Criar desafio';

  @override
  String get challengesTitleLabel => 'Título';

  @override
  String get challengesDescriptionLabel => 'Descrição';

  @override
  String get challengesMetricLabel => 'Métrica';

  @override
  String get challengesScopeLabel => 'Tipo';

  @override
  String get challengesGoalOptional => 'Meta (opcional)';

  @override
  String get challengesActivityTypeLabel => 'Atividade';

  @override
  String get challengesActivityAny => 'Qualquer';

  @override
  String get challengesClubLabel => 'Clube';

  @override
  String get challengesClubNone => 'Aberto (todos)';

  @override
  String get challengesStartLabel => 'Início';

  @override
  String get challengesEndLabel => 'Fim';

  @override
  String get challengesScopeIndividual => 'Individual';

  @override
  String get challengesScopeClubVsClub => 'Clube contra clube';

  @override
  String get challengesScopeGroupGoal => 'Meta de grupo';

  @override
  String get challengesSuffixHours => 'h';

  @override
  String get challengesSuffixActivities => 'atividades';

  @override
  String get challengesSuffixDays => 'dias';

  @override
  String challengesGoalPreview(String value) {
    return 'Os participantes veem $value';
  }

  @override
  String challengesGoalStreakCeiling(int n) {
    return 'Nesta janela cabem no máximo $n dias ativos.';
  }

  @override
  String get challengesErrTitle => 'Dê um título ao desafio.';

  @override
  String get challengesErrGoal => 'Meta: insira um número positivo';

  @override
  String get challengesErrWindow => 'O fim deve ser depois do início.';

  @override
  String limitsWeightOutOfRange(String min, String max, String unit) {
    return 'Informe um peso entre $min e $max $unit.';
  }

  @override
  String limitsHeightOutOfRange(String min, String max) {
    return 'Informe uma altura entre $min e $max cm.';
  }

  @override
  String limitsServingsOutOfRange(String min, String max) {
    return 'Informe um número de porções entre $min e $max.';
  }

  @override
  String runDetailGuidedRun(String title) {
    return 'Corrida guiada: $title';
  }

  @override
  String get runDetailGuidedRunUnavailable =>
      'Corrida guiada não está mais na biblioteca';

  @override
  String get guidedRunUseThisRun => 'Usar esta corrida';
}
