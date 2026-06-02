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
}
