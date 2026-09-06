# Data-subject rights — handling SOP

How each GDPR data-subject right is satisfied, and the operator runbook
for the two rights that have **no self-service product surface** today
(Art 18 restriction, Art 21 objection). Surfaced by audit-findings
2026-05-30 Medium.

**Status**: scaffold. Self-service paths (access/export/erasure/
rectification) are implemented in code; the Art 18/21 manual SOP below is
operator process, not a legal opinion. Counsel review before EU launch.

## Rights map

| Right | Article | How it's satisfied | Surface |
|---|---|---|---|
| Access / copy | 15 | Machine-readable export of personal-data tables + run-photo bytes + tracks, on both paths (`export-data/backup_spec.ts` + the job_worker `exportPersonalDataSpecs`/`buildBackupSpecs`). **Owner-FK gap closed (2026-06-20):** the export previously keyed most tables off a literal `user_id` column, so tables owned via a differently-named column were missing — `session_plans` (`author_id`), `event_orders` (`buyer_user_id`/`host_user_id`), `route_photos` (`owner_id`), and `event_pricing` (`event_id` → host). All four are now exported on both paths, and the completeness guard (`personal_data_export_guard_test.go`) was widened to key on ANY owner-style FK to `auth.users` (`user_id`/`author_id`/`owner_id`/`buyer_user_id`/`host_user_id`/`contact_user_id`), so the next such table can't slip past silently. Widening the guard also surfaced five pre-existing plain-`user_id` gaps now wired in too: `achievements`, `challenge_participants`, `challenge_badges`, `public_recaps`, and `route_conditions` (the user's own community route-condition reports, migration `20270215_001`). | Settings → "Export data" → the Go worker's queued rail (`POST /v1/export/jobs`, `GET /v1/export/jobs/latest`) |
| Portability | 20 | Same machine-readable export (JSON + GPX + zip); the owner-FK gap above is closed on both paths, and every table read pages past PostgREST's 1000-row cap — see [Export completeness](#export-completeness--paging-and-what-the-manifest-count-means) | as above |
| Rectification | 16 | Profile + preference edits; run title/notes edit | Settings, run detail |
| Erasure | 17 | Account deletion: FK cascade + mandatory Storage drain of every user-content bucket (`runs`, `run-photos`, `route-photos`, `club-photos`; best-effort `avatars`) + third-party deauth (Strava, Garmin placeholder, RevenueCat, FCM, Stripe Connect Express account) + audit log. **route-photos/club-photos drain gap closed 2026-07-03** (audit/storage) — buckets added after the original drain code shipped had retained photo bytes post-deletion. | Settings → Delete account (email re-entry challenge) → `delete-account` EF |
| Restriction | 18 | **No self-service toggle** — manual SOP below | operator |
| Objection | 21 | **No self-service toggle** — manual SOP below | operator |
| Withdraw consent | 7(3) | Disconnect integrations; **AI-features consent is self-service withdrawable** (Settings → Account → AI features consent → Withdraw, backed by the `withdraw_ai_disclosure_consent()` RPC — clears the whole record, `coach_consent_at` **and** `ai_disclosure_version`, after which every AI endpoint's 403 gate re-engages: the Coach and both AI route-assistant endpoints). **Mobile's withdrawal control was unreachable until 2026-08-09** — it rendered only when a consent read succeeded, and that read selected `coach_consent_at` directly off `user_profiles`, a column revoked from the `authenticated` grant since 20260707_001, so the read always errored and the tile never appeared (decisions § 573). The read now goes through `get_my_profile()`; web was unaffected. Telemetry opt-out in Settings | Settings (web **and** mobile) |

## Export completeness — paging, and what the manifest count means

**Paging guarantee (2026-08-18).** Every table the export reads is read
in full. PostgREST clamps a response to `db-max-rows` (1000 on Supabase)
and reports the truncation nowhere in the body — even an explicit
`limit=5000` comes back with 1000 rows — so until this was fixed a
runner past their thousandth run, photo, food-log row or gym set
received a silently short archive. Both paths (the Go worker's
queued rail, and the deprecated `export-data` Edge Function) now walk
1000-row pages until the server returns a short one, ordered by each
table's primary key so offset paging cannot repeat one row and skip
another.

**What `manifest.json` asserts.** Each entry in `counts` is the
**authoritative row count the database holds** for that section, not the
number of rows this archive happens to carry. So the completeness check
a data subject (or a regulator) runs is a real one: count the rows in
`food_log.json` and compare them to `counts.food_log`. Two fields make
any shortfall explicit:

- `complete` — `true` only when every section was read in full.
- `incomplete` — the sorted list of sections whose file is short of its
  count.

A section that failed part-way keeps the rows that were read and is
named in `incomplete`; it is never silently dropped, and never counted
as whole. The CSV and GPX formats carry the same signal in the endpoint's
JSON response (`count` / `total` / `complete`).

**Row completeness is not column completeness, so each format now
declares what it OMITS** ([decisions § 1171](../architecture/decisions.md),
closed 2026-09-04). Both transports used to read the run row through a
hand-written column list that nobody widened as columns were added, and
seven columns — `concluded_at`, `elevation_gain_m`, `race_listing_id` and
the four `fastest_*_s` PR times — reached neither `runs.csv` nor the
backup's `runs.json` (found the same day, § 1135). `manifest.json` could
not show it: it counts rows, and every row was present.

The direction is inverted now. Both rails select the whole table, and a
format states the columns it declines and why, so a column added to
`public.runs` reaches every archive without an edit:

- **`runs.csv`** declines `user_id` (the archive is the subject's own,
  and the id is theirs), `track_url` and `hr_series_url` (Storage keys
  inside the owner's folder, of no use to a reader of a CSV).
- **The backup archive's `runs.json`** declines `user_id` alone, so a
  restore can re-home the archive into another account.
- **The GPX zip's `runs.json`** is a manifest of what was exported rather
  than a restorable record, so beside `user_id` it declines both Storage
  paths — the GPX files are in the same archive — and `created_at` /
  `updated_at`.

Four guards hold it, and each fails on an omission that no longer names a
real column as well as on a column neither carried nor declined:
`TestExportRunProjectionCoversEveryRunsColumn` (the Go struct and the
Edge Function's `RUNS_SELECT` both mirror the generated table type),
`TestCSVCarriesEveryRunsColumnExceptTheOnesItDeclares` (which also
compares the two rails' declined sets against each other),
`TestRunsJsonProjectionsOmitOnlyWhatTheyDeclare` (driven off what a row
actually serialises to, not off the source), and
`TestExportRunRowMirrorsItsSelect`.

**Known bounds, stated rather than hidden — and they now differ per
rail.** The Edge Function streams; the Go worker does not yet. Whatever
bound applies, it is visible in the manifest.

*The `export-data` Edge Function has no row bounds at all* since
2026-08-21 ([decisions § 703](../architecture/decisions.md)). It streams
the archive into Storage through a chunked tus upload (6 MiB chunks) and
serialises each section page by page, so `MAX_RUNS` and
`EXPORT_ROW_CEILING` are deleted rather than raised. Its one remaining
bound is a genuine platform limit: the function is killed at 150 s, so
the builders run against an explicit 120 s budget and any section the
clock cuts short is named in `incomplete`. It also fails closed harder
than before — tus publishes the object only once the declared length
arrives, so a build that dies produces no artifact instead of a short
one.

A third cap turned up underneath both of them and had to move with
this: the artifacts were written to the `runs` Storage bucket, whose
per-object limit is 25 MB — on a full-history `backup` archive that is a
ceiling of *tens* of runs, enforced for `service_role` too, and it
surfaced as a failed upload rather than a short archive. Exports now
live in their own `exports` bucket (migration `20270602_001`, 5 GiB,
signed-URL-only, no `storage.objects` policies), which `delete-account`
drains and the 7-day `cleanup_stale_export_blobs` sweep covers.
**That sweep did not run.** storage-api installs a statement-level
`protect_objects_delete` trigger refusing a direct DELETE from
`storage.objects`, and it is present in the image both the CI-pinned and
the workstation CLI start — so the nightly job raised on every run, even
on a night with nothing stale, and the `data_export_jobs` expiry that
follows it in the same call never ran either. `20270703000002` sets the
documented escape GUC transaction-locally and makes the sweep verify its
own post-condition, so a blocked sweep fails loudly instead of reporting
the same zero a clean night reports ([decisions § 857](../architecture/decisions.md)).
**Measured, and the answer is no** ([decisions § 1049](../architecture/decisions.md)):
the sweep deletes `storage.objects` ROWS, that trigger exists because a
row delete is not an object delete, and the backing bytes are **not**
reaped. A probe uploaded through the real Storage API, aged past the
window and swept by the shipped `cleanup_stale_export_blobs()` loses its
row and stops being listable — and its bytes remain on the storage
backend with a matching `sha256`. Migration `20260927_001`'s comment
that "the actual blob bytes are reaped by the storage backend's
background sweeper once the row is gone" is wrong; there is no such
sweeper (no `pg_cron` job touches storage bytes, and the storage
container runs one server process and nothing else). **So the sweep
removes REACHABILITY, not the archive.** The other half of that
contrast is now measured too rather than inferred (2026-09-03): deleting
the same object through the **Storage API** does remove the backend file
— 1 file before, 0 after, on the same bucket in the same session — and
that is the path `delete-account`'s drain uses. So the two legs of the
export-artifact retention are two different guarantees: the account-
deletion leg erases the bytes, the nightly SQL leg does not.
[retention.md](retention.md) states them separately for that reason; it
had been claiming only the stronger one for both. Removing reachability
is still strictly better than the state § 857 replaced, where the sweep
deleted nothing at all, but no document may call it an Art 17 erasure. **The durable fix is half
built and cannot yet run** ([decisions § 1112](../architecture/decisions.md)):
the Go worker gained an `export_blob_reap` job kind that lists the
`exports` bucket and deletes through the Storage API — which removes the
bytes and the rows together, so the SQL row-delete becomes redundant
rather than something to sequence against — but `jobs_kind_chk` forbids
that kind, so nothing can enqueue it and `Worker.dispatch` deliberately
carries no case for it. **Until the four statements that finish it land
(a CHECK widening, an `enqueue_export_blob_reap()`, a `cron.schedule`
and the dispatch case, all in one commit), the state described above is
the state in production: the nightly path has never erased an export
archive's bytes, only its reachability.** That is filed with an owner
and its exact statements are written out rather than described.

**And a Storage-API reaper cannot recover what is already orphaned.**
§ 1049 counted 74 files across every bucket against 0 rows, including 20
export archives stamped nine days earlier. The reaper derives its
worklist by listing, the list API reads `storage.objects`, and those
rows are the ones the sweep already deleted — so every byte a past sweep
orphaned is invisible to it by construction. The reaper stops the pile
growing; it is not a remedy for the pile.

**The remedy this document used to name does not exist for this
project** ([decisions § 1173](../architecture/decisions.md), read out of
the shipped `storage-api:v1.62.5`). An **S3 lifecycle rule** was the
first half of it: on Supabase Cloud the storage backend bucket is
Supabase's, not ours, so there is no bucket to attach a rule to, and on a
self-hosted stack a prefix rule would take live objects with it — the
survivors are interleaved with live ones under the same prefixes. The
remedy on Cloud is a Supabase support request; on a stack the operator
owns, it is a diff of the raw backend against `storage.objects`. And the
orphan's backend key is `{bucket}/{name}<sep>{version}`, where `version`
is the column that went with the deleted row, so even an operator with
real backend credentials cannot compute an orphan's key from what the
database still knows: enumerating the backend is the only entry.

That also retracts § 1049's residual on its own measurement, which said
confirming the residue on Cloud "still means listing the bucket over the
S3-compatible endpoint". **That endpoint is a database query.**
`S3ProtocolHandler`'s `listObjectsV2` runs `SELECT ... FROM
storage.objects`, so it sees exactly what `list` sees — precisely the
rows the sweep deleted — and can neither confirm an orphan nor erase
one. The measurement itself stands: it was taken on the local `file`
backend, so what it proves is the MECHANISM.
**One bound is a deploy-time operator step, not code:** Supabase also
enforces a project-level upload limit (50 MB by default) and the
effective ceiling is the lower of the two, so until that is raised the
project setting is the honest bound whatever the bucket allows.

*The Go worker's queued rail, which production traffic uses, carries
neither cap either* since [decisions § 708](../architecture/decisions.md):
`MaxRunsPerExport = 5000` and `exportRowCeiling = 50_000` were both
consequences of the one `bytes.Buffer` the archive used to be assembled
in, and both are deleted. Every section is now read page by page and
serialised into the same chunked tus upload as it arrives, so a subject's
whole history is exported however deep it is.

Unlike the Edge Function, this rail has **no request clock** — it is a
long-lived Go process, not a 150 s function — so there is no wall-clock
budget and no `ExportBudget` equivalent. What remains is not a policy
choice:

- **The Storage object-size ceiling.** The `exports` bucket admits 5 GiB,
  but Supabase's project-level upload limit (50 MB by default) is the
  lower of the two, and storage-api enforces it for `service_role`. Past
  it the upload fails and the subject gets a 500 with **no artifact** —
  an error, never a short archive.
- **The client connection.** The caller holds the request open for the
  whole build, so their own timeout (or a disconnect) can end an export
  that would otherwise have completed. Closing that is the async `jobs`
  kind tracked in `followups.md`, which is a client-contract change
  rather than a server one.

**Corrected 2026-08-21, and it had been wrong on both rails since before
either cap mattered:** `profile.json` shipped as `null` and
`reports_against_me.json` was absent from every `backup` export, because
both rails projected columns `user_profiles` and `reports` do not have
(`bio`, `location`, `hr_zones`, `activity_default`, `privacy_default`,
and `resolved_at` for `reviewed_at`). PostgREST rejects the whole read
when any projected column is absent, and a failed section is tolerated by
design, so the shortfall appeared only as a log line. The three
prefs-bag columns were always exported separately as `settings_prefs`;
`bio` and `location` exist nowhere, so nothing was lost by dropping them.
Both rails now project only columns the generated row types contain, and
a test checks every backup projection and filter against those types
rather than against a list of known-bad names.

**Corrected 2026-08-31, and the same class one level down:** `user_profiles`
reaches the archive through `FetchExportProfile`'s enumerated projection and
through nothing else — it is not in `exportPersonalDataSpecs`, so the
table-level completeness guard never covered it. Eight columns were therefore
absent from every `backup` export: `handle`, `height_cm`, `onboarded_at` and
the four consent records (`terms_accepted_at`, `age_confirmed_at`,
`coach_consent_at`, `health_data_consent_at`) plus `ai_disclosure_version`.
`height_cm` is the one that mattered most: `withdraw_health_data_consent()`
clears `date_of_birth`, `gender` and `height_cm` as one Art 9 set
([decisions § 718](../architecture/decisions.md)), and the archive was
exporting two of the three. All eight are projected now, and
`personal_data_export_profile_guard_test.go` parses every `user_profiles`
column out of the migrations and fails the build unless each is either
projected or named in an exclusion list with its reason — the same shape the
table-level guard already had. Two are excluded: `tier_updated_event_ts` (the
internal webhook-ordering key for the tier columns that *are* exported) and
`shadow_hidden` (moderation state, controller-assigned; disclosure defeats the
auto-hide mechanism — CISO/counsel to confirm). The Edge Function twin's
`PROFILE_SELECT` is still the narrow list and needs the same mirror; the
queued Go rail is the only one either client reaches
([decisions § 724](../architecture/decisions.md)).

A subject who hits either cap, or the Edge Function's clock, has not
received everything, and the manifest says so. Art 20 is satisfied by
re-running or by an operator export. Giving the Go rail the same
streaming treatment — and then moving it to an async job so no client
connection is held open for a multi-gigabyte archive — is the remaining
durable fix and is tracked as a follow-up; because that rail has no
request clock, it is the one that can end up with no bound at all.

## Art 18 (restriction) + Art 21 (objection) — operator SOP

Until a "pause processing" product toggle exists, restriction/objection
requests are handled manually:

1. **Intake.** Request arrives at `privacy@threkir.com`. Log it (date,
   user id, right invoked, scope) in the breach/rights register.
2. **Verify identity** — match the requesting email to the account email;
   if unsure, send a confirmation link to the account email.
3. **Scope the restriction.** Most Art 18/21 requests target a specific
   processing purpose. The realistic levers today:
   - **Stop all AI processing** — the user can do this themselves:
     Settings → Account → AI features consent → Withdraw calls
     `withdraw_ai_disclosure_consent()`, which clears the versioned consent
     record (`coach_consent_at` + `ai_disclosure_version`); the coach handler
     and both AI route-assistant endpoints then return 403 until they
     re-consent. It is one record covering every AI feature, so withdrawal is
     all-or-nothing by design (migration `20270511_001`, decisions § 571). No
     operator action needed. Their prompts are not retained by us
     (provider-side ~30d, see [retention.md](retention.md)).
   - **Stop social/feed processing** — set the account's runs to private
     (`is_public = false`) and remove follow edges if requested.
   - **Stop marketing/telemetry** — flip the Sentry/telemetry opt-out.
   - **Full processing freeze** — if a true Art 18 "store but don't
     process" is required and no narrower lever fits, the conservative
     action is to suspend the account (block sign-in) while retaining the
     data, pending resolution. There is no automated suspend flag yet —
     this is a manual DB action by an operator with service-role access.
4. **Confirm** to the data subject within one month (Art 12(3)),
   describing what was restricted.
5. **Lift** the restriction only on the data subject's instruction or
   when the legal ground resolves; log the lift.

**Follow-up (tracked, not in this doc):** a first-class "pause my data
processing" account toggle + an `account_status` suspended flag would make
Art 18/21 self-service. Until then this manual SOP is the control.

## Records of Processing Activities (Art 30)

A single consolidated RoPA is **not yet assembled** — the inputs are
split across [sub-processors.md](sub-processors.md) (recipients/transfers),
[retention.md](retention.md) (storage periods), and [dpia.md](dpia.md)
(purposes + risk for the high-risk processing). Assembling `ropa.md` from
these is a documentation task for the controller-of-record before EU
launch; it needs the legal-entity identity (the same blocker as the
Privacy Policy controller field) so it isn't fabricated here.
