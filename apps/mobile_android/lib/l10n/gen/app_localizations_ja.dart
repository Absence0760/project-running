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
}
