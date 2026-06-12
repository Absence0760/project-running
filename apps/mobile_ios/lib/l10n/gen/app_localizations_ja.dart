// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get trustedContactsClearedBanner => '信頼できる連絡先をクリアしました。';

  @override
  String trustedContactsSavedBanner(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の信頼できる連絡先を保存しました。',
    );
    return '$_temp0';
  }

  @override
  String trustedContactsSaveFailedBanner(Object error) {
    return '保存できませんでした: $error';
  }

  @override
  String get trustedContactsTitle => '信頼できる連絡先';

  @override
  String trustedContactsIntro(Object max) {
    return '信頼できる連絡先を1人以上指定してください。リストはアカウントとともに保存され、今後の「ラン遅延」通知や緊急ボタンの通知先として使われます。最大$max件まで。';
  }

  @override
  String get trustedContactsAddButton => '連絡先を追加';

  @override
  String get trustedContactsSavingButton => '保存中…';

  @override
  String get trustedContactsSaveButton => '保存';

  @override
  String get trustedContactsNameLabel => '名前';

  @override
  String get trustedContactsNameHint => '例: アレックス・チェン';

  @override
  String get trustedContactsPhoneLabel => '電話番号';

  @override
  String get trustedContactsPhoneHint => '+1 555 123 4567';

  @override
  String get trustedContactsEmailLabel => 'メールアドレス';

  @override
  String get trustedContactsEmailHint => 'alex@example.com';

  @override
  String get trustedContactsRelationshipLabel => '続柄';

  @override
  String get trustedContactsRelationshipHint => 'パートナー / 親 / ランニング仲間';

  @override
  String get trustedContactsRemoveButton => '削除';

  @override
  String get clubInviteEnterCodeError => 'リンクの招待コードを入力してください。';

  @override
  String get clubInviteJoinedBanner => 'クラブに参加しました。';

  @override
  String get clubInviteTitle => 'クラブに参加';

  @override
  String get clubInviteIntro => 'クラブ管理者から共有された招待コードを貼り付けてください。';

  @override
  String get clubInviteCodeLabel => '招待コード';

  @override
  String get clubInviteJoinButton => '参加';

  @override
  String recapShareHeadline(Object year) {
    return '$year年のランニング:';
  }

  @override
  String recapShareTotals(Object total, Object count) {
    return '$count件のランで$total';
  }

  @override
  String recapShareLongestRun(Object distance) {
    return '最長のラン: $distance';
  }

  @override
  String recapShareBestStreak(Object days) {
    return '最高の連続記録: $days日';
  }

  @override
  String recapShareSubject(Object year) {
    return '$year年の振り返り';
  }

  @override
  String get recapTitle => 'ランニングの1年';

  @override
  String get recapShareTooltip => '振り返りを共有';

  @override
  String recapNoRunsForYear(Object year) {
    return '$year年は振り返るランがありません。';
  }

  @override
  String recapNoRunsYet(Object year) {
    return '$year年はまだランがありません。記録すると振り返りが表示されます。';
  }

  @override
  String recapAcrossRuns(Object count, Object runWord) {
    return '$count件の$runWord';
  }

  @override
  String get recapLongestRunLabel => '最長のラン';

  @override
  String get recapBestStreakLabel => '最高の連続記録';

  @override
  String recapStreakDays(Object days, Object dayWord) {
    return '$days$dayWord';
  }

  @override
  String get recapTopWeekLabel => 'ベストな週';

  @override
  String get recapUniqueRoutesLabel => 'ユニークなルート';

  @override
  String get recapEarliestStartLabel => '最も早いスタート';

  @override
  String get recapLatestStartLabel => '最も遅いスタート';

  @override
  String get routePickerTitle => 'ルートを選択';

  @override
  String get routePickerNoRoute => 'ルートなし';

  @override
  String get routePickerClearSearchTooltip => '検索をクリア';

  @override
  String get routePickerSearchHint => '名前でルートを検索…';

  @override
  String get routePickerEmptyNoRoutes => '保存済みのルートはまだありません';

  @override
  String routePickerEmptyNoMatch(Object query) {
    return '「$query」に一致するルートはありません';
  }

  @override
  String get routePickerStarredHeader => 'スター付き';

  @override
  String get routePickerAllRoutesHeader => 'すべてのルート';

  @override
  String importStatusImported(Object count, Object label) {
    return '$labelから$count件のランをインポートしました';
  }

  @override
  String importStatusImportedWithErrors(Object count, Object errors) {
    return '$count件のランをインポートしました（$errors件失敗）';
  }

  @override
  String importStatusNoGpsNote(Object base, Object label) {
    return '$base。$labelにはルートデータがないため、これらのランに地図はありません。';
  }

  @override
  String importHealthRequestingPermission(Object label) {
    return '$labelの権限をリクエスト中...';
  }

  @override
  String importHealthPermissionDenied(Object label) {
    return '$labelの権限が拒否されました';
  }

  @override
  String get importHealthReadingWorkouts => 'ワークアウトを読み込み中...';

  @override
  String importHealthFailed(Object label, Object error) {
    return '$labelのインポートに失敗しました: $error';
  }

  @override
  String get importStatusSavingLocally => 'ローカルに保存中...';

  @override
  String importStatusSkippedDuplicates(Object count) {
    return '他のソースからすでにインポート済みの重複$count件をスキップしました';
  }

  @override
  String importStatusSavedProgress(Object done, Object total) {
    return '$total件中$done件をローカルに保存しました';
  }

  @override
  String get importStatusSyncingToCloud => 'クラウドに同期中...';

  @override
  String importStatusSyncProgress(Object done, Object total) {
    return '$total件中$done件を同期しました';
  }

  @override
  String get importStatusReadingCsv => 'CSVを読み込み中...';

  @override
  String importCsvFailed(Object error) {
    return 'CSVのインポートに失敗しました: $error';
  }

  @override
  String get importStatusRestoringBackup => 'バックアップを復元中...';

  @override
  String importStatusBackupRestored(Object runs, Object tracks, Object routes) {
    return 'ラン$runs件 · トラック$tracks件 · ルート$routes件を復元しました';
  }

  @override
  String importBackupFailed(Object error) {
    return 'バックアップの復元に失敗しました: $error';
  }

  @override
  String get importStatusReadingExport => 'エクスポートを読み込み中...';

  @override
  String importStravaFailed(Object error) {
    return 'インポートに失敗しました: $error';
  }

  @override
  String get importTitle => 'ランをインポート';

  @override
  String get importStravaCardTitle => 'Strava';

  @override
  String get importStravaCardSubtitle => 'StravaのデータエクスポートZIPからすべてのランをインポート';

  @override
  String get importStravaHowToHeader => 'Stravaのエクスポートの取得方法:';

  @override
  String get importStravaHowToSteps =>
      '1. Stravaを開く → 設定 → マイアカウント\n2. 「アカウントのダウンロードまたは削除」までスクロール\n3. 「始める」→「アーカイブをリクエスト」をタップ\n4. 数時間後にダウンロードリンク付きのメールが届きます\n5. .zipをダウンロードし、下の「インポート」をタップ';

  @override
  String get importStravaButton => 'Strava ZIPをインポート';

  @override
  String importHealthButton(Object label) {
    return '$labelからインポート';
  }

  @override
  String get importCsvCardTitle => 'CSV';

  @override
  String get importCsvCardSubtitle => '設定からエクスポートしたCSVを再インポート — ランのみ、GPSなし';

  @override
  String get importCsvCardDescription =>
      'CSVの各行が手動ランになります（日付、距離、時間、ソース）。地図のトレースはCSVに含まれないため、インポートしたランにはルートの線が表示されません。';

  @override
  String get importCsvButton => 'CSVをインポート';

  @override
  String get importBackupCardTitle => 'フルバックアップZIP';

  @override
  String get importBackupCardSubtitle => 'バックアップファイルからラン、ルート、GPSトレースを復元';

  @override
  String get importBackupCardDescription =>
      'ロスレスで往復できます。サインインなしでも動作し、復元したランは次回サインイン時にアカウントに同期されます。設定 → フルバックアップ からバックアップを作成してください。';

  @override
  String get importBackupButton => 'バックアップZIPを復元';

  @override
  String get importErrorsHeader => 'エラー';

  @override
  String importErrorsMore(Object count) {
    return '... ほか$count件';
  }

  @override
  String get importHealthSubtitleIos =>
      'Apple Watch、Nike Run Club、Strava など、Apple Health に書き込む各アプリで記録したワークアウトを取り込みます';

  @override
  String get importHealthSubtitleAndroid =>
      'Google Fit、Samsung Health、Garmin、Fitbit など、Health Connect 対応アプリからワークアウトを取り込みます';

  @override
  String get importHealthDescriptionIos =>
      '過去1年間のワークアウト概要（日付、距離、時間、種類）を読み込みます。Apple Health はサードパーティ製アプリが記録した GPS ルートを公開しないため、この方法でインポートしたランには地図のトレースがありません。';

  @override
  String get importHealthDescriptionAndroid =>
      '過去1年間のワークアウト概要（日付、距離、時間、種類）を読み込みます。GPS ルートは Health Connect から公開されないため、この方法でインポートしたランには地図のトレースがありません。';

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'フォローを更新できませんでした: $error';
  }

  @override
  String get peopleSearchHint => '名前でランナーを検索';

  @override
  String get peopleClearSearchTooltip => '検索をクリア';

  @override
  String get peopleSearchResultsHeader => '検索結果';

  @override
  String get peopleSuggestedHeader => 'おすすめ';

  @override
  String peopleEmptySearchTitle(Object query) {
    return '「$query」に一致するランナーはいません';
  }

  @override
  String get peopleEmptySearchBody =>
      '短い名前や別の名前で試してください。表示名は公開されます。まだ設定していない人はここに表示されません。';

  @override
  String get peopleEmptySuggestionsTitle => 'おすすめはまだありません';

  @override
  String get peopleEmptySuggestionsBody =>
      'おすすめは参加中のクラブのメンバーから表示されます。クラブに参加すると、ここに表示され始めます。';

  @override
  String peoplePublicRunCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '公開ラン$count件',
    );
    return '$_temp0';
  }

  @override
  String peopleSharedClubsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '共通のクラブ$count件',
    );
    return '$_temp0';
  }

  @override
  String get peopleFallbackDisplayName => 'ランナー';

  @override
  String get peopleFollowingButton => 'フォロー中';

  @override
  String get peopleFollowButton => 'フォロー';

  @override
  String get readinessCardHeader => 'レディネス';

  @override
  String get readinessBandHigh => '高い';

  @override
  String get readinessBandModerate => '普通';

  @override
  String get readinessBandLow => '低い';

  @override
  String get missingMapTilesTitle => 'OpenStreetMapの代替タイルを使用中';

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
  String get navLog => '記録';

  @override
  String get logA11yLabel => 'アクティビティを記録';

  @override
  String get navFitness => 'フィットネス';

  @override
  String get navYou => 'あなた';

  @override
  String get fitnessTabAll => 'すべて';

  @override
  String get fitnessTabRuns => 'ラン';

  @override
  String get fitnessTabGym => 'ジム';

  @override
  String get fitnessTabNutrition => '栄養';

  @override
  String get fitnessRunsRoutes => 'ルート';

  @override
  String get fitnessRunsPlans => 'トレーニングプラン';

  @override
  String get homeAskCoach => 'コーチに相談';

  @override
  String get homeAskCoachSubtitle => 'ラン・筋トレ・栄養のアドバイス';

  @override
  String get youProfileTitle => 'あなたのプロフィール';

  @override
  String get logSheetTitle => '記録';

  @override
  String get logRun => 'ランを記録';

  @override
  String get logLift => '筋トレを記録';

  @override
  String get logFood => '食事を記録';

  @override
  String get prefsKeepRunPrimary => 'ランを主要操作にする';

  @override
  String get prefsKeepRunPrimarySubtitle => '中央のボタンでランを開始、長押しで全メニューを表示';

  @override
  String get bodyMetricsTitle => '身体データ';

  @override
  String get bodyMetricsTileSubtitle => '身長・体重・栄養目標';

  @override
  String get bodyMetricsConsentTitle => '健康データを保存';

  @override
  String get bodyMetricsConsentSubtitle => '身長と体重は特別な健康データです。オフにすると削除されます。';

  @override
  String get bodyMetricsHeight => '身長';

  @override
  String get bodyMetricsWeight => '体重';

  @override
  String get bodyMetricsActivityLevel => '活動レベル';

  @override
  String get bodyMetricsGoal => '目標';

  @override
  String get bodyMetricsTargetsHint => '1日のカロリーとマクロ目標の推定に使用します。';

  @override
  String get bodyMetricsConsentRequired => '健康データの保存をオンにすると身長と体重を保存できます。';

  @override
  String get bodyMetricsSaved => '保存しました';

  @override
  String bodyMetricsSaveFailed(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get safetyTitle => '緊急連絡先';

  @override
  String get safetyTileSubtitle => 'ランを終えたら信頼できる連絡先にメール';

  @override
  String get safetyIntro =>
      '緊急連絡先には、あなたがランを終えたとき（非公開のランでも）メールが届きます。信頼できる人が、あなたが無事に戻ったことを知れます。';

  @override
  String get safetyAddLabel => '連絡先のメール';

  @override
  String get safetyAddButton => '連絡先を追加';

  @override
  String get safetyAdding => '追加中…';

  @override
  String get safetyEmpty => '緊急連絡先はまだありません。';

  @override
  String get safetyStatusPending => '保留中 — 相手の確認待ち';

  @override
  String get safetyStatusConfirmed => '確認済み';

  @override
  String get safetyRemove => '削除';

  @override
  String get safetyRemoveConfirm => 'この緊急連絡先を削除しますか？';

  @override
  String safetyAddFailed(String error) {
    return '連絡先を追加できませんでした：$error';
  }

  @override
  String get safetyInvalidEmail => '有効なメールアドレスを入力してください。';

  @override
  String get safetyAddedToast => '連絡先を追加しました — 確認メールを送りました。';

  @override
  String get safetyRemovedToast => '連絡先を削除しました。';

  @override
  String get safetyIncomingTitle => 'あなたへの依頼';

  @override
  String get safetyIncomingIntro =>
      'これらの人があなたを緊急連絡先に指定したいそうです。確認すると、その人がランを終えたときにメールが届きます。';

  @override
  String safetyIncomingFrom(String name) {
    return '$name さんから';
  }

  @override
  String get safetyConfirm => '確認する';

  @override
  String get safetyDecline => '辞退する';

  @override
  String get safetyConfirmedToast => '緊急連絡先になりました。';

  @override
  String get safetyDeclinedToast => '依頼を辞退しました。';

  @override
  String get safetyUnknownRunner => 'Threkir のランナー';

  @override
  String get activitySedentary => 'ほとんど座っている（デスクワーク）';

  @override
  String get activityLight => '軽い活動（日常の動きが少ない）';

  @override
  String get activityModerate => '中程度の活動（よく立っている）';

  @override
  String get activityVeryActive => 'とても活動的な一日（肉体労働）';

  @override
  String get activityExtraActive => '非常に活動的（激しい肉体労働）';

  @override
  String get goalLose => '減量';

  @override
  String get goalMaintain => '体重を維持';

  @override
  String get goalGain => '増量';

  @override
  String get homeTodaysLift => '今日の筋トレ';

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
  String get historyRangeToday => '今日';

  @override
  String get historyRangeWeek => '今週';

  @override
  String get historyRangeMonth => '過去30日間';

  @override
  String get historyRangeYear => '今年';

  @override
  String get historyRangeAll => '全期間';

  @override
  String get historyRangeCustom => 'カスタム…';

  @override
  String historyRangeFrom(String date) {
    return '$date から';
  }

  @override
  String historyRangeUntil(String date) {
    return '$date まで';
  }

  @override
  String historyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のラン',
    );
    return '$_temp0';
  }

  @override
  String get historyDateRangeTooltip => '期間';

  @override
  String get historySortTooltip => '並べ替え';

  @override
  String get historySortNewest => '新しい順';

  @override
  String get historySortOldest => '古い順';

  @override
  String get historySortLongest => '距離が長い順';

  @override
  String get historySortFastest => 'ペースが速い順';

  @override
  String historySyncTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランを同期',
    );
    return '$_temp0';
  }

  @override
  String get historyRefreshTooltip => 'クラウドから更新';

  @override
  String get historyOfflineTooltip => 'オフライン';

  @override
  String historySelectionTitle(int count) {
    return '$count 件選択中';
  }

  @override
  String get historySelectAllTooltip => 'すべて選択';

  @override
  String get historyClearSelectionTooltip => 'クリア';

  @override
  String get historyDeleteTooltip => '削除';

  @override
  String get historyCancelTooltip => 'キャンセル';

  @override
  String get historyAddRun => 'ランを追加';

  @override
  String get historyAddRunTooltip => '手動でランを追加';

  @override
  String get historyLogTooltip => 'ラン・筋トレ・食事を記録';

  @override
  String historyLoadMore(int count) {
    return 'さらに $count 件読み込む';
  }

  @override
  String get historyNoMatch => 'このフィルターに一致するランはありません';

  @override
  String get historyKindAll => 'すべて';

  @override
  String get historyKindRuns => 'ラン';

  @override
  String get historyKindLifts => '筋トレ';

  @override
  String get historyKindMeals => '食事';

  @override
  String get historyViewAll => 'すべて表示';

  @override
  String get historyToday => '今日';

  @override
  String get historyYesterday => '昨日';

  @override
  String historySetCount(int n) {
    return '$nセット';
  }

  @override
  String historyKcal(int n) {
    return '$n kcal';
  }

  @override
  String get historyTimelineEmpty => 'このビューにはまだ記録がありません。';

  @override
  String get historyClearFilters => 'フィルターをクリア';

  @override
  String get historyEmptyTitle => 'まだランがありません';

  @override
  String get historyEmptyBody => '「ラン」タブをタップして最初のランを始めましょう';

  @override
  String get historyFilterAll => 'すべて';

  @override
  String get historySourceAll => 'すべてのソース';

  @override
  String historySourceLabel(String source) {
    return 'ソース: $source';
  }

  @override
  String get historySourceFilterTooltip => 'ソースで絞り込む';

  @override
  String get historySourceRecorded => '記録';

  @override
  String get historySourceWatch => 'ウォッチ';

  @override
  String get historySourceStrava => 'Strava';

  @override
  String get historySourceParkrun => 'parkrun';

  @override
  String get historySourceHealthKit => 'HealthKit';

  @override
  String get historySourceHealthConnect => 'Health Connect';

  @override
  String get historyRangePickerTitle => '日付を選択';

  @override
  String get historyRangeStart => '開始';

  @override
  String get historyRangeEnd => '終了';

  @override
  String get historyRangeTapDate => '日付をタップ';

  @override
  String get historyRangeApply => '適用';

  @override
  String get historyRangeClear => 'クリア';

  @override
  String get historyPrevMonth => '前の月';

  @override
  String get historyNextMonth => '次の月';

  @override
  String get historyPrevYear => '前の年';

  @override
  String get historyNextYear => '次の年';

  @override
  String historyDeleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランを削除しますか？',
    );
    return '$_temp0';
  }

  @override
  String get historyDeleteConfirmBody => 'この操作は元に戻せません。';

  @override
  String get historyCancel => 'キャンセル';

  @override
  String get historyDelete => '削除';

  @override
  String get historyQueuedToSync => '同期待ち';

  @override
  String get historySignInToSync => 'ランを同期するには設定からサインインしてください';

  @override
  String get historyRefreshFailed => '更新できませんでした — 接続を確認してください';

  @override
  String get historyLoadMoreFailed => 'これ以上ランを読み込めませんでした';

  @override
  String historySyncPartial(int synced, int total, String error) {
    return '$synced/$total を同期しました。エラー: $error';
  }

  @override
  String historySyncTrackFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランで GPS トラックをアップロードできませんでした — 残りは同期されました。次のサイクルで再試行します。',
    );
    return '$_temp0';
  }

  @override
  String historySyncAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランをすべて同期しました',
    );
    return '$_temp0';
  }

  @override
  String historyDeletePartial(int deleted, int queued) {
    return '$deleted 件削除、$queued 件は待機中 — オンライン復帰時に再試行します。';
  }

  @override
  String historyDeleteDone(int count) {
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
  String get runDetailStatGradeAdjPace => '勾配調整ペース';

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
  String runDetailRouteSaveFailed(String name) {
    return '「$name」をルートとして保存できませんでした。';
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
  String get feedActivityLift => '筋トレ';

  @override
  String get feedLiftSetsLabel => 'セット';

  @override
  String get feedLiftVolume => 'ボリューム';

  @override
  String get feedLiftUntitled => 'ワークアウト';

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
  String get clubDetailSessionTemplatesTitle => 'セッションテンプレート';

  @override
  String get clubDetailSessionAdopted => 'セッションをプランに追加しました。';

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
  String get eventClassSessionEyebrow => 'クラス';

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
  String get eventMarkAttended => '出席として記録';

  @override
  String get eventMarkNoShow => '欠席として記録';

  @override
  String get eventAttendanceAttended => '出席';

  @override
  String get eventAttendanceNoShow => '欠席';

  @override
  String get eventAttendanceFailed => '出席を更新できませんでした。もう一度お試しください。';

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
  String get eventRemoveResultTitle => '結果を削除しますか？';

  @override
  String get eventRemoveResultBody =>
      '登録したフィニッシュタイムがこのイベントのリーダーボードから削除されます。後で再度登録できます。';

  @override
  String get eventRemoveResultConfirm => '結果を削除';

  @override
  String eventRemoveResultFailed(String error) {
    return '結果を削除できませんでした: $error';
  }

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

  @override
  String get liveSpectatorBadgeStale => '遅延';

  @override
  String get liveUpdatedNow => 'たった今更新';

  @override
  String liveUpdatedSeconds(int n) {
    return '$n秒前に更新';
  }

  @override
  String liveUpdatedMinutes(int n) {
    return '$n分前に更新';
  }

  @override
  String liveUpdatedHours(int n) {
    return '$n時間前に更新';
  }

  @override
  String liveUpdatedDays(int n) {
    return '$n日前に更新';
  }

  @override
  String get plansTitle => 'トレーニングプラン';

  @override
  String get plansNewPlan => '新しいプラン';

  @override
  String plansDeleteTitle(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String get plansDeleteBody => 'すべての週とワークアウトが削除されます。';

  @override
  String get plansCancel => 'キャンセル';

  @override
  String get plansDelete => '削除';

  @override
  String get plansAbandon => '中止';

  @override
  String plansDaysPerWeek(int count) {
    return '週$count日';
  }

  @override
  String get plansSignInTitle => 'ログインしてトレーニングプランを使用';

  @override
  String get plansSignInBody =>
      'プランはアカウントに同期され、すべてのデバイスで利用できます。設定 → ログインから接続してください。';

  @override
  String get plansEmptyTitle => 'まだプランがありません。';

  @override
  String get plansEmptyBody => '目標レースを選べば、週ごとの予定を作成します。';

  @override
  String get plansTimeoutError => '接続がタイムアウトしました。ネットワークを確認して再試行してください。';

  @override
  String get plansLoadError => 'トレーニングプランを読み込めませんでした。再試行をタップしてください。';

  @override
  String get planNewTitle => '新しいプラン';

  @override
  String get planNewNameLabel => 'プラン名';

  @override
  String get planNewNameHint => '例：秋のハーフマラソン';

  @override
  String get planNewGoalRace => '目標レース';

  @override
  String get planNewStartDate => '開始日';

  @override
  String get planNewDaysPerWeek => '週あたりの日数';

  @override
  String planNewDaysOption(int count) {
    return '$count日';
  }

  @override
  String get planNewGoalTimeSection => '目標タイム · 任意';

  @override
  String get planNewBeginnerTitle => 'ランニング初心者ですか？ウォークラン プランを使用';

  @override
  String get planNewBeginnerSubtitle =>
      'タイム管理されたラン/ウォークのインターバルから連続走へと段階的に進む、C25K 形式の穏やかなプランです。目標タイムのペース設定を上書きします。';

  @override
  String get planNewRecent5kSection => '最近の5kmタイム · 任意';

  @override
  String get planNewRecent5kHelp => '目標ではなく実際の結果にペースを合わせます。リーゲル換算で目標距離に換算します。';

  @override
  String get planNewRecent5kConfirm => 'これは今日でも走れるタイムで、現在の体力を反映しています。';

  @override
  String get planNewRecent5kWarning =>
      '確認するまで、ペースは目標に基づく控えめな推定値のままです。古い結果を基準にすると、復帰ランナーには速すぎるペースが設定される恐れがあります。';

  @override
  String get planNewOverrideHint => '合計週数を上書き';

  @override
  String planNewOverrideLabel(int count) {
    return '週数を上書き（既定 $count）';
  }

  @override
  String get planNewCancel => 'キャンセル';

  @override
  String get planNewCreate => 'プランを作成';

  @override
  String get planNewCreating => '作成中…';

  @override
  String get planNewPreviewTitle => 'プレビュー';

  @override
  String get planNewPaceEasy => 'イージー';

  @override
  String get planNewPaceMarathon => 'マラソン';

  @override
  String get planNewPaceTempo => 'テンポ';

  @override
  String get planNewPaceInterval => 'インターバル';

  @override
  String get planNewPaceRep => 'レペティション';

  @override
  String get planNewPacesFallback =>
      '推定ペースです。最近のランや目標タイムを追加すると、より個別化された目標になります。';

  @override
  String planNewVdot(String value) {
    return 'ダニエルズ VDOT：$value';
  }

  @override
  String get planNewWeekOutline => '週の概要';

  @override
  String planNewMoreWeeks(int count) {
    return '+ さらに$count週';
  }

  @override
  String planNewSessions(int count) {
    return '$countセッション';
  }

  @override
  String get planNewTemplateTitle => 'クラブのテンプレートから始める';

  @override
  String get planNewTemplateSubtitle =>
      '所属クラブが公開したプランを取り込みます。下の開始日でアカウントに複製され、他のプランと同様に編集できます。';

  @override
  String get planNewTemplateButton => 'テンプレートを見る';

  @override
  String get planNewTemplateCloning => '取り込み中…';

  @override
  String planNewTemplateCloneFailed(String error) {
    return 'テンプレートを取り込めませんでした: $error';
  }

  @override
  String get planNewTemplatePickerTitle => 'テンプレートを選択';

  @override
  String get planNewTemplatePickerCancel => 'キャンセル';

  @override
  String get planNewStarterTitle => '組み込みプランから始める';

  @override
  String get planNewStarterSubtitle =>
      '実績のあるトレーニングプランを選ぶと、開始日からスケジュールします。後で調整できます。';

  @override
  String get planNewStarterButton => 'スタータープランを見る';

  @override
  String get planNewStarterCreating => '作成中…';

  @override
  String get planNewStarterPickerTitle => 'スタータープランを選ぶ';

  @override
  String get planNewStarterPickerCancel => 'キャンセル';

  @override
  String planNewStarterCreateFailed(String error) {
    return 'そのプランを作成できませんでした: $error';
  }

  @override
  String get planNewStarterC25k => 'カウチ・トゥ・5K（初心者ウォークラン）';

  @override
  String get planNewStarterHalf12 => 'ハーフマラソン — 12週間';

  @override
  String get planNewStarterMarathon16 => 'マラソン — 16週間';

  @override
  String get planDetailTimeoutError => '接続がタイムアウトしました。ネットワークを確認して再試行してください。';

  @override
  String get planDetailLoadError => 'このプランを読み込めませんでした。再試行をタップしてください。';

  @override
  String get planDetailNotFound => 'プランが見つかりません。';

  @override
  String get planDetailPublishTooltip => 'クラブテンプレートとして公開';

  @override
  String planDetailDaysPerWeek(int count) {
    return '週$count日';
  }

  @override
  String get planDetailToday => '今日';

  @override
  String get planDetailCompleted => '完了';

  @override
  String planDetailWeek(int number) {
    return '第$number週';
  }

  @override
  String planDetailDriftOverFlag(int pct) {
    return '今週は計画より$pct%多く走っています — 疲労を溜めないよう、楽な日は控えめに。';
  }

  @override
  String planDetailDriftUnderFlag(int pct) {
    return '今週は計画より$pct%少なく走っています — 計画した走行量が適応を生みます。';
  }

  @override
  String get planDetailMissedLongMakeUp =>
      '今週のロング走を逃しました — 可能なら入れましょう。最も重要なセッションです。';

  @override
  String get planDetailMissedLongTaper =>
      'ロング走を逃しましたが、テーパー中です — 諦めてレースに向け疲労を抜きましょう。';

  @override
  String get planDetailMissedLongRecovery =>
      'ロング走を逃しました — 取り戻さなくて大丈夫。回復週が来るので体は休息を活かします。';

  @override
  String get planDetailReplan => '残りの週を再計画';

  @override
  String get planDetailAdaptiveReplan => '適応リプラン';

  @override
  String get planDetailAdaptiveOnTrack => '直近の週は計画どおりです。調整は不要です。';

  @override
  String get planDetailAdaptiveNoSafeChange =>
      '最近は計画から外れていますが、今は安全に調整できる変更がありません。';

  @override
  String get planDetailAdaptiveReasonUnder => '数週間にわたって計画を下回っています';

  @override
  String get planDetailAdaptiveReasonOver => '数週間にわたって計画を上回っています';

  @override
  String get planDetailAdaptiveConfidenceHigh => '高い確信度';

  @override
  String get planDetailAdaptiveConfidenceMedium => '中程度の確信度';

  @override
  String planDetailAdaptiveBadge(String reason, String confidence) {
    return '傾向に基づく — $reason（$confidence）';
  }

  @override
  String get planDetailReplanOnTrack => '計画は順調です — 調整は不要です。';

  @override
  String planDetailReplanApplied(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n件のワークアウトを調整しました',
    );
    return '$_temp0';
  }

  @override
  String get planDetailReplanPreviewTitle => '提案された変更';

  @override
  String planDetailReplanMakeUp(String from, String to) {
    return 'ロング走 $from → $to — 逃したロング走を取り戻す';
  }

  @override
  String planDetailReplanEase(String from, String to) {
    return '$from → $to — 走り過ぎ後に軽減';
  }

  @override
  String get planDetailReplanCancel => 'キャンセル';

  @override
  String get planDetailReplanApply => '変更を適用';

  @override
  String get planDetailDuplicateWeek => '週を複製';

  @override
  String planDetailDuplicateWeekDone(int n) {
    return '第$n週を複製しました';
  }

  @override
  String planDetailBulkFailed(String error) {
    return 'プランを更新できませんでした: $error';
  }

  @override
  String get planDetailEditTooltip => 'ワークアウトを編集';

  @override
  String get planDetailPublishLoadClubsTimeout =>
      'クラブを読み込めませんでした。ネットワークを確認してください。';

  @override
  String get planDetailPublishLoadClubsFailed => 'クラブを読み込めませんでした。';

  @override
  String get planDetailPublishNoClubs =>
      'テンプレートを公開するには、クラブのオーナーまたは管理者である必要があります。';

  @override
  String planDetailPublishSuccess(String name) {
    return '「$name」をクラブテンプレートとして公開しました。';
  }

  @override
  String planDetailPublishFailed(String error) {
    return '公開に失敗しました：$error';
  }

  @override
  String get planDetailPublishPickerTitle => 'クラブに公開';

  @override
  String get planDetailPublishPickerBody => 'クラブのメンバーはこのプランを自分のものとして取り込めます。';

  @override
  String planDetailPublishPickerMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'メンバー$count人',
    );
    return '$_temp0';
  }

  @override
  String get planDetailPublishCancel => 'キャンセル';

  @override
  String get workoutTimeoutError => '接続がタイムアウトしました。ネットワークを確認して再試行してください。';

  @override
  String get workoutLoadError => 'このワークアウトを読み込めませんでした。再試行をタップしてください。';

  @override
  String get workoutNotFound => 'ワークアウトが見つかりません。';

  @override
  String get workoutMetricDistance => '距離';

  @override
  String get workoutMetricDuration => '時間';

  @override
  String get workoutMetricTargetPace => '目標ペース';

  @override
  String get workoutCompleted => '完了';

  @override
  String get workoutUnlink => 'リンク解除';

  @override
  String get workoutStart => 'ワークアウトを開始';

  @override
  String get workoutSectionNotes => 'メモ';

  @override
  String get workoutSectionStructure => '構成';

  @override
  String get workoutSectionHowTo => '走り方';

  @override
  String get workoutStructWarmup => 'ウォームアップ';

  @override
  String get workoutStructRepeats => 'リピート';

  @override
  String get workoutStructSteady => '一定';

  @override
  String get workoutStructCooldown => 'クールダウン';

  @override
  String workoutStructWarmupValue(String distance) {
    return '$distance @ イージー';
  }

  @override
  String workoutStructCooldownValue(String distance) {
    return '$distance @ イージー';
  }

  @override
  String get workoutAdviceEasy => '会話できるペースで。会話を続けられないなら速すぎます。';

  @override
  String get workoutAdviceLong =>
      'リラックスして、呼吸を一定に保ちましょう。天候が悪いときや筋肉痛のときは距離を10%減らし、スキップはしないでください。';

  @override
  String get workoutAdviceTempo =>
      '「快適にきつい」ペース。全力で約1時間は維持できそう、それ以上は無理という感覚が目安です。';

  @override
  String get workoutAdviceInterval =>
      '最後のレペティションが最初と同じように感じられる強度で走りましょう。2〜3本しか維持できないペースは選ばないこと。';

  @override
  String get workoutAdviceMarathonPace =>
      '目標マラソンペースに正確に合わせましょう。これはリハーサルです。速くも遅くもしないこと。';

  @override
  String get workoutAdviceWalkRun =>
      'タイム管理されたインターバルで、イージーランとウォークを交互に行いましょう。歩く休憩もワークアウトの一部です。元気でも必ず取ってください。';

  @override
  String get workoutAdviceRace => '計画を信じましょう。最初の1マイルで自己ベストを狙わないこと。';

  @override
  String get workoutAdviceRest => '休養日です。動きたいなら、ウォーキングやストレッチを。';

  @override
  String get coachTitle => 'コーチ';

  @override
  String get coachNewConversation => '新しい会話';

  @override
  String get coachConsentHeadline => 'コーチとチャットする前に';

  @override
  String get coachConsentIntro =>
      '的確なアドバイスのため、コーチはあなたのトレーニングデータの一部を、米国のAIモデルプロバイダーである Anthropic に送信します。その一部には以下が含まれます：';

  @override
  String get coachConsentBulletProfile => '生年月日、性別、設定済みの心拍ゾーン。';

  @override
  String get coachConsentBulletRuns => '直近のランの一部。';

  @override
  String get coachConsentBulletPlan => '選択中のアクティブなトレーニングプラン。';

  @override
  String get coachConsentBulletMessages => '下の画面で入力するチャットメッセージ。';

  @override
  String get coachConsentProcessing =>
      'Anthropic は Threkir に代わってデータ処理条件に基づきデータを処理します。既定では Threkir の顧客データでモデルを学習しません。移転の仕組み、保持期間、撤回の権利を含む詳細は、プライバシーポリシーをご覧ください。';

  @override
  String get coachConsentAction =>
      '「同意する」をタップして続行します。キャンセルをタップすると、データを送信せずにページを離れます。';

  @override
  String get coachConsentCancel => 'キャンセル';

  @override
  String get coachConsentAccept => '同意する — コーチを開始';

  @override
  String get coachConsentSaving => '同意を記録中…';

  @override
  String get coachNoPlanOption => 'プランなし（最近のランのみ）';

  @override
  String coachPlanActive(String name) {
    return '$name · 進行中';
  }

  @override
  String coachPlanDone(String name) {
    return '$name · 完了';
  }

  @override
  String get coachNewChatTooltip => '新しいチャット';

  @override
  String get coachHistoryTooltip => 'チャット履歴';

  @override
  String get coachNewChat => '新しいチャット';

  @override
  String coachActiveThread(String suffix) {
    return '進行中$suffix';
  }

  @override
  String get coachArchiveTapToView => 'タップで表示 · スワイプで削除';

  @override
  String get coachContextNoPlan => 'プランなし';

  @override
  String coachContextPlanWeeks(String name, int weeks) {
    return '$name · $weeks週';
  }

  @override
  String get coachContextNoRuns => 'ランなし';

  @override
  String get coachContextLast => '直近';

  @override
  String get coachContextHr => '心拍';

  @override
  String coachContextWeeklyGoal(String km) {
    return '週${km}km';
  }

  @override
  String coachArchiveBanner(String label) {
    return 'アーカイブを表示中 · $label · 読み取り専用';
  }

  @override
  String get coachBackToActive => '進行中に戻る';

  @override
  String get coachLimitReachedPro => '1日の上限に達しました。明日また来てください。';

  @override
  String get coachLimitReachedFree =>
      '1日の上限に達しました。Pro ならより高い上限になります。設定からアップグレードしてください。';

  @override
  String coachMessagesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '本日あと$countメッセージ',
    );
    return '$_temp0';
  }

  @override
  String get coachEmptyPromptPlan => '今日のワークアウト、ペース、最近のランと計画の比較について質問してください。';

  @override
  String get coachEmptyPromptNoPlan =>
      '最近のラン、イージーランのペース、トレーニングの基本について質問してください。';

  @override
  String get coachSuggestPlanRest => '明日は走るべき？それとも休養日にすべき？';

  @override
  String get coachSuggestPlanOnTrack => '目標タイムに向けて順調ですか？';

  @override
  String get coachSuggestPlanLongRun => '今週のロングランはなぜ大切なの？';

  @override
  String get coachSuggestPlanToday => '今日のワークアウトでは何に集中すべき？';

  @override
  String get coachSuggestNoPlanLastRun => '前回のランはどうだった？';

  @override
  String get coachSuggestNoPlanEasyPace => 'イージーランはどのくらいのペースがいい？';

  @override
  String get coachSuggestNoPlanWeekOff => '1週間走っていません。どうすればいい？';

  @override
  String get coachSuggestNoPlanTempo => 'テンポランとは？';

  @override
  String get coachEditCancel => 'キャンセル';

  @override
  String get coachEditSaveResend => '保存して再送信';

  @override
  String get coachActionCopy => 'コピー';

  @override
  String get coachActionEdit => '編集';

  @override
  String get coachActionRegenerate => '再生成';

  @override
  String get coachActionHelpful => '役に立った';

  @override
  String get coachActionNotHelpful => '役に立たなかった';

  @override
  String get coachComposerHintLimit => '1日の上限に達しました';

  @override
  String get coachComposerHint => 'コーチに質問…';

  @override
  String get coachArchiveTitle => '新しい会話を始めますか？';

  @override
  String get coachArchiveBody => '現在のチャットは履歴に移動します。サイドバーからまた見られます。';

  @override
  String get coachArchiveCancel => 'キャンセル';

  @override
  String get coachArchiveConfirm => '新しいチャット';

  @override
  String get coachSignInFirst => '先にログインしてください。';

  @override
  String get coachSessionExpired => 'セッションの有効期限が切れました。再度ログインしてください。';

  @override
  String coachDailyLimitError(int limit) {
    return '1日の上限に達しました（$limitメッセージ）。明日また来てください！';
  }

  @override
  String coachGenericError(int code) {
    return 'コーチのエラー（$code）';
  }

  @override
  String get coachTransportError => 'コーチに接続できませんでした。接続を確認して再試行してください。';

  @override
  String get coachStreamFailed => 'ストリームに失敗しました';

  @override
  String coachNewConversationFailed(String error) {
    return '新しい会話を開始できませんでした：$error';
  }

  @override
  String coachOpenArchiveFailed(String error) {
    return 'アーカイブを開けませんでした：$error';
  }

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'アーカイブを削除できませんでした：$error';
  }

  @override
  String get coachCopied => 'クリップボードにコピーしました';

  @override
  String get settingsAccountTitle => 'アカウント';

  @override
  String get settingsAccountBackendNotConfigured => 'バックエンドが設定されていません';

  @override
  String get settingsAccountSignOutFailed => 'サインアウトに失敗しました — 接続を確認してください';

  @override
  String get settingsAccountChangePassword => 'パスワードを変更';

  @override
  String get settingsAccountNewPassword => '新しいパスワード';

  @override
  String get settingsAccountConfirm => '確認';

  @override
  String get settingsAccountCancel => 'キャンセル';

  @override
  String get settingsAccountSave => '保存';

  @override
  String get settingsAccountPasswordTooShort => 'パスワードは8文字以上で入力してください';

  @override
  String get settingsAccountPasswordsMismatch => 'パスワードが一致しません';

  @override
  String get settingsAccountPasswordUpdated => 'パスワードを更新しました';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'パスワードを更新できませんでした：$error';
  }

  @override
  String get settingsAccountDeleteTitle => 'アカウントを削除しますか？';

  @override
  String get settingsAccountDeleteBody =>
      'これにより、ラン、ルート、プロフィールがサーバーから完全に削除されます。新しいユーザーとしてサインインしない限り、端末のローカルデータは保持されます。この操作は取り消せません。';

  @override
  String get settingsAccountDeleteChallengeText => '確認するには「DELETE」と入力してください';

  @override
  String settingsAccountDeleteChallengeEmail(String email) {
    return '確認するにはメールアドレス（$email）を入力してください';
  }

  @override
  String get settingsAccountDelete => '削除';

  @override
  String get settingsAccountDeleteSignInFirst => 'アカウントを削除するには、まずサインインしてください。';

  @override
  String get settingsAccountDeleted => 'アカウントを削除しました';

  @override
  String get settingsAccountCoachConsentWithdraw => 'コーチへの同意を撤回';

  @override
  String get settingsAccountCoachConsentActive =>
      'コーチによるトレーニングデータの使用を停止します。いつでも再度同意できます。';

  @override
  String get settingsAccountCoachConsentWithdrawn => 'コーチへの同意を撤回しました。';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return '撤回に失敗しました：$error';
  }

  @override
  String settingsAccountDeleteFailed(Object error) {
    return 'アカウントの削除に失敗しました：$error';
  }

  @override
  String get settingsAccountNoRunsToExport => 'エクスポートするランがありません。';

  @override
  String get settingsAccountCsvShareText => 'Run app — ランのエクスポート';

  @override
  String settingsAccountCsvExportFailed(Object error) {
    return 'CSVエクスポートに失敗しました：$error';
  }

  @override
  String get settingsAccountBackupSignInFirst => 'ランをバックアップするには、まずサインインしてください。';

  @override
  String get settingsAccountBackupPreparing => 'バックアップを準備しています…';

  @override
  String get settingsAccountBackupShareText => 'Run app バックアップ';

  @override
  String settingsAccountBackupFailed(Object error) {
    return 'バックアップに失敗しました：$error';
  }

  @override
  String get settingsAccountRestoreUnavailable => 'バックアップサービスを利用できません。';

  @override
  String get settingsAccountRestoreTitle => 'バックアップから復元しますか？';

  @override
  String get settingsAccountRestoreBodyOffline =>
      'サインインしていません。ランはこの端末に復元され、次回サインインしたときにアカウントと同期されます。';

  @override
  String get settingsAccountRestoreBodyOnline =>
      'バックアップ内のIDが一致するランとルートを追加または上書きします。バックアップに含まれていないランやルートは削除されません。';

  @override
  String get settingsAccountRestore => '復元';

  @override
  String get settingsAccountRestoring => '復元しています…';

  @override
  String settingsAccountRestoreDone(
    int runs,
    int tracks,
    int routes,
    String warnings,
  ) {
    return '$runs 件のラン・$tracks 件のトラック・$routes 件のルートを復元しました$warnings';
  }

  @override
  String settingsAccountRestoreWarningsSuffix(int count) {
    return ' · 警告 $count 件';
  }

  @override
  String settingsAccountRestoreFailed(Object error) {
    return '復元に失敗しました：$error';
  }

  @override
  String get settingsAccountOfflineMode => 'オフラインモード';

  @override
  String get settingsAccountSignedInSync => 'サインイン済み — ランが同期されます';

  @override
  String get settingsAccountSignInToSync => 'サインインすると、複数の端末でランを同期できます';

  @override
  String get settingsAccountSignOut => 'サインアウト';

  @override
  String get settingsAccountSignIn => 'サインイン';

  @override
  String get settingsAccountViewProfile => 'プロフィールを表示';

  @override
  String get settingsAccountViewProfileSubtitle => 'ラン、フォロワー、フォロー中、通知';

  @override
  String get settingsAccountGuidedRuns => 'ガイド付きラン';

  @override
  String get settingsAccountGuidedRunsSubtitle =>
      'コーチの音声とTTSキューによるスクリプト式ワークアウト';

  @override
  String get settingsAccountPrivacyZones => 'プライバシーゾーン';

  @override
  String get settingsAccountPrivacyZonesSubtitle => '自宅付近で公開トラックの開始・終了を切り取る';

  @override
  String get settingsAccountTrustedContacts => '信頼できる連絡先';

  @override
  String get settingsAccountTrustedContactsSubtitle =>
      '予定の遅延ラン／緊急通知のために指定する連絡先';

  @override
  String get settingsAccountSendErrorReports => 'エラーレポートを送信';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      '匿名化されたクラッシュ・エラーデータをSentry（米国）に送信します。オフにすると同意を撤回できます。次回起動時に適用されます。';

  @override
  String get settingsAccountErrorReportingEnabled =>
      'エラーレポートを有効にしました — 適用するにはアプリを再起動してください。';

  @override
  String get settingsAccountErrorReportingDisabled =>
      'エラーレポートを無効にしました — 適用するにはアプリを再起動してください。';

  @override
  String get settingsAccountImport => '別のアプリからインポート';

  @override
  String get settingsAccountImportSubtitle => 'Strava、GPX、TCX';

  @override
  String get settingsAccountFullBackup => '完全バックアップ';

  @override
  String get settingsAccountFullBackupSubtitle =>
      'GPSトラック付きの全ラン、ルート、プロフィール、設定。ウェブまたはAndroidで復元できます。';

  @override
  String get settingsAccountExportCsv => 'ランをCSVでエクスポート';

  @override
  String get settingsAccountExportCsvSubtitle =>
      '日付、距離、時間、ペース、ソース — 1ランにつき1行。ウェブのGDPRエクスポートと同じ形式です。';

  @override
  String get settingsAccountRestoreTile => 'バックアップから復元';

  @override
  String get settingsAccountRestoreTileSubtitle =>
      '以前に保存した.zipバックアップを選択してください。';

  @override
  String get settingsAccountDeleteAccount => 'アカウントを削除';

  @override
  String get settingsAccountDeleteAccountSubtitle => 'サーバーデータを完全に削除します';

  @override
  String get integrationsTitle => '連携';

  @override
  String get integrationsJustNow => 'たった今';

  @override
  String integrationsMinutesAgo(int minutes) {
    return '$minutes分前';
  }

  @override
  String integrationsHoursAgo(int hours) {
    return '$hours時間前';
  }

  @override
  String integrationsDaysAgo(int days) {
    return '$days日前';
  }

  @override
  String integrationsWeeksAgo(int weeks) {
    return '$weeks週間前';
  }

  @override
  String integrationsCouldNotOpen(Object error) {
    return '開けませんでした：$error';
  }

  @override
  String get integrationsStravaBrowserHint =>
      'ブラウザでStravaのサインインを完了し、ここに戻って引っ張って更新してください。';

  @override
  String get integrationsStravaCancelled => 'Stravaのサインインをキャンセルしました。';

  @override
  String integrationsStravaSignInFailed(Object error) {
    return 'Stravaのサインインに失敗しました：$error';
  }

  @override
  String get integrationsStravaCsrfMismatch =>
      'Stravaのサインインが拒否されました：CSRFステートが一致しません。もう一度お試しください。';

  @override
  String integrationsStravaConnectFailed(String error) {
    return 'Stravaの接続に失敗しました：$error';
  }

  @override
  String get integrationsStravaConnected => 'Stravaを接続しました。';

  @override
  String integrationsSyncResult(int imported, int skipped) {
    return '同期しました。新規 $imported 件、既存 $skipped 件。';
  }

  @override
  String integrationsSyncFailed(Object error) {
    return '同期に失敗しました：$error';
  }

  @override
  String get integrationsStravaDisconnectTitle => 'Stravaの接続を解除しますか？';

  @override
  String get integrationsStravaDisconnectBody =>
      '今後のアクティビティは自動同期されなくなります。すでにインポートされたランは履歴に残ります。';

  @override
  String get integrationsCancel => 'キャンセル';

  @override
  String get integrationsDisconnect => '接続を解除';

  @override
  String get integrationsStravaDisconnected => 'Stravaの接続を解除しました。';

  @override
  String integrationsDisconnectFailed(Object error) {
    return '接続解除に失敗しました：$error';
  }

  @override
  String get integrationsParkrunTitle => 'parkrunの結果をインポート';

  @override
  String get integrationsParkrunBody =>
      'parkrunのアスリート番号（例：A123456）を入力してください。フィニッシュ履歴を取得し、新しい結果をランのリストに追加します。';

  @override
  String get integrationsParkrunFieldLabel => 'アスリート番号';

  @override
  String get integrationsImport => 'インポート';

  @override
  String get integrationsParkrunImporting => 'parkrunの結果をインポートしています…';

  @override
  String integrationsParkrunImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'parkrunの結果を$count件インポートしました。',
    );
    return '$_temp0';
  }

  @override
  String get integrationsParkrunNoneNew => '前回のインポート以降、新しいparkrunの結果はありません。';

  @override
  String integrationsImportFailed(Object error) {
    return 'インポートに失敗しました：$error';
  }

  @override
  String get integrationsStravaName => 'Strava';

  @override
  String get integrationsStravaConnectSubtitle => '接続してアクティビティを自動同期';

  @override
  String get integrationsStravaWaitingFirstSync => '接続済み · 初回同期を待機中';

  @override
  String integrationsStravaLastSync(String time) {
    return '接続済み · 最終同期 $time';
  }

  @override
  String get integrationsSyncNow => '今すぐ同期';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle => 'アスリート番号で結果をインポート';

  @override
  String get integrationsSignInTitle => 'サインインしてサービスを接続';

  @override
  String get integrationsSignInSubtitle =>
      '同期したアクティビティを履歴に取り込むには、Strava + parkrunにアカウントが必要です。';

  @override
  String get integrationsHealthConnectTitle => 'ランをHealth Connectに書き込む';

  @override
  String get integrationsHealthConnectSubtitle =>
      '完了した各ランをHealth Connectに送信し、Google Fit、Samsung Health、Fitbitなどに表示します。';

  @override
  String get integrationsHealthConnectDenied =>
      'Health Connectの権限が許可されていません — ランは書き込まれません。';

  @override
  String integrationsHrPairFailed(Object error) {
    return 'ペアリングに失敗しました：$error';
  }

  @override
  String get integrationsHrTitle => '心拍計';

  @override
  String get integrationsHrChecking => '確認中…';

  @override
  String integrationsHrPaired(String name) {
    return 'ペアリング済み：$name';
  }

  @override
  String get integrationsHrNotPaired => 'ストラップ未ペアリング — タップしてスキャン';

  @override
  String get integrationsHrForget => '削除';

  @override
  String get integrationsHrScanTitle => '心拍計をスキャン';

  @override
  String get integrationsHrScanHint => 'ストラップ／チェストバンドを起動してください。通常3〜8秒かかります。';

  @override
  String get integrationsHrScanEmpty =>
      'ストラップが見つかりません。近くにあり、起動していることを確認してください。';

  @override
  String integrationsHrRssi(int rssi) {
    return 'RSSI $rssi dBm';
  }

  @override
  String get proTitle => 'Pro とサポート';

  @override
  String proCouldNotOpen(Object error) {
    return '開けませんでした：$error';
  }

  @override
  String get proWelcome => 'Proへようこそ！特典を取得しています…';

  @override
  String get proPurchaseFailed => '購入に失敗しました。後でもう一度お試しください。';

  @override
  String get proRestoreNeedsSignIn =>
      '復元するには、RevenueCatが設定された状態でサインインしている必要があります。代わりにウェブのアップグレードページでサブスクリプションを管理してください。';

  @override
  String get proRestored => 'Proサブスクリプションを復元しました。';

  @override
  String get proRestoreNone => 'このストアアカウントに有効な購入が見つかりませんでした。';

  @override
  String get proRestoreFailed => '復元に失敗しました。後でもう一度お試しください。';

  @override
  String get proRestoreUnavailable => 'このビルドでは復元を利用できません。';

  @override
  String proSubscribeTitle(String price) {
    return 'Proに登録 — $price/月';
  }

  @override
  String get proSubscribeSubtitleConfigured =>
      '無制限のAIコーチ + 優先処理。設定 → サブスクリプションで解約するまで毎月自動更新されます。';

  @override
  String get proSubscribeSubtitleWeb =>
      'ブラウザでサブスクリプションポータルを開きます。解約するまで毎月自動更新されます。';

  @override
  String get proRegionalNote =>
      '米ドルで請求されます。利用可否はお住まいの国や支払い方法によって異なります — 一部の地域では決済代行業者が対応できません。';

  @override
  String get proRestorePurchases => '購入を復元';

  @override
  String get proRestorePurchasesSubtitle => '以前のインストールや別の端末の購入を再リンク';

  @override
  String get proManageSubscription => 'サブスクリプションを管理';

  @override
  String get proManageSubscriptionSubtitle => '解約、プラン変更、支払い方法の更新';

  @override
  String get proSupport => 'アプリを支援する';

  @override
  String get proSupportSubtitle => 'ブラウザで一回限りの寄付';

  @override
  String get licensesTitle => 'ライセンス';

  @override
  String get licensesVersion => 'バージョン';

  @override
  String get licensesOpenSource => 'オープンソースライセンス';

  @override
  String get licensesOpenSourceSubtitle => 'このアプリに同梱されているサードパーティパッケージ';

  @override
  String get devicesTitle => 'デバイス';

  @override
  String get devicesRenameTitle => 'デバイス名を変更';

  @override
  String get devicesCancel => 'キャンセル';

  @override
  String get devicesSave => '保存';

  @override
  String devicesRenameFailed(Object error) {
    return '名前の変更に失敗しました：$error';
  }

  @override
  String get devicesRemoveTitle => 'デバイスを削除しますか？';

  @override
  String get devicesRemoveBodyCurrent =>
      'これは現在使用中のデバイスです。削除するとデバイスごとの設定オーバーライドが消去されますが、デバイスはサインインしたままです。';

  @override
  String get devicesRemoveBodyOther =>
      'デバイスのエントリとデバイスごとの設定オーバーライドを削除します。デバイスは次回アプリを開くまでサインインしたままです。';

  @override
  String get devicesRemove => '削除';

  @override
  String devicesRemoveFailed(Object error) {
    return '削除に失敗しました：$error';
  }

  @override
  String devicesSaveFailed(Object error) {
    return '保存に失敗しました：$error';
  }

  @override
  String get devicesLoadError => 'デバイスを読み込めませんでした。';

  @override
  String get devicesEmpty => 'まだデバイスがありません — サインインした状態でアプリを初めて開いたときに登録されます。';

  @override
  String get devicesThisDevice => 'このデバイス';

  @override
  String devicesLastSeen(String time) {
    return '最終アクセス $time';
  }

  @override
  String devicesOverrideCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'オーバーライド $count 件',
    );
    return '$_temp0';
  }

  @override
  String get devicesJustNow => 'たった今';

  @override
  String devicesMinutesAgo(int minutes) {
    return '$minutes分前';
  }

  @override
  String devicesHoursAgo(int hours) {
    return '$hours時間前';
  }

  @override
  String devicesDaysAgo(int days) {
    return '$days日前';
  }

  @override
  String get devicesRename => '名前を変更';

  @override
  String get devicesEditOverrides => 'オーバーライドを編集…';

  @override
  String get devicesEveryKeySet =>
      'オーバーライド可能なキーはすべて設定済みです。別のキーを追加する前に1つ削除してください。';

  @override
  String get devicesOverridesSheetTitle => 'デバイスごとのオーバーライド';

  @override
  String get devicesOverridesSheetDesc => 'これらのキーは、この端末でのみ共通設定を上書きします。';

  @override
  String get devicesNoOverrides => 'この端末にオーバーライドはありません。';

  @override
  String get devicesAddOverride => 'オーバーライドを追加';

  @override
  String get devicesPickKey => 'キーを選択';

  @override
  String get devicesEnterWholeNumber => '整数を入力してください。';

  @override
  String get devicesEnterNumber => '数値を入力してください（例：0.8）。';

  @override
  String get devicesValue => '値';

  @override
  String get devicesBack => '戻る';

  @override
  String get devicesAdd => '追加';

  @override
  String get devicesKeyPreferredUnitLabel => '優先する単位';

  @override
  String get devicesKeyPreferredUnitHint => 'すべての表示で使う距離の単位。';

  @override
  String get devicesKeyDefaultActivityLabel => 'デフォルトのアクティビティ';

  @override
  String get devicesKeyDefaultActivityHint => 'スタート画面であらかじめ選択されるアクティビティ。';

  @override
  String get devicesKeyMapStyleLabel => '地図スタイル';

  @override
  String get devicesKeyMapStyleHint => '地図ビューのMapLibreスタイル。';

  @override
  String get devicesKeyPaceFormatLabel => 'ペース形式';

  @override
  String get devicesKeyPaceFormatHint => 'ペースの表示形式。';

  @override
  String get devicesKeyVoiceFeedbackLabel => '音声フィードバック';

  @override
  String get devicesKeyVoiceFeedbackHint => 'ラン中にペース・距離のアナウンスを読み上げます。';

  @override
  String get devicesKeyVoiceIntervalLabel => '音声フィードバックの間隔（km）';

  @override
  String get devicesKeyVoiceIntervalHint => '読み上げアナウンスの間隔。';

  @override
  String get devicesKeyHapticLabel => '触覚フィードバック';

  @override
  String get devicesKeyHapticHint => 'ラップやペースゾーンの変化時に振動します。';

  @override
  String get devicesKeyKeepScreenOnLabel => '画面をオンのままにする';

  @override
  String get devicesKeyKeepScreenOnHint => '記録中はOSの自動減光を無効にします。';

  @override
  String get gearTitle => 'ギア';

  @override
  String get gearAddGear => 'ギアを追加';

  @override
  String get gearDeleteTitle => 'ギアを削除しますか？';

  @override
  String gearDeleteBody(String name) {
    return '「$name」を削除しますか？過去のランの走行距離履歴が失われます。記録を残すには代わりに引退させてください。';
  }

  @override
  String get gearCancel => 'キャンセル';

  @override
  String get gearDelete => '削除';

  @override
  String get gearDeletedOffline => 'ローカルで削除しました — 再接続時に同期されます。';

  @override
  String gearAttached(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$nameを$count件のランに紐付けました。',
    );
    return '$_temp0';
  }

  @override
  String gearOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'オフライン — $count件の編集をキューに登録、キャッシュされたギアを表示中。',
    );
    return '$_temp0';
  }

  @override
  String get gearOfflineCached => 'オフライン — キャッシュされたギアを表示中。';

  @override
  String get gearShoes => 'シューズ';

  @override
  String get gearBikes => 'バイク';

  @override
  String get gearRetired => '引退済み';

  @override
  String get gearEmptyShoes => 'まだシューズがありません';

  @override
  String get gearEmptyBikes => 'まだバイクがありません';

  @override
  String get gearEmptySubtitle => '1足追加すると走行距離を記録し、交換のリマインダーを受け取れます。';

  @override
  String gearRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ラン',
    );
    return '$_temp0';
  }

  @override
  String get gearWearDue => 'そろそろ交換';

  @override
  String get gearWearWorn => '交換距離を超過';

  @override
  String get gearRetire => '引退させる';

  @override
  String get gearRestore => '復帰させる';

  @override
  String get privacyZonesTitle => 'プライバシーゾーン';

  @override
  String get privacyZonesSaved => 'プライバシーゾーンを保存しました。';

  @override
  String privacyZonesSaveFailed(Object error) {
    return '保存に失敗しました：$error';
  }

  @override
  String privacyZonesLocationUnavailable(Object error) {
    return '位置情報を利用できません：$error';
  }

  @override
  String get privacyZonesSave => '保存';

  @override
  String get privacyZonesLocateMe => '現在地を取得';

  @override
  String get privacyZonesHint =>
      '地図をタップしてゾーンを追加します。公開面のトラックは、ゾーン半径を超える開始部分と終了部分が切り取られます。';

  @override
  String get privacyZonesSearchHint => '場所を検索…';

  @override
  String get privacyZonesRadius => '半径';

  @override
  String privacyZonesRadiusMeters(int meters) {
    return '$meters m';
  }

  @override
  String privacyZonesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ゾーン $count 件 — マーカーをタップして削除します。',
    );
    return '$_temp0';
  }

  @override
  String get privacyZonesClearAll => 'すべて消去';

  @override
  String get prefsTitle => '環境設定';

  @override
  String get prefsUnitMetric => 'km、m';

  @override
  String get prefsUnitImperial => 'mi、ft';

  @override
  String prefsSyncedSuffix(String base) {
    return '$base · 他の端末と同期済み';
  }

  @override
  String get prefsClear => 'クリア';

  @override
  String get prefsCancel => 'キャンセル';

  @override
  String get prefsSave => '保存';

  @override
  String get prefsSplitInterval => 'スプリット間隔';

  @override
  String get prefsSplitIntervalDefault => 'デフォルト';

  @override
  String get prefsSplitIntervalDefaultSubtitle => 'デフォルト（ランニングは1km、サイクリングは5km）';

  @override
  String get prefsLivePaceAlert => 'ライブペースアラート';

  @override
  String get prefsLivePaceAlertMin => '分';

  @override
  String get prefsLivePaceAlertSec => '秒';

  @override
  String get prefsLivePaceAlertOff => 'オフ — ペースを設定すると、ラン中に音声アラートを受け取れます';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — ラン中に30秒以上ずれたら音声でアラート';
  }

  @override
  String get prefsActivityRun => 'ラン';

  @override
  String get prefsActivityWalk => 'ウォーク';

  @override
  String get prefsActivityHike => 'ハイク';

  @override
  String get prefsActivityCycle => 'サイクリング';

  @override
  String get prefsPaceFormat => 'ペース形式';

  @override
  String get prefsPaceFormatMinPerKm => '分/km';

  @override
  String get prefsPaceFormatMinPerMi => '分/マイル';

  @override
  String get prefsPaceFormatKph => 'km/h';

  @override
  String get prefsPaceFormatMph => 'mph';

  @override
  String get prefsWeightUnit => '重量単位';

  @override
  String get prefsWeightUnitKg => 'キログラム (kg)';

  @override
  String get prefsWeightUnitLbs => 'ポンド (lbs)';

  @override
  String get prefsNotSet => '未設定';

  @override
  String prefsHrZonesSummary(String zones) {
    return '$zones bpm';
  }

  @override
  String prefsWeeklyGoalSummary(String distance, String unit) {
    return '$distance $unit / 週';
  }

  @override
  String get prefsMapStyle => '地図スタイル';

  @override
  String get prefsMapStyleStreets => 'ストリート';

  @override
  String get prefsMapStyleSatellite => '衛星';

  @override
  String get prefsMapStyleOutdoors => 'アウトドア';

  @override
  String get prefsMapStyleDark => 'ダーク';

  @override
  String get prefsDefaultRunVisibility => 'ランのデフォルト公開範囲';

  @override
  String get prefsCoachPersonality => 'コーチの性格';

  @override
  String get prefsCoachSupportive => '支援的';

  @override
  String get prefsCoachDrillSergeant => '鬼軍曹';

  @override
  String get prefsCoachAnalytical => '分析的';

  @override
  String get prefsSectionNotifications => '通知';

  @override
  String get prefsEmailNotifications => 'メール通知';

  @override
  String get prefsEmailNotifAll => 'すべて';

  @override
  String get prefsEmailNotifImportant => '重要なものだけ';

  @override
  String get prefsEmailNotifOff => 'オフ';

  @override
  String get prefsWeekStart => '週の開始曜日';

  @override
  String get prefsWeekStartMonday => '月曜日';

  @override
  String get prefsWeekStartSunday => '日曜日';

  @override
  String get prefsDefaultActivity => 'デフォルトのアクティビティ';

  @override
  String get prefsDateOfBirth => '生年月日';

  @override
  String get prefsRestingHr => '安静時心拍数';

  @override
  String get prefsMaxHr => '最大心拍数';

  @override
  String get prefsMaxHrNotSet => '未設定 — 208 − 0.7 × 年齢で代替';

  @override
  String prefsHrBpm(int bpm) {
    return '$bpm bpm';
  }

  @override
  String get prefsHrZones => '心拍ゾーン';

  @override
  String get prefsHrZonesDialogTitle => '心拍ゾーン（上限、bpm）';

  @override
  String get prefsWeeklyGoal => '週間走行距離の目標';

  @override
  String get prefsSectionActivityRecording => 'アクティビティと記録';

  @override
  String get prefsSectionTrainingDemographics => 'トレーニングと属性情報';

  @override
  String get prefsSectionPrivacySharing => 'プライバシーと共有';

  @override
  String get prefsSectionAiCoach => 'AIコーチ';

  @override
  String get prefsSignInToEdit => '複数の端末で同期されるプロフィールレベルの設定を編集するには、サインインしてください。';

  @override
  String get prefsUseMiles => 'マイルを使用';

  @override
  String get prefsDarkMode => 'ダークモード';

  @override
  String get prefsAudioCues => '音声キュー';

  @override
  String get prefsAudioCuesSubtitle => 'スプリットの読み上げアナウンス';

  @override
  String get prefsMinimalVoiceCues => '最小限の音声キュー';

  @override
  String get prefsMinimalVoiceCuesSubtitle => 'おしゃべりなレップ途中やペースのずれの通知を省きます';

  @override
  String get prefsKeepScreenOn => '画面をオンのままにする';

  @override
  String get prefsKeepScreenOnSubtitle => 'ラン中はウェイクロックを保持します';

  @override
  String get prefsAdvancedGps => '高度なGPS';

  @override
  String get prefsAdvancedGpsSubtitle => '高精度、より細かいトラック、バッテリー消費増';

  @override
  String get prefsDefaultRunPrivacy => 'ランのデフォルトプライバシー';

  @override
  String get prefsStravaAutoShare => 'Stravaへ自動共有';

  @override
  String get prefsStravaAutoShareSubtitle =>
      '新しいランをすべてStravaに自動送信します。実装後はStrava連携の接続が必要です。';

  @override
  String get prefsDiscoverable => '名前検索に表示する';

  @override
  String get prefsDiscoverableSubtitle =>
      'オフにすると、他のランナーが表示名で検索してもアカウントは表示されません。公開ランとプロフィールはURLを知っている人なら誰でもアクセスできます。';

  @override
  String get dashboardCoachTooltip => 'コーチ';

  @override
  String get dashboardFeedTooltip => 'アクティビティフィード';

  @override
  String get dashboardRecapTooltip => 'ランニングの一年';

  @override
  String get dashboardProfileTooltip => 'マイプロフィール';

  @override
  String get dashboardWelcomeTitle => 'ようこそ！';

  @override
  String get dashboardWelcomeBody =>
      'ランを記録したり、目標を設定したり、履歴をインポートすると、ダッシュボードが充実します。';

  @override
  String get dashboardSetGoal => '目標を設定';

  @override
  String get dashboardImportRuns => 'ランをインポート';

  @override
  String get dashboardPeriodWeek => '週';

  @override
  String get dashboardPeriodMonth => '月';

  @override
  String get dashboardPeriodAllTime => '全期間';

  @override
  String get dashboardSectionStreak => '連続記録';

  @override
  String get dashboardSectionLast20Weeks => '直近20週間';

  @override
  String get dashboardSectionRecentLifts => '最近の筋トレ';

  @override
  String get dashboardViewAllGym => 'すべて表示';

  @override
  String get dashboardSectionPersonalBests => '自己ベスト';

  @override
  String get dashboardLongestRun => '最長ラン';

  @override
  String dashboardFastestDistance(String distance) {
    return '最速の$distance';
  }

  @override
  String get dashboardGoals => '目標';

  @override
  String get dashboardAdd => '追加';

  @override
  String get dashboardGoalWeekly => '毎週';

  @override
  String get dashboardGoalMonthly => '毎月';

  @override
  String dashboardGoalTitleFallback(String period) {
    return '$periodの目標';
  }

  @override
  String get dashboardSetWeeklyGoalA11y => '週間ランニング目標を設定';

  @override
  String get dashboardSetFirstGoal => '最初の目標を設定';

  @override
  String get dashboardSetFirstGoalBody => '週ごと・月ごとに距離、時間、ペース、ラン回数を記録できます。';

  @override
  String get dashboardGoalTapToEdit => 'タップして編集';

  @override
  String get dashboardGoalComplete => '達成。';

  @override
  String get dashboardGoalInProgress => '進行中。';

  @override
  String dashboardGoalA11y(String period, String title, String status) {
    return '$periodの目標 — $title $status';
  }

  @override
  String dashboardRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のラン',
    );
    return '$_temp0';
  }

  @override
  String dashboardVert(String value) {
    return '獲得標高 $value';
  }

  @override
  String dashboardPeriodSummaryA11y(
    String label,
    String distance,
    String runs,
    String elevation,
  ) {
    return '$labelのサマリー、$runsで$distance$elevation';
  }

  @override
  String dashboardElevationGainSuffix(String value) {
    return '、獲得標高 $value';
  }

  @override
  String get dashboardStreakCurrent => '現在';

  @override
  String get dashboardStreakHistory => '履歴';

  @override
  String get dashboardStreakDayUnit => '日';

  @override
  String get dashboardStreakDaysUnit => '日';

  @override
  String dashboardStreakBest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最高 $count 日',
    );
    return '$_temp0';
  }

  @override
  String get dashboardStreakAllTimeBest => '歴代最高';

  @override
  String get dashboardStreakRestart => '今日走って再開しよう';

  @override
  String get dashboardStreakStart => '今日走って始めよう';

  @override
  String get dashboardHeatmapLess => '少ない';

  @override
  String get dashboardHeatmapMore => '多い';

  @override
  String get dashboardHeatmapTapHint => '週をタップするとサマリーを表示';

  @override
  String get periodWeeklySummary => '週間サマリー';

  @override
  String get periodMonthlySummary => '月間サマリー';

  @override
  String get periodAllTimeSummary => '全期間サマリー';

  @override
  String get periodShareTooltip => '共有';

  @override
  String get periodPreviousTooltip => '前へ';

  @override
  String get periodNextTooltip => '次へ';

  @override
  String get periodSwitchToWeekly => 'タップして週間表示に切り替え';

  @override
  String get periodSwitchToMonthly => 'タップして月間表示に切り替え';

  @override
  String get periodSwitchToAllTime => 'タップして全期間表示に切り替え';

  @override
  String get periodStatDistance => '距離';

  @override
  String get periodStatRuns => 'ラン';

  @override
  String get periodStatTime => '時間';

  @override
  String get periodStatAvgPace => '平均ペース';

  @override
  String get periodEmptyWeek => '今週はランがありません';

  @override
  String get periodEmptyMonth => '今月はランがありません';

  @override
  String get periodShareSummary => 'サマリーを共有';

  @override
  String get periodShareText => 'テキスト';

  @override
  String get periodShareImage => '画像';

  @override
  String get periodShareImageFailed => '共有画像を作成できませんでした';

  @override
  String get periodShareCardTagline => 'ベターランナー';

  @override
  String get periodShareStatDistance => '距離';

  @override
  String get periodShareStatRuns => 'ラン';

  @override
  String get periodShareStatTime => '時間';

  @override
  String get periodShareStatAvgPace => '平均ペース';

  @override
  String get trainingLoadTitle => 'フィットネス・疲労・調子';

  @override
  String trainingLoadSubtitleHr(int days) {
    return '過去$days日間の心拍TRIMP。';
  }

  @override
  String get trainingLoadSubtitleVolume =>
      '走行量ベース — 設定で安静時・最大心拍を入力し、ストラップで記録するとTRIMPに切り替わります。';

  @override
  String get trainingLoadEmpty => '数回ランを記録するとフィットネスの推移が見られます。';

  @override
  String get trainingLoadLegendFitness => 'フィットネス';

  @override
  String get trainingLoadLegendFatigue => '疲労';

  @override
  String get trainingLoadLegendForm => '調子';

  @override
  String trainingLoadLegendEntry(String label, int value) {
    return '$label · $value';
  }

  @override
  String get trainingLoadReadingLoaded => '負荷が高い — 無理なく続けて、準備ができたら回復しよう。';

  @override
  String get trainingLoadReadingTapered => '調整済み — ハードな練習でも問題なし。';

  @override
  String get trainingLoadReadingBalanced => 'バランス良好 — 楽な日もハードな日もお好みで。';

  @override
  String get trainingLoadIncludesLifts => 'ジムのセッションを含む — 筋力トレーニングも疲労に加算されます。';

  @override
  String get intensityTitle => 'トレーニング強度';

  @override
  String intensityWindow(int days) {
    return '直近$days日';
  }

  @override
  String intensityBasedOn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のラン',
    );
    return '心拍記録のある$_temp0に基づく';
  }

  @override
  String get mileageTitle => '走行距離';

  @override
  String get mileageWeek => '週';

  @override
  String get mileageMonth => '月';

  @override
  String get mileageYear => '年';

  @override
  String get mileageThisWeek => '今週';

  @override
  String get mileageThisMonth => '今月';

  @override
  String get mileageThisYear => '今年';

  @override
  String get fitnessTitle => 'フィットネス';

  @override
  String get fitnessStatVo2Max => 'VO₂ max';

  @override
  String get fitnessStatVo2MaxTooltip => '有酸素能力の指標：1分間に体が使える酸素量。高いほど高フィットネス。';

  @override
  String get fitnessStatVdot => 'VDOT';

  @override
  String get fitnessStatVdotTooltip =>
      'ダニエルズのランニングフィットネススコア。直近のベスト走から算出し、トレーニングペースを決定します。';

  @override
  String get fitnessStatRuns => 'ラン';

  @override
  String get fitnessStatRunsTooltip => 'フィットネス推定に反映できる十分な長さの直近のラン。';

  @override
  String get fitnessStatCtl => 'フィットネス (CTL)';

  @override
  String get fitnessStatCtlTooltip => '42日間移動平均のトレーニング負荷。ゆっくり積み上がる持久力の土台。';

  @override
  String get fitnessStatAtl => '疲労 (ATL)';

  @override
  String get fitnessStatAtlTooltip => '直近7日間の負荷。ハードな練習で急上昇し、休養で下がります。';

  @override
  String get fitnessStatTsb => '調子 (TSB)';

  @override
  String get fitnessStatTsbTooltip =>
      'フィットネスから疲労を引いた値。プラス＝好調でレース向き、マイナス＝疲労が残る。';

  @override
  String get runSocialActivity => 'アクティビティ';

  @override
  String get runSocialNoComments => 'まだコメントはありません。';

  @override
  String get runSocialReplyHint => '返信を入力…';

  @override
  String get runSocialCommentHint => 'コメントを追加…';

  @override
  String get runSocialRunnerFallback => 'ランナー';

  @override
  String get runSocialReply => '返信';

  @override
  String get runSocialDelete => '削除';

  @override
  String get runSocialDeleteCommentTitle => 'このコメントを削除しますか？';

  @override
  String get runSocialDeleteCommentMessage => 'このコメントは完全に削除されます。元に戻せません。';

  @override
  String get runSocialPost => '投稿';

  @override
  String get runSocialCancel => 'キャンセル';

  @override
  String runSocialKudosError(String error) {
    return '称賛を更新できませんでした: $error';
  }

  @override
  String runSocialPostError(String error) {
    return '投稿に失敗しました: $error';
  }

  @override
  String runSocialDeleteError(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get runPhotosLoading => '写真を読み込み中…';

  @override
  String get runPhotosTitle => '写真';

  @override
  String get runPhotosAdd => '写真を追加';

  @override
  String get runPhotosCaptionPendingHint => 'キャプション（任意、280文字）';

  @override
  String get runPhotosCaptionHint => 'キャプション…';

  @override
  String get runPhotosCancel => 'キャンセル';

  @override
  String get runPhotosSave => '保存';

  @override
  String get runPhotosUpload => 'アップロード';

  @override
  String get runPhotosUploading => 'アップロード中…';

  @override
  String get runPhotosEditCaption => 'キャプションを編集';

  @override
  String get runPhotosDeleteTooltip => '写真を削除';

  @override
  String get runPhotosDeleteTitle => '写真を削除しますか？';

  @override
  String get runPhotosDeleteBody => 'この操作で写真はランから完全に削除されます。';

  @override
  String get runPhotosDeleteConfirm => '削除';

  @override
  String runPhotosPickerError(String error) {
    return 'ピッカーを開けませんでした: $error';
  }

  @override
  String runPhotosUploadError(String error) {
    return 'アップロードに失敗しました: $error';
  }

  @override
  String runPhotosDeleteError(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String runPhotosCaptionError(String error) {
    return 'キャプションを更新できませんでした: $error';
  }

  @override
  String get runSegEffortsChecking => 'セグメントを確認中…';

  @override
  String get runSegEffortsNoRoute =>
      'セグメントはルートごとに対応します。このランを保存済みルートに紐付けるとリーダーボードで競えます。';

  @override
  String get runSegEffortsEmpty => 'このランにセグメント記録はありません。';

  @override
  String get workoutReviewTitle => 'ワークアウト';

  @override
  String get workoutReviewColStep => 'ステップ';

  @override
  String get workoutReviewColPlan => '計画';

  @override
  String get workoutReviewColActual => '実績';

  @override
  String get workoutReviewColPace => 'ペース';

  @override
  String get workoutReviewColDelta => 'Δ';

  @override
  String get workoutReviewSkip => 'スキップ';

  @override
  String get workoutReviewLabelWarmup => 'ウォームアップ';

  @override
  String get workoutReviewLabelCooldown => 'クールダウン';

  @override
  String get workoutReviewLabelSteady => '一定';

  @override
  String get workoutReviewLabelRep => 'レップ';

  @override
  String workoutReviewLabelRepN(int index, int total) {
    return 'レップ $index/$total';
  }

  @override
  String get workoutReviewLabelRecovery => '回復';

  @override
  String workoutReviewLabelRecoveryN(int index, int total) {
    return '回復 $index/$total';
  }

  @override
  String get workoutReviewLabelWalk => 'ウォーク';

  @override
  String workoutReviewLabelWalkN(int index, int total) {
    return 'ウォーク $index/$total';
  }

  @override
  String get segmentsPanelTitle => 'セグメント';

  @override
  String get segmentsPanelNew => '新しいセグメント';

  @override
  String get segmentsPanelCancel => 'キャンセル';

  @override
  String get segmentsPanelLoading => 'セグメントを読み込み中…';

  @override
  String get segmentsPanelEmpty => 'このルートにはまだセグメントがありません。';

  @override
  String get segmentsPanelNameLabel => '名前';

  @override
  String get segmentsPanelNameHint => '悪夢の登り';

  @override
  String get segmentsPanelStartLabel => '開始 (m)';

  @override
  String get segmentsPanelEndLabel => '終了 (m)';

  @override
  String segmentsPanelRouteHint(int metres) {
    return 'ルートは $metres m';
  }

  @override
  String get segmentsPanelCreate => '作成';

  @override
  String get segmentsPanelDeleteTooltip => 'セグメントを削除';

  @override
  String get segmentsPanelDeleteTitle => 'セグメントを削除しますか？';

  @override
  String segmentsPanelDeleteBody(String name) {
    return '「$name」が削除されます。';
  }

  @override
  String get segmentsPanelDeleteConfirm => '削除';

  @override
  String get segmentsPanelErrEndAfterStart => '終了は開始より大きくする必要があります';

  @override
  String get segmentsPanelErrMinLength => 'セグメントは少なくとも 100 m 必要です';

  @override
  String segmentsPanelCreateError(String error) {
    return 'セグメントを作成できませんでした: $error';
  }

  @override
  String segmentsPanelDeleteError(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get segmentsPanelAllGenders => 'すべての性別';

  @override
  String get segmentsPanelGenderMen => '男性';

  @override
  String get segmentsPanelGenderWomen => '女性';

  @override
  String get segmentsPanelGenderNonbinary => 'ノンバイナリー';

  @override
  String get segmentsPanelAllAges => 'すべての年齢';

  @override
  String get segmentsPanelResetFilters => 'リセット';

  @override
  String get segmentsPanelLeaderboardLoading => '読み込み中…';

  @override
  String get segmentsPanelLeaderboardEmptyFiltered =>
      'この絞り込みに一致する記録はありません。条件を広げてみてください。';

  @override
  String get segmentsPanelLeaderboardEmpty => 'まだ記録がありません。このセグメントを最初に走りましょう。';

  @override
  String segmentsPanelCrownBanner(String label) {
    return 'あなたがこの王冠を保持しています — $label。';
  }

  @override
  String get segmentsPanelRunnerFallback => 'ランナー';

  @override
  String get goalEditorTitleNew => '新しい目標';

  @override
  String get goalEditorTitleEdit => '目標を編集';

  @override
  String get goalEditorNameLabel => '名前（任意）';

  @override
  String get goalEditorNameHint => '例：ベース走行';

  @override
  String get goalEditorPeriod => '期間';

  @override
  String get goalEditorThisWeek => '今週';

  @override
  String get goalEditorThisMonth => '今月';

  @override
  String get goalEditorTargets => '目標値';

  @override
  String get goalEditorTargetsHelp => '任意の組み合わせを設定できます。空欄は無視されます。';

  @override
  String get goalEditorTargetDistance => '距離';

  @override
  String get goalEditorTargetTime => '時間';

  @override
  String get goalEditorTargetPace => '平均ペース';

  @override
  String get goalEditorTargetRuns => 'ラン数';

  @override
  String get goalEditorSuffixMin => '分';

  @override
  String get goalEditorSuffixRuns => 'ラン';

  @override
  String get goalEditorDelete => '削除';

  @override
  String get goalEditorDeleteTitle => 'この目標を削除しますか？';

  @override
  String get goalEditorDeleteMessage => 'この目標と進捗の記録が削除されます。いつでも新しく作成できます。';

  @override
  String get goalEditorCancel => 'キャンセル';

  @override
  String get goalEditorSave => '保存';

  @override
  String get goalEditorErrDistance => '距離：正の数を入力してください';

  @override
  String get goalEditorErrTime => '時間：正の分数を入力してください';

  @override
  String get goalEditorErrPace => 'ペース：mm:ss 形式で入力（例 5:00）';

  @override
  String get goalEditorErrRuns => 'ラン数：正の整数を入力してください';

  @override
  String get goalEditorErrNoTarget => '少なくとも 1 つの目標を設定してください';

  @override
  String get goalEditorSavedAnnounce => '目標を保存しました';

  @override
  String get goalEditorDeletedAnnounce => '目標を削除しました';

  @override
  String get eventFormTitle => '新しいイベント';

  @override
  String get eventFormTitleLabel => 'タイトル';

  @override
  String get eventFormStartsAt => '開始';

  @override
  String get eventFormDescriptionLabel => '説明（任意）';

  @override
  String get eventFormMeetLabel => '集合場所（任意）';

  @override
  String get eventFormMeetHint => '登山口の駐車場';

  @override
  String get eventFormDistanceLabel => '距離 (km)';

  @override
  String get eventFormDurationLabel => '所要時間 (分)';

  @override
  String get eventFormRecurrence => '繰り返し';

  @override
  String get eventFormRecurOneOff => '1回のみ';

  @override
  String get eventFormRecurWeekly => '毎週';

  @override
  String get eventFormRecurBiweekly => '隔週';

  @override
  String get eventFormRecurMonthly => '毎月';

  @override
  String get eventFormCancel => 'キャンセル';

  @override
  String get eventFormCreate => 'イベントを作成';

  @override
  String get clubFormTitle => '新しいクラブ';

  @override
  String get clubFormNameLabel => '名前';

  @override
  String get clubFormDescriptionLabel => '説明（任意）';

  @override
  String get clubFormLocationLabel => '場所（任意）';

  @override
  String get clubFormLocationHint => 'エディンバラ, 英国';

  @override
  String get clubFormPublic => '公開';

  @override
  String get clubFormPrivate => '非公開';

  @override
  String get clubFormJoinPolicy => '参加ポリシー';

  @override
  String get clubFormJoinOpen => 'オープン — 誰でも参加可';

  @override
  String get clubFormJoinRequest => 'リクエスト — 管理者が承認';

  @override
  String get clubFormJoinInvite => '招待制のみ';

  @override
  String get clubFormCancel => 'キャンセル';

  @override
  String get clubFormCreate => '作成';

  @override
  String get clubFormErrSlug => '名前には少なくとも 1 文字または数字が必要です。';

  @override
  String get clubFormErrUnreachable =>
      '現在サーバーに接続できません。接続を確認するかサインインして、もう一度お試しください。';

  @override
  String get reportReasonSpam => 'スパム';

  @override
  String get reportReasonHarassment => '嫌がらせまたは虐待';

  @override
  String get reportReasonInappropriate => '不適切なコンテンツ';

  @override
  String get reportReasonImpersonation => 'なりすまし';

  @override
  String get reportReasonOther => 'その他';

  @override
  String get reportSuccess => '報告を送信しました — レビューのための報告ありがとうございます。';

  @override
  String get reportTitleUser => 'ユーザーを報告';

  @override
  String get reportTitleClub => 'クラブを報告';

  @override
  String get reportTitleRoute => 'ルートを報告';

  @override
  String get reportTitleContent => 'コンテンツを報告';

  @override
  String get reportDisclaimer =>
      '報告はモデレーターに送られます。虚偽の報告も審査対象です。コミュニティガイドラインに違反するコンテンツのみ報告してください。';

  @override
  String get reportReason => '理由';

  @override
  String get reportNotesLabel => 'メモ（任意）';

  @override
  String get reportCancel => 'キャンセル';

  @override
  String get reportSubmit => '報告を送信';

  @override
  String get reportErrDuplicate => 'このコンテンツに対する保留中の報告がすでにあります。';

  @override
  String gearBackfillTitle(String gear) {
    return '過去のランを $gear に紐付けますか？';
  }

  @override
  String gearBackfillBody(int count, String activity) {
    return '購入後に $activity のアクティビティが $count 件見つかりました。着用していないものはチェックを外してください。';
  }

  @override
  String get gearBackfillActivityCycling => 'サイクリング';

  @override
  String get gearBackfillActivityRunning => 'ランニング';

  @override
  String get gearBackfillSelectNone => '選択を解除';

  @override
  String get gearBackfillSelectAll => 'すべて選択';

  @override
  String gearBackfillSelectedCount(int selected, int total) {
    return '$total 件中 $selected 件';
  }

  @override
  String get gearBackfillSkip => 'スキップ';

  @override
  String get gearBackfillAttaching => '紐付け中…';

  @override
  String gearBackfillAttach(int count) {
    return '$count 件を紐付け';
  }

  @override
  String gearBackfillAttachError(String error) {
    return '紐付けに失敗しました: $error';
  }

  @override
  String get workoutEditTitle => 'ワークアウトを編集';

  @override
  String get workoutEditKindLabel => '種類';

  @override
  String get workoutEditDistanceLabel => '目標距離 (km)';

  @override
  String get workoutEditDistanceHint => '例：8.0';

  @override
  String get workoutEditPaceLabel => '目標ペース (mm:ss /km)';

  @override
  String get workoutEditPaceHint => '例：5:30';

  @override
  String get workoutEditNotesLabel => 'メモ';

  @override
  String get workoutEditCancel => 'キャンセル';

  @override
  String get workoutEditSave => '保存';

  @override
  String get workoutEditErrDistance => '正の距離を km で入力してください';

  @override
  String get workoutEditErrPace => 'ペースは 5:30 の形式で入力してください';

  @override
  String workoutEditSaveError(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String upcomingEventBadge(String relative) {
    return '参加予定 · $relative';
  }

  @override
  String get upcomingEventStartingNow => 'まもなく開始';

  @override
  String upcomingEventInMinutes(int count) {
    return '$count 分後';
  }

  @override
  String get upcomingEventInOneHour => '1 時間後';

  @override
  String upcomingEventInHours(int count) {
    return '$count 時間後';
  }

  @override
  String get upcomingEventTomorrow => '明日';

  @override
  String upcomingEventInDays(int count) {
    return '$count 日後';
  }

  @override
  String get todaysWorkoutDone => '本日完了';

  @override
  String get todaysWorkoutToday => '今日のワークアウト';

  @override
  String get errorStateRetry => '再試行';

  @override
  String get shareCardRunTitle => 'ランを共有';

  @override
  String get shareCardExport => 'エクスポート';

  @override
  String get shareCardImage => '画像';

  @override
  String get shareCardStatDistance => '距離';

  @override
  String get shareCardStatTime => '時間';

  @override
  String get shareCardStatPace => 'ペース';

  @override
  String get shareCardStatSpeed => '速度';

  @override
  String get shareCardBrandRun => 'RUN';

  @override
  String get shareCardImageError => '共有画像を作成できませんでした';

  @override
  String get shareCardFileError => 'ファイルをエクスポートできませんでした';

  @override
  String get shareCardRouteTitle => 'ルートを共有';

  @override
  String get shareCardRouteShareImage => '画像を共有';

  @override
  String get shareCardRouteCapturing => 'キャプチャ中…';

  @override
  String get shareCardRouteStatDistance => '距離';

  @override
  String get shareCardRouteStatClimb => '獲得標高';

  @override
  String get billingToday => '今日';

  @override
  String get billingYesterday => '昨日';

  @override
  String billingDaysAgo(int count) {
    return '$count 日前';
  }

  @override
  String billingRenewalFailed(String relative) {
    return 'Pro の更新が $relative に失敗しました。';
  }

  @override
  String get billingRenewalBody => 'カードを更新しないと Free にダウングレードされます。';

  @override
  String get billingManage => '管理';

  @override
  String get planCalendarPrevMonth => '前の月';

  @override
  String get planCalendarNextMonth => '次の月';

  @override
  String runGearChipsLoadError(String error) {
    return 'ギアの読み込みに失敗しました: $error';
  }

  @override
  String get runGearChipsPickerTitle => 'このランで使用したギアをタグ付け';

  @override
  String get runGearChipsEmpty => 'ギアがまだ登録されていません。設定 → ギア で追加してください。';

  @override
  String get runGearChipsCancel => 'キャンセル';

  @override
  String get runGearChipsSave => '保存';

  @override
  String get runGearChipsTag => '+ ギアをタグ付け';

  @override
  String get runGearChipsEdit => '編集';

  @override
  String runGearChipsSaveError(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get gearFormTitleEdit => 'ギアを編集';

  @override
  String get gearFormTitleAddShoes => 'シューズを追加';

  @override
  String get gearFormTitleAddBike => 'バイクを追加';

  @override
  String get gearFormNameLabel => '名前';

  @override
  String get gearFormNameHint => 'Pegasus 39';

  @override
  String get gearFormBrandLabel => 'ブランド';

  @override
  String get gearFormModelLabel => 'モデル';

  @override
  String get gearFormBoughtLabel => '購入日';

  @override
  String get gearFormBoughtPick => 'タップして選択';

  @override
  String gearFormRetireAt(String unit) {
    return '交換目安 ($unit)';
  }

  @override
  String get gearFormRetireHint => '500';

  @override
  String get gearFormNotesLabel => 'メモ';

  @override
  String get gearFormCancel => 'キャンセル';

  @override
  String get gearFormSaving => '保存中…';

  @override
  String get gearFormSave => '保存';

  @override
  String get gearFormAdd => '追加';

  @override
  String gearFormSaveError(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get notificationBellTooltip => '通知';

  @override
  String get liveRunMapWaitingGps => 'GPS を待っています...';

  @override
  String get liveRunMapRecentre => '現在地に再センタリング';

  @override
  String get ttsRunStarted => 'ランを開始しました';

  @override
  String ttsRunComplete(String distance, int mins) {
    return 'ラン完了。$mins分で$distance。';
  }

  @override
  String get ttsOffRoute => 'ルートから外れています';

  @override
  String get ttsPaceAlertFast => 'ペースを上げましょう';

  @override
  String get ttsPaceAlertSlow => 'ペースを落としましょう';

  @override
  String get ttsWorkoutComplete => 'ワークアウト完了。お疲れさまでした。';

  @override
  String get ttsStepHalfway => 'このレップの折り返しです';

  @override
  String get ttsStepLastFifty => '残り五十メートル';

  @override
  String ttsPaceDriftAhead(int delta) {
    return '少し緩めましょう — $delta秒速すぎます。';
  }

  @override
  String ttsPaceDriftBehind(int delta) {
    return '少し上げましょう — $delta秒遅れています。';
  }

  @override
  String ttsSpeedKm(String value) {
    return '速度、時速$valueキロメートル';
  }

  @override
  String ttsSpeedMi(String value) {
    return '速度、時速$valueマイル';
  }

  @override
  String ttsPaceKm(int min, int sec) {
    return 'ペース、1キロメートルあたり$min分$sec秒';
  }

  @override
  String ttsPaceMi(int min, int sec) {
    return 'ペース、1マイルあたり$min分$sec秒';
  }

  @override
  String ttsDistanceKm(String value) {
    return '$valueキロメートル';
  }

  @override
  String ttsDistanceMetres(int value) {
    return '$valueメートル';
  }

  @override
  String ttsDistanceMileSingular(String value) {
    return '$valueマイル';
  }

  @override
  String ttsDistanceMiles(String value) {
    return '$valueマイル';
  }

  @override
  String ttsDistanceYards(int value) {
    return '$valueヤード';
  }

  @override
  String ttsSplit(String count, String unit, String tail) {
    return '$count$unit。$tail';
  }

  @override
  String get ttsStepWarmup => 'ウォームアップ';

  @override
  String get ttsStepRecovery => 'リカバリー';

  @override
  String get ttsStepSteady => '一定ペース';

  @override
  String get ttsStepCooldown => 'クールダウン';

  @override
  String get ttsStepRep => 'レップ';

  @override
  String get ttsStepRun => 'ラン';

  @override
  String get ttsStepWalk => 'ウォーク';

  @override
  String ttsStepRepOf(int index, int total) {
    return 'レップ $total本中$index本目';
  }

  @override
  String ttsStepRunOf(int index, int total) {
    return 'ラン $total本中$index本目';
  }

  @override
  String ttsStepWalkOf(int index, int total) {
    return 'ウォーク $total本中$index本目';
  }

  @override
  String ttsStepPaceKm(int min, int sec) {
    return '1キロメートルあたり$min分$sec秒';
  }

  @override
  String ttsStepPaceKmWhole(int min) {
    return '1キロメートルあたり$min分';
  }

  @override
  String ttsStepPaceMi(int min, int sec) {
    return '1マイルあたり$min分$sec秒';
  }

  @override
  String ttsStepPaceMiWhole(int min) {
    return '1マイルあたり$min分';
  }

  @override
  String ttsDurationSeconds(int sec) {
    return '$sec秒';
  }

  @override
  String ttsDurationMinutes(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: '$min分',
    );
    return '$_temp0';
  }

  @override
  String ttsDurationMinutesSeconds(String minutes, int sec) {
    return '$minutes$sec秒';
  }

  @override
  String ttsStepDuration(String intro, String duration) {
    return '$intro。$duration。';
  }

  @override
  String ttsStepDistancePace(String intro, String distance, String pace) {
    return '$intro。$distanceを$paceで。';
  }

  @override
  String get guidedEasy30Title => '30分イージーラン';

  @override
  String get guidedEasy30Subtitle => 'コーチの声 · 30分 · イージーな強度';

  @override
  String get guidedEasy30Description =>
      'リカバリーの日や頭をすっきりさせたいときに、会話できるペースでリラックスして走るランです。コーチが5分ごとにそっと声をかけます。';

  @override
  String get guidedEasy30Cue0 => 'さあ行きましょう。イージーに始めて — これがリカバリーペースです。';

  @override
  String get guidedEasy30Cue1 => '5分経過。肩の力を抜いて。会話できるペースを保ちましょう。';

  @override
  String get guidedEasy30Cue2 => '10分。ケイデンスを確認 — 速い足運び、軽い着地。';

  @override
  String get guidedEasy30Cue3 => '折り返しです。まだ走りながら話せるはずです。';

  @override
  String get guidedEasy30Cue4 => '20分。呼吸に意識を — 鼻からゆっくり吸って、口から吐きます。';

  @override
  String get guidedEasy30Cue5 => '残り5分。リラックスを保って。ペースを上げないで。';

  @override
  String get guidedEasy30Cue6 => '残り1分。イージーに仕上げましょう。';

  @override
  String get guidedEasy30Cue7 => '完了。1分ほど歩いてクールダウン。お見事です。';

  @override
  String get guidedTempo25Title => '25分テンポビルダー';

  @override
  String get guidedTempo25Subtitle => 'コーチの声 · 25分 · 5-15-5';

  @override
  String get guidedTempo25Description =>
      '5分のイージーなウォームアップ、15分のテンポ（ややきつい）、5分のクールダウン。週の定番テンポセッションです。';

  @override
  String get guidedTempo25Cue0 => 'ウォームアップの時間です。5分イージーに — 脚を目覚めさせましょう。';

  @override
  String get guidedTempo25Cue1 => 'ウォームアップ残り1分。ケイデンスを上げて。';

  @override
  String get guidedTempo25Cue2 => 'テンポに上げましょう。ややきつく。10キロのレース強度くらいです。';

  @override
  String get guidedTempo25Cue3 => 'テンポ5分経過。力強く、でもコントロールして。リズムを保ちましょう。';

  @override
  String get guidedTempo25Cue4 => 'テンポ10分完了。ペースを維持しましょう。';

  @override
  String get guidedTempo25Cue5 => 'テンポ残り2分。スムーズに。';

  @override
  String get guidedTempo25Cue6 => '力を抜いて。5分イージーにクールダウン。';

  @override
  String get guidedTempo25Cue7 => '残り2分。心拍を落ち着かせましょう。';

  @override
  String get guidedTempo25Cue8 => '完了。歩いてストレッチを。素晴らしい出来です。';

  @override
  String get guidedFirst15Title => '初心者向け15分ラン／ウォーク';

  @override
  String get guidedFirst15Subtitle => 'コーチの声 · 15分 · ラン／ウォークのインターバル';

  @override
  String get guidedFirst15Description =>
      'ランニングは初めて？1分ラン・1分ウォークを3セット、さらにウォームアップとクールダウン。やさしい入り口です。みんなここから始めます。';

  @override
  String get guidedFirst15Cue0 => 'まずは3分の速歩きでウォームアップしましょう。';

  @override
  String get guidedFirst15Cue1 => '1分のイージーランに切り替え。会話できるペースで。';

  @override
  String get guidedFirst15Cue2 => '1分歩きましょう。';

  @override
  String get guidedFirst15Cue3 => '1分走りましょう。';

  @override
  String get guidedFirst15Cue4 => '1分歩きましょう。';

  @override
  String get guidedFirst15Cue5 => '1分走りましょう。';

  @override
  String get guidedFirst15Cue6 => '1分歩きましょう。';

  @override
  String get guidedFirst15Cue7 => '1分走りましょう — 最後の1本です。';

  @override
  String get guidedFirst15Cue8 => '歩いて落ち着けましょう。5分のクールダウン。';

  @override
  String get guidedFirst15Cue9 => '残り1分。イージーに歩きましょう。';

  @override
  String get guidedFirst15Cue10 => '完了。これは立派なランでした。またすぐに走りに出ましょう。';

  @override
  String guidedRunMinutesBadge(int minutes) {
    return '$minutes分';
  }

  @override
  String guidedRunCueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ラン中に$count件のキュー',
    );
    return '$_temp0';
  }

  @override
  String get guidedRunFullScript => '全スクリプト';

  @override
  String get guidedRunPreviewCue => 'キューを試聴';

  @override
  String guidedRunPreviewError(String error) {
    return '試聴できませんでした: $error';
  }

  @override
  String get ttsSplitUnitKilometre => 'キロメートル';

  @override
  String get ttsSplitUnitKilometres => 'キロメートル';

  @override
  String get ttsSplitUnitMile => 'マイル';

  @override
  String get ttsSplitUnitMiles => 'マイル';

  @override
  String get workoutKindEasy => 'イージー';

  @override
  String get workoutKindLong => 'ロング走';

  @override
  String get workoutKindRecovery => 'リカバリー';

  @override
  String get workoutKindTempo => 'テンポ';

  @override
  String get workoutKindInterval => 'インターバル';

  @override
  String get workoutKindMarathonPace => 'マラソンペース';

  @override
  String get workoutKindWalkRun => 'ウォークラン';

  @override
  String get workoutKindRace => 'レース';

  @override
  String get workoutKindRest => '休養';

  @override
  String get planPhaseBase => 'ベース';

  @override
  String get planPhaseBuild => 'ビルド';

  @override
  String get planPhasePeak => 'ピーク';

  @override
  String get planPhaseTaper => 'テーパリング';

  @override
  String get planPhaseRace => 'レース週';

  @override
  String get runBackgroundLocationNudgeTitle => '位置情報を常に許可';

  @override
  String get runBackgroundLocationNudgeBody =>
      'Android はアプリが開いている間だけ位置情報を許可しました。画面がオフのときも距離を正確に記録するには、設定で位置情報のアクセスを「常に許可」にしてください。このまま開始することもできます。アプリが画面に表示されている間は記録が機能します。';

  @override
  String get runBatteryOptHintTitle => 'バックグラウンドでも記録を継続';

  @override
  String get runBatteryOptHintBody =>
      '一部のスマートフォン（Samsung、Xiaomi、OnePlus など）は、バッテリーを節約するためにアプリをスリープさせることがあり、画面がオフのときに長距離ランの記録が止まる場合があります。念のため、設定でこのアプリをバッテリー最適化の対象から除外してください。ランはいずれにせよ記録されます。これはシステムが記録を途中で止めるのを防ぐだけです。';

  @override
  String shareCardCaption(Object title, Object distance, Object duration) {
    return '$title — $durationで$distance';
  }

  @override
  String get settingsBackendNotConfigured => 'バックエンドが構成されていません';

  @override
  String get settingsAccountSignedIn => 'サインイン済み';

  @override
  String get settingsDevicesSignedOutSubtitle => 'デバイスを管理するにはサインインしてください';

  @override
  String get verifiedClubTooltip => '公式認証済みクラブ';

  @override
  String get raceDistance5k => '5km';

  @override
  String get raceDistance10k => '10km';

  @override
  String get raceDistanceHalfMarathon => 'ハーフマラソン';

  @override
  String get raceDistanceMarathon => 'マラソン';

  @override
  String get settingsTabAccountSubtitle => 'サインイン、バックアップ、アカウント削除';

  @override
  String get settingsTabPreferencesSubtitle => '単位、テーマ、記録、トレーニング、プライバシー';

  @override
  String get settingsTabIntegrationsSubtitle => 'Strava、parkrun、心拍センサー';

  @override
  String get settingsTabDevicesSubtitle => 'サインイン中のデバイスとデバイスごとの設定';

  @override
  String get settingsTabGearSubtitle => 'シューズ・バイクとアイテムごとの走行距離を記録';

  @override
  String get settingsTabCoachingSubtitle => 'アスリートを指導したり、自分のコーチをフォロー';

  @override
  String get settingsTabProSubtitle => '登録、購入の復元、請求の管理';

  @override
  String get settingsTabLicensesSubtitle => 'アプリのバージョンとオープンソースの通知';

  @override
  String periodSummaryWeekOf(Object date) {
    return '$dateの週';
  }

  @override
  String periodShareRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ラン',
    );
    return '$_temp0';
  }

  @override
  String periodShareAvgPace(Object pace) {
    return '平均ペース: $pace';
  }

  @override
  String get gymTitle => 'ジム';

  @override
  String get gymLog => 'ワークアウトを記録';

  @override
  String get gymUntitled => '無題のワークアウト';

  @override
  String get gymOfflineCached => 'オフライン：保存済みのワークアウトを表示中';

  @override
  String get gymOfflineQueued => 'オフライン：変更は後で同期されます';

  @override
  String get gymEmptyTitle => 'ジムのワークアウトがまだありません';

  @override
  String get gymEmptyBody => 'トレーニングを記録すると、ここで管理でき、トレーニング負荷にも反映されます。';

  @override
  String get gymPrBadge => 'PR';

  @override
  String gymExercisesShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 種目',
    );
    return '$_temp0';
  }

  @override
  String gymVolumeShort(int volume) {
    return '$volume kg';
  }

  @override
  String get gymNotFound => 'ワークアウトが見つかりません。';

  @override
  String get gymEdit => '編集';

  @override
  String get gymDelete => '削除';

  @override
  String get gymPublic => '公開';

  @override
  String get gymPrivate => '非公開';

  @override
  String get gymMakePublic => '公開にする';

  @override
  String get gymMakePrivate => '非公開にする';

  @override
  String gymVisibilityFailed(Object error) {
    return '公開設定を更新できませんでした: $error';
  }

  @override
  String get gymNotes => 'メモ';

  @override
  String get gymKg => 'kg';

  @override
  String get gymReps => '回数';

  @override
  String get gymRpe => 'RPE';

  @override
  String get gymDuration => '時間 (秒)';

  @override
  String gymDurationValue(String seconds) {
    return '$seconds秒';
  }

  @override
  String gymSetN(int n) {
    return 'セット $n';
  }

  @override
  String get gymPrWeight => '最高重量';

  @override
  String get gymPrVolume => '最高ボリューム';

  @override
  String get gymPrE1rm => '推定1RM最高';

  @override
  String get gymRecordsLink => '記録';

  @override
  String get gymRecordsTitle => '自己ベスト';

  @override
  String get gymRecordsSubtitle => '重量種目ごとのあなたのベスト記録。';

  @override
  String get gymRecordsEmpty => '重量種目の記録はまだありません。セットに重量を入力すると自己ベストの記録が始まります。';

  @override
  String gymRecordsLastDone(String date) {
    return '最終 $date';
  }

  @override
  String gymRecordsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countセッション',
    );
    return '$_temp0';
  }

  @override
  String get gymExerciseBack => '記録に戻る';

  @override
  String get gymExerciseEmpty => 'この種目の履歴はまだありません。';

  @override
  String gymSinceFirstUp(String delta) {
    return '初回から+$delta';
  }

  @override
  String gymSinceFirstDown(String delta) {
    return '初回から−$delta';
  }

  @override
  String get gymSinceFirstFlat => '初回から変化なし';

  @override
  String gymDetailLastTime(String date) {
    return '前回 $date';
  }

  @override
  String get gymVolumeLabel => 'ボリューム';

  @override
  String get gymDeleteConfirmTitle => 'ワークアウトを削除しますか？';

  @override
  String get gymDeleteConfirmBody => 'ワークアウトとそのセットが完全に削除されます。';

  @override
  String get clubEventLogAsWorkout => 'ワークアウトとして記録';

  @override
  String get clubEventLogAsWorkoutHint =>
      'このクラスを自分のジムログに追加します — 保存前に詳細を調整できます。';

  @override
  String get clubEventLogAsWorkoutSaved => 'ジムログに追加しました';

  @override
  String get gymEditorNewTitle => '新しいワークアウト';

  @override
  String get gymEditorEditTitle => 'ワークアウトを編集';

  @override
  String get gymEditorTitleLabel => 'タイトル（任意）';

  @override
  String get gymEditorTitlePlaceholder => '例：プッシュの日';

  @override
  String get gymEditorExercisePlaceholder => '種目名';

  @override
  String get gymEditorRemoveExercise => '種目を削除';

  @override
  String get gymEditorRemoveSet => 'セットを削除';

  @override
  String get gymEditorAddSet => 'セットを追加';

  @override
  String get gymEditorAddExercise => '種目を追加';

  @override
  String get gymEditorShare => 'フィードに共有';

  @override
  String get gymEditorCancel => 'キャンセル';

  @override
  String get gymEditorSave => 'ワークアウトを保存';

  @override
  String get gymEditorNeedExercise => '名前付きの種目を少なくとも1つ追加してください。';

  @override
  String get gymSaveFailed => 'ワークアウトを保存できませんでした。';

  @override
  String get gymRoutineLink => 'ルーティン';

  @override
  String get gymRoutineTitle => 'ルーティン';

  @override
  String get gymRoutineNew => '新しいルーティン';

  @override
  String get gymRoutineBack => 'ルーティンに戻る';

  @override
  String get gymRoutineNotFound => 'ルーティンが見つかりません。';

  @override
  String gymRoutineExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count種目',
    );
    return '$_temp0';
  }

  @override
  String get gymRoutineStart => 'ルーティンを開始';

  @override
  String get gymRoutineDelete => '削除';

  @override
  String get gymRoutineDeleteConfirmTitle => 'ルーティンを削除しますか？';

  @override
  String get gymRoutineDeleteConfirmBody =>
      'ルーティンを完全に削除します。記録済みのワークアウトには影響しません。';

  @override
  String get gymRoutineDeleted => 'ルーティンを削除しました';

  @override
  String get gymRoutineCreated => 'ルーティンを保存しました';

  @override
  String get gymRoutineSaveFailed => 'ルーティンを保存できませんでした。';

  @override
  String get gymRoutineEmptyTitle => 'まだルーティンがありません';

  @override
  String get gymRoutineEmptyBody => '記録したワークアウトをルーティンとして保存するか、新規作成して再利用しましょう。';

  @override
  String get gymRoutineTargetReps => '目標レップ数';

  @override
  String gymRoutineTargetWeight(String unit) {
    return '目標重量（$unit）';
  }

  @override
  String get gymRoutineEditorNewTitle => '新しいルーティン';

  @override
  String get gymRoutineEditorTitleLabel => 'ルーティン名';

  @override
  String get gymRoutineEditorTitlePlaceholder => '例：プッシュデーA';

  @override
  String get gymRoutineEditorNotesLabel => 'メモ（任意）';

  @override
  String get gymRoutineEditorSave => 'ルーティンを保存';

  @override
  String get gymRoutineEditorCancel => 'キャンセル';

  @override
  String get gymRoutineEditorNeedTitle => 'ルーティンに名前を付けてください。';

  @override
  String get gymRoutineEditorNeedExercise => '名前付きの種目を少なくとも1つ追加してください。';

  @override
  String get gymRoutineSaveAsRoutine => 'ルーティンとして保存';

  @override
  String get gymRoutineRepeatLast => '前回を繰り返す';

  @override
  String get gymRoutineTargetRepsMax => '〜';

  @override
  String get gymRoutineTargetDuration => '目標時間（秒）';

  @override
  String get gymRoutineTargetDistance => '目標距離（m）';

  @override
  String get gymRoutineRestLabel => '休憩（秒）';

  @override
  String get gymRoutineSetType => 'セットタイプ';

  @override
  String get gymRoutineSetTypeWarmup => 'ウォームアップ';

  @override
  String get gymRoutineSetTypeWorking => 'ワーキング';

  @override
  String get gymRoutineSetTypeDropset => 'ドロップセット';

  @override
  String get gymRoutineSetTypeAmrap => 'AMRAP';

  @override
  String get gymRoutineSetTypeFailure => '限界まで';

  @override
  String get gymRoutineSetTypeBackoff => 'バックオフ';

  @override
  String get gymRoutineModality => '計測方法';

  @override
  String get gymRoutineModalityWeightReps => '重量 × 回数';

  @override
  String get gymRoutineModalityTime => '時間';

  @override
  String get gymRoutineModalityDistance => '距離';

  @override
  String get gymRoutineModalityBodyweightReps => '自重の回数';

  @override
  String get gymRoutineSupersetToggle => '次の種目とスーパーセット';

  @override
  String gymRoutineSupersetBadge(int group) {
    return 'スーパーセット $group';
  }

  @override
  String get gymRoutineAdvanced => '詳細';

  @override
  String get gymRoutineProgression => '漸進';

  @override
  String get gymRoutineProgressionNone => 'なし';

  @override
  String get gymRoutineProgressionLinear => 'リニア';

  @override
  String get gymRoutineProgressionDoubleProgression => 'ダブルプログレッション';

  @override
  String get gymRoutineProgressionFiveByFive => '5×5';

  @override
  String get gymRoutineProgressionPercentCycle => '1RMの%サイクル';

  @override
  String get gymRoutineProgressionRpeAutoreg => 'RPE自動調整';

  @override
  String gymRoutineProgressionIncrementLabel(String unit) {
    return '重量ステップ（$unit）';
  }

  @override
  String get gymRoutineProgressionPercentLabel => '1RMの%';

  @override
  String gymRoutineProgressionOneRmLabel(String unit) {
    return '1RM（$unit）';
  }

  @override
  String get gymRoutineProgressionTargetRpeLabel => '目標RPE';

  @override
  String get gymRoutineNextTarget => '次の目標';

  @override
  String get gymRoutineNextTargetIncreaseWeight => '次回は重量を上げる';

  @override
  String get gymRoutineNextTargetIncreaseReps => '次回は回数を増やす';

  @override
  String get gymRoutineNextTargetHold => '維持 — この目標を繰り返す';

  @override
  String get gymRoutineNextTargetDeload => 'ディロード — 重量を下げる';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return '回数アップ $from→$to';
  }

  @override
  String get nutritionTitle => '栄養';

  @override
  String get nutritionLogFood => '食事を記録';

  @override
  String get nutritionCalories => 'カロリー';

  @override
  String get nutritionProtein => 'たんぱく質';

  @override
  String get nutritionCarbs => '炭水化物';

  @override
  String get nutritionFat => '脂質';

  @override
  String get nutritionWater => '水分';

  @override
  String get nutritionWaterAdd => '水分を追加';

  @override
  String get nutritionWaterRemove => '水分を減らす';

  @override
  String get nutritionNoTargets =>
      'カロリー・マクロの目標を表示するには、ウェブアプリで身長・体重・年齢・性別を入力してください。';

  @override
  String get nutritionWeeklyTrend => '直近7日間';

  @override
  String nutritionCaloriesLeft(int n) {
    return '残り $n kcal';
  }

  @override
  String nutritionCaloriesOver(int n) {
    return '$n kcal 超過';
  }

  @override
  String get nutritionOnTarget => '目標達成';

  @override
  String nutritionMacroOver(int n) {
    return '$n 超過';
  }

  @override
  String get nutritionMacroReached => '目標達成';

  @override
  String nutritionWaterAmount(String consumed, String target) {
    return '$consumed / $target L';
  }

  @override
  String get nutritionWaterGoalReached => '目標達成';

  @override
  String nutritionWaterRemaining(int n) {
    return '残り $n ml';
  }

  @override
  String get nutritionWeekOnGoal => '目標どおり';

  @override
  String nutritionWeekUnderGoal(int n) {
    return '目標より1日 $n 少ない';
  }

  @override
  String nutritionWeekOverGoal(int n) {
    return '目標より1日 $n 多い';
  }

  @override
  String get nutritionGoalLine => '1日の目標';

  @override
  String nutritionGoalBreakdown(int base, int exercise) {
    return '目標 $base + 本日消費 $exercise kcal';
  }

  @override
  String get dashGymReadinessIncluded => '最近のジムのセッションは疲労に反映されています。';

  @override
  String get dashGymReadinessExcluded => 'ジムの負荷はランの準備度から除外されています。';

  @override
  String get prefsExcludeGymFromReadiness => 'ジムの負荷をランの準備度から除外する';

  @override
  String get prefsExcludeGymFromReadinessHint =>
      'デフォルトでは、ジムのセッションはランと同様に疲労を増やし準備度を下げます。フィットネス・疲労・フォームをランのみに基づかせるにはこれをオンにしてください。';

  @override
  String get nutritionEmptyTitle => '今日はまだ何も記録していません';

  @override
  String get nutritionEmptyBody => '食事を記録してカロリーとマクロを管理しましょう。';

  @override
  String get nutritionSlotBreakfast => '朝食';

  @override
  String get nutritionSlotLunch => '昼食';

  @override
  String get nutritionSlotDinner => '夕食';

  @override
  String get nutritionSlotSnack => '間食';

  @override
  String get nutritionMealProtein => 'タンパク質';

  @override
  String get nutritionMealCarbs => '炭水化物';

  @override
  String get nutritionMealFat => '脂質';

  @override
  String get nutritionMealItemsHeading => '項目';

  @override
  String get nutritionMealNoItems => 'この食事の記録はありません。';

  @override
  String get nutritionMealTrendHeading => '過去7日間';

  @override
  String get nutritionDelete => '削除';

  @override
  String get nutritionDeleteEntryTitle => 'この項目を削除しますか？';

  @override
  String nutritionDeleteEntryMessage(String item) {
    return '$item を今日の記録から削除します。';
  }

  @override
  String get nutritionOfflineQueued => 'オフライン — 再接続時に変更を同期します';

  @override
  String get nutritionOfflineCached => 'オフライン — 保存済みの記録を表示しています';

  @override
  String get nutritionLogTitle => '食事を記録';

  @override
  String get nutritionSearchHint => '食品を検索';

  @override
  String get nutritionSearching => '検索中…';

  @override
  String get nutritionNoResults => '一致する項目がありません。別の語で検索するか、下から手動で入力してください。';

  @override
  String get nutritionMealSlot => '食事区分';

  @override
  String get nutritionManualEntry => '手動で入力';

  @override
  String get nutritionItemName => '名称';

  @override
  String get nutritionPortionGrams => '分量（g）';

  @override
  String get nutritionAdd => '追加';

  @override
  String get nutritionCancel => 'キャンセル';

  @override
  String get sessionTitle => 'セッション';

  @override
  String get sessionEmpty => 'セッションプランはまだありません。';

  @override
  String get sessionEmptyHint => '再利用できるヨガ・ピラティス・クラスのシーケンスをウェブで作成しましょう。';

  @override
  String get sessionUntitled => '無題のセッション';

  @override
  String get sessionNotFound => 'セッションプランが見つかりません。';

  @override
  String get sessionMakePublic => '公開する';

  @override
  String get sessionMakePrivate => '非公開にする';

  @override
  String get sessionVisibilityError => '公開設定を変更できませんでした。';

  @override
  String get sessionSteps => 'シーケンス';

  @override
  String sessionStepHold(Object name, Object seconds) {
    return '$name・キープ $seconds秒';
  }

  @override
  String sessionStepReps(Object name, Object reps) {
    return '$name・$reps回';
  }

  @override
  String sessionStepFlow(Object name, Object seconds) {
    return '$name・フロー $seconds秒';
  }

  @override
  String sessionSideLeft(Object name) {
    return '$name（左）';
  }

  @override
  String sessionSideRight(Object name) {
    return '$name（右）';
  }

  @override
  String sessionEstDuration(Object minutes) {
    return '約 $minutes 分';
  }

  @override
  String get gymSessionStart => 'セッションを開始';

  @override
  String gymSessionStep(Object exercise, Object set, Object total) {
    return '$exercise・セット $set/$total';
  }

  @override
  String get gymSessionComplete => 'セッション完了';

  @override
  String get gymSessionSkipSet => 'セットをスキップ';

  @override
  String get gymSessionRewind => '前へ';

  @override
  String get gymSessionAbandon => '中止';

  @override
  String get gymSessionFinish => '完了';

  @override
  String get gymSessionDiscardTitle => 'セッションを破棄しますか？';

  @override
  String get gymSessionDiscardBody => 'このセッションの進捗は保存されません。';

  @override
  String get gymSessionDiscardConfirm => '破棄';

  @override
  String get gymSessionSaved => 'ワークアウトを保存しました';

  @override
  String get gymSessionSaveFailed => 'ワークアウトを保存できませんでした';

  @override
  String gymSessionSetProgress(Object done, Object total) {
    return '$done/$total';
  }

  @override
  String get gymSessionLogSet => 'セットを完了';

  @override
  String get gymSessionRest => '休憩';

  @override
  String gymSessionRestRemaining(Object seconds) {
    return '休憩 残り$seconds秒';
  }

  @override
  String get gymSessionRestSkip => '休憩をスキップ';

  @override
  String get gymSessionTarget => '目標';

  @override
  String gymReviewAdherence(Object pct) {
    return '達成率 $pct%';
  }

  @override
  String get gymReviewVerdictCompleted => '完了';

  @override
  String get gymReviewVerdictPartial => '一部完了';

  @override
  String get gymReviewVerdictAbandoned => '中止';

  @override
  String get gymReviewStatusHit => '達成';

  @override
  String get gymReviewStatusPartial => '一部';

  @override
  String get gymReviewStatusMissed => '未達成';

  @override
  String get gymReviewStatusExtra => '追加';

  @override
  String get sessionRunStart => 'セッションを開始';

  @override
  String sessionRunStep(Object name) {
    return '$name';
  }

  @override
  String get sessionRunDone => '完了';

  @override
  String get sessionRunSkip => 'スキップ';

  @override
  String get sessionRunPause => '一時停止';

  @override
  String get sessionRunResume => '再開';

  @override
  String get sessionRunAbandon => '中止';

  @override
  String get sessionRunFinish => '終了';

  @override
  String sessionRunRemaining(Object seconds) {
    return '$seconds秒';
  }

  @override
  String get sessionRunComplete => 'セッション完了';

  @override
  String get sessionRunSaved => 'セッションを保存しました';

  @override
  String get sessionRunSaveFailed => 'セッションを保存できませんでした';

  @override
  String get sessionRunDiscardTitle => 'セッションを破棄しますか？';

  @override
  String get sessionRunDiscardBody => 'このセッションの進捗は保存されません。';

  @override
  String get sessionRunDiscardConfirm => '破棄';

  @override
  String get sessionRunVerdictCompleted => '完了';

  @override
  String get sessionRunVerdictPartial => '一部完了';

  @override
  String get sessionRunVerdictAbandoned => '中止';

  @override
  String sessionRunStepCount(int index, int total) {
    return 'ステップ $index / $total';
  }

  @override
  String get sessionRunSwitchSides => '反対側に切り替え';

  @override
  String get coachingTitle => 'コーチング';

  @override
  String get coachingLede =>
      '招待リンクを共有してアスリートを指導し、トレーニングを確認できます。あるいは自分のコーチをここでフォローできます。';

  @override
  String get coachingCancel => 'キャンセル';

  @override
  String get coachingMyAthletes => '担当アスリート';

  @override
  String get coachingMyAthletesSub => '招待を承認したランナー';

  @override
  String get coachingInviteAnAthlete => 'アスリートを招待';

  @override
  String get coachingCreating => '作成中…';

  @override
  String get coachingPendingInvite => '保留中の招待';

  @override
  String coachingPendingInviteSub(String date) {
    return '$date に作成 · 未承認';
  }

  @override
  String get coachingCopyLink => 'リンクをコピー';

  @override
  String get coachingShareLink => 'リンクを共有';

  @override
  String get coachingRevoke => '取り消す';

  @override
  String get coachingNoAthletes => 'まだアスリートがいません。招待して始めましょう。';

  @override
  String get coachingRunner => 'ランナー';

  @override
  String coachingCoachingSince(String date) {
    return '$date から指導';
  }

  @override
  String get coachingReview => '確認';

  @override
  String get coachingRemove => '削除';

  @override
  String get coachingMyCoaches => '自分のコーチ';

  @override
  String get coachingMyCoachesSub => 'あなたのトレーニングを見られるコーチ';

  @override
  String get coachingNoCoaches => 'まだコーチの招待を承認していません。';

  @override
  String get coachingCoach => 'コーチ';

  @override
  String coachingLinkedSince(String date) {
    return '$date から連携';
  }

  @override
  String get coachingLeave => '解除';

  @override
  String get coachingInviteLinkCopied => '招待リンクをコピーしました';

  @override
  String get coachingThisAthlete => 'このアスリート';

  @override
  String get coachingThisCoach => 'このコーチ';

  @override
  String get coachingRevokeTitle => '招待を取り消しますか？';

  @override
  String get coachingRevokeBody => '招待リンクは使えなくなります。新しいリンクはいつでも作成できます。';

  @override
  String get coachingRemoveAthleteTitle => 'アスリートを削除しますか？';

  @override
  String coachingRemoveAthleteBody(String name) {
    return '$name の指導を終了しますか？そのランやプランへのアクセスができなくなります。';
  }

  @override
  String get coachingLeaveCoachTitle => 'コーチを解除しますか？';

  @override
  String coachingLeaveCoachBody(String name) {
    return '$name とのトレーニング共有を停止しますか？';
  }

  @override
  String coachingLoadError(String error) {
    return 'コーチングを読み込めませんでした: $error';
  }

  @override
  String coachingCreateInviteError(String error) {
    return '招待を作成できませんでした: $error';
  }

  @override
  String coachingRevokeInviteError(String error) {
    return '招待を取り消せませんでした: $error';
  }

  @override
  String coachingRemoveAthleteError(String error) {
    return 'アスリートを削除できませんでした: $error';
  }

  @override
  String coachingEndLinkError(String error) {
    return '連携を終了できませんでした: $error';
  }

  @override
  String get coachingAthleteAthleteFallback => 'アスリート';

  @override
  String get coachingAthleteRunnerFallback => 'ランナー';

  @override
  String coachingAthleteCoachingSince(String date) {
    return '$date から指導';
  }

  @override
  String get coachingAthletePlanCompliance => 'プランの達成状況';

  @override
  String get coachingAthleteNoActivePlan => 'アクティブなトレーニングプランはありません。';

  @override
  String get coachingAthleteAssignTitle => 'プランを割り当てる';

  @override
  String coachingAthleteAssignHint(String name) {
    return 'あなたのプランから 1 つ選んで $name に割り当てます。';
  }

  @override
  String get coachingAthleteAssignSelectLabel => 'プラン';

  @override
  String get coachingAthleteAssignSelectPlaceholder => 'プランを選択…';

  @override
  String get coachingAthleteAssignStartLabel => '開始日';

  @override
  String get coachingAthleteAssigning => '割り当て中…';

  @override
  String get coachingAthleteAssignButton => 'プランを割り当てる';

  @override
  String get coachingAthleteAssignNoPlans =>
      '先にトレーニングプランを作成すると、アスリートに割り当てられます。';

  @override
  String get coachingAthleteAssignedByYou => 'あなたが割り当て';

  @override
  String get coachingAthleteCannotAssignHasPlan =>
      'このアスリートには既にアクティブなプランがあります。新しいプランを割り当てる前に、完了または終了する必要があります。';

  @override
  String get coachingAthleteComplete => '完了';

  @override
  String coachingAthleteDoneCount(int done, int total) {
    return '$total 件中 $done 件完了';
  }

  @override
  String coachingAthleteMissedCount(int n) {
    return '$n 件未実施';
  }

  @override
  String get coachingAthleteStatusDone => '完了';

  @override
  String get coachingAthleteStatusMissed => '未実施';

  @override
  String get coachingAthleteStatusUpcoming => '予定';

  @override
  String get coachingAthleteRecentRuns => '最近のラン';

  @override
  String get coachingAthleteNoRunsYet => 'まだ記録されたランがありません。';

  @override
  String get coachingAthletePrivate => '非公開';

  @override
  String coachingAthleteAssignSuccess(String name) {
    return '$name にプランを割り当てました';
  }

  @override
  String coachingAthleteLoadError(String error) {
    return 'アスリートを読み込めませんでした: $error';
  }
}
