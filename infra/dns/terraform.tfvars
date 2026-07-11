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
email_auth_records = {}
