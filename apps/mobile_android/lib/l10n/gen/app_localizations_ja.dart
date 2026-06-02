// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get prefsLanguage => '言語';

  @override
  String get prefsLanguageSystem => 'システムのデフォルト';

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
  String get navHome => 'ホーム';

  @override
  String get navRun => 'ラン';

  @override
  String get navHistory => '履歴';

  @override
  String get navSocial => 'ソーシャル';

  @override
  String get navSettings => '設定';

  @override
  String get settingsSectionProfile => 'プロフィール';

  @override
  String get settingsSectionAppsData => 'アプリとデータ';

  @override
  String get settingsSectionAccountLegal => 'アカウントと法的情報';

  @override
  String get prefsSectionUnitsDisplay => '単位と表示';

  @override
  String get authEmailLabel => 'メールアドレス';

  @override
  String get authPasswordLabel => 'パスワード';

  @override
  String get authOrDivider => 'または';

  @override
  String get signInTitle => 'サインイン';

  @override
  String get signInHeadline => 'ランを複数のデバイスで同期';

  @override
  String get signInSubtitle => 'サインインしてランをバックアップし、ウェブアプリで表示できます。';

  @override
  String get signInButton => 'サインイン';

  @override
  String get signInForgotPassword => 'パスワードをお忘れですか？';

  @override
  String get signInResetNeedEmail =>
      '先に上にメールアドレスを入力してから、「パスワードをお忘れですか？」をタップしてください。';

  @override
  String get signInResetSent => 'そのメールアドレスが登録されている場合、リセット用リンクを送信しました。';

  @override
  String get signInWithApple => 'Appleでサインイン';

  @override
  String get signInWithGoogle => 'Googleでサインイン';

  @override
  String get signInContinueOffline => 'オフラインで続ける';

  @override
  String get signInCreateAccountPrompt => 'アカウントをお持ちでないですか？ 作成する';

  @override
  String get signUpTitle => 'アカウントを作成';

  @override
  String get signUpHeadline => 'ランの記録を始めよう';

  @override
  String get signUpSubtitle => 'アカウントを作成してランをバックアップし、ウェブアプリで表示できます。';

  @override
  String get signUpButton => 'アカウントを作成';

  @override
  String get signUpConfirmAge => '私は16歳以上です';

  @override
  String get signUpAcceptPrefix => '以下に同意します：';

  @override
  String get signUpTermsLink => '利用規約';

  @override
  String get signUpAcceptConjunction => 'および';

  @override
  String get signUpPrivacyLink => 'プライバシーポリシー';

  @override
  String get signUpErrorConfirmAge => '続けるには、16歳以上であることを確認してください。';

  @override
  String get signUpErrorAcceptTerms => '続けるには、利用規約とプライバシーポリシーに同意してください。';

  @override
  String get signUpContinueWithApple => 'Appleで続ける';

  @override
  String get signUpContinueWithGoogle => 'Googleで続ける';

  @override
  String get signUpSignInPrompt => 'すでにアカウントをお持ちですか？ サインイン';

  @override
  String signUpCouldNotOpen(String url) {
    return '$url を開けませんでした';
  }

  @override
  String get onboardingTrackTitle => 'すべてのランを記録';

  @override
  String get onboardingTrackBody =>
      'ライブマップ、スプリット、ペース、ケイデンス、標高を含むGPS記録。完全にオフラインで動作します。後でサインインすれば複数のデバイスで同期できます。';

  @override
  String get onboardingRoutesTitle => 'ルートをたどる';

  @override
  String get onboardingRoutesBody =>
      'GPXまたはKMLファイルをインポートするか、ウェブアプリからルートを同期できます。走行中にコース外アラートを受け取れます。';

  @override
  String get onboardingLocationTitle => '位置情報へのアクセス';

  @override
  String get onboardingLocationBody =>
      'Threkirは、アプリがフォアグラウンドにあるときもバックグラウンドにあるときもGPS位置情報をサンプリングしてランを記録します（画面がオフのときや、写真を撮るためにアプリを切り替えたときも記録を続けます）。位置情報はデバイス上に保存され、あなたがランを共有または同期することを選んだときにのみThrekirのサーバーにアップロードされます。バックグラウンドの位置情報を拒否すると、アプリから離れた瞬間に記録が停止します。これは後で 設定 → アプリ → Threkir → 権限 で変更できます。';

  @override
  String get onboardingPrivacyTitle => 'あなたのランを見られるのは誰？';

  @override
  String get onboardingPrivacyBody =>
      '新しいランの初期設定を選びましょう。設定でいつでも変更でき、個々のランごとに上書きもできます。';

  @override
  String get onboardingGrantPermission => '権限を許可';

  @override
  String get onboardingNext => '次へ';

  @override
  String get privacyPrivateTitle => '非公開';

  @override
  String get privacyPrivateSubtitle => 'あなただけがランを見られます。どのランも後で共有できます。';

  @override
  String get privacyFollowersTitle => 'フォロワー';

  @override
  String get privacyFollowersSubtitle => 'あなたをフォローしている人が、フィードで新しいランを見られます。';

  @override
  String get privacyPublicTitle => '公開';

  @override
  String get privacyPublicSubtitle => '誰でもあなたのランを見つけて閲覧できます。';

  @override
  String get runStart => 'スタート';

  @override
  String get runStartA11yLabel => 'ランを開始';

  @override
  String get runChooseRoute => 'ルートを選択';

  @override
  String get runChangeRoute => 'ルートを変更';

  @override
  String get runShareLiveLink => 'ライブリンクを共有';

  @override
  String get runTrainingPlans => 'トレーニングプラン';

  @override
  String get runTapToCancel => 'タップしてキャンセル';

  @override
  String get runFirstRunPrompt => '最初のランはタップひとつで始められます。';

  @override
  String get runLastActivity => '前回のアクティビティ';

  @override
  String get runLastRun => '前回のラン';

  @override
  String get runFollowing => 'フォロー中';

  @override
  String get runRaceFallbackTitle => 'レース';

  @override
  String get runRaceArmed => 'レース準備完了';

  @override
  String get runRaceLive => 'レース ライブ';

  @override
  String runRaceWaitingForGo(String label) {
    return '$label — スタート待ち';
  }

  @override
  String runRaceElapsedTapStart(String label, String elapsed) {
    return '$label — 経過 $elapsed · スタートをタップ';
  }

  @override
  String get runComplete => 'ラン完了';

  @override
  String get runStatDistance => '距離';

  @override
  String get runStatTime => '時間';

  @override
  String get runStatMoving => '移動時間';

  @override
  String get runStatPace => 'ペース';

  @override
  String get runStatSpeed => '速度';

  @override
  String get runStatAvgPace => '平均ペース';

  @override
  String get runStatAvgSpeed => '平均速度';

  @override
  String get runStatCalories => 'カロリー';

  @override
  String get runStatElevation => '獲得標高';

  @override
  String get runStatSteps => '歩数';

  @override
  String get runStatCadence => 'ケイデンス';

  @override
  String get runStatHeartRate => '心拍数';

  @override
  String get runUnitKcal => 'kcal';

  @override
  String get runUnitMetres => 'm';

  @override
  String get runUnitSpm => 'spm';

  @override
  String get runUnitBpm => 'bpm';

  @override
  String get runMutePaceCues => 'ペース通知をミュート';

  @override
  String get runPaceCuesMuted => 'ペース通知はミュート中';

  @override
  String get runSynced => '同期済み';

  @override
  String get runSyncing => '同期中…';

  @override
  String get runDone => '完了';

  @override
  String get runDiscardA11yLabel => 'ランを破棄';

  @override
  String get runDiscardA11yHint => '現在の記録を保存せずに破棄します';

  @override
  String get runResumeA11yLabel => 'ランを再開';

  @override
  String get runPauseA11yLabel => 'ランを一時停止';

  @override
  String get runResumeA11yHint => '一時停止した記録を再開します';

  @override
  String get runPauseA11yHint => '記録を終了せずに一時停止します';

  @override
  String get runMarkLapA11yLabel => 'ラップを記録';

  @override
  String runMarkLapWithCountA11yLabel(int count) {
    return 'ラップを記録、これまでに$count回';
  }

  @override
  String get runMarkLapA11yHint => '現在のスプリットを記録します';

  @override
  String get runCollapseStatsPanel => '統計パネルを折りたたむ';

  @override
  String get runExpandStatsPanel => '統計パネルを開く';

  @override
  String runRouteRemaining(String distance) {
    return '残り $distance';
  }

  @override
  String runOffRoute(int metres) {
    return 'コース外 — $metres m 離れています';
  }

  @override
  String get runPermissionRevoked => '位置情報の権限が取り消されました';

  @override
  String get runGpsLost => 'GPS信号を失いました — 開けた場所へ移動してください';

  @override
  String get runWeakGps => 'GPSが弱い — 距離は一時停止中';

  @override
  String get runA11yStarted => 'ランを開始しました';

  @override
  String get runA11yResumed => 'ランを再開しました';

  @override
  String get runA11yPaused => 'ランを一時停止しました';

  @override
  String get runA11yFinished => 'ランを終了しました';

  @override
  String runLapMarked(int count) {
    return 'ラップ $count を記録しました';
  }

  @override
  String get runDiscardDialogTitle => 'ランを破棄しますか？';

  @override
  String get runDiscardDialogBody => '進行中のデータは失われます。';

  @override
  String get runKeepRunning => '走り続ける';

  @override
  String get runDiscard => '破棄';

  @override
  String get runStartWorkout => 'ワークアウトを開始';

  @override
  String get runStartWorkoutSubtitle => 'ライブのステップ目標、音声ガイド、計画と実績の振り返り付きで走ります。';

  @override
  String get runViewWorkoutDetails => '詳細を見る';

  @override
  String get runWorkoutNoStructure => 'このワークアウトには実行可能な構成がありません。';

  @override
  String runWorkoutLoaded(int count) {
    return 'ワークアウトを読み込みました · $countステップ — GOをタップして開始';
  }

  @override
  String get runAbandonWorkoutTitle => 'ワークアウトを中止しますか？';

  @override
  String get runAbandonWorkoutBody =>
      '構成プランはここで終了しますが、記録はフリーランとして続きます。いつでも停止して、これまでの内容を保存できます。';

  @override
  String get runCancel => 'キャンセル';

  @override
  String get runAbandon => '中止';

  @override
  String get runNoRoutesSaved => '保存済みのルートがありません。ルートタブからインポートしてください。';

  @override
  String get runNotificationsOffHint =>
      '通知がオフです — ライブランの通知は表示されません。記録は引き続き動作します。';

  @override
  String get runSettings => '設定';

  @override
  String get runStartAnyway => 'このまま開始';

  @override
  String get runOpenSettings => '設定を開く';

  @override
  String get runNotNow => '後で';

  @override
  String get runShareSubject => 'ライブで追いかけてね';

  @override
  String runCouldNotShareLink(String error) {
    return 'ライブリンクを共有できませんでした：$error';
  }

  @override
  String get runHrStrapLostReconnecting => '心拍ストラップを失いました — 再接続中…';

  @override
  String get runHrStrapReconnected => '心拍ストラップが再接続されました';

  @override
  String get runHrStrapLostNoHr => '心拍ストラップを失いました — 心拍なしで記録を続けます。';

  @override
  String get runHrStrapNotFound => '心拍ストラップが見つかりません — 装着して再接続してください。';

  @override
  String get runReconnect => '再接続';

  @override
  String get runHrStrapStillNotFound => 'まだストラップがありません — 心拍なしで記録を続けます。';

  @override
  String get runSaveFailedRelaunch => 'ローカルに保存できませんでした。アプリを再起動して復元してください。';

  @override
  String get runSyncFailedSaveOffline => 'オフラインで保存しました。ランから同期してください。';

  @override
  String get runSavedOffline => 'オフラインで保存しました。';

  @override
  String runSplitTick(String distance, String pace) {
    return '$distance — $pace';
  }

  @override
  String get runGpsNoServiceSettings => 'GPSなし — 位置情報をオンにすると記録が始まります。';

  @override
  String get runGpsBlockedSettings =>
      'GPSなし — 権限がブロックされています。ルートを記録するには有効にしてください。';

  @override
  String get runGpsPermissionPending => 'GPSなし — 権限が許可されると記録が始まります。';

  @override
  String get runGpsAllowAllTheTime =>
      '位置情報を「常に許可」に設定してください — バックグラウンド権限がないと、アプリを切り替えた時点で記録が停止します。';

  @override
  String get runGpsSensorFailed => 'GPSなしで記録中 — センサーを開始できませんでした。';

  @override
  String get runAgoJustNow => 'たった今';

  @override
  String runAgoMinutes(int count) {
    return '$count分前';
  }

  @override
  String runAgoHours(int count) {
    return '$count時間前';
  }

  @override
  String get runAgoYesterday => '昨日';

  @override
  String runAgoDays(int count) {
    return '$count日前';
  }

  @override
  String runAgoWeeks(int count) {
    return '$count週間前';
  }

  @override
  String runAgoMonths(int count) {
    return '$countか月前';
  }

  @override
  String get runWorkoutAbandonedBand => 'ワークアウト中止 · フリーラン中';

  @override
  String get runWorkoutCompleteBand => 'ワークアウト完了 · 停止をタップして保存';

  @override
  String runWorkoutStepHeader(String label, String target, String pace) {
    return '$label · $target @ $pace';
  }

  @override
  String runWorkoutStepCounter(int current, int total) {
    return '$current/$total';
  }

  @override
  String get runWorkoutRewind => '戻る';

  @override
  String get runWorkoutSkip => 'スキップ';

  @override
  String get runWorkoutAbandon => '中止';

  @override
  String runWorkoutRemainingYards(int yards) {
    return '残り $yards yd';
  }

  @override
  String runWorkoutRemainingMetres(int metres) {
    return '残り $metres m';
  }

  @override
  String runWorkoutRemainingDuration(String duration) {
    return '残り $duration';
  }

  @override
  String get runsRangeToday => '今日';

  @override
  String get runsRangeWeek => '今週';

  @override
  String get runsRangeMonth => '過去30日間';

  @override
  String get runsRangeYear => '今年';

  @override
  String get runsRangeAll => '全期間';

  @override
  String get runsRangeCustom => 'カスタム…';

  @override
  String runsRangeFrom(String date) {
    return '$date から';
  }

  @override
  String runsRangeUntil(String date) {
    return '$date まで';
  }

  @override
  String runsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のラン',
    );
    return '$_temp0';
  }

  @override
  String get runsDateRangeTooltip => '期間';

  @override
  String get runsSortTooltip => '並べ替え';

  @override
  String get runsSortNewest => '新しい順';

  @override
  String get runsSortOldest => '古い順';

  @override
  String get runsSortLongest => '距離が長い順';

  @override
  String get runsSortFastest => 'ペースが速い順';

  @override
  String runsSyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランを同期',
    );
    return '$_temp0';
  }

  @override
  String get runsRefreshTooltip => 'クラウドから更新';

  @override
  String get runsOfflineTooltip => 'オフライン';

  @override
  String runsSelectionTitle(int count) {
    return '$count 件選択中';
  }

  @override
  String get runsSelectAllTooltip => 'すべて選択';

  @override
  String get runsClearSelectionTooltip => 'クリア';

  @override
  String get runsDeleteTooltip => '削除';

  @override
  String get runsCancelTooltip => 'キャンセル';

  @override
  String get runsAddRun => 'ランを追加';

  @override
  String get runsAddRunTooltip => '手動でランを追加';

  @override
  String runsLoadMore(int count) {
    return 'さらに $count 件読み込む';
  }

  @override
  String get runsNoMatch => 'このフィルターに一致するランはありません';

  @override
  String get runsClearFilters => 'フィルターをクリア';

  @override
  String get runsEmptyTitle => 'まだランがありません';

  @override
  String get runsEmptyBody => '「ラン」タブをタップして最初のランを始めましょう';

  @override
  String get runsFilterAll => 'すべて';

  @override
  String get runsSourceAll => 'すべてのソース';

  @override
  String runsSourceLabel(String source) {
    return 'ソース: $source';
  }

  @override
  String get runsSourceFilterTooltip => 'ソースで絞り込む';

  @override
  String get runsSourceRecorded => '記録';

  @override
  String get runsSourceWatch => 'ウォッチ';

  @override
  String get runsSourceStrava => 'Strava';

  @override
  String get runsSourceParkrun => 'parkrun';

  @override
  String get runsSourceHealthKit => 'HealthKit';

  @override
  String get runsSourceHealthConnect => 'Health Connect';

  @override
  String get runsRangePickerTitle => '日付を選択';

  @override
  String get runsRangeStart => '開始';

  @override
  String get runsRangeEnd => '終了';

  @override
  String get runsRangeTapDate => '日付をタップ';

  @override
  String get runsRangeApply => '適用';

  @override
  String get runsRangeClear => 'クリア';

  @override
  String get runsPrevMonth => '前の月';

  @override
  String get runsNextMonth => '次の月';

  @override
  String get runsPrevYear => '前の年';

  @override
  String get runsNextYear => '次の年';

  @override
  String runsDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランを削除しますか？',
    );
    return '$_temp0';
  }

  @override
  String get runsDeleteConfirmBody => 'この操作は元に戻せません。';

  @override
  String get runsCancel => 'キャンセル';

  @override
  String get runsDelete => '削除';

  @override
  String get runsQueuedToSync => '同期待ち';

  @override
  String get runsSignInToSync => 'ランを同期するには設定からサインインしてください';

  @override
  String get runsRefreshFailed => '更新できませんでした — 接続を確認してください';

  @override
  String get runsLoadMoreFailed => 'これ以上ランを読み込めませんでした';

  @override
  String runsSyncPartial(int synced, int total, String error) {
    return '$synced/$total を同期しました。エラー: $error';
  }

  @override
  String runsSyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランで GPS トラックをアップロードできませんでした — 残りは同期されました。次のサイクルで再試行します。',
    );
    return '$_temp0';
  }

  @override
  String runsSyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランをすべて同期しました',
    );
    return '$_temp0';
  }

  @override
  String runsDeletePartial(int deleted, int queued) {
    return '$deleted 件削除、$queued 件は待機中 — オンライン復帰時に再試行します。';
  }

  @override
  String runsDeleteDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランを削除しました',
    );
    return '$_temp0';
  }

  @override
  String get addRunTitle => 'ランを追加';

  @override
  String get addRunSave => '保存';

  @override
  String get addRunSectionWhen => 'いつ';

  @override
  String get addRunSectionActivity => 'アクティビティ';

  @override
  String get addRunSectionRoute => 'ルート（任意）';

  @override
  String get addRunSectionDistance => '距離';

  @override
  String get addRunSectionDuration => '時間';

  @override
  String get addRunSectionTitle => 'タイトル（任意）';

  @override
  String get addRunSectionNotes => 'メモ（任意）';

  @override
  String get addRunClearRoute => 'ルートをクリア';

  @override
  String get addRunSearchRoutes => '保存したルートを検索';

  @override
  String get addRunNoRoutes => '保存したルートはまだありません — 作成またはインポートしてここに添付してください';

  @override
  String get addRunDistanceInvalid => '0 より大きい距離を入力してください';

  @override
  String get addRunDurationInvalid => '時間を入力してください';

  @override
  String get addRunTitleHint => '例: ランチタイムのループ';

  @override
  String get addRunNotesHint => 'どんな感じでしたか？';

  @override
  String get addRunSaveButton => 'ランを保存';

  @override
  String addRunSaveFailed(String error) {
    return 'ランを保存できませんでした: $error';
  }

  @override
  String get addRunSaved => 'ランを履歴に追加しました';

  @override
  String get addRunPickerSearchHint => 'ルートを検索';

  @override
  String get addRunPickerClear => 'クリア';

  @override
  String get addRunPickerCancel => 'キャンセル';

  @override
  String addRunPickerNoMatch(String query) {
    return '\"$query\" に一致するルートはありません';
  }

  @override
  String get addRunPickerNoRoute => 'ルートなし';

  @override
  String get runDetailDnfBadge => 'DNF';

  @override
  String get runDetailEditTooltip => 'ランを編集';

  @override
  String get runDetailShareTooltip => 'ランを共有';

  @override
  String get runDetailMoreTooltip => 'その他';

  @override
  String get runDetailSaveAsRoute => 'ルートとして保存';

  @override
  String get runDetailDeleteRun => 'ランを削除';

  @override
  String get runDetailEditTitle => 'ランを編集';

  @override
  String get runDetailFieldTitle => 'タイトル';

  @override
  String get runDetailFieldNotes => 'メモ';

  @override
  String get runDetailFieldDistance => '距離';

  @override
  String get runDetailFieldDuration => '時間';

  @override
  String get runDetailMarkDnf => 'DNF としてマーク';

  @override
  String get runDetailMarkDnfSubtitle => 'このランを自己ベストから除外します';

  @override
  String get runDetailEditInvalid => '有効な距離と時間を入力してください';

  @override
  String get runDetailSave => '保存';

  @override
  String get runDetailCancel => 'キャンセル';

  @override
  String get runDetailDelete => '削除';

  @override
  String get runDetailLoadingGps => 'GPS データを読み込み中...';

  @override
  String get runDetailGpsUnavailable => 'オフラインでは GPS トラックを利用できません';

  @override
  String get runDetailPauseReplay => '再生を一時停止';

  @override
  String get runDetailReplay => 'このランを再生';

  @override
  String get runDetailStatElevGain => '獲得標高';

  @override
  String get runDetailStatElevLoss => '下り標高';

  @override
  String get runDetailStatAvgHr => '平均心拍';

  @override
  String get runDetailStatAgeGrade => '年齢グレード';

  @override
  String get runDetailSectionElevation => '獲得標高';

  @override
  String get runDetailSectionLaps => 'ラップ';

  @override
  String runDetailLapNumber(int number) {
    return 'ラップ $number';
  }

  @override
  String get runDetailSectionRunningDynamics => 'ランニングダイナミクス';

  @override
  String get runDetailDynVerticalOsc => '上下動';

  @override
  String get runDetailDynGroundContact => '接地時間';

  @override
  String get runDetailDynStrideLength => 'ストライド長';

  @override
  String get runDetailDynAvgPower => '平均パワー';

  @override
  String get runDetailSectionRouteHistory => 'ルート履歴';

  @override
  String get runDetailThisRoute => 'このルート';

  @override
  String runDetailPersonalBest(String route) {
    return '$route での自己ベスト';
  }

  @override
  String runDetailBehindPb(String delta) {
    return '自己ベストから $delta 遅れ';
  }

  @override
  String runDetailAttemptOf(int rank, int total, String pb) {
    return '$total 回中 $rank 回目  —  自己ベスト: $pb';
  }

  @override
  String get runDetailSectionBestEfforts => 'ベストエフォート';

  @override
  String get runDetailSectionHeartRateZones => '心拍ゾーン';

  @override
  String get runDetailHrAvg => '平均';

  @override
  String get runDetailHrMin => '最小';

  @override
  String get runDetailHrMax => '最大';

  @override
  String runDetailZoneRow(int number, String label) {
    return 'ゾーン $number · $label';
  }

  @override
  String get runDetailSectionSplits => 'スプリット';

  @override
  String get runDetailNoGpsForSplits => 'スプリット用の GPS データがありません';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'ランが短すぎて $unit の完全なスプリットを作成できません';
  }

  @override
  String get runDetailSectionSegments => 'セグメント';

  @override
  String get runDetailSaveAsRouteTitle => 'ルートとして保存';

  @override
  String get runDetailSaveAsRouteBody => 'この GPS トレースを、もう一度たどれるルートとして保存します。';

  @override
  String get runDetailRouteNameLabel => 'ルート名';

  @override
  String get runDetailNoTrackToSave => 'このランにはルートとして保存できる GPS トラックがありません';

  @override
  String runDetailRouteLinked(String route) {
    return '$route にリンクしました';
  }

  @override
  String get runDetailRouteLinkFailed => 'ルートをリンクできませんでした';

  @override
  String get runDetailReSnapping => '道路に再スナップ中…';

  @override
  String runDetailRematchFailed(String error) {
    return '再マッチに失敗しました: $error';
  }

  @override
  String runDetailRouteSaved(String name, int kept, int smoothed) {
    return '\"$name\" を保存しました — $kept 個のウェイポイント（$smoothed 個を平滑化）';
  }

  @override
  String runDetailMakePublicFailed(String error) {
    return 'ランを公開できませんでした: $error';
  }

  @override
  String get runDetailMakePublicTitle => 'このランを公開しますか？';

  @override
  String get runDetailMakePublicBodyZone =>
      '共有すると、このランは公開され、リンクを知っている人なら誰でも閲覧できます。このランはプライバシーゾーンのいずれかの内側で開始または終了しているため、閲覧者にはゾーン内の区間が隠された切り取り済みのトラックが表示されます。';

  @override
  String get runDetailMakePublicBodyHasZones =>
      '共有すると、このランは公開され、リンクを知っている人なら誰でも閲覧できます。このトラックに交差するプライバシーゾーンはないため、トラック全体が表示されます。';

  @override
  String get runDetailMakePublicBodyNoZones =>
      '共有すると、このランは公開され、リンクを知っている人なら誰でも閲覧できます — ランの開始地点と終了地点も含まれます。プライバシーゾーンを設定していません。共有する前に自宅周辺に 1 つ追加することを検討してください。';

  @override
  String get runDetailMakePublic => '公開する';

  @override
  String get runDetailDeleteTitle => 'ランを削除しますか？';

  @override
  String get runDetailDeleteBody => 'この操作は元に戻せません。';

  @override
  String get runDetailSuggestLink => 'リンク';

  @override
  String get runDetailSuggestDismiss => '閉じる';

  @override
  String get runDetailSuggestRanRoute => '走ったのは ';

  @override
  String get runDetailSuggestLinkPrompt => 'このランをそのルートにリンクしますか？';

  @override
  String get runDetailMatchPending => '道路にスナップ中…';

  @override
  String get runDetailMatchSkipped => 'スナップなし（ポイントが少なすぎます）';

  @override
  String get runDetailMatchFailed => 'スナップに失敗 — 生のトラックを表示中';

  @override
  String get runDetailMatchMatched => 'スナップ済み';

  @override
  String get runDetailRematchQueueing => 'キューに追加中…';

  @override
  String get runDetailRematch => '再マッチ';

  @override
  String get runDetailSegStatDistance => '距離';

  @override
  String get runDetailSegStatTime => '時間';

  @override
  String get runDetailSegStatPace => 'ペース';

  @override
  String get runDetailSegStatHr => '心拍';

  @override
  String get runDetailSegStatGain => '獲得標高';

  @override
  String get runDetailSegDismiss => '閉じる';

  @override
  String get publicRunTitle => 'ラン';

  @override
  String get publicRunLoadError => 'このランを読み込めませんでした。';

  @override
  String get publicRunUnavailable => 'このランは非公開か、すでに利用できません。';

  @override
  String get publicRunAuthorFallback => 'ランナー';

  @override
  String get publicRunStatDistance => '距離';

  @override
  String get publicRunStatTime => '時間';

  @override
  String get publicRunStatPace => 'ペース';

  @override
  String get publicRunSectionSegments => 'セグメント';

  @override
  String get routesSyncFailedOffline => 'ルートを同期できませんでした — オフラインで動作中';

  @override
  String get routesLoadMoreFailed => 'これ以上ルートを読み込めませんでした';

  @override
  String routesStarUpdateFailed(String error) {
    return 'スターを更新できませんでした: $error';
  }

  @override
  String get routesImportFailedLocalOnly =>
      'インポートに失敗しました: クラウド専用のドキュメント選択ではなく、ローカルストレージからファイルを選んでください。';

  @override
  String routesImported(String name) {
    return '「$name」をインポートしました';
  }

  @override
  String routesImportFailed(String error) {
    return 'インポートに失敗しました: $error';
  }

  @override
  String routesSaved(String name) {
    return '「$name」を保存しました';
  }

  @override
  String get routesEmptyTitle => 'まだルートがありません';

  @override
  String get routesEmptyBody =>
      '「作成」をタップして地図上にルートを描くか、GPX・KML・TCX ファイルをインポートしてください。';

  @override
  String get routesBuild => '作成';

  @override
  String get routesImport => 'インポート';

  @override
  String get routesNoMatch => 'これらのフィルターに一致するルートはありません';

  @override
  String get routesClearFilters => 'フィルターをクリア';

  @override
  String routesLoadMore(int count) {
    return 'さらに $count 件読み込む';
  }

  @override
  String get routesQueuedToSync => '同期待ち';

  @override
  String get routesSavedForOffline => 'オフライン用に保存済み';

  @override
  String get routesUnstarRoute => 'ルートのスターを外す';

  @override
  String get routesStarForWatch => 'ウォッチに表示するためにスターを付ける';

  @override
  String get routesDiscover => '見つける';

  @override
  String get routesSyncFromCloud => 'クラウドから同期';

  @override
  String get routesPublicRoutes => '公開ルート';

  @override
  String get routesHeatmap => 'ヒートマップ';

  @override
  String get routesExplorePublic => '公開ルートを探索';

  @override
  String get routesHeatmapTooltip => 'ルートのヒートマップ';

  @override
  String get routesSearchHint => '名前でルートを検索…';

  @override
  String get routesClearSearch => '検索をクリア';

  @override
  String get routesStarred => 'スター付き';

  @override
  String routesCountMeta(int visible, int total) {
    return '$total 件中 $visible 件のルート';
  }

  @override
  String get routesSurfaceAny => 'すべての路面';

  @override
  String get routesSurfaceRoad => 'ロード';

  @override
  String get routesSurfaceTrail => 'トレイル';

  @override
  String get routesSurfaceMixed => 'ミックス';

  @override
  String get routesDistanceAny => 'すべての距離';

  @override
  String get routesSortNewest => '新しい順';

  @override
  String get routesSortLongest => '長い順';

  @override
  String get routesSortShortest => '短い順';

  @override
  String get routesSortMostRun => '走行回数が多い順';

  @override
  String get routesSortAlpha => 'A–Z';

  @override
  String routesDeleteConfirmTitle(int count) {
    return '$count 件のルートを削除しますか？';
  }

  @override
  String get routesDeleteConfirmBody => 'この操作は取り消せません。';

  @override
  String routesSelectionTitle(int count) {
    return '$count 件選択中';
  }

  @override
  String routesDeletePartial(int deleted, int failed) {
    return '$deleted 件削除、$failed 件失敗 — 接続を確認してください。';
  }

  @override
  String routesDeleteDone(int count) {
    return '$count 件のルートを削除しました。';
  }

  @override
  String get routeBuilderRouteCleared => 'ルートをクリアしました';

  @override
  String routeBuilderPointsSummary(int count, String distance) {
    return '$count ポイント、$distance';
  }

  @override
  String get routeBuilderRouteFailedStraightLines =>
      'ルートを計算できませんでした — ピン間を直線で表示します。';

  @override
  String routeBuilderSegmentsFailed(int count) {
    return '$count 個の区間を道路に合わせられませんでした。該当するピンをドラッグして調整してください。';
  }

  @override
  String routeBuilderRoutingFailed(String error) {
    return 'ルート計算に失敗しました: $error';
  }

  @override
  String get routeBuilderTooCloseToPin => '他のピンに近すぎます — もう少し離してドラッグしてください。';

  @override
  String get routeBuilderPinAlreadyThere =>
      'すでにピンがあります — 別のピンを追加するには離れた場所をタップしてください。';

  @override
  String get routeBuilderTargetTooLong => '目標距離は 1000 km まで入力してください。';

  @override
  String get routeBuilderSaveNeedTwo => 'まず少なくとも 2 つのウェイポイントを置いてください。';

  @override
  String routeBuilderSavedLocally(String detail) {
    return 'ローカルに保存しました。$detail 次回同期されます。';
  }

  @override
  String routeBuilderLocationUnavailable(String error) {
    return '位置情報を取得できません: $error';
  }

  @override
  String get routeBuilderServerUnreachable =>
      'サーバーに接続できません。サインインするか接続を確認して再試行してください。';

  @override
  String routeBuilderSaveFailed(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get routeBuilderSearchHint => '場所を検索…';

  @override
  String get routeBuilderMore => 'その他';

  @override
  String get routeBuilderGenerateLoop => 'ループを生成';

  @override
  String get routeBuilderUndo => '元に戻す';

  @override
  String get routeBuilderClear => 'クリア';

  @override
  String get routeBuilderSaving => '保存中…';

  @override
  String get routeBuilderSave => '保存';

  @override
  String get routeBuilderLocateMe => '現在地を表示';

  @override
  String routeBuilderTapToMovePoint(int number) {
    return 'ポイント $number を移動するにはタップするか、アイコンを使ってください';
  }

  @override
  String routeBuilderEmptyHint(String mode) {
    return '地図をタップしてウェイポイントを配置 · $mode';
  }

  @override
  String routeBuilderOnePointHint(String mode) {
    return 'もう 1 つ置いて線を描く · $mode';
  }

  @override
  String routeBuilderStatusGain(String distance, int gain, int count) {
    return '$distance · $gain m ↑ · $count ポイント';
  }

  @override
  String routeBuilderStatusNoGain(String distance, int count) {
    return '$distance · $count ポイント';
  }

  @override
  String routeBuilderDeletePoint(int number) {
    return 'ポイント $number を削除';
  }

  @override
  String get routeBuilderCancelDrag => 'ドラッグをキャンセル';

  @override
  String get routeBuilderModeTrail => 'トレイル';

  @override
  String get routeBuilderModeRoad => 'ロード';

  @override
  String get routeBuilderModeStraight => '直線';

  @override
  String get routeBuilderLoopDialogBody => '目標距離 — 現在の地図の中心を基点に放射状のループを作成します。';

  @override
  String get routeBuilderCancel => 'キャンセル';

  @override
  String get routeBuilderGenerate => '生成';

  @override
  String get routeBuilderSaveDialogTitle => 'ルートを保存';

  @override
  String get routeBuilderNameLabel => '名前';

  @override
  String get routeBuilderNameHint => '例: 川沿いループ';

  @override
  String get routeBuilderDescriptionLabel => '説明（任意）';

  @override
  String get routeBuilderDescriptionHint => '路面、坂、駐車場など、メモしておきたいこと';

  @override
  String get routeBuilderSaveToLabel => '保存先';

  @override
  String get routeBuilderSaveToPersonal => '個人';

  @override
  String get routeBuilderMakePublic => '公開する';

  @override
  String get routeBuilderMakePublicSubtitle => '他のユーザーが「見つける」で見つけられます';

  @override
  String get routeDetailStartRun => 'ランを開始';

  @override
  String get routeDetailShare => '共有';

  @override
  String get routeDetailShareAsImage => '画像として共有';

  @override
  String get routeDetailShareAsGpx => 'GPX として共有';

  @override
  String get routeDetailShareAsKml => 'KML として共有';

  @override
  String get routeDetailRemoveOfflineSave => 'オフライン保存を解除';

  @override
  String get routeDetailSaveForOffline => 'オフライン用に保存';

  @override
  String get routeDetailUnstarRoute => 'ルートのスターを外す';

  @override
  String get routeDetailStarForWatch => 'ウォッチに表示するためにスターを付ける';

  @override
  String get routeDetailMakePrivate => '非公開にする';

  @override
  String get routeDetailMakePublic => '公開する';

  @override
  String get routeDetailRemoveBookmark => 'ブックマークを削除';

  @override
  String get routeDetailBookmarkRoute => 'ルートをブックマーク';

  @override
  String get routeDetailReportRoute => 'ルートを報告';

  @override
  String get routeDetailTransferToClub => 'クラブに移管';

  @override
  String get routeDetailManageClub => '切り離すか別のクラブに移動';

  @override
  String get routeDetailDeleteRoute => 'ルートを削除';

  @override
  String get routeDetailStatDistance => '距離';

  @override
  String get routeDetailStatElevation => '標高';

  @override
  String routeDetailStatReviews(int count) {
    return '$count 件のレビュー';
  }

  @override
  String get routeDetailStatWaypoints => 'ウェイポイント';

  @override
  String get routeDetailPublicRoute => '公開ルート';

  @override
  String get routeDetailPrivateRoute => '非公開ルート';

  @override
  String get routeDetailPublicSubtitle => '共有リンクを持つ全員がこのルートを見られます';

  @override
  String get routeDetailPrivateSubtitle => 'あなただけがこのルートを見られます';

  @override
  String get routeDetailSavedForOffline => 'オフライン用に保存済み';

  @override
  String get routeDetailSaveForOfflineTitle => 'オフライン用に保存';

  @override
  String get routeDetailOfflinePinnedSubtitle => 'ルートはこの端末に保存され、接続なしで走れます。';

  @override
  String get routeDetailOfflineUnpinnedSubtitle =>
      'ネットワークなしで使えるよう、このルートを端末に保存します。';

  @override
  String get routeDetailDescriptionHeading => '説明';

  @override
  String routeDetailRunCount(int count) {
    return '$count 回の実行';
  }

  @override
  String get routeDetailFeatured => 'おすすめ';

  @override
  String get routeDetailSurfaceTrail => 'トレイル';

  @override
  String get routeDetailSurfaceMixed => 'ミックス';

  @override
  String get routeDetailSurfaceRoad => 'ロード';

  @override
  String get routeDetailAddTagHint => 'タグを追加';

  @override
  String get routeDetailReviewsHeading => 'レビュー';

  @override
  String get routeDetailRate => '評価';

  @override
  String get routeDetailReviewsOffline => 'レビューはオフラインでは利用できません';

  @override
  String get routeDetailNoReviews => 'まだレビューがありません';

  @override
  String get routeDetailRateDialogTitle => 'このルートを評価';

  @override
  String get routeDetailCommentLabel => 'コメント（任意）';

  @override
  String get routeDetailCancel => 'キャンセル';

  @override
  String get routeDetailSubmit => '送信';

  @override
  String get routeDetailSignInToReview => 'レビューを残すにはサインインしてください';

  @override
  String routeDetailReviewFailed(String error) {
    return 'レビューの送信に失敗しました: $error';
  }

  @override
  String routeDetailBookmarkFailed(String error) {
    return 'ブックマークに失敗しました: $error';
  }

  @override
  String get routeDetailPublicWillSync => 'ルートを公開に設定しました。次回同期されます。';

  @override
  String get routeDetailPrivateWillSync => 'ルートを非公開に設定しました。次回同期されます。';

  @override
  String routeDetailVisibilityFailed(String error) {
    return '公開設定を更新できませんでした: $error';
  }

  @override
  String routeDetailStarFailed(String error) {
    return 'スターを更新できませんでした: $error';
  }

  @override
  String get routeDetailOfflineSaved => 'オフライン用に保存しました。';

  @override
  String get routeDetailOfflineRemoved => 'オフライン保存から削除しました。';

  @override
  String routeDetailTagSaveFailed(String error) {
    return 'タグを保存できませんでした: $error';
  }

  @override
  String routeDetailShareFailed(String format, String error) {
    return '$format を共有できませんでした: $error';
  }

  @override
  String get routeDetailClubsLoadTimeout => 'クラブを読み込めませんでした — ネットワークを確認してください。';

  @override
  String get routeDetailClubsLoadFailed => 'クラブを読み込めませんでした。';

  @override
  String get routeDetailDetached => 'クラブから切り離しました。ルートは個人用になりました。';

  @override
  String get routeDetailMovedToClub => 'ルートをクラブのライブラリに移動しました。';

  @override
  String routeDetailTransferFailed(String error) {
    return '移管に失敗しました: $error';
  }

  @override
  String get routeDetailDeleteTitle => 'ルートを削除しますか？';

  @override
  String get routeDetailDeleteBody => 'この操作は取り消せません。';

  @override
  String get routeDetailDelete => '削除';

  @override
  String routeDetailDeleteFailed(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get routeDetailPreview => 'プレビュー';

  @override
  String get routeDetailPreviewStart => 'スタート';

  @override
  String get routeDetailPreviewFinish => 'ゴール';

  @override
  String get routeDetailTransferDialogTitle => 'クラブに移管';

  @override
  String get routeDetailManageClubTitle => 'クラブ所属を管理';

  @override
  String get routeDetailTransferDialogBody =>
      'クラブのメンバーはこのルートをクラブのライブラリで見られ、自分のプランに取り込めます。';

  @override
  String get routeDetailManageClubBody => '管理している別のクラブにこのルートを移動するか、個人用に戻します。';

  @override
  String get routeDetailDetachToPersonal => '個人用に切り離す';

  @override
  String get routeDetailDetachSubtitle => '現在のクラブのライブラリからルートを削除します。';

  @override
  String get routeDetailNoAdminClubs => 'まだ所有または管理しているクラブはありません。';

  @override
  String get routeDetailCurrentClub => '現在のクラブ';

  @override
  String routeDetailClubMemberCount(String location, int count) {
    return '$location · $count 人のメンバー';
  }

  @override
  String get exploreRoutesTitle => 'ルートを探索';

  @override
  String get exploreRoutesModeSearch => '検索';

  @override
  String get exploreRoutesModeNearMe => '近くで探す';

  @override
  String get exploreRoutesSearchHint => '名前でルートを検索...';

  @override
  String get exploreRoutesFeatured => 'おすすめ';

  @override
  String get exploreRoutesSignInRequired => 'ルートを探索するにはサインインしてインターネットに接続してください';

  @override
  String get exploreRoutesTimeout => '接続がタイムアウトしました。ネットワークを確認して再試行してください。';

  @override
  String get exploreRoutesSearchFailed => '検索に失敗しました。再試行をタップしてもう一度試してください。';

  @override
  String get exploreRoutesLoadMoreFailed => 'これ以上読み込めませんでした — 接続を確認してください';

  @override
  String get exploreRoutesLocationPermissionRequired =>
      '近くのルートを探すには位置情報の許可が必要です';

  @override
  String get exploreRoutesNearbyFailed =>
      '近くのルートが見つかりませんでした。再試行をタップしてもう一度試してください。';

  @override
  String get exploreRoutesEmptyNoPublic => 'まだ公開ルートがありません';

  @override
  String get exploreRoutesEmptyNoMatch => '検索に一致するルートはありません';

  @override
  String get exploreRoutesEmptyBody => 'ウェブアプリから共有されたルートがここに表示されます';

  @override
  String get exploreRoutesDistanceAny => 'すべての距離';

  @override
  String get exploreRoutesSurfaceAny => 'すべての路面';

  @override
  String get exploreRoutesSurfaceRoad => 'ロード';

  @override
  String get exploreRoutesSurfaceTrail => 'トレイル';

  @override
  String get exploreRoutesSurfaceMixed => 'ミックス';

  @override
  String get exploreRoutesSortMostRun => '走行回数が多い順';

  @override
  String get exploreRoutesSortNewest => '新しい順';

  @override
  String get exploreRoutesSortFeatured => 'おすすめ';

  @override
  String get exploreRoutesSort => '並べ替え';

  @override
  String exploreRoutesSaveCheckConnection(String name) {
    return '「$name」を保存できませんでした — 接続を確認して再試行してください。';
  }

  @override
  String exploreRoutesSaveFailed(String name) {
    return '「$name」を保存できませんでした。';
  }

  @override
  String exploreRoutesSaved(String name) {
    return '「$name」をライブラリに保存しました';
  }

  @override
  String get exploreRoutesAlreadySaved => '保存済み';

  @override
  String get exploreRoutesSaveToLibrary => 'ライブラリに保存';

  @override
  String get exploreRoutesSurfaceTrailShort => 'トレイル';

  @override
  String get exploreRoutesSurfaceMixedShort => 'ミックス';

  @override
  String get exploreRoutesSurfaceRoadShort => 'ロード';

  @override
  String get exploreRoutesDistanceUnderKm => '5 km 未満';

  @override
  String get exploreRoutesDistanceMidKm => '5〜10 km';

  @override
  String get exploreRoutesDistanceLongKm => '10〜21 km';

  @override
  String get exploreRoutesDistanceUltraKm => '21 km 以上';

  @override
  String get exploreRoutesDistanceUnderMi => '3 マイル未満';

  @override
  String get exploreRoutesDistanceMidMi => '3〜6 マイル';

  @override
  String get exploreRoutesDistanceLongMi => '6〜13 マイル';

  @override
  String get exploreRoutesDistanceUltraMi => '13 マイル以上';

  @override
  String get heatmapSearchHint => '場所を検索…';

  @override
  String get heatmapFilters => 'フィルター';

  @override
  String heatmapRoutesStartHere(int count) {
    return '$count 件のルートがここから始まります';
  }

  @override
  String heatmapRouteCount(int count) {
    return '$count 件のルート';
  }

  @override
  String get heatmapNoRoutesHere => 'ここにルートはありません';

  @override
  String get heatmapNoRoutesHint => 'ここにルートはありません。地図を移動するかフィルターを変更してください。';

  @override
  String heatmapClearKept(int count) {
    return '保持中の $count 件をクリア';
  }

  @override
  String get heatmapUnpinFromMap => '地図から外す';

  @override
  String get heatmapKeepOnMap => '地図に残す';

  @override
  String get heatmapLocateMe => '現在地を表示';

  @override
  String heatmapLocationUnavailable(String error) {
    return '位置情報を取得できません: $error';
  }

  @override
  String get heatmapBackToList => 'リストに戻る';

  @override
  String get heatmapViewRoute => 'ルートを見る';

  @override
  String get heatmapKept => '保持中';

  @override
  String get heatmapKeep => '残す';

  @override
  String get heatmapLensShow => '表示';

  @override
  String get heatmapLensDistance => '距離';

  @override
  String get heatmapLensMap => '地図';

  @override
  String get heatmapHeatDensity => 'ヒート密度';

  @override
  String get heatmapResetFilters => 'フィルターをリセット';

  @override
  String get heatmapLensPopular => '人気';

  @override
  String get heatmapLensFriends => 'フレンド';

  @override
  String get heatmapLensFeatured => 'おすすめ';

  @override
  String get heatmapLensHiddenGems => '隠れた名所';

  @override
  String get publicRouteFallbackTitle => 'ルート';

  @override
  String get publicRouteLoadError => 'このルートを読み込めませんでした。';

  @override
  String get publicRouteUnavailable => 'このルートは非公開か、もう利用できません。';

  @override
  String get publicRouteStatDistance => '距離';

  @override
  String get publicRouteStatElevation => '標高';

  @override
  String get publicRouteStatWaypoints => 'ウェイポイント';

  @override
  String get routesLoadErrorRetry => 'ルートを読み込めませんでした。接続を確認して再試行してください。';

  @override
  String get feedTitle => 'フィード';

  @override
  String get feedFindPeople => 'ユーザーを探す';

  @override
  String get feedActivityAll => 'すべて';

  @override
  String get feedActivityRun => 'ラン';

  @override
  String get feedActivityWalk => 'ウォーク';

  @override
  String get feedActivityCycle => 'サイクリング';

  @override
  String get feedActivityHike => 'ハイク';

  @override
  String get feedLoadMore => 'もっと見る';

  @override
  String feedLoadMoreFailed(String error) {
    return 'これ以上読み込めませんでした: $error';
  }

  @override
  String get feedLoadError => 'フィードを読み込めませんでした。';

  @override
  String get feedEveryoneYouFollow => 'フォロー中の全員';

  @override
  String get feedRunnerFallback => 'ランナー';

  @override
  String get feedLast14Days => '過去14日間';

  @override
  String get feedEmptyTitle => 'フィードは空です';

  @override
  String get feedEmptyBody => '他のランナーをフォローすると、公開ランがここに表示されます。';

  @override
  String get feedNoMatchesTitle => '一致なし';

  @override
  String get feedNoMatchesBody => '過去14日間で現在のフィルターに一致するものはありません。';

  @override
  String get feedNoActivityTitle => '最近のアクティビティなし';

  @override
  String get feedNoActivityBody => 'フォロー中の誰も過去14日間に公開ランを記録していません。';

  @override
  String get feedClearFilters => 'フィルターをクリア';

  @override
  String feedKudosUpdateFailed(String error) {
    return 'Kudosを更新できませんでした: $error';
  }

  @override
  String get profileTitle => 'プロフィール';

  @override
  String get profileRunnerFallback => 'ランナー';

  @override
  String get profileTabRuns => 'ラン';

  @override
  String get profileTabFollowers => 'フォロワー';

  @override
  String get profileTabFollowing => 'フォロー中';

  @override
  String get profileTabNotifications => '通知';

  @override
  String get profileReportUser => 'ユーザーを報告';

  @override
  String get profileUnblock => 'このプロフィールのブロックを解除';

  @override
  String get profileBlock => 'このプロフィールをブロック';

  @override
  String get profileLoadError => 'プロフィールを読み込めませんでした。';

  @override
  String get profileNotFound => 'プロフィールが見つかりません。';

  @override
  String profileFollowStats(int followers, int following) {
    return 'フォロワー $followers · フォロー中 $following';
  }

  @override
  String get profileFollowing => 'フォロー中';

  @override
  String get profileFollow => 'フォロー';

  @override
  String get profileRunsEmptySelf => 'まだランを共有していません。';

  @override
  String get profileRunsEmptyOther => '公開ランはまだありません。';

  @override
  String get profileFollowersEmpty => 'フォロワーはまだいません。';

  @override
  String get profileFollowingEmpty => 'まだ誰もフォローしていません。';

  @override
  String profileLoadMore(int count) {
    return 'さらに$count件読み込む';
  }

  @override
  String get profileLoadMoreFollowersFailed => 'これ以上フォロワーを読み込めませんでした';

  @override
  String get profileLoadMoreFollowingFailed => 'これ以上フォロー中を読み込めませんでした';

  @override
  String profileFollowUpdateFailed(String error) {
    return 'フォローを更新できませんでした: $error';
  }

  @override
  String profileBlockConfirmTitle(String name) {
    return '$nameをブロックしますか？';
  }

  @override
  String get profileBlockConfirmBody =>
      '相手はあなたをフォローしたり、あなたのランにKudosを付けたり、コメントしたりできなくなります。双方向の既存のフォロー関係はすべて解除されます。このページからいつでもブロックを解除できます。';

  @override
  String get profileBlockConfirmAction => 'ブロック';

  @override
  String get profileCancel => 'キャンセル';

  @override
  String get profileThisRunner => 'このランナー';

  @override
  String get profileRunnerNoun => 'ランナー';

  @override
  String profileBlocked(String name) {
    return '$nameをブロックしました';
  }

  @override
  String profileBlockFailed(String error) {
    return 'ブロックできませんでした: $error';
  }

  @override
  String profileUnblocked(String name) {
    return '$nameのブロックを解除しました';
  }

  @override
  String profileUnblockFailed(String error) {
    return 'ブロック解除できませんでした: $error';
  }

  @override
  String get profileNotifAll => 'すべて';

  @override
  String get profileNotifUnread => '未読';

  @override
  String get profileMarkAllRead => 'すべて既読にする';

  @override
  String profileMarkAllReadFailed(String error) {
    return 'すべて既読にできませんでした: $error';
  }

  @override
  String get profileNotifsCaughtUp => 'すべて確認済みです。';

  @override
  String get profileNotifsEmpty => '通知はまだありません。';

  @override
  String get profileDismiss => '閉じる';

  @override
  String profileDismissFailed(String error) {
    return '閉じられませんでした: $error';
  }

  @override
  String get profileNotifSomeone => '誰か';

  @override
  String get profileNotifYourRun => 'あなたのラン';

  @override
  String profileNotifKudos(String name, String dist) {
    return '$nameがあなたの$distにKudosを付けました';
  }

  @override
  String profileNotifComment(String name, String dist) {
    return '$nameがあなたの$distにコメントしました';
  }

  @override
  String profileNotifCommentReply(String name) {
    return '$nameがあなたのコメントに返信しました';
  }

  @override
  String profileNotifFollow(String name) {
    return '$nameがあなたをフォローしました';
  }

  @override
  String profileNotifEventRsvpTitled(String name, String title) {
    return '$nameがあなたのイベント「$title」に参加表明しました';
  }

  @override
  String profileNotifEventRsvp(String name) {
    return '$nameがあなたのイベントに参加表明しました';
  }

  @override
  String profileNotifPlanUpdate(String name) {
    return '$nameがあなたのトレーニングプランを更新しました';
  }

  @override
  String profileNotifMessage(String name) {
    return '$nameがあなたにメッセージを送りました';
  }

  @override
  String profileNotifClubPostNamed(String name, String club) {
    return '$nameが$clubに投稿しました';
  }

  @override
  String profileNotifClubPost(String name) {
    return '$nameがあなたの所属クラブに投稿しました';
  }

  @override
  String profileNotifRunCompletedDist(String name, String dist) {
    return '$nameが$distのランを完了しました';
  }

  @override
  String profileNotifRunCompleted(String name) {
    return '$nameがランを完了しました';
  }

  @override
  String profileNotifGeneric(String name) {
    return '$nameがあなたのアクティビティに反応しました';
  }

  @override
  String get socialTabFeed => 'フィード';

  @override
  String get socialTabPeople => 'ユーザー';

  @override
  String get socialTabClubs => 'クラブ';

  @override
  String get socialTabRoutes => 'ルート';

  @override
  String get clubsTitle => 'クラブ';

  @override
  String get clubsFindPeople => 'ユーザーを探す';

  @override
  String get clubsNewClub => '新しいクラブ';

  @override
  String get clubsTabBrowse => 'さがす';

  @override
  String get clubsTabMine => 'マイクラブ';

  @override
  String get clubsJoinWithCode => '招待コードで参加';

  @override
  String get clubsSearchHint => '名前または場所で検索';

  @override
  String get clubsTimeoutError => '接続がタイムアウトしました。ネットワークを確認して再試行してください。';

  @override
  String get clubsLoadError => 'クラブを読み込めませんでした。再試行してください。';

  @override
  String get clubsBadgePrivate => '非公開';

  @override
  String clubsMemberCount(int count) {
    return 'メンバー$count人';
  }

  @override
  String get clubsEmptyBrowseTitle => 'その検索に一致するクラブはありません。';

  @override
  String get clubsEmptyMineTitle => 'まだクラブに参加していません。';

  @override
  String get clubsEmptyBrowseBody => '別の名前または場所を試してください。';

  @override
  String get clubsEmptyMineBody => '「さがす」から探してみましょう。';

  @override
  String get clubDetailTabFeed => 'フィード';

  @override
  String get clubDetailTabEvents => 'イベント';

  @override
  String get clubDetailTabMembers => 'メンバー';

  @override
  String get clubDetailTabRoutes => 'ルート';

  @override
  String get clubDetailTabTemplates => 'テンプレート';

  @override
  String get clubDetailReportClub => 'クラブを報告';

  @override
  String get clubDetailLoadFailedTitle => 'このクラブを読み込めませんでした。';

  @override
  String get clubDetailLoadFailedBody =>
      '削除されたか、セッションの更新が必要かもしれません。引っ張って再試行するか、設定からサインアウトして再度サインインしてください。';

  @override
  String get clubDetailRetry => '再試行';

  @override
  String get clubDetailTimeoutError => '接続がタイムアウトしました。ネットワークを確認して再試行してください。';

  @override
  String get clubDetailRequestSent => '管理者にリクエストを送信しました。';

  @override
  String clubDetailLeaveTitle(String club) {
    return '$clubから退会しますか？';
  }

  @override
  String get clubDetailCancel => 'キャンセル';

  @override
  String get clubDetailLeave => '退会';

  @override
  String clubDetailReplyFailed(String error) {
    return '返信を投稿できませんでした: $error';
  }

  @override
  String get clubDetailMemberFallback => 'メンバー';

  @override
  String get clubDetailRequestPending => 'リクエスト保留中';

  @override
  String get clubDetailInviteOnly => '招待制';

  @override
  String get clubDetailRequest => 'リクエスト';

  @override
  String get clubDetailJoin => '参加';

  @override
  String get clubDetailOwner => 'オーナー';

  @override
  String get clubDetailNextEvent => '次のイベント';

  @override
  String clubDetailGoingCount(int count) {
    return '$count人参加';
  }

  @override
  String get clubDetailNoPostsMember => 'まだ投稿がありません。メンバーに最新情報を共有しましょう。';

  @override
  String get clubDetailNoPosts => 'まだ更新はありません。';

  @override
  String get clubDetailShareUpdateHint => '最新情報を共有…';

  @override
  String get clubDetailPost => '投稿';

  @override
  String get clubDetailReply => '返信';

  @override
  String clubDetailHideReplies(int count) {
    return '$count件の返信を隠す';
  }

  @override
  String clubDetailShowReplies(int count) {
    return '$count件の返信';
  }

  @override
  String clubDetailReplyAuthorLine(String name, String time) {
    return '$name · $time';
  }

  @override
  String get clubDetailWriteReplyHint => '返信を書く…';

  @override
  String get clubDetailSend => '送信';

  @override
  String get clubDetailNoEventsAdmin => '今後のイベントはありません。「作成」をタップして追加してください。';

  @override
  String get clubDetailNoEvents => '今後のイベントはありません。';

  @override
  String get clubDetailCreateEvent => 'イベントを作成';

  @override
  String get clubDetailGoing => '参加';

  @override
  String clubDetailApproveFailed(String error) {
    return '承認できませんでした: $error';
  }

  @override
  String clubDetailDenyFailed(String error) {
    return '拒否できませんでした: $error';
  }

  @override
  String clubDetailPendingRequests(int count) {
    return '保留中のリクエスト ($count)';
  }

  @override
  String clubDetailUserShort(String id) {
    return 'ユーザー $id…';
  }

  @override
  String get clubDetailDeny => '拒否';

  @override
  String get clubDetailApprove => '承認';

  @override
  String clubDetailMemberCountLine(int count) {
    return 'メンバー$count人。';
  }

  @override
  String clubDetailRouteSaved(String name) {
    return '「$name」を保存しました';
  }

  @override
  String get clubDetailBuildRoute => 'このクラブのルートを作成';

  @override
  String get clubDetailRoutesEmptyBuild =>
      'まだルートがありません。上で公式コースを作成するか、ルート詳細画面から個人ルートを移行してください。';

  @override
  String get clubDetailRoutesEmptyAdmin =>
      'まだルートがありません。管理者はルート詳細画面から個人ルートを移行できます。';

  @override
  String get clubDetailRoutesEmpty => 'このクラブと共有されたルートはまだありません。';

  @override
  String get clubDetailTemplateAdded => 'テンプレートをプランに追加しました。';

  @override
  String clubDetailAdoptFailed(String error) {
    return '採用できませんでした: $error';
  }

  @override
  String get clubDetailNoTemplatesAdmin => 'まだテンプレートがありません。プラン詳細ページから公開してください。';

  @override
  String get clubDetailNoTemplates => 'このクラブのプランテンプレートはまだありません。';

  @override
  String get clubDetailAdopt => '採用';

  @override
  String get eventNotFound => 'イベントが見つかりません。';

  @override
  String get eventLoadError => 'このイベントを読み込めませんでした。再試行してください。';

  @override
  String get eventTimeoutError => '接続がタイムアウトしました。ネットワークを確認して再試行してください。';

  @override
  String eventDurationMin(int minutes) {
    return '· $minutes分';
  }

  @override
  String eventGetDirectionsTo(String label) {
    return '$labelへの経路';
  }

  @override
  String get eventGetDirections => '経路を取得';

  @override
  String get eventCouldNotOpenMaps => '地図を開けませんでした。';

  @override
  String get eventPickOccurrence => '開催回を選択';

  @override
  String get eventTargetPace => '目標ペース';

  @override
  String get eventResultSubmitted => '結果を送信しました。';

  @override
  String eventSubmitFailed(String error) {
    return '送信できませんでした: $error';
  }

  @override
  String eventRaceControlFailed(String error) {
    return 'レース管理に失敗しました: $error';
  }

  @override
  String eventAttendees(int count) {
    return '参加者 ($count)';
  }

  @override
  String get eventNoRsvps => 'まだ参加表明はありません。最初になりましょう。';

  @override
  String get eventAttendeeMember => 'メンバー';

  @override
  String eventAttendeeStatus(String status) {
    return '($status)';
  }

  @override
  String get eventRsvpGoing => '参加する';

  @override
  String get eventRsvpMaybe => '未定';

  @override
  String get eventRsvpDeclined => '行けない';

  @override
  String get eventRaceArmed => '準備完了 — GO待ち';

  @override
  String get eventRaceRunning => '進行中 — ライブ';

  @override
  String get eventRaceFinished => '終了';

  @override
  String get eventRaceCancelled => '中止';

  @override
  String get eventRaceNotArmed => '未準備';

  @override
  String get eventRaceControlLabel => 'レース管理';

  @override
  String get eventRaceAutoApprove => '送信されたタイムを自動承認';

  @override
  String get eventRaceArm => 'レースを準備';

  @override
  String get eventRaceArmedHint =>
      'レース開始時に「GO」をタップしてください。参加者のウォッチに準備バナーが表示されます。';

  @override
  String get eventRaceFireGo => 'GO';

  @override
  String get eventRaceCancel => 'キャンセル';

  @override
  String eventRaceStartedAt(String time) {
    return '$timeに開始';
  }

  @override
  String get eventRaceEnd => 'レースを終了';

  @override
  String get eventRaceCancelRace => 'レースを中止';

  @override
  String get eventUpdatePosted => 'クラブフィードに更新を投稿しました。';

  @override
  String eventPostUpdateFailed(String error) {
    return '更新を投稿できませんでした: $error';
  }

  @override
  String get eventPostUpdateLabel => '更新を投稿';

  @override
  String get eventUpdateHint => '天候判断？別の集合場所？';

  @override
  String get eventPostUpdate => '更新を投稿';

  @override
  String get eventResultsTitle => '結果';

  @override
  String get eventRemoveMine => '自分のを削除';

  @override
  String get eventSubmitMyTime => '自分のタイムを送信';

  @override
  String get eventSubmitting => '送信中…';

  @override
  String get eventNoResults => 'まだ結果がありません。イベント後にタイムを送信すると、ここに表示されます。';

  @override
  String get eventResultRunner => 'ランナー';

  @override
  String get eventResultYou => '(あなた)';

  @override
  String get eventSubmitTimeTitle => 'タイムを送信';

  @override
  String get eventSubmitTimeSubtitle => '添付するランを選ぶか、DNF / DNSを記録してください。';

  @override
  String get eventNoRecentRuns => '最近のランが見つかりません。先にランを記録してから戻ってください。';

  @override
  String get eventRecordDnf => 'DNFを記録';

  @override
  String get eventRecordDns => 'DNSを記録';

  @override
  String get eventSubmitCancel => 'キャンセル';

  @override
  String get liveSpectatorTitle => 'ライブトラッキング';

  @override
  String get liveSpectatorConnectError => '接続できませんでした。';

  @override
  String get liveSpectatorWaiting => 'ランナーの最初の位置情報を待っています…';

  @override
  String get liveSpectatorBadgeLive => 'ライブ';

  @override
  String get liveSpectatorBadgeIdle => '停止中';

  @override
  String get liveSpectatorBadgeConnecting => '接続中';
}
