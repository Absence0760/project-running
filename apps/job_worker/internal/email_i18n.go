package internal

import "strings"

// Email localization. Emails are rendered server-side by the worker, which
// has no access to the client's UI locale (web detects it client-side per
// decisions §108; mobile keeps it per-device, not DB-synced, per §113). So
// the user's chosen language is mirrored into user_settings.prefs.locale by
// the clients (decisions §120), and the worker reads it here. The supported
// set mirrors the web/mobile i18n catalogues: en/de/fr/es/ja/pt-BR.
//
// Unknown or absent locale → English. Unknown template key → the English
// "default" entry. This is the worker's mirror of apps/web/src/lib/i18n and
// the mobile ARB catalogues; emailCatalogueParity_test.go pins that every
// locale carries every key.

// emailStrings is the localizable copy for one email template.
type emailStrings struct {
	subject   string
	preheader string
	heading   string
	cta       string
	body      []string
}

// emailShared is the per-locale copy shared across templates.
type emailShared struct {
	footerNotification    string // "why you're receiving this" for notification mail
	footerWelcome         string // ditto for the welcome
	footerTransactional   string // service-message footer for billing/account lifecycle mail
	managePrefsLabel      string // HTML footer link text
	managePrefsTextPrefix string // plain-text footer prefix before the URL
}

var emailLocales = []string{"en", "de", "fr", "es", "ja", "pt-BR"}

// normalizeEmailLocale maps an arbitrary BCP-47-ish tag to one of the
// supported locales, else "en". Region variants collapse to their base
// language (de-DE → de); Portuguese collapses to pt-BR (the only pt we
// ship).
func normalizeEmailLocale(tag string) string {
	t := strings.ToLower(strings.TrimSpace(tag))
	if t == "" {
		return "en"
	}
	if strings.HasPrefix(t, "pt") {
		return "pt-BR"
	}
	base := t
	if i := strings.IndexAny(t, "-_"); i >= 0 {
		base = t[:i]
	}
	switch base {
	case "en", "de", "fr", "es", "ja":
		return base
	default:
		return "en"
	}
}

// localeFromPrefs reads the email locale out of the user_settings.prefs bag.
func localeFromPrefs(prefs map[string]interface{}) string {
	if v, ok := prefs["locale"].(string); ok {
		return normalizeEmailLocale(v)
	}
	return "en"
}

// keyForKind collapses notification kinds to a catalogue key (comment_reply
// reuses the comment copy).
func keyForKind(kind string) string {
	if kind == "comment_reply" {
		return "comment"
	}
	return kind
}

// lookupEmailStrings resolves (locale, key) with English + "default"
// fallbacks so a missing translation never produces a blank email.
func lookupEmailStrings(locale, key string) emailStrings {
	if loc, ok := emailCatalogue[locale]; ok {
		if s, ok := loc[key]; ok {
			return s
		}
	}
	if s, ok := emailCatalogue["en"][key]; ok {
		return s
	}
	return emailCatalogue["en"]["default"]
}

func lookupEmailShared(locale string) emailShared {
	if s, ok := emailSharedByLocale[locale]; ok {
		return s
	}
	return emailSharedByLocale["en"]
}

