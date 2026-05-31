# Age of consent (GDPR Art 8)

GDPR Art 8 sets the age below which a child cannot consent to information-society services without parental authorisation. The default is 16 but each member state can lower it to 13. UK GDPR sets it at 13.

**Status**: scaffold + recommendation. The product enforces a single self-declared minimum age at signup (16+ today after the age-gate change). Going below 16 in any member state requires parental-consent flow which we do not implement.

## Per-jurisdiction age

| Member state | Age of consent | Source |
|---|---|---|
| Belgium | 13 | Loi du 30 juillet 2018 |
| Bulgaria | 14 | LPDP |
| Cyprus | 14 | Law 125(I)/2018 |
| Italy | 14 | D.Lgs. 196/2003 as amended |
| Lithuania | 14 | Asmens duomenų teisinės apsaugos įstatymas |
| Slovenia | 14 | ZVOP-2 |
| Spain | 14 | Ley Orgánica 3/2018 |
| Austria | 14 | DSG §4(4) |
| Czech Republic | 15 | Zákon č. 110/2019 |
| France | 15 | LIL §45 |
| Greece | 15 | Law 4624/2019 |
| Croatia | 16 | ZPOP |
| Denmark | 13 | Databeskyttelsesloven |
| Estonia | 13 | Isikuandmete kaitse seadus |
| Finland | 13 | Tietosuojalaki |
| Latvia | 13 | Personas datu apstrādes likums |
| Malta | 13 | Data Protection Act, Subsidiary Legislation 586.10 |
| Poland | 16 | UODO |
| Portugal | 13 | Lei 58/2019 |
| Sweden | 13 | DSL |
| **Default (no opt-down)** | **16** | GDPR Art 8(1) |
| **United Kingdom** | **13** | UK GDPR + Data Protection Act 2018 |

Last-checked: 2024-09. Member states occasionally amend. Re-verify before publishing public copy.

## What the product does today

The signup form (`apps/web/src/routes/login/+page.svelte`) requires the user to **confirm they are 16 or older** before completing signup when in Sign Up mode. This was added alongside the international-compliance audits.

The 16+ floor is the most conservative single threshold: it satisfies every member state. It does mean we lock out 13-15 year olds in member states (UK, DE, FR, …) that permit them.

### Trade-off

| Approach | Effort | Coverage |
|---|---|---|
| Single 16+ floor (current) | Trivial | Loses 13-15 year olds globally |
| Per-country age based on IP | Medium (requires geo-IP lookup) | Plausible, but IP is unreliable |
| Per-country age based on declared country | Low | Self-declared, easy to bypass; legally fine if disclosed |
| Full parental-consent flow under 16 | High (separate signup flow + verification) | Maximises addressable market under-16 |

The default position is "single 16+ floor". Re-evaluate if the under-16 segment is strategically important.

## Children's safety + COPPA (US)

COPPA (US) sets the floor at 13 *for verifiable parental consent* on services directed to children. Our app is **not directed to children**:

- No characters or themes targeted at under-13s.
- Marketing copy emphasises distance + pace + training plan vocabulary — adult/teen-runner audience.
- We do not enrol schools or youth clubs.

We accordingly do not need COPPA's verifiable parental-consent mechanism, but we should still avoid collecting personal data from anyone we have actual knowledge is under our 16 minimum (which subsumes COPPA's under-13 floor). The 16+ signup confirmation handles this for direct signups; the gap is when a parent creates a shared device and a child uses it. The Privacy Policy § 8 now states this consistently: the floor is 16+, we don't knowingly collect from anyone under 16, and there's a parental-deletion channel (`privacy@threkir.com`) — aligned with the enforced signup gate (audit-findings 2026-05-30 Medium, age-gate inconsistency closed).

## Enforcement caveats

A self-declared age check is the industry minimum, not a real verification. Apple + Google both publish "Designed for Families" / "Made for Kids" tiers that require additional verification — we are not enrolled in those tiers.

The store age rating (Apple "4+" / Play "Everyone") should be honest:

- If the rating implies suitable-for-13+, the app must not contain content that would otherwise rate higher.
- Health data is generally not a rating-bumper, but verify against the current App Store rating questionnaire.
