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
}

var smsCatalogue = map[string]smsStrings{
	"en": {
		withLastSeen: "%s may be overdue on a run. Started %s, last seen %s. This can also be lost signal. Live progress: %s",
		noPing:       "%s may be overdue on a run. Started %s, no position received since. This can also be lost signal. Live progress: %s",
	},
	"de": {
		withLastSeen: "%s ist beim Laufen evtl. überfällig. Start %s, zuletzt gesehen %s. Kann auch fehlendes Signal sein. Live: %s",
		noPing:       "%s ist beim Laufen evtl. überfällig. Start %s, seitdem keine Position. Kann auch fehlendes Signal sein. Live: %s",
	},
	"fr": {
		withLastSeen: "%s a peut-être du retard sur une course. Départ %s, vu %s. Peut aussi être une perte de signal. Suivi : %s",
		noPing:       "%s a peut-être du retard sur une course. Départ %s, aucune position depuis. Peut aussi être une perte de signal. Suivi : %s",
	},
	"es": {
		withLastSeen: "%s puede ir con retraso en una carrera. Inicio %s, visto %s. También puede ser pérdida de señal. En directo: %s",
		noPing:       "%s puede ir con retraso en una carrera. Inicio %s, sin posición desde entonces. También puede ser pérdida de señal. En directo: %s",
	},
	"ja": {
		withLastSeen: "%s さんのランが遅れている可能性があります。開始 %s、最終位置 %s。電波が届いていない可能性もあります。ライブ: %s",
		noPing:       "%s さんのランが遅れている可能性があります。開始 %s、以降の位置情報なし。電波が届いていない可能性もあります。ライブ: %s",
	},
	"pt-BR": {
		withLastSeen: "%s pode estar atrasado(a) numa corrida. Início %s, visto %s. Também pode ser perda de sinal. Ao vivo: %s",
		noPing:       "%s pode estar atrasado(a) numa corrida. Início %s, sem posição desde então. Também pode ser perda de sinal. Ao vivo: %s",
	},
}

func lookupSmsStrings(locale string) smsStrings {
	if s, ok := smsCatalogue[locale]; ok {
		return s
	}
	return smsCatalogue["en"]
}

// renderSafetySms builds the localized SMS body for a safety_sms job. Returns
// ok=false for an unknown template. The only template today is "overdue"; the
// payload shape is channel-agnostic (same fields the email overdue path uses)
// so a future channel can reuse the scan's enqueue.
func renderSafetySms(p SafetySmsPayload, baseURL, locale string) (string, bool) {
	if p.Template != "overdue" {
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
	if p.LastSeenAt != "" {
		return fmt.Sprintf(s.withLastSeen, owner, formatTimeUTC(p.StartedAt), formatTimeUTC(p.LastSeenAt), link), true
	}
	return fmt.Sprintf(s.noPing, owner, formatTimeUTC(p.StartedAt), link), true
}
