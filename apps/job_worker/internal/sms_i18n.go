package internal

import (
	"fmt"
	"strings"
)

// SMS localization for the safety_sms escalation channel. Mirrors the email
// overdue copy but as a single short plain-text line — SMS has no HTML, no
// subject, and a tight length budget. Times + the live link ONLY, never
// coordinates (the /live page does the privacy-zone clipping). The owner-name
// fallback + the UTC time formatting are shared with the email path
// (lookupEmailShared / formatTimeUTC), so only the body sentences live here.
//
// smsCatalogueParity_test.go pins that every supported locale carries both
// variants, matching the email catalogue's locale set.
type smsStrings struct {
	// withLastSeen: owner, started-at, last-seen, live-link. Used when at
	// least one position ping landed.
	withLastSeen string
	// noPing: owner, started-at, live-link. Used when no ping ever arrived.
	noPing string
	// offRouteWithLastSeen / offRouteNoPing: the off_route template variants
	// (docs/features/safety.md) — the runner left their planned route rather
	// than going silent. Same owner / started-at / last-seen / live-link
	// placeholders as the overdue variants.
	offRouteWithLastSeen string
	offRouteNoPing       string
}

var smsCatalogue = map[string]smsStrings{
	"en": {
		withLastSeen:         "%s may be overdue on a run. Started %s, last seen %s. This can also be lost signal. Live progress: %s",
		noPing:               "%s may be overdue on a run. Started %s, no position received since. This can also be lost signal. Live progress: %s",
		offRouteWithLastSeen: "%s has gone off their planned route on a run. Started %s, last seen %s. Could be a detour or lost signal. Live: %s",
		offRouteNoPing:       "%s has gone off their planned route on a run. Started %s. Could be a detour or lost signal. Live: %s",
	},
	"de": {
		withLastSeen:         "%s ist beim Laufen evtl. überfällig. Start %s, zuletzt gesehen %s. Kann auch fehlendes Signal sein. Live: %s",
		noPing:               "%s ist beim Laufen evtl. überfällig. Start %s, seitdem keine Position. Kann auch fehlendes Signal sein. Live: %s",
		offRouteWithLastSeen: "%s ist beim Laufen von der geplanten Route abgekommen. Start %s, zuletzt gesehen %s. Kann Umweg oder Signalverlust sein. Live: %s",
		offRouteNoPing:       "%s ist beim Laufen von der geplanten Route abgekommen. Start %s. Kann Umweg oder Signalverlust sein. Live: %s",
	},
	"fr": {
		withLastSeen:         "%s a peut-être du retard sur une course. Départ %s, vu %s. Peut aussi être une perte de signal. Suivi : %s",
		noPing:               "%s a peut-être du retard sur une course. Départ %s, aucune position depuis. Peut aussi être une perte de signal. Suivi : %s",
		offRouteWithLastSeen: "%s a quitté son itinéraire prévu sur une course. Départ %s, vu %s. Détour ou perte de signal possible. Suivi : %s",
		offRouteNoPing:       "%s a quitté son itinéraire prévu sur une course. Départ %s. Détour ou perte de signal possible. Suivi : %s",
	},
	"es": {
		withLastSeen:         "%s puede ir con retraso en una carrera. Inicio %s, visto %s. También puede ser pérdida de señal. En directo: %s",
		noPing:               "%s puede ir con retraso en una carrera. Inicio %s, sin posición desde entonces. También puede ser pérdida de señal. En directo: %s",
		offRouteWithLastSeen: "%s se ha salido de su ruta prevista en una carrera. Inicio %s, visto %s. Puede ser un desvío o pérdida de señal. En directo: %s",
		offRouteNoPing:       "%s se ha salido de su ruta prevista en una carrera. Inicio %s. Puede ser un desvío o pérdida de señal. En directo: %s",
	},
	"ja": {
		withLastSeen:         "%s さんのランが遅れている可能性があります。開始 %s、最終位置 %s。電波が届いていない可能性もあります。ライブ: %s",
		noPing:               "%s さんのランが遅れている可能性があります。開始 %s、以降の位置情報なし。電波が届いていない可能性もあります。ライブ: %s",
		offRouteWithLastSeen: "%s さんがランで予定ルートを外れました。開始 %s、最終位置 %s。迂回や電波不良の可能性。ライブ: %s",
		offRouteNoPing:       "%s さんがランで予定ルートを外れました。開始 %s。迂回や電波不良の可能性。ライブ: %s",
	},
	"pt-BR": {
		withLastSeen:         "%s pode estar atrasado(a) numa corrida. Início %s, visto %s. Também pode ser perda de sinal. Ao vivo: %s",
		noPing:               "%s pode estar atrasado(a) numa corrida. Início %s, sem posição desde então. Também pode ser perda de sinal. Ao vivo: %s",
		offRouteWithLastSeen: "%s saiu da rota planejada numa corrida. Início %s, visto %s. Pode ser desvio ou perda de sinal. Ao vivo: %s",
		offRouteNoPing:       "%s saiu da rota planejada numa corrida. Início %s. Pode ser desvio ou perda de sinal. Ao vivo: %s",
	},
}

func lookupSmsStrings(locale string) smsStrings {
	if s, ok := smsCatalogue[locale]; ok {
		return s
	}
	return smsCatalogue["en"]
}

// renderSafetySms builds the localized SMS body for a safety_sms job. Returns
// ok=false for an unknown template. Templates: "overdue" (telemetry silence)
// and "off_route" (left the planned route). The payload shape is
// channel-agnostic (same fields the email path uses) so both reuse the same
// enqueue.
func renderSafetySms(p SafetySmsPayload, baseURL, locale string) (string, bool) {
	if p.Template != "overdue" && p.Template != "off_route" {
		return "", false
	}
	loc := normalizeEmailLocale(locale)
	owner := p.OwnerName
	if owner == "" {
		owner = lookupEmailShared(loc).safetyDefaultOwner
	}
	link := strings.TrimRight(baseURL, "/")
	if p.RunID != nil && *p.RunID != "" {
		link += "/live/" + *p.RunID
	}
	s := lookupSmsStrings(loc)
	withLastSeen, noPing := s.withLastSeen, s.noPing
	if p.Template == "off_route" {
		withLastSeen, noPing = s.offRouteWithLastSeen, s.offRouteNoPing
	}
	if p.LastSeenAt != "" {
		return fmt.Sprintf(withLastSeen, owner, formatTimeUTC(p.StartedAt), formatTimeUTC(p.LastSeenAt), link), true
	}
	return fmt.Sprintf(noPing, owner, formatTimeUTC(p.StartedAt), link), true
}
