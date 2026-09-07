// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

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
  String recapMonthShareHeadline(Object period) {
    return '$periodのランニング:';
  }

  @override
  String recapMonthShareSubject(Object period) {
    return '$periodの振り返り';
  }

  @override
  String get recapTitle => 'ランニングの1年';

  @override
  String get recapMonthTitle => 'ランニングの1か月';

  @override
  String get recapPeriodYear => '年';

  @override
  String get recapPeriodMonth => '月';

  @override
  String get recapShareTooltip => '振り返りを共有';

  @override
  String get recapPublishAndShare => '公開してリンクを共有';

  @override
  String get recapPublishFailed => 'まとめを公開できませんでした。もう一度お試しください。';

  @override
  String get recapPrevYear => '前の年';

  @override
  String get recapNextYear => '次の年';

  @override
  String get recapPrevMonth => '前の月';

  @override
  String get recapNextMonth => '次の月';

  @override
  String recapNoRunsForPeriod(Object period) {
    return '$periodは振り返るランがありません。';
  }

  @override
  String recapNoRunsYetInPeriod(Object period) {
    return '$periodはまだランがありません。記録すると振り返りが表示されます。';
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
  String importFailuresHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のアクティビティを取り込めませんでした',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresIntro =>
      'インポートをやり直すと再試行できます。取り込み済みのものはスキップされるため、重複は発生しません。';

  @override
  String importFailuresTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'さらに $count 件の失敗は記録されていません。',
    );
    return '$_temp0';
  }

  @override
  String get importFailuresShowDetail => '各アクティビティを表示';

  @override
  String get importFailuresShare => 'レポートを共有 (CSV)';

  @override
  String get importFailuresShareFailed => 'レポートを共有できませんでした。';

  @override
  String get importFailuresDismiss => '閉じる';

  @override
  String get importFailuresNoDate => '日付不明';

  @override
  String get importFailuresReasonNetwork => '接続が切断されました';

  @override
  String get importFailuresReasonAuth => 'サインアウト済み';

  @override
  String get importFailuresReasonRateLimited => 'レート制限';

  @override
  String get importFailuresReasonTooLarge => 'ファイルが大きすぎます';

  @override
  String get importFailuresReasonUnparseable => 'ファイルを読み取れません';

  @override
  String get importFailuresReasonRejected => 'サーバーに拒否されました';

  @override
  String get importFailuresReasonUnknown => '不明なエラー';

  @override
  String importStatusCloudPushDeferred(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のランをこの端末に保存しました。クラウドへのアップロードは完了していません。次回の同期時に再試行します。',
    );
    return '$_temp0';
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
  String importHealthRoutesWithheld(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'インポートしたアクティビティ$count件に、Threkirが読み取りを許可されていないGPS地図があります。',
    );
    return '${_temp0}Health Connectはワークアウトのルートを別の権限で保護しています。';
  }

  @override
  String get importHealthRoutesAllowButton => '地図のインポートを許可';

  @override
  String get importHealthRoutesRequesting => 'Health Connectに地図へのアクセスを要求中...';

  @override
  String get importHealthRoutesDenied =>
      '地図へのアクセスは許可されませんでした。インポートは概要のみのままです。Health Connectでいつでも変更できます。';

  @override
  String get importHealthRoutesAdding => 'インポートしたアクティビティに地図を追加中...';

  @override
  String importHealthRoutesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアクティビティに地図を追加しました。',
      zero: '地図を追加できませんでした。',
    );
    return '$_temp0';
  }

  @override
  String peopleFollowFailedBanner(Object error) {
    return 'フォローを更新できませんでした: $error';
  }

  @override
  String get peopleSearchHint => '名前でランナーを検索';

  @override
  String get peopleClearSearchTooltip => '検索をクリア';

  @override
  String get commonClearSearch => '検索をクリア';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get placeSearchNoResults => '場所が見つかりません';

  @override
  String get placeSearchUnavailable => '現在、場所の検索を利用できません';

  @override
  String get placeSearchRetry => '再試行';

  @override
  String get commonDismiss => '閉じる';

  @override
  String get settingsDevicesRemoveOverride => '上書き設定を削除';

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
  String get peopleNearbyHeader => '近くのランナー';

  @override
  String get peopleNearbySubtitle =>
      '設定したエリア付近で参加を選んだランナーです。表示はおよその距離のみで、リアルタイムの位置は含まれません。';

  @override
  String get peopleNearbyEmptyTitle => 'まだ近くに誰もいません';

  @override
  String get peopleNearbyEmptyBody =>
      '「近くのランナーに自分を表示」をオンにし、エリアを設定してください。同じ設定をしたランナーだけがあなたを見つけられます。';

  @override
  String get peopleNearbyEmptyAction => '環境設定を開く';

  @override
  String get peopleNearbyLoadFailed => '近くのランナーを読み込めませんでした。';

  @override
  String peopleNearbyWithin(String distance) {
    return '$distance以内';
  }

  @override
  String peopleNearbyBeyond(String distance) {
    return '$distanceより遠く';
  }

  @override
  String get prefsDiscoverableNearby => '近くのランナーに自分を表示';

  @override
  String get prefsDiscoverableNearbySubtitle =>
      '既定ではオフです。オンにすると、同じく参加を選んだ他のランナーに、あなたがおおよそ近くにいることが表示されます。表示されるのは設定したエリアからのおおよその距離だけで、現在地ではありません。';

  @override
  String get nearbyAreaTitle => 'あなたのエリア';

  @override
  String get nearbyAreaExplainer =>
      '走っている街や地区を選んでください。約1キロメートル単位に丸めて保存され、リアルタイムの位置情報は含まれません。他のランナーにはおおよその距離だけが表示され、エリア自体は表示されません。';

  @override
  String get nearbyAreaNone => 'エリア未設定';

  @override
  String nearbyAreaCurrent(String label) {
    return '現在のエリア: $label';
  }

  @override
  String get nearbyAreaSearchHint => '街や地区を検索';

  @override
  String get nearbyAreaSearchUnavailable => '現在、場所の検索を利用できません。';

  @override
  String get nearbyAreaNoResults => 'その検索に一致する場所はありません。';

  @override
  String get nearbyAreaSaved => 'エリアを保存しました';

  @override
  String get nearbyAreaSaveFailed => 'エリアを保存できませんでした。';

  @override
  String get nearbyAreaLoadFailed => 'エリアを読み込めませんでした。';

  @override
  String get nearbyAreaForget => 'エリアを削除';

  @override
  String get nearbyAreaForgetConfirmTitle => 'エリアを削除しますか？';

  @override
  String get nearbyAreaForgetConfirmBody => '再びエリアを設定するまで、近くのランナーに表示されなくなります。';

  @override
  String get nearbyAreaForgotten => 'エリアを削除しました';

  @override
  String get nearbyAreaForgetFailed => 'エリアを削除できませんでした。';

  @override
  String get peopleFallbackDisplayName => 'ランナー';

  @override
  String get peopleFollowingButton => 'フォロー中';

  @override
  String get peopleFollowButton => 'フォロー';

  @override
  String get peopleSignedOutMessage => '他のランナーを検索してフォローするにはサインインしてください';

  @override
  String get peopleSuggestionsLoadFailed => 'おすすめを読み込めませんでした。';

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
  String get runSurfaceLabel => 'ランセクション';

  @override
  String get runSurfaceTabPlans => 'プラン';

  @override
  String get runSurfaceTabRaces => 'レース';

  @override
  String get gymSurfaceLabel => 'ジムセクション';

  @override
  String get gymTabLog => 'ログ';

  @override
  String get gymTabRecords => '記録';

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
  String get bodyMetricsWithdrawTitle => '健康データの同意を撤回しますか？';

  @override
  String get bodyMetricsWithdrawBody => '保存された身長と体重の履歴がすべて完全に削除されます。元に戻せません。';

  @override
  String get bodyMetricsWithdrawConfirm => '撤回して削除';

  @override
  String get bodyMetricsSaved => '保存しました';

  @override
  String bodyMetricsSaveFailed(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String bodyMetricsPrefSaveFailed(String error) {
    return '保存できませんでした: $error';
  }

  @override
  String get bodyMetricsLoadError => '身体データを読み込めませんでした。';

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
  String get safetyAddHint => 'partner@example.com';

  @override
  String get safetyPhoneLabel => 'SMS用電話番号（任意）';

  @override
  String get safetyPhoneHint =>
      '携帯番号を追加すると、この連絡先はSMSでも通知を受け取れます。受け取るかどうかは承認時に本人が選びます。メール通知は常に送信されます。';

  @override
  String get safetyInvalidPhone => '電話番号は国際形式で入力してください（例: +447700900123）。';

  @override
  String get safetySmsBadge => 'SMS有効';

  @override
  String get safetySmsPending => 'SMS無効 — まだ同意されていません';

  @override
  String get safetyConfirmSmsLabel => 'SMSでも通知する';

  @override
  String get safetyContactOfTitle => 'あなたが緊急連絡先になっているランナー';

  @override
  String get safetyContactOfIntro =>
      'これらの人があなたを緊急連絡先に指定し、あなたが承認しました。通知方法の変更や辞退はいつでもできます。';

  @override
  String safetyContactOfFor(String name) {
    return '$name さんの緊急連絡先';
  }

  @override
  String get safetyContactOfSmsLabel => 'メールに加えてSMSでも通知する';

  @override
  String get safetyContactOfNoPhone =>
      'SMS通知にはあなたの携帯番号が必要ですが、登録されていません。メール通知は常に送信されます。';

  @override
  String get safetyContactOfSmsOnToast => 'SMS通知を有効にしました。';

  @override
  String get safetyContactOfSmsOffToast => 'SMS通知を無効にしました。';

  @override
  String get safetyContactOfSmsNoChange => 'この関係はすでに解除されています。相手が削除した可能性があります。';

  @override
  String safetyContactOfSmsFailed(String error) {
    return 'SMSの設定を変更できませんでした: $error';
  }

  @override
  String get safetyContactOfWithdraw => '辞退する';

  @override
  String get safetyContactOfWithdrawConfirm =>
      'このランナーの緊急連絡先をやめますか？相手はあなたに通知できなくなり、再び追加するには新しい依頼が必要になります。';

  @override
  String get safetyContactOfWithdrawnToast => '緊急連絡先ではなくなりました。';

  @override
  String safetyContactOfWithdrawFailed(String error) {
    return '辞退できませんでした: $error';
  }

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
  String safetyRemoveFailed(String error) {
    return '連絡先を削除できませんでした: $error';
  }

  @override
  String safetySettingSaveFailed(String error) {
    return '設定を保存できませんでした: $error';
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
  String get safetyOverdueTitle => '遅延アラート';

  @override
  String get safetyOverdueIntro =>
      'ライブ共有中のランがこの時間以上更新されない場合、確認済みの連絡先にライブリンク付きのメールが1通送られます。';

  @override
  String get safetyOverdueLabel => '無応答がこの時間続いたら通知';

  @override
  String get safetyOverdueOff => 'オフ';

  @override
  String safetyOverdueMinutesOption(int minutes) {
    return '$minutes分';
  }

  @override
  String get safetyOverdueNote =>
      'ライブ共有をオンにしたランに適用されます。無応答は電波が届かないだけの場合もあり、メールにもその旨が記載されます。通知はラン1回につき1度だけで、完了すると通常の完了通知が届きます。';

  @override
  String get safetyOverdueSaved => '遅延アラートを更新しました';

  @override
  String get safetyAutoLiveShareTitle => '自動ライブ共有';

  @override
  String get safetyAutoLiveShareSubtitle =>
      'この端末でランを開始すると自動的にライブ共有を開始します。進行中のランはリンクを知っている人なら誰でも見られます。ランが終了すると、既定の公開設定に戻ります。';

  @override
  String get safetyOffRouteTitle => 'ルート逸脱アラート';

  @override
  String get safetyOffRouteSubtitle =>
      'ライブ共有中のランで予定ルートを外れたままになったら、確認済みの連絡先に通知します。';

  @override
  String get runOffRouteAlertSent => '予定ルートを外れた状態が続いたため、緊急連絡先に通知しました。';

  @override
  String get runAutoLiveShareStarted => 'ライブ共有中 — 「ライブリンクを共有」でリンクを送れます';

  @override
  String get runSafetyNudgeSolo =>
      '暗くなってから一人で走っていますか？ライブリンクを共有して、誰かに見守ってもらいましょう。';

  @override
  String get runSafetyNudgeShareAction => '共有';

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
  String get authShowPassword => 'パスワードを表示';

  @override
  String get authHidePassword => 'パスワードを非表示';

  @override
  String get authOrDivider => 'または';

  @override
  String get authErrorOffline => 'オフラインのようです。接続を確認してもう一度お試しください。';

  @override
  String get authErrorInvalidCredentials =>
      'メールアドレスまたはパスワードが正しくありません。もう一度お試しください。';

  @override
  String get authErrorRateLimited => '試行回数が多すぎます。しばらく待ってからもう一度お試しください。';

  @override
  String get authErrorGeneric => '問題が発生しました。もう一度お試しください。';

  @override
  String get authErrorNotSignedIn => 'この操作にはサインインが必要です。サインインしてからもう一度お試しください。';

  @override
  String get authErrorEmailExists => 'このメールアドレスにはすでにアカウントがあります。サインインしてください。';

  @override
  String get authErrorEmailNotConfirmed =>
      'まずメールアドレスを確認してください。受信トレイの確認リンクをご確認ください。';

  @override
  String authErrorWeakPassword(int minLength) {
    return 'このパスワードは脆弱です。$minLength 文字以上にしてください。';
  }

  @override
  String get authErrorInvalidEmail => '有効なメールアドレスを入力してください。';

  @override
  String authErrorPasswordTooShort(int minLength) {
    return 'パスワードは $minLength 文字以上で入力してください。';
  }

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
  String get signInResendConfirmation => '確認メールを再送信';

  @override
  String get signInConfirmationResent => 'そのメールアドレスが登録されている場合、新しい確認リンクを送信しました。';

  @override
  String get signInWithApple => 'Appleでサインイン';

  @override
  String get signInWithGoogle => 'Googleでサインイン';

  @override
  String get googleSignInSoon => 'Google でのサインインは近日対応予定です。今はメールをご利用ください。';

  @override
  String get appleSignInSoon => 'Apple でのサインインは近日対応予定です。今はメールをご利用ください。';

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
  String get signUpAcceptConjunction => 'および';

  @override
  String get signUpErrorConfirmAge => '続けるには、16歳以上であることを確認してください。';

  @override
  String get signUpErrorAcceptTerms => '続けるには、利用規約とプライバシーポリシーに同意してください。';

  @override
  String get signUpConfirmPasswordLabel => 'パスワードを確認';

  @override
  String signUpErrorPasswordTooShort(int min) {
    return 'パスワードは$min文字以上で入力してください。';
  }

  @override
  String get signUpErrorPasswordMismatch => 'パスワードが一致しません。';

  @override
  String get signUpCheckEmailTitle => 'メールをご確認ください';

  @override
  String signUpCheckEmailBody(String email) {
    return '$email 宛てに確認リンクを送信しました。開いてアカウントの設定を完了してください。';
  }

  @override
  String get signUpCheckEmailBack => 'サインインに戻る';

  @override
  String get signUpContinueWithApple => 'Appleで続ける';

  @override
  String get signUpContinueWithGoogle => 'Googleで続ける';

  @override
  String get signUpSignInPrompt => 'すでにアカウントをお持ちですか？ サインイン';

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
  String get setupPageTitle => 'アカウントを設定';

  @override
  String get setupSkip => '設定をスキップ';

  @override
  String get setupSkipStep => 'スキップ';

  @override
  String get setupBack => '戻る';

  @override
  String get setupContinue => '続ける';

  @override
  String get setupSaving => '保存中…';

  @override
  String get setupOpenDashboard => 'ダッシュボードを開く';

  @override
  String get setupCreatePlanCta => 'トレーニングプランを作成';

  @override
  String get setupWelcomeToast => 'Threkir へようこそ！';

  @override
  String setupSaveError(String message) {
    return '設定を保存できませんでした: $message';
  }

  @override
  String setupPrefsSaveError(String message) {
    return 'アカウントの設定は完了しましたが、環境設定を保存できませんでした: $message';
  }

  @override
  String get setupOfflineHint =>
      '現在サーバーに接続できません。セットアップは後で完了できます — ここの内容はすべて設定で変更できます。';

  @override
  String get setupFinishLater => '後で完了する';

  @override
  String get setupNameTitle => '何とお呼びしましょうか？';

  @override
  String get setupNameHint => 'これはプロフィールや共有したランで他のランナーに表示される名前です。';

  @override
  String get setupNameLabel => '表示名';

  @override
  String get setupNamePlaceholder => '例: Alex Runner';

  @override
  String get setupUnitsTitle => 'キロメートルとマイル、どちら？';

  @override
  String get setupUnitsHint => '距離やペースの表示すべてに使用します。設定でいつでも変更できます。';

  @override
  String get setupUnitKm => 'キロメートル';

  @override
  String get setupUnitKmSample => '5.0 km · 5:00 /km';

  @override
  String get setupUnitMi => 'マイル';

  @override
  String get setupUnitMiSample => '3.1 mi · 8:03 /mi';

  @override
  String get setupGoalTitle => '主な目標は？';

  @override
  String get setupGoalHint => 'これに合ったトレーニングプランを提案します。任意です。スキップできます。';

  @override
  String get setupGoalGeneralFitness => '健康・フィットネスの維持';

  @override
  String get setupGoalWeightLoss => '減量';

  @override
  String get setupGoal5k => '5Kを走る';

  @override
  String get setupGoal10k => '10Kを走る';

  @override
  String get setupGoalHalf => 'ハーフマラソンを走る';

  @override
  String get setupGoalMarathon => 'フルマラソンを走る';

  @override
  String get setupAboutTitle => 'あなたについて少し';

  @override
  String get setupAboutHint => '任意です。ペースやカロリーの推定を最適化します。健康データを共有するかはあなたが選べます。';

  @override
  String get setupGenderLabel => '性別';

  @override
  String get setupGenderPreferNot => '回答しない';

  @override
  String get setupGenderFemale => '女性';

  @override
  String get setupGenderMale => '男性';

  @override
  String get setupDobLabel => '生年月日';

  @override
  String get setupDobNote =>
      '18歳未満のアカウントを人物検索から除外するため、また健康データを共有する場合は年齢補正結果のために使用します。';

  @override
  String get setupDobPlaceholder => 'タップして選択';

  @override
  String get setupWeightLabel => '体重 (kg)';

  @override
  String get setupWeightPlaceholder => '例: 70';

  @override
  String get setupHealthConsent =>
      'ペース・心拍・カロリーの推定をパーソナライズするために、Threkir が性別と生年月日を使用することに同意します（特別な区分の健康データ、GDPR 第9条）。';

  @override
  String get setupPrivacyTitle => 'ランは誰が見られる？';

  @override
  String get setupPrivacyHint => '新しいランの既定を選びます。いつでも変更でき、個々のランで上書きできます。';

  @override
  String get setupNotificationsTitle => '最新情報を受け取る';

  @override
  String get setupNotificationsHint => 'プッシュ通知の量を選びます。あとで設定で細かく調整できます。';

  @override
  String get setupDoneTitle => '準備完了';

  @override
  String get setupDoneHint => '以上です。「ダッシュボードを開く」をタップしてランを始めましょう。';

  @override
  String get setupDoneHintGoal =>
      'これで完了です。目標に合わせてトレーニングプランを作成するか、ダッシュボードを開いてランを始めましょう。';

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
  String get runLastRunOpenA11yLabel => '前回のランの詳細を開く';

  @override
  String get runChooseRoute => 'ルートを選択';

  @override
  String get runChangeRoute => 'ルートを変更';

  @override
  String get runShareLiveLink => 'ライブリンクを共有';

  @override
  String get runLiveShareNeedsSignIn => 'ライブトラッキングのリンクを共有するにはサインインしてください。';

  @override
  String get runLiveShareNotStarted =>
      'ライブトラッキングを開始できませんでした。「共有」をタップして再試行してください。';

  @override
  String get runLiveShareActive => 'ライブ';

  @override
  String get runLiveShareActiveSemantics =>
      'ライブ共有がオンです。タップしてリンクを再共有するか、共有を停止します。';

  @override
  String get runLiveShareSheetTitle => 'ライブ共有中';

  @override
  String get runLiveShareReshare => 'リンクを再共有';

  @override
  String get runLiveShareStop => '共有を停止';

  @override
  String get runLiveShareExpectedReturn => '指定時刻までに未帰還';

  @override
  String get runExpectedReturnTitle => '指定時刻までに未帰還';

  @override
  String get runExpectedReturnIntro =>
      '終える予定の時刻を選びます。その時刻を過ぎてもこのアクティビティが続いている場合、承認済みの緊急連絡先にライブリンク付きの通知が1回送られます。';

  @override
  String get runExpectedReturnServerNote =>
      '期限はサーバーに保存されるため、この端末が使えなくなっても有効です。アクティビティを保存すると解除されます。圏外で終えた場合は、同期されるまで通知が送られることがあります。';

  @override
  String runExpectedReturnOptionMinutes(int minutes) {
    return '$minutes分後';
  }

  @override
  String runExpectedReturnOptionHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours時間後',
      one: '1時間後',
    );
    return '$_temp0';
  }

  @override
  String runExpectedReturnBy(String time) {
    return '$timeまでに帰還';
  }

  @override
  String runExpectedReturnActive(String time) {
    return '$timeに通知を設定済みです。';
  }

  @override
  String get runExpectedReturnClear => '通知を解除';

  @override
  String get runExpectedReturnSetToast => '帰還時刻の通知を設定しました。';

  @override
  String get runExpectedReturnClearedToast => '帰還時刻の通知を解除しました。';

  @override
  String get runExpectedReturnFailed => '帰還時刻の通知を更新できませんでした。';

  @override
  String get runExpectedReturnUnavailable => 'サーバーに接続できず、帰還時刻の通知を設定できません。';

  @override
  String get runLiveShareStopped => 'ライブ共有を停止しました';

  @override
  String get runLiveShareEndedTitle => 'ライブ共有が終了しました';

  @override
  String get runLiveShareEndedBody =>
      'ライブリンクの更新は停止しました。保存したランを公開のままにして、リンクを知っている人が見られるようにしますか？公開しない場合は既定の公開設定に従います。';

  @override
  String get runLiveShareKeepPublic => '公開のままにする';

  @override
  String get runLiveShareKeepPrivate => '非公開にする';

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
  String get runStopA11yLabel => 'ランを停止して保存';

  @override
  String get runStopA11yHint => '記録を終了してランを保存します';

  @override
  String get runHoldToStopHint => '長押しで停止';

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
  String get runResumeDialogTitle => 'ランを再開しますか？';

  @override
  String get runResumeDialogBody =>
      '前回のセッションのランがまだ進行中です。中断したところから記録を再開するか、今すぐ終了するか、破棄してください。';

  @override
  String get runResumeAction => '再開';

  @override
  String get runResumeFinishAction => '今すぐ終了';

  @override
  String get runResumedBanner => 'ランを再開しました。';

  @override
  String get runResumeSavedBanner => '前回のランを保存しました。';

  @override
  String get runResumeDiscardedBanner => '前回のランを破棄しました。';

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
  String get runTreadmillModeLabel => 'トレッドミルモード';

  @override
  String runTreadmillModeSpeed(String speed) {
    return 'ベルト $speed';
  }

  @override
  String get runTreadmillLostReconnecting => 'トレッドミルとの接続が切れました。再接続中…';

  @override
  String get runTreadmillReconnected => 'トレッドミルに再接続しました';

  @override
  String get runTreadmillLostFallback => 'トレッドミルとの接続が切れました — 距離はGPSに戻ります';

  @override
  String get runTreadmillNotFound => 'トレッドミルに接続できませんでした';

  @override
  String get runTreadmillConnecting => 'トレッドミルに接続中…';

  @override
  String get runTreadmillNoBeltData => 'ベルトのデータなし — 距離はGPSから';

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
  String get runBackgroundLocationPaused =>
      'アプリを離れている間、位置情報の記録が一時停止しました — タイムは計測を続け、記録済みのデータは失われていませんが、画面外で進んだ距離は加算されていません。バックグラウンドでも記録するには、位置情報を「常に許可」に設定してください。';

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
  String get historyUnsyncedRowSemantics => '未同期';

  @override
  String get historyBlockedRowSemantics => 'アップロードできません';

  @override
  String get historyBlockedRowTooltip => 'アップロードできません';

  @override
  String historyBlockedTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランをアップロードできません',
    );
    return '$_temp0';
  }

  @override
  String historySyncBlocked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のランはアップロードできず、再試行もされません。それぞれを開いて対応を選んでください。',
    );
    return '$_temp0';
  }

  @override
  String get runDetailBlockedDropTrack => 'トラックなしでアップロード';

  @override
  String get runDetailBlockedExport => 'コピーを書き出す';

  @override
  String get runDetailBlockedTitle => 'このランはアップロードできません';

  @override
  String runDetailBlockedTrackTooLarge(int waypoints) {
    return 'GPS トラック（$waypoints 点）がクラウド保存の上限を超えているため、再試行しても成功しません。距離・時間・ペース・獲得標高など、それ以外の記録は保存できます。';
  }

  @override
  String get runDetailDropTrackBody =>
      'トラックはこの端末から削除され、ランは地図なしでアップロードされます。距離・時間・ペース・獲得標高は変わりません。残しておきたい場合は、先にコピーを書き出してください。';

  @override
  String get runDetailDropTrackConfirm => 'トラックなしでアップロード';

  @override
  String get runDetailDropTrackDone => 'トラックを削除しました。次のサイクルで同期されます。';

  @override
  String get runDetailDropTrackFailed => 'トラックを削除できませんでした。もう一度お試しください。';

  @override
  String get runDetailDropTrackTitle => 'GPS トラックなしでアップロードしますか？';

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
  String get durationFieldHours => '時間';

  @override
  String get durationFieldMinutes => '分';

  @override
  String get durationFieldSeconds => '秒';

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
  String get runDetailIncompleteBadge => '記録途中';

  @override
  String get runDetailIncompleteTooltip =>
      'ラン中にウォッチが再起動しました。ここに表示されている合計はその時点までに記録された分だけで、アクティビティ全体ではありません。';

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
  String get runDetailReportRun => 'ランを報告';

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
  String get runDetailEditFailed => '変更を保存できませんでした。もう一度お試しください。';

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
  String get runDetailStatHrCoverage => '心拍カバー率';

  @override
  String runDetailHrCoveragePercent(int pct) {
    return '$pct%';
  }

  @override
  String runDetailHrCoverageOnly(int pct) {
    return '$pct% を計測';
  }

  @override
  String get runDetailStatAvgHr => '平均心拍';

  @override
  String get runDetailStatAgeGrade => '年齢グレード';

  @override
  String get runDetailStatGradeAdjPace => '勾配調整ペース';

  @override
  String get runDetailSectionElevation => '獲得標高';

  @override
  String get runDetailPaceLegendTitle => '中央値との比較ペース';

  @override
  String get runDetailPaceBandFaster => '速い';

  @override
  String get runDetailPaceBandSteady => '一定';

  @override
  String get runDetailPaceBandSlower => '遅い';

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
  String get runDetailHrDisclaimer =>
      'ゾーンは年齢から推定した最大心拍数を使用します。心拍に影響する薬（ベータ遮断薬など）を服用している場合や最大心拍数を測定済みの場合は、環境設定で設定すると正確なゾーンを取得できます。';

  @override
  String get runDetailHrDisclaimerAction => '最大心拍数を設定';

  @override
  String get runDetailSectionSplits => 'スプリット';

  @override
  String get runDetailNoGpsForSplits => 'スプリット用の GPS データがありません';

  @override
  String runDetailRunTooShortSplit(String unit) {
    return 'ランが短すぎて $unit の完全なスプリットを作成できません';
  }

  @override
  String get runDetailPacing => 'ペース配分';

  @override
  String get runDetailPacingFirstHalf => '前半';

  @override
  String get runDetailPacingSecondHalf => '後半';

  @override
  String get runDetailPacingNegative => 'ネガティブスプリット';

  @override
  String get runDetailPacingEven => 'イーブンペース';

  @override
  String get runDetailPacingPositive => 'ポジティブスプリット';

  @override
  String runDetailPacingFaster(String delta) {
    return '後半が$delta速い';
  }

  @override
  String runDetailPacingSlower(String delta) {
    return '後半が$delta遅い';
  }

  @override
  String get runDetailPacingHeld => '前半と後半で安定したペース';

  @override
  String get runDetailPacingGapNegative => '勾配を調整すると、後半はペースを上げています。';

  @override
  String get runDetailPacingGapEven => '勾配を調整すると、前半と後半の負荷は同じでした。';

  @override
  String get runDetailPacingGapPositive => '勾配を調整すると、後半はペースが落ちています。';

  @override
  String get runDetailGapColumn => '勾配調整';

  @override
  String get runDetailGapColumnHint => '勾配調整ペースは、実際に走った起伏と同じ負荷になる平地でのペースです。';

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
  String get runDetailMakePrivate => '非公開にする';

  @override
  String get runDetailMakePrivateTitle => 'このランを非公開にしますか？';

  @override
  String get runDetailMakePrivateBody =>
      '公開共有リンクとライブ観戦ページは利用できなくなります。古いリンクを開いてもこのランは表示されません。';

  @override
  String runDetailMakePrivateFailed(String error) {
    return 'ランを非公開にできませんでした: $error';
  }

  @override
  String get runDetailMadePrivate => 'ランは非公開になりました';

  @override
  String get runDetailDeleteTitle => 'ランを削除しますか？';

  @override
  String get runDetailDeleteBody => 'この操作は元に戻せません。';

  @override
  String get runDetailDeleteQueued =>
      'クラウドから削除できませんでした。ランは一時的に保持され、オンライン復帰時に再試行します。';

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
  String get runDetailMatchOffline => 'オフライン — 生のトラックを表示中、再接続時に再試行します';

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
  String get publicRunLiveTitle => 'ただいまライブ中';

  @override
  String get publicRunLiveSub => 'このランはまだ進行中です。ライブトラッカーで追いかけましょう。';

  @override
  String get publicRunWatchLive => 'ライブで見る';

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
  String routesImportedMany(int count) {
    return '$count 件のルートをインポートしました';
  }

  @override
  String routesImportFailed(String error) {
    return 'インポートに失敗しました: $error';
  }

  @override
  String get routesImportSharedFailed => 'このファイルをインポートできませんでした。有効なルートではありません。';

  @override
  String routesSaved(String name) {
    return '「$name」を保存しました';
  }

  @override
  String get historySelectionHint => 'ランを長押しすると複数選択できます';

  @override
  String get routesSelectionHint => 'ルートを長押しすると複数選択できます';

  @override
  String get routesEmptyTitle => 'まだルートがありません';

  @override
  String get routesEmptyBody =>
      '「作成」をタップして地図上にルートを描くか、GPX・KML・KMZ・GeoJSON・TCX ファイルをインポートしてください。';

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
  String get routeBuilderSnapUnavailable =>
      '道路へのスナップは利用できません — ピンはタップした位置に置かれ、直線で結ばれます。';

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
  String get routeBuilderClearConfirmTitle => 'このルートをクリアしますか？';

  @override
  String get routeBuilderClearConfirmBody => 'すべてのウェイポイントが削除されます。元に戻せません。';

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
  String get routeBuilderPointList => 'ルートのポイント';

  @override
  String routeBuilderPointMovedTo(int from, int to) {
    return 'ポイント$fromを$to番目に移動しました';
  }

  @override
  String routeBuilderPointRemoved(int number) {
    return 'ポイント$numberを削除しました';
  }

  @override
  String routeBuilderReorderPoint(int number) {
    return 'ポイント$numberを並べ替え';
  }

  @override
  String get routeBuilderPointStart => 'スタート';

  @override
  String get routeBuilderPointEnd => 'ゴール';

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
  String get routeDetailShareLink => 'リンクを共有';

  @override
  String get routeDetailSendToWatch => 'ウォッチに送信';

  @override
  String routeDetailWatchCourseSent(int points) {
    return 'コースをウォッチに送信しました（$points地点）';
  }

  @override
  String routeDetailWatchCourseSimplified(int source, int points) {
    return 'コースをウォッチに送信しました — 収まるように$source地点から$points地点に間引きました';
  }

  @override
  String get routeDetailWatchCourseTooShort => 'このルートは地点が少なすぎてウォッチでたどれません';

  @override
  String get routeDetailWatchPushRejected =>
      '時計が送信を拒否し、以前の内容をそのまま保持しました。もう一度お試しください。';

  @override
  String routeDetailWatchCourseFailed(String error) {
    return 'コースをウォッチに送信できませんでした: $error';
  }

  @override
  String get routeDetailSendToAppleWatch => 'Apple Watchに送信';

  @override
  String routeDetailAppleWatchRouteSent(int points) {
    return 'ルートをApple Watchに送信しました（$points地点）';
  }

  @override
  String routeDetailAppleWatchRouteSimplified(int source, int points) {
    return 'ルートをApple Watchに送信しました — 収まるように$source地点から$points地点に間引きました';
  }

  @override
  String get routeDetailAppleWatchRouteTooShort =>
      'このルートは地点が少なすぎてApple Watchでたどれません';

  @override
  String routeDetailAppleWatchRouteFailed(String error) {
    return 'ルートをApple Watchに送信できませんでした: $error';
  }

  @override
  String routeDetailWatchCourseAndScheduleSent(int points, int checkpoints) {
    return 'コース（$points ポイント）とレーススケジュール（$checkpoints チェックポイント）をウォッチに送信しました';
  }

  @override
  String routeDetailWatchScheduleThinned(
    int points,
    int source,
    int checkpoints,
  ) {
    return 'コース（$points ポイント）を送信しました。レーススケジュールはウォッチに収めるため $source から $checkpoints チェックポイントに削減されました';
  }

  @override
  String routeDetailWatchScheduleClockCutoffs(int checkpoints, int unresolved) {
    return 'レーススケジュールを送信しました（$checkpoints チェックポイント）。ただし $unresolved 件の時刻制限にはスタート時刻が必要です — クルーシートで設定するとウォッチに反映されます';
  }

  @override
  String routeDetailWatchScheduleTooManyCutoffs(
    int points,
    int cutoffs,
    int max,
  ) {
    return 'コース（$points ポイント）を送信しましたが、レーススケジュールの関門は $cutoffs 件でウォッチの上限は $max 件です — いくつか削除して送信してください';
  }

  @override
  String get routeDetailMadePublicForLink => 'リンクを知っている全員が閲覧できるように公開しました';

  @override
  String get routeDetailShareConfirmTitle => 'このルートを公開しますか？';

  @override
  String get routeDetailShareConfirmBody =>
      'リンクを共有するとこのルートが公開され、リンクを知っている人は誰でも開くことができ、「探索」に表示される場合があります。いつでも非公開に戻せます。';

  @override
  String get routeDetailShareConfirmCta => '公開して共有';

  @override
  String routeDetailShareLinkFailed(String error) {
    return 'リンクを共有できませんでした: $error';
  }

  @override
  String get routeDetailShareAsGpxMarkers => 'GPX + マーカーとして共有';

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
  String get routeDetailReportReview => 'レビューを報告';

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
  String get routeDetailDescribe => 'このルートを説明';

  @override
  String get routeDetailDescribing => '説明を作成中…';

  @override
  String get routeDetailAiAttribution => 'ルートのデータからAIが作成';

  @override
  String get routeDetailDescribeFailed => '説明を生成できませんでした。もう一度お試しください。';

  @override
  String get routeDetailDescribeConsentRequired =>
      'AIによる説明には、更新されたAIの説明への同意が必要です。';

  @override
  String get routeDetailReviewDisclosure => '説明を確認';

  @override
  String get routeDetailEnhanceUpgradeHint =>
      'AIによる説明はPro機能です。アップグレードして強化しましょう。';

  @override
  String get routeDetailDescShapeLoop => '周回';

  @override
  String get routeDetailDescShapeOutAndBack => '往復';

  @override
  String get routeDetailDescShapePointToPoint => 'ポイント間';

  @override
  String get routeDetailDescSurfaceRoad => 'ロード';

  @override
  String get routeDetailDescSurfaceTrail => 'トレイル';

  @override
  String get routeDetailDescSurfaceMixed => '混在路面';

  @override
  String get routeDetailDescElevFlat => '平坦';

  @override
  String get routeDetailDescElevRolling => '緩やかなアップダウン';

  @override
  String get routeDetailDescElevHilly => '起伏あり';

  @override
  String get routeDetailDescElevMountainous => '山岳';

  @override
  String routeDetailDescSentence(
    String name,
    String distance,
    String surface,
    String shape,
  ) {
    return '$nameは$distanceの$surface・$shapeルートです。';
  }

  @override
  String routeDetailDescSentenceNoSurface(
    String name,
    String distance,
    String shape,
  ) {
    return '$nameは$distanceの$shapeルートです。';
  }

  @override
  String routeDetailDescClimb(String gain, String elevation, String perKm) {
    return '獲得標高は$gain（$elevation、1kmあたり約$perKm）です。';
  }

  @override
  String get routeDetailDescFlat => '標高差はほとんどありません。';

  @override
  String routeDetailDescPerKm(int m) {
    return '$m m';
  }

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
  String routeDetailRateStars(int n) {
    return '評価を5段階中$nに設定';
  }

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
  String get routeDetailDeleteReview => '自分のレビューを削除';

  @override
  String routeDetailReviewDeleteFailed(String error) {
    return 'レビューを削除できませんでした: $error';
  }

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
  String routeDetailTagRemoveFailed(String error) {
    return 'タグを削除できませんでした: $error';
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
  String get runHeatmapTitle => 'あなたのヒートマップ';

  @override
  String get runHeatmapTooltip => 'ランのヒートマップ';

  @override
  String get runHeatmapLoading => 'ランを読み込み中…';

  @override
  String runHeatmapLoadingProgress(int n, int total) {
    return 'ランを読み込み中… $n/$total';
  }

  @override
  String get runHeatmapEmptyTitle => 'まだマップ化されたランがありません';

  @override
  String get runHeatmapEmptyBody => 'GPSトラック付きのランを記録またはインポートすると、ここに表示されます。';

  @override
  String get runHeatmapSignedOutTitle => 'サインインして同期済みのヒートマップを表示';

  @override
  String get runHeatmapSignedOutBody =>
      'この端末で記録したランはここに表示されます。同期済みのランも含めるにはサインインしてください。';

  @override
  String get runHeatmapErrorTitle => 'ヒートマップを読み込めませんでした';

  @override
  String get runHeatmapErrorBody => 'ランの読み込み中に問題が発生しました。接続を確認してもう一度お試しください。';

  @override
  String get runHeatmapRetry => '再試行';

  @override
  String get runHeatmapLegendTitle => 'あなたのヒートマップ';

  @override
  String runHeatmapLegendSummaryOne(int n) {
    return 'マップ化されたラン$n件 — よく走る場所ほど明るく表示されます。';
  }

  @override
  String runHeatmapLegendSummaryMany(int n) {
    return 'マップ化されたラン$n件 — よく走る場所ほど明るく表示されます。';
  }

  @override
  String get runHeatmapScaleLess => '少ない';

  @override
  String get runHeatmapScaleMore => '多い';

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
  String runNotificationPausedTitle(String activity) {
    return '$activity • 一時停止中';
  }

  @override
  String get activityTypeRun => 'ランニング';

  @override
  String get activityTypeWalk => 'ウォーキング';

  @override
  String get activityTypeHike => 'トレイルラン';

  @override
  String get activityTypeCycle => 'サイクリング';

  @override
  String get activityTypeStroller => 'ベビーカー';

  @override
  String get feedActivityAll => 'すべて';

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
  String get relativeJustNow => 'たった今';

  @override
  String relativeMinutesAgo(int count) {
    return '$count分前';
  }

  @override
  String relativeHoursAgo(int count) {
    return '$count時間前';
  }

  @override
  String get relativeYesterday => '昨日';

  @override
  String relativeDaysAgo(int count) {
    return '$count日前';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count週間前',
    );
    return '$_temp0';
  }

  @override
  String get coachArchiveToday => '今日';

  @override
  String coachArchiveDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日前',
    );
    return '$_temp0';
  }

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
  String get profileSectionError => 'このセクションを読み込めませんでした。';

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
  String get profileNotifYourRun => 'ラン';

  @override
  String profileNotifNameAndOthers(String name, int count) {
    return '$nameさん他$count名';
  }

  @override
  String profileNotifAndOthers(int count) {
    return '他$count件';
  }

  @override
  String get profileNotifShowLess => '折りたたむ';

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
  String profileNotifPlanAssigned(String name) {
    return '$nameがあなたにトレーニングプランを割り当てました';
  }

  @override
  String profileNotifEventCancelTitled(String title) {
    return '「$title」の開催が1回キャンセルされました';
  }

  @override
  String get profileNotifEventCancel => '参加表明していたイベントの開催がキャンセルされました';

  @override
  String profileNotifEventReminderTitled(String title) {
    return '「$title」がもうすぐ始まります';
  }

  @override
  String get profileNotifEventReminder => '参加予定のイベントがもうすぐ始まります';

  @override
  String get profileNotifAchievement => '新しいアチーブメントを獲得しました';

  @override
  String get profileNotifChallengeComplete => 'チャレンジを達成しました';

  @override
  String get profileNotifContentHidden => '報告を受けて、あなたの投稿の1つが非表示になりました';

  @override
  String get profileNotifDataExportReady => 'データのエクスポートをダウンロードできます';

  @override
  String get profileNotifRefundFailed =>
      '開始した返金が完了しませんでした。代金はまだ当方にあり、別の方法で返金の手配をします。';

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
  String get socialTabDiscover => '見つける';

  @override
  String get discoverSearchPlaceholder => 'クラス、クラブを検索…';

  @override
  String get discoverActivityAll => 'すべてのアクティビティ';

  @override
  String get discoverCadenceLabel => '頻度';

  @override
  String get discoverCadenceAny => '頻度を問わない';

  @override
  String get discoverOneOff => '単発';

  @override
  String get discoverWeekly => '毎週';

  @override
  String get discoverBiweekly => '隔週';

  @override
  String get discoverMonthly => '毎月';

  @override
  String get discoverDayLabel => '曜日';

  @override
  String get discoverDayAny => '曜日を問わない';

  @override
  String get discoverDayMon => '月';

  @override
  String get discoverDayTue => '火';

  @override
  String get discoverDayWed => '水';

  @override
  String get discoverDayThu => '木';

  @override
  String get discoverDayFri => '金';

  @override
  String get discoverDaySat => '土';

  @override
  String get discoverDaySun => '日';

  @override
  String get discoverTimeLabel => '時間帯';

  @override
  String get discoverTimeAny => '時間を問わない';

  @override
  String get discoverMorning => '朝';

  @override
  String get discoverAfternoon => '昼';

  @override
  String get discoverEvening => '夜';

  @override
  String get discoverPriceLabel => '料金';

  @override
  String get discoverPriceAny => '料金を問わない';

  @override
  String get discoverFree => '無料';

  @override
  String get discoverPaid => '有料';

  @override
  String get discoverLoading => '検索中…';

  @override
  String get discoverEmpty => 'この条件に一致する公開アクティビティはまだありません。';

  @override
  String get discoverSearchFailed => 'アクティビティを読み込めませんでした。接続を確認してもう一度お試しください。';

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
  String get clubDetailTabPhotos => '写真';

  @override
  String get clubDetailReadMore => '続きを読む';

  @override
  String get clubDetailReportClub => 'クラブを報告';

  @override
  String get clubDetailReportPost => 'この投稿を報告';

  @override
  String get clubDetailLoadFailedBody =>
      'このクラブを読み込めませんでした。削除されたか、セッションの更新が必要かもしれません。引っ張って再試行するか、設定からサインアウトして再度サインインしてください。';

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
  String get clubDetailDenyTitle => '参加リクエストを却下';

  @override
  String get clubDetailDenyMessage => 'このクラブへの参加リクエストを却下しますか？このユーザーは追加されません。';

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
  String get clubDetailGymRoutineTemplatesTitle => 'ジムルーティンのテンプレート';

  @override
  String get clubDetailGymRoutineTemplatesHint =>
      'メンバーはクラブのジムルーティンを自分のルーティンに取り込めます。コピーへの編集はテンプレートには反映されません。';

  @override
  String get clubDetailGymRoutineAdopted => 'ルーティンをあなたのジムルーティンに追加しました。';

  @override
  String clubDetailRoutineExerciseCount(int n) {
    return '$n種目';
  }

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
  String eventPhotosTitle(int count) {
    return '写真 ($count)';
  }

  @override
  String get eventAddPhoto => '写真を追加';

  @override
  String get eventPhotoUploading => 'アップロード中…';

  @override
  String get eventNoPhotosYet => 'まだ写真はありません。';

  @override
  String get eventNoPhotosAddHint => '最初の1枚を追加しましょう。';

  @override
  String get eventWhichRunPhoto => 'この写真はどのランのものですか？';

  @override
  String get eventNoRecentRuns => '最近のランが見つかりません。先にランを記録してから戻ってください。';

  @override
  String get eventPhotoRunnerFallback => 'ランナー';

  @override
  String get eventPhotoUploadFailed => '写真をアップロードできませんでした。';

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
  String get eventRsvpFailed => '参加可否を更新できませんでした。もう一度お試しください。';

  @override
  String get eventRsvpGoing => '参加する';

  @override
  String get eventRsvpMaybe => '未定';

  @override
  String get eventOccurrenceCancelled => 'この回はキャンセルされました。';

  @override
  String get eventRsvpWaitlisted => '補欠';

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
  String get eventRaceEndConfirmBody => 'レースを終了しますか？全ランナーのイベントが確定され、元に戻せません。';

  @override
  String get eventRaceCancelConfirmBody =>
      'レースを中止しますか？全ランナーのイベントが中止され、元に戻せません。';

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
  String get liveSpectatorBadgeApproximate => 'おおよその位置';

  @override
  String get liveSpectatorApproximateSub => 'この付近で最後に確認 — おおよその位置';

  @override
  String get liveSpectatorBadgeFinished => '終了';

  @override
  String get liveSpectatorBadgeDnf => 'DNF';

  @override
  String get liveSpectatorStatRaceTime => 'レース時間';

  @override
  String get liveSpectatorStatTimer => 'タイマー';

  @override
  String get liveSpectatorStatTimerStale => 'タイマー（最終受信）';

  @override
  String get liveSpectatorRecentPace => '直近';

  @override
  String liveSpectatorCourseProgress(int p) {
    return 'コースの$p%';
  }

  @override
  String liveSpectatorMotionStopped(int n) {
    return '動きなし — 同じ地点に$n分';
  }

  @override
  String liveSpectatorMotionStoppedAtLeast(int n) {
    return '動きなし — 同じ地点に少なくとも$n分';
  }

  @override
  String get liveSpectatorConcludedTitle => 'ランが完了しました';

  @override
  String get liveSpectatorConcludedBody => '全コース・スプリット・統計を確認しましょう。';

  @override
  String get liveSpectatorViewFullRun => 'ランの詳細を見る';

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
  String get liveCutoffTitle => '次の関門';

  @override
  String liveCutoffToGo(String distance) {
    return '残り$distance';
  }

  @override
  String liveCutoffEta(String eta) {
    return '到着予想 $eta';
  }

  @override
  String liveCutoffAhead(String margin) {
    return '$marginの余裕';
  }

  @override
  String liveCutoffBehind(String margin) {
    return '$marginの遅れ';
  }

  @override
  String get liveCutoffWaitingSignal => '到着予想のため最新の信号を待っています';

  @override
  String get liveCutoffSignalLost => '信号が途絶えました — 到着予測できません';

  @override
  String get liveCutoffExpired => '関門時刻を過ぎました';

  @override
  String liveCutoffRequiredPace(String pace) {
    return 'ここから $pace が必要です';
  }

  @override
  String liveCutoffRequiredPaceStale(String pace) {
    return '最後の測位地点から $pace が必要です';
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
  String plansAbandonTitle(String name) {
    return '「$name」を中止しますか？';
  }

  @override
  String get plansAbandonBody => 'その後、新しいプランを作成できます。';

  @override
  String plansActionFailed(String error) {
    return 'プランを更新できませんでした: $error';
  }

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
  String get planNewNameRequiredHint => '「作成」を有効にするにはプラン名を入力してください。';

  @override
  String planNewDefaultName(String goal) {
    return '$goal プラン';
  }

  @override
  String planNewDefaultNameBeginner(String goal) {
    return '$goal までウォークラン';
  }

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
  String planNewRaceAnchored(int weeks) {
    return 'レースに合わせた$weeks週間のプランです。最終週がレース週になります。作成する前に下の内容を自由に調整してください。';
  }

  @override
  String get planNewRacePast => 'このレースはすでに終了しているため、下の日付は通常の初期値です。';

  @override
  String get planNewRaceTooSoon => 'このレースは近すぎて完全なプランを組めないため、下の日付は通常の初期値です。';

  @override
  String get planNewRaceUnreadable => 'このレースの日付を読み取れなかったため、下の日付は通常の初期値です。';

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
  String get planNewRampLabel => 'プランと最近のトレーニングの比較';

  @override
  String planNewRampUnder(String peak, String recent) {
    return 'このプランの最大週は$peakで、過去4週間の平均である週$recentを下回ります。目標レースを長くするか、トレーニング日を増やすと、その土台をより活かせます。';
  }

  @override
  String planNewRampElevated(String opening, String recent) {
    return '第1週は$openingで、過去4週間の平均である週$recentからはっきり上がります。無理せず入るか、トレーニング日を1日減らしましょう。';
  }

  @override
  String planNewRampHigh(String opening, String recent) {
    return '第1週は$openingで、過去4週間の平均である週$recentを大きく上回ります。トレーニング日を減らす、目標レースを短くする、または数週間かけて土台を作ってから始めると、最初の一歩が安全になります。';
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
  String get planNewTemplateCloneFailed => 'テンプレートを取り込めませんでした。';

  @override
  String get planNewTemplatePickerTitle => 'テンプレートを選択';

  @override
  String get planNewTemplatePickerCancel => 'キャンセル';

  @override
  String get planLibraryTitle => '公開プランライブラリ';

  @override
  String get planLibrarySubheading =>
      '他のランナーが公開したプラン。アカウントにクローンしてトレーニングを始めましょう。';

  @override
  String get planLibrarySearchHint => '名前でプランを検索';

  @override
  String get planLibraryLoadError => 'ライブラリを読み込めませんでした。再試行してください。';

  @override
  String get planLibraryRetry => '再試行';

  @override
  String get planLibraryEmpty => '公開されたプランはまだありません。';

  @override
  String planLibraryEmptySearch(String query) {
    return '「$query」に一致するプランはありません。';
  }

  @override
  String planLibraryByAuthor(String author) {
    return '$author 作成';
  }

  @override
  String get planLibraryAnonymous => 'あるランナー';

  @override
  String planLibraryWeeks(int weeks) {
    return '$weeks 週間';
  }

  @override
  String planLibraryDaysPerWeek(int days) {
    return '週$days回';
  }

  @override
  String get planLibraryClone => '自分のプランにクローン';

  @override
  String get planLibraryCloning => 'クローン中…';

  @override
  String get planLibraryCloneSuccess => 'プランをクローンしました。';

  @override
  String planLibraryCloneFailed(String error) {
    return 'クローンに失敗しました: $error';
  }

  @override
  String get planLibraryStartDate => '開始日';

  @override
  String get planLibraryNotFound => 'このプランは公開ライブラリにありません。';

  @override
  String get planLibraryPreviewWeeks => '週';

  @override
  String planLibraryPreviewWeek(int n) {
    return '第$n週';
  }

  @override
  String get planDetailPublishLibraryLabel => '公開プランライブラリ';

  @override
  String get planDetailPublishLibrary => 'ライブラリに公開';

  @override
  String get planDetailPublishLibraryHint =>
      'このプランのコピーを共有して、誰でもクローンできるようにします。フィットネス数値は共有されません。';

  @override
  String get planDetailPublishLibrarySuccess =>
      'プランを公開ライブラリに公開しました。あなた個人のプランは変わりません。';

  @override
  String planDetailPublishLibraryFailed(String error) {
    return '公開に失敗しました: $error';
  }

  @override
  String get planDetailUnpublishLibrary => '公開を取り消す';

  @override
  String get planDetailUnpublishSuccess => '公開ライブラリから削除しました。';

  @override
  String planDetailUnpublishFailed(String error) {
    return '取り消しに失敗しました: $error';
  }

  @override
  String get planDetailAlreadyPublished => 'このプランは公開ライブラリにあります。';

  @override
  String get plansBrowseLibrary => 'ライブラリを見る';

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
  String get planNewStarterCreateFailed => 'そのプランを作成できませんでした。';

  @override
  String get planNewReplaceActiveTitle => 'アクティブなプランを置き換えますか？';

  @override
  String planNewReplaceActiveNamed(String name) {
    return 'すでにアクティブなプランがあります:「$name」。新しいプランを作成すると、現在のプランは完了としてマークされます（「プランの管理」から引き続き確認できます）。続行しますか？';
  }

  @override
  String get planNewReplaceActiveUnnamed =>
      'すでにアクティブなプランがあります。新しいプランを作成すると、現在のプランは完了としてマークされます。続行しますか？';

  @override
  String get planNewReplaceActiveConfirm => 'プランを置き換える';

  @override
  String get planNewReplaceActiveKeep => '現在のプランを保持';

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
  String get planDetailLongestLongRun => '最長のロング走';

  @override
  String get planDetailPublishTooltip => 'クラブテンプレートとして公開';

  @override
  String planDetailDaysPerWeek(int count) {
    return '週$count日';
  }

  @override
  String get planDetailCurrentWeek => '今週';

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
  String get planDetailAdaptiveFitnessHeld =>
      '保留しました — 現在疲労がたまっているため、走行量を増やすのはおすすめしません。';

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
  String get planDetailDuplicateConfirmTitle => 'この週を複製しますか？';

  @override
  String planDetailDuplicateConfirmMessage(int n) {
    return '第$n週のコピーを挿入し、以降のすべての週とレース日を7日後ろにずらします。';
  }

  @override
  String get planDetailDuplicateConfirm => '複製';

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
  String get workoutUnlinkTitle => 'ランのリンクを解除';

  @override
  String get workoutUnlinkBody => '紐付いたランのリンクを解除しますか？このワークアウトは未完了に戻ります。';

  @override
  String get workoutUnlinkError => 'ランのリンクを解除できませんでした。もう一度お試しください。';

  @override
  String get workoutSkipped => 'スキップ済み';

  @override
  String get workoutSkip => 'このワークアウトをスキップ';

  @override
  String get workoutUnskip => 'スキップを取り消す';

  @override
  String get workoutSkipError => 'スキップを更新できませんでした。もう一度お試しください。';

  @override
  String get workoutRelink => 'リンクし直す';

  @override
  String get workoutRelinkTitle => '別のランを紐づける';

  @override
  String get workoutRelinkHint =>
      'このワークアウトの日付に近いランを選んで、このセッションとして数えます。すでに別のワークアウトに紐づいているランは表示されません。';

  @override
  String get workoutRelinkLoading => 'ランを検索中…';

  @override
  String get workoutRelinkError => 'ランを読み込めませんでした。もう一度お試しください。';

  @override
  String get workoutRelinkEmpty => 'この日付の近くに対象のランがありません。';

  @override
  String get workoutRelinkCurrent => '現在';

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
  String get coachTitle => 'AI コーチ';

  @override
  String get coachNewConversation => '新しい会話';

  @override
  String get coachConsentHeadline => 'AI機能を使う前に';

  @override
  String get coachConsentIntro =>
      'ThrekirのAI機能（コーチとAIルートアシスタント）は、あなたのデータの一部を、米国のAIモデルプロバイダーである Anthropic に送信します。利用する機能に応じて、その一部には以下が含まれます：';

  @override
  String get coachConsentBulletProfile => '生年月日、性別、設定済みの心拍ゾーン。';

  @override
  String get coachConsentBulletRuns => '直近のランの一部。';

  @override
  String get coachConsentBulletPlan => '選択中のアクティブなトレーニングプラン。';

  @override
  String get coachConsentBulletMessages => '下の画面で入力するチャットメッセージ。';

  @override
  String get coachConsentBulletRoutes =>
      'AIルートアシスタント利用時: ルートの名称と数値データ、入力したリクエスト、おおまかな地名。正確な座標は送信しません。';

  @override
  String get coachConsentProcessing =>
      'Anthropic は Threkir に代わってデータ処理条件に基づきデータを処理します。既定では Threkir の顧客データでモデルを学習しません。移転の仕組み、保持期間、撤回の権利を含む詳細は、プライバシーポリシーをご覧ください。';

  @override
  String get coachConsentAction =>
      '「同意する」をタップして続行します。キャンセルをタップすると、データを送信せずにページを離れます。';

  @override
  String get coachConsentCancel => 'キャンセル';

  @override
  String get coachConsentAccept => '同意する — AI機能を有効にする';

  @override
  String get coachConsentSaving => '同意を記録中…';

  @override
  String aiDisclosureRecordFailed(Object error) {
    return '同意を記録できませんでした：$error';
  }

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
  String get coachArchiveTapToView => 'タップで表示';

  @override
  String get coachArchiveActions => '会話の操作';

  @override
  String get coachArchiveDelete => '会話を削除';

  @override
  String get coachArchiveDeleteTitle => 'この会話を削除しますか？';

  @override
  String get coachArchiveDeleteBody => 'このアーカイブされた会話は完全に削除されます。';

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
  String get coachSuggestNewFirstRun => '走ったことがありません。どこから始めればいい？';

  @override
  String get coachSuggestNewFirstFeel => '初めてのランはどんな感じがすればいい？';

  @override
  String get coachSuggestNewHowOften => '初心者はどのくらいの頻度で走ればいい？';

  @override
  String get coachSuggestNewWalkRun => 'ランの途中で歩いてもいい？';

  @override
  String get coachEditMessageLabel => 'メッセージを編集';

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
  String get coachNewConversationFailed => '新しい会話を開始できませんでした。';

  @override
  String get coachOpenArchiveFailed => 'アーカイブを開けませんでした。';

  @override
  String coachArchiveDeleteFailed(String error) {
    return 'アーカイブを削除できませんでした：$error';
  }

  @override
  String get coachReactionFailed => 'リアクションを保存できませんでした。もう一度お試しください。';

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
  String get settingsAccountPasswordsMismatch => 'パスワードが一致しません';

  @override
  String get settingsAccountPasswordUpdated => 'パスワードを更新しました';

  @override
  String settingsAccountPasswordUpdateFailed(Object error) {
    return 'パスワードを更新できませんでした：$error';
  }

  @override
  String get settingsAccountCurrentPassword => '現在のパスワード';

  @override
  String get settingsAccountPasswordStepUpHint =>
      '安全のため、変更するには現在のパスワードを入力してください。Google または Apple で登録した場合は、リセットリンクを自分宛てに送信してパスワードを設定してください。';

  @override
  String get settingsAccountCurrentPasswordRequired =>
      '変更するには現在のパスワードを入力してください。';

  @override
  String get settingsAccountCurrentPasswordIncorrect =>
      '現在のパスワードが正しくありません。パスワードを設定したことがない場合は、代わりにリセットリンクを自分宛てに送信してください。';

  @override
  String get settingsAccountSendResetLink => 'リセットリンクを送信';

  @override
  String get settingsAccountSendingResetLink => '送信中…';

  @override
  String get settingsAccountResetLinkSent =>
      'リセットリンクを送信しました。メールを確認して新しいパスワードを設定してください。';

  @override
  String get settingsAccountChangeEmail => 'メールアドレスを変更';

  @override
  String get settingsAccountNewEmail => '新しいメールアドレス';

  @override
  String get settingsAccountEmailChangeInvalid =>
      '現在のアドレスと異なる有効なメールアドレスを入力してください。';

  @override
  String settingsAccountEmailChangePending(Object old, Object newEmail) {
    return '確認待ちです。以前の受信トレイ（$old）と新しい受信トレイ（$newEmail）の両方を確認し、それぞれのリンクを開いて変更を完了してください。両方で確認するまでメールアドレスは変更されません。';
  }

  @override
  String settingsAccountEmailChangeFailed(Object error) {
    return 'メールアドレスの変更を開始できませんでした：$error';
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
  String get settingsAccountCoachConsentWithdraw => 'AI機能への同意を撤回';

  @override
  String get settingsAccountCoachConsentActive =>
      'ThrekirのAI機能によるデータの使用を停止します。いつでも再度同意できます。';

  @override
  String get settingsAccountCoachConsentWithdrawn => 'AI機能への同意を撤回しました。';

  @override
  String settingsAccountCoachConsentWithdrawFailed(Object error) {
    return '撤回に失敗しました：$error';
  }

  @override
  String get settingsAccountAiConsentUpdateTitle => '更新されたAIの説明に同意する';

  @override
  String get settingsAccountAiConsentUpdateSubtitle =>
      '説明の対象となる機能が増えました。内容を確認して同意すると、AIルートアシスタントを利用できます。';

  @override
  String get settingsAccountAiConsentGrantTitle => 'AIの説明を確認する';

  @override
  String get settingsAccountAiConsentGrantSubtitle =>
      'ThrekirのAI機能は、データを使用する前に同意を求めます。説明を読み、ここで同意できます。';

  @override
  String get settingsAccountAiConsentAccepted => 'AIの説明に同意しました。';

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
  String settingsAccountBackupPartial(int count, int total) {
    return 'エクスポートは一部のみです — $total 件中 $count 件のラン。';
  }

  @override
  String settingsAccountBackupPartialNotice(int count, int total) {
    return '前回のエクスポートは一部のみです。アカウントにある $total 件のランのうち $count 件を含んでいます。データは削除されていません — もう一度エクスポートしてください。アカウント全体のアーカイブでは、不完全なセクションが manifest.json に記載されます。';
  }

  @override
  String settingsAccountBackupTracksPartial(int missing, int total) {
    return 'バックアップに GPS ファイルが $total 件中 $missing 件不足しています。';
  }

  @override
  String settingsAccountBackupTracksPartialNotice(int missing, int total) {
    return '前回のバックアップで GPS 軌跡ファイル $total 件中 $missing 件をダウンロードできませんでした。ランはすべてアーカイブに含まれています。軌跡を取り直すにはもう一度エクスポートしてください。manifest.json には complete: false と記録されています。';
  }

  @override
  String settingsAccountRestoreIncompleteArchive(int runs) {
    return 'このアーカイブは不完全であると自己申告しています。$runs 件のランを復元し、何も上書きしていません。欠落を埋めるには完全なバックアップから復元してください。';
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
  String get settingsAccountAvatar => 'プロフィール写真';

  @override
  String get settingsAccountAvatarHint => 'JPEG、PNG、WebP、2 MB まで。';

  @override
  String get settingsAccountAvatarRemove => '写真を削除';

  @override
  String get settingsAccountAvatarRemoveTitle => 'プロフィール写真を削除しますか？';

  @override
  String get settingsAccountAvatarRemoveConfirm =>
      '現在のプロフィール写真を削除します。新しい写真はいつでもアップロードできます。';

  @override
  String get settingsAccountAvatarSaved => 'プロフィール写真を更新しました。';

  @override
  String get settingsAccountAvatarRemoved => 'プロフィール写真を削除しました。';

  @override
  String get settingsAccountAvatarUnsupported =>
      '対応していない画像です — JPEG、PNG、WebP を選んでください。';

  @override
  String settingsAccountAvatarFailed(Object error) {
    return '写真を更新できませんでした: $error';
  }

  @override
  String get guidedRunsTitle => 'ガイド付きラン';

  @override
  String get guidedRunsSubtitle => 'コーチの音声とTTSキューによるスクリプト式ワークアウト';

  @override
  String get privacyZonesTitle => 'プライバシーゾーン';

  @override
  String get privacyZonesSubtitle => '自宅付近で公開トラックの開始・終了を切り取る';

  @override
  String get settingsAccountSendErrorReports => 'エラーレポートを送信';

  @override
  String get settingsAccountSendErrorReportsSubtitle =>
      '匿名化されたクラッシュ・エラーデータをSentry（米国）に送信します。オフにすると同意を撤回できます。次回起動時に適用されます。';

  @override
  String get settingsAccountDisplayName => '表示名';

  @override
  String get settingsAccountDisplayNameHint =>
      '他のランナーに表示される名前です。空欄にすると「Runner」が使われます。';

  @override
  String get settingsAccountDisplayNameUnset => '未設定 —「Runner」として表示されます';

  @override
  String get settingsAccountDisplayNameUpdated => '表示名を更新しました';

  @override
  String get settingsAccountDisplayNameUpdateFailed =>
      '表示名を更新できませんでした。もう一度お試しください。';

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
  String get settingsAccountAccountExport => 'アカウントのエクスポート';

  @override
  String get settingsAccountAccountExportSubtitle =>
      'ラン、ルート、メッセージ、注文、連携、緊急連絡先など、アカウントのすべて。サーバー側で作成するため、作成中はアプリを閉じてかまいません。';

  @override
  String get settingsAccountExportQueued =>
      'エクスポートを作成しています。アプリを閉じても大丈夫です — ダウンロードはこの画面に戻ってください。';

  @override
  String get settingsAccountExportBuildingNotice =>
      'アカウントのエクスポートを作成中です。アプリを閉じても、作成は続きます。';

  @override
  String get settingsAccountExportReadyNotice => 'アカウントのエクスポートの準備ができました。';

  @override
  String get settingsAccountExportDownload => 'ダウンロードして共有';

  @override
  String settingsAccountExportFailedNotice(String error) {
    return '前回のアカウントエクスポートは失敗しました ($error)。データは削除されていません — もう一度リクエストしてください。';
  }

  @override
  String get settingsAccountExportStalledNotice =>
      '前回のアカウントエクスポートが応答しなくなりました。データは削除されていません — もう一度リクエストしてください。';

  @override
  String get settingsAccountExportExpiredNotice =>
      '前回のアカウントエクスポートは期限切れです。エクスポートは 7 日後に削除されます — もう一度リクエストしてください。';

  @override
  String get settingsAccountExportStatusUnavailable =>
      'エクスポートサービスに接続できず、状態を確認できません。まだ作成中の可能性があります。';

  @override
  String get settingsAccountExportUnavailable =>
      'このビルドではアカウントエクスポートのサービスが設定されていません。下の完全バックアップはこの端末で作成され、アカウント記録は含まれません。';

  @override
  String settingsAccountExportUnsyncedWarning(int count) {
    return '$count 件のランがまだ同期されていません。アカウントのエクスポートはサーバーで作成されるため、それらは含まれません — 残すには完全バックアップを使ってください。';
  }

  @override
  String get settingsAccountBackupOnDeviceNotice =>
      '前回の完全バックアップはこの端末で作成されました。ラン、ルート、プロフィール、設定、ジムと食事の記録は含まれますが、アカウント記録は含まれません。完全なコピーはアカウントのエクスポートを使ってください。';

  @override
  String settingsAccountExportRateLimited(int seconds) {
    return 'エクスポートの上限に達しました — $seconds 秒後にもう一度お試しください。';
  }

  @override
  String settingsAccountExportRequestFailed(String error) {
    return 'エクスポートをリクエストできませんでした: $error';
  }

  @override
  String settingsAccountExportDownloadFailed(String error) {
    return 'エクスポートをダウンロードできませんでした: $error';
  }

  @override
  String settingsAccountExportReadyBanner(int count) {
    return 'アカウントのエクスポートの準備ができました — $count 件のラン。';
  }

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
  String integrationsSyncPartial(int imported, int skipped) {
    return '同期が途中で停止しました。新規 $imported 件、既存 $skipped 件 — 一部のアクティビティは取得されていません。もう一度同期して完了させてください。';
  }

  @override
  String integrationsSyncPartialRateLimited(int imported, int skipped) {
    return 'Strava がリクエストを制限しているため、同期が途中で停止しました。新規 $imported 件、既存 $skipped 件。約 15 分後にもう一度お試しください。';
  }

  @override
  String integrationsSyncResultWithFailed(
    int imported,
    int skipped,
    int failed,
  ) {
    return '同期しました。新規 $imported 件、既存 $skipped 件、失敗 $failed 件。';
  }

  @override
  String integrationsStravaConnectedPartial(int imported, int skipped) {
    return 'Strava を連携しましたが、最初のインポートが途中で停止しました。$imported 件をインポート、$skipped 件は既に存在します — もう一度同期して完了させてください。';
  }

  @override
  String integrationsStravaConnectedPartialRateLimited(
    int imported,
    int skipped,
  ) {
    return 'Strava を連携しましたが、Strava がリクエストを制限しているため最初のインポートが途中で停止しました。$imported 件をインポート、$skipped 件は既に存在します。約 15 分後にもう一度同期してください。';
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
  String integrationsImportPartialOf(int n, int total) {
    return '履歴の一部のみインポートできました: $total 件中 $n 件。';
  }

  @override
  String integrationsImportPartial(int n) {
    return 'すべての結果を読み取ることはできませんでした。インポート: $n 件。';
  }

  @override
  String get integrationsImportTruncated =>
      '結果リストが長すぎて最後まで読み取れなかったため、記録を確認できませんでした。代わりに手動で入力してください。';

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
  String get integrationsStravaSyncHistory => '過去の履歴を同期…';

  @override
  String get integrationsStravaLookbackTitle => 'さかのぼる期間';

  @override
  String get integrationsStravaLookback90 => '直近 90 日';

  @override
  String get integrationsStravaLookback180 => '直近 6 か月';

  @override
  String get integrationsStravaLookback365 => '直近 1 年';

  @override
  String get integrationsSyncPartialNoteResumable =>
      '前回の同期は期間の終わりまで届かずに停止しました。もう一度同期すると、停止した続きから再開します。';

  @override
  String get integrationsSyncPartialNote =>
      '前回の同期は期間の終わりまで届かずに停止し、再開位置は記録されていません。もう一度同期してやり直してください。';

  @override
  String get integrationsSyncNow => '今すぐ同期';

  @override
  String get integrationsParkrunName => 'parkrun';

  @override
  String get integrationsParkrunTileSubtitle => 'アスリート番号で結果をインポート';

  @override
  String get integrationsParkrunRegionNote =>
      'parkrun は一部の国でのみ開催されており、お近くにイベントがない場合があります。parkrun のアスリート番号があれば結果をインポートできます。';

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
  String get integrationsHrForgetConfirm =>
      'この心拍計を削除しますか？ランニング中に使うには再度ペアリングが必要です。';

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
  String get integrationsTreadmillTitle => 'トレッドミル';

  @override
  String get integrationsTreadmillChecking => '確認中…';

  @override
  String integrationsTreadmillPaired(String name) {
    return 'ペアリング済み: $name';
  }

  @override
  String get integrationsTreadmillNotPaired => 'トレッドミル未ペアリング — タップして検索';

  @override
  String get integrationsTreadmillForget => '解除';

  @override
  String get integrationsTreadmillForgetConfirm =>
      'このトレッドミルを解除しますか？ランニング中に使うには再度ペアリングが必要です。';

  @override
  String get integrationsTreadmillScanTitle => 'トレッドミルを検索';

  @override
  String get integrationsTreadmillScanHint =>
      'トレッドミルの Bluetooth がオンで、ベルトが起動していることを確認してください。検索には 3〜8 秒かかります。';

  @override
  String get integrationsTreadmillScanEmpty =>
      'トレッドミルが見つかりません。Bluetooth (FTMS) に対応し、近くにあることを確認してください。';

  @override
  String integrationsTreadmillPairFailed(Object error) {
    return 'ペアリングに失敗しました: $error';
  }

  @override
  String integrationsTreadmillLiveSpeed(String speed) {
    return '$speed km/h';
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
  String get proComingSoonTitle => 'Pro — 近日公開';

  @override
  String get proComingSoon => 'Pro は AI コーチを解放します — 近日公開。下からアプリを支援することはできます。';

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
  String get aboutTitle => 'アプリ情報とアップデート';

  @override
  String get aboutVersion => 'バージョン';

  @override
  String get licensesOpenSource => 'オープンソースライセンス';

  @override
  String get licensesOpenSourceSubtitle => 'このアプリに同梱されているサードパーティパッケージ';

  @override
  String get aboutCheckForUpdates => 'アップデートを確認';

  @override
  String get aboutCheckingUpdate => 'アップデートを確認中…';

  @override
  String get aboutUpdateAvailable => 'アップデートがあります';

  @override
  String get aboutUpdateAvailableSubtitle => '新しいバージョンをインストールできます。';

  @override
  String get aboutUpdate => '更新';

  @override
  String get aboutUpToDate => '最新バージョンです';

  @override
  String get aboutUpdateUnavailable => 'このビルドはインストール元のストアから更新されます。';

  @override
  String get aboutUpdateFailed => 'アップデートを開始できませんでした。Play ストアからもう一度お試しください。';

  @override
  String get legalPrivacy => 'プライバシーポリシー';

  @override
  String get legalTerms => '利用規約';

  @override
  String get legalCookieNotice => 'Cookie に関する通知';

  @override
  String get legalHealthDataNotice => '健康データのプライバシー';

  @override
  String get mapAttributionSemantics => '地図データの帰属表示';

  @override
  String mapAttributionProvider(String name) {
    return '© $name';
  }

  @override
  String mapAttributionOsmContributors(String name) {
    return '© $name コントリビューター';
  }

  @override
  String legalCouldNotOpen(String url) {
    return '$url を開けませんでした';
  }

  @override
  String get aboutLegalSection => '法的情報';

  @override
  String get devicesTitle => 'サインイン中のデバイス';

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
  String get gearRotationsTitle => 'ローテーション';

  @override
  String get gearRotationsHint =>
      'ローテーションで使うギアをグループ化します（「普段履き」セット、「レース用」セットなど）。ローテーションは名前付きのグループにすぎず、新しいランに自動でタグ付けされるペアは変わりません。';

  @override
  String get gearRotationsEmpty =>
      'ローテーションはまだありません。シューズやバイクのセットをまとめるには作成してください。';

  @override
  String get gearRotationName => 'ローテーション名';

  @override
  String get gearRotationNew => '新しいローテーション';

  @override
  String get gearRotationCreate => '作成';

  @override
  String get gearRotationRename => '名前を変更';

  @override
  String get gearRotationManage => 'ギアを編集';

  @override
  String gearRotationManageTitle(String name) {
    return '「$name」内のギア';
  }

  @override
  String get gearRotationDeleteTitle => 'ローテーションを削除しますか？';

  @override
  String gearRotationDeleteBody(String name) {
    return '「$name」ローテーションを削除しますか？ギアには影響しません。グループ分けのみが解除されます。';
  }

  @override
  String gearRotationMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件',
    );
    return '$_temp0';
  }

  @override
  String get gearRotationNoGear => 'まずギアを追加すると、ローテーションにまとめられます。';

  @override
  String gearRotationSaveFailed(Object error) {
    return 'ローテーションを保存できませんでした: $error';
  }

  @override
  String get gearRotationDone => '完了';

  @override
  String gearRotationNextUp(String name) {
    return '次に使うペア: $name';
  }

  @override
  String get gearRotationNextUpWhy => 'このローテーションで最も摩耗が少ないペアです。';

  @override
  String get gearRotationMakeCurrent => '現在のペアにする';

  @override
  String gearRotationMakeCurrentLabel(String name) {
    return '$name を現在のペアにします — 新しいランに自動でタグ付けされます';
  }

  @override
  String get gearRotationNextUpIsCurrent => 'すでに現在のペアです。';

  @override
  String get gearRotationAllWorn => 'ここにあるすべてのペアが交換の目安に達しています。';

  @override
  String gearRotationMakeCurrentFailed(Object error) {
    return '現在のペアを変更できませんでした: $error';
  }

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
  String get privacyZonesRemoveTitle => 'プライバシーゾーンを削除しますか？';

  @override
  String get privacyZonesRemoveBody =>
      'このゾーンは公開共有でこの付近のトラックを隠します。削除するとこのエリアが再び公開されます。';

  @override
  String get privacyZonesRemoveSemantics => 'プライバシーゾーンを削除';

  @override
  String get privacyZonesClearAllTitle => 'すべてのプライバシーゾーンを消去しますか？';

  @override
  String get privacyZonesClearAllBody => 'すべてのゾーンが削除され、これらのエリアが公開共有で再び公開されます。';

  @override
  String get privacyZonesDiscardBody => '保存されていないプライバシーゾーンがあります。保存せずに終了しますか？';

  @override
  String get discardChangesTitle => '変更を破棄しますか？';

  @override
  String get discardChangesBody => '保存されていない変更があります。保存せずに終了しますか？';

  @override
  String get discardChangesCancel => 'キャンセル';

  @override
  String get discardChangesDiscard => '破棄';

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
  String prefsSplitIntervalDefaultSubtitle(String run, String cycle) {
    return 'デフォルト（ランニングは$run、サイクリングは$cycle）';
  }

  @override
  String get prefsSplitPaceMode => 'スプリットの読み上げ';

  @override
  String get prefsSplitPaceModeSubtitle => '各スプリットで読み上げるペース';

  @override
  String get prefsSplitPaceModeSplit => 'スプリットのペース';

  @override
  String get prefsSplitPaceModeAverage => '平均ペース';

  @override
  String get prefsSplitPaceModeBoth => '両方';

  @override
  String get prefsSplitPaceModeInfo =>
      '各スプリットで聞くペースを選べます。そのスプリットだけのペース、ここまでのラン全体の平均ペース、またはその両方です。一定のペースを保つのに便利です。例：「1キロメートル。平均ペース、1キロメートルあたり5分45秒。」';

  @override
  String get prefsTargetPace => '目標ペース';

  @override
  String get prefsTargetPaceInfo =>
      '維持したいペースです。単独では音声は鳴りません。音声キュー「ペースずれアラート」をオンにすると、30秒以上ずれたときに「ペースを上げて」「ペースを落として」と読み上げます。例：「8秒ペースを上げてください。」';

  @override
  String get prefsCueInfoTooltip => 'これは何？';

  @override
  String get prefsLivePaceAlert => '目標ペース';

  @override
  String get prefsLivePaceAlertMin => '分';

  @override
  String get prefsLivePaceAlertSec => '秒';

  @override
  String get prefsLivePaceAlertOff => '未設定 — 目標を設定し、「ペースずれアラート」をオンにしてください';

  @override
  String prefsLivePaceAlertOn(String pace, String paceLabel) {
    return '$pace $paceLabel — 30秒以上ずれると「ペースずれアラート」が読み上げます';
  }

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
  String get prefsPushNotifications => 'プッシュ通知';

  @override
  String get prefsPushNotifAll => 'すべて';

  @override
  String get prefsPushNotifImportant => '重要なものだけ';

  @override
  String get prefsPushNotifOff => 'オフ';

  @override
  String get prefsEmailWeeklyDigest => '週刊ダイジェストメール';

  @override
  String get prefsEmailWeeklyDigestHint =>
      'トレーニングとコミュニティのハイライトをまとめた週刊メールを受け取ります。初期設定はオフで、通知メールとは別です。';

  @override
  String get prefsEmailLifecycleDrip => 'ヒントと応援メール';

  @override
  String get prefsEmailLifecycleDripHint =>
      'オンボーディング、再開、連続記録のリマインダーを時々受け取ります。初期設定はオフで、週刊ダイジェストや通知メールとは別です。';

  @override
  String get prefsEmailReOptInFailed =>
      '以前の配信停止を解除できませんでした。メールがブロックされたままの可能性があります。もう一度お試しください。';

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
  String get prefsSectionFueling => 'レース補給';

  @override
  String get prefsCarbsPerHour => '1時間あたりの炭水化物';

  @override
  String prefsCarbsPerHourValue(int grams) {
    return '$grams g/h';
  }

  @override
  String get prefsFluidPerHour => '1時間あたりの水分';

  @override
  String prefsFluidPerHourValue(int ml) {
    return '$ml ml/h';
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
  String get prefsAudioCuesSubtitle => 'ラン中にスプリット・ペースなどの音声を読み上げます';

  @override
  String get prefsMinimalVoiceCues => '最小限の音声キュー';

  @override
  String get prefsMinimalVoiceCuesSubtitle => 'おしゃべりなレップ途中やペースのずれの通知を省きます';

  @override
  String get prefsKeepScreenOn => '画面をオンのままにする';

  @override
  String get prefsKeepScreenOnSubtitle =>
      'ラン中は画面を点灯したままにします。長時間のランではバッテリー消費が大きくなります。';

  @override
  String get prefsDimScreenWhileRecording => '記録中に画面を暗くする';

  @override
  String get prefsDimScreenWhileRecordingSubtitle =>
      'ラン中にマップを暗くしてバッテリーを節約します。統計情報は引き続き見やすく表示されます。';

  @override
  String get prefsAdvancedGps => '高度なGPS';

  @override
  String get prefsAdvancedGpsSubtitle => '高精度、より細かいトラック、バッテリー消費増';

  @override
  String get prefsShowRawTrack => '生のGPSトラックを表示';

  @override
  String get prefsShowRawTrackSubtitle =>
      '補正済みのトラックがある場合でも、未補正の記録ラインをランマップに描画します';

  @override
  String get prefsShowCalories => 'カロリー推定を表示';

  @override
  String get prefsShowCaloriesHint =>
      '距離と体重から推定します（未設定の場合は70 kgを使用）。オフにするとラン詳細ページのカロリー表示を非表示にします。';

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
  String get dashboardProfileTooltip => 'あなたのプロフィール';

  @override
  String get dashboardWelcomeTitle => 'ようこそ！';

  @override
  String get dashboardWelcomeBody =>
      'ランを記録したり、目標を設定したり、履歴をインポートすると、ダッシュボードが充実します。';

  @override
  String get dashboardStartRun => 'ランを開始';

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
  String get dashboardWeekStripTitle => '今週';

  @override
  String dashboardWeekStripCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアクティビティ',
    );
    return '$_temp0';
  }

  @override
  String dashboardWeekStripDayAria(String dow, String dist) {
    return '$dow: $dist';
  }

  @override
  String dashboardWeekStripDayRestAria(String dow) {
    return '$dow: 休息日';
  }

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
  String dashboardPbAgeGrade(String percent) {
    return '年齢別評価 $percent';
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
  String get dashboardHeatmapTitle => 'アクティビティ';

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
  String get runSocialReportComment => 'コメントを報告';

  @override
  String get runSocialReportReply => '返信を報告';

  @override
  String get runSocialPost => '投稿';

  @override
  String get runSocialCancel => 'キャンセル';

  @override
  String get kudosGiveLabel => '称賛する';

  @override
  String get kudosRemoveLabel => '称賛を取り消す';

  @override
  String get kudosViewCommentsLabel => 'コメントを表示';

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
  String get runPhotosPermissionDenied => '写真を追加するには写真へのアクセスが必要です。設定で許可できます。';

  @override
  String get runPhotosOpenSettings => '設定を開く';

  @override
  String get runPhotosPickerFailed => '写真の選択ツールを開けませんでした。もう一度お試しください。';

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
  String get routePhotosLoading => '写真を読み込み中…';

  @override
  String get routePhotosTitle => '写真';

  @override
  String get routePhotosAdd => '写真を追加';

  @override
  String get routePhotosCaptionPendingHint => 'キャプション（任意、280文字）';

  @override
  String get routePhotosCaptionHint => 'キャプション…';

  @override
  String get routePhotosCancel => 'キャンセル';

  @override
  String get routePhotosSave => '保存';

  @override
  String get routePhotosUpload => 'アップロード';

  @override
  String get routePhotosUploading => 'アップロード中…';

  @override
  String get routePhotosEditCaption => 'キャプションを編集';

  @override
  String get routePhotosDeleteTooltip => '写真を削除';

  @override
  String get routePhotosDeleteTitle => '写真を削除しますか？';

  @override
  String get routePhotosDeleteBody => 'この操作で写真はルートから完全に削除されます。';

  @override
  String get routePhotosDeleteConfirm => '削除';

  @override
  String routePhotosPickerError(String error) {
    return 'ピッカーを開けませんでした: $error';
  }

  @override
  String routePhotosUploadError(String error) {
    return 'アップロードに失敗しました: $error';
  }

  @override
  String routePhotosDeleteError(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String routePhotosCaptionError(String error) {
    return 'キャプションを更新できませんでした: $error';
  }

  @override
  String get clubPhotosLoading => '写真を読み込み中…';

  @override
  String get clubPhotosTitle => '写真';

  @override
  String get clubPhotosAdd => '写真を追加';

  @override
  String get clubPhotosEmpty => 'このクラブにはまだ写真がありません。';

  @override
  String get clubPhotosCaptionPendingHint => 'キャプション（任意、280文字）';

  @override
  String get clubPhotosCaptionHint => 'キャプション…';

  @override
  String get clubPhotosCancel => 'キャンセル';

  @override
  String get clubPhotosSave => '保存';

  @override
  String get clubPhotosUpload => 'アップロード';

  @override
  String get clubPhotosUploading => 'アップロード中…';

  @override
  String get clubPhotosEditCaption => 'キャプションを編集';

  @override
  String get clubPhotosDeleteTooltip => '写真を削除';

  @override
  String get clubPhotosDeleteTitle => '写真を削除しますか？';

  @override
  String get clubPhotosDeleteBody => 'この操作で写真はクラブから完全に削除されます。';

  @override
  String get clubPhotosDeleteConfirm => '削除';

  @override
  String clubPhotosPickerError(String error) {
    return 'ピッカーを開けませんでした: $error';
  }

  @override
  String clubPhotosUploadError(String error) {
    return 'アップロードに失敗しました: $error';
  }

  @override
  String clubPhotosDeleteError(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String clubPhotosCaptionError(String error) {
    return 'キャプションを更新できませんでした: $error';
  }

  @override
  String get runSegEffortsRankUnknown => '順位を取得できません';

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
  String get workoutReviewAdherenceCompleted => '完了';

  @override
  String get workoutReviewAdherencePartial => '一部完了';

  @override
  String get workoutReviewAdherenceAbandoned => '中断';

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
  String get segmentsPanelLoadError => 'セグメントを読み込めませんでした';

  @override
  String get segmentsPanelLeaderboardError => 'ランキングを読み込めませんでした';

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
  String get segmentsPanelErrNameRequired => 'セグメント名を入力してください';

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
  String goalEditorSaveFailed(String error) {
    return '目標を保存できませんでした: $error';
  }

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
  String get eventEditorCategory => 'イベントの種類';

  @override
  String get eventEditorCatRun => 'グループラン';

  @override
  String get eventEditorCatCycle => 'サイクリング';

  @override
  String get eventEditorCatClass => 'クラス';

  @override
  String get eventEditorCatSocial => 'ソーシャル';

  @override
  String get eventEditorCategoryHint =>
      'イベントの種類を選びます。クラスやソーシャルの集まりではルート、距離、ペース、レース結果は省略されます。';

  @override
  String get eventEditorMembersOnlyToggle => 'メンバー限定';

  @override
  String get eventEditorMembersOnlyHint =>
      'クラブのメンバーだけがこのイベントを見ることができ、公開検索には表示されません。';

  @override
  String get eventEditorDiscipline => '種目';

  @override
  String get eventEditorDisciplinePlaceholder => '例：ヴィンヤサヨガ、ピラティス、モビリティ';

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
  String get clubFormErrName => 'クラブに名前を付けてください。';

  @override
  String get clubFormErrSlug => '名前には少なくとも 1 文字または数字が必要です。';

  @override
  String get eventFormErrTitle => 'イベントにタイトルを付けてください。';

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
  String get reportTitleComment => 'コメントを報告';

  @override
  String get reportTitlePost => '投稿を報告';

  @override
  String get reportTitleRun => 'ランを報告';

  @override
  String get reportTitleReview => 'レビューを報告';

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
  String get runGearChipsLoadFailed => 'ギアを読み込めませんでした。';

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
  String get gearWearLogHeading => '摩耗ログ';

  @override
  String get gearWearLogHint =>
      'このギアの経年変化を記録します — アウトソールの摩耗、ヘタったミッドソール、ほつれたアッパーなど。';

  @override
  String get gearWearLogEmpty => 'まだ摩耗の記録がありません。';

  @override
  String get gearWearLogAddNote => '観察メモ';

  @override
  String get gearWearLogNoteHint => '例: かかとのアウトソールがすり減った';

  @override
  String get gearWearLogArea => '部位';

  @override
  String get gearWearLogAreaNone => '—';

  @override
  String get gearWearLogAreaOutsole => 'アウトソール';

  @override
  String get gearWearLogAreaMidsole => 'ミッドソール';

  @override
  String get gearWearLogAreaUpper => 'アッパー';

  @override
  String get gearWearLogAreaOther => 'その他';

  @override
  String get gearWearLogAdd => '観察メモを追加';

  @override
  String get gearWearLogAdding => '追加中…';

  @override
  String get gearWearLogDelete => '観察メモを削除';

  @override
  String gearWearLogAddError(String error) {
    return '観察メモを追加できませんでした: $error';
  }

  @override
  String gearWearLogDeleteError(String error) {
    return '観察メモを削除できませんでした: $error';
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
  String ttsSplitAverage(String count, String unit, String tail) {
    return '$count$unit。平均$tail';
  }

  @override
  String ttsSplitBoth(String count, String unit, String tail, String avgTail) {
    return '$count$unit。$tail。平均$avgTail';
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
  String get planPhaseGraduation => '修了週';

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
  String get settingsDevicesSignedOutSubtitle => 'サインインすると、サインイン中のデバイスを確認できます';

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
  String get settingsTabAccountSubtitle => 'サインイン、プロフィール、インポートとバックアップ、アカウント削除';

  @override
  String get settingsTabPreferencesSubtitle => '単位、テーマ、記録、トレーニング、プライバシー';

  @override
  String get settingsTabIntegrationsSubtitle =>
      'Strava、parkrun、レースカレンダー、心拍ベルト、トレッドミル、ウォッチ';

  @override
  String get settingsTabDevicesSubtitle =>
      'サインイン中の場所とデバイスごとの上書き設定。ベルトやトレッドミルのペアリングは「連携」から';

  @override
  String get settingsTabGearSubtitle => 'シューズ・バイクとアイテムごとの走行距離を記録';

  @override
  String get settingsTabCoachingSubtitle => 'アスリートを指導したり、自分のコーチをフォロー';

  @override
  String get settingsTabProSubtitle => '登録、購入の復元、請求の管理';

  @override
  String get settingsTabAboutSubtitle => 'バージョン、アップデート、法的文書';

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
  String gymDeleteFailed(Object error) {
    return 'ワークアウトを削除できませんでした: $error';
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
  String get gymDistance => '距離 (m)';

  @override
  String gymDistanceValue(String metres) {
    return '$metres m';
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
  String get clubEventMembersOnly => 'メンバー限定';

  @override
  String get clubEventLogAsWorkout => 'ワークアウトとして記録';

  @override
  String get clubEventLogAsWorkoutHint =>
      'このクラスを自分のジムログに追加します — 保存前に詳細を調整できます。';

  @override
  String get clubEventLogAsWorkoutSaved => 'ジムログに追加しました';

  @override
  String get clubEventAddToCalendar => 'カレンダーに追加';

  @override
  String get clubEventAddOccurrenceToCalendar => 'この回を追加';

  @override
  String get clubEventAddSeriesToCalendar => 'シリーズ全体を追加';

  @override
  String get clubEventCalendarUnavailable => 'カレンダーアプリを開けませんでした。';

  @override
  String clubEventCalendarCancelledNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'カレンダーは中止された日を除外できないため、中止された$count回もそのまま表示されます。',
    );
    return '$_temp0';
  }

  @override
  String get clubEventDownloadCertificate => '完走証';

  @override
  String get clubEventCertificateShare => '保存または共有';

  @override
  String clubEventCertificateShareText(String event) {
    return '$event を完走しました！';
  }

  @override
  String get clubEventCertificateFailed => '証明書を作成できませんでした。もう一度お試しください。';

  @override
  String get clubEventCertificateHeading => '完走証明書';

  @override
  String get clubEventCertificateCertifies => '以下を証明します';

  @override
  String get clubEventCertificateCompleted => 'が完走しました';

  @override
  String get clubEventCertificateTime => 'タイム';

  @override
  String get clubEventCertificateDistance => '距離';

  @override
  String clubEventCertificatePlace(String place) {
    return '$place位';
  }

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
  String get gymCatalogueBrowse => 'カタログを見る';

  @override
  String get gymCatalogueTitle => '種目カタログ';

  @override
  String get gymCatalogueSearchPlaceholder => '種目を検索';

  @override
  String get gymCatalogueCategoryLabel => 'カテゴリ';

  @override
  String get gymCatalogueEmpty => '該当する種目がありません。';

  @override
  String gymCatalogueOtherCategory(String name, String category) {
    return '「$name」はすでにカタログにあります（$category）。';
  }

  @override
  String get gymCatalogueCustomBadge => 'カスタム';

  @override
  String gymCatalogueCreate(String name) {
    return '「$name」をカスタム種目として追加';
  }

  @override
  String get gymCatalogueCreateFailed => '種目を追加できませんでした。';

  @override
  String get gymCatalogueCategoryAll => 'すべて';

  @override
  String get gymCatalogueCategoryChest => '胸';

  @override
  String get gymCatalogueCategoryBack => '背中';

  @override
  String get gymCatalogueCategoryShoulders => '肩';

  @override
  String get gymCatalogueCategoryLegs => '脚';

  @override
  String get gymCatalogueCategoryArms => '腕';

  @override
  String get gymCatalogueCategoryCore => '体幹';

  @override
  String get gymCatalogueCategoryCardio => '有酸素';

  @override
  String get gymCatalogueCategoryFullBody => '全身';

  @override
  String get gymCatalogueCategoryOther => 'その他';

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
  String get gymRoutinePublishLabel => 'クラブに公開';

  @override
  String get gymRoutinePublishPick => 'クラブを選択…';

  @override
  String get gymRoutinePublish => '公開';

  @override
  String get gymRoutinePublishSuccess => 'ルーティンをクラブに公開しました。';

  @override
  String get gymRoutinePublishFailed => 'ルーティンを公開できませんでした。';

  @override
  String get gymRoutineHistoryTitle => 'ルーティン履歴';

  @override
  String get gymRoutineHistoryRecent => '最近のセッション';

  @override
  String gymRoutineHistoryLastDone(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days日前に実施',
      one: '昨日実施',
      zero: '今日実施',
    );
    return '$_temp0';
  }

  @override
  String gymRoutineHistoryCompletedRate(int completed, int graded) {
    return '$graded件中$completed件を完了';
  }

  @override
  String get gymRoutineHistoryVerdictUngraded => '評価なし';

  @override
  String get gymRoutineHistoryLoadError => 'このルーティンの履歴を読み込めませんでした。';

  @override
  String get gymRoutineClubTemplateBadge => 'クラブテンプレート';

  @override
  String get gymRoutinePublicBadge => '公開ライブラリに掲載中';

  @override
  String get gymRoutinePublishPublicLabel => '公開ライブラリ';

  @override
  String get gymRoutinePublishPublic => '公開ライブラリに公開';

  @override
  String get gymRoutineUnpublishPublic => '公開ライブラリから削除';

  @override
  String get gymRoutinePublishPublicHint =>
      'サインインしているユーザーは誰でもこのルーティンをプレビューして取り込めます。記録したワークアウトは非公開のままです。';

  @override
  String get gymRoutinePublishPublicSuccess => 'ルーティンを公開ライブラリに公開しました。';

  @override
  String get gymRoutineUnpublishPublicSuccess => 'ルーティンを公開ライブラリから削除しました。';

  @override
  String get gymRoutinePublishPublicFailed => '公開設定を変更できませんでした。';

  @override
  String get gymLibraryLink => 'ライブラリ';

  @override
  String get gymLibraryTitle => '公開ルーティンライブラリ';

  @override
  String get gymLibrarySearchHint => '名前でルーティンを検索';

  @override
  String get gymLibraryLoadError => 'ライブラリを読み込めませんでした。';

  @override
  String get gymLibraryEmpty => '公開されたルーティンはまだありません。';

  @override
  String gymLibraryEmptySearch(String query) {
    return '「$query」に一致するルーティンはありません。';
  }

  @override
  String gymLibraryByAuthor(String author) {
    return '$author 作成';
  }

  @override
  String get gymLibraryAnonymous => 'あるユーザー';

  @override
  String get gymLibraryAdopt => '自分のルーティンに取り込む';

  @override
  String get gymLibraryAdopting => '取り込み中…';

  @override
  String get gymLibraryAdoptFailed => 'ルーティンを取り込めませんでした。';

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
  String get gymRoutineNextTargetEstablishBaseline => '基準を設定 — 開始重量を決める';

  @override
  String get gymRoutineNextTargetDeload => 'ディロード — 重量を下げる';

  @override
  String gymRoutineNextTargetRepClimb(int from, int to) {
    return '回数アップ $from→$to';
  }

  @override
  String get nutritionTitle => '栄養';

  @override
  String get nutritionDayNavLabel => '記録する日';

  @override
  String get nutritionDayPrevious => '前の日';

  @override
  String get nutritionDayNext => '次の日';

  @override
  String get nutritionDayToday => '今日';

  @override
  String get nutritionDayYesterday => '昨日';

  @override
  String get nutritionDayBackfillHint => 'ここで記録した内容はこの日に追加されます。';

  @override
  String get nutritionDayEmptyPast => 'この日は何も記録されていません。';

  @override
  String nutritionDayGoalBreakdown(int base, int exercise) {
    return '目標 $base + この日の消費 $exercise kcal';
  }

  @override
  String nutritionDayTrendEnding(String date) {
    return '$date までの7日間';
  }

  @override
  String nutritionDayLogHeadingFor(String date) {
    return '食事を記録 — $date';
  }

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
  String get nutritionFiber => '食物繊維';

  @override
  String get nutritionSugar => '糖質';

  @override
  String get nutritionSodium => 'ナトリウム';

  @override
  String get nutritionSaturatedFat => '飽和脂肪';

  @override
  String get nutritionCholesterol => 'コレステロール';

  @override
  String get nutritionNutrients => '栄養素';

  @override
  String get nutritionNutrientsHint =>
      '参考摂取量です。各合計には、その栄養素の値がある記録済みの食品のみが含まれます。';

  @override
  String get nutritionNutrientAtLeast => '少なくとも';

  @override
  String nutritionNutrientPartial(int reported, int total, String nutrient) {
    return '記録した$total件中$reported件に$nutrientの値があります';
  }

  @override
  String nutritionNutrientOver(String n, String unit) {
    return '$n $unit 超過';
  }

  @override
  String nutritionNutrientLeft(String n, String unit) {
    return '残り $n $unit';
  }

  @override
  String get nutritionNutrientReached => '目標達成';

  @override
  String get nutritionNutrientUntargeted => '1日の目標なし';

  @override
  String get nutritionWater => '水分';

  @override
  String get nutritionWaterAdd => '水分を追加';

  @override
  String get nutritionWaterRemove => '水分を減らす';

  @override
  String get nutritionNoTargets => 'カロリー・マクロの目標を表示するには、身長・体重・年齢・性別を入力してください。';

  @override
  String get nutritionAddBodyMetrics => '身体データを入力';

  @override
  String get nutritionTargetsLink => '目標';

  @override
  String get nutritionTargetsTitle => 'カロリー・マクロの目標';

  @override
  String get nutritionTargetsSubtitle => '今日の目標がどう計算されるか、そしてそれを決める2つの設定。';

  @override
  String get nutritionTargetsTotal => '今日の摂取目標';

  @override
  String get nutritionTargetsBmr => '安静時代謝';

  @override
  String get nutritionTargetsBase => '基礎目標';

  @override
  String nutritionTargetsBaseFloored(int n) {
    return '下限の$n kcalで止めています。これが推奨する最低の1日目標です。';
  }

  @override
  String get nutritionTargetsExercise => '今日のワークアウト';

  @override
  String get nutritionTargetsExerciseHint => '今日記録したランやジムのセッションが上乗せされます。';

  @override
  String get nutritionTargetsMacrosHeading => 'マクロ';

  @override
  String nutritionTargetsProteinHint(String n) {
    return '体重1 kgあたり$n g';
  }

  @override
  String get nutritionTargetsCarbsHint => '残りすべて — あなたの燃料';

  @override
  String nutritionTargetsFatHint(int n) {
    return 'カロリーの$n%';
  }

  @override
  String get nutritionTargetsDefaultsHeading => '既定値';

  @override
  String get nutritionTargetsDefaultsHint =>
      '活動レベルはワークアウトを除いた普段の一日です。記録したランやジムのセッションは別に加算されます。どちらも変更するとすぐ保存されます。';

  @override
  String get nutritionTargetsMetricsHeading => '身体データ';

  @override
  String get nutritionTargetsMetricsHint =>
      '身長・体重・生年月日・性別は健康データのため、同意のうえ設定で編集します。';

  @override
  String get nutritionTargetsEditMetrics => '設定で編集';

  @override
  String get nutritionTargetsUnset => '未設定';

  @override
  String get nutritionTargetsEmptyTitle => 'まだ目標がありません';

  @override
  String get nutritionTargetsEmptyBody =>
      '身長・体重・生年月日・性別を入力すると、カロリー・マクロの目標がここに表示されます。';

  @override
  String get nutritionTargetsAge => '年齢';

  @override
  String nutritionTargetsAgeYears(int n) {
    return '$n歳';
  }

  @override
  String get nutritionTargetsAgeConsentWithheld => '健康データの同意が必要です';

  @override
  String get nutritionTargetsLoadError => '目標を読み込めませんでした。';

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
  String nutritionWeekProtein(int met, int total) {
    return 'タンパク質 $met/$total日';
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
  String nutritionDeleteFailed(String error) {
    return 'エントリーを削除できませんでした: $error';
  }

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
  String get nutritionSearchFailed => '検索に失敗しました。接続を確認して再試行するか、下から手動で入力してください。';

  @override
  String get nutritionSearchRetry => '検索を再試行';

  @override
  String get nutritionSourceOff => 'Open Food Facts';

  @override
  String get nutritionSourceUsda => 'USDA';

  @override
  String get nutritionScanBarcode => 'バーコードをスキャン';

  @override
  String get nutritionScanHint => 'カメラを商品のバーコードに向けてください';

  @override
  String get nutritionScanLookingUp => '検索中…';

  @override
  String get nutritionScanNotFound => 'そのバーコードの商品が見つかりませんでした。検索するか手動で入力してください。';

  @override
  String get nutritionScanFailed => 'スキャンに失敗しました。検索するか手動で入力してください。';

  @override
  String get nutritionScanPermissionDenied =>
      'バーコードのスキャンにはカメラへのアクセスが必要です。検索や手動入力は引き続き利用できます。';

  @override
  String get nutritionScanOpenSettings => '設定を開く';

  @override
  String get nutritionSaveFailed => '食事を記録できませんでした。もう一度お試しください。';

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
  String get nutritionTemplates => '食事テンプレート';

  @override
  String get nutritionSaveAsMeal => '食事として保存';

  @override
  String get nutritionSaveAsMealTitle => '食事テンプレートとして保存';

  @override
  String get nutritionTemplateName => 'テンプレート名';

  @override
  String get nutritionTemplateNamePlaceholder => '例: ランニング前の朝食';

  @override
  String get nutritionSaveTemplate => '食事を保存';

  @override
  String get nutritionTemplateSaved => '食事テンプレートを保存しました。';

  @override
  String nutritionTemplateSaveFailed(String error) {
    return 'テンプレートを保存できませんでした: $error';
  }

  @override
  String get nutritionLogTemplate => '記録';

  @override
  String nutritionTemplateLogged(int n, String name) {
    return '$name から $n 件を記録しました。';
  }

  @override
  String nutritionTemplateLogFailed(String error) {
    return 'テンプレートを記録できませんでした: $error';
  }

  @override
  String nutritionTemplateDeleteFailed(String error) {
    return 'テンプレートを削除できませんでした: $error';
  }

  @override
  String nutritionTemplateItems(int n) {
    return '$n 件';
  }

  @override
  String get nutritionDeleteTemplate => '削除';

  @override
  String get nutritionDeleteTemplateTitle => 'この食事テンプレートを削除しますか？';

  @override
  String nutritionDeleteTemplateMessage(String name) {
    return '$name を削除します。これまでに記録済みの食事は日記に残ります。';
  }

  @override
  String get nutritionRecipes => 'レシピ';

  @override
  String get nutritionSaveAsRecipe => 'レシピとして保存';

  @override
  String get nutritionSaveAsRecipeTitle => 'レシピとして保存';

  @override
  String get nutritionRecipeName => 'レシピ名';

  @override
  String get nutritionRecipeNamePlaceholder => '例：チキンライスボウル';

  @override
  String get nutritionRecipeServings => '人前';

  @override
  String get nutritionRecipeServingsHint =>
      '材料を合計し、人前で割ります。1人前を記録すると、合算したマクロで1件の記録が追加されます。';

  @override
  String get nutritionSaveRecipe => 'レシピを保存';

  @override
  String get nutritionRecipeSaved => 'レシピを保存しました。';

  @override
  String nutritionRecipeSaveFailed(String error) {
    return 'レシピを保存できませんでした：$error';
  }

  @override
  String get nutritionLogRecipe => '記録';

  @override
  String nutritionRecipeLogged(int n, String name) {
    return '$name を記録しました（$n人前）。';
  }

  @override
  String nutritionRecipeLogFailed(String error) {
    return 'レシピを記録できませんでした：$error';
  }

  @override
  String nutritionRecipeDeleteFailed(String error) {
    return 'レシピを削除できませんでした: $error';
  }

  @override
  String nutritionRecipeMeta(int n, num servings) {
    final intl.NumberFormat servingsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String servingsString = servingsNumberFormat.format(servings);

    return '材料$n件・$servingsString人前';
  }

  @override
  String get nutritionDeleteRecipe => '削除';

  @override
  String get nutritionDeleteRecipeTitle => 'このレシピを削除しますか？';

  @override
  String nutritionDeleteRecipeMessage(String name) {
    return '$name を削除します。これまでに記録済みの食事は日記に残ります。';
  }

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
  String get gymSessionLeaveSaveFailed =>
      '下書きを保存できませんでした。まだこの画面にいるので、内容は失われていません。再試行するか、意図的にセッションを破棄してください。';

  @override
  String get gymSessionLeaveTitle => 'セッションを中断しますか？';

  @override
  String get gymSessionLeaveBody =>
      '記録済みのセットは下書きとして保存されます。ジムタブからセッションを再開するか、破棄できます。';

  @override
  String get gymSessionLeaveDraft => '中断して下書きを保存';

  @override
  String get gymSessionKeepGoing => '続ける';

  @override
  String get gymDraftTitle => '進行中のワークアウト';

  @override
  String gymDraftSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countセット記録済み',
    );
    return '$_temp0';
  }

  @override
  String get gymDraftResume => '再開';

  @override
  String get gymDraftSave => 'このまま保存';

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
  String get coachingTitle => 'アスリートとコーチ';

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
  String get coachingRosterTitle => 'アスリート一覧';

  @override
  String get coachingRosterSubtitle => '負荷・プラン達成率・けがリスクをひと目で確認できます。';

  @override
  String get coachingRosterNeverRun => 'ランの記録なし';

  @override
  String get coachingRosterNoPlan => 'プランなし';

  @override
  String get coachingRosterRiskInsufficient => '新規';

  @override
  String get coachingRosterRiskLow => '低';

  @override
  String get coachingRosterRiskOptimal => '最適';

  @override
  String get coachingRosterRiskElevated => 'やや高';

  @override
  String get coachingRosterRiskHigh => '高';

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

  @override
  String get routeMarkerHeading => 'コースマーカー';

  @override
  String get routeMarkerAdd => 'マーカーを追加';

  @override
  String get routeMarkerEmpty => 'コースマーカーはまだありません。エイドステーションや関門などをルート上に追加しましょう。';

  @override
  String get routeMarkerEdit => 'マーカーを編集';

  @override
  String get routeMarkerDelete => '削除';

  @override
  String get routeMarkerCancel => 'キャンセル';

  @override
  String get routeMarkerSave => '保存';

  @override
  String get routeMarkerSaving => '保存中…';

  @override
  String get routeMarkerKindLabel => '種類';

  @override
  String get routeMarkerNameLabel => '名前';

  @override
  String get routeMarkerNamePlaceholder => '例: エイド2';

  @override
  String get routeMarkerServicesLabel => 'サービス';

  @override
  String get routeMarkerCutoffLabel => '関門時刻';

  @override
  String get routeMarkerCutoffInvalid => '関門時刻は HH:MM（24時間制）で入力してください';

  @override
  String get routeMarkerTimeClock => '時刻';

  @override
  String get routeMarkerTimeElapsed => '経過';

  @override
  String get routeMarkerNoteLabel => 'メモ';

  @override
  String get routeMarkerTapToPlace => '地図をタップしてマーカーを配置します。';

  @override
  String get routeMarkerSnapToggle => 'ルートの線に沿わせる';

  @override
  String get routeMarkerPlaced => '配置しました。もう一度地図をタップすると移動できます。';

  @override
  String routeMarkerCutoffAt(String time) {
    return '関門 $time';
  }

  @override
  String get routeMarkerLabelRequired => 'マーカーに名前を付けてください。';

  @override
  String get routeMarkerPlaceRequired => '先に地図上にマーカーを配置してください。';

  @override
  String get routeMarkerLatLabel => '緯度';

  @override
  String get routeMarkerLngLabel => '経度';

  @override
  String get routeMarkerCoordInvalid => '有効な緯度（-90〜90）と経度（-180〜180）を入力してください。';

  @override
  String get routeMarkerEnterCoords => '代わりに位置を入力';

  @override
  String routeMarkerSaveFailed(String error) {
    return 'マーカーを保存できませんでした: $error';
  }

  @override
  String routeMarkerDeleteFailed(String error) {
    return 'マーカーを削除できませんでした: $error';
  }

  @override
  String get routeMarkerKindAidStation => 'エイドステーション';

  @override
  String get routeMarkerKindCutoff => '関門';

  @override
  String get routeMarkerKindCrewAccess => 'クルー / 駐車';

  @override
  String get routeMarkerKindHazard => '危険箇所';

  @override
  String get routeMarkerKindNote => 'メモ';

  @override
  String get routeMarkerKindClimb => '登り';

  @override
  String get routeMarkerKindCustom => 'カスタム';

  @override
  String get routeMarkerServiceWater => '水';

  @override
  String get routeMarkerServiceFood => '補給食';

  @override
  String get routeMarkerServiceMedical => '救護';

  @override
  String get routeMarkerServiceToilets => 'トイレ';

  @override
  String get routeMarkerServiceDropBag => 'ドロップバッグ';

  @override
  String get clubFormEditTitle => 'クラブを編集';

  @override
  String get clubEditorWebsite => 'ウェブサイト';

  @override
  String get clubEditorInstagram => 'Instagram';

  @override
  String get clubEditorStrava => 'Strava';

  @override
  String get clubEditorFacebook => 'Facebook';

  @override
  String get clubEditorSaveChanges => '変更を保存';

  @override
  String get clubDetailVisitWebsite => 'ウェブサイトを見る';

  @override
  String get clubDetailEditClub => 'クラブを編集';

  @override
  String get roadbookTitle => 'ロードブック';

  @override
  String get roadbookCrewSheet => 'ロードブック（クルーシート）';

  @override
  String get roadbookGoalTime => '目標タイム';

  @override
  String get roadbookStartTime => 'スタート時刻';

  @override
  String get roadbookPlanTitle => 'レースプラン';

  @override
  String get roadbookPlanExplain =>
      '時計はこれをもとに到達予想時刻と関門時刻を計算します。時刻で指定された関門も送るには、スタート時刻を設定してください。';

  @override
  String get roadbookPlanCancel => 'キャンセル';

  @override
  String get roadbookPlanSend => '送信';

  @override
  String get roadbookPlanGoalInvalid => '4:30:00 のような目標タイムを入力してください';

  @override
  String get roadbookEffort => '強度ベース';

  @override
  String get roadbookEven => 'イーブン';

  @override
  String get roadbookStart => 'スタート';

  @override
  String get roadbookFinish => 'フィニッシュ';

  @override
  String get roadbookShare => '共有';

  @override
  String get roadbookNoMarkers => 'コースマーカーを追加してロードブックを作成しましょう。';

  @override
  String get roadbookAddElevation => '標高を追加';

  @override
  String get roadbookElevationUnavailable => 'このルートの標高データは利用できません';

  @override
  String roadbookSummary(String distance, String vert, String time) {
    return '$distance · 獲得 $vert · 目標 $time';
  }

  @override
  String get roadbookFuel => '補給';

  @override
  String get roadbookHeat => '暑さ';

  @override
  String get roadbookCarbs => '炭水化物';

  @override
  String get roadbookFluid => '水分';

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
    return '携行: ジェル $gels 個 · $fluid ml';
  }

  @override
  String get roadbookColTarget => '目標';

  @override
  String get roadbookColLegPace => '区間ペース';

  @override
  String get roadbookTargetAhead => '前倒し';

  @override
  String get roadbookTargetOn => '予定どおり';

  @override
  String get roadbookTargetBehind => '遅れ';

  @override
  String get checkpointCheckinAction => 'チェックポイント受付';

  @override
  String get checkpointCheckinTitle => 'エイドステーション受付';

  @override
  String get checkpointSyncNow => '今すぐ同期';

  @override
  String get checkpointPending => '未同期';

  @override
  String get checkpointLoadFailed => 'チェックポイントを読み込めませんでした';

  @override
  String get checkpointRetry => '再試行';

  @override
  String get checkpointNone =>
      'このレースにはまだチェックポイントがありません。クルーがランナーを受付する前に、ウェブで追加してください。';

  @override
  String get checkpointPickLabel => 'チェックポイント';

  @override
  String get checkpointBibLabel => 'ゼッケン番号';

  @override
  String get checkpointBibHint => 'ゼッケンをスキャンまたは入力';

  @override
  String get checkpointBibRequired => 'まずゼッケン番号を入力してください';

  @override
  String get checkpointStampIn => 'IN を記録';

  @override
  String get checkpointStampOut => 'OUT を記録';

  @override
  String checkpointStampedIn(String bib) {
    return 'ゼッケン $bib の入りを記録しました';
  }

  @override
  String checkpointStampedOut(String bib) {
    return 'ゼッケン $bib の出を記録しました';
  }

  @override
  String get checkpointStampFailed => '記録を保存できませんでした';

  @override
  String checkpointLoggedHere(int count) {
    return 'ここで記録済み ($count)';
  }

  @override
  String get checkpointNoneLoggedHere => 'このチェックポイントにはまだランナーの記録がありません。';

  @override
  String checkpointBibRow(String bib) {
    return 'ゼッケン $bib';
  }

  @override
  String checkpointInOut(String inTime, String outTime) {
    return '入 $inTime · 出 $outTime';
  }

  @override
  String get checkpointWeighInTitle => '体重測定';

  @override
  String get checkpointWeighInConsentBlurb =>
      '体重とメディカルホールドのメモは健康データであり、ランナーの同意がある場合にのみ記録され、レース運営者のみが閲覧できます。';

  @override
  String get checkpointWeighInConsent => 'ランナーは健康データの記録に同意します';

  @override
  String get checkpointWeighInBodyWeight => '体重';

  @override
  String get checkpointMedicalHold => 'メディカルホールドにする';

  @override
  String get checkpointWeighInSave => '保存して記録';

  @override
  String get checkpointCancel => 'キャンセル';

  @override
  String get challengesTitle => 'チャレンジ';

  @override
  String get challengesMyChallenges => '参加中のチャレンジ';

  @override
  String get challengesBrowse => 'さがす';

  @override
  String get challengesEmpty => 'まだチャレンジはありません。';

  @override
  String get challengesBrowseEmpty => '現在参加できる公開チャレンジはありません。';

  @override
  String get challengesJoin => '参加';

  @override
  String get challengesLeave => '退出';

  @override
  String get challengesDelete => '削除';

  @override
  String get challengesMetricDistance => '距離';

  @override
  String get challengesMetricDuration => '時間';

  @override
  String get challengesMetricVert => '獲得標高';

  @override
  String get challengesMetricActivityCount => 'アクティビティ数';

  @override
  String get challengesMetricStreak => '活動日数';

  @override
  String challengesGoalProgress(String value, String goal) {
    return '$goal 中 $value';
  }

  @override
  String get challengesProgressComplete => '達成';

  @override
  String get challengesPaceAhead => 'ペースを上回っています';

  @override
  String get challengesPaceOnTrack => '目標達成ペースです';

  @override
  String get challengesPaceBehind => 'ペースを下回っています';

  @override
  String challengesPaceNeedPerDay(String rate) {
    return '達成まで1日あたり$rate';
  }

  @override
  String challengesEndsIn(int n) {
    return 'あと $n 日で終了';
  }

  @override
  String get challengesEndsToday => '本日終了';

  @override
  String get challengesEnded => '終了済み';

  @override
  String get challengesLeaderboard => 'ランキング';

  @override
  String get challengesLeaderboardEmpty => 'まだ記録がありません。';

  @override
  String challengesLeaderboardRank(int rank) {
    return '#$rank';
  }

  @override
  String get challengesStandingTitle => 'あなたの順位';

  @override
  String get challengesStandingTitleTeam => 'チームの順位';

  @override
  String challengesStandingRank(int rank, int total) {
    return '$total中$rank位';
  }

  @override
  String get challengesStandingTiedOne => '同順位: 1';

  @override
  String challengesStandingTiedMany(int n) {
    return '同順位: $n';
  }

  @override
  String challengesStandingBehind(String gap, String name) {
    return '$name まで $gap';
  }

  @override
  String challengesStandingAhead(String gap, String name) {
    return '$name に $gap リード';
  }

  @override
  String get challengesStandingLeading => '首位';

  @override
  String challengesParticipants(int n) {
    return '$n 人参加';
  }

  @override
  String get challengesBadgeEarned => 'バッジ獲得';

  @override
  String challengesUnitDays(int n) {
    return '$n 日';
  }

  @override
  String challengesUnitActivities(int n) {
    return '$n';
  }

  @override
  String get challengesLeaveConfirmTitle => 'チャレンジから退出しますか？';

  @override
  String get challengesLeaveConfirm => 'このチャレンジでの進捗は記録されなくなります。';

  @override
  String get challengesDeleteConfirmTitle => 'チャレンジを削除しますか？';

  @override
  String get challengesDeleteConfirm => 'チャレンジとそのランキングが全員から削除されます。元に戻せません。';

  @override
  String get challengesNotFound => 'このチャレンジは利用できません。';

  @override
  String get challengesJoinFailed => 'チャレンジに参加できませんでした。';

  @override
  String get challengesLeaveFailed => 'チャレンジから退出できませんでした。';

  @override
  String get challengesDeleteFailed => 'チャレンジを削除できませんでした。';

  @override
  String get challengesLoadFailed => 'チャレンジを読み込めませんでした。';

  @override
  String get challengesProgressUnavailable => '進捗を表示できません。開いて結果を確認してください';

  @override
  String get challengesTeamNoClub => 'クラブなし';

  @override
  String get challengesTeamPrivateClub => '非公開クラブ';

  @override
  String fundraiserRaisedOfGoal(String raised, String goal) {
    return '目標 $goal のうち $raised を達成';
  }

  @override
  String fundraiserDonorCount(int count) {
    return '支援者 $count 人';
  }

  @override
  String get fundraiserOverGoal => '目標達成！';

  @override
  String get fundraiserClosed => 'この募金は終了しました。';

  @override
  String get fundraiserFeedTitle => '最近の支援者';

  @override
  String get fundraiserFeedEmpty => '最初の寄付者になりましょう。';

  @override
  String get fundraiserAnonymous => '匿名';

  @override
  String get fundraiserDonateOnWeb => 'ウェブで寄付する';

  @override
  String get racesTitle => 'レースカレンダー';

  @override
  String get racesSearchPlaceholder => 'レースを名前で検索…';

  @override
  String get racesNearPlace => '場所の近くで…';

  @override
  String racesDistanceAway(String distance) {
    return '$distance先';
  }

  @override
  String get racesDistanceAny => 'すべての距離';

  @override
  String get racesDistance5k => '5K';

  @override
  String get racesDistance10k => '10K';

  @override
  String get racesDistanceHalf => 'ハーフ';

  @override
  String get racesDistanceMarathon => 'マラソン';

  @override
  String get racesDistanceUltra => 'ウルトラ';

  @override
  String get racesRegister => '登録';

  @override
  String get racesTrainForThis => 'このレースに向けてトレーニング';

  @override
  String get racesViewResults => '結果を見る';

  @override
  String get racesImportResult => '自分の結果をインポート';

  @override
  String get racesSubmitRace => 'レースを追加';

  @override
  String get racesUnverified => '未確認';

  @override
  String get racesEmpty => 'このフィルターに一致するレースはまだありません。';

  @override
  String get racesSearchFailed => 'レースを読み込めませんでした。接続を確認して再試行してください。';

  @override
  String racesMatchPrompt(String name) {
    return 'これは$nameでしたか？公式結果をインポートします。';
  }

  @override
  String get racesMatchConfirm => '結果をインポート';

  @override
  String get racesMatchDismiss => 'このレースではない';

  @override
  String get racesImported => '公式結果をインポートしました。';

  @override
  String get racesOfficialResult => '公式結果';

  @override
  String get racesChipTime => 'ネットタイム';

  @override
  String get racesGunTime => 'グロスタイム';

  @override
  String get racesOverallPlace => '総合順位';

  @override
  String get racesAgeGroupPlace => '年代別順位';

  @override
  String get racesAgeGroup => '年代';

  @override
  String get racesBib => 'ゼッケン';

  @override
  String get racesRunSignUpBibHint =>
      '全体ではなくあなたの結果だけをインポートするため、ゼッケン番号を入力してください。';

  @override
  String get racesUltraSignUpAthleteId => 'UltraSignupアスリートID';

  @override
  String get racesUltraSignUpAthleteHint =>
      'UltraSignupのアスリートIDを入力してください。空欄のままにすると、このレースに登録されたIDを使います。';

  @override
  String get racesPasteResultHint => 'レースの結果ページから完走の詳細を入力してください。';

  @override
  String get racesSave => '保存';

  @override
  String get racesCancel => 'キャンセル';

  @override
  String get racesEditorTitle => 'レースを追加';

  @override
  String get racesFieldName => 'レース名';

  @override
  String get racesFieldDate => '日付';

  @override
  String get racesFieldDistance => '距離（メートル）';

  @override
  String get racesFieldLocation => '場所';

  @override
  String get racesFieldEntryUrl => '登録リンク';

  @override
  String get racesFieldResultsUrl => '結果リンク';

  @override
  String get racesSubmitFailed => 'レースを保存できませんでした。もう一度お試しください。';

  @override
  String get racesImportFailed => '結果をインポートできませんでした。もう一度お試しください。';

  @override
  String get navRaces => 'レース';

  @override
  String get integrationsRunsignup => 'RunSignUp';

  @override
  String get integrationsRunsignupConnect => 'RunSignUpからレース結果をインポートします。';

  @override
  String get integrationsRunsignupOpen => 'レースカレンダーを開く';

  @override
  String get integrationsRunsignupUnavailable =>
      'RunSignUpのインポートはまだ利用できません。parkrunと手動での貼り付けは引き続き利用できます。';

  @override
  String get integrationsUltrasignup => 'UltraSignup';

  @override
  String get integrationsUltrasignupConnect =>
      'UltraSignupからトレイル・ウルトラの結果をインポートします。';

  @override
  String get integrationsUltrasignupOpen => 'レースカレンダーを開く';

  @override
  String get integrationsUltrasignupUnavailable =>
      'UltraSignupのインポートはまだ利用できません。parkrunと手動での貼り付けは引き続き利用できます。';

  @override
  String get integrationsChronotrack => 'ChronoTrack';

  @override
  String get integrationsChronotrackConnect =>
      'ChronoTrackで計測されたイベントのレース結果をインポートします。';

  @override
  String get integrationsChronotrackOpen => 'レースカレンダーを開く';

  @override
  String get integrationsChronotrackUnavailable =>
      'ChronoTrackのインポートはまだ利用できません。parkrunと手動での貼り付けは引き続き利用できます。';

  @override
  String get routeConditionsTitle => 'コンディション';

  @override
  String get routeConditionsReport => 'コンディションを報告';

  @override
  String get routeConditionsReporting => '報告中…';

  @override
  String get routeConditionsReported => 'コンディションを報告しました';

  @override
  String get routeConditionsReportFailed => 'コンディションを報告できませんでした';

  @override
  String get routeConditionsEmpty => 'まだ報告はありません。';

  @override
  String get routeConditionsLoading => '読み込み中…';

  @override
  String get routeConditionsCancel => 'キャンセル';

  @override
  String get routeConditionsDelete => '削除';

  @override
  String get routeConditionsDeleteFailed => '報告を削除できませんでした';

  @override
  String get routeConditionsKindLabel => '状態';

  @override
  String get routeConditionsSeverityLabel => '深刻度';

  @override
  String get routeConditionsNoteLabel => 'メモ';

  @override
  String get routeConditionsNotePlaceholder => '次のランナーは何に遭遇しますか？';

  @override
  String routeConditionsAtDistance(String distance) {
    return '$distance 地点';
  }

  @override
  String get routeConditionMuddy => '泥';

  @override
  String get routeConditionFlooded => '冠水';

  @override
  String get routeConditionSnowIce => '雪・氷';

  @override
  String get routeConditionOvergrown => '草木が繁茂';

  @override
  String get routeConditionClosed => '閉鎖';

  @override
  String get routeConditionHazard => '危険';

  @override
  String get routeConditionClear => '良好';

  @override
  String get routeConditionOther => 'その他';

  @override
  String get routeConditionSeverityInfo => '情報';

  @override
  String get routeConditionSeverityCaution => '注意';

  @override
  String get routeConditionSeverityImpassable => '通行不能';

  @override
  String get prefTurnByTurnCues => 'ターンバイターン音声ガイド';

  @override
  String get prefTurnByTurnCuesSubtitle => '保存したルートを辿る際に曲がる方向を音声で案内';

  @override
  String ttsTurnLeftIn(String distance) {
    return '$distance先、左折します';
  }

  @override
  String ttsTurnRightIn(String distance) {
    return '$distance先、右折します';
  }

  @override
  String get ttsTurnLeftNow => '左折します';

  @override
  String get ttsTurnRightNow => '右折します';

  @override
  String get ttsSlightLeft => 'やや左へ';

  @override
  String get ttsSlightRight => 'やや右へ';

  @override
  String get ttsUturn => 'Uターンします';

  @override
  String routeOfflinePackDownloading(int done, int total) {
    return '地図をキャッシュ中: $done / $total';
  }

  @override
  String get routeOfflinePackReady => '地図をオフライン保存しました';

  @override
  String routeOfflinePackPartial(int done, int total) {
    return '地図を一部保存 ($done / $total) — 再試行';
  }

  @override
  String get routeOfflinePackTooLarge => 'このルートはオフライン保存には大きすぎます';

  @override
  String get badgesSectionTitle => '実績';

  @override
  String get badgesSectionSubtitle => '達成したマイルストーン';

  @override
  String get badgesEmpty => 'まだバッジがありません。走り続けましょう。';

  @override
  String get badgesEmptyOther => '公開バッジはまだありません。';

  @override
  String badgesEarnedOn(String date) {
    return '$dateに獲得';
  }

  @override
  String badgesFeedEarned(String name, String badge) {
    return '$nameさんが$badgeバッジを獲得しました';
  }

  @override
  String get badgesARunner => 'ランナー';

  @override
  String get badgesTierBronze => 'ブロンズ';

  @override
  String get badgesTierSilver => 'シルバー';

  @override
  String get badgesTierGold => 'ゴールド';

  @override
  String get badgesTierPlatinum => 'プラチナ';

  @override
  String get badgesDistanceSingle5kLabel => '初めての5K';

  @override
  String get badgesDistanceSingle5kDesc => '1回のランで5km走破';

  @override
  String get badgesDistanceSingleHalfLabel => 'ハーフマラソン';

  @override
  String get badgesDistanceSingleHalfDesc => '1回のランで21.1km走破';

  @override
  String get badgesDistanceSingleMarathonLabel => 'マラソン';

  @override
  String get badgesDistanceSingleMarathonDesc => '1回のランで42.2km走破';

  @override
  String get badgesDistanceSingleUltraLabel => 'ウルトラ';

  @override
  String get badgesDistanceSingleUltraDesc => '1回のランで50km以上走破';

  @override
  String get badgesDistanceLifetime100Label => '100kmクラブ';

  @override
  String get badgesDistanceLifetime100Desc => '通算100kmを記録';

  @override
  String get badgesDistanceLifetime500Label => '500km';

  @override
  String get badgesDistanceLifetime500Desc => '通算500kmを記録';

  @override
  String get badgesDistanceLifetime1000Label => '1,000kmクラブ';

  @override
  String get badgesDistanceLifetime1000Desc => '通算1,000kmを記録';

  @override
  String get badgesDistanceLifetime5000Label => '5,000km';

  @override
  String get badgesDistanceLifetime5000Desc => '通算5,000kmを記録';

  @override
  String get badgesStreak7Label => '週間連続';

  @override
  String get badgesStreak7Desc => '7日連続で走破';

  @override
  String get badgesStreak30Label => '月間連続';

  @override
  String get badgesStreak30Desc => '30日連続で走破';

  @override
  String get badgesStreak100Label => '100日連続';

  @override
  String get badgesStreak100Desc => '100日連続で走破';

  @override
  String get badgesStreak365Label => '年間連続';

  @override
  String get badgesStreak365Desc => '365日連続で走破';

  @override
  String get badgesPr1Label => '初の自己ベスト';

  @override
  String get badgesPr1Desc => '初めての自己ベストを記録';

  @override
  String get badgesPr3Label => 'トリプル自己ベスト';

  @override
  String get badgesPr3Desc => '3つの距離で自己ベストを保持';

  @override
  String get badgesPr5Label => '記録コレクター';

  @override
  String get badgesPr5Desc => 'すべての距離で自己ベストを保持';

  @override
  String get badgesPlan1Label => 'プラン完走';

  @override
  String get badgesPlan1Desc => 'トレーニングプランを完了';

  @override
  String get badgesPlan3Label => 'トリプル完走';

  @override
  String get badgesPlan3Desc => '3つのトレーニングプランを完了';

  @override
  String get badgesPlan10Label => 'プランの達人';

  @override
  String get badgesPlan10Desc => '10のトレーニングプランを完了';

  @override
  String get racePredictorTitle => 'レースタイム予測';

  @override
  String racePredictorAnchoredOn(String distance, String time) {
    return '$timeでの$distanceの走りに基づく';
  }

  @override
  String get racePredictorColDistance => '距離';

  @override
  String get racePredictorColTime => 'タイム';

  @override
  String get racePredictorColPace => 'ペース';

  @override
  String get racePredictorColConfidence => '信頼度';

  @override
  String get racePredictorConfidenceHigh => '高';

  @override
  String get racePredictorConfidenceModerate => '中';

  @override
  String get racePredictorConfidenceLow => '低';

  @override
  String get racePredictorConfReasonSimilar => 'この距離に近い最近の走りに基づいています。';

  @override
  String get racePredictorConfReasonExtrapolated =>
      '大きな距離差で外挿しています。おおよその目安としてください。';

  @override
  String get racePredictorConfReasonStale => '数週間前の走りを基準にしています。';

  @override
  String get racePredictorConfReasonLimited => '最近のデータが限られています。';

  @override
  String get racePredictorFootnote =>
      '最近のベストな走りからリーゲルの換算式で算出し、新しさで重み付けしています。近い距離ほど信頼できます。';

  @override
  String get settingsSectionDeveloper => '開発者';

  @override
  String get settingsTabSimWatchSubtitle => 'シミュレーション中のカスタムウォッチのライブ状態';

  @override
  String get simWatchTitle => 'シミュレータウォッチ接続';

  @override
  String get simWatchHostLabel => 'ホスト';

  @override
  String get simWatchPortLabel => 'ポート';

  @override
  String get simWatchConnect => '接続';

  @override
  String get simWatchConnecting => '接続中…';

  @override
  String get simWatchDisconnect => '切断';

  @override
  String simWatchConnectionFailed(String error) {
    return '接続に失敗しました: $error';
  }

  @override
  String get simWatchSyncAction => '時計からランを同期';

  @override
  String simWatchSyncing(int done, int total) {
    return '同期中… $done/$total';
  }

  @override
  String simWatchResult(int synced, int total) {
    return '時計から $total 件中 $synced 件のランを同期しました';
  }

  @override
  String simWatchSyncFailed(String error) {
    return '時計の同期に失敗しました: $error';
  }

  @override
  String get simWatchPushSettingsAction => '設定を時計に送信';

  @override
  String get simWatchSettingsPushed => '設定を時計に送信しました';

  @override
  String simWatchPushSettingsFailed(String error) {
    return '設定の送信に失敗しました: $error';
  }

  @override
  String get simWatchPushWorkoutAction => 'ワークアウトを時計に送信';

  @override
  String simWatchWorkoutPushed(int steps) {
    return 'ワークアウトを時計に送信しました（$stepsステップ）';
  }

  @override
  String simWatchPushWorkoutFailed(String error) {
    return 'ワークアウトの送信に失敗しました: $error';
  }

  @override
  String get simWatchPushRoadbookAction => 'レーススケジュールをウォッチに送信';

  @override
  String simWatchRoadbookPushed(int checkpoints, int cutoffs) {
    return 'レーススケジュールをウォッチに送信しました（$checkpoints チェックポイント、$cutoffs 関門）';
  }

  @override
  String simWatchPushRoadbookFailed(String error) {
    return 'レーススケジュールの送信に失敗しました: $error';
  }

  @override
  String get simWatchPushCourseAction => 'コースを時計に送信';

  @override
  String simWatchCoursePushed(int points) {
    return 'コースを時計に送信しました（$pointsポイント）';
  }

  @override
  String simWatchPushCourseFailed(String error) {
    return 'コースの送信に失敗しました: $error';
  }

  @override
  String get simWatchNoRuns => '同期する時計のランがありません';

  @override
  String get simWatchWaitingFrames => '接続済み — フレーム待機中…';

  @override
  String get simWatchUptime => '稼働時間';

  @override
  String get simWatchNoFix => 'GPS未測位';

  @override
  String get simWatchPosition => '位置';

  @override
  String get simWatchSpeed => '速度';

  @override
  String get simWatchSatellites => '衛星数';

  @override
  String get simWatchAltitude => '高度';

  @override
  String get simWatchBaroAltitude => '気圧高度';

  @override
  String get simWatchAscent => '上昇';

  @override
  String get simWatchDescent => '下降';

  @override
  String get simWatchFixAge => '測位からの経過';

  @override
  String simWatchSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get sessionLoadError => 'セッションを読み込めませんでした。';

  @override
  String get sessionDetailLoadError => 'このセッションプランを読み込めませんでした。';

  @override
  String get gymEditorRemoveExerciseTitle => 'エクササイズを削除しますか？';

  @override
  String get gymEditorRemoveExerciseBody =>
      'このエクササイズとすべてのセットがこのワークアウトから削除されます。';

  @override
  String get gymEditorRemoveExerciseConfirm => '削除';

  @override
  String get eventSubmitRunsLoadError => '最近のランを読み込めませんでした。';

  @override
  String get racesCouldNotOpenLink => 'リンクを開けませんでした。';

  @override
  String get prefsHrZonesClearTitle => '心拍ゾーンをクリアしますか？';

  @override
  String get prefsHrZonesClearBody => 'カスタム5ゾーンがクリアされます。';

  @override
  String get prefsHrZonesClearConfirm => 'クリア';

  @override
  String get signInRequiredMessage => 'この機能を使うにはサインインしてください';

  @override
  String get signInRequiredAction => 'サインイン';

  @override
  String get backendUnavailableMessage => '現在サーバーに接続できません。オンライン機能は利用できません';

  @override
  String get feedSignedOutMessage => 'フォローしている人のランを見るにはサインインしてください';

  @override
  String ttsPaceAlertSpeedUpByKm(int sec) {
    return '1キロメートルあたり$sec秒ペースを上げてください';
  }

  @override
  String ttsPaceAlertSpeedUpByMi(int sec) {
    return '1マイルあたり$sec秒ペースを上げてください';
  }

  @override
  String ttsPaceAlertSlowDownByKm(int sec) {
    return '1キロメートルあたり$sec秒ペースを落としてください';
  }

  @override
  String ttsPaceAlertSlowDownByMi(int sec) {
    return '1マイルあたり$sec秒ペースを落としてください';
  }

  @override
  String ttsCutoffCatchUp(String distance, String pace) {
    return '次の関門まで$distance。間に合うには$paceが必要です。';
  }

  @override
  String get ttsCutoffUnreachable => '次の関門: 制限時間を過ぎました。';

  @override
  String ttsMarkerAheadOfPlan(String label, String time) {
    return '$label: 予定より$time早いです';
  }

  @override
  String ttsMarkerBehindPlan(String label, String time) {
    return '$label: 予定より$time遅れています';
  }

  @override
  String ttsMarkerOnPlan(String label) {
    return '$label: 予定どおりです';
  }

  @override
  String ttsPhaseStart(int index, int total, String phrase) {
    return 'フェーズ$index、全$total。$phrase';
  }

  @override
  String get ttsPhaseHoldBack => '抑えて。コントロールを保って。';

  @override
  String get ttsPhaseSettle => '目標ペースに落ち着いて。';

  @override
  String get ttsPhaseRace => 'ここから勝負。残りの力を出し切って。';

  @override
  String get ttsPhaseEven => '一定のペースを保って。';

  @override
  String ttsPhaseTargetPace(String pace) {
    return '目標は$paceです。';
  }

  @override
  String get prefsVoiceCueTypesLabel => '音声アナウンス';

  @override
  String get prefsCueSplits => 'スプリット';

  @override
  String get prefsCueSplitsSubtitle => 'スプリットマーカーを通過するたびのペース（または速度）';

  @override
  String get prefsCueSplitsInfo =>
      'スプリットを終えるたびに短いまとめを読み上げます（距離はスプリット間隔で設定）。スプリットの読み上げで、スプリットのペース・平均ペース・両方から選べます。例：「1キロメートル。ペース、1キロメートルあたり5分30秒。」';

  @override
  String get prefsCueStartFinish => '開始と終了';

  @override
  String get prefsCueStartFinishSubtitle => '開始時に「ランを開始しました」、終了時にまとめを読み上げ';

  @override
  String get prefsCueStartFinishInfo =>
      'ランの開始を知らせ、停止時に距離と時間を読み上げます。例：「ラン完了。52分で10.0キロメートル。」';

  @override
  String get prefsCueOffRoute => 'ルート逸脱';

  @override
  String get prefsCueOffRouteSubtitle => '追跡中のルートから外れたときの注意喚起';

  @override
  String get prefsCueOffRouteInfo =>
      '保存したルートでランを始めたときだけ機能します。ルートから外れると知らせ、コースに戻れるようにします。例：「ルートを外れています。」';

  @override
  String get prefsCuePaceAlerts => 'ペースずれアラート';

  @override
  String get prefsCuePaceAlertsSubtitle => '目標ペースからずれたら「ペースを上げて」「落として」';

  @override
  String get prefsCuePaceAlertsInfo =>
      '目標ペースの設定が必要です。約30秒以上ずれると、どちらへどれだけ調整するかを知らせます。例：「8秒ペースを上げてください。」';

  @override
  String get prefsCueWorkoutSteps => 'ワークアウトステップ';

  @override
  String get prefsCueWorkoutStepsSubtitle => '構造化ワークアウトの各ステップを開始時に読み上げ';

  @override
  String get prefsCueWorkoutStepsInfo =>
      '構造化ワークアウト（プランのセッションやインターバル）の間だけ有効です。各ステップと目標を読み上げ、前を見て走れます。例：「5本中3本目。1キロメートルあたり4分30秒で400メートル。」';

  @override
  String get prefsCueCutoffCatchUp => '関門ペース';

  @override
  String get prefsCueCutoffCatchUpSubtitle => '間に合わなくなりそうな関門に必要なペース';

  @override
  String get prefsCueCutoffCatchUpInfo =>
      'コース関門のあるルートでだけ有効です。危ない関門があると、そこまでの距離と間に合うペースを読み上げます。例：「関門まで2キロメートル。1キロメートルあたり6分。」';

  @override
  String get prefsCueMarkerTargets => 'コースマーカー';

  @override
  String get prefsCueMarkerTargetsSubtitle => '各コースマーカーで予定より前か後かを知らせます';

  @override
  String get prefsCueMarkerTargetsInfo =>
      'コースマーカーに目標時間があるルートでだけ有効です。各マーカーを通過するたびに、予定より前か後か、どれだけかを知らせます。例：「エイド2：予定より45秒前。」';

  @override
  String get prefsCuePhaseTransitions => 'レースフェーズ';

  @override
  String get prefsCuePhaseTransitionsSubtitle => 'レース戦略プランの各フェーズが始まるときの合図';

  @override
  String get prefsCuePhaseTransitionsInfo =>
      'ランでレース戦略を選んだときだけ有効です。各フェーズとその狙いを開始時に読み上げます。例：「3フェーズ中2フェーズ目。目標ペースに落ち着いて。」';

  @override
  String get prefsCueGuidedRun => 'ガイド付きラン';

  @override
  String get prefsCueGuidedRunSubtitle => '開始前に選んだガイド付きランのコーチ音声スクリプト';

  @override
  String get prefsCueGuidedRunInfo =>
      'ランタブで開始前にガイド付きランを選んだときだけ有効です。各マークに達するとスクリプトのコーチの声を読み上げます。例：「5分経過。一日中維持できるリズムに落ち着いて。」';

  @override
  String get runGuidedRun => 'ガイド付きラン';

  @override
  String get runGuidedRunNone => 'ガイド付きランなし';

  @override
  String runGuidedRunOption(int minutes, String subtitle) {
    return '$minutes分 · $subtitle';
  }

  @override
  String get runRaceStrategy => 'レース戦略';

  @override
  String get runStrategyNone => '戦略なし';

  @override
  String get runStrategyTenTenTen => '10-10-10';

  @override
  String get runStrategyNegativeSplit => 'ネガティブスプリット';

  @override
  String get runStrategyEven => 'イーブンペース';

  @override
  String get runStrategyTenTenTenHint => '序盤は抑え、中盤は安定、終盤は勝負';

  @override
  String get runStrategyNegativeSplitHint => '前半は抑えて後半は速く';

  @override
  String get runStrategyEvenHint => '最初から最後まで一定ペース';

  @override
  String get runStrategyGoalTime => '目標タイム';

  @override
  String get runStrategyDistance => '距離';

  @override
  String get runStrategyNeedsDistance => 'フェーズを使うにはルートを選ぶか距離を入力してください';

  @override
  String get runStrategyInvalidGoal => '目標タイムを h:mm:ss 形式で入力してください';

  @override
  String runPhaseChip(int index, int total, String intent) {
    return 'フェーズ $index/$total — $intent';
  }

  @override
  String get phaseIntentHoldBack => '抑える';

  @override
  String get phaseIntentSettle => '安定';

  @override
  String get phaseIntentRace => '勝負';

  @override
  String get phaseIntentEven => 'イーブン';

  @override
  String routeMarkerTargetChip(String time) {
    return '目標 $time';
  }

  @override
  String get routeMarkerTargetLabel => '目標タイム';

  @override
  String get routeMarkerTargetHelper => '時 : 分 : 秒';

  @override
  String get routeMarkerTargetInvalid => '目標タイムは h:mm:ss 形式で入力してください';

  @override
  String get routeMarkerOfficialBadge => 'ルート所有者';

  @override
  String get routeMarkerDistanceAlongLabel => 'ルート上の距離';

  @override
  String get routeMarkerDistanceInvalid => 'ルート上の有効な距離を入力してください。';

  @override
  String get watchScreensTitle => 'ウォッチ画面';

  @override
  String get watchScreensAction => 'ウォッチ画面を作成';

  @override
  String watchScreensCount(int count, int max) {
    return '$max 画面中 $count 画面';
  }

  @override
  String get watchScreensEmptyTitle => '作成した画面はありません';

  @override
  String get watchScreensEmptyBody =>
      '画面を作成するまで、ウォッチは内蔵ページのみを表示します。画面を追加して表示内容を選びましょう。';

  @override
  String get watchScreensAdd => '画面を追加';

  @override
  String watchScreensFull(int max) {
    return 'ウォッチには最大 $max 画面まで登録できます。';
  }

  @override
  String watchScreensHeading(int index) {
    return '画面 $index';
  }

  @override
  String get watchScreensLayout => 'レイアウト';

  @override
  String watchScreensSlot(int index) {
    return 'スロット $index';
  }

  @override
  String get watchScreensMoveUp => '上へ移動';

  @override
  String get watchScreensMoveDown => '下へ移動';

  @override
  String get watchScreensRemove => '画面を削除';

  @override
  String watchScreensRemoveTitle(int index) {
    return '画面 $index を削除しますか？';
  }

  @override
  String watchScreensRemoveBody(int count) {
    return 'この画面の $count 個の項目も削除されます。';
  }

  @override
  String get watchScreensRemoveConfirm => '削除';

  @override
  String get watchScreensCancel => 'キャンセル';

  @override
  String watchScreensShrinkTitle(int count) {
    return '$count 個の項目を削除しますか？';
  }

  @override
  String watchScreensShrinkBody(String layout, int slots, String dropped) {
    return '$layout レイアウトのスロットは $slots 個なので、$dropped は表示されなくなります。';
  }

  @override
  String get watchScreensShrinkConfirm => 'レイアウトを変更';

  @override
  String get watchScreensPushAction => '画面をウォッチに送信';

  @override
  String watchScreensPushed(int count) {
    return '$count 個の画面をウォッチに送信しました';
  }

  @override
  String get watchScreensCleared => 'ウォッチの作成済み画面を消去しました';

  @override
  String watchScreensPushFailed(String error) {
    return '画面の送信に失敗しました: $error';
  }

  @override
  String get watchScreensLoadFailed => '保存された画面を読み込めませんでした。';

  @override
  String get watchScreensStartOver => '最初からやり直す';

  @override
  String get watchLayoutSingle => 'シングル';

  @override
  String get watchLayoutDuo => 'デュオ';

  @override
  String get watchLayoutTrio => 'トリオ';

  @override
  String get watchMetricElapsed => '経過時間';

  @override
  String get watchMetricDistance => '距離';

  @override
  String get watchMetricAvgPace => '平均ペース';

  @override
  String get watchMetricLapElapsed => 'ラップタイム';

  @override
  String get watchMetricHeartRate => '心拍数';

  @override
  String get watchMetricPacerDelta => 'ペーサーとの差';

  @override
  String get watchMetricGuidedRunRemaining => 'ガイドランの案内';

  @override
  String get watchMetricWorkoutRemaining => 'ワークアウトのステップ';

  @override
  String get watchMetricRacePrediction => 'レース予測タイム';

  @override
  String get watchMetricCutoffMargin => '関門までの余裕';

  @override
  String get watchMetricTrainingStress => 'トレーニング負荷';

  @override
  String get watchMetricRoadbookNext => '次のエイド';

  @override
  String get watchMetricFuelCarbs => '補給の炭水化物';

  @override
  String get watchMetricGearWear => 'ギアの消耗';

  @override
  String get watchMetricEasyPace => 'イージーペース';

  @override
  String get watchMetricVo2Max => 'VO2 Max';

  @override
  String get watchMetricAltitude => '標高';

  @override
  String get watchMetricDistanceToStart => 'スタートまでの距離';

  @override
  String get watchMetricDaylightCountdown => '日没までの時間';

  @override
  String get watchMetricWaypointDistance => 'ウェイポイントまでの距離';

  @override
  String get watchMetricClimbGain => '登りの獲得標高';

  @override
  String get watchMetricRecapDistance => '年間距離';

  @override
  String get watchMetricCurrentStreak => '連続記録';

  @override
  String get watchMetricSyncedMovingTime => '動作時間';

  @override
  String get watchMetricPrAge => '自己ベストの経過';

  @override
  String get watchMetricPlanReplanChanges => '再計画の変更数';

  @override
  String get watchMetricPlanAdaptiveChanges => '適応調整の変更数';

  @override
  String get watchMetricReadinessScore => 'コンディション';

  @override
  String get watchMetricGoalPercent => '目標の達成率';

  @override
  String get watchMetricTurnCueDistance => '次の曲がり角';

  @override
  String get watchMetricRouteSimplifyDistance => 'コース距離';

  @override
  String get watchMetricAutoEffortMatched => '一致したセグメント';

  @override
  String get watchMetricRouteElevTotal => 'コースの獲得標高';

  @override
  String get watchMetricRaceDayDays => 'レースまでの日数';

  @override
  String get watchMetricSleepBudget => '睡眠可能時間';

  @override
  String get watchMetricTimerRemaining => 'タイマー';

  @override
  String get watchMetricBackyardBell => 'ベルまでの残り時間';

  @override
  String get watchMetricStormDelta => '気圧低下傾向';

  @override
  String get watchMetricGap => '勾配調整ペース';

  @override
  String get watchMetricFluid => '水分';

  @override
  String get watchLiveTitle => 'ウォッチのランを共有';

  @override
  String get watchLiveTileSubtitle => '自作ウォッチの位置をライブリンクに中継します';

  @override
  String get watchLiveIntro =>
      'この画面を開いている間、スマートフォンはウォッチの位置を約1秒ごとに観戦者へ中継します。スマートフォンを身につけ、Bluetooth の通信圏内に保ってください。この画面を離れると中継は終了します。';

  @override
  String get watchLiveStateOff => '未接続';

  @override
  String get watchLiveStateConnecting => '接続中';

  @override
  String get watchLiveStateLive => 'ライブ';

  @override
  String get watchLiveStateGap => '中断';

  @override
  String get watchLiveStateLost => '接続を断念';

  @override
  String get watchLiveDetailOff => '何も送信していません。';

  @override
  String get watchLiveDetailSearching => 'ウォッチを探しています…';

  @override
  String get watchLiveDetailAwaitingFix => '接続済み — ウォッチの最初の位置を待っています。';

  @override
  String get watchLiveDetailGap => '観戦者には最後の位置が現在地ではなく遅延として表示されます';

  @override
  String get watchLiveDetailLost => 'ウォッチの電源が切れているか、通信圏外です。新しい位置は送信されていません。';

  @override
  String get watchLiveStart => '中継を開始';

  @override
  String get watchLiveStop => '中継を停止';

  @override
  String get watchLiveRetry => '再試行';

  @override
  String get watchLiveShare => 'ライブリンクを共有';

  @override
  String get watchLiveStartFailed => 'ライブ配信を開始できませんでした — 何も共有されていません。';

  @override
  String get watchLiveSyncAction => 'ウォッチのランを同期';

  @override
  String get watchLiveSyncSubtitle => 'ウォッチに記録されたランを取り込みます。その間、中継は一時停止します。';

  @override
  String pendingSyncOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の変更をこの端末に保存しました — オンラインになったら同期します',
    );
    return '$_temp0';
  }

  @override
  String pendingSyncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の変更が同期されていません',
    );
    return '$_temp0';
  }

  @override
  String get pendingSyncRetry => '再試行';

  @override
  String get photoOpen => '写真を開く';

  @override
  String get photoLightboxClose => '写真を閉じる';

  @override
  String get photoLightboxLoading => '写真を読み込んでいます…';

  @override
  String get photoLightboxError => 'この写真を読み込めませんでした。';

  @override
  String get photoLightboxErrorHint => '画面のどこかをタップすると閉じます。';

  @override
  String get commonLoading => '読み込み中…';

  @override
  String get commonMore => 'その他';

  @override
  String get undoAction => '元に戻す';

  @override
  String get undoDismiss => '閉じる';

  @override
  String get undoHint => 'しばらくの間、元に戻せます。';

  @override
  String get undoRestored => '元に戻しました';

  @override
  String get prefsUndoWindow => '元に戻せる時間';

  @override
  String get prefsUndoWindow8s => '8秒';

  @override
  String get prefsUndoWindow30s => '30秒';

  @override
  String get prefsUndoWindowManual => '自分で閉じるまで';

  @override
  String undoDismissed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '通知$count件を消しました',
    );
    return '$_temp0';
  }

  @override
  String get routeConditionsRemoved => 'コンディション報告を削除しました';

  @override
  String get gearWearLogRemoved => '記録を削除しました';

  @override
  String nutritionEntryRemoved(String item) {
    return '$itemを削除しました';
  }

  @override
  String get runSocialCommentRemoved => 'コメントを削除しました';

  @override
  String get routeDetailReviewRemoved => 'レビューを削除しました';

  @override
  String get routeMarkerRemoved => 'マーカーを削除しました';

  @override
  String get roadbookNeedsRouteLine => 'ロードブックを作成するには、このルートに 2 点以上を追加してください。';

  @override
  String get settingsGearUnavailable => 'このビルドではギアを利用できません';

  @override
  String get loadRampTitle => 'トレーニング負荷の伸び';

  @override
  String get loadRampRatioCaption => '今週 vs 過去4週間の平均';

  @override
  String get loadRampAcuteLabel => '直近7日間';

  @override
  String get loadRampChronicLabel => '4週間の週平均';

  @override
  String get loadRampBandLow => '低い';

  @override
  String get loadRampBandOptimal => '最適';

  @override
  String get loadRampBandElevated => 'やや高い';

  @override
  String get loadRampBandHigh => '高い';

  @override
  String get loadRampMeaningLow =>
      '直近のベースを下回っています。テーパリングや回復週なら問題ありませんが、続くと走力が落ちます。';

  @override
  String get loadRampMeaningOptimal =>
      '今週は故障を最も防ぎやすい範囲にあります。このペースで積み上げていきましょう。';

  @override
  String get loadRampMeaningElevated =>
      '直近のベースが支えられる以上に増やしています。今週はこれ以上増やさず維持しましょう。';

  @override
  String get loadRampMeaningHigh =>
      '直近のベースからの急激な増加です。故障と最も関連が深いパターンなので、軽めの週を検討してください。';

  @override
  String get loadRampTrendRamping => '負荷は増加傾向です。';

  @override
  String get loadRampTrendSteady => '負荷は横ばいです。';

  @override
  String get loadRampTrendTapering => '負荷は減少傾向です。';

  @override
  String get comebackTitle => 'ブランクからの復帰';

  @override
  String get comebackVerdictEasingIn => '順調な立ち上げ';

  @override
  String get comebackVerdictSteep => '初週の負荷が大きい';

  @override
  String comebackLayoff(int weeks) {
    return '$weeks週間ランなし';
  }

  @override
  String get comebackShareCaption => '今週とブランク前の平均週との比較';

  @override
  String get comebackMeaningEasingIn =>
      '今週はブランク前に走っていた週を十分に下回っています。ここから少しずつ積み上げることが、復帰を定着させます。';

  @override
  String get comebackMeaningSteep =>
      '今週はすでにブランク前に走っていた量の半分を超えています。あの頃の走りを支えていた土台は失われているため、今週を短くするほうが、後で故障するよりはるかに安く済みます。';

  @override
  String get comebackThisWeekLabel => '直近7日間';

  @override
  String get comebackBaseLabel => 'ブランク前の週平均';

  @override
  String get comebackFootnote => '安定した週が数週間そろえば、トレーニング負荷の推移が再び表示されます。';

  @override
  String get segmentCatalogueTitle => '有名なセグメント';

  @override
  String get segmentCatalogueIntro =>
      '世界中から選んだ坂、橋、公園の周回コース。走るだけで、あなたのタイムが自動でランキングに登録されます。';

  @override
  String get segmentCatalogueSearchLabel => '検索';

  @override
  String get segmentCatalogueSearchHint => '名前または場所';

  @override
  String get segmentCatalogueRegion => '地域';

  @override
  String get segmentCatalogueAllRegions => 'すべての地域';

  @override
  String get segmentCatalogueSurface => '路面';

  @override
  String get segmentCatalogueAllSurfaces => 'すべての路面';

  @override
  String get segmentCatalogueSort => '並べ替え';

  @override
  String get segmentCatalogueSortName => '名前';

  @override
  String get segmentCatalogueSortShortest => '短い順';

  @override
  String get segmentCatalogueSortLongest => '長い順';

  @override
  String get segmentCatalogueSortClimb => '獲得標高が多い順';

  @override
  String segmentCatalogueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のセグメント',
    );
    return '$_temp0';
  }

  @override
  String get segmentCatalogueLoadFailed => 'セグメントカタログを読み込めませんでした。';

  @override
  String get segmentCatalogueEmpty => 'カタログにはまだ有名なセグメントがありません。';

  @override
  String get segmentCatalogueNoMatches =>
      'これらのフィルターに一致するセグメントはありません。条件を広げてみてください。';

  @override
  String get segmentCatalogueBrowseAll => 'すべて見る';

  @override
  String get segmentCatalogueNotFoundTitle => 'セグメントが見つかりません';

  @override
  String get segmentCatalogueNotFoundBody => 'このセグメントはカタログにないか、削除されています。';

  @override
  String get segmentCatalogueDetailFailedTitle => 'このセグメントを読み込めませんでした';

  @override
  String get segmentCatalogueDetailFailedBody => '接続を確認してもう一度お試しください。';

  @override
  String get segmentCatalogueStatDistance => '距離';

  @override
  String get segmentCatalogueStatElevation => '獲得標高';

  @override
  String get segmentCatalogueStatSurface => '路面';

  @override
  String get segmentCatalogueLeaderboard => 'ランキング';

  @override
  String get runSurfaceTabSegments => 'セグメント';

  @override
  String rateLimitCreateClub(String wait) {
    return 'クラブの作成が速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitCreateRoute(String wait) {
    return 'ルートの作成が速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitCreateReport(String wait) {
    return '報告の送信が速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitCreateChallenge(String wait) {
    return 'チャレンジの作成が速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitAdoptPlan(String wait) {
    return 'プランの取り込みが速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitAdoptSessionPlan(String wait) {
    return 'セッションプランの取り込みが速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitAdoptGymRoutine(String wait) {
    return 'ジムルーティンの取り込みが速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitPublishRoutine(String wait) {
    return 'ルーティンの公開が速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitSendMessage(String wait) {
    return 'メッセージの送信が速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitGeneric(String wait) {
    return '操作が速すぎます。$wait待ってから、もう一度お試しください。';
  }

  @override
  String rateLimitWaitSeconds(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n秒');
    return '$_temp0';
  }

  @override
  String rateLimitWaitMinutes(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n分');
    return '$_temp0';
  }

  @override
  String get rateLimitWaitSoon => '少し';

  @override
  String get challengesCreate => 'チャレンジを作成';

  @override
  String get challengesTitleLabel => 'タイトル';

  @override
  String get challengesDescriptionLabel => '説明';

  @override
  String get challengesMetricLabel => '指標';

  @override
  String get challengesScopeLabel => '種類';

  @override
  String get challengesGoalOptional => '目標（任意）';

  @override
  String get challengesActivityTypeLabel => 'アクティビティ';

  @override
  String get challengesActivityAny => 'すべて';

  @override
  String get challengesClubLabel => 'クラブ';

  @override
  String get challengesClubNone => '公開（誰でも）';

  @override
  String get challengesStartLabel => '開始';

  @override
  String get challengesEndLabel => '終了';

  @override
  String get challengesScopeIndividual => '個人';

  @override
  String get challengesScopeClubVsClub => 'クラブ対抗';

  @override
  String get challengesScopeGroupGoal => 'グループ目標';

  @override
  String get challengesSuffixHours => '時間';

  @override
  String get challengesSuffixActivities => '件';

  @override
  String get challengesSuffixDays => '日';

  @override
  String challengesGoalPreview(String value) {
    return '参加者には $value と表示されます';
  }

  @override
  String challengesGoalStreakCeiling(int n) {
    return 'この期間に収まるアクティブな日数は最大 $n 日です。';
  }

  @override
  String get challengesErrTitle => 'チャレンジにタイトルを付けてください。';

  @override
  String get challengesErrGoal => '目標：正の数を入力してください';

  @override
  String get challengesErrWindow => '終了は開始より後にしてください。';

  @override
  String limitsWeightOutOfRange(String min, String max, String unit) {
    return '$min〜$max$unitの範囲で体重を入力してください。';
  }

  @override
  String limitsHeightOutOfRange(String min, String max) {
    return '$min〜${max}cmの範囲で身長を入力してください。';
  }

  @override
  String limitsServingsOutOfRange(String min, String max) {
    return '$min〜$maxの範囲で分量を入力してください。';
  }

  @override
  String runDetailGuidedRun(String title) {
    return 'ガイド付きラン: $title';
  }

  @override
  String get runDetailGuidedRunUnavailable => 'このガイド付きランはライブラリにありません';

  @override
  String get guidedRunUseThisRun => 'このランを使う';
}