var emailSharedByLocale = map[string]emailShared{
	"en": {
		footerNotification:    "You're receiving this because of your notification settings.",
		footerWelcome:         "You're receiving this because you just created a Threkir account.",
		footerTransactional:   "This is a service message about your Threkir account.",
		managePrefsLabel:      "Manage email preferences",
		managePrefsTextPrefix: "Manage your email preferences:",
	},
	"de": {
		footerNotification:    "Du erhältst diese E-Mail aufgrund deiner Benachrichtigungseinstellungen.",
		footerWelcome:         "Du erhältst diese E-Mail, weil du gerade ein Threkir-Konto erstellt hast.",
		footerTransactional:   "Dies ist eine Service-Nachricht zu deinem Threkir-Konto.",
		managePrefsLabel:      "E-Mail-Einstellungen verwalten",
		managePrefsTextPrefix: "Verwalte deine E-Mail-Einstellungen:",
	},
	"fr": {
		footerNotification:    "Vous recevez cet e-mail en raison de vos paramètres de notification.",
		footerWelcome:         "Vous recevez cet e-mail car vous venez de créer un compte Threkir.",
		footerTransactional:   "Ceci est un message de service concernant votre compte Threkir.",
		managePrefsLabel:      "Gérer les préférences e-mail",
		managePrefsTextPrefix: "Gérez vos préférences e-mail :",
	},
	"es": {
		footerNotification:    "Recibes este correo por tus ajustes de notificaciones.",
		footerWelcome:         "Recibes este correo porque acabas de crear una cuenta de Threkir.",
		footerTransactional:   "Este es un mensaje de servicio sobre tu cuenta de Threkir.",
		managePrefsLabel:      "Gestionar preferencias de correo",
		managePrefsTextPrefix: "Gestiona tus preferencias de correo:",
	},
	"ja": {
		footerNotification:    "通知設定に基づいてこのメールをお送りしています。",
		footerWelcome:         "Threkir アカウントを作成されたため、このメールをお送りしています。",
		footerTransactional:   "これは Threkir アカウントに関するサービス通知です。",
		managePrefsLabel:      "メール設定を管理",
		managePrefsTextPrefix: "メール設定の管理:",
	},
	"pt-BR": {
		footerNotification:    "Você está recebendo este e-mail por causa das suas configurações de notificação.",
		footerWelcome:         "Você está recebendo este e-mail porque acabou de criar uma conta no Threkir.",
		footerTransactional:   "Esta é uma mensagem de serviço sobre a sua conta no Threkir.",
		managePrefsLabel:      "Gerenciar preferências de e-mail",
		managePrefsTextPrefix: "Gerencie suas preferências de e-mail:",
	},
}

