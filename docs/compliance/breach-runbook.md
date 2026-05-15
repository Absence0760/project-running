# Personal-data breach runbook

GDPR Art 33 requires notification to the supervisory authority within **72 hours** of becoming aware of a personal-data breach. Art 34 requires notification to affected data subjects when the breach is likely to result in a "high risk to rights and freedoms". The 72-hour clock is unforgiving — this runbook exists so the response doesn't have to be reinvented at 3am.

**Status**: scaffold. Walk through this end-to-end as a tabletop exercise before going live, and update with real contacts.

## Trigger

"Aware" means: a credible signal that personal data has been **disclosed**, **accessed without authorization**, **altered**, **lost**, or **destroyed**. Examples:

- A bug report shows another user's runs on /share/run/[id].
- A security researcher emails `security@<your-domain>` with a working PoC.
- A `git push` exposes a service-role key (see `/audit/secrets`).
- Supabase, Sentry, or AWS sends a breach notice via their DPA channel.

False positives are fine — start the runbook on any *credible* signal.

## Roles

| Role | Responsibilities | Default holder |
|---|---|---|
| **Incident commander (IC)** | Owns the response, signs off on each step | TODO: name + 24h contact |
| **Technical lead** | Triages the bug, contains, builds the fix | Engineering on-call |
| **Comms lead** | Drafts user notice, regulator notice, status-page update | TODO |
| **Legal** | Reviews regulator + user notices; advises on Art 34 risk threshold | TODO |
| **DPO** | Mandatory under Art 37 if appointed; supervisory liaison | TODO |
| **EU representative** | Required if no EU establishment (Art 27); first contact for EU regulators | TODO — see [eu-representative.md](eu-representative.md) |

## Hour-by-hour playbook

### Hour 0 — Detect

1. IC receives credible signal. **Log the signal** verbatim in a private incident channel (Slack / Signal). Timestamp matters for the 72-hour clock.
2. Page on-call engineering + comms + legal.
3. Open an internal incident doc (template TODO). Start the activity log.

### Hour 0–4 — Contain

4. Identify the affected system, data class, and approximate user count.
5. **Contain immediately**: revoke compromised credentials, take the affected endpoint offline if needed, freeze the suspect Storage bucket, block the leaking IP/CIDR.
6. Snapshot logs **before** rotating anything — preserve evidence (`apps/job_worker` logs on Fly, CloudFront logs in S3, Supabase Auth logs, Sentry events).
7. If the breach is ongoing (active exfil), engage AWS GuardDuty + Supabase support **immediately**.

### Hour 4–24 — Assess

8. Categorise the breach: confidentiality (read), integrity (alter), or availability (lose). Each maps to a different Art 33 risk weight.
9. Quantify scope:
   - How many users? Per country?
   - Which data categories (location? HR? email? auth tokens? card data — *never us*, but verify)?
   - Time window?
10. Run `/audit/secrets` + `/audit/rls` + `/audit/storage` to confirm scope of *related* exposure.
11. Decide: is Art 34 user-notification required? Threshold is "high risk to rights and freedoms":
    - **Yes** if location + identity together; credentials; financial; biometric.
    - **Probably yes** if the data is special category (Art 9 — HR, dob, gender).
    - **Possibly no** if pseudonymous + the data has low real-world impact (e.g. an anonymised run with no identity link).
12. **Document the decision** with reasoning. If you don't notify users, the regulator will ask why.

### Hour 24–48 — Notify

13. **Supervisory authority notice (Art 33)**. The lead supervisory authority is the one in the EU member state of our main establishment, or — if we have no EU establishment — the SA of any member state where affected data subjects live, contacted through our EU representative. UK: ICO. Form: <https://ico.org.uk/for-organisations/report-a-breach/personal-data-breach/>.

    Notice must include (Art 33(3)):
    - Nature of breach, categories + approximate counts of data subjects + records.
    - DPO / EU rep contact.
    - Likely consequences.
    - Measures taken or proposed.

    If the picture isn't fully clear at 72h, file a **partial** notice on time and update later — that's explicitly allowed by Art 33(4).

14. **User notice (Art 34)** if triggered. Direct contact (email + in-app banner) unless that would require disproportionate effort, in which case public communication. Plain language, what happened, what data, what they should do (password reset, etc.), our contact.

### Hour 48–72 — Remediate

15. Fix the underlying bug. Add regression tests + invariant tests.
16. Update `/audit/*` to detect the class of bug going forward.
17. Run `/audit/all` to confirm no related findings.

### Post-incident

18. Postmortem within 7 days of resolution. Blameless. Output: 3–5 concrete remediations, dated.
19. If costs exceed our self-insured retention, notify cyber-insurance carrier (TODO: do we have one?).
20. Update this runbook based on what went wrong with the runbook itself.

## Data-subject contact channels

The Privacy Policy commits us to a per-data-subject-rights inbox. Both Art 33 (notice to authority) and Art 34 (notice to subjects) reference this address:

- **Privacy contact**: `privacy@<your-domain>` — TODO: register, route to legal + IC.
- **Security contact**: `security@<your-domain>` — register a `.well-known/security.txt` per RFC 9116.
- **DPO contact** (if appointed): TODO.

## Records

Art 33(5) requires us to keep a register of every breach, regardless of whether it was notifiable. Suggested fields:

| Field | Source |
|---|---|
| Incident id | Internal doc |
| First detection | IC log |
| Containment time | IC log |
| Notifiable to SA? | Decision in §11 above |
| SA notified at | Submission timestamp |
| User-notice issued? | §14 |
| Affected users | Quantified |
| Affected categories | Quantified |
| Root cause | Postmortem |
| Remediation | Postmortem |

Keep records for at least 5 years (general civil-liability statute of limitations across most member states; UK ICO recommends 6).

## Practice

Schedule a tabletop exercise at least annually. Pick a plausible scenario (signed URL leaked in Sentry breadcrumb; RLS regression on `runs` table; Strava token in git history). Walk this runbook end-to-end with everyone in the Roles table participating. Refine.
