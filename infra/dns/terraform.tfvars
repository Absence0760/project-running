apex_domain = "threkir.com"

# Outbound-email sender authentication (Resend). Paste the records the
# provider shows under Domains → threkir.com after adding the domain.
# Names are relative to the apex. All values here are public DNS data.
#
# Typical Resend set (exact values are account-specific — do not copy
# these literals, use what the dashboard shows):
#
#   dkim  = { name = "resend._domainkey", type = "TXT", records = ["p=MIGf…"] }
#   spf   = { name = "send", type = "TXT", records = ["v=spf1 include:amazonses.com ~all"] }
#   mx    = { name = "send", type = "MX", records = ["10 feedback-smtp.us-east-1.amazonses.com"] }
#   dmarc = { name = "_dmarc", type = "TXT", records = ["v=DMARC1; p=none;"] }
#
# Gotcha: a TXT value longer than 255 chars (2048-bit DKIM keys) must be
# split into quoted chunks inside the one string: "chunkA\"\"chunkB".
#
# Two independent mail systems share this zone, and they do NOT collide:
#   - Resend (OUTBOUND app mail) lives on the `send.` subdomain.
#   - Migadu (INBOUND + human @threkir.com mailboxes) lives on the apex.
# DMARC is domain-wide — one `_dmarc` record governs both; do not add a
# second. The `p=none;` below stays until both Resend and Migadu have been
# authenticating for 48h+, then it can tighten to `p=quarantine;`.
#
# Migadu MX/SPF/DKIM-CNAME/autoconfig targets are fixed for all Migadu
# domains; only `migadu_verify` is account-specific — paste the token from
# admin.migadu.com → Domains → threkir.com before applying.
email_auth_records = {
  # ── Resend: outbound app mail (send.threkir.com) ──
  dkim  = { name = "resend._domainkey", type = "TXT", records = ["p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGHkD1n/X+qOK6ruohZLqEFw5KT1slmd7GFxA/jdIHH0jR1Pa1OrfrpQMXpQR+BoxxLdv6YdWVsHm0O0gQZltrnSSUpToOx7uh3asZS64TfsfzwTFSbQH0Dae1m5NDVHHBOUKiETMLwKFIRp/SgcTX5WwyWVEY8SCCfq/gkXKnywIDAQAB"] }
  spf   = { name = "send", type = "TXT", records = ["v=spf1 include:amazonses.com ~all"] }
  mx    = { name = "send", type = "MX", records = ["10 feedback-smtp.us-east-1.amazonses.com"] }
  dmarc = { name = "_dmarc", type = "TXT", records = ["v=DMARC1; p=none;"] }

  # ── Migadu: inbound + @threkir.com mailboxes (apex) ──
  # SPF + ownership-verify share one apex TXT record set (Route 53 keys a
  # record set by name+type, so both TXT strings live under one entry).
  #
  # The apex SPF authorizes BOTH senders because the app's envelope-from is
  # apex (smtp.ts issues `MAIL FROM:<noreply@threkir.com>`): spf.migadu.com
  # for Migadu, amazonses.com for the Resend/SES relay. Dropping the SES
  # include here would SPF-fail app mail if Resend ever forwards the apex
  # return-path unrewritten. (Resend's own send-subdomain SPF is separate,
  # above.) Keep this in sync with whichever relay `SMTP_HOST` points at.
  migadu_apex_txt   = { name = "", type = "TXT", records = ["v=spf1 include:spf.migadu.com include:amazonses.com -all", "hosted-email-verify=p8dxwnab"] }
  migadu_mx         = { name = "", type = "MX", records = ["10 aspmx1.migadu.com", "20 aspmx2.migadu.com"] }
  migadu_dkim1      = { name = "key1._domainkey", type = "CNAME", records = ["key1.threkir.com._domainkey.migadu.com."] }
  migadu_dkim2      = { name = "key2._domainkey", type = "CNAME", records = ["key2.threkir.com._domainkey.migadu.com."] }
  migadu_dkim3      = { name = "key3._domainkey", type = "CNAME", records = ["key3.threkir.com._domainkey.migadu.com."] }
  migadu_autoconfig = { name = "autoconfig", type = "CNAME", records = ["autoconfig.migadu.com."] }
}
