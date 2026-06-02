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
}