// emailCatalogue[locale][key] — key is a notification kind, "welcome", or
// "default". Keep every locale's key set identical to en (parity test).
var emailCatalogue = map[string]map[string]emailStrings{
	"en": {
		"event_reminder": {"Reminder: your event is coming up", "An event you said you're going to starts soon.", "Your event is coming up", "View event", []string{"You have an event starting soon that you said you're going to.", "Open it for the meet point, timing, and who else is going."}},
		"event_cancel":   {"An event you were going to was cancelled", "One of your RSVP'd events has been called off.", "Event cancelled", "View event", []string{"An event you'd RSVP'd to has been cancelled.", "Open it for the organiser's note and any replacement plans."}},
		"plan_update":    {"Your training plan was updated", "Your coach changed your plan.", "Your training plan changed", "View training", []string{"Your coach made a change to your training plan."}},
		"message":        {"You have a new message", "Someone sent you a direct message.", "New message", "Read message", []string{"You have a new direct message on Threkir."}},
		"event_rsvp":     {"New RSVP to your event", "Someone's going to your event.", "New RSVP", "View event", []string{"Someone RSVP'd to an event you organise."}},
		"club_post":      {"New post in your club", "There's a new post in one of your clubs.", "New club post", "View club", []string{"There's a new post in one of your clubs."}},
		"run_completed":  {"A runner you follow finished a run", "See their latest run.", "New run from someone you follow", "View run", []string{"Someone you follow just completed a run."}},
		"kudos":          {"You got kudos", "Someone gave kudos to your run.", "You got kudos", "View run", []string{"Someone gave kudos to your run."}},
		"comment":        {"New comment on a run", "Someone commented on a run.", "New comment", "View run", []string{"There's a new comment on a run."}},
		"follow":         {"You have a new follower", "Someone started following you.", "New follower", "View profile", []string{"Someone started following you on Threkir."}},
		"welcome":        {"Welcome to Threkir", "You're all set — here's how to get started.", "Welcome to Threkir", "Open Threkir", []string{"Thanks for signing up. You're all set to record your first run, build routes, and follow friends.", "Hit the button below to get going."}},
		"pro_welcome":    {"You're now on Threkir Pro", "Thanks for upgrading — here's what's unlocked.", "Welcome to Threkir Pro", "Explore Pro", []string{"Thanks for upgrading — your Threkir Pro features are now active.", "Dive into advanced training insights, the AI coach, and more."}},
		"payment_failed": {"There was a problem with your payment", "Update your payment method to keep Threkir Pro.", "Payment issue", "Update payment", []string{"We couldn't process your latest Threkir Pro payment.", "Update your payment method to keep your Pro features — your subscription may be paused until it's resolved."}},
		"default":        {"You have a new notification", "You have a new notification on Threkir.", "New notification", "Open Threkir", []string{"You have a new notification on Threkir."}},
	},
	"de": {
		"event_reminder": {"Erinnerung: dein Event steht bevor", "Ein Event, für das du zugesagt hast, beginnt bald.", "Dein Event steht bevor", "Event ansehen", []string{"Ein Event, für das du zugesagt hast, beginnt bald.", "Öffne es für Treffpunkt, Uhrzeit und wer noch dabei ist."}},
		"event_cancel":   {"Ein Event, zu dem du wolltest, wurde abgesagt", "Eines deiner zugesagten Events wurde abgesagt.", "Event abgesagt", "Event ansehen", []string{"Ein Event, für das du zugesagt hattest, wurde abgesagt.", "Öffne es für die Notiz der Organisation und mögliche Ersatztermine."}},
		"plan_update":    {"Dein Trainingsplan wurde aktualisiert", "Dein Coach hat deinen Plan geändert.", "Dein Trainingsplan hat sich geändert", "Training ansehen", []string{"Dein Coach hat eine Änderung an deinem Trainingsplan vorgenommen."}},
		"message":        {"Du hast eine neue Nachricht", "Jemand hat dir eine Direktnachricht geschickt.", "Neue Nachricht", "Nachricht lesen", []string{"Du hast eine neue Direktnachricht auf Threkir."}},
		"event_rsvp":     {"Neue Zusage für dein Event", "Jemand kommt zu deinem Event.", "Neue Zusage", "Event ansehen", []string{"Jemand hat für ein Event zugesagt, das du organisierst."}},
		"club_post":      {"Neuer Beitrag in deinem Club", "Es gibt einen neuen Beitrag in einem deiner Clubs.", "Neuer Club-Beitrag", "Club ansehen", []string{"Es gibt einen neuen Beitrag in einem deiner Clubs."}},
		"run_completed":  {"Eine Person, der du folgst, hat einen Lauf beendet", "Sieh dir ihren neuesten Lauf an.", "Neuer Lauf von jemandem, dem du folgst", "Lauf ansehen", []string{"Eine Person, der du folgst, hat gerade einen Lauf abgeschlossen."}},
		"kudos":          {"Du hast Kudos erhalten", "Jemand hat deinem Lauf Kudos gegeben.", "Du hast Kudos erhalten", "Lauf ansehen", []string{"Jemand hat deinem Lauf Kudos gegeben."}},
		"comment":        {"Neuer Kommentar zu einem Lauf", "Jemand hat einen Lauf kommentiert.", "Neuer Kommentar", "Lauf ansehen", []string{"Es gibt einen neuen Kommentar zu einem Lauf."}},
		"follow":         {"Du hast einen neuen Follower", "Jemand folgt dir jetzt.", "Neuer Follower", "Profil ansehen", []string{"Jemand folgt dir jetzt auf Threkir."}},
		"welcome":        {"Willkommen bei Threkir", "Alles bereit — so legst du los.", "Willkommen bei Threkir", "Threkir öffnen", []string{"Danke für deine Anmeldung. Du kannst jetzt deinen ersten Lauf aufzeichnen, Routen erstellen und Freunden folgen.", "Tippe auf den Button, um loszulegen."}},
		"pro_welcome":    {"Du bist jetzt bei Threkir Pro", "Danke fürs Upgrade — das ist jetzt freigeschaltet.", "Willkommen bei Threkir Pro", "Pro entdecken", []string{"Danke fürs Upgrade — deine Threkir-Pro-Funktionen sind jetzt aktiv.", "Entdecke erweiterte Trainingsanalysen, den KI-Coach und mehr."}},
		"payment_failed": {"Problem mit deiner Zahlung", "Aktualisiere deine Zahlungsmethode, um Threkir Pro zu behalten.", "Zahlungsproblem", "Zahlung aktualisieren", []string{"Wir konnten deine letzte Zahlung für Threkir Pro nicht verarbeiten.", "Aktualisiere deine Zahlungsmethode, um deine Pro-Funktionen zu behalten — dein Abo wird sonst möglicherweise pausiert."}},
		"default":        {"Du hast eine neue Benachrichtigung", "Du hast eine neue Benachrichtigung auf Threkir.", "Neue Benachrichtigung", "Threkir öffnen", []string{"Du hast eine neue Benachrichtigung auf Threkir."}},
	},
	"fr": {
		"event_reminder": {"Rappel : votre événement approche", "Un événement auquel vous avez répondu présent commence bientôt.", "Votre événement approche", "Voir l'événement", []string{"Un événement auquel vous avez répondu présent commence bientôt.", "Ouvrez-le pour le point de rendez-vous, l'horaire et les autres participants."}},
		"event_cancel":   {"Un événement prévu a été annulé", "Un des événements auxquels vous étiez inscrit a été annulé.", "Événement annulé", "Voir l'événement", []string{"Un événement auquel vous vous étiez inscrit a été annulé.", "Ouvrez-le pour le message de l'organisateur et d'éventuelles dates de remplacement."}},
		"plan_update":    {"Votre plan d'entraînement a été mis à jour", "Votre coach a modifié votre plan.", "Votre plan d'entraînement a changé", "Voir l'entraînement", []string{"Votre coach a apporté une modification à votre plan d'entraînement."}},
		"message":        {"Vous avez un nouveau message", "Quelqu'un vous a envoyé un message direct.", "Nouveau message", "Lire le message", []string{"Vous avez un nouveau message direct sur Threkir."}},
		"event_rsvp":     {"Nouvelle réponse à votre événement", "Quelqu'un participe à votre événement.", "Nouvelle réponse", "Voir l'événement", []string{"Quelqu'un a répondu présent à un événement que vous organisez."}},
		"club_post":      {"Nouvelle publication dans votre club", "Il y a une nouvelle publication dans l'un de vos clubs.", "Nouvelle publication de club", "Voir le club", []string{"Il y a une nouvelle publication dans l'un de vos clubs."}},
		"run_completed":  {"Une personne que vous suivez a terminé une course", "Découvrez sa dernière course.", "Nouvelle course d'une personne que vous suivez", "Voir la course", []string{"Une personne que vous suivez vient de terminer une course."}},
		"kudos":          {"Vous avez reçu des kudos", "Quelqu'un a donné des kudos à votre course.", "Vous avez reçu des kudos", "Voir la course", []string{"Quelqu'un a donné des kudos à votre course."}},
		"comment":        {"Nouveau commentaire sur une course", "Quelqu'un a commenté une course.", "Nouveau commentaire", "Voir la course", []string{"Il y a un nouveau commentaire sur une course."}},
		"follow":         {"Vous avez un nouvel abonné", "Quelqu'un s'est abonné à vous.", "Nouvel abonné", "Voir le profil", []string{"Quelqu'un s'est abonné à vous sur Threkir."}},
		"welcome":        {"Bienvenue sur Threkir", "Tout est prêt — voici comment commencer.", "Bienvenue sur Threkir", "Ouvrir Threkir", []string{"Merci de votre inscription. Vous pouvez enregistrer votre première course, créer des itinéraires et suivre des amis.", "Appuyez sur le bouton pour commencer."}},
		"pro_welcome":    {"Vous êtes maintenant sur Threkir Pro", "Merci pour la mise à niveau — voici ce qui est débloqué.", "Bienvenue sur Threkir Pro", "Découvrir Pro", []string{"Merci pour la mise à niveau — vos fonctionnalités Threkir Pro sont maintenant actives.", "Profitez des analyses d'entraînement avancées, du coach IA et plus encore."}},
		"payment_failed": {"Un problème avec votre paiement", "Mettez à jour votre moyen de paiement pour conserver Threkir Pro.", "Problème de paiement", "Mettre à jour le paiement", []string{"Nous n'avons pas pu traiter votre dernier paiement Threkir Pro.", "Mettez à jour votre moyen de paiement pour conserver vos fonctionnalités Pro — votre abonnement pourrait être suspendu en attendant."}},
		"default":        {"Vous avez une nouvelle notification", "Vous avez une nouvelle notification sur Threkir.", "Nouvelle notification", "Ouvrir Threkir", []string{"Vous avez une nouvelle notification sur Threkir."}},
	},
	"es": {
		"event_reminder": {"Recordatorio: tu evento se acerca", "Un evento al que confirmaste asistencia empieza pronto.", "Tu evento se acerca", "Ver evento", []string{"Tienes un evento que empieza pronto y al que confirmaste asistencia.", "Ábrelo para ver el punto de encuentro, la hora y quién más va."}},
		"event_cancel":   {"Se canceló un evento al que ibas", "Uno de los eventos a los que te apuntaste se ha cancelado.", "Evento cancelado", "Ver evento", []string{"Se ha cancelado un evento al que te habías apuntado.", "Ábrelo para ver la nota del organizador y posibles fechas alternativas."}},
		"plan_update":    {"Tu plan de entrenamiento se actualizó", "Tu entrenador cambió tu plan.", "Tu plan de entrenamiento cambió", "Ver entrenamiento", []string{"Tu entrenador hizo un cambio en tu plan de entrenamiento."}},
		"message":        {"Tienes un mensaje nuevo", "Alguien te envió un mensaje directo.", "Mensaje nuevo", "Leer mensaje", []string{"Tienes un nuevo mensaje directo en Threkir."}},
		"event_rsvp":     {"Nueva confirmación para tu evento", "Alguien va a tu evento.", "Nueva confirmación", "Ver evento", []string{"Alguien confirmó asistencia a un evento que organizas."}},
		"club_post":      {"Nueva publicación en tu club", "Hay una nueva publicación en uno de tus clubes.", "Nueva publicación de club", "Ver club", []string{"Hay una nueva publicación en uno de tus clubes."}},
		"run_completed":  {"Alguien a quien sigues terminó una carrera", "Mira su última carrera.", "Nueva carrera de alguien a quien sigues", "Ver carrera", []string{"Alguien a quien sigues acaba de completar una carrera."}},
		"kudos":          {"Recibiste kudos", "Alguien le dio kudos a tu carrera.", "Recibiste kudos", "Ver carrera", []string{"Alguien le dio kudos a tu carrera."}},
		"comment":        {"Nuevo comentario en una carrera", "Alguien comentó una carrera.", "Nuevo comentario", "Ver carrera", []string{"Hay un nuevo comentario en una carrera."}},
		"follow":         {"Tienes un nuevo seguidor", "Alguien empezó a seguirte.", "Nuevo seguidor", "Ver perfil", []string{"Alguien empezó a seguirte en Threkir."}},
		"welcome":        {"Te damos la bienvenida a Threkir", "Todo listo: así puedes empezar.", "Te damos la bienvenida a Threkir", "Abrir Threkir", []string{"Gracias por registrarte. Ya puedes registrar tu primera carrera, crear rutas y seguir a amigos.", "Pulsa el botón para empezar."}},
		"pro_welcome":    {"Ya tienes Threkir Pro", "Gracias por mejorar tu plan: esto es lo que se desbloquea.", "Te damos la bienvenida a Threkir Pro", "Descubrir Pro", []string{"Gracias por mejorar tu plan: tus funciones de Threkir Pro ya están activas.", "Descubre los análisis de entrenamiento avanzados, el entrenador con IA y mucho más."}},
		"payment_failed": {"Hubo un problema con tu pago", "Actualiza tu método de pago para mantener Threkir Pro.", "Problema con el pago", "Actualizar pago", []string{"No pudimos procesar tu último pago de Threkir Pro.", "Actualiza tu método de pago para mantener tus funciones Pro: tu suscripción podría pausarse hasta resolverlo."}},
		"default":        {"Tienes una notificación nueva", "Tienes una notificación nueva en Threkir.", "Notificación nueva", "Abrir Threkir", []string{"Tienes una notificación nueva en Threkir."}},
	},
	"ja": {
		"event_reminder": {"リマインダー：イベントがもうすぐ始まります", "参加予定のイベントがまもなく始まります。", "イベントがもうすぐ始まります", "イベントを見る", []string{"参加予定のイベントがまもなく始まります。", "集合場所・時間・参加者を確認しましょう。"}},
		"event_cancel":   {"参加予定だったイベントが中止されました", "参加予定だったイベントの1つが中止になりました。", "イベント中止", "イベントを見る", []string{"参加予定だったイベントが中止されました。", "主催者からのお知らせや代替予定を確認しましょう。"}},
		"plan_update":    {"トレーニングプランが更新されました", "コーチがプランを変更しました。", "トレーニングプランが変更されました", "トレーニングを見る", []string{"コーチがあなたのトレーニングプランを変更しました。"}},
		"message":        {"新しいメッセージがあります", "ダイレクトメッセージが届きました。", "新しいメッセージ", "メッセージを読む", []string{"Threkir に新しいダイレクトメッセージが届いています。"}},
		"event_rsvp":     {"あなたのイベントに新しい参加表明", "あなたのイベントに参加する人がいます。", "新しい参加表明", "イベントを見る", []string{"あなたが主催するイベントに参加表明がありました。"}},
		"club_post":      {"クラブに新しい投稿があります", "参加中のクラブに新しい投稿があります。", "新しいクラブ投稿", "クラブを見る", []string{"参加中のクラブの1つに新しい投稿があります。"}},
		"run_completed":  {"フォロー中のランナーがランを完了しました", "最新のランを見る。", "フォロー中の人の新しいラン", "ランを見る", []string{"フォロー中の人がランを完了しました。"}},
		"kudos":          {"称賛（kudos）が届きました", "あなたのランに称賛が届きました。", "称賛（kudos）が届きました", "ランを見る", []string{"あなたのランに称賛（kudos）が届きました。"}},
		"comment":        {"ランに新しいコメント", "ランにコメントが付きました。", "新しいコメント", "ランを見る", []string{"ランに新しいコメントが付きました。"}},
		"follow":         {"新しいフォロワーがいます", "あなたをフォローした人がいます。", "新しいフォロワー", "プロフィールを見る", []string{"Threkir であなたをフォローした人がいます。"}},
		"welcome":        {"Threkir へようこそ", "準備完了です。さっそく始めましょう。", "Threkir へようこそ", "Threkir を開く", []string{"ご登録ありがとうございます。最初のランの記録、ルート作成、友達のフォローがすぐに始められます。", "下のボタンから始めましょう。"}},
		"pro_welcome":    {"Threkir Pro をご利用いただけます", "アップグレードありがとうございます。使える機能はこちら。", "Threkir Pro へようこそ", "Pro を見る", []string{"アップグレードありがとうございます。Threkir Pro の機能が有効になりました。", "高度なトレーニング分析や AI コーチなどをぜひお試しください。"}},
		"payment_failed": {"お支払いに問題がありました", "Threkir Pro を継続するにはお支払い方法を更新してください。", "お支払いの問題", "支払いを更新", []string{"最近の Threkir Pro のお支払いを処理できませんでした。", "Pro 機能を継続するにはお支払い方法を更新してください。解決まで購読が一時停止される場合があります。"}},
		"default":        {"新しい通知があります", "Threkir に新しい通知があります。", "新しい通知", "Threkir を開く", []string{"Threkir に新しい通知があります。"}},
	},
	"pt-BR": {
		"event_reminder": {"Lembrete: seu evento está chegando", "Um evento que você confirmou presença começa em breve.", "Seu evento está chegando", "Ver evento", []string{"Você tem um evento que começa em breve e que você confirmou presença.", "Abra para ver o ponto de encontro, o horário e quem mais vai."}},
		"event_cancel":   {"Um evento que você ia foi cancelado", "Um dos eventos que você confirmou foi cancelado.", "Evento cancelado", "Ver evento", []string{"Um evento que você havia confirmado foi cancelado.", "Abra para ver a nota do organizador e possíveis datas alternativas."}},
		"plan_update":    {"Seu plano de treino foi atualizado", "Seu treinador alterou seu plano.", "Seu plano de treino mudou", "Ver treino", []string{"Seu treinador fez uma alteração no seu plano de treino."}},
		"message":        {"Você tem uma nova mensagem", "Alguém te enviou uma mensagem direta.", "Nova mensagem", "Ler mensagem", []string{"Você tem uma nova mensagem direta no Threkir."}},
		"event_rsvp":     {"Nova confirmação no seu evento", "Alguém vai ao seu evento.", "Nova confirmação", "Ver evento", []string{"Alguém confirmou presença em um evento que você organiza."}},
		"club_post":      {"Nova publicação no seu clube", "Há uma nova publicação em um dos seus clubes.", "Nova publicação do clube", "Ver clube", []string{"Há uma nova publicação em um dos seus clubes."}},
		"run_completed":  {"Alguém que você segue concluiu uma corrida", "Veja a corrida mais recente.", "Nova corrida de alguém que você segue", "Ver corrida", []string{"Alguém que você segue acabou de concluir uma corrida."}},
		"kudos":          {"Você recebeu kudos", "Alguém deu kudos para a sua corrida.", "Você recebeu kudos", "Ver corrida", []string{"Alguém deu kudos para a sua corrida."}},
		"comment":        {"Novo comentário em uma corrida", "Alguém comentou em uma corrida.", "Novo comentário", "Ver corrida", []string{"Há um novo comentário em uma corrida."}},
		"follow":         {"Você tem um novo seguidor", "Alguém começou a seguir você.", "Novo seguidor", "Ver perfil", []string{"Alguém começou a seguir você no Threkir."}},
		"welcome":        {"Bem-vindo ao Threkir", "Tudo pronto — veja como começar.", "Bem-vindo ao Threkir", "Abrir Threkir", []string{"Obrigado por se cadastrar. Tudo pronto para registrar sua primeira corrida, criar rotas e seguir amigos.", "Toque no botão para começar."}},
		"pro_welcome":    {"Agora você tem o Threkir Pro", "Obrigado por fazer o upgrade — veja o que foi liberado.", "Bem-vindo ao Threkir Pro", "Explorar o Pro", []string{"Obrigado por fazer o upgrade — seus recursos do Threkir Pro já estão ativos.", "Aproveite as análises de treino avançadas, o treinador com IA e muito mais."}},
		"payment_failed": {"Houve um problema com seu pagamento", "Atualize sua forma de pagamento para manter o Threkir Pro.", "Problema no pagamento", "Atualizar pagamento", []string{"Não conseguimos processar seu último pagamento do Threkir Pro.", "Atualize sua forma de pagamento para manter seus recursos Pro — sua assinatura pode ser pausada até a resolução."}},
		"default":        {"Você tem uma nova notificação", "Você tem uma nova notificação no Threkir.", "Nova notificação", "Abrir Threkir", []string{"Você tem uma nova notificação no Threkir."}},
	},
}
