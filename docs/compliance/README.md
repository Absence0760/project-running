# Compliance docs

Operating docs that back the project's international-launch posture. The `/audit/*` commands under `.claude/commands/audit/` are the **runtime** checks; the docs here are what the auditor compares against.

| Doc | What it answers |
|---|---|
| [retention.md](retention.md) | How long do we keep each personal-data category? When does auto-deletion fire? |
| [sub-processors.md](sub-processors.md) | Every external service that touches user data — input to the Privacy Policy + GDPR Art 30 Record of Processing Activities |
| [dpia.md](dpia.md) | GDPR Art 35 Data Protection Impact Assessment for live-location + heart-rate tracking |
| [breach-runbook.md](breach-runbook.md) | 72-hour Art 33/34 notification flow — who calls what, in what order |
| [eu-representative.md](eu-representative.md) | Art 27 placeholder — required for non-EU controllers offering services to EU residents |
| [age-of-consent.md](age-of-consent.md) | Per-member-state age of consent (GDPR Art 8) + how the product enforces it |

## Status

Every doc here is a **scaffold** generated alongside the international-compliance audit infrastructure. None of these are legal advice. Before a real EU / UK launch, every doc needs:

1. Counsel review.
2. Fact-check against the actual deployed system (e.g. retention windows must match real cron jobs, not what the doc claims).
3. Sign-off by whoever the project's controller-of-record is.

When you fill in a value, delete the `TODO:` markers so the auditor stops flagging them.

## Quick links

- `docs/architecture/decisions.md §33` — privacy-zone clipping (the SECURITY DEFINER `clip_track_for_user` RPC; mandatory for non-owner track render)
- `docs/architecture/decisions.md §41` — OAuth tokens stored in Supabase Vault, not plaintext columns
- `apps/backend/CLAUDE.md` — Edge Function inventory + per-function env vars
- `apps/job_worker/CLAUDE.md` — Go service that owns `data-export` + `token-refresh` + `strava_event` + `live-hub`
